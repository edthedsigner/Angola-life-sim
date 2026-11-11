extends Node
## WorldData (autoload) — lê shared/data/world.json e aplica AS MESMAS regras que server_python/world.py:
## zonas ("w" = rua, "b:<edifício>:<piso>" = interior), conversão píxel<->célula, células/arestas bloqueadas,
## pathfinding (A* 4-direções + suavização por linha de vista) e lista de interativos por zona.
## O servidor valida tudo o que o cliente pede; este ficheiro só serve para o cliente prever e desenhar.

const PATH := "res://shared/data/world.json"
const NEIGH := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const CLEARANCE := 0.17          # meia-largura do corpo do jogador em células (caixa 14x8 px)

var data: Dictionary = {}
var buildings: Dictionary = {}    # id -> definição (+ "idx")
var building_list: Array = []
var floors: Dictionary = {}       # id -> Array de pisos expandidos
var blocked_world: Dictionary = {}
var props: Array = []
var cmin := 0
var cmax := 0
var rmin := 0
var rmax := 0
var _blocked_cache: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldData: não consegui ler %s" % PATH)
		return
	data = parsed
	var g: Dictionary = data["grid"]
	cmin = int(g["cmin"]); cmax = int(g["cmax"]); rmin = int(g["rmin"]); rmax = int(g["rmax"])
	buildings.clear(); floors.clear(); blocked_world.clear(); props.clear(); building_list.clear(); _blocked_cache.clear()
	var idx := 0
	for braw in data["buildings"]:
		var b: Dictionary = (braw as Dictionary).duplicate(true)
		b["idx"] = idx
		idx += 1
		buildings[b["id"]] = b
		building_list.append(b)
		var fl_list: Array = []
		for i in (b["floors"] as Array).size():
			fl_list.append(_expand_floor(b, i, b["floors"][i]))
		floors[b["id"]] = fl_list
		for c in range(int(b["c0"]), int(b["c0"]) + int(b["w"])):
			for r in range(int(b["r0"]), int(b["r0"]) + int(b["d"])):
				blocked_world[Vector2i(c, r)] = true
	var rules: Dictionary = data.get("prop_rules", {})
	var n := 0
	for p in data.get("props", []):
		var rule: Dictionary = rules.get(p[0], {})
		props.append({"fid": "p%d" % n, "id": p[0], "x": int(p[1]), "y": int(p[2]), "r": 0, "actions": rule.get("actions", []), "prop": true})
		if rule.get("blocks", false):
			blocked_world[Vector2i(int(p[1]), int(p[2]))] = true
		n += 1

func _expand_floor(b: Dictionary, idx: int, fd: Dictionary) -> Dictionary:
	var w := int(fd["w"])
	var l := int(fd["l"])
	var walls := {}
	for x in w:
		walls["h:%d:0" % x] = "wall"
		walls["h:%d:%d" % [x, l]] = "wall"
	for y in l:
		walls["v:0:%d" % y] = "wall"
		walls["v:%d:%d" % [w, y]] = "wall"
	for spec in fd.get("walls", []):
		for t in range(int(spec[2]), int(spec[3])):
			walls[("h:%d:%d" % [t, int(spec[1])]) if spec[0] == "h" else ("v:%d:%d" % [int(spec[1]), t])] = "wall"
	for o in fd.get("openings", []):
		walls["%s:%d:%d" % [o[0], int(o[1]), int(o[2])]] = o[3]
	var exits := {}
	if idx == 0:
		for e in b.get("entrances", []):
			walls[e["edge"]] = "exit"
			exits[e["id"]] = e["edge"]
	var furn: Array = []
	var k := 0
	for f in fd.get("furniture", []):
		var ff: Dictionary = (f as Dictionary).duplicate(true)
		ff["fid"] = "f%d" % k
		k += 1
		furn.append(ff)
	return {"idx": idx, "w": w, "l": l, "name": fd.get("name", "Piso %d" % idx), "walls": walls, "exits": exits, "furniture": furn, "rooms": fd.get("rooms", [])}

# ------------------------------------------------------------------ zonas e coordenadas
static func floor_zone(bid: String, f: int) -> String:
	return "b:%s:%d" % [bid, f]

func zone_building(zone: String) -> Dictionary:
	if zone == "w" or not zone.begins_with("b:"):
		return {}
	return buildings.get(zone.split(":")[1], {})

func zone_floor_index(zone: String) -> int:
	return -1 if zone == "w" else int(zone.split(":")[2])

func zone_floor(zone: String) -> Dictionary:
	var b := zone_building(zone)
	if b.is_empty():
		return {}
	var fl: Array = floors[b["id"]]
	var i := zone_floor_index(zone)
	return fl[i] if i >= 0 and i < fl.size() else {}

func zone_valid(zone: String) -> bool:
	return zone == "w" or not zone_floor(zone).is_empty()

func zone_label(zone: String) -> String:
	if zone == "w":
		return "Rua · Maianga"
	var fl := zone_floor(zone)
	var b := zone_building(zone)
	var n: int = (floors[b["id"]] as Array).size()
	return "%s · %s" % [b["name"], ("Piso %d" % int(fl["idx"])) if n > 1 else fl["name"]]

func origin(zone: String) -> Vector2:
	if zone == "w":
		return Vector2.ZERO
	var b := zone_building(zone)
	if b.has("origin"):
		return Vector2(float(b["origin"][0]), float(b["origin"][1]) + zone_floor_index(zone) * float(data["floor_step"]))
	var base: Array = data["interior_base"]
	return Vector2(float(base[0]) + int(b["idx"]) * float(data["interior_step"]), float(base[1]) + zone_floor_index(zone) * float(data["floor_step"]))

func to_cell_space(zone: String, p: Vector2) -> Vector2:
	var q := p - origin(zone)
	return Vector2((q.x / 32.0 + q.y / 16.0) * 0.5, (q.y / 16.0 - q.x / 32.0) * 0.5)

func cs_to_px(zone: String, u: Vector2) -> Vector2:
	return origin(zone) + Vector2((u.x - u.y) * 32.0, (u.x + u.y) * 16.0)

func cell_of(zone: String, p: Vector2) -> Vector2i:
	var u := to_cell_space(zone, p)
	return Vector2i(floori(u.x), floori(u.y))

func cell_center(zone: String, c: Vector2i) -> Vector2:
	return origin(zone) + Vector2((c.x - c.y) * 32.0, (c.x + c.y) * 16.0 + 16.0)

func vertex_px(zone: String, x: float, y: float) -> Vector2:
	return origin(zone) + Vector2((x - y) * 32.0, (x + y) * 16.0)

func zone_of_point(p: Vector2) -> String:
	## Qual zona contém este píxel (usado pelo debug e para validar posições recebidas).
	if p.x < float(data["interior_base"][0]) - 1000.0:
		return "w"
	for b in building_list:
		for fl in floors[b["id"]]:
			var z := floor_zone(b["id"], int(fl["idx"]))
			if in_bounds(z, cell_of(z, p)):
				return z
	return ""

# ------------------------------------------------------------------ caminhabilidade (igual ao servidor)
func in_bounds(zone: String, c: Vector2i) -> bool:
	if zone == "w":
		return c.x >= cmin and c.x <= cmax and c.y >= rmin and c.y <= rmax
	var fl := zone_floor(zone)
	return not fl.is_empty() and c.x >= 0 and c.y >= 0 and c.x < int(fl["w"]) and c.y < int(fl["l"])

func stair_cells(st: Dictionary) -> Array:
	var out: Array = []
	for i in range(1, int(st["len"]) + 1):
		out.append(Vector2i(int(st["x"]), int(st["y"]) - i))
	return out

func stair_base(st: Dictionary) -> Vector2i:
	return Vector2i(int(st["x"]), int(st["y"]))

func stair_landing(st: Dictionary) -> Vector2i:
	return Vector2i(int(st["x"]), int(st["y"]) - int(st["len"]) - 1)

## Dimensões SEPARADAS (docs/SCALE.md): grelha (navegação/colocação/interação) vs tamanho visual/colisão (metros).
func furn_dims(f: Dictionary) -> Vector2i:
	var g: Array = data["furniture"].get(f["id"], {"grid": [1, 1]}).get("grid", [1, 1])
	return Vector2i(int(g[1]), int(g[0])) if _swap(f) else Vector2i(int(g[0]), int(g[1]))

static func _swap(f: Dictionary) -> bool:
	var fc := str(f.get("face", "s"))
	return fc == "e" or fc == "w"

func cell_m() -> float:
	return float(data.get("scale", {}).get("cell_m", 2.0))

## Retângulo visual/colisão em espaço de células (igual a server_python/world.py visual_rect).
func visual_rect(f: Dictionary) -> Rect2:
	var d: Dictionary = data["furniture"][f["id"]]
	var sw := float(d["size"][0]) / cell_m()
	var sd := float(d["size"][1]) / cell_m()
	if _swap(f):
		var t := sw
		sw = sd
		sd = t
	var g := furn_dims(f)
	var al := str(f.get("align", ""))
	var m := 0.04
	var fx := float(f["x"])
	var fy := float(f["y"])
	var x0 := fx + (m if "w" in al else (g.x - sw - m if "e" in al else (g.x - sw) * 0.5))
	var y0 := fy + (m if "n" in al else (g.y - sd - m if "s" in al else (g.y - sd) * 0.5))
	x0 = clampf(x0, fx, fx + g.x - sw)
	y0 = clampf(y0, fy, fy + g.y - sd)
	return Rect2(x0, y0, sw, sd)

## Onde/como um personagem fica numa peça: "sit" à frente do assento, "lie" ao longo da cama (cabeceira atrás).
## Devolve {point (píxel, pés), rot (rad), lift (px)}. Usado pelo jogo e pelo laboratório de escala.
func pose_for(zone: String, obj: Dictionary, pose: String) -> Dictionary:
	var vr: Rect2 = visual_rect(obj)
	var c := vr.get_center()
	var face := str(obj.get("face", "s"))
	var front := {"s": Vector2(c.x, vr.end.y), "n": Vector2(c.x, vr.position.y), "e": Vector2(vr.end.x, c.y), "w": Vector2(vr.position.x, c.y)}
	var back := {"s": Vector2(0, -1), "n": Vector2(0, 1), "e": Vector2(-1, 0), "w": Vector2(1, 0)}
	var ppm := float(data.get("scale", {}).get("px_per_m", 19.6))
	var seat := float(data["furniture"].get(obj["id"], {}).get("seat", 0.45))
	if pose == "sit":
		# anca (7 px acima dos pés no quadro "sentado") sobre o centro do assento; pernas para o lado da frente
		var fd: Vector2 = (front[face] as Vector2) - c
		var flip := 1.0 if (fd.x - fd.y) >= 0.0 else -1.0
		return {"point": vertex_px(zone, c.x, c.y), "rot": 0.0, "lift": maxf(0.0, seat * ppm - 7.0), "flip": flip}
	var hd: Vector2 = back[face]
	var sdir := Vector2((hd.x - hd.y) * 32.0, (hd.x + hd.y) * 16.0).normalized()
	return {"point": vertex_px(zone, c.x, c.y), "rot": atan2(sdir.x, -sdir.y), "lift": seat * ppm}

## Edifícios de teste (laboratório de escala): não fazem parte do mundo nem do servidor.
func register_test_building(b: Dictionary, origin_px: Vector2) -> void:
	var bb := b.duplicate(true)
	bb["idx"] = building_list.size()
	bb["origin"] = [origin_px.x, origin_px.y]
	buildings[bb["id"]] = bb
	var fl_list: Array = []
	for i in (bb["floors"] as Array).size():
		fl_list.append(_expand_floor(bb, i, bb["floors"][i]))
	floors[bb["id"]] = fl_list

func object_cells(f: Dictionary) -> Array:
	if f.get("prop", false):
		return [Vector2i(int(f["x"]), int(f["y"]))]
	var d := furn_dims(f)
	var out: Array = []
	for i in d.x:
		for j in d.y:
			out.append(Vector2i(int(f["x"]) + i, int(f["y"]) + j))
	return out

func blocked_cells(zone: String) -> Dictionary:
	if zone == "w":
		return blocked_world
	if _blocked_cache.has(zone):
		return _blocked_cache[zone]
	var out := {}
	var fl := zone_floor(zone)
	var b := zone_building(zone)
	for f in fl["furniture"]:
		for c in object_cells(f):
			out[c] = true
	for st in b.get("stairs", []):
		if int(st["lo"]) == int(fl["idx"]) or int(st["lo"]) + 1 == int(fl["idx"]):
			for c in stair_cells(st):
				out[c] = true
	_blocked_cache[zone] = out
	return out

static func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x != b.x:
		return "v:%d:%d" % [maxi(a.x, b.x), a.y]
	return "h:%d:%d" % [a.x, maxi(a.y, b.y)]

func edge_kind(zone: String, key: String) -> String:
	if zone == "w":
		return ""
	return str(zone_floor(zone)["walls"].get(key, ""))

func edge_blocked(zone: String, a: Vector2i, b: Vector2i, doors: Dictionary) -> bool:
	if zone == "w":
		return false
	var key := edge_key(a, b)
	var kind: String = zone_floor(zone)["walls"].get(key, "")
	if kind == "wall" or kind == "window" or kind == "exit":
		return true
	if kind == "door":
		return not bool(doors.get(key, true))
	return false

func cell_free(zone: String, c: Vector2i) -> bool:
	return in_bounds(zone, c) and not blocked_cells(zone).has(c)

# ------------------------------------------------------------------ pathfinding
func _astar(zone: String, s: Vector2i, t: Vector2i, doors: Dictionary) -> Array:
	if not cell_free(zone, s) or not cell_free(zone, t):
		return []
	var g := {s: 0}
	var came := {}
	var open: Array = [s]
	var in_open := {s: true}
	while not open.is_empty():
		var best := 0
		var bf := INF
		for i in open.size():
			var c: Vector2i = open[i]
			var f: float = g[c] + absi(c.x - t.x) + absi(c.y - t.y)
			if f < bf:
				bf = f
				best = i
		var cur: Vector2i = open[best]
		open.remove_at(best)
		in_open.erase(cur)
		if cur == t:
			var out: Array = [t]
			while came.has(out[0]):
				out.push_front(came[out[0]])
			return out
		for d in NEIGH:
			var n: Vector2i = cur + d
			if not cell_free(zone, n) or edge_blocked(zone, cur, n, doors):
				continue
			var ng: int = g[cur] + 1
			if ng < int(g.get(n, 1 << 30)):
				g[n] = ng
				came[n] = cur
				if not in_open.has(n):
					open.append(n)
					in_open[n] = true
	return []

func _segment_clear(zone: String, a: Vector2, b: Vector2, doors: Dictionary) -> bool:
	## Linha reta em espaço de células, com folga do corpo (4 linhas paralelas desviadas por CLEARANCE).
	for off in [Vector2(-CLEARANCE, -CLEARANCE), Vector2(CLEARANCE, -CLEARANCE), Vector2(-CLEARANCE, CLEARANCE), Vector2(CLEARANCE, CLEARANCE)]:
		var p0: Vector2 = a + off
		var p1: Vector2 = b + off
		var n := maxi(1, int(p0.distance_to(p1) / 0.08) + 1)
		var prev := Vector2i(floori(p0.x), floori(p0.y))
		if not cell_free(zone, prev):
			return false
		for k in range(1, n + 1):
			var q := p0.lerp(p1, float(k) / n)
			var c := Vector2i(floori(q.x), floori(q.y))
			if c == prev:
				continue
			if not cell_free(zone, c):
				return false
			if c.x != prev.x and c.y != prev.y:
				var m1 := Vector2i(c.x, prev.y)
				var m2 := Vector2i(prev.x, c.y)
				if not cell_free(zone, m1) or not cell_free(zone, m2):
					return false
				if edge_blocked(zone, prev, m1, doors) or edge_blocked(zone, m1, c, doors) or edge_blocked(zone, prev, m2, doors) or edge_blocked(zone, m2, c, doors):
					return false
			elif edge_blocked(zone, prev, c, doors):
				return false
			elif edge_kind(zone, edge_key(prev, c)) == "door":
				var along := fposmod(q.y if c.x != prev.x else q.x, 1.0)    # posição ao longo da aresta da porta
				if along < 0.2 or along > 0.8:
					return false
			prev = c
	return true

func find_path(zone: String, from_px: Vector2, to_px: Vector2, doors: Dictionary) -> Array:
	## Devolve waypoints em píxeis (sem o ponto de partida). Vazio = sem caminho.
	var a := to_cell_space(zone, from_px)
	var b := to_cell_space(zone, to_px)
	var s := Vector2i(floori(a.x), floori(a.y))
	var t := Vector2i(floori(b.x), floori(b.y))
	if not cell_free(zone, t):
		return []
	if not cell_free(zone, s):
		s = nearest_free(zone, s, doors)
		if s.x == -99999:
			return []
	if _segment_clear(zone, a, b, doors):
		return [to_px]
	var cells := _astar(zone, s, t, doors)
	if cells.is_empty():
		return []
	var pts: Array = [a]
	for k in range(1, cells.size() - 1):
		pts.append(Vector2(cells[k].x + 0.5, cells[k].y + 0.5))
	pts.append(b)
	var out: Array = []
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not _segment_clear(zone, pts[i], pts[j], doors):
			j -= 1
		out.append(cs_to_px(zone, pts[j]))
		i = j
	return out

func path_length(from_px: Vector2, pts: Array) -> float:
	var total := 0.0
	var p := from_px
	for q in pts:
		total += p.distance_to(q)
		p = q
	return total

func nearest_free(zone: String, c: Vector2i, doors: Dictionary, max_r: int = 3) -> Vector2i:
	if cell_free(zone, c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-99999, -99999)
		var bd := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if maxi(absi(dx), absi(dy)) == r and cell_free(zone, n) and Vector2(dx, dy).length() < bd:
					bd = Vector2(dx, dy).length()
					best = n
		if best.x != -99999:
			return best
	return Vector2i(-99999, -99999)

# ------------------------------------------------------------------ interativos
func approach_cells(zone: String, cells: Array, doors: Dictionary) -> Array:
	## Células livres encostadas ao objeto e não separadas dele por parede.
	var out: Array = []
	var set_ := {}
	for c in cells:
		set_[c] = true
	for c in cells:
		for d in NEIGH:
			var n: Vector2i = c + d
			if set_.has(n) or not cell_free(zone, n) or out.has(n):
				continue
			if edge_blocked(zone, c, n, {}) and edge_kind(zone, edge_key(c, n)) != "door":
				continue
			out.append(n)
	return out

func exit_cell(fl: Dictionary, edge: String) -> Vector2i:
	var p := edge.split(":")
	var x := int(p[1])
	var y := int(p[2])
	if p[0] == "h":
		return Vector2i(x, y - 1) if y == int(fl["l"]) else Vector2i(x, y)
	return Vector2i(x - 1, y) if x == int(fl["w"]) else Vector2i(x, y)

func entrance_tile(b: Dictionary, e: Dictionary) -> Vector2i:
	if e["face"] == "front":
		return Vector2i(int(b["c0"]) + int(e["i"]), int(b["r0"]) + int(b["d"]))
	return Vector2i(int(b["c0"]) + int(b["w"]), int(b["r0"]) + int(e["i"]))

func interactables(zone: String) -> Array:
	## Lista de interativos da zona: {type, label, cells (clicáveis), approach (células onde o jogador fica), ...}
	var out: Array = []
	if zone == "w":
		for b in building_list:
			for e in b["entrances"]:
				var t := entrance_tile(b, e)
				out.append({"type": "entrance", "building": b["id"], "entrance": e["id"], "label": "Entrar · %s" % b["name"],
					"cells": [], "approach": [t]})
		for p in props:
			if not (p["actions"] as Array).is_empty():
				out.append({"type": "object", "fid": p["fid"], "obj": p, "actions": p["actions"], "label": activity_label(p["actions"][0]),
					"cells": object_cells(p), "approach": approach_cells(zone, object_cells(p), {})})
		return out
	var b := zone_building(zone)
	var fl := zone_floor(zone)
	var fi := int(fl["idx"])
	for eid in fl["exits"]:
		var ec := exit_cell(fl, fl["exits"][eid])
		out.append({"type": "exit", "exit": eid, "label": "Sair para a rua", "cells": [ec], "approach": [ec]})
	var sts: Array = b.get("stairs", [])
	for i in sts.size():
		var st: Dictionary = sts[i]
		if int(st["lo"]) == fi:
			out.append({"type": "stairs", "stair": i, "dir": "up", "to": fi + 1, "label": "Subir ao piso %d" % (fi + 1),
				"cells": stair_cells(st) + [stair_base(st)], "approach": [stair_base(st)]})
		elif int(st["lo"]) + 1 == fi:
			out.append({"type": "stairs", "stair": i, "dir": "down", "to": fi - 1, "label": "Descer ao piso %d" % (fi - 1),
				"cells": stair_cells(st) + [stair_landing(st)], "approach": [stair_landing(st)]})
	for f in fl["furniture"]:
		if not (f.get("actions", []) as Array).is_empty():
			var cells := object_cells(f)
			out.append({"type": "object", "fid": f["fid"], "obj": f, "actions": f["actions"],
				"label": "%s · %s" % [furniture_name(f["id"]), activity_label(f["actions"][0])], "cells": cells, "approach": approach_cells(zone, cells, {})})
	for key in fl["walls"]:
		if fl["walls"][key] == "door":
			var p: PackedStringArray = (key as String).split(":")
			var a := Vector2i(int(p[1]), int(p[2]))
			var bb := Vector2i(a.x, a.y - 1) if p[0] == "h" else Vector2i(a.x - 1, a.y)
			out.append({"type": "door", "key": key, "label": "Porta", "cells": [], "approach": [a, bb],
				"mid": Vector2(a.x + 0.5, a.y) if p[0] == "h" else Vector2(a.x, a.y + 0.5)})
	return out

func activity_label(action: String) -> String:
	return str(data["activities"].get(action, {}).get("label", action))

func furniture_name(id: String) -> String:
	return str(data["furniture"].get(id, {}).get("name", id))

func item_name(id: String) -> String:
	return str(data["items"].get(id, {}).get("name", id))

func building_type_label(b: Dictionary) -> String:
	return str(data["building_types"].get(b.get("type", ""), {}).get("label", ""))

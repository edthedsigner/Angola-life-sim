extends RefCounted
## Constrói um piso interior a partir da definição em shared/data/world.json.
## Paredes = instâncias das MESMAS peças modulares do exterior (WallPieceL/R.tscn, uma por aresta da grelha);
## só muda a textura: paredes do fundo em altura total, frente e divisórias em corte (baixas) para nunca esconder o jogador.
## Chão: tile do pack (pack_original/floor.png) com tom alternado, tapete na saída e abertura nas escadas (como no original v0.6).

const WALL_L := preload("res://client/scenes/components/WallPieceL.tscn")
const WALL_R := preload("res://client/scenes/components/WallPieceR.tscn")
const IsoShapes = preload("res://client/scripts/IsoShapes.gd")
const INT := "res://assets/art/interior/"
const ART := "res://assets/art/"
const WALL_H := 48.0

static func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D

## Devolve {"floor_layer": Node2D (por baixo de tudo), "objects": Node2D (y-sort, vai para Entities), "doors": {key: {sprite, shape}}, "furniture": {fid: Sprite2D}}
static func build(zone: String) -> Dictionary:
	var fl: Dictionary = WorldData.zone_floor(zone)
	var b: Dictionary = WorldData.zone_building(zone)
	var fi := int(fl["idx"])
	var w := int(fl["w"])
	var l := int(fl["l"])
	var floor_layer := Node2D.new()
	floor_layer.name = "Floor_" + zone.replace(":", "_")
	floor_layer.z_index = -5
	var objects := Node2D.new()
	objects.name = "Interior_" + zone.replace(":", "_")
	objects.y_sort_enabled = true
	var body := StaticBody2D.new()
	body.name = "Colliders"
	objects.add_child(body)

	# --- chão
	var holes := {}
	var mats := {}
	for st in b.get("stairs", []):
		if int(st["lo"]) + 1 == fi:
			for c in WorldData.stair_cells(st):
				holes[c] = true
	for eid in fl["exits"]:
		mats[WorldData.exit_cell(fl, fl["exits"][eid])] = true
	var t_floor := _tex(INT + "floor.png")
	var t_mat := _tex(INT + "floor_mat.png")
	for x in w:
		for y in l:
			var c := Vector2i(x, y)
			if holes.has(c):
				continue
			var s := Sprite2D.new()
			s.texture = t_mat if mats.has(c) else t_floor
			s.centered = false
			s.offset = Vector2(-32, 0)
			s.position = WorldData.vertex_px(zone, x, y)
			if (x + y) % 2 == 1 and not mats.has(c):
				s.modulate = Color(0.93, 0.93, 0.92)
			floor_layer.add_child(s)
	# base/sombra à volta do piso (dá leitura de "edifício" ao interior)
	var apron := Polygon2D.new()
	var m := 0.35
	apron.polygon = PackedVector2Array([WorldData.vertex_px(zone, -m, -m), WorldData.vertex_px(zone, w + m, -m), WorldData.vertex_px(zone, w + m, l + m), WorldData.vertex_px(zone, -m, l + m)])
	apron.color = Color(0.16, 0.15, 0.14)
	apron.z_index = -1
	floor_layer.add_child(apron)

	# --- paredes, portas, janelas, saídas
	var doors := {}
	var walls: Dictionary = fl["walls"]
	for key in walls:
		var kind: String = walls[key]
		var p: PackedStringArray = (key as String).split(":")
		var o := p[0]
		var x := int(p[1])
		var y := int(p[2])
		var back := (o == "h" and y == 0) or (o == "v" and x == 0)
		var side := "l" if o == "h" else "r"
		var tex_path := ""
		if back:
			tex_path = INT + "int_wall_%s_%s.png" % [side, "window" if kind == "window" else "plain"]
			if kind == "door" or kind == "exit":
				tex_path = INT + "int_low_%s_%s.png" % [side, kind]
		else:
			tex_path = INT + "int_low_%s_%s.png" % [side, "door" if kind == "door" else ("exit" if kind == "exit" else "plain")]
		var piece: Sprite2D = (WALL_L if o == "h" else WALL_R).instantiate()
		piece.texture = _tex(tex_path)
		var a_px: Vector2
		var b_px: Vector2
		if o == "h":
			a_px = WorldData.vertex_px(zone, x, y)
			b_px = WorldData.vertex_px(zone, x + 1, y)
			piece.position = a_px + Vector2(16, 8)        # ordenar pelo ponto médio da aresta
		else:
			a_px = WorldData.vertex_px(zone, x, y + 1)
			b_px = WorldData.vertex_px(zone, x, y)
			piece.position = a_px + Vector2(16, -8)
		piece.offset = Vector2(-16, -56)
		piece.name = "Wall_" + (key as String).replace(":", "_")
		objects.add_child(piece)
		var cs := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = a_px
		seg.b = b_px
		cs.shape = seg
		body.add_child(cs)
		if kind == "door":
			doors[key] = {"sprite": piece, "shape": cs}

	# --- mobília (sprites do pack; "_r" para a variante rodada)
	var furniture := {}
	for f in fl["furniture"]:
		var fd: Dictionary = WorldData.data["furniture"][f["id"]]
		var tex_base: String = ART + str(fd["tex"])
		var tpath := tex_base + ("_r.png" if int(f.get("r", 0)) % 2 == 1 and ResourceLoader.exists(tex_base + "_r.png") else ".png")
		var sp := Sprite2D.new()
		sp.texture = _tex(tpath)
		sp.centered = false
		var dims := WorldData.furn_dims(f)
		var fx := float(f["x"])
		var fy := float(f["y"])
		var bottom := WorldData.vertex_px(zone, fx + dims.x, fy + dims.y)
		var centre := WorldData.vertex_px(zone, fx + dims.x * 0.5, fy + dims.y * 0.5)
		var ts := sp.texture.get_size() if sp.texture else Vector2(64, 64)
		# âncora como no original: base da imagem na esquina inferior (B) da pegada, centrada em B
		sp.position = centre
		sp.offset = Vector2(bottom.x - ts.x * 0.5, bottom.y - ts.y + 2) - centre
		sp.name = "F_%s_%s" % [f["fid"], f["id"]]
		sp.set_meta("fid", f["fid"])
		objects.add_child(sp)
		furniture[f["fid"]] = sp
		var poly := CollisionPolygon2D.new()
		poly.polygon = PackedVector2Array([WorldData.vertex_px(zone, fx + 0.08, fy + 0.08), WorldData.vertex_px(zone, fx + dims.x - 0.08, fy + 0.08),
			WorldData.vertex_px(zone, fx + dims.x - 0.08, fy + dims.y - 0.08), WorldData.vertex_px(zone, fx + 0.08, fy + dims.y - 0.08)])
		body.add_child(poly)

	# --- escadas (degraus) e aberturas (piso de cima)
	for st in b.get("stairs", []):
		var stair_cells: Array = WorldData.stair_cells(st)
		if int(st["lo"]) == fi or int(st["lo"]) + 1 == fi:
			var shape := IsoShapes.new()
			shape.setup(zone, st, "stairs" if int(st["lo"]) == fi else "hole", WALL_H)
			if int(st["lo"]) == fi:
				objects.add_child(shape)
			else:
				floor_layer.add_child(shape)
			for c in stair_cells:
				var poly2 := CollisionPolygon2D.new()
				poly2.polygon = PackedVector2Array([WorldData.vertex_px(zone, c.x, c.y), WorldData.vertex_px(zone, c.x + 1, c.y),
					WorldData.vertex_px(zone, c.x + 1, c.y + 1), WorldData.vertex_px(zone, c.x, c.y + 1)])
				body.add_child(poly2)
	return {"floor_layer": floor_layer, "objects": objects, "doors": doors, "furniture": furniture, "body": body}

## Porta aberta = vão livre (sem peça, sem colisão); fechada = folha baixa + colisão.
static func set_door(entry: Dictionary, open: bool) -> void:
	(entry["sprite"] as Sprite2D).visible = not open
	(entry["shape"] as CollisionShape2D).set_deferred("disabled", open)

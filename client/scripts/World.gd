extends Node2D
## Mundo. Dois modos:
##  - showcase = true  -> cenário VIVO do menu principal: sem rede, câmara cinematográfica, peões/carros ambiente.
##  - showcase = false -> mundo multiplayer: zonas (rua + pisos interiores), navegação por clique/toque/teclado,
##    interações validadas pelo servidor, HUD do jogador (Hud.gd) e overlay de debug independente (DebugOverlay.gd, F3).
##
## Navegação: um único caminho para rato e toque. Toque/clique -> _on_tap -> (interativo? caminhar até à célula de
## aproximação e executar) : (caminhar até ao tile). O teclado (WASD/setas) continua a funcionar e cancela o caminho.

const PLAYER_SCENE := preload("res://client/scenes/Player.tscn")
const WALKER_SCENE := preload("res://client/scenes/ambient/AmbientWalker.tscn")
const CAR_SCENE := preload("res://client/scenes/ambient/AmbientCar.tscn")
const InteriorBuilder = preload("res://client/scripts/InteriorBuilder.gd")
const HudScript = preload("res://client/scripts/Hud.gd")
const DebugScript = preload("res://client/scripts/DebugOverlay.gd")
const MENU_SCENE := "res://client/scenes/Main.tscn"
const REACH := 0.9                 # células (igual ao servidor: near_cell(..., 1.0) com margem)
const TAP_SLOP := 16.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0

@export var showcase: bool = false

@onready var entities: Node2D = $Entities

var local_player: CharacterBody2D = null
var remote_players: Dictionary = {}
var my_zone := "w"
var door_states: Dictionary = {}       # zona -> {aresta: aberta?}
var interiors: Dictionary = {}         # zona -> nós construídos
var hud: CanvasLayer
var debug: CanvasLayer
var overlay: Node2D
var zoom := 2.0
var pending: Dictionary = {}           # interação a executar quando o caminho terminar
var floor_goal := -1
var nearest: Dictionary = {}
var _inter_cache: Dictionary = {}
var _leaving := false
var _cam: Camera2D = null
var _t := 0.0
var _press_pos := Vector2.ZERO
var _pressed := false
var _touches: Dictionary = {}
var _pinch_d := 0.0
var _last_pinch := 0
var _hover_cell := Vector2i(-99999, 0)
var _hover_building: Dictionary = {}
var _is_touch := false

func _ready() -> void:
	if showcase:
		_start_showcase()
		return
	add_to_group("world")
	_is_touch = DisplayServer.is_touchscreen_available()
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.player_moved.connect(_on_player_moved)
	NetworkManager.zone_changed.connect(_on_zone_changed)
	NetworkManager.position_corrected.connect(_on_corrected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.server_error.connect(_on_server_error)
	NetworkManager.game_message.connect(_on_game_message)
	_fit_screen()
	get_window().size_changed.connect(_fit_screen)
	hud = HudScript.new()
	add_child(hud)
	hud.prompt_pressed.connect(interact_nearest)
	hud.floor_selected.connect(_on_floor_selected)
	hud.zoom_step.connect(func(f: float): set_zoom(zoom * f))
	debug = DebugScript.new()
	add_child(debug)
	_register_debug()
	overlay = Node2D.new()
	overlay.z_index = 100
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_build_prop_colliders()
	var ch: Dictionary = GameState.current_character
	if ch.is_empty() or not NetworkManager.connected:
		_go_menu("Sem personagem/ligação — a voltar ao menu...")
		return
	hud.set_character(ch)
	hud.set_location(WorldData.zone_label("w"))
	GameState.is_in_world = true
	NetworkManager.request_enter_world(str(ch.get("id", "")))

# ---------------------------------------------------------------- showcase (menu)
func _start_showcase() -> void:
	var tint := CanvasModulate.new()                 # ambiente de fim de tarde, ligeiramente escurecido
	tint.color = Color(0.64, 0.62, 0.78)
	add_child(tint)
	_cam = Camera2D.new()
	_cam.zoom = Vector2(2, 2)
	add_child(_cam)
	_cam.make_current()
	_spawn_ambient()

func _spawn_ambient() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var colors := ["red", "blue", "white"]
	var ci := 0
	for route in $AmbientRoutes.get_children():
		var pts: Array = []
		for m in route.get_children():
			pts.append((m as Node2D).global_position)
		if pts.size() < 2:
			continue
		var rname := String(route.name)
		if rname.begins_with("Walk"):
			for k in 2:
				var w: Node2D = WALKER_SCENE.instantiate()
				entities.add_child(w)
				var app := {"skin_tone": rng.randi_range(0, 3), "hair_style": rng.randi_range(0, 3), "hair_color": rng.randi_range(0, 3), "clothes": rng.randi_range(0, 3)}
				w.setup(pts, rng.randf(), app, rng.randf_range(22.0, 34.0))
		elif rname.begins_with("Car"):
			var c: Node2D = CAR_SCENE.instantiate()
			entities.add_child(c)
			c.setup(pts, colors[ci % colors.size()], rng.randf())
			ci += 1

# ---------------------------------------------------------------- ecrã (telemóvel: 1 px de UI = 1 px CSS, como no original)
func _fit_screen() -> void:
	var w := get_window()
	var sc := 1.0
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("window.devicePixelRatio")
		if v != null:
			sc = float(v)
	else:
		sc = DisplayServer.screen_get_scale()
	sc = maxf(sc, 1.0)
	var logical := (Vector2(w.size) / sc).round()
	if logical.x < 1280.0 or logical.y < 720.0:
		w.content_scale_size = Vector2i(maxi(int(logical.x), 360), maxi(int(logical.y), 360))
	else:
		w.content_scale_size = Vector2i(1280, 720)
	var vs := Vector2(w.content_scale_size)
	zoom = clampf(roundf(minf(vs.x / 640.0, vs.y / 360.0)), ZOOM_MIN, 3.0)

func set_zoom(z: float) -> void:
	zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)

# ---------------------------------------------------------------- jogo / rede
func _on_server_error(m: String) -> void:
	Transition.fade_in(0.3)
	if hud:
		hud.notify("Servidor: " + m, false)

func _go_menu(text: String) -> void:
	if _leaving:
		return
	_leaving = true
	GameState.is_in_world = false
	if hud:
		hud.notify(text, false, 99.0)
	await get_tree().create_timer(1.5).timeout
	await Transition.fade_out(0.4)
	get_window().content_scale_size = Vector2i(1280, 720)
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_disconnected() -> void:
	_go_menu("Ligação perdida — a voltar ao menu...")

func logout() -> void:
	NetworkManager.request_logout()          # termina a sessão: apaga o token guardado
	GameState.clear_session()
	GameState.clear()
	_go_menu("A terminar sessão...")

func _on_player_joined(peer_id: String, data: Dictionary) -> void:
	if remote_players.has(peer_id):
		var rp: CharacterBody2D = remote_players[peer_id]
		rp.teleport(_pos_of(data), str(data.get("zone", "w")))
		rp.visible = rp.zone == my_zone
		return
	if local_player and local_player.peer_id == peer_id:
		return
	var player: CharacterBody2D = PLAYER_SCENE.instantiate()
	player.is_local = (peer_id == NetworkManager.local_peer_id)
	player.set_character_data(data)
	if player.is_local:
		player.input_enabled = false             # só ganha controlo quando o mundo e o personagem estão prontos
		_enter_zone(str(data.get("zone", "w")))
	entities.add_child(player)
	if data.get("activity") != null:
		player.set_activity(_activity_status(str(data["activity"])))
	if player.is_local:
		local_player = player
		player.arrived.connect(_on_arrived)
		player.path_failed.connect(_on_path_failed)
		await Transition.fade_in(0.7)
		if is_instance_valid(player):
			player.input_enabled = true
		hud.notify("Toca/clica no chão para andar, ou usa WASD. Toca num edifício para lá ires.")
	else:
		remote_players[peer_id] = player
		player.visible = player.zone == my_zone
		if player.visible:
			hud.notify("%s chegou." % player.character_name)

func _pos_of(data: Dictionary) -> Vector2:
	var p: Dictionary = data.get("position", {})
	return Vector2(float(p.get("x", 0)), float(p.get("y", 0)))

func _on_player_left(peer_id: String) -> void:
	if remote_players.has(peer_id):
		if remote_players[peer_id].visible:
			hud.notify("%s saiu." % remote_players[peer_id].character_name)
		remote_players[peer_id].queue_free()
		remote_players.erase(peer_id)

func _on_player_moved(peer_id: String, pos: Vector2, zone: String) -> void:
	if remote_players.has(peer_id):
		var rp: CharacterBody2D = remote_players[peer_id]
		if rp.zone != zone:
			rp.teleport(pos, zone)
			rp.visible = zone == my_zone
		else:
			rp.apply_remote_position(pos)

func _on_zone_changed(peer_id: String, zone: String, pos: Vector2) -> void:
	if local_player and peer_id == local_player.peer_id:
		Transition.rect.modulate.a = 1.0
		_enter_zone(zone)
		local_player.teleport(pos, zone)
		pending = {}
		Transition.fade_in(0.35)
		if floor_goal != -1:
			if WorldData.zone_floor_index(zone) == floor_goal or zone == "w":
				floor_goal = -1
			else:
				_on_floor_selected(floor_goal)
	elif remote_players.has(peer_id):
		var rp: CharacterBody2D = remote_players[peer_id]
		rp.teleport(pos, zone)
		rp.visible = zone == my_zone

func _on_corrected(pos: Vector2, zone: String) -> void:
	if local_player:
		local_player.teleport(pos, zone)
		pending = {}

func _on_game_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"zone_state":
			var z := str(msg.get("zone", ""))
			door_states[z] = msg.get("doors", {})
			_apply_doors(z)
		"door_state":
			var z2 := str(msg.get("zone", ""))
			if not door_states.has(z2):
				door_states[z2] = {}
			door_states[z2][str(msg.get("key", ""))] = bool(msg.get("open", true))
			_apply_doors(z2)
		"chat":
			var pid := str(msg.get("peer_id", ""))
			var who: CharacterBody2D = local_player if local_player and pid == local_player.peer_id else remote_players.get(pid)
			if who:
				who.say(str(msg.get("text", "")))
		"player_activity":
			var rp: CharacterBody2D = remote_players.get(str(msg.get("peer_id", "")))
			if rp:
				rp.set_activity("" if msg.get("action") == null else _activity_status(str(msg["action"])))
		"activity_started":
			if local_player:
				local_player.stop_path()
				local_player.set_activity(str(msg.get("status", "")))
		"activity_done":
			if local_player:
				local_player.set_activity("")

func _activity_status(action: String) -> String:
	return str(WorldData.data["activities"].get(action, {}).get("status", ""))

# ---------------------------------------------------------------- zonas e interiores
func _enter_zone(zone: String) -> void:
	my_zone = zone
	if zone != "w" and not interiors.has(zone):
		var built := InteriorBuilder.build(zone)
		add_child(built["floor_layer"])
		move_child(built["floor_layer"], entities.get_index())
		entities.add_child(built["objects"])
		interiors[zone] = built
		_apply_doors(zone)
	for pid in remote_players:
		remote_players[pid].visible = remote_players[pid].zone == zone
	hud.set_location(WorldData.zone_label(zone))
	if zone == "w":
		hud.set_floors(0, 0)
	else:
		var b := WorldData.zone_building(zone)
		hud.set_floors((WorldData.floors[b["id"]] as Array).size(), WorldData.zone_floor_index(zone))

func _apply_doors(zone: String) -> void:
	if not interiors.has(zone):
		return
	var ds: Dictionary = door_states.get(zone, {})
	var doors: Dictionary = interiors[zone]["doors"]
	for key in doors:
		InteriorBuilder.set_door(doors[key], bool(ds.get(key, true)))

func _doors() -> Dictionary:
	return door_states.get(my_zone, {})

func _build_prop_colliders() -> void:
	var body := StaticBody2D.new()
	body.name = "PropColliders"
	for p in WorldData.props:
		if not WorldData.blocked_world.has(Vector2i(int(p["x"]), int(p["y"]))):
			continue
		var poly := CollisionPolygon2D.new()
		var x := float(p["x"])
		var y := float(p["y"])
		poly.polygon = PackedVector2Array([WorldData.vertex_px("w", x + 0.2, y + 0.2), WorldData.vertex_px("w", x + 0.8, y + 0.2),
			WorldData.vertex_px("w", x + 0.8, y + 0.8), WorldData.vertex_px("w", x + 0.2, y + 0.8)])
		body.add_child(poly)
	add_child(body)

func _interactables() -> Array:
	if not _inter_cache.has(my_zone):
		_inter_cache[my_zone] = WorldData.interactables(my_zone)
	return _inter_cache[my_zone]

# ---------------------------------------------------------------- input (rato + toque partilham o mesmo caminho)
func _unhandled_input(event: InputEvent) -> void:
	if showcase or _leaving or local_player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F10:
				logout()
			KEY_ESCAPE:
				if not hud.close_all():
					local_player.stop_path()
					pending = {}
			KEY_E:
				interact_nearest()
			KEY_ENTER, KEY_KP_ENTER, KEY_T:
				hud.toggle_chat()
			KEY_TAB:
				hud.toggle_phone()
			KEY_I:
				hud.show_inventory()
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				set_zoom(zoom * 1.25)
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_zoom(zoom * 0.8)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			_pinch_d = 0.0
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var ks := _touches.keys()
			var d: float = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
			if _pinch_d > 0.0:
				set_zoom(zoom * d / _pinch_d)
			_pinch_d = d
			_last_pinch = Time.get_ticks_msec()
		return
	if event is InputEventMagnifyGesture:
		set_zoom(zoom * event.factor)
		_last_pinch = Time.get_ticks_msec()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_zoom(zoom * 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_zoom(zoom / 1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_pos = event.position
				_pressed = true
			elif _pressed:
				_pressed = false
				if _touches.size() < 2 and Time.get_ticks_msec() - _last_pinch > 300 and event.position.distance_to(_press_pos) < TAP_SLOP:
					_on_tap(get_global_mouse_position())

func _on_tap(p: Vector2) -> void:
	if hud.is_modal_open():
		hud.close_all()
		return
	var t := _pick(p)
	if t.is_empty():
		_go_to_point(p)
	else:
		_go_interact(t)

## O que está debaixo do ponto (píxel do mundo) na zona atual.
func _pick(p: Vector2) -> Dictionary:
	var cell := WorldData.cell_of(my_zone, p)
	if my_zone == "w":
		var b := _building_at(p)
		if not b.is_empty():
			return {"type": "building", "b": b}
		for t in _interactables():
			if t["type"] == "object" and (t["cells"] as Array).has(cell):
				return t
		return {}
	# portas: perto do ponto médio da aresta (o vão)
	for t in _interactables():
		if t["type"] == "door":
			var mid: Vector2 = WorldData.cs_to_px(my_zone, t["mid"]) + Vector2(0, -10)
			if p.distance_to(mid) < 16.0:
				return t
	# mobília: pela imagem (a mais à frente) e depois pela pegada
	var best: Dictionary = {}
	var by := -INF
	var furn: Dictionary = interiors.get(my_zone, {}).get("furniture", {})
	for t in _interactables():
		if t["type"] != "object":
			continue
		var sp: Sprite2D = furn.get(t["fid"])
		var hit := (t["cells"] as Array).has(cell)
		if sp and not hit:
			var r := Rect2(sp.global_position + sp.offset, sp.texture.get_size())
			hit = r.has_point(p) and _opaque(sp, p)
		if hit and sp and sp.global_position.y > by:
			by = sp.global_position.y
			best = t
	if not best.is_empty():
		return best
	for t in _interactables():
		if (t["type"] == "stairs" or t["type"] == "exit") and (t["cells"] as Array).has(cell):
			return t
	return {}

func _opaque(sp: Sprite2D, p: Vector2) -> bool:
	var img := sp.texture.get_image()
	if img == null:
		return true
	var q := p - (sp.global_position + sp.offset)
	if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
		return false
	return img.get_pixel(int(q.x), int(q.y)).a > 0.3

func _building_poly(b: Dictionary) -> PackedVector2Array:
	var c0 := float(b["c0"])
	var r0 := float(b["r0"])
	var w := float(b["w"])
	var d := float(b["d"])
	var up := Vector2(0, -48.0 * (b["floors"] as Array).size() - 6.0)
	var L := WorldData.vertex_px("w", c0, r0 + d)
	var B := WorldData.vertex_px("w", c0 + w, r0 + d)
	var R := WorldData.vertex_px("w", c0 + w, r0)
	var T := WorldData.vertex_px("w", c0, r0)
	return PackedVector2Array([L, B, R, R + up, T + up, L + up])

func _building_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var key := -INF
	for b in WorldData.building_list:
		if Geometry2D.is_point_in_polygon(p, _building_poly(b)):
			var k := float(b["c0"]) + float(b["w"]) + float(b["r0"]) + float(b["d"])
			if k > key:
				key = k
				best = b
	return best

func _go_to_point(p: Vector2) -> void:
	var c := WorldData.cell_of(my_zone, p)
	var target := p
	if not WorldData.cell_free(my_zone, c):
		var n := WorldData.nearest_free(my_zone, c, _doors(), 2)
		if n.x == -99999:
			hud.notify("Não dá para ir aí.", false)
			return
		target = WorldData.cell_center(my_zone, n)
	var path := WorldData.find_path(my_zone, local_player.global_position, target, _doors())
	pending = {}
	floor_goal = -1
	if path.is_empty():
		hud.notify("Não encontro caminho até aí.", false)
		return
	local_player.set_path(path)

## Caminha até à melhor célula de aproximação (caminho mais curto) e executa a interação ao chegar.
func _go_interact(t: Dictionary) -> void:
	var options: Array = []      # [interação, célula]
	if t["type"] == "building":
		for e in t["b"]["entrances"]:
			options.append([{"type": "entrance", "building": t["b"]["id"], "entrance": e["id"], "label": "Entrar · " + t["b"]["name"]}, WorldData.entrance_tile(t["b"], e)])
	else:
		for c in t["approach"]:
			options.append([t, c])
	var best_path: Array = []
	var best_t: Dictionary = {}
	var best_len := INF
	for o in options:
		var cell: Vector2i = o[1]
		if _in_reach_cell(cell):
			_execute(o[0])
			return
		var pth := WorldData.find_path(my_zone, local_player.global_position, WorldData.cell_center(my_zone, cell), _doors())
		if pth.is_empty():
			continue
		var ln := WorldData.path_length(local_player.global_position, pth)
		if ln < best_len:
			best_len = ln
			best_path = pth
			best_t = o[0]
	if best_path.is_empty():
		hud.notify("Não encontro um caminho até lá (porta fechada?).", false)
		return
	if t["type"] != "stairs":
		floor_goal = -1
	pending = best_t
	local_player.set_path(best_path)

func _in_reach_cell(cell: Vector2i) -> bool:
	var u := WorldData.to_cell_space(my_zone, local_player.global_position)
	var dx := maxf(maxf(cell.x - u.x, 0.0), u.x - (cell.x + 1))
	var dy := maxf(maxf(cell.y - u.y, 0.0), u.y - (cell.y + 1))
	return Vector2(dx, dy).length() <= REACH * 0.5

func _on_arrived() -> void:
	if not pending.is_empty():
		var t := pending
		pending = {}
		_execute(t)

func _on_path_failed() -> void:
	if not pending.is_empty():
		pending = {}
		hud.notify("Caminho bloqueado.", false)

func _execute(t: Dictionary) -> void:
	match str(t["type"]):
		"entrance":
			NetworkManager.send_game("enter_building", {"building": t["building"], "entrance": t["entrance"]})
		"exit":
			NetworkManager.send_game("exit_building", {"exit": t["exit"]})
		"stairs":
			NetworkManager.send_game("use_stairs", {"stair": t["stair"], "dir": t["dir"]})
		"door":
			NetworkManager.send_game("door_toggle", {"key": t["key"]})
		"object":
			hud.show_actions(t)

func interact_nearest() -> void:
	if not nearest.is_empty():
		_execute(nearest)

func _on_floor_selected(level: int) -> void:
	var cur := WorldData.zone_floor_index(my_zone)
	if my_zone == "w" or level == cur:
		floor_goal = -1
		hud.sync_floor(cur)
		return
	floor_goal = level
	var dir := "up" if level > cur else "down"
	for t in _interactables():
		if t["type"] == "stairs" and t["dir"] == dir:
			_go_interact(t)
			hud.sync_floor(cur)
			return
	floor_goal = -1
	hud.notify("Não há escada para esse piso aqui.", false)

# ---------------------------------------------------------------- frame
func _process(delta: float) -> void:
	if showcase:
		_t += delta
		_cam.position = Vector2(60.0 + 280.0 * sin(_t * 0.07), 30.0 + 70.0 * sin(_t * 0.045 + 1.0))
		return
	if local_player == null:
		return
	local_player.input_enabled = not hud.is_modal_open() and not _leaving
	if is_instance_valid(local_player.camera):
		local_player.camera.zoom = local_player.camera.zoom.lerp(Vector2(zoom, zoom), clampf(delta * 12.0, 0.0, 1.0))
	_update_nearest()
	_update_hover()
	overlay.queue_redraw()

func _update_nearest() -> void:
	nearest = {}
	var best := INF
	var u := WorldData.to_cell_space(my_zone, local_player.global_position)
	for t in _interactables():
		for c in t["approach"]:
			var d := Vector2(c.x + 0.5, c.y + 0.5).distance_to(u)
			if t["type"] == "door":
				d = (t["mid"] as Vector2).distance_to(u) - 0.3
			if d < 0.95 and d < best:
				best = d
				nearest = t
	var text := ""
	if not nearest.is_empty():
		text = str(nearest["label"])
		if nearest["type"] == "door":
			text = "Fechar porta" if bool(_doors().get(nearest["key"], true)) else "Abrir porta"
	hud.set_prompt(text)

func _update_hover() -> void:
	_hover_cell = Vector2i(-99999, 0)
	_hover_building = {}
	if _is_touch or get_viewport().gui_get_hovered_control() != null:
		return
	var p := get_global_mouse_position()
	if my_zone == "w":
		_hover_building = _building_at(p)
	if _hover_building.is_empty():
		_hover_cell = WorldData.cell_of(my_zone, p)

func _diamond(c: Vector2i, inset: float = 0.0) -> PackedVector2Array:
	return PackedVector2Array([WorldData.vertex_px(my_zone, c.x + inset, c.y + inset), WorldData.vertex_px(my_zone, c.x + 1 - inset, c.y + inset),
		WorldData.vertex_px(my_zone, c.x + 1 - inset, c.y + 1 - inset), WorldData.vertex_px(my_zone, c.x + inset, c.y + 1 - inset), WorldData.vertex_px(my_zone, c.x + inset, c.y + inset)])

func _draw_overlay() -> void:
	if local_player == null:
		return
	var gold := Color(0.95, 0.75, 0.25)
	if not _hover_building.is_empty():
		overlay.draw_polyline(_building_poly(_hover_building) + PackedVector2Array([_building_poly(_hover_building)[0]]), gold, 2.0)
	elif _hover_cell.x != -99999 and WorldData.in_bounds(my_zone, _hover_cell):
		overlay.draw_polyline(_diamond(_hover_cell), Color(1, 1, 1, 0.5) if WorldData.cell_free(my_zone, _hover_cell) else Color(1, 0.4, 0.3, 0.5), 1.5)
	if not local_player.path.is_empty():
		var m: Vector2 = local_player.path[local_player.path.size() - 1]
		var k := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
		overlay.draw_polyline(PackedVector2Array([m + Vector2(-9, 0) * k, m + Vector2(0, -4.5) * k, m + Vector2(9, 0) * k, m + Vector2(0, 4.5) * k, m + Vector2(-9, 0) * k]), gold, 2.0)
	if debug.visible:
		for c in WorldData.blocked_cells(my_zone):
			overlay.draw_colored_polygon(_diamond(c, 0.05).slice(0, 4), Color(1, 0.2, 0.2, 0.22))
		for t in _interactables():
			for c in t["approach"]:
				overlay.draw_polyline(_diamond(c, 0.15), Color(0.3, 1, 0.4, 0.7), 1.0)
		if not local_player.path.is_empty():
			var pts := PackedVector2Array([local_player.global_position])
			for q in local_player.path:
				pts.append(q)
			overlay.draw_polyline(pts, Color(1, 1, 0.2), 1.5)
		overlay.draw_polyline(_diamond(WorldData.cell_of(my_zone, local_player.global_position)), Color(0.3, 0.8, 1.0), 1.5)
		for key in _doors():
			if not bool(_doors()[key]):
				var pp := (key as String).split(":")
				var a := Vector2(int(pp[1]), int(pp[2]))
				var b := a + (Vector2(1, 0) if pp[0] == "h" else Vector2(0, 1))
				overlay.draw_line(WorldData.cs_to_px(my_zone, a), WorldData.cs_to_px(my_zone, b), Color(1, 0, 0), 3.0)

# ---------------------------------------------------------------- secções de debug (F3)
func _register_debug() -> void:
	debug.register_section("Rede", _dbg_net)
	debug.register_section("Jogador", _dbg_player)
	debug.register_section("Navegação e colisão", _dbg_nav)
	debug.register_section("Entidades", _dbg_entities)
	debug.register_section("Estado do servidor", _dbg_state, true)
	debug.visibility_toggled.connect(_on_debug_toggled)

func _on_debug_toggled(_on: bool) -> void:
	overlay.queue_redraw()

func _dbg_net() -> Array:
	return ["servidor: %s" % NetworkManager.server_url(), "ligado: %s   peer: %s" % [NetworkManager.connected, NetworkManager.local_peer_id],
		"latência: %s" % (("%d ms" % int(NetworkManager.latency_ms)) if NetworkManager.latency_ms >= 0 else "—"),
		"mensagens: %d recebidas / %d enviadas" % [NetworkManager.msgs_in, NetworkManager.msgs_out]]

func _dbg_player() -> Array:
	if local_player == null:
		return ["(sem jogador)"]
	var p := local_player.global_position
	var u := WorldData.to_cell_space(my_zone, p)
	return ["personagem: %s" % GameState.current_character.get("id", "?"), "zona: %s" % my_zone,
		"pos px: %.1f, %.1f" % [p.x, p.y], "célula: %s   (%.2f, %.2f)" % [WorldData.cell_of(my_zone, p), u.x, u.y],
		"velocidade: %.1f px/s" % local_player.velocity.length(),
		"input: %s   ativo: %s" % [local_player.last_input, local_player.input_enabled],
		"colisões: %d   célula livre: %s" % [local_player.get_slide_collision_count(), WorldData.cell_free(my_zone, WorldData.cell_of(my_zone, p))]]

func _dbg_nav() -> Array:
	if local_player == null:
		return []
	var tgt := "—" if local_player.path.is_empty() else str((local_player.path[local_player.path.size() - 1] as Vector2).round())
	return ["waypoints: %d   destino: %s" % [local_player.path.size(), tgt], "pendente: %s" % str(pending.get("type", "—")),
		"piso objetivo: %d   perto: %s" % [floor_goal, str(nearest.get("label", "—"))],
		"células bloqueadas: %d   interativos: %d" % [WorldData.blocked_cells(my_zone).size(), _interactables().size()],
		"portas fechadas: %d" % _doors().values().count(false), "(vermelho = bloqueado, verde = aproximação, amarelo = caminho)"]

func _dbg_entities() -> Array:
	var vis := 0
	for pid in remote_players:
		if remote_players[pid].visible:
			vis += 1
	var out: Array = ["remotos: %d (visíveis: %d)" % [remote_players.size(), vis]]
	var n := 0
	for pid in remote_players:
		var r: CharacterBody2D = remote_players[pid]
		out.append("%s [%s] %s %s" % [r.character_name, pid, r.zone, r.global_position.round()])
		n += 1
		if n >= 8:
			break
	out.append("interiores construídos: %s" % ", ".join(PackedStringArray(interiors.keys())))
	return out

func _dbg_state() -> Array:
	var st: Dictionary = GameState.self_state
	return ["necessidades: %s" % str(st.get("needs", {})), "inventário: %s" % str(st.get("inventory", {})),
		"emprego: %s   casa: %s" % [str(st.get("job")), str(st.get("housing", {}).get("status", "?"))],
		"game_s: %.0f   escala: %sx" % [GameState.game_time(), str(st.get("time_scale", "?"))], "atividade: %s" % str(st.get("activity"))]

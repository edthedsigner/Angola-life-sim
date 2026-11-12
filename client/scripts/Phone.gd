extends Control
## Telemóvel do jogador: um "Kianda 15" (aparelho original, linguagem de design inspirada no iOS).
## Camadas do ecrã, de baixo para cima: papel de parede → ecrã principal (páginas + dock) → janela da app →
## ecrã bloqueado → Centro de Notificações / Centro de Controlo → faixa de notificação → alertas/menus →
## barra de estado + Dynamic Island + indicador inicial. O corpo físico (PhoneFrame) é desenhado por cima de tudo.
## Gestos: deslizar para cima no indicador (início / desbloquear), puxar do topo (notificações à esquerda, controlo
## à direita), deslizar entre páginas, deslizar da borda esquerda (voltar), toque longo (menu de contexto / editar).
## Todas as ações de jogo passam pelo servidor (NetworkManager.send_game); o telemóvel nunca altera estado de jogo.

const Kit = preload("res://client/scripts/phone/PhoneKit.gd")
const Frame = preload("res://client/scripts/phone/PhoneFrame.gd")
const Apps = preload("res://client/scripts/phone/PhoneApps.gd")
signal call_requested(pub: String, name: String)

const APP_NAMES := {"mensagens": "Mensagens", "amigos": "Amigos", "banco": "Banco", "emprego": "Emprego", "imoveis": "Imóveis",
	"negocios": "Negócios", "governo": "Governo", "definicoes": "Definições"}
const DEFAULT_LAYOUT := {"pages": [["W:hoje", "emprego", "imoveis", "negocios", "governo"], ["W:saude"]], "dock": ["mensagens", "amigos", "banco", "definicoes"]}
const CFG := "user://phone.cfg"
const WEEKDAYS := ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]

# definições do aparelho (guardadas localmente: são preferências de visualização, não estado de jogo)
var appearance := "auto"       # auto (escuro à noite no relógio do jogo) | light | dark
var dnd := false               # Não incomodar: sem faixas, as notificações ficam no Centro de Notificações
var brightness := 1.0
var volume := 0.8
var torch := false
var lock_on_open := true
var battery := 0.86
var layout: Dictionary = {}

# geometria (k = píxeis por ponto lógico; o ecrã tem 393 pt de largura)
var k := 1.0
var W := 393.0
var H := 852.0
var pal: Dictionary = {}

var dim: ColorRect
var device: Control
var frame                      # PhoneFrame
var screen: Control
var wall: TextureRect
var home_root: Control
var pages_strip: Control
var page_dots: HBoxContainer
var dock: PanelContainer
var app_win: Control
var lock: Control
var nc: Control
var cc: Control
var banner_layer: Control
var overlay: Control
var status                     # PhoneKit.StatusBar
var island: PanelContainer
var island_label: Label
var indicator: ColorRect
var outer_banner: Control

var apps                       # PhoneApps
var current_app := ""
var nav: Array = []            # pilha de páginas da app aberta: [{spec, node}]
var page_index := 0
var editing := false
var icon_nodes: Dictionary = {}
var _recent: Array = []
var _gesture: Dictionary = {}
var _claimed := false
var _busy := false
var _tick := 0.0
var _activity := {}
var _focused_field: Control = null
var _base_device_y := 0.0
var _built_for := Vector2.ZERO
var _dark_now := false
var _pressed_ctrl: Control = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	apps = Apps.new(self)
	_load_settings()
	_apply_volume()
	GameState.self_changed.connect(_on_state)
	GameState.social_changed.connect(_on_state)
	GameState.chat_added.connect(func(_n, _t): _on_state())
	NetworkManager.game_message.connect(_on_net)
	_build_outer_banner.call_deferred()

# ================================================================== definições locais
func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		appearance = str(c.get_value("phone", "appearance", appearance))
		dnd = bool(c.get_value("phone", "dnd", dnd))
		brightness = float(c.get_value("phone", "brightness", brightness))
		volume = float(c.get_value("phone", "volume", volume))
		lock_on_open = bool(c.get_value("phone", "lock_on_open", lock_on_open))
		battery = float(c.get_value("phone", "battery", battery))
		layout = c.get_value("phone", "layout", {})
	if not _layout_valid(layout):
		layout = DEFAULT_LAYOUT.duplicate(true)

func _layout_valid(l: Variant) -> bool:
	if not (l is Dictionary) or not l.has("pages") or not l.has("dock"):
		return false
	var seen := []
	for p in l["pages"]:
		for id in p:
			seen.append(id)
	for id in l["dock"]:
		seen.append(id)
	for id in APP_NAMES:
		if not id in seen:
			return false
	return true

func save_settings() -> void:
	var c := ConfigFile.new()
	for kv in [["appearance", appearance], ["dnd", dnd], ["brightness", brightness], ["volume", volume], ["lock_on_open", lock_on_open], ["battery", battery], ["layout", layout]]:
		c.set_value("phone", kv[0], kv[1])
	c.save(CFG)

func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))

func is_dark() -> bool:
	if appearance == "dark":
		return true
	if appearance == "light":
		return false
	var h := int(GameState.game_time() / 3600.0) % 24
	return h >= 19 or h < 6

# ================================================================== abrir / fechar
func is_open() -> bool:
	return visible

func open(skip_lock: bool = false) -> void:
	_build()
	go_home(false)
	lock.visible = lock_on_open and not skip_lock
	lock.position = Vector2.ZERO
	nc.visible = false
	cc.visible = false
	_clear_overlay()
	visible = true
	_refresh_lock()
	_refresh_home()
	_update_status()
	_busy = true
	dim.modulate.a = 0.0
	device.position.y = _base_device_y + size.y
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "modulate:a", 1.0, 0.25)
	tw.tween_property(device, "position:y", _base_device_y, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _busy = false)

func close() -> void:
	if not visible:
		return
	_release_field()
	editing = false
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "modulate:a", 0.0, 0.2)
	tw.tween_property(device, "position:y", _base_device_y + size.y, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		visible = false
		_close_app_now())
	save_settings()

## Esc: fecha a camada de cima (menu, centro, app…) e só depois o telemóvel.
func escape() -> void:
	if _focused_field and is_instance_valid(_focused_field):
		# a escrever: Esc só fecha o teclado. No ecrã tátil a versão web envia um Esc ao abrir o teclado virtual,
		# que não pode fechar a conversa.
		if not DisplayServer.is_touchscreen_available():
			_release_field()
		return
	if overlay.get_child_count() > 0:
		_clear_overlay()
	elif nc.visible:
		_slide_center(nc, false)
	elif cc.visible:
		_slide_center(cc, false)
	elif editing:
		set_editing(false)
	elif current_app != "" and nav.size() > 1:
		pop()
	elif current_app != "":
		go_home()
	else:
		close()

func _build() -> void:
	var vs := get_viewport_rect().size
	position = Vector2.ZERO
	size = vs
	var dh := minf(vs.y - 20.0, 780.0)
	var dw := dh * 0.49
	if dw > vs.x - 12.0:
		dw = vs.x - 12.0
		dh = dw / 0.49
	var key := Vector2(dw, dh)
	var want_dark := is_dark()
	if key == _built_for and want_dark == _dark_now and device != null:
		return
	_built_for = key
	_dark_now = want_dark
	pal = Kit.palette(want_dark)
	for c in get_children():
		c.queue_free()
	icon_nodes.clear()
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = vs
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _busy:
			close())
	add_child(dim)
	device = Control.new()
	device.size = key
	_base_device_y = (vs.y - dh) / 2.0
	device.position = Vector2((vs.x - dw) / 2.0, _base_device_y)
	add_child(device)
	var inset := dw * 0.045
	var sr := Rect2(inset, inset, dw - inset * 2.0, dh - inset * 2.0)
	W = sr.size.x
	H = sr.size.y
	k = W / 393.0
	screen = Control.new()
	screen.position = sr.position
	screen.size = sr.size
	screen.clip_contents = true
	screen.modulate = Color(1, 1, 1).darkened(0.6 * (1.0 - brightness))
	device.add_child(screen)
	for front in [false, true]:                 # corpo por baixo do ecrã, cantos/reflexo por cima
		var f = Frame.new()
		f.front = front
		f.size = key
		f.screen_rect = sr
		f.screen_r = W * 0.135
		f.body_r = dw * 0.17
		device.add_child(f)
		if not front:
			device.move_child(f, 0)
		frame = f
	# camadas do ecrã
	wall = TextureRect.new()
	wall.texture = Kit.wallpaper(int(W), int(H), want_dark)
	wall.size = sr.size
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(wall)
	home_root = _layer()
	app_win = _layer()
	app_win.visible = false
	lock = _layer()
	nc = _layer()
	nc.visible = false
	cc = _layer()
	cc.visible = false
	banner_layer = _layer()
	banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = _layer()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_home()
	_build_lock()
	_build_status()

func _layer() -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	screen.add_child(c)
	return c

func _px(v: float) -> float:
	return v * k

# ================================================================== barra de estado, Dynamic Island, indicador
func _build_status() -> void:
	status = Kit.StatusBar.new()
	status.k = k
	status.island_w = _px(126)
	status.size = Vector2(W, _px(50))
	screen.add_child(status)
	island = PanelContainer.new()
	island.add_theme_stylebox_override("panel", Kit.rounded(Color.BLACK, _px(19)))
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	island.size = Vector2(_px(126), _px(37))
	island.position = Vector2((W - island.size.x) / 2.0, _px(11))
	screen.add_child(island)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(_px(6)))
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	island.add_child(hb)
	island_label = Kit.label("", 13, k, Color.WHITE, "semibold")
	island_label.visible = false
	hb.add_child(island_label)
	indicator = ColorRect.new()
	indicator.size = Vector2(_px(140), _px(5))
	indicator.position = Vector2((W - indicator.size.x) / 2.0, H - _px(13))
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(indicator)
	indicator.color = Color(0, 0, 0, 0)
	indicator.draw.connect(func(): indicator.draw_style_box(Kit.rounded(indicator.get_meta("col", Color.WHITE), _px(2.5)), Rect2(Vector2.ZERO, indicator.size)))

func _update_status() -> void:
	if status == null:
		return
	var g := GameState.game_time()
	status.time_text = "%02d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60]
	var light := true
	if app_win.visible and not lock.visible and not nc.visible and not cc.visible:
		light = pal["dark"]
	status.light = light
	status.no_service = not NetworkManager.connected
	var lat := NetworkManager.latency_ms
	status.bars = 4 if lat < 0 or lat < 120 else (3 if lat < 250 else (2 if lat < 500 else 1))
	var zone := ""
	var lp: Variant = get_tree().get_first_node_in_group("world")
	if lp and "my_zone" in lp:
		zone = str(lp.my_zone)
	status.wifi = zone != "" and zone != "w"
	status.tech = "4G"
	status.battery = battery
	status.charging = _charging(zone)
	status.queue_redraw()
	indicator.set_meta("col", Color.WHITE if light else Color.BLACK)
	indicator.queue_redraw()

## Carrega dentro da casa arrendada (onde estaria o carregador); gasta enquanto o ecrã está ligado. Só visual.
func _charging(zone: String) -> bool:
	var h: Dictionary = GameState.self_state.get("housing", {})
	return h.get("status") == "arrendado" and zone.begins_with("b:%s:" % str(h.get("building", "?")))

func _process(d: float) -> void:
	_tick += d
	if _tick >= 1.0:
		var zone := ""
		var w: Variant = get_tree().get_first_node_in_group("world")
		if w and "my_zone" in w:
			zone = str(w.my_zone)
		if _charging(zone):
			battery = minf(1.0, battery + _tick / 240.0)
		elif visible:
			battery = maxf(0.08, battery - _tick / 1800.0)     # nunca desliga: só avisa (cor vermelha)
		_tick = 0.0
		if visible:
			_update_status()
			if lock.visible:
				_refresh_lock_clock()
			if is_dark() != _dark_now and not _busy and overlay.get_child_count() == 0 and _focused_field == null:
				_rebuild_keep_state()
	if visible and editing:
		var t := Time.get_ticks_msec() / 1000.0
		for id in icon_nodes:
			var n: Control = icon_nodes[id]
			if is_instance_valid(n) and not n.has_meta("dragging"):
				n.rotation = sin(t * 18.0 + float(abs(id.hash()) % 7)) * 0.035
	if visible and current_app != "" and not nav.is_empty():
		_update_navbar(nav[-1]["node"])
	if _activity.size() > 0 and visible:
		var left := maxf(0.0, float(_activity["end"]) - Time.get_ticks_msec() / 1000.0)
		island_label.text = "%s  %d s" % [_activity["status"], ceili(left)]

func _rebuild_keep_state() -> void:
	var app := current_app
	var was_lock := lock.visible
	_built_for = Vector2.ZERO
	_build()
	lock.visible = was_lock
	_refresh_lock()
	_refresh_home()
	if app != "":
		open_app(app, false)
	_update_status()

# ================================================================== ecrã principal (páginas, dock, ícones, widgets)
func _build_home() -> void:
	pages_strip = Control.new()
	pages_strip.mouse_filter = Control.MOUSE_FILTER_PASS
	home_root.add_child(pages_strip)
	page_dots = HBoxContainer.new()
	page_dots.add_theme_constant_override("separation", int(_px(8)))
	page_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	page_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_root.add_child(page_dots)
	dock = PanelContainer.new()
	var ds := Kit.rounded(Color(1, 1, 1, 0.22) if not pal["dark"] else Color(0.15, 0.15, 0.17, 0.55), _px(32))
	dock.add_theme_stylebox_override("panel", ds)
	dock.size = Vector2(W - _px(24), _px(94))
	dock.position = Vector2(_px(12), H - _px(12) - dock.size.y - _px(10))
	dock.mouse_filter = Control.MOUSE_FILTER_PASS
	home_root.add_child(dock)
	var done := Kit.text_button("Concluído", 15, k, Color.BLACK, "semibold", Color(1, 1, 1, 0.85))
	done.name = "Done"
	done.visible = false
	done.position = Vector2(W - _px(112), _px(52))
	done.pressed.connect(func(): set_editing(false))
	home_root.add_child(done)

func _cell() -> Vector2:
	return Vector2((W - _px(40)) / 4.0, _px(104))

func _refresh_home() -> void:
	if pages_strip == null:
		return
	for c in pages_strip.get_children():
		c.queue_free()
	for c in page_dots.get_children():
		c.queue_free()
	for c in dock.get_children():
		c.queue_free()
	icon_nodes.clear()
	var pages: Array = layout["pages"]
	var cell := _cell()
	for pi in pages.size():
		var page := Control.new()
		page.position = Vector2(pi * W, 0)
		page.size = Vector2(W, H)
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		pages_strip.add_child(page)
		var slot := 0
		for id in pages[pi]:
			var col := slot % 4
			var row := slot / 4
			var at := Vector2(_px(20) + col * cell.x, _px(68) + row * cell.y)
			if str(id).begins_with("W:"):
				var wdg: Control = apps.widget(str(id).substr(2), Vector2(W - _px(40) - _px(8), cell.y * 2.0 - _px(22)))
				wdg.position = at + Vector2(_px(4), 0)
				page.add_child(wdg)
				tappable(wdg, func(): pass, func(): set_editing(true))
				slot += 8
			else:
				var ic := _icon(str(id), true)
				ic.position = at + Vector2((cell.x - ic.size.x) / 2.0, 0)
				page.add_child(ic)
				slot += 1
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(_px(7), _px(7))
		dot.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.95 if pi == page_index else 0.4), _px(3.5)))
		page_dots.add_child(dot)
	page_dots.size = Vector2(W, _px(10))
	page_dots.position = Vector2(0, dock.position.y - _px(24))
	pages_strip.position.x = -page_index * W
	var dh := HBoxContainer.new()
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_theme_constant_override("separation", int((dock.size.x - _px(60) * 4) / 5.0))
	dock.add_child(dh)
	for id in layout["dock"]:
		dh.add_child(_icon(str(id), false))
	(home_root.get_node("Done") as Control).visible = editing

func _icon(id: String, with_label: bool) -> Control:
	var box := Control.new()
	var s := _px(62)
	box.custom_minimum_size = Vector2(s, s + (_px(20) if with_label else 0.0))
	box.size = box.custom_minimum_size
	box.pivot_offset = Vector2(s / 2.0, s / 2.0)
	var tr := TextureRect.new()
	tr.texture = Kit.app_icon(id, int(s))
	tr.size = Vector2(s, s)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	if with_label:
		var l := Kit.label(APP_NAMES.get(id, id), 12, k, Color.WHITE, "medium")
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(s + _px(24), _px(16))
		l.position = Vector2(-_px(12), s + _px(4))
		box.add_child(l)
	var n: int = apps.badge_count(id)
	if n > 0:
		var b := Kit.label(str(n), 14, k, Color.WHITE, "semibold")
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bp := PanelContainer.new()
		bp.add_theme_stylebox_override("panel", Kit.rounded(pal["red"], _px(12), Color(0, 0, 0, 0), 0, Vector4(_px(6), 0, _px(6), 0)))
		bp.custom_minimum_size = Vector2(_px(24), _px(24))
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bp.add_child(b)
		bp.position = Vector2(s - _px(16), -_px(7))
		box.add_child(bp)
	box.set_meta("app", id)
	icon_nodes[id] = box
	tappable(box, func(): _icon_tapped(id, box), func(): _icon_long(id, box))
	return box

func _icon_tapped(id: String, box: Control) -> void:
	if editing:
		return
	open_app(id, true, box)

func _icon_long(id: String, box: Control) -> void:
	if editing:
		return
	var items: Array = apps.quick_actions(id)
	items.append(["Editar ecrã principal", "edit", func(): set_editing(true), false])
	context_menu(box, items)

func set_editing(on: bool) -> void:
	editing = on
	if not on:
		for id in icon_nodes:
			if is_instance_valid(icon_nodes[id]):
				icon_nodes[id].rotation = 0.0
		save_settings()
	(home_root.get_node("Done") as Control).visible = on

## Reordenar no modo de edição: largar um ícone sobre outro troca-os de lugar (páginas ou dock).
func _drop_icon(id: String, global_pos: Vector2) -> void:
	var target := ""
	var best := _px(48)
	for other in icon_nodes:
		if other == id or not is_instance_valid(icon_nodes[other]):
			continue
		var r: Rect2 = icon_nodes[other].get_global_rect()
		var dd := (r.get_center() - global_pos).length()
		if dd < best:
			best = dd
			target = other
	if target != "":
		var a := _where(id)
		var b := _where(target)
		a[0][a[1]] = target
		b[0][b[1]] = id
	_refresh_home()

func _where(id: String) -> Array:
	for p in layout["pages"]:
		var i: int = (p as Array).find(id)
		if i >= 0:
			return [p, i]
	return [layout["dock"], (layout["dock"] as Array).find(id)]

func _snap_page(i: int) -> void:
	page_index = clampi(i, 0, (layout["pages"] as Array).size() - 1)
	var tw := create_tween()
	tw.tween_property(pages_strip, "position:x", -page_index * W, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for j in page_dots.get_child_count():
		(page_dots.get_child(j) as Panel).add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.95 if j == page_index else 0.4), _px(3.5)))

# ================================================================== ecrã bloqueado
func _build_lock() -> void:
	var lw := TextureRect.new()                 # o ecrã bloqueado tem o seu próprio papel de parede (não deixa ver o ecrã principal)
	lw.texture = wall.texture
	lw.size = Vector2(W, H)
	lw.stretch_mode = TextureRect.STRETCH_SCALE
	lw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_child(lw)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.18)
	shade.size = Vector2(W, H)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_child(shade)
	var lk := TextureRect.new()
	lk.texture = Kit.glyph("lock", Color.WHITE, int(_px(18)))
	lk.position = Vector2((W - _px(18)) / 2.0, _px(56))
	lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.add_child(lk)
	var date := Kit.label("", 20, k, Color(1, 1, 1, 0.92), "semibold")
	date.name = "Date"
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date.size = Vector2(W, _px(26))
	date.position = Vector2(0, _px(84))
	lock.add_child(date)
	var clock := Kit.label("", 92, k, Color(1, 1, 1, 0.95), "semibold")
	clock.name = "Clock"
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.size = Vector2(W, _px(104))
	clock.position = Vector2(0, _px(112))
	lock.add_child(clock)
	var list := VBoxContainer.new()
	list.name = "List"
	list.add_theme_constant_override("separation", int(_px(8)))
	list.position = Vector2(_px(10), _px(250))
	list.size = Vector2(W - _px(20), H - _px(420))
	lock.add_child(list)
	for side in [["torch", _px(46)], ["moon", W - _px(46) - _px(50)]]:
		var b := PanelContainer.new()
		b.name = "Q_" + str(side[0])
		b.size = Vector2(_px(50), _px(50))
		b.position = Vector2(side[1], H - _px(98))
		lock.add_child(b)
		var tr := TextureRect.new()
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
		var which: String = side[0]
		tappable(b, func():
			if which == "torch":
				set_torch(not torch)
			else:
				dnd = not dnd
				save_settings()
			_refresh_lock())
	var hint := Kit.label("Desliza para cima para abrir", 14, k, Color(1, 1, 1, 0.8), "medium")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(W, _px(20))
	hint.position = Vector2(0, H - _px(40))
	lock.add_child(hint)
	tappable(hint, unlock)
	tappable(lock, func(): pass)

func _refresh_lock_clock() -> void:
	var g := GameState.game_time()
	var day := int(g / 86400.0)
	(lock.get_node("Clock") as Label).text = "%d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60]
	(lock.get_node("Date") as Label).text = "%s, Dia %d" % [WEEKDAYS[day % 7].capitalize(), day + 1]

func _refresh_lock() -> void:
	if lock == null:
		return
	_refresh_lock_clock()
	var list: VBoxContainer = lock.get_node("List")
	for c in list.get_children():
		c.queue_free()
	var shown := 0
	var lst: Array = GameState.social.get("notifications", [])
	for i in range(lst.size() - 1, -1, -1):
		var n: Dictionary = lst[i]
		if bool(n.get("read", false)) or shown >= 4:
			continue
		list.add_child(_notif_card(n, true))
		shown += 1
	for q in [["torch", torch], ["moon", dnd]]:
		var b: PanelContainer = lock.get_node("Q_" + str(q[0]))
		b.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.9) if q[1] else Color(0, 0, 0, 0.32), _px(25)))
		(b.get_child(0) as TextureRect).texture = Kit.glyph(str(q[0]), Color.BLACK if q[1] else Color.WHITE, int(_px(22)))

func unlock() -> void:
	if not lock.visible or _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(lock, "position:y", -H, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		lock.visible = false
		lock.position.y = 0
		_busy = false
		_update_status())
	home_root.scale = Vector2(1.08, 1.08)
	home_root.pivot_offset = Vector2(W / 2.0, H / 2.0)
	home_root.modulate.a = 0.0
	var tw2 := create_tween().set_parallel()
	tw2.tween_property(home_root, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(home_root, "modulate:a", 1.0, 0.25)

func lock_now() -> void:
	_clear_overlay()
	_slide_center(cc, false)
	go_home(false)
	lock.visible = true
	lock.position = Vector2.ZERO
	_refresh_lock()
	_update_status()

# ================================================================== notificações
func _notif_meta(n: Dictionary) -> Dictionary:
	var kind := str(n.get("kind", ""))
	var from: Dictionary = n.get("from", {}) if n.get("from") is Dictionary else {}
	var app: String = {"dm": "mensagens", "friend_request": "amigos", "friend_accepted": "amigos", "invite": "amigos", "invite_reply": "amigos",
		"gift": "banco", "missed_call": "telefone"}.get(kind, "definicoes")
	var app_name: String = {"mensagens": "MENSAGENS", "amigos": "AMIGOS", "banco": "BANCO", "telefone": "TELEFONE"}.get(app, "KIANDA")
	var title := str(from.get("name", "")) if from.get("name") != null else ""
	if kind == "missed_call":
		title = "Chamada não atendida"
	return {"app": app, "app_name": app_name, "title": title, "text": str(n.get("text", "")), "from": from, "kind": kind}

static func ago(t: float) -> String:
	var s := Time.get_unix_time_from_system() - t
	if s < 60:
		return "agora"
	if s < 3600:
		return "há %d min" % int(s / 60)
	if s < 86400:
		return "há %d h" % int(s / 3600)
	return "há %d d" % int(s / 86400)

func _notif_card(n: Dictionary, frosted: bool) -> Control:
	var m := _notif_meta(n)
	var pc := PanelContainer.new()
	var bg: Color = Color(1, 1, 1, 0.78) if not (frosted and _dark_now) else Color(0.12, 0.12, 0.13, 0.82)
	if not frosted:
		bg = pal["card"]
	pc.add_theme_stylebox_override("panel", Kit.rounded(bg, _px(20), Color(0, 0, 0, 0), 0, Vector4(_px(12), _px(10), _px(12), _px(10))))
	var col: Color = Color.BLACK if bg.v > 0.5 else Color.WHITE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(_px(10)))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = Kit.app_icon(m["app"], int(_px(38)))
	ic.custom_minimum_size = Vector2(_px(38), _px(38))
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := Kit.ellipsis(Kit.label(m["title"] if m["title"] != "" else str(m["app_name"]).capitalize(), 15, k, col, "semibold"))
	top.add_child(tl)
	top.add_child(Kit.label(ago(float(n.get("t", 0))), 13, k, Color(col, 0.5)))
	vb.add_child(top)
	var body := Kit.label(m["text"], 15, k, col, "regular", true)
	body.max_lines_visible = 3
	vb.add_child(body)
	tappable(pc, func(): notification_action(n))
	return pc

## Toque numa notificação (ecrã bloqueado, centro, faixa): faz o que a notificação sugere.
func notification_action(n: Dictionary) -> void:
	var m := _notif_meta(n)
	var from: Dictionary = m["from"]
	var fp := str(from.get("pub", "")) if from.get("pub") != null else ""
	var acts: Array = n.get("actions", [])
	if not visible:
		open(true)
	lock.visible = false
	_slide_center(nc, false)
	match m["kind"]:
		"friend_request", "invite":
			if "accept" in acts:
				var verb := "Pedido de amizade" if m["kind"] == "friend_request" else "Convite"
				alert(verb, m["text"], [["Aceitar", func(): _notif_respond(n, true), "default"], ["Recusar", func(): _notif_respond(n, false), "destructive"], ["Agora não", func(): pass, "cancel"]])
				return
			open_app("amigos")
		"missed_call":
			if fp != "":
				request_call(fp, str(from.get("name", "")))
		_:
			if fp != "" and m["kind"] in ["dm", "gift", "friend_accepted", "invite_reply"]:
				open_conversation(fp, str(from.get("name", "")))
			else:
				open_app(m["app"] if APP_NAMES.has(m["app"]) else "definicoes")

func _notif_respond(n: Dictionary, accept: bool) -> void:
	var from_pub := str(n.get("from", {}).get("pub", ""))
	n["actions"] = []
	if str(n.get("kind", "")) == "friend_request":
		NetworkManager.send_game("friend_accept" if accept else "friend_decline", {"target": from_pub})
	else:
		NetworkManager.send_game("invite_respond", {"iid": n.get("data", {}).get("iid", ""), "accept": accept})

func _mark_read() -> void:
	NetworkManager.send_game("notif_read")
	for n in GameState.social.get("notifications", []):
		n["read"] = true
	get_tree().call_group("hud", "_update_badges")

## Chamado pelo HUD quando chega uma notificação do servidor.
func on_notification(n: Dictionary) -> void:
	_refresh_lock()
	var m := _notif_meta(n)
	if m["kind"] == "dm" and is_conversation_open(str(m["from"].get("pub", ""))):
		return
	if dnd:
		return
	if visible and not lock.visible:
		_show_banner(n, banner_layer, Vector2(_px(8), _px(8)), W - _px(16))
	elif not visible and outer_banner:
		var vs := get_viewport_rect().size
		var bw := minf(400.0, vs.x - 16.0)
		_show_banner(n, outer_banner, Vector2((vs.x - bw) / 2.0, 8.0), bw)

func _show_banner(n: Dictionary, parent: Control, at: Vector2, w: float) -> void:
	for c in parent.get_children():
		c.queue_free()
	var card := _notif_card(n, true)
	card.custom_minimum_size = Vector2(w, 0)
	card.size = Vector2(w, 0)
	card.position = Vector2(at.x, -_px(120))
	var sh := card.get_theme_stylebox("panel") as StyleBoxFlat
	if sh:
		sh = sh.duplicate()
		sh.shadow_color = Color(0, 0, 0, 0.25)
		sh.shadow_size = 12
		card.add_theme_stylebox_override("panel", sh)
	parent.add_child(card)
	var tw := card.create_tween()
	tw.tween_property(card, "position:y", at.y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(4.0)
	tw.tween_property(card, "position:y", -card.size.y - 20.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(card.queue_free)

## Faixa fora do telemóvel (telemóvel fechado), por cima do jogo.
func _build_outer_banner() -> void:
	outer_banner = Control.new()
	outer_banner.name = "PhoneBanner"
	outer_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_parent().add_child(outer_banner)

# ================================================================== Centro de Notificações / Centro de Controlo
func _build_nc() -> void:
	for c in nc.get_children():
		c.queue_free()
	var bw := TextureRect.new()
	bw.texture = wall.texture
	bw.size = Vector2(W, H)
	bw.stretch_mode = TextureRect.STRETCH_SCALE
	bw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nc.add_child(bw)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 0.72)
	bg.size = Vector2(W, H)
	nc.add_child(bg)
	tappable(bg, func(): pass)
	var g := GameState.game_time()
	var day := int(g / 86400.0)
	var t := Kit.label("%d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60], 64, k, Color.WHITE, "semibold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(W, _px(74))
	t.position = Vector2(0, _px(62))
	nc.add_child(t)
	var dl := Kit.label("%s, Dia %d" % [WEEKDAYS[day % 7].capitalize(), day + 1], 17, k, Color(1, 1, 1, 0.8), "semibold")
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.size = Vector2(W, _px(22))
	dl.position = Vector2(0, _px(46))
	nc.add_child(dl)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.position = Vector2(_px(10), _px(160))
	sc.size = Vector2(W - _px(20), H - _px(200))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	nc.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", int(_px(8)))
	sc.add_child(list)
	var hdr := Kit.label("Centro de Notificações", 20, k, Color.WHITE, "bold")
	list.add_child(hdr)
	var lst: Array = GameState.social.get("notifications", [])
	if lst.is_empty():
		var e := Kit.label("Sem notificações antigas", 15, k, Color(1, 1, 1, 0.6), "regular", true)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(e)
	for i in range(lst.size() - 1, maxi(-1, lst.size() - 30), -1):
		list.add_child(_notif_card(lst[i], true))
	if dnd:
		var d := Kit.label("Não incomodar está ativo: as notificações chegam aqui sem faixa.", 13, k, Color(1, 1, 1, 0.6), "regular", true)
		list.add_child(d)

func _cc_tile(parent: Control, rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", Kit.rounded(Color(0.2, 0.2, 0.22, 0.72), _px(22)))
	parent.add_child(p)
	return p

func _round_toggle(parent: Control, at: Vector2, d: float, icon: String, on: bool, on_col: Color, cb: Callable, caption: String = "") -> void:
	var b := PanelContainer.new()
	b.position = at
	b.size = Vector2(d, d)
	b.add_theme_stylebox_override("panel", Kit.rounded(on_col if on else Color(1, 1, 1, 0.18), d / 2.0))
	var tr := TextureRect.new()
	tr.texture = Kit.glyph(icon, Color.WHITE, int(d * 0.5))
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)
	parent.add_child(b)
	tappable(b, cb)
	if caption != "":
		var l := Kit.label(caption, 10, k, Color(1, 1, 1, 0.85), "medium")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(d + _px(20), _px(13))
		l.position = at + Vector2(-_px(10), d + _px(2))
		parent.add_child(l)

func _build_cc() -> void:
	for c in cc.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05, 0.78)
	bg.size = Vector2(W, H)
	cc.add_child(bg)
	tappable(bg, func(): _slide_center(cc, false))
	var u := (W - _px(16) * 2 - _px(14) * 3) / 4.0      # módulo 1×1
	var gap := _px(14)
	var x0 := _px(16)
	var y0 := _px(96)
	var R := func(cx: int, cy: int, w: int, h: int) -> Rect2: return Rect2(x0 + cx * (u + gap), y0 + cy * (u + gap), u * w + gap * (w - 1), u * h + gap * (h - 1))
	# conectividade (2×2)
	var conn := _cc_tile(cc, R.call(0, 0, 2, 2))
	var cd := u * 0.62
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	conn.add_child(inner)
	var zone := ""
	var w: Variant = get_tree().get_first_node_in_group("world")
	if w and "my_zone" in w:
		zone = str(w.my_zone)
	var sz: Vector2 = conn.size
	var pad := (sz.x - cd * 2) / 3.0
	_round_toggle(inner, Vector2(pad, pad * 0.8), cd, "antenna", NetworkManager.connected, pal["green"], func(): toast_info("Dados móveis", "Ligado ao servidor do jogo · %s" % ("%d ms" % int(NetworkManager.latency_ms) if NetworkManager.latency_ms >= 0 else "a medir…")), "Dados")
	_round_toggle(inner, Vector2(pad * 2 + cd, pad * 0.8), cd, "wifi", zone != "" and zone != "w", pal["tint"], func(): toast_info("Wi-Fi", "Ligado à rede do edifício." if zone != "w" else "Sem rede Wi-Fi aqui fora. Entra num edifício."), "Wi-Fi")
	var dbg_on := false
	var dbg: Variant = get_tree().get_first_node_in_group("debug_overlay")
	if dbg and "visible" in dbg:
		dbg_on = bool(dbg.visible)
	_round_toggle(inner, Vector2(pad, pad * 1.6 + cd), cd, "bug", dbg_on, pal["orange"], func():
		get_tree().call_group("debug_overlay", "toggle")
		_build_cc.call_deferred(), "Info técnica")
	_round_toggle(inner, Vector2(pad * 2 + cd, pad * 1.6 + cd), cd, "lock", false, pal["tint"], lock_now, "Bloquear")
	# relógio do jogo (2×2)
	var clk := _cc_tile(cc, R.call(2, 0, 2, 2))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clk.add_child(vb)
	var g := GameState.game_time()
	var l1 := Kit.label("%02d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60], 36, k, Color.WHITE, "semibold")
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l1)
	var l2 := Kit.label("Luanda · Dia %d" % (int(g / 86400.0) + 1), 13, k, Color(1, 1, 1, 0.7), "medium")
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l2)
	# Não incomodar (2×1)
	var foc := _cc_tile(cc, R.call(0, 2, 2, 1))
	foc.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.92) if dnd else Color(0.2, 0.2, 0.22, 0.72), _px(22), Color(0, 0, 0, 0), 0, Vector4(_px(12), 0, _px(8), 0)))
	var fh := HBoxContainer.new()
	fh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fh.add_theme_constant_override("separation", int(_px(8)))
	foc.add_child(fh)
	var mi := TextureRect.new()
	mi.texture = Kit.glyph("moon", Color8(94, 92, 230) if dnd else Color.WHITE, int(_px(22)))
	mi.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fh.add_child(mi)
	var fl := Kit.label("Não incomodar", 14, k, Color.BLACK if dnd else Color.WHITE, "semibold", true)
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(fl)
	tappable(foc, func():
		dnd = not dnd
		save_settings()
		_build_cc())
	# aparência e lanterna (1×1)
	_square_toggle(R.call(0, 3, 1, 1), "moon" if _dark_now else "sun", _dark_now, func():
		appearance = "light" if _dark_now else "dark"
		save_settings()
		_rebuild_keep_state()
		_open_center_now(cc))
	_square_toggle(R.call(1, 3, 1, 1), "torch", torch, func():
		set_torch(not torch)
		_build_cc())
	# brilho e volume (1×2, sliders em bloco)
	for s in [[2, "sun", brightness], [3, "speaker", volume]]:
		var sl := Kit.SliderX.new(float(s[2]), true)
		var r: Rect2 = R.call(int(s[0]), 2, 1, 2)
		sl.position = r.position
		sl.size = r.size
		sl.track_col = Color(0.2, 0.2, 0.22, 0.72)
		sl.fill_col = Color.WHITE
		sl.icon = Kit.glyph(str(s[1]), Color.WHITE, int(_px(40)))
		cc.add_child(sl)
		if s[1] == "sun":
			sl.changed.connect(func(v):
				brightness = maxf(0.15, v)
				screen.modulate = Color(1, 1, 1).darkened(0.6 * (1.0 - brightness)))
		else:
			sl.changed.connect(func(v):
				volume = v
				_apply_volume())
	var hint := Kit.label("Desliza para cima ou toca fora para fechar", 12, k, Color(1, 1, 1, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(W, _px(16))
	hint.position = Vector2(0, R.call(0, 4, 1, 1).position.y + _px(8))
	cc.add_child(hint)

func _square_toggle(r: Rect2, icon: String, on: bool, cb: Callable) -> void:
	var p := _cc_tile(cc, r)
	p.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.92) if on else Color(0.2, 0.2, 0.22, 0.72), _px(22)))
	var tr := TextureRect.new()
	tr.texture = Kit.glyph(icon, Color.BLACK if on else Color.WHITE, int(_px(28)))
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	tappable(p, cb)

func set_torch(on: bool) -> void:
	torch = on
	get_tree().call_group("world", "set_torch", on)

func _open_center_now(c: Control) -> void:
	if c == cc:
		_build_cc()
	else:
		_build_nc()
	c.visible = true
	c.position.y = 0
	_update_status()

func _slide_center(c: Control, show: bool) -> void:
	if c == null:
		return
	if show:
		if c == nc:
			_build_nc()
			_mark_read()
		else:
			_build_cc()
		c.visible = true
		if c.position.y >= 0:
			c.position.y = -H
	if not c.visible:
		return
	var tw := create_tween()
	tw.tween_property(c, "position:y", 0.0 if show else -H, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not show:
		tw.tween_callback(func():
			c.visible = false
			c.position.y = 0
			_refresh_lock()
			_update_status())
	else:
		tw.tween_callback(_update_status)

func toast_info(title: String, text: String) -> void:
	alert(title, text, [["OK", func(): pass, "cancel"]])

# ================================================================== apps: abrir, fechar, navegar
func open_app(id: String, animate: bool = true, from_icon: Control = null) -> void:
	if not APP_NAMES.has(id):
		return
	_clear_overlay()
	lock.visible = false
	nc.visible = false
	cc.visible = false
	_close_app_now()
	current_app = id
	_recent.erase(id)
	_recent.push_front(id)
	app_win.visible = true
	app_win.position = Vector2.ZERO
	app_win.scale = Vector2.ONE
	app_win.modulate.a = 1.0
	apps.open(id)
	_update_status()
	if animate:
		var r := Rect2(W / 2.0 - _px(31), H / 2.0 - _px(31), _px(62), _px(62))
		if from_icon and is_instance_valid(from_icon):
			var gr := from_icon.get_global_rect()
			var inv := screen.get_global_transform().affine_inverse()
			r = Rect2(inv * gr.position, gr.size / screen.get_global_transform().get_scale())
		app_win.pivot_offset = Vector2.ZERO
		app_win.scale = Vector2(r.size.x / W, r.size.x / W)
		app_win.position = r.position
		app_win.modulate.a = 0.4
		_busy = true
		var tw := create_tween().set_parallel()
		tw.tween_property(app_win, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(app_win, "position", Vector2.ZERO, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(app_win, "modulate:a", 1.0, 0.2)
		tw.tween_property(home_root, "scale", Vector2(0.92, 0.92), 0.38)
		home_root.pivot_offset = Vector2(W / 2.0, H / 2.0)
		tw.chain().tween_callback(func(): _busy = false)

func _close_app_now() -> void:
	_release_field()
	for c in app_win.get_children():
		c.queue_free()
	nav.clear()
	app_win.visible = false
	current_app = ""
	if home_root:
		home_root.scale = Vector2.ONE

## Voltar ao ecrã principal (a app encolhe para o seu ícone).
func go_home(animate: bool = true) -> void:
	_clear_overlay()
	if current_app == "" or not animate:
		_close_app_now()
		if home_root:
			home_root.scale = Vector2.ONE
			home_root.modulate.a = 1.0
		_refresh_home()
		_update_status()
		return
	var id := current_app
	_release_field()
	var target := Rect2(W / 2.0 - _px(31), H / 2.0 - _px(31), _px(62), _px(62))
	if icon_nodes.has(id) and is_instance_valid(icon_nodes[id]):
		var gr: Rect2 = icon_nodes[id].get_global_rect()
		var inv := screen.get_global_transform().affine_inverse()
		target = Rect2(inv * gr.position, gr.size / screen.get_global_transform().get_scale())
	_busy = true
	home_root.pivot_offset = Vector2(W / 2.0, H / 2.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(app_win, "scale", Vector2(target.size.x / W, target.size.x / W), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(app_win, "position", target.position, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(app_win, "modulate:a", 0.0, 0.34).set_ease(Tween.EASE_IN)
	tw.tween_property(home_root, "scale", Vector2.ONE, 0.34)
	tw.chain().tween_callback(func():
		_busy = false
		_close_app_now()
		_refresh_home()
		_update_status())

## Abre uma página nova na app atual (desliza da direita). spec: {title, build: Callable(body), large, right, bottom, key, bg}
func push(spec: Dictionary, animate: bool = true) -> void:
	var node := _make_page(spec)
	app_win.add_child(node)
	var prev: Control = nav[-1]["node"] if not nav.is_empty() else null
	nav.append({"spec": spec, "node": node})
	if prev and animate:
		node.position.x = W
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(prev, "position:x", -W * 0.3, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func(): prev.visible = false)
	elif prev:
		prev.visible = false

func pop(animate: bool = true) -> void:
	if nav.size() <= 1:
		go_home()
		return
	_release_field()
	var top: Dictionary = nav.pop_back()
	var node: Control = top["node"]
	var prev: Control = nav[-1]["node"]
	prev.visible = true
	rebuild_page(nav[-1])
	if animate:
		var tw := create_tween().set_parallel()
		tw.tween_property(node, "position:x", W, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(prev, "position:x", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(node.queue_free)
	else:
		prev.position.x = 0
		node.queue_free()

func top_key() -> String:
	return "" if nav.is_empty() else str(nav[-1]["spec"].get("key", ""))

func _make_page(spec: Dictionary) -> Control:
	var page := Control.new()
	page.size = Vector2(W, H)
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := ColorRect.new()
	bg.color = pal[spec.get("bg", "grouped")]
	bg.size = page.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)
	var nav_h := _px(98)
	var bottom_h := _px(64) if spec.has("bottom") else 0.0
	var sc := ScrollContainer.new()
	sc.position = Vector2(0, nav_h)
	sc.size = Vector2(W, H - nav_h - bottom_h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.follow_focus = true
	page.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		mc.add_theme_constant_override("margin_" + side, int(_px(16)))
	mc.add_theme_constant_override("margin_bottom", int(_px(40)))
	sc.add_child(mc)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", int(_px(10)))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(body)
	page.set_meta("scroll", sc)
	page.set_meta("body", body)
	# barra de navegação
	var bar := Control.new()
	bar.size = Vector2(W, nav_h)
	page.add_child(bar)
	var bar_bg := ColorRect.new()
	bar_bg.color = pal["chrome"]
	bar_bg.size = bar.size
	bar_bg.modulate.a = 0.0
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_bg)
	var sep := ColorRect.new()
	sep.color = pal["sep"]
	sep.size = Vector2(W, 1)
	sep.position = Vector2(0, nav_h - 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(sep)
	var title := Kit.label(str(spec.get("title", "")), 17, k, pal["label"], "semibold")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(W - _px(180), _px(24))
	title.position = Vector2(_px(90), nav_h - _px(34))
	title.modulate.a = 0.0 if spec.get("large", false) else 1.0
	bar.add_child(title)
	page.set_meta("bar_bg", bar_bg)
	page.set_meta("title", title)
	if not nav.is_empty():
		var back_title := str(nav[-1]["spec"].get("title", ""))
		var bb := HBoxContainer.new()
		bb.add_theme_constant_override("separation", int(_px(2)))
		bb.position = Vector2(_px(6), nav_h - _px(38))
		bb.size = Vector2(_px(150), _px(30))
		var chev := TextureRect.new()
		chev.texture = Kit.glyph("chev_l", pal["tint"], int(_px(24)), 2.6)
		chev.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bb.add_child(chev)
		var bl := Kit.label(back_title if back_title.length() <= 12 else "Voltar", 17, k, pal["tint"])
		bb.add_child(bl)
		bar.add_child(bb)
		tappable(bb, pop)
	var rights: Array = spec.get("right", [])
	var rx := W - _px(12)
	for r in rights:
		var rb: Control
		if str(r[0]).begins_with("icon:"):
			var tr := TextureRect.new()
			tr.texture = Kit.glyph(str(r[0]).substr(5), pal["tint"], int(_px(24)))
			tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			tr.size = Vector2(_px(36), _px(36))
			rb = tr
		else:
			var l := Kit.label(str(r[0]), 17, k, pal["tint"], "semibold" if r.size() > 2 and r[2] else "regular")
			l.size = Vector2(l.get_minimum_size().x + _px(8), _px(36))
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			rb = l
		rx -= rb.size.x
		rb.position = Vector2(rx, nav_h - _px(40))
		bar.add_child(rb)
		tappable(rb, r[1])
		rx -= _px(10)
	if spec.has("bottom"):
		var bot := PanelContainer.new()
		bot.position = Vector2(0, H - bottom_h - _px(20))
		bot.size = Vector2(W, bottom_h + _px(20))
		bot.add_theme_stylebox_override("panel", Kit.rounded(pal["bar"], 0, Color(0, 0, 0, 0), 0, Vector4(_px(10), _px(8), _px(10), _px(26))))
		page.add_child(bot)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", int(_px(8)))
		bot.add_child(hb)
		(spec["bottom"] as Callable).call(hb)
		page.set_meta("bottom", hb)
	_fill_body(page, spec)
	return page

func _fill_body(page: Control, spec: Dictionary) -> void:
	var body: VBoxContainer = page.get_meta("body")
	for c in body.get_children():
		c.queue_free()
	if spec.get("anchor_bottom", false):        # conversas: mensagens encostadas em baixo, junto ao campo de escrita
		var sc: ScrollContainer = page.get_meta("scroll")
		body.custom_minimum_size.y = sc.size.y - _px(48)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(spacer)
	if spec.get("large", false):
		var lt := Kit.label(str(spec.get("title", "")), 34, k, pal["label"], "bold")
		lt.custom_minimum_size = Vector2(0, _px(44))
		body.add_child(lt)
	(spec["build"] as Callable).call(body)

## Reconstrói o conteúdo da página do topo (dados novos do servidor), mantendo a posição do scroll.
func rebuild_page(entry: Dictionary) -> void:
	var node: Control = entry["node"]
	var sc: ScrollContainer = node.get_meta("scroll")
	var keep := sc.scroll_vertical
	_fill_body(node, entry["spec"])
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = keep

func refresh() -> void:
	if not visible or nav.is_empty():
		return
	if _focused_field and is_instance_valid(_focused_field) and (nav[-1]["node"] as Control).is_ancestor_of(_focused_field) and not (nav[-1]["node"] as Control).get_meta("bottom", null):
		return
	rebuild_page(nav[-1])

func scroll_to_bottom() -> void:
	if nav.is_empty():
		return
	var sc: ScrollContainer = nav[-1]["node"].get_meta("scroll")
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)

func _update_navbar(page: Control) -> void:
	if not is_instance_valid(page):
		return
	var sc: ScrollContainer = page.get_meta("scroll")
	var s := float(sc.scroll_vertical)
	(page.get_meta("bar_bg") as Control).modulate.a = clampf(s / _px(20), 0.0, 1.0)
	var spec: Dictionary = nav[-1]["spec"]
	if spec.get("large", false):
		(page.get_meta("title") as Control).modulate.a = clampf((s - _px(30)) / _px(14), 0.0, 1.0)

# ================================================================== alertas, folhas de ações, menus de contexto
func _clear_overlay() -> void:
	if overlay == null:
		return
	for c in overlay.get_children():
		c.queue_free()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _overlay_bg(alpha: float, on_tap: Callable) -> ColorRect:
	_clear_overlay()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, alpha)
	bg.size = Vector2(W, H)
	overlay.add_child(bg)
	tappable(bg, on_tap)
	bg.modulate.a = 0.0
	bg.create_tween().tween_property(bg, "modulate:a", 1.0, 0.18)
	return bg

## Alerta iOS: botões [[texto, Callable, "default"|"cancel"|"destructive"]].
func alert(title: String, message: String, buttons: Array) -> void:
	_release_field()
	_overlay_bg(0.35, func(): pass)
	var card := PanelContainer.new()
	var aw := _px(270)
	card.add_theme_stylebox_override("panel", Kit.rounded(Color(0.95, 0.95, 0.96, 0.97) if not pal["dark"] else Color(0.17, 0.17, 0.18, 0.97), _px(14)))
	card.custom_minimum_size = Vector2(aw, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	card.add_child(vb)
	var tm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		tm.add_theme_constant_override("margin_" + side, int(_px(16 if side != "bottom" else 18)))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", int(_px(4)))
	tm.add_child(tv)
	var tl := Kit.label(title, 17, k, pal["label"], "semibold", true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(tl)
	if message != "":
		var ml := Kit.label(message, 13, k, pal["label"], "regular", true)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(ml)
	vb.add_child(tm)
	var row := buttons.size() == 2            # 2 botões lado a lado; 1 ou 3+ empilhados (como no iOS)
	var holder: BoxContainer = HBoxContainer.new() if row else VBoxContainer.new()
	holder.add_theme_constant_override("separation", 0)
	if row:
		var top_sep := ColorRect.new()
		top_sep.color = pal["sep"]
		top_sep.custom_minimum_size = Vector2(0, 1)
		vb.add_child(top_sep)
	for i in buttons.size():
		var b: Array = buttons[i]
		if not row or i > 0:
			var sep := ColorRect.new()
			sep.color = pal["sep"]
			sep.custom_minimum_size = Vector2(1, 0) if row else Vector2(0, 1)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(sep)
		var style := str(b[2]) if b.size() > 2 else "default"
		var bl := Kit.label(str(b[0]), 17, k, pal["red"] if style == "destructive" else pal["tint"], "semibold" if style == "cancel" else "regular")
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.custom_minimum_size = Vector2(0, _px(44))
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb: Callable = b[1]
		tappable(bl, func():
			_clear_overlay()
			cb.call())
		holder.add_child(bl)
	vb.add_child(holder)
	overlay.add_child(card)
	card.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	card.position = (Vector2(W, H) - card.size) / 2.0
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(1.15, 1.15)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)

## Folha de ações (de baixo): [[texto, Callable, destructive:bool]].
func action_sheet(title: String, items: Array) -> void:
	_release_field()
	_overlay_bg(0.35, _clear_overlay)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(_px(8)))
	vb.size = Vector2(W - _px(16), 0)
	var group := PanelContainer.new()
	group.add_theme_stylebox_override("panel", Kit.rounded(Color(0.97, 0.97, 0.97, 0.96) if not pal["dark"] else Color(0.17, 0.17, 0.18, 0.96), _px(14)))
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 0)
	group.add_child(gv)
	if title != "":
		var tl := Kit.label(title, 13, k, pal["label2"], "semibold", true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.custom_minimum_size = Vector2(0, _px(40))
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gv.add_child(tl)
	for it in items:
		var sep := ColorRect.new()
		sep.color = pal["sep"]
		sep.custom_minimum_size = Vector2(0, 1)
		gv.add_child(sep)
		var l := Kit.label(str(it[0]), 20, k, pal["red"] if it.size() > 2 and it[2] else pal["tint"])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(0, _px(56))
		var cb: Callable = it[1]
		tappable(l, func():
			_clear_overlay()
			cb.call())
		gv.add_child(l)
	vb.add_child(group)
	var cancel := PanelContainer.new()
	cancel.add_theme_stylebox_override("panel", Kit.rounded(Color.WHITE if not pal["dark"] else Color(0.17, 0.17, 0.18), _px(14)))
	var cl := Kit.label("Cancelar", 20, k, pal["tint"], "semibold")
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.custom_minimum_size = Vector2(0, _px(56))
	cancel.add_child(cl)
	tappable(cancel, _clear_overlay)
	vb.add_child(cancel)
	overlay.add_child(vb)
	vb.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(vb):
		return
	vb.position = Vector2(_px(8), H)
	vb.create_tween().tween_property(vb, "position:y", H - vb.size.y - _px(30), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Menu de contexto (toque longo): realça o elemento e mostra ações [[texto, ícone, Callable, destructive]].
func context_menu(anchor: Control, items: Array) -> void:
	_release_field()
	_overlay_bg(0.4, _clear_overlay)
	var inv := screen.get_global_transform().affine_inverse()
	var gr := anchor.get_global_rect()
	var ar := Rect2(inv * gr.position, gr.size / screen.get_global_transform().get_scale())
	# "levantar" o elemento: uma cópia visual por cima do fundo escurecido
	if anchor.has_meta("app"):
		var lift := TextureRect.new()
		lift.texture = Kit.app_icon(str(anchor.get_meta("app")), int(_px(62)))
		lift.size = Vector2(_px(62), _px(62))
		lift.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lift.position = ar.position
		lift.pivot_offset = lift.size / 2.0
		lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(lift)
		lift.create_tween().tween_property(lift, "scale", Vector2(1.12, 1.12), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var menu := PanelContainer.new()
	menu.add_theme_stylebox_override("panel", Kit.rounded(Color(0.96, 0.96, 0.97, 0.97) if not pal["dark"] else Color(0.17, 0.17, 0.18, 0.97), _px(14)))
	menu.custom_minimum_size = Vector2(_px(250), 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	menu.add_child(vb)
	for i in items.size():
		var it: Array = items[i]
		if i > 0:
			var sep := ColorRect.new()
			sep.color = pal["sep"]
			sep.custom_minimum_size = Vector2(0, 1)
			vb.add_child(sep)
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, _px(44))
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", int(_px(16)))
		mc.add_theme_constant_override("margin_right", int(_px(14)))
		mc.add_child(row)
		var destructive: bool = it.size() > 3 and it[3]
		var col: Color = pal["red"] if destructive else pal["label"]
		var l := Kit.label(str(it[0]), 17, k, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		if str(it[1]) != "":
			var tr := TextureRect.new()
			tr.texture = Kit.glyph(str(it[1]), col, int(_px(20)))
			tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			tr.custom_minimum_size = Vector2(_px(22), 0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		var cb: Callable = it[2]
		tappable(mc, func():
			_clear_overlay()
			cb.call())
		vb.add_child(mc)
	overlay.add_child(menu)
	menu.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(menu):
		return
	var mx := clampf(ar.position.x, _px(10), W - menu.size.x - _px(10))
	var my := ar.end.y + _px(12)
	if my + menu.size.y > H - _px(30):
		my = ar.position.y - menu.size.y - _px(12)
	menu.position = Vector2(mx, maxf(_px(54), my))
	menu.pivot_offset = Vector2(menu.size.x / 2.0, 0)
	menu.scale = Vector2(0.85, 0.85)
	menu.modulate.a = 0.0
	var tw := menu.create_tween().set_parallel()
	tw.tween_property(menu, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(menu, "modulate:a", 1.0, 0.12)

# ================================================================== toque, toque longo e gestos do sistema
## Torna um controlo tocável (não dispara se o dedo arrastou / se um gesto do sistema ficou com o toque).
func tappable(c: Control, on_tap: Callable, on_long: Callable = Callable()) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(_tap_input.bind(c, on_tap, on_long))

func _tap_input(e: InputEvent, c: Control, on_tap: Callable, on_long: Callable) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_pressed_ctrl = c
			c.set_meta("down", true)
			c.set_meta("long", false)
			c.set_meta("p0", e.global_position)
			c.modulate = Color(0.75, 0.75, 0.75)
			if on_long.is_valid():
				var stamp := Time.get_ticks_msec()
				c.set_meta("stamp", stamp)
				var wr := weakref(c)                 # o controlo pode ser reconstruído antes de o temporizador disparar
				get_tree().create_timer(0.5).timeout.connect(func():
					var cc2: Control = wr.get_ref()
					if cc2 and cc2.get_meta("down", false) and cc2.get_meta("stamp", 0) == stamp and not _claimed:
						cc2.set_meta("long", true)
						cc2.modulate = Color.WHITE
						if _gesture.size() > 0:
							_gesture["kind"] = "held"
						on_long.call())
		else:
			var was_down: bool = c.get_meta("down", false)
			c.set_meta("down", false)
			c.modulate = Color.WHITE
			if was_down and not _claimed and not c.get_meta("long", false) and not _busy:
				if (e.global_position - (c.get_meta("p0", e.global_position) as Vector2)).length() < 14.0:
					on_tap.call()
		accept_event()
	elif e is InputEventMouseMotion and c.get_meta("down", false):
		if (e.global_position - (c.get_meta("p0", e.global_position) as Vector2)).length() > 14.0:
			c.set_meta("down", false)
			c.modulate = Color.WHITE

func _local(gp: Vector2) -> Vector2:
	return screen.get_global_transform().affine_inverse() * gp

func _input(e: InputEvent) -> void:
	if not visible or screen == null:
		return
	if e is InputEventScreenDrag and _claimed:
		get_viewport().set_input_as_handled()      # o ScrollContainer não arrasta em duplicado
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		var p := _local(e.global_position)
		if e.pressed:
			_claimed = false
			_gesture = {"start": p, "t": Time.get_ticks_msec(), "kind": "", "last": p, "v": Vector2.ZERO, "inside": Rect2(Vector2.ZERO, Vector2(W, H)).has_point(p)}
			if editing and _gesture["inside"]:
				for id in icon_nodes:
					var n: Control = icon_nodes[id]
					if is_instance_valid(n) and n.get_global_rect().has_point(e.global_position):
						_gesture["icon"] = id
		elif _gesture.size() > 0:
			if _gesture["kind"] != "" and _gesture["kind"] != "held":
				_end_gesture(p)
				get_viewport().set_input_as_handled()
			_gesture = {}
	elif e is InputEventMouseMotion and _gesture.size() > 0 and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var p := _local(e.global_position)
		_gesture["v"] = (p - (_gesture["last"] as Vector2)) / maxf(get_process_delta_time(), 0.001)
		_gesture["last"] = p
		var d: Vector2 = p - (_gesture["start"] as Vector2)
		if _gesture["kind"] == "" and d.length() > 10.0 and _gesture["inside"] and not _busy:
			_gesture["kind"] = _classify(_gesture["start"], d)
			if _gesture["kind"] != "":
				_claimed = true
				_begin_gesture()
		if _gesture["kind"] != "" and _gesture["kind"] != "held":
			_move_gesture(p, d)
			get_viewport().set_input_as_handled()

func _classify(s: Vector2, d: Vector2) -> String:
	var vertical := absf(d.y) > absf(d.x)
	if overlay.get_child_count() > 0:
		return ""
	if editing and _gesture.has("icon"):
		return "icon_drag"
	if s.y > H - _px(34) and vertical and d.y < 0:
		return "unlock" if lock.visible else ("cc_close" if cc.visible else ("nc_close" if nc.visible else ("home_up" if current_app != "" else "")))
	if lock.visible:
		if vertical and d.y < 0:
			return "unlock"
		if vertical and d.y > 0 and s.y < _px(60):
			return "nc_open" if s.x < W * 0.62 else "cc_open"
		return ""
	if nc.visible:
		return "nc_close" if vertical and d.y < 0 else ("scroll" if vertical else "")
	if cc.visible:
		return "cc_close" if vertical and d.y < 0 else ""
	if s.y < _px(54) and vertical and d.y > 0:
		return "cc_open" if s.x > W * 0.62 else "nc_open"
	if current_app != "":
		if s.x < _px(24) and not vertical and d.x > 0 and nav.size() > 1:
			return "back"
		if vertical and s.y > _px(98):
			return "scroll"
		return ""
	if not vertical:
		return "page"
	if vertical and d.y > 0 and not editing:
		return "nc_open"
	return ""

func _begin_gesture() -> void:
	var kind: String = _gesture["kind"]
	if _pressed_ctrl and is_instance_valid(_pressed_ctrl):      # o gesto ficou com o toque: o botão por baixo não dispara
		_pressed_ctrl.set_meta("down", false)
		_pressed_ctrl.modulate = Color.WHITE
	if kind == "nc_open":
		_build_nc()
		nc.visible = true
		nc.position.y = -H
	elif kind == "cc_open":
		_build_cc()
		cc.visible = true
		cc.position.y = -H
	elif kind == "scroll":
		var sc: ScrollContainer = (nc.get_node("Scroll") if nc.visible else nav[-1]["node"].get_meta("scroll"))
		_gesture["sc"] = sc
		_gesture["sv"] = sc.scroll_vertical
	elif kind == "icon_drag":
		var n: Control = icon_nodes[_gesture["icon"]]
		n.set_meta("dragging", true)
		n.set_meta("orig", n.global_position)
		n.rotation = 0
		n.z_index = 10
		n.scale = Vector2(1.15, 1.15)
	_release_field()

func _move_gesture(p: Vector2, d: Vector2) -> void:
	match _gesture["kind"]:
		"page":
			var maxp := (layout["pages"] as Array).size() - 1
			var x := -page_index * W + d.x
			if x > 0 or x < -maxp * W:
				x = -page_index * W + d.x * 0.35       # resistência nas pontas
			pages_strip.position.x = x
		"home_up":
			var t := clampf(-d.y / H, 0.0, 1.0)
			app_win.pivot_offset = Vector2(W / 2.0, H)
			app_win.scale = Vector2.ONE * (1.0 - t * 0.55)
			app_win.position = Vector2(d.x * 0.3, d.y * 0.25)
		"unlock":
			lock.position.y = minf(0.0, d.y)
		"nc_open":
			nc.position.y = clampf(-H + d.y, -H, 0.0)
		"cc_open":
			cc.position.y = clampf(-H + d.y, -H, 0.0)
		"nc_close":
			nc.position.y = minf(0.0, d.y)
		"cc_close":
			cc.position.y = minf(0.0, d.y)
		"back":
			var top: Control = nav[-1]["node"]
			var prev: Control = nav[-2]["node"]
			prev.visible = true
			top.position.x = maxf(0.0, d.x)
			prev.position.x = -W * 0.3 + maxf(0.0, d.x) * 0.3
		"scroll":
			var sc: ScrollContainer = _gesture["sc"]
			sc.scroll_vertical = int(_gesture["sv"]) - int(d.y)
		"icon_drag":
			var n: Control = icon_nodes[_gesture["icon"]]
			var g0: Vector2 = n.get_meta("orig")
			n.global_position = g0 + d * screen.get_global_transform().get_scale()

func _end_gesture(p: Vector2) -> void:
	var kind: String = _gesture["kind"]
	var d: Vector2 = p - (_gesture["start"] as Vector2)
	var v: Vector2 = _gesture["v"]
	match kind:
		"page":
			var i := page_index
			if d.x < -W * 0.25 or v.x < -600:
				i += 1
			elif d.x > W * 0.25 or v.x > 600:
				i -= 1
			_snap_page(i)
			_refresh_home_dots()
		"home_up":
			if -d.y > H * 0.12 or v.y < -500:
				go_home()
			else:
				var tw := create_tween().set_parallel()
				tw.tween_property(app_win, "scale", Vector2.ONE, 0.25)
				tw.tween_property(app_win, "position", Vector2.ZERO, 0.25)
		"unlock":
			if -d.y > H * 0.18 or v.y < -500:
				unlock()
			else:
				create_tween().tween_property(lock, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC)
		"nc_open", "cc_open":
			var c: Control = nc if kind == "nc_open" else cc
			_slide_center(c, d.y > H * 0.2 or v.y > 500)
			if kind == "nc_open" and (d.y > H * 0.2 or v.y > 500):
				_mark_read()
		"nc_close", "cc_close":
			var c2: Control = nc if kind == "nc_close" else cc
			_slide_center(c2, not (-d.y > H * 0.15 or v.y < -400))
		"back":
			if d.x > W * 0.35 or v.x > 500:
				pop()
			else:
				var top: Control = nav[-1]["node"]
				var prev: Control = nav[-2]["node"]
				var tw2 := create_tween().set_parallel()
				tw2.tween_property(top, "position:x", 0.0, 0.2)
				tw2.tween_property(prev, "position:x", -W * 0.3, 0.2)
				tw2.chain().tween_callback(func(): prev.visible = false)
		"scroll":
			var sc: ScrollContainer = _gesture["sc"]
			var target := sc.scroll_vertical - int(v.y * 0.25)
			create_tween().tween_property(sc, "scroll_vertical", target, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		"icon_drag":
			var id: String = _gesture["icon"]
			var n: Control = icon_nodes[id]
			n.remove_meta("dragging")
			_drop_icon(id, n.get_global_rect().get_center())

func _refresh_home_dots() -> void:
	for j in page_dots.get_child_count():
		(page_dots.get_child(j) as Panel).add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.95 if j == page_index else 0.4), _px(3.5)))

# ================================================================== teclado no ecrã (telemóveis reais)
## Campos de texto: no ecrã tátil o teclado virtual tapa a metade de baixo, por isso o aparelho sobe enquanto se escreve.
func watch_field(e: LineEdit) -> void:
	e.focus_entered.connect(func():
		_focused_field = e
		if DisplayServer.is_touchscreen_available() and is_instance_valid(device):
			var fy := e.get_global_rect().end.y
			var want := get_viewport_rect().size.y * 0.42
			if fy > want:
				create_tween().tween_property(device, "position:y", _base_device_y - (fy - want), 0.25))
	e.focus_exited.connect(func():
		if _focused_field == e:
			_focused_field = null
		if is_instance_valid(device) and visible:
			create_tween().tween_property(device, "position:y", _base_device_y, 0.25))

func _release_field() -> void:
	if _focused_field and is_instance_valid(_focused_field):
		_focused_field.release_focus()
	_focused_field = null

# ================================================================== API usada pelo HUD / painel social / apps
func request_call(pub: String, name: String) -> void:
	close()
	call_requested.emit(pub, name)

func is_conversation_open(pub: String) -> bool:
	return visible and current_app == "mensagens" and pub != "" and top_key() == "conv:" + pub

func open_conversation(pub: String, name: String) -> void:
	if not visible:
		open(true)
	lock.visible = false
	if current_app != "mensagens":
		open_app("mensagens", false)
	apps.open_conversation(pub, name)

func show_profile(p: Dictionary) -> void:
	apps.profile = p
	if current_app == "governo":
		refresh()

func _on_state() -> void:
	if not visible:
		return
	if current_app == "" and not lock.visible:
		_refresh_home()
	if lock.visible:
		_refresh_lock()
	refresh()

func _on_net(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"dm_history", "dm_message", "dm_sent":
			apps.on_dm_event(msg)
		"activity_started":
			_activity = {"status": str(msg.get("status", "")), "end": Time.get_ticks_msec() / 1000.0 + float(msg.get("secs", 1.0))}
			_island(true)
		"activity_done":
			_activity = {}
			_island(false)

## Dynamic Island: expande enquanto decorre uma atividade (cozinhar, trabalhar…), com contagem decrescente.
func _island(expanded: bool) -> void:
	if island == null or not is_instance_valid(island):
		return
	island_label.visible = expanded
	var w := _px(250) if expanded else _px(126)
	var tw := island.create_tween().set_parallel()
	tw.tween_property(island, "size:x", w, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(island, "position:x", (W - w) / 2.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

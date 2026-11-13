extends Control
## Telemóvel do jogador: um "Kianda 15" com o aspeto de um iPhone moderno, mas que funciona como um menu de jogo simples.
## Abrir leva direto ao ecrã principal (sem bloqueio). Tocar num ícone abre a app; cada página tem um botão de voltar
## (na primeira página de cada app: "‹ Início"); a barra inicial em baixo volta sempre ao ecrã principal (e, já no
## ecrã principal, fecha o telemóvel). Fechar: tocar fora, Esc ou Tab. Os únicos gestos são o scroll das listas.
## Todas as ações de jogo passam pelo servidor (NetworkManager.send_game); o telemóvel nunca altera estado de jogo.

const Kit = preload("res://client/scripts/phone/PhoneKit.gd")
const Frame = preload("res://client/scripts/phone/PhoneFrame.gd")
const Apps = preload("res://client/scripts/phone/PhoneApps.gd")
signal call_requested(pub: String, name: String)

const APP_NAMES := {"mensagens": "Mensagens", "amigos": "Amigos", "banco": "Banco", "emprego": "Emprego", "imoveis": "Imóveis",
	"negocios": "Negócios", "governo": "Governo", "definicoes": "Definições", "jogos": "Jogos"}
const GRID := ["emprego", "imoveis", "negocios", "governo", "jogos"]  # ecrã principal (por baixo do widget; 4 por linha)
const DOCK := ["mensagens", "amigos", "banco", "definicoes"]        # apps mais usadas
const CFG := "user://phone.cfg"
const WEEKDAYS := ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]

# preferências do aparelho (guardadas localmente: são visualização, não estado de jogo)
var appearance := "auto"       # auto (escuro à noite no relógio do jogo) | light | dark
var dnd := false               # Não incomodar: sem faixas de notificação (continuam no sino do HUD)
var brightness := 1.0
var volume := 0.8

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
var dock: PanelContainer
var app_win: Control
var banner_layer: Control
var overlay: Control
var status                     # PhoneKit.StatusBar
var island: PanelContainer
var island_label: Label
var indicator: Control
var outer_banner: Control

var apps                       # PhoneApps
var current_app := ""
var nav: Array = []            # pilha de páginas da app aberta: [{spec, node}]
var icon_nodes: Dictionary = {}
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

# ================================================================== preferências locais
func _load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		appearance = str(c.get_value("phone", "appearance", appearance))
		dnd = bool(c.get_value("phone", "dnd", dnd))
		brightness = float(c.get_value("phone", "brightness", brightness))
		volume = float(c.get_value("phone", "volume", volume))

func save_settings() -> void:
	var c := ConfigFile.new()
	for kv in [["appearance", appearance], ["dnd", dnd], ["brightness", brightness], ["volume", volume]]:
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

## Abre direto no ecrã principal.
func open() -> void:
	_build()
	go_home(false)
	_clear_overlay()
	visible = true
	_refresh_home()
	_update_status()
	_busy = true
	dim.modulate.a = 0.0
	device.position.y = _base_device_y + size.y * 0.35
	device.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "modulate:a", 1.0, 0.2)
	tw.tween_property(device, "modulate:a", 1.0, 0.15)
	tw.tween_property(device, "position:y", _base_device_y, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _busy = false)

func close() -> void:
	if not visible:
		return
	_release_field()
	var tw := create_tween().set_parallel()
	tw.tween_property(dim, "modulate:a", 0.0, 0.18)
	tw.tween_property(device, "position:y", _base_device_y + size.y * 0.35, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(device, "modulate:a", 0.0, 0.22)
	tw.chain().tween_callback(func():
		visible = false
		_close_app_now())
	save_settings()

## Esc: fecha a camada de cima (alerta → página → app) e só depois o telemóvel.
func escape() -> void:
	if _focused_field and is_instance_valid(_focused_field):
		# a escrever: Esc só fecha o teclado. No ecrã tátil a versão web envia um Esc ao abrir o teclado virtual,
		# que não pode fechar a conversa.
		if not DisplayServer.is_touchscreen_available():
			_release_field()
		return
	if overlay.get_child_count() > 0:
		_clear_overlay()
	elif current_app != "" and nav.size() > 1:
		pop()
	elif current_app != "":
		go_home()
	else:
		close()

## Barra inicial: volta ao ecrã principal; no ecrã principal fecha o telemóvel.
func home_button() -> void:
	if _busy:
		return
	if overlay.get_child_count() > 0:
		_clear_overlay()
	if current_app != "":
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
	wall = TextureRect.new()
	wall.texture = Kit.wallpaper(int(W), int(H), want_dark)
	wall.size = sr.size
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(wall)
	home_root = _layer()
	app_win = _layer()
	app_win.visible = false
	banner_layer = _layer()
	banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = _layer()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_home()
	_build_status()

func _layer() -> Control:
	var c := Control.new()
	c.size = Vector2(W, H)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	screen.add_child(c)
	return c

func _px(v: float) -> float:
	return v * k

# ================================================================== barra de estado, Dynamic Island, barra inicial
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
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	island.add_child(hb)
	island_label = Kit.label("", 13, k, Color.WHITE, "semibold")
	island_label.visible = false
	hb.add_child(island_label)
	# barra inicial: a pílula do iPhone, com uma área de toque larga (a única forma de voltar ao ecrã principal)
	indicator = Control.new()
	indicator.size = Vector2(_px(200), _px(26))
	indicator.position = Vector2((W - indicator.size.x) / 2.0, H - indicator.size.y)
	indicator.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	indicator.tooltip_text = "Ecrã principal"
	indicator.draw.connect(func():
		var pw := _px(140)
		indicator.draw_style_box(Kit.rounded(indicator.get_meta("col", Color.WHITE), _px(2.5)), Rect2((indicator.size.x - pw) / 2.0, indicator.size.y - _px(13), pw, _px(5))))
	screen.add_child(indicator)
	tappable(indicator, home_button)

func _update_status() -> void:
	if status == null:
		return
	var g := GameState.game_time()
	status.time_text = "%02d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60]
	var light := true
	if app_win.visible:
		light = pal["dark"]
	status.light = light
	status.no_service = not NetworkManager.connected
	var lat := NetworkManager.latency_ms
	status.bars = 4 if lat < 0 or lat < 120 else (3 if lat < 250 else (2 if lat < 500 else 1))
	status.wifi = _zone() != "" and _zone() != "w"
	status.tech = "4G"
	status.battery = 0.86
	status.charging = false
	status.queue_redraw()
	indicator.set_meta("col", Color.WHITE if light else Color.BLACK)
	indicator.queue_redraw()

func _zone() -> String:
	var w: Variant = get_tree().get_first_node_in_group("world")
	if w and "my_zone" in w:
		return str(w.my_zone)
	return ""

func _process(d: float) -> void:
	_tick += d
	if _tick >= 1.0 and visible:
		_tick = 0.0
		_update_status()
		if is_dark() != _dark_now and not _busy and overlay.get_child_count() == 0 and _focused_field == null:
			_rebuild_keep_state()
	if visible and current_app != "" and not nav.is_empty():
		_update_navbar(nav[-1]["node"])
	if _activity.size() > 0 and visible:
		var left := maxf(0.0, float(_activity["end"]) - Time.get_ticks_msec() / 1000.0)
		island_label.text = "%s  %d s" % [_activity["status"], ceili(left)]

func _rebuild_keep_state() -> void:
	var app := current_app
	_built_for = Vector2.ZERO
	_build()
	_refresh_home()
	if app != "":
		open_app(app, false)
	_update_status()

# ================================================================== ecrã principal (widget, ícones, dock)
func _build_home() -> void:
	dock = PanelContainer.new()
	dock.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.22) if not pal["dark"] else Color(0.15, 0.15, 0.17, 0.55), _px(32)))
	dock.size = Vector2(W - _px(24), _px(94))
	dock.position = Vector2(_px(12), H - _px(12) - dock.size.y - _px(16))
	dock.mouse_filter = Control.MOUSE_FILTER_PASS
	home_root.add_child(dock)

func _cell() -> Vector2:
	return Vector2((W - _px(40)) / 4.0, _px(104))

func _refresh_home() -> void:
	if home_root == null:
		return
	for c in home_root.get_children():
		if c != dock:
			c.queue_free()
	for c in dock.get_children():
		c.queue_free()
	icon_nodes.clear()
	var cell := _cell()
	var y := _px(62)
	var hoje: Control = apps.widget("hoje", Vector2(W - _px(48), cell.y * 1.5))
	hoje.position = Vector2(_px(24), y)
	home_root.add_child(hoje)
	y += cell.y * 1.5 + _px(18)
	for i in GRID.size():
		var ic := _icon(GRID[i], true)
		ic.position = Vector2(_px(20) + (i % 4) * cell.x + (cell.x - ic.size.x) / 2.0, y + (i / 4) * cell.y)
		home_root.add_child(ic)
	y += cell.y * ceili(GRID.size() / 4.0)
	var saude: Control = apps.widget("saude", Vector2(W - _px(48), cell.y * 1.5))
	saude.position = Vector2(_px(24), y)
	home_root.add_child(saude)
	tappable(saude, func(): pass)
	var dh := HBoxContainer.new()
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_theme_constant_override("separation", int((dock.size.x - _px(60) * 4) / 5.0))
	dock.add_child(dh)
	for id in DOCK:
		dh.add_child(_icon(id, false))

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
	tappable(box, func(): open_app(id, true, box))
	return box

# ================================================================== notificações (faixa simples; a lista completa está no sino do HUD)
func _notif_meta(n: Dictionary) -> Dictionary:
	var kind := str(n.get("kind", ""))
	var from: Dictionary = n.get("from", {}) if n.get("from") is Dictionary else {}
	var app: String = {"dm": "mensagens", "friend_request": "amigos", "friend_accepted": "amigos", "invite": "amigos", "invite_reply": "amigos",
		"gift": "banco", "missed_call": "telefone"}.get(kind, "definicoes")
	var nd: Variant = n.get("data")
	if kind == "invite" and nd is Dictionary and (nd as Dictionary).get("game") != null:
		app = "jogos"
	var app_name: String = {"mensagens": "MENSAGENS", "amigos": "AMIGOS", "banco": "BANCO", "telefone": "TELEFONE", "jogos": "JOGOS"}.get(app, "KIANDA")
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

## Toque numa faixa de notificação: faz o que a notificação sugere.
func notification_action(n: Dictionary) -> void:
	var m := _notif_meta(n)
	var from: Dictionary = m["from"]
	var fp := str(from.get("pub", "")) if from.get("pub") != null else ""
	var acts: Array = n.get("actions", [])
	for c in banner_layer.get_children() if banner_layer else []:
		c.queue_free()
	for c in outer_banner.get_children() if outer_banner else []:
		c.queue_free()
	if not visible and m["kind"] != "missed_call":
		open()
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

func on_notification(n: Dictionary) -> void:
	var m := _notif_meta(n)
	if m["kind"] == "dm" and is_conversation_open(str(m["from"].get("pub", ""))):
		return
	if dnd:
		return
	if visible:
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

# ================================================================== apps: abrir, fechar, navegar
func open_app(id: String, animate: bool = true, from_icon: Control = null) -> void:
	if not APP_NAMES.has(id):
		return
	_clear_overlay()
	_close_app_now()
	current_app = id
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
	title.clip_text = true                                  # títulos longos encolhem com "…"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size = Vector2(W - _px(220), _px(24))
	title.position = Vector2(_px(110), nav_h - _px(34))
	title.modulate.a = 0.0 if spec.get("large", false) else 1.0
	bar.add_child(title)
	page.set_meta("bar_bg", bar_bg)
	page.set_meta("title", title)
	if true:                                       # voltar: página anterior, ou "Início" na primeira página da app
		var back_title := str(nav[-1]["spec"].get("title", "")) if not nav.is_empty() else "Início"
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
		tappable(bb, pop if not nav.is_empty() else go_home)
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
	# texto com quebra de linha: largura explícita, senão mede-se com 0 px, fica altíssimo e o alerta sai do ecrã
	var text_w := aw - _px(32)
	var tl := Kit.label(title, 17, k, pal["label"], "semibold", true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.custom_minimum_size = Vector2(text_w, 0)
	tv.add_child(tl)
	if message != "":
		var ml := Kit.label(message, 13, k, pal["label"], "regular", true)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.custom_minimum_size = Vector2(text_w, 0)
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
	card.reset_size()                          # medir de novo com o texto já dividido em linhas
	card.position = _clamp_popup(Vector2((W - card.size.x) / 2.0, (H - card.size.y) / 2.0), card.size)
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
	var sheet_w := W - _px(16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", int(_px(8)))
	vb.custom_minimum_size = Vector2(sheet_w, 0)
	var group := PanelContainer.new()
	group.add_theme_stylebox_override("panel", Kit.rounded(Color(0.97, 0.97, 0.97, 0.96) if not pal["dark"] else Color(0.17, 0.17, 0.18, 0.96), _px(14)))
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 0)
	group.add_child(gv)
	if title != "":
		var tl := Kit.label(title, 13, k, pal["label2"], "semibold", true)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var tm := MarginContainer.new()
		for side in ["left", "right"]:
			tm.add_theme_constant_override("margin_" + side, int(_px(16)))
		for side in ["top", "bottom"]:
			tm.add_theme_constant_override("margin_" + side, int(_px(12)))
		tl.custom_minimum_size = Vector2(sheet_w - _px(32), 0)      # largura explícita (ver alert)
		tm.add_child(tl)
		gv.add_child(tm)
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
	vb.reset_size()
	var final := _clamp_popup(Vector2(_px(8), H - vb.size.y - _px(30)), vb.size)
	vb.position = Vector2(final.x, H)
	vb.create_tween().tween_property(vb, "position:y", final.y, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Garante que um alerta/folha fica dentro do ecrã (abaixo da barra de estado, acima da barra inicial).
func _clamp_popup(pos: Vector2, sz: Vector2) -> Vector2:
	var top := _px(50)
	var bottom := H - _px(20)
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, W - sz.x)), clampf(pos.y, top, maxf(top, bottom - sz.y)))

# ================================================================== toque e scroll
## Torna um controlo tocável. Não dispara se o dedo arrastou (ex.: a fazer scroll numa lista).
func tappable(c: Control, on_tap: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(_tap_input.bind(c, on_tap))

func _tap_input(e: InputEvent, c: Control, on_tap: Callable) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_pressed_ctrl = c
			c.set_meta("down", true)
			c.set_meta("p0", e.global_position)
			c.modulate = Color(0.75, 0.75, 0.75)
		else:
			var was_down: bool = c.get_meta("down", false)
			c.set_meta("down", false)
			c.modulate = Color.WHITE
			if was_down and not _claimed and not _busy:
				if (e.global_position - (c.get_meta("p0", e.global_position) as Vector2)).length() < 14.0:
					on_tap.call()
		accept_event()
	elif e is InputEventMouseMotion and c.get_meta("down", false):
		if (e.global_position - (c.get_meta("p0", e.global_position) as Vector2)).length() > 14.0:
			c.set_meta("down", false)
			c.modulate = Color.WHITE

func _local(gp: Vector2) -> Vector2:
	return screen.get_global_transform().affine_inverse() * gp

## Único gesto: arrastar na vertical dentro de uma app faz scroll (com inércia), com rato ou dedo.
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
			_gesture = {"start": p, "last": p, "v": Vector2.ZERO, "sc": null}
		elif _gesture.size() > 0:
			if _claimed and _gesture["sc"] != null:
				var sc: ScrollContainer = _gesture["sc"]
				var target := sc.scroll_vertical - int((_gesture["v"] as Vector2).y * 0.25)
				create_tween().tween_property(sc, "scroll_vertical", target, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				get_viewport().set_input_as_handled()
			_gesture = {}
	elif e is InputEventMouseMotion and _gesture.size() > 0 and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var p := _local(e.global_position)
		_gesture["v"] = (p - (_gesture["last"] as Vector2)) / maxf(get_process_delta_time(), 0.001)
		_gesture["last"] = p
		var d: Vector2 = p - (_gesture["start"] as Vector2)
		if not _claimed and absf(d.y) > 10.0 and absf(d.y) > absf(d.x) and not _busy and current_app != "" and overlay.get_child_count() == 0 \
				and Rect2(0, _px(98), W, H - _px(98)).has_point(_gesture["start"]):
			_claimed = true
			var sc2: ScrollContainer = nav[-1]["node"].get_meta("scroll")
			_gesture["sc"] = sc2
			_gesture["sv"] = sc2.scroll_vertical
			if _pressed_ctrl and is_instance_valid(_pressed_ctrl):      # o scroll ficou com o toque: o botão por baixo não dispara
				_pressed_ctrl.set_meta("down", false)
				_pressed_ctrl.modulate = Color.WHITE
			_release_field()
		if _claimed and _gesture["sc"] != null:
			(_gesture["sc"] as ScrollContainer).scroll_vertical = int(_gesture["sv"]) - int(d.y)
			get_viewport().set_input_as_handled()

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
		open()
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
	if current_app == "":
		_refresh_home()
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

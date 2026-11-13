extends CanvasLayer
## HUD e interfaces de jogo (exceto o telemóvel, que tem o seu próprio sistema).
## Princípio: o mundo continua vivo por trás. Tudo flutua em superfícies escuras translúcidas (UIStyle/UIKit):
##   · cartão do jogador (avatar, nome, nível, XP, 4 necessidades) e faixa de mundo (local, dia, hora, saldo), sempre visíveis;
##   · dock (conversar, mochila, notificações, telemóvel) e controlo de zoom agrupado;
##   · painéis contextuais que não tapam o ecrã: ações de um objeto (popover), loja/venda/mochila/notificações (folha
##     flutuante no computador, folha de baixo no telemóvel), conversa rápida, chamada, diálogos de confirmação.
## Toda a informação técnica vive no DebugOverlay (F3). Todas as ações são pedidos ao servidor.

signal prompt_pressed
signal floor_selected(level: int)
signal zoom_step(factor: float)
signal guide_requested(building: String)      # convite aceite: World mostra o caminho até lá

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const UI = preload("res://client/scripts/ui/UIKit.gd")
const Icons = preload("res://client/scripts/Icons.gd")
const Phone = preload("res://client/scripts/Phone.gd")
const SocialPanelScript = preload("res://client/scripts/SocialPanel.gd")
const VoiceCallScript = preload("res://client/scripts/VoiceCall.gd")
const NEED_ORDER := [["hunger", "Fome", "food"], ["energy", "Energia", "zap"], ["hygiene", "Higiene", "drop"], ["health", "Saúde", "heart"]]

var root: Control
# cartão do jogador
var card: PanelContainer
var avatar: Control
var lbl_name: Label
var lvl_chip: PanelContainer
var xp_bar: ProgressBar
var lbl_xp: Label
var lbl_loc_card: Label
var lbl_status: Label
var need_bars: Dictionary = {}
var need_vals: Dictionary = {}
# faixa do mundo
var info: PanelContainer
var lbl_clock: Label
var lbl_money: Label
var lbl_loc: Label
var loc_row: Control
# controlos
var dock: PanelContainer
var zoom_box: PanelContainer
var prompt: Button
var act_panel: PanelContainer
var act_label: Label
var act_pct: Label
var act_bar: ProgressBar
var floor_panel: PanelContainer
var floor_box: VBoxContainer
var floor_btns: Dictionary = {}
var toast: PanelContainer
var toast_label: Label
var toast_icon: TextureRect
var _toast_t := 0.0
# folha contextual (ações, loja, venda, mochila, notificações)
var popup: PanelContainer
var sheet_title: Label
var sheet_sub: HBoxContainer
var sheet_scroll: ScrollContainer
var popup_box: VBoxContainer
var _popup_target: Dictionary = {}
var _inv_sel := ""
var _inv_gift := false
var _new_notifs: Dictionary = {}
# conversa rápida
var chat_row: PanelContainer
var chat_log_box: VBoxContainer
var chat_input: LineEdit
# outros
var phone: Control
var social_panel: PanelContainer
var voice: Node
var call_card: PanelContainer
var call_box: VBoxContainer
var dialog_layer: Control
var bell: Button
var bell_badge: Label
var phone_badge: Label
var compact := false
var _act_total := 0.0
var _act_left := 0.0

func _ready() -> void:
	layer = 10
	add_to_group("hud")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.make_theme()
	add_child(root)
	_build_card()
	_build_info()
	_build_dock()
	_build_zoom()
	_build_prompt()
	_build_floor_picker()
	_build_toast()
	_build_sheet()
	_build_chat()
	social_panel = SocialPanelScript.new()
	root.add_child(social_panel)
	voice = VoiceCallScript.new()
	add_child(voice)
	voice.state_changed.connect(_on_call_state)
	social_panel.open_conversation.connect(func(p, n): phone.open_conversation(p, n))
	social_panel.start_call.connect(func(p, n): voice.call_player(p, n))
	_build_call_card()
	phone = Phone.new()
	root.add_child(phone)
	phone.call_requested.connect(func(p, n): voice.call_player(p, n))
	dialog_layer = Control.new()
	dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dialog_layer)
	GameState.social_changed.connect(_update_badges)
	GameState.chat_added.connect(func(_n, _t): _refresh_chat_log())
	get_viewport().size_changed.connect(_layout)
	GameState.self_changed.connect(_on_self)
	NetworkManager.game_message.connect(_on_msg)
	_layout()
	_on_self()

# ================================================================== cartão do jogador
func _build_card() -> void:
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.surface(0.78, UIStyle.R_PANEL, Vector4(12, 10, 14, 10)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(card)
	var vb := UI.vbox(8)
	card.add_child(vb)
	var top := UI.hbox(10)
	vb.add_child(top)
	avatar = UI.avatar({}, 46)
	top.add_child(avatar)
	var idv := UI.vbox(3)
	idv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(idv)
	var nrow := UI.hbox(6)
	lbl_name = UI.title("", 15, UIStyle.TEXT, "bold")
	nrow.add_child(lbl_name)
	lvl_chip = UI.chip("Nv 1", UIStyle.GOLD, "star", 0.16)
	nrow.add_child(lvl_chip)
	idv.add_child(nrow)
	var xrow := UI.hbox(6)
	xp_bar = UI.bar(0, UIStyle.GOLD, 4)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xrow.add_child(xp_bar)
	lbl_xp = UI.label("", 10, UIStyle.FAINT, "semibold")
	xrow.add_child(lbl_xp)
	idv.add_child(xrow)
	lbl_loc_card = UI.title("", 12, UIStyle.DIM, "medium")
	idv.add_child(lbl_loc_card)
	lbl_status = UI.title("", 12, Color(0.62, 0.84, 1.0), "medium")
	idv.add_child(lbl_status)
	var needs := GridContainer.new()
	needs.columns = 4
	needs.add_theme_constant_override("h_separation", 10)
	needs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(needs)
	for spec in NEED_ORDER:
		var col: Color = UIStyle.NEED_COLORS[spec[0]]
		var cell := UI.vbox(3)
		cell.tooltip_text = spec[1]
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var r := UI.hbox(4)
		r.add_child(UI.icon(spec[2], col, 13))
		var v := UI.label("--", 11, UIStyle.TEXT, "semibold")
		r.add_child(v)
		cell.add_child(r)
		var bar := UI.bar(0, col, 5, 42)
		bar.tooltip_text = spec[1]
		cell.add_child(bar)
		needs.add_child(cell)
		need_bars[spec[0]] = bar
		need_vals[spec[0]] = v

# ================================================================== faixa do mundo (local · dia · hora · saldo)
func _build_info() -> void:
	info = PanelContainer.new()
	info.add_theme_stylebox_override("panel", UIStyle.surface(0.78, UIStyle.R_PANEL, Vector4(12, 8, 12, 8)))
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(info)
	var vb := UI.vbox(4)
	info.add_child(vb)
	var row := UI.hbox(8)
	row.add_child(UI.icon("clock", UIStyle.DIM, 15))
	lbl_clock = UI.label("", 14, UIStyle.TEXT, "semibold")
	row.add_child(lbl_clock)
	var sep := ColorRect.new()
	sep.color = UIStyle.STROKE_STRONG
	sep.custom_minimum_size = Vector2(1, 16)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	row.add_child(UI.icon("wallet", UIStyle.GOLD, 15))
	lbl_money = UI.label("", 14, UIStyle.GOLD, "bold")
	row.add_child(lbl_money)
	vb.add_child(row)
	var lr := UI.hbox(6)
	lr.add_child(UI.icon("pin", UIStyle.DIM, 13))
	lbl_loc = UI.label("", 12, UIStyle.DIM, "medium")
	lr.add_child(lbl_loc)
	loc_row = lr
	vb.add_child(lr)

# ================================================================== dock e zoom
func _build_dock() -> void:
	dock = PanelContainer.new()
	dock.add_theme_stylebox_override("panel", UIStyle.surface(0.78, UIStyle.R_PILL, Vector4(6, 6, 6, 6)))
	root.add_child(dock)
	var hb := UI.hbox(6)
	dock.add_child(hb)
	hb.add_child(UI.icon_button("chat", toggle_chat, "Conversar (Enter)", 48, UIStyle.TEXT, true))
	hb.add_child(UI.icon_button("bag", show_inventory, "Mochila (I)", 48, UIStyle.TEXT, true))
	bell = UI.icon_button("bell", show_notifications, "Notificações", 48, UIStyle.TEXT, true)
	hb.add_child(bell)
	bell_badge = UI.badge(bell)
	var ph := UI.icon_button("phone", toggle_phone, "Telemóvel (Tab)", 48, UIStyle.GOLD, true)
	hb.add_child(ph)
	phone_badge = UI.badge(ph)

func _build_zoom() -> void:
	zoom_box = PanelContainer.new()
	zoom_box.add_theme_stylebox_override("panel", UIStyle.surface(0.78, UIStyle.R_PILL, Vector4(4, 4, 4, 4)))
	root.add_child(zoom_box)
	var vb := UI.vbox(2)
	zoom_box.add_child(vb)
	vb.add_child(UI.icon_button("plus", func(): zoom_step.emit(1.25), "Aproximar (+ / roda / pinça)", 42, UIStyle.TEXT, true))
	var line := ColorRect.new()
	line.color = UIStyle.STROKE_STRONG
	line.custom_minimum_size = Vector2(22, 1)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(line)
	vb.add_child(UI.icon_button("minus", func(): zoom_step.emit(0.8), "Afastar (-)", 42, UIStyle.TEXT, true))

func _update_badges() -> void:
	var n := GameState.unread_notifications()
	bell_badge.text = str(n)
	bell_badge.visible = n > 0
	var m := GameState.unread_messages()
	phone_badge.text = str(m)
	phone_badge.visible = m > 0
	if popup.visible and _popup_target.get("kind", "") == "notifications":
		_refresh_popup()

# ================================================================== ação contextual, atividade, pisos, avisos
func _build_prompt() -> void:
	prompt = UI.button("", func(): prompt_pressed.emit(), "primary", "enter")
	prompt.custom_minimum_size = Vector2(0, 48)
	prompt.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.GOLD, Color(0, 0, 0, 0), 0, Vector4(18, 10, 20, 10), UIStyle.R_PILL))
	prompt.add_theme_stylebox_override("hover", UIStyle.box(UIStyle.GOLD.lightened(0.12), Color(0, 0, 0, 0), 0, Vector4(18, 10, 20, 10), UIStyle.R_PILL))
	prompt.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.GOLD.darkened(0.18), Color(0, 0, 0, 0), 0, Vector4(18, 10, 20, 10), UIStyle.R_PILL))
	prompt.visible = false
	root.add_child(prompt)
	act_panel = PanelContainer.new()
	act_panel.add_theme_stylebox_override("panel", UIStyle.surface(0.82, UIStyle.R_PANEL, Vector4(14, 10, 10, 10)))
	var hb := UI.hbox(12)
	act_panel.add_child(hb)
	var vb := UI.vbox(6)
	vb.custom_minimum_size = Vector2(200, 0)
	hb.add_child(vb)
	var top := UI.hbox(6)
	act_label = UI.title("", 14)
	top.add_child(act_label)
	act_pct = UI.label("", 12, UIStyle.GOLD, "semibold")
	top.add_child(act_pct)
	vb.add_child(top)
	act_bar = UI.bar(0, UIStyle.GOLD, 6)
	vb.add_child(act_bar)
	hb.add_child(UI.button("Cancelar", func(): NetworkManager.send_game("cancel_activity"), "ghost"))
	act_panel.visible = false
	root.add_child(act_panel)

func _build_floor_picker() -> void:
	floor_panel = PanelContainer.new()
	floor_panel.add_theme_stylebox_override("panel", UIStyle.surface(0.78, 24, Vector4(4, 8, 4, 4)))
	floor_box = UI.vbox(4)
	floor_panel.add_child(floor_box)
	floor_panel.visible = false
	root.add_child(floor_panel)

func set_floors(count: int, current: int) -> void:
	for k in floor_btns:
		floor_btns[k].queue_free()
	floor_btns.clear()
	for c in floor_box.get_children():
		c.queue_free()
	floor_panel.visible = count > 1
	if count <= 1:
		_layout()
		return
	var t := UI.caption("Piso")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_box.add_child(t)
	for lv in range(count - 1, -1, -1):
		var b := Button.new()
		b.text = str(lv)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UIStyle.font("bold"))
		b.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, Vector4.ZERO, 22))
		b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, Vector4.ZERO, 22))
		b.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.GOLD, Color(0, 0, 0, 0), 0, Vector4.ZERO, 22))
		b.add_theme_color_override("font_pressed_color", Color(0.12, 0.08, 0.02))
		b.add_theme_color_override("font_hover_pressed_color", Color(0.12, 0.08, 0.02))
		b.button_pressed = lv == current
		var lvl := lv
		b.pressed.connect(func(): floor_selected.emit(lvl))
		floor_box.add_child(b)
		floor_btns[lv] = b
	_layout()

func sync_floor(current: int) -> void:
	for k in floor_btns:
		floor_btns[k].set_pressed_no_signal(k == current)

func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := UI.hbox(10)
	toast_icon = UI.icon("check", UIStyle.GOOD, 18)
	hb.add_child(toast_icon)
	toast_label = UI.label("", 14, UIStyle.TEXT, "medium", true)
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(toast_label)
	toast.add_child(hb)
	toast.visible = false
	root.add_child(toast)

func notify(text: String, ok: bool = true, secs: float = 3.2) -> void:
	print("[Aviso] ", text)
	toast_label.text = text
	toast_icon.texture = Icons.tex("check" if ok else "alert", UIStyle.GOOD if ok else UIStyle.BAD, 18)
	toast.add_theme_stylebox_override("panel", UIStyle.box(Color(UIStyle.SURFACE_SOLID, 0.88), Color(UIStyle.BAD, 0.45) if not ok else UIStyle.STROKE, 1, Vector4(14, 10, 16, 10), UIStyle.R_PANEL))
	toast.visible = true
	toast.modulate.a = 0.0
	toast.create_tween().tween_property(toast, "modulate:a", 1.0, 0.15)
	_toast_t = secs
	_layout()

# ================================================================== chamadas (UI; o motor é VoiceCall.gd)
func _build_call_card() -> void:
	call_card = PanelContainer.new()
	call_card.add_theme_stylebox_override("panel", UIStyle.surface(0.88, UIStyle.R_PANEL, Vector4(14, 12, 14, 12)))
	call_box = UI.vbox(10)
	call_card.add_child(call_box)
	call_card.visible = false
	root.add_child(call_card)

func _on_call_state(state: String, info_d: Dictionary) -> void:
	for c in call_box.get_children():
		c.queue_free()
	call_card.visible = state != "idle"
	if state == "idle":
		_layout()
		return
	var title: String = {"outgoing": "A chamar…", "incoming": "Chamada a entrar", "connecting": "A ligar…", "active": "Em chamada"}.get(state, "")
	var top := UI.hbox(10)
	var ring := PanelContainer.new()
	ring.add_theme_stylebox_override("panel", UIStyle.box(Color(UIStyle.GOOD, 0.18), Color(UIStyle.GOOD, 0.5), 1, Vector4(9, 9, 9, 9), 22))
	ring.add_child(UI.icon("phone", UIStyle.GOOD, 20))
	top.add_child(ring)
	var vb := UI.vbox(2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UI.title(str(info_d.get("name", "")), 16, UIStyle.TEXT, "bold"))
	var sub := title
	if state == "active":
		var secs := int(info_d.get("secs", 0))
		sub = "Em chamada · %02d:%02d" % [secs / 60, secs % 60] + ("  · microfone desligado" if info_d.get("muted", false) else "")
	vb.add_child(UI.label(sub, 12, UIStyle.DIM))
	top.add_child(vb)
	call_box.add_child(top)
	if state == "active":
		var mr := UI.hbox(8)
		mr.add_child(UI.icon("mic", UIStyle.DIM, 14))
		var lvl := UI.bar(clampf(float(info_d.get("mic", 0.0)) * 400.0, 0.0, 100.0), UIStyle.GOOD, 4, 180)
		lvl.tooltip_text = "Nível do teu microfone"
		lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mr.add_child(lvl)
		call_box.add_child(mr)
	var row := UI.hbox(8)
	match state:
		"incoming":
			row.add_child(_grow(UI.button("Recusar", func(): voice.answer(false), "danger")))
			row.add_child(_grow(UI.button("Atender", func(): voice.answer(true), "primary", "phone")))
		"outgoing", "connecting":
			row.add_child(_grow(UI.button("Cancelar", func(): voice.hangup(), "danger")))
		"active":
			row.add_child(_grow(UI.button("Ativar som" if info_d.get("muted", false) else "Silenciar", func(): voice.toggle_mute(), "secondary", "mic")))
			row.add_child(_grow(UI.button("Desligar", func(): voice.hangup(), "danger")))
	call_box.add_child(row)
	_layout()

func _grow(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func open_profile(pub: String) -> void:
	_close_popup()
	if phone.visible:
		phone.close()
	social_panel.open(pub)

# ================================================================== conversa rápida (proximidade)
func _build_chat() -> void:
	chat_row = PanelContainer.new()
	chat_row.add_theme_stylebox_override("panel", UIStyle.surface(0.78, UIStyle.R_PANEL, Vector4(10, 10, 10, 10)))
	var vb := UI.vbox(8)
	chat_row.add_child(vb)
	var head := UI.hbox(6)
	head.add_child(UI.icon("chat", UIStyle.GOLD, 15))
	head.add_child(UI.title("Perto de ti", 13, UIStyle.TEXT, "semibold"))
	var conv := UI.button("Conversas", func():
		toggle_chat()
		phone.open()
		phone.open_app("mensagens", false), "ghost", "phone")
	conv.custom_minimum_size = Vector2(0, 32)
	head.add_child(conv)
	head.add_child(UI.icon_button("x", toggle_chat, "Fechar", 32, UIStyle.DIM, true))
	vb.add_child(head)
	chat_log_box = UI.vbox(4)
	vb.add_child(chat_log_box)
	var row := UI.hbox(8)
	var box := PanelContainer.new()
	box.theme_type_variation = "FieldBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Diz algo a quem está perto…"
	chat_input.max_length = 120
	chat_input.text_submitted.connect(_send_chat)
	chat_input.focus_entered.connect(func(): box.theme_type_variation = "FieldBoxFocus")
	chat_input.focus_exited.connect(func(): box.theme_type_variation = "FieldBox")
	box.add_child(chat_input)
	row.add_child(box)
	var send := UI.icon_button("send", func(): _send_chat(chat_input.text), "Enviar", 44, Color(0.12, 0.08, 0.02))
	send.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.GOLD, Color(0, 0, 0, 0), 0, Vector4.ZERO, 22))
	send.add_theme_stylebox_override("hover", UIStyle.box(UIStyle.GOLD.lightened(0.12), Color(0, 0, 0, 0), 0, Vector4.ZERO, 22))
	row.add_child(send)
	vb.add_child(row)
	chat_row.visible = false
	root.add_child(chat_row)

func _refresh_chat_log() -> void:
	if not chat_row.visible:
		return
	for c in chat_log_box.get_children():
		c.queue_free()
	var log: Array = GameState.chat_log
	if log.is_empty():
		chat_log_box.add_child(UI.label("As mensagens chegam a quem está na mesma zona e perto de ti.", 12, UIStyle.DIM, "regular", true))
	var me := str(GameState.current_character.get("name", ""))
	for i in range(maxi(0, log.size() - 4), log.size()):
		var m: Dictionary = log[i]
		var line := UI.hbox(6)
		var who := UI.label(str(m["name"]) + ":", 13, UIStyle.GOLD if str(m["name"]) == me else Color(0.62, 0.84, 1.0), "semibold")
		who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(who)
		var tx := UI.label(str(m["text"]), 13, UIStyle.TEXT, "regular", true)
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(tx)
		chat_log_box.add_child(line)
	_layout()

func toggle_chat() -> void:
	chat_row.visible = not chat_row.visible
	if chat_row.visible:
		_close_popup()
		_refresh_chat_log()
		chat_input.grab_focus()
	else:
		chat_input.release_focus()
	_layout()

func _send_chat(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		NetworkManager.send_game("chat", {"text": t})
	chat_input.text = ""
	if DisplayServer.is_touchscreen_available():
		chat_input.release_focus()

# ================================================================== diálogo de confirmação (centrado, fundo ligeiramente escurecido)
func confirm(title: String, text: String, ok_text: String, on_ok: Callable, danger: bool = false) -> void:
	for c in dialog_layer.get_children():
		c.queue_free()
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = root.get_viewport_rect().size
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_dialog())
	dialog_layer.add_child(dim)
	var vs := root.get_viewport_rect().size
	var w := minf(vs.x - 32.0, 340.0)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.surface(0.94, 18, Vector4(18, 16, 18, 14)))
	var vb := UI.vbox(10)
	p.add_child(vb)
	# rótulos com quebra de linha precisam de largura fixa, senão medem-se com 0 px e o painel fica altíssimo
	var t := UI.label(title, 17, UIStyle.TEXT, "bold", true)
	t.custom_minimum_size = Vector2(w - 36.0, 0)
	vb.add_child(t)
	if text != "":
		var tx := UI.label(text, 14, UIStyle.DIM, "regular", true)
		tx.custom_minimum_size = Vector2(w - 36.0, 0)
		vb.add_child(tx)
	var row := UI.hbox(8)
	row.add_child(_grow(UI.button("Cancelar", _close_dialog, "secondary")))
	row.add_child(_grow(UI.button(ok_text, func():
		_close_dialog()
		on_ok.call(), "danger" if danger else "primary")))
	vb.add_child(row)
	p.custom_minimum_size = Vector2(w, 0)
	dialog_layer.add_child(p)
	p.reset_size()
	await get_tree().process_frame
	if is_instance_valid(p):
		p.position = (vs - p.size) / 2.0
		p.pivot_offset = p.size / 2.0
		p.scale = Vector2(0.94, 0.94)
		p.modulate.a = 0.0
		var tw := p.create_tween().set_parallel()
		tw.tween_property(p, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(p, "modulate:a", 1.0, 0.12)

func _close_dialog() -> void:
	for c in dialog_layer.get_children():
		c.queue_free()
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func dialog_open() -> bool:
	return dialog_layer.get_child_count() > 0

# ================================================================== folha contextual
func _build_sheet() -> void:
	popup = PanelContainer.new()
	popup.add_theme_stylebox_override("panel", UIStyle.surface(0.84, 18, Vector4(14, 12, 14, 14)))
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := UI.vbox(10)
	popup.add_child(vb)
	var head := UI.hbox(8)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_title = UI.title("", 17, UIStyle.TEXT, "bold")
	tv.add_child(sheet_title)
	sheet_sub = UI.hbox(6)
	tv.add_child(sheet_sub)
	head.add_child(tv)
	head.add_child(UI.icon_button("x", _close_popup, "Fechar (Esc)", 36, UIStyle.DIM))
	vb.add_child(head)
	sheet_scroll = ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sheet_scroll)
	popup_box = UI.vbox(8)
	popup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_box.mouse_filter = Control.MOUSE_FILTER_PASS
	sheet_scroll.add_child(popup_box)
	popup.visible = false
	root.add_child(popup)

func _sheet_header(title: String, chips: Array = []) -> void:
	sheet_title.text = title
	for c in sheet_sub.get_children():
		c.queue_free()
	for ch in chips:
		sheet_sub.add_child(ch)
	sheet_sub.visible = not chips.is_empty()

func _money_chip() -> PanelContainer:
	return UI.chip(GameState.fmt_kz(int(GameState.self_state.get("money", 0))), UIStyle.GOLD, "wallet", 0.14)

func _close_popup() -> void:
	popup.visible = false
	_popup_target = {}
	_inv_gift = false

func _show_popup() -> void:
	if not popup.visible:
		popup.visible = true
		popup.modulate.a = 0.0
		popup.create_tween().tween_property(popup, "modulate:a", 1.0, 0.14)
	_layout()

## Menu de ações de um objeto (o jogador já está ao lado — o servidor volta a verificar a proximidade).
func show_actions(target: Dictionary) -> void:
	chat_row.visible = false
	_popup_target = {"kind": "actions", "target": target}
	_refresh_popup()

func _open_sub(t: Dictionary) -> void:
	_popup_target = t
	_refresh_popup()

func _refresh_popup() -> void:
	var kind: String = _popup_target.get("kind", "")
	for c in popup_box.get_children():
		c.queue_free()
	match kind:
		"actions":
			_render_actions()
		"shop":
			_render_shop()
		"sell":
			_render_sell()
		"notifications":
			_render_notifications()
		"inventory":
			_render_inventory()
	_show_popup()

func _render_actions() -> void:
	var acts: Dictionary = WorldData.data["activities"]
	var t: Dictionary = _popup_target["target"]
	var obj: Dictionary = t["obj"]
	_sheet_header(WorldData.furniture_name(obj["id"]) if not obj.get("prop", false) else "Banco de jardim")
	for a in t["actions"]:
		var ad: Dictionary = acts[a]
		var fid: String = t["fid"]
		var act: String = a
		var row := UI.hbox(8)
		var b: Button
		if ad.has("shop"):
			b = UI.button(str(ad["label"]), _open_sub.bind({"kind": "shop", "fid": fid, "action": act}), "primary", "cart")
		elif a == "sell":
			b = UI.button("Vender artigos", _open_sub.bind({"kind": "sell", "fid": fid}), "secondary", "coins")
		else:
			b = UI.button(str(ad["label"]), func(): NetworkManager.send_game("interact", {"fid": fid, "action": act}), "primary")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		# requisitos e custo como etiquetas (o servidor decide; aqui só se informa)
		if ad.has("cost"):
			row.add_child(UI.chip(GameState.fmt_kz(int(ad["cost"])), UIStyle.GOLD, "wallet"))
		elif ad.get("requires") == "housing":
			row.add_child(UI.chip("Casa arrendada", UIStyle.INFO, "home"))
		elif ad.get("requires") == "job":
			row.add_child(UI.chip("Emprego aqui", UIStyle.INFO, "job"))
		if ad.has("effects"):
			var eff: Array = []
			for k in ad["effects"]:
				var v := int(ad["effects"][k])
				eff.append(("+" if v > 0 else "") + "%d %s" % [v, UI.NEED_NAMES.get(k, k)])
			b.tooltip_text = ", ".join(eff)
		popup_box.add_child(row)

func _item_row(it: String, title: String, sub: String, right: Control) -> Control:
	var hb := UI.hbox(12)
	var ic := TextureRect.new()
	ic.texture = UI.item_icon(it, 40)
	ic.custom_minimum_size = Vector2(40, 40)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var vb := UI.vbox(2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UI.title(title, 14))
	if sub != "":
		var s := UI.label(sub, 12, UIStyle.DIM, "regular", true)
		vb.add_child(s)
	hb.add_child(vb)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(right)
	return UI.card(hb, Vector4(10, 8, 10, 8))

func _render_shop() -> void:
	var acts: Dictionary = WorldData.data["activities"]
	var items: Dictionary = WorldData.data["items"]
	var money := int(GameState.self_state.get("money", 0))
	var ad: Dictionary = acts[_popup_target["action"]]
	_sheet_header(str(ad["label"]), [_money_chip()])
	for it in ad["shop"]:
		var item: String = it
		var price := int(items[it]["price"])
		var fid: String = _popup_target["fid"]
		var act: String = _popup_target["action"]
		var right := UI.vbox(4)
		var pl := UI.label(GameState.fmt_kz(price), 14, UIStyle.GOLD, "bold")
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(pl)
		var ok := money >= price
		var b := UI.button("Comprar", func(): NetworkManager.send_game("interact", {"fid": fid, "action": act, "item": item, "qty": 1}), "primary", "", ok, "" if ok else "Saldo insuficiente")
		b.custom_minimum_size = Vector2(96, 36)
		right.add_child(b)
		popup_box.add_child(_item_row(item, WorldData.item_name(item), UI.item_description(item, items, acts), right))

func _render_sell() -> void:
	var acts: Dictionary = WorldData.data["activities"]
	var items: Dictionary = WorldData.data["items"]
	var inv: Dictionary = GameState.self_state.get("inventory", {})
	_sheet_header("Vender", [_money_chip()])
	var any := false
	for it in inv:
		var price := int(items.get(it, {}).get("sell", 0))
		if price <= 0:
			continue
		any = true
		var item: String = it
		var fid: String = _popup_target["fid"]
		var right := UI.vbox(4)
		var pl := UI.label("+" + GameState.fmt_kz(price), 14, UIStyle.GOOD, "bold")
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(pl)
		var b := UI.button("Vender 1", func(): NetworkManager.send_game("interact", {"fid": fid, "action": "sell", "item": item}), "secondary")
		b.custom_minimum_size = Vector2(96, 36)
		right.add_child(b)
		popup_box.add_child(_item_row(item, "%s  ×%d" % [WorldData.item_name(it), int(inv[it])], "Compramos artigos usados.", right))
	if not any:
		popup_box.add_child(UI.empty_state("coins", "Nada para vender", "Não tens artigos que esta loja compre."))

# ---------------------------------------------------------------- notificações
const NOTIF_ICON := {"dm": ["chat", Color(0.45, 0.72, 0.98)], "friend_request": ["user", Color(0.95, 0.71, 0.18)], "friend_accepted": ["user", Color(0.4, 0.84, 0.48)],
	"invite": ["home", Color(0.95, 0.71, 0.18)], "invite_reply": ["home", Color(0.4, 0.84, 0.48)], "gift": ["gift", Color(0.95, 0.71, 0.18)], "missed_call": ["phone", Color(0.96, 0.42, 0.36)]}

static func _ago(t: float) -> String:
	var s := Time.get_unix_time_from_system() - t
	if s < 60:
		return "agora"
	if s < 3600:
		return "há %d min" % int(s / 60)
	if s < 86400:
		return "há %d h" % int(s / 3600)
	return "há %d d" % int(s / 86400)

func show_notifications() -> void:
	if popup.visible and _popup_target.get("kind", "") == "notifications":
		_close_popup()
		return
	chat_row.visible = false
	_popup_target = {"kind": "notifications"}
	_new_notifs = {}
	for n in GameState.social.get("notifications", []):         # o que era novo quando abriste fica marcado como "Novas"
		if not bool(n.get("read", false)):
			_new_notifs[str(n.get("nid", n.get("t", "")))] = true
		n["read"] = true
	NetworkManager.send_game("notif_read")
	_refresh_popup()
	_update_badges()

func _render_notifications() -> void:
	var lst: Array = GameState.social.get("notifications", [])
	var nnew := 0
	for n in lst:
		if _new_notifs.has(str(n.get("nid", n.get("t", "")))):
			nnew += 1
	_sheet_header("Notificações", [UI.chip("%d novas" % nnew, UIStyle.GOLD)] if nnew > 0 else [])
	if lst.is_empty():
		popup_box.add_child(UI.empty_state("bell", "Tudo em dia", "Pedidos de amizade, convites, presentes e mensagens aparecem aqui."))
		return
	var shown_old := false
	if nnew > 0:
		popup_box.add_child(UI.caption("Novas"))
	for i in range(lst.size() - 1, maxi(-1, lst.size() - 20), -1):
		var n: Dictionary = lst[i]
		var is_new := _new_notifs.has(str(n.get("nid", n.get("t", ""))))
		if not is_new and not shown_old and nnew > 0:
			popup_box.add_child(UI.caption("Anteriores"))
			shown_old = true
		popup_box.add_child(_notif_row(n, is_new))

func _notif_row(n: Dictionary, is_new: bool) -> Control:
	var kind := str(n.get("kind", ""))
	var look: Array = NOTIF_ICON.get(kind, ["bell", UIStyle.DIM])
	var hb := UI.hbox(10)
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", UIStyle.box(Color(look[1], 0.16), Color(0, 0, 0, 0), 0, Vector4(8, 8, 8, 8), 18))
	ib.add_child(UI.icon(str(look[0]), look[1], 18))
	ib.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(ib)
	var vb := UI.vbox(4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var top := UI.hbox(6)
	var who := str(n.get("from", {}).get("name", "")) if n.get("from") is Dictionary and n.get("from", {}).get("name") != null else ""
	if who != "":
		top.add_child(UI.title(who, 13, UIStyle.TEXT, "bold"))
	else:
		top.add_child(UI.spacer())
	top.add_child(UI.label(_ago(float(n.get("t", 0))), 11, UIStyle.FAINT))
	if is_new:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.GOLD, Color(0, 0, 0, 0), 0, Vector4.ZERO, 4))
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(dot)
	vb.add_child(top)
	vb.add_child(UI.label(str(n.get("text", "")), 13, UIStyle.TEXT if is_new else UIStyle.DIM, "regular", true))
	var nacts: Array = n.get("actions", [])
	var row := UI.hbox(6)
	if "accept" in nacts:
		row.add_child(_small(UI.button("Aceitar", _notif_action.bind(n, "accept"), "primary")))
		row.add_child(_small(UI.button("Recusar", _notif_action.bind(n, "decline"), "secondary")))
	var fp := str(n.get("from", {}).get("pub", "")) if n.get("from") is Dictionary else ""
	if kind in ["dm", "gift", "friend_accepted", "invite_reply"] and fp != "":
		row.add_child(_small(UI.button("Conversar", _open_dm.bind(fp, who), "secondary", "chat")))
	if kind == "missed_call" and fp != "":
		row.add_child(_small(UI.button("Ligar", _call_back.bind(fp, who), "secondary", "phone")))
	if row.get_child_count() > 0:
		vb.add_child(row)
	return UI.card(hb, Vector4(10, 10, 12, 10), Color(1, 1, 1, 0.08) if is_new else Color(1, 1, 1, 0.03))

func _small(b: Button) -> Button:
	b.custom_minimum_size = Vector2(0, 36)
	return b

func _notif_action(n: Dictionary, action: String) -> void:
	var kind := str(n.get("kind", ""))
	var from_pub := str(n.get("from", {}).get("pub", ""))
	n["actions"] = []
	match kind:
		"friend_request":
			NetworkManager.send_game("friend_accept" if action == "accept" else "friend_decline", {"target": from_pub})
		"invite":
			NetworkManager.send_game("invite_respond", {"iid": n.get("data", {}).get("iid", ""), "accept": action == "accept"})
	_refresh_popup()

func _open_dm(pub: String, name: String) -> void:
	_close_popup()
	phone.open_conversation(pub, name)

func _call_back(pub: String, name: String) -> void:
	_close_popup()
	voice.call_player(pub, name)

# ---------------------------------------------------------------- mochila
func show_inventory() -> void:
	if popup.visible and _popup_target.get("kind", "") == "inventory":
		_close_popup()
		return
	chat_row.visible = false
	_popup_target = {"kind": "inventory"}
	_inv_gift = false
	_refresh_popup()

func _render_inventory() -> void:
	var items: Dictionary = WorldData.data["items"]
	var acts: Dictionary = WorldData.data["activities"]
	var inv: Dictionary = GameState.self_state.get("inventory", {})
	var total := 0
	for it in inv:
		total += int(inv[it])
	_sheet_header("Mochila", [_money_chip(), UI.chip("%d artigo%s" % [total, "" if total == 1 else "s"], UIStyle.DIM, "bag")])
	if inv.is_empty():
		popup_box.add_child(UI.empty_state("bag", "A mochila está vazia", "Compra comida e artigos na Mercearia Girassol ou no Restaurante Maianga."))
		return
	if _inv_sel == "" or not inv.has(_inv_sel):
		_inv_sel = str(inv.keys()[0])
	# grelha de espaços (como num inventário de jogo)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	popup_box.add_child(grid)
	var slots := maxi(8, int(ceil(inv.size() / 4.0)) * 4)
	var keys := inv.keys()
	for i in slots:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(70, 70)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.focus_mode = Control.FOCUS_NONE
		var sel := i < keys.size() and str(keys[i]) == _inv_sel
		var st := UIStyle.box(Color(1, 1, 1, 0.1) if sel else Color(1, 1, 1, 0.04), Color(UIStyle.GOLD, 0.9) if sel else UIStyle.STROKE, 2 if sel else 1, Vector4.ZERO, 12)
		for s in ["normal", "hover", "pressed", "disabled"]:
			slot.add_theme_stylebox_override(s, st)
		slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if i < keys.size():
			var id := str(keys[i])
			slot.icon = UI.item_icon(id, 42)
			slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			slot.tooltip_text = WorldData.item_name(id)
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			slot.pressed.connect(func():
				_inv_sel = id
				_inv_gift = false
				_refresh_popup())
			var q := UI.label("×%d" % int(inv[id]), 11, UIStyle.TEXT, "bold")
			q.add_theme_stylebox_override("normal", UIStyle.box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, Vector4(5, 0, 5, 0), 8))
			q.position = Vector2(6, 48)
			slot.add_child(q)
		else:
			slot.disabled = true
		grid.add_child(slot)
	# detalhe do artigo escolhido com ações contextuais
	var it: String = _inv_sel
	var d := UI.vbox(8)
	var hd := UI.hbox(10)
	var ic := TextureRect.new()
	ic.texture = UI.item_icon(it, 44)
	ic.custom_minimum_size = Vector2(44, 44)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hd.add_child(ic)
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.title(WorldData.item_name(it), 15, UIStyle.TEXT, "bold"))
	tv.add_child(UI.label("Quantidade: %d" % int(inv[it]), 12, UIStyle.DIM))
	hd.add_child(tv)
	d.add_child(hd)
	d.add_child(UI.label(UI.item_description(it, items, acts), 13, UIStyle.DIM, "regular", true))
	var can_eat: bool = items.get(it, {}).has("eat")
	var row := UI.hbox(8)
	row.add_child(_grow(UI.button("Consumir", func(): NetworkManager.send_game("use_item", {"item": it}), "primary", "food", can_eat,
		"" if can_eat else "Não é comestível")))
	row.add_child(_grow(UI.button("Oferecer…", func():
		_inv_gift = not _inv_gift
		_refresh_popup(), "secondary", "gift")))
	d.add_child(row)
	if not can_eat:
		d.add_child(UI.label("Este artigo não se consome diretamente.", 11, UIStyle.FAINT, "regular", true))
	if _inv_gift:
		d.add_child(_gift_picker(it))
	popup_box.add_child(UI.card(d, Vector4(12, 12, 12, 12), Color(1, 1, 1, 0.05)))

## Oferecer um artigo a um amigo (o mesmo pedido gift_item do perfil social; o servidor valida tudo).
func _gift_picker(item: String) -> Control:
	var v := UI.vbox(6)
	v.add_child(UI.caption("Oferecer a"))
	var fr: Array = GameState.social.get("friends", [])
	if fr.is_empty():
		v.add_child(UI.label("Sem amigos ainda. Também podes oferecer tocando num jogador no mundo.", 12, UIStyle.DIM, "regular", true))
		return v
	for f in fr:
		var pub := str(f["pub"])
		var nm := str(f["name"])
		var b := UI.button(nm + ("  · online" if f.get("online", false) else ""), func():
			confirm("Oferecer %s?" % WorldData.item_name(item), "Vais oferecer 1 × %s a %s. Os presentes não podem ser anulados." % [WorldData.item_name(item), nm], "Oferecer",
				func():
					NetworkManager.send_game("gift_item", {"target": pub, "item": item, "qty": 1, "req_id": "%x%x" % [Time.get_ticks_usec(), randi()]})
					_inv_gift = false
					_refresh_popup()), "ghost", "user")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	return v

# ================================================================== layout responsivo
func _layout() -> void:
	var vs := root.get_viewport_rect().size
	compact = vs.x < 760.0
	var m := 8.0 if compact else 14.0
	# cartão do jogador e faixa do mundo
	avatar.visible = true
	lbl_loc_card.visible = compact
	loc_row.visible = not compact
	lbl_xp.visible = not compact
	for k in need_bars:
		(need_bars[k] as ProgressBar).custom_minimum_size = Vector2(30 if compact else 46, 5)
	card.position = Vector2(m, m)
	card.size = Vector2.ZERO
	card.custom_minimum_size = Vector2(0 if compact else 270, 0)
	info.size = Vector2.ZERO
	dock.size = Vector2.ZERO
	zoom_box.size = Vector2.ZERO
	await get_tree().process_frame
	if compact:
		# telemóvel: faixa do mundo à direita do cartão se couber, senão por baixo
		if card.size.x + info.size.x + 3 * m <= vs.x:
			info.position = Vector2(vs.x - info.size.x - m, m)
		else:
			info.position = Vector2(m, card.position.y + card.size.y + 6)
	else:
		info.position = Vector2(vs.x - info.size.x - m, m)
	dock.position = Vector2(vs.x - dock.size.x - m, vs.y - dock.size.y - m)
	zoom_box.position = Vector2(m, vs.y - zoom_box.size.y - m)
	floor_panel.size = Vector2.ZERO
	floor_panel.position = Vector2(m, (vs.y - floor_panel.size.y) * 0.5)
	var top_band := maxf(card.position.y + card.size.y, info.position.y + info.size.y) + 8.0
	call_card.custom_minimum_size = Vector2(minf(vs.x - 2 * m, 340.0), 0)
	call_card.size = Vector2.ZERO
	call_card.position = Vector2((vs.x - call_card.custom_minimum_size.x) * 0.5, top_band if compact else m)
	# zona de baixo ao centro: ação contextual / atividade / conversa
	var bottom_y := vs.y - m - (dock.size.y + 8.0 if compact else 0.0)
	prompt.size = Vector2.ZERO
	prompt.position = Vector2((vs.x - prompt.size.x) * 0.5, bottom_y - prompt.size.y - (0.0 if compact else 4.0))
	act_panel.size = Vector2.ZERO
	act_panel.position = Vector2((vs.x - act_panel.size.x) * 0.5, bottom_y - act_panel.size.y)
	var cw := minf(vs.x - 2 * m, 460.0)
	chat_row.custom_minimum_size = Vector2(cw, 0)
	chat_row.size = Vector2.ZERO
	chat_row.position = Vector2((vs.x - cw) * 0.5, bottom_y - chat_row.size.y - (prompt.size.y + 10 if prompt.visible else 0.0))
	toast.custom_minimum_size = Vector2(minf(vs.x - 2 * m, 420.0), 0)
	toast.size = Vector2.ZERO
	toast.position = Vector2((vs.x - toast.custom_minimum_size.x) * 0.5, top_band if compact else m + 4)
	if call_card.visible and not compact:
		toast.position.y = call_card.position.y + call_card.size.y + 8
	_place_sheet(vs, m, top_band, bottom_y)

## Topo da área livre para painéis (abaixo do cartão do jogador e da faixa do mundo).
func content_top() -> float:
	return maxf(card.position.y + card.size.y, info.position.y + info.size.y) + 8.0

## Folha contextual: popover pequeno para ações de objetos; folha flutuante por cima do dock no computador;
## folha de baixo (largura total, altura limitada) no telemóvel. Nunca cobre o ecrã todo nem o cartão do jogador.
func _place_sheet(vs: Vector2, m: float, top_band: float, bottom_y: float) -> void:
	if not popup.visible:
		return
	var kind: String = _popup_target.get("kind", "")
	var w: float
	var bottom: float
	if compact:
		w = vs.x - 2 * m
		bottom = minf(bottom_y, zoom_box.position.y) - 6.0      # nunca por cima do zoom nem do dock
	elif kind == "actions":
		w = 340.0
		bottom = vs.y - 120.0
	else:
		w = 400.0
		bottom = vs.y - dock.size.y - m - 10.0
	var max_h := (bottom - top_band - 8.0) if compact else minf(vs.y * 0.66, bottom - m)
	popup.custom_minimum_size = Vector2(w, 0)
	var content_h := popup_box.get_combined_minimum_size().y
	sheet_scroll.custom_minimum_size = Vector2(w - 28.0, minf(content_h, maxf(120.0, max_h - 80.0)))
	popup.size = Vector2.ZERO
	var s := popup.get_combined_minimum_size()
	var x := (vs.x - s.x) * 0.5 if (compact or kind == "actions") else vs.x - s.x - m
	popup.position = Vector2(x, bottom - s.y)

# ================================================================== dados
func set_character(ch: Dictionary) -> void:
	lbl_name.text = str(ch.get("name", ""))
	var v: Node2D = avatar.get_meta("visual")
	v.apply_appearance(ch.get("appearance", {}))

func set_location(text: String) -> void:
	lbl_loc.text = text
	lbl_loc_card.text = text
	_layout()

func set_prompt(text: String) -> void:
	var show := text != "" and not act_panel.visible
	if prompt.visible != show or prompt.text != text:
		prompt.text = text
		prompt.visible = show
		_layout()

func _on_self() -> void:
	var st: Dictionary = GameState.self_state
	if st.is_empty():
		return
	lbl_money.text = GameState.fmt_kz(int(st.get("money", 0)))
	var lv: Dictionary = st.get("level", {})
	(lvl_chip.find_child("Text", true, false) as Label).text = "Nv %d" % int(lv.get("level", 1))
	var into := int(lv.get("into", 0))
	var need := maxi(1, int(lv.get("need", 1)))
	xp_bar.value = 100.0 * into / need
	xp_bar.tooltip_text = "Experiência: %d / %d XP para o nível %d" % [into, need, int(lv.get("level", 1)) + 1]
	lbl_xp.text = "%d/%d XP" % [into, need]
	var needs: Dictionary = st.get("needs", {})
	for k in need_bars:
		var v := float(needs.get(k, 0))
		var bar: ProgressBar = need_bars[k]
		bar.value = v
		bar.tooltip_text = "%s: %d%%" % [_need_name(k), int(v)]
		var low := v < 20.0
		(need_vals[k] as Label).text = "%d" % int(v)
		(need_vals[k] as Label).add_theme_color_override("font_color", UIStyle.BAD if low else UIStyle.TEXT)
	if st.get("activity") == null and not act_panel.visible:
		lbl_status.text = _mood(needs)
	if popup.visible and _popup_target.get("kind", "") in ["inventory", "sell", "shop"]:
		_refresh_popup()

func _need_name(k: String) -> String:
	for s in NEED_ORDER:
		if s[0] == k:
			return s[1]
	return k

func _mood(needs: Dictionary) -> String:
	var worst := ""
	var wv := 101.0
	for s in NEED_ORDER:
		var v := float(needs.get(s[0], 100))
		if v < wv:
			wv = v
			worst = s[0]
	if wv >= 35.0:
		return "Bem disposto"
	return {"hunger": "Com fome", "energy": "Cansado", "hygiene": "Precisa de banho", "health": "Doente"}.get(worst, "")

func _on_msg(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"notice":
			notify(str(msg.get("text", "")), bool(msg.get("ok", true)))
		"activity_started":
			_close_popup()
			_act_total = float(msg.get("secs", 1.0))
			_act_left = _act_total
			act_label.text = str(msg.get("status", "")) + "…"
			lbl_status.text = str(msg.get("status", ""))
			act_panel.visible = true
			prompt.visible = false
			_layout()
		"activity_done":
			act_panel.visible = false
			lbl_status.text = _mood(GameState.self_state.get("needs", {}))
			notify(str(msg.get("text", "")), msg.get("action") != null)
			_layout()
		"notification":
			phone.on_notification(msg.get("data", {}))       # faixa estilo telemóvel (respeita Não incomodar)
		"social_result":
			if str(msg.get("text", "")) != "":
				notify(str(msg.get("text", "")), bool(msg.get("ok", false)))
			var inv: Variant = msg.get("invite")
			if bool(msg.get("ok", false)) and inv is Dictionary and str(inv.get("state", "")) == "accepted" and inv.get("building") != null:
				guide_requested.emit(str(inv["building"]))
		"profile":
			phone.show_profile(msg.get("data", {}))

func _process(delta: float) -> void:
	lbl_clock.text = GameState.clock_text()
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast.visible = false
	if act_panel.visible:
		_act_left = maxf(0.0, _act_left - delta)
		var pct := 1.0 - _act_left / maxf(_act_total, 0.01)
		act_bar.value = 100.0 * pct
		act_pct.text = "%d%%" % int(pct * 100.0)

# ================================================================== modais e Esc
func is_modal_open() -> bool:
	return popup.visible or phone.visible or chat_row.visible or social_panel.visible or dialog_open()

func toggle_phone() -> void:
	if phone.visible:
		phone.close()
	else:
		_close_popup()
		chat_row.visible = false
		phone.open()

func close_all() -> bool:
	## Esc: fecha a camada de cima. Devolve true se fechou alguma coisa.
	if dialog_open():
		_close_dialog()
		return true
	if social_panel.visible:
		social_panel.close()
		return true
	if phone.visible:
		phone.escape()
		return true
	if popup.visible:
		_close_popup()
		return true
	if chat_row.visible:
		toggle_chat()
		return true
	return false

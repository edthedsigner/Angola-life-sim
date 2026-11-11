extends CanvasLayer
## HUD do JOGADOR (só informação com significado para quem joga). Toda a informação técnica vive no DebugOverlay (F3),
## que é um nó independente — este ficheiro não sabe nada dele.
## Layout adaptável: em ecrãs estreitos (telemóvel) os painéis encolhem e os botões continuam ≥ 48 px.

signal prompt_pressed
signal floor_selected(level: int)
signal zoom_step(factor: float)

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Icons = preload("res://client/scripts/Icons.gd")
const Phone = preload("res://client/scripts/Phone.gd")
const VISUAL_SCENE := preload("res://client/scenes/CharacterVisual.tscn")
const NEED_ORDER := [["hunger", "Fome", "food", Color(0.93, 0.62, 0.22)], ["energy", "Energia", "zap", Color(0.95, 0.85, 0.3)],
	["hygiene", "Higiene", "drop", Color(0.4, 0.75, 0.95)], ["health", "Saúde", "heart", Color(0.9, 0.35, 0.35)]]

var root: Control
var card: PanelContainer
var avatar_box: Control
var avatar: Node2D
var lbl_name: Label
var lbl_loc: Label
var lbl_status: Label
var need_bars: Dictionary = {}
var top_right: PanelContainer
var lbl_clock: Label
var lbl_money: Label
var dock: HBoxContainer
var zoom_box: VBoxContainer
var prompt: Button
var act_panel: PanelContainer
var act_label: Label
var act_bar: ProgressBar
var floor_panel: PanelContainer
var floor_box: VBoxContainer
var floor_btns: Dictionary = {}
var toast: PanelContainer
var toast_label: Label
var _toast_t := 0.0
var popup: PanelContainer
var popup_box: VBoxContainer
var chat_row: HBoxContainer
var chat_input: LineEdit
var phone: Control
var compact := false
var _act_total := 0.0
var _act_left := 0.0
var _popup_target: Dictionary = {}

func _ready() -> void:
	layer = 10
	add_to_group("hud")
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.make_theme()
	add_child(root)
	_build_card()
	_build_top_right()
	_build_dock()
	_build_zoom()
	_build_prompt()
	_build_floor_picker()
	_build_toast()
	_build_popup()
	_build_chat()
	phone = Phone.new()
	root.add_child(phone)
	get_viewport().size_changed.connect(_layout)
	GameState.self_changed.connect(_on_self)
	NetworkManager.game_message.connect(_on_msg)
	_layout()
	_on_self()

# ------------------------------------------------------------------ construção
func _icon(name: String, col: Color = UIStyle.TEXT, px: int = 18) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, col, px)
	t.custom_minimum_size = Vector2(px, px)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _label(text: String, size: int, col: Color = UIStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _margin(c: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.add_child(c)
	return m

func _build_card() -> void:
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	card.add_child(_margin(hb, 10, 8))
	avatar_box = Control.new()
	avatar_box.custom_minimum_size = Vector2(52, 62)
	avatar_box.clip_contents = true
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fs := UIStyle.box(Color(0.16, 0.2, 0.17), UIStyle.GOLD, 2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_box.add_child(frame)
	avatar = VISUAL_SCENE.instantiate()
	avatar.scale = Vector2(2, 2)
	avatar.position = Vector2(26, 86)
	avatar_box.add_child(avatar)
	hb.add_child(avatar_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	lbl_name = _label("", 16, UIStyle.GOLD)
	vb.add_child(lbl_name)
	lbl_loc = _label("", 12, UIStyle.DIM)
	vb.add_child(lbl_loc)
	lbl_status = _label("", 12, Color(0.7, 0.88, 1.0))
	vb.add_child(lbl_status)
	var needs := GridContainer.new()
	needs.columns = 2
	needs.add_theme_constant_override("h_separation", 10)
	needs.add_theme_constant_override("v_separation", 3)
	vb.add_child(needs)
	for spec in NEED_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.tooltip_text = spec[1]
		row.add_child(_icon(spec[2], spec[3], 14))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100
		bar.custom_minimum_size = Vector2(58, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", UIStyle.box(Color(0.1, 0.1, 0.11), Color(0.3, 0.29, 0.27), 1, Vector4.ZERO))
		bar.add_theme_stylebox_override("fill", UIStyle.box(spec[3], spec[3].darkened(0.3), 1, Vector4.ZERO))
		bar.tooltip_text = spec[1]
		row.add_child(bar)
		needs.add_child(row)
		need_bars[spec[0]] = bar

func _build_top_right() -> void:
	top_right = PanelContainer.new()
	root.add_child(top_right)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	top_right.add_child(_margin(hb, 12, 8))
	hb.add_child(_icon("clock", UIStyle.TEXT, 16))
	lbl_clock = _label("", 14)
	hb.add_child(lbl_clock)
	var sep := VSeparator.new()
	hb.add_child(sep)
	hb.add_child(_icon("wallet", UIStyle.GOLD, 16))
	lbl_money = _label("", 14, UIStyle.GOLD)
	hb.add_child(lbl_money)

func _icon_button(icon: String, tip: String, cb: Callable, size: int = 56) -> Button:
	var b := Button.new()
	b.icon = Icons.tex(icon, UIStyle.TEXT, 26)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _build_dock() -> void:
	dock = HBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	root.add_child(dock)
	dock.add_child(_icon_button("chat", "Falar (Enter)", toggle_chat))
	dock.add_child(_icon_button("bag", "Mochila (I)", show_inventory))
	dock.add_child(_icon_button("phone", "Telemóvel (Tab)", toggle_phone))

func _build_zoom() -> void:
	zoom_box = VBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 6)
	root.add_child(zoom_box)
	zoom_box.add_child(_icon_button("plus", "Aproximar (+ / roda / pinça)", func(): zoom_step.emit(1.25), 46))
	zoom_box.add_child(_icon_button("minus", "Afastar (-)", func(): zoom_step.emit(0.8), 46))

func _build_prompt() -> void:
	prompt = Button.new()
	prompt.theme_type_variation = "PrimaryButton"
	prompt.custom_minimum_size = Vector2(0, 48)
	prompt.focus_mode = Control.FOCUS_NONE
	prompt.icon = Icons.tex("enter", Color(0.1, 0.06, 0.02), 20)
	prompt.pressed.connect(func(): prompt_pressed.emit())
	prompt.visible = false
	root.add_child(prompt)
	act_panel = PanelContainer.new()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	act_panel.add_child(_margin(vb, 14, 10))
	act_label = _label("", 14)
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(act_label)
	act_bar = ProgressBar.new()
	act_bar.show_percentage = false
	act_bar.custom_minimum_size = Vector2(220, 10)
	act_bar.add_theme_stylebox_override("background", UIStyle.box(Color(0.1, 0.1, 0.11), Color(0.3, 0.29, 0.27), 1, Vector4.ZERO))
	act_bar.add_theme_stylebox_override("fill", UIStyle.box(UIStyle.GOLD, UIStyle.GOLD.darkened(0.3), 1, Vector4.ZERO))
	vb.add_child(act_bar)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.custom_minimum_size = Vector2(0, 40)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): NetworkManager.send_game("cancel_activity"))
	vb.add_child(cancel)
	act_panel.visible = false
	root.add_child(act_panel)

func _build_floor_picker() -> void:
	floor_panel = PanelContainer.new()
	floor_box = VBoxContainer.new()
	floor_box.add_theme_constant_override("separation", 6)
	floor_panel.add_child(_margin(floor_box, 6, 6))
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
		return
	var t := _label("Piso", 11, UIStyle.DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_box.add_child(t)
	for lv in range(count - 1, -1, -1):
		var b := Button.new()
		b.text = str(lv)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(48, 48)
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = lv == current
		var lvl := lv
		b.pressed.connect(func(): floor_selected.emit(lvl))
		floor_box.add_child(b)
		floor_btns[lv] = b

func sync_floor(current: int) -> void:
	for k in floor_btns:
		floor_btns[k].set_pressed_no_signal(k == current)

func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = _label("", 14)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(_margin(toast_label, 14, 8))
	toast.visible = false
	root.add_child(toast)

func notify(text: String, ok: bool = true, secs: float = 3.2) -> void:
	print("[Aviso] ", text)
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", UIStyle.TEXT if ok else Color(1.0, 0.72, 0.62))
	toast.visible = true
	_toast_t = secs
	_layout()

func _build_popup() -> void:
	popup = PanelContainer.new()
	popup_box = VBoxContainer.new()
	popup_box.add_theme_constant_override("separation", 8)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(300, 0)
	popup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(popup_box)
	popup.add_child(_margin(sc, 16, 12))
	popup.visible = false
	root.add_child(popup)

func _build_chat() -> void:
	chat_row = HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	var box := PanelContainer.new()
	box.theme_type_variation = "FieldBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Diz algo a quem está perto…"
	chat_input.max_length = 120
	chat_input.text_submitted.connect(_send_chat)
	box.add_child(chat_input)
	chat_row.add_child(box)
	var send := _icon_button("send", "Enviar", func(): _send_chat(chat_input.text), 48)
	chat_row.add_child(send)
	chat_row.visible = false
	root.add_child(chat_row)

# ------------------------------------------------------------------ layout responsivo
func _layout() -> void:
	var vs := root.get_viewport_rect().size
	compact = vs.x < 760.0
	var m := 8.0 if compact else 12.0
	avatar_box.visible = not compact
	for k in need_bars:
		(need_bars[k] as ProgressBar).custom_minimum_size = Vector2(44 if compact else 58, 8)
	card.position = Vector2(m, m)
	card.size = Vector2.ZERO
	top_right.size = Vector2.ZERO
	await get_tree().process_frame
	if compact:
		top_right.position = Vector2(m, card.position.y + card.size.y + 6)
	else:
		top_right.position = Vector2(vs.x - top_right.size.x - m, m)
	dock.size = Vector2.ZERO
	dock.position = Vector2(vs.x - dock.size.x - m, vs.y - dock.size.y - m)
	zoom_box.size = Vector2.ZERO
	zoom_box.position = Vector2(m, vs.y - zoom_box.size.y - m)
	floor_panel.size = Vector2.ZERO
	floor_panel.position = Vector2(m, (vs.y - floor_panel.size.y) * 0.5)
	var bottom_y := vs.y - m - (dock.size.y + 8.0 if compact else 0.0)
	prompt.size = Vector2.ZERO
	prompt.position = Vector2((vs.x - prompt.size.x) * 0.5, bottom_y - prompt.size.y - (0.0 if compact else 4.0))
	act_panel.size = Vector2.ZERO
	act_panel.position = Vector2((vs.x - act_panel.size.x) * 0.5, bottom_y - act_panel.size.y)
	var cw := minf(vs.x - 2 * m, 520.0)
	chat_row.size = Vector2(cw, 48)
	chat_row.position = Vector2((vs.x - cw) * 0.5, bottom_y - 48 - (prompt.size.y + 10 if prompt.visible else 0.0))
	toast.size = Vector2.ZERO
	toast.custom_minimum_size = Vector2(minf(vs.x - 2 * m, 460.0), 0)
	toast.position = Vector2((vs.x - toast.custom_minimum_size.x) * 0.5, (top_right.position.y + top_right.size.y + 8) if compact else m + 4)
	popup.size = Vector2.ZERO
	var pw := minf(vs.x - 2 * m, 380.0)
	popup.custom_minimum_size = Vector2(pw, 0)
	(popup.get_child(0).get_child(0) as ScrollContainer).custom_minimum_size = Vector2(pw - 32, minf(popup_box.get_combined_minimum_size().y, vs.y * 0.6))
	popup.position = (vs - popup.get_combined_minimum_size()) * 0.5

# ------------------------------------------------------------------ dados
func set_character(ch: Dictionary) -> void:
	lbl_name.text = str(ch.get("name", ""))
	avatar.apply_appearance(ch.get("appearance", {}))

func set_location(text: String) -> void:
	lbl_loc.text = text

func set_prompt(text: String) -> void:
	var show := text != "" and not act_panel.visible
	if prompt.visible != show or prompt.text != " " + text:
		prompt.text = " " + text
		prompt.visible = show
		_layout()

func _on_self() -> void:
	var st: Dictionary = GameState.self_state
	if st.is_empty():
		return
	lbl_money.text = GameState.fmt_kz(int(st.get("money", 0)))
	var needs: Dictionary = st.get("needs", {})
	for k in need_bars:
		var v := float(needs.get(k, 0))
		var bar: ProgressBar = need_bars[k]
		bar.value = v
		bar.tooltip_text = "%s: %d%%" % [_need_name(k), int(v)]
		bar.modulate = Color(1, 0.55, 0.55) if v < 20.0 else Color.WHITE
	if st.get("activity") == null and not act_panel.visible:
		lbl_status.text = _mood(needs)
	if popup.visible and _popup_target.get("kind", "") in ["inventory", "sell"]:
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
		act_bar.value = 100.0 * (1.0 - _act_left / maxf(_act_total, 0.01))

# ------------------------------------------------------------------ menus de interação
func is_modal_open() -> bool:
	return popup.visible or phone.visible or chat_row.visible

func _clear_popup() -> void:
	for c in popup_box.get_children():
		c.queue_free()

func _popup_title(text: String, sub: String = "") -> void:
	var t := _label(text, 17, UIStyle.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup_box.add_child(t)
	if sub != "":
		var s := _label(sub, 12, UIStyle.DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup_box.add_child(s)
	popup_box.add_child(HSeparator.new())

func _popup_button(text: String, cb: Callable, primary: bool = false, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	popup_box.add_child(b)
	return b

func _row(left: String, right: String, btn: String, cb: Callable, enabled: bool = true) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var l := _label(left, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(l)
	hb.add_child(_label(right, 13, UIStyle.GOLD))
	var b := Button.new()
	b.text = btn
	b.custom_minimum_size = Vector2(92, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.pressed.connect(cb)
	hb.add_child(b)
	popup_box.add_child(hb)

func _show_popup() -> void:
	popup.visible = true
	_layout()

func _close_popup() -> void:
	popup.visible = false
	_popup_target = {}

## Menu de ações de um objeto (o jogador já está ao lado — o servidor volta a verificar a proximidade).
func show_actions(target: Dictionary) -> void:
	_popup_target = {"kind": "actions", "target": target}
	_refresh_popup()

func _refresh_popup() -> void:
	var kind: String = _popup_target.get("kind", "")
	_clear_popup()
	var acts: Dictionary = WorldData.data["activities"]
	var items: Dictionary = WorldData.data["items"]
	var inv: Dictionary = GameState.self_state.get("inventory", {})
	var money := int(GameState.self_state.get("money", 0))
	match kind:
		"actions":
			var t: Dictionary = _popup_target["target"]
			var obj: Dictionary = t["obj"]
			_popup_title(WorldData.furniture_name(obj["id"]) if not obj.get("prop", false) else "Banco de jardim")
			for a in t["actions"]:
				var ad: Dictionary = acts[a]
				var fid: String = t["fid"]
				var act: String = a
				if ad.has("shop"):
					_popup_button(ad["label"] + "…", _open_sub.bind({"kind": "shop", "fid": fid, "action": act}), true)
				elif a == "sell":
					_popup_button("Vender…", _open_sub.bind({"kind": "sell", "fid": fid}))
				else:
					var extra := ""
					if ad.has("cost"):
						extra = " (%s)" % GameState.fmt_kz(int(ad["cost"]))
					elif ad.get("requires") == "housing":
						extra = " (casa arrendada)"
					elif ad.get("requires") == "job":
						extra = " (emprego aqui)"
					_popup_button(str(ad["label"]) + extra, func(): NetworkManager.send_game("interact", {"fid": fid, "action": act}), true)
		"shop":
			var ad2: Dictionary = acts[_popup_target["action"]]
			_popup_title(str(ad2["label"]), "Saldo: " + GameState.fmt_kz(money))
			for it in ad2["shop"]:
				var item: String = it
				var price := int(items[it]["price"])
				var fid2: String = _popup_target["fid"]
				var act2: String = _popup_target["action"]
				_row(WorldData.item_name(it), GameState.fmt_kz(price), "Comprar", func(): NetworkManager.send_game("interact", {"fid": fid2, "action": act2, "item": item, "qty": 1}), money >= price)
		"sell":
			_popup_title("Vender", "Compramos alguns artigos usados.")
			var any := false
			for it in inv:
				var price3 := int(items.get(it, {}).get("sell", 0))
				if price3 <= 0:
					continue
				any = true
				var item3: String = it
				var fid3: String = _popup_target["fid"]
				_row("%s ×%d" % [WorldData.item_name(it), int(inv[it])], GameState.fmt_kz(price3), "Vender", func(): NetworkManager.send_game("interact", {"fid": fid3, "action": "sell", "item": item3}))
			if not any:
				popup_box.add_child(_label("Não tens nada que possamos comprar.", 13, UIStyle.DIM))
		"inventory":
			_popup_title("Mochila", "Saldo: " + GameState.fmt_kz(money))
			if inv.is_empty():
				var e := _label("Está vazia. Compra comida na Mercearia Girassol ou no Restaurante Maianga.", 13, UIStyle.DIM)
				e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				popup_box.add_child(e)
			for it in inv:
				var item4: String = it
				var eat: Variant = items.get(it, {}).get("eat")
				_row("%s ×%d" % [WorldData.item_name(it), int(inv[it])], "", "Consumir" if eat else "—", func(): NetworkManager.send_game("use_item", {"item": item4}), eat != null)
	_popup_button("Fechar", _close_popup)
	_show_popup()

func _open_sub(t: Dictionary) -> void:
	_popup_target = t
	_refresh_popup()

func show_inventory() -> void:
	if popup.visible and _popup_target.get("kind", "") == "inventory":
		_close_popup()
		return
	_popup_target = {"kind": "inventory"}
	_refresh_popup()

# ------------------------------------------------------------------ chat / telemóvel
func toggle_chat() -> void:
	chat_row.visible = not chat_row.visible
	_layout()
	if chat_row.visible:
		chat_input.grab_focus()
	else:
		chat_input.release_focus()

func _send_chat(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		NetworkManager.send_game("chat", {"text": t})
	chat_input.text = ""
	chat_row.visible = false
	chat_input.release_focus()
	_layout()

func toggle_phone() -> void:
	if phone.visible:
		phone.close()
	else:
		_close_popup()
		phone.open()

func close_all() -> bool:
	## Esc: fecha a camada de cima. Devolve true se fechou alguma coisa.
	if phone.visible:
		phone.close()
		return true
	if popup.visible:
		_close_popup()
		return true
	if chat_row.visible:
		toggle_chat()
		return true
	return false

extends Control
## Telemóvel (restaurado do original v0.6): ecrã inicial com relógio + apps Banco, Mensagens, Emprego, Imóveis,
## Negócios, Governo — agora com dados reais do servidor — e Definições (sessão / debug, acessível por toque).
## Todas as ações passam pelo servidor (NetworkManager.send_game); o telemóvel nunca altera estado localmente.

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Icons = preload("res://client/scripts/Icons.gd")
signal call_requested(pub: String, name: String)

const APPS := [["Banco", "bank"], ["Mensagens", "chat"], ["Amigos", "user"], ["Emprego", "job"], ["Imóveis", "home"], ["Negócios", "shop"], ["Governo", "gov"], ["Definições", "gear"]]
const SCREEN := Color(0.09, 0.1, 0.12)

var device: PanelContainer
var lbl_time: Label
var home: GridContainer
var app_view: VBoxContainer
var app_title: Label
var app_body: VBoxContainer
var current_app := ""
var msg_tab := "conversas"          # conversas (privadas, persistentes) | perto (chat de proximidade)
var conv_pub := ""
var conv_name := ""
var dm_row: HBoxContainer
var dm_input: LineEdit
var app_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _profile: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	device = PanelContainer.new()
	device.add_theme_stylebox_override("panel", _round(Color(0.05, 0.05, 0.06), UIStyle.GOLD.darkened(0.35), 14, 10))
	cc.add_child(device)
	var screen := PanelContainer.new()
	screen.add_theme_stylebox_override("panel", _round(SCREEN, Color(0.2, 0.2, 0.22), 8, 12))
	device.add_child(screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	screen.add_child(vb)
	var bar := HBoxContainer.new()
	vb.add_child(bar)
	lbl_time = _l("", 13)
	lbl_time.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(lbl_time)
	var op := _l("Unitel  4G", 11, UIStyle.DIM)
	op.autowrap_mode = TextServer.AUTOWRAP_OFF
	bar.add_child(op)
	home = GridContainer.new()
	home.columns = 3
	home.add_theme_constant_override("h_separation", 8)
	home.add_theme_constant_override("v_separation", 8)
	home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(home)
	for a in APPS:
		var b := Button.new()
		b.text = a[0]
		b.icon = Icons.tex(a[1], UIStyle.GOLD, 28)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 76)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(open_app.bind(a[0]))
		home.add_child(b)
		app_buttons[a[0]] = b
	app_view = VBoxContainer.new()
	app_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app_view.add_theme_constant_override("separation", 8)
	vb.add_child(app_view)
	var hb := HBoxContainer.new()
	app_view.add_child(hb)
	var back := Button.new()
	back.icon = Icons.tex("back", UIStyle.TEXT, 20)
	back.custom_minimum_size = Vector2(44, 44)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_back)
	hb.add_child(back)
	app_title = _l("", 18, UIStyle.GOLD)
	app_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	app_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(app_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app_view.add_child(sc)
	_scroll = sc
	app_body = VBoxContainer.new()
	app_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_body.add_theme_constant_override("separation", 8)
	sc.add_child(app_body)
	dm_row = HBoxContainer.new()
	dm_row.add_theme_constant_override("separation", 6)
	var fb := PanelContainer.new()
	fb.theme_type_variation = "FieldBox"
	fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dm_input = LineEdit.new()
	dm_input.placeholder_text = "Mensagem privada…"
	dm_input.max_length = 500
	dm_input.text_submitted.connect(_send_dm)
	fb.add_child(dm_input)
	dm_row.add_child(fb)
	var sb := Button.new()
	sb.icon = Icons.tex("send", UIStyle.TEXT, 20)
	sb.custom_minimum_size = Vector2(44, 44)
	sb.focus_mode = Control.FOCUS_NONE
	sb.pressed.connect(func(): _send_dm(dm_input.text))
	dm_row.add_child(sb)
	dm_row.visible = false
	app_view.add_child(dm_row)
	app_view.visible = false
	var pill := Button.new()     # barra "home" (toque: voltar / fechar), como no original
	pill.text = "———"
	pill.flat = true
	pill.custom_minimum_size = Vector2(0, 30)
	pill.focus_mode = Control.FOCUS_NONE
	pill.pressed.connect(_home_bar)
	vb.add_child(pill)
	GameState.self_changed.connect(_refresh_unless_typing)
	GameState.social_changed.connect(_on_social)
	NetworkManager.game_message.connect(_on_net)
	GameState.chat_added.connect(func(_n, _t): _refresh())

func _round(c: Color, border: Color, r: int, m: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(m)
	return s

func _l(text: String, size: int, col: Color = UIStyle.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _scroll_bottom() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

func _home_bar() -> void:
	if app_view.visible:
		show_home()
	else:
		close()

func _write_msg() -> void:
	close()
	get_tree().call_group("hud", "toggle_chat")

func _logout() -> void:
	close()
	get_tree().call_group("world", "logout")

func _refresh_unless_typing() -> void:
	if not (conv_pub != "" and dm_input.has_focus()):
		_refresh()

func _on_social() -> void:
	var m := GameState.unread_messages()
	if app_buttons.has("Mensagens"):
		app_buttons["Mensagens"].text = "Mensagens" + (" (%d)" % m if m > 0 else "")
	var r: int = (GameState.social.get("incoming", []) as Array).size()
	if app_buttons.has("Amigos"):
		app_buttons["Amigos"].text = "Amigos" + (" (%d)" % r if r > 0 else "")
	if current_app in ["Amigos", "Definições"] or (current_app == "Mensagens" and conv_pub == ""):
		_refresh()

func _on_net(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"dm_history":
			GameState.dm_cache[str(msg.get("with", ""))] = msg.get("messages", [])
			if str(msg.get("with", "")) == conv_pub:
				_refresh()
		"dm_message":
			if is_conversation_open(str(msg.get("with", ""))):
				NetworkManager.send_game("dm_read", {"target": conv_pub})
				for c in GameState.social.get("conversations", []):
					if c["pub"] == conv_pub:
						c["unread"] = 0
				_refresh()
		"dm_sent":
			if bool(msg.get("ok", false)) and str(msg.get("with", "")) == conv_pub:
				if not GameState.dm_cache.has(conv_pub):
					GameState.dm_cache[conv_pub] = []
				(GameState.dm_cache[conv_pub] as Array).append(msg.get("data", {}))
				_refresh()
			elif not bool(msg.get("ok", false)):
				get_tree().call_group("hud", "notify", str(msg.get("text", "")), false)

func is_conversation_open(pub: String) -> bool:
	return visible and current_app == "Mensagens" and conv_pub == pub and pub != ""

func open_conversation(pub: String, name: String) -> void:
	if not visible:
		open()
	conv_pub = pub
	conv_name = name
	msg_tab = "conversas"
	open_app("Mensagens")
	NetworkManager.send_game("dm_history", {"target": pub})
	if not DisplayServer.is_touchscreen_available():
		dm_input.grab_focus.call_deferred()

func _send_dm(t: String) -> void:
	t = t.strip_edges()
	if t == "" or conv_pub == "":
		return
	NetworkManager.send_game("dm_send", {"target": conv_pub, "text": t})
	dm_input.text = ""

func _back() -> void:
	if current_app == "Mensagens" and conv_pub != "":
		conv_pub = ""
		_refresh()
	else:
		show_home()

func _open_conv(pub: String, name: String) -> void:
	open_conversation(pub, name)

func _tab(t: String) -> void:
	msg_tab = t
	_refresh()

func _profile_of(pub: String) -> void:
	close()
	get_tree().call_group("hud", "open_profile", pub)

func _social(type: String, pub: String) -> void:
	NetworkManager.send_game(type, {"target": pub})

func _privacy(v: String) -> void:
	NetworkManager.send_game("privacy_set", {"calls": v})

func _call(pub: String, name: String) -> void:
	close()
	call_requested.emit(pub, name)

func open() -> void:
	var vs := get_viewport_rect().size
	# preencher o ecrã explicitamente (as âncoras não resolvem quando o pai é construído no mesmo frame)
	position = Vector2.ZERO
	size = vs
	for c in get_children():
		(c as Control).position = Vector2.ZERO
		(c as Control).size = vs
	var h := minf(vs.y - 24.0, 640.0)
	device.custom_minimum_size = Vector2(minf(vs.x - 16.0, maxf(300.0, h * 0.52)), h)
	show_home()
	visible = true

func close() -> void:
	visible = false

func show_home() -> void:
	current_app = ""
	conv_pub = ""
	dm_row.visible = false
	app_view.visible = false
	home.visible = true

func _process(_d: float) -> void:
	if visible:
		lbl_time.text = GameState.clock_text()

func open_app(n: String) -> void:
	current_app = n
	home.visible = false
	app_view.visible = true
	app_title.text = n
	dm_row.visible = false
	if n == "Governo":
		NetworkManager.send_game("profile_request")
	_refresh()

func show_profile(p: Dictionary) -> void:
	_profile = p
	if current_app == "Governo":
		_refresh()

func _btn(text: String, cb: Callable, primary := false, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b

func _card(lines: Array) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIStyle.box(Color(0.14, 0.15, 0.17), Color(0.28, 0.27, 0.25), 1, Vector4(10, 8, 10, 8)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	for x in lines:
		vb.add_child(x if x is Control else _l(str(x), 13))
	return pc

func _refresh() -> void:
	if not visible or current_app == "":
		return
	for c in app_body.get_children():
		c.queue_free()
	var st: Dictionary = GameState.self_state
	var g := GameState.game_time()
	match current_app:
		"Banco":
			app_body.add_child(_l("Saldo disponível", 12, UIStyle.DIM))
			app_body.add_child(_l(GameState.fmt_kz(int(st.get("money", 0))), 24, UIStyle.GOLD))
			app_body.add_child(HSeparator.new())
			var txs: Array = st.get("transactions", [])
			if txs.is_empty():
				app_body.add_child(_l("Sem movimentos registados.", 13, UIStyle.DIM))
			for i in range(txs.size() - 1, -1, -1):
				var t: Dictionary = txs[i]
				var amt := int(t.get("amount", 0))
				var row := HBoxContainer.new()
				var d := _l(str(t.get("desc", "")), 12)
				d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(d)
				var al := _l(("+" if amt > 0 else "") + GameState.fmt_kz(amt), 12, UIStyle.GOOD if amt > 0 else Color(1, 0.6, 0.55))
				al.autowrap_mode = TextServer.AUTOWRAP_OFF
				row.add_child(al)
				app_body.add_child(row)
		"Mensagens":
			dm_row.visible = conv_pub != ""
			if conv_pub != "":
				app_title.text = conv_name
				var hb := HBoxContainer.new()
				hb.add_theme_constant_override("separation", 6)
				hb.add_child(_btn("Perfil", _profile_of.bind(conv_pub)))
				hb.add_child(_btn("Ligar", _call.bind(conv_pub, conv_name)))
				app_body.add_child(hb)
				var msgs: Array = GameState.dm_cache.get(conv_pub, [])
				if msgs.is_empty():
					app_body.add_child(_l("Sem mensagens. Diz olá!", 13, UIStyle.DIM))
				for mm in msgs:
					var mine := bool(mm.get("mine", false))
					var bub := PanelContainer.new()
					bub.add_theme_stylebox_override("panel", UIStyle.box(Color(0.42, 0.33, 0.12) if mine else Color(0.16, 0.18, 0.2), Color(0.3, 0.28, 0.24), 1, Vector4(8, 5, 8, 5)))
					bub.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
					var bv := VBoxContainer.new()
					var tl := _l(str(mm.get("text", "")), 13)
					tl.custom_minimum_size = Vector2(minf(220.0, 12.0 + str(mm.get("text", "")).length() * 7.0), 0)
					bv.add_child(tl)
					var ts := _l(GameState.time_label(float(mm.get("t", 0))), 10, UIStyle.DIM)
					ts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					bv.add_child(ts)
					bub.add_child(bv)
					app_body.add_child(bub)
				_scroll_bottom.call_deferred()
				return
			app_title.text = "Mensagens"
			var tabs := HBoxContainer.new()
			tabs.add_theme_constant_override("separation", 6)
			var un := GameState.unread_messages()
			var tb1 := _btn("Conversas" + (" (%d)" % un if un > 0 else ""), _tab.bind("conversas"), msg_tab == "conversas")
			tb1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tb2 := _btn("Perto de ti", _tab.bind("perto"), msg_tab == "perto")
			tb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.add_child(tb1)
			tabs.add_child(tb2)
			app_body.add_child(tabs)
			if msg_tab == "conversas":
				var convs: Array = GameState.social.get("conversations", [])
				if convs.is_empty():
					app_body.add_child(_l("Sem conversas privadas. Toca num jogador e escolhe «Mensagem», ou abre um amigo na app Amigos.", 13, UIStyle.DIM))
				for c in convs:
					var b := _btn("", _open_conv.bind(str(c["pub"]), str(c["name"])))
					b.alignment = HORIZONTAL_ALIGNMENT_LEFT
					b.custom_minimum_size = Vector2(0, 52)
					var unread := int(c.get("unread", 0))
					b.text = "%s%s\n%s%s" % [c["name"], ("  (%d novas)" % unread) if unread > 0 else "", "Tu: " if c.get("last_mine", false) else "", str(c.get("last", "")).left(34)]
					if unread > 0:
						b.add_theme_color_override("font_color", UIStyle.GOLD)
					app_body.add_child(b)
			else:
				app_body.add_child(_btn("Escrever (perto de ti)", _write_msg, true))
				if GameState.chat_log.is_empty():
					app_body.add_child(_l("As mensagens chegam a quem está na mesma zona e perto de ti.", 13, UIStyle.DIM))
				for i in range(GameState.chat_log.size() - 1, maxi(-1, GameState.chat_log.size() - 30), -1):
					var m: Dictionary = GameState.chat_log[i]
					app_body.add_child(_card([_l("%s · %s" % [m["name"], m["t"]], 11, UIStyle.GOLD), _l(str(m["text"]), 13)]))
		"Amigos":
			var soc: Dictionary = GameState.social
			var inc: Array = soc.get("incoming", [])
			if not inc.is_empty():
				app_body.add_child(_l("Pedidos de amizade", 12, UIStyle.DIM))
				for f in inc:
					var hb2 := HBoxContainer.new()
					var nl := _l("%s · Nível %d" % [f["name"], int(f.get("level", 1))], 13)
					nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					hb2.add_child(nl)
					hb2.add_child(_btn("Aceitar", _social.bind("friend_accept", str(f["pub"])), true))
					hb2.add_child(_btn("Recusar", _social.bind("friend_decline", str(f["pub"]))))
					app_body.add_child(hb2)
			var fr: Array = soc.get("friends", [])
			app_body.add_child(_l("Amigos (%d)" % fr.size(), 12, UIStyle.DIM))
			if fr.is_empty():
				app_body.add_child(_l("Ainda não tens amigos. Toca noutro jogador para o adicionar.", 13, UIStyle.DIM))
			for f in fr:
				var lines: Array = [_l(("[online] " if f.get("online", false) else "") + "%s · Nível %d" % [f["name"], int(f.get("level", 1))], 14, UIStyle.GOLD if f.get("online", false) else UIStyle.TEXT)]
				var hb3 := HBoxContainer.new()
				hb3.add_theme_constant_override("separation", 6)
				hb3.add_child(_btn("Mensagem", _open_conv.bind(str(f["pub"]), str(f["name"]))))
				hb3.add_child(_btn("Ligar", _call.bind(str(f["pub"]), str(f["name"])), false, bool(f.get("online", false))))
				hb3.add_child(_btn("Perfil", _profile_of.bind(str(f["pub"]))))
				lines.append(hb3)
				app_body.add_child(_card(lines))
			var outg: Array = soc.get("outgoing", [])
			if not outg.is_empty():
				app_body.add_child(_l("Pedidos enviados", 12, UIStyle.DIM))
				for f in outg:
					var hb4 := HBoxContainer.new()
					var nl2 := _l(str(f["name"]), 13)
					nl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					hb4.add_child(nl2)
					hb4.add_child(_btn("Cancelar", _social.bind("friend_cancel", str(f["pub"]))))
					app_body.add_child(hb4)
		"Emprego":
			var job: Variant = st.get("job")
			var jobs: Dictionary = WorldData.data["jobs"]
			if job != null and jobs.has(job):
				var jd: Dictionary = jobs[job]
				app_body.add_child(_card([_l("Emprego atual", 11, UIStyle.DIM), _l(jd["name"], 15, UIStyle.GOLD),
					_l("%s · %s por turno" % [WorldData.buildings[jd["building"]]["name"], GameState.fmt_kz(int(jd["pay"]))], 12),
					_l("Vai ao local de trabalho e usa um posto (secretária / fogão) para trabalhar um turno.", 12, UIStyle.DIM),
					_btn("Despedir-me", func(): NetworkManager.send_game("job_quit"))]))
			else:
				app_body.add_child(_l("Estás desempregado. Vagas abertas:", 13, UIStyle.DIM))
			for jid in jobs:
				if jid == job:
					continue
				var jd2: Dictionary = jobs[jid]
				var jj: String = jid
				app_body.add_child(_card([_l(jd2["name"], 14, UIStyle.GOLD),
					_l("%s · %s por turno" % [WorldData.buildings[jd2["building"]]["name"], GameState.fmt_kz(int(jd2["pay"]))], 12),
					_btn("Candidatar-me" if job == null else "Mudar para esta vaga", func(): NetworkManager.send_game("job_apply", {"job": jj}), true)]))
		"Imóveis":
			var h: Dictionary = st.get("housing", {})
			if h.get("status") == "arrendado" and float(h.get("until", 0)) > g:
				var until := float(h.get("until", 0))
				app_body.add_child(_card([_l("A tua casa", 11, UIStyle.DIM), _l(WorldData.data["rentals"].get(h.get("building", ""), {}).get("name", "?"), 14, UIStyle.GOLD),
					_l("Arrendado até Dia %d, %02d:%02d" % [int(until / 86400.0) + 1, int(until / 3600.0) % 24, int(until / 60.0) % 60], 12)]))
			else:
				app_body.add_child(_card([_l("Situação", 11, UIStyle.DIM), _l("Sem-abrigo", 15, Color(1, 0.65, 0.55)),
					_l("Sem casa não podes dormir numa cama, tomar banho nem cozinhar. Os bancos da rua deixam-te descansar um pouco.", 12, UIStyle.DIM)]))
			for rid in WorldData.data["rentals"]:
				var r: Dictionary = WorldData.data["rentals"][rid]
				var lines: Array = [_l(r["name"], 14, UIStyle.GOLD), _l("Quarto com cama, duche e cozinha.", 12, UIStyle.DIM)]
				for days in r["options"]:
					var cost := int(float(r["price_per_day"]) * days * (float(r.get("discount_7", 1.0)) if int(days) == 7 else 1.0))
					var rr: String = rid
					var dd: int = int(days)
					lines.append(_btn("Arrendar %d dia%s · %s" % [dd, "s" if dd > 1 else "", GameState.fmt_kz(cost)],
						func(): NetworkManager.send_game("rent", {"rental": rr, "days": dd}), true, int(st.get("money", 0)) >= cost))
				app_body.add_child(_card(lines))
		"Negócios":
			app_body.add_child(_l("Em breve.", 16, UIStyle.GOLD))
			app_body.add_child(_l("Abrir e gerir o teu próprio negócio chega num próximo milestone.", 13, UIStyle.DIM))
		"Governo":
			if _profile.is_empty():
				app_body.add_child(_l("A consultar o registo…", 13, UIStyle.DIM))
			else:
				var bg: Dictionary = _profile.get("background", {})
				var fam: Dictionary = bg.get("family", {})
				var ch: Dictionary = bg.get("childhood", {})
				app_body.add_child(_card([_l("REPÚBLICA DE ANGOLA · Bilhete de Identidade", 10, UIStyle.DIM), _l(str(_profile.get("name", "")), 16, UIStyle.GOLD),
					_l("Natural de %s (%s)" % [ch.get("neighbourhood", "?"), ch.get("province", "?")], 12),
					_l("Filho(a) de %s e %s" % [fam.get("father_name", "?"), fam.get("mother_name", "?")], 12)]))
				app_body.add_child(_card([_l("Historial", 11, UIStyle.DIM), _l("Classe de origem: %s" % bg.get("socioeconomic_label", "?"), 12),
					_l("Educação: %s" % ch.get("education", "?"), 12), _l("Pai: %s · Mãe: %s" % [fam.get("father_profession", "?"), fam.get("mother_profession", "?")], 12),
					_l(str(bg.get("starting_circumstances", {}).get("notes", "")), 12, UIStyle.DIM)]))
		"Definições":
			app_body.add_child(_l("Privacidade · quem te pode ligar", 12, UIStyle.DIM))
			var cur := str(GameState.social.get("privacy", {}).get("calls", "everyone"))
			var prow := HBoxContainer.new()
			prow.add_theme_constant_override("separation", 6)
			for opt in [["everyone", "Todos"], ["friends", "Só amigos"], ["nobody", "Ninguém"]]:
				var pb := _btn(opt[1], _privacy.bind(opt[0]), cur == opt[0])
				pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				prow.add_child(pb)
			app_body.add_child(prow)
			app_body.add_child(_l("Aplicado pelo servidor de imediato. Jogadores bloqueados nunca te podem ligar.", 11, UIStyle.DIM))
			var bl: Array = GameState.social.get("blocked", [])
			if not bl.is_empty():
				app_body.add_child(_l("Bloqueados", 12, UIStyle.DIM))
				for f in bl:
					var hb5 := HBoxContainer.new()
					var nl3 := _l(str(f["name"]), 13)
					nl3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					hb5.add_child(nl3)
					hb5.add_child(_btn("Desbloquear", _social.bind("unblock", str(f["pub"]))))
					app_body.add_child(hb5)
			app_body.add_child(HSeparator.new())
			app_body.add_child(_btn("Mostrar/ocultar informação técnica (F3)", func(): get_tree().call_group("debug_overlay", "toggle")))
			app_body.add_child(_btn("Terminar sessão (F10)", _logout, true))

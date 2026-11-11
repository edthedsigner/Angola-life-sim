extends Control
## Telemóvel (restaurado do original v0.6): ecrã inicial com relógio + apps Banco, Mensagens, Emprego, Imóveis,
## Negócios, Governo — agora com dados reais do servidor — e Definições (sessão / debug, acessível por toque).
## Todas as ações passam pelo servidor (NetworkManager.send_game); o telemóvel nunca altera estado localmente.

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Icons = preload("res://client/scripts/Icons.gd")
const APPS := [["Banco", "bank"], ["Mensagens", "chat"], ["Emprego", "job"], ["Imóveis", "home"], ["Negócios", "shop"], ["Governo", "gov"], ["Definições", "gear"]]
const SCREEN := Color(0.09, 0.1, 0.12)

var device: PanelContainer
var lbl_time: Label
var home: GridContainer
var app_view: VBoxContainer
var app_title: Label
var app_body: VBoxContainer
var current_app := ""
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
	back.pressed.connect(show_home)
	hb.add_child(back)
	app_title = _l("", 18, UIStyle.GOLD)
	app_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	app_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(app_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	app_view.add_child(sc)
	app_body = VBoxContainer.new()
	app_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_body.add_theme_constant_override("separation", 8)
	sc.add_child(app_body)
	app_view.visible = false
	var pill := Button.new()     # barra "home" (toque: voltar / fechar), como no original
	pill.text = "———"
	pill.flat = true
	pill.custom_minimum_size = Vector2(0, 30)
	pill.focus_mode = Control.FOCUS_NONE
	pill.pressed.connect(_home_bar)
	vb.add_child(pill)
	GameState.self_changed.connect(_refresh)
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
			app_body.add_child(_btn("Escrever (perto de ti)", _write_msg, true))
			if GameState.chat_log.is_empty():
				app_body.add_child(_l("Ainda não há conversas. As mensagens chegam a quem está na mesma zona e perto de ti.", 13, UIStyle.DIM))
			for i in range(GameState.chat_log.size() - 1, maxi(-1, GameState.chat_log.size() - 30), -1):
				var m: Dictionary = GameState.chat_log[i]
				app_body.add_child(_card([_l("%s · %s" % [m["name"], m["t"]], 11, UIStyle.GOLD), _l(str(m["text"]), 13)]))
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
			app_body.add_child(_btn("Mostrar/ocultar informação técnica (F3)", func(): get_tree().call_group("debug_overlay", "toggle")))
			app_body.add_child(_btn("Terminar sessão (F10)", _logout, true))

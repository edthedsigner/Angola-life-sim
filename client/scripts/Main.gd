extends Control
## Menu principal: mundo vivo como fundo + autenticação + onboarding (introdução → personagem) → mundo.
## O SERVIDOR decide em que passo o jogador está (onboarding.state). O cliente só encaminha e mostra.

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Branding = preload("res://shared/scripts/Branding.gd")
const WORLD_SCENE := preload("res://client/scenes/World.tscn")
const VISUAL_SCENE := preload("res://client/scenes/CharacterVisual.tscn")
const WORLD_PATH := "res://client/scenes/World.tscn"
const STORY_PATH := "res://client/data/intro_story.json"
const REQUEST_TIMEOUT := 8.0

enum Screen { LOGIN, REGISTER, STORY, CHARACTER, REVEAL }

var screen: int = Screen.LOGIN
var panels: Dictionary = {}
var msgs: Dictionary = {}
var story_pages: Array = []
var story_idx: int = 0

var _ui: Control
var _center: VBoxContainer
var _dot: ColorRect
var _server_label: Label
var _overlay: Control
var _overlay_label: Label
var _overlay_retry_btn: Button
var _overlay_other_btn: Button

var _login_user: LineEdit
var _login_pass: LineEdit
var _login_btn: Button
var _reg_user: LineEdit
var _reg_pass: LineEdit
var _reg_pass2: LineEdit
var _reg_btn: Button
var _story_title: Label
var _story_text: RichTextLabel
var _story_page: Label
var _story_back: Button
var _story_next: Button
var _char_name: LineEdit
var _skin_opt: OptionButton
var _hair_opt: OptionButton
var _preview: Node2D
var _char_btn: Button
var _reveal_text: RichTextLabel

var _busy: bool = false
var _active_btn: Button = null
var _btn_orig: String = ""
var _req_id: int = 0
var _resuming: bool = false
var _resume_id: int = 0
var _entering: bool = false
var _reconnecting: bool = false
var _tried_resume: bool = false

# ---------------------------------------------------------------- construção
func _fit_menu() -> void:
	## Ecrãs estreitos (telemóvel): resolução base 640x640 em vez de 1280x720 para os painéis não ficarem minúsculos.
	var sc := 1.0
	if OS.has_feature("web"):
		var v: Variant = JavaScriptBridge.eval("window.devicePixelRatio")
		if v != null:
			sc = maxf(float(v), 1.0)
	var logical := Vector2(get_window().size) / sc
	get_window().content_scale_size = Vector2i(640, 640) if minf(logical.x, logical.y) < 600.0 else Vector2i(1280, 720)

func _ready() -> void:
	if "--selftest-net" in OS.get_cmdline_args():      # dev: regras de normalização do endereço do servidor
		var cases := [["jogo.onrender.com", true, "wss://jogo.onrender.com"], ["https://jogo.onrender.com/", true, "wss://jogo.onrender.com"],
			["ws://jogo.onrender.com", true, "wss://jogo.onrender.com"], ["wss://a.b:8443", false, "wss://a.b:8443"],
			["192.168.1.20", false, "ws://192.168.1.20:7777"], ["192.168.1.20:9000", false, "ws://192.168.1.20:9000"],
			["ws://localhost:7777", true, "ws://localhost:7777"], ["http://a.b", false, "ws://a.b"]]
		for c in cases:
			var got: String = NetworkManager.normalize_url(c[0], c[1])
			print("[selftest] %s %s (https=%s) -> %s" % ["ok  " if got == c[2] else "FAIL", c[0], c[1], got])
		print("[selftest] url=%s origem=%s" % [NetworkManager.server_url(), NetworkManager.url_source])
		return
	if "--check-scripts" in OS.get_cmdline_args():      # dev: compila cada script isoladamente e mostra erros com linha
		for d in ["res://client/scripts/", "res://shared/scripts/"]:
			for f in DirAccess.get_files_at(d):
				if f.ends_with(".gd"):
					var sc: Script = load(d + f)
					var err: int = sc.reload() if sc != null else FAILED
					# ERR_ALREADY_IN_USE = já tem instâncias (autoloads, esta cena): compilou, logo está ok
					print("[check] %s %s" % ["ok " if err == OK or err == ERR_ALREADY_IN_USE else "ERRO", f])
		return
	if "--scale-test" in OS.get_cmdline_args() or "--scale-test" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file.call_deferred("res://client/scenes/tests/ScaleTest.tscn")   # laboratório de escala
		return
	_fit_menu()
	get_window().size_changed.connect(_fit_menu)
	var brand: Dictionary = Branding.data()
	DisplayServer.window_set_title(str(brand.get("window_title", "")))
	# Fundo: o MUNDO REAL em modo showcase (mesmo renderer/assets), sem rede
	var world: Node = WORLD_SCENE.instantiate()
	world.set("showcase", true)
	add_child(world)
	move_child(world, 0)
	# UI numa CanvasLayer acima do mundo
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UIStyle.make_theme()
	layer.add_child(_ui)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.38)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dim)
	_center = VBoxContainer.new()
	_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override("separation", 12)
	_ui.add_child(_center)
	_build_logo(brand)
	_build_login()
	_build_register()
	_build_story()
	_build_character()
	_build_reveal()
	_build_status()
	_build_overlay()
	_connect_network()
	_show_screen(Screen.LOGIN)
	Transition.fade_in(0.6)
	_load_story()
	if NetworkManager.connected:
		_on_connected()
	else:
		_set_server_state("connecting")
		NetworkManager.connect_to_server()

func _build_logo(brand: Dictionary) -> void:
	var path: String = str(brand.get("logo", ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(480, 150)
		_center.add_child(tr)
	else:
		var l := Label.new()
		l.text = str(brand.get("title", ""))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 34)
		l.add_theme_color_override("font_color", UIStyle.GOLD)
		_center.add_child(l)

func _panel(key: int, width: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var mg := MarginContainer.new()
	for side in ["left", "right"]:
		mg.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	mg.add_child(vb)
	pc.add_child(mg)
	_center.add_child(pc)
	panels[key] = pc
	return vb

func _title(vb: Control, text: String) -> void:
	var l := Label.new()
	l.text = "—  %s  —" % text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 19)
	vb.add_child(l)
	vb.add_child(HSeparator.new())

func _msg_label(vb: Control, key: int) -> void:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.visible = false
	vb.add_child(l)
	msgs[key] = l

func _button(vb: Control, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	vb.add_child(b)
	return b

func _field(parent: Control, icon_path: String, placeholder: String, secret: bool) -> LineEdit:
	var box := PanelContainer.new()
	box.theme_type_variation = "FieldBox"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	box.add_child(hb)
	if icon_path != "":
		var ic := TextureRect.new()
		ic.texture = load(icon_path) as Texture2D
		ic.custom_minimum_size = Vector2(22, 22)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.secret = secret
	le.max_length = 32
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(le)
	le.focus_entered.connect(_on_field_focus.bind(box, true))
	le.focus_exited.connect(_on_field_focus.bind(box, false))
	parent.add_child(box)
	return le

func _on_field_focus(box: PanelContainer, focused: bool) -> void:
	box.theme_type_variation = "FieldBoxFocus" if focused else "FieldBox"

func _build_login() -> void:
	var vb := _panel(Screen.LOGIN, 460)
	_title(vb, "Entrar na Conta")
	_login_user = _field(vb, "res://assets/art/ui/icon_user.png", "Utilizador", false)
	_login_pass = _field(vb, "res://assets/art/ui/icon_lock.png", "Palavra-passe", true)
	_login_user.text_submitted.connect(_on_login_submit)
	_login_pass.text_submitted.connect(_on_login_submit)
	_msg_label(vb, Screen.LOGIN)
	_login_btn = _button(vb, "Entrar", true, _on_login_pressed)
	_button(vb, "Criar Conta", false, _on_goto_register)
	# "Esqueci-me da palavra-passe": o sistema de autenticação atual não suporta recuperação — omitido de propósito.

func _build_register() -> void:
	var vb := _panel(Screen.REGISTER, 460)
	_title(vb, "Criar Conta")
	_reg_user = _field(vb, "res://assets/art/ui/icon_user.png", "Utilizador (mín. 3 letras)", false)
	_reg_pass = _field(vb, "res://assets/art/ui/icon_lock.png", "Palavra-passe (mín. 4)", true)
	_reg_pass2 = _field(vb, "res://assets/art/ui/icon_lock.png", "Repetir palavra-passe", true)
	_reg_pass2.text_submitted.connect(_on_register_submit)
	_msg_label(vb, Screen.REGISTER)
	_reg_btn = _button(vb, "Criar Conta", true, _on_register_pressed)
	_button(vb, "Voltar", false, _on_goto_login)

func _build_story() -> void:
	var vb := _panel(Screen.STORY, 560)
	_story_title = Label.new()
	_story_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_title.add_theme_font_size_override("font_size", 19)
	_story_title.add_theme_color_override("font_color", UIStyle.GOLD)
	vb.add_child(_story_title)
	vb.add_child(HSeparator.new())
	_story_text = RichTextLabel.new()
	_story_text.bbcode_enabled = true
	_story_text.fit_content = true
	_story_text.custom_minimum_size = Vector2(0, 150)
	vb.add_child(_story_text)
	_story_page = Label.new()
	_story_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_story_page.add_theme_color_override("font_color", UIStyle.DIM)
	vb.add_child(_story_page)
	_msg_label(vb, Screen.STORY)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	_story_back = Button.new()
	_story_back.text = "Anterior"
	_story_back.custom_minimum_size = Vector2(130, 42)
	_story_back.pressed.connect(_on_story_back)
	row.add_child(_story_back)
	_story_next = Button.new()
	_story_next.theme_type_variation = "PrimaryButton"
	_story_next.custom_minimum_size = Vector2(0, 42)
	_story_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_next.pressed.connect(_on_story_next)
	row.add_child(_story_next)

func _build_character() -> void:
	var vb := _panel(Screen.CHARACTER, 580)
	_title(vb, "O Teu Personagem")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(form)
	var l1 := Label.new()
	l1.text = "Nome"
	form.add_child(l1)
	_char_name = _field(form, "", "Nome do personagem", false)
	_char_name.max_length = 24
	var l2 := Label.new()
	l2.text = "Tom de pele"
	form.add_child(l2)
	_skin_opt = OptionButton.new()
	_skin_opt.custom_minimum_size = Vector2(0, 38)
	for i in Art.SKIN_NAMES.size():
		_skin_opt.add_item(Art.SKIN_NAMES[i], i)
	_skin_opt.item_selected.connect(_on_option_selected)
	form.add_child(_skin_opt)
	var l3 := Label.new()
	l3.text = "Cabelo"
	form.add_child(l3)
	_hair_opt = OptionButton.new()
	_hair_opt.custom_minimum_size = Vector2(0, 38)
	for i in Art.HAIR_NAMES.size():
		_hair_opt.add_item(Art.HAIR_NAMES[i], i)
	_hair_opt.item_selected.connect(_on_option_selected)
	form.add_child(_hair_opt)
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(190, 210)
	hb.add_child(pv)
	_preview = VISUAL_SCENE.instantiate()
	_preview.position = Vector2(95, 195)
	_preview.scale = Vector2(4, 4)
	pv.add_child(_preview)
	_msg_label(vb, Screen.CHARACTER)
	_char_btn = _button(vb, "Confirmar personagem", true, _on_create_character_pressed)
	_update_preview()

func _build_reveal() -> void:
	var vb := _panel(Screen.REVEAL, 600)
	_title(vb, "A Tua História de Vida")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	vb.add_child(sc)
	_reveal_text = RichTextLabel.new()
	_reveal_text.bbcode_enabled = true
	_reveal_text.fit_content = true
	_reveal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_reveal_text)
	_button(vb, "Entrar no mundo", true, _on_reveal_enter)

func _build_status() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(10, 10)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dot)
	_server_label = Label.new()
	_server_label.add_theme_font_size_override("font_size", 13)
	row.add_child(_server_label)
	_center.add_child(row)

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_ui.add_child(_overlay)
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.6)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(d)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(440, 0)
	cc.add_child(pc)
	var mg := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 22)
	pc.add_child(mg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mg.add_child(vb)
	_overlay_label = Label.new()
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_overlay_label)
	_overlay_retry_btn = _button(vb, "Tentar novamente", true, _on_overlay_retry)
	_overlay_other_btn = _button(vb, "Usar outra conta", false, _on_other_account)

func _connect_network() -> void:
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_lost)
	NetworkManager.disconnected_from_server.connect(_on_connection_lost)
	NetworkManager.auth_success.connect(_on_auth_success)
	NetworkManager.auth_failed.connect(_on_auth_failed)
	NetworkManager.session_invalid.connect(_on_session_invalid)
	NetworkManager.onboarding_changed.connect(_on_onboarding_changed)
	NetworkManager.character_spawned.connect(_on_character_created)
	NetworkManager.background_received.connect(_on_background_received)
	NetworkManager.server_error.connect(_on_server_error)

# ---------------------------------------------------------------- ecrãs / estado visual
func _show_screen(s: int) -> void:
	screen = s
	for k in panels:
		(panels[k] as Control).visible = (k == s)
	for k in msgs:
		(msgs[k] as Label).visible = false

func _show_msg(text: String, color: Color = UIStyle.BAD) -> void:
	if msgs.has(screen):
		var l: Label = msgs[screen]
		l.text = text
		l.add_theme_color_override("font_color", color)
		l.visible = true

func _set_server_state(state: String) -> void:
	match state:
		"online":
			_dot.color = UIStyle.GOOD
			_server_label.text = "Servidor Online"
		"connecting":
			_dot.color = UIStyle.WARN
			_server_label.text = "A ligar ao servidor..."
		_:
			_dot.color = UIStyle.BAD
			_server_label.text = "Servidor Offline — a tentar de novo..."

func _begin_request(btn: Button, busy_text: String) -> void:
	_busy = true
	_active_btn = btn
	_btn_orig = btn.text
	btn.text = busy_text
	btn.disabled = true
	_req_id += 1
	var id := _req_id
	await get_tree().create_timer(REQUEST_TIMEOUT).timeout
	if _busy and id == _req_id:
		_end_request()
		_show_msg("O servidor não respondeu. O teu progresso está guardado — tenta novamente.")

func _end_request() -> void:
	_busy = false
	if _active_btn and is_instance_valid(_active_btn):
		_active_btn.text = _btn_orig
		_active_btn.disabled = false
	_active_btn = null

func _show_overlay(text: String, retry: bool, other_account: bool) -> void:
	_overlay_label.text = text
	_overlay_retry_btn.visible = retry
	_overlay_other_btn.visible = other_account
	_overlay.visible = true

func _hide_overlay() -> void:
	_overlay.visible = false

# ---------------------------------------------------------------- ligação / sessão
func _on_connected() -> void:
	_set_server_state("online")
	if _overlay.visible and not _resuming and not _entering:
		_hide_overlay()
	_try_resume()

func _on_connection_lost() -> void:
	_set_server_state("offline")
	_end_request()
	_resuming = false
	if _entering:
		return
	if screen == Screen.STORY or screen == Screen.CHARACTER or screen == Screen.REVEAL:
		_show_overlay("Ligação perdida. O teu progresso está guardado no servidor.\nA tentar reconectar...", false, false)
	_schedule_reconnect()

func _schedule_reconnect() -> void:
	if _reconnecting:
		return
	_reconnecting = true
	await get_tree().create_timer(2.0).timeout
	_reconnecting = false
	if is_inside_tree() and not NetworkManager.connected:
		_set_server_state("connecting")
		NetworkManager.connect_to_server()

func _try_resume() -> void:
	if _resuming or _entering:
		return
	var token := GameState.load_session(NetworkManager.server_url())
	if token == "":
		return
	_resuming = true
	_resume_id += 1
	var id := _resume_id
	_show_overlay("A restaurar sessão...", false, true)
	NetworkManager.request_resume_session(token)
	await get_tree().create_timer(REQUEST_TIMEOUT).timeout
	if _resuming and id == _resume_id:
		_resuming = false
		_show_overlay("O servidor não respondeu ao restaurar a sessão. O teu progresso está guardado.", true, true)

func _on_overlay_retry() -> void:
	_hide_overlay()
	if not NetworkManager.connected:
		_set_server_state("connecting")
		NetworkManager.connect_to_server()
	elif _entering:
		_entering = false
		_enter_world(GameState.current_character)
	else:
		_try_resume()

func _on_other_account() -> void:
	_resuming = false
	GameState.clear_session()
	GameState.clear()
	_hide_overlay()
	_show_screen(Screen.LOGIN)

func _on_session_invalid() -> void:
	_resuming = false
	GameState.clear_session()
	_hide_overlay()
	_show_screen(Screen.LOGIN)
	_show_msg("A sessão expirou. Inicia sessão novamente.", UIStyle.WARN)

func _on_server_error(m: String) -> void:
	_end_request()
	_show_msg("Servidor: " + m)

# ---------------------------------------------------------------- login / registo
func _on_goto_register() -> void:
	_show_screen(Screen.REGISTER)
	_reg_user.grab_focus()

func _on_goto_login() -> void:
	_show_screen(Screen.LOGIN)

func _on_login_submit(_t: String) -> void:
	_on_login_pressed()

func _on_login_pressed() -> void:
	if _busy:
		return
	var user := _login_user.text.strip_edges()
	if user.is_empty() or _login_pass.text.is_empty():
		_show_msg("Preenche o utilizador e a palavra-passe.")
		return
	if not NetworkManager.connected:
		_show_msg("Sem ligação ao servidor. A tentar de novo...")
		return
	_begin_request(_login_btn, "A entrar...")
	NetworkManager.request_login(user, _login_pass.text)

func _on_register_submit(_t: String) -> void:
	_on_register_pressed()

func _on_register_pressed() -> void:
	if _busy:
		return
	var user := _reg_user.text.strip_edges()
	if user.length() < 3 or _reg_pass.text.length() < 4:
		_show_msg("Utilizador: mín. 3 letras. Palavra-passe: mín. 4.")
		return
	if _reg_pass.text != _reg_pass2.text:
		_show_msg("As palavras-passe não coincidem.")
		return
	if not NetworkManager.connected:
		_show_msg("Sem ligação ao servidor. A tentar de novo...")
		return
	_begin_request(_reg_btn, "A criar...")
	NetworkManager.request_register(user, _reg_pass.text)

func _on_auth_failed(reason: String) -> void:
	_resuming = false
	_end_request()
	_show_msg(reason)

func _on_auth_success(data: Dictionary) -> void:
	_resuming = false
	_end_request()
	var tok: String = str(data.get("session_token", ""))
	if tok != "":
		GameState.save_session(tok, NetworkManager.server_url())
	GameState.set_account(data)
	_login_pass.text = ""
	_reg_pass.text = ""
	_reg_pass2.text = ""
	_route(data)

# ---------------------------------------------------------------- encaminhamento (decidido pelo servidor)
func _route(data: Dictionary) -> void:
	var ob: Dictionary = data.get("onboarding", {})
	GameState.onboarding = ob
	var st: String = str(ob.get("state", "new"))
	match st:
		"completed":
			var ch: Variant = data.get("character")
			if typeof(ch) != TYPE_DICTIONARY:
				var arr: Array = data.get("characters", [])
				ch = arr[0] if arr.size() > 0 else null
			if typeof(ch) != TYPE_DICTIONARY:
				_show_overlay("Perfil incompleto no servidor. Contacta o administrador.", true, true)
				return
			_enter_world(ch)         # jogador com regresso: direto ao mundo, sem história/personalização
		"character_customization":
			_hide_overlay()
			_show_screen(Screen.CHARACTER)
			_char_name.grab_focus()
		"story_in_progress":
			story_idx = clampi(int(ob.get("story_step", 0)), 0, maxi(story_pages.size() - 1, 0))
			_start_story()
		_:
			story_idx = 0
			_start_story()

# ---------------------------------------------------------------- introdução
func _load_story() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		story_pages = (parsed as Dictionary).get("pages", [])
	if story_pages.is_empty():
		story_pages = [{"title": "Bem-vindo", "text": "A tua vida começa aqui."}]

func _start_story() -> void:
	_hide_overlay()
	_show_screen(Screen.STORY)
	_render_story()
	NetworkManager.request_onboarding("story_in_progress", story_idx)   # regista início/retoma

func _render_story() -> void:
	var p: Dictionary = story_pages[story_idx]
	_story_title.text = str(p.get("title", ""))
	_story_text.text = str(p.get("text", ""))
	_story_page.text = "%d / %d" % [story_idx + 1, story_pages.size()]
	_story_back.disabled = (story_idx == 0)
	_story_next.text = "Escolher o meu personagem" if story_idx == story_pages.size() - 1 else "Continuar"

func _on_story_back() -> void:
	if story_idx > 0 and not _busy:
		story_idx -= 1
		_render_story()

func _on_story_next() -> void:
	if _busy:
		return
	var steps: int = int(GameState.onboarding.get("story_steps", story_pages.size()))
	if story_idx < story_pages.size() - 1:
		story_idx += 1
		_render_story()
		NetworkManager.request_onboarding("story_in_progress", mini(story_idx, steps - 1))
	else:
		_begin_request(_story_next, "A guardar...")
		NetworkManager.request_onboarding("character_customization", steps - 1)

func _on_onboarding_changed(state: String, _step: int) -> void:
	if screen == Screen.STORY and state == "character_customization":
		_end_request()
		_show_screen(Screen.CHARACTER)
		_char_name.grab_focus()

# ---------------------------------------------------------------- personagem
func _on_option_selected(_i: int) -> void:
	_update_preview()

func _update_preview() -> void:
	_preview.apply_appearance({"skin_tone": _skin_opt.selected, "hair_style": _hair_opt.selected, "hair_color": 0, "clothes": 0})

func _on_create_character_pressed() -> void:
	if _busy:
		return
	var cname := _char_name.text.strip_edges()
	if cname.length() < 2:
		_show_msg("Escolhe um nome com pelo menos 2 letras.")
		return
	if not NetworkManager.connected:
		_show_msg("Sem ligação ao servidor. A tentar de novo...")
		return
	var appearance := {"skin_tone": _skin_opt.selected, "hair_style": _hair_opt.selected, "hair_color": 0, "clothes": 0}
	_begin_request(_char_btn, "A criar...")
	NetworkManager.request_create_character("", appearance, cname)

func _on_character_created(data: Dictionary) -> void:
	_end_request()
	GameState.set_character(data)
	GameState.onboarding = {"state": "completed", "story_step": GameState.onboarding.get("story_steps", 4) - 1, "story_steps": GameState.onboarding.get("story_steps", 4)}

func _on_background_received(bg: Dictionary) -> void:
	_show_background(bg)

func _show_background(bg: Dictionary) -> void:
	_show_screen(Screen.REVEAL)
	var family: Dictionary = bg.get("family", {})
	var childhood: Dictionary = bg.get("childhood", {})
	var start: Dictionary = bg.get("starting_circumstances", {})
	var text := "[b]Classe socioeconómica:[/b] %s\n\n" % bg.get("socioeconomic_label", "?")
	text += "[b]Família[/b]\n"
	text += "• Pai: %s (%s)\n" % [family.get("father_name", "?"), family.get("father_profession", "?")]
	text += "• Mãe: %s (%s)\n" % [family.get("mother_name", "?"), family.get("mother_profession", "?")]
	text += "• Irmãos: %d\n" % int(family.get("siblings", 0))
	text += "• Relação familiar: %s\n\n" % family.get("family_relationship", "?")
	text += "[b]Infância[/b]\n"
	text += "• Província: %s\n• Bairro: %s\n" % [childhood.get("province", "?"), childhood.get("neighbourhood", "?")]
	text += "• Condições: %s\n• Educação: %s\n\n" % [childhood.get("living_conditions", "?"), childhood.get("education", "?")]
	text += "[b]Início da vida independente[/b]\n"
	text += "• Dinheiro inicial: [b]%d Kz[/b]\n" % int(start.get("initial_money", 0))
	text += "• Posses: %s\n" % ", ".join(start.get("personal_possessions", []))
	text += "• Qualificações: %s\n" % ", ".join(start.get("qualifications", []))
	text += "• Contactos: %s\n\n" % ", ".join(start.get("useful_contacts", []))
	text += "• Bens da família (não são teus): %s\n" % ", ".join(bg.get("family_assets", []))
	text += "• Habitação: [b]sem-abrigo[/b] — começas sem casa própria\n\n"
	text += "[i]%s[/i]" % start.get("notes", "")
	_reveal_text.text = text

func _on_reveal_enter() -> void:
	_enter_world(GameState.current_character)

# ---------------------------------------------------------------- entrada no mundo
func _enter_world(ch: Dictionary) -> void:
	if _entering:
		return
	if not NetworkManager.connected:
		_entering = true
		_show_overlay("Sem ligação ao servidor. O teu progresso está guardado.", true, false)
		return
	_entering = true
	GameState.set_character(ch)
	_show_overlay("A entrar no mundo...", false, false)
	await Transition.fade_out(0.5)
	get_tree().change_scene_to_file(WORLD_PATH)

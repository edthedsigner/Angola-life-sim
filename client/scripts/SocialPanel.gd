extends PanelContainer
## Perfil de OUTRO jogador (abre ao tocar/clicar nele). Painel flutuante à direita no computador, folha de baixo no
## telemóvel; o mundo continua visível. Só mostra dados públicos enviados pelo servidor: nome, avatar, nível, estado
## público, desde quando joga, nº de amigos e a relação contigo. Todas as ações são pedidos ao servidor, que decide
## (amizade, saldo, posse, permissões de chamada, convites). Ações destrutivas e presentes pedem confirmação.

signal open_conversation(pub: String, name: String)
signal start_call(pub: String, name: String)

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const UI = preload("res://client/scripts/ui/UIKit.gd")
const Icons = preload("res://client/scripts/Icons.gd")

var pub := ""
var prof: Dictionary = {}
var view := "main"            # main | invite | places | gift | gift_money | gift_item | sending
var box: VBoxContainer
var scroll: ScrollContainer
var _amount: LineEdit

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UIStyle.surface(0.84, 18, Vector4(14, 12, 14, 14)))
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box = UI.vbox(10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(box)
	NetworkManager.game_message.connect(_on_msg)
	GameState.social_changed.connect(_on_social_changed)
	get_viewport().size_changed.connect(_place)

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

func _on_social_changed() -> void:
	if visible and pub != "":
		_request()

func open(p: String) -> void:
	pub = p
	prof = {}
	view = "main"
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.14)
	_render()
	_request()

func close() -> void:
	visible = false
	pub = ""

func _request() -> void:
	NetworkManager.send_game("social_profile", {"target": pub})

func _on_msg(msg: Dictionary) -> void:
	if not visible:
		return
	match str(msg.get("type", "")):
		"social_profile":
			if str(msg.get("data", {}).get("pub", "")) == pub:
				prof = msg["data"]
				if view == "sending":
					view = "main"
				_render()
		"social_result":
			if str(msg.get("action", "")).begins_with("gift"):
				view = "main"
				_render()

func _send(type: String, extra: Dictionary = {}) -> void:
	var d := extra.duplicate()
	d["target"] = pub
	NetworkManager.send_game(type, d)

func _go(v: String) -> void:
	view = v
	_render()

func _name() -> String:
	return str(prof.get("name", ""))

# ================================================================== desenho
func _clear() -> void:
	for c in box.get_children():
		c.queue_free()

func _render() -> void:
	_clear()
	if prof.is_empty():
		var h := UI.hbox(8)
		h.add_child(UI.title("A carregar perfil…", 14, UIStyle.DIM))
		h.add_child(UI.icon_button("x", close, "Fechar", 36, UIStyle.DIM))
		box.add_child(h)
		_place()
		return
	match view:
		"main":
			_render_main()
		"invite":
			_render_invite()
		"places":
			_render_places()
		"gift":
			_render_gift_menu()
		"gift_money":
			_render_gift_money()
		"gift_item":
			_render_gift_item()
		"sending":
			_sub_header("A enviar…")
			box.add_child(UI.label("A aguardar a confirmação do servidor.", 13, UIStyle.DIM))
	_place()

func _sub_header(title: String) -> void:
	var h := UI.hbox(6)
	h.add_child(UI.icon_button("back", func(): _go("main"), "Voltar", 36, UIStyle.TEXT))
	h.add_child(UI.title(title, 16, UIStyle.TEXT, "bold"))
	h.add_child(UI.icon_button("x", close, "Fechar (Esc)", 36, UIStyle.DIM))
	box.add_child(h)

func _header() -> void:
	var hb := UI.hbox(12)
	var online := bool(prof.get("online", false))
	hb.add_child(UI.avatar(prof.get("appearance", {}), 58, UIStyle.GOLD, 1 if online else 0))
	var vb := UI.vbox(4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UI.title(_name(), 18, UIStyle.TEXT, "bold"))
	var chips := UI.hbox(6)
	chips.add_child(UI.chip("Nv %d" % int(prof.get("level", 1)), UIStyle.GOLD, "star"))
	var rel := str(prof.get("relation", "none"))
	var rel_chip: Dictionary = {"friends": ["Amigos", UIStyle.GOOD, "user"], "request_sent": ["Pedido enviado", UIStyle.DIM, "user"],
		"request_received": ["Quer ser teu amigo", UIStyle.GOLD, "user"], "blocked": ["Bloqueado", UIStyle.BAD, "block"]}
	if rel_chip.has(rel):
		chips.add_child(UI.chip(rel_chip[rel][0], rel_chip[rel][1], rel_chip[rel][2]))
	vb.add_child(chips)
	vb.add_child(UI.title(str(prof.get("status", "")), 12, UIStyle.GOOD if online else UIStyle.DIM, "medium"))
	hb.add_child(vb)
	var x := UI.icon_button("x", close, "Fechar (Esc)", 36, UIStyle.DIM)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(x)
	box.add_child(hb)

## Tile de ação (ícone em cima, texto em baixo), em grelha 2×2.
func _tile(icon_name: String, text: String, cb: Callable, enabled: bool = true, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.icon = Icons.tex(icon_name, UIStyle.GOLD if enabled else UIStyle.FAINT, 22)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(0, 68)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip
	b.add_theme_font_override("font", UIStyle.font("semibold"))
	b.add_theme_font_size_override("font_size", 13)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	return b

func _render_main() -> void:
	_header()
	var rel := str(prof.get("relation", "none"))
	var blocked := rel == "blocked"
	# ação de amizade principal (destacada)
	match rel:
		"none":
			box.add_child(UI.button("Adicionar amigo", func(): _send("friend_request"), "primary", "plus"))
		"request_sent":
			box.add_child(UI.button("Cancelar pedido de amizade", func(): _send("friend_cancel"), "secondary"))
		"request_received":
			var r := UI.hbox(8)
			var a := UI.button("Aceitar pedido", func(): _send("friend_accept"), "primary", "check")
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(a)
			var d := UI.button("Recusar", func(): _send("friend_decline"), "secondary")
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(d)
			box.add_child(r)
	if blocked:
		box.add_child(UI.card(UI.label("Bloqueaste este jogador: não te pode enviar mensagens, convites, presentes nem ligar.", 13, UIStyle.DIM, "regular", true)))
		box.add_child(UI.button("Desbloquear", func(): _send("unblock"), "secondary"))
	else:
		var can_msg := bool(prof.get("can_message", true))
		var can_call := bool(prof.get("can_call", false))
		var call_tip := "" if can_call else ("Offline" if not prof.get("online", false) else "Esta pessoa não aceita chamadas tuas")
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(_tile("chat", "Mensagem", _do_message, can_msg))
		grid.add_child(_tile("phone", "Ligar" if can_call else "Ligar · indisponível", _do_call, can_call, call_tip))
		grid.add_child(_tile("home", "Convidar", func(): _go("invite")))
		grid.add_child(_tile("gift", "Presente", func(): _go("gift")))
		box.add_child(grid)
		var games: Dictionary = GameState.social.get("games", {})
		var g := UI.button("Jogar um jogo" if not games.is_empty() else "Jogar um jogo · em breve", func(): pass, "ghost", "gamepad", not games.is_empty(),
			"Os minijogos multijogador ainda não existem; o convite fica ativo quando forem registados.")
		box.add_child(g)
	box.add_child(UI.label("A jogar desde %s · %d amigo%s" % [str(prof.get("since", "?")), int(prof.get("friends_count", 0)), "" if int(prof.get("friends_count", 0)) == 1 else "s"], 12, UIStyle.FAINT))
	# zona de risco, separada e com confirmação
	var danger := UI.hbox(8)
	if rel == "friends":
		var rm := UI.button("Remover amigo", func():
			_hud().confirm("Remover %s?" % _name(), "Deixam de ser amigos. Podes voltar a enviar um pedido mais tarde.", "Remover", func(): _send("friend_remove"), true), "danger")
		rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		danger.add_child(rm)
	if not blocked:
		var bl := UI.button("Bloquear", func():
			_hud().confirm("Bloquear %s?" % _name(), "Remove a amizade e os pedidos pendentes. Deixa de te poder enviar mensagens, convites, presentes e chamadas.", "Bloquear", func(): _send("block"), true), "danger", "block")
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		danger.add_child(bl)
	if danger.get_child_count() > 0:
		box.add_child(HSeparator.new())
		box.add_child(danger)

func _do_message() -> void:
	var p := pub
	var n := _name()
	close()                                  # fecha primeiro (close() limpa `pub`)
	open_conversation.emit(p, n)

func _do_call() -> void:
	var p := pub
	var n := _name()
	close()
	start_call.emit(p, n)

func _option(icon_name: String, title: String, sub: String, cb: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	var h := UI.hbox(12)
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -12
	h.add_child(UI.icon(icon_name, UIStyle.GOLD, 20))
	var v := UI.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UI.title(title, 14, UIStyle.TEXT, "semibold"))
	if sub != "":
		v.add_child(UI.title(sub, 12, UIStyle.DIM, "regular"))
	h.add_child(v)
	h.add_child(UI.icon("send", UIStyle.FAINT, 14))
	b.add_child(h)
	return b

func _render_invite() -> void:
	_sub_header("Convidar %s" % _name())
	box.add_child(_option("home", "Para a minha casa", "Só se tiveres casa arrendada; dá acesso de visita por 30 min", func():
		_send("invite", {"kind": "house"})
		_go("main")))
	box.add_child(_option("pin", "Para um sítio público…", "Recebe o caminho até lá", func(): _go("places")))

func _render_places() -> void:
	_sub_header("Sítio público")
	var places: Dictionary = GameState.social.get("places", {})
	if places.is_empty():
		box.add_child(UI.empty_state("pin", "Sem sítios públicos", ""))
	for bid in places:
		var b_id: String = bid
		box.add_child(_option("pin", str(places[bid]), "", func():
			_send("invite", {"kind": "place", "place": b_id})
			_go("main")))

func _render_gift_menu() -> void:
	_sub_header("Presente para %s" % _name())
	box.add_child(_option("wallet", "Dinheiro", "Saldo: " + GameState.fmt_kz(int(GameState.self_state.get("money", 0))), func(): _go("gift_money")))
	box.add_child(_option("bag", "Artigo da mochila", "Escolhe um artigo", func(): _go("gift_item")))

func _render_gift_money() -> void:
	_sub_header("Enviar dinheiro")
	var money := int(GameState.self_state.get("money", 0))
	box.add_child(UI.chip("O teu saldo: " + GameState.fmt_kz(money), UIStyle.GOLD, "wallet"))
	var presets := UI.hbox(6)
	for v in [500, 1000, 5000]:
		var amt: int = v
		var b := UI.button(GameState.fmt_kz(v), func(): _amount.text = str(amt), "secondary", "", money >= v)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(b)
	box.add_child(presets)
	var field := PanelContainer.new()
	field.theme_type_variation = "FieldBox"
	_amount = LineEdit.new()
	_amount.placeholder_text = "Outro valor (Kz)"
	_amount.max_length = 7
	_amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_amount.focus_entered.connect(func(): field.theme_type_variation = "FieldBoxFocus")
	_amount.focus_exited.connect(func(): field.theme_type_variation = "FieldBox")
	field.add_child(_amount)
	box.add_child(field)
	box.add_child(UI.button("Continuar", _confirm_money, "primary", "send"))

func _confirm_money() -> void:
	var t := _amount.text.strip_edges()
	if not t.is_valid_int() or int(t) <= 0:
		_hud().notify("Escreve um valor válido.", false)
		return
	var amount := int(t)
	var after := int(GameState.self_state.get("money", 0)) - amount
	_hud().confirm("Enviar %s a %s?" % [GameState.fmt_kz(amount), _name()], "Saldo depois: %s. Os presentes não podem ser anulados." % GameState.fmt_kz(after), "Enviar",
		func(): _send_gift({"kind": "money", "amount": amount}))

func _render_gift_item() -> void:
	_sub_header("Oferecer um artigo")
	var inv: Dictionary = GameState.self_state.get("inventory", {})
	if inv.is_empty():
		box.add_child(UI.empty_state("bag", "Mochila vazia", "Compra artigos na Mercearia ou no Restaurante."))
	for it in inv:
		var item: String = it
		var row := UI.hbox(10)
		var ic := TextureRect.new()
		ic.texture = UI.item_icon(item, 36)
		ic.custom_minimum_size = Vector2(36, 36)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		row.add_child(ic)
		row.add_child(UI.title("%s  ×%d" % [WorldData.item_name(it), int(inv[it])], 14))
		var b := UI.button("Oferecer 1", func():
			_hud().confirm("Oferecer %s a %s?" % [WorldData.item_name(item), _name()], "Os presentes não podem ser anulados.", "Oferecer",
				func(): _send_gift({"kind": "item", "item": item, "qty": 1})), "secondary", "gift")
		b.custom_minimum_size = Vector2(0, 38)
		row.add_child(b)
		box.add_child(UI.card(row, Vector4(10, 6, 8, 6)))

func _send_gift(p: Dictionary) -> void:
	# req_id único por confirmação: o servidor ignora repetições (duplo toque, reenvio) — nunca transfere duas vezes
	var req := "%x%x" % [Time.get_ticks_usec(), randi()]
	if p.get("kind") == "money":
		NetworkManager.send_game("gift_money", {"target": pub, "amount": int(p["amount"]), "req_id": req})
	else:
		NetworkManager.send_game("gift_item", {"target": pub, "item": p["item"], "qty": int(p["qty"]), "req_id": req})
	_go("sending")

# ================================================================== posição: painel à direita / folha de baixo
func _place() -> void:
	if not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	var compact := vs.x < 760.0
	var w := vs.x - 16.0 if compact else 370.0
	custom_minimum_size = Vector2(w, 0)
	size = Vector2.ZERO
	await get_tree().process_frame
	if not is_instance_valid(scroll):
		return
	var bottom := vs.y - 70.0
	var top := 8.0
	var hud := _hud()
	if hud and "zoom_box" in hud:                 # no telemóvel: entre o HUD de cima e o dock/zoom, sem tapar nenhum
		bottom = minf(hud.dock.position.y, hud.zoom_box.position.y) - 6.0
		top = hud.content_top()
	var max_h := (bottom - top - 30.0) if compact else vs.y * 0.74
	scroll.custom_minimum_size = Vector2(w - 28.0, minf(box.get_combined_minimum_size().y, max_h))
	size = Vector2.ZERO
	var s := get_combined_minimum_size()
	position = Vector2(8.0, maxf(8.0, bottom - s.y)) if compact else Vector2(vs.x - s.x - 14.0, (vs.y - s.y) * 0.5)

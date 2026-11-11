extends PanelContainer
## Perfil social de OUTRO jogador (abre ao tocar/clicar nele). Só mostra dados públicos enviados pelo servidor:
## nome, avatar, nível, estado público, desde quando joga, nº de amigos e a relação contigo.
## Todas as ações são pedidos ao servidor, que decide (amizade, saldo, posse, permissões de chamada, convites).
## Ações agrupadas: Amizade (cabeçalho) · Convidar · Jogar · Presentes · Comunicar. Dinheiro/artigos pedem confirmação.

signal open_conversation(pub: String, name: String)
signal start_call(pub: String, name: String)

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Icons = preload("res://client/scripts/Icons.gd")
const VISUAL := preload("res://client/scenes/CharacterVisual.tscn")

var pub := ""
var prof: Dictionary = {}
var view := "main"            # main | places | gift_money | gift_item | confirm
var pending: Dictionary = {}  # presente a confirmar
var box: VBoxContainer
var _amount: LineEdit

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(k, 14)
	for k in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(k, 12)
	add_child(m)
	var sc := ScrollContainer.new()
	sc.name = "Scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(sc)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	NetworkManager.game_message.connect(_on_msg)
	GameState.social_changed.connect(_on_social_changed)
	get_viewport().size_changed.connect(_place)

func _noop() -> void:
	pass

func _set_amount(v: int) -> void:
	_amount.text = str(v)

func _on_social_changed() -> void:
	if visible and pub != "":
		_request()

func _do_message() -> void:
	var p := pub
	var n := str(prof.get("name", ""))
	close()                                  # fecha primeiro (close() limpa `pub`)
	open_conversation.emit(p, n)

func _do_call() -> void:
	var p := pub
	var n := str(prof.get("name", ""))
	close()
	start_call.emit(p, n)

func _invite_place(b_id: String) -> void:
	_send("invite", {"kind": "place", "place": b_id})
	_go("main")

func _pick_item(item: String) -> void:
	pending = {"kind": "item", "item": item, "qty": 1}
	_go("confirm")

func open(p: String) -> void:
	pub = p
	prof = {}
	view = "main"
	visible = true
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
				_render()
		"social_result":
			if str(msg.get("action", "")).begins_with("gift") and bool(msg.get("ok", false)):
				view = "main"
				_render()

# ------------------------------------------------------------------ construção
func _l(t: String, size: int, col: Color = UIStyle.TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:                                   # nunca alarga o painel além do ecrã (telemóvel): corta com "…"
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

func _b(t: String, cb: Callable, icon := "", primary := false, enabled := true, tip := "") -> Button:
	var b := Button.new()
	b.text = t
	if icon != "":
		b.icon = Icons.tex(icon, Color(0.1, 0.06, 0.02) if primary else UIStyle.TEXT, 18)
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = tip
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b

func _row(items: Array) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	for it in items:
		hb.add_child(it)
	return hb

func _section(t: String) -> void:
	box.add_child(_l(t.to_upper(), 11, UIStyle.DIM))

func _clear() -> void:
	for c in box.get_children():
		c.queue_free()

func _render() -> void:
	_clear()
	if prof.is_empty():
		box.add_child(_l("A carregar perfil…", 13, UIStyle.DIM))
		box.add_child(_b("Fechar", close))
		_place()
		return
	match view:
		"main":
			_render_main()
		"places":
			_render_places()
		"gift_money":
			_render_gift_money()
		"gift_item":
			_render_gift_item()
		"confirm":
			_render_confirm()
	_place()

func _header() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var av := Control.new()
	av.custom_minimum_size = Vector2(48, 56)
	av.clip_contents = true
	var fr := Panel.new()
	fr.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.add_theme_stylebox_override("panel", UIStyle.box(Color(0.16, 0.2, 0.17), UIStyle.GOLD, 2))
	fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(fr)
	var v: Node2D = VISUAL.instantiate()
	v.scale = Vector2(2, 2)
	v.position = Vector2(24, 86)
	av.add_child(v)
	v.apply_appearance(prof.get("appearance", {}))
	hb.add_child(av)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	vb.add_child(_l(str(prof.get("name", "")), 17, UIStyle.GOLD))
	vb.add_child(_l("Nível %d" % int(prof.get("level", 1)), 13))
	var st := _l(str(prof.get("status", "")), 12, Color(0.5, 0.9, 0.55) if prof.get("online", false) else UIStyle.DIM)
	vb.add_child(st)
	hb.add_child(vb)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.custom_minimum_size = Vector2(112, 0)
	match str(prof.get("relation", "none")):
		"none":
			right.add_child(_b("Adicionar", func(): _send("friend_request"), "plus", true))
		"request_sent":
			right.add_child(_l("Pedido enviado", 11, UIStyle.DIM))
			right.add_child(_b("Cancelar", func(): _send("friend_cancel")))
		"request_received":
			right.add_child(_b("Aceitar", func(): _send("friend_accept"), "", true))
			right.add_child(_b("Recusar", func(): _send("friend_decline")))
		"friends":
			right.add_child(_l("Amigos", 14, UIStyle.GOOD))
			right.add_child(_b("Remover", func(): _send("friend_remove")))
		"blocked":
			right.add_child(_b("Desbloquear", func(): _send("unblock")))
	hb.add_child(right)
	box.add_child(hb)

func _render_main() -> void:
	_header()
	box.add_child(HSeparator.new())
	var blocked := str(prof.get("relation", "")) == "blocked"
	if blocked:
		box.add_child(_l("Bloqueaste este jogador: não te pode contactar.", 13, UIStyle.DIM, true))
	else:
		_section("Convidar")
		box.add_child(_row([_b("Para minha casa", func(): _send("invite", {"kind": "house"}), "home"),
			_b("Sítio público…", func(): _go("places"), "shop")]))
		_section("Jogar")
		var games: Dictionary = GameState.social.get("games", {})
		box.add_child(_b("Jogar um jogo" if not games.is_empty() else "Jogar um jogo — sem jogos disponíveis ainda", _noop, "job", false, not games.is_empty(),
			"Os minijogos multijogador ainda não existem; o convite fica ativo quando forem registados."))
		_section("Presentes")
		box.add_child(_row([_b("Dinheiro", func(): _go("gift_money"), "wallet"), _b("Artigo", func(): _go("gift_item"), "bag")]))
		_section("Comunicar")
		var can_msg := bool(prof.get("can_message", true))
		var can_call := bool(prof.get("can_call", false))
		var call_tip := "" if can_call else ("Offline" if not prof.get("online", false) else "Esta pessoa não aceita chamadas tuas")
		box.add_child(_row([_b("Mensagem", _do_message, "chat", false, can_msg),
			_b("Ligar" if can_call else "Ligar (indisponível)", _do_call, "phone", false, can_call, call_tip)]))
	box.add_child(HSeparator.new())
	box.add_child(_l("A jogar desde %s · %d amigos" % [str(prof.get("since", "?")), int(prof.get("friends_count", 0))], 11, UIStyle.DIM))
	var foot := _row([_b("Bloquear" if not blocked else "Desbloquear", func(): _send("unblock" if blocked else "block")), _b("Fechar", close)])
	box.add_child(foot)

func _render_places() -> void:
	box.add_child(_l("Convidar %s para…" % prof.get("name", ""), 16, UIStyle.GOLD))
	var places: Dictionary = GameState.social.get("places", {})
	for bid in places:
		var b_id: String = bid
		box.add_child(_b(str(places[bid]), _invite_place.bind(b_id), "enter"))
	box.add_child(_b("Voltar", func(): _go("main"), "back"))

func _render_gift_money() -> void:
	var money := int(GameState.self_state.get("money", 0))
	box.add_child(_l("Enviar dinheiro a %s" % prof.get("name", ""), 16, UIStyle.GOLD))
	box.add_child(_l("O teu saldo: %s" % GameState.fmt_kz(money), 12, UIStyle.DIM))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	for v in [500, 1000, 5000]:
		var amt: int = v
		presets.add_child(_b(GameState.fmt_kz(v), _set_amount.bind(amt), "", false, money >= v))
	box.add_child(presets)
	var field := PanelContainer.new()
	field.theme_type_variation = "FieldBox"
	_amount = LineEdit.new()
	_amount.placeholder_text = "Outro valor (Kz)"
	_amount.max_length = 7
	_amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.add_child(_amount)
	box.add_child(field)
	box.add_child(_row([_b("Voltar", func(): _go("main"), "back"), _b("Continuar", _confirm_money, "", true)]))

func _confirm_money() -> void:
	var t := _amount.text.strip_edges()
	if not t.is_valid_int() or int(t) <= 0:
		get_tree().call_group("hud", "notify", "Escreve um valor válido.", false)
		return
	pending = {"kind": "money", "amount": int(t)}
	_go("confirm")

func _render_gift_item() -> void:
	box.add_child(_l("Oferecer um artigo a %s" % prof.get("name", ""), 16, UIStyle.GOLD))
	var inv: Dictionary = GameState.self_state.get("inventory", {})
	if inv.is_empty():
		box.add_child(_l("Não tens artigos. Compra-os na Mercearia ou no Restaurante.", 13, UIStyle.DIM, true))
	for it in inv:
		var item: String = it
		var have := int(inv[it])
		box.add_child(_row([_l("%s ×%d" % [WorldData.item_name(it), have], 14), _b("Oferecer 1", _pick_item.bind(item))]))
	box.add_child(_b("Voltar", func(): _go("main"), "back"))

func _render_confirm() -> void:
	box.add_child(_l("Confirmar presente", 16, UIStyle.GOLD))
	var what := GameState.fmt_kz(int(pending.get("amount", 0))) if pending.get("kind") == "money" else "%s ×%d" % [WorldData.item_name(str(pending.get("item", ""))), int(pending.get("qty", 1))]
	box.add_child(_l("Vais enviar %s a %s." % [what, prof.get("name", "")], 15, UIStyle.TEXT, true))
	if pending.get("kind") == "money":
		box.add_child(_l("Saldo depois: %s" % GameState.fmt_kz(int(GameState.self_state.get("money", 0)) - int(pending["amount"])), 12, UIStyle.DIM))
	box.add_child(_l("Os presentes não podem ser anulados.", 11, UIStyle.DIM))
	box.add_child(_row([_b("Cancelar", func(): _go("main")), _b("Enviar", _send_gift, "send", true)]))

func _send_gift() -> void:
	# req_id único por confirmação: o servidor ignora repetições (duplo toque, reenvio) — nunca transfere duas vezes
	var req := "%x%x" % [Time.get_ticks_usec(), randi()]
	if pending.get("kind") == "money":
		NetworkManager.send_game("gift_money", {"target": pub, "amount": int(pending["amount"]), "req_id": req})
	else:
		NetworkManager.send_game("gift_item", {"target": pub, "item": pending["item"], "qty": int(pending["qty"]), "req_id": req})
	view = "sending"
	_clear()
	box.add_child(_l("A enviar…", 14, UIStyle.DIM))

func _go(v: String) -> void:
	view = v
	_render()

func _send(type: String, extra: Dictionary = {}) -> void:
	var d := extra.duplicate()
	d["target"] = pub
	NetworkManager.send_game(type, d)

func _place() -> void:
	var vs := get_viewport_rect().size
	var compact := vs.x < 760.0
	var w := vs.x - 16.0 if compact else 360.0
	custom_minimum_size = Vector2(w, 0)
	size = Vector2.ZERO
	await get_tree().process_frame
	var sc: ScrollContainer = get_node("MarginContainer/Scroll") if has_node("MarginContainer/Scroll") else get_child(0).get_child(0)
	sc.custom_minimum_size = Vector2(w - 28.0, minf(box.get_combined_minimum_size().y, vs.y * (0.55 if compact else 0.7)))
	size = Vector2.ZERO
	var s := get_combined_minimum_size()
	position = Vector2(8.0, vs.y - s.y - 8.0) if compact else Vector2(vs.x - s.x - 12.0, (vs.y - s.y) * 0.5)

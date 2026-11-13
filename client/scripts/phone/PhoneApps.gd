extends RefCounted
## Apps do telemóvel e widgets do ecrã principal. Cada app é uma pilha de páginas (os.push) com barra de navegação,
## título grande, listas agrupadas e controlos nativos. Os dados vêm do servidor (GameState) e todas as ações são
## pedidos ao servidor; confirmações usam alertas/folhas de ações do sistema.

const Kit = preload("res://client/scripts/phone/PhoneKit.gd")

var os                     # Phone.gd
var profile: Dictionary = {}

func _init(phone) -> void:
	os = phone

var k: float:
	get: return os.k
var pal: Dictionary:
	get: return os.pal

func L(text: String, pt: float, col: Color, weight: String = "regular", wrap: bool = false) -> Label:
	return Kit.label(text, pt, k, col, weight, wrap)

# ================================================================== blocos de interface (listas agrupadas iOS)
func section(body: Control, header: String = "", footer: String = "") -> VBoxContainer:
	if header != "":
		var h := L(header.to_upper(), 13, pal["label2"])
		var hm := MarginContainer.new()
		hm.add_theme_constant_override("margin_left", int(16 * k))
		hm.add_theme_constant_override("margin_top", int(10 * k))
		hm.add_child(h)
		body.add_child(hm)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.rounded(pal["card"], 10 * k))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	card.add_child(vb)
	body.add_child(card)
	if footer != "":
		var f := L(footer, 13, pal["label2"], "regular", true)
		var fm := MarginContainer.new()
		fm.add_theme_constant_override("margin_left", int(16 * k))
		fm.add_theme_constant_override("margin_right", int(16 * k))
		fm.add_child(f)
		body.add_child(fm)
	return vb

func _sep(vb: VBoxContainer, inset: float) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(inset))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := ColorRect.new()
	r.color = pal["sep"]
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(r)
	vb.add_child(m)

## Linha de lista. o: {sub, detail, app, glyph:[nome, cor], avatar:nome, tap:Callable, accessory:Control,
## destructive, tint, center, check, dot:Color, no_chevron, title_col}
func row(vb: VBoxContainer, title: String, o: Dictionary = {}) -> Control:
	var lead := 0.0
	if o.has("app") or o.has("glyph"):
		lead = 45 * k
	elif o.has("avatar"):
		lead = 56 * k
	if vb.get_child_count() > 0:
		_sep(vb, 16 * k + lead)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", int(16 * k))
	mc.add_theme_constant_override("margin_right", int(14 * k))
	mc.add_theme_constant_override("margin_top", int(6 * k))
	mc.add_theme_constant_override("margin_bottom", int(6 * k))
	mc.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(12 * k))
	hb.custom_minimum_size = Vector2(0, 32 * k)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(hb)
	if o.has("dot"):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(10 * k, 10 * k)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", Kit.rounded(o["dot"], 5 * k))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(dot)
	if o.has("app"):
		var tr := TextureRect.new()
		tr.texture = Kit.app_icon(str(o["app"]), int(29 * k))
		tr.custom_minimum_size = Vector2(29 * k, 29 * k)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tr)
	elif o.has("glyph"):
		var gp := PanelContainer.new()
		gp.add_theme_stylebox_override("panel", Kit.rounded(o["glyph"][1], 7 * k))
		gp.custom_minimum_size = Vector2(29 * k, 29 * k)
		gp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var gt := TextureRect.new()
		gt.texture = Kit.glyph(str(o["glyph"][0]), Color.WHITE, int(18 * k))
		gt.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		gt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gp.add_child(gt)
		hb.add_child(gp)
	elif o.has("avatar"):
		var av := Kit.avatar(str(o["avatar"]), 44 * k, k)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(av)
	var vt := VBoxContainer.new()
	vt.add_theme_constant_override("separation", int(1 * k))
	vt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vt)
	var tcol: Color = pal["red"] if o.get("destructive", false) else (pal["tint"] if o.get("tint", false) else o.get("title_col", pal["label"]))
	var tl := Kit.ellipsis(L(title, 17, tcol, o.get("weight", "regular")))
	if o.get("center", false):
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vt.add_child(tl)
	if o.has("sub") and str(o["sub"]) != "":
		var sl := L(str(o["sub"]), 14, pal["label2"], "regular", true)
		sl.max_lines_visible = 2
		vt.add_child(sl)
	if o.has("detail"):
		var dl := L(str(o["detail"]), 17, o.get("detail_col", pal["label2"]))
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(dl)
	if o.has("accessory"):
		var a: Control = o["accessory"]
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(a)
	if o.get("check", false):
		var ck := TextureRect.new()
		ck.texture = Kit.glyph("check", pal["tint"], int(20 * k), 2.6)
		ck.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ck)
	if o.has("tap") and not o.get("no_chevron", false) and not o.get("center", false) and not o.get("destructive", false) and not o.has("check_row"):
		var ch := TextureRect.new()
		ch.texture = Kit.glyph("chev_r", pal["label3"], int(16 * k), 2.6)
		ch.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ch)
	if o.has("tap"):
		os.tappable(mc, o["tap"])
	vb.add_child(mc)
	return mc

func pill_button(text: String, cb: Callable, enabled: bool = true, col: Color = Color(0, 0, 0, 0)) -> Button:
	var c: Color = pal["tint"] if col.a == 0 else col
	var b := Kit.text_button(text, 15, k, c, "semibold", Color(c, 0.14) if not pal["dark"] else Color(c, 0.22))
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c)
	b.add_theme_color_override("font_pressed_color", Color(c, 0.6))
	b.add_theme_stylebox_override("normal", Kit.rounded(Color(c, 0.14), 15 * k, Color(), 0, Vector4(12 * k, 4 * k, 12 * k, 4 * k)))
	b.add_theme_stylebox_override("hover", Kit.rounded(Color(c, 0.18), 15 * k, Color(), 0, Vector4(12 * k, 4 * k, 12 * k, 4 * k)))
	b.add_theme_stylebox_override("pressed", Kit.rounded(Color(c, 0.3), 15 * k, Color(), 0, Vector4(12 * k, 4 * k, 12 * k, 4 * k)))
	b.add_theme_stylebox_override("disabled", Kit.rounded(Color(pal["fill"]), 15 * k, Color(), 0, Vector4(12 * k, 4 * k, 12 * k, 4 * k)))
	b.disabled = not enabled
	b.pressed.connect(func():
		if not os._claimed:
			cb.call())
	return b

func empty_state(body: Control, glyph: String, title: String, text: String) -> void:
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", int(8 * k))
	vb.custom_minimum_size = Vector2(0, 360 * k)
	var tr := TextureRect.new()
	tr.texture = Kit.glyph(glyph, pal["label3"], int(64 * k), 1.6)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	vb.add_child(tr)
	var t := L(title, 22, pal["label"], "bold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var x := L(text, 15, pal["label2"], "regular", true)
	x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(x)
	body.add_child(vb)

static func game_clock(g: float) -> String:
	return "Dia %d, %02d:%02d" % [int(g / 86400.0) + 1, int(g / 3600.0) % 24, int(g / 60.0) % 60]

func my_name() -> String:
	return str(GameState.current_character.get("name", GameState.self_state.get("name", "Eu")))

# ================================================================== registo das apps
func badge_count(id: String) -> int:
	match id:
		"mensagens":
			return GameState.unread_messages()
		"amigos":
			return (GameState.social.get("incoming", []) as Array).size()
	return 0

func open(id: String) -> void:
	match id:
		"mensagens":
			os.push({"title": "Mensagens", "large": true, "bg": "bg", "key": "msgs", "build": _messages_root}, false)
		"amigos":
			os.push({"title": "Amigos", "large": true, "key": "friends", "build": _friends_root}, false)
		"banco":
			os.push({"title": "Banco", "large": true, "key": "bank", "build": _bank_root}, false)
		"emprego":
			os.push({"title": "Emprego", "large": true, "key": "jobs", "build": _jobs_root}, false)
		"imoveis":
			os.push({"title": "Imóveis", "large": true, "key": "homes", "build": _homes_root}, false)
		"negocios":
			os.push({"title": "Negócios", "large": true, "key": "biz", "build": func(body): empty_state(body, "shop", "Em breve", "Abrir e gerir o teu próprio negócio chega numa próxima atualização.")}, false)
		"governo":
			NetworkManager.send_game("profile_request")
			os.push({"title": "Governo", "large": true, "key": "gov", "build": _gov_root}, false)
		"definicoes":
			os.push({"title": "Definições", "large": true, "key": "settings", "build": _settings_root}, false)
		"jogos":
			os.push({"title": "Jogos", "large": true, "key": "games", "build": _games_root}, false)

# ================================================================== Mensagens
func _messages_root(body: Control) -> void:
	var near := section(body)
	var last_near := ""
	if not GameState.chat_log.is_empty():
		var lm: Dictionary = GameState.chat_log[-1]
		last_near = "%s: %s" % [lm["name"], lm["text"]]
	row(near, "Perto de ti", {"glyph": ["chat", pal["green"]], "sub": last_near if last_near != "" else "Conversa com quem está na mesma zona", "tap": open_near})
	var convs: Array = GameState.social.get("conversations", [])
	var sec := section(body, "Conversas", "Toca num jogador no mundo e escolhe «Mensagem» para começar uma conversa privada." if convs.is_empty() else "")
	if convs.is_empty():
		row(sec, "Sem conversas privadas", {"title_col": pal["label2"]})
	for c in convs:
		var unread := int(c.get("unread", 0))
		var prev := ("Tu: " if c.get("last_mine", false) else "") + str(c.get("last", ""))
		var o := {"avatar": str(c["name"]), "sub": prev, "detail": os.ago(float(c.get("t", 0))) if float(c.get("t", 0)) > 0 else "",
			"weight": "semibold", "tap": open_conversation.bind(str(c["pub"]), str(c["name"]))}
		if unread > 0:
			o["dot"] = pal["tint"]
		row(sec, str(c["name"]), o)

func _bubble(list: Control, text: String, mine: bool, who: String = "", t: String = "") -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", int(2 * k))
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if who != "":
		var w := L(who, 12, pal["label2"], "medium")
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
		wrap.add_child(w)
	var bub := PanelContainer.new()
	bub.add_theme_stylebox_override("panel", Kit.rounded(pal["tint"] if mine else pal["bubble_in"], 18 * k, Color(), 0, Vector4(12 * k, 7 * k, 12 * k, 7 * k)))
	bub.size_flags_horizontal = Control.SIZE_SHRINK_END if mine else Control.SIZE_SHRINK_BEGIN
	var maxw: float = os.W * 0.72
	var f := Kit.font("regular")
	var fs := Kit.fsize(17, k)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2
	var tl := L(text, 17, Color.WHITE if mine else pal["label"], "regular", true)
	tl.custom_minimum_size = Vector2(minf(tw, maxw - 24 * k), 0)
	bub.add_child(tl)
	wrap.add_child(bub)
	if t != "":
		var tl2 := L(t, 11, pal["label3"])
		tl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT
		wrap.add_child(tl2)
	list.add_child(wrap)

func _compose(hb: HBoxContainer, placeholder: String, send: Callable) -> void:
	var e := Kit.field(placeholder, pal, k)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.max_length = 500
	hb.add_child(e)
	os.watch_field(e)
	var go := func():
		var t := e.text.strip_edges()
		if t != "":
			send.call(t)
			e.text = ""
	e.text_submitted.connect(func(_t): go.call())
	var sb := PanelContainer.new()
	sb.add_theme_stylebox_override("panel", Kit.rounded(pal["tint"], 16 * k))
	sb.custom_minimum_size = Vector2(32 * k, 32 * k)
	sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ar := TextureRect.new()
	ar.texture = Kit.glyph("up", Color.WHITE, int(20 * k), 2.6)
	ar.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sb.add_child(ar)
	hb.add_child(sb)
	os.tappable(sb, go)

func open_conversation(pub: String, name: String) -> void:
	if os.top_key() == "conv:" + pub:
		return
	while os.nav.size() > 1:
		os.pop(false)
	os.push({"title": name, "key": "conv:" + pub, "bg": "bg", "anchor_bottom": true,
		"right": [["icon:info", func(): _open_profile(pub)], ["icon:phone_fill", func(): os.request_call(pub, name)]],
		"build": func(body): _conversation(body, pub), "bottom": func(hb): _compose(hb, "Mensagem", func(t): NetworkManager.send_game("dm_send", {"target": pub, "text": t}))})
	NetworkManager.send_game("dm_history", {"target": pub})
	os.scroll_to_bottom()

func _conversation(body: Control, pub: String) -> void:
	var msgs: Array = GameState.dm_cache.get(pub, [])
	if msgs.is_empty():
		var e := L("Sem mensagens. Diz olá!", 15, pal["label2"])
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(e)
	var last_t := 0.0
	for m in msgs:
		var t := float(m.get("t", 0))
		if t - last_t > 600:
			var h := L(GameState.time_label(t), 12, pal["label2"], "medium")
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			body.add_child(h)
		last_t = t
		_bubble(body, str(m.get("text", "")), bool(m.get("mine", false)))

func open_near() -> void:
	os.push({"title": "Perto de ti", "key": "near", "bg": "bg", "anchor_bottom": true, "build": _near,
		"bottom": func(hb): _compose(hb, "Mensagem para quem está perto", func(t): NetworkManager.send_game("chat", {"text": t}))})
	os.scroll_to_bottom()

func _near(body: Control) -> void:
	if GameState.chat_log.is_empty():
		var e := L("As mensagens chegam a quem está na mesma zona e perto de ti.", 15, pal["label2"], "regular", true)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(e)
	var me := my_name()
	for m in GameState.chat_log:
		var mine: bool = str(m["name"]) == me
		_bubble(body, str(m["text"]), mine, "" if mine else str(m["name"]), str(m["t"]))

func on_dm_event(msg: Dictionary) -> void:
	var with := str(msg.get("with", ""))
	match str(msg.get("type", "")):
		"dm_history":
			GameState.dm_cache[with] = msg.get("messages", [])
			if os.top_key() == "conv:" + with:
				os.refresh()
				os.scroll_to_bottom()
		"dm_message":
			if os.is_conversation_open(with):
				NetworkManager.send_game("dm_read", {"target": with})
				for c in GameState.social.get("conversations", []):
					if c["pub"] == with:
						c["unread"] = 0
				os.refresh()
				os.scroll_to_bottom()
		"dm_sent":
			if bool(msg.get("ok", false)):
				if not GameState.dm_cache.has(with):
					GameState.dm_cache[with] = []
				(GameState.dm_cache[with] as Array).append(msg.get("data", {}))
				if os.top_key() == "conv:" + with:
					os.refresh()
					os.scroll_to_bottom()
			else:
				os.alert("Mensagem não enviada", str(msg.get("text", "")), [["OK", func(): pass, "cancel"]])

func _open_profile(pub: String) -> void:
	os.close()
	os.get_tree().call_group("hud", "open_profile", pub)

# ================================================================== Amigos (contactos)
func _friends_root(body: Control) -> void:
	var me := section(body)
	var lvl: Dictionary = GameState.self_state.get("level", {})
	row(me, my_name(), {"avatar": my_name(), "sub": "O meu cartão · Nível %d" % int(lvl.get("level", 1)), "weight": "semibold"})
	var soc: Dictionary = GameState.social
	var inc: Array = soc.get("incoming", [])
	if not inc.is_empty():
		var rq := section(body, "Pedidos de amizade")
		for f in inc:
			var pub := str(f["pub"])
			var acc := HBoxContainer.new()
			acc.add_theme_constant_override("separation", int(6 * k))
			acc.add_child(pill_button("Aceitar", func(): NetworkManager.send_game("friend_accept", {"target": pub})))
			acc.add_child(pill_button("Recusar", func(): NetworkManager.send_game("friend_decline", {"target": pub}), true, pal["label2"]))
			row(rq, str(f["name"]), {"avatar": str(f["name"]), "sub": "Nível %d" % int(f.get("level", 1)), "accessory": acc})
	var fr: Array = soc.get("friends", [])
	var online := fr.filter(func(f): return bool(f.get("online", false)))
	var offline := fr.filter(func(f): return not bool(f.get("online", false)))
	if fr.is_empty():
		var s := section(body, "Amigos", "Ainda não tens amigos. Toca noutro jogador no mundo para o adicionar.")
		row(s, "Sem amigos", {"title_col": pal["label2"]})
	for grp in [["Online", online], ["Offline", offline]]:
		if (grp[1] as Array).is_empty():
			continue
		var s2 := section(body, "%s · %d" % [grp[0], (grp[1] as Array).size()])
		for f in grp[1]:
			var o := {"avatar": str(f["name"]), "sub": "Nível %d" % int(f.get("level", 1)), "tap": _contact.bind(f)}
			if f.get("online", false):
				o["dot"] = pal["green"]
			row(s2, str(f["name"]), o)
	var outg: Array = soc.get("outgoing", [])
	if not outg.is_empty():
		var so := section(body, "Pedidos enviados")
		for f in outg:
			var pub2 := str(f["pub"])
			row(so, str(f["name"]), {"avatar": str(f["name"]), "accessory": pill_button("Cancelar", func(): NetworkManager.send_game("friend_cancel", {"target": pub2}), true, pal["label2"])})

func _contact(f: Dictionary) -> void:
	var pub := str(f["pub"])
	var name := str(f["name"])
	os.push({"title": name, "key": "contact:" + pub, "build": func(body):
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", int(6 * k))
		var av := Kit.avatar(name, 96 * k, k)
		av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		head.add_child(av)
		var nl := L(name, 28, pal["label"], "semibold")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(nl)
		var on := false
		for x in GameState.social.get("friends", []):
			if x["pub"] == pub:
				on = bool(x.get("online", false))
		var st := L(("Online" if on else "Offline") + " · Nível %d" % int(f.get("level", 1)), 15, pal["green"] if on else pal["label2"])
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(st)
		body.add_child(head)
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", int(8 * k))
		for a in [["chat", "mensagem", func(): open_conversation_from_contact(pub, name), true], ["phone", "ligar", func(): os.request_call(pub, name), on], ["user", "perfil", func(): _open_profile(pub), true]]:
			var tile := PanelContainer.new()
			tile.add_theme_stylebox_override("panel", Kit.rounded(pal["card"], 10 * k, Color(), 0, Vector4(0, 8 * k, 0, 8 * k)))
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tv := VBoxContainer.new()
			tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var col: Color = pal["tint"] if a[3] else pal["label3"]
			var ti := TextureRect.new()
			ti.texture = Kit.glyph(str(a[0]), col, int(22 * k))
			ti.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			tv.add_child(ti)
			var tl := L(str(a[1]), 12, col, "medium")
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tv.add_child(tl)
			tile.add_child(tv)
			acts.add_child(tile)
			if a[3]:
				os.tappable(tile, a[2])
		body.add_child(acts)
		var danger := section(body)
		row(danger, "Remover amigo", {"destructive": true, "tap": func(): os.alert("Remover %s?" % name, "Deixam de ser amigos. Podes voltar a enviar um pedido mais tarde.",
			[["Cancelar", func(): pass, "cancel"], ["Remover", func():
				NetworkManager.send_game("friend_remove", {"target": pub})
				os.pop(), "destructive"]])})
		row(danger, "Bloquear", {"destructive": true, "tap": func(): os.alert("Bloquear %s?" % name, "Deixa de te poder enviar mensagens, convites, presentes e chamadas.",
			[["Cancelar", func(): pass, "cancel"], ["Bloquear", func():
				NetworkManager.send_game("block", {"target": pub})
				os.pop(), "destructive"]])})})

func open_conversation_from_contact(pub: String, name: String) -> void:
	os.open_app("mensagens", false)
	open_conversation(pub, name)

# ================================================================== Jogos (minijogos multijogador)
func _match_panel() -> Node:
	var h: Node = os.get_tree().get_first_node_in_group("hud")
	return h.match_panel if h else null

func _games_root(body: Control) -> void:
	var mp := _match_panel()
	if mp and mp.has_match():
		var cur := section(body, "Partida")
		var md: Dictionary = mp.m
		row(cur, str(md.get("name", "Jogo")), {"glyph": ["gamepad", pal["tint"]], "sub": "A decorrer · toca para voltar" if mp.active() else "Terminou · ver resultado",
			"weight": "semibold", "tap": func():
				os.close()
				mp.expand()})
	var games: Dictionary = GameState.social.get("games", {})
	var sec := section(body, "Jogar com amigos", "Escolhe um jogo e convida um amigo online. O convite expira em 2 minutos.")
	if games.is_empty():
		row(sec, "Sem jogos disponíveis", {"title_col": pal["label2"]})
	for gid in games:
		var g: Dictionary = games[gid]
		row(sec, str(g.get("name", gid)), {"app": "jogos", "sub": "%d jogadores · %s" % [int(g.get("max_players", 2)), str(g.get("desc", ""))], "tap": _game_page.bind(str(gid))})

func _game_page(gid: String) -> void:
	var g: Dictionary = GameState.social.get("games", {}).get(gid, {})
	os.push({"title": str(g.get("name", gid)), "key": "game:" + gid, "build": func(body):
		var about := section(body)
		row(about, str(g.get("name", gid)), {"app": "jogos", "sub": str(g.get("desc", "")), "weight": "semibold"})
		var fr: Array = GameState.social.get("friends", [])
		var online := fr.filter(func(f): return bool(f.get("online", false)))
		var mp := _match_panel()
		var busy: bool = mp != null and mp.active()
		var foot := "Já estás numa partida. Termina-a antes de convidar." if busy else ("Nenhum amigo online agora." if online.is_empty() else "")
		var sec := section(body, "Amigos online · %d" % online.size(), foot)
		if fr.is_empty():
			row(sec, "Ainda não tens amigos", {"title_col": pal["label2"]})
		for f in online:
			var pub := str(f["pub"])
			var nm := str(f["name"])
			row(sec, nm, {"avatar": nm, "dot": pal["green"], "sub": "Nível %d" % int(f.get("level", 1)),
				"accessory": pill_button("Convidar", func(): NetworkManager.send_game("invite", {"target": pub, "kind": "game", "game": gid}), not busy)})
		var off := fr.filter(func(f): return not bool(f.get("online", false)))
		if not off.is_empty():
			var so := section(body, "Offline · %d" % off.size())
			for f in off:
				row(so, str(f["name"]), {"avatar": str(f["name"]), "sub": "Só podes convidar amigos online", "title_col": pal["label2"]})})

# ================================================================== Banco
func _bank_root(body: Control) -> void:
	var st: Dictionary = GameState.self_state
	var card := PanelContainer.new()
	var cs := Kit.rounded(Color8(16, 42, 78), 18 * k, Color(), 0, Vector4(20 * k, 18 * k, 20 * k, 18 * k))
	cs.bg_color = Color8(18, 46, 86)
	cs.shadow_color = Color(0, 0, 0, 0.18)
	cs.shadow_size = int(10 * k)
	card.add_theme_stylebox_override("panel", cs)
	card.custom_minimum_size = Vector2(0, 190 * k)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", int(4 * k))
	card.add_child(cv)
	var top := HBoxContainer.new()
	var bn := L("BANCO KIANDA", 14, Color(1, 1, 1, 0.9), "bold")
	bn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(bn)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(34 * k, 24 * k)
	chip.add_theme_stylebox_override("panel", Kit.rounded(Color8(232, 192, 96), 5 * k))
	top.add_child(chip)
	cv.add_child(top)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(sp)
	cv.add_child(L("Saldo disponível", 13, Color(1, 1, 1, 0.7)))
	cv.add_child(L(GameState.fmt_kz(int(st.get("money", 0))), 34, Color.WHITE, "bold"))
	var bot := HBoxContainer.new()
	var nm := L(my_name().to_upper(), 13, Color(1, 1, 1, 0.85), "medium")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(nm)
	bot.add_child(L("•••• %04d" % (abs(my_name().hash()) % 10000), 13, Color(1, 1, 1, 0.85), "medium"))
	cv.add_child(bot)
	body.add_child(card)
	var txs: Array = st.get("transactions", [])
	var sec := section(body, "Movimentos", "Salários, compras, rendas e presentes, registados pelo servidor.")
	if txs.is_empty():
		row(sec, "Sem movimentos", {"title_col": pal["label2"]})
	for i in range(txs.size() - 1, -1, -1):
		var t: Dictionary = txs[i]
		var amt := int(t.get("amount", 0))
		row(sec, str(t.get("desc", "")), {"glyph": ["plus" if amt > 0 else "minus", pal["green"] if amt > 0 else pal["label2"]],
			"sub": game_clock(float(t.get("t", 0))), "detail": ("+" if amt > 0 else "−") + GameState.fmt_kz(absi(amt)),
			"detail_col": pal["green"] if amt > 0 else pal["label"], "tap": _tx_detail.bind(t)})

func _tx_detail(t: Dictionary) -> void:
	var amt := int(t.get("amount", 0))
	os.push({"title": "Movimento", "key": "tx", "build": func(body):
		var big := L(("+" if amt > 0 else "−") + GameState.fmt_kz(absi(amt)), 40, pal["green"] if amt > 0 else pal["label"], "bold")
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(big)
		var d := L(str(t.get("desc", "")), 17, pal["label2"], "regular", true)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(d)
		var s := section(body)
		row(s, "Data", {"detail": game_clock(float(t.get("t", 0)))})
		row(s, "Tipo", {"detail": "Entrada" if amt > 0 else "Saída"})
		if t.has("balance"):
			row(s, "Saldo após", {"detail": GameState.fmt_kz(int(t["balance"]))})})

# ================================================================== Emprego
func _jobs_root(body: Control) -> void:
	var st: Dictionary = GameState.self_state
	var job: Variant = st.get("job")
	var jobs: Dictionary = WorldData.data["jobs"]
	if job != null and jobs.has(job):
		var jd: Dictionary = jobs[job]
		var s := section(body, "Emprego atual", "Vai ao local de trabalho e usa um posto (secretária / fogão) para trabalhar um turno.")
		row(s, str(jd["name"]), {"app": "emprego", "weight": "semibold"})
		row(s, "Local", {"detail": str(WorldData.buildings[jd["building"]]["name"])})
		row(s, "Por turno", {"detail": GameState.fmt_kz(int(jd["pay"]))})
		var q := section(body)
		row(q, "Despedir-me", {"destructive": true, "tap": func(): os.alert("Despedir-te?", "Deixas de receber salário de %s." % jd["name"],
			[["Cancelar", func(): pass, "cancel"], ["Despedir-me", func(): NetworkManager.send_game("job_quit"), "destructive"]])})
	var v := section(body, "Vagas abertas" if job == null else "Outras vagas")
	var any := false
	for jid in jobs:
		if jid == job:
			continue
		any = true
		var jd2: Dictionary = jobs[jid]
		var jj: String = jid
		var go := func():
			if job == null:
				NetworkManager.send_game("job_apply", {"job": jj})
			else:
				os.alert("Mudar de emprego?", "Deixas o emprego atual e passas a %s." % jd2["name"], [["Cancelar", func(): pass, "cancel"], ["Mudar", func(): NetworkManager.send_game("job_apply", {"job": jj}), "default"]])
		row(v, str(jd2["name"]), {"sub": "%s · %s por turno" % [WorldData.buildings[jd2["building"]]["name"], GameState.fmt_kz(int(jd2["pay"]))],
			"accessory": pill_button("Candidatar", go)})
	if not any:
		row(v, "Sem outras vagas", {"title_col": pal["label2"]})

# ================================================================== Imóveis
func _homes_root(body: Control) -> void:
	var st: Dictionary = GameState.self_state
	var h: Dictionary = st.get("housing", {})
	var g := GameState.game_time()
	var s := section(body, "A tua casa")
	if h.get("status") == "arrendado" and float(h.get("until", 0)) > g:
		row(s, str(WorldData.data["rentals"].get(h.get("building", ""), {}).get("name", "?")), {"app": "imoveis", "weight": "semibold"})
		row(s, "Arrendado até", {"detail": game_clock(float(h.get("until", 0)))})
	else:
		row(s, "Sem-abrigo", {"glyph": ["home", pal["red"]], "sub": "Sem casa não podes dormir numa cama, tomar banho nem cozinhar. Os bancos da rua deixam-te descansar um pouco."})
	var r := section(body, "Para arrendar")
	for rid in WorldData.data["rentals"]:
		var rd: Dictionary = WorldData.data["rentals"][rid]
		var rr: String = rid
		row(r, str(rd["name"]), {"sub": "%s por dia · cama, duche e cozinha" % GameState.fmt_kz(int(rd["price_per_day"])), "tap": _rental.bind(rr)})

func _rental(rid: String) -> void:
	var rd: Dictionary = WorldData.data["rentals"][rid]
	os.push({"title": str(rd["name"]), "key": "rental", "build": func(body):
		var money := int(GameState.self_state.get("money", 0))
		var s := section(body, "Duração", "Saldo disponível: %s. O pagamento é feito pelo Banco." % GameState.fmt_kz(money))
		for days in rd["options"]:
			var dd := int(days)
			var cost := int(float(rd["price_per_day"]) * dd * (float(rd.get("discount_7", 1.0)) if dd == 7 else 1.0))
			var ok := money >= cost
			row(s, "%d dia%s" % [dd, "s" if dd > 1 else ""], {"detail": GameState.fmt_kz(cost), "title_col": pal["label"] if ok else pal["label3"],
				"sub": "desconto de %d%%" % roundi((1.0 - float(rd.get("discount_7", 1.0))) * 100) if dd == 7 and rd.has("discount_7") else "",
				"tap": func():
					if not ok:
						os.alert("Saldo insuficiente", "Precisas de %s." % GameState.fmt_kz(cost), [["OK", func(): pass, "cancel"]])
						return
					os.action_sheet("Arrendar %s por %d dia%s?" % [rd["name"], dd, "s" if dd > 1 else ""], [["Pagar %s" % GameState.fmt_kz(cost), func(): NetworkManager.send_game("rent", {"rental": rid, "days": dd}), false]])})})

# ================================================================== Governo
func _gov_root(body: Control) -> void:
	if profile.is_empty():
		var w := L("A consultar o registo…", 15, pal["label2"])
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(w)
		return
	var bg: Dictionary = profile.get("background", {})
	var fam: Dictionary = bg.get("family", {})
	var ch: Dictionary = bg.get("childhood", {})
	var card := PanelContainer.new()
	var cs := Kit.rounded(Color8(250, 246, 236), 14 * k, Color(), 0, Vector4(0, 0, 0, 14 * k))
	cs.shadow_color = Color(0, 0, 0, 0.15)
	cs.shadow_size = int(8 * k)
	card.add_theme_stylebox_override("panel", cs)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", int(6 * k))
	card.add_child(cv)
	var band := PanelContainer.new()
	var bs := Kit.rounded(Color8(204, 9, 47), 14 * k, Color(), 0, Vector4(14 * k, 8 * k, 14 * k, 8 * k))
	bs.corner_radius_bottom_left = 0
	bs.corner_radius_bottom_right = 0
	band.add_theme_stylebox_override("panel", bs)
	band.add_child(L("REPÚBLICA DE ANGOLA · BILHETE DE IDENTIDADE", 11, Color.WHITE, "bold"))
	cv.add_child(band)
	var stripe := ColorRect.new()
	stripe.color = Color8(20, 20, 20)
	stripe.custom_minimum_size = Vector2(0, 6 * k)
	cv.add_child(stripe)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", int(12 * k))
	var im := MarginContainer.new()
	for side in ["left", "right"]:
		im.add_theme_constant_override("margin_" + side, int(14 * k))
	im.add_child(inner)
	cv.add_child(im)
	inner.add_child(Kit.avatar(str(profile.get("name", "")), 64 * k, k))
	var iv := VBoxContainer.new()
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(iv)
	var dark := Color8(30, 30, 30)
	iv.add_child(L(str(profile.get("name", "")), 20, dark, "bold"))
	iv.add_child(L("Natural de %s (%s)" % [ch.get("neighbourhood", "?"), ch.get("province", "?")], 13, Color(dark, 0.75), "regular", true))
	iv.add_child(L("Filho(a) de %s e %s" % [fam.get("father_name", "?"), fam.get("mother_name", "?")], 13, Color(dark, 0.75), "regular", true))
	body.add_child(card)
	var s := section(body, "Historial", str(bg.get("starting_circumstances", {}).get("notes", "")))
	row(s, "Classe de origem", {"detail": str(bg.get("socioeconomic_label", "?"))})
	row(s, "Educação", {"sub": str(ch.get("education", "?"))})
	row(s, "Pai", {"sub": str(fam.get("father_profession", "?"))})
	row(s, "Mãe", {"sub": str(fam.get("mother_profession", "?"))})

# ================================================================== Definições
func _settings_root(body: Control) -> void:
	var lvl: Dictionary = GameState.self_state.get("level", {})
	var me := section(body)
	row(me, my_name(), {"avatar": my_name(), "sub": "Nível %d · Telemóvel Kianda" % int(lvl.get("level", 1)), "weight": "semibold"})
	var a := section(body)
	var dnd_sw := Kit.SwitchX.new(os.dnd, k)
	dnd_sw.on_col = pal["green"]
	dnd_sw.toggled.connect(func(v):
		os.dnd = v
		os.save_settings())
	row(a, "Não incomodar", {"glyph": ["moon", Color8(94, 92, 230)], "accessory": dnd_sw, "sub": "Sem faixas de notificação (ficam no sino)"})
	row(a, "Aspeto", {"glyph": ["sun", pal["tint"]], "detail": {"auto": "Automático", "light": "Claro", "dark": "Escuro"}[os.appearance], "tap": _appearance})
	var p := section(body)
	row(p, "Privacidade", {"glyph": ["lock", pal["tint"]], "detail": {"everyone": "Todos", "friends": "Amigos", "nobody": "Ninguém"}.get(str(GameState.social.get("privacy", {}).get("calls", "everyone")), ""), "tap": _privacy})
	var bl: Array = GameState.social.get("blocked", [])
	row(p, "Bloqueados", {"glyph": ["x", pal["red"]], "detail": str(bl.size()), "tap": _blocked})
	var snd := section(body, "Som e ecrã")
	var vol := Kit.SliderX.new(os.volume)
	vol.custom_minimum_size = Vector2(150 * k, 28 * k)
	vol.track_col = pal["fill"]
	vol.fill_col = pal["tint"]
	vol.changed.connect(func(v):
		os.volume = v
		os._apply_volume())
	row(snd, "Volume", {"glyph": ["speaker", pal["red"]], "accessory": vol})
	var br := Kit.SliderX.new(os.brightness)
	br.custom_minimum_size = Vector2(150 * k, 28 * k)
	br.track_col = pal["fill"]
	br.fill_col = pal["tint"]
	br.changed.connect(func(v):
		os.brightness = maxf(0.15, v)
		os.screen.modulate = Color(1, 1, 1).darkened(0.6 * (1.0 - os.brightness)))
	row(snd, "Brilho", {"glyph": ["sun", pal["orange"]], "accessory": br})
	var g := section(body)
	var dbg_on := false
	var dbg: Variant = os.get_tree().get_first_node_in_group("debug_overlay")
	if dbg and "visible" in dbg:
		dbg_on = bool(dbg.visible)
	var ds := Kit.SwitchX.new(dbg_on, k)
	ds.on_col = pal["green"]
	ds.toggled.connect(func(_v): os.get_tree().call_group("debug_overlay", "toggle"))
	row(g, "Informação técnica (F3)", {"glyph": ["bug", pal["orange"]], "accessory": ds})
	row(g, "Sobre", {"glyph": ["info", pal["label2"]], "tap": _about})
	var out := section(body)
	row(out, "Terminar sessão", {"destructive": true, "center": true, "tap": func(): os.alert("Terminar sessão?", "Voltas ao menu inicial. O teu progresso fica guardado no servidor.",
		[["Cancelar", func(): pass, "cancel"], ["Terminar", func():
			os.close()
			os.get_tree().call_group("world", "logout"), "destructive"]])})
	os.save_settings()

func _appearance() -> void:
	os.push({"title": "Aspeto", "key": "appearance", "build": func(body):
		var s := section(body, "", "Automático: escuro entre as 19:00 e as 06:00 do relógio do jogo.")
		for opt in [["auto", "Automático"], ["light", "Claro"], ["dark", "Escuro"]]:
			var v: String = opt[0]
			row(s, str(opt[1]), {"check": os.appearance == v, "check_row": true, "tap": func():
				os.appearance = v
				os.save_settings()
				os._rebuild_keep_state()})})

func _privacy() -> void:
	os.push({"title": "Privacidade", "key": "privacy", "build": func(body):
		var cur := str(GameState.social.get("privacy", {}).get("calls", "everyone"))
		var s := section(body, "Quem te pode ligar", "Aplicado pelo servidor de imediato. Jogadores bloqueados nunca te podem ligar.")
		for opt in [["everyone", "Todos"], ["friends", "Só amigos"], ["nobody", "Ninguém"]]:
			var v: String = opt[0]
			row(s, str(opt[1]), {"check": cur == v, "check_row": true, "tap": func(): NetworkManager.send_game("privacy_set", {"calls": v})})})

func _blocked() -> void:
	os.push({"title": "Bloqueados", "key": "blocked", "build": func(body):
		var bl: Array = GameState.social.get("blocked", [])
		var s := section(body, "", "Toca num jogador para o desbloquear.")
		if bl.is_empty():
			row(s, "Ninguém bloqueado", {"title_col": pal["label2"]})
		for f in bl:
			var pub := str(f["pub"])
			var nm := str(f["name"])
			row(s, nm, {"avatar": nm, "no_chevron": true, "tap": func(): os.alert("Desbloquear %s?" % nm, "", [["Cancelar", func(): pass, "cancel"], ["Desbloquear", func(): NetworkManager.send_game("unblock", {"target": pub}), "default"]])})})

func _about() -> void:
	os.push({"title": "Sobre", "key": "about", "build": func(body):
		var s := section(body)
		row(s, "Nome", {"detail": "Telemóvel de " + my_name()})
		row(s, "Modelo", {"detail": "Kianda 15"})
		row(s, "Software", {"detail": "KiandaOS 1.0"})
		row(s, "Operadora", {"detail": "Unitel"})
		row(s, "Rede", {"detail": ("%d ms" % int(NetworkManager.latency_ms)) if NetworkManager.latency_ms >= 0 else "—"})})

# ================================================================== widgets do ecrã principal
func widget(kind: String, sz: Vector2) -> Control:
	var p := PanelContainer.new()
	p.size = sz
	p.custom_minimum_size = sz
	p.add_theme_stylebox_override("panel", Kit.rounded(Color(1, 1, 1, 0.82) if not pal["dark"] else Color(0.1, 0.1, 0.12, 0.78), 22 * k, Color(), 0, Vector4(16 * k, 14 * k, 16 * k, 14 * k)))
	var fg: Color = Color.BLACK if not pal["dark"] else Color.WHITE
	if kind == "hoje":
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(hb)
		var l := VBoxContainer.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
		var g := GameState.game_time()
		var day := int(g / 86400.0)
		l.add_child(L(str(os.WEEKDAYS[day % 7]).to_upper(), 12, pal["red"], "bold"))
		l.add_child(L("Dia %d" % (day + 1), 30, fg, "bold"))
		var zone := "Rua"
		var w: Variant = os.get_tree().get_first_node_in_group("world")
		if w and "my_zone" in w:
			zone = WorldData.zone_label(str(w.my_zone))
		l.add_child(L(zone, 13, Color(fg, 0.6), "medium"))
		var r := VBoxContainer.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.alignment = BoxContainer.ALIGNMENT_END
		hb.add_child(r)
		var tl := L("%02d:%02d" % [int(g / 3600.0) % 24, int(g / 60.0) % 60], 30, fg, "semibold")
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(tl)
		var ml := L(GameState.fmt_kz(int(GameState.self_state.get("money", 0))), 15, pal["green"], "semibold")
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(ml)
		var hl := L("Luanda", 12, Color(fg, 0.5))
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(hl)
	else:
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", int(14 * k))
		hb2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(hb2)
		var rings := Rings.new()
		rings.custom_minimum_size = Vector2(sz.y - 28 * k, sz.y - 28 * k)
		rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var defs := [["hunger", "Fome", Color8(255, 149, 0)], ["energy", "Energia", Color8(255, 214, 10)], ["hygiene", "Higiene", Color8(90, 200, 250)], ["health", "Saúde", Color8(255, 55, 95)]]
		for d in defs:
			rings.values.append([clampf(GameState.need(str(d[0])) / 100.0, 0.0, 1.0), d[2]])
		hb2.add_child(rings)
		var leg := VBoxContainer.new()
		leg.alignment = BoxContainer.ALIGNMENT_CENTER
		leg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb2.add_child(leg)
		for d in defs:
			var row2 := HBoxContainer.new()
			row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var nl := L(str(d[1]), 14, d[2], "semibold")
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(nl)
			row2.add_child(L("%d%%" % roundi(GameState.need(str(d[0]))), 14, fg, "semibold"))
			leg.add_child(row2)
	return p

## Anéis concêntricos das necessidades (estilo "atividade").
class Rings extends Control:
	var values: Array = []
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		var w := r / (values.size() * 1.25 + 0.5)
		for i in values.size():
			var rr := r - w * 0.6 - i * w * 1.18
			var col: Color = values[i][1]
			draw_arc(c, rr, 0, TAU, 48, Color(col, 0.22), w, true)
			var v: float = values[i][0]
			if v > 0.0:
				draw_arc(c, rr, -PI / 2.0, -PI / 2.0 + TAU * v, 48, col, w, true)
				draw_circle(c + Vector2(0, -rr), w / 2.0, col)

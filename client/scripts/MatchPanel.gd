extends Control
## Partida de minijogo (por agora: Jogo do Galo). Painel escuro translúcido ao centro, com o mundo visível por trás.
## O cliente nunca decide nada: mostra o "game_state" do servidor e envia pedidos (game_move/leave/rematch).
## Pode ser minimizado (Esc, botão ou toque no mundo): fica uma pastilha no topo com o estado da partida.
## Sair a meio é desistir (pede confirmação). Desligar não acaba a partida logo: o servidor espera pelo regresso.

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const UI = preload("res://client/scripts/ui/UIKit.gd")
const MARK_COL := {"X": UIStyle.GOLD, "O": UIStyle.INFO}
const REASONS := {"forfeit": "desistiu", "disconnect": "saiu do jogo", "expired": "Partida parada demasiado tempo"}

var m: Dictionary = {}            # último game_state (vista do servidor para este jogador)
var panel: PanelContainer
var box: VBoxContainer
var pill: Button
var minimized := false
var _pending := -1                # casa pedida à espera do servidor (evita toques repetidos)
var _away := {}                   # pub -> segundos que faltam (contagem local)
var _status: Label
var _away_t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.surface(0.93, 20, Vector4(16, 14, 16, 16)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	add_child(panel)
	box = UI.vbox(12)
	panel.add_child(box)
	pill = Button.new()
	pill.focus_mode = Control.FOCUS_NONE
	pill.custom_minimum_size = Vector2(0, UIStyle.TOUCH)
	pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pill.add_theme_font_override("font", UIStyle.font("semibold"))
	pill.add_theme_font_size_override("font_size", 14)
	pill.add_theme_stylebox_override("normal", UIStyle.box(Color(UIStyle.SURFACE, 0.9), Color(UIStyle.GOLD, 0.45), 1, Vector4(16, 6, 16, 6), UIStyle.R_PILL))
	pill.add_theme_stylebox_override("hover", UIStyle.box(Color(UIStyle.SURFACE, 0.95), UIStyle.GOLD, 1, Vector4(16, 6, 16, 6), UIStyle.R_PILL))
	pill.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.PRESSED, UIStyle.GOLD, 1, Vector4(16, 6, 16, 6), UIStyle.R_PILL))
	pill.icon = preload("res://client/scripts/Icons.gd").tex("gamepad", UIStyle.GOLD, 18)
	pill.visible = false
	pill.pressed.connect(expand)
	add_child(pill)
	NetworkManager.game_message.connect(_on_msg)
	get_viewport().size_changed.connect(_place)

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")

# ================================================================== estado
func has_match() -> bool:
	return not m.is_empty()

func is_open() -> bool:
	return panel.visible

func active() -> bool:
	return str(m.get("status", "")) == "active"

func _me() -> Dictionary:
	var you := int(m.get("you", -1))
	var ps: Array = m.get("players", [])
	return ps[you] if you >= 0 and you < ps.size() else {}

func _other() -> Dictionary:
	var you := int(m.get("you", -1))
	for p in m.get("players", []):
		if int(p.get("seat", -1)) != you:
			return p
	return {}

func _on_msg(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"game_state":
			var d: Variant = msg.get("data")
			if not (d is Dictionary) or (d as Dictionary).is_empty():
				_clear_match()
				return
			var nm: Dictionary = d
			var you := int(nm.get("you", -1))
			if you < 0 or bool((nm["players"] as Array)[you].get("left", false)):
				if str(m.get("mid", "")) == str(nm.get("mid", "")):
					var r: Variant = nm.get("result")
					if r is Dictionary and str((r as Dictionary).get("reason", "")) == "forfeit" and active():
						var hh := _hud()
						if hh:
							hh.notify("Desististe da partida. %s ganhou." % str(_other().get("name", "")), false)
					_clear_match()
				return
			var fresh := str(m.get("mid", "")) != str(nm.get("mid", ""))
			m = nm
			_pending = -1
			_away = {}
			for k in (m.get("away_deadline", {}) as Dictionary):
				_away[k] = float(m["away_deadline"][k])
			if fresh:
				expand()                  # partida nova (ou revanche): abre à frente
			else:
				_render()
		"game_error":
			_pending = -1
			var h := _hud()
			if h:
				h.notify(str(msg.get("text", "")), false)
			_render()

func _clear_match() -> void:
	m = {}
	panel.visible = false
	pill.visible = false
	minimized = false

func request_state() -> void:
	NetworkManager.send_game("game_state_request")

# ================================================================== abrir / minimizar
func expand() -> void:
	if m.is_empty():
		return
	var h := _hud()
	if h and h.has_method("close_others_for_match"):
		h.close_others_for_match()
	minimized = false
	panel.visible = true
	pill.visible = false
	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.14)
	_render()

func minimize() -> void:
	if m.is_empty():
		return
	minimized = true
	panel.visible = false
	pill.visible = true
	_render()

func leave_confirmed() -> void:
	if active():
		var h := _hud()
		h.confirm("Desistir da partida?", "%s ganha esta partida." % str(_other().get("name", "O outro jogador")), "Desistir",
			func(): NetworkManager.send_game("game_leave", {"mid": m.get("mid")}), true)
	else:
		NetworkManager.send_game("game_leave", {"mid": m.get("mid")})
		_clear_match.call_deferred()         # depois do clique (o mesmo toque não passa para o mundo)

# ================================================================== desenho
func _render() -> void:
	if m.is_empty():
		return
	_update_pill()
	if not panel.visible:
		_place()
		return
	for c in box.get_children():
		box.remove_child(c)          # sai já do contentor (queue_free sozinho deixava-o contar no tamanho até ao fim do quadro)
		c.queue_free()
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 16.0, 380.0)
	panel.custom_minimum_size = Vector2(w, 0)
	var inner := w - 32.0
	# cabeçalho
	var head := UI.hbox(8)
	head.add_child(UI.icon("gamepad", UIStyle.GOLD, 18))
	head.add_child(UI.title(str(m.get("name", "Jogo")), 16, UIStyle.TEXT, "bold"))
	var series: Array = m.get("series", [0, 0])
	var you := int(m.get("you", 0))
	if series.size() == 2 and int(series[0]) + int(series[1]) > 0:
		head.add_child(UI.chip("%d – %d" % [int(series[you]), int(series[1 - you])], UIStyle.GOLD, "", 0.14))
	head.add_child(UI.icon_button("minus", minimize, "Minimizar (Esc)", 36, UIStyle.DIM))
	box.add_child(head)
	# jogadores
	var prow := UI.hbox(8)
	prow.add_child(_player_card(_me(), true, (inner - 8.0) / 2.0))
	prow.add_child(_player_card(_other(), false, (inner - 8.0) / 2.0))
	box.add_child(prow)
	# estado
	_status = UI.label(_status_text(), 15, _status_col(), "semibold", true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(inner, 0)
	box.add_child(_status)
	# tabuleiro
	box.add_child(_board(inner))
	# ações
	var actions := UI.hbox(8)
	if active():
		var q := UI.button("Desistir", leave_confirmed, "ghost")
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(q)
	else:
		var other := _other()
		var mine_voted := bool(_me().get("rematch", false))
		var can := not bool(other.get("left", false)) and bool(other.get("online", false))
		var rtxt := "À espera de %s…" % str(other.get("name", "")) if mine_voted else ("Revanche" if can else "Revanche indisponível")
		var r := UI.button(rtxt, func(): NetworkManager.send_game("game_rematch", {"mid": m.get("mid")}), "primary", "", can and not mine_voted,
			"" if can else "%s já não está na partida." % str(other.get("name", "")))
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(r)
		var s := UI.button("Sair", leave_confirmed, "secondary")
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(s)
	box.add_child(actions)
	_place()
	_place.call_deferred()            # de novo depois de o contentor recalcular (rótulos com quebra de linha)

func _player_card(p: Dictionary, mine: bool, w: float) -> Control:
	var marks: Array = (m.get("state", {}) as Dictionary).get("marks", ["X", "O"])
	var seat := int(p.get("seat", 0))
	var mark: String = marks[seat] if seat < marks.size() else "?"
	var turn := active() and int((m.get("state", {}) as Dictionary).get("turn", -1)) == seat
	var col: Color = MARK_COL.get(mark, UIStyle.TEXT)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(w, 0)
	pc.add_theme_stylebox_override("panel", UIStyle.box(Color(col, 0.14) if turn else UIStyle.RAISED, Color(col, 0.7) if turn else UIStyle.STROKE, 2 if turn else 1, Vector4(10, 8, 10, 8), 14))
	var h := UI.hbox(8)
	pc.add_child(h)
	var online := bool(p.get("online", true))
	h.add_child(UI.avatar(p.get("appearance", {}), 34, col, 1 if online else 0))
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.title("Tu" if mine else str(p.get("name", "")), 13, UIStyle.TEXT, "semibold"))
	var sub := "a jogar" if turn else ""
	var pub := str(p.get("pub", ""))
	if bool(p.get("left", false)):
		sub = "saiu"
	elif not online:
		sub = "desligou · %ds" % int(ceil(float(_away.get(pub, 0)))) if _away.has(pub) else "offline"
	elif not active() and bool(p.get("rematch", false)):
		sub = "quer revanche"
	v.add_child(UI.title(sub, 11, UIStyle.BAD if (not online or bool(p.get("left", false))) else UIStyle.DIM, "medium"))
	h.add_child(v)
	var ml := UI.label(mark, 24, col, "bold")
	h.add_child(ml)
	return pc

func _board(inner: float) -> Control:
	var st: Dictionary = m.get("state", {})
	var board: Array = st.get("board", [])
	var res: Variant = m.get("result")
	var line: Array[int] = []                  # o JSON traz números como float: converter para comparar com o índice
	if res is Dictionary:
		for v in (res as Dictionary).get("line", []):
			line.append(int(v))
	var my_turn := active() and int(st.get("turn", -1)) == int(m.get("you", -2)) and _pending < 0 and bool(_other().get("online", true))
	var gap := 8.0
	var cell := floorf(minf(96.0, (inner - 2.0 * gap) / 3.0))
	# no telemóvel: o painel cabe entre a faixa do HUD e o fundo do ecrã (cabeçalho+jogadores+estado+botões ≈ 250 px)
	var h := _hud()
	var top: float = h.content_top() if h else 12.0
	var room: float = get_viewport_rect().size.y - top - 8.0 - 250.0
	cell = floorf(clampf(minf(cell, (room - 2.0 * gap) / 3.0), 56.0, 96.0))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in 9:
		var mark := str(board[i]) if i < board.size() else ""
		if i == _pending:
			mark = str((st.get("marks", ["X", "O"]) as Array)[int(m.get("you", 0))])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(cell, cell)
		b.text = mark
		b.add_theme_font_override("font", UIStyle.font("bold"))
		b.add_theme_font_size_override("font_size", int(cell * 0.5))
		var col: Color = MARK_COL.get(mark, UIStyle.TEXT)
		if i == _pending:
			col = Color(col, 0.45)
		for s in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(s, col)
		var win := i in line
		var last := st.get("last") != null and int(st.get("last")) == i and active()
		var bg := Color(MARK_COL.get(mark, UIStyle.GOLD), 0.22) if win else (Color(1, 1, 1, 0.09) if last else UIStyle.RAISED)
		var border := Color(MARK_COL.get(mark, UIStyle.GOLD), 0.8) if win else (UIStyle.STROKE_STRONG if last else UIStyle.STROKE)
		var normal := UIStyle.box(bg, border, 2 if win else 1, Vector4.ZERO, 14)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("disabled", normal)
		b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.1), Color(UIStyle.GOLD, 0.5), 1, Vector4.ZERO, 14))
		b.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.PRESSED, UIStyle.GOLD, 1, Vector4.ZERO, 14))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var free := mark == ""
		b.disabled = not (my_turn and free)
		if not b.disabled:
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var idx := i
			b.pressed.connect(func(): _play(idx))
		grid.add_child(b)
	var c := CenterContainer.new()
	c.custom_minimum_size = Vector2(inner, 0)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.add_child(grid)
	return c

func _play(cell: int) -> void:
	if _pending >= 0 or not active():
		return
	_pending = cell
	NetworkManager.send_game("game_move", {"mid": m.get("mid"), "cell": cell, "seq": int(m.get("seq", 0))})
	_render()

func _status_text() -> String:
	var other := _other()
	var oname := str(other.get("name", ""))
	if active():
		if not bool(other.get("online", true)):
			return "%s desligou-se. À espera que volte…" % oname
		if _pending >= 0:
			return "A enviar jogada…"
		var turn := int((m.get("state", {}) as Dictionary).get("turn", -1))
		return "A tua vez" if turn == int(m.get("you", -2)) else "Vez de %s" % oname
	var res: Dictionary = m.get("result", {}) if m.get("result") is Dictionary else {}
	var reason := str(res.get("reason", ""))
	if res.get("draw", false):
		return "Partida parada demasiado tempo. Empate." if reason == "expired" else "Empate!"
	var won := int(res.get("winner", -1)) == int(m.get("you", -2))
	if reason in ["forfeit", "disconnect"]:
		return ("Ganhaste! %s %s." % [oname, REASONS[reason]]) if won else ("Perdeste: %s." % ("desististe" if reason == "forfeit" else "saíste do jogo"))
	return "Ganhaste!" if won else "%s ganhou." % oname

func _status_col() -> Color:
	if active():
		var turn := int((m.get("state", {}) as Dictionary).get("turn", -1))
		return UIStyle.GOLD if turn == int(m.get("you", -2)) and bool(_other().get("online", true)) else UIStyle.DIM
	var res: Dictionary = m.get("result", {}) if m.get("result") is Dictionary else {}
	if res.get("draw", false):
		return UIStyle.TEXT
	return UIStyle.GOOD if int(res.get("winner", -1)) == int(m.get("you", -2)) else UIStyle.BAD

func _update_pill() -> void:
	if m.is_empty():
		pill.visible = false
		return
	var t := str(m.get("name", "Jogo"))
	if active():
		var turn := int((m.get("state", {}) as Dictionary).get("turn", -1))
		t += " · " + ("A tua vez" if turn == int(m.get("you", -2)) else "Vez de %s" % str(_other().get("name", "")))
	else:
		t += " · Terminou"
	pill.text = t
	pill.visible = minimized

func _place() -> void:
	var vs := get_viewport_rect().size
	var h := _hud()
	var top: float = h.content_top() if h else 12.0
	if pill.visible:
		pill.size = Vector2.ZERO
		pill.position = Vector2((vs.x - pill.get_combined_minimum_size().x) * 0.5, top)
	if panel.visible:
		panel.reset_size()
		var s := panel.get_combined_minimum_size()
		var compact := vs.x < 760.0
		var y := top if compact else maxf(top, (vs.y - s.y) * 0.5)
		if y + s.y > vs.y - 8.0:
			y = maxf(8.0, vs.y - s.y - 8.0)
		panel.position = Vector2((vs.x - s.x) * 0.5, y)

func _process(delta: float) -> void:
	if _away.is_empty() or not panel.visible:
		return
	for k in _away.keys():
		_away[k] = maxf(0.0, float(_away[k]) - delta)
	_away_t += delta
	if _away_t >= 1.0:
		_away_t = 0.0
		_render()

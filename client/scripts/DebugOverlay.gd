extends CanvasLayer
## Overlay de DEBUG (F3) — independente do HUD do jogador.
## * Escondido por omissão; F3 mostra/esconde (também em Telemóvel → Definições, para ecrãs táteis).
## * Puramente local: não envia nada ao servidor, não afeta outros jogadores nem o movimento.
## * Extensível: qualquer sistema regista uma secção com register_section("Nome", callable) que devolve
##   um Array de linhas (ou uma String). Cada secção pode ser recolhida clicando no título.

signal visibility_toggled(on: bool)

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const REFRESH := 0.2

var panel: PanelContainer
var box: VBoxContainer
var sections: Array = []          # [{title, provider, collapsed, header, body}]
var _t := 0.0

func _ready() -> void:
	layer = 50
	add_to_group("debug_overlay")
	visible = false
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.border_color = Color(0.3, 0.9, 0.4, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(330, 0)
	panel.add_child(sc)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	var title := Label.new()
	title.text = "DEBUG  (F3 para fechar)"
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	title.add_theme_font_size_override("font_size", 12)
	box.add_child(title)
	register_section("Desempenho", _perf)
	get_viewport().size_changed.connect(_place)
	_place()

func _place() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(340.0, vs.x - 16.0)
	panel.position = Vector2(vs.x - w - 8.0, 64.0)
	(panel.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(w - 16.0, minf(vs.y - 150.0, 560.0))

func register_section(title: String, provider: Callable, collapsed: bool = false) -> void:
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.focus_mode = Control.FOCUS_NONE
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	var body := Label.new()
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", Color(0.88, 0.95, 0.88))
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var s := {"title": title, "provider": provider, "collapsed": collapsed, "header": header, "body": body}
	header.pressed.connect(_toggle_section.bind(s))
	box.add_child(header)
	box.add_child(body)
	sections.append(s)

func _toggle_section(s: Dictionary) -> void:
	s["collapsed"] = not s["collapsed"]
	_refresh()

func toggle() -> void:
	visible = not visible
	visibility_toggled.emit(visible)
	if visible:
		_refresh()

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		toggle()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= REFRESH:
		_t = 0.0
		_refresh()

func _refresh() -> void:
	for s in sections:
		(s["header"] as Button).text = ("[+] " if s["collapsed"] else "[-] ") + str(s["title"])
		var body: Label = s["body"]
		body.visible = not s["collapsed"]
		if s["collapsed"]:
			continue
		var out: Variant = (s["provider"] as Callable).call()
		body.text = "\n".join(out) if out is Array else str(out)

func _perf() -> Array:
	return [
		"FPS: %d   frame: %.1f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0],
		"física: %.1f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
		"draw calls: %d   objetos: %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
		"nós: %d   memória: %.1f MB" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0],
	]

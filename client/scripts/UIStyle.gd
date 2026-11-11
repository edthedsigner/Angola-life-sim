extends RefCounted
## Tema de UI "pixel": painéis escuros translúcidos, bordas quadradas grossas, sem gradientes. Cores vêm do mundo (dourado dos candeeiros, tons de rua).

const FONT_PATH := "res://assets/fonts/ui_font.ttf"   # substitui por uma fonte pixel a gosto
const GOLD := Color(0.91, 0.66, 0.13)
const TEXT := Color(0.93, 0.9, 0.82)
const DIM := Color(0.62, 0.6, 0.56)
const BAD := Color(0.96, 0.4, 0.34)
const GOOD := Color(0.36, 0.86, 0.42)
const WARN := Color(0.95, 0.75, 0.25)

static func box(bg: Color, border: Color, bw: int = 2, margins: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(2)
	s.anti_aliasing = false
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	return s

static func _button_styles(th: Theme, type: String, normal: StyleBoxFlat, hover: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat, font: Color, font_hover: Color, font_dis: Color) -> void:
	th.set_stylebox("normal", type, normal)
	th.set_stylebox("hover", type, hover)
	th.set_stylebox("pressed", type, pressed)
	th.set_stylebox("disabled", type, disabled)
	th.set_stylebox("focus", type, box(Color(0, 0, 0, 0), GOLD, 2))
	th.set_color("font_color", type, font)
	th.set_color("font_hover_color", type, font_hover)
	th.set_color("font_pressed_color", type, font_hover)
	th.set_color("font_focus_color", type, font)
	th.set_color("font_disabled_color", type, font_dis)

static func make_theme() -> Theme:
	var th := Theme.new()
	if ResourceLoader.exists(FONT_PATH):
		var f: Resource = load(FONT_PATH)
		if f is FontFile:
			(f as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
			th.default_font = f
	th.default_font_size = 15
	var edge := Color(0.4, 0.37, 0.32)
	th.set_stylebox("panel", "PanelContainer", box(Color(0.055, 0.06, 0.075, 0.9), edge, 3, Vector4(0, 0, 0, 0)))
	th.set_type_variation("FieldBox", "PanelContainer")
	th.set_stylebox("panel", "FieldBox", box(Color(0.03, 0.03, 0.04, 0.95), Color(0.5, 0.48, 0.44), 2, Vector4(8, 2, 8, 2)))
	th.set_type_variation("FieldBoxFocus", "PanelContainer")
	th.set_stylebox("panel", "FieldBoxFocus", box(Color(0.03, 0.03, 0.04, 0.95), GOLD, 2, Vector4(8, 2, 8, 2)))
	# Botões
	_button_styles(th, "Button",
		box(Color(0.07, 0.07, 0.085, 0.95), Color(0.72, 0.7, 0.64), 2), box(Color(0.16, 0.15, 0.13, 0.98), GOLD, 2),
		box(Color(0.04, 0.04, 0.05, 1), GOLD, 2, Vector4(10, 8, 10, 4)), box(Color(0.06, 0.06, 0.07, 0.6), Color(0.28, 0.27, 0.26), 2),
		TEXT, Color(1, 0.93, 0.7), Color(0.45, 0.44, 0.42))
	th.set_type_variation("PrimaryButton", "Button")
	_button_styles(th, "PrimaryButton",
		box(Color(0.9, 0.64, 0.1), Color(0.35, 0.2, 0.04), 2), box(Color(0.98, 0.76, 0.22), Color(0.35, 0.2, 0.04), 2),
		box(Color(0.7, 0.48, 0.07), Color(0.25, 0.14, 0.03), 2, Vector4(10, 8, 10, 4)), box(Color(0.35, 0.28, 0.14, 0.8), Color(0.2, 0.15, 0.08), 2),
		Color(0.1, 0.06, 0.02), Color(0.05, 0.03, 0.0), Color(0.6, 0.52, 0.38))
	_button_styles(th, "OptionButton",
		box(Color(0.03, 0.03, 0.04, 0.95), Color(0.5, 0.48, 0.44), 2), box(Color(0.12, 0.11, 0.1, 0.98), GOLD, 2),
		box(Color(0.03, 0.03, 0.04, 1), GOLD, 2), box(Color(0.06, 0.06, 0.07, 0.6), Color(0.28, 0.27, 0.26), 2),
		TEXT, Color(1, 0.93, 0.7), Color(0.45, 0.44, 0.42))
	th.set_stylebox("panel", "PopupMenu", box(Color(0.04, 0.04, 0.05, 0.98), GOLD, 2, Vector4(4, 4, 4, 4)))
	th.set_stylebox("hover", "PopupMenu", box(Color(0.22, 0.17, 0.06), Color(0, 0, 0, 0), 0, Vector4(4, 2, 4, 2)))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color(1, 0.93, 0.7))
	# Campos de texto (dentro de FieldBox: transparentes)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 6
	empty.content_margin_right = 6
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	for st in ["normal", "focus", "read_only"]:
		th.set_stylebox(st, "LineEdit", empty)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.49, 0.47))
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_color("selection_color", "LineEdit", Color(0.9, 0.64, 0.1, 0.4))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	var line := StyleBoxLine.new()
	line.color = Color(0.4, 0.37, 0.32)
	line.thickness = 2
	th.set_stylebox("separator", "HSeparator", line)
	return th

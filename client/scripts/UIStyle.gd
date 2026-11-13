extends RefCounted
## Sistema de design da interface do jogo (tudo exceto o telemóvel): superfícies escuras translúcidas em carvão,
## bordas subtis, sombras contidas e um dourado quente como acento. O mundo continua visível por trás dos painéis.
## Tokens (cores, raios, tipos) + o Theme aplicado ao HUD e aos menus. Componentes prontos em ui/UIKit.gd.

# ---------------------------------------------------------------- cores
const GOLD := Color(0.95, 0.71, 0.18)          # acento (ações principais, valores, seleção)
const GOLD_DIM := Color(0.95, 0.71, 0.18, 0.18)
const TEXT := Color(0.95, 0.94, 0.91)
const DIM := Color(0.67, 0.66, 0.63)
const FAINT := Color(0.67, 0.66, 0.63, 0.55)
const BAD := Color(0.96, 0.42, 0.36)
const GOOD := Color(0.4, 0.84, 0.48)
const WARN := Color(0.97, 0.76, 0.3)
const INFO := Color(0.45, 0.72, 0.98)
const SURFACE := Color(0.06, 0.065, 0.075, 0.8)     # painel flutuante: deixa ver o mundo
const SURFACE_SOLID := Color(0.07, 0.075, 0.085, 0.93)   # diálogos/menus com texto denso
const RAISED := Color(1, 1, 1, 0.06)                # cartão dentro de um painel
const PRESSED := Color(1, 1, 1, 0.12)
const STROKE := Color(1, 1, 1, 0.09)
const STROKE_STRONG := Color(1, 1, 1, 0.16)
const NEED_COLORS := {"hunger": Color(0.96, 0.6, 0.22), "energy": Color(0.97, 0.84, 0.29), "hygiene": Color(0.38, 0.74, 0.97), "health": Color(0.95, 0.36, 0.38)}

# ---------------------------------------------------------------- medidas
const R_PANEL := 16
const R_CONTROL := 11
const R_PILL := 999
const TOUCH := 44                                # alvo de toque mínimo

# ---------------------------------------------------------------- tipografia (fonte sem serifa do motor, pesos por emboldening)
static var _fonts := {}
static func font(weight: String = "regular") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = {"regular": 0.0, "medium": 0.3, "semibold": 0.55, "bold": 0.85}.get(weight, 0.0)
	_fonts[weight] = fv
	return fv

## Caixa arredondada. Mantém a assinatura antiga (bg, borda, espessura, margens) para quem já a usa.
static func box(bg: Color, border: Color = STROKE, bw: int = 1, margins: Vector4 = Vector4(12, 8, 12, 8), radius: int = R_CONTROL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	return s

static func surface(alpha: float = SURFACE.a, radius: int = R_PANEL, margins: Vector4 = Vector4.ZERO, shadow: bool = true) -> StyleBoxFlat:
	var s := box(Color(SURFACE, alpha), STROKE, 1, margins, radius)
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.28)
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 3)
	return s

static func _button_styles(th: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox, font_col: Color, font_hover: Color, font_dis: Color) -> void:
	th.set_stylebox("normal", type, normal)
	th.set_stylebox("hover", type, hover)
	th.set_stylebox("pressed", type, pressed)
	th.set_stylebox("disabled", type, disabled)
	th.set_stylebox("focus", type, StyleBoxEmpty.new())
	th.set_color("font_color", type, font_col)
	th.set_color("font_hover_color", type, font_hover)
	th.set_color("font_pressed_color", type, font_hover)
	th.set_color("font_focus_color", type, font_col)
	th.set_color("font_disabled_color", type, font_dis)
	th.set_color("icon_normal_color", type, font_col)
	th.set_color("icon_hover_color", type, font_hover)
	th.set_color("icon_pressed_color", type, font_hover)
	th.set_color("icon_disabled_color", type, font_dis)
	th.set_constant("h_separation", type, 8)

static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font("medium")
	th.default_font_size = 15
	var pad := Vector4(14, 9, 14, 9)
	th.set_stylebox("panel", "PanelContainer", surface())
	th.set_stylebox("panel", "Panel", surface())
	# campos de texto
	th.set_type_variation("FieldBox", "PanelContainer")
	th.set_stylebox("panel", "FieldBox", box(Color(0, 0, 0, 0.35), STROKE_STRONG, 1, Vector4(12, 2, 12, 2)))
	th.set_type_variation("FieldBoxFocus", "PanelContainer")
	th.set_stylebox("panel", "FieldBoxFocus", box(Color(0, 0, 0, 0.45), Color(GOLD, 0.85), 1, Vector4(12, 2, 12, 2)))
	# botões: secundário (padrão), principal (dourado), fantasma (sem fundo), perigo
	_button_styles(th, "Button", box(RAISED, STROKE, 1, pad), box(Color(1, 1, 1, 0.1), Color(GOLD, 0.45), 1, pad),
		box(PRESSED, Color(GOLD, 0.6), 1, pad), box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.05), 1, pad), TEXT, Color(1, 0.96, 0.86), Color(TEXT, 0.35))
	th.set_type_variation("PrimaryButton", "Button")
	_button_styles(th, "PrimaryButton", box(GOLD, Color(0, 0, 0, 0), 0, pad), box(GOLD.lightened(0.12), Color(0, 0, 0, 0), 0, pad),
		box(GOLD.darkened(0.18), Color(0, 0, 0, 0), 0, pad), box(Color(GOLD, 0.25), Color(0, 0, 0, 0), 0, pad), Color(0.12, 0.08, 0.02), Color(0.08, 0.05, 0.0), Color(0.12, 0.08, 0.02, 0.5))
	th.set_type_variation("GhostButton", "Button")
	_button_styles(th, "GhostButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, pad), box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, pad),
		box(PRESSED, Color(0, 0, 0, 0), 0, pad), box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, pad), DIM, TEXT, Color(DIM, 0.4))
	th.set_type_variation("DangerButton", "Button")
	_button_styles(th, "DangerButton", box(Color(BAD, 0.14), Color(BAD, 0.35), 1, pad), box(Color(BAD, 0.22), Color(BAD, 0.6), 1, pad),
		box(Color(BAD, 0.3), Color(BAD, 0.7), 1, pad), box(Color(BAD, 0.05), Color(BAD, 0.1), 1, pad), Color(1, 0.62, 0.56), Color(1, 0.75, 0.7), Color(1, 0.62, 0.56, 0.4))
	_button_styles(th, "OptionButton", box(Color(0, 0, 0, 0.35), STROKE_STRONG, 1, pad), box(Color(0, 0, 0, 0.45), Color(GOLD, 0.5), 1, pad),
		box(Color(0, 0, 0, 0.5), GOLD, 1, pad), box(Color(0, 0, 0, 0.2), STROKE, 1, pad), TEXT, Color(1, 0.96, 0.86), Color(TEXT, 0.35))
	th.set_stylebox("panel", "PopupMenu", box(SURFACE_SOLID, STROKE_STRONG, 1, Vector4(6, 6, 6, 6), R_CONTROL))
	th.set_stylebox("hover", "PopupMenu", box(GOLD_DIM, Color(0, 0, 0, 0), 0, Vector4(8, 4, 8, 4), 8))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color(1, 0.96, 0.86))
	# campos (dentro de FieldBox: transparentes)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 9
	empty.content_margin_bottom = 9
	for st in ["normal", "focus", "read_only"]:
		th.set_stylebox(st, "LineEdit", empty)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", FAINT)
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	th.set_color("font_color", "Label", TEXT)
	th.set_color("default_color", "RichTextLabel", TEXT)
	# barras de progresso
	th.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, Vector4.ZERO, R_PILL))
	th.set_stylebox("fill", "ProgressBar", box(GOLD, Color(0, 0, 0, 0), 0, Vector4.ZERO, R_PILL))
	# separadores e scroll discretos
	var line := StyleBoxLine.new()
	line.color = STROKE
	line.thickness = 1
	th.set_stylebox("separator", "HSeparator", line)
	th.set_constant("separation", "HSeparator", 10)
	var grab := box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, Vector4.ZERO, R_PILL)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 3
	track.content_margin_right = 3
	for t in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, track)
		th.set_stylebox("grabber", t, grab)
		th.set_stylebox("grabber_highlight", t, box(Color(1, 1, 1, 0.35), Color(0, 0, 0, 0), 0, Vector4.ZERO, R_PILL))
		th.set_stylebox("grabber_pressed", t, box(Color(GOLD, 0.6), Color(0, 0, 0, 0), 0, Vector4.ZERO, R_PILL))
	# dicas (tooltips)
	th.set_stylebox("panel", "TooltipPanel", box(SURFACE_SOLID, STROKE_STRONG, 1, Vector4(10, 6, 10, 6), 8))
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font_size("font_size", "TooltipLabel", 13)
	return th

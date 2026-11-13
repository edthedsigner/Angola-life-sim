extends RefCounted
## Kit visual do telemóvel (linguagem inspirada no iOS, marca original "Kianda"): cores claro/escuro, tipografia,
## caixas arredondadas, ícones das apps e papel de parede gerados em SVG (sem ficheiros extra) e controlos nativos
## (interruptor, slider, controlo segmentado). Tudo é escalado por `k` (1 ponto lógico de um ecrã de 393 pt).

const Icons = preload("res://client/scripts/Icons.gd")

# ---------------------------------------------------------------- cores (semânticas, como no iOS)
static func palette(dark: bool) -> Dictionary:
	if dark:
		return {"dark": true, "bg": Color(0, 0, 0), "grouped": Color(0, 0, 0), "card": Color8(28, 28, 30), "card2": Color8(44, 44, 46),
			"label": Color(1, 1, 1), "label2": Color(0.92, 0.92, 0.96, 0.6), "label3": Color(0.92, 0.92, 0.96, 0.3),
			"sep": Color(0.33, 0.33, 0.35, 0.65), "fill": Color(0.47, 0.47, 0.5, 0.36), "tint": Color8(10, 132, 255),
			"green": Color8(48, 209, 88), "red": Color8(255, 69, 58), "orange": Color8(255, 159, 10), "yellow": Color8(255, 214, 10),
			"bar": Color(0.11, 0.11, 0.12, 0.94), "bubble_in": Color8(38, 38, 41), "chrome": Color(0.12, 0.12, 0.13, 0.82)}
	return {"dark": false, "bg": Color(1, 1, 1), "grouped": Color8(242, 242, 247), "card": Color(1, 1, 1), "card2": Color8(229, 229, 234),
		"label": Color(0, 0, 0), "label2": Color(0.24, 0.24, 0.26, 0.6), "label3": Color(0.24, 0.24, 0.26, 0.3),
		"sep": Color(0.24, 0.24, 0.26, 0.29), "fill": Color(0.47, 0.47, 0.5, 0.2), "tint": Color8(0, 122, 255),
		"green": Color8(52, 199, 89), "red": Color8(255, 59, 48), "orange": Color8(255, 149, 0), "yellow": Color8(255, 204, 0),
		"bar": Color(0.97, 0.97, 0.97, 0.94), "bubble_in": Color8(233, 233, 235), "chrome": Color(0.96, 0.96, 0.97, 0.82)}

# ---------------------------------------------------------------- tipografia (fonte sem serifa do motor, pesos por emboldening)
static var _fonts := {}
static func font(weight: String = "regular") -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = {"light": -0.35, "regular": 0.0, "medium": 0.3, "semibold": 0.55, "bold": 0.85, "heavy": 1.1}.get(weight, 0.0)
	_fonts[weight] = fv
	return fv

## Label com tamanho em pontos (escalado), peso e cor.
static func label(text: String, pt: float, k: float, col: Color, weight: String = "regular", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", fsize(pt, k))
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	# Sem reticências nem clip por omissão: no Godot 4 qualquer um dos dois põe a largura mínima do Label a 0 e ele
	# desaparece dentro de uma HBox. Quem quer reticências (títulos que expandem) usa ellipsis(label).
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func ellipsis(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func fsize(pt: float, k: float) -> int:
	return maxi(9, roundi(pt * k))

static func rounded(c: Color, r: float, border: Color = Color(0, 0, 0, 0), bw: int = 0, m: Vector4 = Vector4.ZERO) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(roundi(r))
	s.corner_detail = 12
	s.anti_aliasing = true
	s.anti_aliasing_size = 0.8
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.content_margin_left = m.x
	s.content_margin_top = m.y
	s.content_margin_right = m.z
	s.content_margin_bottom = m.w
	return s

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

## Botão de texto (estilo iOS: texto colorido, sem moldura; ou "filled" = cápsula colorida).
static func text_button(text: String, pt: float, k: float, col: Color, weight: String = "regular", filled: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(weight))
	b.add_theme_font_size_override("font_size", fsize(pt, k))
	var fc := Color.WHITE if filled.a > 0 else col
	for st in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(st, fc)
	b.add_theme_color_override("font_pressed_color", fc.darkened(0.25) if filled.a > 0 else Color(col, 0.35))
	b.add_theme_color_override("font_disabled_color", Color(fc, 0.35))
	var pad := Vector4(14 * k, 8 * k, 14 * k, 8 * k)
	var nb := rounded(filled, 12 * k, Color(), 0, pad) if filled.a > 0 else rounded(Color(0, 0, 0, 0), 0, Color(), 0, pad)
	b.add_theme_stylebox_override("normal", nb)
	b.add_theme_stylebox_override("hover", nb)
	b.add_theme_stylebox_override("focus", empty_box())
	b.add_theme_stylebox_override("disabled", rounded(Color(filled, filled.a * 0.4), 12 * k, Color(), 0, pad) if filled.a > 0 else nb)
	b.add_theme_stylebox_override("pressed", rounded(filled.darkened(0.15), 12 * k, Color(), 0, pad) if filled.a > 0 else nb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

## Campo de texto arredondado (iOS search/compose field).
static func field(placeholder: String, pal: Dictionary, k: float) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_override("font", font("regular"))
	e.add_theme_font_size_override("font_size", fsize(16, k))
	e.add_theme_color_override("font_color", pal["label"])
	e.add_theme_color_override("font_placeholder_color", pal["label3"] if pal["dark"] else Color(0.24, 0.24, 0.26, 0.35))
	e.add_theme_color_override("caret_color", pal["tint"])
	e.add_theme_color_override("selection_color", Color(pal["tint"], 0.3))
	var sb := rounded(pal["card"] if not pal["dark"] else pal["card2"], 18 * k, pal["sep"], 1, Vector4(12 * k, 6 * k, 12 * k, 6 * k))
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", rounded(Color(0, 0, 0, 0), 18 * k, pal["tint"], 1, Vector4(12 * k, 6 * k, 12 * k, 6 * k)))
	e.add_theme_stylebox_override("read_only", sb)
	e.custom_minimum_size = Vector2(0, 36 * k)
	e.virtual_keyboard_enabled = true
	return e

# ---------------------------------------------------------------- ícones das apps (squircle com gradiente + glifo branco)
const APP_LOOK := {
	"mensagens": ["5BE36A", "1DB940", "chat"],
	"amigos": ["A8A4A0", "6F6B66", "user"],
	"banco": ["1F3A5F", "0B1A2E", "bank"],
	"emprego": ["FFB340", "F27A00", "job"],
	"imoveis": ["5AC8FA", "1A7FE0", "home"],
	"negocios": ["C38BFF", "8A3FE0", "shop"],
	"governo": ["E5333A", "8E0F14", "gov"],
	"definicoes": ["B5B9C0", "6E737B", "gear"],
	"telefone": ["5BE36A", "1DB940", "phone"],
	"jogos": ["FF7A93", "D62A5B", "gamepad"],
}
static var _icon_cache := {}
static func app_icon(app: String, px: int) -> ImageTexture:
	var key := "%s|%d" % [app, px]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var look: Array = APP_LOOK.get(app, ["999999", "555555", "gear"])
	var glyph: String = Icons.P.get(look[2], "")
	var extra := ""
	if app == "governo":    # faixa dourada (original, evoca as cores nacionais sem usar o emblema)
		extra = '<rect x="0" y="40" width="60" height="5" fill="#F4C430" opacity="0.9"/>'
	if app == "banco":
		extra = '<rect x="9" y="38" width="42" height="3" rx="1.5" fill="#F4C430"/>'
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 60 60">'
		+ '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs>'
		+ '<rect x="0" y="0" width="60" height="60" rx="13.5" fill="url(#g)"/>%s'
		+ '<g transform="translate(12,10) scale(1.5)" fill="none" stroke="#FFFFFF" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>') % [px, px, look[0], look[1], extra, glyph]
	var img := Image.new()
	img.load_svg_from_string(svg)
	var t := ImageTexture.create_from_image(img)
	_icon_cache[key] = t
	return t

## Glifo simples (para listas, barras e botões), recolorível.
static func glyph(name: String, col: Color, px: int, stroke: float = 2.0) -> ImageTexture:
	var key := "g|%s|%s|%d|%.1f" % [name, col.to_html(true), px, stroke]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var paths := {
		"chev_l": '<path d="M15 4l-8 8 8 8"/>', "chev_r": '<path d="M9 4l8 8-8 8"/>', "check": '<path d="M4 12l5 5 11-11"/>',
		"info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>', "up": '<path d="M12 19V5M6 11l6-6 6 6"/>',
		"moon": '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/>', "sun": '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.4 1.4M17.6 17.6L19 19M5 19l1.4-1.4M17.6 6.4L19 5"/>',
		"torch": '<path d="M8 2h8v5l-2 3v12h-4V10L8 7z"/><path d="M12 13v2"/>', "speaker": '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16 9a4 4 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11"/>',
		"antenna": '<path d="M12 10v11M8 6a5.6 5.6 0 0 0 0 8M16 6a5.6 5.6 0 0 1 0 8M5 3a10 10 0 0 0 0 14M19 3a10 10 0 0 1 0 14"/>',
		"wifi": '<path d="M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0"/><circle cx="12" cy="19.5" r="0.8"/>',
		"lock": '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>', "plane": '<path d="M2 14l8-3V5a2 2 0 0 1 4 0v6l8 3v2l-8-2v4l3 2v1l-5-1-5 1v-1l3-2v-4l-8 2z"/>',
		"bug": '<rect x="7" y="7" width="10" height="13" rx="5"/><path d="M12 7V4M4 13h3M17 13h3M5 8l2 2M19 8l-2 2M5 19l2-2M19 19l-2-2"/>',
		"bell_off": '<path d="M6 16V11a6 6 0 0 1 9-5.2M18 11v5l2 2H8"/><path d="M3 3l18 18"/>', "phone_fill": Icons.P["phone"],
		"x": '<path d="M6 6l12 12M18 6L6 18"/>', "copy": '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
		"edit": '<path d="M4 20h4L19 9l-4-4L4 16z"/>', "trash": '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/>', "camera": '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
	}
	var body: String = paths.get(name, Icons.P.get(name, ""))
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24" fill="none" stroke="#%s" stroke-opacity="%.3f" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [px, px, col.to_html(false), col.a, stroke, body]
	var img := Image.new()
	img.load_svg_from_string(svg)
	var t := ImageTexture.create_from_image(img)
	_icon_cache[key] = t
	return t

## Papel de parede original: baía ao pôr do sol com recorte da marginal e palmeiras.
static func wallpaper(w: int, h: int, dark: bool) -> ImageTexture:
	var key := "wp|%d|%d|%s" % [w, h, dark]
	if _icon_cache.has(key):
		return _icon_cache[key]
	var top := "1B1340" if dark else "3B2A8F"
	var mid := "6A2C70" if dark else "D9547A"
	var low := "C0602A" if dark else "FFB15C"
	var sea := "0E2236" if dark else "1E4E7A"
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 100 216" preserveAspectRatio="none">'
		+ '<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="0.55" stop-color="#%s"/><stop offset="0.78" stop-color="#%s"/></linearGradient>'
		+ '<linearGradient id="m" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#05080F"/></linearGradient>'
		+ '<radialGradient id="sun" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFE7A8"/><stop offset="1" stop-color="#FFE7A8" stop-opacity="0"/></radialGradient></defs>'
		+ '<rect width="100" height="216" fill="url(#s)"/><circle cx="62" cy="150" r="30" fill="url(#sun)" opacity="0.8"/><circle cx="62" cy="152" r="9" fill="#FFE2A0"/>'
		+ '<path d="M0 158 h6 v-10 h4 v-6 h5 v16 h3 v-22 h6 v22 h4 v-14 h5 v14 h6 v-30 h3 v-4 h3 v4 h3 v30 h5 v-12 h6 v12 h4 v-18 h5 v18 h6 v-9 h4 v9 h8 v-15 h5 v15 h5 V170 H0z" fill="#1A1030" opacity="0.92"/>'
		+ '<rect y="164" width="100" height="52" fill="url(#m)"/><path d="M38 168 h48 M44 174 h36 M50 181 h22" stroke="#FFD88A" stroke-opacity="0.45" stroke-width="0.8"/>'
		+ '<path d="M8 216 C10 190 12 175 14 160" stroke="#0B0716" stroke-width="2.2" fill="none"/><path d="M14 160 c-8 -2 -14 3 -17 8 M14 160 c6 -6 14 -6 19 -2 M14 160 c-2 -8 -9 -12 -15 -11 M14 160 c4 -9 11 -12 17 -10 M14 160 c-6 3 -9 9 -9 14" stroke="#0B0716" stroke-width="2" fill="none"/>'
		+ '<path d="M90 216 C88 196 87 186 88 176" stroke="#0B0716" stroke-width="1.8" fill="none"/><path d="M88 176 c-7 -1 -12 3 -14 7 M88 176 c5 -5 11 -5 15 -1 M88 176 c-1 -7 -7 -10 -12 -9 M88 176 c3 -7 9 -9 13 -7" stroke="#0B0716" stroke-width="1.7" fill="none"/></svg>') % [w, h, top, mid, low, sea]
	var img := Image.new()
	img.load_svg_from_string(svg)
	var t := ImageTexture.create_from_image(img)
	_icon_cache[key] = t
	return t

## Iniciais num círculo colorido (avatar de contacto).
static func avatar(name: String, d: float, k: float) -> Control:
	var pc := PanelContainer.new()
	var hue := float(abs(name.hash()) % 360) / 360.0
	pc.add_theme_stylebox_override("panel", rounded(Color.from_hsv(hue, 0.35, 0.72), d / 2.0))
	pc.custom_minimum_size = Vector2(d, d)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts := name.strip_edges().split(" ", false)
	var ini := ""
	for p in parts.slice(0, 2):
		ini += p.substr(0, 1).to_upper()
	var l := label(ini if ini != "" else "?", d / k * 0.4, k, Color.WHITE, "semibold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc

# ---------------------------------------------------------------- controlos nativos
## Interruptor iOS (verde quando ligado), animado.
class SwitchX extends Control:
	signal toggled(on: bool)
	var on := false
	var on_col := Color8(52, 199, 89)
	var off_col := Color(0.47, 0.47, 0.5, 0.2)
	var _t := 0.0
	func _init(start: bool = false, k: float = 1.0) -> void:
		on = start
		_t = 1.0 if start else 0.0
		custom_minimum_size = Vector2(51, 31) * k
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func set_on(v: bool) -> void:
		on = v
		var tw := create_tween()
		tw.tween_property(self, "_t", 1.0 if v else 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_callback(queue_redraw).set_delay(0.0)
	func _process(_d: float) -> void:
		queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			set_on(not on)
			toggled.emit(on)
			accept_event()
	func _draw() -> void:
		var r := size.y / 2.0
		var c := off_col.lerp(on_col, _t)
		draw_style_box(_box(c, r), Rect2(Vector2.ZERO, size))
		var kd := size.y - 4.0
		var x := 2.0 + (size.x - kd - 4.0) * _t
		draw_circle(Vector2(x + kd / 2.0, size.y / 2.0 + 1.0), kd / 2.0, Color(0, 0, 0, 0.12))
		draw_circle(Vector2(x + kd / 2.0, size.y / 2.0), kd / 2.0, Color.WHITE)
	static func _box(c: Color, r: float) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = c
		s.set_corner_radius_all(roundi(r))
		s.corner_detail = 12
		s.anti_aliasing = true
		return s

## Slider: "thin" (Definições) ou "block" (Centro de Controlo: bloco alto com ícone, preenche de baixo para cima).
class SliderX extends Control:
	signal changed(v: float)
	var value := 0.5
	var block := false
	var fill_col := Color.WHITE
	var track_col := Color(1, 1, 1, 0.25)
	var icon: Texture2D
	func _init(v: float = 0.5, is_block: bool = false) -> void:
		value = v
		block = is_block
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
			var p: Vector2 = e.position
			value = clampf(1.0 - p.y / size.y, 0.0, 1.0) if block else clampf(p.x / size.x, 0.0, 1.0)
			changed.emit(value)
			queue_redraw()
			accept_event()
	func _draw() -> void:
		if block:
			var r := minf(size.x, size.y) * 0.28
			draw_style_box(SwitchX._box(track_col, r), Rect2(Vector2.ZERO, size))
			var h := size.y * value
			if h > 1.0:
				var fb := SwitchX._box(fill_col, r)
				fb.corner_radius_top_left = roundi(minf(r, h / 2.0))
				fb.corner_radius_top_right = roundi(minf(r, h / 2.0))
				draw_style_box(fb, Rect2(0, size.y - h, size.x, h))
			if icon:
				var s := size.x * 0.36
				draw_texture_rect(icon, Rect2((size.x - s) / 2.0, size.y - s * 1.5, s, s), false, Color(0.25, 0.25, 0.27) if value > 0.18 else Color.WHITE)
		else:
			var th := maxf(3.0, size.y * 0.14)
			var y := size.y / 2.0
			draw_style_box(SwitchX._box(track_col, th / 2.0), Rect2(0, y - th / 2.0, size.x, th))
			draw_style_box(SwitchX._box(fill_col, th / 2.0), Rect2(0, y - th / 2.0, size.x * value, th))
			var kr := size.y * 0.42
			var x := clampf(size.x * value, kr, size.x - kr)
			draw_circle(Vector2(x, y + 1.0), kr + 0.5, Color(0, 0, 0, 0.18))
			draw_circle(Vector2(x, y), kr, Color.WHITE)
			draw_arc(Vector2(x, y), kr, 0, TAU, 24, Color(0, 0, 0, 0.12), 1.0, true)

## Controlo segmentado iOS.
class SegmentedX extends Control:
	signal selected(i: int)
	var items: Array = []
	var index := 0
	var pal: Dictionary
	var k := 1.0
	func _init(opts: Array, sel: int, p: Dictionary, kk: float) -> void:
		items = opts
		index = sel
		pal = p
		k = kk
		custom_minimum_size = Vector2(0, 32 * kk)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed and items.size() > 0:
			var i := clampi(int(e.position.x / (size.x / items.size())), 0, items.size() - 1)
			if i != index:
				index = i
				queue_redraw()
				selected.emit(i)
			accept_event()
	func _draw() -> void:
		var r := 9.0 * k
		draw_style_box(SwitchX._box(Color(0.46, 0.46, 0.5, 0.24) if pal["dark"] else Color(0.46, 0.46, 0.5, 0.12), r), Rect2(Vector2.ZERO, size))
		var w := size.x / maxf(1.0, items.size())
		var sel := SwitchX._box(Color8(99, 99, 102) if pal["dark"] else Color.WHITE, r - 2.0)
		sel.shadow_color = Color(0, 0, 0, 0.12)
		sel.shadow_size = roundi(2 * k)
		draw_style_box(sel, Rect2(index * w + 2.0, 2.0, w - 4.0, size.y - 4.0))
		var f: Font = (load("res://client/scripts/phone/PhoneKit.gd") as GDScript).font("semibold")
		var fs := maxi(9, roundi(13 * k))
		for i in items.size():
			var t := str(items[i])
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(i * w + (w - tw) / 2.0, size.y / 2.0 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["label"])

## Barra de estado: hora à esquerda, rede/Wi-Fi/bateria à direita (desenhada; cor clara ou escura conforme o fundo).
class StatusBar extends Control:
	var time_text := "08:00"
	var light := true
	var bars := 4
	var wifi := false
	var tech := "4G"
	var battery := 0.8
	var charging := false
	var no_service := false
	var k := 1.0
	var island_w := 120.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var col := Color.WHITE if light else Color.BLACK
		var f: Font = (load("res://client/scripts/phone/PhoneKit.gd") as GDScript).font("semibold")
		var fs := maxi(9, roundi(16 * k))
		var side := (size.x - island_w) / 2.0
		var tw := f.get_string_size(time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cy := size.y * 0.56
		draw_string(f, Vector2((side - tw) / 2.0 + 6.0 * k, cy + fs * 0.36), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		# lado direito, da direita para a esquerda: bateria, wifi/4G, barras
		var bw := 25.0 * k
		var bh := 12.0 * k
		var right := size.x - side / 2.0 + 30.0 * k
		var bx := right - bw
		var by := cy - bh / 2.0
		var frame := SwitchX._box(Color(0, 0, 0, 0), 3.5 * k)
		frame.border_color = Color(col, 0.4)
		frame.set_border_width_all(maxi(1, roundi(1.1 * k)))
		draw_style_box(frame, Rect2(bx, by, bw, bh))
		draw_rect(Rect2(bx + bw + 1.0 * k, cy - 2.0 * k, 1.6 * k, 4.0 * k), Color(col, 0.4))
		var fillc := Color8(255, 59, 48) if battery < 0.2 and not charging else (Color8(52, 199, 89) if charging else col)
		draw_style_box(SwitchX._box(fillc, 2.2 * k), Rect2(bx + 2.0 * k, by + 2.0 * k, maxf(1.0, (bw - 4.0 * k) * battery), bh - 4.0 * k))
		if charging:
			var bolt := PackedVector2Array([Vector2(bx + bw * 0.55, by + 1.0), Vector2(bx + bw * 0.38, cy + 0.6 * k), Vector2(bx + bw * 0.5, cy + 0.6 * k), Vector2(bx + bw * 0.43, by + bh - 1.0), Vector2(bx + bw * 0.63, cy - 0.6 * k), Vector2(bx + bw * 0.51, cy - 0.6 * k)])
			draw_colored_polygon(bolt, Color.WHITE if not light else Color.BLACK)
		var x := bx - 6.0 * k
		if no_service:
			var t := "Sem serviço"
			var fs2 := maxi(8, roundi(13 * k))
			var w2 := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			draw_string(f, Vector2(x - w2, cy + fs2 * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, col)
			return
		if wifi:
			var c := Vector2(x - 8.0 * k, cy + 4.5 * k)
			for i in 3:
				var rr := (3.2 + i * 3.4) * k
				draw_arc(c, rr, -PI * 0.78, -PI * 0.22, 10, col, maxf(1.2, 1.7 * k), true)
			draw_circle(c, 1.4 * k, col)
			x -= 20.0 * k
		else:
			var fs3 := maxi(8, roundi(12 * k))
			var w3 := f.get_string_size(tech, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
			draw_string(f, Vector2(x - w3, cy + fs3 * 0.38), tech, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, col)
			x -= w3 + 5.0 * k
		for i in 4:
			var h := (4.0 + i * 2.6) * k
			var bx2 := x - (4 - i) * 4.6 * k
			draw_style_box(SwitchX._box(col if i < bars else Color(col, 0.3), 1.0 * k), Rect2(bx2, cy + 5.5 * k - h, 3.2 * k, h))

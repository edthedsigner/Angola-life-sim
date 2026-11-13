extends RefCounted
## Componentes reutilizáveis da interface do jogo (HUD, painéis, folhas, diálogos). Usa os tokens de UIStyle.gd.
## Não inclui o telemóvel, que tem o seu próprio sistema visual.

const UIStyle = preload("res://client/scripts/UIStyle.gd")
const Icons = preload("res://client/scripts/Icons.gd")
const VISUAL := preload("res://client/scenes/CharacterVisual.tscn")

# ---------------------------------------------------------------- texto
static func label(text: String, size: int = 14, col: Color = UIStyle.TEXT, weight: String = "medium", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIStyle.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Título que encolhe com "…" em vez de alargar o painel (largura mínima 0: usar dentro de contentores que expandem).
static func title(text: String, size: int = 15, col: Color = UIStyle.TEXT, weight: String = "semibold") -> Label:
	var l := label(text, size, col, weight)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func caption(text: String) -> Label:
	var l := label(text.to_upper(), 11, UIStyle.FAINT, "semibold")
	return l

static func icon(name: String, col: Color = UIStyle.TEXT, px: int = 18) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Icons.tex(name, col, px)
	t.custom_minimum_size = Vector2(px, px)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func margin(c: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ---------------------------------------------------------------- botões
## kind: "primary" (dourado) | "secondary" | "ghost" | "danger"
static func button(text: String, cb: Callable, kind: String = "secondary", icon_name: String = "", enabled: bool = true, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UIStyle.TOUCH)
	b.disabled = not enabled
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", UIStyle.font("semibold"))
	b.add_theme_font_size_override("font_size", 14)
	b.theme_type_variation = {"primary": "PrimaryButton", "ghost": "GhostButton", "danger": "DangerButton"}.get(kind, "")
	if icon_name != "":
		var ic_col := Color(0.12, 0.08, 0.02) if kind == "primary" else (Color(1, 0.62, 0.56) if kind == "danger" else UIStyle.TEXT)
		b.icon = Icons.tex(icon_name, ic_col, 18)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

## Botão redondo só com ícone (dock, fechar, zoom).
static func icon_button(icon_name: String, cb: Callable, tip: String = "", d: int = 48, col: Color = UIStyle.TEXT, flat: bool = false) -> Button:
	var b := Button.new()
	b.icon = Icons.tex(icon_name, col, int(d * 0.46))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(d, d)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var r := int(d / 2.0)
	var n := UIStyle.box(Color(0, 0, 0, 0) if flat else UIStyle.RAISED, Color(0, 0, 0, 0) if flat else UIStyle.STROKE, 0 if flat else 1, Vector4.ZERO, r)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", UIStyle.box(Color(1, 1, 1, 0.1), Color(UIStyle.GOLD, 0.35), 1, Vector4.ZERO, r))
	b.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.PRESSED, Color(UIStyle.GOLD, 0.6), 1, Vector4.ZERO, r))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", n)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func badge(on: Control, offset: Vector2 = Vector2(30, -4)) -> Label:
	var l := label("", 11, Color.WHITE, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_stylebox_override("normal", UIStyle.box(Color(0.9, 0.24, 0.24), Color(0.06, 0.06, 0.07), 2, Vector4(5, 0, 5, 0), 9))
	l.custom_minimum_size = Vector2(20, 18)
	l.position = offset
	l.visible = false
	on.add_child(l)
	return l

# ---------------------------------------------------------------- pequenos blocos
static func chip(text: String, col: Color = UIStyle.DIM, icon_name: String = "", bg_alpha: float = 0.14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(Color(col, bg_alpha), Color(col, 0.25), 1, Vector4(8, 2, 8, 2), UIStyle.R_PILL))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(4)
	if icon_name != "":
		h.add_child(icon(icon_name, col, 12))
	var l := label(text, 11, col, "semibold")
	l.name = "Text"
	h.add_child(l)
	p.add_child(h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

static func bar(value: float, col: Color, h: int = 6, w: int = 0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 100
	b.value = value
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_theme_stylebox_override("background", UIStyle.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, Vector4.ZERO, UIStyle.R_PILL))
	b.add_theme_stylebox_override("fill", UIStyle.box(col, Color(0, 0, 0, 0), 0, Vector4.ZERO, UIStyle.R_PILL))
	return b

## Cartão dentro de um painel (fundo um pouco mais claro). tap opcional torna-o clicável.
static func card(content: Control, pad: Vector4 = Vector4(12, 10, 12, 10), bg: Color = UIStyle.RAISED) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIStyle.box(bg, UIStyle.STROKE, 1, pad, 12))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(content)
	return p

## Avatar: o boneco do jogador (mesmas camadas do mundo) numa moldura arredondada.
static func avatar(appearance: Dictionary, d: int = 44, ring: Color = UIStyle.GOLD, online: int = -1) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(d, d)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", UIStyle.box(Color(0.2, 0.26, 0.22), Color(0, 0, 0, 0), 0, Vector4.ZERO, int(d * 0.3)))
	bg.size = Vector2(d, d)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(d, d)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var v: Node2D = VISUAL.instantiate()
	var sc := d / 26.0
	v.scale = Vector2(sc, sc)
	v.position = Vector2(d / 2.0, d * 1.62)
	clip.add_child(v)
	v.apply_appearance(appearance)
	var rim := Panel.new()
	rim.add_theme_stylebox_override("panel", UIStyle.box(Color(0, 0, 0, 0), Color(ring, 0.9), 2, Vector4.ZERO, int(d * 0.3)))
	rim.size = Vector2(d, d)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rim)
	if online >= 0:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.GOOD if online == 1 else Color(0.45, 0.45, 0.47), Color(0.06, 0.06, 0.07), 2, Vector4.ZERO, 7))
		dot.size = Vector2(13, 13)
		dot.position = Vector2(d - 11, d - 11)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(dot)
	holder.set_meta("visual", v)
	return holder

static func empty_state(icon_name: String, title_text: String, text: String) -> Control:
	var v := vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(0, 120)
	var ic := icon(icon_name, UIStyle.FAINT, 34)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := label(title_text, 15, UIStyle.TEXT, "semibold")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var x := label(text, 13, UIStyle.DIM, "regular", true)
	x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(x)
	return v

# ---------------------------------------------------------------- artigos (ícones e descrições a partir dos dados do mundo)
const ITEM_SVG := {
	"pao": '<ellipse cx="24" cy="27" rx="18" ry="11" fill="#C98A3E"/><ellipse cx="24" cy="24" rx="17" ry="10" fill="#E3A85A"/><path d="M14 20l4 6M22 18l4 7M30 18l4 7" stroke="#B5762F" stroke-width="2" stroke-linecap="round"/>',
	"agua": '<rect x="17" y="6" width="14" height="5" rx="1.5" fill="#2F7FD8"/><path d="M15 15c0-2 2-4 4-4h10c2 0 4 2 4 4v24c0 2-2 3-4 3H19c-2 0-4-1-4-3z" fill="#9FD4FF" opacity="0.9"/><rect x="15" y="22" width="18" height="8" fill="#2F7FD8"/>',
	"banana": '<path d="M9 14c3 15 16 24 30 20-2 4-10 7-18 4C12 34 7 24 9 14z" fill="#F4CF3A"/><path d="M12 16c4 11 13 17 25 17" stroke="#C9A421" stroke-width="2" fill="none"/><path d="M9 14l-1-4 3 1z" fill="#6B4F1D"/>',
	"ingredientes": '<path d="M8 20h32l-4 20H12z" fill="#B5793F"/><path d="M8 20h32" stroke="#8A5A2C" stroke-width="3"/><circle cx="18" cy="16" r="6" fill="#E04B3A"/><path d="M27 8c5 2 7 7 5 12-5-2-7-7-5-12z" fill="#4FB061"/><circle cx="31" cy="17" r="4" fill="#F29B38"/>',
	"refeicao": '<path d="M8 18h32l-3 20H11z" fill="#F2EEE6"/><path d="M8 18l5-8h22l5 8" fill="#DDD6C8"/><rect x="20" y="24" width="8" height="8" rx="2" fill="#E04B3A"/>',
	"sabonete": '<rect x="9" y="18" width="30" height="16" rx="7" fill="#F6A7C1"/><rect x="11" y="16" width="26" height="14" rx="6" fill="#FFC9DA"/><circle cx="36" cy="12" r="3" fill="#BFE6FF"/><circle cx="31" cy="8" r="2" fill="#BFE6FF"/>',
}
static var _item_cache := {}
static func item_icon(id: String, px: int = 40) -> ImageTexture:
	var key := "%s|%d" % [id, px]
	if _item_cache.has(key):
		return _item_cache[key]
	var body: String = ITEM_SVG.get(id, '<rect x="10" y="12" width="28" height="26" rx="5" fill="#8C8A84"/><path d="M10 20h28" stroke="#6C6A66" stroke-width="2"/>')
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 48 48">%s</svg>' % [px, px, body]
	var img := Image.new()
	img.load_svg_from_string(svg)
	var t := ImageTexture.create_from_image(img)
	_item_cache[key] = t
	return t

const NEED_NAMES := {"hunger": "Fome", "energy": "Energia", "hygiene": "Higiene", "health": "Saúde"}
## Descrição de um artigo a partir dos dados (efeitos ao consumir, para que serve, valor de venda). Nada inventado.
static func item_description(id: String, items: Dictionary, activities: Dictionary) -> String:
	var it: Dictionary = items.get(id, {})
	var parts: Array = []
	if it.has("eat"):
		var eff: Array = []
		for k in it["eat"]:
			eff.append("+%d %s" % [int(it["eat"][k]), NEED_NAMES.get(k, k)])
		parts.append("Consumir: " + ", ".join(eff) + ".")
	for a in activities:
		if str(activities[a].get("consumes", "")) == id:
			parts.append("Usado para «%s» em casa." % activities[a]["label"])
	if id == "sabonete":
		parts.append("Artigo de higiene.")
	if int(it.get("sell", 0)) > 0:
		parts.append("Vende-se por %s." % _kz(int(it["sell"])))
	else:
		parts.append("Não se pode vender.")
	return " ".join(parts)

static func _kz(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		if (s.length() - i) % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if v < 0 else "") + out + " Kz"

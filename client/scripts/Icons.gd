extends RefCounted
## Ícones vetoriais (SVG gerado em runtime, como no original v0.6) — sem ficheiros extra; recoloríveis.
const P := {
	"clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
	"wallet": '<path d="M3 7h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M3 7l12-3v3"/><circle cx="16.5" cy="13.5" r="1"/>',
	"food": '<path d="M7 3v8M4 3v5a3 3 0 0 0 6 0V3M7 11v10"/><path d="M17 3c-2 2-3 5-3 8h3v10"/>',
	"zap": '<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
	"drop": '<path d="M12 3s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z"/>',
	"heart": '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z"/>',
	"plus": '<path d="M12 5v14M5 12h14"/>',
	"minus": '<path d="M5 12h14"/>',
	"chat": '<path d="M4 5h16v11H9l-5 4z"/>',
	"phone": '<rect x="6.5" y="2" width="11" height="20" rx="2.5"/><path d="M10.5 5.2h3"/>',
	"bag": '<path d="M5 8h14l-1 13H6z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
	"send": '<path d="M5 12h14M13 6l6 6-6 6"/>',
	"back": '<path d="M15 5l-7 7 7 7"/>',
	"enter": '<path d="M10 4H5v16h5"/><path d="M14 8l4 4-4 4M18 12H9"/>',
	"bank": '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M3 10h18"/>',
	"job": '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18"/>',
	"home": '<path d="M3 11l9-8 9 8"/><path d="M5 10v10h14V10"/>',
	"shop": '<path d="M4 9l1-5h14l1 5"/><path d="M4 9h16v11H4z"/>',
	"gov": '<path d="M3 21h18M5 21V10M10 21V10M14 21V10M19 21V10M2 10l10-7 10 7z"/>',
	"gear": '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>',
}
static var _cache := {}

static func tex(name: String, col: Color, px: int = 20) -> ImageTexture:
	var key := "%s|%s|%d" % [name, col.to_html(false), px]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24" fill="none" stroke="#%s" stroke-width="2" stroke-linecap="square" stroke-linejoin="miter">%s</svg>' % [px, px, col.to_html(false), P.get(name, "")]
	var img := Image.new()
	img.load_svg_from_string(svg)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t

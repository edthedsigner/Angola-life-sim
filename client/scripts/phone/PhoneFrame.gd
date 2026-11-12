extends Control
## Corpo físico do telemóvel, desenhado por cima do ecrã (não recebe toques): aro de alumínio com arestas planas,
## botões laterais (ação, volume +/−, lateral), vidro preto, cantos arredondados do ecrã, altifalante e reflexo.
## O ecrã fica por baixo (retangular, clip_contents) e os cantos são "mascarados" aqui com a cor do vidro.

var screen_rect := Rect2()     # retângulo do ecrã, em coordenadas deste nó
var screen_r := 40.0           # raio dos cantos do ecrã
var body_r := 50.0             # raio dos cantos do corpo
var frame_col := Color8(164, 168, 176)       # alumínio natural
var pressed_button := ""                     # "vol_up" | "vol_down" | "side" (feedback visual)
var front := false                           # false: corpo e vidro (por baixo do ecrã); true: cantos, reflexo, altifalante (por cima)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _sb(c: Color, r: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(roundi(r))
	s.corner_detail = 16
	s.anti_aliasing = true
	return s

func _button(r: Rect2, name: String) -> void:
	var off := Vector2(1.5 if r.position.x < 0 else -1.5, 0) if pressed_button == name else Vector2.ZERO
	var rr := Rect2(r.position + off, r.size)
	draw_style_box(_sb(frame_col.darkened(0.35), minf(rr.size.x, rr.size.y) / 2.0), rr)
	draw_style_box(_sb(frame_col.lightened(0.15), minf(rr.size.x, rr.size.y) / 2.0), rr.grow_individual(-0.6, -1.2, -0.6, -1.2))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var k := w / 433.0
	if front:
		_draw_front(w, k)
		return
	# botões laterais (por baixo do aro, salientes)
	var bt := 4.0 * k
	_button(Rect2(-bt, h * 0.165, bt + 2.0, h * 0.04), "action")
	_button(Rect2(-bt, h * 0.235, bt + 2.0, h * 0.075), "vol_up")
	_button(Rect2(-bt, h * 0.325, bt + 2.0, h * 0.075), "vol_down")
	_button(Rect2(w - 2.0, h * 0.26, bt + 2.0, h * 0.11), "side")
	# sombra projetada
	var sh := _sb(Color(0, 0, 0, 0.0), body_r)
	sh.shadow_color = Color(0, 0, 0, 0.45)
	sh.shadow_size = roundi(26 * k)
	sh.shadow_offset = Vector2(0, 10 * k)
	draw_style_box(sh, Rect2(Vector2.ZERO, size))
	# aro de alumínio: camadas com tons diferentes simulam a aresta plana polida
	draw_style_box(_sb(frame_col.darkened(0.45), body_r), Rect2(Vector2.ZERO, size))
	draw_style_box(_sb(frame_col.lightened(0.12), body_r - 1.0), Rect2(Vector2.ZERO, size).grow(-1.2 * k))
	draw_style_box(_sb(frame_col, body_r - 2.0), Rect2(Vector2.ZERO, size).grow(-2.6 * k))
	draw_style_box(_sb(frame_col.darkened(0.25), body_r - 3.5), Rect2(Vector2.ZERO, size).grow(-4.4 * k))
	# brilho na aresta superior esquerda
	draw_arc(Vector2(body_r, body_r), body_r - 2.0 * k, PI, PI * 1.5, 20, Color(1, 1, 1, 0.55), 1.2 * k, true)
	# vidro frontal (moldura preta)
	var glass := Rect2(Vector2.ZERO, size).grow(-5.2 * k)
	draw_style_box(_sb(Color8(6, 6, 8), body_r - 5.0), glass)

func _draw_front(w: float, k: float) -> void:
	# reflexo diagonal subtil no vidro (por cima do ecrã)
	var g := PackedVector2Array([screen_rect.position, screen_rect.position + Vector2(screen_rect.size.x * 0.62, 0), screen_rect.position + Vector2(0, screen_rect.size.y * 0.38)])
	draw_colored_polygon(g, Color(1, 1, 1, 0.035))
	var g2 := PackedVector2Array([screen_rect.position + Vector2(screen_rect.size.x * 0.62, 0), screen_rect.position + Vector2(screen_rect.size.x * 0.72, 0), screen_rect.position + Vector2(0, screen_rect.size.y * 0.44), screen_rect.position + Vector2(0, screen_rect.size.y * 0.38)])
	draw_colored_polygon(g2, Color(1, 1, 1, 0.02))
	# máscaras dos cantos do ecrã (o ecrã por baixo é retangular)
	var r := screen_r
	var sr2 := screen_rect.grow(1.0)            # 1 px a mais cobre o anti-aliasing da borda do ecrã
	var corners := [[sr2.position, Vector2(1, 1)], [Vector2(sr2.end.x, sr2.position.y), Vector2(-1, 1)],
		[sr2.end, Vector2(-1, -1)], [Vector2(sr2.position.x, sr2.end.y), Vector2(1, -1)]]
	for c in corners:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		var centre := p + d * r
		var pts := PackedVector2Array([p])            # canto + arco de (p.x, centro.y) até (centro.x, p.y)
		for i in 17:
			var t := float(i) / 16.0 * PI / 2.0
			pts.append(centre + Vector2(-d.x * r * cos(t), -d.y * r * sin(t)))
		draw_colored_polygon(pts, Color8(6, 6, 8))
	# moldura fina à volta do ecrã (realça a borda do vidro)
	var ring := _sb(Color(0, 0, 0, 0), r)
	ring.border_color = Color(1, 1, 1, 0.05)
	ring.set_border_width_all(1)
	draw_style_box(ring, screen_rect.grow(0.5))
	# altifalante (fenda na borda superior)
	var sw := w * 0.16
	draw_style_box(_sb(Color8(30, 30, 34), 1.5 * k), Rect2((w - sw) / 2.0, 7.2 * k, sw, 2.6 * k))

extends Node2D
## Escadas (degraus em prisma) e abertura da escada no piso de cima — desenho portado do original v0.6
## (draw_stairs / draw_hole / draw_prism), agora como nó próprio para entrar no y-sort com os jogadores.

var zone := ""
var st: Dictionary = {}
var mode := "stairs"
var wall_h := 48.0
const STEP := Color(0.69, 0.55, 0.39)
const LINE := Color(0.3, 0.22, 0.15, 0.8)

func setup(z: String, stair: Dictionary, m: String, h: float) -> void:
	zone = z
	st = stair
	mode = m
	wall_h = h
	name = "Stairs_%s_%d" % [m, int(stair["lo"])]
	# ponto de ordenação: aresta da frente da rampa (entre a base e o 1.º degrau)
	position = WorldData.vertex_px(zone, float(st["x"]) + 0.5, float(st["y"]))

func _v(x: float, y: float) -> Vector2:
	return WorldData.vertex_px(zone, x, y) - position

func _prism(x: float, y: float, w: float, h: float, z1: float, c: Color) -> void:
	var u := Vector2(0, -z1)
	var T := _v(x, y)
	var R := _v(x + w, y)
	var B := _v(x + w, y + h)
	var L := _v(x, y + h)
	draw_colored_polygon(PackedVector2Array([L, B, B + u, L + u]), c.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([B, R, R + u, B + u]), c.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([T + u, R + u, B + u, L + u]), c.lightened(0.12))
	draw_polyline(PackedVector2Array([L + u, T + u, R + u, B + u, L + u]), LINE, 1.0)

func _draw() -> void:
	var bx := float(st["x"])
	var by := float(st["y"])
	var ln := int(st["len"])
	var n := ln * 3
	if mode == "stairs":
		for i in range(n - 1, -1, -1):           # de trás para a frente
			var f1 := float(i + 1) / 3.0
			_prism(bx, by - f1, 1.0, 1.0 / 3.0, wall_h * float(i + 1) / float(n), STEP)
		# corrimão
		var top := _v(bx + 1.0, by - ln) + Vector2(0, -wall_h - 10)
		draw_line(_v(bx + 1.0, by) + Vector2(0, -14), top, Color(0.25, 0.18, 0.12), 2.0)
	else:
		var pts := PackedVector2Array([_v(bx, by - ln), _v(bx + 1, by - ln), _v(bx + 1, by), _v(bx, by)])
		draw_colored_polygon(pts, Color(0.22, 0.2, 0.19))
		for k in range(1, n):
			var yy := by - float(k) / 3.0
			draw_line(_v(bx, yy), _v(bx + 1, yy), Color(0.42, 0.36, 0.3), 1.0)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.1, 0.09, 0.08), 1.5)
		# guarda à volta da abertura
		draw_line(_v(bx + 1, by - ln) + Vector2(0, -12), _v(bx + 1, by) + Vector2(0, -12), Color(0.35, 0.26, 0.18), 2.0)

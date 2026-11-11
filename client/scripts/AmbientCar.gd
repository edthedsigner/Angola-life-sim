extends Node2D
## Carro decorativo (só no cenário do menu): percorre a rota e reaparece no início.
var points: Array = []
var speed: float = 70.0
var color: String = "red"
var _i: int = 1
@onready var body: Sprite2D = $Body

func setup(pts: Array, col: String, start_t: float) -> void:
	points = pts
	color = col
	global_position = (pts[0] as Vector2).lerp(pts[1], start_t)
	_update_texture()

func _update_texture() -> void:
	var d: Vector2 = (points[_i] as Vector2) - (points[(_i - 1) % points.size()] as Vector2)
	body.texture = load("res://assets/art/props/car_%s_%s.png" % [color, "dr" if d.x > 0 else "ul"]) as Texture2D

func _process(delta: float) -> void:
	if points.size() < 2:
		return
	var target: Vector2 = points[_i]
	var to := target - global_position
	var step := speed * delta
	if to.length() <= step:
		_i = (_i + 1) % points.size()
		if _i == 0:               # fim da rota: volta ao início
			_i = 1
			global_position = points[0]
		else:
			global_position = target
		_update_texture()
	else:
		global_position += to.normalized() * step

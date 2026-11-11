extends Node2D
## Peão decorativo (só no cenário do menu). Anda de ponto em ponto ao longo de uma rota editável do World.tscn.
var points: Array = []
var speed: float = 28.0
var _i: int = 1
var _dir: int = 1
@onready var visual: Node2D = $Visual

func setup(pts: Array, start_t: float, appearance: Dictionary, spd: float) -> void:
	points = pts
	speed = spd
	global_position = (pts[0] as Vector2).lerp(pts[1], start_t)
	visual.apply_appearance(appearance)

func _process(delta: float) -> void:
	if points.size() < 2:
		return
	var target: Vector2 = points[_i]
	var to := target - global_position
	var step := speed * delta
	if to.length() <= step:
		global_position = target
		_i += _dir
		if _i >= points.size() or _i < 0:
			_dir = -_dir
			_i += 2 * _dir
	else:
		global_position += to.normalized() * step
	visual.set_moving(true, to.x)

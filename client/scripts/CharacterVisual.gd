extends Node2D
## Aparência em camadas (pernas, corpo/pele, camisa, cabelo). Usado pelo Player e pela pré-visualização.

@onready var legs: Sprite2D = $Legs
@onready var body: Sprite2D = $Body
@onready var shirt: Sprite2D = $Shirt
@onready var hair: Sprite2D = $Hair

var _app: Dictionary = {}
var moving: bool = false
var pose: String = "stand"          # "stand" | "sit" (quadro 3) | "lie" (rodado ao longo da cama)
var _t: float = 0.0
const FRAMES := [1, 0, 2, 0]

func _ready() -> void:
	_apply()

func apply_appearance(app: Dictionary) -> void:
	_app = app
	if is_node_ready():
		_apply()

func _apply() -> void:
	body.modulate = Art.skin_color(int(_app.get("skin_tone", 0)))
	hair.texture = Art.hair_texture(int(_app.get("hair_style", 0)))
	hair.modulate = Art.hair_color(int(_app.get("hair_color", 0)))
	shirt.modulate = Art.shirt_color(int(_app.get("clothes", 0)))

func set_pose(p: String) -> void:
	pose = p
	hair.offset.y = -36.0 if p == "sit" else -40.0      # cabeça desce 4 px quando sentado
	_set_frame(3 if p == "sit" else 0)

func set_moving(m: bool, face_x: float = 0.0) -> void:
	if pose != "stand":
		return
	moving = m
	if face_x > 0.1:
		scale.x = 1.0
	elif face_x < -0.1:
		scale.x = -1.0
	if not m:
		_set_frame(0)

func _set_frame(f: int) -> void:
	if legs:
		legs.frame = f
		body.frame = f
		shirt.frame = f

func _process(delta: float) -> void:
	if moving:
		_t += delta * 8.0
		_set_frame(FRAMES[int(_t) % 4])

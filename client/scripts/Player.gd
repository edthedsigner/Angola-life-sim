extends CharacterBody2D
## Jogador local (teclado OU caminho de navegação + câmara) ou remoto (interpolado a partir do servidor).
## Rato, toque e interações usam todos o mesmo caminho: World calcula-o com WorldData.find_path e chama set_path().
##
## Física (Player.tscn): modo FLOATING (vista de cima, sem "chão") e camada própria (2) com máscara só do mundo (1).
## Os jogadores não colidem entre si: o servidor não os trata como obstáculos, e no modo GROUNDED um jogador remoto
## encostado por baixo passava a ser o "chão" do local, que herdava o movimento dele e o seguia (bug de seguir).

signal arrived                 # chegou ao fim do caminho
signal path_failed             # ficou preso (porta fechada entretanto, canto de parede, etc.)

const ISO_Y := 0.5            # achatamento vertical isométrico
const SEND_INTERVAL := 0.05   # 20 Hz
@export var speed: float = 110.0
var is_local: bool = false
var input_enabled: bool = true
var peer_id: String = ""
var pub: String = ""             # identificador público (social); o id interno nunca chega a outros clientes
var level: int = 1
var character_name: String = "Jogador"
var appearance: Dictionary = {}
var zone: String = "w"
var activity: String = ""
var path: Array = []
var last_input: String = "-"   # "teclado" | "caminho" (debug)
var _target: Vector2 = Vector2.ZERO
var _send_t: float = 0.0
var _last_sent: Vector2 = Vector2(INF, INF)
var _stuck_t: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _say_t: float = 0.0
var _bubble: PanelContainer
var _bubble_label: Label
var _status: Label

@onready var name_label: Label = $NameLabel
@onready var visual: Node2D = $Visual
@onready var camera: Camera2D = $Camera2D

func _ready() -> void:
	if not is_local:
		collision_mask = 0             # o remoto só é desenhado/interpolado; nunca empurra nem é empurrado
	name_label.text = character_name
	visual.apply_appearance(appearance)
	_target = global_position
	_build_bubble()
	if is_local:
		name_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5))
		camera.enabled = true
		camera.make_current()
		camera.reset_smoothing()
	else:
		camera.queue_free()

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.9, 0.96)
	sb.border_color = Color(0.15, 0.12, 0.1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(3)
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble_label = Label.new()
	_bubble_label.add_theme_font_size_override("font_size", 9)
	_bubble_label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06))
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble.add_child(_bubble_label)
	_bubble.visible = false
	_bubble.z_index = 10
	add_child(_bubble)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 8)
	_status.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_status.add_theme_constant_override("outline_size", 3)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.position = Vector2(-60, -72)
	_status.size = Vector2(120, 10)
	_status.visible = false
	add_child(_status)

static func _wrap(text: String, width: int = 26) -> String:
	var lines: Array = []
	var cur := ""
	for w in text.split(" ", false):
		if cur != "" and cur.length() + 1 + w.length() > width:
			lines.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	if cur != "":
		lines.append(cur)
	return "\n".join(lines)

func say(text: String) -> void:
	_bubble_label.text = _wrap(text)
	_bubble.reset_size()
	_bubble.visible = true
	_say_t = 5.0
	var sz := _bubble.get_combined_minimum_size()
	_bubble.size = sz
	_bubble.position = Vector2(-sz.x * 0.5, -64.0 - sz.y - (12.0 if _status.visible else 0.0))

func set_activity(label: String) -> void:
	activity = label
	_status.text = label
	_status.visible = label != ""

## Pose visual durante uma atividade (sentar no sofá/banco, deitar na cama). Só visual: a posição no servidor não muda.
func set_pose(p: String, seat_px: Vector2 = Vector2.ZERO, rot: float = 0.0, lift: float = 0.0, flip: float = 1.0) -> void:
	visual.set_pose(p)
	visual.scale.x = flip
	if not has_meta("label_pos"):
		set_meta("label_pos", name_label.position)
		set_meta("status_pos", _status.position)
	if p == "stand":
		visual.position = Vector2.ZERO
		visual.rotation = 0.0
		visual.z_index = 0
		name_label.position = get_meta("label_pos")
		_status.position = get_meta("status_pos")
		return
	visual.rotation = rot
	# o pivô do visual são os pés; para deitar, centra o corpo (17 px acima dos pés) no ponto pedido
	var centre_fix := Vector2(0, -17).rotated(rot) if p == "lie" else Vector2.ZERO
	visual.position = seat_px - global_position + Vector2(0, -lift) - centre_fix
	visual.z_index = 2
	var shift := seat_px - global_position + Vector2(0, -lift + (10.0 if p == "lie" else 4.0))   # nome/estado seguem a pose
	name_label.position = (get_meta("label_pos") as Vector2) + shift
	_status.position = (get_meta("status_pos") as Vector2) + shift

func set_character_data(data: Dictionary) -> void:
	peer_id = str(data.get("peer_id", ""))
	pub = str(data.get("pub", ""))
	level = int(data.get("level", 1))
	character_name = str(data.get("name", "Jogador"))
	appearance = data.get("appearance", {})
	zone = str(data.get("zone", "w"))
	var pos: Dictionary = data.get("position", {})
	position = Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
	_target = position

func _read_input() -> Vector2:
	var v := Vector2.ZERO
	if not input_enabled:
		return v
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1
	return v.normalized()

func set_path(p: Array) -> void:
	path = p.duplicate()
	_stuck_t = 0.0
	_last_pos = global_position

func stop_path() -> void:
	path.clear()

## Teleporte autoritativo (servidor): entrar/sair/escadas/correções.
func teleport(pos: Vector2, new_zone: String) -> void:
	zone = new_zone
	path.clear()
	global_position = pos
	_target = pos
	_last_sent = pos
	velocity = Vector2.ZERO
	if is_local and is_instance_valid(camera):
		camera.reset_smoothing()

func _process(delta: float) -> void:
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			_bubble.visible = false

func _physics_process(delta: float) -> void:
	if is_local:
		var dir := _read_input()
		if dir != Vector2.ZERO:
			if not path.is_empty():
				path.clear()                 # teclado tem sempre prioridade sobre o clique
			last_input = "teclado"
			velocity = Vector2(dir.x, dir.y * ISO_Y) * speed
		elif not path.is_empty() and input_enabled:
			last_input = "caminho"
			var d: Vector2 = path[0] - global_position
			if d.length() < 3.0:
				path.pop_front()
				velocity = Vector2.ZERO
				if path.is_empty():
					arrived.emit()
			else:
				var n := Vector2(d.x, d.y / ISO_Y).normalized()     # mesma velocidade "no chão" que o teclado
				velocity = Vector2(n.x, n.y * ISO_Y) * speed
				if velocity.length() * delta > d.length():
					velocity = d / delta
			_stuck_t += delta
			if _stuck_t > 0.35:
				if global_position.distance_to(_last_pos) < 2.0:
					if path.size() > 1:
						path.pop_front()
					else:
						path.clear()
					if path.is_empty():
						path_failed.emit()
				_stuck_t = 0.0
				_last_pos = global_position
		else:
			velocity = Vector2.ZERO
		move_and_slide()
		visual.set_moving(velocity.length() > 5.0, velocity.x)
		_send_t += delta
		if _send_t >= SEND_INTERVAL and global_position.distance_to(_last_sent) > 0.1:
			_send_t = 0.0
			_last_sent = global_position
			NetworkManager.send_position(global_position)
	else:
		var d := _target - global_position
		global_position = global_position.lerp(_target, clampf(delta * 14.0, 0.0, 1.0))
		visual.set_moving(d.length() > 1.5, d.x)

func apply_remote_position(pos: Vector2) -> void:
	if not is_local:
		_target = pos

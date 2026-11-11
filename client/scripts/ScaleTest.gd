extends Node2D
## Laboratório de escala (docs/SCALE.md) — corre com o argumento --scale-test (sem servidor).
## Mostra o MESMO piso de teste duas vezes: à esquerda como era no M2 (mobília do pack desenhada ocupando a célula,
## personagem de 38 px, porta de 36 px), à direita com a escala atual (1 célula = 2 m, 19,6 px/m, personagem 34 px).
## Teclas: 1 vista geral · 2 "antes" ampliado · 3 "depois" ampliado · 4 portas exteriores.

const InteriorBuilder = preload("res://client/scripts/InteriorBuilder.gd")
const VISUAL := preload("res://client/scenes/CharacterVisual.tscn")
const WALL_L := preload("res://client/scenes/components/WallPieceL.tscn")
const ART := "res://assets/art/"
const OLD_ORIGIN := Vector2(-270, -40)
const NEW_ORIGIN := Vector2(270, -40)

var cam: Camera2D
var spec: Dictionary

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.1, 0.11, 0.1))
	spec = JSON.parse_string(FileAccess.get_file_as_string("res://shared/data/scale_test.json"))
	var b: Dictionary = spec["building"]
	var old_b := b.duplicate(true)
	old_b["id"] = "lab_antes"
	var new_b := b.duplicate(true)
	new_b["id"] = "lab_depois"
	WorldData.register_test_building(old_b, OLD_ORIGIN)
	WorldData.register_test_building(new_b, NEW_ORIGIN)
	var ents := Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)                      # antes de criar personagens: os visuais têm de estar na árvore (@onready)
	_build("b:lab_depois:0", ents, false)
	_build("b:lab_antes:0", ents, true)
	_doors(ents)
	_label("ANTES (M2)", OLD_ORIGIN + Vector2(16, -78))
	_label("DEPOIS · 1 célula = 2 m · 19,6 px/m", NEW_ORIGIN + Vector2(16, -78))
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_view(1)
	print("[ScaleTest] pronto")

func _build(zone: String, ents: Node2D, legacy: bool) -> void:
	var built := InteriorBuilder.build(zone)
	add_child(built["floor_layer"])
	move_child(built["floor_layer"], 0)
	ents.add_child(built["objects"])
	var fl: Dictionary = WorldData.zone_floor(zone)
	if legacy:
		for fid in built["furniture"]:
			(built["furniture"][fid] as Node).queue_free()
		for f in fl["furniture"]:
			_legacy_piece(zone, f, built["objects"])
	for c in spec["characters"]:
		var v: Node2D = VISUAL.instantiate()
		built["objects"].add_child(v)
		v.apply_appearance({"skin_tone": 2, "hair_style": 2, "hair_color": 1, "clothes": (spec["characters"] as Array).find(c) % 4})
		if legacy:
			_legacy_textures(v)
		if c.has("stand"):
			v.position = WorldData.vertex_px(zone, float(c["stand"][0]), float(c["stand"][1]))
			continue
		var pose := "sit" if c.has("sit") else "lie"
		var obj: Dictionary = fl["furniture"][int(c.get("sit", c.get("lie", 0)))]
		var ps: Dictionary = WorldData.pose_for(zone, obj, pose)
		if legacy:      # antes não havia poses: o personagem ficava de pé "dentro" da peça
			v.position = WorldData.vertex_px(zone, float(obj["x"]) + 0.5, float(obj["y"]) + 0.5)
			continue
		v.set_pose(pose)
		v.scale.x = float(ps.get("flip", 1.0))
		v.rotation = ps["rot"]
		var fix := Vector2(0, -17).rotated(ps["rot"]) if pose == "lie" else Vector2.ZERO
		v.position = ps["point"] + Vector2(0, -float(ps["lift"])) - fix
		v.z_index = 2

func _legacy_piece(zone: String, f: Dictionary, parent: Node) -> void:
	## Colocação EXATAMENTE como no M2: imagem do pack centrada na esquina inferior da pegada antiga.
	var g: Array = spec["legacy_grid"].get(f["id"], [1, 1])
	var sp := Sprite2D.new()
	sp.texture = load(ART + str(spec["legacy_sprite"].get(f["id"], "pack_original/furniture_planta")) + ".png")
	sp.centered = false
	var fx := float(f["x"])
	var fy := float(f["y"])
	var bottom := WorldData.vertex_px(zone, fx + g[0], fy + g[1])
	var centre := WorldData.vertex_px(zone, fx + g[0] * 0.5, fy + g[1] * 0.5)
	var ts := sp.texture.get_size()
	sp.position = centre
	sp.offset = Vector2(bottom.x - ts.x * 0.5, bottom.y - ts.y + 2) - centre
	parent.add_child(sp)

func _legacy_textures(v: Node2D) -> void:
	var d := ART + "_scale_reference/legacy_character/"
	for n in ["Legs", "Body", "Shirt"]:
		var s: Sprite2D = v.get_node(n)
		s.texture = load(d + n.to_lower() + ".png")
		s.hframes = 3
		s.frame = 0
	(v.get_node("Hair") as Sprite2D).texture = load(d + "hair_2.png")

func _doors(ents: Node2D) -> void:
	## Porta exterior + personagem, antes (porta 36 px, personagem 38 px) e depois (41 px / 34 px).
	for k in 2:
		var legacy := k == 0
		var base := Vector2(-120 + k * 240, 300)
		for i in 3:
			var piece: Sprite2D = WALL_L.instantiate()
			piece.texture = load(ART + ("_scale_reference/legacy_door_l.png" if legacy else "buildings/pink_wall_l_door.png") if i == 1 else ART + "buildings/pink_wall_l_plain.png")
			piece.position = base + Vector2(i * 32, i * 16)
			ents.add_child(piece)
		var v: Node2D = VISUAL.instantiate()
		ents.add_child(v)
		v.apply_appearance({"skin_tone": 1, "hair_style": 0, "hair_color": 0, "clothes": 2})
		if legacy:
			_legacy_textures(v)
		v.position = base + Vector2(32 + 24, 16 + 22)
		_label("porta + personagem (%s)" % ("antes" if legacy else "depois"), base + Vector2(-10, 50))

func _label(t: String, p: Vector2) -> void:
	var l := Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	l.z_index = 50
	add_child(l)

func _view(n: int) -> void:
	match n:
		1:
			cam.position = Vector2(0, 110)
			cam.zoom = Vector2(1.3, 1.3)
		2:
			cam.position = OLD_ORIGIN + Vector2(10, 95)
			cam.zoom = Vector2(2.6, 2.6)
		3:
			cam.position = NEW_ORIGIN + Vector2(10, 95)
			cam.zoom = Vector2(2.6, 2.6)
		4:
			cam.position = Vector2(0, 300)
			cam.zoom = Vector2(3.0, 3.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode >= KEY_1 and e.keycode <= KEY_4:
		_view(e.keycode - KEY_0)

extends Node2D
## AVALIAÇÃO TEMPORÁRIA: personagem do pack "Isometric Pre-rendered Townsfolk" (amostra gratuita, Austin = adulto).
## Mesma interface que CharacterVisual.gd (apply_appearance, set_moving, set_pose, set_frame), por isso o Player,
## a colisão, a câmara e a sincronização não mudam. Voltar ao personagem original: Art.CHARACTER_SET = "classic".
## Arte: assets/art/characters_sample/townsfolk/ (ver NOTICE.md — licença só não comercial, fora da licença do projeto).
##
## Folhas: 512×512 = 8 colunas (quadros) × 8 linhas (direções), quadros de 64×64, pivô (32, 55) = chão entre os pés.
## Linhas: 0 S, 1 SW, 2 W, 3 NW, 4 N, 5 NE, 6 E, 7 SE (bússola no ecrã). Escala 1× (sem redimensionar), filtro "nearest".

const DIR := "res://assets/art/characters_sample/townsfolk/"
const FRAME := Vector2(64, 64)
const PIVOT := Vector2(32, 55)
## Valores de austin.json (fps e velocidade no chão a 1×, em px/s na horizontal do ecrã).
const ANIMS := {
	"idle": {"file": "idle.png", "fps": 6.0, "speed": 0.0},
	"walk": {"file": "walk.png", "fps": 10.0, "speed": 37.5},
	"run": {"file": "run.png", "fps": 12.0, "speed": 90.1},
	"wave": {"file": "wave.png", "fps": 10.0, "speed": 0.0},
}
## Ordem dos ângulos no chão (E = 0°, SE = 45°, …) → linha da folha.
const ROW_FOR_HEADING := [6, 7, 0, 1, 2, 3, 4, 5]
## Acima desta velocidade no chão usa-se "run", abaixo "walk" (meio caminho entre 37.5 e 90.1 px/s).
const RUN_THRESHOLD := 64.0

var character := "austin"
var anim := "idle"
var row := 0                 # começa virado para o jogador (S)
var pose := "stand"
var moving := false
var force := ""              # avaliação: "" (automático) | idle | walk | run | wave
var _textures := {}
var _t := 0.0
var _rate := 1.0
var _wave_left := 0.0
var sprite: Sprite2D
var shadow: Sprite2D
## Topo da cabeça acima dos pés (px), para o Player pôr o nome por cima: quadro mais alto do idle (51 px, com contorno).
var head_height := 51.0

func _ready() -> void:
	for a in ANIMS:
		_textures[a] = load(DIR + character + "/" + ANIMS[a]["file"]) as Texture2D
	shadow = Sprite2D.new()
	shadow.texture = load(DIR + "shadow_64px.png") as Texture2D
	shadow.centered = false
	shadow.offset = -PIVOT
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.offset = -PIVOT                    # o pivô do quadro fica na origem do nó = pés do jogador
	sprite.hframes = 8
	sprite.vframes = 8
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	_show()

# ---------------------------------------------------------------- interface comum (CharacterVisual)
func apply_appearance(_app: Dictionary) -> void:
	pass                                      # personagem com desenho fixo: pele/cabelo/roupa não se aplicam

func set_pose(p: String) -> void:
	pose = p                                  # o pack não tem sentar/deitar: fica no idle virado para a frente
	if p != "stand":
		row = 0
		anim = "idle"
	_show()

func set_moving(m: bool, _face_x: float = 0.0) -> void:
	moving = m                                # a direção vem de set_motion (vetor completo)

## Velocidade no ecrã → direção (8) e animação. O Player chama isto a cada quadro de física.
func set_motion(v: Vector2) -> void:
	if pose != "stand":
		return
	var ground := Vector2(v.x, v.y * 2.0)     # desfaz o achatamento 2:1 do isométrico
	var sp := ground.length()
	if sp > 5.0:
		var a := fposmod(rad_to_deg(atan2(ground.y, ground.x)), 360.0)
		row = ROW_FOR_HEADING[int(round(a / 45.0)) % 8]
		var name := "run" if sp >= RUN_THRESHOLD else "walk"
		_set_anim(name)
		_rate = clampf(sp / float(ANIMS[name]["speed"]), 0.6, 1.6)   # pés sem escorregar
		_wave_left = 0.0
	elif _wave_left <= 0.0:
		_set_anim("idle")
		_rate = 1.0

## Cumprimentar (animação "wave" do pack), por n ciclos de 8 quadros.
func wave(cycles: int = 2) -> void:
	_wave_left = cycles * 8.0 / float(ANIMS["wave"]["fps"])
	_set_anim("wave")
	_rate = 1.0

func set_frame(_f: int) -> void:
	pass

# ---------------------------------------------------------------- animação
func _set_anim(name: String) -> void:
	if force != "":
		name = force
	if name != anim:
		anim = name
		_t = 0.0                              # recomeça o ciclo ao mudar (sem saltar para um quadro a meio)

func _process(delta: float) -> void:
	if _wave_left > 0.0:
		_wave_left -= delta
		if _wave_left <= 0.0 and force == "":
			_set_anim("idle")
	if force != "" and anim != force:
		anim = force
		_t = 0.0
	_t += delta * float(ANIMS[anim]["fps"]) * (_rate if anim in ["walk", "run"] else 1.0)
	_show()

func _show() -> void:
	if sprite == null:
		return
	sprite.texture = _textures[anim]
	sprite.frame = row * 8 + int(_t) % 8

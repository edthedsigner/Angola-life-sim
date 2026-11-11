extends Node2D
## Exterior modular de um edifício (peças de parede/telhado são nós filhos editáveis).
## A arquitetura interior (pisos, divisões, portas, escadas, mobília, atividades) está em shared/data/world.json
## com o mesmo building_id; o interior é construído a partir dessa definição (client/scripts/InteriorBuilder.gd).
@export var building_id: String = ""
@export var building_name: String = "Edifício"
@export var floors: int = 1
@export var footprint_w: int = 3
@export var footprint_d: int = 3

func get_entrance_position(entrance_id: String = "frente") -> Vector2:
	var n := "Entrance_" + entrance_id
	if has_node(n):
		return (get_node(n) as Node2D).global_position
	return global_position

extends Node
## Art — registo central de referências visuais (autoload "Art").
## Para trocar a arte: substitui os PNG em assets/art/ (mesmo nome) ou edita os caminhos aqui.

const CHARACTER_DIR := "res://assets/art/characters/"
const HAIR_STYLE_COUNT := 4
const SKIN_TONES := [Color(0.93, 0.76, 0.62), Color(0.76, 0.54, 0.38), Color(0.55, 0.36, 0.24), Color(0.34, 0.22, 0.15)]
const SKIN_NAMES := ["Tom 1 (claro)", "Tom 2", "Tom 3", "Tom 4 (escuro)"]
const HAIR_COLORS := [Color(0.07, 0.05, 0.05), Color(0.25, 0.15, 0.08), Color(0.5, 0.3, 0.12), Color(0.8, 0.8, 0.8)]
const SHIRT_COLORS := [Color(0.85, 0.3, 0.25), Color(0.25, 0.55, 0.85), Color(0.3, 0.7, 0.4), Color(0.9, 0.8, 0.3)]
const HAIR_NAMES := ["Curto", "Médio", "Com tranças", "Rapado"]

func skin_color(i: int) -> Color:
	return SKIN_TONES[clampi(i, 0, SKIN_TONES.size() - 1)]

func hair_color(i: int) -> Color:
	return HAIR_COLORS[clampi(i, 0, HAIR_COLORS.size() - 1)]

func shirt_color(i: int) -> Color:
	return SHIRT_COLORS[clampi(i, 0, SHIRT_COLORS.size() - 1)]

func hair_texture(i: int) -> Texture2D:
	return load(CHARACTER_DIR + "hair_%d.png" % clampi(i, 0, HAIR_STYLE_COUNT - 1)) as Texture2D

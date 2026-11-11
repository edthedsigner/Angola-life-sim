extends RefCounted
## Lê config/branding.json — o nome/logótipo do jogo é PROVISÓRIO e vive só nesse ficheiro + assets/art/ui/logo.png.
const PATH := "res://config/branding.json"

static func data() -> Dictionary:
	var d := {"title": "Jogo", "title_line1": "", "title_line2": "", "window_title": "Jogo", "logo": ""}
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			d.merge(parsed, true)
	return d

extends Node
## GameState - Estado local do cliente (personagem atual, UI flags, etc.)

signal character_loaded(character: Dictionary)
signal money_changed(new_amount: int)
signal self_changed                       # novo estado privado vindo do servidor (necessidades, dinheiro, inventário...)
signal chat_added(name: String, text: String)

var current_account: Dictionary = {}
var current_character: Dictionary = {}
var is_in_world: bool = false
var onboarding: Dictionary = {}
## Estado privado autoritativo (só o próprio jogador o recebe). O cliente nunca o altera localmente.
var self_state: Dictionary = {}
var _clock_at_ms: int = 0
var chat_log: Array = []                   # [{name, text, t}] — app Mensagens
const SESSION_FILE := "user://session.cfg"

## O token de sessão guardado é só uma conveniência para retomar a sessão; o servidor valida-o e é a fonte de verdade.
func save_session(token: String, server: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "token", token)
	cfg.set_value("session", "server", server)
	cfg.save(SESSION_FILE)

func load_session(server: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_FILE) != OK:
		return ""
	if str(cfg.get_value("session", "server", "")) != server:
		return ""
	return str(cfg.get_value("session", "token", ""))

func clear_session() -> void:
	if FileAccess.file_exists(SESSION_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))

func set_account(data: Dictionary) -> void:
	current_account = data

func set_character(data: Dictionary) -> void:
	current_character = data
	character_loaded.emit(data)

func get_money() -> int:
	return current_character.get("money", 0)

func add_money(amount: int) -> void:
	# Apenas para UI local. O servidor é autoritativo.
	current_character["money"] = current_character.get("money", 0) + amount
	money_changed.emit(current_character["money"])

func apply_self_state(d: Dictionary) -> void:
	self_state = d
	_clock_at_ms = Time.get_ticks_msec()
	if current_character.size() > 0:
		current_character["money"] = int(d.get("money", 0))
	self_changed.emit()

func need(k: String) -> float:
	return float(self_state.get("needs", {}).get(k, 0.0))

## Relógio do jogo: valor do servidor + tempo decorrido localmente (sem saltos entre atualizações).
func game_time() -> float:
	if self_state.is_empty():
		return 8.0 * 3600.0
	return float(self_state.get("game_s", 0.0)) + (Time.get_ticks_msec() - _clock_at_ms) / 1000.0 * float(self_state.get("time_scale", 4.0))

func clock_text() -> String:
	var g := game_time()
	return "Dia %d · %02d:%02d" % [int(g / 86400.0) + 1, int(g / 3600.0) % 24, int(g / 60.0) % 60]

static func fmt_kz(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		if (s.length() - i) % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if v < 0 else "") + out + " Kz"

func add_chat(n: String, text: String) -> void:
	chat_log.append({"name": n, "text": text, "t": clock_text()})
	print("[Chat] %s: %s" % [n, text])
	if chat_log.size() > 60:
		chat_log.pop_front()
	chat_added.emit(n, text)

func clear() -> void:
	self_state = {}
	chat_log = []
	current_account = {}
	current_character = {}
	onboarding = {}
	is_in_world = false

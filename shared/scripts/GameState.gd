extends Node
## GameState - Estado local do cliente (personagem atual, UI flags, etc.)

signal character_loaded(character: Dictionary)
signal money_changed(new_amount: int)
signal self_changed                       # novo estado privado vindo do servidor (necessidades, dinheiro, inventário...)
signal chat_added(name: String, text: String)
signal social_changed                     # amigos, pedidos, notificações, conversas (estado privado do servidor)
signal dm_received(pub: String, msg: Dictionary)

var current_account: Dictionary = {}
var current_character: Dictionary = {}
var is_in_world: bool = false
var onboarding: Dictionary = {}
## Estado privado autoritativo (só o próprio jogador o recebe). O cliente nunca o altera localmente.
var self_state: Dictionary = {}
var _clock_at_ms: int = 0
var chat_log: Array = []                   # [{name, text, t}] — app Mensagens (separador "Perto de ti")
var social: Dictionary = {}                # social_state do servidor (só o próprio jogador o recebe)
var dm_cache: Dictionary = {}              # pub -> [mensagens] (conversas abertas nesta sessão)
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

func apply_social(d: Dictionary) -> void:
	social = d
	social_changed.emit()

func unread_messages() -> int:
	var n := 0
	for c in social.get("conversations", []):
		n += int(c.get("unread", 0))
	return n

func unread_notifications() -> int:
	var n := 0
	for x in social.get("notifications", []):
		if not bool(x.get("read", false)) and str(x.get("kind", "")) != "dm":
			n += 1
	return n

func on_dm(msg: Dictionary) -> void:
	var pub := str(msg.get("with", ""))
	if dm_cache.has(pub):
		(dm_cache[pub] as Array).append(msg.get("data", {}))
	var found := false
	for c in social.get("conversations", []):
		if c["pub"] == pub:
			c["unread"] = int(msg.get("unread", 1))
			c["last"] = str(msg.get("data", {}).get("text", ""))
			c["last_mine"] = false
			c["t"] = float(msg.get("data", {}).get("t", 0))
			found = true
	if not found and social.has("conversations"):
		(social["conversations"] as Array).push_front({"pub": pub, "name": msg.get("name", ""), "last": msg.get("data", {}).get("text", ""), "unread": int(msg.get("unread", 1)), "t": msg.get("data", {}).get("t", 0), "appearance": {}})
	dm_received.emit(pub, msg.get("data", {}))
	social_changed.emit()

func on_notification(n: Dictionary) -> void:
	if not social.has("notifications"):
		social["notifications"] = []
	var lst: Array = social["notifications"]
	if str(n.get("kind", "")) == "dm":                 # uma por conversa (não inundar)
		for i in range(lst.size() - 1, -1, -1):
			if lst[i].get("kind") == "dm" and lst[i].get("from", {}).get("pub") == n.get("from", {}).get("pub"):
				lst.remove_at(i)
	lst.append(n)
	social_changed.emit()

static func time_label(t: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(t) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "%02d/%02d %02d:%02d" % [d["day"], d["month"], d["hour"], d["minute"]]

func clear() -> void:
	social = {}
	dm_cache = {}
	self_state = {}
	chat_log = []
	current_account = {}
	current_character = {}
	onboarding = {}
	is_in_world = false

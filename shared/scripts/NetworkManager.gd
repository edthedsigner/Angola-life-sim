extends Node
## NetworkManager — cliente WebSocket para server_python/server.py (autoload).
## Endereço: ver resolve_server_url() (argumento --server=, ANGOLA_SERVER, config/server.json do build, ?server=). docs/DEPLOY.md

signal connected_to_server
signal connection_failed
signal disconnected_from_server
signal player_joined(peer_id: String, character_data: Dictionary)
signal player_left(peer_id: String)
signal player_moved(peer_id: String, position: Vector2, zone: String)
signal zone_changed(peer_id: String, zone: String, position: Vector2)
signal position_corrected(position: Vector2, zone: String)
## Mensagens de jogo (self_state, door_state, zone_state, chat, player_activity, activity_started/done, notice, profile)
signal game_message(msg: Dictionary)
signal character_spawned(character_data: Dictionary)
signal auth_success(account_data: Dictionary)
signal auth_failed(reason: String)
signal background_received(background: Dictionary)
signal server_error(message: String)
signal session_invalid
signal onboarding_changed(state: String, step: int)
signal logged_out

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 7777

var socket: WebSocketPeer = WebSocketPeer.new()
var connected: bool = false
var local_peer_id: String = ""
var _connecting: bool = false
var host: String = DEFAULT_HOST
var port: int = DEFAULT_PORT
var latency_ms: float = -1.0       # medido por ping/pong (mostrado no debug F3)
var _ping_t: float = 0.0
var msgs_in: int = 0
var msgs_out: int = 0

const CONFIG_PATH := "res://config/server.json"   # escrito pelo build na nuvem (ver docs/DEPLOY.md); opcional
var url: String = ""
var url_source: String = "omissão"

func _ready() -> void:
	url = resolve_server_url()
	print("[Client] Servidor: %s  (origem: %s)" % [url, url_source])

## Ordem: argumento `--server=` → variável ANGOLA_SERVER → `?server=` no link da página (só se o build o permitir)
## → config/server.json (definido no build) → ws://127.0.0.1:7777.
## Aceita URL completo (wss://jogo.exemplo.com) ou host[:porta]. Página em https => sempre wss (o browser bloqueia ws://).
func resolve_server_url() -> String:
	var cfg := _file_config()
	var addr := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			addr = a.substr(9)
			url_source = "argumento --server"
	if addr == "" and OS.get_environment("ANGOLA_SERVER") != "":
		addr = OS.get_environment("ANGOLA_SERVER")
		url_source = "ANGOLA_SERVER"
	# Um link com ?server= poderia apontar jogadores para um servidor falso (que recebe as palavras-passe):
	# em builds de produção (config com "url") só é aceite se "allow_override" for true.
	var override_ok := not cfg.has("url") or bool(cfg.get("allow_override", false))
	if addr == "" and override_ok and OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server') || ''", true)
		if q is String and q != "":
			addr = q
			url_source = "link ?server="
	if addr == "" and cfg.has("url") and str(cfg["url"]) != "":
		addr = str(cfg["url"])
		url_source = CONFIG_PATH
	if addr == "":
		addr = "%s:%d" % [DEFAULT_HOST, DEFAULT_PORT]
		url_source = "omissão"
	return normalize_url(addr, page_is_https())

static func normalize_url(addr: String, https_page: bool) -> String:
	var a := addr.strip_edges().rstrip("/")
	if a.begins_with("https://"):
		a = "wss://" + a.substr(8)
	elif a.begins_with("http://"):
		a = "ws://" + a.substr(7)
	if not a.contains("://"):
		var hostport := a.split("/")[0]
		if https_page:
			a = "wss://" + a                       # porta 443 por omissão (atrás do TLS do host)
		else:
			a = "ws://" + a + ("" if hostport.contains(":") else ":%d" % DEFAULT_PORT)
	if https_page and a.begins_with("ws://"):
		var h := a.substr(5).split("/")[0].split(":")[0]
		if h != "localhost" and h != "127.0.0.1":
			push_warning("Página em https: a usar wss:// em vez de ws:// para " + h)
			a = "wss://" + a.substr(5)
	return a

func page_is_https() -> bool:
	if not OS.has_feature("web"):
		return false
	return str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:"

func _file_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return d if d is Dictionary else {}

func server_url() -> String:
	return url

func _process(_delta: float) -> void:
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED and not (connected or _connecting):
		return
	socket.poll()
	state = socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and connected and GameState.is_in_world:
		_ping_t += _delta
		if _ping_t >= 2.0:
			_ping_t = 0.0
			_send({"type": "ping", "t": Time.get_ticks_msec()})
	if state == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			_handle_message(socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_connecting := _connecting
		connected = false
		_connecting = false
		local_peer_id = ""
		print("[Client] Ligação fechada")
		if was_connecting:
			connection_failed.emit()
		else:
			disconnected_from_server.emit()

func connect_to_server() -> void:
	if connected or _connecting:
		return
	print("[Client] A ligar a ", server_url())
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(server_url())
	if err != OK:
		push_error("Falha ao iniciar ligação: %s" % error_string(err))
		connection_failed.emit()
		return
	_connecting = true

func disconnect_from_server() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.close()

func _send(msg: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	msgs_out += 1
	socket.send_text(JSON.stringify(msg))

func _handle_message(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = json.data
	msgs_in += 1
	match str(msg.get("type", "")):
		"welcome":
			local_peer_id = str(msg.get("peer_id", ""))
			connected = true
			_connecting = false
			connected_to_server.emit()
		"auth_response":
			if msg.get("success", false):
				auth_success.emit(msg.get("data", {}))
			else:
				auth_failed.emit(str(msg.get("error", "Erro desconhecido")))
		"character_created":
			if msg.get("success", false):
				var data: Dictionary = msg.get("data", {})
				character_spawned.emit(data)
				if data.has("background"):
					background_received.emit(data["background"])
			else:
				auth_failed.emit(str(msg.get("error", "Erro ao criar personagem")))
		"spawn_player":
			var d: Dictionary = msg.get("data", {})
			player_joined.emit(str(d.get("peer_id", "")), d)
		"player_left":
			player_left.emit(str(msg.get("peer_id", "")))
		"position":
			player_moved.emit(str(msg.get("peer_id", "")), Vector2(float(msg.get("x", 0)), float(msg.get("y", 0))), str(msg.get("zone", "w")))
		"zone_change":
			zone_changed.emit(str(msg.get("peer_id", "")), str(msg.get("zone", "w")), Vector2(float(msg.get("x", 0)), float(msg.get("y", 0))))
		"position_correction":
			position_corrected.emit(Vector2(float(msg.get("x", 0)), float(msg.get("y", 0))), str(msg.get("zone", "w")))
		"pong":
			latency_ms = float(Time.get_ticks_msec()) - float(msg.get("t", 0))
		"self_state":
			GameState.apply_self_state(msg.get("data", {}))
			game_message.emit(msg)
		"chat":
			GameState.add_chat(str(msg.get("name", "")), str(msg.get("text", "")))
			game_message.emit(msg)
		"social_state":
			GameState.apply_social(msg.get("data", {}))
			game_message.emit(msg)
		"dm_message":
			GameState.on_dm(msg)
			game_message.emit(msg)
		"notification":
			GameState.on_notification(msg.get("data", {}))
			game_message.emit(msg)
		"session_invalid":
			session_invalid.emit()
		"onboarding_state":
			onboarding_changed.emit(str(msg.get("state", "")), int(msg.get("story_step", 0)))
		"logged_out":
			logged_out.emit()
		"error":
			server_error.emit(str(msg.get("error", "")))
		_:
			game_message.emit(msg)

func request_register(username: String, password: String) -> void:
	_send({"type": "register", "username": username, "password": password})

func request_login(username: String, password: String) -> void:
	_send({"type": "login", "username": username, "password": password})

func request_create_character(_account_id: String, appearance: Dictionary, char_name: String) -> void:
	_send({"type": "create_character", "appearance": appearance, "name": char_name})

func request_enter_world(character_id: String) -> void:
	_send({"type": "enter_world", "character_id": character_id})

func send_position(pos: Vector2) -> void:
	_send({"type": "position", "x": pos.x, "y": pos.y})

func request_resume_session(token: String) -> void:
	_send({"type": "resume_session", "token": token})

func request_logout() -> void:
	_send({"type": "logout"})

func request_onboarding(state: String, step: int) -> void:
	_send({"type": "onboarding_progress", "state": state, "step": step})

## Pedido genérico de jogo (o servidor valida tudo: proximidade, zona, dinheiro, requisitos).
func send_game(type: String, fields: Dictionary = {}) -> void:
	var m := fields.duplicate()
	m["type"] = type
	_send(m)

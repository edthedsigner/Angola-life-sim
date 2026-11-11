extends Node
## NetworkManager — cliente WebSocket para server_python/server.py (autoload).
## Endereço: argumentos `-- --server=host:porta`, variável ANGOLA_SERVER, ou 127.0.0.1:7777.

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

func _ready() -> void:
	var addr := OS.get_environment("ANGOLA_SERVER")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			addr = a.substr(9)
	if addr != "":
		var parts := addr.split(":")
		host = parts[0]
		if parts.size() > 1:
			port = int(parts[1])

func server_url() -> String:
	return "ws://%s:%d" % [host, port]

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

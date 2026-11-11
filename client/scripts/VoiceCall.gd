extends Node
## Chamadas de voz P2P (docs/SOCIAL.md).
## * Sinalização (oferta/resposta/ICE) passa pelo servidor, que só a reencaminha entre os 2 participantes de uma
##   chamada aceite; permissões (privacidade, bloqueio, ocupado, offline) são decididas no servidor.
## * Áudio: WebRTC data channel não-ordenado e sem retransmissão (o WebRTC do Godot só tem data channels).
##   Microfone (AudioStreamMicrophone + AudioEffectCapture) -> 8 kHz mono -> G.711 μ-law (64 kbit/s) em pacotes de 20 ms
##   -> AudioStreamGenerator do outro lado. Nunca passa pelo servidor do jogo.
## * Disponível na versão Web (o browser fornece WebRTC). Em versões nativas é preciso a extensão webrtc-native;
##   sem ela a chamada falha com uma mensagem clara (sem fingir que funciona).

signal state_changed(state: String, info: Dictionary)

const RATE := 8000
const PACKET := 160                 # 20 ms
const CONNECT_TIMEOUT := 20.0

var state := "idle"                 # idle | outgoing | incoming | connecting | active
var call_id := ""
var peer_name := ""
var peer_pub := ""
var role := ""
var muted := false
var pc: Object = null               # WebRTCPeerConnection
var dc: Object = null               # WebRTCDataChannel
var sent := 0
var received := 0
var mic_level := 0.0
var rx_level := 0.0
var active_since := 0.0
var _t_state := 0.0
var _t_log := 0.0
var _mic_player: AudioStreamPlayer
var _out_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _playback: AudioStreamGeneratorPlayback
var _acc := 0.0
var _acc_n := 0
var _acc_sum := 0.0
var _pending_tx := PackedByteArray()
var _pending_ice: Array = []
var _remote_set := false

func _ready() -> void:
	NetworkManager.game_message.connect(_on_msg)

func available() -> bool:
	return ClassDB.class_exists("WebRTCPeerConnection") and ClassDB.can_instantiate("WebRTCPeerConnection")

# ------------------------------------------------------------------ fluxo de chamada
func call_player(pub: String, name: String) -> void:
	if state != "idle":
		_info("Já estás numa chamada.")
		return
	peer_pub = pub
	peer_name = name
	NetworkManager.send_game("call_start", {"target": pub})

func answer(accept: bool) -> void:
	if state == "incoming":
		NetworkManager.send_game("call_answer", {"call_id": call_id, "accept": accept})
		if not accept:
			_reset("Chamada recusada.")

func hangup(reason: String = "hangup") -> void:
	if state == "idle":
		return
	NetworkManager.send_game("call_end", {"call_id": call_id, "reason": "cancelled" if state == "outgoing" else reason})
	_reset("Chamada terminada." if reason == "hangup" else "A ligação falhou.")

func toggle_mute() -> void:
	muted = not muted
	_emit()

func _set_state(s: String) -> void:
	state = s
	_t_state = 0.0
	print("[Voz] estado=%s" % s)
	_emit()

func _emit(extra: Dictionary = {}) -> void:
	var info := {"name": peer_name, "pub": peer_pub, "muted": muted, "secs": (Time.get_ticks_msec() / 1000.0 - active_since) if state == "active" else 0.0,
		"mic": mic_level}
	info.merge(extra)
	state_changed.emit(state, info)

func _info(t: String) -> void:
	get_tree().call_group("hud", "notify", t, false)

func _on_msg(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"call_outgoing":
			call_id = str(msg.get("call_id", ""))
			peer_name = str(msg.get("peer", {}).get("name", peer_name))
			_set_state("outgoing")
		"call_failed":
			_info(str(msg.get("text", "Não foi possível ligar.")))
			_reset("")
		"call_incoming":
			if state != "idle":
				return
			call_id = str(msg.get("call_id", ""))
			peer_name = str(msg.get("from", {}).get("name", ""))
			peer_pub = str(msg.get("from", {}).get("pub", ""))
			_set_state("incoming")
		"call_accepted":
			if str(msg.get("call_id", "")) != call_id:
				return
			role = str(msg.get("role", ""))
			_set_state("connecting")
			_start_rtc(msg.get("ice_servers", []))
		"rtc_signal":
			if str(msg.get("call_id", "")) == call_id:
				_on_signal(msg.get("payload", {}))
		"call_ended":
			if str(msg.get("call_id", "")) == call_id:
				var r := str(msg.get("reason", ""))
				_reset({"declined": "Chamada recusada.", "no_answer": "Não atendeu.", "missed": "Chamada perdida.", "offline": "A outra pessoa saiu.",
					"failed": "A ligação falhou.", "cancelled": "Chamada cancelada."}.get(r, "Chamada terminada."))

# ------------------------------------------------------------------ WebRTC
func _start_rtc(ice: Array) -> void:
	if not available():
		_info("Voz indisponível nesta versão (requer a versão Web ou a extensão webrtc-native).")
		hangup("failed")
		return
	pc = ClassDB.instantiate("WebRTCPeerConnection")
	var err: int = pc.initialize({"iceServers": ice})
	if err != OK:
		_info("Voz indisponível nesta plataforma (WebRTC).")
		hangup("failed")
		return
	pc.session_description_created.connect(_on_sdp)
	pc.ice_candidate_created.connect(_on_ice)
	dc = pc.create_data_channel("voz", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	if role == "offerer":
		pc.create_offer()

func _on_sdp(type: String, sdp: String) -> void:
	pc.set_local_description(type, sdp)
	NetworkManager.send_game("rtc_signal", {"call_id": call_id, "payload": {"kind": type, "sdp": sdp}})

func _on_ice(media: String, index: int, name: String) -> void:
	NetworkManager.send_game("rtc_signal", {"call_id": call_id, "payload": {"kind": "ice", "media": media, "index": index, "name": name}})

func _on_signal(p: Dictionary) -> void:
	if pc == null:
		return
	match str(p.get("kind", "")):
		"offer", "answer":
			pc.set_remote_description(str(p["kind"]), str(p.get("sdp", "")))
			_remote_set = true
			for c in _pending_ice:
				pc.add_ice_candidate(c[0], c[1], c[2])
			_pending_ice.clear()
		"ice":
			if not _remote_set:                           # candidatos podem chegar antes da descrição remota
				_pending_ice.append([str(p.get("media", "")), int(p.get("index", 0)), str(p.get("name", ""))])
			else:
				pc.add_ice_candidate(str(p.get("media", "")), int(p.get("index", 0)), str(p.get("name", "")))

# ------------------------------------------------------------------ áudio
func _audio_start() -> void:
	var bus := AudioServer.get_bus_index("VozMic")
	if bus == -1:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "VozMic")
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5                         # tolera fotogramas lentos sem perder áudio (o padrão 0,1 s transborda)
		AudioServer.add_bus_effect(bus, cap)
		AudioServer.set_bus_mute(bus, true)             # não ouvir o próprio microfone
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_capture.clear_buffer()
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "VozMic"
	add_child(_mic_player)
	_mic_player.play()                                  # no browser isto pede a permissão do microfone
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.4
	_out_player = AudioStreamPlayer.new()
	_out_player.stream = gen
	add_child(_out_player)
	_out_player.play()
	_playback = _out_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _audio_stop() -> void:
	for p in [_mic_player, _out_player]:
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	_mic_player = null
	_out_player = null
	_playback = null

static func _ulaw_enc(x: float) -> int:
	var s := int(clampf(x, -1.0, 1.0) * 32635.0)
	var sign := 0x80 if s < 0 else 0
	s = mini(absi(s) + 132, 32767)
	var exp := 7
	var mask := 0x4000
	while exp > 0 and (s & mask) == 0:
		exp -= 1
		mask >>= 1
	var mant := (s >> (exp + 3)) & 0x0F
	return (~(sign | (exp << 4) | mant)) & 0xFF

static func _ulaw_dec(b: int) -> float:
	b = (~b) & 0xFF
	var sign := b & 0x80
	var exp := (b >> 4) & 0x07
	var mant := b & 0x0F
	var s := ((mant << 3) + 132) << exp
	s -= 132
	return float(-s if sign else s) / 32768.0

func _pump_mic() -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	var step := AudioServer.get_mix_rate() / float(RATE)
	var peak := 0.0
	for f: Vector2 in buf:
		var v: float = (f.x + f.y) * 0.5
		_acc_sum += v
		_acc_n += 1
		_acc += 1.0
		if _acc >= step:                            # média das amostras = filtro passa-baixo simples + decimação
			_acc -= step
			var smp := _acc_sum / _acc_n
			_acc_sum = 0.0
			_acc_n = 0
			peak = maxf(peak, absf(smp))
			_pending_tx.append(_ulaw_enc(0.0 if muted else smp))
	mic_level = lerpf(mic_level, peak, 0.3)
	while _pending_tx.size() >= PACKET:
		var pkt := _pending_tx.slice(0, PACKET)
		_pending_tx = _pending_tx.slice(PACKET)
		if dc and dc.get_ready_state() == 1:          # WebRTCDataChannel.STATE_OPEN
			dc.put_packet(pkt)
			sent += 1

func _pump_rx() -> void:
	while dc and dc.get_available_packet_count() > 0:
		var pkt: PackedByteArray = dc.get_packet()
		received += 1
		var peak := 0.0
		for b: int in pkt:
			var v: float = _ulaw_dec(b)
			peak = maxf(peak, absf(v))
			if _playback and _playback.can_push_buffer(1):
				_playback.push_frame(Vector2(v, v))
		rx_level = lerpf(rx_level, peak, 0.3)

func _process(delta: float) -> void:
	if state == "idle":
		return
	_t_state += delta
	if pc:
		pc.poll()
		if state == "connecting":
			if dc and dc.get_ready_state() == 1:
				active_since = Time.get_ticks_msec() / 1000.0
				_audio_start()
				_set_state("active")
			elif pc.get_connection_state() == 4 or _t_state > CONNECT_TIMEOUT:      # STATE_FAILED
				_info("Não foi possível estabelecer a ligação de voz (rede/firewall).")
				hangup("failed")
				return
		elif state == "active":
			if pc.get_connection_state() >= 4:            # failed / closed
				hangup("failed")
				return
			_pump_mic()
			_pump_rx()
			_t_log += delta
			if _t_log > 2.0:
				_t_log = 0.0
				print("[Voz] enviados=%d recebidos=%d mic=%.3f recebido=%.3f fps=%d mix=%d" % [sent, received, mic_level, rx_level, Engine.get_frames_per_second(), AudioServer.get_mix_rate()])
				_emit()

func _reset(text: String) -> void:
	if text != "":
		get_tree().call_group("hud", "notify", text, true)
	_audio_stop()
	if dc:
		dc.close()
	if pc:
		pc.close()
	pc = null
	dc = null
	call_id = ""
	role = ""
	muted = false
	sent = 0
	received = 0
	_pending_tx = PackedByteArray()
	_pending_ice.clear()
	_remote_set = false
	_set_state("idle")

func debug_lines() -> Array:
	return ["estado: %s   papel: %s" % [state, role], "WebRTC disponível: %s" % available(),
		"pacotes enviados/recebidos: %d / %d" % [sent, received], "nível mic: %.3f   recebido: %.3f" % [mic_level, rx_level],
		"ligação: %s" % (str(pc.get_connection_state()) if pc else "—")]

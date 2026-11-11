# Player social interaction

Tap or click another player in the world to open their **profile** (bottom sheet on phones, side panel on desktop).
Everything is decided on the server (`server_python/social.py`, routed by `server.py: handle_social`). The client only
displays what the server returns and sends requests.

Screenshots: `docs/screenshots/social_01…12_*.png` (two real browser clients against the real server, plus a phone viewport).

## What the profile shows, and what it never shows
Shown: avatar (appearance), username (the **character name**, since account login names are never exposed), level, status
(walking / at work / cooking… from the current activity), online, "playing since", friend count, your relationship to them.

Never sent to another player: money, inventory, messages, internal character/account ids, zone coordinates beyond what the
world already shows. Players are addressed by an opaque random handle `pub` (12 hex chars, generated per character and
persisted). `public_view` and `public_profile` are the only functions that build data about another player, and both use
whitelists. The integration tests assert that no `id`, `money` or `inventory` key ever appears in another player's data.

## Actions (grouped in the panel)
| Group | Action | Server rules |
|---|---|---|
| Header | **Add friend** (primary) · Cancel request · Accept / Decline · Remove | no duplicates; a request to someone who already asked you becomes an accept; limit 200 friends; blocked pairs can't interact |
| Convidar | **My house** | only if you currently rent/own a home; the guest gets a 30 min guest pass to *your* home only, valid while your rental is active (checked when entering the building) |
| | **Public place** | any public building from `world.json`; the guest gets directions |
| | Expiry / cancel | invites expire after 10 min (`ANGOLA_INVITE_TTL`); the sender can cancel; one pending invite per pair and kind |
| | Accept → guidance | the accepting player is auto-walked: interior → ground floor → exit → building entrance (`World.guide_to`) |
| Jogar | Play a game | reads the `games` registry in `world.json`. It is **empty**, so the button shows "no games available yet" and is disabled. Adding a game = add an entry (`_games_doc` explains the fields); the invite flow already carries `game_id` |
| Presentes | **Money** | presets / custom amount → confirmation screen (shows your balance after) → send. Integer 1…1 000 000, must have the funds; debit+credit happen in one synchronous step (no `await` in between), so it's atomic in the single-threaded server; `req_id` makes retries idempotent (a repeat returns the first result, nothing moves twice); both sides get a bank transaction entry ("Presente para/de …") |
| | **Item** | choose from *your* inventory (sent from the server's copy, never the client's count) → confirm → atomic move, same `req_id` rule |
| Comunicar | **Message** | opens the phone's Mensagens conversation (the same messaging system, not a second one) |
| | **Call** | real voice call, see below. Hidden or shown according to `can_call`, but that's only presentation: the server re-checks |
| Footer | Block / Unblock | blocking removes friendship and pending requests, and stops DMs, invites, gifts and calls in both directions |

## Private messages
* Persistent (`server_python/data/social.json`), 500 chars max, last 200 per conversation, timestamps.
* Delivered live if the recipient is online, otherwise waiting in the conversation list with an unread count.
* Unread indicators: badge on the phone dock button, on the Mensagens app, and per conversation. Opening a conversation sends `dm_read`.
* Reachable from: the profile (Mensagem), the phone (Mensagens → Conversas, or Amigos → Mensagem), and from the notification.
* Chat stays what it was (proximity/public); DMs are separate and private.

## Notifications
Bell button with badge (bottom dock). Kept per player (last 60), persisted, so offline players see them when they log in.
Actionable where it makes sense: friend request → Aceitar / Recusar; invite → Aceitar / Recusar; new message → Abrir;
missed call → Ligar de volta. Gifts, accepted requests, level-ups and expiries are informational. Repeated DM notifications from the same
person collapse into one. A toast appears when a notification arrives (skipped if you're already reading that conversation).

## Voice calls
Real audio, peer-to-peer over **WebRTC**, with the game server only doing signaling.

* **Permissions** (phone → Definições → *Quem te pode ligar*): Todos (default) / Só amigos / Ninguém. Stored on the server, checked
  on `call_start`, and changing it applies immediately to new calls. Blocking also blocks calls. Other checks: target online, neither
  side already in a call, 1 call request per second.
* **Flow:** `call_start` → callee sees an incoming card (Atender / Recusar), ringing for 30 s (`ANGOLA_CALL_RING_SECS`) then "missed call".
  On answer the server sends both sides `call_accepted` with their role and the ICE server list. The caller creates the offer. The server relays
  `rtc_signal` (offer / answer / ice only, ≤ 20 000 chars) **only between the two participants of that accepted call**. Either side
  can hang up; disconnecting ends the call.
* **Audio path:** Godot 4's WebRTC exposes data channels but not media tracks, so audio goes over an unreliable, unordered
  data channel (`maxRetransmits = 0`, so a lost packet is dropped rather than delaying the rest): microphone (`AudioStreamMicrophone` →
  `AudioEffectCapture` on a muted bus) → mono, low-pass + decimate to 8 kHz → G.711 μ-law (telephone codec) → 160-byte
  packets every 20 ms (64 kbit/s) → other side decodes into an `AudioStreamGenerator`. Mute button sends silence.
* **Verified** between two browser clients (Chromium with a fake microphone): both cards, connecting → active, packets both
  directions, received level follows the remote mic level, hang-up clears both sides (`social_08…10`).

### Limits of the voice implementation (honest list)
1. **Platforms:** works in the **web export** (the browser provides WebRTC). Native desktop/mobile builds need the
   [webrtc-native](https://github.com/godotengine/webrtc-native) GDExtension in `addons/`. Without it `VoiceCall.gd` detects
   the missing class when the call connects, tells the player voice isn't available in this build and ends the call. Nothing pretends to work.
2. **NAT traversal:** the default ICE list is Google's public STUN. On strict/corporate/mobile-carrier networks a **TURN server**
   is required: set `ANGOLA_ICE_SERVERS='[{"urls":["turn:turn.example.com:3478"],"username":"u","credential":"p"}]'` on the server
   (coturn is the usual choice and can run on the same VPS as the game server).
3. **Quality:** 8 kHz μ-law is phone-call quality. There is no echo cancellation beyond what the browser's mic capture applies,
   no jitter buffer beyond the generator's 0.4 s buffer, and no Opus (Godot has no built-in Opus encoder).
4. **Headless test caveat:** in the test harness the page renders at 5–6 FPS (software GL), and the single-threaded web
   audio driver then only processes about 20% of real time, so we measured about 10 packets/s instead of 50. The code sends everything
   the mixer captures each frame; on a normal machine at 60 FPS the mixer keeps real time.
5. The microphone permission prompt is the browser's. If the player denies it the call still connects and they can listen.
   `project.godot` has `audio/driver/enable_input=true`, which the microphone needs.

## Level / progression foundation
There was no level system, so a small one was added without inventing rewards:
* XP comes from activities the player already does, defined in `world.json → progression.xp` (work 25, cook 8, dine 4, sleep 5,
  shower 3, rest 1). It's awarded server-side when the activity completes.
* Level curve: reaching level *n* needs `level_base · n(n−1)/2` XP (base 100: level 2 at 100, level 3 at 300, level 4 at 600…).
* Shown in the HUD ("Nível N"), on profiles, and as a notification on level-up. **Levels unlock nothing yet**, so balancing
  rewards is a design decision left open.

## Protocol (client → server)
`social_profile, social_state_request, friend_request, friend_accept, friend_decline, friend_cancel, friend_remove, block,
unblock, privacy_set, invite, invite_respond, invite_cancel, gift_money, gift_item, dm_send, dm_history, dm_read,
call_start, call_answer, call_end, rtc_signal, notif_read`. Targets are always `target: <pub>`.
Server → client: `social_profile, social_state, social_result, notification, dm_message, dm_history, dm_sent, call_*,
rtc_signal`. Results are delivered per recipient, so each side only receives its own view.

Rate limits: friend requests 0.5 s, invites 0.8 s (only valid ones count), DMs 0.4 s, calls 1 s.

## Tests
`python tests/run_integration.py` (141 checks) covers privacy (no private keys in public data), friend states and duplicates,
money/item gifts including bad amounts, insufficient funds and duplicate `req_id`, DMs online and offline, invites (house without a
home, place, game id rejected while the registry is empty, duplicates, cancel, expiry, guest entering the host's house), blocking,
call privacy modes, busy, relay only between participants, hang-up, no-answer and offline.

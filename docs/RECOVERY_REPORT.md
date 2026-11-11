# Recovery report — Milestone 1

## Audit of the previous delivery (what was actually wrong)
| Area | Finding |
|---|---|
| Character invisible | `Player.tscn` Sprite2D had **no texture**; nothing ever assigned one. Appearance dict was sent to server and never rendered. |
| World invisible / "nothing visible" | World was 2 ColorRect "buildings" + flat rects. **Camera was `enabled=false` in the scene and `make_current()` does not enable it → no active camera**, so only the top-left of the world was shown. Project also used Forward+ (Vulkan), which fails/black-screens on many machines. |
| Python server | Logic mostly worked, but: `enter_world` needed no login; `account_id` for character creation was trusted from the client; spawn messages leaked each player's full life background to everyone; no input validation; unsalted SHA-256; saves non-atomic; same character could be spawned twice; `websockets.server.WebSocketServerProtocol` import is deprecated. |
| Dead code | `server/` (old Godot server) called a non-existent `NetworkManager.start_server`; `AuthService.gd` autoload unused. Both removed. |
| Modularity | None: world was hardcoded colored rectangles. |

## What was changed
* Visible layered character (skin/hair/shirt) driven by server appearance data; name label; walk animation; remote players use their own data and are interpolated.
* Working camera (zoom 2, smoothed, explicitly enabled). GL Compatibility renderer.
* Isometric world from editable scenes: 475 ground tiles (your pack), road with markings + side street, sidewalks, 4 modular buildings (different sizes 3x3/5x4/3x3/3x4, 1–3 floors, doors, windows, shopfronts, roofs, collision footprints, entrance markers), props, world-bounds collision, y-sorting.
* Character creation screen has a live preview of skin/hair.
* HUD: connection state, character, position, money, nearby players; join/leave notices; connection-loss banner; auto-reconnect on the menu.
* Server hardening (see audit); background generator preserved and extended (`family_assets`, explicit `housing: sem_abrigo`, no owned properties); spawn/bounds in `server_python/world_config.json`.

## Tests actually performed
1. **Static validation** (`tools/validate_and_preview.py`): every `ext_resource` path, id, parent and `res://` reference in scenes/scripts resolves. PASSED.
2. **Server integration test** (`tests/run_integration.py`): launches the REAL `server_python/server.py` and connects two independent TCP/WebSocket clients: register/login, character creation, server-generated background, enter world, both see each other with correct names/appearance, bidirectional position sync, bounds clamping, invalid-input rejection, disconnect → `player_left`, reconnect → saved position/background, duplicate-session replacement, persistence after server restart. **29/29 PASSED.**
   **Caveat:** this sandbox had no network, so the real `websockets` package could not be installed. The test ran against a minimal stand-in WebSocket implementation (`tests/shim/`). Game logic is verified; the real library's transport is not. Run `python tests/run_integration.py` on your machine (it uses the real `websockets` automatically when installed).
3. `docs/preview_from_scene_data.png`: composite drawn **from the .tscn data by a Python script** to sanity-check geometry/alignment. **It is NOT a Godot screenshot.**

## NOT tested (environment limitation: no Godot binary here)
* Opening the project / loading any scene in Godot, GDScript compilation, runtime errors.
* Real rendering, camera behaviour, input, animation, UI layout, character preview.
* Godot client ↔ Python server over the real `websockets` library.
* Two real Godot clients showing each other. **No Godot screenshots exist; none were fabricated.**
Multiplayer in the Godot client is therefore **unverified**; only the server side is verified. Please run the steps in README and report any errors — see CONTINUATION.md §1 for the first things to check.

## Status
| Feature | Status |
|---|---|
| Server: auth, characters, background, persistence, spawn/position/leave broadcast | Verified by test (with stand-in ws) |
| Client character rendering, customization → appearance, preview | Implemented, untested in Godot |
| Camera, WASD/arrows movement, iso movement scaling, collisions | Implemented, untested in Godot |
| World scenes (ground, road, sidewalk, 4 buildings, props) | Implemented, static-validated + data preview |
| Remote players rendering/interpolation | Implemented, untested in Godot |
| HUD / reconnect flow | Implemented, untested in Godot |
| Entering buildings / interiors, stairs | Not implemented |
| Visual building-editor tooling | Not implemented (scenes are hand-editable) |
| Economy, jobs, politics, businesses | Not implemented (out of scope) |

## Known limitations
No client-side prediction/anti-speed-hack (server clamps to bounds only); one character per account; walking uses 2 mirrored views (no 4-direction sprites); passwords/traffic not encrypted (ws://, no TLS); JSON file storage.

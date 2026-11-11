# Project continuation notes

## 0. After M2 (gameplay restoration) — start here
* Open the project in Godot (4.3+) once so it imports the new art (`assets/art/interior`, `assets/art/furniture`) and check the Output panel.
  The client was run on the Godot 4.4.1 web runtime (see `tools/web_test/`), not in an editor.
* Next candidates: hosted build (wss + server address setting), decorate mode for rented/owned homes (the original v0.6 editor,
  server-validated), more buildings from the original list (Farmácia, Padaria, Escola, Oficina…) via `world.json`, NPCs driven by the
  server, consequences for health 0, stacked-floor view of interiors.
* Sections 1–2 below are from M1 and partly superseded: interiors, stairs, enterable doors, prop collisions, chat, logout UI and the
  spawn single-source-of-truth are now done.

## 1. First thing to do next session: get a real Godot run
This build was assembled WITHOUT a Godot binary. Expect possible small load/runtime errors. Checklist:
1. Open the project in Godot 4.3+; fix any parse errors shown in the Output panel (most likely candidates: hand-written `.tscn` properties in `client/scenes/World.tscn` HUD labels, `Player.tscn`, `Main.tscn` Preview node).
2. `python tools/validate_and_preview.py` after any scene edits.
3. Start server, run 2 Godot instances, run the README flow, take the 5 screenshots required by the original brief (customization, character in world, environment, two players, synced movement). **None exist yet.**
4. Run `python tests/run_integration.py` with the real `websockets` installed.

## 1b. Menu/onboarding build (latest) — verify in Godot
Read `docs/MENU_ONBOARDING_REPORT.md`. Likely first-run issues: `Main.gd` UI built in code (Theme/StyleBox properties), `World.tscn` showcase (`$UI.visible`, CanvasModulate, Camera2D), `Lamp.tscn` additive glow material, `Transition` autoload. Check scenarios A–E by hand: new account → intro → customize → world; quit and relaunch (session restore → straight to world); quit mid-intro and relaunch (resumes); stop the server mid-menu (overlay + auto-reconnect).

## 2. Left out / not done
* Menu/onboarding: logo is a placeholder; fonts are placeholders; intro text is placeholder copy; no password recovery; life-story reveal is only shown once (no profile screen to re-read it); ambient actors only in menu; no per-device multiple accounts UI; settings screen (server address) not built.
* Real Godot launch, screenshots, Godot↔server verification (see above).
* Building interiors, enterable doors, stairs, per-floor visibility (doors/stairs are visual only; the `Entrance` Marker2D is where interior transition should hook in).
* Your pack's monolithic building sprites are unused (kept in `assets/art/pack_original`). Options: use them as a `Facade` skin for a Building, or as decor. Furniture/NPC sprites unused.
* Corner pieces, back walls, wall-height variants, sloped/pitched roofs, awnings as separate components.
* Converting ground from per-tile `Sprite2D` instances to a `TileMapLayer` (better painting UX). Not done because the tile-data format could not be tested without Godot. Use `tools/generate_world.py` as the source of the current layout.
* Building editor tooling (snap grid, EditorPlugin) — buildings are plain scenes of instanced pieces; edit them directly.
* Character: hair color & clothing selection UI (server/data already support `hair_color`, `clothes`), 4-direction sprites, richer walk cycle.
* Prop collisions (trees/lamps/benches are walk-through).
* Spawn single source of truth: server `world_config.json` spawn must match `World.tscn` `SpawnPoint` (client uses the server's position). Same for bounds vs `WorldBounds` collision.
* Server: speed/anti-cheat validation, rate limiting, TLS (wss), SQLite instead of JSON, multiple characters per account, chat, NPC support.
* Client: character selection screen if multiple characters, logout button, settings UI for server address (currently CLI arg/env var).
* Economy, jobs, politics, businesses — intentionally not started.

## 3. Conventions
* Art: fixed file names in `assets/art/` (see `docs/ART_GUIDE.md`); appearance constants in `shared/scripts/Art.gd`.
* World coordinates: screen-space iso, tile 64x32, tile (c,r) top vertex = `((c-r)*32, (c+r)*16)`. Entity origin = feet/ground point. Entities are children of `World/Entities` (y-sorted).
* Movement: screen-space WASD/arrows, vertical speed scaled by 0.5 (iso foreshortening).
* Protocol (JSON over WebSocket): client→server `register, login, create_character, enter_world, position`; server→client `welcome, auth_response, character_created, spawn_player, position, player_left, error`.
* `tools/generate_world.py` is a one-shot bootstrap; re-running it OVERWRITES hand edits to World/buildings scenes.

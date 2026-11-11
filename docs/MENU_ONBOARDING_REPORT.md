# Main menu + onboarding + session restore — report

## Audit of what existed
* **No story/introduction existed.** The only narrative was the generated life background, shown after character creation **and again on every login** (returning players were forced through it).
* **No onboarding state.** The client decided the flow with `characters.is_empty()`.
* **No session persistence**; every launch required login. Login UI was a plain `Panel` on a flat `ColorRect`.
* Reused unchanged: account system, character creation, server background generator, character appearance data, `NetworkManager`/`GameState`, the world scenes, `CharacterVisual`.

## What was built
**Server (authoritative)** — `server_python/server.py`
* `account.onboarding = {state, story_step}` with states `new → story_in_progress → character_customization → completed`.
  Rules enforced by the server: steps never go backwards, `completed` can only be set by successful character creation, the story can't be skipped (customization requires the last step), `create_character` is rejected before customization state.
* **Migration, nothing reset:** accounts without the field become `completed` if they own a character, otherwise `new` (also self-heals).
* **Sessions:** login/register return a `session_token` (stored hashed server-side, 30-day TTL, `sessions.json`). New messages: `resume_session`, `logout`, `onboarding_progress`; replies `session_invalid`, `logged_out`, `onboarding_state`. Login/resume responses include `onboarding` and the saved `character`.
* Duplicate-entity protection from the previous milestone still applies (same character on a second connection replaces the old session).

**Client**
* `Main.tscn/Main.gd` rewritten: the menu background is the **real `World.tscn` in `showcase` mode** (same renderer, tiles, buildings, props; no network, no player), with a slow cinematic camera (independent of input), dusk tint, glowing streetlamps, ambient pedestrians and cars following **editable route markers** (`World/AmbientRoutes`). Dark overlay for readability. ~10 ambient actors only.
* Pixel UI theme (`client/scripts/UIStyle.gd`): dark translucent panels, thick square borders, gold primary button with normal/hover/pressed/disabled/loading states, field icons, focus highlight, server dot (green/amber/red). Matches the mockup layout. No glass/gradients.
* Flow: login → server decides → `completed` goes **straight to the world** (fade, no story, no customization, no confirmation) · `story_in_progress` resumes at the saved page · `character_customization` resumes at customization · `new` starts the introduction. After creating a character: one-time life-story reveal → world.
* Session restore on launch (token in `user://session.cfg`, validated by the server; the file is only a convenience). "Usar outra conta" escape. F10 in-world = log out (revokes token).
* Failure handling: 8 s request timeouts with retry; connection loss during onboarding shows an overlay and auto-reconnects (2 s loop) then re-resumes the session — server-side progress is never lost.
* Fade transitions (`Transition` autoload); the player only gets input after the world fade-in finishes.
* Branding: `config/branding.json` + `assets/art/ui/logo.png` (placeholder logo; replace the PNG). No script contains the game name.
* "Forgot password": **omitted** (the auth system has no recovery).

## Tests actually run
`python tests/run_integration.py` — real `server.py`, independent clients, **46/46 passed**, covering:
* A new player: `new` state, can't skip story, creation completes onboarding.
* B returning player: login returns `completed` + saved character/appearance/background; state never regresses.
* C interrupted onboarding: resumes at `story_in_progress` step 1, then `character_customization` after reconnect; step never goes backwards.
* D session: valid token restores full profile without password and enters world; logout revokes; invalid/forged token → `session_invalid`.
* Legacy-account migration without data loss.
* Plus all multiplayer/persistence checks from the previous milestone.
Caveat unchanged: run against a stand-in websocket library (no network in this sandbox).

## NOT tested (no Godot binary available)
Everything on the client: scene loading, GDScript compilation, menu rendering, showcase camera/ambient actors, theme look, transitions, session file read/write, scenario E UI behaviour (timeouts/overlay/reconnect). **No screenshots exist.** The scenarios A–E are verified at the protocol/server level only; the client logic implementing them is untested code.

## Known limitations
Placeholder logo/intro text/fonts (DejaVu Sans Mono Bold); ambient actors are client-side visuals only (not synced); intro text is new placeholder copy since no story existed; ambient actors/lamp glow do not yet exist in gameplay; `config/branding.json` and `client/data/*.json` must be included in export filters when exporting builds.

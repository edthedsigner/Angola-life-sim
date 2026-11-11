# Original (simulador-vida v0.6) vs current (Angola Life Simulator M1) — inventory

Written **before** any change, from reading both codebases in full
(original: `scripts/main.gd` 2,639 lines + `scripts/building_defs.gd`; current: all scripts, scenes, server, tests).
The original is a single-player prototype drawn entirely with `_draw()`; the current project is a scene-based
multiplayer client with an authoritative Python server.

| Area | Original project | Current project (before this work) | Action |
|---|---|---|---|
| Building structures | Data-driven defs: per-floor `w×l`, wall segments per grid edge (`h:x:y`/`v:x:y`), doors, windows, stairs. 1-floor house with 2 rooms, 2-floor shop with different layouts per floor, 3-floor office with a shorter top floor (terrace). Interior cell = ½ world tile. | 4 exterior-only shells (1–3 floors of facade sprites + roof). No interiors, rooms or stairs. Doors are pictures. | **Restore** the architecture as JSON definitions (same edge-key format) built with the current wall pieces. |
| Wall construction | Polygons drawn per frame, autotiled posts, thickness/material editor. | `WallPieceL/R` sprite scenes per tile edge, textures per kind (plain/window/door/shop). | **Preserve current.** Interiors instance the same `WallPieceL/R` scenes. |
| Floor tiling | Per-tile texture `ground`/`ground_b` checkerboard, `road`, `plaza`; interior `floor.png` with alternating tint, a darker door mat at the exit, stair holes on upper floors, faint grid lines when untextured. | Exterior per-tile sprites: grass/grass_b pseudo-random (less repetitive than a checkerboard), road with lane markings, sidewalks. No interiors. | **Keep current exterior tiling**; **adopt original interior tiling** (pack `floor.png`, alternating tint, door mat, stair hole). |
| Click-to-move | A* (world) / BFS with edge blocking (interiors), line-of-sight path smoothing, target marker, hover highlight. | Missing (WASD only). | **Restore**, one nav system for mouse and touch, also used by interactions. |
| Building navigation | Click a building → walk to its door; `E`/button enters. | Missing; `Entrance` markers unused. | **Restore** with multiple entrances and server-validated entry. |
| Interior navigation | Floors, stair walking, floor picker buttons (auto-path to stairs), doors open/close (closed blocks path), windows open/close (visual). | None. | **Restore** floors, stairs, floor picker, doors (synced). Window toggling: not restored (purely visual). |
| Zoom / camera | Wheel, `+`/`-`, pinch, on-screen buttons. | Fixed zoom 2. | **Restore** (essential on mobile). |
| Phone | Overlay phone with clock, 6 apps: Banco (balance), Mensagens (own chat log), Emprego/Imóveis/Negócios/Governo = "Em breve". | None. | **Restore** all 6 apps; Banco/Mensagens with real server data, Emprego/Imóveis wired to the new activity system, Governo shows the character's ID/life story, Negócios stays "Em breve" (as in the original). |
| Character interactions | Local speech bubbles from a chat field; NPCs say random lines. | Players see each other; nearby names list in HUD. | **Restore chat as multiplayer chat** (server-relayed, proximity, bubbles, log). |
| NPCs | 10 wandering NPCs (local only). | Ambient walkers/cars only in the menu showcase. | Not restored in gameplay: client-only NPCs would differ per client. Kept as menu ambience. |
| Furniture & objects | Decorate mode: 6 furniture types (pack sprites), place/rotate/move/remove, saved locally. No furniture *interactions*. | None (pack furniture unused). | **Furniture restored** as building-defined objects with **interactions** (sleep, cook, shower, buy, sell, work, rest). Decorate/architecture editor **deferred**: in multiplayer it needs property ownership (players start homeless). |
| Inventory | None. | Server field `inventory: []`, unused. | **Implement** (server-owned items, buy/eat/sell). |
| Needs / status | Hunger + energy decaying, no way to restore them; local clock (Day N HH:MM, 4× speed); money Kz 25,000. | Money only (server). | **Restore + complete**: server clock, hunger/energy/hygiene/health decaying server-side, restored by activities. |
| Activities | None. | None. | **New, data-driven** per building type (spec §6). |
| Player HUD | Light top bar: location, clock, money, hunger/energy bars; hints; enter prompt. | Debug panel: connection, player count, pixel position, money, nearby names. | **Redesign** (player-facing only). |
| Debug interface | None. | Mixed into HUD. | **New F3 overlay**, sectioned and extensible. |
| Save / persistence | Local `user://save.cfg`. | Server JSON (accounts, characters, sessions). | Server stays the source of truth; all restored state is server-side. |
| Multiplayer | None. | Auth, onboarding, sessions, spawn/position sync, duplicate-session replacement. | **Preserve**; add zones, validated movement, validated interactions. |
| Menu / onboarding | Name field + Começar/Continuar. | Full login/register/story/customization flow over a live world. | Keep current. |
| Architecture editor (walls/doors/stairs in-game) | v0.6 in-game editor. | Walls edited as scenes in the Godot editor. | Not restored: the brief says keep the newer wall system; editing is via data + scenes. |

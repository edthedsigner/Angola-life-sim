# Angola Life Simulator — M2 (gameplay restoration)

Persistent multiplayer life sim set in Luanda. Godot 4.3+ client, Python authoritative WebSocket server.
**Latest work: `docs/RESTORATION_REPORT.md`** (what was restored from the original prototype, how, what was tested — with real
in-engine screenshots in `docs/screenshots/`). Comparison of both projects: `docs/COMPARISON.md`. Adding buildings/activities: `docs/BUILDINGS.md`.

## Run

### 1. Server (Python 3.10+)
```bash
cd server_python
pip install -r requirements.txt
python server.py            # ws://0.0.0.0:7777   (override: ANGOLA_HOST / ANGOLA_PORT)
```
Data is saved in `server_python/data/` (accounts.json, characters.json). Delete that folder to reset the world.

### 2. Client (Godot 4.3+)
Open the project folder in Godot, press **F5**. The project uses the **GL Compatibility** renderer (works on old GPUs / VMs).

**Two clients on one PC:** Godot editor → *Debug → Customize Run Instances…* → enable 2 instances → F5.
Or from a terminal run the project twice: `godot --path . ` (two terminals).

**Server on another machine:** `godot --path . -- --server=192.168.1.20:7777` (or env var `ANGOLA_SERVER=host:port`).
The client auto-retries the connection every 2 s until the server is up.

### 3. Play
Register → introduction → create character → life story → world.

| Action | Mouse / touch | Keyboard |
|---|---|---|
| Walk | click / tap the ground | WASD / arrows |
| Go to a building and enter | click / tap the building | walk to the door, `E` |
| Use furniture (buy, cook, sleep, work…) | click / tap it → menu | `E` next to it |
| Doors, stairs, exit | click / tap them, or the floor buttons (left) | `E` |
| Zoom | pinch, wheel, `+`/`−` buttons | `+` / `-` |
| Chat · Backpack · Phone | dock buttons (bottom right) | `Enter`/`T` · `I` · `Tab` |
| Debug info | Telemóvel → Definições | **F3** |
| Log out | Telemóvel → Definições | F10 |

You start homeless (life story): rent a room in the **Imóveis** app to use the Casa Mussulo, get a job in **Emprego**,
buy food at the Mercearia. Hunger/energy/hygiene/health run on the server.

## Game flow
Launch → live-world main menu → login/register → **server decides**: new/in-progress account → introduction → character → life story → world; completed account → straight into the world. A valid saved session skips the login screen. F10 in the world logs out. Branding: edit `config/branding.json` and replace `assets/art/ui/logo.png`.

## Project layout
```
shared/data/world.json            map, buildings (floors/rooms/walls/doors/stairs/entrances), furniture, activities, economy
shared/scripts/WorldData.gd       client mirror of the server's world rules + pathfinding (autoload)
client/scripts/InteriorBuilder.gd interiors from data using the same WallPieceL/R pieces as exteriors
client/scripts/Hud.gd, Phone.gd   player HUD and phone;  DebugOverlay.gd = F3 (independent)
server_python/world.py, game.py   geometry/validation and gameplay rules (needs, economy, activities)
tools/web_test/                   run the real client in a browser against the real server (test harness)
```
Older layout notes:
```
client/scenes/World.tscn          the level (open it in Godot and move/replace things)
client/scenes/buildings/*.tscn    modular buildings: Walls/ Roof/ Body(collision)/ Entrance/ SignLabel
client/scenes/components/*.tscn   reusable pieces: WallPieceL/R, RoofPiece, GroundTile, Tree, Lamp, Bench, Bush
client/scenes/Player.tscn, CharacterVisual.tscn   layered character (legs/body-skin/shirt/hair)
client/scripts/                   Main (menus), World (HUD+spawning), Player, CharacterVisual, Building
shared/scripts/                   NetworkManager, GameState, Art (central art/appearance registry)
server_python/                    server.py + world_config.json (spawn, bounds)
assets/art/                       ALL textures (see docs/ART_GUIDE.md)
tools/                            bootstrap generators + validator (not needed at runtime)
tests/run_integration.py          two-client integration test against the real server.py
```

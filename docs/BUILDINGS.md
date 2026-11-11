# Adding buildings, rooms and activities

Everything lives in `shared/data/world.json`. Client, server and the scene generator all read it.

## A building
```json
{"id": "casa", "name": "Casa Mussulo", "type": "residential", "scene": "Casa.tscn", "palette": "pink", "shopfront": false,
 "c0": -6, "r0": -6, "w": 3, "d": 4,
 "entrances": [{"id": "frente", "face": "front", "i": 1, "edge": "h:2:8"}],
 "floors": [ {"w": 6, "l": 8, "name": "Rés-do-chão", "walls": [...], "openings": [...], "rooms": [...], "furniture": [...]} ],
 "stairs": []}
```
* `c0, r0, w, d` — footprint on the street grid (tiles). Exterior shell = `tools/generate_world.py`.
* `entrances` — `face: "front"` (the street-facing left face, tile `(c0+i, r0+d)`) or `"side"` (right face, tile `(c0+w, r0+i)`);
  `edge` is the matching perimeter edge inside floor 0. Several entrances are allowed; the client picks the closest reachable one.
* `floors[n]` — size in interior cells (convention: interior = 2 × footprint). The outer perimeter is automatic.
  * `walls`: `["h", y, x1, x2]` horizontal wall at row line `y` from `x1` to `x2`; `["v", x, y1, y2]` vertical.
  * `openings`: `["h"|"v", x, y, "door"|"window"]` — replaces one wall edge (`h:x:y` = edge (x,y)-(x+1,y); `v:x:y` = (x,y)-(x,y+1)).
  * `rooms`: optional names (documentation / future use).
  * `furniture`: `{"id": "cama", "x": 0, "y": 0, "r": 0, "actions": ["sleep"]}` — `r: 1` rotates (uses `<tex>_r.png` if present).
* `stairs`: `{"lo": 0, "x": 0, "y": 3, "len": 2}` — base cell (x,y) on floor `lo`, ramp going north (y−1 … y−len), landing (x, y−len−1) on `lo+1`.

After editing: run `python3 tools/generate_world.py` (exterior scenes + world), then start the server — it refuses to start
and lists the problem if a floor is not fully connected, furniture overlaps, a piece is not allowed for that building type, etc.

## Building types and furniture restrictions
`building_types.<type>.furniture` lists which furniture may be placed; `private: true` means entering requires renting it (`rentals`).

## Activities
```json
"cook": {"label": "Cozinhar", "secs": 5, "consumes": "ingredientes", "effects": {"hunger": 45}, "requires": "housing", "status": "A cozinhar"}
```
* Timed: `secs`, `effects` on needs (`hunger`, `energy`, `hygiene`, `health`; negative = cost), optional `cost` (Kz), `consumes` (item id),
  `requires`: `"housing"` (rented home) or `"job"` (a job whose `building` is this one; pays `jobs.<id>.pay` per shift).
* Shops: `"shop": ["pao", "agua"]` opens a buy list; `"sell"` buys back items with a `sell` price.
* Attach an activity by adding its id to a furniture piece's `actions` (or to `prop_rules` for street props).
Rules are in `server_python/game.py`; the client only displays them.

# In-browser test harness (no Godot editor needed)

Used to run the real client (Godot 4.4 web runtime) against the real server and take screenshots.
It is a **test tool**, not a replacement for exporting from the Godot editor.

1. Get a Godot 4.4.x *Web* export template build (`index.html/.js/.wasm`, thread support off) and put it in a folder, e.g. `web/`.
2. `python3 build_pck.py <project> web/index.pck` — packs scripts/scenes as text and PNGs as `.import` + `.ctex`.
3. `python3 -m http.server 8060` inside `web/`; start `server_python/server.py` (port 7777).
4. `python3 seed.py <shim-or-site-packages> <user> "<Name>"` creates an account with a character.
5. `node run.js http://localhost:8060/index.html out.png 10 actions.json` (Playwright). `run2.js` = two clients, `runm.js` = phone (390×844, touch).
   `scen.py` turns world cells into click coordinates (camera = player + (0,-20), zoom 2, 1280×720).

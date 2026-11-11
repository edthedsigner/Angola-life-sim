"""Builds Playwright action lists with clicks on world cells (camera = player + (0,-20), zoom 2, 1280x720)."""
import json, sys
sys.path.insert(0, sys.argv[1] + "/server_python")
import world as wm
W = wm.load(sys.argv[1] + "/shared/data/world.json")
S = sys.argv[2]
chars = json.load(open(S + "/srvdata/data/characters.json"))
class Sc:
    def __init__(s, user, name):
        ch = next(c for c in chars.values() if c["name"] == name)
        s.zone = ch.get("zone", "w"); s.px = (ch["position"]["x"], ch["position"]["y"]); s.acts = []
        s.acts += [{"wait": 2500}, {"click": [640, 359]}, {"type": user}, {"click": [640, 411]}, {"type": "pw1234"}, {"key": "Enter"}, {"wait": 5500}]
    def scr(s, x, y): return [round(640 + (x - s.px[0]) * 2), round(360 + (y - s.px[1] + 20) * 2)]
    def click_cell(s, c, r, wait=5000, dy=0, end=None):
        x, y = W.cell_center(s.zone, c, r); p = s.scr(x, y + dy); s.acts += [{"click": p}, {"wait": wait}]
        if end: s.px = W.cell_center(s.zone, *end)
        return p
    def at(s, zone, c, r): s.zone = zone; s.px = W.cell_center(zone, c, r)
    def click(s, x, y, wait=900): s.acts += [{"click": [x, y]}, {"wait": wait}]
    def key(s, k, wait=600): s.acts += [{"key": k}, {"wait": wait}]
    def shot(s, n): s.acts.append({"shot": f"{S}/{n}.png"})
    def wait(s, ms): s.acts.append({"wait": ms})
    def save(s, f): json.dump(s.acts, open(f, "w")); print("player", s.zone, s.px)
def click_cs(s, u, v, dy=0, wait=4000):
    ox, oy = W.origin(s.zone); p = s.scr(ox + (u - v) * 32, oy + (u + v) * 16 + dy); s.acts += [{"click": p}, {"wait": wait}]
Sc.click_cs = click_cs
def hold(s, k, ms): s.acts += [{"down": k}, {"wait": ms}, {"up": k}, {"wait": 400}]
Sc.hold = hold
def walk_to(s, c, r, step=5):
    import math
    u, v = W.to_cell_space(s.zone, *s.px)
    n = max(1, math.ceil(max(abs(c + 0.5 - u), abs(r + 0.5 - v)) / step))
    for k in range(1, n + 1):
        tc = (round(u + (c + 0.5 - u) * k / n - 0.5), round(v + (r + 0.5 - v) * k / n - 0.5))
        x, y = W.cell_center(s.zone, *tc); p = s.scr(x, y)
        s.acts += [{"click": p}, {"wait": 2600}]; s.px = (x, y)
Sc.walk_to = walk_to

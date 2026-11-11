#!/usr/bin/env python3
"""Ferramenta de BOOTSTRAP: escreve as cenas .tscn iniciais (componentes, edificios, mundo).
Depois de gerado, o mundo edita-se no editor Godot; este script NAO e usado em runtime.
Projecao iso: tile 64x32; ecra(c,r) = ((c-r)*32, (c+r)*16)."""
from pathlib import Path
import json
R = Path(__file__).resolve().parent.parent
DATA = json.loads((R / "shared" / "data" / "world.json").read_text(encoding="utf-8"))   # fonte única do mapa
SC = R / "client" / "scenes"; (SC / "components").mkdir(parents=True, exist_ok=True); (SC / "buildings").mkdir(exist_ok=True)
A = "res://assets/art/"; S = "res://client/scenes/"

class Scene:
    def __init__(self): self.ext = {}; self.sub = []; self.nodes = []
    def res(self, typ, path):
        if path not in self.ext: self.ext[path] = (len(self.ext) + 1, typ)
        return f'ExtResource("{self.ext[path][0]}")'
    def node(self, name, typ=None, parent=None, inst=None, **props):
        h = f'[node name="{name}"'
        if typ: h += f' type="{typ}"'
        if parent is not None: h += f' parent="{parent}"'
        if inst: h += f' instance={self.res("PackedScene", inst)}'
        h += "]"
        self.nodes.append(h + "".join(f"\n{k} = {v}" for k, v in props.items()))
    def subres(self, typ, **props):
        sid = f"{typ}_{len(self.sub)+1}"; self.sub.append((sid, typ, props)); return f'SubResource("{sid}")'
    def text(self):
        out = [f"[gd_scene load_steps={len(self.ext)+len(self.sub)+1} format=3]\n"]
        for p, (i, t) in self.ext.items(): out.append(f'[ext_resource type="{t}" path="{p}" id="{i}"]')
        out.append("")
        for sid, t, pr in self.sub:
            out.append(f'[sub_resource type="{t}" id="{sid}"]' + "".join(f"\n{k} = {v}" for k, v in pr.items())); out.append("")
        return "\n".join(out) + "\n" + "\n\n".join(self.nodes) + "\n"
    def save(self, p): Path(p).write_text(self.text())
def V(x, y): return f"Vector2({x}, {y})"

# ------------------------------------------------------------- componentes reutilizaveis
def sprite_comp(fname, tex, offset):
    s = Scene(); s.node("Piece", "Sprite2D", texture=s.res("Texture2D", A + tex), centered="false", offset=V(*offset)); s.save(SC / "components" / fname)
sprite_comp("GroundTile.tscn", "tiles/grass.png", (-32, 0))
sprite_comp("WallPieceL.tscn", "buildings/pink_wall_l_plain.png", (0, -48))
sprite_comp("WallPieceR.tscn", "buildings/pink_wall_r_plain.png", (0, -64))
sprite_comp("RoofPiece.tscn", "buildings/pink_roof.png", (-32, 0))
for n, f, off in (("Tree", "tree", (-24, -70)), ("Lamp", "lamp", (-8, -62)), ("Bench", "bench", (-20, -26)), ("Bush", "bush", (-16, -22))):
    sprite_comp(f"{n}.tscn", f"props/{f}.png", off)
# candeeiro com brilho (aditivo)
s_ = Scene(); s_.node("Lamp", "Sprite2D", texture=s_.res("Texture2D", A + "props/lamp.png"), centered="false", offset=V(-8, -62))
s_.node("Glow", "Sprite2D", parent=".", texture=s_.res("Texture2D", A + "props/glow.png"), position=V(0, -56), modulate="Color(1, 1, 1, 0.6)",
        material=s_.subres("CanvasItemMaterial", blend_mode=1))
s_.save(SC / "components" / "Lamp.tscn")
# ambiente
s_ = Scene(); s_.node("AmbientWalker", "Node2D", script=s_.res("Script", "res://client/scripts/AmbientWalker.gd")); s_.node("Visual", parent=".", inst=S + "CharacterVisual.tscn"); s_.save(SC / "ambient" / "AmbientWalker.tscn")
s_ = Scene(); s_.node("AmbientCar", "Node2D", script=s_.res("Script", "res://client/scripts/AmbientCar.gd"))
s_.node("Body", "Sprite2D", parent=".", texture=s_.res("Texture2D", A + "props/car_red_dr.png"), centered="false", offset=V(-56, -44)); s_.save(SC / "ambient" / "AmbientCar.tscn")
C = S + "components/"

# ------------------------------------------------------------- edificios modulares
def sc_of(c0, W, r0, D): return ((c0 + W - (r0 + D)) * 32, (c0 + W + r0 + D) * 16)
def building(fname, title, W, D, floors, pal, entrances, shopfront, bid, label):
    # Origem do nó = ponto de ordenação (y-sort) do edifício: min(y da esquina esquerda, y da direita) + 8.
    # Com |W-D| <= 1, quem está à frente de qualquer fachada fica por cima e quem está atrás fica por baixo
    # (antes a origem era a esquina da frente, o que escondia o jogador à porta).
    SY = min(-W * 16, -D * 16) + 8
    def P(x, y): return V(x, y - SY)
    s = Scene(); sp = s.res("Script", "res://client/scripts/Building.gd")
    s.node(title, "Node2D", script=sp, building_id=f'"{bid}"', building_name=f'"{label}"', floors=floors, footprint_w=W, footprint_d=D)
    s.node("Walls", "Node2D", parent=".")
    front_doors = {e["i"] for e in entrances if e["face"] == "front"}
    side_doors = {D - 1 - e["i"] for e in entrances if e["face"] == "side"}   # R{f}_j: j=0 é a peça mais à frente
    for f in range(floors):
        for i in range(W):                                    # face esquerda (virada a +r, para a rua)
            kind = "plain"
            if f == 0: kind = "door" if i in front_doors else ("shop" if shopfront else "window")
            else: kind = "window"
            tex = A + f"buildings/{pal}_wall_l_{kind}.png"
            s.node(f"L{f}_{i}", parent="Walls", inst=C + "WallPieceL.tscn", position=P(-(W - i) * 32, -(W - i) * 16 - 48 * f), texture=s.res("Texture2D", tex))
        for j in range(D):                                    # face direita (virada a +c)
            kind = "window" if (f > 0 or j % 2 == 0) else "plain"
            if f == 0 and j in side_doors: kind = "door"
            tex = A + f"buildings/{pal}_wall_r_{kind}.png"
            s.node(f"R{f}_{j}", parent="Walls", inst=C + "WallPieceR.tscn", position=P(j * 32, -j * 16 - 48 * f), texture=s.res("Texture2D", tex))
    s.node("Roof", "Node2D", parent=".")
    nx, ny = (D - W) * 32, -(W + D) * 16 - 48 * floors
    for k in range(W + D - 1):
        for i in range(W):
            j = k - i
            if 0 <= j < D:
                s.node(f"Roof_{i}_{j}", parent="Roof", inst=C + "RoofPiece.tscn", position=P(nx + (i - j) * 32, ny + (i + j) * 16), texture=s.res("Texture2D", A + f"buildings/{pal}_roof.png"))
    s.node("Body", "StaticBody2D", parent=".")
    poly = f"PackedVector2Array({(D-W)*32}, {-(W+D)*16 - SY}, {D*32}, {-D*16 - SY}, 0, {-SY}, {-W*32}, {-W*16 - SY})"
    s.node("Footprint", "CollisionPolygon2D", parent="Body", polygon=poly)
    for e in entrances:                                       # centro do tile exterior à porta (onde o jogador fica para entrar)
        # origem do edifício = vértice (c0+W, r0+D); centro do tile exterior = ponto (tile + 0.5)
        dc, dr_ = (e["i"] - W + 0.5, 0.5) if e["face"] == "front" else (0.5, e["i"] - D + 0.5)
        s.node(f"Entrance_{e['id']}", "Marker2D", parent=".", position=P(int((dc - dr_) * 32), int((dc + dr_) * 16)))
    s.node("SignLabel", "Label", parent=".", offset_left=-110, offset_right=110, offset_top=-(W * 16 + 48 * floors) + 8 - 30 - SY, offset_bottom=-(W * 16 + 48 * floors) - 6 - SY,
           horizontal_alignment=1, text=f'"{label}"', **{"theme_override_font_sizes/font_size": 10, "theme_override_constants/outline_size": 3, "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)"})
    s.save(SC / "buildings" / fname)
BUILDINGS = [(b["scene"][:-5], b["scene"], b["c0"], b["w"], b["r0"], b["d"], len(b["floors"]), b["palette"], b["entrances"], b["shopfront"], b["id"], b["name"])
             for b in DATA["buildings"]]
for t, f, c0, W, r0, D, fl, pal, ents, shop, bid, label in BUILDINGS: building(f, t, W, D, fl, pal, ents, shop, bid, label)

# ------------------------------------------------------------- personagem
s = Scene(); s.node("CharacterVisual", "Node2D", script=s.res("Script", "res://client/scripts/CharacterVisual.gd"))
s.node("Shadow", "Sprite2D", parent=".", texture=s.res("Texture2D", A + "characters/shadow.png"), centered="false", offset=V(-12, -5))
for n, f in (("Legs", "legs"), ("Body", "body"), ("Shirt", "shirt")):
    s.node(n, "Sprite2D", parent=".", texture=s.res("Texture2D", A + f"characters/{f}.png"), centered="false", offset=V(-12, -40), hframes=4)
s.node("Hair", "Sprite2D", parent=".", texture=s.res("Texture2D", A + "characters/hair_0.png"), centered="false", offset=V(-12, -40))
s.save(SC / "CharacterVisual.tscn")

s = Scene(); s.node("Player", "CharacterBody2D", script=s.res("Script", "res://client/scripts/Player.gd"))
shape = s.subres("RectangleShape2D", size="Vector2(14, 8)")
s.node("CollisionShape2D", "CollisionShape2D", parent=".", position=V(0, -4), shape=shape)
s.node("Visual", parent=".", inst=S + "CharacterVisual.tscn")
s.node("NameLabel", "Label", parent=".", offset_left=-70, offset_right=70, offset_top=-60, offset_bottom=-46, horizontal_alignment=1, text='"Jogador"',
       **{"theme_override_font_sizes/font_size": 10, "theme_override_constants/outline_size": 4, "theme_override_colors/font_outline_color": "Color(0, 0, 0, 1)"})
s.node("Camera2D", "Camera2D", parent=".", position=V(0, -20), zoom=V(2, 2), position_smoothing_enabled="true", position_smoothing_speed=10.0)
s.save(SC / "Player.tscn")

# ------------------------------------------------------------- mundo
G = DATA["grid"]; CMIN, CMAX, RMIN, RMAX = G["cmin"], G["cmax"], G["rmin"], G["rmax"]
def tile_kind(c, r):
    if 0 <= c <= 2 and r <= -1 and r >= RMIN: return "road_line_r" if c == 1 and r < -1 else "road"
    if 0 <= r <= 2: return "road_line_c" if r == 1 else "road"
    if r in (-1, 3) or (c in (-1, 3) and RMIN <= r <= -2): return "sidewalk"
    return "grass_b" if (c * 7 + r * 13) % 5 == 0 else "grass"
def top(c, r): return ((c - r) * 32, (c + r) * 16)
def ctr(c, r): x, y = top(c, r); return (x, y + 16)

s = Scene(); s.node("World", "Node2D", script=s.res("Script", "res://client/scripts/World.gd"))
s.node("Ground", "Node2D", parent=".")
groups = {"Grass": ("grass", "grass_b"), "Sidewalk": ("sidewalk",), "Road": ("road", "road_line_c", "road_line_r")}
for g in groups: s.node(g, "Node2D", parent="Ground")
for r in range(RMIN, RMAX + 1):
    for c in range(CMIN, CMAX + 1):
        k = tile_kind(c, r); g = next(n for n, ks in groups.items() if k in ks); x, y = top(c, r)
        s.node(f"T_{c}_{r}".replace("-", "m"), parent=f"Ground/{g}", inst=C + "GroundTile.tscn", position=V(x, y), texture=s.res("Texture2D", A + f"tiles/{k}.png"))
s.node("Entities", "Node2D", y_sort_enabled="true")
s.nodes[-1] = s.nodes[-1].replace('type="Node2D"', 'type="Node2D" parent="."', 1)
s.node("Buildings", "Node2D", parent="Entities", y_sort_enabled="true")
for t, f, c0, W, r0, D, fl, pal, ents, shop, bid, label in BUILDINGS:
    x, y = sc_of(c0, W, r0, D); s.node(t, parent="Entities", inst=S + "buildings/" + f, position=V(x, y + min(-W * 16, -D * 16) + 8))
PROPS = [(k.capitalize(), c, r) for k, c, r in DATA["props"]]   # índice i => id "p{i}" (igual ao servidor)
for i, (kind, c, r) in enumerate(PROPS):
    x, y = ctr(c, r); s.node(f"{kind}{i}", parent="Entities", inst=C + f"{kind}.tscn", position=V(x, y))
s.node("AmbientRoutes", "Node2D", parent=".")
def route(name, pts):
    s.node(name, "Node2D", parent="AmbientRoutes")
    for i, (x, y) in enumerate(pts): s.node(f"P{i}", "Marker2D", parent=f"AmbientRoutes/{name}", position=V(x, y))
route("WalkA", [ctr(-11, -1), ctr(10, -1)]); route("WalkB", [ctr(10, 3), ctr(-11, 3)]); route("WalkC", [ctr(-1, -9), ctr(-1, -2), ctr(8, -1)])
route("CarA", [ctr(-11, 2), ctr(11, 2)]); route("CarB", [ctr(11, 0), ctr(-11, 0)])
s.node("SpawnPoint", "Marker2D", parent=".", position=V(DATA["spawn"]["x"], DATA["spawn"]["y"]))
s.node("WorldBounds", "StaticBody2D", parent=".")
N, E, Sx, W_ = (-64, -352), (736, 48), (128, 352), (-672, -48)
for i, (a, b) in enumerate(((N, E), (E, Sx), (Sx, W_), (W_, N))):
    s.node(f"Edge{i}", "CollisionShape2D", parent="WorldBounds", shape=s.subres("SegmentShape2D", a=V(*a), b=V(*b)))
# HUD do jogador e overlay de debug (F3) são construídos em código: client/scripts/Hud.gd e DebugOverlay.gd
s.save(SC / "World.tscn")
print("cenas geradas; tiles:", (CMAX - CMIN + 1) * (RMAX - RMIN + 1))

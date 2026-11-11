#!/usr/bin/env python3
"""1) Valida estaticamente os .tscn (ext_resource existem, ids resolvem, pais existem).
2) Desenha uma PRE-VISUALIZACAO aproximada (NAO e uma captura do Godot) a partir dos dados das cenas -> docs/preview_from_scene_data.png"""
import re, sys
from pathlib import Path
from PIL import Image
R = Path(__file__).resolve().parent.parent
def res(p): return R / p.replace("res://", "")
def parse(path):
    txt = path.read_text(); ext = {}; nodes = []
    for m in re.finditer(r'\[ext_resource type="(\w+)" path="([^"]+)" id="([^"]+)"\]', txt): ext[m.group(3)] = (m.group(1), m.group(2))
    for blk in re.split(r'\n(?=\[node )', txt):
        m = re.match(r'\[node name="([^"]+)"(?: type="(\w+)")?(?: parent="([^"]*)")?(?: instance=ExtResource\("([^"]+)"\))?\]', blk)
        if not m: continue
        props = dict(re.findall(r'^(\w+) = (.+)$', blk, re.M)); nodes.append(dict(name=m.group(1), type=m.group(2), parent=m.group(3), inst=m.group(4), props=props))
    return ext, nodes
errors = []
for f in sorted(R.glob("client/scenes/**/*.tscn")):
    ext, nodes = parse(f)
    for i, (t, p) in ext.items():
        if not res(p).exists(): errors.append(f"{f.name}: falta {p}")
    names = {"."}; 
    for n in nodes:
        if n["parent"] is None: names.add(n["name"]); root = n["name"]; continue
        par = n["parent"]
        if par != "." and par not in names: errors.append(f"{f.name}: pai '{par}' inexistente para {n['name']}")
        names.add(n["name"] if par == "." else f"{par}/{n['name']}")
        for k, v in n["props"].items():
            m = re.search(r'ExtResource\("([^"]+)"\)', v)
            if m and m.group(1) not in ext: errors.append(f"{f.name}: id {m.group(1)} sem ext_resource")
for g in R.glob("**/*.gd"):
    for p in re.findall(r'res://[\w/\.]+', g.read_text()):
        if p.endswith(('_', '/')) : continue
        if not res(p).exists(): errors.append(f"{g.name}: falta {p}")
print("ERROS:" if errors else "Validação estática OK", *errors[:30], sep="\n")

# ---- preview
def offset_of(scene_path):
    ext, nodes = parse(res(scene_path)); n = nodes[0]; o = re.findall(r'-?\d+', n["props"].get("offset", "Vector2(0, 0)").replace("Vector2", "")); return int(o[0]), int(o[1]), ext, n
def vec(s): a = re.findall(r'-?\d+\.?\d*', s.replace("Vector2", "")); return float(a[0]), float(a[1])
items = []  # (sort_y, img, x, y)
def walk(scene_path, base=(0, 0), tex_override=None, top=True):
    ext, nodes = parse(res(scene_path)); out = []
    order = []
    for n in nodes:
        pos = vec(n["props"]["position"]) if "position" in n["props"] else (0, 0)
        tex = None
        if "texture" in n["props"]:
            m = re.search(r'ExtResource\("([^"]+)"\)', n["props"]["texture"]); tex = ext[m.group(1)][1]
        if n["inst"]:
            sp = ext[n["inst"]][1]
            if "/components/" in sp:
                ox, oy, e2, n2 = offset_of(sp); t = tex
                if t is None:
                    m = re.search(r'ExtResource\("([^"]+)"\)', n2["props"]["texture"]); t = e2[m.group(1)][1]
                order.append(("sprite", n, pos, t, (ox, oy)))
            else: order.append(("scene", n, pos, sp, None))
    return order
def render():
    ext, nodes = parse(R / "client/scenes/World.tscn")
    W, H = 1600, 900; ox, oy = 500, 460; canvas = Image.new("RGBA", (W, H), (26, 33, 26, 255))
    def paste(tex, x, y, off):
        im = Image.open(res(tex)).convert("RGBA"); canvas.alpha_composite(im, (int(ox + x + off[0]), int(oy + y + off[1])))
    ground, ents = [], []
    for n in nodes:
        pos = vec(n["props"]["position"]) if "position" in n["props"] else (0, 0)
        if n["inst"]:
            sp = ext[n["inst"]][1]
            if "GroundTile" in sp:
                m = re.search(r'ExtResource\("([^"]+)"\)', n["props"]["texture"]); ground.append((pos, ext[m.group(1)][1]))
            elif "/buildings/" in sp: ents.append((pos[1], "b", pos, sp))
            else:
                ox2, oy2, e2, n2 = offset_of(sp); m = re.search(r'ExtResource\("([^"]+)"\)', n2["props"]["texture"]); ents.append((pos[1], "p", pos, (e2[m.group(1)][1], (ox2, oy2))))
    for pos, tex in sorted(ground, key=lambda g: g[0][1]): paste(tex, pos[0], pos[1], (-32, 0))
    for sy, kind, pos, data in sorted(ents):
        if kind == "p": paste(data[0], pos[0], pos[1], data[1])
        else:
            for typ, n, p, t, off in walk(data):
                paste(t, pos[0] + p[0], pos[1] + p[1], off)
    # personagens de exemplo (skin 2 / hair 3 e skin 0 / hair 1) a partir das camadas
    def char(x, y, skin, hair, shirt):
        from importlib import util
        cols = [(0.93,0.76,0.62),(0.76,0.54,0.38),(0.55,0.36,0.24),(0.34,0.22,0.15)]; shc=[(0.85,0.3,0.25),(0.25,0.55,0.85),(0.3,0.7,0.4),(0.9,0.8,0.3)]
        def tint(im, c): px = im.load(); 
        def tinted(im, c):
            r, g, b, a = im.split(); return Image.merge("RGBA", (r.point(lambda v: int(v*c[0])), g.point(lambda v: int(v*c[1])), b.point(lambda v: int(v*c[2])), a))
        d = R / "assets/art/characters"
        legs = Image.open(d/"legs.png").convert("RGBA").crop((0,0,24,40)); body = tinted(Image.open(d/"body.png").convert("RGBA").crop((0,0,24,40)), cols[skin])
        sh = tinted(Image.open(d/"shirt.png").convert("RGBA").crop((0,0,24,40)), shc[shirt]); hr = tinted(Image.open(d/f"hair_{hair}.png").convert("RGBA"), (0.07,0.05,0.05))
        for l in (legs, body, sh, hr): canvas.alpha_composite(l, (int(ox+x-12), int(oy+y-40)))
    char(0, 40, 2, 3, 1); char(70, 52, 0, 1, 2)
    canvas.save(R / "docs/preview_from_scene_data.png"); print("preview ->", R / "docs/preview_from_scene_data.png")
(R / "docs").mkdir(exist_ok=True); render()

#!/usr/bin/env python3
"""PROPOSTA: mostra, à mesma escala, a pegada EXTERIOR de cada edifício e o seu INTERIOR jogável independente
(plantas lidas de shared/data/world.json; o Prédio Imbondeiro é o desenho proposto). Saída: docs/proposal/building_examples.png"""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
R = Path(__file__).resolve().parent.parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else R / "docs" / "proposal"
world = json.loads((R / "shared/data/world.json").read_text(encoding="utf-8"))
S = 13                                                    # px por célula/tile (2 m) — a MESMA escala dos dois lados
def font(sz, bold=True):
    return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf", sz)
F9, F11, F13, F17 = font(9, False), font(11, False), font(13), font(17)
FURN = (150, 110, 70)

# Prédio proposto: zona comum por piso (corredor + escadas + 2 portas de apartamento) e um modelo de apartamento T1
PREDIO = dict(id="predio_imbondeiro", name="Prédio Imbondeiro (proposto)", type="apartment", w=6, d=4, palette=(132, 196, 150),
              entrances=[dict(id="frente", face="side", i=2, edge="v:4:5")],
              floors=[dict(name=f"Piso {n} — zona comum", w=4, l=8, walls=[], rooms=[],
                           openings=[["v", 0, 2, "unit"], ["v", 4, 2, "unit"]] + ([["v", 4, 5, "exit"]] if n == 0 else []),
                           furniture=[dict(id="planta", x=3, y=7)], units=[f"{n}A", f"{n}B"]) for n in range(3)],
              stairs=[dict(lo=0, x=0, y=6, len=2), dict(lo=1, x=3, y=6, len=2)])
UNIT = dict(name="Apartamento T1 (modelo) — instância privada por unidade", w=6, l=6, walls=[["h", 3, 0, 6], ["v", 3, 0, 3]],
            openings=[["h", 1, 3, "door"], ["h", 4, 3, "door"], ["v", 6, 4, "unitexit"], ["h", 1, 0, "window"], ["h", 4, 0, "window"], ["v", 0, 4, "window"]],
            rooms=[dict(name="Quarto", x=0, y=0, w=3, h=3), dict(name="WC", x=3, y=0, w=3, h=3), dict(name="Sala e cozinha", x=0, y=3, w=6, h=3)],
            furniture=[dict(id="cama", x=0, y=0), dict(id="chuveiro", x=5, y=0), dict(id="sofa", x=0, y=5), dict(id="mesa", x=2, y=4), dict(id="fogao", x=4, y=3), dict(id="bancada", x=3, y=3)])

def draw_floor(d, ox, oy, fl, stairs, idx, exits):
    w, l = fl["w"], fl["l"]
    d.rectangle([ox, oy, ox + w * S, oy + l * S], fill=(196, 150, 104))
    for y in range(l):
        for x in range(w):
            if (x + y) % 2: d.rectangle([ox + x * S, oy + y * S, ox + x * S + S - 1, oy + y * S + S - 1], fill=(186, 140, 96))
    for r in fl.get("rooms", []):
        d.text((ox + (r["x"] + r["w"] / 2) * S, oy + (r["y"] + r["h"] / 2) * S), r["name"], fill=(60, 40, 25), anchor="mm", font=F9)
    for f in fl.get("furniture", []):
        d.rectangle([ox + f["x"] * S + 3, oy + f["y"] * S + 3, ox + f["x"] * S + S - 3, oy + f["y"] * S + S - 3], fill=FURN, outline=(70, 45, 25))
    for st in stairs:
        if st["lo"] == idx or st["lo"] + 1 == idx:
            for k in range(1, st["len"] + 1):
                d.rectangle([ox + st["x"] * S + 1, oy + (st["y"] - k) * S + 1, ox + st["x"] * S + S - 1, oy + (st["y"] - k) * S + S - 1], fill=(120, 96, 150), outline=(60, 40, 90))
            d.text((ox + st["x"] * S + S / 2, oy + (st["y"] - 1) * S), "↑" if st["lo"] == idx else "↓", fill=(255, 255, 255), anchor="mm", font=F13)
    wall = (40, 34, 30)
    d.rectangle([ox, oy, ox + w * S, oy + l * S], outline=wall, width=3)
    for k, a, b, c in fl.get("walls", []):
        if k == "h": d.line([ox + b * S, oy + a * S, ox + c * S, oy + a * S], fill=wall, width=3)
        else: d.line([ox + a * S, oy + b * S, ox + a * S, oy + c * S], fill=wall, width=3)
    colr = {"door": (60, 200, 90), "window": (90, 170, 240), "exit": (240, 60, 60), "unit": (250, 200, 40), "unitexit": (250, 200, 40)}
    def edge(k, x, y, col, wd=5):
        if k == "h": d.line([ox + x * S + 2, oy + y * S, ox + (x + 1) * S - 2, oy + y * S], fill=col, width=wd)
        else: d.line([ox + x * S, oy + y * S + 2, ox + x * S, oy + (y + 1) * S - 2], fill=col, width=wd)
    for k, x, y, kind in fl.get("openings", []): edge(k, x, y, colr[kind])
    for e in exits:
        k, x, y = e.split(":"); edge(k, int(x), int(y), colr["exit"], 7)
    return w * S, l * S

def row(d, y0, b, title, unit=None):
    col = b["palette"] if not isinstance(b["palette"], str) else {"yellow": (224, 186, 92), "pink": (226, 150, 160), "blue": (124, 152, 214), "cream": (232, 218, 186)}[b["palette"]]
    nfl = len(b["floors"]); fa = b["w"] * b["d"]; ia = b["floors"][0]["w"] * b["floors"][0]["l"] + (2 * UNIT["w"] * UNIT["l"] if unit else 0)
    d.text((20, y0), title, fill=(255, 220, 110), font=F17)
    d.text((20, y0 + 24), f"EXTERIOR: pegada {b['w']}×{b['d']} tiles ({b['w'] * 2}×{b['d'] * 2} m), {nfl} piso(s)   ·   INTERIOR: rés-do-chão {ia} células "
           f"({ia / fa:.1f}× a pegada), definido só pela função do edifício", fill=(225, 225, 225), font=F11)
    x, y = 30, y0 + 62
    d.text((x, y - 16), "exterior (mapa)", fill=(180, 180, 180), font=F9)
    d.rectangle([x, y, x + b["w"] * S, y + b["d"] * S], fill=col, outline=(20, 20, 20), width=2)
    d.text((x + b["w"] * S / 2, y + b["d"] * S / 2), str(nfl), fill=(20, 20, 20), anchor="mm", font=F13)
    d.text((x, y + b["d"] * S + 14), f"{nfl} piso(s) × 48 px", fill=(180, 180, 180), font=F9)
    doors = []
    for e in b["entrances"]:
        if e["face"] == "front": p = (x + (e["i"] + 0.5) * S, y + b["d"] * S)
        else: p = (x + b["w"] * S, y + (e["i"] + 0.5) * S)
        d.rectangle([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(240, 60, 60), outline=(255, 255, 255)); doors.append((p, e))
    fx = x + 8 * S + 60
    for idx, fl in enumerate(b["floors"]):
        exits = [e["edge"] for e in b["entrances"]] if idx == 0 else []
        d.text((fx, y - 16), fl.get("name", f"Piso {idx}"), fill=(180, 180, 180), font=F9)
        wpx, lpx = draw_floor(d, fx, y, fl, b.get("stairs", []), idx, exits)
        if idx == 0:
            for p, e in doors:
                k, ex, ey = e["edge"].split(":"); ex, ey = int(ex), int(ey)
                q = (fx + (ex + 0.5) * S, y + ey * S) if k == "h" else (fx + ex * S, y + (ey + 0.5) * S)
                d.line([p, q], fill=(240, 60, 60), width=2)
        fx += wpx + 46
    if unit:
        d.text((fx, y - 16), unit["name"], fill=(250, 200, 40), font=F9)
        draw_floor(d, fx, y, unit, [], 0, [])
        d.text((fx, y + unit["l"] * S + 8), "× 6 instâncias: u:predio_imbondeiro:0A … 2B\n(móveis, arrumos, contrato e permissões por unidade;\nporta amarela = só inquilino e convidados, validado no servidor)", fill=(225, 225, 225), font=F9)
    return y + max(fl["l"] for fl in b["floors"]) * S + 50

world_pal = {b["id"]: b["palette"] for b in world["buildings"]}
BY = {b["id"]: b for b in world["buildings"]}
im = Image.new("RGB", (1500, 1010), (24, 26, 24)); d = ImageDraw.Draw(im)
d.text((20, 12), "PROPOSTA — exterior e interior são representações independentes, ligadas pelas portas (tudo à mesma escala: 1 quadrado = 2 m)", fill=(255, 255, 255), font=F17)
y = 56
y = row(d, y, BY["casa"], "Casa Mussulo — moradia unifamiliar (1 unidade residencial)")
y = row(d, y, BY["mercearia"], "Mercearia Girassol — comércio, 2 pisos, 2 portas (frente e lado)")
y = row(d, y, BY["escritorio"], "Escritório Atlântico — 3 pisos; o último é mais curto (terraço), como no exterior")
y = row(d, y, PREDIO, "Prédio Imbondeiro — 3 pisos × 2 apartamentos; zona comum partilhada + interiores privados", unit=UNIT)
lx, ly = 1130, 70
d.text((lx, ly), "Legenda", fill=(255, 220, 110), font=F13); ly += 22
for c, t in [((240, 60, 60), "porta exterior ↔ saída do interior (a mesma porta)"), ((60, 200, 90), "porta interior"), ((90, 170, 240), "janela"),
             ((250, 200, 40), "porta de apartamento (acesso privado)"), ((120, 96, 150), "escadas (ligam pisos consecutivos)"), (FURN, "mobília")]:
    d.rectangle([lx, ly + 2, lx + 16, ly + 12], fill=c); d.text((lx + 24, ly), t, fill=(230, 230, 230), font=F11); ly += 18
ly += 10
for t in ["Regras de coerência (validadas no arranque do servidor):", "• n.º de pisos do exterior = n.º de pisos do interior",
          "• cada porta exterior liga a uma aresta do perímetro", "   do piso 0, na mesma fachada (frente/lado)",
          "• área do rés-do-chão entre 2× e 5× a pegada", "   (uma casa pequena nunca dá uma mansão)",
          "• ordem de grandeza preservada entre tipos:", "   casa < loja < escritório < prédio"]:
    d.text((lx, ly), t, fill=(230, 230, 230), font=F11); ly += 16
im.save(OUT / "building_examples.png"); print(OUT / "building_examples.png", im.size)

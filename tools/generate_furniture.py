#!/usr/bin/env python3
"""Mobília e carros À ESCALA DO MUNDO (ver docs/SCALE.md).

Escala única do jogo (derivada da projeção isométrica 2:1 já usada pelos tiles):
  * 1 célula da grelha = 2,0 m  (aresta de tile 64x32 px)
  * altura: 19,6 px por metro   (a altura equivalente a 1 célula é ~39 px nesta projeção)
  * personagem 1,75 m = 34 px; porta 2,1 m = 41 px; piso 2,45 m = 48 px

Cada peça é descrita em METROS como caixas (x, y, z), com a frente virada para +y ("s").
As outras orientações (e, n, w) são rodadas geometricamente — não espelhadas — e desenhadas com a
MESMA projeção do jogo, sem escalar bitmaps (pixel-art nítida). Cada PNG tem uma âncora: o píxel onde cai o
canto (0,0,0) da pegada visual; está em assets/art/furniture/anchors.json e é usado pelo InteriorBuilder.
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "assets" / "art"
CELL_M = 2.0
V = 19.6


def proj(x, y, z):
    u, v = x / CELL_M, y / CELL_M
    return ((u - v) * 32.0, (u + v) * 16.0 - z * V)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + ((c[3],) if len(c) > 3 else (255,))


def rotate(boxes, W, D, face):
    out = []
    for (x0, y0, z0, x1, y1, z1, c, *rest) in boxes:
        if face == "s":
            b = (x0, y0, x1, y1)
        elif face == "n":
            b = (W - x1, D - y1, W - x0, D - y0)
        elif face == "e":
            b = (y0, W - x1, y1, W - x0)
        else:  # w
            b = (D - y1, x0, D - y0, x1)
        out.append((b[0], b[1], z0, b[2], b[3], z1, c, *rest))
    return out, ((W, D) if face in ("s", "n") else (D, W))


def render(boxes, outline=True):
    """boxes: (x0,y0,z0,x1,y1,z1,color[,flags]); devolve (imagem, âncora do ponto (0,0,0))."""
    pts = [proj(x, y, z) for (x0, y0, z0, x1, y1, z1, *_r) in boxes for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    minx = min(p[0] for p in pts) - 2
    miny = min(p[1] for p in pts) - 2
    maxx = max(p[0] for p in pts) + 2
    maxy = max(p[1] for p in pts) + 2
    w, h = int(maxx - minx) + 1, int(maxy - miny) + 1
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    P = lambda x, y, z: (round(proj(x, y, z)[0] - minx), round(proj(x, y, z)[1] - miny))
    # sombra suave no chão (pegada)
    xs = [b[0] for b in boxes] + [b[3] for b in boxes]
    ys = [b[1] for b in boxes] + [b[4] for b in boxes]
    X0, X1, Y0, Y1 = min(xs), max(xs), min(ys), max(ys)
    dr.polygon([P(X0, Y0, 0), P(X1, Y0, 0), P(X1 + 0.05, Y1 + 0.05, 0), P(X0, Y1 + 0.05, 0)], fill=(0, 0, 0, 46))
    order = sorted(boxes, key=lambda b: ((b[0] + b[3]) / 2 + (b[1] + b[4]) / 2, b[2]))
    for (x0, y0, z0, x1, y1, z1, c, *flags) in order:
        line = outline and "noline" not in flags and (x1 - x0) > 0.12 and (y1 - y0) > 0.12
        ol = shade(c, 0.55) if line else None
        top = [P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)]
        south = [P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)]
        east = [P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)]
        dr.polygon(south, fill=shade(c, 0.86), outline=ol)
        dr.polygon(east, fill=shade(c, 0.68), outline=ol)
        dr.polygon(top, fill=shade(c, 1.08), outline=ol)
    return im, (-minx, -miny)


WOOD = (150, 98, 56)
DARK = (104, 66, 38)
LIGHT = (200, 156, 104)
WHITE = (236, 236, 230)
METAL = (120, 124, 132)


def legs(W, D, h, t=0.05, c=DARK, inset=0.03):
    return [(inset, inset, 0, inset + t, inset + t, h, c, "noline"), (W - inset - t, inset, 0, W - inset, inset + t, h, c, "noline"),
            (inset, D - inset - t, 0, inset + t, D - inset, h, c, "noline"), (W - inset - t, D - inset - t, 0, W - inset, D - inset, h, c, "noline")]


# nome: (largura x, profundidade y, caixas) — frente para +y
PIECES = {
    "cadeira": (0.46, 0.46, legs(0.46, 0.46, 0.42) + [(0, 0, 0.42, 0.46, 0.46, 0.47, WOOD), (0.02, 0, 0.47, 0.44, 0.06, 0.95, WOOD)]),
    "mesa": (1.6, 0.9, legs(1.6, 0.9, 0.7, 0.07) + [(0, 0, 0.7, 1.6, 0.9, 0.76, LIGHT)]),
    "secretaria": (1.4, 0.7, [(0, 0, 0, 0.05, 0.7, 0.72, DARK), (1.35, 0, 0, 1.4, 0.7, 0.72, DARK), (0.9, 0.05, 0.1, 1.35, 0.68, 0.72, WOOD),
                              (0, 0, 0.72, 1.4, 0.7, 0.76, LIGHT), (0.45, 0.08, 0.76, 0.95, 0.14, 1.1, (40, 44, 52)), (0.65, 0.1, 0.76, 0.75, 0.16, 0.8, (60, 60, 64), "noline")]),
    "sofa": (2.0, 0.9, [(0, 0, 0.08, 2.0, 0.9, 0.4, (52, 124, 134)), (0.18, 0.25, 0.4, 1.82, 0.88, 0.47, (78, 160, 168)),
                        (0, 0, 0.4, 2.0, 0.25, 0.85, (60, 138, 148)), (0, 0.25, 0.4, 0.18, 0.9, 0.62, (60, 138, 148)), (1.82, 0.25, 0.4, 2.0, 0.9, 0.62, (60, 138, 148))]),
    "cama": (1.6, 2.0, [(0, 0, 0.1, 1.6, 2.0, 0.32, DARK), (0.04, 0.08, 0.32, 1.56, 1.98, 0.52, WHITE), (0, 0, 0.1, 1.6, 0.08, 1.0, WOOD),
                        (0.15, 0.14, 0.52, 0.72, 0.5, 0.62, (246, 246, 240)), (0.88, 0.14, 0.52, 1.45, 0.5, 0.62, (246, 246, 240)),
                        (0.02, 0.75, 0.52, 1.58, 2.0, 0.56, (70, 110, 170))]),
    "estante": (0.9, 0.35, [(0, 0, 0, 0.9, 0.06, 1.9, DARK), (0, 0, 0, 0.04, 0.35, 1.9, WOOD), (0.86, 0, 0, 0.9, 0.35, 1.9, WOOD), (0, 0, 1.86, 0.9, 0.35, 1.9, WOOD)]
                + [(0.04, 0.06, z, 0.86, 0.35, z + 0.03, WOOD, "noline") for z in (0.0, 0.47, 0.94, 1.41)]
                + [(0.06 + i * 0.13, 0.08, z + 0.03, 0.06 + i * 0.13 + 0.1, 0.3, z + 0.03 + 0.3 + 0.05 * (i % 2), c, "noline")
                   for z in (0.0, 0.47, 0.94) for i, c in enumerate([(180, 60, 50), (60, 110, 170), (210, 180, 80), (70, 140, 80), (150, 70, 140), (220, 120, 60)])]),
    "planta": (0.42, 0.42, [(0.04, 0.04, 0, 0.38, 0.38, 0.32, (190, 96, 60)), (0, 0, 0.32, 0.42, 0.42, 0.62, (60, 140, 64)),
                            (0.06, 0.06, 0.62, 0.36, 0.36, 0.9, (80, 166, 80)), (0.13, 0.13, 0.9, 0.29, 0.29, 1.05, (100, 186, 96))]),
    "fogao": (0.6, 0.6, [(0, 0, 0, 0.6, 0.6, 0.88, WHITE), (0.08, 0.6, 0.12, 0.52, 0.61, 0.6, (60, 60, 66), "noline")]
              + [(x, y, 0.88, x + 0.14, y + 0.14, 0.9, (40, 40, 44), "noline") for x in (0.1, 0.36) for y in (0.1, 0.36)]),
    "bancada": (1.6, 0.6, [(0, 0, 0, 1.6, 0.6, 0.86, WOOD), (0, 0, 0.86, 1.6, 0.6, 0.9, (210, 210, 204)), (0.9, 0.12, 0.84, 1.4, 0.48, 0.9, (150, 170, 184), "noline"),
                           (1.12, 0.04, 0.9, 1.18, 0.1, 1.15, METAL, "noline")] + [(0.08 + i * 0.4, 0.6, 0.1, 0.44 + i * 0.4, 0.61, 0.78, DARK, "noline") for i in range(2)]),
    "chuveiro": (0.9, 0.9, [(0, 0, 0, 0.9, 0.9, 0.08, (220, 226, 230)), (0.4, 0.02, 0.08, 0.46, 0.08, 2.0, METAL, "noline"),
                            (0.3, 0.06, 1.9, 0.56, 0.3, 1.94, METAL, "noline"), (0, 0.86, 0.08, 0.9, 0.9, 1.95, (170, 210, 230, 110), "noline"),
                            (0.86, 0, 0.08, 0.9, 0.86, 1.95, (170, 210, 230, 110), "noline")]),
    "balcao": (2.4, 0.6, [(0, 0, 0, 2.4, 0.6, 1.0, WOOD), (0, 0, 1.0, 2.4, 0.6, 1.05, LIGHT), (0.1, 0.6, 0.15, 2.3, 0.61, 0.85, DARK, "noline"),
                          (1.7, 0.1, 1.05, 2.1, 0.45, 1.25, (60, 60, 66)), (1.75, 0.12, 1.25, 2.05, 0.2, 1.35, (80, 80, 88), "noline")]),
}


def furniture():
    d = ROOT / "furniture"
    d.mkdir(exist_ok=True)
    anchors = {}
    for name, (W, D, boxes) in PIECES.items():
        for face in ("s", "e", "n", "w"):
            bx, (w, dd) = rotate(boxes, W, D, face)
            im, anc = render(bx)
            im.save(d / f"{name}_{face}.png")
            anchors[f"{name}_{face}"] = [round(anc[0]), round(anc[1])]
    (d / "anchors.json").write_text(json.dumps(anchors, indent=1, sort_keys=True), encoding="utf-8")


def cars():
    """Carros do cenário: 4,2 x 1,8 x 1,45 m (antes eram ~metade do tamanho). Âncora = centro no chão."""
    for name, body, roof in (("red", (190, 50, 44), (150, 36, 34)), ("blue", (54, 96, 180), (40, 70, 140)), ("white", (220, 220, 214), (180, 180, 176))):
        L, Wd = 4.2, 1.8
        boxes = [(0, 0, 0.18, L, Wd, 0.8, body), (1.0, 0.12, 0.8, 3.1, Wd - 0.12, 1.4, roof), (1.05, Wd - 0.13, 0.86, 3.05, Wd - 0.11, 1.34, (150, 200, 230), "noline"),
                 (3.08, 0.15, 0.86, 3.11, Wd - 0.15, 1.34, (150, 200, 230), "noline")]
        boxes += [(x, y, 0, x + 0.6, y + 0.2, 0.36, (30, 30, 32), "noline") for x in (0.5, 3.1) for y in (-0.02, Wd - 0.18)]
        for direction, face in (("dr", "e"), ("ul", "w")):
            # carro ao longo de +u ("dr", desce para a direita) = comprimento no eixo x
            bx = [(x0 - L / 2, y0 - Wd / 2, z0, x1 - L / 2, y1 - Wd / 2, z1, *r) for (x0, y0, z0, x1, y1, z1, *r) in boxes]
            if direction == "ul":
                bx = [(-x1, -y1, z0, -x0, -y0, z1, *r) for (x0, y0, z0, x1, y1, z1, *r) in bx]
            hl = (255, 238, 150) if direction == "dr" else (210, 60, 50)
            bx.append((L / 2 - 0.02, -0.7, 0.45, L / 2 + 0.01, -0.4, 0.6, hl, "noline") if direction == "dr" else (-L / 2 - 0.01, 0.4, 0.45, -L / 2 + 0.02, 0.7, 0.6, hl, "noline"))
            im, anc = render(bx)
            canvas = Image.new("RGBA", (112, 64), (0, 0, 0, 0))   # âncora fixa (56, 44) para o AmbientCar
            canvas.paste(im, (56 - round(anc[0]), 44 - round(anc[1])), im)
            canvas.save(ROOT / "props" / f"car_{name}_{direction}.png")


if __name__ == "__main__":
    furniture()
    cars()
    print("OK furniture + cars")

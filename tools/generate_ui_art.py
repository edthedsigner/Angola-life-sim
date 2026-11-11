#!/usr/bin/env python3
"""Gera arte PLACEHOLDER de UI/ambiente: logo, icones, brilho de candeeiro, carros. Substitui os PNG com o mesmo nome para trocar.
Requer pillow. Logo: assets/art/ui/logo.png (qualquer tamanho; a UI escala mantendo proporção)."""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import json, math, random
R = Path(__file__).resolve().parent.parent / "assets" / "art"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
cfg = json.loads((Path(__file__).resolve().parent.parent / "config" / "branding.json").read_text())

def text_outlined(dr, xy, s, font, fill, outline, anchor="mm"):
    x, y = xy
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx or dy: dr.text((x + dx, y + dy), s, font=font, fill=outline, anchor=anchor)
    dr.text((x, y + 1), s, font=font, fill=(60, 36, 10, 255), anchor=anchor)  # sombra
    dr.text((x, y), s, font=font, fill=fill, anchor=anchor)

def logo():
    W, H = 240, 74
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dr = ImageDraw.Draw(im); dr.fontmode = "1"
    # sol
    dr.ellipse([84, 0, 156, 72], fill=(236, 170, 40, 255)); dr.ellipse([90, 6, 150, 66], fill=(248, 196, 64, 255))
    # skyline
    rnd = random.Random(7)
    for x in range(92, 150, 6):
        h = rnd.randint(14, 30); dr.rectangle([x, 44 - h, x + 5, 44], fill=(120, 82, 56, 255))
        for wy in range(44 - h + 3, 42, 5): dr.point([x + 2, wy], fill=(250, 220, 120, 255))
    # obelisco
    dr.polygon([(150, 44), (152, 4), (154, 44)], fill=(188, 150, 106, 255)); dr.polygon([(152, 4), (154, 44), (153, 44)], fill=(150, 116, 78, 255))
    # palmeiras
    def palm(cx, base, h, lean):
        tx, ty = cx + lean, base - h
        dr.line([(cx, base), (tx, ty)], fill=(86, 56, 30, 255), width=2)
        for ang in (-150, -110, -70, -30, 10, 190):
            a = math.radians(ang); ex, ey = tx + math.cos(a) * 14, ty + math.sin(a) * 8 + 4
            dr.line([(tx, ty), (ex, ey)], fill=(46, 150, 70, 255), width=2); dr.line([(tx, ty - 1), ((tx + ex) / 2, (ty + ey) / 2 - 3)], fill=(90, 190, 90, 255), width=1)
    palm(72, 50, 28, -2); palm(168, 50, 26, 3); palm(60, 52, 20, 4)
    # relva
    dr.rectangle([48, 48, 192, 52], fill=(54, 120, 52, 255))
    f1 = ImageFont.truetype(FONT, 27); f2 = ImageFont.truetype(FONT, 20)
    text_outlined(dr, (W // 2, 46), cfg["title_line1"], f1, (255, 255, 255, 255), (40, 28, 20, 255))
    text_outlined(dr, (W // 2, 66), cfg["title_line2"], f2, (252, 196, 28, 255), (60, 30, 8, 255))
    im = im.resize((W * 2, H * 2), Image.NEAREST); im.save(R / "ui" / "logo.png")

def icons():
    u = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(u); c = (232, 168, 28, 255)
    d.ellipse([5, 1, 10, 6], fill=c); d.rectangle([3, 8, 12, 14], fill=c); d.rectangle([4, 7, 11, 8], fill=c); u.save(R / "ui" / "icon_user.png")
    l = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(l)
    d.rectangle([3, 7, 12, 14], fill=c); d.rectangle([5, 2, 6, 7], fill=c); d.rectangle([9, 2, 10, 7], fill=c); d.rectangle([5, 1, 10, 2], fill=c)
    d.rectangle([7, 9, 8, 11], fill=(60, 40, 10, 255)); l.save(R / "ui" / "icon_lock.png")

def glow():
    S = 48; im = Image.new("RGBA", (S, S))
    px = im.load()
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - S / 2 + .5, y - S / 2 + .5) / (S / 2); a = max(0, 1 - d) ** 2
            px[x, y] = (255, 214, 120, int(a * 200))
    im.save(R / "props" / "glow.png")

def car(name, body, roof, direction):
    # carro iso 40x24; direction 'dr' (desce para a direita) ou 'ul'
    im = Image.new("RGBA", (40, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.polygon([(4, 14), (22, 23), (38, 15), (20, 6)], fill=(0, 0, 0, 70))
    d.polygon([(3, 12), (20, 21), (20, 16), (3, 8)], fill=tuple(int(v * .75) for v in body) + (255,))      # lado esquerdo
    d.polygon([(20, 21), (37, 12), (37, 8), (20, 16)], fill=tuple(int(v * .55) for v in body) + (255,))    # lado direito
    d.polygon([(3, 8), (20, 16), (37, 8), (20, 0)], fill=body + (255,))                                    # topo
    d.polygon([(11, 8), (20, 12), (29, 8), (20, 4)], fill=roof + (255,))                                    # tejadilho
    d.polygon([(21, 13), (28, 9), (28, 8), (21, 12)], fill=(150, 200, 230, 255))
    hl = (255, 238, 150, 255) if direction == "dr" else (210, 60, 50, 255)
    if direction == "dr": d.rectangle([33, 11, 36, 12], fill=hl)
    else: d.rectangle([4, 10, 7, 11], fill=hl)
    im.save(R / "props" / f"car_{name}_{direction}.png")

if __name__ == "__main__":
    logo(); icons(); glow()
    for n, b, r in (("red", (190, 50, 44), (150, 36, 34)), ("blue", (54, 96, 180), (40, 70, 140)), ("white", (220, 220, 214), (180, 180, 176))):
        for dr_ in ("dr", "ul"): car(n, b, r, dr_)
    print("OK ui art")

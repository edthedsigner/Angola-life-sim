#!/usr/bin/env python3
"""Gera a arte PLACEHOLDER em assets/art/. Para trocar arte: substitui o PNG com o mesmo nome e dimensoes.
Os tiles do chao vem do pack (assets/art/pack_original). Requer: pillow."""
from PIL import Image, ImageDraw
from pathlib import Path
import shutil
ROOT = Path(__file__).resolve().parent.parent / "assets" / "art"
PACK = ROOT / "pack_original"
H = 48
def sh(c, f): return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)

def tiles():
    d = ROOT / "tiles"
    for src, dst in (("ground", "grass"), ("ground_b", "grass_b"), ("road", "road"), ("plaza", "sidewalk")):
        shutil.copy(PACK / f"{src}.png", d / f"{dst}.png")
    base = Image.open(PACK / "road.png").convert("RGBA")
    for name, (a, b) in {"road_line_c": ((22, 11), (42, 21)), "road_line_r": ((22, 21), (42, 11))}.items():
        im = base.copy(); ImageDraw.Draw(im).line([a, b], fill=(232, 212, 96, 255), width=2); im.save(d / f"{name}.png")

PAL = {"pink": ((226,160,160),(150,70,60)), "yellow": ((236,208,110),(170,70,40)),
       "blue": ((150,186,226),(90,96,110)), "cream": ((232,220,190),(150,80,50))}
def fp(side, u, v):
    return (32*u, (48+16*u if side == "l" else 64-16*u) - H*v)
def quad(dr, side, u0, v0, u1, v1, fill):
    dr.polygon([fp(side,u0,v0), fp(side,u1,v0), fp(side,u1,v1), fp(side,u0,v1)], fill=fill)
def wall(pal, side, kind):
    base = PAL[pal][0]; col = sh(base, 0.95 if side == "l" else 0.78)
    im = Image.new("RGBA", (32, 64), (0,0,0,0)); dr = ImageDraw.Draw(im)
    quad(dr, side, 0,0,1,1, col); quad(dr, side, 0,0,1,0.09, sh(col,0.72)); quad(dr, side, 0,0.93,1,1, sh(col,1.12))
    for k in range(1, 7):
        v = 0.09 + k*0.12
        if v < 0.93: quad(dr, side, 0, v, 1, v+0.012, sh(col,0.93))
    quad(dr, side, 0,0,0.04,1, sh(col,0.85))
    glass = (110,160,200,255) if side == "l" else (84,128,168,255); frame = (245,245,240,255)
    if kind == "window":
        quad(dr, side, .22,.34,.78,.82, frame); quad(dr, side, .28,.40,.72,.76, glass)
        quad(dr, side, .48,.40,.52,.76, frame); quad(dr, side, .22,.30,.78,.34, sh(base,0.6))
    elif kind == "door":
        quad(dr, side, .26,0,.74,.76, frame); quad(dr, side, .31,0,.69,.71, (112,70,40,255))
        quad(dr, side, .34,.12,.66,.40, (96,58,32,255)); quad(dr, side, .58,.32,.62,.38, (230,200,90,255))
    elif kind == "shop":
        quad(dr, side, .08,.14,.92,.58, frame); quad(dr, side, .12,.18,.88,.54, glass)
        for i in range(6):
            quad(dr, side, .05+i*.15,.58,.05+(i+1)*.15,.76, (200,50,50,255) if i%2==0 else (245,245,240,255))
    return im
def roof(pal):
    rc = PAL[pal][1]; im = Image.new("RGBA", (64,32), (0,0,0,0)); dr = ImageDraw.Draw(im)
    dr.polygon([(32,0),(63,15),(32,31),(0,15)], fill=sh(rc,1.0)); dr.polygon([(32,4),(56,15),(32,27),(8,15)], fill=sh(rc,1.12))
    dr.line([(32,0),(63,15)], fill=sh(rc,1.3)); dr.line([(0,15),(32,0)], fill=sh(rc,1.3))
    dr.line([(32,31),(63,15)], fill=sh(rc,0.7)); dr.line([(0,15),(32,31)], fill=sh(rc,0.8)); return im
def buildings():
    d = ROOT / "buildings"
    for pal in PAL:
        for side in "lr":
            for kind in ("plain","window","door","shop"): wall(pal, side, kind).save(d / f"{pal}_wall_{side}_{kind}.png")
        roof(pal).save(d / f"{pal}_roof.png")
def props():
    d = ROOT / "props"
    im = Image.new("RGBA",(48,72),(0,0,0,0)); dr = ImageDraw.Draw(im)
    dr.ellipse([14,62,34,71], fill=(0,0,0,70)); dr.rectangle([21,38,27,68], fill=(110,76,46,255))
    for b,c in (([4,8,44,40],(46,120,54)),([10,2,40,28],(60,148,66)),([16,10,36,24],(84,172,86))): dr.ellipse(b, fill=c+(255,))
    im.save(d/"tree.png")
    im = Image.new("RGBA",(16,64),(0,0,0,0)); dr = ImageDraw.Draw(im)
    dr.ellipse([2,58,14,63], fill=(0,0,0,70)); dr.rectangle([7,12,9,60], fill=(60,64,72,255)); dr.rectangle([4,56,11,60], fill=(50,54,60,255))
    dr.rectangle([3,4,12,12], fill=(250,232,150,255)); dr.rectangle([2,2,13,4], fill=(60,64,72,255)); im.save(d/"lamp.png")
    im = Image.new("RGBA",(40,28),(0,0,0,0)); dr = ImageDraw.Draw(im)
    dr.polygon([(2,20),(20,28),(38,20),(20,12)], fill=(0,0,0,60)); dr.polygon([(4,14),(20,22),(36,14),(20,6)], fill=(150,100,56,255))
    dr.polygon([(4,14),(20,22),(20,25),(4,17)], fill=(110,72,40,255)); dr.polygon([(36,14),(20,22),(20,25),(36,17)], fill=(90,58,32,255))
    dr.polygon([(4,6),(20,14),(36,6),(36,9),(20,17),(4,9)], fill=(170,116,66,255)); im.save(d/"bench.png")
    im = Image.new("RGBA",(32,24),(0,0,0,0)); dr = ImageDraw.Draw(im)
    dr.ellipse([2,14,30,24], fill=(0,0,0,55)); dr.ellipse([2,6,20,22], fill=(48,128,60,255)); dr.ellipse([12,4,30,22], fill=(64,150,72,255))
    dr.ellipse([9,2,23,14], fill=(90,176,92,255)); im.save(d/"bush.png")

def char_layers():
    d = ROOT / "characters"; W, Hh = 24, 40
    body = Image.new("RGBA",(W*3,Hh),(0,0,0,0)); legs = Image.new("RGBA",(W*3,Hh),(0,0,0,0)); shirt = Image.new("RGBA",(W*3,Hh),(0,0,0,0))
    WH=(255,255,255,255); LT=(226,226,226,255); EYE=(36,26,26,255)
    bd = ImageDraw.Draw(body); lg = ImageDraw.Draw(legs); sd = ImageDraw.Draw(shirt)
    for f in range(3):
        o = f*W; la = 0 if f==0 else (1 if f==1 else -1)
        bd.rectangle([o+7,2,o+16,11], fill=WH); bd.rectangle([o+7,9,o+16,11], fill=LT); bd.rectangle([o+10,12,o+13,13], fill=LT)
        bd.point([o+9,6], fill=EYE); bd.point([o+14,6], fill=EYE); bd.line([o+11,9,o+12,9], fill=(150,80,80,255))
        bd.rectangle([o+4,18+la,o+5,24+la], fill=WH); bd.rectangle([o+18,18-la,o+19,24-la], fill=WH)
        sd.rectangle([o+6,13,o+17,25], fill=WH); sd.rectangle([o+4,13,o+5,19+la], fill=WH); sd.rectangle([o+18,13,o+19,19-la], fill=WH)
        sd.rectangle([o+6,22,o+17,25], fill=(215,215,215,255))
        lo = 0 if f==0 else (-2 if f==1 else 0); ro = 0 if f==0 else (0 if f==1 else -2)
        pants=(52,62,104,255); shoe=(40,36,36,255)
        lg.rectangle([o+7,26,o+11,36+lo], fill=pants); lg.rectangle([o+12,26,o+16,36+ro], fill=pants)
        lg.rectangle([o+6,37+lo,o+11,39+lo], fill=shoe); lg.rectangle([o+12,37+ro,o+17,39+ro], fill=shoe)
    body.save(d/"body.png"); legs.save(d/"legs.png"); shirt.save(d/"shirt.png")
    s = Image.new("RGBA",(24,10),(0,0,0,0)); ImageDraw.Draw(s).ellipse([1,1,22,8], fill=(0,0,0,80)); s.save(d/"shadow.png")
    G=(255,255,255,255); S=(214,214,214,255)
    def new(): im = Image.new("RGBA",(W,Hh),(0,0,0,0)); return im, ImageDraw.Draw(im)
    im,dr = new(); dr.rectangle([7,0,16,4],fill=G); dr.rectangle([6,2,7,6],fill=G); dr.rectangle([16,2,17,6],fill=G); dr.rectangle([7,4,16,4],fill=S); im.save(d/"hair_0.png")
    im,dr = new(); dr.rectangle([6,0,17,5],fill=G); dr.rectangle([5,2,7,12],fill=G); dr.rectangle([16,2,18,12],fill=G); dr.rectangle([6,5,17,5],fill=S); im.save(d/"hair_1.png")
    im,dr = new(); dr.rectangle([6,0,17,5],fill=G); dr.rectangle([6,5,17,5],fill=S)
    for x in (4,18):
        for y in range(4,24,4): dr.rectangle([x,y,x+1,y+2],fill=G); dr.rectangle([x,y+3,x+1,y+3],fill=S)
    im.save(d/"hair_2.png")
    im,dr = new(); dr.rectangle([7,1,16,2],fill=S); dr.point([6,3],fill=S); dr.point([17,3],fill=S); im.save(d/"hair_3.png")
# ------------------------------------------------------------------ interiores (mesmo sistema de peças por aresta)
INT = (232, 222, 204)
def int_walls():
    """Paredes interiores: 'int_wall_*' altura total (paredes do fundo, com janela opcional) e 'int_low_*' em corte
    (paredes da frente e divisórias ficam baixas para o jogador nunca ficar escondido — vista em corte como no original)."""
    d = ROOT / "interior"; d.mkdir(exist_ok=True)
    PAL["int"] = (INT, (120, 100, 80))
    for side in "lr":
        for kind in ("plain", "window"):
            wall("int", side, kind).save(d / f"int_wall_{side}_{kind}.png")
        col = sh(INT, 0.95 if side == "l" else 0.8)
        for kind in ("plain", "door", "exit"):
            im = Image.new("RGBA", (32, 64), (0, 0, 0, 0)); dr = ImageDraw.Draw(im)
            if kind == "plain":
                quad(dr, side, 0, 0, 1, 0.26, col); quad(dr, side, 0, 0.22, 1, 0.26, sh(col, 1.18)); quad(dr, side, 0, 0, 1, 0.04, sh(col, 0.7))
            elif kind == "door":   # porta fechada vista em corte: folha de madeira baixa
                quad(dr, side, 0.06, 0, 0.94, 0.3, (112, 70, 40, 255)); quad(dr, side, 0.06, 0.26, 0.94, 0.3, (150, 100, 60, 255))
            else:                  # saída para a rua: soleira escura + tapete
                quad(dr, side, 0, 0, 1, 0.05, (70, 60, 52, 255)); quad(dr, side, 0.1, 0.0, 0.9, 0.03, (180, 60, 50, 255))
            im.save(d / f"int_low_{side}_{kind}.png")
    floor = Image.open(PACK / "floor.png").convert("RGBA"); floor.save(d / "floor.png")
    mat = floor.copy(); px = mat.load()
    for y in range(32):
        for x in range(64):
            r, g, b, a = px[x, y]
            if a and abs(x - 32) / 32 + abs(y - 16) / 16 <= 0.62: px[x, y] = (150, 50, 44, a)
    mat.save(d / "floor_mat.png")

def iso_box(im, cx, by, w, h, ht, top, left, right):
    """Caixa isométrica com a esquina de baixo em (cx, by); w/h em células (64x32 por célula)."""
    dr = ImageDraw.Draw(im)
    B = (cx, by); L = (cx - 32 * h, by - 16 * h); R = (cx + 32 * w, by - 16 * w); T = (L[0] + 32 * w, L[1] - 16 * w)
    up = lambda p: (p[0], p[1] - ht)
    dr.polygon([L, B, up(B), up(L)], fill=left); dr.polygon([B, R, up(R), up(B)], fill=right)
    dr.polygon([up(T), up(R), up(B), up(L)], fill=top)
    return dr, up, (T, R, B, L)

def furniture():
    d = ROOT / "furniture"; d.mkdir(exist_ok=True)
    # fogão 1x1 (64x76): caixa branca com bicos
    im = Image.new("RGBA", (64, 76), (0, 0, 0, 0)); dr, up, (T, R, B, L) = iso_box(im, 32, 75, 1, 1, 30, (236, 236, 232, 255), (200, 200, 196, 255), (170, 170, 166, 255))
    for (u, v) in ((0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)):
        x = L[0] + 32 * u + 32 * v - 32 * 0; y = up(L)[1] - 16 * u + 16 * v
        dr.ellipse([x - 5 + 0, y - 3, x + 5, y + 3], fill=(40, 40, 44, 255))
    dr.polygon([(B[0] - 22, B[1] - 26), (B[0] - 4, B[1] - 17), (B[0] - 4, B[1] - 6), (B[0] - 22, B[1] - 15)], fill=(60, 60, 66, 255))
    im.save(d / "fogao.png")
    # chuveiro 1x1 (64x112): base de duche + vidro + chuveiro
    im = Image.new("RGBA", (64, 112), (0, 0, 0, 0)); dr, up, (T, R, B, L) = iso_box(im, 32, 111, 1, 1, 6, (210, 230, 240, 255), (190, 196, 200, 255), (160, 166, 170, 255))
    dr.line([(T[0], T[1] - 6), (T[0], T[1] - 92)], fill=(150, 150, 156, 255), width=3)
    dr.line([(T[0], T[1] - 92), (T[0] + 12, T[1] - 84)], fill=(150, 150, 156, 255), width=3)
    dr.ellipse([T[0] + 8, T[1] - 86, T[0] + 18, T[1] - 80], fill=(180, 180, 186, 255))
    dr.polygon([(L[0], L[1] - 6), (L[0], L[1] - 88), (B[0], B[1] - 88), (B[0], B[1] - 6)], fill=(170, 210, 230, 90))   # vidro virado para a divisão
    dr.line([(B[0], B[1] - 6), (B[0], B[1] - 88)], fill=(220, 236, 244, 200), width=1)
    dr.line([(L[0], L[1] - 88), (B[0], B[1] - 88)], fill=(200, 210, 216, 220), width=1)
    im.save(d / "chuveiro.png")
    # balcão 2x1 (128x94): madeira com tampo claro e caixa registadora
    im = Image.new("RGBA", (128, 94), (0, 0, 0, 0)); dr, up, (T, R, B, L) = iso_box(im, 64 - 16, 93, 2, 1, 34, (222, 196, 150, 255), (150, 98, 56, 255), (122, 78, 44, 255))
    dr.polygon([(B[0] - 26, B[1] - 30), (B[0] - 4, B[1] - 19), (B[0] - 4, B[1] - 14), (B[0] - 26, B[1] - 25)], fill=(190, 140, 80, 255))
    cx, cy = up(T)[0] + 4, up(T)[1] + 18
    dr.polygon([(cx - 10, cy), (cx, cy - 5), (cx + 10, cy), (cx, cy + 5)], fill=(60, 60, 64, 255))
    dr.polygon([(cx - 10, cy), (cx, cy + 5), (cx, cy - 6), (cx - 10, cy - 11)], fill=(80, 80, 86, 255))
    im.save(d / "balcao.png")

if __name__ == "__main__":
    tiles(); buildings(); props(); char_layers(); int_walls(); furniture(); print("OK", ROOT)

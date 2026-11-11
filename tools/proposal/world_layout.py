#!/usr/bin/env python3
"""PROPOSTA de mapa (não é usada pelo jogo): gera o bairro proposto como dados (estradas, terreno, edifícios, adereços),
valida-o (entradas alcançáveis, nada a tapar caminhos) e desenha as pré-visualizações em docs/proposal/.
Uso: python3 tools/proposal/world_layout.py [pasta_de_saida]
Coordenadas de planta: x = coluna (este), y = linha (sul). 1 tile = 2 m. No jogo a vista é isométrica (planta rodada 45°)."""
import heapq, json, math, random, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parent.parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else R / "docs" / "proposal"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 128, 96
TILE_M = 2.0
SPEED_TILES_S = 2.43            # medido: 110 px/s ao longo de um eixo do tile (Player.gd)
rng = random.Random(7)
np.random.seed(7)

# ---------------------------------------------------------------- superfícies
GRASS, DRY, DIRT, SOIL, SAND, GRAVEL, CONCRETE, PAVE, ASPHALT, VALA, BRIDGE, PITCH, PATH, YARD, DROAD = range(15)
NAMES = {GRASS: "Relva / vegetação", DRY: "Capim seco", DIRT: "Terra batida", SOIL: "Solo nu", SAND: "Areia",
         GRAVEL: "Brita / cascalho", CONCRETE: "Betão", PAVE: "Passeio calcetado", ASPHALT: "Asfalto",
         VALA: "Vala de drenagem (não se atravessa)", BRIDGE: "Pontão", PITCH: "Campo de terra", PATH: "Carreiro / atalho pedonal",
         YARD: "Quintal (terra + relva)", DROAD: "Rua de terra batida compactada"}
COL = {GRASS: (104, 158, 72), DRY: (156, 160, 92), DIRT: (170, 128, 90), SOIL: (140, 100, 68), SAND: (224, 203, 152),
       GRAVEL: (162, 160, 152), CONCRETE: (192, 190, 182), PAVE: (208, 192, 160), ASPHALT: (82, 82, 94),
       VALA: (66, 104, 116), BRIDGE: (146, 112, 78), PITCH: (200, 160, 108), PATH: (232, 204, 160), YARD: (160, 138, 88), DROAD: (214, 170, 118)}
WALK_BLOCK = {VALA}

def value_noise(scale, seed):
    r = np.random.RandomState(seed)
    gw, gh = W // scale + 3, H // scale + 3
    g = r.rand(gh, gw)
    ys, xs = np.mgrid[0:H, 0:W]
    fx, fy = xs / scale, ys / scale
    x0, y0 = fx.astype(int), fy.astype(int)
    tx, ty = fx - x0, fy - y0
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = g[y0, x0] * (1 - tx) + g[y0, x0 + 1] * tx
    b = g[y0 + 1, x0] * (1 - tx) + g[y0 + 1, x0 + 1] * tx
    return a * (1 - ty) + b * ty
N1 = value_noise(10, 1) * 0.6 + value_noise(4, 2) * 0.4      # manchas grandes
N2 = value_noise(3, 3)                                        # detalhe
N3 = value_noise(16, 4)

# ---------------------------------------------------------------- bairros (sementes -> fronteiras irregulares)
ZONES = {
    "centro":     dict(name="Centro comercial", purpose="lojas, restaurante, escritórios, praça", tint=(230, 120, 60),
                       seeds=[(64, 46), (63, 32), (76, 44), (54, 46), (60, 22)]),
    "mercado":    dict(name="Mercado informal", purpose="bancas, vendedores de rua, armazém", tint=(220, 60, 120),
                       seeds=[(24, 34), (22, 22), (34, 38), (14, 42)]),
    "obras":      dict(name="Zona em construção", purpose="obra, lotes vazios (expansão futura)", tint=(150, 150, 150),
                       seeds=[(34, 10), (46, 8), (14, 8), (48, 18)]),
    "residencial": dict(name="Bairro residencial", purpose="casas com quintal, becos, escola", tint=(70, 130, 230),
                        seeds=[(84, 20), (98, 24), (90, 36), (104, 34), (92, 8), (112, 14), (76, 12), (80, 32)]),
    "predios":    dict(name="Zona dos prédios", purpose="prédios de apartamentos, estacionamento, pátios", tint=(150, 90, 220),
                       seeds=[(42, 62), (46, 78), (54, 64), (38, 56), (56, 76)]),
    "periferia":  dict(name="Periferia", purpose="terreno aberto, vegetação, campo de futebol, trilho", tint=(60, 170, 90),
                       seeds=[(112, 60), (108, 80), (122, 44), (90, 84), (72, 86), (124, 86), (122, 6), (92, 66), (76, 64)]),
    "areal":      dict(name="Areal", purpose="areia e capim; reserva para casas futuras", tint=(230, 200, 60),
                       seeds=[(14, 84), (24, 90), (6, 76), (10, 62), (6, 54)]),
}
ZKEYS = list(ZONES)
ys, xs = np.mgrid[0:H, 0:W]
best = np.full((H, W), 1e9); zone = np.zeros((H, W), int)
for zi, k in enumerate(ZKEYS):
    for (sx, sy) in ZONES[k]["seeds"]:
        d = np.hypot(xs - sx, ys - sy) + (N1 - 0.5) * 22 + (N2 - 0.5) * 5
        m = d < best; best[m] = d[m]; zone[m] = zi
def zone_at(x, y): return ZKEYS[zone[int(y), int(x)]]

surf = np.zeros((H, W), int)
def base_surface(z, a, b, c):
    if z == "centro":      return CONCRETE if a < 0.62 else (DIRT if b < 0.6 else GRAVEL)
    if z == "mercado":     return DIRT if a < 0.66 else (SOIL if b < 0.55 else SAND)
    if z == "obras":       return SOIL if a < 0.45 else (GRAVEL if a < 0.6 else (DRY if b < 0.6 else DIRT))
    if z == "residencial": return DIRT if a < 0.4 else (SOIL if a < 0.5 else (DRY if a < 0.62 else GRASS))
    if z == "predios":     return DIRT if a < 0.42 else (CONCRETE if a < 0.56 else (GRASS if b < 0.5 else DRY))
    if z == "periferia":   return GRASS if a < 0.6 else (DRY if a < 0.76 else (SOIL if b < 0.5 else DIRT))
    return SAND if a < 0.68 else (DRY if b < 0.6 else SOIL)          # areal
for y in range(H):
    for x in range(W):
        surf[y, x] = base_surface(ZKEYS[zone[y, x]], N1[y, x], N2[y, x], N3[y, x])

# ---------------------------------------------------------------- vias (polilinhas suavizadas, larguras por função)
def smooth(pts, n=14):
    p = [pts[0]] + list(pts) + [pts[-1]]; out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = (np.array(q, float) for q in p[i - 1:i + 3])
        for t in np.linspace(0, 1, n, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(np.array(pts[-1], float)); return out
ROADS = [  # (id, nome, classe, largura em tiles, superfície, pontos)
    ("avenida", "Avenida (via principal)", "principal", 4, ASPHALT, [(-2, 53), (18, 51), (40, 46), (64, 48), (86, 53), (106, 50), (130, 43)]),
    ("comercio", "Rua do Comércio", "secundaria", 3, ASPHALT, [(64, 48), (62, 37), (66, 25), (64, 11), (70, -2)]),
    ("predios", "Rua dos Prédios (sem saída)", "secundaria", 3, ASPHALT, [(43, 46), (41, 59), (46, 71), (44, 85)]),
    ("bairro", "Rua do Bairro (terra, sem saída)", "terra", 3, DROAD, [(66, 25), (79, 20), (94, 24), (107, 18), (116, 15)]),
    ("mercado", "Rua do Mercado (terra)", "terra", 3, DROAD, [(21, 51), (20, 39), (26, 29), (22, 17), (31, 9)]),
    ("trilho", "Trilho da periferia (terra)", "terra", 2, DROAD, [(105, 50), (110, 62), (106, 76), (115, 89), (130, 92)]),
    ("beco1", "Beco (liga a Rua do Bairro à Avenida)", "beco", 2, DROAD, [(84, 21), (86, 32), (83, 42), (86, 52)]),
    ("beco2", "Beco sem saída (pátio)", "beco", 2, DROAD, [(98, 23), (100, 33), (106, 38)]),
    ("beco3", "Beco norte sem saída", "beco", 2, DROAD, [(91, 23), (93, 11), (88, 4)]),
    ("travessa", "Travessa do mercado (pedonal)", "pedonal", 1, PATH, [(26, 29), (38, 31), (51, 29), (62, 36)]),
    ("atalho", "Atalho prédios–campo (pedonal)", "pedonal", 1, PATH, [(46, 71), (60, 69), (71, 71), (80, 62), (90, 59), (93, 52)]),
    ("carreiro", "Carreiro do areal (pedonal, pontão)", "pedonal", 1, PATH, [(23, 52), (21, 62), (20, 72), (16, 82), (22, 91)]),
    ("carreiro2", "Carreiro prédios–areal (pedonal, pontão)", "pedonal", 1, PATH, [(42, 64), (33, 66), (26, 76), (20, 72)]),
    ("carreiro3", "Carreiro da escola (pedonal)", "pedonal", 1, PATH, [(106, 38), (112, 42), (112, 47)]),
]
VALA_LINE = [(-2, 71), (14, 66), (30, 70), (35, 84), (30, 98)]
road_id = np.full((H, W), -1)            # índice em ROADS
def stamp(pts, width, fn):
    for p in smooth(pts, 24):
        r = width / 2.0
        for yy in range(int(p[1] - r - 1), int(p[1] + r + 2)):
            for xx in range(int(p[0] - r - 1), int(p[0] + r + 2)):
                if 0 <= xx < W and 0 <= yy < H and math.hypot(xx + 0.5 - p[0], yy + 0.5 - p[1]) <= r + 0.15:
                    fn(xx, yy)
def set_vala(x, y): surf[y, x] = VALA
stamp(VALA_LINE, 2, set_vala)
for ri in sorted(range(len(ROADS)), key=lambda i: {"pedonal": 0, "beco": 1, "terra": 2, "secundaria": 3, "principal": 4}[ROADS[i][2]]):
    rid, name, klass, width, s, pts = ROADS[ri]
    def put(x, y, ri=ri, s=s, klass=klass):
        if surf[y, x] == VALA or (surf[y, x] == BRIDGE):
            surf[y, x] = BRIDGE; road_id[y, x] = ri; return
        surf[y, x] = s; road_id[y, x] = ri
    stamp(pts, width, put)
def culdesac(x, y, r, s, ri):
    for yy in range(y - r, y + r + 1):
        for xx in range(x - r, x + r + 1):
            if 0 <= xx < W and 0 <= yy < H and math.hypot(xx - x, yy - y) <= r + 0.3 and surf[yy, xx] != VALA:
                surf[yy, xx] = s; road_id[yy, xx] = ri
culdesac(44, 86, 3, ASPHALT, 2); culdesac(116, 15, 3, DROAD, 3); culdesac(106, 38, 3, DROAD, 7); culdesac(88, 4, 2, DROAD, 8)
is_road = road_id >= 0

# ---------------------------------------------------------------- espaços públicos e áreas especiais
area = np.full((H, W), "", dtype=object)
def blob(cx, cy, rx, ry, s, tag, rough=0.35, keep_roads=True):
    for y in range(H):
        for x in range(W):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 + (N2[y, x] - 0.5) * rough
            if d <= 1 and surf[y, x] not in (VALA, BRIDGE) and not (keep_roads and is_road[y, x]):
                surf[y, x] = s; area[y, x] = tag
def rot_rect(cx, cy, w, h, ang, s, tag):
    ca, sa = math.cos(ang), math.sin(ang)
    for y in range(H):
        for x in range(W):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy; u, v = dx * ca + dy * sa, -dx * sa + dy * ca
            if abs(u) <= w / 2 and abs(v) <= h / 2 and not is_road[y, x]:
                surf[y, x] = s; area[y, x] = tag
blob(73, 41, 7.5, 6.0, PAVE, "praca", 0.25)                 # Praça (ponto de encontro, spawn)
blob(26, 37, 9.0, 7.0, DIRT, "mercado", 0.5)                # terreiro do mercado informal
blob(50, 55, 5.5, 4.0, GRAVEL, "parque", 0.4)               # estacionamento dos prédios
blob(70, 30, 4.0, 3.0, GRAVEL, "parque", 0.4)               # estacionamento do comércio
blob(37, 12, 8.0, 6.0, SOIL, "obra", 0.5)                   # estaleiro de obra
rot_rect(94, 70, 20, 12, math.radians(-14), SAND, "campo_borda")
rot_rect(94, 70, 16, 9, math.radians(-14), PITCH, "campo")
blob(112, 76, 5, 4, SOIL, "largo", 0.6)                     # largo de terra na periferia

# passeios: ao longo do asfalto, só onde há comércio/prédios; fora disso berma irregular de brita/terra
asph = (surf == ASPHALT)
for y in range(H):
    for x in range(W):
        if is_road[y, x] or surf[y, x] in (VALA, BRIDGE) or area[y, x] in ("campo", "campo_borda"): continue
        near = asph[max(0, y - 1):y + 2, max(0, x - 1):x + 2].any()
        near2 = asph[max(0, y - 2):y + 3, max(0, x - 2):x + 3].any()
        z = zone_at(x, y)
        if near and z in ("centro", "predios"): surf[y, x] = PAVE
        elif near and z == "mercado": surf[y, x] = PAVE if N2[y, x] < 0.55 else DIRT       # passeio partido
        elif near: surf[y, x] = GRAVEL if N2[y, x] < 0.6 else DIRT
        elif near2 and z == "centro" and N2[y, x] < 0.7: surf[y, x] = PAVE
# margens da vala: solo e capim
vala = (surf == VALA)
for y in range(H):
    for x in range(W):
        if not is_road[y, x] and surf[y, x] not in (VALA, BRIDGE) and vala[max(0, y - 1):y + 2, max(0, x - 1):x + 2].any():
            surf[y, x] = DRY if N2[y, x] < 0.6 else SOIL

# ---------------------------------------------------------------- edifícios (pegada EXTERIOR; o interior é independente)
PAL = {"shop": (224, 186, 92), "restaurant": (232, 218, 186), "office": (124, 152, 214), "residential": (226, 150, 160),
       "apartment": (132, 196, 150), "service": (200, 170, 210), "school": (236, 200, 120), "workshop": (170, 170, 180)}
B = []   # dict(id,name,type,x,y,w,d,floors,face,status)
def blocked_for_building(x, y, margin=1):
    for yy in range(y - margin, y + margin + 1):
        for xx in range(x - margin, x + margin + 1):
            if not (0 <= xx < W and 0 <= yy < H): return True
            if is_road[yy, xx] or surf[yy, xx] in (VALA, BRIDGE) or area[yy, xx] in ("praca", "campo", "campo_borda", "mercado", "parque", "obra") or occ[yy, xx]:
                return True
    return False
occ = np.zeros((H, W), bool)          # ocupado por edifício (com 1 tile de folga)
solid = np.zeros((H, W), int) - 1     # índice do edifício
def entrance_tile(b):
    if b["face"] == "front": return (b["x"] + b["ent"], b["y"] + b["d"])        # tile a sul da porta
    return (b["x"] + b["w"], b["y"] + b["ent"])                                  # tile a este da porta
def fits(b):
    for yy in range(b["y"], b["y"] + b["d"]):
        for xx in range(b["x"], b["x"] + b["w"]):
            if blocked_for_building(xx, yy): return False
    ex, ey = entrance_tile(b)
    if not (0 <= ex < W and 0 <= ey < H) or occ[ey, ex] or surf[ey, ex] == VALA: return False
    return True
def place(bid, name, typ, x, y, w, d, floors, face, status, ent=None):
    b = dict(id=bid, name=name, type=typ, x=x, y=y, w=w, d=d, floors=floors, face=face, status=status,
             ent=(ent if ent is not None else (w // 2 if face == "front" else d // 2)))
    for rad in range(0, 9):                                  # procura a posição válida mais próxima da pretendida
        cands = [(dx, dy) for dx in range(-rad, rad + 1) for dy in range(-rad, rad + 1) if max(abs(dx), abs(dy)) == rad]
        cands.sort(key=lambda c: c[0] ** 2 + c[1] ** 2)
        for dx, dy in cands:
            b["x"], b["y"] = x + dx, y + dy
            if fits(b):
                i = len(B); B.append(b)
                for yy in range(b["y"] - 1, b["y"] + b["d"] + 1):
                    for xx in range(b["x"] - 1, b["x"] + b["w"] + 1):
                        if 0 <= xx < W and 0 <= yy < H: occ[yy, xx] = True
                for yy in range(b["y"], b["y"] + b["d"]):
                    for xx in range(b["x"], b["x"] + b["w"]): solid[yy, xx] = i
                ex, ey = entrance_tile(b); occ[ey, ex] = False
                return b
    print("AVISO: não coube", bid); return None
E, N_, RSV = "existente", "novo (este marco)", "lote reservado"
place("mercearia", "Mercearia Girassol", "shop", 55, 40, 5, 4, 2, "side", E)          # tem 2 portas: frente (sul) e lado (este)
place("escritorio", "Escritório Atlântico", "office", 56, 27, 4, 5, 3, "side", E)
place("restaurante", "Restaurante Maianga", "restaurant", 72, 30, 3, 4, 2, "front", E)
place("casa", "Casa Mussulo", "residential", 78, 13, 3, 4, 1, "front", E)
place("predio_kilamba", "Prédio Kilamba (6 apart.)", "apartment", 32, 56, 6, 4, 3, "side", N_)
place("farmacia", "Farmácia", "service", 57, 34, 3, 3, 1, "side", RSV)
place("padaria", "Padaria", "shop", 77, 34, 3, 3, 1, "front", RSV)
place("banco", "Banco / Multicaixa", "service", 58, 19, 3, 3, 1, "side", RSV)
place("bar", "Bar / Quiosque", "restaurant", 80, 44, 2, 2, 1, "front", RSV)
place("oficina", "Oficina", "workshop", 30, 42, 5, 4, 1, "front", RSV)
place("armazem", "Armazém do mercado", "shop", 13, 30, 4, 3, 1, "side", RSV)
place("escola", "Escola", "school", 108, 38, 7, 5, 2, "front", RSV)
place("predio_b", "Prédio B", "apartment", 50, 61, 6, 4, 3, "front", RSV)
place("predio_c", "Prédio C", "apartment", 49, 77, 6, 4, 4, "front", RSV)
place("salao", "Salão / Igreja", "service", 116, 26, 5, 6, 1, "front", RSV)
# casas: lotes ao longo das ruas de terra e becos do bairro (posição com variação, frente a sul ou a este)
house_spots = [(70, 15), (86, 14), (95, 17), (101, 13), (109, 11), (119, 9), (73, 26), (89, 27), (94, 30), (103, 27),
               (110, 22), (79, 36), (89, 40), (96, 44), (84, 6), (97, 5), (104, 42), (120, 18), (76, 5), (112, 30)]
for i, (hx, hy) in enumerate(house_spots):
    w, d = rng.choice([(3, 3), (3, 4), (4, 3), (3, 3)])
    place(f"casa_{i + 2:02d}", f"Casa {i + 2}", "residential", hx + rng.randint(-1, 1), hy + rng.randint(-1, 1), w, d, 1 if rng.random() < 0.8 else 2,
          rng.choice(["front", "front", "side"]), RSV)
for i, (hx, hy) in enumerate([(10, 78), (24, 84), (8, 88), (112, 68), (122, 80), (10, 58)]):   # areal e periferia: reserva
    place(f"casa_x{i + 1}", f"Casa (futura)", "residential", hx, hy, 3, 3, 1, "front", RSV)

# quintais (terreno misto à volta das casas) e carreiro da porta até à via mais próxima
walk_cost = np.ones((H, W))
def free(x, y): return 0 <= x < W and 0 <= y < H and solid[y, x] < 0 and surf[y, x] not in WALK_BLOCK
for i, b in enumerate(B):
    if b["type"] == "residential":
        for yy in range(b["y"] - 2, b["y"] + b["d"] + 2):
            for xx in range(b["x"] - 2, b["x"] + b["w"] + 2):
                if 0 <= xx < W and 0 <= yy < H and solid[yy, xx] < 0 and not is_road[yy, xx] and surf[yy, xx] not in (VALA, BRIDGE, PAVE) and area[yy, xx] == "":
                    surf[yy, xx] = YARD; area[yy, xx] = "quintal"
    elif b["type"] == "apartment":
        for yy in range(b["y"] - 1, b["y"] + b["d"] + 2):
            for xx in range(b["x"] - 1, b["x"] + b["w"] + 2):
                if 0 <= xx < W and 0 <= yy < H and solid[yy, xx] < 0 and not is_road[yy, xx] and surf[yy, xx] not in (VALA, BRIDGE):
                    surf[yy, xx] = CONCRETE
def path_to_road(start):
    """Dijkstra da porta até ao tile de via mais próximo; devolve a lista de tiles."""
    pq = [(0, start)]; came = {start: None}; dist = {start: 0}
    while pq:
        dcur, cur = heapq.heappop(pq)
        if is_road[cur[1], cur[0]] or surf[cur[1], cur[0]] == PAVE:
            out = []
            while cur is not None: out.append(cur); cur = came[cur]
            return out
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cur[0] + dx, cur[1] + dy)
            if not free(*n): continue
            nd = dcur + 1 + N2[n[1], n[0]] * 1.5                 # ruído -> carreiros ligeiramente tortos
            if nd < dist.get(n, 1e9): dist[n] = nd; came[n] = cur; heapq.heappush(pq, (nd, n))
    return None
door_paths = {}
for i, b in enumerate(B):
    p = path_to_road(entrance_tile(b))
    if p is None: print("AVISO: porta sem acesso", b["id"]); continue
    door_paths[b["id"]] = p
    for (x, y) in p:
        if not is_road[y, x] and surf[y, x] != PAVE:
            surf[y, x] = PATH if zone_at(x, y) not in ("centro", "predios") else PAVE
            area[y, x] = "acesso"
is_path = (surf == PATH) | (area == "acesso")

# ---------------------------------------------------------------- adereços (nunca em vias, carreiros, portas ou campo)
PROPS = []   # (tipo, x, y)
taken = np.zeros((H, W), bool)
ENT = {entrance_tile(b) for b in B}
def can_prop(x, y):
    if not (0 <= x < W and 0 <= y < H) or taken[y, x] or solid[y, x] >= 0 or is_road[y, x] or is_path[y, x]: return False
    if surf[y, x] in (VALA, BRIDGE, PITCH) or (x, y) in ENT: return False
    for ex, ey in ENT:
        if abs(ex - x) <= 1 and abs(ey - y) <= 1: return False
    return True
def add_prop(t, x, y):
    if can_prop(x, y): PROPS.append((t, x, y)); taken[y, x] = True; return True
    return False
tree_density = {"periferia": 0.085, "residencial": 0.03, "areal": 0.012, "predios": 0.02, "centro": 0.004, "mercado": 0.008, "obras": 0.006}
for y in range(H):
    for x in range(W):
        z = zone_at(x, y)
        if area[y, x] in ("mercado", "parque", "obra", "campo_borda", "largo"): continue
        dens = tree_density[z] * (2.2 if N3[y, x] > 0.6 else 0.5)
        if area[y, x] == "praca": dens = 0.06 if N2[y, x] > 0.6 else 0.0
        if area[y, x] == "quintal": dens = 0.05
        if surf[y, x] in (GRASS, DRY, YARD, SAND, SOIL, DIRT, PAVE) and rng.random() < dens:
            add_prop("palmeira" if (z in ("areal",) or (z == "centro" and rng.random() < 0.5)) else ("arbusto" if rng.random() < 0.3 else "arvore"), x, y)
def along(pts, step, off, t, cond=lambda x, y: True):
    sm = smooth(pts, 30); acc = 0; last = sm[0]
    for i in range(1, len(sm)):
        seg = sm[i] - sm[i - 1]; L = float(np.hypot(*seg)); acc += L
        if acc >= step and L > 0:
            acc = 0; nrm = np.array([-seg[1], seg[0]]) / L
            for side in (1, -1):
                p = sm[i] + nrm * off * side; x, y = int(p[0]), int(p[1])
                if 0 <= x < W and 0 <= y < H and cond(x, y): add_prop(t, x, y)
along(ROADS[0][5], 9, 3.4, "poste"); along(ROADS[1][5], 8, 2.9, "candeeiro"); along(ROADS[2][5], 9, 2.9, "candeeiro")
along(ROADS[3][5], 11, 2.6, "poste"); along(ROADS[4][5], 12, 2.6, "poste")
for (cx, cy) in [(22, 33), (25, 34), (28, 33), (23, 37), (26, 38), (29, 37), (31, 40), (21, 41), (25, 41), (30, 34), (19, 36), (27, 30)]:
    add_prop("banca", cx + rng.randint(0, 1), cy + rng.randint(0, 1))                     # bancas do mercado (filas tortas)
for (cx, cy) in [(60, 50), (67, 51), (75, 52), (48, 49), (36, 50)]: add_prop("banca", cx, cy)   # vendedores de rua na avenida
for (cx, cy) in [(70, 39), (76, 39), (70, 44), (76, 44)]: add_prop("banco", cx, cy)       # bancos da praça
for (cx, cy) in [(48, 54), (51, 54), (49, 57), (52, 56), (69, 30), (71, 31)]: add_prop("carro", cx, cy)
for (cx, cy) in [(85, 72), (103, 68)]: PROPS.append(("baliza", cx, cy))
fences = []   # segmentos (x0,y0,x1,y1) em coordenadas de vértice
def fence_rect(x0, y0, x1, y1, gap=None):
    for x in range(x0, x1):
        for yy in (y0, y1):
            if gap and (x, yy) in gap: continue
            fences.append((x, yy, x + 1, yy))
    for y in range(y0, y1):
        for xx in (x0, x1):
            if gap and (xx, y) in gap: continue
            fences.append((xx, y, xx, y + 1))
fence_rect(31, 8, 43, 17, gap={(36, 17), (37, 17)})                                       # tapume da obra (portão a sul)
for b in B:
    if b["type"] == "residential" and b["id"] != "casa" and rng.random() < 0.55:          # muro/vedação do quintal (aberto na porta)
        ex, ey = entrance_tile(b); x0, y0, x1, y1 = b["x"] - 1, b["y"] - 1, b["x"] + b["w"] + 1, b["y"] + b["d"] + 1
        gap = {(ex, y1), (ex + 1, y1), (x1, ey), (x1, ey + 1)}
        seg_ok = lambda xa, ya, xb, yb: all(0 <= v[0] < W and 0 <= v[1] < H and not is_road[v[1], v[0]] for v in ((xa, ya), (max(xa - 1, 0), max(ya - 1, 0))))
        n0 = len(fences); fence_rect(x0, y0, x1, y1, gap)
        fences[n0:] = [s for s in fences[n0:] if seg_ok(*s)]

EMPTY_PLOTS = [(8, 12, 7, 5), (18, 4, 6, 5), (46, 4, 7, 6), (48, 14, 6, 5), (4, 26, 6, 5), (4, 58, 5, 5), (14, 56, 5, 4), (30, 86, 6, 6), (60, 84, 8, 7), (120, 52, 6, 6)]
# ---------------------------------------------------------------- validação (o que o servidor também validará)
walk = np.zeros((H, W), bool)
for y in range(H):
    for x in range(W): walk[y, x] = free(x, y) and not (taken[y, x] and any(p[0] in ("banca", "carro", "arvore", "palmeira") and p[1] == x and p[2] == y for p in PROPS))
SPAWN = (73, 42)
def dijkstra(src):
    dist = np.full((H, W), np.inf); dist[src[1], src[0]] = 0; pq = [(0.0, src)]
    while pq:
        d, (x, y) = heapq.heappop(pq)
        if d > dist[y, x]: continue
        for dx, dy, c in ((1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and walk[ny, nx] and (dx == 0 or dy == 0 or (walk[y, nx] and walk[ny, x])):
                nd = d + c
                if nd < dist[ny, nx]: dist[ny, nx] = nd; heapq.heappush(pq, (nd, (nx, ny)))
    return dist
D0 = dijkstra(SPAWN)
errs = []
for b in B:
    ex, ey = entrance_tile(b)
    if not np.isfinite(D0[ey, ex]): errs.append(f"entrada de {b['id']} inalcançável")
for t, x, y in PROPS:
    if t != "baliza" and (is_road[y, x] or is_path[y, x] or (x, y) in ENT): errs.append(f"adereço {t} a tapar caminho em {x},{y}")
unreach = int((walk & ~np.isfinite(D0)).sum())
HUBS = [("Praça (spawn)", SPAWN), ("Mercearia / R. do Comércio", (61, 42)), ("Escritório", (61, 29)), ("Restaurante", (73, 35)),
        ("Mercado informal", (25, 36)), ("Prédio Kilamba", (39, 58)), ("Casa Mussulo", entrance_tile(next(b for b in B if b["id"] == "casa"))),
        ("Campo de futebol", (94, 62)), ("Largo da periferia", (112, 76)), ("Areal", (16, 82))]
hub_d = {}
for n, p in HUBS:
    dd = dijkstra(p); hub_d[n] = {m: float(dd[q[1], q[0]]) for m, q in HUBS}
cnt = {NAMES[s]: int((surf == s).sum()) for s in NAMES}
outdoor_walk = int(walk.sum())
stats = dict(tiles=W * H, size_m=[W * TILE_M, H * TILE_M], walkable_outdoor_tiles=outdoor_walk, unreachable_walkable_tiles=unreach,
             buildings={s: sum(1 for b in B if b["status"] == s) for s in (E, N_, RSV)}, building_tiles=int((solid >= 0).sum()),
             road_tiles=int(is_road.sum()), surfaces=cnt, errors=errs,
             cross_map_s={"oeste-este (avenida)": round(float(dijkstra((1, 52))[44, 126]) / SPEED_TILES_S, 1)},
             hub_seconds={n: {m: round(v / SPEED_TILES_S) for m, v in d.items()} for n, d in hub_d.items()},
             residential_units=dict(agora=1 + 6, com_lotes=sum(1 for b in B if b["type"] == "residential") + 6 * sum(1 for b in B if b["type"] == "apartment")))
(OUT / "world_layout_stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1))
json.dump(dict(size=[W, H], roads=[dict(id=r[0], name=r[1], klass=r[2], width=r[3], points=r[5]) for r in ROADS], vala=VALA_LINE,
               buildings=B, props=PROPS, spawn=SPAWN), open(OUT / "world_layout_data.json", "w"), ensure_ascii=False)

# ---------------------------------------------------------------- desenho
def font(sz, bold=True):
    try: return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/DejaVuSans{'-Bold' if bold else ''}.ttf", sz)
    except Exception: return ImageFont.load_default()
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c)
def tile_col(x, y):
    s = surf[y, x]; c = COL[s]
    j = 0.93 + 0.14 * N2[y, x] + ((x * 7 + y * 13) % 5) * 0.012
    if s == YARD: c = COL[GRASS] if N2[y, x] > 0.62 else (COL[SOIL] if N2[y, x] < 0.3 else COL[YARD])
    if s == PAVE and (x + y) % 2: j *= 0.96
    return shade(c, j)

def draw_plan(path, schematic=False):
    S = 12; LEG = 430
    im = Image.new("RGB", (W * S + LEG, H * S + 70), (24, 26, 24)); d = ImageDraw.Draw(im, "RGBA"); oy = 50
    for y in range(H):
        for x in range(W):
            c = tile_col(x, y)
            if schematic:
                g = int(0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]); t = ZONES[ZKEYS[zone[y, x]]]["tint"]
                c = tuple(int(g * 0.45 + t[i] * 0.55) for i in range(3))
            d.rectangle([x * S, oy + y * S, x * S + S - 1, oy + y * S + S - 1], fill=c)
    if not schematic:                                         # marcações da avenida
        sm = smooth(ROADS[0][5], 40)
        for i in range(0, len(sm) - 1, 3): d.line([sm[i][0] * S, oy + sm[i][1] * S, sm[i + 1][0] * S, oy + sm[i + 1][1] * S], fill=(230, 200, 90), width=2)
        for (cx, cy, ang) in [(94, 70, math.radians(-14))]:  # linhas do campo
            ca, sa = math.cos(ang), math.sin(ang)
            def P(u, v): return ((cx + u * ca - v * sa) * S, oy + (cy + u * sa + v * ca) * S)
            d.line([P(-8, -4.5), P(8, -4.5), P(8, 4.5), P(-8, 4.5), P(-8, -4.5)], fill=(245, 240, 225), width=2)
            d.line([P(0, -4.5), P(0, 4.5)], fill=(245, 240, 225), width=2)
            m = P(0, 0); d.ellipse([m[0] - 14, m[1] - 14, m[0] + 14, m[1] + 14], outline=(245, 240, 225), width=2)
    else:
        klass_col = {"principal": (255, 255, 255), "secundaria": (255, 220, 120), "terra": (190, 120, 60), "beco": (240, 150, 90), "pedonal": (120, 255, 160)}
        for rid, name, klass, width, s, pts in ROADS:
            sm = smooth(pts, 30); xy = [(p[0] * S, oy + p[1] * S) for p in sm]
            if klass == "pedonal":
                for i in range(0, len(xy) - 1, 2): d.line([xy[i], xy[i + 1]], fill=klass_col[klass], width=3)
            else: d.line(xy, fill=klass_col[klass], width={"principal": 9, "secundaria": 6, "terra": 5, "beco": 3}[klass], joint="curve")
        sm = smooth(VALA_LINE, 30); d.line([(p[0] * S, oy + p[1] * S) for p in sm], fill=(70, 170, 220), width=5)
    for (px, py, pw, ph) in EMPTY_PLOTS:
        for k in range(0, pw * S, 6): d.line([px * S + k, oy + py * S, px * S + k + 3, oy + py * S], fill=(250, 250, 250, 200)); d.line([px * S + k, oy + (py + ph) * S, px * S + k + 3, oy + (py + ph) * S], fill=(250, 250, 250, 200))
        for k in range(0, ph * S, 6): d.line([px * S, oy + py * S + k, px * S, oy + py * S + k + 3], fill=(250, 250, 250, 200)); d.line([(px + pw) * S, oy + py * S + k, (px + pw) * S, oy + py * S + k + 3], fill=(250, 250, 250, 200))
        d.text(((px + pw / 2) * S, oy + (py + ph / 2) * S), "lote\nvazio", fill=(250, 250, 250), anchor="mm", font=font(9, False), align="center")
    for (x0, y0, x1, y1) in fences: d.line([x0 * S, oy + y0 * S, x1 * S, oy + y1 * S], fill=(92, 70, 52), width=2)
    for t, x, y in PROPS:
        cx, cy = x * S + S // 2, oy + y * S + S // 2
        if t in ("arvore", "palmeira"): d.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], fill=(44, 112, 52) if t == "arvore" else (70, 140, 70), outline=(24, 64, 30))
        elif t == "arbusto": d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(70, 140, 64))
        elif t == "banca": d.rectangle([cx - 5, cy - 5, cx + 5, cy + 5], fill=rng.choice([(214, 70, 60), (60, 120, 210), (240, 190, 60), (240, 240, 240)]), outline=(40, 30, 30))
        elif t == "carro": d.rectangle([cx - 6, cy - 4, cx + 6, cy + 4], fill=rng.choice([(190, 40, 40), (230, 230, 235), (40, 70, 150)]), outline=(20, 20, 20))
        elif t in ("poste", "candeeiro"): d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=(250, 230, 120) if t == "candeeiro" else (60, 50, 40))
        elif t == "banco": d.rectangle([cx - 5, cy - 2, cx + 5, cy + 2], fill=(140, 90, 50))
        elif t == "baliza": d.rectangle([cx - 2, cy - 8, cx + 2, cy + 8], outline=(255, 255, 255), width=2)
    f9, f11, f13, f18 = font(10), font(11), font(13), font(19)
    for b in B:
        col = PAL[b["type"]]; x0, y0, x1, y1 = b["x"] * S, oy + b["y"] * S, (b["x"] + b["w"]) * S, oy + (b["y"] + b["d"]) * S
        if b["status"] == RSV:
            d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=col + (90,), outline=col + (255,), width=2)
            for k in range(0, (b["w"] + b["d"]) * S, 8): d.line([x0 + k, y0, x0 + k - (y1 - y0), y1], fill=col + (150,), width=1)
            d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=shade(col, 0.6) + (255,), width=2)
        else:
            d.rectangle([x0 + 3, y0 + 3, x1 + 2, y1 + 2], fill=(0, 0, 0, 90))
            d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=col, outline=(30, 24, 24), width=2)
            d.rectangle([x0 + 4, y0 + 4, x1 - 5, y1 - 5], outline=shade(col, 0.75), width=2)
        ex, ey = entrance_tile(b); d.rectangle([ex * S + 2, oy + ey * S + 2, ex * S + S - 3, oy + ey * S + S - 3], fill=(255, 255, 255, 230), outline=(180, 30, 30))
        d.text(((x0 + x1) / 2, (y0 + y1) / 2), str(b["floors"]), fill=(20, 20, 20), anchor="mm", font=f11)
    labels = [b for b in B if b["status"] != RSV or b["type"] != "residential"]
    for b in labels:
        d.text(((b["x"] + b["w"] / 2) * S, oy + b["y"] * S - 8), b["name"], fill=(255, 255, 255), anchor="mm", font=f9, stroke_width=2, stroke_fill=(0, 0, 0))
    place_lbl = [("PRAÇA", 73, 41), ("MERCADO\nINFORMAL", 26, 36), ("CAMPO DE FUTEBOL", 94, 77), ("OBRA", 37, 12), ("P", 50, 55), ("P", 70, 30), ("largo", 112, 76),
                 ("pontão", 21, 66), ("pontão", 30, 73)]
    for t, x, y in place_lbl: d.multiline_text((x * S, oy + y * S), t, fill=(255, 250, 200), anchor="mm", font=f11, stroke_width=2, stroke_fill=(0, 0, 0), align="center")
    if schematic:
        zl = {"centro": (66, 59), "mercado": (16, 24), "obras": (22, 5), "residencial": (100, 3), "predios": (60, 82), "periferia": (116, 58), "areal": (10, 93)}
        for k, (x, y) in zl.items():
            d.text((x * S, oy + y * S), ZONES[k]["name"].upper(), fill=(255, 255, 255), anchor="mm", font=f18, stroke_width=3, stroke_fill=(0, 0, 0))
        for n, (x, y) in HUBS:
            d.ellipse([x * S - 9, oy + y * S - 9, x * S + 9, oy + y * S + 9], outline=(255, 60, 60), width=3)
        for t, x, y, a in [("→ expansão este: avenida continua", 127, 47, "rm"), ("← expansão oeste", 9, 56, "lm"), ("↑ saída norte (futura)", 73, 2, "lm"),
                           ("→ trilho: futura zona rural / praia", 113, 94, "rm")]:
            d.text((x * S, oy + y * S), t, fill=(255, 235, 130), anchor=a, font=f11, stroke_width=2, stroke_fill=(0, 0, 0))
    else:
        for rid, name, klass, width, s, pts in ROADS:
            if klass in ("principal", "secundaria", "terra"):
                sm = smooth(pts, 10); p = sm[len(sm) // 2 + (6 if rid == "avenida" else 0)]
                d.text((p[0] * S, oy + p[1] * S), name.split(" (")[0], fill=(255, 255, 255), anchor="mm", font=f9, stroke_width=2, stroke_fill=(0, 0, 0))
    d.text((8, 12), ("PROPOSTA — bairros, hierarquia de vias, pontos de encontro e expansão" if schematic else
                     "PROPOSTA — planta do bairro (128 × 96 tiles = 256 × 192 m). Vista de cima; no jogo a vista é isométrica."), fill=(255, 220, 110), font=f18)
    lx = W * S + 16; ly = oy
    def leg_title(t):
        nonlocal ly; d.text((lx, ly), t, fill=(255, 220, 110), font=f13); ly += 22
    def leg_item(col, t, shape="box"):
        nonlocal ly
        if shape == "box": d.rectangle([lx, ly, lx + 18, ly + 12], fill=col, outline=(0, 0, 0))
        elif shape == "line": d.line([lx, ly + 6, lx + 18, ly + 6], fill=col, width=4)
        elif shape == "dot": d.ellipse([lx + 3, ly, lx + 15, ly + 12], fill=col)
        d.text((lx + 26, ly - 1), t, fill=(235, 235, 235), font=font(11, False)); ly += 18
    if schematic:
        leg_title("Bairros")
        for k in ZKEYS: leg_item(ZONES[k]["tint"], f"{ZONES[k]['name']}"); d.text((lx + 26, ly - 3), ZONES[k]["purpose"], fill=(170, 170, 170), font=font(9, False)); ly += 13
        ly += 8; leg_title("Vias")
        for k, c, t in [("principal", (255, 255, 255), "Principal — asfalto, 4 tiles (8 m), passeios"), ("secundaria", (255, 220, 120), "Secundária — asfalto, 3 tiles"),
                        ("terra", (190, 120, 60), "Rua de terra batida — 2–3 tiles"), ("beco", (240, 150, 90), "Beco — terra, 2 tiles"),
                        ("pedonal", (120, 255, 160), "Carreiro / atalho pedonal — 1 tile"), ("vala", (70, 170, 220), "Vala de drenagem (só nos pontões)")]:
            leg_item(c, t, "line")
        ly += 8; leg_title("Sem saída / becos")
        for t in ["Rua dos Prédios (rotunda de retorno)", "Rua do Bairro (largo no fim)", "Beco do pátio · Beco norte", "Rua do Mercado termina na obra"]:
            d.text((lx, ly), "• " + t, fill=(220, 220, 220), font=font(11, False)); ly += 16
        ly += 8; leg_title("Pontos de encontro (círculos)")
        for n, _ in HUBS: d.text((lx, ly), "○ " + n, fill=(255, 150, 150), font=font(11, False)); ly += 16
    else:
        leg_title("Terreno")
        for s in (ASPHALT, DROAD, PATH, PAVE, CONCRETE, GRAVEL, DIRT, SOIL, SAND, DRY, GRASS, YARD, PITCH, VALA, BRIDGE):
            leg_item(COL[s], f"{NAMES[s]}  ({100 * (surf == s).sum() / (W * H):.0f}%)")
        ly += 8; leg_title("Edifícios (n.º = pisos, □ branco = porta)")
        for k, t in [("shop", "Comércio"), ("restaurant", "Alimentação"), ("office", "Serviços / escritórios"), ("residential", "Casa (1 unidade)"),
                     ("apartment", "Prédio (várias unidades)"), ("service", "Serviço público"), ("school", "Escola"), ("workshop", "Oficina")]:
            leg_item(PAL[k], t)
        d.rectangle([lx, ly, lx + 18, ly + 12], fill=(120, 120, 120, 90), outline=(200, 200, 200)); d.line([lx + 4, ly + 12, lx + 14, ly], fill=(200, 200, 200))
        d.text((lx + 26, ly - 1), "tracejado = lote reservado (não construído agora)", fill=(235, 235, 235), font=font(11, False)); ly += 26
        leg_title("Adereços")
        for c, t in [((44, 112, 52), "Árvores, palmeiras, arbustos"), ((214, 70, 60), "Bancas / vendedores de rua"), ((250, 230, 120), "Candeeiros"), ((60, 50, 40), "Postes de eletricidade"),
                     ((190, 40, 40), "Carros estacionados"), ((92, 70, 52), "Muros, vedações, tapume da obra")]:
            leg_item(c, t, "dot")
    im.save(path); print(path, im.size)

def draw_iso(path):
    hw, hh, FH = 8, 4, 12
    def P(x, y, h=0): return ((x - y) * hw + H * hw + 20, (x + y) * hh + 70 - h)
    im = Image.new("RGB", ((W + H) * hw + 40, (W + H) * hh + 110), (24, 26, 24)); d = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            d.polygon([P(x, y), P(x + 1, y), P(x + 1, y + 1), P(x, y + 1)], fill=tile_col(x, y))
    items = [(b["x"] + b["w"] + b["y"] + b["d"], "b", b) for b in B if b["status"] != RSV] + [(x + y + 1, "p", (t, x, y)) for t, x, y in PROPS]
    for b in B:
        if b["status"] == RSV:
            pts = [P(b["x"], b["y"]), P(b["x"] + b["w"], b["y"]), P(b["x"] + b["w"], b["y"] + b["d"]), P(b["x"], b["y"] + b["d"])]
            d.polygon(pts, outline=PAL[b["type"]]); d.line([pts[0], pts[2]], fill=PAL[b["type"]])
    for _, kind, it in sorted(items, key=lambda i: i[0]):
        if kind == "b":
            b = it; col = PAL[b["type"]]; x0, y0, x1, y1, h = b["x"], b["y"], b["x"] + b["w"], b["y"] + b["d"], b["floors"] * FH
            d.polygon([P(x0, y1), P(x1, y1), P(x1, y1, h), P(x0, y1, h)], fill=col, outline=(40, 30, 30))
            d.polygon([P(x1, y0), P(x1, y1), P(x1, y1, h), P(x1, y0, h)], fill=shade(col, 0.78), outline=(40, 30, 30))
            d.polygon([P(x0, y0, h), P(x1, y0, h), P(x1, y1, h), P(x0, y1, h)], fill=shade(col, 0.55), outline=(40, 30, 30))
            for n in range(1, b["floors"]):
                d.line([P(x0, y1, n * FH), P(x1, y1, n * FH), P(x1, y0, n * FH)], fill=shade(col, 0.6))
        else:
            t, x, y = it; cx, cy = P(x + 0.5, y + 0.5)
            if t in ("arvore", "palmeira"): d.line([cx, cy, cx, cy - 7], fill=(90, 60, 40), width=2); d.ellipse([cx - 5, cy - 15, cx + 5, cy - 5], fill=(44, 112, 52) if t == "arvore" else (80, 150, 70))
            elif t == "arbusto": d.ellipse([cx - 3, cy - 5, cx + 3, cy], fill=(70, 140, 64))
            elif t == "banca": d.rectangle([cx - 3, cy - 6, cx + 3, cy], fill=rng.choice([(214, 70, 60), (60, 120, 210), (240, 190, 60)]))
            elif t == "carro": d.rectangle([cx - 4, cy - 4, cx + 4, cy], fill=(190, 40, 40))
            elif t in ("poste", "candeeiro"): d.line([cx, cy, cx, cy - 11], fill=(50, 45, 40), width=1); d.point((cx, cy - 12), fill=(255, 240, 150))
    d.text((12, 10), "PROPOSTA — o mesmo bairro na projeção do jogo (blocos = pegadas exteriores; contorno = lote reservado). Desenho, não captura do motor.",
           fill=(255, 220, 110), font=font(15))
    im.save(path); print(path, im.size)

draw_plan(OUT / "world_plan.png"); draw_plan(OUT / "world_zones.png", schematic=True); draw_iso(OUT / "world_iso.png")
print(json.dumps({k: stats[k] for k in ("tiles", "walkable_outdoor_tiles", "unreachable_walkable_tiles", "buildings", "building_tiles", "road_tiles", "errors", "cross_map_s", "residential_units")}, ensure_ascii=False))
print("praça ->", stats["hub_seconds"]["Praça (spawn)"])

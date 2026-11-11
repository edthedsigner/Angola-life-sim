#!/usr/bin/env python3
"""Teste de integracao: arranca o server_python/server.py REAL e liga dois clientes WebSocket independentes (ligações TCP
separadas, sessoes separadas). Usa `websockets` real se instalado; caso contrario o stand-in em tests/shim."""
import asyncio, json, os, subprocess, sys, shutil, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
try:
    import websockets
    SHIM = False
except ImportError:
    sys.path.insert(0, str(ROOT / "tests" / "shim")); import websockets; SHIM = True
PORT = 7791; URI = f"ws://127.0.0.1:{PORT}"
OK = []; FAIL = []
def check(name, cond):
    (OK if cond else FAIL).append(name); print(("PASS " if cond else "FAIL ") + name)

class Bot:
    def __init__(self, ctx, ws): self.ws, self.ctx, self.q = ws, ctx, []
    async def get(self, typ, timeout=3, pred=None):
        end = time.time() + timeout
        while time.time() < end:
            for m in self.q:
                if m.get("type") == typ and (pred is None or pred(m)): self.q.remove(m); return m
            try: self.q.append(json.loads(await asyncio.wait_for(self.ws.recv(), 0.3)))
            except (asyncio.TimeoutError, TimeoutError): pass
        return None
    async def send(self, **m): await self.ws.send(json.dumps(m))
    async def drain(self):
        while True:
            try: self.q.append(json.loads(await asyncio.wait_for(self.ws.recv(), 0.25)))
            except (asyncio.TimeoutError, TimeoutError): return

def start_server(data_dir):
    env = dict(os.environ, ANGOLA_PORT=str(PORT), PYTHONUNBUFFERED="1", ANGOLA_ACTIVITY_SCALE="0.1", ANGOLA_DEV_START_MONEY="30000",
               ANGOLA_WORLD=str(ROOT / "shared" / "data" / "world.json"))
    if SHIM: env["PYTHONPATH"] = str(ROOT / "tests" / "shim")
    p = subprocess.Popen([sys.executable, str(data_dir / "server.py")], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(1.2); return p

async def main():
    tmp = Path(tempfile.mkdtemp()); shutil.copytree(ROOT / "server_python", tmp / "sp"); sp = tmp / "sp"
    srv = start_server(sp)
    try:
        print("websockets:", "STAND-IN (tests/shim)" if SHIM else "REAL")
        async with websockets.connect(URI) as wa, websockets.connect(URI) as wb:
            A, B = Bot("A", wa), Bot("B", wb)
            check("A recebe welcome", (await A.get("welcome")) is not None); check("B recebe welcome", (await B.get("welcome")) is not None)
            await A.send(type="enter_world", character_id="x"); r = await A.get("error"); check("enter_world sem login rejeitado", r is not None)
            await A.send(type="register", username="alice", password="pw1234"); ra = await A.get("auth_response"); check("registo A", ra and ra["success"])
            await B.send(type="register", username="bruno", password="pw1234"); rb = await B.get("auth_response"); check("registo B", rb and rb["success"])
            await A.send(type="register", username="alice", password="x1234"); r = await A.get("auth_response"); check("registo duplicado rejeitado", r and not r["success"])
            await A.send(type="create_character", name="Cedo Demais", appearance={}); r = await A.get("character_created"); check("criar personagem antes da introdução é rejeitado", r and not r["success"])
            for bot in (A, B):
                for s in range(4):
                    await bot.send(type="onboarding_progress", state="story_in_progress", step=s); await bot.get("onboarding_state")
                await bot.send(type="onboarding_progress", state="character_customization", step=3); st = await bot.get("onboarding_state")
            check("história concluída -> character_customization", st and st["state"] == "character_customization")
            await A.send(type="create_character", name="Alice Teste", appearance={"skin_tone": 2, "hair_style": 3, "hair_color": 99, "clothes": 1}, account_id=rb["data"]["account_id"])
            ca = await A.get("character_created"); chA = ca["data"]
            check("personagem A criada (account_id spoofado ignorado)", ca["success"] and chA["account_id"] == ra["data"]["account_id"])
            check("aparência validada/clamped", chA["appearance"] == {"skin_tone": 2, "hair_style": 3, "hair_color": 3, "clothes": 1})
            bg = chA["background"]
            check("background gerado no servidor com família/pais/dinheiro/bens", all(k in bg for k in ("family", "childhood", "starting_circumstances", "family_assets")) and bg["family"]["father_profession"] and chA["money"] == 30000 and bg["starting_circumstances"]["initial_money"] > 0)
            check("começa sem-abrigo sem propriedades", bg["housing"] == {"status": "sem_abrigo", "owned_properties": []})
            await B.send(type="create_character", name="Bruno Teste", appearance={"skin_tone": 0, "hair_style": 1, "hair_color": 0, "clothes": 2})
            chB = (await B.get("character_created"))["data"]
            await B.send(type="enter_world", character_id=chA["id"]); r = await B.get("error"); check("B não pode entrar com personagem de A", r is not None)
            await A.send(type="enter_world", character_id=chA["id"])
            sA = await A.get("spawn_player"); check("A vê-se a si próprio", sA and sA["data"]["name"] == "Alice Teste")
            await B.send(type="enter_world", character_id=chB["id"])
            spB_on_A = await A.get("spawn_player"); check("A vê B com nome e aparência corretos", spB_on_A and spB_on_A["data"]["name"] == "Bruno Teste" and spB_on_A["data"]["appearance"]["hair_style"] == 1)
            check("spawn de B não vaza background", spB_on_A and "background" not in spB_on_A["data"] and "money" not in spB_on_A["data"])
            got = {}
            for _ in range(2):
                m = await B.get("spawn_player"); got[m["data"]["name"]] = m["data"] if m else None
            check("B vê A (aparência skin=2/hair=3) e a si próprio", "Alice Teste" in got and got["Alice Teste"]["appearance"]["skin_tone"] == 2 and "Bruno Teste" in got)
            check("spawn no ponto definido", got["Alice Teste"]["position"] == {"x": 0.0, "y": 40.0})
            await A.send(type="position", x=120.5, y=60.25); m = await B.get("position"); check("B recebe movimento de A", m and (m["x"], m["y"]) == (120.5, 60.25) and m["peer_id"] == spB_on_A["data"]["peer_id"] or (m and m["x"] == 120.5))
            await B.send(type="position", x=-50, y=10); m = await A.get("position"); check("A recebe movimento de B", m and (m["x"], m["y"]) == (-50, 10))
            await A.send(type="position", x=99999, y=-99999); m = await A.get("position_correction"); check("posição fora do mapa rejeitada com correção", m and (m["x"], m["y"]) == (120.5, 60.25))
            await A.send(type="position", x="NaN", y=1); await A.send(type="position", x=300, y=100); m = await B.get("position"); check("posição inválida ignorada", m and m["x"] == 300)
            pidA = spB_on_A["data"]["peer_id"]
        # ligação de A fechou (saiu do bloco `async with` de wa e wb) -> reabrir B para ver o disconnect
    finally:
        pass
    # --- disconnect / reconnect / persistência
    async with websockets.connect(URI) as wb:
        B = Bot("B", wb); await B.get("welcome")
        await B.send(type="login", username="bruno", password="pw1234"); rb = await B.get("auth_response"); chB = rb["data"]["characters"][0]
        check("login B devolve personagem persistida", chB["name"] == "Bruno Teste" and chB["position"] == {"x": -50.0, "y": 10.0})
        await B.send(type="enter_world", character_id=chB["id"]); await B.get("spawn_player")
        async with websockets.connect(URI) as wa:
            A = Bot("A", wa); await A.get("welcome")
            await A.send(type="login", username="alice", password="errada"); r = await A.get("auth_response"); check("password errada rejeitada", r and not r["success"])
            await A.send(type="login", username="alice", password="pw1234"); r = await A.get("auth_response"); chA = r["data"]["characters"][0]
            check("login A: background e posição persistidos", chA["background"]["family"]["father_name"] and chA["position"] == {"x": 300.0, "y": 100.0})
            await A.send(type="enter_world", character_id=chA["id"])
            s = await B.get("spawn_player"); check("B vê A reentrar na posição guardada", s and s["data"]["name"] == "Alice Teste" and s["data"]["position"] == {"x": 300.0, "y": 100.0})
            pid = s["data"]["peer_id"]
            async with websockets.connect(URI) as wa2:   # mesma personagem noutra ligação => substitui sessão
                A2 = Bot("A2", wa2); await A2.get("welcome"); await A2.send(type="login", username="alice", password="pw1234"); await A2.get("auth_response")
                await A2.send(type="enter_world", character_id=chA["id"])
                left = await B.get("player_left", pred=lambda m: m["peer_id"] == pid); check("sessão duplicada: antiga removida (player_left)", left is not None)
                s2 = await B.get("spawn_player", pred=lambda m: m["data"]["name"] == "Alice Teste"); check("sessão duplicada: nova entra", s2 is not None)
                pid2 = s2["data"]["peer_id"]
            left = await B.get("player_left", pred=lambda m: m["peer_id"] == pid2); check("B recebe player_left quando A desliga", left is not None)
    # --- persistência após reinício do servidor
    srv.terminate(); srv.wait(); time.sleep(0.5); srv = start_server(sp)
    async with websockets.connect(URI) as w:
        A = Bot("A", w); await A.get("welcome"); await A.send(type="login", username="alice", password="pw1234"); r = await A.get("auth_response"); c = r["data"]["characters"][0]
        check("persistência após reiniciar servidor (bg+posição+aparência)", c["background"]["family"]["father_name"] == chA["background"]["family"]["father_name"] and c["position"] == {"x": 300.0, "y": 100.0} and c["appearance"]["skin_tone"] == 2)
        await A.send(type="create_character", name="Outra", appearance={}); r = await A.get("character_created"); check("só 1 personagem por conta", r and not r["success"])
    # ---------------- Cenários de onboarding / sessão
    async def open_bot():
        cm = websockets.connect(URI); ws = await cm.__aenter__(); b = Bot("x", ws); b.cm = cm; b.pid = (await b.get("welcome"))["peer_id"]; return b
    async def login(b, u):
        await b.send(type="login", username=u, password="pw1234"); return await b.get("auth_response")
    # A) novo jogador
    b = await open_bot(); await b.send(type="register", username="novo", password="pw1234"); r = await b.get("auth_response")
    check("A: conta nova => onboarding 'new' sem personagem", r["data"]["onboarding"]["state"] == "new" and r["data"]["character"] is None and r["data"]["session_token"])
    tokN = r["data"]["session_token"]
    await b.send(type="onboarding_progress", state="character_customization", step=0); s = await b.get("onboarding_state"); check("A: não pode saltar a história", s["state"] != "character_customization")
    await b.send(type="onboarding_progress", state="story_in_progress", step=1); await b.get("onboarding_state"); await b.cm.__aexit__()
    # C) onboarding interrompido -> retoma no passo certo
    b = await open_bot(); r = await login(b, "novo")
    check("C: retoma em story_in_progress passo 1", r["data"]["onboarding"]["state"] == "story_in_progress" and r["data"]["onboarding"]["story_step"] == 1)
    await b.send(type="onboarding_progress", state="story_in_progress", step=0); s = await b.get("onboarding_state"); check("C: passo nunca recua", s["story_step"] == 1)
    await b.send(type="onboarding_progress", state="story_in_progress", step=3); await b.get("onboarding_state")
    await b.send(type="onboarding_progress", state="character_customization", step=3); await b.get("onboarding_state"); await b.cm.__aexit__()
    b = await open_bot(); r = await login(b, "novo"); check("C: retoma em character_customization", r["data"]["onboarding"]["state"] == "character_customization")
    await b.send(type="create_character", name="Novo Jogador", appearance={"skin_tone": 1, "hair_style": 2}); r = await b.get("character_created")
    check("A: criação conclui onboarding", r["success"]); await b.cm.__aexit__()
    # B) jogador com regresso: login devolve tudo e estado completed (cliente vai direto ao mundo)
    b = await open_bot(); r = await login(b, "novo")
    check("B: regresso => completed + personagem + aparência guardada", r["data"]["onboarding"]["state"] == "completed" and r["data"]["character"]["appearance"]["hair_style"] == 2 and r["data"]["character"]["background"])
    await b.send(type="onboarding_progress", state="story_in_progress", step=0); s = await b.get("onboarding_state"); check("B: completed nunca regride", s["state"] == "completed"); await b.cm.__aexit__()
    # D) sessão existente
    b = await open_bot(); await b.send(type="resume_session", token=tokN); r = await b.get("auth_response")
    check("D: sessão válida restaura perfil completo sem password", r and r["success"] and r.get("resumed") and r["data"]["onboarding"]["state"] == "completed")
    await b.send(type="enter_world", character_id=r["data"]["character"]["id"]); spw = await b.get("spawn_player"); check("D: entra no mundo diretamente", spw is not None)
    await b.send(type="logout"); lo = await b.get("logged_out"); check("D: logout", lo is not None); await b.cm.__aexit__()
    b = await open_bot(); await b.send(type="resume_session", token=tokN); r = await b.get("session_invalid"); check("D: token revogado/inválido => session_invalid", r is not None)
    await b.send(type="resume_session", token="lixo"); r = await b.get("session_invalid"); check("D: token falso rejeitado", r is not None); await b.cm.__aexit__()
    # Migração de contas antigas (sem campo onboarding)
    srv.terminate(); srv.wait()
    accs = json.loads((sp / "data" / "accounts.json").read_text()); chs = json.loads((sp / "data" / "characters.json").read_text())
    for a_ in accs.values(): a_.pop("onboarding", None)
    accs["legado_vazio"] = {"id": "legacy1", "username": "legado_vazio", "password_hash": accs["novo"]["password_hash"], "created_at": "x"}
    (sp / "data" / "accounts.json").write_text(json.dumps(accs)); time.sleep(0.4); srv = start_server(sp)
    b = await open_bot(); r = await login(b, "novo"); check("migração: conta antiga com personagem => completed (nada apagado)", r["data"]["onboarding"]["state"] == "completed" and r["data"]["character"]["name"] == "Novo Jogador"); await b.cm.__aexit__()
    b = await open_bot(); r = await login(b, "legado_vazio"); check("migração: conta antiga sem personagem => new", r and r["data"]["onboarding"]["state"] == "new"); await b.cm.__aexit__()
    await gameplay_tests(open_bot)
    srv.terminate(); shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{len(OK)} passaram, {len(FAIL)} falharam"); sys.exit(1 if FAIL else 0)
# ---------------------------------------------------------------- gameplay (zones, interiors, needs, economy)
sys.path.insert(0, str(ROOT / "server_python"))
import world as worldmod  # noqa: E402
W = worldmod.load(ROOT / "shared" / "data" / "world.json")


def cell_path(zone, start, goal, doors=None):
    blocked = W.blocked_cells(zone); prev = {start: None}; q = [start]
    while q:
        c = q.pop(0)
        if c == goal: break
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + d[0], c[1] + d[1])
            if n in prev or n in blocked or not W.in_bounds(zone, n) or W.edge_blocked(zone, c, n, doors or {}): continue
            prev[n] = c; q.append(n)
    out = []; c = goal
    while c is not None: out.append(c); c = prev.get(c)
    return out[::-1] if goal in prev else []


async def walk(bot, zone, start_px, goal_cell):
    path = cell_path(zone, W.cell_of(zone, *start_px), goal_cell)
    if not path: print("   ! sem caminho", zone, start_px, goal_cell)
    for c in path[1:]:
        x, y = W.cell_center(zone, *c); await bot.send(type="position", x=x, y=y)
    await bot.drain()
    bad = [m for m in bot.q if m["type"] == "position_correction"]
    if bad: print("   ! correção durante walk", zone, goal_cell, bad[:1])
    bot.q = [m for m in bot.q if m["type"] != "position_correction"]
    return W.cell_center(zone, *goal_cell) if path else start_px


def pt(zone, u, v):
    ox, oy = W.origin(zone); return (ox + (u - v) * 32, oy + (u + v) * 16)


async def last_self(bot):
    await bot.drain(); ss = [m for m in bot.q if m["type"] == "self_state"]
    bot.q = [m for m in bot.q if m["type"] != "self_state"]
    return ss[-1]["data"] if ss else None


async def make_player(open_bot, user, name):
    b = await open_bot(); await b.send(type="register", username=user, password="pw1234"); await b.get("auth_response")
    for st in range(4):
        await b.send(type="onboarding_progress", state="story_in_progress", step=st); await b.get("onboarding_state")
    await b.send(type="onboarding_progress", state="character_customization", step=3); await b.get("onboarding_state")
    await b.send(type="create_character", name=name, appearance={}); ch = (await b.get("character_created"))["data"]
    await b.send(type="enter_world", character_id=ch["id"]); await b.get("spawn_player"); st = await b.get("self_state")
    return b, ch, st


async def gameplay_tests(open_bot):
    G, chG, st = await make_player(open_bot, "gamer", "Gamer Um")
    check("self_state privado: necessidades, dinheiro, relógio, inventário", st and set(st["data"]["needs"]) == {"hunger", "energy", "hygiene", "health"} and st["data"]["game_s"] > 0 and st["data"]["inventory"] == {})
    money0 = st["data"]["money"]
    await G.send(type="ping", t=123); pg = await G.get("pong"); check("ping/pong (latência no debug)", pg and pg["t"] == 123)
    pos = (W.spawn["x"], W.spawn["y"])
    merc = W.buildings["mercearia"]; ent = merc["entrances"][0]
    await G.send(type="enter_building", building="mercearia", entrance="frente"); n = await G.get("notice"); check("entrar longe da porta é rejeitado", n and not n["ok"])
    await G.send(type="position", x=W.cell_center("w", -9, -4)[0], y=W.cell_center("w", -9, -4)[1]); c = await G.get("position_correction"); check("não se pode andar para dentro de um edifício", c is not None)
    pos = await walk(G, "w", pos, W.entrance_tile(merc, ent))
    await G.send(type="enter_building", building="mercearia", entrance="frente"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid)
    check("entra na Mercearia pela porta da frente (zona piso 0)", z and z["zone"] == "b:mercearia:0")
    zs = await G.get("zone_state"); check("recebe estado das portas ao entrar", zs is not None)
    zone = "b:mercearia:0"; pos = (z["x"], z["y"])
    a = W.cell_center(zone, 3, 7); await G.send(type="position", x=a[0], y=a[1]); c = await G.get("position_correction")
    check("atravessar parede interior é rejeitado", c is not None)
    fl = W.floors["mercearia"][0]; bal = next(f for f in fl.furniture if f["id"] == "balcao")
    pos = await walk(G, zone, pos, (7, 4))
    await G.send(type="interact", fid=bal["fid"], action="buy", item="ingredientes", qty=2); n = await G.get("notice"); st = {"data": await last_self(G)}
    check("comprar ingredientes no balcão (dinheiro e inventário no servidor)", n and n["ok"] and st["data"]["inventory"].get("ingredientes") == 2 and st["data"]["money"] == money0 - 1800)
    if not (n and n["ok"]): print("   ", n)
    await G.send(type="interact", fid=bal["fid"], action="buy", item="refeicao"); n = await G.get("notice"); check("artigo que a loja não vende é rejeitado", n and not n["ok"])
    await G.send(type="interact", fid=bal["fid"], action="buy", item="pao"); await G.get("notice"); await G.get("self_state")
    await G.send(type="interact", fid=bal["fid"], action="sell", item="pao"); n = await G.get("notice"); st = {"data": await last_self(G)}
    check("vender pão de volta", n and n["ok"] and "pao" not in st["data"]["inventory"])
    await G.send(type="use_item", item="ingredientes"); n = await G.get("notice"); check("ingredientes crus não se comem", n and not n["ok"])
    # porta interior (v:5:5) e escadas
    pos = await walk(G, zone, pos, (5, 5))
    a = pt(zone, 5.0, 5.5); await G.send(type="position", x=a[0], y=a[1]); await G.drain()
    await G.send(type="door_toggle", key="v:5:5"); n = await G.get("notice"); check("não fecha a porta com alguém no vão", n and not n["ok"])
    pos = await walk(G, zone, pos, (6, 5)); await G.drain()
    await G.send(type="door_toggle", key="v:5:5"); d = await G.get("door_state"); check("fecha porta interior (sincronizado)", d and d["open"] is False)
    a = W.cell_center(zone, 4, 5); await G.send(type="position", x=a[0], y=a[1]); c = await G.get("position_correction"); check("porta fechada bloqueia passagem", c is not None)
    await G.send(type="door_toggle", key="v:5:5"); d = await G.get("door_state"); check("reabre porta", d and d["open"] is True)
    st0 = merc["stairs"][0]
    pos = await walk(G, zone, pos, (st0["x"], st0["y"]))
    await G.send(type="use_stairs", stair=0, dir="up"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); check("sobe ao piso 1 pela escada", z and z["zone"] == "b:mercearia:1")
    await G.send(type="use_stairs", stair=0, dir="up"); n = await G.get("notice"); check("não sobe acima do último piso", n and not n["ok"])
    await G.send(type="use_stairs", stair=0, dir="down"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); check("desce ao piso 0", z and z["zone"] == zone)
    pos = (z["x"], z["y"])
    pos = await walk(G, zone, pos, W.exit_cell(fl, fl.exits["lado"]))
    await G.send(type="exit_building", exit="lado"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid)
    if z is None: print("   ", [m for m in G.q if m["type"] in ("notice", "error")])
    check("sai pela porta lateral (segunda entrada) para a rua certa", z and z["zone"] == "w" and W.cell_of("w", z["x"], z["y"]) == W.entrance_tile(merc, merc["entrances"][1]))
    pos = (z["x"], z["y"])
    # casa privada, arrendamento, cozinhar, dormir
    casa = W.buildings["casa"]; pos = await walk(G, "w", pos, W.entrance_tile(casa, casa["entrances"][0]))
    await G.send(type="enter_building", building="casa", entrance="frente"); n = await G.get("notice"); check("residência privada sem arrendamento: entrada negada", n and not n["ok"])
    await G.send(type="rent", rental="casa", days=3); n = await G.get("notice"); check("opção de arrendamento inválida rejeitada", n and not n["ok"])
    await G.send(type="rent", rental="casa", days=1); n = await G.get("notice"); st = {"data": await last_self(G)}
    check("arrenda quarto (app Imóveis)", n and n["ok"] and st["data"]["housing"]["status"] == "arrendado")
    await G.send(type="enter_building", building="casa", entrance="frente"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); check("com arrendamento entra em casa", z and z["zone"] == "b:casa:0")
    zone = "b:casa:0"; pos = (z["x"], z["y"]); cfl = W.floors["casa"][0]
    fog = next(f for f in cfl.furniture if f["id"] == "fogao"); cama = next(f for f in cfl.furniture if f["id"] == "cama")
    pos = await walk(G, zone, pos, (4, 4)); await G.drain()
    h0 = None
    await G.send(type="self_request"); h0 = (await last_self(G))["needs"]["hunger"]
    await G.send(type="interact", fid=fog["fid"], action="cook"); s_ = await G.get("activity_started"); check("cozinhar começa (atividade temporizada)", s_ is not None)
    dn = await G.get("activity_done", timeout=3); st = {"data": await last_self(G)}
    check("cozinhar consome ingredientes e mata a fome", dn and st["data"]["inventory"].get("ingredientes") == 1 and st["data"]["needs"]["hunger"] > h0)
    pos = await walk(G, zone, pos, (1, 1))
    # segundo jogador: arrenda, entra, tenta usar a mesma cama
    H, chH, _ = await make_player(open_bot, "gamer2", "Gamer Dois")
    await H.send(type="rent", rental="casa", days=7); await H.get("notice")
    hp = await walk(H, "w", (W.spawn["x"], W.spawn["y"]), W.entrance_tile(casa, casa["entrances"][0]))
    await H.send(type="enter_building", building="casa", entrance="frente"); z = await H.get("zone_change", pred=lambda m, _b=H: m["peer_id"] == _b.pid); hp = (z["x"], z["y"])
    hp = await walk(H, zone, hp, (1, 2)); await G.drain(); await H.drain()
    await G.send(type="interact", fid=cama["fid"], action="sleep"); s_ = await G.get("activity_started", timeout=2)
    if s_ is None:
        n = await G.get("notice"); print("   (sleep:", n, ")")
    await H.send(type="interact", fid=cama["fid"], action="sleep"); n = await H.get("notice")
    check("cama ocupada por outro jogador: rejeitado", s_ is not None and n and not n["ok"] and "ocupado" in n["text"])
    await G.get("activity_done", timeout=3)
    await G.send(type="chat", text="Olá vizinho!"); m = await H.get("chat"); check("chat chega a quem está na mesma zona", m and m["text"] == "Olá vizinho!" and m["name"] == "Gamer Um")
    await H.send(type="profile_request"); pr = await H.get("profile"); check("perfil (app Governo) só com dados do próprio", pr and pr["data"]["name"] == "Gamer Dois" and "background" in pr["data"])
    # emprego
    await G.send(type="job_apply", job="assistente"); n = await G.get("notice"); check("candidatura a emprego", n and n["ok"])
    pos = await walk(G, zone, pos, W.exit_cell(cfl, cfl.exits["frente"]))
    await G.send(type="exit_building", exit="frente"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); pos = (z["x"], z["y"])
    await G.send(type="chat", text="Já saí"); m = await H.get("chat", timeout=1); check("chat não chega a outra zona", m is None)
    esc = W.buildings["escritorio"]; pos = await walk(G, "w", pos, W.entrance_tile(esc, esc["entrances"][0]))
    await G.send(type="enter_building", building="escritorio", entrance="frente"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); zone = z["zone"]; pos = (z["x"], z["y"])
    pos = await walk(G, zone, pos, (esc["stairs"][0]["x"], esc["stairs"][0]["y"]))
    await G.send(type="use_stairs", stair=0, dir="up"); z = await G.get("zone_change", pred=lambda m, _b=G: m["peer_id"] == _b.pid); zone = z["zone"]; pos = (z["x"], z["y"])
    efl = W.floors["escritorio"][1]; desk = next(f for f in efl.furniture if f["id"] == "secretaria")
    pos = await walk(G, zone, pos, (desk["x"], desk["y"] - 1)); await G.drain()
    await G.send(type="self_request"); m0 = (await last_self(G))["money"]
    await G.send(type="interact", fid=desk["fid"], action="work"); await G.get("activity_started")
    dn = await G.get("activity_done", timeout=3); st = {"data": await last_self(G)}
    check("trabalhar no posto paga salário e regista no banco", dn and st["data"]["money"] == m0 + 3000 and st["data"]["transactions"][-1]["amount"] == 3000)
    await G.send(type="interact", fid=desk["fid"], action="work"); await G.get("activity_started")
    a = W.cell_center(zone, desk["x"] + 2, desk["y"] - 1); await G.send(type="position", x=a[0], y=a[1])
    dn = await G.get("activity_done"); check("mexer-se interrompe a atividade (sem salário)", dn and dn["action"] is None)
    # persistência da zona + migração de inventário antigo
    for bot in (G, H): await bot.cm.__aexit__()
    await asyncio.sleep(0.3)
    G = await open_bot(); await G.send(type="login", username="gamer", password="pw1234"); r = await G.get("auth_response")
    await G.send(type="enter_world", character_id=r["data"]["character"]["id"]); sp_ = await G.get("spawn_player")
    check("reentrada repõe zona interior guardada", sp_ and sp_["data"]["zone"] == zone)
    await G.cm.__aexit__()


asyncio.run(main())

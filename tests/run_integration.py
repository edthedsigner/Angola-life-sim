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
    env = dict(os.environ, ANGOLA_PORT=str(PORT), PYTHONUNBUFFERED="1", ANGOLA_ACTIVITY_SCALE="0.1", ANGOLA_DEV_START_MONEY="30000", ANGOLA_CALL_RING_SECS="2", ANGOLA_INVITE_TTL="3",
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
    await social_tests(open_bot)
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
    hp = await walk(H, zone, hp, (1, 0)); await G.drain(); await H.drain()
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



# ---------------------------------------------------------------- social (perfis, amizades, convites, presentes, MPs, chamadas)
PRIVATE_KEYS = {"id", "money", "inventory", "needs", "background", "job", "housing", "transactions", "account_id", "privacy", "xp"}


async def last_of(bot, t):
    await bot.drain(); xs = [m for m in bot.q if m["type"] == t]
    bot.q = [m for m in bot.q if m["type"] != t]
    return xs[-1] if xs else None


async def social_tests(open_bot):
    import uuid
    A, chA_, _ = await make_player(open_bot, "soc_ana", "Ana Social")
    B, chB_, _ = await make_player(open_bot, "soc_beto", "Beto Social")
    C, chC_, _ = await make_player(open_bot, "soc_carla", "Carla Social")
    for bot in (A, B, C):
        await asyncio.sleep(0.2); await bot.drain()
    sa = await A.get("social_state") or {}
    await A.send(type="social_state_request"); sa = (await A.get("social_state"))["data"]
    await B.send(type="social_state_request"); sb = (await B.get("social_state"))["data"]
    await C.send(type="social_state_request"); sc = (await C.get("social_state"))["data"]
    pa, pb, pc = sa["pub"], sb["pub"], sc["pub"]
    check("cada personagem tem identificador público opaco (≠ id interno)", pa and pa != chA_["id"] and len(pa) == 10)
    # 1. o que os outros recebem (spawn) não tem id interno nem dados privados
    D = await open_bot(); await D.send(type="login", username="soc_ana", password="pw1234")
    await B.drain()
    await D.cm.__aexit__(); await asyncio.sleep(0.3)
    A = await open_bot(); await A.send(type="login", username="soc_ana", password="pw1234"); r = await A.get("auth_response")
    await A.send(type="enter_world", character_id=r["data"]["character"]["id"]); await A.get("spawn_player")
    sp = await B.get("spawn_player", pred=lambda m: m["data"]["name"] == "Ana Social")
    check("spawn de outro jogador: sem id interno, sem dinheiro/inventário", sp and "id" not in sp["data"] and not (PRIVATE_KEYS & set(sp["data"])) and sp["data"]["pub"] == pa and "level" in sp["data"])
    # 2. perfil público
    await B.send(type="social_profile", target=pa); pr = (await B.get("social_profile"))["data"]
    check("perfil público: nome, aparência, nível, estado, relação", pr["name"] == "Ana Social" and pr["level"] >= 1 and pr["relation"] == "none" and pr["online"])
    check("perfil público nunca expõe dinheiro, inventário, história, emprego, casa, posição nem ids", not ((PRIVATE_KEYS | {"position"}) & set(pr)))
    await B.send(type="social_profile", target="naoexiste"); r = await last_of(B, "social_result"); check("perfil de jogador inexistente rejeitado", r and not r["ok"])
    # 3. amizades
    await A.send(type="friend_request", target=pb); r = await last_of(A, "social_result"); check("pedido de amizade enviado", r and r["ok"])
    n = await B.get("notification"); check("destinatário recebe notificação acionável do pedido", n and n["data"]["kind"] == "friend_request" and n["data"]["actions"] == ["accept", "decline"] and n["data"]["from"]["pub"] == pa)
    await A.send(type="friend_request", target=pb); r = await last_of(A, "social_result"); check("pedido duplicado rejeitado", r and not r["ok"])
    await B.send(type="social_profile", target=pa); pr = (await B.get("social_profile"))["data"]; check("perfil mostra 'pedido recebido'", pr["relation"] == "request_received")
    await B.send(type="friend_accept", target=pa); r = await last_of(B, "social_result"); n = await A.get("notification", pred=lambda m: m["data"]["kind"] == "friend_accepted")
    check("aceitar pedido -> amigos dos dois lados + aviso ao remetente", r and r["ok"] and n)
    await A.send(type="social_profile", target=pb); pr = (await A.get("social_profile"))["data"]; check("perfil mostra 'amigos'", pr["relation"] == "friends")
    await asyncio.sleep(0.6)
    await A.send(type="friend_request", target=pc); await A.get("social_result"); await C.get("notification")
    await A.send(type="friend_cancel", target=pc); r = await last_of(A, "social_result")
    await C.send(type="social_state_request"); st = (await last_of(C, "social_state"))["data"]
    check("cancelar pedido enviado remove-o do destinatário", r and r["ok"] and not st["incoming"])
    await C.send(type="friend_request", target=pa); await C.get("social_result"); await A.drain()
    await A.send(type="friend_decline", target=pc); r = await last_of(A, "social_result"); check("recusar pedido", r and r["ok"])
    await A.send(type="friend_accept", target=pc); r = await last_of(A, "social_result"); check("não aceita pedido já recusado", r and not r["ok"])
    # 4. presentes de dinheiro (atómicos, idempotentes)
    await A.send(type="self_request"); ma = (await last_self(A))["money"]; await B.send(type="self_request"); mb = (await last_self(B))["money"]
    rid = uuid.uuid4().hex
    await A.send(type="gift_money", target=pb, amount=1000, req_id=rid); r = await last_of(A, "social_result")
    n = await B.get("notification", pred=lambda m: m["data"]["kind"] == "gift")
    sa_ = await last_self(A); sb_ = await last_self(B)
    check("presente de dinheiro: debita, credita e notifica", r and r["ok"] and sa_["money"] == ma - 1000 and sb_["money"] == mb + 1000 and n)
    check("presente fica no histórico dos dois", sa_["transactions"][-1]["amount"] == -1000 and sb_["transactions"][-1]["amount"] == 1000)
    await A.send(type="gift_money", target=pb, amount=1000, req_id=rid); r = await last_of(A, "social_result"); sa2 = await last_self(A)
    check("pedido repetido (mesmo req_id) não transfere outra vez", r and r["duplicate"] and sa2["money"] == ma - 1000)
    for bad in (-5, 0, 10.5, "100", 10**9, True):
        await A.send(type="gift_money", target=pb, amount=bad, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result")
        if r["ok"]: break
    sa3 = await last_self(A); check("valores negativos/zero/decimais/texto/excessivos rejeitados", not r["ok"] and sa3["money"] == ma - 1000)
    await A.send(type="gift_money", target=pb, amount=ma, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("não pode oferecer mais do que tem", r and not r["ok"])
    await A.send(type="gift_money", target=pa, amount=10, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("não pode oferecer a si próprio", r and not r["ok"])
    await A.send(type="gift_money", target=pb, amount=10, req_id="x"); r = await last_of(A, "social_result"); check("req_id obrigatório (idempotência)", r and not r["ok"])
    # 5. presentes de artigos (só o que possui)
    await A.send(type="gift_item", target=pb, item="pao", qty=1, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("não oferece artigo que não tem", r and not r["ok"])
    merc = W.buildings["mercearia"]; ap = await walk(A, "w", (W.spawn["x"], W.spawn["y"]), W.entrance_tile(merc, merc["entrances"][0]))
    await A.send(type="enter_building", building="mercearia", entrance="frente"); z = await A.get("zone_change", pred=lambda m, _b=A: m["peer_id"] == _b.pid)
    ap = await walk(A, z["zone"], (z["x"], z["y"]), (7, 4)); bal = next(f for f in W.floors["mercearia"][0].furniture if f["id"] == "balcao")
    await A.send(type="interact", fid=bal["fid"], action="buy", item="pao", qty=2); await A.get("notice")
    await A.send(type="gift_item", target=pb, item="pao", qty=3, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("não oferece mais unidades do que possui", r and not r["ok"])
    await A.send(type="gift_item", target=pb, item="pao", qty=0, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("quantidade inválida rejeitada", r and not r["ok"])
    await A.send(type="gift_item", target=pb, item="pao", qty=1, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result")
    sa4 = await last_self(A); sb4 = await last_self(B)
    check("presente de artigo transfere o inventário", r and r["ok"] and sa4["inventory"].get("pao") == 1 and sb4["inventory"].get("pao") == 1)
    # 6. mensagens privadas
    await A.send(type="dm_send", target=pb, text="Olá Beto, tudo bem?"); s_ = await last_of(A, "dm_sent")
    m = await B.get("dm_message"); n = await B.get("notification", pred=lambda m: m["data"]["kind"] == "dm")
    check("mensagem privada entregue só ao destinatário, com hora e contador de não lidas", s_ and s_["ok"] and m and m["data"]["text"] == "Olá Beto, tudo bem?" and m["unread"] == 1 and m["data"]["t"] > 0 and n)
    cm = await C.get("dm_message", timeout=0.6); check("terceiros não recebem a mensagem privada", cm is None)
    await A.send(type="dm_send", target=pb, text="Segunda mensagem"); await B.get("dm_message"); await last_of(A, "dm_sent")
    await B.send(type="dm_history", target=pa); h = await B.get("dm_history")
    check("histórico da conversa (ordem + 'mine')", h and [x["text"] for x in h["messages"]] == ["Olá Beto, tudo bem?", "Segunda mensagem"] and not h["messages"][0]["mine"])
    await B.send(type="social_state_request"); st = (await last_of(B, "social_state"))["data"]
    check("abrir a conversa limpa as não lidas", st["conversations"] and st["conversations"][0]["unread"] == 0 and st["conversations"][0]["pub"] == pa)
    await A.send(type="dm_send", target=pb, text="   "); s_ = await last_of(A, "dm_sent"); check("mensagem vazia rejeitada", s_ and not s_["ok"])
    # mensagem para alguém offline fica guardada
    await B.cm.__aexit__(); await asyncio.sleep(0.4)
    await A.send(type="dm_send", target=pb, text="Estás aí?"); s_ = await last_of(A, "dm_sent"); check("mensagem para jogador offline é aceite e guardada", s_ and s_["ok"])
    B = await open_bot(); await B.send(type="login", username="soc_beto", password="pw1234"); r = await B.get("auth_response")
    await B.send(type="enter_world", character_id=r["data"]["character"]["id"]); await B.get("spawn_player"); st = (await B.get("social_state"))["data"]
    check("ao voltar: conversa com 1 não lida + notificações persistentes", st["conversations"][0]["unread"] == 1 and any(n["kind"] == "gift" for n in st["notifications"]))
    # 7. convites
    await A.send(type="invite", target=pb, kind="house"); r = await last_of(A, "social_result"); check("convite para casa sem casa arrendada rejeitado", r and not r["ok"])
    await A.send(type="invite", target=pb, kind="place", place="casa"); r = await last_of(A, "social_result"); check("convite para sítio privado como 'público' rejeitado", r and not r["ok"])
    await A.send(type="invite", target=pb, kind="game", game="xadrez"); r = await last_of(A, "social_result"); check("convite para jogar: sem jogos registados -> indisponível", r and not r["ok"] and "jogos" in r["text"])
    await A.send(type="invite", target=pb, kind="place", place="restaurante"); r = await last_of(A, "social_result")
    n = await B.get("notification", pred=lambda m: m["data"]["kind"] == "invite"); check("convite para o Restaurante Maianga com destino", r and r["ok"] and n and n["data"]["data"]["building"] == "restaurante")
    await asyncio.sleep(0.5)
    await A.send(type="invite", target=pb, kind="place", place="restaurante"); r = await last_of(A, "social_result"); check("convite duplicado pendente rejeitado", r and not r["ok"])
    await B.send(type="invite_respond", iid=n["data"]["data"]["iid"], accept=True); r = await last_of(B, "social_result")
    rep = await A.get("notification", pred=lambda m: m["data"]["kind"] == "invite_reply")
    check("aceitar convite: destino devolvido + remetente avisado", r and r["ok"] and r["invite"]["building"] == "restaurante" and rep and rep["data"]["data"]["accepted"])
    await B.send(type="invite_respond", iid=n["data"]["data"]["iid"], accept=True); r = await last_of(B, "social_result"); check("não responde duas vezes", r and not r["ok"])
    await A.send(type="invite", target=pb, kind="place", place="mercearia"); r = await last_of(A, "social_result"); iid = r["iid"]
    await A.send(type="invite_cancel", iid=iid); r = await last_of(A, "social_result"); await B.drain()
    await B.send(type="invite_respond", iid=iid, accept=True); r = await last_of(B, "social_result"); check("convite cancelado já não pode ser aceite", r and not r["ok"] and "cancelado" in r["text"])
    await A.send(type="invite", target=pb, kind="place", place="escritorio"); r = await last_of(A, "social_result"); iid = r["iid"]
    await asyncio.sleep(3.3); await B.drain()
    await B.send(type="invite_respond", iid=iid, accept=True); r = await last_of(B, "social_result"); check("convite expira", r and not r["ok"] and "expirou" in r["text"])
    # convite para casa -> visita autorizada (e só para o convidado)
    await A.send(type="rent", rental="casa", days=1); await A.get("notice")
    await asyncio.sleep(0.9)
    await A.send(type="invite", target=pb, kind="house"); r = await last_of(A, "social_result")
    await asyncio.sleep(0.3); await B.drain()
    n = [m for m in B.q if m["type"] == "notification" and m["data"]["kind"] == "invite"][-1]; B.q.clear()
    if not (r and r["ok"]): print("   house invite:", r)
    await B.send(type="invite_respond", iid=n["data"]["data"]["iid"], accept=True); r = await last_of(B, "social_result")
    if not (r and r["ok"]): print("   house accept:", r)
    casa = W.buildings["casa"]; bp = await walk(B, "w", (W.spawn["x"], W.spawn["y"]), W.entrance_tile(casa, casa["entrances"][0]))
    await B.send(type="enter_building", building="casa", entrance="frente"); z = await B.get("zone_change", pred=lambda m, _b=B: m["peer_id"] == _b.pid)
    check("convidado entra na casa do anfitrião (acesso validado no servidor)", z and z["zone"] == "b:casa:0")
    if not z: print("   ", [m for m in B.q if m["type"] in ("notice", "error")])
    cp = await walk(C, "w", (W.spawn["x"], W.spawn["y"]), W.entrance_tile(casa, casa["entrances"][0]))
    await C.send(type="enter_building", building="casa", entrance="frente"); nn = await C.get("notice"); check("quem não foi convidado continua sem acesso", nn and not nn["ok"])
    # 8. bloqueio
    await C.send(type="block", target=pa); r = await last_of(C, "social_result"); check("bloquear jogador", r and r["ok"])
    await A.send(type="dm_send", target=pc, text="olá"); s_ = await last_of(A, "dm_sent"); check("bloqueado não pode enviar mensagem", s_ and not s_["ok"])
    await A.send(type="gift_money", target=pc, amount=5, req_id=uuid.uuid4().hex); r = await last_of(A, "social_result"); check("bloqueado não pode dar presentes", r and not r["ok"])
    await A.send(type="friend_request", target=pc); r = await last_of(A, "social_result"); check("bloqueado não pode pedir amizade", r and not r["ok"])
    await A.send(type="invite", target=pc, kind="place", place="restaurante"); r = await last_of(A, "social_result"); check("bloqueado não pode convidar", r and not r["ok"])
    await A.send(type="call_start", target=pc); r = await A.get("call_failed"); check("bloqueado não pode ligar", r and r["reason"] == "blocked")
    # 9. chamadas: privacidade (aplicada no servidor, efeito imediato), sinalização, ocupado, perdida
    await B.send(type="privacy_set", calls="friends"); await B.get("social_result")
    await C.send(type="unblock", target=pa); await C.get("social_result")
    await C.send(type="call_start", target=pb); r = await C.get("call_failed"); check("'só amigos': não-amigo não consegue ligar", r and r["reason"] == "privacy")
    await B.send(type="privacy_set", calls="nobody"); await B.get("social_result")
    await A.send(type="call_start", target=pb); r = await A.get("call_failed"); check("'ninguém': nem amigos ligam (efeito imediato)", r and r["reason"] == "privacy")
    await B.send(type="privacy_set", calls="bogus"); r = await last_of(B, "social_result"); check("opção de privacidade inválida rejeitada", r and not r["ok"])
    await B.send(type="privacy_set", calls="everyone"); await B.get("social_result")
    await A.send(type="call_start", target=pb); o = await A.get("call_outgoing"); inc = await B.get("call_incoming")
    check("chamada: A a chamar, B recebe chamada a entrar", o and inc and inc["from"]["pub"] == pa and inc["call_id"] == o["call_id"])
    cid_ = o["call_id"]
    await C.send(type="call_start", target=pb); r = await C.get("call_failed"); nm = await B.get("notification", pred=lambda m: m["data"]["kind"] == "missed_call")
    check("B ocupado: C recebe 'ocupado' e B uma chamada perdida", r and r["reason"] == "busy" and nm)
    await C.send(type="call_answer", call_id=cid_, accept=True); await asyncio.sleep(0.2)
    await B.send(type="call_answer", call_id=cid_, accept=True); acc_b = await B.get("call_accepted"); acc_a = await A.get("call_accepted")
    check("atender: papéis WebRTC (oferta/resposta) + servidores ICE", acc_a and acc_b and acc_a["role"] == "offerer" and acc_b["role"] == "answerer" and acc_a.get("ice_servers"))
    await A.send(type="rtc_signal", call_id=cid_, payload={"kind": "offer", "sdp": "v=0 fake"}); sg = await B.get("rtc_signal")
    check("sinalização SDP/ICE reencaminhada só ao outro participante", sg and sg["payload"]["kind"] == "offer")
    await C.send(type="rtc_signal", call_id=cid_, payload={"kind": "offer", "sdp": "x"}); sg2 = await B.get("rtc_signal", timeout=0.6); check("terceiro não injeta sinalização", sg2 is None)
    await A.send(type="rtc_signal", call_id=cid_, payload={"kind": "evil"}); sg3 = await B.get("rtc_signal", timeout=0.6); check("payload inválido não é reencaminhado", sg3 is None)
    await A.send(type="call_end", call_id=cid_); e = await B.get("call_ended"); check("desligar avisa o outro lado", e and e["reason"] == "hangup")
    await asyncio.sleep(1.1)
    await A.send(type="call_start", target=pb); o = await A.get("call_outgoing"); await B.get("call_incoming")
    e1 = await A.get("call_ended", timeout=4); e2 = await B.get("call_ended", timeout=1); nm = await B.get("notification", pred=lambda m: m["data"]["kind"] == "missed_call")
    check("sem resposta: expira, avisa os dois e regista chamada perdida", e1 and e1["reason"] == "no_answer" and e2 and e2["reason"] == "missed" and nm)
    await asyncio.sleep(1.1)
    await A.send(type="call_start", target=pb); await A.get("call_outgoing"); await B.get("call_incoming")
    await B.cm.__aexit__(); await asyncio.sleep(0.4); e = await A.get("call_ended", timeout=2)
    check("se o outro se desliga, a chamada termina ('offline')", e and e["reason"] == "offline")
    await asyncio.sleep(1.1)
    await A.send(type="call_start", target=pb); r = await A.get("call_failed"); check("ligar a quem está offline falha", r and r["reason"] == "offline")
    for bot in (A, C):
        await bot.cm.__aexit__()

asyncio.run(main())

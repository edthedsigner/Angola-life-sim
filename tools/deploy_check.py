#!/usr/bin/env python3
"""Verifica um deploy PÚBLICO (corre no GitHub Actions: workflow "Deploy check", ou localmente).

    python tools/deploy_check.py --server wss://angola-life-sim-server.onrender.com \
                                 --client https://angola-life-sim.onrender.com [--players]

1. cliente web: a página, o .wasm e o .pck respondem 200 (e o .pck tem o servidor certo embutido);
2. servidor: GET https://…/healthz (espera até 3 min: o plano grátis do Render "adormece");
3. duas ligações wss SIMULTÂNEAS recebem `welcome`;
4. --players: cria DUAS contas de teste (smoke_xxxx), passa a introdução, cria personagens, entra no mundo e confirma
   que cada um vê o outro e recebe o movimento do outro. As contas de teste ficam guardadas (não há apagar contas).
Sai com código 0 só se tudo passar.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import re
import secrets
import sys
import time
import urllib.request

import websockets

RESULTS: list[tuple[bool, str]] = []


def check(ok: bool, name: str) -> bool:
    RESULTS.append((bool(ok), name))
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    return bool(ok)


def http_get(url: str, timeout: float = 30) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": "angola-deploy-check"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:  # noqa: BLE001
        print("   ", url, "->", repr(e))
        return 0, b""


def check_client(client: str, server: str) -> None:
    base = client.rstrip("/")
    st, body = http_get(base + "/")
    check(st == 200 and b"GODOT_CONFIG" in body, f"cliente: {base}/ responde (página Godot)")
    st, _ = http_get(base + "/index.wasm", timeout=120)
    check(st == 200, "cliente: index.wasm disponível")
    # o .pck tem a versão no nome (index-<commit>.pck, ver build.yml); o index.html diz qual é
    m = re.search(rb'"mainPack":"([^"]+)"', body)
    pck_name = m.group(1).decode() if m else "index.pck"
    st, pck = http_get(base + "/" + pck_name, timeout=120)
    check(st == 200 and len(pck) > 100_000, f"cliente: {pck_name} disponível ({len(pck) // 1024} KB)")
    host = server.split("://", 1)[-1].rstrip("/").encode()
    check(host in pck, f"cliente: build aponta para {host.decode()} (config/server.json embutido)")
    check(b"GODOT_THREADS_ENABLED = false" in body, "cliente: export sem threads (iPhone/Safari, sem cabeçalhos especiais)")


async def wait_health(server: str, deadline_s: float = 180) -> bool:
    url = "https://" + server.split("://", 1)[-1].rstrip("/") + "/healthz"
    if server.startswith("ws://"):
        url = "http://" + url[len("https://"):]
    t0 = time.time()
    while time.time() - t0 < deadline_s:
        st, body = await asyncio.to_thread(http_get, url, 30)
        if st == 200 and body.strip() == b"ok":
            return check(True, f"servidor: {url} -> ok ({time.time() - t0:.0f} s)")
        print(f"   à espera do servidor ({st})…", flush=True)
        await asyncio.sleep(10)
    return check(False, f"servidor: {url} não respondeu em {deadline_s:.0f} s")


class Bot:
    def __init__(self, ws):
        self.ws, self.q = ws, []

    async def get(self, typ: str, timeout: float = 10, pred=None):
        end = time.time() + timeout
        while time.time() < end:
            for m in self.q:
                if m.get("type") == typ and (pred is None or pred(m)):
                    self.q.remove(m)
                    return m
            try:
                self.q.append(json.loads(await asyncio.wait_for(self.ws.recv(), 0.5)))
            except (asyncio.TimeoutError, TimeoutError):
                pass
        return None

    async def send(self, **m):
        await self.ws.send(json.dumps(m))


async def enter(bot: Bot, user: str, pw: str, name: str) -> dict | None:
    await bot.send(type="register", username=user, password=pw)
    r = await bot.get("auth_response")
    if not (r and r.get("success")):
        print("   registo falhou:", r)
        return None
    for s in range(4):
        await bot.send(type="onboarding_progress", state="story_in_progress", step=s)
        await bot.get("onboarding_state")
    await bot.send(type="onboarding_progress", state="character_customization", step=3)
    await bot.get("onboarding_state")
    await bot.send(type="create_character", name=name, appearance={"skin_tone": 2, "hair_style": 1, "clothes": 1})
    c = await bot.get("character_created")
    if not (c and c.get("success")):
        print("   criar personagem falhou:", c)
        return None
    await bot.send(type="enter_world", character_id=c["data"]["id"])
    return await bot.get("spawn_player", pred=lambda m: m["data"].get("name") == name)


async def check_server(server: str, players: bool) -> None:
    async with websockets.connect(server, open_timeout=60) as wa, websockets.connect(server, open_timeout=60) as wb:
        A, B = Bot(wa), Bot(wb)
        a, b = await A.get("welcome"), await B.get("welcome")
        check(a is not None and b is not None and a["peer_id"] != b["peer_id"], "servidor: duas ligações wss simultâneas recebem welcome")
        if not players:
            return
        tag = secrets.token_hex(3)
        na, nb = f"Teste A {tag}", f"Teste B {tag}"
        pw = secrets.token_urlsafe(12)
        sa = await enter(A, f"smoke_a_{tag}", pw, na)
        sb = await enter(B, f"smoke_b_{tag}", pw, nb)
        check(sa is not None and sb is not None, f"jogadores: smoke_a_{tag} e smoke_b_{tag} entraram no mundo")
        if sa is None or sb is None:
            return
        seen = await A.get("spawn_player", pred=lambda m: m["data"].get("name") == nb)
        check(seen is not None, "jogadores: A vê B aparecer no mundo partilhado")
        check("money" not in (seen or {}).get("data", {}) and "id" not in (seen or {}).get("data", {}), "jogadores: dados públicos não incluem dinheiro/ids")
        p = sa["data"]["position"]
        x, y = float(p["x"]) + 12.0, float(p["y"]) + 6.0
        await A.send(type="position", x=x, y=y)
        m = await B.get("position")
        check(m is not None and abs(m["x"] - x) < 0.01, "jogadores: B recebe o movimento de A em tempo real")


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True, help="wss://… do servidor de jogo")
    ap.add_argument("--client", default="", help="https://… do cliente web")
    ap.add_argument("--players", action="store_true", help="cria duas contas de teste e testa o mundo partilhado")
    a = ap.parse_args()
    if a.client:
        check_client(a.client, a.server)
    if await wait_health(a.server):
        try:
            await check_server(a.server, a.players)
        except Exception as e:  # noqa: BLE001
            check(False, f"servidor: ligação WebSocket falhou ({e!r})")
    bad = [n for ok, n in RESULTS if not ok]
    print(f"\n{len(RESULTS) - len(bad)} passaram, {len(bad)} falharam")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))

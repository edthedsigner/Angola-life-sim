"""Gameplay rules (server-authoritative): clock, needs, inventory, economy, jobs, rentals, activities.

Everything here mutates plain character dicts; server.py owns networking, zones and persistence.
All tunables come from shared/data/world.json so client and server agree.
"""
from __future__ import annotations

import os
import time

NEEDS = ("hunger", "energy", "hygiene", "health")
DAY = 86400.0


class Clock:
    """Game time advances `time_scale` x faster than real time (original v0.6: 1 real hour = 4 game hours)."""

    def __init__(self, cfg: dict, saved_game_s: float | None):
        self.scale = float(os.environ.get("ANGOLA_TIME_SCALE", cfg.get("time_scale", 4.0)))
        self.base_game = float(saved_game_s) if saved_game_s is not None else float(cfg.get("start_hour", 8)) * 3600.0
        self.base_real = time.time()

    def now(self) -> float:
        return self.base_game + (time.time() - self.base_real) * self.scale

    @staticmethod
    def label(game_s: float) -> str:
        return "Dia %d, %02d:%02d" % (int(game_s // DAY) + 1, int(game_s // 3600) % 24, int(game_s // 60) % 60)


def ensure_fields(ch: dict, W) -> None:
    """Adds gameplay fields to a character (migration for characters created before this milestone; nothing is removed)."""
    start = W.needs_cfg["start"]
    needs = ch.get("needs") if isinstance(ch.get("needs"), dict) else {}
    ch["needs"] = {k: float(needs.get(k, start[k])) for k in NEEDS}
    inv = ch.get("inventory")
    ch["inventory"] = {str(k): int(v) for k, v in inv.items() if int(v) > 0} if isinstance(inv, dict) else {}
    ch.setdefault("job", None)
    if not isinstance(ch.get("housing"), dict):
        ch["housing"] = {"status": "sem_abrigo"}
    if not isinstance(ch.get("transactions"), list):
        ch["transactions"] = []
    ch.setdefault("zone", "w")
    ch["money"] = int(ch.get("money", 0))


def add_tx(ch: dict, desc: str, amount: int, game_s: float) -> None:
    ch["transactions"].append({"t": game_s, "desc": desc, "amount": int(amount), "balance": int(ch["money"])})
    del ch["transactions"][:-30]


def apply_effects(ch: dict, effects: dict) -> None:
    for k, v in effects.items():
        if k in ch["needs"]:
            ch["needs"][k] = max(0.0, min(100.0, ch["needs"][k] + float(v)))


def decay(ch: dict, game_hours: float, cfg: dict) -> None:
    n = ch["needs"]
    for k, rate in cfg["decay_per_game_hour"].items():
        n[k] = max(0.0, n[k] - rate * game_hours)
    h = cfg["health_per_game_hour"]
    delta = 0.0
    if n["hunger"] <= 0:
        delta += h["starving"]
    if n["energy"] <= 0:
        delta += h["exhausted"]
    if n["hygiene"] <= 0:
        delta += h["dirty"]
    if delta == 0.0:
        delta = h["regen"]
    n["health"] = max(0.0, min(100.0, n["health"] + delta * game_hours))


def housing_active(ch: dict, building_id: str, game_s: float) -> bool:
    h = ch.get("housing") or {}
    return h.get("status") == "arrendado" and h.get("building") == building_id and float(h.get("until", 0)) > game_s


def status_text(ch: dict, game_s: float) -> str:
    h = ch.get("housing") or {}
    if h.get("status") == "arrendado" and float(h.get("until", 0)) <= game_s:
        h["status"] = "sem_abrigo"
    return h.get("status", "sem_abrigo")


# ---------------------------------------------------------------- economy (results are (ok, message))
def buy(ch: dict, W, action: str, item: str, qty: int, game_s: float):
    shop = W.activities[action].get("shop", [])
    if item not in shop or item not in W.items:
        return False, "Este artigo não está à venda aqui."
    qty = max(1, min(10, int(qty)))
    cost = W.items[item]["price"] * qty
    if ch["money"] < cost:
        return False, "Dinheiro insuficiente."
    ch["money"] -= cost
    ch["inventory"][item] = ch["inventory"].get(item, 0) + qty
    add_tx(ch, f"Compra: {W.items[item]['name']} x{qty}", -cost, game_s)
    return True, f"Compraste {W.items[item]['name']} x{qty} por {cost} Kz."


def sell(ch: dict, W, item: str, game_s: float):
    if ch["inventory"].get(item, 0) <= 0 or item not in W.items:
        return False, "Não tens esse artigo."
    price = int(W.items[item].get("sell", 0))
    if price <= 0:
        return False, "Ninguém compra este artigo."
    ch["inventory"][item] -= 1
    if ch["inventory"][item] <= 0:
        del ch["inventory"][item]
    ch["money"] += price
    add_tx(ch, f"Venda: {W.items[item]['name']}", price, game_s)
    return True, f"Vendeste {W.items[item]['name']} por {price} Kz."


def use_item(ch: dict, W, item: str):
    if ch["inventory"].get(item, 0) <= 0 or item not in W.items:
        return False, "Não tens esse artigo."
    eff = W.items[item].get("eat")
    if not eff:
        return False, "Isto não se come."
    ch["inventory"][item] -= 1
    if ch["inventory"][item] <= 0:
        del ch["inventory"][item]
    apply_effects(ch, eff)
    return True, f"Consumiste {W.items[item]['name']}."


def rent(ch: dict, W, rental: str, days: int, game_s: float):
    r = W.rentals.get(rental)
    if r is None or int(days) not in r["options"]:
        return False, "Opção de arrendamento inválida."
    days = int(days)
    cost = int(r["price_per_day"] * days * (r.get("discount_7", 1.0) if days == 7 else 1.0))
    if ch["money"] < cost:
        return False, "Dinheiro insuficiente para arrendar."
    h = ch["housing"]
    start = float(h.get("until", 0)) if housing_active(ch, rental, game_s) else game_s
    ch["money"] -= cost
    ch["housing"] = {"status": "arrendado", "building": rental, "until": start + days * DAY}
    add_tx(ch, f"Renda: {r['name']} ({days} dia{'s' if days > 1 else ''})", -cost, game_s)
    return True, f"Arrendaste: {r['name']} por {days} dia(s)."


def job_apply(ch: dict, W, job: str):
    if job not in W.jobs:
        return False, "Vaga inexistente."
    if ch.get("job") == job:
        return False, "Já tens este emprego."
    ch["job"] = job
    return True, f"Foste contratado: {W.jobs[job]['name']}. Vai ao local de trabalho e usa um posto para trabalhar."


def job_quit(ch: dict, W):
    if not ch.get("job"):
        return False, "Não tens emprego."
    name = W.jobs.get(ch["job"], {}).get("name", ch["job"])
    ch["job"] = None
    return True, f"Despediste-te: {name}."


def check_activity(ch: dict, W, action: str, building_id: str | None, game_s: float):
    """Pre-conditions of a timed activity (location/proximity is checked by the caller)."""
    a = W.activities[action]
    req = a.get("requires")
    if req == "housing" and not housing_active(ch, building_id or "", game_s):
        return False, "Só podes fazer isto numa casa que arrendaste (app Imóveis)."
    if req == "job":
        job = W.jobs.get(ch.get("job") or "")
        if not job or job["building"] != building_id:
            return False, "Precisas de um emprego aqui (app Emprego)."
    if a.get("consumes") and ch["inventory"].get(a["consumes"], 0) <= 0:
        return False, f"Precisas de {W.items[a['consumes']]['name']} (compra na mercearia)."
    if ch["money"] < int(a.get("cost", 0)):
        return False, "Dinheiro insuficiente."
    if action in ("sleep", "rest", "rest_bench") and ch["needs"]["energy"] >= 99:
        return False, "Não estás cansado."
    return True, ""


def finish_activity(ch: dict, W, action: str, game_s: float) -> str:
    a = W.activities[action]
    if a.get("consumes"):
        item = a["consumes"]
        ch["inventory"][item] = ch["inventory"].get(item, 0) - 1
        if ch["inventory"][item] <= 0:
            ch["inventory"].pop(item, None)
    cost = int(a.get("cost", 0))
    if cost:
        ch["money"] -= cost
        add_tx(ch, a["label"], -cost, game_s)
    apply_effects(ch, a.get("effects", {}))
    if action == "work":
        job = W.jobs[ch["job"]]
        ch["money"] += int(job["pay"])
        add_tx(ch, f"Salário: {job['name']}", int(job["pay"]), game_s)
        return f"Turno concluído: +{job['pay']} Kz."
    return f"{a['label']}: concluído."


def private_state(ch: dict, W, clock: Clock, activity: dict | None) -> dict:
    g = clock.now()
    status_text(ch, g)
    return {"money": ch["money"], "needs": {k: round(v, 1) for k, v in ch["needs"].items()}, "inventory": ch["inventory"],
            "job": ch.get("job"), "housing": ch["housing"], "transactions": ch["transactions"][-12:],
            "game_s": g, "time_scale": clock.scale, "zone": ch.get("zone", "w"),
            "activity": None if not activity else {"action": activity["action"], "fid": activity["fid"],
                                                      "secs": activity["secs"], "left": max(0.0, activity["until"] - time.time())}}

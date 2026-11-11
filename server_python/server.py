#!/usr/bin/env python3
"""
Angola Life Simulator — Servidor autoritativo (Python)
Milestone 1

Requisitos: pip install websockets
Correr: python server.py
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import math
import json
import os
import random
import secrets
import time
import uuid
from pathlib import Path
from typing import Any

try:
    import websockets
except ImportError:
    print("Instala a dependência:  pip install websockets")
    raise SystemExit(1)

import game
import world as worldmod

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
HOST = "0.0.0.0"
PORT = 7777
DATA_DIR = Path(__file__).parent / "data"
CONFIG_FILE = Path(__file__).parent / "world_config.json"
WORLD = {"max_players": 64, "story_steps": 4}
try:
    WORLD.update(json.loads(CONFIG_FILE.read_text(encoding="utf-8")))
except Exception:
    pass
# Mapa, edifícios, interiores, mobília, atividades e economia: shared/data/world.json (mesmo ficheiro que o cliente lê).
W = worldmod.load()
WORLD["spawn"] = dict(W.spawn)            # fonte única do spawn (antes duplicado em world_config.json e World.tscn)
WORLD_STATE_FILE = DATA_DIR / "world_state.json"
clock: game.Clock = game.Clock(W.clock_cfg, None)
door_states: dict[str, dict[str, bool]] = {}   # zone -> {edge_key: open}
activities: dict[str, dict] = {}               # peer_id -> atividade em curso
occupied: dict[tuple, str] = {}                # (zone, fid) -> peer_id (evita dois jogadores na mesma cama/posto)
last_chat: dict[str, float] = {}
MAX_STEP_PX = 220.0
ACTIVITY_SCALE = float(os.environ.get("ANGOLA_ACTIVITY_SCALE", "1"))   # testes: <1 encurta as atividades                             # salto máximo aceite entre duas mensagens de posição
ACCOUNTS_FILE = DATA_DIR / "accounts.json"
CHARACTERS_FILE = DATA_DIR / "characters.json"
SESSIONS_FILE = DATA_DIR / "sessions.json"
STORY_STEPS = int(WORLD.get("story_steps", 4))      # nº de páginas da introdução (client/data/intro_story.json)
SESSION_TTL = 30 * 24 * 3600
sessions: dict[str, dict] = {}   # sha256(token) -> {account_id, expires}

# ---------------------------------------------------------------------------
# Persistência
# ---------------------------------------------------------------------------
accounts: dict[str, dict] = {}          # username -> account
characters: dict[str, dict] = {}        # character_id -> character
account_characters: dict[str, list] = {}  # account_id -> [character_ids]

# Conexões ativas
# websocket -> {"peer_id": str, "account_id": str|None, "character_id": str|None}
clients: dict[Any, dict] = {}
# peer_id -> websocket
peers: dict[str, Any] = {}
# peer_id -> character data (no mundo)
players_in_world: dict[str, dict] = {}


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_json(path: Path, data: dict) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def load_all() -> None:
    global accounts, characters, account_characters
    accounts = load_json(ACCOUNTS_FILE)
    characters = load_json(CHARACTERS_FILE)
    account_characters = {}
    for cid, ch in characters.items():
        acc_id = ch.get("account_id", "")
        account_characters.setdefault(acc_id, []).append(cid)
    # Migração (sem apagar nada): contas antigas sem estado de onboarding
    for acc in accounts.values():
        if not isinstance(acc.get("onboarding"), dict):
            done = bool(account_characters.get(acc.get("id", "")))
            acc["onboarding"] = {"state": "completed" if done else "new", "story_step": STORY_STEPS - 1 if done else 0}
    global sessions, clock, door_states
    sessions = {k: v for k, v in load_json(SESSIONS_FILE).items() if v.get("expires", 0) > time.time()}
    ws_state = load_json(WORLD_STATE_FILE)
    clock = game.Clock(W.clock_cfg, ws_state.get("game_s"))
    door_states = {z: {k: bool(v) for k, v in d.items()} for z, d in ws_state.get("doors", {}).items() if W.zone_valid(z)}
    for ch in characters.values():
        game.ensure_fields(ch, W)


def save_all() -> None:
    save_json(ACCOUNTS_FILE, accounts)
    save_json(CHARACTERS_FILE, characters)
    save_json(SESSIONS_FILE, sessions)
    save_json(WORLD_STATE_FILE, {"game_s": clock.now(), "doors": door_states})


# ---------------------------------------------------------------------------
# Onboarding + sessões
# ---------------------------------------------------------------------------
def account_by_id(acc_id: str) -> dict | None:
    for acc in accounts.values():
        if acc.get("id") == acc_id:
            return acc
    return None


def profile_data(acc: dict) -> dict:
    """Perfil devolvido no login/retoma de sessão. O servidor é a fonte de verdade do onboarding."""
    chars = [characters[c] for c in account_characters.get(acc["id"], []) if c in characters]
    ob = acc.setdefault("onboarding", {"state": "new", "story_step": 0})
    if chars and ob.get("state") != "completed":      # auto-cura: tem personagem => concluído
        ob.update({"state": "completed", "story_step": STORY_STEPS - 1})
        save_all()
    return {"account_id": acc["id"], "username": acc["username"], "characters": chars,
            "character": chars[0] if chars else None,
            "onboarding": {"state": ob["state"], "story_step": int(ob.get("story_step", 0)), "story_steps": STORY_STEPS}}


def advance_onboarding(acc: dict, state: str, step: Any) -> dict:
    ob = acc["onboarding"]
    try:
        step = max(0, min(STORY_STEPS - 1, int(step)))
    except (TypeError, ValueError):
        step = 0
    cur = ob["state"]
    if cur == "completed":
        return ob
    if state == "story_in_progress" and cur in ("new", "story_in_progress"):
        ob["state"] = "story_in_progress"
        ob["story_step"] = max(int(ob.get("story_step", 0)), step)
    elif state == "character_customization" and cur in ("new", "story_in_progress", "character_customization") and step >= STORY_STEPS - 1:
        ob["state"] = "character_customization"
        ob["story_step"] = STORY_STEPS - 1
    ob["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    save_all()
    return ob


def issue_session(acc_id: str) -> str:
    token = secrets.token_urlsafe(32)
    sessions[hashlib.sha256(token.encode()).hexdigest()] = {"account_id": acc_id, "expires": time.time() + SESSION_TTL}
    save_json(SESSIONS_FILE, sessions)
    return token


def resolve_session(token: str) -> dict | None:
    s = sessions.get(hashlib.sha256(str(token).encode()).hexdigest())
    if not s or s["expires"] < time.time():
        return None
    return account_by_id(s["account_id"])


def revoke_session(token: str) -> None:
    if sessions.pop(hashlib.sha256(str(token).encode()).hexdigest(), None) is not None:
        save_json(SESSIONS_FILE, sessions)


def hash_password(password: str, salt: str | None = None) -> str:
    salt = salt or uuid.uuid4().hex
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode(), 120_000).hex()
    return f"pbkdf2${salt}${dk}"


def check_password(password: str, stored: str) -> bool:
    if stored.startswith("pbkdf2$"):
        _, salt, _ = stored.split("$", 2)
        return hmac.compare_digest(hash_password(password, salt), stored)
    return hmac.compare_digest(hashlib.sha256(password.encode("utf-8")).hexdigest(), stored)  # legado


def new_id() -> str:
    return f"{int(time.time())}_{uuid.uuid4().hex[:8]}"


# ---------------------------------------------------------------------------
# Geração de background (coerente, data-driven)
# ---------------------------------------------------------------------------
MALE_NAMES = [
    "João", "António", "Carlos", "Pedro", "Manuel", "Francisco",
    "José", "Paulo", "Domingos", "Sebastião", "Mateus", "Daniel",
]
FEMALE_NAMES = [
    "Maria", "Ana", "Isabel", "Catarina", "Teresa", "Rosa",
    "Joana", "Filomena", "Lúcia", "Beatriz", "Helena", "Sofia",
]
SURNAMES = [
    "da Silva", "dos Santos", "Ferreira", "Costa", "Pereira", "Oliveira",
    "Rodrigues", "Martins", "Fernandes", "Gonçalves", "Alves", "Lopes",
    "Nunes", "Mendes", "Carvalho",
]

FATHER_JOBS = {
    "lower": [
        "vendedor ambulante", "pedreiro", "motorista de candongueiro",
        "trabalhador de construção", "segurança", "carregador",
    ],
    "middle": [
        "professor", "técnico de informática", "funcionário público",
        "enfermeiro", "contabilista", "comerciante",
    ],
    "wealthy": [
        "empresário", "médico", "engenheiro", "advogado",
        "dono de empresa de importação", "diretor comercial",
    ],
}
MOTHER_JOBS = {
    "lower": [
        "empregada doméstica", "vendedora de mercado", "costureira",
        "cozinheira", "auxiliar de limpeza",
    ],
    "middle": [
        "professora", "enfermeira", "secretária",
        "comerciante", "técnica administrativa",
    ],
    "wealthy": [
        "médica", "empresária", "advogada", "gestora", "dona de boutique",
    ],
}
LUANDA_NBH = {
    "lower": ["Cazenga", "Sambizanga", "Rangel", "Viana (periferia)", "Cacuaco"],
    "middle": ["Maianga", "Ingombota", "Kilamba", "Talatona (zona média)", "Benfica"],
    "wealthy": ["Talatona", "Miramar", "Alvalade", "Maculusso", "Ilha de Luanda"],
}
PROVINCES = ["Luanda", "Benguela", "Huíla", "Huambo", "Cabinda", "Malanje"]
EDUCATION = {
    "lower": ["ensino primário incompleto", "ensino primário", "ensino médio incompleto"],
    "middle": ["ensino médio", "curso técnico", "licenciatura em andamento"],
    "wealthy": ["ensino médio completo", "licenciatura", "mestrado"],
}
MONEY_RANGES = {
    "lower": (500, 3500),
    "middle": (8000, 25000),
    "wealthy": (50000, 180000),
}
POSSESSIONS = {
    "lower": ["roupa básica", "telemóvel usado"],
    "middle": ["roupa decente", "telemóvel", "alguns documentos"],
    "wealthy": ["roupa boa", "telemóvel recente", "documentos", "carta de recomendação familiar"],
}


def random_name(male: bool) -> str:
    first = random.choice(MALE_NAMES if male else FEMALE_NAMES)
    return f"{first} {random.choice(SURNAMES)}"


def weighted_class() -> str:
    # lower 45, middle 40, wealthy 15
    r = random.randint(0, 99)
    if r < 45:
        return "lower"
    if r < 85:
        return "middle"
    return "wealthy"


def generate_background(character_id: str) -> dict:
    socio = weighted_class()
    labels = {"lower": "Baixa renda", "middle": "Classe média", "wealthy": "Classe alta"}

    siblings = {
        "lower": random.randint(1, 4),
        "middle": random.randint(0, 2),
        "wealthy": random.randint(0, 2),
    }[socio]

    family = {
        "father_name": random_name(True),
        "father_profession": random.choice(FATHER_JOBS[socio]),
        "mother_name": random_name(False),
        "mother_profession": random.choice(MOTHER_JOBS[socio]),
        "siblings": siblings,
        "family_relationship": "próxima" if random.random() > 0.3 else "distante",
        "family_support_level": {"lower": 1, "middle": 2, "wealthy": 3}[socio],
    }

    province = "Luanda" if random.random() > 0.35 else random.choice(PROVINCES)
    if province == "Luanda":
        neighbourhood = random.choice(LUANDA_NBH[socio])
    else:
        neighbourhood = "Centro" if socio != "lower" else "Bairro periférico"

    childhood = {
        "province": province,
        "neighbourhood": neighbourhood,
        "living_conditions": {"lower": "modestas", "middle": "confortáveis", "wealthy": "abastadas"}[socio],
        "education": random.choice(EDUCATION[socio]),
    }

    lo, hi = MONEY_RANGES[socio]
    money = random.randint(lo, hi)

    quals = {
        "lower": ["experiência informal", "trabalho braçal"],
        "middle": ["ensino médio", "alguma experiência profissional"],
        "wealthy": ["formação superior", "contactos profissionais", "experiência em negócios familiares"],
    }[socio]
    contacts = {
        "lower": ["conhecido no mercado", "primo que trabalha em construção"],
        "middle": ["amigo de escola", "contacto na função pública"],
        "wealthy": ["amigo da família empresário", "contacto no banco", "conhecido em empresa de importação"],
    }[socio]
    notes = {
        "lower": "Começas a tua vida independente com poucos recursos. A família pode ajudar ocasionalmente, mas o caminho é teu.",
        "middle": "Tens uma base razoável. A família pode oferecer apoio pontual, mas precisas de construir a tua própria estabilidade.",
        "wealthy": "Vens de uma família com meios. Podes receber apoio financeiro ou contactos, mas as propriedades e negócios da família não são teus automaticamente.",
    }[socio]

    assets = {
        "lower": ["casa modesta da família num bairro periférico"],
        "middle": ["apartamento da família", "um carro familiar usado"],
        "wealthy": ["moradia da família", "negócio da família", "vários carros", "terrenos"],
    }[socio]
    starting = {
        "initial_money": money,
        "personal_possessions": POSSESSIONS[socio],
        "qualifications": quals,
        "useful_contacts": contacts,
        "notes": notes,
    }

    bg = {
        "socioeconomic_class": socio,
        "socioeconomic_label": labels[socio],
        "family": family,
        "childhood": childhood,
        "family_assets": assets,
        "housing": {"status": "sem_abrigo", "owned_properties": []},
        "starting_circumstances": starting,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }

    if character_id in characters:
        characters[character_id]["money"] = money
        characters[character_id]["background"] = bg
        save_all()

    return bg


# ---------------------------------------------------------------------------
# Auth & Character
# ---------------------------------------------------------------------------
def register(username: str, password: str) -> dict:
    username = username.strip().lower()
    if len(username) < 3:
        return {"ok": False, "error": "Nome de utilizador demasiado curto"}
    if len(password) < 4:
        return {"ok": False, "error": "Palavra-passe demasiado curta"}
    if username in accounts:
        return {"ok": False, "error": "Nome de utilizador já existe"}

    acc_id = new_id()
    accounts[username] = {
        "id": acc_id,
        "username": username,
        "password_hash": hash_password(password),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "onboarding": {"state": "new", "story_step": 0},
    }
    save_all()
    return {"ok": True, "data": profile_data(accounts[username])}


def login(username: str, password: str) -> dict:
    username = username.strip().lower()
    if username not in accounts:
        return {"ok": False, "error": "Conta não encontrada"}
    acc = accounts[username]
    if not check_password(password, acc["password_hash"]):
        return {"ok": False, "error": "Palavra-passe incorreta"}

    return {"ok": True, "data": profile_data(acc)}


def clean_appearance(a: Any) -> dict:
    a = a if isinstance(a, dict) else {}
    def g(key: str, hi: int) -> int:
        try:
            return max(0, min(hi, int(a.get(key, 0))))
        except (TypeError, ValueError):
            return 0
    return {"skin_tone": g("skin_tone", 3), "hair_style": g("hair_style", 3), "hair_color": g("hair_color", 3), "clothes": g("clothes", 3)}


def create_character(account_id: str, appearance: dict, name: str) -> dict:
    name = "".join(ch for ch in str(name) if ch.isprintable()).strip()[:24]
    if len(name) < 2:
        return {"ok": False, "error": "Nome demasiado curto"}

    acc = account_by_id(account_id)
    if acc is None or acc["onboarding"]["state"] not in ("character_customization",):
        if acc is not None and acc["onboarding"]["state"] == "completed":
            return {"ok": False, "error": "Já tens um personagem nesta conta"}
        return {"ok": False, "error": "Conclui primeiro a introdução"}
    existing = account_characters.get(account_id, [])
    if len(existing) >= 1:
        return {"ok": False, "error": "Já tens um personagem nesta conta"}

    cid = new_id()
    character = {
        "id": cid,
        "account_id": account_id,
        "name": name,
        "appearance": clean_appearance(appearance),
        "position": dict(WORLD["spawn"]),
        "money": 0,
        "inventory": [],
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "last_seen": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    game.ensure_fields(character, W)
    characters[cid] = character
    account_characters.setdefault(account_id, []).append(cid)

    bg = generate_background(cid)
    character["background"] = bg
    character["money"] = bg["starting_circumstances"]["initial_money"]
    if os.environ.get("ANGOLA_DEV_START_MONEY"):            # só desenvolvimento/testes: dinheiro inicial fixo
        character["money"] = int(os.environ["ANGOLA_DEV_START_MONEY"])
    acc["onboarding"] = {"state": "completed", "story_step": STORY_STEPS - 1, "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    save_all()

    return {"ok": True, "data": character}


# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------
async def send(ws: Any, msg: dict) -> None:
    try:
        await ws.send(json.dumps(msg, ensure_ascii=False))
    except Exception:
        pass


async def broadcast_world(msg: dict, exclude_peer: str | None = None) -> None:
    for peer_id, data in list(players_in_world.items()):
        if peer_id == exclude_peer:
            continue
        ws = peers.get(peer_id)
        if ws:
            await send(ws, msg)


# ---------------------------------------------------------------------------
# Message handlers
# ---------------------------------------------------------------------------
dirty = False


def public_view(peer_id: str, ch: dict) -> dict:
    """Só dados públicos — o background de vida, dinheiro, necessidades e inventário NUNCA vão para outros jogadores."""
    return {"id": ch["id"], "peer_id": peer_id, "name": ch["name"], "appearance": ch.get("appearance", {}),
            "position": dict(ch.get("position", WORLD["spawn"])), "zone": ch.get("zone", "w"),
            "activity": (activities.get(peer_id) or {}).get("action"), "activity_fid": (activities.get(peer_id) or {}).get("fid")}


def finite(v: Any) -> float | None:
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


def cancel_activity(peer_id: str) -> dict | None:
    act = activities.pop(peer_id, None)
    if act:
        occupied.pop((act["zone"], act["fid"]), None)
        t = act.get("task")
        if t and not t.done() and t is not asyncio.current_task():
            t.cancel()
    return act


async def leave_world(peer_id: str) -> None:
    cancel_activity(peer_id)
    if peer_id in players_in_world:
        del players_in_world[peer_id]
        await broadcast_world({"type": "player_left", "peer_id": peer_id})
        print(f"[World] Peer {peer_id} saiu")


def char_of(peer_id: str) -> dict | None:
    me = players_in_world.get(peer_id)
    return characters.get(me["id"]) if me else None


async def send_self(peer_id: str) -> None:
    ch = char_of(peer_id)
    ws = peers.get(peer_id)
    if ch and ws:
        await send(ws, {"type": "self_state", "data": game.private_state(ch, W, clock, activities.get(peer_id))})


async def notice(ws: Any, text: str, ok: bool = True) -> None:
    await send(ws, {"type": "notice", "text": text, "ok": ok})


def peers_in_zone(zone: str) -> list[str]:
    return [pid for pid, p in players_in_world.items() if p.get("zone", "w") == zone]


async def move_zone(peer_id: str, zone: str, pos: tuple) -> None:
    """Teleporte autoritativo (entrar/sair/escadas). Todos os clientes recebem; cada um mostra só a sua zona."""
    global dirty
    cancel_activity(peer_id)
    me = players_in_world[peer_id]
    ch = characters[me["id"]]
    dirty = True
    me["zone"] = ch["zone"] = zone
    me["position"] = ch["position"] = {"x": float(pos[0]), "y": float(pos[1])}
    await broadcast_world({"type": "zone_change", "peer_id": peer_id, "zone": zone, "x": pos[0], "y": pos[1]})
    ws = peers.get(peer_id)
    if ws and zone != "w":
        await send(ws, {"type": "zone_state", "zone": zone, "doors": door_states.get(zone, {})})
    await send_self(peer_id)


def safe_spawn(ch: dict) -> None:
    """Posições gravadas podem ficar inválidas quando o mapa muda (ex.: edifícios maiores) -> volta ao spawn."""
    zone = ch.get("zone", "w")
    pos = ch.get("position") or {}
    x, y = finite(pos.get("x")), finite(pos.get("y"))
    if not W.zone_valid(zone) or x is None or y is None or not W.walkable_point(zone, x, y):
        ch["zone"] = "w"
        ch["position"] = dict(WORLD["spawn"])


async def run_activity(peer_id: str, act: dict) -> None:
    try:
        await asyncio.sleep(act["secs"])
    except asyncio.CancelledError:
        return
    if activities.get(peer_id) is not act:
        return
    cancel_activity(peer_id)
    ch = char_of(peer_id)
    ws = peers.get(peer_id)
    if not ch:
        return
    ok, why = game.check_activity(ch, W, act["action"], act["building"], clock.now())
    msg = game.finish_activity(ch, W, act["action"], clock.now()) if ok or why == "Não estás cansado." else why
    global dirty
    dirty = True
    if ws:
        await send(ws, {"type": "activity_done", "action": act["action"], "fid": act["fid"], "text": msg})
    await broadcast_world({"type": "player_activity", "peer_id": peer_id, "action": None})
    await send_self(peer_id)


async def handle_game(ws: Any, peer_id: str, mtype: str, msg: dict) -> bool:
    """Mensagens de jogo (só no mundo). Devolve False se o tipo não for de jogo."""
    global dirty
    me = players_in_world.get(peer_id)
    if mtype not in ("enter_building", "exit_building", "use_stairs", "door_toggle", "interact", "use_item", "cancel_activity",
                     "chat", "job_apply", "job_quit", "rent", "profile_request", "ping", "self_request"):
        return False
    if mtype == "ping":
        await send(ws, {"type": "pong", "t": msg.get("t")})
        return True
    if me is None:
        await send(ws, {"type": "error", "error": "Não estás no mundo"})
        return True
    ch = characters[me["id"]]
    zone = me.get("zone", "w")
    x, y = me["position"]["x"], me["position"]["y"]
    now = clock.now()

    if mtype == "self_request":
        await send_self(peer_id)

    elif mtype == "enter_building":
        b = W.buildings.get(str(msg.get("building", "")))
        ent = next((e for e in (b or {}).get("entrances", []) if e["id"] == msg.get("entrance")), None)
        if zone != "w" or b is None or ent is None:
            return await notice(ws, "Entrada inválida.", False) or True
        if not W.near_cell("w", x, y, W.entrance_tile(b, ent), 1.0):
            return await notice(ws, "Estás longe da porta.", False) or True
        if W.data["building_types"][b["type"]].get("private") and not game.housing_active(ch, b["id"], now):
            return await notice(ws, f"{b['name']} é uma residência privada. Arrenda um quarto na app Imóveis.", False) or True
        fz = W.floor_zone(b["id"], 0)
        _, fl = W.parse_zone(fz)
        await move_zone(peer_id, fz, W.cell_center(fz, *W.exit_cell(fl, ent["edge"])))

    elif mtype == "exit_building":
        if zone == "w":
            return True
        b, fl = W.parse_zone(zone)
        edge = fl.exits.get(str(msg.get("exit", "")))
        if fl.idx != 0 or edge is None:
            return await notice(ws, "Saída inválida.", False) or True
        if not W.near_cell(zone, x, y, W.exit_cell(fl, edge), 1.0):
            return await notice(ws, "Estás longe da saída.", False) or True
        ent = next(e for e in b["entrances"] if e["id"] == msg.get("exit"))
        await move_zone(peer_id, "w", W.cell_center("w", *W.entrance_tile(b, ent)))

    elif mtype == "use_stairs":
        if zone == "w":
            return True
        b, fl = W.parse_zone(zone)
        try:
            st = b["stairs"][int(msg.get("stair", -1))]
        except (ValueError, IndexError, TypeError):
            return await notice(ws, "Escada inválida.", False) or True
        up = msg.get("dir") == "up"
        if up and st["lo"] == fl.idx and W.near_cell(zone, x, y, (st["x"], st["y"]), 1.0):
            nz = W.floor_zone(b["id"], fl.idx + 1)
            await move_zone(peer_id, nz, W.cell_center(nz, *W.stair_landing(st)))
        elif not up and st["lo"] + 1 == fl.idx and W.near_cell(zone, x, y, W.stair_landing(st), 1.0):
            nz = W.floor_zone(b["id"], fl.idx - 1)
            await move_zone(peer_id, nz, W.cell_center(nz, st["x"], st["y"]))
        else:
            await notice(ws, "Aproxima-te da escada.", False)

    elif mtype == "door_toggle":
        key = str(msg.get("key", ""))
        if zone == "w":
            return True
        _, fl = W.parse_zone(zone)
        if fl.walls.get(key) != "door":
            return await notice(ws, "Não há porta aí.", False) or True
        mu, mv = W.door_mid(zone, key)
        u, v = W.to_cell_space(zone, x, y)
        if math.hypot(u - mu, v - mv) > 1.6:
            return await notice(ws, "Estás longe da porta.", False) or True
        cur = door_states.get(zone, {}).get(key, True)
        if cur:   # fechar: ninguém pode estar no vão da porta
            for pid in peers_in_zone(zone):
                p = players_in_world[pid]["position"]
                pu, pv = W.to_cell_space(zone, p["x"], p["y"])
                if math.hypot(pu - mu, pv - mv) < 0.5:
                    return await notice(ws, "Está alguém na porta.", False) or True
        door_states.setdefault(zone, {})[key] = not cur
        dirty = True
        for pid in peers_in_zone(zone):
            await send(peers[pid], {"type": "door_state", "zone": zone, "key": key, "open": not cur})

    elif mtype == "interact":
        fid, action = str(msg.get("fid", "")), str(msg.get("action", ""))
        obj = W.find_furniture(zone, fid)
        if obj is None or action not in obj.get("actions", []):
            return await notice(ws, "Não podes fazer isso aqui.", False) or True
        if not W.near_cells(zone, x, y, W.object_cells(obj), 1.0):
            return await notice(ws, "Aproxima-te mais.", False) or True
        if peer_id in activities:
            return await notice(ws, "Já estás ocupado.", False) or True
        bid = None if zone == "w" else W.parse_zone(zone)[0]["id"]
        a = W.activities[action]
        if "shop" in a:
            ok, text = game.buy(ch, W, action, str(msg.get("item", "")), msg.get("qty", 1) or 1, now)
            dirty = dirty or ok
            await notice(ws, text, ok)
        elif action == "sell":
            ok, text = game.sell(ch, W, str(msg.get("item", "")), now)
            dirty = dirty or ok
            await notice(ws, text, ok)
        else:
            ok, why = game.check_activity(ch, W, action, bid, now)
            if not ok:
                return await notice(ws, why, False) or True
            if occupied.get((zone, fid)) not in (None, peer_id):
                return await notice(ws, "Está ocupado por outra pessoa.", False) or True
            secs = float(a["secs"]) * ACTIVITY_SCALE
            act = {"action": action, "fid": fid, "zone": zone, "building": bid, "secs": secs,
                   "until": time.time() + secs, "pos": (x, y)}
            activities[peer_id] = act
            occupied[(zone, fid)] = peer_id
            act["task"] = asyncio.create_task(run_activity(peer_id, act))
            await send(ws, {"type": "activity_started", "action": action, "fid": fid, "secs": act["secs"], "status": a.get("status", a["label"])})
            await broadcast_world({"type": "player_activity", "peer_id": peer_id, "action": action, "fid": fid, "zone": zone}, exclude_peer=peer_id)
        await send_self(peer_id)

    elif mtype == "cancel_activity":
        if cancel_activity(peer_id):
            await send(ws, {"type": "activity_done", "action": None, "text": "Atividade cancelada."})
            await broadcast_world({"type": "player_activity", "peer_id": peer_id, "action": None})
        await send_self(peer_id)

    elif mtype == "use_item":
        ok, text = game.use_item(ch, W, str(msg.get("item", "")))
        dirty = dirty or ok
        await notice(ws, text, ok)
        await send_self(peer_id)

    elif mtype in ("job_apply", "job_quit", "rent"):
        if mtype == "job_apply":
            ok, text = game.job_apply(ch, W, str(msg.get("job", "")))
        elif mtype == "job_quit":
            ok, text = game.job_quit(ch, W)
        else:
            ok, text = game.rent(ch, W, str(msg.get("rental", "")), msg.get("days", 1) if isinstance(msg.get("days"), int) else -1, now)
        dirty = dirty or ok
        await notice(ws, text, ok)
        await send_self(peer_id)

    elif mtype == "profile_request":
        await send(ws, {"type": "profile", "data": {"name": ch["name"], "background": ch.get("background", {}),
                                                    "job": ch.get("job"), "housing": ch["housing"], "created_at": ch.get("created_at", "")}})

    elif mtype == "chat":
        text = "".join(c for c in str(msg.get("text", "")) if c.isprintable()).strip()[:120]
        if not text:
            return True
        if time.time() - last_chat.get(peer_id, 0) < 0.8:
            return await notice(ws, "Calma — mensagens demasiado rápidas.", False) or True
        last_chat[peer_id] = time.time()
        out = {"type": "chat", "peer_id": peer_id, "name": ch["name"], "text": text, "zone": zone}
        for pid in peers_in_zone(zone):          # proximidade: mesma zona e até 600 px (interiores: o piso todo)
            p = players_in_world[pid]["position"]
            if zone != "w" or math.hypot(p["x"] - x, p["y"] - y) <= 600:
                await send(peers[pid], out)
    return True


async def handle_message(ws: Any, raw: str) -> None:
    global dirty
    try:
        msg = json.loads(raw)
        if not isinstance(msg, dict):
            raise ValueError
    except (json.JSONDecodeError, ValueError):
        await send(ws, {"type": "error", "error": "JSON inválido"})
        return

    mtype = msg.get("type", "")
    info = clients.get(ws)
    if info is None:
        return
    peer_id = info["peer_id"]

    if mtype in ("register", "login"):
        fn = register if mtype == "register" else login
        result = fn(str(msg.get("username", "")), str(msg.get("password", "")))
        if result["ok"]:
            info["account_id"] = result["data"]["account_id"]
            info["token"] = issue_session(info["account_id"])
            result["data"]["session_token"] = info["token"]
            await send(ws, {"type": "auth_response", "success": True, "data": result["data"], "error": ""})
        else:
            await send(ws, {"type": "auth_response", "success": False, "data": {}, "error": result["error"]})

    elif mtype == "resume_session":
        acc = resolve_session(str(msg.get("token", "")))
        if acc is None:
            await send(ws, {"type": "session_invalid", "error": "Sessão expirada"})
            return
        info["account_id"] = acc["id"]
        info["token"] = str(msg.get("token", ""))
        await send(ws, {"type": "auth_response", "success": True, "resumed": True, "data": profile_data(acc), "error": ""})

    elif mtype == "logout":
        if info.get("token"):
            revoke_session(info["token"])
        await leave_world(peer_id)
        info.update({"account_id": None, "token": None, "character_id": None})
        await send(ws, {"type": "logged_out"})

    elif mtype == "onboarding_progress":
        acc = account_by_id(info["account_id"]) if info["account_id"] else None
        if acc is None:
            await send(ws, {"type": "error", "error": "Não autenticado"})
            return
        ob = advance_onboarding(acc, str(msg.get("state", "")), msg.get("step", 0))
        await send(ws, {"type": "onboarding_state", "state": ob["state"], "story_step": int(ob.get("story_step", 0))})

    elif mtype == "create_character":
        if not info["account_id"]:
            await send(ws, {"type": "character_created", "success": False, "data": {}, "error": "Não autenticado"})
            return
        # account_id vem SEMPRE da sessão autenticada, nunca do cliente
        result = create_character(info["account_id"], msg.get("appearance", {}), str(msg.get("name", "")))
        if result["ok"]:
            await send(ws, {"type": "character_created", "success": True, "data": result["data"], "error": ""})
        else:
            await send(ws, {"type": "character_created", "success": False, "data": {}, "error": result["error"]})

    elif mtype == "enter_world":
        cid = str(msg.get("character_id", ""))
        ch = characters.get(cid)
        if not info["account_id"] or ch is None or ch.get("account_id") != info["account_id"]:
            await send(ws, {"type": "error", "error": "Personagem inválido ou não autenticado"})
            return
        if peer_id in players_in_world:
            return
        if len(players_in_world) >= int(WORLD.get("max_players", 64)):
            await send(ws, {"type": "error", "error": "Mundo cheio"})
            return
        # Mesma personagem já online noutra ligação (ex.: crash/reconexão) -> substitui a sessão antiga
        for old_pid, old in list(players_in_world.items()):
            if old["id"] == cid:
                old_ws = peers.get(old_pid)
                await leave_world(old_pid)
                if old_ws:
                    try:
                        await old_ws.close(1000, "Sessão substituída")
                    except Exception:
                        pass
        game.ensure_fields(ch, W)
        safe_spawn(ch)
        pos = ch["position"]
        ch["position"] = {"x": float(pos.get("x", 0.0)), "y": float(pos.get("y", 0.0))}
        info["character_id"] = cid
        players_in_world[peer_id] = {"id": cid, "name": ch["name"], "appearance": ch.get("appearance", {}),
                                     "position": ch["position"], "zone": ch["zone"]}
        for pid, pdata in players_in_world.items():           # o novo recebe todos (incluindo ele próprio)
            await send(ws, {"type": "spawn_player", "data": public_view(pid, pdata)})
        await broadcast_world({"type": "spawn_player", "data": public_view(peer_id, players_in_world[peer_id])}, exclude_peer=peer_id)
        if ch["zone"] != "w":
            await send(ws, {"type": "zone_state", "zone": ch["zone"], "doors": door_states.get(ch["zone"], {})})
        await send_self(peer_id)
        print(f"[World] {ch['name']} entrou (peer {peer_id}); online: {len(players_in_world)}")

    elif mtype == "position":
        me = players_in_world.get(peer_id)
        x, y = finite(msg.get("x")), finite(msg.get("y"))
        if me is None or x is None or y is None:
            return
        zone = me.get("zone", "w")
        old = me["position"]
        # Validação autoritativa: dentro da zona, em célula caminhável, sem atravessar paredes nem teletransportar.
        bad = (math.hypot(x - old["x"], y - old["y"]) > MAX_STEP_PX or not W.walkable_point(zone, x, y)
               or W.crosses_wall(zone, old["x"], old["y"], x, y, door_states.get(zone, {})))
        if bad:
            await send(ws, {"type": "position_correction", "x": old["x"], "y": old["y"], "zone": zone})
            return
        act = activities.get(peer_id)
        if act and math.hypot(x - act["pos"][0], y - act["pos"][1]) > 10:
            cancel_activity(peer_id)                 # mexer-se interrompe a atividade
            await send(ws, {"type": "activity_done", "action": None, "text": "Atividade interrompida."})
            await broadcast_world({"type": "player_activity", "peer_id": peer_id, "action": None})
        me["position"] = {"x": x, "y": y}
        characters[me["id"]]["position"] = {"x": x, "y": y}
        dirty = True
        await broadcast_world({"type": "position", "peer_id": peer_id, "x": x, "y": y, "zone": zone}, exclude_peer=peer_id)

    elif await handle_game(ws, peer_id, mtype, msg):
        pass

    else:
        await send(ws, {"type": "error", "error": f"Tipo desconhecido: {mtype}"})


async def autosave_loop() -> None:
    global dirty
    while True:
        await asyncio.sleep(5)
        if dirty:
            dirty = False
            save_all()


TICK = 5.0


async def needs_loop() -> None:
    """Relógio + necessidades (fome/energia/higiene/saúde) avançam no servidor; cada jogador recebe o seu estado."""
    global dirty
    while True:
        await asyncio.sleep(TICK)
        hours = TICK * clock.scale / 3600.0
        for pid in list(players_in_world):
            ch = char_of(pid)
            if ch is None:
                continue
            game.decay(ch, hours, W.needs_cfg)
            dirty = True
            await send_self(pid)


# ---------------------------------------------------------------------------
# Connection lifecycle
# ---------------------------------------------------------------------------
async def handler(ws: Any) -> None:
    peer_id = uuid.uuid4().hex[:12]
    clients[ws] = {"peer_id": peer_id, "account_id": None, "character_id": None, "token": None}
    peers[peer_id] = ws
    print(f"[Net] Conectado: {peer_id}")
    await send(ws, {"type": "welcome", "peer_id": peer_id})
    try:
        async for raw in ws:
            if isinstance(raw, bytes):
                continue
            await handle_message(ws, raw)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        await leave_world(peer_id)
        peers.pop(peer_id, None)
        clients.pop(ws, None)
        save_all()
        print(f"[Net] Desconectado: {peer_id}")


async def main() -> None:
    ensure_data_dir()
    load_all()
    host = os.environ.get("ANGOLA_HOST", HOST)
    port = int(os.environ.get("ANGOLA_PORT", PORT))
    print("=== Angola Life Simulator — Servidor Python ===")
    print(f"A escutar em ws://{host}:{port}  (spawn {WORLD['spawn']})")
    print("Ctrl+C para parar.\n", flush=True)
    asyncio.create_task(autosave_loop())
    asyncio.create_task(needs_loop())
    async with websockets.serve(handler, host, port, ping_interval=20, ping_timeout=20):
        await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServidor parado.")
        save_all()

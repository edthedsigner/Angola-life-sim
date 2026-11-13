"""Sistema social (servidor autoritativo): perfis públicos, níveis, amizades, bloqueios, privacidade de chamadas,
convites (casa / sítio público / jogo), presentes (dinheiro / artigos), mensagens privadas, chamadas de voz
(sinalização WebRTC) e notificações.

Regras de segurança (docs/SOCIAL.md):
* Os jogadores são endereçados por um identificador PÚBLICO opaco ("pub"), nunca pelo id interno da personagem.
* Perfil público = nome, aparência, nível, estado público, data de entrada, relação com quem vê. Nunca dinheiro,
  inventário, necessidades, emprego, casa, história de vida, mensagens ou ids internos.
* O cliente nunca decide: amizade, posse, saldo, permissão de chamada, validade de convites — tudo é verificado aqui.
* Presentes: verificação + transferência sem `await` pelo meio (atómico no loop asyncio) e idempotentes por `req_id`.

Este módulo não faz rede: devolve resultados e "entregas" [(cid, mensagem)] que o server.py envia a quem estiver online.
"""
from __future__ import annotations

import math
import os
import secrets
import time

FRIEND_LIMIT = 200
DM_MAX = 500
DM_KEEP = 200
NOTIF_KEEP = 60
INVITE_TTL = float(os.environ.get("ANGOLA_INVITE_TTL", 10 * 60.0))      # segundos reais
GAME_INVITE_TTL = float(os.environ.get("ANGOLA_GAME_INVITE_TTL", 2 * 60.0))   # convite para jogar: expira mais depressa
GUEST_TTL = 30 * 60.0
CALL_RING_TTL = float(os.environ.get("ANGOLA_CALL_RING_SECS", 30.0))
GIFT_MAX = 1_000_000
CALL_PRIVACY = ("everyone", "friends", "nobody")


def now() -> float:
    return time.time()


class Social:
    def __init__(self, state: dict, characters: dict, W, game):
        self.W = W
        self.game = game
        self.characters = characters
        s = state or {}
        self.friends: dict[str, list] = s.get("friends", {})
        self.requests: dict[str, dict] = s.get("requests", {})        # destinatário -> {remetente: t}
        self.blocks: dict[str, list] = s.get("blocks", {})
        self.dms: dict[str, list] = s.get("dms", {})                  # "cidA|cidB" ordenado -> mensagens
        self.unread: dict[str, dict] = s.get("unread", {})            # cid -> {outro: n}
        self.notifs: dict[str, list] = s.get("notifs", {})
        self.invites: dict[str, dict] = s.get("invites", {})
        self.guests: dict[str, dict] = s.get("guests", {})            # building -> {cid: até}
        self.gift_reqs: dict[str, dict] = s.get("gift_reqs", {})      # cid -> {req_id: resultado}
        self.calls: dict[str, dict] = {}                              # só em memória
        self.rate: dict[tuple, float] = {}
        self.by_pub: dict[str, str] = {}
        for cid, ch in characters.items():
            self.ensure(ch)

    def dump(self) -> dict:
        self.expire()
        return {"friends": self.friends, "requests": self.requests, "blocks": self.blocks, "dms": self.dms, "unread": self.unread,
                "notifs": self.notifs, "invites": self.invites, "guests": self.guests, "gift_reqs": self.gift_reqs}

    # ------------------------------------------------------------------ identidade, nível, perfil
    def ensure(self, ch: dict) -> None:
        if not ch.get("pub"):
            ch["pub"] = secrets.token_hex(5)
        ch.setdefault("xp", 0)
        priv = ch.get("privacy") if isinstance(ch.get("privacy"), dict) else {}
        ch["privacy"] = {"calls": priv.get("calls", "everyone") if priv.get("calls") in CALL_PRIVACY else "everyone"}
        self.by_pub[ch["pub"]] = ch["id"]

    def cid_of(self, pub: str) -> str | None:
        return self.by_pub.get(str(pub or ""))

    def level_of(self, xp: int) -> tuple[int, int, int]:
        """Nível n precisa de base*(n-1)*n/2 XP acumulado. Devolve (nível, xp no nível, xp para o próximo)."""
        base = int(self.W.data.get("progression", {}).get("level_base", 100))
        n = 1 + int((math.sqrt(1 + 8 * max(0, xp) / base) - 1) / 2)
        start = base * (n - 1) * n // 2
        return n, xp - start, base * n

    def award_xp(self, ch: dict, action: str) -> int:
        gain = int(self.W.data.get("progression", {}).get("xp", {}).get(action, 0))
        ch["xp"] = int(ch.get("xp", 0)) + gain
        return gain

    def relation(self, viewer: str, target: str) -> str:
        if viewer == target:
            return "self"
        if target in self.blocks.get(viewer, []):
            return "blocked"
        if target in self.friends.get(viewer, []):
            return "friends"
        if viewer in self.requests.get(target, {}):
            return "request_sent"
        if target in self.requests.get(viewer, {}):
            return "request_received"
        return "none"

    def public_profile(self, target_cid: str, viewer_cid: str, status: str, online: bool) -> dict:
        ch = self.characters[target_cid]
        lvl, into, need = self.level_of(int(ch.get("xp", 0)))
        rel = self.relation(viewer_cid, target_cid)
        blocked_me = viewer_cid in self.blocks.get(target_cid, [])
        out = {"pub": ch["pub"], "name": ch["name"], "appearance": ch.get("appearance", {}), "level": lvl,
               "status": status if online else "Offline", "online": online, "since": str(ch.get("created_at", ""))[:10],
               "friends_count": len(self.friends.get(target_cid, [])), "relation": rel,
               # o que o cliente pode mostrar como disponível (o servidor volta a verificar tudo)
               "can_call": online and not blocked_me and rel != "blocked" and self.call_allowed(viewer_cid, target_cid)[0],
               "can_message": not blocked_me and rel != "blocked"}
        if rel == "self":
            out["xp"] = {"into": into, "need": need}
        return out

    # ------------------------------------------------------------------ utilidades
    def _limit(self, key: tuple, secs: float) -> bool:
        t = now()
        if t - self.rate.get(key, 0) < secs:
            return False
        self.rate[key] = t
        return True

    def blocked_between(self, a: str, b: str) -> bool:
        return b in self.blocks.get(a, []) or a in self.blocks.get(b, [])

    def notify(self, cid: str, kind: str, from_cid: str | None, text: str, data: dict | None = None, actions: list | None = None,
               collapse: str | None = None) -> tuple:
        """Guarda e devolve (cid, mensagem). `collapse` substitui uma notificação anterior com a mesma chave (sem inundar)."""
        lst = self.notifs.setdefault(cid, [])
        if collapse:
            lst[:] = [n for n in lst if n.get("collapse") != collapse]
        fch = self.characters.get(from_cid or "", {})
        n = {"nid": secrets.token_hex(6), "kind": kind, "text": text, "t": now(), "read": False,
             "from": {"pub": fch.get("pub"), "name": fch.get("name")} if fch else None, "data": data or {}, "actions": actions or []}
        if collapse:
            n["collapse"] = collapse
        lst.append(n)
        del lst[:-NOTIF_KEEP]
        return (cid, {"type": "notification", "data": self._notif_out(n)})

    @staticmethod
    def _notif_out(n: dict) -> dict:
        return {k: v for k, v in n.items() if k != "collapse"}

    def resolve_notif(self, cid: str, kind: str, key: str, value) -> None:
        for n in self.notifs.get(cid, []):
            if n["kind"] == kind and n["data"].get(key) == value:
                n["actions"] = []
                n["read"] = True

    # ------------------------------------------------------------------ amizades e bloqueios
    def friend_request(self, me: str, other: str):
        out = []
        if me == other:
            return False, "Não te podes adicionar a ti próprio.", out
        if self.blocked_between(me, other):
            return False, "Não é possível enviar o pedido.", out
        rel = self.relation(me, other)
        if rel == "friends":
            return False, "Já são amigos.", out
        if rel == "request_sent":
            return False, "Já enviaste um pedido a esta pessoa.", out
        if rel == "request_received":                   # os dois quiseram: aceita automaticamente
            return self.friend_accept(me, other)
        if len(self.friends.get(me, [])) >= FRIEND_LIMIT:
            return False, "Lista de amigos cheia.", out
        if not self._limit(("freq", me), 0.5):
            return False, "Calma — espera um pouco.", out
        self.requests.setdefault(other, {})[me] = now()
        out.append(self.notify(other, "friend_request", me, f"{self.characters[me]['name']} quer ser teu amigo.",
                               {"pub": self.characters[me]["pub"]}, ["accept", "decline"]))
        return True, "Pedido de amizade enviado.", out

    def friend_accept(self, me: str, other: str):
        out = []
        if other not in self.requests.get(me, {}):
            return False, "Não há pedido desta pessoa.", out
        del self.requests[me][other]
        for a, b in ((me, other), (other, me)):
            lst = self.friends.setdefault(a, [])
            if b not in lst:
                lst.append(b)
        self.resolve_notif(me, "friend_request", "pub", self.characters[other]["pub"])
        out.append(self.notify(other, "friend_accepted", me, f"{self.characters[me]['name']} aceitou o teu pedido de amizade.",
                               {"pub": self.characters[me]["pub"]}))
        return True, f"Tu e {self.characters[other]['name']} são agora amigos.", out

    def friend_decline(self, me: str, other: str):
        if other not in self.requests.get(me, {}):
            return False, "Não há pedido desta pessoa.", []
        del self.requests[me][other]
        self.resolve_notif(me, "friend_request", "pub", self.characters[other]["pub"])
        return True, "Pedido recusado.", []          # o remetente não é avisado (evita pressão social)

    def friend_cancel(self, me: str, other: str):
        if me not in self.requests.get(other, {}):
            return False, "Não há pedido pendente.", []
        del self.requests[other][me]
        self.resolve_notif(other, "friend_request", "pub", self.characters[me]["pub"])
        return True, "Pedido cancelado.", []

    def friend_remove(self, me: str, other: str):
        if other not in self.friends.get(me, []):
            return False, "Não são amigos.", []
        self.friends[me].remove(other)
        if me in self.friends.get(other, []):
            self.friends[other].remove(me)
        return True, "Amizade removida.", []

    def block(self, me: str, other: str):
        if me == other:
            return False, "Inválido.", []
        lst = self.blocks.setdefault(me, [])
        if other not in lst:
            lst.append(other)
        self.friend_remove(me, other)
        self.requests.get(me, {}).pop(other, None)
        self.requests.get(other, {}).pop(me, None)
        for iid, inv in self.invites.items():       # convites pendentes entre os dois caducam
            if {inv["from"], inv["to"]} == {me, other} and inv["state"] == "pending":
                inv["state"] = "cancelled"
        return True, "Jogador bloqueado: não te pode ligar, escrever, convidar nem dar presentes.", []

    def unblock(self, me: str, other: str):
        if other in self.blocks.get(me, []):
            self.blocks[me].remove(other)
            return True, "Desbloqueado.", []
        return False, "Não estava bloqueado.", []

    def set_privacy(self, me: str, calls: str):
        if calls not in CALL_PRIVACY:
            return False, "Opção inválida.", []
        self.characters[me]["privacy"]["calls"] = calls
        return True, "Privacidade atualizada.", []

    # ------------------------------------------------------------------ convites
    def expire(self) -> list:
        out, t = [], now()
        for iid, inv in list(self.invites.items()):
            if inv["state"] == "pending" and inv["expires"] <= t:
                inv["state"] = "expired"
                self.resolve_notif(inv["to"], "invite", "iid", iid)
            if inv["state"] != "pending" and t - inv["expires"] > 3600:
                del self.invites[iid]
        for b, gs in self.guests.items():
            for cid in [c for c, until in gs.items() if until <= t]:
                del gs[cid]
        return out

    def places(self) -> dict:
        """Sítios públicos convidáveis: edifícios não privados (o mapa define-os)."""
        return {bid: b["name"] for bid, b in self.W.buildings.items() if not self.W.data["building_types"][b["type"]].get("private")}

    def invite(self, me: str, other: str, kind: str, place: str, game_id: str, game_s: float):
        out = []
        self.expire()
        if me == other or other not in self.characters:
            return False, "Convite inválido.", out, None
        if self.blocked_between(me, other):
            return False, "Não é possível convidar esta pessoa.", out, None
        for inv in self.invites.values():
            if inv["from"] == me and inv["to"] == other and inv["state"] == "pending" and inv["kind"] == kind:
                return False, "Já tens um convite pendente para esta pessoa.", out, None
        me_ch = self.characters[me]
        data: dict = {"kind": kind}
        if kind == "house":
            h = me_ch.get("housing") or {}
            if not (h.get("status") == "arrendado" and float(h.get("until", 0)) > game_s):
                return False, "Não tens casa para receber visitas (arrenda na app Imóveis).", out, None
            bid = h["building"]
            data.update(building=bid, place_name=f"Casa de {me_ch['name']} · {self.W.buildings[bid]['name']}")
        elif kind == "place":
            if place not in self.places():
                return False, "Escolhe um sítio público.", out, None
            data.update(building=place, place_name=self.places()[place])
        elif kind == "game":
            games = self.W.data.get("games", {})
            if game_id not in games:
                return False, "Esse jogo não existe.", out, None
            data.update(game=game_id, place_name=games[game_id]["name"])
        else:
            return False, "Tipo de convite inválido.", out, None
        if not self._limit(("inv", me), 0.8):        # só convites válidos contam para o limite
            return False, "Calma — espera um pouco.", out, None
        iid = secrets.token_hex(6)
        inv = {"iid": iid, "from": me, "to": other, "kind": kind, "state": "pending", "created": now(), "expires": now() + (GAME_INVITE_TTL if kind == "game" else INVITE_TTL), **data}
        self.invites[iid] = inv
        label = {"house": "para a casa dele(a)", "place": f"para {data['place_name']}", "game": f"para jogar {data['place_name']}"}[kind]
        out.append(self.notify(other, "invite", me, f"{me_ch['name']} convidou-te {label}.", {"iid": iid, **self.invite_out(inv)}, ["accept", "decline"]))
        return True, "Convite enviado.", out, iid

    def invite_out(self, inv: dict) -> dict:
        return {"iid": inv["iid"], "kind": inv["kind"], "state": inv["state"], "place_name": inv.get("place_name", ""),
                "building": inv.get("building"), "game": inv.get("game"), "expires_in": max(0, int(inv["expires"] - now())),
                "from": self.characters[inv["from"]]["pub"], "to": self.characters[inv["to"]]["pub"]}

    def invite_respond(self, me: str, iid: str, accept: bool):
        out = []
        self.expire()
        inv = self.invites.get(str(iid))
        if not inv or inv["to"] != me:
            return False, "Convite inexistente.", out, None
        if inv["state"] != "pending":
            return False, {"expired": "O convite expirou.", "cancelled": "O convite foi cancelado."}.get(inv["state"], "O convite já foi respondido."), out, None
        inv["state"] = "accepted" if accept else "declined"
        self.resolve_notif(me, "invite", "iid", iid)
        name = self.characters[me]["name"]
        if accept and inv["kind"] == "house":
            self.guests.setdefault(inv["building"], {})[me] = now() + GUEST_TTL     # acesso de visita (a casa continua a exigir o anfitrião com renda)
            inv["host"] = inv["from"]
        out.append(self.notify(inv["from"], "invite_reply", me, f"{name} {'aceitou' if accept else 'recusou'} o teu convite ({inv.get('place_name', '')}).",
                               {"iid": iid, "accepted": accept}))
        return True, ("Convite aceite — a mostrar o caminho." if accept else "Convite recusado."), out, self.invite_out(inv)

    def invite_cancel(self, me: str, iid: str):
        inv = self.invites.get(str(iid))
        if not inv or inv["from"] != me or inv["state"] != "pending":
            return False, "Não há convite pendente para cancelar.", []
        inv["state"] = "cancelled"
        self.resolve_notif(inv["to"], "invite", "iid", iid)
        return True, "Convite cancelado.", []

    def guest_allowed(self, cid: str, bid: str, game_s: float) -> bool:
        """Visita autorizada: convite aceite há < GUEST_TTL E o anfitrião ainda tem a casa arrendada."""
        if self.guests.get(bid, {}).get(cid, 0) <= now():
            return False
        for inv in self.invites.values():
            if inv["to"] == cid and inv["kind"] == "house" and inv["state"] == "accepted" and inv.get("building") == bid:
                host = self.characters.get(inv["from"], {})
                if self.game.housing_active(host, bid, game_s) and not self.blocked_between(cid, inv["from"]):
                    return True
        return False

    # ------------------------------------------------------------------ presentes (atómicos e idempotentes)
    def _gift_done(self, me: str, req_id: str):
        return self.gift_reqs.get(me, {}).get(req_id)

    def _gift_record(self, me: str, req_id: str, result: tuple) -> None:
        d = self.gift_reqs.setdefault(me, {})
        d[req_id] = [result[0], result[1]]
        while len(d) > 100:
            d.pop(next(iter(d)))

    def gift_money(self, me: str, other: str, amount, req_id: str, game_s: float):
        req_id = str(req_id or "")[:40]
        if len(req_id) < 8:
            return False, "Pedido inválido.", [], False
        prev = self._gift_done(me, req_id)
        if prev:                                     # pedido repetido (duplo clique, reenvio): não transfere outra vez
            return prev[0], prev[1], [], True
        if me == other or other not in self.characters:
            res = (False, "Destinatário inválido.")
        elif self.blocked_between(me, other):
            res = (False, "Não é possível enviar presentes a esta pessoa.")
        elif not isinstance(amount, int) or isinstance(amount, bool) or amount <= 0 or amount > GIFT_MAX:
            res = (False, "Valor inválido.")
        elif self.characters[me]["money"] < amount:
            res = (False, "Dinheiro insuficiente.")
        else:
            a, b = self.characters[me], self.characters[other]
            a["money"] -= amount                     # sem await entre a verificação e as duas escritas
            b["money"] += amount
            self.game.add_tx(a, f"Presente para {b['name']}", -amount, game_s)
            self.game.add_tx(b, f"Presente de {a['name']}", amount, game_s)
            res = (True, f"Enviaste {amount} Kz a {b['name']}.")
            self._gift_record(me, req_id, res)
            return True, res[1], [self.notify(other, "gift", me, f"{a['name']} enviou-te {amount} Kz.", {"amount": amount})], False
        self._gift_record(me, req_id, res)
        return res[0], res[1], [], False

    def gift_item(self, me: str, other: str, item: str, qty, req_id: str):
        req_id = str(req_id or "")[:40]
        if len(req_id) < 8:
            return False, "Pedido inválido.", [], False
        prev = self._gift_done(me, req_id)
        if prev:
            return prev[0], prev[1], [], True
        a = self.characters[me]
        if me == other or other not in self.characters:
            res = (False, "Destinatário inválido.")
        elif self.blocked_between(me, other):
            res = (False, "Não é possível enviar presentes a esta pessoa.")
        elif not isinstance(qty, int) or isinstance(qty, bool) or qty <= 0 or qty > 99:
            res = (False, "Quantidade inválida.")
        elif item not in self.W.items or a["inventory"].get(item, 0) < qty:
            res = (False, "Não tens esse artigo nessa quantidade.")
        else:
            b = self.characters[other]
            a["inventory"][item] -= qty
            if a["inventory"][item] <= 0:
                del a["inventory"][item]
            b["inventory"][item] = b["inventory"].get(item, 0) + qty
            name = self.W.items[item]["name"]
            res = (True, f"Enviaste {name} x{qty} a {b['name']}.")
            self._gift_record(me, req_id, res)
            return True, res[1], [self.notify(other, "gift", me, f"{a['name']} enviou-te {name} x{qty}.", {"item": item, "qty": qty})], False
        self._gift_record(me, req_id, res)
        return res[0], res[1], [], False

    # ------------------------------------------------------------------ mensagens privadas
    @staticmethod
    def pair(a: str, b: str) -> str:
        return "|".join(sorted((a, b)))

    def dm_send(self, me: str, other: str, text: str):
        text = "".join(c for c in str(text or "") if c.isprintable() or c == "\n").strip()[:DM_MAX]
        if not text:
            return False, "Mensagem vazia.", [], None
        if me == other or other not in self.characters:
            return False, "Destinatário inválido.", [], None
        if self.blocked_between(me, other):
            return False, "Não podes enviar mensagens a esta pessoa.", [], None
        if not self._limit(("dm", me), 0.4):
            return False, "Mensagens demasiado rápidas.", [], None
        msg = {"mid": secrets.token_hex(6), "from": me, "text": text, "t": now()}
        conv = self.dms.setdefault(self.pair(me, other), [])
        conv.append(msg)
        del conv[:-DM_KEEP]
        u = self.unread.setdefault(other, {})
        u[me] = u.get(me, 0) + 1
        a = self.characters[me]
        out = [(other, {"type": "dm_message", "data": self.dm_out(msg, other), "with": a["pub"], "name": a["name"], "unread": u[me]}),
               self.notify(other, "dm", me, f"Mensagem de {a['name']}: {text[:60]}", {"pub": a["pub"]}, collapse=f"dm:{me}")]
        return True, "", out, self.dm_out(msg, me)

    def dm_out(self, msg: dict, viewer: str) -> dict:
        return {"mid": msg["mid"], "mine": msg["from"] == viewer, "text": msg["text"], "t": msg["t"]}

    def dm_history(self, me: str, other: str) -> list:
        return [self.dm_out(m, me) for m in self.dms.get(self.pair(me, other), [])[-100:]]

    def dm_read(self, me: str, other: str) -> None:
        self.unread.get(me, {}).pop(other, None)
        for n in self.notifs.get(me, []):
            if n["kind"] == "dm" and n["data"].get("pub") == self.characters[other]["pub"]:
                n["read"] = True

    def conversations(self, me: str) -> list:
        out = []
        for key, conv in self.dms.items():
            a, b = key.split("|")
            if me not in (a, b) or not conv:
                continue
            other = b if a == me else a
            och = self.characters.get(other)
            if not och:
                continue
            last = conv[-1]
            out.append({"pub": och["pub"], "name": och["name"], "appearance": och.get("appearance", {}), "last": last["text"][:80],
                        "last_mine": last["from"] == me, "t": last["t"], "unread": self.unread.get(me, {}).get(other, 0)})
        return sorted(out, key=lambda c: -c["t"])

    # ------------------------------------------------------------------ chamadas de voz (sinalização; o áudio vai P2P)
    def call_allowed(self, caller: str, callee: str) -> tuple[bool, str]:
        if caller == callee:
            return False, "self"
        if self.blocked_between(caller, callee):
            return False, "blocked"
        pref = self.characters[callee].get("privacy", {}).get("calls", "everyone")
        if pref == "nobody":
            return False, "privacy"
        if pref == "friends" and caller not in self.friends.get(callee, []):
            return False, "privacy"
        return True, ""

    def in_call(self, cid: str) -> str | None:
        for k, c in self.calls.items():
            if cid in (c["caller"], c["callee"]) and c["state"] in ("ringing", "active"):
                return k
        return None

    def call_start(self, me: str, other: str, online: bool):
        out = []
        reasons = {"self": "Não te podes ligar a ti próprio.", "blocked": "Não é possível ligar a esta pessoa.",
                   "privacy": "Esta pessoa não aceita chamadas tuas (definições de privacidade).",
                   "offline": "Está offline.", "busy": "Está noutra chamada.", "me_busy": "Já estás numa chamada."}
        if other not in self.characters:
            return False, "Destinatário inválido.", out, None, "invalid"
        ok, why = self.call_allowed(me, other)
        if not ok:
            return False, reasons[why], out, None, why
        if not online:
            return False, reasons["offline"], out, None, "offline"
        if self.in_call(me):
            return False, reasons["me_busy"], out, None, "me_busy"
        if self.in_call(other):
            out.append(self.notify(other, "missed_call", me, f"Chamada não atendida de {self.characters[me]['name']} (estavas ocupado).", {"pub": self.characters[me]["pub"]}))
            return False, reasons["busy"], out, None, "busy"
        if not self._limit(("call", me), 1.0):
            return False, "Espera um pouco antes de voltar a ligar.", out, None, "rate"
        call_id = secrets.token_hex(8)
        self.calls[call_id] = {"caller": me, "callee": other, "state": "ringing", "t": now()}
        a = self.characters[me]
        out.append((other, {"type": "call_incoming", "call_id": call_id, "from": {"pub": a["pub"], "name": a["name"], "appearance": a.get("appearance", {})}}))
        return True, "A chamar…", out, call_id, ""

    def call_answer(self, me: str, call_id: str, accept: bool):
        c = self.calls.get(str(call_id))
        if not c or c["callee"] != me or c["state"] != "ringing":
            return False, "Chamada inexistente.", []
        a = self.characters[me]
        if not accept:
            c["state"] = "ended"
            return True, "Chamada recusada.", [(c["caller"], {"type": "call_ended", "call_id": call_id, "reason": "declined"})]
        c["state"] = "active"
        c["started"] = now()
        return True, "", [(c["caller"], {"type": "call_accepted", "call_id": call_id, "role": "offerer", "peer": {"pub": a["pub"], "name": a["name"]}})]

    def call_end(self, me: str, call_id: str, reason: str = "hangup"):
        c = self.calls.get(str(call_id))
        if not c or me not in (c["caller"], c["callee"]) or c["state"] not in ("ringing", "active"):
            return False, "", []
        other = c["callee"] if me == c["caller"] else c["caller"]
        out = [(other, {"type": "call_ended", "call_id": call_id, "reason": reason if reason in ("hangup", "failed", "cancelled") else "hangup"})]
        if c["state"] == "ringing" and me == c["caller"]:
            out.append(self.notify(other, "missed_call", me, f"Chamada perdida de {self.characters[me]['name']}.", {"pub": self.characters[me]["pub"]}))
        c["state"] = "ended"
        return True, "", out

    def call_timeouts(self) -> list:
        out = []
        for k, c in list(self.calls.items()):
            if c["state"] == "ringing" and now() - c["t"] > CALL_RING_TTL:
                c["state"] = "ended"
                out.append((c["caller"], {"type": "call_ended", "call_id": k, "reason": "no_answer"}))
                out.append((c["callee"], {"type": "call_ended", "call_id": k, "reason": "missed"}))
                out.append(self.notify(c["callee"], "missed_call", c["caller"], f"Chamada perdida de {self.characters[c['caller']]['name']}.",
                                       {"pub": self.characters[c["caller"]]["pub"]}))
            if c["state"] == "ended" and now() - c["t"] > 300:
                del self.calls[k]
        return out

    def drop_calls(self, cid: str) -> list:
        """Jogador desligou-se: termina chamadas dele."""
        out = []
        k = self.in_call(cid)
        if k:
            c = self.calls[k]
            other = c["callee"] if cid == c["caller"] else c["caller"]
            c["state"] = "ended"
            out.append((other, {"type": "call_ended", "call_id": k, "reason": "offline"}))
        return out

    def rtc_relay(self, me: str, call_id: str, payload) -> list:
        """Só reencaminha sinalização (SDP/ICE) entre os DOIS participantes de uma chamada aceite."""
        c = self.calls.get(str(call_id))
        if not c or c["state"] != "active" or me not in (c["caller"], c["callee"]):
            return []
        if not isinstance(payload, dict) or payload.get("kind") not in ("offer", "answer", "ice") or len(str(payload)) > 20000:
            return []
        other = c["callee"] if me == c["caller"] else c["caller"]
        return [(other, {"type": "rtc_signal", "call_id": call_id, "payload": payload})]

    # ------------------------------------------------------------------ estado social privado
    def state_for(self, me: str, online_cids: set) -> dict:
        def card(cid):
            ch = self.characters[cid]
            return {"pub": ch["pub"], "name": ch["name"], "appearance": ch.get("appearance", {}), "level": self.level_of(int(ch.get("xp", 0)))[0],
                    "online": cid in online_cids}
        self.expire()
        mine = self.characters[me]
        return {"friends": [card(c) for c in self.friends.get(me, []) if c in self.characters],
                "incoming": [card(c) for c in self.requests.get(me, {}) if c in self.characters],
                "outgoing": [card(to) for to, d in self.requests.items() if me in d and to in self.characters],
                "blocked": [card(c) for c in self.blocks.get(me, []) if c in self.characters],
                "privacy": mine["privacy"], "level": self.level_of(int(mine.get("xp", 0))), "pub": mine["pub"],
                "notifications": [self._notif_out(n) for n in self.notifs.get(me, [])[-30:]],
                "conversations": self.conversations(me),
                "invites_out": [self.invite_out(i) for i in self.invites.values() if i["from"] == me and i["state"] == "pending"],
                "places": self.places(), "games": self.W.data.get("games", {})}

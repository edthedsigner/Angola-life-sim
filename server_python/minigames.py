"""Minijogos multijogador (autoridade total do servidor).

Infraestrutura comum a todos os jogos:
  * partidas criadas quando um convite de jogo (social.invite kind="game") é aceite;
  * participação: só os jogadores da partida a podem ver ou jogar;
  * estado sincronizado: cada alteração gera um "game_state" para cada participante;
  * turnos e jogadas validados aqui (o cliente só pede);
  * resultado, revanche (todos votam), desistência;
  * desligar/voltar: a partida espera RECONNECT_GRACE segundos; depois quem saiu perde por falta de comparência;
  * expiração: partidas paradas há IDLE_TTL segundos terminam; partidas acabadas são limpas ao fim de FINISHED_TTL.

Cada jogo tem a sua classe de regras (ex.: TicTacToe) com: id, name, min_players, max_players,
new_state(n), apply(state, seat, payload) -> erro|None, outcome(state) -> None|{...}, public(state).

As partidas vivem em memória: um reinício do servidor (deploy) termina as partidas a decorrer.
"""
from __future__ import annotations

import os
import secrets
import time

RECONNECT_GRACE = float(os.environ.get("ANGOLA_GAME_RECONNECT", 60.0))   # segundos para voltar depois de desligar
IDLE_TTL = float(os.environ.get("ANGOLA_GAME_IDLE", 15 * 60.0))           # partida parada demasiado tempo
FINISHED_TTL = 5 * 60.0                                                    # quanto tempo uma partida acabada aceita revanche


def now() -> float:
    return time.time()


class TicTacToe:
    """Jogo do Galo: 2 jogadores, X começa, alternam, 3 em linha ganha, tabuleiro cheio sem linha = empate."""
    id = "galo"
    name = "Jogo do Galo"
    min_players = 2
    max_players = 2
    MARKS = ["X", "O"]
    LINES = [(0, 1, 2), (3, 4, 5), (6, 7, 8), (0, 3, 6), (1, 4, 7), (2, 5, 8), (0, 4, 8), (2, 4, 6)]

    def new_state(self, n: int) -> dict:
        return {"board": [""] * 9, "turn": 0, "last": None}

    def apply(self, st: dict, seat: int, payload: dict) -> str | None:
        if seat != st["turn"]:
            return "Não é a tua vez."
        cell = payload.get("cell")
        if isinstance(cell, bool) or not isinstance(cell, int) or not 0 <= cell <= 8:
            return "Jogada inválida."
        if st["board"][cell] != "":
            return "Essa casa já está ocupada."
        st["board"][cell] = self.MARKS[seat]
        st["last"] = cell
        st["turn"] = 1 - seat
        return None

    def outcome(self, st: dict) -> dict | None:
        b = st["board"]
        for line in self.LINES:
            a, c, d = line
            if b[a] and b[a] == b[c] == b[d]:
                return {"winner": self.MARKS.index(b[a]), "line": list(line), "reason": "line"}
        if all(b):
            return {"draw": True, "reason": "draw"}
        return None

    def public(self, st: dict) -> dict:
        return {"board": list(st["board"]), "turn": st["turn"], "last": st["last"], "marks": self.MARKS}


GAMES = {g.id: g for g in (TicTacToe(),)}


class Minigames:
    def __init__(self, characters: dict):
        self.characters = characters
        self.matches: dict[str, dict] = {}
        self.away: dict[str, float] = {}          # cid -> quando desligou (com partida ativa)

    # ---------------------------------------------------------------- consulta
    def active_of(self, cid: str) -> dict | None:
        for m in self.matches.values():
            if m["status"] == "active" and cid in m["players"]:
                return m
        return None

    def latest_of(self, cid: str) -> dict | None:
        """Partida a mostrar a quem (re)entra: a ativa, ou a última acabada ainda com revanche possível."""
        best = None
        for m in self.matches.values():
            if cid in m["players"] and cid not in m["left"] and (best is None or m["updated"] > best["updated"]):
                best = m
        return best

    def busy(self, cid: str) -> bool:
        return self.active_of(cid) is not None

    def view(self, m: dict, for_cid: str, online: set) -> dict:
        rules = GAMES[m["game"]]
        players = []
        for i, cid in enumerate(m["players"]):
            ch = self.characters.get(cid, {})
            players.append({"pub": ch.get("pub", ""), "name": ch.get("name", "?"), "appearance": ch.get("appearance", {}),
                            "seat": i, "online": cid in online and cid not in self.away, "left": cid in m["left"],
                            "rematch": cid in m["rematch"]})
        return {"mid": m["mid"], "game": m["game"], "name": rules.name, "status": m["status"], "seq": m["seq"],
                "you": m["players"].index(for_cid) if for_cid in m["players"] else -1, "players": players,
                "state": rules.public(m["state"]), "result": m["result"], "series": list(m["series"]),
                "away_deadline": {self.characters[c]["pub"]: max(0, int(self.away[c] + RECONNECT_GRACE - now()))
                                  for c in m["players"] if c in self.away}}

    # ---------------------------------------------------------------- ciclo de vida
    def create(self, game_id: str, players: list, series: list | None = None) -> dict:
        rules = GAMES[game_id]
        mid = secrets.token_hex(6)
        m = {"mid": mid, "game": game_id, "players": list(players), "state": rules.new_state(len(players)), "status": "active",
             "seq": 0, "result": None, "rematch": set(), "left": set(), "created": now(), "updated": now(),
             "series": list(series) if series else [0] * len(players)}
        self.matches[mid] = m
        return m

    def _finish(self, m: dict, result: dict) -> None:
        m["status"] = "finished"
        m["result"] = result
        m["updated"] = now()
        if "winner" in result:
            m["series"][result["winner"]] += 1

    def _get(self, cid: str, mid) -> tuple:
        m = self.matches.get(str(mid))
        if m is None:
            return None, "Partida inexistente."
        if cid not in m["players"]:
            return None, "Não fazes parte desta partida."         # acesso não autorizado
        return m, None

    def move(self, cid: str, mid, payload: dict, seq) -> tuple:
        """Jogada. seq = número de jogadas que o cliente viu (rejeita jogadas repetidas ou baseadas num estado antigo)."""
        m, err = self._get(cid, mid)
        if err:
            return False, err, None
        if m["status"] != "active":
            return False, "A partida já terminou.", m
        if isinstance(seq, bool) or not isinstance(seq, int) or seq != m["seq"]:
            return False, "Jogada desatualizada.", m
        seat = m["players"].index(cid)
        rules = GAMES[m["game"]]
        err = rules.apply(m["state"], seat, payload)
        if err:
            return False, err, m
        m["seq"] += 1
        m["updated"] = now()
        res = rules.outcome(m["state"])
        if res:
            self._finish(m, res)
        return True, "", m

    def leave(self, cid: str, mid) -> tuple:
        """Sair: numa partida a decorrer é desistência (o outro ganha); numa acabada só deixa de aceitar revanche."""
        m, err = self._get(cid, mid)
        if err:
            return False, err, None
        if m["status"] == "active":
            seat = m["players"].index(cid)
            self._finish(m, {"winner": 1 - seat, "reason": "forfeit", "by": self.characters[cid]["pub"]})
        m["left"].add(cid)
        m["rematch"].discard(cid)
        m["updated"] = now()
        return True, "", m

    def rematch(self, cid: str, mid) -> tuple:
        """Voto de revanche. Quando todos votam, nasce uma nova partida com os lugares rodados (quem era O passa a X)."""
        m, err = self._get(cid, mid)
        if err:
            return False, err, None, None
        if m["status"] != "finished":
            return False, "A partida ainda não terminou.", m, None
        if m["left"]:
            return False, "O outro jogador já saiu.", m, None
        for c in m["players"]:
            if self.busy(c):
                return False, ("Já estás noutra partida." if c == cid else "O outro jogador já está noutra partida."), m, None
        m["rematch"].add(cid)
        m["updated"] = now()
        if m["rematch"] != set(m["players"]):
            return True, "", m, None
        players = m["players"][1:] + m["players"][:1]
        series = m["series"][1:] + m["series"][:1]
        new = self.create(m["game"], players, series)
        m["left"] = set(m["players"])                 # a antiga fica arquivada
        return True, "", m, new

    def disconnected(self, cid: str) -> dict | None:
        m = self.active_of(cid)
        if m:
            self.away[cid] = now()
        return m

    def reconnected(self, cid: str) -> dict | None:
        self.away.pop(cid, None)
        return self.latest_of(cid)

    def tick(self) -> list:
        """Falta de comparência, partidas paradas e limpeza. Devolve as partidas alteradas (para avisar os jogadores)."""
        changed, t = [], now()
        for cid, since in list(self.away.items()):
            if t - since >= RECONNECT_GRACE:
                del self.away[cid]
                m = self.active_of(cid)
                if m:
                    seat = m["players"].index(cid)
                    self._finish(m, {"winner": 1 - seat, "reason": "disconnect", "by": self.characters[cid]["pub"]})
                    changed.append(m)
        for mid, m in list(self.matches.items()):
            if m["status"] == "active" and t - m["updated"] >= IDLE_TTL:
                self._finish(m, {"draw": True, "reason": "expired"})
                changed.append(m)
            elif m["status"] == "finished" and t - m["updated"] >= FINISHED_TTL:
                del self.matches[mid]
        return changed

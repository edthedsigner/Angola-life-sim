"""World geometry shared with the client (same rules as shared/scripts/WorldData.gd).

Coordinates
-----------
* Pixel positions (what clients send) live in *zones*: "w" (outdoor world) or "b:<building>:<floor>" (interior floor).
* Each zone has a pixel origin. Cell (x, y) in a zone: top vertex = origin + ((x-y)*32, (x+y)*16), centre = +(0, 16).
* Continuous cell space: cs = ((qx/32 + qy/16)/2, (qy/16 - qx/32)/2) with q = pixel - origin; cell = floor(cs).
* Interior edges use the original v0.6 keys: "h:x:y" = edge (x,y)-(x+1,y); "v:x:y" = edge (x,y)-(x,y+1).
* Stairs go "north" (y decreasing): base cell (x,y) on floor lo, ramp cells (x,y-1..y-len), landing (x,y-len-1) on lo+1.
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path

DEFAULT_PATH = Path(__file__).resolve().parent.parent / "shared" / "data" / "world.json"


def load(path: str | os.PathLike | None = None) -> "World":
    p = Path(path or os.environ.get("ANGOLA_WORLD", DEFAULT_PATH))
    return World(json.loads(p.read_text(encoding="utf-8")))


def edge_key(a: tuple, b: tuple) -> str:
    if a[0] != b[0]:
        return f"v:{max(a[0], b[0])}:{a[1]}"
    return f"h:{a[0]}:{max(a[1], b[1])}"


class Floor:
    def __init__(self, b: dict, idx: int, fd: dict):
        self.idx, self.w, self.l = idx, int(fd["w"]), int(fd["l"])
        self.name = fd.get("name", f"Piso {idx}")
        self.walls: dict[str, str] = {}
        for x in range(self.w):
            self.walls[f"h:{x}:0"] = "wall"
            self.walls[f"h:{x}:{self.l}"] = "wall"
        for y in range(self.l):
            self.walls[f"v:0:{y}"] = "wall"
            self.walls[f"v:{self.w}:{y}"] = "wall"
        for o, k, a1, a2 in fd.get("walls", []):
            for t in range(int(a1), int(a2)):
                self.walls[f"h:{t}:{k}" if o == "h" else f"v:{k}:{t}"] = "wall"
        for o, x, y, kind in fd.get("openings", []):
            self.walls[f"{o}:{x}:{y}"] = kind
        self.exits: dict[str, str] = {}
        if idx == 0:
            for e in b.get("entrances", []):
                self.walls[e["edge"]] = "exit"
                self.exits[e["id"]] = e["edge"]
        self.furniture = [dict(f, fid=f"f{n}") for n, f in enumerate(fd.get("furniture", []))]


class World:
    def __init__(self, data: dict):
        self.data = data
        g = data["grid"]
        self.cmin, self.cmax, self.rmin, self.rmax = g["cmin"], g["cmax"], g["rmin"], g["rmax"]
        self.spawn = dict(data["spawn"])
        self.items = data["items"]
        self.activities = data["activities"]
        self.jobs = data["jobs"]
        self.rentals = data["rentals"]
        self.furn_defs = data["furniture"]
        self.needs_cfg = data["needs"]
        self.clock_cfg = data["clock"]
        self.buildings: dict[str, dict] = {}
        self.floors: dict[str, list[Floor]] = {}
        self.blocked_world: set[tuple] = set()
        self.props = []
        for idx, b in enumerate(data["buildings"]):
            b = dict(b, idx=idx)
            self.buildings[b["id"]] = b
            self.floors[b["id"]] = [Floor(b, i, fd) for i, fd in enumerate(b["floors"])]
            for c in range(b["c0"], b["c0"] + b["w"]):
                for r in range(b["r0"], b["r0"] + b["d"]):
                    self.blocked_world.add((c, r))
        rules = data.get("prop_rules", {})
        for n, (kind, c, r) in enumerate(data.get("props", [])):
            rule = rules.get(kind, {})
            self.props.append({"pid": f"p{n}", "kind": kind, "c": c, "r": r, "actions": rule.get("actions", [])})
            if rule.get("blocks"):
                self.blocked_world.add((c, r))
        self.validate()

    # ------------------------------------------------------------------ zones / coordinates
    def world_zone(self) -> str:
        return "w"

    @staticmethod
    def floor_zone(bid: str, f: int) -> str:
        return f"b:{bid}:{f}"

    def parse_zone(self, zone: str):
        """-> (building dict, Floor) for interiors, (None, None) for the world, raises KeyError if invalid."""
        if zone == "w":
            return None, None
        _, bid, f = zone.split(":")
        b = self.buildings[bid]
        return b, self.floors[bid][int(f)]

    def zone_valid(self, zone: str) -> bool:
        try:
            self.parse_zone(zone)
            return True
        except (KeyError, ValueError, IndexError):
            return False

    def origin(self, zone: str) -> tuple[float, float]:
        if zone == "w":
            return (0.0, 0.0)
        b, fl = self.parse_zone(zone)
        bx, by = self.data["interior_base"]
        return (bx + b["idx"] * self.data["interior_step"], by + fl.idx * self.data["floor_step"])

    def to_cell_space(self, zone: str, x: float, y: float) -> tuple[float, float]:
        ox, oy = self.origin(zone)
        qx, qy = x - ox, y - oy
        return ((qx / 32 + qy / 16) / 2, (qy / 16 - qx / 32) / 2)

    def cell_center(self, zone: str, c: int, r: int) -> tuple[float, float]:
        ox, oy = self.origin(zone)
        return (ox + (c - r) * 32, oy + (c + r) * 16 + 16)

    def cell_of(self, zone: str, x: float, y: float) -> tuple[int, int]:
        u, v = self.to_cell_space(zone, x, y)
        return (math.floor(u), math.floor(v))

    # ------------------------------------------------------------------ walkability
    def in_bounds(self, zone: str, cell: tuple) -> bool:
        if zone == "w":
            return self.cmin <= cell[0] <= self.cmax and self.rmin <= cell[1] <= self.rmax
        _, fl = self.parse_zone(zone)
        return 0 <= cell[0] < fl.w and 0 <= cell[1] < fl.l

    def stair_cells(self, b: dict, st: dict) -> list[tuple]:
        return [(st["x"], st["y"] - i) for i in range(1, int(st["len"]) + 1)]

    def stair_landing(self, st: dict) -> tuple:
        return (st["x"], st["y"] - int(st["len"]) - 1)

    def furn_cells(self, f: dict) -> list[tuple]:
        d = self.furn_defs[f["id"]]
        w, h = (d["h"], d["w"]) if int(f.get("r", 0)) % 2 else (d["w"], d["h"])
        return [(f["x"] + i, f["y"] + j) for i in range(w) for j in range(h)]

    def blocked_cells(self, zone: str) -> set:
        if zone == "w":
            return self.blocked_world
        b, fl = self.parse_zone(zone)
        out = set()
        for f in fl.furniture:
            out.update(self.furn_cells(f))
        for st in b.get("stairs", []):
            if st["lo"] == fl.idx or st["lo"] + 1 == fl.idx:
                out.update(self.stair_cells(b, st))
        return out

    def edge_blocked(self, zone: str, a: tuple, b: tuple, doors: dict | None = None) -> bool:
        if zone == "w":
            return False
        _, fl = self.parse_zone(zone)
        key = edge_key(a, b)
        kind = fl.walls.get(key, "")
        if kind in ("wall", "window", "exit"):
            return True
        if kind == "door":
            return not (doors or {}).get(key, True)
        return False

    def walkable_point(self, zone: str, x: float, y: float, margin: float = 0.12) -> bool:
        """Feet point must lie in a walkable cell; tolerates `margin` cells of overlap into a blocked neighbour."""
        u, v = self.to_cell_space(zone, x, y)
        cell = (math.floor(u), math.floor(v))
        blocked = self.blocked_cells(zone)
        if self.in_bounds(zone, cell) and cell not in blocked:
            return True
        for du in (-margin, margin):
            for dv in (-margin, margin):
                c2 = (math.floor(u + du), math.floor(v + dv))
                if self.in_bounds(zone, c2) and c2 not in blocked:
                    return True
        return False

    def crosses_wall(self, zone: str, x0: float, y0: float, x1: float, y1: float, doors: dict | None = None) -> bool:
        """True if the straight move between two pixel points crosses a blocking interior edge."""
        if zone == "w":
            return False
        u0, v0 = self.to_cell_space(zone, x0, y0)
        u1, v1 = self.to_cell_space(zone, x1, y1)
        n = max(1, int(math.hypot(u1 - u0, v1 - v0) / 0.1) + 1)
        prev = (math.floor(u0), math.floor(v0))
        for k in range(1, n + 1):
            t = k / n
            c = (math.floor(u0 + (u1 - u0) * t), math.floor(v0 + (v1 - v0) * t))
            if c != prev:
                if c[0] != prev[0] and c[1] != prev[1]:
                    mid1, mid2 = (c[0], prev[1]), (prev[0], c[1])
                    ok1 = not self.edge_blocked(zone, prev, mid1, doors) and not self.edge_blocked(zone, mid1, c, doors)
                    ok2 = not self.edge_blocked(zone, prev, mid2, doors) and not self.edge_blocked(zone, mid2, c, doors)
                    if not (ok1 or ok2):
                        return True
                elif self.edge_blocked(zone, prev, c, doors):
                    return True
                prev = c
        return False

    def zone_bounds_px(self, zone: str) -> tuple[float, float, float, float]:
        if zone == "w":
            corners = [(self.cmin, self.rmin), (self.cmax + 1, self.rmin), (self.cmin, self.rmax + 1), (self.cmax + 1, self.rmax + 1)]
        else:
            _, fl = self.parse_zone(zone)
            corners = [(0, 0), (fl.w, 0), (0, fl.l), (fl.w, fl.l)]
        ox, oy = self.origin(zone)
        xs = [ox + (c - r) * 32 for c, r in corners]
        ys = [oy + (c + r) * 16 for c, r in corners]
        return (min(xs), max(xs), min(ys), max(ys))

    # ------------------------------------------------------------------ interactables
    def entrance_tile(self, b: dict, e: dict) -> tuple:
        if e["face"] == "front":
            return (b["c0"] + e["i"], b["r0"] + b["d"])
        return (b["c0"] + b["w"], b["r0"] + e["i"])

    def exit_cell(self, fl: Floor, edge: str) -> tuple:
        o, x, y = edge.split(":")
        x, y = int(x), int(y)
        if o == "h":
            return (x, y - 1) if y == fl.l else (x, y)
        return (x - 1, y) if x == fl.w else (x, y)

    @staticmethod
    def dist_to_rect(u: float, v: float, x0: float, y0: float, x1: float, y1: float) -> float:
        du = max(x0 - u, 0.0, u - x1)
        dv = max(y0 - v, 0.0, v - y1)
        return math.hypot(du, dv)

    def near_cell(self, zone: str, x: float, y: float, cell: tuple, reach: float = 0.9) -> bool:
        u, v = self.to_cell_space(zone, x, y)
        return self.dist_to_rect(u, v, cell[0], cell[1], cell[0] + 1, cell[1] + 1) <= reach

    def near_cells(self, zone: str, x: float, y: float, cells: list, reach: float = 0.9) -> bool:
        return any(self.near_cell(zone, x, y, c, reach) for c in cells)

    def find_furniture(self, zone: str, fid: str) -> dict | None:
        if zone == "w":
            for p in self.props:
                if p["pid"] == fid:
                    return {"id": p["kind"], "x": p["c"], "y": p["r"], "r": 0, "actions": p["actions"], "fid": fid, "prop": True}
            return None
        _, fl = self.parse_zone(zone)
        for f in fl.furniture:
            if f["fid"] == fid:
                return f
        return None

    def object_cells(self, f: dict) -> list[tuple]:
        if f.get("prop"):
            return [(f["x"], f["y"])]
        return self.furn_cells(f)

    def door_mid(self, zone: str, key: str) -> tuple[float, float]:
        o, x, y = key.split(":")
        x, y = int(x), int(y)
        return (x + 0.5, y) if o == "h" else (x, y + 0.5)

    # ------------------------------------------------------------------ validation of the data file
    def validate(self) -> None:
        errs = []
        for bid, b in self.buildings.items():
            allowed = set(self.data["building_types"][b["type"]]["furniture"])
            fls = self.floors[bid]
            for fl in fls:
                occ = set()
                for f in fl.furniture:
                    if f["id"] not in allowed:
                        errs.append(f"{bid} piso {fl.idx}: mobília '{f['id']}' não permitida em {b['type']}")
                    for a in f.get("actions", []):
                        if a not in self.activities:
                            errs.append(f"{bid}: atividade desconhecida {a}")
                    for c in self.furn_cells(f):
                        if not (0 <= c[0] < fl.w and 0 <= c[1] < fl.l):
                            errs.append(f"{bid} piso {fl.idx}: {f['id']} fora do piso em {c}")
                        if c in occ:
                            errs.append(f"{bid} piso {fl.idx}: sobreposição em {c}")
                        occ.add(c)
            for st in b.get("stairs", []):
                lo = st["lo"]
                if lo + 1 >= len(fls):
                    errs.append(f"{bid}: escada sem piso superior")
                    continue
                for c in [(st["x"], st["y"])] + self.stair_cells(b, st):
                    if not (0 <= c[0] < fls[lo].w and 0 <= c[1] < fls[lo].l):
                        errs.append(f"{bid}: escada fora do piso {lo}")
                land = self.stair_landing(st)
                if not (0 <= land[0] < fls[lo + 1].w and 0 <= land[1] < fls[lo + 1].l):
                    errs.append(f"{bid}: patamar fora do piso {lo + 1}")
            for e in b.get("entrances", []):
                t = self.entrance_tile(b, e)
                if t in self.blocked_world:
                    errs.append(f"{bid}: entrada {e['id']} bloqueada em {t}")
            # every floor must be fully connected (from the exit / landing) with doors open
            for fl in fls:
                zone = self.floor_zone(bid, fl.idx)
                blocked = self.blocked_cells(zone)
                free = {(x, y) for x in range(fl.w) for y in range(fl.l)} - blocked
                if not free:
                    continue
                start = next(iter(free))
                seen, q = {start}, [start]
                while q:
                    c = q.pop()
                    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        n = (c[0] + d[0], c[1] + d[1])
                        if n in free and n not in seen and not self.edge_blocked(zone, c, n, {}):
                            seen.add(n)
                            q.append(n)
                if seen != free:
                    errs.append(f"{bid} piso {fl.idx}: células inacessíveis {sorted(free - seen)[:6]}")
        if errs:
            raise ValueError("world.json inválido:\n  " + "\n  ".join(errs))

"""Geography data (shared/data/geo/): loading and validation. Milestone 1: data only, nothing in the game uses it yet.

Four separate layers (docs/GEOGRAPHY.md):
  admin.json      real administrative geography (adm.*)        -> country, provinces, municipalities, comunas
  playable.json   the game's selected playable locations (loc.*) -> each points to one admin unit
  maps.json       map representations (map.*)                   -> each points to one playable location
  attributes.json gameplay attributes per playable location     -> kept apart from geography
plus sources.json, the registry every record cites.

validate() returns a list of human-readable errors (empty = valid). It enforces the rules that keep the data honest:
every record cites at least one registered source stating what it confirms; a 'verified' administrative link needs a
source that supports it; an inferred link needs a stated basis; internal ids and official codes never mix.
"""
from __future__ import annotations

import json
import re
from datetime import date
from pathlib import Path

GEO_DIR = Path(__file__).resolve().parent.parent / "shared" / "data" / "geo"
FILES = ("sources", "admin", "playable", "maps", "attributes")

SLUG = r"[a-z][a-z0-9_]*"
ID_PATTERNS = {
    "source": re.compile(rf"^src\.{SLUG}(\.{SLUG})*$"),
    "country": re.compile(rf"^adm\.{SLUG}$"),
    "province": re.compile(rf"^adm\.{SLUG}\.{SLUG}$"),
    "municipality": re.compile(rf"^adm\.{SLUG}\.{SLUG}\.{SLUG}$"),
    "comuna": re.compile(rf"^adm\.{SLUG}\.{SLUG}\.{SLUG}\.{SLUG}$"),
    "location": re.compile(rf"^loc\.{SLUG}\.{SLUG}$"),
    "map": re.compile(rf"^map\.{SLUG}\.{SLUG}\.\d\d$"),
}
STATUSES = {"verified", "unverified"}
EXISTENCE = {"verified", "verified_weak", "unverified"}
LINK_STATUSES = {"verified", "inferred", "unverified"}
SUPPORTS = {"existence", "parent", "type", "name", "count"}


def load(geo_dir: Path | str = GEO_DIR) -> dict:
    d = Path(geo_dir)
    return {name: json.loads((d / f"{name}.json").read_text(encoding="utf-8")) for name in FILES}


def province_abbr(pid: str) -> str:
    return pid.split(".")[2]


def validate(data: dict) -> list[str]:
    errors: list[str] = []
    err = errors.append
    seen: set[str] = set()

    def check_id(kind: str, rid) -> bool:
        if not isinstance(rid, str) or not ID_PATTERNS[kind].match(rid):
            err(f"{kind} id inválido: {rid!r}")
            return False
        if rid in seen:
            err(f"id duplicado: {rid}")
            return False
        seen.add(rid)
        return True

    # ---------------------------------------------------------------- fontes
    reg = data["sources"]
    stypes, methods = set(reg.get("types", [])), set(reg.get("access_methods", []))
    sources = reg.get("sources", {})
    for sid, s in sources.items():
        check_id("source", sid)
        if not str(s.get("url", "")).startswith("https://"):
            err(f"{sid}: url em falta ou não https")
        if s.get("type") not in stypes:
            err(f"{sid}: tipo de fonte desconhecido {s.get('type')!r}")
        if s.get("access_method") not in methods:
            err(f"{sid}: access_method desconhecido {s.get('access_method')!r}")
        try:
            date.fromisoformat(str(s.get("verified_on", "")))
        except ValueError:
            err(f"{sid}: verified_on não é uma data ISO")
        if not s.get("title") or not s.get("publisher"):
            err(f"{sid}: title/publisher em falta")

    def check_citations(rid: str, rec: dict, required: bool = True) -> set:
        """Valida as citações de um registo e devolve o conjunto de aspetos suportados."""
        cites = rec.get("sources")
        if not isinstance(cites, list) or (required and not cites):
            err(f"{rid}: sem fontes")
            return set()
        supported: set = set()
        for c in cites:
            if c.get("source") not in sources:
                err(f"{rid}: fonte não registada {c.get('source')!r}")
            if not str(c.get("confirms", "")).strip():
                err(f"{rid}: citação de {c.get('source')} sem 'confirms'")
            sup = c.get("supports")
            if not isinstance(sup, list) or not set(sup) <= SUPPORTS:
                err(f"{rid}: 'supports' inválido em {c.get('source')}")
                continue
            supported |= set(sup)
        return supported

    def check_code(rid: str, rec: dict) -> None:
        if "official_code" not in rec:
            err(f"{rid}: falta o campo official_code (null até verificado)")
        elif rec["official_code"] is not None and (not isinstance(rec["official_code"], str) or rec["official_code"] in seen
                                                   or rec["official_code"].startswith(("adm.", "loc.", "map.", "src."))):
            err(f"{rid}: official_code não pode ser um id interno")

    def check_admin_status(rid: str, rec: dict, supported: set) -> None:
        st = rec.get("status")
        if st not in STATUSES:
            err(f"{rid}: status inválido {st!r}")
        elif st == "verified" and "existence" not in supported:
            err(f"{rid}: 'verified' sem fonte que confirme a existência")
        if rec.get("name_status") == "disputed" and not rec.get("alternative_names"):
            err(f"{rid}: nome disputado sem alternative_names")

    # ---------------------------------------------------------------- geografia administrativa
    admin = data["admin"]
    country = admin["country"]
    if check_id("country", country.get("id")):
        check_code(country["id"], country)
        check_admin_status(country["id"], country, check_citations(country["id"], country))
    provinces = {}
    for p in admin.get("provinces", []):
        if not check_id("province", p.get("id")):
            continue
        provinces[p["id"]] = p
        if p.get("country") != country["id"] or not p["id"].startswith(country["id"] + "."):
            err(f"{p['id']}: país inválido")
        check_code(p["id"], p)
        check_admin_status(p["id"], p, check_citations(p["id"], p))
        if not isinstance(p.get("municipalities_complete"), bool):
            err(f"{p['id']}: municipalities_complete tem de ser true/false")
        for rc in p.get("reported_municipality_counts", []):
            if rc.get("source") not in sources or not isinstance(rc.get("value"), int):
                err(f"{p['id']}: contagem de municípios sem fonte registada")
    municipalities = {}
    for m in admin.get("municipalities", []):
        if not check_id("municipality", m.get("id")):
            continue
        municipalities[m["id"]] = m
        if m.get("province") not in provinces or not m["id"].startswith(str(m.get("province")) + "."):
            err(f"{m['id']}: província inválida {m.get('province')!r}")
        check_code(m["id"], m)
        sup = check_citations(m["id"], m)
        check_admin_status(m["id"], m, sup)
        if m.get("status") == "verified" and "parent" not in sup:
            err(f"{m['id']}: 'verified' sem fonte que confirme a província")
        if m.get("status") == "unverified" and not m.get("status_note"):
            err(f"{m['id']}: 'unverified' sem status_note a explicar")
    comunas = {}
    for c in admin.get("comunas", []):
        if not check_id("comuna", c.get("id")):
            continue
        comunas[c["id"]] = c
        if c.get("municipality") not in municipalities or not c["id"].startswith(str(c.get("municipality")) + "."):
            err(f"{c['id']}: município inválido {c.get('municipality')!r}")
        check_code(c["id"], c)
        sup = check_citations(c["id"], c)
        check_admin_status(c["id"], c, sup)
        if c.get("status") == "unverified" and not c.get("status_note"):
            err(f"{c['id']}: 'unverified' sem status_note a explicar")
    for p in provinces.values():
        cap = p.get("capital")
        if cap is not None and (cap not in municipalities or municipalities[cap]["province"] != p["id"]):
            err(f"{p['id']}: capital inválida {cap!r}")
    for prop in admin.get("pending_proposals", []):
        if prop.get("status") != "not_in_force":
            err(f"{prop.get('id')}: propostas pendentes têm de estar marcadas not_in_force")
        check_citations(str(prop.get("id")), prop)

    def province_of(ref: str) -> str | None:
        if ref in municipalities:
            return municipalities[ref]["province"]
        if ref in comunas:
            return municipalities.get(comunas[ref]["municipality"], {}).get("province")
        return None

    # ---------------------------------------------------------------- locais jogáveis
    pl = data["playable"]
    lim = pl.get("limits", {})
    types = set(pl.get("location_types", []))
    sel = pl.get("provinces", [])
    if len(sel) != len(set(sel)):
        err("províncias jogáveis repetidas")
    if len(sel) > lim.get("max_provinces", 0):
        err(f"mais de {lim.get('max_provinces')} províncias jogáveis")
    for pid in sel:
        if pid not in provinces:
            err(f"província jogável não existe na geografia administrativa: {pid}")
    locations = {}
    per_province: dict[str, int] = {}
    for loc in pl.get("locations", []):
        if not check_id("location", loc.get("id")):
            continue
        lid = loc["id"]
        locations[lid] = loc
        if not str(loc.get("name", "")).strip():
            err(f"{lid}: sem nome")
        if loc.get("type") not in types:
            err(f"{lid}: tipo desconhecido {loc.get('type')!r}")
        if "official_code" in loc:
            err(f"{lid}: locais jogáveis não têm official_code (pertence à geografia administrativa)")
        if not isinstance(loc.get("fictional"), bool):
            err(f"{lid}: 'fictional' tem de ser true/false")
        ref = loc.get("admin_ref")
        prov = province_of(ref) if isinstance(ref, str) else None
        if prov is None:
            err(f"{lid}: admin_ref não é um município ou comuna conhecido: {ref!r}")
        else:
            if prov not in sel:
                err(f"{lid}: a província {prov} não é jogável")
            if province_abbr(prov) != lid.split(".")[1]:
                err(f"{lid}: prefixo do id não corresponde à província {prov}")
            per_province[prov] = per_province.get(prov, 0) + 1
            if loc.get("type") == "municipio" and ref not in municipalities:
                err(f"{lid}: tipo município tem de apontar para um município")
            if loc.get("type") == "comuna" and ref not in comunas:
                err(f"{lid}: tipo comuna tem de apontar para uma comuna")
        sup = check_citations(lid, loc)
        ex = loc.get("existence")
        if ex not in EXISTENCE:
            err(f"{lid}: existence inválido {ex!r}")
        elif ex in ("verified", "verified_weak") and "existence" not in sup:
            err(f"{lid}: existência '{ex}' sem fonte que a confirme")
        link = loc.get("admin_link") or {}
        ls = link.get("status")
        if ls not in LINK_STATUSES:
            err(f"{lid}: admin_link.status inválido {ls!r}")
        if not str(link.get("basis", "")).strip():
            err(f"{lid}: admin_link sem 'basis'")
        if ls == "verified":
            if "parent" not in sup:
                err(f"{lid}: ligação administrativa 'verified' sem fonte que a confirme (rebaixar para inferred/unverified)")
            target = municipalities.get(ref) or comunas.get(ref) or {}
            if target.get("status") != "verified":
                err(f"{lid}: ligação 'verified' a uma unidade administrativa não verificada ({ref})")
        if loc.get("fictional"):
            if "fictício" not in str(loc.get("notes", "")).lower() and "fictional" not in str(loc.get("notes", "")).lower():
                err(f"{lid}: local fictício tem de o dizer nas notas")
    if len(locations) > lim.get("max_locations", 0):
        err(f"mais de {lim.get('max_locations')} locais jogáveis")
    for prov, n in per_province.items():
        if n > lim.get("max_locations_per_province", 0):
            err(f"{prov}: {n} locais (máximo {lim.get('max_locations_per_province')})")

    # ---------------------------------------------------------------- mapas
    mp = data["maps"]
    reps = set(mp.get("representations", []))
    for m in mp.get("maps", []):
        if not check_id("map", m.get("id")):
            continue
        if m.get("location") not in locations:
            err(f"{m['id']}: local jogável inexistente {m.get('location')!r}")
        elif m["id"].split(".")[1:3] != m["location"].split(".")[1:3]:
            err(f"{m['id']}: id do mapa não corresponde ao local {m['location']}")
        if m.get("representation") not in reps:
            err(f"{m['id']}: representation inválida {m.get('representation')!r}")
        if m.get("representation") == "fictional" and not str(m.get("description", "")).strip():
            err(f"{m['id']}: mapa fictício sem descrição a explicá-lo")
        if "official_code" in m:
            err(f"{m['id']}: mapas não têm official_code")

    # ---------------------------------------------------------------- atributos de jogo
    at = data["attributes"]
    names, bases = set(at.get("attributes", {})), set(at.get("bases", []))
    values = at.get("values", {})
    for lid in values:
        if lid not in locations:
            err(f"atributos para um local inexistente: {lid}")
    for lid in locations:
        row = values.get(lid)
        if not isinstance(row, dict):
            err(f"{lid}: sem atributos")
            continue
        if set(row) != names:
            err(f"{lid}: atributos em falta ou desconhecidos: {sorted(set(row) ^ names)}")
        for a, v in row.items():
            if not isinstance(v, dict) or isinstance(v.get("value"), bool) or not isinstance(v.get("value"), (int, float)):
                err(f"{lid}.{a}: valor numérico em falta")
                continue
            if v.get("basis") not in bases:
                err(f"{lid}.{a}: basis inválida {v.get('basis')!r}")
            srcs = v.get("sources", [])
            if v.get("basis") == "sourced" and not srcs:
                err(f"{lid}.{a}: 'sourced' sem fontes")
            for s in srcs:
                if s not in sources:
                    err(f"{lid}.{a}: fonte não registada {s!r}")
    return errors


def summary(data: dict) -> dict:
    locs = data["playable"]["locations"]
    count = lambda key, val: sum(1 for l in locs if (l["admin_link"]["status"] if key == "link" else l["existence"]) == val)
    return {"provinces": len(data["playable"]["provinces"]), "locations": len(locs),
            "existence_verified": count("existence", "verified"), "existence_weak": count("existence", "verified_weak"),
            "link_verified": count("link", "verified"), "link_inferred": count("link", "inferred"),
            "link_unverified": count("link", "unverified"), "maps": len(data["maps"]["maps"])}


if __name__ == "__main__":
    d = load()
    problems = validate(d)
    print(json.dumps(summary(d), ensure_ascii=False))
    for p in problems:
        print("ERRO", p)
    raise SystemExit(1 if problems else 0)

#!/usr/bin/env python3
"""Tests of the geography data (milestone 1): the real files are valid, and the validator rejects every kind of mistake
it exists to catch. Run alone (python tests/test_geo.py) or from tests/run_integration.py."""
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server_python"))
import geo  # noqa: E402


def run(check) -> None:
    data = geo.load()
    errors = geo.validate(data)
    check("geo: ficheiros reais válidos" + ("" if not errors else f" ({errors[:3]})"), not errors)
    s = geo.summary(data)
    check("geo: 8 províncias jogáveis e 40 locais jogáveis", s["provinces"] == 8 and s["locations"] == 40)
    pl = data["playable"]
    per = {}
    for loc in pl["locations"]:
        per[loc["id"].split(".")[1]] = per.get(loc["id"].split(".")[1], 0) + 1
    check("geo: 5 locais por província", sorted(per.values()) == [5] * 8)
    check("geo: limites 10 províncias / 50 locais / 5 por província", pl["limits"] == {"max_provinces": 10, "max_locations": 50, "max_locations_per_province": 5})
    check("geo: a geografia real não se limita às províncias jogáveis (Cuando, Moxico Leste registadas, não jogáveis)",
          {"adm.ao.cuando", "adm.ao.mxl"} <= {p["id"] for p in data["admin"]["provinces"]} and "adm.ao.cuando" not in pl["provinces"])
    check("geo: país declara 21 províncias e lista incompleta assinalada",
          data["admin"]["country"]["division"]["provinces"] == 21 and data["admin"]["country"]["provinces_complete"] is False)
    maianga = next(m for m in data["maps"]["maps"] if m["location"] == "loc.lua.maianga")
    check("geo: o mapa atual de Maianga está marcado como fictício", maianga["representation"] == "fictional" and "invented" in maianga["description"])
    check("geo: nenhum local jogável é fictício (todos reais)", not any(l["fictional"] for l in pl["locations"]))
    check("geo: ligações inferidas/não verificadas mantêm-se assinaladas (12 inferidas, 8 por verificar)",
          s["link_inferred"] == 12 and s["link_unverified"] == 8 and s["link_verified"] == 20)
    check("geo: Forte Santa Rita e Lândana rebaixadas para 'unverified' com motivo",
          all(next(l for l in pl["locations"] if l["id"] == i)["admin_link"]["status"] == "unverified" for i in ("loc.nam.forte_santa_rita", "loc.cab.landana")))
    allrec = [data["admin"]["country"]] + data["admin"]["provinces"] + data["admin"]["municipalities"] + data["admin"]["comunas"]
    check("geo: official_code presente e vazio (null) em todos os registos administrativos", all("official_code" in r and r["official_code"] is None for r in allrec))
    check("geo: todos os registos citam fontes com URL, tipo, data e o que confirmam",
          all(r["sources"] and all(c["confirms"] for c in r["sources"]) for r in allrec + pl["locations"])
          and all(v["url"] and v["type"] and v["verified_on"] for v in data["sources"]["sources"].values()))
    check("geo: atributos de jogo neutros (1.0, placeholder) e separados", all(
        v["value"] == 1.0 and v["basis"] == "placeholder" for row in data["attributes"]["values"].values() for v in row.values()))

    # ---- o validador apanha os erros que deve apanhar (cada mutação parte de uma cópia válida)
    def broken(desc, mutate, expect):
        d = copy.deepcopy(data)
        mutate(d)
        errs = geo.validate(d)
        check(f"geo: rejeita {desc}", any(expect in e for e in errs))

    loc = lambda d, i: next(l for l in d["playable"]["locations"] if l["id"] == i)
    broken("ligação inferida promovida a 'verified' sem fonte", lambda d: loc(d, "loc.bgu.compao")["admin_link"].update(status="verified"), "sem fonte que a confirme")
    broken("ligação 'verified' a um município não verificado",
           lambda d: (loc(d, "loc.hua.kalundo")["admin_link"].update(status="verified"),
                      loc(d, "loc.hua.kalundo")["sources"][0]["supports"].append("parent")), "não verificada")
    broken("ligação inferida sem justificação", lambda d: loc(d, "loc.lua.ilha")["admin_link"].update(basis=""), "sem 'basis'")
    broken("admin_ref inexistente", lambda d: loc(d, "loc.lua.cazenga").update(admin_ref="adm.ao.lua.inventado"), "admin_ref")
    broken("local numa província não jogável", lambda d: d["playable"]["provinces"].remove("adm.ao.mal"), "não é jogável")
    broken("prefixo de id que não corresponde à província", lambda d: loc(d, "loc.mal.catepa").update(id="loc.cab.catepa"), "prefixo")
    broken("id duplicado", lambda d: d["playable"]["locations"].append(copy.deepcopy(loc(d, "loc.lua.maianga"))), "duplicado")
    broken("id com maiúsculas/acentos", lambda d: loc(d, "loc.lua.maianga").update(id="loc.lua.Maiánga"), "id inválido")
    broken("official_code num local jogável", lambda d: loc(d, "loc.lua.maianga").update(official_code="LUA-01"), "não têm official_code")
    broken("official_code igual a um id interno", lambda d: d["admin"]["municipalities"][0].update(official_code="adm.ao.lua.maianga"), "id interno")
    broken("registo sem fontes", lambda d: d["admin"]["municipalities"][0].update(sources=[]), "sem fontes")
    broken("fonte não registada", lambda d: loc(d, "loc.icb.zango")["sources"].append({"source": "src.nada", "supports": [], "confirms": "x"}), "não registada")
    broken("citação sem 'confirms'", lambda d: loc(d, "loc.icb.zango")["sources"][0].update(confirms=""), "sem 'confirms'")
    broken("fonte sem data de verificação", lambda d: d["sources"]["sources"]["src.wikipedia.malanje"].update(verified_on="ontem"), "data ISO")
    broken("fonte sem URL https", lambda d: d["sources"]["sources"]["src.wikipedia.malanje"].update(url="ftp://x"), "https")
    broken("tipo de local desconhecido", lambda d: loc(d, "loc.lua.kilamba").update(type="cidade_fantasma"), "tipo desconhecido")
    broken("mais de 5 locais numa província", lambda d: d["playable"]["locations"].append(dict(copy.deepcopy(loc(d, "loc.lua.maianga")), id="loc.lua.extra")), "máximo")
    broken("mais de 10 províncias jogáveis", lambda d: d["playable"]["limits"].update(max_provinces=7), "províncias jogáveis")
    broken("mapa fictício sem descrição", lambda d: d["maps"]["maps"][0].update(description=""), "fictício sem descrição")
    broken("mapa de um local inexistente", lambda d: d["maps"]["maps"][0].update(location="loc.lua.nada"), "inexistente")
    broken("atributo de jogo em falta", lambda d: d["attributes"]["values"]["loc.lua.maianga"].pop("tourism"), "em falta")
    broken("atributo 'sourced' sem fontes", lambda d: d["attributes"]["values"]["loc.lua.maianga"]["tourism"].update(basis="sourced"), "sem fontes")
    broken("município 'verified' sem fonte da província",
           lambda d: [c.update(supports=["existence"]) for c in next(m for m in d["admin"]["municipalities"] if m["id"] == "adm.ao.lua.cazenga")["sources"]], "província")
    broken("proposta pendente apresentada como em vigor", lambda d: d["admin"]["pending_proposals"][0].update(status="in_force"), "not_in_force")


if __name__ == "__main__":
    OK, FAIL = [], []

    def check(name, cond):
        (OK if cond else FAIL).append(name)
        print(("PASS " if cond else "FAIL ") + name)
    run(check)
    print(f"\n{len(OK)} passaram, {len(FAIL)} falharam")
    sys.exit(1 if FAIL else 0)

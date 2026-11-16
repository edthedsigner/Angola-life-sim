# Geography: data specification (milestone 1)

Milestone 1 adds geography **data only**. Nothing in the game reads it yet: the map, characters, prices, travel and the
database are unchanged. Files live in `shared/data/geo/`. Loading and validation are in `server_python/geo.py` and the
tests are in `tests/test_geo.py`, which also run inside `tests/run_integration.py`.

## Four layers, kept separate
| Layer | File | IDs | What it is |
|---|---|---|---|
| Administrative geography | `admin.json` | `adm.*` | Real units of Angola under Lei n.º 14/24: country, provinces, municipalities, comunas. Only units with a cited source. |
| Playable locations | `playable.json` | `loc.*` | The game's selection: 8 provinces, 5 locations each. Each points to exactly one administrative unit and keeps its real type. |
| Map representations | `maps.json` | `map.*` | Game artefacts that depict a playable location. A location without a map can't be entered yet. |
| Gameplay attributes | `attributes.json` | keyed by `loc.*` | Values for density, infrastructure, prices, employment, etc. Neutral placeholders in this milestone. |

`sources.json` is the source registry that every record cites.

**The playable selection is not Angola's geography.** Angola has 21 provinces, 326 municipalities and 378 comunas. The
8 playable provinces are a game choice. `admin.json` also records non-playable units (for example Cuando, Moxico Leste
and Ingombota) and marks every partial list (`provinces_complete`, `municipalities_complete`).

## IDs and official codes
* **Internal IDs** are stable and never change once released:
  * format: lowercase ASCII, no accents, `_` between words;
  * patterns: `adm.ao`, `adm.ao.<prov>`, `adm.ao.<prov>.<municipality>`, `adm.ao.<prov>.<municipality>.<comuna>`,
    `loc.<prov>.<slug>`, `map.<prov>.<slug>.<nn>`, `src.<publisher>.<slug>`.
* **Province abbreviations** (`lua`, `icb`, `bgu`, `hui`, `hua`, `nam`, `cab`, `mal`, `cuando`, `mxl`) are internal only.
* **Official codes** go in `official_code` on administrative records only. They are `null` until verified against
  Lei n.º 8/25, and can be corrected without touching any ID. Playable locations and maps have no official code.

## Status vocabulary (never upgraded without a source)
| Field | Values | Meaning |
|---|---|---|
| admin `status` | `verified`, `unverified` | Whether a cited source confirms that the unit exists and which unit it belongs to. `unverified` needs a `status_note`. |
| location `existence` | `verified`, `verified_weak`, `unverified` | Whether the place exists. `verified_weak` = only a directory or listing site confirms it. |
| location `admin_link.status` | `verified`, `inferred`, `unverified` | Whether the location belongs to the unit in `admin_ref`. **Inferred** = deduced from confirmed facts but not stated by any source; it is treated as unverified. Every link states its `basis`. |
| `name_status` | `disputed` + `alternative_names` | Spelling or name not settled, e.g. Tômbwa/Tômbua, Moxico Leste/Cassai-Zambeze. |

**What the validator enforces:**
* **Verified link:**
  * at least one citation that supports `parent`;
  * a target administrative unit that is itself `verified`.
* **Every inferred link** has a stated `basis`.
* **Proposals** (e.g. splitting Malanje) live only in `pending_proposals` with status `not_in_force`.

## Source metadata
* **Source registry (`sources.json`):** every source has a URL, title, publisher, `type` and `verified_on` date.
  * `type` is one of: law database, official portal, official statistics, state news agency, news, academic,
    technical study, encyclopedia (or mirror), travel guide, gazetteer, directory, chronicle.
  * `access_method` is `search_excerpt` or `page_read`.
* **Citations:** every administrative record and playable location cites one or more sources. Each citation says what it
  `supports` (existence, parent, type, name, count) and states exactly what the source `confirms`.

**All current sources were checked through quoted search excerpts on 2026-11-15/16**, not by opening the pages; their
`access_method` is `search_excerpt`. Before an `inferred` or `unverified` entry is upgraded, its source must be read
directly. The INE Censo 2024 provincial reports and the annexes of Lei n.º 14/24 and Lei n.º 8/25 are the next sources
to read.

## The current map is fictional
`map.lua.maianga.01` is the existing game world (`shared/data/world.json`). Its street and four buildings are
**invented** and do not reproduce any real street, building or landmark. The location it represents, the município of
Maianga in Luanda, is real. Building names (Mercearia Girassol, Casa Mussulo, Escritório Atlântico, Restaurante Maianga)
are game names, not real businesses.

## Current dataset (milestone 1)
* **Playable:** 8 provinces and 40 locations. Of these, 39 have verified existence and 1 is weak (Lombo-Lombo).
* **Municipality links:** 20 verified, 12 inferred, 8 unverified.
* **Location types:** município, centralidade, comuna, bairro, localidade, zona urbana.
* **No fictional locations.** A fictional location would need `fictional: true` and an explanation in `notes`.

## Not in this milestone
* Character location fields and migration.
* New maps or map loading.
* Per-map multiplayer isolation.
* Economic effects of the attributes.
* Travel and transport modes.
* Any production database change.

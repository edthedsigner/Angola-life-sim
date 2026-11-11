# Art / texture-pack guide
All textures live in `assets/art/` with FIXED file names. To swap art, overwrite the PNG with the same name (same size) — no code change.
Filtering is nearest (project setting `default_texture_filter=0`).

| Folder | Contents | Source |
|---|---|---|
| `tiles/` | grass, grass_b, road, road_line_c/_r, sidewalk (64x32 iso diamonds) | **your pack** (ground/ground_b/road/plaza) + generated road markings |
| `buildings/` | `<palette>_wall_{l,r}_{plain,window,door,shop}.png` (32x64), `<palette>_roof.png` (64x32). Palettes: pink, yellow, blue, cream | generated placeholders |
| `props/` | tree, lamp, bench, bush | generated placeholders |
| `characters/` | `body.png` (skin, white, tinted at runtime), `legs.png`, `shirt.png` (3 walk frames of 24x40), `hair_0..3.png`, `shadow.png` | generated placeholders |
| `pack_original/` | your full texture pack, untouched (monolithic building sprites, furniture, player/npc) | **your pack** |

Appearance data (skin tones, hair colors, names) is centralized in `shared/scripts/Art.gd`.
Regenerate placeholders: `python3 tools/generate_placeholder_art.py` (overwrites placeholders, re-copies tiles from pack_original).
Why your pack's buildings are not used yet: they are single monolithic sprites; the brief requires modular walls/doors/windows/roofs. See CONTINUATION.md.

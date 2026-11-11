# World scale

## One scale for everything
The grid already fixes the projection: a 64×32 tile is a 2:1 dimetric view (camera ~30° above the ground), where one
cell's height-equivalent is ≈ 39 px. Pairing that with a 1.75 m character gives:

| Unit | Value |
|---|---|
| 1 grid cell | **2.0 m** (interior cell and street tile are the same pixel size) |
| Height | **19.6 px per metre** |
| Character (1.75 m) | **34 px** |
| Door (2.1 × 0.8 m) | **41 px** |
| Floor / wall height | 48 px ≈ 2.45 m |

These live in `shared/data/world.json` → `scale`, in `tools/generate_furniture.py` (`CELL_M`, `V`) and in this file.

## Audit (measured opaque pixels, before → after)
| Object | Before | Real-world equivalent before | After | Notes |
|---|---|---|---|---|
| Character | 38 px | — | 34 px | slightly shorter so doors are taller than people; same art style |
| Exterior door | 36 px | 1.8 m (shorter than the character!) | 41 px | 2.1 m, 0.8 m wide |
| Interior doorway | full 2 m edge gap | — | 1.2 m gap between wall stubs | the closed leaf only fills the gap |
| Chair (pack) | 64×70 px, 1 cell | ≈ 3.6 m tall | 19×30 px (0.46 × 0.46 × 0.95 m) | 1 grid cell, uses ~¼ of it |
| Table | 2 cells, 76 px | 4 m long | 1.6 × 0.9 × 0.76 m, 1 cell | |
| Sofa | 2 cells, 86 px | 4 m long | 2.0 × 0.9 × 0.85 m, 1 cell | |
| Bed | 1×2 cells, 88 px | 4 m long | 1.6 × 2.0 m double, 1 cell | |
| Bookcase | 99 px | ≈ 5 m | 0.9 × 0.35 × 1.9 m (37 px) | |
| Plant | 75 px | ≈ 3.8 m | 0.42 m pot, 1.05 m tall | |
| Stove / shower / counter (M2 placeholders) | full cell, 63–112 px | 3–5 m | 0.6 m / 0.9 m cabin 2 m / 2.4 m counter (2 cells) | |
| Kitchen counter (new) | — | — | 1.6 × 0.6 × 0.9 m with sink | |
| Cars (menu) | 36×24 px | ≈ 1.9 m long | 4.2 × 1.8 × 1.45 m | |
| Lamp / tree / bush / bench | 62 / 70 / 22 / 22 px | 3.2 / 3.6 / 1.1 / 1.1 m | unchanged | already plausible |
| Buildings | 48 px per floor | 2.45 m | unchanged | |

The pack furniture (`assets/art/pack_original/`) was drawn about 3–4× too big for the grid, so shrinking it would have
destroyed it (a 64 px chair down to 17 px). It is kept untouched; the furniture is redrawn as true-scale pixel art by
`tools/generate_furniture.py`, with each piece built from boxes in metres and drawn with the game's own projection
(no bitmap scaling, nearest filtering). All four facings are real rotations, not mirrors.

## Separate dimensions (world.json → `furniture`)
| Dimension | Field | Used for |
|---|---|---|
| Grid occupancy | `grid` (cells) | placement, navigation (paths avoid the whole cell), interaction (adjacent cells) |
| Visual / collision footprint | `size` (metres, front = +y) + instance `face` / `align` | where the sprite is drawn, y-sort point (visual centre), physics collider, server walkability |
| Height | `h`, `seat` (metres) | documentation, sit/lie poses |
| Rendering origin | `assets/art/furniture/anchors.json` | pixel where the footprint's (0,0,0) corner falls in each sprite |

`face` = which way the front points (s/e/n/w); `align` pushes the visual against walls inside its cell (n/s/e/w,
combinable). The server (`world.py: visual_rect / solid_rects`) and the client (`WorldData.visual_rect`) compute the same rects.

## Poses
`activities.<id>.pose`: `sit` (sofa, bench) or `lie` (bed). The pose is visual only and the server position doesn't move.
The hips go over the seat at seat height, legs toward the front. Lying follows the bed's long axis with the head at the
headboard. The sitting frame (frame 3) is drawn in 3/4 view and mirrored to the furniture's front.

## Validation environment
`client/scenes/tests/ScaleTest.tscn`, started with the argument `--scale-test` (in a web build: `"args": ["--scale-test"]`).
It shows the same two-room test floor (3×6 and 4×6 cells, door, four chairs around a table, sofa, bed, kitchen counter,
stove, shop counter, bookcase, plant) **before** (M2 sprites and placement, from `assets/art/_scale_reference/`) and
**after**, with characters standing at the door, table and counters, sitting on the sofa and a chair, and lying in the bed,
plus an exterior door next to a character. Keys 1–4 switch views. Screenshots: `docs/screenshots/scale_*.png`.

## Known compromises
* Interiors stay "bigger on the inside" (one street tile = 2×2 interior cells, as in the original prototype), so a house is 12×16 m inside.
* Characters face the camera only (no side sprites); the sitting frame uses a 3/4 leg pose so it reads as sitting.

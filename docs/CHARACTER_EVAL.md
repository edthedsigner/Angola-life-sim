# Character pack evaluation: Isometric Pre-rendered Townsfolk (free sample)

This is a temporary experiment to decide whether to buy the full pack ($5, 20 characters). The adult sample character
(Austin) replaces the player's look in the world. Nothing else changes: movement, collision, camera, interaction, name
label and multiplayer sync are the same.

## Switching
* `shared/scripts/Art.gd`: `CHARACTER_SET = "townsfolk_sample"` (the experiment) or `"classic"` (the original, which
  is untouched).
* In game, on your own screen only:
  * **F4** switches every player between the original and the sample character.
  * **F5** forces each animation in turn (idle → walk → run → wave → automatic).
* To remove the experiment completely: delete `assets/art/characters_sample/` and `client/scripts/TownsfolkVisual.gd`,
  revert the small hooks in `Player.gd`, `World.gd` and `Art.gd`, and set `CHARACTER_SET` to `"classic"`.

## What the sample contains
| | |
|---|---|
| Characters | Austin (adult, about 50 px tall at idle, 51 px for the tallest frame including the outline); Finn (child, about 37 px). Finn is not integrated |
| Animations | idle (6 fps), walk (10 fps), run (12 fps), wave (10 fps). All 8 frames, seamless loops, in place (no root motion) |
| Directions | 8 (S, SW, W, NW, N, NE, E, SE), one row each |
| Sheets | one 512×512 PNG per animation: 8 columns (frames) × 8 rows (directions), 64×64 frames |
| Pivot | (32, 55) = the ground point between the feet |
| Variants | with a 1 px dark outline (used here) and without outline; separate drop shadow (`shadow_64px.png`, same pivot) |
| Extras | per-character palettes (.gpl/.hex), preview GIFs, `<character>.json` with fps and the foot-matched ground speed (walk 37.5 px/s, run 90.1 px/s at 1×) |
| Projection | 2:1 isometric, 30° elevation, about 29 px per metre on the ground |

No sitting, lying, working or other animations are in the sample (the full pack lists the same four).

## How it is integrated
* `client/scripts/TownsfolkVisual.gd` has the same interface as `CharacterVisual.gd`, so the Player only swaps the
  visual node.
* The sprite is drawn at **1×**, never resized, with nearest-neighbour filtering. Its pivot sits on the player's
  position (the feet), so collision, y-sorting and depth are unchanged.
* **Direction:** taken from the movement vector (the 2:1 squash is undone before choosing one of the 8 rows). Correct
  for local and remote players.
* **Animation:** idle when stopped. When moving, walk below 64 px/s and run above, using the pack's speeds. Playback
  rate follows the real speed (clamped 0.6–1.6×) so the feet don't slide. Changing animation restarts at frame 0, so
  frames never play out of order.
* The name label, status and chat bubble sit 13 px higher to clear the taller head.

## Scale: measured in the game, at the original size
| | Height | In this world (doors 41 px = 2.1 m, 19.6 px/m) |
|---|---|---|
| Original character | 34 px | 1.75 m |
| Austin (1×, no resize) | 51 px | about 2.6 m |

At its original size the sample character is **about 1.5× too tall for this world**: his head is above the house door
(`docs/screenshots/char_eval_03_scale_and_mobile.png`). The pack's own scale (about 29 px/m) is larger than this game's
(about 20–23 px/m on the ground). Matching it would need about 0.67×. That is not a whole-number factor, so it would
blur or distort the pixel art, and per your instruction no resizing was done.

## Limitations found
* **Running vs walking:** the game has a single movement speed (110 px/s), which corresponds to the pack's run. So
  normal movement always plays **run**. Walk only appears when moving slower, or when forced with F5. A real walk/run
  split would need a slower walking speed (a gameplay change, not made).
* **Greeting:** the game has no greeting action, so wave plays only with F5. Wiring it to gameplay (for example a
  "Cumprimentar" button in a player's profile) is a design decision for you.
* **Customisation:** the pack's characters are fixed designs, so skin tone, hair and clothing choices from character
  creation no longer show. Every player looks like Austin in this test. The full pack has 20 designs, which would
  have to be offered as a choice instead.
* **Sit/lie poses:** none in the pack. On sofas, benches and beds the character stays in the idle pose.
* The HUD and profile avatars still use the original character.

## Assessment
* **Style:** good. Clean 2:1 pixel art with a dark outline and a muted, modern palette. It sits well on the roads, sidewalks
  and buildings, and is more detailed and more natural-looking than the current character.
* **Animation:** smooth and well timed. 8 directions make movement read correctly in every direction (the current
  character only faces left or right).
* **Proportions vs this world:** too large at 1× (taller than doors, about 2.6 m). This is the main problem, and it can't
  be fixed by scaling without hurting the pixel art. Options: (a) accept the oversize, (b) redraw doors and buildings
  taller (an environment change, not done), or (c) use a pack drawn at this game's scale.
* **Readability:** clear at the normal desktop zoom; small but readable on a phone.
* **Fit with the game's features:** loses character customisation, and has no sit/lie/work animations.
* **Verdict:** visually strong, but at native size it is noticeably out of scale with this world and removes
  customisation. Worth the $5 only if you are willing to accept the larger characters (or change the buildings) and
  replace customisation with a choice of 20 fixed characters.

## Licence (sample)
Non-commercial use only. A commercial release needs the full pack. The sprites are excluded from this project's
licence (see `assets/art/characters_sample/townsfolk/NOTICE.md`). Do not re-upload the zip.

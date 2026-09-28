# Original actor placement initialization

> evidence: static-derived; runtime-measured: 第 6 关 061_1 装在 0xff 格 · status: live · functions: 0x407cc0, 0x4080b0, 0x411a30, 0x45e307, 0x45fa1e, 0x46be17 · tools: hsl_map_object_origins.py, hsltools/data/first_battle_formation.py, hsltools/levels/battle.py, test_hsl_opening_positions.py · updated: 2026-09-28

## 结论

- Original: EVEF records pass raw X/Y to object creation unchanged; enemy (`0x407cc0`) and player (`0x4080b0`) installers snap each coordinate to the cell centre `(v & ~31) + 16`, then `0x411a30` marks the map cell with no terrain test — an actor stands on its EVEF cell whatever the terrain (static-derived; runtime-measured: level 6's 061_1 on a 0xff cell).
- Original: SHP draw origins are signed per-frame header values (`0x45fa1e`); an image's top-left is object position minus that origin; stand objects keep the raw EVEF position (static-derived).
- Remake: `MapSceneConfig` uses grid origin (0,0) with 32-pixel cells and centred actors; `hsltools/levels/battle.py` keeps install cells on blocked terrain; the importers read signed origins and `ActorRuntime` applies them per frame (static-derived).
- Difference: none known for install coordinates; later NPC paths and foreground anchors are outside this packet. Fire zoom/blending is in [gate_fire_animation.md](gate_fire_animation.md), draw order in [original_draw_order.md](original_draw_order.md).

## 证据

**static-derived** (EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`)

### Native coordinate chain

| Address | Reading |
| --- | --- |
| `0x46be17` | enumerates EVEF records from the buffer at `0x4c0924`; records start at offset `0x10`, stride `0xd0` (`0x46be84`) |
| `0x46be33` / `0x46be36` | read record `+8` / `+0xc`; the normal-object branch passes them as X/Y and record `+4` as object code into `0x45e307` (`0x46be5b..0x46be60`) |
| `0x45e34d..0x45e360` | stores X/Y unchanged at object `+4` / `+8` |
| `0x43ede0` → `0x43eef6` → `0x407cc0` | enemy initialization; `0x407d1a..0x407d4e` makes each coordinate `(coordinate & ~31) + 16` |
| `0x4080b0` | player installer, same rounding and centring at `0x4080c6..0x4080ee` |

The old `(192,64)` display calibration must not be added to native map coordinates.

### Install has no terrain test

After the rounding, enemy initialization continues `0x446c40` (shape), `0x458c80(0x18)` (stamina jitter), `0x40ba20` (live side) and `0x411a30(actor, side)`, which takes `(+4 >> 5, +8 >> 5)` and ORs the side into the map word through `0x411900` (for a large actor, over its 3×3). No branch reads the cell's height or flags and none searches for another cell: **an actor is installed on its EVEF (or insert) cell whatever the terrain there**. Runtime-measured confirmation: level 6's villager 061_1 is live on the 0xff cell (25,15) at the 宣戰 card ([battle_006 原版开局](../runtime_observations/battle_006/README.md)). Whether such a ground actor can leave its 0xff cell is answered by the movement flood: it can cross only adjacent 0xff／253／254 cells and never steps down ([actor traversal](original_actor_traversal.md), static-derived with original instructions executed). A flying STORY walker whose endpoint is a 0xff cell stands on the endpoint (runtime-measured: the opening snapshot at the original's round-1 halt, [opening_snapshot_diff](../../../content/generated/hsl/development/opening_snapshot_diff.md)); a ground walker's endpoint goes through the walk-destination fix 0x44fbd0 ([original_script_entry](original_script_entry.md)).

### SHP draw origin (`0x45fa1e`)

The common SHP loader validates TLHS and two-byte pixels, reads header `+0x1c/+0x20` at `0x45fa5a`/`0x45fa5d`, keeps X (`0x45fa75`), negates Y (`0x45fa7b`–`0x45fa80`), subtracts X from each row segment (`0x45faac`) and writes −Y per row (`0x45fab1`–`0x45fab4`, incremented at `0x45fb3f`): the decoded image top-left is object position minus the per-frame origin, not the image centre. With `0x4a421c == 0` pixel words are copied unchanged; the alternate branch `0x45fb07` converts 565 to 555. Stand objects retain the EVEF position (without the actor-only cell-centring step); their texture top-left is `EVEF position − SHP draw_origin`.

**resource-derived**

Level 51 formation — `map_objects.json` joins `level051.bin` EVEF records with `obj-051.obs`; 12 actor placements:

| EVEF record | Actor | Raw X,Y | Initialized X,Y |
| --- | --- | --- | --- |
| 4 | 021 | 544,192 | 560,208 |
| 5 | 026 | 416,192 | 432,208 |
| 7 | 021 | 352,224 | 368,240 |
| 9 | 021 | 192,288 | 208,304 |
| 10 | 021 | 320,288 | 336,304 |
| 11 | 026 | 128,288 | 144,304 |
| 12 | 021 | 96,352 | 112,368 |
| 17 | 023 | 544,576 | 560,592 |
| 18 | 023 | 448,608 | 464,624 |
| 20 | Leonard | 480,640 | 496,656 |
| 21 | 024 | 544,672 | 560,688 |
| 22 | 024 | 480,704 | 496,720 |

STORY051 moves Leonard `(0,-96)`, yielding `(496,560)` after that motion.

Stand-object origins (original PAK re-read with `tools/hsl_map_object_origins.py --check`):

| Resource | Draw origin | Example native top-left |
| --- | --- | --- |
| tree07 | 139,225 | record 15: 149,351 |
| bar004b | 10,44 | record 8: 392,212 |
| bar004a | 155,171 | record 13: 230,232 |
| FIRE01-01 | 43,72 | unscaled record 3: 303,81 |

Tree previews are 277×271. Native bridge top-left values exactly equal the earlier curated bbox calibration. Actor frames: signed origins for all 150 live actor frames (Leonard 001-00001: 36×76, origin (11,49)).

## 重制接线

- `game/battle/runtime/MapSceneConfig.gd`: grid origin `(0,0)`, 32-pixel cells, actors drawn at the cell centre; provenance `layout: static-derived docs/evidence_packets/static_reverse/actor_placement_initialization.md`.
- `tools/hsltools/levels/battle.py` keeps install cells on blocked terrain (records `position_source.install_on_blocked_cell`) and STORY endpoints on blocked cells (`position_source.story_endpoint_on_blocked_cell`).
- `tools/hsltools/data/first_battle_formation.py` (`python3 tools/hsl.py generate first_battle_formation`) writes the level 51 placement fields, preserving existing mechanics templates; runtime stores Leonard's destination grid `(15,17)` and prepares his opening visual at `(496,656)`.
- `ActorRuntime` applies each frame's signed draw origin on frame change; stand objects use `EVEF position − draw_origin` (no runtime bridge position overrides).

## 复现

`python3 tools/hsl.py check first_battle_formation`（placement and projection）；static windows: `r2 -q -e scr.color=0 -c 'pd 40 @ 0x46be17; pd 28 @ 0x45e307; pd 28 @ 0x407d1a; pd 25 @ 0x4080b0; pd 70 @ 0x407d94; pd 30 @ 0x411a30; pd 110 @ 0x45fa1e' hsl01.exe`.

## 边界

- STORY walkers with blocked endpoints (80's 嚎, 34's 037_2／037_3): the destination goes through `0x44fbd0` and the walk stops on the `0x4111d0` chain's cell — read in [original_script_walk_path.md](original_script_walk_path.md)「证据」 and [original_script_entry.md](original_script_entry.md)「边界」. Not claimed: a large-footprint unit on a blocked cell (still moved; the PlayLoop refuses it as a stop), and two EVEF records sharing a cell (the encounter assembler refuses it; none does).
- The curated `opening_lower_formation_before_dialogue` and `first_control_action_menu` frames show different NPC locations: initial coordinates are not the first-control formation; NPC paths, scheduling, colours, foreground anchors and final formation are not established here.
- `first_battle_formation --check` does not validate the provisional combat templates or original AI.
- SHP header `+0x10` semantics are unread; animated frames and dynamic draw order are not established by these origins (see the fire and draw-order packets above).

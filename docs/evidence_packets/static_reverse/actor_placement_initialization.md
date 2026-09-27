# Original actor placement initialization

> evidence: static-derived; runtime-measured: 第 6 关 061_1 装在 0xff 格 · status: live · functions: 0x407cc0, 0x4080b0, 0x411a30, 0x45e307, 0x46be17 · tools: hsl_map_object_origins.py, hsltools/data/first_battle_formation.py, hsltools/levels/battle.py, test_hsl_opening_positions.py · updated: 2026-09-25

Evidence id: `actor_placement_initialization`.

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

## Native coordinate chain — static-derived

- `0x46be17` enumerates EVEF records from the buffer at `0x4c0924`. Records start at offset `0x10`, stride `0xd0` (`0x46be84`).
- `0x46be33` / `0x46be36` read record `+8` / `+0xc`. The normal-object branch passes these as X/Y and record `+4` as object code into `0x45e307` (`0x46be5b..0x46be60`).
- `0x45e34d..0x45e360` stores X/Y unchanged at object `+4` / `+8`.
- Enemy process `0x43ede0`, initialization branch `0x43eef6`, calls `0x407cc0`. At `0x407d1a..0x407d4e`, each coordinate becomes `(coordinate & ~31) + 16`.
- Player installer `0x4080b0` performs the same rounding and centering at `0x4080c6..0x4080ee` before creating the player.

Therefore the remake grid uses origin `(0,0)` and 32-pixel cells, and draws actors at the center. The old `(192,64)` display calibration must not be added to native map coordinates. This proof concerns actor initialization; it does not establish every original overlay polygon or foreground sprite anchor.

## Install has no terrain test

Lane R5-L4b, 2026-09-25 (r2 on the same EXE, `pd 70 @ 0x407d94`, `pd 30 @ 0x411a30`). After the rounding above, the enemy initialization continues `0x446c40` (shape), `0x458c80(0x18)` (stamina jitter), `0x40ba20` (live side) and `0x411a30(actor, side)`, which takes `(+4 >> 5, +8 >> 5)` and ORs the side into the map word through `0x411900` (for a large actor, over its 3×3). No branch reads the cell's height or flags and none searches for another cell: **an actor is installed on its EVEF (or insert) cell whatever the terrain there** (static-derived). Runtime-measured confirmation: level 6's villager 061_1 is live on the 0xff cell (25,15) at the 宣戰 card ([battle_006 原版开局](../runtime_observations/battle_006/README.md#原版开局lane-r5-l62026-09-24)).

The remake generator follows this for install cells (no STORY movement): `hsltools/levels/battle.py` keeps them and records `position_source.install_on_blocked_cell`. Whether such a ground actor can leave its 0xff cell is answered by the movement flood: it can cross only adjacent 0xff／253／254 cells and never steps down ([起点在0xff格](original_actor_traversal.md#起点在0xff格lane-r5-l4c2026-09-25), static-derived with original instructions executed). A STORY walker whose endpoint is blocked stands on the endpoint too (runtime-measured: the opening snapshot at the original's round-1 halt, [opening_snapshot_diff](../../../content/generated/hsl/development/opening_snapshot_diff.md), 53 one-cell walkers); the generator records `position_source.story_endpoint_on_blocked_cell`. Not claimed: why three walkers do not (80's 嚎, 34's 037_2／037_3, the report's `cell` row), a large-footprint unit on a blocked cell (still moved, the PlayLoop refuses it as a stop), and what happens when two EVEF records share a cell (the encounter assembler refuses it; none does).

To inspect these narrow windows again, run r2 on the external original EXE with `pd 40 @ 0x46be17`, `pd 28 @ 0x45e307`, `pd 28 @ 0x407d1a`, and `pd 25 @ 0x4080b0`. No original runtime is required for this finding.

## Formation — resource-derived

The imported `map_objects.json` joins `level051.bin` EVEF records with `obj-051.obs`. There are 12 actor placements:

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

STORY051 directly moves Leonard `(0,-96)`, yielding `(496,560)` after that motion. Runtime stores his destination grid `(15,17)` and prepares his opening visual at `(496,656)`, using its existing opening presentation contract. Other actors use their initialized cells pending recovery of their actual movement.

Run `python3 tools/hsl.py generate first_battle_formation` to regenerate placement fields while preserving existing mechanics templates; `--check` verifies live scenario placement and projection. It does not validate those provisional combat templates or original AI.

## Visual limits

The curated `opening_lower_formation_before_dialogue` and `first_control_action_menu` frames show different NPC locations. Initial coordinates cannot be mislabeled as the final first-control formation. The current change restores missing actors and their native initial arrangement; NPC paths, scheduling, colors, foreground anchors and final formation still require work.

Actual Godot rendering of the move menu and overlay was inspected. This also exposed a development-entry bug: bypassing opening left the actor at the start while clicks used the destination. Both normal and development handoffs now finish the existing opening motion before opening the menu. A live scene assertion checks the visible player position `(496,560)` after bypass.

## Stand-object SHP origins

The common SHP loader reads signed draw origins at header `+0x1c/+0x20`; see `actor_shp_draw_origin.md`. Stand objects retain the EVEF position (without the actor-only cell-centering step). Their texture top-left is `EVEF position - SHP draw_origin`.

The original PAK was re-read with `tools/hsl_map_object_origins.py --check`:

| Resource | Draw origin | Example native top-left |
| --- | --- | --- |
| tree07 | 139,225 | record 15: 149,351 |
| bar004b | 10,44 | record 8: 392,212 |
| bar004a | 155,171 | record 13: 230,232 |
| FIRE01-01 | 43,72 | unscaled record 3: 303,81 |

Tree previews are 277×271. The previous bottom-center formula placed them 46 pixels too high and half a pixel too far right. Native bridge top-left values exactly equal the earlier curated bbox calibration. Removing runtime bridge position overrides therefore preserves those measured bridge locations, confirmed by focused assertions and a Godot render. Historical calibration records remain comparison metadata only.

Fire zoom/blending, animated frames, and dynamic draw order are not established by these origins. Runtime still uses the existing foreground layer policy.

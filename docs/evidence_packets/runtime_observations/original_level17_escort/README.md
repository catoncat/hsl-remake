# Original level 17 (艾瓦台地): escort NPCs vs enemy AI, two all-wait openings

> evidence: runtime-measured; provisional: item consumption and NPC movement rule; static-derived: remake friendly candidate filter (R16), fixed-point refinement walk (R23) · status: record-only · tools: hsl_original_control.py, hsltools/data/original_save.py · updated: 2026-09-23

Lane R14. The original HSL v1.06 was loaded from the generated 回憶錄 preset
`level17_pre_battle` ([original_save_format.md](../../static_reverse/original_save_format.md):
five chapter-1 members as fresh PLAYERS rows, main-path WINFAIL wins through 15,
standing in 席達鎮 with 艾瓦台地 unvisited), walked to point 17, and played into the
escort battle twice with every player unit choosing 待機 on every turn. Live unit
records were dumped at each player menu and at selected AI frames through the
Win32 memory helper (`receipt.json`: 18 snapshots, 24 units each). The remake was
then booted into `content/battles/battle_017.json` with the same all-wait policy
(`remake_all_wait_trace.gd.txt` → `remake_all_wait_trace.txt`) so the two openings
can be read side by side. Nothing here is a balance claim; the player never acts.

## Route and instruments

- Control: `python3 tools/hsl_original_control.py` (`click`, `rclick`, `key space`,
  `screenshot`); every input verified against the emitted cnc-ddraw PNG. Title →
  戰場記錄 lands in the first battle, so the preset was loaded from the in-battle
  system menu (right-click → 讀取回憶錄 → row 1 `席達鎮 等級01 2:00`), then Escape
  out of the town, click 艾瓦台地 on the map (`(310,105)` logical), Space through the
  opening lines until the first action menu.
- Memory: `tools/hsl_original_probe_units.py` (promoted from this packet's `probe_units.py.txt`
  by lane R16) drives `ignored/bin/hsl_win32_memread.exe` (`tools/build_runtime_helpers.sh`)
  to read `*0x4c1bc8` actor records (0x1fc stride; field table in original_save_format.md)
  joined to the object list at `0x4c34c0` by `+0xa4`; grid = object `+4`/`+8` ÷ 32. Side codes: player `0x10000`, enemy
  `0x20000`, friendly NPC `0x50000`.
- 待機 was located per menu by template match; the icon's highlighted state
  differs, so the second (activating) click is unconditional. Two mis-hits (道具,
  狀態) were closed with Escape before any further input; neither changed unit state
  (the dumps before/after are identical).

## Spawn (first player control)

| unit | original run 1 | original run 2 | remake (loop seed 1) | script cell |
| --- | --- | --- | --- | --- |
| 雷歐納德 / 緹娜 / 琥 / 漢克斯 / 雪拉 | L1 30 · L2 36 (MP 19) · L4 40 · L7 50 · L6 59 (MP 41) at (34,20) (35,17) (35,22) (37,22) (38,19) | identical | identical HP, MP, cells | — |
| 克里夫 064 | L5 **64/91** at (31,14) | L5 **74/94** at (31,14) | L4 **65/87** at (31,14) after the same first strike | (31,14) |
| 062 ×3 | L5 83, L5 83, L5 82 at (32,13) (32,16) (35,13) | L5 83, L4 75, L5 81 | L4 75, L5 82, L4 77 | same |
| 035 ×2 (front) | L10 58 MP **20**/28 at (27,14); L10 58 MP 28 at (29,15) | L10 58 MP 28 at **(30,14)**; L10 58 MP 28 at (29,15) | 035_1 moved to (30,14); 035_2 at (25,15) | (27,14) (25,15) |
| 038 / 037 / 036 (front) | 038 L4 66 (20,12), L6 79 (26,18); 037 L6 67 (22,17) (22,11); 036 L4 52 (22,14) | 038 L5 72, L4 66; 037 67, 67; 036 L3 46 | 038 66, 80; 037 67, 67; 036 52 | same cells |
| rear group (9 units) | 038 80, 80 · 035 58 ×3 MP 28 · 037 67 ×2 · 036 45 | 038 80, 84 · 035 58 ×3 · 037 67 ×2 · 036 59 | 038 79, 66 · 035 58 ×3 · 037 70, 67 · 036 73 | same cells |

- Both original runs show per-object level/HP variance on NPCs and enemies (062 L4–L5
  HP 75–83, 064 max 91/94, 036 L3–L5 HP 45–59); the remake's loop rolls the same kind
  of variance from the actor templates (064 87, 036 73). Player rows are identical
  on both sides.
- In both original runs one enemy acted **before** the first player menu: 035 at
  (27,14). Run 1 it cast 地裂 (MP 28→20, 064 91→64); run 2 it moved to (30,14) and
  struck 064 in melee (94→74). The remake's first AI turn is the same unit doing the
  run-2 thing (`move_then_attack` → 064 87→65). 035 at (25,15) had moved to (29,15)
  in both original runs before first control; the remake's 035_2 moves to (27,14)
  during round 1.

## Round-by-round (player side always 待機)

Original round 1 (both runs): 037 (22,17)→(26,17), 037 (22,11)→(24,13), 036
(22,14)→(26,14)/(27,14), 038 (20,12)→(26,12), 038 (26,18)→(32,18)/(30,16); **064
moved (31,14)→(33,15)** — away from the two 035 and toward the party; all three 062
stayed. Run 1 additionally: 035 (27,14)→(31,14) and the second 035 cast 地裂 from
(29,15) (MP 28→20): 064 64→37, 062 at (32,16) 83→59.

Remake round 1: 037 →(25,16) and →(24,13), 036 →(26,13), 038 →(26,12) and →(30,16),
035_2 →(27,14); **062 ×3 and 064 `wait`** (`target_selection.index = -1`, no draws).

Original round 2: run 1 — 038 (32,18)→(35,20) struck 雷歐納德 30→10; **064
(33,15)→(34,18)**; 038 →(32,12) struck 062 at (32,13) 83→48; the two 035 cast 咒殺
(MP 20→11) and 地裂 (MP 20→12) on 062 at (32,16) 59→6; 037 →(32,17) finished it
(6→0, 搬運工人 death line). Run 2 — both 035 cast 地裂 (MP 28→20 each) on 064 at
(33,15) and 062 at (32,16): 064 74→47→21, 062 75→51→29; by the first round-2 menu
038 had reached (26,12) and (30,16).

Remake round 2: 035_1 cast 咒殺 (MP 28→19) 064 65→36; 035_2 cast 地裂 (MP 28→20)
064 36→10; 062 ×3 and 064 `wait`; 036_1 (26,13)→(31,13) struck 064 10→0 →
`battle_outcome=defeat_leonard` (shared fail key; the scenario label is fail_1
「艾瓦遺民 陣亡」, WINFAIL017 `actCheckPlayer(1, SID_ENEMY064)`).

### Remake after lanes R16 and R23 (same policy, loop seed 1)

The round table the two remake reruns give beside the original, 克里夫 064 only
([remake_all_wait_trace_r16.txt](remake_all_wait_trace_r16.txt),
[remake_all_wait_trace_r23.txt](remake_all_wait_trace_r23.txt)):

| round | original run 1 | original run 2 | remake R16 (path-distance walk) | remake R23 (0x411080 refinement) | rule position / why |
| --- | --- | --- | --- | --- | --- |
| pre-control | 035 地裂 91→64 | 035 melee 94→74 | 035_1 melee 87→65 | 035_1 melee 87→65 | `AIDecisionRules.select_action` roll (RNG); the melee 20/22 and 地裂 27/26 both sit in the remake's numbers — no rule difference |
| 1 move | 064 (31,14)→**(33,15)** | (31,14)→**(33,15)** | →(32,17) | →**(33,15)** | `AINavigationRules.approach_home`: R16 ranked stoppable cells by path distance to (37,18); R23 replays `0x4111a0`/`0x411080` (flood 18→4, Manhattan-nearest to the previous pick: (37,18)→(36,18)→(36,16)→(34,16)→(33,15)) — static-derived, same cell as both original runs |
| 1 038 at (26,18) | →(32,18), no strike | →(30,16), no strike | →(31,17) **struck 064 65→33** | →**(30,16)**, no strike | consequence of the cell above: (32,17) was 7 Manhattan from the 038 (`find_type 3`, nearest foe) and its neighbour reachable in 6 moves; (33,15) is 10 away, tied with 雷歐納德, out of reach |
| 2 damage | 地裂+咒殺 on the 062 at (32,16) | 地裂 ×2 on 064 74→47→21 | 咒殺 65→36, 地裂 36→10, 036 melee 10→**0** | 035_1 地裂 on 062_2 splashes 064 65→39 | caster targeting and 地裂 splash are the existing kernels; 064 is no longer adjacent to a melee attacker |
| 2 move | 064 (33,15)→(34,18) | (33,15) held (dumps per menu) | dead | (33,15)→**(36,16)** | refinement (37,18)→(37,17)→(36,16); original run 2 reached (36,16) one round later |
| 3 | 雷歐納德 fell | 064 (33,15)→(36,16), heals 21→61 | — | 064 →(37,18), released round 4 (`fixed_point_reached`), 39 HP, no potion | `AIPriorityRules.self_recovery`: the 回復藥 fires at HP ≤ 12–29% of max (original 21/94 = 22%); 39/87 = 45% is above the band, so no drink — same rule, different HP path |
| 4–5 | — | run stopped | — | 038_2 strikes 雷歐納德 30→12 (round 4), 037_2 finishes him (round 5) → `defeat_leonard`; 064 alive at 39 | all-wait policy; original run 1 lost 雷歐納德 in round 3 the same way |

Differences with a rule position: the round-1 cell (fixed, static-derived). Differences
without one: the pre-control action kind, which caster hits whom, and the potion round —
each traces to an RNG draw inside a kernel whose formula both sides share. The R23 run
also shows the round-6 `actSetPlayerFixPos(SID_ENEMY064,1,1024,416,1)` reading: it now
re-anchors 064 to (32,13) with radius 1 instead of teleporting it (the all-wait battle
ends in round 5, before it fires; the interpreter test covers the write).

Original round 3: run 1 — 雷歐納德 fell (defeat page; no dump). Run 2 — **064
(33,15)→(36,16) and 21→61** in one AI turn; 038 →(32,12) and 036 →(31,13) both
adjacent to 062 at (32,13): 83→18, with `EXP 23` shown over the attacker; 038
(30,16)→(33,16) killed 062 at (32,16) 29→0 (death line). The run was stopped there;
the dump `r14p-8` shows 064 holding one 回復藥 (241) at (36,16), 062 at (32,13)
holding none, the other two 062 holding one each.

## What this supports

- runtime-measured: the enemy side's opening in the remake matches the original's
  in unit, order and kind for the front group (first 035 acts before player control;
  037/038/036 approach along the same lanes; the two 035 spend 8/9 MP on 地裂/咒殺
  at the escort target; 地裂's 27/26 on 064 and 24/22 on an adjacent 062 sit inside
  the remake's numbers 26–29). 038 melee on a 062 was 35 in run 1 (run 2's 65 came
  from two adjacent attackers in one interval); 035 melee on 064 20 (remake 22).
- runtime-measured: in the original, 克里夫 064 **moves every round** (two cells
  toward the player group, away from the casters — i.e. toward its EVEF fixed point
  (37,18), see the static-derived bullet below) and **heals itself by 40 at 21/94
  HP**; the three 062 never move in three rounds. In the remake with the same
  policy, 064 and all 062 `wait` every turn, 064 carries no item, and it dies in round
  2, which is the sweep's recorded outcome for level 17
  (`results.json` level 17: `fail`, `defeat_leonard`, 2 rounds).
- runtime-measured: a 062's death does not end the battle (run 2 continued after
  the death line); 064's death ends it in the remake by WINFAIL017 fail 1 — the
  original's fail path was not reached in either run.
- resource-derived (lane R16, replaces the provisional item reading): the EVEF
  instance words 0x10..0x2C of level017.BIN give 064 (record 8) two 回復藥 `[241, 241]`,
  the 062 at (32,16) and (35,13) (records 6, 7) one each and the 062 at (32,13)
  (record 5) none — exactly the `r14p-8` slots after 064 spent one at 21/94 (+40 =
  241's `max_hp: 40`). The remake now fills these slots at initialization
  (`ActorInitializationRules.apply_instance_words`) and the friendly self-heal runs
  through the same `ai_check_hp` path as the enemy side.
- static-derived (lane R16, replaces the "toward the party" reading): 064's EVEF
  instance record 8 carries the index-15 word `0x04A00240` → fixed point (37,18)
  with `ai_fixed 8` and object flag 0x4000 (install callback `0x42bd50`); an unarmed
  guard off its point walks toward it every turn (`0x43fbd6` → `0x411080`) and is
  released on arrival. (37,18) lies inside the party's area, which is why the moves
  read as "toward the party"; see
  [original_ai_navigation.md](../../static_reverse/original_ai_navigation.md#evef-实例覆盖友军护送目标与物品).
  provisional: the exact cells — original (33,15) then (34,18)/(36,16), remake (seed 1)
  (32,17) then (36,17) ([remake_all_wait_trace_r16.txt](remake_all_wait_trace_r16.txt)) —
  differed because R16 ranked this turn's cells by path distance to the point. Lane
  R23 replays the original's refinement (floods of radius 18→move, Manhattan-nearest
  to the previous pick, occupied cells skipped, equal candidates on a coin): the
  remake now lands (33,15) in round 1 like both original runs and (36,16) in round 2
  (original run 2's round-3 cell). Still not modelled: the 80% rejection of crowded
  cells (`0x40d800`) and the native flood metric; replacing evidence is a bounded
  execution of `0x411080`.
- static-derived (lane R16, replaces R14's negative-evidence): the remake's friendly
  AI returns no target for 064/062 because every one of the 15 living foes is
  dropped by the **approach filter**, not by `_are_enemies` or `guard_allows`
  (`BattleLoopAI._prepare_ai_turn` → `ai_decision.candidate_filters`
  `{"living_foes":15,"without_approach":15,"guard_excluded":0,"unarmed":true}`,
  `wait_reason=no_valid_action`). 062/064 carry `weapon_code 0`, so
  `PositionCapabilityRules.attack_pattern` yields the range0 pattern with no
  offsets, `AINavigationRules.approaches` has no goal cell for any foe, and
  `select_target` sees only removed rows. The original does the same for an
  unarmed non-guard: `0x409090` (weapon range) returns 0 at `0x43ff1f`/`0x440041`
  and the turn ends at `0x441eb8` — the three 062 standing still is parity, not
  a remake gap. The 064 difference is data, see
  [original_ai_navigation.md](../../static_reverse/original_ai_navigation.md#evef-实例覆盖友军护送目标与物品) (EVEF instance
  words). The trace driver now prints `wait_reason`/`candidate_filters` for
  friendly actors.

## Not covered

- Player actions, the round-6/8 insertions (WINFAIL017 events 1/2, 嚎's arrival),
  the win path, the original's result page for fail 1.
- Whether the original's 062 ever move (three rounds only), the original round
  order within a round (dumps are per player menu, not per AI step), hit/miss rolls.
- The remake trace uses loop seed 1 and the in-loop rolled HP; the original's RNG
  is not seeded, so cell-for-cell equality is only claimed where both runs agree.

## Files

- `receipt.json` — 18 live-record snapshots (both runs, labels in play order), side
  codes, frame hashes.
- `run2-opening-cliff-line.png` — 克里夫's opening line on arrival at 艾瓦台地.
- `run1-round1-earth-spell-on-cliff.png` — 地裂 landing on 064 beside the cart.
- `run2-round3-enemy-exp-on-refugee.png` — `EXP 23` over the 038 that struck a 062.
- `run2-round3-refugee-death-line.png` — 搬運工人 death line; the battle continues.
- live-record dump script: [`tools/hsl_original_probe_units.py`](../../../../tools/hsl_original_probe_units.py)
  (read-only; item slots `+0x138`; `PID [label] --out-dir`).
- `remake_all_wait_trace.gd.txt` / `remake_all_wait_trace.txt` — the headless
  driver (SceneTree script: `Autoplay.reach_first_control`, `choose_command("wait")`
  for players, `step_ai_turn` with per-step roster diffs) and its R14 output
  (`HSL_TRACE_SCENARIO` / `HSL_TRACE_ROUNDS` / `HSL_TRACE_PLAYER_HP` select another
  scenario, round count and an observation-only party HP; run it as a temporary
  `res://tests/*.gd` copy).
- `remake_all_wait_trace_r16.txt` — the same level-17 run after lane R16 (instance
  items, rear-group `wait_round` 3, 064's fixed-point walk).
- `remake_all_wait_trace_r23.txt` — the same run after lane R23 (`HSL_TRACE_ROUNDS=9`):
  064's `home_approach.refinements` per round, (33,15) → (36,16) → (37,18), alive at the
  round-5 defeat.
- `remake_all_wait_trace_level52.txt` — the level-52 run (emperor `wait_round` 8 /
  `find_range` 10, two 026 `wait_round` 2) beside the user's observation that the
  original's emperor and upper group do not come down at once (user-confirmed).

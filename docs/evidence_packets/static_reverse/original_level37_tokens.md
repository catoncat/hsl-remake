# WINFAIL037 Token Readings

> evidence: static-derived · status: live · functions: 0x407ec0, 0x42c700, 0x42caa0, 0x4348f0, 0x448840, 0x44e820, 0x450840, 0x453b30, 0x45dbe1 · updated: 2026-09-29

Evidence tier: `static-derived` from the resource action table and bounded `hsl01.exe` static read. This packet records the five level 37 tokens required by `WINFAIL037`; it does not claim a complete native battle equivalence.

## Dispatcher

`ACTION.H` assigns 110 (`0x6e`), 113 (`0x71`), 115 (`0x73`), 116 (`0x74`), and 118 (`0x76`). The handlers are in `0x450840`:

- `actCheckSerialPlayerAttacked([attacked player id][serial])` is case `0x6e`. The dispatcher reads the token and serial, resolves a live actor through the same registration lookup used by the nearby player checks, and enters the attacked-object comparison path. The remake reads the PlayLoop `last_attack` record in the attack action's completion scan (the `attack` context, lane R37 — [original_round_display.md](original_round_display.md) «Attack context») and requires one of its targets to be the exact token/serial unit.
- `actFALSE` is case `0x71`. It jumps to the condition-failure path without inspecting arguments. The remake implements it as a supported condition that always returns false.
- `actSetPlayerWalkShape([player id][serial])` is case `0x73`. The handler resolves code plus serial and invokes the actor walk-shape transition (`0x46c40`). The remake records the resolved unit and serial as a presentation request; actual frame availability remains an ActorRuntime boundary, so no frame group is invented.
- `actCheckNotPlayerAttacker([player id])` is case `0x74`. The current attack actor is compared with the resolved player id and the condition succeeds only when the named player is not the attacker. The remake uses `last_attack.attacker_id` in the attack action's completion scan; at a completion without an attack the attacker global is 0 and the condition holds (lane R37).
- `actPlayerJobUpProcess([player id][serial])` is case `0x76`. It calls `0x4348f0(player_code, 0x80000000)` and consumes two script arguments.

## Guardians and the pillar puzzle (R6-L10)

STORY037 fields five gems `guard067_1..5` (PLAYERS 67, pmMagicAttack, `no_attack`, max HP 1) and five guardians `guard066_1..5` (PLAYERS 66, pmEnemy, 050's sprite, max HP 1), all undead, in random-slot order ([random position](original_random_position.md)). Reading of WINFAIL037 in the remake:

- A gem takes magic and specials only (`ActorRoleRules.player_range_selectable`, [player mode sides](original_player_mode_sides.md)); a hit gem revives at 1 HP and `actSetPlayerMode … pmPlayerEnemy` switches it off (no range selects it), `actSetPlayerMode … pmMagicAttack` switches all five back on.
- Physical attacks on a guardian 066 fire events 38–45 (2096 「攻擊對它們毫無效果」): it revives at 1 HP.
- The mid-action `actCheckEventNotExist` (events 1–37) is a chain gate (lane R6-L11, static-derived: `0x450840` case `0x72` inside the status-object tick `0x453b30` ends the chain while any listed event slot still holds its code, `0x44e820`). A struck gem's event has already left the slot table when its chain runs, so the gate asks whether the other four gems of this round were struck earlier. Gem 5 struck while another gem is lit only goes dark; gem 5 struck **last** reaches `actInsertEventStatus 6` (guardians removed, Enemy052 inserted); any other gem struck last reaches `actInsertEventStatus 7`／13／19／25／31／32, which relights the five gems and arms the next round (2102／2103／2104 are Leonard's and Klodi's reset lines, 2104「依照他們出現的順序」). Gem 5 is the last of the five white lights of the opening (`actInsertObjectRandomPos … 4` fills slot 4 last), so 'in order of appearance' ends on it; only the last position is checked. Several gems struck by one area spell: one scan starts one event, and a gated chain never reaches its `actExecWinFailProcess`, so only the lowest struck gem's event fires — the others stay lit (same scan shape as the original).
- The guardians' AI: 066 are ordinary enemy AI; a gem has no AI declarations and no hostile unit (pmALL shares a bit with everyone), so it waits (`BattleLoopAI._idle_without_strategy`, provisional).

## Job Up

`0x4348f0(code, flag)` is a dedicated player-slot transformation (`hsl01.exe`, same SHA as the other packets; r2 `pdg` of the function, re-runnable with `tools/hsl_exe_decompile.py 0x4348f0`). Reading in call order:

1. `0x42caa0(code)` — the slot must be enabled.
2. `job_up = *(record + 0x60)` with `record = [0x4c1bc8] + (code + 1) · 0x1fc`. **`job_up == 0` returns before anything else** — no exchange, no refresh, no receipt.
3. `desc = 0x45dbe1(job_up)` = `*(0x4a2728 + job_up · 4)`, the parsed object descriptor of object code `job_up`; a null descriptor also returns.
4. `0x42c700(code, job_up)` writes `job_up` into the slot's object-code table (`0x4c4360[code]`), so the next `defProcPlayerInstall` of that slot constructs the up object.
5. `target = 0x4c1afc + *(desc + 0xa4) · 0x1fc` — the PLAYERS row indexed by the descriptor's `+0xa4`, i.e. `obj_Data7` (「Extra Data Table ID」; the same 4-byte stride that puts `obj_Data8` at `+0xa8` and `obj_Data9` at `+0xac` in [原安装分支](original_player_install.md)).
6. Field copy from `target` into `record` — exactly the list of [原城镇转职](original_town_job_up.md#exchange-helper-0x4348f0code-flag) (`+0x8..+0x14` sounds when non-zero, `+0x18/+0x1c` job/title, `+0x20/+0x22`, `+0x2c/+0x5c/+0x60` shape/face/job_up, `+0xa0`, `+0xec` weapon when non-zero, `+0x118..+0x128` resists capped 80, `+0x130` move capped 12, `+0x194..+0x1b4` additive layer, `+0x134 |= flag`); then `0x448840(record)`.

### Level-37 target: PLAYERS row 017, not 052

`resource-derived` chain for the registered 咕嚕 (slot 7, PLAYERS row 008):

| hop | value | source |
| --- | --- | --- |
| `record + 0x60` of a never-transformed 咕嚕 | `job_up_code = obj_Player8Up1` | `PLAYERS.TXT` row `code = 8` |
| `obj_Player8Up1` | `816` | `OBJ-ALL.H` (`obj_Player1Up1..9Up1` = 809..817, `1Up2/2Up2` = 818/819) |
| object 816 | `Player8_Up1`, `obj_Data7 = 17`, `SHAPE\017-00001.SHP`, `SID_PLAYER16`, `defProcPlayer` | `global.obs` |
| level override | none — `obj-037.obs` declares no object 816 (its codes are 3–14 party installs, 96 Enemy052, 180–188 conditional installs, 17/18/19/90/97/98/99 story objects) | `@:\data\obj-037.obs` (seed `sources.objects`) |
| `*(desc + 0xa4)` → PLAYERS row | **017** (`jobEvilMonster` 邪獸, `name_7` 咕嚕, `FACE0007`, `job_up_code = 0`, `sound_walk FLY002`, `attack ATTACK20`, `dead DEAD0003`, weapon 53) | `PLAYERS.TXT` row `code = 17` |

So `actPlayerJobUpProcess SID_咕嚕 0` in WINFAIL037 turns 咕嚕 into the **same 017 row the town chain names** (`JobUpRules.TOWN_TARGETS["008"] = "017"`); the `0x80000000` flag is the first-tier flag both callers write. The `actInsertStoryObjectRandomPos obj_Story_Player8` that follows re-installs slot 7, whose object code is now 816: the constructor `0x407ec0` draws the 017 shape. Row 052 (`jobWindWarrior`, name 306「???」, `FACE0052`) is the guardian 謎之生命體 the party fights and `actDeleteObject SID_ENEMY052` removes; it is not a job-up target. WINFAIL037 messages 2125/2126 (「這....這..........是咕嚕嗎？」「咕嚕和那怪物..............合體了？」) are consistent with the member keeping his name on a new form — a consistency check, not the basis.

History: until 2026-09-21 the remake mapped 008 → 052 (`provisional`, "reviewed source target"); the chain above replaces it. The 052 walk / cut-in imports stay, as the guardian's own presentation.

The remake therefore assembles `scenario_rules.job_up_targets: {"008": "017"}` with the generated 017 template in `scenario_rules.job_up_templates` (`hsltools.levels.battle` LEVELS[37]), and both callers run through `JobUpRules.merge_source_template`: the stable unit id, party role, `actor_id`, level, experience and attributes stay; the target's job code, caps, additive PLAYERS layer, capped resists／move point and declared weapon 53 merge in; `job_up_flags |= 0x80000000`, `job_up_target_actor_id = "017"` and a `job_up_history` step are recorded; the shared `ProgressionRules` refresh (0x448840) then derives the 017 form. Only the cinematic departure request for that same registered player is removed. Missing target data is an explicit `unsupported_encountered` reason.

### Vitals after the exchange (static-derived)

Neither function on the path writes the record's current or maximum HP/MP (`+0xd8/+0xdc/+0xe0/+0xe4`, offsets per [原成长刷新](original_growth_refresh.md)):

- `0x4348f0` writes only the offsets listed above.
- `0x407ec0` (player constructor reached by the re-install of `obj_Story_Player8`): for object kind 3 it re-reads the slot, falls to the fresh template copy `0x44cb10(slot, 1)` only when the live working attributes `+0x4c..+0x58` are all zero (a never-initialised record), **deletes the object and returns when `+0xd8 < 1`** (a dead member is not re-installed), otherwise touches only the object's own transient fields (`+0x14`, `+0x1b6`, `+0x4`, `+0x1c`, `+0x28`, `+0x134` from insert parameters) and ends with `0x448840(record)`.
- `0x448840` clamps a current value downward to the new maximum and never refills ([原成长刷新](original_growth_refresh.md), probe-verified).

The remake keeps the member's current HP/MP through the shared refresh's clamp (`WinfailActions._apply_player_job_up`); the earlier "stands at the refreshed maximum" was `provisional` and is replaced by this reading. A member already defeated stays defeated (the exchange still records; the re-install is refused natively).

### A member whose row declares `job_up_code = 0`

`negative-evidence` for the scenario itself: TOWNDEF's `teCheckJobUp` entries name 雷歐納德／緹娜／琥／漢克斯／雪拉／雷特／嚎／克羅蒂 and `teCheckJobUp2` 雷歐納德／緹娜 — **no `SID_咕嚕`**, so a 咕嚕 already standing on 017 cannot reach level 37 in the original; the only path onto 017 is this token. If a carry nevertheless holds such a member (dev fixture), `0x4348f0` returns at step 2 (017 declares `job_up_code = 0`): the remake mirrors that as a no-op receipt `job_up_code_zero_noop` in `job_up_changes` — no stacking, no `unsupported_encountered`.

## Conditional install of 咕嚕

`resource-derived`: EVEF record 10 of level 37 is object 187 「咕嚕(有才產生)」, `defProcPlayerInstall` with `obj_Data8 = 1` (conditional install), `obj_Data9 = 7` (registered slot 7) at placement (384, 1312); STORY037 then walks `SID_咕嚕` by (0, −192). The conditional branch of `defProcPlayerInstall` (`0x4080b0`: only an existing, enabled registered slot reaches the constructor) is the static-derived basis in [原安装分支](original_player_install.md). The remake fields the slot `install_if_carried` (`ConditionalPartyRules`), the same reading as the encounter slots and the other 27 formal battles carrying such records. Headless observation before the fix (runtime-measured, not original evidence): `battle_037.json` had no 咕嚕 row, so a carry holding him was silently reduced and the job-up token could never fire in the product.

## Limits

- The exact native field-to-domain mapping for every copied offset, the global actor registration side effects, frame-set timing, and the original RNG/scheduler are not reconstructed. Those boundaries are `provisional`; the implementation relies on the reviewed PLAYERS templates, the existing single PlayLoop state owner, and focused runtime assertions.
- The vitals reading above is a static read of `0x4348f0`, a bounded read of `0x407ec0` and the probe-verified `0x448840`; no native run of the whole WINFAIL037 event has been observed. Replacement evidence for the remaining doubt: a bounded native probe executing `0x4348f0` then `0x407ec0` on a slot with reduced HP.
- `job_up_targets` maps only the base row 008 to 017 — the only row 0x4348f0 can reach from a registered 咕嚕; the 017 → 0 chain end is handled as the native no-op.
- The conditional install is read as 「carried ⇒ installed」; a registered-but-disabled slot is not modelled. A launch without a campaign hand-off fields every slot (dev／sweep), so the registered sweep roster of level 37 now includes 咕嚕.
- `actInsertStoryObjectRandomPos obj_Story_Player8` after the job-up is the cinematic re-insert of the same registered player: the interpreter keeps the unit (the preceding `actDeleteObject SID_咕嚕` departure is withdrawn) and records the insert as unresolved (`obj_Story_Player8` is not a `script_objects` row); the white-light presentation and the random landing are not remade.

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleLoopAI.gd` rules：an undeclared unit whose side meets every living unit — the level-37 gems — has nothing the 0x40bb80 scan can pick

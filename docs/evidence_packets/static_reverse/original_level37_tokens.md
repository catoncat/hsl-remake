# WINFAIL037（level 37）：五个 token、宝石谜题与咕嚕转职

> evidence: static-derived · status: live · functions: 0x4051d0, 0x407ec0, 0x42c700, 0x42caa0, 0x4348f0, 0x448840, 0x44e820, 0x450840, 0x451d0f, 0x451db7, 0x453b30, 0x45dbe1 · tools: hsltools/probes/objcomd_motion.py, run_winfail_rules_tests.gd · updated: 2026-09-28

## 结论

- 原版 WINFAIL037 用到的五个 token 在 `0x450840` 的 case 0x6e／0x71／0x73／0x74／0x76；宝石谜题靠 case 0x72 链闸门判「最后被击中的是否第 5 颗」；`actPlayerJobUpProcess SID_咕嚕` 经 `0x4348f0` 把咕嚕换成 PLAYERS 017 行（邪獸），不改当前 HP／MP（static-derived；resource-derived）。
- 重制 `WinfailScenarioRules`／`WinfailActions` 实现这五个 token 与链闸门，`scenario_rules.job_up_targets: {"008": "017"}` 经 `JobUpRules.merge_source_template` 合并，咕嚕按 `install_if_carried` 条件安装（static-derived 输入）。
- 随机落点已重制：五个守卫对按 `actSetRandomPos` 洗牌后的槽位落点（`BattleLoopInit` 在全局流上洗牌，[随机位置](original_random_position.md)），开场表现读同一顺序；WINFAIL037 的 `actSetPlayerPosToRandom0` 把表现槽 0 设为该角色像素（`0x451db7`）（static-derived）。
- 白光是 `defProcObjectMove` 对象（obj-037.obs 17「白光」／19「白光2」，BALL001），原指令轨迹由 `0x4051d0` 逐 tick 跑出；重制 `StoryEffectObjects` 按该轨迹画加色缩放与级数淡出（static-derived）。
- 差异：宝石无 AI 时原地等待、复制字段的完整语义未重建（provisional）。

## 证据

### static-derived：分派

`ACTION.H` assigns 110 (`0x6e`), 113 (`0x71`), 115 (`0x73`), 116 (`0x74`), and 118 (`0x76`). The handlers are in `0x450840`:

- `actCheckSerialPlayerAttacked([attacked player id][serial])` is case `0x6e`. The dispatcher reads the token and serial, resolves a live actor through the same registration lookup used by the nearby player checks, and enters the attacked-object comparison path. The remake reads the PlayLoop `last_attack` record in the attack action's completion scan (the `attack` context — [original_round_display.md](original_round_display.md) «攻击上下文») and requires one of its targets to be the exact token/serial unit.
- `actFALSE` is case `0x71`. It jumps to the condition-failure path without inspecting arguments. The remake implements it as a supported condition that always returns false.
- `actSetPlayerWalkShape([player id][serial])` is case `0x73`. The handler resolves code plus serial and invokes the actor walk-shape transition (`0x46c40`). The remake records the resolved unit and serial as a presentation request; actual frame availability remains an ActorRuntime boundary, so no frame group is invented.
- `actCheckNotPlayerAttacker([player id])` is case `0x74`. The current attack actor is compared with the resolved player id and the condition succeeds only when the named player is not the attacker. The remake uses `last_attack.attacker_id` in the attack action's completion scan; at a completion without an attack the attacker global is 0 and the condition holds.
- `actPlayerJobUpProcess([player id][serial])` is case `0x76`. It calls `0x4348f0(player_code, 0x80000000)` and consumes two script arguments.

### resource-derived＋static-derived：守卫与宝石谜题

STORY037 fields five gems `guard067_1..5` (PLAYERS 67, pmMagicAttack, `no_attack`, max HP 1) and five guardians `guard066_1..5` (PLAYERS 66, pmEnemy, 050's sprite, max HP 1), all undead, in random-slot order ([random position](original_random_position.md)). Reading of WINFAIL037 in the remake:

- A gem takes magic and specials only (`ActorRoleRules.player_range_selectable`, [player mode sides](original_player_mode_sides.md)); a hit gem revives at 1 HP and `actSetPlayerMode … pmPlayerEnemy` switches it off (no range selects it), `actSetPlayerMode … pmMagicAttack` switches all five back on.
- Physical attacks on a guardian 066 fire events 38–45 (2096 「攻擊對它們毫無效果」): it revives at 1 HP.
- The mid-action `actCheckEventNotExist` (events 1–37) is a chain gate (static-derived: `0x450840` case `0x72` inside the status-object tick `0x453b30` ends the chain while any listed event slot still holds its code, `0x44e820`). A struck gem's event has already left the slot table when its chain runs, so the gate asks whether the other four gems of this round were struck earlier. Gem 5 struck while another gem is lit only goes dark; gem 5 struck **last** reaches `actInsertEventStatus 6` (guardians removed, Enemy052 inserted); any other gem struck last reaches `actInsertEventStatus 7`／13／19／25／31／32, which relights the five gems and arms the next round (2102／2103／2104 are Leonard's and Klodi's reset lines, 2104「依照他們出現的順序」). Gem 5 is the last of the five white lights of the opening (`actInsertObjectRandomPos … 4` fills slot 4 last), so 'in order of appearance' ends on it; only the last position is checked. Several gems struck by one area spell: one scan starts one event, and a gated chain never reaches its `actExecWinFailProcess`, so only the lowest struck gem's event fires — the others stay lit (same scan shape as the original).
- The guardians' AI: 066 are ordinary enemy AI; a gem has no AI declarations and no hostile unit (pmALL shares a bit with everyone), so it waits (`BattleLoopAI.idle_without_strategy`, provisional).

### static-derived：白光（`defProcObjectMove` 原指令轨迹）

STORY037 每个守卫对之前在槽 k 插入 `obj_Story_Level_WhiteLight`（obj-037.obs code 17，`SHAPE`＝`MAGIC\BALL001.SHP`，`planeEffect6`，`obj_Data7 = 21`，无 `obj_Mode`），再 `actDelay 10` 后删石像、插宝石与守护者；WINFAIL037 事件 6 在 (496, 304) 插同一对象，事件 48（咕嚕合体）在 052 与咕嚕的位置各插一次 `obj_Story_Level_WhiteLight2`（code 19，同 BALL001，`obj_Data7 = 62`）。`obj_Data7` 选 objcomd.txt 程序：21 = `objmZoomOutIn 0x1000,0x3000, objmWaitLargerZoom 0x10000`；62 = `objmZoomOutIn 0x1000,0x1000, objmWaitLargerZoom 0x18000, objmStopZoom, objmSetZoomEffect 4, objmDelay 80, objmFadeIn 3`。

`hsltools/probes/objcomd_motion.py` 以 obj-037.obs 模板在 `0x4051d0`（跳表 `0x406bc8`）上逐 tick 执行这两个对象，轨迹写进 `objcomd_motion.json`：

| 对象 | 缩放（16.16） | 模式 | 级数 | 删除 |
| --- | --- | --- | --- | --- |
| 白光（21） | tick 1 为 0.4375，每 tick +0.1875，到 tick 37 为 7.1875 | tick 1–5 `engZOOM｜engADDCOLOR`（整幅加色）；tick 6 起加 `engMIX` | 16 起每 2 tick 降 1，到 1 | tick 38 |
| 白光2（62） | tick 1 为 0.1875，每 tick +0.0625，tick 23 达 1.5625；此后在 1.53–1.59 间每 9 tick 往返 | tick 1–104 整幅加色；tick 105 起加 `engMIX` | 16 起每 3 tick 降 1，到 1 | tick 153 |

两者位置不动、不发声、脚本不等它（插入后紧跟 `actDelay 10`／`actDelay 1`）。加色由 `0x4051d0` 自身写入模式（模板没有 `obj_Mode`）。

### static-derived：转职 `0x4348f0`

`0x4348f0(code, flag)` is a dedicated player-slot transformation (`hsl01.exe`, same SHA as the other packets; r2 `pdg` of the function, re-runnable with `tools/hsl_exe_decompile.py 0x4348f0`). Reading in call order:

1. `0x42caa0(code)` — the slot must be enabled.
2. `job_up = *(record + 0x60)` with `record = [0x4c1bc8] + (code + 1) · 0x1fc`. **`job_up == 0` returns before anything else** — no exchange, no refresh, no receipt.
3. `desc = 0x45dbe1(job_up)` = `*(0x4a2728 + job_up · 4)`, the parsed object descriptor of object code `job_up`; a null descriptor also returns.
4. `0x42c700(code, job_up)` writes `job_up` into the slot's object-code table (`0x4c4360[code]`), so the next `defProcPlayerInstall` of that slot constructs the up object.
5. `target = 0x4c1afc + *(desc + 0xa4) · 0x1fc` — the PLAYERS row indexed by the descriptor's `+0xa4`, i.e. `obj_Data7` (「Extra Data Table ID」; the same 4-byte stride that puts `obj_Data8` at `+0xa8` and `obj_Data9` at `+0xac` in [原安装分支](original_player_install.md)).
6. Field copy from `target` into `record` — exactly the list of [原城镇转职](original_town_job_up.md#exchange-helper-0x4348f0code-flag) (`+0x8..+0x14` sounds when non-zero, `+0x18/+0x1c` job/title, `+0x20/+0x22`, `+0x2c/+0x5c/+0x60` shape/face/job_up, `+0xa0`, `+0xec` weapon when non-zero, `+0x118..+0x128` resists capped 80, `+0x130` move capped 12, `+0x194..+0x1b4` additive layer, `+0x134 |= flag`); then `0x448840(record)`.

### resource-derived：level 37 的目标是 PLAYERS 017 行，不是 052

`resource-derived` chain for the registered 咕嚕 (slot 7, PLAYERS row 008):

| hop | value | source |
| --- | --- | --- |
| `record + 0x60` of a never-transformed 咕嚕 | `job_up_code = obj_Player8Up1` | `PLAYERS.TXT` row `code = 8` |
| `obj_Player8Up1` | `816` | `OBJ-ALL.H` (`obj_Player1Up1..9Up1` = 809..817, `1Up2/2Up2` = 818/819) |
| object 816 | `Player8_Up1`, `obj_Data7 = 17`, `SHAPE\017-00001.SHP`, `SID_PLAYER16`, `defProcPlayer` | `global.obs` |
| level override | none — `obj-037.obs` declares no object 816 (its codes are 3–14 party installs, 96 Enemy052, 180–188 conditional installs, 17/18/19/90/97/98/99 story objects) | `@:\data\obj-037.obs` (seed `sources.objects`) |
| `*(desc + 0xa4)` → PLAYERS row | **017** (`jobEvilMonster` 邪獸, `name_7` 咕嚕, `FACE0007`, `job_up_code = 0`, `sound_walk FLY002`, `attack ATTACK20`, `dead DEAD0003`, weapon 53) | `PLAYERS.TXT` row `code = 17` |

So `actPlayerJobUpProcess SID_咕嚕 0` in WINFAIL037 turns 咕嚕 into the **same 017 row the town chain names** (`JobUpRules.TOWN_TARGETS["008"] = "017"`); the `0x80000000` flag is the first-tier flag both callers write. The `actInsertStoryObjectRandomPos obj_Story_Player8` that follows re-installs slot 7, whose object code is now 816: the constructor `0x407ec0` draws the 017 shape. Row 052 (`jobWindWarrior`, name 306「???」, `FACE0052`) is the guardian 謎之生命體 the party fights and `actDeleteObject SID_ENEMY052` removes; it is not a job-up target. WINFAIL037 messages 2125/2126 (「這....這..........是咕嚕嗎？」「咕嚕和那怪物..............合體了？」) are consistent with the member keeping his name on a new form — a consistency check, not the basis.

The 052 walk / cut-in imports serve the guardian's own presentation.

### static-derived：转职后的 HP／MP

Neither function on the path writes the record's current or maximum HP/MP (`+0xd8/+0xdc/+0xe0/+0xe4`, offsets per [原成长刷新](original_growth_refresh.md)):

- `0x4348f0` writes only the offsets listed above.
- `0x407ec0` (player constructor reached by the re-install of `obj_Story_Player8`): for object kind 3 it re-reads the slot, falls to the fresh template copy `0x44cb10(slot, 1)` only when the live working attributes `+0x4c..+0x58` are all zero (a never-initialised record), **deletes the object and returns when `+0xd8 < 1`** (a dead member is not re-installed), otherwise touches only the object's own transient fields (`+0x14`, `+0x1b6`, `+0x4`, `+0x1c`, `+0x28`, `+0x134` from insert parameters) and ends with `0x448840(record)`.
- `0x448840` clamps a current value downward to the new maximum and never refills ([原成长刷新](original_growth_refresh.md), probe-verified).

The remake keeps the member's current HP/MP through the shared refresh's clamp (`WinfailActions._apply_player_job_up`). A member already defeated stays defeated (the exchange still records; the re-install is refused natively).

### negative-evidence：行 `job_up_code = 0` 的成员

`negative-evidence` for the scenario itself: TOWNDEF's `teCheckJobUp` entries name 雷歐納德／緹娜／琥／漢克斯／雪拉／雷特／嚎／克羅蒂 and `teCheckJobUp2` 雷歐納德／緹娜 — **no `SID_咕嚕`**, so a 咕嚕 already standing on 017 cannot reach level 37 in the original; the only path onto 017 is this token. If a carry nevertheless holds such a member (dev fixture), `0x4348f0` returns at step 2 (017 declares `job_up_code = 0`): the remake mirrors that as a no-op receipt `job_up_code_zero_noop` in `job_up_changes` — no stacking, no `unsupported_encountered`.

### resource-derived：咕嚕的条件安装

`resource-derived`: EVEF record 10 of level 37 is object 187 「咕嚕(有才產生)」, `defProcPlayerInstall` with `obj_Data8 = 1` (conditional install), `obj_Data9 = 7` (registered slot 7) at placement (384, 1312); STORY037 then walks `SID_咕嚕` by (0, −192). The conditional branch of `defProcPlayerInstall` (`0x4080b0`: only an existing, enabled registered slot reaches the constructor) is the static-derived basis in [原安装分支](original_player_install.md). The remake fields the slot `install_if_carried` (`ConditionalPartyRules`), the same reading as the encounter slots and the other 27 formal battles carrying such records.

## 重制接线

白光：`StoryEffectObjects.effect_kind` 对 `defProcObjectMove`、BALL001、无 `obj_Mode` 且符号与 `obj_Data7` 都和轨迹一致的剧情对象返回 `objcomd_track`，每次插入建一个 `TrackSprite`，第 n tick 取轨迹第 n 帧的缩放、加色与 `level/16` 权重，轨迹结束自删；STORY037 的五个随机槽插入经 `random_slot_event` 解析槽位后走同一路径。WINFAIL037 事件 48 的两次 `actInsertStoryObjectRandomPos obj_Story_Level_WhiteLight2` 及其前面的 `actSetPlayerPosToRandom0` 在过场里仍被画出（`BattleOpeningCoordinator._drawn_despite_rules`：白光不生单位，规则层已记录插入）。同符号同程序的其他关（22、28、59、76、77 的 `obj_Story_Level_WhiteLight`）走同一轨迹；79 关白光换了形状、80 关程序是 13，不套用。

The remake assembles `scenario_rules.job_up_targets: {"008": "017"}` with the generated 017 template in `scenario_rules.job_up_templates` (`hsltools.levels.battle` LEVELS[37]), and both callers run through `JobUpRules.merge_source_template`: the stable unit id, party role, `actor_id`, level, experience and attributes stay; the target's job code, caps, additive PLAYERS layer, capped resists／move point and declared weapon 53 merge in; `job_up_flags |= 0x80000000`, `job_up_target_actor_id = "017"` and a `job_up_history` step are recorded; the shared `ProgressionRules` refresh (0x448840) then derives the 017 form. Only the cinematic departure request for that same registered player is removed. Missing target data is an explicit `unsupported_encountered` reason.

### 来源头备注

`game/` 模块 `## provenance:` 头里的长备注（头里只留 `tag path`，每条来源项不超过 200 字符）。每行是「模块 维度：原备注」。

- `game/sim/loop/BattleLoopAI.gd` rules：an undeclared unit whose side meets every living unit — the level-37 gems — has nothing the 0x40bb80 scan can pick

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`；白光轨迹 `uv run --with unicorn==2.1.4 --with pillow python tools/hsl.py generate objcomd_motion`（需本机 EXE 与 hsl.pak）；`0x4348f0` 反编译 `tools/hsl_exe_decompile.py 0x4348f0`（需本机 EXE）。

## 边界

- The exact native field-to-domain mapping for every copied offset, the global actor registration side effects, frame-set timing, and the original RNG/scheduler are not reconstructed. Those boundaries are `provisional`; the implementation relies on the reviewed PLAYERS templates, the existing single PlayLoop state owner, and focused runtime assertions.
- The vitals reading above is a static read of `0x4348f0`, a bounded read of `0x407ec0` and the probe-verified `0x448840`; no native run of the whole WINFAIL037 event has been observed. Replacement evidence for the remaining doubt: a bounded native probe executing `0x4348f0` then `0x407ec0` on a slot with reduced HP.
- `job_up_targets` maps only the base row 008 to 017 — the only row 0x4348f0 can reach from a registered 咕嚕; the 017 → 0 chain end is handled as the native no-op.
- The conditional install is read as 「carried ⇒ installed」; a registered-but-disabled slot is unreachable in the original (no writer sets the `0x80000000` bit, [player install](original_player_install.md)). A launch without a campaign hand-off fields every slot (dev／sweep), so the registered sweep roster of level 37 now includes 咕嚕.
- `actInsertStoryObjectRandomPos obj_Story_Player8` after the job-up is the cinematic re-insert of the same registered player: the interpreter keeps the unit (the preceding `actDeleteObject SID_咕嚕` departure is withdrawn) and records the insert as unresolved (`obj_Story_Player8` is not a `script_objects` row).
- 白光轨迹以探针原点为创建点、镜头在 (0,0)；对象不移动也不等出屏，落点不影响轨迹。`engMIX｜engADDCOLOR` 按 `level/16` 乘源再加色读（同 [绝技对象](original_objcomd_programs.md)），合成器逐像素公式未在本包核对（provisional）。
- 其他关的白光只在符号、形状、程序与 37 关模板一致时套用该轨迹；各关 obs 模板的其余字段未逐关比对（provisional）。

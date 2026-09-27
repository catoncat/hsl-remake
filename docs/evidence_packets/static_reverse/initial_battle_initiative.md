# Initial battle initiative

> evidence: static-derived; runtime-measured: 第一战模拟器样本的注册槽与队列（original_enemy_turn §7），51／52／505 关队列追踪（待机、轮中改速度、阵亡、中途插入、回合计数） · status: live · functions: 0x407260, 0x407340, 0x4074a0, 0x407510, 0x407540, 0x407660, 0x407720, 0x407990, 0x407ab0, 0x407b70, 0x407cc0, 0x408370, 0x40b910, 0x40e2b0, 0x40e3b0, 0x40e430, 0x40e800, 0x40e870, 0x439f80, 0x448420, 0x458c80 · tools: hsltools/checks/registration_order.py, hsltools/data/first_battle_formation.py, hsltools/probes/_turn_queue_trace.py, run_level7_runtime_tests.gd, run_tests.gd · updated: 2026-09-26

The current remake previously selected Leonard immediately after STORY051. That skipped any faster actors at the head of the battle queue. The normal handoff now calls `BattlePlayLoop.begin_battle`, plays queued NPC actions through the existing stepped AI presentation, and opens the menu only when a player-controlled actor is current. No additional battle state is created.

## Source and static chain

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

- `0x448a3f..0x448a51` initializes live speed `+0xb8` from the template's speed field `+0x1b0`.
- The job switch at `0x448a5d` uses TYPE.H job values minus 80. SwordMan (80) starts at `0x448a64`, Magician (90) at `0x449e9c`, BeastWarrior (94) at `0x44a74e`.
- SwordMan's shared tail reads working dex `+0x50` at `0x449014`, multiplies it by 90 at `0x44901f..0x44902b`, and jumps to the signed divide-by-100 sequence at `0x44b152`.
- Magician's tail (`0x44a2c2..0x44a2e0`, reached via `0x449ff3 → 0x44a172`) computes dex × 94 before division at `0x44b5a8`.
- BeastWarrior's tail (`0x44ab73..0x44ab7f`, reached via `0x44a8a1 → 0x44a9f4`) computes dex × 60 before that division.
- `0x44b5b9` adds the integer job contribution to live speed. Six equipment slots call `0x448420` from `0x44b5de..0x44b627`.
- Equipment type 5 (`itemTypeFoot` in TYPE.H) adds its attack_damage field at `0x44865f..0x448672`; all equipment additionally adds `add_speed` at `0x4486cc..0x4486d7`.
- `0x407340` builds the queue from the registration array `0x4c34c0` and stably sorts descending by live speed. Comparisons at `0x4073e5..0x4073ec` and `0x407433..0x40743a` do not swap equals.

Resource-derived, unadjusted level-one values:

| Actor | Dex | Job contribution | Equipment speed | Result |
| --- | --- | --- | --- | --- |
| 001 | 16 | 14 | boots 181 +2, weapon 2 -2 | 14 |
| 021 | 15 | 13 | boots 181 +2 | 15 |
| 023 | 14 | 12 | boots 181 +2 | 14 |
| 024 | 12 | 7 | boots 182 +5 | 12 |
| 026 | 12 | 11 | 0 | 11 |

`tools/hsltools/data/first_battle_formation.py` now derives these baseline speeds from tracked PLAYERS/ITEM tables. The scenario file keeps these level-1 values; the live roster applies the native opening level-up (`0x40e870`) at creation through `InitialRosterGrowthRules` (see [original_auto_growth](original_auto_growth.md)).

## Registration order is not simply EVEF order

`0x407660` uses reserved player slots for identities below 20. NPC registration starts in the later array slots (`0x407681..0x4076e1`). Thus stable speed sorting does not imply that every NPC placed before Leonard in EVEF wins a speed tie. The cursor is reset to slot 20 at `0x407287` and `0x407340` collects the array from slot 0 (`0x407365..0x407390`) before its stable sort, so equal speeds put registered players first (by slot = PLAYERS code − 1), then NPCs in creation order. **2026-09-25 (lane R7-NPC):** the queue follows this order again (`CoreTurnQueue.registration_slot`), replacing the interim EVEF-order remake choice; the user's first-battle recording confirms it (speed-14 023_1 acts after speed-14 Leonard). See [first_control_formation_order.md](first_control_formation_order.md).

**Every battlefield, and runtime inserts (2026-09-25, lane SLOTORDER).** Static-derived from the local hsl01.exe disassembly:

- *Who registers, and when.* `0x407660` is reached only from `0x407cc0`, which copies `+0xa0` (the obj_Data6 SID token: `SID_PLAYERn` = n, `SID_ENEMYxxx` ≥ 21) into `+0xa2`; `0x407cc0` runs on an actor's first process tick, from the enemy process init `0x43eef6` (gated only by init flag `0x20000000`, so static `defProcEnemy` objects such as the Enemy101 hulls register too) and the player process init `0x44343e`. Objects tick plane by plane in list order (`0x45f5f7`) and a created object is appended to its plane list tail (`0x45e307`), so registration order is creation order within a plane. Every EVEF actor template and every scripted actor insert is `planeObject1` (one level-51 exception: the transient `obj_Story_Level51_Object1`, inserted alone and deleted in the same chain).
- *Cursor.* `0x407260` sets the cursor `0x4c1a3c` to 20 (store at `0x407287`); its only caller is the level load `0x42da60` (call at `0x42da92`), i.e. once per battle. Unregister `0x407720` clears a slot without moving the cursor. A registration takes the cursor, increments it, wraps it to 0 at 200 (`0x4076b1..0x4076bf`) and then scans upward for the first free slot (`0x4076c4..0x4076e1`). The skip at `[0x4c1b94]+20 ≥ 200` counts live enemy-side actors (inc `0x40770c` and `0x4079c5`, dec `0x4077f8`, reset `0x40729f`).
- *Save and load.* The general save routine (the call at `0x42e46f`, beside the other subsystem writers) calls `0x4079f0`, which stores the cursor `0x4c1a3c`, the queue index `0x4c6e48` and the compressed queue table `0x4c3940`; the matching reader `0x407ab0` (called at `0x42ea52`) reads them back through `0x46cab0`, which clamps the length to what is left in the file (the writer's `0x46c9d0` instead grows the recorded size). A restored actor re-enters the array at its own saved slot: the process inits `0x43ee0f` (enemy) and `0x44335f` (player) call `0x407b70`, whose `0x407990` (at `0x407c2a`) writes `[+0xa0]` directly without touching the cursor. So wherever the original saves, a load keeps the slots and continues numbering new inserts from the saved cursor. Not traced: whether that save is reachable mid-battle (`BattleCheckpoint` records the original as having no in-battle save) and whether anything between the read and play resumption calls the level load `0x42da60` again (its only caller is `0x42f7dd`). The remake's `BattleCheckpoint.state` stores `units` and `turn_queue` as they are, so its own save cannot reorder them.
- *Consequence.* NPC slots rise in creation order — EVEF record order, then STORY inserts in script order, then WINFAIL inserts in firing／action order — until the 181st NPC registration of one battle wraps the cursor; from then on a new actor takes the lowest freed slot (possibly a vacant player slot 0..19). The remake's roster is written in exactly that creation order (assembler `trace_opening`; runtime inserts append in `ScriptActorCreationRules._install`), so "append to the roster" equals "next slot" below the wrap.
- *Emulator corroboration (runtime-measured by lane ORACLE, [original_enemy_turn](original_enemy_turn.md) §7):* the first-battle sample reads slots 021_1 s20 … 024_2 s30 in EVEF record order (4, 5, 7, 9, 10, 11, 12, 17, 18, 21, 22) and Leonard s0.

`python3 tools/hsl.py check registration_order` (tools/hsltools/checks/registration_order.py, in the gate) recomputes this for all 139 scenarios: 128 original-derived rosters compared (battle_200 is authored; 10 development trials have no original order), 0 class／slot／order mismatches, 4543 equal-speed NPC pairs and 596 equal-speed player／NPC pairs whose order it covers. Written NPC registrations (EVEF actors incl. static objects + every STORY／WINFAIL actor insert once) peak at 117 (level 12), below the wrap at 181. Only refill events (WINFAIL sections on an arming cycle, or armed from one) can go further: levels 10, 12, 37, 51, 53 and 902, the tightest 902 after 21 refill cycles (8 actors per cycle). Post-wrap slot reuse is **not modelled** (the remake keeps appending); it can only matter after that much farming. `--table` prints the per-scenario rows; `--pak` re-surveys the EVEF actor planes from the original hsl.pak. Real pairs are pinned in `run_tests.gd` (level 51 Leonard 5／023_1 6／023_2 7; level 6 EVEF 023_7 directly before STORY-inserted guards 1..3) and `run_level7_runtime_tests.gd` (WINFAIL007's inserted 024 captains after equal-speed EVEF 038_6).

The examined actor EVEF records have zero words after their basic object code and X/Y fields; no hidden path was found in those records. STORY051 has Leonard's direct displacement, not an explicit displacement for each NPC.

## Verification and limits

A dedicated test starts from the actual initial queue: five baseline Enemy021 turns precede Leonard, the queue stays in round one, and real NPC positions advance. Player selection cannot steal an NPC turn. Existing command/combat tests now explicitly start their fixture at the player's queue slot; they no longer assert that Leonard is naturally the fastest actor.

Normal opening tests check the NPC handoff before player interaction. The dev first-control harness resolves this same prefix without its animations. Actual Godot menu/overlay rendering was inspected after the prefix.

This does not recover the original NPC AI paths, targeting, initialization-level adjustments or full first-control formation. The curated original frames also show allied swordsmen advancing, which the unadjusted template speeds do not explain yet. Do not hardcode those observed destinations as a replacement for recovering their actions.

Implementation reuses the existing queue, AI step and movement presentation. No credible extra state layer remained to remove in this bounded change; the test-only player-turn fixture is required to keep command tests independent of the opening phase.

## NPC adjustment continuation: attribute growth also changes speed

Static-derived on the same EXE hash:

- Parser `0x44ca64..0x44cab0` packs `level_adjust_range` in the upper word (`+0x1fa`) and `level_adjust_disp_range` in the lower word (`+0x1f8`). The initializer passes those to `0x40e870` in range, dispersion order.
- `0x40e800` recomputes level from the four base attributes (`+0x64..+0x70`): `1 + ceil(max(0, sum - 52) / 5)`. All five first-battle templates sum to 52, hence level one.
- `0x40e870` bypasses adjustment for object process 3. Otherwise it clamps registered player average level to the template range and samples a target around it. The dispersion-zero case still enforces an upper endpoint above the lower one; it must not be translated as automatically no adjustment.
- `0x40ea62..0x40ea8a` adds `floor((rand(20)+20) * level_delta / 100)` to base speed. This is **not the only speed-affecting change**.
- `0x40eb07..0x40eb10` then calls `0x439f80` with `5 * level_delta`. That routine allocates attribute points, including base dex at `0x43a07a..0x43a093`, and calls stat refresh again. Therefore an argument that friendly 023 must stay at speed 14 because the direct speed bonus rounds to zero is invalid.
- `0x458c80` returns a value in `[0,n)` (zero for n=0); initialization consumes several other random draws before attribute allocation. Current implementation does not reproduce this initialization RNG sequence or complete attribute limits.

This narrows the next work to the native level/attribute initialization and its live outcome; it does not prove a fixed first-control formation or justify manually moving allied soldiers.

## Remove mixed test attributes from the live baseline

The formation importer now updates combat `str` and `dex` from the same PLAYERS templates used for baseline speed. These are the native base-to-working copy inputs (`+0x64 → +0x4c`, `+0x68 → +0x50`, recorded in `core_logic.stat_refresh`). Current equipped items have no str/dex additions. Leonard now uses 16/16; 021 uses 15/15, 023 15/14, 024 15/12 and 026 10/12. This removes test placeholder attributes from hit/damage comparisons without claiming that template values reproduce adjusted NPCs. Existing attack/defense/HP values remain provisional and are preserved.

The generator checks these consumed combat fields directly. It merges just the recovered attributes into existing profiles, so unrelated combat values are not discarded. No new runtime rule layer, random seed or snapshot is introduced; this mechanical data correction has no meaningful executable ablation candidate.

## 轮次语义：待机、轮中改速度、阵亡、中途插入、回合计数

lane TURNQ（2026-09-26），同一 EXE 哈希。先静态读下表，再用 `tools/hsltools/probes/_turn_queue_trace.py` 在模拟器里逐事件记原版队列。这个探针是挂在 `_enemy_level.run_level` 上的观察器：玩家回合从 `+0x8c=0x10000` 回合结束态起跑，不经待機菜单输入；下文 f 是该次运行的驱动帧。

队列表 `0x4c3940` 每项 12 字节，依次是对象、注册槽、本轮可用标志（`+8`）。下标在 `0x4c6e48`，回合计数在 `0x4c1bbc`。

| 地址 | 读法（static-derived） |
| --- | --- |
| `0x4074a0(arg)` | arg 为 0 时直接返回（`0x4074ac` → `0x4074f8`），不走。否则从下标 +1 往后找对象非 0 且标志非 0 的项；到表尾没找到，就把下标置 −1 从头再找一遍；两遍都没有，才由 `0x4074ec` 调 `0x407340` 重建，再由 `0x4074f1` 执行 `inc word [0x4c1bbc]`。找到则写下标（`0x4074fd`），并把该项标志清 0（`0x407504`）。本函数不排序 |
| `0x407340` | 清表，按注册槽 0..199 收集，再按活记录 `+0xb8` 稳定降序排序；下标置 0，首项标志清 0（`0x407477`／`0x407487`），所以首项在重建时就已被选中。调用点只有两处：`0x4074ec`（换轮）和 `0x40827f`（剧情转入战斗，只调一次） |
| `0x407510` | `0x407511` 先把 `[0x4c1ba0]` 存进 esi，再依次调完成扫描 `0x408370`、调 `0x44f4e0`、`inc word [0x4c1ad4]`，最后调 `0x4074a0(esi)` |
| 回合结束序列 | 玩家状态 `0x10000` 经 `0x443a70` 分派：`0x443a96` 调 `0x40e2b0`（中毒）→ `0x443ba2` 调 `0x40e3b0`（返回 0 时跳过回复，直达 `0x443c01`）→ `0x443bce` 调 `0x40e430`（HP／MP 回复）→ `0x443c1a` 调 `0x40b910`（状态计时）→ `0x443c22` 调 `0x407510`。AI 顺序相同：`0x441f12`、`0x44202e`、`0x442053`、`0x4420ad`、`0x4420b5` |
| `0x407720(obj)` | 清注册槽 `0x4c34c0`（`0x40773a`／`0x407786`），把队列项三字写 0（`0x407767`／`0x4077ae`）：留下空洞，不压缩，也不改下标。随后 `0x4077bb` 调 `0x407540` 取当前项，当前项为 0 或等于 obj 时，`0x4077ca` 调 `0x4074a0(1)` |
| `0x407720` 的调用点 | 共五处：`0x43f198`（AI 阵亡）、`0x4436a6`（玩家阵亡）、`0x4506d8`／`0x4542e7`／`0x453cbf`（脚本离场）。写法相同：先存 `cur = 0x407540()`，调 `0x407720` 与 `0x44cb90`，之后只有 `cur == obj` 时才再调 `0x407510`（`0x43f1b0`、`0x4436c8`、`0x4506f1`、`0x4542ff`） |
| `0x407cc0` → `0x407660` | 对象首个过程 tick 时注册，只写注册槽和游标 `0x4c1a3c`，不碰队列表 |

runtime-measured：

| 实验 | 参数 | 原版读数 |
| --- | --- | --- |
| E1 待机 | `--level 51 --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json --board-key r1 --turns 2` | 第 1 轮 12 项各被选中一次。雷歐納德在 f1266 被选中（下标 6）；f1278 调 `0x40e2b0`；f1280 依次走 `0x40e3b0` → `0x40b910` → `0x407510` → `0x408370`，同帧选中下标 7（023_1）。此后他不在任何待选列表里，直到 f1562 换轮重建。本轮 11 名 NPC 都待机，同样各只被选中一次 |
| E5 wait_round | `--level 52 --seed 1 --turns 3` | 带 wait_round 的 NPC 每轮照样占自己的队列位，照常被选中和交接；倒数在它自己的行动里减 1。皇帝交接时 `+0x1b8` 依次为 7、6、5（f2260／f3196／f6099）；021_1 依次为 1、0，第 3 轮起行动 |
| E2 轮中改速度 | E1 加 `--poke 1:026_2:30 --poke 1:021_1:1`（在 f920、021_3 交接后改） | 第 1 轮顺序不变：021_1 仍在下标 2 行动（f992 选中，f1064 交接），026_2 仍最后行动（f1562）。f1562 重建后 026_2 排首（30），021_1 排末（1） |
| E3a 非当前者阵亡 | E1 加 `--kill 2:021_2 --kill 6:024_2` | f992 021_1 刚被选中时注销 021_2：下标 3 变成空洞，下标仍是 2，下一次从 2 选到 4。f1200 雷歐納德刚被选中时注销 024_2：下一次从 7 选到 9。其余单位照常行动；f1439 重建出 10 项的紧凑表。另见 E1：f4333 024_1 攻击杀死已行动过的 021_4，当前者仍是 024_1；f4403 024_1 交接后，026_1、026_2 照常行动 |
| E3b 当前者阵亡 | `--level 505 --seed 1 --turns 2` | 036_4（下标 12）攻击时被反击打死。f1070 注销 036_4，当前项已空，内层 `0x4074a0(1)` 选中 036_5（下标 13）；同帧 `0x407510` 交接时当前者是 036_5，它再走一步到表尾，`0x407340` 重建，回合 1→2。036_4 与 036_5 都没有走 `0x40e2b0`／`0x40b910` |
| E3c 同上，死者之后还有人 | E3b 加 `--set claudie.speed=1`（克勞蒂排到表尾） | f1068 注销 036_4（下标 11）→ 选中 036_5（12）→ 同帧交接 → 选中克勞蒂（13）。克勞蒂在 f1070 走 `0x40e2b0`，f1072 走 `0x40b910` 并交接，然后换轮。只有紧随其后的一名失去行动，与关卡脚本无关 |
| E4 中途插入 | E1 加 `--kill 1:021_4 --kill 2:021_5 --kill 3:021_3` | 021 少于 3 名，触发 WINFAIL051 事件 0。新 021 在 f1133（雷歐納德回合中）经 `0x407660` 注册，取游标槽 31：空出的 23／24／26 不复用，对象沿用已释放的 021_4 地址。它在第 1 轮从未被选中；f1465 重建时按速度 15、槽 31 排在下标 3，位于 021_1（槽 20）、021_2（槽 22）之后 |
| E1 回合计数 | 同 E1 | 本轮最后一名 026_2：f1560 走 `0x40e2b0`；f1562 依次走 `0x40e3b0` → `0x40b910` → `0x407510` → `0x408370` → `0x4074a0` → `0x4074ec` 重建 → `0x4074f1` 计数 1→2 → 返回下标 0（021_3） |

结论：

1. **待机。** 被选中时标志就清 0（`0x407504`），回合结束时 `0x407510` 只往后走，所以已被选过的单位本轮不会再被选。玩家与 NPC 走同一条路径。唯一例外是 `0x4075a0`（ActiveAgain）把某项标志重新置 1，它会在第二遍扫描里被选中（见 [original_skill_function_bits](original_skill_function_bits.md)）。wait_round 只是 AI 在自己回合里的倒数，队列本身没有"延后"语义。
2. **轮中改速度。** 队列是开轮快照：`0x4074a0` 从不排序，`0x407340` 只在换轮（`0x4074ec`）和开战（`0x40827f`）时调用。轮中改动的 `+0xb8` 要到下一轮重建才生效。
3. **阵亡。** `0x407720` 留空洞不压缩，下标不变，扫描跳过空洞，排在后面的单位照常行动。死者若正是当前行动者，它的 `0x407720` 先走一步（`0x4074a0(1)`，把下一名活单位标成已用），随后的 `0x407510` 再走一步：紧随其后的那名活单位失去本轮行动；死者是本轮最后一名时，第一步就换轮，新一轮最快的那名失去第一次行动。这是规则，不是关卡脚本（E3c）。脚本离场用同一写法；但脚本链由 `0x453ac0` 启动时已把 `[0x4c1ba0]` 清 0，此时 `0x407510` 调的是 `0x4074a0(0)`，不走，所以只剩内层那一步，下一名照常成为当前行动者（static-derived，未实测）。
4. **中途插入。** 注册（`0x407660`）不碰队列表：新单位本轮不行动，下一次 `0x407340` 重建时按速度排入，同速按注册槽排。注册槽取游标递增，不复用空槽，直到本战第 181 次 NPC 注册使游标回绕。
5. **回合计数。** `0x4c1bbc` 在本轮最后一名的 `0x407510` 里 +1：排在它自己的中毒、回复、状态计时和完成扫描 `0x408370` 之后，紧跟在 `0x407340` 重建之后。没有"轮末回复"，回复是每名单位在自己回合末各做一次。所以本轮最后一次完成扫描读到的仍是旧计数。

未覆盖：`0x40e430` 没有被实测执行（51 关样本里没有带回复的单位，`0x40e3b0` 返回 0），它的顺序只来自静态读；单位在自己回合末中毒致死、`0x4075a0` 第二遍扫描、游标回绕后的空槽复用、待機菜单输入到状态 `0x10000` 这一段，以及脚本离场当前行动者，都没有实测。

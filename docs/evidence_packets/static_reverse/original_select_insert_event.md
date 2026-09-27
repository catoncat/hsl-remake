# actSelectInsertEvent Battle-Side Evidence

> evidence: static-derived: opcode shape; runtime-measured: remake presentation contract, level-900 inserted-event timing (unicorn, _enemy_level.py) · status: live · functions: 0x4082a6, 0x43f1df, 0x44ee20, 0x450840, 0x453a80, 0x453ac0, 0x454187 · updated: 2026-09-27

## Source

ACTION.H defines actSelectInsertEvent as opcode 79 with arguments `[id][serial][num][message id][event code]...`. The level-15 source call is:

`actSelectInsertEvent,SID_雷歐納德,1,2,1810,3,1811,4`

The script interpreter bridge is the already catalogued `0x450840`; no new native function identity is claimed by this slice. The existing STORY-side selection packet establishes the shared WINDOW50-style prompt and option message lookup.

## Remake Contract

`WinfailScenarioRules.select_event_status` appends the selected event code to the sole `event_statuses` loop, evaluates its `actTRUE` branch, and records the request. `BattleOpeningCoordinator` reuses its existing `select_options` prompt and splices the selected formal status timeline after the current token. Newly fired status entries are marked `presentation_inlined` so `BattleSceneRuntime` does not replay the same branch as a second cutscene.

For level 15, event 2 arms event 5 before the prompt. Selecting 1810 inserts event 3; selecting 1811 inserts event 4. Event 5 remains armed and is evaluated later by its source enemy-total condition. This preserves the source action order without creating a second battle-state dictionary.

## 所选事件的执行时机与走位落格（runtime-measured，lane VILLAGER900）

曼多力亞 · 對峙（LEVEL900）：STORY900 末句 `actSelectInsertEvent,SID_雷歐納德,1,2,1113,0,1114,1`，选项二（1114）插入 WINFAIL900 `[event] code = 1`，链内 `actWalk,SID_ENEMY062,1,576,1088,8`／`actWalk,SID_ENEMY062,2,640,1056,8`／`actWalkWait,SID_ENEMY062,3,640,1120,8`。

原版整映像机器（`_enemy_level.py` 进关，growth false，种子 (1,1)，选项 2），在第 1 回合队列排序 `0x407340` 的停点起挂钩与村民对象 `+4／+8` 写监视：

| 帧 | 事件 |
| --- | --- |
| 1286 | 停点：`[0x4c1d44]` = 1（case `0x4f` 插入时置位），三名村民在 [29,26]／[31,25]／[33,27]，`+0x8c` = 0 |
| 1286 | 排序后，剧情→战斗交接 `0x4082a6` 调扫描 `0x44ee20`（返回地址 `0x4082ab`）；事件扫描以 `0x453ac0(pc, 4, 0)` 启动 event 1 链（返回地址 `0x44ee17`）。此时队列当前是第一个行动者 027_1（索引 0），还没行动 |
| 1829–1862 | 链走到三条 actWalk：村民 `+0x8c` 依次 `0x320001` → `0x320006`（走） |
| 1832–1945 | 位置由 NPC 进程每帧写 `0x43f1df`（x）／`0x43f1e2`（y），调用链 `0x42dbfb` 帧循环 → `0x42d772` → 对象执行器 `0x45f657` → 进程 |
| 1905／1914／1945 | 到达：`0x442109` 调 `0x454187..0x4541b7` 把坐标对齐格子，`+0x8c` = `0x320007`，落在 [18,34]／[20,33]／[20,35]（像素 ÷ 32） |
| 2306 | 链结束 `0x453a80(4)`（返回地址 `0x453b66`，状态对象 `0x453b30`） |
| 2377 | 027_1 行动结束 `0x407510`，此后每次行动结束照常 `0x40751c` → `0x44ee20` |

结论：所选事件链不在剧情里跑，而是在第 1 回合排序之后、第一个行动者之前，由交接扫描启动的状态对象跑完；链里的 actWalk 由被点名对象自己的进程真的走过去，结束时坐标对齐到目标格。所以第 1 回合所有行动者看到的村民都已在新格；村民自己的第 1 回合行动从新格起、动作 wait。

## Limits

The native menu cursor, message-box layout, event-status scheduling boundary and exact handler call target beyond `0x450840` were not independently recovered here. The branch insertion and prompt behavior are a provisional remake contract verified by the focused `run_winfail_rules_tests.gd` branches.

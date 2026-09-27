# actSelectInsertEvent（战斗侧）：选项插入 winfail 事件与所选链的执行时机

> evidence: static-derived: opcode 形状; runtime-measured: 原版整镜像 LEVEL900 所选事件链时机与走位落格（unicorn）; provisional: 重制提示框与分支拼接 · status: live · functions: 0x4082a6, 0x43f1df, 0x44ee20, 0x450840, 0x453a80, 0x453ac0, 0x454187 · tools: hsltools/probes/_enemy_level.py, run_winfail_rules_tests.gd · updated: 2026-09-27

## 结论

- 原版 `actSelectInsertEvent`（opcode 79）按选项把指定 winfail 事件插入；所选事件链不在剧情里跑，而是在第 1 回合排序之后、第一个行动者之前，由剧情→战斗交接扫描启动的状态对象跑完，链里的 actWalk 由被点名对象自己的进程走到并对齐目标格（runtime-measured）。
- 重制 `WinfailScenarioRules.select_event_status` 把所选事件码追加到唯一的 `event_statuses`，`BattleOpeningCoordinator` 复用 `select_options` 提示并把所选状态时间线拼在当前 token 之后（provisional 表现合同）。
- 差异：原版菜单光标、消息框版式与事件调度边界本包未读（provisional）。

## 证据

### resource-derived

`ACTION.H`：actSelectInsertEvent = 79，参数 `[id][serial][num][message id][event code]...`。LEVEL015：`actSelectInsertEvent,SID_雷歐納德,1,2,1810,3,1811,4`（event 2 在提示前先挂上 event 5；选 1810 插 event 3，选 1811 插 event 4，event 5 之后按其敌数条件判定）。LEVEL900：STORY900 末句 `actSelectInsertEvent,SID_雷歐納德,1,2,1113,0,1114,1`，选项二（1114）插入 WINFAIL900 `[event] code = 1`，链内 `actWalk,SID_ENEMY062,1,576,1088,8`／`actWalk,SID_ENEMY062,2,640,1056,8`／`actWalkWait,SID_ENEMY062,3,640,1120,8`。

### runtime-measured：LEVEL900 所选事件链（原版整镜像）

`_enemy_level.py` 进关（growth false，种子 (1,1)，选项 2），自第 1 回合队列排序 `0x407340` 的停点起挂钩并监视村民对象 `+4／+8` 写：

| 帧 | 事件 |
| --- | --- |
| 1286 | 停点：`[0x4c1d44]` = 1（case `0x4f` 插入时置位），三名村民在 [29,26]／[31,25]／[33,27]，`+0x8c` = 0 |
| 1286 | 排序后，剧情→战斗交接 `0x4082a6` 调扫描 `0x44ee20`（返回 `0x4082ab`）；事件扫描以 `0x453ac0(pc, 4, 0)` 启动 event 1 链（返回 `0x44ee17`）；队列当前是第一个行动者 027_1（索引 0），尚未行动 |
| 1829–1862 | 链走到三条 actWalk：村民 `+0x8c` 依次 `0x320001` → `0x320006` |
| 1832–1945 | 位置由 NPC 进程每帧写 `0x43f1df`（x）／`0x43f1e2`（y），调用链 `0x42dbfb` → `0x42d772` → `0x45f657` → 进程 |
| 1905／1914／1945 | 到达：`0x442109` 调 `0x454187..0x4541b7` 对齐格子，`+0x8c` = `0x320007`，落在 [18,34]／[20,33]／[20,35] |
| 2306 | 链结束 `0x453a80(4)`（返回 `0x453b66`，状态对象 `0x453b30`） |
| 2377 | 027_1 行动结束 `0x407510`，此后每次行动结束照常 `0x40751c` → `0x44ee20` |

所以第 1 回合所有行动者看到的村民都已在新格；村民自己的第 1 回合行动从新格起、动作 wait。

## 重制接线

- `game/sim/WinfailScenarioRules.gd` `select_event_status`：追加事件码、求值其 `actTRUE` 分支并记录请求。
- `game/battle/runtime/BattleOpeningCoordinator.gd`：`select_options` 提示（WINDOW50 选项，与剧情侧共用）；新触发的状态标 `presentation_inlined`，`BattleSceneRuntime` 不再把同一分支作第二段过场重播。

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`（`_select_event_status_branches`）

## 边界

- 原版菜单光标、消息框版式、事件状态调度边界与 `0x450840` 之后的 handler 调用目标本包未读。
- LEVEL900 读数是一次种子、一个选项的整镜像运行。

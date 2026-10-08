# actSelectInsertEvent（战斗侧）：选项插入 winfail 事件与所选链的执行时机

> evidence: static-derived: opcode 形状、case 0x4f 选择窗参数与交回; runtime-measured: 原版整镜像 LEVEL900 所选事件链时机与走位落格（unicorn）; resource-derived: ACTION.H 参数与 LEVEL015 选项行; provisional: 分支拼接与键盘选行 · status: live · functions: 0x4082a6, 0x4264a0, 0x426680, 0x43f1df, 0x44e7b0, 0x44ee20, 0x44fad0, 0x450840, 0x451f2b, 0x45354e, 0x453a80, 0x453ac0, 0x454187, 0x454e20 · tools: hsltools/probes/_enemy_level.py, run_story_scene_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-28

## 结论

- 原版 `actSelectInsertEvent`（opcode 79）按选项把指定 winfail 事件插入；所选事件链不在剧情里跑，而是在第 1 回合排序之后、第一个行动者之前，由剧情→战斗交接扫描启动的状态对象跑完，链里的 actWalk 由被点名对象自己的进程走到并对齐目标格（runtime-measured）。
- 原版战斗侧选项窗与城镇 teSelect 是同一个对象 704 选择窗（`0x4264a0`，BOARD02 下槽、行距 28、脉冲绿悬停、ACCEPT01、16 tick 淡入淡出）：头像取 `[id][serial]` 对象的角色头像，找不到则居中；不开对白板、不加「離開」行；窗淡出后才把行号交回，VM 此时插入事件（static-derived）。
- 重制 `WinfailScenarioRules.select_event_status` 把所选事件码追加到唯一的 `event_statuses`；`OpeningSelectPrompt` 用与城镇共用的 `EventSelectWindow` 出窗，淡出后把所选状态时间线拼在当前 token 之后（窗 static-derived；拼接 provisional）。
- 差异：事件状态调度边界本包未读；键盘上下／回车选行是重制补的，原版行只读鼠标（provisional）。

## 证据

### static-derived：选项窗对象

`r2 pxw 4 @ 0x4537f4+79*4` → `0x451f2b`；该 case 在 `0x451fbb..0x451fca` 依次压入结果指针、`0x4c2940`（选项消息 id 表）、0、picture，调 `0x4264a0`。城镇 `0x454e20` case 0xf／0x1e 调的是同一函数同一参数形状，故战斗与城镇的选项窗是同一个对象 704。

### resource-derived

`ACTION.H`：actSelectInsertEvent = 79，参数 `[id][serial][num][message id][event code]...`。LEVEL015：`actSelectInsertEvent,SID_雷歐納德,1,2,1810,3,1811,4`（event 2 在提示前先挂上 event 5；选 1810 插 event 3，选 1811 插 event 4，event 5 之后按其敌数条件判定）。LEVEL900：STORY900 末句 `actSelectInsertEvent,SID_雷歐納德,1,2,1113,0,1114,1`，选项二（1114）插入 WINFAIL900 `[event] code = 1`，链内 `actWalk,SID_ENEMY062,1,576,1088,8`／`actWalk,SID_ENEMY062,2,640,1056,8`／`actWalkWait,SID_ENEMY062,3,640,1120,8`。

### static-derived：case 0x4f 选择窗参数与交回（r2 反汇编 `hsl01.exe`，未执行）

`hsl01.exe` sha256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。全 EXE 对 `0x4264a0` 的 call 只有三处：`0x451fca`（战斗 VM case 0x4f）与 `0x4556dd`／`0x45585a`（城镇 `0x454e20` case 0xf／0x1e）。

| 项 | 原版 | 地址 |
| --- | --- | --- |
| 进入 | 跳转表 `0x4537f4`＋79×4 → `0x451f2b`；状态 `+0x8c` 置 `0x4f << 16`（阶段 0） | `0x4537f4`、`0x451f2b` |
| picture | `[id][serial]` 经 `0x44fad0` 找对象；找到取 `[0x4c1bc8]` 角色表（行 508 字节）第 `对象+0xa4` 行 `+0x5c`，id 为 −1 或找不到为 0 | `0x451f34`–`0x451f73` |
| 选项 | `[num]` 对 (消息 id, 事件码) 写入 `0x4c2940`／`0x4c2900`，最多 10 对；不调消息框 | `0x451f73`–`0x451fb3` |
| 建窗 | 结果 `+0x9c` 置 −2，调 `0x4264a0(picture, 0, 0x4c2940, &+0x9c)`，与城镇同一调用形状；picture 为 0 时 `0x426680` 让窗居中（x 75），否则 x 144 | `0x451fb5`–`0x451fca`、`0x42685d` |
| 离开 | 不追加 RESOURCE 312「離開」（只有城镇 case 0x1e 在 `0x455831` 追加） | `0x451fb5` |
| 交回 | 阶段 1：结果为 −2 继续等（窗淡出 16 tick 后才写）；−1（窗无行）回主状态；否则 `0x44e7b0(0x4c2900[结果])` 插入事件、`[0x4c1d44]` 置 1、VM 继续 | `0x45354e`–`0x453599` |

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
- `game/common/EventSelectWindow.gd`：对象 704 选择窗，城镇与战斗共用（板、行位、悬停色、ACCEPT01、淡入淡出，版式见 [original_world_town](../runtime_observations/original_world_town/README.md)「select 选择窗」）。
- `game/battle/runtime/opening/OpeningSelectPrompt.gd`：关对白板，按 `[id][serial]` 绑定取头像（无则居中），无「離開」行；鼠标点行后窗淡出再交回；键盘上下／回车与脚本直调 `choose_select_option` 立即交回。`BattleOpeningCoordinator` 保存 `select_options`；所选状态标 `presentation_inlined`，`BattleSceneRuntime` 不再把同一分支作第二段过场重播；同一次结算里所选链之后重扫发出的状态（以及当场判定的胜负段）不标，按触发顺序各演一段过场，同原版（case 0x4f 与 actExecWinFailProcess 置的是同一个重扫旗 `0x4c1d44`，其后各次重扫启动的链都是普通链）。

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`（`_select_event_status_branches`）；选项窗调用 `r2 -q -c 'pxw 4 @ 0x4537f4+79*4; pd 40 @ 0x451f2b' hsl01.exe`；选择窗 `tools/godot.sh --headless --script res://tests/run_story_scene_tests.gd`（LEVEL900 两个选项）

## 边界

- 事件状态调度边界与 `0x450840` 之后的 handler 调用目标本包未读。
- 选择窗只有静态读数，无原版战斗侧实拍帧；角色表 `[0x4c1bc8]` `+0x5c` 按用法当头像读，未逐项核对敌方对象。
- LEVEL900 读数是一次种子、一个选项的整镜像运行。

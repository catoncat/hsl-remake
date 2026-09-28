# 开战先手与行动队列：速度、注册槽、轮次语义

> evidence: static-derived; runtime-measured: 第一战模拟器样本的注册槽与队列（original_enemy_turn「证据」），51／52／505 关队列追踪（待机、轮中改速度、阵亡、中途插入、回合计数） · status: live · functions: 0x407260, 0x407340, 0x4074a0, 0x407510, 0x407540, 0x407660, 0x407720, 0x407990, 0x407ab0, 0x407b70, 0x407cc0, 0x408370, 0x40b910, 0x40e2b0, 0x40e3b0, 0x40e430, 0x40e800, 0x40e870, 0x439f80, 0x448420, 0x458c80 · tools: hsltools/checks/registration_order.py, hsltools/data/first_battle_formation.py, hsltools/probes/_turn_queue_trace.py, run_tests.gd · updated: 2026-09-28

## 结论

- 原版：live 速度 = 模板速度 + 职业 dex 贡献 + 装备；`0x407340` 从注册数组 `0x4c34c0` 槽 0 起收集后稳定降序排序，同速时登记玩家（槽 = PLAYERS 编号 −1）先于 NPC，NPC 按创建顺序（槽 20 起）（static-derived；模拟器实测第一战槽号印证）。
- 队列是开轮快照：选中即清 ready，轮中改速度下一轮生效；阵亡留空洞不压缩，当前行动者阵亡会让紧随其后的一名失去当轮行动；中途插入当轮不行动；回合计数在当轮最后一名的交接里、重建之后 +1（static-derived；51／52／505 关模拟器逐事件实测）。
- 重制：`BattlePlayLoop.begin_battle` 从真实队列首项开始，NPC 前缀走正常 AI 演出后才开玩家菜单；`CoreTurnQueue.rebuild` 按 `registration_slot` 排序；`registration_order` 对 128 个原版名单 0 失配（static-derived 规则；门禁检查）。
- 差异：当前行动者阵亡时的连走两步由 `BattlePlayLoop._step_past_dead_actor` 照原版复现（见 [original_death_disposal.md](original_death_disposal.md)）；游标回绕（本战第 181 次 NPC 注册）后的空槽复用未建模；开战出生（张延迟、携带、调级）按创建顺序在全局流抽（`InitialRosterGrowthRules`，见 [original_script_entry.md](original_script_entry.md)「结论」），种子与原版不同，玩家之间与 NPC 之间的创建次序是重制读法（provisional）。

## 证据

**static-derived：速度**（原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

| 锚点 | 结论 |
| --- | --- |
| `0x448a3f..0x448a51` | live +0xb8 = 模板 +0x1b0 |
| `0x448a5d` 职业跳转（值 −80） | SwordMan `0x448a64`：dex(+0x50)×90（`0x449014..0x44902b`）；Magician `0x449e9c`：×94（`0x44a2c2..0x44a2e0`）；BeastWarrior `0x44a74e`：×60（`0x44ab73..0x44ab7f`）；再有符号 /100（`0x44b152`／`0x44b5a8`） |
| `0x44b5b9`、`0x44b5de..0x44b627` | 加职业贡献；六装备槽调 `0x448420` |
| `0x44865f..0x448672`、`0x4486cc..0x4486d7` | Foot（type 5）加 attack_damage 字段；全部装备加 `add_speed` |
| `0x4073e5..0x4073ec`、`0x407433..0x40743a` | 相等不交换（稳定） |
| `0x40e800` | 等级 = `1 + ceil(max(0, 四基础属性和 − 52)/5)` |
| `0x44ca64..0x44cab0`、`0x40e870` | `level_adjust_range`（+0x1fa）与 `level_adjust_disp_range`（+0x1f8）传入开战调级；过程 3 跳过 |
| `0x40ea62..0x40ea8a`、`0x40eb07..0x40eb10` | 速度直加 `floor((rand(20)+20)×Δlv/100)`，再以 `5×Δlv` 调 `0x439f80` 分配属性（含 dex `0x43a07a..0x43a093`）并重刷 |

resource-derived，未调级 1 级值（`first_battle_formation.py` 从 PLAYERS／ITEM 生成）：

| 角色 | Dex | 职业 | 装备速度 | 结果 |
| --- | --- | --- | --- | --- |
| 001 | 16 | 14 | 靴 181 +2，武器 2 −2 | 14 |
| 021 | 15 | 13 | 靴 181 +2 | 15 |
| 023 | 14 | 12 | 靴 181 +2 | 14 |
| 024 | 12 | 7 | 靴 182 +5 | 12 |
| 026 | 12 | 11 | 0 | 11 |

str／dex 来自同一模板（+0x64→+0x4c，+0x68→+0x50）：001 16/16，021 15/15，023 15/14，024 15/12，026 10/12。第一战 EVEF 记录 17／18 为 023，20 为雷歐納德（保留槽 0），21／22 为 024；EVEF 演员记录在代码与 X/Y 之后无隐藏路径字。

**static-derived：注册**

| 锚点 | 结论 |
| --- | --- |
| `0x407cc0`→`0x407660` | 首个过程 tick 时把 +0xa0（SID token）复制到 +0xa2 并注册；敌方 `0x43eef6`、玩家 `0x44343e`；<20 用保留槽 |
| `0x45f5f7`、`0x45e307` | 按平面列表顺序 tick、新对象追加到表尾：同平面内注册顺序 = 创建顺序 |
| `0x407260`（写 `0x407287`，调用 `0x42da92`） | 每战一次把游标 `0x4c1a3c` 置 20 |
| `0x4076b1..0x4076e1` | 取游标后递增，200 回绕到 0，向上找首个空槽；`0x407720` 注销不动游标 |
| `0x4079f0`／`0x407ab0`（`0x42e46f`／`0x42ea52`） | 存档保存游标、下标、队列表；读档经 `0x407b70`→`0x407990`（`0x407c2a`）按原槽直接回填 |

**static-derived：轮次**（队列表 `0x4c3940` 每项 12 字节：对象、注册槽、ready）

| 锚点 | 结论 |
| --- | --- |
| `0x4074a0(arg)` | arg=0 直接返回；否则从下标 +1 找 ready 项，表尾后从头再找；都无才 `0x4074ec`→`0x407340` 重建并 `0x4074f1` 加 `0x4c1bbc`；选中写下标（`0x4074fd`）并清 ready（`0x407504`） |
| `0x407340` | 下标置 0、首项 ready 清 0（`0x407477`／`0x407487`）；调用点仅 `0x4074ec`（换轮）与 `0x40827f`（开战） |
| `0x407510` | 存 `[0x4c1ba0]`，调 `0x408370`、`0x44f4e0`，`inc [0x4c1ad4]`，再 `0x4074a0(esi)` |
| 回合末序列 | 玩家 `0x443a96` 中毒 `0x40e2b0` → `0x443ba2` `0x40e3b0` → `0x443bce` 回复 `0x40e430` → `0x443c1a` 状态 `0x40b910` → `0x443c22` `0x407510`；AI 同序 `0x441f12`／`0x44202e`／`0x442053`／`0x4420ad`／`0x4420b5` |
| `0x407720(obj)` | 清注册槽与队列项（空洞，不压缩，不改下标）；当前项为 0 或等于 obj 时 `0x4077ca` 调 `0x4074a0(1)`；调用点 `0x43f198`、`0x4436a6`、`0x4506d8`／`0x4542e7`／`0x453cbf`，之后仅 `cur==obj` 时再 `0x407510` |
| `0x453ac0` | 脚本链启动时清 `[0x4c1ba0]`，脚本离场时 `0x407510` 调 `0x4074a0(0)` 不走 |

**runtime-measured**（原版模拟器；`hsltools/probes/_turn_queue_trace.py` 挂在 `_enemy_level.run_level`，f 为驱动帧）

| 实验 | 读数 |
| --- | --- |
| 第一战注册槽（[original_enemy_turn](original_enemy_turn.md)「证据」） | 雷歐納德 s0；021_1 s20、026_1 s21、021_2 s22、021_3 s23、021_4 s24、026_2 s25、021_5 s26、023_1 s27、023_2 s28、024_1 s29、024_2 s30（EVEF 记录 4／5／7／9／10／11／12／17／18／21／22） |
| 第一战录屏 | 速度 14 的 023_1 在速度 14 的雷歐納德之后行动（[battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)） |
| E1 待机（51 r1，2 轮） | 12 项各选中一次；雷歐納德 f1266 选中（下标 6），f1280 交接同帧选中下标 7；f1562 换轮 |
| E5 wait_round（52，3 轮） | 皇帝交接时 +0x1b8 依次 7、6、5；wait_round 单位照常占队列位 |
| E2 轮中改速度 | 026_2→30、021_1→1 后第 1 轮顺序不变；f1562 重建后 026_2 排首、021_1 排末 |
| E3a 非当前者阵亡 | 注销 021_2 后下标 2 直接选到 4；f1439 重建出 10 项紧凑表 |
| E3b／E3c 当前者阵亡（505） | 036_4 被反击打死：内层 `0x4074a0(1)` 选中 036_5，同帧交接再走一步，036_5 失去行动且未走 `0x40e2b0`／`0x40b910` |
| E4 中途插入 | WINFAIL051 新 021 f1133 注册取槽 31（不复用 23／24／26），第 1 轮不被选中，重建后速度 15、槽 31 排在下标 3 |
| 回合计数 | 026_2 f1562：`0x40e3b0`→`0x40b910`→`0x407510`→`0x408370`→`0x4074a0`→重建→计数 1→2→下标 0 |

参考帧 `first_control_action_menu.png` 首控时两名 023 在雷歐納德前方：由开战调级解释（每名 023 有 2/3 概率升到 L2 以上、速度 ≥15，见 [original_auto_growth](original_auto_growth.md)），不是排序差。

## 重制接线

- `BattlePlayLoop.begin_battle` 开战从队列首项起跑，NPC 前缀走现有 AI 步进演出；玩家选择不能抢 NPC 回合。
- `CoreTurnQueue.rebuild` 按 `registration_slot` 排序；名单按创建顺序写入（汇编 `trace_opening`；运行时插入由 `ScriptActorCreationRules._install` 追加），回绕前「追加」等于「下一槽」。
- `hsltools/data/first_battle_formation.py` 保持 EVEF 记录顺序并生成 1 级速度与 str／dex；开战调级由 `InitialRosterGrowthRules` 施加。
- `BattleCheckpoint.state` 原样存 `units` 与 `turn_queue`，读档不重排。
- 回归钉点：`run_tests.gd`（51 关雷歐納德 5／023_1 6／023_2 7；`_test_real_equal_speed_pairs_follow_registration_slots`；6 关 EVEF 023_7 在剧情插入守卫 1..3 之前）。

## 复现

`python3 tools/hsl.py check registration_order`（139 个场景：128 个原版名单 0 失配，覆盖 4543 对同速 NPC、596 对同速玩家／NPC；`--table` 逐场景，`--pak` 从原 hsl.pak 重测 EVEF 平面）。

## 边界

- 游标回绕后空槽复用未建模；写入的 NPC 注册峰值 117（12 关），只有补兵事件（10、12、37、51、53、902 关）可能超过 181。
- 原存档是否能在战中触发、读档与恢复之间是否再调 `0x42da60` 未追。
- `0x40e430` 回复未实测执行；回合末中毒致死、`0x4075a0` ActiveAgain 第二遍扫描、待機菜单输入到 `0x10000`、脚本离场当前行动者未实测。
- 开战调级抽数已按创建顺序接全局流；全局流种子、玩家之间与 NPC 之间的创建次序、完整属性上限未复现。
- 不恢复原 NPC AI 路径与目标选择；不得把观察到的落点硬编码。

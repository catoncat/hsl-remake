# 原版 艾瓦台地（LEVEL017）：护送 NPC 与敌方 AI，两次全待机开局

> evidence: runtime-measured; provisional: item consumption and NPC movement rule; static-derived: remake friendly candidate filter, fixed-point refinement walk; resource-derived: level017.BIN EVEF instance words · status: record-only · functions: 0x409090, 0x40ed50, 0x411080, 0x413740, 0x42bd50 · tools: hsl_original_control.py, hsl_original_probe_units.py, hsltools/data/original_save.py · updated: 2026-09-28

## 结论

- 原版两次全待机开局：克里夫 064 每回合移动（第 1 回合两次都 (31,14)→(33,15)，走向 EVEF 固定点 (37,18)），HP 21/94 时自用回復藥 +40；三名 062 三回合不动；062 阵亡不结束战斗（runtime-measured）。
- 敌方前队的单位、次序与行动种类与重制一致：首控前 035 先行动，037／038／036 走同样路线，两名 035 以 8／9 MP 的地裂／咒殺打护送目标，伤害落在重制数值区间内（runtime-measured）。
- 064 的物品与移动来自 EVEF 实例字（两瓶 241、固定点 (37,18)、`ai_fixed 8`），062 不动是无武器普通路径（static-derived／resource-derived）；重制接入后 064 第 1 回合同落 (33,15)，第 2 回合落 (36,16)（原版第 2 次运行第 3 回合的格）。
- 差异：用药回合与谁打谁取决于共享公式里的随机抽样；逐格一致只在两次原版运行一致处声明（provisional）。

## 证据

**runtime-measured：出处**。原版 HSL v1.06 载入生成的回憶錄预设 `level17_pre_battle`（[original_save_format.md](../../static_reverse/original_save_format.md)：五名第一章成员、主线 WINFAIL 胜到 15、站在席達鎮且艾瓦台地未访问），走到点 17，玩家单位每回合都選 待機，打两次。控制 `tools/hsl_original_control.py`（每次输入对照 cnc-ddraw PNG）；内存 `tools/hsl_original_probe_units.py` 经 `ignored/bin/hsl_win32_memread.exe` 读 `*0x4c1bc8` 演员记录（步长 0x1fc），按 +0xa4 连到对象表 `0x4c34c0`，格 = 对象 +4/+8 ÷ 32；阵营码 玩家 `0x10000`、敌 `0x20000`、友军 NPC `0x50000`。[receipt.json](receipt.json) 存 18 份快照（每份 24 单位）。两次误点（道具、狀態）以 Escape 关闭，前后快照相同。

**开局（首次玩家控制）**

| 单位 | 原版第 1 次 | 原版第 2 次 | 重制（loop 种子 1） | 脚本格 |
| --- | --- | --- | --- | --- |
| 雷歐納德／緹娜／琥／漢克斯／雪拉 | L1 30 · L2 36（MP 19）· L4 40 · L7 50 · L6 59（MP 41），(34,20) (35,17) (35,22) (37,22) (38,19) | 相同 | HP、MP、格相同 | — |
| 克里夫 064 | L5 **64/91** (31,14) | L5 **74/94** (31,14) | L4 **65/87** (31,14)（同一首击后） | (31,14) |
| 062 ×3 | L5 83、L5 83、L5 82，(32,13) (32,16) (35,13) | L5 83、L4 75、L5 81 | L4 75、L5 82、L4 77 | 同 |
| 035 ×2（前队） | L10 58 MP **20**/28 (27,14)；L10 58 MP 28 (29,15) | L10 58 MP 28 **(30,14)**；L10 58 MP 28 (29,15) | 035_1 移到 (30,14)；035_2 在 (25,15) | (27,14) (25,15) |
| 038／037／036（前队） | 038 L4 66 (20,12)、L6 79 (26,18)；037 L6 67 (22,17) (22,11)；036 L4 52 (22,14) | 038 L5 72、L4 66；037 67、67；036 L3 46 | 038 66、80；037 67、67；036 52 | 同 |
| 后队 9 单位 | 038 80、80 · 035 58 ×3 MP 28 · 037 67 ×2 · 036 45 | 038 80、84 · 035 58 ×3 · 037 67 ×2 · 036 59 | 038 79、66 · 035 58 ×3 · 037 70、67 · 036 73 | 同 |

两次原版都在首控前让 (27,14) 的 035 先行动：第 1 次施地裂（MP 28→20，064 91→64），第 2 次走到 (30,14) 近战（94→74）；重制首个 AI 回合同一单位做第 2 次的动作（064 87→65）。(25,15) 的 035 在两次原版首控前都已到 (29,15)。

**逐回合（玩家侧全待机）**

| 回合 | 原版第 1 次 | 原版第 2 次 |
| --- | --- | --- |
| 1 | 037 (22,17)→(26,17)、(22,11)→(24,13)；036 (22,14)→(26,14)；038 (20,12)→(26,12)、(26,18)→(32,18)；**064 (31,14)→(33,15)**；062 不动；035 (27,14)→(31,14)，另一 035 自 (29,15) 施地裂（MP 28→20）：064 64→37，(32,16) 的 062 83→59 | 同路线（036 到 (27,14)，038 到 (30,16)），**064 →(33,15)**，062 不动 |
| 2 | 038 (32,18)→(35,20) 打雷歐納德 30→10；**064 (33,15)→(34,18)**；038 →(32,12) 打 (32,13) 的 062 83→48；两 035 咒殺（MP 20→11）与地裂（MP 20→12）打 (32,16) 的 062 59→6；037 →(32,17) 击杀（搬運工人遗言） | 两 035 各施地裂（MP 28→20）于 (33,15) 的 064 与 (32,16) 的 062：064 74→47→21，062 75→51→29 |
| 3 | 雷歐納德阵亡（败北页，无快照） | **064 (33,15)→(36,16)，21→61**；038 →(32,12)、036 →(31,13) 打 (32,13) 的 062 83→18（攻击者上方 `EXP 23`）；038 (30,16)→(33,16) 击杀 (32,16) 的 062 29→0，战斗继续；快照 `r14p-8`：064 持 1 瓶 241，(32,13) 的 062 无，另两名 062 各 1 |

**重制对照（同策略，loop 种子 1）**：[remake_all_wait_trace.txt](remake_all_wait_trace.txt)（接入前）、[remake_all_wait_trace_r16.txt](remake_all_wait_trace_r16.txt)（实例物品、后队 `wait_round` 3、按路径距离走向固定点）、[remake_all_wait_trace_r23.txt](remake_all_wait_trace_r23.txt)（`0x411080` 精化）。

| 回合 | 原版第 1 次 | 原版第 2 次 | 重制（路径距离走法） | 重制（精化走法） | 规则位置 |
| --- | --- | --- | --- | --- | --- |
| 首控前 | 035 地裂 91→64 | 035 近战 94→74 | 035_1 近战 87→65 | 同左 | `AIDecisionRules.select_action` 抽样；近战 20/22、地裂 27/26 均在重制数值内 |
| 1 移动 | 064 →**(33,15)** | →**(33,15)** | →(32,17) | →**(33,15)** | `AINavigationRules.approach_home`：精化链 (37,18)→(36,18)→(36,16)→(34,16)→(33,15) |
| 1 038（26,18） | →(32,18) 不打 | →(30,16) 不打 | →(31,17) 打 064 65→33 | →**(30,16)** 不打 | 上一格的后果：(32,17) 距该 038 七格可达，(33,15) 十格够不着 |
| 2 伤害 | 地裂＋咒殺打 062 | 地裂 ×2 打 064 74→47→21 | 咒殺 65→36、地裂 36→10、036 近战 10→**0** | 035_1 地裂打 062_2，波及 064 65→39 | 施法者选目标与地裂波及沿用现有内核 |
| 2 移动 | 064 →(34,18) | (33,15) 未动 | 已死 | →**(36,16)** | 精化 (37,18)→(37,17)→(36,16) |
| 3 | 雷歐納德阵亡 | 064 →(36,16)，21→61 | — | 064 →(37,18)，第 4 回合释放（`fixed_point_reached`），39 HP 不喝药 | `AIPriorityRules.self_recovery`：阈值约 max 的 12–29%（原版 21/94=22%），39/87=45% 不触发 |
| 4–5 | — | 停止 | — | 038_2 打雷歐納德 30→12，037_2 击杀 → `defeat_leonard`；064 存活 39 | 全待机策略 |

**resource-derived**：level017.BIN EVEF 实例字 0x10..0x2C：064（记录 8）`[241, 241]`，(32,16) 与 (35,13) 的 062（记录 6、7）各一瓶，(32,13) 的 062（记录 5）无——与 `r14p-8` 在 064 用掉一瓶（241 `max_hp: 40`）后的槽位一致。记录 8 的 index-15 字 `0x04A00240` → 固定点 (37,18)、`ai_fixed 8`、对象旗 0x4000。

**static-derived**：无武器守备者离开固定点时每回合走向它（`0x43fbd6`→`0x411080`），到达后释放（安装回调 `0x42bd50`）；无武器的普通路径 `0x409090` 在 `0x43ff1f`／`0x440041` 返回 0 并在 `0x441eb8` 结束回合，三名 062 不动与原版一致（[original_ai_navigation.md](../../static_reverse/original_ai_navigation.md#证据)）。重制接入前 064／062 全部 `wait`，原因是接近过滤而非阵营判定：`ai_decision.candidate_filters` `{"living_foes":15,"without_approach":15,"guard_excluded":0,"unarmed":true}`，`wait_reason=no_valid_action`。

图：run2-opening-cliff-line.png（原版帧见私有档案：`runtime_observations/original_level17_escort/run2-opening-cliff-line.png`）（克里夫到场台词）、run1-round1-earth-spell-on-cliff.png（原版帧见私有档案：`runtime_observations/original_level17_escort/run1-round1-earth-spell-on-cliff.png`）（地裂落在 064）、run2-round3-enemy-exp-on-refugee.png（原版帧见私有档案：`runtime_observations/original_level17_escort/run2-round3-enemy-exp-on-refugee.png`）（`EXP 23`）、run2-round3-refugee-death-line.png（原版帧见私有档案：`runtime_observations/original_level17_escort/run2-round3-refugee-death-line.png`）（062 遗言后战斗继续）。

## 重制接线

- `ActorInitializationRules.apply_instance_words` 按实例字填物品；友军自疗走与敌方相同的 `ai_check_hp` 路径。
- `AINavigationRules.approach_home` 复刻 `0x411080` 精化；第 6 回合 `actSetPlayerFixPos(SID_ENEMY064,1,1024,416,1)` 把锚点改到 (32,13)、半径 1，不瞬移（全待机战在第 5 回合结束，未触发；解释器测试覆盖写入）。
- 重制侧驱动 [remake_all_wait_trace.gd.txt](remake_all_wait_trace.gd.txt)：`Autoplay.reach_first_control`，玩家 `choose_command("wait")`，`step_ai_turn` 逐步打印名单差异与友军 `wait_reason`／`candidate_filters`；`HSL_TRACE_SCENARIO`／`HSL_TRACE_ROUNDS`／`HSL_TRACE_PLAYER_HP` 选场景、回合数与仅观察用的队伍 HP；复制为临时 `res://tests/*.gd` 运行。
- 52 关同策略复跑见 [remake_all_wait_trace_level52.txt](remake_all_wait_trace_level52.txt)（结论在 [original_ai_navigation.md](../../static_reverse/original_ai_navigation.md#证据)）。

## 复现

不可再生：原版侧唯一记录。

## 边界

- 未覆盖玩家行动、第 6／8 回合插入（WINFAIL017 event 1/2、嚎到场）、胜利路径与原版 fail 1 结果页。
- 062 三回合后是否移动、原版回合内的行动次序（快照按玩家菜单而非逐个 AI）、命中抽样未覆盖。
- 原版 RNG 未播种；逐格一致只在两次原版运行一致处声明。
- 精化洪泛已按 `0x411080`／`0x40ed50`／`0x413740` 静态读法移植并由原版抽签回放核对（[original_ai_navigation](../../static_reverse/original_ai_navigation.md)「结论」）；80% 拒绝对本关护送路线的影响仍未由本记录证明。

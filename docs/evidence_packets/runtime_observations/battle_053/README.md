# 逃出克萊恩城（level 53）：自动对局为什么输、逃脱路线是什么

> evidence: runtime-measured: 重制自动对局、原版 53 关开局全部单位记录与前两回合（R33 一趟 Wine）及其 AI 实例字解码、同一 53 交接 5 种子×3 属性档对局（M2）; resource-derived: WINFAIL053／STORY053／EVEF／WRD／obj-053.h; static-derived: 0x43ede0 追击入口与 0x40e590 气力、0x407ec0 阵营互换与 0x448840 的 hp_level 项、STORY／WINFAIL 插入同走脚本 VM 0x450840; provisional: 机器人策略、WINFAIL 插入单位当回合是否行动、最短路平局次序与 023 随机携带品 · status: live · functions: 0x407ec0, 0x40e590, 0x43ede0, 0x448840, 0x450840 · tools: hsl_original_probe_units.py, hsltools/data/original_save.py, run_autoplay_sweep_tests.gd, run_chapter_autoplay_tests.gd · updated: 2026-09-23

前半记录的是 Godot 重制版自动对局（`tests/support/AutoplayBrain.gd` lookahead 机器人）在 `content/battles/third_battle.json` 上的实际对局与静态资源读法；末段「原版对照」是 lane R33 用生成存档把原版带到 53 关开局后读出的现场（runtime-measured）。脚本 token、EVEF 编队与地形格为 resource-derived；机器人的走位、死法与"路线长度"是重制读法，不能据此声称原版等价或原版难度。

## 胜负条件（resource-derived，WINFAIL053）

| 段 | token | 重制读法 |
| --- | --- | --- |
| win 0 | `actCheckPlayerArrivePos,SID_PLAYER1,1,960,1120,992,1152` → `actMessage 704`／`actDeletePlayerCode`／`actSetNextPlayLevelEvent,1,1` | 受控单位（緹娜）站到像素矩形 (960,1120)–(992,1152) 即 4 格 `(30..31, 35..36)` 之一 → `victory_escape`；这是唯一胜利条件，没有"清场胜利" |
| fail 0 | `actCheckPlayer,1,SID_PLAYER1` | 緹娜 阵亡 → 判负（autoplay 记为 `defeat_leonard`，即"受控主角阵亡"的统一出口名） |
| event 0／1 | 回合 5：插入 `obj_Story_Level53_Enemy23` 走到 (160,576)＝格 (5,18)；回合 7：走到 (32,960)＝格 (1,30) | 增援落点 |
| event 2 | `actCheckEnemyNumber,SID_ENEMY023,2`：023 登记数**严格小于 2**（0x450840 case 0x24，见 [目标计数读法](../../static_reverse/original_check_targets.md)）时再插一名到 (1,30) 并重新武装自身；这一段没有 `actSetPrevInsertObjectAdjustLevel` | 场上只剩 1 名 023 时补一名 |

STORY053：緹娜 由 `obj_Story_Player2` 装在 (640,416)，开场走 (0,32) 再沿绳滑 (0,288) → 首控格 **(20,23)**；两名守卫 023 由脚本从 (1056,768) 走到 (928,768)／(864,736) → 格 **(29,24)／(27,23)**；`obj_Story_Block` 插在 (640,672)＝格 (20,21)（重制未建模碰撞，见 [第三场 unresolved](../../../../content/battles/battle_053.json)）。EVEF record 17 是第三名 023，站在 (960,1152)＝**出口格 (30,36)** 本身，实例字 `wait_round 8`／`find_range 8`。

## 路线长度（resource-derived 地形 ＋ 重制四邻读法）

`content/generated/hsl/static/hsl01/level053_terrain.json`（32×43，`b` 阻挡 231 格，`h` 高度 1–3 是 x 8–18／y 32–35 的坡道）。从 (20,23) 到出口 4 格的曼哈顿距离 22，但四邻 BFS 最短路 **54 步**：屋顶南缘 y=27 自 x=12 起全阻挡，唯一下行口在西侧 x≤11；y=31 自 x=6–17 阻挡，只能从 x≤5 下到 y=32；再经坡道东行到 y=35 的城墙走道，向东 12 格到出口。移动 5 的 緹娜 至少 11 回合。三处增援落点 (5,18)／(1,30)／(1,30) 全部压在这条西行路线上——脚本作者预期的逃脱路线就是它。

```text
y22 ....##..........................   ← 緹娜 (20,23) 先上到 y22 西行
y23 .####..#............T.#....E....
y27 ........#...####################   ← 屋顶南缘只在 x≤11 开口
y31 ......############..............   ← 只能从 x≤5 下去
y32 ###..............###############   ← 坡道 h1–3（x8–16）
y35 .......###.......#............XX   ← 城墙走道东行到出口 XX
```

## 机器人怎么死的（runtime-measured，`HSL_AUTOPLAY_LEVELS=53 HSL_AUTOPLAY_BRAIN=lookahead HSL_AUTOPLAY_BRAIN_TRACE=1`，基线 660194b5）

- `escape` 候选用**曼哈顿距离**挑"离出口最近的可达格"：第 1–4 回合把 緹娜 往东南推到 (22,26)→(23,26)→(25,26)，即 y=27 墙前的死口袋，与真实路线反向。
- lookahead 的 `evaluate` 没有逃脱项：第 1、2 回合 escape 的 value（−8，暴露度）低于 protect_hero／hold_line（0），机器人原地兜圈；第 3 回合起两名守卫（速度 14 先于 緹娜 12 行动）贴身，每击 8–17 对 36 HP，机器人在 heal／magic／special 与 escape 间摇摆，第 13 回合被 enemy023_3 击杀（chapter 记录 9 回合、贪心 sweep 4 回合，死法相同：被两名脚本守卫追上）。
- 门口守卫 enemy023_1 与两名增援整场 `wait`：增援从 `template_unit_id enemy023_1` 克隆，连 EVEF record 17 的实例字（`wait_round 8`）一起继承。原版脚本插入的 023 不带 record 17 的实例字（PLAYERS 023 默认 `wait_round 0`／`find_range 80`）——这是重制的 provisional 读法，方向上让本关**更容易**而非更难；替换证据：原版对 `actInsertObject` 实例字的初始化路径，或 Wine 观察第 5 回合增援是否立即追击。

## 修复（机器人，`tests/support/AutoplayBrain.gd`）

| 提交 | 改动 | 53 关 lookahead 结果 |
| --- | --- | --- |
| 基线 660194b5 | — | 第 1–4 回合走进死口袋（步行距离 57 不变），13 回合败 |
| 第一步 | 逃脱候选按**步行距离**（`_escape_field`：从出口四格用 `TacticalGridRules.movement_reachability_envelope` 无界洪泛的地形代价场，按场景缓存）；`evaluate` 加逃脱进度项 `VALUE_ESCAPE_STEP` 12/格；逃脱方案不受 reach 规则搁置；跑者只在能击杀时出手（`_escape_strike`／`_move_then_wait`）；逃脱格暴露度按"自己已离开当前格"重算（`_pursuers_reaching`，走廊里自身身体挡住追兵路径造成 thr=0 误判） | 11 回合内 57→4（跑到出口外 4 格），第 7、8 回合在坡道各中一击（13＋15／36），第 11 回合补药，第 13 回合被追兵击杀 |
| 第二步 | `_reach_exempt`：kills>0 的方案与 escape 一样必进模拟——第 12 回合月花圓舞@门口守卫（29.0 伤害＝29 HP）此前被 −415 的 escape 压住（未到 `RELAX_BELOW_VALUE` −500 不放宽）从未模拟 | 第 12 回合击杀堵在 (26,35) 的门口守卫，第 13 回合被两名追兵 14＋16 击杀（HP 15）；**仍 fail** |

非逃脱关不受影响：`HSL_AUTOPLAY_LEVELS=1,2,52` lookahead 与基线同构（win／fail／fail）。

## 结论

1. **胜利条件接线无缺口**：`WinfailScenarioRules.victory_state` 已把 `actCheckPlayerArrivePos` 解释为 `victory_escape`，出口格与脚本像素一致；队伍 `{tina: 2}` 也对——53 是序章，緹娜 独自逃脱，进 53 时不该有别人。
2. **机器人一半已修**（上表）；修完后 53 关在当前重制数值下按任何跑法都赢不了——**数值节拍**：月花圓舞 20 ST 要靠挨 3 下攒（`StaminaRules.amounts`＝`0x40e590`：受击 +6，半血以上重击 +8；緹娜 初始 0 ST），而 緹娜 36 HP＋一瓶药（+28）撑不过坡道 2 下（等速追兵在 h1–3 爬坡处追上）＋补药回合 1 下＋清门口守卫回合 2 下（每下 13–21）。
3. **AI 追击不是缺口**（static-derived，r2 有界读 AI 过程 `0x43ede0` state 0xb sub 0，`0x440d5c`–`0x440d84`）：普通追击在 `0x40fb20` 找不到本回合可攻击站位时调 `0x4111a0(actor, 目标+4, 目标+8, 0x12, +0x12c)`，即与固定点行走同一条 `0x411080` 精化链（R23 `AINavigationRules.approach_home` 已复刻，见 [原 AI 导航包](../../static_reverse/original_ai_navigation.md)）。53 关路线单调，精化链落格与重制最短路前缀相同；`0x40d800` 的 80% 拒绝只数 `mask|0x4000`（障碍位＋敌方侧位），WRD 0xff 悬崖不带 0x4000（[原移动包](../../static_reverse/original_movement.md)），路线上没有一格能凑到 ≥3。所以复刻它不会改变 53 关结果，本 lane 未实现（负责人决定）。
4. **原版 53 关开局已实测**（下节「原版对照」，R33）：緹娜 与出口守卫的记录逐字段相同，但两名脚本守卫在重制里多了 1–2 级（脚本的 `actSetPrevInsertObjectAdjustLevel,0,0` 没进开局名册），且阵营互换单位的最大 HP 多 1；`stuck_at=53` 的定性从"重制数值节拍下不可过"改为"规则缺口（两项）＋机器人"，规则字段与消费点见下节，本 lane 不调属性、不改断言。
5. （R35 前的读法，已被取代）门口守卫与增援全场 `wait`（增援复制 record 17 的实例字）。R35 起增援走 `script_actor_templates`、带 PLAYERS 023 默认 AI 字；原版插入实例字的实测与对照见下节「M2 对照」。

## 原版对照（runtime-measured，lane R33，2026-09-22）

**路线。** 生成存档 `content/generated/hsl/development/original_saves/level53_pre_battle.SAV`（[原版存档格式](../../static_reverse/original_save_format.md) 的 `entry_level` 预设：51／52 胜后 header `next_level＝level_files＝58`，只注册 slot 0，其余记录全零）装为 `SAVES/HSL00.SAV`；原版 v1.06（Wine）标题 → 戰場記錄（落在 51 关首控）→ 右键系统菜单 → 讀取回憶錄 → 第 1 行「歐姆村 等級01 0:15」→ 直接进入 STORY058（王座厅），空格走完 058／060 对白（memread `0x4c1bb8` 依次 58 → 60 → 53）→ STORY053 开场 → 緹娜 首个行动菜单。玩家只按 待機 两次；每个菜单用只读 `tools/hsl_original_probe_units.py`（`hsl_win32_memread.exe`）读全部 live 单位记录（[original_units.json](original_units.json)，四份快照含原始 0x1fc 记录 hex）。游戏画面：[首控](original_first_control.png)、[待機 #1 后的菜单](original_after_wait1.png)、[第 3 回合守卫第二击的切入](original_after_wait2_cutin.png)。一趟起止 17:58:11–18:13:48（15 分 37 秒，**超出任务书的 ≤10 分钟约 5.5 分钟**：058／060 共约 40 句对白每句一次有界按键各带截图；未做无人值守对局，不占用键鼠超过该时段）。原始输出留 `ignored/`，副本在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-recordings/R33-level53/`。重制侧用同一 seed 1 的 lookahead 对局（`HSL_AUTOPLAY_LEVELS=53 HSL_AUTOPLAY_BRAIN=lookahead HSL_AUTOPLAY_BRAIN_TRACE=1 HSL_AUTOPLAY_DEBUG_AI=1`）与首控时 PlayLoop 单位字段（临时 dump 脚本，未提交）对照。

**开局单位（首控时刻）。** 原版 = live 记录（`+0x9c` 等级、`+0xd8/+0xdc` HP、`+0xe0/+0xe4` MP、`+0x4c..+0x58` 四维、`+0xc0` 攻、`+0xb4` 防、`+0xb8` 速、`+0xbc` 命中、`+0xd0` 魔攻、`+0x130` 移动、`+0xec..+0x100` 装备、`+0x138` 物品、`+0x28` 阵营字；格 = 对象 `+4/+8 ÷ 32`）；重制 = PlayLoop 单位（`level`／`hp`／`combat_profile.*`／`equipment`／`inventory`／`coord`／`battle_actor_role`）。

| 单位 | 字段 | 原版 | 重制（seed 1） | 同／异 |
| --- | --- | --- | --- | --- |
| 緹娜 002 | 等级／经验 | L2 exp 0（模板 L1，安装时按四维推得 L2；`+0x8c` 门槛 150） | L2 exp 0（`InitialRosterGrowthRules.prepare_player` 的 `inferred_level`） | 同 |
| | HP／MP | 36/36 · 19/19 | 36/36 · 19/19 | 同 |
| | 四维 str/dex/mind/con | 16/11/15/15 | 16/11/15/15 | 同 |
| | 攻／防／速／命中／魔攻／移动 | 38／42／12／98／53／5 | 38／42／12／98／53／5 | 同 |
| | 装备（武／头／甲／足／饰） | 82／152／122／181／201 | 82／152／122／181／201 | 同 |
| | 物品 | [241, 244] | [241, 244] | 同 |
| | 坐标／阵营 | (20,23)／`+0x28` 0x10000 pmPlayer | (20,23)／player_controlled | 同 |
| | 气力 | 0（受击后 +6：6 → 12 → 18，三击） | 0（`StaminaRules` 受击 +6） | 同 |
| 出口守卫 023（EVEF record 17，(30,36)） | 等级 | L1 | L1（`entry_growth` parameters [0,0]，record 17 覆盖） | 同 |
| | **HP** | **28/28** | **29/29** | **异（−1）** |
| | 四维／攻／防／速／命中／魔攻／移动 | 15/14/9/14／45／36／14／96／17／5 | 同 | 同 |
| | 装备 | 1／152／124／181 | 1／152／124／181 | 同 |
| | 物品 | [249] | [246] | 异（原版安装时随机携带品，来源未定位） |
| | 坐标／阵营 | (30,36)／0x20000 pmEnemy（`+0xa0` |= 8，obj_Data9 互换） | (30,36)／enemy_ai | 同 |
| | 实例字 | `+0x1c8` find_range 8、`+0x1b8` 7（record 17 的 wait_round 8 剩余计数） | evef_instance find_range 8／wait_round 8 | 同 |
| 脚本守卫 023 #1（`actInsertObject` → 走到 (928,768)=(29,24)） | **等级** | **L1**（`+0x1f8` 0/0：`actSetPrevInsertObjectAdjustLevel,0,0` 已消费） | **L2**（`entry_growth` origin initial_roster，parameters **[18, 2]** = PLAYERS 023 模板的 level_adjust_range／disp） | **异** |
| | **HP／四维／攻／防／速／魔攻** | **28/28 · 15/14/9/14 · 45／36／14／17** | **35/35 · 17/15/10/15 · 48／39／15／19（气力 2）** | **异** |
| | 物品 | [246] | [241] | 异（同上） |
| | 首控前位置 | 已先于 緹娜 行动：(29,24) → **(25,23)** | (29,24) → **(26,22)** | 异（同为满 5 步逼近，落格不同） |
| 脚本守卫 023 #2（走到 (864,736)=(27,23)） | **等级** | **L1** | **L3**（parameters [18, 2]） | **异** |
| | **HP／四维／攻／防／速／魔攻** | **28/28 · 15/14/9/14 · 45／36／14／17** | **40/40 · 19/16/11/16 · 50／39／16／20（气力 8）** | **异** |
| | 物品 | [249] | [246] | 异 |
| | 首控前位置 | (27,23) → (23,22) | (27,23) → (23,22) | 同 |

**AI 前两回合（玩家 待機）。** 原版：首控前两名脚本守卫（速度 14 > 緹娜 12）各走满 5 步逼近（上表）；出口守卫整场不动。緹娜 待機 #1 后：(23,22) 守卫走到 (21,23) 并命中 **9**（36 → 27，该守卫 exp 9／气力 3），(25,23) 守卫走到 (21,22)（斜邻，未攻击）。待機 #2 后：(21,22) 守卫走到 (19,23) 命中 **7**（27 → 20，exp 7），(21,23) 守卫原地再命中 **13**（20 → 7，exp 累计 21／气力 6）——第 3 回合菜单时 緹娜 7/36、气力 18。重制（机器人逃跑，条件不同，只比守卫的首控前一步与出口守卫）：#2 守卫同格 (23,22)，#1 守卫 (26,22) 而非 (25,23)，出口守卫 wait；重制 L2／L3 守卫对 緹娜 的单击为 13–21（R28）对原版 L1 守卫的 7／9／13。`0x4c1e8c` 在四份快照里始终为 1，不能当回合计数用（记为 negative-evidence）。

**定性：规则缺口（两项）＋机器人。** 緹娜 与出口守卫的数值原版等价；把 53 关变难的是重制自己加给两名脚本守卫的 1–2 级，以及阵营互换单位多出的 1 HP：

1. **脚本插入的 023 未继承 `actSetPrevInsertObjectAdjustLevel,0,0`**（原版 `+0x1f8` 范围／离散 = 0 → 安装时不调级，L1／28 HP／攻 45／速 14）。重制消费点：`game/battle/runtime/BattleOpeningCoordinator.gd:_apply_event` 的 `inserted_object_adjust_level` 只记录不处理（`recorded_no_handler`），STORY 层的两名守卫由 `tools/hsltools/levels/scenario.py` 烤进 `third_battle.json` 的 `playable_units`（`position_source.story_walk_target`）时没有带上 0/0；`game/sim/InitialRosterGrowthRules.gd` 对 allocation≠manual 的初始名册调 `ReinforcementGrowthRules.prepare(next, actor, {}, "initial_roster")`，插入参数为空时回落到 PLAYERS 模板的 `level_adjust_range 18／disp 2`（只有 `evef_instance.overrides` 能覆盖）→ 以 緹娜 L2 为中心抽到 L2／L3。全库 STORY 层该 token 只出现在 53 关这两处（field coverage：关 1、出现 2），WINFAIL 层的运行时插入已走 `adjust_level`。修法（交负责人派）：让 scenario.py 把脚本的 adjust_level 写进这两名单位（如 `evef_instance.overrides.level_adjust_range/disp = 0/0` 或新字段 `adjust_level: [0,0]`），并让 `ReinforcementGrowthRules.prepare` 在 initial_roster 时读它。
2. **阵营互换单位的最大 HP 少 1**：`0x448840` 的 HP 公式含 `hp_level` 项，只在 live `+0x28 & 0x10000`（pmPlayer）时取等级，否则取 0；`0x407ec0` 在刷新前按 obj_Data9 把 023 的 `+0x28` 由 pmPlayer 换成 pmEnemy，所以原版 L1 023 敌人 28 HP，而 PLAYERS 模板（pmPlayer）刷出 29。重制 `game/sim/JobStatsRules.gd:98` 的 `hp_level` 读 `growth_profile.source.mode`（`hsltools/model/jobs.py:source_profile` 取 PLAYERS 行的 mode，`third_battle.json` 三名 023 都是 65536），没有跟随安装后的 `player_mode`／`battle_actor_role`。影响所有被互换成敌方的 023／024 类单位（1 HP／级别相关项）。
3. 023 的一格随机携带品（原版 246／249，模板无物品）来源未定位，重制另有一套（241／246）；不影响本关胜负，标 provisional。

机器人侧：R28 的"跑不过坡道"是在 L2／L3 守卫（单击 13–21）下得出的；原版 L1 守卫单击 7–13、HP 28（月花圓舞 29.0 一击可杀），修完两项后应重跑 `HSL_AUTOPLAY_LEVELS=53` 再定性机器人。本包不改规则、数值与机器人。

**R34 收口（两项已按原版修，lane R34）**：① `scenario.py story_inserts` 解析 `actSetPrevInsertObjectAdjustLevel`，两名追兵在 `third_battle.json` 带 `script_insert.adjust_level [0,0]`，`InitialRosterGrowthRules` 把它作为 insertion 传给 `ReinforcementGrowthRules.prepare`（运行时插入请求早已带同名 `adjust_level`）；`BattleOpeningCoordinator` 把该 kind 列入 RECORD_ONLY_KINDS（由装配预烤）。② `JobStatsRules.base_values` 多一个 `side_mask` 参数，`ProgressionRules.refresh_growth_stats` 传 `ActorRoleRules.side_mask(unit)`（安装后的 `player_mode`，无则按 role 隐含侧）。重制 53 关开局现在三名 023 均 L1／28／攻 45／速 14（`run_entry_growth_tests.adjust_level_zero_story_and_runtime`、`run_job_stats_tests.live_side_hp_level` 以本包数值为断言）。机器人重跑：lookahead 指挥官 seed 1 **胜**（22 回合 `victory_escape`，改前 13–14 回合败），贪心 sweep 仍败（5 回合，改前 4）；见 lane R34 报告。

## M2 对照（R35／R36 之后：规则缺口还是机器人缺口，lane M2，2026-09-23）

**结论：机器人缺口，没有找到规则缺口。** 守卫与追兵的模板、出场格、出场时机、等级、AI 实例字，以及前三回合的走位和伤害，都与原版现有证据一致。卡关的原因是：同一名机器人在同一份交接下，原属性只赢 1/5，属性 +10% 就 5/5 全胜，+25% 也是 5/5；输掉的种子到死没用过一次魔法，到达出口守卫时气力也不够放月花圓舞。R35 让增援改追击是向原版靠拢，**不是**变难的来源：5 个种子里增援从没打到过緹娜，致死的都是两名 STORY 追兵和出口守卫。本 lane 没有改 `game/`；R35 之后从 3/5 掉到 1/5，读作这一关胜负本来就悬在一线，随机数路径一分叉结果就不同（p≈0.4 时 5 局赢 ≤1 局的概率约 0.34）。

**来源。** 原版 AI 实例字：从 R33 的四份快照 [original_units.json](original_units.json) 里按原始记录 hex 解码（runtime-measured）。偏移依据是 [原 AI 导航包](../../static_reverse/original_ai_navigation.md) 的实例字表：`+0x1b8` wait_round、`+0x1c0` find_type、`+0x1c8` find_range、`+0x1cc` ai_call_range、`+0x1e8` ai_lock、`+0x1f8` 调级半字。重制侧用 R36 深门章节走查写出的 53 关交接存档，副本在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-artifacts/M2/handoff53.json`（从 51／52 走来的 carry；緹娜 用关卡模板）。对局命令：`HSL_AUTOPLAY_HANDOFF=… HSL_RNG_SEED=1..5 HSL_AUTOPLAY_BRAIN=lookahead HSL_AUTOPLAY_STAT_SCALE=1.0|1.1|1.25 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`（外加 `HSL_AUTOPLAY_DEBUG_AI=1 HSL_AUTOPLAY_BRAIN_TRACE=1`）。另写了一个未提交的探针，照 R33 在原版里的走法，让緹娜 每回合只按待機，并在每个菜单时刻转储全部单位。基线 pipeline-line `88febe9a`。

**守卫与追兵逐项对照**（原版 = R33 快照；重制 = `88febe9a`，只待機的探针种子 1–5，另注明的除外）

| 单位 | 项 | 原版 | 重制 | 同／异 |
| --- | --- | --- | --- | --- |
| 出口守卫 enemy023_1（EVEF record 17） | 模板／出场 | PLAYERS 023＋record 17 实例字，开局就在 (30,36) | `playable_units` enemy023_1 `evef_instance`（find_range 8／wait_round 8／调级 0/0），(30,36) | 同 |
| | 等级／HP／攻／速 | L1／28／45／14 | L1／28／45／14 | 同（R34 之后） |
| | AI 实例字 | find_range **8**、wait_round 8（首控时剩 **7**，待機一次后 6，第 3 回合 5）、find_type 3、ai_call_range 4、ai_lock 60 | `instance_profile` find_range 8；`ai_wait_remaining` 在菜单 1／2／3 时为 **7／6／5** | 同 |
| | 醒来规则 | 等待中受伤、异常或八格圆域内有敌人则结束等待（`0x43f603`，static-derived）；等满 8 回合后 find_range 仍是 8 | `AINavigationRules.acquire` 同一读法；圆域是 dx²+dy²≤64：y=35 上 x≥23、y=36 上 x≥22 会叫醒它 | 同（静态读法） |
| | 第 1–3 回合位置 | (30,36) 不动 | (30,36) 不动 | 同 |
| | 随机携带品 | 249（R33 那一局） | 种子 1 是 241 回復藥（同一 carry 表 [246,241,247,248,249] 随机抽） | 随机结果不同，不是规则差异 |
| STORY 追兵 enemy023_2／_3（`actInsertObject obj_Story_Level53_Enemy23`） | 模板 | PLAYERS 023，**没有** record 17 实例字 | 同 | 同 |
| | 出场格 | 在 (1056,768) 插入，走到 (29,24)／(27,23) | 同 | 同 |
| | 调级 | `+0x1f8` 0/0 → L1／28 HP | `script_insert.adjust_level [0,0]` → L1／28 | 同 |
| | AI 实例字 | find_range **80**、wait_round **0**、find_type 3、ai_call_range 4、ai_lock 60 | find_range 80、wait 0 | 同 |
| | 首控时位置 | (25,23)／(23,22) | (26,22)／(23,22)，5 个种子都一样 | #1 不同：两边都走满 5 步，差在最短路平局时的取舍次序（provisional） |
| | 第 2 回合（待機后） | (21,22) 未出手；(21,23) 命中 9 | (21,22) 未出手；(21,23) 命中 8／9／8／11／11 | 落格相同，伤害在同一区间 |
| | 第 3 回合 | (19,23) 命中 7；(21,23) 命中 13 → 緹娜 7 HP | (20,22) 命中 12／8／8／7／28（暴击）；(21,23) 命中 8／11／14／9／– → 緹娜 8／8／6／9／0 | #1 落在西侧还是北侧不同（都贴着她）；伤害同区间 |
| | 反击 | 三击都没有反击（守卫一直 28/28） | 种子 1 反击一次，9 伤害（緹娜 `attack_back` 12） | 概率事件 |
| WINFAIL 增援 ×2（event 0／1） | 模板 | `obj_Story_Level53_Enemy23`，与 STORY 追兵是同一符号 | `script_actor_templates` 同一符号 → `level53_enemy23`（没有 `evef_instance`，所以是 PLAYERS 023 默认 AI） | 同 |
| | 出场格 | (−32,480)→(160,576)=(5,18)；(−32,960)→(32,960)=(1,30) | (5,18)／(1,30) | 同（resource-derived） |
| | 出场时机 | `actCheckRoundNumber 5／7`：计数 < num 时不成立；插入发生在第 5／7 回合第一个行动之后（R36 的读法，static-derived） | 第 5／7 回合 enemy023_1 待机之后插入，下一回合才第一次行动 | 插入时刻相同；原版插入的单位当回合能不能行动**未测**（provisional；如果原版能行动，只会更难） |
| | 调级／AI 实例字 | 脚本写了 0/0 → L1；AI 字：STORY 插入实测是 80／0，WINFAIL 与 STORY 共用 ACTION.H 的 token 表，也共用同一个脚本 VM `0x450840`（它同时处理 win／fail／event 条件 case 0x24／0x28，见 [回合显示包](../../static_reverse/original_round_display.md)），由此推得相同（static-derived） | L1／28；find_range 80、wait 0 | 同 |
| | 第 13–16 回合位置（重制机器人对局） | 未测 | (17,34)／(15,34)，落后緹娜 8–10 格；5 个种子里一次也没打到她 | 不影响胜负 |
| event 2 增援 | 触发／调级 | 023 登记数 <2；这一段没有调级指令 → PLAYERS 调级 | 同一读法 | 5 个种子都没触发 |

R35 前（`55b0c128`）的增援是按 `template_unit_id enemy023_1` 整条复制的，连 `evef_instance` 一起带过来，所以 find_range 是 8：緹娜 走出 8 格它就不追了。这与上表原版插入实例字（find_range 80）不符，R35 把它改掉是向原版靠拢。

**合格玩家检验**（同一交接、lookahead；`HSL_AUTOPLAY_STAT_SCALE` 在首控时放大緹娜 四维）

| 档 | 緹娜 HP／速／攻／防 | 种子 1–5 | 胜 |
| --- | --- | --- | --- |
| 1.0 | 36／12／38／42 | 败 14、**胜 13**、败 13、败 16、败 13（与 B2b 的 1/5 相同） | 1/5 |
| 1.1 | 40／13／39／43 | 胜 18、胜 18、胜 17、胜 19、胜 18 | **5/5** |
| 1.25 | 43／15／40／45 | 5 局都在第 11 回合被判 `stalemate_no_contact` dead_end：她比追兵快、一路没交手，驾驭器"10 回合无交手"的规则把正常逃跑当成了僵局。临时把 `STALEMATE_ROUNDS` 改成 1000（不提交，已还原）后：胜 17、胜 17、胜 17、胜 16、胜 17 | **5/5** |

加上同样的逐步打印重跑 1.0，5 局结局与回合数和上表完全相同，说明打印本身不影响结果。

**1.0 为什么输（都是机器人的问题）。**

1. **出口守卫这一仗躲不掉。** 出口 4 格只能从 (27..29,35) 这条单格通道进（y=36 上 x 27–29 是阻挡）；守卫的醒来圆域覆盖 y=35 上 x≥23，速度 14 比她先动，醒来后走 4–5 步就堵在 (26,35)／(27,35)。圈外离出口最近的格是 (22,35)，到 (30,35) 要 8 步，她只有 5 点移动。所以不管怎么走，都得在通道口打倒这名 28 HP 的守卫。这是 WINFAIL／EVEF 原本就有的设计（resource-derived），不是重制加的。
2. **到达时的气力决定胜负。** 月花圓舞 20 ST，打一片区域（种子 1 一发同时打死两名追兵），打守卫实测 21–28。5 个种子在走到 (25,35) 之前都只挨了 2 击（12 ST）。只有种子 2 靠第 8 回合一次反击（+3）加第 12 回合再挨一击，第 12 回合攒到 ≥20 ST，一发打死守卫（28），第 13 回合走到 (30,35) 逃出。种子 1／3／5 第 12 回合根本没有 special 候选，只能选 `hold_line`，也就是普通攻击守卫（20／未命中／9），第 13 回合被三面夹击。种子 4 第 12 回合气力够了，但先挨了守卫一击（12，只剩 7 HP），只好先喝药，之后 special 打守卫只打出 21。
3. **资源没用完。** 4 个输掉的种子 `magic`＝0：19 MP 到死没动（水系回復 6 MP 回 20 HP，能放三次，合计 60 HP）；种子 1／3／5 第 11 回合是走进守卫圆域 (23,35) 之后才喝药。
4. **估值偏差。** 种子 1 第 13 回合，special 候选按确定性中点估成 84 伤害、3 杀；实际上守卫先喝了自带的回復藥，special 之后还剩 4 HP，第 14 回合一击 11 打死 7 HP 的緹娜。

所以同属性下，只要在路上多攒一次气力（多换一击再用魔法补血，或顺手打一下追兵），满血、≥20 ST 走到通道口，就能走种子 2 和全部 +10% 局的那条胜线：先用月花圓舞打守卫，必要时再补一发。+10% 只多 4 HP、速度 13，仍慢于追兵，就能 5/5——这是"合格玩家能过"的量化依据，不是原版难度声明。

**为什么没开 Wine。** 能改变结论的量已经全部 runtime-measured 并对上了：等级、HP、STORY 插入与出口守卫的 AI 实例字、等待倒计时、前三回合的落格与伤害区间。还没测的只有三项：插入单位当回合能否行动、最短路平局次序、原版里人能否逃出。要看这三项得在原版里真打到第 5 回合以后；R33 只到第 3 回合就用了 15 分 37 秒（主要是 058／060 的约 40 句对白），远超一趟 10 分钟。而且这三项无论结果如何，原版都只会同样难或更难，推不翻"机器人缺口"的结论。

**留给负责人的边界（不是规则缺口，不需要派修）。** ① 插入单位当回合能否行动：provisional，替换证据是一趟原版第 5 回合观察。② 首控时 (26,22) 对 (25,23)、第 3 回合 (20,22) 对 (19,23)：`AINavigationRules` 已标注的最短路平局次序 provisional，步数相同。③ `obj_Story_Block` 在 (20,21) 没有建模碰撞：它在北侧，不在西行路线上。④ 机器人与驾驭器：气力规划、第 11 回合的喝药时机、魔法回复从不使用、special 伤害按中点估算，以及逃脱关里"10 回合无交手"的僵局判定——这些交给 bot lane。

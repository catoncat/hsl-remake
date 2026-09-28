# 逃出克萊恩城（level 53）：逃脱路线、原版开局与前两回合对照、自动对局败因

> evidence: runtime-measured: 重制自动对局、原版 53 关开局全部单位记录与前两回合（一趟 Wine）及其 AI 实例字解码、同一 53 交接 5 种子×3 属性档对局; resource-derived: WINFAIL053／STORY053／EVEF／WRD／obj-053.h; static-derived: 0x43ede0 追击入口与 0x40e590 气力、0x407ec0 阵营互换与 0x448840 的 hp_level 项、STORY／WINFAIL 插入同走脚本 VM 0x450840; provisional: 机器人策略、WINFAIL 插入单位当回合是否行动、最短路平局次序与 023 随机携带品 · status: live · functions: 0x407ec0, 0x40e590, 0x43ede0, 0x448840, 0x450840 · tools: hsl_original_probe_units.py, hsltools/data/original_save.py, run_autoplay_sweep_tests.gd, run_chapter_autoplay_tests.gd · updated: 2026-09-28

## 结论

- 原版第 53 关唯一胜利是緹娜 站上出口 4 格；四邻最短路 54 步，出口前必须在单格通道口打倒出口守卫；緹娜、出口守卫、两名脚本追兵与增援的模板、等级（脚本追兵 `actSetPrevInsertObjectAdjustLevel,0,0` → L1）、AI 实例字与前两回合走位伤害均已实测（resource-derived；runtime-measured）。
- 重制 `content/battles/battle_053.json` 在这些项上与原版一致：脚本追兵带 `script_insert.adjust_level [0,0]`，阵营互换单位的 `hp_level` 跟随安装后的侧（原版 L1 023 敌人 28 HP）；同一交接下 lookahead 自动对局原属性 1/5、+10% 5/5、+25% 5/5，输因在自动对局策略（runtime-measured）。
- 差异：WINFAIL 插入单位当回合能否行动、最短路平局次序未对齐或未测（provisional）；023 的随机携带品两边同为出生时按携带表在全局流抽，单局抽中哪件随流而异。

## 证据

### resource-derived：胜负条件（WINFAIL053）与开场（STORY053）

| 段 | token | 重制读法 |
| --- | --- | --- |
| win 0 | `actCheckPlayerArrivePos,SID_PLAYER1,1,960,1120,992,1152` → `actMessage 704`／`actDeletePlayerCode`／`actSetNextPlayLevelEvent,1,1` | 緹娜 站到像素矩形 (960,1120)–(992,1152) 即格 `(30..31, 35..36)` 之一 → `victory_escape`；无清场胜利 |
| fail 0 | `actCheckPlayer,1,SID_PLAYER1` | 緹娜 阵亡判负（自动对局统一记为 `defeat_leonard`） |
| event 0／1 | 回合 5：插入 `obj_Story_Level53_Enemy23` 走到 (160,576)＝(5,18)；回合 7：走到 (32,960)＝(1,30) | 增援落点 |
| event 2 | `actCheckEnemyNumber,SID_ENEMY023,2`：023 登记数严格小于 2（[original_check_targets](../../static_reverse/original_check_targets.md)）时再插一名到 (1,30) 并重新武装；无调级指令 | 场上只剩 1 名 023 时补一名 |

STORY053：緹娜 由 `obj_Story_Player2` 装在 (640,416)，走 (0,32) 再沿绳滑 (0,288) → 首控格 (20,23)；两名追兵 023 由脚本从 (1056,768) 走到 (928,768)／(864,736) → (29,24)／(27,23)；`obj_Story_Block` 插在 (640,672)＝(20,21)。EVEF record 17 是第三名 023，站在 (960,1152)＝出口格 (30,36)，实例字 `wait_round 8`／`find_range 8`。

### resource-derived：路线长度

`content/generated/hsl/static/hsl01/level053_terrain.json`（32×43，阻挡 231 格，x 8–18／y 32–35 为高度 1–3 的坡道）。(20,23) 到出口曼哈顿距离 22，四邻 BFS 最短路 54 步：屋顶南缘 y=27 自 x=12 起全阻挡，唯一下行口在 x≤11；y=31 自 x=6–17 阻挡，只能从 x≤5 下到 y=32；再经坡道东行到 y=35 城墙走道，向东 12 格到出口。移动 5 至少 11 回合。三处增援落点都压在这条西行路线上。出口 4 格只能从 (27..29,35) 单格通道进（y=36 上 x 27–29 阻挡）；出口守卫的醒来圆域（dx²+dy²≤64）覆盖 y=35 上 x≥23、y=36 上 x≥22，速度 14 先动，醒来后 4–5 步就堵住通道口。

```text
y22 ....##..........................   ← 緹娜 (20,23) 先上到 y22 西行
y23 .####..#............T.#....E....
y27 ........#...####################   ← 屋顶南缘只在 x≤11 开口
y31 ......############..............   ← 只能从 x≤5 下去
y32 ###..............###############   ← 坡道 h1–3（x8–16）
y35 .......###.......#............XX   ← 城墙走道东行到出口 XX
```

### runtime-measured：原版开局与前两回合（原版 v1.06／Wine）

路线：生成存档 `content/generated/hsl/development/original_saves/level53_pre_battle.SAV`（[original_save_format](../../static_reverse/original_save_format.md) 的 `entry_level` 预设：51／52 胜后 header `next_level＝level_files＝58`，只注册 slot 0）装为 `SAVES/HSL00.SAV`；标题 → 戰場記錄（51 关首控）→ 右键系统菜单 → 讀取回憶錄 → 第 1 行 → STORY058／060（memread `0x4c1bb8` 依次 58 → 60 → 53）→ STORY053 → 緹娜 首个行动菜单；玩家只按 待機 两次。每个菜单用只读 `tools/hsl_original_probe_units.py` 读全部 live 单位：[original_units.json](original_units.json)（四份快照含 0x1fc 记录 hex）。画面：首控（原版帧见私有档案：`runtime_observations/battle_053/original_first_control.png`）、待機 #1 后（原版帧见私有档案：`runtime_observations/battle_053/original_after_wait1.png`）、第 3 回合守卫第二击切入（原版帧见私有档案：`runtime_observations/battle_053/original_after_wait2_cutin.png`）。

原版 = live 记录（`+0x9c` 等级、`+0xd8/+0xdc` HP、`+0xe0/+0xe4` MP、`+0x4c..+0x58` 四维、`+0xc0` 攻、`+0xb4` 防、`+0xb8` 速、`+0xbc` 命中、`+0xd0` 魔攻、`+0x130` 移动、`+0xec..+0x100` 装备、`+0x138` 物品、`+0x28` 阵营字；格 = `+4/+8 ÷ 32`）。AI 实例字按 [original_ai_navigation](../../static_reverse/original_ai_navigation.md) 的偏移解码：`+0x1b8` wait_round、`+0x1c0` find_type、`+0x1c8` find_range、`+0x1cc` ai_call_range、`+0x1e8` ai_lock、`+0x1f8` 调级半字。

| 单位 | 字段 | 原版 | 重制 | 同／异 |
| --- | --- | --- | --- | --- |
| 緹娜 002 | 等级／经验 | L2 exp 0（模板 L1，安装时按四维推得 L2；`+0x8c` 门槛 150） | L2（`InitialRosterGrowthRules.prepare_player` 的 `inferred_level`） | 同 |
| | HP／MP · 四维 | 36/36 · 19/19 · 16/11/15/15 | 同 | 同 |
| | 攻／防／速／命中／魔攻／移动 | 38／42／12／98／53／5 | 同 | 同 |
| | 装备（武／头／甲／足／饰）· 物品 | 82／152／122／181／201 · [241, 244] | 同 | 同 |
| | 坐标／阵营 · 气力 | (20,23)／`+0x28` 0x10000 pmPlayer · 0（受击 +6：6 → 12 → 18） | (20,23)／player_controlled · 0（`StaminaRules` 受击 +6） | 同 |
| 出口守卫 023（record 17） | 等级／HP | L1／28/28 | L1／28/28 | 同 |
| | 四维／攻／防／速／命中／魔攻／移动 | 15/14/9/14／45／36／14／96／17／5 | 同 | 同 |
| | 装备 · 物品 | 1／152／124／181 · [249] | 同装备 · 随机携带品（carry 表 [246,241,247,248,249] 抽一件） | 携带品随机 |
| | 阵营 · 实例字 | 0x20000 pmEnemy（`+0xa0` \|= 8，obj_Data9 互换）· find_range 8、wait_round 8（首控剩 7，待機后 6，第 3 回合 5）、find_type 3、ai_call_range 4、ai_lock 60 | enemy_ai · `evef_instance` find_range 8／wait_round 8／调级 0/0；`ai_wait_remaining` 7／6／5 | 同 |
| | 第 1–3 回合 | (30,36) 不动 | 不动 | 同 |
| 脚本追兵 023 ×2（`actInsertObject`） | 等级／HP／四维／攻／防／速／魔攻 | L1（`+0x1f8` 0/0：`actSetPrevInsertObjectAdjustLevel,0,0` 已消费）／28/28／15/14/9/14／45／36／14／17 | L1／28（`script_insert.adjust_level [0,0]`） | 同 |
| | 物品 | [246]／[249] | 随机 | 携带品随机 |
| | AI 实例字 | find_range 80、wait_round 0、find_type 3、ai_call_range 4、ai_lock 60（无 record 17 实例字） | find_range 80、wait 0 | 同 |
| | 首控前位置（速 14 先于 緹娜 12） | (29,24) → (25,23)；(27,23) → (23,22) | (26,22)；(23,22)（5 个种子相同） | #1 差在最短路平局次序（provisional），步数相同 |
| | 待機 #1 后 | (23,22) 守卫到 (21,23) 命中 9（36 → 27，守卫 exp 9／气力 3）；(25,23) 守卫到 (21,22) 未攻击 | (21,23) 命中 8／9／8／11／11；(21,22) 未出手 | 落格同，伤害同区间 |
| | 待機 #2 后 | (21,22) 守卫到 (19,23) 命中 7（27 → 20）；(21,23) 原地命中 13（20 → 7，exp 累计 21／气力 6）；緹娜 7/36、气力 18 | (20,22) 命中 12／8／8／7／28（暴击）；(21,23) 命中 8／11／14／9／–；緹娜 8／8／6／9／0 | #1 在西侧或北侧（都贴身），伤害同区间 |
| | 反击 | 三击都没有反击 | 种子 1 反击一次 9（`attack_back` 12） | 概率事件 |
| WINFAIL 增援 ×2 | 模板／出场 | `obj_Story_Level53_Enemy23`（与追兵同符号）；(−32,480)→(5,18)、(−32,960)→(1,30) | `script_actor_templates` → `level53_enemy23`（PLAYERS 023 默认 AI）；(5,18)／(1,30) | 同 |
| | 时机 | `actCheckRoundNumber 5／7` 在第 5／7 回合第一个行动后成立（[original_round_display](../../static_reverse/original_round_display.md)） | 同；下一回合才首次行动 | 插入单位当回合能否行动未测（provisional） |
| | 调级／AI 字 | 0/0 → L1；AI 字与 STORY 插入同（共用 ACTION.H token 表与脚本 VM `0x450840`，static-derived） | L1／28；find_range 80、wait 0 | 同 |

`0x4c1e8c` 在四份快照里始终为 1，不能当回合计数用（negative-evidence）。

### static-derived：追击、气力、hp_level

- 追击：AI 过程 `0x43ede0` state 0xb sub 0（`0x440d5c`–`0x440d84`）在 `0x40fb20` 找不到本回合可攻击站位时调 `0x4111a0(actor, 目标+4, 目标+8, 0x12, +0x12c)`，与固定点行走同一条 `0x411080` 精化链；本关路线单调，精化链落格与最短路前缀相同；`0x40d800` 的 80% 拒绝只数 `mask|0x4000`，WRD 0xff 悬崖不带 0x4000（[original_movement](../../static_reverse/original_movement.md)），路线上没有一格凑到 ≥3。
- 气力：`0x40e590`：受击 +6，半血以上重击 +8；月花圓舞 20 ST。
- `0x448840` 的 HP 公式含 `hp_level` 项，只在 live `+0x28 & 0x10000`（pmPlayer）时取等级；`0x407ec0` 在刷新前按 obj_Data9 把 023 由 pmPlayer 换成 pmEnemy，所以原版 L1 023 敌人 28 HP（PLAYERS 模板刷出 29）。

### runtime-measured：重制自动对局

同一交接（从 51／52 走来的 carry，緹娜 用关卡模板），`HSL_RNG_SEED=1..5`、lookahead，`HSL_AUTOPLAY_STAT_SCALE` 在首控时放大緹娜 四维：

| 档 | 緹娜 HP／速／攻／防 | 种子 1–5 | 胜 |
| --- | --- | --- | --- |
| 1.0 | 36／12／38／42 | 败 14、**胜 13**、败 13、败 16、败 13 | 1/5 |
| 1.1 | 40／13／39／43 | 胜 18、胜 18、胜 17、胜 19、胜 18 | **5/5** |
| 1.25 | 43／15／40／45 | 默认驾驭器在第 11 回合判 `stalemate_no_contact`（快于追兵、一路未交手）；`STALEMATE_ROUNDS` 放宽后胜 17、17、17、16、17 | **5/5** |

1.0 输因：① 5 个种子走到 (25,35) 前都只挨 2 击（12 ST），只有种子 2 靠一次反击（+3）与第 12 回合再挨一击攒到 ≥20 ST，月花圓舞一发打死守卫（28）、第 13 回合逃出；种子 1／3／5 第 12 回合没有 special 候选、只能普攻守卫（20／未命中／9），第 13 回合被三面夹击；种子 4 先挨守卫一击（12，剩 7 HP）只好喝药，之后 special 只打出 21。② 4 个输掉的种子 `magic`＝0：19 MP（水系回復 6 MP 回 20 HP，可放三次）到死未用；种子 1／3／5 走进守卫圆域 (23,35) 之后才喝药。③ special 按确定性中点估算（种子 1 第 13 回合估 84 伤害、3 杀，守卫先喝回復藥后仍剩 4 HP）。增援在 5 个种子里从未打到緹娜，致死的是两名追兵与出口守卫。

## 重制接线

- `content/battles/battle_053.json`（`level_battle:53`）：`rule_adapter: winfail`，`WinfailScenarioRules.victory_state` 把 `actCheckPlayerArrivePos` 解释为 `victory_escape`；campaign 53 为 `party: separate`，队伍 `{tina: 2}`。
- 追兵：`tools/hsltools/levels/scenario.py` `story_inserts` 解析 `actSetPrevInsertObjectAdjustLevel`，写 `script_insert.adjust_level [0,0]`；`InitialRosterGrowthRules` 把它作为 insertion 传给 `ReinforcementGrowthRules.prepare`；`BattleOpeningCoordinator` 把该 kind 列为只记录（装配预烤）。
- `hp_level`：`JobStatsRules.base_values(growth, attrs, level, side_mask)`，`ProgressionRules.refresh_growth_stats` 传 `ActorRoleRules.side_mask(unit)`（安装后的 `player_mode`，无则按 role 隐含侧）；`run_entry_growth_tests.adjust_level_zero_story_and_runtime`、`run_job_stats_tests.live_side_hp_level` 以本包数值为断言。
- 自动对局逃脱：`tests/support/AutoplayBrain.gd` 的逃脱候选按步行距离（`_escape_field`，从出口四格洪泛的地形代价场）、`VALUE_ESCAPE_STEP` 12／格、`_escape_strike`／`_move_then_wait`、`_pursuers_reaching`、`_reach_exempt`（kills>0 的方案必进模拟）。

## 复现

原版侧不可再生：原版侧唯一记录。重制侧 `HSL_AUTOPLAY_LEVELS=53 HSL_AUTOPLAY_BRAIN=lookahead tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`。

## 边界

- WINFAIL 插入单位当回合能否行动未测（provisional；若能，原版只会更难）；替换证据是一趟原版第 5 回合观察。
- 首控时 (26,22) 对 (25,23)、第 3 回合 (20,22) 对 (19,23)：`AINavigationRules` 已标注的最短路平局次序（provisional），步数相同。
- 023 一格随机携带品：原版 pmEnemy 出生时 `0x407c86` 按 PLAYERS `carry_item` 取候选表逐项 `rand(101)`、抽全局流（[battle_reward_inputs](../../static_reverse/battle_reward_inputs.md)「结论」），原版 [249]／[246] 都在 023 的候选表内；重制同表同流抽，单局结果随流而异，不影响胜负。
- `obj_Story_Block` 在 (20,21) 未建模碰撞：在北侧，不在西行路线上。
- 原版只到第 3 回合菜单；原版里人能否逃出、增援之后的交手无样本。
- 自动对局的气力规划、喝药时机、魔法回复从不使用、special 中点估算与逃脱关的僵局判定属自动对局策略，不是规则。

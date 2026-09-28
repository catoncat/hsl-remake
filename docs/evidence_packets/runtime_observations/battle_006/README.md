# 席達鎮（level 6）：正式战斗、原版开局 27 名单位对照与自动对局检验

> evidence: runtime-measured: 重制窗口化运行、原版 6 关开局全部单位读出（回憶錄 预设 level06_pre_battle 经酒馆事件进关）; resource-derived: STORY006／WINFAIL006／EVEF; static-derived: 安装不查地形（0x45e307／0x407cc0）; provisional: 敌人随机调级与携带品的逐项对照 · status: live · functions: 0x407cc0, 0x42bd50, 0x45e307 · tools: capture_battle_review.gd, hsl_original_probe_units.py, hsltools/levels/battle.py, play_original.sh, run_battle_sweep_tests.gd, run_script_wait_tests.gd, test_hsl_level_battle.py, test_hsl_opening_positions.py · updated: 2026-09-28

## 结论

- 原版经预设读档、酒馆事件 23 进入第 6 关时，由原版本机安装全部 27 名单位；村民 061_1 装在 0xff 悬崖格 (25,15)，因为安装路径不查地形（runtime-measured；static-derived）。
- 重制 `content/battles/battle_006.json`（`level_battle:6`）的 27 名单位出场格、等待回合、装备、move 与原版逐格一致，调级用同一 PLAYERS 参数；胜负由 `WinfailScenarioRules` 现场解释 WINFAIL006（runtime-measured 对照）。
- 差异：敌人等级与携带品是各一次随机抽样，只比较了分布（provisional）；原版第 1 回合之后的行动未采样。

## 证据

### resource-derived：组装输入

- 27 名单位：`obj_Story_Player1–4` 安装的四个受控槽（雷歐納德／緹娜／琥／漢克斯，北门走入后的 STORY 终点 (23,8)／(22,6)／(20,7)／(21,9)）、12 名村民（PLAYERS `pmNPCPlayer` → friendly_ai）、7 名 EVEF 士兵＋开场插入的 3 名士兵与隊長（`actSetPrevInsertObjectWaitRound 3`）。
- WINFAIL006：win0＝第 5 回合前击败隊長（士兵撤退 → 对白 959–961／790 → `[6,62]`）；event0 第 5 回合撤 win0 换 event1（隊長倒下后 6 名士兵＋第二隊長自 (896,928) 增援，标出 (992..1088,864) 四格）；win1＝第二隊長倒下；win2＝雷歐納德 到达标格；fail＝雷歐納德 阵亡；event2 第 2 回合对白。
- 两个 EVEF 寶藏（record 52／53）的 override words：[205 烈炎戒指, 253 力之源]、[255 魔之源, 210 黃金首飾]（复制例程 `0x42bd50` 见 [original_treasure](../../static_reverse/original_treasure.md)）。

### static-derived：安装不查地形

EVEF 记录 → `0x45e307` 把 X／Y 原样写进对象 `+4／+8`；敌方初始化 `0x407cc0`（`0x407d1a..0x407d4e`）与玩家安装 `0x4080b0` 只做 `(v & ~31) + 16` 取格心；随后 `0x411a30` 把占位侧位 OR 进该格地图字——全程没有地形测试或找空格（[actor_placement_initialization](../../static_reverse/actor_placement_initialization.md#install-has-no-terrain-test)）。起点在 0xff 格的单位只能在相连的 0xff 格上移动、走不下悬崖（[original_actor_traversal](../../static_reverse/original_actor_traversal.md#起点在0xff格lane-r5-l4c2026-09-25)）。

### runtime-measured：原版开局（原版 v1.06／Wine）

路线：`tools/play_original.sh` 把生成存档 `level06_pre_battle`（[original_save_format](../../static_reverse/original_save_format.md)；队伍抄自 playtest kit 的第 6 关入口 `memoir_05`）装进 回憶錄 第 1 行 → 标题「戰場記錄」→ 战场 Esc →「讀取回憶錄」第 1 行（席達鎮 等級08 4:00）→ 事件 19 对白 → 席達鎮 城镇选单 → 酒館 → 沃斯菲塔士兵（TOWNDEF 23 `teSetNextPlayLevelEvent 6,6`）→ STORY006 → 宣戰 卡。宣戰 卡在屏时（第 1 回合，战斗内尚无输入）用只读 `tools/hsl_original_probe_units.py` 读出全部 live 单位：[original_units.json](original_units.json)（AI 字按 [original_ai_navigation](../../static_reverse/original_ai_navigation.md) 的载入偏移从 `record_hex` 解出）；随后是胜负条件卡「勝利條件：打倒沃斯菲塔兵隊長／失敗條件：雷歐納德死亡」。

| 帧 | 内容 |
| --- | --- |
| original_battle_open.png（原版帧见私有档案：`runtime_observations/battle_006/original_battle_open.png`） | 原版 STORY006 结束、宣戰 卡：北门广场，士兵已由原版本机安装 |
| original_winfail_card.png（原版帧见私有档案：`runtime_observations/battle_006/original_winfail_card.png`） | 原版胜负条件卡 |

| 组 | 原版 | 重制（`battle_006.json`） | 同／异 |
| --- | --- | --- | --- |
| 队伍 4 人 | 001 L8 41 HP (23,8)；002 L5 39 HP 36 MP (22,6)；003 L7 43 HP (20,7)；004 L8 52 HP (21,9) | 同格；等级／HP／装备由战役 carry 覆盖 | 格同；数值同源 |
| 村民 12 名 | 5×062 (22,3)(15,9)(18,7)(12,13)(14,13)，L4–6、76–89 HP；7×061 (25,15)(21,5)(19,7)(17,10)(15,14)(12,17)(15,23)，L4–5、70–78 HP；阵营字 `0x30000`；find_range 20、ai_call_range 6 | 同 12 格，061_1 站在 (25,15) | 同 |
| 士兵 10 名（023） | EVEF 7 名 (15,16)(17,17)(15,18)(13,19)(23,16)(21,15)(23,14)，前两名 wait_round 2，其余 0；开场插入 3 名 (28,7)(27,9)(29,9)，wait 0；L6–9、53–69 HP；武器 1（長劍）、move 5；find_type 3、find_range 80、ai_call_range 4、ai_lock 60；携带品 248／247／246／241 各有 | 同 10 格、同 wait、同武器、同 move | 格／wait／装备同 |
| 隊長（024） | (31,8)，L9、113 HP、武器 41（長槍）、move 4、wait_round 3、携带 241×2 | (31,8)、長槍、move 4、`opening_wait_round 3` | 同 |

### runtime-measured：同一队伍的数值对照（重制种子 1）

重制侧：同一 `memoir_05` 用 `HSL_AUTOPLAY_HANDOFF` 启动，只读探针在首控时转储全部单位。

| 项 | 原版 | 重制（种子 1） | 同／异 |
| --- | --- | --- | --- |
| 调级来源 | 每个对象出生时一次，中心＝队伍均级（8/5/7/8 → 7），PLAYERS 参数 023 [18,2]、024 [24,2]、061／062 [3,0]（static-derived，见 [battle_005](../battle_005/README.md)） | `InitialRosterGrowthRules` 同参数，`party_levels [8,5,7,8]` | 同 |
| 士兵 023 等级 | 9/7/6/6/8/6/7｜9/7/8（和 73） | 9/6/7/5/8/8/6｜7/8/5（和 69） | 同分布、不同掷点 |
| 同级士兵数值 | L9 66 HP 攻 69 防 47；L6 55／53 HP 攻 59／60 防 43 | L9 66 HP 攻 68 防 47；L6 55／52 HP 攻 59／60 防 43 | 同（差值在调级随机增益内） |
| 隊長 024 | L9 113 HP 攻 78 防 75 速 18，wait 3 | L6 98 HP 攻 68 防 71 速 16，wait 3 | 同公式，原版这次掷高 3 级 |
| 村民 | L4–6，70–89 HP | L4–5，70–84 HP | 同分布 |
| 敌人携带品 | 士兵带 241／246／247／248 之一，隊長 241×2 | 士兵带 241／246／248 之一，隊長 241×1 | 同一机制（`0x407cc0`）各抽一次 |
| 队伍 | 雷歐納德 41 HP 攻 94 防 57；緹娜 39 HP 36 MP 防 44 | 雷歐納德 40 HP 攻 91 防 56；緹娜 39 HP 30 MP 防 43 | 预设替两人分配了重制未分配的 5 点（原版记录无未分配点字段），重制玩家分配后相同 |

### runtime-measured：自动对局检验

`memoir_05`、`HSL_AUTOPLAY_BRAIN=lookahead`、`HSL_AUTOPLAY_STAT_SCALE` 在首控时放大受控单位四维、`HSL_RNG_SEED=1..5`，15 局共 5.5 分钟：

| 档 | 种子 1–5（结果 回合） | 胜 |
| --- | --- | --- |
| 1.0 | 败 4、败 18、败 4、败 2、败 12 | 0/5 |
| 1.1 | 败 4、败 8、败 11、败 5、败 6 | 0/5 |
| 1.25 | 败 9、**胜 15**、**胜 16**、**胜 17**、败 17 | 3/5 |

胜局都在第 15 回合后打倒第二隊長（win1），没有一局在第 5 回合前打倒第一个隊長；雷歐納德 在第 2～4 回合被围死——主角风险按计划格估算，比他先动的敌人打的是当前格。开局层面规则与原版一致，输因在自动对局策略；直接打队长即胜是实玩观察（user-hypothesis：重制可能比原版容易）。

### runtime-measured：重制窗口化回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 首次控制：27 名单位、4 名受控、`interaction=action_menu` |
| [win-dialogue-959.png](win-dialogue-959.png) | 强制胜利后 win0 演出：雷歐納德 对白 959 |
| [result.png](result.png) | 结果页 `victory_boss`（`win_0`），交接 `story_062.json` |

[review_manifest.json](review_manifest.json)：11 帧（开场对白 950–952、首次控制、胜利段对白 958–961／790、结果页）。

## 重制接线

- `python3 tools/hsl.py generate level_battle:6`（`tools/hsltools/levels/battle.py`）从开场预览 `story_006.json`＋战斗 seed＋来源模板（`first_battle.json` 的 001／023／024、`content/generated/hsl/actors/002|003|004|061|062.json`）组装；村民 `pmNPCPlayer` → friendly_ai；士兵 enemy-process 物件 → enemy_ai。
- 安装点落在不可站格时原样保留并记 `position_source.install_on_blocked_cell`；STORY 走位终点照原版先经 `0x44fbd0` 修正、再走 `0x4111d0` 寻路链并在所站格提交停格（生成器 `script_walk_stop`，static-derived，见 [original_script_walk_path](../../static_reverse/original_script_walk_path.md) §结论）。同类安装点全游戏共 88 名（以遭遇战为主）。
- 隊長等待经 `ScriptWaitRules.initial_source` 按符号计数落为等待 3 回合；增援用 `script_actor_templates`（obj_Story_Level6_Enemy23／24 → 023／024 模板）运行时创建；寶藏写入 `content/generated/hsl/treasures/battle_006.json`。
- 四个受控槽组装时取模板基线，实际进入时由战役 carry 按 id 覆盖。

## 复现

原版侧不可再生：原版侧唯一记录。重制侧 `python3 -m unittest tools.test_hsl_opening_positions`（第 5、6 关原版开局逐格比较；消融按旧规则挪位只差 061_1）。

## 边界

- 敌人等级、HP 与携带品是一次随机抽样，只比较分布（provisional）。
- 原版第 1 回合之后的行动、伤害与第 5 回合增援没有运行时样本；读出时刻在首控之前。
- 原版里 061_1 之后的位置未采样。
- 原 `obj_Story_PlayerN` 对不存在槽位的处理未定位。隊長等待已由原指令确定：setter 把参数原值写进 `+0x1b8`，AI 入口每次先减一（[original_script_wait.md](../../static_reverse/original_script_wait.md)「原指令结论」）；增援落点经 `0x44fbd0` 修正（[original_script_entry.md](../../static_reverse/original_script_entry.md)「结论」）。
- 强制胜利夹具只证明流转，不证明 AI、平衡或原版节奏。

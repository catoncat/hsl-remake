# 席達鎮（level 6）：正式战斗——通用组装器的首个关卡

> evidence: runtime-measured: 重制窗口化运行、原版 6 关开局全部单位读出（lane R5-L6，回憶錄 预设 level06_pre_battle 经酒馆事件进关）; resource-derived: STORY006／WINFAIL006／EVEF; static-derived: 安装不查地形（0x45e307／0x407cc0）; provisional: 敌人随机调级与携带品的逐项对照 · status: live · functions: 0x407cc0, 0x42bd50, 0x45e307 · tools: capture_battle_review.gd, hsl_original_probe_units.py, hsltools/levels/battle.py, play_original.sh, run_battle_sweep_tests.gd, run_script_wait_tests.gd, test_hsl_level_battle.py, test_hsl_opening_positions.py · updated: 2026-09-25

记录的是 **Godot 重制版**的实际运行（`tests/capture_battle_review.gd -- --level=6`，窗口化，remake pacing），不是原 EXE 现场；末节「原版开局」才是原 EXE 现场读出。原 STORY006／WINFAIL006 的 token 顺序、EVEF 编队、寶藏内容为 resource-derived；走位／镜头时钟、结束卡文案与强制胜利夹具是重制读法，不能据此声称原版等价。

## 入口

大地图 席達鎮 酒馆事件 23（`teSetNextPlayLevelEvent 6,6`）现进入 `content/battles/battle_006.json`，由 `python3 tools/hsl.py generate level_battle:6` 从开场预览（`story_006.json`：编译好的开场、绑定、资源、EVEF cast）＋战斗 seed（STORY 走位终点、winfail 脚本、物件表）＋已审核来源模板（`first_battle.json` 的 001／023／024、`content/generated/hsl/actors/002|003|004|061|062.json`）组装：

- 27 名单位：四个由 `obj_Story_Player1–4` 安装的受控槽（雷歐納德／緹娜／琥／漢克斯，北门走入后的 STORY 终点 (23,8)／(22,6)／(20,7)／(21,9)）、12 名村民（PLAYERS `pmNPCPlayer` → friendly_ai，沿用 level 1 读法）、7 名 EVEF 士兵＋开场插入的 3 名士兵与隊長（enemy-process 物件 → enemy_ai；隊長 `actSetPrevInsertObjectWaitRound 3` 由开场时间线经 `ScriptWaitRules.initial_source` 落为等待 3 回合——该函数此前按全局序号查 `<symbol>/insertN`，混合符号的开场会丢失等待，现改为按符号计数）。
- 村民 `actor061_1` 的 EVEF 位置 (25,15) 是 0xff 悬崖格；原版照样装在该格（runtime-measured，下节），因为安装路径不查地形（static-derived，[安装不查地形](../../static_reverse/actor_placement_initialization.md#install-has-no-terrain-test)）。lane R5-L4b 起重制同样站在 (25,15)（`position_source.install_on_blocked_cell`）；此前组装器把它挪到最近可用格 (24,14)。
- 胜负全部由 `WinfailScenarioRules` 现场解释 WINFAIL006：win0＝第 5 回合前击败隊長（士兵撤退→对白 959–961／790→`[6,62]`）、event0 第 5 回合撤 win0 换 event1（隊長倒下后 6 名士兵＋第二隊長自 (896,928) 增援，并标出 (992..1088,864) 四格）、win1＝第二隊長倒下、win2＝雷歐納德 到达标格、fail＝雷歐納德 阵亡、event2 第 2 回合对白。增援用 `script_actor_templates`（obj_Story_Level6_Enemy23／24 → 023／024 模板）在运行时创建。
- 两个 EVEF 寶藏（record 52／53）的内容取自 seed 新记录的 8 个 override words（[205 烈炎戒指, 253 力之源]、[255 魔之源, 210 黃金首飾]），写入 `content/generated/hsl/treasures/battle_006.json`（原复制例程 0x42bd50 的压缩读法见 [宝箱证据](../../static_reverse/original_treasure.md)）。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场后首次控制：27 名单位、4 名受控、`interaction=action_menu` |
| [win-dialogue-959.png](win-dialogue-959.png) | 强制胜利后 win0 演出：雷歐納德 对白 959（士兵撤退后） |
| [result.png](result.png) | 结果页：`victory_boss`（`win_0`），下一步交接到 `story_062.json` |

[review_manifest.json](review_manifest.json) 是该次窗口化运行的记录（11 帧：开场对白 950–952、首次控制、胜利段对白 958–961／790、结果页）。自动验证：`tests/run_battle_sweep_tests.gd`（全部注册正式战斗：开场→首次控制→强制胜利→交接，含 level 6 的编队／等待回合／寶藏断言）、`tests/run_script_wait_tests.gd`（隊長等待 3 回合）、`tools/test_hsl_level_battle.py`。

## 边界

- 强制胜利夹具（击倒全部存活敌军再结算）只证明流转，不证明 AI、平衡或原版节奏；真实对战尚无实玩回执。
- 队伍来源：四个受控槽在组装时取模板基线，实际进入时由战役 carry 按 id（leonard／tina／hu／hanks）覆盖；漢克斯 在 level 3 仍为预览（略過）时不在 carry 中，则以模板基线出场。
- 原 `obj_Story_PlayerN` 对不存在的槽位如何处理、原隊長等待与增援落点的整除读法未定位。

## 原版开局（lane R5-L6，2026-09-24）

**路线（runtime-measured，原版 v1.06／Wine）。** `tools/play_original.sh` 把生成存档 `level06_pre_battle`（[原版存档格式](../../static_reverse/original_save_format.md)；队伍抄自重制 playtest kit 的第 6 关入口 `memoir_05`）装进 回憶錄 第 1 行并启动原版 → 标题「戰場記錄」→ 战场上按 Esc 开系统选单 →「讀取回憶錄」→ 第 1 行（席達鎮 等級08 4:00）→ 事件 19 的 琥／雷歐納德 对白 → 席達鎮 城镇选单（武器店／護甲店／道具店／酒館）→ 酒館 → 侍女招呼 → 酒馆选单（酒館老闆／年輕人／沃斯菲塔士兵）→ 沃斯菲塔士兵（TOWNDEF 23 `teSetNextPlayLevelEvent 6,6`）→ STORY006 → 宣戰 卡。宣戰 卡在屏时（第 1 回合、战斗内还没有任何输入）用只读 `tools/hsl_original_probe_units.py` 读出全部 live 单位：[original_units.json](original_units.json)（AI 字按 [AI 导航包](../../static_reverse/original_ai_navigation.md) 的载入偏移从 `record_hex` 解出）。随后出现胜负条件卡「勝利條件：打倒沃斯菲塔兵隊長／失敗條件：雷歐納德死亡」，再按空格即首控。

| 帧 | 内容 |
| --- | --- |
| original_battle_open.png（原版帧见私有档案：`runtime_observations/battle_006/original_battle_open.png`） | 原版 STORY006 结束、宣戰 卡：北门广场，沃斯菲塔士兵已由原版本机安装在场 |
| original_winfail_card.png（原版帧见私有档案：`runtime_observations/battle_006/original_winfail_card.png`） | 原版胜负条件卡 |

**读出的开局（27 名，与重制 `battle_006.json` 同样 27 名）。**

| 组 | 原版 | 重制（`content/battles/battle_006.json` 组装值） | 同／异 |
| --- | --- | --- | --- |
| 队伍 4 人 | 001 L8 41 HP (23,8)；002 L5 39 HP 36 MP (22,6)；003 L7 43 HP (20,7)；004 L8 52 HP (21,9) | 同格；等级／HP／装备由战役 carry 覆盖（预设即抄自同一 carry） | 格同；数值同源 |
| 村民 12 名 | 5×062 (22,3)(15,9)(18,7)(12,13)(14,13)，L4–6、76–89 HP；7×061 (25,15)(21,5)(19,7)(17,10)(15,14)(12,17)(15,23)，L4–5、70–78 HP；阵营字 `0x30000`；find_range 20、ai_call_range 6 | 同 12 格（R5-L4b 前 061_1 被挪到 (24,14)） | R5-L4b 起一致：安装不查地形，061_1 站在 (25,15) |
| 士兵 10 名（023） | EVEF 7 名 (15,16)(17,17)(15,18)(13,19)(23,16)(21,15)(23,14)，前两名 wait_round 2，其余 0；开场插入 3 名 (28,7)(27,9)(29,9)，wait 0；L6–9、53–69 HP；武器 1（長劍）、move 5；find_type 3、find_range 80、ai_call_range 4、ai_lock 60；携带品 248／247／246／241 各有 | 同 10 格、同 wait（EVEF 覆盖 2／2）、同武器、同 move | 格／wait／装备同；等级与携带品是随机抽样，需重制首控探针对照 |
| 隊長（024） | (31,8)，L9、113 HP、武器 41（長槍）、move 4、wait_round 3、携带 241×2 | (31,8)、長槍、move 4、`opening_wait_round 3` | 同 |

结论（第 ① 项）：**预设读档后，第 6 关由原版本机安装全部敌人开始**（与 5 关 `entry_level` 直进的负结果不同，这条路走的是原版自己的酒馆事件）。开局格、等待回合、装备与重制一致，唯一的格差是村民 061_1（R5-L4b 已按原版改正，见下「R5-L4b 复核」）。

**边界。** ① 敌人等级、HP 与携带品是一次随机抽样；与重制的逐项数值对照、首回合行动与合格玩家检验属第 ② 项，另记。② 061_1 的 (25,15)：原版单位站在该格，安装时不挪位（R5-L4b 从 EXE 读出原因：安装路径没有地形检查）；原版里它之后的位置未采样；静态读法（R5-L4c，[起点在0xff格](../../static_reverse/original_actor_traversal.md#起点在0xff格lane-r5-l4c2026-09-25)，原指令执行）是起点高度参与第一步高差判定，地面单位只能在相连的 0xff 格上移动、走不下悬崖，重制相同。③ 读出时刻在首控之前的 宣戰 卡，之后第 1 回合的行动未采样。

**两趟用时与操作回执。** 第 1 趟 01:10 启动，走到 STORY006 对白时 wineserver 随负责人进程崩溃丢失，游戏成为孤儿进程，只能结束它（我自己启动的 PID）；第 2 趟 01:36:50–01:54:30（17 分 40 秒，超出 ≤10 分钟：光是从标题走到本关就要约 8 分钟，已向负责人报备）。退出用 `wine taskkill /pid <wine pid>`（发 WM_CLOSE，原版正常退出；退出时原版在 SAVES 下新写了 12 字节 `HSL.CFG`，已移出到仓库外备份，SAVES 恢复为原样）。之后 `tools/play_original.sh --restore` 实测一次：`SAVES/HSL00.SAV` 恢复为用户原存档（sha1 `b90bb976…`，与 `m3-saves-backup` 相同），HSL01／HSL02／HSLBAT 始终未被改动。操作上的摩擦：注入的鼠标点击在光标未悬停时先只高亮、第二次才生效；光标已在目标上时一次生效——连点两次会把第二击落到下一个画面上（本趟因此误读过一次 回憶錄 第 3 行、误开过一次新故事，均未写存档）。

## 第 6 关对照：规则缺口还是机器人缺口（lane R5-L6，2026-09-24）

**结论：机器人缺口；开局没有规则缺口。** 同一支队伍（kit `memoir_05`）在重制与原版的开局逐项对上（上节＋下表）；重制 lookahead 机器人原属性 0/5、+10% 0/5、+25% 3/5，而用户实玩重制"直接打队长就赢了"（user-hypothesis：重制可能比原版容易）。机器人输的方式与 B3 记录一致：不在第 1～4 回合主动去打隊長（WINFAIL006 win0 在第 5 回合被删），主角风险按计划格估算、比他先动的敌人打的是当前格，雷歐納德 在第 2～4 回合被围死。原版第 1 回合之后的敌方行动没有采样，所以"原版比重制难还是容易"要靠人玩：`tools/play_original.sh`（见 [PLAYTEST](../../../PLAYTEST.md#对照原版第-6-关)）。

**来源。** 原版：上节 [original_units.json](original_units.json)（runtime-measured，一次抽样）。重制：同一 `memoir_05` 用 `HSL_AUTOPLAY_HANDOFF` 启动，只读探针在首控时转储全部单位（`ignored/l6/probe.gd`，不入库；副本与 15 份对局日志在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-artifacts/R5-L6/`），种子 1。

| 项 | 原版 | 重制（种子 1） | 同／异 |
| --- | --- | --- | --- |
| 出场格、等待回合、装备、move | 见上节 | 同（R5-L4b 起含 061_1） | 同 |
| 调级来源 | 每个对象出生时一次，中心＝队伍均级（8/5/7/8 → 7），PLAYERS 参数 023 [18,2]、024 [24,2]、061／062 [3,0]（static-derived，见 [呼嘯平原 M3 节](../battle_005/README.md)） | `InitialRosterGrowthRules` 用同样参数，`party_levels [8,5,7,8]` | 同 |
| 士兵 023 等级 | 9/7/6/6/8/6/7｜9/7/8（和 73） | 9/6/7/5/8/8/6｜7/8/5（和 69） | 同分布、不同掷点 |
| 同级士兵数值 | L9 66 HP 攻 69 防 47；L6 55／53 HP 攻 59／60 防 43 | L9 66 HP 攻 68 防 47；L6 55／52 HP 攻 59／60 防 43 | 同（差值在调级随机增益内） |
| 隊長 024 | L9 113 HP 攻 78 防 75 速 18，wait 3 | L6 98 HP 攻 68 防 71 速 16，wait 3 | 同公式；原版这次掷得高 3 级 |
| 村民 061／062 | L4–6，70–89 HP | L4–5，70–84 HP | 同分布 |
| 敌人携带品 | 士兵带 241／246／247／248 中的一件，隊長 241×2 | 士兵带 241／246／248 中的一件，隊長 241×1 | 同一机制（`0x407cc0` 携带品）各抽一次 |
| 队伍 | 雷歐納德 41 HP 攻 94 防 57；緹娜 39 HP 36 MP 防 44；琥、漢克斯 与重制相同 | 雷歐納德 40 HP 攻 91 防 56；緹娜 39 HP 30 MP 防 43 | 预设把重制未分配的 5 点替两人分配了（雷歐納德 力、緹娜 智；原版记录没有未分配点数字段，见 [原版存档格式](../../static_reverse/original_save_format.md)），所以原版这边略强；重制玩家分配后相同 |

**合格玩家检验**（`memoir_05`、`HSL_AUTOPLAY_BRAIN=lookahead`、`HSL_AUTOPLAY_STAT_SCALE` 在首控时放大受控单位四维、`HSL_RNG_SEED=1..5`，每局 6–117 秒，15 局共 5.5 分钟）

| 档 | 种子 1–5（结果 回合） | 胜 |
| --- | --- | --- |
| 1.0 | 败 4、败 18、败 4、败 2、败 12 | 0/5 |
| 1.1 | 败 4、败 8、败 11、败 5、败 6 | 0/5 |
| 1.25 | 败 9、**胜 15**、**胜 16**、**胜 17**、败 17 | 3/5 |

**怎么读。** 规则与原版在开局层面一致，机器人即使属性 +25% 也只赢 3/5，且都是打到第 15 回合以后（第二隊長 增援出场后再打倒它，win1），没有一局在第 5 回合前打倒第一个隊長。用户实玩的"直接打队长"正是机器人缺的那步：这属于机器人缺口，交 bot lane；重制与原版的难度差另需人玩对照。

**边界。** ① 原版第 1 回合之后的行动、伤害与第 5 回合增援都没有运行时样本（provisional）；一趟 Wine 从标题走到本关就要约 8 分钟，打到第 5 回合要再加一趟，本节不列为待跑 route。② 敌人等级只比较了各一次抽样。③ 061_1 的起始格差已由 R5-L4b 改正（上节）。

## R5-L4b 复核（2026-09-25）

在 R5-L4 合并后的树（`4660d59b`）上复核：差格仍在——`battle_006.json` 的 061_1 为 (24,14)，`position_source.blocked_source_cell = [25,15]`。根因是组装器 `hsltools/levels/battle.py` 的 `nearest_free`：凡源格在重制地形读法里不可站（0xff 高度或 0x74000 旗标）就挪到最近空格。原版没有这一步：

- EVEF 记录 → `0x45e307` 把 X/Y 原样写进对象 +4/+8；敌方初始化 `0x407cc0`（`0x407d1a..0x407d4e`）与玩家安装 `0x4080b0` 只做 `(v & ~31) + 16` 取格心；随后 `0x411a30` 把占位侧位 OR 进该格地图字——全程没有地形测试或找空格（static-derived，[安装不查地形](../../static_reverse/actor_placement_initialization.md#install-has-no-terrain-test)）。

修法在共享生成链：**安装点**（无 STORY 走位的 EVEF／actInsertObject 单位）落在不可站格时原样保留并记 `install_on_blocked_cell`；STORY 走位终点落在不可站格、以及与他人重格时仍用最近空格（provisional，原版走位终点读法另见 [剧情走位路径](../../static_reverse/original_script_walk_path.md)）。检查：`tools/test_hsl_opening_positions.py` 的 `test_level_5_and_6_openings_match_the_original_cell_by_cell` 把第 5 关（`m2-first-control`，13 名）与第 6 关（`l6-open`，27 名）原版实测开局逐格比较全部单位，两关全部一致；消融 `test_ablation_relocating_blocked_install_cells_breaks_the_level6_receipt`（按旧规则挪位）恰好只差 061_1 的 (25,15)／(24,14)。

同一类在全游戏共 88 名安装点单位（遭遇战为主，例如 521–530 回音之谷 地图上方雾谷里的 038／043、504–506 的 蕾特 站在 0x4000 格），见 lane R5-L4b 报告的逐场解释。

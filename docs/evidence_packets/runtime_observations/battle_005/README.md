# 呼嘯平原（level 5）：正式战斗、原版开局对照与自动对局败因

> evidence: runtime-measured: 重制窗口化运行与自动对局、原版 5 关开局全部单位记录与第 1 回合（两趟 Wine）、同一交接 5 种子×3 属性档对局与只待機探针; resource-derived: STORY005／WINFAIL005／EVEF／PLAYERS 036／038; static-derived: 0x406fe0 毒强度与 0x409be0 伤害公式（经重制规则）、0x43ede0 初始化分支的出生调级与 0x40e870 的四个调用点; negative-evidence: 回憶錄 直进战斗关不安装敌军; provisional: 机器人策略、AI 同距落点次序、WINFAIL 插入单位当回合是否行动 · status: live · functions: 0x406fe0, 0x409be0, 0x40e870, 0x43ede0, 0x43f603 · tools: capture_battle_review.gd, hsl_original_control.py, hsl_original_probe_units.py, hsltools/data/original_save.py, hsltools/levels/battle.py, run_autoplay_sweep_tests.gd · updated: 2026-09-28

## 结论

- 原版第 5 关开局 13 名单位的模板、装备、出场格、AI 实例字、第 1 回合唤醒规则与伤害公式可实测读出；敌人出生时调级一次；WINFAIL005 event 0 在第 9 回合插入 6 名 036 与 2 名 038（runtime-measured；static-derived；resource-derived）。
- 重制 `content/battles/battle_005.json` 与原版在这些项上逐项一致，唯一的数值差是随机调级的掷点；同一交接下 lookahead 自动对局原属性 0/5、+10% 2/5、+25% 4/5，输因在自动对局策略（中毒不解、风险模型不计毒发），不是规则缺口（runtime-measured）。
- 差异：AI 同距落点次序、WINFAIL 插入单位当回合是否行动未对齐或未测（provisional）；回憶錄 直进战斗关不安装敌军（negative-evidence）。

## 证据

### runtime-measured：原版开局（原版 v1.06／Wine）

路线：生成存档 `content/generated/hsl/development/original_saves/level05_pre_battle.SAV`（[original_save_format](../../static_reverse/original_save_format.md) 的大地图点预设：WINFAIL001–003 胜段写入，站在 自由都市 米蘭多（点 4），呼嘯平原（点 5，bmpmBattle）未访问；四名队员的等级／经验／四维／装备／物品抄自重制章节自动对局种子 1 的交接）装为 `SAVES/HSL00.SAV`；标题 → 戰場記錄 → 右键系统菜单 → 讀取回憶錄 → 第 1 行 → 米蘭多城镇菜单 → 右键回大地图 → 点橙色标记（大地图（原版帧见私有档案：`runtime_observations/battle_005/original_milando_map.png`））→ STORY005（3 句对白）→ 胜负条件卡 → 雷歐納德 首个行动菜单（首控（原版帧见私有档案：`runtime_observations/battle_005/original_first_control.png`））；玩家只按 待機 四次（第 1 回合后（原版帧见私有档案：`runtime_observations/battle_005/original_after_round1.png`））。每个时点用只读 `tools/hsl_original_probe_units.py` 读全部 live 单位：[original_units.json](original_units.json)（含 0x1fc 记录 hex 与按 loader 偏移解码的 AI 字）。

negative-evidence：用 `entry_level 5`（header 直接写 5 关）进关时，STORY005 照常开场、四名队员记录与生成值逐字段相同，但九名 EVEF 敌军全部未安装（code 0、L1、HP 1/1），雷歐納德 第一次 待機 就触发 WINFAIL005 胜段（`actCheckEnemyTotalNumber,0` → 903／904）回大地图；战斗关须从相邻大地图点点击进入。

| 项 | 原版 | 重制（同一交接首控） | 判定 |
| --- | --- | --- | --- |
| 队伍 4 人 | 001 L7 39 HP 攻 82 防 54 速 19；002 L4 38/30 MP；003 L6 42；004 L7 50；格 (12,9)／(14,12)／(10,11)／(9,10) | 逐字段相同 | 同 |
| 敌军模板／装备／格 | 5×036（爪 33）(12,3)(7,4)(3,3)(3,15)(2,14)；4×038（針 37，毒 0x200000）(28,4)(24,2)(4,2)(6,21)；move 5／6；038 能力位 0x41（`move_fly`＋`no_poison`） | 同；`move_fly`／`no_poison` 由 `ActorTraversalRules`／`StatusApplicationRules` 消费 | 同 |
| 敌军等级（随机调级） | 036：6／5／8／8／4；038：8／8／4／4（和 55） | 036：5／5／6／6／5；038：5／8／7／5（和 52） | 同分布、不同掷点：036 `level_adjust_range 16`／`disp 3`（原始 L2，中心＝队伍均级 6 → 3..9）、038 `19`／`4`（原始 L4 → 2..10，≤4 不升） |
| 同级数值 | L6 036 69 HP 攻 60 防 18；L8 038 94／92 HP 攻 65 防 26；L4 038 66 HP 攻 56 防 21 速 12 魔攻 31 | L6 036 69／69 HP 攻 60／58 防 18；L8 038 94 HP 攻 67 防 26；`original_save_members.calculate` 对原版 L4 038 算出 66／56／21／12／31 | 同（差值在调级随机增益范围内） |
| AI 字 | wait_round 2／0／0／3／2｜3／4／0／4；find_type 3；find_range 80；ai_call_range 4（036）／6（038）；ai_fixed 0；ai_lock 80；ai_check_hp 10／0 | EVEF `wait_round` 覆盖逐单位相同，其余取 PLAYERS 同值 | 同 |
| 第 1 回合谁醒 | (12,3) 与 (3,15) 的 wait 从 2／3 直接归 0 并出动，其余等待者各减 1 | 036_1 与 036_4 以 `nearby_enemy` 醒来，其余减 1 | 同（`0x43f603` 八格圆域近敌：(12,3)→雷歐納德 距 6；(3,15)→漢克斯 dx 6 dy 5，36+25 ≤ 64） |
| 第 1 回合落点 | 036 (12,3)→(12,8) 打 雷歐納德 9；(7,4)→(7,9)；(3,3)→(3,8)；(3,15)→(7,14)；038 (4,2)→(5,7) | (12,3)→(12,8) 打 雷歐納德 6；(7,4)→(7,9)；(3,3)→(5,6)；(3,15)→(5,12)；(4,2)→(4,8) | 2 个同格；3 个差异都是离最近目标同距的落点次序（provisional） |
| 第一击伤害 | L6 036 攻 60 − 防 54 ＝ 6 → 9 | L5 036 攻 54 − 54 ＝ 0 → 6 | 公式一致：`CoreCombatRules.preview_damage`（0x409be0）base 6 的弱段 rand(10)+8 减噪声覆盖 9；base 0 的底段 rand(5)+3 覆盖 6 |

### static-derived＋resource-derived：出生调级与第 9 回合增援

| 项 | 原版 | 重制 | 同／异 |
| --- | --- | --- | --- |
| 出生调级 | 敌方对象过程 `0x43ede0` 首次调用、调用字带 `0x20000000` 时走初始化分支 `0x43eed1..0x43ef35`：清该位、置 `0x100000`，调 `0x407cc0`（站位取整、出手延迟 `rand(24)`、携带品，见 [battle_reward_inputs](../../static_reverse/battle_reward_inputs.md)），再以 live `+0x1f8`／`+0x1fa` 调 `0x40e870`；玩家过程 `0x44341b..0x44347d` 同段；全 EXE 只有四处 `call 0x40e870`（这两处，加上只在 opcode 73 置位时走的 `0x43f3f3`／`0x44392f`），无 jmp 进入 | `InitialRosterGrowthRules`（EVEF）与 `ReinforcementGrowthRules.prepare`（WINFAIL 插入）每个单位出生时调一次 `EntryGrowthRules.propose`；STORY005／WINFAIL005 无 `actAdjustAllPlayerLevel`／`actSetPrevInsertObjectAdjustLevel`，用 PLAYERS 模板参数 | 同 |
| 增援组成 | WINFAIL005 event 0：`obj_Story_Level5_Enemy36` ×6、`obj_Story_Level5_Enemy38` ×2 | `script_actor_templates` 同两符号，套 036／038 模板 | 同 |
| 增援出场格 | 八次 `actWalkPrevInsertObject(Wait)` 终点像素：(224,64) (544,64) (192,640) (768,640) (96,224) (64,576) (896,96) (896,384) | (7,2) (17,2) (6,20) (24,20) (3,7)=038 (2,18) (28,3) (28,12)=038 | 同（像素 ÷ 32） |
| 增援时机 | `actCheckRoundNumber 9` 在第 9 回合第一个行动完成后的扫描成立（[original_round_display](../../static_reverse/original_round_display.md)） | 第 9 回合 漢克斯 行动后插入 | 同；插入单位当回合能否行动未测（provisional） |
| 增援 AI 字 | PLAYERS 默认：find_range 80、wait 0、ai_call_range 4（036）／6（038）（按 53 关 STORY 插入实测推得） | 同 | 同 |
| 毒针（038 的 針，ITEM 37） | `attack_poison`：先查防毒／通用防护，再抽 1..100 ≤25 中毒；强度 `24−rand(9)+rand(9)`＝16..32；持续 `+rand(2)+1`，上限 9；每次行动后扣 `min(hp−1, 强度)`，不致死（[original_weapon_effects](../../static_reverse/original_weapon_effects.md)） | `StatusEffectRules.weapon_status`／`after_action` 同值域 | 同 |

### runtime-measured：重制自动对局败因

同一交接单跑（`HSL_AUTOPLAY_HANDOFF=<level5 hand-off> HSL_AUTOPLAY_BRAIN=lookahead`）在第 15 回合 `defeat_leonard`。雷歐納德 的 HP 线：

| 回合 | 事件 | HP |
| --- | --- | --- |
| 1–7 | 036／038 普攻 6、5、6、6、6、3、4，回合 4 回復藥 22 → 39 | 39 → 20 |
| 10 | actor038_4 普攻 8 | 20 → 12 |
| 11 | 回復藥 → 41；actor038_4 普攻 12 并上毒（强度 20、2 回合） | 12 → 41 → 29 |
| 12 | 移动，行动后毒发 20 | 29 → 9 |
| 13 | 移动，毒发 `min(hp−1, 20)` ＝ 8 | 9 → 1 |
| 14 | 回復藥 → 41；Enemy038 增援普攻 3 | 1 → 41 → 38 |
| 15 | Enemy038 增援普攻 9 再上毒（强度 24、1 回合）；上前击杀 Enemy036（45），毒发 24；Enemy036 增援普攻 14 | 38 → 29 → 5 → 0 |

雷歐納德 带 1 个 解毒草（246）、琥 带 3 个，整场未用：`AutoplayBrain._heal_intent` 只找 `restored_hp > 0` 的物品，风险估值（`hero_risk`／`hero_can_die`）不计毒发。

| 旋钮（同一交接单跑） | 结果 |
| --- | --- |
| 无 | 败，15 回合，3 人倒 |
| `HSL_AUTOPLAY_STAT_SCALE=1.1` | 胜，16 回合，1 人倒 |
| `HSL_AUTOPLAY_STAT_SCALE=1.25` | 胜，15 回合，0 人倒 |
| 章节 `HSL_AUTOPLAY_GOLD=unlimited` | 米蘭多 商店货架封顶（銀劍／水晶杖／巨弓／水晶短刀、鋼鐵頭盔／鋼鐵之靴／鎖子甲、回復藥），与正常金钱同档；本关仍败（第 5 回合） |

另一份交接（雷歐納德 L6 41/16/8/12 39 HP、緹娜 L3、琥 L6、漢克斯 L7，队伍均级 5）按只待機探针转储首控：036 为 3/5/2/5/4、038 为 8/4/8/8（`entry_growth` 036 [16,3]、038 [19,4]）；增援 036 L3/2/4/4/5/4、038 L7/L4。合格玩家检验（`HSL_RNG_SEED=1..5`）：

| 档 | 种子 1–5 | 胜 |
| --- | --- | --- |
| 1.0 | 败 15、败 15、败 15、败 9、败 15 | 0/5 |
| 1.1 | **胜 16**、败 19、败 12、**胜 17**、败 17 | 2/5 |
| 1.25 | **胜 15**、**胜 16**、**胜 16**、败 8、**胜 16** | 4/5 |
| 1.0，雷歐納德 点数改加体质（41/16/8/12 → 29/16/8/24） | 败 13、败 14、败 18、败 18、败 16 | 0/5 |

败局大部分伤害来自第一波：种子 2／3／5 第一波对队伍打 195–290、增援只打 22–70；种子 4 在第 9 回合增援行动前就输。复跑（另一代码树）1.0 档 0/5 逐局相同、1.25 档 4/5（种子 2 提前到第 9 回合胜）。

### runtime-measured：重制窗口化回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 首次控制：13 名单位、4 名受控，行动菜单可用 |
| [win-dialogue-903.png](win-dialogue-903.png)／[win-dialogue-904.png](win-dialogue-904.png) | 强制胜利后雷歐納德／琥的胜利段对白 |
| [result.png](result.png) | 结果页 `victory_optional_clear`、`win_0`，回大地图 |

## 重制接线

- `python3 tools/hsl.py generate level_battle:5`（`tools/hsltools/levels/battle.py`）从 `story_005.json`（开场 timeline、EVEF 绑定、资源、演员清单）＋`battle005_seed.json`（STORY 走位终点、WINFAIL005、地图物件）＋`first_battle.json` 与 `content/generated/hsl/actors/` 组装 `battle_005_level5`：4 名 `player_controlled`、9 名 `enemy_ai`；WINFAIL005 编为 `win_0`、`fail_0`、`event_0`；EVEF 宝箱记录 17 写入 `content/generated/hsl/treasures/battle_005.json`。
- 走位终点照原版：目的格先经 `0x44fbd0` 修正，再走 `0x4111d0` 寻路链、`0x453b90` 在所站格提交停格（static-derived，见 [original_script_walk_path](../../static_reverse/original_script_walk_path.md) §结论，lane SCRIPTWALKPATH／WINFAILWALK）；无走位的安装点原样保留（[actor_placement_initialization](../../static_reverse/actor_placement_initialization.md#install-has-no-terrain-test)）；13 名单位与原版首控逐格一致（`tools/test_hsl_opening_positions.py`）。

## 复现

原版侧不可再生：原版侧唯一记录。重制侧 `HSL_AUTOPLAY_LEVELS=5 tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`。

## 边界

- 原版只跑到第 1 回合末：之后的伤害、中毒命中、中毒强度与增援等级没有运行时样本，毒强度 16..32 是 static-derived。
- 3 个同距落点差异（036 (3,3)／(3,15)、038 (4,2)）与同速次序未对齐（provisional）；替换证据是原版 `0x43f603` 之后的选格循环或更多回合的原版落点样本。
- WINFAIL 插入单位当回合能否行动未测（provisional；若能，只会让原版更难）。
- 敌军等级只各有一次抽样，不比较分布均值；两边公式同源（`EntryGrowthRules.propose`）。
- 强制胜利夹具只证明开场、结果与交接路径。

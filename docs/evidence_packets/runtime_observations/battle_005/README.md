# 呼嘯平原（level 5）：正式战斗、原版开局对照与自动对局败因

> evidence: runtime-measured: 重制窗口化运行与自动对局、原版 5 关开局全部单位记录与第 1 回合（lane M1 两趟 Wine）、同一交接 5 种子×3 属性档对局与只待機探针（M3）; resource-derived: STORY005／WINFAIL005／EVEF／PLAYERS 036／038; static-derived: 0x406fe0 毒强度与 0x409be0 伤害公式（经重制规则）、0x43ede0 初始化分支的出生调级与 0x40e870 的四个调用点（M3）; negative-evidence: 回憶錄 直进战斗关不安装敌军; provisional: 机器人策略、AI 同距落点次序、WINFAIL 插入单位当回合是否行动 · status: live · functions: 0x406fe0, 0x409be0, 0x40e870, 0x43ede0, 0x43f603 · tools: capture_battle_review.gd, hsl_original_control.py, hsl_original_probe_units.py, hsltools/data/original_save.py, hsltools/levels/battle.py, run_autoplay_sweep_tests.gd · updated: 2026-09-24

前三节记录 **Godot 重制版** 的一次窗口化运行（`tests/capture_battle_review.gd -- --level=5`，`runtime-measured`），不是原 EXE 的现场回执；末节「原版对照（lane M1）」是用生成存档把原版带到 5 关开局后读出的现场。STORY005／WINFAIL005 的开场、编队、宝箱记录与脚本顺序来自 `resource-derived` 数据；走位、镜头时钟、结果页文案和强制胜利夹具属于 `provisional` 重制读法。

## 入口

大地图点 5「呼嘯平原」现在进入 `content/battles/battle_005.json`，不再进入产品路径的 `story_005.json` 预览。正式场景由 `python3 tools/hsl.py generate level_battle:5` 从以下 tracked 输入组装：

- `story_005.json` 的开场 timeline、EVEF 绑定、资源和演员清单。
- `battle005_seed.json` 的 STORY 走位终点、WINFAIL005 状态脚本和地图物件。
- `first_battle.json` 与 `content/generated/hsl/actors/` 的已审核演员模板。

场景 `battle_005_level5` 共 13 名单位：4 名 `player_controlled`、9 名 `enemy_ai`。WINFAIL005 的可见状态时间线编译为 `win_0`、`fail_0` 与 `event_0`，本次强制胜利回执解析为 `win_0`。原 EVEF 宝箱记录 17 的物品字写入 `content/generated/hsl/treasures/battle_005.json`，宝箱动作与奖励持久化继续遵循现有重制合同。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 首次控制：13 名单位、4 名受控，行动菜单可用。 |
| [win-dialogue-903.png](win-dialogue-903.png) | 强制胜利后的对白帧：雷歐納德显示胜利段对白。 |
| [win-dialogue-904.png](win-dialogue-904.png) | 强制胜利后的对白帧：琥显示胜利段对白。 |
| [result.png](result.png) | 结果页：`victory_optional_clear`、`win_0`，可回到大地图。 |

捕获 manifest 为 `ignored/battle-005-review/manifest.json`，本次运行记录 8 张截图、首次控制 `units=13`／`players=4`，结果 `win_0`。自动检查包括 `BATTLE_SWEEP_TESTS_PASS battles=13`、`STORY_MODE_WALKTHROUGH_PASS steps=48`、`CAMPAIGN_TESTS_PASS`、`STORY_SCENE_TESTS_PASS` 与 `SCRIPT_WAIT_TESTS_PASS checks=447`。

## 边界

- 强制胜利夹具只证明正式场景的开场、结果和 campaign hand-off 路径，不证明 AI、战斗平衡或原版节奏。
- 开场资源、脚本 token、演员模板和宝箱物品字是 `resource-derived`；完整原作调度、全局随机流和原始墙钟未恢复。
- 若 STORY 走位终点落在重制地形阻挡格，组装器使用记录明确的最近可用格（`provisional`）；无走位的安装点照原版原样保留（static-derived，[安装不查地形](../../static_reverse/actor_placement_initialization.md#install-has-no-terrain-test)）。本关 13 名单位与原版 `m2-first-control` 逐格一致（`tools/test_hsl_opening_positions.py`）。
- 窗口截图只证明本次重制运行的可见状态，不把测试绿或截图升级为原版等价声明。

## 原版对照（lane M1，2026-09-23）

**问题。** B1 之后章节自动对局赢下 51／52／53／1／2／3，停在本关：seed 1 第 12 回合 雷歐納德 阵亡（`defeat_leonard`）。要判定是规则缺口、机器人缺口还是真难。

**路线。** 生成存档 `content/generated/hsl/development/original_saves/level05_pre_battle.SAV`（[原版存档格式](../../static_reverse/original_save_format.md) 的大地图点预设：WINFAIL001–003 胜段写入，站在 自由都市 米蘭多（点 4），呼嘯平原（点 5，bmpmBattle）显示未访问；四名队员的等级／经验／四维／装备／物品抄自重制章节机器人 seed 1 带进本关的 hand-off）装为 `SAVES/HSL00.SAV`；原版 v1.06（Wine）标题 → 戰場記錄 → 右键系统菜单 → 讀取回憶錄 → 第 1 行 → 米蘭多城镇菜单 → 右键回大地图 → 点橙色标记（[大地图](original_milando_map.png)）→ STORY005（3 句对白）→ 胜负条件卡 → 雷歐納德 首个行动菜单（[首控](original_first_control.png)）。玩家只按 待機 四次（[第 1 回合结束后的菜单](original_after_round1.png)）。每个时点用只读 `tools/hsl_original_probe_units.py` 读全部 live 单位记录：[original_units.json](original_units.json)（含原始 0x1fc 记录 hex 与按 loader 偏移解码的 AI 字）。

两趟用时：第 1 趟 02:19:34–02:31:59（12.5 分，超出 ≤10 分钟约 2.5 分；其中约 4 分钟是 Wine 窗口停在已断开的外接显示器 x=1972 上、点击全部落空——此后 `tools/hsl_original_control.py place X Y` 专治此事，见 [tools README](../../../../tools/README.md#原作-runtime-验证)）；第 2 趟 02:34:42–02:41:20（6 分 38 秒，负责人批准的 7 分钟上限内）。原始输出留 `ignored/`。

**第 1 趟的负结果（negative-evidence）。** 旧版预设用 `entry_level 5`（header 直接写 5 关）：STORY005 照常开场，四名队员记录与生成值逐字段相同，但九名 EVEF 敌军的 live 记录全部未安装（code 0、L1、HP 1/1），雷歐納德 第一次 待機 就触发 WINFAIL005 胜段（`actCheckEnemyTotalNumber,0` → 903／904）回大地图。所以战斗关不能这样进；预设已改成站在相邻点、点击进关，结论写进存档格式包。

### 开局逐字段（runtime-measured 原版 vs 重制同一 hand-off 首控）

| 项 | 原版 | 重制 | 判定 |
| --- | --- | --- | --- |
| 队伍 4 人 | 001 L7 39 HP 攻 82 防 54 速 19；002 L4 38/30 MP；003 L6 42；004 L7 50；装备、物品、格 (12,9)／(14,12)／(10,11)／(9,10) | 逐字段相同 | 同（证明预设把重制队伍原样带进原版） |
| 敌军模板／装备／格 | 5×036（爪 33）(12,3)(7,4)(3,3)(3,15)(2,14)；4×038（針 37，毒 0x200000）(28,4)(24,2)(4,2)(6,21)；move 5／6；038 能力位 0x41（`move_fly`＋`no_poison`） | 同模板、同装备、同 9 格、同 move；`move_fly`／`no_poison` 已由 `ActorTraversalRules`／`StatusApplicationRules` 消费 | 同 |
| 敌军等级（随机调级） | 036：6／5／8／8／4；038：8／8／4／4（总和 55） | 036：5／5／6／6／5；038：5／8／7／5（总和 52） | 同分布、不同掷点：PLAYERS 036 `level_adjust_range 16`／`disp 3`（原始 L2，中心＝队伍均级 6 → 3..9）、038 `19`／`4`（原始 L4 → 2..10，≤4 不升）；两边各一次抽样，原版这次更高 |
| 同级数值 | L6 036 69 HP 攻 60 防 18；L8 038 94／92 HP 攻 65 防 26；L4 038 66 HP 攻 56 防 21 速 12 魔攻 31 | L6 036 69／69 HP 攻 60／58 防 18；L8 038 94 HP 攻 67 防 26；`original_save_members.calculate` 对原版 L4 038 四维算出 66／56／21／12／31 逐项相同 | 同：差值只在调级时 `hit_point`／`attack_power`／`speed` 的随机增益（每级 2.5–3.5 HP 等）范围内 |
| AI 字 | wait_round 2／0／0／3／2｜3／4／0／4；find_type 3；find_range 80；ai_call_range 4（036）／6（038）；ai_fixed 0；ai_lock 80；ai_check_hp 10／0 | EVEF `wait_round` 覆盖逐单位相同（2／0／0／3／2｜3／4／0／4），其余取 PLAYERS 同值 | 同 |
| 第 1 回合谁醒 | (12,3) 与 (3,15) 的 wait 从 2／3 直接归 0 并出动，其余等待者各减 1 | 同样 `全员待機` 复跑（`ignored/m1/m1_tmp_allwait.gd.txt`，R14 驱动加 hand-off）：036_1 与 036_4 以 `nearby_enemy` 醒来，其余减 1 | 同（`0x43f603` 八格圆域近敌：(12,3)→雷歐納德 距 6；(3,15)→漢克斯 dx 6 dy 5，36+25 ≤ 64） |
| 第 1 回合落点 | 036 (12,3)→(12,8) 打 雷歐納德 9；(7,4)→(7,9)；(3,3)→(3,8)；(3,15)→(7,14)；038 (4,2)→(5,7) | (12,3)→(12,8) 打 雷歐納德 6；(7,4)→(7,9)；(3,3)→(5,6)；(3,15)→(5,12)；(4,2)→(4,8) | 5 个出动者 2 个同格；3 个差异全是**离最近目标同距**的落点次序不同（provisional，AI 同距 tie-break 未对齐），不改变接敌节奏 |
| 第一击伤害 | L6 036 攻 60 − 雷歐納德 防 54 ＝ 6 → 9 | L5 036 攻 54 − 54 ＝ 0 → 6 | 公式一致：重制 `CoreCombatRules.preview_damage`（0x409be0）在 base 6 的弱段区间 rand(10)+8 减噪声覆盖 9；base 0 的底段 rand(5)+3 覆盖 6 |

结论一：**开局没有规则缺口**。与 53 关（R33 找到两处规则差）不同，本关原版与重制在模板、装备、格、AI 字、唤醒规则与伤害公式上一致；唯一的数值差是随机调级的掷点，而原版这次抽样（总等级 55）比重制（52）更凶。

### 雷歐納德 怎么死的（重制，seed 1 hand-off 单跑，`HSL_M1_TRACE` 临时插桩，未提交）

`HSL_AUTOPLAY_HANDOFF=<level5 hand-off> HSL_AUTOPLAY_BRAIN=lookahead` 单跑在第 15 回合 `defeat_leonard`。`chapter.json` 记的「第 12 回合、緹娜 4／雷歐納德 6／胡 5／漢克斯 7」是 B1 合并树那次章节对局；本 lane 在当前树重跑章节（seed 1，途中多一场 502 遭遇）带进本关的是 雷歐納德 7／緹娜 4／胡 6／漢克斯 7——即预设所抄、本节单跑所用的 hand-off——同样败于 `defeat_leonard`。雷歐納德 的 HP 线：

| 回合 | 事件 | HP |
| --- | --- | --- |
| 1–7 | 036／038 普攻 6、5、6、6、6、3、4（弱段／底段），回合 4 回復藥 22 → 39 | 39 → 20 |
| 10 | actor038_4 普攻 8 | 20 → 12 |
| 11 | 回復藥 → 41；actor038_4 普攻 12 **并上毒**（`status_counters.poison` 强度 20、2 回合） | 12 → 41 → 29 |
| 12 | 雷歐納德 移动，行动后毒发 20 | 29 → 9 |
| 13 | 移动，毒发 `min(hp−1, 20)` ＝ 8（毒不致死，只压到 1） | 9 → 1 |
| 14 | 回復藥 → 41；Enemy038 增援普攻 3 | 1 → 41 → 38 |
| 15 | Enemy038 增援普攻 9 **再上毒**（强度 24、1 回合）；雷歐納德 仍上前击杀 Enemy036（45），行动后毒发 24；Enemy036 增援普攻 14 | 38 → 29 → 5 → 0 |

毒来自 038 的 針（ITEM 37 `attack_poison`，0x409310 命中后 25%）；强度 16..32、每次行动后扣（`StatusEffectRules.after_action`，static-derived 0x406fe0），对 39 HP 的 雷歐納德 一次毒发就是半条命。雷歐納德 自己带 1 个 解毒草（246），胡 带 3 个——**整场一次没用**：`AutoplayBrain._heal_intent` 只找 `restored_hp > 0` 的物品，风险估值（`hero_risk`／`hero_can_die`）不计毒发。

### 合格玩家手段诊断（同一 hand-off 单跑，lookahead）

| 旋钮 | 结果 |
| --- | --- |
| 无 | fail，15 回合，`defeat_leonard`，3 人倒 |
| `HSL_AUTOPLAY_STAT_SCALE=1.1` | **win**，16 回合，1 人倒 |
| `HSL_AUTOPLAY_STAT_SCALE=1.25` | **win**，15 回合，0 人倒 |
| 章节 `HSL_AUTOPLAY_GOLD=unlimited`（整章重走） | 米蘭多 商店的采购与正常金钱下 hand-off 所带的是同一档（武器 銀劍／水晶杖／巨弓／水晶短刀，另有 鋼鐵頭盔／鋼鐵之靴／鎖子甲 与回復藥）：商店货架封顶，钱多买不到更好的；本关仍 fail，第 5 回合 `defeat_leonard`（途中遭遇换成 504，队伍 雷歐納德 7／緹娜 4／胡 5／漢克斯 7）。装备不是瓶颈 |
| `HSL_RNG_SEED=2`／`3` | 与 seed 1 逐行相同（sweep 把 `play_battle` 的 AI 随机种子固定为 1，hand-off 单跑下换 loop seed 不换对局——换种子须走章节 `HSL_CHAPTER_TRIES`；这是 T3 之前的回执——T3 起 sweep 把 `HSL_RNG_SEED` 同时交给 `play_battle`，hand-off 单跑换种子即换对局） |

四维只加 10% 就翻盘，说明差距很薄、不是「原版这个等级本就打不过」。

结论二：**机器人缺口，决策类「状态异常处理」**：(1) 中毒不解（有解毒草不用）；(2) 风险模型不计毒发，中毒的必活单位照样前压挨打；(3) `protect_hero` 不把带毒武器的敌人（038）当作对必活单位的额外威胁。不是规则缺口（开局逐字段一致），也不能称真难（+10% 即胜；原版第一击与抽样等级都不比重制弱，毒规则两边同源 static-derived）。

### 边界

- 原版只跑到第 1 回合末；第 2 回合之后的原版伤害、毒命中与毒强度没有 runtime 样本，毒强度 16..32 仍是 static-derived。
- 3 个同距落点差异（036 (3,3)／(3,15)、038 (4,2)）标 provisional：AI 选格 tie-break 未对齐原版，替换证据是原版 `0x43f603` 之后的选格循环或更多回合的原版落点样本。
- 敌军等级只各有一次抽样，不能比较两边调级分布的均值；两边公式同源（`EntryGrowthRules.propose`）。

## M3 对照（B3 之后：规则缺口还是机器人缺口，lane M3，2026-09-23）

**结论：机器人缺口，没有找到让重制变难的规则缺口。** M1 已经把开局逐字段对上（上节）。本节补上 M1 没覆盖的部分：第 9 回合增援、038 的毒针、B3 最终树的章节交接下的开局，以及合格玩家检验。同一份交接、同一个 lookahead 机器人：原属性赢 0/5，属性 +10% 赢 2/5，+25% 赢 4/5。败局里大部分伤害来自第一波敌人，不是增援：种子 2／3／5 第一波对队伍打了 195–290，增援只打了 22–70；种子 4 在第 9 回合、增援还没行动时就输了。本 lane 没有开 Wine，也没有改 `game/`。

**来源。** 重制侧用 B3 最终合并树章节走查写出的第 5 关交接，副本在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-artifacts/B3/handoffs/snap5/5.json`（雷歐納德 L6 41/16/8/12 39 HP、緹娜 L3、琥 L6、漢克斯 L7，队伍均级 5）。基线 pipeline-line `6358be38`。只按待機的探针是 `ignored/m3/probe.gd`，没有入库，副本在 lane-artifacts/M3：它在首控时转储全部单位（等级、HP、攻、防、速、移动、AI 实例字、`entry_growth` 参数）和速度队列，之后受控单位每回合只按待機，逐条打印 AI 行动，并在新单位出现时转储它；打到第 9 回合用了 `HSL_AUTOPLAY_STAT_SCALE=3.0`，只为让队伍活到增援出现，敌方数值不受影响。原版侧是 M1 的两趟实测（上节），以及本节新做的只读反汇编（hsl01.exe，r2 与 E8／E9／0F8x 全段扫描）。

**逐项对照**

| 项 | 原版 | 重制（snap5 交接） | 同／异 |
| --- | --- | --- | --- |
| 敌人模板、装备、出场格、移动、AI 实例字 | M1 实测，见上节 | 同 | 同（M1） |
| 出生调级的来源 | 敌方对象过程 `0x43ede0` 第一次被调用、调用字带 `0x20000000` 时走初始化分支 `0x43eed1..0x43ef35`：清掉这一位，置 `0x100000`，调 `0x407cc0`（站位取整、出手延迟 `rand(24)`、携带品，见 [战斗奖励输入](../../static_reverse/battle_reward_inputs.md)），然后以 live 记录 `+0x1f8`／`+0x1fa` 调 `0x40e870`。玩家对象过程在 `0x44341b..0x44347d` 有同一段。全 EXE 只有四处 `call 0x40e870`：这两处，加上只在 opcode 73 置位时才走的 `0x43f3f3`／`0x44392f`；没有 jmp 进入（static-derived） | `InitialRosterGrowthRules`（EVEF 单位）和 `ReinforcementGrowthRules.prepare`（WINFAIL 插入）每个单位出生时调一次 `EntryGrowthRules.propose` | 同：每个对象出生时调级一次；STORY005／WINFAIL005 都没有 `actAdjustAllPlayerLevel` 和 `actSetPrevInsertObjectAdjustLevel`，所以用 PLAYERS 模板参数 |
| 首控时敌人等级 | 队伍均级 6（M1 队伍）：036 为 6/5/8/8/4，038 为 8/8/4/4 | 队伍均级 5：036 为 3/5/2/5/4，038 为 8/4/8/8（首控时 `entry_growth` 参数 036 [16,3]、038 [19,4]，origin initial_roster） | 同一公式各抽一次；这份交接的队伍均级低 1，敌人中心随之低 1 |
| 第 1 回合 | (12,3) 与 (3,15) 的 036 醒来出动，(12,3) 那只打 雷歐納德 9（M1） | 036_1 在 (12,3) 醒来走到 (12,8)，打 雷歐納德 6；036_4 从 (3,15) 醒来走到 (5,12)（种子 1，只待機） | 同（伤害在同一区间；落格属于 M1 已记录的同距平局次序，provisional） |
| 增援组成 | WINFAIL005 event 0：`obj_Story_Level5_Enemy36` ×6、`obj_Story_Level5_Enemy38` ×2（resource-derived；**不是** 8 个 038） | `script_actor_templates` 用同样两个符号，套 036／038 模板，共 8 个 | 同 |
| 增援出场格 | 八次 `actWalkPrevInsertObject(Wait)` 的终点像素：(224,64) (544,64) (192,640) (768,640) (96,224) (64,576) (896,96) (896,384) | (7,2) (17,2) (6,20) (24,20) (3,7)=038 (2,18) (28,3) (28,12)=038 | 同（像素 ÷ 32） |
| 增援出场时机 | `actCheckRoundNumber 9`：在第 9 回合第一个行动完成后的那次扫描时成立（[回合显示包](../../static_reverse/original_round_display.md)，static-derived） | 第 9 回合 漢克斯 行动后插入；第 10 回合第一次行动 | 插入时刻相同；原版插入的单位当回合能不能行动**未测**（provisional，与 M2 在 53 关的边界相同；如果能，只会让原版更难） |
| 增援调级 | 出生分支，用 PLAYERS 参数（036 [16,3]、038 [19,4]），中心是队伍均级 | 036 L3/2/4/4/5/4，038 L7/L4（origin source_template，种子 1） | 同 |
| 增援 AI 实例字 | PLAYERS 默认值：find_range 80、wait 0、ai_call_range 4（036）／6（038）；WINFAIL 插入与 STORY 插入共用同一个脚本 VM，按 M2 在 53 关的 STORY 插入实测推得（static-derived） | find_range 80、wait 0、call 4／6 | 同 |
| 毒针（038 的 針，ITEM 37） | `attack_poison`：命中后先查目标的防毒／通用防护，再抽 1..100，≤25 就中毒；强度 `24−rand(9)+rand(9)`＝16..32；持续回合 `+rand(2)+1`，上限 9；每次行动后扣 `min(hp−1, 强度)`，不会毒死。以上都在原指令上执行过（[武器附加效果](../../static_reverse/original_weapon_effects.md)，static-derived）；038 自带 `no_poison`（M1） | `StatusEffectRules.weapon_status`／`after_action` 用同一组值域；机器人有 `cure` 方案（种子 1 用过一次解毒草） | 同（static-derived；原版没有中毒的运行时样本） |

**合格玩家检验**（snap5 交接、lookahead、`HSL_AUTOPLAY_STAT_SCALE` 在首控时放大受控单位四维，`HSL_RNG_SEED=1..5`）

| 档 | 种子 1–5 | 胜 |
| --- | --- | --- |
| 1.0 | 败 15、败 15、败 15、败 9、败 15 | 0/5 |
| 1.1 | **胜 16**、败 19、败 12、**胜 17**、败 17 | 2/5 |
| 1.25 | **胜 15**、**胜 16**、**胜 16**、败 8、**胜 16** | 4/5 |
| 1.0，雷歐納德 重新分配点数（41/16/8/12 → 29/16/8/24：L1 之后的 25 点里拿 12 点加体质；交接里只改这一处） | 败 13、败 14、败 18、败 18、败 16 | 0/5 |

**怎么读。** 规则与原版一致，所以对同一支队伍来说，重制和原版一样难。差距在机器人：+25% 就能赢 4/5，但余量比 53 关（+10% 就 5/5）薄。这支队伍本身是机器人一路打出来的：緹娜 只有 L3，把队伍均级拉低，敌人因此反而更弱；雷歐納德 把所有点数都加在力量上，只有 39 HP。点数改加体质也没用（0/5），所以 HP 分配不是关键。M1 那份更早的交接（雷歐納德 L7）在 +10% 时单种子能赢。败因的细节交给 bot lane，B3 的报告里已经有第 9 回合增援与毒的描述；本 lane 的日志补了一点：第一波的伤害量才是主体。

**复核（lane R5-L6，2026-09-24）。** 在合并了 R5-L1／L2／L5 的树（`5b4bc9fb`，基于 pipeline-line `8d257490`）上，用同一份 snap5 交接和同一组参数重跑了 1.0 与 1.25 两档。1.0 为败 15、败 15、败 15、败 9、败 15，**0/5**，回合数与上表逐局相同。1.25 为胜 15、**胜 9**、胜 16、败 8、胜 16，**4/5**，只有种子 2 从第 16 回合提前到第 9 回合取胜。本节结论不变：机器人缺口，没有规则缺口。十局共 3 分钟，日志在 `~/.pi-worktrees/hsl-pipeline/ignored/lane-artifacts/R5-L6/l5/`。本 lane 没有为第 5 关另开 Wine：原版只有第 1 回合的样本（M1），要看第 9 回合增援之后，一趟就会超过 10 分钟。

**边界。** ① WINFAIL 插入的单位当回合能否行动：provisional。② 同距落点与同速次序：provisional（`CoreTurnQueue` 注明同速平局未解）。③ 原版在第 1 回合之后的伤害、中毒命中率、增援等级都没有运行时样本；一趟 Wine 要打到第 9 回合以后，不划算，本节不列为待跑 route。

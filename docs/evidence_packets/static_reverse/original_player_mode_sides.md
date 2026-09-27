# 阵营位：每个已放置演员的 player mode 覆盖、HP 加值与谁打谁

> evidence: static-derived; resource-derived: OBJ 字段普查与 TYPE.H 位定义; runtime-measured: 裁判开局盘 obj_Data9 换边单位与全库 NPC 最大 HP（DATA9）；整镜像 LEVEL012 62 枚船壳同一 live 记录（改一枚 HP 其余同读）; provisional: 玩家可见后果未原生观察 · status: live · functions: 0x407660, 0x407720, 0x407ec0, 0x40ba20, 0x40ba80, 0x40bab0, 0x40bb00, 0x40bb80, 0x40f5d0, 0x40f8b0, 0x40fdc0, 0x4104d0, 0x42bdb0, 0x43f413, 0x4420ef, 0x446b30, 0x446b60, 0x446be0, 0x44cb10, 0x450710 · tools: hsl_payload_inspector.py, hsltools/levels/battle.py, hsltools/probes/_enemy_level.py, run_tests.gd · updated: 2026-09-29

## 范围

R21 字段覆盖审计（[original_field_coverage.md](original_field_coverage.md) §3／§4）排出的两条 P1：原版关卡对象表 `[Object]` 记录的 `obj_X1`（逐个已放置演员的阵营模式覆盖）与 `obj_HitPoint`（HP 加值），此前导入器丢弃。本包记录：① 演员构造把这两个字写到 live 记录的哪里；② 阵营模式 `+0x28` 在目标选择、玩家攻击范围、通行阻挡与胜负计数里各自怎么读；③ 重制接入与未原生观察的边界。原版等价声明只到静态读法；"敌军不打村民"等玩家可见后果标 provisional。

## 数据（resource-derived）

`TYPE.H`：`pmPlayer 0x10000`、`pmEnemy 0x20000`、`pmNPC 0x40000`；组合 `pmPlayerEnemy 0x30000`、`pmNPCPlayer 0x50000`、`pmNPCEnemy 0x60000`、`pmALL 0x70000`、`pmMagicAttack 0x870000`、`pmNPCPlayerNoMagic 0x850000`。

148 关 OBJ-NNN 的已放置（EVEF）`defProcEnemy` 演员：`obj_X1` 102 条（pmNPC 39：7 关 036×10／037×5／038×6、21 关 038×5／041×5／043×3、57 关 054、531／532／533 关 049；pmPlayerEnemy 36：6 关 061×7／062×5、9 关 061×7／062×7、34 关 062×3、65 关 061×3／062×4；pmPlayer 6：900 关 062×6；pmEnemy 21：510／511／512 关 036／037／038，与模板同值）；`obj_HitPoint` 46 条（024 +50 ×25：24／29／44／531／532／575／903；023 +20 ×18：32／552／554；024 +30 ×3：901 隊長）。STORY／WINFAIL 脚本插入的对象另有 `obj_X1` 14 条（7／21／22／24／32 关 pmNPC，6 关村民 pmPlayerEnemy）与 `obj_HitPoint` 7 条（6／7／901 隊長 +30，24／29／44 024 +50，34 023 +20）。复现：`git show HEAD:content/generated/hsl/chapter01/battle006_seed.json`（`placements.records[].object_data_fields.obj_X1`）；普查脚本见 `hsltools/checks/field_coverage.py --census`。

## 静态读法（static-derived，r2ghidra 反编译 `hsl01.exe`）

**演员构造 `0x407ec0`**（对象过程 3 defProcPlayer／5 defProcEnemy；`0x44cb10` 复制 PLAYERS 模板到 live 记录之后）依次：`obj_Data9`（模板 +0xac）≠0 → live `+0x28` 若等于 pmPlayer 写 pmEnemy、若等于 pmEnemy 写 pmPlayer，并 `+0xa0 |= 8`；`obj_HitPoint`（+0x88）≠0 → live `+0x1b6`（HP 加值半字，PLAYERS `hit_point` 所在）`+=`；`obj_X1`（+0x10）≠0 → live `+0x28` 直接覆盖；随后 `0x448840` 刷新。过程码 `+0x64` 不随模式改变——defProcEnemy 对象覆盖成 pmPlayer 仍由 AI 驾驭。每个用过的模板字随即清零。

**侧位读取 `0x40ba20`**：返回 live `+0x28` 的 `0x10000｜0x20000｜0x40000｜0x800000` 四位。`0x40ba80`：`~mode & 0x70000`（搜索 mask）。`0x40bab0`：pmPlayer 位→2、否则 pmEnemy 位→3、否则 pmNPC 位→7（地面通行模式，配 `0x40ed50` 的阻挡 mask 2→0x64000／3→0x54000／7→0x34000，即被"不含自己首位"的占格阻挡）。`0x40bb00`：同序 8／9／10（支援范围模式）。

**AI 目标扫描 `0x40bb80`**：遍历 200 槽，跳过空槽、自身、`+0x80 & 0x8000000` 已移除；`own & other & 0x870000 != 0` → 排除。因此 pmEnemy 不选 pmPlayerEnemy（共 E 位）也不选 pmNPCEnemy；pmNPC 与 pmPlayer、pmEnemy 互选；pmNPCPlayer 与 pmPlayer 同侧、选 pmEnemy、不选 pmNPC（共 N 位）。呼叫广播 `0x40bee0` 与支援扫描要求 `& 0x870000` **相等**（[original_ai_calls.md](original_ai_calls.md)／[original_ai_support.md](original_ai_support.md)）。

**攻击／支援范围 `0x40f8b0`→`0x40f5d0`**（RANGE 记录展开到 `0x4c1b48`）：参数 mode 经 `0x4c63a4` 进 9 格跳表 `0x40f874`／11 格 `0x40fa48`：mode 0–2→排除位 0x10000、3→0x20000、7→0x40000、8→0x60000、9→0x50000、10→0x30000、4／5／6→无排除。每格：格标志（占位对象的侧位）`& 排除位 != 0` 且 `(flags & 0x70000) != 0x70000` → 不写该格（不可选为目标）；`0x4c63ac`（魔法）≠0 且格标志有 0x800000 → 亦不写。读法：以 `0x40bab0` 的 2／3／7 建攻击范围时，占位者只要含攻击者首位就不可选——玩家（P）不能攻击 pmPlayer／pmNPCPlayer／pmPlayerEnemy 占位者，可攻击 pmNPC；pmALL 占位者在排除位检查里总被保留。8／9／10 只留同首位格（支援范围）。

**`0x4c63ac` 是调用方给的第 5 参数，不是「魔法」标志**（R6-L10 更正旧读法）：`0x40f8b0` 入口 `mov [0x4c63ac], [esp+0x14]`，经 `0x40fa80`（`obj, range, mode, flag` 包装）传入。flag＝1 的调用方（`0x43fca5`、`0x440c62`、`0x440d2d`、`0x44134a`、`0x4426b0`、`0x4426ea`、`0x444156`）的射程都取自 `0x409090`——记录 `+0xec` 武器 → ITEM 表 `0x4c1b40` 的射程，即**普通攻击射程**；flag＝0 的是 `0x441779`（`0x4097d0`，MAGIC 表 `0x4c2ca0`）、`0x441a73`（`0x409830`，SPECIAL 表 `0x4c3920`）、`0x444eb7` 魔法选目标、`0x445075`／`0x44508f` 绝技选目标与 AI 的各次建范围。所以 pmMagicAttack（`0x870000`＝pmALL｜`0x800000`）占位者**普通攻击选不中、魔法／绝技选得中**；不带 `0x800000` 的 pmALL（18 关 門 Enemy100 的 PLAYERS mode）两者都选得中。AI 仍由 `0x40bb80` 排除一切 pmALL（与任何侧位都有交集）。这与 WINFAIL037 2099「依照顺序将宝石灌入魔力或氣力」一致（台词只是一致性，不是依据）。

**注册／注销计数 `0x407660`／`0x407720`**：`side = 0x40ba20(obj)`；`P 位清 且 E 位设` → `*0x4c1b94`（敌方总数，`actCheckEnemyTotalNumber` 读）±1；`P 位设 且 E 位清` → `*0x4c1b90`（玩家总数，`actCheckPlayerTotalNumber` 读）±1。pmNPC 与 pmPlayerEnemy 两边都不计。

**脚本换阵营 `0x450710`**（`actSetPlayerMode`）：写 `+0x28`；新模式恰为 pmPlayer → 过程码 3（玩家驾驭）并着色 (0x50,0x50,0xff)；pmEnemy → 过程码 5、着色 (0xff,0x64,0xa0)；其他模式 → 过程码 5、着色 (0xff,0xff,0x50)。剧本用到的模式：pmEnemy／pmPlayer（多关）、pmPlayerEnemy（36 关 克羅蒂 第 10 回合"谁也不打她"、37 关 067）、pmMagicAttack（37 关 067 与 pmPlayerEnemy 交替）。

## 重制接入

| 层 | 位置 | 读法 |
| --- | --- | --- |
| 导入 | `hsltools.sources.scripts.parse_text_metadata` | 对 defProcEnemy／defProcPlayer 对象保留 `obj_X1`／`obj_HitPoint`（效果／地图对象同名字段是 WAV 名／mapobj 参数，无消费者，不保留） |
| 组装 | `hsltools/levels/battle.py install_player_mode`／`_apply_object_install` | 单位键 `player_mode`（int，live +0x28）= PLAYERS mode → obj_Data9 互换 → obj_X1 覆盖；`player_mode_source`（字符串）；`object_hit_point`（int，有加值时）加进 `growth_profile.source.hit_point` 与 `max_hp`／`hp`。放置、STORY 开场插入、WINFAIL 脚本模板、遭遇战四路同一函数。角色：有 pmPlayer 位 → `friendly_ai`（pmPlayer／pmNPCPlayer／pmPlayerEnemy），无 → `enemy_ai`（pmEnemy／pmNPC）；注册槽安装仍 `player_controlled`；profile `role_overrides` 优先并把 `player_mode` 拉到对应侧 |
| 规则 | `ActorRoleRules.side_mask`／`hostile`／`same_side`／`counts_as_enemy`／`counts_as_player` | `side_mask` = `player_mode & 0x70000`，无 `player_mode` 的单位（手写场景、开发夹具）按角色：player_controlled／friendly_ai → 0x10000、enemy_ai → 0x20000；`hostile` = 侧位无交集（0x40bb80／0x40f8b0）；`same_side` = 有交集（支援）；计数按 0x407660 |
| 消费者 | `BattlePlayLoop._are_enemies`（AI 目标、玩家攻击 `not_enemy` 拒绝、友军援助）、`AISkillPlanning`／`AISupportPlanning`／`SkillTargetRules.side_matches`、`ActorTraversalRules`（占格侧位与 0x40bab0 通行模式）、`WinfailScenarioRules._alive_enemy_total`／`_alive_player_side_total`、AI 呼叫 `side` 行 | 全部改读 `ActorRoleRules`；`actSetPlayerMode` 同时写 `player_mode`，新增 pmPlayerEnemy→friendly_ai、pmNPC→enemy_ai 两个受支持模式（pmMagicAttack 仍 `unsupported_mode`） |
| pmALL 射程（R6-L10） | `ActorRoleRules.player_range_selectable(attacker, target, magic_range)`：`hostile` 或目标侧位＝pmALL 且（魔法／绝技射程，或目标无 `0x800000`）；`BattlePlayLoop.attack_target` 普通攻击与 `BattlePresentation` 预览、`SkillTargetRules.side_matches`（玩家受控施法者的攻击型技能）用它；AI 施法者选主目标与 AI 目标扫描保持 `hostile`（范围结算另见下文 `area_side_matches`，R6-L11）；`actSetPlayerMode pmMagicAttack` 支持（role friendly_ai，`player_mode` 0x870000）；无 AI 声明且没有任何敌对单位的单位（37 关宝石）待机而不是 `missing_ai_strategy` | 37 关宝石只吃魔法／绝技 |
| 未改 | `BattleRewardRules`（只对 enemy_ai 目标结算）、`DevelopmentBattleRules` 胜利 | 保持角色读法 |

## 门（PLAYERS 100）与船壳（PLAYERS 101）是登记演员（lane ACTORS100，static-derived＋runtime-measured）

原版把 18 关 Enemy100 门、12／26 关 Enemy101 船壳（EVEF `defProcEnemy`，形体 `SHAPE11\18_DOOR01.SHP`＝两行 SHAPEDEF 的 stand）当演员构造、登记进对象表 `0x4c34c0`：开局对拍（runtime-measured）在第 1 回合停机点读到 12 关 62 个、26 关 26 个 row 101，18 关 1 个 row 100（槽 36，格 [29,10]——STORY018 先 `actDeleteObject SID_ENEMY100/1` 删 EVEF 门，再 `actInsertObject obj_Story_Level_Door` 插回同格）。

| 项 | 原版读法 |
| --- | --- |
| 阵营 | 门 pmALL `0x70000`；船壳 pmNPCPlayerNoMagic `0x850000`。`0x40bb80` 阵营交集排除：门对所有人排除（AI 从不选）；pmEnemy `0x20000 & 0x850000 = 0`，船壳是敌方 AI 的扫描候选；`0x40c2f0` 支援扫描要求阵营位相等，没人给船壳回血 |
| 能否被打 | 门：玩家普通攻击走 pmALL 分支（无 `0x800000`，选得中），魔法／绝技也选得中。船壳：`0x40f5d0` 对玩家（排除 `0x10000`）、NPC（排除 `0x40000`）丢格，只有敌方普通攻击能打；范围魔法三处（`0x40ff1f..0x40ff43`、`0x4103f6..0x41041a`、`0x4102ca..0x4102ee`）在 `0x40fc90` 找不到非 no_block 占格者且 `(格字 & 0x870000) == 0x850000` 时丢格。无不死位，HP 归零照常 `0x43f179` 清格 → `0x407720` 注销 |
| no_attack（`+0xa0` 位 2） | `0x43f413`：非剧情阶段整段状态机短路，轮到自己时 `0x442084` → `0x407510` 交出回合（不动、不结算状态）；仍占行动队列位。作为防守方不反击（`0x442646`），攻击方命中率固定 100（`0x406ed8`） |
| no_block（`0x44c30e` 置 `+0xa0` 位 `0x10`，查询 `0x446b30`）| 船壳照样经 `0x411a30` 把阵营位写进格字，但洪泛 `0x40ef96`、寻路 `0x411335`、点格 `0x443caa`、找占格者 `0x40fd81` 都把它当空格：敌我都能穿过、停在船壳格上；门会挡所有人 |
| no_showshape（`0x44c33c` 置 `0x20`，查询 `0x446b60`）| 敌方过程每 tick 收尾 `0x4420ef`（`+0x80 & 0x1000` 为 0 时）写形号 `0xffff`，形体与底影（`0x43db8b`）都不画——船壳是隐形对象，画面上的船身是地图底图 |
| obj_Data7 高位 `0x80000000` | 船壳的 obj_Data7 是 `0x80000065`：`0x42bdb0..0x42be0b` 去掉高位后看 `0x4c1ad0`（关卡初始化 `0x42c6da` 清 0）：为 0 时置 −1、调 `0x44cb10(行号, 1)` 建记录，把返回的记录号写对象 `+0xa4`，再把 `0x4c1ad0` 写成这枚对象；之后的船壳直接取 `[0x4c1ad0]+0xa4` 当自己的 `+0xa4`。记录地址 `[0x4c1bc8] + 号·0x1fc`，所以共用的是**整份 0x1fc 字节 live 记录**——HP `+0xd8`、最大 HP、状态字 `+0x24／+0x30`、阵营字 `+0x28`、属性与等级全是同一份；对象自己的只有像素、朝向、形号与过程状态。其后 `0x42be79..` 把每枚对象的 obj 覆盖字（+0xac 换边、+0xa8 死亡台词、+0x88 HP 加值、+0x9c 稱號、+0x10 阵营）照写进这份共用记录（全部船壳同模板，写的值相同）。整镜像实测（`_enemy_level.run_level` 进 12 关，开局盘把 actor101_1 的 HP 写成 700）：62 枚船壳的 `+0xa4` 全是 53，改 actor101_1 一枚后 62 枚读出的 HP 全是 700 |

**重制接入**：模板 `content/generated/hsl/actors/100.json`／`101.json`（`campaign_actor_data`，PLAYERS 缺 `move_point` 读 0，同 `0x44ca5c` 预置 0 写法）；`object_actor_code` 按 16 位取 obj_Data7 的行号（高位是共享记录标志），`standing_actor_code` 让它们与 80 关 068 一样成为 PlayLoop 单位（role friendly_ai：两者都带 pmPlayer 位；SHAPE11 门帧作 stand 帧）；18 关 `standing_actor_inserts` 把插回的门接成 `actor100_2`，EVEF 门 `actor100_1` 由 `actDeleteObject` 作单位离场；`static_enemy_counts` 从组装器删除（`actCheckEnemyNumber SID_ENEMY101` 改数存活单位）；`BattleLoopAI._idle_without_strategy`：无 AI 声明且 no_attack 的单位原地等待（`0x43f413` 的交回合）；`no_showshape` 进单位字段，`ActorRuntime.hide_shape` 不画船壳；`EntryGrowthRules.propose` 不再拒绝属性高于职业上限（101 str 120／con 200 高于上限 107／99，原版第 1 回合记录原样保留）。开局对拍：`presence:original_only` 356 行→0，89 个单位全部配对，余下只落在既有 `weapon_magic_type`（无武器默认值）一类。

**共享记录（lane SMALLTAILS 2026-09-27）**：组装器 `_apply_object_install` 对 obj_Data7 带高位的对象写 `shared_record`（行号，12 关 62 枚、26 关 26 枚）；`game/sim/SharedRecordRules.gd` 在每次行动结算的公共缝 `BattleLoopScript._resolve_outcome` 开头把同组活着的船壳 HP 并成一池（每枚行动开始时都等于池值，池按本次各枚变化之和移动；本次被打倒的一枚最后一击也计入），任一枚被打就是整船掉血。WINFAIL 条件读法不变（`actCheckEnemyNumber SID_ENEMY101,62` 仍数存活单位）。

**未接（provisional）**：只并 HP——状态字、阵营字、属性按单位各自保存（船壳 no_attack、没人给它回血或施状态，阵营改写经 token 本就作用于全部船壳）；池归零后原版其余船壳记录 HP 为 0 但对象仍在，重制让其余船壳保持最后一个正值（12 关此时 fail 段已成立）；一次行动同时打到两枚船壳时池按两次变化相加，未逐项核对原版逐次扣减的最低 1 HP 等截断。门／船壳被打时的命中 100 与不反击沿用重制现有 no_attack 读法，未逐项核对。船壳计入玩家总数 `*0x4c1b90`（P 位有、E 位无，按 `0x407660` 推论）未单独核对。

## 6 关 席達鎮 全待机对照（前两回合谁打谁）

重制列由 `tests/run_tests.gd`（`_test_level6_soldiers_never_attack_villagers`，loop RNG 种子 22）打印的 `PLAYER_MODE_SIDES_ATTACK` 行得出；原版列为静态推断，**未原生观察**。

| 回合 | 重制（R22 前，`13bda1bb`） | 重制（R22 后） | 原版（static prediction，provisional） |
| --- | --- | --- | --- |
| 1 | 村民 friendly_ai 侧位 P：士兵 023 把最近的村民当目标，3 次交锋中可含村民 | 023×3 → 漢克斯／雷歐納德；村民 0 次被打 | 023 的 `0x40bb80` 扫描排除 P∣E 村民（共 E 位），只选 4 名受控 |
| 2 | 同上 | 023×4 → 漢克斯／雷歐納德；雷歐納德 阵亡（`defeat_leonard`）；村民 0 次被打、0 次出手 | 村民（P∣E）搜索 mask = pmNPC，本关无 pmNPC → 村民不出手 |

替换证据：给 `hsltools/data/original_save.py` 的 `PRESETS` 加一个 `level06_pre_battle` 预设（尚未编写：CHAPTER1_FLOW 到 5 关 win、点 5 站位、点 6 未访问）并 `hsl generate` 它→ Wine 单步 `tools/hsl_original_control.py` 全待机两回合 → `tools/hsl_original_probe_units.py` 读各单位 `+0x28` 与目标；观察到"士兵不打村民、村民不动"即可把本表原版列从静态推断改为原生观察结论。

## 边界（provisional／未接）

- **玩家可见后果未原生观察**：士兵不打村民、531–533 关 049 与其余敌军互打、24 关 049／053／054 pmNPC 三方、44／45 关 021／022 到场为友军、34 关 023／044 到场为友军再叛变——全部只到静态读法（`run_tests.gd` 在 531 关 3 回合里记录到 7 次 049↔044 交锋，是重制行为，不是原版观察）。
- **支援同侧 = 有交集** 保留现行合同（friendly_ai 援助 player_controlled）；原 AI 支援扫描要求掩码相等、支援范围模式 8／9／10 只留同首位格——若按原读法，pmNPCPlayer 村民不能被 P 侧治疗、也不能治疗 P 侧；待原生观察后再定。
- **hp_level 项（lane DATA9 用裁判核过，重制自 R34 `647dbca9` 起与原版一致，不需要改）**：`0x448840` 算 HP 等级项只看刷新那一刻 live `+0x28` 的 pmPlayer 位（`0x448851 test eax,0x10000`，不置位时 `0x448858` 清零；[original_job_stats.md](original_job_stats.md)）。`0x407ec0` 先做 obj_Data9 换边、再调 `0x448840`，所以出生刷新读到的已是换边后的 pmEnemy，023／024 比模板少 `1.2×level`（job 88）～`1.5×level`（job 94）。重制顺序相同：组装器把换边后的值写进单位 `player_mode`。载入刷新（`ActorInitializationRules.prepare`）和 NPC 出生刷新（`InitialRosterGrowthRules.prepare` → `ReinforcementGrowthRules._apply` → `ProgressionRules.refresh_growth_stats`）都经 `ActorRoleRules.side_mask` → `JobStatsRules.base_values` 读这个值。模板 `growth_profile.source.mode` 不参与，也就用不着 HANKS3 的 `birth_player_mode`；那个字段只给出生后才被脚本 `0x450710` 改阵营的玩家单位用。
  - **裁判实测（runtime-measured，2026-09-26）**：原版一侧跑 `_enemy_level.py batch --seed 1`，growth 设为 false（`0x43eefb` 清零 +0x1f8／+0x1fa，`0x40e870` 照常推等级并刷新），读 `meta.opening_board`；重制一侧是同关零成长出生（`adjust_level [0,0]`，经 `initialize_roster_growth` → `begin_battle`；诊断脚本未入库）。结果：obj_Data9 单位共 113 名，出现在原版开局盘上的 111 名等级和最大 HP 全部相同（023 L1 28、023＋20 L1 48、024＋30 L1 72、024＋50 L1 92、52 关 069 L4 40）；另外 2 名（53 关 `enemy023_2／3`）原版要到停机点之后才出生。全库 127 关 NPC 最大 HP 1487／1487 相同，玩家 1012／1012 相同（200 关裁判起不来）。
  - **battle JSON 快照**（lane CUTMIRROR，2026-09-26）：`max_hp／hp` 快照也按安装后的 `player_mode` 取 HP 等级项（`hsltools/model/jobs.py` `calculate(..., mode=)`，组装器 `battle.py align_birth_hp`，在模板行的出生前等级上取差）。改前 113 名放置单位＋10 个脚本模板（互换单位）与 1 个无对象定义的 903 关模板比运行值差 1（29／49／73／93／41 与反向的 021／044／048），改后 0；运行时载入刷新本来就覆盖它，对局不变，`_enemy_level.py --align`／`board_diff` 不再报这 1 点假差。
- **`+0xa0` 掩码 8（换边位）**（lane CUTMIRROR 读）：构造 `0x407ec0` 只在 obj_Data9 真的互换了 pmPlayer／pmEnemy 时 `or dword [+0xa0], 8`（`0x407fc3`；模板 mode 是别的就不互换也不置位）；`0x450710` 每次调用都先 `xor ecx, 8` 写回（`0x45073c`），在比较新旧 mode（`0x45073f`）之前——是**翻转**，模式不变也翻。`0x446be0` 读它镜像该演员的全部切入对象：攻方（普攻／施法引导，x 缩放 −1、aniSetXYDisp x 取反、速度角反射）、刀光、守方（x 缩放 −1、受击位移旗左右互换）（[效果对象运动包 §4b](original_effect_motion.md#4b-普通切入的换边镜像cutin-mirror)）。重制：组装器写单位 `side_swapped`，`WinfailActions._apply_player_mode` 每次翻转。
- **pmALL 占位者** 已按上文调用方读法接入（R6-L10）。
- **范围波及（R6-L11，static-derived）**：施法事务 `0x442a90` 的目标由 `0x4104d0` 逐格扫范围遮罩 `*0x4c1b4c`（`0x407800` 取占位对象、去重）得到，`0x4116a0` 只是画范围。遮罩由 `0x40fdc0` 建：与 `0x40f5d0` 同一张 mode→排除位跳表（`0x4100a0`），格标志 `& 排除位 != 0` 且 `(flags & 0x70000) != 0x70000` 才丢；**没有 `0x4c63ac` 这一步**，所以 pmALL（含 pmMagicAttack）占位者对任何施法者的攻击型范围都在内；另外 `0x40fc90` 之后 `(flags & 0x870000) == 0x850000`（pmNPCPlayerNoMagic）的格也丢（重制无此类单位）。重制：`SkillTargetRules.area_side_matches` 供范围结算（`SkillResolutionRules` 区域分支、`RepeatedSpecialRules`）使用——AI 的范围魔法也会波及宝石，宝石各自的 event（`actCheckSerialPlayerAttacked` 不看攻击者）照常可触发；主目标选择与 AI 规划仍用 `side_matches`（AI 不会以宝石为目标，0x40bb80）。`run_tests` 覆盖。给予／支援对 pmALL 的处理沿用「有交集」读法。
- **0x800000（NoMagic）位**：`side_mask` 丢弃；魔法范围对该位的排除未接。
- **着色**：`0x450710` 按模式给对象着色（P 蓝／E 红／其他黄）；表现层未按 `player_mode` 区分村民与友军。
- `obj_Data8`（死亡台词）与 `obj_Data5`（称号／名字）自 R29 起由同一 `_apply_object_install` 写单位 `dead_message` 与 `title`／`display_name`（读法见 [字段覆盖 §4](original_field_coverage.md#4-静态读法本包新增static-derived)）；`obj_Y1`（+0x134）仍未进数据链。

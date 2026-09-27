# Battle loop：配置／状态分离

> 状态：**现行合同**（2026-09-22 夜间由负责人起草为 proposal，lane S6e 落地；lane S10 量过 `units` 后补「units 的所有权」与反例；lane S12 把「真正的墙」`_prepare_ai_turn` 降下来并写入「AI 准备阶段」合同；S13 前瞻指挥官自身；S14 规则侧 AI 回合）。依据 review R20 F1 与 S3 之后的实测事实。入口段落见 [BATTLE_SYSTEMS「BattlePlayLoop.gd」](BATTLE_SYSTEMS.md#battleplayloopgd)。

## 问题（落地前）

`loop` 字典同时装着**只读配置**（terrain `tiles` 728 KB、`equipment_items` 302 KB、`skill_book` 195 KB、`ai_profiles` 75 KB、`reward_data`、`events`……）和**可变状态**（`units`、turn queue、`winfail_runtime`、interaction……）。规则是 `f(loop) -> loop` 的纯函数，靠 `loop.duplicate(true)` 保证不改输入：PlayLoop 83 处整库复制、sim 13 处、测试支援 6 处；一次 AI 行动约 3.4 次整库深拷贝（`tests/measure_loop_copy.gd` 量得 44 关 84 人一回合 283 次），绝大部分字节是配置；存档把配置一起写盘；`Autoplay` 用 `stepped == loop` 做整库比较。续集战斗更大（84 人战斗已存在），这是必然要碰的墙。

## 合同

- **`BattleLoopConfig.CONFIG_SHARED`**（`game/sim/BattleLoopConfig.gd`）列出全部只读配置键：`CONFIG_KEYS` 20 个（每个成功 `create()` 后必在，`BattleCheckpoint.configuration()` 按此顺序做摘要；旧 `BattleCheckpoint.CONFIG_KEYS` 的 `escape_zone` 移出——`WinfailScenarioRules._refresh_objective` 每回合按已武装的 win status 重算它，是派生状态，随存档写读）＋ `CONFIG_SOURCE_KEYS` 8 个（`script_wait_source`／`entry_growth_data`／`script_actor_source`／`treasure_source`／`script_presentation_source`／`winfail_script_rules`／`job_up_templates`／`job_up_targets`，由某些场景的 `_load_*` 阶段或 rule adapter 写入）。`BattlePlayLoop.CONFIG_KEYS`／`CONFIG_SHARED` 转发同一常量。
- **消融结论**：create() 后前十大键里 `CONFIG_SHARED` 之外只剩 `units`（状态）；`winfail_script_rules`（34 KB）／`job_up_templates`／`job_up_targets` 只读、并入共享集；冻结断言在规则里没有抓到任何原地改配置，抓到的全是测试夹具（见下）；`escape_zone` 因被规则整键重写而移出。
- **配置在 `create()` 后不可变且只有一份**。`create()` 的每个 `_load_*` 阶段（以及 `BattleScenarioRuleAdapter.initialize_script_state`）是唯一写入点；新增只读输入必须登记进 `CONFIG_SHARED`，否则它继续随状态深拷贝、不受冻结断言保护、并被存档写盘。
- **战中改地形是状态**（lane R5-L4b）：脚本插入的改地形物件（第 39 关 `actInsertStoryObjectXRange obj_Story_Block`）不改 `tiles`，而是向状态键 `terrain_edits`（`create()` 起为 `[]`）追加 `{cell, height|clear_flags, source}`；通行读者一律经 `TerrainEditRules.tiles(loop)` 取「配置＋编辑」（无编辑时就是 `tiles` 本身；有编辑时是按配置引用＋编辑表记忆化的新字典，`_tile_tables` 的引用缓存照样命中）。存档写读 `terrain_edits`，`BattleCheckpoint.validate` 在站位校验前先校验它。
- **`BattlePlayLoop.copy(loop)`**（转发 `BattleLoopConfig.copy`）是复制整个 loop 的唯一方式：状态键 `duplicate(true)`，`CONFIG_SHARED` 值按引用共享。PlayLoop、sim 模块（经 `LoopConfig.copy`，避免 PlayLoop 循环 preload）、`tests/support` 的整库复制全部走它；对子字典的 `duplicate(true)`（unit、receipt、queue slot……）不变。
- **规则签名不变**（仍 `f(loop) -> loop`），调用方不感知；断言零改动。
- **`BattlePlayLoop.same_state(a, b)`**：只比较非配置键；`Autoplay`／`AutoplayBrain` 的"这一步有没有进展"整库比较改用它。
- **测试期冻结**：`tests/run_all.gd` 打开 `BattleLoopConfig.freeze_enabled`，之后每次 `create()` 记录每个 `CONFIG_SHARED` 值的 `hash()`；每个规则套件结束时 `TestSuite.assert_config_frozen()` 重算比对，任何原地改配置的地方立刻以 `<TAG> wrote the shared configuration block <key> in place` 失败（只加失败、不加 check 计数，套件的 PASS 行不变）。产品路径不付这个成本。
- **测试夹具改配置**必须先拿到自己的副本：`TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0`——`own` 用深拷贝替换该键，冻结的原块与所有共享它的 loop 不受影响。直接写 `loop["skill_book"][...] = …` 会改到共享块并让套件失败。
- **存档只写状态**（`BattleCheckpoint` schema `hsl_battle_checkpoint.v4`）：`encode` 写 `state(loop)`（`CONFIG_SHARED` 之外的键），`decode(bytes, current)`／`read(path, current)`／`validate(snapshot, current)` 以运行中战斗的 loop 为配置来源：先比配置摘要，再把保存的状态与 `current` 的配置块（按引用）合成完整 loop 做原有校验并返回。v1（第一战技能清单摘要）、v2（整库写盘）与 v3（`battle_outcome` 写成键字串）按名拒绝 `unsupported_save_schema`，不做迁移；`battle_outcome` 须是 `BattleOutcome` 结构（`{}` 或 `{result, reason}`），否则 `invalid_saved_outcome`。

## 不做的

- 不改规则签名为 `f(config, state)`（R20 建议的完全体）：106 个函数签名＋853 处测试 `Loop._unit` 调用，收益不比现合同多多少。
- 不把配置搬出字典（`loop["config"]` 子字典）：会让 2411 处 `loop.get(key)` 里读配置的那部分全部改路径。
- 不对 `units` 做 copy-on-write（S10 量过，见下「units 的所有权」与「量化 S10」）：它占剩余字节的 95%，但整库复制只占一回合墙钟 2–4%，按单位共享＋写时复制要审 `game/` 15 个文件里 121 处 `_unit(...)` 取用者与 24 处 `["units"][i]` 直接下标，收益上限 ≈3% 时间，不合并。

## units 的所有权（现行合同，S10）

- **`units` 是状态**：`copy` 对它 `duplicate(true)`，每个单位字典及其子块（`combat_profile`／`growth_profile`／`entry_growth`／`equipment`／`inventory`……）都随之深拷。单位里没有按引用共享的块：`combat_profile` 由 `ProgressionRules.apply_level_ups`（逐键原地写）／`refresh_growth_stats`（整键重写）、`JobUpRules`、`CampaignCarryRules` 重写，`growth_profile` 由 `ActorInitializationRules`／`JobUpRules` 改写，`entry_growth` 由 `ReinforcementGrowthRules` 写入——它们都是可变状态，不是配置。
- **谁能原地写 units**：只有刚用 `copy(loop)` 得到自己 `next` 的规则，写它自己的 `next["units"]`——经 `Loop._unit(next, id)[...] = …`、`_set_unit_coord`／`_set_unit_hp`、`next["units"][index]`（AI 行数索引）或 `Loop._unit(...).merge(...)`。规则不得写入参 `loop` 的单位：`AutoplayBrain.simulate_round` 用 `loop.hash()` 前后比对把这种泄漏记为 `mutated` 并 `push_error`。
- **表现层与测试只读**：场景经 `BattlePlayLoop.unit(loop, id)` 拿深拷副本；`BattleSceneRuntime.apply_loop` 是唯一写入口；测试夹具改单位写自己那份 loop（`Loop._unit(loop, id)["hp"] = …` 在夹具的 loop 上是允许的，因为夹具持有它）。没有 `own_unit` 之类的入口——不需要，因为没有共享。
- **新增单位字段**：直接放进单位字典即随 `copy` 深拷、随存档写读、进 `same_state` 比较；不要为省复制把单位字段登记进 `CONFIG_SHARED`（那会让它跳过存档并被冻结断言当作配置）。

## 量化 S10

`tests/measure_loop_copy.gd`，2026-09-25，同机有其他 lane 门禁在跑（load 2.6–7.5），每关跑 2 次：比值稳定、绝对值相差 2×，表中「a／b」为两次。先量后判——整库复制不是墙，AI 准备阶段是：

| 战斗 | 单位 | 状态字节／次 | 其中 `units` | 单位均值 | `copy` µs（含释放） | 一回合步数 | 一回合复制次数 | 复制估时／回合 | **复制占比** | `_prepare_ai_turn` 占比（AI 单位数） | 阶段（ms，第 1 次） |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 44 | 84 | 578 372 | 553 088（95.6%） | 6 584 | 1 216／2 340 | 84 | 283 | 344／662 ms of 12 101／27 495 ms | **2.8%／2.4%** | 95.4%／80.6%（75） | approach_routes 6 354、target_rows 2 787、action_candidates 2 145、preflight 75 |
| 45 | 44 | 289 936 | 271 996（93.8%） | 6 181 | 662／1 819 | 44 | 168 | 111／305 ms of 3 410／8 749 ms | **3.3%／3.5%** | 83.6%／89.5%（35） | action_candidates 1 190、approach_routes 919、target_rows 629 |
| 51 | 12 | 88 224 | 78 660（89.2%） | 6 555 | 209／638 | 12 | 40 | 8／25 ms of 508／1 200 ms | **1.6%／2.1%** | 85.0%／89.3%（11） | approach_routes 252、action_candidates 93、target_rows 55 |

单位字节的构成（44 关 84 人）：`entry_growth` 125 652、`growth_profile` 64 936、`combat_profile` 53 088、`equipment` 33 820、`permanent_gains` 20 160、`position_source` 16 360、`attack_range_evidence` 14 232、`position_note` 9 072；其余约 200 个来源／证据字串键合计 ≈ 215 KB。

前瞻（`HSL_AUTOPLAY_BRAIN=lookahead`，本回合第一个玩家菜单的一次决策）：44 关 2 次模拟回合 547 次整库复制 37.0 s／99.9 s；45 关 3 次模拟 423 次复制 20.1 s／50.0 s；51 关 4 次模拟 81 次复制 1.2 s／3.1 s。每次决策只多 1 次整库复制（`simulate_round` 的 `Loop.copy`），其余复制都是模拟回合里规则自己的；决策成本 ＝ 模拟回合里的 `_prepare_ai_turn`。

候选消融（按上表估，未实施）：

| 候选 | 复制字节／次（44 关） | 字节比 | 墙钟上限 | 代价 | 结论 |
| --- | --- | --- | --- | --- | --- |
| (a) 单位按引用共享＋写时复制 `own_unit` | 578 372 → ≈ 25 284 ＋ 6 584 × 改动单位数（1–3）≈ 32–45 KB | 13–18× | ≤ 复制占比 2.4–3.5% | 审 `game/` 15 文件 121 处 `_unit(...)` 取用者（读写混用，返回的引用被缓存在 `turn["actor"]` 之类的工作字典里传给后续阶段）＋24 处 `["units"][i]`＋10 处 `_set_unit_*`；所有权标记要么污染单位内容（破坏逐字节）要么加隐藏 loop 键（`same_state`／存档／`==` 全要排除）；漏一处只在保留旧 loop 的路径（前瞻、场景持有）静默串改 | 不做：字节达标，时间收益 ≈3%，远低于 ≥30% 门槛，风险面最大 |
| (b) 前瞻探针浅复制＋差量回滚 | 每次决策省 1 次复制（547 → 546） | ≈1.0× | <0.1% | 回滚要枚举模拟回合写过的全部键 | 不做：成本不在这次复制 |
| (c) 单位内只读块按引用共享（`entry_growth`／`growth_profile`／`combat_profile`） | 578 372 → 334 696 | 1.73× | ≤1.2% | 三块都有原地写者（见上），仍要写时复制 | 不做：字节比不到 2×，时间 ≈1% |

真正的墙（S10 结论）：`BattleLoopAI._prepare_ai_turn` 每个 AI 单位每回合重算整图路由（`_ai_approach_routes` → `AINavigationRules.full_routes`／`approaches`，44 关 6.3 s）、目标行（`_ai_target_rows` 2.8 s）与动作候选（`_ai_action_candidates` 2.1 s），合计一回合 80–95%。S12 量了它的内部分布并按下节合同降下来（行为逐字节不变）。

## AI 准备阶段（现行合同，S12）

S12 先在 44 关一回合里给 `full_routes`／`_movement_envelope`／`_ai_target_rows` 的内部打计数（临时插桩，未提交）：一回合 35 s 里 **17 s** 在 75 次整图洪泛，其中 **10.9 s** 是 `_move_target_blockers` 对同一被阻挡格从最多 4 个邻格各扫一遍 84 个单位（63 273 次 × 173 µs）；**7.8 s** 在 `_ai_target_rows` 对 84 个单位 × 75 个行动者调 6 300 次经验输入校验（今 `ExperienceRules.input_error`）（每次整份 `refresh_growth_stats` 重算再比对，1.1–1.2 ms）；**4.5 s** 在 245 次 `_movement_envelope`（每个行动者 3 次同参数：两条技能通道各一次、包络一次），每次里 `Traversal.prepare` 扫 2 220 格 9.5 ms；开阔图（36 关）上洪泛回溯对 22 500 个路径元素逐个 `stop_error`。没有一处是"同一起点同一棋盘算了两次整图路由"——棋盘每步都变，跨行动者／跨回合记忆化 `full_routes` 命中率为零，因此没做。

现行做法与所有权（全部是纯函数的等价重写或只读中间结果的复用；规则语义、RNG 次数与顺序不变）：

| 层 | 做法 | 键／生命周期 | 失效 | 拥有者 |
| --- | --- | --- | --- | --- |
| 一次洪泛内（`TacticalGridRules.movement_reachability_envelope`） | 每个被阻挡格的阻挡者回执只建一次（`blockers_by_coord`），占位由 `Footprint.occupants(units)` 一次建成的全员占位表解析（与 `unit_at` 同语义：名册顺序第一个阻挡单位，否则最后一个 no-block 单位），首个被阻挡格时懒建；路径回溯按父状态复用数组（`routes_by_state`：path／path_costs／path_stops ＝ 父数组 `duplicate` ＋ 1 格，每条 route 仍持有自己的数组，无别名），每格 `stop_error` 只问一次（`stop_errors`）；每个展开状态只算一次 `costs[state]` 与 `onward_penalty`，邻格只算 `arrival_cost`（`step_cost` ＝ 两者之和，供 `path_costs` 等调用方） | 局部变量，一次洪泛调用 | 随调用结束丢弃 | 洪泛函数自己 |
| `Traversal.prepare` 上下文 | 遍历 tiles 时同时建 `flags`／`heights`（`elevation` 规则，`blocks_movement`→255）／`move_costs` 三张每格表；`transition_error`／`step_cost`／`height_delta` 读表（缺格默认 0／1 与原 `tiles.get` 默认相同）；`tiles` 形参保留（调用方形状不变，改名 `_tiles`） | 上下文字典，由调用方持有 | 与调用方一致 | `ActorTraversalRules` |
| 一个 AI 回合内（`_prepare_ai_turn` 的 `work`） | `_ai_approach_routes` 先 `Traversal.prepare` 一次存 `work["traversal"]`（被拒则存空，让各洪泛按原顺序自行报错），`full_routes` 与 `_ai_action_candidates` 的 `_movement_envelope` 共用；`_ai_action_candidates` 只算一次包络，传给技能候选（S14 起为不含校验的 `_ai_skill_plans`）、友军支援与物理候选。`movement_reachability_envelope`／`AINavigationRules.full_routes`／`BattlePlayLoop._movement_envelope` 各加可选尾参 `traversal` | `work` 字典，一次 `_prepare_ai_turn` | 随回合准备结束丢弃 | `BattleLoopAI` |
| 跨回合、跨行动者（唯一的静态缓存） | `BattleLoopAI._row_validation`：`_ai_target_rows` 的每单位输入校验（`StaminaRules.input_error` → `ExperienceRules.input_error` → `CoreCombatRules.input_error` 的第一个错误）按 **精确字节** 记忆化：`units[unit_id] = {"bytes": var_to_bytes(unit), "error"}`；命中要求字节完全相同（62 µs 比对，类型敏感，不用 `==`／`hash()`）；`equipment_items` 引用（`is_same`）变化即整体丢弃（另一场战斗、读档合成的 loop）。它不是 loop 的键：不复制、不存档、不进 `same_state`／`==`／`hash()`；大小 ≤ 当前战斗单位数。诊断开关 `HSL_AI_PREP_CACHE=0` 走无缓存路径（A/B 计时用，默认开，结果相同） | 静态变量；一场战斗 | 单位字节变化→该单位重算；`equipment_items` 引用变化→整表丢弃 | `BattleLoopAI._row_input_error` 唯一读写者 |

不做的（S12 消融）：按 `tiles` 引用记忆化 `Traversal.prepare` 的三张表——`tests/run_actor_traversal_tests.gd` 等在同一 tiles 字典上原地改格后再洪泛是合法用法，按引用键会陈旧，不健全；跨行动者／跨回合记忆化 `full_routes`——棋盘每步变化，同键不会重现；改洪泛为 Dijkstra——展开顺序变会改等代价路径的 tie-break；`full_routes` 传入上下文时跳过自己的 tile 校验循环（每行动者 ≈2 ms）——为省 4% 引入"已校验则跳过"的条件路径，不值。

对照方法：基线 `db8d03f7` 的 `TacticalGridRules`＋`ActorTraversalRules` 复制为临时脚本，与本树对 44／36／45／51／12／517／38／34／32 关全部存活单位 × 3 种预算（`move_point`／整图／18）共 930 次 `movement_reachability_envelope` 输出 `var_to_bytes` 逐字节相同；规则套件 checks 数不变；sweep `results.json` 逐字节相同；`measure_loop_copy.gd` 的前瞻决策复制次数／模拟次数／行动者不变。

## 量化 S12

`tests/measure_loop_copy.gd -- 44 45 51 36`，2026-09-22 深夜，基线树（`db8d03f7` 导出）与本树**同时**运行（同一负载，load 2–6）：

| 战斗（AI 单位） | 一回合 ms 前→后 | `_prepare_ai_turn` ms 前→后 | target_rows | approach_routes | action_candidates | 一次前瞻决策 ms 前→后（模拟回合／复制次数不变） |
| --- | --- | --- | --- | --- | --- | --- |
| 44（75） | 13 344 → 3 974（×0.30） | 12 034 → 2 905（×0.24） | 2 919 → 191 | 6 631 → 1 641 | 2 232 → 804 | 40 879 → 19 431（×0.48；2／547） |
| 45（35） | 4 026 → 1 943（×0.48） | 2 771 → 1 416（×0.51） | 603 → 56 | 897 → 554 | 1 159 → 691 | 29 666 → 15 865（×0.53；3／423） |
| 51（11） | 690 → 268（×0.39） | 615 → 197（×0.32） | 79 → 6 | 363 → 126 | 136 → 35 | 1 523 → 811（×0.53；4／81） |
| 36（9，开阔图） | 3 005 → 876（×0.29） | 1 931 → 697（×0.36） | 57 → 6 | 1 632 → 612 | 207 → 45 | 18 141 → 6 516（×0.36；3／236） |

128 场 sweep（`run_autoplay_sweep_tests.gd`，两树同时跑，见 `ignored/lane-reports/S12.md`）：基线 1 053.5 s → 本树 636.1 s（×0.60，−40%；两树同时起跑，本树先跑完后基线独占 7 分钟，比值偏保守）；上一对（缺最后一步离格惩罚提取）1 014.5 s → 757.0 s（×0.75）。三次 sweep 的 `results.json` 与基线逐字节相同。剩余时间的去向：开阔图上洪泛展开本身（每次转移 ≈3 µs，已接近 GDScript 调用开销的下限）、`AISupportPlanning.prepare`／`AISkillPlanning.prepare`（每行动者 ≈10 ms）、以及 sweep 里可选战斗（5xx）约一半时间在场景／固定帧率的表现层而非 loop。

## 前瞻指挥官自身（现行合同，S13）

`tests/support/AutoplayBrain.gd` 不是产品代码，但深门章节 autoplay 的 600 s 预算（`HSL_CHAPTER_BUDGET_SECONDS`）大半花在它的前瞻决策里。S13 临时插桩（未提交）量到：44 关一次决策 49.8 s 里 **22.9 s** 是 22 张 board 各对 73 个敌人整图洪泛建威胁图（`_board`，1 602 次洪泛；模拟回合里每次玩家落地、每次估值都新建一张），**5.5 s** 是 `_path_cost` 每个 (单位, 格) 一次 `Loop.movement_path`——每次都整图洪泛同一个包络（386 次），模拟回合的 AI 步（规则侧）19.3 s。做法（决策序列不变：同种子下每条 `AUTOPLAY_BRAIN round=… pick=…` 与候选行逐字相同）：

| 层 | 做法 | 键／生命周期 | 拥有者 |
| --- | --- | --- | --- |
| 移动包络 | `_envelope_cache` 每单位一份 `Loop._movement_envelope`（`envelope:<id>`），可达格与每格路径长都从它读 | 与原 memo 相同：每条命令／每个模拟步清空，模拟与估值时换入空表 | `_movement_envelope` |
| 威胁图 | `_board` 只列 `threat_foes`（`enemies` 顺序、武器偏移、上界 ＝ `move_point` ＋ 最长偏移的曼哈顿距离）；`_threatening` 经 `_threat_at` 按格查询，只洪泛上界内的敌人，每格 id 列表记在 `board["threat"]`，顺序同原来的 `enemies` 顺序。上界成立是因为洪泛每步代价 ≥1（`ActorTraversalRules.tile_error` 拒绝 `move_cost` < 1，被拒的地图不洪泛）；缺 `move_point` 的敌人不设上界 | board 自己；敌人包络仍走同一 `_envelope_cache`，所以 board 只能在它的 loop 的 memo 期内查询（现有调用都是） | `_board`／`_threat_at` |
| 模拟 AI 步 | `select_lookahead` 期间打开 `_ai_step_memo`：同一决策里每个候选都从同一 loop、同一种子起跑，行动单位落地相同的两个候选之后 AI 回合逐步相同；键 ＝ 全部非 `CONFIG_SHARED` 键的 `var_to_bytes`（类型敏感）＋ RNG state，且配置块为同一引用；命中返回记录的 loop 并把 RNG 置到该步之后的 state（依赖本页合同：规则是不写输入的纯函数） | 一次决策；结束即清空 | `_step_ai_turn` |

模拟步数（`LOOKAHEAD_STEP_BUDGET` 计数）与模拟次数不变；只有 `sim_msec` 与 `measure_loop_copy.gd` 的前瞻复制次数（44 关 547 → 531，命中的 AI 步不再复制）变。

不做的（S13 消融）：玩家落地也进这份 memo（键另带 `_grounding_signature`：每种方案在该单位走的分支读的全部字段）——命中率 5 关 12／104、3 关 15／114，省下不到决策的 3%，而签名必须随 `_ground` 每个分支同步改（并行 lane 给方案加新种类时漏改即静默串用），删掉；剪枝、少模拟一回合——改决策，不在范围内。剩余：决策时间现在约 3／4 在模拟回合的 `step_ai_turn`（规则侧，S12 的范围），指挥官自身（候选、落地里的格搜索、估值）约 1／7（5 关 3 回合插桩：21.1 s 决策里 AI 步 15.5 s、落地 3.8 s 其中一半是规则命令）。

对照方法：基线树（`git archive ceeb8b5f` 导出）与本树同时起跑：纯 loop 前瞻单跑（临时脚本，5／3／52 关各 3 回合、44 关 2 回合、12 关 1 回合）每条 pick 行＋候选行（去掉 `sim_msec`）＋每步单位哈希 diff 为空；章节走查以临时包装脚本给全局 RNG（大地图遭遇骰子）播种，使两树走同一组战斗，7 场正式战斗 143 条 pick、990 行 diff 为空，两树写出的 `chapter.json` 逐字相同。

## 量化 S13

两树同时起跑（同机，负载见列）：

| 指标 | 基线 `ceeb8b5f` | S13 | 比 | 负载 |
| --- | --- | --- | --- | --- |
| 一次前瞻决策 44 关（`measure_loop_copy.gd`，2 次模拟） | 28 868 ms／44 835 ms | 13 412 ms／17 753 ms | ×0.46／×0.40 | 4–18 |
| 一次前瞻决策 5 关（4 次模拟） | 2 890 ms／9 472 ms | 1 885 ms／2 705 ms | ×0.65／（基线遇负载尖峰） | 4–18 |
| 章节一趟（全局 RNG 种子 1，7 场，无预算） | 587.6 s | 317.9 s | ×0.54 | 9–15 |
| 章节一趟（全局 RNG 种子 2，8 场含 506） | 885.5 s | 457.5 s | ×0.52 | 30–75 |

## 规则侧 AI 回合（现行合同，S14）

S13 之后决策耗时约 3／4 在模拟回合的 `step_ai_turn`（规则侧）。S14 临时插桩（未提交）量到：44 关一回合 AI（load≈30）15 s 里，洪泛展开 3.3 s、地图逐格校验与每格表重建 2.1 s、技能输入校验 4 次／行动 1.5 s、整库复制 3 次／行动 1.5 s、`_prune_ai_calls` 的 O(n²) 查找 0.5 s；章节关（51／52／3／5）上整图洪泛占一步的 55–60%，其中路由回溯（逐格复制父路径建路由字典）占洪泛 25–33%。做法（全部是纯函数的等价重写、只读中间结果的复用或调用方已持有的所有权；RNG 次数与顺序、遍历与平局顺序、每个字节不变）：

| 层 | 做法 | 键／生命周期／所有权 |
| --- | --- | --- |
| 洪泛内层（`TacticalGridRules.movement_reachability_envelope`） | `transition_error`／`arrival_cost`／`onward_penalty` 对单格体型内联（3×3 仍调 `transition_error`）；状态编号 `(y*width+x)*4+来向`（起点单独一格），`costs`／`parents` 为按状态下标的 `PackedInt32Array`，`best_state` 按格；每格 flags／高度／代价／no_block 读上下文的行主序紧凑表 `cell_*`；`best` 字典仍按首次到达顺序记格（输出顺序） | 局部变量，一次洪泛 |
| 地图每格表 | `ActorTraversalRules.tile_tables(tiles, map_size)`：三张字典表＋`max_cost`＋行主序 `cell_flags`／`cell_heights`／`cell_costs`（缺格 0／0／1）；`prepare(actor, units, tiles, tables, map_size)` 复制 `cell_flags` 叠加单位侧位、另建 `cell_pass`，上下文带 `size`。上下文 `size` 与本次 `map_size` 不符时洪泛用 `_cell_rows` 从字典现建同值表 | `BattlePlayLoop._tile_tables`：按 `TerrainEditRules.tiles(loop)` 的引用（`is_same`）＋`map_size` 记忆化，loop 外静态变量（不复制／不存档／不比较）。依据本页合同：`tiles` 是 CONFIG_SHARED，`create()` 后不原地写，测试改地图先 `TestSuite.own` 换引用。AI 回合与 `_movement_envelope` 经 `_traversal_context` 取上下文；直调 Grid／Traversal 的纯函数调用方每次现建 |
| AI 整图路由 | `movement_reachability_envelope` 可选 `route_cells`（格集合）：展开相同，之后只解析这些格（路由、停留判定、reachable／transit 归属），null 解析全部；`AINavigationRules.approach_goals`（每个敌人的目标格，不依赖洪泛）＋`approaches(full, goals)`；`_ai_approach_routes` 先算目标格再带着并集洪泛，目标格的失败回执仍排在洪泛失败之后；`full_routes` 拿到被接受的上下文时读其 `max_cost`、不再逐格校验地图 | `prepared["full_routes"]` 只含目标格与行动者本格的路由（唯一读者 `approaches`） |
| 重复校验 | `_ai_skill_plans`（`_ai_action_candidates` 用，不重复 `_skill_input_error`；`_ai_skill_candidates` 仍校验）；`step_ai_turn` 校验过的技能输入经 `skill_inputs_checked` 不在预检里再跑；`ExperienceRules.input_error(…, enhancement_checked)`（`_skill_input_error` 传 true）及 `ProgressionRules.enhancement_reads_growth` 略去已完成的 refresh 检查；`enhancement_profile_error` 调无校验的 `_refreshed_growth_stats` | 形参默认值保持原行为；只有已在同一状态上做过同一检查的调用方关闭它 |
| 所有权 | `step_ai_turn` 把自己的 `next` 交给 `_ai_take_owned_turn` 原地进行（被拒步骤复制未改的输入 `loop`，与 `next` 状态逐字节相同）；`_finish_ai_or_continue` 就地写调用方交来的 loop（两个调用方都交出自己持有的 loop）；`_prune_ai_calls` 一次建 id 索引 | 对外「规则不写输入」合同不变：规则入口仍先复制 |

不做的（S14 消融／试过无效）：洪泛状态用 int 键字典代替 Vector3i 键（无收益，字典哈希本身才是开销）；内层全整数坐标＋阻挡回执延后到洪泛后统一建（±5% 噪声内，删掉）；`refresh_input_error`／`enhancement_profile_error` 按单位字节记忆化（命中率高，但要在纯规则模块里加以 `equipment_items` 引用为键的静态缓存，测试与工具会传自有、可原地改的装备表，按最保守取舍未做）；去掉 `_finish_ai_or_continue` 以外的整库复制（`_return_to_player` 等调用方多、收益小）；把 `_row_input_error` 的字节比对换成 `==`（类型不敏感，S12 已否决）。剩余：开阔图上整图洪泛展开本身（每次转移约 1 µs，已接近 GDScript 下限）；44 关的友军支援规划（`prepare_cast` 里每个候选中心对施法者与目标各跑一次 `refresh_input_error`）；`_ai_target_rows` 每行动者对全部单位的字节比对。前瞻指挥官的威胁图直调 `TacticalGridRules.movement_reachability_envelope` 不带上下文，每次现建地图表（44 关约 15 ms／次，load≈25）——改经 `Loop._traversal_context` 可省大半，属 `tests/support/AutoplayBrain.gd` 的范围。

对照方法：基线 `TacticalGridRules`＋`ActorTraversalRules` 复制为临时脚本，与本树对 9–12 关全部存活单位 ×（move_point／整图／18）× 4 种体型探针（原样、飞行、3×3、3×3 飞行不阻挡）× 5 种上下文来源洪泛输出 `var_to_bytes` 逐字节相同，另把一半单位改成 no_block 再比；`route_cells` 惰性与全建对照 31 万项相同；纯 loop 逐步状态摘要（44／5／3／52／12 关各 3 回合、每步非配置键 `var_to_bytes` 的 md5＋RNG state，489 行）与基线相同；规则套件 checks 数不变；sweep `results.json` 与播种章节走查 `chapter.json` 逐字节相同。

## 量化 S14

两树同时起跑（同机，负载见列），详见 `ignored/lane-reports/S14.md`：

| 指标 | 基线 | S14 | 比 | 负载 |
| --- | --- | --- | --- | --- |
| 一次敌军回合（纯 loop 第 1 回合全部 AI 步），44 关（75 步） | 10 596 ms | 4 838 ms | ×0.46 | 14–22 |
| 同上，5 关（9 步） | 624 ms | 235 ms | ×0.38 | 14–22 |
| 同上，52 关（R35 后，15 步） | 1 475 ms | 482 ms | ×0.33 | 14–22 |
| 同上，12 关（开阔图，32 步） | 6 339 ms | 1 972 ms | ×0.31 | 14–22 |
| 128 场 sweep（合并树对 pipeline-line `329121ef`） | 907.1 s | 513.9 s | ×0.57 | 21–40 |
| 章节走查，全局 RNG 种子 1（S14 合并前树对 `9a84b912`，7 场） | 423.9 s | 184.4 s | ×0.43 | 17–26 |
| 章节走查，种子 2（同上，8 场含 506） | 467.9 s | 252.7 s | ×0.54 | 17–48 |
| 章节走查，种子 1／2（合并树对 `329121ef`，R35 后停在 52 关，2 场） | 82.2／94.6 s | 35.0／41.3 s | ×0.43／×0.44 | 16–26 |

基线先跑完的一方在对方结束后独占机器，比值偏保守。深门（合并树，jobs=3）：章节 40.0 s／600 s 预算、sweep 423.2 s。

## 量化 S6e

`tests/measure_loop_copy.gd`，2026-09-23，同机 load ≈ 9。

| 战斗 | 单位 | 整库字节 | 配置字节（共享） | 状态字节（仍复制） | 字节比 | `duplicate(true)` | `copy` | 一回合整库复制次数 | 一回合复制字节 前→后 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 44 | 84 | 2 007 788 | 1 442 084 | 565 704 | 3.5× | 7.5 ms | 2.3 ms | 283 | 568 MB → 160 MB |
| 45 | 44 | 1 721 984 | 1 437 808 | 284 176 | 6.1× | 4.7 ms | 0.9 ms | 168 | 289 MB → 48 MB |
| 38 | 44 | — | — | — | — | 6.7 ms | 1.8 ms | 172 | — |

字节比未到设计页预期的 ≥10×：剩余字节几乎全是 `units`（84 人 540 KB）。一回合墙钟时间由 AI 搜索主导且受同机负载影响大（同一基线在两次运行间 17.7 s／27.1 s），不作为指标。

## 验证

- `tools/godot.sh --headless --script res://tests/run_all.gd`：34 个规则套件全部 PASS 且 `assert_config_frozen` 通过，checks 数与落地前相同（112754）。
- `tools/godot.sh --headless --script res://tests/measure_loop_copy.gd [-- 44 45]`：重跑上两表（每关 7 行 `LOOP_COPY_MEASURE level=…`：字节／前十大键／units 字节构成／复制微基准／一回合复制次数与占比／`_prepare_ai_turn` 分阶段占比／一次 lookahead 决策的复制次数）。`BattleLoopConfig.copy_count` 只为它计数。
- 128 场 sweep（`tools/verify.sh --deep`）结果逐字不变；存档 v3 往返在 `tests/run_battle_reward_tests.gd` `checkpoint_cases` 及各套件的 F9 往返断言中覆盖。

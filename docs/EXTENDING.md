# 扩展与修改指南（How to extend the remake）

面向要改剧情、加关卡、换配乐或调整流转的人／Agent。原则：**规则与表现分离、内容数据驱动**——绝大多数改动落在 `content/` 的 JSON 与 `tools/` 的生成器上，不需要改 Godot 代码；改动后按下面的"验证"一节跑对应检查即可。

## 内容在哪里

| 想改什么 | 去哪里 | 说明 |
| --- | --- | --- |
| 战役流转（哪一关接哪一关、哪一关是正式战斗／预览／过场） | `content/battles/campaign.json` | `battles["N"]` 一行一关：`scenario`（场景 JSON 或 `.tscn`）、`title`、`kind`（省略＝正式战斗；`story`＝剧情场景／开场预览；`game_clear`＝谢幕）。运行时 `CampaignProgress.next_destination` 只看这张表；`tools/hsltools/data/campaign_overview.py` 生成[战役总览](evidence_packets/resource_inventory/campaign_overview.md) |
| 导入素材放哪一层 | `content/imported/hsl/shared/`（引擎直读、每关共用：界面音效、切入绝技与魔法特效、SHP 预览、面板、命令菜单、范围格、共享走路帧／音效）；`content/imported/hsl/chapter01/battleNNN/`（逐关：地图、物件、肖像、时间线、对白证据、关卡走路帧／音效） | 引擎只经 `game/sim/ContentPaths.gd` 取 `shared/` 路径，逐关路径由场景 JSON 的 `resources` 给出；`game/` 里出现 `chapter01` 目录名即 `hsl check engine:chapter_paths` 失败（唯一例外：`## provenance:` 头引用章节导入作证据） |
| 原作全部剧本文本与动作顺序 | `content/imported/hsl/story_corpus/` | 152 STORY／130 winfail／STORYOVER／TOWNDEF 的机器可读语料（`tools/hsltools/data/story_corpus.py`），改剧情前先在这里查原文与流转 |
| 某一关的开场／过场场景 | `content/battles/story_NNN.json` ← `python3 tools/hsl.py generate story_scene:N` | 由 seed、timeline、对白证据、地图物件、角色清单生成；该关 `content/battles/levels/NNN.json` 的 `story_scene` 分区决定标题、结束卡、玩家槽绑定与追加说明句（[关卡档案](architecture/LEVEL_PROFILES.md)）；`skip_battle`（胜利段写入）与 `select_event_timelines`（脚本内二选一）由生成器自动写出 |
| 一关的数据链（地图／地形／脚本／物件／角色／音效） | `tools/hsltools/levels/seed.py` → `hsltools/levels/sounds.py` → `hsltools/levels/source_texts.py` → `hsltools/levels/timeline.py`＋`hsltools/levels/timeline.py` → `hsl_chapter_dialogue.py`（说话人表来自 `levels/NNN.json` 的 `speakers`）→ `hsltools/levels/map_objects.py` → `hsltools/levels/actors.py`（演员清单来自 `levels/NNN.json` 的 `cast`）→ `hsltools/levels/story_scene.py` | 每步都有 `--check`；`tools/verify.sh` 每关一个离线块。新关卡照 `git show b93f655` / `5ff8977` 的模板逐步加表项 |
| 正式战斗场景 | `content/battles/battle_NNN.json` ← `python3 tools/hsl.py generate level_battle:N`（通用组装器：预览 `story_NNN.json` 的开场／绑定／资源／EVEF cast ＋ seed 的 STORY 走位终点／winfail／物件表 ＋ 已审核来源模板；该关 `content/battles/levels/NNN.json` 的 `battle` 分区只写输出名、结果标签、初始焦点、角色覆盖与预期人数，需要时加 `unit_ids`／`initial_unit_state`（见 [LEVEL_PROFILES](architecture/LEVEL_PROFILES.md)）；同时写出 `content/generated/hsl/treasures/battle_NNN.json`。任务由 profile 的 `battle` 分区注册，首建新关也是这一条命令。第一章 51／52／53 与其余主线关同一条链，没有例外）；仅 1／2 关仍是手工场景 `hsltools/data/ohm_village.py`／`hsltools/data/gol_road.py` | 规则由 `WinfailScenarioRules` 直接解释 seed 的 WINFAIL；把 `campaign.json` 的该关从预览换成战斗场景即接入，预览与走查自动让位；注册后 `tests/run_battle_sweep_tests.gd` 自动覆盖（开场→首次控制→强制胜利→交接；胜利条件不是清敌时在 `levels/NNN.json` 写 `sweep_fixture`），窗口化回执用 `tests/capture_battle_review.gd -- --level=N`。前置：该关全部演员有模板（`content/generated/hsl/actors/`／`first_battle.json`）、winfail token 全在解释器支持集内（`content/generated/hsl/static/hsl01/winfail_token_coverage.json`）、`levels/NNN.json` 的 `cast.speakers` 含 winfail 段说话人 |
| 胜负／事件脚本能用哪些 token、参数形状与解释器读法 | [WINFAIL_TOKENS](WINFAIL_TOKENS.md) ← `python3 tools/hsl.py generate winfail_token_table` | 词表常量在 `game/sim/WinfailCompiler.gd`（token 行尾 `# 语义` 注释即表中语义列，缺注释时 `hsl check winfail_token_table` 失败）；新 token 先加词表与 `WinfailConditions.condition_holds`／`WinfailActions.apply_actions` 分支，再 `generate winfail_coverage`（需原版 PAK）与 `winfail_token_table` |
| 城镇菜单与事件 | `content/world/town_initial_trees.json`＋`content/imported/hsl/global/world_map/towndef.json` | 191 条 te 事件由 `TownEventRules` 解释；脚本对城镇树的改写（actAddTE 等）在交接时经 `WorldScriptActions` 施加 |
| 转职后哪座城怎么变（原作：雷歐納德／緹娜都拿到第二稱號后 兩棲族部落 关店、换 exec 事件） | `content/world/town_job_up_writes.json`（`hsl_town_job_up_writes.v1`：`second_tier.members` SID_* 成员、`town` town_* 符号、`writes` te 写入列表，参数序同 TOWNDEF.H） | `TownEventRules` 在 `teCheckJobUp2` 成功后只读这份表回放（缺表明确 `check_failed`，无内置列表）；改后 `python3 tools/hsl.py check town_job_up_writes`（符号／事件号／token 形状；`static-derived` 时还钉在 R11 原生存档的写入表上，改成别的城要把 `evidence_tier` 标 `authored`）＋ Godot `run_town_event_rules_tests.gd` |
| 酒館神秘男子的价格／货表／出现事件 | `content/generated/hsl/static/hsl01/secret_man_goods.json` ← `python3 tools/hsl.py generate secret_man_goods`（需原 EXE） | `TownEventRules` 的 `teAppearSecretMan`（rows[*].event）与 `teSecretManBuyThing`（price／items）只读它；`hsl check secret_man_goods` 离线核价与 ITEM.TXT |
| 大地图点位／路线／隐藏 | `content/imported/hsl/global/world_map/world_map.json`、`content/world/world_map_scene.json`（`new_game` 隐藏集） | 运行时状态 `hsl_world_state.v1` 随存档 |
| 配乐 | `content/imported/hsl/music/NN.ogg`（NN＝原曲号 02–19）与 `manifest.json` ← `python3 tools/hsl.py generate music_import`（读仓库外 Steam 經典版 `music\NN.wav`） | 哪个场景放哪首照 [原版配乐](evidence_packets/static_reverse/original_music.md)；标题与通关尾声的曲目写在 `content/imported/hsl/global/title/manifest.json`（`music`、`game_clear.music`），大地图／城镇写在 `content/world/world_map_scene.json`（`map_music`／`town_music`）；OGG 由 `project.godot` 的 `[importer_defaults]` 默认整首循环；播放器增益统一用 `GameSettings.MUSIC_PLAYER_DB` |
| 标题／系统菜单／谢幕美术与版式 | `content/imported/hsl/global/title/manifest.json` ← `tools/hsltools/assets/title_assets.py` | 版式常量（`ITEMS`／`SYSTEM_ITEMS`／`GAME_CLEAR` 等）在工具里，改后重跑并 `--check` |
| 职业公式、学习表、哪些角色是 live profile | `content/authored/roles/{job_formulas,learning_tables,roster}.json` | 角色链只以表为输入；步骤见下节[「角色与职业」](#角色与职业加一个职业或一名角色) |
| 续集的一关／一名角色（没有原作资源可导） | `content/authored/levelNNN/`（`level.json`、`story.txt`、`winfail.txt`、`messages.json`、`terrain.txt`）＋`content/battles/levels/NNN.json` battle 分区；角色行在 `content/authored/roles/characters.json` | `python3 tools/hsl.py generate authored_level:N` 组出 `content/battles/battle_NNN.json` 与 `content/generated/hsl/authored/` 下的 seed／timeline／对白／地形；再在 `campaign.json` 注册。逐步表（只写数据／必须改代码／必须有素材）与最小文件原文见 [AUTHORING](AUTHORING.md) |

## 角色与职业：加一个职业或一名角色

角色链（职业属性公式 → 学习表 → live profile → 入场成长）现在只读表：`game/sim/JobStatsRules.gd` 与 `tools/hsltools/model/jobs.py` 是同一张表的两个求值器，没有 per-job 分支。第一章 20 个职业的行由原生回执钉住（`hsl check probe` 的 216／184／44／1350 组完整返回、`role_profiles_proof`／`learning_tables_proof`）；新行标 `"evidence_tier": "authored"` 即不需要回执。

| 要加什么 | 改哪一行 | 然后 |
| --- | --- | --- |
| 一个职业的属性公式 | [`content/authored/roles/job_formulas.json`](../content/authored/roles/job_formulas.json) `jobs` 下加 `"NNN": {…}`：`caps`（str dex mind con 上限）、`allocation_quota`（自动分配配额）、`max_hp`／`max_mp`／`attack`／`defense`／`speed` 的项列表（`[mul, var, div]`＝`mul*var/div`，`[mul, var, div, pre]`＝`mul*(var/pre)/div`，裸整数＝常数；变量 `str dex mind con level hp_level`）、`magic_attack`（`terms`＋可选 `cap`／`soft_knee`＋`bonus`）、`resist`（`cap`＋五行 `[p, div]`）；80–100 的 code 用 `content/imported/hsl/global/tables/TYPE.H` 的 `#define jobXxx NNN` 作名字（100 = `jobDarkAngel` 原版有代号无公式）；其他 code 是授权职业，行内写 `"symbol": "jobXxx"` 自己起名（不得与 TYPE.H 重名／重号，角色行 `job =` 就写这个名字，TYPE.H 不改） | `python3 tools/hsl.py generate job_formulas` → 运行时表 `content/generated/hsl/roles/job_formulas.json`；`JobStatsRules`／`EntryGrowthRules`／`EquipmentRules` 自动认识该 job |
| 该职业学什么 | [`content/authored/roles/learning_tables.json`](../content/authored/roles/learning_tables.json) `jobs` 下加 `"NNN": {"tier": 1, "magic": [{"id": "magic:magicWATER:magicCode06", "level": 3}], "special": [{"id": "special:magicAIR:magicCode01", "tier": 1, "attributes": {"str": 26, "dex": 20, "mind": 20, "con": 24}}], "evidence_tier": "authored"}`；id 是 MAGIC.TXT／SPECIAL.TXT 的 type／code（NN = code+1），名字生成时从 RESOURCE.TXT 解析 | `python3 tools/hsl.py generate growth_lifecycle_data` |
| 一名角色 | `PLAYERS.TXT` 加一段 `[character]`（`code`、`job = jobXxx`、`mode = pmXxx`、`str/dex/mind/con`、`level`、`move_point`、装备槽、`magic_*`／`special_*`、`resist_*`…），再把 code 加进 [`content/authored/roles/roster.json`](../content/authored/roles/roster.json) `actors` | `python3 tools/hsl.py generate role_data entry_growth_data growth_lifecycle_data`：`roles/profiles.json` 得到它的 `profile`／`initial`（模型按初始等级＋声明装备算出），`entry_growth.json`／`growth_lifecycle.json` 得到它的入场参数与初始 mask |
| 一个全新招式（没有 SPECIAL.TXT／MAGIC.TXT 行） | [`content/authored/roles/skills.json`](../content/authored/roles/skills.json) `skills` 下加一行（原表字段＋`channel`／`name_text`，code 以 `authored` 开头；表现指已有 specCode／effCode 段或 `scripts` 里的新段），角色在该招元素的声明栏写招名（`special_fire = 龍炎斬`）；字段表见 [AUTHORING #13](AUTHORING.md#授權招式表欄位contentauthoredrolesskillsjson) | `python3 tools/hsl.py generate initial_skill_book skill_target_data authored_effect_scripts growth_lifecycle_data`；效果族只收 `magicFun_Attack`（原生绝技／魔法伤害），其他族与新 opcode 生成即失败并说明 |
| 验证 | | `python3 tools/hsl.py check job_formulas role_data growth_lifecycle_data entry_growth_data role_profiles_proof learning_tables_proof`；Godot `tools/godot.sh --headless --script res://tests/run_all.gd -- run_job_stats_tests.gd run_entry_growth_tests.gd` |

续集角色不进 `PLAYERS.TXT`：写进 [`content/authored/roles/characters.json`](../content/authored/roles/characters.json)（同一套 PLAYERS 字段，`tools/hsltools/sources/tables.py character_rows()` 把它接在原表之后，七张全局表与名册脸表自动长出该行；原表哈希不动，58 个原生探针包照常）。步骤、最小行与仍然阻塞的点（新素材等）见 [AUTHORING](AUTHORING.md)。

## 手写一场战斗：battle JSON 的合同

`content/battles/*.json` 里 `rule_adapter` 为 `winfail`／`development_battle` 的文件是战斗，装载时按 [`content/schema/battle.schema.json`](../content/schema/battle.schema.json)（`hsl_battle.v1`，手写）校验：`required` 是没有默认值能顶替的输入（`schema`／`id`／`title`／`rule_adapter`／`player_unit_id`／`playable_units`／`resources.{map_texture,terrain,attack_ranges,consumables,progression}`／`scenario_rules.initial_objective_phase`），其余 `create()` 会读的键都带 `default`，`BattleScenario.load_file` 先填默认再交给 `BattlePlayLoop.create`；违规明确失败（`scenario_error = "battle_schema:$.<path>: <reason>"`，Python 侧 `hsl check battle_schema` 同一文本）。适配器读哪个脚本资源（`winfail`→`battle_seed`、`development_battle`→`development_objectives`）由 `create()` 以 `missing_battle_script_payload` 检查。场景进入 `BattleSceneRuntime` 还要 `actor_walk_manifest`／`actor_audio`／`interface_audio`（表现输入，缺则 push_error）和对白 speaker 表 `portraits`（缺则该场对白无脸）。引擎级全局表（技能书／targeting／成长／AI profiles／奖励／装备目录／名册肖像表）不在 `resources` 里，登记在 `game/sim/ContentPaths.gd`。

单位只需要 [`content/schema/unit.schema.json`](../content/schema/unit.schema.json) 的 20 个规则键（`tools/hsltools/schema/unit.py` `RULE_KEYS`）；证据台账 `*_evidence_tier`／`*_source`／`position_note`／`growth_profile.evidence`（`PROVENANCE_KEYS`）一键不写，运行时按 `authored` 标记。最小手写 battle JSON 的原文是 [`tests/support/authored_minimal_battle.json`](../tests/support/authored_minimal_battle.json)（`tests/run_authored_battle_tests.gd` 证明它能被 `create()` 接受、在 headless 里开到首次控制并让 Autoplay 打完几回合）。**要加一关**不必手写这份 JSON：写 `content/authored/levelNNN/`（原脚本文法的 STORY／winfail、对白、ASCII 地形、单位表），`hsl generate authored_level:N` 组出同形的 `battle_NNN.json`；路线与逐步表见 [AUTHORING](AUTHORING.md)。

## 运行时的入口（改表现或加机制时）

- 场景与开场：`game/battle/scene/BattleSceneRuntime.gd`（宿主）→ `game/battle/runtime/BattleOpeningCoordinator.gd`（编译 timeline 的逐 token 播放：对白、走位、镜头、物件、效果、选择提示、结束卡）。新增脚本 opcode 的表现：在 `tools/hsltools/levels/timeline.py` 的 `ACTION_KIND` 映射 kind，再在协调器 `_apply_event` 加分支；没有分支的 kind 走 `RECORD_ONLY_KINDS`（记录不演）。
- 战斗规则：`game/sim/`（`TacticalGridRules`／`CoreCombatRules`／`CoreTurnQueue`／`WinfailScenarioRules`…），唯一可变战斗状态在 `BattlePlayLoop.gd`。
- 大地图／城镇：`game/world/`（`WorldMapRules`／`WorldMapRuntime`／`TownRuntime`／`TownShopScreen`／`TownEventRules`／`WorldScriptActions`）。
- 外壳：`game/title/`（标题、GAME OVER、GameClear）、`game/battle/scene/BattleSystemMenu.gd`（战斗内／战间卷轴）、`game/settings/GameSettings.gd`。
- 战役持久化单一出口：`game/battle/runtime/CampaignProgress.gd`（hand-off、自动存档、回憶錄、戰場記錄）。
- 新增任何 `game/**/*.gd`：文件头加 `## provenance:` 块（五维度来源，格式见 [ARCHITECTURE「Provenance headers」](ARCHITECTURE.md#provenance-headers)），然后 `python3 tools/hsl.py generate provenance` 更新 [PROVENANCE](PROVENANCE.md)；缺块门禁 FAIL。

## 验证（改完做什么）

1. 改了生成器或表：重跑该关的生成命令，然后跑该关命中的检查（`python3 tools/hsl.py list '*:37'` 列出该关的任务，`python3 tools/hsl.py check '*:37'` 只跑它们；或直接 `tools/verify_runner.py checks` 并行跑全部），再 `python3 tools/hsl.py check story_corpus`（说话人表变了要重建语料）与 `hsltools/data/campaign_overview.py`。
2. 改了运行时或注册：Godot headless 跑 `tests/run_story_scene_tests.gd`（含**全部注册剧情场景的扫描**：启动→跑完→交接），大地图／城镇改动加 `run_world_map_tests.gd`／`run_town_scene_tests.gd`，流转改动加 `run_story_mode_walkthrough_tests.gd`；按需跑 `run_story_mode_explorer_tests.gd`（20 分钟，自动走全图）。
3. 合并前跑快门 `tools/verify.sh`，阶段收口跑 `tools/verify.sh --full`（可用隔离 HOME 与另一条线并行，见 [PROJECT 验证一节](PROJECT.md#validation)）。
4. 玩家可见的版式／动效改动要窗口化截图（`tests/capture_*_review.gd`）并写进对应 evidence packet。

## 证据用语

新结论只用 `resource-derived`／`static-derived`／`runtime-measured`／`user-confirmed`／`user-hypothesis`／`provisional`／`negative-evidence`；改剧情属于重制决定，请在场景 `unresolved_semantics` 或 packet 里写明"重制读法／原创"，不把改动说成原版等价。

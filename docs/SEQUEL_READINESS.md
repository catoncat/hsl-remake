# 第四轮：续集就绪（Sequel readiness）

> 状态：**已收口（2026-09-23）**——§2 唯一验收（level 200＋新角色只靠数据跑通）与全部派生 oracle 达成，见 §6；此后的作者入口问题直接进 [AUTHORING](AUTHORING.md) 与 PROJECT Next steps。计划自 2026-09-21 起。上一轮计划见 [PLAYABILITY](PLAYABILITY.md)；本轮依据两份只读 review（结构 R19、代码 R20，报告在仓库外 `ignored/reviews/`，结论摘要见 §2）。本文件只存目标、约束、lane 划分与收口状态；进度真相仍在 [PROJECT](PROJECT.md)。

## 1. 为什么

用户在第一章复刻完成后要**用这套引擎写续集**。续集没有原版资源可导入：关卡、角色、技能、剧情、城镇都要自己创作，走同一条运行时。两份 review 用同一把尺子（"新增一场战斗＋一个新角色要碰什么"）得出一致结论：**引擎骨架对（规则／表现分离、单一 PlayLoop 真相、数据驱动的 winfail／te 解释器、sim 无循环依赖），但作者入口不通**——每条内容产线都从 `hsl.pak`／EXE 探针出发；引擎把证据台账当必填字段；逐关知识散在 5 个 Python 字典＋1 个测试夹具；职业公式在两种语言各写一遍、学习表从 docs 证据包生成；第一战走另一套带 fallback 的手写规则；`First*`／`chapter01/` 已是引擎与全局资源的名字。

## 2. 目标与 oracle（tracer bullet）

**唯一验收：一场从零手写的新战斗 `level 200` 与一名新角色（新职业、新绝技）只靠写数据跑通整条链**——`content/authored/level200/` 的地图、地形、布阵、原脚本文法的 STORY／WINFAIL、新角色的表行 → `hsl generate` → `battle_200.json` → 标题→战役进入 → 开场剧情 → 机器人（`HSL_AUTOPLAY_LEVELS=200`）打到自然胜负 → 结果页；期间**不改任何 GDScript／Python 代码**，且 `hsl check provenance` 显示该关全部 `authored`。做到这一步之前，任何"续集就绪"的说法都不成立。

派生 oracle：`unit.schema` 的 required 只含规则键；`LEVELS`／`LEVEL_CASTS`／`SPEAKER_IDS`／`BattleForceWin` 的逐关分支为 0；`JobStatsRules` 无 per-job match；`FirstBattleScenarioRules` 删除且 51 关走通用路径；引擎目录内 `res://content/.../chapter01/` 字面量为 0；`docs/AUTHORING.md` 让新人 10 分钟内完成"加一关"的路径。

## 3. 不动的东西

- 单一可变真相仍是 loop 字典；拆文件只拆"同一字典上的静态模块"，不产生第二份状态（R19 F9 的分法）。
- 原版等价声明与证据语言不变；本轮把证据台账从**必填输入**降为**可选透传**，不是删除证据。第一章内容继续标原有标签；新内容标 `authored`。
- 不重写规则语义；重构以"生成物逐字节不变／既有套件断言不变"为默认 oracle，断言改动逐条列出。
- 现有 `verify.sh` 门禁与 deep 套件不放松；`hsl check` 的 stale-output 机制保留（作者数据走 `content/authored/` 输入，生成物仍由任务产生）。
- 第三轮在飞的 lane（R15 驾驭器前瞻、R16 逐单位 AI 参数、R17 来源声明、R18 面板）先收口；本轮 lane 与之不重叠文件，或等其合并后再派。

## 4. 工作协议

沿用 [PLAYABILITY §4](PLAYABILITY.md#4-工作协议)：负责人派 lane（fable high／opus）、fresh context、独立工作树、"验证过就提交"、负责人合并＋门禁＋快进 main。每条 lane 任务书写明：负责文件、oracle、不动的断言、消融候选。两条改同一文件的 lane 不并行。

## 5. lane 划分与顺序

| 波 | lane | 覆盖 review 发现 | 负责范围 | oracle |
| --- | --- | --- | --- | --- |
| 1 | **S1 逐关知识→数据** | R19 F3／R20 F11 | `hsltools/levels/{battle,story_scene,actors}.py`、`hsl_chapter_dialogue.py`、`tests/support/BattleForceWin.gd` → `content/battles/levels/NNN.json`（title／result_labels／role_overrides／casts／speakers／`sweep_fixture`） | 生成物逐字节不变；`force_win` 变 fixture 解释器；sweep 结果不变 |
| 1 | **S2 角色链→数据** | R19 F4／R20 F7 | `JobStatsRules.gd`、`EntryGrowthRules`、`EquipmentRules` 白名单；`model/jobs.py`、`data/role_profiles.py`、`data/growth_lifecycle.py` → `roles/job_formulas.json`＋以 `global/tables` 为唯一输入，探针包降为 check | `run_job_stats_tests` 216 原生返回不变；`run_campaign_actor_tests` 不变；新 job 行只加数据即可被生成 |
| 1 | **S3 PlayLoop 入口与 schema** | R19 F2／F15、R20 F3／F5／F10／F13（部分） | `BattlePlayLoop.create()` 管线化（`_fail`／`_load_x`）、删 `first_skill`／`mage_magic` 特例、`ContentPaths`、UI 肖像从 `resources`；`hsltools/schema/unit.py` 显式 `RULE_KEYS`／`PROVENANCE_KEYS`；`content/schema/battle.schema.json`；`evidence_tier` 默认 `authored` | 既有套件绿；required 数字断言按新表改（列出）；存档 schema bump |
| 1 | **S4 作者格式（tracer）** | R19 F1／F8 | 新 `GeneratedFilesTask`：`content/authored/levelNNN/{story.txt,winfail.txt,placements.json,terrain.json,map.png}` → `battle_seed.json`（复用 `seed.py` 抽出的纯函数与 `imported_script_ir` 解析器）；`docs/AUTHORING.md`（最小 battle JSON、terrain、timeline kind 词表、winfail token 表自动生成、unit 规则键、job／skill 数据行）；**level 200 端到端** | §2 的唯一验收；依赖 S1–S3 合并后收口（可先起步，缺口记进 AUTHORING） |
| 2 | S5 第一战并入通用路径 | R19 F5／F6、R20 小味道 | `level_battle:51` 组装 `battle_051.json`，`campaign "51"` 改指；删 `FirstBattleScenarioRules`／`FirstBattleScenario`／adapter 分支／默认加载；Runtime 第一战开场迁 coordinator，`StoryStage`／`_opening_*`／`SpatialContract` 退役 | 双路并行→测试迁移→删除；`run_battle_scene_runtime_tests` 断言变化逐条列出 |
| 2 | S6 引擎内部形状 | R20 F1／F2／F4／F6／F8／F9、R19 F9／F10／F12／F13 | 配置／状态分离（设计页 [BATTLE_CONFIG_STATE](architecture/BATTLE_CONFIG_STATE.md)：`Loop.copy` 按引用共享 21＋5 个只读键，签名不变）；`LoopKeys`／`Interaction` 常量；`SkillPresenter` 基类；模态面板表；winfail `_arg`＋handler 表＋单一 `script_requests`；`Runtime.apply_loop` 唯一写入口；PlayLoop→`BattleLoopInit/Rewards/AI/Script`；Winfail→Compiler/Conditions/Actions；`TownEventRules` 内容外移；sim→scene 反向依赖归位 | 断言不变为默认；性能：一次 AI 步的 `duplicate(true)` 次数与字节数下降（量出来） |
| 2 | S7 测试与产品面 | R19 F14、R20 F13／F15 | `FirstSceneReadback` → `tests/support`；Runtime 转发壳删除；`development/` 演练→fixtures；`TestSuite` 断言族＋15 套件接入；三级测试目录（需 verify_runner 枚举改动，负责人做） | 套件数与断言数不减 |
| 3 | S8 改名与文档收口 | R19 F7／F8、R20 F12／F14 | `first_scene`→`battle/scene`、`FirstScene*`→`Battle*`、UI 套件→`game/ui/`、`chapter01/` 共享资源→`shared/`；`class_name`＋删别名；outcome 结构化＋文案统一繁体；README／PROJECT／ARCHITECTURE 路径更正 | `hsl_docs_check`、全套件绿；纯机械 |

顺序理由：改名放最后（先解耦再改名，否则只是"名副其实但仍耦合"）；S6 的配置／状态分离需要一页设计再动，放第二波；S4 是 tracer，第一波并行起步、第一波末收口。

## 6. 收口状态

| lane | 结果 | 提交 |
| --- | --- | --- |
| S2 角色链→数据 | 20 job 公式／学习表／初始值成表；探针包降为 check；job 100 tracer 通过；作者要加的三处数据写进 EXTENDING | `dfd9b63b` |
| S1 逐关知识→数据 | 72 个 `levels/NNN.json`；删 ~3,800 行字典与 13 处 `if level==N`；夹具变 5 模式解释器；生成物逐字节不变 | `863532d2` |
| S3 PlayLoop 入口与 schema | create() 24 阶段管线；required 27→20（台账键可选、缺省 authored）；battle.schema required 8；拔 first_skill／mage_magic；ContentPaths；最小手写战斗 tracer | `69d2cb5a` |
| S4 作者格式 tracer | 第 200 关＋角色 102 只靠 `content/authored/` 数据到玩家；`authored_level:N` 任务族；`docs/AUTHORING.md` 19 步作者路径表（真正的续集阻塞：新素材、全新绝技、职业代号 >100、切入 manifest 路径、标题固定第一战） | `8be7d756` |
| S6b Winfail 拆分 | Compiler／Conditions／Actions＋门面；裸 `args[N]` 194→0；`docs/WINFAIL_TOKENS.md` 119 token 生成表；行为逐字节不变（99,184 检查同基线） | `87ebb0f2` |
| S6c 技能表现可插拔＋魔法 EFFECTS | `SkillPresenter` 合同；魔法 39 段 effCode 脚本经 `SkillEffectScriptPlayer` 播放（4/4 opcode）；删五个手写魔法模块；remake-invented 141→133 | `20fcc231` |
| S5 第一战并入通用路径 | 51 关由 `level_battle:51` 生成、走 winfail 适配器与开场协调器；删 FirstBattleScenarioRules／Scenario／StoryStage／SpatialContract 与 fallback；~95 测试迁 BattleFixture；撤离格按脚本改为城门 (8,6)（修正此前 provisional） | `1d9a46c6` |
| S6e 配置／状态分离 | `BattleLoopConfig.CONFIG_SHARED` 28 键按引用共享、`Loop.copy`；冻结断言（规则零命中）；存档 v3 只写状态；84 人战斗一回合复制 568→160 MB（3.5×，剩余为 units，copy-on-write 是下一堵墙）；设计页转现行合同 | `c45a25d1` |
| S6a＋S7 Runtime 唯一写入口／常量／模态表＋Readback 迁出 | `Runtime.apply_loop` 唯一写入口（118 处测试同走）；34 转发壳删；`FirstSceneReadback`→`tests/support/RuntimeReadback`；`modal_open()` 取代 6 处谓词；`Interaction`／`LoopKeys` 常量；Runtime 1231→1059 行 | `29e5d244` |
| P1 四件已定的玩家可见小事 | 切入原速（慢放为 `HSL_CUTIN_PLAYBACK_SPEED` 开发开关）；具名 NPC 显示专名（name id 306 为无名占位，数据判定）；地图数字原版配色去符号；章节标题三段时长、停留期任意键跳过（时长经 R7-TITLE 按汇编更正为 159＋320＋103 tick）；录屏待补 | `c196a71f` |
| R27 四个 sim 侧字段疑点（偷窃加成／解衰弱／武器状态字与随机异常／击杀金钱覆盖） | +0x196 偷窃字（重制此前比原版低 12 点）、249／251 解衰弱、完整 0x409310 状态字（含 R21 误记 dead 的三位）、EVEF 实例金钱；审计疑点清零、unconsumed 28→22；三条读法反编译级 provisional（替换＝有界原生探针） | `62bd0485` |
| R29 死亡台词＋逐实例称号（obj_Data8／Data5） | 安装字→单位 title／display_name／dead_message；三写者顺序 static-derived；34 关村民说 373、24／44 关 023／024 静默、17 关工人稱號 搬運工人；审计疑点 7→5、unconsumed 34→32 | `50ba984b` |
| R30 普攻／施法姿态按 ANIMAL 程序（aniSetShape） | 更正：普攻姿态早已由 `compile_action` 绑定（审计误归因，checker 改按通道取消费点，独立测试 228 检查证明帧序＝源程序）；新增 `AnimalCastLead`：绝技切入先按施法者 s_action 引导（氣刃斬 139 tick，构图与原录像一致）；m_action（魔法）引导待导入 18 条 m_shape；unconsumed 32→28、疑点 5→4；受击停留 15／77／20 tick 仍 provisional | `6a39818b` |
| P2 移动／攻击格画法照原版＋悬停身份栏（用户提出） | 范围格＝填充 ((bg+0x295a)>>1)＋I_rect 边框、17 tick 脉动（EXE 色表＋Wine 采样核对）；移动选择态悬停显示 WINDOW10 身份栏，未知敌人 ??／??? 遮罩，`known_unit_ids` loop 状态（被选为目标或死亡即已知；AI 打你不揭示，negative-evidence）随存档 v3；待办 P3：攻击目标预览／WINDOW20 状态页遮罩 | `f31de979` |
| R31 脚本写者接单位字（actSetDeadMessage／actSetPlayerName）＋魔法 m_action 引导素材＋`hsl generate '*'` 环 | STORY 层装配时写、WINFAIL 层运行时写单位 dead_message（29 关 023 1684／1686、6 关 隊長 969、全体队员有脚本台词）；actSetPlayerName 2 处（STORY029 梅爾／凱文）；69 张 m_shape 导入、魔法切入按 m_action 引导；两个生成环解开、`hsl generate '*'` 可排序 1395 任务；unconsumed 22→18。负责人随后：败北结果页不再复述死亡台词 `cb5bf605`；队员台词的脸从名册脸表取 `e83621f8` | `bb0cee30` |
| R32 R27 三条反编译级读法的有界原生探针 | 0x409310 状态字 176 行、cure_weaken 97 应用、+0x196／转职／金之手 21＋5＋67 行原生回执；矩阵 95–97 行 static-derived＋native receipt；唯一差异：偷窃遍历遇首个空槽即停（已修，sweep 不变） | `ee3a0c21` |
| S8 PlayLoop 拆分 | 2519→1116 行、preload 51→31，六个静态模块 BattleLoop{Init,Rewards,Script,AI,Combat,Inventory}；tests／91 调用文件零改动；规则套件 checks 逐套件相同、sweep 逐字节不变；未达 ≤900（剩余为玩家流程合同） | `9daf8886` |
| P3 身份栏遮罩补全＋切入受击停留读法 | ??／??? 遮罩铺满：目标预览、状态页、切入身份栏（唯一 `BattleVitals.mask`）；no_attack 位／>99 分支；受击停留 0x4038a0 static-derived（TARGET_PAUSE 32、HURT_HOLD 命中 68＋10×位数／未命中 56）；phase 100 开场 56 tick 无放声（记录）；剩余 provisional：RECOVERY 20、未知单位 HP 条画法 | `e9434ad4` |
| R33 53 关原版对照（存档链＋一次 Wine 采样） | 回憶錄 生成器支持非地图关入口（预设 level53_pre_battle）；Wine 15.5 min 读出 53 关开局全部单位：緹娜／出口守卫与重制逐字段同；**两条规则缺口**：脚本插入的两名 023 未继承 actSetPrevInsertObjectAdjustLevel,0,0（原版 L1／28 HP，重制 L2／L3）、阵营互换 023 的 hp_level 读模板 mode 多 1 HP——R28「等级 2 数值节拍」是在被抬级守卫下得出的 | `fc7f7481` |
| S6f 城镇内容外移＋sim→scene 反依赖归位 | 兩棲族部落 转职后 9 条 te 写入→`content/world/town_job_up_writes.json`＋`hsl check town_job_up_writes`（钉 TOWNDEF 与 R11 原生存档）；PartyEquipmentRules 由调用方注入 loop，`game/sim` 零 scene preload；待办：original_save.py 改读 JSON | `a9d4d1e2` |
| R34 修两条 53 关缺口＋重定性机器人 | `script_insert.adjust_level` 令牌进 unit（三个 023 全 L1 28/28）；`JobStatsRules.base_values(…, side_mask)` hp_level 取安装侧；53 关前瞻指挥官 22 回合逃出，章节 53→1→2 胜、停第 3 关（緹娜 L2 四击）；附带：分队交接前结清战利品（测试侧）、月花圓舞 镜头补 known 图（P3 缺口）；产品发现：分队结果页在战利品未结清时不给 下一戰 也不解释 | `5acf601f` |
| P4 切入开场／收尾读法＋身份栏尾巴 | 普攻开场 24＋32 tick（BALL001 缩放＋叠层）、收尾 16＋16 tick 取代猜的 RECOVERY 20；未知单位受伤 HP 条仍 negative-evidence；runtime 发现 known 按模板行（交 U1） | `b18d7d59` |
| X1 explorer 覆盖全部剧情 | 22/22 剧情场景、3/3 结局走到 GameClear，缺一即失败；顺带修掉「结局后直接片尾被读成卡住却仍 PASS」的静默漏洞 | `6af58587` |
| M2 第 53 关原版对照 | 出口守卫、追兵、增援的模板／出场格／时机／等级／AI 参数与前三回合行动逐项同原版——**机器人缺口**：气力不够放 月花圓舞、从不施放治疗、进苏醒范围才喝药；+10% 属性即 5/5 胜 | `3485fca1` |
| B3 章节走查可复现＋指挥官 5／6 关 | 走查播种全局 RNG（遭遇骰、城镇事件）、默认 3 次尝试，同树多跑 chapter.json 逐字节同；指挥官认胜利目标、保持队形、先行动者给药、补给先于装备、逃跑不判僵局；**第 5／6 关未过**：播种走查停在 5（8 名增援磨光余部、中毒主角），6 关单关探针 1/6 | `81ea543a` |
| 人工验收包 | `tools/playtest.sh N` 用独立存档从标题「戰場記錄」直进 8 个验收格（53／6／6 关前大地图／5／51／3／52／2），[PLAYTEST](PLAYTEST.md) 列看什么与回报格式 | `2332d742` |
| S14 规则侧敌军回合提速 | 一次敌军回合 ×0.31–0.46、sweep 947→450 s、章节 132→67 s（深门 1458→914 s），sweep／章节结果逐字节不变 | `c6634195` |
| R36 事件按原版节拍检查 | 每个行动完成后、推进队列前检查胜负／事件：回合 N 事件晚一个行动（第一个单位行动后），待机／用药后也重读；128 场中 13 场触发时刻移动、结局只 10 关一行变 | `e0cffc24` |
| P7 功能绝技结果文字 | 金之手／銀之手／天鳴覺醒／獅子吼 等不再显示「0」：落地只显示名字、未落地「閃避」、偷金飘「$」（原版 0x404643 按本次 EXP 判定） | `a9806ac6` |
| J1 转职素材 | 8 个角色的绝技切入条带自原版导入（056 原版无）；052 守护者音效；组装器 cast_gaps 守卫 | `9d1ffe81` |
| K1 技能侧边界 | 四条核实：两条早已关闭、增益绝技切入不再显示「0」、SP08 保持 negative-evidence | `f1c215b2` |
| B2／B2b 指挥官解毒 | 解毒计划、毒发进风险与估值、先治英雄、营救计划；52 关（R35 新格）34 回合无人阵亡胜；章节卡点 52→53（緹娜 逃跑被夹杀，等 R36） | `e1c15d91` |
| C1 共享素材搬出 chapter01 | 七组引擎直读素材 → shared/、经 ContentPaths；game/ 代码里 chapter01 字面量 0（剩 38 处是 provenance 证据引用），`engine:chapter_paths` 防回退 | `baa7b68e` |
| R35 52／53 关增援走通用路径 | 删 S11 专用增援键、winfail 镜像、四处钉格与死表现分支（−1570 行）；52 关后排 021 用原版整除落格——章节机器人因此在 52 关败（指挥官缺口，转 B2b） | `0176cfa3` |
| P6 起手节拍按原版 | 玩家普攻确认即出手；AI 引导用原版 tick（施放 24／普攻 6＋滑动＋停留，滑动按距离减速）；技能名字幕固定屏幕位置、只在 AI 引导期显示 | `135645ec` |
| S13 前瞻指挥官提速 | 章节走查 587.6→317.9 s（×0.54）、决策逐条不变（两种子章节 chapter.json 逐字节同）；移动包络复用、威胁图按需、模拟 AI 回合重放 | `11ca4234` |
| P5 施放期间的地图叠加层 | 静态读出原版确认后不画射程／光标／身份栏；玩家施放确认当帧进效果（去掉 0.7 s 引导）；A2 截图的红格是截图脚本造成 | `34b74f9a` |
| T3 七条 Agent 工具摩擦 | 种子传给机器人骰子、新关一条命令首建、章节单跑默认 600 s、规则套件可直接 --script、未导入素材提示、registry 家族具名失败、promote-timings --missing | `fb478743` |
| W1 outcome 结构化＋文案统一繁体 | `BattleOutcome` {result, reason} 取代拼接字符串，全部读者改读字段、存档 v4 拒 v3；玩家可见字串全繁体＋`content:player_copy_traditional`（1236 字差异表）；决策项：弃卒→棄卒、v3 不迁移 | `0f1158ba` |
| M1 第 5 关原版对照 | 两趟 Wine（12.5＋6.6 min）：开局逐字段同原版，**无规则缺口**；败因＝机器人不用 解毒草、风险不计毒伤（+10% 属性即胜）；直接进战斗关的 回憶錄 入口不装敌军（negative-evidence）；`hsl_original_control.py place` 救回断开显示器上的窗口 | `24f8b906` |
| A1 作者素材／切入／标题入口只写数据 | 切入表由场景 resources 给、作者关生成；`content/authored/actors/<外观>/` PNG 约定→与导入同形的行；開始新故事 按 campaign start_level、片头为 start_movie；新修 #20 身份栏崩溃（actor_panels 生成表）；零代码第二角色 103；与 A2 的集成缺口（作者职业称号）以 name_text 补 | `3a4a9f5d` |
| E1 机制矩阵 provisional 行 | 8→3（静态读 EXE，无 Wine）；未知单位 HP／MP 条照画真实比例（关闭 P4 ②）；不死单位 1 HP 复活；决策项：事件求值节拍晚一个动作（排 R36） | `f9b4a978` |
| A2 全新绝技＋职业 ≥101 只写数据 | `skills.json` 授权招式表（字段同 SPECIAL／MAGIC＋effCode 已有 opcode）→skill book／targeting／效果脚本；职业行自带 symbol 不改 TYPE.H；龍炎斬／龍息，第二招零代码；唯一运行时改动 SkillEffectScriptPlayer 读作者表；仅伤害类效果（治疗／状态／新 opcode 为代码决策） | `c8330075` |
| B1 指挥官必活集合 | `must_survive_ids` 从失败条件推出全部必活单位（多人、非硬编码）；章节 stuck_at 3→5（停 呼嘯平原）；lane 死于 401，负责人恢复提交、补 suite_timings、代写报告 | `33581551` |
| S12 AI 回合准备提速 | 四种常数级浪费（阻挡者回执重扫、目标行成长重算、包络重复、洪泛重建表）；一回合 ×0.30、前瞻决策 ×0.48；合并树深门 1256→607 s、sweep 851→414 s；行为逐字节不变 | `875da6a5` |
| T2 工具层三件小账 | 存档生成器读 `town_job_up_writes.json`；hsltools 反向 import 归零（6 个库体进包，4 个脚本变薄 CLI，34→33）；新检查 `docs:tool_references`（1238 路径／388 任务名有人查，修 4 处失效） | `73891d86` |
| S11 52／53 并入通用组装器 | `battle_052／053.json` 由 `level_battle:N` 从 `levels/052／053.json` 组装；scenario.py 1026→194；专用行为全部成数据（unit_ids／reinforcements／story_actors／excluded_source_actors）；sweep 与章节结果逐字节相同；决策清单：52／53 援军改 script_actor_templates、52 后排四格 021 采用原读法 | `04670eb6` |
| U1 分队结果页战利品哑门＋known 按模板 | 分队胜利且池非空：提示行＋「先處理戰利品」开面板，空了才出「下一戰」；顺带修好从来点不到的「查看待領物品」（结果遮罩吞点击，按钮升到 layer-3）；`unit_known` 同 actor_id 任一已知即已知（P4 runtime 证据） | `c1ccbd78` |
| S10 units 复制成本量化 | 负结果：units 占状态字节 95% 但整库复制只占一回合 2–4%，80–95% 在 `BattleLoopAI._prepare_ai_turn`（整图路由／目标行／动作候选）；不做 COW，反例与所有权合同进 BATTLE_CONFIG_STATE；`measure_loop_copy.gd` 扩 4 行 | `db8d03f7` |
| S9 改名 first_scene→battle/scene、FirstScene*／FirstBattle*→Battle* | 679 文件等量替换、50 uid 随 git mv；规则套件逐批 checks=113826 相同、sweep 不变；保留 13 个 `hsl_first_scene_*` schema id（数据合同）；未做 chapter01→shared/、game/ui/（非纯机械）与 outcome 结构化／繁体统一 | `920a5936` |
| T1 tools 垫片归零 | 前提过时：34 个 hsl_*.py 均为真实工具（152 壳此前已删）；拆 4 个再导出缝、45 处调用方改指 hsltools、README 34 行工具表；待办：文档代码块工具路径守卫、8 个被 hsltools import 的真实脚本迁入 | `7ef449d5` |

夜间保守选择（供早上审）：S2 (a)(b)(c)、S3 名册脸表作全局表、battle.schema 的 level／battle_seed 未 required——均已接受并记入合并说明。

夜间（2026-09-22 01:30–09:45）另收口：R22 `d562b6cb`、R24 `d50dd40f`、R25 `2f0ccba5`、H1 `660194b5`、R26 `93f403f4`（R 线回执见 [PLAYABILITY §7.1](PLAYABILITY.md#71-收口回执2026-09-21)）。模型服务两波故障（08:40 起 Request timed out ×5、09:00 起 Overloaded ×2）击落全部在飞 lane：有提交的工作树完整并已复活（S5／R23／R26），R27 两次失去未提交工作（第 4 项由 dangling commit 抢救为 `lane-r27-partial`），第三次派出改为"第一步先提交"。**待用户拍板**（均不阻塞）：① 重制时序目标 16 ms（原版设计）已按此执行，若偏好本机手感 19.4 ms 只改 `OriginalTick` 一处；② 切入回放 `PLAYBACK_SPEED` 0.4→1.0（普攻切入 ~4.6 s→~1.9 s）；③ 具名 NPC 怪物名册显示名（064 克里夫→商人、053 克羅蒂→四魔將，`hsltools/assets/portraits.py` 一行）；④ 回复数字用原色还是「+／−」；⑤ 「再次行動」提示（ExtraActionCue）删否；⑥ 章节标题是否加跳过输入以恢复原版 320 tick 停留。

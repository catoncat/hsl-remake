# HSL Remake Agent Guide

## Mission

本项目在 Godot 4.x 中重制《幻世录》第一章第一战。原版资源、脚本、EXE 静态分析和本机 runtime 观测用于恢复规则；目标是自己的可维护游戏工程，不是自动操纵原作，也不是把截图或 readback 当产品。

交付范围与验收以 `docs/FIRST_BATTLE_ACCEPTANCE.md` 为准。用户允许重制版改善交互、规则与配乐；原版等价声明仍须逐项证据支持。

## 效率硬规则

用户 2026-09-25／26 多次强制要求（"以后我们干活都要记步骤时间""非必要不测试，非必要不搞门禁和占时间的活"），与下文冲突时以本节为准。

- **记步骤时间**：开工记 `date`，每步（探路／实现／调试／验证／提交）记起止；lane 报告 ⑤ 写每步分钟、总墙钟、工具调用次数和最花时间的一步为什么；负责人把它连同派出／交回时刻、门禁模式与秒数记进 [`docs/LANE_TIMELOG.md`](docs/LANE_TIMELOG.md) 一行，每轮收口据此砍固定开销。
- **非必要不测试**：只按下文「测试政策」的两种情形写测试；验收只做任务书写明的 oracle——不自加负例、一次性探针、场景冒烟、手跑单测、逐字节复现证明、顺手的文档段落；不截图，除非是视觉改动。
- **非必要不门禁**：lane 收尾只跑一次 `tools/lane_verify.sh affected <基线>`（前台跑、timeout 给够，不 sleep 轮询）；不跑没命中的套件，不重生成没变的生成物；完整门禁只由负责人在合并树跑，几条 lane 一起交回只跑一次，由 `tools/lane_merge.sh gate` AUTO 按改动范围选。
- **任务书写准再派**：负责人写明入口文件／函数、可照抄的先例和时间预算（小改 20／单条规则 45／含裁判实验 60 分钟，到点先交报告），不写与本文件冲突的要求（09-26 MUSIC-IMPORT 任务书要求提交 `.import`，与仓库规则冲突，lane 为此多探路；62 分钟墙钟里命令只占 10 分钟）。
- **少轮次**：能合并的读、查、跑合成一条命令——时间主要花在一问一答的轮次上，不在命令本身。

## Cold start

所有任务先读：

1. `AGENTS.md`
2. `docs/PROJECT.md`

收口冲刺期间（见 [`docs/CONSOLIDATION.md`](docs/CONSOLIDATION.md) 状态）第三步读它：功能 lane 冻结，阶段、oracle 与 lane 协议以它为准。用户授权的现有双对话协作期间，接着读取根目录 [`PARALLEL_WORK.md`](PARALLEL_WORK.md)，按它定位各线最新 CLAIM／收口；旧留言只在需要核对消息编号时读取。未知 Git 改动先确认负责范围；这项明确授权仅覆盖已登记的两条工作线。

按任务补读：

| 本次任务 | 增量阅读 |
| --- | --- |
| 改 `game/`、scene 或 tests | [架构入口](docs/ARCHITECTURE.md)，再只读命中的 [战斗系统](docs/architecture/BATTLE_SYSTEMS.md)／[表现合同](docs/architecture/PRESENTATION.md) 章节 |
| 选定向测试、排查验证 | [测试路由](tests/README.md)、[工具入口](tools/README.md) |
| 资源、静态分析或原作对照 | [知识索引](docs/KNOWLEDGE_INDEX.md) 定位对应 packet；[CONTEXT](CONTEXT.md) 核对证据用语 |
| 改机制状态或等价声明 | [机制矩阵](docs/MECHANICS_EVIDENCE_MATRIX.md) 及对应证据 |
| 加关卡、改剧情流转、换配乐、加脚本 opcode 表现 | [扩展指南](docs/EXTENDING.md)（内容位置、生成链、运行时入口、验证步骤）＋[战役总览](docs/evidence_packets/resource_inventory/campaign_overview.md) |
| 派出或承接一条 lane | [Lane 任务书模板](docs/templates/lane_brief.md)＋[收口冲刺 §5](docs/CONSOLIDATION.md#5-工作协议冲刺期间) |
| 开新机制找原函数、筛长文档、自检证据用语 | [TypeSafe Jev 用法](docs/external/typesafe/README.md)：冷启动路由 `jevgrep rank`、证据用语 lint `jevgrep lint --rules tools/typesafe/evidence_lint_rules.json --diff HEAD`、全 EXE 函数候选目录 `PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query`；模型判断只是路由候选，不是证据 |

视觉／交互对照再读 `docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md`，按主题看原帧，代码入口查 ARCHITECTURE 的任务路由。外部模型解释是待审查线索；用 manifest 的源帧号定位，勿把导出编号、单次录像或压缩像素升级为全局规则。参考图存在不等于游戏已修复。

历史计划、一次性接力文档和对话快照已从活跃仓库删除；需要考古时使用仓库外的清理前 Git bundle，不要在 main 恢复成任务入口。

## 执行方式

用户要求继续开发或修复时，从 `docs/PROJECT.md` 的当前缺口选取本次范围内可验证的结果，实际实现并验证，不停在调查、计划或待办。常规可逆选择自行解决；原版语义未知时先查对应证据，仍未知就标明 provisional，不为推进而编造等价性。只对影响目标的不可查明歧义或未授权动作提问。保留本仓默认单线程及原作对照边界。

开始一块工作时明确玩家结果、负责文件和验收条件，搜索实际定义及调用者后实施；先跑命中的定向检查，完成后再跑完整门禁。已提交且验证成立的部分直接复用；下一项的来源字段或工具完成不能代替玩家功能完成。中断接续先核对 Git 和最后验证结果，再推进尚未完成的边界。

文档按职责更新：[PROJECT](docs/PROJECT.md) 只保留当前能力、边界与唯一 Next steps；架构存现行合同；evidence packet 存来源和具体回执；协作留言只存认领、请求与收口。新 slice 更新对应段落，不向入口末尾追加历史日报，也不新增另一份 TODO／STATUS／HANDOFF。结构或代码路径变化同步修复链接，避免新 Agent 依靠已过期的文件名和行号。

## Current truth

正式入口：

```text
project.godot
→ game/title/TitleScreen.tscn（原版標題畫面：開始新故事／戰場記錄／離開遊戲）
→ game/battle/scene/BattleSceneRuntime.tscn
→ BattleSceneRuntime.gd
→ BattlePlayLoop.gd
```

当前场景配置：`content/battles/campaign.json`（`start_level "51"` → `battle_051.json`，由 `level_battle:51` 生成；`BattleSceneRuntime.tscn` 仍可直接启动，默认加载同一文件，测试与开发路线不经标题）。`first_battle.json` 是旧的手工场景，仅供测试夹具与证据引用。

`BattlePlayLoop` 是唯一可变战斗状态所有者。Scene、`_unit_grid_coords` 和 `ActorRuntime` 只是输入/表现镜像。禁止新增第二套 battle dictionary、bootstrap snapshot 或 UI-owned combat truth。

玩家菜单以 `BattlePlayLoop.IMPLEMENTED_COMMANDS` 为准；新增命令时同时接通玩家交互与验证。未实现命令保持隐藏，直接调用返回 `not_implemented`。

## Repository boundaries

当前开发输入：

- `game/`
- `content/battles/`
- `content/imported/`
- `content/generated/`
- `tests/`
- `tools/`
- `docs/evidence_packets/`
- 当前状态与证据文档

原作本体位于仓库外，路径由 `HSL_ORIGINAL_DIR` 指定（维护者本机即 Wine 前缀里的 `$WINEPREFIX/drive_c/hsl`）。用户所购 Steam 經典版（1.06，含原曲 `music\NN.wav` 和第二套数据包）也在仓库外：`~/hsl-steam/fancy-realm/GAME-PAK`（`HSL_STEAM_CLASSIC`）。取得和核对用 `tools/hsl_steam_classic.py`，内容见[证据包](docs/evidence_packets/resource_inventory/steam_classic_edition.md)。复刻数据仍以本机原作为准，它等于 Steam 的 `hsl-cn.pak`。不要用 Steam 文件覆盖原作目录；Steam 登录只由用户本人操作。

以下内容不得成为 tracked 产品依赖：

- `.godot/`、`*.import`
- `ignored/`
- `asset-dumps/`
- `legal-assets/`
- `.pytest_cache/`、编译二进制、raw trace、长反汇编和未整理截图

Godot 的 `*.gd.uid` 不是 import cache：当前 `game/`、`tests/` 中每个 live GDScript 都必须保留一一对应的 UID 文件；删除脚本时同步删除 orphan UID。

Raw 发现只有压缩成可复跑工具输出、imported/generated data 或 curated evidence packet 后，才能成为开发输入。

## Evidence language

新结论使用：

- `resource-derived`
- `static-derived`
- `runtime-measured`
- `user-confirmed`
- `user-hypothesis`
- `provisional`
- `negative-evidence`

规则：

1. 文件名、临时批次编号、截图名、临时反编译符号不是语义。
2. 用户确认不能伪装成 static/runtime evidence。
3. 测试绿只证明当前合同，不证明原版等价。
4. provisional 必须写替换证据和不支持的结论。
5. Camera、projection、脚点、Move overlay、hit-test、z-order 和菜单 anchor 作为一个空间合同处理。
6. 每个 `game/**/*.gd` 模块文件头的 `## provenance:` 块按 rules／layout／strings／timing／audio 五维度用上述词汇（另加 `runtime-reference`、`remake-invented`）声明来源，`hsl check provenance` 强制、汇总在 [docs/PROVENANCE.md](docs/PROVENANCE.md)，格式见 [ARCHITECTURE「Provenance headers」](docs/ARCHITECTURE.md#provenance-headers)。

## Code rules

- 规则与表现分离；`ActorRuntime` 不拥有 HP、阵营、回合或目标真相。
- 坐标只走 `viewport → logical → world → grid`。
- 当前 live 规则分在 `TacticalGridRules`、`CoreCombatRules`、`CoreTurnQueue`；不要重新建立聚合上帝规则文件。
- 关卡脚本（winfail／story）由 `WinfailCompiler`／`WinfailConditions`／`WinfailActions`／`WinfailScenarioRules` 四个静态模块解释，经验成长已进入 play loop；第一战没有专用规则模块（S5 已并入通用路径）。战斗内转职（`actPlayerJobUpProcess`）已接入，完整角色控制规则尚未。新增规则直接进入 play loop（六个 `BattleLoop*` 静态模块之一），不新增 readback 状态机。
- `BattleSceneRuntime.gd`（≈1,060 行）与 `BattlePlayLoop.gd`（≈1,100 行）已按模块拆分；新增功能进对应模块（Input／Menus／Stage／Overlays；BattleLoopInit／Rewards／Script／AI／Combat／Inventory），不回填门面。
- 不为测试创建玩家不可见的长期 surface。
- **测试政策（用户 2026-09-25 强制要求："不要写太多的测试了！除非非常有必要，不写就会很有问题的时候才写"）**：测试只在两种情形写——①钉的是原版量得的事实（static-derived／模拟器实测），且没有现成套件覆盖；②不写就会让门禁抓不到会伤玩家的回归。其余一律不写。重制自己随机流的产物（开场等级数组、某个种子下的流状态、动作计数）**不钉数值**，只断言不变量；不为"消融能变红"而加测试；不为机械小改加复述实现的测试；一条 lane 默认不新增测试文件，优先在现有套件里加一两个代表性用例。任务书验收只写玩家可见结果与原版对照结果行。
- 不保留“缺数据时悄悄用另一套规则”的 legacy fallback；必要输入缺失应明确失败。

## Verification

首次使用环境、环境发生变化或排查工具问题时运行 `tools/doctor.sh`，不为未变化环境在开工和收尾重复诊断。实现期间跑命中的定向测试；每次合并前与 lane 报告前跑快门 `tools/verify.sh`；阶段收口或波末按 `docs/PROJECT.md` 运行一次全门 `tools/verify.sh --full`，并跑一次深门 `tools/verify.sh --deep`（快门 ＋ 全程剧情 explorer ＋ 自动对局 sweep 等长测试），不因改动仅为文档而自行免除。同一 diff 与验证环境的通过证据可复用，仅新改动、失败或未解风险需要重跑。

纯文档/提示词改动还要检查内容、路径/链接和 `git diff --check`；不为此额外启动 GUI、Wine 或重复冷缓存导入，但保留完整非 GUI 门禁自己的检查。若修改可执行验证合同则额外核对对应脚本。不要为机械小改增加复述实现的测试。

`verify.sh` 仍是唯一完整非 GUI 门禁（快门默认约 4–6 分钟——2026-09-25 实测最短 239 s、中位约 360 s；旧"约 2 分钟"已过期、`--full` 另证冷克隆导入约 6 分钟；检查由 `tools/hsl.py` 注册表、套件由 `tools/verify_runner.py` 按仓库数据枚举并行运行），覆盖：

- Python unit tests 与全部 source／evidence／importer 检查（`hsl check --all`：每个 tracked 生成物与源、每个证据包与其校验器）
- Godot asset import（快门热缓存、全门冷缓存），以及全部 `tests/run_*.gd` 套件：规则套件在 `tests/run_all.gd` 进程内分片运行，场景套件各自独立进程，注册场景 sweep 分片，快钟套件走 `--fixed-fps 60`
- Shell/Swift 语法
- 当前 tracked/untracked JSON 解析
- 当前文档的显式本地链接、图片与标题锚点
- live GDScript 与 `.gd.uid` 一一对应
- `git diff HEAD --check`

玩家可见布局或动效变化还需要截图/录屏人工验收；自动测试不能替代。

## Original runtime work

Wine 仅用于 targeted validation。执行前：

1. 先确认现有 resource/static/curated evidence 无法回答。
2. 把问题压缩成一个可重复 route。
3. 运行 `tools/doctor.sh --original`。
4. 先验证所选入口：`python3 tools/hsl_original_control.py ACTION ... --dry-run`，或旧路线的 `tools/hsl_capture.sh --dry-run ROUTE`。
5. 优先 Wine 内部单步输入 + cnc-ddraw 游戏画面采样（见 `tools/README.md`）；旧 macOS 路线只截游戏窗口，多窗口必须显式传 window id。新入口遇到多原作进程/窗口直接拒绝，不猜测。
6. Raw 输出留在仓库外 archive 或 `ignored/`，只提升结论。

不得用长时间无监督 playthrough 占用用户鼠标键盘，也不得截整个桌面。

## Lane 协议

自收口冲刺（[docs/CONSOLIDATION.md](docs/CONSOLIDATION.md)）起，负责人对话把可并行、文件域不重叠的工作派给 lane——独立 git worktree 里的子代理。任务书与报告都用 [docs/templates/lane_brief.md](docs/templates/lane_brief.md)：负责人先量出事实、写死 oracle，lane 先打 tracer 再批量，每步一提交，报告前跑快门；负责人审 diff、合并、跑合并树门禁、删 worktree。lane 不改 `docs/PROJECT.md`、`docs/CONSOLIDATION.md`、`tools/verify.sh`，不动规则语义与测试断言；需人判断的事进决策清单不阻塞。lane 自 2026-09-25 起由 Claude Code 的 Agent／Workflow 子代理以 worktree 隔离运行（位于 `.claude/worktrees/`，此前由 pi-subagents 管理），是本节授权的例外，不算下文的"自行新增工作树"。

负责人节拍（2026-09-21 起累积的一手经验，接手的 Agent 照此运转）：

- 任务书写**目的、背景、约束、验收**，方法留给 lane；负责人的推荐单列「推荐做法（可换）」。派活时记下 lane 的预期最终提交号——lane 结束后其分支引用可能消失，提交仍可按哈希合并（`git branch -f lane-x <hash>`）。
- **实验用探针（≤5 场代表性战斗），回归用全量**；说"久"必须说已跑多久、预计多久、卡在哪一步。
- lane 模型与负责人同模型（2026-09-24 用户指定：`PH/claude-opus-5-5`、thinking high；旧 `posthog/claude-opus-5-5` 已 403 失效）；并行上限 3–4（2026-09-25 收紧：6 条同跑把 8 核打满，快门从 4 分钟拖到 22 分钟）；lane 与负责人门禁都设 `HSL_VERIFY_JOBS=3`（曾冲到 load 130）。
- 合并节拍（`tools/lane_merge.sh merge|gate|publish|cleanup` 已脚本化；几条 lane 同时交回就连续 merge、只跑一次 gate）：`--no-ff --no-commit` 合并 → 冲突只在生成物（`docs/PROVENANCE.md`、`KNOWLEDGE_INDEX.md`）时用合并树 `hsl generate` 重生成 → 合并树快门（sweep 结果或规则语义变了跑 `--deep`）→ 提交说明写 lane 做了什么、根因、oracle 行、合并树门禁行 → 删 worktree／分支 → 快进 `main` 与 `presentation-line`。合并已暂存时不要再做别的提交（会把它做成合并提交）。
- lane 回来先向用户汇报结论，再动手派下一条；lane 说"平衡打不过"这类结论，先问它是否具备一个合格玩家的全部手段（买装备、换装、加点、全队估值）再接受。
- **战斗命名口径（用户 2026-09-26 强制）**：对用户、任务书、合并说明、PROJECT.md 里提到任何一场战斗，一律写「玩家第 N 场 · 场景名（LEVEL0xx）」＋在做什么，文件号只放括号；对照表 [docs/BATTLE_NAMES.md](docs/BATTLE_NAMES.md)。lane 报告只写文件号的，负责人转述时换成玩家口径。
- 用户要看的不是编号是人话；需要用户拍板的事集中、带例子、带推荐，不阻塞。只问产品行为：派不派 lane、何时派、门禁怎么提速、清理哪些工作树这类流程选择负责人自己定，做完告知（用户 2026-09-24）。
- 结束进程只按自己记录的 PID，不用 `pkill`／`killall`／按名字匹配：macOS `pkill -f X -U 501` 把模式之后的 `-U`、`501` 当成额外模式，会 SIGTERM 命令行含 501 的一切进程——2026-09-24 一条 lane 因此误杀了另外两条 lane 的 runner。
- 用户实玩报的问题按**类**处理（用户 2026-09-23："不能只解决我发现的……应该当成共性问题"）：任务书里写根因线索、要求盘点全游戏同类实例、在共享层修、加覆盖全部实例的检查，报告写找到／修了／剩余。截图只是样本。
- **排序按复刻品质影响，不按清单可见度**（用户 2026-09-25）：影响输赢与走位的规则（AI、行动顺序、随机数、调级、伤害）先于演出，演出先于外观；按"每场都看得到"排会把字体和 AI 规则混在一起。
- **让原版程序当裁判**：能用 `tools/hsltools/native/` 直接执行原版代码拿输出的，就不要靠读代码或看录屏推（R7-SPELL 整批执行 effProc 录轨迹是范例）；模型做视觉比对又慢又不准，看着不对的地方交给用户实玩反馈再回原程序挖；截帧脚本自检屏幕矩形与新帧，窗口用 `--always-on-top`（被遮挡时 macOS 不渲染）。
- **效率节拍（用户 2026-09-25："我们一定要最高性价比地干活"；依据 09-25 审计：16 次门禁 202 分钟中 54% 花在失败门禁、4 次为结果文件逐字节过期、0 次拦到真规则错）**：写集按**函数／改动块**认领而不是按文件——别的 lane 正在改的文件，只要不碰同一函数、改动 ≤30 行就直接改，合并时解冲突（WRANGE 为 11 行多开了一整条 lane 是反例）；lane **只跑** `tools/lane_verify.sh affected <基线>`（命中的检查与套件），**不跑快门 `tools/verify.sh`**——合并树门禁是唯一权威，且 `tools/lane_merge.sh gate` 默认 AUTO：改动不碰规则／战斗数据／harness／verify 工具（OUTCOME_PATHS）就只跑 affected（1–3 分钟），碰了才跑含 128 场自动对局的快门（2026-09-26 一个 Tab 快捷键跑了两遍自动对局，用户震怒——界面改动永远不该为自动对局买单）；≤30 行、不碰规则的小改（快捷键、文案、脚本一行）负责人直接在合并树改，不派 lane（一条 lane 的固定开销：开树、导入、截图、门禁 ≈ 20–40 分钟）；全机 verify 并发上限 2、负责人优先；深门只在发布前对合并树跑一次，结果文件（results.json／chapter.json）只由负责人在阶段收口重生成一次；自动对局 regen-and-compare 只对胜负／死局／脚本错误判失败（计数漂移只打印，合并者顺手提交）；独立复核只给改随机流／存档格式等高风险 lane、1 名怀疑者（13 人 0 反证，有用发现每组只出自 1 人）、只核最要紧的一条断言；证据包只写原版事实，"重制现状"只放代码头 provenance 与差异清单条目（0x458c10 在 21 个 md 出现 56 处，每改规则要扫十几个包是税）；机器人整章进度只作信息不阻塞；每轮收口做一次效率审计（门禁失败原因与耗时、每条 lane 固定开销、测试与文档增长），砍掉自证性工作；时间账与非必要不测试／不门禁见顶部[效率硬规则](#效率硬规则)。用户的"和原版不一样"是线索不是规格：查清原版后照原版做（原版有 bug 除外），证据与其结论冲突时按证据并说明。
- **旧断言先查来源**（`git log -S`），被原版证据取代才改并列旧→新；不写死会随工作推进变化的数（条目数、探针数、模块数）。先提交、确认落地再启动门禁，门禁期间不动那棵树。

## Git discipline

- 开工检查 `git status`, `git branch`, `git worktree list`。
- 不用 destructive reset 处理未知改动。
- 2026-09-12 用户明确要求在现有 `main` 和主工作区直接工作，不自行新增分支、worktree 或额外 checkout；2026-09-18 用户另行授权 presentation 接续线使用独立工作树 `~/.pi-worktrees/hsl-presentation`（分支 `presentation-line`）并按 slice 合并回 main。两条授权对话按 `PARALLEL_WORK.md` 协作；其他 Agent 不得据此再增加工作树。
- 默认单线程，不自动新增子任务。每个独立、可验证的 slice 完成后，更新项目进度和协作记录并立即本地提交，不把已完成成果长期留在工作区。
- 结束前必须取回后台验证的最终结果，确认提交号及剩余改动；同步更新本对话计划，不能以“验证已启动”或过时的 IN_PROGRESS 作为交付。
- 不自动 push；用户明确要求后才推送。
- 提交前列出自动验证、人工验证和仍 unresolved 的边界。

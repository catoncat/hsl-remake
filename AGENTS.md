# HSL Remake Agent Guide

给代理（Claude Code、Codex 等）看的索引和工作手册，公开仓库也带着——别人的代理照它干活。给人看的贡献规则在 [CONTRIBUTING](CONTRIBUTING.md)。结构：**一、索引**（读什么、按什么顺序）→ **二、硬规则** → **三、工作流** → **四、参考**。与别处冲突时以「效率硬规则」为准，其次本文件。

写成代码样式、以 `docs/internal/` 或 `docs/audits/` 开头的路径是维护者的内部文档，只在私有仓库里有，公开导出不带；公开仓库里的代理跳过它们即可。

---

## 一、索引

### Mission

本项目在 Godot 4.x 中重制《幻世录》第一章。终点两个，按顺序：①第一章 127 场战斗像原版一样从标题玩到章末；②这套引擎能写续集——没有原版数据可导入时，关卡／角色／技能／剧情只靠写数据就能跑。原版资源、脚本、EXE 静态分析和原版运行实测用于恢复规则；目标是自己的可维护游戏工程，不是自动操纵原作，也不是把截图或 readback 当产品。

交付范围、当前缺口与下一步以 [docs/PROJECT.md](docs/PROJECT.md) 为准。默认一律照原版（界面选择全部照原版；选项系统默认原版预设）；讲得清的改良只做成「重製選項」里的选项（[OPTIONS](docs/OPTIONS.md)），门禁与裁判只跑原版档。原版等价声明须逐项证据支持。

### 冷启动

所有任务按顺序读：

1. `AGENTS.md`（本文件；「效率硬规则」必读）
2. [`docs/PROJECT.md`](docs/PROJECT.md)（唯一当前状态：现状、进度尺、1.0 的条件）
3. 承接 lane 时：负责人给的任务书；格式见 `docs/internal/lane_brief.md`

未知 Git 改动先确认归谁，不动别人的。历史用 Git 查（`git log -S`）；逐轮流水在 `docs/internal/ROUNDS.md`，更早的考古用仓库外的清理前 Git bundle；不要把历史文件恢复成任务入口。

### 按任务补读

| 本次任务 | 增量阅读 |
| --- | --- |
| 改 `game/`、scene 或 tests | [架构入口](docs/ARCHITECTURE.md)，再只读命中的 [战斗系统](docs/architecture/BATTLE_SYSTEMS.md)／[表现合同](docs/architecture/PRESENTATION.md) 章节 |
| 选定向测试、排查验证 | [测试路由](tests/README.md)、[工具入口](tools/README.md) |
| 资源、静态分析或原作对照 | [知识索引](docs/KNOWLEDGE_INDEX.md) 定位对应 packet；[METHOD](docs/METHOD.md#证据分级) 核对证据等级 |
| 改机制状态或等价声明 | [机制矩阵](docs/MECHANICS_EVIDENCE_MATRIX.md)、[差异清单](docs/evidence_packets/static_reverse/parity_gap_inventory.md) 及对应证据 |
| 改游戏：换素材、加关卡、改剧情流转、换配乐、加脚本 opcode 表现 | [MODDING](docs/MODDING.md)＋[加关卡与角色逐步表](docs/MODDING_LEVELS.md)（文件位置、生成命令、改代码入口、验证步骤）＋[战役总览](docs/evidence_packets/resource_inventory/campaign_overview.md) |
| 写外传、续集或新剧情 | [原作剧情简报](docs/ORIGINAL_STORY.md)（世界、人物、三个结局、原作留白）；逐句台词读 `docs/internal/ORIGINAL_SCRIPT.md`，不必再从导入件抽取 |
| 设计续集的人物、数值与关卡 | [原作人物名录](docs/ORIGINAL_CAST.md)、[规则数值手册](docs/NUMBERS.md)、[原作关卡](docs/ORIGINAL_LEVELS.md)、[战棋设计方法](docs/SRPG_DESIGN.md)（末节「落到我们的规则」是对到本作的结论），直接读，不重做调查 |
| 提到某一场战斗 | [战斗称呼对照](docs/BATTLE_NAMES.md)（见「命名口径」） |
| 派出或承接一条 lane | 下文「三、工作流」＋`docs/internal/lane_brief.md` |
| 开新机制找原函数、筛长文档、自检证据用语 | TypeSafe Jev 用法（完整文档是私有仓库的第三方镜像；要联网和 key；配方见[工具说明](tools/README.md#typesafe-判断分担与全-exe-函数目录)）：冷启动路由 `jevgrep rank`、证据用语 lint `jevgrep lint --rules tools/typesafe/evidence_lint_rules.json --diff HEAD`、全 EXE 函数候选目录 `PYTHONPATH=tools python3 -m hsltools.checks.function_catalog query`；模型判断只是路由候选，不是证据 |
| 全部文档怎么分工 | [文档地图](docs/README.md) |

视觉／交互对照再读 `docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md`，按主题看原帧，代码入口查 ARCHITECTURE 的任务路由。外部模型解释是待审查线索；用 manifest 的源帧号定位，勿把导出编号、单次录像或压缩像素升级为全局规则。参考图存在不等于游戏已修复。

### Current truth

正式入口：

```text
project.godot
→ game/title/TitleScreen.tscn（原版標題畫面：開始新故事／戰場記錄／離開遊戲）
→ game/battle/scene/BattleSceneRuntime.tscn
→ BattleSceneRuntime.gd
→ BattlePlayLoop.gd
```

当前场景配置：`content/battles/campaign.json`（`start_level "51"` → `battle_051.json`，由 `level_battle:51` 生成；`BattleSceneRuntime.tscn` 仍可直接启动，默认加载同一文件，测试与开发路线不经标题）。`first_battle.json` 是名册模板与测试夹具，不是现行场景。

机器可读的权威数据：`content/imported/hsl/` 是可复用的原版资源、脚本 IR 与 manifest；`content/generated/hsl/` 是可重现的生成事实；`content/authored/` 是手写数据（续集关卡与角色、选项注册表等）；原作视觉基准是 `docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json`；完整资源成员索引 `docs/evidence_packets/resource_inventory/resource_manifest.json` 供机器搜索，不要整文件读进上下文。

`BattlePlayLoop` 是唯一可变战斗状态所有者。Scene、`_unit_grid_coords` 和 `ActorRuntime` 只是输入/表现镜像。禁止新增第二套 battle dictionary、bootstrap snapshot 或 UI-owned combat truth。

玩家菜单以 `BattlePlayLoop.IMPLEMENTED_COMMANDS` 为准；新增命令时同时接通玩家交互与验证。未实现命令保持隐藏，直接调用返回 `not_implemented`。

---

## 二、硬规则

### 效率硬规则

干活记步骤时间；非必要不测试、不跑门禁、不做占时间的活；按最高性价比干活。与下文冲突时以本节为准。

- **记步骤时间**：开工记 `date`，每步（探路／实现／调试／验证／提交）记起止；lane 报告 ⑤ 写每步分钟、总墙钟、工具调用次数和最花时间的一步为什么；负责人把它连同派出／交回时刻、门禁模式与秒数记进时间账 `docs/internal/LANE_TIMELOG.md` 一行，每轮收口据此砍固定开销（见「时间账」）。
- **非必要不测试**：只按下文「测试政策」的两种情形写测试；验收只做任务书写明的 oracle——不自加负例、一次性探针、场景冒烟、手跑单测、逐字节复现证明、顺手的文档段落；不截图，除非是视觉改动（最多 3 张）。
- **非必要不门禁**：lane 收尾只跑一次 `tools/lane_verify.sh affected <基线>`（前台跑、timeout 给够，不 sleep 轮询），**不跑快门 `tools/verify.sh`**；不跑没命中的套件，不重生成没变的生成物；完整门禁只由负责人在合并树跑，几条 lane 一起交回只跑一次，由 `tools/lane_merge.sh gate` AUTO 按改动范围选档（见「门禁」）。
- **任务书写准再派**：负责人写明入口文件／函数、可照抄的先例和时间预算（小改 20／单条规则 45／含裁判实验 60 分钟，到点先交报告），不写与本文件冲突的条目（09-26 MUSIC-IMPORT 任务书写了提交 `.import`，与仓库规则冲突，lane 为此多探路；62 分钟墙钟里命令只占 10 分钟）。
- **少轮次**：能合并的读、查、跑合成一条命令——时间主要花在一问一答的轮次上，不在命令本身。
- **砍自证性工作**：每轮收口做一次效率审计（门禁失败原因与耗时、每条 lane 固定开销、测试与文档增长）。依据 09-25 审计：16 次门禁 202 分钟中 54% 花在失败门禁、4 次为结果文件逐字节过期、0 次拦到真规则错。

### 测试政策

测试非必要不写：只有不写就会出问题时才写。

- 测试只在两种情形写：①钉的是原版量得的事实（static-derived／模拟器实测），且没有现成套件覆盖；②不写就会让门禁抓不到会伤玩家的回归。其余一律不写。
- 重制自己随机流的产物（开场等级数组、某个种子下的流状态、动作计数）**不钉数值**，只断言不变量；不为"消融能变红"而加测试；不为机械小改加复述实现的测试。
- 一条 lane 默认不新增测试文件，优先在现有套件里加一两个代表性用例；删掉多余的测试。任务书验收只写玩家可见结果与原版对照结果行。
- 不为让测试过而改断言；测试绿只证明当前合同，不证明原版等价。

### 命名口径

- **战斗**：汇报、任务书、合并说明、PROJECT.md 里提到任何一场战斗，一律写「玩家第 N 场 · 场景名（LEVEL0xx）」＋在做什么，文件号只放括号；对照表 [docs/BATTLE_NAMES.md](docs/BATTLE_NAMES.md)。lane 报告只写文件号的，负责人转述时换成玩家口径。
- **对负责人汇报用玩家口径**：负责人要看的不是编号；需要拍板的事集中、带例子、带推荐，不阻塞。
- **不写死会随工作推进变化的数**（条目数、探针数、模块数、文件行数）；进度数字只写在 PROJECT「进度尺」并带日期与出处。

<a id="evidence-language"></a>

### 证据用语

新结论使用（唯一定义见 [METHOD](docs/METHOD.md#证据分级)；写结论的规矩见 [CONTEXT](CONTEXT.md#claim-rules)）：

- `resource-derived`
- `static-derived`
- `runtime-measured`
- `user-confirmed`
- `user-hypothesis`
- `provisional`
- `negative-evidence`

规则：

1. 文件名、临时批次编号、截图名、临时反编译符号不是语义。
2. 原版知情者确认（user-confirmed）不能伪装成 static/runtime evidence。
3. 测试绿只证明当前合同，不证明原版等价。
4. provisional 必须写替换证据和不支持的结论。
5. Camera、projection、脚点、Move overlay、hit-test、z-order 和菜单 anchor 作为一个空间合同处理。
6. 每个 `game/**/*.gd` 模块文件头的 `## provenance:` 块按 rules／layout／strings／timing／audio 五维度用上述词汇（另加 `runtime-reference`、`remake-invented`）声明来源，`hsl check provenance` 强制、汇总在 [docs/PROVENANCE.md](docs/PROVENANCE.md)，格式见 [ARCHITECTURE「Provenance headers」](docs/ARCHITECTURE.md#provenance-headers)。
7. 证据包只写原版事实；"重制现状"只放代码头 provenance 与差异清单条目（0x458c10 曾在 21 个 md 出现 56 处，每改规则要扫十几个包是税）。
8. **旧断言先查来源**（`git log -S`），被原版证据取代才改并列旧→新。

### 代码规则

- 规则与表现分离；`ActorRuntime` 不拥有 HP、阵营、回合或目标真相。
- 坐标只走 `viewport → logical → world → grid`。
- 当前 live 规则分在 `TacticalGridRules`、`CoreCombatRules`、`CoreTurnQueue`；不要重新建立聚合上帝规则文件。
- 关卡脚本（winfail／story）由 `WinfailCompiler`／`WinfailConditions`／`WinfailActions`／`WinfailScenarioRules` 四个静态模块解释，经验成长已进入 play loop；第一战没有专用规则模块。战斗内转职（`actPlayerJobUpProcess`）已接入，完整角色控制规则尚未。新增规则直接进入 play loop（六个 `BattleLoop*` 静态模块之一），不新增 readback 状态机。
- `BattleSceneRuntime.gd` 与 `BattlePlayLoop.gd` 已按模块拆分；新增功能进对应模块（Input／Menus／Stage／Overlays；BattleLoopInit／Rewards／Script／AI／Combat／Inventory），不回填门面。
- 不为测试创建玩家不可见的长期 surface。
- 不保留"缺数据时悄悄用另一套规则"的 legacy fallback；必要输入缺失应明确失败。

### 仓库边界

当前开发输入：`game/`、`content/battles/`、`content/imported/`、`content/generated/`、`content/authored/`、`tests/`、`tools/`、`docs/evidence_packets/`、当前状态与证据文档。

原作本体位于仓库外，路径由 `HSL_ORIGINAL_DIR` 指定（维护者本机即 Wine 前缀里的 `$WINEPREFIX/drive_c/hsl`）。用户所购 Steam 經典版（1.06，含原曲 `music\NN.wav` 和第二套数据包）也在仓库外（`HSL_STEAM_CLASSIC`）。取得和核对用 `tools/hsl_steam_classic.py`，内容见[证据包](docs/evidence_packets/resource_inventory/steam_classic_edition.md)。复刻数据仍以本机原作为准，它等于 Steam 的 `hsl-cn.pak`。

以下内容不得成为 tracked 产品依赖：

- `.godot/`、`*.import`
- `ignored/`
- `asset-dumps/`
- `legal-assets/`
- `.pytest_cache/`、编译二进制、raw trace、长反汇编和未整理截图

Godot 的 `*.gd.uid` 不是 import cache：当前 `game/`、`tests/` 中每个 live GDScript 都必须保留一一对应的 UID 文件；删除脚本时同步删除 orphan UID。

Raw 发现只有压缩成可复跑工具输出、imported/generated data 或 curated evidence packet 后，才能成为开发输入。原版截图、录像帧不进公开仓库（[CONTRIBUTING §5](CONTRIBUTING.md#5-不提交原版派生物)）。

### 安全底线

- 不用 destructive reset 处理未知改动；不改别人正在认领的函数／改动块。
- **边提交边 push**：每个可验证步骤单独提交，不等全部验证完；lane 每次提交后 `git push -u origin HEAD` 推自己的分支；合并树 publish 后由脚本自动推 main／presentation-line／pipeline-line，cleanup 顺手删远端 lane 分支。publish 推 main 后 `tools/oss_sync.sh` 自动把公开仓库 hsl-remake 同步到 main（导出→复扫→提交→推送），不再手动同步。
- 结束进程只按自己记录的 PID（`kill <pid>`），不用 `pkill`／`killall`／按名字匹配：macOS `pkill -f X -U 501` 把模式之后的 `-U`、`501` 当成额外模式，会 SIGTERM 命令行含 501 的一切进程——2026-09-24 一条 lane 因此误杀了另外两条 lane 的 runner。
- 不要用 Steam 文件覆盖原作目录；Steam 登录只由用户本人操作。
- 不得用长时间无监督 playthrough 占用用户鼠标键盘，也不得截整个桌面。
- 不提交原版派生物、密钥、会话 id 和本机绝对路径（写成 `$HSL_ORIGINAL_DIR`、`$WINEPREFIX`、`~` 或 `ignored/`）。
- 仓库文件、任务书、提交说明不转述用户的话，也不写「用户说／拍板」这类说法，规则用中性说法写（`tools/hsl_docs_check.py` 会拦 Markdown 里的这类说法）。
- 提交标题和正文会被 `tools/oss_sync.sh` 原样抄进公开仓库，不写未公开内容的名字；名单在 `docs/internal/unreleased_names.txt`，导出和同步遇到名单里的名字就失败。

---

## 三、工作流

### 执行方式

接到继续开发或修复的任务时，从 `docs/PROJECT.md` 的排队项选取本次范围内可验证的结果，实际实现并验证，不停在调查、计划或待办。常规可逆选择自行解决；原版语义未知时先查对应证据，仍未知就标明 provisional，不为推进而编造等价性。只对影响目标的不可查明歧义或未授权动作提问。

开始一块工作时明确玩家结果、负责文件和验收条件，搜索实际定义及调用者后实施；先跑命中的定向检查。已提交且验证成立的部分直接复用；下一项的来源字段或工具完成不能代替玩家功能完成。中断接续先核对 Git 和最后验证结果，再推进尚未完成的边界。

- **排序按复刻品质影响，不按清单可见度**：影响输赢与走位的规则（AI、行动顺序、随机数、调级、伤害）先于演出，演出先于外观。
- **让原版程序当裁判**：能用 `tools/hsltools/native/` 直接执行原版代码拿输出的，就不要靠读代码或看录屏推（R7-SPELL 整批执行 effProc 录轨迹是范例）；模型做视觉比对又慢又不准，看着不对的地方交给实玩反馈再回原程序挖；截帧脚本自检屏幕矩形与新帧，窗口用 `--always-on-top`（被遮挡时 macOS 不渲染）。
- 用户的"和原版不一样"是线索不是规格：查清原版后照原版做（原版有 bug 除外），证据与其结论冲突时按证据并说明。
- 实玩报的问题按**类**处理（当成共性问题，不只解决报出的那一处）：写根因线索、盘点全游戏同类实例、在共享层修、加覆盖全部实例的检查，报告写找到／修了／剩余。截图只是样本。
- **实验用探针（≤5 场代表性战斗），回归用全量**；说"久"必须说已跑多久、预计多久、卡在哪一步。

文档按用途分事实、做法、记录三类，事实和做法只写现在（[CONTEXT「文档怎么写」](CONTEXT.md#文档怎么写)）。文档按职责更新：[PROJECT](docs/PROJECT.md) 只保留一屏当前状态（现状、进度尺、1.0 的条件、文档地图），不追加历史日报，也不新增另一份 TODO／STATUS／HANDOFF；每轮收口的流水进 `docs/internal/ROUNDS.md`；架构存现行合同；evidence packet 存来源和具体回执。结构或代码路径变化同步修复链接。公开文档（`docs/internal/`、`docs/audits/` 之外）不得链接内部文档，`tools/hsl_docs_check.py` 会拦；需要提到时写成代码样式的路径。内部状态（未公开内容的入口和阶段）写进 PROJECT 的内部段：单独成行的 `<!-- internal -->` 与 `<!-- /internal -->` 之间，公开导出时整段去掉。

### Lane 协议

负责人对话（Claude Code 会话）把可并行、写集不重叠的工作派给 lane——Claude Code 的 Agent／Workflow 子代理，以 worktree 隔离运行（位于 `.claude/worktrees/`，自 2026-09-25 起；此前由 pi-subagents 管理）。任务书与报告都用 `docs/internal/lane_brief.md`：负责人先量出事实、写死 oracle，lane 先打 tracer 再批量，每步一提交；负责人审 diff、合并、跑合并树门禁、删 worktree。

lane 这一侧：

- 基线从 `pipeline-line` 快进（`git merge --ff-only pipeline-line`）；每个可验证步骤单独提交（中文说明写清做了什么与 oracle 结果行），验证过就提交，不留给负责人。
- 不改 `docs/PROJECT.md`、`tools/verify.sh`（任务书明确要求的除外），不动规则语义与测试断言；需人判断的取舍选最保守的一种继续，列进报告，不停下等。
- 收尾只跑 `tools/lane_verify.sh affected <基线>`，报告贴结果行；不跑快门。
- lane 自己不再派 lane。时间预算到了先交报告（做完的部分＋剩余清单）。
- 报告：①提交号 ②交付物与用法 ③结果行原样 ④边界／剩余 ⑤时间账。

负责人这一侧：

- 任务书写**目的、背景、约束、验收**，方法留给 lane；负责人的推荐单列「推荐做法（可换）」。派活时记下 lane 的预期最终提交号——lane 结束后其分支引用可能消失，提交仍可按哈希合并（`git branch -f lane-x <hash>`）。
- **写集按函数／改动块认领而不是按文件**：别的 lane 正在改的文件，只要不碰同一函数、改动 ≤30 行就直接改，合并时解冲突（WRANGE 为 11 行多开了一整条 lane 是反例）。
- **≤30 行、不碰规则的小改**（快捷键、文案、脚本一行）负责人直接在合并树改，不派 lane（一条 lane 的固定开销：开树、导入、截图、门禁 ≈ 20–40 分钟）。
- lane 模型与负责人同模型、thinking high；并行上限 3–4（2026-09-25：6 条同跑把 8 核打满，快门从 4 分钟拖到 22 分钟）；lane 与负责人门禁都设 `HSL_VERIFY_JOBS=3`（曾冲到 load 130）；全机 verify 并发上限 2、负责人优先；lane 的验证与 headless Godot 以 nice 10 运行（`tools/lane_verify.sh`、`tools/godot.sh` 在 `HSL_VERIFY_PRIORITY` 不为 1 时自动降级），负责人门禁保持默认优先级（2026-09-29：一次快门与 lane 验证争 CPU 跑了 1211 s，空闲时 184–338 s）。
- lane 回来先向用户汇报结论，再派下一条；lane 说"平衡打不过"这类结论，先问它是否具备一个合格玩家的全部手段（买装备、换装、加点、全队估值）再接受。
- 只问产品行为：派不派 lane、何时派、门禁怎么提速、清理哪些工作树这类流程选择负责人自己定，做完告知。
- 机器人整章进度只作信息不阻塞。先提交、确认落地再启动门禁，门禁期间不动那棵树。

### 性价比与流程

**排队**

- 价值＝玩家能否察觉 × 碰到的频率，从高到低：影响胜负或卡关的规则＞每场都见的演出＞部分关卡＞罕见。成本＝墙钟分钟，实现、审查、修复、合并、门禁都算；按时间账同类 lane 实测估（S 级约 15–35 分钟，M 级约 55–65 分钟，会改胜负的另加受影响关卡的对局时间）。
- 新项进队列前过三关：写出玩家在哪一关、哪个操作下能看到；给出原版地址或差异清单字段；估出成本。缺一条只记进差异清单，不派 lane。
- 只记清单、不派 lane：1 px 取整、1–3 tick 或相位、闪烁相位、LSB 级合成、字间距；visibility＝invisible，或只改抽签次数、行为分布不变的；要 Wine 实测或调度模型才能判定的；原版没有的重制新增；证据包内部矛盾和纯文档措辞。
- 同一块区域（同一面板、同一演出系统）的小项合成一条 lane。审查报出的、落在同一批文件里的玩家可见项由当条修复收，不另开后续 lane；文档余项走 docfix，不攒文档扫尾 lane。
- 能让整章走查或实玩推进的事（重跑走查、修卡关、修规则）排在外观项之前。机器人打不过某关先查规则（胜负条件、数值是否照原版）；规则照原版就记「机器人打不过」往下走，不开 lane 逐关调机器人。

**审查与修复**

- 每条 lane 交回后由两个视角各一名审查者设法驳倒：原版读法（重读引用的地址）与代码协议（逻辑、回归、别的技能或调用方是否被波及）。审查者先从报告里列不超过 5 条核心结论，只驳这些结论和 diff 的行为，工具调用约 35 次以内。
- 分三档：**blocker**（玩家可见的行为错、回归、破坏门禁或协议）、**docfix**（文档、证据层级、地址、标签写错事实）、**minor**（其余，1 tick／1 px／单帧／闪烁相位级差异一律 minor，只进差异清单）。
- 只有 blocker 才起修复；只有 docfix 时由负责人合并时改（改完重生成物）。修复只跑自己改到的定向套件，改到定向套件覆盖之外的 `game/*.gd` 才跑 `lane_verify`；只改文档就重生成物＋`hsl check docs`＋`git diff --check`，不跑 Godot。

**lane 里怎么跑命令**

- 直接跑 `tools/godot.sh` 与 `tools/lane_verify.sh`，不设 HOME、不 source 环境文件（`tools/godot.sh` 自己隔离 HOME）。
- 开窗口跑 `--script`（审看、试演、截图脚本）一律走 `tools/play.sh --script <脚本>`，它把 HOME 换到 `ignored/script-home`；`tools/godot.sh` 只给 `--headless` 隔离 HOME，开窗口直接跑的脚本会动到真实存档。
- 一次调用只放一条简单命令；git 一律 `git -C`；一次性的多行 Python 先写成 `ignored/*.py` 再运行。会再用的脚本、配方、提示词当场放进受管目录并提交（公开的放 `tools/`，只给维护者用的放 `docs/internal/`）；`ignored/` 只留截图、录像、日志、大批试作图和缓存。
- 验证只用 `tools/lane_verify.sh`，不自写脚本跑整套；收尾前台跑一次（Bash timeout 600000），不放后台轮询；中途用定向套件。

**自动对局与走查**

- lane 不跑全量 128 场自动对局、不提交 `results.json`。要看战果时用 `HSL_AUTOPLAY_LEVELS` 跑受影响的 2–5 关，结果写到 `ignored/`，报告列翻转场次。
- 全量 128 场由负责人每批合并后在后台重生成一次、单独提交，同一提交重算 `brain_comparison.json`（`autoplay_brain` 检查两者一致）。胜负翻转只报告并归因；死局、脚本错误、超时才判失败。
- 整章走查在独立的干净检出里跑（与合并树共用 `user://` 会互相干扰），只在夜里或阶段收口时跑。

**门禁与收口**

- 已交回的 lane 攒 2–3 条依次合并（每条单独提交），对 HEAD 跑一次 gate，过了一次发布，发布前在 `CHANGELOG.md` 当天日期下给每条 lane 补一行白话；门红时按失败套件与各 lane 的 diffstat 定位，revert 那一条再过门。
- 合并后在合并树手改过任何文件，提交前重跑受影响的 `hsl generate`（生成块不会自己更新）。
- 纯文档改动不评审，在合并树直接提交，走 docs 档。门禁、验证工具本身的小改攒成一个提交，只过一次快门。
- 时间账「合并树门禁」一列抄 `ignored/gate-history.tsv`（每次 gate 追加一行：档位、秒数、探索器秒数、开跑时 load）。

### 合并节拍

`tools/lane_merge.sh` 的 merge／gate／publish／cleanup 已脚本化，**一律用合并树（`pipeline-line` 工作树）里的那份**——别的工作树里的副本可能是旧脚本（09-26 OPTIONS-HOTKEY 就因旧脚本误跑了快门）。几条 lane 同时交回：连续 `merge`，只跑一次 `gate`，一次 `publish`。

1. `merge REF MSGFILE`：`--no-ff --no-commit` 合并进 `pipeline-line`。冲突只在生成物（PROVENANCE、KNOWLEDGE_INDEX、差异清单 md/json、原版派生物清单）时取 ours 后由合并树 `hsl generate` 重生成（PROVENANCE 与 KNOWLEDGE_INDEX 是手写正文夹一个生成块，冲突落在生成块外时停下手解，免得丢掉 lane 手写的行）——无冲突也总是重生成（两条 lane 各加证据包不冲突但生成块会过期）；差异清单人工归类 `parity_gap_inventory.curation.json` 的冲突由 `tools/merge_curation_json.py` 三方并集自动解（列表按 id 合并，ours 已删／改名的键保持删除）；其余冲突手解。提交说明写 lane 做了什么、根因、oracle 行。合并已暂存时不要再做别的提交（会把它做成合并提交）。
2. `gate`：见下节「门禁」。
3. `publish`：当前 HEAD 的门禁日志以 `VERIFY_PASS`／`LANE_AFFECTED_PASS`／`LANE_DOCS_PASS` 结尾、目标工作树没有会被覆盖的改动时，把 `main` 与 `presentation-line` 快进到 `pipeline-line`（没有工作树的目标直接快进分支引用），并推送 origin；`--dry-run` 只做检查。
4. `cleanup WORKTREE...`：删已合并的 lane 工作树与分支。

### 门禁

`tools/verify.sh` 是唯一完整非 GUI 门禁：快门（默认，空闲时约 3–6 分钟，2026-09-29 实测 184–338 s）、`--full` 全门（先删 `.godot` 与 `*.import` 证明冷克隆可导入，另约 6 分钟）、`--deep` 深门（快门＋全程剧情 explorer＋128 场自然胜负自动对局＋限时整章自动对局等长测试）。检查由 `tools/hsl.py` 注册表、套件由 `tools/verify_runner.py` 按仓库数据枚举并行运行，覆盖：

- Python unit tests 与全部 source／evidence／importer 检查（`hsl check --all`：每个 tracked 生成物与源、每个证据包与其校验器）
- Godot asset import（快门热缓存、全门冷缓存），以及全部 `tests/run_*.gd` 套件：规则套件在 `tests/run_all.gd` 进程内分片运行，场景套件各自独立进程，注册场景 sweep 分片，快钟套件走 `--fixed-fps 60`
- Shell/Swift 语法；当前 tracked/untracked JSON 解析
- 当前文档的显式本地链接、图片与标题锚点，公开文档不链接内部文档
- live GDScript 与 `.gd.uid` 一一对应；`git diff HEAD --check`

谁跑什么：

| 谁 | 跑什么 |
| --- | --- |
| lane（实现期间） | 命中的定向测试：`tools/godot.sh --headless --script res://tests/run_all.gd -- run_x_tests.gd`（规则套件）／`--script res://tests/run_x_tests.gd`（场景套件）／`python3 tools/hsl.py check <family>` |
| lane（收尾一次） | `tools/lane_verify.sh affected <基线>`（命中的注册表检查、Python 测试与 Godot 套件）；只改文档时 `python3 tools/hsl.py check docs`＋`python3 tools/hsl_docs_check.py`＋`git diff --check` |
| 负责人（合并树） | `tools/lane_merge.sh gate`，默认 **AUTO 三档**：①自上一个过了门禁的提交以来只改了 `*.md` → **docs 档**（空白、链接、工具引用，秒级）；②改动不碰 OUTCOME_PATHS（规则、战斗数据、harness、verify 工具；资源导入工具 `tools/hsltools/assets/` 不算）→ **affected 档**（`lane_verify.sh affected main`，1–3 分钟；改了 `project.godot` 另跑两个预设的场景冒烟；affected 推迟了 Godot 套件时自动改跑快门）；③碰了 OUTCOME_PATHS → **快门**（含 128 场强制胜利 sweep，分 4 片；自然胜负的自动对局属深门）。改动落在剧情链上（affected 选中剧情探索器的同一判据）时，affected 档自带探索器，快门档通过后再跑一次探索器（`STORY_EXPLORER_GUARD` 行）。`--fast`／`--deep`／`--affected` 可强制。2026-09-26 一个 Tab 快捷键跑了两遍自动对局——界面改动永远不该为自动对局买单 |
| 负责人（发布前） | 深门只在发布前对合并树跑一次；`results.json` 每批合并后由负责人重生成一次，`chapter.json` 在阶段收口重生成 |

- 自动对局 regen-and-compare 只对胜负／死局／脚本错误判失败，计数漂移只打印；`results.json` 由负责人每批重生成（见「性价比与流程」），lane 不提交。
- 首次使用环境、环境变化或排查工具问题时运行 `tools/doctor.sh`，不为未变化环境在开工和收尾重复诊断。同一 diff 与验证环境的通过证据可复用，仅新改动、失败或未解风险需要重跑。
- 纯文档改动检查内容、路径/链接和 `git diff --check`；不为此启动 GUI、Wine 或冷缓存导入。改可执行验证合同时另核对对应脚本。
- 玩家可见布局或动效变化还需要截图/录屏人工验收；自动测试不能替代。

### 时间账

- lane：开工记 `date`，每步记起止（读证据／开树导入／写代码／定向验证／截图／文档），报告 ⑤ 写每步分钟数、总墙钟、工具调用次数与最花时间的一步为什么。
- 负责人：每条 lane 一行记进 `docs/internal/LANE_TIMELOG.md`（派出／交回时刻、步骤分钟、合并树门禁模式与秒数、备注）；每轮收口据此做效率审计，砍固定开销最大的一步。

### 原版运行观测

Wine 仅用于 targeted validation。执行前：

1. 先确认现有 resource/static/curated evidence 无法回答。
2. 把问题压缩成一个可重复 route。
3. 运行 `tools/doctor.sh --original`。
4. 先验证所选入口：`python3 tools/hsl_original_control.py ACTION ... --dry-run`，或旧路线的 `tools/hsl_capture.sh --dry-run ROUTE`。
5. 优先 Wine 内部单步输入 + cnc-ddraw 游戏画面采样（见 `tools/README.md`）；旧 macOS 路线只截游戏窗口，多窗口必须显式传 window id。新入口遇到多原作进程/窗口直接拒绝，不猜测。
6. Raw 输出留在仓库外 archive 或 `ignored/`，只提升结论。

### Git 纪律

- 开工检查 `git status`、`git branch`、`git worktree list`。
- 分支：`pipeline-line` 是合并树（负责人在它的工作树里合并与门禁）；`main` 与 `presentation-line` 只由 `lane_merge.sh publish` 快进；lane 在 `.claude/worktrees/` 的独立工作树里，基线从 `pipeline-line` 快进。其他代理不得自行新增分支、工作树或额外 checkout。
- 每个独立、可验证的 slice 完成后立即本地提交，不把已完成成果长期留在工作区。
- 结束前必须取回后台验证的最终结果，确认提交号及剩余改动；不能以"验证已启动"或过时的 IN_PROGRESS 作为交付。
- 提交前列出自动验证、人工验证和仍 unresolved 的边界。

---

## 四、参考

| 要什么 | 在哪 |
| --- | --- |
| lane 任务书与报告模板 | `docs/internal/lane_brief.md` |
| 时间账／轮次记录 | `docs/internal/LANE_TIMELOG.md`／`docs/internal/ROUNDS.md` |
| 审计报告（文档、代码、工具） | `docs/audits/` |
| lane 收尾验证 | `tools/lane_verify.sh affected <基线>` |
| 合并、门禁、发布、清理 | `tools/lane_merge.sh` 的 merge／gate／publish／cleanup（用合并树那份）；curation 并集 `tools/merge_curation_json.py` |
| 完整门禁 | `tools/verify.sh`（加 `--full` 或 `--deep`）；任务注册表 `python3 tools/hsl.py list`，同一入口的 check／generate／affected |
| 环境诊断 | `tools/doctor.sh [--original]` |
| 开游戏／试玩某一关 | `tools/play.sh`／`tools/playtest.sh <槽名>`（[PLAYTEST](docs/PLAYTEST.md)） |
| 文档链接检查 | `python3 tools/hsl_docs_check.py`；代码块里的工具路径 `python3 tools/hsl.py check docs:tool_references` |
| 公开导出 | `tools/oss_export.sh OUT_DIR [REF]`（去掉原版派生物、`docs/internal/`、`docs/audits/`、Markdown 的内部段等；残留未公开内容的名字就失败） |
| 证据用语自检 | `jevgrep lint --rules tools/typesafe/evidence_lint_rules.json --diff HEAD`（要联网和 key） |

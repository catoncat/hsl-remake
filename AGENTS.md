# HSL Remake Agent Guide

给代理（Claude Code、Codex 等）看的规矩，公开仓库也带着。给人看的贡献规则在 [CONTRIBUTING](CONTRIBUTING.md)，全部文档的索引在 [docs/README](docs/README.md)，唯一当前状态在 [docs/PROJECT.md](docs/PROJECT.md)。开工先读本文件和 PROJECT，承接 lane 再读任务书。与别处冲突时以「效率硬规则」为准，其次本文件。

写成代码样式、以 `docs/internal/` 或 `docs/audits/` 开头的路径是维护者的内部文档，公开导出不带，公开仓库里的代理跳过即可。lane 的派出、承接、审查、合并、门禁与并发怎么做见 `docs/internal/LANE_WORKFLOW.md`，任务书模板是 `docs/internal/lane_brief.md`。

## 效率硬规则

按最高性价比干活，不做占时间又不必要的活：

- **记步骤时间**：开工记 `date`，每步（探路／实现／调试／验证／提交）记起止；交付时写每步分钟、总墙钟、工具调用次数和最花时间的一步为什么。
- **非必要不测试**：只按「测试政策」写测试；验收只做任务书写明的 oracle，不自加负例、一次性探针、场景冒烟、手跑单测、逐字节复现证明、顺手的文档段落；不截图，除非是视觉改动（最多 3 张）。
- **非必要不门禁**：lane 收尾只跑一次 `tools/lane_verify.sh affected <基线>`（前台跑、Bash timeout 给到 600000，不放后台、不 sleep 轮询），不跑快门 `tools/verify.sh`；只改文档时改跑 `python3 tools/hsl.py check docs`、`python3 tools/hsl_docs_check.py` 与 `git diff --check`，不跑 Godot。不跑没命中的套件，不重生成没变的生成物。完整门禁只由负责人在合并树跑，按改动范围自动选档，几条 lane 一起交回只跑一次。
- **少轮次**：能合并的读、查、跑合成一条命令——时间主要花在一问一答的轮次上，不在命令本身。
- **砍自证性工作**：每轮收口做一次效率审计（门禁失败原因与耗时、每条 lane 的固定开销、测试与文档增长），砍固定开销最大的一步。

## 复刻口径

- 目标是自己的可维护游戏工程：原版资源、脚本、EXE 静态分析和原版运行实测只用来恢复规则，不自动操纵原作，也不把截图或 readback 当产品。
- 默认一律照原版（界面选择照原版，选项默认原版预设）；讲得清的改良只做成「重製選項」里的选项（[OPTIONS](docs/OPTIONS.md)），门禁与裁判只跑原版档。原版等价声明逐项要证据。
- 排序按复刻品质影响，不按清单可见度：影响输赢与走位的规则（AI、行动顺序、随机数、调级、伤害）先于演出，演出先于外观。
- 让原版程序当裁判：能用 `tools/hsltools/native/` 直接执行原版代码拿输出的，就不靠读代码或看录屏推；模型做视觉比对又慢又不准，看着不对的地方交给实玩反馈，再回原程序挖。
- 实玩反馈的「和原版不一样」是线索不是规格：查清原版后照原版做（原版有 bug 除外），证据与反馈冲突时按证据并说明。
- 实玩报的问题按类处理：写根因线索、盘点全游戏同类实例、在共享层修、加覆盖全部实例的检查，报告写找到／修了／剩余；截图只是样本。
- 实验用探针（≤5 场代表性战斗），回归用全量；说"久"要说已跑多久、预计多久、卡在哪一步。
- 原版运行观测只做定向验证：先确认现有资源、静态分析和证据包答不了，把问题压成一条可重复的路线，按[工具说明](tools/README.md)的入口先 `--dry-run` 再跑（多个原作窗口时显式指定，工具不猜）；raw 输出留在仓库外或 `ignored/`，只提升结论。

## 干活方式

- 接到继续开发或修复的任务，从 PROJECT 里选本次范围内可验证的结果，实际实现并验证，不停在调查、计划或待办。开工明确玩家结果、负责文件和验收条件，搜到实际定义和调用者再改；中断接续先核对 Git 和最后的验证结果。
- 常规可逆的选择自己定；原版语义未知先查证据，仍未知就标 provisional，不为推进编造等价。只对影响目标又查不清的歧义或未授权的动作提问。
- 历史用 Git 查（`git log -S`），逐轮流水在 `docs/internal/ROUNDS.md`；不把历史文件恢复成任务入口。

## 测试政策

测试非必要不写：只有不写就会出问题时才写。

- 只在两种情形写：①钉的是原版量得的事实（static-derived／模拟器实测），且没有现成套件覆盖；②不写就会让门禁抓不到会伤玩家的回归。
- 重制自己随机流的产物（开场等级数组、某个种子下的流状态、动作计数）不钉数值，只断言不变量；不为"消融能变红"而加测试；不为机械小改加复述实现的测试。
- 默认不新增测试文件，优先在现有套件里加一两个代表性用例；删掉多余的测试。任务书验收只写玩家可见结果与原版对照结果行。
- 不为让测试过而改断言；测试绿只证明当前合同，不证明原版等价。

## 代码规则

现行入口、状态所有者与数据分层见 [ARCHITECTURE](docs/ARCHITECTURE.md)。

- `BattlePlayLoop` 是唯一可变战斗状态所有者；Scene、`_unit_grid_coords` 与 `ActorRuntime` 只是输入／表现镜像，不拥有 HP、阵营、回合或目标真相。不新增第二套 battle dictionary、bootstrap snapshot 或界面持有的战斗真相。
- 规则在 `TacticalGridRules`、`CoreCombatRules`、`CoreTurnQueue` 与六个 `BattleLoop*` 静态模块里，关卡脚本（winfail／story）由 `WinfailCompiler`／`WinfailConditions`／`WinfailActions`／`WinfailScenarioRules` 解释；新规则直接进 play loop 对应的模块，不建聚合的上帝规则文件，不新增 readback 状态机。
- `BattleSceneRuntime.gd` 与 `BattlePlayLoop.gd` 已按模块拆分，新功能进对应模块（Input／Menus／Stage／Overlays；BattleLoopInit／Rewards／Script／AI／Combat／Inventory），不回填门面。
- 玩家菜单以 `BattlePlayLoop.IMPLEMENTED_COMMANDS` 为准；新增命令同时接通玩家交互与验证，未实现的命令隐藏，直接调用返回 `not_implemented`。
- 坐标只走 `viewport → logical → world → grid`；镜头、投影、脚点、移动范围层、点击判定、遮挡顺序和菜单锚点是同一个空间合同，一起改，不分别凭感觉调。
- 不为测试创建玩家看不见的长期 surface；不保留"缺数据时悄悄用另一套规则"的 fallback，必要输入缺失就明确失败。

<a id="evidence-language"></a>

## 证据用语

来源等级只用 [METHOD「证据分级」](docs/METHOD.md#证据分级)的七级，写结论的规矩见同页「写结论的规矩」。另外：

- 每个 `game/**/*.gd` 模块头的 `## provenance:` 块按 rules／layout／strings／timing／audio 五个维度声明来源（七级之外另有 `runtime-reference`、`remake-invented`），`hsl check provenance` 强制，汇总在 [PROVENANCE](docs/PROVENANCE.md)，格式见 [ARCHITECTURE「Provenance headers」](docs/ARCHITECTURE.md#provenance-headers)。
- 证据包只写原版事实；重制现状只放代码头 provenance 与差异清单条目。
- 旧断言先查来源（`git log -S`），被原版证据取代才改，并列出旧→新。
- 录像与外部模型的解释是待审查的线索：按 manifest 的源帧号定位，不把导出编号、单次录像或压缩像素升级为全局规则；参考图存在不等于游戏已修复。

## 仓库边界

- 开发输入：`game/`、`content/battles/`、`content/imported/`、`content/generated/`、`content/authored/`、`tests/`、`tools/`、`docs/evidence_packets/` 与现行文档。完整资源成员索引 `docs/evidence_packets/resource_inventory/resource_manifest.json` 只供机器搜索，不整文件读进上下文。
- 原作在仓库外，路径由 `HSL_ORIGINAL_DIR` 指定（维护者本机是 `$WINEPREFIX/drive_c/hsl`），复刻数据以它为准；Steam 經典版在 `HSL_STEAM_CLASSIC`，取得和核对用 `tools/hsl_steam_classic.py`（[证据包](docs/evidence_packets/resource_inventory/steam_classic_edition.md)）。
- 不得成为 tracked 产品依赖：`.godot/`、`*.import`、`ignored/`、`asset-dumps/`、`legal-assets/`、`.pytest_cache/`、编译二进制、raw trace、长反汇编和未整理截图。`game/`、`tests/` 里每个 live GDScript 都保留一一对应的 `*.gd.uid`，删脚本时同步删 UID。
- raw 发现压缩成可复跑的工具输出、imported／generated 数据或整理过的证据包后，才成为开发输入；原版截图、录像帧不进公开仓库（[CONTRIBUTING §5](CONTRIBUTING.md#5-不提交原版派生物)）。
- 会再用的脚本、配方、提示词当场放进受管目录并提交（公开的放 `tools/`，只给维护者用的放 `docs/internal/`）；`ignored/` 只留截图、录像、日志、大批试作图和缓存。

## 安全底线

- 不用 destructive reset 处理未知改动；不改别人正在认领的函数／改动块。
- 结束进程只按自己记录的 PID（`kill <pid>`），不用 `pkill`／`killall`／按名字匹配。
- 开窗口跑 Godot 脚本一律走 `tools/play.sh --script <脚本>`（它隔离 HOME）；`tools/godot.sh` 只给 `--headless` 隔离 HOME，开窗口直接跑会动到真实存档。
- 不用 Steam 文件覆盖原作目录；Steam 登录只由用户本人操作。不用长时间无监督的 playthrough 占用用户的鼠标键盘，不截整个桌面。
- 不提交原版派生物、密钥、会话 id 和本机绝对路径（写成 `$HSL_ORIGINAL_DIR`、`$WINEPREFIX`、`~` 或 `ignored/`）。
- 提交标题和正文会被 `tools/oss_sync.sh` 原样抄进公开仓库，不写未公开内容的名字；名单在 `docs/internal/unreleased_names.txt`，导出和同步遇到名单里的名字就失败。

## Git 纪律

- 开工看 `git status`、`git branch`、`git worktree list`。未知改动不动、不提交，接着干，汇报时提一句。
- 分支：`pipeline-line` 是合并树；`main` 与 `presentation-line` 只由 `tools/lane_merge.sh publish` 快进；lane 在 `.claude/worktrees/` 的独立工作树里，基线从 `pipeline-line` 快进。代理可以开临时工作树，用完当场删（删前核没合进去的提交）。
- 边提交边 push：每个独立、可验证的步骤完成就单独提交，不等全部验证完；lane 每次提交后 `git push -u origin HEAD`。
- **不等人**：lane 交回就合，过了门禁就发布，lane 回来直接派下一条，汇报和派活写在同一条消息里；人工验收不挡合并，玩家看得见的改动挂进工作台等实玩；时间预算到了报一次进度接着做；派不派 lane、门禁怎么提速、清理哪些工作树这类流程选择自己定，做完告知。只有会公开的内容（未公开内容并入主线）、台词、凭证与合规先问维护者。
- 结束前取回后台验证的最终结果，确认提交号和剩余改动，不以"验证已启动"或过时的进行中状态交付；交付时列出自动验证、人工验证和仍未解决的边界。

## 汇报与文档的写法

- **战斗命名**：汇报、任务书、合并说明、PROJECT 里提到任何一场战斗，一律写「玩家第 N 场 · 场景名（LEVEL0xx）」＋在做什么，文件号只放括号；对照表 [BATTLE_NAMES](docs/BATTLE_NAMES.md)。lane 报告只写文件号的，负责人转述时换成玩家口径。
- 对负责人汇报用玩家口径，不报编号；要拍板的事集中、带例子、带推荐，不阻塞。
- 不写死会随工作推进变化的数（条目数、探针数、模块数、文件行数）；进度数字只写在 PROJECT「进度尺」并带日期与出处。
- 仓库文件、任务书、提交说明不转述用户的话，也不写「用户说／拍板」这类说法，规则用中性说法写（`tools/hsl_docs_check.py` 会拦）。
- 文档按职责更新：PROJECT 只保留一屏当前状态，不追加日报，也不另开 TODO／STATUS／HANDOFF；每轮收口的流水进 `docs/internal/ROUNDS.md`；架构文档存现行合同；证据包存来源和回执。结构或代码路径变了同步修链接。
- 公开文档（`docs/internal/`、`docs/audits/` 之外）不链接内部文档，要提到时写成代码样式的路径；未公开内容的状态写进 PROJECT 的内部段（单独成行的 `<!-- internal -->` 与 `<!-- /internal -->` 之间），公开导出时整段去掉。

### 文档怎么写

文档按用途分三类，分开放，各写各的：

- **事实**：游戏和仓库现在是什么——规则、数值、剧情设定、数据格式、守则。
- **做法**：怎么做——流程、工具用法。
- **记录**：工作日志、调查、决定的来由、代理交接、审核、提示词。可以按日期追加，但不当规矩读。

事实和做法只写现在：不写「原来……现在改成……」、搬迁经过、旧地址还能不能用，也不写日期和进度。东西挪了就直接写新位置，来龙去脉留给 git log 和记录。当前进度只写在 [PROJECT](docs/PROJECT.md)，别的文档不另记。文件名带「守则」的文档不写日期和提交号；不再适用的文档在标题下第一行写 `> 已取代：见 …`，现行文档不再指向它（`tools/hsl_docs_check.py` 会拦）。

## 派 lane 还是自己改

- 可并行、写集不重叠、超过 30 行或碰规则的工作派 lane；≤30 行、不碰规则的小改（快捷键、文案、脚本一行）和纯文档改动直接在合并树改，不派 lane。lane 自己不再派 lane。
- 写集按函数／改动块认领而不是按文件：别人在改的文件，只要不碰同一函数、改动 ≤30 行就直接改，合并时解冲突。
- 只记进差异清单、不派 lane：1 px 取整、1–3 tick 或相位、闪烁相位、LSB 级合成、字间距；visibility＝invisible，或只改抽签次数、行为分布不变的；要 Wine 实测或调度模型才能判定的；原版没有的重制新增；证据包内部矛盾和纯文档措辞。

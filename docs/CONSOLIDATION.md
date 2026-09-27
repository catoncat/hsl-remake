# 收口冲刺（Consolidation Sprint）

**决策日期**：2026-09-20 **决策人**：用户（授权本对话 Agent 为项目负责人） **状态**：已于 2026-09-20 收口（`70f358f7`）；本文件仅保留历史决策与度量，不再冻结功能 lane。当前产品优先级只看 [PROJECT.md 的 Next steps](PROJECT.md#next-steps)，中断 lane 的恢复位置看 [协作入口](../PARALLEL_WORK.md)。

本文件记录当时为什么做、做什么、不做什么、怎样验收及协作。下文「冻结」「进行中」等描述属于冲刺期间的历史协议，不是当前派活状态。

## 1. 为什么现在做

过去 7 天 597 次提交（占全部 679 的 88%）全部来自多 lane 分片工作，从未整理。资产（规则、数据、证据、测试断言）是对的，**形式**已成负债——量得的数字（2026-09-20，提交 `125bcf20`）：

| 度量 | 现值 | 症状 |
| --- | --- | --- |
| `tools/*.py` | 306 个文件、66,958 行；64 个 `hsl_native_*_probe.py`、109 个 `test_hsl_*.py` | 一 lane 一脚本 |
| 各自解析原作源文件的工具 | 44 个读 `PLAYERS.TXT`、93 个直接打开 EXE | 没有共享读取器 |
| `tools/verify.sh` | 1,195 行；约 1,300 次串行 Python 进程调用；672 行是同 9 个工具 × 71 关逐关手写；8 条一模一样的重复检查；注释按 lane 命名（`lane ch2a`、`lane ch2c: level 37`） | 每 lane 往末尾追加 |
| Godot 测试 | 136 个 `tests/*.gd` 共 39,371 行（游戏本体 138 个文件 31,011 行）；70 个套件各起一个进程 | 无 runner，一 lane 一套件 |
| 门禁墙钟 | 约 45 分钟；Python 段 181 s，其余为冷导入 1.2 GB ＋ 70 个串行套件（走查一项 292 s） | 冷克隆属性放在每次合并路径上；退出时再删缓存，下一次定向测试又要导入 |
| 三条 lane 的 fan-in | 约 1.5 小时 | PROJECT.md 五次合并五次冲突；过期断言在合并后才暴露 |
| 运行时最大文件 | `BattleSceneRuntime.gd` 3,208 行、`BattlePlayLoop.gd` 2,351、`WinfailScenarioRules.gd` 2,034（含成段散文 `CLAIM_LIMITS`）、`BattleOpeningCoordinator.gd` 1,924 | ARCHITECTURE 已要求抽离 |
| 数据形状 | Python 生成器与 GDScript 运行时各自定义同一 unit 字典形状 | 第九波两个真 bug 皆源于此（`job_up_templates` 读错层级、装备按 int 列表写） |
| 文档 | `docs/PROJECT.md` 最长一行 14,850 字符；272 个 md、223 个证据包 | Next steps 是一段散文 |

## 2. 第一性原理

这个项目只需要五样东西：

1. 可玩的 Godot 游戏（`game/` ＋ `content/`）。
2. 每条规则、每份数据可追溯到原作证据（resource／static／runtime）。
3. 生成数据由确定性工具从仓库外的原作文件复现。
4. 锁住行为的测试。
5. 多 lane 并行时集成便宜。

②③④ 的**内容**是资产——本冲刺前一天它们抓到 3 个真回归；**形式**是负债。原则：**保留内容、重做形式、用现有产物做 oracle**。

现成的 oracle：

- tracked `content/generated/`、`content/imported/` 与证据 JSON 在工具重构后必须**逐字节不变**（`--check` 本来就是 regen-and-compare）；
- 每个 Godot 套件输出的 `checks=N` 在 runner 重构后必须不变；0 `SCRIPT ERROR`；
- 同一提交上快门与全门结论一致；
- 玩家可见变化仍需截图人工验收（列入决策清单，不由自动测试代替）。

## 3. 不动的东西

- `game/sim` 按原函数切分的细粒度规则文件：这是可追溯性，不聚合成上帝规则文件（AGENTS.md 既有规则）。
- 测试的断言**内容**；只改 harness。
- 证据用语纪律（resource-derived／static-derived／runtime-measured／user-confirmed／user-hypothesis／provisional／negative-evidence）；只把它做成机器可读。
- 已 tracked 的生成数据与导入数据；工具重构不得改变一个字节，除非另有独立 slice 并说明原因。
- 单一 play loop 真相、坐标链、表现与规则分离等现行架构合同。

## 4. 阶段

每阶段：目标 → 做法 → oracle → 交付 → 状态。阶段可并行的地方已标明；顺序原因是"每阶段让下一阶段更便宜"。

### P0 快门（流水线）

- **目标**：`tools/verify.sh --fast` 在本机（10 核／16 GB）的墙钟 ≈ 最长单项套件（走查 ~5 min）＋ 1 min；`--full` 保留冷导入与全部检查，只在阶段收口与波末运行。
- **做法**：
  1. 基线：带时间戳跑一次现门禁，得到 Python／冷导入／每个套件的分解（`ignored/verify-wave9-profiled.log`）。
  2. Python 段：把 `--check` 命令列表化，`xargs -P` 并行；同一命令去重。
  3. Godot 段：`--fast` 不删 `.godot`（热缓存增量导入）、**退出也不删**；70 个套件 N 路并行；先实测多进程共享 `.godot` 有无写冲突。
  4. sweep 用既有 `HSL_SWEEP_LEVELS` 分片并行；走查暂不拆（它就是快门的下界）。
  5. 缓存预热 tracer：把已导入的 `.godot` rsync 进新 worktree，验证 `--import` 变为秒级——成立则写进 lane 派发流程。
  6. 文档：`tests/README.md`、`tools/README.md`、AGENTS.md「Verification」段同步两级门禁语义。
- **oracle**：同一提交 `--fast` 与 `--full` 结论一致；`--full` 仍 VERIFY_PASS。
- **交付**：`verify.sh --fast|--full`、并行 runner 脚本、缓存预热步骤、基线与目标数字写入本文 §6。
- **状态**：已收口 `9a414858`（快门 457 s／全门 541 s，均 VERIFY_PASS、0 SCRIPT ERROR）。剩余交给 P2：sweep 单片独跑 234 s、走查 292 s 主要是实时等待而非 CPU。

### P1 工具收口

- **目标**：306 个脚本收进一个包 `tools/hsltools/`：共享源读取器（PLAYERS／ANIMAL／SHAPEDEF／PAK／EXE／脚本 IR）、**一个**原生探针 harness、生成器注册表（声明输入、输出、依赖）、`hsl check`（单进程、并行、可按改动过滤）、`hsl generate`（按依赖顺序重生成）。
- **做法**：负责人先写核心与三个 tracer（一个源读取器家族、一个探针、一个逐关生成器），证明 oracle 可用；其余按家族派 lane 机械迁移（探针家族、逐关数据链、资产导入器、证据检查器）。`verify.sh` 的 672 行逐关手写改为对注册表的循环。
- **oracle**：tracked 生成数据与证据 JSON 逐字节不变（`git status` 干净且 `hsl check --all` PASS）；重复检查归零；Python 单测 604 全绿。
- **交付**：`hsltools` 包、注册表、`hsl` CLI、迁移完成清单（每个旧脚本 → 新模块）、`tools/README.md` 重写。
- **状态**：核心已合并 `e7600ae9`（hsltools 包 3,809 行、注册表＋`hsl` CLI、124 个原生检查 1 s、Python 单测 604→620、生成数据零字节变化）；家族 lane：probes 已合并 `c74519a2`（56 探针，9 包用真 EXE 逐字节复现）、levels 已合并 `d97bcfa9`（1,023 条命令，本家族 58 s → 17 s）、assets 已合并 `704bb6e6`（32 工具，重复 PASS 行归零）；data 已合并 `bffbc2b5`（50 工具，两处任务名冲突改 `*_data`）；**legacy 1,160 → 0，native 1,286**；P1-close 已合并：台账成为注册表不变量（`check_ledger`：每条旧命令恰好被一个任务 replaces）、`LegacyScriptTask` 子进程路径与 `list-checks`／`--legacy` 删除、148 行手写模块清单改 `pkgutil` 自动发现、tools/README hsltools 段重写为现行合同。**P1 收口**。

### P2 测试收口

- **目标**：一个 runner 发现 `tests/**/*_test.gd`；纯规则套件在同一 Godot 进程内运行；runtime／sweep／walkthrough 类由驱动脚本分片并行；每个套件保留自己的 `checks=N` 计数并由 runner 汇总；共享断言与 SCRIPT ERROR 计数。
- **做法**：先做 runner ＋ 迁移 3 个纯规则套件为 tracer，再按家族派 lane 迁移；runtime 类套件保留独立进程但走同一驱动。
- **oracle**：每套件 `checks=N` 与迁移前一致；0 SCRIPT ERROR；快门墙钟不升。
- **交付**：`tests/run_all.gd`（或等价）、分片驱动、`tests/README.md` 重写（按能力路由而非按套件文件）。
- **状态**：runner 已合并 `7ca0c587`——根因是 headless 每帧固定睡 6.9 ms（套件 91% 时间在睡），`--fixed-fps 60` 令走查 292 s → 6.7 s、整 sweep ~8 min → 48 s；`tests/support/TestSuite.gd` ＋ `tests/run_all.gd` 让 24 个规则套件同进程运行；合并树快门 **211 s**（5 条 lane 并行时），Godot 段 148 s。P2b 已合并 `0fd019dd`：story_scene 等 6 个场景套件改等条件／墙钟收尾后进快钟（152 s → 22 s），8 个视图套件进 run_all（32 规则套件）并 4 片分片；**快门 130 s，Godot 段 70 s**（新下界 run_all#3 50 s）。P3a 的 48 个转发壳**保留**为场景的 readback／输入门面（负责人判断：它们是测试与调试唯一依赖的公开面，删掉要改 30+ 套件的访问路径而行为零收益，冲突面反而变大；模块实现已在五个文件里）。

### P3 运行时抽离与共享 schema

- **目标**：`BattleSceneRuntime.gd` 按 ARCHITECTURE 已命名的缝抽出 Input／Menu／Presentation／Opening 模块；`WinfailScenarioRules.CLAIM_LIMITS` 等散文迁到证据包并以引用替代；**一份** unit JSON schema（`content/schema/`）在 Python 生成器与 GDScript 加载两侧校验。
- **做法**：一次抽一条缝，抽完立即过快门；schema 先描述现状再收紧。
- **oracle**：表现合同测试、smoke、走查全绿；玩家可见布局／动效由用户截图验收（决策清单）。
- **交付**：模块化的 runtime、schema 与两侧校验器、ARCHITECTURE 对应章节更新。
- **状态**：P3a 已合并 `a09af4a5`（BattleSceneRuntime 3,208 → 1,681 行，五模块 Readback／Input／Menus／Stage／Overlays，48 个转发壳保留为 readback 门面；D3 已验收）；P3b 已合并 `7166e85f`（`content/schema/unit.schema.json` 27 必需键／67 属性，Python＋GDScript 两侧校验，`UNIT_SCHEMA_TESTS_PASS checks=2872` 含第九波负向回归；game/ 内 30 条散文字面串 → 0）；P3c 已合并 `70f358f7`（BattleOpeningCoordinator 1,924 → 762 行，`game/battle/runtime/opening/` 四模块，PASS 行逐字一致）。**P3 收口**；D3 用户实机验收完成。

### P4 文档与协作协议

- **目标**：`PROJECT.md` Next steps 改为结构化列表（一项一行、带链接、可独立合并）；证据包加机器可读头（kind、functions、status）并由工具生成索引；lane 协议：lane 只交回执、不改 `PROJECT.md`／`verify.sh`／索引，由负责人统一写。
- **oracle**：链接检查通过；下一波 fan-in 零文档冲突。
- **交付**：新 PROJECT.md 结构、证据包头规范与索引生成器、lane 任务书模板。
- **状态**：P4a（PROJECT.md 结构化）已做 `8fbb65ae`；P4b 已合并 `f64630c3`（222 包字段块、evidence index 的 `--check/--write/--lint`（现 `hsltools/evidence/index.py`）、KNOWLEDGE_INDEX 生成段）；P4c 的 [lane 任务书模板](templates/lane_brief.md)和 AGENTS.md 回执协议已在冲刺收口时就位。

## 5. 工作协议（冲刺期间）

- 功能 lane **冻结**到 P2 收口；期间只派收口 lane。
- lane 模型：fable-5-1 或 opus 级；任务书与报告按 [`docs/templates/lane_brief.md`](templates/lane_brief.md)，第一行短 ASCII 标签。
- lane 交付 = 代码 ＋ 测试 ＋ 报告（提交号、oracle 结果行、边界／消融／摩擦）；不改 `PROJECT.md`、`verify.sh`、索引类文件。
- lane 报告前必须跑快门；合并后立即删 worktree；磁盘可用 ≥ 20 GB。
- 负责人串行合并到 `presentation-line`，每阶段收口跑一次 `--full`，写 P-0xx 回执，快进 `main`。
- 不 push；不 destructive reset；不升级 provisional／不编造等价。
- 需用户判断的事项（截图验收、规则取舍、Wine 原生观察）进 §8 决策清单，不阻塞。

## 6. 度量基线与目标

| 度量 | 基线（`125bcf20`） | 目标 | 现值 |
| --- | --- | --- | --- |
| 快门墙钟 | 无快门；全门 ~45 min | ≈ 走查 ＋ 1 min | P0 **457 s**（`9a414858`）→ P2 **211 s**（`7ca0c587`）→ P2b **130 s**（`0fd019dd`，Godot 段 70 s；走查本身 6.7 s，目标已达） |
| 全门墙钟 | ~45 min（空载 ~14 min） | ≤ 15 min（冷导入为下界） | P0 541 s → 收口 **288 s**（`70f358f7`，空载；Godot 段 94 s） |
| 合并后定向测试前的导入 | 每次 ~10 min（门禁退出删缓存） | 0（缓存保留） | 4 s 热导入（P0） |
| lane worktree 首次导入 | ~10 min | 秒级（缓存预热） | seed 21–38 s ＋ import 28–47 s（8 条 lane 实测，随负载）；之后增量 3–4 s |
| 三 lane fan-in | ~1.5 h | ≤ 20 min | 每条 lane 合并＝审报告＋解冲突（多为清单追加）＋一次快门 2–6 min；第四波四条家族 lane 全部合入约 50 min（其中门禁 4 × ~4 min） |
| `verify.sh` 行数 | 1,195 | ≤ 100 | 94（P0） |
| 独立解析 PLAYERS.TXT／EXE 的工具 | 44／93 | 1／1 | 1／1（`hsltools/sources/tables.py`、`hsltools/native/image.py`）；156 个旧脚本只剩再导出垫片（4,145 行，见 §10） |
| 重复检查 | 8 | 0 | 0（assets 家族消融：ohm／priest／mobile_jobs 不再重复三条共享检查） |
| `PROJECT.md` 最长行（awk 字节数） | 14,850 | ≤ 1,200（表格行为下界） | 3,160（P4a：Next steps 改为 6 项列表；按区域的能力块拆为 128 行 bullets 移入 Current status；剩余最长行是预先存在的表格行） |
| PROJECT.md 合并冲突 | 5／5 次 | 0 | 0／12 次 lane 合并（lane 不改 PROJECT；冲突只出现在 registry 模块清单、README 追加段与 verify_runner 文档字符串，共 9 处，全部为两侧都保留） |

基线分解（`125bcf20`，带时间戳的串行旧门禁，空载）：doctor 1 s、Python 单测 60 s、1,282 条检查 120 s、冷导入 229 s、套件串行 30+ min（走查 292 s、sweep 单片 11 场独跑 234 s）。P0 后：单测 15 s、检查 31 s、热导入 2–4 s、79 个 Godot 作业 8 路并行 373 s。收口时（`70f358f7`，空载）：单测 39 s（661 测）、1,286 项检查 20 s（全部进程内）、44 个 Godot 作业 8 路 94 s（全门含冷导入）／70 s（快门）；tools/*.py 318 个 38,358 行，其中 hsltools 包 37,370 行、156 个垫片 4,145 行；tests 72 套件 40,161 行；game 31,586 行，最大文件 BattlePlayLoop 2,370（状态所有者，未拆）。

## 7. 风险与回退

- 多 Godot 进程共享 `.godot`：若实测有写冲突，退回"每分片一份缓存副本"（rsync 秒级）。
- 并行 `--check` 的临时文件冲突：命令在各自 `mktemp -d` 下运行；发现写 tracked 文件的 `--check` 一律视为 bug 修正。
- 工具迁移改变生成字节：该工具回退到旧实现并单独开 slice 查原因，不在迁移 slice 内"顺手修"。
- 运行时抽离引入表现回归：一次一条缝、快门即验；用户截图验收未通过则回退该缝。
- 冲刺过长：每阶段收口都可停，停在任一阶段边界项目都比之前健康。

## 8. 决策清单（需用户判断，累积不阻塞）

| # | 事项 | 背景 | 建议 |
| --- | --- | --- | --- |
| D1 | 42 名演员／上位行 `sprite_facing` 人眼判定 | `tools/hsl_sprite_facing_audit.py` 生成审核表到 `ignored/g/` | 冲刺后一次看完 |
| D2 | 兩棲族部落 第二次转职后菜单的原生观察 | 需 Wine 与用户键鼠 | 冲刺后安排一次 targeted route |
| D3 | P3 运行时抽离后的截图验收 | 布局／动效人工验收 | **已验收**（user-confirmed 2026-09-20：P3a／P3b 合并后菜单正常；P3c 开场抽离合并后用户实机打完第一战无问题） |

## 9. 进度记录

| 阶段 | 收口提交 | 门禁 | 备注 |
| --- | --- | --- | --- |
| P0 | `9a414858` | 快门 457 s／全门 541 s VERIFY_PASS（`ignored/full-gate-p0.log`） | 基线 profile 跑于 `125bcf20`；P1／P2 lane 基于此派出 |
| P2（runner） | `7ca0c587` | 快门 211 s／全门 **623 s** VERIFY_PASS，0 SCRIPT ERROR（`ignored/full-gate-p2.log`，5 条 lane 并行时；Godot 段 141 s） | 24 规则套件进程内、sweep 4 片＋fixed-fps 60；P1 核心 `e7600ae9`／P3a `a09af4a5`／P4b `f64630c3` 一并进入本收口点；P2b 已合并 `0fd019dd` |
| P3 收口＋冲刺收口 | `70f358f7`（文档提交见其后） | 快门 138 s（P1-close 合并树）／全门 **288 s** VERIFY_PASS，0 SCRIPT ERROR，661 单测、1,286 检查、69 套件（`ignored/full-gate-sprint-close.log`，空载） | P3b `7166e85f`／P3c `70f358f7`；P1-close `612a21d5`；全部 lane worktree 已删；D3 用户实机验收完成（菜单与第一战全程） |
| P1＋P2 收口 | `0fd019dd`（门禁跑于 `0fd019dd`；文档提交 `e3f39851`） | 快门 130 s／全门 **337 s** VERIFY_PASS，0 SCRIPT ERROR（`ignored/full-gate-p2b.log`，2 条 lane 并行时） | P1 四家族（probes `c74519a2`／levels `d97bcfa9`／assets `704bb6e6`／data `bffbc2b5`）legacy 归零；P2b `0fd019dd` 快钟＋分片；P1-close（注册表不变量／自动发现）与 P3c 在跑，冲刺末再跑一次全门 |

## 10. 冲刺遗留（不在本冲刺范围，接续时按 lane 派）

按预期收益 ÷ 验证成本排序：

1. **垫片脚本**：已关闭（T1 `7ef449d5`：152 个壳已在前一轮删除，剩余 34 个 `tools/hsl_*.py` 均为真实工具，README 列表；4 个再导出缝已拆、约 45 个调用方改指 `hsltools`）。遗留：文档代码块里的工具路径无守卫；`hsltools` 仍 import 8 个真实 `tools/hsl_*.py`。
2. **run_all 按实测耗时分片**：现在按名轮转，最重一片约 50 s 是 Godot 段下界；需先在 runner 里积累每套件 timings。
3. **BattleOpeningCoordinator 762 行**：对白三函数（100 行）可开第五缝；`_apply_event` 134 行必留。**BattlePlayLoop** 已按『同一 loop 字典上的静态模块』拆分（S8 `9daf8886`：2,519→1,116 行，六个 `BattleLoop*` 模块，无第二份真相；剩余为玩家流程合同）。
4. **unit_schema 的 inputs** 未逐列 122 个 `story_NNN.json`（`hsl affected` 对 story 改动不会指向它）；`tools/hsltools/data/story_corpus.py:88` 还有一处 Python 侧 CLAIM_LIMIT_IDS（散文已进 packet 表）。
5. 8 个不在检查台账的 `hsl_native_{animal,growth,growth_refresh,level,map_scroll,presentation,stats}_probe.py`（探索工具，非检查）；`hsl_title_layout_probe` 需 numpy（环境无，基线同样）。
6. `run_story_mode_explorer_tests` 在基线即 `STORY_MODE_EXPLORER_FAIL outcome=exhausted`（550 s，不入门禁）——属功能项 Next steps 3。
7. 观察到但未量化：多条 lane 同机跑门禁把 load 压到 100+，`HSL_VERIFY_JOBS=3` 已写进 lane 模板；子代理的 240 s 工具看门狗对每次门禁都会误报，需要更长阈值。

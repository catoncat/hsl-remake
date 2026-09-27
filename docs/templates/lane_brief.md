# Lane 任务书模板

负责人派出一条 lane（独立 git worktree 里的子代理）时按本模板写任务书；lane 按同一模板的「报告格式」交付。规则见 [AGENTS.md「Lane 协议」](../../AGENTS.md#lane-协议) 与 [收口冲刺 §5](../CONSOLIDATION.md#5-工作协议冲刺期间)。任务书写**目的、背景、约束、验收**，不写方法：lane 是有判断力的工程师，可能有比负责人更省事的路——负责人的推荐做法单列一节，标明是推荐、可换。填不出「背景」里的量得事实，说明还没到派活的时候。

```markdown
# lane <短 ASCII 标签>: <一句话说明改什么>

## 目的
<我们要什么：玩家／作者／开发者可见的结果。一两句。>

## 背景
<为什么现在做：哪个量得的问题、用户的原话、这件事在轮次计划里的位置；负责人已量出的事实（数字、位置、耗时、已知坑——每个数字都能被 lane 一条命令复核）。这一节给 lane 判断用，不是清单。>

## 约束（不能动的）
<原版等价与证据语言；PlayLoop 唯一真相；哪些文件别的 lane 正在改（避免冲突）；不为让测试过而改断言；其余方法自选。>

## 验收（怎么算做完）
- <逐条可执行的判定：PASS 行原样、字节零变化、数量不减、0 SCRIPT ERROR、`tools/lane_verify.sh affected <基线>` 的 LANE_VERIFY_PASS 行。>

## 推荐做法（可换）
<负责人倾向的路和理由：可能的 tracer bullet、相关文件、类似先例、已知坑。这是推荐不是命令——lane 若有更省事或更稳的路，走自己的，并在报告里说明为什么比推荐好。>

## 冲刺协议（必须遵守）
- 你在独立 git worktree 工作，基线是 <分支> `<提交>`。先读 AGENTS.md、当前轮次的决策记录（docs/PLAYABILITY.md 或任务书指定的文件）。
- 不改 docs/PROJECT.md、docs/CONSOLIDATION.md、tools/verify.sh；不动 game/sim 规则文件与任何测试的断言内容（harness 可改）。
- 每个可验证步骤单独提交（中文说明写清做了什么与 oracle 结果行）；不 push；不 destructive reset。
- **实验用探针，回归用全量**：回答「A 比 B 强多少／开关有没有用」这类问题只跑 ≤5 场有代表性的战斗（各自代表一种失败形态），几分钟出表；127 场全量与 tracked 对照矩阵只在深门回归里跑，不为实验重生成。任何预计超过 10 分钟的命令，先在报告草稿里写下「预计 N 分钟、回答什么问题」。
- **测试只在必要时写**（AGENTS.md「测试政策」）：钉原版量得的事实、或不写门禁就抓不到伤玩家的回归；重制随机产物不钉数值；默认不新增测试文件、不做消融。
- **胜负变了才必须重生成并说明；计数漂移由合并者顺手提交**：深门 sweep 只在某关 outcome（win／fail／dead_end）或 dead_end reason 变了、或关卡增删时 `AUTOPLAY_SWEEP_FAIL`；只有回合数、动作计数等变化时打印 `AUTOPLAY_SWEEP_DRIFT levels=[…]` 加逐字段行、照常 PASS，重写的 `content/generated/hsl/development/autoplay/results.json` 留在工作树。chapter 只在 dead_end 或 SCRIPT ERROR 时失败，不比对 `chapter.json`，只打印 `CHAPTER_AUTOPLAY_DRIFT`（stuck_at／胜场／重试）。所以：预计会翻转胜负的 lane（改 game/ 规则、战斗数据或指挥官），收尾前自己跑一次 128 场 sweep（约 15 分钟，先写预计时长），提交重写的 results.json（以及 `hsl check autoplay_brain` 要求的 brain_comparison.json），提交说明与报告里列出翻转场次；只有计数漂移时不必为它重跑，合并树深门打印的漂移由合并者随合并提交。
- **验证过就提交**：oracle 行绿、快门绿的成果由你自己提交到本 lane 分支，不要留着「等负责人审」——负责人只审报告与合并；收口时工作树里不得有未提交成果。
- 统一环境：`export HOME=$PWD/ignored/lane-home GIT_CONFIG_GLOBAL=~/.gitconfig XDG_CONFIG_HOME=~/.config PYTHONDONTWRITEBYTECODE=1 HSL_VERIFY_JOBS=3; mkdir -p $HOME`（`HSL_VERIFY_JOBS` 限制门禁并行度，多条 lane 同机时必须设）；新工作树直接 `tools/godot.sh --headless --import`（缺缓存时自动从最近成功导入的工作树克隆种子，只补导入有差异的文件）。
- **不跑快门 `tools/verify.sh`**（完整门禁只由负责人在合并树跑一次，且按改动范围自动选 affected／fast）；报告前跑 `tools/lane_verify.sh affected <基线>` 并贴 LANE_VERIFY_PASS 行；定向：`tools/godot.sh --headless --script res://tests/run_all.gd -- run_x_tests.gd`（规则套件）／`--script res://tests/run_x_tests.gd`（场景套件）／`python3 tools/hsl.py check <family>`。
- 结束自己启动的进程只按记录的 PID（`kill <pid>`），不用 `pkill`／`killall`／按名字匹配——会误杀别的 lane 与负责人的进程（见 AGENTS.md「Lane 协议」）。
- 工作树干净收尾（无未提交改动、无 orphan .gd.uid；ignored/ 不算）。
- 需负责人决定的取舍：选最保守的一种继续，报告里列出；不要停下等。
- **时间账（用户 2026-09-26 强制要求）**：开工先记 `date`，每个步骤记起止（读证据／开树导入／写代码／定向验证／截图／文档），报告 ⑤ 列出每步分钟数与总墙钟。**时间预算**：任务书给的预算到了就先交报告（做完的部分＋剩余清单），不要为了做完再拖。默认预算：小改 20 分钟、单条规则 45 分钟、含裁判实验 60 分钟。
- **只做任务书要的**：不截图除非任务书要（视觉改动才要，且最多 3 张）；不跑没命中的套件；不重生成没变的生成物；不写"顺手"的文档段落。

## 报告格式
① 提交号列表（每条一句话）② 交付物与用法 ③ oracle／检查结果行（原样粘贴）④ 迁移映射／边界／剩余／工具摩擦 ⑤ **时间账**：每步分钟数＋总墙钟＋最花时间的一步为什么
```

## 负责人侧回执

0. 把报告 ⑤ 的时间账连同派出／交回时刻、合并树门禁模式与秒数记进 [docs/LANE_TIMELOG.md](../LANE_TIMELOG.md) 一行；每轮收口按它做效率审计（哪一步固定开销最大、砍什么）。
1. 读报告 ④ 的边界，再 `git diff --stat 基线..lane` 核对文件域没有越界。
2. 合并到工作分支（`--no-ff`；`tools/lane_merge.sh merge REF MSGFILE`，几条同时交回就连续 merge 后只跑一次 `tools/lane_merge.sh gate`）；解冲突后跑**合并树**快门，提交说明写：lane 做了什么、根因、oracle 行、父级解了什么冲突、合并树门禁行。
3. 立即删 lane worktree 与分支；阶段收口跑 `--full`，在 [CONSOLIDATION §9](../CONSOLIDATION.md#9-进度记录) 记一行，快进 `main`／`presentation-line`。
4. 报告里"需负责人决定"的项进 [§8 决策清单](../CONSOLIDATION.md#8-决策清单需用户判断累积不阻塞)或直接决定并记入合并说明。

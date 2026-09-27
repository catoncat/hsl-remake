# 成长：NPC 交锋升级、玩家学魔法与学绝技的独立入口

> evidence: static-derived · status: live · functions: 0x40e870, 0x4348f0, 0x437080, 0x4373f0, 0x437970, 0x437a40, 0x439f80, 0x442720, 0x450840 · tools: hsltools/data/growth_lifecycle.py, hsltools/data/growth_lifecycle_trial.py, hsltools/probes/growth_lifecycle.py, hsltools/probes/job_up_learning.py, run_growth_lifecycle_tests.gd · updated: 2026-09-27

## 结论

- 原版三种成长来源互不混合：一般 NPC 交锋后由 `0x442720` 调 `0x439f80(actor,5)` 按职业配额自动加点、不学技；玩家 kind3 进入手动分配 UI；玩家学魔法由 `0x4373f0` 按当前职业与「存储等级+1」查表，学绝技由 `0x437a40`／`0x437970` 按职业、阶级与四项基础属性查表；两者都不抽随机数（static-derived）。
- 重制 `game/sim/LearningRules.gd` 按成员当前 `job_code` 选表（80–99 共二十个职业），`BattlePlayLoop` 在交锋事务里一并提交等级与新技能，`BattleAftermath` 只显示已提交消息；NPC 交锋升级沿 `EntryGrowthRules.allocate`（static-derived）。
- 已知差异：原手动 UI 对象的逐 tick 创建／点击时序未执行；开场阵容按场景顺序出生是重制调度（provisional）；全局随机流跨子系统的抽样次数未对齐，同一种子下出生等级不等于原版那一局（provisional）。

## 证据

**static-derived**（同一 SHA 锁定 `hsl01.exe` 指令执行与 PLAYERS／ITEM／MAGIC／SPECIAL 表；回执 [original_growth_lifecycle.json](original_growth_lifecycle.json)、[original_job_up_learning.json](original_job_up_learning.json)）

| 环节 | 原地址与字段 | 已执行范围 |
| --- | --- | --- |
| NPC 交锋升级 | `0x442720`，阶段 `0x4c432c=8`；`0x44299c..0x442a32` 检查 EXP 门槛与四项容量后调 `0x439f80(actor,5)` | 78 组：六职业、两种对象 kind、连续等级、门槛上下、部分／全封顶；玩家有剩余点数的分支止于 `0x442a45`（UI 未创建） |
| 玩家学魔法 | `0x4373f0` 按 job 与存储等级+1 检查；`0x437080` 写 `+0x174..0x188` 魔法位 | 与绝技合计 278 组完整返回：已拥有／未拥有、临界上下、多个门槛、六个职业 |
| 玩家学绝技 | `0x437a40` 选职业表与阶级，`0x437970` 逐行检查 `+0x64..0x70` 四基础属性；`0x437080` 写 `+0x158..0x170` | 一次调用只接受第一条符合且未拥有的能力；非空文字 buffer 只预览，null buffer 才写位 |
| 脚本全员重调 | `0x43f3a5..0x43f3fb`（一般对象）、`0x4438d4..0x44393c`（玩家对象）；需 phase 位 `0x4000000` 且 `0x4c1d48` 非零（仅 opcode 73 置位，见 [触发条件](original_auto_growth.md#开战调级的触发条件)） | 16 组有界 caller：条件齐备才以 `+0x1f8` 高／低字完整执行 `0x40e870` |
| opcode 73 `actAdjustAllPlayerLevel` | VM `0x450840`；设置点 `0x452408`、恢复点 `0x452f1a` | 两次正常返回：首次消耗一个 token、置阶段与全局 latch；恢复清 latch、不推进游标；VM 本身不改角色记录 |
| 消息与提交 caller | `0x437d6c`（魔法消息）、`0x43808f`／`0x4380d9`（绝技预览／提交） | NPC 自动分配 caller 不经过这些入口 |

学习门槛（当前职业表）：80 战士、88 盗贼、94 兽类不学魔法；祭司 85 于 6 级取得驅毒，法师 90 于 8 级取得治癒之水，翼战士 92 于 8 级取得毒术。战士绝技首条要求基础 26/20/20/24。随机性：78＋278 组完整轨迹里随机全局字不变；入场调级 `0x40e870` 调 `0x458c80`，抽全局流（状态 `0x4795d4`／`0x4795d8`）。

### 上位职业的学习表（static-derived）

两处学习函数都以角色记录 `+0x18` 的**当前**职业号分派；转职 `0x4348f0` 只改写职业号并保留已学位，故转职成员从下一次升级／确认属性起按上位表学习。`job_up_learning.py` 对 `0x4373f0`／`0x437a40` 以基础职业同款夹具完整执行 714 组（门槛上下、已拥有、预览／提交、四属性各减一）；表数据经 `hsltools/data/growth_lifecycle.py` 合并到 `growth_lifecycle.json`。

| 职业 | 魔法（`0x437950` 索引字节→`0x437920` case；上位 case 先查自身门槛，再落入基础职业 case） | 绝技（`0x437bd4` 跳表，表＝基础职业表、阶级更高） |
| --- | --- | --- |
| 81 劍豪 | 24 治癒之水、31 生命之水、34 滅 | 战士表 `0x4782b0` tier 2（慌雨斬／精神統一／皇龍閃） |
| 82 劍王 | 45 女神之淚，再落入 81 | 战士表 tier 3（再加孤月斬／闇瑩蝶舞／無想冥殺） |
| 84 弓聖 | 无 | 弓手表 `0x478378` tier 2 |
| 86 神官長 | 26 赤炎波動、28 地靈聖護、30 大地之癒、32 女神之淚，再落入 85 | 祭司表 `0x478314` tier 2 |
| 87 賢者 | 48 魔障壁、48 大地之惠、56 極，再落入 86 | 祭司表 tier 3 |
| 89 刺客 | 无 | 盗贼表 `0x4783c0` tier 2 |
| 91 jobElfMan | 25 魔燒焚燼／逆風裂空、27 烈蝕水彈／生命之水、30 天地鳴動、39 怒炎魔獄燋、40 極零裂凍破，再落入 90 | 无表（与 90／96 同为默认返回） |
| 97 邪獸 | 无 | 自有两行表 `0x47848c` tier 2：神罰（1/1/1/1）、神怒（80/40/28/45） |
| 99 DarkAngel | 26 地靈縛、27 封魔滅殺、28 天地鳴動、30 咒靈縛剎、37 怒濤地裂崩、42 死骸腐靈獄，再落入 98 | 魔剑士表 `0x4784ac` tier 2 |

93／95 的 tier 2 表与 98 见 [original_campaign_actors.md](original_campaign_actors.md)；83／88／94–97 不学魔法。

## 重制接线

- `game/sim/LearningRules.gd`：`acquire` 读当前 `job_code` 选表；转职前学到的记录保留取得时职业，按 `job_up_history` 校验。`learned_skills` 存 ID、名称、职业、取得等级、取得时四属性与触发类型；重复学习不加记录；未实现效果的技能记为已取得、显示「尚未可用」、菜单隐藏。
- `game/sim/loop/BattlePlayLoop.gd` `initialize_roster_growth`：`BattleSceneRuntime` 在 campaign carry 后、生成角色前调用；先登记玩家，再按阵容顺序给 NPC 出生（provisional 调度顺序）。手动分配确认后才取得绝技，取消或空分配不学技。
- `game/sim/EntryGrowthRules.gd`：NPC 交锋升级的配额与封顶退路。
- `game/sim/GlobalRandomStream.gd`：出生调级、新援、脚本建角抽全局流；全局流不入存档、不随战役承接，进程首次使用按时钟播种（无窗口取 `HSL_RNG_SEED`）。自动加点、手动点数、学技、换装、第二行动不抽随机数。
- `game/sim/CampaignCarryRules.gd`：携带取得记录，不携带生成流游标（旧 carry 的 `initialization_rng` 读入时忽略）；取得记录的浮点字段在来源与整数域验证后才规范为整数，5.5 级等非法值拒绝。单战快照 v6（出生收据记全局流两字），v5 按名拒绝。
- `game/battle/runtime/GrowthCampaignProgress.gd`：独立队伍（第三战）只交接伤害流，不把 Leonard 的人物／金币套给緹娜。
- `game/battle/scene/BattleAftermath.gd`：只显示已提交的升级／学技消息，并阻塞下一行动与结果页。
- 开发入口 `game/battle/development/GrowthLifecycleTrial.tscn`（由 `tools/hsltools/data/growth_lifecycle_trial.py` 生成），声明等级、近门槛经验、耐久与装备，不改正式初始法术／装备。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md`。

## 复现

`python3 tools/hsl.py check growth_lifecycle`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [growth_lifecycle](../runtime_observations/growth_lifecycle/receipt.json) | public、initial、initial_dev、unlock、below、multilevel、special、npc、ai_learn、mobile、limited、paralyzed、permanent、carry、victory、defeat、escape | `run_growth_lifecycle_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 原手动升级 UI 的逐 tick 创建／点击时序、上位表的提示时序未执行。
- 转职当刻不升级时是否另有补学入口未读（原 caller 只在升级／分配时调学习函数）。
- AI 决策链、出手动画延迟等其它全局抽取次数不是原版的。
- 未注册技能的具体效果与整个原高位调度器不在本包；转职事务见 [original_town_job_up.md](original_town_job_up.md)。
- opcode 73 的全局 phase 没有被模拟成另一个可变战斗所有者；重复触发不重新应用出生加成。

# 原 AI：目标选择与普通／魔法／特殊技类别

> evidence: static-derived; runtime-measured: 原版裁判不喂抽签分布; provisional: 原函数外的候选过滤 · status: live · functions: 0x40ba20, 0x40bb80, 0x40bee0, 0x40bf70, 0x40c110, 0x40c570, 0x40c620, 0x40d4e0, 0x42c780, 0x43f695, 0x43f79b, 0x43fa29, 0x43fd60, 0x440db1, 0x441002, 0x458c10, 0x458c80, 0x45ec32 · tools: hsltools/data/ai_profiles.py, hsltools/probes/_enemy_level.py, hsltools/probes/ai.py, run_ai_decision_tests.gd · updated: 2026-09-28

## 结论

- 原版：`0x40bb80` 按 find_type 七种比较在圆形搜索半径内选目标，严格改善时先更新基准再抽 `0x458c10()&1` 决定换不换；`0x40c570` 用同一个 `rand(99)+1` 样本的奇偶决定先试特殊技（奇）还是魔法（偶），并与倾向做 `<=` 比较（static-derived；200 组合成内存原函数执行全部正常返回）。
- 重制：`game/sim/AIDecisionRules.gd` 以相同 RNG 样本复现两函数的返回值与调用次数，`game/sim/loop/BattleLoopAI.gd` 在全部输入验证通过后才抽签，魔法／特殊技与玩家共用 `SkillResolutionRules` 与 `_resolve_skill`（static-derived 规则＋重制组合）。
- 一次行动的全局随机数消费（下表）：原版每次都走完优先级链的抽取，重制在链上各项不可能出手时不抽、锁定掷只在已持有目标时新抽；这些被省的抽取都落在不改变结果的分支上，锁定比较用的末值在原版也总是新掷，所以盯谁的分布与原版相同，逐值对拍不齐（static-derived 读法＋runtime-measured 分布）。
- 差异：原整体 16 状态 AI 与技能评分未作为整体复原（持有目标／锁定、wait_round、追击精化与攻击站位见 [original_ai_navigation](original_ai_navigation.md)「结论」）；原函数外的候选过滤是重制组合（provisional），不称整体 AI 等价。

## 证据

**static-derived**（[original_ai_decisions.json](original_ai_decisions.json)，`hsltools/probes/ai.py` 在合成内存执行原 x86 指令，调用者与 RNG 不替换；原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

`0x40bb80` 目标选择：扫描最多 200 槽，跳过 null、自身、对象 +0x80 的移除位 `0x8000000`；`0x40ba20` 取阵营掩码，双方 `&0x870000` 有交集则排除；搜索半径经 `0x45ec32` 用平方欧氏距离（含边界），排序距离用曼哈顿距离。

| find_type | 比较值 |
| --- | --- |
| 0 AI_NORMAL | 顺序扫描，已有候选时抽签是否替换 |
| 1/2 HPMIN/HPMAX | 当前 HP 最小／最大 |
| 3/4 NEAREST/FAREST | 世界坐标曼哈顿距离最小／最大 |
| 5/6 LEVELMIN/LEVELMAX | live+0x9c 等级最小／最大 |

- 职业偏好在 owner live+0x12c 的圆形近域内覆盖一般选择，与 find_range 分别传入；分组（跳转表＋TYPE）：施法 85/87/90/91/97/98/99/100，弓 83/84，剑 80/81/82，盗 88/89，翼 92/93，兽 94/95/96；多个优选对象同样抽保留签。
- 优选索引以 0 作 sentinel，与真实第 0 槽冲突；排除 SID 命中时回退此前候选。
- 104 组目标样例：7 种排序 × 7 种职业偏好 × 2 种子，范围 0/4/8、近域 0/5、排除 SID、阵营、已移除、空槽、远处角色、第 0 槽 sentinel；核对返回槽+1 与全部抽签。函数不检查 HP0。

`0x40c570` 类别：返回 0 普通／1 魔法／2 特殊技；样本 `0x458c80(99)+1`（1～99）。先试类别不存在时第二类复用原样本；先试类别存在但未通过时第二类再抽一次；禁魔位 2 只禁魔法。96 组样例：6 组倾向（含 95/0、0/100、50/50、20/90）× 4 种可用组合 × 禁魔与否 × 2 种子。

| 其他锚点 | 结论 |
| --- | --- |
| RNG | AI 用 `0x458c10/0x458c80`（状态 `0x4795d4/0x4795d8`），不同于伤害／状态 helper 的 `0x42c780` |
| `0x43fa8d..0x43face` | 先试返回类别，失败后 `(kind+1)%3` 轮换（调用者未整体执行） |
| `0x40c620..0x40c76c` | 准备已拥有且资源足够的魔法／特殊技 function 桶（ST 倍率、MP、禁魔）；不是地图洪泛 |
| `0x40bee0`、`0x43f6c2..0x43f74e` | 队友呼叫广播与消费，见 [original_ai_calls.md](original_ai_calls.md) |
| `0x40bf70`、`0x40c110` | 残血敌方扫描与自身低 HP，见 [original_ai_priority.md](original_ai_priority.md) |
| `0x40d4e0` | 单体／范围先后选择，见 [original_ai_skills.md](original_ai_skills.md) |

**一次 NPC 行动的随机数消费表**（static-derived，r2 读 `0x43f600..0x441040`、`0x43fd60..0x43fe40`；全部走全局流 `0x458c10`／`0x458c80`，`rand(n)` 取 `(r & 0xffff) % n`）：

| 顺序 | 调用点 | 抽法 | 条件 |
| --- | --- | --- | --- |
| 1 获取 | `0x43f695`（`+0x24≠0` 或 `+0xd8≠+0xdc`；否则 `0x43f63c` 半径 8）→ `0x40bb80` | `0x40bd4f` `0x458c10()&1`，每个严格改善且已有候选的对象一次；优选职业命中再一次 | 候选数决定次数；无结果取呼叫目标 `+0x8a` 时 `0x43f73e` → `0x40c110`（`0x40c138` `rand(18)`） |
| 2 链首掷 | `0x440db5` | `rand(99)+1` 一次 | 每次进入 `0x440db1`（含选中项失败返回） |
| 3 链逐项 | 位 2 `+0x1d8`、位 1 `+0x1d4`、位 4 `+0x1dc`、位 8 `+0x1e0`、位 0x10 `+0x1e4` | 未尝试且 r ≤ 门槛：选中，`0x441035` 写状态；否则在 `0x440ddf`／`0x440e1b`／`0x440e57`／`0x440e93`／`0x440ecf` 重掷 `rand(99)+1` | 已尝试位跳过不抽；每项只试一次 |
| 4a 自身 HP | `0x43fa29` | `0x40d4e0`（`0x40d500` `rand(100)+1`）→ `0x40c110`（`0x40c138` `rand(18)`） | 不需回复回 `0x440db1`；需要时 `0x43fa7e` → `0x40c570` |
| 4b 残血敌方 | `0x43f79b` | `0x40bf70` 方域内每个合格对象 `0x40c061` `rand(18)`；找到后 `0x40d4e0` 一次，每个找到的 `0x40c570`（`0x40c58d`，再掷 `0x40c5b3`／`0x40c5f8`） | 普通类别 `0x409090`／`0x40d8b0` 有站位即持有进攻（state 0xb），否则 `0x43f994` 续扫；扫完回 `0x440db1` |
| 5 锁定 | `0x441002` | 不抽；末值 r（最后一次重掷或首掷，恒为新掷）> `+0x1e8` → `0x441022` 重扫 `0x40bb80`（`0x40bd4f` 掷） | 链全部未中、`0x440ef1` 定点守卫之后（守卫 `0x440f88` 也可重扫） |
| 6 进攻 | `0x43fd60` | 持有失效 `0x43fd98` 重扫；`0x43fdc9` `0x40d4e0`（`0x40d500`）→ `0x43fe0c` `0x40c570`（`0x40c58d` 起） | 魔法／特殊技分支再抽 `0x40c7f8`／`0x40c842`／`0x40de0c`／`0x40de56`，落空侧移 `0x43ff32` |
| 7 追击 | `0x440d7f` 之后 | `0x413740` 同距 `0x41385d` `&1`、`0x413890` `rand(100)` | 见 [original_ai_navigation.md](original_ai_navigation.md) |

重制对照：获取（1）与进攻类别掷（6 的 `0x40c570`）同结构；链（2～4）在无回复手段且无残血机会时整段不抽（`BattleLoopAI._select_ai_priority` 起始 attempted＝3），辅助三项只在有可用辅助时抽；锁定只在已持有目标时新抽 `rand(99)+1`（`_ai_lock_check`）；`0x40d4e0` 只在有魔法时、排在类别掷之后抽。省掉的抽取都在不可能出手的分支里；原版末值 r 每次都是某一格失败后的新掷，`P(重扫)=(99−ai_lock)/99` 两边相同；同一串 `0x40bd4f` 掷两边选中同一目标（下段逐种子对照）。

**runtime-measured：不喂抽签的盯谁分布**（原版 `_enemy_level.py batch --mix 20 --turns 1`，重制 `export_enemy_turns.gd --seed s`，同一局面）：

| 单位 | 原版 | 重制 | 卡方蒙特卡洛 p |
| --- | --- | --- | --- |
| 玩家第 1 场 · 棄卒（LEVEL051）r1 023_2 | 32 种子 026_1×17 021_1×15 | 种子 1..32：026_1×10 021_1×22；1..200：026_1×96 021_1×104 | 0.593 |
| 玩家第 2 场 · 惡夢的終曲（LEVEL052）开场 ally023_2 | 128 种子 021_5×59 021_1×33 026_2×24 021_6×12 | 200 种子 021_5×99 021_1×52 026_2×39 021_6×10 | 0.202（32 种子时 0.001） |
| 同上 ally024_1 | 021_6×57 021_5×35 026_2×18 069_2×18 | 021_6×92 021_5×49 069_2×30 026_2×29 | 0.899 |
| 同上 ally024_2 | 021_8×62 021_7×33 021_5×18 021_4×12 026_1×2 069_1×1 | 021_8×77 021_7×57 021_5×34 069_1×15 021_4×10 026_1×7 | 0.003 |

023_2 两个候选、每次扫描一掷，两边首扫＋重扫的掷值到目标的对应 32/32 相同；10:22 是重制种子 1..32 的抽样偏差。ally024_2 的掷串到目标对应两边相同（`01111`→069_1、`11111`→026_1），五掷串分布对均匀的卡方 28.2／21.8（31 自由度，95% 线 45.0）；差在首扫四掷（四个候选）的比例 11/128 对 34/200，即此前行动者的落点改变了搜索半径内的候选数（第 2 场 enemy021_5 落点 p=0.042、enemy021_6 p=0.023），属追击精化层，不在目标选择层。

**resource-derived**：`hsltools/data/ai_profiles.py` 从 PLAYERS、TYPE、SHAPEDEF 生成 66 个声明到 `content/generated/hsl/ai/profiles.json`（find_type、find_range、find_flag、find_no_id、魔法／特殊技倾向、ai_call_range、ai_fixed、职业、SID）；缺必要字段标 `missing_required`，不借用他人策略。第一、二战的 001/021/023/024/025/026 字段齐全。

**重制侧回执**（Godot 640×480，真实 Wait 按钮经 `Viewport.push_input` 触发 Runtime AI；夹具四人、400HP、关闭反击，026 魔法倾向设 100、Leonard ST100 且由 AI 控制，不代表正常第一战）：法师幻火 MP 30→22；友军气刃斩 ST 100→80，与玩家同一结算路径；演出后队列 index=2 交给下一可控角色，无重复 AI 动作。回执目录已删除，本段为历史记录。

## 重制接线

- `game/sim/AIDecisionRules.gd`、`game/sim/loop/BattleLoopAI.gd`：provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_decisions.md`。
- `_prepare_ai_turn` 先验证身份、策略、移动输入、技能字段；缺字段返回命名 `scenario_error`，units／队列／收据不变，不改用普通攻击。缺 MP/ST、禁魔只改变可用类别。
- `ai_profiles` 是 PlayLoop 一次加载的不可变输入；HP、位置、等级、阵营、状态、MP/ST、库存取当前 units。
- 重制组合（provisional，替换点为原 AI 调用者读出后）：
  - 源范围内有本回合可攻击目标时先保留可攻击集合，再按原目标规则排序；绕开封闭最近敌人、长枪原地保持距离。
  - 源 SID 排除在候选生成前执行；纯原函数的回退 quirk 单独对照。
  - owner+0x12c 近域暂用当前 move_point。
  - 魔法取最小位移并在受支持法术中选一项。
  - 无搜索结果时采用队友呼叫，仍无则 Wait。
- 普通攻击站位与向目标推进已不属重制组合：`AINavigationRules.attack_stations`／`attack_station`（`0x40d8b0 → 0x413390`）与追击精化 `approach_point`，见 [original_ai_navigation](original_ai_navigation.md)「结论」。

## 复现

`python3 tools/hsl.py check ai`（重算已保存 200 组；`uv run --with unicorn==2.1.4 python3 tools/hsl.py generate ai --exe "$HSL_ORIGINAL_DIR/hsl01.exe"` 在 16384 条指令上限内重新执行原字节）。

## 边界

- 原桶的全部技能与评分仍未复原；未注册的治疗／辅助技能不会由 AI 私造效果。
- 原整体 16 状态机、引擎标记清理与槽复用未作为整体复原；目标锁定／等待、ai_fixed、追击精化与攻击站位见 [original_ai_navigation](original_ai_navigation.md)，治疗与辅助优先级见 [original_ai_priority](original_ai_priority.md)／[original_ai_support](original_ai_support.md)，NPC 出生调级 `0x40e870` 见 [original_auto_growth](original_auto_growth.md)，麻痺见 [original_paralysis](original_paralysis.md)。
- 随机数消费表的重制侧只做到分布等价：同一初始状态下重制与原版的全局流逐值不齐（链省抽、锁定新掷、`0x40d4e0` 位置）；辅助三项（+0x1dc／+0x1e0／+0x1e4）选中后各自的抽取未逐条列入本表。
- 机器包只声称已初始化并执行的路径，不推断未定义栈值。
- 合成内存原函数执行不是原作自然游玩或整场等价证明。

# 原 AI：目标选择与普通／魔法／特殊技类别

> evidence: static-derived · status: live · functions: 0x40ba20, 0x40bb80, 0x40bee0, 0x40bf70, 0x40c110, 0x40c570, 0x40c620, 0x40d4e0, 0x42c780, 0x458c10, 0x458c80, 0x45ec32 · tools: hsltools/data/ai_profiles.py, hsltools/probes/ai.py, run_ai_decision_tests.gd · updated: 2026-09-27

## 结论

- 原版：`0x40bb80` 按 find_type 七种比较在圆形搜索半径内选目标，严格改善时先更新基准再抽 `0x458c10()&1` 决定换不换；`0x40c570` 用同一个 `rand(99)+1` 样本的奇偶决定先试特殊技（奇）还是魔法（偶），并与倾向做 `<=` 比较（static-derived；200 组合成内存原函数执行全部正常返回）。
- 重制：`game/sim/AIDecisionRules.gd` 以相同 RNG 样本复现两函数的返回值与调用次数，`game/sim/loop/BattleLoopAI.gd` 在全部输入验证通过后才抽签，魔法／特殊技与玩家共用 `SkillResolutionRules` 与 `_resolve_skill`（static-derived 规则＋重制组合）。
- 差异：原整体 16 状态 AI、目标锁定／等待、原路径选择与技能评分未复原；原函数外的候选过滤与移动取格是重制组合（provisional），不称整体 AI 等价。

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
  - 选定目标后普通攻击取最低移动费用与最小横移；魔法取最小位移并在受支持法术中选一项。
  - 无可攻击目标时向目标推进；无搜索结果时采用队友呼叫，仍无则 Wait。

## 复现

`python3 tools/hsl.py check ai`（重算已保存 200 组；`uv run --with unicorn==2.1.4 python3 tools/hsl.py generate ai --exe "$HSL_ORIGINAL_DIR/hsl01.exe"` 在 16384 条指令上限内重新执行原字节）。

## 边界

- 原桶的全部技能与评分仍未复原；未注册的治疗／辅助技能不会由 AI 私造效果。
- 原整体 16 状态机、目标锁定／等待、引擎标记清理与槽复用、治疗与辅助优先级、麻痺 wake/skip、ai_fixed、完整原路径选择、NPC 动态等级初始化未复原。
- 机器包只声称已初始化并执行的路径，不推断未定义栈值。
- 合成内存原函数执行不是原作自然游玩或整场等价证明。

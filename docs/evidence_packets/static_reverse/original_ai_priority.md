# 原 AI：自救用药与残血敌方机会

> evidence: static-derived; runtime-measured: 原版裁判残血路径打谁用什么的分布; provisional: 无注册药品时跳过自身 HP 检查 · status: live · functions: 0x40bf70, 0x40c110, 0x40c1d0, 0x40c570, 0x40c770, 0x40c9a0, 0x40cca0, 0x40d340, 0x40d4e0, 0x40d8b0, 0x40df70, 0x43f504, 0x43f765, 0x43f79b, 0x440d01, 0x44fa80 · tools: hsltools/probes/_enemy_level.py, hsltools/probes/ai_priority.py, run_ai_support_tests.gd · updated: 2026-09-29

## 结论

- 原版：每次进入先抽 `rand(99)+1`，未尝试的自身 HP 检查（+0x1d8）先比，成功选 mode2；再比残血敌方检查（+0x1d4），成功 mode1；自身门槛由 `0x40c110` 计算，药品取 `0x40c1d0` 背包中第一件回血消耗品；残血敌方由 `0x40bf70` 在含边界方形范围内按登记槽顺序找首个 `hp<=clamp(...,10,80)` 的对象（static-derived；146 组原指令执行：98 正常返回、48 有界 prefix）。残血检查 `0x43f79b..0x43fa24` 是逐候选的循环：`0x40d4e0` 循环外抽一次、全部候选共用，每名候选掷一次 `0x40c570` 且只试掷中的一类，不成立换下一名；扫尽后从 0 号重扫只问普通，仍无经 +0x8c＝0x10001 回链首（static-derived，r2 读）。
- 重制：`game/sim/AIPriorityRules.gd`、`game/sim/AISelfPreservation.gd` 复现数值与顺序，`BattleLoopAI._ai_dying_scan` 按原版循环逐候选掷类别、失败换人、第二遍只问普通、仍无回链首，用药与玩家共用 `_resolve_item_use`（static-derived 规则＋重制组合）；原版裁判两个压残血盘面各 32 种子，残血路径打谁、用什么规则类分歧 0，随机类最小 p＝0.11（runtime-measured，见「证据」）。
- 差异：原完整辅助与整回合逐值 RNG 序列未复原（持有目标／ai_lock 与 wait_round 见 [original_ai_navigation](original_ai_navigation.md)「结论」，抽数分布见 [original_ai_decisions](original_ai_decisions.md)「结论」）；无注册药品时跳过自身 HP 检查是重制组合（provisional）；方域内没有一名敌方有站位或伤害施放时残血检查不掷就记为已尝试，只省抽取：链上自身 HP 位总在残血位之前记掉，原版残血检查落空经 0x10001 回链时两位都已尝试，结果同样落到后续项。

## 证据

**static-derived**（[original_ai_priority.json](original_ai_priority.json)，`hsltools/probes/ai_priority.py` 在合成内存执行未替换的原 x86 与 RNG，16384 条指令上限；原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

| 组 | 样例 | 结果 |
| --- | --- | --- |
| 敌方扫描 `0x40bf70` | 60 | 正常返回 |
| 自身血量 `0x40c110` | 33 | 正常返回 |
| 背包选择 `0x40c1d0` | 5 | 正常返回 |
| 优先级前段 `0x440db1..0x440e3d` | 48 | prefix，在 `0x441035` 状态写入或 `0x440e3d` 后续检查前停止 |

| 锚点 | 结论 |
| --- | --- |
| parser `0x44c8f8..0x44c917`／`0x44c926..0x44c942` | `ai_check_dying`→+0x1d4，`ai_check_hp`→+0x1d8 |
| `0x440db1..0x440e3d` | 先抽 99；自身 HP 检查成功 mode2、attempt bit2；残血敌方成功 mode1、bit1；已尝试位跳过；失败检查另抽一次 99 |
| `0x40c110` | `raw=floor(max_hp*(12+rand(18))/100)`；raw<10 → `10+raw%10`，raw>160 → `160+raw%16`，否则 raw；需 `max_hp-hp>=10` 且 `hp<=threshold` |
| `0x40c1d0` | 顺扫 actor+0x138 八格，ITEM +8 type=1 且 +0x2c add_hp≠0，返回首件槽号+1；不比药效、不耗 RNG |
| `0x43fa29..0x43fac1`、`0x4406d7` | 自救 caller 先查自身血量，普通类别命中 `0x40c1d0` 后进物品状态 |
| `0x40bf70` | 第三参数为起始零基槽，返回槽+1；`0x43f994/0x43f9f6` 以上次返回值续扫；范围 `abs(delta)<=find_range*32`（方形含边界）；每个空间合格敌方抽 `rand(18)`，门槛 `clamp(floor(max_hp*(12+rand(18))/100),10,80)`（绝对 HP）；首个命中并通过 SID 排除即返回，不再排序 |
| `0x43f79b..0x43fa24` | 首扫 `0x40bf70(actor,[+0x1c8],0)` 写 [0x4c1cfc]，无候选 `0x43f7b8` 回链；`0x43f7bf` `0x40d4e0` 一次写 [0x4c2c50]／[0x4c2c4c]；每名候选 `0x43f824` `0x40c570(actor,0x40dd60(),0x40e1f0())`：普通 `0x409090` 有武器且 `0x40d8b0(actor,cand)==cand` → +0x88＝cand、+0x8c＝0xb0000；魔法 `0x43f8f6` `0x40d340(actor,cand,first,fallback,mode,1)`、特技 `0x43f873` `0x40df70(…,1)`：非 0 → +0x88、+0x8e＝0xd／0x14 跳 `0x440614`，−1 → +0x80 \|＝ 0x200／0x400，0 → 换人；失败 `0x43f982`／`0x43f987` → `0x43f994` 续扫；扫尽 `0x43f9a6` 从 0 号重扫只问普通（`0x43fa13`），仍无 `0x43fa04` +0x8c＝0x10001 |
| `0x43f765`／`0x43f774`／`0x43f77f` | state 1（分派表 `0x4421b4`＋索引字节 `0x4421f4`）：sub 1 `je 0x440db1` 回链首，不清 +0x98、不动 0x10000；sub 0 先查 +0x80：带 0x200 跳 `0x43f8d3` 续法术、带 0x400 跳 `0x43f850` 续绝技，否则新扫。−1 来自 `0x40cca0` 每帧格数预算（[0x476b10]，续算旗 [0x4c1a40]）用尽，重制一步规划完，无可见后果 |
| `0x43f504..0x43f53f`、`0x440d01`／`0x440da1` | state 0 sub 1 非剧情阶段清 +0x98（`0x43f51d`）、+0x80 \|＝ 0x10000（`0x43f523`）后进链，每个 AI 回合都置位；清位只在 `0x440ff6`（锁定前）、`0x441318`、`0x441f41`，所以只有跳过锁定的残血 state 0xb 进站位时还带着。站位 `0x410a50` 返回 0（首站位是自身格且该格武器够不着，`0x40fb20` flag 1 贴墙不对称）时 `0x440d01` 见位回链首、不结束回合；`0x440da1` 追击失败在此路径不可达（`0x40d8b0` 已在候选上找到站位） |
| `0x40c570` | 入口 `0x40c58d` 无条件 `rand(99)`，没有法术也抽 |
| `0x44fa80` | removed 对象返回 -1；`0x40bf70` 本身无 removed／HP0 过滤（另有两组从 removed 对象起扫的样例） |
| `0x40d4e0` | parser `0x44c9c5..0x44c9e1`→+0x1f4 `ai_magic_multi_first`：`rand(100)+1`，字段 0 时 ≤30 返回 1，非零时 >30 返回 1；详见 [original_ai_skills.md](original_ai_skills.md) |
| `0x40c770` | 按 function 桶与 MAGIC `use_ratio`（parser `0x44db40..0x44db5d`→+0x28）试选技能；`0x40c970` 是其尾部，后继入口 `0x40c9a0` 选范围中心，`0x40cca0` 枚举移动施法格 |

**runtime-measured：残血路径打谁、用什么**（原版 `_enemy_level.py batch --levels 51 --seeds 1..32 --mix 32`，重制 `export_enemy_turns.gd --seed s`，同一盘面）：玩家第 1 场 · 棄卒（LEVEL051）开场，023_1、023_2、024_2 压到 HP 6（盘面 A）；盘面 B 另把两名法师 026_1／026_2 移到 (12,11)／(13,12) 并排在最先行动。逐单位（行动, 目标, 技能）分布，原版:重制：

| 盘面 | 单位 | 残血路径的决定 | 原版:重制 | p |
| --- | --- | --- | --- | --- |
| A | 021_4 | 普通 → 023_1 | 32:31（另 1 种子该单位行动前已被击倒） | 1.00 |
| A | 021_2 | 第一名候选落空换人，普通 → 023_2；否则回链追击 | 攻 023_2 30:26、追 leonard 1:5、追 023_1 1:0 | 0.14 |
| A | 024_1 | 普通 → 021_4（候选落空回链时同样打 021_4） | 31:30，用药 1:1，追 021_1 0:1 | 0.60 |
| B | 026_2 | 魔法 → 023_2（magicAIR／magicFIRE） | 16:16、16:16 | 1.00 |
| B | 021_4 | 普通 → 023_1 | 32:32 | 1.00 |

其余单位（021_1／021_3／021_5／026_1 等）候选都落空后回链追击，追击目标分布两盘面最小 p＝0.11（021_5，盘面 B）。原版这些单位在残血检查里逐名掷类别、落空后回链；重制因方域内无站位也无施放，残血检查不掷直接记为已尝试，决定相同、抽数不同。规则类分歧 0。

**重制侧回执**（Godot 640×480，真实 Wait 按钮触发，正常时钟；夹具五单位、健康 HP400／残血 HP8／自救 HP4、两份药、counter0、026 魔法倾向 100，不代表正常第一战）：自救 HP 4→44 只耗一份药，显示 +40HP；近战机会绕开健康近敌改打 HP8 目标；法术机会一次扣 MP；各路线一个 AI 收据，队列 index2 交给 `enemy023_1`。驱动已退役，回执为历史记录。

## 重制接线

- `game/sim/AIPriorityRules.gd`、`game/sim/AISelfPreservation.gd`、`game/sim/loop/BattleLoopAI.gd`：provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_priority.md`。
- PlayLoop 在任何 RNG、移动、广播、扣费、队列变化前验证两个倾向、库存、注册药品效果、存活对象 HP/maxHP、普通圆域、机会方域与呼叫对象技能输入；HP 输入上限 1000000（防 signed32 溢出）。
- 回血与扣物由 `_resolve_item_use` 一次提交，收据含 HP 前后、槽号、唯一 sequence；毒伤与状态持续在回血后处理一次，禁魔不阻止用药。给友军的回复药可在其行动中被使用；正常场景不给 AI 凭空加药。
- 残血检查 `BattleLoopAI._ai_dying_scan`：`0x40d4e0` 循环外一次，经 `AISkillPlanning.choose` 的 requested_buckets 交给每名候选；每名候选一次 `AIDecisionRules.select_action`（行动者自身的魔法／特技可用性），只试掷中的一类，失败从候选之后续扫；扫尽从 0 号只问普通；仍无回链首，已尝试位保留。定下候选即写持有目标（不广播）；站位走不动时回链首（`0x440d01`）。回执 `priority.dying_checks` 记每名候选的类别、掷值与失败原因（unarmed／no_station／no_cast）。
- 表现：`BattlePresentation.show_item_use` 按唯一收据显示回血／解毒文字与用药音效，重复收据不重复。
- 重制组合（provisional）：原普通目标与残血目标分别存收据；技能与位置评分、注册药品子集、死亡过滤、SID 预排除不升级为原整体 AI 等价。

## 复现

`python3 tools/hsl.py check ai_priority`（重执行原字节：`uv run --with unicorn==2.1.4 python3 tools/hsl.py generate ai_priority --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`）。

## 边界

- 优先级 dispatcher 只执行到前两种检查，完整 dispatcher 未执行。
- 原用药效果函数未执行；物品效果沿 `ItemUseRules.prepare`。
- 未注册的回复魔法／特殊技不会被 AI 创造。
- 完整地图／辅助筛选、owner+0x12c、可行动状态未复原；目标锁定与 wait_round 已照原版（[original_ai_navigation](original_ai_navigation.md)「结论」）。
- 不保证整回合 RNG 与原版相同。

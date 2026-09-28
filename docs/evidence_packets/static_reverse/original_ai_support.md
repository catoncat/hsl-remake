# 原 AI：友军回复、状态援助、增益自施与友军用药

> evidence: static-derived; runtime-measured: 0x440db5 链首掷（enemy_turn 回执）, L547 buff self-cast distribution, ALLYHEAL 友军用药（模板背包、救与不救、0x40d530 落点，第 51／52 关裁判）; provisional: 空类别预先跳过、自清毒组合位置、全局 RNG 逐值序列 · status: live · functions: 0x40c110, 0x40c1b0, 0x40c2d0, 0x40c2f0, 0x40c3a0, 0x40c480, 0x40d530, 0x40dcf0, 0x40e180, 0x40f440, 0x40fa80, 0x413390, 0x43fce1, 0x44cb10, 0x458c80 · tools: hsltools/probes/_enemy_level.py, hsltools/probes/ai_support.py, run_ai_support_tests.gd · updated: 2026-09-28

## 结论

- 原版：优先级链位 4（友军回复，比 `ai_help_otherhp`）先于位 8（状态援助，比 `ai_help_status`）；`0x40c2f0`／`0x40c3a0` 在八格方域按登记槽序续查同侧（`side & 0x870000` 相等）非自身友军；增益入口 `0x43fce1` 先找友军、找不到才自施；友军用药取模板背包首件回血药，落点 `0x40d530` 不含自身格、按半格偏置距离远者优先（static-derived；26 组扫描正常返回＋48 组优先级后缀）。
- 裁判对照：玩家第 1 场 · 棄卒 · 死守與撤離（LEVEL051）雷歐納德 HP5／15／20 时原版骑士用药 9/12、6/12、0/12，重制改后逐项相同；漆黑之森 · 遭遇戰（LEVEL547）自施 FIRE05／EARTH06 频率一致（runtime-measured）。
- 重制：`AISupportRules`（纯扫描／优先级）、`AISupportPlanning`（技能与药品意图、`_item_intent` 站位）、`_resolve_skill`／`_resolve_item_use` 共同提交；每个角色 PLAYERS 模板非空 item1..8 进 `consumables.json` 的 `initial_inventory`（static-derived 规则＋重制组合）。
- 援助链首掷：原版每次进入优先级链都在 `0x440db1..0x440dc9`（`push 0x63; call 0x458c80; inc esi`）抽一次 `rand(99)+1`，类别找不到对象跳回 `0x440db1` 再抽；重制 `AISupportPlanning.choose` 没有携带链掷骰时补抽的 `rand(99)+1` 就是这一掷，模数与 +1 一致（static-derived；runtime-measured：`enemy_turn` 回执 5 回合 55 个 NPC 行动中 `0x440db5` 256 次、均为 n=99，回跳时两次链首掷之间没有别的抽取）。
- 差异：空类别预先跳过只改抽取次数不改分布，同种子逐值不同；射程 1 用平铺四邻未走地形传播；原空格中心、全地图遍历与全局随机流未复原（provisional）。

## 证据

**static-derived**（[original_ai_support.json](original_ai_support.json)，`hsltools/probes/ai_support.py` 执行锁定 SHA 的原 EXE，无 stub）

| 原入口 | 合同 |
| --- | --- |
| `0x44c949..0x44c997` | `ai_help_otherhp`→+0x1dc，`ai_help_status`→+0x1e0 |
| `0x40c2f0` | 八格方域按登记槽序找同侧非自身目标，内部调 `0x40c110` 残血阈值；续查从上一目标之后，穷尽返回 0 |
| `0x40c3a0` | 同方域／同侧／续查，`0x40c1b0` 提供低四位状态 mask；无候选时不覆盖输出 mask |
| `0x440e3d..0x440eb5` | 位 4 成功 mode3、位 8 成功 mode4；比当前 1..99 roll，失败再抽并标记已尝试 |
| `0x43fce1..0x43fd46` | `0x40c480(self,8,0,&0x4c1cfc)` 扫同侧友军（`0x40c2d0` 取状态位，经 `0x40dcf0`／`0x40e180` 判有用），找到转 `0x440a6c`；否则以自身为目标（`[0x4c1cec]=ebp`），`0x440a79` 掷 `&1` 定魔法／绝技先后；续查 `0x440a3b` 遇自身即结束 |
| `0x440789`、`0x4407d0` | 友军回复复用类别选择器；普通类别查首件回复药后要求 range1 移动规划；全失败续查下一友军 |
| `0x440db1..0x440ef1` | 每次入口 `0x440db5` 抽 `rand(99)+1`，依次查位 2／1／4／8／16；某类别找不到对象时跳回 `0x440db1` 重抽（mode3 `0x44075b`／`0x440767`，mode4 `0x4408f8`，mode6 `0x440a3b`） |
| `0x40d530(actor,伤员,1)` | 移动力洪泛 `0x40f440`（不抹自身占位），以伤员为中心射程 1（`0x40fa80`）；3×3 伤员按身体格顺序；`0x413390` 收集「到达 ∩ 射程 ∩ 无单位」，按 `\|2dx+1\|+\|2dy+1\|` 远者优先，等键按 raw&1 交换（`0x4136ba`）；四邻都不可达则放弃该伤员 |

残血阈值：`floor(max_hp*(12+rand(18))/100)`，<10 时 `10+raw%10`，>160 时 `160+raw%16`；需缺血 ≥10 且 HP ≤ 阈值。雷歐納德 max 30 → 阈值 13..18。

**runtime-measured**（原版模拟器整镜像裁判 `hsltools/probes/_enemy_level.py`，原版全局流 (s,s)，重制 `--seed s`，比分布不比同种子）

背包：`0x44cb10` 把 PLAYERS 模板整条（含 +0x138 八槽）复制进 live，EVEF 实例物品（`0x42be2e..0x42be79`）与 pmEnemy 出生携带（`0x407c40`）再填空槽。round-1 读数：51 关 024_1／024_2 各 [241]、023 空；52 关 ally024 各 [241,241]、emperor025 [241]；3 关漢克斯 [241]；5／12 关 004 [241]、005 [241,244]、006 [241,241]、007 [241]、009 [241,241,247]、008 空。

| 局面（024 骑士动作） | 种子 | 原版 | 重制 |
| --- | --- | --- | --- |
| 51 r1，雷歐納德 5/30 在 (15,17)，024_2 从 (15,22) | 1–12 | 走到 (15,18) 用 241：9/12 | 9/12，(15,18) |
| 同上 HP 15/30 | 1–12 | 6/12 | 6/12 |
| 同上 HP 20/30 | 1–12 | 0/12 | 0/12 |
| 雷歐納德移到 (11,14)，四邻不可达 | 1–12 | 0/12 | 0/12 |
| 024_2 已在右侧 (16,17) | 1–8 | 换到 (15,18) 用药 7/8 | 7/8 |
| 024_2 已在下侧 (15,18) | 1–8 | 换到 (16,17) 用药 7/8 | 8/8 |
| 52 开场，雷歐納德 5/30 (10,35)，ally024_1 (10,38) | 1–8 | (11,35) 用药 5/8 | 5/8，(11,35) |

HP5 行原版不救的种子 1、2、4 位 4 抽到 85、96、93（>80）。第 547 关 049_1／049_3 自施 32 个混合种子：原版 3+1／3+2，重制 3+1／3+3。整回合按检查序号喂 roll 的重放在 548 s1、564 s3、532 s3、547 s2、78 s2 逐项一致。

**重制侧回执**（Godot 真实输入，夹具授予 001 水系技能与药品、`move_point=move_range=3`、100MP）：十条路线 heal_move／greater_move／life_move／cure_move／next_patient／enemy_heal／no_mp／silence／item_move／item_no_mp 全部通过（如治癒之水回复 37HP、EXP9；不可达首伤员后续查到下一人）；数据在 [runtime_observations/ally_support/receipt.json](../runtime_observations/ally_support/receipt.json)、[default_routes.json](../runtime_observations/ally_support/default_routes.json)。

## 重制接线

- `game/sim/AISupportRules.gd`、`game/sim/AISupportPlanning.gd`：provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_support.md`。
- `AISupportPlanning.choose` 的扫描按 `CoreTurnQueue.registry_layout`（`0x4c34c0` 登记表）顺序；`_select_ai_priority` 预先把空类别标为已尝试。
- 技能援助经 `AISkillPlanning.choose` 传入桶 1/2（回复）或 7（驱毒），范围收益只计缺 HP／中毒目标；移动后范围按目的地枚举。
- 药品援助：`_item_intent` 收集站位（不抽随机），类别选中后 `AINavigationRules.station_order` 抽等键硬币；`_resolve_item_use` 提交 HP 与库存；收据 `move_then_item`，到达后才显示反馈。
- 所有资格、资源、目标在 RNG 前验证，坏输入返回命名错误；无有效援助手段接续进攻或 Wait。
- 重制组合（provisional）：最大有效人数、同中心 row-major 平分、最近威胁、WRD 可达网格；Godot 先排除死亡与不可用角色。

## 复现

`python3 tools/hsl.py check ai_support`（重执行：`uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate ai_support --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`；裁判对照：`hsltools/probes/_enemy_level.py --level 51 --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json --board-key r1 --seed 3 3 --set leonard.hp=5 --brief`）。

## 边界

- 射程 1 用平铺四邻，未经 `0x40fa80` 地形传播；差别只可能在墙角。
- 大体型行动者只按锚点格算站位。
- 同种子逐值结果不同，只要求分布一致。
- 回放判定不把 `0x440db5` 的值喂给援助链首掷：预先跳过空类别后锁定掷骰（`0x441002`）携带的值与原版差一次抽取，喂入后漆黑之森 · 遭遇戰（LEVEL547）有 4 行只在持有目标上分歧（抽取结构差，分布相同）。
- `0x40d530` 移动搜索未由探针执行，落点读法由裁判实测验证。
- 自清毒与友军支援的组合位置、全局 RNG 逐值序列仍为 provisional；锁定与 wait_round 已照原版（[original_ai_navigation](original_ai_navigation.md)「结论」）。
- 完整原助攻／增益／特殊支援、驱毒药援助、所有职业成长未完成。
- 原扫描不排除 0HP 对象；重制的排除不冒称原槽生命周期。

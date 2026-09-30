# 原 AI：技能桶、使用概率、范围中心与施法站位

> evidence: static-derived; runtime-measured: LEVEL059 法术落空; resource-derived: 第一战法师法术定义与素材绑定; provisional: 有效收益计数 · status: live · functions: 0x407010, 0x40aa80, 0x40bb80, 0x40c620, 0x40c770, 0x40c9a0, 0x40cca0, 0x40d340, 0x40d4e0, 0x40dd80 · tools: hsltools/data/mage_magic.py, hsltools/probes/_spell_pick_trace.py, hsltools/probes/ai_skill.py, run_ai_skill_tests.gd · updated: 2026-09-30

## 结论

- 原版：`0x407010` 按 function 位把技能分到范围桶 3／单体桶 4（另有治疗、增益、状态、解除桶），`0x40c770` 在非空桶内 `rand(32)%count` 起步循环，逐项 `rand(100)+1 <= use_ratio` 才接受；`0x40d4e0` 决定单体／范围先后；`0x40c9a0` 选覆盖最多的范围中心，`0x40d200..0x40d2b0` 在最大覆盖施法格中取离威胁最远者（static-derived；202 组原指令执行：162 正常返回、40 距离后缀）；威胁在施法时刻由 `0x40bb80(actor, 3, 0, 8)` 按登记槽序抽出（见「移动施法的威胁对象」）。
- 原版 AI 选法术／绝技与施放中心时不估伤：伤害公式 `0x40aa80` 全 EXE 只有两个调用者，都是实际结算——`0x40b8d0`（地图打击 `0x442a90` 在 `0x442e18`／`0x4430f4` 调）与 `0x40b8f0`（逐击结算体 `0x4047e9` 在 `0x404848` 调）；`0x40dd80` 与 `0x40c9a0` 都不读伤害字段、段数或 op 72 计数。所以多段绝技（慌雨斬 5 段、無想冥殺 8 段、星辰落牙破 6 段、殘影亂斬 7 段、百裂突刺 8 段、血之宴 12 段）的段数不影响 AI 选哪招、打谁；重制 `AISkillPlanning.useful_ids` 同样只数有效目标、不估伤，与原版一致（static-derived）。
- 重制：`game/sim/AISkillDecisionRules.gd` 只算已证实的桶、顺序、逐项概率与距离比较；`game/sim/AISkillPlanning.gd` 为每个拥有的受支持技能准备独立合法站位与中心，选中后先最大化有效覆盖再用原距离末段选格，经 `_resolve_skill` 一次提交（static-derived 规则＋重制组合）。
- 法术落空已照原版：state 0xa 的 `0x40d340` flag 0 返回 0 后，`0x43ff1f` 查武器（调 `0x409090`，为 0 跳 `0x441eb8`），`0x43ff32` 掷 rand(100)，>10 跳 `0x440041` 普通进攻，≤10 才走 `0x40d8b0` 侧走。劫數 · 地劫神（LEVEL059）的对照里，同一目标、同一法术两边施放与否全同；加跑后以雷歐納德为目标的落空原版 20／75、重制 51／216，都在 `0x40c770` 的期望附近。种子 1..8 的落空次数差（原版 32、重制 11）归为抽签样本，这一点只有分布层面的支持（见「证据」runtime-measured 段）。
- 差异：原完整地图候选生成、空格中心、中心平分的随机流未复原（目标锁定见 [original_ai_navigation](original_ai_navigation.md)「结论」，辅助见 [original_ai_support](original_ai_support.md)）；有效收益计数是重制组合（provisional）；施放目标为行动者本人时的逃离分支已照原版（见「移动施法的威胁对象」），3×3 行动者的逃离泛洪沿用移动包络（provisional）。

## 证据

**static-derived**（[original_ai_skills.json](original_ai_skills.json)，`hsltools/probes/ai_skill.py` 有界执行；原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

| 地址 | 合同 | 样例 |
| --- | --- | --- |
| `0x407010` | 敌对 function 掩码 `0x501d` 分到范围桶 3／单体桶 4；治疗 1／2、增益 5、状态 6、解除 7 可重叠；节点前插 | 14 组正常返回 |
| `0x40c620` | 按 type、code 升序遍历拥有技能并前插，桶内为倒序 | 字节锚点 |
| `0x40c770` | 非空桶 `rand(32)%count` 定位，循环至多 count 个节点，`rand(100)+1 <= descriptor+0x28` 接受；空桶不取随机数；桶 5／7 语义见 [技能功能位](original_skill_function_bits.md) | 84 组正常返回（含全落空、循环、count40 合成链表） |
| `0x44db40..0x44db5d` | MAGIC parser 读 `use_ratio` 写描述符 +0x28 | 字节锚点 |
| `0x40d4e0` | `ai_magic_multi_first`=0 时样本 ≤30 返回范围优先，非零时 >30 返回范围优先 | 64 组正常返回 |
| `0x40c9a0` | 枚举施法中心，分别保留含指定目标与一般候选的最高覆盖计数 | 字节锚点 |
| `0x40cca0`（`0x40cfea` 附近） | 收集保持最大覆盖的可移动施法格 | 字节锚点，整函数未执行 |
| `0x40d200..0x40d2b0` | 选离威胁曼哈顿距离最大的格，相等时消费原随机低位并可能替换 | 40 组后缀执行 |
| `0x40d1a8`／`0x40cdd9`／`0x40d0ed` | `0x40cca0` 取威胁：`push 8, 0, 3, ebp` → `0x40bb80` | r2 反汇编 |
| `0x413930` → `0x413740` | 自施法逃离：`push 1` 走 `0x413740` 最远模式，held 初值 0（模式 0 为 `0x927c0`，`0x4137cc..0x4137d3`），同距先掷 `0x458c10()&1`（`0x41385d`），严格更远才替换（`0x413876`），再过 `0x40d800` 拥挤丢弃；候选与格心曼哈顿距离同最近模式 | r2 反汇编 |
| `0x40dd80` | SPECIAL 表孪生（use_ratio 在 +0x20），进攻桶先后与 MAGIC 共用 `0x40d4e0`；只读桶链表 `[0x4c1b78]+0x38..+0x68`、`rand(32)%count`、`rand(100)+1` 对描述符 +0x20、桶 5／7 经 `0x409870` 读 function 位（+0x28） | 见技能功能位包；r2 反汇编 |
| `0x40c9a0` 计数 | 覆盖数＝效果区网格 `0x4c1b4c` 内持有目标格计 1，其余格经 `0x411c40` 取占位字、`& 0x70000` 既非 0 也非 `0x70000` 才计 1；不读技能伤害或段数 | r2 反汇编 `0x40cad4..0x40cb3b` |
| `0x40c9a0` 尾段（flag） | flag≠0（`0x40cc20..0x40cc6e`）返回含目标组里覆盖最多的中心（`[esp+0x3c]`）；含目标最高计数为 0 返回 0，即落点失败（`0x40d494` → `0x40d3bc` 换备用桶）；该计数为 1 且 `0x40fab0(目标 x, y)` 为真时中心直接取目标本格（`0x40cc30..0x40cc54`）。flag＝0 取一般最高（`0x40cc6f..0x40cc77`）。`0x40cca0` 把第 6 参 flag 原样作为 `0x40c9a0` 第 8 参（`0x40cfb5..0x40cfda`；`0x40d340` 在 `0x40d416` push ebp），返回 0 的格不计（`0x40cfe8 je 0x40d054`），所以移动施法站位也只数含目标的中心。flag 1＝「落点必须含目标」：残血检查（`0x43f8f6`／`0x43f873`）传 1，state 0xa 传 0。重制 `AISkillPlanning.choose_for_target` 取挑中行的 `by_primary`（受影响者含该候选的落点）交 `cast_station`，最高覆盖 1 时偏好 `center_is_primary` | r2 反汇编 |
| `0x40aa80` 调用者 | 全 EXE 的 `E8／E9` rel32 与 dword 字面量扫描：只有 `0x40b8e6`（`0x40b8d0`）、`0x40b906`（`0x40b8f0`）；`0x40b8d0` 只被 `0x442e18`／`0x4430f4`（地图打击 `0x442a90`，返回值累加 `0x4c2c7c`）调，`0x40b8f0` 只被 `0x404848`（逐击结算体 `0x4047e9`）调；无数据指针 | 字节扫描＋r2 `axt` |

**runtime-measured：state 0xa 的法术落空**（`hsltools/probes/_spell_pick_trace.py`，原版裁判，batch 种子 `mixed_seed(S, 20)`，2 回合，雷歐納德 hp／max_hp 999，玩家待机；重制侧 `export_enemy_turns.gd --decisions` 的 `skill_attempts`）：劫數 · 地劫神（LEVEL059）的 actor060_1 身体中心 (40,16)、移动力 0，8 条进攻法术全在范围桶 3，单体桶 4 为空（`0x40c770` 不取随机数），桶内顺序两边同为 source_order 降序。

- 链路：`0x43feba` 调 `0x40d340(actor, 目标 [0x4c1cec], b1, b2, 0x40bab0(actor), 0)`；`0x40c770` 抽中后 `0x40e270`（move_magic_use）为 0，走原地施放：`0x4097d0` 取施法范围索引，`0x40f8b0(行动者 x, y, 范围, -1, 0)` 洪泛（索引 13 即 6 格 85 格、12 即 5 格 61 格、10 即 3 格 25 格），`0x40c9a0` flag 0 取全场最高计数，目标只是计数项之一：逐个到达格数效果区内的可计单位（目标格，或 `0x411c40` 侧位 `& 0x70000` 非 0 非 `0x70000` 的单位；`0x40cac2..0x40cb3b` 计数），`0x40cb8b` 起更新全局最高，`0x40cc6f..0x40cc77` 返回全局最佳；没有一格的效果区含可计单位即返回 0。本局面 range 3 可达区内能计的只有雷歐納德。探针在 `0x40cb3d` 读 ebx：这里是一格计数的完成点（`call 0x458410`），不是计数指令。返回 0 后 `0x40d3bc` 换桶 4（空），`0x40d340` 返回 0，`0x43ff1f` 查武器（`0x409090` 为 0 跳 `0x441eb8`），`0x43ff32` 掷 rand(100)，>10 跳 `0x440041` 普通进攻，≤10 才走 `0x40d8b0` 侧走。
- 距离按施法洪泛的菱形（曼哈顿）口径：[40,21]、[35,16] 离中心 5，[37,19] 离中心 6（切比雪夫 3）。三格上 EARTH magicCode05（range 3、效果 1Cell）与 MIND magicCode03（range 3、效果 1CellFull）的到达格里没有一格的效果区含雷歐納德，计数全为 0，每次落空；其余 6 条（range 5／6）每次施放。按（目标、法术）分组，两边施放与否无一例外相同。
- 次数：种子 1..8 × 三格，原版 93 次调用落空 32（EARTH magicCode05 21、MIND magicCode03 9、目标緹娜 2），重制 80 次落空 11（6、5、0）。分格（只算以雷歐納德为目标的调用）：

  | 格 | 原版落空 | 重制落空 |
  | --- | ---: | ---: |
  | [40,21] | 11／31 | 3／26 |
  | [37,19] | 8／29 | 5／28 |
  | [35,16] | 11／31 | 3／26 |

  [40,21] 与 [35,16] 相对中心互为镜像，同一种子的抽签序列逐次相同；[37,19] 前一两动相同，之后常因 `0x40c9a0` 的平局抽签（`0x40cb54` 含目标最佳、`0x40cb99` 全局最佳）分叉：它在曼哈顿 6，range 5／6 法术打平的中心数与另两格不同，取随机数的次数随之不同。有效独立样本约 8～16。`0x40c770` 在这一桶的落空期望为 27.4%（均匀抽签精确值；`0x458c10` 模型 20 万个随机状态 26.9%）。原版加跑 [40,21] 种子 9..32，以雷歐納德为目标 75 次落空 20（26.7%）；重制 [40,21] 种子 1..64，216 次落空 51（23.6%）。两边都在期望附近。「无规则差」的结论不靠样本数，靠两点：同一（目标、法术）两边结果全同；加跑分布原版 20／75 对重制 51／216。种子 1..8 的 32 对 11 归为抽签样本，只有分布层面的支持：以雷歐納德为目标的落空率重制 14%（11／80）、原版 33%（30／91），按有效样本计两侧直接比不显著。逐次对齐可用 `hsltools/probes/enemy_turn.py` 的原版抽签回放逐次喂 `AISkillDecisionRules.select_index`，未做。重制诊断的 AI 源是 Godot `RandomNumberGenerator`，与原版抽签流不逐次对齐，只比分布。
- 目标緹娜：原版 [40,21] 32 个种子中有 5 个（另有 [35,16] 种子 5），地劫神第 2 回合第 1 动打倒雷歐納德后仍跑第 2 动，`0x40d340` 以緹娜（[36,26]，离中心曼哈顿 14）为目标，全部落空；重制在雷歐納德倒下时 `BattleOutcome.decided` 成立，没有第 2 动。这属于判负时机，不在法术分支，见差异清单 `boss-twice-action-after-lead-down`。

**resource-derived**：
- `use_ratio`：幻火、风刃、酸蚀幻雾 90，封魔灭杀 86；技能书经 TYPE.H 与 code 位值保存 `source_order`。固定起始选择 0 时 026 单体桶先试幻火再试风刃。
- 第一战帝国法师（PLAYERS 026）：magic_fire=幻火、magic_wind=風刃、ai_att_magic=95。MAGIC.TXT FIRE/AIR 的 magicCode01 指向 RESOURCE 169/162，均耗 8 MP、range3CellCircle、影响 range0Cell、命中 96%，伤害字段 18–32／12–26；原始 magic_point=5 是基础字段。`effects.txt` effCode16 = AirWave1/2＋AirBlade1/2，effCode23 = FlyDrop＋FireBomb＋FireBomb2；`global.obs` 绑定 SHP 序列与 WIND0002、WIND0001、BOMB0004。`hsltools/data/mage_magic.py` 导入 24 张源图与 3 个 WAV 并校验摘要。

**重制侧回执**（Godot 640×480，真实 Wait 输入，正常时钟；夹具设位置、HP400、倾向 100、指定技能 use_ratio 100，不代表第一战自然遇敌）：

| 路线 | 施法移动 | MP | 结果 |
| --- | --- | --- | --- |
| 026 幻火 | (7,7)→(6,8) | 30→22 | 单体伤害，完成后交接 |
| 026 风刃 | (7,7)→(7,9) | 30→22 | 单体伤害，完成后交接 |
| 025 酸蚀幻雾 | (8,10)→(7,10) | 100→90 | 改选中间单位为中心，原目标仍覆盖，三目标各有状态结果，一次付费 |

默认数值第一战 advance 路线：`victory_escape`、第 7 回合、209.606 秒，Leonard 剩余 HP21。数据在 [runtime_observations/ai_skills/receipt.json](../runtime_observations/ai_skills/receipt.json)。

## 移动施法的威胁对象

`0x40cca0` 只有两个调用者：`0x40d41c`（`0x40d340`，法术）与 `0x40e03d`（`0x40df70` 在 `0x40e030` push 1，绝技；不查 move_magic_use）。两支取威胁都是 `0x40bb80(actor, 3, 0, 8)`（static-derived，r2）：

- 参数：find_type 3（最近，分数 32×曼哈顿）、find_flag 0（不走优选职业）、半径＝arg4×32（`0x40bb95`），平方欧氏距离含边界；find_no_id 读行动者自己的 +0x1bc（`0x40bbf3`，`0x40bd88..0x40bd9a` 与 `0x44fa80` 的 SID 比较），near range 读 +0x12c（move_point×32，`0x40bbe6`）。
- 扫描：对象表 `0x4c34c0` 从 0 号槽起（`0x40bbfa`），跳过空槽、自身、+0x80 的 `0x8000000` 位与阵营字相交者（`0x40bc3c`）；严格更近时先改最小值，已有候选再掷 `0x458c10()&1`（`0x40bd4f`），掷中保留旧的。守卫半径 ai_fixed 不在此函数内。
- 时机：一般分支收集完站位后，按最高覆盖数 `[0x4c1a00]`（`0x40cff8` 写入）分三路：为 0 时 `0x40d0d2` 直接跳 `0x40d31b`，不扫；为 1 且施放目标是行动者本人时进逃离分支 `0x40d0ed`（`0x40d0f3` 扫描后走 `0x413930`，见「边界」）；其余情形在 `0x40d1a8` 扫描（只有 1 个候选也照掷）。本人分支更早：`0x40cdab` 施放目标就是行动者、且技能记录 +0xc（效果范围序号，`0x4097f0`／`0x409810`；RANGE.H 的 range0Cell 为 0）为 0 时，`0x40cdd9` 不收集站位，`0x40cddf` 取威胁后同样走 `0x413930`。候选数 `[0x4c1a60]`（`0x40d036` 写回）只在扫描之后起作用：无威胁且候选多于 1（`0x40d1be`）→ `0x40d1c8` `rand(count)`；有威胁且候选多于 1（`0x40d1ec`）→ `0x40d200..0x40d2b0` 取最远者。
- 逃离（`0x40cdf0..0x40ce63`、`0x40d104..0x40d173`）：`0x40ba20` 取阵营字，`0x413930(threat+4, threat+8, side, &x, &y)` 在 `0x40f440` 移动泛洪里取离威胁最远的可停格（`0x413740` 模式 1，见上表），`0x410a50` 从行动者走到该格，返回该格后对自己施放；无威胁、无格或走不到时，range0Cell 分支经 `0x40ce64`、覆盖 1 分支经 `0x40d174`，都到 `0x40d17e`，返回行动者自身位置，原地施放——`0x40d340` 这时仍返回 2（空路径的先移后施，`+0x94`＝0x18），落点照原地，这一步多出的节拍未核（provisional）。覆盖 ≥2 的移动自施不逃，照一般分支挪位。原版三处把施放目标设成本人：自愈状态 `0x140000`、状态 `0xd0000`（`0x43fad6..0x43fb0c`）、增益援助找不到友军时退回自身（`0x43fce1..0x43fd46`）。
- `0x413930` 与 `0x40d200..0x40d2b0` 不是同一段：后者只在一般分支已收集的最高覆盖站位里取离威胁最远者（候选是能施放的站位）；前者不看覆盖，在整张移动泛洪的可停格里取最远者，并带 `0x40d800` 拥挤丢弃。重制分别是 `AISkillDecisionRules.farthest_index` 与 `AINavigationRules.farthest_stoppable`；后者与最近模式 `nearest_stoppable`（`0x413740` 模式 0）共用同一扫描、拥挤规则与随机数消耗顺序。
- 重制：`AISkillPlanning.threat_scan` 在规划时记下行动者移动前盘面的活对象行与 `CoreTurnQueue.registry_layout`（与进攻目标扫描同一份），`AISkillPlanning.threat` 在站位收集之后调 `AIDecisionRules.select_registered_target`；`choose`（援助施法）、`choose_for_target`（濒死路径）与 `_cast_search`（state 0xa）共用，绝技通道也走它；法术无 move_magic_use 不进 `0x40cca0`，不扫。自施法的两条逃离在 `AISkillPlanning.cast_station`（`choose` 选中行之后的站位段）：计划带 `flee`（`AINavigationRules.flee_field` 与行动者拥有的 range0Cell 技能）即目标是本人，range0Cell 行先逃，其余行在最高覆盖为 1 时逃，`AINavigationRules.flee` 取格与路径；`AISelfPreservation` 的自疗／自解毒与增益援助退回自身的计划都挂同一逃离场。自疗行的站位意图借 `AISupportPlanning` 的援助意图收集、只以行动者本人为受益者（重制组合）。

## 重制接线

- `game/sim/AISkillDecisionRules.gd`、`game/sim/AISkillPlanning.gd`：provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_skills.md`。
- `AISkillPlanning.prepare` 产出 `skill_id / primary_target_id / target_id / destination / path / affected_ids / useful_ids`；primary 是原目标，target 是施法中心，primary 必须仍在效果内。
- 所有源参数、技能定义、目标在任何 RNG、移动、扣费、呼叫前验证；概率全落空是正常结果，沿类别顺序继续；坏概率或缺 `source_order` 返回 `scenario_error`，状态不变。
- 纯毒：免疫或已达上限的目标不计分，整个范围无效时不投概率、不付款。
- 技能书加入 `source_order` 改变 BattleCheckpoint 配置指纹，旧存档在恢复入口被拒绝。
- 法术的地图演出由 `SkillEffectScriptPlayer` 回放原生效果脚本（[original_effect_motion](original_effect_motion.md)「结论」）；AI 在付得起的技能间按上述桶与逐项概率选。
- 相邻目标状态文字按实际字体测量错开高度（重制可读性选择）。

## 复现

`python3 tools/hsl.py check ai_skill`（重执行：`uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate ai_skill --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`）。

## 边界

- 原完整地图候选生成、空格中心、中心平分两条随机流未复制；重制中心必须是活敌人，候选按行／列排序。
- 自施法逃离的泛洪：1×1 行动者照 `0x40f440` 原生泛洪取候选（自身登记格跳过）；3×3 行动者沿用移动包络的可达格（provisional，与接近目标点同一处理）。逃离取格在移动前的盘面上读，与 `0x413930` 调用时刻一致。
- 原候选上限、对象生命周期、owner+0x12c 初始化、完整特殊技能选择与全局 RNG 逐值序列未复原；目标锁定与 wait_round 见 original_ai_navigation。
- 本包只证桶识别；治疗／增益的 AI 用法见 [original_ai_support](original_ai_support.md) 与 [original_support_magic](original_support_magic.md)。
- 原版幻火是单体法术；最终原伤害公式不由本包证明。AI 选法术／绝技不估伤只证到上述选择链（`0x40c570`／`0x40c620`／`0x40d4e0`／`0x40d340`／`0x40df70`／`0x40dd80`／`0x40cca0`／`0x40c9a0`）与 `0x40aa80` 的调用者；普通攻击的目标选取见 original_ai_navigation。
- 多段绝技的 AI 持有者（初始声明）：048 慌雨斬——巴瀚納海峽 · 遭遇戰（LEVEL538）敌方 9 名、巴瀚納海峽（LEVEL012）敌方与友军各 1 名；054 殘影亂斬——自覺與宿命・塔克斯（LEVEL075）、哈莫特沙漠（LEVEL024）、哈莫特沙漠・魔騎士團（LEVEL903）敌方；059 無想冥殺——破滅的命運・席德爾（LEVEL077）敌方。职业 80–84／88／89／92／93／98／99 的学习表另含这些绝技，出生推级学到的持有者未逐场列举；因原版不估伤，持有与否不改变 AI 的估算口径。

# 原 AI：技能桶、使用概率、范围中心与施法站位

> evidence: static-derived; resource-derived: 第一战法师法术定义与素材绑定; provisional: 有效收益计数 · status: live · functions: 0x407010, 0x40aa80, 0x40bb80, 0x40c620, 0x40c770, 0x40c9a0, 0x40cca0, 0x40d4e0, 0x40dd80 · tools: hsltools/data/mage_magic.py, hsltools/probes/ai_skill.py, run_ai_skill_tests.gd · updated: 2026-09-29

## 结论

- 原版：`0x407010` 按 function 位把技能分到范围桶 3／单体桶 4（另有治疗、增益、状态、解除桶），`0x40c770` 在非空桶内 `rand(32)%count` 起步循环，逐项 `rand(100)+1 <= use_ratio` 才接受；`0x40d4e0` 决定单体／范围先后；`0x40c9a0` 选覆盖最多的范围中心，`0x40d200..0x40d2b0` 在最大覆盖施法格中取离威胁最远者（static-derived；202 组原指令执行：162 正常返回、40 距离后缀）；威胁在施法时刻由 `0x40bb80(actor, 3, 0, 8)` 按登记槽序抽出（见「移动施法的威胁对象」）。
- 原版 AI 选法术／绝技与施放中心时不估伤：伤害公式 `0x40aa80` 全 EXE 只有两个调用者，都是实际结算——`0x40b8d0`（地图打击 `0x442a90` 在 `0x442e18`／`0x4430f4` 调）与 `0x40b8f0`（逐击结算体 `0x4047e9` 在 `0x404848` 调）；`0x40dd80` 与 `0x40c9a0` 都不读伤害字段、段数或 op 72 计数。所以多段绝技（慌雨斬 5 段、無想冥殺 8 段、星辰落牙破 6 段、殘影亂斬 7 段、百裂突刺 8 段、血之宴 12 段）的段数不影响 AI 选哪招、打谁；重制 `AISkillPlanning.useful_ids` 同样只数有效目标、不估伤，与原版一致（static-derived）。
- 重制：`game/sim/AISkillDecisionRules.gd` 只算已证实的桶、顺序、逐项概率与距离比较；`game/sim/AISkillPlanning.gd` 为每个拥有的受支持技能准备独立合法站位与中心，选中后先最大化有效覆盖再用原距离末段选格，经 `_resolve_skill` 一次提交（static-derived 规则＋重制组合）。
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
| `0x40aa80` 调用者 | 全 EXE 的 `E8／E9` rel32 与 dword 字面量扫描：只有 `0x40b8e6`（`0x40b8d0`）、`0x40b906`（`0x40b8f0`）；`0x40b8d0` 只被 `0x442e18`／`0x4430f4`（地图打击 `0x442a90`，返回值累加 `0x4c2c7c`）调，`0x40b8f0` 只被 `0x404848`（逐击结算体 `0x4047e9`）调；无数据指针 | 字节扫描＋r2 `axt` |

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
- 重制：`AISkillPlanning.threat_scan` 在规划时记下行动者移动前盘面的活对象行与 `CoreTurnQueue.registry_layout`（与进攻目标扫描同一份），`AISkillPlanning.threat` 在站位收集之后调 `AIDecisionRules.select_registered_target`；`choose`（濒死路径、援助施法）与 `_cast_search`（state 0xa）共用，绝技通道也走它；法术无 move_magic_use 不进 `0x40cca0`，不扫。自施法的两条逃离在 `AISkillPlanning.cast_station`（`choose` 选中行之后的站位段）：计划带 `flee`（`AINavigationRules.flee_field` 与行动者拥有的 range0Cell 技能）即目标是本人，range0Cell 行先逃，其余行在最高覆盖为 1 时逃，`AINavigationRules.flee` 取格与路径；`AISelfPreservation` 的自疗／自解毒与增益援助退回自身的计划都挂同一逃离场。自疗行的站位意图借 `AISupportPlanning` 的援助意图收集、只以行动者本人为受益者（重制组合）。

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

# 原 AI：技能桶、使用概率、范围中心与施法站位

> evidence: static-derived; resource-derived: 第一战法师法术定义与素材绑定; provisional: 威胁选取与有效收益计数 · status: live · functions: 0x407010, 0x40c620, 0x40c770, 0x40c9a0, 0x40cca0, 0x40d4e0, 0x40dd80 · tools: hsltools/data/mage_magic.py, hsltools/probes/ai_skill.py, run_ai_skill_tests.gd · updated: 2026-09-28

## 结论

- 原版：`0x407010` 按 function 位把技能分到范围桶 3／单体桶 4（另有治疗、增益、状态、解除桶），`0x40c770` 在非空桶内 `rand(32)%count` 起步循环，逐项 `rand(100)+1 <= use_ratio` 才接受；`0x40d4e0` 决定单体／范围先后；`0x40c9a0` 选覆盖最多的范围中心，`0x40d200..0x40d2b0` 在最大覆盖施法格中取离威胁最远者（static-derived；202 组原指令执行：162 正常返回、40 距离后缀）。
- 重制：`game/sim/AISkillDecisionRules.gd` 只算已证实的桶、顺序、逐项概率与距离比较；`game/sim/AISkillPlanning.gd` 为每个拥有的受支持技能准备独立合法站位与中心，选中后先最大化有效覆盖再用原距离末段选格，经 `_resolve_skill` 一次提交（static-derived 规则＋重制组合）。
- 差异：原完整地图候选生成、空格中心、中心平分的随机流未复原（目标锁定见 [original_ai_navigation](original_ai_navigation.md)「结论」，辅助见 [original_ai_support](original_ai_support.md)）；威胁选取与有效收益计数是重制组合（provisional）。

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
| `0x40dd80` | SPECIAL 表孪生（use_ratio 在 +0x20），进攻桶先后与 MAGIC 共用 `0x40d4e0` | 见技能功能位包 |

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
- 威胁取八格圆内最近活敌人，同距按行／列；原最近目标 helper 的改选随机流未接。
- 原候选上限、对象生命周期、owner+0x12c 初始化、完整特殊技能选择与全局 RNG 逐值序列未复原；目标锁定与 wait_round 见 original_ai_navigation。
- 本包只证桶识别；治疗／增益的 AI 用法见 [original_ai_support](original_ai_support.md) 与 [original_support_magic](original_support_magic.md)。
- 原版幻火是单体法术；最终原伤害公式与 AI 法术评分不由本包证明。

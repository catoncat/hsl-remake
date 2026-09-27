# 回复、驱毒与自保施法

> evidence: static-derived; provisional: AI 自救组合顺序与粒子／时钟 · status: live · functions: 0x40a7b0, 0x40aa80, 0x40c570 · tools: hsltools/data/skill_book.py, hsltools/data/skill_targeting.py, hsltools/data/support_magic.py, hsltools/probes/support.py, run_support_magic_tests.gd · updated: 2026-09-27

## 结论

- 原版水系回复（治癒之水／生命之水／女神之淚）经 `0x40a7b0` proc1 取三角值、跳过元素抗性，只补 `min(缺失HP, 数值)`；驱毒清整个 packed 毒字与毒 flag、保留禁魔与 HP、零 RNG；贡献分别为实际回复÷2 与 (毒回合+1)×12（static-derived）。
- 重制 `game/sim/SupportMagicRules.gd`（提案）经 `SkillResolutionRules` 一次提交，数值由 `game/sim/NativeMagicRollRules.gd` 按原 RNG 顺序计算；AI 自保由 `game/sim/AISelfPreservation.gd` 复用原选择内核（static-derived）。
- 一致：18／18 数值返回与 24／24 应用前段逐字段相等。已知差异：满 HP／无效目标主动拒绝与「+／−」字形是重制取舍；AI 自救优先级连接、粒子与时钟为 provisional。

## 证据

**resource-derived**（MAGIC.TXT、TYPE.H、RANGE.TXT、PLAYERS.TXT、RESOURCE）

| WATER code | 名称／费用 | 源 function | 选取范围／效果范围 |
| --- | --- | --- | --- |
| 05 | 驅毒／4MP | CurePoison，0x400 | range3CellCircle／range1Cell |
| 06 | 治癒之水／6MP | Heal，2 | range3CellCircle／range0Cell |
| 07 | 生命之水／16MP | Heal，2 | range4CellCircle／range0Cell |
| 08 | 女神之淚／28MP | Heal，2 | range5CellCircle／range0Cell |

范围取源矩阵中大于 0 的格；治疗单目标，驱毒十字覆盖中心周边存活友军。拥有权按 PLAYERS：正式第一战 001／025／026 不获治疗术；027 的 WATER06 为原声明。原资源：eff12–15 程序、OBJ 定义、20 个去重 SHP 帧、6 个 WAV（SHOOT005、MHEAL003／006／007／008、LASERUP003），哈希见 [support_magic/manifest.json](../../../content/imported/hsl/chapter01/support_magic/manifest.json)。

**static-derived**（固定 EXE SHA-256；[original_support_magic.json](original_support_magic.json)；无 stub、无原 UI 调用）

| 入口／终点 | 覆盖 | 边界 |
| --- | --- | --- |
| `0x40a7b0` 数值 helper，正常返回 | 18 组：3 种子 × 3 种等级／精神／魔击力 × 抗性 0／80 | 数值、hit_bonus、每次 RNG 界限与顺序 |
| `0x40aa80` 进入，停在 `0x40ac04` 前 | 12 组回复（含 `0x40abb0` 回复分支） | 停在显示回调前，不是整法术返回 |
| `0x40aa80` 进入，停在 `0x40b831` 前 | 12 组驱毒（含 `0x40b3a6` 清毒分支） | 不执行共同回调 |

### 逐项对照：18 组数值返回与 24 组应用前段 vs 重制规则

`tests/run_support_magic_tests.gd native_cases` 把回执每行喂给 `NativeMagicRollRules.roll` 与 `SupportMagicRules.prepare／resolve` 并回放 `draws`；`python3 tools/hsl.py check support` 用独立 Python 模型核对同一回执（两者都不重跑原 EXE）。

数值 helper：输入 low 24／high 36／hit_ratio 100／hit_bonus 7；抗性 0 与 80 两列返回相同（proc1 跳过抗性由原返回得到）。

| # | seed | level／mind／魔击力 | draws (bound:value) | 原返回 | hit_bonus_after | 重制 |
| --- | --- | --- | --- | --- | --- | --- |
| 1／2 | 1 | 1／10／24 | 100:58 7:0 7:5 | 9 | 0 | = |
| 3／4 | 1 | 80／36／80 | 100:58 7:0 7:5 | 106 | 0 | = |
| 5／6 | 1 | 100／50／110 | 100:58 7:0 7:5 | 149 | 0 | = |
| 7／8 | 7 | 1／10／24 | 100:77 7:4 7:4 | 8 | 0 | = |
| 9／10 | 7 | 80／36／80 | 100:77 7:4 7:4 | 102 | 0 | = |
| 11／12 | 7 | 100／50／110 | 100:77 7:4 7:4 | 144 | 0 | = |
| 13／14 | 101 | 1／10／24 | 100:96 7:4 7:1 | 7 | 0 | = |
| 15／16 | 101 | 80／36／80 | 100:96 7:4 7:1 | 100 | 0 | = |
| 17／18 | 101 | 100／50／110 | 100:96 7:4 7:1 | 140 | 0 | = |

```text
half = (36-24)/2 = 6;  sampled = 24 + 6 - rand(7) + rand(7)
mind' = mind/2 (mind<36)  或  (mind-36)/4 + 18
value = (clamp(level,1,80) + mind' + sampled) * 魔击力 / 100;  value<3 时补到 3..5
命中 roll ≤ 107 即命中，hit_bonus 清 0
例：level 100 → 80，mind 50 → 21，sampled 30-0+5 = 35 → (80+21+35)*110/100 = 149
```

应用前段：

| # | kind（seed，Lv） | 输入 HP／毒字／禁魔 | 原 HP | 原毒字 | 原禁魔 | flags | contribution | 停止点 | 重制 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1–3 | heal（1，1） | 1／95／100，0x90003，2 | 10／100／100 | 0x90003 | 2 | 3 | 4／2／0 | 0x40ac04 | = |
| 4–6 | heal（1，100） | 同上 | 100／100／100 | 0x90003 | 2 | 3 | 49／2／0 | 0x40ac04 | = |
| 7–9 | heal（101，1） | 同上 | 8／100／100 | 0x90003 | 2 | 3 | 3／2／0 | 0x40ac04 | = |
| 10–12 | heal（101，100） | 同上 | 100／100／100 | 0x90003 | 2 | 3 | 49／2／0 | 0x40ac04 | = |
| 13／14 | cure（1，1） | 1，0，0／2 | 1 | 0 | 0／2 | 0／2 | 0 | 0x40b831 | = |
| 15／16 | cure（1，1） | 1，0x50001，0／2 | 1 | 0 | 0／2 | 0／2 | 24 | 0x40b831 | = |
| 17／18 | cure（1，1） | 1，0x320009，0／2 | 1 | 0 | 0／2 | 0／2 | 120 | 0x40b831 | = |
| 19–24 | cure（1，1） | HP 100，其余同 13–18 | 100 | 同上 | 同上 | 同上 | 0／24／120 | 0x40b831 | = |

| 结论项 | 等级 | 依据 |
| --- | --- | --- |
| WATER05–08 实际缺失 HP 回复量 | static-derived | 18＋12 组逐字段相等 |
| 清毒字同时保留禁魔 | static-derived | 12 组驱毒 |
| 多目标只扣一次 MP | static-derived（读法） | `0x442bc1..0x442bce` 施法时扣一次（[技能资源](original_skill_resources.md)），`0x40aa80` 逐目标循环不读 MP |
| 最终经验 | static-derived | 贡献→经验见 [original_experience.md](original_experience.md)；本包只证 contribution |
| 结果数字显示 | static-derived | `0x4084e0`→`0x408580`：绿 NUM2xx 回复、蓝 NUM3xx MP、红 NUM1xx 伤害，无「+／−」字形（[技能功能位](original_skill_function_bits.md)） |

## 重制接线

- `tools/hsltools/data/skill_book.py` 登记能力（登记不授予）；`tools/hsltools/data/skill_targeting.py` 从完整注册表收集 RANGE。
- `game/sim/SupportMagicRules.gd`：HP／状态／数值提案；`game/sim/SkillResolutionRules.gd` 在 RNG 前验证拥有权、MP、禁魔、目标与状态，一次提交施法者扣款与去重目标变化；自身为目标时回复不覆盖 MP 扣款；正向法术不附送气力、不走反击。
- `game/sim/AISelfPreservation.gd`：当前格、自身中心的受支持技能；自救 HP 门槛后复用进攻类别 helper、回复桶 1/2、单体／范围优先与 use_ratio；无 MP／禁魔／未选中时接用药；满 HP 仍中毒时桶 7 驱毒在残血敌方检查后、普通进攻前（provisional）。
- `game/sim/StatusCatalog.gd`：毒字与禁魔状态目录。
- `tools/hsltools/data/support_magic.py` 从原 PAK 提取帧（逐帧 draw_origin）与声音（XOR-A8）；表现层只读收据与投影坐标，release／impact 各一次，完成门槛覆盖最后一批粒子淡出。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_support_magic.md`。

## 复现

`python3 tools/hsl.py check support`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [support_magic](../runtime_observations/support_magic/receipt.json) | 治癒之水→自己，先取消后确认、治癒之水→友军，先取消后确认、生命之水→友军、滚轮找到女神之淚→友军、驅毒→相邻友军，覆盖自己、Wait→残血AI自身治疗、Wait→满血中毒AI自身驱毒、Wait→无MP的残血AI | `run_support_magic_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- `0x40ac04`／`0x40b831` 之后的显示回调与共同尾部未执行。
- 原全局 RNG 顺序与完整辅助 dispatcher（`0x43f5f0` 支援分支及其 `0x40c570`／移动搜索）未追踪；帮助其他友军见 [original_ai_support.md](original_ai_support.md)。
- 满 HP／无效目标拒绝是重制交互取舍（原前段仍取值）；「+／−」字形是重制表现选择。
- 粒子散布、轨迹、加色、持续时间与 tick→秒映射为 provisional，替换需四种法术的连续原帧与音轨。
- 复活与其他增益不在本包。

# 回复、驱毒与自保施法

> evidence: static-derived; provisional: AI 自救组合顺序与粒子／时钟 · status: live · functions: 0x40a7b0, 0x40aa80, 0x40c570 · tools: hsltools/data/skill_book.py, hsltools/data/skill_targeting.py, hsltools/data/support_magic.py, hsltools/probes/support.py, run_support_magic_tests.gd · updated: 2026-09-24

2026-09-16。本批把正向法术接入现有选目标、共同技能事务、AI自保和地图表现。原程序结果、源资源、重制组合和实际输入验收分别说明；不声称恢复完整辅助AI或原法术引擎。

## 本次系统对照及选择依据

基线是当前 [PROJECT](../../PROJECT.md)、[机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md)、已接入的 [AI技能与站位](original_ai_skills.md)、[气力循环](original_stamina.md)，以及 [原录像V01–V10](../runtime_observations/original_gameplay_reference/README.md)。录像用于外观／局部过程，不由单次伤害数字推出规则；该录像没有提供本批四种水系法术的完整受控过程。

| 体验维度 | 已有实现和证据 | 本批对照结论 |
| --- | --- | --- |
| 核心循环 | 原行动出口、先后队列、受击积气／绝技、物品恢复已接入 | 法术事务只有伤害和负面状态，源水系回复／驱毒不能完成，优先补齐同一循环的自救分支 |
| 操作手感 | 原菜单布局／开合、同坐标选格、取消、移动回退 | 正向法术需要选自身和友军；取消不能付款，后继回合仍应能查看刚回复过的队友 |
| 战斗节奏 | 完整特写、地图法术、死亡／经验与一次交接；默认第一战已跑通第9回合撤离 | 回复／解毒需要完整可读演出后交接；不通过调低敌方HP或放宽默认授予改变已证明的战斗 |
| 敌人与交互 | 自救门槛、用药、残血进攻、源魔法桶与概率 | 回复桶1/2和解状态桶7尚无可执行正向效果；接入已拥有、可支付的自身技能，保留用药退路 |
| 数值反馈 | 普通气力原函数；状态魔法原数值helper；原三种伤害及EXP仍有重制边界 | 回复调用proc1，跳过抗性并截到实际缺失HP；解毒必须清除整个毒字而保留禁魔；显示实际+HP／解毒 |
| 镜头 | 幻火源声明为地图法术；坐标／脚点／镜头是统一合同 | 水系四技能也声明eff_proc_Local，沿同一地图坐标投影，不新增双人战斗场景 |
| 动画与音效 | 原SHP／OBJ／脚本及独立声音资源可提取 | 把对应水环、绿色星光、聚集／扩散和脚本声音一起接入；粒子位置与时钟仍为重制编排 |
| UI | 源窗体、魔法可滚动列表、只读状态栏 | 列表按原MP费用显示四种能力，滚动可选最后一项；目标栏区分回复／驱毒，范围反馈按字体宽度避让 |

这是一条从源能力、目标资格、一次提交到可见回馈的连续改进。已完成的开场、对白、物品、奖励／存档和普通特写不因接续而重做。后续顺序只在 [PROJECT Next steps](../../PROJECT.md#next-steps) 维护。

## 原字段与拥有权

源来自tracked MAGIC.TXT、TYPE.H、RANGE.TXT、PLAYERS.TXT和RESOURCE。工具`hsltools/data/skill_book.py`登记能力，`hsltools/data/skill_targeting.py`从完整注册表收集所需RANGE，避免高级能力因手写范围名单漏项而不可选择。

| WATER code | 名称／费用 | 源function | 选取范围／效果范围 |
| --- | --- | --- | --- |
| 05 | 驅毒／4MP | CurePoison，0x400 | range3CellCircle／range1Cell |
| 06 | 治癒之水／6MP | Heal，2 | range3CellCircle／range0Cell |
| 07 | 生命之水／16MP | Heal，2 | range4CellCircle／range0Cell |
| 08 | 女神之淚／28MP | Heal，2 | range5CellCircle／range0Cell |

使用源矩阵中大于0的格子，不从“圆形”名字猜半径。治疗是单目标；驱毒的十字范围会覆盖中心周边的存活友军。原模式3的支持分类沿用 [技能目标证据](original_skill_targets.md)；当前敌我适配和稳定roster访问次序仍是显式重制组合。

登记不授予：正式第一战的001／025／026仍保留自身原声明，不会突然获得治疗术。源027的WATER06原声明现在对应可执行能力。实际输入夹具为001／026明确授予技能，仅验证公共系统；PLAYERS与原包的既有字节差异没有被放宽或宣布解决。

## 原指令执行

工具 [hsltools/probes/support.py](../../../tools/hsltools/probes/support.py)复用固定EXE SHA-256的PE映像与原随机helper。记录 [original_support_magic.json](original_support_magic.json)；没有替换原返回值、注入函数stub或调用原游戏UI。

| 入口／终点 | 新执行覆盖 | 证据边界 |
| --- | --- | --- |
| 0x40a7b0数值helper，正常返回 | 18组：3个种子×3种等级／精神／魔击力×0/80抗性 | 原指令完整返回，数值、hit_bonus与每次RNG界限／顺序分别和独立模型对照 |
| 0x40aa80进入，0x40ac04之前停止 | 12组回复：1/95/100HP、低／高数值、毒与禁魔同时存在 | 包含0x40abb0回复分支、HP封顶和原贡献值；停止在显示回调前，不是整法术正常返回 |
| 0x40aa80进入，0x40b831之前停止 | 12组驱毒：正常／两种毒字×有无禁魔×1/100HP | 包含0x40b3a6清毒分支，整个毒字与flag清零，禁魔和HP保留，零RNG；不执行共同回调 |

原回复数值先按原命中helper，再用区间中点减一次随机值、加一次随机值得到三角取值；等级夹到1..80、精神分段折算，与魔击力百分比计算。proc1保留该取值和最低值处理，但跳过元素抗性乘算；目标最终只增加`min(缺失HP, 数值)`。满HP的原应用前段仍会执行取值，本产品主动拒绝全无效果目标／区域，属于交互取舍。

驱毒清掉整个packed poison word，不仅是低16位回合数；同时清除毒flag，保留no_magic。原前段贡献字段在回复时为实际回复量整数除2，驱毒时为原毒回合数加1再乘12。SR-047只记录`native_contribution`而未发经验；后续SR-048已沿[原最终EXP](original_experience.md)完成每目标换算、整次汇总入账和成长。贡献仍不直接等于最终经验。

`--execute`实际运行原字节；普通checker仅核对已保存结果和独立模型，不能称为又一次原程序运行：

```sh
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate support --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
python3 tools/hsl.py check support
```

## 逐项对照：18 组数值返回与 24 组应用前段 vs 重制规则（2026-09-24，lane R25）

矩阵此前只写「18数值返回＋24应用前段」，没有说清重制哪些数值已对上原返回值。对照口径：`tests/run_support_magic_tests.gd native_cases` 把 tracked 回执 [original_support_magic.json](original_support_magic.json) 的每一行原样喂给 `NativeMagicRollRules.roll`（数值）与 `SupportMagicRules.prepare／resolve`（应用），并按原 RNG 调用顺序回放 `draws`；`python3 tools/hsl.py check support` 另用独立 Python 模型核对同一回执。两者都不重跑原 EXE。**结论：18／18 数值与 24／24 应用前段全部逐字段相等**（`SUPPORT_MAGIC_TESTS_PASS checks=297`、`SUPPORT_NATIVE_PASS rolls=18 application_prefixes=24`）。

### 数值 helper `0x40a7b0`（proc1，正常返回）

输入固定 low 24／high 36／hit_ratio 100／hit_bonus 7；三种施法者 (level, mind, 魔击力) × 抗性 0／80 × 三个种子。抗性两列返回值相同，即 proc1 跳过元素抗性乘算（这一点由原返回而非推断得到）。

| # | seed | level／mind／魔击力 | 抗性 | draws (bound:value) | 原返回 value | hit_bonus_after | 重制 `NativeMagicRollRules.roll` |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1／2 | 1 | 1／10／24 | 0／80 | 100:58 7:0 7:5 | 9 | 0 | = |
| 3／4 | 1 | 80／36／80 | 0／80 | 100:58 7:0 7:5 | 106 | 0 | = |
| 5／6 | 1 | 100／50／110 | 0／80 | 100:58 7:0 7:5 | 149 | 0 | = |
| 7／8 | 7 | 1／10／24 | 0／80 | 100:77 7:4 7:4 | 8 | 0 | = |
| 9／10 | 7 | 80／36／80 | 0／80 | 100:77 7:4 7:4 | 102 | 0 | = |
| 11／12 | 7 | 100／50／110 | 0／80 | 100:77 7:4 7:4 | 144 | 0 | = |
| 13／14 | 101 | 1／10／24 | 0／80 | 100:96 7:4 7:1 | 7 | 0 | = |
| 15／16 | 101 | 80／36／80 | 0／80 | 100:96 7:4 7:1 | 100 | 0 | = |
| 17／18 | 101 | 100／50／110 | 0／80 | 100:96 7:4 7:1 | 140 | 0 | = |

公式（与三组返回一致，`hsltools/probes/status_roll.py independent`）：`half=(36−24)/2=6`；`sampled = 24+6 − rand(7) + rand(7)`；`mind' = mind/2 (mind<36) 或 (mind−36)/4+18`；`value = (clamp(level,1,80) + mind' + sampled) × 魔击力 / 100`；`value<3` 时补到 3..5；命中 roll 100:58／77／96 均 ≤ 107 即命中，hit_bonus 清 0。level 100 行落到 80 上限（149 = (80+21+35)×110/100 取整：mind 50 → (50−36)/4+18 = 21，sampled = 30−0+5 = 35）。

### 应用前段 `0x40aa80`

| # | kind（seed，Lv） | 输入 HP／毒字／禁魔 | 原 HP | 原毒字 | 原禁魔 | flags | contribution | 停止点 | 重制 `SupportMagicRules.resolve` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1–3 | heal（1，1） | 1／95／100，毒 0x90003，禁魔 2 | 10／100／100 | 0x90003 | 2 | 3 | 4／2／0 | 0x40ac04 | = |
| 4–6 | heal（1，100） | 同上 | 100／100／100 | 0x90003 | 2 | 3 | 49／2／0 | 0x40ac04 | = |
| 7–9 | heal（101，1） | 同上 | 8／100／100 | 0x90003 | 2 | 3 | 3／2／0 | 0x40ac04 | = |
| 10–12 | heal（101，100） | 同上 | 100／100／100 | 0x90003 | 2 | 3 | 49／2／0 | 0x40ac04 | = |
| 13／14 | cure（1，1） | 1，毒 0，禁魔 0／2 | 1 | 0 | 0／2 | 0／2 | 0 | 0x40b831 | = |
| 15／16 | cure（1，1） | 1，毒 0x50001，禁魔 0／2 | 1 | **0** | 0／2 | 0／2 | 24 | 0x40b831 | = |
| 17／18 | cure（1，1） | 1，毒 0x320009，禁魔 0／2 | 1 | **0** | 0／2 | 0／2 | 120 | 0x40b831 | = |
| 19–24 | cure（1，1） | HP 100，其余同 13–18 | 100 | 同上 | 同上 | 同上 | 0／24／120 | 0x40b831 | = |

读法：heal 只加 `min(缺失 HP, value)`（#2／#5 满格前 5 点只补 5；#3／#6 满 HP 加 0），毒字与禁魔不动；贡献 = 实际回复／2。cure 清整个 packed 毒字（高 16 位回合数与低位一起归零）并清毒 flag，禁魔 2 保留、HP 不动；贡献 = (毒字低 16 位 + 1) × 12（0x50001 → 24；0x320009 → 120），零 RNG。

### 对照结果分层

| 矩阵句 | 证据等级 | 依据 |
| --- | --- | --- |
| WATER05–08 的实际缺失 HP 回复量 | static-derived（有界执行，18＋12 组逐字段相等） | 上两表 |
| 毒字清除同时保留禁魔 | static-derived（有界执行，12 组） | cure 表 |
| 多目标一次 MP | static-derived（读法） | 扣费在 `0x442bc1..0x442bce` 于施法执行时减一次（[技能资源](original_skill_resources.md)），逐目标应用循环 `0x40aa80` 不读 MP |
| 最终经验 | static-derived | 贡献→经验换算见[原经验](original_experience.md)；本包只证明 contribution 字段 |
| 回复／驱毒结果数字的显示 | 原语义 static-derived（`0x4084e0`→`0x408580`：绿 NUM2xx 回复、蓝 NUM3xx MP、红 NUM1xx 伤害、无「+／−」字形，[技能功能位](original_skill_function_bits.md#结果数字的显示语义anishowhitresult--0x4084e0--defprocshownumber2026-09-22-lane-r12-rules-leftoversstatic-derived数字图-resource-derived)）；重制以「+／−」字形区分是**明示重制表现选择**，不是待证据替换的 provisional——原行为已知，改不改是产品决定（进决策清单） | — |
| 满 HP／无效目标拒绝 | 重制交互取舍（原前段仍执行取值） | 上文 |

未执行、仍属边界：`0x40ac04`／`0x40b831` 之后的显示回调与共同尾部；原全局 RNG 顺序；AI 自救／净化组合顺序（见下节 provisional）。

## 共同事务与AI

`SupportMagicRules`只返回HP／状态和数值提案。`SkillResolutionRules.prepare_cast`先验证拥有权、MP、禁魔、每个范围目标与状态一致性；任何坏输入在RNG之前拒绝。确认时返回一个施法者扣款、去重目标变化与各自收据，PlayLoop一次提交。自身既是施法者又是目标时，回复HP不能覆盖MP扣款；正向法术不附送普通攻击气力，不走反击或受伤声音。原状态行动后处理继续通过唯一交接入口运行，先解毒可以避免随后自己的毒伤。

`AISelfPreservation`只准备当前格、自身中心的受支持技能。原自救HP门槛通过后，复用进攻类别helper、回复桶1/2、单体／范围优先和use_ratio选择；原用药分支可在无MP、禁魔或技能未选中时接续。满HP仍中毒时，桶7驱毒候选在HP／残血敌方检查之后、普通进攻之前考虑。没有敌人可攻击也能完成有效自保。未授予／无效果能力不生成候选；格式错误不能悄悄变成普通攻击。

此处复用了原选择内核，**没有声明原完整辅助dispatcher／全局RNG顺序等价**。优先级连接、用药退路、自身中心和清毒检查位置为provisional适配；替换需完整追踪0x43f5f0支援分支及其0x40c570／移动搜索调用。帮助其他友军和移动施援已由后续[友军支援批次](original_ai_support.md)接入，不能用本包较早的自保回执代替其验收；复活和其他增益仍不在当前支持范围。

## 原资源与表现

[support_magic/manifest.json](../../../content/imported/hsl/chapter01/support_magic/manifest.json)保存四条eff12–15程序、OBJ定义、20个去重SHP帧与6个WAV的源／导出哈希。`hsltools/data/support_magic.py`从本机原PAK提取，逐帧保存SHP draw_origin，声音沿现有XOR-A8解码；普通check不依赖原PAK或Wine。缺资源、歧义记录或未知序列明确失败。

`SupportMagicPresentation`复用现有cast前摇，读取原水环／绿色星光帧和各物体delay，按法术显示不同聚集／扩散过程。音效消费SHOOT005、MHEAL003/006/007/008与LASERUP003。它只接收已结算收据、投影后坐标和clip时钟；不保存战斗真相、不抽战斗RNG。release／impact每次仅一次，全部目标显示实际+HP或解毒，沿现有文字碰撞避让。

粒子散布、移动轨迹、加色、显示持续时间和tick→秒映射是provisional重制选择。源Wait/Delay并不自动等于已测原作秒数；替换需四种水系法术的受控连续原帧／音轨和原效果调度证据。当前 [实际输入验收](../runtime_observations/support_magic/README.md)证明Godot中可选、可取消、可完成并交接，不能证明原版像素或时钟一致。

完成门槛必须覆盖最后一批错峰粒子的整个淡出；实际`present(complete)`仍有非透明源帧视为回归。三种回复尾部截断已由3项red复现并修复，四种效果的impact／complete检查与受影响的三条实际输入及尾帧均通过；修复保持release／impact不变。完整支持套件为284项，其中8项是该表现边界，不能把其数字当作284次原作执行。

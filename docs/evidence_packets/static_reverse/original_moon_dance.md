# 月花圓舞：自身中心、逐目标五段受击与动作末经验

> evidence: static-derived · status: live · functions: 0x409a20, 0x40b8f0, 0x4104d0 · tools: hsltools/data/moon_dance.py, hsltools/probes/moon_dance.py, run_moon_dance_tests.gd · updated: 2026-09-28

## 结论

- 原版 002 的初始绝技月花圓舞以自身为中心、对周围 3×3 敌人逐目标完整执行五段再切换下一目标；整次只付一次 20 气力；目标 HP 归零后后续段仍抽样但伤害与经验为零；全段用施放前等级／属性／连杀 word，经验与连杀在整次动作结束统一处理（static-derived）。
- 重制 `game/sim/RepeatedSpecialRules.gd` 提出去重后的完整五段结果，`game/sim/loop/BattlePlayLoop.gd` 一次提交扣费／HP／死亡／经验／奖励，`game/battle/scene/MoonDancePresentation.gd` 读不可变逐段快照播放（static-derived）。
- 一致：63 组序列共 315 次伤害应用与 14 组前段与重制相符（static-derived）。花瓣与打击光球按 objcomd.txt 命令 10／11 的原生轨迹运动（[objcomd 命令程序包](original_objcomd_programs.md)），演出按原版 16 ms tick（[tick 率包](../runtime_observations/original_tick_rate/README.md)）；落点偏移用按目标取种的随机变体、施法者开场面板与 1.5 s 起手是重制值（provisional）。

## 证据

**resource-derived**
- 002 `special:magicOTHER:magicCode06`，原 type5／零基 index5，名称 146；029 离场演出角色不获战斗技能。字段：伤害 6..12、命中 98、属性倍率 36、气力 `expend=1`（费用 20）；`range0Cell` 自身中心、`range1CellFull` 周围 3×3、`magicFun_Attack` 只选敌方。
- `specCode19` 攻击效果为空；`specCode20` 受击程序：延迟 20，生成 6 个花瓣并播风声，延迟 60 后五次 `aniProcessHitMiss`，后四次间隔 10，末次后延迟 60；累计命中等待 80／90／100／110／120，总等待 180。每次命中后插入两颗打击光球、播打击声，再 `aniShowHitResultNoWait`（资源顺序，不是每秒帧数）。
- `s_shape=P002_201.SHP` 三帧、421 四帧花瓣、422 四帧光球、WIND0009／BOMB0005，共 11 张图／2 段声音；PAK effects 与 global.obs 字节与来源一致。见 [content/generated/hsl/skills/moon_dance.json](../../../content/generated/hsl/skills/moon_dance.json)、[content/imported/hsl/shared/moon_dance/manifest.json](../../../content/imported/hsl/shared/moon_dance/manifest.json)。

**static-derived**（[original_moon_dance.json](original_moon_dance.json)；未代换指令、未跳过 callee、未 stub；随机数逐次记 bound／value／阶段；锚点拼接 SHA-256 `60fd76d7dd2d0f189e54c6f87df5d82fa1da498537fa193c005e8a7c34f43046`）

| 项 | 锚点 | 读法 |
| --- | --- | --- |
| 伤害应用 | `0x40b8f0` 150 次入口正常返回；另 165 次由 `0x403968` opcode 分派读 17，经 `0x4047e9` 命中路径，止于 `0x4048b3` 首个数字表现调用前 | 每段用原 channel1 的反应／精神／体质／等级与命中补偿，按当前 HP 封顶；无伤害不伪造击杀或贡献 |
| 目标切换 | `0x403d3d` 受击程序结束后 `0x4104d0(1)` 取下一唯一目标，`0x409a20` 取受击程序并重设游标 | 按行扫描、角色指针去重；大型角色多格只一套五段；“仍有／已耗尽”两边界均执行 |
| 扣费 | `0x445290`，攻击动画生成前 | 20／40／60 气力三组 |
| 逐段累积 | `0x4c13f0`／`0x4c2c7c` | 不改角色已发 EXP 或气力 |
| 死亡扫描 | `0x445305` 之后开始；`0x4453a9` 每死者 kill_count +1，只第一个死者 +1 连杀低字 | 三种 word × 一至三个死者，9 组前段 |

覆盖输入：初始 HP 0／1／10／30／100、命中 0／98、三个种子、高低等级差与既有连续数。经验逐段换算（伤害贡献、等级差、击杀奖励、随机折减、既有连杀与 EXP 装备倍率，见 [original_experience.md](original_experience.md)）后汇总，一次入账／升级。与普通 `double_attack` 的死亡截断不同。

## 重制接线

- `game/sim/RepeatedSpecialRules.gd`：按行去重的五段结果；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_moon_dance.md`。
- `game/sim/loop/BattlePlayLoop.gd`：先核对全部目标／来源／状态／资源，再一次提交；每段存 HP 前后、原抽样、贡献、独立经验换算与参与者快照；`game/battle/runtime/BattleCheckpoint.gd` 核对五段顺序、目标不重复、HP 连续与单次付款，恢复不重演。
- 玩家：“絕技”后点击自身；效果区与唯一中心不同线框；技能菜单按真实拥有权生成；取消回当前行动；移动后可用；禁魔／MP0 不阻止，麻痺禁止。
- AI：枚举能覆盖目标的自身落点，走共享整块通行与现有技能概率；第二行动重查活目标、气力、位置与装备。普通双击、反击、武器尾部附毒与 `action_twice` 各自独立，月花不附加普通武器状态；终态冻结后不再运行命中或状态尾部。
- `game/battle/scene/MoonDancePresentation.gd`：完整受击程序结束后才播地图死亡／EXP／领取／成长／第二行动；源等待按原版 tick（`OriginalTick.TICK_SECONDS`，经 `CombatPresentationTiming.scaled`）计时；1.5 s 起手代替 002 的 s_action 引导（provisional）。
- 开发演练 `game/battle/development/MoonDanceTrial.tscn`：原 051 地形、002 源职业／装备／技能、三名原士兵，PriestTrial 开发库存、额外 40 初始气力与 120HP／20speed 加值；正式第一战与 PriestTrial 原初始气力不变。

## 复现

`python3 tools/hsl.py check moon_dance`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| `moon_dance/`（目录已删，见 Git 历史） | manual、multi_kill、misses、phase_extra、ordinary_then_moon、aid_after_moon、large_target、ai_multi、ai_empty、ai_paralysis、victory、defeat、escape | `run_moon_dance_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 原完整 dispatcher、全局随机流、renderer 与现场实玩未执行；165 次与 14 组为前段。
- 花瓣与光球的落点偏移用按目标取种的随机变体代替共享随机流；施法者开场面板布局与 1.5 s 起手是重制值；混色未逐像素对照（provisional）。
- 正式第三战接入、伙伴入队调级／学习、其余职业不在本包。

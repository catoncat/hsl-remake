# 水剎：原数值、真实十字范围与可执行所有权

> evidence: resource-derived; static-derived; runtime-measured · status: live · functions: 0x40a7b0, 0x40aa80, 0x42c780 · tools: hsltools/data/water_strike.py, hsltools/data/water_strike_trial.py, hsltools/probes/water_strike.py, run_water_strike_tests.gd · updated: 2026-09-27

## 结论

- 原版水剎为 magicWATER code01：range3CellCircle 射程、range1Cell 十字效果、8MP、伤害参数 16–24、命中 94，走共同原伤害公式、水抗性索引 1（resource-derived；static-derived）。
- 重制经 `game/sim/SkillResolutionRules.gd` 一次付款、逐目标结算，`game/sim/StatusApplicationRules.gd` 补 `magicWATER → 1` 抗性映射；拥有权按 PLAYERS 与学习条件，不全员授予（static-derived）。
- 一致：22 次数值返回与 44 段应用前段与重制对上；目标访问次序、粒子排布与播放时钟是重制取值（provisional）；实际输入回执为重制集成证据（runtime-measured）。

## 证据

**resource-derived**

- `MAGIC.TXT` `magicWATER / magicCode01` 与 `RESOURCE.TXT` 名称 154 确定水剎；字段：`range3CellCircle`／`range1Cell`／MP 8／伤害 16–24／命中 94／使用权重 90／`magicFun_Attack`／`eff_proc_Local / effCode08`。
- `RANGE.H` `range1Cell` 为中心及四邻十字（非对角菱形）。
- `PLAYERS.TXT`：025 声明水剎与酸蝕幻霧（按此顺序列出）；026 只有风／火；002 只初始声明治癒之水，四级经 [原学习条件](original_growth_lifecycle.md) 取得水剎。
- 原资源（`content/imported/hsl/chapter01/water_strike/manifest.json`）：`effCode08`、`obj_Effect_WaterFlyUp` 8 张 WAT01 帧、`obj_Effect_WaterDrop` 3 张 WAT02 帧、`WAV\WATER005.WAV`；源顺序 放音→上升对象→wait80→下落对象→wait30→下落对象→wait120。

**static-derived**（固定 SHA 原 `hsl01.exe`；[original_water_strike.json](original_water_strike.json)；每路径 ≤4096 指令，只允许已审查数值／RNG callee）

| 地址 | 执行范围 | 边界 |
| --- | --- | --- |
| `0x40a7b0` | 22 次正常返回；逐次核 RNG 边界／值、结果、命中补偿、输入不变 | 不等于完整施法或全局随机序列 |
| `0x40aa80` | 44 段前段：水类型 1、抗性偏移、命中、扣血／贡献；每组给 1 与 100 HP | 停在 `0x40ab87` 或 `0x40abb0`，未执行显示／经验回调 |
| `0x42c780` | 预置两个原全局种子并记录有界抽样 | 跳过 OS 时钟种子初始化 |

参数覆盖两组等级／精神／魔攻 × 水抗 0、25、80 × 三个初始种子，另有零／中等命中、补偿／装备命中与 `no_attack` 分支。每目标经验换算与最终发放见 [original_experience.md](original_experience.md)。

**runtime-measured**（重制侧）：见「复现」回执；`WaterStrikeTrial` 路线中祭司由治疗所得最终 EXP 3→4 级，于独立第二行动向两敌之间空格施放刚学的水剎。

## 重制接线

- `game/sim/SkillResolutionRules.gd`：全部目标预检查→一次付款→逐目标效果与经验→全动作一次成长；空格中心可选，四邻合法敌人按当前阵容顺序（provisional）；039 巨型单位占多格只结算一次。
- 未取得、MP 不足、禁魔、麻痺、不许可的移动后施法、任一目标无效、终态均在付款与抽样前拒绝；逆十字 218 把整次 8MP 降为 4MP；232 只影响移动后施法合法性。
- AI 用同一所有权、射程、资源与状态模型；025 用尽 8MP 后第二行动重新决策。
- 表现只读已提交回执：释放一次，各受影响者显示 HP／MP 与伤害或 MISS，水滴完成后才播死亡、经验／学习、成长与菜单；固定 8 颗布局、sin/cos 分布、速度、混色、落点偏移与 100 tick/s 时钟为重制排布，不消费战斗随机流。
- 存档／F9 保留动作阶段、学习与结算，恢复不重付款、不重学、不重播。
- `tools/hsltools/data/water_strike_trial.py` 生成 `game/battle/development/WaterStrikeTrial.tscn`（初始属性／经验、毒、敌人麻痺、位置与装备为演练配置）。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_water_strike.md`。

## 复现

`python3 tools/hsl.py check water_strike`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [water_strike](../runtime_observations/water_strike/receipt.json) | public、mixed、mobile、limited、silence、ai、victory、defeat、escape | `capture_water_strike_review.gd`、`run_water_strike_tests.gd` |

## 边界

- 完整原墙钟、对象调度与全局 RNG 未确认；原随机粒子生成器与对象 opcode 语义未还原。
- 多目标访问次序是重制适配合同，不由源范围形状推出原对象遍历次序。
- 地裂、未实现绝技与高阶职业不因本包获得支持。

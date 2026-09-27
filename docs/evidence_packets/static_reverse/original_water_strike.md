# 水剎：原数值、真实十字范围与可执行所有权

> evidence: resource-derived; static-derived; runtime-measured · status: live · functions: 0x40a7b0, 0x40aa80, 0x42c780 · tools: hsltools/data/water_strike.py, hsltools/data/water_strike_trial.py, hsltools/probes/water_strike.py, run_water_strike_tests.gd · updated: 2026-09-19

证据分为三层，不能互相替代：源表／原图音是 `resource-derived`；原 EXE 的有界指令执行结果为 `static-derived`；Godot 实际输入／画面为 `runtime-measured` 的重制集成证据，不是原引擎实玩录像。

## 原始定义与身份

`MAGIC.TXT` 的 `magicWATER / magicCode01`、`RESOURCE.TXT` 名称154共同确定**水剎**。`hsltools/data/water_strike.py`逐字段检查：射程 `range3CellCircle`、效果 `range1Cell`、MP费用8、原伤害参数16–24、命中参数94、使用权重90、`magicFun_Attack`、`eff_proc_Local / effCode08`。`RANGE.H` 的 `range1Cell` 是中心及四邻十字，非对角菱形；水剎是本次接入的真实源范围法术，旧风刃／幻火仍为各自源单体，不能把那些合成范围夹具叫原始范围定义。

水抗性是原类型索引 **1**。当前 `StatusApplicationRules` 增加缺失的 `magicWATER → 1` 映射，水剎没有借用火抗性或一个缺省零值。原16–24是公式参数而非任意目标的最终扣血；实际等级、精神、魔攻、抗性、命中及目标剩余HP继续参与共同原公式。

`PLAYERS.TXT` 的025原声明已含水剎及酸蝕幻霧；注册后按源技能顺序列出水剎、酸蝕幻霧。026仍只有原风／火，002祭司仍只初始声明治癒之水。002通过[原学习条件](original_growth_lifecycle.md)在四级取得水剎后才具备当前施放资格；没有把注册当成全员授予，也没有改默认第一战装备、技能或阵容。

## 22次完整数值返回与44段实际HP前段

[机器包](original_water_strike.json)由`tools/hsltools/probes/water_strike.py`读取固定SHA的原`hsl01.exe`执行，复用已登记的确定符号与已有安全边界，不引入模型候选名称：

| 地址 | 本批执行范围 | 不证明的部分 |
| --- | --- | --- |
| `0x40a7b0` | 22次原数值函数正常返回；逐次核RNG边界／值、结果、命中补偿及输入未变 | 不等同于一次完整施法或全局引擎随机序列 |
| `0x40aa80` | 44次原施加前段，沿实际水类型1、抗性偏移、命中、扣血／贡献运行 | 在`0x40ab87`或`0x40abb0`停止，未执行后续显示／经验回调，不能标为完整返回 |
| `0x42c780` | 上述函数真实调用原随机函数；预置两个原全局种子并记录有界抽样 | 跳过OS时钟种子初始化，未统一重制各随机流 |

参数覆盖两组等级／精神／魔攻，水抗0、25、80及三个初始种子；额外零／中等命中、补偿／装备命中和`no_attack`分支。应用前段对每组分别给1、100HP，核对实际扣血、HP下限、贡献和局部命中补偿。所有路径最多4096条指令，仅允许既有已审查数值／RNGcallee。原表字段／EXE哈希、正常返回或前段停止、所有原输出及抽样均保存在机器包；默认运行只离线重验，显式`--execute`才重新执行原输入。

已有函数登记仍是这些地址，不把水元素的新输入矩阵另起一个虚构原函数。原每目标经验换算和最终动作发放复用[经验证据](original_experience.md)，没有再发一次“胜利经验池”。

## 当前共享事务与可见反馈

`SkillResolutionRules`沿现有全部目标预检查→一次付款→逐目标效果与经验→全动作一次成长的路径接入水剎；没有第二套施法或成长状态。候选可以是空格中心，中心四邻的合法敌人按当前阵容顺序选取；一个039巨型单位即使占据多个效果格也仅结算一次。该稳定访问次序是当前适配合同，不由源范围形状推导成原引擎对象遍历次序。

未取得、MP不足、禁魔、麻痺、不许可的移动后施法、任一目标无效、终态都会在付款与抽样前拒绝。逆十字218把整次8MP降为4MP，不对每目标重复收费；232移动施法权限只影响当前合法性。AI使用同一所有权、射程、资源和状态模型；025消耗最后8MP后，白光之翼第二行动重新决策，不复用先前水剎意图。

动画只读已提交回执：释放一次，命中阶段为各实际受影响者显示HP／MP与独立伤害或MISS；源水滴效果完成后才播放死亡、经验／学习、成长确认和下一菜单。存档／F9保留动作阶段、学习与结算，恢复不付款、不重学、不重新播放旧施法。跨战继续使用已经提交的学习记录；其持久化及生成流边界继承SR-072。

## 原资源与明确的重制表现边界

`content/imported/hsl/chapter01/water_strike/manifest.json`追溯原`effCode08`及两个对象：`obj_Effect_WaterFlyUp`的8张WAT01帧、`obj_Effect_WaterDrop`的3张WAT02帧，和独立`WAV\WATER005.WAV`。PAK条目／原字节SHA、整张图、偏移和ShapeDelay保留；不是把风火调成蓝色。源顺序是放音→上升对象→wait80→下落对象→wait30→下落对象→wait120。

`WaterStrikePresentation`继承已有纯表现工具，按各实际受影响位置绘制。100 tick/s与全局可读播放倍率沿用当前重制时钟；固定8颗的每组布局、sin/cos分布、运动速度、混色和落点偏移是确定的重制排布，未宣称还原原随机粒子生成器或完整对象opcode语义。它不消费战斗或生成随机流，不以更多装饰物改变真实抽样。完整原墙钟、对象调度和全局RNG保持未确认。

## 可玩入口与复验

`game/battle/development/WaterStrikeTrial.tscn`可独立操作：待机让真实中毒同伴受伤，治疗所得最终EXP使祭司3→4，再于独立第二行动向两敌之间空格施放刚学水剎。初始属性／经验、毒、敌人麻痺、位置和装备明确标为演练配置；没有运行中虚构取得。具体过程、回执及限制见[真实输入与画面](../runtime_observations/water_strike/README.md)。

```sh
python3 tools/hsl.py check water_strike
python3 tools/hsl.py check water_strike_data
python3 tools/hsl.py check water_strike_trial
tools/godot.sh --headless --script res://tests/run_water_strike_tests.gd
tools/godot.sh --screen 1 res://game/battle/development/WaterStrikeTrial.tscn
```

屏幕1是本次实际内建屏编号，别机需先确认。原图音生成需合法原PAK；门禁只校验已生成输入，不依赖原游戏运行。本切片只使水剎可用；地裂、尚未实现的绝技、高阶职业与原全局状态机不能因这一注册获得支持。地系已有增强／麻痺等独立能力也不被这里笼统称为未实现。

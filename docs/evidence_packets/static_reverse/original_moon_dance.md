# 月花圓舞：自身中心、五段受击与最后经验

> evidence: static-derived · status: live · functions: 0x409a20, 0x40b8f0, 0x4104d0 · tools: hsltools/data/moon_dance.py, hsltools/probes/moon_dance.py, run_moon_dance_tests.gd · updated: 2026-09-18

本条链在002祭司已接入后恢复她源声明的初始绝技。来源为`PLAYERS.TXT`的`special_other`、`SPECIAL.TXT`、完整`EFFECT.TXT`／`ANIMAL.TXT`和固定哈希EXE的有界执行。`TypeSafe Jev`未参与本批事实判断；既有符号和确定性caller用于定位。

## 来源与编号

002的月花圓舞为`special:magicOTHER:magicCode06`，原type5／零基index5，名称146。029的离场演出角色身份与002分开，未获得战斗技能。原技能字段：伤害6..12、命中98、属性倍率36、气力`expend=1`，费用20；`range0Cell`为自身中心，`range1CellFull`为周围3×3效果，`magicFun_Attack`只选择敌方。

`specCode19`攻击效果为空，`specCode20`受击程序先延迟20，生成6个花瓣并播放风声，再延迟60开始五次`aniProcessHitMiss`；后四次间隔10，末次之后延迟60。累计命中等待值为80／90／100／110／120，程序总等待180。每次原命中后的效果语句插入两颗打击光球、播放打击声，再使用`aniShowHitResultNoWait`。这些是资源顺序，不能直接当作原引擎每秒帧数。

原002的`s_shape=P002_201.SHP`三帧、421的四帧花瓣、422的四帧光球与WIND0009／BOMB0005共11张图／2段声音独立导入，PAK中完整effects及global.obs字节与现存来源逐字节一致。源位移、程序及哈希保留在[生成合同](../../../content/generated/hsl/skills/moon_dance.json)和[资源清单](../../../content/imported/hsl/shared/moon_dance/manifest.json)。

## 原指令的可复现结论

[机器回执](original_moon_dance.json)由`tools/hsltools/probes/moon_dance.py`写出：63组五段序列，共315次伤害应用。其中150次`0x40b8f0`从函数入口正常返回；另165次从真正的`0x403968` opcode分派读取17，经`0x4047e9`命中路径运行，止于第一个数字表现调用前的`0x4048b3`。没有代换指令、跳过callee或stub；数字与经验随机数逐次记录bound／value／所属阶段，独立正域模型核对结果。

**同一目标完整执行五段，再切换下一目标。** `0x403d3d`在受击程序结束后通过`0x4104d0(1)`取下一唯一目标，`0x409a20`取得该绝技的受击程序，并重新设置程序游标。两种“仍有下一个／已耗尽”边界都有实际执行。覆盖顺序复用已证明的按行扫描、角色指针去重；大型角色多个身体格命中仍只执行一套五段程序。

**目标HP归零后，后续回调仍抽样，但实际HP差和经验为零。** 这条链与普通`double_attack`的死亡截断不同。每段使用原channel1的反应／精神／体质／等级及命中补偿，按当前HP封顶；无伤害时不伪造击杀或贡献，也不再播“受伤0”。初始0／1／10／30／100HP、命中0／98、三个种子以及高低等级差／既有连续数均有回执。

**气力只付一次，经验和连杀在整次动作结束处理。** `0x445290`在生成攻击动画之前扣费用；三组20／40／60气力输入分别验证。逐段回调累积`0x4c13f0/0x4c2c7c`，不改角色已发EXP或气力。死亡扫描到`0x445305`之后才开始，`0x4453a9`每个死者增加kill_count，只有第一个死者增加一次连杀低字；三种原有word×一至三个死者的9组扫描前段已执行。

因此，本次所有段、所有目标的经验换算都使用施放前等级／属性／连杀word。不能让第一个死者提前提高后面目标的连杀倍率，也不能让中途升级改变后面段的伤害。伤害贡献、等级差、击杀奖励、随机折减、既有连杀和EXP装备倍率复用[原经验合同](original_experience.md)，逐段换算后汇总，再一次入账／升级。

以上另有14组扣费／目标切换／死亡扫描前段。全部指令锚点拼接SHA256为`60fd76d7dd2d0f189e54c6f87df5d82fa1da498537fa193c005e8a7c34f43046`。这不是原完整dispatcher、全局随机流、renderer或现场实玩等价声明。

## 进入当前游戏的合同

`RepeatedSpecialRules`只提出目标按行去重的完整五段结果。`BattlePlayLoop`先核对所有当前目标／来源／状态／资源，再一次提交扣费、HP、死亡占用释放、经验／成长及奖励，最后沿既有行动出口处理。每段保存HP前后、原抽样、实际贡献、独立经验换算和参与者快照；每目标汇总用于范围提示，全段收据用于最终经验／死亡查找。Checkpoint核对五段顺序、目标不重复、连续HP和只一次付款，恢复不重演。

玩家在“絕技”选择后点击自身；周围效果区域与唯一可选中心用不同线框提示，没有敌人时明确提示无目标。技能菜单从真实拥有权生成，多个已拥有绝技可实际选择，不把月花硬替代氣刃斬。取消回到当前行动，撤销待确认移动恢复原地；移动后可用绝技、禁魔／MP0不阻止气力足够的月花，麻痺仍禁止该行动。

AI枚举能覆盖当前目标的自身落点，使用共享整块通行／停留和现有技能概率，再提交相同多段事务。第二行动重新检查活目标、气力、当前位置与装备，不复用首轮死亡目标。普通攻击、暴击／反击、武器尾部附毒和`double_attack`继续使用独立普通系列；月花不会因此多倍生成五段或附加普通武器状态。`action_twice`仍是另一独立完整行动，分别付款，毒／禁魔等末尾计时只按原最终行动出口推进。胜负／撤离冻结后不再运行任何命中或状态尾部。

`MoonDancePresentation`读取不可变逐段快照，完整受击程序结束之后才播放地图死亡／EXP／领取／成长／第二行动。原三张施放图与花瓣／光球／音效已接入；沿用本项目演出时钟，将源等待比值放到100tick/s再受共同0.4播放倍率影响。花瓣轨迹、两球位置、混色和面板布局属于重制表现值；不能由原资产存在推导这些值是原版时钟或坐标。

## 复跑和保留边界

```sh
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate moon_dance --exe $HSL_ORIGINAL_DIR/hsl01.exe
python3 tools/hsl.py check moon_dance_data
tools/godot.sh --headless --script res://tests/run_moon_dance_tests.gd
tools/godot.sh --screen 0 res://game/battle/development/MoonDanceTrial.tscn
```

`MoonDanceTrial`是明确开发演练：原051地形、002源职业／装备／技能和三个原士兵，提供PriestTrial开发库存及额外40初始气力、120HP／20speed来源加值，让被包围的角色可先操作。正式第一战和PriestTrial原初始气力不变。正式第三战接入、伙伴入队调级／学习、其余职业与完整高位分支保持独立范围。[十三条实际输入／十六张图](../runtime_observations/moon_dance/README.md)已按四个零退出进程归档；最终完整门禁日志和真实退出码写入本批提交说明，不用原指令或定向测试替代视听验收。

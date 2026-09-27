# 当前职业初始化、成长与装备的共同刷新

> evidence: static-derived · status: live · functions: 0x448370, 0x448800, 0x448840 · tools: hsltools/data/role_profiles.py, hsltools/probes/job_stats.py, run_job_stats_tests.gd · updated: 2026-09-17

## 证据范围

本包是原 EXE `0x448840` 的有界完整返回，不是重新命名旧战斗快照。机器证据 [original_job_stats.json](original_job_stats.json) 保存 001／021／023／024／025／026 六个源模板、108 组输入、每组两次完整刷新（共216次）、源表哈希、原字节与返回值。第二次先污染旧派生槽，核对刷新不会累加上次结果；HP／MP按新上限夹取，EXP与气力不受刷新影响。

源字段取自已跟踪的 PLAYERS／ITEM／TYPE 表，EXE由只读原安装读取并校验完整SHA。没有执行原初始化随机调级、表解析器或完整主循环，PLAYERS原包差异也未放宽。Jev函数目录与确定性符号用于找候选；正式结论由原指令运行与独立算术模型支持。

## 本轮更正

旧Godot只对Leonard保留完整SwordMan刷新，NPC的抗性使用PLAYERS基础字段，遗漏职业分支与装备抗性。本轮所有当前场景角色使用同一个刷新入口，补全这些派生值，并清除026从场景统一MP常数重填的特例。025保留其源模板三级。（2026-09-25 更正：首战 NPC 的模板为 1 级，开战时按原出生调级 `0x40e870` 抽等级，见[触发条件](original_auto_growth.md#开战调级的触发条件)；本包刷新公式不变。）

原actor `+0x28` 的源mode位 `0x10000` 决定HP公式中的等级项。它不是“当前玩家可控制”或Godot当前阵营。将法师临时设为玩家控制，不能因此多加这一项；反过来友军AI的原pmPlayer仍保留它。源mode独立保存在profile中，换装、分点、存档不根据临时控制权改写。

## 确认的分支

| 原入口／表 | 结论 |
| --- | --- |
| `0x448840` | 清工作槽、分职业计算、应用当前装备、统一夹取与当前资源收束 |
| `0x448370`，`0x4786bc` | 四属性上限来自职业索引；80为90/88/80/94，90为84/78/100/90，94为107/80/66/99 |
| `0x448800` | 攻击等级增量独立于HP的源mode门禁：1–9按等级，10–19每两级增1，20以后每四级增1 |
| `0x449e9c`、`0x44a74e` | 原dispatch所选Magician／BeastWarrior分支；名称只是项目标签 |
| `0x44b62c`后公共尾部 | 源基础增量、HP至少1、无已学魔法时MP0、移动0..12、五类抗性0..80；当前HP／MP只夹取，不自动回满 |

`JobStatsRules`逐项实现80（SwordMan）、90（Magician）、94（BeastWarrior，当前重装兵模板所用）的正值整数分支。不同乘除顺序不合并成浮点系数，法师魔击超过50的折半段、职业抗性各自上限、速度系数、HP／MP构成都保持原截断位置。精确输入／输出以机器包为准，不由简化公式表覆盖原返回。

108组包含实际初始装备、等级2/9/10/19/20/40/99、四属性分别加1、职业上限、源mode翻转、空装备、重复抗性饰品、HP/MP回复装备、减耗与白光之翼组合。空装备只证明刷新算术，不宣布徒手攻击范围已支持；合成跨职业装备组合是算术夹具，不放宽产品use_job资格。

## 当前接入

`tools/hsltools/data/role_profiles.py` 从验证过的机器包和源表生成六个role profile，第一／第二战生成器消费同一入口。`JobStatsRules`负责职业基础部分，`ProgressionRules`叠加一次当前装备，并统一更新战斗profile、HP/MP上限、速度、抗性与唯一move_point。初始queue在刷新后构造，战中换装／升级仍不重排本轮queue，下次正常wrap才读取新速度。

初始化先复制输入模板，不把刷新写回调用者；该边界有独立回归。升级后的当前资源不回满，卸下原有護身符确实会失去那一件的属性，恢复原装备才应恢复完整原profile，不能把“换一件后直接卸空”当成无净变化。

profile分别保存`allocation=manual`与`fixed_template`。正式仍只有Leonard采用既定五点手动成长；现有NPC即使有完整数值profile，也不会因此制造EXP／升级。受控法师／重装兵的实际成长是明确夹具，用于验证公共职业链，不是默认新增伙伴、控制权或原NPC随机成长算法。

成长面板保留原完整四维与派生预览，增加魔力上限与五类抗性，原生滚轮可看到末项。移动力与固有飞行／不阻挡能力分开，装备装卸和成长不会重复叠加或改写固有通行。

## 复跑和边界

```sh
python3 tools/hsl.py check job_stats
python3 tools/hsl.py check role_data
uv run --no-project --with unicorn==2.1.4 --with pillow python3 tools/hsl.py generate job_stats --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
tools/godot.sh --headless --script res://tests/run_job_stats_tests.gd
```

默认命令离线核对源哈希／固定原字节／完整返回记录，只有`--execute`实际执行原指令。没有其他职业、转职、动态学技、弱化／增益对基础槽的重写、大型占地或跨关队伍。资源装备的最终行动循环见 [原资源回复](original_resource_recovery.md)，可玩验收见 [职业与资源](../runtime_observations/role_resources/README.md)。

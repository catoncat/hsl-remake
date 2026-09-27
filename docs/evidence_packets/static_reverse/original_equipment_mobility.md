# 装备移动力与基础属性刷新

> evidence: static-derived · status: live · functions: 0x448840 · tools: hsltools/probes/mobility.py, run_position_equipment_tests.gd · updated: 2026-09-17

2026-09-17，基线`7abf2c8`。本批把源`ITEM.add_move`接入角色初始化、换装／成长、玩家及AI的当前移动预算、取消和存档。原完整刷新返回、源字段和实际交互分别记录；不重新证明已接通的寻路、攻击和支援算法。

## 系统对照与选择依据

输入为[AI续追／等待](original_ai_navigation.md)、[四邻路径与邻接代价](original_movement.md)、[追加攻击](original_extra_attack.md)、[SwordMan刷新](original_growth_refresh.md)及[原录像观察](../runtime_observations/original_gameplay_reference/README.md)。源`move_point`已用于所有路径预算，但原有初始化只读取基础值，换装／成长不会刷新移动力。

| 体验维度 | 实际缺口 | 本批结果 |
| --- | --- | --- |
| 核心战斗／装备收益 | 三件源移动装备因唯一未支持字段而不能装备 | 蒼空之鎧、舞空之靴、追風之羽通过正常装备流程生效，各加1，多个槽位叠加 |
| 移动／AI站位 | 当前预算可用于原路径，但缺装备刷新来源 | 基础值加当前装备后限制0..12，玩家范围／路径、AI接近／移动后攻击共读同一move_point |
| 操作与取消 | 已走到远格后降低预算，需要明确撤销／继续行为 | 保留已接受的待提交位置；取消仅回原格并按现装备重算，不能回滚装备或误用旧高亮 |
| 成长／初始化 | 逐次加装备值可能累加错误；其他角色初始化来源未连通 | 第一／二战全部角色同一基础／装备计算；SwordMan升级和加点均从基础重新算，不叠旧值 |
| 数值与UI | 状态已有移動力，装备预览缺该值；成长完整预览溢出 | 装备首先显示移動力前后，状态读当前值，成长预览完整保留并能滚动到移動力 |
| 镜头／动画／声音 | 地图坐标、路径、脚步声和打击已有完整合同 | 复用原路径与真实时钟，走完新预算路径后才攻击，不新增移动动画或另一套坐标真相 |
| 保存／终态 | 基础、装备与当前值不一致的存档可能恢复成另一预算 | 安静边界保存全部状态，读回严格校验、不重新抽样；待移动取消及清敌／败北／撤离和重开均实际验证 |

原录像不能单独证明三件装备的数值；本批数值来自表和原刷新。窗口内滚动预览、保留已接受路径及静止边界保存是当前重制交互合同，不能升级为完整原UI等价。

## 源字段与原完整返回

来源为tracked `PLAYERS.TXT`、`ITEM.TXT`、`TYPE.H`，哈希保存在[original_equipment_mobility.json](original_equipment_mobility.json)。[hsltools/probes/mobility.py](../../../tools/hsltools/probes/mobility.py)读取SHA锁定EXE，执行未修改的`0x448840`及已审查的装备／属性子函数；不替换返回值，不为未知调用造stub。

| 地址／范围 | 确认内容 |
| --- | --- |
| `0x44c261..0x44c27f` | PLAYERS.move_point由loader写入角色基础字段`+0x130` |
| `0x447a0b..0x447a31` | ITEM.add_move写入装备有符号增量`+0x34` |
| `0x448987` | 每次refresh先把基础`+0x130`复制到当前`+0x12c` |
| `0x4486bb` | 每件实际装备把`+0x34`加到当前移动力 |
| `0x44b760` | 全部装备处理后把当前值夹到0..12 |

39个输入每个调用两次完整刷新，合计**78次正常返回**。包括六类现有角色的无装备／源装备，基础−3／0／1／5／10／11／12／15的边界，以及三件单独／组合和两个饰品槽的叠加。每例先一级、再四十级，并故意把旧当前值置为1234／−987；输出始终从基础与装备重建，基础保持不变，HP1、MP0、EXP37和ST20不被补满或消费。

该探针只断言移动力和四种资源不变，不由完整函数返回推导其他职业全部派生属性等价。负数／超上限基础是算术边界夹具，不是默认角色；产品只接收非负、有界的基础输入。未执行原角色随机初始化、临时移动状态、大型占地、飞行flags、原装备UI或原存档。

| ITEM | 来源名称 | add_move | 当前支持 |
| --- | --- | --- | --- |
| 138 | 蒼空之鎧 | 1 | 其他字段全部已支持，正常换装 |
| 193 | 舞空之靴 | 1 | 其他字段全部已支持，正常换装 |
| 231 | 追風之羽 | 1 | 饰品槽可分别叠加，正常换装 |
| 194 | 神之足 | 2 | `add_defnese`未确认，继续拒绝，不猜测修正 |
| 236 | 穹蒼之鍊 | 1 | `add_attack_range`／`move_magic_use`未接通，继续拒绝 |

普通checker仅检查已保存原结果；只有显式execute才重新运行原指令：

```sh
python3 tools/hsl.py check mobility
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate mobility --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
```

## 同一状态和刷新事务

`MobilityRules`只做来源校验和加总。`base_move_point`是原基础字段，用于初始化／换装／成长重新计算；唯一供行动范围、全图搜索与路径前缀使用的可变值仍是`unit.move_point`，没有重建move_range或UI预算。源角色生成器把基础及装备后值写入第一／二战配置，PlayLoop初始化再按实际装备验证并重建同一值；默认角色装备和最终移动值没有改变。

`EquipmentRules.replace`先给出完整库存／装备提案，`ProgressionRules.refresh_input_error`校验基础与所有新装备字段，成功后才在PlayLoop一次提交。缺字段、非整数、NaN／Infinity、越界或未知装备都不能半换装。成长同样重算基础加装备，不将敏捷或当前move_point当下一次基础，不因刷新赠送HP／MP／ST。

装备在待提交移动之后变化时，已接受的位置保持；Wait／攻击沿既有提交出口完成，取消则恢复旧起点并立即重新计算当前装备范围。确认过的鞋／饰品不随移动取消恢复。AI现有每次准备均重新生成合法路径和攻击／支援候选，自然读到最新move_point；不会把装备加1作为无视障碍、占格或邻接成本的许可。

Checkpoint校验保存的base、当前装备与move_point一致。加载直接恢复单一loop，不运行初始化、增长或RNG；配置变化仍通过已有摘要拒绝旧存档。第一战模板和第二战开发场景的基础值明确存在，不能在缺数据时由当前已加成的值倒推基础。

## 体验验收与剩余边界

[定向回归](../../../tests/run_position_equipment_tests.gd)（mobility_* 用例；实际场景读回在 run_battle_scene_runtime_tests.gd）检查78个原返回、叠加／去除／重复刷新、成长保留、阻挡路径、玩家和AI预算、低预算下取消、坏输入及保存恢复；旧装备、战利品和追加攻击定向保持通过。实际控件、七条玩法路线、三种终态与末项滚动见[装备移动验收](../runtime_observations/equipment_mobility/README.md)。

人工检图发现成长左栏原完整文本超过可见底板，已在现有区域加入原生ScrollContainer，完整属性保留、滚轮能看到末行“移動力9→9”、按钮不被覆盖；未改变成长数值或时钟。其他未确认能力仍是独立边界：完整角色初始化、飞行／占地flags、action_twice、命中附带状态、其余职业刷新与伙伴资格。下一项只由[PROJECT](../../PROJECT.md#next-steps)维护，不把历史未接入描述当当前状态。

# 装备移动力：实际控件与战斗验收

> evidence: runtime-measured · status: live · tools: capture_equipment_mobility_review.gd, run_position_equipment_tests.gd · updated: 2026-09-17

2026-09-17。原表、78次完整刷新返回和接入依据见[装备移动研究](../../static_reverse/original_equipment_mobility.md)。本包是Godot实际输入／正常时钟的验收，不是原作录像或默认获得这些装备的证明。

## 具名路径

[receipt.json](receipt.json)保存七条路线的来源基础、当前移动力、装备前后、成长／经验、实际路径、攻击／声音事件、终态和重开结果。首次完整七条进程`EQUIPMENT_MOBILITY_RENDER_PASS routes=7`、退出0；成长左栏滚动修复后，仅重跑受影响的equip_growth，`routes=1`、退出0。其余六条没有因接续重新执行，结果没有被覆盖成新运行。

| 路线 | 真实操作和检查 | 已确认结果 |
| --- | --- | --- |
| equip_growth | 靴子预览／取消／确认→状态→铠甲及两个羽毛→攻击→EXP／领取→五点成长→后继 | 源基础5不变，移动力5→6→7→8→9，升到2级后仍为9；最后滚轮到移動力9→9并实际确认 |
| pending_restore | 加移动力后走到原5点不能到的格子→换回旧靴并取消／确认→F5/F9→状态→取消移动→点击旧高亮→重新穿靴移动→Wait | 换鞋不瞬移、不额外消费行动；恢复／取消回原点后范围降为5，旧远格不可点，已确认装备不被回滚；再穿靴后正常到达和交接 |
| ai_without | 玩家Wait，同一真实WRD遭遇中AI只有源基础5 | 正常走近，不能提前攻击；一次AI行动后交给玩家后继 |
| ai_boots | 同一遭遇、AI当前装备舞空之靴并按源公式初始化6 | 路径走完后普通攻击，实际本次伤害16；只有一次移动／攻击／交接，未放宽阻挡或距离 |
| victory | 玩家实际穿靴，走到需要6点才能到的攻击落点→最后敌人1HP→最终EXP／领取 | 清敌胜利，当前移动6保留；F5/F9精确恢复终态，鼠标重开恢复默认5 |
| defeat | 玩家实际穿靴→Wait→遭遇致死攻击 | 正常败北；F5/F9不改变装备或重发奖励，鼠标重开默认5 |
| escape | 源报告之后，从旧5不可达／新6可达的真实位置穿靴→Move→Wait | 撤离成功，不额外产生攻击、经验或回合；终态恢复和重开默认5 |

七条都使用真实Control／地图鼠标事件、键盘取消及保存恢复、相同运行时时钟，未替换RNG、赋值打击结果或加速。测试位置、速度、控制资格、库存和部分属性明确为夹具：三名源角色及当前WRD，测试库存193／138／231／231；击杀／成长路线起始99EXP及1HP敌人，败北路线主角1HP；胜利与撤离从源报告之后开始。角色实际换装使用原派生刷新，并非为了保证结果伪造装备收益。源默认场景未添加这些道具，第二战仍只是共享开发入口。

## 可见检查

十一张精选图的哈希在receipt中；均已人工查看。移动格仍为同一32px空间合同，原脚步／受击／确认声音沿原播放入口。声音事件和AudioStreamPlayer正常前进只能说明本机Godot播放，不宣称原音轨混合或精确秒数等价。

| 内容 | 图证 |
| --- | --- |
| 源装备预览 | [舞空之靴5→6](equip_growth-equip-193-foot.png)、[第二饰品8→9](equip_growth-equip-231-accessory2.png) |
| 状态与成长保留 | [四件装备移動力9](equip_growth-status-9.png)、[成长上段](equip_growth-growth.png)、[真实滚轮到移動力9→9](equip_growth-growth-mobility.png) |
| 保存后按现预算取消 | [恢复起点后的5点范围](pending_restore-cancel-shrink.png) |
| AI同一目标的不同可达性 | [5点只能接近](ai_without-ai-move.png)、[6点走完后真实受击](ai_boots-impact.png) |
| 三种结果 | [清敌](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png) |

人工看图发现旧成长左栏完整预览超出底板，已改为同一区域内的原生滚动容器；属性／派生值没有删减，确认按钮保持独立，新增移動力前后比较。受影响的成长流程和末行滚动专门复验，当前定向173项、既有装备418／奖励583／追加攻击129项检查通过。完整门禁最终结果另记录在提交说明，不把定向通过冒称完整门禁已通过。

默认advance路线使用正式属性／库存／原数值，正常时钟于第6回合167.446秒败北，随后鼠标重开成功。原日志`ignored/equipment-mobility/default-advance.log`；不把该一次冒进结果当作长期难度统计。胜利、撤离及穿装后的恢复由上述独立具名路线证明。

## 复跑与限制

本次先查询显示器：EV2736W为0，内建Retina为1，窗口640×480明确运行于1。显示布局变化须重新查询内建索引。

```sh
tools/play.sh --screen 1 --script res://tests/capture_equipment_mobility_review.gd
# 只重验受影响路径时显式选择。
tools/play.sh --screen 1 --script res://tests/capture_equipment_mobility_review.gd -- pending_restore ai_boots
tools/godot.sh --headless --script res://tests/run_all.gd -- run_position_equipment_tests.gd
python3 -m unittest tools.test_hsl_mobility
```

原始图、进程记录和逐路线progress在`ignored/equipment-mobility-review`，保存文件也仅在该目录，不覆盖玩家存档。单战静止边界保存、降低移动力后保留已接受位置，是明确的重制交互合同；原完整装备UI、临时移动状态、飞行／大体型通行及全局初始化随机序列尚未声称恢复。没有新增第二份战斗字典或长期测试专属产品入口。

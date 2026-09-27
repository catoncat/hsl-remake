# 移动施法、范围装备与行动阶段：实际输入

> evidence: runtime-measured · status: live · tools: capture_position_equipment_review.gd, run_position_equipment_tests.gd · updated: 2026-09-18

SR-058在`1a4168b`主线上的17条具名路线。使用源WRD／原角色美术、真实鼠标／键盘和正常时钟，窗口只在当时核对的内建屏运行。角色控制、装备库存、HP／MP、初始状态和技能授予均为显式夹具；不向正式第一战赠送装备或技能。原指令证据见[移动施法与范围](../../static_reverse/original_position_equipment.md)，逐路线、进程及截图哈希见[receipt.json](receipt.json)。

## 验收范围

| 实际路线 | 已验证行为 |
| --- | --- |
| cancel_equip、remove_restore | 原法师移动后隐藏魔法；保存／恢复后取消移动回原点重新获资格；移动后免费装戒指启用施法，移除一个／最后一个来源分别保留／撤销能力 |
| double_growth、counter_range | 范围装备与双击、白光之翼组合；首击击杀截断次击，EXP／领取／成长后第二行动移动施法；扩大普通／反击范围后四次真实命中只结算一次末次毒伤 |
| support_cure、no_mp_item、silence_special、detour | 移动治疗、第二行动空格中心双目标驱毒；缺MP禁用法术但可用药及末尾血转MP；禁魔仍可用氣刃斬；当前装备预算穿过源地图绕路 |
| ai_stationary、ai_mobile、ai_silence、ai_wait | 无权限先站位再于独立第二行动原地施法；有戒指才移动施法；禁魔／缺MP保留合法回退，无有效动作完成两次有界等待与一次末次交接 |
| ai_support、ai_retarget | 治满友军后第二行动不重放旧治疗；首行动击杀清持有目标，第二行动重新选择存活目标 |
| victory、defeat、escape | 第二行动清敌、致命反击、撤离格待机；终态冻结未执行资源尾部和次数，F5/F9不重放，实际按钮重开回默认装备／阶段 |

所有路线在安静边界使用独立测试存档。反击、数值／状态／经验与下一角色UI由实际收据推进，未替换伤害、经验、随机数或AI决定。旧稳定数值链复用其证据；本页只声明新增位置能力与行动阶段的集成范围。

默认第一战因法师移动资格改变额外走了两条正常完整流程：[坚守](default-hold.json)第8回合208.935秒撤离，[冒进](default-advance.json)第5回合208.216秒败北，途中自然使用氣刃斬并成长；两条均实际按钮重开，进程退出0。这两条没有设置装备／HP／随机数，和上表合成场景分别归档。

## 已检查图证

[移动前提示](cancel_equip-movement-warning.png)说明选择的阶段后果；[组合装备预览](remove_restore-equip-236-accessory1.png)同时显示施法资格和攻击范围增益。[普通连击](counter_range-impact-0.png)仍读取逐击前后值，[AI交接](ai_stationary-ready-0.png)回到真正的下一控制者；[空格驱毒](support_cure-impact-1.png)分别标出两个接收者。终态为[清敌](victory-result.png)、[败北](defeat-result.png)、[撤离及恢复](escape-result.png)。这些原尺寸截图均已查看。

## 失败与回执限制

旧测试曾把236判为不支持；已按三件装备各自能力修正，其他未支持效果继续拒绝。新登记的两个范围函数曾误用不在目录枚举中的role，已改为已有`combat_resolution`并离线重建，未调用模型重判或改变原指令结论。

早期窗口使用已不存在的screen1，虽然具名操作打印PASS，Godot诊断仍失败，因此该进程不采纳；screen0两条重跑实际退出0。AI夹具最初把远目标放在源障碍(14,8)，开场检查正确拒绝；改到同距离的原可通行格(13,9)，地图本身未修改。修正后的六AI＋三终态单进程退出0。其余早期两组共六条保留匹配的PASS日志与完整回执，终端退出码未保留，机器记录明确注明；不补造退出码。

```sh
# 先确认内建屏编号；本次后半段只连接内建屏，编号0。
tools/godot.sh --screen 0 --script res://tests/capture_position_equipment_review.gd
tools/godot.sh --headless --script res://tests/run_position_equipment_tests.gd
tools/verify.sh
```

最终完整非GUI门禁的日志与真实退出码记录在本批提交说明。多格占地、伙伴自动成长及高位状态机其余分支不由本包推导为已完成；原禁魔隐藏菜单与本作保留禁用列表的差异仍为明示交互选择。

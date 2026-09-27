# 攻防增益与退魔：实际控件验收

> evidence: runtime-measured · status: live · tools: capture_stat_magic_review.gd, run_support_magic_tests.gd · updated: 2026-09-18

SR-064基于main@3b4fe51，使用正式PlayLoop、源051地形和原角色／技能美术，以640×480内建屏0、正常时钟操作。`capture_stat_magic_review.gd`在setup后只发真实Viewport鼠标／键盘事件，不替换战斗随机数，也不直接修改结算结果。公开`StatMagicTrial.tscn`提供可手动操作的演练；它的技能／资源赠予是明确开发设置，正式初始能力未增加。

机器记录：[receipt.json](receipt.json)。原数值、原调用边界和AI helper见[研究包](../../static_reverse/original_stat_magic.md)。本页证明当前玩法的实际接入，不升级为原全局时钟或完整dispatcher等价。

## 走通的路线

| 路线 | 实际覆盖 |
| --- | --- |
| manual、repeat、expiry | 公开场景施加；两次独立行动重复加持、读取总攻防及剩余回数、F5/F9；真实多个队列周期走到到期、数值恢复和独立提示 |
| dispel | 同一敌人带攻防增益与毒／禁魔／麻痺，退魔只清两项增益；三项旧状态的packed数值完整保留 |
| movement、melee、growth | 移动选法后取消、原位恢复、移动施法、第二行动卸／重装即时资格；带增益的普通双击／暴击／反击，随后再施法；支援EXP＋装备加倍、实际分配成长点、换杖及治疗 |
| empty_mp、silence、paralysis | 无MP按钮禁用、先喝回魔药再独立施法；禁魔保留但用药／气力绝技可行；麻痺仅跳一个槽，同时到期增益、下次恢复正常行动 |
| ai_buff、ai_dispel、ai_blocked | AI移动后两次补齐不同增益，不刷新已有同类；先退魔再放弃已无效果的第二次施法；无MP／禁魔／禁止普攻时正常回退 |
| victory、defeat、escape | 第一次加持，保存／恢复后第二行动击杀、致命反击或移动撤离；结果出现前演出／经验等收尾完成，终态不能再执行资源／状态／队列，实际按钮重开 |

三种职业以002施法者、023重装友军、026法师目标／敌人接入；完整四职业刷新另由原指令和定向测试覆盖，不虚构未出现职业的GUI路线。既有风火、月花、3×3、装备和普通交锋充分证明的内核不重复跑整批，只验证本轮联动。16条具名路线共13张精选截图，全部已人工查看。

## 图证

[实际施加](repeat-cast-1-attack_up-true.png)、[总值与固定加值](repeat-stats-tina.png)、[自然到期](expiry-tail-13-0.png)。[退魔前五项状态](dispel-target-magicCode06.png)与[仅解除两项增益](dispel-cast-1-dispel-true.png)分开显示。

[增益后的成长](growth-growth.png)、[普通连击／暴击](melee-cast-1-ordinary-true.png)、[麻痺行动入口](paralysis-skip.png)。[AI第二次补齐攻击增益](ai_buff-cast-2-attack_up-true.png)和[AI驱散](ai_dispel-cast-1-dispel-true.png)读取已提交收据；没有让UI反向施加效果。

[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)均覆盖恢复与实际按钮重开。结果页无遗留菜单或后续攻击。图像哈希和初始／最终状态在机器记录中。

## 每次进程的边界

施加3条、阶段4条和最终终态3条的三个进程均退出0。另三个进程分别先完成1／2／3条，然后遭遇下一条夹具问题并退出1；回执只采用它们已经完成的具名范围，不声称整次进程通过。三项问题分别是月花目标在范围外、额外饰品直接追加造成重复槽、F9后尚在菜单展开时输入被正常拒绝。都只修正测试setup或等待条件，没有放宽产品合法性、费用、范围或输入门禁。

新增定向检查还比较带／不带增益的实际普通伤害，确认物理增益不另乘进风火／治疗；核对AI第一次驱散后的第二次无效候选、所有新特效的末帧淡出及篡改存档拒绝。最终完整门禁的实际日志路径及退出码写入本批提交说明。

```sh
tools/godot.sh --screen 0 --script res://tests/capture_stat_magic_review.gd
tools/godot.sh --headless --script res://tests/run_all.gd -- run_support_magic_tests.gd
tools/verify.sh
```

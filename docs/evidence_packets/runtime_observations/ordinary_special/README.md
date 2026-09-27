# 普通交锋／氣刃斬：可玩验收

> evidence: runtime-measured · status: live · tools: capture_ordinary_special_review.gd, run_first_battle_playthrough.gd, run_ordinary_special_tests.gd · updated: 2026-09-17

2026-09-17。[原指令、公式与系统对照](../../static_reverse/original_ordinary_special.md)定义数值证据边界，本页记录Godot实际控件和正常时钟。当前单场景仍由PlayLoop持有唯一战斗状态；原游戏没有被自动操纵，下面不是原版录像。

## 九条实际输入路线

[receipt.json](receipt.json)记录九条路线的技能／普通收据、HP／气力、最终EXP、等级、音频资源、事件顺序和后继。所有路线通过Viewport真实鼠标／键盘／滚轮事件操作已有控件，Engine.time_scale=1；没有替换RNG、修改最终结果或快进演出。

| 路线 | 玩家操作与实际检查 |
| --- | --- |
| ordinary | 选普通攻击→取消→确认→暴击与实际伤害→EXP→下一队友；真实Wait再经过一个敌方行动回到下一回合Leonard |
| critical_kill | 1HP敌人承受暴击，界面显示实际1HP；遗言／KILL／EXP／成长分配之后交接，经验不使用未封顶的暴击量 |
| counter | 普通命中之后目标实际反击并暴击；两次独立出招／impact、HP和经验，完成后才开放菜单 |
| elemental_equipment | 实际装备名劍 狂嵐，取消无损后确认；滚轮看到最后武器附加行，后续真实攻击包含该源风属性附加 |
| critical_equipment | 先装备元素剑，再换死靈血刃、墨鏡；清除旧元素、概率14→24→40；真实攻击使用该概率，允许合法落空且落空不伪造EXP |
| special | 真实氣刃斬选择／取消／确认，源20ST一次扣除，10000物理防御不进入绝技公式；出招声／release→impact→最终EXP→后继 |
| special_silenced | 带禁魔的Leonard仍可施放ST绝技；源特效、实际扣血、经验和行动交接均完成 |
| insufficient | 19ST的实际按钮禁用，点击不扣费、不生成战斗事件；随后Wait正常交接 |
| final_kill | 任务切换后最后1HP敌人被氣刃斬击杀；先遗言／KILL／EXP／金币再胜利；F5/F9恢复保持同一已发放状态，无重抽、重发或重演 |

夹具明确把演员、位置、速度、HP、装备背包和部分分支概率设置为可重复观察条件，保留场景真实WRD。暴击／反击专项使用有效概率100或0，装备路线使用实际刷新后的源概率；成功绝技用100命中，非演出规则回放仍覆盖源98命中与落空。最终击杀从99EXP／连续数1开始。正式第一战没有因此增加装备、改变技能拥有权或提高初始气力。

九条路线跨顺序运行的三个进程保留：第一进程的普通／致命暴击／反击通过，但后来装备真实落空时，脚本错误要求产生EXP；修正为检查零经验。第二进程的两条装备路线通过，但后续绝技暴露未发release的产品缺口；修复后四条受影响的绝技／门槛／终局路线同进程PASS、退出0。receipt逐项保留各进程退出事实，未把前两个失败进程写成整体通过。更早一次脚本误把从0起算的内部round当成从1起算，已改为比较前后加1；正式普通路线已重验。

## 已人工核对的画面

![致命暴击只显示实际1HP](critical_kill-primary-impact.png)

![反击使用自身的暴击收据](counter-counter-impact.png)

![末项武器附加可通过滚轮查看，确认按钮保持可见](elemental_equipment-equip-6.png)

![当前装备叠加后的暴击变化](critical_equipment-equip-216.png)

![禁魔下的氣刃斬与实际伤害](special_silenced-primary-impact.png)

![最后击杀后的终态恢复](final_kill-restored-victory.png)

其余选择图：[实际EXP](critical_kill-experience.png)、[成长分配](critical_kill-growth.png)、[19ST门槛](insufficient-disabled.png)、[下一回合](ordinary-next-round.png)。以上图像SHA-256保存在receipt，字体、混色、暴击文字及精确时钟属于已声明的重制表现。音频检查确认实际播放器推进并释放，对应原资源且事件一次，不冒称原音轨逐帧时刻一致。

## 默认第一战与撤离

[default_routes.json](default_routes.json)是两次不覆盖战斗数值／库存／概率／RNG的正式场景运行，正常开场、实际指令和鼠标重开。默认角色现在使用来源暴击／反击概率及新的原普通／氣刃斬规则，已有AI移动支援和风火／经验链保留。

| 策略 | 本次结果 | 已验证的过程 |
| --- | --- | --- |
| hold | 第7回合撤离胜利，180.094秒 | 开场→NPC普通／魔法交锋→剧情目标切换→两次移动／Wait→撤离→鼠标重开 |
| advance | 第5回合战败，137.753秒 | 主动接敌、普通攻击与原经验、自然积气后第4回合氣刃斬（气力回到1、累计87EXP）→后续战斗→败北对白／结果→鼠标重开 |

![默认撤离胜利](default-hold-result.png)

![默认主动进攻战败](default-advance-result.png)

这只是两次完整路线，不是难度统计；不会因为进攻路线战败调低原伤害或伪造撤离成功。已有多目标风火／状态／驱毒、两人支援贡献、MP不足与禁魔魔法回退的实际流程见[风火／经验](../magic_experience/README.md)和[移动友军援助](../ally_support/README.md)，本轮不重复它们的原函数考证。

## 回归保护与复跑

`run_ordinary_special_tests.gd`将原返回与RNG调用逐项对拍，覆盖queued气力／actual经验的差别、装备换入换出／成长刷新、坏输入零RNG、保存字段拒绝、实际伤害显示及大步长绝技事件／音频清理。既有共同技能、气力、最终EXP、AI、场景与表现合同通过完整`tools/verify.sh`统一验收；最终完整退出码以本批提交说明为准。

门禁中旧气力测试把暴击装备当成未实现，现改用仍未实现的action_twice验证拒绝。旧场景／状态夹具也曾假定普通攻击没有反击、只需播放一个clip或HP只减少毒伤；现保留新的原概率，用非终局HP分别核对反击收据、之后的一次毒伤，以及全部clip完成后才发EXP／交接。单打击文字去重夹具显式隔离反击，完整反击仍由其他场景测试和实际路线覆盖。特技悬停也改为与原channel1的累计命中补偿一致，没有降低规则或放宽产品输入校验。

本次查询内建屏索引为1；布局变化后须重新查询，不硬编码全机永久索引。GUI必须顺序运行，完整门禁清理缓存期间不要打开渲染进程。

```sh
tools/play.sh --screen 1 --script res://tests/capture_ordinary_special_review.gd
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- hold
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- advance
tools/godot.sh --headless --script res://tests/run_ordinary_special_tests.gd
tools/verify.sh
```

演出入口支持在`--`后传本页mode，便于只复验实际受影响路线。Raw输出保存在ignored，产品不依赖这些截图或回执。

# 武器末击效果、行动取消与阶段回退：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_weapon_effect_review.gd, hsltools/data/weapon_effect_trial.py, run_weapon_effect_tests.gd · updated: 2026-09-18

SR-061在`5349143`及已完成大型角色`40acde3`上接续。原函数证据见[武器尾部](../../static_reverse/original_weapon_effects.md)；本页是Godot真实控件、正常时钟的[机器回执](receipt.json)，不能替代原作执行证据。原10%取消／25%附毒与强度、持续时间随机取样没有调高或替换；概率路线通过真实合法轮次重试，次数记录在各route。

## 采用的十五条路线

| 路线 | 实际行为与观察范围 |
| --- | --- |
| poison_series | 14次合法攻击后观察到主攻末击附毒；先移动，再普通／反击各自双击，前击无额外概率，HP／气力／成长完成后保存恢复 |
| cancel_queue | 第15次合法攻击观察到取消未来槽；当次反击仍执行，随后该目标没有毒伤／资源／计时或额外行动，下一轮恢复资格；取消槽跨F5/F9保留 |
| protected_poison、guard_cure | 通用防护在原概率前免疫新毒，已有毒／禁魔／麻痺保持；真实换装不清旧状态，解毒药仍能解除毒 |
| growth_swap | 第一击击杀截断后续，完成EXP／成长并返回第二行动；读档、换为取消武器、移动后双击只读取新装备来源 |
| ai_poison、ai_fallback、ai_silence、ai_wait | AI在3轮中观察到真实附毒；耗完8MP后重选普通武器，禁魔选择物理，无MP且无有效攻击则两次等待；两次行动只执行一次最终状态尾部 |
| ai_cure | 第2次攻击后观察到附毒，AI同伴立即施放原驱毒术；目标身体多格只计一次解除，施法在其自身行动之前完成 |
| phase_cancel | 取消攻击选择保留pending移动；F5/F9后撤回整块占地，仍受禁魔；第一次交锋后取消第二次选择不重发效果，再换武器、移动和攻击，最终只交接一次 |
| trial | 直接打开已发布的开发场景，用实际道具控件把毒牙换成鎮魂之斧，随后保存恢复；没有测试脚本修改该场景的运行时战斗状态 |
| victory、defeat、escape | 提前击杀清敌、致命反击败北、第二行动到达撤离格；结果前所有交锋表现结束，终态恢复不重算，三条均用实际按钮重开 |

窗口640×480、内建屏；屏号以每进程回执为准，显示器布局变化后重新确认。来源039、原WRD和原美术不变。长概率路线增加HP／防御以允许反复交锋，指定速度、反击100和命中补偿、受控039／双击／技能库存均为setup夹具。AI驱毒场的第6回合传令兵离场已在setup标为呈现完毕，避免原剧情移除本场专用治疗者；正式关卡离场逻辑未修改。终态路径使用既有第6回合脚本hook，不能作为默认自然通关或难度统计。

## 画面检查

第一击的[正常状态](poison_series-14-impact-27-83.png)与第二击的[实际中毒](poison_series-14-impact-27-84.png)分别记录，前击没有提前显示末击结果。[取消未来行动](cancel_queue-15-impact-29-60.png)在伤害之后显示，不遮住资源栏。[防护保留旧异常](protected_poison-0-impact-1-1.png)、[防护装备预览](guard_cure-0-equip-229-accessory1.png)和[成长后替换武器](growth_swap-0-equip-29-weapon.png)与实际状态一致。

[AI耗魔后的末击](ai_fallback-1-impact-1-3.png)、[禁魔物理回退](ai_silence-1-impact-1-4.png)、[无有效动作后交接](ai_wait-1-restored-1.png)和[友军驱毒](ai_cure-2-impact-3-3.png)覆盖重新决策与有限反馈。[第二行动恢复](phase_cancel-0-restored-2.png)保留现有提示和菜单；开发场的[入口](trial-0-manual-entry.png)与[实际换装](trial-0-manual-cancel-weapon.png)可直接复现。

三种终态：[清敌](victory-0-result.png)、[败北](defeat-0-result.png)、[撤离](escape-0-result.png)。以上16张图均已检查，哈希记录于机器回执。原空针图不伪造图标，针武器使用已绑定角色攻击声，不复用其他武器的命中别名。数值与状态由不可变收据控制；排版、0.7秒反馈和镜头时钟仍属重制选择。

## 进程边界与失败处理

四条玩家路线有匹配的`WEAPON_EFFECT_RENDER_PASS`和完整JSON，原终端退出码未保留；仅按具名范围采用。随后含附毒／AI附毒的进程记录了下一条AI初始控制等待失败，原终端退出码同样未保留；只采用此前两条。独立AI耗魔重跑退出0，后续同进程的耗魔／禁魔／等待三条也完成，但该进程随后在驱毒夹具失败，退出1，不将其称为整组全绿。

驱毒失败中，多次真实概率重试跨过第6回合，专用026治疗者被原剧情移除，最终已不存在于队列和单位表；修正setup的离场呈现设置后，最后六条在同一进程全部通过，退出0。此前初始控制等待的根因没有被过度归结为菜单算法：后续设置在`_ready`前选择已有开发入口，并仅在验收子进程期间保持显示器唤醒；正式菜单未因此改写。回执保留各次PID、日志和原JSON哈希以及采用范围。

定向回归还补查了：末击落空不回补附毒，HP0原抽样之后不留下尸体毒状态，第二行动等待演出出口，取消选点／撤回移动不重放状态和EXP；替换装备后新增的效果位也在库存提交前校验。它们检查现行事务，不能作为全局原版等价证明。

## 复跑入口与边界

```sh
tools/godot.sh --screen 0 res://game/battle/development/WeaponEffectsTrial.tscn
tools/godot.sh --screen 0 --script res://tests/capture_weapon_effect_review.gd -- phase_cancel ai_cure victory defeat escape
tools/godot.sh --headless --script res://tests/run_weapon_effect_tests.gd
tools/verify.sh
```

内建屏不是0时先按当前显示器布局调整。手动开发场由`hsltools/data/weapon_effect_trial.py`生成并在完整门禁校验，额外HP及供换装的装备是明确演练设置；正式第一／第二战不新增这些授予。最终完整门禁的真实日志和退出码记入本批提交说明。大型角色原6924项／13条既有实玩直接复用，不把它们再算为本批新增路线。

剩余范围包括原MP打击正向分支、随机多状态／弱化、jobWise与全职业初始化、原全局RNG、完整高位dispatcher和精确原时钟；本批没有由字段名、模型候选或测试通过推导这些能力已恢复。

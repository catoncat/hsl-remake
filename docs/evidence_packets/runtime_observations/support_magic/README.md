# 回复／驱毒：实际输入与自保交接

> evidence: runtime-measured · status: live · tools: capture_ai_skill_review.gd, capture_support_magic_review.gd, run_support_magic_tests.gd · updated: 2026-09-16

2026-09-16，Godot正常渲染时钟，实查内建屏0、1470×956，游戏窗口640×480。源规则、18次原数值正常返回／24次应用前段、四条水系效果程序和20帧／6声音见 [支持效果证据](../../static_reverse/original_support_magic.md)。本包证明重制版实际输入链，不能替代原游戏录像或全局AI／EXP证据。

## 场景与输入

[capture_support_magic_review.gd](../../../../tests/capture_support_magic_review.gd)通过真实Viewport鼠标事件点击魔法列表、滚轮滚动、地图目标、状态按钮，并用Esc取消。使用正式Runtime、共享PlayLoop和原地图WRD；确认后不直接赋值HP、MP、状态、结果或队列，也不替换战斗RNG或加快时钟。

夹具明确调整三名角色的位置、HP/MP、速度／控制权和技能授予。玩家施法者001拥有四种水系能力；AI026拥有回复／驱毒，为得到稳定可见路线把AI倾向和使用率设为100。普通回复初始20/100HP，AI残血4/100HP；驱毒夹具毒字为`(10<<16)|2`，友军另有2回合禁魔。继任可控角色是023。场景中的其他演员节点在输入前按这三人重建，避免旧精灵混入画面。上述参数都是验证夹具，正式第一战的角色授予没有变化。

## 已完成的八条路线

下表来自 [精简回执](receipt.json)，数值是本次随机结果，不是固定回复量。

| 实际操作路线 | 可观察结果 | 费用与交接 |
| --- | --- | --- |
| 治癒之水→自己，先取消后确认 | HP20→63，状态页显示63/100 | MP100→94；下一角色，队列index1 |
| 治癒之水→友军，先取消后确认 | 友军HP20→56 | 一次6MP；index1 |
| 生命之水→友军 | 友军HP20→89、+69HP | 一次16MP；index1 |
| 滚轮找到女神之淚→友军 | 回复截断为缺失80HP，20→100 | 一次28MP；index1 |
| 驅毒→相邻友军，覆盖自己 | 两人的毒字归零；自己保持20HP没有收尾毒伤；友军禁魔仍为2 | 一次4MP；两条“解毒”；index1 |
| Wait→残血AI自身治疗 | AI4→44HP，保留回血药 | 一次6MP；仅一个AI行动，index2 |
| Wait→满血中毒AI自身驱毒 | AI毒字归零，保持100HP | 一次4MP；仅一个AI行动，index2 |
| Wait→无MP的残血AI | 自动使用回血药，4→44HP | MP仍0；只执行一次用药，index2 |

全部玩家路线实际取消均保留角色与队列；确认后到完整表现结束才显示后继菜单。后三条从玩家实际点击Wait开始，经过正常AI决策和表现到下一可控角色，没有直接触发“成功”信号。

最初三个路线已完成时，第四条的测试点击落在滚动列表外，导致该进程退出1。保留的是前三条无诊断的完成回执，并明确保存这次失败；修正测试为真实滚轮后，后五条在同一进程`SUPPORT_MAGIC_RENDER_REVIEW_PASS`／退出0。未把早先失败进程标为整批PASS，也没有重复前三条已成立的玩法。

![源费用与可滚动魔法列表](heal_self-list.png)
![自己回复后查看实际HP和MP](heal_self-status.png)
![生命之水的源绿色星光与实际回复](greater_heal-impact.png)
![女神之淚只回复缺失的80HP](life_heal-impact.png)

## 实玩发现并修复的回归

**非当前可控队友无法检查。** 施法交接后，点击上一位可控角色原先会尝试选择其行动，因不在当前队列槽而拒绝，状态页不开。现在该点击进入同一个只读状态页；当前行动者、待确认移动和队列均不改变。Runtime回归覆盖此路径，实际自己治疗路线已经走通并留下上图。

**强光覆盖状态文字。** 首次驱毒截图显示上方文字清楚，但另一条被水环亮光覆盖。根因是世界层文字在法术CanvasLayer5之后仍然画在其下。现有文字改在更高的反馈层，沿既有world→logical投影和字体边界避让，不改数值、命中时刻或0.7秒清除。最终范围驱毒单独复跑PASS／退出0，人工查看如下选帧确认两条文字都清楚；状态页确认禁魔保留。

![最终驱毒文字位于光效上方且彼此错开](cure_area-impact.png)
![驱毒后仍有禁魔，HP保持20](cure_area-status.png)

同一改动影响负面状态，故又独立运行既有`capture_ai_skill_review.gd -- poison`，得到`AI_SKILL_RENDER_REVIEW_PASS`／退出0，三个中毒结果可读，实际移动／施法／一次交接成立。旧风／火路线没有重做。状态套件同时核对层级、当前投影、文字碰撞、上浮期间分离、只读与有限清除。

![最终三目标中毒反馈](poison-feedback-final.png)
![AI主动治疗自己，仍只执行一次行动](ai_heal-impact.png)

**星光尾部被提前截断。** 完整门禁后的末帧检查复现三种回复法术在完成时仍有未淡完的源粒子，产生3项red。现在完成时刻包含最后一批错峰发射及完整淡出，分别补足2～12ticks；release、impact、扣费和回复逻辑不变。这是重制演出内部时序修复，不是新的原作时间测量。

修复后支持套件284项通过，额外的8项检查覆盖四种效果在impact可见、complete时全部淡出。只重新运行受影响的`heal_self greater_heal life_heal`三条实际输入，`SUPPORT_MAGIC_RENDER_REVIEW_PASS`／退出0；记录末尾约0.09秒时仍有半透明粒子且菜单隐藏，后继菜单出现前所有粒子已完成淡出。上表和对应图更新为这次结果，其余五条已成立的输入链继续复用。

![女神之淚末尾仍在淡出，后继菜单尚未打开](life_heal-tail.png)
![全部源粒子消失后恢复后继角色菜单](life_heal-end.png)

各图和路线按上述实际验证范围保留。逐进程范围、退出状态、尾帧采样和图片SHA-256都在回执，不由拼接回执推成一次连续默认关卡流程。

## 自动回归与复跑

`run_support_magic_tests.gd`覆盖284项：原数值／状态提案、自身／友军、三种治疗、范围驱毒、扣费前的坏输入与全无效果拒绝、AI无MP／禁魔／概率未中退回用药、无敌人仍自救、状态／队列一次提交和粒子完成边界。原技能结算134项、AI技能2150项、状态600项及完整场景回归已通过。完整门禁最终结果记录在本批提交说明，入口仍只有`tools/verify.sh`。

```sh
# 已导入资源后运行定向非GUI回归。
tools/godot.sh --headless --script res://tests/run_support_magic_tests.gd

# 先实查当前内建屏；此批索引为0。串行运行，不能同时占用窗口。
tools/play.sh --screen 0 --script res://tests/capture_support_magic_review.gd
# 只复查受影响部分时：
tools/play.sh --screen 0 --script res://tests/capture_support_magic_review.gd -- cure_area
tools/play.sh --screen 0 --script res://tests/capture_ai_skill_review.gd -- poison
```

这些演示会自动发送游戏窗口内输入并退出；不操纵原作、不占用桌面鼠标，也不生成默认场景的额外技能。手动体验正式第一战仍使用`tools/play.sh`。第一战气力循环和默认第9回合撤离／重开沿用已完成的 [stamina验收](../stamina/README.md)；本批不把额外授予的支持法术称为默认第一战可学能力。

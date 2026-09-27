# 技能选择与站位：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_ai_skill_review.gd, run_first_battle_playthrough.gd · updated: 2026-09-16

2026-09-16，640×480 Godot视口、正常时钟。实现和原指令边界见 [技能／站位合同](../../static_reverse/original_ai_skills.md)。本包只记录重制版运行，不冒充原作runtime或全AI等价。

## 隔离技能路线

[capture_ai_skill_review.gd](../../../../tests/capture_ai_skill_review.gd)通过实际Wait控件的鼠标按下／释放进入Runtime；随后使用正常AI、逐格移动、地图施法和后继输入。不调用技能结算捷径，不替换RNG或设置战斗结果。

夹具保留正式WRD阻挡，但明确设置位置、HP400、速度与可控后继，施法倾向100，以及指定技能use_ratio100／另一技能0。酸蚀幻雾使用有源授予的025，未给第一战026增加技能。它证明共享能力和表现联动，不是默认第一战自然遇到三目标毒雾。状态法术的圆环和文字仍为明示重制视觉。

最终精选图片及回执从 `ignored/ai-skill-review/` 提升。回执保留每条路线真实的技能、起止位置、路径、MP前后、命中／状态和下一角色；可以核对一次付款和一次交接。原照片、完整战斗字典与反汇编长输出不作为产品输入。

最终运行输出`AI_SKILL_RENDER_REVIEW_PASS`，退出0，日志无SCRIPT ERROR／ERROR。三条路线均经过可见移动、蓄力或状态前摇、地图效果，再出现enemy023_1的操作菜单；一条AI行动令队列从初始玩家后的索引1前进到2。[本次回执](receipt.json)和图片哈希保存了实际结果。

| 路线 | 实际施法移动 | MP | 结果 |
| --- | --- | --- | --- |
| 026 幻火 | (7,7) → (6,8) | 30 → 22 | 源爆破与单体伤害反馈，完成后交接 |
| 026 风刃 | (7,7) → (7,9) | 30 → 22 | 源风刃波形与单体反馈，完成后交接 |
| 源025酸蚀幻雾 | (8,10) → (7,10) | 100 → 90 | 改选中间单位为中心，原目标仍被覆盖，三个目标各有状态结果，一次付费 |

同分位置消费正常RNG，复跑落点可能不同。第一版图证暴露相邻状态文字挤在一行的问题；最终版本按实际文字和描边范围分层，并保留每个目标的水平位置。回执中的feedback记录三块实际文字边界，截图也已逐张人工检查。测试的免疫／伤害混合结果同样不碰撞，0.7秒反馈清除不变。

![真实Wait输入前的近身法师与战场](fire-before.png)
![移动后在地图上结算幻火](fire-cast.png)
![另一合法站位释放风刃](wind-cast.png)
![酸蚀幻雾覆盖三人，各目标的状态文字分别可读](poison-cast.png)
![范围法术结束后回到下一角色菜单](poison-handoff.png)

## 默认第一战

[run_first_battle_playthrough.gd](../../../../tests/run_first_battle_playthrough.gd)的advance路线从正式开场开始，以真实场景控件推进正常数值；不覆盖HP、伤害、RNG、位置、时间、回合或结果。它与上述合成技能路线分开记在本包回执中。完整目标变更、胜负和鼠标重开由该路线验收；不能由一次路线推论所有自主打法平衡。

本次实际结果：`victory_escape`、第7回合、209.606秒，Leonard剩余HP21；真实鼠标重开成功，进程退出0并输出`FIRST_BATTLE_PLAYTHROUGH_PASS`。开场、近战／气刃斩、目标切换和撤离均走正常流程；回执default_playthrough保留该次操作及表现记录。状态文字修复不改变此路线的规则与默认角色能力，该修复另由上面的三法术可见路线覆盖。

![默认数值第一战第七回合撤离成功](default-result.png)

## 复跑

先查询内建屏编号；本次实测外接为0、内建为1，窗口实际位于内建屏范围。设备布局变化后须重新确认。

```sh
tools/play.sh --screen 1 --script res://tests/capture_ai_skill_review.gd
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- advance
```

两条顺序运行；第一条写 `ignored/ai-skill-review/receipt.json` 和PNG，第二条写 `ignored/first-battle-playthrough/advance/`。检查各自明确PASS、退出0与日志无SCRIPT ERROR／ERROR，再人工查看图片。主完整非GUI门禁仍是 `tools/verify.sh`。

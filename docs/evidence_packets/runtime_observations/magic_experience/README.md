# 原魔法与最终经验：Godot 实际输入验收

> evidence: runtime-measured · status: live · tools: capture_magic_experience_review.gd, run_magic_experience_tests.gd · updated: 2026-09-17

本包对应 SR-048 的 [原伤害](../../static_reverse/original_magic_damage.md)与[最终经验](../../static_reverse/original_experience.md)。`tests/capture_magic_experience_review.gd` 在640×480内建屏窗口发送真实ViewPort鼠标、滚轮和键盘事件，使用正常动画时钟和实际技能事务；不替换战斗RNG，不把期望伤害写回状态。机器回执见 [receipt.json](receipt.json)。

## 已完成的八条路径

| 路径 | 实际验证 |
| --- | --- |
| wind | 选择／取消／重选、原命中与伤害、短HP/MP条→实际数字→最终EXP、下一角色与状态检查 |
| fire_kill | 1HP目标真实死亡、KILL连续数、遗言、最终EXP、保证携带物领取、五点成长实际确认、一次后继 |
| mixed_area | 合成攻击范围下，一个目标存活另一个死亡；每目标反馈与原经验换算、整次付款／成长，禁止中途升级改变下一目标 |
| heal_xp | 实际治疗贡献经原函数换算后发放，显示EXP／升级并保留未用点数 |
| cure_xp | 两友军实际驱毒，各自贡献进入一次合并发放；受援者原禁魔仍在 |
| empty_mp / silence | 真实列表禁用、点击无副作用、取消与正常Wait后继；不增加EXP、伤害或技能序号 |
| final_kill | 撤离目标阶段最后一敌人死亡，EXP及领取先于胜利；终态保留所得经验和未分配点数，F5/F9不重发 |

每个有效施法结束都通过F5/F9检查唯一战斗字典恢复，比较经验、费用、连续数、库存和收据；这次是同进程实际恢复，新字段的序列化另有纯回归。先前跨进程领取验收见 [battle_rewards](../battle_rewards/README.md)，不重复声称这轮又跑了那组完整流程。

## 看图

[短资源条](wind-receiver-bars.png)随后变成[伤害数字](wind-damage-number.png)；多目标条值按实际布局[分开](mixed_area-receiver-bars.png)。[KILL](fire_kill-kill.png)、[最终EXP](fire_kill-experience.png)后进入[五点成长](fire_kill-growth.png)。支援分别有[治疗EXP](heal_xp-experience.png)、[驱毒EXP](cure_xp-experience.png)及[保留禁魔的状态](cure_xp-status.png)。[缺MP](empty_mp-disabled.png)、[禁魔](silence-disabled.png)和[恢复后的胜利](final_kill-restored-result.png)属于不同边界。

首次短条因Godot主题最小高度变成大块，实际看图后改成独立42×7像素条，补几何回归并重跑wind／mixed_area。原录像只提供视觉顺序与样本尺寸线索；当前线条、字体、暗度、时钟和避让是明确重制编排。

## 夹具与失败记录

测试角色使用原图帧，但配置了固定位置／速度、Leonard临时拥有风火与支援技能、100MP及相容的合成成长源。命中设100用于稳定观察，伤害／EXP使用真实RNG。敌人100HP或特定1HP；mixed_area明确改为合成十字，**原風刃／幻火都是单体**。驱毒用合成中毒／禁魔；末敌路线从第6回合后阶段开始。默认第一战授予、敌方模板和真实存档不被修改，测试存档只写ignored路径。

第一进程的六条完整路线有回执，但资源不足／禁魔夹具访问尚不存在的last_combat字段造成脚本错误，因此整个进程退出1，不能以打印PASS当成功。修正后只复跑这两个失败路径和改过短条的两条路径，新的四路线进程退出0、`MAGIC_EXPERIENCE_RENDER_PASS routes=4`且无脚本／资源诊断。被保留路线、失败原因和当前图像哈希全部写入回执，不把此前失败抹掉。

## 命令

先查询内建屏索引，不假定永远为0；以下0为本次查询结果，1470×956。

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 0 --script res://tests/capture_magic_experience_review.gd
# 只重放命中的路径：
tools/godot.sh --screen 0 --script res://tests/capture_magic_experience_review.gd -- wind mixed_area empty_mp silence
tools/godot.sh --headless --script res://tests/run_magic_experience_tests.gd
```

输出`ignored/magic-experience-review/`。Godot wrapper同时检查最终退出码和诊断；引擎打印PASS不能覆盖SCRIPT ERROR。原贡献／发放核对、新规则及交锋／领取／恢复门禁见 `tools/verify.sh`；默认数值整场路线的本次结果记录在协作收口和提交说明中，不将上述合成路径称为自然通关。

默认主场景`advance`已用新伤害／经验跑完：236.855秒，第9回合`victory_escape`，实际使用普通攻击、气刃斩、恢复药和撤离，鼠标重开成功。最终Leonard等级1／EXP85；这条自然路线没有升级，不以夹具升级冒充自然获得。它证明新AI风火与正式战斗循环联动及一次结局，不代表所有策略／随机种子的平衡。日志`ignored/magic-experience/playthrough.log`严格退出0。

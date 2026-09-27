# 战利品领取与单战恢复验收

> evidence: runtime-measured · status: live · tools: capture_battle_reward_review.gd, run_battle_reward_tests.gd, run_combat_aftermath_tests.gd · updated: 2026-09-15

2026-09-15，基线 `e037e0c` 上的奖励切片。发放、库存、成长、队列与领取状态由唯一 PlayLoop 持有，面板只读收据并提交选择。原字段和13处字节比较见 [奖励来源与取舍](../../static_reverse/battle_reward_inputs.md)，该包不证明原版全局随机序列或取物 handler 等价。

## 玩家入口

正常击败敌人后，完整演出、地图遗言／淡出、EXP和金币提示完成，若产生掉落则打开「獲得物品」。点左侧物品，再确认放入所选角色背包；满包时先点一个槽位交换，换出物保留在左侧。Esc／右键取消本次选择；“稍後領取”保留物品，下一角色状态页及结果页可以重开。普通剩余物可二次确认放弃，重要物品不可放弃。

F5 在安静行动、领取或结果页面保存；F9 在这些边界读取。下次启动存在存档时，开场右上角提供“繼續存檔 F9”。玩家单槽存档位于 Godot 的 `user://first_battle.save`；测试使用独立 ignored 路径。旧版／其他配置或校验和不符时拒绝且不替换当前游戏。当前只保存单战，不包含跨关或原作格式兼容，也不支持攻击／对白／未确认物品操作中途保存。

## 已实际执行的路线

`prepare`：真正点击 Attack 与目标，正常时钟经历遗言→淡出→EXP→金币→领取。确认前取消一次，再实际领取一件，用F5保存部分领取状态，退出进程。

`resume`：新的 Godot 进程在正式开场点“繼續存檔”，核对完整状态与前一进程存档相同。继续领取、完成、暂存成长点后只交接给第二位角色一次；完全领取后的F5/F9不重开旧物品、不重发金币。随后独立满包夹具检查交换取消、换出药品留存、放弃取消、延期后状态页重开及确认放弃。末敌夹具通过实际攻击触发真正胜利，领取和结局对白后才显示结果，终态F5/F9不重复奖励。

两次均为 `BATTLE_REWARD_RENDER_PASS`／exit0，无脚本和资源诊断；各进程PID、设置和截图时状态记录在 manifest。所有窗口均位于实际查询的内建屏0、640×480，时钟比例1。源码回归另覆盖范围技能逐目标EXP／一次扣费、升级后MP夹紧、致命反击、主角失败、无掉落、延期跨新交锋、重入确认及坏存档保持原状态。

默认 `advance` 路线也已正常速度执行：七段开场，普通攻击、气刃斩、战中报告和用药，第10回合撤离胜利，229.965秒，鼠标重开成功，`FIRST_BATTLE_PLAYTHROUGH_PASS`／exit0。没有覆盖HP、库存、RNG、伤害或结果；具体行动及最终角色保存在 manifest 的 default_route。它证明这一次路线可玩，不证明所有策略或随机种子的难度。

夹具明确设置邻接敌人1HP、来源重要物品281/282、Leonard99EXP与命中补偿9，以及第二个可控角色／速度；满包夹具填满八槽，末敌夹具使用已报告的撤退阶段。它们不覆盖攻击结果或金币生成，不注入 RNG 回调，但仍不是默认自然打法或自然获得这些道具的证明。正常路线的结果另由本批日志／提交说明记录。

## 原帧与当前画面

原录像 [取物前（重制画面）](../../../screenshots/remake/loot-window.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/16_loot_spoils_screen/frame_003.png`） 显示獲得物品、库存、绿色物品和余额；它是638×480压缩样本，只支持可见过程。本次保留原窗体资源，采用明确确认／延期的重制交互，并不宣称原布局或原暂持取消行为已还原。

当前可看 [领取页](initial-loot.png)、[金币提示](initial-gold.png)、[部分领取后新进程读回](partial-restored.png)、[满包交换](full-exchanged.png)、[放弃确认](abandon-confirmation.png)、[新启动入口](startup-resume.png) 和 [终态恢复](terminal-result.png)。manifest 保存图片哈希与真实回执，raw及测试存档只在 ignored。

## 复跑

```sh
tools/godot.sh --headless --script res://tests/run_battle_reward_tests.gd
tools/godot.sh --headless --script res://tests/run_combat_aftermath_tests.gd
# 先确认实际内建屏编号；前一个进程退出后再执行后一个。
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/capture_battle_reward_review.gd -- prepare
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/capture_battle_reward_review.gd -- resume
tools/verify.sh
```

完整门禁的最终结果以本批提交正文与 `ignored/battle-settlement/verify-result.json` 为准。测试绿、图片真实与原版等价分别判断；原完整 EXP／奖励资格、全局随机流、原存档、跨关、KILL 字样演出和精确动画时钟仍未由这批实现恢复。

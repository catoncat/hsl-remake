# 气力循环与绝技就绪：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_stamina_review.gd, run_first_battle_playthrough.gd · updated: 2026-09-16

2026-09-16。原公式及168组完整原函数执行见 [气力证据](../../static_reverse/original_stamina.md)。本包只记录Godot运行；不把重制截图或测试通过称作原作runtime等价。

## 可玩链路

[capture_stamina_review.gd](../../../../tests/capture_stamina_review.gd)实际点击Wait、物品／装备、确认／取消、状态和绝技目标，通过正常Runtime与时钟完成两条路线。保留正式WRD；三人队伍、位置、HP、速度、初始ST和测试物品是明确夹具，详见 [回执](receipt.json)。没有在启动后直接写损伤、气力或结果，也没有替换RNG。

普通路线从14气力开始，实际受到一次普通攻击后增加6到20；装备路线从8开始，实际装备凝氣之環，再装备鬼面后受击保持8，卸下鬼面后的下一击增加12到20。戒指预览取消没有改变库存或战斗；确认换装沿正常派生刷新，夹具110速度变为实际装备后的速度是预期结果。

两条路线均在20显示可用绝技，状态条为全长的三分之一。点击绝技后取消不扣气；重新选定目标释放气刃斩，20一次扣至0，完整效果结束后回到下一角色菜单，队列只推进一次。

![20气力的状态条](ordinary-status20.png)
![凝氣之環确认前的积气预览](equipment-ring-preview.png)
![鬼面覆盖加倍效果的预览](equipment-mask-preview.png)

## 特写数值时序回归

收尾检查发现：战斗已逻辑结算，特写却直接读取最终气力，受击前会提前显示增长，主攻击还会泄漏尚未播放的反击增长。定向回归先产生8项失败；修复后409项检查通过。特写只从当前strike的气力收据投影before／after，落空时也剔除未来反击的增长，不改实际HP、ST或队列。

增加实际普通路线的前后观察并重新运行，输出`STAMINA_RENDER_REVIEW_PASS`、退出0，无Godot错误。下列截图与断言同时确认受击前14、命中后20；完整普通／反击及落空组合由`run_ordinary_special_tests.gd`覆盖。装备操作的既有图证继续复用。

![受击前保留14气力和原HP](ordinary-hit-before.png)
![命中后显示20气力和扣减HP](ordinary-hit-after.png)

## 默认第一战

[run_first_battle_playthrough.gd](../../../../tests/run_first_battle_playthrough.gd)的advance路线使用正式开场、默认数值和正常时钟，实际控件完成普通攻击、自然积气后的绝技、升级分配、用药、剧情与撤离。未覆盖HP、伤害、位置、随机数或回合结果。

本次`FIRST_BATTLE_PLAYTHROUGH_PASS`：第9回合`victory_escape`、233.288秒，Leonard 33/33HP、18ST、等级2，鼠标重开成功，进程退出0。完整操作回执保留在本包；不能由一次路线推论所有打法平衡。后续特写修复只改只读显示，其新视觉由上方单独复跑覆盖。

![默认数值第一战撤离成功](default-result.png)

## 复跑

本次启动前实查仅有内建屏，索引0、1470×956。屏幕布局变化后重新查询，不能沿用旧批次的屏幕索引。顺序运行：

```sh
tools/play.sh --screen 0 --script res://tests/capture_stamina_review.gd
# 只检查新特写回归时可运行普通路线：
tools/play.sh --screen 0 --script res://tests/capture_stamina_review.gd -- ordinary
tools/play.sh --screen 0 --script res://tests/run_first_battle_playthrough.gd -- advance
```

检查各自PASS、退出0、日志无错误，再人工查看PNG。完整非GUI门禁仍是`tools/verify.sh`；本包的选帧哈希记录媒体身份，不认证原作像素或时钟。

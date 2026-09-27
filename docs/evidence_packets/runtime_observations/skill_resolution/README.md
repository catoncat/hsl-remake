# 共同施法结算的短Control验收

> evidence: runtime-measured · status: live · tools: capture_give_review.gd · updated: 2026-09-13

2026-09-13，Godot4.7.2，内建屏 `(0,0,1470,956)`、游戏窗口 `(160,160)` 和640×480。`tests/capture_give_review.gd -- resolve` 实际返回 `SKILL_RESOLUTION_RENDER_REVIEW_PASS`／exit0。真实Viewport鼠标motion/press/release经控件和正常动画时钟处理，不直接发按钮signal，不用桌面键鼠，不截全桌面。

路线：19ST特殊技禁用→20ST可用→通过Move控件真实移动一格→特殊技选敌→右键取消→重新选敌确认→完整演出后查看下一位角色状态。

实际回执：移动前(15,17)，移动后(14,17)；取消选敌后仍在已移动位置且资源20、pending move与所有units保持；确认后ST0，费用收据before20/amount20/after0；后继 `enemy023_1`、queue.index1；`failures=[]`。19ST时的点击无变化，取消不消费，施放只提交一次。

`resolution-st19-disabled.png`、`resolution-st20-enabled.png`、`resolution-special-next-ally.png` 和 `skill-resolution-receipt.json` 已归档，哈希见 `manifest.json`。最终图像已人工查看，显示下一位可控一般兵的真实状态；其可控资格、速度、目标位置/HP与气力是合成夹具，不代表默认第一战或原版现场数值。

```sh
godot --path . --position 160,160 --resolution 640x480 --script res://tests/capture_give_review.gd -- resolve
```

复跑先确认当前内建屏位置。原公式/初始拥有权/新原包复核限制见 [共同结算证据](../../static_reverse/shared_skill_resolution.md)，完整门禁最终结果在本批提交说明。

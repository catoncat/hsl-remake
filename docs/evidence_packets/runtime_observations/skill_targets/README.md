# 技能目标与范围的短Control验收

> evidence: runtime-measured · status: live · tools: capture_give_review.gd · updated: 2026-09-13

2026-09-13，Godot4.7.2，实际检查只有内建屏 `(0,0,1470,956)`，窗口 `(160,160)`、640×480。`capture_give_review.gd -- targets` 实际取得 `SKILL_TARGET_RENDER_REVIEW_PASS`／exit0，JSON `failures=[]`。输入经Viewport的真实motion/press/release和正常动画时钟，无桌面输入、无直接按钮signal、无全桌面截图。

雷欧纳德位于(15,17)，20ST。真实特殊技选格显示源 `range2Cell` 十字；(16,16)虽然曼哈顿距离2，源矩阵为0，点击该敌人后收到out_of_range，角色/库存/资源/队列不变。右键取消仍为20ST；重新选择(15,15)的轴向敌人，确认后ST=0，演出完成紧接 `enemy023_1`、queue.index=1。最后用Status按钮查看该队友，确认没有跳过后继。

图像 `target-special-source-cross.png` 与 `target-valid-special-successor.png` 和 `skill-target-receipt.json` 已保存；`manifest.json`包含逐文件SHA-256。

这是合成资格夹具：修改了速度、气力、两敌位置/HP及第二位角色的可控标志，其他角色移出测试区域。不是默认第一战新增队友、不是原版现场编队/数值验收。AI不同法术范围、失效目标/未实现效果拒绝由Godot组合回归覆盖；原模式/覆盖/枚举执行边界见 [目标证据](../../static_reverse/original_skill_targets.md)。

```sh
godot --path . --position 160,160 --resolution 640x480 --script res://tests/capture_give_review.gd -- targets
```

复跑前核实内建屏布局。完整非GUI门禁的最终退出结果见本批提交说明。

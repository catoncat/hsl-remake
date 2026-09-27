# 技能费用的真实Control验收

> evidence: runtime-measured · status: live · tools: capture_give_review.gd · updated: 2026-09-13

2026-09-13，Godot4.7.2，内建屏，窗口位置(160,160)、640×480。`tests/capture_give_review.gd -- costs` 已实际执行并取得 `SKILL_COST_RENDER_REVIEW_PASS`／exit0；本页保存复核结果，原始JSON与三张viewport图像保留在 `ignored/give-review/`。本次图像归档操作被工具阻断，**没有把PNG复制为tracked文件**，不能声称图像已归档。规则／原函数证据不依赖这些raw图片。

实际输入为 `Viewport.push_input` 的鼠标移动／按下／释放，经真实控件和正常动画时钟处理；无直接按钮signal、无真实桌面键鼠、无全桌面截图。

验证路线：19ST时特殊技图标禁用，点击保持整个战斗状态；改为专用20ST夹具后图标可用；选择特殊技再右键取消，保持20ST和原队列；重新确认合法目标，ST只扣一次变为0；完整演出后紧接第二位可控角色，queue.index=1。最后通过Status控件查看该后继，证明没有跳过他。

原回执 `ignored/give-review/skill-cost-receipt.json` 的已读取结果：`failures=[]`，`st19_rejected=true`，`initial_stamina=20`，`final_stamina=0`，`payment={resource:stamina,before:20,amount:20,after:0,native_required:20,native_affordable:true,ok:true}`，`next_actor=enemy023_1`，`queue_index=1`。

实际检查的图像名：`cost-st19-disabled.png`、`cost-st20-enabled.png`、`cost-special-next-ally.png`。第一次夹具把测试disabled控件交给了“必须enabled”的通用点击helper，虽有正确最终状态仍报告失败；改为对disabled控件位置发送真实输入后复跑，得到上述PASS和空失败数组。后续必要数据错误检查由定向回归和完整门禁覆盖。

夹具修改角色速度、气力、目标生命和第二位一般兵的可控资格；不代表正常第一战拥有新可控角色、不代表原版现场数值。原版费用和产品边界见 [技能资源证据](../../static_reverse/original_skill_resources.md)。

```sh
godot --path . --position 160,160 --resolution 640x480 --script res://tests/capture_give_review.gd -- costs
```

复跑前核对当前内建屏位置，不沿用不匹配的桌面坐标。完整门禁最终退出结果记录在本批提交说明。

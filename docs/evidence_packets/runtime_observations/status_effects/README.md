# 状态／解毒 Control 验收

> evidence: runtime-measured · status: live · tools: capture_status_review.gd · updated: 2026-09-13

2026-09-13，当前 Godot 4.7.2，内建屏 `1470×956` 上的单个 `640×480` 游戏窗口，位置 `(160,160)`。真实 `Viewport.push_input` 鼠标移动／按下／释放与取消键事件；没有操作系统键鼠、整桌面截图或直接 emit 按钮信号。

夹具给 Leonard 中毒强度7／持续2、禁魔持续2，并将一个原友军设为下一可控角色。正常开场配置没有额外异常、物品或队友。路线：Status → Item → Use → 解毒草 → 目标 → 右键取消 → 再选择／确认 → 下一队友；随后健康目标尝试被拒。

图证：`poison-and-no-magic.png` 显示满血与两种状态；`antidote-target.png` 显示目标选择；`cured-next-ally.png` 显示解毒反馈及下一队友菜单；`healthy-target-refusal.png` 显示不能对健康目标使用解毒草。`receipt.json` 记录空失败列表、清零的中毒字段、禁魔只递减一次、只消耗一件解毒草、正确后继和健康目标拒绝。文件身份见 `manifest.json`。

```sh
godot --headless --path . --import
# 先重新确认内建屏坐标，不能照搬多屏布局：
godot --path . --position 160,160 --resolution 640x480 \
  --script res://tests/capture_status_review.gd
```

实际结果：`STATUS_RENDER_REVIEW_PASS`、exit0。首次捕获下一队友菜单时仍处于展开动画，夹具增加正常0.3秒等待后复跑通过；没有为了截图改变产品动画。原版字段与规则为静态证据，本次没有原函数执行，不把夹具施加的异常当成正常第一战内容。

# 状态施加与AI行动后的显示验收

> evidence: runtime-measured · status: live · tools: capture_status_application_review.gd · updated: 2026-09-14

2026-09-14，Godot实际640×480窗口，位置 `(1760,400)`，位于本机内建显示器范围 `(1600,251,1470,956)`。使用 `Viewport.push_input` 发送真实 Control／地图鼠标事件；不发送桌面鼠标键盘，不捕获整屏。

这是重制版的显式夹具，不是原作自然游玩，也不更改正常第一战。原025拥有酸蝕幻霧；夹具给予100MP和控制权，设定法术成功率100以固定显示路径。目标026为1000HP、已有1次禁魔；队列、位置和反击设为有界路线。数值／成功率边界另由 [原状态证据](../../static_reverse/original_status_application.md) 的非GUI样例验证。

| 输入与画面 | 人工检查／实际规则结果 |
| --- | --- |
| [魔法菜单](magic-list.png)：点击原BCMD09，再取消并重新打开 | 显示实际拥有的酸蝕幻霧及MP10；按钮文字和取消均在窗体内 |
| 选择法术并点击地图敌人 | 两个敌人在范围内各自施毒；025 MP100→90，只有一笔扣费 |
| [施法后查看法师](poison-and-silence.png) | HP1000/1000、MP30/30，状态“中毒／禁魔”；下一位为Leonard |
| Leonard实际点击Wait，法师行动，交接到下一名可控队友 | 法师未消费MP；完成普通行动后HP1000→976，中毒剩余2→1且强度24不变，禁魔1→0 |
| [再次查看法师](after-ai-expiry.png) | HP976/1000、MP30/30，状态仅“中毒”；没有跳过下一可控队友 |

[receipt.json](receipt.json) 保留这条路线的压缩结果、夹具说明、窗口边界和零失败记录。检查了字体、边框、状态文字与血蓝条，无溢出或遮挡。新技能短动画为重制表现，不宣称原版逐帧等价。

```sh
godot --path . --position 1760,400 --resolution 640x480 \
  --script res://tests/capture_status_application_review.gd
```

窗口位置必须按运行机器的内建屏调整。脚本35秒有界，成功输出 `STATUS_APPLICATION_RENDER_REVIEW_PASS`，原始截图和收据位于 `ignored/status-application-review/`。对应修复包括魔法选择后的地图阶段同步、取消恢复可见菜单、旧按钮和禁用按钮拒绝、范围一次扣费与公共行动收尾。

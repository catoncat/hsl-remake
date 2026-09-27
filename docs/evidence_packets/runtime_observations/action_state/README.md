# 公共行动状态的短视觉验收

> evidence: runtime-measured · status: live · tools: capture_give_review.gd · updated: 2026-09-13

2026-09-13，Godot 4.7.2，640×480。运行前 CoreGraphics 显示当前只有内建屏 `(0,0,1470,956)`；本次窗口 `(160,160)`。读取的是游戏 viewport 图像，不截全桌面。输入通过 `Viewport.push_input` 的 motion/press/release 进入真实 Control 和场景输入，演出使用正常时钟，没有真实桌面键鼠或直接按钮 signal。

`tests/capture_give_review.gd -- actions` 已实际完成、`ACTION_STATE_RENDER_REVIEW_PASS`、exit0；完整状态记录在 `action-state-receipt.json`，`failures=[]`。PNG和回执哈希见 `manifest.json`。

| 路线 | 检查内容 | 图证 |
| --- | --- | --- |
| Wait → next ally | 下一位角色保留控制，额外旧释放事件不再触发Wait | `action-wait-successor.png` |
| Drop → Attack → next ally | 丢弃一件后仍能攻击；未移动的攻击演出完成后只交接一次 | `action-drop_attack-successor.png` |
| Move → Cancel → Move → Give → next ally | 撤销回到原位置并立即显示可达格；直接重选移动；Give会话关闭前不换人，完成后只推进一次 | `action-move-cancel-reselect.png`、`action-move_cancel_give-successor.png` |
| Special → next ally | 未移动特殊技在完整演出后交接，后继未被跳过 | `action-special-successor.png` |

四条路线的后继均为 `enemy023_1`，queue.index=1／round=0，phase=`action_menu`、无AI播放；Wait与Special不改变库存，Drop与Give只扣相应一件。Move路线由(15,17)移动到(14,17)，取消恢复(15,17)再移动到(14,17)，Give后最终位置保持(14,17)。

**夹具边界：** 速度、气力、目标生命和第二位一般兵的可控资格均为专门测试设置，不代表正常第一战增加了队友或原版现场初始化。显示第二位角色状态用于证明后继控制，截图本身不能证明原版等价。命令原证据与已知差异见 [公共矩阵](../../static_reverse/original_action_state_machine.md)。

```sh
godot --path . --position 160,160 --resolution 640x480 --script res://tests/capture_give_review.gd -- actions
```

复跑前先定位当前内建屏；坐标不适用于所有显示器布局。完整非GUI门禁见本批提交说明。

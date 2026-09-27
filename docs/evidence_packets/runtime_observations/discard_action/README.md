# 丢弃后继续行动

> evidence: runtime-measured · status: live · tools: capture_equipment_review.gd · updated: 2026-09-13

Observed: 2026-09-13，Godot 4.7.2。受控第一战库存夹具，验证当前重制版的玩家操作；原版静态路径见 [original_item_actions.md](../../static_reverse/original_item_actions.md)。这不是原作录像或自然通关记录。

## 路线与结果

初始库存为 `[281,241,241,246,0,0,0,0]`，HP17/30。场景正式 Runtime 运行，用 `Viewport.push_input` 投递鼠标移动／按下／释放，由实际菜单和 Control 处理，不直接发送按钮 signal，不占用系统鼠标。

从 Item→Drop 进入列表，重要物品通行證保持禁丢。回復藥先预览后取消，完整战斗状态不变；重新确认后只丢一件，当前队列与玩家控制保留。接着实际点 Move，移动 `(15,17)→(16,17)`；移动后再丢第二件药，pending move 仍可撤销。右键撤销移动返回原格，两个已丢物品没有重新出现；之后点 Attack 仍可选择攻击。最终库存 `[281,246,0,0,0,0,0,0]`，队列始终不变，AI 未启动。

| 文件 | 检查内容 |
| --- | --- |
| `discard-action-menu.png` | 第一次丢弃后仍有移动、攻击、道具和待机菜单 |
| `discard-move-select.png` | 真正点击移动后出现合法移动范围 |
| `discard-inventory-after.png` | 两次丢弃及撤销移动后只剩通行證和解毒草，道具2/8 |
| `discard-receipt.json` | 无失败、队列不变、实际移动格、撤销结果与最终库存 |

`DISCARD_ACTION_RENDER_REVIEW_PASS`，进程 exit0，图像已人工检查。`manifest.json` 保存上述文件的 SHA-256。

## 复跑

```sh
godot --headless --path . --import
godot --path . --position 1700,350 --resolution 640x480 \
  --script res://tests/capture_equipment_review.gd -- discard
```

本次启动前 CoreGraphics 确认内建屏为 `(1600,251) 1470×956`，640×480 窗口完整位于其中。截图取自该游戏根 viewport，没有截桌面。其他显示布局先重新确认位置。输出在 `ignored/equipment-review/discard-*`。

原作暂持后取消可能把物品放到首空槽，满包时会保持窗口；当前重制版在确认前不取出物品，取消不改变顺序。此交互差异保留，不以当前 Control 验收推断原完整拖动、连续给予或整理等价。较早 `item_rules/` 中丢弃后交接行动的记录属于已替换的旧行为。

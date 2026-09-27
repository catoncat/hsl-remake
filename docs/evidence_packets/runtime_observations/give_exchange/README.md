# 给予／交换 Control 鼠标验收

> evidence: runtime-measured · status: live · tools: capture_give_review.gd · updated: 2026-09-13

2026-09-13，Godot 4.7.2，640×480。运行 `tests/capture_give_review.gd`，实际取得 `GIVE_RENDER_REVIEW_PASS`、exit0。单窗口位置 `(1700,350)`；启动前已检查内建屏 bounds `(1600,251,1470,956)`，外接屏未用于验收。图像来自该游戏 viewport，没有截桌面。

使用开发入口和专门的合成库存／相邻友军位置；不修改正常开场库存。所有选择、确认、取消、移动撤销由 `Viewport.push_input` 鼠标 motion/press/release 经真实 Control 或既有地图输入处理完成，无桌面键鼠、无直接按钮信号。源函数、原版时钟及原版 UI 全流程未由这次验收证明；对应静态证据和重制边界见 [给予／交换证据](../../static_reverse/original_give_exchange.md)。

| 路线 | 结果／图证 |
| --- | --- |
| Item→Give→选择同伴→选择源物品及空位→取消／确认 | 取消不改任何战斗状态；目标选择画面 `give-target-choice.png` |
| 同一会话连续给出两件241 | 给出方 `[246,281,0,0,0,0,0,0]`；接收方 `[246,241,241,0,0,0,0,0]`；确认期间队列不变，明确结束后推进一次。`give-two-items.png` |
| 双方8/8满包，选择241交换目标246 | 确认预览可取消且库存不变；确认后给出方尾格246、目标8件241，没有丢失／复制。`full-exchange-confirmation.png`、`full-exchange-result.png` |
| 真实鼠标移动→Give预览取消→返回目标→结束空会话→右键撤销移动 | 队列未变，坐标回到原点，库存原顺序保持；准确布尔结果在 `receipt.json` |

`manifest.json` 保存所有图证和回执 SHA-256。首次渲染后发现拉伸的小窗背景和仅显示职业名，已改为原资源九宫格边框及原人物名称，重跑全部路线后保存本目录。

```sh
godot --path . --position 1700,350 --resolution 640x480 --script res://tests/capture_give_review.gd
```

坐标只适用于上述显示器布局；复跑前重新确认内建屏。原始输出位于 `ignored/give-review`，本目录仅保存经过检查的最终样本。完整非 GUI 门禁的最终退出结果见包含本目录的本地提交说明。

# 公共行动交接：Control 操作回执

> evidence: runtime-measured · status: live · tools: capture_give_review.gd, run_action_handoff_tests.gd · updated: 2026-09-13

2026-09-13，Godot 4.7.2，640×480，内建屏窗口 `(1700,350)`。运行 `tests/capture_give_review.gd -- handoff` 两次，最终输出 `ACTION_HANDOFF_RENDER_REVIEW_PASS`，已取回 exit0。第二次增加后继选择移动的图像采样，所有操作再次通过。

原第一战开发入口中，仅在夹具里将 `enemy023_1` 设为第二位可控角色，速度排序为 Leonard30、该角色29；正常产品 roster 未改。输入为 viewport 鼠标 motion/press/release，实际点击 Wait／Item／Use／Give、目标、确认、结束、Status和Move，无直接信号、无桌面键鼠。首位角色HP10，包中 `[241,241,246,0,0,0,0,0]`。

| 首位角色操作 | 队列／后继 | 首位角色结果 | 后继验证 |
| --- | --- | --- | --- |
| Wait | index1，round0，`enemy023_1` | HP10，库存原样 | 可打开自己的Status，关闭后可选择Move |
| 使用241治疗自己 | index1，round0，`enemy023_1` | HP30，库存`[241,246,0,0,0,0,0,0]` | 可打开自己的Status，关闭后可选择Move |
| 给出241并结束给予 | index1，round0，`enemy023_1` | HP10，库存`[241,246,0,0,0,0,0,0]` | 可打开自己的Status，关闭后可选择Move |

已通过工具查看实际渲染：Use 后状态面板显示一般兵及其自身装备／数值；Wait 后移动格围绕该后继角色，Leonard 保持在相邻格。回执 failures为空，三路 `next_player_can_move=true`。这些是 Godot 夹具验收，不能作为原游戏多队友初始化或原版数值等价证据。

最终图片与完整 JSON 输出目前位于 `ignored/give-review/handoff-*.png`、`handoff-receipt.json`；随后把这组媒体复制为 tracked 图证的工具调用被拦截，未换入口重试，也未创建媒体哈希清单。本文件是已核对结果的文字回执和复跑入口，**没有声称图片已归档进本目录**。产品及自动门禁不依赖 ignored 中这些文件。

```sh
godot --path . --position 1700,350 --resolution 640x480 --script res://tests/capture_give_review.gd -- handoff
godot --headless --path . --script res://tests/run_action_handoff_tests.gd
```

坐标适用于本轮已查明的内建屏 `(1600,251,1470,956)`；显示器布局变化后先重新定位。规则、原状态路径和剩余范围见 [公共行动状态](../../static_reverse/original_action_state_machine.md)。完整门禁最终结果记录于本批本地提交说明。

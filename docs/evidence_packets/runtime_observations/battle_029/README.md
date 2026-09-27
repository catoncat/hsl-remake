# 約瑟河（level 29）

> evidence: runtime-measured · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

本 packet 记录 Godot 重制版正式战斗 level 29 的窗口化实际运行，证据等级为 **runtime-measured**。它不是原版 EXE 现场，也不证明原版等价。

## 入口

窗口化回执由以下命令生成：

`timeout 900 tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=29`

场景入口为 `content/battles/battle_029.json`。该正式场景由 `tools/hsltools/levels/battle.py` 从 STORY029 opening/bindings、battle029 seed 的 STORY endpoints 与 winfail、以及已审核 actor templates 组装。

## Manifest

[review_manifest.json](review_manifest.json) 摘录了这次窗口化运行的 schema、level、capture labels、first-control roster、结果与 failures。完整 34 张 capture frame 留在 `ignored/battle-029-review/`；本 packet 只保留 3 张审阅图。

## Captures

| Frame | Runtime observation |
| --- | --- |
| [first-control.png](first-control.png) | opening 完成后的首次控制状态，formal battle roster 已加载 |
| [win-dialogue-1688.png](win-dialogue-1688.png) | win_0 后的約瑟河关键对白 |
| [result.png](result.png) | 强制胜利夹具后的结果页，`victory_boss` |

## Boundary

Opening walk/camera timing、对白 pacing、结果页文案与 capture 使用的强制清敌夹具是重制表现或验证读法，属于 **provisional**，不能升级为原版规则。WINFAIL029 的 next-level/world-map writes 由现有 winfail/skip_battle hand-off 记录；本 packet 不证明其原版调度时序。

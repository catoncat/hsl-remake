# 沙羅尼亞近郊（level 34）

> evidence: runtime-measured · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

本 packet 记录 Godot 重制版正式战斗 level 34 的窗口化实际运行，证据等级为 **runtime-measured**。它不是原版 EXE 现场，也不证明原版等价。

## 入口

窗口化回执由以下命令生成：

`timeout 900 tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=34`

场景入口为 `content/battles/battle_034.json`。该正式场景由 `tools/hsltools/levels/battle.py` 从 STORY034 opening/bindings、battle034 seed 的 STORY endpoints 与 winfail、以及已审核 actor templates 组装。

正式战斗额外以 `scenario_rules.initial_status_overrides.win=[0]` 武装 win_0：STORY034 预览在正式战斗控制交接前只写入 fail/event status；这是为可玩正式战斗保留 source win_0 时间线的显式重制边界，属于 **provisional**。

## Manifest

[review_manifest.json](review_manifest.json) 摘录了这次窗口化运行的 schema、level、capture labels、first-control roster、结果与 failures。完整 16 张 capture frame 留在 `ignored/battle-034-review/`；本 packet 只保留 3 张审阅图。

## Captures

| Frame | Runtime observation |
| --- | --- |
| [first-control.png](first-control.png) | opening 完成后的首次控制状态，formal battle roster 已加载 |
| [win-dialogue-2021.png](win-dialogue-2021.png) | win_0 后的緹娜关键对白 |
| [result.png](result.png) | 强制胜利夹具后的结果页，`victory_boss` |

## Boundary

Opening walk/camera timing、对白 pacing、结果页文案、event_0／event_1 插入与模式切换时序、以及 capture 使用的强制清敌夹具是重制表现或验证读法，属于 **provisional**，不能升级为原版规则。WINFAIL034 没有 next-level，现有 town/big-map writes 与 `actSetBMWalkToPoint` 只按既有 hand-off 路径记录；本 packet 不证明其原版调度时序。

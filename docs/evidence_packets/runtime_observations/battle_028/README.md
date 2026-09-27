# 眾神的宮殿遺址（level 28）：正式戰鬥

> evidence: runtime-measured; resource-derived; provisional · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版的窗口化运行回执（`tests/capture_battle_review.gd -- --level=28`），属于 **runtime-measured**，不是原 EXE 现场。关卡 seed、预览开场、WINFAIL 与演员资源为 **resource-derived**；镜头、走位和强制胜利夹具属于 **provisional** 重制读法。

## 入口

`content/battles/campaign.json` 将 level 28 注册为 `content/battles/battle_028.json`；正式战斗由 `python3 tools/hsl.py generate level_battle:28` 组装，`story_028.json` 保留为独立预览回归。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 开场取景 |
| [first-control.png](first-control.png) | 首次控制：16 名单位、7 个受控槽、`interaction=action_menu` |
| [win-dialogue-2473.png](win-dialogue-2473.png) | source-timed `event_2` 后的胜利演出 |
| [result.png](result.png) | 结果页：`victory_script`、`win_0` |

[manifest.json](manifest.json) 保存完整捕获摘要；完整帧留在 `ignored/battle-028-review/`。

## 边界

- WINFAIL028 的 `win_0` 由第 4 回合 round-display/event 链武装；回执夹具只证明当前重制流转，不证明原版调度或节奏。
- 九个非对齐源终点的最近合法落点、对象表现、AI 与奖励时序保持 **provisional**。

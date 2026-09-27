# 龍之息（火山，level 13）：正式戰鬥

> evidence: runtime-measured; resource-derived; provisional · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版的窗口化运行回执（`tests/capture_battle_review.gd -- --level=13`），属于 **runtime-measured**，不是原 EXE 现场。关卡 seed、预览开场、WINFAIL 与演员资源为 **resource-derived**；镜头、走位和到达夹具属于 **provisional** 重制读法。

## 入口

`content/battles/campaign.json` 将 level 13 注册为 `content/battles/battle_013.json`；正式战斗由 `python3 tools/hsl.py generate level_battle:13` 组装，`story_013.json` 保留为独立预览回归。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 开场取景 |
| [first-control.png](first-control.png) | 首次控制：16 名单位、7 个受控槽 |
| [win-dialogue-1788.png](win-dialogue-1788.png) | 到达目标后的胜利演出 |
| [result.png](result.png) | 结果页：`victory_escape`、`win_0` |

[manifest.json](manifest.json) 保存完整捕获摘要；完整帧留在 `ignored/battle-013-review/`。

## 边界

- `win_0` 是源到达矩形 `(416,288)-(448,288)`；回执夹具只证明当前重制逻辑可达，不证明原版脚点、镜头或节奏。
- 火山对象表现、脚本时序、AI 与奖励持久化保持 **provisional**。

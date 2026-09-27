# 悲嘆之湖（level 41）：正式战斗

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

记录的是 Godot 重制版窗口化运行（`tests/capture_battle_review.gd -- --level=41`），属于 **runtime-measured** 回执，不是原 EXE 现场。关卡 seed、预览开场、WINFAIL 与演员资源为 **resource-derived**；镜头、走位和强制胜利夹具是重制读法，不能据此声称原版等价。

## 入口

`content/battles/campaign.json` 将 level 41 注册为 `content/battles/battle_041.json`；胜利结果按当前正式 profile 进入 73 兄弟的抉擇。战斗由 `python3 tools/hsl.py generate level_battle:41` 组装，预览 `story_041.json` 保留为独立回归输入。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 开场取景 |
| [first-control.png](first-control.png) | 首次控制：24 名单位、8 个受控槽、`interaction=action_menu` |
| [dialogue-2155.png](dialogue-2155.png) | 开场关键对白 |
| [win-dialogue-2179.png](win-dialogue-2179.png) | 强制胜利后的演出 |
| [result.png](result.png) | 结果页：`victory_boss`、`win_0` |

[manifest.json](manifest.json) 是从完整窗口化 capture 中筛选的摘要；完整帧留在 `ignored/battle-041-review/`。

## 边界

- 强制胜利夹具只证明开场、结果页和战役交接流转，不证明 AI、平衡或原版节奏。
- 终点、镜头与表现层的对应关系保持 **provisional**；后续应以可重复 runtime measurement 或更直接的原作证据替换。

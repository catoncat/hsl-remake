# 利魯瑪山地 再訪（level 904）：正式战斗

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

记录的是 Godot 重制版窗口化运行（`tests/capture_battle_review.gd -- --level=904`），属于 **runtime-measured** 回执，不是原 EXE 现场。关卡 seed、预览开场、WINFAIL 与演员资源为 **resource-derived**；镜头、走位和强制胜利夹具是重制读法，不能据此声称原版等价。

## 入口

大地图 event 904 现在进入 `content/battles/battle_904.json`，而不是预览 `story_904.json`；`content/battles/campaign.json` 保留 level 904 的特别关注册。战斗由 `python3 tools/hsl.py generate level_battle:904` 组装。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 开场取景 |
| [first-control.png](first-control.png) | 首次控制：5 名单位、1 个受控槽、`interaction=action_menu` |
| [dialogue-1457.png](dialogue-1457.png) | 开场关键对白 |
| [win-dialogue-1464.png](win-dialogue-1464.png) | 强制胜利后的演出 |
| [result.png](result.png) | 结果页：`victory_optional_clear`、`win_0` |

[manifest.json](manifest.json) 是从完整窗口化 capture 中筛选的摘要；完整帧留在 `ignored/battle-904-review/`。

## 边界

- 强制胜利夹具只证明开场、结果页和战役交接流转，不证明 AI、平衡或原版节奏。
- 再访脚本的增援、终点与镜头表现保持 **provisional**；证据包只记录当前重制运行，不扩大为原版全局语义。

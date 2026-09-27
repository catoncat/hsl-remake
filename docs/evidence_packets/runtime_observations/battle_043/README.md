# 大地的裂縫（level 43）：正式战斗回执

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行（tests/capture_battle_review.gd -- --level=43），属于 runtime-measured，不是原 EXE 现场。STORY043／WINFAIL043 的演员、脚本 token、物件与地形输入为 resource-derived；开场镜头、走位时钟、强制胜利夹具与结果页为 remake pacing，不能据此声称原版等价。

## 组装结果

python3 tools/hsl.py generate level_battle:43 生成 25 名初始单位、7 名受控玩家、18 名敌方单位。条件槽 008／009 保留在 cast 但本次开场未安装。WINFAIL043 的 actDeletePosObject(816,111,4,defProcStandObject) 与 actGetItem(16,1) 通过共享 coordinator 记录和消费；坐标命中是对象请求，不猜测单位离场。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 窗口化开场画面 |
| [first-control.png](first-control.png) | 首次控制：25 名单位、7 名受控玩家 |
| [dialogue-2560.png](dialogue-2560.png) | 开场关键对白 |
| [win-dialogue-2561.png](win-dialogue-2561.png) | 胜利段对白 |
| [result.png](result.png) | victory_optional_clear / win_0 结果页 |

[review_manifest.json](review_manifest.json) 是完整窗口化运行的精简记录；完整截图留在 ignored/。强制胜利夹具只证明流转，不证明 AI、平衡或原版节奏。

## 边界

原版站立物件命中边界、地形碰撞、奖励／经验与 battle scheduler 仍 provisional；替代依据是 tracked battle seed、预览绑定、WINFAIL token 解释器和本次窗口化回执。

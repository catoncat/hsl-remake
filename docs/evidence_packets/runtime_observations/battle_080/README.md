# 禁忌之魂・墳場地下（level 80）：正式战斗回执

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

本包记录 Godot 重制版的窗口化运行（tests/capture_battle_review.gd -- --level=80），属于 runtime-measured，不是原 EXE 现场。STORY080／WINFAIL080 的演员、脚本 token、物件与地形输入为 resource-derived；开场镜头、走位时钟、强制胜利夹具与结果页为 remake pacing，不能据此声称原版等价。

## 组装结果

python3 tools/hsl.py generate level_battle:80 生成 30 名初始单位、7 名受控玩家、23 名敌方单位。条件槽 008／009 保留在 cast 但本次开场未安装。WINFAIL080 是脚本推进：到达两个位置后删除站立物件并分别发放物品 112／15；每条链末尾的 `actCheckEventNotExist 1,<另一条>` 是闸门（R6-L11，static-derived，`0x450840` case 0x72），所以只有第二个宝物到手才武装 win_0——下方宝物在墙后，墙要 怨念體 068 倒下（event 3）才开，即必须先打倒它（`run_winfail_rules_tests` 的 80 关宝箱顺序）。怨念體 按对象 `obj_Mode engADDCOLOR` 加色绘制；落点仍是 provisional (25,9)。回执夹具提交 source win status 仅用于验证流转。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [00-framed.png](00-framed.png) | 窗口化开场画面 |
| [first-control.png](first-control.png) | 首次控制：30 名单位、7 名受控玩家 |
| [dialogue-2487.png](dialogue-2487.png) | 开场关键对白 |
| [dialogue-2488.png](dialogue-2488.png) | 开场关键对白 |
| [result.png](result.png) | victory_script / win_0 结果页 |

[review_manifest.json](review_manifest.json) 是完整窗口化运行的精简记录；完整截图留在 ignored/。80 的强制胜利夹具只证明脚本结果流转，不证明 native 事件触发时序。

## 边界

原版站立物件身份、到达判定、事件 scheduler、奖励／经验与镜头时序仍 provisional；替代依据是 tracked battle seed、预览绑定、WINFAIL token 解释器和本次窗口化回执。

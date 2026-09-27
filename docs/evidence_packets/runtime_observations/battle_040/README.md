# 聖靈之森（level 40）：正式战斗

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

记录的是 **Godot 重制版**的实际运行（`tests/capture_battle_review.gd -- --level=40`，窗口化，remake pacing），不是原 EXE 现场。WINFAIL040 的 section／action 顺序、EVEF 编队、演员模板与寶藏内容为 resource-derived；开场镜头、脚本增援的表现时钟、阻挡格与结果页文案是重制读法，不能据此声称原版等价。

## 入口

大地图的 level 40 入口进入 `content/battles/battle_040.json`，由 `python3 tools/hsl.py generate level_battle:40` 从开场预览、战斗 seed、WINFAIL040 与已审核演员模板组装。正式场景首次控制回执为 17 名单位、8 名受控成员；咕嚕条件成员在本次开场 roster 中 skipped，脚本模板保留 3 个运行时安装槽。

正式 profile 的初始目标为 clear，`win_0` 的结果页回执为 `victory_boss`；第 14 回合脚本增援与条件成员安装的具体表现时序保持 provisional。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场后首次控制：17 名单位、8 名受控 |
| [dialogue-2148.png](dialogue-2148.png) | 开场关键对白 |
| [win-dialogue-2151.png](win-dialogue-2151.png) | 强制胜利后的结果对白 |
| [result.png](result.png) | 结果页：`victory_boss`（`win_0`） |

[review_manifest.json](review_manifest.json) 是窗口化运行记录。自动验证：`BATTLE_SWEEP_TESTS_PASS battles=92`、`STORY_MODE_WALKTHROUGH_PASS steps=48`、`STORY_SCENE_TESTS_PASS`、`WORLD_MAP_TESTS_PASS`、`SCRIPT_WAIT_TESTS_PASS checks=447`，以及 level 40 的离线组装检查。

## 边界

- 强制胜利夹具只证明 formal opening → first control → result → campaign hand-off 的流转，不证明 AI、平衡、原版节奏或原版等价。
- 第 14 回合的六名脚本增援、咕嚕条件安装、阻挡格落点与表现时钟仍是 provisional；需以 runtime-measured 对照或 bounded native probe 替换。

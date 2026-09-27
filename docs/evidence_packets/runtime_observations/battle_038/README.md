# 幽闇墳場（level 38）：正式战斗

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

记录的是 **Godot 重制版**的实际运行（`tests/capture_battle_review.gd -- --level=38`，窗口化，remake pacing），不是原 EXE 现场。WINFAIL038 的 section／action 顺序、EVEF 编队、三格到达区与寶藏内容为 resource-derived；开场镜头、脚本到达区的网格投影、结果页文案与强制胜利夹具是重制读法，不能据此声称原版等价。

## 入口

大地图的 level 38 入口进入 `content/battles/battle_038.json`，由 `python3 tools/hsl.py generate level_battle:38` 从开场预览、战斗 seed、WINFAIL038 与已审核演员模板组装。正式场景首次控制回执为 42 名单位、7 名受控成员；033／034／035 的涌入记录保留在正式脚本数据，咕嚕与克羅蒂条件成员在本次开场 roster 中 skipped。

WINFAIL038 的 win_0 结果动作记录前往 80,80；event_1–7 处理现有可控成员的到达区离场，条件 event_8/9 因成员缺席跳过。正式 JSON 的 escape zone 为 [7,3]、[7,4]、[7,5]，该网格投影与阻挡格解释保持 provisional。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场后首次控制：42 名单位、7 名受控 |
| [dialogue-2482.png](dialogue-2482.png) | 开场关键对白 |
| [win-dialogue-2485.png](win-dialogue-2485.png) | 到达区流程的结果对白 |
| [result.png](result.png) | 结果页：`victory_script`（`win_0`） |

[review_manifest.json](review_manifest.json) 是窗口化运行记录。自动验证：`BATTLE_SWEEP_TESTS_PASS battles=92`、`STORY_MODE_WALKTHROUGH_PASS steps=48`、`STORY_SCENE_TESTS_PASS`、`WORLD_MAP_TESTS_PASS`、`SCRIPT_WAIT_TESTS_PASS checks=447`，以及 level 38 的离线组装检查。

## 边界

- 强制胜利夹具把正式 roster 中的可控成员放入 escape zone，按 source timing 触发到达区 event 与 win_0；它只证明流转，不证明 AI、平衡、原版节奏或原版坐标。
- 033／034／035 的增援落点、三格到达区的原始像素到网格映射、条件成员安装时序与部分表现时钟仍是 provisional；需以 runtime-measured 对照或 bounded native probe 替换。

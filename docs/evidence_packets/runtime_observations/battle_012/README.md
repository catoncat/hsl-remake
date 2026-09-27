# 巴瀚納海峽（level 12）：正式战斗运行回执

> evidence: runtime-measured; resource-derived · status: live · tools: capture_battle_review.gd, hsltools/levels/actors.py, hsltools/levels/battle.py, run_battle_sweep_tests.gd, run_script_wait_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-20

记录的是 Godot 重制版的实际窗口化运行（tests/capture_battle_review.gd -- --level=12，remake pacing），不是原 EXE 现场。STORY012／WINFAIL012 的 token 顺序、EVEF 编队、地图尺寸、宝箱字与 actor cast 为 resource-derived；本回执的走位、镜头时钟、对白节奏、结果页和 source-timed 强制胜利夹具是 runtime-measured 的重制读法，不能据此声称原版等价。

## 入口

产品战役现在从 content/battles/campaign.json 的 level 12 进入 content/battles/battle_012.json。场景由 python3 tools/hsl.py generate level_battle:12 从 level-12 opening／seed／来源模板组装：39 个可玩单位（7 个受控玩家与 32 个 Enemy038），45x60 地形网格，1 个 EVEF 宝箱；62 个 Enemy101 船殼与 RainBOSS／Rain／RainSound 保留为静态开场物件。

WINFAIL012 的 actSetPlayerFixPos（第 8 回合：32 名 038 的守备锚点改写为四个图外撤退点、半径 1——单位不瞬移，靠固定点行走退向图边，第 10 回合 actWalkAndDelete 离场；lane R23 之前的瞬移读法会把它们放到图外并让下一个 AI 回合以 `unsupported_ai_coordinates` 失败）、actSetPlayerFly 与 actChangePrevInsertObjectID 已由数据驱动解释器记录到同一 unit／insert 状态。窗口化回执中的胜利路径经过 round 8／10／16／23 的 source-timed event hooks，最终状态为 win_0／victory_script。

## 本次回执

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 首次控制：39 名单位、7 名受控玩家、interaction=action_menu |
| [win-dialogue-1716.png](win-dialogue-1716.png) | round 16 水怪增援段对白与战场镜头 |
| [win-dialogue-1720.png](win-dialogue-1720.png) | round 23 船战收束段对白 |
| [result.png](result.png) | 结果页：victory_script，已解析 win_0 |

[review_manifest.json](review_manifest.json) 是该次窗口化运行的记录（30 张原始 review 帧；本 packet 只保留上面 4 张）。自动验证：python3 tools/hsl.py check level_battle:12、python3 tools/hsl.py check level_actors:12、tests/run_winfail_rules_tests.gd、tests/run_battle_sweep_tests.gd、tests/run_script_wait_tests.gd。

## 边界

- 强制胜利夹具只证明从开场、脚本事件到结果页的流转，不证明 AI、平衡、战斗难度或原版节奏。
- 62 个 Enemy101 船殼没有作为 playable units 建模；其 WINFAIL 数量条件与静态物件计数的连接仍是 provisional。review／sweep fixture 在推进 source rounds 时暂时不让这个 provisional fail status 终止流程。
- six actChangePrevInsertObjectID(10000) writes are retained as insert receipts. Native object identity lifetime and absence of a separate visible effect in the remake remain provisional.
- Out-of-map fixed positions, collision, flight traversal and water-creature placement retain the source token data but use remake presentation timing.

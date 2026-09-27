# 亞雷比斯（level 26）

> evidence: runtime-measured · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版正式战斗的 runtime-measured 窗口化回执，不是原版 EXE 的等价性证明。捕获入口为 tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=26，原始批次保存在 ignored/battle-026-review/；本包保留首次控制、胜利对白与结果页三帧，以及对应的 review_manifest.json。

## 入口与编队

大地图点 26 现在进入 content/battles/battle_026.json，不再停在 story_026.json 开场预览。正式场景由 python3 tools/hsl.py generate level_battle:26 从 tracked preview、battle seed、EVEF 物件与已审核演员模板组装：首次控制有 20 名单位，其中 8 名受控角色（001–007、009）、4 名 Enemy039 与 8 名 Enemy038。26 个 Enemy101 船壳是 resource-derived 静态对象，不作为可攻击单位计入 roster。

WINFAIL026 的 event_0 在 round 14 条件满足后插入 7 个 Enemy035；Enemy035 的走路帧与音频已进入该关演员资源。win_0 使用 actCheckEnemyTotalNumber(0)，窗口化强制清敌回执为 victory_optional_clear，并执行消息 2429 与后续大地图／城镇 token 的 remake 结果链。

宝箱内容是 EVEF override words：记录 52 坐标 [2, 15]，物品代码 [68]，写入 content/generated/hsl/treasures/battle_026.json。Enemy038 的首个 STORY endpoint 落在 remake terrain 的 blocked source cell [16, 5]，组装器采用最近可用格并标记 provisional。

## 帧清单

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场结束后的首次控制，8 名受控单位与 12 名敌方单位 |
| [win-dialogue-2429.png](win-dialogue-2429.png) | win_0 胜利对白（雷歐納德，消息 2429） |
| [result.png](result.png) | victory_optional_clear 结果页 |

## 验证

本次 slice 的自动回执：

- BATTLE_SEED_CHECK_PASS level=26 placements=52 map=1600x992 terrain=50x31
- LEVEL_SCRIPT_SOUNDS_CHECK_PASS level=26 sounds=0
- LEVEL_SOURCE_TEXTS_CHECK_PASS level=26 texts=3
- OPENING_TIMELINE_CHECK_PASS source=story026 events=47 output=content/imported/hsl/chapter01/battle026/opening_timeline.json
- opening timeline ok: source=story026 events=47 messages=5 timeline=content/imported/hsl/chapter01/battle026/opening_timeline.json
- message text evidence ok: level=26 message_id_count=27
- LEVEL_MAP_OBJECTS_CHECK_PASS level=26 placements=29 shapes=4 combined=0
- LEVEL_ACTORS_CHECK_PASS level=26 actors=11 portraits=8 sounds=13
- STORY_SCENE_CHECK_PASS level=26 actors=20
- LEVEL_BATTLE_CHECK_PASS level=26 units=20 players=8 templates=1 statuses=4 chests=1
- BATTLE_SWEEP_TESTS_PASS battles=15
- STORY_MODE_WALKTHROUGH_PASS steps=48
- STORY_SCENE_TESTS_PASS
- CAMPAIGN_TESTS_PASS
- SCRIPT_WAIT_TESTS_PASS checks=447
- BATTLE_REVIEW_PASS level=26 shots=9

## 边界

- STORY／WINFAIL token、EVEF 编队、脚本演员、肖像／音频／走路帧、船壳对象、宝箱 words 与消息正文是 resource-derived；窗口帧、开场／对白时钟、Enemy035 增援表现、胜利夹具和结果页布局是 runtime-measured 的重制表现。
- 咕嚕 008 是 seed 中的「有才產生」条件成员，未作为首次控制单位安装；其资格与安装时序仍是 provisional，替代证据是 original_player_install.md 的登记槽表。
- 地图投影、船壳碰撞／原生移动规则、阻挡格最近合法落点、完整原始对象调度、全局 RNG、AI 平衡与墙钟不由本回执证明。

# 利魯瑪山地（level 19）

> evidence: runtime-measured · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版正式战斗的 runtime-measured 窗口化回执，不是原版 EXE 的等价性证明。捕获入口为 tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=19，原始批次保存在 ignored/battle-019-review/；本包保留首次控制、胜利对白与结果页三帧，以及对应的 review_manifest.json。

## 入口与编队

大地图点 19 现在进入 content/battles/battle_019.json，不再停在 story_019.json 开场预览。正式场景由 python3 tools/hsl.py generate level_battle:19 从 tracked preview、battle seed、EVEF 物件与已审核演员模板组装：首次控制有 5 名单位，其中雷特 1 名受控角色与 4 名 Enemy041 敌人；EVEF 宝箱 3 个，内容写入 content/generated/hsl/treasures/battle_019.json。

首次控制帧记录 units=5、players=1。WINFAIL019 的 event 1／event 2 会按源条件加入 041／043／038 增援，并在胜利段安装后续状态；运行时回执的强制清敌结果为 win_0 / victory_optional_clear。脚本实际会插入的 001–007、038、041、043 演员已进入该关 actor walk/audio manifest，避免表现层把数据演员当作缺失资源。

宝箱内容是 EVEF override words：记录 9 为 [228]，记录 10 为 [225]，记录 11 为 [242, 244]。坐标／阻挡格若采用最近可用格，均由组装器记录为 provisional，而不是宣称原版站立规则已恢复。

## 帧清单

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场结束后的首次控制，1 名受控单位与 4 名敌人 |
| [win-dialogue-1484.png](win-dialogue-1484.png) | win_0 胜利对白（雷特，消息 1484） |
| [result.png](result.png) | victory_optional_clear 结果页 |

## 验证

本次 slice 的自动回执：

- BATTLE_SEED_CHECK_PASS level=19 placements=11 map=1600x1184 terrain=50x37
- LEVEL_SCRIPT_SOUNDS_CHECK_PASS level=19 sounds=0
- LEVEL_SOURCE_TEXTS_CHECK_PASS level=19 texts=3
- OPENING_TIMELINE_CHECK_PASS source=story019 events=39 output=content/imported/hsl/chapter01/battle019/opening_timeline.json
- opening timeline ok: source=story019 events=39 messages=8 timeline=content/imported/hsl/chapter01/battle019/opening_timeline.json
- message text evidence ok: level=19 message_id_count=42
- LEVEL_MAP_OBJECTS_CHECK_PASS level=19 placements=4 shapes=2 combined=0
- LEVEL_ACTORS_CHECK_PASS level=19 actors=10 portraits=6 sounds=10
- STORY_SCENE_CHECK_PASS level=19 actors=5
- LEVEL_BATTLE_CHECK_PASS level=19 units=5 players=1 templates=9 statuses=6 chests=3
- BATTLE_SWEEP_TESTS_PASS battles=14
- STORY_SCENE_TESTS_PASS
- CAMPAIGN_TESTS_PASS
- SCRIPT_WAIT_TESTS_PASS checks=447
- BATTLE_REVIEW_PASS level=19 shots=32

## 边界

- STORY／WINFAIL token、EVEF 编队、脚本演员、肖像／音频／走路帧、宝箱 words 与消息正文是 resource-derived；窗口帧、开场／对白时钟、增援表现、胜利夹具和结果页布局是 runtime-measured 的重制表现。
- 后续脚本安装的条件成员 001–005／007 没有作为首次控制编队出现；其“有才產生”资格仍是 provisional，替代证据是 original_player_install.md 的登记槽表。
- 山地地图投影、阻挡格最近合法落点、完整原始对象调度、全局 RNG、AI 平衡与墙钟不由本回执证明。

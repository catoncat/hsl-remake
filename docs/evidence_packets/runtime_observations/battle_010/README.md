# 帕尼西亞城 廢墟（level 10）

> evidence: runtime-measured · status: live · tools: capture_battle_review.gd, hsltools/levels/battle.py · updated: 2026-09-20

这是 Godot 重制版正式战斗的 runtime-measured 窗口化回执，不是原版 EXE 的等价性证明。捕获入口为 tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=10，原始批次保存在 ignored/battle-010-review/；本包保留首次控制、胜利对白与结果页三帧，以及对应的 review_manifest.json。

## 入口与编队

大地图点 10 现在进入 content/battles/battle_010.json，不再停在 story_010.json 开场预览。正式场景由 python3 tools/hsl.py generate level_battle:10 从 tracked preview、battle seed、EVEF 物件与已审核演员模板组装：首次控制有 6 名单位，其中雷歐納德／緹娜 2 名受控角色与 4 名 Enemy034／Enemy035 敌人；EVEF 宝箱 1 个，内容写入 content/generated/hsl/treasures/battle_010.json。

开场首次控制帧显示 units=6、players=2。强制清敌回执解析为 win_0，结果为 victory_optional_clear，随后可通过战役 hand-off 进入后续剧情。WINFAIL010 的 win status 不是初始安装：测试与捕获先推进到 source-derived 的第 5 回合 event 3，再使用共享清敌夹具，以保留该脚本的状态时序。

## 帧清单

| 帧 | 内容 |
| --- | --- |
| [first-control.png](first-control.png) | 开场结束后的首次控制，2 名受控单位与 4 名敌人 |
| [win-dialogue-1098.png](win-dialogue-1098.png) | win_0 胜利对白（緹娜，消息 1098） |
| [result.png](result.png) | victory_optional_clear 结果页 |

## 验证

本次 slice 的自动回执：

- BATTLE_SEED_CHECK_PASS level=10 placements=13 map=960x704 terrain=30x22
- LEVEL_ACTORS_CHECK_PASS level=10 actors=7 portraits=5 sounds=7
- STORY_SCENE_CHECK_PASS level=10 actors=6
- LEVEL_BATTLE_CHECK_PASS level=10 units=6 players=2 templates=5 statuses=11 chests=1
- BATTLE_SWEEP_TESTS_PASS battles=13
- STORY_MODE_WALKTHROUGH_PASS steps=48
- STORY_SCENE_TESTS_PASS（REGISTERED_STORY_SWEEP scenes=64）
- CAMPAIGN_TESTS_PASS
- SCRIPT_WAIT_TESTS_PASS checks=447
- BATTLE_REVIEW_PASS level=10 shots=26

## 边界

- opening／WINFAIL token、EVEF 编队、演员模板、宝箱 override words 与消息正文是 resource-derived；窗口帧、开场／对白时钟、胜利夹具和结果页布局是 runtime-measured 的重制表现。
- 雷雨、闪电、火焰与环形物件沿 source placement 与帧资源呈现；战斗中帧速、镜头和效果时序仍是 provisional 的重制读法，待对应原版 runtime route 才能替换。
- 受控单位终点和阻挡格处理遵循组装器的当前合同；完整原始对象调度、全局 RNG、AI 平衡与墙钟不由本回执证明。

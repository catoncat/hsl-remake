# 第二战（level 52）重制运行回执：开场、交锋对白、event1 增援

> evidence: runtime-measured; resource-derived: STORY052／WINFAIL052 token 与对白正文; provisional: 节奏、镜头、条件极性 · status: live · tools: run_winfail_rules_tests.gd · updated: 2026-09-27

## 结论

- 原版 STORY052 开场、WINFAIL052 event0 交锋对白与 event1 增援的 token 顺序与对白正文见 [second_battle_opening_script](../../static_reverse/second_battle_opening_script.md)；handler 时序、镜头与走位速度未读（resource-derived；provisional）。
- 重制以 `product_opening` 启动 `battle_052.json`，`BattleOpeningCoordinator` 播完 57 个 token 后把首次控制交给同一 PlayLoop；event0 对白与 event1 的四名 021 增援由 `WinfailScenarioRules` 触发、`ScriptActorCreationRules` 出生（runtime-measured）。
- 差异：节奏为重制值；差异清单 `winfail-readings`（provisional）。

## 证据

### runtime-measured：开场（窗口化，正常节奏）

`SECOND_BATTLE_OPENING_REVIEW_PASS shots=16`：开场 35.0 s 后进入 `action_menu`、选中 `leonard`；25 段运动（9 次 `actWalkDispWait`、8 次插入、8 次插入行走）、0 个跳过 token、1 条「CLIP001 未导入」记录；结束后 16 名角色落在 PlayLoop 格上（[review-manifest.json](review-manifest.json)）。

| 帧 | 观察 | token |
| --- | --- | --- |
| [00-emperor-framed](00-emperor-framed.png) | 镜头落在王座上的法蘭克（025），两名帝國法師（026）分列两侧 | `actSetBGToObject(SID_ENEMY025,1)` |
| [dialogue-379](dialogue-379.png) | 帝國法師进言，与第一战共用 BOARD02 | `actMessage(SID_ENEMY026,1,379)` |
| [dialogue-383](dialogue-383.png) | 皇帝沿地毯下行 96 px 后表态 | `actWalkDispWait(SID_ENEMY025,1,0,96,1)`→383 |
| [party-walk-up](party-walk-up.png) | Leonard 由地图下缘外上行 224 px | `actScrollBGToObject(SID_PLAYER0,1)`、`actWalkDispWait(SID_PLAYER0,1,0,-224,2)` |
| [dialogue-388](dialogue-388.png) | 八名衛兵从左右地图外插入并走到位后 Leonard 分派任务 | 8 组 `actInsertObject`／`actWalkPrevInsertObjectWait`、388 |
| [section-title](section-title.png) | WORD052「惡夢的終曲 / NIGHTMARE FINALE」1x 居中淡入 | `actShowSectionName` |
| [first-control](first-control.png) | 速度更高的衛兵先行动，随后 Leonard 打开共享行动菜单 | `actShowWinFailStatus`→`first_control_ready` |

### runtime-measured：event0 交锋对白与结果消息

Leonard 攻击皇帝的行动完成扫描触发 event_0：法蘭克（speaker 382 → 头像 025）说 392、雷歐納德说 393，经共享对白视图显示；胜利 `victory_boss` → 378、败北 `defeat_leonard` → 394（文本来自 `battle052/message_text_evidence.json`）。

### runtime-measured：event1 增援

击破 021 至剩一名后回合钩子触发 `actCheckEnemyNumber SID_ENEMY021 2`（重制按严格小于）；四名 `Enemy021_script_0_*` 按 `script_actor_templates`（`obj_Story_Level52_Enemy21`）在脚本插入像素出生，首名在底边 (227,1356) 显形，逐个阻塞到位，落在 (7,38)、(12,38)、(4,30)、(14,30)；`script_actor_transactions[0]` 四个 `created_ids`，`reinforcement_deficits` 归零（[../second_battle_reinforcement/manifest.json](../second_battle_reinforcement/manifest.json)）。

## 重制接线

- `content/battles/battle_052.json`（`level_battle:52`，`rule_adapter: winfail`）。
- `game/battle/runtime/BattleOpeningCoordinator.gd`（开场）；`WinfailScenarioRules`（event／胜负）；`ScriptActorCreationRules` 与 `BattleScriptActorPresentation.apply_event`（增援出生与走入）。

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`（`_second_battle_sequence`）；开场、交锋与增援的窗口驱动已退役，回执为历史记录。

## 边界

- 节奏：走位 160 px/s、`actDelay` 每单位 0.025 s、标题 1.4 s、镜头滚动 0.6 s 为重制值，原延迟单位与走位速度未读。
- 插入行走终点用脚本像素量化出的格，不是原非 32 对齐像素；对象生命周期、阵营与脚点未读。
- `actCheckPlayerAttacked` 的触发极性、对白在攻击演出前后的时机、`actCheckEnemyNumber` 的比较极性、增援是否伴随镜头移动与等待回合未读。
- `actPlaySound(WAV\CLIP001.WAV)` 只记录不播放；说话人「帝國法師」为重制标签。

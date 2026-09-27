# 第二战开场：正式入口实际运行回执

> evidence: runtime-measured; resource-derived · status: live · tools: capture_second_battle_opening_review.gd, run_second_battle_opening_tests.gd · updated: 2026-09-18

Checked: 2026-09-18。`runtime-measured`（Godot 重制版窗口），对照原作只到 STORY052 token 顺序与对白正文（`resource-derived`）；镜头、走位速度、延迟单位为明示重制节奏，不声称原版等价。

## 复跑

```sh
# 无头合同（进入完整门禁）
tools/godot.sh --headless --script res://tests/run_second_battle_opening_tests.gd
# 正常节奏可见窗口（先确认内建屏编号）
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/capture_second_battle_opening_review.gd
```

路线：`BattleSceneRuntime.tscn` 以 `scenario_path=second_battle.json`、`startup_mode=product_opening` 启动 → `BattleOpeningCoordinator` 按 `content/imported/hsl/chapter01/battle052/opening_timeline.json` 播放 57 个 token → `first_control_ready` 交给同一 PlayLoop（NPC 前置行动后 Leonard 菜单）。无数值、坐标或结果覆盖；只有对白确认使用合成空格键。

## 本次回执

`SECOND_BATTLE_OPENING_REVIEW_PASS shots=16`，开场 35.0 秒后进入 `action_menu`，选中 `leonard`，12 句对白各截一帧；[review-manifest.json](review-manifest.json) 记录每帧的事件 id、镜头与运动状态。无头合同 `SECOND_BATTLE_OPENING_TESTS_PASS`：25 段运动（9 次 `actWalkDispWait`、8 次插入、8 次插入行走）、0 个被跳过 token、1 条显式「CLIP001 未导入」记录、win/fail/event/dead-message 注册齐全，结束后 16 名角色全部可见并落在 PlayLoop 格上。

| 帧 | 观察 | 对应 token |
| --- | --- | --- |
| [00-emperor-framed](00-emperor-framed.png) | 镜头先落在王座上的法蘭克（025），两名帝國法師（026）分列两侧 | `actSetBGToObject(SID_ENEMY025,1)` |
| [dialogue-379](dialogue-379.png) | 帝國法師进言，肖像／说话人／原文三行分页与第一战共用 BOARD02 | `actMessage(SID_ENEMY026,1,379)` |
| [dialogue-383](dialogue-383.png) | 皇帝已沿地毯下行 96px 后表态 | `actWalkDispWait(SID_ENEMY025,1,0,96,1)`→`actMessage(...,383)` |
| [party-walk-up](party-walk-up.png) | 镜头转向队伍，Leonard 由地图下缘外沿地毯上行 224px | `actScrollBGToObject(SID_PLAYER0,1)`、`actWalkDispWait(SID_PLAYER0,1,0,-224,2)` |
| [dialogue-388](dialogue-388.png) | 八名衛兵从左右地图外插入并走到位后，Leonard 分派任务 | 8 组 `actInsertObject`／`actWalkPrevInsertObjectWait`、`actMessage(SID_PLAYER0,1,388)` |
| [section-title](section-title.png) | 原 WORD052 标题「惡夢的終曲 / NIGHTMARE FINALE」以原始 1x 尺寸居中淡入 | `actShowSectionName(SHAPE01\WORD052.SHP)` |
| [first-control](first-control.png) | 状态注册后进入同一 PlayLoop：速度更高的衛兵先行动，随后 Leonard 打开共享行动菜单 | `actShowWinFailStatus`→`first_control_ready` |

## 明示的重制选择与未确认边界

- 节奏：走位 160px/s（与战斗 0.20 秒/格一致）、`actDelay` 每单位 0.025 秒、标题 1.4 秒、镜头滚动 0.6 秒；原延迟单位与走位速度未证明。
- 插入行走终点使用 scenario 由脚本像素量化出的格，而非原非 32 对齐像素；原对象生命周期、阵营与脚点未证明。
- `actPlaySound(WAV\CLIP001.WAV)` 未导入，coordinator 只记录不播放；关卡音乐仍是第一战重制曲。
- 说话人「帝國法師」为重制标签（PLAYERS 名称字段为 ???）；对白框、字体与分页是既有重制表现。
- 本回执不覆盖第二战的胜负事件表现、增援演出与跨关承接；它们仍在 [PROJECT Next steps](../../../PROJECT.md#next-steps)。

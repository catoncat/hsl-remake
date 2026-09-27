# 战役承接：第一战胜利 → 第二战开场（实际运行回执）

> evidence: runtime-measured; provisional · status: live · tools: capture_campaign_chain_review.gd, capture_campaign_handoff_review.gd, capture_campaign_resume_review.gd, run_campaign_tests.gd, run_third_battle_runtime_tests.gd · updated: 2026-09-18

Checked: 2026-09-18。`runtime-measured`（Godot 重制版窗口）。跨关承接规则是明示重制策略（`provisional`），原版关卡间的存续行为未证明。

## 复跑

```sh
# 无头合同（进入完整门禁）：纯 carry 捕获／应用 + 结果页按钮 + 下一场景消费 hand-off
tools/godot.sh --headless --script res://tests/run_campaign_tests.gd
# 可见窗口（先确认内建屏编号）
tools/play.sh --screen 0 --position 60,80 --resolution 640x480 \
  --script res://tests/capture_campaign_handoff_review.gd
```

可见路线在第一战 dev first-control seam 上显式设定 `battle_outcome=victory_escape`、Leonard 等级 2／经验 20、金币 150（夹具，不是自然通关），确认结局台词后出现结果页，点击「下一戰 · 惡夢的終曲」，`reload_current_scene` 后以 `second_battle.json` 重新启动并进入 STORY052 开场。

## 回执

`CAMPAIGN_HANDOFF_REVIEW_PASS shots=4`；[review-manifest.json](review-manifest.json) 保存 carry receipt（`applied_unit_ids=["leonard"]`，无错误）与第二战存档槽 `user://battle_002_level52.save`。无头合同 `CAMPAIGN_TESTS_PASS`：等级／经验／未用点数／四属性／装备／库存／击杀数进入新 loop 并经共享成长刷新，HP/MP 回到刷新后的上限，气力按场景初值重置，金币随 loop 承接；其余 15 名单位与场景规则不变；开战后或空 carry 的应用为 no-op；actor 不符的单位被明确跳过。

| 帧 | 观察 |
| --- | --- |
| [01-closing-line](01-closing-line.png) | 胜利结局台词（371）先于结果页 |
| [02-result-next-battle](02-result-next-battle.png) | 结果页下方出现「下一戰 · 惡夢的終曲」；有待领物品时该位置由既有「查看待領物品」占用，两者互斥 |
| [03-next-battle-opening](03-next-battle-opening.png) | 重新加载后进入王座厅开场，Leonard 带等级／金币进入同一 PlayLoop |

## 承接策略（`content/battles/campaign.json`）

- 只承接 `player_controlled` 单位：`level/exp/pending_stat_points/equipment/weapon_code/inventory/kill_count` 与 `str/dex/mind/con`；loop 级只承接 `gold`。
- 应用发生在 `BattlePlayLoop.create` 之后、`begin_battle` 之前（`apply_campaign_carry` seam），派生数值走 `ProgressionRules.refresh_growth_stats`，队列按刷新后速度重建。
- `next_level_event` 来自各战 winfail 脚本（051→52，052→58）；level 58 没有场景，第二战胜利后不出现按钮。
- 下一场景通过 `CampaignProgress.pending`（进程内一次性静态）交给重新加载的 Runtime；不写跨关存档，第二战使用独立单战存档槽。

## 未确认边界

- 原版关卡间的 HP/MP 是否回满、金币／物品是否结算、是否有关间剧情或商店：未证明；当前为重制选择。
- 第二战胜负／事件对白、增援演出、CLIP001 音效、专属配乐已在后续切片接入（见各自回执）；level 53 之后的 level 1 尚未重制，53 胜利结果页以「第一章　完 · level 1 尚未重製，回到第一戰」结束本章（见 [PROJECT Next steps](../../../PROJECT.md#next-steps)）。

## 跨启动续战（2026-09-18 追加，runtime-measured）

- `CampaignProgress` 在每次跨关 hand-off（结果页「下一戰／繼續」与 story scene 的 `start_story_handoff`）把 `{scenario_path, carry, from_scenario_id}` 写入 `user://campaign_progress.json`（`hsl_campaign_progress_save.v1`）；`reset_campaign()`／章末「回到第一战」／提示中的「從第一戰重新開始」删除它。
- 新进程以 `product_opening` 进入 campaign 首关（`first_battle.json`）且存档指向更后的关卡时，开场在第一帧暂停（`SceneTree.paused`），在始终处理的 CanvasLayer 4 上显示「偵測到戰役進度 / 上次進行到：<title>」与两个按钮（`resume-prompt.png`）；「繼續」把存档作为一次性 `pending` 重载进入该关卡并带回 carry（`resumed-story-scene.png` 为 story 058 起始帧），「從第一戰重新開始」删除存档并恢复开场。
- 采集：`tools/play.sh --screen 0 --script res://tests/capture_campaign_resume_review.gd`（`CAMPAIGN_RESUME_REVIEW_PASS shots=2`）；headless 覆盖在 `tests/run_campaign_tests.gd` 的 `_test_saved_progress`（headless 需 `resume_prompt_in_headless = true` 显式开启，避免 smoke 套件受开发机存档影响）。
- 边界：只保存战役位置与受控单位 carry，不保存战斗中途状态（单战存档仍是 `BattleCheckpoint` 的独立槽）；原作跨关存档流程未考证，此为重制流程。

## 第二战之后的整链回执（2026-09-18，runtime-measured；同日更新为 53 正式战斗，再延到 level 1 预览→大地圖→城镇）

`tools/play.sh --script res://tests/capture_campaign_chain_review.gd --resolution 640x480 --screen 0`（level 52 dev first-control seam 上把皇帝置为阵亡后由 PlayLoop `_resolve_outcome` 裁决胜负，等级 3／金币 275 作为显式 fixture；53 的逃出胜利把緹娜放到城门格 (30,35) 后选「待機」由 PlayLoop 裁决；story 场景与开场用快节奏，只看衔接）：`CAMPAIGN_CHAIN_REVIEW_PASS shots=13`；[chain-review-manifest.json](chain-review-manifest.json) 保存各步 check 与最终落盘位置。

1. `chain-01-level52-victory-cutscene.png`：皇帝阵亡 → 解释器提交 WINFAIL052 win_0 → 其结果链以脚本演出播放：镜头对准雷歐納德、脚本消息框显示 378「拉爾斯帝國的時代結束了！！」（故事队列不再重复分页）。
2. `chain-02-level52-result-next.png`：演出结束后结果页出现「繼續 · 沃斯菲塔王座廳」按钮。
3. `chain-03-level58-opening.png`：点击后重载进 `story_058.json`，`campaign_handoff.carry.loop.gold == 275` 到达 story 场景；58 结束经 `start_story_handoff` 进 `story_060.json`，60 结束进 `third_battle.json`（level 53 正式战斗），carry 三次交接后仍为 275。
4. `chain-07-level53-opening.png`：53 以 `product_opening` 进入，协调器**战斗模式**从 `actScrollBGToPos(0,0)` 的塔顶月夜开始播放 STORY053（右缘阳台为仅演出的緹娜 029）。
5. `chain-08-level53-first-control.png`：开场结束、卫兵先手行动播放完毕后，受控单位 `tina`（PLAYERS 002 模板）在攀绳终点格 (20,23) 打开行动菜单（移動／攻擊／魔法／道具／待機／狀態），两名追兵已逼近；`user://campaign_progress.json` 记录 `third_battle.json` 为续战位置，《逃出克萊恩城》在首次控制时播放。campaign 将 53 标 `party: separate`，Leonard 的 carry 未施加于緹娜、原样保留待传递。

6. `chain-09-level53-victory-line.png`：緹娜站上城门格并待機 → `victory_escape` → 解释器提交 WINFAIL053 win_0 → 704「……」以脚本演出播放（结果页等演出结束）。
7. `chain-10-level53-result.png`：结果页「緹娜 逃出克萊恩城」与「繼續 · 歐姆村（開場預覽）」按钮（winfail `[1,1]`：第二值 1 为下一关，按 `CampaignProgress.next_destination` 解析）。
8. `chain-11-level1-preview-end-card.png`：`story_001.json` 播完 STORY001 81 个 token 后的「戰鬥部分（level 1）尚未重製……進入大地圖（歐姆村）」卡；确认后经 `_exit_to_world_map` 带 carry（loop.gold 仍为 275，53 为 separate party 未触碰）与世界状态进入 `world_map_scene.json`，站在歐姆村点 1。此后到戈爾山道弹「level 2 · 戈爾山道 尚未重製」卡、回歐姆村开城镇画面的帧（12–14）与[大地圖回执](../world_map_scene/README.md)／[城镇回执](../town_scene/README.md)相同，不重复收录；`user://campaign_progress.json` 最终为 `world_map_scene.json` ＋ `world.current_point = 1`。

边界：fixture 不是自然打完第二战／第三战（53 胜利由夹具把緹娜放到城门格）；节奏被压缩，不作为各场景的视觉验收；53 的被捕失败／增援由 `tests/run_third_battle_runtime_tests.gd` headless 覆盖，尚无自然打通 53 的实玩回执。各工作树的 Godot 测试共用 `user://`，并发 campaign 测试会清掉落盘文件，此 review 须单独运行；结果页按钮的窗口点击偶发未命中（重跑即过），属采集夹具时序，不是产品缺陷。
# Level 6 席達鎮 開場預覽（STORY006）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd, run_town_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=6`（`STORY_SCENE_REVIEW_PASS shots=6`；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_6_preview` 与 `tests/run_town_scene_tests.gd` 的 `_run_next_level_exit`）。场景文件 `content/battles/story_006.json` 由 `python3 tools/hsl.py generate story_scene:6` 生成。入口不是大地图到达：席達鎮（bigmap 点 6，Town）酒馆事件 23「席達鎮酒館沃斯菲塔士兵」以 `teSetNextPlayLevelEvent 6,6` 关闭城镇并交接进入；卡片确认回大地图仍站在点 6。

## 看到什么

1. `01-town-gate-framed.png`：1120×896 城镇街区，`actScrollBGToPos 1024,224` 框住东门；EVEF 预置 12 名村民（061／062）与 7 名沃斯菲塔士兵 023（蓝甲）。四名队员由 `actInsertStoryObject obj_Story_Player1..4` 在 (1024,224) 依次安装并 `actWalk` 进街区。
2. `02-captain-950.png`：三名 023 与隊長 024 由 `actInsertObject` ＋ 非等待 `actWalkPrevInsertObject` 跟进到 (896,224)／(864,288)／(928,288)／(992,256)；隊長（重裝兵）950「各位，他....就是叛賊雷歐納德……」。
3. `03-captain-952.png`：士兵（`SID_ENEMY023,8`，重制读法＝第一名插入士兵）951 劝阻，隊長 952「囉唆！有事我......會負責的。」；随后 WORD006 标题、win 0／fail 0／event 0·2 status 登记，止于「席達鎮 / 戰鬥部分（level 6）尚未重製」卡。

## 断言（headless）

51 个 STORY006 事件零跳过；插入前地图上无雷歐納德，四个玩家槽按序 spawn；对白 950–952 顺序与说话人（重裝兵／一般兵）；雷歐納德终点 (736,256)、隊長终点 (992,256)、第三名士兵 (928,288)；`actAdjustAllPlayerLevel` 记录为 recorded_no_handler；卡片；确认后交接 `world_map_scene.json`，world state `current_point 6`。城镇侧：事件 23 关闭城镇后 `CampaignProgress.pending.scenario_path` 为 `story_006.json`、无卡片。

## 边界

- 只证明开场按 token 顺序播放与城镇→关卡→大地图往返；不证明原版镜头、走位速度与延时。
- `SID_ENEMY023,8` → 第一名插入士兵、`SID_ENEMY024,1` → 插入隊長为重制 token 绑定（原版实例查找未解）。
- `actSetPrevInsertObjectWaitRound 3` 与 `actAdjustAllPlayerLevel` 只记录：预览无回合队列与等级表。
- 配乐：原表 `0x477b44` 给 level 6 track 17；当时该槽位放重制原创曲（2026-09-26 起改放原曲，原创曲已删）。
- 战斗本体待 P-024 与多受控槽；两个 `寶藏`（EVEF 52／53）与 winfail006 未接入。

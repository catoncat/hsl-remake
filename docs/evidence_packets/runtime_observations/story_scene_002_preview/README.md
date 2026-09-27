# Level 2 戈爾山道 開場預覽（STORY002）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_campaign_chain_review.gd, capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=2`（`STORY_SCENE_REVIEW_PASS shots=14`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_2_preview`）。场景文件 `content/battles/story_002.json` 由 `python3 tools/hsl.py generate story_scene:2` 从 `battle002_seed` 生成；campaign 注册 level 2 后，大地图到达戈爾山道（bigmap 点 2，无脚本点事件时其 +8 事件值＝2）即交接进入，卡片确认回大地图仍站在点 2（[大地图回执](../world_map_scene/README.md)、`tests/capture_campaign_chain_review.gd` 15 帧链路）。

## 看到什么

1. `01-raiders-run-sky-backdrop.png`：768×640 山道地图右上为透明天空，`移動背景01`（`LVL04_01.SHP`，`mapobjMoveBG`）按 `backdrop` 层画在地图底图之下从透明区透出（此前同类物件在 level 53 画在底图之上，本片一并改正）；路標／欄杆／雲02 为普通站立物件。镜头初始夹在地图东南角（雷歐納德的 EVEF 槽位在地图外 (832,672)），5 名 028 盜賊自东南缘外跑上山道。
2. `02-raiders-750.png`：盜賊到达山道顶部 (128,64)…(192,128)，`SID_ENEMY028` 以 632「盜賊」说 750–752（752 为 defNoOne 叙述）。
3. `03-hu-753.png`：`actScrollBGToObject SID_雷歐納德` 后琥 (003) 走到 (704,512)，说 753；雷歐納德走到 (640,544)。两人位于镜头夹在地图下缘后的对白框下槽区间，对白框改用顶部槽位（重制表现选择，见 [表现合同](../../../architecture/PRESENTATION.md#opening-and-dialogue)）；北侧的盜賊 750 仍用底部槽位。画面左侧与中央的两只 `寶藏`（defProcTreasureBox，EVEF 记录 23／24，锚点 (160,448)／(480,448)）以 `SHAPE\BOX0001.SHP` 关闭宝箱作站立物件绘出（`map_objects.json` role `treasure_box`，back 层；帧内像素与解码 PNG 逐点一致，差值 0.0）。
4. `04-section-title-encounter.png`：`actShowSectionName SHAPE01\WORD002.SHP`「遭遇 ENCOUNTER」。
5. `05-leonard-757.png`：`SID_雷歐納德` 说 757；event status 0、fail 0/1 已登记，遺言 741（雷歐納德）／743（琥）。
6. `06-not-remade-card.png`：first_control_marker 处止于「戈爾山道 / 戰鬥部分（level 2）尚未重製 空格／點擊：回到大地圖（戈爾山道）」。

## 断言（headless）

32 个 STORY002 事件零跳过；8 句对白 750–757 按脚本顺序，说话人 盜賊／（叙述）／琥／雷歐納德；`actWalk`／`actWalkWait` 为绝对像素目标：盜賊 1 终点 (128,64)、盜賊 5 (192,128)、琥 (704,512)、雷歐納德 (640,544)；镜头中心不越出 768×640 地图；配乐为原创曲《戈爾山道》`gol_mountain_road.ogg`（track 12 槽位）；卡片确认交接 `world_map_scene.json`，world state 仍 `current_point 2`、`visited_points [1,2]`，carry（gold 275）原样通过。

## 边界

- 只证明 STORY002 开场在协调器 story 模式下按 token 顺序播放与大地图往返；不证明原版镜头初始位置、走位速度与延时。
- 配乐：原表 `0x477b44` 给 level 2 track 12（static-derived：`r2 -c 'px 2 @ 0x477b48'` → `0c00`；level 1 = 13，level 51 = 19 与既有证据一致）；当时该槽位放重制原创曲（2026-09-26 起改放原曲，原创曲已删）。
- 战斗本体待 P-024 的琥 jobBowMan 83 与双受控槽；两只 `寶藏` 只作关闭宝箱绘出，开箱／拾取／箱内物品与 winfail002 胜利事件（`obj_Story_Player2` 緹娜与 4 名 023 士兵入场、点 3／线旗、next level 3）未接入；`移動背景` 的漂移未重现。

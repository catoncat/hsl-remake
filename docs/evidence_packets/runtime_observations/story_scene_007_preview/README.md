# Level 7 寧靜之森 開場預覽（STORY007）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=7`（`STORY_SCENE_REVIEW_PASS shots=10`；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_registered_story_sweep` 与全程剧情 explorer）。场景文件 `content/battles/story_007.json` 由 `python3 tools/hsl.py generate story_scene:7` 生成；campaign 注册 level 7 后，大地图到达寧靜之森（bigmap 点 7，bmpmGeneral）即交接进入，卡片确认回大地图仍站在点 7。

## 看到什么

1. `01-tina-1007.png`：960×832 密林；`actScrollBGToPos 416,896` 后镜头被夹在地图下缘，四人（雷歐納德／緹娜／琥／漢克斯）自南缘外走到 (448,704)／(576,768)／(352,800)／(640,800)——他们站在对白框的下槽区间内，因此对白框改用顶部槽位（重制表现选择，无原版顶部对白框证据；见 [表现合同](../../../architecture/PRESENTATION.md#opening-and-dialogue)），四人可见。緹娜 1007「只要通過這個寂靜之森，就是拉爾斯帝國了。」、琥 1008。
2. `02-monsters-pour-in.png`：十名 036（翼兽）、六名 038、五名 037（狼）自四边地图外 `actWalk`／`actWalkWait` 涌入（EVEF 负坐标／越界候场）。
3. `03-leonard-1009.png`：雷歐納德 1009「看來這寂靜之森將不再寂靜了。」；随后 `actShowSectionName SHAPE01\WORD007.SHP`、fail 0／event 0–2 status 登记，止于「寧靜之森 / 戰鬥部分（level 7）尚未重製」卡。

## 断言（headless）

45 个 STORY007 事件零跳过；三句对白顺序与说话人；雷歐納德终点 (448,704)；25 名 cast；配乐加载 track-13 槽位曲并在 `actPlayLevelMusic` 后播放；卡片；确认后交接 `world_map_scene.json`，world state `current_point 7`。

## 边界

- 只证明开场按 token 顺序播放与大地图往返；不证明原版镜头、走位速度与延时。
- 配乐：原表 `0x477b44` 给 level 7 track 13——与 level 1 同槽位，当时放重制原创曲（2026-09-26 起改放原曲，原创曲已删）。
- 战斗本体待 P-024 与多受控槽；两个 `寶藏`（EVEF 76／77）与 winfail007 未接入。

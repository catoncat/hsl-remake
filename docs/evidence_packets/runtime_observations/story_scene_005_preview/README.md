# Level 5 呼嘯平原 開場預覽（STORY005）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=5`（`STORY_SCENE_REVIEW_PASS shots=9`；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_5_preview`）。场景文件 `content/battles/story_005.json` 由 `python3 tools/hsl.py generate story_scene:5` 生成；campaign 注册 level 5 后，大地图到达呼嘯平原（bigmap 点 5，bmpmBattle）即交接进入，卡片确认回大地图仍站在点 5。

## 看到什么

1. `01-party-and-038-closing-in.png`：960×704 林间平原；`actSetBGToObject SID_雷歐納德` 锁镜头于雷歐納德；四人（雷歐納德／緹娜／琥／漢克斯）`actWalk` 到平原中央 (384,288)／(448,384)／(320,352)／(288,320)，五名 036（紫色翼兽）与四名 038 自四边地图外（EVEF 负坐标／越界）分别 `actWalk`／`actWalkWait` 合围。
2. `02-hanks-899.png`：漢克斯 899「不好，被包圍了！」、緹娜 900、雷歐納德 901「那還用說？當然是殺出一條血路啊！」。
3. `03-word005-title.png`：`actShowSectionName SHAPE01\WORD005.SHP`「猛狩 RAPTORIAL」；随后 win／fail／event status 0 登记，止于「呼嘯平原 / 戰鬥部分（level 5）尚未重製」卡。

## 断言（headless）

31 个 STORY005 事件零跳过；三句对白顺序与说话人；雷歐納德终点 (384,288)；镜头中心不出地图；13 名 cast；配乐为 track-18 槽位曲；卡片文案；确认后交接 `world_map_scene.json`，world state `current_point 5`。

## 边界

- 只证明开场按 token 顺序播放与大地图往返；不证明原版镜头、走位速度与延时。
- 配乐：原表 `0x477b44` 给 level 5 track 18——与 level 53 同槽位，重制曲《逃出克萊恩城》按"同一 track 同一曲"复用，不是等价声明。
- 战斗本体待 P-024 与多受控槽；`寶藏`（defProcTreasureBox，EVEF 17）与 winfail005 未接入。

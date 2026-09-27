# Level 3 盜賊洞窟 開場預覽（STORY003）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=3`（`STORY_SCENE_REVIEW_PASS shots=11`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_3_preview`）。场景文件 `content/battles/story_003.json` 由 `python3 tools/hsl.py generate story_scene:3` 从 `battle003_seed` 生成；campaign 注册 level 3 后，大地图自戈爾山道沿 track 2 到达盜賊洞窟（bigmap 点 3）即交接进入，卡片确认回大地图仍站在点 3。

## 看到什么

1. `01-cave-framed.png`：1152×672 洞窟地图；镜头夹在西缘（雷歐納德的 EVEF 槽位在地图外 (-64,288)——EVEF 放置坐标按有符号 32 位读取，此前工具把 0xFFFFFFC0 读成 4294967232）；右下可见 028 盜賊。`光01／02`（`engADDCOLOR`）为前景加色光，柱子／牆为站立物件。
2. `02-party-enters-west.png`：`actWalk`／`actWalkWait` 绝对像素目标——雷歐納德 (160,320)、緹娜 (96,320)、琥 (128,288) 自西缘外走入。
3. `03-raider-828.png`／`04-leonard-829.png`：两名盜賊迎上 (288,288)／(224,384)，`SID_ENEMY028` 说 828「什麼人！？」，雷歐納德 829。
4. `05-hanks-833.png`：`SID_漢克斯`（speaker 3，004 头像）说 833；STORY003 开头的 `actSetPlayerMode SID_漢克斯 pmEnemy`／`actSetPlayerUndead` 只记录（`player_mode_set`／`player_undead_flag`），预览按 EVEF 玩家槽绘制他。
5. `06-not-remade-card.png`：first_control_marker 处止于「盜賊洞窟 / 戰鬥部分（level 3）尚未重製 空格／點擊：回到大地圖（盜賊洞窟）」。

## 断言（headless）

31 个 STORY003 事件零跳过；6 句对白 828–833 按脚本顺序，说话人 盜賊／雷歐納德／漢克斯；终点 雷歐納德 (160,320)、緹娜 (96,320)、琥 (128,288)、盜賊 1 (288,288)；漢克斯起点 (1056,448)；镜头中心不越出地图左上；event status 0–2、fail 0／1 登记，遺言 741／742／846；卡片确认交接 `world_map_scene.json`，world state `current_point 3`。

## 边界

- 只证明 STORY003 开场在协调器 story 模式下按 token 顺序播放与大地图往返；不证明原版镜头初始位置、走位速度（`actWalk` 第五参 8 只记录为 speed_arg）与延时。
- 配乐：原表 `0x477b44` 给 level 3 track 14（static-derived：与 level 1＝13、2＝12 同一读取）；当时该槽位放重制原创曲（2026-09-26 起改放原曲，原创曲已删）。
- 战斗本体待 P-024（琥 jobBowMan 83）与多受控槽；漢克斯的敌对／不死战斗状态、`寶藏`（defProcTreasureBox）、winfail003 胜利事件（点事件／遭遇率改写、next level）未接入。

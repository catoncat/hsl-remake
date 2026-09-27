# Level 12 巴瀚納海峽 開場預覽（STORY012）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=12`（`STORY_SCENE_REVIEW_PASS`；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_12_preview`）。场景 `content/battles/story_012.json` 由 `python3 tools/hsl.py generate story_scene:12` 生成；大地图点 12 经 薛維斯港（点 11）船行到达。

## 看到什么

1. `01-deck-banter-1702.png`：1440×1920 甲板图（`shape11\level12.SHP`）；七名队员（雷歐納德／緹娜／琥／漢克斯／雪拉／雷特／嚎）按 EVEF 槽位站在甲板上，雷特 1702 讚嘆怒濤與晚霞、嚎 1704 不解。
2. `02-storm-deck.png`：`obj_Story_Level_RainBOSS` 四次与 `obj_Story_Level_RainSound` 插入后，雨滴（`12_RAIN` 帧段由 `obj_Story_Level_Rain` 提供）落满甲板与海面、雨声循环；62 个 Enemy101「船殼」（`SHAPE11\18_DOOR01.SHP`，无 SHAPEDEF 步行帧）作为站立物件绘出。
3. `03-boarders-1710.png`：32 名 Enemy038 以 `actWalkDisp`／`actWalkDispWait` 位移走上船，雷特 1710 叱责「破壞我海上的浪漫約會」；随后 `actShowSectionName SHAPE01\WORD012.SHP`、fail 0／event 0–1 登记，止于「巴瀚納海峽 / 戰鬥部分（level 12）尚未重製」卡。

## 断言（headless）

85 个 STORY012 事件零跳过；39 名 actor（7 队员＋32 名 038），雷特／嚎按槽位安装，Enemy101 不生成 actor 而以 62 个站立物件绘出；11 句对白按脚本顺序（1701–1709、728、1710），1702 雷特、1704 嚎；效果读法 `rain_emitter 4／background_sound 1`；卡片确认交接 `world_map_scene.json`，world state `current_point 12`。

## 边界

- 咕嚕／克羅蒂的 EVEF 槽位标为「有才產生」（有该队员才安装）；预览不建模此刻的队伍成员，故不安装，见场景 `unresolved_semantics`。
- 船殼以 defProcEnemy 进程存在于原作（可被攻击的船体部件）；预览只按 collide 字段将其画在前景层，不建模其战斗语义。
- 配乐：`actPlayMusic 9` 的原表 track 9 当时由重制原创曲填槽（2026-09-26 起改放原曲，原创曲已删）。
- 位移走位速度、雨密度与淡入为重制值；战斗本体待 P-024 与多受控槽。

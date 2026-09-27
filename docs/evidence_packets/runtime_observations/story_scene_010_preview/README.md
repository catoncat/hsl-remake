# Level 10 帕尼西亞城 廢墟 開場預覽（STORY010）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=10`（`STORY_SCENE_REVIEW_PASS shots=28`；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_registered_story_sweep` 与全程剧情 explorer）。场景 `content/battles/story_010.json` 由 `python3 tools/hsl.py generate story_scene:10` 生成；效果读法在 `game/battle/runtime/StoryEffectObjects.gd`。

## 看到什么

1. `01-rain-begins-1084.png`：960×704 廢墟；雷歐納德／緹娜自南缘外走到 (416,192)／(416,128)，1081–1083 对白后 `actInsertStoryObject obj_Story_Level10_RainBoss`（降雨BOSS，`mapobjDropRain`）两次与 `obj_Story_Level10_RainSound`（雨聲，`mapobjPlayBGSound WAV\RAIN001.WAV`）插入——雨滴（`10_RAIN001..003` 帧段）开始落下、雨声循环，緹娜 1084。
2. `02-lightning-firebomb.png`：`actScrollBGToPos 512,288` 把视野推到地图右下；`obj_Story_Level10_Lightn`（閃電，engZOOM 2×，`obj_Data7 5`）闪现淡出、`WAV\LIGHTN007.WAV`，全局对象 `obj_Effect_FireBomb`（OBJ-ALL.H 162，`FIR02_01..06` 一次性帧段，1.25×）在老树 (528,350) 炸开。
3. `03-burnt-tree-embers.png`：`actDeletePosObject 528,418,2,defProcStandObject` 隐藏 EVEF 樹02，`obj_Story_Level10_Tree`（樹03）立于原位，五个 `obj_Story_Level10_Fire`（火01，`FIR03_01..03` 5–7 像素小火星，engADDCOLOR 循环帧）与光環（`EAR32_01`，engADDCOLOR_MIX 光晕）叠在树上；雨持续。
4. `04-not-remade-card.png`：034／035 走入、1088–1093 对白、`actShowSectionName SHAPE01\WORD010.SHP`、fail 0／1 与 event 0–3·6 status 登记后，止于「帕尼西亞城　廢墟 / 戰鬥部分（level 10）尚未重製」卡。

## 断言（headless）

89 个 STORY010 事件零跳过；19 句对白按脚本顺序（1081、380、1082、1083、873、1084、1085、1086、380、1087、873、1088、797、1089、1090、1091、1092、1002、1093），1081 雷歐納德、1087 緹娜；效果读法计数 `rain_emitter 2／background_sound 1（looping）／flash 2／frame_once 4／glow 2／frame_loop 5`；雨发射器同屏雨滴峰值 >20；樹02 隐藏、樹03 可见、五个火01 节点存活；LIGHTN007×2 与 BOMB0027×1 已播放；镜头中心不越出地图；卡片确认交接 `world_map_scene.json`，world state `current_point 10`。

## 边界

- 效果读法只由物件字段驱动（`obj_Process_Code`／`obj_Mode`／`obj_Data*`／`obj_Shape_Number`）；雨密度与落带、16.16 速度按 40 Hz tick 换算、闪电／光环淡出曲线、火球帧时长均为重制值，不证明原版粒子数、时序或混色。
- `actScrollBGToPos` 沿用协调器现行"背景左上角"读法（视野夹在地图右下），老树因此出现在画面左上。
- 火01 的 `FIR03` 帧只有 5–7 像素、暗红加色，在暗地面上几乎不可辨——这是源 shape 的尺寸，不是绘制缺陷。
- 配乐：STORY010 `actPlayMusic 8` 用 track-8 宫廷曲；结尾 `actPlayLevelMusic` 解析到原表 `0x477b44` 的 track 15，当时切入重制原创曲（2026-09-26 起改放原曲，原创曲已删）。
- 战斗本体待 P-024：WINFAIL010 事件链由 `obj_Story_Player3–5` 让琥／漢克斯／雪拉入场；`寶藏`（EVEF 800,224）未接入。

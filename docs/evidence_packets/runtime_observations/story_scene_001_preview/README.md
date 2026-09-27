# Level 1 歐姆村 開場預覽（STORY001）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-26

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=1`（`STORY_SCENE_REVIEW_PASS shots=36`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_registered_story_sweep` 与全程剧情 explorer）。场景文件 `content/battles/story_001.json` 由 `python3 tools/hsl.py generate story_scene:1` 从 `battle001_seed` 生成；campaign 把 level 53 胜利的 winfail `[1,1]` 路由到它。

## 看到什么

1. `01-village-framed.png`：歐姆村清晨——EVEF 18 名 cast（8 村民、雷歐納德、琥、6 强盗、2 翼战士）按 EVEF 像素落位；地图 32 个站立物件加 26 组「树／房＋影」组合物件的 55 个子物件（首次由运行时消费 `combined_placements`）。
2. `02-leonard-calls-hu.png`：`SID_雷歐納德` 以 speaker 0 的头像说 708「琥！」；`SID_琥` 以 speaker 2（003 头像）说 705／707；命名玩家 token 通过 `player_installs` 绑定（不是 SID_PLAYERn）。
3. `03-village-house-alarm.png`：叙述 712（defNoOne，无头像）；村民按 STORY001 的 walk_disp 来回走动，房屋与水井为组合物件。
4. `04-raiders-march-north.png`：6 名 028 强盗与 2 名 036 翼战士从地图南缘外（EVEF y≥1184，地图高 1120）按脚本各北进 192／128px 进入画面；云影（CLOUD102，`engGLASS`）读为半透明暗影。
5. `05-raider-chief-725.png`：`SID_ENEMY028` 以职业名 632「盜賊」为 speaker 说 725–729／732。
6. `06-not-remade-card.png`：first_control_marker 处止于「歐姆村 / 戰鬥部分（level 1）尚未重製」卡片并回到第一战。

## 断言（headless）

81 个 STORY001 token 零跳过；30 个对白 token／29 个不同消息按脚本顺序；雷歐納德终点 (512,608)、强盗 1 终点 (480,1024)、翼战士 1 终点 (160,1088)；win 0/1、fail 0/1 status 记录，遗言 742/743 登记；无待处理战役承接；配乐开场为 track 8，开场末 `actPlayLevelMusic` 切到原表 track 13（2026-09-26 起改放原曲，原创曲已删）；全程镜头中心保持在 [320,960]×[240,880]（640×480 视口不越出 1280×1120 地图——聚焦地图外候场的强盗时也被 `clamped_position` 夹住；早先「画面走到地图下方」的猜想是把 CLOUD102 黑剪影误读为地图外区域，negative-evidence）。

## 边界

- 只证明 STORY001 开场在协调器 story 模式下按 token 顺序播放；不证明原版走位速度、延时时长、镜头与配乐（actPlayMusic,8 的 track 8 映射与 actPlayLevelMusic 的 track 13 原创曲均为重制读法，不是原曲重现）。
- 战斗本体（琥 jobBowMan 83、强盗 jobThief 88、翼战士 jobWingWarrior 92、村民 pmNPCPlayer）等待 source-research 的职业模型（P-024）；预览的 cast 只是演出。
- 组合物件的图层顺序与 `engGLASS` 的透明度（0.4）为 provisional。`mapobjCloud` 雲／雲影的漂移与回绕照原版读法，见[地图物件漂移](../../static_reverse/original_map_object_drift.md)。

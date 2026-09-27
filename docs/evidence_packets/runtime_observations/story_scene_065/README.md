# Level 65 廢都　曼多利亞　村民（STORY065）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=65`（`STORY_SCENE_REVIEW_PASS shots=23`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_65_story`）。场景文件 `content/battles/story_065.json` 由 `python3 tools/hsl.py generate story_scene:65` 从 `battle065_seed` 生成。level 65 是 STORY009 以 `actSetNextPlayLevelEvent 9,65` 串起的 story-only 过场（无 WINFAIL、自有地图 `shape41\level65.SHP` 640×480），为**完整重制**。

## 看到什么

1. `01-villager-1062.png`：室内单屏地图，`光01`（`engADDCOLOR`，前景加色）为窗口光柱；緹娜 1061 求助后村民三号 `actWalkWait` 到 (256,288) 说 1062「以我們現在的實力，想要去和沃斯菲塔對抗，別開玩笑了！」——`SID_ENEMY062` 按索引绑定 062 村民，说话人标签 656「村民」为 remake 标签（PLAYERS.TXT 名字字段 306 为 ???）。
2. `02-leonard-1075.png`：緹娜／漢克斯与村民往复 17 条 message token（含 380 两次）后，緹娜、漢克斯、琥、雪拉依次 `actWalkAndDelete` 至 (256,512) 离场；雷歐納德走到 (256,384) 说 1075，再离场。
3. `03-level-66-card.png`：`actSetNextPlayLevelEvent 9,66`——level 66 在 PAK 中没有 `level66.shp`（同 60／61–64／67–71 等无图 story 关），其 WRD 与 55／56／61／62／64／67–70 是同一张 1224 字节占位表，脚本 `#include OBJ-007.H` 也不是地图别名证据（8／9／65 有自有地图却同样 include）；原引擎的关卡→地图表未定位，故场景以卡片「後續劇情（level 66）尚未重製」结束并回大地图站点 9。

## 断言（headless）

45 个 STORY065 事件零跳过；16 个不同消息 ID 按序（380 复用）；说话人 村民 1062、雷歐納德 1075；五次 `actWalkAndDelete` 令全队隐藏且 `actor_deleted` 记录按 緹娜／漢克斯／琥／雪拉／雷歐納德 顺序；结束时无待处理交接（66 未注册）、卡片文案；Space 确认后 `CampaignProgress.pending` 指向 `world_map_scene.json`，world state `current_point 9`。

## 边界

- 证明 STORY065 按 token 顺序播放并以卡片回大地图；不证明原版镜头初始位置、走位速度与延时长度。
- 配乐：`actPlayMusic,8`——沿用重制 track-8 曲《渥斯菲塔宫廷》。
- level 66（大地图前最后一段：五人在某处对白后回大地图）待原引擎无图关卡的地图来源（已作为 P-033 REQUEST 交 source-research）。

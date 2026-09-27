# 战后营地／王座廳剧情链——略過戰鬥（視為勝利）續播（runtime-measured）

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-19

2026-09-19，presentation 线。窗口化 `tests/capture_story_scene_review.gd -- --level=2|55|63`（640×480，正常重制节奏）
与 headless `tests/run_story_scene_tests.gd` 的实际运行回执。数据链由并行工具线（P-044）按 58／60 的既有路径建成，
运行时接线与注册由本线完成。

## 玩家结果

- 大地图到达 戈爾山道（点 2）→ STORY002 开场预览 → 尚未重製卡片成两行选择：
  「略過戰鬥（視為勝利）→ 續播劇情『營地・黃昏』」／「回到大地圖（不施加戰果）」。
- 选第一行：WINFAIL002 胜利段的城镇／大地图写入（点 2 → event 501／Visit、遭遇率 20、路线 3 隐藏）施加到世界状态后进入
  `story_055.json`（營地・黃昏，32 句），`[2,56]` 接 `story_056.json`（營地・清晨，緹娜由 obj_Story_Player2 安装，10 句），
  `[2,gameBigMapLevel]` 回大地图站在点 2。carry 原样透传（gold 275）；被略过战斗的奖励／经验／入队不模拟。
- 同一路径：盜賊洞窟（3）→ 61 營地・漢克斯的報告 → 点 3（路线 3 揭示、歐姆村 exec event 10）；席達鎮（6）→ 62 → 63 王座廳・密報 → 点 6
  （路线 6 揭示）；寧靜之森（7）→ 64 營地・雪拉入隊 → 点 7。歐姆村（1）／呼嘯平原（5）／廢墟（10）／海峽（12）的胜利段不设下一关：
  第一行直接回大地图并施加胜利写入（5：点 5 event 507／遭遇率 100／席達鎮 exec 19／路线 6·15 隐藏；10：点 10 event 513；12：揭示点 13）。
- level 63 的密探以 `actShapeMessage,SHAPE\FACE0054|FACE0008.SHP,306,<id>` 说话：脚本自带人脸与名字资源 306（「???」）显示在对白板，五句全部可见。

## 帧

1. `01-level2-skip-card.png`：戈爾山道 预览结束卡——「戰鬥部分（level 2）尚未重製」下两行选择，第一行高亮（▶）。
2. `02-level2-skip-card-row2.png`：Down 后第二行「回到大地圖（不施加戰果）」高亮。
3. `03-camp-dusk-791.png`：`story_055.json` 營地・黃昏（`shape41\level55.SHP` 自有地图）——篝火 火01 站立物件、帐篷、三人围坐，緹娜 791。
4. `04-hall-spy-997.png`：`story_063.json` 王座廳・密報（地图别名 58）——密探经 FACE0054 人脸与「???」标签说 997。

## 自动验证

- `STORY_SCENE_TESTS_PASS`：level 2 预览 skip 行文案与目的地、Down／Up 环绕、Enter 交接 story_055、世界写入透传三关、
  55 的 32 个消息 token（791→818）、56 的十句顺序与緹娜安装、61／62→63／64 链（63 五张脚本人脸 `face_imported`、
  「???：」标签、克里歐司 999）、各预览卡片四行文案与胜利行目的地（6→story_062、7→story_064、10／12 回图带写入）。
- `CAMPAIGN_TESTS_PASS`：`[2,55]` 解析到 story_055，未注册的 57 解析为空。
- 窗口化：`STORY_SCENE_REVIEW_PASS` level 2 shots=15、level 55 shots=32、level 63 shots=19。

## 证据等级与边界

- 胜利段的 next level 与世界写入：static-derived（重建 winfail 文本，`tools/hsltools/levels/story_scene.py` 取首个 win 段；level 1／6 的多段结果一致）。
- 55／56 地图 resource-derived；61／62／64 别名 55、63 别名 58：provisional（`.wrd` 逐字节相同＋EVEF／说话人证据，引擎 level→map 表未定位）。
- 卡片两行的文案、光标、行距为重制读法；「視為勝利」只施加胜利段的城镇／大地图写入，不施加其对白、走位、`actSetPlayerMode` 入队与战斗奖励。
- `actShapeMessage` 的人脸位置与名字标签沿用对白板既有版式（重制表现）；原 handler 未定位。
- 营地场景的 EVEF `mapobjPlayBGSound`（夜晚聲 NIGHT001／鳥聲 YELL010）作 `background_sound` 放置由 `BattleSceneRuntime._start_background_sounds` 循环播放（−8 dB，重制值；不按放置坐标衰减）；headless 断言 55 的 `background_sound_records` 为一条 `looping` 且播放器在播。

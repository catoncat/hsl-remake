# Level 9 廢都　曼多利亞（STORY009）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=9`（`STORY_SCENE_REVIEW_PASS shots=9`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_9_story`）。场景文件 `content/battles/story_009.json` 由 `python3 tools/hsl.py generate story_scene:9` 从 `battle009_seed` 生成。level 9 是 story-only 过场（无 WINFAIL）：STORY008 把廢都（bigmap 点 9）改成战斗点后到达即进入，是**完整重制**。

## 看到什么

1. `01-ruins-framed.png`：1600×1184 废都地图；`actScrollBGToPos 608,32` 先框住北侧石造建筑，随后 `actScrollBGToPosSpeed 608,1152,4` 按脚本速度参数缓滚到南侧；14 名村民（061／062，`SID_ENEMY061／062` 按索引）先各自 `actWalk` 到指定点。
2. `02-party-enters-south.png`：`actSetWalkSoundMode 1` 后五人队自南缘外（EVEF y 1248–1312）走入，緹娜 `actWalkWait` 至 (672,1056) 再单独前行至 (800,928)。
3. `03-shera-1059.png`：緹娜 1057「終於......終於回來了........。」、漢克斯 1058「公主............。」后，`SID_雪拉` 说 1059「咦？公主？緹娜是公主？拉爾斯帝國的公主嗎？」——该行与雷歐納德的 380 在脚本中拼作 `actMEssage`，编译器按大小写不敏感归一后正常成为对白事件；緹娜 1060 收尾。
4. `04-handoff-into-level-65.png`：`actSetNextPlayLevelEvent 9,65` 交接进入已注册的 level 65（廢都室内，[回执](../story_scene_065/README.md)）；交接世界状态里脚本的 `actBMSetPointEvent 9,0,bmpmTown` 已施加——廢都恢复为城镇点（event 0）。

## 断言（headless）

42 个 STORY009 事件零跳过；五句对白顺序 1057／1058／1059／380／1060 与说话人（雪拉 1059）；緹娜终点 (704,1024)；19 名 cast；结束时 `CampaignProgress.pending` 指向 `story_065.json`，交接 world state `current_point 9`、点 9 类型 bmpmTown、event 0。前置条件由 `TownEventRules.apply_script_town_actions` 施加 STORY008 的 `actBMSetPointEvent 9,9,bmpmBattle` 得到。

## 边界

- 证明 STORY009 在协调器 story 模式下按 token 顺序播放并把点 9 改写带回世界状态；不证明原版镜头滚动速度（`actScrollBGToPosSpeed` 第三参 4 的原始换算）、走位速度与延时长度。
- `actSetWalkSoundMode 1／0` 只记录（重制版无步行音效开关）。
- 配乐：`actPlayMusic,8`——沿用重制 track-8 曲《渥斯菲塔宫廷》。
- 链 9 → 65 → 66 → 大地图（点 9）：65 已接入，66 无自有地图 shape（见 65 回执的边界）；回大地图后点 9 为无初始菜单树的城镇（曼多力亞 TOWNDEF 事件由后续脚本 actAddTE 加入），城镇画面行为未在此验证。

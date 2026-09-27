# Level 8 菲納斯河畔（STORY008）— runtime-measured

> evidence: runtime-measured · status: live · tools: capture_story_scene_review.gd, hsltools/levels/story_scene.py, run_story_scene_tests.gd · updated: 2026-09-18

来源：`tools/play.sh --script res://tests/capture_story_scene_review.gd --resolution 640x480 --screen 0 -- --level=8`（`STORY_SCENE_REVIEW_PASS shots=9`，正常重制节奏；headless 回归为 `tests/run_story_scene_tests.gd` 的 `_run_level_8_story`）。场景文件 `content/battles/story_008.json` 由 `python3 tools/hsl.py generate story_scene:8` 从 `battle008_seed` 生成。level 8 是主线 22 段 story-only 过场之一（无 WINFAIL），因此这是**完整重制**而非开场预览：大地图到达菲納斯河畔（bigmap 点 8）即进入，播完自动回大地图。

## 看到什么

1. `01-party-walks-up.png`：1504×800 河畔地图（木桥、溪石、树）；五人队自地图南缘外（EVEF y 864–928）按 `actWalk` 绝对像素目标走入；镜头 `actScrollBGToPos 1472,768` 后跟随雷歐納德。
2. `02-shera-1053.png`：`SID_雪拉`（speaker 4，005 头像，首次在重制版出场）说 1053「對了對了，雪拉還沒問你們到拉爾斯來要幹什麼？」；对白 1052／1053／1054／1055／380／1056 六句按脚本顺序。
3. `03-tina-1056.png`：緹娜 1056「好了，不要吵了，趕快趕路吧。」之后五人相隔 12 帧依次 `actWalk` 到 (512,512) 向西离开。
4. `04-back-on-map-point-8.png`：`actSetNextPlayLevelEvent 8,gameBigMapLevel` 结束场景并交接回大地图，队伍站在菲納斯河畔；脚本的 `actBMSetPointEvent 9,9,bmpmBattle` 已由 `WorldScriptActions.apply_story` 施加——廢都 曼多利亞 由城镇标记改为战斗标记（橙）；`actBMSetPointEvent 8,8,bmpmVisit` 与 `actBMSetPointEncounterRatio 8,0` 同时落入世界状态。

## 断言（headless）

41 个 STORY008 事件零跳过；六句对白顺序与说话人（雪拉 1053、漢克斯 1054）；雪拉起点 (1376,928)；场景结束 `CampaignProgress.pending` 指向 `world_map_scene.json`，world state `current_point 8`、点 8 含 bmpmVisit、点 9 类型 bmpmBattle、encounter_ratios["8"] = 0；carry 金币 275 不变。

## 边界

- 证明 STORY008 在协调器 story 模式下按 token 顺序播放并把大地图改写带回世界状态；不证明原版镜头初始位置、走位速度与延时长度。
- 配乐：`actPlayMusic,8`——与 level 1／58／60 同用重制 track-8 曲《渥斯菲塔宫廷》，不是原曲重现。
- 遺言 846／742／906／1034 只登记（story-only 场景无死亡）。
- 廢都（点 9）变战斗点后进入的 level 9 也是 story-only 过场（STORY009 → level 65），尚未接入。

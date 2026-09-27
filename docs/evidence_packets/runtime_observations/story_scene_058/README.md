# Level 58 story scene（沃斯菲塔王座廳）runtime observation

> evidence: runtime-measured; provisional · status: live · tools: capture_story_scene_review.gd, run_story_scene_tests.gd · updated: 2026-09-18

- 采集日期：2026-09-18；分支 presentation-line；Godot 4.7.2 可见窗口 640×480（`tools/play.sh --screen 0 --script res://tests/capture_story_scene_review.gd`），正常重制节奏。
- 证据等级：**runtime-measured**（重制版自身行为）；对原作的关系全部 **provisional**。
- 完整原始输出（24 张 PNG＋manifest.json）留在 `ignored/story-scene-058-review/`；本包只提升 7 帧。

## 观察到的结果

1. `BattleSceneRuntime` 以 `scenario_path=content/battles/story_058.json`、`startup_mode=product_opening` 启动：`level_kind: story` 分支不创建 PlayLoop（`play_loop == {}`），`BattleOpeningCoordinator` 进入 `story_mode`，从 `story_actors`（EVEF 记录顺序绑定 token／instance）生成 12 个演出 actor：Leonard、058 克里歐司、027×2、024×8。首 token `actSetBGToObject(SID_ENEMY058)` 把镜头对准王座（`00-throne-framed`）。
2. STORY058 全部 53 个 token 按源顺序播放，无跳过：18 句对白（658–675）经共享对白板分页，027 使用 PLAYERS 名 `???`（`dialogue-658`），058 使用 克里歐司（`dialogue-663`）；`defNoOne` 的 675 以无肖像叙述模式显示于黑屏之上（`dialogue-675`）。
3. 前向脚本运动：`actWalkWait`／`actWalk`／`actWalkDisp` 从 EVEF 像素起点走到脚本绝对像素；`actWalkFollow(Wait)` 以领队起点偏移跟随（`escort-follows`）；`actWalkAndDelete` 走完后隐藏 Leonard 与两名护卫（3 条 `actor_deleted` 记录）。
4. `actInsertStoryObject(obj_Star,288,320)` 以 `MAGIC/AIR06_04.SHP` 预览图（徽章）静态放置（`medal-thrown`）；`actPlaySound` COIN001／COIN002 播放（2 条 `played`）；`actPlayMusic,8` 启动原创配乐《沃斯菲塔王座廳》。
5. `actDarkScreen` 0.8 s 淡黑；`actSetNextPlayLevelEvent(60,60)` 记录后到达 `scene_end_marker`：campaign.json 无 level 60 条目，因此显示章末卡「第一章　完 / level 60 尚未重製」并阻塞输入，空格／点击经 `CampaignProgress.restart_campaign()` 清空战役状态回到第一战（`chapter-end-card`）。若存在下一场景，`start_story_handoff` 会把收到的 carry 原样交给下一关。
6. 本次采集总时长 24.7 s，15 段运动记录，headless `tests/run_story_scene_tests.gd` 覆盖同一路径（`STORY_SCENE_TESTS_PASS`）。

## 边界（不支持的结论）

- 走路速度 160 px/s、跟随偏移规则、淡黑 0.8 s、对白分页、音乐曲目 8 均为重制取值；原作 `defProcObjectMove` 徽章飞行、`actWalkFollow` 精确语义、`actWalkAndDelete` 的删除时机未验证。
- 角色 027 的身份为 PLAYERS `???`；未用推断姓名。
- 章末卡与「回到第一战」是重制流程；原作 level 60 之后的承接未重制，跨关存档仍未实现。

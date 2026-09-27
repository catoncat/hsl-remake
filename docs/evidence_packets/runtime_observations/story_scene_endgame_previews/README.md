# 终章链预览与过场（59／73／75–82）——接入回执（runtime-measured）

> evidence: runtime-measured · status: live · tools: capture_game_clear_review.gd, capture_story_scene_review.gd · updated: 2026-09-19

2026-09-19，presentation 线。数据链由子线 ch3（`773015b`／`b9f8d6d`，[P-049](../../../collaboration/presentation.md)）建成并由本线合并注册；
窗口化 `tests/capture_story_scene_review.gd -- --level=73|82` 与 headless 套件的实际运行回执。

## 玩家结果

- 至此 PAK 中全部 66 个带 STORY 脚本的主范围关卡均已注册：终章 41→73 悲嘆之湖・兄弟的抉擇（雷特 的二选一，两支都回图并写 斐達克 事件）、
  45→75 塔克斯→57 塔克斯之死、76 妖精王→81 告白→59 劫數、77 席德爾→82 終幕、78 接觸→79 終焉、38→80 墳場地下。
- 59／79／82 以 `actSetNextPlayLevelEvent 90,998` 收尾：level 998 GameClear 谢幕已重制为 `game/title/GameClearScreen`（先在黑场上播 STORYOVER 尾声独白——緹娜／漢克斯 十句、脚本停顿与 WALKSOUND 脚步声、点击确认逐句，[加载者证据](../../static_reverse/original_game_clear_epilogue.md)；再 OverBG01／02 上的 Over001／002 结语、TITLE011 卡上的逐槽队员展示、workteam 制作群卷轴到「劇終」，任意键跳段，卷毕回标题；配乐《破滅之後》），通关时清自动存档的战役位置；82 的「幻世錄　完」卡片只在 998 未注册时出现。59 预览的 略過戰鬥（視為勝利） 行先播原结尾动画 end.ani 再进 GameClear（[播放回执](../original_movies_playback/README.md)）。
- STORY 内的 `actSelectInsertEvent` 提示（73 由 雷特 选择、900 由 雷歐納德 选择）以 WINDOW50 选项按钮呈现，所选 winfail 事件链拼入时间线继续播放。

## 帧

1. `01-level73-choice-prompt.png`：悲嘆之湖（level 41 地图别名）——「雷特：請選擇」与两行选项（1.老哥，別怨我!／2.我.....我辦不到!）。
2. `02-level82-finale-2378.png`：終幕（王座廳 地图别名）——最后一句 2378。
3. `03-level82-game-clear-card.png`：「幻世錄　完」卡片——998 未注册时的兜底（现已注册 GameClear，82 直接交接）。
4. `04-game-clear-showcase.png`：GameClear 队员展示（TITLE011 夕阳卡＋肖像＋名字，逐槽淡入淡出；`tests/capture_game_clear_review.gd`）。
5. `05-game-clear-credits.png`：制作群卷轴（workteam）上卷中。
6. `06-game-clear-storyover-2396.png`：GameClear 开头黑场上的 STORYOVER 首句（緹娜 2396，共享对白板＋肖像）。
7. `07-game-clear-storyover-2404.png`：STORYOVER 末句（緹娜 2404）；此后 actDeleteDarkScreen 淡入 OverBG01。

## 自动验证

- `STORY_SCENE_TESTS_PASS`：`_run_registered_story_sweep` 严格等于当前注册 story 集合（66 主范围＋900／901）逐个启动、跑完、交接或卡片；
  跳过 token 仅允许场景 unresolved 中说明的条件成员／无安装 token（STORY078 SID_咕嚕）；82 的终局卡片视为合法结尾。
- 窗口化 `STORY_SCENE_REVIEW_PASS` level 73 shots=12（含 select-prompt）、level 82 shots=13。

## 证据等级与边界

- 别名：73→41、75→57、76–79／81／82→58 以 obs 地圖管理員 记录为主证据（resource-derived；loader 未定位）。
- STORYOVER 由 `defProcClearBOSS` 加载（static-derived）；独白与 OverBG01 的先后由其 actDeleteDarkScreen 推断，对白板、肖像、点击确认与 0.025 s 的 actDelay 单位为重制读法。
- 57 的 `actSetNextPlayLevelGetOverEvent 0` 依 over-score／flag 在 76／77／78 间选结局路线：选择表未定位，57 暂以卡片回图；73 两支追加 event 2 的顺序为重制读法；78 无 win 段，skip 以第 10 回合 event 2 代替。
- 配乐：track 4／10 无重制曲，以 王座廳 stand-in；其余按原表 track 复用既有重制曲。
- 只记录的 opcode：actEnterStorageWindow／actKeepPlayerST／actSetNextPlayLevelGetOverEvent／actPlayMovie（movie.pak 未导入）／actSetDoublePageMode／actEarthQuake／actUseItem。
- 终战本体、九槽受控与第三章职业模型未重制。

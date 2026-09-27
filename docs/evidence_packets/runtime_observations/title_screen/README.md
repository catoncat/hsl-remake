# 標題畫面（Title001／002／021–028）— runtime-measured

> evidence: runtime-measured; resource-derived · status: live · tools: capture_title_review.gd, hsl_title_layout_probe.py, hsltools/assets/title_assets.py, run_title_screen_tests.gd · updated: 2026-09-26

来源：`tools/play.sh --script res://tests/capture_title_review.gd --resolution 640x480 --screen 0`（`TITLE_REVIEW_PASS shots=7`；headless 回归为 `tests/run_title_screen_tests.gd`）。资源与布局由 `tools/hsltools/assets/title_assets.py` 生成到 `content/imported/hsl/global/title/manifest.json`（resource-derived：PAK `@:\shape\TitleNNN.SHP` 解码、SHP 头绘制原点；布局 runtime-measured：`tools/hsl_title_layout_probe.py` 把各 shape 对原录像参考帧 [01/frame_001（重制画面）](../../../screenshots/remake/title-framed.png)（原版帧见私有档案：`runtime_observations/original_gameplay_reference/01_title_and_opening/frame_001.png`） 做模板匹配，亮起项对圆环 shape 匹配）。场景 `game/title/TitleScreen.tscn` 现为 `project.godot` 主场景。

## 看到什么

1. `01-title-framed.png`：Title001 海面断像背景、Title002「幻世錄 ～The Legend of Fancy Realm～」标志（左上 (99,12)）、Title021 圆环菜单（(197,161)）、Title022／023 左右石像（(117,227)／(405,227)）、Title027 宝珠与 Title028 书分居第一项「開始新故事」两侧（(216,257)／(386,243) 为参考帧位置，二者各自竖直浮动，见下）。与参考帧逐 shape 匹配的平均色差 10–22（录像有损）；圆环内三行字位置与参考一致。
2. `02-hover-battle-record-lit.png`：鼠标悬停「戰場記錄」时该行改用红字带焰的 Title025 亮起版；宝珠与书留在第一项旁，不随选择移动（原版实录 [original_title_ornaments](../original_title_ornaments/README.md)：停在哪一项平均位置差 ≤0.3 px）。
3. `03-no-record-hint.png`：无存档时选「戰場記錄」不离开标题，底部提示「沒有戰場記錄」约 1.6 秒。
4. `04-product-opening-after-fade.png`：「開始新故事」清空战役进度、黑场淡出 0.6 秒后进入 `BattleSceneRuntime` 的正式开场（level 51）。参考录像 01 接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/01_title_and_opening/contact_sheet.jpg`） 的 frame_005／009 亦为标题→黑场→开场地图淡入，时长未测。
5. `05-game-over.png`：败北战斗结束淡黑后的 GAME OVER 画面（重制原先经败北结果页「回主選單 · Esc」进入，结果页已按原版删除，见 [战斗结束流程](../../static_reverse/original_battle_end_flow.md)）——Title011 夕阳底图＋Title012 文字（左上 (55,211)，按其中心原点居中于 640×480，provisional），黑场淡入 0.9 秒后等待任意键，再淡出 0.6 秒回标题。

## 断言（headless）

三项菜单 `new_story／battle_record／quit`；标志、圆环、石像位于 manifest 布局坐标；选中第 1／2／3 项时宝珠与书各采一个浮动周期：水平不动、竖直在参考位置上 2 px 到下 8 px 之间往返、两件各有起始相位；上下键／换行选择并让选中项亮起；悬停命中项亮起、离开熄灭；「離開遊戲」在 headless 只记录 `quit_requested`；无存档的「戰場記錄」返回 `no_record` 并显示提示、不装 hand-off；有第一战检查点时「戰場記錄」进入第一战并直接恢复（`runtime_entrypoint == restored_battle_checkpoint`）；有存档（story_002 位置）的「戰場記錄」装入 pending hand-off、淡出后 `current_scene` 为 story 模式的 `BattleSceneRuntime`（scenario story_002）；「開始新故事」清空 `campaign_progress.json`、淡出后进入 `product_opening`／`first_battle.json`。

## 边界

- 窗口复核 `tools/godot.sh --script res://tests/capture_ui_reference_review.gd` 连拍 4 s（悬停依次移过三项）并写出逐帧宝珠／书位置表。
- 宝珠与书的浮动按原版实录（runtime-measured，4–5 帧／秒采样）：周期 1.646 s、振幅 5 px 的正弦，围绕参考帧位置下方 3 px 往返；周期与振幅是拟合值，两件起始相位在进入标题时随机取（原版两件相位差在三组采样间不一致，不做同步或反相）——provisional，替换证据为 `hsl_win32_memread.exe --repeat` 找到的浮动计数器。
- 标题 handler 未在 EXE 定位：亮起项出现条件（悬停；键盘选择后亮选中项为重制读法）、淡出时长、按键映射均为重制读法（provisional）。
- 菜单语义为重制读法：「戰場記錄」优先恢复最近一份战斗检查点（原版 戰場記錄 的语义），否则接现有单槽战役进度（`CampaignProgress`）；回憶錄 八槽走战间卷轴（见 [system_menu](../system_menu/README.md)）；「開始新故事」清空进度（不清回憶錄与检查点）。
- 败北战斗结束约 0.2 s 淡黑后直接进入 GAME OVER 画面（原版 0x42cbd0，无结果页；160 tick 无输入也自行回标题，0x42aea0）（`05-game-over.png`：Title011 夕阳底图＋Title012 文字居中，黑场淡入 0.9 秒后任意键淡出 0.6 秒回标题）；原版败北画面无录像，位置／时长／解除输入为重制读法，存档与战役进度不清除。
- 标题曲为原曲 03：关卡 0 在厂商标志之后放表内曲目 03，离开关卡时立即停乐（[原版配乐](../../static_reverse/original_music.md) §3.1）。GAME OVER（Title011／012）、設定選項（Title039）、系统菜单（Title041–057）、確定／取消（Title061–063）已在 PAK 中、尚未导入。
- 参考帧为 638×480 简体版录像；PAK 的标题字形亦为简体（开始新故事／战场记录／离开游戏），重制自身文字沿用 RESOURCE 的繁体。

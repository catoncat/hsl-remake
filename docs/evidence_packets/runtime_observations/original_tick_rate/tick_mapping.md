# 36 格 remake-invented 时序 → 原版 tick 的映射表

> evidence: runtime-measured: tick period and walk／idle cadence; static-derived: native tick counts cited per row and in original_tick_counts.md; resource-derived: object shape_delay and teDelay fields; provisional: rows marked B · status: live · functions: 0x407230, 0x43bf30, 0x43e4a0, 0x43e570, 0x450840, 0x453b90, 0x454e20, 0x45e5a6, 0x45e80d, 0x45e882, 0x45e91e, 0x46098f, 0x4609c0, 0x46bede · tools: hsl_win32_memread.c · updated: 2026-09-28

## 结论

- 原版演出计数以主循环 tick 为单位，设计 16 ms/tick（62.5 tick/s），本机 Wine 实测 19.4 ms/tick（[README](README.md)，runtime-measured）。
- [docs/PROVENANCE.md](../../../PROVENANCE.md) 中 timing＝`remake-invented` 的 36 格逐格分为 A 可直接换算／B 以 tick 计但计数未读／C 与 tick 无关；重制唯一换算常数在 `game/common/OriginalTick.gd`，A 类全部经它表达，B 类读出的计数记在 [original_tick_counts.md](../../static_reverse/original_tick_counts.md)（static-derived）。
- 处置后 remake-invented timing 剩 8 格有意保留（C 或产品取舍），B 类未读的保留现值标 provisional（provisional）。

## 证据

### 分类

- **A 可直接换算**：原版计数已知（static／resource），乘 16 ms 即得。
- **B 以 tick 计但计数未读**：原版确以主循环 tick 为单位，但具体计数还没人读；给出要读的函数／字段，读到就落入 A。
- **C 与 tick 无关**：原版没有对应演出（重制自创的过渡、淡入淡出、提示节拍），tick 率量出来也换不了；保留为重制改善，或删掉。

### 36 格映射（按 16 ms/tick；按本机体验 19.4 ms 对标时秒数乘 1.2125）

| # | 模块 | 常数／现值 | 类 | 原版依据 | 按 16 ms/tick 应为 |
| --- | --- | --- | --- | --- | --- |
| 1 | [BattleAftermath](../../../../game/battle/scene/BattleAftermath.gd) | `FADE_SECONDS`＝`DEATH_TICKS 16` tick、`REWARD_SECONDS`＝`SHOW_NUMBER_SECONDS` | A | 已读：阵亡处置每 tick 纵向 +0.25、层级 −1，16 tick 消失（`0x43eff9..0x43f0e6`）；EXP／$ 等 `defProcShowNumber` 层级 16 停 16 tick 后每 2 tick 降一级、第 46 tick 删除，下一段奖励在第 32 tick 放行，KILL 连击数字 40 tick（`BattleRewardFloater`，[tick 计数](../../static_reverse/original_tick_counts.md)） | 已换算 |
| 2 | [BattleAttackCue](../../../../game/battle/scene/BattleAttackCue.gd) | `0.24＋0.22＋0.24 s` 引导 | C → A | 已读出 AI 起手状态（[施法覆盖层「起手节拍」](../../static_reverse/original_cast_overlays.md#起手节拍)）：普攻 6＋滑动＋12 tick，施法 24＋滑动＋24 tick，滑动 `0x45e882` 按距离；玩家确认无起手 | 普攻一格 (6＋15＋12)×16 ms＝0.528 s；施法一格 (24＋15＋24)×16 ms＝1.008 s |
| 3 | [BattleCombatCutin](../../../../game/battle/scene/BattleCombatCutin.gd) | manifest `presentation_fps 60`（ANIMAL `complete_updates／fps`）、`PLAYBACK_SPEED 0.4`、`SPELL_TICKS_PER_SECOND 100` | A | ANIMAL 程序每 tick 推进一条／一 delay；魔法脚本 Wait 单位是 tick | `presentation_fps → 62.5`；`SPELL_TICKS_PER_SECOND → 62.5`；`PLAYBACK_SPEED 0.4` 是重制倍率（C，若要原速取 1.0） |
| 4 | [BattleCommandMenu](../../../../game/battle/scene/BattleCommandMenu.gd) | `HOVER_UPDATES_PER_SECOND 60` | A | 悬停换帧与展开步进都是每 tick 一次调用（`0x45e5a6`／`0x45e80d`，[native_presentation_helpers](../../static_reverse/native_presentation_helpers.md)） | `62.5`（D=6 → 7 tick／帧 = 112 ms） |
| 5 | [BattleDepartureView](../../../../game/battle/scene/BattleDepartureView.gd) | `FADE_SECONDS 0.24` | A | 离场阶段 0x35／0x36 计 16 tick（`0x454286`／`0x4542a7`） | **0.256 s**（原版是 16 tick 后直接注销，无淡出；淡出形式本身是 C） |
| 6 | [BattleDialogue](../../../../game/battle/scene/BattleDialogue.gd) | 四行窗口、字体、行距；淡入淡出、擦出、上卷 | A | 对白框过程 `0x414280` 已读（[对白框包](../../static_reverse/original_dialogue_board.md)）：淡入淡出 16 tick、擦出 3 px/tick（17→112 px）、上卷 3 px/tick（10 tick／行）；原版没有逐字显示 | 淡入淡出 **0.256 s**；满窗擦出 32 tick＝0.512 s；上卷 0.16 s／行 |
| 7 | [BattleExtraActionCue](../../../../game/battle/scene/BattleExtraActionCue.gd) | `DURATION 0.55` | C | 原版无「再次行動」提示 | — |
| 8 | [BattleNavigationCue](../../../../game/battle/scene/BattleNavigationCue.gd) | `WAIT_SECONDS 0.55` | C | 原版无待機／守候提示节拍 | — |
| 9 | [BattlePresentation](../../../../game/battle/scene/BattlePresentation.gd) | 伤害浮字 `0.7 s` 上浮（已改）、结果页 `0.3 s` 淡出＋`0.6 s` 延迟 | A／C | 地图伤害／回复数字是 `defProcShowNumber`（kind 0 弹跳、kind 2／3）：kind 0 为 10×位数＋34 tick，kind 2／3 为 hold＋46 tick（[tick 计数 §1](../../static_reverse/original_tick_counts.md)）；结果页淡出为 C | 已按此落地（`ResultNumberFloater`） |
| 10 | [BattleScriptActorPresentation](../../../../game/battle/scene/BattleScriptActorPresentation.gd) | 揭示 `coordinator.default_step_seconds 0.04` | A | 原 STORY VM（`0x450840`）连续执行非等待 token，到等待类 opcode 才让出（[original_script_wait](../../static_reverse/original_script_wait.md)、[original_auto_growth](../../static_reverse/original_auto_growth.md) 的 opcode56 序列） | `0`（同 tick）；重制若要可见节拍取 1 tick = `0.016 s` |
| 11 | [BattleScriptCoordinator](../../../../game/battle/scene/BattleScriptCoordinator.gd) | 继承开场协调器（行 28） | A | 同 28 | 同 28 |
| 12 | ~~FirstBattleStoryStage~~（已删除，信使走 [BattleOpeningCoordinator](../../../../game/battle/runtime/BattleOpeningCoordinator.gd) 的脚本走位） | 信使斜走 `0.5 s`／段；离场沿 `MOVE_CELL_PRESENTATION_SECONDS` | A／B | 玩家行走实测 4 px/tick（32 px = 8 tick）；脚本 `actWalk*` 的 speed 参数已读（[剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)，`0x453b90` 状态 0x32 sub 2）：1→1、2／3→2、0／4→4、8→8 px/tick，每格 32/步长 tick | 玩家格 `0.128 s`；信使若同速 45 px ≈ 11 tick = `0.18 s`；确认 speed 参数后落 A |
| 13 | [BattleSystemMenu](../../../../game/battle/scene/BattleSystemMenu.gd) | 卷轴逐 tick 步进、`HINT_SECONDS 1.6` | A／C | 卷轴 `0x4253f0`／`0x425a90`：展开 `0x45e882` 每 tick min(40, 距离>>3)、至少 2，收起 `0x45e91e` 40 px/tick（[menus_ui](../menus_ui/README.md) §6）；提示 1.6 s 无原版对应 | `HINT` 为 C |
| 14 | [BattleTreasurePresentation](../../../../game/battle/scene/BattleTreasurePresentation.gd) | `DURATION 0.45` 淡出 | C | 原版宝箱领取后直接处置，无淡出（[original_treasure](../../static_reverse/original_treasure.md)） | — |
| 15 | [BattleTurnEndCue](../../../../game/battle/scene/BattleTurnEndCue.gd) | `EVENT_SECONDS 0.7`／事件 | A（间隔）／B（寿命） | HP 数字后 MP 数字延迟 **40 tick**（[original_resource_recovery](../../static_reverse/original_resource_recovery.md)）；数字寿命见 9 | 事件间隔 **0.64 s**；数字停留读 `0x408580` |
| 16 | [BattlePlayLoop](../../../../game/sim/loop/BattlePlayLoop.gd) | `MOVE_CELL_PRESENTATION_SECONDS 0.20`／格 | A | 实测 4 px/tick → 32 px = 8 tick | **0.128 s**／格（本机体验 0.155 s） |
| 17 | [BattleSceneRuntime](../../../../game/battle/scene/BattleSceneRuntime.gd) | 章节标题 `1.4 s`、结果音乐淡出 `1.2 s`、自动推进 `0.04／0.06／0.14 s`、`AI_PLAYBACK_STEP_SECONDS 0.35` | C／A | 标题淡入淡出与音乐淡出无原版对应，原章节标题停留未读；自动推进 token 步同行 10 | 自动推进 `0.016 s`／token；其余 C |
| 18 | [MagicImpactPresentation](../../../../game/battle/scene/MagicImpactPresentation.gd) | `BEFORE_TICKS 21`、`NUMBER_TICKS 29`、`BAR_TICKS 60`（已改） | A／B | 数字为 `defProcShowNumber`：红字 kind 0 为 10×位数＋34 tick，MISS kind 5 为 46 tick；受者条的三个节拍由 2026-09-24 录屏按 19.4 ms/tick 折回（[魔法伤害包](../../static_reverse/original_magic_damage.md)），计数未静态读出 | 已按此落地 |
| 19 | [MoonDancePresentation](../../../../game/battle/scene/MoonDancePresentation.gd) | `TICKS_PER_SECOND 100` × `PLAYBACK_SPEED 0.4` | A | moon_dance.json 的 delay 比值是 tick | `62.5` tick/s（×0.4 倍率是 C；原速取 1.0） |
| 20 | ~~ParalysisMagicPresentation~~（已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `tick = (t − CAST_LEAD_IN) × 100` | A | 源对象 `shape_delay` 以 tick 计 | `× 62.5` |
| 21 | [PoisonArrowPresentation](../../../../game/battle/scene/PoisonArrowPresentation.gd) | 100 Hz 时钟、`LEAD 0.65` | A／C | manifest 源 tick 顺序；`LEAD` 为重制引导 | `62.5` Hz；`LEAD` C |
| 22 | ~~StatMagicPresentation~~（已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | impact／complete `tick / 100`、`tick = (t − lead) × 100` | A | 源 Wait 单位 tick | `/ 62.5`、`× 62.5` |
| 23 | ~~StatusMagicPresentation~~（已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `0.55 s` 扩散、`0.18／0.4 s` 淡入出 | C | 这些法术没有导入源特效对象（provenance 已注明） | — |
| 24 | ~~SupportMagicPresentation~~（已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | impact／complete `/ 100`、`tick = … × 100`、施法帧 `elapsed × 30` | A／C | 源 Wait 单位 tick；施法帧 30 fps 为重制 | `/ 62.5`、`× 62.5`；施法帧若按 ANIMAL delay 则同 3 |
| 25 | ~~WaterStrikePresentation~~（已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `tick = (elapsed − lead) × 100` | A | 同上 | `× 62.5` |
| 26 | [ActorRuntime](../../../../game/battle/runtime/ActorRuntime.gd) | 移动 tween（来自 16）、`_override_fps 8`、待机 manifest `fps 8` | A | 实测待机 11 tick／帧、行走 3 tick／帧；脚本形状覆盖（绳降等）用对象自身 `shape_delay` | 待机 **5.68 fps**（62.5/11）、行走 **20.8 fps**（62.5/3）；覆盖帧率取 `62.5/(delay+1)`。注意 PROVENANCE 把待机 8 fps 记为 resource-derived，实为 manifest 的 provisional 值 |
| 27 | [BattleCameraController](../../../../game/common/BattleCameraController.gd) | 边缘平移 `EDGE_SCROLL_PIXELS_PER_TICK 12` × 62.5 tick/s | A | 已读：地图光标过程 `0x43e570`（只在玩家过程的四个选格／选目标子态 `0x443e2a`／`0x4445b7`／`0x444fe6`／`0x445286` 每 tick 调用）调 `0x43e4a0`，边缘或方向键请求 ±12（修饰键 ±24），帧尾 `0x46bede` 一次加到镜头并夹取（[tick 计数](../../static_reverse/original_tick_counts.md) `0x43e570` 一段）；剧情居中缓动的每 tick 步进见 [剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)（`0x43bf30` 逐轴 `min(step, 剩余/2)`，step 16／32） | 已换算：**750 px/s**；修饰键 ±24 的倍速未接 |
| 28 | [BattleOpeningCoordinator](../../../../game/battle/runtime/BattleOpeningCoordinator.gd) | `delay_token_seconds 0.025`、`default_step_seconds 0.04`、`walk_pixels_per_second 160`、`min_walk_seconds 0.35`、`walk_margin_seconds 0.14`、`camera_scroll_seconds 0.6`、`title_seconds 1.4`、`move_pixels_per_frame_hz 60` | A／B／C | `actDelay(n)` = n tick；`actMoveDispWait` speed 走行走表 `0x4543d8`（[tick 计数 §4](../../static_reverse/original_tick_counts.md)）；行走 speed 参数与镜头每 tick 步进已读（[剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)：speed→1／2／4／8 px/tick；居中缓动逐轴 `min(step, 剩余/2)`，剧情位 step 16，tol 4）；章节标题停留由脚本 actDelay 给出 | `delay_token → 0.016`；`default_step → 0.016`；`move_pixels_per_frame_hz → 62.5`；行走若同玩家 4 px/tick → **250 px/s**（B）；`min_walk`／`margin`／`title 1.4` 为 C；镜头 B |
| 29 | [CombatPresentationTiming](../../../../game/battle/runtime/CombatPresentationTiming.gd) | `TARGET_PAUSE 0.12`、`HURT_HOLD 0.60`、`RECOVERY 0.16`、`CAST_LEAD_IN 0.44`（源钟单位 ×0.4）；`ordinary(actor, fps)` | A（fps）／B（受击） | 攻方时长 = ANIMAL `complete_updates` tick；受击停留在 ANIMAL 守方程序里（未按 tick 读出） | `fps → 62.5`；受击／恢复读守方程序的 aniDelay 和 → ×16 ms |
| 30 | [MapObjectFlash](../../../../game/battle/runtime/MapObjectFlash.gd) | 逐 tick 计数器（`OriginalTick.TICK_SECONDS`）（已改） | A | `0x43cee7`：每 obj_HitPoint tick 一步，层级 16 降 obj_Score 级再升回（[地图物件闪烁](../../static_reverse/original_map_object_flash.md)） | 已按 16 ms/tick 走 |
| 31 | [StoryEffectObjects](../../../../game/battle/runtime/StoryEffectObjects.gd) | `TICK_SECONDS 0.025`（40 Hz）、`DEFAULT_FRAME_TICKS 3` | A | 雨滴 16.16 速度、`obj_Data7` tick、`shape_delay` 都是每 tick 一次 | **`TICK_SECONDS → 0.016`** |
| 32 | [OpeningCinematics](../../../../game/battle/runtime/opening/OpeningCinematics.gd) | 标题 `0.2 s` 入／`0.3 s` 出、`DARK_SCREEN_TICKS_PER_LEVEL 3`×16 级、镜头速度单位 | C／B | 标题淡入出无原版对应；`actDarkScreen` 对象 700 过程 `0x43e2d0` 每 3 tick 一级、16 级（[tick 计数 §5](../../static_reverse/original_tick_counts.md)）；镜头同 27 | 标题 C；暗屏与镜头 B |
| 33 | [OpeningSelectPrompt](../../../../game/battle/runtime/opening/OpeningSelectPrompt.gd) | 提示节拍（`SELECT_CHOICE_GAP 6.0` 为像素间距） | C | 选择窗等待输入，无时钟 | — |
| 34 | [OpeningStoryObjects](../../../../game/battle/runtime/opening/OpeningStoryObjects.gd) | 行走 `walk_pixels_per_second 160`、揭示 `default_step_seconds 0.04`、`actMoveDispWait` speed 走行走表 | A／B | 同 28 | 揭示 `0.016`；`×62.5`；行走 B（若 4 px/tick → 250 px/s） |
| 35 | [TownRuntime](../../../../game/world/TownRuntime.gd) | 菜单节拍（`teDelay` 已执行，见处置表第 35 行） | A | `teDelay [ticks]` 6–100（[town_event_semantics](../../static_reverse/town_event_semantics.md)） | `teDelay(n) = n × 0.016 s`（0.10–1.6 s） |
| 36 | [WorldMapRuntime](../../../../game/world/WorldMapRuntime.gd) | `travel_pixels_per_second 96`、`EDGE_SCROLL_PIXELS_PER_SECOND 240`、`track_reveal_seconds 0.6` | A／B／C | 大地图行者 16.16 速度 2／tick（[world_map_data](../../static_reverse/world_map_data.md) SR-069） | 行者 **125 px/s**（2 px × 62.5）；边缘滚动同 27（B）；轨迹揭示 C |
统计：A（含混合）21 格，B 12 格，C 15 格（一格可含多类，按常数计）。纯 C 且无任何 A／B 成分的格：2、7、8、14、23、33（6 格）——这些的「改不改」只是产品选择，与 tick 测量无关。

### 处置

`OriginalTick.gd`：`TICK_SECONDS = 0.016`、`TICKS_PER_SECOND = 62.5`、`seconds(n)`／`ticks(s)`／`ticks_from_host_seconds(s)`（÷0.0194）。所有 A 类经它表达；B 类读出的计数写在 [original_tick_counts.md](../../static_reverse/original_tick_counts.md)；未读的保留现值标 provisional 并写函数；C 类删或如实标 remake-invented。PROVENANCE timing 列 remake-invented：36（删五个魔法模块后 33）→ **10**；其后 29 的 PLAYBACK_SPEED 取 1.0 原速、不再算 remake-invented，36 格内有意保留的由 9 格减为 8 格（见本节末）。

| # | 模块 | 处置 | 旧 → 新（n tick × 16 ms） |
| --- | --- | --- | --- |
| 1 | BattleAftermath | REWARD 换算（B 读出）；FADE 读出（死亡分支 0x43f0cd／0x4435e9，[阵亡演出](../../static_reverse/original_death_disposal.md)） | 奖励浮字 1.0 s → 46 tick = 0.736 s（第 32 tick 放行后 14 tick 淡出）；死亡 0.45 s 淡出 → 16 tick 纵向拉伸＋淡出 |
| 2 | BattleAttackCue | **换算**（static-derived）：玩家确认的普攻与施法都不播；AI 起手按原版 tick——普攻射程 6、滑动、目标 12，施法射程 24（12 是离开时的重置值）、滑动、目标 24；滑动逐 tick 移植 `0x45e882`（步长 clamp(距离>>3, 2, 16)），见[施法覆盖层「起手节拍」](../../static_reverse/original_cast_overlays.md#起手节拍) | 0.24＋0.22＋0.24 s → 普攻 (6＋N＋12)、施法 (24＋N＋24) tick，N＝滑动 tick（一格 15、两格 20、三格 24、十二格 42） |
| 3 | BattleCombatCutin | fps 经 tick；PLAYBACK_SPEED 取 **1.0 原速**，0.4 只剩开发开关 `HSL_CUTIN_PLAYBACK_SPEED`；绝技切入的施法引导改按该角色 ANIMAL `s_action` 程序逐 call 播放（`AnimalCastLead`：aniShadowBG 1＋8 call、aniMoveToCenter 与施法对象滑入按 `0x45e80d(16,32)`、局部图每张 delay1、肖像每张 delay2＋末张 20、过渡 16＋停留 10＋1 call、法术尾段 31 call（级 16→1）与中心光球——见 [original_cast_overlays](../../static_reverse/original_cast_overlays.md) §施法引导的合成，[ANIMAL 程序包 §8](../../static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释)） | ANIMAL 更新 60 → 62.5 次/s（manifest 删 presentation_fps）；攻方程序 60 tick = 0.96 s（原速）；雷歐納德 氣刃斬 引导 139 tick = 2.22 s，再接 60 tick 攻方脚本 |
| 4 | BattleCommandMenu | 换算 | 悬停／展开 60 → 62.5 次/s（D=6 → 7 tick/帧 = 112 ms） |
| 5 | BattleDepartureView | 换算 | 0.24 s → 16 tick = 0.256 s |
| 6 | BattleDialogue | timing 改 provisional（分页属 layout）；按 `0x414280` 读出的 tick 计数换算（见上表第 6 行） | 溶解 0.29／0.32 s → 16 tick＝0.256 s；逐行 0.1 s → 3 px/tick 擦出 |
| 7 | BattleExtraActionCue | **有意保留**；消融：置 0 只挂自身一条断言「readable second-action transition」，流程不需要，可删 | 0.55 s 不变 |
| 8 | BattleNavigationCue | **有意保留** | 0.55 s 不变 |
| 9 | BattlePresentation | 换算（B 读出）；trail／受击色 0.18 s 已删，地图受击改由 `MapHitState` 照 `0x407230` 放 60 tick hit 帧与左右抖动（static-derived）；落空音时刻 provisional | 伤害数字 0.9 s 上浮＋0.3 s 淡 → 10 tick/位＋34（2 位 54 tick = 0.864 s）；回复／MISS／状态字 0.7 s → 46 tick；上浮 26 px/s → 0.5 px/tick = 31 px/s |
| 10 | BattleScriptActorPresentation | 换算 | 揭示步 0.04 s → 1 tick = 0.016 s |
| 11 | BattleScriptCoordinator | 随 28 | 同 28 |
| 12 | ~~FirstBattleStoryStage~~ | **已删除**：第一战信使改为 WINFAIL051 event 3 的脚本对象 10000，由 `BattleOpeningCoordinator` 按 8 号（`actWalkDispWait`／`actWalkAndDeleteWait` speed 表 px/tick）走位 | 不再有独立时序常数 |
| 13 | BattleSystemMenu | 卷轴照 0x45e882／0x45e91e 逐 tick 步进（战斗 35／11 tick，大地图 40／16 tick）；HINT **有意保留** | 卷轴已改；1.6 s 不变 |
| 14 | BattleTreasurePresentation | **有意保留**（原版直接处置，重制字幕需要可读节拍） | 0.45 s 不变 |
| 15 | BattleTurnEndCue | 换算 | 事件间隔 0.7 s → 40 tick = 0.64 s；末事件停留 46 tick = 0.736 s；上浮 16 px/事件 → 0.5 px/tick |
| 16 | BattlePlayLoop | 常数实际在 BattleSceneRuntime；PlayLoop timing 改 n/a | 行走一格 0.20 s → 8 tick = 0.128 s（`ActorRuntime.WALK_CELL_SECONDS`） |
| 17 | BattleSceneRuntime | **手写开场已删除**：章节标题、自动推进 0.04／0.06／0.14 s 随 `opening_*` 一并删除（第一战标题与步进走 `OpeningCinematics`／协调器的标题子状态机／1 tick）；剩 `AI_PLAYBACK_STEP_SECONDS 0.35`／结果音乐淡出 1.2 s，无 tick 依据，有意保留（C） |
| 18 | MagicImpactPresentation | 数字换算（B 读出）；VITALS 条 **有意保留** | 数字 0.75 s → 伤害 10 tick/位＋34、MISS 46 tick；条 0.45 s 不变 |
| 19 | MoonDancePresentation | 换算；INTRO provisional（002 的 s_action 引导程序已读——同 `AnimalCastLead` 的四 opcode——但 002 的 s_shape 条未导入 combat manifest，模块仍用自己的三帧施放画） | 100 tick/s（×0.4 = 40 真实 tick/s）→ 62.5 真实 tick/s：每目标 180 tick 4.5 s → 2.88 s；风声 0.2 s → 20 tick |
| 20／22／23／24／25 | （已删） | 归 3／SkillEffectScriptPlayer | 60 → 62.5 tick/s；有 `m_shape` 条的施法者按 m_action 引导逐 call 播，无条带者照原版无引导路径 8 call 压暗、第 9 call 姿势（[original_cast_overlays](../../static_reverse/original_cast_overlays.md) §无条带起手序列） |
| 21 | PoisonArrowPresentation | 换算；删 LEAD | LEAD 0.65 s 删；攻方 0.8 s → 80 tick（面板全程可见）；命中 0.32 s → 32 tick；结果 0.92 s → 92 tick；帧 0.04 s → 5 tick |
| 26 | ActorRuntime | 换算 | 待机 8 fps → 62.5/11 = 5.68 fps；行走帧 30 fps → 每 3 tick = 20.8 fps；覆盖帧率 8 → 待机节奏（provisional）；manifest `fps: 8` 字段不再读 |
| 27 | BattleCameraController | 换算（B 读出 §3） | 240 px/s → 12 px/tick = 750 px/s |
| 28 | BattleOpeningCoordinator | 换算；删 min_walk／walk_margin／camera_scroll（消融通过：运动闸门与 tick 模拟覆盖） | actDelay 0.025 → 0.016 s；非等待 token 0.04 → 0.016 s；行走 160 px/s → 0x4543d8 表 1／2／2／4／8 px/tick（默认 250 px/s）；镜头 0.6 s → 0x45e80d 逐 tick 模拟（剧情步进 16 px，320 px ≈ 21 tick）；标题 1.4 s → **159＋320（任意键／点击可跳）＋103 = 582 tick**（按 `0x452f32` 汇编，层级段各 51 tick） |
| 29 | CombatPresentationTiming | fps 经 tick；受击三段改 tick 表达（runtime-reference＋provisional）；PLAYBACK_SPEED 迁入，取 **1.0**，环境变量开关唯一读取点在此；守方 AnimalDefense `0x4038a0` 读出（[tick 计数包 §6](../../static_reverse/original_tick_counts.md#6-普攻切入的守方对象-defprocanimaldefense0x4038a0slot-23受击停留)），TARGET_PAUSE／hurt_hold 落 A；屏幕过渡 `0x46098f(1)`／`0x4609c0(1)` 读出（tick 计数包 §6「同 tick 先后」），RECOVERY／CLOSING_LIGHTEN 落 A | TARGET_PAUSE 0.12／HURT 0.60／RECOVERY 0.16（源钟）→ 15／77／20 tick（77 = 录像 1.5 s ÷ 19.4 ms）→ **中立 32 tick（0.512 s）；命中停留 68 ＋ 10×伤害位数 tick（1 位 78 = 1.248 s）、落空 56 tick（0.896 s）；变暗 16 ＋ 变亮 16 tick、之间无停留** |
| 30 | MapObjectFlash | 换算（static-derived：`0x43cee7` 每 obj_HitPoint tick 一步、层级 16 降 obj_Score 级再升回，[地图物件闪烁](../../static_reverse/original_map_object_flash.md)） | 0.55 s／0.22 → 逐 tick 计数器 |
| 31 | StoryEffectObjects | 换算 | 0.025 → 0.016 s；闪光寿命 obj_Data7×2 且 ≥0.2 s → obj_Data7 tick（≥3）；雨滴帧 0.05 s → 3 tick |
| 32 | OpeningCinematics | 换算（标题斜坡、镜头）；暗屏 provisional（对象 700） | 标题 0.2／0.3 s → 逐 tick 走 `0x452f32` 子状态机（横幅减色＋纵向缩放、章节名交叉淡化，层级段 51 tick）；镜头速度单位 60 → 62.5 Hz；暗屏 0.8 s 不变 |
| 33 | OpeningSelectPrompt | timing 改 n/a（无时钟） | — |
| 34 | OpeningStoryObjects | 随 28 | 揭示 0.04 → 0.016 s；行走同 28 |
| 35 | TownRuntime | 换算（static-derived：`0x454e20` case 0xe 存 N 到 `0x4c1d54`，链停 N＋1 tick 不出板；teMenuMoveOut 20 tick） | teDelay(n) → (n＋1) × 0.016 s，经 `OriginalTick` 执行 |
| 36 | WorldMapRuntime | 换算；轨迹揭示照 `0x4280d0` | 行者 96 → 125 px/s；边缘滚动 240 → 750 px/s；揭示 0.6 s → 每 tick 裁剪半径 +1（`track_reveal_tick_seconds` = 1 tick） |
| 邻 | GameOverScreen | 换算 | 淡入 0.9 s → 60 tick = 0.96 s |
| 邻 | MapObjectAnimation | 换算 | 60 → 62.5 更新/s（fire_animation manifest 删 presentation_tick_hz） |

剩余 remake-invented timing：有意保留 2、3、7、8、13、14、17、18；12 随 FirstBattleStoryStage 删除；3／29 的 PLAYBACK_SPEED 取 1.0 原速，29 的 timing 列不再有 remake-invented 项，3 因合成 clip 专用的借用 氣刃斬 演出保留该标签。

相邻的 provisional 时序格（不在 36 格内，但同一换算）：[SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) `TICKS_PER_SECOND 60 → 62.5`；[GameOverScreen](../../../../game/title/GameOverScreen.gd) 60 tick 保持 = **0.96 s**；[GameClearScreen](../../../../game/title/GameClearScreen.gd) `actDelay 0.025 → 0.016`；[MapObjectAnimation](../../../../game/battle/runtime/MapObjectAnimation.gd) 60 更新/s → 62.5（火焰 4 tick／帧 = 15.6 显示帧/s）；[CommandPresentationRules](../../../../game/battle/runtime/CommandPresentationRules.gd)「每秒调用率未测」→ 62.5 次/s。

## 重制接线

- `game/common/OriginalTick.gd` 是唯一 tick 常数；表中各行点名的模块经它换算，provenance 头 timing 维度写 `docs/evidence_packets/runtime_observations/original_tick_rate/README.md` 或 `static_reverse/original_tick_counts.md`。
- B 类行的替换点就是「原版依据」列点名的函数／字段；读出后改该模块常数并把本行改为 A。

## 复现

`python3 tools/hsl.py check provenance`（timing 列 remake-invented／provisional 计数）；tick 周期本身见 [README](README.md) 的复现块。

## 边界

- 按 16 ms 给出的「应为」是设计时长；本机录像量得的秒数须先按 19.4 ms/tick 折回 tick。
- B 类行只证明原版以 tick 计，不证明现值与原版等价。
- 表中基线是 PROVENANCE 计数表的 36 格；之后删掉的模块保留删除线行，便于对照。

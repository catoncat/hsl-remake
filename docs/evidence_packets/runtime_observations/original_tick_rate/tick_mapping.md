# 36 格 remake-invented 时序 → 原版 tick 的映射表

> evidence: runtime-measured: tick period and walk／idle cadence; static-derived: native tick counts cited per row and in original_tick_counts.md; resource-derived: object shape_delay and teDelay fields; provisional: rows marked B · status: live · tools: hsl_win32_memread.c · updated: 2026-09-23

输入：[docs/PROVENANCE.md](../../../PROVENANCE.md) 计数表中 timing＝`remake-invented` 的 36 格（2026-09-22 基线 `d3b3fdf8`）。tick 率来自 [README](README.md)：**设计 16 ms/tick（62.5 tick/s）**；本机 Wine 实测 19.4 ms/tick。「应为」一栏按 16 ms 给出；如负责人决定按用户实际体验（19.4 ms）对标，把秒数乘 1.2125。

分类：

- **A 可直接换算**：原版计数已知（static／resource），乘 16 ms 即得。
- **B 以 tick 计但计数未读**：原版确以主循环 tick 为单位，但具体计数还没人读；给出要读的函数／字段，读到就落入 A。
- **C 与 tick 无关**：原版没有对应演出（重制自创的过渡、淡入淡出、提示节拍），tick 率量出来也换不了；保留为用户允许的重制改善，或删掉。

| # | 模块 | 常数／现值 | 类 | 原版依据 | 按 16 ms/tick 应为 |
| --- | --- | --- | --- | --- | --- |
| 1 | [BattleAftermath](../../../../game/battle/scene/BattleAftermath.gd) | `FADE_SECONDS 0.45`、`REWARD_SECONDS 1.0` | B／C | EXP／KILL／$ 浮字是 `obj_ShowNumber` kind 1／4（`0x4084e0`→`0x408580`），寿命计数在 `0x408580` 内未读；页面淡入本身无原版对应 | 读 `0x408580` 的存活 tick → ×16 ms 定 `REWARD_SECONDS`；`FADE` 为 C |
| 2 | [BattleAttackCue](../../../../game/battle/scene/BattleAttackCue.gd) | `0.24＋0.22＋0.24 s` 引导 | C → A（P6） | 基线时未定位；P5／P6 读出 AI 起手状态（[施法覆盖层「起手节拍」](../../static_reverse/original_cast_overlays.md#起手节拍)）：普攻 6＋滑动＋12 tick，施法 24＋滑动＋24 tick，滑动 `0x45e882` 按距离；玩家确认无起手 | 普攻一格 (6＋15＋12)×16 ms＝0.528 s；施法一格 (24＋15＋24)×16 ms＝1.008 s |
| 3 | [BattleCombatCutin](../../../../game/battle/scene/BattleCombatCutin.gd) | manifest `presentation_fps 60`（ANIMAL `complete_updates／fps`）、`PLAYBACK_SPEED 0.4`、`SPELL_TICKS_PER_SECOND 100` | A | ANIMAL 程序每 tick 推进一条／一 delay；魔法脚本 Wait 单位是 tick | `presentation_fps → 62.5`；`SPELL_TICKS_PER_SECOND → 62.5`；`PLAYBACK_SPEED 0.4` 是重制倍率（C，若要原速取 1.0） |
| 4 | [BattleCommandMenu](../../../../game/battle/scene/BattleCommandMenu.gd) | `HOVER_UPDATES_PER_SECOND 60` | A | 悬停换帧与展开步进都是每 tick 一次调用（`0x45e5a6`／`0x45e80d`，[native_presentation_helpers](../../static_reverse/native_presentation_helpers.md)） | `62.5`（D=6 → 7 tick／帧 = 112 ms） |
| 5 | [BattleDepartureView](../../../../game/battle/scene/BattleDepartureView.gd) | `FADE_SECONDS 0.24` | A | 离场阶段 0x35／0x36 计 16 tick（`0x454286`／`0x4542a7`） | **0.256 s**（原版是 16 tick 后直接注销，无淡出；淡出形式本身是 C） |
| 6 | [BattleDialogue](../../../../game/battle/scene/BattleDialogue.gd) | 四行窗口、字体、行距；淡入淡出、擦出、上卷 | A | 对白框过程 `0x414280` 已读（[对白框包](../../static_reverse/original_dialogue_board.md)）：淡入淡出 16 tick、擦出 3 px/tick（17→112 px）、上卷 3 px/tick（10 tick／行）；原版没有逐字显示 | 淡入淡出 **0.256 s**；满窗擦出 32 tick＝0.512 s；上卷 0.16 s／行 |
| 7 | [BattleExtraActionCue](../../../../game/battle/scene/BattleExtraActionCue.gd) | `DURATION 0.55` | C | 原版无「再次行動」提示 | — |
| 8 | [BattleNavigationCue](../../../../game/battle/scene/BattleNavigationCue.gd) | `WAIT_SECONDS 0.55` | C | 原版无待機／守候提示节拍 | — |
| 9 | [BattlePresentation](../../../../game/battle/scene/BattlePresentation.gd) | 伤害浮字 `0.7 s` 上浮（已改）、结果页 `0.3 s` 淡出＋`0.6 s` 延迟 | A／C | 地图伤害／回复数字是 `defProcShowNumber`（kind 0 弹跳、kind 2／3）：kind 0 为 10×位数＋34 tick，kind 2／3 为 hold＋46 tick（[tick 计数 §1](../../static_reverse/original_tick_counts.md)）；结果页淡出为 C | lane DIGITS（2026-09-26）已按此落地（`ResultNumberFloater`） |
| 10 | [BattleScriptActorPresentation](../../../../game/battle/scene/BattleScriptActorPresentation.gd) | 揭示 `coordinator.default_step_seconds 0.04` | A | 原 STORY VM（`0x450840`）连续执行非等待 token，到等待类 opcode 才让出（[original_script_wait](../../static_reverse/original_script_wait.md)、[original_auto_growth](../../static_reverse/original_auto_growth.md) 的 opcode56 序列） | `0`（同 tick）；重制若要可见节拍取 1 tick = `0.016 s` |
| 11 | [BattleScriptCoordinator](../../../../game/battle/scene/BattleScriptCoordinator.gd) | 继承开场协调器（行 28） | A | 同 28 | 同 28 |
| 12 | ~~FirstBattleStoryStage~~（S5 删除，信使走 [BattleOpeningCoordinator](../../../../game/battle/runtime/BattleOpeningCoordinator.gd) 的脚本走位） | 信使斜走 `0.5 s`／段；离场沿 `MOVE_CELL_PRESENTATION_SECONDS` | A／B | 玩家行走实测 4 px/tick（32 px = 8 tick）；脚本 `actWalk*` 的 speed 参数已读（[剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)，`0x453b90` 状态 0x32 sub 2）：1→1、2／3→2、0／4→4、8→8 px/tick，每格 32/步长 tick | 玩家格 `0.128 s`；信使若同速 45 px ≈ 11 tick = `0.18 s`；确认 speed 参数后落 A |
| 13 | [BattleSystemMenu](../../../../game/battle/scene/BattleSystemMenu.gd) | `SCROLL_SECONDS 0.25`、`HINT_SECONDS 1.6` | B／C | 卷轴展开若沿用 `0x45e80d`（距离右移一位、步进 ≤8/tick）可算；提示 1.6 s 无原版对应 | 读系统卷轴对象过程的展开路径；`HINT` 为 C |
| 14 | [BattleTreasurePresentation](../../../../game/battle/scene/BattleTreasurePresentation.gd) | `DURATION 0.45` 淡出 | C | 原版宝箱领取后直接处置，无淡出（[original_treasure](../../static_reverse/original_treasure.md)） | — |
| 15 | [BattleTurnEndCue](../../../../game/battle/scene/BattleTurnEndCue.gd) | `EVENT_SECONDS 0.7`／事件 | A（间隔）／B（寿命） | HP 数字后 MP 数字延迟 **40 tick**（[original_resource_recovery](../../static_reverse/original_resource_recovery.md)）；数字寿命见 9 | 事件间隔 **0.64 s**；数字停留读 `0x408580` |
| 16 | [BattlePlayLoop](../../../../game/sim/loop/BattlePlayLoop.gd) | `MOVE_CELL_PRESENTATION_SECONDS 0.20`／格 | A | 实测 4 px/tick → 32 px = 8 tick | **0.128 s**／格（本机体验 0.155 s） |
| 17 | [BattleSceneRuntime](../../../../game/battle/scene/BattleSceneRuntime.gd) | 章节标题 `1.4 s`、结果音乐淡出 `1.2 s`、自动推进 `0.04／0.06／0.14 s`、`AI_PLAYBACK_STEP_SECONDS 0.35` | C／A | 标题淡入淡出与音乐淡出无原版对应，原章节标题停留未读；自动推进 token 步同行 10 | 自动推进 `0.016 s`／token；其余 C |
| 18 | [MagicImpactPresentation](../../../../game/battle/scene/MagicImpactPresentation.gd) | `VITALS_SECONDS 0.45`、`FLOAT_SECONDS 0.75`（已改） | A／C | 数字为 `defProcShowNumber`：红字 kind 0 为 10×位数＋34 tick，MISS kind 5 为 46 tick；HP 条动画无原版对应 | lane DIGITS（2026-09-26）已按此落地；`VITALS` 为 C |
| 19 | [MoonDancePresentation](../../../../game/battle/scene/MoonDancePresentation.gd) | `TICKS_PER_SECOND 100` × `PLAYBACK_SPEED 0.4` | A | moon_dance.json 的 delay 比值是 tick | `62.5` tick/s（×0.4 倍率是 C；原速取 1.0） |
| 20 | ~~ParalysisMagicPresentation~~（S6c 已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `tick = (t − CAST_LEAD_IN) × 100` | A | 源对象 `shape_delay` 以 tick 计 | `× 62.5` |
| 21 | [PoisonArrowPresentation](../../../../game/battle/scene/PoisonArrowPresentation.gd) | 100 Hz 时钟、`LEAD 0.65` | A／C | manifest 源 tick 顺序；`LEAD` 为重制引导 | `62.5` Hz；`LEAD` C |
| 22 | ~~StatMagicPresentation~~（S6c 已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | impact／complete `tick / 100`、`tick = (t − lead) × 100` | A | 源 Wait 单位 tick | `/ 62.5`、`× 62.5` |
| 23 | ~~StatusMagicPresentation~~（S6c 已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `0.55 s` 扩散、`0.18／0.4 s` 淡入出 | C | 这些法术没有导入源特效对象（provenance 已注明） | — |
| 24 | ~~SupportMagicPresentation~~（S6c 已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | impact／complete `/ 100`、`tick = … × 100`、施法帧 `elapsed × 30` | A／C | 源 Wait 单位 tick；施法帧 30 fps 为重制 | `/ 62.5`、`× 62.5`；施法帧若按 ANIMAL delay 则同 3 |
| 25 | ~~WaterStrikePresentation~~（S6c 已删除；该法术现由 [SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) 按 EFFECTS 脚本播放，timing 归第 3 行） | `tick = (elapsed − lead) × 100` | A | 同上 | `× 62.5` |
| 26 | [ActorRuntime](../../../../game/battle/runtime/ActorRuntime.gd) | 移动 tween（来自 16）、`_override_fps 8`、待机 manifest `fps 8` | A | 实测待机 11 tick／帧、行走 3 tick／帧；脚本形状覆盖（绳降等）用对象自身 `shape_delay` | 待机 **5.68 fps**（62.5/11）、行走 **20.8 fps**（62.5/3）；覆盖帧率取 `62.5/(delay+1)`。注意 PROVENANCE 把待机 8 fps 记为 resource-derived，实为 manifest 的 provisional 值 |
| 27 | [BattleCameraController](../../../../game/battle/runtime/BattleCameraController.gd) | 平移 `240 px/s` | B | 原版边缘滚动请求 ±12（`0x43e4a0`）是否每 tick 施加一次未确认；剧情居中缓动的每 tick 步进已读（[剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)：`0x43bf30` 逐轴 `min(step, 剩余/2)`，step 16／32／+12） | 若每 tick ±12 px → **750 px/s**；先读 `0x46bede` 滚动消费 |
| 28 | [BattleOpeningCoordinator](../../../../game/battle/runtime/BattleOpeningCoordinator.gd) | `delay_token_seconds 0.025`、`default_step_seconds 0.04`、`walk_pixels_per_second 160`、`min_walk_seconds 0.35`、`walk_margin_seconds 0.14`、`camera_scroll_seconds 0.6`、`title_seconds 1.4`、`move_pixels_per_frame_hz 60` | A／B／C | `actDelay(n)` = n tick；`actMoveDispWait` speed 读作 px/帧，帧 = tick；行走 speed 参数与镜头每 tick 步进已读（[剧情镜头读法](../../static_reverse/original_script_camera_scroll.md)：speed→1／2／4／8 px/tick；居中缓动逐轴 `min(step, 剩余/2)`，剧情位 step 16，tol 4）；章节标题停留由脚本 actDelay 给出 | `delay_token → 0.016`；`default_step → 0.016`；`move_pixels_per_frame_hz → 62.5`；行走若同玩家 4 px/tick → **250 px/s**（B）；`min_walk`／`margin`／`title 1.4` 为 C；镜头 B |
| 29 | [CombatPresentationTiming](../../../../game/battle/runtime/CombatPresentationTiming.gd) | `TARGET_PAUSE 0.12`、`HURT_HOLD 0.60`、`RECOVERY 0.16`、`CAST_LEAD_IN 0.44`（源钟单位 ×0.4）；`ordinary(actor, fps)` | A（fps）／B（受击） | 攻方时长 = ANIMAL `complete_updates` tick；受击停留在 ANIMAL 守方程序里（未按 tick 读出） | `fps → 62.5`；受击／恢复读守方程序的 aniDelay 和 → ×16 ms |
| 30 | [MapObjectFlash](../../../../game/battle/runtime/MapObjectFlash.gd) | `PERIOD_SECONDS 0.55`、`DEPTH 0.22` | B | `mapobjFlash` 的 `defProcStandObject` 分支未读 | 读该分支的每 tick 亮度步进 |
| 31 | [StoryEffectObjects](../../../../game/battle/runtime/StoryEffectObjects.gd) | `TICK_SECONDS 0.025`（40 Hz）、`DEFAULT_FRAME_TICKS 3` | A | 雨滴 16.16 速度、`obj_Data7` tick、`shape_delay` 都是每 tick 一次 | **`TICK_SECONDS → 0.016`** |
| 32 | [OpeningCinematics](../../../../game/battle/runtime/opening/OpeningCinematics.gd) | 标题 `0.2 s` 入／`0.3 s` 出、`DARK_SCREEN_FADE_SECONDS 0.8`、镜头速度单位 | C／B | 标题淡入出无原版对应；`actDarkScreen` 原版是否逐 tick 渐暗未读；镜头同 27 | 标题 C；暗屏与镜头 B |
| 33 | [OpeningSelectPrompt](../../../../game/battle/runtime/opening/OpeningSelectPrompt.gd) | 提示节拍（`SELECT_CHOICE_GAP 6.0` 为像素间距） | C | 选择窗等待输入，无时钟 | — |
| 34 | [OpeningStoryObjects](../../../../game/battle/runtime/opening/OpeningStoryObjects.gd) | 行走 `walk_pixels_per_second 160`、揭示 `default_step_seconds 0.04`、`actMoveDispWait` speed×60 Hz | A／B | 同 28 | 揭示 `0.016`；`×62.5`；行走 B（若 4 px/tick → 250 px/s） |
| 35 | [TownRuntime](../../../../game/world/TownRuntime.gd) | 菜单节拍（`teDelay` 只记录不执行） | A | `teDelay [ticks]` 6–100（[town_event_semantics](../../static_reverse/town_event_semantics.md)） | `teDelay(n) = n × 0.016 s`（0.10–1.6 s） |
| 36 | [WorldMapRuntime](../../../../game/world/WorldMapRuntime.gd) | `travel_pixels_per_second 96`、`EDGE_SCROLL_PIXELS_PER_SECOND 240`、`track_reveal_seconds 0.6` | A／B／C | 大地图行者 16.16 速度 2／tick（[world_map_data](../../static_reverse/world_map_data.md) SR-069） | 行者 **125 px/s**（2 px × 62.5）；边缘滚动同 27（B）；轨迹揭示 C |

统计：A（含混合）21 格，B 12 格，C 15 格（一格可含多类，按常数计）。纯 C 且无任何 A／B 成分的格：2、7、8、14、23、33（6 格）——这些的「改不改」只是产品选择，与本次测量无关。

## R26 处置（2026-09-23，lane R26-tick-timing）

唯一常数 [`game/common/OriginalTick.gd`](../../../../game/common/OriginalTick.gd)：`TICK_SECONDS = 0.016`、`TICKS_PER_SECOND = 62.5`、`seconds(n)`／`ticks(s)`／`ticks_from_host_seconds(s)`（÷0.0194）。所有 A 类经它表达；B 类读出的计数写在 [original_tick_counts.md](../../static_reverse/original_tick_counts.md)；未读的保留现值标 provisional 并写函数；C 类删或如实标 remake-invented。PROVENANCE timing 列 remake-invented：基线 36（S6c 删五个魔法模块后 33）→ **10**。

| # | 模块 | 处置 | 旧 → 新（n tick × 16 ms） |
| --- | --- | --- | --- |
| 1 | BattleAftermath | REWARD 换算（B 读出）；FADE 读出（R5-L2：死亡分支 0x43f0cd／0x4435e9，[阵亡演出](../../static_reverse/original_death_disposal.md)） | 奖励浮字 1.0 s → 46 tick = 0.736 s（第 32 tick 放行后 14 tick 淡出）；死亡 0.45 s 淡出 → 16 tick 纵向拉伸＋淡出 |
| 2 | BattleAttackCue | ~~有意保留~~ → **P6 换算**（static-derived）：玩家确认的普攻与施法都不播（P5 施法、P6 普攻）；AI 起手按原版 tick——普攻射程 6、滑动、目标 12，施法射程 24（P5 读的 12 是离开时的重置值）、滑动、目标 24；滑动逐 tick 移植 `0x45e882`（步长 clamp(距离>>3, 2, 16)），见[施法覆盖层「起手节拍」](../../static_reverse/original_cast_overlays.md#起手节拍) | 0.24＋0.22＋0.24 s → 普攻 (6＋N＋12)、施法 (24＋N＋24) tick，N＝滑动 tick（一格 15、两格 20、三格 24、十二格 42） |
| 3 | BattleCombatCutin | fps 经 tick；PLAYBACK_SPEED 0.4 有意保留（负责人决定项）→ **P1 已决：1.0 原速**，0.4 只剩开发开关 `HSL_CUTIN_PLAYBACK_SPEED`；**R30**：绝技切入的施法引导改按该角色 ANIMAL `s_action` 程序逐 call 播放（`AnimalCastLead`：aniShadowBG 1＋8 call、aniMoveToCenter 与施法对象滑入按 `0x45e80d(16,32)`、局部图每张 delay1、肖像每张 delay2＋末张 20、过渡 16＋停留 10——尾段 provisional，[ANIMAL 程序包 §8](../../static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释)） | ANIMAL 更新 60 → 62.5 次/s（manifest 删 presentation_fps）；攻方程序 60 tick = 0.96 s（原速）；雷歐納德 氣刃斬 引导 139 tick = 2.22 s，再接 60 tick 攻方脚本 |
| 4 | BattleCommandMenu | 换算 | 悬停／展开 60 → 62.5 次/s（D=6 → 7 tick/帧 = 112 ms） |
| 5 | BattleDepartureView | 换算 | 0.24 s → 16 tick = 0.256 s |
| 6 | BattleDialogue | timing 改 provisional（分页属 layout）；R7-DLG 起按 `0x414280` 读出的 tick 计数换算（见上表第 6 行） | 溶解 0.29／0.32 s → 16 tick＝0.256 s；逐行 0.1 s → 3 px/tick 擦出 |
| 7 | BattleExtraActionCue | **有意保留**；消融：置 0 只挂自身一条断言「readable second-action transition」，流程不需要——建议负责人决定删除 | 0.55 s 不变 |
| 8 | BattleNavigationCue | **有意保留** | 0.55 s 不变 |
| 9 | BattlePresentation | 换算（B 读出）；trail／受击色 0.18 s 与落空音 0.12 s provisional | 伤害数字 0.9 s 上浮＋0.3 s 淡 → 10 tick/位＋34（2 位 54 tick = 0.864 s）；回复／MISS／状态字 0.7 s → 46 tick；上浮 26 px/s → 0.5 px/tick = 31 px/s |
| 10 | BattleScriptActorPresentation | 换算 | 揭示步 0.04 s → 1 tick = 0.016 s |
| 11 | BattleScriptCoordinator | 随 28 | 同 28 |
| 12 | ~~FirstBattleStoryStage~~ | **S5 删除**：第一战信使改为 WINFAIL051 event 3 的脚本对象 10000，由 `BattleOpeningCoordinator` 按 8 号（`actWalkDispWait`／`actWalkAndDeleteWait` speed 表 px/tick）走位 | 不再有独立时序常数 |
| 13 | BattleSystemMenu | SCROLL provisional（0x45e80d 消费者未读）；HINT **有意保留** | 0.25 s／1.6 s 不变 |
| 14 | BattleTreasurePresentation | **有意保留**（原版直接处置，重制字幕需要可读节拍） | 0.45 s 不变 |
| 15 | BattleTurnEndCue | 换算 | 事件间隔 0.7 s → 40 tick = 0.64 s；末事件停留 46 tick = 0.736 s；上浮 16 px/事件 → 0.5 px/tick |
| 16 | BattlePlayLoop | 常数实际在 BattleSceneRuntime；PlayLoop timing 改 n/a | 行走一格 0.20 s → 8 tick = 0.128 s（`ActorRuntime.WALK_CELL_SECONDS`） |
| 17 | BattleSceneRuntime | **S5 删除手写开场**：章节标题、自动推进 0.04／0.06／0.14 s 随 `opening_*` 一并删除（第一战标题与步进走 `OpeningCinematics`／协调器的标题子状态机／1 tick）；剩 `AI_PLAYBACK_STEP_SECONDS 0.35`／结果音乐淡出 1.2 s，无 tick 依据，有意保留（C） |
| 18 | MagicImpactPresentation | 数字换算（B 读出）；VITALS 条 **有意保留** | 数字 0.75 s → 伤害 10 tick/位＋34、MISS 46 tick；条 0.45 s 不变 |
| 19 | MoonDancePresentation | 换算；INTRO provisional（002 的 s_action 引导程序已读——同 R30 `AnimalCastLead` 的四 opcode——但 002 的 s_shape 条未导入 combat manifest，模块仍用自己的三帧施放画） | 100 tick/s（×0.4 = 40 真实 tick/s）→ 62.5 真实 tick/s：每目标 180 tick 4.5 s → 2.88 s；风声 0.2 s → 20 tick |
| 20／22／23／24／25 | （S6c 已删） | 归 3／SkillEffectScriptPlayer | 60 → 62.5 tick/s；CAST_LEAD_IN provisional（m_action 引导：程序已读同 s_action，`m_shape` 条未导入——R30 遗留决定项） |
| 21 | PoisonArrowPresentation | 换算；删 LEAD | LEAD 0.65 s 删；攻方 0.8 s → 80 tick（面板全程可见）；命中 0.32 s → 32 tick；结果 0.92 s → 92 tick；帧 0.04 s → 5 tick |
| 26 | ActorRuntime | 换算 | 待机 8 fps → 62.5/11 = 5.68 fps；行走帧 30 fps → 每 3 tick = 20.8 fps；覆盖帧率 8 → 待机节奏（provisional）；manifest `fps: 8` 字段不再读 |
| 27 | BattleCameraController | 换算（B 读出 §3） | 240 px/s → 12 px/tick = 750 px/s |
| 28 | BattleOpeningCoordinator | 换算；删 min_walk／walk_margin／camera_scroll（消融通过：运动闸门与 tick 模拟覆盖） | actDelay 0.025 → 0.016 s；非等待 token 0.04 → 0.016 s；行走 160 px/s → 0x4543d8 表 1／2／2／4／8 px/tick（默认 250 px/s，R25 读出）；镜头 0.6 s → 0x45e80d 逐 tick 模拟（剧情步进 16 px，320 px ≈ 21 tick）；标题 1.4 s → **159＋320（任意键／点击可跳）＋103 = 582 tick**（R7-TITLE 按 `0x452f32` 汇编更正，层级段各 51 tick） |
| 29 | CombatPresentationTiming | fps 经 tick；受击三段改 tick 表达（runtime-reference＋provisional）；PLAYBACK_SPEED 迁入并有意保留 → **P1 已决：1.0**，环境变量开关唯一读取点在此；**P3**：守方 AnimalDefense `0x4038a0` 读出（[tick 计数包 §6](../../static_reverse/original_tick_counts.md#6-普攻切入的守方对象-defprocanimaldefense0x4038a0slot-23受击停留lane-p3)），TARGET_PAUSE／hurt_hold 落 A，RECOVERY 仍 B（屏幕过渡 `0x46098f` 未读） | TARGET_PAUSE 0.12／HURT 0.60／RECOVERY 0.16（源钟）→ R26 15／77／20 tick（77 = 录像 1.5 s ÷ 19.4 ms）→ **P3：中立 32 tick（0.512 s）；命中停留 68 ＋ 10×伤害位数 tick（1 位 78 = 1.248 s）、落空 56 tick（0.896 s）；RECOVERY 20 保留** |
| 30 | MapObjectFlash | provisional（TYPE.H objsScore/objsHitPoint 字段未导出） | 0.55 s／0.22 不变 |
| 31 | StoryEffectObjects | 换算 | 0.025 → 0.016 s；闪光寿命 obj_Data7×2 且 ≥0.2 s → obj_Data7 tick（≥3）；雨滴帧 0.05 s → 3 tick |
| 32 | OpeningCinematics | 换算（标题斜坡、镜头）；暗屏 provisional（对象 700） | 标题 0.2／0.3 s → R7-TITLE 起逐 tick 走 `0x452f32` 子状态机（横幅减色＋纵向缩放、章节名交叉淡化，层级段 51 tick）；镜头速度单位 60 → 62.5 Hz；暗屏 0.8 s 不变 |
| 33 | OpeningSelectPrompt | timing 改 n/a（无时钟） | — |
| 34 | OpeningStoryObjects | 随 28 | 揭示 0.04 → 0.016 s；行走同 28 |
| 35 | TownRuntime | provisional（teDelay 记录未执行） | teDelay(n) = n × 0.016 s 待接线 |
| 36 | WorldMapRuntime | 换算；轨迹揭示 provisional（0x4280d0） | 行者 96 → 125 px/s；边缘滚动 240 → 750 px/s；揭示 0.6 s 不变 |
| 邻 | GameOverScreen | 换算 | 淡入 0.9 s → 60 tick = 0.96 s |
| 邻 | MapObjectAnimation | 换算 | 60 → 62.5 更新/s（fire_animation manifest 删 presentation_tick_hz） |

剩余 remake-invented timing 9 格＝有意保留 9（2、3、7、8、13、14、17、18、29）；12 随 FirstBattleStoryStage 删除。lane P1（2026-09-24）把 3／29 的 PLAYBACK_SPEED 定为 1.0 原速：29 的 timing 列不再有 remake-invented 项（剩 8 格），3 仍因合成 clip 专用的借用 氣刃斬 演出保留该标签。

相邻的 provisional 时序格（不在 36 格内，但同一换算）：[SkillEffectScriptPlayer](../../../../game/battle/scene/SkillEffectScriptPlayer.gd) `TICKS_PER_SECOND 60 → 62.5`；[GameOverScreen](../../../../game/title/GameOverScreen.gd) 60 tick 保持 = **0.96 s**；[GameClearScreen](../../../../game/title/GameClearScreen.gd) `actDelay 0.025 → 0.016`；[MapObjectAnimation](../../../../game/battle/runtime/MapObjectAnimation.gd) 60 更新/s → 62.5（火焰 4 tick／帧 = 15.6 显示帧/s）；[CommandPresentationRules](../../../../game/battle/runtime/CommandPresentationRules.gd)「每秒调用率未测」→ 62.5 次/s。

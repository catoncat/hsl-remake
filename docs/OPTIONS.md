# 参数与选项系统

> 状态：**现行**。2026-09-26 起草（lane OPTIONS-DESIGN）；底座与八张选项卡已实现（OPTIONS-B1、S1–S4，见 §9），注册表在 `content/authored/options/remake_options.json`。§5、§9 保留当时的设计与实施记录。文中 `id` 指 [差异清单](evidence_packets/static_reverse/parity_gap_inventory.md) 的条目。

一句话：玩家可以在"照原版"和"少量讲得清的改良"之间选；门禁和裁判永远只看原版。

## 1. 目标与非目标

- **默认就是原版**：第一次启动、门禁、原版裁判、批量对照、自动对局都跑「原版」。
- **每个改良都讲得清**：原版这样／改良这样／为什么，各一句，并链到差异清单 id 或证据包。
- **一个选项＝一个玩家意图**（多看到一些信息、少等、少操作、看着舒服），不是一处代码差异一个开关。
- **续集作者能定默认值**：写在 campaign.json。

不做的：不是调试面板（种子、机器人、裁判导出、停格留在开发层）；不做平衡滑杆（伤害／经验／金钱倍率、敌人等级、AI 难度一律不做）；不让规则开关泛滥（规则类总数上限 3，首批最多 1 个）；不用选项掩盖没查清的原版——原版没读清的差异是缺口，先查清，不做成"原版／重制"二选一。

## 2. 三层、影响层、选项卡与准入

| 层 | 是什么 | 在哪里改 | 门禁 |
| --- | --- | --- | --- |
| ① 原版 | 每个选项的默认值，合起来就是全部照原版。原版自带的 設定選項（場景效果／音效音量／音樂音量／預備動作）也属于这一层，照旧放在原版窗里 | 预设「原版」 | 全部门禁、裁判、批量对照、自动对局只跑这一层 |
| ② 体验改良 | 从差异清单挑出的有意偏离 | 设置页；预设「舒适」一键全开，或逐项自定 | 只加一次「舒适全开」冒烟 |
| ③ 开发 | 种子、驾驭器、裁判导出、停格、调试 HUD | 只有环境变量、命令行、开发场景 | 不进设置文件，不改产品默认 |

**影响层**：规则＝改 BattlePlayLoop 算出的真相（公式、初值、AI、随机流、胜负、承接、经济），战役开始时锁定、写进存档摘要；演出＝改时序、交互流程、提示与信息公开，随时可改；外观＝只改画法（字体、光标、颜色），随时可改。判断方法：同一串玩家输入、同一个种子，开关两边的战斗结果会不会不同——会就是规则。给玩家原版没有的信息（宝箱位置、命中率）不算规则，但卡上标「信息」。

**选项卡字段**：编号（OPT-XXX，删了不复用）｜名称与一句说明（直接用作设置页说明）｜层级（体验改良／开发）｜影响层（规则／演出／外观，另可标「信息」）｜取值（原版值、舒适值；多档的列全）｜原版／改良／为什么（各一句）｜存档影响（无／进战役摘要）｜何时可改（随时／开始新故事时）｜读点（哪几个模块读这个键，删选项时一并删）｜证据（差异 id＋证据包或提交）｜工作量（S ≤ 半天、M 约一天、L 多天）。

**②体验改良的准入**（全部满足才做）：

1. 原版行为已经查清（至少这个行为本身已读实）。
2. 三句话讲得清，而且说得出谁会想要（用户实玩提过，或原版明显费事）。
3. 关掉时走的就是原版路径：选项只在原版路径上加一层，不许出现第二套规则，也不许"缺设置时悄悄换规则"（AGENTS 代码规则）。
4. 演出类不得改变随机数抽取的次数和顺序：跳过的演出照样做它该做的抽取。原版的出手延迟 rand(24)、遗言抽取以后接进全局流时同样适用（`rng-streams`）。
5. 规则类另加三条：用户点名要；只改初值、承接这类一次性输入，不碰公式、AI 和随机流结构；总数不超过 3。

不配做成选项的：原版缺陷的修正（直接作为永久偏离）、重制自有界面必需的文字、原版不可能出现的局面的兜底、平衡数值、开发工具。

## 3. 首批候选（9 张卡的摘要）

★＝进「舒适」预设。都不进存档、随时可改（原第 10 张 OPT-STAMINA 已移到 §4）。

| 编号 | 名称 | 原版 → 改良 | 为什么值得给玩家选 | 影响层 | 量 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| OPT-TREASURE ★ | 宝箱显示 | 原版很多宝箱不画（已测 1／2／3／6／19 关全部隐藏，28 关 21 只里 2 只隐藏），踩上先响发现音再领；可见箱踩上直接处理，不出字、不放声（0x445526 → 0x4156d0） → 全部画成闭箱，发现时出「發現寶藏」说明与通用确认音，停留时出悬停提示 | 不查攻略也能拿全宝物；领取规则（踩上即领、零随机、重开重置）两边完全相同 | 外观·信息 | S | `treasure-rules`、`treasure-caption`、[原宝箱](evidence_packets/static_reverse/original_treasure.md)；等 HIDDENCHEST 把原版做成默认 |
| OPT-INFO ★ | 战斗信息公开 | 原版选目标不显示命中率和击数；没交过手的敌人面板印 ???；飘字只有数字 → 头顶「命中 N%」「2擊」、敌人数值始终可见（状态页点谁都开、带永久加值行与悬停说明）、飘字带暴擊／擊倒／反擊／連擊和中毒／麻痺等说明、恢复没有原字形的说明字（特写结果行的净化／增益说明与未回復、武器附加效果行，地图的状态施加说明，道具的永久加成／解毒／增益／氣力行，回合末麻痺解除／增益結束，法术／辅助选目标的「N 個目標」；原版值一律不出）、学会新技能时受者头上飘学技提示（原版只在升级窗印學會魔法／學會特殊技）（法术命中先亮受者血条是原版行为，两个预设都保留，见 §9 S2） | 原版命中率全靠猜，敌人要先挨一刀才知深浅；想"看着数字打"的玩家可以选 | 演出·信息 | M | `floater-extra-words`、`learning-notice`、`magic-impact-bar`、`identity-bar-bits`、`status-page-extras`；UI6 `ea45f5b4`、KNOWN `3fad7816`、[身份栏](evidence_packets/static_reverse/original_identity_bar.md) |
| OPT-GUIDE ★ | 操作提示 | 原版移动只画范围、撤离格只在剧本插入时画、AI 待机与再次行动没提示 → 移动画路径线和「移動 3/5」费用栏与「可通過，不能停留」、撤离格常驻标记、「待機」「再次行動」提示、状态页底部「保存／讀取／待領物品／返回」按钮条、大地图点名、标题悬停亮起、系统卷轴确认框问句与提示行、道具使用列表的说明提示与「沒有道具」「道具 N / 8」、道具说明的解释行（行动环图标下的说明字是原版画法，默认就画，不归本项） | 新手第一次玩看得懂该点哪里、能走到哪 | 演出·信息 | M | `move-path-overlay`、`wait-cue`、`extra-action-cue`、`status-page-extras`、`world-map-presentation`、`title-flow-extras`、`panel-captions`；ESCAPEMARK `644178ea` |
| OPT-GROWTH ★ | 升级加点方式 | 原版每升一级一个窗，点数没分完不能关 → 一次升多级合成一个窗，可右键暂缓，状态页「成長點」随时再分 | 战斗中途不被加点窗卡住，可以看完局势再加；最终属性两边相同 | 演出 | S | `growth-point-reserve`、`growth-window-timing`、[升级窗](evidence_packets/static_reverse/original_growth_window.md)、GROWTHWIN `cc1a4709` |
| OPT-PACE ★（快） | 演出节奏 | 原版切入特写和地图演出按原速播完，对白擦出／上卷时不收确认，剧情走位不能快进 → 三档：原版／快（演出 2 倍、对白按键立即整屏、确认键快进走位）／极快（再加跳过切入特写，直接出结果数字） | 127 场战斗反复看同样的切入很耗时间 | 演出 | M | `dialogue-timing`、`script-fast-forward`、`settings-ready-action`；`CombatPresentationTiming.gd` 已有开发用倍速开关 |
| OPT-RETRY ★ | 败北后重来 | 原版败北 → GAME OVER → 回标题，没有重新挑战 → GAME OVER 画面加「重新挑战本战」，用进入本战时的队伍重进 | 没存档就得从回憶錄重走；这相当于原版在首次行动时存一份戰場記錄，不给新能力 | 演出 | S | [原版胜负收尾](evidence_packets/static_reverse/original_battle_end_flow.md)、`game-over-screen`、RESULTPAGE `a6963e2c` |
| OPT-CURSOR | 光标 | 原版红宝石权杖画进 640×480 画面，跟着窗口放大 → 用系统硬件光标显示同一支权杖（不放大、不晚一帧） | 软件画的光标比鼠标晚至少一帧，大窗口下权杖被放大发糊 | 外观 | S | [游戏光标](evidence_packets/runtime_observations/game_cursor/README.md)、`cursor-hide-item-icon`、CURSOR `84eb5465` |
| OPT-FONT | 字体 | 原版 FONT.24／FONT.15 位图字 → 系统字 | 高分屏下系统字更清楚。**已接**（lane FONT）：读点 `OriginalBitmapFont.install`（自动加载 SimplifiedDisplay 启动时、重製選項页关闭且有值变了再读）换默认主题字体，新开的界面用新字体 | 外观 | S（字体导入本身 L，另算） | `bitmap-font` |
| OPT-DEV | 开发开关（③层，不进设置页） | 保留环境变量和命令行：`HSL_RNG_SEED`、`HSL_AUTOPLAY_BRAIN`、`HSL_CUTIN_PLAYBACK_SPEED`、`--debug-hud`、`tests/diagnostics/export_enemy_turns.gd`；新增 `HSL_OPTIONS_PRESET` 供冒烟用；**P 停格／N 单步现在是常驻 autoload，谁都能按**：为实玩验收而设，改成开发开关、由 `tools/play.sh` 默认打开 | 正式玩家不该误触调试功能，实玩验收照常可用 | — | S | `debug-pause` |

## 4. 不做成选项的

| 项 | 理由 |
| --- | --- |
| OPT-STAMINA 开场气力 | 不做成选项——原版规则已照做（STAMINA-RULE）：原版裁判实测首次登记取 PLAYERS 气力（第 51 关雷歐納德 20、雷特首次登记那场 8，其余 0），携带进关清 0，上一段脚本执行过 actKeepPlayerST 才保留余气；"每场从 0 开始"随之取消（[开场实测](evidence_packets/static_reverse/original_stamina.md#证据)） |
| AI 集火／AI 难度 | 规则改动。目标定义是 AI「规则等价＋分布等价」；再开一档 AI 就是第二套规则，裁判管不到。自动对局胜率低是原版难度，不是回归（PROJECT 第八轮）。嫌难的玩家用 OPT-INFO／OPT-RETRY，不改规则 |
| 伤害／经验／金钱倍率、敌人等级 | 平衡滑杆，非目标 |
| 战斗结果页 | 原版没有（RESULTPAGE 已删）；战绩页不帮玩家做任何决定，真正有用的"重来"由 OPT-RETRY 提供 |
| 胜负条件板自动淡出 | 只省开场一次按键，不值得一个开关；`--script` 驱动用的自动淡出接缝保留在开发层（`winfail-board-dissolve`） |
| 对白不拆专名 | 原版 38 字节硬断会把「雪｜拉」拆开，属原版缺陷；用户实玩报过，直接保留为永久偏离（`dialogue-line-breaks`） |
| 战斗中 F5／F9 存读档 | 原版本来就能在战斗卷轴里 儲存戰場記錄（[原版存档格式](evidence_packets/static_reverse/original_save_format.md) 记录的 HSLBAT.SAV 就是首次行动时从卷轴写的），快捷键只是捷径。注意：差异清单 `in-battle-checkpoint` 写"原版战斗内不能存档"，与该证据冲突，建议负责人更正 |
| 全队阵亡判负 | 原版靠剧本保证不会出现这种局面，重制的兜底只在重制独有的状态下触发，不影响原版层（`party-wipe-rule`） |
| 跨战 HP／MP 回满 | 原版跨关承接还没读清，是缺口不是选项；查清后原版层照原版（`carry-model`） |
| 繁体显示 | 繁体要重画约 80 张图，低优先，接缝已留（`simplified-display-gaps`）；配乐已换成原版曲目，不再是选项 |
| 重制自有界面与流程的文字 | 面板说明、续玩提示、预览关结束卡、Home 回中：原版没有对应的东西可切换，保留（`panel-captions`、`campaign-flow-extras`、`title-flow-extras`、`opening-end-card`、`home-recenter`） |
| 悬停身份栏规则 | 原版规则还没读完，先查（`hover-strip-rule`）；技能射程与脚印已照原版调色板与各自脉动 |

## 5. 三件已定的事

1. **默认改成原版**：下面这些今天默认开着的重制行为默认关掉（选「舒适」一键找回）：飘字里的状态说明字（UI6 暂留的那部分）、行动环说明、移动路径与费用栏、待機／再次行動提示、法术命中血条、对白擦出中按键立即整屏、剧情走位快进、一次升多级合成一个窗；差异清单对应条目随之改为已做（原版成为默认），改良记为 OPT-XXX。
2. **开场气力**：不做成选项，原版裁判实测（STAMINA-MEASURE）后直接照原版（STAMINA-RULE，见 §4），规则类选项与 B2 底座因此暂无用户。
3. **预设名**：第一章叫「原版」「舒适」「自定」；续集里同一个默认预设显示为「作者默认」（见 §8）。

## 6. 存档与承接口径

- **规则类**：在「開始新故事」时按设置页取值，写进战役进度记录（`user://campaign_progress.json` 和各回憶錄，只记和默认不同的项）。每次交接随交接记录带给下一战；`BattlePlayLoop.create()` 把它放进只读键 `rule_options`，登记在 `BattleLoopConfig.CONFIG_SOURCE_KEYS`（按需出现的那一组）。`BattleCheckpoint.configuration()` 只在 `rule_options` 非空时把它并进摘要——全原版战役的摘要和今天逐字相同，现有 v6 存档照读，不升存档版本。
- **读档不一致**：战斗存档另存一份明文 `rule_options`，读档先按它建局，再核摘要，所以正常情况下读档跟着存档走，不拒读也不弹提示；读回憶錄就换成那条战役的选项。只有存档里的选项本版本不认识、取值非法、或摘要对不上时才拒读（`incompatible_save_configuration`），提示写明是哪一项。不做"提示后强行读"：规则不同的状态无法证明合法。
- **战役中途**：规则类选项只能在标题开新故事前改；战斗和大地图的設定選項里显示为灰色，写"本战役开始时已锁定"。队伍承接（CampaignCarryRules）和 campaign.json 的 `carry_policy` 不用改：选项跟着进度记录走，不跟着队伍走。
- **演出／外观类**：存在 `user://settings.json`（`GameSettings`），加 `preset` 和 `presentation` 两个键。现有读法忽略未知键、缺键补默认，所以不用升 `hsl_settings.v1`。不进任何存档，读档不检查，改了下一次演出就生效。

## 7. 测试与门禁口径

- 门禁、原版裁判（敌人回合、交锋对拍、128 关批量对照）、自动对局、剧情 explorer 一律只跑默认选项；`HSL_OPTIONS_PRESET` 不设就是原版。
- 「舒适全开」只冒烟一次：快门里把 `run_scene_smoke` 在 `HSL_OPTIONS_PRESET=comfort` 下多跑一遍（已接入：`tools/verify_runner.py` 的 `run_scene_smoke.gd#comfort` 作业），只看有没有脚本错误、卡死，不比数值。
- 不测组合，不为每个开关写测试（AGENTS 测试政策）。演出类底座（B1）不加测试；规则底座（B2）只加一个用例，放在现有 `run_battle_scene_runtime_tests`：非默认规则选项进摘要、读档按存档里的选项建局——这条不写就抓不到"读档读成了另一套规则"。
- 演出类选项在原版层必须和今天逐字相同：自动对局结果文件不变就是证明，不另写断言。

## 8. 与续集引擎的关系

campaign.json 可选两个键：`option_defaults`（这个战役默认预设的取值，第一章不写＝全原版）和 `option_hidden`（在这个战役里没意义的选项不显示，例如没有隐藏宝箱的续集隐藏 OPT-TREASURE）。取值顺序：代码默认 < campaign.json `option_defaults` < 玩家选择。规则类的作者默认值同样只在开新故事时生效。所以续集没有"原版"可言时，「原版」预设就是「作者默认」。

## 9. 实施计划

| 步 | 内容 | 量 | 前置 |
| --- | --- | --- | --- |
| B1 底座（**已做**，lane OPTIONS-B1） | 选项注册表（卡片字段即数据：id、层级、影响层、取值、原版值、舒适值、读点）和取值顺序；`GameSettings` 加 `preset`／`presentation`；campaign.json `option_defaults`／`option_hidden` 读取；设置页：原版 設定選項 窗保持原样，旁边加「重製選項」入口进二级页（三个预设钮＋每项一行说明与层级标记，布局是重制设计）；`HSL_OPTIONS_PRESET` 开发缝＋快门舒适冒烟；P／N 停格改为开发开关（`tools/play.sh` 默认开）。**落地**：注册表 [`content/authored/options/remake_options.json`](../content/authored/options/remake_options.json)（八张演出／外观卡，`read_points` 全空；`page` 块是设置页版面，改数据即可调）；取值与读点接口 [`GameOptions`](../game/settings/GameOptions.gd)（`value(id)`／`is_original(id)`）；设置页入口＝设定选项窗下一条「重製選項 ›」（键盘从 音樂音量 再按下），二级页 [`RemakeOptionsPage`](../game/settings/RemakeOptionsPage.gd)；另有 Tab 入口（lane OPTIONS-HOTKEY）：任何画面按 Tab 开关同一页，开着时整棵树暂停（自动加载 [`RemakeOptionsHotkey`](../game/settings/RemakeOptionsHotkey.gd)），关页且值变了通知场景重读（OPT-TREASURE 当场重画宝箱）；规则分组本期不放（开场气力改为照原版实现，不做成选项）；停格开关 `HSL_DEBUG_PAUSE`（不设时无窗口开、有窗口关）；快门接入舒适冒烟由负责人做 | M（1 条 lane） | — |
| S1（**已做**，负责人直接接在合并树，2026-09-26） | OPT-TREASURE：HIDDENCHEST 合并后原版＝隐藏；读点 `BattleSceneRuntime._ready` 设 `treasure_view.reveal_all_chests = not GameOptions.is_original("OPT-TREASURE")`，全部畫出＝画闭箱＋悬停提示＋确认音。原版预设第 1 关隐藏宝箱不画、踩上响发现音；两边领到的东西相同 | S | B1、HIDDENCHEST |
| S2（**已做**，lane OPTIONS-S2） | OPT-INFO：从 UI6 `ea45f5b4` 之前取回头顶命中率／击数和飘字附加词，敌人面板在读已知字节处加"公开"分支。验收：原版预设无头顶行、未交手敌人 ???；舒适预设都可见。**落地**：读点见注册表 `read_points`（选格画面进入时、每一击、每次命中、状态页打开、回合末回执各读一次）；原版分支即现行代码、逐字不变；特写结果行的说明字由表现层在切入层之上另立一行，不改 `BattleCombatCutin`。**法术受者血条不归本卡**：原录像 V08 frame_041（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_041.png`） 原版就在受者旁画 HP 24/43、MP 0/0 两条再出数字 19，血条是原版行为（只有 0.45 s 是重制估值），两边都保留；`magic-impact-bar` 条目「原版直接出数字」与此冲突，待更正 | S–M | B1 |
| B2 规则底座 | 只在第一条规则类选项获批时做：`rule_options` 只读键、摘要并入、战斗存档明文副本与读档先建局、进度记录／回憶錄携带、设置页锁定；加 §7 那一个用例 | M | 规则类选项获批 |
| S3a（**已做**，lane OPTIONS-S3） | OPT-GROWTH：读点 `BattleGrowthPanel.show_unit`（升級窗每次打开读一次，含状态页「成長點」重开）设 `postpone_allowed`；原版分支即 GROWTHWIN 现行代码（右键／Esc 被吞、点满才出 OK）；合成一窗，可暫緩 时恢复 GROWTHWIN 之前的写法：右键／Esc 关窗、点数留着，状态页「成長點」随时再分，读档后／下一场首个安静时刻再弹。一次升多级：原版分支每级一个窗（GROWTHWIN2 照原版，`growth-point-reserve`），合成一窗 分支一个窗给全部点数，最终属性相同 | S | B1 |
| S3b（**已做**，lane OPTIONS-S3） | OPT-RETRY：读点 `GameOverScreen._ready`（GAME OVER 画面建好时读一次）设 `retry_offered`；原版分支即 RESULTPAGE 现行代码（任意键或 160 tick 淡出回标题）；可重新挑戰本戰 时画面下方加「重新挑戰本戰／回到標題」两行（上下键／Enter／鼠标），不自动离开；重新挑战把进入本战的交接 `CampaignProgress.last_entry`（戰場記錄读档去掉 `load_checkpoint`，从本战开头打）重设为 pending 再进战斗场景——与 RESULTPAGE 之前「重新挑戰」的 reload 同一条重进路径，开场演出照放 | S | B1 |
| S3c（**已做**，lane OPTIONS-S3） | OPT-CURSOR：读点 `GameCursor._read_cursor_option`（自动加载启动时读一次；重製選項页关闭且有值变了经 `remake_options_changed` 再读）设 `hardware`；原版分支即 CURSOR 现行代码（权杖画进 640×480 画面随窗口放大）；系統硬體游標 时不画进画面、系统指针常显，`Input.set_custom_mouse_cursor` 用同一张 CURSOR01..10 图与热点（原尺寸、不晚一帧，翅膀随原版 6 tick 一帧照转）。舒适预设不开它（注册表 comfort_value＝原版） | S | B1 |
| S4a（**已做**，lane OPTIONS-S4） | OPT-GUIDE：读点见注册表 `read_points`（进入移动选格、建场景／关页、每个 AI 行动、每次第二次行动各读一次）。原版分支：移动选格只画范围与选格、撤离格只有剧本插入的 obj_Story_Show_Pos、AI 待机与再次行动无提示不停顿；**注意**这几项在本卡之前是默认开着的重制写法（§5 第 1 项预告的"默认关掉"），UI6／ESCAPEMARK 只去掉了飘字附加词与常驻金格。提示 分支恢复：路径线与「移動 3 / 5」费用栏及可通過／無法到達说明、撤离格常驻金格（ESCAPEMARK 644178ea 之前）、「待機」「守候」「麻痺」与「再次行動」各停 0.55 s | M | B1 |
| S4b（**已做**，lane OPTIONS-S4） | OPT-PACE：先查清「預備動作」＝原版 設定選項 第二行开关（[0x477c14] bit1，默认开），只管施法／绝技攻方的起手动作（m_action／s_action），关掉时起手不播、普攻不受影响——它不跳过切入，所以"跳过切入"仍是本卡的改良，照原版实现 預備動作 另起一项（原版层 設定選項，不是选项卡；[查证](evidence_packets/runtime_observations/menus_ui/README.md#預備動作0x477c14-bit1)）。读点见注册表 `read_points`：切入每次交锋第一段入队、地图起手与法术血条每次 begin、对白外每次确认各读一次。原版分支：切入与地图演出原速（× 1.0，逐字即现行代码）、对白外确认不快进走位（**注意**：快进在本卡之前默认开着）；快：切入与地图演出 2 倍、确认快进走位；極快：地图 2 倍、切入层不上画面按 16 倍跑完（信号与数字照序），直接看到地图结果数字。**未接**：对白擦出／上卷中不收确认（`dialogue-timing` 已定保留即时确认、不改所有对白宿主，且 37 处测试直接调用翻页），三档现在都即时整屏，卡上说明已不再声称原版值不收确认 | M | B1 |
| 后续 | 預備動作 照原版实现（設定選項 第二行加旋钮，关时 BattleCombatCutin 跳过 cast_lead 起手）、OPT-FONT（**已做**，lane FONT） | S | — |

顺序：B1 → S1＋S2（一条 lane 合做，先打演出类的通路）→ 其余演出类 → B2（仅在有规则类选项获批时；OPT-STAMINA 已照原版，不再排队）。首批合计约 4–5 条 lane；规则类通路没有用户就不先建。

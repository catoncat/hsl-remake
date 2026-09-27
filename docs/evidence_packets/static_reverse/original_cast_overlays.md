# 施法确认到效果结束之间的地图覆盖层：射程／范围格、光标、身份栏

> evidence: static-derived; provisional · status: live · functions: 0x4100e0, 0x411480, 0x4116a0, 0x42dc50, 0x430230, 0x43bf30, 0x43c0f0, 0x43e110, 0x43e1c0, 0x43e570, 0x441043, 0x4423b0, 0x442a90, 0x45e6da, 0x45e882 · tools: capture_ai_cue_review.gd, capture_cast_overlay_review.gd, capture_lead_in_review.gd, run_presentation_contract_tests.gd · updated: 2026-09-25

Checked: 2026-09-23。负责人审 A2 的 龍息 截图（火焰效果与红色射程格同屏）后提出：施法确认之后到效果结束，地图覆盖层保留哪些，重制从没按原版定过。本包从原版单位状态机读出每种覆盖层在「目标选择 → 确认 → 效果 → 结算 → 下一单位」各阶段有没有绘制调用，并记录重制的前后对照。几何、调色板与脉动见 [范围格包](original_range_cells.md)；本包只管显隐时机。

A2 截图本身是截图脚本的产物：它停掉场景的 `_process` 后直接调用 `_show_strike`，`BattleAttackCue` 没有机会走完并隐藏。产品路径上攻击引导总在效果开始前隐藏（下文「重制之前」列、`tests/capture_cast_overlay_review.gd` 的日志）。真正不对的是另一件事：玩家确认施法之后，重制又用 0.7 s 的红格＋目标方框把射程画了一遍，而原版玩家路径没有这一段。

## 原版状态机（static-derived，EXE SHA-256 `f0b5f835…70f7`）

单位更新函数按 `[unit+0x8c]` 分派。玩家分支 `0x443390..0x445660` 的状态表是 `0x445758`（索引字节）→ `0x445694`（入口），与本题有关的状态：

| 状态 | 入口 | 内容 | 覆盖层绘制调用 |
| --- | --- | --- | --- |
| `0x00` | `0x443a0d` | 地图浏览（下一单位） | 移动范围 `0x411200`（`0x443e0e`）、光标 `0x430230`（`0x443e22`）、悬停单位信息 `0x43e570`（`0x443e2a`） |
| `0x50` | `0x4442e4` | 普通攻击选目标 | 攻击范围 `0x411480`（`0x44459b`）、光标（`0x4445af`）、悬停信息（`0x4445b7`） |
| `0x51`／`0x57` | `0x444f3e` | 重置效果 VM（`0x4423b0` 清 `0x4c432c`／`0x4c4320`）后 `state+1` | 无 |
| `0x52` | `0x4445c1` | 普通攻击执行（`0x4423c0`） | 无 |
| `0x79` | `0x444ec1` | 魔法选目标（`0x4097f0` 查 `0x4c2ca0` MAGIC 表） | 法术名字幕 `0x43e110`（`0x444ec1`，见下「起手节拍」）、射程 `0x411480`（`0x444fb3`）、范围 `0x4116a0`（`0x444fca`）、光标（`0x444fde`）、悬停信息（`0x444fe6`） |
| `0x7a` | `0x444ff0` | 魔法效果：每 tick 只调 `0x442a90`（效果脚本 VM），返回非零后转 `0x8f` | 无 |
| `0x98` | `0x445099` | 绝技选目标（`0x409810` 查 `0x4c3920` SPECIAL 表） | 绝技名字幕 `0x43e1c0`（`0x445099`）、射程（`0x445256`）、范围（`0x44526b`）、光标（`0x44527e`）、悬停信息（`0x445286`） |
| `0x99` | `0x445290` | 绝技确认后：`0x409980`（ST 消耗 ×0x14）、`0x406d20`（切入战斗画面装载） | 无 |
| `0x8f`／`0xa1` | `0x445458` | 结算（`0x439f70`、`0x44f4d0`） | 无 |

- **确认 tick**：`0x79` 的确认分支（输入位 `0x4c6398 & ebx` 且目标链表非空）在 `0x444f3e` 调 `0x4423b0`、`state+1` 后直接跳到公共尾 `0x4447a7`，跳过本状态下方的四个绘制调用；`0x98` 的确认分支（`0x44516e` `state+1`，`0x4451c0` 跳尾）同样不画。所以从确认那一 tick 起，射程、范围、光标、悬停信息都不再绘制。
- **四个绘制函数在玩家分支里的全部调用点**（`tools` 外的一次性 `E8` 直接调用交叉引用，已压成上表）：`0x411480` 在 `0x44459b`／`0x444fb3`／`0x445256`，`0x4116a0` 在 `0x444fca`／`0x44526b`，`0x430230` 在 `0x443e22`／`0x4445af`／`0x444d8f`（`0x06` 移动选格）／`0x444fde`／`0x44527e`，`0x43e570` 在 `0x443e2a`／`0x4445b7`／`0x444fe6`／`0x445286`。确认后的 `0x7a`／`0x99`／`0x8f`／`0xa1` 里没有调用点。
- **`0x43e570`**：读光标格（`0x4c1a8c`／`0x4c1a90`）的单位位 `0x70000`，有单位时调 `0x436490(unit+0xa0, 3, -1)` 与 `0x43b4e0`，再调 `0x43e4a0`——即悬停单位信息，对应重制的身份栏 `BattleVitals`。
- **AI 施法状态**（同一函数的另一分支，表 `0x44231c`→`0x4422f4`；这一段没有输入读取，光标由 `0x45e882` 移向预先选好的目标 `0x4c2c70`／`0x4c2c74`，按计数器确认——据此判为 AI 路径）：`0x4417df` 画射程＋施法者格光标，计数见下「起手节拍」（lane P6 更正：进入时是 24 tick，`0x4417fe` 的 `0xc` 是离开时的重置值）；`0x44182a` 画射程并滑动光标；到位后 `0x441887` 调 `0x4423b0`、置 24 tick（`0x18`），`0x4418c7..0x441942` 画范围＋光标并以 `0x43c0f0` 滚屏；`0x441947` 保持 24 tick 画射程＋范围＋光标并给目标置标记位；计数到 0 转 `0x4419c6`／`0x4419f8`，每 tick 只调 `0x442a90`，不再画任何覆盖层。

**推论边界**：「不画」来自调用点缺失。覆盖层是每 tick 立即绘制（范围格包：脉动计数器每次绘制调用前进一格），没有保留层；本包没有重读主循环是否每 tick 整屏重画地图，这一点由下方的参考帧佐证。

## 起手节拍

lane P6，static-derived。AI 行动的地图起手与字幕，逐 tick 读自同一单位更新函数（AI 分支 `0x440662..0x4420ba`）。「tick」＝原版主循环一次（16 ms，[tick 率](../runtime_observations/original_tick_rate/README.md)）。

| 段 | AI 普通攻击（子状态表 `0x44233c`，`[unit+0x8c]` 7–11） | AI 魔法（表 `0x4422f4` 状态 7–11）／绝技（`0x441a46` 起） |
| --- | --- | --- |
| 准备 | `0x44136f`：光标＝攻击者像素 −16，`[unit+0x94]=6`，状态 +1 | `0x44174d`（绝技 `0x441a46`）：先 `0x43bf30` 把镜头移到施法者、到位后光标＝施法者像素 −16，经 `0x441ad3` 置 `[unit+0x94]=0x18`（24），状态 +1 |
| 射程 | `0x44139d`：每 tick 画射程 `0x411480`；计数 >0 时减一并在攻击者格画光标——**6 tick** | `0x4417df`（绝技 `0x441ae9`）：每 tick 名字幕＋射程＋施法者格光标，减到 0 时状态 +1——**24 tick** |
| 滑动 | 计数为 0 后同一状态每 tick 转 `0x440233`：`0x45e882` 走一步、画射程与新位置光标，贴屏边时 `0x42dc50` 滚屏；到位的那一 tick 状态 +1、置 12 | `0x44182a`（绝技 `0x441b35`）：名字幕＋射程，`0x45e882` 走一步后画范围 `0x4116a0`＋光标并 `0x43c0f0` 让镜头跟光标；到位那一 tick 调 `0x4423b0`、状态 +1、置 24 |
| 目标 | `0x44142a`：给目标置标记位、只画光标（**不画射程**），减到 0 时状态 +1——**12 tick**；`0x4416ab` 再用 1 tick 调 `0x4423b0`；`0x441492` 普通攻击 `0x4423c0` | `0x441947`（绝技 `0x441c4c`）：名字幕＋射程＋范围＋光标并置标记位——**24 tick**；之后魔法在同一状态每 tick 画名字幕并跑效果 VM `0x442a90`，VM 离开阶段 0（先 `0x43bf30` 镜头回施法者）后转 `0x4419f8`（只跑 VM）；绝技第 24 tick 扣 ST（`0x409980`）并装载切入 `0x406d20` |

- **滑动 `0x45e882(x, y, tx, ty, 16, &x', &y')`**：距离＝`trunc(sqrt(dx²+dy²))`（`0x46e0f0` fsqrt → `0x46e720` 截断取整）；≤1 时贴到目标并返回 0（到位，这一 tick 计入滑动）；否则步长＝`max(2, min(16, 距离>>3))`，方向＝`0x45e6da` 的 256 分度角（`|dy|·65536/|dx|` 对 `0x4a3dfc` 的 64 个半步正切边界二分，再折象限；竖直为 64／192），每轴位移＝`(cos／sin 表 × 步长) >> 16`（`0x4a35fc`／`0x4a39fc`，算术右移）。三张表可由公式逐项重算（cos／sin＝`round(65536·cos／sin(2πi/256))`，边界＝`round(65536·tan(2π(i+½)/256))`，256 项与 64 项全等）；索引 256 读到下一张表的首项。所以滑动是「远处每 tick ≤16 px、近处按距离八分之一减速、最后 2 px」的缓出，时长随距离：一格 15 tick、两格 20、三格 24、（1,1）23、十二格 42（离线按 EXE 表逐指令模拟，`BattleAttackCue.glide_path` 与之逐 tick 对齐，合同见下）。
- **目标坐标约定**：AI 目标 `0x4c2c70`／`0x4c2c74` 与光标同为「格像素 −16」（`0x40d4a5` 写入前 `sub 0x10`；普通攻击目标 `0x4c297c`−16，`0x440248`），所以滑动距离＝格差×32。
- **名字幕 `0x43e110`（魔法）／`0x43e1c0`（绝技）**：`0x4098b0`／`0x4099b0` 从 MAGIC／SPECIAL 表取名字串，`x = 镜头x + 320 − (字节数/2)·12`、`y = 镜头y + 0x114`（276），`0x460884` 先在 (x+1, y+1) 画黑色（0）再在 (x, y) 画白色（`0xffff`）——**屏幕水平居中、上沿 y=276 的固定位置**，与格子位置无关（录像 14 里「在格下方」是镜头恰好把格子放在上半屏）。调用点只有 AI 魔法 `0x4417df`／`0x44182a`／`0x441947`、AI 绝技 `0x441ae9`／`0x441b35`／`0x441c4c`、玩家 `0x444ec1`（`0x79`）与 `0x445099`（`0x98`）；效果态 `0x4419f8`／`0x7a`、切入与结算都没有。两次 `0x460884` 的字体都是 `[0x4c1ae0]`（`0x43e158`／`0x43e18b`），即 FONT.24＋ASCFONT.24 正文面（全角 24×24、格顶在 y、前进 24 px）；`0x32` 是其后的另一参数，不是字体。按字节居中与每字前进 24 px 一致，录像 14 源帧 9987 的「幻火」墨迹 x 298..318 与 321..342、y 281..296（638 宽录像），与 FONT.24 字形逐像素相同（横向差 1 px 来自 638 宽裁切）。

## 起手的镜头与各段覆盖层（lane R7-CUE，2026-09-25）

static-derived，r2 读同一 EXE。补齐 P6 留下的两件事：起手各段画哪些几何、镜头怎样跟。

| 段 | AI 普通攻击 | AI 魔法／绝技 |
| --- | --- | --- |
| 镜头段（重制新增的段名） | 敌方 mode 5 子状态 1 `0x441043` 每 tick 先 `0x43bf30(actor, 0)`；到位后路径为空（`0x4c63c0 == 0`）直接进子状态 7 普攻准备——不移动的普攻也先把镜头滑到攻击者；普攻子状态 7–11 自身不动镜头（mode 5 经 `0x4421d4 → 0x440b2c` 分派，不经 `0x440b14` 的 `0x43bf30`） | 准备 `0x44174d`／`0x441a46` 先 `0x43bf30(caster, 0)`；返回 0 的 tick 什么都不画、不写字幕 |
| 射程 | 射程＋攻击者格光标 | 名字幕＋射程＋施法者格光标 |
| 滑动 | 射程＋光标；`0x440233` 走一步后，新光标 (x′, y′)（格左上像素）按 `y′ < 0 ? y′ > [0x4c0964] : y′ < [0x4c096c]` 请求 (0, dy)、按 `x′ < 0 ? x′ > [0x4c0960] : x′ < [0x4c0968]` 请求 (dx, 0)（`0x4402cd..0x441425`），`0x46bede` 加完再夹取 | 名字幕＋射程；`0x45e882` 走一步后 `0x4100e0(caster, x, y, 技能, …)` 以**新光标像素 >> 5** 为中心重算作用范围（`0x4101c1..0x4101ca`，只查地图边界与格标志，**不查射程**），`0x4116a0` 画范围（魔法调色板 0、绝技 1）＋光标，再 `0x43c0f0(x, y)` |
| 目标 | **只画光标**（`0x44142a` 无 `0x411480`） | 名字幕＋射程＋范围＋光标（`0x441947`，无 `0x43c0f0`） |

- **`0x43c0f0(x, y)` 不是缓动**：目标左上＝(x − 0x130, y − 0xb0) 夹到 `[0, 0x4c0958]`×`[0, 0x4c095c]`，差值一次交给 `0x42dc50`（`0x43c0f8..0x43c136`）——每 tick 把光标格放在视图 (320, 192)，与 `0x43bf30` 的落点相同。光标每 tick 最多走 16 px，镜头随之同步走；P6 记的"步长未读"不存在。`0x4c0958`／`0x4c095c` ＝ max(0, 地图宽 − 640)／max(0, 地图高 − 480)（关卡装载 `0x46bc05..0x46bc58`）；边界带 `0x4c0960..0x4c096c` ＝ 320／240／地图宽 − 320／地图高 − 240（同处）。
- **普攻滑动测的是位置正负，不是方向**：走路跟随（`0x4411cb`）按路径码分方向判边；这里 `test eax, eax` 测的是新光标坐标。光标在地图上坐标不为负，所以实际规则是"光标不在右／下半屏边缘带里，镜头就与光标同步平移"，向左、向上走也照样请求（再由夹取挡住）。照二进制复刻。
- **镜头段的长度**：`0x43bf30` 首次调用即在容差内时同一 tick 返回 1（`0x43bfd8`）；否则每 tick `0x45e80d`（战斗步长 32、容差 4）走一步，到位那一 tick 落到目标并返回 1，这一 tick 就是准备 tick。重制沿用 P6 不计准备 tick 的约定：镜头段＝返回 0 的 tick 数。

**重制接线**：`BattleAttackCue` 在 `begin` 调共享的 `BattleCameraController.scroll_to_grid(行动者格)`（与其他战斗对准同一落点），镜头段长度取 `scroll_ticks − 1`；`stage()` 依次为 camera／range／cursor／target。`range_visible`／`cursor_visible`／`area_rects` 按上表取舍：镜头段不画、无字幕；普攻目标段只画光标；施法滑动与目标段按光标所在格画作用范围（`SkillTargetRules.effect_cells`，不用要求中心在射程内的 `cast_footprint`），样式照原版（UI6，用户 2026-09-25 定）：射程画 `0x411480` 的攻击调色板格，作用范围画 `0x4116a0` 调色板 0（魔法，`skill_id` 以 `magic:` 开头）／1（绝技），都是半强度脉动 ramp＋`I_rect` 边框，由 `BattleAttackCue._draw_cells` 取 `RangeCellOverlay.fill_color／border_sheet／border_region`（与玩家选择态同一 manifest），脉动与换帧按起手自己的 tick。滑动段每 tick：施法调 `center_on_point(光标格点)`（与 `center_on_grid` 同一换算，含夹取），普攻按 `edge_follow_request` 把步长交给 `snap_to`（加完再夹取）。`BattleSceneRuntime._present_ai_action` 不再对 AI 攻击把镜头滑到目标（原版没有这一步）。合同：`run_presentation_contract_tests.gd` 的 `ai_cue_camera_area_contracts`（从远处起：镜头段长度与共享对准一致、此段不画；射程段；施法滑动逐 tick 镜头＝参照控制器 `center_on_point` 的结果、作用范围＝光标格的 `effect_cells` 且出现过射程外格；普攻滑动逐 tick 镜头＝夹取后的前值＋光标步长；目标段施法画射程＋范围、普攻只画光标、镜头不动；边缘规则四例）。截帧：`tests/capture_ai_cue_review.gd`。

## 原版参考帧（原录像观察）

录像 14 幻火（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/contact_sheet.jpg`）：源帧 9987（frame_006（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_006.png`））红色范围格＋格下方「幻火」字样；源帧 10012 与 10037（frame_016（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_016.png`））地图压暗进入施法引导，范围格、光标和字样都已消失；10137 爆破、10162 受击条、10237 下一单位的蓝色移动范围。录像没有标出施法者阵营，只能佐证「效果期间不画范围格」，不能区分玩家和 AI 路径。单次录像，不作计时。

## 覆盖层 × 阶段

「原版」列：S＝static-derived（上表调用点），R＝原录像观察（录像 14 的外部帧，不是受控 runtime-measured），P＝provisional。「前」「后」＝本 lane 改动前后的重制（`capture_cast_overlay_review.gd` 在 battle_010（帕尼西亞城 廢墟）緹娜 治癒之水、battle_051（弃卒）雷歐納德 氣刃斬、battle_200（龍脊隘口，作者关）蕾雅 龍息 上逐阶段记录的可见性）。

| 覆盖层 | 目标选择 | 确认帧 | 施法引导／效果 | 结算（受击条、EXP） | 下一单位 |
| --- | --- | --- | --- | --- | --- |
| 射程格（MoveOverlay `AttackCell`） | 原版 画（S）· 前 画 · 后 画 | 原版 不画（S）· 前 不画 · 后 不画 | 原版 不画（S、R）· 前后 不画 | 原版 不画（S）· 前后 不画 | 原版 浏览态画移动范围（S，触发条件未读）· 前后 不画（显示行动环） |
| 范围格（施法区域） | 原版 画（S）· 前后 画（与射程格同一 overlay） | 原版 不画（S）· 前后 不画 | 原版 不画（S、R）· 前后 不画 | 原版 不画（S）· 前后 不画 | — |
| `BattleAttackCue`（红格＋目标方框，重制） | 前后 不画 | **玩家施法：原版 无此段（S）· 前 画（0.24＋0.22＋0.24 s）· 后 不画**；**玩家普攻（P6）：原版 无此段（`0x50`→`0x51`→`0x52`，S）· P6 前 画 0.7 s · P6 后 不画**；AI 施法：原版 射程 24 tick＋按距离滑动＋目标 24 tick（S）· P6 前 0.24＋0.22＋0.24 s · P6 后 原版 tick；AI 普攻：原版 射程 6＋滑动＋目标 12 tick（S）· P6 前 0.7 s · P6 后 原版 tick | 前后 不画（效果开始前隐藏） | 前后 不画 | 前后 不画 |
| 选择光标 `BattleSelectionCursor` | 原版 画（S）· 前后 画 | 原版 不画（S）· 前后 不画（确认帧的 `refresh` 先隐藏） | 原版 不画（S、R）· 前后 不画 | 原版 不画（S）· 前后 不画 | 原版 浏览态画（S）· 前后 不画（下一玩家单位直接开行动环） |
| 身份栏 `BattleVitals`（悬停单位信息） | 原版 画（`0x43e570`，S）· 前后 画 | 原版 不画（S）· 前后 不画 | 原版 不画（S）· 前后 不画 | 原版 不画（S）· 前后 不画 | 原版 浏览态画（S）· 前后 悬停时画 |
| 命中预览标签（重制） | 前后 画；UI6 起普攻／绝技不再画「命中 N%」（用户 2026-09-25 照原版，绝技命中率移到技能页说明框），只剩法术／辅助的「N 個目標」 | 前后 不画 | 前后 不画 | 前后 不画 | 前后 不画 |
| 魔法／绝技选单、行动环 | 前后 不画（选法后关闭）；原版 P（选单窗何时关未读） | 原版 P · 前后 不画 | 原版 P · 前后 不画 | 原版 P · 前后 不画 | 前后 玩家单位开行动环 |
| 技能名字幕 | 原版 玩家选目标画（`0x43e110`／`0x43e1c0`，S）· 重制 光标说明条里写名字（未改） | 原版 AI 起手的射程／滑动／目标段画，屏幕居中 y=276（S、R 源帧 9987）· P6 前 切入 `result` 顶部 y=16（引导期间不画）· P6 后 `BattleAttackCue.caption_label` 同段同位；玩家施法无起手、无字幕 | 原版 不画（S；魔法效果 VM 阶段 0 仍画几 tick，P）· P6 前 切入／地图效果顶部画名字 · P6 后 不画，结果行出现时才带名字（重制结果行）· UI6 后 结果行只有数字、不带名字 | 前后 不画 | — |
| 道具使用 | 前后 目标页在道具窗内，不画地图覆盖层；原版 P（道具目标态未定位；上述四个绘制函数在玩家分支里没有别的调用点，negative-evidence） | 前后 窗口关闭、浮字 | — | — | — |

作者技能（龍息）与第一章技能走同一条 `BattlePresentation.refresh` → `BattleAttackCue.leads` 路径，结果一致。

## 重制接线

**P6 起**：`BattleAttackCue.leads(strike, attacker)` 只看施放者——`player_commandable` 时返回 false（普攻与施法同一条），AI 的攻击与施法照旧 `begin`；`begin` 按收据有无 `skill_id` 取普攻（6／滑动／12 tick）或施法（24／滑动／24 tick）计数，滑动逐 tick 取 `glide_path`（上文 `0x45e882` 的移植），全部经 `OriginalTick` 换算；施法的名字（`magic_name`／`skill_name`）进 `caption_label`（CanvasLayer 上 640 宽居中、上沿 276、20 px 白字＋1 px 黑影、字距 4＝每字前进 24 px），与起手同显同隐；`SkillEffectScriptPlayer`／`BattleCombatCutin._process_borrowed_skill` 不再在顶部 y=16 写名字，结果行（y=264）到 `aniShowHitResult`／impact 才出现。合同：`run_presentation_contract_tests.gd` 的 `lead_in_contracts`（`glide_path` 对离线模拟的 11 组距离与两条逐 tick 路径；玩家普攻确认帧无起手、切入已开始；AI 普攻 6＋15＋12 tick 各段边界；AI 施法两格外 24＋20＋24 tick、字幕同段同位、切入不再顶部写名）。以下为 P5 当时的接线：受理的交锋带 `skill_id`（魔法、绝技、月花圓舞等全部技能收据都有）且施放者 `player_commandable` 时返回 false，`BattlePresentation.refresh` 改调 `skip(sequence)`——记下序号、不画、同一帧把片段交给切入／地图效果；其余交锋（普通攻击、AI 的攻击与施法）照旧 `begin`。AI 从不为 `player_commandable` 单位行动（`BattleLoopAI` 直接交还玩家），所以这个判断等于「玩家下令的施法」。规则、收据、回合与 sweep 不变。合同：`run_presentation_contract_tests.gd` 的 `cast_overlay_contracts`（玩家绝技确认帧无攻击引导、无射程格／光标／身份栏／命中预览／菜单，切入已开始；AI 施法仍从引导的 range 阶段开始，引导结束才进效果）。

## 不支持的结论

- （P6 已落地）AI 起手的原版计数、玩家普攻无起手、技能名字幕的位置与时段——见上「起手节拍」与「重制接线」。
- （R7-CUE 已落地）AI 起手各段的覆盖层取舍与镜头（施法者／攻击者镜头段、施法滑动逐 tick 对准光标、普攻滑动随光标平移）——见上「起手的镜头与各段覆盖层」。
- （UI6 已落地）AI 起手的射程与作用范围照原版调色板＋`I_rect` 边框（上「重制接线」）；用户录屏 469.2 s 的红色半透明格＋红边即 `0x411480` 攻击调色板。玩家选目标的结算脚印仍是用户定的洋红＋白边（`BattleSceneOverlays.FOOTPRINT_*`）。起手时计数器 `0x4c1a80`／`0x4c1a84` 的相位（原版是全局计数，重制从起手第 0 tick 起数）未读。
- AI 普攻目标段后的 1 tick `0x4423b0`（`0x4416ab`，无绘制）与魔法效果 VM 阶段 0（镜头回施法者期间字幕仍画）未建模——前者 16 ms，后者长度取决于镜头距离（`0x43bf30`）。
- 玩家选目标时原版同样在屏幕 y=276 画名字幕（`0x444ec1`／`0x445099`）；重制保留 `BattleSelectionCursor` 说明条里的名字（现有合同 `run_battle_scene_runtime_tests` 断言它），没有另加屏幕字幕，以免同屏两处名字——要对齐就把说明条的名字移到 `caption_label` 并改那两条断言。
- 魔法／绝技选单窗在 `0x78`→`0x79` 时是否关闭未读（provisional）；替换路线：读 `0x444e58`（`0x78`）。（P5 提到的 `0x445099` 开头 `0x43e1c0` 已读：是绝技名字幕，见上。）
- 道具使用的原版目标态没有定位（provisional）；替换路线：从行动环道具项的状态转移（`0x63..0x72` 段）读起。
- 浏览态 `0x443e0e` 画移动范围的条件没有读。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleAttackCue.gd` layout：what each lead-in stage draws: attack range stage range＋cursor, glide range＋cursor, target cursor only — 0x44142a has no 0x411480; cast range stage range＋cursor, glide and target range＋the effect area 0x4116a0 at the cursor's cell (0x4100e0 with pixel >> 5, no range test)＋cursor; the camera: cast setup 0x43bf30 to the caster (no-move attack: sub-state 1 0x441043 to the attacker), cast glide 0x43c0f0 frames the cursor every tick, attack glide 0x440233..0x44141d requests the cursor's step unless it stands in the far half-view band; AI cast caption 0x43e110／0x43e1c0: the skill name centred on the screen, top at y=276, white over a black +1 px shadow

# 施法确认到效果结束之间的地图覆盖层：射程／范围格、光标、身份栏

> evidence: static-derived; provisional · status: live · functions: 0x4010c0, 0x401220, 0x401c20, 0x402499, 0x402b68, 0x402e47, 0x4034c6, 0x4035ef, 0x406d20, 0x4100e0, 0x411480, 0x4116a0, 0x42dc50, 0x430230, 0x43bf30, 0x43c0f0, 0x43e110, 0x43e1c0, 0x43e570, 0x441043, 0x4423b0, 0x442a90, 0x45e307, 0x45e6da, 0x45e882, 0x45f5f7, 0x461479 · tools: run_presentation_contract_tests.gd, run_skill_effect_script_tests.gd · updated: 2026-09-28

## 结论

- 原版单位状态机里射程 `0x411480`、范围 `0x4116a0`、光标 `0x430230`、悬停信息 `0x43e570` 只在选目标状态有调用点；从确认那一 tick 起到效果、结算都不画（static-derived）。
- 原版 AI 起手：普攻射程 6 tick＋按距离滑动＋目标 12 tick（只画光标），施法射程 24 tick＋滑动＋目标 24 tick，施法名字幕屏幕居中、上沿 y=276；玩家路径没有起手段（static-derived）。
- 重制 `game/battle/scene/BattleAttackCue.gd` 按这些计数与覆盖层取舍演出 AI 起手（`glide_path` 移植 `0x45e882`），玩家下令时不起手；显隐细节见证据块「覆盖层 × 阶段」（static-derived）。
- 差异：魔法／绝技选单窗的关闭时机、道具目标态、浏览态画移动范围的条件与起手计数器相位，逐条见边界（provisional）。
- 原版施法引导（对象 154 `0x401c20`）不画黑底，地图上盖一层全黑屏形状按 1..8／16 级交叉淡化成阴影底；局部图与肖像以模式 0 不透明画在桶 0x33，子状态 4 的 16 call 也不淡化；残影是对象 179 的 6→1 级交叉淡化，局部图残影与面板同桶、画在面板之上（static-derived）。
- 重制 `AnimalCastLead`／`BattleCombatCutin.show_cast_lead` 照此画阴影级、不透明面板与残影先后；法术引导结束后的交叉淡化尾段未播，见边界（provisional）。

## 证据

几何、调色板与脉动见 [范围格包](original_range_cells.md)；本包只管显隐时机。

### 原版状态机（static-derived，EXE SHA-256 `f0b5f835…70f7`）

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
- **四个绘制函数在玩家分支里的全部调用点**（`E8` 直接调用交叉引用，已压成上表）：`0x411480` 在 `0x44459b`／`0x444fb3`／`0x445256`，`0x4116a0` 在 `0x444fca`／`0x44526b`，`0x430230` 在 `0x443e22`／`0x4445af`／`0x444d8f`（`0x06` 移动选格）／`0x444fde`／`0x44527e`，`0x43e570` 在 `0x443e2a`／`0x4445b7`／`0x444fe6`／`0x445286`。确认后的 `0x7a`／`0x99`／`0x8f`／`0xa1` 里没有调用点。
- **`0x43e570`**：读光标格（`0x4c1a8c`／`0x4c1a90`）的单位位 `0x70000`，有单位时调 `0x436490(unit+0xa0, 3, -1)` 与 `0x43b4e0`，再调 `0x43e4a0`——即悬停单位信息，对应重制的身份栏 `BattleVitals`。
- **AI 施法状态**（同一函数的另一分支，表 `0x44231c`→`0x4422f4`；这一段没有输入读取，光标由 `0x45e882` 移向预先选好的目标 `0x4c2c70`／`0x4c2c74`，按计数器确认——据此判为 AI 路径）：`0x4417df` 画射程＋施法者格光标，计数见下「起手节拍」（进入时是 24 tick，`0x4417fe` 的 `0xc` 是离开时的重置值）；`0x44182a` 画射程并滑动光标；到位后 `0x441887` 调 `0x4423b0`、置 24 tick（`0x18`），`0x4418c7..0x441942` 画范围＋光标并以 `0x43c0f0` 滚屏；`0x441947` 保持 24 tick 画射程＋范围＋光标并给目标置标记位；计数到 0 转 `0x4419c6`／`0x4419f8`，每 tick 只调 `0x442a90`，不再画任何覆盖层。

**推论边界**：「不画」来自调用点缺失。覆盖层是每 tick 立即绘制（范围格包：脉动计数器每次绘制调用前进一格），没有保留层；本包没有重读主循环是否每 tick 整屏重画地图，这一点由下方的参考帧佐证。

### 起手节拍

static-derived。AI 行动的地图起手与字幕，逐 tick 读自同一单位更新函数（AI 分支 `0x440662..0x4420ba`）。「tick」＝原版主循环一次（16 ms，[tick 率](../runtime_observations/original_tick_rate/README.md)）。

| 段 | AI 普通攻击（子状态表 `0x44233c`，`[unit+0x8c]` 7–11） | AI 魔法（表 `0x4422f4` 状态 7–11）／绝技（`0x441a46` 起） |
| --- | --- | --- |
| 准备 | `0x44136f`：光标＝攻击者像素 −16，`[unit+0x94]=6`，状态 +1 | `0x44174d`（绝技 `0x441a46`）：先 `0x43bf30` 把镜头移到施法者、到位后光标＝施法者像素 −16，经 `0x441ad3` 置 `[unit+0x94]=0x18`（24），状态 +1 |
| 射程 | `0x44139d`：每 tick 画射程 `0x411480`；计数 >0 时减一并在攻击者格画光标——**6 tick** | `0x4417df`（绝技 `0x441ae9`）：每 tick 名字幕＋射程＋施法者格光标，减到 0 时状态 +1——**24 tick** |
| 滑动 | 计数为 0 后同一状态每 tick 转 `0x440233`：`0x45e882` 走一步、画射程与新位置光标，贴屏边时 `0x42dc50` 滚屏；到位的那一 tick 状态 +1、置 12 | `0x44182a`（绝技 `0x441b35`）：名字幕＋射程，`0x45e882` 走一步后画范围 `0x4116a0`＋光标并 `0x43c0f0` 让镜头跟光标；到位那一 tick 调 `0x4423b0`、状态 +1、置 24 |
| 目标 | `0x44142a`：给目标置标记位、只画光标（**不画射程**），减到 0 时状态 +1——**12 tick**；`0x4416ab` 再用 1 tick 调 `0x4423b0`；`0x441492` 普通攻击 `0x4423c0` | `0x441947`（绝技 `0x441c4c`）：名字幕＋射程＋范围＋光标并置标记位——**24 tick**；之后魔法在同一状态每 tick 画名字幕并跑效果 VM `0x442a90`，VM 离开阶段 0（先 `0x43bf30` 镜头回施法者）后转 `0x4419f8`（只跑 VM）；绝技第 24 tick 扣 ST（`0x409980`）并装载切入 `0x406d20` |

- **滑动 `0x45e882(x, y, tx, ty, 16, &x', &y')`**：距离＝`trunc(sqrt(dx²+dy²))`（`0x46e0f0` fsqrt → `0x46e720` 截断取整）；≤1 时贴到目标并返回 0（到位，这一 tick 计入滑动）；否则步长＝`max(2, min(16, 距离>>3))`，方向＝`0x45e6da` 的 256 分度角（`|dy|·65536/|dx|` 对 `0x4a3dfc` 的 64 个半步正切边界二分，再折象限；竖直为 64／192），每轴位移＝`(cos／sin 表 × 步长) >> 16`（`0x4a35fc`／`0x4a39fc`，算术右移）。三张表可由公式逐项重算（cos／sin＝`round(65536·cos／sin(2πi/256))`，边界＝`round(65536·tan(2π(i+½)/256))`，256 项与 64 项全等）；索引 256 读到下一张表的首项。所以滑动是「远处每 tick ≤16 px、近处按距离八分之一减速、最后 2 px」的缓出，时长随距离：一格 15 tick、两格 20、三格 24、（1,1）23、十二格 42（离线按 EXE 表逐指令模拟，`BattleAttackCue.glide_path` 与之逐 tick 对齐，合同见下）。
- **目标坐标约定**：AI 目标 `0x4c2c70`／`0x4c2c74` 与光标同为「格像素 −16」（`0x40d4a5` 写入前 `sub 0x10`；普通攻击目标 `0x4c297c`−16，`0x440248`），所以滑动距离＝格差×32。
- **名字幕 `0x43e110`（魔法）／`0x43e1c0`（绝技）**：`0x4098b0`／`0x4099b0` 从 MAGIC／SPECIAL 表取名字串，`x = 镜头x + 320 − (字节数/2)·12`、`y = 镜头y + 0x114`（276），`0x460884` 先在 (x+1, y+1) 画黑色（0）再在 (x, y) 画白色（`0xffff`）——**屏幕水平居中、上沿 y=276 的固定位置**，与格子位置无关（录像 14 里「在格下方」是镜头恰好把格子放在上半屏）。调用点只有 AI 魔法 `0x4417df`／`0x44182a`／`0x441947`、AI 绝技 `0x441ae9`／`0x441b35`／`0x441c4c`、玩家 `0x444ec1`（`0x79`）与 `0x445099`（`0x98`）；效果态 `0x4419f8`／`0x7a`、切入与结算都没有。两次 `0x460884` 的字体都是 `[0x4c1ae0]`（`0x43e158`／`0x43e18b`），即 FONT.24＋ASCFONT.24 正文面（全角 24×24、格顶在 y、前进 24 px）；`0x32` 是其后的另一参数，不是字体。按字节居中与每字前进 24 px 一致，录像 14 源帧 9987 的「幻火」墨迹 x 298..318 与 321..342、y 281..296（638 宽录像），与 FONT.24 字形逐像素相同（横向差 1 px 来自 638 宽裁切）。

### 起手的镜头与各段覆盖层

static-derived：起手各段画哪些几何、镜头怎样跟。

| 段 | AI 普通攻击 | AI 魔法／绝技 |
| --- | --- | --- |
| 镜头段（重制新增的段名） | 敌方 mode 5 子状态 1 `0x441043` 每 tick 先 `0x43bf30(actor, 0)`；到位后路径为空（`0x4c63c0 == 0`）直接进子状态 7 普攻准备——不移动的普攻也先把镜头滑到攻击者；普攻子状态 7–11 自身不动镜头（mode 5 经 `0x4421d4 → 0x440b2c` 分派，不经 `0x440b14` 的 `0x43bf30`） | 准备 `0x44174d`／`0x441a46` 先 `0x43bf30(caster, 0)`；返回 0 的 tick 什么都不画、不写字幕 |
| 射程 | 射程＋攻击者格光标 | 名字幕＋射程＋施法者格光标 |
| 滑动 | 射程＋光标；`0x440233` 走一步后，新光标 (x′, y′)（格左上像素）按 `y′ < 0 ? y′ > [0x4c0964] : y′ < [0x4c096c]` 请求 (0, dy)、按 `x′ < 0 ? x′ > [0x4c0960] : x′ < [0x4c0968]` 请求 (dx, 0)（`0x4402cd..0x441425`），`0x46bede` 加完再夹取 | 名字幕＋射程；`0x45e882` 走一步后 `0x4100e0(caster, x, y, 技能, …)` 以**新光标像素 >> 5** 为中心重算作用范围（`0x4101c1..0x4101ca`，只查地图边界与格标志，**不查射程**），`0x4116a0` 画范围（魔法调色板 0、绝技 1）＋光标，再 `0x43c0f0(x, y)` |
| 目标 | **只画光标**（`0x44142a` 无 `0x411480`） | 名字幕＋射程＋范围＋光标（`0x441947`，无 `0x43c0f0`） |

- **`0x43c0f0(x, y)` 不是缓动**：目标左上＝(x − 0x130, y − 0xb0) 夹到 `[0, 0x4c0958]`×`[0, 0x4c095c]`，差值一次交给 `0x42dc50`（`0x43c0f8..0x43c136`）——每 tick 把光标格放在视图 (320, 192)，与 `0x43bf30` 的落点相同。光标每 tick 最多走 16 px，镜头随之同步走。`0x4c0958`／`0x4c095c` ＝ max(0, 地图宽 − 640)／max(0, 地图高 − 480)（关卡装载 `0x46bc05..0x46bc58`）；边界带 `0x4c0960..0x4c096c` ＝ 320／240／地图宽 − 320／地图高 − 240（同处）。
- **普攻滑动测的是位置正负，不是方向**：走路跟随（`0x4411cb`）按路径码分方向判边；这里 `test eax, eax` 测的是新光标坐标。光标在地图上坐标不为负，所以实际规则是"光标不在右／下半屏边缘带里，镜头就与光标同步平移"，向左、向上走也照样请求（再由夹取挡住）。照二进制复刻。
- **镜头段的长度**：`0x43bf30` 首次调用即在容差内时同一 tick 返回 1（`0x43bfd8`）；否则每 tick `0x45e80d`（战斗步长 32、容差 4）走一步，到位那一 tick 落到目标并返回 1，这一 tick 就是准备 tick。重制不计准备 tick：镜头段＝返回 0 的 tick 数。

### 原版参考帧（原录像观察）

录像 14 幻火（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/contact_sheet.jpg`）：源帧 9987（frame_006（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_006.png`））红色范围格＋格下方「幻火」字样；源帧 10012 与 10037（frame_016（原版帧见私有档案：`runtime_observations/original_gameplay_reference/14_tactical_map_magic_aoe/frame_016.png`））地图压暗进入施法引导，范围格、光标和字样都已消失；10137 爆破、10162 受击条、10237 下一单位的蓝色移动范围。录像没有标出施法者阵营，只能佐证「效果期间不画范围格」，不能区分玩家和 AI 路径。单次录像，不作计时。

### 覆盖层 × 阶段

S＝static-derived（上表调用点），R＝原录像观察（录像 14 外部帧，不是受控 runtime-measured），P＝provisional。重制列为当前行为。

| 覆盖层 | 目标选择 | 确认帧 → 效果 → 结算 | 下一单位 |
| --- | --- | --- | --- |
| 射程格（MoveOverlay `AttackCell`） | 原版 画（S）· 重制 画 | 原版 不画（S、R）· 重制 不画 | 原版 浏览态画移动范围（S，触发条件未读）· 前后 不画（显示行动环） |
| 范围格（施法区域） | 原版 画（S）· 重制 画（与射程格同一 overlay） | 原版 不画（S、R）· 重制 不画 | — |
| `BattleAttackCue` 起手 | 不画 | 玩家施法与普攻：原版无此段（`0x50`→`0x51`→`0x52`，S）· 重制 不画；AI 施法：射程 24＋滑动＋目标 24 tick；AI 普攻：射程 6＋滑动＋目标 12 tick（S）· 重制 同计数；效果开始前隐藏 | 不画 |
| 选择光标 `BattleSelectionCursor` | 原版 画（S）· 重制 画 | 原版 不画（S、R）· 重制 确认帧 `refresh` 先隐藏 | 原版 浏览态画（S）· 重制 下一玩家单位直接开行动环 |
| 身份栏 `BattleVitals`（悬停单位信息） | 原版 画（`0x43e570`，S）· 重制 画 | 原版 不画（S）· 重制 不画 | 原版 浏览态画（S）· 重制 悬停时画 |
| 命中预览标签（重制） | 普攻／绝技不画「命中 N%」（绝技命中率在技能页说明框），法术／辅助画「N 個目標」 | 不画 | 不画 |
| 魔法／绝技选单、行动环 | 重制 选法后关闭；原版 P（选单窗何时关未读） | 原版 P · 重制 不画 | 重制 玩家单位开行动环 |
| 技能名字幕 | 原版 玩家选目标画（`0x43e110`／`0x43e1c0`，S）· 重制 写在光标说明条 | 原版 AI 起手的射程／滑动／目标段画，屏幕居中 y=276（S、R 源帧 9987）· 重制 `BattleAttackCue.caption_label` 同段同位；效果期间原版不画（魔法效果 VM 阶段 0 仍画几 tick，P）· 重制 不画，结果行只有数字 | — |
| 道具使用 | 重制 目标页在道具窗内，不画地图覆盖层；原版 P（道具目标态未定位；上述四个绘制函数在玩家分支里没有别的调用点，negative-evidence） | 重制 窗口关闭、浮字 | — |

作者技能（龍息）与第一章技能走同一条 `BattlePresentation.refresh` → `BattleAttackCue.leads` 路径。

### 施法引导的合成

施法引导对象由 `0x406d20` 以 `0x45e307(0, 0, 0x9a)` 建成（对象 154 Animal_Attack，模板 planeEffect3，无 obj_Attribute），`+0xa4` 写 kind（1 法术／2 绝技）；kind 2 时 `[0x4c1408]` = 攻方 EFFECTS 程序，kind 1 时为 0。过程 `0x401c20`（过程表 slot 22）。合成器读法见 [tick 计数包](original_tick_counts.md)：模式 `0x20000000` → 操作 4 `0x4699fd`，`out = T[n](源) + T[16−n](下层)`。

| 项 | 原版（static-derived） | 地址 |
| --- | --- | --- |
| 黑底 | 每 call 尾部：`+0x80` 无 `0x100` 时以模式 0 把全黑屏形状 `[0x4bbb4e]`（`0x46067d`）画进桶 0x32；kind ≠ 0 的首 call 置 `+0x80 |= 0x100`，施法引导不画黑底（普攻切入画） | `0x4034c6`、`0x401e66` |
| 阴影底 | 调度器传入的消息字（`0x45f5f7` 在调用前读的 `+0x80`）带 `0x1000` 时：同一全黑形状、坐标＝镜头原点、桶 0x17、模式 `0x20000000`、级 n = min(`+0x90`, 8)；源为纯黑，地图与桶 < 0x17 的单位每分量 ⌊c·(16−n)／16⌋ | `0x4035ef..0x403647` |
| 阴影节拍 | aniShadowBG 那一 call 置位（`0x402499`，`+0x90` 清零），消息字下一 call 才带位；phase 12 每 call 先 `+0x90++`（`0x402752`）再画：级 1..8 各 1 call，之后停在 8。預備動作 关的法术：首 call 置位并在同一 call 进子状态 7 使 `+0x90 = 1`，第 k call 画级 min(k+1, 8) | `0x402499`、`0x402752`、`0x401ed4`、`0x4030f7` |
| 横幅 | 施法对象本身，kind 1／2 时 `+0xc = 0x32`，第二遍提交（在同桶黑底之后）；换边时模式 `|= 0x8000000`（x 缩放 −1） | `0x401cfd`／`0x401d58`、`0x401de6` |
| 局部图／肖像 | 过程内以栈上记录两次 `0x461479`：先局部图（`+0x9c` 张、`+0x96／+0x94`）后肖像（`+0x9e` 张、`+0x8a／+0x88`），桶 0x33、模式 0（子状态 0–3） | `0x402a80`、`0x402b0e`、`0x402e69..0x402ee5` |
| 子状态 4 | `+0x84` ≤ 16 的 call 模式 0（不透明）；=16 时 `+0xa0`（子状态 2 末置 10）倒数 10 call，第 11 call 读 `0x4c1408`：非零非 −1（绝技）→ phase 103，−1 → phase 101；0（法术）→ `+0x84` 继续：17 起模式 `0x20000000`，级 `+0x28` 自 16 每 2 call 减一（`0x4c6f70 = 0x20002`），到 `+0x84` ≥ 32 那 call 画级 9 后进子状态 5 | `0x402e47..0x402fbb` |
| 残影 | `0x401220`：`0x45e307(x, y, 179)`，复制形状与缩放，模式 = 施法对象模式 `| 0x20000000`（换边时 `0x28000000`，缩放＋交叉淡化），级 6，清创建跳画位；defProcShadowLeft 每 4 call 减一级、到 0 删除 | `0x401220`、`0x4010c0` |
| 残影深度 | 横幅残影（`0x402187`）留在模板桶 planeEffect2（resource-derived，`map_objects.json` 对象 179）；局部图残影（`0x402b68`）建后改 `+0xc = 0x33`、坐标＝局部图锚点 | `0x402b87` |
| 同桶先后 | 施法对象在 `0x45f5f7` 第一遍（调用过程）里就提交局部图／肖像；残影对象第二遍才提交，都挂桶尾，所以桶 0x33 内残影画在活动面板之上 | `0x45f5f7`、`0x461479` |

## 重制接线

- `BattleAttackCue.leads(strike, attacker)` 只看施放者：`player_commandable` 时返回 false（普攻与施法同一条，`BattlePresentation.refresh` 改调 `skip(sequence)`，同一帧把片段交给切入／地图效果）；AI 从不为 `player_commandable` 单位行动，所以这等于「玩家下令」。AI 的攻击与施法 `begin`：按收据有无 `skill_id` 取普攻（6／滑动／12 tick）或施法（24／滑动／24 tick），滑动逐 tick 取 `glide_path`，经 `OriginalTick` 换算。
- 名字幕：`magic_name`／`skill_name` 进 `caption_label`（CanvasLayer 上 640 宽居中、上沿 276、20 px 白字＋1 px 黑影、字距 4＝每字前进 24 px），与起手同显同隐；`SkillEffectScriptPlayer`／`BattleCombatCutin._process_borrowed_skill` 不在顶部写名字，结果行（y=264）到 `aniShowHitResult`／impact 才出现。
- 镜头与各段覆盖层：`BattleAttackCue` 在 `begin` 调共享的 `BattleCameraController.scroll_to_grid(行动者格)`（与其他战斗对准同一落点），镜头段长度取 `scroll_ticks − 1`；`stage()` 依次为 camera／range／cursor／target。`range_visible`／`cursor_visible`／`area_rects` 按上表取舍：镜头段不画、无字幕；普攻目标段只画光标；施法滑动与目标段按光标所在格画作用范围（`SkillTargetRules.effect_cells`，不用要求中心在射程内的 `cast_footprint`），样式照原版：射程画 `0x411480` 的攻击调色板格，作用范围画 `0x4116a0` 调色板 0（魔法，`skill_id` 以 `magic:` 开头）／1（绝技），都是半强度脉动 ramp＋`I_rect` 边框，由 `BattleAttackCue._draw_cells` 取 `RangeCellOverlay.fill_color／border_sheet／border_region`（与玩家选择态同一 manifest），脉动与换帧按起手自己的 tick。滑动段每 tick：施法调 `center_on_point(光标格点)`（与 `center_on_grid` 同一换算，含夹取），普攻按 `edge_follow_request` 把步长交给 `snap_to`（加完再夹取）。`BattleSceneRuntime._present_ai_action` 不再对 AI 攻击把镜头滑到目标（原版没有这一步）。合同：`run_presentation_contract_tests.gd` 的 `ai_cue_camera_area_contracts`（从远处起：镜头段长度与共享对准一致、此段不画；射程段；施法滑动逐 tick 镜头＝参照控制器 `center_on_point` 的结果、作用范围＝光标格的 `effect_cells` 且出现过射程外格；普攻滑动逐 tick 镜头＝夹取后的前值＋光标步长；目标段施法画射程＋范围、普攻只画光标、镜头不动；边缘规则四例）。
- 施法引导合成：`AnimalCastLead` 每 call 状态的 `shadow` 为阴影级 0..8（aniShadowBG 那一 call 为 0），子状态 4 的 16 call `fade` 恒 0；`BattleCombatCutin.show_cast_lead` 把黑层 alpha 设为级／16、面板 modulate 不透明、横幅残影排在横幅精灵下、局部图残影排在肖像精灵上。8 位 alpha 混合与原版 5／6 位分量截断只差末位。provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#施法引导的合成`（AnimalCastLead layout）。
- `game/battle/scene/BattleAttackCue.gd` layout：what each lead-in stage draws: attack range stage range＋cursor, glide range＋cursor, target cursor only — 0x44142a has no 0x411480; cast range stage range＋cursor, glide and target range＋the effect area 0x4116a0 at the cursor's cell (0x4100e0 with pixel >> 5, no range test)＋cursor; the camera: cast setup 0x43bf30 to the caster (no-move attack: sub-state 1 0x441043 to the attacker), cast glide 0x43c0f0 frames the cursor every tick, attack glide 0x440233..0x44141d requests the cursor's step unless it stands in the far half-view band; AI cast caption 0x43e110／0x43e1c0: the skill name centred on the screen, top at y=276, white over a black +1 px shadow
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md`（BattleAttackCue layout／timing）。
- 合同：`run_presentation_contract_tests.gd` 的 `lead_in_contracts`、`ai_cue_camera_area_contracts`、`cast_overlay_contracts`。

## 复现

`tools/godot.sh --headless --script res://tests/run_presentation_contract_tests.gd`；原版侧窗口回执的截帧驱动已退役，回执为历史记录。

## 边界

- 「不画」来自调用点缺失；主循环是否每 tick 整屏重画地图没有重读，由录像 14 参考帧佐证。
- 起手时计数器 `0x4c1a80`／`0x4c1a84` 的相位（原版是全局计数，重制从起手第 0 tick 起数）未读。
- AI 普攻目标段后的 1 tick `0x4423b0`（`0x4416ab`，无绘制）与魔法效果 VM 阶段 0（镜头回施法者期间字幕仍画）未建模——前者 16 ms，后者长度取决于镜头距离（`0x43bf30`）。
- 玩家选目标时原版同样在屏幕 y=276 画名字幕（`0x444ec1`／`0x445099`）；重制保留 `BattleSelectionCursor` 说明条里的名字（`run_battle_scene_runtime_tests` 断言它），没有另加屏幕字幕；要对齐就把说明条的名字移到 `caption_label` 并改那两条断言。
- 魔法／绝技选单窗在 `0x78`→`0x79` 时是否关闭未读（provisional）；替换路线：读 `0x444e58`（`0x78`）。
- 道具使用的原版目标态没有定位（provisional）；替换路线：从行动环道具项的状态转移（`0x63..0x72` 段）读起。
- 浏览态 `0x443e0e` 画移动范围的条件没有读。
- 玩家选目标时射程红格与脚印黄／青绿格的叠画与两层各自的计数器见 [范围格包](original_range_cells.md)。
- 施法引导：planeEffect2 的数值取自 PROCESS.DEF 的排列（planeObject40 = 43 之后），本地无该文件，横幅残影低于桶 0x32 按此推定；桶 0x17 阴影与同桶 23 的单位先后（单位第二遍提交、画在阴影之上）重制未建模，重制阴影盖住全部单位。
- 施法引导：法术（kind 1）读 `0x4c1408 = 0` 后的交叉淡化尾段（16 call，级 16→9）与子状态 5／6 未播，绝技读 `0x4c1408` 的第 11 个停留 call 重制少画 1 call；归 `cast-lead-phase`。
- 施法对象自身模式在子状态 1 是否带 `0x80000000`（挂桶头）未逐条核对；带则局部图残影会排到桶头、画在面板之下。

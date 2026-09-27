# 剧情脚本的镜头：居中缓动、走路跟随与 actScrollBG 步进

> evidence: static-derived; resource-derived: 脚本 token 与参数; provisional: 16 ms 设计值与 19.4 ms 实测的取舍（R24 负责人决定） · status: live · functions: 0x42dc50, 0x43bf30, 0x43c140, 0x44fcf0, 0x44fd90, 0x450840, 0x453b90, 0x45e80d · tools: hsltools/data/story_corpus.py · updated: 2026-09-24

2026-09-24，lane R25。矩阵「Camera curve」行此前只有「离散候选 anchor／runtime-measured 静帧／provisional」，本包回答任务书的问题——**镜头曲线能不能用静态／资源推导替代 runtime 观察**：镜头在每个 tick 走到哪里可以从原指令读出（本包），每个 tick 多长（墙钟）由 lane R24 量出（16 ms 设计值／19.4 ms 本机实测），两者相乘即秒数（末节）。以下全部为只读反汇编／反编译（`hsl01.exe` sha256 `f0b5f835…`），未做有界执行，也未开原作。

## 三条镜头入口

| 入口 | 谁调用 | 读法 |
| --- | --- | --- |
| `0x43bf30(obj, flag)` 居中缓动 | 剧情 VM `0x450840` 的 actScrollBGToPos／ToObject 阶段（case 0x13／0x14，经伪对象 `0x4c3860`）；脚本行走 `0x453b90` 状态 0x32 sub 0／1（`0x453d44 cmp [ebx+0x50], 0` → 仅 **Wait 变体**，`0x453d4b call 0x43bf30`）；经验结算 `0x442720`、共用施法序列 `0x442a90`（旧稿误称「玩家过程」，lane R7-CAMX 更正）、玩家对象过程 `0x443330` 与 AI 过程 `0x43ede0` 的对准（全部 51 个调用点见 [镜头包 §1](../runtime_observations/camera_panel_motion/README.md)） | 目标 = 对象像素 (`+4`,`+8`) − (0x140, 0xc0)（`0x43bf71`／`0x43bf76`：把对象放在 640×384 地图视口正中），夹到 `[0, *0x4c0958]`／`[0, *0x4c095c]`；`flag & 0x7fffffff != 0` 时 `0x46be92` 直接落位。否则每 tick：步长 `0x20`（`0x43bffa`），`*0x4c1b00 & 0x4000000`（剧情阶段位）时 `0x10`（`0x43bfff`／`0x43c007`），`*0x4c6390 & 0x600` 或 `*0x4c1d78`（快进）再 `+0xc`（`0x43c022`）；`0x45e80d(cur, target, tol 4, step, &next)`（`0x43c030 push 4`）→ `0x42dc50(next − cur)` 累计滚动请求（`0x43c064`／`0x43c091`）；到位返回 1 并清 `+0x80` 的 0x8000 锁 |
| `0x43c140(tx, ty, speed, &state)` 定速滚动 | actScrollBGToPosSpeed（case 0x4b） | 同一目标换算与夹取，`0x45e80d(..., tol 1, step = speed)`；到位 `0x46be92` 落位返回 1 |
| `0x42dc50(dx, dy)` 滚动请求累计 | 上两者与走路跟随 | 只加到 `0x4c1b98`／`0x4c1b9c`，不直接写镜头 `0x4c091c`／`0x4c0920`（[机制审计 §3](original_mechanics_audit.md) 52 组完整返回）；主循环 `0x42d8a8..0x42d8b5` 每帧把累计量交给引擎 `0x46bede` 并清零 |

**步进函数 `0x45e80d(cx, cy, tx, ty, tol, step, &nx, &ny)`**（曲线形状本身）：`|tx−cx| <= tol && |ty−cy| <= tol` → 到位（返回 1，next = target）；否则**逐轴** `delta = clamp((t − c) >> 1, −step, +step)`，即每 tick 走剩余距离的一半、上限 `step` 像素——远处线性 `step`／tick，近处指数缓出，最后一步由 `tol` 吞掉。剧情阶段的居中缓动因此是「16 px／tick 直到剩余 < 32 px，然后 16→8→4→2，剩 ≤4 时落位」；两轴独立，斜向目标不是直线而是先对角后单轴。

## 剧情 VM 的 token（`0x450840`，resource-derived 参数）

| token（ACTION.H） | opcode 分派 | 阶段 |
| --- | --- | --- |
| `actScrollBGToPos x y`（19） | case 0x13：`+0x8c = 0x130000`，存 x／y | 阶段 0：`*0x4c3864/*0x4c3868 = (v & ~0x1f) + 0x10`（格心），清 `*0x4c38e0`；阶段 1：每 tick `0x43bf30(0x4c3860, 0)`，返回非零才前进 |
| `actScrollBGToObject code serial`（20） | case 0x14：存 code／serial | 阶段 0：`0x44fad0` 找对象，取其像素进 `+0x9c/+0xa0`，转入 0x13 的阶段 |
| `actScrollBGToPosSpeed x y speed`（75） | case 0x4b：多存 speed | 阶段 0 同 0x13；阶段 1：`0x43c140(*0x4c3864, *0x4c3868, speed, 0x4c38e0)` |
| `actWalk*`（2–7）／`actWalkDisp*` | case 2..7：`0x44fcf0`（绝对格）／`0x44fd90`（**Disp = 相对当前像素的位移**，不是「显示」）把目的格心写进对象 `+0x4a/+0x48`，速度写 `+0x98`，Wait 变体把 VM 指针写 `+0x50` | 走路本体在 `0x453b90` 状态 0x32（下节） |

脚本语料（`content/imported/hsl/story_corpus/scripts/`，resource-derived）：actScrollBGToPos 出现于 56 个脚本、actScrollBGToObject 22、actScrollBGToPosSpeed 18、actScrollBGToRandomPos 1（STORY037，未读）、actWalkDisp／DispWait 34／33。**STORY051（第一战开场）没有任何 actScrollBG token，只有 `actWalkDispWait SID_PLAYER0 1 0 -96 2`**——第一战的镜头曲线全部来自下节的走路跟随。

## 脚本行走的镜头跟随（`0x453b90` 状态 0x32）

| sub | 读法 |
| --- | --- |
| 0 | `+0x50 != 0`（Wait 变体）→ 先 `0x43bf30(actor, 0)` 把镜头缓动到以演员为中心（上节曲线），到位才算路径 `0x4111d0(actor, dest, 0x12, 0xc)`；非 Wait 变体跳过居中 |
| 1 | 同样先居中（`0x453de6`），再取形态帧 |
| 2 | 速度换算（跳转表 `0x4543d8`）：speed 1 → 1 px／tick、帧延迟 6；2／3 → 2 px／tick、延迟 4；0／4／其他 → 4 px／tick、延迟 2；8 → 8 px／tick、延迟 1；`+0x9e = 0x20 / 步长` = 每格 tick 数（`0x453eb8`） |
| 3／6 | 每 tick 演员亚像素偏移 ±步长；**Wait 变体且演员越过屏内边界 `*0x4c0964`／`*0x4c096c` 时 `0x42dc50(0, ±步长)`（`0x454039`）**——镜头以与演员相同的 px／tick 跟着走；非 Wait 变体镜头不动 |

对第一战开场这意味着（static-derived 读法，未原执行）：雷歐納德 的 `actWalkDispWait(…, 0, −96, 2)` 先让镜头按 16 px／tick 上限＋半程缓出居中到他身上，再以 2 px／tick 向北走 3 格（48 tick），镜头只在他要越过上边界 `*0x4c096c` 时同步上移 2 px／tick。

## 与重制的对照及边界

| 重制现状（[表现合同](../../architecture/PRESENTATION.md)） | 原读法 | 差异等级 |
| --- | --- | --- |
| scroll token 0.6 s tween | 逐轴 `min(step, 剩余/2)`，剩余 ≤ 4 px 落位；step 16（剧情）／32／+12 快进 | 曲线形状 static-derived 已知；秒数 provisional（需 tick 周期） |
| `actWalkDispWait` 160 px／s | speed 参数 → 1／2／4／8 px／tick，每格 32／16／8／4 tick | 同上 |
| 镜头在 token 前居中 | 只有 Wait 变体先居中；走路时镜头只在越过边界时同步 | 重制：Wait 变体（`actWalkWait`／`actWalkDispWait`／`actWalkPrevInsertObjectWait`）走路时按同一组边界逐 tick 跟随（R7-CAM）；开走前仍对所有变体瞬切到演员（原版只有 Wait 变体先缓动居中） |
| 位置 token 曾读作视口左上角（STORY006 `actScrollBGToPos,1024,224` 让入场四人站在视口最上沿，用户实玩「看不到人」） | case 0x13／0x4b 先取格心 `(v & ~0x1f) + 0x10`，case 0x61（actSetBGToPos）用原值，都经 `0x43bf30` 把点放在视口 (320,192) | lane R5-L4 已改：`OpeningCinematics.script_position_camera_centre`（重制 640×480 视口的中心＝点＋(0,48)）；普查 `run_opening_camera_tests.gd`：82 次「位置镜头后插入的演员」旧读法仅 12 次完整在画面内，新读法 81 次，余下 WINFAIL041 event 0 的水怪在原版读法下也只露脚——重制对插入演员加「拉进画面」（remake-invented） |
| 对象 token 与战斗对准按单位居中（画面正中 (320,240)） | `0x43bf30` 对任何对象都把点放在 (320,192)；case 0x14（actScrollBGToObject）取对象点后转 0x13 阶段 0 取格心再缓动，case 0x15（actSetBGToObject）`0x43bf30(对象, 1)` 用原始点落位；录屏 212.45 s AI 回合被对准的法师站在 (320,192) | lane R7-CAMX 已改：`BattleCameraController.focus_centre`（点＋(0,48)）供战斗对准、结算对准、位置／对象 token、对白与走前瞬切共用 |
| actScrollBGToPosSpeed 按「距离÷速度」直线滑动 | case 0x4b 阶段 1 → `0x43c140`：同一换算与夹取，`0x45e80d(…, tol 1, step = speed)`，到位 `0x46be92` 落位 | lane R7-CAMX 已改：`scroll_to(目标, speed, 1)` |
| 第一战「离散候选 anchor」 | STORY051 无 scroll token；锚点即 雷歐納德 的居中目标 (x−320, y−192) 夹取后的值 | 静帧锚点可由本读法推出，不再需要从录像猜 |

**秒数的换算**：lane R24 已把 tick 周期量成 runtime-measured（[原版 tick 率](../runtime_observations/original_tick_rate/README.md)：设计值 16 ms／tick＝62.5 tick／s，本机 Wine 实测 19.4 ms；负责人决定重制以 16 ms 为目标）。按 16 ms：剧情居中缓动上限 16 px／tick＝**1000 px／s**（近处半程缓出，32 px 内 16→8→4→2 共约 5 tick≈80 ms）；脚本行走 speed 2＝2 px／tick＝**125 px／s**（一格 16 tick＝0.256 s），speed 4＝250 px／s，speed 8＝500 px／s，speed 1＝62.5 px／s；快进时居中步长 28 px／tick。lane R26 已把表现线换成上述派生值：`OpeningCinematics.camera_scroll_seconds` 逐 tick 模拟 `0x45e80d`（步进 16、容差 4），`BattleOpeningCoordinator.walk_pixels_per_tick` 用 `0x4543d8` 表（[tick 映射表](../runtime_observations/original_tick_rate/tick_mapping.md) 行 27／28）；`0x46bede` 引擎侧只做加法与地图范围夹取（[tick 计数 §3](original_tick_counts.md)）。**唯一仍 provisional 的**是本机 19.4 ms 与 16 ms 设计值之间的取舍——那是 R24 已记录的负责人决定，不是本包的读法问题。**不在本读法内**：（`0x46bede` 的应用方式与边界全局 `0x4c0960..0x4c096c` 的数值、写入者已由 lane R7-CAM 读出：一次加完再夹取；常量 320／240／地图宽−320／地图高−240——见[走路跟随](../runtime_observations/camera_panel_motion/README.md#走路跟随镜头与走路的人同步走不滑向终点lane-r7-cam2026-09-25)）；`*0x4c1b1c` 对 `0x43bf30` 负 flag 的语义；actScrollBGToRandomPos；非剧情阶段（战斗中玩家光标）的镜头路径。实现不支持的结论：当前 0.6 s／160 px／s 与原版秒数一致。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/runtime/opening/OpeningStoryObjects.gd` timing：actWalk speed → 1／2／2／4／8 px per tick, 0x4543d8; Wait walks request the walker's step for the camera, 0x453fbd..0x454039

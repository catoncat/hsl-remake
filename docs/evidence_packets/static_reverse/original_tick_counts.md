# 以 tick 计的原版时长：数字寿命、章节标题、边缘滚动、脚本行走速度（R26 静态读法）

> evidence: static-derived: object-process and STORY VM state machines read from hsl01.exe; runtime-measured: 2026-09-24 user recording of the 棄卒 title card (§2); provisional: rows marked 未读 · status: live · functions: 0x401060, 0x401c20, 0x4038a0, 0x406d20, 0x406eb0, 0x408580, 0x42c3f0, 0x42d280, 0x42dc50, 0x42dc80, 0x43e2a0, 0x43e4a0, 0x43e570, 0x4423c0, 0x44fcf0, 0x451818, 0x452102, 0x452f32, 0x453111, 0x45e307, 0x45e525, 0x45e91e, 0x45f5f7, 0x45f7cb, 0x4607f9, 0x460989, 0x46098f, 0x4609c0, 0x4609f1, 0x460a06, 0x461479, 0x461982, 0x462154, 0x463eeb, 0x464c22, 0x4699fd, 0x46b691, 0x46bede · tools: hsl_exe_decompile.py · updated: 2026-09-26

lane R26-tick-timing（2026-09-23）。[原版 tick 率](../runtime_observations/original_tick_rate/README.md)给出单位（设计 16 ms／tick，62.5 tick/s）；[映射表](../runtime_observations/original_tick_rate/tick_mapping.md) B 类要求"先读计数再换算"。本包记录本 lane 用 `tools/hsl_exe_decompile.py`（r2ghidra）与 r2 反汇编读出的计数，重制侧由 `game/battle/runtime/CombatPresentationTiming.gd`（数字）与 `game/battle/runtime/opening/OpeningCinematics.gd`（标题）、`game/battle/runtime/BattleCameraController.gd`／`game/world/WorldMapRuntime.gd`（滚动）消费。EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。所有计数以主循环 tick 为单位；秒 = tick × 16 ms（设计值），本机体验 × 19.4 ms。

## 1. `defProcShowNumber`（`0x408580`）：地图数字的寿命与上浮

对象由 `0x4084e0(x, y, value, wait_ref, kind, hold)` 生成（对象 0xb1 `obj_ShowNumber`，`0x45e307` 创建时置 `+0x80 |= 0xb0000000`，含 0x20000000「初始化中」位；`+0xa8 = hold`、`+0xac = wait_ref`、`+0x8e = kind`）。过程每 tick 收到 `+0x80` 作为 flags（`0x45f5f7` 调 `[0x4a19bc[+0x64]](obj, obj+0x80)`）：

| 阶段 | 读法 | tick |
| --- | --- | --- |
| 保持（hold） | flags 含 0x20000000：`+0xa8--`，>0 则返回；≤0 时清该位、`+0x28 = 16`，kind 0 置 `+0x90 = 0x20005`（低字倒数 5、高字重载 2）、`+0x94 = 0x10000`、`+0x98 = 0xa000a`（10／10）、`+0x9c = 0x10006`；其他 kind 置 `+0x90 = 0x20010`（倒数 16、重载 2） | `hold`（至少 1） |
| kind 1–6（EXP／回复／MP／$／MISS／LEVEL UP）显示 | 每 tick `word[+0x90]--`；归零时重载 `word[+0x92]`（2）并 `+0x28--`；`+0x28 < 9` 时首次把 `wait_ref+0x8c` 加一（放行等待它的动画）并清 `+0xac`；`+0x28 < 1` 时 `0x45e3ed` 删除对象 | 16 ＋ 15×2 ＝ **46**；放行在第 **32** tick |
| kind 0（红色伤害数字，弹跳） | `+0x96` 为弹跳中的位数索引，每 10 tick（`+0x98`／`+0x9a`）前进一位，越过位数后归 0；两索引都归零后 `+0x90 = 0x10012`（倒数 18、重载 1），之后每 tick `+0x28--`，从 16 数到 0 | 10×位数 ＋ 18 ＋ 16：1 位 **44**、2 位 **54**、3 位 **64** |
| 上浮 | 函数末尾 `+0x80 ^= 0x10000`；flags 含 0x10000 的 tick `+8`（y）减 1 | 每 2 tick 上浮 1 px（46 tick ≈ 23 px） |

调用侧的 hold：HP／MP 回复（[original_resource_recovery](original_resource_recovery.md)）HP 数字 hold 0、MP 数字 hold 40。因此回合尾部 HP 数字 0–46 tick、MP 数字 40–86 tick。

重制：`CombatPresentationTiming.SHOW_NUMBER_TICKS = 46`、`SHOW_NUMBER_RELEASE_TICKS = 32`、`DAMAGE_NUMBER_BASE_TICKS = 34`＋`DAMAGE_NUMBER_DIGIT_TICKS = 10`／位（lane DIGITS 由 44 更正为 kind 0 实际寿命）、`SHOW_NUMBER_RISE_PX_PER_TICK = 0.5`；`BattleTurnEndCue` 以 40 tick 间隔换事件、末事件停留 46 tick；`BattlePresentation`／`MagicImpactPresentation` 的浮字按 kind 取寿命。kind 0 的弹跳绘制已由 lane R7-POSE 读出（逐位揭示、2×／1.5×／4× 闪光、不上浮，寿命 10×位数＋34，[地图姿势与飘字包 §3](../runtime_observations/map_pose_floaters/README.md#3-红色伤害数字0x408580-kind-0)），地图、特写与法术的伤害数字由 `DamageNumberFloater` 画，回复／MP／MISS 由 `ResultNumberFloater` 按 kind 2／3／5 画（lane DIGITS）。

## 2. `actShowSectionName`（opcode 12）：章节标题的进出与停留

处理器 `0x451818` 装载 `SHAPE\LEVELSEC.SHP`、记下章节码并把 VM 状态写成 opcode 12 等待（`+0x8c`），之后每 tick 由 `0x452f32` 的 8 段子状态推进（`+0x8c` 低字）：

| 子状态 | 读法 | tick |
| --- | --- | --- |
| 0 | `+0x9e = +0x9a = 0`、`+0xa0 = 320`、`+0xa4 = 0x30003`（倒数 3／重载 3）、缩放 `[0x4c1d34] = 0x80000`（8.0） | 1 |
| 1 | 每 tick `+0xa4--`；归零时先重载 3，再查 `+0x9e ≥ 16`：是则进 2，否则 `+0x9e++`（底图混合层级 0→16，第 48 tick 到 16） | **51** |
| 2 | 每 tick 缩放 −0x2000（0.125）；≤ 0x10000 时夹到 1.0 并进 3 | 56 |
| 3 | 同子 1，作用于 `+0x9a`（章节名层级，第 48 tick 到 16） | **51** |
| 4 | 每 tick `+0xa0--`；归零或按键（`[0x4c6390] & 0x600010`）／点击（`[0x4c6398] & 0x10002`）进入下一段——按键的那个 tick 本身算一个停留 tick | 1–320（可跳过） |
| 5 | 重载时先查 `+0x9a == 0`：是则进 6，否则 `+0x9a--`（第 48 tick 到 0） | **51** |
| 6 | 每 tick 缩放 +0x2000（封顶 8.0），同时按子 5 的方式倒数 `+0x9e`；重载时 `+0x9e == 0` 即经 `0x452fea` 进 7——缩放此时只到 1.0 + 51 × 0.125 = **7.375**，不到 8.0 | **51** |
| 7 | `+0x8c = 0`，VM 继续 | 1 |

合计：不跳过 **582 tick ≈ 9.3 s**；停留首 tick 即按键 **263 tick ≈ 4.2 s**（停留最少 1 tick）。进（0–3）＝159 tick、出（5–7）＝103 tick。

**更正（lane R7-TITLE，2026-09-25，static-derived）**：此前按"每 3 tick 加到 16＝48 tick"估算，写成子 1／3／5 各 48、子 6 为 56（缩放）／48（层级）、合计 577（进 153、出 104、跳过 257）。r2 逐条核汇编 `0x452f8d`（子 1）／`0x452ff6`（子 3）／`0x45307b`（子 5）／`0x4530b3`（子 6）：计数重载时**先查 ≥16／==0 再加减**，第 16 次加减之后还要再等一次重载（3 tick）才换段，故每个层级段 51 tick；子 6 由层级归零结束，不等缩放回到 8.0（`0x4530c9` 的封顶在 51 tick 内不会触发）。

**两层的画法（lane R7-TITLE，static-derived）**：每 tick 状态推进后（`0x453111` 起）先画底图、再画章节名，两者同一绘制记录（`0x461479`），位置都是镜头左上 ＋ (0x140, 0xf0)＝视口 (320,240)，由各自 SHP 原点对齐。
- 底图（`+0x9e ≠ 0`）：层 0x32，形状 `+0x9c`（`SHAPE\LEVELSEC.SHP`，640×208、原点 (320,104)，中间灰带 0x73ae、上下渐黑）；模式 `0x2000000`，层级 < 16 时 `0x22000000`，缩放 ≠ 1.0 时再或 `0x8000000`。记录 `+0x20 = 0x10000`（x 缩放 1.0）、`+0x24 = [0x4c1d34]`（y 缩放）——`0x461479` 把两者抄到显示项 `+0x1c`／`+0x20`，`0x461982` 用 `+0x1c` 乘 x 跨度、`+0x20` 乘 y 跨度，所以**只纵向拉伸**。`0x46b691` 按位 25–27 查表 `0x46b6b1`：`0x2000000` → 像素种类 10（`0x463eeb`）、`0xa000000` → 种类 11（`0x464c22`，缩放版）。种类 10 的内核是 RGB565 逐通道**饱和减法** `dst − src`（借位检测后与掩码表 `0x4bdbec`）；模式含 `0x20000000` 时 src 先经 `[0x4bfbf0 + 层级×4]` 的层级表缩放，即 `dst − src × 层级/16`。因此 8× 纵向拉伸时灰带盖满全屏、把整个画面压暗，缩回 1× 后成为屏幕 y 170–310 的暗带（形状行 34–174 非黑；核心灰 64–144 → 屏幕 200–280，上下各 30 px 渐变）。
- 章节名（`+0x9a ≠ 0`）：层 0x33，形状 `+0x98`（本关 `SHAPE01\WORDnnn.SHP`；PAK 内全部 46 个 WORD 形状原点都是 (宽÷2, 高÷2) 下取整，resource-derived）；层级 16 时模式 0（普通不透明绘制），以下 `0x20000000` → 表 `0x46b691` 种类 4（`0x4699fd`，`src×层级/16 ＋ dst×(16−层级)/16` 交叉淡化）；不缩放（x、y 字段沿用底图那次的栈记录，但模式无 `0x8000000`）。

**录屏对照（runtime-measured，2026-09-24 录屏，游戏区 = 原片 (112,140) 起 1280×960 ÷ 2）**：第一战《棄卒》标题卡 27.62 s 起全屏均匀变暗（平均亮度 84 → 8，28.36 s 到底），28.72 s 起暗区从上下边缘收拢，29.36 s 定格为 y≈172–308 的横带（核心 196–284 最暗，与形状推算的 170–310／200–280 一致）；章节名 29.36 → 30.19 s 淡入、1× 居中（宽约 158 px，WORD051 为 161 px），**停留 0 tick 即被跳过**（录屏者按住／点击），30.19 → 31.07 s 淡出；31.07 s 起暗带张开并淡出，31.91 s 画面复原；32.01 s 胜负面板开始淡入（与重制标题结束后 5 个非等待 token＋面板溶入一致）。全程 27.62–31.91 s ＝ 4.29 s，与 263 tick 同量级（该录屏的实际 tick 长未单独量，不用于区分 257／263）。帧在仓库外 `ignored/title/`，不入库。

重制（`BattleOpeningCoordinator.title_seconds`／`OpeningCinematics`，lane R7-TITLE 起）：`OpeningCinematics.section_title_step` 逐 tick 复现子状态 0–7（含 3 tick 计数与"先查后加减"），`_fade_title` 每过一个原版 tick 走一步；`build_section_title_view` 建两层——`SectionTitleBand`（LEVELSEC，`CanvasItemMaterial.BLEND_MODE_SUB`，按原点 (320,104) 放在 (320,240)，`scale = (1, zoom)`，`modulate.a = 层级/16`，即 `dst − src·层级/16`）与 `SectionTitleName`（WORD，1×，`modulate.a = 层级/16`）；层级 0 的层不画。协调器等待 582 tick（`SECTION_TITLE_IN_TICKS 159`＋`HOLD 320`＋`OUT 103`）；停留期间任意键或任意鼠标键（`skip_section_title`，原版按键掩码 `0x600010`／点击掩码 `0x10002` 的重制读法＝任意键／任意键钮）交给下一个停留 tick，等待改为当前 tick 余量＋1＋103，最短 263 tick；进段与出段的输入忽略（只在子状态 4 收输入）。跳过记入 `story_records`（`section_title_skip`：trigger、held_ticks＝含收键那一 tick 的停留数）。标题结束后照旧逐 tick 走完随后的非等待 token 再由 `BattleWinFailBoard` 溶入胜负面板。定向测试 `tests/run_section_title_tests.gd`（逐 tick 子状态、两层节点、全部注册场景的标题卡资源与唯一处理路径）。未对照：RGB565 饱和减法与 Godot 线性减法混合的逐像素差异；原版一次按住的键也会立即结束停留（掩码是当前按键状态），重制只认按下事件。

## 3. 地图边缘滚动：每 tick ±12 px

`0x43e570`（地图光标过程，每 tick 一次）调 `0x43e4a0`：光标 x < 10 或按左键位 → `0x42dc50(−12, 0)`；x > 630 → `(+12, 0)`；y < 10／> 470 → `(0, ∓12)`；`[0x4c6390] & 0x600`（修饰键）时循环两遍即 ±24。帧体 `0x42d600` 开头 `0x42dc80` 清零请求、结尾 `0x46bede(dx, dy)` 把累计请求加到镜头 `[0x4c091c]`／`[0x4c0920]` 并夹到地图范围。大地图经 `0x4271f1 → jmp 0x43e4a0` 复用同一函数。剧情脚本的镜头（actScrollBG*、走路跟随）走另一条 `0x43bf30`／`0x45e80d` 缓动路径，见 [original_script_camera_scroll](original_script_camera_scroll.md)（lane R25）。

因此边缘滚动 = **12 px/tick = 750 px/s**（修饰键 1500 px/s）。重制 `BattleCameraController.EDGE_SCROLL_PIXELS_PER_TICK = 12`、`WorldMapRuntime` 同值；键盘平移与鼠标边缘共用（原版键位与边缘同一请求）。修饰键加速未接（重制无对应输入）。

## 4. 脚本 `actWalk` 系列：速度参数存入角色 `+0x98`

VM 处理器（opcode 2–7，`0x4508a8` 等）把 `[code][serial][x][y][speed]` 交给 `0x44fcf0`：目标格中心化（`& ~31 + 16`），`+0x4a`／`+0x48` 目标，`word[+0x98] = speed`，`+0x8c = 0x320000`（行走状态 0x32），`+0x50` = 删除／Wait 标志。消费在 `0x453b90` 状态 0x32 sub 2 的跳转表 `0x4543d8`（lane R25 读出，[original_script_camera_scroll](original_script_camera_scroll.md)）：speed 1 → 1 px/tick、2／3 → 2、0／4／其他 → 4、8 → 8——与 [tick 率包](../runtime_observations/original_tick_rate/README.md) 实测玩家 4 px/tick 一致。重制 `BattleOpeningCoordinator.walk_pixels_per_tick(speed)` 用同一张表，速度 × 62.5 px/s。`actMoveDispWait`（opcode 55，状态 case 0x37）的 speed 语义未读，重制仍按 px/tick 读（provisional）。

## 5. `actDarkScreen`（opcode 48）：不等待，交给对象 700

`0x452102` 调 `0x43e2a0(0)`：`0x45e307(0, 0, 700, 0)` 插入 `obj_ScreenDarker`（OBJ-ALL.H 700）并置 `+0x90 = 0`，VM 立即继续（无等待状态）。渐暗节拍在对象 700 的过程里，**未读**——重制 `OpeningCinematics.DARK_SCREEN_FADE_SECONDS` 保持 provisional，替换证据是该过程每 tick 的亮度步进。

## 6. 普攻切入的守方对象 `defProcAnimalDefense`（`0x4038a0`，slot 23）：受击停留（lane P3）

攻击序列 `0x4423c0` state 0 用 `0x406d20(actor, 0, parent)` 插入攻方对象 0x9a（过程 `0x401c20`），攻方 aniOver 进 phase 101、等 flash 对象（`+0x88`）结束后给 parent `+0x8c` 加一并自删；state 2 再用 `0x406eb0(target, kind, damage, hit%, extra, parent)` 插入守方对象 0x9b（过程 `0x4038a0`；`+0xa4 = kind`：普攻 0、绝技 2；`+0xa6 = 命中率`，目标 `0x446b00` no_attack 位为真时写 100；`+0xa0 = 伤害`）。守方对象自己的钟（phase 字 `+0x8c`，字节表 `0x404e80` → 跳表 `0x404e5c`）：

| phase | 读法 | tick |
| --- | --- | --- |
| 100（init） | `0x4038fe` 置 `0x640000`；kind ≠ 2 时 case 100 直接落回 `+0x8c = 0` | 1 |
| 0 | `0x403ef8`：`0x4c1418 = rand(100)`，计数 `+0x84 = 0x1e`（`0x4038b4` 装入 ebx） | 1 |
| 1 | `0x403f13` 每 tick `+0x84--`，归零时重装 `0x28`（`0x403f29`）并比较 `0x4c1418 < +0xa6`；**命中**（`0x403f4f..`）：伤害滚动、`+0x30 += 姿态数 − 1`（`0x404015`，受击帧）、击退向量 `+0x9c = 0xe0000`／`+0x94 = 0x10000`（尾部 `0x45eb9d` 积分、`0x45eb89` 每 tick 衰减 1.0，共 14 tick 105 px）、`0x436490(+0xa0, 3, 0)` 刷身份栏、按武器类 `0x4c6f60` 放 0x194–0x199 受击音、`0x401310` 插入击中闪光 → phase 2；**落空**（`0x4041ea..0x404247`）：`+0x96 = x ∓ 0x96`（150 px）、`0x4c6f64 = 3`（残影计数）、`0x409760` 放该角色模板 `+0xc` 的闪避音 → phase 5 | **30**（中立姿态可见 = 1 ＋ 1 ＋ 30 = **32** tick） |
| 2（命中） | `0x40424c` 每 tick `+0x84--`；≤0 时 `0x4084e0(x, y+200, 伤害, 本对象, kind 0, hold 0)` 生成红色伤害数字（返回 0 直接 phase 4） → phase 3 | **40** |
| 3（命中） | 无 handler（字节表 idx 8 → 公共尾部）：等数字对象在 `+0x28 < 9` 时给 `wait_ref+0x8c` 加一 | kind 0 数字：hold 1 ＋ 10×位数 ＋ 18 ＋ 8 = **27 ＋ 10×位数**（1 位 37、2 位 47） |
| 4 | `0x4042a5` `+0x84--`，<1 → `0x650000`（phase 101）；命中路径计数已为 0 → 1 tick；落空路径计数仍是 40 → 40 tick | 1（命中）／**40**（落空） |
| 5（落空） | `0x4042c9` `0x45e91e(x, y, +0x96, +0x94, 0x24, 2, …)`：步长 = min(36, 距离/4)，最小 2，距离 <2 时返回 0 → phase 6；每步残影计数归零时 `0x401220` 留残影 | 150 px：14 步 ＋ 到达 1 = **15** |
| 6（落空） | `0x404350` → phase 4 | 1 |
| 101 | 子状态 0（`0x404b23`）：有续击（对象 `+0x80` 位 0x200，`0x403860` 为反击／追加击置位）且目标 HP ≥ 1 → 直接子 2、`0x4c1404 \|= 1`、`0x42c3f0(0)`（无过渡）；否则 `0x42dc90(1)` = `0x46098f(1)` 请求变暗 → 子 1；子 1（`0x404ada`）等 `0x460989()`（`[0x4bbb5a]` 过渡挂起标志）归零后 `0x42c3f0(0)` 退出切入、`0x42dca0(1)` = `0x4609c0(1)` 请求变亮、`+0x30 = 0xffff` 隐藏 → 子 2；子 2 等挂起归零后 parent `+0x8c++`、自删 | **变暗 16 ＋ 变亮 16**（lane P4 读法见下）|

合计（守方对象生成起）：中立 32 tick → 命中：受击姿态停留 40 ＋（27 ＋ 10×位数）＋ 1 = **68 ＋ 10×位数**（1 位 78、2 位 88、3 位 98）；落空：15 ＋ 1 ＋ 40 = **56**；之后进屏幕过渡。原版**没有**"恢复中立姿态"一段：受击帧持续到过渡开始、对象隐藏。±1 tick：数字对象与守方对象在同一 tick 内的处理顺序未读。R30 之前的 77 tick（录像 1.5 s ÷ 19.4 ms）与 1 位伤害的 78 tick 相符。

**屏幕过渡的 tick 长度（lane P4，2026-09-26）**：`0x46098f(rate)` 置挂起 `[0x4bbb5a] = 1`（方向 +1）、未挂起时层级 `[0x4bbb56] = 1`、计数字 `[0x4bbb5e] = rate:rate`；`0x4609c0(rate)` 置挂起 −1、未挂起时层级 16。帧体 `0x42d600` 每 tick 调 `0x460a06`：层级 ≠ 0 时以模式 `0x20000000`、层级 `[0x4bbb56]`、最高绘制层 `[0x4bfc4c]` 画全屏形状 `[0x4bbb4e]`（`0x45f7cb` 合成的屏幕大小形状，768 行全指向 `0x4a4210`——.data 中初始化为零的行 ＝ RGB565 黑；运行期是否改写该行未查），再让计数字减一：归零时重载高字并 `层级 += 方向`；层级 ≤ 0 → `0x4609f1`（层级 0、挂起 0）；层级 > 16 → 层级 16、挂起 0。模式 `0x20000000` 的像素例程（`0x4699fd`，跳表 `0x46211c` 项 4）为 `out = src×表[层级] ＋ dst×表[16−层级]`，16 ＝ 全 src。因此 `0x46098f(1)`：画层级 1…16 各 1 tick 后挂起清零 ＝ **16 tick 变黑**（受击姿态在其下保持）；`0x4609c0(1)`：画 16…1 ＝ **16 tick 从黑变亮**（此时 `0x42c3f0(0)` 已清切入标志，帧体 `0x42d280` 重新画地图；守方 `+0x30 = 0xffff`）。守方对象与帧体在同一 tick 的先后未读（±1 tick）。有续击（反击／追加击待演、目标存活）的镜头两段都不播，phase 101 约 2 tick 内交给下一镜头。

重制（`CombatPresentationTiming`）：`TARGET_PAUSE_TICKS = 32`，`hurt_hold_ticks(hit, damage)` = 命中 `HIT_TO_NUMBER_TICKS 40 ＋ damage_number_release_ticks ＋ 1`／落空 `MISS_SLIDE_TICKS 15 ＋ 1 ＋ MISS_HOLD_TICKS 40`；`RECOVERY_TICKS = 16`（变黑期间受击姿态保持，static-derived，取代此前 provisional 的 20）、`CLOSING_LIGHTEN_TICKS = 16`（地图上从黑变亮，切入内容已隐藏），只在交换的最后一镜或击杀镜（`closes_exchange`：`last_shot` 或 `defender_hp_after ≤ 0`）播放；`ordinary(actor, strike, first_shot, last_shot)` 返回 `opening／release／target／impact／recovery／darkened／complete`。`BattleCombatCutin` 不再回到中立姿态（受击帧保持到镜头结束）。此前的 15／77／20 是录像换算。击退 105 px／残影／闪避滑动 150 px 的位移未接（重制仍用 6／24 px 的 reaction 位移，provisional）。

## 7. 普攻切入的攻方开场（`0x401c20` phase 100）：24 tick 缩放 ＋ 32 tick 叠层，无放声

攻方对象 init（`0x401c20`，kind 0）置 phase `0x640000`。case 100（`0x4027ce..`）：

| 子状态 | 读法 | tick |
| --- | --- | --- |
| 0 | `+0x80` 位 0x200 清零（首击）：`+0x90 = 0x1000`（缩放 1/16）、`+0x28 = 0x10`、子 1；位 0x200 已置（反击／追加击的后续镜头）：只 `0x436490(+0xa0, 3, 0)` 生成身份栏文字，直接 phase 0 开始程序 | 1 |
| 1（缩放段） | `+0x90 < 0xd0001` 时以模式 `0xc000000` 在 (320,240) 画 `+0x86` 形状第 0x34 帧、缩放 `+0x90`，再 `+0x90 = 0x401060(+0x90)`：<0x4000 步 0x1000、<0x8000 步 0x2000、<0x10000 步 0x4000、<0x20000 步 0x6000、<0x30000 步 0x8000、<0x40000 步 0xa000、其余步 0xe000 | 0x1000 → 0xc4000 共 **24** 步 |
| 1（叠层段） | 首次 ≥ 0xd0001：`+0x90 = 0x120000`（18.0）、恢复帧 `+0x30 = +0xc8`、`0x436490(+0xa0, 3, 0)` 生成身份栏文字、`+0x94 = 0x20002`；之后每 tick 以模式 `0x28000000`、层级 `+0x28` 画；`+0x94` 每 2 tick 让 `+0x28` 减 1，16 → 0 | **32** |
| 2 | 等 `0x460989()` 归零（屏幕过渡挂起标志） | 未读 |

`0x436490` 是状态窗文字生成器（→ `0x434d10`，mode 3 = 切入身份栏），**不是放声**——[ANIMAL 程序包](animal_program_execution.md) ⑤ 的"放声"为误读；phase 100 内没有 `0x42c180` 调用。

**画法（lane P4，2026-09-26，static-derived）**：
- 被画的形状 `+0x86`：init 顶部（`0x401c89`）`+0x86 = word[+0x32]`，早于 `0x45e525(obj, 演员 shape, count, 2)` 把 `+0x30／+0x32` 改成演员形状——即 `0x45e307` 按对象类型装入的默认形状。OBJ-ALL 154 `obj_Animal_Attack` 的 `shape_resource` 为 `MAGIC\BALL001.SHP`（resource-derived，`battle*_seed.json` 对象表）：295×298、原点 (147,149) 的白心→黑边径向光球（已导入 `content/imported/hsl/chapter01/combat_animation/opening_ball.png`，manifest `opening`）。`0x4607f9(mode, x, y, shape, layer, level, zoomx, zoomy, …)` 把绘制记录排进显示表 `0x461479`（第 5 参 0x34 是绘制层，演员的公共尾部用 0x17；`[0x4bbbd4 + 层×4]` 链表），不是帧号。
- 模式位（`0x46b691` 显示表消费者）：位 25–26 非零走表 `0x46b6b1`：`0x4000000` → 像素例程种类 8（`0x462154`：`ax = src + dst`，异或检测各通道进位后 `or` 饱和掩码 `0x4bbbec`——**RGB565 饱和加法**），`0xc000000` = 加法 ＋ 缩放（种类 9 `0x462e8b`，同一加法内核的缩放变体）；位 25–26 为零走表 `0x46b691`：`0x20000000` → 种类 4（`0x4699fd`，层级交叉淡化，见 §6）、`0x28000000` → 种类 5（缩放 ＋ 交叉淡化）。
- 因此：缩放段 24 tick 是光球以加法混合从 1/16（18 px）长到 12.25×（3600 px，屏幕角落只到半径 22%，近白）盖满屏幕；叠层段 32 tick 是同一光球 18×（屏幕只到半径 15%）以层级 16→1 交叉淡化——**白屏淡出**，露出已恢复帧的攻方与刚生成的身份栏（原录像 `12_leonard_normal_attack/frame_001` 的泛白画面即此段）。缩放段之下：init 的 `0x42c3f0(1)` 置 `[0x4c1b20]`，帧体 `0x42d280` 据此跳过地图绘制、改 blit `[0x4c1e00]` 缓冲（行距 0x500 ＝ 640 px）；该缓冲的装入路径未追。~~缩放段之下是切入底图 BG051~~——**已被 runtime-measured 取代**（lane R6-P2，[镜头与面板动效 §5](../runtime_observations/camera_panel_motion/README.md#5-切入白光光球在地图之上放大)）：2026-09-24 录屏四次普攻切入（113.49–113.78、163.95–164.20、199.66–199.95、353.72–353.97 s）光球都从屏幕中心在**仍可见的战场地图**上长大，直到全白才换成特写；即 `0x4c1e00` 在缩放段装的是地图画面，不再支持「缩放段显示 BG051」的结论。身份栏底板在缩放段是否已画未读（文字在叠层切换时才生成）。

重制（`BattleCombatCutin._show_opening`，`CombatPresentationTiming.OPENING_*`）：交换的第一镜（`first_shot`，`BattlePresentation._show_strike` 按 `CombatSequence.strikes` 顺序传入；反击镜与追加击镜对应位 0x200 → 无开场）先播 24 tick 加法光球（`opening_zoom_ramp()` 复现 `0x401060` 的 24 个 16.16 缩放值，`BLEND_MODE_ADD`，攻方隐藏、身份栏隐藏、特写底图与底色隐藏——光球画在地图之上）再播 32 tick 18× 光球 alpha = 层级/16（`opening_overlay_level`），光球盖住整个 640×480 含身份栏；随后程序第一条指令。缩放段隐藏身份栏底板为 provisional。

## 边界

- 本包只给 tick 计数与状态机读法，不证明绘制内容（数字弹跳曲线）等价；切入开场的 `0xc000000`／`0x28000000`、过渡的 `0x20000000` 与章节标题的 `0x2000000`／`0x20000000` 已读到像素例程种类（饱和加法／饱和减法／16 级交叉淡化），像素级等价仍未对照。
- 未读（保留 provisional）：`mapobjFlash` 亮度步进（TYPE.H：`objsScore = level, objsHitPoint = delay`，字段尚未导出到 map_objects）、系统卷轴展开步进（`0x45e80d` 消费者）、击中闪光对象 `0x401310` 的寿命（攻方 phase 101 等 `+0x88` 归零）、施法对象 phase 102 子状态 4 的过渡／停留 cadence 与外部释放 `0x4c1408`（s_action 引导的其余 call 数已读，[ANIMAL 程序包 §8](animal_program_execution.md#8-施法引导程序m_actions_action的解释)）、对象 700 渐暗、攻方 phase 100 子 2 等的挂起标志由谁请求（普攻首镜时通常已为 0）、`0x4c1e00` 切入底图缓冲的装入路径。
- 反编译原文留在 `ignored/static/hsl01/decompiled/`，不入库。

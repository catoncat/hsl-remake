# 以 tick 计的原版时长：数字寿命、章节标题、边缘滚动、脚本行走速度

> evidence: static-derived: object-process and STORY VM state machines read from hsl01.exe; runtime-measured: 2026-09-24 recording of the 棄卒 title card (§2); provisional: rows marked 未读 · status: live · functions: 0x401060, 0x401370, 0x401710, 0x401c20, 0x402295, 0x40298a, 0x4038a0, 0x403d3d, 0x404ada, 0x404b23, 0x404f90, 0x4050a0, 0x4051d0, 0x406d20, 0x406eb0, 0x408580, 0x409610, 0x4104d0, 0x4111d0, 0x415910, 0x42c3d0, 0x42c3f0, 0x42d280, 0x42dc50, 0x42dc80, 0x42dc90, 0x42dca0, 0x43b4e0, 0x43e270, 0x43e2a0, 0x43e2d0, 0x43e4a0, 0x43e570, 0x4423c0, 0x446c40, 0x44fbd0, 0x44fcf0, 0x44fd90, 0x44ff50, 0x4501f0, 0x4502f0, 0x45136a, 0x451818, 0x452102, 0x452123, 0x452eac, 0x452f32, 0x453111, 0x453b90, 0x45e307, 0x45e3ed, 0x45e525, 0x45e5a6, 0x45e91e, 0x45f5f7, 0x45f7cb, 0x46067d, 0x4607f9, 0x460989, 0x46098f, 0x4609c0, 0x4609f1, 0x460a06, 0x460e9c, 0x460f26, 0x460fb0, 0x4611e3, 0x461479, 0x461982, 0x462154, 0x463eeb, 0x464c22, 0x4699fd, 0x46b691, 0x46b6c1, 0x46bede · tools: hsl_exe_decompile.py · updated: 2026-09-28

## 结论

- 原版以主循环 tick 计的演出计数已从对象过程与 STORY VM 状态机读出：地图数字 kind 1–6 寿命 46 tick（第 32 tick 放行），红色伤害数字 10×位数＋34；章节标题 582 tick（任意键最短 263）；边缘滚动 12 px/tick（按住任一 Shift 24）；脚本行走（含 actMoveDispWait）speed→1／2／4／8 px/tick；剧情压黑每 3 tick 一级、16 级（48 tick），actDarkScreen／actDeleteDarkScreen 都不等待；普攻守方中立 32 tick、命中停留 68＋10×位数、落空 56，屏幕过渡变暗／变亮各 16、之间无停留，收尾镜头在子 0 起第 33 tick 交接（有续击的镜头第 2 tick）；攻方开场 24 tick 缩放＋32 tick 叠层＋1 tick 查挂起（static-derived）。
- 绝技特写收尾：守方 EFFECTS 脚本的 aniOver 直接进 phase 101（变暗 16 → 拆场 → 回地图变亮 16），不查场上对象是否还活着；未完的特写对象在拆场位 `0x4c1404` 置位的那一 tick 自删（static-derived，§9）。
- 重制 `CombatPresentationTiming`、`OpeningCinematics`／`BattleOpeningCoordinator`、`BattleCameraController`／`WorldMapRuntime`、`BattleCombatCutin` 按这些计数经 `OriginalTick`（16 ms/tick）换算（static-derived）。
- 差异：对象 700 每级明暗已读出——每个 565 分量取 ⌊c·(16−n)／16⌋，重制黑层 alpha n／16 与之线性等价，只差 5／6 位截断的末位（static-derived）；击中闪光寿命已读（defProcAttackFlash `0x401140`：刀光级 16、停 10、每 2 call 降一级、第 54 call 自删并清父 `+0x88`，见 [original_effect_motion.md](original_effect_motion.md) 第 77 行）；施法 phase 102 子状态 4 的 16＋11 call 与 `0x4c1408` 释放已读并照做（见 [original_cast_overlays.md](original_cast_overlays.md)「证据」）（`mapobjFlash` 已读，见 [地图物件闪烁](original_map_object_flash.md)）；像素混合未逐像素对照（provisional）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。单位见 [原版 tick 率](../runtime_observations/original_tick_rate/README.md)（设计 16 ms／tick，62.5 tick/s）；本包是 [映射表](../runtime_observations/original_tick_rate/tick_mapping.md) B 类行的读数来源。所有计数以主循环 tick 为单位；秒 = tick × 16 ms（设计值），本机体验 × 19.4 ms。

### 1. `defProcShowNumber`（`0x408580`）：地图数字的寿命与上浮

对象由 `0x4084e0(x, y, value, wait_ref, kind, hold)` 生成（对象 0xb1 `obj_ShowNumber`，`0x45e307` 创建时置 `+0x80 |= 0xb0000000`，含 0x20000000「初始化中」位；`+0xa8 = hold`、`+0xac = wait_ref`、`+0x8e = kind`）。过程每 tick 收到 `+0x80` 作为 flags（`0x45f5f7` 调 `[0x4a19bc[+0x64]](obj, obj+0x80)`）：

| 阶段 | 读法 | tick |
| --- | --- | --- |
| 保持（hold） | flags 含 0x20000000：`+0xa8--`，>0 则返回；≤0 时清该位、`+0x28 = 16`，kind 0 置 `+0x90 = 0x20005`（低字倒数 5、高字重载 2）、`+0x94 = 0x10000`、`+0x98 = 0xa000a`（10／10）、`+0x9c = 0x10006`；其他 kind 置 `+0x90 = 0x20010`（倒数 16、重载 2） | `hold`（至少 1） |
| kind 1–6（EXP／回复／MP／$／MISS／LEVEL UP）显示 | 每 tick `word[+0x90]--`；归零时重载 `word[+0x92]`（2）并 `+0x28--`；`+0x28 < 9` 时首次把 `wait_ref+0x8c` 加一（放行等待它的动画）并清 `+0xac`；`+0x28 < 1` 时 `0x45e3ed` 删除对象 | 16 ＋ 15×2 ＝ **46**；放行在第 **32** tick |
| kind 0（红色伤害数字，弹跳） | `+0x96` 为弹跳中的位数索引，每 10 tick（`+0x98`／`+0x9a`）前进一位，越过位数后归 0；两索引都归零后 `+0x90 = 0x10012`（倒数 18、重载 1），之后每 tick `+0x28--`，从 16 数到 0 | 10×位数 ＋ 18 ＋ 16：1 位 **44**、2 位 **54**、3 位 **64** |
| 上浮 | 函数末尾 `+0x80 ^= 0x10000`；flags 含 0x10000 的 tick `+8`（y）减 1 | 每 2 tick 上浮 1 px（46 tick ≈ 23 px） |

调用侧的 hold：HP／MP 回复（[original_resource_recovery](original_resource_recovery.md)）HP 数字 hold 0、MP 数字 hold 40。因此回合尾部 HP 数字 0–46 tick、MP 数字 40–86 tick。

### 2. `actShowSectionName`（opcode 12）：章节标题的进出与停留

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

**层级段为何是 51 tick（static-derived）**：r2 逐条核汇编 `0x452f8d`（子 1）／`0x452ff6`（子 3）／`0x45307b`（子 5）／`0x4530b3`（子 6）：计数重载时**先查 ≥16／==0 再加减**，第 16 次加减之后还要再等一次重载（3 tick）才换段，故每个层级段 51 tick；子 6 由层级归零结束，不等缩放回到 8.0（`0x4530c9` 的封顶在 51 tick 内不会触发）。

**两层的画法（static-derived）**：每 tick 状态推进后（`0x453111` 起）先画底图、再画章节名，两者同一绘制记录（`0x461479`），位置都是镜头左上 ＋ (0x140, 0xf0)＝视口 (320,240)，由各自 SHP 原点对齐。
- 底图（`+0x9e ≠ 0`）：层 0x32，形状 `+0x9c`（`SHAPE\LEVELSEC.SHP`，640×208、原点 (320,104)，中间灰带 0x73ae、上下渐黑）；模式 `0x2000000`，层级 < 16 时 `0x22000000`，缩放 ≠ 1.0 时再或 `0x8000000`。记录 `+0x20 = 0x10000`（x 缩放 1.0）、`+0x24 = [0x4c1d34]`（y 缩放）——`0x461479` 把两者抄到显示项 `+0x1c`／`+0x20`，`0x461982` 用 `+0x1c` 乘 x 跨度、`+0x20` 乘 y 跨度，所以**只纵向拉伸**。`0x46b691` 按位 25–27 查表 `0x46b6b1`：`0x2000000` → 像素种类 10（`0x463eeb`）、`0xa000000` → 种类 11（`0x464c22`，缩放版）。种类 10 的内核是 RGB565 逐通道**饱和减法** `dst − src`（借位检测后与掩码表 `0x4bdbec`）；模式含 `0x20000000` 时 src 先经 `[0x4bfbf0 + 层级×4]` 的层级表缩放，即 `dst − src × 层级/16`。因此 8× 纵向拉伸时灰带盖满全屏、把整个画面压暗，缩回 1× 后成为屏幕 y 170–310 的暗带（形状行 34–174 非黑；核心灰 64–144 → 屏幕 200–280，上下各 30 px 渐变）。
- 章节名（`+0x9a ≠ 0`）：层 0x33，形状 `+0x98`（本关 `SHAPE01\WORDnnn.SHP`；PAK 内全部 46 个 WORD 形状原点都是 (宽÷2, 高÷2) 下取整，resource-derived）；层级 16 时模式 0（普通不透明绘制），以下 `0x20000000` → 表 `0x46b691` 种类 4（`0x4699fd`，`src×层级/16 ＋ dst×(16−层级)/16` 交叉淡化）；不缩放（x、y 字段沿用底图那次的栈记录，但模式无 `0x8000000`）。

**录屏对照（runtime-measured，2026-09-24 录屏，游戏区 = 原片 (112,140) 起 1280×960 ÷ 2）**：第一战《棄卒》标题卡 27.62 s 起全屏均匀变暗（平均亮度 84 → 8，28.36 s 到底），28.72 s 起暗区从上下边缘收拢，29.36 s 定格为 y≈172–308 的横带（核心 196–284 最暗，与形状推算的 170–310／200–280 一致）；章节名 29.36 → 30.19 s 淡入、1× 居中（宽约 158 px，WORD051 为 161 px），**停留 0 tick 即被跳过**（按住／点击），30.19 → 31.07 s 淡出；31.07 s 起暗带张开并淡出，31.91 s 画面复原；32.01 s 胜负面板开始淡入（与重制标题结束后 5 个非等待 token＋面板溶入一致）。全程 27.62–31.91 s ＝ 4.29 s，与 263 tick 同量级（该录屏的实际 tick 长未单独量，不用于区分 257／263）。帧在仓库外 `ignored/title/`，不入库。

### 3. 地图边缘滚动：每 tick ±12 px

`0x43e570`（地图光标过程，只在玩家过程的四个选格／选目标子态 `0x443e2a`／`0x4445b7`／`0x444fe6`／`0x445286` 每 tick 调用）调 `0x43e4a0`：四个方向各自独立判一次「方向键位置位或光标越过该边」→ 一次请求：左（位 1 或屏幕 x < 10）`0x42dc50(−12, 0)`、右（位 2 或 x > 630）`(+12, 0)`、上（位 4 或 y < 10）`(0, −12)`、下（位 8 或 y > 470）`(0, +12)`（屏幕坐标＝`[0x4c1a8c]／[0x4c1a90]` 减镜头 `[0x4c091c]／[0x4c0920]`）。所以同向键＋边缘仍只请求一次（不加倍），反向键＋边缘在同轴上抵消，斜向是两轴各 12（不归一化）；`[0x4c6390] & 0x600` 时循环两遍即 ±24——输入轮询 `0x415910` 把 DIK 0x2a（左 Shift）记为位 0x200、DIK 0x36（右 Shift）记为位 0x400，方向键位 1／2／4／8 为 ←（DIK 0xcb／0x4b）→（0xcd／0x4d）↑（0xc8／0x48）↓（0xd0／0x50）。帧体 `0x42d600` 开头 `0x42dc80` 清零请求、结尾 `0x46bede(dx, dy)` 把累计请求加到镜头 `[0x4c091c]`／`[0x4c0920]` 并夹到地图范围。大地图经 `0x4271f1 → jmp 0x43e4a0` 复用同一函数（`0x4271e9` 仅在 `[0x4c1ac0] == 0` 时跳入，该标志含义未读），方向键与边缘同样生效。剧情脚本的镜头（actScrollBG*、走路跟随）走另一条 `0x43bf30`／`0x45e80d` 缓动路径，见 [original_script_camera_scroll](original_script_camera_scroll.md)。

因此边缘滚动 = **12 px/tick = 750 px/s**（按住任一 Shift 24 px/tick = 1500 px/s）。

### 4. 脚本 `actWalk` 系列：速度参数存入角色 `+0x98`

VM 处理器（opcode 2–7，`0x4508a8` 等）把 `[code][serial][x][y][speed]` 交给 `0x44fcf0`：目标格中心化（`& ~31 + 16`），`+0x4a`／`+0x48` 目标，`word[+0x98] = speed`，`+0x8c = 0x320000`（行走状态 0x32），`+0x50` = 删除／Wait 标志。消费在 `0x453b90` 状态 0x32 sub 2 的跳转表 `0x4543d8`（[original_script_camera_scroll](original_script_camera_scroll.md)）：speed 1 → 1 px/tick、2／3 → 2、0／4／其他 → 4、8 → 8——与 [tick 率包](../runtime_observations/original_tick_rate/README.md) 实测玩家 4 px/tick 一致。重制 `BattleOpeningCoordinator.walk_pixels_per_tick(speed)` 用同一张表，速度 × 62.5 px/s。`actMoveDispWait`（opcode 55）：VM 处理器 `0x45136a` 存 code／serial／dx／dy／speed 并进 VM 状态 0x37；`0x452eac` 调 `0x4501f0(code, serial, dx, dy, speed, Wait 时 VM)`，它把「当前像素＋位移」格心化写进 `+0x4a`／`+0x48`、speed 写 `word[+0x98]`、`+0x80 |= 0x1800`、`+0x8c = 0x320000`——与 actWalkDisp 进同一行走状态，走速走同一张 `0x4543d8` 表。`0x1800` 两位对路线、到位、帧推进与朝向的作用见 §8（static-derived）。

### 5. `actDarkScreen`（opcode 48）：不等待，交给对象 700

`0x452102` 调 `0x43e2a0(0)`：`0x45e307(0, 0, 700, 0)` 插入 `obj_ScreenDarker`（OBJ-ALL.H 700）并置 `+0x90 = 0`，VM 立即继续（无等待状态）。

对象 700 的过程 `0x43e2d0`（过程表 `0x477d28`；由 `+0x90` 放行指针契约与 `0x43e2a0` 对应）：初始化消息 `+0x94` 为 0 时置 `0x30003`（重装 3、计数 3），暗度级 `[0x4c1ca8] = 0`；状态 0 每 tick 计数 −1，归零重装 3 并级 +1，到 16 进状态 1（**48 tick 渐暗**，16 级阶梯）；状态 1 保持；带 `0x10000` 时转状态 2（状态 1 先置级 16），每 3 tick 级 −1，到 0 删对象并放行 `+0x90`。每 tick 以 `0x461479(0x4c1c80)` 提交绘制。`actDeleteDarkScreen`（opcode 49，`0x452123`）调 `0x43e270(对象, 0)`：`+0x80 |= 0x10000`、`+0x90 = 0`，同样**不等待**；渐暗中途收到则从当前级往下退。

**每级画法（static-derived）**：`0x461479` 只把记录挂进深度桶，真正的混合在合成器里。记录 `0x4c1c80` 状态 0／2 模式 `0x20000000`、`+0x28 = [0x4c1ca8]`＝级 n、源形状 `+0x30 = [0x4bbb4e]`；状态 1 模式 0（整屏直接盖源形状）。`[0x4bbb4e]` 由 `0x45f7cb` 建成 768 行都指向 `[0x4a4210]` 前 0x600 字节（清零）的整屏纯黑形状（`[0x4bbb52]` 是同法的纯白形状）。合成器 `0x46b6c1` 按 `(模式 & 0x78000000) >> 27` 查 `0x46b691` 得操作 4，跳转表 `0x46211c[4] = 0x4699fd`：每像素 `out = T[n](源) + T[16−n](下层)`，`T[k]` 是 `0x460fb0` 开机建的 17 张表之一（`0x4bfbf0[k]`，每张 0x1000 字节、低 11 位与高 11 位各一半），由 `0x460e9c`（565）／`0x460f26`（555）按分量算 `⌊c·k／16⌋`。色格式：默认 565（半色掩码 `[0x4bfc34] = 0xf7de`），显示为 555 时 `0x4611e3` 改 `0x7bde` 并改用 555 表。源为纯黑，故**级 n 的每个分量＝⌊c·(16−n)／16⌋**（R、B 5 位，G 6 位，各自截断；n＝16 全黑，n＝0 原样），线性、无查表曲线。

重制 `OpeningCinematics._step_dark_screen`：每 3 tick 一级、从当前级走到 16 或 0，两个 token 不再挡脚本（static-derived）；每级画黑层 alpha 级数／16，即 `c·(16−n)／16`，与原版同一比例（static-derived）；原版在 5／6 位分量上向下截断，重制在 8 位上混合，每分量最多差一个 565 量化级，未逐像素对照（provisional）。

### 6. 普攻切入的守方对象 `defProcAnimalDefense`（`0x4038a0`，slot 23）：受击停留

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
| 101 | 子状态 0（`0x404b23`）：有续击（对象 `+0x80` 位 0x200，`0x403860` 为反击／追加击置位）且目标 HP ≥ 1 → 直接子 2、`0x4c1404 \|= 1`、`0x42c3f0(0)`（无过渡）；否则 `0x42dc90(1)` = `0x46098f(1)` 请求变暗 → 子 1；子 1（`0x404ada`）等 `0x460989()`（`[0x4bbb5a]` 过渡挂起标志）归零后 `0x42c3f0(0)` 退出切入、`0x42dca0(1)` = `0x4609c0(1)` 请求变亮、`+0x30 = 0xffff` 隐藏 → 子 2；子 2 等挂起归零后 parent `+0x8c++`、自删 | **变暗 16 ＋ 变亮 16**（读法见下）|

合计（守方对象生成起）：中立 32 tick → 命中：受击姿态停留 40 ＋（27 ＋ 10×位数）＋ 1 = **68 ＋ 10×位数**（1 位 78、2 位 88、3 位 98）；落空：15 ＋ 1 ＋ 40 = **56**；之后进屏幕过渡。原版**没有**"恢复中立姿态"一段：受击帧持续到过渡开始、对象隐藏。±1 tick：数字对象与守方对象在同一 tick 内的处理顺序未读。录像量得的受击停留 1.5 s（÷ 19.4 ms ＝ 77 tick）与 1 位伤害的 78 tick 相符。

**屏幕过渡的 tick 长度**：`0x46098f(rate)` 置挂起 `[0x4bbb5a] = 1`（方向 +1）、未挂起时层级 `[0x4bbb56] = 1`、计数字 `[0x4bbb5e] = rate:rate`；`0x4609c0(rate)` 置挂起 −1、未挂起时层级 16。帧体 `0x42d600` 每 tick 调 `0x460a06`：层级 ≠ 0 时以模式 `0x20000000`、层级 `[0x4bbb56]`、最高绘制层 `[0x4bfc4c]` 画全屏形状 `[0x4bbb4e]`（`0x45f7cb` 合成的屏幕大小形状，768 行全指向 `0x4a4210`——.data 中初始化为零的行 ＝ RGB565 黑；运行期是否改写该行未查），再让计数字减一：归零时重载高字并 `层级 += 方向`；层级 ≤ 0 → `0x4609f1`（层级 0、挂起 0）；层级 > 16 → 层级 16、挂起 0。模式 `0x20000000` 的像素例程（`0x4699fd`，跳表 `0x46211c` 项 4）为 `out = src×表[层级] ＋ dst×表[16−层级]`，16 ＝ 全 src。因此 `0x46098f(1)`：画层级 1…16 各 1 tick 后挂起清零 ＝ **16 tick 变黑**（受击姿态在其下保持）；`0x4609c0(1)`：画 16…1 ＝ **16 tick 从黑变亮**（此时 `0x42c3f0(0)` 已清切入标志，帧体 `0x42d280` 重新画地图；守方 `+0x30 = 0xffff`）。**同 tick 先后**：帧体 `0x42d600` 先调对象执行器 `0x45f5f7`（`0x42d76d`），再调 `0x460a06`（`0x42d772`）、最后 `0x42d280` 画帧，所以对象发出的请求当 tick 就画。`0x460989` 只是 `mov eax, [0x4bbb5a]; ret`（读挂起标志）。以 phase 101 子 0 那一 tick 为 T0：子 0 请求 `0x46098f(1)`，T0…T15 画层级 1…16（T15 画完层级越过 16、挂起清零）；T16 子 1 见挂起为 0，调 `0x4609c0(1)`（未挂起→层级 16），T16…T31 画 16…1（T31 后层级 0、挂起清零）；T32 子 2（`0x404ac8`）见挂起为 0 跳 `0x404d90`：清 `0xc00000` 切入位、`0x4c1404 = 0`、`0x401710`、`0x42c3d0`、parent（`+0xa8`）`+0x8c++`、`0x45e3ed` 自删。变暗 16 tick 含子 0 那一 tick、之间**没有停留**、变亮 16 tick，交接在 T32＝子 0 起第 33 个 tick。有续击（反击／追加击待演、目标存活）的镜头两段都不播：T0 子 0 直接置子 2（`add ecx, 2`，`0x404b55`），T1 子 2 见挂起为 0 同样走 `0x404d90` 交接——比"子 0 当 tick 交接"晚 1 tick。战斗中 `0x42dc90`（→ `0x46098f`）只有守方 `0x404b97` 一个调用点（其余 `0x42cb89..0x42cd00` 在画面切换例程）。

### 7. 普攻切入的攻方开场（`0x401c20` phase 100）：24 tick 缩放 ＋ 32 tick 叠层，无放声

攻方对象 init（`0x401c20`，kind 0）置 phase `0x640000`。case 100（`0x4027ce..`）：

| 子状态 | 读法 | tick |
| --- | --- | --- |
| 0 | `+0x80` 位 0x200 清零（首击）：`+0x90 = 0x1000`（缩放 1/16）、`+0x28 = 0x10`、子 1；位 0x200 已置（反击／追加击的后续镜头）：只 `0x436490(+0xa0, 3, 0)` 生成身份栏文字，直接 phase 0 开始程序 | 1 |
| 1（缩放段） | `+0x90 < 0xd0001` 时以模式 `0xc000000` 在 (320,240) 画 `+0x86` 形状第 0x34 帧、缩放 `+0x90`，再 `+0x90 = 0x401060(+0x90)`：<0x4000 步 0x1000、<0x8000 步 0x2000、<0x10000 步 0x4000、<0x20000 步 0x6000、<0x30000 步 0x8000、<0x40000 步 0xa000、其余步 0xe000 | 0x1000 → 0xc4000 共 **24** 步 |
| 1（叠层段） | 首次 ≥ 0xd0001：`+0x90 = 0x120000`（18.0）、恢复帧 `+0x30 = +0xc8`、`0x436490(+0xa0, 3, 0)` 生成身份栏文字、`+0x94 = 0x20002`；之后每 tick 以模式 `0x28000000`、层级 `+0x28` 画；`+0x94` 每 2 tick 让 `+0x28` 减 1，16 → 0 | **32** |
| 2 | `0x4027ee` 调 `0x460989()`（读挂起标志 `[0x4bbb5a]`）：非零则让出；为零则整字 `+0x8c = 0`（`0x4027fb`）进 phase 0 开始程序。上一交锋的守方 phase 101 子 2 要等挂起清零才交接（§6），战斗中别无变暗请求者，故首镜到这里挂起总为 0 | **1** |

`0x436490` 是状态窗文字生成器（→ `0x434d10`，mode 3 = 切入身份栏），**不是放声**——[ANIMAL 程序包](animal_program_execution.md) ⑤ 的"放声"为误读；phase 100 内没有 `0x42c180` 调用。

**画法（static-derived）**：
- 被画的形状 `+0x86`：init 顶部（`0x401c89`）`+0x86 = word[+0x32]`，早于 `0x45e525(obj, 演员 shape, count, 2)` 把 `+0x30／+0x32` 改成演员形状——即 `0x45e307` 按对象类型装入的默认形状。OBJ-ALL 154 `obj_Animal_Attack` 的 `shape_resource` 为 `MAGIC\BALL001.SHP`（resource-derived，`battle*_seed.json` 对象表）：295×298、原点 (147,149) 的白心→黑边径向光球（已导入 `content/imported/hsl/chapter01/combat_animation/opening_ball.png`，manifest `opening`）。`0x4607f9(mode, x, y, shape, layer, level, zoomx, zoomy, …)` 把绘制记录排进显示表 `0x461479`（第 5 参 0x34 是绘制层，演员的公共尾部用 0x17；`[0x4bbbd4 + 层×4]` 链表），不是帧号。
- 模式位（`0x46b691` 显示表消费者）：位 25–26 非零走表 `0x46b6b1`：`0x4000000` → 像素例程种类 8（`0x462154`：`ax = src + dst`，异或检测各通道进位后 `or` 饱和掩码 `0x4bbbec`——**RGB565 饱和加法**），`0xc000000` = 加法 ＋ 缩放（种类 9 `0x462e8b`，同一加法内核的缩放变体）；位 25–26 为零走表 `0x46b691`：`0x20000000` → 种类 4（`0x4699fd`，层级交叉淡化，见 §6）、`0x28000000` → 种类 5（缩放 ＋ 交叉淡化）。
- 因此：缩放段 24 tick 是光球以加法混合从 1/16（18 px）长到 12.25×（3600 px，屏幕角落只到半径 22%，近白）盖满屏幕；叠层段 32 tick 是同一光球 18×（屏幕只到半径 15%）以层级 16→1 交叉淡化——**白屏淡出**，露出已恢复帧的攻方与刚生成的身份栏（原录像 `12_leonard_normal_attack/frame_001` 的泛白画面即此段）。缩放段之下：init 的 `0x42c3f0(1)` 置 `[0x4c1b20]`，帧体 `0x42d280` 据此跳过地图绘制、改 blit `[0x4c1e00]` 缓冲（行距 0x500 ＝ 640 px）；该缓冲的装入路径未追。缩放段之下是战场地图，不是切入底图 BG051（runtime-measured，[镜头与面板动效 §5](../runtime_observations/camera_panel_motion/README.md#5-切入白光光球在地图之上放大)：2026-09-24 录屏四次普攻切入 113.49–113.78、163.95–164.20、199.66–199.95、353.72–353.97 s，光球都从屏幕中心在**仍可见的战场地图**上长大，直到全白才换成特写；即 `0x4c1e00` 在缩放段装的是地图画面）。身份栏与特写黑底在缩放段不画，见下「构图」。

**构图：缩放段跳过公共尾部（static-derived）**。`0x401c20` 各子状态处理完多数 `jmp 0x4034c6`（公共尾部）；缩放段两条路径直接 `jmp 0x4035eb`，**越过** `0x4034c6..0x4035eb`：子状态 0 首击分支（`0x402985`，置 1/16 缩放那 1 tick）与子状态 1 缩放分支（`0x40285d`，`+0x90 ≤ 0xd0000` 的 24 tick）。被越过的一段依次是：`[esp+0x24]`（对象 `+0x80 & 0x100`）为 0 时 `0x46067d`／`0x461479` 排入桶 0x32 的特写黑底、`0x43b4e0(+0xac, 2, +0xac)` 排入切入身份栏窗口（WINDOW10，mode 2；`0x43b4e0` 不读 `[0x4c1b00]`，身份栏每 tick 靠这一调用出现），以及位 0x40／0x20 的位移积分（`0x45eb9d`／`0x45eb75`／`0x45eb89`）。叠层段首 tick（`0x402862`：恢复帧、`0x436490` 生成文字）画完光球后走 `0x4028f2..` 落到 `0x4034c6`，**同一 tick** 起黑底与身份栏每 tick 排入，被层级 16→1 的光球盖住后渐显；反击／追加击（位 0x200）子状态 0 也落 `0x4034c6`，首 tick 即有身份栏。守方 `0x4038a0` 没有缩放段（phase 100 kind ≠ 2 直接回 0），公共尾部 `0x404ba6..0x404cc6`（黑底桶 0x2f、`0x43b4e0(+0xac, 2, +0xac)`）只在 phase 101 子 1→2 那 tick（`0x404b1e`，清切入标志、请求变亮、`+0x30 = 0xffff`）与子 2（`0x404ad5`）被越过——变亮段不画身份栏与黑底。

| 段 | 攻方光球 | 特写黑底 | 身份栏（底板＋文字＋条） | 攻方／守方 |
| --- | --- | --- | --- | --- |
| 缩放段（首击 1 ＋ 24 tick） | 加法 1/16→12.25× | 不画 | 不画 | 攻方帧仍是对象默认形状，被帧体跳地图后的 `0x4c1e00` 缓冲与光球覆盖（见上） |
| 叠层段（32 tick） | 18× 层级 16→1 | 画 | 画（首 tick 生成文字） | 攻方恢复帧 |
| 程序与受击停留 | — | 画 | 画 | 守方命中 tick `+0x30 += +0x7a − 1`（`0x404015`，`+0x7a` 是 `0x45e525` 装入的该演员形状帧数）＝最后一帧，保持到对象隐藏 |
| 变暗（16 tick） | — | 画 | 画 | 受击帧 |
| 变亮（16 tick） | — | 不画 | 不画 | 守方隐藏 |

**攻方缩放只来自程序**：`0x401c20` 对对象缩放字 `+0x20／+0x24` 的写入只有换边镜像（`0x401ddf`：−1.0／1.0）与 aniSetZoom 指令（`0x40247f`：两轴同值），没有按动作外框自动缩小的计算；演员在特写里按原尺寸（或程序给的缩放）画，身份栏窗口画在其上。

### 8. actMoveDispWait 的 `+0x80 |= 0x1800`：同一寻路，保形、无声、按速度换帧

读法：r2 反汇编 `0x453b90`（行动者过程，状态 0x32 分支 `0x453d27`，子状态跳表 `0x4543b8`）、`0x4501f0`、`0x4111d0 → 0x411080 → 0x40f350／0x413900／0x410a50`。`+0x80` 在整个过程里只在三处被读：

| 块 | 地址 | 原版 |
| --- | --- | --- |
| 目标 | `0x4501f0` | 目标 = (当前像素 + 位移) `& ~31 + 16`，再经 `0x44fbd0` 修正（与 actWalkWait `0x44fcf0` 同一调用）；写 `+0x4a／+0x48`、速度 `+0x98`、`+0x50`、`+0x80 \|= 0x1800`、`+0x8c = 0x320000` |
| 路线 | `0x453d44..0x453d71`、`0x454122..0x45412d` | 子状态 0 与途中续算都调 `0x4111d0(actor, dest, 0x12, 0xc)`，与 actWalk 系列完全同路（[剧情走位寻路](original_script_walk_path.md)）；寻路链 `0x4111d0／0x411080／0x40f350／0x40f200／0x411990／0x410a50／0x413900` 不读 `+0x80`，所以 0x1800 不改变路线、不穿墙、不穿单位 |
| 到位 | `0x4540f0..0x454120` | 路径缓冲走完时比较当前格与目的格（都 `& ~31`），不同则续算，相同则落位进下一子状态；无容差，与 actWalk 相同 |
| 帧推进 | `0x453ba3..0x453bb2`；`0x453e63..0x453ebf` | 过程入口在分派状态前测 `ah & 0x10` 与 `ah & 8`，两位都置时**每 tick** 调 `0x45e5a6`（循环换帧，延迟 D 时每 D+1 次推进一帧）；子状态 2／6 按速度写延迟 `+0x7c／+0x7e`：1 → 6、2／3 → 4、8 → 1、其他 → 2，即每 7／5／2／3 tick 一帧 |
| 朝向 | `0x454205..0x454215` | 每步换方向时本应 `0x446c40(obj, 类型, 方向, 延迟)` 换行走形态、到位时 `0x446c40(…, 0, 10)` 回站立；`ch & 0x10`（0x1000）置位时整段跳过——保持当前形态与朝向（如 actChangeShape 换上的绳索形态） |
| 走步声 | `0x454041..0x45408a` | `ah & 0x10` 置位时跳过相对帧 0／3 的走步声 `0x409610` |

子状态 1／4 的 `0x446c10` 检查与 `0x446c40(…, 5, 6)` 不受这两位控制；到位后 `0x454262` 回状态 0 时 0x1800 仍置位，站立公共尾因 0x1000 跳过推帧，帧定格在到位那一帧，直到 `actRestoreShape` 清位并从站立首帧重载（static-derived；lane SHAPECADENCE，见 [actor_animation_groups.md](actor_animation_groups.md)「结论」）。

0x1800 的去向（static-derived，全 EXE 字节搜 `ffe7ffff` 与 `and r8h, 0xe7`）：唯一同清两位的写入点是 `0x450329`（`0x4502f0` 帧数 0 即 actRestoreShape：`+0x90 = 0xffff`、`and ch, 0xe7`、`+0x8c = 0`）。`0x454262` 到位、`0x44fcf0`／`0x44fd90`／`0x44ff50` 的走位入口都不写 `+0x80`；另外三处只动 0x1000／0x800 的（`0x407210`／`0x407243`、`0x43f243`、`0x443767`）属战斗受击／倒下状态机，不在剧情路径上。所以 actMoveDispWait 之后到 actRestoreShape 之前，同一演员的任何剧情走位都照样保形、无声、按该次速度换帧。插播：actMoveDispWait 是 Wait 形式，VM 停在状态 0x37，直到 `0x454262` 对 `+0x50` 指向的 VM `inc word [+0x8c]` 放行，其间不会执行别的 token，没有对白插进移动中的情形。重制 `OpeningStoryObjects._move_disp_held`：`_move_disp` 记下、`_restore_shape` 清掉，期间 `_move_actor` 一律按 `move_disp_frame_ticks(该次速度)` 保形。第一章唯一用例是玩家第 3 场 · 逃出克萊恩城（LEVEL053）开场：`actChangeShape,SID_PLAYER1,1,4,SHAPE\002-30001.SHP,6` → `actMoveDispWait,SID_PLAYER1,1,0,288,2`（绳索下滑）→ 紧接 `actRestoreShape`，中间没有别的走位。


### 9. 绝技特写的收尾时刻：脚本结束即收，对象不参与

读法：r2 反汇编 `0x401c20` phase 101（字节表 `0x403748` → 跳表 `0x403720` 第 6 项 `0x40298a`）、`0x4038a0` kind 2 的解释循环（`0x403954` 起，op 字节表 `0x404f48` → 跳表 `0x404ee8`）与 phase 101（`0x404aab`）、拆场位 `0x4c1404` 的全部 16 处引用（`/x 04144c00`）。

| 步骤 | 地址 | 原版 |
| --- | --- | --- |
| 攻方脚本结束 | `0x402295` | aniOver：`+0x8c = 0x650000`（phase 101 子 0）、保存指针、让出 |
| 攻方收页 | `0x40298a..0x4029ee` | 子 0 只等 `+0x88`（本对象插入的攻击闪光）归零，随即子 1 并 `0x4c1404 \|= 1`；子 1：`0x42c3f0(0)`、`0x401710`、`0x42c3d0`、parent `+0x8c++`、`0x45e3ed` 自删 |
| 守方开页 | `0x40435e`（phase 100） | 先清 `0x4c1404` 位 0；`0x406d20`／`0x406eb0` 插入攻／守方对象时整字清零 |
| 守方脚本 | `0x403954` | kind 2 从 `0x4c1408` 取 EFFECTS 守方程序逐条执行（op 0..35） |
| 守方 aniOver | `0x403d3d..0x403db6` | `0x4104d0(1)` 取下一目标：有则换目标、`+0x8c = 100` 重开守方页，新程序指针来自 `0x4c1b70` 表并 `0x4c1404 \|= 1`；无（或 `0x409a20` 返回 −1）则 `+0x8c = 0x650000` 直接进 phase 101（`0x403d7a`） |
| 守方收尾 | `0x404b23`／`0x404ada` | 子 0：无续击 → `0x42dc90(1)` 请求变暗（16 tick，§6）→ 子 1；子 1 等过渡挂起归零后 `0x4c1404 \|= 1`、`0x401370`（删 `0x4c1400` 对象）、`0x42c3f0(0)` 退出切入、`0x42dca0(1)` 变亮、`+0x30 = 0xffff` |
| 对象自删 | `0x404ffa`、`0x4050a0`、`0x4051d1` | 过程表 slot 36／37／38（`0x404f90`／`0x4051d0`／`0x4050a0`）入口都测 `0x4c1404 & 1`，置位即 `0x45e3ed` 自删 |

结论：两页都在各自脚本 aniOver 后收，收尾路径上没有任何对象存活检查——攻方只等自己的攻击闪光，守方只经 16 tick 变暗；这 16 tick 内特写对象照常运行，拆场位一置，slot 36–38 的对象在下一次过程调用时自删（带延迟尚未出现的随机插入实例同样被删）。攻方页的对象在攻方收页时已被删，不跨入守方页。

## 重制接线

provenance 头 timing／layout 维度写 `static-derived docs/evidence_packets/static_reverse/original_tick_counts.md`（`BattleCombatCutin.gd` 按 §7 锚点引用）。

- **§1 数字**：`CombatPresentationTiming`：`SHOW_NUMBER_TICKS = 46`、`SHOW_NUMBER_RELEASE_TICKS = 32`、`DAMAGE_NUMBER_BASE_TICKS = 34`＋`DAMAGE_NUMBER_DIGIT_TICKS = 10`／位（kind 0 实际寿命）、`SHOW_NUMBER_RISE_PX_PER_TICK = 0.5`；`BattleTurnEndCue` 以 40 tick 间隔换事件、末事件停留到它的数字被删（`ResultNumberFloater.life_ticks`：hold 归零那一 tick 在 `0x4085eb`／`0x40861b` 只初始化即返回，故 hold 0 的绿／蓝数字 1＋46＝47 tick；无数字的节拍 46 tick）；`BattlePresentation`／`MagicImpactPresentation` 的浮字按 kind 取寿命。kind 0 的弹跳绘制见（逐位揭示、2×／1.5×／4× 闪光、不上浮，寿命 10×位数＋34，[地图姿势与飘字包 §3](../runtime_observations/map_pose_floaters/README.md#3-红色伤害数字0x408580-kind-0)），地图、特写与法术的伤害数字由 `DamageNumberFloater` 画，回复／MP／MISS 由 `ResultNumberFloater` 按 kind 2／3／5 画。
- **§2 章节标题**：`BattleOpeningCoordinator.title_seconds`／`OpeningCinematics`：`OpeningCinematics.section_title_step` 逐 tick 复现子状态 0–7（含 3 tick 计数与"先查后加减"），`_fade_title` 每过一个原版 tick 走一步；`build_section_title_view` 建两层——`SectionTitleBand`（LEVELSEC，`CanvasItemMaterial.BLEND_MODE_SUB`，按原点 (320,104) 放在 (320,240)，`scale = (1, zoom)`，`modulate.a = 层级/16`，即 `dst − src·层级/16`）与 `SectionTitleName`（WORD，1×，`modulate.a = 层级/16`）；层级 0 的层不画。协调器等待 582 tick（`SECTION_TITLE_IN_TICKS 159`＋`HOLD 320`＋`OUT 103`）；停留期间任意键或任意鼠标键（`skip_section_title`，原版按键掩码 `0x600010`／点击掩码 `0x10002` 的重制读法＝任意键／任意键钮）交给下一个停留 tick，等待改为当前 tick 余量＋1＋103，最短 263 tick；进段与出段的输入忽略（只在子状态 4 收输入）。跳过记入 `story_records`（`section_title_skip`：trigger、held_ticks＝含收键那一 tick 的停留数）。标题结束后照旧逐 tick 走完随后的非等待 token 再由 `BattleWinFailBoard` 溶入胜负面板。定向测试 `tests/run_ui_class_contract_tests.gd`（逐 tick 子状态、两层节点、全部注册场景的标题卡资源与唯一处理路径）。未对照：RGB565 饱和减法与 Godot 线性减法混合的逐像素差异；原版一次按住的键也会立即结束停留（掩码是当前按键状态），重制只认按下事件。
- **§8 actMoveDispWait**：`OpeningStoryObjects._move_disp` 目标格心化后走 `_move_actor`（`ScriptWalkPath.route`，与 actWalkDispWait 同路、同速度表、Wait 居中与跟随）；`ActorRuntime.move_along(..., keep_pose_frame_ticks)` 不换朝向与行走形态、不放走步声、到位不回站立，帧按 `move_disp_frame_ticks`（7／5／2／3 tick）循环；到位后定格当前帧、到 `actRestoreShape` 才回站立（lane SHAPECADENCE）。
- **§3 边缘滚动**：`BattleCameraController.EDGE_SCROLL_PIXELS_PER_TICK = 12`、`WorldMapRuntime` 同值；键盘平移与鼠标边缘共用（原版键位与边缘同一请求）：`BattleCameraController.scroll_direction` 按四个方向各自「方向键或越边」合成，同向不加倍、反向抵消、斜向不归一化；战斗选格态（`BattleSceneRuntime`）与大地图（`WorldMapRuntime`）同用，大地图方向键滚动已接上。按住任一 Shift 时 `BattleCameraController.edge_scroll_pixels_per_second()` 取两倍（`EDGE_SCROLL_SHIFT_PASSES = 2`，`0x43e4a0` 两遍循环），战斗选格态与大地图同用。
- **§6 守方受击**：`CombatPresentationTiming`：`TARGET_PAUSE_TICKS = 32`，`hurt_hold_ticks(hit, damage)` = 命中 `HIT_TO_NUMBER_TICKS 40 ＋ damage_number_release_ticks ＋ 1`／落空 `MISS_SLIDE_TICKS 15 ＋ 1 ＋ MISS_HOLD_TICKS 40`；`RECOVERY_TICKS = 16`（变黑期间受击姿态保持，static-derived）、`CLOSING_LIGHTEN_TICKS = 16`（地图上从黑变亮，切入内容已隐藏），只在交换的最后一镜或击杀镜（`closes_exchange`：`last_shot` 或 `defender_hp_after ≤ 0`）播放；`ordinary(actor, strike, first_shot, last_shot)` 返回 `opening／release／target／impact／recovery／darkened／complete`。`BattleCombatCutin` 不回到中立姿态（受击帧保持到镜头结束）。击退 105 px／残影／闪避滑动 150 px 的位移未接（重制仍用 6／24 px 的 reaction 位移，provisional）。
- **§9 绝技收尾**：`SkillEffectScriptPlayer._finish_timeline`：`darken_tick` = max(脚本游标, 结果 tick ＋ `RESULT_HOLD_TICKS`)，`complete_tick` = `darken_tick` ＋ 16（守方 phase 101 变暗后拆场），对象寿命不参与。拆场删对象与攻方收页：攻方页对象剪到 `release_tick`，守方页对象剪到 `complete_tick`（含 open-ended）；插入 tick 不早于本页拆场的对象（随机插入的延迟越过拆场，标 `random`）不生成，它的命令音与对象被删之后才到的命令音一并去掉。`_present_special` 在 `darken_tick` 起叠 16 级变暗；`clip_closing_tick`（拆场与最后一个结果数字删除取晚）后退出切入、地图变亮 16 tick（`BattleCombatCutin.show_closing_lighten_ticks`），`clip_complete_tick` = closing ＋ 16。结果行：萬息集氣法 complete 290 → 306（对象 69 个不变）；慌雨斬 364／329 → 176（种子 7／8，对象 215 → 91／103）；殘影亂斬 142／143 → 126；龍嘯天驅 越过攻方收页仍在画的攻方对象 7 → 0。
- **§7 攻方开场**：`BattleCombatCutin._show_opening`、`CombatPresentationTiming.OPENING_*`：交换的第一镜（`first_shot`，`BattlePresentation._show_strike` 按 `CombatSequence.strikes` 顺序传入；反击镜与追加击镜对应位 0x200 → 无开场）先播 24 tick 加法光球（`opening_zoom_ramp()` 复现 `0x401060` 的 24 个 16.16 缩放值，`BLEND_MODE_ADD`，攻方隐藏、身份栏隐藏、特写底图与底色隐藏——光球画在地图之上）再播 32 tick 18× 光球 alpha = 层级/16（`opening_overlay_level`），光球盖住整个 640×480 含身份栏；随后程序第一条指令。缩放段隐藏身份栏与底板、变亮段隐藏，照「构图」表；攻方只按程序缩放（aniSetZoom）与换边镜像画，不另做外框适配；受击帧 `hurt_frame` ＝ 演员帧数 − 1（`0x404015`）。

## 复现

`python3 tools/hsl_exe_decompile.py`（r2ghidra）或 r2 反汇编本包点名的地址；重制侧 `tools/godot.sh --headless --script tests/run_ui_class_contract_tests.gd`（章节标题逐 tick 子状态）。

## 边界

- 本包只给 tick 计数与状态机读法，不证明绘制内容（数字弹跳曲线）等价；切入开场的 `0xc000000`／`0x28000000`、过渡的 `0x20000000` 与章节标题的 `0x2000000`／`0x20000000` 已读到像素例程种类（饱和加法／饱和减法／16 级交叉淡化），像素级等价仍未对照。
- 系统卷轴展开／收起已读（`0x45e882`／`0x45e91e`，[menus_ui](../runtime_observations/menus_ui/README.md) §6）。
- 未读（保留 provisional）：`0x4c1e00` 切入底图缓冲的装入路径。击中闪光对象 `0x401310` 的寿命（攻方 phase 101 等 `+0x88` 归零）已读，见 [original_effect_motion.md](original_effect_motion.md) 第 77 行。施法对象 phase 102 子状态 4 的过渡／停留与 `0x4c1408` 释放已读（`AnimalCastLead` 照做，见 [original_cast_overlays.md](original_cast_overlays.md)「证据」），对象 700 每级明暗已读（§结论）。
- `mapobjFlash` 亮度步进已读：见 [地图物件闪烁](original_map_object_flash.md)。
- §8：到位后原版回状态 0，`0x453ba3` 的每 tick 推帧只在脚本状态里跑、站立公共尾因 0x1000 跳过，无脚本形态时帧同样定格；重制到位即停帧，一致。子状态 1／4 的 `0x446c10` 起步动作分支在数据下不可达（SHAPEDEF 无 `prepare`，见 [original_action_state_machine.md](original_action_state_machine.md)「起步动作」），`0x44fbd0` 目标修正在重制里经 `_move_actor` 取开局生成器记下的落点（与 actWalk 系列同一路径，见 [original_script_walk_path.md](original_script_walk_path.md)「结论」），走位当时不另跑一次。
- §9：攻方收页在重制里取 `release_tick`，原版还等本对象插入的攻击闪光（`+0x88`）归零；闪光寿命已读（刀光 54 call，[original_effect_motion.md](original_effect_motion.md) 第 77 行），但 ANIMAL 的 19 段 s_action（绝技攻方程序）都不含 aniInsertAttackFlash（`0x4021df`；59 处全在普攻 action，见 [ANIMAL 程序包 §8.1](animal_program_execution.md#81-逐通道-opcode-普查resource-derived)），绝技攻方页没有本对象插入的闪光可等，重制取 `release_tick` 不改（`+0x88` 的其他写入点未逐一核）；结果数字放行（`0x404643`）的阻塞未计入脚本游标，仍以 `RESULT_HOLD_TICKS` 代替，数字寿命长过拆场时黑幕下多停几 tick；出现的随机插入实例集随种子变（与原版共享 RNG 同理，具体实例不逐个对应）。
- §6 交接：重制 `CombatPresentationTiming.ordinary` 在收尾镜头的 `complete` ＝ recovery ＋ 32 tick（原版子 2 交接的 T32）；有续击的镜头 `complete` ＝ recovery ＋ `HANDOVER_TICKS` 1（原版子 0 `0x404b23` 置子 2、T1 交接）。§7：`OPENING_TICKS` ＝ 24 ＋ 32 ＋ 1（`OPENING_WAIT_TICKS`，子 2 那一 tick 不画光球）；子 0 那 1 tick 首镜与续击镜头两边都不计，出手到守方各段的相对 tick 不变。
- 反编译原文留在 `ignored/static/hsl01/decompiled/`，不入库。

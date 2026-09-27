# 法术特效的运动：effProc* 程序逐 tick 原指令执行

> evidence: static-derived: 0x415dc0 效果对象过程、effProc* 跳表 0x4231b0、0x45f5f7 帧循环、0x4237f7 效果脚本解释器、0x401220／0x4010c0 残影的读法与原指令执行; runtime-measured: 2026-09-24 原版录屏 471.7–474.6 s 幻火与原生轨迹的对照; provisional: 种子变体、±1 帧、缺帧循环、镜头跟随与屏幕波纹未在重制画出 · status: live · functions: 0x4010c0, 0x401140, 0x401220, 0x401290, 0x401310, 0x401c20, 0x401dc0, 0x402180, 0x4021df, 0x4038a0, 0x407ec0, 0x415c10, 0x415d20, 0x415d40, 0x415d70, 0x415d90, 0x415dc0, 0x416095, 0x41618a, 0x4162e6, 0x416409, 0x423873, 0x423951, 0x423a20, 0x42dc50, 0x42dcb0, 0x43bf30, 0x446be0, 0x450710, 0x458c10, 0x458c80, 0x45e307, 0x45e3ed, 0x45e575, 0x45e5a6, 0x45e785, 0x45eb75, 0x45eb9d, 0x45ebdc, 0x45f141, 0x45f4b9, 0x45f5f7, 0x45fc01, 0x4602d4, 0x460541, 0x4606a9, 0x46075b, 0x4607f9, 0x46163a, 0x46164b, 0x461687, 0x461982, 0x46b691, 0x46be92, 0x46bede · tools: hsltools/assets/skill_effects.py, hsltools/levels/battle.py, hsltools/probes/effect_motion.py, run_battle_scene_runtime_tests.gd, run_skill_effect_script_tests.gd, run_support_magic_tests.gd · updated: 2026-09-28

## 结论

- 原版每个效果对象由自己的 effProc* 程序每 tick 改位置、换帧、改混合层级与缩放，许多程序还会抛出子对象（火花、子弹、残影）；效果对象一律加法混合（static-derived）。
- 39 行法术引用的 144 个效果对象全部连同子对象逐 tick 原指令执行（84 个 effProc 程序全部复原；四个运行时助手见 §四个运行时助手），得到 `content/generated/hsl/skills/effect_motion.json`；重制 `game/battle/scene/EffectObjectMotion.gd`／`SkillEffectScriptPlayer.gd` 按它逐帧画整棵树（static-derived）。
- 幻火（effCode23）的独立 Python 模型与原生轨迹逐样本相等，与原版录屏节拍一致（[runtime 包](../runtime_observations/effect_motion/README.md)）；幻火是一团光从目标头顶 88 px 处摇摆落下，不是从施法者飞向目标（runtime-measured）。
- 差异：种子变体代替共享随机流、±1 帧、缺帧循环是重制读法；镜头跟随（OtherBBall1）与屏幕波纹（FireBGSet／IconBGSet1）已记入轨迹、重制未画，逐条见边界（provisional）；声音排程未切到原生结果（`effect-sound-timing`）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；unicorn 在合成对象上执行原指令，未运行原程序。

### 覆盖

- **原版读法可以整体执行**：39 行法术引用的 144 个效果对象**全部**连同它们抛出的子对象只经过已审阅代码或下文逐条读过的 Python 应答，逐 tick 执行后得到原生轨迹 `content/generated/hsl/skills/effect_motion.json`；按程序计，法术直接引用的 84 个 effProc **全部**复原。原先卡住的 13 个对象（9 个程序）靠 §四个运行时助手 的读法跑通。
- **tracer 幻火（effCode23）**：独立 Python 模型（`hsltools/probes/_effect_motion_model.py`）按下文 tracer 的读法重算 FlyDrop／FireBomb／FireBomb2 三棵对象树，与原生轨迹逐样本（位置、帧、模式、层级、缩放）一致；与原版录屏逐帧对照（[runtime 包](../runtime_observations/effect_motion/README.md)）：落光 → 50 tick 后六团火 → 112 tick 处 FireBomb2 的 12 颗光球四散淡出，节拍按本机 19.4 ms/tick 对齐。

### 帧模型与公共部分（static-derived）

| 地址 | 读法 |
| --- | --- |
| `0x45f5f7` 每 tick 主体 | 先按平面顺序遍历对象链调用各自过程（`[0x4a19bc + 过程号×4](obj, obj+0x80)`），**调用前先读下一个链接**——当前链尾在本次调用里新挂上的子对象下一帧才处理；再遍历一次绘制：`+0x80 & 0x10000000`（`0x45e307` 创建时置位）的对象本帧不画并清位，形状字 `0xffff` 不画 |
| `0x45e307(x, y, code, 头插)` | 复制 0xb0 字节模板（`0x4a2728[code]`），`+0x80 |= 0xb0000000`，写 x／y、`+0x54` 代码、`+0x58` 平面，默认挂链尾 |
| `0x415dc0` defProcEffectProcess1 前导 | 初始化位 `0x20000000` 在时：形状置 `0xffff`，`+0xae` 减一，>0 则返回（插入延迟）；到 0 时 `+0x30 = +0x32`（首帧）、清初始化位、放 obj_X1、`+0x46 = obj_X2`、`+0x44 = obj_Y1`、`+0x10..+0x18 = 0, 0, 640`、**模式 `|= 0x4000000`（engADDCOLOR）**、层级 `+0x28 = 16`、`+0xa8` 为零时把自身坐标记为基点 `+0xaa／+0xa8`；随后同一次调用按 `+0xac`（obj_Data9）查跳表 `0x4231b0` 进入程序 |
| 模式位（`0x46b691`） | 位 25–26 非零走表 `0x46b6b1`：engADDCOLOR → 种类 8 饱和加法（内核 `0x4623e4` 处读层级表 `0x4bfbf0`，即 `dst + src×层级/16`），加 engZOOM → 种类 9；PROCESS.DEF 名字 `engADDCOLOR_MIX = 0x24000000` 正是"加法＋层级"。全部 131 个对象的轨迹只出现 `0x4000000／0x24000000／0xc000000／0x2c000000` 四种组合——**效果对象一律加法混合**（global.obs 写 `engMIX` 的对象也被前导或上加法位） |
| `0x4237f7` 效果脚本解释器 | op 0 effInsertObject：在原点 `(0x4c6388, 0x4c638c)` ＋位移处创建，`+0xaa／+0xa8` 写原点；op 1 effInsertRandomObject（`0x423873..0x42397a`）：每个对象偏移 = rand(范围) 折进 `(−范围/2, 范围/2]`（范围 0 按 1），**第一个立即、之后每个比前一个晚 rand(延迟范围)**（`+0xae` 累加，`0x423951`）；原点由 `0x423a20` 创建解释器对象时写入 |
| `0x415c10` 随机抛出 | `(x, y, code, x范围, y范围, 起始延迟, 延迟范围, 个数, 演员)`：同样的折叠偏移，`+0xae` 从起始延迟起每个加 rand(延迟范围)＋1，逐个 `0x45e485` 串链 |
| `0x458c10`／`0x458c80` | 两个旋转字的 RNG；rand(n) = (rng & 0xffff) mod n |
| `0x45e575`／`0x45e5a6` | 形状计数：每张停 `shape_delay + 1` 次调用；前者走完停在末张并返回 1，后者回到首张返回 1 |

### tracer：幻火（effCode23）从创建到销毁

脚本：`effInsertObject FlyDrop,0,0 · effWait 50 · effInsertRandomObject FireBomb,0,0,36,48,24,6 · effWait 50 · effInsertObject FireBomb2,0,0 · effWait 50`。

| 对象 | 程序 | 读法（帧从对象创建起算；创建帧不画） |
| --- | --- | --- |
| obj_Effect_FlyDrop（161，FIR01 四张） | effProcFlyDrop `0x416095` | 相 0：上移 90 px、摆动相位 = rand(255)、角速度 6/256 圈、振幅 16；每 tick 下落 1 px，x = 基点 + 16·sin(相位)；四张各 7 tick 走完后置 engMIX，层级 16→1 每 tick 减一，到 0 销毁：共 44 帧（首个可见帧在原点上方 88 px） |
| obj_Effect_FireBomb（162，FIR02 六张，obj_Zoom 1.25） | effProcFireAndBomb `0x41618a`（跳表 `0x42337c`） | 相 0：上移 24 px，以 `0x415c10(x, y, 163, 16, 8, 0, 12, 3)` 抛 3 颗 SprayUpDown 火花；相 1：1.25 倍循环六张一轮；相 2：缩放从 1.0 每 tick 减 1/32 到 0.25；相 3：再循环 24 tick 后销毁：78 帧 |
| obj_Effect_FireBomb2（165） | effProcFireAndBomb2（同一段，`+0xac == 9` 分支 `0x41627b`） | 同 FireBomb，另在第 12 次调用时以两次 `0x415c10(x, y, 164, 16, 8, 0／12, 2, 6)` 抛 2×6 颗 Spray 光球：80 帧、16 个实例 |
| obj_Effect_Fire_Spray（163，FIR03） | effProcSprayUpDown `0x4162e6` | 角度 = (rng & 0x7f) + 128，近水平时拉回 16，与上一颗（全局 `0x4c1a9c`）差 <4 时再转 32；速度 (rng & 0xf000) + 2.125 px；每 tick 重力 +1/8 px 到 4 px 封顶；八张走完即销毁 |
| obj_Effect_Fire_Spray（164，FIR04，obj_Zoom 2.0） | effProcSpray `0x416409` | 任意角度（同样的 4 步间隔），速度 (rng & 0x1f000) + 2 px，匀速；七张走完置 engMIX 淡出 16 级 |

独立模型（`_effect_motion_model.verify`，`hsl check effect_motion` 执行）用 global.obs 模板与已跟踪的原版 cos／sin 表（`command_menu/native_layout.json`）重算三棵树，要求与原生轨迹完全相等；消融（FlyDrop 横向偏 1 px）→ `instance 0 model track differs from native`。

### 原生执行（`hsltools/probes/effect_motion.py`）

- 每个法术对象一台 unicorn：原点 (320,240)、镜头 (0,0)、RNG 取映像初值（`0x4c1e8c = 1` 不按时钟播种）；根对象按解释器的方式创建（基点 = 原点），然后逐帧执行 §2 的帧模型直到全部对象销毁。
- 原指令执行的范围只有对象内读写、RNG 与纯几何（`REVIEWED`：`0x4010c0`、`0x401220..0x401307`、`0x415c10..0x4231ae`、`0x42dc50`、`0x42dcb0`、`0x458c10`、`0x45e485`、`0x45e575..0x45ed46`、`0x46e0f0`、`0x46e720`）；创建／销毁、放声（记录）、堆、形状名表 `0x45fc01` 与 SHP 原点／尺寸 `0x4606a9`（读 hsl.pak 的 SHP 头）由 Python 应答；遇到其它地址即停下，对象列入 `unrestored` 并写明卡在哪个函数。
- 随机：每个根对象另以 3 个固定种子（`seed(k)`，与 objcomd_motion 同式）各跑一次，轨迹与种子 0 不同的存进 `variants`（86 个对象有变体）。
- 每个对象再以位移 (37,−23) 跑一次，比较得出 `motion`：`translates`（114：整体平移）、`anchored`（3：由原点驱动，位移无关）、`mixed`（3）与 `reshaped`（11）——后两类在重制里按平移处理（provisional，替换证据是各程序对基点的逐条读法）。
- 残影对象 179（obj_Shadow_Left，定义在关卡 OBS，取 `obj-051.obs`）由 `0x401220` 复制父对象当前形状、模式 `| engMIX`、层级 6，defProcShadowLeft `0x4010c0` 每 4 tick 层级减一，到 0 销毁（24 tick）——施法引导的残影也是它（见 [ANIMAL 程序包 §8](animal_program_execution.md#8-施法引导程序m_actions_action的解释)）。

### 施法引导的残影与换边镜像（cast-afterimage）

- **残影** `0x401220(obj)`：以 `0x45e307(x, y, 179)` 在对象当前位置建 obj_Shadow_Left，复制形状 `+0x30` 与缩放 `+0x20／+0x24`，模式 = 父模式 `| engMIX`，层级 `+0x28 = 6`，`+0x90 = 0x40004`，并清掉创建跳画位（`0x401269`）——创建那一帧就以 6/16 画出。defProcShadowLeft `0x4010c0` 首次调用只清初始化位，之后 `+0x90` 低字每 4 次归零重装、层级减一，到 0 销毁：共 24 帧、层级 6→1。
- 施法引导（`0x401c20` 的 m_action／s_action）里两处留残影：aniSetXYDisp（`0x402180`）作为这一次 call 的首条指令时，先在对象原地（(320,240)，横幅第 0 张）留一个再加位移（`0x402187`）；子状态 1 每张局部图的停留到期且还有下一张时，在局部图锚点留该张（`0x402b68`，层 0x33），然后换下一张。
- **换边镜像** `0x446be0(actor)`：读演员 live 记录 `+0xa0` 的 bit 8——构造 `0x407ec0` 在放置对象 obj_Data9≠0 时置位（与 pmPlayer↔pmEnemy 互换同一条件）。为真时引导对象初始化把 x 缩放设为 −1（`0x401ddf`），aniSetXYDisp 的 x 位移取反（`0x4021b8`）：横幅左右翻转、从另一侧滑入；局部图与肖像由 `0x4024d3` 按 aniInsertCastObject 的位移符号定边，不读此旗。
- 重制：`AnimalCastLead.compile(program, panels, mirrored)` 的每个状态带 `afterimages`（张、锚点、层级、是否镜像）与 `mirrored`；`BattleCombatCutin.show_cast_lead` 画横幅翻转与各残影（透明度 = 层级/16，engMIX 交叉淡化）；`cast_lead` 读单位 `side_swapped`（`hsltools/levels/battle.py` 按 obj_Data9≠0 写入 18 场里的相关单位）。`run_animal_program_tests.cast_lead_afterimages_and_mirror` 按上述常数独立算出并逐 call 断言；消融：去掉横幅残影 25 条失败、去掉局部图残影 8 条失败、镜像不取反位移 1 条失败。
- provisional：残影与活动面板的先后（同层链表顺序）；残影用 Godot 普通透明混合近似 RGB565 16 级交叉淡化。

### 4b. 普通切入的换边镜像（cutin-mirror）

`0x446be0(对象)` 取对象 `+0xac`（所属演员）的记录号 `+0xa4`，读 `[0x4c1bc8 + 号×0x1fc + 0xa0] & 8`——即记录 `+0xa0` 的掩码 8 位。全 EXE 只有 6 处调用，5 处在攻方对象 `0x401c20`、1 处在守方对象 `0x4038a0`，特效脚本对象（effProc*／specCode）不读它：

| 调用点 | 读法（static-derived） |
| --- | --- |
| `0x401dd1`（攻方 init，`0x401dc0` 起） | 三种 kind（`+0xa4` 字：0 普攻、1 m_action、2 s_action）都走这段：`0x45e525` 装演员形状后，为真 → `+0x20 = 0xffff0000`（x 缩放 −1.0）、`+0x24 = 0x10000`、模式 `\|= 0x8000000`（缩放绘制）。**普通攻击的攻方整段镜像**，不只施法引导 |
| `0x4021a8`（aniSetXYDisp `0x402180`） | 为真 → x 位移取反（`0x4021b8 neg`）再加到 `+0x04` |
| `0x4021fa`（aniInsertAttackFlash `0x4021df`） | 为真 → `ebx = 1` 作为 `0x401310` 的第 5 参；刀光位置 = 攻方 `(+0x04 + xdisp, +0x08 + ydisp)`，**xdisp 不取反**（`0x402231..0x402240` 原样相加） |
| `0x4022e4`（op 3 aniSetAddSpeed `0x4022cb`）、`0x402369`（op 4 aniSetSubSpeed `0x402350`） | 为真 → 方向角经 `0x45e785` 左右反射：`(0x80 − 角) & 0xff`（0 为 +x），写 `+0x98` |
| `0x4044ae`（守方 init） | 为真 → `+0x20 = 0xffff0000`（esi 自入口 `0x4038be` 装入）、`+0x24 = 0x10000`、模式 `\|= 0x8000000`，并把受击位移旗 `+0xa2` 1↔2 互换（aniKRight↔aniKLeft，`0x4044be..0x4044f1`）；为假 → 清 `0x8000000`。随后 `0x404539` 按互换后的旗做 −50／+30 起站偏移，命中击退（`0x40401b`）与落空闪避（`0x4041ec`）也读这一旗——换边受击者起站、击退、闪避全反向 |

- **`0x401310(父, x, y, 形状, 镜像)`**：`0x45e307(x, y, 0xb2)` 建击中／刀光对象，`+0x30／+0x32 = 形状`、`+0x88 = 父`；镜像非零 → 同样 `+0x20 = 0xffff0000`、`+0x24 = 0x10000`、模式 `\|= 0x8000000`。镜像参数**只翻帧，不动位置**。另一个调用点 `0x40418a`（守方命中时插入 `ANIMAL\ATTACK_FLASH00N.SHP` 按武器类的击中闪光，形状 `+0x86` 由 `0x4043a5` 装）传的镜像是「守方侧位恰为 pmPlayer」（`0x40ba20 == 0x10000`），不是 `0x446be0`。
- **刀光对象 178 obj_Attack_Flash 的过程 defProcAttackFlash `0x401140`**（过程表 `0x477c2c` 第 25 项）：不读父对象、不改位置，所以位置就是创建点。首次调用清初始化位、模式 `|= 0x24000000`（engADDCOLOR_MIX）、层级 16、`+0x90 = 10`、`+0x94 = 0x20002`；之后先停 10 次调用，再每 2 次调用层级减一到 0（32 次），然后 `+0x8c = 1`、再等 12 次调用清父 `+0x88` 并自删——攻方 phase 101 等的就是这一刻（顺带读出，重制的 0.12 s 白闪未改）。
- **x 缩放 −1 的画法**：`0x46b6e4` 显示表消费者对带 `0x8000000` 的记录走 `0x461982`；它按 SHP 行段逐段把段内 x 偏移乘 x 缩放再加锚点 x，缩放为负时走 `0x461b76` 分支——**以锚点为轴左右翻转**（与 Godot `scale.x = −1`、`offset = −原点` 相同）。
- **aniSetZoom 丢镜像**：`0x402476` 把参数同时写 `+0x20` 与 `+0x24`（正值），镜像对象执行 aniSetZoom 后不再翻转。ANIMAL.TXT 里用 aniSetZoom／速度指令的 action 只有 004／006／007（缩放）与 002（速度），都不是换边单位。
- **位怎么来**：构造 `0x407ec0` 在 obj_Data9≠0 且 PLAYERS mode 恰为 pmPlayer 或 pmEnemy（真的互换）时 `or 8`（`0x407fc3`），其他 mode 不置位；脚本 `0x450710` actSetPlayerMode 每次调用先 `xor 8`（`0x45073c`）再比较新旧 mode——**翻转**，模式不变也翻（[阵营位包](original_player_mode_sides.md)）。
- 重制接入点：`CutinLayout.side_swapped`／`k_action(row, swapped)`，`BattleCombatCutin._set_frame(…, mirrored)`（普攻、借用演出）、`SkillEffectScriptPlayer._stand`、`MoonDancePresentation` 的守方帧；`WinfailActions._apply_player_mode` 翻位。守方的 ATTACK_FLASH 击中闪光重制未画，其镜像读法随之未接。

### 四个运行时助手（static-derived）

| 地址 | 读法 | 探针怎么执行 |
| --- | --- | --- |
| `0x460541(n)` 合成形状槽 | 从形状表 `0x4abf28` 第 0x1f3f 项往下找 **n 个连续空槽**，返回最低一格，同时压低水位 `0x4a4218`；本身不画东西。十个调用点（效果程序九处＋`0x4017da`）都是同一套路：`0x460541` → `0x4602d4(ctx, 形状, &宽, &高, &原点x, &原点y, &色键)` 把源形状解成 16 位位图（读 SHP 头 `+0x14／+0x18／+0x1c／+0x20／+0x10`）→ 逐槽 `0x45f141(角, 宽, 高, 行距, 位图, 原点x, 原点y, 色键, 槽)` → `0x45f4b9(60)` 重置帧节拍器 → `0x457c20` 释放位图 | Python 应答：槽号取合成区 `0x8000+`，记下（源成员, 角度）|
| `0x45f141` 旋转写槽 | 取 `cos／sin(−角)`（表 `0x4a35fc／0x4a39fc`）把四角绕 `(原点x, 原点y)` 转 **+角/256 圈**（y 向下，屏幕上顺时针）求外框，逆映射逐像素取样，编成新形状写进槽 `[0x4abf28＋槽×4]`；原点保持在枢轴 | Python 应答：记录角度；`0x4606a9` 查询合成槽时按转后外框回答 |
| `0x415d20` | `0x46075b` 释放合成槽，清缓存 `0x4c6360`（10 dword）与计数 `0x4c1aa4`——同一法术的几个对象共用第一次合成的结果 | 原指令执行；`0x46075b` Python 空应答 |
| `0x4607f9(模式, x, y, 形状, 平面, 层级, 0…)` 自绘 | 把参数写进绘制块 `0x4bbb9a..`，形状表项非空时交 `0x461479` **立即排进本帧显示表**——对象自己多画一张，与自身形状字无关 | Python 应答：每次调用记成 `drawn_now` 伪实例的一帧（EarthRoundBall、EarthUpBall）|
| `0x46164b(相位, 行相位步, 帧相位步, 每步行数, 振幅)` 屏幕波纹 | 只写 `0x4c08c4..0x4c08d4`（相位为负时不改），`0x4c08d8` 清零（`0x46163a` 置 1、`0x461645` 读）；`0x461687` 每帧 `相位 += 帧相位步`，再对 `[0x4bfc44]` 行逐行写位移表 `0x4bfcc4`：每 `每步行数` 行 `相位 += 行相位步`，位移 = `sin[相位]×振幅 >> 16`（相位 64 取 66）| 原指令执行（行数取 480）；参数变化记 `ripple` 行。IconBGSet 两帧就自删，参数留在全局 |
| `0x43bf30(对象, 旗)` 镜头跟随 | 旗非 0：`0x46be92(x−320, y−192)` 立即定位；旗 0：首次把目标 `clamp(x−320, 0, [0x4c0958])`／`clamp(y−192, 0, [0x4c095c])` 存到 `+0x86／+0x84` 并置 `+0x80` 的 0x8000 位，之后每次以 `0x45e80d` 朝目标走 32 px（`[0x4c1b00]&0x4000000` 时 16，`[0x4c6390]&0x600` 或 `[0x4c1d78]` 时再 +12），差量经 `0x42dc50` 加进滚动累加；到位返回 1 并清位。帧体 `0x42d600` 在 `0x45f5f7` 之后以 `0x46bede` 把累加加到镜头并夹在地图内 | 原指令执行；镜头起点居中于原点 (0, 48)、边界 4000；每帧镜头相对起点与累加记 `camera` 行（OtherBBall1 266 行）|

复原状态（原先未复原的 13 个对象）：

| 对象 | 程序 | 卡在 | 现状 |
| --- | --- | --- | --- |
| AirSmoke2 | effProcAirSmoke1 | `0x460541` | 原生：AIR09_04 按 8/256 圈一格合成 32 张，每张停 5 tick 转动，engZOOM 从 1/8 放大 |
| EarthUpBrk | effProcEarthUpBrk | `0x460541` | 原生（mixed，按平移放置）|
| MindDish1／MindDish2 | effProcMindDish | `0x460541` | 原生（旋转列）|
| MindWordDish | effProcMindWordDish | `0x460541` | 原生（旋转列）|
| OtherBall | effProcMindBall3 | `0x460541` | 原生；合成了 MIN30 的旋转张，本对象的轨迹里没有画到|
| OtherRotateBomb | effProcRotateBomb | `0x460541` | 原生（旋转列）|
| OtherWord3 | effProcOtherWord3 | `0x460541` | 原生（旋转列）|
| EarthRoundBall | effProcEarthRoundBall | `0x4607f9` | 原生，含 2 个自绘伪实例 |
| EarthUpBall | effProcEarthUpBall | `0x4607f9` | 原生，含 4 个自绘伪实例 |
| FireBGSet／IconBGSet1 | effProcIconBGSet | `0x46164b` | 原生（两帧、不画）；波纹参数已记，重制未画波纹 |
| OtherBBall1 | effProcOtherBig | `0x43bf30` | 原生（anchored）；镜头轨迹已记，重制未移动战场镜头 |

### 找到／复原／剩余

| 类别 | 数目 | 说明 |
| --- | --- | --- |
| 法术直接引用的 effProc | 84 | 另有 59 种子对象由这些程序抛出 |
| 全部复原 | 84 | 其所有对象都有原生轨迹 |
| 部分复原 | 0 | — |
| 未复原 | 0 | — |

重制里已没有走"静帧＋最短 48 tick＋24 tick 淡出"的法术效果对象；剩下的是轨迹已记、重制未画的镜头跟随与屏幕波纹（边界）。

### 声音：原生结果与静态计数

原生执行同时记录了每棵树放的全部声音。与 `special_effect_scripts.json` 的 `program_sounds`（静态计数）相比：FireBigHead、MindUBrkShp1..4、OtherGlass、WaterBeast 有 ±1～16 tick 的出入；MindBall、MindBeast、WaterBig1／2、WaterBigBall、WaterBigIce、OtherBBall2、WaterDrop、FireArray 的**子对象**各自放 obj_X1（原计数只看根对象，漏掉）。声音排程仍用静态计数，这些差异是 `effect-sound-timing` 的替换证据（见 [特效对象声音](original_effect_object_sounds.md)）。

## 重制接线

- `game/battle/scene/EffectObjectMotion.gd` 读原生轨迹并给出某帧的精灵（成员、偏移、加法／减法／普通、层级透明度、缩放）；`SkillEffectScriptPlayer.compile_effect` 给有轨迹的对象标 `native`，同一对象重复插入时轮换种子变体，寿命 = 所选变体的轨迹帧数，合成形状按 `angle` 列旋转（`sprites_at` 的 `rotation`），`_draw_native` 在插入 tick 起逐帧画整棵树；effInsertRandomObject 改为 §2 的折叠偏移与累加延迟。
- `skill_effects` 导入同时收下轨迹画到的成员（新导入 53 张子对象帧；hsl.pak 没有的 11 个列入 `missing_members`，与原有缺帧一样按系列循环，provisional）。
- 定向测试：`run_skill_effect_script_tests`（`native_motion_tracks`／`native_motion_drawing`／`effect_random_insertion`、改写的旧断言）、`run_support_magic_tests`（创建帧不画）、`run_battle_scene_runtime_tests._test_local_spell_layers`（風刃按原生存活区间取样）。消融：`tracked()` 恒假 → 2291 条失败；延迟改回独立随机 → 40 个种子的顺序断言失败；轨迹帧 +1 → "创建 tick 不画"失败。
- `game/battle/scene/EffectObjectMotion.gd` layout：native execution of 0x415dc0／0x4010c0 and the effProc* jump table 0x4231b0: positions, members, draw modes, levels, zooms; frame model of 0x45f5f7 — docs/evidence_packets/static_reverse/original_effect_motion.md
- `game/battle/scene/EffectObjectMotion.gd` timing：one sample per original tick from the object's creation; the creation-flagged first frame is not drawn — 0x45f5f7 skip bit 0x10000000
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_effect_motion.md`。

## 复现

`python3 tools/hsl.py check effect_motion skill_effects`（独立模型与原生轨迹逐样本比较；重生成需原作 hsl01.exe＋hsl.pak 与 unicorn：`ignored/venv/bin/python tools/hsl.py generate effect_motion skill_effects`）。

## 边界

- **随机样本**：每个根对象至多 4 个种子变体，重复插入轮换；原版所有实例共用一条 RNG 流，变体只是分布里的样本。
- **镜头跟随与屏幕波纹**：OtherBBall1 的 `camera` 行、FireBGSet／IconBGSet1 的 `ripple` 行已由原指令算出，重制不移动战场镜头、不画逐行波纹；波纹参数在对象自删后由谁关闭（`0x46163a` 的调用方）未读。
- **合成形状的画法**：重制把合成槽画成源 SHP 加 Sprite 旋转（先缩放后旋转）；原版先转位图再缩放，只在非等比缩放时有差，旋转取样的像素误差不证明。
- **特效原点**：已读（[地图普攻与受击包 §1](original_map_strike.md#1-结论)）：eff_proc_Local 取目标对象 `(+4, +8)`（`0x443087`），即目标格中心、无 y 偏移；eff_proc_Global 取光标格中心（`0x442d81`）。录屏"高约 14 px"量的是脚下，换算到锚点约 2 px。
- **±1 帧**：真实平面链顺序与探针不同时，子对象首帧可能早／晚一帧；有插入延迟的对象在原版里首个可见帧比根对象早一帧（创建帧的跳画位在等待期间已清）。
- **缺帧**：程序画到 hsl.pak 没有的 SHP 名（如 EAR24_05..10、FIR07_03..07）时原版取的是注册表里的下一个名字，注册表内容未读；重制循环系列里已有的成员。
- **镜头**：探针按帧体把滚动累加加到镜头；只有 OtherBBall1 写镜头，其余 143 个对象都没有写；地震类程序对镜头的作用不在本包。
- **不支持的结论**：不证明像素级混合与原版一致（Godot 加法混合不是 RGB565 饱和加法）；不证明合成形状的逐像素外观；不证明特写绝技（defProcObjectMove／obj_Data7）的运动；不证明法术演出与伤害结算的先后。

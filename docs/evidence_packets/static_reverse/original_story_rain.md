# 剧情雨（mapobjDropRain 降雨BOSS 与 defProcDropRain 雨滴）

> evidence: static-derived: 站立物件过程 0x43ccf0 的 mapobjDropRain 分支 0x43d578、雨滴过程 0x43c4a0 与水波过程 defProcWaterWave 0x43c3f0 逐条静读; resource-derived: 帕尼西亞城　廢墟（開場預覽）（LEVEL010）与 巴瀚納海峽（開場預覽）（LEVEL012）OBS 的 降雨BOSS／雨 模板字段、global.obs 698 Wave_Up／699 Wave_Up2 模板、PROCESS.DEF plane 号、两关 WRD 水格数; provisional: 400 对象上限只数本发射器的雨滴与水波、每 tick 第一滴的陈旧栈字取自前一滴 · status: live · functions: 0x4300f0, 0x43c3f0, 0x43c4a0, 0x43ccf0, 0x43d578, 0x43dec0, 0x458c80, 0x45e28f, 0x45e307, 0x45e3ed, 0x45e77a, 0x45e785, 0x45eaa3, 0x45eb9d, 0x45ebdc, 0x45f5f7, 0x461982, 0x46c091 · updated: 2026-09-29

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 只读。tick 按 [tick 率包](../runtime_observations/original_tick_rate/README.md) 的设计值 16 ms 换算。

## 结论

- **密度**：每个 降雨BOSS 每隔 `rand(|lo − hi + 1|) + hi` tick 生一滴（obj_Data3 低字 lo、高字 hi）。帕尼西亞城　廢墟（開場預覽）（LEVEL010）`0x00020004` → 2–4 tick；巴瀚納海峽（開場預覽）（LEVEL012）`0x00020003` → 2–3 tick。进场第一 tick 就生一滴。全场活对象满 400 时不生（static-derived）。
- **落带**：落点 x 在镜头中心 ±(hi(obj_Data7) + 576)、y 在 ±(lo(obj_Data7) + 400) 内均匀取；LEVEL010 雨 obj_Data7 = 0 → ±576／±400，LEVEL012 雨 obj_Data7 = 640 → ±576／±1040（static-derived）。
- **落速与角度**：速度 `rand(Data4 − Data3) + Data3`（16.16 px/tick），角度 `rand(Data6 − Data5 + 1) + Data5`（256 等分，0 右 64 下）；两关角度都是 80–84（向左下斜）。LEVEL010 速度 7.5–9.5 px/tick（分量 −2.9..−4.5, +6.6..+8.8），LEVEL012 9.5–12.5（−3.6..−5.9, +8.4..+11.5）（static-derived）。
- **轨迹与寿命**：起点是落点沿反方向推回 80 tick 的路程（LEVEL010 右上 229–358, 530–703 px），落 80 tick 到落点（整数步进累计，终点比落点偏左上 1 px）；落地后原地 14 tick 淡出再删。一滴共 94 tick（static-derived）。
- **帧**：生出时从三帧里随机取一帧，终生不换（static-derived）。
- **画法**：engADDCOLOR_MIX，层级从生出那一 tick 的 1 每 tick 加 1 到 16 后改普通加色；落地那 tick 层级 14，之后每 tick 减 1，到 0 删（static-derived）。
- **深度**：`+0xc = max(0x4300f0(槽), 5)`。第一次调用的槽是落点 y（按落点行桶，5..23）；之后的调用槽是未初始化的栈字，对象执行器紧循环里它是上一个对象过程留下的——上一滴步进写入的 dy（< 16 px）——所以落下期间恒为桶 5：视口第 0、1 行（桶 4／5）的单位先画、被雨盖住，桶 6 起的单位与站立物件压在雨上（static-derived；陈旧栈字为推导，未实测）。
- **藏起**：`[0x4c1b00] & 0x400000`（特写／状态窗）或 場景效果 关时 `+0x30 = 0xffff` 不画，照落照淡（static-derived）。
- **落水**：落地那 tick `0x43dec0(x, y)` 取落点地形字（`0x46c091`：格 = 像素 >> 5，无符号比较越界返回 −1；`0x43ded5` 见 −1 返回 0，越界不算水），`& 0x8000` 为真时在落点先后生 global.obs 698 Wave_Up、699 Wave_Up2（defProcWaterWave，planeEffect4），两者 `+0xc` 抄雨滴当 tick 的桶（static-derived）。
- **水波**：水波链 planeEffect4（47）在雨滴链 planeEffect6（49）之前跑，首调在下一 tick：engADDCOLOR_ZOOM、缩放 0.5、桶 −1（698）／+1（699）；之后每 tick 缩放 +0xc00（0.046875），`+0x7c` 数满 18 调后置 engMIX 层级 16，此后每 tick 减 1，到 0 删。创建那 tick 不画，共画 34 tick：19 tick 满加色（末一 tick 为 engMIX 16），15 tick 层级 15..1，缩放 0.5 → 0x20c00（约 2.05），以绘制原点为轴。水波过程不读 場景效果 与特写／状态窗位、不写 `+0x30`，雨滴藏起时水波照画（static-derived）。帕尼西亞城　廢墟（開場預覽）（LEVEL010）WRD 无水格（0／660），巴瀚納海峽（開場預覽）（LEVEL012）1392／2700 格是水（resource-derived）。

## 证据

### 降雨BOSS（站立物件 0x43ccf0，obj_Data9 = 13 → 跳表 `0x43d8c0` 第 12 项 `0x43d578`）

| 步 | 地址 | 做什么 |
| --- | --- | --- |
| 初始化 | `0x43d578..0x43d583` | `edi`（消息 & 0x20000000）非零：`+0x50 = 0`，`+0x30 = 0xffff`（BOSS 自己不画） |
| 计时 | `0x43d589..0x43d594` | `+0x50` 减 1，仍 > 0 跳公共尾 `0x43d76a` |
| 重装 | `0x43d59a..0x43d5c8` | `eax = word +0x94 − word +0x96 + 1`，`cdq／xor／sub` 取绝对值，`0x458c80(eax) + word +0x96` 写 `+0x50` |
| 上限 | `0x43d5cb..0x43d5d5` | `0x45e28f()` 读活对象数 `[0x4a19dc]`，≥ 0x190 不生 |
| 生滴 | `0x43d5db..0x43d5e8` | `0x45e307(0, 0, +0x98, 0)`：obj_Data4 模板，坐标 0，第 4 参 0 → 挂平面链表尾 |

`0x45e307` 不调过程，只置 `+0x80 |= 0xb0000000`（含初始化位 0x20000000）、挂链、`[0x4a19dc]` 加 1；雨滴 planeEffect6 在 BOSS 的 planeBG3 之后，同一轮执行器 `0x45f5f7` 就调到它。

### 雨滴初始化（defProcDropRain 槽 66 `0x477d34` → `0x43c4a0`，消息带 `0x20000000`）

| 步 | 地址 | 做什么 |
| --- | --- | --- |
| 1 模式 | `0x43c4ba..0x43c4dc` | `+0 |= 0x24000000`（engADDCOLOR_MIX），`+0x80` 清初始化位，`+0x28 = 0`（层级） |
| 2 帧 | `0x43c4d1..0x43c4fe` | `+0x30 += 0x458c80(+0x7a 帧数)`，`+0x32 = +0x30` |
| 3 速度 | `0x43c4e8..0x43c51c` | `0x458c80(+0x98 − +0x94) + +0x94`（obj_Data4 − obj_Data3 + obj_Data3） |
| 4 角度 | `0x43c508..0x43c544` | `(0x458c80(+0xa0 − +0x9c + 1) + +0x9c) & 0xff`（obj_Data6／obj_Data5），`0x45eb9d(角, 速, +0x34)`：`v = (tab·速) >> 16`，两轴小数清 0 |
| 5 落点 x | `0x43c549..0x43c586` | `h = movsx word +0xa6 + 0x240`，`r = 0x458c80(2h)`，`r > h` 时 `r −= 2h`，`x = r + [0x4c091c] + 0x140` |
| 6 落点 y | `0x43c550..0x43c5ae` | `h = movsx word +0xa4 + 0x190`，同折法，`y = r + [0x4c0920] + 0xf0`；`+0xa6／+0xa4` 改存落点 x／y |
| 7 寿命 | `0x43c5c8` | `+0xa8 = 0x50` |
| 8 回推 | `0x43c5d2..0x43c60e` | `0x45e785(角)` = `(0x80 − 角) & 0xff`（水平镜像），`0x45e77a` 对低字节取负 → `角 + 128`；`0x45eaa3(速·80, 角 + 128, &dx, &dy)`：`d = ((tab·距) 的 16..47 位) sar 16`；`+4 = 落点 x + dx`，`+8 = 落点 y + dy` |

### 雨滴每 tick（`0x43c611..0x43c75a`，初始化那次调用接着走）

| 步 | 地址 | 做什么 |
| --- | --- | --- |
| 深度 | `0x43c611..0x43c630` | `0x4300f0([esp+0x10])` 小于 5 取 5 写 `+0xc`；`[esp+0x10]` 只在初始化分支写（落点 y，`0x43c5b9`），否则是陈旧栈字 |
| 藏起 | `0x43c633..0x43c652` | `[0x4c1b00] & 0x400000` 或 `[0x477c14]` bit0 清：`+0x30 = 0xffff`；否则 `+0x30 = +0x32` |
| 落 | `0x43c658..0x43c69c` | `+0x8c == 0`：`0x45ebdc(+0x34, &dx, &dy)`（`&dy` 即 `[esp+0x10]`），`x += dx`、`y += dy` |
| 淡入 | `0x43c691..0x43c6a6` | `+0x28 < 16` 加 1，否则 `+0 &= ~0x20000000`（去 engMIX，普通加色） |
| 落地 | `0x43c6ac..0x43c6e3` | `+0xa8` 减 1，≤ 0：`+0x8c = 1`、`+0 |= 0x20000000`、`+0x28 = 14`，`0x43dec0(x, y)` |
| 水波 | `0x43c6ef..0x43c735` | 水上：`0x45e307(x, y, 0x2ba, 0)`、`0x45e307(x, y, 0x2bb, 0)`（x、y 为本 tick 步进后的位置），两者 `+0xc` 抄雨滴的；698 未建成时不建 699 |
| 淡出 | `0x43c73d..0x43c74b` | `+0x8c ≠ 0`：`+0x28` 减 1，≤ 0 `0x45e3ed` 删 |

陈旧栈字：`0x43c4a0` 的局部 `[esp+0x10]` 在入口 esp 下 8 字节；执行器 `0x45f62d..0x45f65f` 逐对象 `push 标志; push 对象; call; add esp, 8`，中间不调别的函数，同一地址留着上一个过程写下的值。上一滴落下时经 `0x45ebdc` 把 dy 写在那里；淡出中的雨滴不写。

`0x4300f0(y) = clamp(((y + 16) >> 5) − ([0x4c0920] >> 5), 0, 19) + 4`；`0x458c80(n)`：0 返回 0，≤ 0xffff 取 `(0x458c10() & 0xffff) idiv n`，更大无符号取模——全局流 `0x4795d4／0x4795d8`。

### 水波（defProcWaterWave 槽 62 `0x477d24` → `0x43c3f0`）

模板（global.obs，resource-derived）：698 Wave_Up `MAGIC\WAVEUP001.SHP`（原点 18,14）、699 Wave_Up2 `MAGIC\WAVEUP002.SHP`（原点 18,0），各 1 张，planeEffect4，obj_Shape_Delay 18（`+0x7c`），obj_Data6 `0x00000c00`（`+0xa0` 缩放步长），obj_Data7 −1／+1（`+0xa4` 桶修正）。PROCESS.DEF：planeEffect4 = 47，planeEffect6 = 49，defProcWaterWave = 62。

| 步 | 地址 | 做什么 |
| --- | --- | --- |
| 首调 | `0x43c3f0..0x43c433` | 消息 & 0x20000000：`+0 |= 0x0c000000`（engADDCOLOR_ZOOM），`+0x80` 清初始化位，`+0x20 = +0x24 = 0x8000`，`+0xc += +0xa4`，返回 |
| 放大 | `0x43c434..0x43c450` | 之后每调 `+0x20`、`+0x24` 各加 `+0xa0` |
| 满色 | `0x43c46f..0x43c493` | `+0x8c == 0`：字 `+0x7c` 减 1，≤ 0 时 `+0x28 = 16`、`+0 |= 0x20000000`、`+0x8c = 1` |
| 淡出 | `0x43c455..0x43c46e` | `+0x8c == 1`：`+0x28` 减 1，≤ 0 `0x45e3ed` 删 |

调度：`0x45e307` 按模板 `+0xc`（obj_Plane）挂进该 plane 链尾（`0x45e37f..0x45e3b2`），置 `+0x80 |= 0xb0000000`。`0x45f5f7` 第一遍按 plane 0..max 逐链调过程（`0x45f62d..0x45f633` 先取下一节点再调），planeEffect4 链早于雨滴的 planeEffect6 链，落地 tick 新挂的水波这一遍调不到，首调在下一 tick；第二遍 `0x45f716` 见 `0x10000000` 清位跳过，创建那 tick 不画。第二遍只跳 `0x10000000` 与 `+0x30 == 0xffff`（`0x45f716..0x45f733`）；水波过程全程不读 `[0x477c14]`、`[0x4c1b00]`，也不写 `+0x30`，所以 場景效果 关、特写或状态窗期间照画。

画法：`0x0c000000` 位 25–26 非零，`0x46b6b1[6]` = 种类 9（`0x462e8b`，饱和加法缩放版），带 `0x8000000` 走 `0x461982`；置 engMIX 前不走层级分支，`+0x28` 的创建初值不起作用，满加色；置位后同种类走层级分支（[地图姿势飘字](../runtime_observations/map_pose_floaters/README.md) 第 4 节）。`0x461982` 把形状行段偏移乘缩放再加锚点，以绘制原点为轴缩放（[效果对象运动](original_effect_motion.md) x 缩放一条）。

## 重制接线

`game/battle/runtime/StoryRainEmitter.gd`：`StoryEffectObjects.insert` 为每个 降雨BOSS 建一个，按 16 ms 累计 tick，每 tick 先走 BOSS 计时再按建立顺序走每滴；深度经 `ActorRuntime.depth_bucket`（`0x4300f0`）与 `bucket_z` 进行桶域，plane 取雨模板 obj_Plane；画法用 `AdditiveLevelBlend`（`alpha = 层级/16`）；藏起接 `BattleSceneStage._close_up_hidden`，場景效果 关时发射器照建照走，每 tick 读 `GameSettings.scene_effects_enabled()` 并入藏起判定（剧情中途切换即藏即现，位置连续）。落地查水走 `StoryEffectObjects` 建发射器时接的 `is_water`：`MapSceneConfig.world_to_grid`（floor，越界格不在表里按 0）取格，读 `TerrainEditRules.tiles(play_loop)` 的 `tile_id & 0x8000`；剧情专场没有 PlayLoop，读场景 terrain 资源的 WRD 字（`WrdTerrainTiles.load_tiles`，含 terrain_overrides）。水波是发射器内的 Sprite2D（`MAGIC\WAVEUP001／002.SHP` 按字节导入 `content/imported/hsl/shared/skill_effects/`，manifest 取 res_path 与 draw_origin），position = 落点、offset = −原点、scale 按 16.16 缩放字，满色段 alpha 1、engMIX 段 `AdditiveLevelBlend.alpha(层级)`，z 与雨滴同取 `bucket_z(桶, planeEffect4)` 并夹在 `CAST_LIFT_Z` 下；每 tick 顺序为 BOSS → 已有水波 → 雨滴，新水波挂尾、下一 tick 首调；不抽随机数、不读藏起判定。随机数用同一生成器 `0x458c10`／`0x458c80`（`DamageRandomStream.rand`）但走本场所有 降雨BOSS 共用的一份自有状态：原版抽的是全局流，重制的全局流是 PlayLoop 的 `global_rng`（时钟播种、不存档，AI、增援与脚本随机都抽它），演出去抽会挪动这些结果。

## 边界

- 400 对象上限原版数的是全场活对象，重制只数本发射器的雨滴与水波（每个 BOSS 同时最多约 47 滴，加上落水水波也远达不到）。各关种子 `content/generated/hsl/chapter01/battleNNN_seed.json` 把 698／699 标 unmatched 是因为 join 不读 global.obs 这两条，与导入无关。
- 淡出中的雨滴不写栈字（`0x43c73d` 跳过 `0x45ebdc`），雨滴按创建序排在链尾，所以淡出中的雨滴连同其后第一颗下落雨滴，深度槽都取自雨滴段之前那个对象过程留下的栈残值，原版为 max(桶(残值), 5)，残值未读；重制按桶 5（provisional）。多个降雨BOSS 同 tick 生滴时，原版先跑各 BOSS 计时再跑各新滴初始化，重制逐发射器「计时→生滴→步进」，抽取交错与原版不同。
- 原版每 tick 画一帧，重制按显示帧渲染、按 16 ms 累计 tick。

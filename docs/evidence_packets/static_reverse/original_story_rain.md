# 剧情雨（mapobjDropRain 降雨BOSS 与 defProcDropRain 雨滴）

> evidence: static-derived: 站立物件过程 0x43ccf0 的 mapobjDropRain 分支 0x43d578 与雨滴过程 0x43c4a0 逐条静读; resource-derived: 帕尼西亞城 廢墟（LEVEL010）与 巴瀚納海峽（LEVEL012）OBS 的 降雨BOSS／雨 模板字段; provisional: 落水水波模板 698／699 未导入不画、400 对象上限只数雨滴、每 tick 第一滴的陈旧栈字取自前一滴 · status: live · functions: 0x4300f0, 0x43c4a0, 0x43ccf0, 0x43d578, 0x43dec0, 0x458c80, 0x45e28f, 0x45e307, 0x45e3ed, 0x45e77a, 0x45e785, 0x45eaa3, 0x45eb9d, 0x45ebdc, 0x45f5f7 · updated: 2026-09-29

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 只读。tick 按 [tick 率包](../runtime_observations/original_tick_rate/README.md) 的设计值 16 ms 换算。

## 结论

- **密度**：每个 降雨BOSS 每隔 `rand(|lo − hi + 1|) + hi` tick 生一滴（obj_Data3 低字 lo、高字 hi）。帕尼西亞城 廢墟（LEVEL010）`0x00020004` → 2–4 tick；巴瀚納海峽（LEVEL012）`0x00020003` → 2–3 tick。进场第一 tick 就生一滴。全场活对象满 400 时不生（static-derived）。
- **落带**：落点 x 在镜头中心 ±(hi(obj_Data7) + 576)、y 在 ±(lo(obj_Data7) + 400) 内均匀取；LEVEL010 雨 obj_Data7 = 0 → ±576／±400，LEVEL012 雨 obj_Data7 = 640 → ±576／±1040（static-derived）。
- **落速与角度**：速度 `rand(Data4 − Data3) + Data3`（16.16 px/tick），角度 `rand(Data6 − Data5 + 1) + Data5`（256 等分，0 右 64 下）；两关角度都是 80–84（向左下斜）。LEVEL010 速度 7.5–9.5 px/tick（分量 −2.9..−4.5, +6.6..+8.8），LEVEL012 9.5–12.5（−3.6..−5.9, +8.4..+11.5）（static-derived）。
- **轨迹与寿命**：起点是落点沿反方向推回 80 tick 的路程（LEVEL010 右上 229–358, 530–703 px），落 80 tick 到落点（整数步进累计，终点比落点偏左上 1 px）；落地后原地 14 tick 淡出再删。一滴共 94 tick（static-derived）。
- **帧**：生出时从三帧里随机取一帧，终生不换（static-derived）。
- **画法**：engADDCOLOR_MIX，层级从生出那一 tick 的 1 每 tick 加 1 到 16 后改普通加色；落地那 tick 层级 14，之后每 tick 减 1，到 0 删（static-derived）。
- **深度**：`+0xc = max(0x4300f0(槽), 5)`。第一次调用的槽是落点 y（按落点行桶，5..23）；之后的调用槽是未初始化的栈字，对象执行器紧循环里它是上一个对象过程留下的——上一滴步进写入的 dy（< 16 px）——所以落下期间恒为桶 5：视口第 0、1 行（桶 4／5）的单位先画、被雨盖住，桶 6 起的单位与站立物件压在雨上（static-derived；陈旧栈字为推导，未实测）。
- **藏起**：`[0x4c1b00] & 0x400000`（特写／状态窗）或 場景效果 关时 `+0x30 = 0xffff` 不画，照落照淡（static-derived）。
- **落水**：落地那 tick 若落点地形字带 `0x8000`（水，`0x43dec0`），在落点生 obj_Water_Wave1／2（模板 698／699），深度抄雨滴的；两模板没有任何关卡导入，重制不画（provisional）。

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
| 水波 | `0x43c6ef..0x43c735` | 水上：`0x45e307(x, y, 0x2ba, 0)`、`0x45e307(x, y, 0x2bb, 0)`，两者 `+0xc` 抄雨滴的 |
| 淡出 | `0x43c73d..0x43c74b` | `+0x8c ≠ 0`：`+0x28` 减 1，≤ 0 `0x45e3ed` 删 |

陈旧栈字：`0x43c4a0` 的局部 `[esp+0x10]` 在入口 esp 下 8 字节；执行器 `0x45f62d..0x45f65f` 逐对象 `push 标志; push 对象; call; add esp, 8`，中间不调别的函数，同一地址留着上一个过程写下的值。上一滴落下时经 `0x45ebdc` 把 dy 写在那里；淡出中的雨滴不写。

`0x4300f0(y) = clamp(((y + 16) >> 5) − ([0x4c0920] >> 5), 0, 19) + 4`；`0x458c80(n)`：0 返回 0，≤ 0xffff 取 `(0x458c10() & 0xffff) idiv n`，更大无符号取模——全局流 `0x4795d4／0x4795d8`。

## 重制接线

`game/battle/runtime/StoryRainEmitter.gd`：`StoryEffectObjects.insert` 为每个 降雨BOSS 建一个，按 16 ms 累计 tick，每 tick 先走 BOSS 计时再按建立顺序走每滴；深度经 `ActorRuntime.depth_bucket`（`0x4300f0`）与 `bucket_z` 进行桶域，plane 取雨模板 obj_Plane；画法用 `AdditiveLevelBlend`（`alpha = 层级/16`）；藏起接 `BattleSceneStage._close_up_hidden`，場景效果 关时照旧不建发射器（画面等价）。随机数用同一生成器 `0x458c10`／`0x458c80`（`DamageRandomStream.rand`）但走本场所有 降雨BOSS 共用的一份自有状态：原版抽的是全局流，重制的全局流是 PlayLoop 的 `global_rng`（时钟播种、不存档，AI、增援与脚本随机都抽它），演出去抽会挪动这些结果。

## 边界

- 水波 obj_Water_Wave1／2（698／699）只见于 `OBJ-ALL.H` 的名字，各关种子 `join_status` 为 unmatched，重制不画、也不查落点地形。
- 400 对象上限原版数的是全场活对象，重制只数本发射器的雨滴（每个 BOSS 同时最多约 47 滴，达不到）。
- 淡出中的雨滴不写栈字（`0x43c73d` 跳过 `0x45ebdc`），雨滴按创建序排在链尾，所以淡出中的雨滴连同其后第一颗下落雨滴，深度槽都取自雨滴段之前那个对象过程留下的栈残值，原版为 max(桶(残值), 5)，残值未读；重制按桶 5（provisional）。多个降雨BOSS 同 tick 生滴时，原版先跑各 BOSS 计时再跑各新滴初始化，重制逐发射器「计时→生滴→步进」，抽取交错与原版不同。
- 原版每 tick 画一帧，重制按显示帧渲染、按 16 ms 累计 tick。

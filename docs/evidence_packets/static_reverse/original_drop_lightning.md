# 打人閃電（defProcDropLightn）：第 10 关的落雷

> evidence: static-derived; runtime-measured: 整镜像进 10 关跑 2 回合（8 次：种子 1–6 与三次改盘）的落雷时刻、镜头、落点、九格取人与伤害，42 处按抽前随机字逐值重算全对; resource-derived: PROCESS.DEF defProcDropLightn=67、OBJ-010 码 25、WINFAIL010 event 6／7; provisional: 落雷时的镜头：重制有窗口时取表现层当时的镜头（presentation_view），但在行动提交时读、原版在交接扫描时读；无窗口（headless 自动对局、套件）按刚结束行动者居中（0x43bf30 同式）取 · status: live · functions: 0x407230, 0x407800, 0x4084e0, 0x415dc0, 0x43bf30, 0x43c9d0, 0x43ca70, 0x43f288, 0x458c80, 0x45e307, 0x45e3ed · tools: hsltools/probes/_drop_lightning.py · updated: 2026-09-28

## 结论

- 原版 帕尼西亞城 · 廢墟中的雷雨（LEVEL010；场次见 [命名表](../../BATTLE_NAMES.md)）由 WINFAIL010 event 6／7 轮流触发，每 2 次交接落一道雷；落点是当时画面内均匀一点，九格各取占格单位、不分阵营、无命中率，中心 16..32、周围 4..16 伤害且劈不死人；`0x43ca70` 演出为满层级 11 帧、淡出 15 帧、到位后第 27 tick 结算、剧本在第 106／46 tick 继续（static-derived）。
- 整镜像 8 次运行的 42 处落点与伤害按抽前随机字逐值重算全对（runtime-measured）；重制 `game/sim/DropLightningRules.gd` 按此结算、`game/battle/scene/BattleDropLightningPresentation.gd` 按状态机演出（static-derived）。
- 差异：落雷时的镜头来源（有窗口取行动提交时的表现层镜头，无窗口按行动者居中）是重制读法（provisional）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。

### 规则（static-derived／resource-derived）

| 问题 | 原版 |
| --- | --- |
| 谁放 | STORY010 结尾挂上 event 6。WINFAIL010 event 6：`actTRUE` → `actPlaySound WAV\LIGHTN007.WAV` → `actInsertStoryObjectWait obj_Story_Level10_Lightn3,0,0` → `actInsertEventStatus 7`；event 7：`actTRUE` → `actInsertEventStatus 6`。两条都不含 `actExecWinFailProcess`，链结束不重扫（[扫描形状](original_round_display.md)），所以每次行动结束的扫描（`0x407510` → `0x44ee20`）轮流点 6、7：**每 2 次交接落一道雷**。码 25（OBJ-010）模板：打人閃電、`MAGIC\AIR14_01.SHP`、obj_Shape_Number 2、engZOOM 2×、planeEffect6、`defProcDropLightn`（PROCESS.DEF 67 → 过程表 `0x477c2c + 67·4 = 0x477d38` → `0x43ca70`）。全部剧本只有 WINFAIL010 插入它 |
| 间隔为何偶尔 3 | 雷的链（镜头滚动 + 10 + 16 + 20／80 tick）与下一名角色的行动并行；链还在跑时的交接扫描被剧情旗挡住、计数照加，那次 6／7 不前进。实测 5 个种子的落雷计数都是 1 3 5 8 10（第 5 次交接是紧跟落雷的玩家待机） |
| 落在哪 | 创建消息（`0x43ca8a`）：全局流 `rand(640)`，大于 320 的减 640（−319..320），加镜头 x 字 `0x4c091c` + 320；再 `rand(480)`，大于 240 的减 480（−239..240），加镜头 y 字 `0x4c0920` + 240——即**当时画面内均匀一点**（像素，不对齐格）。镜头字是表现层当时的位置：实测多数等于刚结束行动者按 `0x43bf30` 居中（x−320、y−192，钳在 `[0, 地图宽−640]`／`[0, 地图高−480]`），但行动者刚走完时镜头常在滚动途中（如 `[44,16]`、`[308,196]`） |
| 何时劈 | 状态 0 `0x43bf30(obj, 0)` 把镜头滚到以雷为中心，到位后抽全局流 `rand(obj_Shape_Number)` 定帧（AIR14_01 起两帧之一），在雷点装 `obj_Effect_FireBomb`（162）与 `obj_Effect_FireBomb2`（165）；状态 1 等 10 tick、置 `+0 |= 0x20000000`；状态 2 等 `+0x28` tick（模板 0 时取 16），形状字置 0xffff（不画）；状态 3 劈九格 |
| 劈到谁 | `0x43c9d0(x, y, lo, hi)` 共 9 次，顺序：中心 `(x, y, 16, 32)`，然后 (−32,−32)(0,−32)(+32,−32)(−32,0)(+32,0)(−32,+32)(0,+32)(+32,+32) 各 `(…, 4, 16)`。每格 `0x407800(x, y)` 取占格对象（像素 `>>5` 成格；阻挡优先、大体型按占地）；**不分阵营、没有命中率、不查免疫或飞行**，站上就劈 |
| 伤多少 | 找到单位时抽全局流 `rand(hi − lo + 1) + lo`：中心 16..32、周围 4..16。HP（record `+0xd8`）减后低于 1 时伤害改成 `HP − 1`、HP 置 1——**雷劈不死人**。伤害非 0 时 `0x4084e0(x, y − 48, 伤害, 0, 0, 0)` 装伤害数字对象（177）并 `0x407230` 受击闪示，计为命中；已是 1 HP 的单位伤害 0、不显示、不计命中 |
| 收尾 | 状态 4：九格有命中停 80 tick、否则 20 tick，到 0 清脚本等待指针 `*(+0xac)` 并删除自己，event 6 的链才走到 `actInsertEventStatus 7`。过程本身不放音效（音效是链里的 `actPlaySound`） |

### 演出（static-derived）

`0x43ca70` 全文（状态跳表 `0x43ccd8`，状态字 `+0x8c`；每 tick 由 `0x45f5f7` 调一次）：

| 时刻 | 原版 |
| --- | --- |
| 创建 | 初始化位 `0x20000000` 在时（`0x43ca7e`）：清位、形状字 `+0x30 = 0xffff`（不画）、抽落点（见上）、模式 `+0 |= 0x4000000`（engADDCOLOR，加色）、`+0x28` 为 0 时置 16、`+0x90 = 10`。模板（码 25）obj_Mode engZOOM、obj_Zoom 2.0，所以闪电按 2 倍、以 SHP draw origin 为锚画在落点像素 |
| 状态 0（`0x43cb2a`） | 每 tick `0x43bf30(obj, 0)` 把镜头滚向落点（x − 320、y − 192）；到位那一 tick：`+0x30 = +0x32 + rand(+0x7a)`（AIR14_01 或 AIR14_02；即回执的 `frame`）、状态 1，并在落点 `0x45e307(x, y, 0xa2, 0)`、`0x45e307(x, y, 0xa5, 0)` 装 obj_Effect_FireBomb（162）与 obj_Effect_FireBomb2（165）——两者都挂链尾、同一点；新对象当 tick 不画、下一 tick 起由 defProcEffectProcess1 走（运动、帧与寿命见 [效果对象运动包](original_effect_motion.md)：FireBomb 78 帧、FireBomb2 80 帧；前导 `0x415e1a` 放模板 obj_X1 `WAV\BOMB0004.WAV`） |
| 状态 1（`0x43cb8e`） | `+0x90` 每 tick 减一，到 0 那一 tick 置 `+0 |= 0x20000000`（engMIX，与加色合成 engADDCOLOR_MIX：`dst + src × 层级/16`，层级字 `+0x28`）并转状态 2。连同到位 tick，闪电以满层级画 **11 帧** |
| 状态 2（`0x43cbbd`） | `+0x28` 每 tick 减一（层级 15..1 各画一帧），到 0 那一 tick 形状字置 `0xffff`、转状态 3：闪电**淡出 15 帧**后消失 |
| 状态 3（`0x43cbe1`） | 到位后第 27 tick：九格 `0x43c9d0`（顺序、伤害见上）。每个伤害非 0 的单位：`0x4084e0(单位 x, 单位 y − 48, 伤害, 0, 0, 0)`——kind 0 红色伤害数字、hold 0、无等待者（[数字对象](original_tick_counts.md)）；再 `0x407230(单位)`——`+0x92 = 60`、`+0x98 = 0x300`，受击态：行动者过程 `0x43f288` 让它左右抖 ±1 px 60 tick，过程收尾 `0x4420ba` 期间换 SHAPEDEF `hit` 单帧、第 60 tick 回站立（读法见 [original_map_strike.md](original_map_strike.md)；与 [噴人沼氣](original_poison_gas.md) 同一函数）。九格返回值和非 0 时 `+0x90 = 80`、否则 20，状态 4，并在同一 tick 先减一 |
| 状态 4（`0x43cca7`） | `+0x90` 减到 0：`*(+0xac) = 0`（放开 `actInsertStoryObjectWait` 的脚本等待）、`0x45e3ed` 删除自己。所以从到位算起，剧本在第 27 + 80 − 1 = **106**（有命中）／27 + 20 − 1 = **46** tick 往下走；FireBomb 与抖动各按自己的寿命继续 |

过程本身不调放声函数；平面：闪电 planeEffect6、FireBomb planeEffect2。

### 整镜像实测（runtime-measured）

`tools/hsltools/probes/_drop_lightning.py`（诊断，不注册任务）借 `_enemy_level.run_level` 从 `0x42da60` 进 10 关、玩家回合一律待机，钩 `0x43ca8a`（创建：镜头字、抽前全局字、各演员像素）、`0x43cb14`（落点）、`0x43c9d0`／`0x43c9e4`（九格与取到的单位、抽伤害前全局字）、`0x43ca14`／`0x43ca30`（伤害抽取、写回 HP 与显示伤害）、`0x407510`（计数、镜头）。

| 种子（全局） | 改盘 | 交接 | 落雷时计数 | 命中 |
| --- | --- | --- | --- | --- |
| 1 1 | — | 12 | 1 3 5 8 10 | 第 4 道：actor035_1 周围格 roll 7 → 11，58→47 |
| 2 2 | — | 12 | 1 3 5 8 10 | 无 |
| 3 3 | — | 12 | 1 3 5 8 10 | 无 |
| 4 4 | — | 12 | 1 3 5 8 10 | 无 |
| 5 5 | — | 12 | 1 3 5 8 10 | 无 |
| 6 6 | 緹娜 hp 12 | 12 | 1 3 5 8 10 | 第 1 道：actor035_2 周围格 roll 11 → 15，58→43 |
| 6 6 | 緹娜 hp 12、actor035_2 hp 10 | 12 | 1 3 5 8 10 | 第 1 道：actor035_2 roll 11 → 15 截成 9，10→**1** |
| 1 1 | 緹娜 (18,15)、雷歐納德 (17,14) | 9 | 1 3 5 8 | 无（改盘后第一名行动者换了抽取，落点随之变） |

- 39 个落点（x、y）按创建时的全局字与本包公式重算全对；九格顺序与 lo／hi 每道都是上表顺序；3 次伤害 roll 按抽前全局字重算全对（`REPLAY ok=42 diff=0`）。
- 创建与伤害抽取之间全局流被别的对象抽过（镜头滚动期间），所以伤害 roll 要用钩子在抽前记下的字重算；重制在同一次扫描里连抽。

**落雷时的镜头从哪来**（种子 1–5 各 5 道、共 25 道）：原版 16 道的镜头字恰是某名角色按 `0x43bf30` 居中（x−320、y−192，钳在 960×704 地图内的 `[0,320]×[0,224]`），9 道在滚动途中（如 `[320,160]`、`[276,176]`、`[12,208]`）；落点相对镜头 x 4..607、y 25..465，都在 640×480 画面内。

## 重制接线

- `game/sim/DropLightningRules.gd`（rules：static-derived／runtime-measured 本包）：同一次扫描里连抽落点与伤害。
- `game/battle/scene/BattleDropLightningPresentation.gd`（layout／timing／audio：static-derived 本包）消费 `winfail_runtime.presentation_requests[].drop_lightning` 回执，规则已先提交；受击者经 `BattlePoisonGasPresentation.shake` → `MapHitState.begin` 换 hit 帧并抖 60 tick。
- 镜头：场景每帧（及每次 `step_ai_turn` 前）把 `BattleCameraController.logical_to_world(0,0)` 减网格原点写进 loop 的只读输入 `presentation_view`，`DropLightningRules.strike` 有它就当镜头（仍钳在地图内），回执记 `view_source: presentation`；headless 不写（自动对局不播镜头，写了只是停在开场的陈旧值：第 1 道 5 个种子全是 `[112,0]`），回退为刚结束行动者居中，回执记 `actor_centre`——LEVEL010 自动对局 5 种子 25 道全是 `actor_centre`、落点都在画面内，对应原版的多数情形。有窗口时取的是行动提交那一刻的镜头：玩家行动在走完之后提交，与原版交接时相近；AI 行动由 `step_ai_turn` 一次结算，此刻镜头停在上一名行动者的演出末尾，未原生对照。

## 复现

`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_drop_lightning.py --level 10 --seed 6 6 --turns 3 --set tina.hp=12 --set actor035_2.hp=10 --out ignored/droplightning/L010_s6.json`（每个种子约 2 分钟）。

## 边界

- 落雷时的镜头来源按上面「镜头」一条取（provisional），AI 行动一次结算的情形见同条。
- 探针 `_drop_lightning.py` 是诊断脚本，不注册任务。

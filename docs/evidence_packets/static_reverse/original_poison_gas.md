# 噴人沼氣（defProcPoisonGas）、地形毒与剧情 VM 的 actCheckNextSerialNumber／actUseItem／actInsertStoryObjectWaitPos／actSetPlayerNoAttack

> evidence: static-derived; runtime-measured: 整镜像进 32 关跑 1–3 回合（5 个种子）的喷气时刻、落点、中毒对象与状态字，43 处按抽前随机字逐值重算全对；进 15 关的地形毒 5 处中毒字逐值重算全对; resource-derived: PROCESS.DEF defProcPoisonGas=71、OBJ-032.OBS 码 20、WINFAIL032 event 9、ACTION.H token 值; provisional: 烟对象初始化的 12 次全局流抽取（每团 rand(5)、rand(77)×2、rand(0x8000)）重制在喷气那次结算里紧接 3 次 rand(3) 连抽，原版在下一 tick、其间可能插进别的对象的抽取；地形毒的 0x407230 受击态重制表现层未接 · status: live · functions: 0x406fe0, 0x407230, 0x407510, 0x407800, 0x409140, 0x409e40, 0x40e240, 0x411c40, 0x42c780, 0x43bf30, 0x43c260, 0x43c760, 0x43c7c0, 0x43f1c6, 0x441eb8, 0x4436f9, 0x4454a5, 0x446ad0, 0x446b90, 0x44fad0, 0x450390, 0x450840, 0x4525e0, 0x458c80, 0x45e307, 0x45eb9d, 0x45ebdc · tools: hsltools/data/winfail_coverage.py, hsltools/probes/_poison_gas.py · updated: 2026-09-28

## 结论

- 原版 拉格納沼地（LEVEL032，场次见 [命名表](../../BATTLE_NAMES.md)）的 WINFAIL032 event 9 每 4 次交接在 9 组坐标之一放一团噴人沼氣，毒中心格及周围 8 格上不免疫的任何单位；深淵之沼（LEVEL015）的 `0x200000` 地形格在行动收尾对非飞行、不免疫者施毒（static-derived；整镜像逐值重算 43/43、5/5，runtime-measured）。
- 重制 `game/sim/PoisonGasRules.gd`、`WinfailConditions.gd`（交接计数定时器）、`WinfailActions.gd`、`game/battle/scene/BattlePoisonGasPresentation.gd` 与 `BattlePlayLoop` 的地形毒收尾照此实现（static-derived）。
- 差异：烟团初始化的全局流抽取次序、受击抖动局部状态 6 的消费者未对齐（provisional）；item 252 经 `ItemResolutionRules.prepare` 的 dispatcher 等价未证（provisional）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。

### static-derived：噴人沼氣

| 问题 | 原版 |
| --- | --- |
| 谁放 | WINFAIL032 event 9：`actCheckNextSerialNumber,3` → `actInsertEventStatus,9`（自己重新挂上）→ `actInsertStoryObjectWaitPos,obj_Story_Level_PoisonGas,9,…` → `actExecWinFailProcess`。STORY032 开场挂上 event 0／1／9。码 20（OBJ-032.H）模板：噴人沼氣、`MAGIC\MIN20_01.SHP`、obj_Shape_Number 3、planeEffect6、`defProcPoisonGas`（PROCESS.DEF 71 → 过程表 `0x477d48` → `0x43c7c0`）。552／553／554 关的 OBS 也有同一模板，但全部剧本只有 WINFAIL032 插入它 |
| 多久一次 | `actCheckNextSerialNumber` 是**行动计数定时器**，不是安装次数上限：截止字 `0x4c1ad6` 为 0 时写成 `0x4c1ad4 + num`（16 位），`0x4c1ad4` 到截止值时条件成立并把截止字清 0。`0x4c1ad4` 是交接计数：`0x407510` 先扫胜负／事件（`0x408370`）再 `inc word [0x4c1ad4]`；新关复位 `0x42c6e2` 连同截止字清 0；存档 `0x42e308`／读档 `0x42e96c` 带着这两个字。所以 event 9 在第一次扫描时定下截止，之后每 4 次交接喷一次（喷完的重扫在本次交接的 +1 之后，截止＝c+1+3）；喷气链播放期间又有行动者交接（扫描被剧情旗挡住、计数照加）时那一次间隔是 5 |
| 喷在哪 | 位置由 `0x451ecf` 在 9 组坐标里抽一组（全局流 rand(9)，见下文 VM case 0x63）。对象状态 0 调 `0x43bf30(obj, 0)` 把镜头滚到以它为中心（x−320、y−192，钳在地图内）；到位后状态 1 抽两次全局流 `rand(65)`，大于 32 的折成 `32 − r`（−32..32），`(x + dx) & ~31`、`(y + dy) & ~31` 再 +16 得中心格像素。9 组坐标都是 32 的倍数，所以每轴落在原格或左／上一格各 32/65、右／下一格 1/65 |
| 毒到谁 | 中心格与周围 8 格共 9 次 `0x43c760(x, y, n)`，顺序：中心 n=5，然后 (−1,−1)(0,−1)(+1,−1)(−1,0)(+1,0)(−1,+1)(0,+1)(+1,+1) 各 n=3。每格 `0x407800` 取占格对象（阻挡优先、大体型按占地，同一大体型可被多格各毒一次），`0x446b90` → `0x40e240(actor, 0x800000)` 查 record `+0x18c & 0x800080`（avoid_poison 0x800000 与 0x80）为真就跳过；**不分阵营、没有命中率**，站上就中 |
| 施加什么 | `0x409140(record, n)`：`+0x24 |= 1`（中毒位）；次数 `t = min(4, 旧次数 + 1 + rand_d(n))`，比旧次数大才写（旧次数 ≥4 不变）；强度 `0x406fe0(16, 32)` ＝ `24 − rand_d(9) + rand_d(9)`（先抽的那个减），旧强度非 0 时取 `max(旧, (新+旧)/2)`。rand_d 是 `0x42c780`：把伤害流 `0x4c3044／0x4c3040` 换进生成器抽 `0x458c80`。字布局同[中毒公共规则](original_status_effects.md)：`+0x30` 低 16 次数、高 16 强度。随后 `0x407230(actor)` 写 `+0x92 = 60`、`+0x98 = 0x300`、`+0x80` 清 0x1000 置 0x800 |
| 演出 | 见下节「演出」：镜头滚到喷点 → 中心格心 ±38 px 3 团 SMOKE001 烟上飘淡出 → 九格有人中毒停 90 tick、否则 40 tick → 放行剧本并删除自己；中毒者左右抖 ±1 px 60 tick（不是变色闪烁）；不放音效 |

### static-derived：演出

`0x43c7c0` 是噴人沼氣对象每 tick 的过程，状态字 `+0x8c`：

| 段 | 原版 |
| --- | --- |
| 初始化 | 首 tick（`+0x80 & 0x20000000`）：清该位、置 0x100000，形状字 `+0x30 = 0xffff`（本体不画），`+0x92／+0x90` 存下安装点 x／y |
| 状态 0：镜头 | 每 tick 调 `0x43bf30(obj, 0)`，返回非 0（到位）才进状态 1。`0x43bf30` 把对象点对到视焦 (320,192)、逐轴 `min(step, 剩余/2)`、tol 4、钳在地图内，步长读法见[剧情镜头包](original_script_camera_scroll.md)。对准的是安装点本身（32 的倍数，不取格心），偏移在到位之后才抽 |
| 状态 1：烟 | 同一 tick 抽完两次偏移（上节）后循环 3 次 `0x45e307(cx, cy, 706, 0)`：`obj_Fire_Smoke` 装在中心格心像素 (cx, cy)，`+0xc` 抄自噴人沼氣（`+0xc` 是按 y 算的层内排序字，演员过程 `0x43f300` 用 `0x4300f0(y)` 写同一字），形状字 `+0x30 = 噴人沼氣+0x32 + rand(+0x7a)`（全局流 rand(3)）——OBJ-032 码 20 的 `MAGIC\MIN20_01.SHP`、`obj_Shape_Number 3`，即 MIN20_01／02／03 之一。706 模板（global.obs）：planeEffect4、自身形状 `MAGIC\SMOKE001.SHP` 1 张、延迟 3、`defProcFireSmoke`；模板与噴人沼氣都没有 obj_Mode。**MIN20 这一张从来画不出来**：新建对象带 `+0x80 \|= 0xb0000000`（`0x45e353`，含创建跳画位 0x10000000），创建那一帧不画；下一 tick 烟过程初始化把层级置 0（加法×0）；再下一 tick 起烟过程每 tick 写 `+0x30 = +0x32`，即 706 自己的 SMOKE001（见下行） |
| 烟对象（defProcFireSmoke） | PROCESS.DEF 70 → 过程表 `0x477d44` → `0x43c260`，与噴人沼氣无关联（噴人沼氣删自己时烟照走）。**初始化**（首次调用）：清 0x20000000、模式 `+0 \|= 0x24000000`（engADDCOLOR_MIX，[效果运动包](original_effect_motion.md)）、层级 `+0x28 = 0`；全局流依次抽 `rand(5)` → 保持 `P = +0x7c（obj_Shape_Delay 3）+ r` 存进 `+0x90`／`+0x92`；`rand(77)` 两次，大于 38 的折成 `38 − r`（−38..38 均匀），加到 x、y；`+0xc = 0x4300f0(y)`；`rand(0x8000) + 0x4000` 作速度，`0x45eb9d(0xc0, 速度, +0x98)`——角 0xc0 查表 cos 0、sin −65536，即 `vx = 0`、`vy = −速度`（16.16，0.25..0.75 px/tick 正上）。**每 tick**：`[0x4c1b00] & 0x400000` 或 設定選項 場景效果（`[0x477c14]` bit0）关时 `+0x30 = 0xffff`（不画），否则 `+0x30 = +0x32`（SMOKE001）；状态 0 层级 +1，到 16 进状态 1；状态 1 `+0x90` 减 1，到 ≤0 重装 P、层级 −1，到 0 即 `0x45e3ed` 删除（本 tick 不移动）；其余每次调用 `0x45ebdc` 走一步（小数累积，y 已移 `floor(−(k−1)·速度/65536)`，k 为创建后 tick）。可见：创建后第 2 tick 起层级 1..16 淡入（16 tick），再每 P tick 减一淡出，创建后第 `17 + 16P` tick 删除——P＝3..7 即 65..129 tick，常比 90／40 tick 的剧本停顿长 |
| 状态 1：等待 | 九次 `0x43c760` 返回值相加：非 0（有人中毒）→ `+0x98 = 0x5a`（90），否则 `0x28`（40）；进状态 2 |
| 状态 2：放行 | 每 tick `+0x98` 减 1，到 ≤0 时清脚本等待指针 `*(+0xac) = 0`（`actInsertStoryObjectWaitPos` 挂的等待，WINFAIL 链才往下走）并 `0x45e3ed` 删除自己。剧本共停：镜头 tick ＋ 1 ＋ 90／40 tick |
| 中毒者 | `0x43c760` 对站上的每名中毒者调 `0x407230(actor)`：`+0x92 = 60`、`+0x98 = 0x300`（低字节相位 0、高字节幅度 3）、`+0x80` 清 0x1000 置 0x800。行动者过程（敌 `0x43f288..0x43f2f4`，玩家 `0x4437bd..` 同构）在 `+0x80` 有 0x800 且无 0x1000 时每 tick：`+0x92` 减 1，到 ≤0 清 0x800 并把 x 放回 `(x & ~31) + 16`；否则相位 +1、大于幅度则变 −幅度，相位 ≥0 时 `x = (x & ~31) + 15`，否则 `+ 17`。即 60 tick 的**左右抖动**：相位 1,2,3,−3,−2,−1,0,… 周期 7 tick，4 tick 在格心左 1 px、3 tick 在右 1 px，第 60 tick 回格心。两分支都把本 tick 姿势量写成 6，过程收尾 `0x4420ba` 据此换 SHAPEDEF `hit` 单帧、0x800 清掉后回站立（[original_map_strike.md](original_map_strike.md)）——即受击态：hit 帧＋抖动。没有变色／闪白 |
| 音效 | 本过程与 `0x407230` 都不放音效 |

另：`0x409140` 还有两个调用者 `0x441f00`（AI 过程）与 `0x4454ef`（玩家过程），即下节地形毒，与噴人沼氣无关。

### static-derived：地形毒

| 问题 | 原版 |
| --- | --- |
| 何时 | 每次行动完成的公共收尾：玩家 `0x4454a5`（攻击／待机／用物品／给予／特殊技完成都到这里，[行动状态机](original_action_state_machine.md)）、AI `0x441eb8`。顺序：地形毒 → `0x80000` 格的宝箱检查（`0x4454f7`）→ 额外行动查询（`0x443a86`／`0x441f08`，`0x4c1cf0`）与中毒扣血 → `0x40b910` 状态倒计时 → 交接 `0x407510`。所以踩上当次就在同一收尾里扣第一次毒、倒计时一次；额外行动的前半次收尾同样查 |
| 查什么 | 行动者自己的像素 `+4／+8` 经 `0x411c40` 取地图格字（`[0x4c0928][(y>>5)·w + (x>>5)]`），`& 0x200000` 为真；非飞行（`0x446ad0`：record `+0xa0 & 1`）；不免疫（`0x446b90` → `0x40e240(actor, 0x800000)`：record `+0x18c & 0x800080`，同噴人沼氣） |
| 施加什么 | `0x407230(actor)` 闪示，然后 `0x409140(record, 3)`：与噴人沼氣同一施毒（次数 `min(4, 旧 + 1 + rand_d(3))`、强度 `24 − rand_d(9) + rand_d(9)`、已中毒取合并） |
| 标记从哪来 | 格字就是 WRD 文件体原样：加载 `0x46bb90..0x46bca6` 核对 `WORL` 后把 `宽·高·4` 字节直接读进 `0x4c0928`。导入器 [`wrd.py`](../../../tools/hsltools/sources/wrd.py) 的 `t`（低 24 位）已含该位，重制地形格 `tile_id` 原样保留。83 个已导入 WRD 里只有 LEVEL015（深淵之沼）有 `0x200000`：290 格，全部同时带 `0x8000`，集中在地图右半与中部沼地 |
| 谁会中 | 深淵之沼的敌人全免：038 飞行（`+0xa0 & 1`），037 与 033 的 `+0x18c` 含 avoid_poison `0x800000`（`0xa04000`／`0x804000`）；我方 克羅蒂 `+0x18c = 0x800200` 也免疫、雷特 飞行。其余我方成员停上去就中 |

### runtime-measured：地形毒（LEVEL015）

临时探针（钩 `0x441eb8`／`0x4454a5` 记行动者格字、飞行位、`+0x18c`，钩 `0x409140` 记伤害流两字与 `0x4454f4` 处写后的 `+0x24／+0x30`）进 15 关跑 1–2 回合。原盘（种子 1 1，57 次收尾）敌人多次停在毒格（037 原地待机、038 飞越）而 `0x409140` 零次调用；改盘把 緹娜／漢克斯／雷歐納德 放到毒格 (10,5)／(11,5)／(9,6)、雷特 放到 (12,5)（种子 1 1 注入伤害字 2027808452 174357、种子 2 2 注入 11 22）：待机收尾 5 次调用都来自 `0x4454f4`、n=3，写后字 `0x160001`／`0x160002`／`0x130001`／`0x130001`／`0x1c0002` 与中毒位 1 按调用前伤害流两字重算 **5/5 全对**；雷特（飞行）与停在 (13,4)（无标记）的 雪拉 不中。

### resource-derived＋static-derived：剧情 VM 其余三个 case

`ACTION.H`：actUseItem 93（0x5d，`code` `serial` `item id`）、actInsertStoryObjectWaitPos 99（0x63，`object code` `position count` `x/y pairs...`）、actCheckNextSerialNumber 100（0x64，`[number]`）、actSetPlayerNoAttack 101（0x65，`player id` `serial` `mode`）。剧情 VM bridge 是 `0x450840`：

| case | 原版 |
| --- | --- |
| `0x5d` actUseItem | 以 `code` `serial` 经 `0x44fad0` 找 actor，`0x450390(code, serial, 0)` 建立使用道具的等待阶段，再调 `0x409e40(actor, item_id)`；道具效果失败时 VM 只前进脚本指针，不把 item id 解释成别的 actor 或目标 |
| `0x63` actInsertStoryObjectWaitPos | 读 object code、位置数与位置表（世界／像素坐标，不是格），`0x451ecf` 经 `0x458c80` 抽一组，`0x45e307(x, y, object_code, 0)` 安装对象，并把脚本返回指针写入对象等待状态 |
| `0x64` actCheckNextSerialNumber | 上文的交接计数定时器 |
| `0x65` actSetPlayerNoAttack | 经 `0x44fad0(code, serial)` 找 player record，在 `PLAYER_TABLE + 0xa0` 清除或设置 bit `0x2`（no-attack，不是 undead bit `0x4`，也不改 mode） |

`0x409e40` 的既有静态范围只覆盖永久道具 253..261 的属性／抗性分支（[original_tactical_items](original_tactical_items.md)）；item 252 的恢复 HP、MP 与清状态字段来自 `ITEM.TXT`（resource-derived）。

### runtime-measured：噴人沼氣（LEVEL032）

`tools/hsltools/probes/_poison_gas.py`（诊断，不注册任务）借 `_enemy_level.run_level` 从 `0x42da60` 进 32 关、玩家回合一律待机，钩 `0x43c84d`（状态 1 入口，记全局流两字）、`0x43c8b4`（中心像素 ESI／EDI）、`0x409140`（调用者、record 的 `+0x24`／`+0x30` 前后与伤害流两字）、`0x407510`（计数字与截止字）。

| 种子（全局／伤害） | 回合 | 交接 | 喷气 | 喷气时计数 `0x4c1ad4` | 中毒 |
| --- | --- | --- | --- | --- | --- |
| 1 1／进关 | 1 | 25 | 5 | 5 9 14 18 22 | 023_8；023_2＋044_4（同一次） |
| 2 2／进关 | 2 | 48 | 11 | 5 9 14 18 … 46（其后每 4） | 023_3、023_8 |
| 3 3／进关 | 2 | 48 | 11 | 同上 | 044_4 |
| 4 4／注入 | 3 | 71 | 17 | 5 9 14 18 … 70 | 044_4（中心 n=5）＋023_6；023_4 |
| 5 5／注入 | 3 | 71 | 17 | 同上 | 044_4（n=5）、023_3、023_3 再中（0x110002→0x170004）、023_2、023_9、023_3 |

- 截止字：第一次交接前 0，扫描后 3；计数 3 的交接扫描成立（截止清 0），链开始后下一名行动者又交接一次（扫描被挡、截止仍 0、计数 5），链结束重扫定下 5+3=8。之后同理。
- 种子 4／5 的 34 次喷气中心、9 次中毒字，按钩子记下的抽前随机字用本包公式重算 **43/43 全对**（`REPLAY ok=43 diff=0`），含中心 n=5、重复中毒的次数封顶 4 与强度合并。
- 种子 1–3 的伤害流取进关时的时钟桩状态，6 次中毒全是 3 次、强度 24／25（低质量起点）；换注入的伤害字后次数 1–4、强度 16–25 都出现。

## 重制接线

- `game/sim/PoisonGasRules.gd`：落点、九格施毒与合并；`game/sim/WinfailConditions.gd`：交接计数定时器（`0x4525e0..0x45260b`）；`game/sim/WinfailActions.gd`：`actInsertStoryObjectWaitPos` 在 loop 的全局流 `global_rng`（`GlobalRandomStream`，原版 `0x4795d4`／`0x4795d8`）抽一次 `rand(count)` 选位置，收据记全局流前后两个字；`game/sim/WinfailCompiler.gd`：OBS 过程识别。
- `actUseItem` 解析唯一 `[SID, serial]` actor，调 `ItemResolutionRules.prepare`，提交到同一 loop 的 HP／status／inventory，记录 `item_requests`；缺 actor、catalog、inventory 或 item 显式记拒绝原因。
- `actSetPlayerNoAttack` 写单位字典 `no_attack`：玩家普通攻击命令与直接攻击结算都拒绝；魔法／特殊技与 AI 策略是独立能力。
- `game/battle/scene/BattlePoisonGasPresentation.gd`：镜头、烟团、停顿，中毒者经 `shake` → `MapHitState.begin` 换 hit 帧并抖 60 tick；`game/sim/loop/BattlePlayLoop.gd`：地形毒收尾顺序。

## 复现

`uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3 tools/hsltools/probes/_poison_gas.py --level 32 --seed 4 4 --damage-seed 2027808452 174357 --turns 3 --out ignored/poisongas/L032_s4.json`（需本机原版 EXE；首次建停点缓存约 20 s，之后每回合约 15 s）。

## 边界

- 烟对象初始化的 12 次全局流抽取在原版发生于下一 tick，其间可能插进别的对象的抽取；重制在喷气那次结算里紧接连抽。
- 地形毒（深淵之沼 LEVEL015）的 `0x407230` 受击态：规则回执 `loop.terrain_poison` 已写，表现层不消费，踩毒者不换 hit 帧不抖。
- 道具等待时序、安装对象渲染、packed serial 的完整边界与 no-attack 的全部 AI 分支未读。
- 552／553／554 关的 OBS 也有噴人沼氣模板，但全部剧本只有 WINFAIL032 插入它。

# 脚本安装的入场、落点替代与离场收尾

> evidence: static-derived: 入场、落点替代与离场读法，0x44fbd0 在 LEVEL034／038／080 地图上原指令实跑; runtime-measured: 开局快照的走位单位格; provisional: 出生张延迟之后站立循环是否另有重载, 洪泛 mode 1 与重制无单位洪泛的对应、落点检查时机、链中有 Wait 时出生与后续落点的交错、剧情插入玩家的张延迟次序、开场生成器等距取格 · status: live · functions: 0x407cc0, 0x407ec0, 0x40d800, 0x40e870, 0x40ed50, 0x40f200, 0x40f440, 0x40f520, 0x411940, 0x4119d0, 0x413740, 0x413900, 0x43ede0, 0x446c40, 0x44fbd0, 0x450450, 0x450840, 0x453b90, 0x45e307, 0x45e525, 0x45e575 · tools: hsltools/levels/battle.py, run_all.gd, test_hsl_opening_positions.py · updated: 2026-09-28

## 结论

- 原版脚本安装没有入场态或出现帧序列：`actInsertObject`（`0x450840` case 0x12）构造（`0x407ec0`→`0x45e307` 复制 176 字节模板）后只调 `0x44fbd0` 修落点，单位在修好的格上直接出现；走入是脚本自己的 `actWalkPrevInsertObject*` 行（static-derived）。
- 落点替代 `0x44fbd0`：落格格字带单位／硬阻挡（`& 0x74000`），或地面单位落 0xff 格，才替代；以单位副本站在落格洪泛 12（地面 mode 1、飞行 mode 6），清掉中心，行主序取无单位格中曼哈顿最近者，等距按 `rand()&1` 替换，四邻硬阻挡 ≥3 时 `rand(100)<80` 跳过；无候选就留在原格。行走目的地同样经过它，随机位置插入不经过（static-derived）。
- 离场收尾：两台 VM 的 `actWalkAndDelete` 都进状态 0x36（`0x450450`），走到末格后与 `actDeleteObject`（0x35）同一收尾：engMIX 层级 16、每 tick 减一，16 帧由 16/16 淡到 1/16 后注销（static-derived）。
- 洪泛前 `0x4119d0(x, y, 0)`→`0x411940` 把落格格字只留低 12 位（高度 0、无旗标），所以地面单位落在 0xff 格时只能走到高差规则允许的邻格，周围 0xff 格一格也到不了；四邻全是 0xff 时无候选、留在原格。在原指令上跑 `0x44fbd0`：沙羅尼亞近郊（LEVEL034）037_3 终点 (38,20)→(37,20)、幽闇墳場（LEVEL038）034_2 (14,11)→(13,11)，与原版开局快照一致；飞行单位（雷特、038、041 等 PLAYERS `move_fly = 1`）落 0xff 不触发替代，留在终点（static-derived；runtime-measured）。
- 开场走位也照做：生成器 `script_landing` 对落在 0xff 终点的地面走位单位跑同一替代（LEVEL034 037_3、LEVEL038 034_2 改到原版格），飞行单位仍留终点。
- 安装时的随机数顺序：NPC（SID_ENEMY，`+0xa0 ≥ 0x14`）构造时不出生，`0x44fbd0` 的替代抽数在插入 token 当时就抽，出生抽数（`0x407cc0` 携带、`0x40e870` 调级）要等 VM 这一轮跑完、对象第一次 tick 才抽；只有 `SID_PLAYERn`（`+0xa0 < 0x14`）在构造里就出生、排在替代之前。重制一条事件链先落点、再按安装顺序做 NPC 出生（static-derived）。
- 出生张延迟：`0x407cc0` 先经 `0x446c40(obj, +0xa2, 0, 10)` 装站立循环（`0x45e525` 写 `+0x7c／+0x7e = 10`），再把 `rand(24)`（`0x407dba`，全局流）加到当前张停留计数 `+0x7c`；每 tick 的换帧 `0x45e575` 先减 `+0x7c`，所以第一张站立帧多停 0..23 tick，之后按重装值 10 每 11 tick 一张，各单位的站立动画由此错开。单位本身在出生当时就画出，没有出现延迟。两个调用者 `0x43eef6`（NPC 首 tick）与 `0x44343e`（玩家构造）都抽；开场 PLAYERS／EVEF 预置单位同样走这两条出生分支，也抽（static-derived）。
- 重制照做：`ScriptActorCreationRules.nearest_landing` 用同一度量与抽数，`BattleDepartureView` 逐 tick 阶梯淡出，剧情模式走完也淡出。差异：落点只在事件末对最终格检查一次（provisional）。

## 证据

**static-derived**（`hsl01.exe` SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 静态读）

| 地址 | 读法 |
| --- | --- |
| `0x450ec4`→`0x450ee2` | case 0x12：`0x407ec0(x, y, code)` 返回对象写 `0x4c1d38`（上一插入），随即 `0x44fbd0(obj, &obj+4, &obj+8)` 就地改坐标，然后回 VM 主循环 |
| `0x407ec0`／`0x45e307` | 构造只复制模板、写 `+4／+8` 坐标与 `+0x80 \|= 0xb0000000`，不写状态字 `+0x8c`；随后调该过程一次初始化。`0x453b90` 的脚本态只有 0x32–0x36（行走、滚屏、删除），没有出现态 |
| `0x450f55` | 随机位置插入：`0x407ec0(x + 表[pos], y + 表[pos], code)` 后直接跳回，不调 `0x44fbd0` |
| `0x44fbd0` 触发 | 坐标取格心 `(v & ~0x1f) + 0x10`；`0x411c40` 格字 `& 0x74000` 非零，或高字节 0xff 且 `0x446ad0`（模板 `+0xa0` bit0 飞行）为假，才进替代；否则原样返回 |
| `0x44fbd0` 替代 | 对象复制到伪对象 `0x4c3860` 并放到落格；落格格字暂置 0（`0x4119d0(x, y, 0)`→`0x411940`：`word = (word & 0xfff) \| 0`，高度与旗标清零）；`0x40f440(copy, 12, 飞行 ? 6 : 1)`；恢复格字；`0x40f520(0)` 清洪泛中心；`0x413900(x, y, 0, &nx, &ny)` 找到才写回坐标 |
| `0x40f200`／`0x40ed50` | 半径上限 50；mode 1 分支（`0x40f02a`）只被 `0x4000` 与高差 ≥3 挡，每步扣 `1 + 上坡附加`，不看单位阵营 mask；mode 6 只看 `0x4000` |
| `0x413740`（side 0） | 行主序扫洪泛缓冲；跳过未到达、`0x80` 位与格字 `& 0x70000` 的格；像素曼哈顿距离严格更小才替换，相等时 `0x458c10() & 1`；候选先过 `0x40d800(x, y, 0x4000)`：四邻中 ≥3 格带 `0x4000` 时 `rand(100) < 80` 跳过 |
| `0x44fbd0` 其他调用 | 行走 `0x44fcf0`／`0x44fd90`／`0x44fed0` 等（`0x44fd43`、`0x44fdf5`、`0x44fe83`、`0x44ff09`）、按 code／serial 行走 `0x450140`／`0x4501f0`、行走删除 `0x450450`（`0x450488`）都先修目的地 |
| `0x450450` 调用 | WINFAIL VM `0x450949` 与剧情 VM `0x452c97`（参数取自 `[ebp+0x94..]`） |
| `0x453ce0`（0x35）／`0x454286`（0x36） | 置 `+0 = 0x20000000`（engMIX）、`+0x28 = 16`；`0x453c7b`／`0x4542a7` 每 tick 减一，到 0 先推进 Wait 父对象再依次注销（见 [original_script_departure](original_script_departure.md)） |

### 安装时的随机数消费顺序

| 步骤 | 地址 | 全局流抽数 |
| --- | --- | --- |
| 1 构造 | `0x450ec4`→`0x407ec0`→`0x45e307`：复制模板，`+0x80 \|= 0xb0000000`，按第 4 参 0 接在同优先级链表尾（安装顺序即 tick 顺序） | 无 |
| 1a 玩家当场出生 | `0x40805d..0x40809e`：有记录（`+0xa4 ≠ 0`）且 `word [+0xa0] < 0x14`（`SID_PLAYERn`）时，构造里就以 `+0x80` 为调用字调一次对象过程；调用字带 `0x20000000`，玩家过程 `0x44341b` 清位后调 `0x407cc0` 再推等级 | 出生张延迟 `0x407dba` |
| 2 落点替代 | `0x450ee2`→`0x44fbd0`：替代时 `0x413740` 等距 `0x458c10() & 1`、拥挤 `rand(100) < 80` | 仅替代且等距／拥挤时 |
| 3 下一个 token | `0x450eea`→`0x4511e9`：不让出，直接取下一 token，直到 Wait 类 token 存 `+0x90` 返回 | — |
| 4 NPC 出生 | `SID_ENEMY`（`≥ 21`）构造里不调过程；第一次 tick 时敌方过程 `0x43ede0` 在 `0x43eed1` 见调用字 `0x20000000`，清位、`0x43eef6` 调 `0x407cc0`（张延迟、pmEnemy 携带 `0x407c86`），再 `0x43ef26` 调级 `0x40e870` | 张延迟、携带、调级 |

- 随机位置插入 `0x450f55`：构造后直接回 `0x4511e9`，无第 2 步，`0x45e307` 不抽随机；槽位洗牌 `0x451d0f` 在 opcode 106 token 当时抽，排在预置玩家第 1 tick 构造里的张延迟之后、其后插入的 NPC 出生之前（剧情 VM 从关卡对象第 2 tick 起才跑，见 [original_random_position](original_random_position.md)）。
- 开场 PLAYERS／EVEF 预置对象不经 `0x44fbd0`（见 [actor_placement_initialization](actor_placement_initialization.md)）；开场剧情里的插入与行走走同一 case 0x12／行走路径，按上表顺序。

### 出生 `0x407cc0` 内的张延迟

| 地址 | 读法 |
| --- | --- |
| `0x407d9a..0x407da9` | `0x446c40(obj, word [+0xa2], 0, 10)`：按职业形状表取第 0 组（站立）的起始张与张数，经 `0x45e525` 写 `+0x30／+0x32` 起始张、`+0x78／+0x7a` 张数、`+0x7c／+0x7e` = 10 |
| `0x407dae..0x407dbf` | `+0x90 = 0`；`push 0x18; call 0x458c80`（全局流 `rand(24)`）；`add word [+0x7c], ax`——只加当前计数，重装值 `+0x7e` 仍是 10 |
| 次序 | 张延迟在站位取整（`0x407d1a..0x407d4e`）与 `0x446c40` 之后、`0x40ba20`／`0x411a30`／`0x407660` 注册与 pmEnemy 携带 `0x407e3b`→`0x407c40` 之前；`0x40e870` 调级在 `0x407cc0` 返回后由调用者做 |
| `0x45e575` | 换帧：`dec word [+0x7c]`，非负不换帧；否则从 `+0x7e` 重载、`+0x30` 加 1、`+0x78` 减 1（见 [native_presentation_helpers](native_presentation_helpers.md)） |
| 调用者 | 全 EXE 只有 `0x43eef6`（敌方／NPC 过程首 tick）与 `0x44343e`（玩家过程，构造里调），都在调用字带 `0x20000000` 的初始化分支 |

engMIX 的层级混合见 [original_battle_end_flow](original_battle_end_flow.md)（字物件同一 `+0x28` 层级字）。

## 重制接线

- `game/sim/ScriptActorCreationRules.gd`：`nearest_landing` 按上表触发与挑选，洪泛前把落格改成高度 0、无旗标（`0x411940`）；洪泛用 `TacticalGridRules.movement_reachability_envelope`（不传单位，只剩地形与高差；飞行单位走飞行模式），候选排除占用格，挑选复用 `AINavigationRules.nearest_stoppable`（行主序、等距硬币、`0x40d800` 拒绝，mask `0x4000`）；抽数走战斗全局流，记入 `placements[].draws`。随机位置插入保留请求格。`_apply_status` 先对整条链落点（`_place_touched`），再按安装顺序做 NPC 出生（`_npc_birth`：携带、调级）；玩家出生（张延迟）在安装当时、落点之前。provenance 写 `rules: static-derived docs/evidence_packets/static_reverse/original_script_entry.md`。
- 出生张延迟：`InitialRosterGrowthRules.draw_frame_delay` 在全局流抽 `rand(24)` 写 `birth_frame_delay`；开场先给全部玩家（含承接成员）抽，再按阵容顺序给每个 NPC 依次抽张延迟、携带、调级；剧情插入的玩家在安装当时抽，NPC 在 `_npc_birth` 里先于携带抽；`BattleLoopScript` 的补兵同序。演出层 `BattleSceneStage.spawn_actor_node` 装站立后调 `ActorRuntime.delay_first_idle_frame`，第一张站立帧多停这么多 tick。
- `game/battle/scene/BattleScriptActorPresentation.gd`：安装行在提交格上直接显示，入场走位由后续行走行演出。
- `game/battle/scene/BattleDepartureView.gd`：`fade` 每 tick 把 alpha 设为 `(16 − 已过 tick)/16`，16 tick 后隐藏；`BattleOpeningCoordinator._settle_pending_deletes` 在剧情模式也调用它。

## 复现

`tools/godot.sh --headless --script res://tests/run_all.gd`（规则套件；`run_winfail_rules_tests.gd` 覆盖安装与走位收据）；`python3 -m unittest tools.test_hsl_opening_positions`（开场站位）

## 边界

- provisional：重制在整条事件末只对每个单位的最终格检查一次；原版在每个安装／行走 token 当时检查，中间格被占时落点可能不同。
- provisional：mode 1 洪泛与重制无单位洪泛在 `0x100000` 不可停格、3×3 起点八邻种子上的差别未逐格对照；3×3 角色另保留重制的全身合法性过滤（原版只查中心格）。
- provisional：链中插入之后还有 Wait 类 token 时，原版 NPC 在 Wait 让出后出生，Wait 之后的落点抽数排在出生之后；重制整条链先落点、后出生，这类链（WINFAIL005／010／012／015／017／019／021／030／031／032／040／052／901／902／904 各有一两条）只在 Wait 之后的落点有等距或拥挤判定时次序不同。
- provisional：出生后到第一次换帧之间，站立态是否另经 `0x446c40` 重载 `+0x7c`（会抹掉张延迟）未逐 tick 读；`0x407cc0` 置 `+0x90 = 0`，不走 `+0x90 = −1` 的重选。
- provisional：开场里经剧情插入的玩家，其张延迟抽数在重制里与其他开场玩家一起排在全部 NPC 出生之前；原版该玩家在剧情 VM 跑到插入 token 时构造出生，若 VM 在首批 NPC 首 tick 之后才跑到，次序不同。
- 未接：开场生成器替代不抽随机（等距取行主序靠后格），原版开场的插入／行走替代若抽数，开场全局流少这几次。
- 已读并照做：沙羅尼亞近郊（LEVEL034）037_2 终点 (36,17)、禁忌之魂・墳場地下（LEVEL080）嚎 终点 (5,22) 四邻全是 0xff，`0x44fbd0` 原指令留在原格；行走过程 `0x453b90` 经 `0x4111d0` 链停在最近可达格 (34,17)、(5,19) 并在所站格登记，重制生成器 `script_walk_stop` 落同一链停格（见 [original_script_walk_path.md](original_script_walk_path.md)「结论」）。
- provisional：开场生成器等距时取行主序靠后的格（原版 `rand()&1`，LEVEL038 四次快照都取后者），不做 `0x40d800` 拥挤跳过。
- 未读：`actInsertStoryObject*` 分支是否经 `0x44fbd0`；伪对象上的 `0x411a30`／`0x411ae0` 对原占位格字的读写细节。

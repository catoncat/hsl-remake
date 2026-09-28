# 剧情走位：逐格路径、Wait 与并行

> evidence: static-derived; runtime-measured: 原指令实跑五关开局的走位登记格; provisional: 战中走位抽数与原版 VM 轮／走位 tick 的交错次序、按键快进（remake-invented） · status: live · functions: 0x407940, 0x40eb40, 0x40ed50, 0x40f200, 0x40f350, 0x40f440, 0x40f560, 0x410730, 0x410a50, 0x411080, 0x4111d0, 0x411a30, 0x411b90, 0x413740, 0x413900, 0x446ad0, 0x44fbd0, 0x44fcf0, 0x44fd90, 0x450840, 0x453b90 · tools: hsltools/levels/battle.py, run_story_object_terrain_tests.gd · updated: 2026-09-28

## 结论

- 原版：剧情走位 token 经 `0x4111d0 → 0x411080` 依次洪泛半径 18、16、14、12（`0x40f350`，脚本模式不查地图边界，只受 (2r+1)² 缓冲限制）；前三级只把目的格挪到洪泛内曼哈顿最近格（`0x413740` 行主序），末级由 `0x410a50`／`0x410730` 严格下降深搜取路；走完未到目的格再调，`0x410a50` 无路可走即停。非 Wait 变体写完目的格即放行 VM，只有 Wait 变体走完才放行（static-derived，反汇编与反编译读法；60 条走位原指令执行逐格对照）。
- 重制：`game/sim/ScriptWalkPath.gd` 移植整条链；`BattleOpeningCoordinator` 默认不阻塞，只有 Wait 变体经 `_block_on(unit_id)` 等自己的走位者（static-derived）。
- 原版走完的位置提交：目的格在写入时已经 `0x44fbd0` 修过；`0x453b90` 走完（到目的格或再调 `0x4111d0` 返回 0）就在所站格 `0x411a30` 登记，不再替代。飞行（`0x446ad0`）走 mode 6，0xff 不挡，走到终点；地面走位者终点 0xff 且四邻无落点时停在链停格（static-derived；原指令实跑 runtime-measured）。
- 重制：生成器 `script_walk_stop` 让这类地面走位者开局落链停格，演出对记录了 `0x44fbd0` 落点的终点朝落点寻路，PlayLoop 格与演出停点一致（static-derived）。战中 WINFAIL 走位同规则：`ScriptActorCreationRules._place_touched` 取 `0x44fbd0` 落点后从走位起点跑 `ScriptWalkPath.stop_cell`，提交链停格；链里每次 `0x413740` 跳过有单位的格，等距平局与三邻被挡的丢弃抽全局流（static-derived）。
- 差异：开局演出不抽数（`0x413740` 同距留先到、三邻被挡照收），停格取原版开局快照；战中抽数排在该单位落点抽数之后、逐单位，和原版 VM 轮与走位 tick 的交错不一定一致（provisional）；按键快进是 remake-invented（差异清单 `script-walk-path`／`script-fast-forward`）。

## 证据

**static-derived**（`hsl01.exe` 反汇编与反编译）

| 地址 | 读法 |
| --- | --- |
| `0x450840` case 2..7 → `0x44fcf0`／`0x44fd90` | actWalk*／actWalkDisp* 写目的格心到 +0x4a/+0x48、速度到 +0x98；Wait 变体另把 VM 指针写进 +0x50（[剧情镜头读法](original_script_camera_scroll.md)） |
| `0x453b90` 状态 0x32 sub 0 | 调 `0x4111d0(actor, x, y, 0x12, 0xc)`（`0x453d6a` 压栈 0xc、0x12）；返回 0 → sub 7 不移动；否则复制路径缓冲 `0x4c63c0`（0x65 dword） |
| `0x453b90` sub 3／6 | 每 tick 按方向码（1 上、2 下、3 左、4 右）移 `步长` 像素，每 `0x20/步长` tick 取下一格；方向码 0 时若所在格 ≠ 目的格再调 `0x4111d0`（`0x45412d`），失败则在所在格登记（`0x411a30`）并进 sub 4 |
| `0x453b90` sub 7 | 清状态；+0x50 非零时 VM `+0x8c` 加一（只放行 Wait 变体） |
| `0x4111d0` | 转 `0x411080(actor, x, y, 18, 12, 1)` |
| `0x411080` | 演员已在目的格心返回 0；半径 `r = max(18, 12)`；模式 = 飞行（`0x446ad0`：记录 +0xa0 & 1）? 6 : 1；循环：`0x40f350(actor, r, 模式)`；r ≠ 12 时 `0x413900(目的, 0)` 找到就改写目的，`r −= 2`（不低于 12）；r = 12 时 `0x413900(目的, 阵营 mask)`，找不到返回 0，找到则 `0x410a50(目的)` |
| `0x40f350`／`0x40f440` | 只差 `*0x4c1a74` = 1／0；大体型（记录 +0x2c）另标周围 8 格（`0x411990`） |
| `0x40f200` | 半径上限 50；缓冲宽高 `2r+1`，清零；中心写 `r+1`，四邻按上、下、左、右以预算 r 调 `0x40ed50`；起点在图外时源高度取 0x80 |
| `0x40ed50` | 循环条件：`*0x4c1a74 ≠ 0` 时不查地图边界，只查缓冲边界。模式 1：格字 `& 0x4000` 停；高差 d = 新 − 旧（`shr 0x18` 无符号），上坡附加 d，下坡 \|d\| < 3 附加 0；附加 > 2 停；源高度 0x80 时附加 = 新格 0xff ? 16 : 0；到达预算 ≤ 缓冲值停；缓冲写到达预算，续传 `预算 − 1 − 附加`，< 1 停。模式 6：只看 0x4000，续传减 1。扩展次序：上／下来的格先直行、再左、右；左／右来的格先上、下、再直行；不回头 |
| `0x40eb40` | 图外返回「传入高度 << 24」、无旗标 |
| `0x413740`（`param_1 = 0`） | 缓冲逐行、逐列扫描；跳过 0 与 0x80 格、格字 `& 0x70000`（单位）格；像素曼哈顿距离（格心对目的像素）更小则候选；相等时 `0x458c10 & 1` 为 1 才候选；候选若 `0x40d800` 数得四个图内邻格命中 `mask \| 0x4000` ≥ 3，`rand(100) < 80` 放弃 |
| `0x410a50` | 目的格缓冲值 v_t（`0x40f560`：0 或带 0x80 则返回 0）；目的格 = 中心返回 0；首步次序按 dx、dy：dx ≤ 0 且 dy ≤ 0 时 dy < dx 取左上右下，否则上左下右；dx ≤ 0、dy ≥ 1：dy < dx 取左下右上，否则下左上右；dx ≥ 1、dy ≤ 0：dy < dx 取右上左下，否则上右下左；dx ≥ 1、dy ≥ 1：dy < dx 取右下左上，否则下右上左 |
| `0x410730` | 深度 > 99 或出缓冲：`0x458410`（消息泵）后返回 0；格值 < v_t 或 ≥ 上一格值返回 0；到目的格返回 1；否则先同向、再垂直两向（竖走时中心 x < 目的 x 取右左，否则左右；横走时中心 y < 目的 y 取下上，否则上下）；成功时写方向码到缓冲第 depth 项 |

**原指令执行**（unicorn，`hsltools.native.machine`；地图字 = 高度 << 24 | WRD 低 24 位，按走位状态机在每段末把演员移到段末格再调 `0x4111d0`）：60 条随机抽取的变化走位与 `ScriptWalkPath` 逐格一致（`NATIVE_COMPARE ok=60 bad=0`）；嚎（LEVEL080）(−2,21) → (5,22) 停 (5,19)、037_2／037_3（LEVEL034）停 (34,17)／(37,20)，与原版开局快照（`content/generated/hsl/development/opening_snapshot_diff.json` leaderboard `cell`）一致。

**resource-derived**：WINFAIL006 win_0 撤退为九条 `actWalkAndDelete`（间隔 `actDelay,2`）加一条 `actWalkAndDeleteWait`；STORY006、WINFAIL006 event_1 入场为 `actWalkPrevInsertObject`（非 Wait）＋`actDelay,30`；WINFAIL006 撤退 speed 8。

**重制盘点**（`run_story_object_terrain_tests.gd`，199 个场景的开场时间线与全部 winfail 链）：

```
SCRIPT_WALK_ROUTES scenarios=199 walks=1817 routed=1375 straight_crossed=167 nearest_reachable=17 unresolved_start=442
```

对旧 BFS：1375 条可定位走位中约 370 条格序列改变，终点不变的约 360 条（同距改道、经图外一行或按上坡代价绕行），终点改变的有幽闇墳場（LEVEL038）actor034_2 与 STORY009 actor061_1（都是目标围死、按行主序最近格停）。

### 走完后的位置提交

**static-derived**（`hsl01.exe` 反编译与反汇编）

| 地址 | 读法 |
| --- | --- |
| `0x44fcf0`／`0x44fd90`（`0x44fd43`／`0x44fdf5`） | 目的地取格心后先 `0x44fbd0(obj, &x, &y)`，修好的格才写 +0x4a／+0x48；走位过程只读这两个字 |
| `0x453b90` sub 0 | 先调 `0x4111d0`（`0x453d71`），这时起点格还带着走位者的登记（建立时 `0x411a30`，`0x407c24`／`0x407dcb`；上次停格 `0x4541a1`；`0x411900` 只记图内格；体型 0 时 `0x40f350` 不撤中心格），`0x413740` 跳过它，`0x40d800` 在该格读到走位者阵营字；返回 0 → sub 7，不撤登记；成功时复制路径，`0x407940`（同格另有登记对象）为 0 才 `0x411b90` 撤掉起点格的登记（`0x453dcb`）；之后 `0x45412d` 再调链时所在格是候选 |
| `0x453b90` sub 3／6，`0x4540f0..0x4541bf` | 方向码 0：所站格 = 目的格，或 `0x4111d0` 返回 0 → `+4 += +0xa8`、`+8 += +0xac` 临时合成所站像素，`0x407940` 为 0 时 `0x411a30(obj, 0x40ba20(obj))` 在该格登记（`0x4541a1`），sub 加一进 4；否则复制新路径续走 |
| `0x453b90` sub 4／5／7 | 只改动作帧（`0x446c40`、`0x45e642`、`0x45e660`）与放行 Wait；无第二次落点替代 |
| `0x411080` 模式 | `0x446ad0` 读 live 记录 +0xa0 bit 0（`0x44c294` 由 PLAYERS `move_fly` 置位）：飞行 mode 6 只看格字 0x4000，地面 mode 1 受高差规则 |

规则：提交格 = 链在修过的目的格上停下的格。两类情形的区分就是模式：
- 飞行走位者（雷特 006 `move_fly = 1`，mode 6）穿过 0xff 走到终点：利魯瑪山地（LEVEL019）(52,22)→(40,22)→(32,23)；回音之谷（LEVEL021）(42,14)→(30,14)→(19,15)→(19,16)；古代神殿遺跡（LEVEL037）、幽闇墳場（LEVEL038）、黃昏之丘　陽（LEVEL039）、大地的裂縫（LEVEL043）的走位者也是雷特。
- 地面走位者终点 0xff：`0x44fbd0` 有落点就改目的格（幽闇墳場（LEVEL038）034_2 (14,11)→(13,11)、沙羅尼亞近郊（LEVEL034）037_3 (38,20)→(37,20)），链走到落点；四邻全 0xff 无落点就保留终点，链停在最近可达格（禁忌之魂・墳場地下（LEVEL080）嚎 (5,22) 停 (5,19)、037_2 (36,17) 停 (34,17)）。

**runtime-measured**（unicorn 原指令跑 `round_sort_machine` 开局，g0；钩 `0x44fbd0` 前后、`0x4111d0` 的两个调用点、`0x40f350` 模式、`0x4541a1` 登记，停在首个 `0x407340`）：五关的登记格与快照格一致——LEVEL019 雷特 (32,23)、LEVEL021 雷特 (19,16) 模式 6、LEVEL034 037_2 (34,17)／037_3 (37,20)、LEVEL038 034_2 (13,11)、LEVEL080 嚎 (5,19)。

**战中走位同规则**（static-derived）：WINFAIL VM 与剧情 VM 的 actWalk*／actWalkPrevInsertObject* 都写 +0x4a／+0x48 后进同一行走者过程 `0x453b90`（[入场读法](original_script_entry.md)），所以战中走位的提交格也是链在 `0x44fbd0` 修过的目的格上停下的格。核对：同一条链的 Python 移植 `script_walk_stop` 静态普查全部 WINFAIL 的 `actInsertObject`→`actWalkPrevInsertObject*`（飞行按 `initial_book` traversal），另有 32 关自动对局里实际触发的 20 条战中走位。

| 关与单位 | 起点 → 目的 | 改前（落点） | 改后（链停格） |
| --- | --- | --- | --- |
| 巴瀚納海峽（LEVEL012）event 7 弓兵 048 ×4（地面，静态） | (14,y) → (18,y)，y＝23／33／34／42 | (18,y) | (14,y)：城墙高 16，下一格高 3，高差 ≥ 3 走不下 |
| 巴瀚納海峽（LEVEL012）event 7 弓兵 048 ×4（地面，静态） | (31,y) → (28,y)，y＝16／24／34／41 | (28,y) | (30,y) |
| 利魯瑪山地（LEVEL019）event 4／5 增援 038／041／043（静态） | 图外 (24,−3) 等 → 图内 | 目的格 | 目的格（飞行 mode 6，不变） |
| 沙羅尼亞近郊（LEVEL034）增援 023／044（实跑 9 条） | 图外 (36,−1) → (35,11) 等 | 落点 | 同落点（不变） |
| 棄卒（LEVEL051）021／026（实跑 4 条） | (8,6) → (9,7) | (9,7)／(10,7)／(8,7) | 同（不变） |
| 曼多力亞　對峙（LEVEL900）062 ×3（实跑） | (29,26) → (18,34) 等 | 目的格 | 同（不变） |

其余关的静态普查与实跑走位，链都走到落点，提交格不变。

SCRIPTWALKPATH 记的「雷特停旁格」与「LEVEL019 续走」来自普查按 `actors/006.json`（不带 traversal）把雷特当地面单位；按 PlayLoop 的 traversal（`skills/initial_book.json`）重跑后雷特五条都到终点，续走删去。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_script_walk_path.md`：`game/sim/ScriptWalkPath.gd`、`game/battle/runtime/opening/OpeningStoryObjects.gd`、`game/battle/runtime/BattleOpeningCoordinator.gd`、`game/sim/ScriptActorCreationRules.gd`。
- `ScriptWalkPath.route`：战斗读 PlayLoop tiles，剧情场景读关卡 WRD；`_flood`／`_flood_step` 对应 `0x40f200`／`0x40ed50`，`_nearest` 对应 `0x413740`，`_descend`／`_descend_step` 对应 `0x410a50`／`0x410730`（失败按格与方向记忆，结果不变），`_segment` 对应一次 `0x411080`。`walk` 上下文（全局流、抽数表、有单位的格、`0x40d800` 格字、阵营字）只由战中提交传入：`_nearest` 交给 `AINavigationRules.nearest_stoppable` 比较（行主序、同距 `rand() & 1`、三邻命中 `blocker_mask` 时 `rand(100) < 80` 丢弃；前三级 mask 0，半径 12 用走位者阵营字），第一段（`0x453d71` 的首次 `0x4111d0`）起点格在图内时仍带走位者登记，跳过它，`0x40d800` 在该格读走位者阵营字；之后各段（`0x45412d`）已撤登记，所在格是候选；不传时（开局与演出）不抽数、同距留先到、不丢弃。
- `BattleScriptActorPresentation` 取 `actWalk*` 第 5 参／`actWalkPrevInsertObject*` 第 3 参为速度。
- 按键快进（remake-invented）：见差异清单 `script-fast-forward`。
- 战中位置提交：`game/sim/ScriptActorCreationRules.gd` `_place_touched` 对最后一步是走位的单位，`nearest_landing`（`0x44fbd0`）后调 `ScriptWalkPath.stop_cell`（起点＝该走位的 `from` 格），停格不同且无人占时提交停格并记 `placements[].walk_stop_from`；链跳过事件里站着的与已落位的单位（第一段另跳过走位者自己的起点格），抽数紧接该单位落点抽数、记 `placements[].walk_draws`；演出 `_move_actor` 读回执的提交格（`motion.to`），不抽数，沿链走到该格。
- 位置提交：`tools/hsltools/levels/battle.py` `script_walk_stop` 是同一条链的 Python 移植，只用于终点 0xff 且 `0x44fbd0` 无落点的走位者（记 `position_source.story_walk_stop_from`）；`OpeningStoryObjects._fixed_destination` 读 `story_endpoint_landing_from` 把该终点换成落点再寻路。

## 复现

`tools/godot.sh --headless --script res://tests/run_all.gd -- run_story_object_terrain_tests.gd`（输出上面的 `SCRIPT_WALK_ROUTES` 行与逐条 `SCRIPT_WALK_WALLED_OFF`）。

## 边界

- `0x413740` 的随机分支：战中提交照原版以 `0x458c10 & 1`、`rand(100) < 80` 抽全局流；开局演出不抽数（同距留先到、三邻被挡照收），开局停格取原版快照。
- 战中抽数次序与登记时机：逐单位、先落点后走位，链跳过的有单位格取事件开始时站着的单位加已落位的单位；原版各走位者按 VM 轮与走位 tick 交错调链、撤登记、在停格登记（provisional）。
- 普查只列目标不可达的走位；它不套 `0x44fbd0`，034_2 与 037_3 仍按原终点列出。
- 战中走位只对每个单位事件内的最后一步走位跑链；同一事件里更早的走位仍按脚本像素记起点（原版每步各自走链）。链停格被别的单位占着时保留落点（原版照登记，重制不叠格）；3×3 体型保留落点。LEVEL012 城墙弓兵的停格只有静态普查，自动对局没有触发该事件。
- 大体型演员（记录 +0x2c，`0x411990` 标周围 8 格与 `0x40ecc0` 分支）未移植；洪泛只看地形（`0x40f350` 里的单位格未移植），单位只在 `0x413740` 挑格时跳过。

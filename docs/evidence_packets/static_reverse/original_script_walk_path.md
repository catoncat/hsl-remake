# 剧情走位：逐格路径、Wait 与并行

> evidence: static-derived; provisional: 0x413740 随机分支取定值、链停滞时的广度优先续走、按键快进（remake-invented） · status: live · functions: 0x40eb40, 0x40ed50, 0x40f200, 0x40f350, 0x40f440, 0x40f560, 0x410730, 0x410a50, 0x411080, 0x4111d0, 0x413740, 0x413900, 0x450840, 0x453b90 · tools: run_story_object_terrain_tests.gd · updated: 2026-09-28

## 结论

- 原版：剧情走位 token 经 `0x4111d0 → 0x411080` 依次洪泛半径 18、16、14、12（`0x40f350`，脚本模式不查地图边界，只受 (2r+1)² 缓冲限制）；前三级只把目的格挪到洪泛内曼哈顿最近格（`0x413740` 行主序），末级由 `0x410a50`／`0x410730` 严格下降深搜取路；走完未到目的格再调，`0x410a50` 无路可走即停。非 Wait 变体写完目的格即放行 VM，只有 Wait 变体走完才放行（static-derived，反汇编与反编译读法；60 条走位原指令执行逐格对照）。
- 重制：`game/battle/runtime/opening/ScriptWalkPath.gd` 移植整条链；`BattleOpeningCoordinator` 默认不阻塞，只有 Wait 变体经 `_block_on(unit_id)` 等自己的走位者（static-derived）。
- 差异：`0x413740` 的两处随机分支取定值；链停在可达目标前的局部最近格时重制续以广度优先走到目标；按键快进是 remake-invented（provisional，差异清单 `script-walk-path`／`script-fast-forward`）。

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

对旧 BFS：1375 条可定位走位中约 370 条格序列改变，终点不变的约 360 条（同距改道、经图外一行或按上坡代价绕行），终点改变的有玩家第 38 场 actor034_2、玩家第 39 场雷特与 STORY009 actor061_1（都是目标围死、按行主序最近格停）。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_script_walk_path.md`：`game/battle/runtime/opening/ScriptWalkPath.gd`、`game/battle/runtime/opening/OpeningStoryObjects.gd`、`game/battle/runtime/BattleOpeningCoordinator.gd`。
- `ScriptWalkPath.route`：战斗读 PlayLoop tiles，剧情场景读关卡 WRD；`_flood`／`_flood_step` 对应 `0x40f200`／`0x40ed50`，`_nearest` 对应 `0x413740`，`_descend`／`_descend_step` 对应 `0x410a50`／`0x410730`（失败按格与方向记忆，结果不变），`_segment` 对应一次 `0x411080`；不读单位占用（剧情走位是已提交结果的表现）。
- `BattleScriptActorPresentation` 取 `actWalk*` 第 5 参／`actWalkPrevInsertObject*` 第 3 参为速度。
- 按键快进（remake-invented）：见差异清单 `script-fast-forward`。

## 复现

`tools/godot.sh --headless --script res://tests/run_all.gd -- run_story_object_terrain_tests.gd`（输出上面的 `SCRIPT_WALK_ROUTES` 行与逐条 `SCRIPT_WALK_WALLED_OFF`）。

## 边界

- `0x413740` 的随机分支：同距候选重制保留先到的一格，三邻被挡的候选重制接受；原版分别以 `0x458c10 & 1`、`rand(100) < 80` 决定。
- 链停在局部最近格而目标可达时（玩家第 19 场雷特，原链停 (35,25)），原版开局快照雷特在终点 (32,23)；重制续以广度优先走到目标。停点之后的原版机制未读（候选：`0x453b90` sub 3／6 与 sub 4 之后的位置提交）。
- 走完后的停点：原版开局快照里玩家第 21、37、38、39、43 场的走位者站在目标格上（多为 0xff），原链与重制都停在旁格；嚎与 037_2／037_3 则停在旁格。区分条件未读，PlayLoop 仍取目标格。
- 大体型演员（记录 +0x2c，`0x411990` 标周围 8 格与 `0x40ecc0` 分支）与单位占用未移植。

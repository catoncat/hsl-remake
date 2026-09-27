# 脚本安装的入场、落点替代与离场收尾

> evidence: static-derived; provisional: 洪泛 mode 1 与重制无单位洪泛的对应、落点检查时机、抽数与出生抽数的先后 · status: live · functions: 0x407ec0, 0x40d800, 0x40ed50, 0x40f200, 0x40f440, 0x40f520, 0x413740, 0x413900, 0x44fbd0, 0x450450, 0x453b90, 0x45e307 · tools: run_all.gd · updated: 2026-09-28

## 结论

- 原版脚本安装没有入场态或出现帧序列：`actInsertObject`（`0x450840` case 0x12）构造（`0x407ec0`→`0x45e307` 复制 176 字节模板）后只调 `0x44fbd0` 修落点，单位在修好的格上直接出现；走入是脚本自己的 `actWalkPrevInsertObject*` 行（static-derived）。
- 落点替代 `0x44fbd0`：落格格字带单位／硬阻挡（`& 0x74000`），或地面单位落 0xff 格，才替代；以单位副本站在落格洪泛 12（地面 mode 1、飞行 mode 6），清掉中心，行主序取无单位格中曼哈顿最近者，等距按 `rand()&1` 替换，四邻硬阻挡 ≥3 时 `rand(100)<80` 跳过；无候选就留在原格。行走目的地同样经过它，随机位置插入不经过（static-derived）。
- 离场收尾：两台 VM 的 `actWalkAndDelete` 都进状态 0x36（`0x450450`），走到末格后与 `actDeleteObject`（0x35）同一收尾：engMIX 层级 16、每 tick 减一，16 帧由 16/16 淡到 1/16 后注销（static-derived）。
- 重制照做：`ScriptActorCreationRules.nearest_landing` 用同一度量与抽数，`BattleDepartureView` 逐 tick 阶梯淡出，剧情模式走完也淡出。差异：落点只在事件末对最终格检查一次（provisional）。

## 证据

**static-derived**（`hsl01.exe` SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 静态读）

| 地址 | 读法 |
| --- | --- |
| `0x450ec4`→`0x450ee2` | case 0x12：`0x407ec0(x, y, code)` 返回对象写 `0x4c1d38`（上一插入），随即 `0x44fbd0(obj, &obj+4, &obj+8)` 就地改坐标，然后回 VM 主循环 |
| `0x407ec0`／`0x45e307` | 构造只复制模板、写 `+4／+8` 坐标与 `+0x80 \|= 0xb0000000`，不写状态字 `+0x8c`；随后调该过程一次初始化。`0x453b90` 的脚本态只有 0x32–0x36（行走、滚屏、删除），没有出现态 |
| `0x450f55` | 随机位置插入：`0x407ec0(x + 表[pos], y + 表[pos], code)` 后直接跳回，不调 `0x44fbd0` |
| `0x44fbd0` 触发 | 坐标取格心 `(v & ~0x1f) + 0x10`；`0x411c40` 格字 `& 0x74000` 非零，或高字节 0xff 且 `0x446ad0`（模板 `+0xa0` bit0 飞行）为假，才进替代；否则原样返回 |
| `0x44fbd0` 替代 | 对象复制到伪对象 `0x4c3860` 并放到落格；落格格字暂置 0（`0x4119d0(x, y, 0)`）；`0x40f440(copy, 12, 飞行 ? 6 : 1)`；恢复格字；`0x40f520(0)` 清洪泛中心；`0x413900(x, y, 0, &nx, &ny)` 找到才写回坐标 |
| `0x40f200`／`0x40ed50` | 半径上限 50；mode 1 分支（`0x40f02a`）只被 `0x4000` 与高差 ≥3 挡，每步扣 `1 + 上坡附加`，不看单位阵营 mask；mode 6 只看 `0x4000` |
| `0x413740`（side 0） | 行主序扫洪泛缓冲；跳过未到达、`0x80` 位与格字 `& 0x70000` 的格；像素曼哈顿距离严格更小才替换，相等时 `0x458c10() & 1`；候选先过 `0x40d800(x, y, 0x4000)`：四邻中 ≥3 格带 `0x4000` 时 `rand(100) < 80` 跳过 |
| `0x44fbd0` 其他调用 | 行走 `0x44fcf0`／`0x44fd90`／`0x44fed0` 等（`0x44fd43`、`0x44fdf5`、`0x44fe83`、`0x44ff09`）、按 code／serial 行走 `0x450140`／`0x4501f0`、行走删除 `0x450450`（`0x450488`）都先修目的地 |
| `0x450450` 调用 | WINFAIL VM `0x450949` 与剧情 VM `0x452c97`（参数取自 `[ebp+0x94..]`） |
| `0x453ce0`（0x35）／`0x454286`（0x36） | 置 `+0 = 0x20000000`（engMIX）、`+0x28 = 16`；`0x453c7b`／`0x4542a7` 每 tick 减一，到 0 先推进 Wait 父对象再依次注销（见 [original_script_departure](original_script_departure.md)） |

engMIX 的层级混合见 [original_battle_end_flow](original_battle_end_flow.md)（字物件同一 `+0x28` 层级字）。

## 重制接线

- `game/sim/ScriptActorCreationRules.gd`：`nearest_landing` 按上表触发与挑选；洪泛用 `TacticalGridRules.movement_reachability_envelope`（不传单位，只剩地形与高差；飞行单位走飞行模式），候选排除占用格，挑选复用 `AINavigationRules.nearest_stoppable`（行主序、等距硬币、`0x40d800` 拒绝，mask `0x4000`）；抽数走战斗全局流，记入 `placements[].draws`。随机位置插入保留请求格。provenance 写 `rules: static-derived docs/evidence_packets/static_reverse/original_script_entry.md`。
- `game/battle/scene/BattleScriptActorPresentation.gd`：安装行在提交格上直接显示，入场走位由后续行走行演出。
- `game/battle/scene/BattleDepartureView.gd`：`fade` 每 tick 把 alpha 设为 `(16 − 已过 tick)/16`，16 tick 后隐藏；`BattleOpeningCoordinator._settle_pending_deletes` 在剧情模式也调用它。

## 复现

`tools/godot.sh --headless --script res://tests/run_all.gd`（规则套件；`run_winfail_rules_tests.gd` 覆盖安装与走位收据）

## 边界

- provisional：重制在整条事件末只对每个单位的最终格检查一次；原版在每个安装／行走 token 当时检查，中间格被占时落点可能不同。
- provisional：mode 1 洪泛与重制无单位洪泛在 `0x100000` 不可停格、3×3 起点八邻种子上的差别未逐格对照；3×3 角色另保留重制的全身合法性过滤（原版只查中心格）。
- provisional：原版替代抽数发生在构造当时、出生抽数（`0x407cc0` 首 tick）之前；重制先做出生抽数再抽落点，有等距或拥挤判定时全局流次序不同。
- 未读：`actInsertStoryObject*` 分支是否经 `0x44fbd0`；伪对象上的 `0x411a30`／`0x411ae0` 对原占位格字的读写细节。

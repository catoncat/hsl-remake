# WINFAIL 的 actChangePrevInsertObjectID／actSetPlayerFixPos／actSetPlayerFly

> evidence: static-derived; resource-derived: ACTION.H 与 WINFAIL012 用法; provisional: 锚点量化与精化行走的洪泛度量; negative-evidence: 碰撞、动画时序、飞行物理、对象旗标 0x4000 · status: live · functions: 0x44fa80, 0x44fad0, 0x450840 · tools: run_ai_navigation_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-27

## 结论

- 原版 `actSetPlayerFixPos` 只改对象的守备锚点（`+0x46`／`+0x44`）与非零时的守备半径（`+0x1d0`），不移动单位；`actSetPlayerFly` 切换 player 记录 `+0xa0` bit 0；`actChangePrevInsertObjectID` 改上一插入记录 `+0x84` 的身份字（static-derived）。
- 重制 `game/sim/WinfailActions.gd` 写 `ai_home_coord` 与 `ai_fixed_radius`，单位按守备分支走向锚点，图外锚点是撤退点；飞行写单位 `traversal.flying`；插入身份只作收据（static-derived）。
- 差异：锚点的 32 px 量化与精化行走洪泛度量为重制读法；原版 handler 是否置对象旗标 0x4000 未读（provisional；negative-evidence）。

## 证据

### resource-derived

`content/imported/hsl/global/tables/ACTION.H`：actChangePrevInsertObjectID = 32 `[id]`；actSetPlayerFixPos = 84 `[code][serial][x][y][distance]`；actSetPlayerFly = 92 `[code][serial][mode]`。WINFAIL012 用第一个 token 六次（id 10000），第 8 回合对全部 32 名 SID_ENEMY038 设固定点（`-160,1824`、`576,-160`、`1632,608`、`736,2112`，45×60 图外），对八名 SID_ENEMY048 在脚本离场前设飞行 1。

### static-derived（`0x450840` 分派）

| case | 原版 |
| --- | --- |
| `0x20` actChangePrevInsertObjectID | 读一个字写到当前关上一插入／player 记录 `+0x84`，游标前进一个参数；是记录身份改写，不插入新对象 |
| `0x54` actSetPlayerFixPos | `0x44fad0(code, serial)` 找到对象后 x 写 `+0x46`、y 写 `+0x44`；distance 非零时把它写到按 actor 槽索引的 player 记录 `+0x1d0`；五个参数一起消费 |
| `0x5c` actSetPlayerFly | 同样解析 code＋serial，mode 0 清、非零置 player 记录 `+0xa0` bit 0；三个参数一起消费 |
| `0x44fad0` | 按 actor code 扫登记对象槽，在匹配者中递减 serial（serial 1 = 第一个匹配）；辅助 `0x44fa80` 拒绝已移除／不可用的槽，已删除对象不再解析 |

`+0x46`／`+0x44` 是固定点行走 `0x4111a0` 读的锚点（[original_ai_navigation](original_ai_navigation.md#证据)）；守备分支 `0x440ef1` 把锚点半径外的敌人排除在目标外。EVEF 固定点安装把格心对齐为 `(word & ~0x1f) + 0x10`，并置对象旗标 0x4000，否则到达释放 `0x43fbf1..0x43fc0e` 不清脚本半径。

## 重制接线

- `game/sim/WinfailActions.gd`：固定点写 `ai_home_coord = floor(pixel / 32)`，非零 distance 写 `ai_fixed_radius`（`AINavigationRules.instance_profile` 最后读）；单位不移动，之后经 `approach_home` 走向锚点；图外锚点使单位走到最近边格并保持参战，直到第 10 回合 `actWalkAndDelete` 移除；收据 `winfail_runtime.fixed_position_changes` 记 `coord`、`distance`、`off_map`。
- 地图外的活单位是显式场景错误 `ai_unit_off_map:<id>`（`BattleLoopAI.prepare_ai_turn`）。
- 飞行写单位飞行字段（只在该 token 施加时创建）；插入身份记在 `winfail_runtime.previous_insert_id_changes`，并更新待处理插入收据的源 id。
- 边界 id `fix_pos`、`fly_prev_insert` 见 [winfail_claim_limits](winfail_claim_limits.md)。

## 复现

`tools/godot.sh --headless --script res://tests/run_ai_navigation_tests.gd`（`script_anchor_cases`）；`tools/godot.sh --headless --script res://tests/run_all.gd -- run_winfail_rules_tests.gd`（`_level_twelve_opcode_actions`）

## 边界

- provisional：锚点的 32 px 量化（与 EVEF 格心对齐同格）、精化行走的洪泛度量、id 10000 在重制中无可见效果。
- negative-evidence：本读法不确立原生碰撞、动画时序、飞行物理，也不确立 handler 是否置对象旗标 0x4000；重制在到达后仍按该半径守备。替换证据是 LEVEL012 第 8–10 回合的有界运行探针。

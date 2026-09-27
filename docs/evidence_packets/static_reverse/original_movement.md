# 移动：四邻扩展与邻接阻挡代价

> evidence: static-derived · status: live · functions: 0x40eb80, 0x40f200 · tools: hsltools/probes/movement.py, run_ai_navigation_tests.gd · updated: 2026-09-27

## 结论

- 原版：`0x40f200` 从中心以 `budget+1` 起按上、下、左、右扩展；先登记当前格到达余量，再按 `0x40eb80` 为继续扩展扣邻接代价——前方与两侧（排除来格）有 `0x74000` 类阻挡时 2，否则 1；WRD `0xff000000` 高字节阻止进入但不计入邻接代价（static-derived；58 组扩展＋80 组邻格代价完整返回）。
- 重制：`game/sim/TacticalGridRules.gd` 共享扩展，玩家移动范围、AI 攻击／法术／支援站位与追击共用；58 组原扩展逐格一致（static-derived 规则；Godot 导航套件对照）。
- 差异：对象通行资格、盟友穿越、各模式 mask、全部高差、大型占地、原 250 项缓存节流与平分路径顺序未等价；全图最短路线是重制组合（provisional）。

## 证据

**static-derived**（[original_movement.json](original_movement.json)，`hsltools/probes/movement.py`，SHA 锁定原 EXE，callee 不替换，未知 callee 拒绝；检查返回地址、栈恢复与指令上限）

| 函数 | 样例 | 结论 |
| --- | --- | --- |
| `0x40f200` | 58 | 9×9 合成地图（开放、单障碍、墙、整列阻断、多障碍、边角），预算 1／2／4／6；输出格值全部与独立最短路径模型一致 |
| `0x40eb80` | 80 | 按进入方向查前方与两侧；无相关阻挡 1，有则 2（多个也只 2）；普通模式 mask `0x74000`，分别覆盖 `0x4000/0x10000/0x20000/0x40000` |

- 第一步成本 1；从邻接相关阻挡的格继续前进时该步成本 2；落脚格不付自己的继续扩展费用。
- 四邻扩展不表示普通角色可斜走；八方向目标距离与大体型占地见 [original_ai_navigation.md](original_ai_navigation.md)。
- `0x40eb40` 读 WRD 格字，`0x74000` 旗标拒绝进入（`WrdTerrainTiles`）。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_movement.md`：`game/sim/TacticalGridRules.gd`、`game/sim/AINavigationRules.gd`、`game/sim/WrdTerrainTiles.gd`。
- `TacticalGridRules` 准备占用、显式地块 `movement_flags` 与成本；活着的其他角色阻挡，死者立即释放占用与邻接成本；全部更便宜路径更新完成后才构造 `path` 与 `path_costs`。
- `WrdTerrainTiles` 保留 0xff 不可进语义，低位 flags 为 0；自定义 `move_cost` 是场景／测试能力。
- `AINavigationRules` 全图搜索保留累计成本，当回合前缀按 `move_point` 截取；过期施法站位不能移动或扣费。
- 逐格动画每条边 0.20 秒，不随移动点代价变化。

## 复现

`python3 tools/hsl.py check movement`（重执行：`uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate movement --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`）。

## 边界

- 完整对象通行资格、盟友穿越、各模式 mask、所有高差、大型占地未等价。
- 原 250 项缓存的执行节流与完整平分路径顺序未复刻；所选路线本身是 provisional，成本来源是 static-derived。
- 剧情走位（忽略角色占用、遵守地形）见 [original_script_walk_path.md](original_script_walk_path.md)。

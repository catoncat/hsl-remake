# 直线效果范围：0x4100e0 的 range 21..23（Dir）分支

> evidence: static-derived; provisional: 效果区域接线 · status: live · functions: 0x40fc90, 0x40fdc0, 0x4100e0 · tools: hsltools/data/attack_ranges.py, hsltools/data/skill_targeting.py, hsltools/probes/range_terrain.py, run_tests.gd · updated: 2026-09-27

## 结论

- 原版：`range3CellDir`／`range4CellDir`／`range5CellDir`（21..23）不读矩阵 data 行，只用首字节 size 作线长；从所选格出发朝「施法者→所选格」的轴向延伸 size 格（列不同优先水平，所选格含在内）；出界或遇 `0x4000` 格停线，排除位格与无角色的 `0x850000` 格跳过但继续（static-derived；126 次原生完整执行）。
- 重制：`SkillTargetRules.line_direction／line_cells／effect_cells` 以施法者格为必要输入，`RangePropagationRules.line_coverage` 实现停线与跳格（static-derived）。
- 差异：玩家施法结算与悬停预览尚未传入效果区域地形，对局中直线只裁地图边界（provisional：效果区域接线）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835…70f7`；126 次完整执行见 [original_range_terrain.json](original_range_terrain.json)，含 `0x4000` 墙、柱与各侧占位字）

| 锚点 | 行为 |
| --- | --- |
| `0x41019b`、`0x4101a4` | `cmp esi,0x15 / jl`、`cmp esi,0x17 / jg`：21..23 进直线分支 `0x4101ad`，其余走 `0x41035d` 矩阵＋`0x40fdc0` 四向传播 |
| 线长 | `al=byte[record]`（size）；`0x4c6d3c` 指向记录但本分支不读 data 行 |
| 坐标 | `>>5` 把目标像素与施法者 actor+4／+8 换成格 |
| 方向 `0x4101cd..0x410222` | `tx≠ax` → `(sign(tx−ax), 0)`；否则 `ty≠ay` → `(0, sign(ty−ay))`；都相等则线长置 1 |
| 循环 `0x41026d..0x41034b` | 从 `(tx,ty)` 出发每步写 `ebx+1`（首格＝size，末格＝1） |
| 停线 | 出 `0x4c0934／0x4c0938`（地图宽高）或格标志 `ah&0x40`（`0x4000`）→ `0x410359` 置 `ebx=0` |
| 跳格 | 命中 mode 排除位 `0x4c6d50` 且非 `0x70000` 组合（`0x4102b2..0x4102c6`）不写但继续；否则 `0x4102ca` 调 `0x40fc90`：找到活角色时清格字（`0x4102d6`），再测 `(flags&0x870000)==0x850000`（`0x4102e4..0x4102ee`）——有角色的格照写，只有无角色的 `0x850000` 格跳过；写格在 `0x41030b` |

**resource-derived**：RANGE.TXT 的 Dir 记录是 `size=N` 后 N 行各一个值（`3／2／1`、`4／3／2／1`、`5／4／3／2／1`）。使用者都以 `range1Cell` 施放：

| 绝技 | id | range | effect_range |
| --- | --- | --- | --- |
| 皇龍閃 | `special:magicOTHER:magicCode02` | range1Cell | range3CellDir |
| 龍嘯天驅 | `special:magicOTHER:magicCode19` | range1Cell | range4CellDir |
| 翔天刃風擊 | `special:magicAIR:magicCode07` | range1Cell | range4CellDir |

没有源行把 Dir 当施放范围；`range5CellDir` 无使用者。

## 重制接线

- `hsltools/data/attack_ranges.py`、`hsltools/data/skill_targeting.py` 把 Dir 编译为 `shape=line`（size＋原 data 行）。
- `SkillTargetRules.line_direction`／`line_cells`／`effect_cells(center, …, origin)`：缺施法者位置返回空；`candidate_centers` 用同一正向投影四轴反查；Dir 作施放范围返回 `unsupported_line_cast_range`；terrain 带 `area_modes` 时使用 `RangePropagationRules.line_coverage`。
- `SkillResolutionRules.prepare_cast`、`AISkillPlanning.target_for_center`、`BattlePlayLoop.magic_target_id_at_coord`／`strike_range_cells` 传入施法者格；settled 提示条显示实际直线。
- `BattleLoopCombat._skill_context` 与悬停预览尚未传效果区域地形，线上敌我仍由 `side_matches` 过滤（provisional），接线点同 [original_weapon_ranges.md](original_weapon_ranges.md)。

## 复现

`python3 tools/hsl.py check range_terrain`；重制侧 `tools/godot.sh --headless --script tests/run_tests.gd`（126 次原生返回逐字节对拍）。

## 边界

- 角色分支（`0x40fc90` 找到活角色）只有指令读法，探针角色表为空，重制用 `ACTOR` 标记代替。
- 对局中直线尚未按地形停线与跳格。

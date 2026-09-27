# 直线（Dir）效果范围：0x4100e0 的 range 21..23 分支

> evidence: static-derived; provisional: 效果区域接线 · status: live · functions: 0x40fc90, 0x40fdc0, 0x4100e0 · tools: hsltools/data/attack_ranges.py, hsltools/data/skill_targeting.py, hsltools/probes/range_terrain.py, run_range_propagation_tests.gd · updated: 2026-09-25

Checked: 2026-09-20。接续 [技能function、目标覆盖与共享范围](original_skill_targets.md)（`0x4100e0` 已登记为 `build_signed_source_range_coverage`）与 [原武器射程](original_weapon_ranges.md)。本包只恢复 RANGE.H 注释 "N Line"／"E Line" 的三个符号（`range3CellDir=21`、`range4CellDir=22`、`range5CellDir=23`）在原覆盖函数里的几何；证据等级 **static-derived**（反汇编读法，指令地址可复核）。2026-09-25 起直线分支另有 126 次本机完整执行（[original_range_terrain.json](original_range_terrain.json)，含 `0x4000` 墙、柱与各侧占位字），停线与跳格规则逐字节对上。

## 来源表

RANGE.TXT 里 Dir 记录不是 size×size 矩阵，而是 `size=N` 后 N 行、每行一个值（`3／2／1`、`4／3／2／1`、`5／4／3／2／1`）。SPECIAL.TXT 中使用它们的行都以 `range1Cell` 施放：

| 绝技 | id | range | effect_range |
| --- | --- | --- | --- |
| 皇龍閃 | `special:magicOTHER:magicCode02` | range1Cell | range3CellDir |
| 龍嘯天驅 | `special:magicOTHER:magicCode19` | range1Cell | range4CellDir |
| 翔天刃風擊 | `special:magicAIR:magicCode07` | range1Cell | range4CellDir |

没有任何源行把 Dir 当作施放范围；`range5CellDir` 无使用者。

## 静态读法（0x4100e0，EXE SHA-256 `f0b5f835…70f7`）

入口清空覆盖缓冲后，`0x41019b`：`cmp esi,0x15 / jl`、`0x4101a4`：`cmp esi,0x17 / jg`——range 索引 21..23 进入 `0x4101ad` 的直线分支，其余走 `0x41035d` 的矩阵＋`0x40fdc0` 四向传播分支。直线分支：

1. `al=byte[record]`（RANGE 记录首字节＝size）为线长；`0x4c6d3c` 仍指向记录数据，但本分支**不读任何 data 行**。
2. 以 `>>5` 把目标像素与施法者 `actor+4／+8` 换成格：`tx,ty` 与 `ax,ay`。
3. 方向（`0x4101cd..0x410222`）：`tx≠ax` → 步进 `(sign(tx−ax), 0)`；否则 `ty≠ay` → `(0, sign(ty−ay))`；两者都相等 → 线长置 1（只写目标格本身）。**列不同时优先水平轴**，斜向目标不会取对角线。
4. 循环 `0x41026d..0x41034b`：从目标格 `(tx,ty)` 出发，每步写值 `ebx+1`（首格＝size，末格＝1），然后按步进推进 size 次。
5. 停线条件：格坐标越出 `0x4c0934／0x4c0938`（地图宽高）→ `0x410359` 置 `ebx=0` 结束；地图格标志 `ah&0x40`（`0x4000`）→ 同样结束。
6. 跳格不停线：格标志命中当前 mode 排除位 `0x4c6d50` 且非 `0x70000` 组合（`0x4102b2..0x4102c6`）→ 不写该格但继续推进。否则调 `0x40fc90`（`0x4102ca`）：找到活角色时把该格字清 0（`0x4102d6`），再测 `(flags&0x870000)==0x850000`（`0x4102e4..0x4102ee`）——所以有角色的格照写，只有无角色的 `0x850000` 格跳过（写格在 `0x41030b`）。2026-09-20 版把「`0x40fc90` 返回非零」写成跳过，方向相反，已按指令更正。

因此 Dir 效果＝"从所选格出发、朝施法者→所选格的轴向延伸 N 格"，所选格本身包含在内。这与 range1Cell 的施放范围配合：目标必须与施法者正交相邻，线从目标格开始向远离施法者的方向延伸 N−1 格。

## 重制接入

- `hsltools/data/attack_ranges.py`／`hsltools/data/skill_targeting.py` 把 Dir 记录编译为 `shape=line`（`size`＋原 data 行），矩阵合同不变。
- `SkillTargetRules.line_direction／line_cells／effect_cells(center, …, origin)`：施法者位置是直线脚印的必要输入，缺失时返回空、不假定方向；`candidate_centers` 用同一正向投影做四轴反查；Dir 作为施放范围返回 `unsupported_line_cast_range`。
- `SkillResolutionRules.prepare_cast`、`AISkillPlanning.target_for_center`、`BattlePlayLoop.magic_target_id_at_coord／strike_range_cells` 传入施法者格；settled 提示条显示实际直线。

## 边界

- **0x4000 停线与占位跳格（static-derived，已实现未接）**：`RangePropagationRules.line_coverage` 按上文 5、6 两步停线与跳格，126 次原生返回在 `tests/run_range_propagation_tests.gd` 逐字节对拍；`SkillTargetRules.line_cells` 在 terrain 带 `area_modes` 时使用它。玩家施法结算（`BattleLoopCombat._skill_context`）和悬停预览尚未传入效果区域地形，所以对局里的直线仍只裁地图边界，线上的敌我仍由 `side_matches` 过滤——与矩阵效果区域同一处接线，见 [原武器射程](original_weapon_ranges.md#调用方与重制接线)。
- 角色分支（`0x40fc90` 找到活角色）只有指令读法：探针的角色表为空。重制用 `ACTOR` 标记代替该命中。

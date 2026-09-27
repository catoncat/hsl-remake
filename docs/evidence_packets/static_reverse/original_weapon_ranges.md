# 武器射程：武器字来源、RANGE 掩码与地形传播

> evidence: static-derived; resource-derived: EVEF 装备字为零; provisional: AI 接近目标格平铺、大型角色锚点 · status: live · functions: 0x409090, 0x40bab0, 0x40bb00, 0x40c9a0, 0x40cca0, 0x40d340, 0x40eb80, 0x40f5d0, 0x40f8b0, 0x40fa80, 0x40fab0, 0x40fb20, 0x40fc90, 0x40fdc0, 0x4100e0, 0x4119f0, 0x411a30, 0x411b90, 0x42bd50, 0x43f79b, 0x441779, 0x441a73, 0x4423c0, 0x442a90, 0x4477c0, 0x44b980, 0x44cb10 · tools: audit_range_propagation_impact.gd, hsltools/data/attack_ranges.py, hsltools/probes/range_terrain.py, run_ai_navigation_tests.gd, run_autoplay_sweep_tests.gd, run_tests.gd · updated: 2026-09-28

## 结论

- 原版：射程读 live 角色记录 +0xec 的武器字（PLAYERS `weapon_equip` 复制而来，EVEF 非零实例字可覆盖），武器 0 → 范围 0；`ITEM.attack_range` 选 RANGE 记录，但目标格不是正掩码本身——武器与施放范围由 `0x40f8b0` 从起点四向深度优先传播，效果区域由 `0x4100e0` 矩阵分支调 `0x40fdc0`；只读地图字（WRD `0x4000` 与占位者侧位），不读高度；`0x4000` 格停线且不写，障碍前方检查使本格照写但不外传（static-derived；354 次完整执行逐字节对拍）。
- 原版 AI 施放：规划与出手同一套传播——施放范围 `0x40f8b0(施放格, 射程, −1, 0)`（与玩家施放同 mode），效果区域 `0x4100e0(行动者, x, y, 区域, mode)`，mode 由 AI 分支写进 `0x4c2c78`：进攻 `0x40bab0`（P 2、E 3、N 7），援助 `0x40bb00`（P 8、E 9、N 10）；规划逐个候选格先抹自身占位再把自身写到候选格（static-derived）。
- 重制：`RangePropagationRules`（`weapon_coverage`／`area_coverage`／`line_coverage`）由玩家武器格、反击资格、敌方武器格显示、玩家施放范围与效果区域、AI 武器站位、AI 进攻与援助施放的规划和结算共用；`PositionCapabilityRules.attack_pattern` 选掩码（static-derived）。
- 差异：`approach_goals`（重制的接近目标格收据，无原版对应调用）仍读平铺掩码；大型角色以 `FootprintRules` 锚点为传播起点（provisional）。

## 证据

**static-derived**（`hsl01.exe` sha256 `f0b5f835…`；[original_range_terrain.json](original_range_terrain.json) 在 open／wall／pillar 三张 15×15 格子上完整执行 354 次：武器 124、矩阵区域 104、直线 126）

武器字来源：

| 步骤 | 锚点 | 读法 |
| --- | --- | --- |
| PLAYERS 模板 | `0x44b980`：`0x44c0af push "weapon_equip"` → `0x44c0ca mov [ecx+esi+0xec], eax`（模板表 `*0x4c1afc`，步长 `0x1fc`，缺字段为 0）；同段 head→+0xf0、armor→+0xf4、foot→+0xf8、other1→+0xfc、other2→+0x100 | 模板武器＝`weapon_equip` |
| 安装复制 | `0x44cb10(code, is_player)`：`0x44cb41 rep movsd`（0x7f 个 DWORD）复制到 live 表 `*0x4c1bc8`；玩家槽号＝code，敌方从槽 21 起取首空槽（`0x44cb53 mov eax, 0x15` … `cmp eax, 0xc7`） | live +0xec 初值＝模板武器 |
| EVEF 实例覆盖 | `0x42bd50` 演员分支：`0x42bf50 mov eax, [rec+edx*4+0x50]`，`0x42bf5a je` 为 0 跳过；跳转表 `0x42c0a8` case 18 `0x42c055 mov [ecx+0xec], eax`（19→+0xf4、20→+0xf0、21→+0xf8、22→+0xfc、23→+0x100、24→+0xe8 气力），`0x42c096 call 0x448840` 刷新 | 非零实例字覆盖，零保留模板 |
| ITEM 表 | `0x4477c0`：`0x447a5e push "attack_range"` → `0x447a7e mov [edx+edi+0x84], eax`（`*0x4c1b40`，步长 `0xb0`） | `attack_range` 在 +0x84 |
| 范围读点 | `0x409090`：`0x4090bf mov ecx, [rec+0xec]`；`0x4090cd`／`0x4090f1` 武器 0 返回 0；否则 `0x4090db`／`0x409100` 取 +0x84；另有 +0x18c bit1 饰品加一档、+0x2c 大型加 17 封顶 20（见 [original_position_equipment.md](original_position_equipment.md)） | 范围索引＝武器 attack_range |

地形传播：

| 规则 | 原版做法 |
| --- | --- |
| 地图字 `0x4c0928` | 每格一个 DWORD：WRD `movement_flags & 0x4000` 或上占位者侧位（P `0x10000`、E `0x20000`、N `0x40000`，pmALL `0x70000`，pmMagicAttack `0x800000`）；高度（h 255、blocks_movement）不参与 |
| 起点 | `0x40f8b0`（包装 `0x40fa80`）：起点写 `half+1`，除非命中 `0x40fa48[mode]` 排除位；`0x4100e0` 矩阵：中心写 `half+1`，除非命中 `0x410498[mode]` 且非 pmALL，或是无角色的 `0x850000` 字；中心不查 `0x4000` 与 RANGE 值 |
| 方向与顺序 | 起点四邻各调一次 `0x40f5d0`（上、下、左、右，power＝half）；每步写完深度优先：上→上、左，再转右；下→下、左，再转右；左→上、下，再继续左；右→上、下，再继续右 |
| 每步次序 | 越界停；含 `0x4000` 停；RANGE 值 0 停；已写 ≥ power 停；值 > 0 写 power（被排除则不写）并做前方检查；power−1 到 0 停；值 < 0 只传递、不写、不查前方 |
| 前方检查 | `0x40eb80(x, y, dir, 0x4000)`：正前方与左右两侧三格任一带 `0x4000` 时本格照写、power 置 0；越界按 0 读；只在步进表 check 位为 1 的 mode 做（`0x40f874`：2、3、7、8、9、10；`0x4100a0`：除 0、1、4、5 外） |
| 敌我（武器） | 步进表 `0x40f874[mode−2]` 侧位命中且非 pmALL 不写但继续；flag 1 时 pmALL＋pmMagicAttack 也不写；玩家武器 `0x444149` 常数 mode 2（只排除 P）；反击 `0x44269c` 与 AI 用 `0x40bab0`：P→2、E→3、N→7，无侧位→`0x10000`；支援类 `0x40bb00`：8／9／10 |
| 敌我（施放） | 玩家施放 mode −1、flag 0：不排除占位者、无前方检查 |
| 敌我（区域） | `0x40fdc0` 步进表 `0x4100a0`：mode 2 不写 P、3 不写 E（pmALL 例外）；无角色的 `0x850000` 不写；`0x40fc90` 找到活角色先把字清 0，因此照写 |

调用方：玩家武器 `0x442a90` 内 `0x444156`（`0x40fa80`→`0x40f8b0`，mode 2、flag 1）；反击 `0x4423c0` 内 `0x4426b0`（守方 `0x40bab0` mode、flag 1，`0x409090`→`0x40fa80` 建覆盖，`0x40fab0` 查攻方格，命中在 `0x4c4320` 置 `0x10000`；门槛 `test byte [ecx+0x24], 4` 与 [ecx+0x19e]）；玩家施放 `0x444eb7`／`0x445075`／`0x44508f`；玩家效果区域 `0x444f08`／`0x4450e0`（mode 2 攻击、3 支援）；AI 站位 `0x40d8b0` 先 `0x411b90` 抹自身占位（`0x40d8c3`），普通目标 `0x40fa80(目标, 射程, mode, 0)`（`0x40dbe6..0x40dbfa`），3×3 目标逐身体格 `0x40f8b0(px±32, py±32, …)`；「目标在射程内」`0x40fa80(行动者, 射程, mode, 1)` → `0x40fb20`（`0x440d2d`、`0x440c62`、`0x43fca5`）；到站复查 `0x441311..0x441369`（清 `0x10000`、`0x411a30` 放回占位、为零 `je 0x441eb8` 不出手）。AI 技能侧 `0x40f8b0` 调用方 `0x40cca0`、`0x40d340`、`0x40d530`、`0x40df70`，`0x4100e0` 调用方 `0x40ca71`、`0x4417a6`、`0x4418fd`、`0x441aa0`、`0x441c02`，`0x40fa80` 调用方 `0x441779`、`0x441a73`。

AI 施放（`hsl01.exe` 指令读法）：

| 步骤 | 锚点 | 读法 |
| --- | --- | --- |
| 进攻分支写 mode | `0x43f851`／`0x43f8d4`／`0x43fe3f`／`0x43febb` `call 0x40bab0` → `mov [0x4c2c78], eax`，同值作第 5 参给 `0x40df70`（SPECIAL）／`0x40d340`（MAGIC） | 进攻区域 mode＝P 2、E 3、N 7 |
| 援助分支写 mode | `0x43fad6`／`0x43faf9`／`0x440adb`／`0x440af8` `call 0x40bb00` → `mov [0x4c2c78], eax`；`0x40bb00` 读 player_mode：`0x10000`→8、`0x20000`→9、`0x40000`→10，否则返回 `0x20000` | 援助区域 mode＝P 8、E 9、N 10 |
| 规划：移动施放格 | `0x40cca0`：候选格字 `& 0x74000` 非零跳过（`0x40cf34`）；`0x411b90` 抹自身占位（`0x40cf47`）、`0x4119f0` 写到候选格（`0x40cf55`）；`0x4097d0`／`0x409830` 取射程后 `0x40f8b0(px, py, 射程, −1, 0)`（`0x40cfb0`）；`0x40c9a0` 评估后 `0x411a10`／`0x411a30` 复原 | 施放范围从候选格传播，mode −1、flag 0 |
| 规划：原地 | `0x40d340` 内 `0x40d459` `0x40f8b0(自身格, 射程, −1, 0)`，`0x40d47e` 调 `0x40c9a0`，第 6 参＝`0x40d340` 第 5 参（mode） | 同上 |
| 规划：区域计数 | `0x40c9a0` 遍历 `*0x4c1b48` 已写格，`0x40ca71` `0x4100e0(行动者, x, y, 区域, 第 6 参)`；再遍历 `*0x4c1b4c`，字 `& 0x70000` 非零且非 pmALL 计一（`0x40cb06..0x40cb14`） | 效果区域按 mode 传播 |
| 出手 | MAGIC `0x441779` `0x40fa80(行动者, 射程, −1, 0)`、`0x4417a6`／`0x4418fd` `0x4100e0(…, [0x4c2c78])`；SPECIAL `0x441a73` 同 −1、0，`0x441aa0`／`0x441c02` 同 `[0x4c2c78]` | 结算读同一组格 |

**resource-derived**：RANGE.H range3CellCircle 10、range3CellThrust 15、range5CellCircle 12、range6CellShoot 7、range0Cell 0；ITEM 32（Gulu 008）与 53（Enemy057）→ range3CellCircle，57（Enemy058）→ range0Cell（注释掉的 range3CellCircle 行不用）。普通武器接受 range0Cell、range1Cell、range2Cell、range3／4／5／6CellShoot、range3CellCircle、range3CellThrust、range5CellCircle，其余拒绝。70 关 569 个 EVEF 演员实例的 `override_fields` 中装备六字均为 0 次，未应用实例覆盖对现有数据是空操作。

**runtime-measured**（重制侧影响面，`tests/diagnostics/audit_range_propagation_impact.gd`，139 个战场、63 种地图）

| 比较 | 变化／总数 | 涉及关卡 |
| --- | --- | --- |
| 开场位置武器格（墙＋占位者） | 313／524 | 126 |
| 同上只算 `0x4000` 墙 | 20／524 | 8 |
| 任一非墙格起算的武器格（只算墙） | 33／524 | 11 |
| 开场位置玩家施放范围 | 44／2163 | 7 |
| 任一非墙格起算的施放范围 | 43／831 | 9 |
| 任一非墙中心的效果区域 | 27／742 | 9 |

开场武器格变化 481／2516 个单位，主要是 mode 2 不写 P 侧占位格与敌方 mode 3 不写同侧格；5 场自动对局（51、1、3、504、80）胜负、回合数不变。AI 施放改传播前后各跑一次全量 128 场自动对局（种子 1）：`results.json` 逐字节相同（win 19、fail 109），无胜负翻转。

## 重制接线

| 读点 | 重制 |
| --- | --- |
| 武器字 | `tools/hsltools/levels/scenario.py` 取 `weapon_equip`；换装经 `EquipmentRules`；`seed.py _actor_instance` 把实例字 18–23 解码为 `overrides.*`，`evef_instances.json` 列为 `recorded_only_fields`，运行时不应用 |
| 掩码 | `PositionCapabilityRules.attack_pattern`：weapon_code → ITEM.attack_range → RANGE；code 0 → 空，无徒手 fallback；`hsltools/data/attack_ranges.py` 生成 `content/generated/hsl/chapter01/attack_ranges.json`（正格、不含中心） |
| 地图字 | `RangePropagationRules.cell_words`／`loop_words`，占位取 `FootprintRules.occupants`（no_block 角色也写侧位，provisional） |
| 玩家武器、反击、敌方武器显示 | `BattlePlayLoop.weapon_cells` → `attack_cells`，按 `offensive_mode`；`BattleLoopCombat` 反击读 `Loop.attack_cells(loop, defender_id)` |
| 玩家施放与效果区域 | `SkillTargetRules.cells(…, terrain)`、`BattlePlayLoop.skill_terrain`／`player_cast_terrain`；`BattleLoopCombat._skill_context` 放进 `range_terrain`，悬停自绘格、目标行、`magic_target_id_at_coord`、`RepeatedSpecialRules.prepare` 读同一份 |
| AI 武器 | `AINavigationRules.weapon_terrain` → `attack_stations(…, terrain)`；`BattleLoopAI._ai_station_attack` 到站 `target_in_range`，不含目标回 `move`，`wait_reason = station_out_of_range` |
| AI 技能 | `AISkillPlanning.cast_terrain`（抹自身占位后写到施放格；`cast_mode` −1，`area_modes` 进攻 `offensive_mode`、援助 `support_mode`）交给 `AISkillPlanning`／`AISupportPlanning` 的 `SkillTargetRules.cells`、`target_for_center` 与 `prepare_cast`；出手 `BattleLoopCombat.skill_context(loop, 施放者, 施放格)` 取同一份 |
| AI 接近 | `AINavigationRules.approach_goals` 仍平铺（provisional，重制收据） |
| 自动对局 | `tests/support/Autoplay.gd` `_destination` 落脚格按落脚后的武器洪泛判定 |

## 复现

`python3 tools/hsl.py check range_terrain`；重制侧 `tools/godot.sh --headless --script tests/run_tests.gd`（354 次逐字节重放，第 3 关与第 504 关预览＝结算）与 `tests/run_ai_navigation_tests.gd`（`terrain_range_cases`）。

## 边界

- 原函数把 RANGE 局部框裁在地图内，比记录小的地图未执行（注册战场都 ≥ 20×15，最大记录 13×13）。
- 大型角色的传播起点取锚点还是身体未验证。
- `0x44451e`–`0x444592`（range 9..13、mode 4、flag 1，受 `0x45b554` 门控）未验证。
- `0x44cb10` 敌方槽表满返回 0 的调用方处理未读；宝箱实例字属 [original_treasure.md](original_treasure.md)。
- range2／4／6CellCircle、range4CellThrust、range1CellFull、Dir 系列不接受为普通武器（没有 ITEM 武器使用）；直线见 [original_line_ranges.md](original_line_ranges.md)。

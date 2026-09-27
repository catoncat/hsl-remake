# Original Weapon Ranges

> evidence: static-derived; resource-derived: EVEF 装备字为零; provisional: AI 技能规划与 AI 施放仍平铺、大型角色锚点 · status: live · functions: 0x409090, 0x40bab0, 0x40bb00, 0x40eb80, 0x40f5d0, 0x40f8b0, 0x40fa80, 0x40fab0, 0x40fb20, 0x40fc90, 0x40fdc0, 0x4100e0, 0x411a30, 0x411b90, 0x42bd50, 0x4423c0, 0x442a90, 0x4477c0, 0x44b980, 0x44cb10 · tools: audit_range_propagation_impact.gd, hsltools/data/attack_ranges.py, hsltools/probes/range_terrain.py, run_ai_navigation_tests.gd, run_tests.gd · updated: 2026-09-25

## Scope

This packet records the source-range builder used by the first-battle weapon catalog and, since lane WRANGE (2026-09-25), the terrain propagation every original range read goes through (「地形传播」 below): the RANGE mask is not the target set by itself, the original floods it over the map words 0x4c0928 with 0x40f8b0／0x4100e0.

## Source Table

- **static-derived**: content/imported/hsl/global/tables/RANGE.H assigns range3CellCircle index 10, range3CellThrust index 15, range5CellCircle index 12, range6CellShoot index 7, and range0Cell index 0.
- **static-derived**: content/imported/hsl/global/tables/RANGE.TXT is compiled by tools/hsltools/data/attack_ranges.py into content/generated/hsl/chapter01/attack_ranges.json; the generated offsets are the positive cells around the centered mask and exclude the center cell.
- **resource-derived**: ITEM.TXT joins item 32 (Gulu 008) and item 53 (Enemy057) to range3CellCircle. Item 57 (Enemy058) has active range0Cell; its commented range3CellCircle line is not an active source field and is not used.
- **resource-derived**: current source weapon fields are accepted for range0Cell, range1Cell, range2Cell, range3CellShoot, range4CellShoot, range5CellShoot, range3CellCircle, range3CellThrust, and range5CellCircle. The builder still rejects any other weapon range rather than substituting a pattern.

## Runtime Contract

- **static-derived**: every range read selects the pattern through PositionCapabilityRules.attack_pattern (weapon_code → ITEM.attack_range → RANGE record). No five-range hard-coded branch was found in those paths.
- **static-derived**: the cells come from the original flood, not the positive mask alone: the player's weapon cells, counter eligibility and the player's cast range run `RangePropagationRules.weapon_coverage` (0x40f8b0) over the battlefield's map words; the rules, callers and remaining flat paths are in 「地形传播」 below.
- **runtime-measured**: the targeted core suite checks that range3CellCircle produces exactly the generated offsets after map-edge clipping, that AI can strike a target in those offsets without moving, and that a defender in those offsets can counter (its fixture has no wall, so the flood equals the mask there).
- **runtime-measured**: item 57 remains equipped as range0Cell; the pattern is valid with an empty hostile target set. This preserves the source item and prevents an unarmed fallback while retaining the existing no-normal-target policy.
- **provisional**: AI skill planning (cast centres) and AI skill casts, and the AI approach goals (`approach_goals`), still read the flat mask; AI weapon strike positions and the in-range／arrival tests read the flood since lane AI-PRIO; the player's cast range, effect area, hover footprint and settlement read the flood since lane WRANGE2. Large actors keep the FootprintRules anchor as the flood origin. See 「调用方与重制接线」.

## Roster join: which weapon the range reads (static-derived)

2026-09-24（lane R25，只读反汇编，无有界执行；`hsl01.exe` sha256 `f0b5f835…`）。矩阵此前把「名册模板的武器与放置实例的武器谁优先／缺武器取什么」标为 provisional。原链只有一个武器字——live 角色记录 `+0xec`——四个写点和一个读点如下：

| 步骤 | 函数／锚点 | 读法 |
| --- | --- | --- |
| ① PLAYERS.TXT 模板 | `0x44b980`：`0x44c0af push "weapon_equip"`→`0x44c0ca mov [ecx+esi+0xec], eax`（模板表 `*0x4c1afc`，步长 `0x1fc`；读前 `var_ch := 0`，字段缺失即 0）。同段 `head_equip→+0xf0`、`armor_equip→+0xf4`、`foot_equip→+0xf8`、`other1_equip→+0xfc`、`other2_equip→+0x100` | 模板武器 = PLAYERS `weapon_equip`，无字段 = 0 |
| ② 安装复制 | `0x44cb10(code, is_player)`：`0x44cb41 rep movsd`（0x7f 个 DWORD ＝ 整条 `0x1fc` 记录）从模板表复制到 live 表 `*0x4c1bc8`；玩家（kind 3）槽号 = code，敌方（kind 5）从槽 21 起取第一个空槽（`0x44cb53 mov eax, 0x15`…`cmp eax, 0xc7`） | live `+0xec` 初值 = 模板武器 |
| ③ EVEF 实例覆盖 | `0x42bd50` 演员分支（对象 kind 3／5）：`0x42bf50 mov eax, [rec+edx*4+0x50]`；`0x42bf5a je`——字为 0 直接跳过；跳转表 `0x42c0a8` case 18 `0x42c055 mov [ecx+0xec], eax`（19→`+0xf4` 护甲、20→`+0xf0` 头、21→`+0xf8`、22→`+0xfc`、23→`+0x100`、24→`+0xe8` 气力），随后 `0x42c096 call 0x448840` 刷新 | **非零实例字覆盖模板武器；零保留模板** |
| ④ ITEM 表 | `0x4477c0`：`0x447a5e push "attack_range"`→`0x447a7e mov [edx+edi+0x84], eax`（ITEM 表 `*0x4c1b40`，步长 `0xb0`） | `ITEM[weapon].attack_range` 落在 `+0x84` |
| ⑤ 范围读点 | `0x409090`：`0x4090bf mov ecx, [rec+0xec]`；`0x4090cd／0x4090f1 shl ecx,4; jne`——**武器 0 → 返回 0**（range0Cell，无普通目标）；否则 `0x4090db／0x409100 mov …, [0x4c1b40+idx*0xb0+0x84]`（＋`+0x18c` bit1 的一档饰品加成；`+0x2c` 大型另加 17 封顶 20，见[位置证据](original_position_equipment.md)的 72 次完整返回） | 范围索引 = 该武器的 attack_range |

与重制的逐项对照：

| 原链 | 重制 | 结论 |
| --- | --- | --- |
| ① 模板 `weapon_equip` → `+0xec` | `tools/hsltools/levels/scenario.py` 单位 `weapon_code = player['weapon_equip']`；换装经 `EquipmentRules` 改写 `weapon_code` | 一致 |
| ③ 实例字 18–23 覆盖装备槽 | `seed.py _actor_instance` 解码为 `overrides.weapon／armor／head／foot／other1／other2`，`evef_instances.json` 列为 `recorded_only_fields`，运行时不应用 | **resource-derived**：70 关 569 个演员实例的 `override_fields` 统计里这六个字均为 0 次（`totals.override_fields` 只有 ai_fixed／find_*／fixed_point／gold／level_adjust_*／stamina／wait_round）——已注册关卡没有任何实例改写装备，未应用路径对现有数据是空操作 |
| ⑤ 武器 0 → 范围 0 | `PositionCapabilityRules.attack_pattern`：`code == 0` → `index 0, offsets []`（无普通目标，不做徒手 fallback） | 一致（17 关三名 062 `weapon_equip` 空因此不动，见[导航证据](original_ai_navigation.md#evef-实例覆盖友军护送目标与物品)） |
| ⑤ `ITEM.attack_range` → RANGE 掩码 | `weapon_code → ITEM.attack_range → RANGE.TXT` 正掩码（本包上文） | 一致；掩码之后还要经 `0x40f8b0` 地形传播（下文「地形传播」） |

未在本读法内：`0x448840` 刷新如何消费 `+0xec` 之外的五个装备槽（已由[装备刷新](original_inventory_equipment.md)覆盖）；EVEF 实例字对非演员对象（宝箱 kind 0x29）的分支属[宝箱包](original_treasure.md)；`0x44cb10` 敌方槽分配在槽表满时返回 0 的调用方处理。

## 地形传播

2026-09-25（lane WRANGE；`hsl01.exe` sha256 `f0b5f835…`，只读反汇编加本机逐函数执行，不启动 Wine）。原版没有一处直接拿 RANGE 正掩码当目标格：武器与施放范围由 `0x40f8b0`（经包装 `0x40fa80`）起点写格后四向调 `0x40f5d0`，技能效果区域由 `0x4100e0` 的矩阵分支调 `0x40fdc0`、RANGE 21..23 走直线分支（[直线范围](original_line_ranges.md)）。两者都只读地图字 `0x4c0928`。[original_range_terrain.json](original_range_terrain.json) 在 open／wall／pillar 三张 15×15 格子上完整执行 354 次（武器 124、矩阵区域 104、直线 126），覆盖字节逐个对拍；`python3 tools/hsl.py check range_terrain` 复核，`tests/run_tests.gd` 让重制逐字节重放。

| 规则 | 原版做法 | 等级 | 重制位置 |
| --- | --- | --- | --- |
| 地图字 | 每格一个 DWORD：WRD `movement_flags & 0x4000` 或上占位者侧位（P `0x10000`、E `0x20000`、N `0x40000`，pmALL `0x70000`，pmMagicAttack `0x800000`）。高度（h 255、blocks_movement）不在任何射程读点里 | static-derived | `RangePropagationRules.cell_words`／`loop_words`；占位者取 `FootprintRules.occupants`，no_block 角色也写侧位属 provisional |
| 起点 | `0x40f8b0`：起点格写 `half+1`，除非起点字命中 `0x40fa48[mode]` 排除位。`0x4100e0` 矩阵：中心格写 `half+1`，除非命中 `0x410498[mode]` 且非 pmALL，或是无角色的 `0x850000` 字；中心不查 `0x4000` 和 RANGE 值 | static-derived | `weapon_coverage`／`area_coverage`；武器与施放的调用方照旧去掉自身格（`cells(coverage, origin)`） |
| 方向与顺序 | 从起点四邻各调一次步进函数（上、下、左、右，power＝`half`）。每步写完按方向深度优先：上→上、左，再原地转向右继续；下→下、左，再转右；左→上、下，再继续左；右→上、下，再继续右 | static-derived | `_flood`／`_visit` |
| 每步次序 | 越界停；字含 `0x4000` 停；RANGE 值为 0 停；已写覆盖 ≥ power 停；值 > 0 写 power（被排除则不写）并做前方检查；power−1，到 0 停。值 < 0 只传递、不写、不做前方检查 | static-derived | `_visit` |
| 障碍停线 | `0x40eb80(x, y, dir, 0x4000)`：步进方向正前方和左右两侧三格里任一带 `0x4000`，本格照写但 power 置 0，不再外传；越界格按 0 读。只在步进表 check 位为 1 的 mode 做（`0x40f874`：2、3、7、8、9、10；`0x4100a0`：除 0、1、4、5 外） | static-derived | `_onward_clear`、`WEAPON_STEP`／`AREA_STEP` |
| `0x4000` 停线 | 带 `0x4000` 的格不写、也不越过；武器、施放、矩阵区域相同；直线遇到即整条结束 | static-derived | `_visit`、`line_coverage` |
| 高差 | 射程读点不读高度：h 255 但无 `0x4000` 的格照常覆盖、照常传播 | static-derived | `cell_words` 只收 `0x4000` |
| 敌我（武器） | 步进表 `0x40f874[mode−2]` 的侧位：命中且非 pmALL 不写但继续传；flag 1 时 pmALL＋pmMagicAttack 也不写。玩家武器调用点 `0x444149` 常数 mode 2（只排除 P：NPC 占位格对玩家武器照亮）；反击 `0x44269c` 与 AI 用 `0x40bab0`：P→2、E→3、N→7，无侧位→`0x10000`（不在表中：不排除、无前方检查）；支援类 `0x40bb00`：8／9／10 | static-derived | `_skip`、`offensive_mode` |
| 敌我（施放） | 玩家施放 mode −1、flag 0：表中无此项，不排除任何占位者、无前方检查，只剩 `0x4000` 和 RANGE 值停线 | static-derived | `PLAYER_CAST_MODE` |
| 敌我（区域） | `0x40fdc0` 步进表 `0x4100a0`：mode 2 不写 P、3 不写 E（pmALL 例外）；无角色的 `0x850000` 不写；`0x40fc90` 找到活角色时先把字清 0，因此照写 | static-derived（角色分支是指令读法：探针角色表为空） | `_skip`、`_no_magic_npc`、`ACTOR` |
| 局部框 | 原函数把 RANGE 局部框裁在地图内 | 未验证（比记录小的地图没有执行） | 不裁：注册战场都 ≥ 20×15，最大记录 13×13 |
| 大型角色 | `0x409090` 给大型角色的武器索引加 17 封顶 20；传播起点取锚点还是身体 | 未验证 | 沿用 `FootprintRules` 锚点 |

### 调用方与重制接线

| 读点 | 原版 | 重制 | 状态 |
| --- | --- | --- | --- |
| 玩家武器可攻击格 | `0x442a90` 内 `0x444156`：`0x40fa80`→`0x40f8b0`，mode 2（`0x444149 push 2` 常数）、flag 1 | `BattlePlayLoop.weapon_cells` → `attack_cells`（高亮、选择、`attack_target` 校验） | 已接，static-derived |
| 反击资格 | `0x4423c0` 内 `0x4426b0`：守方按 `0x40bab0` 取 mode、flag 1，经 `0x409090`→`0x40fa80` 建覆盖，再 `0x40fab0` 查攻方格，命中则在 `0x4c4320` 置 `0x10000` 位；门槛 `test byte [ecx+0x24], 4` 与 `[ecx+0x19e]` | `BattleLoopCombat` 读 `Loop.attack_cells(loop, defender_id)`，`weapon_cells` 按守方 `offensive_mode` | 已接，static-derived（未改 BattleLoopCombat） |
| 敌方／NPC 武器格显示 | 同 `0x40bab0` mode | `weapon_cells` 按 `offensive_mode` | 已接 |
| 玩家魔法／绝技施放范围 | `0x444eb7`／`0x445075`／`0x44508f`：mode −1、flag 0 | `SkillTargetRules.cells(…, terrain)`，`BattlePlayLoop.skill_terrain`；`prepare_cast` 的 `range_terrain` | 已接：选择、确认与结算校验同一组格 |
| 玩家效果区域 | `0x444f08`／`0x4450e0`：`0x4100e0`，mode 2 攻击、3 支援 | `effect_cells`／`line_cells`／`cast_footprint` 在 terrain 带 `area_modes` 时走 `area_coverage`／`line_coverage`；`BattlePlayLoop.player_cast_terrain` 只在玩家指令施放（`attack_select` 的魔法／特技）返回 `skill_terrain`（区域一半只给 P 侧施放者：mode 2／3 是玩家侧常数），`BattleLoopCombat._skill_context` 把它放进 `range_terrain`，`skill_cast_footprint`（悬停自绘格）、悬停目标行、`magic_target_id_at_coord`、自身中心特技范围与 `RepeatedSpecialRules.prepare` 读同一份 | 已接（lane WRANGE2），static-derived；`run_tests.gd` 在第 3 关（毒魔箭贴墙、夹在三名我方之间）、第 504 关（地龍震中心旁 (8,15) 墙、皇龍閃直线遇 (9,16) 墙）钉住预览＝结算，`run_targeting_preview_tests.gd` 钉住自绘格＝`skill_cast_footprint` |
| AI 武器 | `0x40d8b0` 站位：先 `0x411b90` 抹自身占位（`0x40d8c3`），对普通目标 `0x40fa80(目标, 0x409090 射程, 0x40bab0 mode, 0)`（`0x40dbe6..0x40dbfa`），3×3 目标逐身体格 `0x40f8b0(px±32, py±32, 射程, mode, 0)`；「目标在射程内」`0x40fa80(行动者, 射程, mode, 1)` → `0x40fb20`（`0x440d2d`、`0x440c62`、`0x43fca5`）；到站复查 `0x44134a`（`0x441311..0x441369`：清 `0x10000`、`0x411a30` 放回占位、flag 1 覆盖测持有目标，为零 `je 0x441eb8` 不出手） | `AINavigationRules.weapon_terrain`（每回合一次：RANGE 行、mode、全占位字图与抹掉自身的字图）→ `attack_stations(…, terrain)`（站位＝目标覆盖∩可停格，原地＝行动者覆盖含目标）→ `BattleLoopAI._ai_station_attack` 到站 `target_in_range`，不含目标时回 `move`（站位即自身格时 `wait`），`wait_reason = station_out_of_range` | 已接，static-derived（lane AI-PRIO）；`run_ai_navigation_tests.gd` `terrain_range_cases` 钉住并可消融；504／003 探针局面隔墙出手 8／15／21／27 → 0 |
| AI 技能 | `0x40f8b0` 调用方 `0x40cca0`、`0x40d340`、`0x40d530`、`0x40df70`；`0x4100e0` 调用方 `0x40ca71`、`0x4417a6`、`0x4418fd`、`0x441aa0`、`0x441c02`；`0x40fa80` 调用方 `0x441779`、`0x441a73` | `AISkillPlanning` 的施放位与效果格经 `SkillTargetRules`，仍平铺；`approach_goals`（`candidate_filters` 回执、`no_attack` 追击）的武器目标格也仍平铺；AI 施放在 `ai_resolving` 里结算，`player_cast_terrain` 返回空，效果区域也平铺，与 AI 规划一致 | provisional：`SkillTargetRules` 属他 lane；提交走 resolver，不经 `attack_target`，不会被新射程拒绝成循环 |
| `0x44451e`–`0x444592` | range 9..13、mode 4、flag 1，受 `0x45b554` 门控 | — | 未验证（像调试路径） |

### 影响面

旧平铺投影与新传播在 139 个战场（63 种地图：地形文件＋关卡改写）上逐组合比较，一个组合＝一关里的一种武器／技能／效果区域：

| 比较 | 变化／总数 | 去重（地图, 名） | 涉及关卡 |
| --- | --- | --- | --- |
| 开场位置武器格（墙＋占位者） | 313／524 | 167 | 126 |
| 同上，只算 `0x4000` 墙 | 20／524 | 10 | 8 |
| 地图任一非墙格起算的武器格（只算墙） | 33／524 | 23 | 11 |
| 开场位置玩家施放范围 | 44／2163 | 27 | 7 |
| 任一非墙格起算的施放范围 | 43／831 | 29 | 9 |
| 任一非墙中心的效果区域（WRANGE2 起结算与预览都读） | 27／742 | 19 | 9 |

开场武器格变化 481／2516 个单位，大头是 mode 2 不写玩家侧（P）占位格（NPC 占位格对玩家武器照亮）与敌方 mode 3 不写同侧格；墙造成的变化集中在 11 关。复跑（旧规则取本 lane 之前的 `b0f0bee3`，约 90 秒）：

```sh
mkdir -p ignored/wrange-old
git show b0f0bee3:game/sim/SkillTargetRules.gd >| ignored/wrange-old/SkillTargetRules.gd
git show b0f0bee3:game/sim/TacticalGridRules.gd >| ignored/wrange-old/TacticalGridRules.gd
tools/godot.sh --headless --script res://tests/diagnostics/audit_range_propagation_impact.gd -- ignored/wrange-old ignored/wrange-impact.json
```

输出一行 `WRANGE_IMPACT battles=139 maps=63 units_changed=481/2516 …`，逐关清单写进 JSON。5 场自动对局（51、1、3、504、80）胜负、回合数与 `results.json` 相同，无 dead_end。

lane WRANGE2 起，自动对局驾驭器 `tests/support/Autoplay.gd` `_destination` 的落脚格也按落脚后的武器洪泛判定（平铺射程只提候选格），不再走到墙边落地后打不到；第 3／504 关三处墙边站位由 `run_tests.gd` 钉住。

## Remaining Rejections

range2CellCircle, range4CellCircle, range6CellCircle, range4CellThrust, range1CellFull, range3CellDir, range4CellDir, and other range symbols not selected by hsltools/data/attack_ranges.py remain rejected for ordinary weapons because no active first-battle ITEM.TXT weapon currently joins to them. Skill targeting may use its own generated range data and is outside this packet.

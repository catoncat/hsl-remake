# 阵营位：演员的 player mode 覆盖、HP 加值、谁打谁与门／船壳

> evidence: static-derived; resource-derived: OBJ 字段普查与 TYPE.H 位定义; runtime-measured: 裁判开局盘 obj_Data9 换边单位与全库 NPC 最大 HP（DATA9）；整镜像 LEVEL012 62 枚船壳同一 live 记录（改一枚 HP 其余同读）; provisional: 玩家可见后果未原生观察 · status: live · functions: 0x407660, 0x407720, 0x407ec0, 0x40ba20, 0x40ba80, 0x40bab0, 0x40bb00, 0x40bb80, 0x40f5d0, 0x40f8b0, 0x40fdc0, 0x4104d0, 0x42bdb0, 0x43f413, 0x4420ef, 0x446b30, 0x446b60, 0x446be0, 0x44cb10, 0x450710 · tools: hsl_payload_inspector.py, hsltools/levels/battle.py, hsltools/probes/_enemy_level.py, run_tests.gd · updated: 2026-09-27

## 结论

- 原版：演员构造 `0x407ec0` 依次做 obj_Data9 换边（pmPlayer↔pmEnemy，置 +0xa0 位 8）、obj_HitPoint 加到 HP 加值、obj_X1 直接覆盖阵营字 +0x28；AI 目标扫描排除阵营位有交集者，攻击范围丢弃含攻击者首位的占格，胜负计数只数「P 有 E 无」与「E 有 P 无」（static-derived）。
- pmMagicAttack 占位者普通攻击选不中、魔法／绝技选得中；门（pmALL）与船壳（pmNPCPlayerNoMagic，no_attack／no_block／no_showshape）是登记演员，同组船壳共用整份 live 记录（static-derived；12 关整镜像实测改一枚 HP 62 枚同读）。
- 重制：`hsltools/levels/battle.py` 按同序写单位 `player_mode`／`object_hit_point`，`game/sim/ActorRoleRules.gd` 的 `side_mask`／`hostile`／`same_side`／`counts_as_*`／`player_range_selectable` 供全部消费者读取；换边单位的出生 HP 等级项与原版开局盘 111/111 名一致（runtime-measured）。
- 差异：「士兵不打村民」等玩家可见后果只到静态读法（provisional）；支援同侧按「有交集」而非原版「相等」；船壳只共享 HP（provisional）。

## 证据

**resource-derived**：TYPE.H `pmPlayer 0x10000`、`pmEnemy 0x20000`、`pmNPC 0x40000`、`pmPlayerEnemy 0x30000`、`pmNPCPlayer 0x50000`、`pmNPCEnemy 0x60000`、`pmALL 0x70000`、`pmMagicAttack 0x870000`、`pmNPCPlayerNoMagic 0x850000`。148 关 EVEF `defProcEnemy` 演员：`obj_X1` 102 条（pmNPC 39：7 关 036×10／037×5／038×6、21 关 038×5／041×5／043×3、57 关 054、531–533 关 049；pmPlayerEnemy 36：6 关 061×7／062×5、9 关 061×7／062×7、34 关 062×3、65 关 061×3／062×4；pmPlayer 6：900 关 062×6；pmEnemy 21：510–512 关，与模板同值）；`obj_HitPoint` 46 条（024 +50 ×25、023 +20 ×18、024 +30 ×3）。脚本插入对象另有 `obj_X1` 14 条、`obj_HitPoint` 7 条。普查：`hsltools/checks/field_coverage.py --census`。

**static-derived**（r2ghidra 反编译 hsl01.exe）

| 锚点 | 读法 |
| --- | --- |
| `0x407ec0` | `0x44cb10` 复制模板后：obj_Data9≠0 → +0x28 P↔E 互换并 `+0xa0 \|= 8`（`0x407fc3`）；obj_HitPoint≠0 → +0x1b6 `+=`；obj_X1≠0 → +0x28 覆盖；`0x448840` 刷新；过程码 +0x64 不变 |
| `0x40ba20`／`0x40ba80`／`0x40bab0`／`0x40bb00` | 侧位四位 `0x10000｜0x20000｜0x40000｜0x800000`；搜索 mask `~mode & 0x70000`；地面通行模式 P→2／E→3／N→7（阻挡 mask 0x64000／0x54000／0x34000）；支援范围模式 8／9／10 |
| `0x40bb80` | 跳过空槽、自身、已移除；`own & other & 0x870000 ≠ 0` 排除 |
| `0x40f8b0`→`0x40f5d0` | mode 经跳表 `0x40f874`／`0x40fa48`：0–2→排除 0x10000，3→0x20000，7→0x40000，8→0x60000，9→0x50000，10→0x30000，4／5／6 无；格标志 `& 排除位` 且 `(flags & 0x70000) ≠ 0x70000` 不写；第 5 参 `0x4c63ac`≠0 且格有 0x800000 不写 |
| `0x4c63ac` 调用方 | flag=1（`0x43fca5`、`0x440c62`、`0x440d2d`、`0x44134a`、`0x4426b0`、`0x4426ea`、`0x444156`）射程取 `0x409090` 武器；flag=0 为 `0x441779`（MAGIC）、`0x441a73`（SPECIAL）、`0x444eb7`、`0x445075`／`0x44508f` 与 AI 建范围 |
| `0x40fdc0`→`0x4104d0` | 施法范围遮罩同一排除表（`0x4100a0`）但无 `0x4c63ac` 步；`0x40fc90` 后 `(flags & 0x870000) == 0x850000` 的格也丢 |
| `0x407660`／`0x407720` | P 清 E 设 → `*0x4c1b94`（敌方总数）±1；P 设 E 清 → `*0x4c1b90`（玩家总数）±1 |
| `0x450710` actSetPlayerMode | 先 `xor +0xa0, 8`（`0x45073c`，模式不变也翻）；写 +0x28；pmPlayer → 过程码 3、着色 (0x50,0x50,0xff)；pmEnemy → 过程码 5、(0xff,0x64,0xa0)；其他 → 过程码 5、(0xff,0xff,0x50) |
| `0x446be0` | 读 +0xa0 位 8 镜像该演员全部切入对象（[效果对象运动 §4b](original_effect_motion.md)） |
| `0x448851`／`0x448858` | HP 等级项只看刷新时 +0x28 的 pmPlayer 位（[original_job_stats.md](original_job_stats.md)） |

门与船壳：

| 项 | 读法 |
| --- | --- |
| 登记 | 12 关 62、26 关 26 个 row 101，18 关 1 个 row 100（槽 36，格 [29,10]；STORY018 删 EVEF 门再插回同格） |
| 阵营 | 门 pmALL：所有 AI 排除；船壳 0x850000：敌方 AI 候选；`0x40c2f0` 要求相等，无人给船壳回血 |
| 可否被打 | 门：普通攻击与魔法／绝技都选得中；船壳：只有敌方普通攻击能打（范围魔法三处 `0x40ff1f..0x40ff43`、`0x4103f6..0x41041a`、`0x4102ca..0x4102ee` 丢格）；无不死位 |
| no_attack（+0xa0 位 2） | `0x43f413` 短路，轮到时 `0x442084`→`0x407510` 交回合；防守不反击（`0x442646`），攻方命中固定 100（`0x406ed8`） |
| no_block（`0x44c30e` 置 0x10，查 `0x446b30`） | 洪泛 `0x40ef96`、寻路 `0x411335`、点格 `0x443caa`、找占格 `0x40fd81` 都当空格 |
| no_showshape（`0x44c33c` 置 0x20，查 `0x446b60`） | `0x4420ef` 写形号 `0xffff`，形体与底影（`0x43db8b`）都不画 |
| obj_Data7 高位 `0x80000000` | `0x42bdb0..0x42be0b`：首枚调 `0x44cb10` 建记录并存于 `0x4c1ad0`，其余取 `[0x4c1ad0]+0xa4`；共用整份 0x1fc 字节记录（HP +0xd8、状态、阵营、属性）；`0x42be79..` 把各枚覆盖字写进同一记录 |

**runtime-measured**（`hsltools/probes/_enemy_level.py`）：
- 12 关整镜像：62 枚船壳 +0xa4 全为 53，把 actor101_1 HP 写成 700 后 62 枚读出全为 700。
- obj_Data9 单位 113 名中出现在原版开局盘的 111 名等级与最大 HP 全部相同（023 L1 28、023＋20 L1 48、024＋30 L1 72、024＋50 L1 92、52 关 069 L4 40）；全库 127 关 NPC 最大 HP 1487/1487、玩家 1012/1012 相同。

## 重制接线

| 层 | 位置 |
| --- | --- |
| 导入 | `hsltools.sources.scripts.parse_text_metadata` 保留 defProcEnemy／defProcPlayer 的 `obj_X1`／`obj_HitPoint` |
| 组装 | `hsltools/levels/battle.py` `install_player_mode`／`_apply_object_install`：`player_mode` = PLAYERS mode → Data9 互换 → X1 覆盖；`object_hit_point` 加进 `growth_profile.source.hit_point` 与 `max_hp`／`hp`；`align_birth_hp` 按安装后 mode 取 HP 等级项；`side_swapped`、`shared_record`、`no_showshape`、`dead_message`、`title` |
| 角色 | 有 pmPlayer 位 → `friendly_ai`，无 → `enemy_ai`；注册槽安装仍 `player_controlled` |
| 规则 | `game/sim/ActorRoleRules.gd`：`side_mask = player_mode & 0x70000`（无 mode 按角色）、`hostile`（无交集）、`same_side`（有交集）、`counts_as_enemy`／`counts_as_player`、`player_range_selectable`（pmALL 且魔法射程或无 0x800000） |
| 消费者 | `BattlePlayLoop._are_enemies`、`AISkillPlanning`、`AISupportPlanning`、`SkillTargetRules.side_matches`／`area_side_matches`、`ActorTraversalRules`、`WinfailConditions`、`WinfailActions._apply_player_mode`（翻转 `side_swapped`，支持 pmPlayerEnemy、pmNPC、pmMagicAttack）、`JobStatsRules.base_values` |
| 门／船壳 | 模板 `content/generated/hsl/actors/100.json`／`101.json`；`standing_actor_code`／`standing_actor_inserts`；`BattleLoopAI._idle_without_strategy`；`ActorRuntime.hide_shape`；`game/sim/SharedRecordRules.gd` 在 `BattleLoopScript._resolve_outcome` 开头把同组活船壳 HP 并成一池 |

provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_player_mode_sides.md`。

## 复现

`tools/godot.sh --headless --script res://tests/run_tests.gd`（打印 `PLAYER_MODE_SIDES_ATTACK` 行：6 关全待机前两回合 023 只打漢克斯／雷歐納德，村民 0 次被打、0 次出手）。

## 边界

- 玩家可见后果（士兵不打村民、531–533 关 049 与其余敌军互打、24 关三方、44／45 关与 34 关到场阵营）未原生观察；替换证据为原版存档预设 `level06_pre_battle` 加原版全待机两回合读 +0x28 与目标。
- 支援同侧按「有交集」；原 AI 支援扫描要求相等、支援范围 8／9／10 只留同首位格，未按原读法改。
- `0x800000` 位被 `side_mask` 丢弃；魔法范围对该位的排除未接。
- `0x450710` 的按模式着色未接。
- 船壳只并 HP；池归零后其余船壳保持最后正值；同一行动打两枚时逐次截断未核对；船壳计入玩家总数未单独核对。
- `obj_Y1`（+0x134）未进数据链。

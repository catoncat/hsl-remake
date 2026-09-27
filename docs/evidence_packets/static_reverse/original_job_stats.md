# 职业：初始化、成长与装备的共同刷新 `0x448840`

> evidence: static-derived; provisional: 合成初始化 · status: live · functions: 0x448370, 0x448420, 0x448800, 0x448840 · tools: hsl_native_stats_probe.py, hsltools/data/role_profiles.py, hsltools/probes/job_stats.py, run_job_stats_tests.gd · updated: 2026-09-27

## 结论

- 原版所有角色的派生值由同一个 `0x448840` 刷新：清工作槽→按 job−80 分派职业分支→累加装备→公共尾部夹取；源 mode 位 `0x10000` 只决定 HP 公式里的等级项；当前 HP/MP 只向下夹、不回满（static-derived）。
- 重制 `game/sim/JobStatsRules.gd` 按职业公式表（`content/authored/roles/job_formulas.json` → `content/generated/hsl/roles/job_formulas.json`）求职业基础部分，`ProgressionRules` 叠加一次当前装备并统一更新上限、速度、抗性与 move_point；新职业只加表行（static-derived）。
- 一致：六个源模板 108 组输入 × 2 次完整返回（共 216 次）与重制逐项相同；职业 91／99 分支见 [original_job_stats_91_99.md](original_job_stats_91_99.md)。探针对象是合成初始化，模板值不是关卡现场数值（provisional：现场等级由 [入场调级](original_auto_growth.md) 决定）。

## 证据

**static-derived**（EXE SHA 锁定；机器包 [original_job_stats.json](original_job_stats.json) 保存源表哈希、原字节与返回值；第二次刷新前先污染旧派生槽，确认不累加）

| 原入口／表 | 结论 |
| --- | --- |
| `0x448840` | 清工作槽、分职业计算、应用当前装备、统一夹取与当前资源收束 |
| `0x448370`、`0x4786bc` | 四属性上限按职业索引：80 为 90/88/80/94，90 为 84/78/100/90，94 为 107/80/66/99 |
| `0x448420` | 累加装备 |
| `0x448800` | 攻击等级增量：1–9 按等级，10–19 每两级 +1，20 起每四级 +1；不受源 mode 门禁 |
| `0x449e9c`、`0x44a74e` | 原 dispatch 所选 Magician／BeastWarrior 分支（名称是项目标签） |
| `0x44b62c`／`0x44b655` 起公共尾部 | HP/MP 模板附加、HP ≥ 1、移动 0..12、五类抗性 0..80；`0x44b678` 升级门槛 |
| `0x44b7b8..0x44b815` | 合并六个已学魔法槽；全空时置禁用 MP 标记并清零 MP |
| actor `+0x28` 位 `0x10000` | HP 等级项门禁；与当前可控或 Godot 阵营无关，临时改控制权不改写 |

108 组覆盖：实际初始装备、等级 2/9/10/19/20/40/99、四属性各 +1、职业上限、源 mode 翻转、空装备、重复抗性饰品、HP/MP 回复装备、减耗与白光之翼组合。

1 级模板刷新值（`hsl_native_stats_probe.py`，合成初始化，含初始装备；[first_battle_template_stats.json](first_battle_template_stats.json)、[second_battle_template_stats.json](second_battle_template_stats.json)）：

| 模板 | 源 mode | HP | MP | 攻 | 防 | 速 | 命中 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 001 雷歐納德 | pmPlayer | 30 | 0 | 54 | 43 | 14 | — |
| 021 敌步兵 | pmEnemy | 22 | 0 | 45 | 30 | 15 | — |
| 023 友军步兵 | pmPlayer | 29 | 0 | 45 | 36 | 14 | — |
| 024 友军重兵 | pmPlayer | 43 | 0 | 52 | 61 | 12 | — |
| 026 敌法师 | pmEnemy | 33 | 30 | 21 | 22 | 11 | — |
| 025 | pmEnemy | 91 | 24 | 58 | 46 | 16 | 92 |
| 069 | pmPlayer | 40 | 0 | 54 | 38 | 42 | 98 |

069 的 PLAYERS 模板为 pmPlayer，而其地图对象用精灵 022、过程 `defProcEnemy`：两源不一致，阵营不按名字或对象过程推定。

## 重制接线

- `game/sim/JobStatsRules.gd`：表驱动职业项；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_job_stats.md`。
- `game/sim/ProgressionRules.gd`：叠加当前装备并统一刷新；初始化先复制模板，不回写调用者。
- `tools/hsltools/data/role_profiles.py`：从机器包与源表生成 role profile，第一／第二战生成器共用；`tools/hsltools/data/first_battle_formation.py` 读模板 JSON 生成 hp/max_hp 与法师 initial_mp。
- profile 区分 `allocation=manual`（玩家五点）与 `fixed_template`；初始 queue 在刷新后构造，战中换装／升级到下次 wrap 才读新速度。

## 复现

`python3 tools/hsl.py check job_stats`

重制侧实际输入回执：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [role_resources](../runtime_observations/role_resources/receipt.json) | mage_growth、heavy_growth、sword_double、poison_recovery、second_remove_restore、support_recovery、detour、ai_half_cast、ai_mp_return、ai_item_restore、victory、defeat、escape | `capture_role_resources_review.gd`、`run_job_stats_tests.gd`、`run_resource_recovery_tests.gd` |

## 边界

- 未执行原初始化随机调级、表解析器与完整主循环；探针只运行属性刷新。
- 转职、动态学技、弱化／增益对基础槽的重写不在本包。
- 空装备只证刷新算术，不表示徒手攻击范围已支持；合成跨职业装备组合不放宽 use_job 资格。
- 资源装备的行动循环见 [original_resource_recovery.md](original_resource_recovery.md)。

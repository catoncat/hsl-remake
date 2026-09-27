# 诊断脚本（不是门禁，用完即删）

这里放一次性诊断脚本：`run_all`、`verify.sh` 和深门都不跑它们，它们也不产出验收回执。用途结束就删掉脚本和同名 `.gd.uid`，并同步删掉文档里指向它的命令。

| 脚本 | 用途 | 何时删 |
| --- | --- | --- |
| [export_enemy_turns.gd](export_enemy_turns.gd) | 原版敌人回合裁判的重制端：给定关卡、随机流起点和局面，逐个 NPC 跑一回合，每回合一行 JSON；[`_enemy_level.py`](../../tools/hsltools/probes/_enemy_level.py) 调用它并与原版逐行动、逐抽取对照（[§11](../../docs/evidence_packets/static_reverse/original_enemy_turn.md)） | 裁判退役时（`_enemy_level.py` 不再调用它） |
| [export_opening_snapshot.gd](export_opening_snapshot.gd) | 开局盘面全字段对拍的重制端：每关同一刻（出生后、首回合排序前）导出每个单位字典与派生值（g0 零成长、g1 多种子＋出生上下界）；[`_opening_snapshot.py`](../../tools/hsltools/probes/_opening_snapshot.py) 导出原版整条活记录，`python3 tools/hsl.py generate opening_snapshot` 对拍成 [报表](../../content/generated/hsl/development/opening_snapshot_diff.md) | 开局字段差异清零、报表不再需要重生成时 |
| [export_ai_action_frequency.gd](export_ai_action_frequency.gd) | AI 行动种类频率对拍的重制端：继承 `export_enemy_turns.gd`，一个进程跑多关 × 多种子（每局与裁判批量的重制导出同参数），[`ai_action_frequency.py`](../../tools/hsltools/probes/ai_action_frequency.py) 按种类计数、与原版裁判对照成 [报表](../../content/generated/hsl/development/ai_action_frequency.md) | 裁判退役或报表不再需要重生成时 |
| [replay_ai_actions.gd](replay_ai_actions.gd) | 回放判定的重制端：继承 `export_enemy_turns.gd`，把原版裁判首轮每个队列槽的 AI 抽签按调用点喂给重制（四种喂法），盘面每步按原版校正，逐槽比落点／动作／目标；[`ai_replay.py`](../../tools/hsltools/probes/ai_replay.py) 判规则／随机／口径成 [报表](../../content/generated/hsl/development/ai_replay.md) | 裁判退役或报表不再需要重生成时 |
| [compare_ai_global_draws.gd](compare_ai_global_draws.gd) | 第 51 关首次控制局面上，重制 AI 的全局流抽取与原版模拟回合逐行动对照 | AI 全局流对齐收口后 |
| [audit_range_propagation_impact.gd](audit_range_propagation_impact.gd) | WRANGE：平铺射程和地形传播在全部战场上的差异面（[地形传播](../../docs/evidence_packets/static_reverse/original_weapon_ranges.md)） | 射程传播规则不再改动时 |

运行：`tools/godot.sh --headless --script res://tests/diagnostics/<脚本>.gd -- [参数]`，参数见各脚本开头的注释。

# 装备：移动力增量与基础属性刷新

> evidence: static-derived · status: live · functions: 0x448840 · tools: hsltools/probes/mobility.py, run_position_equipment_tests.gd · updated: 2026-09-27

## 结论

- 原版每次 `0x448840` 刷新先把 PLAYERS 基础移动力 `+0x130` 复制到当前值 `+0x12c`，再逐件加装备 `add_move`（`+0x34`），最后夹到 0..12；当前值从不作为下次基础（static-derived）。
- 重制 `game/sim/MobilityRules.gd` 按同一式从 `base_move_point` 与当前装备重算唯一 `unit.move_point`，玩家范围／路径与 AI 接近／移动后攻击共读；换装经 `EquipmentRules.replace` 提案、`ProgressionRules.refresh_input_error` 校验后一次提交（static-derived）。
- 一致：39 个输入 × 2 次共 78 次完整返回与重制逐项相同；换装后保留已接受的待提交位置、取消按现装备重算是重制交互合同（provisional）。

## 证据

**static-derived**（`hsltools/probes/mobility.py` 执行 SHA 锁定 EXE 与已审查子函数，不替换返回、不造 stub；[original_equipment_mobility.json](original_equipment_mobility.json) 存 PLAYERS／ITEM／TYPE 哈希）

| 地址／范围 | 内容 |
| --- | --- |
| `0x44c261..0x44c27f` | PLAYERS.move_point 写入基础 `+0x130` |
| `0x447a0b..0x447a31` | ITEM.add_move 写入有符号增量 `+0x34` |
| `0x448987` | 刷新先复制 `+0x130` → `+0x12c` |
| `0x4486bb` | 每件实际装备把 `+0x34` 加到当前值 |
| `0x44b760` | 全部装备处理后夹到 0..12 |

78 次覆盖：六类现有角色无装备／源装备；基础 −3／0／1／5／10／11／12／15；三件装备单独与组合、两个饰品槽叠加；每例 1 级与 40 级，旧当前值预置 1234／−987。输出始终由基础加装备重建；HP1、MP0、EXP37、ST20 不被补满或消费。负数与超上限基础是算术夹具。

**resource-derived**

| ITEM | 名称 | add_move | 重制 |
| --- | --- | --- | --- |
| 138 | 蒼空之鎧 | 1 | 可换装 |
| 193 | 舞空之靴 | 1 | 可换装 |
| 231 | 追風之羽 | 1 | 饰品槽分别叠加 |
| 194 | 神之足 | 2 | 另有错拼列 `add_defnese`，原 loader 按名查字段而丢弃（见 [original_field_coverage.md](original_field_coverage.md)） |
| 236 | 穹蒼之鍊 | 1 | 另有范围与移动施法位，见 [original_position_equipment.md](original_position_equipment.md) |

## 重制接线

- `game/sim/MobilityRules.gd`：来源校验与加总；`base_move_point` 为原基础字段。
- `game/sim/EquipmentRules.gd`、`game/sim/ProgressionRules.gd`：缺字段、非整数、NaN／Infinity、越界或未知装备不半换装；成长从基础重算，不以敏捷或当前值作基础。
- 源角色生成器把基础与装备后值写入第一／二战配置，PlayLoop 初始化按实际装备重建同值；Checkpoint 校验 base、装备与 move_point 一致，加载不重跑初始化或 RNG。
- 装备预览先显示移動力前后；成长预览在原区域内滚动显示完整属性（重制 UI 合同）。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_equipment_mobility.md`。

## 复现

`python3 tools/hsl.py check mobility`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [equipment_mobility](../runtime_observations/equipment_mobility/receipt.json) | equip_growth、pending_restore、ai_without、ai_boots、victory、defeat、escape | `capture_equipment_mobility_review.gd`、`run_position_equipment_tests.gd` |

## 边界

- 探针只断言移动力与四种资源，不推导其他派生属性等价。
- 原角色随机初始化、临时移动状态、飞行／占地 flags、原装备 UI 与原存档未执行。
- 换装后保留待提交位置与静止边界保存是重制交互，不作原 UI 等价。

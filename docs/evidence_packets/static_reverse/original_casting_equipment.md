# 装备：生命转魔力、状态防护与魔法命中

> evidence: resource-derived; static-derived · status: live · functions: 0x406fe0, 0x4094c0, 0x40e210, 0x40e430, 0x439f80, 0x448420, 0x448840 · tools: capture_casting_equipment_review.gd, hsltools/probes/casting_equipment.py, run_position_equipment_tests.gd · updated: 2026-09-27

## 结论

- 原版怨念血衣在最后一次行动尾部按当前最大 HP 两次三角采样，扣 `min(hp-1, 采样)` 生命、回 `min(max_mp-mp, 实损)` 魔力，满魔或无 MP 职业仍扣血；防毒／防禁魔是装备并集，只挡后续施加、不解除已有状态；魔法命中饰品只加主命中，不加状态成功率（static-derived）。
- 重制 `game/sim/ResourceRecoveryRules.gd` 在自动回复之后转化，`game/sim/TurnEndRules.gd` 按 毒伤→HP 回复→MP 回复→转化扣 HP→转化加 MP 一次提交；防护与命中由 `game/sim/StatusApplicationRules.gd` 的 `modifiers` 从当前装备重算（static-derived）。
- 一致：80 次 refresh 完整返回与 243 组转化样例与重制逐项相同；0.7 秒逐段反馈是重制时钟（provisional）。

## 证据

**static-derived**（[original_casting_equipment.json](original_casting_equipment.json)；原 EXE 只读，Unicorn 合成内存与边界保护，未替换 callee）

| 原入口／字段 | 行为 | 回执范围 |
| --- | --- | --- |
| ITEM loader `0x447983`；装备应用 `0x4485b6` | `add_magic_hit` 存 item+0x1c，累加到 actor+0xd4 | 字节锚点、80 次完整 refresh；+0xd4 不加到状态成功率 |
| loader `0x4480e5` | `avoid_poison` = 主效果 `0x800000`，`avoid_nomagic` = `0x1000000` | 字节锚点、refresh 合并、既有免疫 helper |
| loader `0x4481b8`，getter `0x40e210` | `hp_transfer_mp` 在 item+0xa4、actor+0x190 位 1，与主效果字分开 | 完整转化调用路径与字段锚点 |
| `0x448840`→`0x448420` | 清旧工作值，再从当前装备累加命中、OR 防护／转化；保留已有中毒／禁魔 | 40 组 × 2 = 80 次完整返回，每次预置脏值，不叠加；HP/MP/ST/EXP 与状态原样 |
| `0x4094c0`→`0x406fe0` | 两次三角采样，按可付生命换魔力；HP 最低 1，MP 独立封顶 | 243 组：144 组有效前段停在 `0x40959f` 首个数字 renderer 前；99 组无损耗完整返回（含 1HP 仍抽样） |
| `0x40e56b` | 已有 HP 回复、MP 回复之后才调转化 | caller 字节；不执行含 renderer 的完整末次行动 dispatcher |
| `0x439f80`、`0x43ae60` | 职业余量分配与资格更新 | 仅定位，未接入 |

采样式：`low = max(1, floor(max_hp*8/100))`，`high = max(low+1, floor(max_hp*12/100))`，`half = floor((high-low)/2)`，结果 `low + half - r1 + r2`，r1、r2 ∈ 0..half；奇数跨度不等价于含两端的均匀采样。1HP 时不扣不回但仍抽两次；未装备时不抽。refresh 样例覆盖 job80／90、六件装备及组合、已有毒／禁魔；原 refresh 不查职业资格。

**resource-derived**

| 装备 | 效果 |
| --- | --- |
| 怨念血衣 145 | 最后行动生命转魔力；含原防御值 |
| 清心法衣 128／銀製髮飾 217 | 防后续中毒，并集生效 |
| 深紅之瞳 219 | 防后续禁魔；复合技能前段伤害照常 |
| 學者眼鏡 215／魔操玉 226 | 各 +10 魔法命中；魔操玉另有原魔击增量，两件合计 +20 |

主命中 `hit_ratio + hit_bonus + magic_hit_bonus`；状态成功检查 `proc&4` 只用 `status_hit_ratio`。

## 重制接线

- `game/sim/ResourceRecoveryRules.gd`、`game/sim/TurnEndRules.gd`：两次抽样取共用 [伤害随机流](original_damage_random.md) `damage_rng`，只有非零变化进入反馈；白光之翼第一行动不走该出口。
- `game/sim/StatusApplicationRules.gd`：玩家、AI、范围目标与存档共用 `modifiers`；全免疫毒雾无有益候选，混合范围逐目标免疫、一次付款。
- `game/sim/EquipmentRules.gd`、`game/battle/scene/BattleItemPanel.gd`：按源 `use_job` 装卸与八槽交换；预览说明「满魔仍耗生命」「防护不解除已有状态」。
- 保存 policy `source_resource_tail_v2`，收据可重算；旧配置不兼容。终态冻结未执行的尾部能力。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_casting_equipment.md`。

## 复现

`python3 tools/hsl.py check casting_equipment`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [casting_equipment](../runtime_observations/casting_equipment/receipt.json) | poison_tail、full_mp、one_hp、remove_restore、accuracy、blood_growth、blood_support、blood_item、poison_guard、silence_guard、detour、ai_blood、ai_silence、victory、defeat、escape | `capture_casting_equipment_review.gd`、`run_position_equipment_tests.gd` |

## 边界

- 转化后续 MP 数字的调用次序只有字节记录，完整含 renderer 的返回未执行。
- 原样例不证明每个职业都可穿每件装备；产品按源 `use_job`。
- 伙伴自动成长与动态学技（`0x439f80`／`0x43ae60`）未接入。
- 其他命中附带状态与完整高位 dispatcher 不在本包。
- 转化反馈无原音效绑定；0.7 秒反馈时钟为重制选择。

# 装备：移动后施法资格与普通攻击范围

> evidence: resource-derived; static-derived · status: live · functions: 0x409090, 0x4097d0, 0x40d340, 0x40e240, 0x40e270, 0x43ea30, 0x448840 · tools: capture_position_equipment_review.gd, hsltools/probes/position_equipment.py, run_position_equipment_tests.gd · updated: 2026-09-27

## 结论

- 原版只有装备效果位 `0x1000`（移动施法）的角色移动后才能施法，玩家 mode1 菜单与 AI 施法选点查同一位；装备 bit1 让普通攻击的源范围索引最多 +1，法术只读自己的 range；多来源同一效果按 OR，不叠两档（static-derived）。
- 重制 `game/sim/PositionCapabilityRules.gd` 从当前装备与角色声明计算两种能力，`BattlePlayLoop` 命令资格与最终确认核对本行动是否已移动，`game/sim/SkillResolutionRules.gd` 核对移动施法提案的新站位；攻击、反击、AI 候选、预告共读同一范围（static-derived）。
- 一致：88 次 getter／范围完整返回、24 次装备刷新完整返回与重制相同；菜单与 AI 只执行 55 个前段，AI 路径平分／中心随机流、反馈时钟与静止存档为 provisional。禁魔／MP 不足时重制保留禁用技能列表，不等同原版隐藏菜单（已知差异）。

## 证据

**static-derived**（[original_position_equipment.json](original_position_equipment.json)；原 EXE 哈希核对、合成内存，未替换或跳过 callee）

| 入口 | 内容 | 回执 |
| --- | --- | --- |
| `0x409090` | 有武器时以 item+0x84 为范围索引，主效果 bit1 最多再 +1；无武器返回 0；size 低字非零另 +17、封顶 20 | 72 次完整返回（含无武器、普通／大体型、合成边界索引） |
| `0x40e270`→`0x40e240` | 查 actor+0x18c 的 `0x1000` 位 | 7 次完整返回 |
| `0x4097d0` | 读指定法术表自身 range，忽略武器范围加成 | 9 次完整返回 |
| `0x43ea30..0x43ebf3` | 生成未移动／已移动命令字符：mode1 无移动施法位时移除 magic，禁魔另行移除；special 不受此位限制 | 48 个前段，停在菜单几何与对象创建前 |
| `0x40d3f7` | 已选法术后查移动施法位：有则可移动站位搜索，无则原地中心搜索 | 7 个前段，停于 `0x40d404`／`0x40d439` |
| `0x448840` 及装备应用 | 当前槽 OR 移动施法／范围位，加总 add_move；能力 400 只在非空装备应用后映射成 `0x1000`；刷新清旧工作值 | 12 组 × 2 次完整返回（源装备值配合成 job90，含两件相同饰品与固有能力） |

ITEM loader `add_attack_range→1`、`move_magic_use→0x1000`，PLAYERS `move_magic_use→capability 0x400` 与非空装备映射由固定字节锚点约束。`0x409090`、`0x40e270`、`0x4097d0` 登记于 `known_functions`；`0x40d340` 只执行中段资格分支。

**resource-derived**

| 装备 | 效果 |
| --- | --- |
| 冥晦之輪 232 | 移动后可施放自身拥有且合法的魔法 |
| 奧義之證 233 | 普通攻击／反击范围提升一个源索引 |
| 穹蒼之鍊 236 | 两种能力兼有，并 +1 移动力 |

RANGE.H 普通索引 1／2／3；源武器只用 1／2，加成后可到 3。RANGE.TXT 中三者均为四向十字，分别 4／8／12 格，不含自身格，不是曼哈顿菱形。

## 重制接线

- `game/sim/PositionCapabilityRules.gd`：只算结果，不另存能力状态。
- `BattlePlayLoop`：取消选目标仍处于移动后阶段，只有取消待提交移动回原点才恢复未移动资格；换装免费，可在移动后获得或失去施法资格，不加移动预算。
- 白光之翼两次独立行动：第一次只移动／待机，第二次可在新位置原地施法；第二次再移动则重新需要移动施法能力。双击不重置行动阶段。
- AI 有权限时遍历合法移动施法格，无权限只试原地施法；目标死亡、能力移除、MP 耗尽、禁魔或路径失效时旧候选不支付不移动，回退普通攻击／物品／等待。
- UI 移动预览提示「移動後不能施法；取消可返回原位」，移动后隐藏不合法的魔法入口（重制可读性）。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_position_equipment.md`。

## 复现

`python3 tools/hsl.py check position_equipment`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [position_equipment](../runtime_observations/position_equipment/receipt.json) | cancel_equip、remove_restore、double_growth、counter_range、support_cure、no_mp_item、silence_special、detour、ai_stationary、ai_mobile、ai_silence、ai_wait、ai_support、ai_retarget、victory、defeat、escape | `capture_position_equipment_review.gd`、`run_position_equipment_tests.gd` |

## 边界

- 大体型 +17 范围分支只记录，不证明多格占地（见 [original_large_actor.md](original_large_actor.md)）。
- 源射击／方向／大型专用范围矩阵未开放。
- 菜单与 AI 只有前段；完整对象状态机、地图搜索与 AI 随机流未执行（provisional）。
- 禁用技能列表与原隐藏菜单不同（已知差异）。
- 三件装备不进默认库存。

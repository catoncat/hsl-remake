# 库存与装备：八槽库存、六装备槽与当前装备刷新

> evidence: static-derived; resource-derived: ITEM／TYPE／PLAYERS 表值 · status: live · functions: 0x409090, 0x40e2a0, 0x40f8b0, 0x430710, 0x436e30, 0x436e80, 0x436ed0, 0x436ef0, 0x436f30, 0x437020, 0x4423c0, 0x4464f0, 0x4466d0, 0x4477c0, 0x448420, 0x448840, 0x46db10, 0x46de00, 0x472ec0 · tools: hsltools/data/attack_ranges.py, hsltools/data/equipment.py, hsltools/evidence/inventory_equipment.py, run_inventory_equipment_tests.gd · updated: 2026-09-29

## 结论

- 原版：每个角色八个库存 DWORD（0 为空、同 code 不堆叠、首空插入、删除左移）；六个装备槽由 setter `0x436f30` 查职业、类型和旧装备 `take_off` 锁，失败 -1、成功返回旧 code；卸下 `0x437020` 禁止时返回 0；属性由 `0x448840` 从基础值加六槽 `0x448420` 统一刷新并夹紧（static-derived）。
- 重制：`InventoryRules`、`EquipmentRules`、`ProgressionRules` 纯规则，PlayLoop 唯一提交；换装为「校验→取新物→换槽→旧物首空→统一刷新→一次提交」；战斗内由 mode4／5 持物窗触发、提交后旧物进手（static-derived；持物草稿为 provisional，见 [original_item_actions.md](original_item_actions.md)）。
- 原版读表：ITEM loader `0x4477c0` 只按 EXE 内的字段名取列，常量名经 `0x46db10` 以 `_stricmp` 不分大小写解析，武器射程索引由 `0x40f8b0` 通用传播；故 194 神之足、222 龍鱗、71 朧月 都能装（static-derived）。
- 差异：原版暂持物中间态、取消归还与行动标志未全恢复；未知字段与未识别常量仍禁止装备，现有 ITEM 行已无此类装备（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；31 段指令／数据锚点见 [original_inventory_equipment.json](original_inventory_equipment.json)）

角色：对象 +0xa4 为 roster index，全局 `0x4c1bc8` 指向步长 `0x1fc` 的记录，库存在 +0x138..+0x154。

| 原函数 | 行为与返回 |
| --- | --- |
| `0x436e30` | 扫 0..7，首空写 code 返回 1；满返回 0 不改 |
| `0x436e80` | 删指定槽，后续 `(7-index)` 项左移，末槽清 0；EAX 不作成功标记；无负索引保护 |
| `0x436ef0` | 同类删除，输入为角色记录指针 |
| `0x436ed0` | 返回末槽 code，不是数量 |

八格容量来自循环上界与字段访问，不由 PLAYERS item1..item8 推断。

ITEM 全局 `0x4c1b40`，步长 `0xb0`；type +0x8、flags2 +0xa4、职业 mask +0xa8。

| setter slot | 角色偏移 | 原 type | 重制槽 |
| --- | --- | --- | --- |
| 0 | `+0xec` | 2 Weapon | weapon |
| 1 | `+0xf0` | 3 Head | head |
| 2 | `+0xf4` | 4 Body | armor |
| 3 | `+0xf8` | 5 Foot | foot |
| 4 | `+0xfc` | 6 Other | accessory1 |
| 5 | `+0x100` | 6 Other | accessory2 |

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| 职业 mask | `0x4464f0` | job 80..100→bit 0..20，其他 -1；setter 对 job 1000 跳过职业检查；loader `0x44826a..0x448318`：jobAll=1000 全 1，jobAllNoPlayer8=1001 清 bit16／17；use_job=0 无有效 bit |
| take_off | `0x4481d7` 读字符串 `0x47886c`，`0x4481ec..0x4481f2` 置 bit1，`0x448207` 存 ITEM+0xa4 | 非零阻止卸下／替换；与 important（+0xa0）不同 |
| 暂持取出 | `0x4292aa` | 选中 code 放 `0x4c1ce4` 并调删除 |
| 装备路径 | `0x429e18` 读暂持 → `0x429e24` setter → `0x429e3f` 旧装备入暂持 → `0x429e59` refresh；卸下返回非零才 `0x429ea1` refresh | — |
| 六槽应用 | `0x44b5de..0x44b627` 依次调 `0x448420` | 先算职业基础，再加装备 |
| `0x448420` | weapon：attack_damage、hit_ratio 加到攻击／命中；head／body：attack_damage 加防御；foot：加速度 | 通用字段 add_weapon_hit、add_attack_power、add_magic_power、add_hp/mp、add_speed/defense、add_miss_hit、add_attack_back 与抗性 |
| 抗性分组 | 同函数分支 | 0..4 土水风火心；7 全五类；8 前四类；9 水火、10 土火、11 风火、12 火心、13 土水、14 水风、15 水心、16 土风、17 土心、18 风心 |
| hp_damage_half | loader `0x447e00..0x447e1b` 置 item+0xa0 bit 4；`0x448709..0x448717` 并入 actor+0x18c；`0x4423c0` 在 `0x442545` 调 `0x40e2a0`（测守方 bit 4） | 普攻／反击伤害非零时 `sar 1` 减半，得 0 取 1；技能不经此路（`0x40e2a0` 只有这一个调用点）。302 替身雕像 |
| high_cost | loader `0x448164` 置 item+0xa0 bit 0x800，`0x4481b1` 存入，同样并入 +0x18c | 规则代码无测该位的 test／and，`0x40e240` 包装掩码无 0x800：无规则效果；唯一读者是说明框 `0x430710`（`0x432946` `test ah, 8`）写 RESOURCE 618 高價值。130／157／186／210 |
| 字段名读取 | ITEM loader `0x4477c0` 每列按名调 `0x4466d0`（`0x46dd50` 取值串、`0x46de00` 解析） | EXE 字串表无 `add_defnese`：194 神之足的错拼列从不读入，照常可装，防御不加 |
| 常量解析 | `0x46de00` 先 `0x45b5fa` 按数字（十进制、`0x` 十六进制、`-`／`~`），失败则 `0x46db10` 沿 #define 表逐项调 `0x472ec0`（`_stricmp`，A..Z 折叠）匹配名字再取值串重解析；add_resist 在 `0x4478bf..0x447939` 逐段走同一路径 | 名字不分大小写：222 龍鱗 `magic4Type` 命中 TYPE.H `magic4TYPE`=8，抗性分组 8（土水风火各 +5） |
| 武器射程 | `0x447a5e` 读 attack_range 存 ITEM+0x84；`0x409090` 返回 ITEM+0x84（actor+0x18c bit1 扩展 +1；大体型 +0x11 封顶 20），`0x40f8b0` 按 RANGE 行洪泛，无按索引分支 | range6CellShoot（RANGE.H 7）与其他射击掩码同一规则；71 朧月 可装，扩展后为 range7CellShoot（8）；0x40f8b0 对 range6CellShoot 的完整执行见 [original_range_terrain.json](original_range_terrain.json) |
| 夹紧 | `0x44b6ca..0x44b75a` 抗性 0..80；`0x44b77e..0x44b7b8` 攻击／魔击／防御／速度下限 0 | HP／MP 当前值只向下夹，不因上限增加而治疗 |

Equip 是 state7 mode4（`0x444185`），Drop 是 state8 mode5（`0x4441ac`），两者同一持物窗（装备板点击 `0x43993e` setter／`0x439998` 卸下），窗体与关窗流程见 [original_item_actions.md](original_item_actions.md)。

**resource-derived**：字段名与类别来自 `ITEM.TXT`、`TYPE.H`、`PLAYERS.TXT`、`RESOURCE.TXT`；表字节身份写入 `content/generated/hsl/equipment/items.json`。Leonard 初始库存 `[241,241,241,246,0,0,0,0]`；3 号銀劍 add_magic_power=5。TYPE.H 的 magic4TYPE 与 ITEM 222 的 magic4Type 大小写不一致，按原解析视为同名。

**runtime-measured**（重制侧 Control 回执，已随回执目录删除）：夹具给 Leonard 3 号銀劍，预览攻击 54→59、魔击 17→22、速度 14→16，确认后 HP 17/30 不变；卸下再装头盔防御 43→37→43；满包卸头盔被拒（当时的重制行为；现按 `0x437020` 卸到手上，见上文）；饰品 201 可选第二槽。

## 重制接线

- `game/sim/InventoryRules.gd`：首空插入、有序删除、执行前校验索引与预期 code；provenance 头 `rules: static-derived docs/evidence_packets/static_reverse/original_inventory_equipment.md`。
- `game/sim/EquipmentRules.gd`：接收当前装备与只读 catalog（`EquipmentCatalog` 读缓存返回副本）；`ProgressionRules` 接收显式 catalog；换装、加点、升级在改字段前检查属性源完整性，缺项以 `scenario_error` 整笔拒绝。
- `hp_damage_half` 由 `EquipmentRules.has_flag` 读出，`BattleLoopCombat.apply_strike` 传给 `CoreCombatRules.resolve_attack` 的 `damage_halved`；`high_cost` 在 `equipment.py` 的 `INERT_FIELDS` 里不影响可装，只导出给说明框（`BattleEquipmentView.flag_row`）；错拼列在 `LOADER_ABSENT_FIELDS` 忽略；TYPE.H 常量表不分大小写查找；武器射程表与 `attack_ranges.py` 的 `WEAPON_SELECTED` 共用，含 range6CellShoot。
- 满包换装可用取走新装备腾出的格；满包卸下不经背包、进 PlayLoop 手持 `held_item`（`0x437020` 不查背包，见 [original_item_actions.md](original_item_actions.md)「边界」）；武器只允许替换（原徒手范围未证明）；同 code：`0x436f30` 只有两处调用（状态窗 `0x429e24`、战斗持物窗 `0x43993e`），都只判 −1，不比较新旧 code，所以手持装上同一件时照写、手仍持该件、音 400，重制两处同（`EquipmentRules.replace` 的 `rewrite_same`、`BattleLoopInventory.hand_fits`）；`change()`／`change_equipment` 规则接口仍按无变化拒绝，原版没有对应的非手持入口。

## 复现

`python3 tools/hsl.py check inventory_equipment_evidence`；`python3 tools/hsl.py check equipment_data`；重制侧 `tests/run_inventory_equipment_tests.gd`（含十组原成长输出 equipped／unequipped 逐字段比较）。换装 Control 回执（`capture_equipment_review.gd` 主路线）截图驱动仍保留，回执为历史记录。

## 边界

- 原 UI 暂持中间态的关闭、取消归还与最终行动标志没有全部追完。
- range7CellShoot 只经射程扩展到达，未做单独原版执行对拍（沿用 `0x40f8b0` 通用洪泛读法）。
- high_cost 无规则读者是静态全文搜索的反证（negative-evidence）；按变量掩码的通用位循环读法没有排除；说明框 `0x432946` 是按字面位测的唯一读者。
- 其他角色空库存是重制配置，没有恢复全 roster 初始物品。
- 大地图整理裝備窗见 [original_storage_window.md](original_storage_window.md)。

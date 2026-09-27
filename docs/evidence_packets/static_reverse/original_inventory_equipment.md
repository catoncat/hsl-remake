# 原作八槽库存、装备交换与动态属性刷新

> evidence: static-derived · status: live · functions: 0x436e30, 0x436e80, 0x436ed0, 0x436ef0, 0x436f30, 0x437020, 0x4464f0, 0x448420, 0x448840 · tools: hsltools/data/equipment.py, hsltools/evidence/inventory_equipment.py, run_inventory_equipment_tests.gd · updated: 2026-09-13

Checked: 2026-09-13。机器摘要：[original_inventory_equipment.json](original_inventory_equipment.json)。当前玩家功能与接续优先级只维护在 [PROJECT](../../PROJECT.md)。

## 来源和证明范围

原文件为 `$HSL_ORIGINAL_DIR/hsl01.exe`，SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。字段名与类别来自 tracked `ITEM.TXT`、`TYPE.H`、`PLAYERS.TXT` 和 `RESOURCE.TXT`。原表字节身份写入 `content/generated/hsl/equipment/items.json`，由 `python3 tools/hsl.py check equipment_data` 重建核对。

本包新增结论属于 **static-derived**，表值属于 **resource-derived**。本轮新库存原函数探针的文件写入被工具阻断，文件未创建、未执行；没有新增原 EXE 函数正常返回的回执，也没有运行 Wine。Godot 回归覆盖实现合同，不升级为原版全部等价。既有成长包中十组输入的 equipped/unequipped 原函数输出仍可复用，本轮直接将新的动态装备刷新与这些输出逐字段比较。

## 库存实际是八个运行时槽

对象 `+0xa4` 给出 roster index；全局 `0x4c1bc8` 指向步长 `0x1fc` 的角色记录。库存为角色 `+0x138..+0x154` 的八个 DWORD，0 表示空槽。

| 原函数 | 实际行为与返回 |
| --- | --- |
| `0x436e30` | 扫描 0..7，向第一个空槽写入物品 code，返回 1；没有空槽返回 0，不改已有槽 |
| `0x436e80` | 删除指定槽，后续 `(7-index)` 项左移，最后一槽清 0；EAX 不作为成功标记 |
| `0x436ef0` | 同类删除操作，输入为直接角色记录指针 |
| `0x436ed0` | 返回最后一槽的 code；不是背包物品数量 |

相同 code 不堆叠，插入不排序。八格容量来自实际循环上界和字段访问，**不由 PLAYERS 的 item1..item8 数量推断**。原删除函数没有负索引保护；产品在执行前校验索引和预期 code，不复刻越界内存行为。原表初始 Leonard 库存为 `[241,241,241,246,0,0,0,0]`，其他角色当前空库存仍是既有重制配置，没有声称恢复了全 roster 初始物品。

## 六个装备槽及失败合同

ITEM 全局为 `0x4c1b40`，记录步长 `0xb0`；type 位于 `+0x8`，flags2 位于 `+0xa4`，职业 mask 位于 `+0xa8`。

| setter slot | 角色偏移 | 原 type | 产品槽 |
| --- | --- | --- | --- |
| 0 | `+0xec` | 2 Weapon | weapon |
| 1 | `+0xf0` | 3 Head | head |
| 2 | `+0xf4` | 4 Body | armor |
| 3 | `+0xf8` | 5 Foot | foot |
| 4 | `+0xfc` | 6 Other | accessory1 |
| 5 | `+0x100` | 6 Other | accessory2 |

`0x436f30(object,new_code,slot)` 依次检查职业、槽位类型和旧装备的不可卸 bit。失败返回 -1，不改槽；成功写新 code 并返回旧 code。`0x437020(object,slot)` 检查同一 bit，允许时清槽并返回旧 code，禁止时返回 0。两者失败值不同；调用者必须先验证所选对象、code 和槽位。

`0x4464f0` 将 job 80..100 映射为 bit 0..20，其他值返回 -1；setter 对 job 1000 单独跳过职业 gate，不据此给它杜撰角色业务名。ITEM loader 的 jobAll=1000 生成全 1 mask；jobAllNoPlayer8=1001 在全 1 上清 job96/97 对应 bit16/17，锚点 `0x44826a..0x448318`。原表 use_job=0 不产生有效职业 bit。

不可卸字段已经定位：`0x4481d7` 读取字符串地址 `0x47886c` 的 **take_off**，非零在 `0x4481ec..0x4481f2` 置 bit 1，`0x448207` 存到 ITEM+0xa4。因此 take_off 非零阻止卸下／替换，不能按英文字面解释为“允许卸下”。important 是另一字段，不能与它混用。

## 原 UI 的暂持物品与重制版的原子确认

`0x4292aa` 将选中库存 code 放到 `0x4c1ce4` 并调用删除 helper，证明该全局是暂持的物品 code。库存有空位时将暂持物放入首空槽；满包时，界面可以取出所指格的物品再插入暂持物，换成新的暂持物。

装备路径 `0x429e18` 读取暂持 code，`0x429e24` 调 setter；成功后 `0x429e3f` 将返回的旧装备放到暂持全局，`0x429e59` 调统一 refresh `0x448840`。无暂持物时走卸下 helper，返回旧物非零才在 `0x429ea1` refresh。原界面允许中间暂持状态，关闭、取消、归还和最终行动标志仍需继续追调用者，不能只从 setter 推导。指令检查时已纠正早期摘要把 load 地址 `0x429e18` 误标成 call 的问题。

当前产品采用明确确认事务：校验 → 从所选库存槽取新物 → 换槽 → 旧物放回首空位 → 从基础属性和当前装备统一刷新 → 一次提交。原库存结构和 helper 规则已接入；确认 UI、失败回滚、同 code 无变化拒绝属于重制交互策略。满包换装可使用取走新装备后腾出的格；满包单独卸防具拒绝。原徒手攻击范围未证明，武器目前只允许替换。

**后续更正：** 本包首版沿用了交接中按菜单 `rtus` 顺序推算状态的错误。原 `obj-051.obs` 的 obj_Data8 加上 `0x43e887/0x43e891` 点击处理，证明 Use/Give/Equip/Drop 是 state5/6/7/8。Equip 实际为 `0x444185` 的 state7、mode4；`0x4441ac` 的 state8、mode5 是 Drop。两者进入 state76，返回 state77 后由 `0x444c19` 回到 state3。此更正不改变已独立证明的库存／装备 setter／refresh；完整 UI 子流程和行动 bits 仍继续跟进。[物品行动后续证据](original_item_actions.md)保存直接原包／EXE 检查与取消归还路径。

后续 [物品行动证据](original_item_actions.md) 已把 mode4/5 的根窗口 `0x438160`、暂持归还／满包拒绝关闭、父 state76→77→3 连起来，正常装备／丢弃返回物品菜单而不结束行动。产品换装和丢弃均免费；use/give 仍按现有一次成功后交接行动。确认式操作、确认前不取物及保持 pending move 可撤销仍是当前交互策略；连续给予、同 code 交换和完整移动标志未由本包概括为完成。

## 当前装备重新参与统一刷新

`0x44b5de..0x44b627` 依次读取六槽调用 `0x448420`。基础职业计算先发生，随后才应用当前装备；原始固定装备 delta 已从 live growth profile 删除，旧 `CoreCombatRules.apply_weapon_item` 也已移除。

`0x448420` 对 weapon 将 attack_damage 和 hit_ratio 加到攻击／命中；对 head/body 将 attack_damage 加到防御；对 foot 加到速度。通用字段包括 add_weapon_hit、**add_attack_power**、**add_magic_power**、add_hp/mp、add_speed/defense、add_miss_hit、add_attack_back 和抗性。注意旧窄探针的 add_attack/add_magic_attack 别名不等于原表字段；3号银剑的 add_magic_power=5 是本轮源数据回归之一。

抗性分组来自该函数分支：0..4 对应土水风火心；7 全五类；8 前四类；9水火、10土火、11风火、12火心、13土水、14水风、15水心、16土风、17土心、18风心。刷新尾部 `0x44b6ca..0x44b75a` 将每项限制到 0..80；`0x44b77e..0x44b7b8` 将攻击、魔击、防御和速度下限限制到 0。HP/MP 当前值仅向下夹紧，不因最大值增加治疗。

生成器保留全部物品定义，但存在未接入的非零字段就明确禁止装备：状态被动、add_move、暴击结算、特殊武器范围／魔法伤害窗口等。TYPE.H 的 magic4TYPE 与部分 ITEM 的 magic4Type 大小写不一致，原解析器是否忽略大小写尚未证明，对应抗性效果也标为 unsupported，不擅自纠正。

纯 `EquipmentRules` 接收当前装备和只读 catalog；纯 `ProgressionRules` 接收明确传入的 catalog。PlayLoop 是唯一提交者；面板只有预览和所选槽／code。目录数据由 `EquipmentCatalog` 读取缓存并向调用者返回副本，没有运行时 EXE 仿真。

换装、加点和升级在改变任何字段之前，先检查属性源、四基础属性、生命／魔力及当前装备效果的完整性；缺项整笔拒绝。Leonard 初始 MP/maxMP=0 已从原模板明确写入场景，不依赖显示或刷新函数的默认值。异常场景以具体 `scenario_error` 失败，避免新装备已提交但派生数值仍旧的状态。

## 重跑与验收

```sh
R2_NOPLUGINS=1 r2 -N -q -e bin.relocs.apply=true -e scr.color=0 \
  -c 'pD 277 @ 0x436e30' -c 'pD 372 @ 0x436f30' \
  -c 'pD 304 @ 0x429e00' $HSL_ORIGINAL_DIR/hsl01.exe
python3 tools/hsl.py check equipment_data
PYTHONPATH=tools python3 -m hsltools.evidence.inventory_equipment --exe $HSL_ORIGINAL_DIR/hsl01.exe
python3 -m unittest tools.test_hsl_equipment_data tools.test_hsl_attack_ranges
godot --headless --path . --script res://tests/run_inventory_equipment_tests.gd
tools/verify.sh
```

定向测试包括首空插入、重复 code、有序删除、JSON 数字规范化、满包交换／卸下拒绝、职业／槽位／旧装备锁、重复输入、死亡／敌军／终局拒绝、换回不累加、装备后升级、下一轮速度更新、给予满包原子性、真实面板回调。旧道具回归曾暴露 JSON float 与整数 Array.find 不相等，已在加载时规范为整数并覆盖离线 decoded-array 样例；未隐藏该失败。

`hsltools/evidence/inventory_equipment.py` 对 31 段经人工反汇编复核的指令／数据锚点逐字节比较，包括八槽循环、失败返回、左移清尾、锁定 bit、take_off loader、暂持取出／插入与装备调用顺序。带 `--exe` 先校验完整 EXE 哈希再读 PE sections；无该参数只核对 curated packet。它不启动、模拟或执行原程序，不把静态字节一致性说成原函数运行结果。静态 checker 和篡改／截断／布局矛盾回归进入完整门禁。

画面与真实 Control 输入见 [equipment/README.md](../runtime_observations/equipment/README.md)。额外银剑只来自验收夹具，不修改正常开场库存。正常第一战可通过卸下／重新装备原有防具使用同一事务。完整门禁最终结果记录在对应提交说明；未证明边界以本包机器摘要和 PROJECT 为准。

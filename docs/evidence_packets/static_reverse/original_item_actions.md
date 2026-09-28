# 物品命令：入口状态、取消归还、重要物品保护与用药目标

> evidence: static-derived · status: live · functions: 0x4097d0, 0x409830, 0x409e40, 0x40e690, 0x40f440, 0x40f560, 0x411c40, 0x436e30, 0x436ed0, 0x438c84, 0x439a0f, 0x43ac10, 0x43b4e0, 0x443330, 0x4466d0, 0x446b00 · tools: hsltools/evidence/item_action.py, run_inventory_equipment_tests.gd · updated: 2026-09-28

## 结论

- 原版：Use／Give／Equip／Drop 是玩家 state5／6／7／8（原 `obj-051.obs` 的 obj_Data8，不按菜单字符串 `rtus` 顺序）；Equip／Drop 走 Object130 根窗口，关窗后父 state76→77→3 回物品子菜单，不结束行动；Use 完成走 state4 公共结束；ITEM `important`（+0xa0 bit27）禁丢，与禁卸的 `take_off`（+0xa4 bit1）无关（static-derived）。
- 原版用药：模式4 从使用者格泛洪一格（大体型两格），可对自己用，敌方／NPC 格被挡；无 HP／MP／状态资格检查，满值照用并消耗一件，回复量夹到 0 浮出 0；AI 用药只看阈值与状态 mask（static-derived）。
- 原版裝備／丟棄窗：mode4／5 同一持物窗（`0x43b7fd`），空手点背包格拿起、持物点格放回首空格；持物点装备板槽装上、旧装备进手，空手点槽卸下进手；mode5 多一个 丟棄 钮（中心 (285,387)），只清非重要持物；右键先放回持物、空手才关窗回道具子环；持物且指针在装备板上时左栏改显屬性页，离板回道具页（`0x439a0f`）；无确认页、无饰品选位置页（static-derived）。
- 重制：`InventoryRules.discard_error/discard`、`ItemUseRules`、`ItemResolutionRules`、`game/sim/loop/BattleLoopInventory.gd`；丢弃与换装免费并保留当前行动；`BattleItemPanel` 裝備／丟棄 走同一持物窗，持物记所持背包格，行里即按删格收拢显示，装上／卸下／丢弃／放回各提交一次 PlayLoop 命令（static-derived）。
- 差异：用药取消（`0x444a5c` 首空归还）重制仍回原格；重要物品不附加给予限制；差异清单 `item-use-rules`（static-derived）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；PAK 成员 `@:\data\obj-051.obs` SHA-256 `f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8`；36 段锚点见 [original_item_actions.json](original_item_actions.json)）

| 操作 | 对象 code | Data8／玩家 state | 分派入口 | 物品 UI mode／等待 |
| --- | --- | --- | --- | --- |
| 使用 | 114 | 5 | `0x444a8b` | state102→`0x4448ba` 构造 mode6 |
| 给予 | 115 | 6 | `0x444d6a` | state110→`0x444b8a` 构造 mode7 |
| 装备 | 116 | 7 | `0x444185` | mode4，等待 state76 |
| 丢弃 | 117 | 8 | `0x4441ac` | mode5，等待 state76 |

`0x43e887` 读命令对象 +0xa8 的 Data8，`0x43e891` 写父对象 +0x8c；分派经 `0x445758` byte 表与 `0x445694` 目标表。state9／10 中 `0x4097d0`／`0x409830` 是技能选择分支，不是物品规则。

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| important loader | `0x447da1`（字符串 `0x478a54`）→ `0x447dba` → `0x4481b1` | 非零置 `0x08000000`，存 ITEM +0xa0；源表非零为 code281..285（通行證、殘忍的情書、劍之魂、福音之書、聖水晶） |
| important predicate | `0x40e690` | code×176 查 ITEM +0xa0 bit27 |
| 丢弃分支 | `0x43aacb..0x43aae6`、`0x42a7e2..0x42a805` | 重要物品不清暂持位，普通物品清 `0x4c1ce4` |
| 用药取消 | `0x444a5c..0x444a94` | 暂持物首空插入 `0x436e30` 归还，回 state102 |
| 给予取消 | `0x444d3b..0x444d73` | 同样归还，回 state110 |
| Object130 构造 | `0x43b4e0` mode4／5 → `0x43b7fd` → `0x43ac10`；`0x43ac51` 存调用者到根 +0x9c | 根标 `0x40004000`；mode5 另建丢弃按钮；过程 `defProcStatusWindow` = `0x438160`，Data9=0 分派 `0x439ed8`→`0x4385d3` |
| 根状态表 `0x439ef8` | 0 打开、1 输入、2 关闭动画、3 通知父对象 | — |
| 取消，手上无暂持 | `0x438811` → `0x4388be` | 1→2 关闭动画 |
| 取消，可放回 | `0x438868` 插入成功 → `0x438882` 清暂持 → `0x4388bd` | 归还，窗口保留；再取消才关 |
| 取消，背包满 | `0x438868` 失败 → `0x438872` | 暂持与窗口都保留 |
| 关窗完成 | `0x43896b` → 根 3 → `0x4389ce` | 读 +0x9c，父 state76→77；`0x444c19` 设回 3，`0x44416c` 重开物品子菜单 |
| 使用完成 | state118 → `0x444e3b` | 关 UI，玩家 state4 → 公共结束 `0x4454a5` |

裝備／丟棄持物窗（mode4／5）：

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| 分派 | `0x43b541` 跳表 `0x43bef4`：mode4、mode5 → `0x43b7fd` | 根 `+0x94`＝1、`+0x80 |= 0x40004000`；子窗 `0x43ac90`／`0x43ace0`／`0x43ad30`／`0x43ad80`，`0x43add0`／`0x43ae70` 两子窗另置 0x4000 |
| 丟棄钮 | `0x43b8fe` 仅 mode5 → `0x43b280(0,0)` | 模板 148 BCMD08_1（42×42，原点 (21,21)）落点 x `0x11d`、y `0x183`＝中心 (285,387)，自 y `0x2ff` 滑入 |
| 背包格，空手 | `0x438d63..0x438de7` | 格中物写 `0x4c1ce4`、`0x436e80` 删格压紧、音 399；窗不关（`0x1000` 给予接收与 `0x2000` 用药两种旗标才另走关窗／类型检查） |
| 背包格，持物 | `0x438c84..0x438d5e` | 背包末格 `0x436ed0` 有物（满）时格中物与持物互换，否则持物进首空格 `0x436e30`；音 400 |
| 装备板槽，持物 | `0x43993e..0x439995` | `0x436f30(成员, 槽, 持物)`；-1 手不变、无音；否则旧装备写 `0x4c1ce4`、`0x448840` 刷新、音 400 |
| 装备板槽，空手 | `0x439997..0x4399e1` | `0x437020` 卸下，返回值写 `0x4c1ce4`；非零则刷新、音 399 |
| 丟棄钮按下 | `0x43aacb..0x43aae6` | 持物非零且 `0x40e690` 非重要才清 `0x4c1ce4` |

用药目标（state102 确认后 `0x4448f4`）：

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| 范围 | `0x40f440(user, 2 或 1, 4)`，按使用者 +0x2c 大体型；`0x444be4` 开选格 | 模式4 经 `0x40ed50` 泛洪，中心格保留；不进 `0x24000`（pmEnemy／pmNPC）格，no_block 例外；物品无射程字段参与 |
| 给予范围 | `0x444bc7`：`0x40f440(user,1,4)` 后 `0x40f520(0)` 清中心 | 不能给自己 |
| 选取 | `0x44492a..0x4449b6` | 格须标记（`0x40f560`）且格字 `0x411c40` 含 `0x10000`（EBX 在 `0x443955` 设定）；`0x407800` 取对象写 `0x4c1cec`；`0x446b00` 排除 no_attack（PLAYER+0xa0 bit2）；给予从 `0x444c27` 同样检查但不调 `0x446b00` |
| 生效与消耗 | `0x444ab2` 调 `0x409e40(target, code, user, 0)`；`0x444aba` 无条件清暂持 | 一次一件、一个目标；`0x409e40` 先把 `0x4c1a44`／`0x4c1a48` 置 -1，HP（`0x40a1b9..0x40a218`）／MP 按上限夹紧写实际增量 |
| 数字 | state108 `0x444ac9` | 不为 -1 的各浮一个数，满血喝药浮 0 |

AI 用药：

| 原入口 | 条件 | 目标与位置 |
| --- | --- | --- |
| `0x43fa29..0x43fac1` 自救 | `0x40c110` 自身阈值；`0x40c570` 选起始类别循环三类，普通类 `0x40c1d0` 取首件回血药（type1、add_hp≠0） | 跳 `0x4406d7` 写 state `0xc0000`，原地对自己 |
| `0x44075b..0x44080c` 友军回复 | `0x40c2f0(actor, 8, 1)` 找同侧非自身过阈值友军；同上取药 | `0x40d530(actor, ally, 1)` 走到距离 1，写 `0x4c2c70`／`0x4c2c74`，state `0xe0000` |
| `0x44086e..0x4408dd` 对症药 | 桶 7；`0x40c1b0` 取状态 mask，`0x40c230` 找首件对症药 | 自己原地，否则 `0x40d530` 距离 1；state `0x100000`；找不到转 `0x4408e2` 的 `0x40c3a0(actor, 8, 1)` |
| `0x4406af` | `0x44060e` 在 `0x40df70` 返回 0 后进入；`0x4c2c50==1` 时查 `0x40c1d0` | 自己原地，否则距离 1 |

`0x40c110` 要求缺血至少 10，AI 不对满血目标用回血药。`0x40d530` 落点见 [original_ai_support.md](original_ai_support.md#证据)。

## 重制接线

- `game/sim/InventoryRules.gd`：`discard_error`／`discard` 读 catalog important 布尔，缺记录或字段拒绝；provenance 头 `rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md`。
- `game/sim/loop/BattleLoopInventory.gd` 的 `discard_item`：只提交库存，保留行动与可撤销移动；面板对重要物品置灰并说明，旧回调被版本检查拒绝。
- `game/sim/ItemUseRules.gd`、`game/sim/ItemResolutionRules.gd`：用药目标与夹紧；`game/battle/scene/BattleItemText.gd` 浮 0。
- `game/battle/scene/BattleItemPanel.gd` `_show_hand_window`：裝備（state7）与丟棄（state8）同一窗，左 WINDOW20 背包、右 `BattleEquipmentView`（`accepts_empty_slots`），丟棄 时 (285,387) 加 BCMD08_1 钮；`held_index`／`held_code` 为持物草稿（行里不画被拿起的格），拿起只改所持格并发 take_up 音；放下（点背包任一行或右键）发 `hand_return_requested`，`BattleSceneMenus.return_held_item` 提交 `BattlePlayLoop.return_held_item`（`InventoryRules.put_back`：删格收拢后首空格，即末尾；不耗行动），put_down 音。
- 装上：持物点槽发 `equipment_requested(槽, held_index, held_code)`，`BattleSceneMenus.change_equipment` 提交 `BattlePlayLoop.change_equipment`，窗不关，`hand_equipment_changed` 把换下的装备（规则放进的首空格）拿到手上；被拒则手不变、无音。卸下：空手点有物槽发 `(槽, -1, 0)`，卸下物同样进手。
- 左栏：`_update_attribute_page` 每帧按 `0x439a0f` 规则切 AttributePage（WINDOW21＋九项现值，取法同状态页）——指针离板回道具页，持物在板上换屬性页，空手在板上不变；新开窗先是屬性页（`0x43ac10` 建根 +0x94 = 4）。
- 丢弃：丟棄 钮对非重要持物发 `drop_requested`，`BattleSceneMenus.discard_inventory_item` 提交 `discard_item` 后窗不关、手清空；重要物不发、留在手上。右键：持物放回（同上，落末尾）；空手回道具子环。
- 用药选目标照原版地图选格（范围、合法格、悬停与取消见 [用药演出](original_item_use_presentation.md#证据)）。

## 复现

`python3 tools/hsl.py check item_action_evidence`；重制侧 `tests/run_inventory_equipment_tests.gd`、`tests/run_presentation_contract_tests.gd`（拿起→丟棄）；持物窗截图驱动 `tools/godot.sh --script tests/capture_equipment_review.gd`（默认换装路线，`-- important`／`-- discard` 为丢弃路线）。

## 边界

- 大体型使用者的 range2 泛洪（体型 `0x40ecc0`／邻接 `0x40eb80`）只读到入口参数，逐格结果未读。
- `0x4406af` 的触发上下文、`0x40c570` 无法术时是否抽随机数未读。
- 剧情 `actUseItem` 只调 `0x409e40`，是否删除库存未读。
- 连续给予与交换见 [original_give_exchange.md](original_give_exchange.md)；库存结构与换装见 [original_inventory_equipment.md](original_inventory_equipment.md)。
- 整理、全部脚本组合与移动标志不由本包概括。
- 持物放回：原版拿起即删格收拢（`0x436e80`），持物点背包任一行或右键放首空格——即收拢后的末尾，重制同（规则层删格与放回一次提交，窗内无别的出口）。满包互换（`0x438c84`：`0x436ed0` 末格有物时点中格物进手、删格收拢、持物放第 8 格）只在持物来自装备板且背包满时发生；这种情形重制按规则拒绝卸下，互换顺序随之不出现。换装被拒时原版不出音与字，重制同。
- 0x40000 与背包格、待领列表判点击的是同一位（`0x438c78`／`0x43990c` 都测 `[esp+0x74] & 0x40000`），写入它的输入分派未追；屬性页切换读的是同一过程的 `0x2000000`（指针在装备板内，`0x439245`）。窗内 钱框、「返回」钮与「道具 n／8」是重制沿用的共用排布。

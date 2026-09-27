# 给予与交换：连续给予会话、满包交换与行动消耗

> evidence: static-derived · status: live · functions: 0x407800, 0x40f560, 0x411c40, 0x436e30, 0x436e80, 0x436ed0, 0x43b4e0 · tools: capture_give_review.gd, hsltools/evidence/give.py, run_inventory_equipment_tests.gd · updated: 2026-09-28

## 结论

- 原版：Give 是循环会话——每次选源物、选相邻友军、选接收槽；目标格非空就取出该物交换，再把输入物插入目标首空格，所以双方都满也能交换；返回 code 与给出 code 不同即 OR 置使用标记 `0x10000`，结束会话时有标记才走公共结束，否则回物品子菜单（static-derived）。
- 同 code 交换不置标记，但可能改变双方槽序；取消目标选择把暂持物首空归还给出方，不置标记（static-derived）。
- 重制：`InventoryRules.exchange` 计算、`game/sim/loop/BattleLoopInventory.gd` 的 `begin_give`／`confirm_give`／`finish_give` 持会话并原子提交，`ActionBudgetRules` 按会话标记结算一次行动（static-derived；确认式预览为 provisional）。
- 界面：重制逐状态照原版——给出方持物窗点物入手（持物图标随指针、权杖不画）→ 地图标相邻格（移动色，不含本人格）＋格光标＋悬停身份栏 → 点友军以目标开同一持物窗 → 点物品行交换／点空行首空放入，一次点选即提交 → 回给出方持物窗；选格时右键放回手持回持物窗，给出方持物窗右键结束会话（static-derived；目标持物窗右键为 provisional）。
- 差异：原版取消后首空归还可能改槽序，重制确认前不取物、取消保持原顺序；自动找空位时满包明确失败，不自动挑物交换（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；`@:\data\obj-051.obs` SHA-256 `f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8`，obj_Data8 把 Give 对象 115 接到玩家 state6；15 段指令与 8 个状态分派见 [original_give_exchange.json](original_give_exchange.json)，其中 6 组输入输出为独立 Python 模型的合成例子，`native_execution=false`）

库存布局（八槽、首空插入 `0x436e30`、删除左移 `0x436e80`、末格读取 `0x436ed0`）见 [original_inventory_equipment.md](original_inventory_equipment.md)。

| 阶段 | 入口／字段 | 行为 |
| --- | --- | --- |
| 打开给出方背包 | state110 `0x444b8a` → `0x43b4e0(mode7)` | mode7 根设 `0x40005000`（`0x43ba0b`）；库存子对象设 `0x5000`（`0x43ba97`） |
| 选取给出物品 | `0x438c53`、`0x438d63`、`0x438d8d` | 索引 0..7；空格无操作；code 存暂持全局 `0x4c1ce4`，源槽删除／压紧，关选择窗 |
| 选目标 | state113 `0x444c27`，`0x444c4e..0x444c99` | `0x40f560` 可达、格字 `0x411c40` 含 `0x10000`、`0x407800` 返回非空对象；目标格由 `0x444bc7` 的 `0x40f440(user,1,4)` 标相邻一格并清本人格，不查 no_attack |
| 打开目标背包 | state114 `0x444d9c` | 给出 code 存 `0x4c2c88`；以 `0x4c1cec` 的目标打开同一 mode7，父对象仍为给出方 |
| 选择接收槽 | `0x438c92` → `0x438cbf..0x438d0c` | `0x1000` 位跳过尾格判断；目标格非空先取出作新暂持物并压紧，再首空插入输入物；选空格也插入第一个空槽 |
| 关闭目标背包 | `0x438d0c..0x438d29` | 一次选择完成即请求根窗口关闭，通知父对象 |
| 归还并继续 | state116 `0x444def..0x444e36` | 返回暂持 code ≠ `0x4c2c88` 时 `0x10000` OR 进给出方 object+0x80；非零返回物首空插入归还给出方，回 state110 |
| 结束会话 | `0x444bff..0x444c22` | 有 `0x10000` 清位进 `0x4454a5`，否则回 state3；EBX=`0x10000` 来自 `0x443955` |
| 取消目标选择 | `0x444d3b..0x444d73` | 暂持物首空归还，回 state110，不置位；mode7 的 `0x1000` 绕过 `0x438835` 的「先放回本窗口背包」 |

行动矩阵：

| 操作／结果 | 原版 | 重制 |
| --- | --- | --- |
| Give 到空格 | 返回 0 ≠ 给出物，置位回 110 | 当次提交库存，可继续；结束会话消费一次行动 |
| 交换不同 code | 同一置位分支 | 满包或有空位都可交换，双方守恒 |
| 仅交换同 code | 比较相等不置位 | 顺序可变；无其他交易时退出后仍能行动 |
| 满包未选交换／错误或失效选择 | helper 无空位插入失败 | 整笔拒绝，不改库存、标记、队列 |
| 取消未确认选择／退出空会话 | 回 110 不置位；无标记回 3 | 不改状态、不耗行动 |
| 成功后取消下一次预览 | OR 标记不被清除 | 已确认交易保留，退出仍结束行动 |

例：双方均为 `[241,246,0,0,0,0,0,0]`，互换各自第 0 格，结果均为 `[246,241,0,0,0,0,0,0]`。

**runtime-measured**（重制侧 Control 回执，已随回执目录删除）：合成库存连续给出两件 241 后给出方 `[246,281,0,0,0,0,0,0]`、接收方 `[246,241,241,0,0,0,0,0]`；双方 8/8 满包以 241 换 246 守恒；移动后 Give 预览取消、结束空会话、右键撤销移动回原点且库存原序。

## 重制接线

- `game/sim/InventoryRules.gd` `exchange`：按双方真实八格计算；`target_index=-1, expected_return=0` 满包失败。
- `game/sim/loop/BattleLoopInventory.gd` `begin_give`／`confirm_give`／`finish_give`：唯一持会话者；每次开始、确认、结束递增 `item_revision`，旧请求与旧按钮被拒；provenance 头 `rules: static-derived docs/evidence_packets/static_reverse/original_give_exchange.md`。
- `game/sim/ActionBudgetRules.gd`：Give 的 sticky 比较、Use 结束、免费 Drop／Equip。
- 给予期间暂停其他命令与移动撤销，未成交结束保留 pending move（provisional）。

界面状态对应（`game/battle/scene/`）：

| 原版 state | 重制 |
| --- | --- |
| 110 `0x444b8a` 给出方持物窗 | `BattleItemPanel.show_give_session` → `_show_list("give")`（page `inventory`，与用药同一持物窗）；每次提交后回到这里 |
| 选物 `0x438c53..0x438d8d` 入暂持、关窗 | `_select_item` → `_show_targets`：页滑出，`_hold_selected_item` 的 HeldItem 随指针（GameCursor 藏权杖） |
| 112 `0x444bc7` `0x40f440(user,1,4)` 标格、清本人格 | `BattleSceneMenus._begin_item_pick`：`BattleItemUsePresentation.use_cells` 去掉本人格，`BattleSceneOverlays.show_item_range` 移动色 |
| 113 `0x444c27` 选格 | `_item_pick_pointer`／`_item_pick_hover`：格光标＋悬停身份栏与用药同；左键须标记格上的 `give_target_ids` 单位 → `BattleItemPanel.select_give_target` |
| 取消选格 `0x444d3b..0x444d73` | `cancel`（page `give_target`）：回给出方持物窗并滑入，库存不变 |
| 114 `0x444d9c` 目标持物窗 | `_show_give_inventories` → `_show_list("give", 目标)`（page `give_inventory`），HeldItem 仍随指针；首个空槽画成空行 |
| 选槽 `0x438c92..0x438d29` | `_place_give_item`：物品行＝`(index, code)` 交换、空行＝`(-1, 0)` 首空放入，`InventoryRules.exchange` 预检后发 `give_requested`；`BattleSceneMenus._confirm_give` 提交 `confirm_give` |
| 116 `0x444def` 归还、回 110 | `_confirm_give` → `show_give_session`（换回物已由 `exchange` 首空插回给出方） |
| 结束 `0x444bff..0x444c22` | 给出方持物窗右键／「返回」→ `give_finished` → `_finish_give_session` → `finish_give` |

## 复现

`python3 tools/hsl.py check give_evidence`；重制侧 `tests/run_inventory_equipment_tests.gd`（逐 code 守恒、顺序、满包、同 code、连续给予、拒绝、移动）。截图驱动 `tests/capture_give_review.gd`（需渲染窗口；`tools/oss_screenshots.py` 使用）：默认路线走持物窗→选格→目标持物窗，出 `give-held`（选格＋持物）、`give-recipient-window`、`give-two-items` 等帧。

## 边界

- 死亡／隐藏对象的格字映射未读。
- 原版完整移动 flag 与 rollback、攻击后再操作、全部脚本组合见 [original_action_state_machine.md](original_action_state_machine.md)，不由本包概括。
- 自动整理、跨关存档不在本包。
- 物品命令入口与用药见 [original_item_actions.md](original_item_actions.md)。
- 目标持物窗里右键：读法是 mode7 的 `0x1000` 绕过「先放回本窗口背包」、暂持仍为给出物，116 比较相等不置位并归还给出方；重制回给出方持物窗、库存不变（provisional）。
- 标格滤掉敌对占位格沿用用药选格的 `use_cells`（provisional，见 [original_item_use_presentation.md](original_item_use_presentation.md)）；持物窗外观（无钱框、行样式）沿用重制用药持物窗。

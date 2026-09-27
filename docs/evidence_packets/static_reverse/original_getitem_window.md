# 獲得物品窗：战利品拾取的绘制、输入与三个按钮

> evidence: static-derived; resource-derived: 窗体资源、文字表与音效表; runtime-measured: 录像 16 段四帧对照 · status: live · functions: 0x414c00, 0x42aad0, 0x430710, 0x436d70, 0x436e30, 0x438160, 0x43a640, 0x43b4e0, 0x442720, 0x44f2d0, 0x44f430, 0x44f4d0 · tools: run_battle_reward_tests.gd, run_presentation_contract_tests.gd · updated: 2026-09-27

## 结论

- 原版：击杀后金钱浮字之后、升級判定之前，玩家击杀者且待领池非空时打开状态窗 mode 0xb；接收者固定为击杀者；左栏背包 8 格、右栏 WINDOW90 待领 5 行、下方 丟棄／倉庫／離開；手持一次一件，重要物品不能从池拾起；离开时剩余全部进队伍仓库，不丢物（static-derived；录像 16 段四帧 runtime-measured）。
- 重制：`game/battle/scene/BattleLootPanel.gd` 与 `BattleSettlementController.gd` 同坐标、同资源绘制，拾取经 `claim_reward`，离开经 `finish_rewards`（static-derived）。
- 差异：重要物品可拾入包；丟棄为两次点击放弃全部剩余；倉庫即放回待领池；交换时换出物直接回池；空手点背包格无动作；字体为系统字（provisional）。

## 证据

**static-derived**（EXE／PAK 来源与读法同 [original_growth_window.md](original_growth_window.md)；未执行）

入口 `0x442720` case 4（`0x4428b8`–`0x44290e`）：待领池非空（`0x44f4d0() != 0`，池 = `*0x4c1d28` 的 (code, qty) 对，计数 `*0x4c1d2c`）时——击杀者为玩家对象（kind 3）则 `*0x4c2ae4 = 击杀者槽`、`0x436490(actor,0,0)` 生成文字、`0x43b4e0(actor,0xb,…)` 开窗；否则 `0x44f600(actor)` 把池中物逐件塞入击杀者背包（`0x436e30`），塞不下的留池，`0x44f4e0()` 释放池（NPC 击杀不开窗）。宝箱由 `0x4156d0` 加入同一池后走同一窗（[original_treasure.md](original_treasure.md)）；掉落资格见 [battle_reward_inputs.md](battle_reward_inputs.md)。

对象（`0x43b4e0` case 0xb，`0x43bd94`–`0x43bed2`）：`*0x4c1cbc |= 1`（getitem 模式位，商店为 bit 2）；root flag `0x40004400`（含 `0x400`，右键／Esc 关闭被挡）。

| obj | SHP | 停靠 (x,y) | 创建 | 用途 |
| --- | --- | --- | --- | --- |
| 130／131／145／146／147 | 头像／WINDOW10／三条 | 同状态页 (12,14)…(154,116) | `0x43ac10`… | 接收者抬头；root +0x94 = 1 |
| 132 | WINDOW20 | (12,168) | `0x43ae20` | 背包 8 格；`0x438160` case 2 mode 1：行距 32，文字 x 偏移 0x30，图标 x 偏移 0x20 |
| 134 | WINDOW40 `$:`（208×32），Data9=4 | (20,442) | `0x43afb0` | 金钱：6 空格 + `0x45b6de(*0x4c1bcc,…,9,' ')` 九位右对齐于 (x+8,y+8)，右缘 x=208 |
| 136 | Status_Window_6 WINDOW90（375×220）`defProcGetItemWindow`，+0xa0 = 313 | (252,168) | `0x43b050` | 待领列表 |
| 148 | Button_Drop `BCMD08_1`（42×42，原点 (21,21)）Data6=6 Data9=26 | 中心 (285,429) | `0x43b280(0,0x2a)` | 丟棄 |
| 750 | Button_Storage `BCMD15_1` Data6=7 Data9=309 | 中心 (346,429) | `0x43b2e0(0x3d,0x2a)` | 倉庫 |
| 751 | Button_Storage_Exit `BCMD14_1` Data6=8 Data9=312 | 中心 (468,429) | `0x43b340(0xb7,0x2a)` | 離開 |

无 Prev／Next、成员选择与存档按钮。

待领列表 `0x414c00`（与商店窗同函数）：顶缘 +0x9a = 43，行距 +0x98 = 32，滚动起点 `*0x4c1a5c = 0`，滚动条 `0x446060` 范围 = 池计数。坐标以 (252,168) 为 (x,y)：

| 元素 | 位置 | 内容 |
| --- | --- | --- |
| 标题 | `0x4128f0(x+32, y+10, "@6"+资源313, …, 26)`，26 半角居中，「獲得物品」起于 x=392 | 米白 `@6` |
| 行 i（0..4） | 图标 `0x4607f9(x+32, y+43+8+6+32i, ICON[type])`，中心 (284, 225+32i)；文字 `0x4123b0(x+56, y+43+8+32i)` → (308, 219+32i) | 颜色码 + 名字（补／截 14 半角）+ 两空格 + 七位右对齐数量（右缘 x=584）+ `#` |
| 行颜色 | ITEM +0xa0 & 0x8000000 → `@6`；+0xa8 & (1<<job) → `@1` 白；否则 `@2` 红 | job 位 = `0x4464f0(job)` |
| 悬停 | `(mouse_y − y − 51) / 32`，0..4 | `0x430710(code)` 生成描述，`0x436d70()` 画框，`0x4132f0` 把行名改画 `@3` 绿 |

左栏背包悬停 `(mouse_y − y − 8)/32` 0..7；图标中心 (44, 184+32i)，文字 (68, 176+32i)。描述框 `0x436d70`：WINDOW50（`*0x4c2c98`，376×88）在 getitem 模式画在 (252,390)（状态页 (252,349)），`0x412060(x+8, y+12, buf, …, 0x2d, 0x10)` 15 号小字、45 半角居中、行高 16；内容 `@3`名字、`@1#`、消耗品「可使用」(79) 与生命／魔法／氣力／永久行及解毒／解痲痺／解封印（114／113／115／168）、装备数值行与职业括号。框覆盖 y 390–478，悬停物品时三个按钮不可见也不可点。

拾取／放置（手持槽 `*0x4c1ce4`；点击 `in_stack & 0x40000`）：

| 状态 | 点待领列表 | 点背包格 | 右键／Esc |
| --- | --- | --- | --- |
| 空手 | 有物且 `0x40e690(code)==0` → 拿起，`0x44f430(idx,1)` 池中 −1，音 399 TAKEUP01；重要物品不能拾 | 有物 → 拾起（`0x436e80`），音 399 | 关闭，被 `0x400` 挡住 |
| 手持 | `0x44f2d0(held,1)` 放回池，音 400 PUT00003 | 空格放入（`0x436e30`）；有物则交换，格物进手，音 400 | `0x436e30(actor, held)` 放入首空格，音 400 |

三个按钮 `0x43a640`（defProcStatusButton）：标签 15 号小字画在 `(中心x − 21 + (42 − len·8)/2, 中心y + 13)`，白 `0xffff`／悬停黄 `0xffef`，阴影 0x8430，点击音 398 ACCEPT01。

| 按钮 | 行为 |
| --- | --- |
| 丟棄（Data6=6） | 手持且非重要 → `*0x4c1ce4 = 0`，只丢手上一件；空手无效 |
| 倉庫（Data6=7） | 手持 → 重要走 `0x44ef70`、普通走 `0x44f100` 加入队伍仓库表（`0x4c1d10`／`0x4c1d1c`）；空手无效 |
| 離開（Data6=8） | 空手才有效 → root +0x96 = -1；`0x414c00` case 1 非商店模式调 `0x42aad0()` 把池中剩余按重要／普通加入仓库表，再 `0x44f4e0()` 释放池 |

**runtime-measured**（[16 段录像](../runtime_observations/original_gameplay_reference/16_loot_spoils_screen/)，638×480，简体字版本）

| 帧 | 可见 | 对照 |
| --- | --- | --- |
| `frame_003` 取物前 | 抬头 雷歐納德 Lv1 69/100；左栏 回復藥×2；右栏标题居中 y≈180–200，一行 破魔咒（绿，悬停）数字 `1` x≈575；描述框 (255–625, 390–478) 三行；`$: 1410` | 标题、行 y=219、数字右缘 584、描述框、金钱右缘 208 在 ±3px 内相容 |
| `frame_006` 持物 | 右栏空；游标画 破魔咒 图标；三按钮中心 x≈285／346／468 | 描述框消失后按钮可见 |
| `frame_008` 入包后 | 左栏第三格 破魔咒 | 手持→空格 |
| `frame_019` 再次持物 | 左栏第三格空、游标持物 | 空手点背包格可拾起 |

## 重制接线

| 原 | 重制（`game/battle/scene/BattleLootPanel.gd`、`BattleSettlementController.gd`） |
| --- | --- |
| 接收者 = 击杀者／开箱者 | 按 `kills[0].attacker_id`／`owner_id`；从状态页重开时 = 所看成员；无成员下拉 |
| 坐标、资源、字号级 | 同坐标同资源；字号 24／15 → 系统字 22／14（无 FONT.24 位图导入，provisional） |
| 行 = 名字 + 数量 | 逐件实例按 code 归并显示；拾起取该 code 首个实例 |
| 重要物品不能拾 | 可拾入包（provisional） |
| 手持点有物格交换进手 | `claim_reward(slot,code)`，换出物直接回待领池 |
| 空手点背包格拾起 | 无动作（PlayLoop 无背包→池命令） |
| 右键／Esc 手持放首空格；空手不关 | 同（`quick_place`） |
| 丟棄只丢一件 | 手持且池中无重要物时两次点击 `finish_rewards(abandon)` 放弃全部剩余，已入包与金钱保留（provisional） |
| 倉庫 | 放回待领池（重制无第二套存储） |
| 離開：剩余进仓库 | `finish_rewards(defer = 池非空)`，剩余留池，可从状态页／结果页重开 |
| 音 399／400／398 | `take_up`／`put_down`／`confirm`（`interface_audio`） |

## 复现

`python3 tools/hsl.py check gameplay_reference`；重制侧 `tools/godot.sh --headless --script tests/run_battle_reward_tests.gd`。

## 边界

- 录像未覆盖重要物品行、红字行、满包、滚动、丟棄／倉庫按下与離開后仓库。
- 原版队伍仓库表的读取窗口不在本包，见 [original_storage_window.md](original_storage_window.md)。
- 逐件丢弃需要 PlayLoop 新命令，重制目前没有。

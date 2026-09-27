# Original Storage Window

> evidence: static-derived; resource-derived: OBJ-049 按钮／窗模板、PROCESS.DEF、RESOURCE.TXT 字样; runtime-measured: 原版帧 15–17（狀態／裝備／倉庫 三页） · status: live · functions: 0x425a90, 0x4282c0, 0x428390, 0x428410, 0x4285e0, 0x4289e0, 0x42a330, 0x42ab40, 0x450840 · updated: 2026-09-27

- Source: original hsl.exe decompilation cache at ignored/static/hsl01/catalog/decompiled/0x42ab40.c
- Function: 0x42ab40

## Observed behavior

The function has two explicit mode branches selected by param_1.

- param_1 == 0 creates the shared storage-window object, installs the common header entries, then adds the normal item entry layout.
- param_1 == 1 sets the storage mode bit at 0x4c1cbc, resets both storage cursors at 0x4c4a04 and 0x4c4a00, then adds an alternate item entry layout.
- Both branches increment the supplied object counter at param_3 + 0x8c when shared-screen setup cannot create its object.

This packet supports the function identity and separate normal/alternate setup paths. It does not claim that every original item, cursor, input, or renderer rule is reproduced by the remake.

## 按钮与调用者（lane TOWNMAP，2026-09-27，r2 反汇编＋上述反编译缓存，未执行）

两种模式都经 `0x4285e0(win, 按钮号, x, y, flags)` 建底部按钮，y 全为 `0x1ad`＝429：

| 模式 | 按钮号 @ x（flags） |
| --- | --- |
| 1（置 `0x4c1cbc \| 2`＝商店，见[原作商店交易](original_shop_transaction.md)） | 0x2d4@284 上一位、0x2d9@332 下一位、0x2de@397 裝備、0x2df@445 買賣、0x2db@493 倉庫（0x80007fff）、0x2da@589 丟棄——与[原版实录](../runtime_observations/original_world_town/README.md)帧 08 量得的六个中心逐个相同，只有六个，倉庫 与 丟棄 之间没有第七个 |
| 0（仓库／整理） | 0x2d4@272 上一位、0x2d9@320 下一位、0x2db@389（0x80000007）与 0x2da@389（7）同位、0x2d8@457（0x80000007）与 0x2dd@437（7）、0x2de@505 裝備、0x2d6@553、0x2d7@601——flags 位 31 分两组互斥；0x2d6／0x2d7／0x2d8／0x2dd 的字样未对上 |

调用者（`axt 0x42ab40`）：剧情 act 分派 `0x450840` case 0x8b——原 `ACTION.H` 的 `actEnterStorageWindow 139`——调 `0x42ab40(0, …)`；大地图 `0x425e89` 先取当前点事件（`0x426ce0`）再以模式 0 调用；城镇过程 `0x456910` 调用（teCreateShop 开商店窗）。因此原版剧情 57／81 的仓库窗与大地图上的仓库／整理窗是同一个共用状态窗的模式 0，与商店窗、战后獲得物品窗同一套板与 handler `0x414c00`。

## 模式 0 全貌（lane PARTYEQUIP，2026-09-27，r2 反编译 `hsl01.exe`＋原 `OBJ-049` 模板，未执行）

**入口＝系统卷轴「整理裝備」。** 过程表 `0x477c2c` 第 50 项（`PROCESS.DEF defProcBigMapMenu = 50`）＝`0x425a90`；`0x425e4b` 按卷轴当前项 `[esi+0xac]` 走 6 项跳表 `0x42610c`：项 0（`0x425e58`）先 `0x4253d0` 把卷轴各项 `+0x30` 设 0xffff 隐藏、卷轴状态 `+0x8c = 0xa`，再 `0x42ab40(0, 0x426ce0(*0x4c1ba4), 卷轴)`（`0x425e89`）；项 1／2 各以 `0x423bd0(…,1)`／`(…,0)` 开存／读列表。项序与 Title051 的 整理裝備／儲存回憶錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單 相符。剧情 act 0x8b 与卷轴项 0 进的是同一个 `0x42ab40(0,…)`。

**窗体。** `0x428390` 建根（模板 710 BM_Window_0，`+0x94 = 4`＝初始页「狀態」，根旗 `0x40000000`，无获得物品窗挡右键的 `0x400`）；`0x428410(win, n)` 按 n 建子窗（落点 `+0xaa／+0xa8`，自 `+0xa6／+0xa4` 滑入）：

| n | 模板（OBJ-049） | 落点 | 模式 0 | 模式 1（商店） |
| --- | --- | --- | --- | --- |
| 1 | 711 BM_Window_1 WINDOW10 | (381,14) | ✓ | ✓ |
| 2 | 712 BM_Window_2 WINDOW20 | (12,168) | ✓ | ✓ |
| 3 | 713 Status_Window_3 WINDOW30 | (252,168) | ✓ | ✓ |
| 4 | 714 BM_Window_4 WINDOW40 `$:` | (20,442) | ✓ | ✓ |
| 6 | 716 Status_Window_6 WINDOW90（`defProcBMGetItemWindow`），标题 `+0xa0 = 0x135`＝RESOURCE 309「倉庫」 | (252,168) | ✓ | ✓ |
| 7 | 716 同上，标题 `+0xa0 = *0x4c28a8`（店名） | (252,168) | — | ✓ |

外加 `0x428570` 三条：717 HP／718 MP 于 (170,67)／(170,97)，719 ST 于 (154,116)。

**九个按钮（模板 724–735，`defProcBMWindowButton` 过程表第 55 项＝`0x42a330`；字样＝`obj_Data9` 的 RESOURCE 号）：**

| 模板 | SHP | 字样（RESOURCE） | x @ y 429 | flags `+0x98` | `obj_Data6`＝按下做什么（`0x42a330` 子状态 3 跳表 `0x42a9a8`） |
| --- | --- | --- | --- | --- | --- |
| 724 Button_Prev | B_PREV1 | 上一位（133） | 272 | 常显 | 0：`0x4282c0(*0x4c59cc,1,-1)` 往前找下一名在队成员（20 格环绕），重载窗 |
| 729 Button_Next | B_NEXT1 | 下一位（134） | 320 | 常显 | 5：同上往后 |
| 731 Button_Storage | BCMD15_1 | 倉庫（309） | 389 | `0x80000007`：页≠7 时显 | 7：flags 有效 → 页＝7（右侧换成仓库列表 6） |
| 728 Button_Attr | BCMD13_1 | 狀態（40） | 457 | `0x80000007`：页≠7 时显 | 4：页＝4 |
| 730 Button_Drop | BCMD08_1 | 丟棄（`bcommand_7`＝26） | 389 | `7`：仅页＝7 时显 | 6：手持物非重要（`0x40e690==0`）→ 手持清零（丢弃） |
| 733 Button_Use | BCMD05_1 | 使用（23） | 437 | `7`：仅页＝7 时显 | 9：手持物对当前成员 `0x409e40(成员, 物, 0, 1)` 成功 → 刷新、手持清零 |
| 734 Button_Equip | BCMD07_1 | 裝備（25） | 505 | 常显 | 10：页＝10，另 `0x434d10(…,0,1)` |
| 726 Button_Magic | BCMD09_1 | 魔法（28） | 553 | 常显 | 2：页＝2 |
| 727 Button_Special | BCMD10_1 | 特殊技（29） | 601 | 常显 | 3：页＝3 |

flags 读法（`0x42a330` 每 tick）：`-1`／0 常显；位 31 清 → 页（根 `+0x94`）＝flags 才显；位 31 置 → 页＝`flags & 0x7fffffff` 时隐藏。所以「倉庫／狀態」与「丟棄／使用」按页互斥（389 同位）。点击音 0x18e（398 ACCEPT01）；`*0x4c6390` 的 0x10000／0x20000 位另触发 上一位／下一位。模式 0 没有「離開」钮（732 Button_Exit 未建），右键／Esc 由根关闭。

**各页内容（`defProcBMWindow`＝`0x4289e0`）：**

- 左窗 2（(12,168)）按页换内容：页 1／7／10／11 → 背包 8 格，行距 `+0x98 = 0x20`（32），文字 x 偏移 0x30；空手点有物格 → 拾起（`0x436e80`，音 399），手持点格 → 手持物入背包首空格、格中物进手（音 400）；悬停 → `0x430710`＋`0x436d70` 描述框、行名绿。页 2 → 魔法列表（`*0x4c1cd8` 条，行距 28，最多 9 行，滚动 `*0x4c59c0`，悬停 `0x4331b0` 描述）；页 3 → 特殊技列表（`*0x4c1cdc` 条，行距 28，悬停 `0x433a90`）；页 4 → 狀態属性（形状表项 2，行距 28）。
- 右窗 3（WINDOW30，(252,168)）：页≠7 且≠11 时画六个装备槽（成员记录 `+0xec…+0x100`），两列三行：图标于 (x+0x68, y+0x1a+行·行距)／(x+0x11c, …)，名字于 (x+0x2c, …)／(x+0xe0, …)；命中 `列 = (mx−x)/(宽/2)`、`行 = (my−y−16)/行距`。**只有页 10（裝備）可换装**：空手点有物槽 → `0x437020` 卸下进手（音 399）；手持点任意槽 → `0x436f30(成员, 手持物)` 按物品类别装上、旧装备进手（返回 −1＝不能装，手持不变、无音无字）（音 400）。页 10 手持时鼠标移入右窗 → 根页改 0x40a（左窗高字节 4＝暂显狀態属性），移出回 10。
- 页 7：右窗换成列表 6（WINDOW90「倉庫」，与獲得物品窗同一列表过程）。

**原版实拍核对**（[原版实录](../runtime_observations/original_world_town/README.md)帧 15–17，2026-09-27 一趟 Wine）：卷轴「整理裝備」开在狀態页，七钮与倉庫页的七钮（丟棄 389、使用 437 取代 倉庫／狀態）与上表逐个相同；当前页的按钮画暗（`+0x10000000`）；右键关窗后回到卷轴。另见两处本包未读的着色：狀態页 力量 51 为黄字（其余白字），裝備页背包里的 回復藥 为红字（倉庫页同一件为白字）。

未读：页 2／3 列表的形状表项 5／10 对应哪张板、魔法／特殊技悬停描述的逐行格式；`0x426ce0` 返回值在模式 0 里的用途（反编译里 `0x42ab40` 的 param_2 未被读）。

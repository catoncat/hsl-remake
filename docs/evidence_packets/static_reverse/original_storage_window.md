# 共用状态窗：仓库／整理裝備（模式 0）与商店（模式 1）

> evidence: static-derived; resource-derived: OBJ-049 按钮／窗模板、PROCESS.DEF、RESOURCE.TXT 字样; runtime-measured: 原版帧 15–17（狀態／裝備／倉庫 三页） · status: live · functions: 0x425a90, 0x4282c0, 0x428390, 0x428410, 0x4285e0, 0x4289e0, 0x42a330, 0x42ab40, 0x450840 · updated: 2026-09-27

## 结论

- 原版：`0x42ab40(mode, …)` 建共用状态窗；模式 0 是仓库／整理裝備（系统卷轴项 0、剧情 `actEnterStorageWindow` 139、大地图点事件共用），模式 1 置 `0x4c1cbc|2` 是商店；两者同一套板与 handler `0x414c00`，底部按钮由 `0x4285e0` 建在 y 429，按页显隐（static-derived）。
- 模式 0 初始页 狀態（4）；只有裝備页（10）能换装；倉庫页（7）才显 丟棄／使用；右键／Esc 由根关闭，无「離開」钮；与原版帧 15–17 七钮位置与板左上角逐像素偏移 (0,0)（static-derived；runtime-measured）。
- 重制：`game/world/PartyEquipmentScreen.gd` 宿主＋`game/world/TownShopScreen.gd` 的 MODE_ARRANGE 窗体，规则 `game/sim/PartyEquipmentRules.gd`（static-derived）。
- 差异：倉庫 暗置（重制无队伍仓库），丟棄／使用因而不出现；空手卸下进背包；魔法／特殊技页无悬停说明与滚动条；裝備页手持移入装备板暂显狀態未做；差异清单 `party-equipment-screen`（provisional）。

## 证据

**static-derived**（r2 反汇编与反编译 `hsl01.exe`，未执行；OBJ-049 模板）

调用者（`axt 0x42ab40`）：剧情 act 分派 `0x450840` case 0x8b 调 `0x42ab40(0, …)`；大地图 `0x425e89` 先取当前点事件 `0x426ce0` 再以模式 0 调用；城镇过程 `0x456910`（teCreateShop）开商店窗。过程表 `0x477c2c` 第 50 项（`PROCESS.DEF defProcBigMapMenu = 50`）＝`0x425a90`；`0x425e4b` 按卷轴项 `[esi+0xac]` 走 6 项跳表 `0x42610c`：项 0（`0x425e58`）先 `0x4253d0` 把卷轴各项 +0x30 设 0xffff 隐藏、卷轴 +0x8c = 0xa，再调 `0x42ab40`；项 1／2 以 `0x423bd0(…,1)`／`(…,0)` 开存／读列表。项序对应 Title051 的 整理裝備／儲存回憶錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單。模式 1 另重置两个仓库光标 `0x4c4a04`／`0x4c4a00`。

商店（模式 1）按钮：0x2d4@284 上一位、0x2d9@332 下一位、0x2de@397 裝備、0x2df@445 買賣、0x2db@493 倉庫（0x80007fff）、0x2da@589 丟棄，与原版帧 08 六个中心相同；交易见 [original_shop_transaction.md](original_shop_transaction.md)。

窗体：`0x428390` 建根（模板 710 BM_Window_0，+0x94 = 4，根旗 `0x40000000`，无獲得物品窗挡右键的 `0x400`）；`0x428410(win, n)` 建子窗（落点 +0xaa／+0xa8，自 +0xa6／+0xa4 滑入）：

| n | 模板（OBJ-049） | 落点 | 模式 0 | 模式 1 |
| --- | --- | --- | --- | --- |
| 1 | 711 BM_Window_1 WINDOW10 | (381,14) | ✓ | ✓ |
| 2 | 712 BM_Window_2 WINDOW20 | (12,168) | ✓ | ✓ |
| 3 | 713 Status_Window_3 WINDOW30 | (252,168) | ✓ | ✓ |
| 4 | 714 BM_Window_4 WINDOW40 `$:` | (20,442) | ✓ | ✓ |
| 6 | 716 Status_Window_6 WINDOW90（`defProcBMGetItemWindow`），标题 +0xa0 = 0x135＝RESOURCE 309「倉庫」 | (252,168) | ✓ | ✓ |
| 7 | 716 同上，标题 +0xa0 = `*0x4c28a8`（店名） | (252,168) | — | ✓ |

`0x428570` 另建 717 HP／718 MP 于 (170,67)／(170,97)，719 ST 于 (154,116)。

模式 0 九个按钮（模板 724–735，`defProcBMWindowButton`＝过程表第 55 项 `0x42a330`；字样＝obj_Data9 的 RESOURCE 号）：

| 模板 | SHP | 字样（RESOURCE） | x @ y 429 | flags +0x98 | 按下（`0x42a330` 子状态 3 跳表 `0x42a9a8`） |
| --- | --- | --- | --- | --- | --- |
| 724 Button_Prev | B_PREV1 | 上一位（133） | 272 | 常显 | 0：`0x4282c0(*0x4c59cc,1,-1)` 往前找在队成员（20 格环绕）重载 |
| 729 Button_Next | B_NEXT1 | 下一位（134） | 320 | 常显 | 5：往后 |
| 731 Button_Storage | BCMD15_1 | 倉庫（309） | 389 | `0x80000007`：页≠7 时显 | 7：页＝7 |
| 728 Button_Attr | BCMD13_1 | 狀態（40） | 457 | `0x80000007`：页≠7 时显 | 4：页＝4 |
| 730 Button_Drop | BCMD08_1 | 丟棄（26） | 389 | `7`：仅页＝7 | 6：手持物非重要（`0x40e690==0`）则清零 |
| 733 Button_Use | BCMD05_1 | 使用（23） | 437 | `7`：仅页＝7 | 9：`0x409e40(成员, 物, 0, 1)` 成功则刷新、清手持 |
| 734 Button_Equip | BCMD07_1 | 裝備（25） | 505 | 常显 | 10：页＝10，另 `0x434d10(…,0,1)` |
| 726 Button_Magic | BCMD09_1 | 魔法（28） | 553 | 常显 | 2：页＝2 |
| 727 Button_Special | BCMD10_1 | 特殊技（29） | 601 | 常显 | 3：页＝3 |

flags：-1／0 常显；位 31 清→页＝flags 才显；位 31 置→页＝`flags & 0x7fffffff` 时隐藏。点击音 0x18e（398 ACCEPT01）；`*0x4c6390` 的 0x10000／0x20000 位另触发 上一位／下一位。

各页（`defProcBMWindow`＝`0x4289e0`）：

| 区域 | 页 | 内容 |
| --- | --- | --- |
| 左窗 2 (12,168) | 1／7／10／11 | 背包 8 格，行距 32，文字 x 偏移 0x30；空手点有物格拾起（`0x436e80`，音 399），手持点格则手持物入首空格、格中物进手（音 400）；悬停 `0x430710`＋`0x436d70` 描述框，行名绿 |
| 左窗 2 | 2／3 | 魔法（`*0x4c1cd8` 条）／特殊技（`*0x4c1cdc` 条），行距 28，最多 9 行，滚动 `*0x4c59c0`，悬停 `0x4331b0`／`0x433a90` |
| 左窗 2 | 4 | 狀態属性（形状表项 2，行距 28） |
| 右窗 3 WINDOW30 (252,168) | ≠7 且 ≠11 | 六个装备槽（成员 +0xec…+0x100）两列三行；图标 (x+0x68, y+0x1a+行·行距)／(x+0x11c, …)，名字 (x+0x2c, …)／(x+0xe0, …)；命中 列＝(mx−x)/(宽/2)、行＝(my−y−16)/行距 |
| 右窗 3 | 10 | 空手点有物槽 `0x437020` 卸下进手（音 399）；手持点槽 `0x436f30` 装上、旧装备进手（-1 不能装，手持不变、无音无字）；手持移入右窗时根页改 0x40a（左窗暂显狀態），移出回 10 |
| 右窗 | 7 | 换成列表 6（WINDOW90「倉庫」，与獲得物品窗同一列表过程） |

**runtime-measured**（[原版实录](../runtime_observations/original_world_town/README.md)帧 15–17）：卷轴「整理裝備」开在狀態页；七钮与倉庫页七钮（丟棄 389、使用 437 取代 倉庫／狀態）与上表相同；当前页按钮画暗（+0x10000000）；右键关窗回卷轴；七个按钮图标、WINDOW21／WINDOW30 左上角、`$:` 框最佳偏移都是 (0,0)。狀態页 力量 51 为黄字（其余白字）；裝備页背包里的 回復藥 为红字（倉庫页同一件为白字）。

## 重制接线

- `game/world/PartyEquipmentScreen.gd`：`open` 是大地图卷轴「整理裝備」与剧情 57／81、winfail 045／078 的 `actEnterStorageWindow` 共同入口；关窗把新队伍写回 hand-off carry 与 `user://campaign_progress.json`，其余顶层字段（金币、`pending_rewards`、`initialization_rng`）原样保留；来源场景缺失时 `unknown_source_scenario` 只可关闭，无 carry 时 `no_party`。
- `game/world/TownShopScreen.gd` MODE_ARRANGE：窗体、按钮条与按页显隐；左板 狀態＝WINDOW21 九行、裝備＝背包 8 格、魔法／特殊技＝WINDOW20 列表；右板六槽每页都显示，悬停出 WINDOW50 说明 (252,390)。
- `game/sim/PartyEquipmentRules.gd` `change`：与 `BattlePlayLoop.change_equipment` 同序，去掉战斗阶段门与行动结算；被拒物留在手上、无消息；右键／Esc 先放回手上物再关窗。
- 队员来源＝carry.units；城镇 Esc 是离开城镇，无系统卷轴入口。

## 复现

`tools/godot.sh --headless --script tests/run_system_menu_tests.gd`（卷轴「整理裝備」返回 `party_equipment`）。截图驱动 `tests/capture_party_equipment_review.gd` 保留（`tools/oss_screenshots.py` 使用），旧帧在 `runtime_observations/party_equipment/`。

## 边界

- 未读：页 2／3 列表的形状表项 5／10 对应哪张板、魔法／特殊技悬停描述的逐行格式。
- 狀態页黄字与裝備页红字的着色条件未读，重制未做。
- `0x426ce0` 返回值在模式 0 的用途未读（`0x42ab40` 的 param_2 反编译里未被读）。
- 来源场景缺失的提示字是重制自拟。

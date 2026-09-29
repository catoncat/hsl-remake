# 共用状态窗：仓库／整理裝備（模式 0）与商店（模式 1）

> evidence: static-derived; resource-derived: OBJ-049 按钮／窗模板、PROCESS.DEF、RESOURCE.TXT 字样; runtime-measured: 原版帧 15–24（狀態／裝備／倉庫 三页、商店 裝備／倉庫 页与存取、换人后手持） · status: live · functions: 0x409e10, 0x409e40, 0x414c00, 0x414db9, 0x414e67, 0x425a90, 0x4282c0, 0x428390, 0x428410, 0x4285e0, 0x4289e0, 0x42923b, 0x42a330, 0x42a5dd, 0x42a68f, 0x42a930, 0x42aa50, 0x42aad0, 0x42ab40, 0x434d10, 0x436e80, 0x436f30, 0x437020, 0x446060, 0x448840, 0x44ef70, 0x44efe0, 0x44f100, 0x44f170, 0x44f2d0, 0x44f430, 0x44f670, 0x44f720, 0x44f8a0, 0x450840, 0x45e80d, 0x45e882 · updated: 2026-09-29

## 结论

- 原版：`0x42ab40(mode, …)` 建共用状态窗；模式 0 是仓库／整理裝備（系统卷轴项 0、剧情 `actEnterStorageWindow` 139、大地图点事件共用），模式 1 置 `0x4c1cbc|2` 是商店；两者同一套板与 handler `0x414c00`，底部按钮由 `0x4285e0` 建在 y 429，按页显隐（static-derived）。
- 模式 0 初始页 狀態（4）；只有裝備页（10）能换装；倉庫页（7）才显 丟棄／使用；右键／Esc 由根关闭，无「離開」钮；与原版帧 15–17 七钮位置与板左上角逐像素偏移 (0,0)（static-derived；runtime-measured）。
- 原版换人保留手持：上一位／下一位（`0x42a330` case 0／5）只调 `0x4282c0` 换成员并以 `0x434d10` 重载，二者都不写手持 `0x4c1ce4`；商店（帧 18）与整理裝備（帧 24）换人后物品仍在光标上（static-derived；runtime-measured）。
- 原版倉庫是一份存档里的队伍存储：重要 `0x4c1d10`／普通 `0x4c1d1c` 两张 (code, qty) 表，初容量 5、满了加 5、无上限，同 code 叠数；手持点列表放入一件，空手点行取出一件（重要物品取不出）；丟棄 清掉非重要手持物，使用 ＝`0x409e40(成员, 物, 0, 1)`；商店 倉庫 页（7）与整理裝備 倉庫 页是同一份（帧 20–23）；商店 裝備 页（10）在右板显示六槽并可换装（帧 19）（static-derived；runtime-measured）。
- 重制：`game/world/PartyEquipmentScreen.gd` 宿主＋`game/world/TownShopScreen.gd` 的 MODE_ARRANGE 窗体，规则 `game/sim/PartyEquipmentRules.gd` `hand_action`、存储 `game/sim/PartyStorageRules.gd`（carry.loop.party_storage）；商店同一窗体经 `TownRuntime.shop_hand`（static-derived）。
- 拿起背包物即离包（`0x436e80`）、空手卸下与装上换下的旧件进手（`0x437020`／`0x436f30`）、商店买入进手持再放下（[original_shop_transaction](original_shop_transaction.md)）已照原版（lane SHOPHAND）。
- 原版 倉庫 页 使用（`0x42a887`）＝`0x409e40(成员, 物, 0, 1)`：`0x40a121` 先无条件清 ebp，第四参 1 使 `0x40a125` 跳过临时攻防块（→ `0x40a1b9`；块内 `0x40a16d` 才置 ebp＝1），ebp 因此为 0，`0x40a39b` 跳过飘字与效果对象（→ `0x40a5a5`）；永久块（`0x409ef8`–`0x40a115`）照跑，每项以 `0x409e10` 从伤害随机流抽 low＋rand(high−low＋1)。力／禦／魔／速之源字段非零即置永久旗（`0x409f22`）；土／火／水／風／靈之源先抽样、抗性夹到 80（`0x409fb3` ebp＝0x50），增量 >0 才置旗。返回值（`0x40a369`–`0x40a391` 写 `[esp+0x28]`）在 HP +0x2c、MP +0x28、状态字 +0xa0 & 0xf0000080（`0x409eed`）、气力 +0x30（`0x40a27d`–`0x40a298` 加到 live +0xe8、夹到 60）、ebp、永久旗任一非零时为 1；计数 edi 与之同真，非零时放 402 sfxUseItem（`0x40a347`）；ebp、永久旗与解状态块各以 `0x448840` 刷新（`0x40a2a4`／`0x40a2b6`／`0x40a337`）。返回 0（會心之素／鐵壁之素 只有临时字段；抗性已 80 的抗性之源——已抽样）时 `0x42a8a6` 保留手持；否则 `0x434d10` 重载、`0x42a8bb` 清手持 `0x4c1ce4`（static-derived）。
- 原版空手卸下 `0x437020`：物品 +0xa4 字节位 2 置则返回 0、不动；否则清槽并返回原 code，不查背包空位；调用处 `0x429e75` 写手持后 `0x448840`／`0x434d10`（static-derived）。
- 原版右键／Esc：根态 `0x428dac` 测右键 `*0x4c6398 & 0x20000` 或 Esc `*0x4c6390 & 0x100000`，`0x428dc7` 只在手持 `0x4c1ce4` 为 0 时关窗，持物时不动作；窗内其余读写 `0x4c1ce4` 的路径都走左键位 0x40000；关窗 `0x42aad0` 不碰手持（static-derived）。
- 倉庫 页 使用（永久道具抽样、返回 0 不消耗、402）与满包空手卸下已照原版（lane EQUIPUSE）。
- 原版开窗滑入：`0x428410` 把子窗起点写成落点偏 400（WINDOW10 自上 y−400、WINDOW20／WINDOW40 自左 x−400、WINDOW30 与列表窗 WINDOW90 自右 x+400），`0x4285e0` 把按钮起点写成 y＋400（自下）；列表窗 state 0（`0x414db9`）与按钮子状态 0（`0x42a5dd`）每 tick `0x45e882(当前, 落点, 40)`：距离 ≤1 落位，否则走 min(40, 距离>>3)、至少 2，400 px 共 34 tick；关窗滑出 state 2（`0x414e67`）与子状态 4（`0x42a930`）每 tick `0x45e80d(当前, 起点, 容差 4, 步 20)`：逐轴走剩余一半、上限 20，剩 ≤4 落位，共 23 tick（static-derived）。
- 重制：`TownShopScreen` 开窗（`open`／`open_arrange`）全部部件共用同一剩余距离逐 tick 走 `slide_in_step`，只改绘制变换、命中照落点；返回键关窗时把最后一帧按部件快照、按 `slide_out_step` 滑回起点（无渲染器跳过）（static-derived）。
- 差异：列表即时按重要在前排序（原版开窗时并入一张池、关窗才分表）；魔法／特殊技页无悬停说明与滚动条；裝備页手持移入装备板暂显狀態未做；差异清单 `party-equipment-screen`（provisional）。

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

起点（`0x428410` 写 +0xa6／+0xa4，`0x4285e0` 写按钮的同两字）：n=1 (381,−386)、n=2 (−388,168)、n=3／6／7 (652,168)、n=4 (−380,442)，按钮 (x, 829)；过程首次调用把 +0xa4 dword 抄进当前位置 +0x90（列表窗 `0x414c87`、按钮 `0x42a475`）。滑入 `0x414db9`／`0x42a5dd` 压参 (+0x92, +0x90, +0xaa, +0xa8, 0x28)，`0x45e882` 返回 0 时 +0x8c 进下一状态；滑出 `0x414e67`／`0x42a930` 压参 (+0x92, +0x90, +0xa6, +0xa4, 4, 0x14)，`0x45e80d` 返回 1 时 +0x8c 进下一状态。子窗与按钮只在 `0x42ab40`（`0x42abd4`–`0x42ae81`）一次建齐，换页不重建、不滑。

`0x428570` 另建 717 HP／718 MP 于 (170,67)／(170,97)，719 ST 于 (154,116)。

模式 0 九个按钮（模板 724–735，`defProcBMWindowButton`＝过程表第 55 项 `0x42a330`；字样＝obj_Data9 的 RESOURCE 号）：

| 模板 | SHP | 字样（RESOURCE） | x @ y 429 | flags +0x98 | 按下（`0x42a330` 子状态 3 跳表 `0x42a9a8`） |
| --- | --- | --- | --- | --- | --- |
| 724 Button_Prev | B_PREV1 | 上一位（133） | 272 | 常显 | 0：`0x4282c0(*0x4c59cc,1,-1)` 往前找在队成员（20 格环绕）重载 |
| 729 Button_Next | B_NEXT1 | 下一位（134） | 320 | 常显 | 5：往后 |
| 731 Button_Storage | BCMD15_1 | 倉庫（309） | 389 | `0x80000007`：页≠7 时显 | 7：页＝7 |
| 728 Button_Attr | BCMD13_1 | 狀態（40） | 457 | `0x80000007`：页≠7 时显 | 4：页＝4 |
| 730 Button_Drop | BCMD08_1 | 丟棄（26） | 389 | `7`：仅页＝7 | 6：手持物非重要（`0x40e690==0`）则清零 |
| 733 Button_Use | BCMD05_1 | 使用（23） | 437 | `7`：仅页＝7 | 9：`0x409e40(成员, 物, 0, 1)` 返回非零则刷新、清手持，返回 0 手持不变 |
| 734 Button_Equip | BCMD07_1 | 裝備（25） | 505 | 常显 | 10：页＝10，另 `0x434d10(…,0,1)` |
| 726 Button_Magic | BCMD09_1 | 魔法（28） | 553 | 常显 | 2：页＝2 |
| 727 Button_Special | BCMD10_1 | 特殊技（29） | 601 | 常显 | 3：页＝3 |

flags：-1／0 常显；位 31 清→页＝flags 才显；位 31 置→页＝`flags & 0x7fffffff` 时隐藏。按钮子状态 2（`0x42a68f`）：按钮 id＝父窗当前页（+0x94 == +0xa0）时画暗（+0x10000000）且不响应；否则点击（参数位 0x40000）或 `*0x4c6390` 位 0x10000 且 id 0（上一位）／位 0x20000 且 id 5（下一位）（`0x42a6d3`–`0x42a6ef`）进子状态 3，同时放 0x18e（398 ACCEPT01，`0x42a6f4`–`0x42a70f` 经 `0x4477b0`／`0x459990`／`0x42c180`）。

各页（`defProcBMWindow`＝`0x4289e0`）：

| 区域 | 页 | 内容 |
| --- | --- | --- |
| 左窗 2 (12,168) | 1／7／10／11 | 背包 8 格，行距 32，文字 x 偏移 0x30；空手点有物格拾起（`0x436e80`，音 399），手持点格则手持物入首空格、格中物进手（音 400）；悬停 `0x430710`＋`0x436d70` 描述框，行名绿 |
| 左窗 2 | 2／3 | 魔法（`*0x4c1cd8` 条）／特殊技（`*0x4c1cdc` 条），行距 28，最多 9 行，滚动 `*0x4c59c0`，悬停 `0x4331b0`／`0x433a90` |
| 左窗 2 | 4 | 狀態属性（形状表项 2，行距 28） |
| 右窗 3 WINDOW30 (252,168) | ≠7 且 ≠11 | 六个装备槽（成员 +0xec…+0x100）两列三行；图标 (x+0x68, y+0x1a+行·行距)／(x+0x11c, …)，名字 (x+0x2c, …)／(x+0xe0, …)；命中 列＝(mx−x)/(宽/2)、行＝(my−y−16)/行距 |
| 右窗 3 | 10 | 空手点有物槽 `0x437020` 卸下进手（音 399）；手持点槽 `0x436f30` 装上、旧装备进手（-1 不能装，手持不变、无音无字）；手持移入右窗时根页改 0x40a（左窗暂显狀態），移出回 10 |
| 右窗 | 7 | 换成列表 6（WINDOW90「倉庫」，与獲得物品窗同一列表过程） |

**倉庫数据（static-derived）**

| 地址 | 作用 |
| --- | --- |
| `0x44f670` | 两表初始化：容量 5、条数 0（重要 `0x4c1d10`／`0x4c1d14`／`0x4c1d18`，普通 `0x4c1d1c`／`0x4c1d20`／`0x4c1d24`） |
| `0x44ef70`／`0x44f100(code, n)` | 放入：找同 code 的在用条目加数，否则追加；满了 `0x44ee30`／`0x44ee90` realloc 加 5，无上限 |
| `0x44efe0`／`0x44f170` | 取出一件，数量到 0 删行并前移 |
| `0x44f720`／`0x44f8a0` | 存／读档：两表各写容量、条数与数据 |
| `0x42aa50` | 模式 0 开窗：清池 `0x4c1d28`，先重要后普通经 `0x44f2d0` 并入池，再 `0x44f210`／`0x44f250` 清两表 |
| `0x42aad0` | 关窗：池中每条按 `0x40e690` 重要与否回 `0x44ef70`／`0x44f100`，`0x44f4e0` 释放池 |
| `0x414c00` 列表点击（非商店或子类型 6） | 手持 → `0x44f2d0(物, 1)` 入列表（音 400）；空手 → `0x44f3f0` 读行，重要物 `0x4154cd` 拒取，否则手持＝code、`0x44f430(行, 1)`（音 399） |
| `0x42923b` 背包格点击（手持） | `0x436ed0` 背包第 8 格有物（满）→ 格中物与手持互换；否则手持物进首空格 `0x436e30` |
| `0x42a330` case 6 `0x42a7e2` | 丟棄：`0x40e690(手持)==0` 才清 `0x4c1ce4` |
| `0x42a330` case 7 `0x42a80a` | 倉庫钮：flags 为 0／-1 时把手持物存入（`0x44ef70`／`0x44f100(物,1)`），否则页＝7 |
| `0x42a330` case 9 `0x42a887` | 使用：`0x409e40(成员, 物, 0, 1)` 返回 0 走 `0x42a8a6` 保留手持；非零则 `0x434d10` 重载、`0x42a8bb` 清 `0x4c1ce4` |
| `0x437020` | 空手卸下：物品 +0xa4 位 2 置返回 0；否则清槽、返回原 code，无背包检查；调用处 `0x429e75` 写手持、`0x448840`／`0x434d10` |
| `0x4289e0` 根态 `0x428dac`／`0x428dc7` | 右键 `0x4c6398&0x20000` 或 Esc `0x4c6390&0x100000`：手持为 0 才关窗，否则不动作 |
| `0x42a330` case 0／5 `0x42a76e`／`0x42a77a` | `0x4282c0(*0x4c59cc, 1／0, -1)` 换人；`0x4282c0` 与 `0x434d10` 内无 `0x4c1ce4` 写入 |

商店（模式 1）按钮 flags：倉庫 `0x80007fff`（常显）、丟棄／裝備／買賣 -1（常显）；裝備 case 10 页＝10，買賣 页＝11，倉庫 页＝7；初始页 0xb。

**runtime-measured**（[原版实录](../runtime_observations/original_world_town/README.md)帧 15–17）：卷轴「整理裝備」开在狀態页；七钮与倉庫页七钮（丟棄 389、使用 437 取代 倉庫／狀態）与上表相同；当前页按钮画暗（+0x10000000）；帧 18–24：商店换人手持保留、裝備 页右板六槽、倉庫 页放入叠数与取出、商店存入在整理裝備可见、整理裝備换人手持保留；右键关窗回卷轴；七个按钮图标、WINDOW21／WINDOW30 左上角、`$:` 框最佳偏移都是 (0,0)。狀態页 力量 51 为黄字（其余白字）；裝備页背包里的 回復藥 为红字（倉庫页同一件为白字）。

## 重制接线

- `game/world/PartyEquipmentScreen.gd`：`open` 是大地图卷轴「整理裝備」与剧情 57／81、winfail 045／078 的 `actEnterStorageWindow` 共同入口；关窗把新队伍写回 hand-off carry 与 `user://campaign_progress.json`，其余顶层字段（金币、`pending_rewards`、`initialization_rng`）原样保留，携带的伤害随机流 `damage_rng` 进沙盒并取回沙盒的（使用 从它抽样）；来源场景缺失时 `unknown_source_scenario` 只可关闭，无 carry 时 `no_party`。
- `game/world/TownShopScreen.gd` MODE_ARRANGE：窗体、按钮条与按页显隐；左板 狀態＝WINDOW21 九行、裝備＝背包 8 格、魔法／特殊技＝WINDOW20 列表；右板六槽每页都显示，悬停出 WINDOW50 说明 (249,390)：`0x436d70` 在镜头＋(252,349) 画框，`[0x4c1cbc]` bit 0 时 y＋41、bit 1 未置时 x−3；模式 0（`0x425e89` push 0）在 `0x42ab8c` 跳 `0x42acfe`，只有 `0x42ab4b` 置的 bit 0（static-derived；原版帧 15–17、23、24 无悬停框，未实测）。商店（模式 1，`0x45686e`）另在 `0x42ab9f` 或上 bit 1，框在 (252,390)（原版帧 10、22）。
- `game/sim/PartyStorageRules.gd`：`hsl_party_storage.v1` 两表（important／normal，[{code, qty}]），`put` 同 code 叠数、`take` 拒重要物；存在 carry.loop.party_storage，`CampaignCarryRules` 的 loop 键让它随 carry 跨场与存档，旧 carry 读作空。
- `PartyEquipmentRules.hand_action`：place（满包互换，换出物成散件手持）／store／retrieve（须空手）／drop（拒重要）／use（`_use_stored`：`ItemUseRules.prepare` 的 HP／MP／气力／解状态＋`ItemResolutionRules.draw_permanent` 抽样与 `refresh_growth_stats`，不跑临时攻防；返回 0 拒用、手持不变而抽样保留；成功耗一件、清手持、放 402 `use_item.wav`）／equip（外来或散件先放进该成员背包再 `change`，换下的旧件进手）／lift（拿起即离包，`0x436e80`）／unequip（空手卸下进手、不占背包，`0x437020`；`unequip_blocked` 拒）／back（放回当前成员首空格；满包时散件留在手上）。
- `TownShopScreen.gd`：换人不清手持；商店六钮都可按，当前页画暗；裝備 页（10）右板六槽、倉庫 页（7）WINDOW90 列表（数量右对齐）；手势发 `hand_requested`，整理裝備由 `PartyEquipmentScreen` 结算、商店由 `TownRuntime.shop_hand` 结算后写回 carry；商店散件点货表由 `TownRuntime.shop_sell_hand` 卖出。
- `TownShopScreen._build_list`：商店货表与倉庫页列表同是 `0x414c00`，首帧（`0x414c3e` 窗标志 0x20000000，不看商店标志）挂 `0x446060(win, 760, 151, 152, 153, 宽−24, 0, 0, 0, 5, 0x414af0)`——与獲得物品窗同一个 `BattleSkillScrollBar(LIST_AT, "WIN06BAR", 5, 351)`（箭头松开 ±1、槽点翻 5 行、拖动；不超过 5 行不出现）；滚动只换行不重建整页（static-derived）。键掩码同獲得物品窗（`0x445f00` 存成 0x800／0x1000／4／8，`0x445860` 读 ↑↓ 与 PgUp／PgDn，见 [original_getitem_window.md](original_getitem_window.md)）；重制未接键（差异清单 `shop-hand-cursor`）。
- `TownShopScreen.press_button`：当前页按钮不响应；其余按下放 ACCEPT01（`interface_audio/confirm.wav`＝398）再走按下分派；←／→ 键按 上一位／下一位（键位对应 0x10000／0x20000 取自状态审计复核）。
- `TownShopScreen.gd` 滑动：`slide_in_step`＝`0x45e882`、`slide_out_step`＝`0x45e80d`（单轴）；部件分边按节点：`Vitals`（WINDOW10 与 HP／MP／ST）自上，`Button_`／`Caption_` 自下，其余中心 x<252 自左、否则自右；说明框、消息板、手持不滑；关窗快照挂在宿主层之上的 CanvasLayer。
- `game/sim/PartyEquipmentRules.gd` `change`：与 `BattlePlayLoop.change_equipment` 同序，去掉战斗阶段门与行动结算；被拒物留在手上、无消息；右键／Esc 先放回手上物再关窗（放回是重制读法）。
- 队员来源＝carry.units；城镇 Esc 是离开城镇，无系统卷轴入口。

## 复现

`tools/godot.sh --headless --script tests/run_system_menu_tests.gd`（卷轴「整理裝備」返回 `party_equipment`）。城镇场景 `tools/godot.sh --headless --script tests/run_town_scene_tests.gd`（商店六钮可按）。截图驱动 `tests/capture_party_equipment_review.gd` 保留（`tools/oss_screenshots.py` 使用），旧帧在 `runtime_observations/party_equipment/`。

## 边界

- 未读：页 2／3 列表的形状表项 5／10 对应哪张板、魔法／特殊技悬停描述的逐行格式。
- 裝備页背包行颜色照 `0x414c00` 行色（重要 @6、本职可用 @1、否则 @2 红，与獲得物品窗同一套），重制 `TownShopScreen._row_color`；狀態页黄字（力量 51）已读：`0x4289e0` 狀態页的四项属性经 `0x434d10` 调 `0x434bf0`，`cap−50 ≤ base < cap` 为 `@5` 黄、到上限 `@2` 红（SID 7 咕嚕不黄），细节见 [升級窗](original_growth_window.md) §3 行 0–3，重制 `TownShopScreen._build_attributes` 调 `BattleGrowthPanel.attribute_text`。
- `0x426ce0` 返回值在模式 0 的用途未读（`0x42ab40` 的 param_2 反编译里未被读）。
- 来源场景缺失的提示字是重制自拟。
- 战后獲得物品窗的 倉庫／離開 与本窗共用同一份队伍倉庫（`store_reward` → `PartyStorageRules.put`，见 [original_getitem_window](original_getitem_window.md)「结论」）。
- 持物时右键／Esc 原版不动作（`0x428dc7`），重制默认同；OPT-GUIDE＝提示 时放回当前成员首空格（满包时散件留在手上）。
- 父窗把子窗切到滑出状态的触发点（+0x80 旗位经引擎分派）与关窗是否等子窗滑完未读；重制关窗立即交回宿主，只留快照滑出。717／718／719 HP／MP／ST 对象是否随 WINDOW10 滑动未读，重制随 `Vitals` 一起滑。
- 商店手持散件点货表卖出已接（`TownRuntime.shop_sell_hand`，见 [original_shop_transaction](original_shop_transaction.md)）；手持移入右板时左板暂显狀態未做。

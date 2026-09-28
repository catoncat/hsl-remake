# 原版大地图与城镇画面：状态栏、系统卷轴、城镇根菜单、对白板位置、商店窗、整理裝備

> evidence: runtime-measured: 原版 v1.06（Wine、cnc-ddraw 640×480）大地图状态栏、系统卷轴、城镇根菜单、对白板上下位置、大地图网格线、商店窗构图与买卖手势、金钱不足消息、退店与离城、整理裝備三页、商店 裝備／倉庫 页与存取、换人后手持; negative-evidence: 城镇根画面上没有金钱显示（只有商店窗的金钱框）; static-derived: select 选择窗（0x4264a0／0x426680／0x4264f0）、tePlayerSelect [mode] 过滤（0x4557ad）与石纹菜单行（0x4561d0） · status: live · functions: 0x412680, 0x412760, 0x4264a0, 0x4264f0, 0x426680, 0x42c130, 0x4348f0, 0x4557ad, 0x4561d0 · tools: hsl_original_control.py, play_original.sh · updated: 2026-09-28

## 结论

- 原版进城不压暗大地图，TownBG 约在 (160,148)，石纹菜单板叠在其左上，菜单无「離開」项、画面无金钱／同伴栏，右键／Esc 离城；shape 台词在上、队员台词在下；商店窗是战后「獲得物品」窗的商店分支，買賣 钮暗着（runtime-measured；negative-evidence）。
- 重制 `game/world/TownRuntime.gd`、`TownShopScreen.gd`、`WorldMapRuntime.gd`、`BattleSystemMenu.gd` 按下表对齐；对白板上下分工由 [original_dialogue_board](../../static_reverse/original_dialogue_board.md) 的 `0x414220` 顶槽位静态确认（static-derived）。
- teSelectInsertEvent／tePlayerSelectInsertEvent 的选项不在石纹板上：原版建 BOARD02 选择窗放下槽，行距 28、FONT.24 白字、悬停脉冲绿，选人末行固定「離開」；重制照做（static-derived，见「select 选择窗」）。
- tePlayerSelect 的 `[mode]` 按队员记录 `+0x134` 的转职位筛名单：mode 1（儀式之間）只列未转职的，mode 2（神殿中樞）只列转过一次、未转第二次的；重制照做（static-derived，见「tePlayerSelect 名单过滤」）。
- 差异：不画红色 ↓（买入进手持再放下已照原版，[original_shop_transaction](../../static_reverse/original_shop_transaction.md)）；差异清单 `town-layout-extras`（provisional）。

## 证据

### runtime-measured：采集

- 2026-09-24 三趟原版（`tools/hsl_original_control.py` 单步输入并截 cnc-ddraw 画面）：帧 03／05／06 读回憶錄预设 `level06_pre_battle`（席達鎮，完成度 13%）；帧 01／02 与 04／07 读 兩栖族部落 附近的存档（完成度 31%），只读，结束后 `--restore` 恢复存档（sha1 核对）。
- 2026-09-24 另三趟 `level06_pre_battle`（席達鎮，金钱 70）：武器店与右键、护甲店与 Esc、道具店卖出／买入，得帧 08–14；存档 sha1 前后一致。
- 2026-09-27 一趟：「戰場記錄」进战斗 → 卷轴「讀取回憶錄」第 1 行（席達鎮，只读）→ 城镇 Esc 回大地图 → 卷轴「整理裝備」，得帧 15–17。
- 2026-09-27 另一趟：同一只读回憶錄进 席達鎮 道具店 → 拿起背包物按 下一位 → 裝備 页 → 倉庫 页放入两次、取出一次 → 离店 → 卷轴「整理裝備」倉庫页取出后按 下一位，得帧 18–24；存档 sha1 前后一致。
- 原始帧在仓库外 `ignored/original-control/`；入库帧压成 256 色。坐标为 640×480 帧上的目测近似值。带「重制画面」的链接是重制同一画面的截图，原版帧见私有档案。

### runtime-measured：大地图、城镇根菜单与对白板（帧 01–07）

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| [01-bigmap-status-bar.png（重制画面）](../../../screenshots/remake/world-map-status-bar.png)（原版帧见私有档案：`runtime_observations/original_world_town/01-bigmap-status-bar.png`） | 大地图 | 底部黑色状态栏：左黄字「完成度： 31%」、右白字时间「1:06:15」。地图不压暗；网格线、点（青＝城镇、橙＝战场）与红色路线画在底图上。 |
| [02-bigmap-system-menu.png（重制画面）](../../../screenshots/remake/world-system-scroll.png)（原版帧见私有档案：`runtime_observations/original_world_town/02-bigmap-system-menu.png`） | 大地图按 Esc | 石质卷轴居中，六项：整理装备／储存回忆录／读取回忆录／读取战场记录／设定选项／回主选单；状态栏仍可见。 |
| [重制 歐姆村 根菜单（重制画面）](../../../screenshots/remake/town-root-menu.png)（原版帧见私有档案：`runtime_observations/original_world_town/03-town-root-menu-sidazhen.png`） | 进 席達鎮 | 大地图不压暗、状态栏仍在。TownBG 约 (160,148)–(482,330)，金色细框；石纹菜单板约 (62,62)–(297,322)，叠在 TownBG 左上；左对齐白字：武器店／护甲店／道具店／酒馆；无「離開城鎮」项，无金钱或同伴栏。 |
| [重制 歐姆村 根菜单（同一构图）（重制画面）](../../../screenshots/remake/town-root-menu.png)（原版帧见私有档案：`runtime_observations/original_world_town/04-town-root-menu-amphibian-tribe.png`） | 进 兩栖族部落 | 同一构图，四项：武器店／护甲店／道具店／集会场。 |
| [05-shape-message-top.png（重制画面）](../../../screenshots/remake/dialogue-board-top.png)（原版帧见私有档案：`runtime_observations/original_world_town/05-shape-message-top.png`） | 席達鎮 入城事件 19，消息 912（teShapeMessage FACE0077） | 对白板在上方：头像框约 (16,22)–(132,160)，文字板约 (146,22)–(630,160)，首行名字（绿）后台词（白）；TownBG 留在原处。 |
| [06-player-message-bottom.png（重制画面）](../../../screenshots/remake/dialogue-board-bottom.png)（原版帧见私有档案：`runtime_observations/original_world_town/06-player-message-bottom.png`） | 席達鎮 酒馆事件 23，琥 的 tePlayerMessage | 对白板在下方：头像框约 (16,322)–(132,462)，文字板约 (146,322)–(630,462)；状态栏被盖住。 |
| [07-shopkeeper-message-top.png（重制画面）](../../../screenshots/remake/dialogue-board-top.png)（原版帧见私有档案：`runtime_observations/original_world_town/07-shopkeeper-message-top.png`） | 兩栖族部落 武器店（teShapeMessage） | 对白板在上方；该剧情状态下老板只说「你们还在干什麼？快逃命吧！」，不开商店。 |

- 网格线：帧 01 纯黑 (0,0,0)、1 px 竖线在 x＝160／360／560，横线在 y＝120／319，间距 200，与 BigMap.SHP 自带的黑色列（x＝200,400,…）和行（y≈199,401,…）相差镜头偏移；进城后仍在，只被城镇窗挡住；状态栏盖住 y≈432 以下。
- 帧 01 整体亮度约为 BigMap.SHP 的 0.58 倍（文字黄 (152,156,101)、白 (144,130,120)），帧 04 在镜头 (640,480) 与 BigMap.SHP 逐点吻合（平均差 2.2，文字 (248,252,136)／(248,252,248)）；状态栏混合与文字颜色以帧 03／04 为准。
- 对白板样本 7 句（事件 19、23 与一处武器店）：teShapeMessage 全在上方、tePlayerMessage 全在下方；静态规则见 [original_dialogue_board](../../static_reverse/original_dialogue_board.md)（`0x414220` 第 2 参置 `0x4000`，`0x4145f6–0x414618` 读它把框放到 y＋20）。

### runtime-measured：商店窗（帧 08–14）

三家店同一窗，即战后「獲得物品」窗（[original_getitem_window](../../static_reverse/original_getitem_window.md)，`0x414c00`）的商店分支：大地图不压暗、状态栏仍在；顶部成员条（WINDOW10）、左下背包板 (12,168)、右边货表板 (252,168)，板头写店名；左下 `$:` 金钱框 (20,442)。货表每行图标、名字、右对齐价格「$200」，价格字形右缘 x 594；所显示成员职业用不了的行名字与价格红字；部分行价格前有红色 ↓（闊刃劍、銀劍 有，水晶劍 没有）。底部六个 42×42 红框按钮中心 y 429，x 284／332／397／445／493／589：上一位／下一位／裝備／買賣／倉庫／丟棄，買賣 暗着、点击无反应。悬停物品时底部换成 WINDOW50 说明框：绿字「名字(可用职业…)」、效果行与「賣價$N」（N＝标价一半）。

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| [重制 歐姆村 武器店窗（重制画面）](../../../screenshots/remake/shop-window.png)（原版帧见私有档案：`runtime_observations/original_world_town/08-weapon-shop-window.png`） | 席達鎮 武器店招呼后开窗 | 上述构图；雷歐納德 的背包、红字行与 ↓、六个按钮与暗着的 買賣。 |
| [重制 武器店，背包里的 長劍 拿在手上（重制画面）](../../../screenshots/remake/shop-holding-bag-item.png)（原版帧见私有档案：`runtime_observations/original_world_town/09-item-shop-bag-item-picked-up.png`） | 道具店，点背包里的 回復藥 | 物品离格贴在鼠标上；金钱不变（70）。 |
| 10-item-shop-sold-hover-description.png（原版帧见私有档案：`runtime_observations/original_world_town/10-item-shop-sold-hover-description.png`） | 带着它点货表 | 卖出：金钱 70→120（半价 50）；悬停 銀製髮飾：「銀製髮飾(劍,弓,拳,賊,法,翼,獸,魔劍)」「防毒　賣價$200」。 |
| 11-item-shop-bought-in-hand.png（原版帧见私有档案：`runtime_observations/original_world_town/11-item-shop-bought-in-hand.png`） | 点货表的 回復藥 | 买入：金钱 120→20，物品贴在鼠标上，再点背包格才放入。 |
| 12-armor-shop-not-enough-gold.png（原版帧见私有档案：`runtime_observations/original_world_town/12-armor-shop-not-enough-gold.png`） | 护甲店，70 金点 布衣 | BOARD02 石板居中偏下（约 (75,320)–(564,465)），红字「抱歉, 您的金錢不足無法購買。」（消息 606）；点一下关掉。 |
| 13-shop-esc-farewell.png（原版帧见私有档案：`runtime_observations/original_world_town/13-shop-esc-farewell.png`） | 店里按 Esc（右键同样） | 商店窗关掉，回到老板上方对白板说告别话；再点回根菜单。 |
| [14-town-esc-back-to-map.png（重制画面）](../../../screenshots/remake/world-map-status-bar.png)（原版帧见私有档案：`runtime_observations/original_world_town/14-town-esc-back-to-map.png`） | 根菜单按 Esc（右键同样） | 城镇关掉回大地图；在大地图再按 Esc 才是系统卷轴。 |

### runtime-measured：整理裝備（帧 15–17）

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| 15-arrange-status-page.png（原版帧见私有档案：`runtime_observations/original_world_town/15-arrange-status-page.png`） | 卷轴选「整理裝備」 | 共用状态窗模式 0 开在「狀態」页：大地图不压暗、状态栏仍在；成员条同商店，左板 WINDOW21 九行属性（力量 51 黄字，其余白字），右板 WINDOW30 六个装备槽，左下 `$:` 框；底部七钮 上一位／下一位／倉庫／狀態／裝備／魔法／特殊技，狀態 画暗；无「離開」钮；与 [original_storage_window](../../static_reverse/original_storage_window.md)「模式 0 全貌」逐项相同。 |
| 16-arrange-equip-page.png（原版帧见私有档案：`runtime_observations/original_world_town/16-arrange-equip-page.png`） | 点「裝備」 | 左板换成背包（回復藥 一行红字，帧 17 同一件白字），右板不变；裝備 画暗、狀態 恢复。 |
| 17-arrange-storage-page.png（原版帧见私有档案：`runtime_observations/original_world_town/17-arrange-storage-page.png`） | 点「倉庫」 | 右板换成 WINDOW90「倉庫」列表（空，右缘上下箭头）；底部 上一位／下一位／丟棄（389）／使用（437）／裝備／魔法／特殊技，倉庫 与 狀態 消失；再右键窗关掉，回到仍开着的卷轴。 |

### runtime-measured：商店 裝備／倉庫 页与换人手持（帧 18–24）

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| 18-shop-next-member-hand-kept.png（原版帧见私有档案：`runtime_observations/original_world_town/18-shop-next-member-hand-kept.png`） | 道具店拿起背包里的 回復藥 后点 下一位 | 成员换成 緹娜，回復藥 仍在光标上；底部六钮 上一位／下一位／裝備／買賣／倉庫／丟棄，買賣 画暗。 |
| 19-shop-equip-page.png（原版帧见私有档案：`runtime_observations/original_world_town/19-shop-equip-page.png`） | 点「裝備」 | 右板从货表换成六个装备槽（与整理裝備同一块板），左板仍是背包；裝備 画暗，買賣 与 倉庫 常显。 |
| 20-shop-storage-put.png（原版帧见私有档案：`runtime_observations/original_world_town/20-shop-storage-put.png`） | 点「倉庫」，手持 回復藥 点列表 | 右板换成 WINDOW90「倉庫」，一行 回復藥 数量 1（数字右对齐）；手空。 |
| 21-shop-storage-stack2.png（原版帧见私有档案：`runtime_observations/original_world_town/21-shop-storage-stack2.png`） | 再放一瓶 | 同一行数量变 2，不另起一行；倉庫 画暗。 |
| 22-shop-storage-take.png（原版帧见私有档案：`runtime_observations/original_world_town/22-shop-storage-take.png`） | 空手点该行 | 一瓶到手上，行数量回到 1，下方出该物说明框。 |
| 23-arrange-storage-after-shop.png（原版帧见私有档案：`runtime_observations/original_world_town/23-arrange-storage-after-shop.png`） | 离店离城，卷轴「整理裝備」→ 倉庫 | 商店里放入的 回復藥 1 仍在列表里：商店 倉庫 与 整理裝備 倉庫 是同一份存储。 |
| 24-arrange-next-member-hand-kept.png（原版帧见私有档案：`runtime_observations/original_world_town/24-arrange-next-member-hand-kept.png`） | 从列表取出后点 下一位 | 成员换人，回復藥 仍在光标上，列表空。 |

### static-derived：石纹菜单行（`0x4561d0` 绘制分支，r2 反汇编 `hsl01.exe`，未执行）

城镇窗是对象 740 Town_Window（WINDOW70，defProcTownBOSS `0x4561d0`，见 [bigmap_performances](../../resource_inventory/bigmap_performances.md)）；根菜单与子菜单（`+0x80` 置 `0x4000` 时走 `0x454610` 子项表）都由它的绘制分支画，不另建行对象。

| 项 | 原版 | 地址 |
| --- | --- | --- |
| 字 | 最多 8 行、行距 32；FONT.24 经 `0x460884`，先画 `0x8430` 阴影于 (+1,+1)，再画字 | `0x4562b6`–`0x4562ec`、`0x456377`–`0x4563a5` |
| 悬停色 | 行号等于 `+0x9a`（鼠标所在行）时字色取 `0x42c130`（绿 255 − 2·\|p\|、红蓝 0，与选择窗同一计数），否则白 `0xffff`；阴影照画 | `0x4562f1`–`0x456317` |
| 点击 | 状态 `+0x8c` 为 4 且悬停行上点击（`0x4c6398` 位 `0x10000`）→ 状态 5、放 398 ACCEPT01 | `0x45630f`–`0x45636f` |

### static-derived：select 选择窗（`0x4264a0`／`0x426680`／`0x4264f0`，r2ghidra 反编译 `hsl01.exe`，未执行）

`0x454e20` case 0xf（teSelectInsertEvent）与 case 0x1e（tePlayerSelectInsertEvent）把选项消息 id 填进 `0x4c2940`、事件填进 `0x4c2900`，调 `0x4264a0(picture, 0, 0x4c2940, &0x4c1d54)`；`0x4264a0` 建对象 704，第 2 参为 0，不置 `0x4000`。对象 704／705 的定义在 global.obs，过程号经 PROCESS.DEF 查表 `0x477c2c`（resource-derived）。

| 项 | 原版 | 地址 |
| --- | --- | --- |
| 窗对象 | 704 Event_Select_Window：`SHAPE\BOARD02.SHP`（489×145，与对白板同一块），planeMenu4，defProcEventSelectWindow 69 → `0x426680` | global.obs |
| 窗位置 | y ＝ 镜头 y ＋ 320（下槽）；`0x4000` 时 ＋20，但两条 te 都不置。x：有 picture ＝ 镜头 x ＋ 144，picture 画在 (x − 132, y)；无 picture ＝ (640 − 宽)/2 ＝ 75 | `0x426680` |
| picture | teSelect：`[player id]` 在队时取 PLAYERS 行 `+600`（−1 视为无）；tePlayerSelect：`[shape]`，TOWNDEF 两处都传 −1 → 居中无头像 | case 0xf／0x1e |
| 行对象 | 705 Event_Select_String：planeMenu5，defProcEventSelectString 68 → `0x4264f0`；最多 10 行 | global.obs、`0x426680` |
| 行位置 | x ＝ 窗 ＋ 17；第 6–10 行 x ＝ 窗 ＋ 37 ＋ 行宽（第二列）；y ＝ 窗 ＋ 顶 ＋ 28·(i mod 5)，顶 17，行数 > 4 时 4；行宽 472，行数 > 5 时 226；行高 28 | `0x426680` |
| 字 | FONT.24（`[0x4c1ae0]`）；平时 `0x412760`：阴影 `0x8430` 画在 (+1,+1)、再白 `0xffff`；淡入淡出中 `0x413040` 按窗层级画 | `0x4264f0` |
| 悬停色 | 鼠标在行上（位 `0x2000000`）时再以 `0x412680` 用 `0x42c130` 色重画、不画阴影：绿 255 − 2·\|p\|、红蓝 0，p 每 tick −16..16（同特殊技页悬停） | `0x4265a4`–`0x4265d6` |
| 点击 | 窗层级满 16 且未选时，点击（位 `0x40000`）写行号、放 398 ACCEPT01；窗淡出 16 tick 后把行号交回 VM | `0x4265e2`–`0x42661a`、`0x426680` 状态 3 |
| 状态机 | `+0x8c` 四态：0 淡入，层级 `+0x28` 每 tick ＋1，到 16 进 1；1 只一 tick，结果 `+0xa4` 置 −1 进 2；2 活动，等行对象写入结果（行只在层级 16 且结果 −1 时读点击）后进 3；3 淡出，层级每 tick −1，到 0 把结果写进 `*[+0xac]`、销毁自己，脚本在此后才拿到行号。窗与行都按层级/16 画（`0x4607f9` 带层级） | `0x426872`–`0x42695a` |
| 取消 | 两个过程都不读 Esc／右键；tePlayerSelect 在队员行后固定追加 RESOURCE 312「離開」、事件 −1，选它结束本事件（VM 返回 1） | `0x455831`、`0x454e20` 阶段 0x1e |
| 对白板上下 | 与选择窗无关：`0x414220` 的 `0x4000` 只由 teShapeMessage／teCheckMoney 置（上，y 20），tePlayerMessage 不置（下，y 320） | [original_dialogue_board](../../static_reverse/original_dialogue_board.md) |

### static-derived：tePlayerSelect 名单过滤（`0x4557ad`–`0x455827`，r2 反汇编 `hsl01.exe`，未执行）

case 0x1e 逐个读 `[player][event]` 对，候选只有同时满足下列条件才写进选项表；记录地址 ＝ `[0x4c1bc8]` ＋ (player ＋ 1)·0x1fc。

| 项 | 原版 | 地址 |
| --- | --- | --- |
| 在队 | `0x42caa0(player)` 为 0 跳过 | `0x4557b7` |
| 行数上限 | 已写满 9 行后其余跳过，再追加「離開」 | `0x4557c3` |
| mode 1 | `+0x134 & 0xc0000000` 非 0 跳过：只列两位都没有的 | `0x4557fb` |
| mode 2 | `+0x134` 无 `0x80000000` 跳过、有 `0x40000000` 跳过：只列只有第一位的 | `0x4557e5`–`0x4557f7` |
| 其他 mode | 不筛 | `0x4557e3` |
| 位的写者 | `0x4348f0(code, flag)` 在 `0x434b40` 把 flag 或进 `+0x134`：teCheckJobUp（case 0x1f，`0x455a54`）与战斗脚本 actPlayerJobUpProcess（`0x450840` case 0x76，`0x45149d`）传 `0x80000000`；teCheckJobUp2（case 0x20，`0x455c89`）传 `0x40000000`；读档 `0x44c51b` 原样恢复 | `0x434b2c`–`0x434b48` |
| 两处调用 | TOWNDEF 事件 71 命運神殿 儀式之間：mode 1，候选 雷歐納德／緹娜／琥／漢克斯／雪拉／雷特／嚎／克羅蒂（→ 61–68 teCheckJobUp）；事件 87 命運神殿 受驗者：mode 2，候选 雷歐納德／緹娜（→ 69／70，其后 79／80 teCheckJobUp2） | `towndef.json` |

## 重制接线

| 项 | 重制 | 与原版 |
| --- | --- | --- |
| 大地图状态栏 | `WorldMapRuntime._build_status_bar`：(0,412) 整张减法混合；「完成度：」x 6、数字 x 114、时间右对齐 x 634，字行 y 427–444 | 同 |
| 大地图行走者 | 按战斗尺寸画；当前点、可达点、悬停点标名是重制补的 | 尺寸同；标名异（原版悬停是否显示未采） |
| 网格线、系统卷轴、进城底图 | BigMap.SHP 1:1 不压暗；`BattleSystemMenu` world 变体六项同名；进城不压暗 | 同 |
| TownBG、菜单 | TownBG (158,148)；WINDOW70.SHP (60,60) 叠在其上，白字行 x 72、行距 32；悬停行 `0x42c130` 脉冲绿、阴影照画 | 同 |
| 离城、金钱栏 | 右键／Esc 离城、退子菜单、取消选人；根画面无点名与金钱／同伴条 | 同 |
| 对白板 | `TownRuntime`：上 y 20、下 y 320；转职结果与获得金钱／物品的重制旁白放下方 | 同 |
| select 选择窗 | `TownRuntime._show_select_window`：BOARD02 下槽，有头像 x 144（头像 x 12）、无头像 x 75；行 +17、行距 28、行数 > 4 顶 4、> 5 分两列；FONT.24 白字＋阴影，悬停脉冲绿去阴影；点击放 ACCEPT01；选人名单由 `TownEventRules` 的 `listed` 给出（在队、mode 1／2 按 `job_up_flags` 的同两位、至多 9 行），末行「離開」；Esc／右键不取消；选择期间石纹板隐藏 | 同；淡入 16 tick 满级前不收点击、点选后淡出 16 tick 再交回（玩家点击路径；脚本直调 `choose` 仍立即交回）；选择期间石纹板是否仍在未核对 |
| 商店窗 | `TownShopScreen`：同一套 WINDOW10／20／90／40 板与六钮、价格右缘 x 594、悬停说明框、BOARD02 拒绝消息；红字按物品职业掩码 | 同；不画 ↓ |
| 卖出 | 手上物 → 货表，`WorldPartyRules.sell` 半价，重要物品拒卖 | 同 |
| 买入 | 空手点货行走 `TownRuntime.shop_pick`：扣钱、物品进手持，再点背包格放下，右键放回首空格 | 同，见 [original_shop_transaction](../../static_reverse/original_shop_transaction.md) §结论；拿起／放下／卖出音效照放 |
| 退店 | 右键／Esc 先关消息、再放回手上物、再退店；告别话照该店事件 te 脚本 | 同（告别话是否由退店触发未单独核对） |

城镇数据：菜单树与 te 事件 `content/imported/hsl/global/world_map/towndef.json`（解释器 `game/sim/TownEventRules.gd`），文字／头像／货表 `town_messages.json`／`town_portraits.json`／`town_shop_items.json`（`tools/hsltools/assets/town_assets.py`）；城镇交易只改 hand-off 的 carry（金币与各成员 8 格背包）。

## 复现

不可再生：原版侧唯一记录。重制侧对照 `tools/godot.sh --headless --script res://tests/run_town_scene_tests.gd`。

## 边界

- 商店只看了 席達鎮 三家店、一名成员：换人、商店里的 裝備／倉庫／丟棄、买入后放到别的成员背包、背包满与重要物品拒收（消息 607）无样本；背包格与货表行格位沿用战后窗静态坐标，未逐像素重测。
- 红色 ↓ 的含义未核对。
- 城镇根菜单项字体与菜单板纹理只看了截图，未核对资源文件；根／子菜单悬停色已照石纹菜单行 `0x4561d0` 用 `0x42c130` 脉冲绿、阴影照画（static-derived，lane TOWNMENU2，见 [original_world_town](../../static_reverse/original_world_town.md)）。
- select 选择窗与 tePlayerSelect 名单过滤只有静态读数，无原版实拍帧；重制的 `job_up_flags` 由城镇转职与 actPlayerJobUpProcess 写，未与原版存档 `+0x134` 逐位对照。
- 读存档那一趟在帧 07 后游戏失去前台（`game_not_foreground`），商店与离城由后续三趟补采。

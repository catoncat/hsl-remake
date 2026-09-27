# 原版大地图与城镇画面实录（lane R5-L6／R5-L6b）

> evidence: runtime-measured: 原版 v1.06（Wine、cnc-ddraw 640×480）大地图状态栏、系统卷轴、两个城镇的根菜单、对白板的上／下两种位置、大地图网格线；R5-L6b 起加上商店窗（武器店／护甲店／道具店）构图、买入与卖出手势、金钱不足消息、右键／Esc 退店与离城；PARTYEQUIP 起加上 整理裝備 窗（共用状态窗模式 0）的狀態／裝備／倉庫 三页与右键回卷轴; negative-evidence: 城镇根画面上没有金钱显示（只有商店窗的金钱框）; provisional: 由 7 帧归纳出的"teShapeMessage 在上、tePlayerMessage 在下" · status: record-only · tools: hsl_original_control.py, play_original.sh · updated: 2026-09-27

回答 [bigmap 演出盘点](../../resource_inventory/bigmap_performances.md)留下的问题"原版画面长什么样"：给出 17 帧原版画面（01–07 为 R5-L6，08–14 为 R5-L6b 的商店与离城，15–17 为 PARTYEQUIP 的整理裝備），与重制现行 `game/world/TownRuntime.gd`／`WorldMapRuntime.gd`／`BattleSystemMenu.gd` 对照。画面上的坐标都是在 640×480 帧上目测的近似值，不是从代码读出的。

## 怎么采的

- 2026-09-24 的三趟原版，走 `tools/hsl_original_control.py` 在 Wine 内单步输入并截取 cnc-ddraw 游戏画面。帧 03／05／06 来自 01:12–01:31 那趟，读 `tools/play_original.sh` 装入的回憶錄 预设 `level06_pre_battle`（席達鎮，完成度 13%、时间 4:0x）；帧 01／02（01:38）与 04／07（02:23–02:29）读的是用户自己的 回憶錄 第 3 行（兩栖族部落 附近的大地图，完成度 31%），只读，没有存档。每趟结束都用 `--restore` 把用户存档恢复原样（sha1 核对）。
- R5-L6b（2026-09-24 04:29–05:02）又走三趟有效的 `level06_pre_battle`（席達鎮，金钱 70）：04:29–04:40 武器店与右键、04:44–04:53 护甲店与 Esc、04:54–05:02 道具店的卖出／买入；04:41–04:43 那趟点进了战斗，约 2 分钟后关掉自己启动的进程，不入帧。每趟开走前核对存档 sha1，结束后四个存档 sha1 与开走前逐字相同；最后一趟退出时原版新建的 `HSL.CFG`（开走前不存在）移到仓库外备份目录，游戏目录恢复原状。
- lane PARTYEQUIP（2026-09-27 04:04–04:14）一趟：标题「戰場記錄」进战斗 → Esc 卷轴「讀取回憶錄」第 1 行（席達鎮，等級 08，只读）→ 城镇根菜单 Esc 回大地图 → Esc 卷轴「整理裝備」，得帧 15–17；结束时关掉自己启动的进程，四个存档修改时间未变、没有新建 `HSL.CFG`。
- 原始帧留在仓库外的 `ignored/original-control/`；入库的 17 帧压成 256 色。

## 看到什么

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| [01-bigmap-status-bar.png（重制画面）](../../../screenshots/remake/world-map-status-bar.png)（原版帧见私有档案：`runtime_observations/original_world_town/01-bigmap-status-bar.png`） | 大地图 | 底部一条黑色状态栏：左边黄字「完成度： 31%」、右边白字时间「1:06:15」。地图不压暗；网格线、点（青＝城镇、橙＝战场）与红色路线都画在底图上。 |
| [02-bigmap-system-menu.png（重制画面）](../../../screenshots/remake/world-system-scroll.png)（原版帧见私有档案：`runtime_observations/original_world_town/02-bigmap-system-menu.png`） | 在大地图按 Esc | 石质卷轴居中，六项：整理装备／储存回忆录／读取回忆录／读取战场记录／设定选项／回主选单。状态栏仍可见。 |
| [03-town-root-menu-sidazhen.png](03-town-root-menu-sidazhen.png) | 进 席達鎮 | 大地图原样留在底下（不压暗，状态栏仍在）。TownBG 窗约在 (160,148)–(482,330)，金色细框；菜单板是一块石纹板，约 (62,62)–(297,322)，**叠在 TownBG 左上**。菜单是左对齐白字：武器店／护甲店／道具店／酒馆。菜单里**没有**「離開城鎮」项，画面上**没有**金钱或同伴栏。 |
| [04-town-root-menu-amphibian-tribe.png](04-town-root-menu-amphibian-tribe.png) | 进 兩栖族部落 | 同一构图，四项：武器店／护甲店／道具店／集会场。 |
| [05-shape-message-top.png（重制画面）](../../../screenshots/remake/dialogue-board-top.png)（原版帧见私有档案：`runtime_observations/original_world_town/05-shape-message-top.png`） | 席達鎮 入城事件 19，消息 912（teShapeMessage FACE0077） | 对白板在**上方**：头像框约 (16,22)–(132,160)，文字板约 (146,22)–(630,160)，第一行是名字（绿），后面是台词（白）。TownBG 窗留在原处。 |
| [06-player-message-bottom.png（重制画面）](../../../screenshots/remake/dialogue-board-bottom.png)（原版帧见私有档案：`runtime_observations/original_world_town/06-player-message-bottom.png`） | 席達鎮 酒馆事件 23，琥 的 tePlayerMessage | 对白板在**下方**：头像框约 (16,322)–(132,462)，文字板约 (146,322)–(630,462)；状态栏被盖住。 |
| [07-shopkeeper-message-top.png（重制画面）](../../../screenshots/remake/dialogue-board-top.png)（原版帧见私有档案：`runtime_observations/original_world_town/07-shopkeeper-message-top.png`） | 兩栖族部落 武器店（teShapeMessage，武器店老板） | 对白板在上方；这时的剧情状态下老板只说「你们还在干什麼？快逃命吧！」，没有打开商店。 |

**大地图黑色网格线（R5-L5 转来的问题 B）。** 原版屏幕上**看得见**这些线，没有被别的东西盖住：帧 01 里纯黑 (0,0,0)、1 像素宽的竖线在屏幕 x＝160／360／560，横线在 y＝120／319，间距 200，与 BigMap.SHP 自带的黑色列（x＝200,400,…）和行（y≈199,401,…）对得上（相差的是镜头偏移）。帧 03／04 进城后线仍在大地图上，只被城镇窗和菜单板挡住；底部状态栏盖住 y≈432 以下。逐像素统计来自仓库外的原始帧（入库帧已压色，但黑色保持 0）。

**帧 01 整体偏暗（R5-L5b 对照）。** 帧 04 的大地图与 BigMap.SHP 在镜头 (640,480) 逐点吻合（平均差 2.2），同一镜头的帧 01 各处亮度只有 BigMap.SHP 的约 0.58 倍，文字也一样偏暗（黄 (152,156,101)、白 (144,130,120)，帧 03／04 为 (248,252,136)／(248,252,248)）——像是读档后的淡入途中，不是常态；状态栏混合与文字颜色因此以帧 03／04 为准。

**对白板位置的归纳（provisional）。** 本次看到的 teShapeMessage（NPC 头像、FACE*.SHP，包括 912 这句 緹娜 披斗篷的头像）都在上方，tePlayerMessage（队伍成员）都在下方；样本共 7 句，来自事件 19、23 与一处武器店。TOWNDEF 的这两个指令本身没有位置参数（`towndef.json` 的 `token_signatures`：teShapeMessage 的参数是 `[shape file][name][message id][if_wait]`），位置由哪段代码决定尚未定位；要升级为规则需要找到对白板的摆放函数，或采到反例。静态线索（lane TOWNMAP，r2ghidra 读 `0x454e20`）：两条指令建消息后都调 `0x414220(msg, 位, if_wait, 头像)`，teShapeMessage（case 7 → `0x45560f`）第 2 参为 1、tePlayerMessage（case 5 → `0x455da9`）为 0；`0x414220` 按第 2 参给消息对象 `+0x80` 置 `0x4000`、按 if_wait 置 `0x2000`、有头像置 `0x1000`——上下之分只能来自这一位，但读 `0x4000` 的摆放代码仍未读。

**商店窗（R5-L6b，帧 08–12）。** 三家店是同一个窗，也就是战后「獲得物品」窗（[原作获得物品窗](../../static_reverse/original_getitem_window.md)，`0x414c00`）的商店分支：大地图不压暗、状态栏仍在，顶部成员条（WINDOW10，与战后窗同位置）、左下背包板 (12,168)、右边货表板 (252,168)——板头写店名（武器店／护甲店／道具店）而不是战后窗的「獲得物品」，左下 `$:` 金钱框 (20,442)。货表每行一件：图标、名字、右对齐价格「$200」，价格字形右缘在 x 594（五行、两家店逐像素一致）；所显示成员的职业用不了的行（雷歐納德 看 鋼斧／長槍）名字与价格都是红字；部分行在价格前有红色 ↓（闊刃劍、銀劍 有，水晶劍 没有；含义本次未核对）。底部六个 42×42 红框按钮的中心在 y 429，x 284／332／397／445／493／589，字幕是 上一位／下一位／裝備／買賣／倉庫／丟棄——与战后窗同一排按钮，**買賣 暗着**，点它没有反应（帧 08、12、道具店同样）。鼠标停在物品上时，底部按钮区换成 WINDOW50 说明框：第一行绿字「名字(可用职业…)」或「名字」，其后是效果行与「賣價$N」（N＝标价一半：回復藥 标价 100、说明写 賣價$50，卖出实得 +50）。

| 帧 | 画面 | 读到的事实 |
| --- | --- | --- |
| [08-weapon-shop-window.png](08-weapon-shop-window.png) | 席達鎮 武器店老板招呼后开窗 | 上述构图；雷歐納德 的背包、红字行与 ↓、六个按钮与暗着的 買賣。 |
| [09-item-shop-bag-item-picked-up.png](09-item-shop-bag-item-picked-up.png) | 道具店，点背包里的 回復藥 | 物品离开格子、贴在鼠标上（手上物）；金钱不变（70）。 |
| [10-item-shop-sold-hover-description.png](10-item-shop-sold-hover-description.png) | 带着它点货表 | 卖出：物品消失，金钱 70→120（半价 50）；鼠标停在 銀製髮飾 上，说明框「銀製髮飾(劍,弓,拳,賊,法,翼,獸,魔劍)」「防毒　賣價$200」。 |
| [11-item-shop-bought-in-hand.png](11-item-shop-bought-in-hand.png) | 点货表的 回復藥 | 买入：金钱 120→20，买到的 回復藥 贴在鼠标上，要再点背包格才放进去（下一次点背包第 1 格即放入）。 |
| [12-armor-shop-not-enough-gold.png](12-armor-shop-not-enough-gold.png) | 护甲店，70 金点 布衣 | BOARD02 石板居中偏下（约 (75,320)–(564,465)），红字「抱歉, 您的金錢不足無法購買。」（消息 606）；点一下关掉。 |
| [13-shop-esc-farewell.png](13-shop-esc-farewell.png) | 店里按 Esc（右键同样，04:38 那趟） | 商店窗关掉，回到老板的上方对白板，说告别话；再点一下回根菜单。 |
| [14-town-esc-back-to-map.png（重制画面）](../../../screenshots/remake/world-map-status-bar.png)（原版帧见私有档案：`runtime_observations/original_world_town/14-town-esc-back-to-map.png`） | 根菜单按 Esc（右键同样，04:39 那趟） | 城镇关掉，回到大地图；根菜单上没有「離開」项，右键／Esc 就是离城的方式。在大地图再按 Esc 才是系统卷轴（帧 02）。 |
| [15-arrange-status-page.png](15-arrange-status-page.png) | 大地图卷轴选「整理裝備」 | 共用状态窗模式 0 开在「狀態」页：大地图不压暗、状态栏仍在；上方同商店的成员条，左板 WINDOW21 九行属性（力量 51 是黄字，其余白字），右板 WINDOW30 六个装备槽，左下 `$:` 框。底部七钮：上一位／下一位／倉庫／狀態／裝備／魔法／特殊技，**狀態 画暗**（当前页）；没有「離開」钮。与[原作仓库窗](../../static_reverse/original_storage_window.md)「模式 0 全貌」的读法逐项相同。 |
| [16-arrange-equip-page.png](16-arrange-equip-page.png) | 点「裝備」 | 左板换成背包（回復藥 一行，**红字**——同一件在帧 17 是白字），右板不变；**裝備 画暗**、狀態 恢复亮。 |
| [17-arrange-storage-page.png](17-arrange-storage-page.png) | 点「倉庫」 | 右板换成 WINDOW90「倉庫」列表（空，右缘上下箭头）；底部变成 上一位／下一位／丟棄（389）／使用（437）／裝備／魔法／特殊技——倉庫 与 狀態 消失。再右键：窗关掉，回到大地图卷轴（卷轴仍开着）。 |

## 与重制对照

| 项 | 原版（本包） | 重制现行 | 同／异 |
| --- | --- | --- | --- |
| 大地图状态栏 | 底部，完成度＋时间；STATUS_BAR.SHP 从底图减去（不是贴一块灰条）；黄字 @5、白字 @1 各带阴影 | `WorldMapRuntime._build_status_bar`（R5-L5b 起）：(0,412) 整张减法混合；「完成度：」x 6、数字 x 114、时间右对齐 x 634，字行 y 427–444 | 同（R5-L5b 逐像素对照后修正） |
| 大地图行走者 | 帧 01 的队伍行走者约 42 px 高（战斗人物原尺寸），地图上没有点名文字 | lane TOWNMAP 起按战斗尺寸画（原先半尺寸）；点名文字（当前点、可达点、悬停点）仍是重制补的 | 尺寸同；点名异（原版悬停时是否显示点名未采） |
| 大地图网格线 | BigMap.SHP 自带的黑线直接显示 | 同一张 BigMap.SHP 1:1 不压暗显示，黑线可见（`run_world_map_tests` 检查） | 同 |
| 大地图系统卷轴 | Esc 打开，六项 | `BattleSystemMenu` world 变体（Title051），六项同名 | 同 |
| 进城时的底图 | 大地图不压暗，状态栏可见 | R5-L5b 起不压暗 | 同 |
| TownBG 位置 | 约 (160,148)，屏幕中部偏右 | (158,148)（模板匹配本包帧 03／04） | 同 |
| 菜单 | 左上石纹板、叠在 TownBG 上，左对齐白字 | WINDOW70.SHP（匹配在 (60,60)）叠在 TownBG 上，白字行 x 72、行距 32 | 同 |
| 「離開城鎮」 | 菜单里没有这一项；右键或 Esc 离城（帧 14） | 右键／Esc 离城（R5-L6b 起）；lane TOWNMAP 起去掉重制补的 離開城鎮／返回／取消 按钮，子菜单与选人同样右键／Esc 退出 | 同 |
| 金钱／同伴栏 | 城镇根画面上没有 | lane TOWNMAP 起去掉点名与金錢／同伴条（金钱只在商店窗 `$:` 框） | 同 |
| 对白板 | teShapeMessage 在上，tePlayerMessage 在下 | 同（TownRuntime：上 y 20、下 y 320；上下分工 provisional） | 同 |
| 商店窗构图 | 战后「獲得物品」窗的商店分支，帧 08–12 | `TownShopScreen`（R5-L6b 起）：同一套 WINDOW10／20／90／40 板与六个按钮、货表行与价格右缘 x 594、悬停说明框、BOARD02 拒绝消息（`run_town_scene_tests` 检查坐标） | 同（红字行按战后窗同一规则：物品职业掩码不含成员职业）；重制的 裝備／倉庫／丟棄 暗着（原版在商店里做什么未采），不画 ↓；lane TOWNMAP 起去掉重制加在 x 541 的 離開 按钮（右键／Esc 退店）。六个按钮的中心与 `0x42ab40` 模式 1 的建钮参数逐个相同（y `0x1ad`＝429，x 284／332／397／445／493／589，见[原作仓库窗](../../static_reverse/original_storage_window.md)） |
| 卖出 | 拿起背包物、点货表，半价入账 | 同一手势（`TownShopScreen` 手上物 → 货表），`WorldPartyRules.sell` 半价 | 同 |
| 买入 | 点货行扣钱，物品到手上，再放进背包格 | 点货行扣钱，直接放进所显示成员的首个空格 | 异（重制交互改写，见[原作商店交易](../../static_reverse/original_shop_transaction.md)边界） |
| 退店 | 右键／Esc 退店，老板说告别话（帧 13） | 右键／Esc 先关消息、再放回手上物、再退店；告别话照该店事件的 te 脚本播放 | 同（告别话是否由退店触发未单独核对） |

## 边界

- R5-L6 读用户存档那一趟在第 7 帧后游戏失去前台（`game_not_foreground`），为了不和用户抢鼠标就停了；商店与离城由 R5-L6b 补采（帧 08–14）。
- 商店只看了 席達鎮 三家店、一名成员（雷歐納德）：上一位／下一位 换人、裝備／倉庫／丟棄 在商店里的行为、买入后手上物放到别的成员背包、背包满与重要物品拒收（消息 607）都没有样本；背包格与货表行的精确格位沿用战后窗的静态坐标，没有逐像素重测。
- 城镇菜单项的字体与颜色、菜单板纹理只看了截图，没有核对资源文件。
- 本包只记录原版画面；重制要不要改构图属于表现合同的决定，交负责人。

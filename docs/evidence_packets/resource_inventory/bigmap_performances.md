# 原版大地图上的剧情演出盘点

> evidence: resource-derived; negative-evidence: 无 STORY／WINFAIL 关卡以大地图为底图; provisional: 原版画面构图待 runtime 实录 · status: record-only · tools: hsltools/checks/source_map_binding.py, hsltools/data/big_map_flow.py · updated: 2026-09-27

本包只盘点**原版数据里**在大地图（level 49）上发生的对白／走位／演出，并逐条对照重制现在的处理。原版画面构图（城镇窗、对白板、状态栏）见[原版大地图与城镇画面实录](../runtime_observations/original_world_town/README.md)（runtime-measured）。

## 结论

**原版大地图上的对白全部来自城镇事件（TOWNDEF te 事件），不是另开一个剧情关**：没有任何 STORY／WINFAIL 关卡把大地图当底图（negative-evidence，见下），而大地图关 level 49 自己的对象表里就带着对白板和城镇窗。所以“大地图上的剧情”分三类：
1. **入城事件**：进城时自动播的队伍对白，共 12 条；**出城事件** 1 条，是沙羅尼亞“第一次離開”，琥喊住众人后接 8 句会合对白，然后进 STORY072。
2. **城镇菜单里的对白**：191 条 TOWNDEF 事件，其中 180 条有台词。
3. **不带台词的演出**：脚本自动行走 7 处，行走者换成琥 2 处，路线揭示 11 处。

重制**全部都有数据和解释器，且都能玩到**，因为触发它们的关卡都已注册。差别在两处：
- **画面构图是重制自拟的**：全屏压暗的大地图上叠加 TownBG、右侧菜单和下方对白板。
- **行走者换人没有接**：`actSetBMWalkerPlayerID` 只做了记录，地图上一直画雷歐納德。

## 依据（resource-derived）

- **没有别的关卡以大地图为底图**：各关 `OBJ-NNN.OBS` 中 `defProcIconBG` 地图管理员记录的 `obj_Shape_Name` 决定该关底图，[原地图绑定](../static_reverse/original_map_binding.md)已核对全部 154 个。153 个指向 `SHAPEnn\LEVELnn.SHP`，唯一例外 level 49 是 `SHAPE\ICONRECT.SHP` 控制器；没有任何一关指向 `SHAPE99\BIGMAP.SHP`。用 `tools/hsltools/sources/pak.py` 重扫全部 `obj-*.obs`，结果相同。无图剧情关（60–64、66–71 等）借用的是 LEVEL55／58 营地和王座厅，不是大地图。level 66（STORY065 之后五人对白）就是 LEVEL55 夜营，不在大地图上（`hsltools/levels/seed.py` 的 `MAP_ALIASES[66]`）。
- **对白板和城镇窗属于大地图关**：`obj-049.OBS` 除点、路线外的 48 个对象里有下面这些。`TownBG` 不在这张对象表里，由城镇过程动态载入，这是推测，要看实录。

| 对象 | 形状 | 过程 | 大小 |
| --- | --- | --- | --- |
| obj 5 `MessageBox` | `SHAPE\BOARD02.SHP` | `defProcMessageBox` | |
| obj 740 `Town_Window` | `SHAPE\WINDOW70.SHP` | `defProcTownBOSS` | 238×264 |
| obj 12 `Status Bar` | `SHAPE99\STATUS_BAR.SHP` | | 640×51 |
| obj 711–716 `BM_Window_*`／`Status_Window_*` | `WINDOW10/20/30/40/50/90` | | |
| obj 717–719 `Bar_HP／MP／ST` | | | |
| obj 724–735 按钮 | BCMD 系列 | | |

  按钮依次为：上一个、物品、魔法、特技、屬性、下一个、丟棄、倉庫、離開、使用、裝備、買賣。
- **触发写入**：STORY／WINFAIL 的 act* 写入来自 [big_map_flow.json](../../../content/generated/hsl/static/hsl01/big_map_flow.json)，TOWNDEF te* 写入来自 [towndef.json](../../../content/imported/hsl/global/world_map/towndef.json)，二转城镇写入来自 [town_job_up_writes.json](../../../content/world/town_job_up_writes.json)，台词来自 `town_messages.json`。

## 盘点表

“重制处理”一栏的实现入口：
- 入城、出城事件：`TownRuntime.open`／`leave`，由 `WorldScriptActions` 施加脚本写入；
- 行走：`WorldMapRuntime._consume_pending_walk`；
- 揭示：`_consume_show_track_points`；
- 解释器：`game/sim/TownEventRules.gd`。

“可达”指触发关卡已在 `content/battles/campaign.json` 注册。

### A. 入城／出城事件（进城或离城时自动播的对白）

| # | 城镇（点） | 事件 | 谁在何时布置 | 演出内容 | 重制处理 |
| --- | --- | --- | --- | --- | --- |
| A1 | 歐姆村（1） | 9 歐姆村未完成 | WINFAIL001 胜利 | 村民 656「盜賊解決了嗎？」／雷歐納德「別急嘛！」，共 4 句 | 已有，城镇画面里播；可达 |
| A2 | 歐姆村（1） | 10→11 歐姆村完成（二） | STORY061 | 村民致谢＋teGetGold；10 共 4 句，11 共 1 句，然后清除 | 已有；可达 |
| A3 | 席達鎮（6） | 19 席達鎮未完成 | WINFAIL005 胜利 | 琥「不好！到處都是沃斯菲塔的士兵。」等 7 句，然后清除 | 已有；可达 |
| A4 | 席達鎮（6） | 25 席達鎮事件後 | WINFAIL901 胜利 | 雷歐納德「我們到酒館打聽一下…」，1 句 | 已有；可达 |
| A5 | 薛維斯港（11） | 32 第一次到薛維斯港 | TOWNDEF 30（席達鎮酒館女客人二） | 緹娜「到了，就是這裡了。」等 5 句；布置 命運神殿 53 | 已有；可达 |
| A6 | 薛維斯港（11） | 152 回到港口清除路線 | TOWNDEF 138（船长选一） | 无台词，只把路线 10／11／12 的显示模式改回 | 已有；可达 |
| A7 | 命運神殿（16） | 53 命運神殿第一次進入 | TOWNDEF 32 | 神官 1283「請問你們是來接受稱號的嗎？」等 6 句，接着 teExecEvent 54 | 已有；可达 |
| A8 | 瑪哈亞鎮（23） | 88 第一次進入瑪哈亞鎮 | WINFAIL021 胜利 | 雷特「呼，到這裡種算可以鬆一口氣了。」等 7 句 | 已有；可达 |
| A9 | 兩棲族部落（14） | 141 第一次進入 | WINFAIL012 胜利 | 緹娜「這裡就是兩棲族生活的地方？…」等 6 句 | 已有；可达 |
| A10 | 兩棲族部落（14） | 153 事件後第一次進入 | 0x434680 二转城镇写入 | 雷歐納德「…地都裂開了？…」／緹娜「火山灰…」，3 句 | 已有；可达 |
| A11 | 沙羅尼亞（35） | 157 第一次進入 | WINFAIL034 胜利 | 雷歐納德「總算到了…」等 2 句 | 已有；可达 |
| A12 | 斐達克（42） | 168 第一次進入 | WINFAIL073 event 段 | 雷歐納德「這裡就是沃斯菲塔的首都了…」，1 句 | 已有；可达 |
| A13 | 亞雷比斯（27） | 185 第一次進入 | WINFAIL026 胜利 | 雷歐納德「這裡就是妖精隱居的地方？…」／雪拉「小雷~~~」等 5 句 | 已有；可达 |
| A14 | 沙羅尼亞（35） | **出城** 166→167 | WINFAIL034 胜利，`actSetTownExitExecEvent` | 离城时琥「喂！雷........我們在這裡!!」，接 167 会合 8 句，然后 teSetNextPlayLevelEvent 35,72 进 STORY072 | 已有：`leave()` 先跑出城事件；可达 |

### B. 城镇菜单事件

TOWNDEF 共 191 条事件，180 条带 teShapeMessage 或 tePlayerMessage，合计 269＋184 句。它们包括商店招呼、酒館 NPC、神殿转职、神秘商人、港口船长等，都在城镇菜单里触发。

其中 6 条会把玩家带离城镇：
- 23：席達鎮士兵，进第 6 关；
- 51：船去命運神殿，大地图站到点 16；
- 74：从神殿回薛維斯港；
- 151：兩棲族人類学者，进第 13 关；
- 167：沙羅尼亞会合，进 STORY072；
- 178：斐達克旅館，进 STORY074。

重制处理：同一解释器全部可跑，`town_scene` 回执覆盖了 14 长对白、23 关城进关等。原版在哪里画菜单和对白，见 runtime 实录。

### C. 大地图上不带台词的演出

| # | 类型 | 来源 | 内容 | 重制处理 |
| --- | --- | --- | --- | --- |
| C1 | 自动行走 | WINFAIL030 胜利 | 队伍自动 30→31 | 已有：`pending_walk`，有路线就走，否则瞬移；可达 |
| C2 | 自动行走 | WINFAIL033 胜利 | 31→32 | 已有 |
| C3 | 自动行走 | WINFAIL032 胜利 | 33→34 | 已有 |
| C4 | 自动行走 | WINFAIL034 胜利 | 32→35，先揭示点 34 的路线 | 已有 |
| C5 | 自动行走 | STORY071 | 30→33，先揭示点 30 | 已有 |
| C6 | 船行 | TOWNDEF 138（薛維斯港船长选一） | 队伍走 11→12 巴瀚納海峽；布置 152 | 已有 |
| C7 | 船行 | TOWNDEF 183（戈黎塔尼港船员选一） | 揭示后走 25→26 | 已有 |
| C8 | **行走者换人** | WINFAIL032 胜利、STORY071 | `actSetBMWalkerPlayerID SID_琥`：大地图小人改成琥（雷歐納德离队段落） | **缺失**：`TownEventRules.RECORDED_ONLY_TOKENS` 只记录，`WorldMapRuntime._spawn_marker` 固定画 001 |
| C9 | 路线揭示 | STORY061（2）、STORY071（30）、WINFAIL034（34）；TOWNDEF 30、43、97、164、175、183、188、190 | `act／teBMSetShowTrackPoint`：以该点为端点的路线进入揭示动画 | 已有：进图和关城时消费；揭示时长为重制值（见 [world_map_scene](../static_reverse/original_world_town.md)） |

## 不支持的结论

- 本表证明**原版数据里有哪些**大地图演出、由谁触发；不证明原版的画面构图、对白板位置、是否先显示城镇窗再播入城对白、以及每句的等待方式（TOWNDEF 每句 if_wait 都是 0）。这些由 runtime 实录回答，实录没有覆盖的仍属未知。
- `obj-049.OBS` 的对象清单只证明这些窗口属于大地图关，不证明它们同时出现，也不证明坐标。
- “重制可达”只说明触发关卡已注册，不说明整条战役路线已自然走通。

## 缺口的接线方案（未实现）

- **C8 行走者换人**：把 `actSetBMWalkerPlayerID` 的 SID 写进 world state，比如 `walker_actor_id`；`_spawn_marker` 用它代替固定 001。`actor_id` 用 EXTRAS 的 SID→001..009 映射。改动约 20 行，属 `game/world` 的规则接线。什么时候换回雷歐納德，要查后续脚本有没有再次调用 `actSetBMWalkerPlayerID SID_雷歐納德`：盘点里只有两处都是 SID_琥，**换回的时机未知**，需要原版证据。
- **构图**：按 runtime 实录重排 `TownRuntime` 的菜单、对白板和 TownBG 位置。

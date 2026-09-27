# 世界地图与城镇：初始化、bigmap 三字段、到达分支、路线揭示与 te 条件

> evidence: static-derived; resource-derived; negative-evidence: 独立默认 level 表、路线红白插值、买卖 handler 执行回执 · status: live · functions: 0x426b70, 0x426bb0, 0x426bf0, 0x426c70, 0x426ce0, 0x426e40, 0x427070, 0x427200, 0x427420, 0x427df0, 0x4280d0, 0x42c1c0, 0x42cc10, 0x42d090, 0x44e0e0, 0x454650, 0x4546c0, 0x454a20, 0x454ae0, 0x454cd0, 0x454db0, 0x454e20, 0x4606a9 · tools: hsltools/data/world_map.py, hsltools/probes/world_town.py · updated: 2026-09-27

## 结论

- 原版城镇菜单是 `0x454a20` 按 town id 建立的可变 100×264 字节记录，新游戏只有歐姆村／米蘭多／席達鎮有初始树；bigmap 点与路线各有展示阶段、类型位、可变 event 三个独立字段；到达按当前 event 与类型分支，没有独立默认 level 表（static-derived，原指令有界执行；negative-evidence）。
- 重制 `game/world/WorldMapRuntime.gd`、`WorldMapRules.gd`、`TownRuntime.gd` 与 `game/sim/TownEventRules.gd` 按这些字段、新游戏隐藏点线、到达分支、M_PNT 三帧、命中框 ±16、状态栏与揭示排序实现（static-derived 输入）。
- 点自己所在的点：点对象过程 `0x427df0` 不比当前点，只写点击目标；行走者子状态 3 找不到自身路线后，仅 event 非 0 且带 Town 位时进城，Battle／General（及 event 0）清掉点击、不分派到达，不会重打该点关卡；重制 `select_point` 当前点分支照此（static-derived）。
- 差异：旅行速度、揭示触发外的时钟、遭遇抽样比较方向、镜头滑行步长为重制值；差异清单 `town-event-timing`、`town-layout-extras`（provisional）。

## 证据

### static-derived：城镇归属与初始树

`0x454ae0` 将 `0x4c1d74` 指向的 100×264 字节清零后完整调用 `0x454a20`，按 town id 逐项建树。每城 8 个根槽，每根存根 event code 加 7 个子项，尾部两个 DWORD 为入城／离城事件覆盖（重置后为 0）；`0x454650` 查询地址 `town*264 + root_slot*32 + child_slot*4`。两次完整初始化结果相同（名称／id 来自 `extras.h`）：

| town id | 城镇 | 初始根节点 | 初始子项 |
| --- | --- | --- | --- |
| 1 | 歐姆村 | 1, 2, 3 | 无 |
| 4 | 米蘭多 | 4, 5, 6, 7 | 7 → 8, 12, 13, 14 |
| 6 | 席達鎮 | 16, 17, 18, 20 | 20 → 21, 22, 23 |
| 9／11／14／16／23／25／27／35／42 | 曼多力亞／薛維斯港／兩棲族部落／命運神殿／瑪哈亞鎮／戈黎塔尼港／亞雷比斯／沙羅尼亞／斐達克 | 空 | 空 |

其余 88 个槽位也为空。`TOWNDEF.TXT` 是 event 定义，不含永久城镇归属；段尾注释与 event 编号邻近不能作初始菜单来源。`teCreateSubEventMenu`（10）在 `0x454e20` 返回 2 并保存后续程序位置，不重跑初始树。

### static-derived：bigmap.dat 三个字段

原文件 5600 字节：100×40 字节点记录＋100×16 字节路线记录，45 个点、44 条路线非空；运行时点数组 `0x4c4a20`、路线数组 `0x4c43c0`。

| 字段 | 用途 | 入口 |
| --- | --- | --- |
| 点、路线 `+0` | 展示阶段：0 不显示、1 揭示中、2 稳定显示 | `0x426b70`／`0x426bb0`／`0x426bf0`；点 `0x427df0`、路线 `0x4280d0` |
| `+4` | Hidden `0x08000000`、Visit `0x10000000`、Town `0x20000000`、General `0x40000000`、Battle `0x80000000` | 类型替换 `0x426c70`、到达 `0x427ab3..0x427b95` |
| 点 `+8` | 可变事件值；45 个非空点初值等于点号 | getter `0x426ce0`、setter `0x426c70` |

普通 setter 在 Hidden 时不改值、不把 mode2 降回；强制 setter `0x426bf0` 可替换 mode2 但仍受 Hidden 限制。`0x426c70(point,event,flags)`：event=-1 保留原值；flags 非零先清 Visit，含类型位时清旧类型再 OR；flags=0 不动 Visit／类型。

新游戏 `0x42c86e..0x42ca2a` 将点 1 设 mode2，并 OR Hidden：点 11–16、22、25–28、31–34、38、43；路线 10–14、20、23–26、29–34、37、43。

### static-derived：到达

`0x427ab3` 先读目的点当前 `+8` 再读类型；General 判断在 Battle 之前；关卡请求走 `0x42cc10`（探针止于 `0x427b3e`）。

| 当前记录 | 原分支 |
| --- | --- |
| event=0 | 不请求关卡／城镇 |
| General，未 Visit | 用当前 event 请求关卡 |
| General，已 Visit | 先过 encounter ratio 与 1..100 抽样，再在 event 上加 0..2 |
| Battle | 未访问用 event；已访问加 0..2，不走 encounter 检查 |
| Town | 仅当它是选定目的点时写城镇 id、进 phase15、标 Visit；路过不进城 |

点自己所在的点（不经 `0x427ab3`）：点对象过程 `0x427df0` 在 `0x427ffc` 见按下位 `0x40000`、点击目标 `0x4c1ab8` 为 −1 且 `0x4c1b00` 无 `0x40000000` 时放音并把本点号写 `0x4c1ab8`，不比较当前点 `0x4c1ba4`。行走者 `0x427420` 子状态 3 先调 `0x427070(当前,目标)`，同点在 `0x42708a` 直接返回 0（无路线），随后：

| 当前点类型 | 原分支 |
| --- | --- |
| Town，event 非 0 | `0x42779c` 读 event（`0x426ce0`）与类型（`0x426e00`），`0x4277c5` 把 event 写城镇 id `0x4c59c4`、进子状态 15、`0x4277e0` 标 Visit——重新进城 |
| Town 且 event 0、Battle、General | `0x4277b4`／`0x4277bf` 跳 `0x4276fd`：`0x4c1ab8` 清 −1，不分派到达、不请求关卡、不抽遭遇 |

negative-evidence：raw load→`+8` setter/getter→到达路径中没有第二张缺省 level 表。

### static-derived＋resource-derived：大地图对象、行走、状态栏

`PROCESS.DEF` 与表 `0x477c2c` 把 point32／track33／walker35／statusbar51 连到 `0x427df0`、`0x4280d0`、`0x427420`、`0x427230`；45 点、44 路线与 OBS／EVEF／SHP 的 join 在回执 `object_sources`（resource-derived）。

| 项 | 结论 | 边界 |
| --- | --- | --- |
| `m_pnt` | 45 个点都以 `M_PNT001.SHP` 起始、`obj_Shape_Number=3`；`POINT.H` Battle0／General1／Town2 经 `0x427f0d` 加到基础 frame | 动态 bmpm 类型与 OBS 视觉类型分开 |
| 点命中区 | 相对 `[-16,-16,16,16]` | 按下／放开与重叠优先级未执行 |
| `m_trk` 落点 | 顶左 = level049 EVEF 锚点 − SHP draw origin；第 1 条锚点 (910,527)、origin (51,60)、53×61 | — |
| 路线 mode1 | 子状态 0 置裁剪位 `[obj] \|= 0x1000000`、半边 `+0x94 = 0`，计数 `+0x90 = max(\|w−ox\|, \|ox\|, \|h−oy\|, \|oy\|)`（`0x4606a9` 取 shape 宽高与 origin）；子状态 1 每 tick 半边 +1、计数 −1，到 0 设 mode2、清裁剪位、两端点 `0x426b70(point,1)`、`[0x4c1abc]+0x88` 减一；每 tick 尾 `0x428280` 把裁剪写成锚点 ± 半边的正方形；第 1 条 60 tick | negative-evidence：回调里没有红→白插值 |
| 揭示写者 | `0x426e40(point, 行走者)` 把点记录 `+0x18..+0x24` 的路线交给 `0x426bb0(track,1)`，每成功一条行走者 `+0x88` 加一；只由行走者过程 `0x427420` 调用 | r2 阅读，未执行 |
| 行走者子状态 | 0：等 `0x460989()` 为 0，请求 `0x4c1bb0` 为 0 时揭示当前点 `0x4c1ba4` 的路线；1：计数 >0 就等；请求为点号时每 tick 经 `0x43bf30` 滚镜头到该点、到位揭示、请求改 −1；为 −1 时滚回当前点、揭示、改 0；为 0 时进 2 并把点击目标 `0x4c1ab8` 置 −1；2：写当前点，若有 `0x4c1bb4` 设为目标，进 3 起行走 | 揭示期间的点击作废 |
| 行走速度 | `0x4277ed` 设 `+0x88=0x20000`（16.16 的 2／tick） | 每秒 tick 数未测 |
| 配乐 | `0x42c1c0` 查 `0x477b44`：level 49 → track 6；level ≥100 → −1 | 见 [original_music](original_music.md) |
| `Status_Bar` | obj12，camera+(0,412)；`0x427200` 算完成度（分子 mode2 且非 Hidden 的点，分母命名点数 −1，上限 100），`0x42d090` 写 `h:mm:ss`；RESOURCE 360「完成度：」；前段生成「完成度： 42%」，止于 `0x427309` | 精确成像与计时来源未执行 |

### static-derived：te 条件

opcode 按 `TOWNDEF.H`，入口 `0x454e20`；返回 0 继续／等待、1 结束当前事件、2 交给子菜单。

| token | 语义与地址 |
| --- | --- |
| `teCheckMoney` 16 | `0x4555a5` 比较金币；足够时 `0x455627` 立即扣 cost 并继续；不足不扣款、进提示（止于 `0x4555f4`）；完成阶段 `0x455eb6` 等待标志清后 phase 清 0、返回 1，无隐式跳转或退款 |
| `teCheckPlayerExist` 18、`teCheckItemExist` 19 | 正常返回 0，只前进 opcode 一个 DWORD，不检查对象、不消费参数 |
| `teCheckItemExecEvent` 29 | `0x454cd0` 查两个共享物品库与当前队员八槽；找到可按 delete 参数消费一份，经 `0x44e0e0` 切到指定 event；未找到继续原程序 |
| `teCheckTEExist` 33 | `0x455db7` 调 `0x4546c0` 查 town／parent／child：找到且 event 非 0 转指针，event 0 返回 1，未找到继续 |
| `teCheckJobUp` 31、`teCheckJobUp2` 32 | 无合格角色进 100 号失败提示（止于 `0x455d39`）；提示结束后 fail event=-1 结束、非负转指针 |
| `teAppearSecretMan` 36 | `0x454db0` 用全局缓存 0／-1／正 event 表示未决／失败／已选；未决时 `rand(100)+1 < threshold` 严格成立才加子项，相等失败并缓存 -1；force 可绕过；`0x479398` 的 9 个 short 123,113–120 按当前索引选 event |

negative-evidence（有范围）：`0x454e20` 的 shop／delay 分派没有取得买卖 handler、入包选择与消息输入时钟的执行回执；买入价、卖价 price×50÷100 与重要物品拒收见 [original_shop_transaction](original_shop_transaction.md)。

## 重制接线

- 数据：`tools/hsltools/data/world_map.py` → `content/imported/hsl/global/world_map/`（[结构](world_map_data.md)）；场景 `content/world/world_map_scene.json`（`level_kind: world_map`）。
- `game/world/WorldMapRuntime.gd`：`select_point` 当前点分支只对 Town 且 event 非 0 重新进城，其余记 `current_point_ignored`；`_build_status_bar`（(0,412) 整张减法混合，「完成度：」x 6、数字 x 114、时间右对齐 x 634），`_advance_show_sequence`（按上表排序，揭示期间丢弃点击）；`game/world/WorldMapRules.gd`（到达分支）；`game/world/WorldScriptActions.gd`（脚本写入）。
- 城镇：`game/world/TownRuntime.gd`、`TownShopScreen.gd`、`game/sim/TownEventRules.gd`（[读法表](town_event_semantics.md)）、`game/world/WorldPartyRules.gd`（买卖）；文字／头像／货表由 `tools/hsltools/assets/town_assets.py` 生成；初始根菜单 `content/world/town_initial_trees.json`。
- 重制值：旅行速度 96 px/s、揭示动画节奏、遭遇抽样比较方向、镜头滑行步长 32、Leonard 贴图作队伍标记、TOWNDEF if_wait=0 仍逐句等确认、`teDelay`／`tePlaySound` 只记录（provisional）。

## 复现

`python3 tools/hsl.py check world_town`

## 边界

- 探针止于地图新游戏设置、到达请求、失败对白创建、速度设置与状态栏绘制准备等具名边界；关卡加载、UI 与请求后的 Visit 写入未执行。
- 完整菜单对象创建、焦点／返回导航与后期所有树变更未执行；UI 应从当前城镇／根的现有子项生成，不从 TOWNDEF 注释归类。
- 大地图上 `0x43bf30` 是否走剧情步长 16 未读；if_wait=0 是否仍需输入、全转职成功链、secret 阈值的所有设定入口未读。
- 点 16 命運的神殿在 bigmap.dat 没有路线相连，进入方式未读。
- 夹具的金额、指针、角色与阶段是显式输入，不是实际存档快照。

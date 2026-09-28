# 世界地图与城镇：初始化、bigmap 三字段、到达分支、路线揭示与 te 条件

> evidence: static-derived; resource-derived; runtime-measured: Wine 原版多跳旅行两趟（0x4c59c4／0x4c1ba8／0x4c1bac 读数）; negative-evidence: 独立默认 level 表、路线红白插值、买卖 handler 执行回执 · status: live · functions: 0x426b70, 0x426bb0, 0x426bf0, 0x426c70, 0x426ce0, 0x426e40, 0x426fc0, 0x427070, 0x427200, 0x427420, 0x427df0, 0x4280d0, 0x42c180, 0x42c1c0, 0x42cc10, 0x42cc60, 0x42d090, 0x42f7a4, 0x44de20, 0x44e0e0, 0x4545a0, 0x454650, 0x4546c0, 0x454a20, 0x454ae0, 0x454cd0, 0x454db0, 0x454e20, 0x45543a, 0x455710, 0x4606a9 · tools: hsltools/data/world_map.py, hsltools/probes/world_town.py · updated: 2026-09-28

## 结论

- 原版城镇菜单是 `0x454a20` 按 town id 建立的可变 100×264 字节记录，新游戏只有歐姆村／米蘭多／席達鎮有初始树；bigmap 点与路线各有展示阶段、类型位、可变 event 三个独立字段；到达按当前 event 与类型分支，没有独立默认 level 表（static-derived，原指令有界执行；negative-evidence）。
- 重制 `game/world/WorldMapRuntime.gd`、`WorldMapRules.gd`、`TownRuntime.gd` 与 `game/sim/TownEventRules.gd` 按这些字段、新游戏隐藏点线、到达分支、M_PNT 三帧、命中框 ±16、状态栏与揭示排序实现（static-derived 输入）。
- 寻路与行走：点任何点都由 `0x427070` 在展示阶段 2 的路线上求最短路（代价＝折线 |dx|+|dy|），不查点与路线的 Hidden、不查点的展示阶段；行走者逐段走，每到一个点都跑到达分派 `0x427ab3`（非目的点不进城），途中点的 Battle／General 带 event 就在该点进关并停在那里；路过的点不标 Visit、不揭示路线。Wine 两趟实录印证；重制 `WorldMapRules.route_between` 与 `WorldMapRuntime` 逐段行走照此（static-derived；runtime-measured）。
- 脚本行走 `teSetBMWalkToPoint` 与玩家点击同路：城镇分支 `0x45543a` 写目标 `0x4c1bb4`、from≠49 时写 `0x477c18`，回大地图 `0x42f7a4` 以 from 作当前点，行走者子状态 2 把目标转成点击、子状态 3 同样调 `0x427070`；无路线时原地不动。重制 `_consume_pending_walk` 照此经 `select_point` 多跳（static-derived）。
- 大地图不画点名：帧 01／03／04 当前点、可达点、悬停点旁都没有地名；重制点名只在 OPT-GUIDE=提示 画（runtime-measured）。
- 城镇 `tePlaySound`（opcode 28）分支 `0x455710` 调 `0x42c180(wav, 0)` 即播不等；重制导入三个 WAV 并当场播放（static-derived；resource-derived）。
- 点自己所在的点：点对象过程 `0x427df0` 不比当前点，只写点击目标；行走者子状态 3 找不到自身路线后，仅 event 非 0 且带 Town 位时进城，Battle／General（及 event 0）清掉点击、不分派到达，不会重打该点关卡；重制 `select_point` 当前点分支照此（static-derived）。
- 到点分派：event 0 一律不分派，Town 也一样（`0x427aca`）；已访问 General 的遇敌是 `0x458c80(100)+1 ≤ ratio`；Visit 只在分派成立时写——请求关卡后立即（`0x427b54`）或进城时（`0x427b88`）；目的点分派不成立时 `0x427d36` 揭示该点路线、不写 Visit；分派成立时当场不揭示：请求关卡的，换场后大地图重新载入，由行走者子状态 0 在请求 `0x4c1bb0` 为 0 时揭示当前点 `0x4c1ba4`；进城的，行走者子状态 15（`0x427ce9`，调 `0x456150` 开城）进 16（`0x427d22`）等城镇返回，结果不为 2 时先 `0x42c340` 放音乐，再由 `0x427d36` 揭示 `[行走者+0x90]`（城镇点）、进子状态 1，不看 `0x4c1bb0`（static-derived）。
- 差异：旅行速度、揭示触发外的时钟、镜头滑行步长为重制值；差异清单 `town-event-timing`、`town-layout-extras`（provisional）。

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

### static-derived＋runtime-measured：寻路与行走

点对象过程 `0x427df0` 只写点击目标 `0x4c1ab8`；行走者 `0x427420` 子状态 3 调 `0x427070(当前 0x4c1ba4, 目标)`，非 0 即进 `0x4277ed` 起步（速度 `+0x88=0x20000`）。

| 环节 | 原版 | 地址 |
| --- | --- | --- |
| 寻路范围 | 整张点表（100 槽）的最短路，不是单条路线查找：节点表 `0x4c59e0` 每点 24 字节（活动、代价、入边路线、首路线、前驱、后继），代价初值 600000（`0x927c0`），起点 0 且活动 | `0x427070..0x4270c6` |
| 松弛 | 按点槽顺序反复扫；活动点依次取自身记录 `+0x18..+0x24` 的路线经 `0x426fc0` 松弛后置不活动；有任何松弛就再扫一遍 | `0x4270e0..0x427165` |
| 路线条件 | 只收展示阶段 ＝2 的路线（`0x426c50`）；邻点＝路线另一端（`+8` 等于本点取 `+0xc`，否则取 `+8`）；新代价严格小于邻点代价且小于已知到目标最优（`0x4c59c8`）才写；不查路线／点的 Hidden、不查点的展示阶段 | `0x426fc0..0x42705b` |
| 路线代价 | 路线装载把 TRACK 折线相邻点的 \|dx\|+\|dy\| 累加存 `[0x4c1b64]+track*12+8` | `0x44e006..0x44e061` |
| 结果 | 从目标沿前驱倒推，给每点写后继（`+0x14`）与出边路线（`+0xc`），返回起点的出边路线；目标未达或起点＝终点返回 0 | `0x427170..0x4271b2`、`0x42708a` |
| 逐段行走 | 子状态 4 取 `[walker+0x90]` 的出边路线，按与折线首点距离 >6 决定反向，逐点走完（子状态 5／6）；镜头每 tick 经 `0x43bf30` 跟随行走者 | `0x427866..0x427a80` |
| 每到一个点 | 取出边路线另一端，直接跑到达分派 `0x427ab3`，选定＝该点等于 `0x4c1ab8`；分派成立（关卡请求或进城）即停，`[walker+0x90]` 改成该点 | `0x427a86..0x427bad` |
| 途中点 | event 0 与 Town 路过；General 未访问、Battle（带 event）请求关卡，General 已访问先过 encounter ratio（`0x4545a0` 读 `0x4c27e0` 的 short）与 1..100 抽样，成立再抽 0..2——与目的点同一段代码，抽取按路线顺序每点一次；关卡请求 `0x42cc10(点, level)` 把点记 `0x4c1ba8`，回大地图时 `0x42f7a4` 把它写回当前点 | `0x427ab3..0x427b95`、`0x42cc41`、`0x42f7bf` |
| 路过不做的事 | 不标 Visit（`0x426d60` 只在分派成立时调）、不揭示路线（`0x426e40` 只在目的点 `0x427d36` 调）、不写 `0x4c1ba4`（子状态 2 才写） | `0x427bb3..0x427bd2` |
| 目的点 | 分派不成立（event 0、未抽中遭遇）时 `0x427d36` 揭示目的点路线、回子状态 1；随后子状态 2 写当前点 | `0x427d36..0x427d50`、`0x42772a` |
| 脚本行走写入 | te opcode 41 `teSetBMWalkToPoint(from, to)`：`0x45544e` 写 `0x4c1bb4`＝to；from≠49（`0x455443`）时 `0x42cc60` 写 `0x477c18`＝from；随后 `0x42cc10(49,49)` 请求回大地图 | `0x45543a..0x45546b`、`0x42cc60` |
| 脚本行走起点 | 回大地图 `0x42f7a4`：`0x477c18`≠−1 就写当前点 `0x4c1ba4` 并复位 −1，否则取 `0x4c1bb8`；只写当前点，不标 Visit、不揭示 | `0x42f7a4..0x42f7c9` |
| 脚本行走寻路 | 子状态 2 写当前点后，`0x4c1bb4` 非 0 则写点击目标 `0x4c1ab8` 并清 `0x4c1bb4`；子状态 3 与玩家点击同一段：`0x427070(当前, 目标)` 非 0 起步多跳，0 时目标≠当前 `0x427796` 跳 `0x4276fd` 清点击、原地不动，目标＝当前按上节重新进城规则 | `0x427723..0x42775a`、`0x427775..0x427796` |

runtime-measured（2026-09-27，Wine 原版 v1.06，读回憶錄第 3 行 兩棲族部落 完成度 31%，存档 sha 前后一致）：

| 趟 | 操作与路线（0x427070 同算法离线复算） | 读数与画面 |
| --- | --- | --- |
| 1 | 当前点 14 兩棲族部落 点 11 薛維斯港：路线 13→12→11，经 龍之息（Town，event 0）与 巴瀚納海峽（General 已访问，ratio 10） | 点击后 `0x4c1ab8`＝11；行走者经 巴瀚納海峽 未进关；约 1 s 内 `0x4c59c4`＝11、薛維斯港 城镇菜单打开；离城后 `0x4c1ba4`＝11 |
| 2 | 当前点 11 点 8 菲納斯河畔：路线 10→8，经点 9 廢都 曼多利亞（General 未访问，event 900，展示阶段 0，路线 10 带 Hidden 位但阶段 2） | `0x4c1ab8`＝8，`0x4c1ba8`＝9、`0x4c1bac`＝900（0x384）：在途中点 9 请求关卡，随即进入该关（曼多利亞 废墟场景、一般兵对白），没有走到 8 |

### static-derived：到达

`0x427ab3` 先读目的点当前 `+8`（event，`0x426ce0`）再读类型（`0x426e00`）；General 判断在 Battle 之前；关卡请求走 `0x42cc10`（探针止于 `0x427b3e`）。

| 当前记录 | 原分支 |
| --- | --- |
| event=0 | 不请求关卡／城镇，Town 也一样：`0x427aca` `test ebx,ebx; je 0x427b95` 在任何类型位测试之前 |
| General，未 Visit | 用当前 event 请求关卡 |
| General，已 Visit | ratio＝`0x4545a0(点)`，r＝`0x458c80(100)+1`，`cmp ratio, r; jl 0x427b95`：r ≤ ratio 才遇敌；再加 `0x458c80(3)`，夹到 2 |
| Battle | 未访问用 event；已访问加 `0x458c80(3)`，不走 encounter 检查 |
| Town | 仅当点＝点击目标 `0x4c1ab8`（选定目的点）：`0x427b78` 把 event 写城镇 id `0x4c59c4`、进子状态 15、`0x427b88` `0x426d60(点, Visit)`；路过不进城 |
| 请求关卡之后 | `0x427b3e` 调 `0x42cc10(点, level)`，`0x427b54` 立即 `0x426d60(点, 0x10000000)`（`or [点*40+0x4c4a24], Visit`） |
| 分派结果 | 成立时 `0x427bad` `jne 0x427d59` 跳过揭示；不成立且点是目的点时 `0x427bbf` 跳 `0x427d36`：`0x426e40(行走者, 点)` 揭示该点路线、进子状态 1，不写 Visit。`0x427d36` 另一个入口是离城路径：子状态 16 `0x427d22` 等 `[esi+0xac]` 非 0，为 2（`0x456150` 建城镇对象失败时写的值）经 `0x427d2f` 直接跳来，否则先 `0x427d31` 调 `0x42c340` 再落进来 |

这张表对路线上的每个点都执行（见上节「每到一个点」）。`0x426e40` 的调用点只有 `0x427582`、`0x42763b`、`0x4276b8`、`0x4276df`、`0x427d48`，都不在成立分支里。分派成立后的揭示按两种成立分开：请求关卡的，换场后大地图重新载入，由行走者子状态 0 揭示（`0x427572..0x427582`：请求 `0x4c1bb0` 为 0 时 `0x426e40(行走者, [0x4c1ba4])`）；进城的，`0x427b7f` 写子状态 15，跳转表 `0x427da0` 第 15 项 `0x427ce9` 把子状态加到 16、清 `[esi+0xac]`、调 `0x456150([0x4c59c4], &[esi+0xac], [esi+4], [esi+8])` 开城，第 16 项 `0x427d22` 在 `[esi+0xac]` 为 0 时等，城镇返回后经 `0x427d31`／`0x427d2f` 落到 `0x427d36`：`0x426e40(行走者, [esi+0x90])` 揭示城镇点路线、进子状态 1，这条路不经子状态 0、不看 `0x4c1bb0`。重制 `_on_town_closed` 不带条件地揭示当前点，对应 `0x427d36`。

城镇号取 event 值：脚本对 Town 点写的 event 只有 0 或该点自身的号（WINFAIL900／STORY009 把点 9 设为 event 0 Town，TOWNDEF 30 设 900 General；WINFAIL026／028／043 把点 26／28／43 设 event 0 Town；点 13、37、45 设 event 0 Visit 后加 Town 位），所以城镇号总等于点号（resource-derived）。

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
| 点 mode1 | 点过程 `0x427df0` 的 mode 1 在 `0x427fca` 直接 `0x426b70(点, 2)` 并落到 case 2，没有显现动画 | — |
| 路线 mode1 | 子状态 0 置裁剪位 `[obj] \|= 0x1000000`、半边 `+0x94 = 0`，计数 `+0x90 = max(\|w−ox\|, \|ox\|, \|h−oy\|, \|oy\|)`（`0x4606a9` 取 shape 宽高与 origin）；子状态 1 每 tick 半边 +1、计数 −1，到 0 设 mode2、清裁剪位、两端点 `0x426b70(point,1)`、`[0x4c1abc]+0x88` 减一；每 tick 尾 `0x428280` 把裁剪写成锚点 ± 半边的正方形；第 1 条 60 tick | negative-evidence：回调里没有红→白插值 |
| 揭示写者 | `0x426e40(行走者, 点)` 把点记录 `+0x18..+0x24` 的路线交给 `0x426bb0(track,1)`，每成功一条行走者 `+0x88` 加一；只由行走者过程 `0x427420` 调用：子状态 0／1（`0x427582`、`0x42763b`、`0x4276b8`、`0x4276df`）与 `0x427d36`（调用点 `0x427d48`，到点分派不成立与离城共用） | r2 阅读，未执行 |
| 行走者子状态 | 0：等 `0x460989()` 为 0，请求 `0x4c1bb0` 为 0 时揭示当前点 `0x4c1ba4` 的路线；1：计数 >0 就等；请求为点号时每 tick 经 `0x43bf30` 滚镜头到该点、到位揭示、请求改 −1；为 −1 时滚回当前点、揭示、改 0；为 0 时进 2 并把点击目标 `0x4c1ab8` 置 −1；2：写当前点，若有 `0x4c1bb4` 设为目标，进 3 起行走 | 揭示期间的点击作废 |
| 行走速度 | `0x4277ed` 设 `+0x88=0x20000`（16.16 的 2／tick） | 每秒 tick 数未测 |
| 配乐 | `0x42c1c0` 查 `0x477b44`：level 49 → track 6；level ≥100 → −1 | 见 [original_music](original_music.md) |
| `Status_Bar` | obj12，camera+(0,412)；`0x427200` 算完成度（分子 mode2 且非 Hidden 的点，分母命名点数 −1，上限 100），`0x42d090` 写 `h:mm:ss`；RESOURCE 360「完成度：」；前段生成「完成度： 42%」，止于 `0x427309` | 精确成像与计时来源未执行 |

### runtime-measured：大地图点名

帧 01／03／04（[original_world_town 实录](../runtime_observations/original_world_town/README.md)）大地图上只有点图标、路线与行走者，当前点、可达点与悬停点旁都没有地名文字；悬停是否另显示地名未采。

### static-derived：te 条件

opcode 按 `TOWNDEF.H`，入口 `0x454e20`；返回 0 继续／等待、1 结束当前事件、2 交给子菜单。

| token | 语义与地址 |
| --- | --- |
| `teCheckMoney` 16 | `0x4555a5` 比较金币；足够时 `0x455627` 立即扣 cost 并继续；不足不扣款、进提示（止于 `0x4555f4`）；完成阶段 `0x455eb6` 等待标志清后 phase 清 0、返回 1，无隐式跳转或退款 |
| `teCheckPlayerExist` 18、`teCheckItemExist` 19 | 正常返回 0，只前进 opcode 一个 DWORD，不检查对象、不消费参数 |
| `teCheckItemExecEvent` 29 | `0x454cd0` 查两个共享物品库与当前队员八槽；找到可按 delete 参数消费一份，经 `0x44e0e0` 切到指定 event；未找到继续原程序 |
| `teCheckTEExist` 33 | `0x455db7` 调 `0x4546c0` 查 town／parent／child：找到且 event 非 0 转指针，event 0 返回 1，未找到继续 |
| `teCheckJobUp` 31、`teCheckJobUp2` 32 | 无合格角色进 100 号失败提示（止于 `0x455d39`）；提示结束后 fail event=-1 结束、非负转指针 |
| `tePlaySound` 28 | `0x455710` 取参数（WAV 成员路径）调 `0x42c180(wav, 0)`：音效开关 `0x4c1af4` 开且 `0x477c20` 非 0 时 `0x459a20` 装载、`0x45a390` 以音量 255 播放后返回，不等待，同一次调用继续下一 token |
| `teAppearSecretMan` 36 | `0x454db0` 用全局缓存 0／-1／正 event 表示未决／失败／已选；未决时 `rand(100)+1 < threshold` 严格成立才加子项，相等失败并缓存 -1；force 可绕过；`0x479398` 的 9 个 short 123,113–120 按当前索引选 event |

negative-evidence（有范围）：`0x454e20` 的 shop／delay 分派没有取得买卖 handler、入包选择与消息输入时钟的执行回执；买入价、卖价 price×50÷100 与重要物品拒收见 [original_shop_transaction](original_shop_transaction.md)。

## 重制接线

- 数据：`tools/hsltools/data/world_map.py` → `content/imported/hsl/global/world_map/`（[结构](world_map_data.md)）；场景 `content/world/world_map_scene.json`（`level_kind: world_map`）。
- `game/world/WorldMapRules.gd` `route_between`／`track_route_cost`：照 `0x427070`／`0x426fc0` 的扫描顺序、阶段 2 条件、严格比较与 |dx|+|dy| 代价给出路线序列；`WorldMapRuntime.gd` `select_point` 走整条路线，`_pass_point` 在每个途中点以 `arrival(selected=false)` 分派，关卡则在该点停下进关（标 Visit、当前点改为该点），否则接着走，目的点才走原有到达。
- `game/world/WorldMapRuntime.gd`：`select_point` 当前点分支只对 Town 且 event 非 0 重新进城，其余记 `current_point_ignored`；`_build_status_bar`（(0,412) 整张减法混合，「完成度：」x 6、数字 x 114、时间右对齐 x 634），`_advance_show_sequence`（按上表排序，揭示期间丢弃点击）；`game/world/WorldMapRules.gd`（到达分支）；`game/world/WorldScriptActions.gd`（脚本写入）。
- 城镇：`game/world/TownRuntime.gd`、`TownShopScreen.gd`、`game/sim/TownEventRules.gd`（[读法表](town_event_semantics.md)）、`game/world/WorldPartyRules.gd`（买卖）；文字／头像／货表由 `tools/hsltools/assets/town_assets.py` 生成；初始根菜单 `content/world/town_initial_trees.json`。
- 脚本行走：`WorldMapRuntime._consume_pending_walk` 先按 from（≠49）设当前点，再经 `select_point(to, "script_walk")` 走 `route_between` 多跳；无路线记 `unreachable` 原地不动。
- 点名：`WorldMapRuntime._refresh_labels` 在 OPT-GUIDE=原版 时不画。
- 音效：`tools/hsltools/assets/town_assets.py` 从 PAK 解出 `tePlaySound` 点名的 WAV（`content/imported/hsl/global/world_map/town_sounds.json`、`town_sounds/*.wav`）；`TownRuntime._play_sound` 当场播放。
- 重制值：旅行速度 96 px/s、揭示动画节奏、镜头滑行步长 32、Leonard 贴图作队伍标记、TOWNDEF if_wait=0 仍逐句等确认（provisional）。

## 复现

`python3 tools/hsl.py check world_town`

## 边界

- 探针止于地图新游戏设置、到达请求、失败对白创建、速度设置与状态栏绘制准备等具名边界；关卡加载与 UI 未执行；请求后的 Visit 写入（`0x427b54`）与分派结果分支为静态读，未执行。
- 完整菜单对象创建、焦点／返回导航与后期所有树变更未执行；UI 应从当前城镇／根的现有子项生成，不从 TOWNDEF 注释归类。
- 大地图上 `0x43bf30` 是否走剧情步长 16 未读；if_wait=0 是否仍需输入、全转职成功链、secret 阈值的所有设定入口未读。
- 脚本行走 from 改当前点时，原版回大地图后行走者子状态 0 揭示的是 from 的路线；重制城镇关闭时先揭示原当前点再处理脚本行走（两者只在 from≠所在城镇时不同，TOWNDEF 里两例 from 都等于所在港口）。
- `tePlaySound` 的音效开关 `0x4c1af4` 与 `0x477c20` 对应重制的音效音量设置，未逐位核对。
- 点 16 命運的神殿在 bigmap.dat 没有路线相连：由 薛維斯港 事件 51（港口船長二選一）清点 16 的 Hidden、`teBMSetPointMode gameBMShow`，再 `teSetNextPlayLevelEvent(town_命運神殿, gameBigMapLevel)` 回大地图站到点 16（resource-derived）。
- 夹具的金额、指针、角色与阶段是显式输入，不是实际存档快照。

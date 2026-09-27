# 世界地图／城镇数据链（bigmap.dat、TRACK、TOWNDEF）

> evidence: resource-derived; provisional · status: live · tools: hsltools/data/big_map_flow.py, hsltools/data/world_map.py, hsltools/levels/map_objects.py, test_hsl_big_map_flow.py · updated: 2026-09-18

Checked: 2026-09-18. 本包只记录原包成员的**结构**与字段交叉校验，证据等级为 `resource-derived`；
凡是数据本身不能证明的字段含义和运行时行为一律标 `provisional`，列在文末。它不声明任何原版
运行时语义，也不对应任何已实现的玩法。

## 可复跑入口

```sh
PYTHONPATH=. python3 tools/hsl.py generate world_map            # 从 $HSL_ORIGINAL_DIR 重生成
PYTHONPATH=. python3 tools/hsl.py check world_map    # 有 PAK：重生成并逐字节比对；无 PAK：只做离线一致性
PYTHONPATH=. python3 -m unittest tools.test_hsl_world_map
```

Tracked 输出（`content/imported/hsl/global/world_map/`）：

- `world_map.json`（schema `hsl_world_map.v1`）：点位、路线、城镇、底图与自检结果。
- `towndef.json`（schema `hsl_towndef.v1`）：商店物品表、城镇事件表、te token 统计与消息 id 清单。
- `previews/`：`bigmap.png`（1280×960）、11 张 `townbg_NN.png`（325×185）、3 张点位标记 `m_pnt00N.png`、44 张路线预绘图
  `m_trk0NN.png`、`status_bar.png`（640×51），共 60 张，全部由共用 TLHS 解码器 `hsltools.sources.shp.parse_shp`／
  `write_shp_preview` 解出；JSON 记录源成员 SHA-256、PNG SHA-256、宽高、`frame_count`（TLHS 一成员一图，恒为 1）与
  0x1C/0x20 的 `draw_origin`（与 `hsltools/levels/map_objects.py` 同一读法，带符号 int32）。

## 来源成员

| 键 | 成员 | 字节 | 用途 |
| --- | --- | --- | --- |
| bigmap_dat | `@:\data\bigmap.dat` | 5600 | 点／线二进制表 |
| track_txt / track_h | `@:\data\TRACK.TXT`、`@:\data\TRACK.H` | 3214 / 1575 | 44 条 `[track]` 折线，`bmTrackNN = NN` |
| resource_txt | `@:\data\RESOURCE.TXT` | 129701 | `[name]` 表：点名 315..359、店名 30..34 等（复用 `hsltools.sources.tables.parse_table`，cp950） |
| extras_h | `@:\data\extras.h` | 627 | 12 个 `#define town_XXX N`（N 为点 id）与 `SID_*` 玩家槽 |
| type_h | `@:\data\TYPE.H` | 10555 | `bmpm*` 五个旗标位、`gameBMShowHidden/Slow/Show = 0/1/2`、`gameBigMapLevel = 49` |
| towndef_txt / towndef_h | `@:\data\TOWNDEF.TXT`、`@:\data\TOWNDEF.H` | 57611 / 2570 | 城镇事件表与 46 个 `te*` token 定义（含参数签名注释） |
| SHP | `@:\shape99\BigMap.SHP`、`@:\shape\TownBG01.SHP`…（大小写不一，按不区分大小写匹配） | — | 大地图底图、城镇背景 |
| SHP | `@:\shape99\m_pnt001..003.SHP`、`@:\shape99\m_trk001..044.SHP`、`@:\shape99\Status_Bar.SHP` | — | 点位标记（3 种）、每条 bmTrackNN 的预绘路线图、状态条 |

SHA-256 逐成员写在两份 JSON 的 `sources` 里；工具在构建时核对 TYPE.H 的 `bmpm*` 值与内置表一致，不一致即失败。

## bigmap.dat 记录布局（resource-derived）

- 偏移 0 起：100 个 40 字节槽（到偏移 4000），每槽 10 个 int32 LE。槽 0 全零；槽 1..45 各一个点，**点 id 等于槽号**。
  字段顺序：`[0] raw_field0`、`[1] flags`、`[2] point id`、`[3] name resource id`、`[4] x`、`[5] y`、`[6..8] 最多 3 个 track id（0 = 空）`、`[9] 恒为 0`。
  名称 id 恰为 315..359（315 歐姆村 … 359 克萊恩城），x∈[81,1173]、y∈[143,791]，落在 BigMap.SHP 的 1280×960 像素空间内。
- 偏移 4000 起：100 个 16 字节槽（到文件末 5600），每槽 4 个 int32 LE。槽 0 全零；槽 1..44 各一条线，**线 id 等于槽号**，与 TRACK.H 的 `bmTrackNN` 一一对应。
  字段顺序：`[0] raw_field0`、`[1] raw_field1`、`[2] from point`、`[3] to point`。
- 旗标位（TYPE.H）：`bmpmBattle 0x80000000`、`bmpmGeneral 0x40000000`、`bmpmTown 0x20000000`、`bmpmVisit 0x10000000`、`bmpmHidden 0x08000000`。
  工具按位解成名字列表并保留原始 hex；`flags_undecoded_bits` 记录落在这五位之外的位（当前全部为 null）。

静态分布（计数，不是语义）：45 点中 bmpmTown 14、bmpmGeneral 23、bmpmBattle 8（5 呼嘯平原、10 帕尼西雅城廢墟、15 深淵之沼、19 利魯瑪山地、28 眾神的宮殿遺址、29 約瑟河、38 幽闇墳場、41 悲嘆之湖），bmpmVisit／bmpmHidden 在文件里均为 0。
44 条线中 18 条的 `raw_field1` 为 `0x08000000`（bmpmHidden 位）：10–14、20、23–26、29–34、37、43；所有线的 `raw_field0` 均为 0。

## 自检结果

`world_map.json.self_check` 由工具用数据互相核对，条目原样记录，不做修补：

- 44 条线的 from/to 都是有效点；每个点列出的 track id 都存在且确实以该点为端点；每条线都至少被一个端点列出。
- TRACK.TXT 44 条折线（共 176 个顶点）的首顶点＝from 点 (x,y)、末顶点＝to 点 (x,y)，44/44 全部相等（`endpoints_match_points`）。
- **唯一不一致**：点 16（命運的神殿，bmpmTown）的三个 track 槽全为 0，没有任何线连到它。TOWNDEF 里有 `teBMSetPointMode,town_命運神殿,gameBMShow`、`teBMClearPointFlag,town_命運神殿,bmpmHidden`、`teSetNextPlayLevelEvent,town_命運神殿,gameBigMapLevel` 等脚本引用；它如何在大地图上进入是未解事项，本包只记录“无线”。
- 城镇交叉核对：extras.h 12 个 `town_*` 全部指向存在且带 bmpmTown 的点；PAK 中 11 个 `TownBG` 成员（01、04、06、11、14、16、23、25、27、35、42）全部对应某个 `town_*`；`town_曼多力亞 = 9` 没有 `TownBG09`，`background` 写 null。另外点 20（王都 希里烏斯）与 45（克萊恩城）带 bmpmTown 但 extras.h 没有 `town_*` 符号，也没有 TownBG。

## 大地图图形成员（resource-derived，只记录）

- `assets.point_markers`：`m_pnt001` 17×17 origin (8,8)、`m_pnt002` 18×19 origin (9,9)、`m_pnt003` 18×19 origin (9,10)，三者 0x10 头字段同为 `0x2704`。三种标记与 bmpmTown／General／Battle 或其他状态的对应关系**未证明**，本包不解释。
- `tracks[].sprite`：44 条线各有一个 `m_trk0NN.SHP`（编号＝bmTrackNN），44/44 解码成功。宽高与折线包围盒同量级（如 bmTrack01 折线包围盒 48×53、图 53×61，origin (51,60)），`draw_origin` 含负值（bmTrack10 为 (0,-1)）；图相对折线／端点的放置规则未证。
- `assets.status_bar`：`Status_Bar.SHP` 640×51，origin (0,0)，用途按文件名记录，未证。

## TOWNDEF.TXT 结构（resource-derived）

去掉 `;` 注释与整行注释后：62 条 `[item]`（code 1..62，`item_id` 多行合并；44 条段头带注释，如「歐姆村」「敵人身上隨機攜帶物品, 等級一」）、191 条 `[town_event]`（code 1..191；段头注释保留为 `comment`，如「歐姆村武器店」「米蘭多酒館老闆」）。
每条 town_event 含 `show_name`（资源 id＋RESOURCE.TXT 文字，如 30 老闆／32 武器店／875 酒館老闆；14 条没有 show_name）、可选 `item_code`（31 个不同值，全部指向存在的 `[item]`）与 `events[]`。
`event = teXXX,args...` 一行可串多个 te 指令（如 `teDeleteSelfTE,7,1,14,teAddSelfTE,7,1,15`），工具按 `te[A-Z]` 前缀切分；行尾多余逗号丢弃。共 923 条指令，涉及 46 个定义 token 中的 39 个，**0 个未知 token**；使用次数全表见 `statistics.token_usage`（前三位 teShapeMessage 269、tePlayerMessage 184、teDelay 171）。
消息 id 只按 TOWNDEF.H 签名注释里标明的“message id”参数位收集（tePlayerMessage[1]、teShapeMessage[2]、teCheckMoney[3]、teCheckJobUp／teCheckJobUp2[1]、teSecretManBuyThing[2]、teSelectInsertEvent 自 2 起的偶数位）：433 个不同 id；teShapeMessage 的名字参数另列 46 个 `shape_name_resource_ids`。参数里出现的符号（`SID_*`、`town_*`、`bmpm*`、`gameBM*`、`gameoverID*`、`gameBigMapLevel`）经 extras.h／TYPE.H 解析写在 `symbols`，全部有值。

## 大地图流转脚本惯例（resource-derived）

`tools/hsltools/data/big_map_flow.py` 扫描原 PAK 全部 151 个含流转指令的 `story*.txt`／`winfail*.txt`（352 条 `actSetNextPlayLevelEvent`／`actBM*`／`actSetTownExecEvent`／`actAddTE` 等），写 `content/generated/hsl/static/hsl01/big_map_flow.json`（`hsl_big_map_flow.v1`，`--check` 离线复推导；单测 `tools/test_hsl_big_map_flow.py`）。symbol 取 `towndef.json` 的 TYPE.H／extras.h 读法（`gameBigMapLevel = 49`、`town_*`）。脚本惯例（不是 EXE handler 的证明）：

| 惯例 | 数据 | 读法 |
| --- | --- | --- |
| `actSetNextPlayLevelEvent,level,event` 的第二参是下一个要跑的关卡脚本集 | WINFAIL002 `2,55` → STORY055 `2,56` → STORY056 `2,gameBigMapLevel`；WINFAIL006 `6,62` → STORY062 `6,63` → STORY063 `6,gameBigMapLevel`；story-only 关卡 55／56／62／63 各有自己的 LEVEL bin | `event` = 下一关；`event == gameBigMapLevel` 回大地图并站在点 `level` |
| 主线战斗回图点 = 自己的关卡号 | 17 个带 `N,gameBigMapLevel` 的主线战斗全部 N＝关卡号（`battle_return_point_equals_level` 17/17）；story-only 关卡回到其前一场战斗的点（56→2、61→3、63→6、64→7、66→9、67／68→17、69→19、70→29、72→35、73→41、74→42、80→38） | 主线 1–45 关位于同号大地图点（`campaign.json` `world_map.point_level_range`） |
| 5xx 遭遇关回到被指派的点 | 28 个被 `actBMSetPointEvent,N,5xx,bmpmVisit` 指派的遭遇关，其 `5xx,gameBigMapLevel` 回图点全部＝N（28/28）；遭遇关按点成三（501–503→2、504–506→3…），脚本只指派第一个 | 第一参的“点”语义成立；引擎是否在三个里掷选未证 |
| 清关后写 Visit 点 | 25 个 WINFAIL 在 win 段写 `actBMSetPointEvent,N,5xx,bmpmVisit` ＋ `actBMSetPointEncounterRatio,N,ratio`（ratio 20／40／100 等）；`13,0,bmpmVisit`／`45,0,bmpmVisit` 为无遭遇的可过点 | Visit 点按 ratio（百分比读法）掷遭遇，event 0 或 ratio 0 只是停 |
| 城镇点变战斗再变回 | STORY008 `actBMSetPointEvent,9,9,bmpmBattle` → STORY009 `9,0,bmpmTown`；WINFAIL026／028／043 把清关点写成 `N,0,bmpmTown` | 点事件的 flag 决定该点当前类型（标记与到达行为随之变） |
| 没有 `actSetNextPlayLevelEvent` 的战斗 | WINFAIL001（只 `actSetTownExecEvent,town_歐姆村,9`，`;actBMSetPointEvent,1,501,0` 被注释）、WINFAIL005（只写点 5 Visit 与席達鎮事件 19） | 胜利后默认回大地图、站在同号点（provisional） |
| 城镇点上的关卡 | 席達鎮 town_event 23 `teSetNextPlayLevelEvent,6,6`、兩棲族部落 151 `13,13`、沙羅尼亞 167 `35,72`、斐達克 178 `42,74` | 城镇点到达先开城镇，关卡由城镇事件触发；Battle／General 点无脚本事件时默认开同号关卡 |

重制按此表实现 `WorldMapRules.arrival`／`CampaignProgress.next_destination`；SR-069 的原指令执行（[原合同](original_world_town.md)）随后印证了 +8 初值＝点号与到达分支（General 已访先 ratio 再 +0..2、Battle 已访 +0..2、Town 仅目的点），并把「同号默认」改述为文件数据。

## 未解语义（provisional，不在本包内声明）

| 项 | 观察 | 替换证据 |
| --- | --- | --- |
| 点 `raw_field0` | **已解（SR-069）**：展示阶段 0 不显示／1 揭示／2 稳定，与 Hidden 位分开；新游戏另由代码把 17 个点、18 条线 OR 上 Hidden（[原合同](original_world_town.md)） | — |
| 线 `raw_field1` | **已解（SR-069）**：`+0` 为展示阶段、`+4` 为 bmpm 位；18 条 Hidden 与代码列表一致 | — |
| `bmpm*` 位的行为 | **已解（SR-069）**：Visit＝已访问；Town／General／Battle 为类型（点事件整组替换）；到达分支见原合同；Hidden 阻止揭示 | 遭遇抽样比较方向、请求后的 Visit 写入未执行 |
| 点 16 无线 | 命運的神殿没有 track；到达方式（脚本 `teSetBMWalkToPoint`／直接进入）未证 | 大地图 walk handler |
| 折线行走 | 命中框 ±16 与 16.16 速度 2／tick 已解（SR-069）；路线进入揭示阶段的触发已定位（lane TOWNMAP：行走者 `0x427420` 子状态 0／1 调 `0x426e40`，见[原合同](original_world_town.md)）；每点进入的关卡号＝点记录 `+8`（文件初值＝点号）或脚本指派 | walker tick 与揭示触发的静态分析 |
| TOWNDEF handler | te 指令行为、商店定价、事件排程未证；本包仅复制 TOWNDEF.H 注释里的参数签名 | 城镇脚本 VM 静态分析 |
| m_pnt／m_trk／Status_Bar | **已解（SR-069）**：M_PNT001..003 为同一 shape 的三帧（Battle0／General1／Town2）；m_trk 锚点＝level049 EVEF 位置（＝起点）减 draw origin，44 条与本包一致；Status_Bar 在 camera+(0,412) 显示完成度与累计时间 | 状态栏文字排版与计时器来源未执行 |

TownBG／BigMap 预览只证明共用解码器能解出这些 TLHS 成员并给出尺寸；不代表原版绘制顺序、缩放或 UI 叠加。

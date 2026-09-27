# 剧情物件改地形：mapobjBlock 与 mapobjClearWall

> evidence: static-derived; resource-derived: 脚本 token、OBJ 字段与 WRD 格字; provisional: 第 80 关怨念體起始格为重制落点 · status: live · functions: 0x40ed50, 0x411900, 0x411990, 0x4119f0, 0x411a10, 0x42eb70, 0x43ccf0, 0x44fa80, 0x44fad0, 0x450840 · tools: TerrainEditRules.gd, hsltools/levels/scenario.py, run_story_object_terrain_tests.gd, test_hsl_story_object_terrain.py · updated: 2026-09-25

2026-09-24，lane R5-L4。起因：第 53 关实玩反馈——緹娜 还能走回 2 楼窗台，原版是否如此记不清（复述）；记忆不是原版证据，本包从脚本与 EXE 读出原版答案。只读 r2 反汇编 `hsl01.exe`，未开原作。

## 原版读法

| 来源 | 读法 |
| --- | --- |
| STORY053（resource-derived） | 緹娜 由 `obj_Story_Player2` 装在 (640,416)，走 (0,32)、沿绳 `actMoveDispWait` 滑 (0,288) 到格 (20,23) 之后，脚本 `actInsertStoryObject,obj_Story_Block,640,672`——格 (20,21)，正是二楼窗台下那条绳索竖井（格列 20、行 13..21，两侧行 12..21 是 0xff 墙）穿过底墙的唯一缺口 |
| `global.obs`／`OBJ-ALL.H`（resource-derived） | `obj_Story_Block`＝701「Map_Block」，`defProcStandObject`、`SHAPE\NULL.SHP`、`obj_Data9 = mapobjBlock`（TYPE.H 10）；各关 `obj_Story_Level_ClearWall` 为 `obj_Data9 = mapobjClearWall`（15） |
| `0x42eb70` | 建对象时以 `process(obj, -3)` 调该对象的过程（安装消息） |
| `0x43ccf0`（PROCESS.DEF `defProcStandObject = 2`，槽 `0x477c34`）消息 −3 | 按 `obj_Data9`（`+0xac`）分派：case 10 `0x4119f0(x, y, 0xff000000)` → `0x411900`：地图格字 `0x4c0928[(y>>5)·w + (x>>5)] |= 0xff000000`（高度字节成 0xff＝悬崖，地面走不过，飞行照高度规则不受限）；case 15 `0x411a10(x, y, 0x4000)` → `0x411990`：该格字 `&= ~0x4000`（清掉硬阻挡位） |
| `0x40ed50` | 通行洪泛读同一格字：0xff 高度拦地面模式，`& 0x74000`／`0x4000` 且格上无可穿越对象即拦（[四邻路径](original_movement.md)） |

结论：**原版第 53 关開場结束后格 (20,21) 是悬崖，緹娜 不能回到窗台竖井**；第 28 关四道门、第 80 关一道墙是 WRD 格字里的 0x4000，事件触发时由 `mapobjClearWall` 打开。

另：WRD 格字 bits 12..23 带原版地图旗标。导入以前只读 0xff 高度，房屋（第 1 关 187 格）、洞窟空处、墙下的 0x4000 格被当作可走；P8 起 `WrdTerrainTiles` 把 `& 0x974000` 写进 `movement_flags`，关卡生成链的站位检查同样拒绝（带 0x4000 的地图：1／3／28／52／57／65／74／75／80）。

## 全游戏盘点与重制处理

`hsltools.levels.scenario.story_object_terrain_inserts` 扫全部关卡 seed 的 STORY／WINFAIL：

| 关 | 来源 | 物件 | 格 | 重制 |
| --- | --- | --- | --- | --- |
| 53 | STORY（开场，首控前） | obj_Story_Block ×1 | (20,21) | `terrain_overrides` 高度 255，全程生效——与原版同（static-derived） |
| 28 | WINFAIL event 3..6（各自守门的 Enemy50 阵亡） | ClearWall ×4 | (4,48)、(26,34)、(12,31)、(14,8) | 事件触发时写进 `terrain_edits`、清 0x4000（static-derived，lane R5-L4c，见下「28／80 开墙按事件」） |
| 80 | WINFAIL event 3（Enemy068 倒下） | ClearWall ×4 | (21,11)、(22,12)、(23,13)、(24,13) | 事件触发时写进 `terrain_edits`；怨念體 actor068_1 倒下后才触发（R6-L10） |
| 39 | WINFAIL event 5（第 7 回合第三次震动） | obj_Story_Block，`actInsertStoryObjectXRange` 10 行 | 行 20..29 的横段共 89 格 | 事件触发时写进 loop 状态 `terrain_edits`，此后高度 255（static-derived，lane R5-L4b，见下「战中改地形」） |

`terrain_overrides` 由 `hsl generate level_battle:N` 写进 battle JSON，`WrdTerrainTiles.load_tiles(path, overrides)` 在建 loop 时应用；生成链自己的站位检查读同一张改后的地图。

## 边界与替换证据

- **28／80 的开墙时机**：lane R5-L4c 起按事件打开，见文末一节；此前（R5-L4）开战即开。
- **消融**：去掉 `BattleLoopInit` 对 overrides 的应用，`run_story_object_terrain_tests.gd` 的「(20,21) 是悬崖」「緹娜 回不到竖井」两条失败；Python 普查（`test_hsl_story_object_terrain.py`）要求每一处插入都已施加，或是解释器战中改地形的 `actInsertStoryObjectXRange`（下节）。
- 不声明：物件 `NULL.SHP` 的绘制、`mapobjBlock` 对已站在该格单位的处理（53 关无人站在 (20,21)）。

## 战中改地形（lane R5-L4b，2026-09-25）

第 39 关 WINFAIL event 5（第 7 回合）先 `actDeletePosPlayerXRange` 删掉十行上的双方单位，再以 `actInsertStoryObjectXRange,obj_Story_Block,x,y,n` 在同样十行上各建 n 个 `mapobjBlock` 物件——按上表 `0x42eb70`→`0x43ccf0` case 10，每格高度字节成 0xff：塌陷区成悬崖，地面单位进不去（resource-derived 脚本＋static-derived 读法）。

重制：
- `WinfailCompiler` 把 seed 的 `script_objects` 按 `obj_Data9` 连到改地形种类，编译为 `story_object_terrain`（第 39／53 关：`{"obj_Story_Block": {"height": 255}}`；resource-derived 连接，同 `_insert_class_id`）。
- `WinfailActions` 执行 `actInsertStoryObjectXRange` 时，经 `game/sim/TerrainEditRules.gd` 为每格追加 `{cell, height: 255, source}` 到 loop 状态 `terrain_edits`（随存档写读，`BattleCheckpoint.validate` 先校验它）。
- 共享的 `tiles` 配置从不改写；全部通行读者（移动包络、AI 路由与泛洪、剧情走位、脚本落点、增援落点、存档站位校验、自动对局指挥官的威胁图）改经 `TerrainEditRules.tiles(loop)` 读「配置＋编辑」，编辑后的地图按（配置引用，编辑表）记忆化，每格表缓存不失效。

检查：`tests/run_story_object_terrain_tests.gd` 在产品 loop 上把第 7 回合的 event 5 触发——89 格记为 0xff、共享块未改、主角走不进塌陷区、存档状态合到新建战斗的地图上仍是悬崖、越界编辑被拒；消融（编译程序去掉 `story_object_terrain`）塌陷区照旧可走。`tools/test_hsl_story_object_terrain.py` 的普查要求每个 WINFAIL mapobjBlock 都是解释器会改地形的 `actInsertStoryObjectXRange`，且不在开场 overrides 里。

不声明：`DisappearRock` 物件与烟雾的画面、塌陷后已站在该格的单位（脚本先删除，本关无此例）、飞行单位能否停在塌陷格（照高度规则可以）。

## 28／80 开墙按事件（lane R5-L4c，2026-09-25）

触发事件（resource-derived 脚本＋static-derived 读法）：

- **第 28 关**：STORY028 开场连插四个 `obj_Story_Level_Enemy50`，每个紧跟 `actChangePrevInsertObjectID,5000..5003`（(496,1264)、(816,1264)、(432,624)、(368,880)）。WINFAIL028 event 3..6 各以 `actCheckEnemy,1,500N` 为条件，触发后在 (128,1536)、(832,1088)、(384,992)、(448,256) 插 ClearWall——杀掉哪个守门者，开哪道门。
- **id 如何对上**（capstone 反汇编，同一 SHA）：`0x450840` case 0x20（跳表 `0x4537f4`，目标 `0x451155`）取上一个插入对象 `*0x4c1d38` 的 `+0xa4` 下标，把参数写进角色记录 `0x4c1bc8[下标]` 的字 `+0x84`；`0x44fa80`（process 3／5、未死亡的对象）返回的正是这个 `+0x84`；`0x44fad0` 逐槽调 `0x44fa80` 比较 code（`0x44fb53`）。所以 `actCheckEnemy,1,5000` 查的就是被改成 5000 的那名守门者（这也补上了 [出场检查](original_check_targets.md) 未读的「`0x44fa80` 取 code 的字段位置」）。
- **第 80 关**：event 3 条件 `actCheckEnemy,1,SID_ENEMY068`。Enemy068 是 EVEF 第 45 条的 `defProcEnemy` 静态对象（(736,352)，格 (23,11)，紧挨墙格），原版里它消失后开墙。

重制：
- `TerrainEditRules.EDITS_BY_OBJECT_KIND` 加 `mapobjClearWall: {clear_flags: 0x4000}`；`WinfailActions` 执行 `actInsertStoryObject` 时（除原有的表现记录外）经 `TerrainEditRules.record` 为该格追加编辑。`scenario.terrain_overrides` 只留 STORY 插入，WINFAIL 插入一律由解释器在事件触发时写入。
- 生成链 `trace_opening`（`hsltools/levels/battle.py`）遇到 STORY 的 `actChangePrevInsertObjectID` 时把新 id 绑到上一个插入的单位（`5000/1`→`guard050_6` … `5003/1`→`guard050_9`），与解释器里 WINFAIL 插入的同名处理（`ScriptActorCreationRules`）一致。全游戏只有 STORY028 用到这个 token。
- 第 80 关的 Enemy068 自 R6-L10 起是 PlayLoop 单位 actor068_1（PLAYERS 68 怨念體：pmEnemy、`size_type 1`、原刷新 1 级 1293 HP、move 0、8 种魔法；自有站立帧 `SHAPE\68-001`），`actCheckEnemy` 等它倒下才成立，墙随之打开。R6-L10 之前它只画不打、event 3 首检即触发。provisional：它的 3×3 身体在源格 (23,11) 盖住墙格 (22,12)（0x4000），重制的大型单位落点规则要求身体可停留，组装把它放到最近可停留的 (25,9)；原版安装不做地形检查，替换证据是原版里它站在墙上时的碰撞／选取读法。

检查：`tests/run_story_object_terrain_tests.gd` 的 `_door_walls`——两关载入时墙格都带 0x4000；28 关守门者都在时不开门；杀掉 `guard050_6` 只触发 event 3、只开 (4,48)、共享地图块不写、存档读回仍开着；消融（去掉 ClearWall 连接／去掉 `5000/1` 绑定）门不开；80 关首次判定开墙。`tools/test_hsl_story_object_terrain.py` 普查：WINFAIL 插入都是解释器会改地形的 token、不在开场 overrides 里、其事件检查的 id 都绑到单位（消融：去掉 28 关的四个绑定即失败）。

不声明：ClearWall 本身（`SHAPE\NULL.SHP`）的画面、开门时的 WhiteLight／Fire 演出之外的门扇动画；80 关怨念體的加色（`obj_Mode engADDCOLOR`）画法。

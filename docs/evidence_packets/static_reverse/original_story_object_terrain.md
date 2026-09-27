# 剧情物件改地形：mapobjBlock 与 mapobjClearWall

> evidence: static-derived; resource-derived: 脚本 token、OBJ 字段与 WRD 格字; provisional: 第 80 关怨念體起始格为重制落点 · status: live · functions: 0x40ed50, 0x411900, 0x411990, 0x4119f0, 0x411a10, 0x42eb70, 0x43ccf0, 0x44fa80, 0x44fad0, 0x450840 · tools: hsltools/levels/scenario.py, run_story_object_terrain_tests.gd, test_hsl_story_object_terrain.py · updated: 2026-09-27

## 结论

- 原版剧情物件在安装时改地图格字：`mapobjBlock` 把格高度字节置 0xff（悬崖），`mapobjClearWall` 清硬阻挡位 0x4000；因此第 53 关开场后格 (20,21) 是悬崖，緹娜 回不到窗台竖井；第 28 关四道门、第 80 关一道墙在事件触发时打开；第 39 关第 7 回合塌陷区成悬崖（static-derived＋resource-derived，r2 只读反汇编）。
- 重制：开场插入由 `terrain_overrides` 写进 battle JSON，战中插入由 `WinfailActions` 经 `game/sim/TerrainEditRules.gd` 追加到 loop 状态 `terrain_edits`，全部通行读者经 `TerrainEditRules.tiles(loop)` 读改后的地图（static-derived 输入）。
- 差异：第 80 关怨念體按大型单位落点规则放在 (25,9)，原版源格 (23,11)（provisional）。

## 证据

### resource-derived＋static-derived：原版读法

| 来源 | 读法 |
| --- | --- |
| STORY053 | 緹娜 由 `obj_Story_Player2` 装在 (640,416)，走 (0,32)、沿绳 `actMoveDispWait` 滑 (0,288) 到格 (20,23) 后，`actInsertStoryObject,obj_Story_Block,640,672`——格 (20,21)，即二楼窗台下绳索竖井（格列 20、行 13..21，两侧行 12..21 是 0xff 墙）穿过底墙的唯一缺口 |
| `global.obs`／`OBJ-ALL.H` | `obj_Story_Block`＝701「Map_Block」，`defProcStandObject`、`SHAPE\NULL.SHP`、`obj_Data9 = mapobjBlock`（TYPE.H 10）；各关 `obj_Story_Level_ClearWall` 为 `obj_Data9 = mapobjClearWall`（15） |
| `0x42eb70` | 建对象时以 `process(obj, -3)` 调该对象的过程（安装消息） |
| `0x43ccf0`（`defProcStandObject = 2`，槽 `0x477c34`）消息 −3 | 按 `obj_Data9`（`+0xac`）分派：case 10 `0x4119f0(x, y, 0xff000000)` → `0x411900`：`0x4c0928[(y>>5)·w + (x>>5)] |= 0xff000000`（地面走不过，飞行照高度规则不受限）；case 15 `0x411a10(x, y, 0x4000)` → `0x411990`：该格字 `&= ~0x4000` |
| `0x40ed50` | 通行洪泛读同一格字：0xff 高度拦地面模式，`& 0x74000`／`0x4000` 且格上无可穿越对象即拦（[original_movement](original_movement.md)） |
| WRD 格字 | bits 12..23 带原版地图旗标；带 0x4000 的地图：1／3／28／52／57／65／74／75／80（第 1 关房屋 187 格） |

### resource-derived＋static-derived：第 28／80 关开墙事件

- 第 28 关：STORY028 开场连插四个 `obj_Story_Level_Enemy50`，各紧跟 `actChangePrevInsertObjectID,5000..5003`（(496,1264)、(816,1264)、(432,624)、(368,880)）；WINFAIL028 event 3..6 各以 `actCheckEnemy,1,500N` 为条件，触发后在 (128,1536)、(832,1088)、(384,992)、(448,256) 插 ClearWall——杀掉哪个守门者开哪道门。
- id 对应：`0x450840` case 0x20（跳表 `0x4537f4`，目标 `0x451155`）取上一个插入对象 `*0x4c1d38` 的 `+0xa4` 下标，把参数写进角色记录 `0x4c1bc8[下标]` 的字 `+0x84`；`0x44fa80`（process 3／5、未死亡）返回的正是 `+0x84`；`0x44fad0` 逐槽调 `0x44fa80` 比较 code（`0x44fb53`）。所以 `actCheckEnemy,1,5000` 查的是被改成 5000 的守门者。
- 第 80 关：event 3 条件 `actCheckEnemy,1,SID_ENEMY068`；Enemy068 是 EVEF 第 45 条 `defProcEnemy` 静态对象（(736,352)，格 (23,11)，紧挨墙格），它消失后开墙。

### 全游戏盘点（`hsltools.levels.scenario.story_object_terrain_inserts`）

| 关 | 来源 | 物件 | 格 | 重制 |
| --- | --- | --- | --- | --- |
| 53 | STORY（开场，首控前） | obj_Story_Block ×1 | (20,21) | `terrain_overrides` 高度 255，全程生效 |
| 28 | WINFAIL event 3..6（各自守门的 Enemy50 阵亡） | ClearWall ×4 | (4,48)、(26,34)、(12,31)、(14,8) | 事件触发时写 `terrain_edits`、清 0x4000 |
| 80 | WINFAIL event 3（Enemy068 倒下） | ClearWall ×4 | (21,11)、(22,12)、(23,13)、(24,13) | 事件触发时写 `terrain_edits`；怨念體 actor068_1 倒下才触发 |
| 39 | WINFAIL event 5（第 7 回合第三次震动：先 `actDeletePosPlayerXRange` 删十行上双方单位） | obj_Story_Block，`actInsertStoryObjectXRange` 10 行 | 行 20..29 横段共 89 格 | 事件触发时写 `terrain_edits`，此后高度 255 |

## 重制接线

- 导入：`WrdTerrainTiles` 把 `& 0x974000` 写进 `movement_flags`；生成链站位检查同样拒绝。`terrain_overrides` 由 `hsl generate level_battle:N` 写进 battle JSON，`WrdTerrainTiles.load_tiles(path, overrides)` 在建 loop 时应用；只含 STORY 插入。
- `WinfailCompiler` 把 seed 的 `script_objects` 按 `obj_Data9` 编译为 `story_object_terrain`（第 39／53 关 `{"obj_Story_Block": {"height": 255}}`）；`TerrainEditRules.EDITS_BY_OBJECT_KIND` 含 `mapobjClearWall: {clear_flags: 0x4000}`。
- `WinfailActions` 执行 `actInsertStoryObjectXRange`／`actInsertStoryObject` 时经 `TerrainEditRules.record` 追加 `{cell, height|clear_flags, source}` 到 `terrain_edits`（随存档写读，`BattleCheckpoint.validate` 先校验）；共享 `tiles` 配置不改写，改后地图按（配置引用，编辑表）记忆化。
- 通行读者（移动包络、AI 路由与泛洪、剧情走位、脚本落点、增援落点、存档站位校验、自动对局威胁图）都经 `TerrainEditRules.tiles(loop)`。
- 生成链 `trace_opening`（`hsltools/levels/battle.py`）遇 STORY 的 `actChangePrevInsertObjectID` 把新 id 绑到上一个插入单位（`5000/1`→`guard050_6` … `5003/1`→`guard050_9`），与解释器 `ScriptActorCreationRules` 一致；全游戏只有 STORY028 用这个 token。
- 第 80 关 Enemy068 是 PlayLoop 单位 actor068_1（PLAYERS 68 怨念體：pmEnemy、`size_type 1`、原刷新 1 级 1293 HP、move 0、8 种魔法、站立帧 `SHAPE\68-001`）。

## 复现

`tools/godot.sh --headless --script res://tests/run_story_object_terrain_tests.gd`；`python3 -m unittest tools.test_hsl_story_object_terrain`

## 边界

- provisional：怨念體 3×3 身体在源格 (23,11) 盖住墙格 (22,12)（0x4000），重制落点规则要求身体可停留，放到最近可停留的 (25,9)；原版安装不做地形检查，替换证据是原版它站在墙上时的碰撞／选取读法。
- 不声明：`NULL.SHP` 物件与 `DisappearRock`／烟雾的画面、门扇动画、怨念體 `obj_Mode engADDCOLOR` 画法。
- 不声明：`mapobjBlock` 对已站在该格单位的处理（53 关无人站在 (20,21)，39 关脚本先删单位）；飞行单位照高度规则可停在塌陷格。

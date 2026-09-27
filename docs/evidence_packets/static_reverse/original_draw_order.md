# 原版绘制顺序：单位与站立物件谁挡住谁

> evidence: static-derived; resource-derived: PROCESS.DEF plane／objattr 常量、各关 OBS 的 obj_Plane／obj_Attribute · status: live · functions: 0x4300f0, 0x43ccf0, 0x43f31e, 0x443849, 0x446ad0, 0x45dd8a, 0x45e307, 0x45f5f7, 0x461479 · tools: ActorRuntime.gd, BattleSceneStage.gd, run_battle_scene_runtime_tests.gd, test_hsl_opening_positions.py · updated: 2026-09-25

lane R5-L4b，2026-09-25。R5-L4 普查发现 14 名单位的脚点落在可走格上，却被北侧建筑的前景贴图盖住。当时的判断是 z-order 遮挡而不是站错，但原版是否也这样画没有核实。本包用 r2 只读 `hsl01.exe`（SHA-256 `f0b5f835…0a70f7`）回答这个问题，没有开原作。

## 原版读法（static-derived）

| 位置 | 读法 |
| --- | --- |
| OBS 加载 `0x45dd8a` | `obj_Plane` 写进模板 +0xc。常量取自 PROCESS.DEF（resource-derived）：planeBG3..BG1 = 0..2，planeIcon = 3，planeObject1..40 = 4..43，planeEffect／Menu／Cursor 在其后。`obj_Attribute` 写进模板 +0x80（`objattrATTACKFLAG = 0x10000`） |
| 建对象 `0x45e307` | 复制 0xb0 字节模板（对象 +0xc 起初等于 plane），并把对象挂进它 plane（+0x58）的链表尾 |
| 每帧 `0x45f5f7` | 第一遍按 plane 0..max、各链表顺序调用每个对象的过程；第二遍同样顺序，逐个 `0x461479` 提交绘制 |
| 提交 `0x461479` | 按对象 **+0xc** 把绘制记录挂进 4096 个桶之一（`0x4bbbd4`／`0x4bbbd8` 头尾表；对象 +0 带 `0x80000000` 时挂到桶头，否则挂到桶尾）；`0x46141c` 按桶号从小到大画。**桶号就是深度** |
| 深度 `0x4300f0(y)` | `clamp(((y + 16) >> 5) − (camera_y >> 5), 0, 19) + 4`，即相对视口顶的格行，落在 planeObject1..20 |
| 站立物件过程 `0x43ccf0` | 每 tick 若对象 +0x80 没有 `0x10000`（objattrATTACKFLAG），则 +0xc = `0x4300f0(对象 y)`（EVEF 锚点 y）；带这一位的物件保持固定的 `obj_Plane` |
| 敌方过程 `0x43f300..0x43f31e`、玩家过程 `0x44382f..0x443849` | +0xc = `0x4300f0(脚点 y)`；`0x446ad0`（飞行位）为真时 **+10**。之后的两段全局状态分支会把深度封顶到 22 或再加 23（`0x4c1b00 & 0x1400000`／`0x1000000`，未读透） |

结论：
- 原版按 32 px 格行给单位和（非 ATTACKFLAG 的）站立物件排序，**行号小的先画**。单位脚点所在格行 < 建筑锚点格行时，建筑盖住单位。
- 同一桶内按 plane 链表的遍历顺序：plane 小者先画（玩家 planeIcon 3 早于 planeObject1 4 的物件和敌人）；同一 plane 内按建立顺序。
- 飞行单位的桶号多 10 行，所以会画在它南边近处的屋顶和树上面。
- `objattrATTACKFLAG` 的站立物件不参与 y 排序，而是固定在 `obj_Plane`。全游戏 OBS 共 100 个这样的物件（resource-derived），例如背景 planeBG1..3、云 planeObject40、火 planeObject19、39 关岩石2 planeIcon。

## 14 名单位逐一判定

判定脚本：`tools/test_hsl_opening_positions.py`，`test_building_overlaps_follow_the_original_draw_order`。它对每名脚点被建筑像素盖住的单位，按上面的规则求原版深度桶：单位取 `脚点格行 + 1`，飞行单位再加 10；建筑取 `(锚点 y + 16) >> 5`。建筑都不带 ATTACKFLAG，视口平移不改变两者的先后。

| 战斗 | 单位 | 格 | 建筑（锚点 y） | 原版 | 重制（R5-L4b 后） |
| --- | --- | --- | --- | --- | --- |
| 038 | actor034_1、actor034_2 | (13,10)、(14,10) | 墳墓01 38_HOUSE001（399） | 被盖（桶 11 < 12） | 被盖 |
| 059 | 琥、克羅蒂 | (32,24)、(31,23) | 門02 59_DOOR002（1208） | 被盖 | 被盖 |
| 075 | actor049_2 | (11,10) | 門02 57_DOOR002（424） | 被盖 | 被盖 |
| 576／577／578 | 雷特（**飞行**） | (16,10) | 墳墓01 38_HOUSE001（399） | **不被盖**（桶 11 + 10 = 21 > 12） | 不被盖（改前被盖） |
| 900 | 漢克斯、actor062_3、actor062_4、actor031_2、actor030_2 | (24,32)、(33,27)、(15,23)、(33,7)、(10,7) | 房子07／04／06／12／11 | 被盖 | 被盖 |
| ohm_village（1 关） | actor061_3 | (18,15) | 井 WELL001（576） | 被盖 | 被盖 |

11 名与原版一致：原版也画在建筑后面，不改行为。雷特 在 576–578 是飞行单位（技能书 traversal.flying），原版把他画在墳墓上面，重制原来把他画在下面。

## 重制

- `ActorRuntime.depth_index(foot_y, flying)`：z_index = 脚点 y，飞行单位加 `FLYING_DEPTH_ROWS × 32 = 320`。地图物件的 z_index 是其 EVEF 锚点 y（`BattleSceneStage`），与单位同一个深度域。
- `BattleSceneStage.sync_actor_depth` 在生成节点时和每次同步 loop 时，从 PlayLoop 单位的 `traversal.flying` 写 `flying_depth`。`actSetPlayerFly` 在战中改飞行时也随之更新。
- 这是共享绘制层的修改：全游戏所有飞行单位都适用，不按关卡处理。

## 边界

- 重制用像素 y，原版用 32 px 桶（provisional）。锚点落在单位同一格行内时（`锚点 y ∈ [行·32+16, 行·32+48)`），原版改按 plane／建立顺序决定先后，重制仍按像素决定。14 名都不在这种同桶情形。
- ATTACKFLAG 物件的固定 plane（云、火、背景、39 关岩石2）重制仍按锚点 y 排序，本包未逐一核对。
- 深度封顶到 22／再加 23 的两段全局状态分支未读透：推测与选中或演出状态有关，未建模。
- 同一桶内的建立顺序与 `0x45f0d1`（移到本 plane 链表尾）的调用时机未建模。

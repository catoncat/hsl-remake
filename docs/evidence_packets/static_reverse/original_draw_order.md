# 原版绘制顺序：单位与站立物件谁挡住谁

> evidence: static-derived; resource-derived: PROCESS.DEF plane／objattr 常量、各关 OBS 的 obj_Plane／obj_Attribute · status: live · functions: 0x4051d0, 0x4300f0, 0x43ccf0, 0x43f31e, 0x443849, 0x446ad0, 0x45dd8a, 0x45e307, 0x45f5f7, 0x461479 · tools: run_battle_scene_runtime_tests.gd, test_hsl_opening_positions.py · updated: 2026-09-27

## 结论

- 原版按 32 px 格行给单位和非 ATTACKFLAG 的站立物件排深度桶，行号小的先画；同桶内 plane 小者先画、同 plane 按建立顺序；飞行单位桶号 +10；ATTACKFLAG 物件固定在 `obj_Plane`（static-derived）。
- 重制 `ActorRuntime.depth_index` 以脚点像素 y 作 z_index、飞行单位 +320，地图物件以 EVEF 锚点 y 同域排序（`BattleSceneStage`）；脚点被北侧建筑盖住的 14 名单位中 11 名原版同样被盖，雷特（飞行）原版不被盖，重制已照做（static-derived）。
- 过程不改 +0xc 的物件停在 `obj_Plane` 桶：defProcObjectMove（`0x4051d0`）整段只读不写自身 +0xc。第 53 战开场的 繩子（planeObject1 = 桶 4）因此画在 緹娜 下面——她下绳时桶号 10..19，只有她站在视口最上一格行时才与绳子同桶（static-derived）。
- 重制 `ActorRuntime.fixed_plane_depth` 照此给 defProcObjectMove 物件定 z：planeObject1 及以下压在全部单位下、planeObject31 以上压在全部单位上、planeEffect* 起用 `EFFECT_Z`；改前繩子 z = 锚点 y + 241 = 705，盖住下绳途中脚点 y < 705 的 緹娜（static-derived）。
- 差异：像素 y 代替 32 px 桶、同桶先后、planeObject2..30 的固定 plane（相机相对行）与站立物件的 ATTACKFLAG 固定 plane 未建模（provisional）；深度封顶 22／+23 的全局状态分支未读透。

## 证据

`hsl01.exe`（SHA-256 `f0b5f835…0a70f7`），r2 只读。

### 原版读法（static-derived）

| 位置 | 读法 |
| --- | --- |
| OBS 加载 `0x45dd8a` | `obj_Plane` 写进模板 +0xc。常量取自 PROCESS.DEF（resource-derived）：planeBG3..BG1 = 0..2，planeIcon = 3，planeObject1..40 = 4..43，planeEffect／Menu／Cursor 在其后。`obj_Attribute` 写进模板 +0x80（`objattrATTACKFLAG = 0x10000`） |
| 建对象 `0x45e307` | 复制 0xb0 字节模板（对象 +0xc 起初等于 plane），并把对象挂进它 plane（+0x58）的链表尾 |
| 每帧 `0x45f5f7` | 第一遍按 plane 0..max、各链表顺序调用每个对象的过程；第二遍同样顺序，逐个 `0x461479` 提交绘制 |
| 提交 `0x461479` | 按对象 **+0xc** 把绘制记录挂进 4096 个桶之一（`0x4bbbd4`／`0x4bbbd8` 头尾表；对象 +0 带 `0x80000000` 时挂到桶头，否则挂到桶尾）；`0x46141c` 按桶号从小到大画。**桶号就是深度** |
| 深度 `0x4300f0(y)` | `clamp(((y + 16) >> 5) − (camera_y >> 5), 0, 19) + 4`，即相对视口顶的格行，落在 planeObject1..20 |
| 站立物件过程 `0x43ccf0` | 每 tick 若对象 +0x80 没有 `0x10000`（objattrATTACKFLAG），则 +0xc = `0x4300f0(对象 y)`（EVEF 锚点 y）；带这一位的物件保持固定的 `obj_Plane` |
| defProcObjectMove `0x4051d0`（过程表 `0x477c2c` slot 37） | 对象在 edi；全函数对 +0xc 只有读（`0x405401` 等），仅有的两处写 `0x4058e5`／`0x406aa8` 是把自己的 +0xc 抄给 `0x45e307` 新建的子对象；不调用 `0x4300f0`；38 个被调函数除建对象 `0x45e307` 与 `0x45e3ed` 外的 36 个（`0x42f880..0x42fcb0`、`0x45e5a6`、`0x45e785` 等）都不写 +0xc。所以对象一直留在建立时的 `obj_Plane` 桶 |
| 敌方过程 `0x43f300..0x43f31e`、玩家过程 `0x44382f..0x443849` | +0xc = `0x4300f0(脚点 y)`；`0x446ad0`（飞行位）为真时 **+10**。之后的两段全局状态分支会把深度封顶到 22 或再加 23（`0x4c1b00 & 0x1400000`／`0x1000000`，未读透） |

- 同一桶内按 plane 链表的遍历顺序：plane 小者先画（玩家 planeIcon 3 早于 planeObject1 4 的物件和敌人）；同一 plane 内按建立顺序。
- 飞行单位的桶号多 10 行，所以会画在它南边近处的屋顶和树上面。
- `objattrATTACKFLAG` 的站立物件不参与 y 排序，而是固定在 `obj_Plane`。全游戏 OBS 共 100 个这样的物件（resource-derived），例如背景 planeBG1..3、云 planeObject40、火 planeObject19、39 关岩石2 planeIcon。

### 第 53 战开场：繩子与 緹娜

| 时刻（STORY053） | 对象 | 深度 |
| --- | --- | --- |
| `actInsertStoryObject(obj_Story_Level53_Rope,656,464)` | 繩子 `53_ROPE001.SHP`，defProcObjectMove，planeObject1（resource-derived）；过程不改 +0xc，有无 ATTACKFLAG 都不影响深度 | 固定桶 4，挂在 planeObject1 链表 |
| `actWalkDispWait(SID_PLAYER1,1,0,32,2)` 后 → `actMoveDispWait(SID_PLAYER1,1,0,288,2)` | 緹娜（玩家，planeIcon 链表） | 脚点 y 448 → 736，行 `(y+16)>>5` = 14 → 23；按重制镜头 y ≈ 272（行 8）桶 = 10 → 19 |

桶 4 < 10..19：绳子先画、緹娜 后画。只有 緹娜 所在行 ≤ 视口顶行时才同为桶 4，此时按链表 planeIcon 3 先于 planeObject1 4，绳子反而在上；本段镜头下不出现。

### 脚点被建筑盖住的 14 名单位

判定规则：单位桶 `脚点格行 + 1`，飞行单位再加 10；建筑桶 `(锚点 y + 16) >> 5`。建筑都不带 ATTACKFLAG，视口平移不改变两者的先后。

| 战斗 | 单位 | 格 | 建筑（锚点 y） | 原版 | 重制 |
| --- | --- | --- | --- | --- | --- |
| 038 | actor034_1、actor034_2 | (13,10)、(14,10) | 墳墓01 38_HOUSE001（399） | 被盖（桶 11 < 12） | 被盖 |
| 059 | 琥、克羅蒂 | (32,24)、(31,23) | 門02 59_DOOR002（1208） | 被盖 | 被盖 |
| 075 | actor049_2 | (11,10) | 門02 57_DOOR002（424） | 被盖 | 被盖 |
| 576／577／578 | 雷特（**飞行**） | (16,10) | 墳墓01 38_HOUSE001（399） | **不被盖**（桶 11 + 10 = 21 > 12） | 不被盖（改前被盖） |
| 900 | 漢克斯、actor062_3、actor062_4、actor031_2、actor030_2 | (24,32)、(33,27)、(15,23)、(33,7)、(10,7) | 房子07／04／06／12／11 | 被盖 | 被盖 |
| ohm_village（1 关） | actor061_3 | (18,15) | 井 WELL001（576） | 被盖 | 被盖 |

11 名原版也画在建筑后面；雷特 在 576–578 是飞行单位（技能书 traversal.flying），原版把他画在墳墓上面。

## 重制接线

- `game/battle/runtime/ActorRuntime.gd` `depth_index(foot_y, flying)`：z_index = 脚点 y，飞行单位加 `FLYING_DEPTH_ROWS × 32 = 320`。地图物件的 z_index 是其 EVEF 锚点 y（`game/battle/scene/BattleSceneStage.gd`），与单位同一个深度域。
- `BattleSceneStage.sync_actor_depth` 在生成节点时和每次同步 loop 时，从 PlayLoop 单位的 `traversal.flying` 写 `flying_depth`；`actSetPlayerFly` 在战中改飞行时随之更新。全游戏所有飞行单位共用，不按关卡处理。
- `ActorRuntime.fixed_plane_depth(plane, fallback_z)`：plane 编号 ≤ 4（planeBG*、planeIcon、planeObject1）给 z 0..4（地图底图 z 0 之上、所有脚点 y 之下）；> 33（planeObject31 起）给 3900 + 编号；planeEffect* 及以后给 4000（= `StoryEffectObjects.EFFECT_Z`）；5..33 返回调用方原 z。`game/battle/runtime/opening/OpeningStoryObjects.gd` 的普通精灵路径对 `process == defProcObjectMove` 的剧情物件改用它（engRANGE 绳子展开后同样覆盖）。
- 重制截图：`ignored/ropez/after_053_slide1.png`、`after_053_slide2.png`（下绳途中，人在绳前），对照 `after_051.png`、`after_002.png`（地图物件与单位叠画不变）。
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_draw_order.md`（`ActorRuntime.gd`）。

## 复现

`PYTHONPATH=tools python3 -m unittest test_hsl_opening_positions.OpeningPositionTests.test_building_overlaps_follow_the_original_draw_order`（14 名单位的原版深度桶判定）。

## 边界

- 重制用像素 y，原版用 32 px 桶（provisional）。锚点落在单位同一格行内时（`锚点 y ∈ [行·32+16, 行·32+48)`），原版改按 plane／建立顺序决定先后，重制仍按像素决定。14 名都不在这种同桶情形。
- ATTACKFLAG 物件的固定 plane（云、火、背景、39 关岩石2）重制仍按锚点 y 排序：地图物件的 obj_Attribute 导入器没保留，本包未逐一核对。
- planeObject2..30 的固定 plane 与 y 桶的比较取决于镜头行（桶 = 视口相对行），重制未建模，这类物件仍用锚点 y。
- defProcEffectProcess1／defProcDropRain／defProcFireSmoke／defProcScreenFlash 等过程是否改写 +0xc 未读；重制对它们维持原有 z（效果类多为 EFFECT_Z）。
- 固定桶 4 的物件与视口最上一格行的单位同桶时，原版按 plane 链表让玩家先画、物件在上；重制把 planeObject1 物件一律压在单位下。
- 深度封顶到 22／再加 23 的两段全局状态分支未读透：推测与选中或演出状态有关，未建模。
- 同一桶内的建立顺序与 `0x45f0d1`（移到本 plane 链表尾）的调用时机未建模。

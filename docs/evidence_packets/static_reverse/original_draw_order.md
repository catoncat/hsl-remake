# 原版绘制顺序：单位与站立物件谁挡住谁

> evidence: static-derived; resource-derived: PROCESS.DEF plane／objattr 常量、各关 OBS 的 obj_Plane／obj_Attribute · status: live · functions: 0x4051d0, 0x4071e0, 0x410670, 0x4300f0, 0x43ccf0, 0x43f31e, 0x442a90, 0x443849, 0x446ad0, 0x45dd8a, 0x45e307, 0x45f5f7, 0x461479 · tools: run_battle_scene_runtime_tests.gd, test_hsl_opening_positions.py · updated: 2026-09-28

## 结论

- 原版按 32 px 格行给单位和非 ATTACKFLAG 的站立物件排深度桶，行号小的先画；同桶内 plane 小者先画、同 plane 按建立顺序；飞行单位桶号 +10；ATTACKFLAG 物件固定在 `obj_Plane`（static-derived）。
- 重制 `ActorRuntime.depth_index` 照原版算行桶：`clamp(((y+16)>>5) − 镜头顶行, 0, 19) + 4`，飞行 +10，z = (桶 + 镜头顶行)·32 + plane（玩家 planeIcon 3、敌人 planeObject1 4），同桶 plane 小者先、同 plane 按节点顺序；站立物件以锚点行桶 + obj_Plane 同域排序（`ActorRuntime.stand_object_z`）；脚点被北侧建筑盖住的 14 名单位中 11 名原版同样被盖，雷特（飞行）原版不被盖，重制已照做（static-derived）。
- 过程不改 +0xc 的物件停在 `obj_Plane` 桶：defProcObjectMove（`0x4051d0`）整段只读不写自身 +0xc。第 53 战开场的 繩子（planeObject1 = 桶 4）因此画在 緹娜 下面——她下绳时桶号 10..19，只有她站在视口最上一格行时才与绳子同桶（static-derived）。
- 重制 `ActorRuntime.apply_object_depth` 给 defProcObjectMove 物件与带 ATTACKFLAG 的站立物件定固定 plane：planeObject1 以下压在全部单位下，planeObject1..30 = 当前视口的同号桶（`refresh_fixed_planes` 每帧按镜头顶行换算，随镜头滚动与单位交错），planeObject31 以上压在全部未抬起单位上，planeEffect* 起用 `EFFECT_Z`；繩子 = 桶 4，下绳的 緹娜 桶 10..19 画在其上（static-derived）。
- 单位过程算完行桶与飞行 +10 后还有两段全局状态分支（static-derived）：①`[0x4c1b00] & 0x1400000`（战斗特写或状态窗／仓库窗打开期间、或魔法效果阶段）时，桶号超过 22 的飞行单位若不在施法脚印里就压回 22；②`& 0x1000000`（魔法效果阶段）时，飞行单位先压回 22，再给施法脚印内的单位和摆着施法姿势的单位 +23——施法者与目标在效果放完前画在全部 y 排序的单位与站立物件上面。
- 重制 `BattleSceneStage.sync_cast_depth` 在地图 `magic:` 切入播放期间，给效果格内的单位与施法姿势中的单位置 `ActorRuntime.cast_lift`（桶 +23，z 进 `CAST_LIFT_Z` 带：全部行桶 z 之上、planeObject31 固定带之下，带内按桶与 plane），并给全部飞行单位置 `flying_cap`；其他切入（攻方特写，对应 0x400000）期间目标格外的飞行单位置 `flying_cap`（桶 > 22 压回 22）（static-derived）。
- 同桶先后：`0x461479` 对象 +0 带 `0x80000000` 时挂桶头，否则挂桶尾；单位（初始化 `or 0x2c000000`）与站立物件都不带这一位，所以同桶按第二遍遍历顺序——plane 小者先画，同 plane 按链表顺序（static-derived）。
- 差异：站立物件锚点行桶不按视口夹紧（只影响锚点在视口外的物件）、抬起桶 27..46 与 planeObject24..40 不交错、状态窗／仓库窗期间的飞行封顶未建模（provisional）。

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
| 敌方过程 `0x43f300..0x43f3a5`、玩家过程 `0x44382f..0x4438d4` | +0xc = `0x4300f0(脚点 y)`；`0x446ad0`（飞行位）为真时 **+10**，随后两段全局状态分支，见下节 |

### 两段全局状态分支（static-derived）

敌方与玩家过程逐条同形（敌方 `0x43f311..0x43f3a5` 用 ebp 指对象、esi = 22；玩家 `0x443840..0x4438d4` 用 esi 指对象、edi = 22）。

| 步 | 条件 | 动作 |
| --- | --- | --- |
| 1 | 飞行（`0x446ad0` 读单位记录 +0xa0 位 0） | +0xc += 10，飞行标记 = 1 |
| 2 | 飞行，且 `[0x4c1b00] & 0x1400000`，且 +0xc > 22，且 `0x410670(对象)` = 0 | +0xc = 22 |
| 3 | `[0x4c1b00] & 0x1000000`，且飞行标记，且 +0xc > 22 | +0xc = 22（不看脚印） |
| 4 | `& 0x1000000`，且 `0x410670(对象)` ≠ 0 | +0xc += 23；`[0x4c1b2c]` 非 0 时再调 `0x43db60(对象)` |
| 5 | `& 0x1000000`，且 `0x410670` = 0 | 字节 +0x34 = 0；对象 +0x80 带 `0x1000` 时 +0xc += 23 |

| 读出的量 | 读法 |
| --- | --- |
| `0x410670(对象)` 施法脚印 | 以对象 +4／+8（像素 x／y）查字节格 `*0x4c1b4c`（`0x410600`：`(x>>5)+宽/2−[0x4c6d44]`、`(y>>5)+高/2−[0x4c6d40]`，越界读 0）。单位记录（`0x4c1bc8` 表，+0xa4 为下标，步长 0x1fc）+0x2c 字非 0 时查自身与周围 8 格，任一非 0 即真；为 0 只查自身格。`*0x4c1b4c` 是选目标时 `0x4100e0` 写入的光标格效果脚印（[射程格](original_range_cells.md)） |
| 位 `0x1000000` 魔法效果阶段 | 只由共用施法例程 `0x442a90`（魔法与辅助魔法，玩家与 AI 同一函数）写：阶段字 `[0x4c432c]` 状态 4（`0x442c71`）、7（`0x442cef`）、0x17（`0x442f4d`）、0x19（`0x442ff1`）置位，状态 9（`0x442daf`，镜头回施法者）与 0x1c（`0x44327c`）清除，与 [游戏光标](../runtime_observations/game_cursor/README.md) 的隐藏位读法一致 |
| 位 `0x400000` | 攻方特写程序 `0x401c20`（`0x401c6b`）与 AnimalDefense `0x4038a0`（`0x4038dd`）以 `or 0xc00000` 置位，`0x403089`／`0x404d9d`／`0x406fc2`（`and 0xff3fffff`）、`0x4029b7` 清除；状态窗过程（`0x43863f` 置、`0x4389f3` 清）与仓库窗 `0x4289e0` 一段（`0x428d2b` 置、`0x428f15` 清）也单独置位。全 EXE 别无写这一位的地方 |
| 对象 +0x80 位 `0x1000` 施法姿势 | `0x4071e0` 以 `0x446c40(对象, …, 7, 3)` 换 use_magic 姿势后置位（+0x92 = 40、+0x98 = 0）；调用者为地图施法 `0x402fd1`／`0x403128`、用药 `0x4449a7`、AI `0x440366`／`0x4404c7` 等；姿势播完由单位过程（玩家 `0x443767`、敌方 `0x43f243`）清除，`0x407230` 改置 0x800 时也清 |
| 站立物件 | `0x43ccf0` 只在 `0x43ce77` 写 +0xc，没有这两段分支，效果阶段不抬 |

所以：魔法效果阶段施法者（摆姿势时）与脚印内单位的桶号落在 27..45，高于所有 y 排序的单位（≤ 23）与站立物件（≤ 23）；脚印外的飞行单位不超过 22。特写或状态窗／仓库窗期间只剩第 2 步：脚印外的飞行单位压回 22。

### 同桶先后（static-derived）

`0x461479` 读对象 +0：带 `0x80000000` 挂桶头，否则挂桶尾。单位初始化时 `or 0x2c000000`（敌方 `0x43f04f`、玩家 `0x44356b`），站立物件过程 `0x43ccf0` 只加 `0x1000000`／`0x40000000`／`0x24000000`，都不带 `0x80000000`，所以同桶按 `0x45f5f7` 第二遍的遍历顺序挂尾：plane 小者先画，同 plane 按链表顺序（建立顺序，`0x45f0d1` 移到链表尾时改变）。

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

- `game/battle/runtime/ActorRuntime.gd` `depth_bucket(foot_y, flying, lifted, capped)`：原版桶号，`clamp(((y+16)>>5) − view_top_row, 0, 19) + 4`，飞行 +10，`capped` 且飞行桶 > 22 压回 22，`lifted` +23。`depth_index(…, plane)`：未抬起 z = `bucket_z(桶, plane)` = (桶 + view_top_row)·32 + plane（`BUCKET_Z` 32，plane 夹到 0..31），即世界行桶；`view_top_row`（camera_y >> 5）由 `BattleSceneRuntime.sync_view_depth` 在镜头推进后、单位 `_process` 之前每帧写入。`stand_object_z(anchor_y, plane)`：站立物件的世界行桶 z，与单位同域；`BattleSceneStage` 地图物件、`MapObjectDrift` 云影、剧情物件与特效循环帧都用它。
- `lifted` 为真时 z = `CAST_LIFT_Z`（2700）+ (桶 − 27)·32 + plane，封在 3899 以下——全部世界行桶 z（≤ 2698，60 行地图最低处飞行单位 (60 + 18)·32 + 31 仍在带下）之上、planeObject31 固定带之下，CASTBUCKET 的施法阴影在 `CAST_LIFT_Z − 1`。`BattleSceneStage.sync_cast_depth` 每帧（`BattleSceneRuntime._process` 在 `BattlePresentation.refresh` 之后）判断切入队首：地图 `magic:` 片段（位 `0x1000000` 的阶段）给 `SkillTargetRules.effect_cells(施法中心)` 格内的单位与 `is_posing()`（use_magic 姿势 = +0x80 位 `0x1000`）的单位置 `cast_lift`、全部单位置 `flying_cap`；其他切入（攻方特写，位 `0x400000`）给目标格以外的单位置 `flying_cap`；无切入全清。
- `BattleSceneStage.sync_actor_depth` 在生成节点时和每次同步 loop 时，从 PlayLoop 单位的 `traversal.flying` 写 `flying_depth`；`actSetPlayerFly` 在战中改飞行时随之更新。全游戏所有飞行单位共用，不按关卡处理。
- `ActorRuntime.fixed_plane_depth(plane, fallback_z)`：plane 编号 < 4（planeBG*、planeIcon）给 z 0..3（地图底图 z 0 之上、所有行桶之下）；4..33（planeObject1..30）给 `bucket_z(编号, 编号)`；> 33 给 3900 + 编号；planeEffect* 及以后给 4000（= `StoryEffectObjects.EFFECT_Z`）。`apply_object_depth(node, anchor_y, plane, fixed)`：`fixed`（defProcObjectMove，或 obj_Attribute 带 objattrATTACKFLAG）用固定 plane，4..33 的节点进组 `fixed_plane_depth`，`refresh_fixed_planes` 每帧按镜头顶行重算；否则 `stand_object_z`。站立物件的 `plane` 与 `obj_Attribute` 由种子（`tools/hsltools/levels/seed.py`）与地图物件清单（`map_objects.py`）从 OBS 模板带出。玩家单位 `depth_plane` = planeIcon 3，其余 planeObject1 4（`sync_actor_depth`，[自动成长](original_auto_growth.md) 的出生顺序读法）。
- 重制截图：`ignored/ropez/after_053_slide1.png`、`after_053_slide2.png`（下绳途中，人在绳前），对照 `after_051.png`、`after_002.png`（地图物件与单位叠画不变）。
- provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_draw_order.md`（`ActorRuntime.gd`）。

## 复现

`PYTHONPATH=tools python3 -m unittest test_hsl_opening_positions.OpeningPositionTests.test_building_overlaps_follow_the_original_draw_order`（14 名单位的原版深度桶判定）。

## 边界

- 站立物件的行桶用世界行、不按视口夹紧（provisional）：锚点在视口上方或下方 19 行以外的物件，原版夹到桶 4／23，重制保持世界行；只影响锚点在视口外而图像伸进视口的高物件。
- defProcEffectProcess1／defProcDropRain／defProcFireSmoke／defProcScreenFlash 等过程是否改写 +0xc 未读；重制对它们维持原有 z（效果类多为 EFFECT_Z）。
- 飞行单位封顶 22：重制在切入（特写）与魔法效果阶段封顶；状态窗、仓库窗期间的封顶未建模（重制窗口是全屏覆盖层）；攻方特写的脚印取目标格（provisional）。
- 重制效果阶段取切入队首的 `magic:` 片段整段（provisional）；原版从状态 4（镜头滚向目标）到状态 9（镜头回施法者）。
- 单位记录 +0x2c 非 0（大体型）时原版按 3×3 查脚印，重制只查单位所在格；`0x43db60`（`[0x4c1b2c]` 非 0 时对脚印内单位）与字节 +0x34 未读。
- 原版抬起后的桶 27..45 与 planeObject24..40 固定 plane 物件交错，重制把抬起的单位一律放在 planeObject31 固定带之下。
- 同一桶同一 plane 内重制按 Godot 节点顺序（单位层与物件层分属不同父节点），原版按建立顺序；`0x45f0d1`（移到本 plane 链表尾）的调用时机未建模。

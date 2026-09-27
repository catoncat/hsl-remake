# 游戏光标：原版红宝石权杖（CURSOR01–10）画在游戏画面里、每个画面都有、每 6 tick 换一帧、热点在宝石

> evidence: resource-derived: 155 个原版 OBS 的 object 2「游標」字段逐项相同（SHAPE\CURSOR01.SHP、obj_Shape_Number 10、obj_Shape_Delay 5、planeCursor、defProcCursor），CURSOR01–10.SHP 尺寸与 draw origin; static-derived: 0x430410 defProcCursor 每 tick 把对象放到鼠标坐标、0x45e5a6 按 delay+1 tick 换帧、窗口过程 WM_SETCURSOR → 0x458650 SetCursor(NULL) 藏起 Windows 指针（光标只由游戏画进画面）、`[0x4c1b00] & 0x1800000` 与持物 `[0x4c1ce4]`（0x430310 画物品图标）时权杖隐藏; runtime-measured: 2026-09-24 原版录屏标题／战斗／状态页／敌方回合／系统菜单均见同一权杖，CURSOR10 每 1.151 s 出现一次；2026-09-27 原版玩家第 1 場「棄卒」（LEVEL051）雷歐納德用回復藥选目标时指针处是回復藥图标、无权杖 · status: live · functions: 0x403089, 0x4038a0, 0x406fc2, 0x430310, 0x430410, 0x437020, 0x439997, 0x442a90, 0x444a5c, 0x444ab2, 0x444aba, 0x456cf0, 0x458650, 0x45e5a6 · tools: hsl_video_events.py, run_ui_class_contract_tests.gd · updated: 2026-09-27

## 结论

- 原版：光标是 planeCursor 上的 OBS 对象 2（CURSOR01–10，热点＝SHP draw origin，落在红宝石），每 tick 站到鼠标上、6 tick 换一帧、60 tick 一圈，由游戏画进 640×480 画面，Windows 指针被 `SetCursor(NULL)` 藏起；只有「隐藏」（施法效果阶段、战斗特写）与「持物时换成物品图标」两种变化（resource-derived；static-derived；runtime-measured）。
- 重制：autoload `game/cursor/GameCursor.gd` 在 root 视口最上层 CanvasLayer 画同一套十帧，随画面缩放；`BattlePresentation.hides_game_cursor()` 与持物图标组照原版隐藏权杖（static-derived）。
- 差异：录屏没有大地图与城镇，那两处沿用 OBS 普查结论；比系统硬件光标多约一帧延迟，与原版画在帧里相同（一致）。

## 证据

### 1. 资源：一个对象、十帧、同一套字段遍布全部 OBS

`python3 tools/hsl.py generate game_cursor` → `content/imported/hsl/shared/game_cursor/`。`DATA\OBJ-000.OBS`（标题）与各战斗、剧情、大地图 OBS 的 `[Object] obj_code=2`：

| 字段 | 值 |
| --- | --- |
| obj_name | 游標 |
| obj_Shape_Name／Number／Delay | `SHAPE\CURSOR01.SHP`／10／5 |
| obj_Plane | planeCursor（最上层，盖住所有菜单与面板） |
| obj_Process_Code | defProcCursor |

定义 object 2 的 OBS 共 155 个，字段解析后 0 个不同（`obs_disagreements: []`），一个光标服务所有画面。十帧是一支转动翅膀的权杖，尖端是红宝石：

| 帧 | 尺寸 | draw origin（热点） |
| --- | --- | --- |
| CURSOR01、02、10 | 31×34 | (8,3) |
| CURSOR03、09 | 27×34 | (6,3) |
| CURSOR04–08 | 24×34 | (4,3) |

每帧热点处的像素都是红宝石（RGB 197–255,0,0）；帧 1→10 宝石逐渐变亮再变暗，是翅膀转一圈时的闪光。

### 2. 静态：跟着鼠标、6 tick 一帧、热点即 draw origin

- `0x430410`（defProcCursor，处理槽 4）：每 tick 把对象 +4／+8 设为鼠标坐标 `[0x4c1a8c]／[0x4c1a90]`。
- 形状绘制在「对象位置 − SHP draw origin（头部 0x1c／0x20）」，所以 draw origin 就是指向点。
- `0x45e5a6`：满 `obj_Shape_Delay + 1` = 6 tick 换下一帧，第十帧后回到第一帧，一圈 60 tick（与第 51 战火把同一读法，`tools/hsltools/assets/fire_animation.py`）。
- **画进画面，不是 Windows 光标**：窗口过程 `0x456cf0` 把 WM_SETCURSOR（0x20，字节表 0x457000 第 4 项）交给 `0x458650`：除非 `[0x4c22d8]` 位 0，就 `SetCursor(NULL)` 并返回 TRUE；导入表里 `LoadCursorA` 只在 `0x4572a0` 注册窗口类时出现一次，`SetCursor` 只有这一处。cnc-ddraw 放大窗口时光标跟画面一起放大。
- **隐藏与持物**（`0x430410` 全文）：把对象放到鼠标后，若 `[0x4c1b00] & 0x1800000` 就把形状设为 0xffff（不画）并返回；否则按鼠标键 `[0x4c6398]`（位 0／位 1／0x10000／0x20000 → 0x1000000／0x800000／0x40000／0x20000）加 0x2000000 标到鼠标下的对象（`0x46cf98` 找对象、`0x46d05a` 取实体，写 +0x80），再调 `0x430310`：持物 `[0x4c1ce4]` 非 0 时在鼠标处把该物品图标（表 `0x4c30a0`，按物品记录 +0xc 取）画到 plane 0x38（`0x460799`）并返回非 0，权杖形状设为 0xffff；都不成立时，若刚才隐藏过就从 +0x32／+0x7a／+0x7e 恢复形状与帧，再 `0x45e5a6` 换帧。原版没有「可选目标／不可用」等换形。
- **用药选目标时持物**：用药窗（mode6）点道具 `0x439997` → `0x437020(成员, 格)` 把道具从格里取进 `[0x4c1ce4]`（音效 399 TAKEUP01）；玩家状态 `0x4448f4` 见 `[0x4c1ce4]` 非 0 即建用药范围，选目标期间 `0x430310` 在指针处画该道具图标、权杖不画；确认那一 tick 进姿势（`0x4449a7`），下一 tick state106 `0x444ab2` 调 `0x409e40` 结算、`0x444aba` 清 `[0x4c1ce4]`——图标只多留一 tick；右键取消 `0x444a5c..0x444a94` 经 `0x436e30` 放回并在 `0x444a81` 清零。悬停到单位上 `0x4449bb` 只开信息窗（`0x43b4e0` mode 3），图标不变。
- 隐藏位 0x1000000 只由共用施法例程 `0x442a90`（魔法与辅助魔法效果阶段，玩家与 AI 同一函数，见 [施法覆盖层](../../static_reverse/original_cast_overlays.md)）写：状态字 `[0x4c432c]` 经字节表 `0x443304` → 跳表 `0x4432c8` 分派，状态 4（`0x442c71`）、7（`0x442cef`，随后 `0x423a20` 起效果脚本）、0x17（`0x442f4d`）、0x19（`0x442ff1`）置位，状态 9（`0x442daf`，镜头回施法者 `[0x4c1cec]`）与 0x1c（`0x44327c`）清除——从镜头滚向目标起、到效果放完镜头回施法者止，权杖不画。全 EXE 160 处 `[0x4c1b00]` 引用里别无写 0x1000000 的地方。
- 隐藏位 0x800000 与 0x400000 一起（`or 0xc00000`）由 AnimalDefense `0x4038a0` 在 `0x4038dd` 置位（战斗特写守方对象开演时），`0x403089`（`and 0xff3fffff`）与 `0x406fc2` 清除——特写期间权杖不画。
- 恢复（`0x4304e7..0x430502`）：上一 tick 形状字是 0xffff 时，`+0x30 = +0x32`（CURSOR01）、`+0x78 = +0x7a`、`+0x7c = +0x7e`——从第一帧重新转、延迟计数重置；隐藏期间不调 `0x45e5a6`，翅膀不转。

### 3. 录屏：每个画面都是同一支权杖（runtime-measured，2026-09-24 原版录屏）

游戏区 `crop=1280:960:112:140`，PTS 秒定位。`hsl_video_events.py sprite` 用十帧 PNG 在 17–23 s 地图区（box 200,230,120,100）模板匹配；光标停在逻辑 (246,281) 不动的 19.8–23.0 s 里，CURSOR10 起点 19.920／21.071／22.222 s、CURSOR01 起点 19.803／20.971／22.122 s，即每 1.151–1.168 s 转一圈（≈ 60 tick × 19.2 ms，本机 tick 实测 19.4 ms 见 [tick 率](../original_tick_rate/README.md)）。窄帧 CURSOR04–07 彼此只差翅膀几像素，单帧分类不可靠，只用首末帧的周期。

| PTS（s） | 画面 |
| --- | --- |
| 6.0 | 标题（圆盘右下；此时 macOS 箭头另在圆盘上，是宿主指针与 Wine 内光标不同步） |
| 89.0 | 状态页（道具栏右侧） |
| 91.0 | 蓝色移动格上 |
| 93.5、110.9 | 敌方回合地图上——光标**没有**消失（录屏索引 88.5–95.8 段模型写的「红剑光标消失」与像素不符，不采用） |
| 575.0 | 系统菜单右侧 |

2026-09-27 原版截帧（玩家第 1 場 · 棄卒（LEVEL051），雷歐納德 道具 → 回復藥）：选道具前道具窗上是权杖；选中回復藥后，范围外指针与悬停雷歐納德本格时指针处都是回復藥布袋图标、无权杖，雷歐納德周围画十字五格蓝框，悬停时下方开雷歐納德信息窗；点下确认后下一帧起图标、蓝框、信息窗全部消失，镜头留在雷歐納德处，随后移到城门转入敌方行动。

### 4. 重制实测（runtime-measured，重制侧）

本机 Retina，光标在屏幕上的实际像素（CURSOR01 31×34）：

| 窗口 | 旧做法（`Input.set_custom_mouse_cursor` 硬件光标，按窗口像素÷640 放大、不小于 1） | 现做法（画进画面） |
| --- | --- | --- |
| 480×360 | 62×68（缩放夹到 1，再被 Retina 翻倍） | 23×26（画面 0.75 倍） |
| 640×480 | 62×68 | 31×34 |
| 1280×960（默认） | 124×136（缩放 2，再被 Retina 翻倍） | 62×68（画面 2 倍） |

窗口化截帧（1280×960 与 640×480，第 51 战首控十帧依次指向选中角色格中心逻辑 (368,272)）：两种窗口的 root 画面都是 640×480、宝石像素都在 (368,272)、命中测试读到同一格 (15,17)，failures=0。第 10 关自动对局战斗特写中无权杖；歐姆村武器店拿起長劍后指针处只见長劍图标。

## 重制接线

- `game/cursor/GameCursor.gd`（autoload）：root 视口 CanvasLayer 1025（高于内嵌弹窗画布 1024，对应 planeCursor）上的 Sprite2D，源尺寸、最近邻；stretch mode viewport 下 root 视口坐标就是逻辑坐标，热点落在指针所在逻辑像素。位置每帧取 `get_mouse_position`；always 处理，换帧只在树运行时走（每 `OriginalTick.TICK_SECONDS` 一 tick、6 tick 一帧）。
- 系统指针只在「窗口有焦点且指针在画面内」时隐藏（`MOUSE_MODE_HIDDEN`，对应 `SetCursor(NULL)`）；信箱黑边、窗外、失焦时系统箭头回来、权杖不画；启动后第一次移动指针前不画（`_pointer_moved`）。
- 隐藏：`GameCursor.suppressed()` 每帧问组 `game_cursor_hiders`；`BattlePresentation.hides_game_cursor()` 在战斗特写或地图魔法效果播放（`cutin.busy()`，0x800000／0x1000000）时为真；剧本演出（落雷、噴人沼氣、对白）原版不置这两位，权杖照常显示。
- 持物：战利品面板与商店的持物图标（`hand_icon`，以物品 SHP draw origin 为锚）加入组 `game_cursor_held_items`，任一可见时权杖不画；隐藏期间翅膀不转，再显示从 CURSOR01 开始。OPT-CURSOR=系統硬體游標 时同样条件下隐藏系统指针。战斗道具面板用药选格页（`BattleItemPanel._show_use_pick`，地图选格见 [用药演出](../../static_reverse/original_item_use_presentation.md#重制接线)）把选中道具图标 `HeldItem` 挂在页根、每帧跟指针、同组，确认、右键放回或面板隐藏即消失。
- provenance 头写 `static-derived docs/evidence_packets/runtime_observations/game_cursor/README.md`。

## 复现

`python3 tools/hsl.py check game_cursor`（清单字段、十帧、`frame_ticks = delay + 1`、PNG 哈希、155 个 OBS 无分歧）；运行侧 `tools/godot.sh --headless --script tests/run_ui_class_contract_tests.gd`。窗口化截帧驱动已退役，回执为历史记录。

## 边界

- 录屏没有大地图与城镇；那两处用同一对象的依据是 §1 的 OBS 普查。
- 帧 1→10 的宝石明暗只由 SHP 像素给出，没有单独的闪光程序。
- 用药持物：原版确认后下一 tick 清持物，重制确认当帧撤，差一 tick；原版点道具即持物、窗口收起期间已画图标，重制页面滑出后才挂（provisional）；给予流程原版同样经 `[0x4c1ce4]` 持物（`0x438c86`），重制给予先选对象、未接持物图标。

# 游戏光标：原版红宝石权杖（CURSOR01–10）画在游戏画面里、每个画面都有、每 6 tick 换一帧、热点在宝石

> evidence: resource-derived: 155 个原版 OBS 的 object 2「游標」字段逐项相同（SHAPE\CURSOR01.SHP、obj_Shape_Number 10、obj_Shape_Delay 5、planeCursor、defProcCursor），CURSOR01–10.SHP 尺寸与 draw origin; static-derived: 0x430410 defProcCursor 每 tick 把对象放到鼠标坐标、0x45e5a6 按 delay+1 tick 换帧、窗口过程 WM_SETCURSOR → 0x458650 SetCursor(NULL) 藏起 Windows 指针（光标只由游戏画进画面）、`[0x4c1b00] & 0x1800000` 与持物 `[0x4c1ce4]`（0x430310 画物品图标）时权杖隐藏; runtime-measured: 2026-09-24 用户录屏标题／战斗／状态页／敌方回合／系统菜单均见同一权杖，CURSOR10 每 1.151 s 出现一次 · status: live · functions: 0x403089, 0x4038a0, 0x406fc2, 0x430310, 0x430410, 0x442a90, 0x456cf0, 0x458650, 0x45e5a6 · tools: hsl_video_events.py · updated: 2026-09-27

lane R7-CAM（2026-09-25）。用户实玩：重制版的鼠标是系统箭头，原版是游戏内的红宝石权杖。本包回答「原版光标是什么、何时出现、怎样动、指向点在哪」，并写重制怎样接；lane CURSOR（2026-09-26，用户实玩：小窗口下光标显得非常大）补读隐藏与持物分支、把重制改成画进画面。原版录屏：`录屏2026-09-24 中午12.03.22.mov`（用户录屏，私有档案）（游戏区 `crop=1280:960:112:140`，PTS 秒定位）；帧与临时脚本在 lane worktree 的 `ignored/cam/`，不入库。

## 1. 资源：一个对象、十帧、同一套字段遍布全部 OBS

**资源**（`python3 tools/hsl.py generate game_cursor` → `content/imported/hsl/shared/game_cursor/`）：`DATA\OBJ-000.OBS`（标题）与各战斗、剧情、大地图 OBS 的 `[Object] obj_code=2` 都是

| 字段 | 值 |
| --- | --- |
| obj_name | 游標 |
| obj_Shape_Name／Number／Delay | `SHAPE\CURSOR01.SHP`／10／5 |
| obj_Plane | planeCursor（最上层，盖住所有菜单与面板） |
| obj_Process_Code | defProcCursor |

导入器读完所有定义了 object 2 的 OBS：155 个，字段解析后 0 个不同（`obs_disagreements: []`），所以一个光标服务所有画面，没有按场景换图。十帧是一支转动翅膀的权杖，尖端是红宝石：

| 帧 | 尺寸 | draw origin（热点） |
| --- | --- | --- |
| CURSOR01、02、10 | 31×34 | (8,3) |
| CURSOR03、09 | 27×34 | (6,3) |
| CURSOR04–08 | 24×34 | (4,3) |

每帧热点处的像素都是红宝石（RGB 197–255,0,0，`run_game_cursor_tests` 逐帧核对）。帧 1→10 宝石也逐渐变亮再变暗，是翅膀转一圈时的闪光。

## 2. 静态：跟着鼠标、6 tick 一帧、热点即 draw origin

- `0x430410`（defProcCursor，处理槽 4）：每 tick 把对象 +4／+8 设为鼠标坐标 `[0x4c1a8c]／[0x4c1a90]`。
- 形状绘制在「对象位置 − SHP draw origin（头部 0x1c／0x20）」，所以 draw origin 就是指向点——十帧宽度不同但热点都落在宝石上。
- `0x45e5a6`：对象每 tick 计数，满 `obj_Shape_Delay + 1` = 6 tick 换下一帧，第十帧后回到第一帧：一圈 60 tick（与第 51 战火把的读法相同，见 `tools/hsltools/assets/fire_animation.py`）。
- **画进画面，不是 Windows 光标**：窗口过程 `0x456cf0` 把 WM_SETCURSOR（0x20，字节表 0x457000 第 4 项）交给 `0x458650`：除非 `[0x4c22d8]` 位 0，就 `SetCursor(NULL)` 并返回 TRUE——游戏窗口上没有 Windows 指针；导入表里 `LoadCursorA` 只在 `0x4572a0` 注册窗口类时出现一次，`SetCursor` 只有这一处。权杖是 planeCursor 上的普通 OBS 对象，由游戏自己的平面绘制画进 640×480 画面，所以 cnc-ddraw 放大窗口时光标跟画面一起放大。
- **隐藏与持物**（lane CURSOR 读 `0x430410` 全文）：把对象放到鼠标后，若 `[0x4c1b00] & 0x1800000` 就把形状设为 0xffff（不画）并返回；否则按鼠标键 `[0x4c6398]`（位 0／位 1／0x10000／0x20000 → 0x1000000／0x800000／0x40000／0x20000）加 0x2000000 标到鼠标下的对象（`0x46cf98` 找对象、`0x46d05a` 取实体，写 +0x80），再调 `0x430310`：若持物 `[0x4c1ce4]` 非 0，就在鼠标处把该物品的图标（表 `0x4c30a0`，按物品记录 +0xc 取）画到 plane 0x38（`0x460799`）并返回非 0，权杖形状设为 0xffff；都不成立时，若刚才隐藏过就从 +0x32／+0x7a／+0x7e 恢复形状与帧，再 `0x45e5a6` 换帧。所以原版只有一套权杖形状：没有「可选目标／不可用」等换形，只有「隐藏」与「持物时换成物品图标」两种变化。
- 隐藏位 0x1000000 只由共用施法例程 `0x442a90`（魔法与辅助魔法的效果阶段，玩家与 AI 同一函数，见 [施法覆盖层](../../static_reverse/original_cast_overlays.md)）写：状态字 `[0x4c432c]` 经字节表 `0x443304` → 跳表 `0x4432c8` 分派，状态 4（`0x442c71`）、7（`0x442cef`，随后 `0x423a20` 起效果脚本）、0x17（`0x442f4d`）、0x19（`0x442ff1`，同样起效果脚本）置位，状态 9（`0x442daf`，镜头回施法者 `[0x4c1cec]`）与 0x1c（`0x44327c`）清除——即从镜头滚向目标起、到效果放完镜头回施法者止，权杖不画。全 EXE 160 处 `[0x4c1b00]` 引用里别无写 0x1000000 的地方（lane FXQUEUE）。
- 隐藏位 0x800000 与 0x400000 一起（`or 0xc00000`）由 AnimalDefense `0x4038a0` 在 `0x4038dd` 置位——战斗特写（切入画面）的守方对象开演时；`0x403089`（`and 0xff3fffff`）与 `0x406fc2` 清除，即特写期间权杖不画（lane FXQUEUE）。
- 恢复（`0x4304e7..0x430502`）：上一 tick 形状字是 0xffff 时，`+0x30 = +0x32`（CURSOR01）、`+0x78 = +0x7a`、`+0x7c = +0x7e`——权杖从第一帧重新转、延迟计数重置；隐藏期间不调 `0x45e5a6`，翅膀不转。

## 3. 录屏：每个画面都是同一支权杖

**像素**：`hsl_video_events.py sprite` 用十帧 PNG 在 17–23 s 的地图区（box 200,230,120,100）做模板匹配；光标停在逻辑 (246,281) 不动的 19.8–23.0 s 里，CURSOR10 起点 19.920／21.071／22.222 s、CURSOR01 起点 19.803／20.971／22.122 s，即每 1.151–1.168 s 转一圈（≈ 60 tick × 19.2 ms，本机 tick 实测 19.4 ms 见 [tick 率](../original_tick_rate/README.md)）。窄帧 CURSOR04–07 彼此只差翅膀几像素，单帧分类不可靠，所以只用首末帧的周期。逐帧看到同一支权杖的画面：

| PTS（s） | 画面 |
| --- | --- |
| 6.0 | 标题（圆盘右下；此时 macOS 箭头另在圆盘上，是宿主指针与 Wine 内光标不同步） |
| 89.0 | 状态页（道具栏右侧） |
| 91.0 | 蓝色移动格上 |
| 93.5、110.9 | 敌方回合地图上——光标**没有**消失（录屏索引 88.5–95.8 段模型写的「红剑光标消失」与像素不符，不采用） |
| 575.0 | 系统菜单右侧 |

录屏没有大地图与城镇；那两处用同一对象的依据是 §1 的 OBS 普查。

## 4. 重制

**R7-CAM（2026-09-25）**：autoload `game/cursor/GameCursor.gd` 把当前帧经 `Input.set_custom_mouse_cursor` 交给系统作硬件光标，并按窗口像素÷640 放大（不小于 1）。问题（lane CURSOR，用户实玩）：macOS 按「点」显示光标图，而 Godot 的窗口尺寸是像素，Retina（背板 2 倍）上光标显示成 2 倍；又因不小于 1，窗口缩到 640×480 以下也不缩小——小窗口里光标显得非常大，和原版「画在画面里、随画面缩放」不符。

**lane CURSOR（2026-09-26）后**：照原版画进游戏自己的 640×480 画面。

- 光标是 root 视口最上层 CanvasLayer（1025，高于内嵌弹窗画布 1024，对应 planeCursor 盖住一切）上的 Sprite2D，源尺寸、最近邻；stretch mode viewport 下 root 视口坐标就是逻辑坐标，窗口把整张画面一起缩放，所以光标像素大小随窗口等比变化，热点（draw origin，红宝石）落在指针所在的逻辑像素——命中测试读的就是这个像素。
- 位置每帧取真实指针（`get_mouse_position`），与原版「每 tick 站到鼠标上」同义；比系统硬件光标多约一帧延迟，与原版在 cnc-ddraw 下画在帧里相同。
- 系统指针只在「窗口有焦点且指针在画面内」时隐藏（`MOUSE_MODE_HIDDEN`，对应原版 WM_SETCURSOR 里 `SetCursor(NULL)`）；信箱黑边、窗外、失焦时系统箭头回来、画面里的权杖不画。启动后第一次移动指针前不画（窗口化截图夹具不会凭空出现光标）。
- always 处理：调试停格、续战提示时照样跟手；换帧只在树运行时走（每 `OriginalTick.TICK_SECONDS` 一 tick、6 tick 一帧）。
- 标题、战斗、剧情、大地图、城镇都是同一个 autoload，`run_game_cursor_tests` 普查 `game/` 下别无代码设光标图、形状或隐藏系统指针。

前后（本机 Retina，光标在屏幕上的实际像素，CURSOR01 31×34）：

| 窗口 | 改前 | 改后 |
| --- | --- | --- |
| 480×360 | 62×68（缩放夹到 1，再被 Retina 翻倍） | 23×26（画面 0.75 倍） |
| 640×480 | 62×68 | 31×34 |
| 1280×960（默认） | 124×136（缩放 2，再被 Retina 翻倍） | 62×68（画面 2 倍） |

窗口化截帧：`tools/godot.sh --script res://tests/capture_walk_follow_cursor_review.gd -- --window=1280x960 --cursor-only --out=<目录>`（与 `--window=640x480`）在第 51 战首控把十帧依次指向选中角色格中心逻辑 (368,272)：两种窗口的 root 画面都是 640×480、宝石像素都在 (368,272)、命中测试读到同一格 (15,17)，failures=0（截图在 lane worktree 的 `ignored/cursor/`，不入库）。

**lane FXQUEUE（2026-09-27）后**：照 §2 三条。

- 演出隐藏：`GameCursor.suppressed()` 每帧问组 `game_cursor_hiders` 里的节点；`BattlePresentation.hides_game_cursor()` 在战斗特写或地图魔法效果播放（`cutin.busy()`，0x800000／0x1000000）时为真。剧本演出（落雷、噴人沼氣、对白）原版不置这两位，权杖照常显示。
- 持物：战利品面板与商店的持物图标（`hand_icon`，已按原版画在指针处、以物品 SHP draw origin 为锚）加入组 `game_cursor_held_items`；其中任一可见时权杖不画——指针处只剩物品图标，与 `0x430310` 画图标并藏权杖同貌。
- 隐藏期间翅膀不转；再显示时从 CURSOR01 重新开始。OPT-CURSOR=系統硬體游標 时同样条件下系统指针隐藏（`MOUSE_MODE_HIDDEN`）。
- 启动后不动鼠标不出现（lane CURSOR 已做，`_pointer_moved`）。

截图（lane worktree 的 `ignored/fxqueue/`，不入库）：第 10 关自动对局战斗特写中无权杖（`cursor_hidden_close_up.png`）；歐姆村武器店拿起長劍后指针处只见長劍图标（`cursor_held_item.png`）。

**验证**：`hsl check game_cursor`（清单字段、十帧、`frame_ticks = delay + 1`、PNG 哈希、155 个 OBS 无分歧）；`tests/run_game_cursor_tests.gd`（autoload 安装、热点 = draw origin 且落在红宝石、逐 tick 换帧 [6,12,…,60] 并循环、源尺寸画在 root 视口 1024 以上的层、热点落在指针所在逻辑像素、无第二个光标来源）。消融：换帧改成 delay tick、热点改 (0,0)、去掉 autoload 注册各自失败。

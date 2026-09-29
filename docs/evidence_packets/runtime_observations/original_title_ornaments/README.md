# 原版标题画面的宝珠与书：上下浮动，不跟随选项；点击标题项放 ACCEPT01

> evidence: static-derived: defProcMainMenuItem 0x424360 每 tick y＝生成 y＋trunc(6·sin(角))、角 +3／256、初角 rand()%255；点击放 RESOURCE 398；菜单首帧低 300 px 以 0x45e882 速度 40 滑回；悬停每 6 tick 撒 Menu_Star、点击加 Menu_Star2；码 10／11 开設定選項／回憶錄列表；宝珠／书按住计时 10 tick 与读入淡出 0x42dc90(2); runtime-measured: 原版 v1.06 标题画面的宝珠与书只在竖直方向浮动，周期约 1.65 s、上下各约 5 px，位置与鼠标停在哪一项无关; provisional: 星点逐颗落点、Menu_Star Shape_Delay 按 0 · status: live · functions: 0x415c10, 0x415dc0, 0x416d04, 0x41f5db, 0x423aa0, 0x423b90, 0x423bd0, 0x423cd0, 0x423f00, 0x424004, 0x4241a0, 0x424360, 0x42c180, 0x42c7e0, 0x42cb60, 0x42cc10, 0x42cc70, 0x42dc90, 0x4477b0, 0x458c80, 0x459990, 0x45e575, 0x45e882, 0x45e9bc, 0x45efce, 0x46098f, 0x460a58 · tools: hsl_original_control.py, play_original.sh · updated: 2026-09-28

## 结论

- 原版：宝珠（Item1）与书（Item2）由 defProcMainMenu `0x423cd0` 建在菜单位置（环左上）＋(33,112)／(207,107)；defProcMainMenuItem `0x424360` 每 tick 令 y＝生成 y＋trunc(6·sin(角·2π/256))、x 不变，字节角每 tick +3，初角各自 rand()%255；点击标题项（三行字与宝珠、书同走 `0x4241a0`）放 ACCEPT01（RESOURCE 398）（static-derived）。实录周期 1.646 s、振幅 5.1–5.2 px、相位差各组不一，与读法一致（runtime-measured）。
- 原版：菜单（环、三行字、两尊雕像、宝珠、书）首帧低 300 px，state 0 以 `0x45e882` 每 tick min(40, 距离>>3)（至少 2、1 px 内落位）滑回，落位后才收输入；悬停对象每 6 tick 按 32 px 一列撒 4 颗 Menu_Star（788），点击撒 24 颗 Menu_Star2（789）＋16 颗 788，星点随机起始张、竖直上飘、停 6..13＋1 tick 后 16 级加色淡出；点宝珠开 設定選項（792）、点书开读取回憶錄列表（790），窗开期间菜单照画不收输入，窗写回结果后复位或读入（static-derived）。
- 原版：宝珠／书点击后主菜单先数按住计时 `+0xa8`＝obj_Data8＝10 tick（state 3 `0x424004`，与三行字的 40 tick 同一套）再开窗；读入回憶錄经 `0x42cc10(1,1)` → `0x42dc90(2)` 淡出，每 2 tick 一级、30 tick 全黑（static-derived）。
- 重制：`game/title/TitleScreen.gd` 按同一生成位置、正弦表截断、每 tick 步进与各自随机初角逐 tick 浮动；点击标题项放 ACCEPT01；滑入、火花节拍与运动、宝珠／书按住 10 tick 后开窗与读入淡出照上述读法（static-derived）。
- 差异：星点逐颗落点用重制随机流；Menu_Star 未写 Shape_Delay 按 0；读入时 `0x42c7e0` 的表现未读，见「边界」（provisional）。

## 证据

**static-derived（hsl01.exe SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 静态读）**

- 对象：OBJ-000.OBS 的 Item1（码 7，TITLE027，defProcMainMenuItem）、Item2（码 8，TITLE028，同过程）；PROCESS.DEF 45 → 表 `0x477c2c` → `0x424360`。三行字 String1–3（码 1／3／4，TITLE024–026，Data9＝0／1／2）是 defProcMainMenuString 9 → `0x4241a0`。
- 生成：defProcMainMenu `0x423cd0` 首帧把自己 y 加 300，在 (X＋33, Y＋300＋112) 建码 7（`0x423e06`）、(X＋207, Y＋300＋107) 建码 8（`0x423e32`），再在 state 0 以 `0x45e882` 步长 40 滑回 Y 并经 `0x45efce` 带动子对象。菜单停位即环左上 (197,161)（两尊雕像 X−80／X＋208、Y＋66 与版面实测 (117,227)／(405,227) 相符）；减 SHP 绘制原点 (14,14)／(18,21) 得宝珠左上 (216,259)、书左上 (386,247)。
- 每 tick（`0x424360`）：首帧（`0x20000000`）`+0x34`＝`0x458c80(0xff)`＝rand()%255、`+0x36`＝3，记下生成位置；之后若位置被外部移动（菜单滑入）把差加到生成位置；`0x45e9bc(角, 0x60000, 3, &dx, &dy)` 取余弦表 `0x4a35fc`／正弦表 `0x4a39fc`（256 项 16.16）乘半径 6、取绝对值截断再补符号，返回角＋3（字节回绕）；x＝生成 x（dx 不用）、y＝生成 y＋dy；最后调 `0x4241a0` 处理悬停与点击。
- 周期：256/3＝85.3 tick；按 19.4 ms 宿主 tick 为 1.655 s，与实录拟合 1.646 s 相差 0.5%；偏移取整后在 −6…+6 px，实录拟合振幅 5.1–5.2 px。
- 初相：两件各自在首帧取 rand()%255，彼此无关；实录三组相位差 48°／194°／193° 与此一致。
- 点击声：`0x4241a0` 收到点击（`0x40000`）且碰到的是处于待输入的主菜单（`+0x80 & 0x10000`，state 2）时，`0x4242d6` 放 RESOURCE 398（ACCEPT01，`0x4477b0`→`0x459990`→`0x42c180`），把自己的码 `+0xac` 与按住计时 `+0xa8` 交给主菜单，并建对象 789 Menu_Star2；悬停（`0x2000000`）建对象 788 Menu_Star（global.obs，MAGIC\EAR24_22.SHP，effProcFlyUpShape）即悬停火花。
- 码分派（`0x424037`，字节表 `0x42418c`）：0 開始新故事、1 戰場記錄、2 離開遊戲、10（宝珠 Data9）→ `0x423b90` 建对象 792 Option（TITLE039 設定選項）、11（书 Data9）→ `0x423bd0(…,0)` 读取回憶錄列表。
- 滑入：`0x423cd0` 首帧记下原位（`+0x90`／`+0x92`），自身 y＋300（`0x423d06`），子对象三行字 (X＋45, Y＋300＋60／109／151)、雕像码 11／12 (X−80／X＋208, Y＋300＋66)、宝珠、书都建在下移后的位置；state 0（`0x423f4c`）`0x45e882(x, y, 原 x, 原 y, 40, …)` 步进，未到则留在 state 0，`0x45efce` 把位移加给子对象；到位 state 1（`0x423fa7`）置 `+0x80 |= 0x10000`、码 0xffff，state 2 等码。背景与标志不是菜单子对象。`0x45e882` 步长与商店／卷轴同读（min(40, 距离>>3)，至少 2，1 px 内落位），300 px 约 32 tick 到位。
- 悬停与点击火花（`0x4241a0`）：只在碰到的主菜单带 `0x10000`（待输入）时处理；悬停（`0x2000000`）`+0x90` 每 tick −1（首帧置 6），≤0 时复位为 `+0x92`＝6 并以 4 颗调 `0x423aa0(自身, 788, 48, 6, 4)`；点击另调 `0x423aa0(自身, 789, 64, 1, 24)`，再以 16 颗调 788。计数跨悬停不清零。
- 撒点（`0x423aa0` → `0x415c10`）：列 x 从形状左＋16 起每 32 px 一列、到形状右为止，列中心 y＝形状顶＋16；每列 `count` 颗，dx＝rand()%宽 折成 宽/2−dx（宽 48／64），dy 同法取 2×(高−16)；首颗延迟 0，此后每颗 +rand(抖动)+1（788 抖动 6、789 抖动 1），延迟记 `+0xae`；全局对象数到 900 停撒。
- 星点运动：global.obs 788 Menu_Star（`MAGIC\EAR24_22.SHP` 起 3 张，Shape_Delay 被注释、Data6 被注释）、789 Menu_Star2（`EAR24_21.SHP` 起 3 张，Shape_Delay 2，Data6 0x8000），planeMenu6、defProcEffectProcess1、Data9 effProcFlyUpShape（TYPE.H 81 → 表 `0x4231b0` → `0x41f5db`）。序言 `0x415dc0` 数完 `+0xae` 才画、置加色与层级 16；`0x41f5db` 起始张＋rand(3) 并定住（`+0x78`＝0x10001），速度＝(rand & 0x1f000)＋Data6（16.16）朝 0xc0 正上，`+0x7c` += 6＋(rand & 7)，把过程改成 16 effProcFlyUp2 并跳过其首帧；之后 `0x416d04` 每 tick 先位移，再 `0x45e575` 数 `+0x7c`，数完置 `0x20000000`，此后 `0x422c9a` 层级每 tick −1、归零删除。
- 按住计时：`0x424302` 把被点对象 `+0xa8` 交给主菜单；OBJ-000.OBS 的 Item1／Item2 obj_Data8＝10（注释 delay），String1–3 为 40；state 2 `0x423fd8` 见码进 state 3 并清 `0x10000`，state 3 `0x424004` 每 tick 减一、到 0 按码分派（码 10／11 即开窗）。宝珠／书因此在点击后 10 tick 开窗，其间菜单不收输入。
- 读入淡出：state 5 结果 1 时 `0x42cc10(1,1)` 置 `0x4c1b00 |= 0x90000000` 并调 `0x42dc90(2)` → `0x46098f(2)`：级 1 起、方向 +1、每 2 tick 加一级（`0x460a58`，主循环 `0x42d772` 每 tick 一次），超 16 夹住并停；与離開遊戲（`0x42cb60`）、開始新故事（`0x42cc10(0x33,0x33)`）、戰場記錄（`0x42cc70`）同参数 2。
- 开窗关窗：码 10 state 4、码 11 state 5，把 `+0xac` 清 0 并把其地址交给窗（`0x423b90` 建 792 于 (0,0)、`0x423bd0` 建 790 于 (0,0) 且 `+0x9c`＝0 读取模式；建失败直接写 2）；菜单此时已清 `0x10000`，照画但不收悬停与点击，宝珠与书照常浮动。state 4（`0x424101`）等 `+0xac` 非零回 state 1；state 5（`0x424117`）非零且为 1 时 `0x42c7e0`、`0x42cc10(1,1)` 读入并进 state 99，否则回 state 1。

**runtime-measured（2026-09-24 原版 v1.06，Wine＋cnc-ddraw 640×480）**

- 采样：鼠标停在第 1／2／3 项（`hsl_original_control.py move`／`click`），等 5 s 后 `screencapture -l <窗口 id>` 只截游戏窗口，每项连拍 45 张、间隔 0.15–0.26 s（每项 7.6–9.8 s）；Retina 2× 截图去标题栏后按 2×2 平均缩回 640×480。
- 定位：第 1 项第 1 张的宝珠块 (218,256,30,30) 与书块 (388,240,34,40) 作模板，每张 ±6 px 水平、±18 px 竖直搜索最小平均差；宝珠另用绿色像素质心核对（135 张里 134 张 481 像素、1 张 456 像素），两法一致。
- 入库：逐张位移表 [ornament_track.tsv](ornament_track.tsv) 与 4 格裁切图。

停在第 1 项：浮到最高、沉到最低；停在第 2 项；停在第 3 项（原版帧见私有档案：`runtime_observations/original_title_ornaments/title-ornaments-4-states.png`）

| 量 | 宝珠 | 书 |
| --- | --- | --- |
| 水平位移 | 135 张全为 0 | 135 张全为 0 |
| 竖直范围（相对模板帧） | 0 … +10 px | −2 … +8 px |
| 拟合周期（三组合并） | 1.646 s | 1.646 s |
| 拟合振幅 | 5.1–5.2 px | 5.1–5.2 px |
| 拟合残差（RMS） | 0.4–0.7 px | 0.4–0.7 px |
| 均值：停第 1／2／3 项 | +4.96／+5.00／+5.02 | +2.84／+3.10／+2.93 |
| 640×480 画面上的位置 | 质心 x＝233，y 在 270 与 280 之间往返（球体约 26×26 px） | 书约占 (375,245)–(424,286)（模板帧），整体在其上 2 px 到下 8 px 之间往返 |

- 三组采样间隔各不相同却拟合出同一周期，1.65 s 不是采样混叠。
- 选中项只是文字变金色并出现火花（第 1 项火花见第 1、2 格）。
- 三个文字行（黑色描边竖直范围）：第 1 项 y 243–261、第 2 项 286–303、第 3 项 331–348。宝珠中心总在第 1 项文字中心（y≈252）下方 18–28 px；原版参考帧 01/frame_001 的"约 19 px"对应浮到最高点附近。
- 两件相位差三组分别为 48°、194°、193°（三组相隔几分钟）：两周期可能只差很少，也可能各自计时，采样分辨不出。

## 重制接线

`game/title/TitleScreen.gd`：`ORNAMENT_SPAWN_OFFSETS`＋`ornament_spawn_top_left` 是生成位置，`ornament_offset` 按 `OriginalTick` 的整 tick 数算角与截断偏移，`ornament_phases` 存两件初角；`play_click_sound` 在点击标题项（及重制键盘确认）时放 interface_audio 的 confirm（ACCEPT01，398）。`menu_slide`／`_tick` 逐 tick 滑入，`menu_armed` 落位前与开窗时不收输入；`spawn_sparkles` 交给 `game/common/MenuStars.gd` 的 `spawn`、逐 tick 运动由 `MenuStars.tick` 照上述撒点与运动画在加色层 `MenuStars`（回憶錄列表共用）；`press_window` 数 10 tick 后 `open_window` 经 `BattleSystemMenu.open_standalone` 开 設定選項／读取回憶錄列表（不带卷轴），窗返回发 `standalone_closed` 复位，列表选有记录的格确认后 `resume_memoir_record` 入队并淡出。provenance 头写 `static-derived` 本包。标题其余读法见 [menus_ui](../menus_ui/README.md)。

## 复现

实录不可再生：原版侧唯一记录。静态部分：`r2 -q -e scr.color=0 -c 'pd 140 @ 0x423cd0; pd 60 @ 0x424360; pd 120 @ 0x4241a0; pd 30 @ 0x45e9bc; px 12 @ 0x42418c; pd 75 @ 0x423aa0; pd 90 @ 0x415c10; pd 25 @ 0x41f5db; pd 50 @ 0x416d04; pd 30 @ 0x423b90; pd 20 @ 0x423bd0; pxw 8 @ 0x4232f0; pd 80 @ 0x424004; pd 30 @ 0x42cc10; pd 30 @ 0x460989; pd 20 @ 0x460a58' hsl01.exe`；effProc 号读 PAK 内 `data\TYPE.H`；对象与过程号用 PakReader 读 OBJ-000.OBS、global.obs、PROCESS.DEF。

## 边界

- 实录采样率只有 4–5 帧／秒；书的范围由目测裁切图得到，误差约 ±2 px。静态读法与实录的周期、振幅、相位关系一致，未另做逐帧读数。
- 星点只照分布、数量与运动，逐颗落点与原版全局随机流不同；Menu_Star 的 Shape_Delay 被注释，按 0 读（obs 缺省值未读）。
- 撒点的形状矩形用亮起形状（三行字）与宝珠／书贴图，`+0x94`..`+0xa0` 的内缩按 0。
- 读取回憶錄列表沿用战斗内列表（选有记录的格先问確定／取消，重制读法）；读入时 `0x42c7e0` 的表现未读，重制不停留直接按 `0x42dc90(2)` 淡出。
- 点击声只在主菜单处于待输入态时放；重制键盘确认也放同一声，属重制键盘路径。

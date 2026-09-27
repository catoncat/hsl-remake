# 菜单与界面：标题、目标光标、系统卷轴的原版测量与重制落地（lane R6-P4）

> evidence: runtime-measured: 2026-09-24 原版录屏（605.8 s，可变帧率约 57 fps）的逐帧像素、SHP 模板匹配与音轨互相关，2026-09-26 Wine 原版实拍技能页三帧（§5，cnc-ddraw 游戏窗截图）; resource-derived: I_RECT01.SHP、BOARD02.SHP、WINDOW60.SHP、Title039／Title061、WAV 表; static-derived: 状态窗 mode 10 与 WINDOW20／21 的既有读法（static_reverse/original_growth_window.md）、状态页 mode 0／1 板与页按钮 `0x43ac10`／`0x43a640`／`0x443cfa`（§4）、技能页 `0x43b4e0`／`0x438160`／`0x434d10`／`0x433a90`／`0x4331b0`、滚动条 `0x446060`／`0x445860`／`0x445d70`、悬停脉冲 `0x42c110`／`0x42c130` 的读法（§5）; provisional: 只在这一份录屏出现一次的时长与未命中的声音 · status: live · tools: hsl_original_control.py, hsl_video_events.py, run_battle_scene_runtime_tests.gd, run_presentation_contract_tests.gd, run_skill_resource_tests.gd, run_system_menu_tests.gd, run_title_screen_tests.gd · updated: 2026-09-27

起因：R6-V2 录屏对账第 5、6 节与「并排对比补充」列出标题、状态页、任務說明／存档、目标光标与敌方回合的差异（模型描述）。本包逐项用像素／资源／声音核对后再改重制；agy 本轮不可用，没有模型命名，全部是量值。

## 方法

- 录屏：`录屏2026-09-24 中午12.03.22.mov`（用户录屏，私有档案）（本机，不入库），游戏区 `crop=1280:960:112:140`，缩到 640×480 逻辑像素；时刻是视频 PTS 秒。
- 像素：ffmpeg `signalstats` 逐帧平均亮度（标题淡黑）、白色墨迹外框（版本号）、SHP 预览图对录屏的模板匹配（lane 本地脚本，在候选区域按 1 px 步长求平均绝对差最小值，下称"模板差"，0 为逐像素相同；缩放与压缩使完全命中约 9–21）。
- 声音：`tools/hsl_video_events.py audio`——10 ms 包络起点，以及 220 个原版 WAV 在所给时段内的归一化互相关（NCC）最佳位置。
- 原始帧、局部放大与匹配日志在 lane worktree 的 `ignored/r6p4/`，不入库。

## 1. 标题画面

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 版本号 | 左下常驻白字「V1.06」，定宽点阵字 8 px 步进，墨迹 (3,459)–(41,467)，整段录屏不变 | runtime-measured | 没有 | ASCFONT.15 半角字（8×15 格，墨迹行 3–11、列 1–7），格左上 (2,456)，墨迹 (3,459)–(41,467) 与原版逐像素一致（lane UIFIX） |
| 確認「開始新故事」 | 点击后该项红色亮起字形（Title024 系）在 13.52 s 出现，停 0.75 s；14.27→14.82 s 整屏亮度线性降到黑（0.55 s） | runtime-measured | 0.6 s 直接淡黑 | 亮起停 0.75 s，再 0.55 s 淡黑（`CONFIRM_HOLD_SECONDS`／`FADE_TO_BLACK_SECONDS`）；戰場記錄 同用（provisional） |
| 悬停 | 原版悬停只有火花，红色亮起出现在点击时 | runtime-measured | 悬停即亮起 | 不改（重制的悬停提示保留，记在标题 manifest 的 unresolved） |
| 点击声 | 13.59 s 有一个短起点（峰值 −43.6 dB）；最高 NCC Walk0011 0.34、Accept01 0.31，都不够认定 | negative-evidence | 无声 | 无声（未认定前不加） |

R6-V2 的"停约 10 s 再淡黑约 2 s"与录屏量值不符：亮起到全黑一共 1.30 s。

## 2. 目标格光标（玩家选目标与敌方攻击预告）

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 形状 | 黄色格框，四角有饰纹，32×32：`I_RECT01.SHP`（黄色渐变 238,222,0 → 139,121,0）。R6-V2 的"菱形"是这个框 | resource-derived＋runtime-measured | 玩家选目标：青绿呼吸角括号；敌方预告：淡黄角括号方块 | 两处都画 I_RECT01 |
| 玩家选目标 | 178.0 s 目标格 (320,220) 上的黄框 | runtime-measured | 同上 | `BattleSelectionCursor` 在攻击／魔法／特殊选目标时画 I_RECT01；选移动格仍是重制的角括号 |
| 敌方预告 | 97.6 s (318,176)、199.1 s (316,192)、256.5 s (304,172)：同一黄框停在被攻击者格上；画面上没有玩家式选择框 | runtime-measured | 敌方预告期间，鼠标停在格上时玩家选择框也会出现 | `BattleAttackCue` 用同一张 I_RECT01；玩家选择框只在 `Interaction.TARGETING` 显示，敌方回合不出现 |
| 底部卡片 | 普通攻击选目标时底部只有一张卡（头像＋数值条＋WINDOW10 身份条，178.0 s），与重制相同；"施术者＋目标两张卡"只出现在特殊技流程 | runtime-measured | 一张目标卡 | 不改（特殊技页不在本 lane） |

## 3. 系统卷轴：任務說明、存档确认与提示

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 確定／取消 | Title061（128×47）压在打开的卷轴中央 (256,217)，没有问句、没有压暗；所选项在提示期间保持红色亮起。582.0 s 儲存戰場記錄（模板差 17.1）、592.5 s 回主選單（9.5） | runtime-measured | (256,300)，全屏压暗 55%，亮起项隐藏 | (256,217)，不压暗，亮起项保留；卷轴下方的问句是重制补充（remake-invented） |
| 儲存戰場記錄 | 点击后先问確定／取消（581.0 s）；確定后卷轴不关 | runtime-measured | 直接保存、关卷轴、顶部横幅 | 先问；確定后存档，卷轴保持打开 |
| 完成提示 | 「進度儲存完成」在无头像、居中的 BOARD02 消息板上：板 (75,320)（583.5 s 模板差 13.2），582.53→582.77 s 淡入，停到 583.73 s，583.87 s 前淡出 | runtime-measured＋resource-derived | 顶部「戰鬥已保存（F9 讀取）」横幅 | BOARD02 (75,320) 居中文字，0.25 s 入、0.95 s 停、0.15 s 出 |
| 存档声音 | 582.28 s 起点（確定 点击）最高 NCC Walk0010 0.73；582.8 s 第二个起点 Put00003 0.52 | provisional | 无声 | 无声（单一样本，未认定） |
| 任務說明 | 577.55–579.48 s：卷轴上方淡入与开场同一块 WINDOW60 胜负条件面板 (136,108)，绿色「勝利條件」「失敗條件」标题各带一行条件，停到按键 | runtime-measured | WINDOW60 居中卡片、表现侧文案 | 同一 `BattleWinFailBoard`（开场用的那块）在 (136,108) 淡入，等输入；Esc 淡出回卷轴 |
| 設定選項 | Title039 居中 (142,90)，588.0 s 模板差 21.4 | runtime-measured | 同位置（provisional） | 不改，证据等级升为 runtime-measured |

同类盘点（`run_system_menu_tests._run_confirm_class_inventory`）：两种卷轴里写记录或离开当前游戏的项——战斗卷轴 儲存戰場記錄／讀取回憶錄／讀取戰場記錄／回主選單，大地图卷轴 讀取戰場記錄／回主選單——都走同一个 Title061 提示；回憶錄列表里覆盖已有格与读取已有格也用同一提示。未纳入：状态页的保存／读取按钮（OPT-GUIDE＝提示 才有）与 F5／F9 快捷键（重制补充），仍即时执行并用顶部横幅。

## 4. 状态页（lane STATUSPAGE 2026-09-27：左栏默认就是属性页；钱框只在行动环 狀態 页）

| 项 | 原版 | 等级 | 重制 |
| --- | --- | --- | --- |
| 两个入口 | 行动环 狀態 `0x444285`（`push 0`）→ `0x43b4e0` mode 0；点非己方指挥单位 `0x443cfa` → mode 1，且只对已知单位开（未知落到 `0x443d9d`，同点空地，[身份栏包](../../static_reverse/original_identity_bar.md#显示未知单位信息的原版界面static-derived)） | static-derived | `BattleSceneMenus` 狀態 → `show_unit(…, own_page=true)`；`BattleSceneInput` 点单位先问 `BattleStatusPanel.opens_for(known)`，再 `show_unit(…, known, false)`；OPT-INFO＝公開 时一律开 |
| 板 | mode 0／1 同建 130 头像 (12,14)、131 WINDOW10、145–147 三条、132 WINDOW20 (12,174)、133 WINDOW30（`0x43ae70`，停靠 x 252）；mode 0 另建 134 `$:` WINDOW40（`0x43af60`，y 440）与 137 上一位／142 下一位，mode 1 跳过这三个（`in_stack_8 != 1` 分支） | static-derived | mode 1 的页不画钱框（`gold_board`／`gold_label` 随 `own_page`） |
| 左栏 | `0x43ac10` 建根对象时 `+0x94 = 4`，WINDOW20 过程（`0x438160` case 2）按它分页：4＝属性（帧 +1 → WINDOW21，九行属性）、1＝道具（`+0x138` 八格，行高 32，悬停出说明）、2＝魔法、3＝特殊技；只有页按钮（`0x43a640` case 3 `default: root+0x94 = Data6`）改它——开页总是属性页 | static-derived＋runtime-reference | 重制左栏本来就是 WINDOW21 九项属性，与原版默认页相同，不改 |
| 页按钮 | y 387 一排 42×42 图标（`0x43b0a0`..`0x43b230` 停靠 y 387）：mode 1 四个——狀態（141 BCMD13，Data6 4）、道具（138，1）、魔法（139，2）、特殊技（140，3）；mode 0 另加上一位（137）／下一位（142）；当前页那颗置 `0x10000000` 画暗。`06_status_and_stats_screen/frame_028`（638 px 宽）红框行 366–406、首钮列 264–304：钮心 y 386.5，与停靠 387、图标高 42 一致；接触表 frame_001..016 开页即属性页，frame_018 按 道具 后才列 回復藥×3／解毒草，frame_026／028 是 特殊技 页 | static-derived＋runtime-reference | **未做**：重制没有这排页按钮（道具／魔法／特殊技页要从别处进），差异清单 `status-left-column` 改记此项 |
| 说明框 | 悬停装备（WINDOW30 过程 `0x430710`＋`0x436d70`）或道具行时 WINDOW50 (252,349) 盖在按钮排上（frame_006：悬停 铁护轮 时按钮排不见） | static-derived＋runtime-reference | 重制 WINDOW50 常驻（`BattleEquipmentView`），同记在 `status-left-column` |
| 录屏 77.5 s／84.0 s | 雷歐納德、重裝兵 左栏是道具列表、手上拿着物品、有钱框、**没有页按钮**：这是物品／交换窗（`0x43b4e0` mode 4／5／7，根旗标带 `0x4000`）——WINDOW30 过程在 `0x4000` 下鼠标不在装备板时把 `+0x94` 写 1（道具）、拿着物品移上装备板写 4（属性），不是状态页；此前「状态页左栏是道具列表」的读法据此更正 | static-derived＋runtime-measured | — |

重制补充（原版没有）改挂选项，原版值下都不显示：永久加值／入场成长行与属性、抗性悬停说明归 OPT-INFO＝公開；底部「保存 F5／讀取 F9／待領物品／返回」按钮条归 OPT-GUIDE＝提示；「成長點」随 OPT-GROWTH 暂缓路径（有点数才显示，原版值点数总在升级窗里分完）。读点见 `content/authored/options/remake_options.json` 两张卡的 `read_points`。

## 5. 技能页：特殊技与魔法（lane UI6 进入流程；SKILLPAGE 布局；SKILLPAGE2 2026-09-26 原版实拍、滚动条、列表顺序）

页面是状态窗的另一种 root mode，不是独立列表板。来源三路：hsl01.exe 静态读法（地址）、2026-09-24 录屏 238.8 s 帧、2026-09-26 Wine 原版实拍（`tools/hsl_original_control.py` 的 cnc-ddraw 游戏窗截图，回憶錄 第 1 行 `level06_pre_battle` 进第 6 关，只截游戏窗口）。本目录三帧：skill-page-magic-hover.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-magic-hover.png`）（緹娜 魔法页，悬停 水剎）、skill-page-special-red.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-special-red.png`）（琥 特殊技页，氣力 0 付不起 毒魔箭）、skill-page-special-red-hover.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-special-red-hover.png`）（同页悬停该行）。cnc-ddraw 把 RGB565 左移展开，帧里白色是 (248,252,248)，颜色比 8 位原值低 3–7。

| 项 | 原版 | 等级 |
| --- | --- | --- |
| 进入 | 按「特殊技」总先开技能页：46.5–54.75 s 首控（雷歐納德 只有 氣刃斬，氣力槽空）打开页、再取消回行动环；237.9–239.6 s 与 423.6–429.6 s 先开页，选 氣刃斬 之后才出现技能格与底部目标卡（240.4 s）；Wine：琥 氣力 0 也开页，右键回行动环 | runtime-reference＋runtime-measured |
| 页面 | `0x43b4e0` case 8 魔法（root `+0x94 = 2`）／case 9 特殊技（`+0x94 = 3`），开页把已选码 `*0x4c2c40／44／54／94` 置 −1；挂 130 头像 (12,14)、131 WINDOW10 (381,14)（原点 (248,0)，左缘 133）、132 WINDOW20 (12,174) 224×264（`0x43add0`）、134 `$:` WINDOW40 (416,440)（`0x43af60`）；地图压暗（平均亮度 79.9→37.9）。Wine 两页四块板模板匹配都在 WINDOW10 (133,14)、WINDOW20 (12,174)、WINDOW40 (416,440)、说明框 WINDOW50 (252,349) | static-derived＋runtime-measured |
| 行 | `0x438160` case 2 魔法（列表 `0x4c30e0`、行数 `0x4c1cd8`、页字 5、说明 `0x4331b0`、可选判 `0x408fe0`）／case 3 特殊技（`0x4c2cc0`、`0x4c1cdc`、10、`0x433a90`、`0x409040`）：首行距框顶 8（+0x9a）、行高 28（+0x98）；名字 x＝框 x+8+24（`0x4123b0`）；元素宝石 MAGICON[type] 在 (框 x+15, 行+2)（`0x4607f9`，表 `0x4c3460`；type 5／6 不画）；行文字整块画在 y+8−28·pos，裁到 (x, y+8)–(x+224, y+258)，第九行少 2 px。Wine：水剎 墨迹 x 45–91、y 187–202，治癒之水 x 46–139、y 215–230，宝石 (27,184)–(35,202)／(27,212)–(35,230)；238.8 s 氣刃斬 x 45–115 | static-derived＋runtime-measured |
| 顺序 | `0x434d10`（魔法 `0x436010`–`0x4361c4`，特殊技 `0x436253`–`0x436408`）：类型 t 外层（魔法 0..5＝地、水、風、火、心靈、其他；特殊技 0..6 多「其他2」），每类 magicCode 位 0..31（magicCode01＝位 0）内层，只列 actor 掩码（魔法 `+0x174+4t`，特殊技 `+0x158+4t`）置位且表里有的项；付不起的也列（@2，项 `\|0x80000000`）；每行＝@1／@2＋名字补空格到 18 字节＋`#`，没有消耗数字列。Wine：水剎（水 位 0）排在 治癒之水（水 位 5）前 | static-derived＋runtime-measured |
| 悬停 | 没有光标条。悬停行＝(鼠标 y − 框 y − 8)/28，须在 0..8 且加 pos 后小于行数（横向整框，Wine 在 x 200 仍命中）；该行说明进说明框，名字由 `0x4132f0` 模式 1 重画成 `0x42c130` 的颜色：R、B 基值 0（`[0x4c1c68]`／`[0x4c1c6c]`），G 基值 255（.data `0x477c28`），各减 2·\|p\|、下限 0，p 是帧体 `0x42d600` 每 tick 调 `0x42c110` 加一的 −16..16 计数（33 tick 一周，[tick 率](../original_tick_rate/README.md)）——绿色在 223–255 往复。Wine 两帧 G 236／244（RGB565 六位 59／61），238.8 s 录屏 224–255；不是色表 `0x476b44` 的 @3 (205,255,205)（说明框首行用它） | static-derived＋runtime-measured |
| 付不起的行 | `0x434d10` 给付得起的行 @1 白、`0x409040`／`0x408fe0` 拒绝的行 @2 红（色表 0xfa8a＝(255,82,82)）。Wine：琥 毒魔箭（消耗 1、氣力 0）红字 (248,80,80)；悬停照样变脉冲绿 (0,236,0) 并出说明；点击时 `0x438160` 先过可选判，拒绝就不进选格 | static-derived＋runtime-measured |
| 说明框 | `0x436d70` 框 (252,349) 376×88，行 (x+8, y+12+16i)、360 px 居中、首行 @3 绿（[getitem 窗静态读法](../../static_reverse/original_getitem_window.md#描述框-0x436d70)）；四行由 `0x433a90`（特殊技）／`0x4331b0`（魔法）写：名字（魔法加「 (地系)」…）；氣格消耗N（特殊技元素加「, 屬性: 地系」）／魔法消耗N；威力行（function bit 1 基礎攻擊力 lo~hi、否则 bit 2 基礎回復力，后接异常、解除、辅助词，特殊技再接回復魔法…吸取敵人生命，整组齐全时合成一词）；命中率N%,對象一名／多名（effect_range＝0 即 range0Cell 为一名，RESOURCE 239／240；魔法写「魔法命中率N%, 對象…」）。238.8 s「氣刃斬／氣格消耗1／基礎攻擊力36~54／命中率98%,對象一名」；Wine「水剎 (水系)／魔法消耗8／基礎攻擊力16~24／魔法命中率94%, 對象多名」「治癒之水 (水系)／魔法消耗6／基礎回復力24~36／魔法命中率100%, 對象一名」「毒魔箭／氣格消耗1, 屬性: 心靈系／基礎攻擊力30~45 中毒傷害／命中率98%,對象多名」 | static-derived＋runtime-measured |
| 金钱框 | WINDOW40 (416,440)，金额右对齐；Wine「$: 70」 | static-derived＋runtime-measured |
| 滚动条对象 | WINDOW20 建立时 `0x438330` 总调 `0x446060(父=WINDOW20, 150, 151, 152, 153, x=宽−24=200, y=0, 行数, pos=*0x4c1cd4, 每页 9, 回调 0x4364c0)`，坐标相对 WINDOW20，随面板滑入由 `0x445f70` 同步。150 VScroll_Bar（`defProcScrollBar` `0x445860`）WIN02BAR.SHP 24×264，上下红箭头画在图里；151 Bar_Block（`defProcReturn`）BAR_BLK1.SHP 14×478，engRANGE 裁到滑块高；152 Bar_Up（`defProcScrollStep` `0x445cd0`）BAR_UP.SHP 14×16；153 Bar_Down 同 BAR_DOWN.SHP；150 的绘制回调 `proc(obj, −1)` 在滑块底 2 px 画 BAR_BLK2.SHP 14×2（`0x44614f` 装入 151 `+0xa8`）；全部原点 (0,0)。屏幕：底槽 (212,174)、上箭头 (217,179)、下箭头 (217,417)、滑块 x 217 宽 14，行程 y 196–416（`+0x6c`＝16+6，`+0x74`＝264−22） | static-derived |
| 滑块 | `0x445d70`：高 H＝⌊⌊9·65536/n⌋·220/65536⌋，顶＝196＋⌊220·pos/n⌋，pos 夹在 [0, n−9]。n ≤ 9 时 150 每 tick 给四个对象置本帧不画（`0x10000000`）并返回，键也不处理，即十行起才有滚动条。10 行 H 197（顶 196／218）；11 行 H 179（196／216／236）；12 行 H 165（196／214／232／251） | static-derived |
| 滚动条操作 | 箭头：按下 engFLASH＋色 0x4208（像素与 (66,65,66) 各半平均，变暗）；松开时仍在按住状态才置 `+0x90` 位 1，150 消费后 pos ∓1；按住移出箭头即复位、不生效；没有长按连发，到顶／底只是夹住。底槽：按下时鼠标 y 在滑块顶之上 pos −9、在顶＋H 之下 +9，同一次按住随即进入拖动（抓点＝鼠标 y − 滑块顶）；拖动中滑块顶＝鼠标 y − 抓点，夹在 [196, 416]，≥ 416−H 时取 416−H−1，平滑跟随；列表 pos＝⌊(顶 − 196＋⌊110/n⌋)·n/220⌋（`220/(2n)` 整除）整行跟随；松开时 `0x445d70` 把滑块吸附到 pos。键：`0x445f00(sb, 0x8000000, 0x10000000, 0x40000, 0x80000)`，新按下的 ↑／↓ ∓1、PgUp／PgDn ∓9（`[0x4c6390]` 高半字 4／8／0x800／0x1000）。滚轮：WndProc 只分派 0x200–0x209，0x20a WM_MOUSEWHEEL 落到 DefWindowProcA（`0x456e87`、表 `0x457200`、`0x456fa5`） | static-derived |
| 开页位置 | `0x43add0` 每次开页新建 WINDOW20 并置 `+0xa0 = 2`；`0x438160` 首个 tick 见页字不是 5（魔法）／10（特殊技）就写回页字、`*0x4c1cd4 = 0`、`0x445d70(sb, 行数, 0, 9, 0)`——每次开页从第 0 行起；换人（`0x43aa56`、`0x42a793` 置 `0x4c1cd0` 位 0）同样清零 | static-derived |

## 不支持的结论

- 版本号的点阵字形与颜色梯度没有导入；只对齐了墨迹外框。
- 標題 戰場記錄 的亮起停留与淡黑只量了 開始新故事 一次，戰場記錄 沿用。
- 完成提示的淡入淡出只有一次样本；右下角小方块（录屏里 BOARD02 旁的指示）未识别，重制不画。
- I_RECT02..08 是同一框的其他配色，何时使用未读；重制只用 01。
- 任務說明 面板在原版里的淡入时长与开场是否相同只量到起止（577.55 出现、579.48 按键收起），重制沿用开场的 32 tick。
- 技能页：超过九行的滚动条只有静态读法——本机三份回憶錄存档（席達鎮 等級08、黃昏之丘 陰 等級18、兩棲族部落 等級24）里没有带十个以上技能的角色，Wine 实拍拍不到；悬停脉冲只有两帧样本，证明亮度在变，周期与相位来自静态读法；名字宽度原先因系统字对不上原版（63 对 71 px），lane FONT 换 FONT.24 点阵后一致。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleSystemMenu.gd` timing：save notice 582.53–582.77 s in, held to 583.73 s, out by 583.87 s; 任務說明 board dissolves in 577.55–577.95 s and out 579.08–579.48 s — BattleWinFailBoard's 32／34-tick dissolve

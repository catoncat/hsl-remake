# 菜单与界面：标题、目标光标、系统卷轴、状态页与技能页的原版测量

> evidence: runtime-measured: 2026-09-24 原版录屏（605.8 s，可变帧率约 57 fps）的逐帧像素、SHP 模板匹配与音轨互相关，2026-09-26 Wine 原版实拍技能页三帧（§5，cnc-ddraw 游戏窗截图），2026-09-28 Wine 战斗卷轴开启与回憶錄列表四帧及 `0x4c1b00` 读数（§3）; resource-derived: I_RECT01.SHP、BOARD02.SHP、WINDOW60.SHP、Title039／Title061、WAV 表; static-derived: 状态窗 mode 10 与 WINDOW20／21 的既有读法（static_reverse/original_growth_window.md）、状态页 mode 0／1 板与页按钮 `0x43ac10`／`0x43a640`／`0x443cfa`（§4）、技能页 `0x43b4e0`／`0x438160`／`0x434d10`／`0x433a90`／`0x4331b0`、滚动条 `0x446060`／`0x445860`／`0x445d70`、悬停脉冲 `0x42c110`／`0x42c130` 的读法（§5）、預備動作 开关 `0x424590`／`0x401e74`（§預備動作）、战斗卷轴开启条件 `0x4082ab` 与 讀取回憶錄 去向 `0x425842`（§3）、卷轴卷动 `0x4253f0`／`0x425a90` 起点与 `0x45e882`／`0x45e91e` 逐 tick 步进（§6）; provisional: 只在这一份录屏出现一次的时长与未命中的声音；回憶錄列表与標題语义等重制读法（§6） · status: live · functions: 0x401c20, 0x401e74, 0x4030f7, 0x403199, 0x4031c7, 0x4081c0, 0x423c10, 0x424560, 0x424590, 0x424680, 0x4253f0, 0x425a90, 0x45e882, 0x45e91e · tools: hsl_original_control.py, hsl_video_events.py, run_battle_scene_runtime_tests.gd, run_presentation_contract_tests.gd, run_skill_resolution_tests.gd, run_system_menu_tests.gd, run_title_screen_tests.gd · updated: 2026-09-28

## 结论

- 原版：标题版本号「V1.06」常驻左下，悬停只有火花不亮起，確認「開始新故事」亮起停 0.75 s 再 0.55 s 淡黑，離開遊戲 同样先经按住计时再淡出退出，戰場記錄 无记录弹消息 12「無存檔記錄」；目标格光标（玩家选目标与敌方预告）都是 `I_RECT01.SHP` 黄框；系统卷轴打开放 ACCEPT01，確定／取消压在卷轴中央 (256,217)、无问句、不压暗，存档完成提示在 BOARD02 (75,320)；战斗卷轴只在刚打开的玩家行动环上按 Esc／右键才开（选格、移动后的环、敌方回合、首个行动环之前、额外行动都不开），其 讀取回憶錄 开 Title031 八格读取列表；状态页开页总是属性页，状态页页按钮排在 y 387；技能页是状态窗 root mode 8／9，十行起才有滚动条；系统卷轴战斗版自静止位下方 400 px、大地图版自上方 600 px 卷入，展开每 tick 走剩余距离的 1/8（封顶 40、至少 2 px），收起 40 px/tick 回起点（runtime-measured；static-derived）。
- 重制：`BattleSelectionCursor`／`BattleAttackCue` 画 I_RECT01，`TitleScreen` 原版值悬停不亮起、三项同一亮起停留与淡黑，`BattleSystemMenu` 开卷放 ACCEPT01、照原版位置与时长出確定／取消（原版值无问句）与完成提示，`BattleStatusPanel`／`BattleMagicPanel` 按 mode 0／1 与技能页读法落地；預備動作 开关做在 設定選項 第二行（`GameSettings.ready_action`）（runtime-measured）。
- 差异：标题悬停亮起与卷轴确认问句收进 OPT-GUIDE＝提示；标题悬停火花的字形未认定、不画；回憶錄列表、標題语义与 GAME OVER 位置时长是重制读法；只有一份录屏样本的时长与未命中的声音保持 provisional（provisional）。

## 证据

### 方法

- 录屏：2026-09-24 原版录屏（605.8 s，私有档案，不入库），游戏区 `crop=1280:960:112:140`，缩到 640×480 逻辑像素；时刻是视频 PTS 秒。
- 像素：ffmpeg `signalstats` 逐帧平均亮度（标题淡黑）、白色墨迹外框（版本号）、SHP 预览图对录屏的模板匹配（在候选区域按 1 px 步长求平均绝对差最小值，下称"模板差"，0 为逐像素相同；缩放与压缩使完全命中约 9–21）。
- 声音：`tools/hsl_video_events.py audio`——10 ms 包络起点，以及 220 个原版 WAV 在所给时段内的归一化互相关（NCC）最佳位置。
- 原始帧、局部放大与匹配日志在 `ignored/`，不入库。

### 1. 标题画面

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 版本号 | 左下常驻白字「V1.06」，定宽点阵字 8 px 步进，墨迹 (3,459)–(41,467)，整段录屏不变 | runtime-measured | 没有 | ASCFONT.15 半角字（8×15 格，墨迹行 3–11、列 1–7），格左上 (2,456)，墨迹 (3,459)–(41,467) 与原版逐像素一致 |
| 確認「開始新故事」 | 点击后该项红色亮起字形（Title024 系）在 13.52 s 出现，停 0.75 s；14.27→14.82 s 整屏亮度线性降到黑（0.55 s） | runtime-measured | 0.6 s 直接淡黑 | 亮起停 0.75 s，再 0.55 s 淡黑（`CONFIRM_HOLD_SECONDS`／`FADE_TO_BLACK_SECONDS`）；戰場記錄 同用（provisional） |
| 悬停 | 原版悬停只有火花，红色亮起出现在点击时 | runtime-measured | 悬停即亮起 | 原版值悬停不亮起；OPT-GUIDE＝提示 时悬停项亮起；方向键选中项亮起（重制键盘路径）；火花字形未认定，不画 |
| 離開遊戲 | 标题 handler `0x423f00`：每项先经 state 3 `0x424004` 按住计时，码 2 `0x4240b2` 经 `0x42cb60`（置 `0xa0000000`）与 `0x42dc90(2)` 淡出后退出 | static-derived | 立即退出 | 同 開始新故事 亮起停 0.75 s、0.55 s 淡黑后退出（时长沿用，provisional） |
| 戰場記錄 无记录 | 码 1 `0x42404c`：`0x42ebe0(0)` 失败时 `0x4072b0` 弹消息 11「讀取存檔失敗」或 12「無存檔記錄」（按 `0x4c43b8`） | static-derived | 底部提示字「沒有戰場記錄」1.6 s | 无可恢复进度时 BOARD02 (75,320) 消息「無存檔記錄」，出入时长沿用存档完成提示（provisional）；重制无"读取失败"路径，不出消息 11 |
| 点击声 | 13.59 s 有一个短起点（峰值 −43.6 dB）；最高 NCC Walk0011 0.34、Accept01 0.31，都不够认定 | negative-evidence | 无声 | 无声（未认定前不加） |

早先模型描述的"停约 10 s 再淡黑约 2 s"与录屏量值不符：亮起到全黑一共 1.30 s。

### 2. 目标格光标（玩家选目标与敌方攻击预告）

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 形状 | 黄色格框，四角有饰纹，32×32：`I_RECT01.SHP`（黄色渐变 238,222,0 → 139,121,0）。模型描述里的"菱形"就是这个框 | resource-derived＋runtime-measured | 玩家选目标：青绿呼吸角括号；敌方预告：淡黄角括号方块 | 两处都画 I_RECT01 |
| 玩家选目标 | 178.0 s 目标格 (320,220) 上的黄框 | runtime-measured | 同上 | `BattleSelectionCursor` 在攻击／魔法／特殊选目标时画 I_RECT01；选移动格仍是重制的角括号 |
| 敌方预告 | 97.6 s (318,176)、199.1 s (316,192)、256.5 s (304,172)：同一黄框停在被攻击者格上；画面上没有玩家式选择框 | runtime-measured | 敌方预告期间，鼠标停在格上时玩家选择框也会出现 | `BattleAttackCue` 用同一张 I_RECT01；玩家选择框只在 `Interaction.TARGETING` 显示，敌方回合不出现 |
| 底部卡片 | 普通攻击选目标时底部只有一张卡（头像＋数值条＋WINDOW10 身份条，178.0 s），与重制相同；"施术者＋目标两张卡"只出现在特殊技流程 | runtime-measured | 一张目标卡 | 不改（特殊技页见 §5） |

### 3. 系统卷轴：任務說明、存档确认与提示

| 项 | 原版量值 | 等级 | 重制前 | 重制后 |
| --- | --- | --- | --- | --- |
| 確定／取消 | Title061（128×47）压在打开的卷轴中央 (256,217)，没有问句、没有压暗；所选项在提示期间保持红色亮起。582.0 s 儲存戰場記錄（模板差 17.1）、592.5 s 回主選單（9.5） | runtime-measured | (256,300)，全屏压暗 55%，亮起项隐藏；卷轴下方常驻问句 | (256,217)，不压暗，亮起项保留；原版值无问句，OPT-GUIDE＝提示 时卷轴下方加问句（remake-invented） |
| 儲存戰場記錄 | 点击后先问確定／取消（581.0 s）；確定后卷轴不关 | runtime-measured | 直接保存、关卷轴、顶部横幅 | 先问；確定后存档，卷轴保持打开 |
| 完成提示 | 「進度儲存完成」在无头像、居中的 BOARD02 消息板上：板 (75,320)（583.5 s 模板差 13.2），582.53→582.77 s 淡入，停到 583.73 s，583.87 s 前淡出 | runtime-measured＋resource-derived | 顶部「戰鬥已保存（F9 讀取）」横幅 | BOARD02 (75,320) 居中文字，0.25 s 入、0.95 s 停、0.15 s 出 |
| 存档声音 | 582.28 s 起点（確定 点击）最高 NCC Walk0010 0.73；582.8 s 第二个起点 Put00003 0.52 | provisional | 无声 | 无声（单一样本，未认定） |
| 任務說明 | 577.55–579.48 s：卷轴上方淡入与开场同一块 WINDOW60 胜负条件面板 (136,108)，绿色「勝利條件」「失敗條件」标题各带一行条件，停到按键 | runtime-measured | WINDOW60 居中卡片、表现侧文案 | 同一 `BattleWinFailBoard`（开场用的那块）在 (136,108) 淡入，等输入；Esc 淡出回卷轴 |
| 設定選項 | Title039 居中 (142,90)，588.0 s 模板差 21.4 | runtime-measured | 同位置（provisional） | 不改，证据等级升为 runtime-measured |
| 开启时机 | 关卡控制对象 defProcBattleBOSS（`0x4081c0`，过程表第 6 项）每 tick：`[0x4c1b00] & 0x7e000000` 为 0 且额外行动计数 `[0x4c1cf0]` 为 0（`0x4082ab`／`0x4082b7`）时，Esc（`[0x4c6390] & 0x100000`）或右键（`[0x4c6398] & 0x20000`）即置 `0xc0000000`、放 ACCEPT01（RESOURCE 398）、`0x423c10` 建对象 787（Battle Menu，TITLE041，defProcBattleMenu 49）。`0x2000000` 在开战 `0x42c6b4` 与按下行动环图标 `0x43e91a` 时置位，只在新行动环打开 `0x443a52` 时清除；`0x4000000` 剧情／状态链，`0x8000000`／`0x10000000`／`0x20000000` 结束与转场。Wine：环刚打开时读数 0、Esc 开卷轴后 `0xc0000000`；移动选格读数 `0x02000000`，Esc 退回行动环；敌方回合 `0x02c00000`／`0x02100000`，Esc 无卷轴 | static-derived＋runtime-measured | `action_menu` 且检查点控制器 `quiet()` 时 Esc 开，右键不开 | 同门槛再加：移动后的环（`pending_move_revert`）与额外行动（`extra_action.pending`）不开；Esc 与右键都开，否则照旧取消 |
| 讀取回憶錄 | 战斗卷轴过程 `0x4253f0` 项 2（`0x42583c`）调 `0x423bd0(…, 0)`——与大地图卷轴项 2 同一调用——直接开「读取回忆录」八格列表，不先问確定／取消（Wine 帧：三格有记录、五格「无记录」） | static-derived＋runtime-measured | 直接读自动记下的战役位置，没有就提示「沒有回憶錄」；先问確定／取消 | 开同一张回憶錄列表（`_show_memoir_list("load")`），选有记录的格问確定／取消后经 `_resume_memoir_slot` 放弃本场读入 |

同类盘点（`run_system_menu_tests._run_confirm_class_inventory`）：两种卷轴里写记录或离开当前游戏的项——战斗卷轴 儲存戰場記錄／讀取戰場記錄／回主選單，大地图卷轴 讀取戰場記錄／回主選單——都走同一个 Title061 提示；回憶錄列表里覆盖已有格与读取已有格也用同一提示。未纳入：状态页的保存／读取按钮（OPT-GUIDE＝提示 才有）与 F5／F9 快捷键（重制补充），仍即时执行并用顶部横幅。

### 4. 状态页（左栏默认就是属性页；钱框只在行动环 狀態 页）

| 项 | 原版 | 等级 | 重制 |
| --- | --- | --- | --- |
| 两个入口 | 行动环 狀態 `0x444285`（`push 0`）→ `0x43b4e0` mode 0；移动选格态（phase 20 子态 0 `0x443c63`）点非己方指挥单位 `0x443cfa` → mode 1，关窗子态 11 `0x4440b7` 回选格；行动环 98／74 无点单位分支；且只对已知单位开（未知落到 `0x443d9d`，同点空地，[身份栏包](../../static_reverse/original_identity_bar.md#显示未知单位信息的原版界面static-derived)） | static-derived | `BattleSceneMenus` 狀態 → `show_unit(…, own_page=true)`；`BattleSceneInput` 只在 `MOVE_SELECT` 点非可指挥单位时，先问 `BattleStatusPanel.opens_for(known)`，再 `show_unit(…, known, false)`；OPT-INFO＝公開 时一律开 |
| 板 | mode 0／1 同建 130 头像 (12,14)、131 WINDOW10、145–147 三条、132 WINDOW20 (12,174)、133 WINDOW30（`0x43ae70`，停靠 x 252）；mode 0 另建 134 `$:` WINDOW40（`0x43af60`，y 440）与 137 上一位／142 下一位，mode 1 跳过这三个（`in_stack_8 != 1` 分支） | static-derived | mode 1 的页不画钱框（`gold_board`／`gold_label` 随 `own_page`） |
| 左栏 | `0x43ac10` 建根对象时 `+0x94 = 4`，WINDOW20 过程（`0x438160` case 2）按它分页：4＝属性（帧 +1 → WINDOW21，九行属性）、1＝道具（`+0x138` 八格，行高 32，悬停出说明）、2＝魔法、3＝特殊技；只有页按钮（`0x43a640` case 3 `default: root+0x94 = Data6`）改它——开页总是属性页 | static-derived＋runtime-reference | 重制左栏本来就是 WINDOW21 九项属性，与原版默认页相同，不改 |
| 页按钮 | y 387 一排 42×42 图标（`0x43b0a0`..`0x43b230` 停靠 y 387）：mode 1 四个——狀態（141 BCMD13，Data6 4）、道具（138，1）、魔法（139，2）、特殊技（140，3）；mode 0 另加上一位（137）／下一位（142）；当前页那颗置 `0x10000000` 画暗。`06_status_and_stats_screen/frame_028`（638 px 宽）红框行 366–406、首钮列 264–304：钮心 y 386.5，与停靠 387、图标高 42 一致；接触表 frame_001..016 开页即属性页，frame_018 按 道具 后才列 回復藥×3／解毒草，frame_026／028 是 特殊技 页 | static-derived＋runtime-reference | `BattleStatusPanel.PAGE_BUTTONS`：钮心 x 按各建钮函数的 `+0xaa`——上一位 285（`0x43b0a0`）、下一位 346（`0x43b230`）、道具 407（`0x43b140`）、狀態 468（`0x43b0f0`）、魔法 529（`0x43b190`）、特殊技 590（`0x43b1e0`），y 387；图形与字样取 obj-051.obs 137–142（B_PREV1／B_NEXT1／BCMD03／BCMD13／BCMD09／BCMD10，obj_Data9 → RESOURCE 133／134／19／40／28／29）；mode 1 不出上一位／下一位；当前页画暗；道具页八格、魔法／特殊技页列表（只读，悬停出说明）；上一位／下一位在可指挥的在场单位间按名册顺序循环（换人顺序 provisional） |
| 说明框 | 悬停装备（WINDOW30 过程 `0x430710`＋`0x436d70`）或道具行时 WINDOW50 (252,349) 盖在按钮排上（frame_006：悬停 铁护轮 时按钮排不见） | static-derived＋runtime-reference | `BattleEquipmentView` 悬停有物品的槽才出 WINDOW50 (252,349) 与文字、名字变绿，移开即隐；道具／魔法／特殊技页的行同样悬停才出（`BattleStatusPanel.page_detail`） |
| 录屏 77.5 s／84.0 s | 雷歐納德、重裝兵 左栏是道具列表、手上拿着物品、有钱框、**没有页按钮**：这是物品／交换窗（`0x43b4e0` mode 4／5／7，根旗标带 `0x4000`）——WINDOW30 过程在 `0x4000` 下鼠标不在装备板时把 `+0x94` 写 1（道具）、拿着物品移上装备板写 4（属性），不是状态页；此前「状态页左栏是道具列表」的读法据此更正 | static-derived＋runtime-measured | — |

重制补充（原版没有）改挂选项，原版值下都不显示：永久加值／入场成长行与属性、抗性悬停说明归 OPT-INFO＝公開；底部「保存 F5／讀取 F9／待領物品／返回」按钮条归 OPT-GUIDE＝提示；「成長點」随 OPT-GROWTH 暂缓路径（有点数才显示，原版值点数总在升级窗里分完）。读点见 `content/authored/options/remake_options.json` 两张卡的 `read_points`。

### 5. 技能页：特殊技与魔法（进入流程、布局、原版实拍、滚动条、列表顺序）

页面是状态窗的另一种 root mode，不是独立列表板。来源三路：hsl01.exe 静态读法（地址）、2026-09-24 原版录屏 238.8 s 帧、2026-09-26 Wine 原版实拍（`tools/hsl_original_control.py` 的 cnc-ddraw 游戏窗截图，回憶錄 第 1 行 `level06_pre_battle` 进第 6 关，只截游戏窗口）。本目录三帧：skill-page-magic-hover.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-magic-hover.png`）（緹娜 魔法页，悬停 水剎）、skill-page-special-red.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-special-red.png`）（琥 特殊技页，氣力 0 付不起 毒魔箭）、skill-page-special-red-hover.png（原版帧见私有档案：`runtime_observations/menus_ui/skill-page-special-red-hover.png`）（同页悬停该行）。cnc-ddraw 把 RGB565 左移展开，帧里白色是 (248,252,248)，颜色比 8 位原值低 3–7。

| 项 | 原版 | 等级 |
| --- | --- | --- |
| 进入 | 按「特殊技」总先开技能页：46.5–54.75 s 首控（雷歐納德 只有 氣刃斬，氣力槽空）打开页、再取消回行动环；237.9–239.6 s 与 423.6–429.6 s 先开页，选 氣刃斬 之后才出现技能格与底部目标卡（240.4 s）；Wine：琥 氣力 0 也开页，右键回行动环 | runtime-reference＋runtime-measured |
| 页面 | `0x43b4e0` case 8 魔法（root `+0x94 = 2`）／case 9 特殊技（`+0x94 = 3`），开页把已选码 `*0x4c2c40／44／54／94` 置 −1；挂 130 头像 (12,14)、131 WINDOW10 (381,14)（原点 (248,0)，左缘 133）、132 WINDOW20 (12,174) 224×264（`0x43add0`）、134 `$:` WINDOW40 (416,440)（`0x43af60`）；地图压暗（平均亮度 79.9→37.9）。Wine 两页四块板模板匹配都在 WINDOW10 (133,14)、WINDOW20 (12,174)、WINDOW40 (416,440)、说明框 WINDOW50 (252,349) | static-derived＋runtime-measured |
| 行 | `0x438160` case 2 魔法（列表 `0x4c30e0`、行数 `0x4c1cd8`、页字 5、说明 `0x4331b0`、可选判 `0x408fe0`）／case 3 特殊技（`0x4c2cc0`、`0x4c1cdc`、10、`0x433a90`、`0x409040`）：首行距框顶 8（+0x9a）、行高 28（+0x98）；名字 x＝框 x+8+24（`0x4123b0`）；元素宝石 MAGICON[type] 在 (框 x+15, 行+2)（`0x4607f9`，表 `0x4c3460`；type 5／6 不画）；行文字整块画在 y+8−28·pos，裁到 (x, y+8)–(x+224, y+258)，第九行少 2 px。Wine：水剎 墨迹 x 45–91、y 187–202，治癒之水 x 46–139、y 215–230，宝石 (27,184)–(35,202)／(27,212)–(35,230)；238.8 s 氣刃斬 x 45–115 | static-derived＋runtime-measured |
| 顺序 | `0x434d10`（魔法 `0x436010`–`0x4361c4`，特殊技 `0x436253`–`0x436408`）：类型 t 外层（魔法 0..5＝地、水、風、火、心靈、其他；特殊技 0..6 多「其他2」），每类 magicCode 位 0..31（magicCode01＝位 0）内层，只列 actor 掩码（魔法 `+0x174+4t`，特殊技 `+0x158+4t`）置位且表里有的项；付不起的也列（@2，项 `\|0x80000000`）；每行＝@1／@2＋名字补空格到 18 字节＋`#`，没有消耗数字列。Wine：水剎（水 位 0）排在 治癒之水（水 位 5）前 | static-derived＋runtime-measured |
| 悬停 | 没有光标条。悬停行＝(鼠标 y − 框 y − 8)/28，须在 0..8 且加 pos 后小于行数（横向整框，Wine 在 x 200 仍命中）；该行说明进说明框，名字由 `0x4132f0` 模式 1 重画成 `0x42c130` 的颜色：R、B 基值 0（`[0x4c1c68]`／`[0x4c1c6c]`），G 基值 255（.data `0x477c28`），各减 2·\|p\|、下限 0，p 是帧体 `0x42d600` 每 tick 调 `0x42c110` 加一的 −16..16 计数（33 tick 一周，[tick 率](../original_tick_rate/README.md)）——绿色在 223–255 往复。Wine 两帧 G 236／244（RGB565 六位 59／61），238.8 s 录屏 224–255；不是色表 `0x476b44` 的 @3 (205,255,205)（说明框首行用它） | static-derived＋runtime-measured |
| 付不起的行 | `0x434d10` 给付得起的行 @1 白、`0x409040`／`0x408fe0` 拒绝的行 @2 红（色表 0xfa8a＝(255,82,82)）。Wine：琥 毒魔箭（消耗 1、氣力 0）红字 (248,80,80)；悬停照样变脉冲绿 (0,236,0) 并出说明；点击时 `0x438160` 先过可选判，拒绝就不进选格 | static-derived＋runtime-measured |
| 说明框 | `0x436d70` 框 (252,349) 376×88，行 (x+8, y+12+16i)、360 px 居中、首行 @3 绿（[getitem 窗静态读法](../../static_reverse/original_getitem_window.md#证据)）；四行由 `0x433a90`（特殊技）／`0x4331b0`（魔法）写：名字（魔法加「 (地系)」…）；氣格消耗N（特殊技元素加「, 屬性: 地系」）／魔法消耗N；威力行（function bit 1 基礎攻擊力 lo~hi、否则 bit 2 基礎回復力，后接异常、解除、辅助词，特殊技再接回復魔法…吸取敵人生命，整组齐全时合成一词）；命中率N%,對象一名／多名（effect_range＝0 即 range0Cell 为一名，RESOURCE 239／240；魔法写「魔法命中率N%, 對象…」）。238.8 s「氣刃斬／氣格消耗1／基礎攻擊力36~54／命中率98%,對象一名」；Wine「水剎 (水系)／魔法消耗8／基礎攻擊力16~24／魔法命中率94%, 對象多名」「治癒之水 (水系)／魔法消耗6／基礎回復力24~36／魔法命中率100%, 對象一名」「毒魔箭／氣格消耗1, 屬性: 心靈系／基礎攻擊力30~45 中毒傷害／命中率98%,對象多名」 | static-derived＋runtime-measured |
| 金钱框 | WINDOW40 (416,440)，金额右对齐；Wine「$: 70」 | static-derived＋runtime-measured |
| 滚动条对象 | WINDOW20 建立时 `0x438330` 总调 `0x446060(父=WINDOW20, 150, 151, 152, 153, x=宽−24=200, y=0, 行数, pos=*0x4c1cd4, 每页 9, 回调 0x4364c0)`，坐标相对 WINDOW20，随面板滑入由 `0x445f70` 同步。150 VScroll_Bar（`defProcScrollBar` `0x445860`）WIN02BAR.SHP 24×264，上下红箭头画在图里；151 Bar_Block（`defProcReturn`）BAR_BLK1.SHP 14×478，engRANGE 裁到滑块高；152 Bar_Up（`defProcScrollStep` `0x445cd0`）BAR_UP.SHP 14×16；153 Bar_Down 同 BAR_DOWN.SHP；150 的绘制回调 `proc(obj, −1)` 在滑块底 2 px 画 BAR_BLK2.SHP 14×2（`0x44614f` 装入 151 `+0xa8`）；全部原点 (0,0)。屏幕：底槽 (212,174)、上箭头 (217,179)、下箭头 (217,417)、滑块 x 217 宽 14，行程 y 196–416（`+0x6c`＝16+6，`+0x74`＝264−22） | static-derived |
| 滑块 | `0x445d70`：高 H＝⌊⌊9·65536/n⌋·220/65536⌋，顶＝196＋⌊220·pos/n⌋，pos 夹在 [0, n−9]。n ≤ 9 时 150 每 tick 给四个对象置本帧不画（`0x10000000`）并返回，键也不处理，即十行起才有滚动条。10 行 H 197（顶 196／218）；11 行 H 179（196／216／236）；12 行 H 165（196／214／232／251） | static-derived |
| 滚动条操作 | 箭头：按下 engFLASH＋色 0x4208（像素与 (66,65,66) 各半平均，变暗）；松开时仍在按住状态才置 `+0x90` 位 1，150 消费后 pos ∓1；按住移出箭头即复位、不生效；没有长按连发，到顶／底只是夹住。底槽：按下时鼠标 y 在滑块顶之上 pos −9、在顶＋H 之下 +9，同一次按住随即进入拖动（抓点＝鼠标 y − 滑块顶）；拖动中滑块顶＝鼠标 y − 抓点，夹在 [196, 416]，≥ 416−H 时取 416−H−1，平滑跟随；列表 pos＝⌊(顶 − 196＋⌊110/n⌋)·n/220⌋（`220/(2n)` 整除）整行跟随；松开时 `0x445d70` 把滑块吸附到 pos。键：`0x445f00(sb, 0x8000000, 0x10000000, 0x40000, 0x80000)`，新按下的 ↑／↓ ∓1、PgUp／PgDn ∓9（`[0x4c6390]` 高半字 4／8／0x800／0x1000）。滚轮：WndProc 只分派 0x200–0x209，0x20a WM_MOUSEWHEEL 落到 DefWindowProcA（`0x456e87`、表 `0x457200`、`0x456fa5`） | static-derived |
| 开页位置 | `0x43add0` 每次开页新建 WINDOW20 并置 `+0xa0 = 2`；`0x438160` 首个 tick 见页字不是 5（魔法）／10（特殊技）就写回页字、`*0x4c1cd4 = 0`、`0x445d70(sb, 行数, 0, 9, 0)`——每次开页从第 0 行起；换人（`0x43aa56`、`0x42a793` 置 `0x4c1cd0` 位 0）同样清零 | static-derived |

### 6. 标题、战间卷轴与設定選項：重制读法

重制窗口回执的截图留在 [title_screen/](../title_screen/) 与 [system_menu/](../system_menu/) 目录（runtime-measured，重制侧，视觉评审输入，不是原版等价证明）。

| 项 | 读数 | 等级 |
| --- | --- | --- |
| 标题布局 | `hsltools/assets/title_assets.py` 解码 PAK `Title001／002／021–028`；`hsl_title_layout_probe.py` 对原录像参考帧模板匹配：标志 (99,12)、圆环 (197,161)、石像 (117,227)／(405,227)、宝珠／书参考位 (216,257)／(386,243)，逐 shape 平均色差 10–22 | resource-derived＋runtime-measured |
| 宝珠与书 | 周期 1.646 s、振幅 5 px 的正弦，围绕参考位下方 3 px 往返，起始相位随机，不随选择移动（[original_title_ornaments](../original_title_ornaments/README.md)） | provisional（拟合值） |
| 标题菜单语义 | 「戰場記錄」先恢复最近一份战斗检查点，否则接单槽战役进度；「開始新故事」清空进度，不清回憶錄与检查点；无存档时出消息「無存檔記錄」（§1） | provisional |
| GAME OVER | 原版败北无结果页（`0x42cbd0`），160 tick 无输入自回标题（`0x42aea0`）；重制败北约 0.2 s 淡黑后显示 Title011＋Title012（居中）、淡入 0.9 s、任意键淡出 0.6 s 回标题；原版败北画面无录像 | static-derived；provisional：位置与时长 |
| 系统卷轴 | 停在 (190,67)（对原版 `05_system_scroll_menu` 帧 003 模板差 10.6）；亮起框中心对齐字行中心 (128,56)；键盘选择也亮起、確定／取消预选取消 | runtime-measured；provisional：预选 |
| 系统卷轴卷动 | 战斗卷轴过程 `0x4253f0`：起点 y＝静止 y＋400（`0x42549b`），状态 0 每 tick `0x45e882(当前, 静止, 40)`，到达后把起点抄成目标（`0x42569b`）；状态 4 `0x45e91e(当前, 起点, 40, 0)` 收起后删对象（`0x425969`）。大地图卷轴 `0x425a90` 起点 y＝静止 y−600（`0x425b3b`），同一对步进（`0x425d22`／`0x425fbf`）。`0x45e882`：距离＝isqrt(dx²+dy²)，≤1 即对齐并返回 0，否则步长＝min(40, 距离>>3)、至少 2；`0x45e91e` 同式、右移位数取参数（此处 0），即 40 px/tick。战斗版展开 35 tick、收起 11 tick；大地图版 40／16 tick | static-derived |
| 战间卷轴 | Title051 位置沿用 (190,67)；讀取戰場記錄 恢复修改时间最新的战斗检查点 | provisional |
| 回憶錄列表 | Title031 居中 (87,44)，Title033 抬头，八条槽带 x 63–407、首带 y 80、间距 33，存 `user://memoir_NN.json`（槽数依 Title031，文件布局与标签为重制值）；战斗与大地图卷轴共用（§3 有原版帧，未逐像素对位） | provisional |
| 設定選項 | Title039 居中 (142,90)，宝珠 Title027 作旋钮；場景效果＝剧情特效物件（雨／闪电／火焰／光环）是否绘制，音效音量＝Master，音樂音量＝Music 总线；原混音器未定位 | provisional：行语义 |

标题 handler 在 `0x423f00`（子状态跳表 `0x424158`、动作表 `0x424174`）；参考帧是 638×480 简体版录像，PAK 标题字形亦为简体，重制文字沿用 RESOURCE 繁体。战斗卷轴的开启条件见 §3「开启时机」；卷轴不改战斗真相。

### 預備動作（0x477c14 bit1）

static-derived（hsl01.exe v1.06）。預備動作 是原版的施法／绝技攻方起手动作开关，不跳过切入；重制做在 設定選項 第二行。

- 面板登记 `0x4247f6` 起四次 `0x446270`：四个控件都传同一组旋钮图 0x319–0x31c 与 x 0x9f，依 y 登记——y 95 开关（2 档，`0x424560`）、y 139 开关（2 档，`0x424590`）、y 194 滑杆（18 档，`0x4245c0` → `[0x477c20]`＝档×15 封顶 255）、其后第四个滑杆。按 Title039 行序（場景效果／預備動作／音效音量／音樂音量），第二个开关就是 預備動作。面板打开时 `0x424680` 从 `[0x477c14]` bit0／bit1 回填两开关的档位；`0x42ecdf` 把 `[0x477c20]`、`[0x477c14]&0xffff`、`[0x477c24]` 12 字节写进设置文件，`0x42ee01` 读回。
- `0x424590`：`0x445f60` 取开关档，非零 `[0x477c14] |= 2`，零 `&= ~2`。`[0x477c14]` 初值 3（两开关都开）。
- bit1 的唯一读者是攻方对象过程 `0x401c20`（攻击序列插入的对象 0x9a）的 `0x401e74`：`+0xa4` 为 0（普攻，插入者 `0x4424e4`／`0x442704`）时总是载入并播放攻击帧；为 1（施法例程 `0x442f26` 插入）或 2（`0x441d06` 插入，绝技）时，bit1 开且逐角色表 `[0x4c1b6c]+idx·44` 的起手帧存在，就逐帧 `0x460058` 载入并 `0x45e525` 播放起手（kind 1 先取 +0x14／+0x18／+0x1c 组、缺则 +0x20 组；kind 2 反之），再 `0x45f4b9(0x3c)` 重校节拍器；bit1 关则对象隐藏（`+0x30 = 0xffff`），直接进 `+0x8c = 0x660007`（kind 1，另置 `+0x80` 0x1000 位）或 `0x660008`，不播起手。
- 第一个开关（bit0，`0x424560`）的读者是地图物件过程（`0x43c337`／`0x43c63f`／`0x43cecd`／`0x43d13e`／`0x43d758`：云等背景物件关时不画不走，[地图物件漂移](../../static_reverse/original_map_object_drift.md)），与 場景效果 的行义一致。
- 关掉时的走向（`0x401e74..0x401efa` 与 phase 102 子状态 5–9）：bit1 关与"该角色没有起手帧"（`0x401e87` 张数为 0、`0x401e8d` 首张为 0）跳到同一处 `0x401ec4`，所以关掉＝按没有起手的施法者处理；起手帧不预载、起手程序（`+0x1c`／`+0x28` 组：aniSetXYDisp／aniShadowBG／aniMoveToCenter／aniInsertCastObject）一条不执行，横幅（`+0x30 = 0xffff` 隐藏）、残影（`0x401220` 只由 aniSetXYDisp 与子状态 1 调用）、局部图、肖像全都不出。对象过程在设置这一 call 里就接着按新 phase 分派（`0x401f1c`），下面的 call 数都含这一 call。
- 法术（kind 1，`0x442f26` 插入，`0x4c1408 = 0`）：`+0x80 |= 0x1000`（aniShadowBG 用的同一压暗位）、`+0x90 = 0`、进子状态 7（`0x4030f7`）：每 call `+0x90++`，`cmp +0x90, bp(8); jbe` 让出——第 9 个 call 调 `0x4071e0` 施法者地图姿势、`0x408b20(x, y − h, 4, 0, 3)` Cast_Star、放 `0x193`（施法音），与开着时引导末 `0x402fd1` 同一组；再下一 call 子状态 5（`0x403089`）清 `0x4c1b00` 的 `0xc00000` 切入位、推进链接对象（`+0xa8` 的 `+0x8c++`），子状态 6（`0x4030b7`）把 `+0x90` 倒数 9 个 call 后销毁自己。停顿只剩 8 个压暗 call（开着时緹娜 002 引导 130 call）。
- 绝技（kind 2，`0x441d06` 插入，`0x4c1408` = 攻方 EFFECTS 程序）：不置压暗位，进子状态 8（`0x403199`）：`+0xa0 = 10`、`+0x28 = 16`、`0x4c6f70 = 0x20002`、`+0x84 = 0`，子状态 9（`0x4031c7`）与子状态 4 同形——`+0x84` 计 16 个 call、`+0xa0` 倒数 10 个 call，然后见 `0x4c1408` 非零：调 `0x4607f9`（参数含 (320,240)，未读）后以它为程序指针进 phase 103（`0x403272`，−1 则 phase 101 结束）。停顿是 1＋16＋10 = 27 个 call 的隐藏等待（开着时雷歐納德 139 call）；等待期间屏幕底图未读（重制显示未压暗的地图，provisional）。
- 普攻（kind 0）不经 `0x401e74`（`0x401dfd` 起自己的分支），不受此位影响。
- 重制：`GameSettings` 键 `ready_action`（默认开＝初值 3，写 `user://settings.json`，旧文件缺键补默认）；`BattleSystemMenu` 設定選項 第二行旋钮读写它；关掉时 `BattleCombatCutin.cast_lead` 对有起手条带的施法者返回 `AnimalCastLead.skipped`（法术 8 个压暗 call、绝技 27 个隐藏 call），`SkillEffectScriptPlayer` 的绝技与地图法术两条起手分支原样消费它；没有导入起手条带的施法者照旧走 Cast_Star 替身／站立帧（原版两档同路）。

## 重制接线

- 标题：`game/title/TitleScreen.gd`（版本号、`CONFIRM_HOLD_SECONDS`／`FADE_TO_BLACK_SECONDS`、宝珠与书浮动、`_refresh_lit` 悬停亮起读 OPT-GUIDE、`show_message` 无记录消息）；布局来自 `content/imported/hsl/global/title/manifest.json`。
- 目标格光标：`game/battle/scene/BattleSelectionCursor.gd`、`BattleAttackCue.gd`。
- 系统卷轴：`game/battle/scene/BattleSystemMenu.gd`——`open` 放 ACCEPT01（`runtime.play_ui_sound("confirm")`），`_ask` 出確定／取消、问句读 OPT-GUIDE；timing：save notice 582.53–582.77 s in, held to 583.73 s, out by 583.87 s；任務說明 board dissolves in 577.55–577.95 s and out 579.08–579.48 s（`BattleWinFailBoard` 的 32／34 tick 溶入溶出）；卷动 `_slide`／`_slide_tick` 逐原版 tick 复现 `0x45e882`／`0x45e91e`，起点取 `SCROLL_START_OFFSET`。
- 状态页与技能页：`BattleStatusPanel`、`BattleMagicPanel`、`BattleSceneMenus`、`BattleSceneInput`；provenance 头写 `runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md#5` 等。
- 預備動作：`game/settings/GameSettings.gd`（`ready_action`）、`game/battle/scene/AnimalCastLead.gd`（关掉时的 call 数）。
- 重制补充（原版没有）挂在选项上，原版值下不显示：见 `content/authored/options/remake_options.json` 的 `read_points`。

## 复现

不可再生：原版侧唯一记录（2026-09-24 原版录屏与 2026-09-26 Wine 实拍）。重制侧回归：`tools/godot.sh --headless --script tests/run_system_menu_tests.gd`。

## 边界

- 战斗卷轴开启条件：开场剧情中与首个行动环之前只有静态读法（`0x4000000`／`0x2000000`），Wine 只拍了行动环、移动选格与敌方回合三态；消息框打开期间 `0x413bce` 也置 `0x2000000`，重制由 `quiet()` 覆盖。
- 版本号的点阵字形与颜色梯度没有导入；只对齐了墨迹外框。
- 標題 戰場記錄／離開遊戲 的亮起停留与淡黑只量了 開始新故事 一次，二者沿用；`0x42dc90(2)` 的淡出时长未读。
- 标题悬停火花：录屏可见，字形与位置未认定，重制不画。
- 标题「無存檔記錄」消息的出入时长与是否等按键未读，沿用战斗卷轴存档完成提示。
- 完成提示的淡入淡出只有一次样本；右下角小方块（录屏里 BOARD02 旁的指示）未识别，重制不画。
- I_RECT02..08 是同一框的其他配色，何时使用未读；重制只用 01。
- 任務說明 面板在原版里的淡入时长与开场是否相同只量到起止（577.55 出现、579.48 按键收起），重制沿用开场的 32 tick。
- 技能页：超过九行的滚动条只有静态读法——本机三份回憶錄存档（席達鎮 等級08、黃昏之丘 陰 等級18、兩棲族部落 等級24）里没有带十个以上技能的角色，Wine 实拍拍不到；悬停脉冲只有两帧样本，证明亮度在变，周期与相位来自静态读法；名字宽度原先因系统字对不上原版（63 对 71 px），换 FONT.24 点阵后一致。

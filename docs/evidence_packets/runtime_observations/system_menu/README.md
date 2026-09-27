# 系统卷轴（战斗 Title041／大地图 Title051）、回憶錄列表与設定選項窗口化回执

> evidence: runtime-measured; static-derived: 預備動作 一节（hsl01.exe 0x424590／0x401e74／0x4030f7／0x403199）; provisional · status: live · functions: 0x401c20, 0x401e74, 0x4030f7, 0x403199, 0x4031c7, 0x424560, 0x424590, 0x424680 · tools: capture_system_menu_review.gd · updated: 2026-09-27

runtime-measured（重制版窗口化截图，640×480，dev 首控 harness 下的第一战）。视觉评审输入，不是原版等价证明。

来源：`tools/play.sh --script res://tests/capture_system_menu_review.gd --resolution 640x480 --screen 0`（`SYSTEM_MENU_REVIEW_PASS shots=9`；完整输出在 `ignored/system-menu-review/`，此处只提升六帧）。原作对照：05_system_scroll_menu（原版帧见私有档案：`runtime_observations/original_gameplay_reference/05_system_scroll_menu/contact_sheet.jpg`） 帧 001–005（卷入／卷出与 读取回忆录 悬停亮起）。

1. `01-scroll-open-mission-lit.png`：Esc 后卷轴自底边卷入停在 (190,67)（模板匹配原帧 003 所得，mean diff 10.6），首项 任務說明 以 Title042 亮起（红字盒中心对齐 Title041 字行中心 (128,56)）。
2. `02-confirm-prompt-ok-lit.png`：讀取戰場記錄 的 確定／取消 提示——Title061 按钮对当时在 (256,300)，Left 键后 確定 以 Title062 亮起 (7,15)；卷轴亮起项在提示期间隐藏。（2026-09-24 起按原版录屏改到卷轴中央 (256,217)、去掉压暗，见 [menus_ui](../menus_ui/README.md)。）
3. `03-mission-card.png`：任務說明 卡片（WINDOW60 居中）显示当前目标板文字；第一战沿用表现侧文案，level 52／53 显示 winfail 目标板。（2026-09-24 起改为与开场同一块胜负条件面板，见 [menus_ui](../menus_ui/README.md)。）
4. `04-world-scroll-save-memoir-lit.png`：大地图（歐姆村）上 Esc 卷出 Title051 战间卷轴（位置沿用战斗卷轴 (190,67)，provisional），儲存回憶錄 以 Title053 亮起。
5. `05-memoir-list-slot1-saved.png`：儲存回憶錄 后的 回憶錄 列表——Title031 居中 (87,44)，Title033 儲存回憶錄 抬头盖住烧录标题，八条槽带（x 63–407，首带 y 80，间距 33）；槽 1 已存「大地圖　歐姆村　0:00:02」，光标（半透明金）落在槽 2。
6. `06-options-panel.png`：設定選項（Title039 居中 (142,90)）——宝珠 Title027 作旋钮：場景效果 在 on 端、音效音量 在 max、音樂音量 0.6 在槽中，光标带落在 音樂音量 行；預備動作 此时无旋钮（截图早于 2026-09-27 READYACTION 接上的开关）。

边界：

- 原作系统卷轴 handler、卷动速度、键盘选择与确认提示均未定位；卷动 0.25 s、键盘选择也亮起、確定／取消 预选 取消 为重制读法（provisional）。
- 战斗卷轴的 讀取回憶錄 读作「回到自动保存的战役位置」；战间卷轴的 儲存／讀取回憶錄 走八槽 `user://memoir_NN.json`（槽数依 Title031 八条槽带，文件布局与标签文字为重制值）。原作战间卷轴、回憶錄列表均无录像，位置为 provisional。
- 战间卷轴的 整理裝備 未重制，只提示；讀取戰場記錄 恢复最近一份战斗检查点（按 campaign 已注册战斗场景的存档路径查找，取修改时间最新），無则提示 沒有戰場記錄。
- 設定選項 的行语义为重制读法：場景效果 = 剧情特效物件（雨／闪电／火焰／光环）是否绘制（音效仍播放），音效音量 = Master 总线，音樂音量 = 运行时建立的 Music 总线（增益补偿使其独立于 Master）；預備動作 照原版＝施法／绝技攻方起手开关（GameSettings `ready_action`，见下节）；原作混音器未定位（设定 handler 见下节）。

## 預備動作（0x477c14 bit1）

static-derived（2026-09-27，lane OPTIONS-S4，r2 读 hsl01.exe v1.06）。结论：**預備動作 是原版自己的动画开关，只管施法／绝技攻方的起手动作，不跳过切入**；OPT-PACE 的"極快跳过切入"因此仍是改良，預備動作 本身照原版做在 設定選項 第二行（2026-09-27 lane READYACTION，关掉后的逐 call 走向见本节末两条）。

- 面板登记 `0x4247f6` 起四次 `0x446270`：四个控件都传同一组图片 0x319–0x31c（旋钮图，不是行标签）与 x 0x9f，依 y 登记——y 95 开关（2 档，处理函数 `0x424560`）、y 139 开关（2 档，`0x424590`）、y 194 滑杆（18 档，`0x4245c0` → `[0x477c20]`＝档×15 封顶 255）、其后第四个滑杆。按 Title039 行序（場景效果／預備動作／音效音量／音樂音量），第二个开关就是 預備動作。面板打开时 `0x424680` 从 `[0x477c14]` bit0／bit1 回填两开关的档位；`0x42ecdf` 把 `[0x477c20]`、`[0x477c14]&0xffff`、`[0x477c24]` 12 字节写进设置文件，`0x42ee01` 读回。
- `0x424590`：`0x445f60` 取开关档，非零 `[0x477c14] |= 2`，零 `&= ~2`。`[0x477c14]` 初值 3（两开关都开）。
- bit1 的唯一读者是攻方对象过程 `0x401c20`（攻击序列插入的对象 0x9a）的 `0x401e74`：`+0xa4` 为 0（普攻，插入者 `0x4424e4`／`0x442704`）时总是载入并播放攻击帧；为 1（施法例程 `0x442f26` 插入）或 2（`0x441d06` 插入，绝技）时，bit1 开且逐角色表 `[0x4c1b6c]+idx·44` 的起手帧存在，就逐帧 `0x460058` 载入并 `0x45e525` 播放起手（kind 1 先取 +0x14／+0x18／+0x1c 组、缺则 +0x20 组；kind 2 反之），再 `0x45f4b9(0x3c)` 重校节拍器；bit1 关则对象隐藏（`+0x30 = 0xffff`），直接进 `+0x8c = 0x660007`（kind 1，另置 `+0x80` 0x1000 位）或 `0x660008`，不播起手。
- 第一个开关（bit0，`0x424560`）的读者是地图物件过程（`0x43c337`／`0x43c63f`／`0x43cecd`／`0x43d13e`／`0x43d758`：云等背景物件关时不画不走，[地图物件漂移](../../static_reverse/original_map_object_drift.md)），与 場景效果 的行义一致。
- 关掉时走哪条路（static-derived，2026-09-27 lane READYACTION 续读 `0x401e74..0x401efa` 与 phase 102 子状态 5–9）：bit1 关与"该角色没有起手帧"（`0x401e87` 张数为 0、`0x401e8d` 首张为 0）跳到同一处 `0x401ec4`，所以关掉＝按没有起手的施法者处理；起手帧不预载（`0x460058` 逐帧载入与 `0x45f4b9(0x3c)` 节拍重校都跳过）、起手程序（`+0x1c`／`+0x28` 组：aniSetXYDisp／aniShadowBG／aniMoveToCenter／aniInsertCastObject）一条不执行，横幅（施法对象本身，`+0x30 = 0xffff` 隐藏）、残影（`0x401220` 只由 aniSetXYDisp 与子状态 1 调用）、局部图、肖像全都不出。对象过程在设置这一 call 里就接着按新 phase 分派（`0x401f1c`），下面的 call 数都含这一 call。
- 法术（kind 1，`0x442f26` 插入，`0x4c1408 = 0`）：`+0x80 |= 0x1000`（aniShadowBG 用的同一压暗位）、`+0x90 = 0`、进子状态 7（`0x4030f7`）：每 call `+0x90++`，`cmp +0x90, bp(8); jbe` 让出——第 9 个 call（`+0x90 = 9`）调 `0x4071e0` 施法者地图姿势、`0x408b20(x, y − h, 4, 0, 3)` Cast_Star、放 `0x193`（施法音），与开着时引导末 `0x402fd1` 做的是同一组；再下一 call 子状态 5（`0x403089`）清 `0x4c1b00` 的 `0xc00000` 切入位、推进链接对象（`+0xa8` 的 `+0x8c++`，法术效果开始），子状态 6（`0x4030b7`）把 `+0x90` 倒数 9 个 call 后销毁自己。停顿因此只剩 8 个压暗 call（开着时緹娜 002 引导 130 call）。
- 绝技（kind 2，`0x441d06` 插入，`0x4c1408` = 攻方 EFFECTS 程序）：不置压暗位，进子状态 8（`0x403199`）：`+0xa0 = 10`、`+0x28 = 16`、`0x4c6f70 = 0x20002`、`+0x84 = 0`，下一子状态 9（`0x4031c7`）与子状态 4 同形——`+0x84` 计 16 个 call、`+0xa0` 倒数 10 个 call，然后见 `0x4c1408` 非零：调 `0x4607f9`（参数含 (320,240)，未细读）后以它为程序指针进 phase 103（`0x403272`，−1 则 phase 101 结束）。停顿因此是 1＋16＋10 = 27 个 call 的隐藏等待（开着时雷歐納德 139 call），攻方对象此间不画；等待期间屏幕底图未读（重制显示未压暗的地图，provisional）。
- 普攻（kind 0，`0x4424e4`／`0x442704` 插入）不经 `0x401e74`（`0x401dfd` 起自己的分支），不受此位影响。
- 重制：`GameSettings` 键 `ready_action`（默认开＝`[0x477c14]` 初值 3，写 `user://settings.json`，旧文件缺键补默认）；`BattleSystemMenu` 設定選項 第二行旋钮读写它；关掉时 `BattleCombatCutin.cast_lead` 对有起手条带的施法者返回 `AnimalCastLead.skipped`（法术 8 个压暗 call、绝技 27 个隐藏 call，状态里横幅隐藏、无局部图／肖像／残影），`SkillEffectScriptPlayer` 的绝技与地图法术两条起手分支原样消费它；没有导入起手条带的施法者照旧走 Cast_Star 替身／站立帧（原版两档同路，重制也不随开关变）。
- 設定選項 未重制，只显示「設定選項尚未重製」提示；Title039 设定面板未导入。
- 卷轴只在 `play_loop.interaction == action_menu` 且检查点控制器 `quiet()` 时打开；不改任何战斗真相。

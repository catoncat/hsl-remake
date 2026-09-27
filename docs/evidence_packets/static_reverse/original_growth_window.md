# 原作升級窗（手动加点）绘制与输入

> evidence: static-derived; resource-derived: 窗体资源与文字表; negative-evidence: 参考录像无升級窗原帧; runtime-measured: 2026-09-24 用户录屏 340–351 s（§8） · status: live · functions: 0x434bf0, 0x434d10, 0x437c30, 0x437ec0, 0x438160, 0x43a140, 0x43ac10, 0x43b4e0, 0x442720 · tools: run_battle_scene_runtime_tests.gd, run_presentation_contract_tests.gd · updated: 2026-09-27

Checked: 2026-09-21。r2 + r2ghidra 阅读 `hsl01.exe`（sha256 `f0b5f835…`，与 [商店交易包](original_shop_transaction.md) 同一文件），原 PAK 成员 `@:\data\obj-051.obs`／`global.obs`／`PROCESS.DEF`／`OBJ-ALL.H`／`resource.h`／`RESOURCE.TXT` 与 SHAPE 成员直接解码；未执行 Wine 或有界执行。本包回答「玩家升级时原版画出什么、按什么、每个数从哪来」，是 `BattleGrowthPanel.gd` 的布局合同来源。规则本身（五点四维、cap、学技）已在 [成长刷新](original_growth_refresh.md)／[成长生命周期](original_growth_lifecycle.md) 证明，本包不重复。

## 1. 入口与时机

`0x442720`（settle_experience_reward_phase，阶段字 `0x4c432c`）：

| 阶段 | 行为 | 地址 |
| --- | --- | --- |
| 0→2 | EXP 浮字（`0x4084e0(...,1)`） | `0x442720` case 0 |
| 2→4 | 金钱浮字（`0x4084e0(...,4)`） | case 2 |
| 4 | 掉落非空 → 见 [獲得物品窗](original_getitem_window.md) | `0x4428b8`–`0x44290e` |
| 6 | `exp ≥ next && 0x439f70(actor) != 0`（还有可加点数）→ `0x4071e0(actor)`（`0x446c40(actor,+0xa2,7,3)` 角色演出，内容未细读）→ `0x4084e0(...,6)` LEVEL UP 浮字 | `0x44294c`–`0x442971` |
| 8 | 玩家对象（kind 3）：阶段字先减一（`0x442a22` `dec word [0x4c432c]`），`0x436490(actor,10,0)` 生成窗内文字，`0x43b4e0(actor,10,…)` 以等待指针 `0x4c42a0` 打开状态窗 **mode 10**（全程序唯一的 mode 10 调用点 `0x442a52`，城镇无另一个升级窗）；NPC：循环 `0x439f80` 自动分配 | `0x4429c6`–`0x442a52` |

因此原版升級窗在 EXP、金钱、LEVEL UP 浮字之后、下一次行动交接之前打开；与重制 `BattleAftermath` 结束后再开 growth panel 的次序一致。

**一次跨多级＝每级一个窗**（static-derived，GROWTHWIN 2026-09-26）：`0x43ac10` 把等待指针存进 root `+0x9c`；窗关闭时 root case 3 做 `*(+0x9c)+0x8c += 1`，即 `0x4c42a0+0x8c` ＝阶段字 `0x4c432c` 从 7 回到 8；阶段 8 再查 `exp ≥ next && 0x439f70(actor) != 0`，还够就再开一个窗（开窗时 level+1，见 §4）。阶段 8 不回阶段 6，窗与窗之间**不再放 LEVEL UP 浮字**；每窗点数是开窗时的 `0x439f70(actor)`（本级 5 点，受剩余容量限制），同一角色的窗连着开完才交回。

**最后一击与胜负判定的先后（lane R5-L7，2026-09-24；static-derived 读法，窗开着时的并行性 provisional）。** 胜／负／事件扫描 `0x44ee20` 的常规入口是行动结束 `0x407510` → `0x408370`（`jmp 0x44ee20`，[回合显示包「Evaluation cadence」](original_round_display.md)）；另两处 `call` 是剧情→战斗交接 `0x4082a6` 与状态对象 `0x453b7c`，都不在 `0x442720` 之内（R5-L7 按 `call` 目标扫描复核）。阶段 8 在攻击者完成态里（玩家 `0x4447d8..0x44484b`、AI `0x4416bc..0x441738` 调 `0x442720`），行动状态机随后才走 `0x407510`（`0x443c1a`／`0x443c38`）——所以读作「结束战斗的那一击先开升級窗，之后行动结束、扫描判胜负、放胜利动作」。重制的胜负扫描也在行动收尾（`_advance_current_actor`），玩家自己的最后一击本来就先弹窗；缺的是在交锋当场或 AI 步内就已判定的终局（敌方回合反击打死最后一个敌人等），现在同样先弹窗。未追：`0x442720` 是否等窗关闭才返回（若不等，扫描可能在窗开着时发生）。替换证据：Wine 第 3 关（或 51 关）一名成员差 1 级时在敌方回合反击打死最后一个敌人，看升級窗与胜利剧情／结算的先后；失败那一击同时升级时是否开窗。重制照此（用户 2026-09-24 决定「照原版：结算前弹」）：胜利一击的窗在遗言、浮字、獲得物品窗之后，胜利对白、胜利 status 过场与结果页之前；失败不开窗（保守选择：失败重开本战，点数无处保留）。

## 2. 窗体对象与坐标（mode 10，`0x43b4e0` case 10，`0x43bbca`–`0x43bd94`）

对象由 `0x45e307(x,y,code)` 从 obs 模板创建；`+0xa6/+0xa4` 是滑入起点，`+0xaa/+0xa8` 是停靠坐标（屏幕像素，640×480）。root flag `0x40004400`：bit `0x400` 在 mode 10（`0x43bbd3 or ecx,0x40004400`）／0xb（`0x43bdcc` 同一指令）置位，其他状态页模式没有——`0x438160` root case 1 的右键／Esc 关闭分支（`0x438811`–`0x43883c`：`0x4c6398 & 0x20000` 或 `0x4c6390 & 0x100000`，且非 `0x4c6398 & 1`）在 `0x438839 test ah,4` 见 `0x400` 即 `jne 0x4388c7`，跳过写 `+0x96 = 0xffff`（`0x4388be`，关窗）；这条路上没有提示文字也没有音效。读作「升級窗与獲得物品窗不能用右键／Esc 关闭，按了什么都不发生」（static-derived，未原生执行）。

| obj | 名称／SHP（obs） | 停靠 (x,y) | 创建函数 | 用途 |
| --- | --- | --- | --- | --- |
| 130 | Status_Window_0 `CURSOR01`，`defProcStatusWindow` Data9=0 | (12,14) | `0x43ac10` | root；帧改为角色记录 `+0x5c` 的头像索引 → 头像画在 (12,14)；root `+0x94` = 4 |
| 131 | Status_Window_1 `WINDOW10`（494×144，绘制原点 (248,0)） | (381,14) → 左缘 133 | `0x43ac90` | 抬头：等級／經驗／生命／魔法／氣力，文字槽 1，行距 0x22 |
| 145／146／147 | Bar_HP／Bar_MP／Bar_ST | (170,67)／(170,97)／(154,116) | `0x43ace0`/`0x43ad30`/`0x43ad80` | 条 |
| 132 | Status_Window_2 `WINDOW20`（224×264，2 帧：WINDOW20 空、WINDOW21 带 力量…移動力 九个金色标签） | (12,174) | `0x43add0` | 左栏；root mode 4 时每 tick `帧 = 基帧 + 1` → **WINDOW21**（`0x438160` case 2→mode 4），文字槽 2，行距 0x1c=28，顶缘偏移 8 |
| 703 | Status_Window_3_LevelUp `WINDOW31`（376×168 空） `defProcLevelUpWindow` | (252,174) | `0x43aec0` | 「學會魔法:」框，见 §5 |
| 707 | Status_Window_3_LevelUp `WINDOW50`（376×88 空） `defProcLevelUpWindow2` | (252,344) | `0x43af10` | 「學會特殊技:」预览框，见 §5 |
| 134 | Status_Window_4 `WINDOW40`（2 帧：WINDOW40 `$:`、WINDOW41 208×36 `殘餘點數:`） | (20,442)，帧 +1 → **WINDOW41**，Data9=7 | `0x43b000` | 剩余点数框 |
| 144 | Button_Ok `BT_OK`（60×35）`defProcLevelUpButton` Data6=2 | (168,395) | `0x43b3a0` | OK |
| 143 ×8 | Button_AttributeAddSub `BT_ADD1`（25×25，2 帧：BT_ADD1 `+`、BT_ADD2 `−`）`defProcLevelUpButton` | x = 159 + 37·col，y = 181 + 28·row（row 0..3，col 0 = `+`，col 1 = `−` 帧 +1） | `0x43bcfb`–`0x43bd45` | 四属性加减 |

不创建 Prev／Next／道具／魔法／特殊技／屬性 页按钮、WINDOW30 装备栏或 `$:` 钱框；没有「稍后」「重置」按钮。

## 3. 文字：字体、颜色、内容

- 字体：`0x42f230`–`0x42f31b` 装载 `DATA\FONT.15`+`ASCFONT.15`（`*0x4c1adc`，全角 16px／半角 8px）与 `DATA\FONT.24`+`ASCFONT.24`（`*0x4c1ae0`，全角 24px／半角 12px）。窗内正文用 24 号（`0x4123b0`／`0x4128f0` 每字节前进 12px，`0x4128f0` 居中公式 `x + (宽−len)/2·12`），按钮小标签用 15 号。每个字先在 (x+1,y+1) 画阴影色再画本色。
- 颜色码 `@0`–`@9`（`0x476b44` 表，RGB565→RGB）：`@1` 白 (255,255,255)／阴影 0x8430；`@2` 红 (255,80,82)；`@3` 绿 (205,255,205)；`@5` 黄 (255,255,123)；`@6` 米白 (255,255,222)。`#` 换行。
- 左栏文字槽 2 由 `0x434d10(actor, mode, …)` 生成（`(*0x4c1b80)[2]`，`0x435...` 段），mode 10 与状态页共用同一格式，只在四属性取值不同：

| 行 | 内容 | 来源字段 | 备注 |
| --- | --- | --- | --- |
| 前导 | 6 个半角空格（`0x477824`）→ 数值从 x = 12+8+72 = **92** 起 | — | 标签是 WINDOW21 图内的，不是文字 |
| 0–3 | 力量／反應／精神／體質 | `0x434bf0(buf, base(+0x64..+0x70), live, cap(+0x74..+0x80), job7?)`；**mode 10 传 live=base**（`0x434d10` 四处 `if (param_2 != 10)`） | 着色：`base ≥ cap` → `@2` 红；`cap−50 ≤ base < cap`（非 job 7）→ `@5` 黄；否则默认白；数值宽 4 右对齐；状态页 `base != live` 时追加 `\x1a`（箭头字形）+ live，mode 10 不出现 |
| 4 | 攻擊力 `+0xc0`（衰弱时 `−(+0x42)` 并追加箭头） | 每次加减后 `0x448840` 刷新 | 行 4–8 前导 `#` + 8 空格（`0x4785dc`） |
| 5 | 防禦力 `+0xb4`（同上 `+0x46`） | | |
| 6 | 魔擊力 `+0xd0` + `%`（`0x477820`） | | 与 [V05](../runtime_observations/original_gameplay_reference/README.md) 一致 |
| 7 | 敏捷度 `+0xb8` | | |
| 8 | 移動力 `+0x12c` | | |

- 剩余点数框（`0x438160` case 7）：文字 = 10 个半角空格 + `0x45b6de(*0x4c1ccc, …, 6, ' ')` 六位右对齐；画在 (x+8, y+6) → 数字右缘 x = 28+120+72 = 220，y = 448。

## 4. 按钮流程（`0x43a140` defProcLevelUpButton）

| 事件 | 行为 |
| --- | --- |
| OK 按钮初始化（Data6=2，`0x43a140` init 分支） | `*0x4c1ccc = 0x439f70(actor)`（本次可分配点数）；四项草稿 `0x4c2c60[4]` 清零；**level +1，exp −= next_exp（钳 ≥0）**，`0x448840` 刷新，`0x436490(actor,10)` 重建文字 |
| `+`（Data6=0）每 tick | `0x4c1ccc != 0 && base[row] < cap[row]` → 正常；否则 flag `0x10000000`（暗显／不可按） |
| `−`（Data6=1） | 草稿 `0x4c2c60[row] != 0` 才可按 |
| OK 每 tick | `0x4c1ccc != 0` → flag `0x10000000`（不画，§8）并跳过输入（`goto 0x43a2f1`）；剩余 0 时才读输入位 `0x4c6390 & 0x200000`（推断为键盘确认，重制未映射）与点击同路 |
| 点 `+` | `base[row] += 1; 0x4c1ccc −= 1; 草稿 += 1; 0x448840; 0x436490(actor,10)` —— 属性**原地**修改，派生行即时变化 |
| 点 `−` | 逆操作 |
| 点 OK（仅剩余 0） | root `+0x96 = -1` → 整组窗滑出关闭 |

没有「稍后再分配」：五点必须全部分配后才能关闭；右键／Esc 被 `0x400` 位挡住（§2）。`−` 只退本窗草稿，已提交的点数不能撤；没有自动分配按钮（只有 OK 与八个 ±）。`0x4c1ccc` 读者只有本窗与 case 7 文字，不进存档。

## 5. 右侧两框（学技提示）

- 703 `WINDOW31` `0x437c30`：初始化时 `0x4373f0(actor, buf)` 以**存储等级+1**检查职业魔法；学到 → 文字 `@3學會魔法:@1#<魔法名>`（资源 907 + `0x4098b0` 名字，`0x437080` 拼接）画在 (x+8, y+10)，行距 26；没学到 → 帧 −1（不画）。开窗时确定，不随加点变化。
- 707 `WINDOW50` `0x437ec0`：每 tick `0x437a40(actor, buf)` 以**当前**四属性预览可学特殊技 → 有则显示 `@3學會特殊技:@1#<名>`（资源 908 + `0x4099b0`），否则隐藏；窗关闭（`+0x96 == -1`）时 `0x437a40(actor, NULL)` 提交学习。即加点过程中一旦满足某行属性门槛，下框立刻出现该技名；OK 后无另外弹窗。

## 6. 与录像帧的对照

原录像（[original_gameplay_reference](../runtime_observations/original_gameplay_reference/README.md)）**没有升級窗帧**（manifest 无 LEVEL UP／升級 标签；AUDIT 只记 EXP／KILL 浮字）——本包的坐标全部 static-derived，未做像素比对。可用的间接对照：`06/frame_006` 状态页显示同一 WINDOW10 抬头、同一 WINDOW21 左栏（标签金色、数值白、`魔擊力 17%`）和数值起始 x≈97（录像 638 宽），与 §3 的 x=92 相容。录像为用户的简体字版本，资源表文字为繁体；重制显示资源表文字。

## 7. 重制映射（`game/battle/scene/BattleGrowthPanel.gd`）

| 原 | 重制 | 备注 |
| --- | --- | --- |
| root 头像 + WINDOW10 + 三条 | `BattleVitals`（已有，(0,14)） | 不变 |
| WINDOW21 (12,174) 九行、x=92 数值、行 28 | 同坐标，`shared/panels/WINDOW21.png` | 字体为系统字（22px≈24px 格），不是 FONT.24 位图 |
| `+`／`−` BT_ADD1／BT_ADD2 (159/196, 181+28·row) | `TextureButton`，不可按时隐藏（`_set_enabled`） | `0x10000000` ＝ 不画，§8 录屏 |
| OK BT_OK (168,395)，剩余 0 才可按 | 同，未点满时隐藏 | §8 |
| WINDOW41 (20,442) 剩余点数 | 同，数字右缘 220 | |
| 属性原地修改、开窗即升级 | 草稿 + `Growth.apply_allocation` 预览；OK → `allocate_growth` 一次提交（PlayLoop 已在 EXP 结算时升级并留 `pending_stat_points`） | 玩家可见数值变化一致；真相所有者不变 |
| WINDOW31 學會魔法（开窗固定） | 显示本级 `trigger == level_up` 的 learned_skills | 重制在 EXP 结算时已学 |
| WINDOW50 學會特殊技（随加点预览，OK 提交） | `Learning.acquire(预览角色, skill_book, "special")["added"]` 实时预览；`allocate_growth` 提交 | 同 |
| 阶段 8 对每个玩家对象开窗（敌方回合反击亦同） | `BattleSceneMenus.offer_pending_growth`：行动菜单或敌方回合两步 AI 之间的安静时刻，按角色记录已提示等级（`growth_offered_levels`），任何存活可控成员都弹；`run_growth_offer_tests` | 胜利一击：在胜利对白／过场／结果页之前弹（`terminal_growth_pending`，`allocate_growth` 胜利后仍收点数、失败后拒绝；`run_growth_offer_tests`、`run_combat_aftermath_tests.terminal_victory_level_up`）；先后为静态读法，见 §1 |
| 右键／Esc 不能关闭（`0x43bbd3`／`0x438839`） | 同：`BattleGrowthPanel.handle_input` 吞掉右键／Esc，窗不关、无提示；只有点满后出现的 OK 能关 | GROWTHWIN（2026-09-26）起照原版；此前重制允许右键／Esc 暂缓。`hide()` 只作自动对局／测试的跳过缝；旧存档或跳过缝留下的点数在读档后、下一场首个安静时刻或状态页「成長點」再开 |
| 一次跨多级：每级一个窗（`0x442a22` 阶段减一、关窗时阶段字 `0x4c432c` 加一重查，§1） | 同：`window_points` 每窗 5 点，OK 后 `BattleSceneMenus.allocate_growth` 接着开下一级的窗，等级／經驗显示逐窗；点数仍在 EXP 结算时一次预占（`ProgressionRules`） | GROWTHWIN2（2026-09-27）起照原版；OPT-GROWTH=合成一窗 保留一窗给全部点数 |
| 无 稍后／重置／确定 文字按钮 | 已删除 | |

## 8. 录屏对照（R7-UI）

用户原版录屏 `录屏2026-09-24 中午12.03.22.mov` 340–351 s 有一次 雷歐納德 Lv2 升級窗（runtime-measured，逐帧）：

- 340.26–340.68 s 打开：地图按 [面板压暗](../runtime_observations/camera_panel_motion/README.md) 的层级逐步压暗，上栏／左栏／右窗滑入；**没有** WINDOW31／WINDOW50（本级无学技，与 §5 的「帧 −1 不画」一致）。
- 341.0 s：四行只有 `+`（x≈160），**没有 `−` 也没有 OK**；殘餘點數 5。
- 345.5 s 起每点一次 `+`：该行出现 `−`（x≈196），其余行仍只有 `+`；殘餘點數 递减。
- 殘餘點數 0：四个 `+` 同时消失，OK 出现在 (168,395) 左右（持有草稿的行仍有 `−`）。
- 350.69–350.90 s 点 OK 关闭：上栏向上、左栏向左、右窗向上滑出（与状态页的收起相同，不是向下），随后压暗淡回。

即 §4 的 `0x10000000`（不可按）画法是**不画**，不是调暗；没有「一个按钮在 ＋／− 间切换」——两列按钮各自按可按性出现。重制 `BattleGrowthPanel._set_enabled` 照此隐藏不可按的按钮（`run_presentation_contract_tests` 守：开窗只见 `+`、点一次后该行见 `−`、点满后 `+` 全隐藏且 OK 可见；消融：恢复调暗 → 失败）。截帧目审：`tools/godot.sh --script res://tests/capture_growth_panel_review.gd`（输出 `ignored/r7-growth-review/`）。

## 用户验收路线

第一战 雷歐納德 击杀敌兵累计 EXP 达 `ProgressionRules.exp_to_next`（Lv1→2 为 100）后在浮字结束时弹出；旧存档里留着的未分点数在读档后的首个安静时刻（或 狀態 页 成長點）再弹。录像**无升級窗原帧**，间接对照 [`06/frame_006`](../runtime_observations/original_gameplay_reference/README.md) 的状态页左栏。

| 步骤 | 操作 | 应看到 | 对照 |
| --- | --- | --- | --- |
| 1 | 击杀后 EXP／`$` 浮字与（若有）獲得物品 窗结束 | 上方 WINDOW10 头像＋等级／經驗／生命／魔法／氣力条＋姓名窗（与状态页相同）；左 WINDOW21 (12,174) 九行金色标签 力量／敏捷／智慧／體質／攻擊力／防禦力／魔擊力／速度／移動力，数值白色起 x=92；四属性右侧只有 `+`（BT_ADD1）；左下 WINDOW41「殘餘點數: N」；没有 OK | §2 表；§8 录屏 341.0 s |
| 2 | 点某属性 `+` | 该属性 +1；攻擊力／防禦力／魔擊力／速度 随之刷新；殘餘點數 −1；该行出现 `−` | `0x434bf0` 着色；§8 |
| 3 | 点 `−` | 回退一点；该行草稿归零时 `−` 消失 | §8 |
| 4 | 点满剩余点数 | 所有 `+` 消失；BT_OK 出现 | §8 录屏 |
| 5 | 本级学会魔法／特殊技（如 Lv2 无则跳过） | 右侧 WINDOW31「學會魔法:」／WINDOW50「學會特殊技:」列出名字 | §5 |
| 6 | 点 OK | 关窗，状态页数值与预览一致 | `allocate_growth` |
| 7 | 未点满时按 右键／Esc | 什么都不发生：窗不关、无提示，殘餘點數 不变 | §2 `0x438839` |

## 复跑

```sh
EXE="$HSL_ORIGINAL_DIR/hsl01.exe"
r2 -q -e scr.color=0 -e bin.cache=true -c 'af @ 0x43b4e0; pdg @ 0x43b4e0' "$EXE"   # case 10：对象清单与坐标
r2 -q -e scr.color=0 -e bin.cache=true -c 'af @ 0x43a140; pdg @ 0x43a140' "$EXE"   # +/−/OK
r2 -q -e scr.color=0 -e bin.cache=true -c 'af @ 0x434bf0; pdg @ 0x434bf0' "$EXE"   # 属性着色
r2 -q -e scr.color=0 -e bin.cache=true -c 'pd 8 @ 0x442a42' "$EXE"                 # 玩家分支 push 0xa → 0x43b4e0
r2 -q -e scr.color=0 -e bin.cache=true -c 'pd 2 @ 0x43bbca; pd 16 @ 0x438811' "$EXE" # mode 10 置 0x400；右键／Esc 关闭分支见 0x400 跳过
r2 -q -e scr.color=0 -e bin.cache=true -c 'pxw 40 @ 0x476b44' "$EXE"               # @0–@9 颜色表
tools/godot.sh --headless --script res://tests/run_presentation_contract_tests.gd
```

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleGrowthPanel.gd` layout：0x4370b0 window ids, row coordinates, NUM font fields, button centres; §4 flag 0x10000000 on an unavailable ＋／－／OK; §5 the magic／special boxes only when something is learned
- `game/sim/loop/BattleLoopRewards.gd` rules：§1: a won result still takes the final blow's manual allocation — phase 8 precedes the win scan; a lost result takes none, provisional

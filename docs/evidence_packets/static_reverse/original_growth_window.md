# 成长：原作升級窗（手动加点）的时机、布局与输入

> evidence: static-derived; resource-derived: 窗体资源与文字表; negative-evidence: 参考录像无升級窗原帧; runtime-measured: 原版录屏 340–351 s（§8） · status: live · functions: 0x434bf0, 0x434d10, 0x437c30, 0x437ec0, 0x438160, 0x43a140, 0x43ac10, 0x43b4e0, 0x442720 · tools: run_battle_scene_runtime_tests.gd, run_presentation_contract_tests.gd · updated: 2026-09-27

## 结论

- 原版在 EXP、金钱、LEVEL UP 浮字之后、行动交接与胜负扫描之前，为玩家对象打开状态窗 mode 10（全程序唯一调用点 `0x442a52`）；一次跨多级＝每级一个窗、每窗 5 点（受容量限制）；点数全部分完才出现 OK，右键／Esc 不能关闭；不可按的 ＋／－／OK 不画（static-derived；runtime-measured 录屏对照）。
- 重制 `game/battle/scene/BattleGrowthPanel.gd` 按同一坐标、按钮可见性与逐级开窗实现，`BattleSceneMenus.offer_pending_growth` 在安静时刻开窗，点数在 EXP 结算时由 `ProgressionRules` 一次预占、OK 时 `allocate_growth` 提交（static-derived）。
- 已知差异：重制属性为草稿预览、OK 一次提交（原版原地修改）；字体为系统字而非 FONT.24 位图；`0x442720` 是否等窗关闭才返回未追，胜利一击先开窗的先后是静态读法（provisional）。参考录像无升級窗帧（negative-evidence）。

## 证据

**static-derived**（r2 + r2ghidra 阅读 `hsl01.exe` sha256 `f0b5f835…`；PAK 成员 `obj-051.obs`／`global.obs`／`PROCESS.DEF`／`OBJ-ALL.H`／`resource.h`／`RESOURCE.TXT` 与 SHAPE 直接解码；未有界执行）。规则本身（五点四维、上限、学技）见 [original_growth_refresh.md](original_growth_refresh.md)、[original_growth_lifecycle.md](original_growth_lifecycle.md)。

### 1. 入口与时机

`0x442720`（阶段字 `0x4c432c`）：

| 阶段 | 行为 | 地址 |
| --- | --- | --- |
| 0→2 | EXP 浮字 `0x4084e0(...,1)` | case 0 |
| 2→4 | 金钱浮字 `0x4084e0(...,4)` | case 2 |
| 4 | 掉落非空 → [獲得物品窗](original_getitem_window.md) | `0x4428b8`–`0x44290e` |
| 6 | `exp ≥ next && 0x439f70(actor) != 0` → `0x4071e0(actor)`（`0x446c40(actor,+0xa2,7,3)` 角色演出，内容未读）→ `0x4084e0(...,6)` LEVEL UP 浮字 | `0x44294c`–`0x442971` |
| 8 | kind 3：`0x442a22` 阶段字减一，`0x436490(actor,10,0)` 生成文字，`0x43b4e0(actor,10,…)` 以等待指针 `0x4c42a0` 开 mode 10；NPC：循环 `0x439f80` 自动分配 | `0x4429c6`–`0x442a52` |

- 多级：`0x43ac10` 把等待指针存进 root `+0x9c`；关窗时 root case 3 做 `*(+0x9c)+0x8c += 1`（阶段字 7→8），阶段 8 再查条件，够就再开一窗；不回阶段 6，窗间无 LEVEL UP 浮字；同一角色的窗连开完才交回。
- 与胜负扫描：`0x44ee20` 常规入口是行动结束 `0x407510` → `0x408370`（另两处 `call` 为 `0x4082a6` 剧情→战斗交接、`0x453b7c` 状态对象，都不在 `0x442720` 内）；阶段 8 在攻击者完成态（玩家 `0x4447d8..0x44484b`、AI `0x4416bc..0x441738`），行动状态机随后才走 `0x407510`（`0x443c1a`／`0x443c38`）——结束战斗的一击先开升級窗，再判胜负。

### 2. 窗体对象与坐标

mode 10：`0x43b4e0` case 10，`0x43bbca`–`0x43bd94`。对象由 `0x45e307(x,y,code)` 从 obs 模板创建；`+0xa6/+0xa4` 滑入起点，`+0xaa/+0xa8` 停靠坐标（640×480）。root flag `0x40004400` 的 bit `0x400` 只在 mode 10（`0x43bbd3`）／0xb（`0x43bdcc`）置位；`0x438160` root case 1 的右键／Esc 关闭分支（`0x438811`–`0x43883c`：`0x4c6398 & 0x20000` 或 `0x4c6390 & 0x100000`，且非 `0x4c6398 & 1`）在 `0x438839 test ah,4` 见该位即 `jne 0x4388c7`，跳过 `0x4388be` 的关窗写入，无提示无音效。

| obj | 名称／SHP | 停靠 (x,y) | 创建函数 | 用途 |
| --- | --- | --- | --- | --- |
| 130 | Status_Window_0 `CURSOR01`，Data9=0 | (12,14) | `0x43ac10` | root；帧＝角色记录 `+0x5c` 头像；root `+0x94`=4 |
| 131 | `WINDOW10`（494×144，原点 (248,0)） | (381,14) | `0x43ac90` | 抬头：等級／經驗／生命／魔法／氣力，文字槽 1，行距 0x22 |
| 145／146／147 | Bar_HP／MP／ST | (170,67)／(170,97)／(154,116) | `0x43ace0`/`0x43ad30`/`0x43ad80` | 条 |
| 132 | `WINDOW20`／`WINDOW21`（224×264，九个金色标签） | (12,174) | `0x43add0` | 左栏；root mode 4 时帧 +1 → WINDOW21（`0x438160` case 2），文字槽 2，行距 28，顶缘偏移 8 |
| 703 | `WINDOW31`（376×168）`defProcLevelUpWindow` | (252,174) | `0x43aec0` | 學會魔法 框（§5） |
| 707 | `WINDOW50`（376×88）`defProcLevelUpWindow2` | (252,344) | `0x43af10` | 學會特殊技 预览（§5） |
| 134 | `WINDOW40`→帧 +1 `WINDOW41`（208×36 `殘餘點數:`），Data9=7 | (20,442) | `0x43b000` | 剩余点数 |
| 144 | `BT_OK`（60×35）Data6=2 | (168,395) | `0x43b3a0` | OK |
| 143 ×8 | `BT_ADD1`／`BT_ADD2`（25×25） | x = 159 + 37·col，y = 181 + 28·row | `0x43bcfb`–`0x43bd45` | 四属性 ＋（col 0）／－（col 1） |

不创建翻页／道具／魔法／特殊技／屬性按钮、WINDOW30 装备栏、`$:` 钱框，也没有「稍后」「重置」按钮。

### 3. 文字

- 字体：`0x42f230`–`0x42f31b` 装载 `FONT.15`+`ASCFONT.15`（`*0x4c1adc`，全角 16／半角 8）与 `FONT.24`+`ASCFONT.24`（`*0x4c1ae0`，全角 24／半角 12）；窗内正文 24 号（`0x4123b0`／`0x4128f0`，居中 `x + (宽−len)/2·12`），按钮小标签 15 号；每字先在 (x+1,y+1) 画阴影。
- 颜色码 `0x476b44`：`@1` 白（阴影 0x8430）、`@2` 红 (255,80,82)、`@3` 绿 (205,255,205)、`@5` 黄 (255,255,123)、`@6` 米白 (255,255,222)；`#` 换行。
- 左栏由 `0x434d10(actor, mode, …)` 生成，与状态页同格式：前导 6 个半角空格（`0x477824`）→ 数值起 x=92。

| 行 | 内容 | 来源 |
| --- | --- | --- |
| 0–3 | 力量／反應／精神／體質 | `0x434bf0(buf, base(+0x64..+0x70), live, cap(+0x74..+0x80), job7?)`，mode 10 传 live=base；`base ≥ cap` 红、`cap−50 ≤ base < cap`（非 job 7）黄；宽 4 右对齐；状态页 `base != live` 时追加 `\x1a`+live，mode 10 不出现 |
| 4 | 攻擊力 `+0xc0`（衰弱时 −`+0x42` 并加箭头） | 每次加减后 `0x448840` 刷新；行 4–8 前导 `#`+8 空格（`0x4785dc`） |
| 5 | 防禦力 `+0xb4`（衰弱 −`+0x46`） | |
| 6 | 魔擊力 `+0xd0` + `%`（`0x477820`） | 与 [录像参考 V05](../runtime_observations/original_gameplay_reference/README.md) 一致 |
| 7 | 敏捷度 `+0xb8` | |
| 8 | 移動力 `+0x12c` | |

剩余点数框（`0x438160` case 7）：10 个半角空格 + `0x45b6de(*0x4c1ccc, …, 6, ' ')` 六位右对齐，画在 (x+8,y+6) → 数字右缘 x=220、y=448。

### 4. 按钮流程

`0x43a140` defProcLevelUpButton：

| 事件 | 行为 |
| --- | --- |
| OK 初始化（Data6=2） | `*0x4c1ccc = 0x439f70(actor)`；草稿 `0x4c2c60[4]` 清零；level +1、exp −= next（钳 ≥0）、`0x448840`、`0x436490(actor,10)` |
| ＋（Data6=0）每 tick | `0x4c1ccc != 0 && base[row] < cap[row]` 才可按，否则置 `0x10000000` |
| －（Data6=1） | 草稿 `0x4c2c60[row] != 0` 才可按 |
| OK 每 tick | `0x4c1ccc != 0` → 置 `0x10000000` 并跳过输入（`0x43a2f1`）；剩余 0 时读 `0x4c6390 & 0x200000`（推断为键盘确认）与点击同路 |
| 点 ＋ | `base[row]+=1; 0x4c1ccc−=1; 草稿+=1; 0x448840; 0x436490(actor,10)`——原地修改，派生行即时变化 |
| 点 － | 逆操作 |
| 点 OK（剩余 0） | root `+0x96 = -1`，整组滑出 |

没有「稍后」、自动分配或撤销已提交点数；`0x4c1ccc` 不进存档。

### 5. 右侧两框

- 703 `WINDOW31` `0x437c30`：初始化时 `0x4373f0(actor, buf)` 以存储等级+1 查职业魔法；学到 → `@3學會魔法:@1#<名>`（资源 907 + `0x4098b0`，`0x437080` 拼接）画在 (x+8,y+10)、行距 26；否则帧 −1 不画。开窗时确定。
- 707 `WINDOW50` `0x437ec0`：每 tick `0x437a40(actor, buf)` 以当前四属性预览 → `@3學會特殊技:@1#<名>`（资源 908 + `0x4099b0`），否则隐藏；关窗（`+0x96 == -1`）时 `0x437a40(actor, NULL)` 提交。
- 学技只在这两个框里出现：交锋回执 `0x442720` 的各阶段（EXP、$、得物窗、LEVEL UP）不印学技；`0x437080`／`0x4373f0`／`0x437a40`／`0x437c30`／`0x437ec0` 都不调放声 `0x42c180`（全 EXE 51 个调用点无一在 `0x436000–0x438000`）（negative-evidence）。重制原版预设不在地图上飘学技提示，OPT-INFO=公開 才飘（差异清单 `learning-notice`）。

**negative-evidence**：[录像参考](../runtime_observations/original_gameplay_reference/README.md) manifest 无 LEVEL UP／升級 标签，没有升級窗帧；间接对照 `06/frame_006` 状态页（同一 WINDOW10、WINDOW21、`魔擊力 17%`、数值起 x≈97／638 宽，与 x=92 相容）。录像为简体字版本，重制显示资源表繁体文字。

<a id="8-录屏对照r7-ui"></a>

### 8. 录屏对照

**runtime-measured**：原版录屏 340–351 s，雷歐納德 Lv2 升級窗逐帧：

| 时刻 | 画面 |
| --- | --- |
| 340.26–340.68 s | 地图按 [面板压暗](../runtime_observations/camera_panel_motion/README.md) 逐步压暗，上栏／左栏／右窗滑入；本级无学技，无 WINDOW31／WINDOW50 |
| 341.0 s | 四行只有 ＋（x≈160），无 － 也无 OK；殘餘點數 5 |
| 345.5 s 起 | 每点一次 ＋，该行出现 －（x≈196），殘餘點數递减 |
| 殘餘點數 0 | 四个 ＋ 同时消失，OK 出现在 (168,395) 附近 |
| 350.69–350.90 s | 点 OK：上栏向上、左栏向左、右窗向上滑出，压暗淡回 |

即 `0x10000000` 的画法是不画而非调暗；两列按钮各自按可按性出现。

## 重制接线

| 原 | 重制 | 备注 |
| --- | --- | --- |
| root 头像 + WINDOW10 + 三条 | `game/battle/scene/BattleVitals.gd`（(0,14)） | |
| WINDOW21 (12,174) 九行、x=92、行 28 | 同坐标，`shared/panels/WINDOW21.png` | 系统字 22px（provisional，替换点：FONT.24 位图） |
| ＋／－ (159/196, 181+28·row) | `TextureButton`，`_set_enabled` 不可按即隐藏 | §8 |
| OK (168,395) 剩余 0 才出现 | 同 | |
| WINDOW41 (20,442) | 同，数字右缘 220 | |
| 属性原地修改、开窗即升级 | 草稿 + `Growth.apply_allocation` 预览；OK → `allocate_growth` 一次提交；PlayLoop 在 EXP 结算时升级并留 `pending_stat_points` | 可见数值一致，真相所有者不变 |
| WINDOW31（开窗固定） | 本级 `trigger == level_up` 的 learned_skills | 重制在 EXP 结算时已学 |
| WINDOW50（随加点预览、OK 提交） | `Learning.acquire(预览角色, skill_book, "special")["added"]` 预览，`allocate_growth` 提交 | |
| 阶段 8 对每个玩家对象开窗（含敌方回合反击） | `game/battle/scene/BattleSceneMenus.gd` `offer_pending_growth`：行动菜单或敌方回合两步 AI 之间的安静时刻，按 `growth_offered_levels` 弹给存活可控成员 | 胜利一击在胜利对白／过场／结果页之前弹（`terminal_growth_pending`）；失败不开窗（点数无处保留） |
| 右键／Esc 不能关 | `BattleGrowthPanel.handle_input` 吞掉右键／Esc | `hide()` 只作自动对局／测试跳过缝；遗留点数在读档后首个安静时刻或状态页「成長點」再开 |
| 每级一个窗 | `window_points` 每窗 5 点，OK 后 `allocate_growth` 接着开下一级，等级／經驗逐窗显示 | 选项 OPT-GROWTH＝合成一窗 |

provenance 头写法：`layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md`（`BattleGrowthPanel`、`BattleSceneMenus`、`BattleVitals`、`BattleStatusPanel`）。迁入的模块备注：

- `game/battle/scene/BattleGrowthPanel.gd` layout：0x4370b0 window ids, row coordinates, NUM font fields, button centres; §4 flag 0x10000000 on an unavailable ＋／－／OK; §5 the magic／special boxes only when something is learned
- `game/sim/loop/BattleLoopRewards.gd` rules：§1: a won result still takes the final blow's manual allocation — phase 8 precedes the win scan; a lost result takes none, provisional

## 复现

`tools/godot.sh --headless --script res://tests/run_presentation_contract_tests.gd`

（守：开窗只见 ＋、点一次后该行见 －、点满后 ＋ 全隐藏且 OK 可见；开窗时机另由 `tests/run_combat_aftermath_tests.gd`（`run_growth_offer()`） 覆盖。）

## 边界

- `0x442720` 是否等窗关闭才返回未追；若不等，胜负扫描可能在窗开着时发生（provisional）。替换证据：原版一名成员差 1 级时在敌方回合反击打死最后一个敌人，看升級窗与胜利剧情的先后。
- 失败的那一击同时升级时原版是否开窗未测；重制不开。
- `0x4071e0` 角色演出内容未读。
- `0x4c6390 & 0x200000` 的物理键为推断，重制未映射。
- 坐标全部 static-derived，没有原帧像素比对。

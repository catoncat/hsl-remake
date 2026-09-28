# 战斗特写站位、击杀／升级飘字与抗性宝石：原版三路测量

> evidence: runtime-measured: 2026-09-24 用户录屏逐帧像素（特写演员锚点、底栏 WINDOW10 外框、左上红框立绘外框、KILL／EXP／$／LEVEL UP 精灵匹配的出现时刻与轨迹、抗性宝石位置）与音轨起音; static-derived: 0x401c20／0x4038a0 特写站位与击退、0x442720 结算阶段、0x4084e0／0x408580 数字浮字、0x408390／0x4083e0 KILL 浮字、0x434d10 抗性文字; resource-derived: hsl.pak KILL_000..010、NUM4xx／5xx／511／512／514、MAGICON1..5、ANIMAL.TXT k_action · status: live · functions: 0x401c20, 0x4038a0, 0x404560, 0x408390, 0x4083e0, 0x4084e0, 0x408580, 0x408b20, 0x42f4fc, 0x434d10, 0x43f0aa, 0x442720, 0x4435c5, 0x45e91e · tools: hsl_video_events.py, run_combat_aftermath_tests.gd, run_skill_effect_script_tests.gd · updated: 2026-09-28

## 结论

- 原版特写攻方在中线 (320,330)，守方按 ANIMAL `k_action` 偏移（aniKLeft +30、aniKRight −50）并在命中后 14 tick 被击退 105 px、落空退 150 px；底栏 WINDOW10 与特殊技左上红框立绘位置已与重制一致（runtime-measured＋static-derived）。
- 原版结算每位受益者依次出 EXP → $ →（獲得物品窗）→ LEVEL UP＋升级音 → 加点窗，每个浮字在第 32 tick 放行下一个；KILL 美术字随阵亡在其头上出、40 tick 定住；身份栏抗性行是五颗元素宝石＋「07%」（runtime-measured＋static-derived＋resource-derived）。
- 重制 `CutinLayout`（站位、击退、闪避）、`BattleRewardFloater`（美术字排版与淡出）、`BattleAftermath`（队列与放行）、`BattleVitals`（抗性宝石）按这些读法实现（static-derived）。
- 差异：反击方第二份金钱累加器合在一份 $ 里（provisional）；抗性数字已用原版 FONT.15＋ASCFONT.15 点阵小字（`0x411d70`，lane BITMAPFONT，差异清单 `bitmap-font`）；画宝石的原版调用点未找到，位置取像素（negative-evidence）。

## 证据

录屏 `录屏2026-09-24 中午12.03.22.mov`（私有档案；游戏区 `crop=1280:960:112:140` 缩到 640×480，可变帧率约 57 fps，一律用 PTS 秒）；本机原作 tick ≈ 19.4 ms、设计 16 ms（[tick 率](../original_tick_rate/README.md)）。精灵匹配用 `hsl_video_events.py sprite`（给 hsl.pak 解出的 RGBA 图，逐帧求最小掩膜 RGB 差的位置与分数，分数 ≤ 40 记为可见）。原始帧与中间 JSON 不入库。

### 1. 特写站位：攻方在中线，守方按 k_action 偏移并被击退

**像素**（把 combat_animation 帧的中心 120×120 块匹配到录像帧，锚点 = 匹配位置 + SHP 绘制原点）：

| 对象 | 原版 |
| --- | --- |
| WINDOW10 身份栏外框 | 左上 (133,322)、右缘 627（101.5、189.0 s） |
| 攻方（023 一般兵 100.5 s；001 雷歐納德 189.0 s） | 锚点 (320,330) |
| 守方 021 中立姿态 | (350,330)（100.9／101.1／101.3 s） |
| 守方 021 受击姿态 | (266,330) 101.5 s → (245,330) 102.3 s |

**静态**（r2ghidra 读 `hsl01.exe`）：攻方对象 `0x401c20` 普攻（kind 0）置 `x = 视口 + 0x140`、`y = 视口 + 0x14a`（法术／绝技 kind 1／2 为 `y + 0xf0`）；守方对象 `0x4038a0` 同样置 (0x140, 0x14a)，记下 `+0x8a = x` 后按角色 ANIMAL 行的 `k_action`（`+0xa2`；ANIMAL.H：aniKStop 0／aniKRight 1／aniKLeft 2，ANIMAL.TXT 注释 "hit move flag"）偏移：1 → `x − 0x32`，2 → `x + 0x1e`（`0x404560`）。命中时（`0x404040..0x404069`，脚本绝技的命中 opcode 同一段）置击退速度 `0xe0000`（14 px／tick）、角度 0（aniKRight，向右）或 0x80（aniKLeft，向左），尾部 `0x45eb9d／0x45ebdc` 每 tick 积分、`0x45eb89` 每 tick 减 1.0：14 tick 共 105 px。落空（`0x404214..0x404217`）目标 `x ± 0x96`（150 px），`0x45e91e` 每 tick 走 min(36, 剩余／4)、至少 2：14 步＋到达 1 tick。021 为 aniKLeft：350 起、击退到 245，与像素逐点相符。攻击白闪 `aniInsertAttackFlash` 的对象由 `0x40222e..0x402245` 置于攻方对象 (x, y) ＋ 位移。

**资源**：`content/imported/hsl/chapter01/combat_animation/manifest.json` 每行 `source_k_action`（第一章 57 行＋作者关 5 行全部有值）。

**声音**：站位与击退无放声（受击音由武器类 0x194–0x199 另放）。

### 2. 特殊技切入的左上红框立绘

**像素**：原版 242.1 s 与重制补录 72.1 s，把 001 的 `special-1..6.png` 匹配到帧，最佳都是 `special-2`（234×184 红框持剑半身），左上 (100,0)，分数 6.6／3.6。原版分镜顺序（240.5–246.5 s 每 0.25 s 抽帧）：眼部横幅 → 左上红框持剑半身 → 蓝色剑光局部 → 右下肖像 → 白光 → 特写，与重制施法引导 `AnimalCastLead` 一致（静态读法见 [ANIMAL 程序包 §8](../../static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释)）。「重制缺半身立绘」的说法不成立（negative-evidence）。

### 3. 击杀／升级飘字：KILL（随阵亡）→ EXP → $ →（獲得物品）→ LEVEL UP＋升级音 → 加点窗

**资源**（hsl.pak 解码，`content/imported/hsl/shared/reward_floats/`，`hsl generate reward_floats`）：`KILL_000`「KILL」119×43、`KILL_001..010` 数字 0–9（红金金属渐变）；`NUM511`「EXP」57×20 与 `NUM400..409` 紫色数字；`NUM512`「$」16×25 与 `NUM500..509` 金色数字；`NUM514`「LEVEL UP」152×21 金色；`NUM513`「MISS」。对象表：`obj_ShowContinueKillNumber` 395 → `SHAPE\KILL_000.SHP` 11 帧（`defProcShowContinueKillNumber`）；`obj_ShowNumber` 177 → NUM100 65 帧；`obj_LevelUp_Star` 149 → `MAGIC\AIR06_03.SHP`（`effProcFlyUpShape`）。

**静态**：

| 读法 | 地址 |
| --- | --- |
| 金钱分两份累加器，各在自己受益者那轮的阶段 2 飘 $：攻方一轮推 `*0x4c2c84`（`0x4447d8`／`0x4416bc`），装主击击杀金钱（`0x4446d3`／`0x4415bc` 调 `0x40e390`）与本次交换全部 StealGold 实得（`0x40b556..0x40b574`，双方施放者都加这里）；反击方一轮在 AI 路径推 `*0x4c2978`（`0x441724..0x441738`），它只由反击打死 AI 发起者时写入（`0x44151d..0x44152b`），玩家路径反击方一轮推 0（`0x444847`）；五处清零 `0x441ced`、`0x442b8d`、`0x44437e`、`0x444487`、`0x44519e` | `0x4c2c84`、`0x4c2978` |
| 结算 `0x442720` 每位受益者一轮：阶段 0 先 `0x43bf30` 把镜头滑到受益者（到位才继续），再在 (x, y − 0x30) 生 EXP 浮字（kind 1，等待对象 = 受益者副本 `0x4c42a0`）；阶段 2 生 $（kind 4）；阶段 4 待领池非空开獲得物品窗；阶段 6 `exp ≥ 门槛` 且有点可加时 `0x4071e0` 角色演出＋ LEVEL UP（kind 6）；阶段 8 开升級窗／NPC 自动分配。下一阶段等上一浮字放行 | `0x442720`（阶段字 `0x4c432c`），调用：攻方 `0x4447d8`／`0x4416bc`，反击方 `0x44483c`／`0x441724` |
| kind 6 另调 `0x408b20(x, y, 3)`（`0x415c10` 撒 LevelUp_Star 星光）并放 `0x191` = `sfxLevelUp`（`WAV\LEVELUP2.WAV`） | `0x4084e0` |
| 浮字排版：首字 x − ((位数 − 1) ＋ 前缀格数) × 7，EXP 前缀占 4 格、$ 占 2 格，每格 14 px；LEVEL UP 画在 x；按形状绘制原点居中 | `0x408580` |
| 层级：16 保持 16 tick，之后每 2 tick −1，第 46 tick 删除；层级 < 9（第 32 tick）放行等待者；每 2 tick 上浮 1 px | `0x408580`（[tick 包 §1](../../static_reverse/original_tick_counts.md)） |
| KILL：阵亡者的死亡分支在开始拉伸消散的同一子状态里，若杀手的连杀字（记录 `+0xa8`）> 1，在 (x, y − 0x18) 生 KILL 浮字；KILL 画在 x − (19 × 位数 ＋ 38)，首位数字再右 114、之后每位 38；40 tick 后删除，不上浮、不淡出 | 敌 `0x43f07c..0x43f0aa`、我方 `0x4435c5` → `0x408390`；过程 `0x4083e0` |

**像素**（精灵匹配，中心坐标为形状中心 = 绘制原点）：

| 场次 | KILL | EXP | $ | LEVEL UP |
| --- | --- | --- | --- | --- |
| 336–343 s（KILL 3、$ 100、升级） | 337.954 出现，中心 (263,164)，镜头滑动时随地图上移到 136，338.655 整块消失（0.70 s，无淡出） | 338.371 出现（先被 KILL 盖住，338.655 起可单独匹配），中心 (285,144)，0.7 s 上浮 19 px | 338.972，中心 (292,144) | 339.589，中心 (320,144) |
| 370–377 s（KILL 3、EXP 26、$ 220） | 371.905–372.606（0.70 s），镜头横滑时随地图左移 64 px | 372.355，(285,144) | 372.939，(292,144) | — |
| 498–505 s（敌法师反击、升级） | — | 501.484 EXP 19，(237,144) | — | 502.052，(272,144)；502.702 第二位受益者 EXP 1，(244,144) |

读法：同一场里 EXP → $ → LEVEL UP 间隔 0.60／0.62／0.58 s ≈ 32 tick（本机 18–19 ms／tick），即「上一浮字放行才出下一个」；EXP、$、LEVEL UP 中心按 0x408580 排版反推都落在同一点 x（336 场 = 320，受益者已在画面 (320,192)，y − 48 = 144）；KILL 的中心 263 = 320 − 57（1 位数），数字与 KILL 字之间空约 35 px；KILL 与之后的 EXP 同时在屏（EXP 在 KILL 开始后 0.42–0.45 s，即 16 tick 消散＋镜头滑动之后）；有两位受益者时第一位的 LEVEL UP 在第二位的 EXP 之前（498 场）。

**声音**（`hsl_video_events.py audio`，10 ms 包络起音）：337.5–341.0 s 只有 339.67 s 一个起音（LEVEL UP 精灵出现后 0.08 s）；500.0–503.5 s 只有 502.14 s（LEVEL UP 502.05 s 后 0.09 s）。与 `LEVELUP2.WAV`／`LEVELUP1.WAV` 的互相关只有 0.03–0.05（录音里有背景乐，不能据此认定文件）；文件身份取静态 `0x191` 与资源表 `sfxLevelUp → WAV\LEVELUP2.WAV`。EXP、$、KILL 出现时无起音（0x4084e0 只有 kind 6 放声，0x408390 不放声）。

### 4. 身份栏抗性行：五颗元素宝石＋「07%」

**像素**：原版特写身份栏（101.5 s 等）气力条下一行，放大 4 倍看是五颗菱形宝石（棕、蓝、绿、红、灰）各跟一个数字，即 ASCII 小字的「07%」（不是剑也不是倍率）。宝石匹配（`MAGICON1..5`，9×19）左上 (138 + 48·i, 450)；白字外框 x 149 + 48·i 起、宽 23 px、行 457–465。

**资源**：hsl.pak `SHAPE\MAGICON1..5.SHP`（9×19，棕／蓝／绿／红／灰）；EXE 字串 `SHAPE\MAGICON1..5.SHP`。

**静态**：`0x42f4fc..0x42f58c` 把 MAGICON1..5 装入句柄表 `0x4c3460[0..4]`，魔法列表 `0x42a0ef`／`0x439cec` 以魔法元素 0..4 为下标取图，所以 1..5 = 地水風火心，与 `resist_by_type` 的 0..4 同序。身份栏文字 `0x434d10` 的抗性循环（五项，记录 `+0x104` 起）：未知单位 `"???   "`；值 < 80（0x50）`"%02d"`＋`"%   "`（`0x43563b`）；否则 `"MAX   "`（`0x435616`）。画宝石的调用点未在 `0x4c3460` 的读者里找到（只有两个魔法列表读它，negative-evidence），位置取像素。

### 5. 重制验收录像读数（runtime-measured，重制侧）

Godot Movie Maker 离线录像（60 fps），开发夹具：A 段雷歐納德普攻不致死的 021（被反击），B 段 氣刃斬 击杀 021（连杀 2→3、EXP 差 1 级、必掉的重要物品）；同一套脚本（`sprite` 子命令、中心块锚点匹配、宝石与 WINDOW10 匹配）复量：

| 量 | 原版 | 重制验收录像 |
| --- | --- | --- |
| WINDOW10 | (133,322)–627 | (133,322)–627（3.35 s） |
| 攻方锚点 | (320,330) | (320,320)（2.6 s；录于中线改为 330 之前） |
| 守方 021 中立／受击末 | 350／245 | 350（3.85 s）／245（4.6 s） |
| 反击镜头的 001（aniKRight）受击末 | —（录屏无） | 375（7.35 s）＝ 270 ＋ 105 |
| 左上红框立绘 | special-2 (100,0) | special-2 (100,0)（15.95 s） |
| KILL 3 | 40 tick，中心 x − 57，定住 | 22.000–22.617 s，中心 311 ＝ 368 − 57，漂移 0 |
| EXP → $ 间隔 | 0.60 s（≈32 tick） | 22.30 → 22.80 s（0.53 s ＝ 33 × 16 ms）；中心 x − 35／x − 28 |
| LEVEL UP 与獲得物品窗 | $ → 獲得物品窗 → LEVEL UP（静态阶段 4／6） | 獲得物品窗 23.37 s、领完 24.87 s、LEVEL UP 24.85–24.88 s、加点窗 25.40 s |
| 抗性宝石 | (138+48i, 450) | (138+48i, 450) |

## 重制接线

- `game/battle/runtime/CutinLayout.gd`：`SHOT_ANCHOR = (320,330)`；`attacker_anchor()` x 320；`defender_anchor(row)` 按 k_action 偏 −50／+30；命中后 `knockback_x`、落空后 `dodge_x` 按 tick 位移。普攻（`BattleCombatCutin._show_shot`＋受击段）、脚本绝技（`SkillEffectScriptPlayer` 守方段，从 aniProcessHitMiss 的 impact tick 起）、借用 氣刃斬 与专属演出共用；攻击白闪为 `attacker_anchor()` ＋ 位移（雷歐納德 (−90,−120) → (230,210)）。
- `BattleRewardFloater`：按 §3 排版画 KILL_000＋数字、NUM511＋NUM4xx、NUM512＋NUM5xx、NUM514，层级淡出与上浮按 `0x408580`；KILL 40 tick 定住。游戏代码里只有它画这些美术字。
- `BattleAftermath`：阵亡（遗言 → 拉伸消散，同时在阵亡者头上 24 px 出 KILL，杀手连杀 > 1 时）→ 每位受益者依次 EXP →（归其所有的）$ → LEVEL UP；每格在 32 tick 放行时进入下一格，上一格继续淡完 46 tick；獲得物品待领时 LEVEL UP 格停住（`holding_for_loot`），领完才出；`level_up_presented` 触发升级音（`play_growth_sound` 唯一入口）；之后开加点窗。所有交锋回执（普攻、法术、绝技、反击）经 `BattleAftermath.prepare`。结算前镜头滑到受益者见 [镜头包](../camera_panel_motion/README.md)；LevelUp_Star 星光与 `0x4071e0` 姿势见 [地图姿势与飘字包 §1–§2](../map_pose_floaters/README.md)。
- `BattleVitals`：抗性行画五颗宝石（panels manifest `magicon1..5`），数字按 `resist_text`（「07%」、80 起「MAX」、未知「???」），白字黑影；身份栏在特写、状态页、道具、升級窗、獲得物品窗共用。
- provenance 写法：`runtime-measured docs/evidence_packets/runtime_observations/cutin_floaters/README.md`。

## 复现

不可再生：原版侧唯一记录（录屏读数）。重制侧：`tools/godot.sh --headless --script tests/run_skill_effect_script_tests.gd`（站位全经 `defender_anchor`、manifest 行都有已知 k_action、美术字与升级音单一入口）。

## 边界

- 两份 $ 的先后按「攻方一轮、再反击方一轮」排；被反击打死的 AI 发起者由死亡序列付 `0x4c2978`（`0x43f13f..0x43f150`），这一轮与攻方一轮在原版画面上的先后未实拍。重制攻击不带 StealGold、主击击杀与反杀互斥，两份同时非零目前只在构造收据里出现。
- 抗性数字已用原版 FONT.15＋ASCFONT.15 点阵小字（lane BITMAPFONT）；宝石位置取像素（原版画宝石的调用点未找到）。
- 升级音文件身份来自静态与资源表，录音互相关不足以单独认定。

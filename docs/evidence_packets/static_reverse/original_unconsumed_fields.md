# 字段覆盖未消费项的原版读法

> evidence: static-derived; resource-derived: PLAYERS／各关 OBS／global.obs／TYPE.H／PROCESS.DEF 的取值与出现处; negative-evidence: PLAYERS.class 读取后 10 条指令内无 class 常量比较、install_code（+0x84）除 0x44fa80／0x44fad0 外无读者，均为有界线性扫描; provisional: 禁忌之魂・墳場地下（LEVEL080）光环 0x43def0 第 2 参在两个调用点的来源、逃出克萊恩城（LEVEL053）繩子 engRANGE 框的下边与左右边、新建演员默认 install_code 0..8 在重制里的对应 · status: record-only · functions: 0x403d50, 0x4040da, 0x404f6c, 0x4052f1, 0x406d20, 0x407cc0, 0x407ec0, 0x409790, 0x415c10, 0x415dc0, 0x42b2b0, 0x4348f0, 0x434d10, 0x43def0, 0x44bc8c, 0x44fa80, 0x44fad0, 0x451155 · tools: hsltools/checks/field_coverage.py · updated: 2026-09-30

## 结论

- [字段覆盖](original_field_coverage.md)原先标 unconsumed 的 11 项里，有两处是真缺口，都属演出：普攻受击音的优先链，以及禁忌之魂・墳場地下（LEVEL080）怨念集合體身上周期冒星的光环。原版读这些字段的地方都找到了；已读的各项都没有规则效果，TYPE.H other 剩下的 13 条没有逐条看，不在此列。
- PLAYERS.class（种族）在原版只用来显示：GameClear 状态表和身份栏文字会读它，另有一处原样复制；有界扫描内未见跟 class 常量的比较。重制已经从 panel_assets 显示「種族」，所以改记 consumed，TYPE.H class* 同理。
- install_code（记录 +0x84）是脚本拿来寻址演员的 id。脚本改号一路（actChangePrevInsertObjectID）重制由 `ScriptActorCreationRules._apply_status` 记进 actor_bindings、按 SID token 寻址，效果等价，改记 consumed；新建演员时 `0x407cc0` 写的默认码 0..8 在重制里对应什么待核。
- WINFAIL 里 actMEssage 是大小写拼错，原版和重制都按大小写无关的规则认成 actMessage，所以它其实是被读的。字段覆盖表按精确拼写统计，才把它算成 unconsumed。
- obj_X2 的效果对象 WAV 已经接上。obj_Y2 只出现在逃出克萊恩城（LEVEL053）的繩子上，是 engRANGE 裁切框的下边：上边 464 与重制插入线同值；下边 800 是否裁到图未核（provisional）。TYPE.H objattr* 一个定义都没有；TYPE.H other 里有 114 条是 effProc* 程序码。

## 证据

| 字段 | 原版读点 | 含义 | 重制 | 处置 |
|---|---|---|---|---|
| players.class | 装载 `0x44bc8c..0x44bccb` 写 +0x20；读者 `0x42b3b3`（`0x42b2b0` GameClear 状态表，标签 39 種族，`0x42b130` 带 0x80000000 按 RESOURCE 文字印）、`0x4351a0`（`0x434d10` 身份栏，经 `0x4477b0` 取 RESOURCE 文字）、`0x4349b3`（`0x4348f0` 非零时复制）；全 .text 839 处 [reg+0x20] 读取后 10 条指令内未见 class 常量比较（有界扫描，negative-evidence） | 种族名：101–106 人類／精靈／水族／獸族／翼族／變種，243 半獸人，244 妖精 | `panel_assets.definitions` 写 race，BattleVitals 状态面板、GameClear 表都显示 | 无规则效果，改 consumed |
| players.sound_hit／sound_shoothit | 攻击结算对象 `0x4038a0`（每次出手由 `0x406d20` 创建，过程码 0x9a，过程表项 `0x477c88`）相位 1 命中分支 `0x4040da..0x40414a`：先放攻方 sound_shoothit（`0x406dc9` 写进 `[0x4c13f8]`），没有就放目标的 sound_hit，都没有才按攻方武器图标走跳表 `0x404f6c` 放 404–409，图标大于 5（爪 6、刺 7）放 405 sfxHitSword。目标取自对象 +0xac：创建时写攻方（第 1 参，`0x406dbd`），到 `0x403d50` 才改成 `0x4104d0(1)` 取到的目标；`0x4040e9` 取 `[edi+0xac]` 调 `0x409790`，后者按其 +0xa4 索引记录表 `[0x4c1bc8]` 读 +0x10 | 普攻受击音的三级优先 | `BattlePresentation._play_weapon_hit_sound` 只查武器图标；爪、刺在 `interface_audio.weapon_hits` 里给的是空串 | 缺口 `normal-attack-hit-sound-chain` |
| obj.obj_Y1 | 演员：`0x407ec0` 把非零值写进 live +0x134 低半字（`0x408053`）；`0x43def0`（演员每帧，调用点 `0x44217e`／`0x445633`）在 `0x43e0a7` 读到非零就给倒计数 +0xac 减一，减到 0 时调 `0x415c10(x, y, 码, 0x60, 0x20, 0, 3, 4, 0)` 抛 4 个该码对象：`0x415c10` 对 0x60、0x20 各取随机数，超过一半就折回，实际偏移约 ±0x30（横）×±0x10（纵）；然后第 2 参非零重置为 8、为零重置为 20。效果对象：`0x415dc0` 存进 +0x44，由 effProc 程序在自己的事件点放 | 演员：周期冒出的伴随对象码。效果：WAV | 20 行效果对象 WAV：法术引用的 13 个由 `special_effect_scripts.program_sounds` 接上；逃出克萊恩城（LEVEL053）繩子见 obj_Y2 行；1 个演员没接 | 缺口 `actor-companion-effect-object` |
| obj.obj_X2 | `0x415dc0` 存进 +0x46，由 `0x415d90` 放一次 | 效果对象的第二个 WAV | 9 行效果 WAV，法术引用的 7 个由 program_sounds 接上，另 2 个对象没有法术引用、从不生成；剩 1 行是繩子 | 改 consumed |
| obj.obj_Y2 | defProcObjectMove `0x4051d0` 创建时，对象字 +0x00（obj_Mode）没有 0x1000000 就在 `0x4052f1..0x4052fa` 把 +0x10..+0x1c 清零；繩子是 engRANGE（0x01000000），四个值保留 | 逃出克萊恩城（LEVEL053）25 号繩子的 engRANGE 框：X1 0、Y1 464、X2 10000、Y2 800 | `StoryEffectObjects.TrackSprite` 在插入线 y=464 裁掉上方，和 Y1 同值 | 上边同值；下边 800 是否裁到图未核（provisional）；保持 unconsumed |
| actor_record.install_code | `0x450840` case 0x20（`0x451155`，actChangePrevInsertObjectID）写 +0x84；`0x44fa80` 返回它，`0x44fad0` 逐槽拿它和 code 比较；`0x407cc0` 另在 `0x407d94` 按对象 +0xa2 经 11 项跳表 `0x407e8c` 给新建演员写默认码 0..8，跳表最后两项与首两项同目标 | 脚本寻址 id | 改号一路由 `ScriptActorCreationRules._apply_status` 记进 actor_bindings，按 SID token 寻址，效果等价；默认码 0..8 的对应待核 | 改 consumed |
| winfail.actMEssage | 脚本词按大小写无关匹配 | WINFAIL002 胜利段 028 的台词 768 | `WinfailCompiler.canonical_action` 把它归到 actMessage | 生成器按大小写归并，改 consumed |
| TYPE.H class* | 同 players.class | 同上 | 同上 | 改 consumed |
| TYPE.H objattr* | TYPE.H 里没有 objattr 定义；objattr* 在 PROCESS.DEF，obj_Attribute 行已经覆盖 | — | — | 改 dead |
| TYPE.H other | 127 条里 114 条 effProc*，是效果对象 obj_Data9 选中的程序（跳表 `0x4231b0`）；其余 13 条：gameBigMapLevel、gameTempResourceID、gameover*（5）、bmpm*（5）、effSMOKE | — | effProc* 经探针 `effect_motion.table_defines` 按名字解出程序号，PROCESS.DEF 优先、TYPE.H 同名被遮；EffectObjectMotion 放记录 | 拆出 effProc* 组记 consumed；其余 13 条保持 unconsumed |

普攻受击音优先链：PLAYERS 只有 5 行带这两个字段。sound_hit 在 咕嚕 008 和 殭屍 034 上是 HIT00017，在 門 100（那可那魯邊境 · 邊境之門（LEVEL018））和 船殼 101（巴瀚納海峽（LEVEL012）、亞雷比斯（LEVEL026））上是 HIT00015；sound_shoothit 只有 紅龍 051 带，是 BOMB0028（龍之息（火山）（LEVEL013）、尼布魯瀑布（LEVEL022）、大地的裂縫（LEVEL043）和尼布魯瀑布　遭遇戰（LEVEL570–572））。武器图标是爪或刺的 PLAYERS 有 15 行：008、017、034–039、050–052、057、060、066、068。咕嚕 008 是队员，在 106 场战斗里出现。攻方 shoothit、受方 sound_hit 这两级优先和爪／刺的 405 回退，重制未做：原版这些攻击命中时会再响一声撞击音，重制只有出手音。

禁忌之魂・墳場地下（LEVEL080）光环：敌军 怨念集合體 068（obj-080 第 99 号 Enemy068）写着 obj_Y1 = obj_Story_Level_Enemy68Star（= 90）。obj-080 的 90 号是 LevelUp_Star（MAGIC\SP52_044.SHP，defProcEffectProcess1，effProcFlyUpShape），和升级飞星是同一种图。所以原版里这个敌人每隔 20（或 8）tick 就在身边随机冒出 4 颗上飞的星，这一光环重制未做。live +0x134 的高两位是转职旗（`0x434b40` 用 or 写入；`0x4557e5`／`0x4557fb` 选人时读），和这个低半字互不干扰。

## 重制接线

- 字段覆盖的判定在 `tools/hsltools/checks/field_coverage.py` 的 FIELD_NOTES 里。winfail 表里，大小写不同但和已支持的词相同的，用 `canonical_action` 当 consumer。TYPE.H 按 DEFINE_GROUPS 分组，新加了 `TYPE.H effProc*` 一组。
- 两个缺口登记在 [差异清单](parity_gap_inventory.md)：`normal-attack-hit-sound-chain`、`actor-companion-effect-object`。

## 复现

- `python3 tools/hsl.py generate field_coverage`：重算表格和总数。
- 各 OBS 里的 obj_X2／Y1／Y2 出现处，按 `PYTHONPATH=tools python3 -m hsltools.checks.field_coverage --census` 同样的读法从 hsl.pak 逐关读 `[Object]` 块统计（需要原版 PAK）。

## 限制

- 「class 常量比较」和「install_code 其他读者」两条否定结论都来自有界线性扫描：前者只看读取后 10 条指令，后者把对象和物品表的 +0x84 排除在外，经寄存器间接传的读法可能漏掉。
- 光环重置值由 `0x43def0` 的第 2 参决定，非零 8、为零 20。两个调用点 `0x44217e` 压 [esp+0x24]、`0x445633` 压 [esp+0x14]，这两个值从哪来待追。
- 繩子框的下边 800 有没有裁到图没有核：按记录的轨迹，y 偏移从 4 走到 260。
- `0x407cc0` 给新建演员写的默认码 0..8 在重制里对应哪种寻址待核。

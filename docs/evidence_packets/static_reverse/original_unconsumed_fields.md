# 字段覆盖未消费项的原版读法

> evidence: static-derived; resource-derived: PLAYERS／各关 OBS／global.obs／TYPE.H／PROCESS.DEF 的取值与出现处; negative-evidence: PLAYERS.class 读取后 10 条指令内无 class 常量比较、install_code（+0x84）除 0x44fa80／0x44fad0 外无读者，均为有界线性扫描；0x406eb0 调用者（0x441d47／0x4425bc／0x4452f1，无指针引用）与 0x42c180 51 个调用点前 14 条指令为全 .text 有界线性扫描; provisional: 禁忌之魂・墳場地下（LEVEL080）光环 0x43def0 第 2 参在两个调用点的来源、逃出克萊恩城（LEVEL053）繩子 engRANGE 框的下边与左右边、新建演员默认 install_code 0..8 在重制里的对应 · status: live · functions: 0x401c20, 0x4038a0, 0x403d3d, 0x403d50, 0x4040da, 0x404f6c, 0x4052f1, 0x406d20, 0x406eb0, 0x407cc0, 0x407ec0, 0x409610, 0x409760, 0x409790, 0x415c10, 0x415dc0, 0x42b2b0, 0x4348f0, 0x434d10, 0x43def0, 0x442a90, 0x44bc8c, 0x44fa80, 0x44fad0, 0x451155 · tools: hsltools/checks/field_coverage.py · updated: 2026-09-30

## 结论

- [字段覆盖](original_field_coverage.md)原先标 unconsumed 的 11 项里，有两处是真缺口，都属演出：普攻受击音的优先链（已照做，见下条），以及禁忌之魂・墳場地下（LEVEL080）怨念集合體身上周期冒星的光环。原版读这些字段的地方都找到了；已读的各项都没有规则效果，TYPE.H other 剩下的 13 条没有逐条看，不在此列。
- 普攻命中音逐级回退，只放一声。`0x4040da` 先看 `[0x4c13f8]`：非零就跳 `0x404149`，由 `0x42c180` 放。为零才在 `0x4040e9` 调 `0x409790`：受方模板 +0x10 非零就放，返回 1，跳 `0x404152` 越过武器音。两级都空才到 `0x404104`，按图标 `[0x4c6f60]` 查表 `0x404f6c`（0..5 → 404..409，大于 5 由 `ja 0x404130` 取 405），经 `0x4477b0`／`0x459990`／`0x42c180` 放。未命中时，`0x403f49` 的掷点 `[0x4c1418]` 不小于命中率 `[edi+0xa6]` 就走 `0x4041ea`，只调 `0x409760([edi+0xac])` 放受方模板 +0xc 的闪避音，三级链整段不走。sound_shoothit 不看武器：`0x406d20` 每建一个结算对象，`0x406d8f` 先清 `[0x4c13f8]`，`0x406dc9` 在攻方模板 +0x22 非零时写入，与武器图标、模式无关；图标 `[0x4c6f60]` 只在模式 0（普攻）写。
- PLAYERS.class（种族）在原版只用来显示：GameClear 状态表和身份栏文字会读它，另有一处原样复制；有界扫描内未见跟 class 常量的比较。重制已经从 panel_assets 显示「種族」，所以改记 consumed，TYPE.H class* 同理。
- install_code（记录 +0x84）是脚本拿来寻址演员的 id。脚本改号一路（actChangePrevInsertObjectID）重制由 `ScriptActorCreationRules._apply_status` 记进 actor_bindings、按 SID token 寻址，效果等价，改记 consumed；新建演员时 `0x407cc0` 写的默认码 0..8 在重制里对应什么待核。
- WINFAIL 里 actMEssage 是大小写拼错，原版和重制都按大小写无关的规则认成 actMessage，所以它其实是被读的。字段覆盖表按精确拼写统计，才把它算成 unconsumed。
- obj_X2 的效果对象 WAV 已经接上。obj_Y2 只出现在逃出克萊恩城（LEVEL053）的繩子上，是 engRANGE 裁切框的下边：上边 464 与重制插入线同值；下边 800 是否裁到图未核（provisional）。TYPE.H objattr* 一个定义都没有；TYPE.H other 里有 114 条是 effProc* 程序码。

## 证据

| 字段 | 原版读点 | 含义 | 重制 | 处置 |
|---|---|---|---|---|
| players.class | 装载 `0x44bc8c..0x44bccb` 写 +0x20；读者 `0x42b3b3`（`0x42b2b0` GameClear 状态表，标签 39 種族，`0x42b130` 带 0x80000000 按 RESOURCE 文字印）、`0x4351a0`（`0x434d10` 身份栏，经 `0x4477b0` 取 RESOURCE 文字）、`0x4349b3`（`0x4348f0` 非零时复制）；全 .text 839 处 [reg+0x20] 读取后 10 条指令内未见 class 常量比较（有界扫描，negative-evidence） | 种族名：101–106 人類／精靈／水族／獸族／翼族／變種，243 半獸人，244 妖精 | `panel_assets.definitions` 写 race，BattleVitals 状态面板、GameClear 表都显示 | 无规则效果，改 consumed |
| players.sound_hit／sound_shoothit | 受方结算对象 `0x4038a0`（过程码 0x9b，过程表项 `0x477c88`，只由 `0x406eb0` 创建，+0xac 写目标 `0x406f55`）相位 1 命中分支 `0x4040da..0x40414a`：先放攻方 sound_shoothit（`[0x4c13f8]`，攻方起手对象 `0x401c20`（0x9a，`0x477c84`）由 `0x406d20` 创建时在 `0x406dc9..0x406dd7` 读攻方 +0x22 写入；`0x4040da` 是它唯一读者），没有就放目标的 sound_hit，都没有才按攻方武器图标走跳表 `0x404f6c` 放 404–409，图标大于 5（爪 6、刺 7）放 405 sfxHitSword。`0x4040e9` 取 `[edi+0xac]` 调 `0x409790`（唯一调用点 `0x4040f0`），后者按其 +0xa4 索引记录表 `[0x4c1bc8]` 读 +0x10 | 普攻受击音的三级优先 | `BattlePresentation._play_hit_sound` 照三级链；`actor_audio` 导入 hit／shoothit 事件 | 已照做，改 consumed |
| obj.obj_Y1 | 演员：`0x407ec0` 把非零值写进 live +0x134 低半字（`0x408053`）；`0x43def0`（演员每帧，调用点 `0x44217e`／`0x445633`）在 `0x43e0a7` 读到非零就给倒计数 +0xac 减一，减到 0 时调 `0x415c10(x, y, 码, 0x60, 0x20, 0, 3, 4, 0)` 抛 4 个该码对象：`0x415c10` 对 0x60、0x20 各取随机数，超过一半就折回，实际偏移约 ±0x30（横）×±0x10（纵）；然后第 2 参非零重置为 8、为零重置为 20。效果对象：`0x415dc0` 存进 +0x44，由 effProc 程序在自己的事件点放 | 演员：周期冒出的伴随对象码。效果：WAV | 20 行效果对象 WAV：法术引用的 13 个由 `special_effect_scripts.program_sounds` 接上；逃出克萊恩城（LEVEL053）繩子见 obj_Y2 行；1 个演员没接 | 缺口 `actor-companion-effect-object` |
| obj.obj_X2 | `0x415dc0` 存进 +0x46，由 `0x415d90` 放一次 | 效果对象的第二个 WAV | 9 行效果 WAV，法术引用的 7 个由 program_sounds 接上，另 2 个对象没有法术引用、从不生成；剩 1 行是繩子 | 改 consumed |
| obj.obj_Y2 | defProcObjectMove `0x4051d0` 创建时，对象字 +0x00（obj_Mode）没有 0x1000000 就在 `0x4052f1..0x4052fa` 把 +0x10..+0x1c 清零；繩子是 engRANGE（0x01000000），四个值保留 | 逃出克萊恩城（LEVEL053）25 号繩子的 engRANGE 框：X1 0、Y1 464、X2 10000、Y2 800 | `StoryEffectObjects.TrackSprite` 在插入线 y=464 裁掉上方，和 Y1 同值 | 上边同值；下边 800 是否裁到图未核（provisional）；保持 unconsumed |
| actor_record.install_code | `0x450840` case 0x20（`0x451155`，actChangePrevInsertObjectID）写 +0x84；`0x44fa80` 返回它，`0x44fad0` 逐槽拿它和 code 比较；`0x407cc0` 另在 `0x407d94` 按对象 +0xa2 经 11 项跳表 `0x407e8c` 给新建演员写默认码 0..8，跳表最后两项与首两项同目标 | 脚本寻址 id | 改号一路由 `ScriptActorCreationRules._apply_status` 记进 actor_bindings，按 SID token 寻址，效果等价；默认码 0..8 的对应待核 | 改 consumed |
| winfail.actMEssage | 脚本词按大小写无关匹配 | WINFAIL002 胜利段 028 的台词 768 | `WinfailCompiler.canonical_action` 把它归到 actMessage | 生成器按大小写归并，改 consumed |
| TYPE.H class* | 同 players.class | 同上 | 同上 | 改 consumed |
| TYPE.H objattr* | TYPE.H 里没有 objattr 定义；objattr* 在 PROCESS.DEF，obj_Attribute 行已经覆盖 | — | — | 改 dead |
| TYPE.H other | 127 条里 114 条 effProc*，是效果对象 obj_Data9 选中的程序（跳表 `0x4231b0`）；其余 13 条：gameBigMapLevel、gameTempResourceID、gameover*（5）、bmpm*（5）、effSMOKE | — | effProc* 经探针 `effect_motion.table_defines` 按名字解出程序号，PROCESS.DEF 优先、TYPE.H 同名被遮；EffectObjectMotion 放记录 | 拆出 effProc* 组记 consumed；其余 13 条保持 unconsumed |

普攻受击音优先链：PLAYERS 只有 5 行带这两个字段。sound_hit 在 咕嚕 008 和 殭屍 034 上是 HIT00017，在 門 100（那可那魯邊境 · 邊境之門（LEVEL018））和 船殼 101（巴瀚納海峽（LEVEL012）、亞雷比斯（LEVEL026））上是 HIT00015；sound_shoothit 只有 紅龍 051 带，是 BOMB0028（龍之息（火山）（LEVEL013）、尼布魯瀑布（LEVEL022）、大地的裂縫（LEVEL043）和尼布魯瀑布　遭遇戰（LEVEL570–572））。武器图标是爪或刺的 PLAYERS 有 15 行：008、017、034–039、050–052、057、060、066、068。咕嚕 008 是队员，在 106 场战斗里出现。原版这些攻击命中时，出手音之后再响一声撞击音。

魔法与技能打击不走这条链，也不放受方闪避音。命中音链 `0x4040da..0x40414a` 和闪避 `0x4041ea..0x404247`（`0x40423f` 调 `0x409760` 读模板 +0xc，是 `0x409760` 唯一调用点）都在受方对象 `0x4038a0` 的相位 1（`0x403f13`）里。魔法（结算模式 1）：魔法通道 `0x442a90` 只在 `0x442f26` 调 `0x406d20(施法者, 1, 0x4c42a0)` 建施法者起手对象 `0x401c20`，不建受方对象；`0x406eb0` 只有三处调用 `0x441d47`（技能）、`0x4425bc`（普攻）、`0x4452f1`（技能），没有指针引用。技能（模式 2）：受方对象 +0xa4 = 2 时，case 0 在 `0x403954` 比较 `word [edi+0xa4], 2`，相等就进脚本解释（`[0x4c1408]`，op 0 处理入口 `0x403d3d`（`0x403d50` 写 +0xac），`0x4104d0(1)` 取目标）。模式 2 在外层状态 +0x8e 为 0 时，+0x8c 只会写出 0（进脚本，`0x403954`）、0x62（`0x403ecc`）、0x63 随即复位（`0x4047b8`）、0x64（`0x403d56`）；外层 1／0x12／0x64 回到外层 0 时一律复位到 (0,0)。`0x404b9f` 写 +0x8c = 1，但从 `0x403f0e` 到达时不是模式 2，从 `0x404b95` 顺序落入（`0x404b2a`／`0x404b53` 由外层 0x65 跳来）时外层是 0x65；`0x4042a0` 是 case 2 先置 3 再加 1 得 4，不写 1。函数外没有跳进相位 1 体（`0x403f13..0x40424c`）的跳转，函数内也不写 +0xa4，所以相位 1 走不到。技能的声音只来自脚本 aniPlaySound／aniPlayHitSound（`0x403c9c` 无条件、`0x403cb5` 只在 `[0x4c1418]` < +0xa6 即命中时放；调用点 `0x403ca8`／`0x403cd8`）与效果对象的 objcomd 程序（objmPlaySound `0x4059b7`／objmPlayHitSound `0x4059cf`）。对 `0x42c180` 51 个调用点前 14 条指令的有界扫描，取模板表 `[0x4c1bc8]` 记录后读声音字段的有 `0x409610`（`0x409635`／`0x409649` 取记录，`0x409670` 读模板 +0x12，`0x409680` 调 `0x42c180`；同函数 `0x4096a0`／`0x4096d5`／`0x4096e9` 也放音）、`0x409720`、`0x409750`、`0x409780`、`0x4097bd`；+0x10（sound_hit）只由 `0x409790` 读。重制原先技能落空会放受方 miss，已去掉；魔法、技能命中本就不放命中音，与原版一致。以上是静态读法，没有原版运行时声音记录佐证。

禁忌之魂・墳場地下（LEVEL080）光环：敌军 怨念集合體 068（obj-080 第 99 号 Enemy068）写着 obj_Y1 = obj_Story_Level_Enemy68Star（= 90）。obj-080 的 90 号是 LevelUp_Star（MAGIC\SP52_044.SHP，defProcEffectProcess1，effProcFlyUpShape），和升级飞星是同一种图。所以原版里这个敌人每隔 20（或 8）tick 就在身边随机冒出 4 颗上飞的星，这一光环重制未做。live +0x134 的高两位是转职旗（`0x434b40` 用 or 写入；`0x4557e5`／`0x4557fb` 选人时读），和这个低半字互不干扰。

## 重制接线

- 字段覆盖的判定在 `tools/hsltools/checks/field_coverage.py` 的 FIELD_NOTES 里。winfail 表里，大小写不同但和已支持的词相同的，用 `canonical_action` 当 consumer。TYPE.H 按 DEFINE_GROUPS 分组，新加了 `TYPE.H effProc*` 一组。
- 缺口 `actor-companion-effect-object` 登记在 [差异清单](parity_gap_inventory.md)；`normal-attack-hit-sound-chain` 已照做，从差异清单删除。
- 普攻命中音：`actor_audio.OPTIONAL_EVENTS` 与 `levels/actors.AUDIO_EVENTS` 只给带 sound_hit／sound_shoothit 的行导出 hit／shoothit 事件，共享表与各关表读法相同；爪、刺在 `interface_audio.weapon_hits` 里没有表项，取 manifest 的 weapon_hit_default（`0x404130` 的缺省分支，hit_sword）；`BattlePresentation._play_hit_sound` 依次查攻方 shoothit、受方 hit、攻方武器音，只放一声。普攻未命中只放受方 miss；技能与魔法打击命中、落空都不放这两类声音（`_present_impact` 按 `magic_key`／`skill_name` 排除），读法见上文「魔法与技能打击」一段。

## 复现

- `python3 tools/hsl.py generate field_coverage`：重算表格和总数。
- 各 OBS 里的 obj_X2／Y1／Y2 出现处，按 `PYTHONPATH=tools python3 -m hsltools.checks.field_coverage --census` 同样的读法从 hsl.pak 逐关读 `[Object]` 块统计（需要原版 PAK）。

## 限制

- 「class 常量比较」和「install_code 其他读者」两条否定结论都来自有界线性扫描：前者只看读取后 10 条指令，后者把对象和物品表的 +0x84 排除在外，经寄存器间接传的读法可能漏掉。
- 光环重置值由 `0x43def0` 的第 2 参决定，非零 8、为零 20。两个调用点 `0x44217e` 压 [esp+0x24]、`0x445633` 压 [esp+0x14]，这两个值从哪来待追。
- 魔法、技能不放命中音与闪避音的结论只有静态读法：`0x406eb0` 的调用者与 `0x42c180` 调用点前 14 条指令都是全 .text 有界线性扫描，经寄存器间接调用的可能漏掉。
- 繩子框的下边 800 有没有裁到图没有核：按记录的轨迹，y 偏移从 4 走到 260。
- `0x407cc0` 给新建演员写的默认码 0..8 在重制里对应哪种寻址待核。

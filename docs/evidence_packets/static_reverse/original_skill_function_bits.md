# 技能功能位：衰弱、净化、回魔、再行动／取消／吸取、AI 绝技桶与结果数字

> evidence: static-derived; resource-derived; provisional · status: live · functions: 0x4051d0, 0x406fe0, 0x4074a0, 0x407550, 0x4075a0, 0x409a60, 0x409be0, 0x40a5d0, 0x40a7b0, 0x40aa80, 0x40b910, 0x40c480, 0x40c570, 0x40c620, 0x40c770, 0x40d340, 0x40d4e0, 0x40dc50, 0x40dc70, 0x40dcf0, 0x40dd80, 0x40df70, 0x40e0e0, 0x40e100, 0x40e180, 0x40e2f0, 0x40e6c0, 0x42c780, 0x4348f0, 0x436e80, 0x448420, 0x448840, 0x44f2d0, 0x44f580 · tools: hsltools/assets/skill_effects.py, hsltools/data/skill_book.py, hsltools/probes/steal_ratio.py, run_ai_support_tests.gd, run_skill_effect_script_tests.gd · updated: 2026-09-28

## 结论

- 原版：`0x40aa80` 按 function mask 固定顺序逐位结算，每位调同一数值 helper `0x40a7b0`；衰弱（0x1000）减基础四属性并刷新，净化（0x200／0x400／0x800／0x2000）清对应状态字，HealMP、ActiveAgain、CancelActive、StealGold、StealItem、StealHP 各有即时 EXP 换算；绝技通道（channel 1）命中只读 hit_ratio、magicOTHER 不乘抗性（static-derived；偷窃加成字另有 93 组原生回执）。
- AI 的 SPECIAL 与 MAGIC 用同一分桶器 `0x40c620`，SPECIAL 选行 `0x40dd80` 与 MAGIC `0x40c770` 的接受语义不同（MAGIC 桶 5／7 对有用目标无条件接受）；进攻绝技与魔法共用同一对 (first, fallback) 桶（static-derived）。
- 结果数字：`aniShowHitResult` 读 HP／MP 变化生成 kind 0 红（伤害）、2 绿（回复）、3 蓝（MP）、5 MISS；功能绝技 HP／MP 皆 0 时按本次 EXP 之和为非零则不显示、为零则 MISS；数字无正负号（static-derived；字形 resource-derived）。
- 收片段条件：opcode 30 把最后生成的数字设为守方对象的 waiter、phase 停在 0x62，数字 `+0x28 < 9` 时才放行（红字 27＋10×位数 tick），数字自身活到 34＋10×位数（两位 47／54）；50／60 行绝技守方脚本以 aniShowHitResult 结尾，脚本随放行结束，数字尾巴在收尾期间走完。普通一击同样由数字放行守方 phase 3；续击无过渡，上一镜数字在下一镜上走完（static-derived）。
- 重制：`StatusEffectRules`、`SupportMagicRules`、`StatMagicRules`、`SpecialUtilityRules`、`SpecialStatusRules`、`AISkillDecisionRules`／`AISkillPlanning`／`AISupportPlanning`，结果数字 `ResultNumberFloater`，绝技脚本 `SkillEffectScriptPlayer`（static-derived；脚本时钟与对象运动 provisional）。
- 差异：天鳴覺醒／獅子吼对无可再激活／取消槽的目标重制拒绝施放（原版照付 ST）；`0x40d4e0` 单次共用抽取重制在各通道内各抽一次；MAGIC 桶 5 对已有增益的目标重制预过滤跳过（provisional）。

## 证据

**static-derived**（r2／r2ghidra 阅读 `hsl01.exe`；除偷窃加成字外未做有界原执行）

`0x40aa80(caster_obj, target_obj, table_index, code, channel)` 位访问顺序：Attack(1)@`0x40ab35` → Heal(2)@`0x40abb0` → Paralysis(4) → Poison(8) → NoMagic(0x10)@`0x40ae3d` → Weaken(0x1000)@`0x40aee0` → DefUp(0x20)@`0x40b01c` → AttUp(0x40)@`0x40b112` → AllUp(0x100)@`0x40b1ee` → ClearAtDfUp(0x4000)@`0x40b29d` → CureWeaken(0x2000)@`0x40b30f` → …；每个状态位各自 proc6 判定（channel0 读 `status_hit_ratio`），Poison／Weaken 幅度在同行含 Attack 时 ×30/100，主伤害致死后状态分支跳过。

| 位 | 名称 | 原分支 |
| --- | --- | --- |
| `0x1000` | Weaken | 免疫 `0x40e2f0(target, 0x2000000)`；proc6 抽签；`rand(2)+2` 回合累加到 +0x38（封顶 9）；flag \|= 8；贡献 turns×7；proc0 取幅度（同行含 Attack 则 ×30/100），折叠 >15 → 13..15、<2 → 2..3，与旧幅度 `max(old,(old+new)/2)` 合并进 +0x3a；`0x448840` 刷新 |
| `0x2000` | CureWeaken | 仅 flag&8：清 +0x38 整字与 flag 8、刷新；贡献 (turns+1)×12 |
| `0x200`／`0x400`／`0x800` | CureParalysis／CurePoison／CureNoMagic | 只看 flag 4／1／2，清 +0x3c／+0x30／+0x34 整字；不刷新；贡献 (turns+1)×12；四净化掩码 `0x2e00` 按 0x2000→0x200→0x400→0x800 访问 |
| `0x8000` | HealMP | proc1 取值，+0xe0 加到 +0xe4 封顶；实际回复≠0 时贡献临时改为 `rand(caster+0x9c)+1` 在 `0x40b49e` 换算后于 `0x40b4aa` 恢复 |
| `0x10000` | ActiveAgain | proc0 命中后 `0x4075a0(target)`：在队列槽 [0, current) 找该目标已消耗槽置回 1，目标本回合未行动返回 0；`0x4074a0` 前向槽用尽后从 -1 再扫一遍才重建回合，再激活槽在本回合末尾服务 |
| `0x80000` | CancelActive（ActiveAgain 未置位才访问） | proc0 命中后 `0x407550(target)`：从 current+1 向后找仍启用的槽置 0 |
| `0x20000` | StealGold | `amount = rand(\|high-low\|) + low + 1 + rand(dex/3 + level)`；caster 记录 +0x28&0x10000（`0x40b538 test`、`0x40b546 je`）时封顶目标 live +0x98（`0x40b548`；记录经 `0x40aa87 mov ecx, [0x4c1bc8]`、`0x40aab3`／`0x40aac3` 取）并加到 `0x4c2c84`，否则从 `0x4c1bcc` 扣；两支都不减目标 +0x98；EXP `amount/2 + rand(amount/2)` 直接计入；击杀金 `0x40e390` 读同一 +0x98（`0x40e3a7`） |
| `0x40000` | StealItem | 遍历目标 +0x138 八槽，`rand(100)+1 < 0x40e6c0(item)+10+caster+0x196` 时 `0x44f2d0(item,1)` 与 `0x436e80(target, slot)`，首个成功即停；`0x40e6c0` 即 ITEM `get_ratio`（掉落 `0x44f580` 同一 getter）；贡献永久加 proc0 值（`0x40b641`），再 `rand(level)+1` 即时换算（`0x40b674`）后恢复（`0x40b68b`）；遇首个空槽即断（`0x40b5e1..0x40b5e5`） |
| `0x100000` | StealHP | 需主伤害≠0：caster HP += 伤害封顶；贡献 += 伤害×20/100 − 伤害（`0x40b7c3..0x40b7ec`），>0 时 `0x40b7fe` 换算后 `0x40b814` 恢复；尾部 `0x40b866` 再按原伤害换算 |
| `0x100` | AllUp | `0x40b206` proc1 调 helper（只保留补偿）；`0x40b20d` turns = rand(4)+2；`0x40b218` flag \|= 0x40；+0x48 累加超过 9 按差额缩减；贡献 3×turns（`0x40b24c`）；`0x40b257` rand(14)，新强度 = 旧 + rand(14)+7 封顶 20（`0x40b269`）存 +0x4a；`0x40b278` 刷新 |

分派后 `*(caster+0xb0) = compensation`；即时换算五处（`0x40b49e`、`0x40b674`、`0x40b6fa`、`0x40b770`、`0x40b7fe`）同一模式：保存 `[0x4c13fc]` → 写临时值 → `call 0x40a5d0` → 累加 var_18h → 恢复；已有即时换算时贡献 >0 才在 `0x40b866` 再换算并相加，否则 `0x40b8b5` 直接返回一次换算。

`0x40a7b0` 通道差异：channel0 命中率 = (proc&4) ? status_hit_ratio : caster+0xd4 + hit_ratio + 补偿；channel1 = hit_ratio + 补偿；落空 proc&4==0 时补偿 += (draw+1)/10；命中清零；proc&2==0 取三角值加属性项（channel0：`(clamp(level,1,80)+mind项+sample)×magic_attack/100`；channel1：`(sample + rand(level×180/100) + rand(level×150/100) + dex/3 + con/8 + mind/4) × attackpow_ratio/100`），proc&2≠0 用 `0x406fe0(low, high)` 纯三角；<3 折到 3..5；proc&1==0 按 row.type 取抗性（≤80），magicOTHER 不乘。

衰弱与属性：`0x448840` 把基础 +0x64／+0x68／+0x6c／+0x70 复制到 live +0x4c..+0x58，flag&8 时各减 +0x3a（下限 1），再进职业公式；复制基础抗性 +0x118..+0x128 → +0x104..+0x114 后（`0x448903`）flag&0x40 时五槽各加 +0x4a（封顶 80）。`0x40b910` 对 +0x38、+0x48 递减，归零清 flag 并刷新（`0x40b9eb..0x40ba0c`）；退魔 `0x40b29d` 只清 0x20／0x10 与 +0x44／+0x40。公式读的都是 live 字：`0x40a7b0` channel1 +0x50/3、+0x54/4、+0x58/8，channel0 mind +0x54；`0x409a60` 命中差 (+0x50 − 目标+0x50)/2；`0x409be0` 力量差 (+0x4c − 目标+0x4c)/2；StealGold +0x50/3。免疫位：PLAYERS loader `0x44c3ec` 把 `no_weaken` 写 +0xa0 的 0x2000（`no_paralyze` 0x800、`no_disablemagic` 0x1000 同段），`0x448420` 在装备非空时映射为效果位 0x2000000。

偷窃加成字（[original_steal_ratio.json](original_steal_ratio.json)，`hsltools/probes/steal_ratio.py` 原生回执 refresh 21 组、job_up 5 组、steal 67 组）：

| 写点／判定 | 读法 | 原生结果 |
| --- | --- | --- |
| PLAYERS loader `0x44b980` | `steal_ratio` → +0x194（缺行 0）；只有 004 漢克斯 30、013 20 非零 | — |
| 刷新 `0x448840` | +0x196 = +0x194 字，为 0 时 12 | 001 → 12／32／52，004 → 30／50／70，013 → 20／40／60（装备 无／131／131×2）；字 1 → 1；两次刷新相同 |
| 装备 `0x448420` | +0x196 += item+0x40（`add_steal_ratio`，ITEM 只有 131 隱忍黑衣 20） | 同上 |
| 转职 `0x4348f0` | `0x434aa6 add word [esi+0x194], cx` | 004→013 为 30+20=50；职业码 89／81／82／88 复制，槽 code 809，+0x134 \|= flag |
| 判定 `0x40b5a8` | `rand(100)+1 < get_ratio + 10 + caster+0x196` | 左密库存首槽 roll 75 < 82 偷；首槽为空零抽样零偷取；`[32,0,210,…]` 首槽失败后遇空槽即停；八件 get_ratio 0、字 0 时种子 7／40 全失败、种子 99 第八槽 roll 3 偷中；未命中补偿加 roll/10 |

AI 绝技通道（AI 对象过程 `0x43ede0`）：

| 原入口 | 读法 |
| --- | --- |
| `0x40c620` | 清 `*0x4c1b78` 的 0x1c 个 dword，先遍历 SPECIAL 表 `0x4c3920`（7 型 × 位掩码 actor+0x158..，`row+0x10*20 <= +0xe8`）以 `0x407010(row+0x28, 0x38, row+0xc, type, code, buckets)` 装桶，再遍历 MAGIC 表 `0x4c2ca0`（actor+0x174..，`row+0x10 <= +0xe0`，status&2 时跳过）以 base 0 装桶；桶：治疗 1（范围）／2、进攻 3／4、增益 5、状态 6、净化 7；SPECIAL 桶从 +0x38 起 |
| `0x40e0e0`／`0x40dc50` | SPECIAL／MAGIC 治疗桶 1 或 2 非空 |
| `0x40e100(mask)`／`0x40dc70(mask)` | 净化桶 7 中有净化位（0x400→1、0x800→2、0x200→4、0x2000→8）落在 mask 之外的行 |
| `0x40e180(mask)`／`0x40dcf0(mask)` | 增益桶 5 中有增益 flag（0x20→0x20、0x40→0x10、0x100→0x40）全不在 mask 内的行 |
| `0x440767..0x44080c` 友军回复 | `0x40c2f0(actor,8,1)` → `0x40c570(actor, 0x40dc50(), 0x40e0e0())`；类别 0 首件回复药 `0x40c1d0` 并 `0x40d530(range 1)`；1 → 子状态 0xd（MAGIC）；2 → 0x14（SPECIAL）；三类 `(kind+1)%3` 轮转 |
| `0x4408ee..0x440a21` 状态援助 | `0x40c3a0(actor,8,1,&mask)` → `0x40c570(actor, 0x40dc70(mask), 0x40e100(mask))`；类别 0 `0x40c230` |
| `0x440a3b..0x440ad5` 增益 | `0x40c480(actor,8,1,&mask)` → `0x458c10() & 1` 决定先 MAGIC 或先 SPECIAL，两次尝试，无物品类别 |
| `0x40dd80(bucket, mask)` | 桶在 +0x38+8×(bucket−1)，`rand(32)%count` 起点，逐节点 `rand(100)+1 <= row+0x20`；桶 7 无交集置 200，桶 5 已全在 mask 内置 200；桶 3／4 无额外分支 |
| `0x40c770(bucket, mask)` | 每节点先 `rand(100)+1`；桶 7 净化位与 mask 相交 roll = 0、否则 200（`0x40c89d`）；桶 5 增益 flag 与 mask 无交集 roll = 0（`0x40c8dd..0x40c8e1`）；桶 3／4 对含 0x4000 的行 mask 含 0x60 则 0、否则 200；再 `roll <= row+0x28` |
| `0x40df70(actor, target, bucket, fallback, …)` | 桶 7／5 取 `0x40c1b0`／`0x40c2d0(target)` 为 mask，`0x40dd80(first)` 落空或 `0x40cca0`／`0x40c9a0` 站位失败再试 fallback |
| 进攻段 `0x43f79b..0x43f939` | `0x40bf70` 取目标后先 `0x40d4e0`（`0x43f7bf`）写 `[0x4c2c50]`／`[0x4c2c4c]` 为 (3,4) 或 (4,3)，再 `0x40c570(actor, 0x40dd60(), 0x40e1f0())`（`0x43f824`）；类别 2 → `0x40df70`（`0x43f873`，子状态 0x14），类别 1 → `0x40d340`（`0x43f8f6`，0xd）；`0x40d4e0` 另三个调用点 `0x43fa2a`／`0x43fb1c`／`0x43fdc9` 同样先于 `0x40c570` |

`0x40c480` 排除自身，原版无自身增益路径，所以 千羽風靈壁／激怒／精神統一（`range0Cell` 纯自身增益）原版 AI 不会施放（negative-evidence：`0x43ede0` 的 16 个 mode 中未见读取增益桶的自身路径）。

结果数字：绝技守方脚本解释器 `0x403954`（`cmp eax,0x23; ja` → 字节表 `0x404f48` → 指针表 `0x404ee8`）；命中 opcode `0x4047c7` 对每个目标清 `*0x4c6f74`／`*0x4c6f78`，调 `0x40b8f0`（＝`0x40aa80` channel 1），返回的 EXP 加进 `*0x4c13f0`（`0x40484d..0x404861`，只在攻方开场 `0x40438c` 清零）与 `*0x4c2c7c`，再记 HP 差与 MP 差（`0x404867..0x40489f`）；channel 1 下 `0x40aa80` 自己不生成数字。opcode 30 `aniShowHitResult`（`0x403ebd`）／35 NoWait（`0x403eb3`）汇合到 `0x404643`：HP 变化 >0 → `0x4084e0(x, y, v, 0, kind 0)`；<0 → kind 2；MP≠0 在同一点生成 kind 3、hold 0x28（`0x4046b0..0x4046d6`）；都为 0 且 `*0x4c13f0 == 0` → kind 5，非零则跳 `0x404772` 不显示。`0x4084e0` 生成对象 0xb1（`obj_ShowNumber`，`SHAPE\NUM100.SHP` 65 帧，planeMenu2），`0x45b6de` 写十进制到 +0x34；Heal 分支 `0x40ac10..0x40ac24` 直接 `0x4084e0(target.x, target.y-0x34, 实际回复, 0, 2, 0)`。`defProcShowNumber = 0x408580`：kind 0 NUM100..109 红（弹跳缩放）、1 NUM400..409 紫＋NUM511「EXP」、2 NUM200..209 绿、3 NUM300..309 蓝、4 NUM500..509 黄＋NUM512「$」、5 NUM513「MISS」、6 NUM514「LEVEL UP」（另放 `0x408b20(...,3)` 与声音 0x191）。偷到的东西在结算显示：`0x4416bc` 调 `0x442720`，case 0 EXP、case 2 `*0x4c2c84` 的「$」（StealGold 在 `0x40b556..0x40b574` 加进）、case 4 待领池开 [獲得物品窗](original_getitem_window.md)。

收片段：`0x403eb3`（opcode 35）置 `[esp+0x14]=0`、`0x403ebd`（opcode 30）置 1，`0x403ecc` 把守方 `+0x8c` 写成 0x62；Wait 路径 `0x404699`／`0x404671`／`0x404784`／`0x4046f0` 把本对象 `edi` 作 waiter 压给 `0x4084e0`，生成成功跳 `0x404980` 不加 phase（HP＋MP 同时变化时 HP 数字无 waiter、hold 0x28 的 MP 数字作 waiter）；NoWait 路径与 `*0x4c13f0 ≠ 0` 的空结果走 `0x404772`／`0x4046de` 立即 `inc word [edi+0x8c]`。数字放行与寿命见 [original_tick_counts](original_tick_counts.md) §6（kind 0：放行 27＋10×位数、删除 34＋10×位数）。资源：60 行 SPECIAL 守方脚本中 50 行以 aniShowHitResult 收尾、1 行（多段）用 NoWait、9 行不显示结果。

**resource-derived**

| 条目 | 内容 |
| --- | --- |
| 绝技脚本 | `content/generated/hsl/skills/special_effect_scripts.json`：每行 attack_code／defense_code 对应 EFFECTS.TXT 一个 `[effect]`；60 行引用 221 个 `obj_Special*`（planeEffect4 231／planeEffect3 29／planeEffect2 5 次）→ 535 个 SHP 成员、605 帧、59 个 WAV、24 个 `ani*` opcode（aniDelay 308、aniPlaySound 138、aniInsertObject 124、aniInsertRandomObject 93、…FixDelay 67、aniProcessHitMiss 55、aniShowHitResult 50、…Delay 48、aniPlayHitSound 43、aniInsertHitRandomObject 38、aniInsertSpecialBG 16、aniDoublePageMode 15，其余 12 个各 ≤11） |
| 素材 | `hsltools/assets/skill_effects.py` 导入 `content/imported/hsl/shared/skill_effects/`（495 PNG、59 WAV）；`obj_Special51_05` 在 OBJ-ALL.H 无定义（`unresolved_objects`）；闇瑩蝶舞 `obj_Special08_01…08` 各声明 9 个 shape 但 PAK 只有每十位 3 个，40 个成员无记录（`missing_members`，negative-evidence） |
| 数字颜色（`SHAPE\NUM1xx／2xx／3xx／513` 调色板） | kind 0 (255,238,238)／(255,182,180)／(255,125,123)；kind 2 (189,230,164)／(148,218,115)／(115,206,74)；kind 3 (189,226,246)／(131,206,238)；MISS 红 (255,97,98) 描边＋白；EXP 紫 (222,178,255) |
| 无人持有的源行 | 高級金之手 `special:magicOTHER:magicCode14`（别名 `金之手LV2`＝0x2000）、百裂突刺 `magicCode29`（0x10000000）、獅子吼 `magicCode32`（0x80000000）、吸血劍 `special:magicOTHER2:magicCode03`（OTHER2 位 0x4；059 的「吸血劍2」落在 special_other 掩码即 無想冥殺）：PLAYERS、学习表、来源模板都不引用 |
| 银之手 | 004 漢克斯 的 PLAYERS `special_other` 初始声明 |
| 结果字串 | 原文字表无偷窃／再行动／取消行动结果字串（negative-evidence）；原录像无这些绝技 |

## 重制接线

| 家族 | policy | 模块 |
| --- | --- | --- |
| 衰弱与净化 | — | `StatusEffectRules.WEAKEN`／`apply_weaken`／`cure_weaken`／`weakened_attributes`；`SupportMagicRules.CURE_BITS`；`ProgressionRules.refresh_growth_stats` 扣衰弱幅度；公式属性统一经 `weakened_attributes`（学习回滚与点数分配仍读基础字） |
| 状态（弱體箭／獸神怒號／影纏） | `native_special_status` | `SpecialStatusRules` → `StatusApplicationRules.resolve`，roller `PoisonArrowRules.roll` |
| 支援（萬息四技） | `native_special_support` | `SupportMagicRules`，HealMP 的 `rand(level)+1` 进 `immediate_contributions` |
| 增益（千羽風靈壁／激怒／精神統一、魔障壁） | `native_special_stat` | `StatMagicRules`、`StatEnhancementRules.resist_up`（打包字，`merge_resist_word` 累加封顶 20；`dispel` 只清 attack_up／defense_up） |
| 队列／吸取（天鳴覺醒／獅子吼／吸血劍／竊殺／金之手／銀之手） | `native_special_utility` | `SpecialUtilityRules`：ActiveAgain → `CoreTurnQueue.reactivate_consumed`＋`advance` 第二遍，CancelActive → `cancel_pending`；StealGold 按 `growth_profile.source.mode & 0x10000` 判侧别，封顶读 `BattleRewardRules.carried_gold`；StealItem 遇空槽 `break`、首槽为空时 `skill_has_no_effect`；`+0x196` 读 `combat_profile.steal_ratio`（缺失 `missing_steal_ratio`） |
| EXP | — | `ExperienceRules.record` 先按 `immediate_contributions` 逐项换算再做尾部换算；`experience_basis.points`／`tail_points`／`immediate_experience` |
| AI | — | `AISkillDecisionRules.buckets`／`select_index(rates, rng, channel, bucket)`（MAGIC 桶 5／7 `useful_accepts`）；`AISkillPlanning.choose`（special 与 magic 同走 `area_order(ai_magic_multi_first)`，`choose_any` 站位失败退另一桶）；`AISupportPlanning.choose`（增益分支一次 `rand(2)`）；`AISelfPreservation`；`AISupportRules.buff_useful` 含绝技增益掩码 |
| 偷窃加成字 | — | `equipment.initial_physical_fields` 写 `combat_profile.base_steal_ratio`／`steal_ratio`；`EquipmentRules.effect_delta` 求和；`JobUpRules.merge_source_template` 加模板原字 |
| 目标 | — | `SkillTargetRules.is_support` 用 mode3 掩码 `0x18f62` |
| 结果数字 | — | `game/battle/scene/ResultNumberFloater.gd`（kind 0／2／3／5；kind 2／3／5 层级 16 停 16 tick 后每 2 tick 减 1、第 46 tick 删除、每 2 tick 上 1 px；首位 x − 7×(位数−1)、间距 14）；出现点：普通特写 (320,200) 命中后 40 tick（`0x40424c`→`0x404290`），脚本 (320,180)，地图法术 (x, y−0x34)，道具 (x, y−0x30)，回合末 (x, y−48)；`BattleCombatCutin.shows_miss`／`show_result`；绝技片段收尾 `SkillEffectScriptPlayer.clip_complete_tick`＝编译时间线结束与结果数字删除（`ResultNumberFloater.life_of`）的较晚者，受击帧保持到片段结束；普通续击时上一镜存活数字挪进 `BattleCombatCutin.result_tail` 走完寿命；`BattleAftermath` 的「$」浮字加 `gold_effects`；结果行只剩无原字形的说明（增益、净化、未回復、武器效果，provisional） |
| 绝技脚本 | — | `game/battle/scene/SkillEffectScriptPlayer.gd` 实现 24 个 opcode，`compile(attack, defense, hit, seed, manifest)` 编 tick 时间线；`BattleCombatCutin._process_skill` 按 `presentation` 分流（script 58 行；毒魔箭、月花圓舞 走专属模块）；`game/sim/loop/BattleLoopRewards.gd` 把 `stolen_items` 并入待领池（`0x44f2d0`），StealGold 见 `0x40b4e8` |

脚本播放 provisional（manifest `policy`／`replacement_evidence`）：时钟 60 tick/s；aniInsertRandomObject／aniInsertHitRandomObject／…Disp 已按生成器 `0x401390` 的折叠偏移与累加延迟（每只比前一只晚 rand(delay)＋1）放置（static-derived，见 [original_objcomd_programs.md](original_objcomd_programs.md)「结论」），其余 Random 系列 delay 仍读作每实例 `rand(0..delay)`、FixDelay 读作 `base + i×delay`、range 为 ±range/2；Angle／RoundRandom／Tornado 的几何按参数名推读；守方底图压暗 0.45、双页攻方 (160,320)／守方 (480,320)、结果至少保留 40 tick（无数字的说明行的重制下限），有数字时保留到数字删除；混合模式默认加色。

## 复现

`python3 tools/hsl.py check special_effect_scripts`；`python3 tools/hsl.py check skill_effects`；偷窃加成字 `PYTHONPATH=tools python3 -m hsltools.probes.steal_ratio`；重制侧 `tools/godot.sh --headless --script tests/run_skill_effect_script_tests.gd` 与 `tests/run_ai_support_tests.gd`。绝技截图驱动已退役，截图为历史记录。

## 边界

- 除偷窃加成字外全部为反编译阅读，幅度、持续、贡献与原全局 RNG 顺序的等价未声明；衰弱施法者的 `0x40a7b0`／`0x409a60` 数值未做原执行。
- 对象寿命与舞台外对象的飞行：`defProcObjectMove`（`0x4051d0`）与 `obj_Data7` 选中的 objcomd.txt 命令程序已读，221 个对象经原指令逐 tick 执行写进 `objcomd_motion.json`，重制按它画（见 [original_objcomd_programs.md](original_objcomd_programs.md)「结论」）；种子变体与模式插入几何的剩余差异记在该包「边界」。
- `aniDelay` 计数器（`0x4022aa`）的调用频率未量。
- phase 0x63（放行后）的处理未逐条读，按"放行即续读脚本"推定；片段收尾的 16 tick 变暗（守方 phase 101 `0x404b23`）与随后变亮重制已照做，数字尾巴叠在变暗后的画面上走完再变亮（`SkillEffectScriptPlayer.clip_closing_tick`；变暗起点仍取 `RESULT_HOLD_TICKS` 暂代，见 [original_tick_counts.md](original_tick_counts.md) §9）；数字对象与守方对象同 tick 先后未读（±1 tick）。
- `*0x4c13f0` 在多目标施放中跨目标累积，重制按每目标 `experience_basis` 判定；功能绝技命中未生效时守方是否切受击帧未核。
- `0x4c6f74` 由哪些结算路径写入未全核。
- 自救净化的通道顺序（先 MAGIC 桶再 SPECIAL 桶再物品）是重制选择；AI 净化只以中毒触发。
- 桶 3／4 的退魔行重制仍按 `useful_ids` 预过滤加 use_ratio 抽签，未接原 0／200 改写。
- 魔障壁与第九波区域行（天地鳴動、怒濤地裂崩、魔燒焚燼、怒炎魔獄燋、烈蝕水彈、極零裂凍破、地靈聖護、赤炎波動、大地之癒、大地之惠、神怒）无专属特效素材，降级到通用表现。

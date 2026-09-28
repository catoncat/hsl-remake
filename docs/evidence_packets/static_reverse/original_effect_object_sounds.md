# 特效对象自带的声音：绝技对象的命令程序（objcomd.txt）与法术效果对象的程序音

> evidence: resource-derived: objcomd.txt／OBJCOMD.H／global.obs／effects.txt／PROCESS.DEF from hsl.pak; static-derived: object-process handlers and the mixer channel allocation read from hsl01.exe, sound cues recorded by native execution (objcomd_motion.json／effect_motion.json); provisional: untracked objects keep the static tables, the hit word before the first multi-hit strike and an MP-only last strike · status: live · functions: 0x4038a0, 0x403e9e, 0x4045a4, 0x4047af, 0x4051d0, 0x406d20, 0x406eb0, 0x409610, 0x409760, 0x409790, 0x40a5d0, 0x40b8f0, 0x415d40, 0x415d70, 0x415d90, 0x415dc0, 0x42c180, 0x42f164, 0x4593a0, 0x459b60, 0x45a390, 0x45e307, 0x45f5f7 · tools: hsltools/assets/skill_effects.py, hsltools/data/first_skill.py, hsltools/data/special_effect_scripts.py, hsltools/probes/effect_motion.py, hsltools/probes/objcomd_motion.py, run_skill_effect_script_tests.gd · updated: 2026-09-29

## 结论

- 原版绝技命中的落地声来自 defProcObjectMove 对象（`0x4051d0`）按 obj_Data7 执行的 objcomd.txt 命令程序（`objmPlaySound`／命中才响的 `objmPlayHitSound`），不在 EFFECTS.TXT 脚本里；法术效果对象（`0x415dc0`）出现时放 obj_X1，obj_Y1／obj_X2 由各 effProc 程序在自己的事件点经 `0x415d40`／`0x415d70`／`0x415d90` 播放（static-derived）。
- 两个原生探针逐 tick 执行这些程序时记下每次放声的帧与 WAV：`objcomd_motion.json` 每个 SPECIAL 对象的 `sounds` 是 `[帧, WAV, hit_only]`（命中局，`hit_only` 由调用返回地址 `0x4059f3` 判定），`effect_motion.json` 每棵效果树的 `sounds` 是 `[帧, WAV]`（含子对象），种子变体各有一份（static-derived）。重制 `game/battle/scene/SkillEffectScriptPlayer.gd` 的 `_insert_sounds` 按记录逐实例排声（插入 tick＋记录帧），帧未导入时声音照放。
- 混音通道：`0x42f164` 以 `0x459b60(9, 20, …)` 开 **9 个通道**；对象程序放声（`0x42c180` → `0x45a390`，flags 0）经 `0x4593a0` 取第一个空或已停的通道，全忙则丢掉新声，不截旧声、同名不合并（static-derived）。重制 `SOUND_VOICES = 9`，同一规则。
- 差异：没有轨迹的对象仍按静态表排声；角度环／龙卷等图案插入画面用重制几何，声音与 op 71／72 同样取记录；多段绝技命中才放的对象声按读字那一 tick 的段放（见 §边界）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 反汇编阅读，未执行原程序。

### 1. 根因：氣刃斬 命中那一声

**氣刃斬 命中那一声不在 EFFECTS.TXT 脚本里，而在命中火花对象自己的命令程序里；本包立项时重制没有读这些程序（命令程序的运动现已逐 tick 执行，见 [original_objcomd_programs.md](original_objcomd_programs.md) §结论）。**

- `effects.txt` 的 specCode02（守方脚本）没有 `aniPlaySound`／`aniPlayHitSound`：`aniDelay,20 → aniInsertObject obj_Special01_02 → aniDelay,10 → aniProcessHitMiss → aniInsertHitRandomObject obj_Special01_03 ×6 ／ obj_Special01_04 ×24 → aniDelay,60 → aniShowHitResult`（resource-derived）。
- `global.obs` 的 obj_Special01_03（obj_code 412）是 `obj_Process_Code = defProcObjectMove`、`obj_Data7 = 2 ; action code`（resource-derived）。
- `hsl.pak` 的 `data\objcomd.txt`（`#include OBJCOMD.H`）第 2 号 `[command]`：`objmPlaySound,WAV\BOMB0017.WAV` 然后 `objmProcNextShapeDelete,-1,-1`（resource-derived）。**这就是那一声**：每个火花对象出现时自己播 BOMB0017。
- 本包立项时重制 `SkillEffectScriptPlayer` 只解释 EFFECTS.TXT 的 ani*／eff* 指令，特殊对象当静帧画，对象程序里的声音一并丢失；现状：对象运动按 `objcomd_motion.json` 原生轨迹回放（[original_objcomd_programs.md](original_objcomd_programs.md) §重制接线），声音按同一次原生执行记下的时刻排（§4）。

### 2. 原版读法（static-derived）

| 地址 | 读法 |
| --- | --- |
| 过程表 `0x477c2c` slot 37 → `0x4051d0` | PROCESS.DEF `defProcObjectMove = 37`（resource-derived 名字）。init（`0x40522f..0x40523c`）：`程序 = [0x4c1b74][word +0xa4]`——对象 `+0xa4` 是模板 obj_Data7，即 objcomd.txt 的 `code`；首条若是 71（objmInitMultiHitData）先执行、若是 2（objmRandomDelay）化为出现前的延迟 |
| `0x42c180(id, flags)` → `0x45a390` | `[0x4c1af4]` 为 0（声卡未开）或 flags 位 0 为 0 且 `[0x477c20]`（音效开关）为 0 时不放；否则 `0x459a20` 取缓存号后调 `0x45a390(缓存, 0xff, flags)`。flags 位 1：先停同名通道再放；位 2：同名还在响就不放；**flags 0（对象程序的全部放声）不查同名**，直接 `0x4593a0` 取通道 |
| `0x4593a0` | 按序扫描 `[0x4c23e0]` 的 `[0x4c23d4]` 个通道（每个 0x24 字节）：空槽直接返回；槽里的 DirectSound 缓冲 GetStatus（vtable +0x24）成功且 `status & 5`（PLAYING／LOOPING）为 0 则 Release 后返回该号；全在响返回 −1，`0x45a44a` 放弃本次放声——**满了丢新声，不抢占** |
| `0x42f164` → `0x459b60(9, 20, "@:\\", "WAV\\", …)` | 初始化写 `[0x4c23d4] = 9`（通道数）、`[0x4c23cc] = 20`（缓存 WAV 数），即全局 9 个声部，所有经 `0x45a390` 的声音共用 |
| `0x405337..0x40537a` | 解释器：`+0x8e` 相位 ≤ 99 时从 `+0xa4` 取 32 位 opcode（0..0x4f），跳表 `0x406bc8` |
| op 51 `objmPlaySound` → `0x4059b7` | `0x42c180(id, 0)` 放声，`jmp 0x405df1` 继续取下一条（不让出） |
| op 52 `objmPlayHitSound` → `0x4059cf` | `[0x4c1418] < [0x4c6f58]` 时才放；`0x4c6f58` 由守方对象插入 `0x406eb0` 写入命中率（`0x406f81`），`0x4c1418` 是命中滚动（`aniProcessHitMiss` 置 0＝命中、未造成变化置 200）——即"命中才响" |
| op 1 `objmDelay` → `0x405e53` | `+0x8e = 1`、`+0xa0 = 计数`、保存指针并让出（与 aniDelay 同形） |
| op 71／72 `objmInitMultiHitData`／`objmSetMultiHitData` → `0x405d6d`／`0x405d76` | `0x4c6f6a++`／`0x4c6f6a--, 0x4c6f68++`，不让出；程序首字为 71 时由首帧 `0x40524d` 在插入延迟之前计数。`aniProcessHitMissMulti`（`0x403e9e`）让守方进相位 18（`0x4045a4`）：子态 0（`0x4047af`）每 tick 读双字 `0x4c6f68`，为零回脚本（`0x4047b8`），`0x4c6f68` 非零就减一结算一击（`0x4047d5`→`0x4047e9`），下一 tick 子态 1（`0x4045d5`）出该击数字，子态 3 再一 tick 复位，所以相邻两击至少隔 3 tick；最后一击（`0x4045fb` 读结算计数为 0）的数字以守方为 waiter，`0x404795`／`0x40473a` 见数字建成就不自增子态，等数字释放（`0x4088fa`）再走子态 3 → 0 → 回脚本，见 §边界「多段结算时刻」；计数由守方插入 `0x406ecc` 清零。探针记下每个对象的 op 71／72 帧（`objcomd_motion.json` `multi_hit`，19 个对象），重制守方脚本按记录逐击结算、片段随之变长；无 op 72 的绝技照旧按游标 |
| 逐击结算体 `0x4047e9..0x404986` | 每击先清 HP／MP 变化字 `0x4c6f74`／`0x4c6f78` 与命中判定 `[0x4c1418]`（`0x404803`），再调 `0x40b8f0`（→ `0x40aa80` channel1：自己的命中掷骰 `0x40a7b0`、伤害抽样、按当前 HP 封顶，`0x40b853` 调 `0x40a5d0` 换算经验并返回），返回值加进 `0x4c13f0`／`0x4c2c7c`（`0x40485d`／`0x40485f`），本击 HP／MP 差写回两变化字，`0x4048b3` 刷身份栏；三者全零改写 `[0x4c1418]=200`（`0x4048d6`）。与月花圓舞 的 `aniProcessHitMiss`（op 17）是同一结算体（[月花圓舞包](original_moon_dance.md)）。段数＝防守对象实例执行 op 72 的次数；9 行多段脚本里带 op 72 的对象都由不看命中的插入指令放出（命中趟只多子对象、主对象不变），所以段数与命中无关：慌雨斬 5、無想冥殺 8、星辰落牙破 6、殘影亂斬 7、百裂突刺 8、血之宴 12。重制 `MultiHitSpecialRules` 逐段结算（收据 `hit_segments`），`SkillEffectScriptPlayer.strike_spawns` 每段在自己的结果时刻出自己的数字 |
| op 52 的放声调用返回 `0x4059f3`，op 51 返回 `0x4059c7` | 探针据此给记录标 `hit_only`；同一比较（`0x405434`／`0x405495`）还管命中才抛的子对象（objmThrowHit*），命中局的轨迹另存 `hit_variants`（[对象命令程序包](original_objcomd_programs.md)「命中趟」），`variants` 仍是落空局 |
| 过程表 slot 28 → `0x415dc0` `defProcEffectProcess1` | 效果对象（obj_Effect_*）出现时（插入延迟 `+0xae` 数完）`0x415e1a..0x415e24` 放模板 `+0x10`＝obj_X1；随后 `+0x46 = +0x18`（obj_X2）、`+0x44 = +0x14`（obj_Y1），留给 effProc 程序在各自事件点经 `0x415d40`（放 `+0x44` 一次后清零）／`0x415d90`（放 `+0x46` 一次后清零）／`0x415d70`（放 `+0x44` 不清零）播放 |

附带读到的普攻受击音：
- 普通攻击的受击音不在 ANIMAL 程序里：守方对象 `0x4038a0` 相位 1 命中分支（`0x4040da..0x40414a`）先放 `[0x4c13f8]`（攻方 PLAYERS `sound_shoothit` 模板 `+0x22`，`0x406dc9` 写入），否则放受击方 `sound_hit`（模板 `+0x10`，`0x409790`），都没有才按 `[0x4c6f60]`（攻方武器 ITEM `+0xc` 图标类，只在 `0x406d20` mode 0＝普攻时写）放 `0x194..0x199`（sfxHitStaff／Sword／Bow／Axe／Spear／Dagger，跳表 `0x404f6c`：0→404、1→405、2→406、3→407、4→408、5→409，其它→405）。绝技的 `aniProcessHitMiss`（op 17，`0x4047e9..0x404980`）只结算伤害、刷身份栏、切受击帧，**不放声**——所以绝技命中声只能来自脚本 `aniPlayHitSound`（op 34 `0x403cb5`，同样 `0x4c1418 < +0xa6` 才放）或对象程序。重制 `BattlePresentation._present_impact` 对 `skill_name` 回执不放武器受击音，与此一致。PLAYERS `sound_hit`（4 行）与 `sound_shoothit`（1 行）重制仍未消费（[字段覆盖](original_field_coverage.md) 的 unconsumed 行），属普攻受击音的另一缺口。

### 3. 全部绝技的同类盘点（resource-derived，`hsl check special_effect_scripts` 从 tracked 源逐字节重算）

60 行绝技脚本引用的 221 个 defProcObjectMove 对象全部带 obj_Data7，全部落在 objcomd.txt 的 152 段命令里；其中 **39 个对象、24 行绝技**的命令程序含 `objmPlaySound`／`objmPlayHitSound`（被 objmThrow* 抛出的子对象的命令都不含声音）。`special_effect_scripts.json` 每个对象记 `command_code` 与 `command_sounds`（WAV、`hit_only`、前面 objmDelay 的 tick 和、前面无法计时的运动等待；下表是这张静态表，排程已改用 §4 的原生记录，静态表只留给无轨迹对象）；`skill_effects` 导入新增 7 个 WAV（BOMB0017／0019／0020／0025、HIT00004／00007／00012），manifest 共 118 个。

| 行 | 对象（command） | 声音（延迟 tick） | 计时 |
| --- | --- | --- | --- |
| 氣刃斬 ×2（OTHER／OTHER2） | Special01_03（2） | BOMB0017（0） | delays |
| 竊殺 | Special28_03（2） | BOMB0017（0） | delays |
| 神罰 | Special43_03（39）、43_04／43_06（2） | BOMB0017（0） | delays |
| 神怒 | Special45_01／45_03（2） | BOMB0017（0） | delays |
| 妖華紅蓮舞、壞滅咆哮襲、龍嘯天驅 ×2 | Special16_03／39_04／35_05（39） | BOMB0017（0） | delays |
| 連續突刺 ×2 | Special31_01（30）、55_01（138） | ATTACK17（0） | delays |
| 百裂突刺 ×2 | Special34_01（80）、54_01（133）；34_03（82）、54_03（135） | ATTACK17（0）；ATTACK17（0）＋命中 HIT00004（0） | HIT00004 provisional（objmWaitSpeedBelow） |
| 虛空無轉 | Special52_04／52_05（129） | ATTACK17（0） | delays |
| 血之宴 | Special50_01（110） | ATTACK17（0）＋命中 HIT00007（1） | delays |
| 闇瑩蝶舞 | Special08_09（127） | 命中 HIT00007（0） | delays |
| 慌雨斬 ×2 | Special04_02（49）、62_02（143）；04_03（50）、62_03（144） | 命中 BOMB0019（25）；命中 BOMB0020（25） | delays |
| 星辰落牙破 | Special24_02（75） | 命中 BOMB0005（14） | delays |
| 殘影亂斬 ×2 | Special30_01..04、56_01..04（79）；30_05、56_05（88） | 命中 BOMB0024＋BOMB0016（2）；命中 HIT00012＋BOMB0024（2） | delays |
| 獸神怒號 | Special42_01（59）、42_02（97） | UPGROUND02（0）、LASERUP004（0） | delays |
| 萬息臨界法 | Special17_06（59） | UPGROUND02（0） | delays |
| 無想冥殺 | Special06_06（124） | SHOOT008（2）＋命中 BOMB0025（3） | provisional（objmLoopCounter／objmRandomDelay／objmWaitRadiusBelow） |

专属模块的两行（毒魔箭、月花圓舞）的对象命令不含声音；法术 39 行全是 defProcEffectProcess1 对象，不走 objcomd。

### 6. 法术效果对象的 obj_Y1／obj_X2（static-derived 计数；部分 provisional）

`defProcEffectProcess1`（`0x415dc0`）起始时放 obj_X1（插入音，重制原已接）、把 obj_Y1／obj_X2 存进 `+0x44`／`+0x46`；之后 obj_Data9 选中的 effProc 程序（`+0xac`，跳表 `0x4231b0`，TYPE.H `effProc*` 编号）在自己的事件点经 `0x415d40`（放 `+0x44` 一次）、`0x415d70`（放 `+0x44` 不清零，可重复）、`0x415d90`（放 `+0x46` 一次）播放。39 行法术引用的 144 个效果对象里，**13 个（8 行法术）带 obj_Y1／obj_X2 WAV**，它们的 10 个程序全部有调用点。

每个程序是 `+0x8c` 相位机；下表「静态」列的 tick 从对象开始（插入延迟数完）算，按各相位的倒计数相加（对象模板 obj_Data4／obj_Data6 即对象 `+0x98`／`+0xa0`，`0x45dc5c` 装载），数据在 `hsltools/data/special_effect_scripts.py` 的 `EFFECT_PROGRAM_SOUNDS`，生成进 `objects.program_sounds`（只作无轨迹对象的后备）。「原生」列是 `effect_motion.json` 变体 0 记下的同一声（根对象，子对象的声音见 §4），排程用它。

| 程序（handler） | 对象（法术） | 相位读法 | 静态（tick） | 原生（tick） |
| --- | --- | --- | --- | --- |
| effProcFireArray（`0x421e1f`） | FireArray（怒炎魔獄燋） | 相 1→2 倒数 200→3 倒数 120→4 倒数 60→5：每 48 tick 一圈火并 `0x415d70`，共 3 次（`+0x92 = 3`） | EARTH0001 ×3（430／478／526） | 429／477／525 |
| effProcFireHead（`0x421cb3`） | FireBigHead（怒炎魔獄燋） | 相 1 数 obj_Data4＝160（`+0x98`）→ `0x415d40` | SHOOT006（161） | 160 |
| effProcMindBall（`0x418f7a`） | MindBall（封魔滅殺） | 相 1 数 40（`+0x92`）→ 相 2 环绕半径 48→2 px 每 tick 2 px（22）→ 放大到 1.125 即 `0x415d40` | BOMB0013（63） | 79（此后每约 9.5 tick 一声，共 8 声） |
| effProcMindBeast（`0x420c56`） | MindBeast（死骸腐靈獄） | 倒数 66／40／100（`+0x92`）→ `0x415d40` | UPGROUND04（207） | 206 |
| effProcWaterBeast（`0x418056`） | WaterBeast（水龍波） | 倒数 42（`+0x92`）／60（`+0x96`）→ `0x415d40` | WIND0004（103） | 101 |
| effProcUpBreakShape（`0x41c6d7`） | MindUBrkShp1..4（退魔） | 片 d＝obj_Data6 先等 8·d（`+0x34`），恰好数到 0 时 `0x415d90`（d＝0 的片不响）；再数 48（`+0xa2`）→ `0x415d40` 碎裂 | SHOOT004（9／17／25，片 2–4）；BOMB0014（48／56／64／72） | 8／16／24；64／71／79／87 |
| effProcOtherWord3（`0x42248c`） | OtherWord3（極） | 相 0 即 `0x415d90`；缩放 16→8（每 tick 0.5，16）→1（每 tick 0.234，30）、动画等待（`0x45e5a6`，未读，按 0）、倒数 40 → `0x415d40` | UPGROUND04（0）；WIND0004（87） | 0；88 |
| effProcOtherBig（`0x42270f`） | OtherBBall1（極） | 相 1 等 `0x43bf30(obj,0)`（未读，按 0），相 2 倒数 120 → `0x415d40` | SHOOT003（121） | 125 |
| effProcOtherGlass（`0x41f643`） | OtherGlass（魔障壁） | 相 1 倒数（起值来自相 0 的局部量，未读清，按 1）→ `0x415d90`；相 2 等一个形体延迟（24）→ 倒数 80 → `0x415d40` | UPGROUND02（2）；BOMB0014（106） | 1／8／16／24／32；105／112／120／128／136（5 片各一声） |
| effProcWaterBig（`0x41db97`） | WaterBig1（烈蝕水彈） | 相 1 倒数 80 → 相 2 每 16 tick 抛一子弹共 6（96）→ 相 3 倒数 40 恰到 0 时 `0x415d90` → 以 `0x45e80d`(步 8) 飞向相 0 算出的 200 px 外目标，到达 `0x415d40` | SHOOT002（217）；WATER008（242） | 96..176 每 16 tick 一声（6 颗子弹）＋238；257 |

### 4. 原生执行记录与静态表的差值（static-derived）

`python3 tools/hsl.py generate objcomd_motion effect_motion` 逐 tick 执行，放声都经 `0x42c180` 桩记下帧与 WAV。绝技对象（`objcomd_motion.json`，命中局变体 0；只列与静态表不同的行）：

| 对象（行） | 静态（tick） | 记录（tick） | 差值 |
| --- | --- | --- | --- |
| Special04_02／62_02（慌雨斬 ×2） | 命中 BOMB0019（25） | 27 | +2 |
| Special04_03／62_03（慌雨斬 ×2） | 命中 BOMB0020（25） | 27 | +2 |
| Special24_02（星辰落牙破） | 命中 BOMB0005（14） | 16 | +2 |
| Special30_01..05、56_01..05（殘影亂斬 ×2） | 命中两声（2） | 4 | +2 |
| Special50_01（血之宴） | 命中 HIT00007（1） | 2 | +1 |
| Special34_03／54_03（百裂突刺 ×2） | 命中 HIT00004（0，provisional） | 6／7／7／8（四个种子） | +6..+8 |
| Special06_06（無想冥殺） | SHOOT008（2）、命中 BOMB0025（3）（provisional） | 102／100／99／122、133／131／130／153 | 见 §边界 |

其余 22 个对象（0 tick 放 BOMB0017、ATTACK17、UPGROUND02、LASERUP004、HIT00007 的各行）记录与静态表一致。+1／+2 的规律：每个 objmDelay N 实占 N＋1 tick（计数减到 0 的那一次调用才继续）；慌雨斬／星辰落牙破／殘影亂斬 的声音前有两个 objmDelay，血之宴 一个。

效果对象（`effect_motion.json`）除 §6 的根对象差值外，子对象各自放 obj_X1——静态表整列漏掉：FireArray（LASERUP005 ×5、BOMB0004 约 15 声）、MindBall（8 声 BOMB0013）、MindBeast（约 31 声 BOMB0013）、OtherBBall1／2（BOMB0001 各 8 声）、WaterBeast（SHOOT002 约 22 声）、WaterBig1／2（SHOOT002、WATER002 各 6 声）、WaterBigBall（BOMB0007 ×12）、WaterBigIce（FIRE0002 ×8）、WaterDrop（WATER003）、EarthRoundBall／EarthUpBall（SPRAY0001）、EarthUpBrk（EARTH0004 ×6、WIND0004）。随机程序的声音随种子变化，重制随所画变体取。

## 重制接线

共享层在 `SkillEffectScriptPlayer._insert_sounds`（每次对象插入都经过它，与技能无关）：
- 有轨迹的绝技对象：`ObjcomdMotion.sounds(对象, 变体)` 每条在**该实例的插入 tick ＋记录帧**入时间线；`hit_only` 的只在命中（`hit`）时；每个实例各放一次（原版每个对象程序各自调用放声——百裂突刺 26 次突刺各一声 ATTACK17）。变体按同一对象的插入次序取，与 `_finish_timeline` 给轨迹分配变体的次序相同（图案插入不计）。
- 有轨迹的效果对象：`EffectObjectMotion.sounds(对象, 变体)`，含 obj_X1（每个实例在自己开始时放，不再"每条插入指令一次"）、obj_Y1／obj_X2 与全部子对象的声音。
- 角度环／龙卷等图案插入（`_insert_pattern` 传 `patterned`）：画面按图案几何，声音与 op 71／72 同样取记录（每个实例都跑程序）。
- 没有轨迹的对象：仍按 `command_sounds`（插入 tick＋objmDelay 和）、obj_X1（每条指令一次）与 `program_sounds`。
- 播放：`_play` 取第一个不在响的声部，9 个全在响就丢掉这一声（`0x4593a0`）。
- **先排声音再判能否画**：对象帧未导入（`missing_members`）或被跳过时声音照放——"素材未导入的降级路径"不再丢声。
- **缺演员切入图的降级路径**：切入表（`chapter01/combat_animation/manifest.json`）没有 022／029／102／103 的行；此前任何带这些演员的绝技都落到 `BattleCombatCutin._process_missing_ordinary_clip`（0.75 s 纯文字、无声）——022 是 44／45 关的友军、PLAYERS `special_other = 氣刃斬`。现 `SkillEffectScriptPlayer.needs_actor_art` 恒假，脚本照常演出（底图、对象、全部声音），缺行的演员由 `_stand` 隐去；`run_presentation_contract_tests.skill_effect_contracts` 守着。专属模块（毒魔箭／月花圓舞）仍要求两端切入图。
- 声部 `SOUND_VOICES = 9`（`0x459b60` 的通道数），满了丢新声（`0x4593a0`）。

氣刃斬 命中：守方脚本 tick 90..94 出现的 6 个 obj_Special01_03 各放一次 BOMB0017（与火花同一 tick；落空不插火花、不响）。

重制：效果阶段把记录的每一声排在对象开始 tick ＋记录帧（`run_skill_effect_script_tests.effect_program_sounds` 守"在片段内"）。例：烈蝕水彈 的 WaterBig1 在 tick 40 进场，136..216 每 16 tick 一声 SHOOT002（6 颗子弹）、278 再一声、297 放 WATER008；怒炎魔獄燋 的 FireArray 在 60 进场，489／537／585 三声地鸣，FireBigHead 540 进场、700 放 SHOOT006。

provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md`。

## 复现

`python3 tools/hsl.py check special_effect_scripts skill_effects first_skill objcomd_motion effect_motion`（重生成需原作与 unicorn：`python3 tools/hsl.py generate first_skill special_effect_scripts objcomd_motion effect_motion skill_effects`）。

## 边界

- **计时**：记录帧从对象创建起算（探针的帧模型见 [效果对象运动包](original_effect_motion.md) §帧模型与公共部分，±1 帧）；随机程序的声音是种子样本，原版所有实例共用一条随机流。
- **图案插入**：角度环／龙卷插入（`aniInsertAngleObject*`／`aniInsertTornadoObject`）重制按图案几何画、不用轨迹，声音与 op 71／72 取记录（每个实例都跑程序）。無想冥殺 的 Special06_06 环：程序自设半径 170 px（`objmSetRoundPos`），8 个实例在插入后 128..151 帧各执行一次 op 72，守方脚本的 `aniProcessHitMissMulti` 等到这 8 击结算完（种子 7：458..484），SHOOT008／BOMB0025 落在 429..483，片段收场 584 之内。
- **命中才抛的子对象**：`objmThrowHit*`（`0x405434`／`0x405495`）只在命中时抛出（慌雨斬、星辰落牙破、殘影亂斬、無想冥殺 的火花）；命中局轨迹另存 `hit_variants`，重制按该击结算的命中／落空选趟画。多段绝技里抛子对象与 objmPlayHitSound（`0x4059cf`）都在程序第一个命中声那一帧读 `[0x4c1418]`＜`[0x4c6f58]`（objcomd code 79：op 72、objmDelay 1、抛子对象、放声，探针记录里命中声都在 op 72 后 2 帧，百裂突刺 的 HIT00004 在 op 72 前）；读到的是该 tick 及以前最后结算的一段（static-derived，见下条「多段结算时刻」），重制的火花趟与命中对象声都按这一段（`SkillEffectScriptPlayer.strike_word_hit`）。首段结算前字里是整次的掷骰，重制取整次命中（provisional）。
- **叠声**：原版 9 个通道全局共用（脚本 aniPlaySound、界面音效也经 `0x45a390`）；重制的 9 个声部只给特效播放器自己的声音，其它声音走各自的播放器、不占这 9 个。
- **多段结算时刻**（static-derived）：帧循环 `0x45f5f7` 按 plane 升序、每条链按建立序（`0x45e307` 挂链尾，第 4 参非 0 才挂链头）调对象过程；守方对象 155 Animal_Defense 在 planeEffect3（46），多段对象在 planeEffect4（47，Special50_01 在 46 但建立晚于守方），数字对象 177 Show_Number 在 planeMenu2（51）（PROCESS.DEF 与 global.obs 取值）。所以 tick t 执行的 op 72 在 t+1 的检查计数、守方结算改写 `[0x4c1418]` 先于同一 tick 的对象读字、数字释放 waiter 后守方下一 tick 才见子态 3。末击后回脚本：红字（kind 0）在建成后 27＋10×位数 tick 释放，绿字／MISS（kind 2／5，`0x4086ea`）32＋1 tick；两个变化字都为零且本页经验 `[0x4c13f0]`（`0x40485d` 累加、`0x40438c` 清）非零时不出数字（`0x404772`），仍按 3 tick；从末击检查到回脚本的检查是 1＋释放＋2 tick（`SkillEffectScriptPlayer._last_strike_ticks`）。子态 1 的出数判据只读两个变化字（`0x404611`–`0x404622`，不看命中字）：都为零且不是末击（`0x4045fb` 读双字 `0x4c6f68` 非零，`[esp+0x14]` 不置 1）时 `0x404630` 不建数字、直接进子态 3，下一次检查仍在 3 tick 后；末击无变化出 MISS（kind 5，`0x404664`），经验非零时照上不出。重制 `SkillEffectScriptPlayer.strike_spawns` 照此：非末段无伤害不出数字，末段无伤害出 MISS、整次经验非零时不出。只改 MP 的末击出 kind 3 数字，收据不带 MP 变化，重制按 3 tick（provisional）。
- **不支持的结论**：不证明音量、声像、叠声的混音与原版一致。
- 效果对象的画面按原生 effProc 轨迹运动（[效果对象运动包](original_effect_motion.md)），声音与画面来自同一次执行。

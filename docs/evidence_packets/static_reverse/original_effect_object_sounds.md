# 特效对象自带的声音：绝技对象的命令程序（objcomd.txt）与法术效果对象的程序音

> evidence: resource-derived: objcomd.txt／OBJCOMD.H／global.obs／effects.txt／PROCESS.DEF from hsl.pak; static-derived: object-process handlers read from hsl01.exe; provisional: rows marked provisional · status: live · functions: 0x4038a0, 0x4051d0, 0x406d20, 0x406eb0, 0x409610, 0x409760, 0x409790, 0x415d40, 0x415d70, 0x415d90, 0x415dc0, 0x42c180 · tools: hsltools/assets/skill_effects.py, hsltools/data/first_skill.py, hsltools/data/special_effect_scripts.py, run_skill_effect_script_tests.gd · updated: 2026-09-27

## 结论

- 原版绝技命中的落地声来自 defProcObjectMove 对象（`0x4051d0`）按 obj_Data7 执行的 objcomd.txt 命令程序（`objmPlaySound`／命中才响的 `objmPlayHitSound`），不在 EFFECTS.TXT 脚本里；法术效果对象（`0x415dc0`）出现时放 obj_X1，obj_Y1／obj_X2 由各 effProc 程序在自己的事件点经 `0x415d40`／`0x415d70`／`0x415d90` 播放（static-derived）。
- 重制 `game/battle/scene/SkillEffectScriptPlayer.gd` 的 `_insert_sounds` 按 `special_effect_scripts.json` 的 `command_sounds`（39 个对象、24 行绝技）与 `program_sounds`（13 个效果对象、8 行法术）逐实例排声，帧未导入时声音照放（resource-derived）。
- 差异：运动等待按 0 计的几声、8 声部与叠声通道是重制读法（provisional，表中逐行标注）。

## 证据

EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，r2 反汇编阅读，未执行原程序。

### 1. 根因：氣刃斬 命中那一声

**氣刃斬 命中那一声不在 EFFECTS.TXT 脚本里，而在命中火花对象自己的命令程序里；重制从未读过这些程序。**

- `effects.txt` 的 specCode02（守方脚本）没有 `aniPlaySound`／`aniPlayHitSound`：`aniDelay,20 → aniInsertObject obj_Special01_02 → aniDelay,10 → aniProcessHitMiss → aniInsertHitRandomObject obj_Special01_03 ×6 ／ obj_Special01_04 ×24 → aniDelay,60 → aniShowHitResult`（resource-derived）。
- `global.obs` 的 obj_Special01_03（obj_code 412）是 `obj_Process_Code = defProcObjectMove`、`obj_Data7 = 2 ; action code`（resource-derived）。
- `hsl.pak` 的 `data\objcomd.txt`（`#include OBJCOMD.H`）第 2 号 `[command]`：`objmPlaySound,WAV\BOMB0017.WAV` 然后 `objmProcNextShapeDelete,-1,-1`（resource-derived）。**这就是那一声**：每个火花对象出现时自己播 BOMB0017。
- 重制 `SkillEffectScriptPlayer` 只解释 EFFECTS.TXT 的 ani*／eff* 指令，特殊对象当静帧画（`defProcObjectMove motion is not restored`），所以对象程序里的声音一并丢失。

### 2. 原版读法（static-derived）

| 地址 | 读法 |
| --- | --- |
| 过程表 `0x477c2c` slot 37 → `0x4051d0` | PROCESS.DEF `defProcObjectMove = 37`（resource-derived 名字）。init（`0x40522f..0x40523c`）：`程序 = [0x4c1b74][word +0xa4]`——对象 `+0xa4` 是模板 obj_Data7，即 objcomd.txt 的 `code`；首条若是 71（objmInitMultiHitData）先执行、若是 2（objmRandomDelay）化为出现前的延迟 |
| `0x405337..0x40537a` | 解释器：`+0x8e` 相位 ≤ 99 时从 `+0xa4` 取 32 位 opcode（0..0x4f），跳表 `0x406bc8` |
| op 51 `objmPlaySound` → `0x4059b7` | `0x42c180(id, 0)` 放声，`jmp 0x405df1` 继续取下一条（不让出） |
| op 52 `objmPlayHitSound` → `0x4059cf` | `[0x4c1418] < [0x4c6f58]` 时才放；`0x4c6f58` 由守方对象插入 `0x406eb0` 写入命中率（`0x406f81`），`0x4c1418` 是命中滚动（`aniProcessHitMiss` 置 0＝命中、未造成变化置 200）——即"命中才响" |
| op 1 `objmDelay` → `0x405e53` | `+0x8e = 1`、`+0xa0 = 计数`、保存指针并让出（与 aniDelay 同形） |
| op 71／72 `objmInitMultiHitData`／`objmSetMultiHitData` → `0x405d6d`／`0x405d76` | `0x4c6f6a++`／`0x4c6f6a--, 0x4c6f68++`，不让出；`aniProcessHitMissMulti`（`0x4047c7`）等 `0x4c6f68` 非零才结算一击——多段绝技的结算时刻由对象程序驱动（重制仍按脚本游标结算） |
| 过程表 slot 28 → `0x415dc0` `defProcEffectProcess1` | 效果对象（obj_Effect_*）出现时（插入延迟 `+0xae` 数完）`0x415e1a..0x415e24` 放模板 `+0x10`＝obj_X1；随后 `+0x46 = +0x18`（obj_X2）、`+0x44 = +0x14`（obj_Y1），留给 effProc 程序在各自事件点经 `0x415d40`（放 `+0x44` 一次后清零）／`0x415d90`（放 `+0x46` 一次后清零）／`0x415d70`（放 `+0x44` 不清零）播放 |

附带读到的普攻受击音：
- 普通攻击的受击音不在 ANIMAL 程序里：守方对象 `0x4038a0` 相位 1 命中分支（`0x4040da..0x40414a`）先放 `[0x4c13f8]`（攻方 PLAYERS `sound_shoothit` 模板 `+0x22`，`0x406dc9` 写入），否则放受击方 `sound_hit`（模板 `+0x10`，`0x409790`），都没有才按 `[0x4c6f60]`（攻方武器 ITEM `+0xc` 图标类，只在 `0x406d20` mode 0＝普攻时写）放 `0x194..0x199`（sfxHitStaff／Sword／Bow／Axe／Spear／Dagger，跳表 `0x404f6c`：0→404、1→405、2→406、3→407、4→408、5→409，其它→405）。绝技的 `aniProcessHitMiss`（op 17，`0x4047e9..0x404980`）只结算伤害、刷身份栏、切受击帧，**不放声**——所以绝技命中声只能来自脚本 `aniPlayHitSound`（op 34 `0x403cb5`，同样 `0x4c1418 < +0xa6` 才放）或对象程序。重制 `BattlePresentation._present_impact` 对 `skill_name` 回执不放武器受击音，与此一致。PLAYERS `sound_hit`（4 行）与 `sound_shoothit`（1 行）重制仍未消费（[字段覆盖](original_field_coverage.md) 的 unconsumed 行），属普攻受击音的另一缺口。

### 3. 全部绝技的同类盘点（resource-derived，`hsl check special_effect_scripts` 从 tracked 源逐字节重算）

60 行绝技脚本引用的 221 个 defProcObjectMove 对象全部带 obj_Data7，全部落在 objcomd.txt 的 152 段命令里；其中 **39 个对象、24 行绝技**的命令程序含 `objmPlaySound`／`objmPlayHitSound`（被 objmThrow* 抛出的子对象的命令都不含声音）。`special_effect_scripts.json` 每个对象记 `command_code` 与 `command_sounds`（WAV、`hit_only`、前面 objmDelay 的 tick 和、前面无法计时的运动等待）；`skill_effects` 导入新增 7 个 WAV（BOMB0017／0019／0020／0025、HIT00004／00007／00012），manifest 共 118 个。

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

每个程序是 `+0x8c` 相位机；下表的 tick 从对象开始（插入延迟数完）算，按各相位的倒计数相加（对象模板 obj_Data4／obj_Data6 即对象 `+0x98`／`+0xa0`，`0x45dc5c` 装载）。`counts`＝前面每一相都是固定倒数（±1 tick）；`provisional`＝前面某相等运动或动画（重制不跑），按注明的估计计。数据在 `hsltools/data/special_effect_scripts.py` 的 `EFFECT_PROGRAM_SOUNDS`（每项注释写相位），生成进 `objects.program_sounds`。

| 程序（handler） | 对象（法术） | 相位读法 | 声音（tick） | 计时 |
| --- | --- | --- | --- | --- |
| effProcFireArray（`0x421e1f`） | FireArray（怒炎魔獄燋） | 相 1→2 倒数 200→3 倒数 120→4 倒数 60→5：每 48 tick 一圈火并 `0x415d70`，共 3 次（`+0x92 = 3`） | EARTH0001 ×3（430／478／526） | counts |
| effProcFireHead（`0x421cb3`） | FireBigHead（怒炎魔獄燋） | 相 1 数 obj_Data4＝160（`+0x98`）→ `0x415d40` | SHOOT006（161） | counts |
| effProcMindBall（`0x418f7a`） | MindBall（封魔滅殺） | 相 1 数 40（`+0x92`）→ 相 2 环绕半径 48→2 px 每 tick 2 px（22）→ 放大到 1.125 即 `0x415d40` | BOMB0013（63） | counts |
| effProcMindBeast（`0x420c56`） | MindBeast（死骸腐靈獄） | 倒数 66／40／100（`+0x92`）→ `0x415d40` | UPGROUND04（207） | counts |
| effProcWaterBeast（`0x418056`） | WaterBeast（水龍波） | 倒数 42（`+0x92`）／60（`+0x96`）→ `0x415d40` | WIND0004（103） | counts |
| effProcUpBreakShape（`0x41c6d7`） | MindUBrkShp1..4（退魔） | 片 d＝obj_Data6 先等 8·d（`+0x34`），恰好数到 0 时 `0x415d90`（d＝0 的片不响）；再数 48（`+0xa2`）→ `0x415d40` 碎裂 | SHOOT004（9／17／25，片 2–4）；BOMB0014（48／56／64／72） | counts |
| effProcOtherWord3（`0x42248c`） | OtherWord3（極） | 相 0 即 `0x415d90`；缩放 16→8（每 tick 0.5，16）→1（每 tick 0.234，30）、动画等待（`0x45e5a6`，未读，按 0）、倒数 40 → `0x415d40` | UPGROUND04（0）；WIND0004（87） | X2 counts；Y1 provisional |
| effProcOtherBig（`0x42270f`） | OtherBBall1（極） | 相 1 等 `0x43bf30(obj,0)`（未读，按 0），相 2 倒数 120 → `0x415d40` | SHOOT003（121） | provisional |
| effProcOtherGlass（`0x41f643`） | OtherGlass（魔障壁） | 相 1 倒数（起值来自相 0 的局部量，未读清，按 1）→ `0x415d90`；相 2 等一个形体延迟（24）→ 倒数 80 → `0x415d40` | UPGROUND02（2）；BOMB0014（106） | provisional |
| effProcWaterBig（`0x41db97`） | WaterBig1（烈蝕水彈） | 相 1 倒数 80 → 相 2 每 16 tick 抛一子弹共 6（96）→ 相 3 倒数 40 恰到 0 时 `0x415d90` → 以 `0x45e80d`(步 8) 飞向相 0 算出的 200 px 外目标，到达 `0x415d40` | SHOOT002（217）；WATER008（242，飞行 ≈25 按估计） | provisional |

## 重制接线

共享层在 `SkillEffectScriptPlayer._insert_sounds`（每次对象插入都经过它，与技能无关）：
- 绝技对象：`command_sounds` 每条在**该实例自己的插入 tick ＋ objmDelay 和**入时间线；`objmPlayHitSound` 只在命中（`hit`）时；每个实例各放一次（原版每个对象程序各自调用放声——百裂突刺 26 次突刺各一声 ATTACK17）。
- 效果对象：obj_X1 仍按原有约定每条插入指令放一次（在指令游标）。
- **先排声音再判能否画**：对象帧未导入（`missing_members`）或被跳过时声音照放——"素材未导入的降级路径"不再丢声。
- **缺演员切入图的降级路径**：切入表（`chapter01/combat_animation/manifest.json`）没有 022／029／102／103 的行；此前任何带这些演员的绝技都落到 `BattleCombatCutin._process_missing_ordinary_clip`（0.75 s 纯文字、无声）——022 是 44／45 关的友军、PLAYERS `special_other = 氣刃斬`。现 `SkillEffectScriptPlayer.needs_actor_art` 恒假，脚本照常演出（底图、对象、全部声音），缺行的演员由 `_stand` 隐去；`run_presentation_contract_tests.skill_effect_contracts` 守着。专属模块（毒魔箭／月花圓舞）仍要求两端切入图。
- 声部从 4 增到 `SOUND_VOICES = 8`（remake-invented：原混音器通道数未读），最老的先被截。

氣刃斬 命中：守方脚本 tick 90..94 出现的 6 个 obj_Special01_03 各放一次 BOMB0017（与火花同一 tick；落空不插火花、不响）。

重制：`SkillEffectScriptPlayer._insert_sounds` 在效果阶段把每条 `program_sounds` 排在对象开始 tick ＋延迟（同 WAV 同 tick 一条）；全部 13 个对象都经 `effInsertObject` 单插，声音都落在各自脚本的等待之内（`run_skill_effect_script_tests.effect_program_sounds` 守"在片段内"）。例：烈蝕水彈 的 WaterBig1 在 tick 40 进场，257 放 SHOOT002、282 放 WATER008；怒炎魔獄燋 的 FireArray 在 60 进场，490／538／586 三声地鸣，FireBigHead 540 进场、701 放 SHOOT006。

provenance 写法：`static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md`。

## 复现

`python3 tools/hsl.py check special_effect_scripts skill_effects first_skill`（重生成需原作：`python3 tools/hsl.py generate first_skill special_effect_scripts skill_effects`）。

## 边界

- **计时**：objmDelay 按重制 aniDelay 同一约定（N tick）；程序在插入当 tick 开始（`0x405294` 之后同一次调用进入解释器，未逐 tick 验证 ±1）。运动等待（`objmWaitSpeedBelow`／`objmWaitRadiusBelow`／`objmLoopCounter`／`objmRandomDelay` 的随机部分）重制不跑对象运动，按 0 计——涉及 百裂突刺 的 HIT00004 与 無想冥殺 两声。替换证据：`0x4051d0` 运动相位（速度／半径积分）的 tick 读法，或原作单场录像的音画对照。
- **叠声**：原版同 tick 多实例是否各占一个通道（`0x45a390` flags 0 走 `0x4593a0` 分配通道，未读完）；重制每实例一条、8 声部轮转。
- **不支持的结论**：不证明音量、声像、叠声的混音与原版一致；不证明多段绝技 `aniProcessHitMissMulti` 的结算时刻（重制仍按脚本游标）。
- provisional 的替换证据：OtherWord3 的 `0x45e5a6` 动画结束条件、OtherBig 的 `0x43bf30`、OtherGlass 相 0 的倒数起值、WaterBig 相 2 结束与相 3 飞行的逐 tick 读（或原作单场法术录像的音画对照）。效果对象的画面按原生 effProc 轨迹运动（[效果对象运动包](original_effect_motion.md)）；原指令执行记下的声音与本表的差异见该包「声音」一节，排程未切换。

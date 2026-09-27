# 绝技通道的元素抗性（0x40a7b0 channel 1 / proc 0）

> evidence: static-derived · status: live · functions: 0x409be0, 0x40a7b0, 0x40aa80 · tools: hsltools/probes/special_damage.py · updated: 2026-09-27

Checked: 2026-09-20。接续 [普通交锋、武器附加与氣刃斬](original_ordinary_special.md)。该包只回答一个问题：非 magicOTHER 的绝技（SPECIAL type 0..4）是否乘目标元素抗性、是否读魔击力。机器证据仍是 [original_special_damage.json](original_special_damage.json)（探针 [hsltools/probes/special_damage.py](../../../tools/hsltools/probes/special_damage.py)，本次新增 8 组元素行，全部原指令正常返回）。

## 静态读法（static-derived）

原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。`0x40aa80`（技能 HP／状态应用）在 function bit 1（`magicFun_Attack`）下调用 `0x40a7b0(actor, target, record, &bonus, proc=0, channel)`，channel 1 = SPECIAL。`0x40a7b0` 内：

1. channel 1 的命中只读 `record+0x1c`（hit_ratio）＋累计补偿；不加 `actor+0xd4`（魔法命中装备）。
2. 伤害项＝三角取值＋rand(level×180/100)＋rand(level×150/100)＋con/8＋mind/4＋dex/3，再乘 `record+0x2c`（attackpow_ratio）/100；**不读 `actor+0xd0`（魔击力）**，那是 channel 0 的乘数。
3. 低值折算（<3）后，只要 `proc & 1 == 0`（攻击 proc 为 0），**两个 channel 都进入同一个 `switch(record+4)`（技能 type）**：case 0..4 取 `target+0x104+type*4`（resist_by_type），非零时夹到 80 再乘 `(100−r)/100`；**default（type 5 = magicOTHER）直接跳到 `0x40aa64` 返回**，不乘任何抗性。
4. 物理防御（`target+0xb4`）在该函数任何分支都不出现。

结论：氣刃斬（magicOTHER）"防御／抗性／魔法命中装备不进入数值"仍成立；天雷猛襲劍（magicAIR）等元素绝技则乘目标对应元素抗性（上限 80），其余项与氣刃斬相同。

## 原指令执行（8 组新增元素行）

固定 seed 7、level 20／dex 30／mind 20／con 28、36..54／98／100 的探针模板，仅改 `record+4` 与目标五个抗性槽：

| element | resistance | native value | 说明 |
| --- | --- | --- | --- |
| 2 | 0 | 101 | 抗性 0 时跳过乘法 |
| 2 | 40 | 60 | 101×60/100 |
| 2 | 80 | 20 | 101×20/100 |
| 2 | 100 | 20 | 夹到 80 |
| 3 | 25 | 75 | magicFIRE 走同一 switch |
| 0 | 80 | 20 | magicEARTH |
| 4 | 40 | 60 | magicMIND |
| 5 | 80 | 101 | magicOTHER 不乘（对照） |

随机调用顺序与氣刃斬行一致（100／10／10／36／30），抗性乘法不消耗随机数。

## 重制接入

`SpecialDamageRules.prepare` 按 SPECIAL type 读目标 `resist_by_type[element]`（type 5 固定 0，不读槽位），缺失或超过 80 明确返回 `missing_skill_resistance`，不为缺数据留默认值；`roll` 在低值折算后按 `(100−min(80,r))×value/100` 缩减。`run_ordinary_special_tests` 逐行回放 28 组原随机值；元素行进入同一断言。

## 同一 switch 的 magicOTHER 魔法（滅／裁）

channel 0（MAGIC）在 `proc & 1 == 0` 时走完全相同的 `switch(record+4)`：type 5 的 滅（`magic:magicOTHER:magicCode01`，30..40／96／19MP／range2CellCircle→range0Cell）与 裁（`magicCode02`，50..70／96／37MP／range3CellCircle→range1Cell）同样落到 default，**不读任何 resist_by_type 槽**；命中项仍加 `actor+0xd4`（魔法命中装备），伤害项仍是 `(clamp(level,1,80)+mind 折算+三角取值)×魔击力/100`。重制用 `OtherMagicRules.prepare` 产出与 `StatusApplicationRules.prepare` 同形的 roll_input（resistance 固定 0＝switch default，不是缺数据默认值），结算沿 `StatusApplicationRules.resolve`／`NativeMagicRollRules.roll`。这与 [普通交锋](original_ordinary_special.md) 里"武器附加类型 5 不乘元素抗性"是两个不同函数（`0x409be0` vs `0x40a7b0`）里各自的读法，此处独立核对。

同为 magicFun_Attack 的 逆風裂空／天滅崩雷破（`effect_proc=eff_proc_Global`）在数值上与 風刃 完全相同（type 2 读风抗性）；`effect_proc` 只影响原演出（全屏 vs 落点），重制的 cutin 对没有导入特效素材的 magic_key 一律降级到风刃帧（provisional 表现，不新做特效）。

## 敌方「2」版本与 magicOTHER2（type 6）的 switch 上界

Checked: 2026-09-20（static-derived）。SPECIAL.TXT 的敌方独立行（`; enemy` 注释：碎岩擊2 `special:magicEARTH:magicCode05`、排山倒海2 `magicEARTH:magicCode04`、流星降2 `magicAIR:magicCode06`、慌雨斬2 `magicWATER:magicCode05`、連續突刺2 `magicOTHER:magicCode30`、殘影亂斬2 `magicOTHER:magicCode31`）与 `; ----------- Other 2 -----------` 段（氣刃斬2 `special:magicOTHER2:magicCode01`、龍嘯天驅2 `magicOTHER2:magicCode02`）在 mag-spc.h 里各有独立位（别名 = 本尊名 + `2`），RESOURCE 名字资源与本尊相同（296／298／294／293／288／297／290／291），因此只能用 id 区分。`TYPE.H` 定义 `magicOTHER2 6`。

`0x40a7b0` 的 type switch 入口原指令：

```text
0x0040a9f0  mov eax, dword [edx + 4]        ; record->type
0x0040a9f3  cmp eax, 4
0x0040a9f6  ja  0x40aa64                    ; 无符号 >4 → 直接返回，不乘抗性
0x0040a9f8  jmp dword [eax*4 + 0x40aa6c]    ; 5 项跳表：+0x104..+0x114
```

结论：type 5（magicOTHER）与 type 6（magicOTHER2）同样落在 `ja` 分支，不读任何 `resist_by_type` 槽；其余项（hit_ratio＋补偿、三角取值＋level／con／mind／dex 项、attackpow_ratio）与本尊行相同，只是行内数值不同。重制 `SpecialDamageRules.ELEMENTS` 新增 `magicOTHER2 → "6"`，与 `"5"` 同列 `NO_RESIST_ELEMENTS`（resistance 固定 0 是 switch 上界读法，不是缺数据默认）。未做 type 6 的原指令探针：`ja` 的无符号比较对 6 与 5 走同一条路径，不需要额外执行证据。

## 边界

- 探针使用合成正域角色数据，不断言原完整初始化、全局 RNG 身份或演出。
- 抗性槽 `+0x104..+0x114` 的来源填充（装备／职业刷新）沿既有 profile 合同，本包不重推。
- 滅／裁 与两条 Global 风魔法未做原指令探针（channel 0 的 type 5 分支只有指令读法；探针 `hsl_native_status_probe`／`original_status_rolls.json` 的 type 0..4 行是既有覆盖）。
- `effCode35／36／18／19` 的原特效、`obj_Effect_OtherWord` 施法者演出与 eff_proc_Global 全屏演出均未恢复。

## 复现

`python3 tools/hsl.py check special_damage`；重制侧 `tools/godot.sh --headless --script tests/run_ordinary_special_tests.gd`。

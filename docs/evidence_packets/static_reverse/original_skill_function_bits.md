# 技能功能位：衰弱、净化、回魔、绝技通道与再行动／取消／吸取

> evidence: static-derived; provisional · status: live · functions: 0x406fe0, 0x4074a0, 0x407550, 0x4075a0, 0x409a60, 0x409be0, 0x40a5d0, 0x40a7b0, 0x40aa80, 0x40b910, 0x40c480, 0x40c570, 0x40c620, 0x40c770, 0x40d340, 0x40d4e0, 0x40dc50, 0x40dc70, 0x40dcf0, 0x40dd80, 0x40df70, 0x40e0e0, 0x40e100, 0x40e180, 0x40e2f0, 0x40e6c0, 0x42c780, 0x4348f0, 0x436e80, 0x448420, 0x448840, 0x44f2d0, 0x44f580 · tools: hsltools/assets/skill_effects.py, hsltools/data/skill_book.py, hsltools/probes/steal_ratio.py, run_ai_support_tests.gd, run_skill_effect_script_tests.gd · updated: 2026-09-23

2026-09-20。第七波技能覆盖 lane A 的静态读法。全部结论为 `static-derived`（r2ghidra 反编译阅读，未做有界原指令执行），数值幅度与原随机流等价性未经原探针复核处标 `provisional`。接续 [中毒／禁魔施加](original_status_application.md)、[回复／驱毒](original_support_magic.md)、[攻防增益](original_stat_magic.md)、[毒魔箭](original_poison_arrow.md) 与 [白光之翼](original_extra_action.md)。

## 结算主函数 `0x40aa80` 的功能位分派

`0x40aa80(caster_obj, target_obj, table_index, code, channel)` 先按 channel（0=MAGIC.TXT／1=SPECIAL.TXT）取技能行，再按 function mask 逐位访问；每位调用同一数值 helper `0x40a7b0(caster, target, row, &compensation, proc, channel)`。下表为本包新读出的位（既有位见前包）：

| 位 | 名称 | 原分支 | 重制落点 |
| --- | --- | --- | --- |
| `0x1000` | Weaken | 免疫 `0x40e2f0(target, 0x2000000)`；proc6 成功抽签；`rand(2)+2` 回合累加到 `+0x38`（封顶 9）；flag `|= 8`；贡献 `turns*7`；proc0 取幅度，若同行含 Attack 位则 `*30/100`；折叠 `>15 → 13..15`、`<2 → 2..3`；与旧幅度 `max(old,(old+new)/2)` 合并进 `+0x3a`；随后 `0x448840` 刷新 | `StatusEffectRules.WEAKEN`／`apply_weaken`／`weaken_strength`；`StatusApplicationRules` 的 weaken 分支＋刷新 |
| `0x2000` | CureWeaken | 仅当 flag&8：清 `+0x38` 整字、清 flag 8、`0x448840` 刷新；贡献 `(turns+1)*12` | `StatusEffectRules.cure_weaken`（刷新由 SupportMagicRules 结算） |
| `0x200`／`0x400`／`0x800` | CureParalysis／CurePoison／CureNoMagic | 各自只看对应 flag（4／1／2），清 `+0x3c`／`+0x30`／`+0x34` 整字并清位；不刷新；贡献 `(turns+1)*12` | 聖靈祝福／萬息秘孔術 的四净化掩码为 `0x2e00`；`SupportMagicRules.CURE_BITS` 按原访问顺序（0x2000→0x200→0x400→0x800）处理 |
| `0x8000` | HealMP | proc1 取值；`+0xe0`(MP) 加到 `+0xe4`(上限) 封顶；若实际回复 ≠0：贡献临时改为 `rand(caster+0x9c)+1` 立刻换算 EXP（`0x40b49e` 调 `0x40a5d0`），再恢复原贡献（`0x40b4aa`） | `SupportMagicRules` HealMP 分支；`rand(level)+1` 进 `immediate_contributions`，`ExperienceRules.record` 先逐项即时换算再做尾部换算 |
| `0x10000` | ActiveAgain | proc0 命中后调 `0x4075a0(target)`：在队列槽 `[0, current)` 找该目标已消耗（flag 0）的槽并置回 1；目标本回合尚未行动则返回 0（无效果、无 EXP）；`0x4074a0` 前向槽用尽后从 -1 再扫一遍才重建回合，因此再激活槽在本回合末尾被服务 | `CoreTurnQueue.reactivate_consumed`＋`advance` 第二遍（其余槽标 `consumed`）；重制在准备阶段对无可再激活槽的目标按 `skill_has_no_effect` 拒绝（交互取舍，原作照付 ST） |
| `0x80000` | CancelActive（ActiveAgain 未置位时才访问） | proc0 命中后调 `0x407550(target)`：从 `current+1` 向后找该目标仍启用的槽并置 0 | 复用 `CoreTurnQueue.cancel_pending`（已消耗槽不可取消）；无可取消槽同样拒绝 |
| `0x20000` | StealGold | proc0 命中后：`amount = rand(|high-low|) + low + 1 + rand(caster.dex/3 + caster.level)`；caster 记录 `+0x28&0x10000` 置位（玩家侧；`0x40b538 test`、`0x40b546 je` 清位才跳走）时封顶目标记录 live `+0x98` 携带金（`0x40b548`；ebp／esi 是 `[0x4c1bc8] + obj+0xa4·0x1fc` 记录——`0x4c1bc8` 存的是记录表指针，`0x40aa87 mov ecx, [0x4c1bc8]`，`0x40aab3`／`0x40aac3`）并累加到 `0x4c2c84`，否则从 `0x4c1bcc` 扣；两支都不减目标 `+0x98`；EXP 直接 `amount/2 + rand(amount/2)` 不经贡献换算。击杀金钱 `0x40e390(victim)` 返回的正是同一记录 `+0x98`（`0x40e3a7`），所以封顶与击杀金钱读同一个 live 字：模板复制后 `0x42bd50` 字 0 的 EVEF 实例金钱与入场成长都作用于它 | `SpecialUtilityRules` STEAL_GOLD（竊殺 Attack+StealGold、銀之手 纯 StealGold——004 漢克斯 的 PLAYERS `special_other` 初始声明，resource-derived）：施法者 `growth_profile.source.mode & 0x10000` 判定侧别；金额进 PlayLoop `gold`（登记玩家加、敌方扣）；封顶读 `BattleRewardRules.carried_gold`（与击杀金钱同一读法：EVEF 实例覆盖＋入场成长，lane GOLD 2026-09-25 起）；EXP 经 `experience_basis.direct_experience` 直接加 |
| `0x40000` | StealItem | proc0 命中后遍历目标 `+0x138` 八个槽，逐槽 `rand(100)+1 < 0x40e6c0(item)+10+caster+0x196` 时 `0x44f2d0(item,1)`（进待领取集合）与 `0x436e80(target, slot)`；首个成功即停；`0x40e6c0` 即 ITEM `get_ratio`（掉落函数 `0x44f580` 同一 getter）；贡献永久加 proc0 值（`0x40b641`），再以 `rand(level)+1` 临时替换贡献即时换算（`0x40b674`）后恢复（`0x40b68b`） | `SpecialUtilityRules` STEAL_ITEM：`InventoryRules.remove` 左移目标槽，`BattleLoopRewards._commit_rewards` 把 `stolen_items` 追加进同一 pending 集合（领取／延期／满包交换共用）；proc0 值留在尾部贡献、`rand(level)+1` 进 `immediate_contributions`；`+0x196` 读 `combat_profile.steal_ratio`（R27 起，见「偷窃加成字 +0x194／+0x196」段） |
| `0x100000` | StealHP | 需主伤害 `iStack_4≠0`：caster HP += 伤害，封顶上限；贡献 `+= 伤害*20/100 − 伤害`（`0x40b7c3..0x40b7ec`，纯 Attack+StealHP 行即 `伤害*20/100`），仅 >0 时 `0x40b7fe` 换算一次 EXP，再恢复（`0x40b814`）；函数尾部 `0x40b866` 再按原伤害贡献换算一次 | `SpecialUtilityRules` STEAL_HP：施法者 HP 回补封顶；`dmg*20/100` 进 `immediate_contributions`（>0 才进），尾部贡献保持 `dmg` |

分派之后 `*(caster+0xb0) = compensation` 写回命中补偿；末尾按贡献换算 EXP：若函数内已有即时换算（累计值 `var_18h≠0`），仅当贡献 >0 时 `0x40b866` 再换算一次并相加返回；否则 `0x40b8b5` 直接返回一次换算（贡献 0 时 `0x40a5d0` 返回 0）。

### 即时换算与尾部换算（2026-09-21 lane R3-skills 复核，static-derived）

`0x40aa80` 内五处 `call 0x40a5d0`（HealMP `0x40b49e`、StealItem `0x40b674`、ActiveAgain `0x40b6fa`、CancelActive `0x40b770`、StealHP `0x40b7fe`）都是同一模式：`edi/esi/ebx = [0x4c13fc]`（保存运行中贡献）→ `[0x4c13fc] = 临时值` → `call 0x40a5d0` → 累加到 `var_18h` → `[0x4c13fc] = 保存值`。两次换算读同一施法者等级、目标等级、效果后的目标 HP 与连杀字（`0x40a5d0` 只读这些，连杀字由外层交锋处理更新）。重制 `ExperienceRules.record` 接受收据的 `immediate_contributions`，按顺序各调一次 `from_contribution`（消耗随机数的顺序与原函数一致：五处即时换算都是本行最后一个消耗随机数的分支，尾部换算随后），再按 `native_contribution` 做尾部换算；`experience_basis.points` 为两者之和，`tail_points`／`immediate_experience` 分列。纯 ActiveAgain／CancelActive／HealMP 行尾部贡献为 0，两种写法数值相同；萬息臨界法（Heal+HealMP）、吸血劍（Attack+StealHP）、金之手（StealItem 的 proc0 值留在尾部）三行原先合并为单次换算的 provisional 已替换。未做有界原指令执行；替换证据仍是对这些位的原执行回执。

## 数值 helper `0x40a7b0` 的通道差异

```text
channel0 (magic):   rate = (proc&4) ? row.status_hit_ratio : caster.+0xd4 + row.hit_ratio + compensation
channel1 (special): rate = row.hit_ratio + compensation           （proc 任意）
miss:  proc&4==0 → compensation += (draw+1)/10 ; return 0
hit:   proc&4==0 → compensation = 0
       proc&2==0 → 三角取值 + [channel0: (clamp(level,1,80)+mind项+sample)*magic_attack/100]
                             [channel1: (sample + rand(level*180/100) + rand(level*150/100) + dex/3 + con/8 + mind/4) * attackpow_ratio/100]
       proc&2!=0 → 0x406fe0(low, high)（纯三角，无属性项）
       value<3 → 折到 3..5
       proc&1==0 → 按 row.type 取目标 +0x104.. 抗性（封顶 80）乘 (100-res)/100；magicOTHER 无 case，不乘
```

由此：绝技通道的状态判定（proc6）读 `hit_ratio` 而非 `status_hit_ratio`（SPECIAL.TXT 亦无该列），magicOTHER 绝技不受抗性影响，magicMIND 等绝技受对应抗性影响。`PoisonArrowRules.roll` 已实现这两条路径，`SpecialStatusRules` 直接复用它作为 channel1 roller。

## 衰弱在派生刷新 `0x448840` 与计时 `0x40b910` 中的参与

`0x448840` 开头把基础四属性 `+0x64/+0x68/+0x6c/+0x70` 复制到 live `+0x4c/+0x50/+0x54/+0x58`；若 flag&8，则四项各减 `+0x3a`（衰弱幅度），下限 1；之后才进入职业公式（攻防／魔攻／速度／HP／MP 上限，并把当前 HP／MP 夹到新上限）。`0x40b910` 对 `+0x38` 低字递减，归零时清字、清 flag 8 并调用 `0x448840`。

重制：`ProgressionRules.refresh_growth_stats` 通过 `StatusEffectRules.weakened_attributes` 把衰弱幅度扣进 `JobStats.base_values` 的输入；`StatusEffectRules.after_action` 递减／到期并报告 `expired=["weaken"]`，PlayLoop 的行动尾部据此刷新。

2026-09-21 lane R3-skills（static-derived，r2ghidra 阅读 `0x40a7b0`／`0x409a60`／`0x409be0`／`0x40aa80`）：原作公式读的全是 live 字，不读基础字 `+0x64..+0x70`——`0x40a7b0` channel1 `+0x50/3 + +0x54/4 + +0x58/8`（dex／mind／con），channel0 mind 项 `+0x54`；`0x409a60` 命中差 `(+0x50 − 目标+0x50)/2`（dex）；`0x409be0` 伤害力量差 `(+0x4c − 目标+0x4c)/2`（str）；`0x40aa80` StealGold `+0x50/3`（dex）。重制统一走 `StatusEffectRules.weakened_attributes`（`0x448840` 前奏：基础减衰弱幅度、下限 1）：`CoreCombatRules.combat_profile_from_unit` 的 str／dex／mind／con、`SpecialDamageRules.prepare` 的 dex／mind／con（Utility／Support／StatMagic 的 channel1 与 StealGold 经它取值）、`StatusApplicationRules`／`SupportMagicRules`／`OtherMagicRules`／`StatMagicRules` 的 mind。保留读基础值的两处按原语义：`LearningRules` 的学习记录属性回滚校验与 `ProgressionRules` 的点数分配都作用于基础字。数值幅度仍未做有界原执行：替换证据为对衰弱施法者执行 `0x40a7b0`／`0x409a60` 的探针。

## 偷窃加成字 +0x194／+0x196（2026-09-22 lane R27 读法；lane R32 有界原生执行，static-derived＋native receipt）

`0x40b5a8` 的判定 `rand(100)+1 < get_ratio + 10 + caster+0x196` 里的加成字来源（下表每个写点与判定都已由 [original_steal_ratio.json](original_steal_ratio.json) 回执核对，探针 `hsltools/probes/steal_ratio.py`）：

| 写点 | 读法 | 重制 |
| --- | --- | --- |
| PLAYERS loader `0x44b980`：`steal_ratio` → 模板 dword 索引 0x65（`+0x194`；缺行时 0） | 与 `avoid_hit_ratio→+0x198`、`attack_back→+0x19c`、`attack_damagex2→+0x1a0` 同段（`original_town_job_up.md`）。PLAYERS 66 行只有 004 漢克斯 30、013 20 非零（resource-derived） | `equipment.initial_physical_fields` 写单位 `combat_profile.base_steal_ratio`（原字）与 `steal_ratio`（工作值），137 场 battle JSON／actors 模板同步；`profiles.json`／`growth_profile.source` 不加键——原探针回执逐字比较 `source_profile` 与 `calculate`，加键会伪造回执差异 |
| 刷新 `0x448840`：`+0x196 = +0x194 字，为 0 时 12`（与 `+0x19e` 12、`+0x1a2` 8 同一默认块） | 反编译 `0x448840` 第 80–91 行 | `ProgressionRules.refresh_growth_stats`：`steal_ratio = (base 或 12) + Σ 装备` |
| 逐件装备 `0x448420`：`+0x196 += item+0x40`（`add_steal_ratio`，ITEM loader `0x4477c0` 写 `+0x40`） | 与 `+0x19a += +0x44`、`+0x19e += +0x48`、`+0x1a2 += +0x4c` 同段；ITEM 只有 131 隱忍黑衣 20 非零 | `equipment.py NUMERIC add_steal_ratio→effects.steal_ratio`，`EquipmentRules.effect_delta` 求和；131 因此 `supported` |
| 转职 `0x4348f0`：`add word [esi+0x194], cx`（`0x434aa6`）字相加 | `original_town_job_up.md` | `JobUpRules.merge_source_template` 把模板 `combat_profile.base_steal_ratio` 加进单位；下次刷新重算工作值。004→013 链为 30+20=50 |
| 判定 `0x40aa80` 位 0x40000（`0x40b5a8`） | 上表 | `SpecialUtilityRules.prepare` 读 `caster.combat_profile.steal_ratio` 缺失即 `missing_steal_ratio`，`resolve` 用它替代原 provisional 0 |

玩家可见差异：此前重制把加成记 0，比原版默认 12 低 12 个百分点，漢克斯低 30；现按原字。

### R32 原生回执（`refresh` 21 组、`job_up` 5 组、`steal` 67 组）

| 组 | 执行 | 原生结果 |
| --- | --- | --- |
| `refresh` | `0x448840` 于完整 PLAYERS 记录（001／004／013 与 001 上的合成字 0／1／12／30／50／200），装备 无／131／131×2，`+0x196` 先污染为 0x7777、各刷两次 | `+0x196 = (+0x194 字，0 时 12) + Σ item+0x40`：001 → 12／32／52，004 → 30／50／70，013 → 20／40／60；字 1 → 1（非零字不套默认）；两次结果相同——重算不累加 |
| `job_up` | `0x4348f0(slot, flag)`：记录 004→模板 013、001→010、010→019（二阶 flag）、004＋131→013、013→004；模板经 `0x4a2728[code]` 描述符→`0x4c1afc` 模板表解析，`0x42c700` 换槽 code，内部 `0x448840` 真实执行 | `+0x194` 低字相加（30+20=50、0+0=0），`+0x196` 由刷新重写（50、50+20=70、0→12），职业码 89／81／82／88 复制，槽 code 809，`+0x134 |= flag`；四属性／经验／等级／背包不变 |
| `steal` | `0x40b8f0(owner,target,5,5)` → 完整 `0x40aa80` 正常返回，SPECIAL 金之手 行（function 0x40000），待领池预分配，caster `+0x196` 直接给字，目标八槽由 ITEM `get_ratio` 铺表 | 见下 |

`steal` 组证明的循环语义（`0x40b5e1..0x40b5e5`）：

| 库存 | 结果 |
| --- | --- |
| 左密 `[210,246,241,0…]`（字 12／30／50／0，六种子） | 首槽 `roll < 60+10+字` 即偷（roll 75 < 82 偷、20 偷），失败则下一槽；偷中：待领池 `[[code,1]]`、`0x436e80` 左移、贡献 += proc0 值、`rand(level)+1` 立即换算一次（`0x40b674`）＋尾部按 proc0 值再换算一次（`0x40b866`），返回两者之和 |
| **非左密** `[0,210,246,241,…]` | 命中但**零次抽样、零偷取**，返回 0（`0x40b8b5` 直接换算贡献 0） |
| `[32,0,210,246,…]`（字 0，阈值 10） | 首槽 roll 20／75 失败后遇空槽即停，后面的 210／246 不抽；roll 5 则偷走 32 |
| `[246,246,0,210,…]` | 首槽偷中即停，210 不抽 |
| `[32..39]` 八件 `get_ratio` 0、字 0 | 种子 7／40 八槽全失败（roll 全 ≥ 10）返回 0；种子 99 第八槽 roll 3 偷中 |
| 行 hit 90 未命中（种子 11／12／35／40） | 不进循环，返回 0，补偿 `+0xb0` 加 roll/10 |

**差异与规则修正**：原版遇首个空槽即断，重制此前 `continue` 跳过空槽——对左密库存两者等价（sweep 137 场 results.json 不变），但对带洞库存重制会多抽样并可能偷到洞后的物品。R32 把 `SpecialUtilityRules.resolve` 改为 `break`，`prepare` 的 `useful` 改为「首槽非空」（首槽为空时原版必然一无所获，准备阶段照旧以 `skill_has_no_effect` 拒绝、不扣 ST）；`run_skill_resolution_tests` 新增两条断言（洞后物品拒绝、首槽失败＋空槽只抽一次 rand(100)）。其余（阈值、`get_ratio` getter `0x40e6c0`、两次换算、左移）零差异。

## 免疫位来源

PLAYERS 加载器 `0x44c3ec` 把 `no_weaken` 写入角色 `+0xa0` 的 `0x2000` 位（`no_paralyze` 0x800、`no_disablemagic` 0x1000 同段）；`0x448420` 在装备非空时把 `0x2000` 映射为效果位 `0x2000000`，与 `0x40aa80` 的免疫查询一致。`hsltools/data/skill_book.py` 的 `status_capability_flags` 现包含该位。

## 第九波补读：AllUp（魔障壁）、五位复合状态与无人持有的源行

2026-09-20 lane A2。仍为 `static-derived`（r2 反汇编阅读 `0x40aa80`／`0x448840`／`0x40b910`，未做有界原指令执行）。

### `0x100` AllUp —— `0x40b1ee..0x40b299`

```text
0x40b1f2  test ah, 1                          ; function & 0x100
0x40b206  call 0x40a7b0(caster, target, row, &comp, proc=1, channel)   ; 返回值被随后的 rand 覆盖，只保留命中补偿
0x40b20d  call 0x42c780(4) ; +2                 ; turns = rand(4)+2
0x40b218  or [target+0x24], 0x40                ; 状态 flag 0x40
0x40b223  cx = word [target+0x48]; ecx += turns; 超过 9 时 turns 按差额缩减（不为负）, ecx = 9
0x40b240  word [target+0x48] = cx               ; 剩余回数（低字）
0x40b24c  contribution += 3*turns               ; 与 DefUp／AttUp 的 2*turns 不同
0x40b257  call 0x42c780(14)                     ; rand(14)
0x40b265  eax = rand + word[target+0x4a] + 7    ; 新强度 = 旧强度 + rand(14)+7
0x40b269  cmp eax, 0x14 ; jle → mov eax, 20     ; 封顶 20（累加，不取平均）
0x40b274  word [target+0x4a] = ax
0x40b278  call 0x448840(target)                 ; 派生刷新
```

`0x448840` 在复制基础抗性 `+0x118..+0x128 → +0x104..+0x114` 之后（`0x448903`）：若 flag&0x40，五个抗性槽各加 `movsx word [+0x4a]`，每个封顶 0x50＝80。`0x40b910` 对 `+0x48` 递减，归零时清 flag 0x40 并调用 `0x448840`（`0x40b9eb..0x40ba0c`）。退魔 `0x4000` 分支（`0x40b29d`）只清 `0x20`／`0x10` 与 `+0x44`／`+0x40`，不触及 AllUp。

重制：`StatEnhancementRules` 新增打包字 `resist_up`（flag 0x40，低字回数、高字强度 7..20，`merge_resist_word` 累加封顶；`dispel` 只清 attack_up／defense_up），`StatMagicRules` 的 0x100 序列为 proc1 抽样（弃值）→`rand(4)+2`→`rand(14)+7`（不再第二次调用 helper），贡献 3／回；`ProgressionRules.refresh_growth_stats` 把强度加进五抗性并 clamp 80；到期沿既有增益尾部刷新。AI 端 `0x40dcf0` 已把 0x100 映射到 flag 0x40（`AISupportRules.buff_useful`），`AISupportPlanning` 现把 0x100 归入 buff 类。魔障壁 无导入特效素材，切入落到通用状态效果（provisional）。

### `0x101d` 死骸腐靈獄 —— 五位复合

MAGIC 唯一同时含 Attack／Paralysis／Poison／NoMagic／Weaken 的行。`0x40aa80` 的位访问顺序为 Attack(1)@0x40ab35 → Heal(2)@0x40abb0 → Paralysis(4) → Poison(8) → NoMagic(0x10)@0x40ae3d → Weaken(0x1000)@0x40aee0 → DefUp(0x20)@0x40b01c → AttUp(0x40)@0x40b112 → AllUp(0x100)@0x40b1ee → ClearAtDfUp(0x4000)@0x40b29d → CureWeaken(0x2000)@0x40b30f → …；每个状态位各自 proc6 判定（channel0 读 `status_hit_ratio`），Poison／Weaken 幅度在同行含 Attack 位时 `*30/100`，主伤害致死后各状态分支因 HP 0 直接跳过。`StatusApplicationRules` 既有实现即按此顺序逐位处理，本波只把 0x101d 加进接受掩码。

### 无人持有的源行（resource-derived）

| 行 | 别名 | 说明 |
| --- | --- | --- |
| `special:magicOTHER:magicCode14` 高級金之手 | `金之手LV2`＝0x2000（既非 RESOURCE 264 名也非 名+'2'，生成器 `ALIAS_OVERRIDES` 显式映射） | PLAYERS 66 行无声明、20 职业学习表无条目、45 来源模板不引用 |
| `special:magicOTHER:magicCode29` 百裂突刺 | `百裂突刺2`＝0x10000000 | 同上 |
| `special:magicOTHER:magicCode32` 獅子吼 | `獅子吼2`＝0x80000000 | 同上 |
| `special:magicOTHER2:magicCode03` 吸血劍 | `吸血劍2`＝OTHER2 位 0x4 | 059 的 PLAYERS `special_other` 字段写「吸血劍2」，但别名表不分字段：0x4 落在 special_other 掩码即 OTHER 03 無想冥殺（059 现有初始授予），special_other2 掩码为 0 |

四行按本尊 policy 登记为数据行（native_special_damage／native_special_utility），覆盖表 `unknown_skill` 归零；玩家与 AI 在原作数据下实际无法获得它们，登记只保证同一事务可解析。

### 其余第九波登记

天地鳴動／怒濤地裂崩（EARTH 03／04）、魔燒焚燼／怒炎魔獄燋（FIRE 03／04）、烈蝕水彈／極零裂凍破（WATER 03／04）＝纯 `magicFun_Attack` 的 `eff_proc_Global` 行，走各元素既有 `native_magic_damage`；地靈聖護（EARTH 07 DefUp）／赤炎波動（FIRE 06 AttUp）＝区域版 `native_magic_stat`；大地之癒／大地之惠（EARTH 08／09 Heal）＝区域版 `native_magic_support`；神怒（OTHER 23，job 97 tier 2）＝`native_special_damage`。全部沿既有 `prepare_cast`／`resolve_cast` 逐目标事务，专属特效素材未导入——降级到既有通用表现（provisional）。


## AI 绝技通道支援／增益（2026-09-21 lane R3-skills，static-derived）

r2ghidra 阅读 `0x40c620`／`0x40dd80`／`0x40df70`／`0x40e0e0`／`0x40e100`／`0x40e180`／`0x40c480` 与 AI 对象过程 `0x43ede0` 的 `0x440767..0x440b0f` 段（`pD` 线性反汇编，地址可复核）；未做有界原执行。

| 原入口 | 读法 | 重制落点 |
| --- | --- | --- |
| `0x40c620` | 清空 `*0x4c1b78` 的 0x1c 个 dword 后，先遍历 SPECIAL 表 `0x4c3920`（7 型 × 位掩码 `actor+0x158..`，`row+0x10*20 <= 气力+0xe8`）以 `0x407010(row+0x28, 0x38, row+0xc, type, code, buckets)` 装桶，再遍历 MAGIC 表 `0x4c2ca0`（`actor+0x174..`，`row+0x10 <= MP+0xe0`，`status&2` 时整段跳过）以 base 0 装桶。即 SPECIAL 与 MAGIC 用同一分桶器：治疗 1（范围）／2、进攻 3／4、增益 5、状态 6、净化 7；桶结构每桶 8 字节（头指针＋计数），SPECIAL 桶从 `+0x38` 起 | `AISupportPlanning`／`AISelfPreservation` 以 `AISkillDecisionRules.buckets` 给 `native_special_support`／`native_special_stat` 行分桶；无桶行（萬息降靈法 纯 HealMP）跳过 |
| `0x40e0e0`／`0x40dc50` | SPECIAL／MAGIC 治疗桶 1 或 2 计数非零 | `0x40c570` 的 special／magic 可用性参数（`select_action(profile, flags, magic, special)`） |
| `0x40e100(mask)`／`0x40dc70(mask)` | SPECIAL／MAGIC 净化桶 7 中存在净化位（0x400 毒→1、0x800 禁魔→2、0x200 麻痺→4、0x2000 衰弱→8）落在 mask 之外的行 | 同上，状态援助路径 |
| `0x40e180(mask)`／`0x40dcf0(mask)` | SPECIAL／MAGIC 增益桶 5 中存在增益 flag（0x20→0x20、0x40→0x10、0x100→0x40）全不在 mask 内的行 | `0x40c480` 扫描内二者 OR：`AISupportRules.buff_useful` 的 `buff_masks` 现含绝技增益掩码 |
| `0x440767..0x44080c`（友军回复 mode 3） | `0x40c2f0(actor,8,1)` 扫描 → `0x40c570(actor, 0x40dc50(), 0x40e0e0())` 选类别 → 类别 0 查首件回复药 `0x40c1d0` 并 `0x40d530(range 1)`；类别 1 → `0x40dc50()` → 子状态 0xd（MAGIC）；类别 2 → `0x40e0e0()` → 子状态 0x14（SPECIAL）；三类轮转 `(kind+1)%3` 各试一次后续扫下一位友军 | `AISupportPlanning.choose`：heal／status 以 `select_action(..., 有 magic 行, 有 special 行)` 定类别，类别 2 取该友军计划的 special 切片 |
| `0x4408ee..0x440a21`（状态援助 mode 4） | `0x40c3a0(actor,8,1,&mask)` → `0x40c570(actor, 0x40dc70(mask), 0x40e100(mask))` → 类别 0 `0x40c230` 首件状态药；1 → 0xd；2 → 0x14 | 同上 |
| `0x440a3b..0x440ad5`（增益 mode 6） | `0x40c480(actor,8,1,&mask)` → `0x458c10() & 1` 决定先 MAGIC（0，`0x40dcf0`）或先 SPECIAL（1，`0x40e180`），两次尝试，无物品类别、不读 `ai_att_*` | `AISupportPlanning.choose` 的 buff 分支改为一次 `rand(2)` 硬币（source `0x440a86..0x440ad3`），不再复用 `select_action` |
| `0x40dd80(bucket, mask)` | `0x40c770` 的 SPECIAL 孪生：桶在 `+0x38+8*(bucket-1)`，`rand(32)%count` 起点、逐节点 `rand(100)+1 <= row+0x20`（SPECIAL 的 use_ratio 列；MAGIC 在 `+0x28`）；桶 7 若该行净化位与 mask 无交集则置 200 拒绝，桶 5 若该行增益 flag 已全部在 mask 内则拒绝 | `AISkillDecisionRules.select_index(rates, rng, "special", bucket)` 标 `0x40dd80`；有益性由 `useful_ids` 预过滤（等价于 200 拒绝，随机消耗顺序不声明等价）；进攻桶 3／4 亦经同一 walk（见下「进攻绝技桶 3／4 的回放」） |
| `0x40df70(actor, target, bucket, fallback_bucket, …)` | `0x40d340` 的 SPECIAL 孪生：桶 7 取 `0x40c1b0(target)`、桶 5 取 `0x40c2d0(target)` 为 mask，`0x40dd80` 选行（失败再试 fallback 桶），随后与 MAGIC 相同的 `0x40cca0`／`0x40c9a0` 中心／落点搜索（channel 参数 1；无 MAGIC 路径的 `0x40e270` 检查） | `AISkillPlanning.choose` 对 special 计划一律走桶路径：支援调用方传入桶，进攻按 `area_order` 的 (first, fallback)；落点仍用既有最短合法移动策略 |
| 自救回复（`0x43fa29` case 2） | `0x40d4e0` 范围先后 → `0x40c570(actor, 0x40dc50(), 0x40e0e0())` → 同两条子状态 | `AISelfPreservation.choose_healing` 以两通道可用性调 `select_action`，类别 2 取 special 治疗行 |

由 SPECIAL.TXT 源行可知：萬息集氣法／萬息臨界法（治疗桶 1）、萬息秘孔術（净化桶 7）都是 `range0Cell` 施放、自身为中心的范围行，AI 走到友军旁再施放；千羽風靈壁／激怒／精神統一 是 `range0Cell`／`range0Cell` 的纯自身增益，`0x40c480` 排除自身（`iVar5 != param_1`）且原作无自身增益路径，故原作 AI 实际不会施放这三行（negative-evidence：在 `0x43ede0` 的 16 个 mode 中未见读取增益桶的自身路径）；重制的友军增益扫描把它们计入 `buff_masks` 但生成不出合法意图，与原作行为一致。

**provisional**：自救净化路径本身无原通道顺序（`AISelfPreservation.choose_cure` 先 MAGIC 桶再 SPECIAL 桶再物品）。

### `0x40c770` MAGIC 桶 5／7 的接受语义（2026-09-22 lane R12-rules-leftovers，static-derived）

r2ghidra 复读 `0x40c770(bucket, mask)`：每个访问节点先 `rand(100)+1` 得 roll（`fcn.00458c80(100)`，无条件消耗），再按桶改写 roll：桶 7 取该行净化位（0x400→1、0x800→2、0x200→4、0x2000→8）与 mask 相交则 `roll = -200 + 200 = 0`，否则 `200`（`0x40c89d`）；桶 5 取该行增益 flag（0x40→0x10、0x20→0x20、0x100→0x40）与 mask **无交集**则 `roll = 0`（`0x40c8dd..0x40c8e1`），有交集则保留 rand 值；桶 3／4 只对含 0x4000（退魔）位的行改写：mask 含 0x60 则 0、否则 200。随后统一 `roll <= row+0x28`（use_ratio）接受。即：MAGIC 净化行对有该状态的目标、MAGIC 增益行对尚无该增益的目标**无条件接受，不读 use_ratio**；SPECIAL 孪生 `0x40dd80` 没有置 0 分支——桶 7 无交集置 200、桶 5 已全部在 mask 内置 200，其余保留 `rand(100)+1 <= row+0x20`。

落地：`AISkillDecisionRules.select_index(rates, rng, channel, bucket)` 对 `channel == "magic"` 且桶 5／7 把 roll 置 0（`useful_accepts`），rand(32)／rand(100) 仍照原顺序消耗；调用方（`AISkillPlanning.choose`／`AISelfPreservation._choose`）已按 `useful_ids`／`cures_something` 预过滤为对 primary 有用的行，所以 200 拒绝路径对应"不在候选里"。`run_ai_support_tests.useful_bucket_acceptance` 守着：use_ratio 0 的 MAGIC 桶 5／7 行被接受、SPECIAL 桶 5／7 与两通道桶 3／4 仍落空，且 draw 序列不变；live 用例为 use_ratio 0 的 驅毒（MAGIC）施放、萬息秘孔術（SPECIAL）落空。

边界：① MAGIC 桶 5 对目标**已有**该增益的行原作仍按 use_ratio 抽签（不是拒绝），重制预过滤直接跳过——差异只在"重复施加已存在增益"这一种情形，重制不复制；② 桶 3／4 的退魔（0x4000）行原作按目标是否持有 0x60 增益置 0／200，重制对退魔行仍按 `useful_ids` 预过滤＋use_ratio 抽签，未接（provisional，替换证据即本段读法）；③ 均为反编译阅读，未原执行。

### 进攻绝技桶 3／4 的回放（2026-09-22 lane R12-rules-leftovers，static-derived）

AI 对象过程 `0x43ede0` 的进攻段（`pD` 线性反汇编 `0x43f79b..0x43f939`）：`0x40bf70` 取到目标后 **先** `call 0x40d4e0`（`0x43f7bf`），按返回把 `[0x4c2c50]`／`[0x4c2c4c]` 写成 (3,4) 或 (4,3)；再 `0x40c570(actor, 0x40dd60(), 0x40e1f0())`（`0x43f824`）选类别；类别 2 → `0x40df70(actor, target, [0x4c2c50], [0x4c2c4c], 0x40bab0(actor), 1)`（`0x43f873`，成功写子状态 0x14），类别 1 → `0x40d340(actor, target, [0x4c2c50], [0x4c2c4c], …, 1)`（`0x43f8f6`，子状态 0xd）。即 MAGIC 与 SPECIAL 收到**同一对** (first, fallback) 进攻桶。`0x40df70`：桶 7／5 先取 `0x40c1b0`／`0x40c2d0(target)` 为 mask（进攻桶 mask=0），`0x40dd80(first, mask)` 选行，落空或 `0x40cca0`／`0x40c9a0` 站位搜索失败再 `0x40dd80(fallback, mask)` 一次；`0x40dd80` 对桶 3／4 **没有**额外分支——`rand(32)%count` 起点、逐节点 `rand(100)+1 <= row+0x20`（SPECIAL use_ratio）接受，无权重、无顺序偏置（桶内顺序即 `0x40c620` 前插得到的倒源序）。另 `0x40d4e0` 的另外三个调用点（`0x43fa2a`／`0x43fb1c`／`0x43fdc9`）同样先于各自的 `0x40c570`。

落地：`AISkillPlanning.choose` 删除进攻 special 的均匀抽取，special 与 magic 同走 `area_order(ai_magic_multi_first)` → 逐桶 `select_index(..., channel, bucket)`；`prepare` 对两通道都要求 `ai_magic_multi_first`（原 `0x40d4e0` 不看通道）。`run_ai_skill_tests.special_bucket_walk` 守着：flag 0／1 分别先桶 3（流星降）／桶 4（氣刃斬），draw 序列 `[100, 32, 100…]`，use_ratio 0 两桶各访问一行后落空且 live 回合不付 ST。

边界（provisional，最保守取舍，供负责人决定）：原作 `0x40d4e0` 在 `0x40c570` **之前**只抽一次并由两通道共用；重制沿用既有组合——`select_action` 之后在每个通道的 `choose` 内各抽一次 `area_order`，两通道都有计划且先试的通道落空时会多抽一次。改成先抽会改变既有 MAGIC 路径的 RNG 序列与 `run_ai_skill_tests` 的 draw 断言，本 lane 未动。`0x40df70` 的"站位失败回退到 fallback 桶"已由 lane AI-PRIO 复刻（`AISkillPlanning.choose_any`：挑中的行无施法中心时退到另一桶一次）。


## 专属特效素材：导入与脚本播放器（2026-09-22 lane R7-skill-effects，resource-derived；时序／几何 provisional）

范围（`content/generated/hsl/skills/special_effect_scripts.json`，`python3 tools/hsl.py check special_effect_scripts` 从 tracked 的 effects.txt／global.obs／OBJ-ALL.H／初始技能书逐字节重渲染）：每行绝技的 `attack_code`／`defense_code` 各对应 EFFECTS.TXT 一个 `[effect]` 脚本（攻方脚本多为空，守方脚本承载演出）；60 行共引用 221 个 `obj_Special*` 对象（`defProcObjectMove`，`planeEffect4` 231／`planeEffect3` 29／`planeEffect2` 5）→ 535 个 SHP 成员名／605 帧声明，59 个 WAV，24 个 `ani*` opcode（`aniDelay` 308、`aniPlaySound` 138、`aniInsertObject` 124、`aniInsertRandomObject` 93、`aniInsertRandomObjectFixDelay` 67、`aniProcessHitMiss` 55、`aniShowHitResult` 50、`aniInsertRandomObjectDelay` 48、`aniPlayHitSound` 43、`aniInsertHitRandomObject` 38、`aniInsertSpecialBG` 16、`aniDoublePageMode` 15，其余 12 个各 ≤11 次）。

**素材（resource-derived）**：`hsltools/assets/skill_effects.py`（`python3 tools/hsl.py check skill_effects`）把清单里每个 SHP 成员与 WAV 从 hsl.pak 逐字节导入 `content/imported/hsl/shared/skill_effects/`（frames 495 PNG、sounds 59 WAV，与 first_skill 同一 `parse_shp`／`write_shp_preview`／XOR-A8 WAVE 解码，13 个与 first_skill 重叠的文件字节相同）；manifest 记每帧 `draw_origin`／sha256、每个对象的 plane／process／`shape_delay`／`frame_ticks = shape_delay + 1`（SHP helper 的 D+1 约定，与 fire_animation 同）／`obj_Mode`。两处显式缺口：`obj_Special51_05`（弒神渺殺斷 第三段命中对象）在 OBJ-ALL.H 无定义→`unresolved_objects`，播放器跳过并登记 `skipped_objects`；闇瑩蝶舞 的 `obj_Special08_01…08` 各声明 9 个 shape 但 hsl.pak 只有每十位的 3 个（SP08_001…003、007…009、011…013…），40 个成员名无记录→`missing_members`（negative-evidence），播放器循环现有 3 帧。ANIMAL.H 给出每个 opcode 的参数名（`aniInsertRandomObject [code][x][y][x range][y range][delay][number]` 等，resource-derived）。

**播放器（表现层，`game/battle/scene/SkillEffectScriptPlayer.gd`）**：24 个 opcode 全部实现（manifest `implemented_opcodes` 与代码同拼写，`run_skill_effect_script_tests` 守着），`compile(attack, defense, hit, seed, manifest)` 把攻方脚本＋守方脚本编成 tick 时间线：`aniDelay` 推进游标；`aniPlaySound`／`aniPlayHitSound`（后者只在命中）声音事件；`aniInsertObject` 与 Random／RandomDelay／RandomFixDelay／DistanceFixDelay／HitRandom／HitRandomDisp／HitRandomFixDelay／Angle／AngleMakeShape／RoundRandom／Tornado 各按参数名插入对象；`aniInsertSpecialBG` 换该阶段底图；`aniProcessHitMiss(Multi)` 首个即 impact；`aniShowHitResult(NoWait)` 首个即结果文字时刻；`aniDoublePageMode`／`aniNoSpecialDarkBG`／`aniShowAttacker`／`aniSetXYDisp` 为页面旗标。`BattleCombatCutin._process_skill` 按 manifest `rows[skill_id].presentation` 分流：`script`（58 行）→ 播放器；`dedicated_module`（毒魔箭 `PoisonArrowPresentation`、月花圓舞 `MoonDancePresentation`）不经此处；`borrowed_qi_blade`（含未实现 opcode 的行，今 0 行）与无 `skill_id` 的合成 clip 保留 氣刃斬 借用演出。规则不动：命中／伤害由 play loop 已判定，播放器按 `hit` 丢弃 Hit* 事件；随机布置用按 clip 播种的表现层 RNG。

**provisional（写进 manifest `policy`／`replacement_evidence`）**：① 时钟 60 tick/s 按真实秒（原 `0x4022aa` aniDelay 计数器的调用频率未量，first_skill 包同一假设）；② 对象寿命 `shape_number × (shape_delay+1)` tick、舞台外（x∉[0,640] 或 y∉[0,320]）插入的对象直线飞向目标中心 (320,160) 并在同阶段下一个命中标记落地（无则 30 tick）、其余静止——`defProcObjectMove` 与 `obj_Data7` 运动程序未读；③ Random 系列的 `delay` 读作每实例 `rand(0..delay)`、`FixDelay` 读作 `base + i×delay`、range 读作以 (x,y) 为中心的 ±range/2；Angle 系列 `degree num` 个实例按等分角向外 6 px/tick、AngleObject 用对象第 i 个 shape 为方向帧、MakeShape 旋转单帧；RoundRandom 按 `radius>>xshr`／`radius>>yshr` 椭圆等分（角度单位 256＝一圈）；Tornado 按 `y step`／`radius step`／`angle step`／`zoom step` 逐实例递增并每 tick 转 4/256 圈——替换证据是 `0x4037b0` 分派表 handler 15…35 的静态读法；④ 守方阶段底图压暗 0.45、双页模式攻方 (160,320)／守方 (480,320)、无 `aniShowHitResult` 的脚本在命中标记显示结果、结果文字保留 40 tick、脚本结束且全部对象消失后 pop——重制表现选择；⑤ 混合模式：默认加色（SP 帧黑底），`engSUBCOLOR_MIX` 减色、`engMIX` 普通——像素级等价未声明。截图（8 行×攻方／命中／结果）见 `tests/capture_skill_effects_review.gd` → `ignored/r7-skill-effects/`（人工验收，不入库）。

### 结果数字的显示语义：`aniShowHitResult` → `0x4084e0` → `defProcShowNumber`（2026-09-22 lane R12-rules-leftovers，static-derived；数字图 resource-derived）

绝技守方脚本由 `0x403954` 解释（`cmp eax,0x23; ja` → 字节表 `0x404f48` → 指针表 `0x404ee8`，与 ANIMAL.H 的 36 个 opcode 一一对应；对象动画解释器 `0x401f3b`／表 `0x4037b0` 对 17／18／30／35 等命中类 opcode 只 yield，不是它们的落点）。opcode 30 `aniShowHitResult`（`0x403ebd`，wait=1）／35 `NoWait`（`0x403eb3`）汇合到 `0x404643`：读 `*0x4c6f74`（HP 变化，正＝伤害、负＝回复）与 `*0x4c6f78`（第二值，MP 量）——`ecx>0` → `0x4084e0(x, y, ecx, 0, kind 0)`；`ecx<0` → `0x4084e0(x, y, -ecx, 0, kind 2)`；`eax≠0` 再在**同一点**生成 `kind 3` 的 `|eax|`，hold（第 6 参）＝`0x28`（`0x4046b0..0x4046d6` 依次压 0x28、3、0、|eax|、y、x）——MP 数字比 HP 数字晚 40 tick、位置相同（2026-09-26 lane DIGITS 更正：此前误读为 `y-0x28` 叠放）；两者皆 0 且 `*0x4c13f0`（状态已生效标志）为 0 → `kind 5`。`0x4084e0(x, y, value, wait_ref, kind, hold)` 生成对象 `0xb1`（`obj_ShowNumber`，`SHAPE\NUM100.SHP` 65 帧，`planeMenu2`），`0x45b6de` 把 value 十进制写入 `+0x34`，`+0x8e = kind`；`kind 6` 另放 `0x408b20(...,3)` 与声音 `0x191`。`0x40aa80` 的 Heal 分支（`0x40ac10..0x40ac24`）不经脚本，直接 `0x4084e0(target.x, target.y-0x34, 夹到上限后的实际回复量, 0, 2, 0)`。

`defProcShowNumber = 0x408580`（`switch [+0x8e]`，数字形 = `(c-'0') + param_1 + [+0x32]`，`+0x32` 初始 0）：kind 0 → `NUM100..109`（**红**，带弹跳／缩放的 case 0 专用绘制）；kind 1 → `+0x1e` `NUM400..409`（紫）前置形 `+0x33`＝`NUM511`「EXP」；kind 2 → `+10` `NUM200..209`（**绿**，无前置形、无符号）；kind 3 → `+0x14` `NUM300..309`（**蓝**）；kind 4 → `+0x28` `NUM500..509`（黄）前置 `NUM512`「$」；kind 5 → 清空字串、只画 `NUM513`「MISS」；kind 6 → `NUM514`「LEVEL UP」。hsl.pak `shape\num1xx…6xx` 65 条记录（`ignored/r12-num100/sheet.png` 为本 lane 渲染的对照图，不入库）。即**原作对回复不显示「+」或「−」字形，用绿色数字区分回复、蓝色区分 MP、红色为伤害、MISS 为落空**。

落地（表现层）：`BattleCombatCutin.strike_feedback` 对带 `support_effects` 的回执改走 `support_feedback_parts`——`N HP`／`N MP`／净化标签（解毒／無中毒 等）／全无时 `未回復`，地图侧 `_present_status_effects` 复用同一来源（`feedback_parts`，带 kind 的分项）。绝技切入的结果行因此显示「萬息集氣法 · 27 HP」而不再是「−0」。`run_presentation_contract_tests.skill_effect_contracts` 加 5 条断言（含脚本切入实际播放到 aniShowHitResult 的文字）。

**2026-09-23 lane K1：增益绝技的结果行。** 同一 `0x404643` 读法下，`kind 0` 只在 HP 变化 `ecx>0` 时生成，HP／MP 变化皆 0 时要么不出数字（状态已生效标志 `*0x4c13f0` 非 0）要么 `kind 5` MISS——原作不会对增益绝技显示数字「0」。重制此前 `special_stat` 回执（千羽風靈壁／激怒／精神統一：`damage 0`、无 `support_effects`、带 `stat_effects`）落到伤害分支，切入结果行为「精神統一 · 0」。落地：`feedback_parts` 收 `stat_effects`（「防禦 +N · N回」／「攻擊增益解除」，即地图侧 `_present_status_effects` 原有的说明，移入同一函数、地图显示不变），`strike_feedback` 对非空 `stat_effects` 走分项；效果为空的回执 `hit=false` 仍读「閃避」（对应 `kind 5`）。说明文字是重制表现（remake-invented）；`*0x4c13f0` 由增益分支写入与否未核（未原执行），故「成功增益在原作不显示数字」不作等价声明。`run_presentation_contract_tests.skill_effect_contracts` 加 5 条（双增益顺序、说明无配色、解除、空效果＝閃避、精神統一 脚本切入实播到 `aniShowHitResult` 的文字）；消融：去掉 `strike_feedback` 的 `stat_effects` 分支 → 3 条失败（「0」／「精神統一 · 0」），去掉 `feedback_parts` 的增益分项 → 4 条失败。`special_utility`（金之手／銀之手／高級金之手／天鳴覺醒／獅子吼）无伤害时切入同样显示「0」——不属支援类，本 lane 未改，留负责人（已由 lane P7 按原读法关闭，见下「功能绝技的结果显示」）。

**2026-09-24 lane P1（负责人决定）：按原作配色、去符号。** 地图数字（`BattlePresentation` 的普通伤害／状态与回复分项、`MagicImpactPresentation` 的法术伤害、`BattleTurnEndCue` 的回合末回复／轉化、`show_item_use` 的道具回复）与切入结果行的数字都不再带「+／−」字形；地图侧每个分项一个 Label，按 kind 取 `game/battle/runtime/ShowNumberStyle.gd` 的颜色，同一目标的分项自下而上叠放（伤害在下、回复／MP 在上，当时读作原 `kind 3` 的 `y-0x28` 叠放；间距为重制值。lane DIGITS 更正：原版 MP 数字与 HP 数字同点、hold 40 tick，见上）。颜色取自各数字图的调色板（resource-derived，`hsltools.sources.pak`＋`shp` 解码 hsl.pak `SHAPE\NUM1xx／2xx／3xx／513`，取非黑像素频次前列的中间色）：

| kind | 数字图 | 采样到的填色（RGB） | ShowNumberStyle |
| --- | --- | --- | --- |
| 0 伤害 | NUM100–109 | 高光 (255,238,238)、主色 (255,182,180)、阴影 (255,125,123) | `DAMAGE` = (255,125,123) |
| 2 回复 | NUM200–209 | (189,230,164)／(148,218,115)／(115,206,74) | `HEAL` = (148,218,115) |
| 3 MP | NUM300–309 | (189,226,246)／(131,206,238) | `MP` = (131,206,238) |
| 5 MISS | NUM513 | 红 (255,97,98) 描边＋白 (255,255,255) | `MISS` = (255,97,98)（文字仍为重制的「闪避」） |
| 1 EXP／4 $ | NUM400／500 | 紫 (222,178,255)／黄 | `BattleAftermath` 既有紫／黄不改 |

切入结果行是一个 Label（技能名＋分项＋击倒／連擊 说明），不按分项上色；HP／MP 后缀与净化标签、中毒／禁魔 等状态说明为重制文字。地图 case 0 伤害数字的弹跳与原字形已由 `DamageNumberFloat` 复刻（[地图姿势与飘字包 §3](../runtime_observations/map_pose_floaters/README.md#3-红色伤害数字0x408580-kind-0)）；切入结果行与风火水地图数字的原字形已由 lane DIGITS 落地（见文末 DIGITS 段）；**仍未核对**：`0x4c6f74` 由哪些结算路径写入（Heal 分支直接显示而非经脚本）；均为反编译阅读，未原执行。

### 功能绝技的结果显示（2026-09-25 lane P7-utility-special-text，static-derived；r2 阅读 hsl01.exe，未原执行）

绝技守方脚本的命中 opcode（`0x4047c7`）对每个目标：清 `*0x4c6f74`／`*0x4c6f78`，调 `0x40b8f0(caster, target, …)`（＝`0x40aa80(…, channel 1)`），把返回值（即 `0x40aa80` 的 EXP：各分支即时换算 `iStack_14` 之和，或尾部 `0x40a5d0`）加进 `*0x4c13f0`（`0x40484d..0x404861`）与 `*0x4c2c7c`，再把目标 HP 前后差记进 `*0x4c6f74`、MP 差记进 `*0x4c6f78`（`0x404867..0x40489f`）。`*0x4c13f0` 只在攻方开场 opcode 清零（`0x40438c`），所以上文「状态已生效标志」实为**本次施放已得 EXP 之和**。`0x40aa80` 在 channel 1 下自己不生成任何数字（`0x4084e0` 的三处调用都要求 `param_5 == 0`，即魔法通道）。于是 `aniShowHitResult`（`0x404643`）对功能绝技：HP 损失 >0 → 红色 kind 0 数字；HP／MP 皆 0 且 `*0x4c13f0 ≠ 0` → 跳到 `0x404772`，**什么都不显示**；皆 0 且 `*0x4c13f0 == 0` → kind 5 MISS。

各功能分支何时给出非零 EXP（`0x40aa80` 反编译，行号见上表）：StealItem 偷到一件 → `rand(level)+1` 即时换算（`0x40b674`）；CancelActive／ActiveAgain 的队列 helper（`0x407550`／`0x4075a0`）返回 1 → 同样即时换算；StealGold 命中 → `amount/2 + rand(amount/2)` 直接计入（`amount < 2` 时为 0）。门控掷骰失败、八个槽位掷骰全落空、队列 helper 返回 0 时返回 0。两个队列 helper 只改队列字、不画任何东西（`0x407550`／`0x4075a0` 全文无绘制调用）。

偷到的东西在行动结算时显示：`0x4416bc` 以 `(actor, *0x4c2c7c, *0x4c2c84)` 调 `0x442720`；case 0 画 EXP 浮字（kind 1），case 2 画 `*0x4c2c84` 的「$」浮字（kind 4）——StealGold 在 `0x40b556..0x40b574` 把本次所偷加进 `*0x4c2c84`（玩家侧封顶目标携带金、敌方侧从队伍金扣，两边都加），与掉落金同一个数；case 4 待领池非空则开 GetItem 窗（StealItem 经 `0x44f2d0` 放进同一待领池，见 [GetItem 窗](original_getitem_window.md)）。原字串表（`content/imported/hsl` 各 RESOURCE／message 文字）中无偷窃／再行动／取消行动的结果字串（negative-evidence：检索「偷」「竊」「行動」只命中剧情对白）；原录像参考帧中无这些绝技（negative-evidence）。

| 绝技 | 原作切入结果（依据） | 重制前 | 重制后 |
| --- | --- | --- | --- |
| 金之手／高級金之手（StealItem） | 偷到：无数字；之后 GetItem 窗。全落空：MISS | 「金之手 · 0」 | 「金之手」；全落空「金之手 · 閃避」；偷到的物品照旧进待领（战利品窗） |
| 銀之手（StealGold） | 偷到 ≥2：无数字；结算「$ N」浮字。<2 或未命中：MISS | 「銀之手 · 0」，无「$」浮字 | 「銀之手」＋结算「$ 37」浮字（施法者头上） |
| 竊殺（Attack＋StealGold） | 红色伤害数字；结算「$」＝掉落金＋所偷 | 伤害数字；「$」只含掉落金 | 伤害数字；「$」＝掉落金＋所偷，一个浮字 |
| 天鳴覺醒（ActiveAgain） | helper 成功：无数字。失败／未命中：MISS | 「天鳴覺醒 · 0」 | 「天鳴覺醒」 |
| 獅子吼（CancelActive，两行） | 同上 | 「獅子吼 · 0」 | 「獅子吼」 |
| 吸血劍（Attack＋StealHP，两行） | 红色伤害数字；施法者回复不显示数字 | 伤害数字 | 不变 |

落地：`BattleCombatCutin.shows_miss` 按上述条件（`special_key == special_utility`、HP 损失 0、回执 `experience_basis.points`＝该 EXP 返回值为 0 → MISS），`strike_feedback` 对 HP 损失 0 的已生效功能绝技返回空，`with_feedback` 在空结果时不加「 · 」；地图侧 `_present_impact` 的颜色改按 `shows_miss`。`BattleAftermath` 的「$」浮字加上回执 `gold_effects` 的数额（与掉落金合为一个，主人为掉落金的击杀者，否则为施法者）。`run_presentation_contract_tests.utility_special_contracts` 守着；消融：去空结果分支 → 10 条失败（「· 0」回来），`shows_miss` 不读 EXP → 3 条失败，浮字不加 `gold_effects` → 3 条失败，脚本切入改回无条件「 · 」→ 4 条失败。边界：`*0x4c13f0` 在多目标施放中跨目标累积（先偷到后落空的第二个目标原作不出 MISS），重制按每目标 `experience_basis` 判定；功能绝技命中但未生效时守方仍切受击帧（`aniProcessHitMiss` 读 `hit`），与原作是否一致未核；敌方偷窃的 EXP／「$」浮字依既有结算合同（敌方 fixed_template 无 EXP 浮字）。

UI6（2026-09-25，用户定照原版只显示数字）：切入结果行不再带技能名（`with_feedback` 删去，改 `BattleCombatCutin.show_result`），落空读「MISS」（NUM513 的字），数字不带 HP／MP 后缀，字色按 `result_color`（伤害红／回复绿／MP 蓝／MISS）；上表「重制后」列的「金之手」「天鳴覺醒」等今为空行，「金之手 · 閃避」今为「MISS」。增益与净化说明、「未回復」仍是重制文字（无原字形）。

DIGITS（2026-09-26，照原版字形）：数字不再是字体 Label，统一走 `game/battle/scene/ResultNumberFloat.gd`（`0x4084e0` 的 kind 0／2／3／5：红 NUM100..109 逐位揭示不上浮、绿 NUM200..209、蓝 NUM300..309、MISS＝NUM513；kind 2／3／5 层级 16 停 16 tick 后每 2 tick 减 1、第 46 tick 删除，每 2 tick 上 1 px；hold 期间不画，至少 1 tick；首位 x − 7×(位数−1)、间距 14，无符号）。出现点：普通一击特写 (320,200)、命中后 40 tick（`0x40424c`→`0x404290`，只在命中且有伤害时，落空不出 MISS）；脚本一击 `aniShowHitResult` (320,180)，回复与 MP 同点、MP hold 40；地图一击与法术（`0x40aba0`）目标 (x, y−0x34)；道具 (x, y−0x30)；回合末 (x, y−48)。`result_color` 已删；结果行 Label 只剩无原字形的说明（增益、净化、未回復、武器效果）。

## 已登记函数

`0x40a7b0` skill_numeric_roll_channel_proc（与 [原绝技元素](original_special_element.md) 同一登记）、`0x406fe0` triangular_range_sample、`0x4075a0` reactivate_consumed_actor_slot、`0x4074a0` advance_turn_queue_slot_with_wrap；2026-09-21 新增 `0x40c620` build_actor_skill_buckets、`0x40dd80` select_special_bucket_skill（更正 core_logic 沿用的 `ai_movement_helper` 标签）、`0x40df70` plan_special_bucket_cast、`0x40e0e0` has_special_heal_bucket、`0x40e100` has_special_cure_for_mask、`0x40e180` has_missing_special_positive_state；2026-09-22 新增 `0x4084e0` spawn_show_number、`0x408580` show_number_object_process（`0x403954` 是对象过程内的 case 入口、非函数起点，只在正文登记）（`content/generated/hsl/static/hsl01/known_functions.json`）。

## 通道差异带来的实现分工

| 家族 | policy | 数值 helper 路径 |
| --- | --- | --- |
| 状态（弱體箭／獸神怒號／影纏） | `native_special_status` | `SpecialStatusRules` → `StatusApplicationRules.resolve` 以 `PoisonArrowRules.roll` 为 roller |
| 支援（萬息四技） | `native_special_support` | `SupportMagicRules`，proc1 用 `SpecialDamageRules.roll` |
| 增益（千羽風靈壁／激怒／精神統一） | `native_special_stat` | `StatMagicRules`，proc1 用 `SpecialDamageRules.roll`，proc3 用无 `+0xd4` 项的三角取值；`0x60` 按 DefUp→AttUp 顺序各自抽样 |
| 队列／吸取（天鳴覺醒／獅子吼／吸血劍／竊殺／金之手） | `native_special_utility` | `SpecialUtilityRules`，proc0 门控后产出 turn／gold／item 效果提案，PlayLoop 唯一提交 |

`SkillTargetRules.is_support` 改为原 mode3 掩码判定（`0x18f62`，与 `native_target_mode` 同源）；既有 2／0x20／0x40／0x400 的分类不变，0x4000 退魔与偷取／取消位仍为敌方目标。

## 边界

- 本包全部为反编译阅读，未运行原指令；幅度／持续／贡献按代码逐行读出，随机流顺序与原全局 RNG 的等价性未声明。
- StealGold／StealItem 的金币／物品归属涉及全局 `0x4c1bcc`／`0x4c2c84` 与待领取集合，本波未接入（后续波已接入；`+0x196` 偷窃加成字见上「偷窃加成字」段）。
- HealMP／StealHP／StealItem 的两次 EXP 换算已按 `0x40aa80` 五处 `call 0x40a5d0` 的读法分开（见上「即时换算与尾部换算」）；仍为反编译阅读，未做有界原执行。
- 金之手 的 `+0x196` 装备偷取加值已由 R27 导入、R32 原生回执核对（见上「偷窃加成字」）。
- 天鳴覺醒／獅子吼 对无可再激活／可取消槽目标的拒绝是重制交互取舍；原作照付 ST 并返回 0。
- 特殊技能的切入演出复用 氣刃斬 的面板／弹道（`BattleCombatCutin._process_skill`），无专属素材（provisional 重制表现）；范围与替换路径见下「专属特效素材」段。
- AI：`AISkillPlanning` 对无原桶（0x407010）的技能行（獅子吼／金之手／萬息降靈法）跳过；绝技通道支援／净化已接入（见下「AI 绝技通道支援」），AI 净化仍只以中毒为触发；进攻绝技（桶 3／4）按 `0x40df70`→`0x40dd80` 的 (first, fallback) 桶 walk 回放（见下「进攻绝技桶 3／4 的回放」），`0x40d4e0` 单次共用抽取仍为重制组合边界。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/battle/scene/BattleCombatCutin.gd` strings：result numbers carry no sign glyph — defProcShowNumber digit sets; a utility special with no HP change shows no result when its 0x40aa80 EXP return is non-zero and MISS when it is zero — 0x40485d／0x40464f, section 功能绝技的结果显示; 0x404643 spawns a number or MISS and nothing else, so the line carries the number alone — no 連擊／反擊／暴擊／擊倒 caption, no HP／MP suffix, no skill-name head, a miss reads MISS in the NUM513 colour, heal／MP in their digit colours — UI6, user 2026-09-25 照原版
- `game/sim/loop/BattleLoopRewards.gd` rules：0x44f2d0 StealItem into the pending collection, 0x40b4e8 StealGold

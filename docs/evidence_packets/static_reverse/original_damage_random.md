# 伤害／命中随机流：原版生成器、单一状态、随存档保存

> evidence: static-derived · status: live · functions: 0x403860, 0x406fe0, 0x409be0, 0x40a5d0, 0x40aa80, 0x40e430, 0x42c720, 0x42c780, 0x42c7e0, 0x42e070, 0x42e640, 0x4414a0, 0x4423c0, 0x4445cf, 0x457410, 0x458bb0, 0x458c10, 0x458c80 · tools: export_exchanges.gd, hsltools/evidence/damage_random.py, hsltools/probes/_exchange_check.py, run_tests.gd · updated: 2026-09-26

## 结论

原版战斗结算只用一条伤害随机流：生成器是`0x458c10`，`rand(n)`是`0x458c80`，状态是两个32位字`0x4c3044`／`0x4c3040`。`0x42c720`（原始抽取）和`0x42c780`（`rand(n)`）先把这两个字换进全局生成器`0x4795d4`／`0x4795d8`，抽完再换回，所以全局流（AI决策、掉落、出生调级、脚本随机）不受影响。新游戏只在两个字都为0时播种一次：word0＝时钟`t`，word1＝`~t`（`0x42ca47`）。存档偏移`0x38`／`0x3c`保存这两个字（`0x42e070`内`0x42e342`写入）；读档（`0x42e640`内`0x42e980`）默认把它们读回，只有命令行开关`random`（解析`0x457410`，置`0x4c1aec`）才跳过。所以原版读档后重复同样操作，伤害、命中、暴击、状态和回复结果完全相同。

重制的普通交锋已和原程序整段逐值对拍：敌人回合的 1111 次交锋里，每次抽取、命中／伤害／暴击／反击／经验以及交锋末状态都相同，见[整段交锋对拍](#整段交锋对拍)。对拍中查出一处差异并已改正：NPC 进程发起的交锋不回写命中加成（`0x442405`）。

## 原生执行对拍

[机器包](original_damage_random.json)由`hsl generate damage_random`在unicorn里执行hsl01.exe的原指令生成：4组状态（含`0x7fffffff`／`0x80000000`等符号边界），每组连续1000次`0x458c10`，再连续1000次`0x458c80`（20种循环上限：0、1、`0xffff`、`0x10000`、`0x7fffffff`、负数、`-0x80000000`等），逐值记录返回和终态。每组另测`rand(0)`与两层包装：包装后的结果与直接跑生成器一致，全局字（哨兵值）保持不变。9处原字节（生成器、播种、包装、新游戏播种、存档读写）按字节钉住。独立Python模型逐值复算，离线`hsl check damage_random`不需要unicorn。

| 原指令 | 确认规律 |
| --- | --- |
| `0x458c10` | `a1=a+1`、`b1=b-1`、`k=b1&31`；`a'=sar(a1,(32-k)&31)+shl(a1,k)`；`k2=a'&31`；`b'=shl(b1,(32-k2)&31)+sar(b1,k2)`；返回`a'+b'`。x86移位计数取低5位 |
| `0x458c80` | `n==0`返回0且**不推进**；有符号`n<=0xffff`（含负数）取`(r&0xffff) idiv n`，被除数非负，结果等于`(r&0xffff) mod |n|`；更大的`n`取无符号`r mod n` |
| `0x42c720`／`0x42c780` | 换入伤害字、调用生成器、换出；全局状态不变 |
| `0x42ca47`（`0x42c7e0`内） | 两个伤害字都为0时才播种：`t`／`~t` |
| `0x42e342`／`0x42e980`（`0x42e070`／`0x42e640`内） | 存档偏移`0x38`／`0x3c`写入与读回；`[0x4c1aec]!=0`时读档不恢复 |

## 谁从这条流抽

静态调用点（`0x42c780`共56处、`0x42c720`1处）只在战斗结算：命中／暴击`0x403860`、三角分布`0x406fe0`、武器效果`0x409110`–`0x409310`、元素加成`0x409af0`、物理伤害`0x409be0`（含一次原始抽取`0x409d06`）、物品数值区间`0x409e10`、经验`0x40a5d0`、技能数值`0x40a7b0`、技能目标效果`0x40aa80`（含偷窃）、最终行动回复`0x40e430`、反击门槛`0x442669`（`0x4423c0`内）。一次交锋的顺序是反击门槛`rand(100)+1`→伤害→命中`rand(100)`→暴击，与重制`CoreCombatRules.resolve_attack`的抽取顺序相同。AI决策`0x40c770`／`0x40c110`／`0x40dd80`／`0x40bb80`、掉落`0x44f580`、出生调级`0x40e870`、脚本和对象安装都直接调用`0x458c10`／`0x458c80`，属于全局流，不在本包范围内。

## 整段交锋对拍

`hsltools/probes/_exchange_check.py record`借`_enemy_level.run_level`的观察者钩子，在原版敌人回合里逐次记下每次交锋`0x4423c0`的数据：开场的两个伤害字、双方活记录（HP `+0xd8`、EXP `+0x88`、命中加成 `+0xb0`、连杀字 `+0xa8`、战斗字）、每次伤害流抽取及其调用点、每一下的命中／暴击／伤害（`0x403860`）和发放（`0x442720`）。`tests/export_exchanges.gd`从同一开场状态（格位与 HP、双方活记录、`damage_rng`＝原版两个字）走重制`BattleLoopCombat._resolve_exchange`。`compare`逐列对照：命中／伤害／暴击／反击／反击伤害／经验、每次抽取的上界与值、交锋末双方活记录与伤害字。

局面有两个。第 51 关用首控局面`first_control`，注入 026_1／026_2／021_1 与我方相邻，12 个伤害种子，每种子 3 回合。第 53 关用原版开局，250 个伤害种子，每种子 8 回合。`growth` 为 false 时原版只把成长字 `+0x1f8`／`+0x1fa` 清零，玩家出生 `0x44346e` 照样调 `0x40e870`：先由 `0x40e800` 按四项基础属性推等级，kind3 在 `0x40e89d` 跳到 `0x40eb18` 刷新并回满。第 53 关剧情插入的緹娜因此由模板 L1、HP 35/35、攻击 37 变成 L2、36/36、38（模拟器实测，成长字 0,0 与 20,3 结果相同）。重放的玩家也先走同一推断（`InitialRosterGrowthRules.prepare_player`），两关都没有覆盖。lane TINA53 于 2026-09-26 两关重录重放：结果行与下面一字不差，`overrides` 为 0 行；此前的 989 行覆盖都是重放漏了这一步。

结果行：

```
EXCHANGE_COMPARE levels=51,53 rows=1111 agree=1111/1111 enemy_on_player=1027/1027 combos=3 draws_same=1111/1111 end_same=1111/1111 missing=0 strikes=1219 misses original=40 remake=40 crits original=112 remake=112 counters original=108 remake=108 hit_bonus_rows=2 record_cleared=250 dead_bonus=2
```

- 敌人打玩家共 1027 行，分三组攻守：021→雷歐納德、026→雷歐納德、023→緹娜。每一行的抽取次数、每次抽取的值、各列结果和交锋末状态都相同。
- `record_cleared=250`：緹娜阵亡即收场，原版关卡结束会清零整条记录，这些行的末状态只比 HP。
- `dead_bonus=2`：见下文“阵亡记录的命中加成”。

摘录下面 32 行敌人打玩家：第 51 关种子 1–6 的全部 18 行、第 53 关种子 1–3 的全部 11 行，再加 3 行第 53 关落空。经验列是“攻方/守方”，反击列的 H 是命中、C 是暴击。

| # | 局面 | 伤害种子 | 回合 | 攻 → 守 | 原版 命中／伤害／暴击／反击／反击伤害／经验 | 重制 同左 | 伤害流抽取 | 交锋末状态 | 一致 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | L051 | 1 | 1 | actor021_1 → leonard | Y ／ 8 ／ N ／ N ／ - ／ 5/0 | Y ／ 8 ／ N ／ N ／ - ／ 5/0 | 9／9 同 | 同 | ✓ |
| 2 | L051 | 1 | 2 | actor021_1 → leonard | Y ／ 9 ／ N ／ Y(H) ／ 18 ／ 7/11 | Y ／ 9 ／ N ／ Y(H) ／ 18 ／ 7/11 | 16／16 同 | 同 | ✓ |
| 3 | L051 | 1 | 2 | actor021_4 → leonard | Y ／ 8 ／ N ／ Y(C) ／ 30 ／ 0/36 | Y ／ 8 ／ N ／ Y(C) ／ 30 ／ 0/36 | 17／17 同 | 同 | ✓ |
| 4 | L051 | 1 | 3 | actor021_2 → leonard | Y ／ 6 ／ N ／ N ／ - ／ 37/0 | Y ／ 6 ／ N ／ N ／ - ／ 37/0 | 9／9 同 | 同 | ✓ |
| 5 | L051 | 2 | 1 | actor026_2 → leonard | Y ／ 5 ／ N ／ Y(H) ／ 22 ／ 0/22 | Y ／ 5 ／ N ／ Y(H) ／ 22 ／ 0/22 | 16／16 同 | 同 | ✓ |
| 6 | L051 | 3 | 1 | actor021_1 → leonard | Y ／ 8 ／ N ／ N ／ - ／ 6/0 | Y ／ 8 ／ N ／ N ／ - ／ 6/0 | 9／9 同 | 同 | ✓ |
| 7 | L051 | 3 | 2 | actor021_1 → leonard | Y ／ 10 ／ N ／ N ／ - ／ 6/0 | Y ／ 10 ／ N ／ N ／ - ／ 6/0 | 9／9 同 | 同 | ✓ |
| 8 | L051 | 3 | 2 | actor021_4 → leonard | Y ／ 8 ／ N ／ N ／ - ／ 5/0 | Y ／ 8 ／ N ／ N ／ - ／ 5/0 | 9／9 同 | 同 | ✓ |
| 9 | L051 | 4 | 2 | actor021_4 → leonard | Y ／ 8 ／ N ／ Y(H) ／ 15 ／ 5/7 | Y ／ 8 ／ N ／ Y(H) ／ 15 ／ 5/7 | 16／16 同 | 同 | ✓ |
| 10 | L051 | 4 | 3 | actor021_3 → leonard | Y ／ 11 ／ N ／ N ／ - ／ 8/0 | Y ／ 11 ／ N ／ N ／ - ／ 8/0 | 9／9 同 | 同 | ✓ |
| 11 | L051 | 5 | 2 | actor021_1 → leonard | Y ／ 7 ／ N ／ N ／ - ／ 3/0 | Y ／ 7 ／ N ／ N ／ - ／ 3/0 | 9／9 同 | 同 | ✓ |
| 12 | L051 | 5 | 2 | actor021_4 → leonard | Y ／ 10 ／ N ／ N ／ - ／ 7/0 | Y ／ 10 ／ N ／ N ／ - ／ 7/0 | 9／9 同 | 同 | ✓ |
| 13 | L051 | 5 | 3 | actor021_1 → leonard | Y ／ 6 ／ N ／ N ／ - ／ 2/0 | Y ／ 6 ／ N ／ N ／ - ／ 2/0 | 9／9 同 | 同 | ✓ |
| 14 | L051 | 5 | 3 | actor021_4 → leonard | Y ／ 9 ／ N ／ N ／ - ／ 7/0 | Y ／ 9 ／ N ／ N ／ - ／ 7/0 | 9／9 同 | 同 | ✓ |
| 15 | L051 | 6 | 1 | actor021_1 → leonard | Y ／ 9 ／ N ／ N ／ - ／ 3/0 | Y ／ 9 ／ N ／ N ／ - ／ 3/0 | 9／9 同 | 同 | ✓ |
| 16 | L051 | 6 | 2 | actor021_1 → leonard | Y ／ 6 ／ N ／ N ／ - ／ 2/0 | Y ／ 6 ／ N ／ N ／ - ／ 2/0 | 9／9 同 | 同 | ✓ |
| 17 | L051 | 6 | 2 | actor021_4 → leonard | Y ／ 8 ／ N ／ N ／ - ／ 6/0 | Y ／ 8 ／ N ／ N ／ - ／ 6/0 | 9／9 同 | 同 | ✓ |
| 18 | L051 | 6 | 3 | actor021_4 → leonard | Y ／ 10 ／ N ／ N ／ - ／ 7/0 | Y ／ 10 ／ N ／ N ／ - ／ 7/0 | 9／9 同 | 同 | ✓ |
| 19 | L053 | 1 | 4 | enemy023_2 → tina | Y ／ 8 ／ N ／ N ／ - ／ 8/0 | Y ／ 8 ／ N ／ N ／ - ／ 8/0 | 8／8 同 | 同 | ✓ |
| 20 | L053 | 1 | 4 | enemy023_3 → tina | Y ／ 10 ／ N ／ N ／ - ／ 10/0 | Y ／ 10 ／ N ／ N ／ - ／ 10/0 | 8／8 同 | 同 | ✓ |
| 21 | L053 | 1 | 5 | enemy023_2 → tina | Y ／ 10 ／ N ／ N ／ - ／ 8/0 | Y ／ 10 ／ N ／ N ／ - ／ 8/0 | 8／8 同 | 同 | ✓ |
| 22 | L053 | 1 | 5 | enemy023_3 → tina | Y ／ 11 ／ N ／ N ／ - ／ 36/0 | Y ／ 11 ／ N ／ N ／ - ／ 36/0 | 8／8 同 | 同 | ✓ |
| 23 | L053 | 2 | 4 | enemy023_2 → tina | Y ／ 13 ／ N ／ N ／ - ／ 12/0 | Y ／ 13 ／ N ／ N ／ - ／ 12/0 | 8／8 同 | 同 | ✓ |
| 24 | L053 | 2 | 4 | enemy023_3 → tina | Y ／ 20 ／ Y ／ N ／ - ／ 20/0 | Y ／ 20 ／ Y ／ N ／ - ／ 20/0 | 9／9 同 | 同 | ✓ |
| 25 | L053 | 2 | 5 | enemy023_2 → tina | Y ／ 7 ／ N ／ N ／ - ／ 29/0 | Y ／ 7 ／ N ／ N ／ - ／ 29/0 | 8／8 同 | 同 | ✓ |
| 26 | L053 | 3 | 4 | enemy023_2 → tina | Y ／ 9 ／ N ／ N ／ - ／ 9/0 | Y ／ 9 ／ N ／ N ／ - ／ 9/0 | 8／8 同 | 同 | ✓ |
| 27 | L053 | 3 | 4 | enemy023_3 → tina | Y ／ 8 ／ N ／ N ／ - ／ 7/0 | Y ／ 8 ／ N ／ N ／ - ／ 7/0 | 8／8 同 | 同 | ✓ |
| 28 | L053 | 3 | 5 | enemy023_2 → tina | Y ／ 12 ／ N ／ N ／ - ／ 11/0 | Y ／ 12 ／ N ／ N ／ - ／ 11/0 | 8／8 同 | 同 | ✓ |
| 29 | L053 | 3 | 5 | enemy023_3 → tina | Y ／ 15 ／ Y ／ N ／ - ／ 36/0 | Y ／ 15 ／ Y ／ N ／ - ／ 36/0 | 9／9 同 | 同 | ✓ |
| 30 | L053 | 11 | 5 | enemy023_2 → tina | N ／ 0 ／ N ／ N ／ - ／ 0/0 | N ／ 0 ／ N ／ N ／ - ／ 0/0 | 6／6 同 | 同 | ✓ |
| 31 | L053 | 13 | 5 | enemy023_3 → tina | N ／ 0 ／ N ／ N ／ - ／ 0/0 | N ／ 0 ／ N ／ N ／ - ／ 0/0 | 6／6 同 | 同 | ✓ |
| 32 | L053 | 15 | 5 | enemy023_3 → tina | N ／ 0 ／ N ／ N ／ - ／ 0/0 | N ／ 0 ／ N ／ N ／ - ／ 0/0 | 6／6 同 | 同 | ✓ |

### 暴击率（同一组攻守，250 个种子）

| 攻 → 守 | 系列 | 原版 次数／命中／暴击 | 重制 次数／命中／暴击 | 暴击率字 |
| --- | --- | --- | --- | --- |
| enemy023 → 緹娜 | 主攻 | 989／957／83 | 989／957／83 | 8 |
| 緹娜 → enemy023 | 反击 | 92／90／18 | 92／90／18 | 18 |

- 83／957＝8.7%，符合暴击率字 8 的 8%。
- 伤害 19 在 957 次命中里出现 5 次，全部是暴击。伤害 ≥15 的 68 次命中全部是暴击，另有 15 次暴击落在 11–14。
- 第 53 关“19 出现 4／13”只是小样本：同一局面同一公式，原版与重制逐下相同。

暴击公式地址如下：
- `0x4425aa`把攻方`+0x1a2`（暴击率）压栈，交给冲击构造`0x406eb0`，写进冲击记录的`+0x4e`。
- `0x403860`内，`0x403f4f push 0x64`／`0x403f51 call 0x42c780`取`rand(100)`，`0x403f5f inc`加 1。
- `0x403f60 cmp eax, [imp+0x4e]`，`jg 0x403ff6`跳过即不暴击；暴击事件在`0x403ff1 call 0x401ac0`。
- 重制对应`CoreCombatRules.critical_impact`。

### 找到并改正的差异：命中加成只在玩家进程回写

初跑第 53 关 250 个种子：`agree=955/989`。989 行抽取全部相同，34 行末状态不同，都是敌人或緹娜的反击落空。原版交锋末`+0xb0`仍为 0，重制写成 9（`hit_bonus_after`＝0＋基础命中率/10）。

**分叉站点**：原版`0x442405 mov al, [esp+0x20]; test al, 2; jne 0x442452`。`0x4423c0`的第 4 阶段（阶段字`0x4c432c`＝4）按 mode 的 bit 1 跳过`0x44240d..0x44244c`：先把`[0x4c2c80]/10`（本下基础命中率，`0x442573`由`0x409a60`写入）加到攻方`+0xb0`，本下经验非 0 时再清零。

mode 由调用进程压入：
- 玩家进程`0x4445cf`压 0（主攻）、`0x444601`压 1（反击）。
- NPC 进程`0x4414a0`压 2（主攻）、`0x4414d3`压 3（反击）。

所以敌人／NPC 发起的交锋里，敌人自己和反击的玩家都不累加、也不清零命中加成。命中判定照旧读`+0xb0`（`0x442591`，不看 mode）。bit 0 是反击标记（`0x44251e`，反击伤害×80/100）。

重制对应`BattleLoopCombat._apply_strike`：原先每一下都写`hit_bonus_accum`，现在只在交锋发起方（反击时即本下的守方）`player_commandable`时写。发起方不可指令时回执的`hit_bonus_after`报活值不变。

- 钉测试：`run_ordinary_special_tests.gd`的`hit_bonus_process`，玩家／敌人发起 × 落空／命中，双方都反击。
- 消融：还原此改后`ORDINARY_SPECIAL_TESTS_FAIL count=6`，失败的正是 NPC 进程的 6 条。
- 改后第 53 关`989/989`，第 51 关`122/122`。

### 边界

- **只量了 NPC 进程**：回合裁判只跑敌人回合。玩家进程的“落空加基础命中率/10、经验非 0 清零”只有静态依据，玩家回合交锋没有在原程序里逐值对拍。
- **阵亡记录的命中加成**：原版阵亡单位的记录保留`+0xb0`，重制`BattlePlayLoop._set_defeated`把它清零。本批共 2 行，是第 51 关种子 10／11 的 actor026_1：它先前施法落空，交锋开始时带着 9／10，这次被 actor023_2 普攻击杀。活着的单位不读这个值，对照端把它列作`dead_bonus`，不比较；复活路径是否读它未查。
- **没覆盖到的分支**：技能在 NPC 进程是否回写`+0xb0`没有对拍；技能函数自己写回`+0xb0`，见[技能功能位](original_skill_function_bits.md)。另外两个静态分支本批局面没触发：守方`+0x18c` bit 4 时伤害减半（`0x40e2a0`），以及`0x409090(守方)`为 0 时不抽反击骰。

## 产品接入与保存

`DamageRandomStream`逐值实现上面的生成器和`rand(n)`，状态是两个u32字`[word0, word1]`（JSON中精确）。整场战斗只有这一份状态，放在PlayLoop的`damage_rng`键：

- **播种**：新战斗由`BattleLoopInit`以`seeded(reward_seed)`播种，即`[t, ~t]`。产品的`t`来自`BattleSceneRuntime._loop_seed()`：平时取时钟`Time.get_ticks_usec()`，无窗口运行取`HSL_RNG_SEED`。
- **谁在抽**：以下几类都从这一个状态抽，抽完立即写回。
  - 玩家与AI的普通交锋：反击门槛、伤害、命中、暴击、武器效果、经验。
  - 玩家与AI施法。
  - 道具数值区间：`ItemResolutionRules`，对应`0x409e10`。
  - 回合末回复与生命转魔力：`TurnEndRules`／`ResourceRecoveryRules`。
- **失败回滚**：动作被拒绝或目标无效时，状态回滚。
- **不走这里的**：AI的决策抽取（选目标、选技能、走位）仍用全局流。原先独立的`item_rng`／`recovery_rng`已删除。
- **`rand(0)`**：照`0x458c80`返回0且不推进。重制原先让它推进，现已改正；经验与特殊攻击的可调用回放仍记下这次调用。
- **单战存档**：`BattleCheckpoint`升为`hsl_battle_checkpoint.v5`，整个loop连同`damage_rng`一起保存，读档后从同一状态继续；`damage_rng`不是两个u32字就拒绝读档。v4存档按版本名拒绝，理由有二：v4的道具／回复收据记的是旧整数流，在新流上无法重证；给它另起新流，又会破坏“读档后同样操作得同样结果”。
- **战役承接**：`CampaignCarryRules.capture`把`damage_rng`写进承接。schema仍是v1，只多一个可选键。下一战`apply`读回，JSON浮点经`from_words`精确还原。分队关卡也带上它，因为原版存档只有一对字，这条流属于整个战役。缺这个键的旧承接照常接受，下一战重新播种，等同原版两字为0时重新播种。
- **收据**：道具与回合末收据记下抽样前后的状态。存档校验只要求收据自证：从抽样前状态重算，得到同样的抽样和抽样后状态。不再要求loop当前状态等于收据的抽样后状态，因为之后的交锋会继续推进同一条流。

测试有两组：
- `run_tests.gd`的`damage_order_cases`：用影子流逐次比对一次交锋的抽取上界`[100, 5|base+4, eff*30/100, half, half, (-1), 100, (100)]`。
- `save_load_cases`：在一场小战里先存档，连打三回合，再跑AI回合；然后读档，重复同样操作。逐次比对伤害、命中、暴击、状态和最终状态，并确认流确实推进过，而且换一个起始状态结果就不同。

## 复跑

```sh
python3 tools/hsl.py check damage_random
uv run --no-project --with 'unicorn>=2,<3' --with capstone python3 tools/hsl.py generate damage_random
tools/godot.sh --headless --script res://tests/run_all.gd -- run_tests.gd

# 整段交锋对拍（第 53 关 250 个种子约 5 分钟，第 51 关约 35 秒）
U='uv run --no-project --with unicorn==2.1.4 python3 tools/hsltools/probes/_exchange_check.py'
$U record --level 51 --board docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json \
    --board-key first_control --set 026_1.cell=15/16 --set 026_2.cell=16/17 --set 021_1.cell=14/17 \
    --damage-seeds 1-12 --turns 3 --out ignored/dmgcheck/L51_12.json
$U record --level 53 --damage-seeds 1-250 --turns 8 --out ignored/dmgcheck/L53_250.json
tools/godot.sh --headless --script res://tests/export_exchanges.gd -- --cases ignored/dmgcheck/L51_12.json --out ignored/dmgcheck/L51_12_remake.json
tools/godot.sh --headless --script res://tests/export_exchanges.gd -- --cases ignored/dmgcheck/L53_250.json --out ignored/dmgcheck/L53_250_remake.json
$U compare ignored/dmgcheck/L51_12.json ignored/dmgcheck/L51_12_remake.json ignored/dmgcheck/L53_250.json ignored/dmgcheck/L53_250_remake.json
```

## 仍未支持

原版时钟播种分支`0x457830`没有执行，只是字节钉住；重制的`t`是产品时钟或`HSL_RNG_SEED`，不会和某次原版开局的具体数值相同。全局流由lane RNG-A接入`GlobalRandomStream`（同一生成器，状态对应`0x4795d4`／`0x4795d8`，不入存档）：AI决策、出生调级、新援、开局随机槽、opcode 86／99的随机位置已改抽它；掉落（`0x44f5d3`）、出生随机携带（`0x407c86`）与opcode 121（`0x450fe6`／`0x451012`／`0x451075`）原版也抽全局流（lane RNGC 实测／静态），opcode 107／108原版不抽随机数，见[差异清单](parity_gap_inventory.md)的`rng-streams`。

- **AI决策**：产品里AI每回合新建一个随机源来做决策。读档后，AI的选择可能和存档前那次不同，伤害流的消耗顺序也会随之不同。存档一致性测试固定了决策随机源，所以不受影响。
- **交锋内抽取顺序**：由`order_cases`对照原版的静态顺序。整段普通交锋已在原程序里逐值对拍，但只限敌人回合，见[整段交锋对拍](#整段交锋对拍)。武器效果（`0x409110`–`0x409310`）、元素加成、偷窃等分支各自抽几次，仍只在各自的规则测试里对照过原版，本批局面没有触发它们。

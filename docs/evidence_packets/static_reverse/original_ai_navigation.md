# 原 AI：持有目标、等待、守备固定点、追击走法与攻击站位

> evidence: static-derived; runtime-measured: 原版抽签回放、移动力 0 的普通进攻出口; resource-derived: EVEF 字值; provisional: 固定点逐格路线 · status: live · functions: 0x40c9a0, 0x40cca0, 0x40d530, 0x40d800, 0x40d8b0, 0x40eb80, 0x40ed50, 0x40f200, 0x40f440, 0x40f8b0, 0x40fa80, 0x40fb20, 0x410a50, 0x411080, 0x4111a0, 0x411a30, 0x411b90, 0x413390, 0x413740, 0x42bd50, 0x43f413, 0x43fbd6, 0x45ec32, 0x45ec63 · tools: hsltools/levels/seed.py, hsltools/probes/_normal_attack_trace.py, hsltools/probes/ai_navigation.py, hsltools/probes/ai_replay.py, run_ai_navigation_tests.gd, run_battle_reward_tests.gd · updated: 2026-09-30

## 结论

- 原版：`object+0x88` 持有目标，保留用曼哈顿域、新查询用圆域，`ai_lock` 概率决定是否换；`wait_round` 每行动减一，受伤／异常／近敌提前结束；`ai_fixed` 是以锚点为中心的半径；追击与回固定点共用 `0x4111a0 → 0x411080` 精化（半径 `max(18,移动力)` 洪泛取曼哈顿最近可停格、半径 −2 重复）；攻击站位由 `0x40d8b0 → 0x413390` 按半格偏置距离降序选取，并以地形射程到站复查（static-derived；118 组原指令执行＋反汇编读法）。移动力 0 的行动者：站位洪泛半径 0（`0x40f200` 在 `0x40f24b` 不写中心格就返回），`0x40d8b0` 恒 0，普通进攻在 `0x440094` 读到移动力 0 即 `0x441eb8` 结束回合，不出手也不追击；侧走与濒死检查的站位查询同样落空（static-derived；runtime-measured：劫數 · 地劫神（LEVEL059）5 格 24 局＋2–4 格 6 局有效（另 18 局在 `0x4603ca` 提前停机）0 普攻）。
- EVEF 实例回调 `0x42bd50` 把实例字写进物品槽与 25 个 AI／调级／装备字段；敌友走同一 dispatcher，无武器的普通路径不移动（static-derived；实例字值 resource-derived）。
- 重制：`game/sim/AINavigationRules.gd`（`approach_home`／`approach_point`／`attack_stations`／`attack_station`／`target_in_range`）、`game/sim/loop/BattleLoopAI.gd`、`game/sim/ActorInitializationRules.gd` 复刻上述链；第一战原版第 1 回合 12 个 AI 落点全部落在重制可产出集合内（见 [battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)）。
- 追击精化的洪泛就是移动洪泛：`0x4111a0` 传末参 0，`0x411080` 取 `0x40f440`（受地图边界）与行动者 `0x40bab0` 模式（P 2／E 3／N 7，飞行 6），每步代价＝上坡差＋`0x40eb80` 的 1／2、高差 ≥3 与敌方占位（mask）挡；洪泛按上下左右深度优先、每格存最大余量；候选按缓冲逐行扫描、像素曼哈顿距离取最近，某一级无候选则目标点不变；目标点是持有目标的像素位置，不是射程格。`no_attack` 单位（模板 +0xa0 bit 2）在 `0x43f413` 直接结束回合，不追击不施法；追击选中的格不可能是自身格（有单位跳过），`0x410a50` 自身格返回 0 只出现在站位＝自身格且打不到时，回合结束（static-derived，反汇编读法）。原版裁判喂原版抽签回放：玩家第 1 场 · 棄卒（LEVEL051）r1 32 种子 352/352、第 1 场与第 2 场 · 惡夢的終曲（LEVEL052）开场 32 种子 894/896 一致（其余 2 行落点一致、目标标签归口径）（runtime-measured）。
- 重制：`AINavigationRules.native_flood`／`_native_step`／`native_candidates` 逐步移植 `0x40f200`／`0x40ed50`／`0x413740`；`BattleLoopAI._ai_take_owned_turn` 对 `no_attack` 单位直接待机。
- 差异：中心平分的双候选随机流与原全局 RNG 顺序未等价；3×3 行动者的精化仍用移动包络（provisional）；+0x80 bit 0x10000（`0x43f523` 每回合置位，`0x440ff6`／`0x441318`／`0x441f41` 清）只在跳过锁定的残血 state 0xb 进站位时还在，站位走不动重进优先级链已照原版（[original_ai_priority](original_ai_priority.md)）。

## 证据

**static-derived：有界原指令执行**（[original_ai_navigation.json](original_ai_navigation.json)，`hsltools/probes/ai_navigation.py`，固定 SHA 的 hsl01.exe，合成输入，无 stub）

| 路径 | 样例 | 终点 |
| --- | --- | --- |
| `0x45ec32` 圆域、`0x45ec63` 曼哈顿域 | 52 | 正常返回（轴向／四斜向、3–4 距离、边界内外） |
| `0x43f55f` 已有目标前段 | 30 | 到新搜索或保留分支（移除、搜索距离、守备半径） |
| `0x43f603` 初始等待 | 12 | 停在近敌查询或决策入口（0/1/3 次剩余、健康／受伤／毒／禁魔） |
| `0x441002` 锁定比较 | 24 | 停在重搜或保留分支（0/30/60/100 与临界 roll） |

**static-derived：字段与读法**

| 锚点 | 结论 |
| --- | --- |
| loader | `wait_round→live+0x1b8`（缺省 0），`ai_fixed→+0x1d0`（锚点半径），`ai_lock→+0x1e8`（1..99 比样本，0 不保留，100 总保留） |
| 移动力 | `move_point` 载入 +0x130，`0x448987..0x448998` 复制到 +0x12c，装备可叠加 |
| `0x40c9a0`／`0x40cca0` | 中心不要求有对象；每次 update 1/2/5/8 个工作预算并保存游标；原移动候选缓存上限 250 |
| `0x40d530` | 八周边格＋中心是大体型目标的接近候选，不表示普通角色可斜走 |
| `0x43ede0` 阵营 | 只经 `0x40ba20`／`0x40ba80`（`~mode & 0x70000`）／`0x40bab0`（地面模式 2／3／7）读 +0x28；友军 0x50000 视玩家为同侧 |
| `0x409090` | 武器 +0xec 为 0 时返回 0；普通进攻 `0x43ff1f`／`0x440041` 得 0 即跳 `0x441eb8`（`+0x8c=0x640001`，结束回合） |
| `0x440ef1`→`0x43fbd6` | `ai_fixed≠0` 且无武器或重搜失败 → `+0x8c=0x50000`；到锚点且 flag 0x4000 置位则清位、`ai_fixed=0`；否则 `0x4111a0(actor,+0x46,+0x44,0x12,+0x12c)` |
| `0x440d5c..0x440d84` | 普通追击：`0x4111a0(actor, 目标+4, 目标+8, 0x12, +0x12c)`，与回固定点同入口同参数 |
| `0x413740` | 洪泛行主序；跳过未到达／有单位（`&0x70000`）格；等距抽 `0x458c10&1`；`0x40d800` 数四个图内邻格命中 mask 数 ≥3 时 `rand(100)<80` 跳过（`0x413889..0x41389b`）；mask 换算 `0x10000→0x60000`、`0x20000→0x50000`、`0x40000→0x30000`，再或 0x4000；`0x411080` 收窄各级传 0（`0x41112b`），最后一级传自身侧位（`0x41114d`） |
| `0x40d8b0`→`0x413390` | 抹自身占位（`0x411b90`），以目标为原点按地形射程（`0x40fa80`／`0x40f8b0`）收集「洪泛到达 ∩ 射程格 ∩ 无单位」，上限 500；3×3 目标按九个身体格顺序试；按 `\|2dx+1\|+\|2dy+1\|` 降序插入，仅与前项等键时抽 `rand()&1`（`0x41362f..0x413716`） |
| `0x40d8b0` 的移动洪泛 | `0x40d8f7`／`0x40d911` 读 live+0x12c 移动力作半径，`0x40f440(actor, move, 6 或 0x40bab0 模式)` → `0x40f200` |
| `0x40f200` 半径 0 | `0x40f247 test edx,edx`、`0x40f24b je 0x40f345`：缓冲按 1×1 清零后直接返回，中心格不写；`0x413390` 只收洪泛字非零且无 0x80 的格（`0x41345a..0x413464`；第二分支 `0x4135a2..0x4135a8` 同样查洪泛字非零、无 0x80），于是移动力 0 的行动者一格站位也收不到（自身格同样不算），`0x40d8b0` 恒返回 0，与目标距离、体型、射程无关；四个调用点 `0x43f959`／`0x43f9e1`（濒死检查）、`0x43ff4e`（侧走）、`0x44005d`（普通进攻）同果 |
| `0x440041..0x4400ac` | 普通进攻：`0x409090` 有武器后 `0x40d8b0(actor, +0x88)`（`0x44005d`）；非零写回 +0x88、`0x40bee0` 广播、`+0x8c=0xb0000`；为零到 `0x440094` 读 live+0x12c，为 0 `je 0x441eb8` 结束回合（不出手、不追击），非 0 才 `0x4400a2` 置 `+0x8c=0xb0000` 进追击 |
| `0x440b2c` | 站位不比攻击者远且四邻有敌时，`rand(99)+1` > 92（近战）或 78（远程）仍走到站位；否则目标已在射程内就原地攻击；都不成立则走到站位 |
| `0x441311..0x441369` | 到站后以行动者为原点重建覆盖测持有目标，为零 `je 0x441eb8` 结束回合不出手 |
| `0x4111a0` | `0x411080(actor, x, y, 0x12, move, 0)`；两处调用：`0x43fc46`（回固定点）、`0x440d7f`（追击） |
| `0x411080` | 行动者已在目的格心返回 0；半径 `max(0x12, move)`；模式：飞行（`0x446ad0`）6，否则末参 0 → `0x40bab0`（P 2／E 3／N 7），末参 1（剧情走位）→ 1；洪泛：末参 0 → `0x40f440`，1 → `0x40f350`；半径 ≠ move 时 `0x413900(点, 0)` 找到才改写目的点（返回值不看），半径 −2、不低于 move；半径 = move 时 `0x413900(点, 0x40ba20 阵营)`，找不到或 `0x410a50` 返回 0 → 返回 0 |
| `0x40f200`／`0x40ed50`（`0x4c1a74 = 0`） | 半径上限 50，缓冲 (2r+1)²，中心 r+1，四邻按上、下、左、右以预算 r 递归；每格先查地图与缓冲边界；模式跳转表 `0x40f1c4`：2→mask `0x64000`、3→`0x54000`、7→`0x34000`（高差附加在前：`预算 −= 上坡差`，`\|高差\|≥3` 停），格字命中 mask 时要该格对象 `0x446b30`（模板 +0xa0 bit 0x10）才可过，缓冲值 ≥ 预算停，写入预算后 `预算 −= 0x40eb80`（前方与两侧有 mask 旗 2，否则 1）；6→只看 `0x4000`、减 1；预算 ≤0 停；上／下来的格先直行再左、右，左／右来的格先上、下再直行 |
| `0x413740` | 缓冲逐行逐列；跳过 0／带 0x80 与格字 `& 0x70000` 的格（`0x40d8b0` 在 `0x40dc36` 重新登记自身，所以追击时自身格也跳过）；距离是格心像素对目标像素的曼哈顿；同距先抽 `0x458c10 & 1`；命中写回格心像素 |
| `0x440c2c..0x440d11` | 站位走法：重定位掷中 `0x410a50(站位)`；否则 `0x40fb20` 在射程内原地攻击；否则 `0x40f440(move)` 后 `0x410a50(站位)`，返回 0（站位＝自身格或不可达）时对象 +0x80 带 0x10000 回 `0x440db1`，否则 `0x441eb8` 结束回合 |
| `0x43f3fb..0x43f45a` | 一般对象过程每 tick 都跑，不是回合入口：除非 `[0x4c1b00]` 带对话框位 0x100000 而无剧情位 0x4000000（`0x43f40c` 跳走），`0x446b00`（no_attack）为 1 → `0x411a30` 登记、`0x4483f0`（→ `0x4483c0` 清 +0x24 状态、+0x30..+0x48 计数、+0xb0 并刷新 `0x448840`）、活记录 +0xe8 清零；此后才 `0x407540` 判当前行动者，剧情阶段改走 `0x43f45f` 一般路径，否则是自己则 `0x442084` 结束回合、不是则 `0x4420df` 走过程尾；麻痺门 `0x43f47b` 在这之后 |
| `0x43feba`（抽取 `0x43ff32`） | 魔法进攻无法术目标时 `rand(100)<11` 且有站位：`0x40f440(actor,1,mode)` 一步洪泛内取离站位最近格（`0x413900`） |

EVEF 实例回调 `0x42bd50`（过程 3／5 分支 `0x42bd96..`）：

| 实例字 | 写入 |
| --- | --- |
| `0x10..0x2c` 八 DWORD | live +0x138 物品槽，逐字找第一个空槽，非零才写（`0x42be2e..0x42be79`） |
| `0x50+4·i`（`0x42bf4c..0x42c08b`，跳转表 `0x42c0a8`，零值跳过） | 0 gold +0x98；1 find_type；2 find_flag；3 find_range；4 ai_call_range；5 ai_fixed；6 ai_check_dying；7 ai_check_hp；8 ai_help_otherhp；9 ai_help_status；10 ai_help_attack；11 ai_lock；12 ai_att_special；13 ai_att_magic；14 wait_round；16／17 调级高／低字；18–23 六装备槽 +0xec..+0x100；24 气力 +0xe8 |
| i=15（`0x42c012`） | 对象 +0x80 \|= 0x4000，`ai_fixed=8`，锚点 +0x46／+0x44 = 格心像素 |

`actSetPlayerFixPos` 同样写锚点与 `ai_fixed`，见 [original_fixpos_fly_prev_insert.md](original_fixpos_fly_prev_insert.md)。

**resource-derived**（`hsltools/levels/seed.py`，[evef_instances.json](../../../content/generated/hsl/development/evef_instances.json)）：70 关 569 个演员实例中六个装备字出现 0 次；gold 字仅 53 关 Enemy023 写 100，与 PLAYERS 023 模板相同。固定点：17 关记录 8 → (37,18)；34 关三名村民 → (5,19)／(7,13)／(24,5)；1 关八名村民 → (6..9,2..4)／(21,12)。52 关皇帝 025 `wait_round 8`／`find_range 10`，两名 026 `wait_round 2`／`find_range 12`。

**runtime-measured**（原版）：17 关 064 第 1 回合两次运行都落 (33,15)，重制精化链 (37,18)→(36,18)→(36,16)→(34,16)→(33,15) 一致；第 2 回合原版 (34,18)／(36,16)，重制 (36,16)；第 3 回合到 (37,18) 释放（[original_level17_escort](../runtime_observations/original_level17_escort/README.md)）。3 关 028_1 16/16 种子取右侧 (6,10) 而非上方 (5,9)。17 关 035_1 实测 `0x40f440(035_1,1,3)`→`0x413900` 取 (28,14)。第一战 021_3 站位 (14,11) 与原版一致。

**runtime-measured：原版裁判喂抽签回放**（`ai_replay` 判定器，`_enemy_level.py batch --mix 20 --turns 1` 原版侧，SEEDS 1..32）：

```
L051 r1 : AI_REPLAY_CHECK_PASS levels=1 runs=32 rows=352 agree=352 random=0 rule=0 caliber=0 unreached=0
L051+L052 开场 (--align): AI_REPLAY_CHECK_PASS levels=2 runs=64 rows=896 agree=894 random=0 rule=0 caliber=2 unreached=0
```

口径 2 行是玩家第 2 场 · 惡夢的終曲（LEVEL052）的 ally024_2（s9／s13）：落点一致，原版目标 021_8、重制 021_7。不喂抽签的 32 种子落点分布（两边各自随机流）：

| 单位 | 原版 | 重制 |
| --- | --- | --- |
| 玩家第 1 场 · 棄卒（LEVEL051）r1 023_2 | [14,14]×20 [15,15]×6 [16,16]×4 [13,15]×2 | [14,14]×14 [16,16]×8 [15,15]×7 [17,17]×2 [13,15]×1 |
| 玩家第 2 场 · 惡夢的終曲（LEVEL052）ally024_2 | [14,35]×12 [13,36]×9 [12,37]×6 [15,36]×2 [11,38]×2 [17,38]×1 | [13,36]×15 [12,37]×5 [17,38]×4 [11,38]×4 [10,39]×2 [14,35]×2 |

分布差来自持有目标比例（023_2 原版 026_1:021_1＝17:15，重制 10:22）与两边随机流不同；同一抽签下落点逐行一致，本包的精化链不是分歧来源。原生洪泛移植前后这 64 局重制输出逐字节相同。

**runtime-measured：普通进攻的移动力 0 出口**（`hsltools/probes/_normal_attack_trace.py`，原版裁判，batch 种子 `mixed_seed(S, 20)` S=1..8，2 回合，雷歐納德 hp／max_hp 999）：劫數 · 地劫神（LEVEL059）的 actor060_1 移动力 0，身体中心 (40,16)。

| 雷歐納德所在 | 运行 | `0x440041` 进入 | `0x40d8b0` 调用（调用点） | `0x40f200` 半径 | `0x413390` 调用／到达格 | `0x40d8b0` 非零 | `0x440094` 读移动力 | 普攻 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 距中心 5 格：(40,21)／(37,19)／(35,16) | 24 | 33 | 39（`0x44005d` 33，`0x43ff4e` 侧走 6） | 全 0 | 349／0，缓冲均 1×1 | 0 | 33 次，全 0 | 0 |
| 距中心 2–4 格：(40,18)／(40,19)／(40,20) | 24 | 6 | 6（`0x44005d`） | 全 0 | 51／0 | 0 | 6 次，全 0 | 0 |

侧走抽取 `0x43ff32` 在 5 格探点 32 次，掷中后的 6 次 `0x40d8b0` 同样返回 0。2–4 格探点 24 局中 18 局在 `0x4603ca` 越界访问停机（裁判模拟器边界），停机前的数据同上。结论：移动力 0 的行动者在原版从不普攻，普通进攻总是经 `0x440094` 到 `0x441eb8` 结束回合，不进追击。

**user-confirmed**：原版第二战皇帝与上方法师／重装队不会立即下压；重制 all-wait 复跑皇帝第 1–8 回合 `wait_round` 7→0，两名 026 第 3 回合才动（[remake_all_wait_trace_level52.txt](../runtime_observations/original_level17_escort/remake_all_wait_trace_level52.txt)）。

**重制侧回执**（Godot 真实控件，正常时钟，夹具改位置／HP／速度／控制资格）：绕障碍 4 回合保持目标经 (7,9)→(8,8)→(9,9)→(10,9) 攻击；近目标不连通时改追远目标；锁定目标死亡后重选；空格 (10,9) 为中心的毒雾／驱毒各覆盖 4 人一次 MP；缺 MP／禁魔改物理接近。数据在 [runtime_observations/ai_navigation/receipt.json](../runtime_observations/ai_navigation/receipt.json)。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_navigation.md`：`game/sim/AINavigationRules.gd`、`game/sim/loop/BattleLoopAI.gd`、`game/sim/ActorInitializationRules.gd`、`game/sim/ReinforcementGrowthRules.gd`、`game/sim/BattleRewardRules.gd`。
- 持有目标存稳定 `ai_target_id`，死亡／离场／终态清除；`wait_round` 进 `ai_wait_remaining`；存档含持有 ID、守备锚点、剩余等待。
- 实例字：`seed.py` 解码进 `placements[].actor_instance`，运行时 `ActorInitializationRules.apply_instance_words`（物品、气力）、`AINavigationRules.instance_profile`（1..14 覆盖 profile）、`ReinforcementGrowthRules.prepare`（16／17）、`BattleRewardRules.kill_gold`（gold）；装备字只记录不应用。
- 回执：`home_approach.refinements`（含 `crowded_skips`）、`ai_decision.pursuit_approach`、`ai_decision.attack_station`（`order`／`draws`／`roll`／`reason`／`arrival_in_range`）、`wait_reason`（`fixed_point_reached`／`station_out_of_range`）。
- 侧走 11% 支线：`AIDecisionRules.side_walk_roll`、`BattleLoopAI._ai_side_walk`；逐槽换目标：`BattleLoopAI._ai_station_switch`。
- 表现：`BattleNavigationCue` 画实际路径；Wait 0.55 秒「待機」短反馈是重制可读性选择。
- 精化：`approach_point` 每级 `native_flood`（`0x40f200`／`0x40ed50`，移动模式、mask、高差、`0x40eb80`、no_block 占位格）→ `native_candidates`（`0x413740` 候选）→ `nearest_stoppable`；末级选中格的走法与耗费取本回合移动包络的路线；3×3 行动者仍用移动包络。
- `no_attack`：`BattleLoopAI._ai_take_owned_turn` 在决策前待机（`wait_reason` `no_attack`，`0x43f413`）；逐 tick 的清除由 `BattleLoopAI.clear_no_attack_units` 在每个 AI 步进（麻痺门之前）与每次玩家菜单入口对全体存活、非玩家操控的 no_attack 单位执行，一次行动之内（连击之间）不清。
- 重制组合（provisional）：`SkillTargetRules.candidate_centers` 遍历全部合法站位不复刻 250 缓存；`approach_goals` 按平铺 RANGE，只进 `candidate_filters.without_approach` 回执，不影响走法。

## 复现

`python3 tools/hsl.py check ai_navigation`（重执行：`uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate ai_navigation --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`）。

## 边界

- 原生洪泛移植没有逐格原指令对照（静态读法＋整局回放一致）；3×3 行动者的精化洪泛未移植。
- `0x410a50` 自身格：重制把站位即自身格当原地攻击，到站复查不中即结束回合，与原版 `0x441eb8` 同果；+0x80 bit 0x10000 只在残血 state 0xb 进站位时还在，此时原版重进优先级链，重制同（[original_ai_priority](original_ai_priority.md)）。
- `0x43feba` 与 `0x410a50`（自身格）尚无有界原指令执行。
- 不喂抽签的落点分布差属于抽取结构（持有目标比例、随机流），见差异清单 `ai-first-battle-moves`。
- 中心平分的双候选流与原全局 RNG 顺序未等价。
- 大型占地、特殊移动模式、全部高差／地块 flags 另见 [original_movement.md](original_movement.md)。
- 护送战全程逐格一致与 80% 拒绝对路线的影响不由本包支持；逐格一致只在两次原版运行一致处声明。
- 对象槽复用生命周期未宣称等价。

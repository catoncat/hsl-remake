# 原版敌人回合裁判：在模拟器里跑原帧体，输出 enemy_turn_v1

> evidence: runtime-measured: 整个 hsl01.exe 映像在 unicorn 中执行——载入 51 关样本存档后的敌人回合（落点、动作、目标、每次抽取）、0x407340 四种速度下的队列、帧桩消融、0x4c1bbc 回合计数从 1 走到 2、0x40e870 出生调级只抽全局流、任意关卡经 0x42da60 进关并在首个 0x407340 前注入局面后原版跑整回合; static-derived: 0x460a06 转场步进与 [0x4bbb5a]、0x458c10／0x458c80 与伤害流换入 0x42c780／0x42c720、0x407340 插入排序; provisional: 全局流的样本起点（来自模拟器时钟桩）、玩家回合结束从 +0x8c=0x10000 起跑（不经待機菜单输入）、call／other 两类动作从不产出、抽取点对照表 SITE_MAP（逐站点反汇编对照，未逐值对拍） · status: live · functions: 0x407340, 0x407510, 0x407cc0, 0x409e40, 0x40a7b0, 0x40c9a0, 0x40e870, 0x42c720, 0x42c780, 0x42ce10, 0x42d280, 0x42d600, 0x42da60, 0x42e640, 0x43e110, 0x43e1c0, 0x4423c0, 0x458c10, 0x458c80, 0x460799, 0x4607f9, 0x460884, 0x460a06, 0x461479 · tools: hsl_original_probe_units.py, hsltools/probes/_enemy_level.py, hsltools/probes/_turn_queue_trace.py, hsltools/probes/enemy_turn.py, test_hsl_enemy_level.py · updated: 2026-09-28

## 结论

- 原版程序本身作裁判：整个 `hsl01.exe`（SHA-256 `f0b5f835…`）映像在 unicorn 中逐帧执行完整帧体 `0x42d600`（只桩掉「画出来」的四处），载入 51 关样本后原版跑完 11 个 NPC 行动回到玩家控制；4 个其他全局种子同样跑到玩家控制（5 回合 55 行动、2739 次抽取）（runtime-measured）。
- 早先出手等待的根因是没调转场步进 `0x460a06`：守方特写 phase 101 以 `0x46098f(1)` 置 `[0x4bbb5a]`=1，只有 `0x460a06` 清零；桩掉它等待原样复现（runtime-measured 消融）。
- `0x407340` 按注册槽收集后插入排序，等于按 (−速度, 槽) 排序；`0x40e870` 出生调级只抽全局流 `0x458c10`，不碰伤害流（runtime-measured）。
- 任意关卡裁判 `_enemy_level.py`：原版经 `0x42da60` 进关，在首个 `0x407340` 前注入重制局面后跑整回合；51 关 r1 种子 1 落点 8/11 一致，分歧按 32 种子分布归为持有目标规则 5 处、随机 4 处（runtime-measured，证据块的表是当时重制的读数；持有目标规则此后已照原版，规则类分歧为 0，见差异清单 `ai-first-battle-moves`）。
- 古代神殿遺跡 · 守護者之戰（LEVEL037）首轮在 guard067_5 之后结束，与重制相同：原版首轮队列 30 项，最后五项是速度 0 的宝石 guard067_1–067_5（登记槽 31／33／35／37／39），三种子各自 30 次 `0x407510` 交接，067_1–067_5 五次在同一帧内走完、不抽全局流；067_5 交接后 `0x4074a0` 找不到待行动项，`0x4074ec` 调 `0x407340` 重建、`0x4074f1` 回合计数 +1。`_enemy_level.py` 按帧看队列当前项，同一帧里连走的零帧回合只记第一个，故原版行只到 067_1；重制首轮同为 066_1–066_5 后 067_1–067_5 各待机、不抽签（runtime-measured，`_turn_queue_trace.py --level 37 --turns 1 --seed 1／2／3`）。
- 两端逐值对拍对不上：原版每个 NPC 先抽优先级链，重制省掉的链上抽取都在不可能出手的分支；规则类分歧已为 0，随机类只要求分布等价（盯谁比例差经 200 种子为抽样噪声，见 [AI 决策包](original_ai_decisions.md#证据) 的随机数消费表；provisional，差异清单 `ai-first-battle-moves`）。

## 证据

**runtime-measured：样本回合**（回执 [original_enemy_turn.json](original_enemy_turn.json)，注册任务 `enemy_turn`）。样本随机数：全局 [956367880, 2292745173]（伪影：时钟桩值加载入时 `0x407b70` 内 `0x407c06` 的 12 次抽取，写在 `meta.rng_source`），伤害 [212957692, 4082009603]（取自存档 `0x4c3044`／`0x4c3040`）。

```
actor023_1 [17, 18]->[15, 15] wait actor021_4        actor021_2 [13, 10]->[14, 13] attack actor023_2 (−10)
actor023_2 [14, 19]->[14, 14] wait actor021_2        actor021_3 [10, 8]->[12, 11] wait leonard
actor026_1 [13, 6]->[11, 7] wait actor023_1          actor021_5 [6, 9]->[10, 8] wait leonard
actor026_2 [4, 9]->[7, 9] wait actor023_1            actor021_1 [13, 7]->[12, 9] wait actor023_2
actor024_1 [17, 21]->[17, 17] wait actor021_4        actor021_4 [13, 11]->[15, 14] attack actor023_2 (−9)
actor024_2 [15, 22]->[15, 18] wait actor021_4        stop=player_control next=leonard frames=1472
```

- 026_1 (13,6)→(11,7)、026_2 (4,9)→(7,9)、024_1 (17,21)→(17,17)、024_2 (15,22)→(15,18) 与录屏 R1-09..R1-12 相同，`check` 校验这四条。
- 021_2 攻 023_2 的伤害流 (site, n, value)：`0x442669` 100→32，`0x409cc3` 3→2，`0x409ce6` 0→0，`0x409cf5` 0→0，`0x403efa` 100→14，`0x403f51` 100→86，`0x40a660` 5→0，`0x40a6d7` 1→0。样本回合全局流 515 次、伤害流 17 次；全局最多的站点 `0x41385d`（268 次，走法精化），其次 `0x40c061`、`0x40c138`、`0x440db5`、`0x40d500`。
- 种子 (1,2)、(0x12345678,0x9abcdef0)、(7,7)、(0xdeadbeef,0x13579bdf)：1469–1478 帧回到雷歐納德；021_2、021_4 每次攻击，021_4 的目标在两个种子下换成 023_1；026_2 落点在 (7,9)／(6,8) 间变化。

**runtime-measured：消融**（`--ablate`，回执 `ablations`）

| 开关 | 结果 |
| --- | --- |
| 去掉 blit `0x461479` 的桩 | 5 回合、终局 HP、帧数逐字相同，已从垫片删除 |
| keep-present（不桩 `0x42d280`） | 第 1 帧 `unmapped access 0x0 at eip 0x457d67` |
| keep-shape（不桩 `0x4607f9`） | 第 464 帧 `fatal 'Shape not loaded: 364'` |
| keep-text（不桩 `0x460884`） | 第 489 帧 `unmapped access 0x4 at eip 0x4608d6` |
| keep-draw-pass（跑 `0x45f724..0x45f75e`） | 第 1 帧 `fatal 'Shape not loaded: 2'` |
| stub-transition（桩 `0x460a06`） | 6000 帧 `frame_limit`，current=actor021_2，`[0x4bbb5a]`=1 |

**runtime-measured：队列 `0x407340`**（回执 `queue_sort`；改 live 速度后直接调原函数）

```
loaded        021_2/s22/v16 021_3/s23/v16 021_5/s26/v16 021_1/s20/v15 021_4/s24/v15 leonard/s0/v14 023_1/s27/v14 023_2/s28/v14 026_1/s21/v13 026_2/s25/v12 024_1/s29/v12 024_2/s30/v12
023_2 速度16  … 021_5/s26/v16 023_2/s28/v16 021_1/s20/v15 021_4/s24/v15 leonard/s0/v14 023_1/s27/v14 …
全员速度10     leonard/s0 021_1/s20 026_1/s21 021_2/s22 021_3/s23 021_4/s24 026_2/s25 021_5/s26 023_1/s27 023_2/s28 024_1/s29 024_2/s30
速度=槽号      024_2/s30 … 021_1/s20 leonard/s0
```

样本载入后当前行动者 `0x4c6e48`=5（雷歐納德），023_1 为下标 6、023_2 为 7。

**runtime-measured：出生调级与回合计数**（回执 `growth`）：对 023_2 按 `0x43ef26` 参数 (18, 2) 原生调 `0x40e870`：L1 29 HP 速 14 → L2 36 HP 速 15；rand(n) 站点依次 `0x40e92c`、`0x40e938`、`0x40e956`、`0x40e9a2`、`0x40ea0b`、`0x40ea38`、`0x40ea62`、`0x40ea90`、`0x40eabe`、`0x40eaf9`，伤害流状态不变。回合计数是 u16 `0x4c1bbc`（`0x42c6b9` 置 1，`0x4074f1` 每轮加一），样本中 1→2；`0x4c1e8c` 是全局流种子标志（`0x458c10` 为 0 时按时钟播种，`0x458bc3` 置 1）。旧回执（battle_005、battle_006、level17 护送）里的 `round_counter_0x4c1e8c` 值 1 表示「已播种」。

**static-derived：抽取与动作分类**

| 项 | 读法 |
| --- | --- |
| 全局流 | rand(n) `0x458c80`：n ≤ 0xffff 时 (raw & 0xffff) % n，否则 raw % n；rand(0) 不抽返回 0；raw `0x458c10` 直接调用记 n=null |
| 伤害流 | `0x42c780`（rand）／`0x42c720`（raw，唯一调用者 `0x409d06`）把 `0x4c3044`／`0x4c3040` 换入全局生成器抽一次再换回 |
| attack | `0x4423c0` 起手（`0x4c432c`=0）且攻方是当前行动者；否则记为反击 `meta.counters` |
| magic／skill | 名牌 `0x43e110`（MAGIC `[0x4c2c54]`／`[0x4c2c40]`）／`0x43e1c0`（SPECIAL `[0x4c2c44]`／`[0x4c2c94]`）；target 为 `0x4417b5` 写的 `[0x4c1cec] = 0x4104d0(0)`（区域内按行首个对象，`0x410548..0x410553`） |
| item | `0x409e40(target, item, user)` 且 user 是当前行动者 |
| wait | 其余；target 为持有目标 +0x88（槽 + 1） |

抽取点对照表 `enemy_turn.SITE_MAP`（逐站点反汇编对照）：

| 原版调用点 | 重制 `Script.function` |
| --- | --- |
| `0x40bd4f`（raw & 1） | `AIDecisionRules.select_target` |
| `0x40c061` | `AIPriorityRules.low_hp_target` |
| `0x40c138` | `AIPriorityRules.self_recovery` |
| `0x40c58d` `0x40c5b3` `0x40c5f8` | `AIDecisionRules.select_action` |
| `0x40c7f8` `0x40c842` `0x40de0c` `0x40de56` | `AISkillDecisionRules.select_index` |
| `0x40d500` | `AISkillDecisionRules.area_order` |
| `0x4136ba`（raw & 1） | `AINavigationRules.station_order` |
| `0x440bf5` | `AINavigationRules.attack_station` |
| `0x41385d`（raw & 1） `0x413890` | `AINavigationRules._nearest_stoppable` |
| `0x440db5` `0x440ddf` `0x440e1b` | `AIPriorityRules.choose_check` |
| `0x440e57` `0x440e93` `0x440ecf` | `AISupportRules.next_check` |
| `0x43ff32` | `AIDecisionRules.side_walk_roll` |
| `0x40cb54` `0x40cb99`（raw & 1） | `AISkillPlanning.centre_scan` |
| `0x40d1c8` | `AISkillPlanning._cast_search` |
| `0x40d273`（raw & 1） | `AISkillDecisionRules.farthest_index` |

raw & 1 站点记 n=2、取低位。伤害流另表 `DAMAGE_SITE_MAP`（魔法 `0x40a7f0`／`0x40a884`／`0x40a893` → `NativeMagicRollRules.roll`）；无对应的站点登记在 `UNMAPPED_ACTION_SITES`（`0x401390`、`0x415c10`、`0x415d90..0x4239xx` 效果进程区，`0x407cc0` 入场，`0x40e870` 升级）。

**runtime-measured：任意关卡裁判**（`hsltools/probes/_enemy_level.py`；重制列为 2026-09-25 当时的重制）

第 51 关 r1，种子 1：

```
ORACLE_MATCH total agree=2/11 order=11/11 draw_sites_same=0/11 draw_values_same=0/11 extra=0 draws_both_empty=0
ORACLE_DRAWS site=AIPriorityRules.choose_check original=53 remake=0
ORACLE_DRAWS site=AINavigationRules._nearest_stoppable original=353 remake=320
```

| actor | 分歧 | 归类 | 依据（两边各 32 种子） |
| --- | --- | --- | --- |
| 023_2 | to＋target 021_1 对 021_2 | 规则 | 持有目标集合不相交：原版 {026_1, 021_1}，重制 {021_2, 021_4} |
| 021_2 | target leonard 对 023_2 | 规则 | 原版 14/32 持有雷歐納德，重制 0/32；023_1 原版 0、重制 19/32 |
| 021_4 | target leonard 对 023_1 | 规则 | 原版雷歐納德 19/32、023_1 0/32；重制雷歐納德 0/32 |
| 021_5 | target leonard 对 023_2 | 规则 | 原版雷歐納德 13/32，重制 0/32 |
| 023_1 | target 021_1 对 021_2 | 规则 | 原版 021_1 7/32，重制 0/32 |
| 024_2／024_1 | target 021_4 对 021_1 | 随机 | 两边都出现 021_4／021_2／021_1 |
| 026_1 | target 023_1 对 023_2 | 随机 | 两边都出现（原版另有雷歐納德 13/32） |
| 026_2 | to [7,9] 对 [6,8] | 随机 | 两格两边都出现 |

第 3 关种子 1（`{"growth": false}`）：`agree=12/14 order=14/14`；028_2 原版 [5,9] 攻击 hu 16/16、重制从不（规则）；028_5 落点随机；028_1 原版 16/16 走 [6,10] 无抽取，重制 7/9 分并抽 `attack_station`（规则）。第 52 关种子 1：`agree=11/15 order=15/15 extra=2`，4 处随机；多出的 2 个是两名 069（EVEF obj_Data9 换为敌方，(15,14)／(6,13)，48 种子第 1 回合都 wait）。

批量（`{"growth": false}`）：

| level | seed | 原版行动 | 重制行动 | 一致 | 顺序 | 抽取站点相同（两边皆空） |
|---|---|---|---|---|---|---|
| 003 | 1／2／3 | 14 | 14 | 12／11／11 | 14 | 7 (7) |
| 006 | 1／2／3 | 23 | 9／23／23 | 4／19／19 | 9／23／23 | 2 (2) |
| 010 | 1／2／3 | 4 | 4 | 1／3／2 | 4 | 0 (0) |
| 051 | 1／2／3 | 11 | 11 | 0／3／4 | 11 | 0 (0) |
| 052 | 1／2／3 | 17 | 15 | 11／11／12 | 15 | 7 (7) |

第 6 关种子 1 重制只 9 个行动：重制这一局回合中途判定胜负。

魔法（r1 加 `--set 026_1.cell=17/15 --set 026_2.cell=16/16`，全局 (1,2)）：`actor026_2 [16,16]->[16,16] magic actor024_2 skill=magic:magicFIRE:magicCode01 draws=521`，024_2 −20；伤害流 `0x40a7f0` 100→23、`0x40a884` 8→0、`0x40a893` 8→2、`0x40a660` 10→1、`0x40a6d7` 3→2；全局 516 次（AI 决策 28、效果进程区 472、单位入场 16）。停点后第 1844 帧 `0x43eedd` 对一个盘外对象（`+0x64`=5，格 [8,6] 即本关 `escape_zone`，`+0x80 = 0x90100000`，注册槽 31）调 `0x407cc0` 与 `0x40e870`。8 种子分布：原版 023_1 8/8 打 026_1、026_2 魔法 024_2 5 次／024_1 2 次／攻击雷歐納德 1 次；重制 023_1 打 026_1 3/8、026_2 5/8，魔法目标 023_x——魔法目标与 023_1 攻击目标归规则（样本小）。

## 重制接线

- 整映像机器 `tools/hsltools/native/battle_machine.py`。垫片（回执 `shims` 逐条列出）：Win32 导入白名单（GetTickCount／timeGetTime 每调加 1，FindFirstFileA 返回无效句柄，PeekMessageA 与按键状态为 0，其余停机）；malloc `0x457b70` 换 bump 分配；文件层 `0x46c830..0x46c970` 换内存文件；形状加载 `0x4601a2`／`0x460058` 返回 0，`0x45fc01` 发顺序号，跳过 `0x45f724→0x45f75e`，桩 `0x4607f9`／`0x460799`／`0x460884`／`0x42d280`（呈现桩返回前置 `[0x4c1b1c]`=1）；致命框 `0x45b29e` 停机。每加钩子 `ctl_remove_cache(at, at+1)`。
- 载入照 WinMain `0x42f1ad`：`0x46d14c`、12 个文本表、GLOBAL.OBS `0x45dc5c`、复位 `0x42c640`／`0x407260`／`0x45fb5c`、`0x42ce10(51)`＋`0x45e224`、存档读取 `0x42e640(0,0,1)`。回合：当前玩家 `+0x8c` 写 `0x10000` 走回合末（地形、中毒、回复、`0x40b910`、`0x407510`，记 `meta.handoff`），再逐帧 `0x42d600` 直到当前对象 `+0x64`=3。
- 状态注入 `apply_board`（`INJECTION` 表）：speed → live +0xb8；hp／max_hp／level → +0xd8／+0xdc／+0x9c；cell → 对象 +4/+8，占位用 `0x411b90`／`0x411a30`；target → +0x88；dead → 死亡入口写入、`0x411b90`、`0x407720`、`0x44cb90`、`0x45e3ed`；turn → `0x4c1bbc`。
- `_enemy_level.py`：以载入标志清零调 `0x42da60(level)` 进关、进 `0x42dbf0` 帧循环；对话在等待点后置左键 `[0x4c2344]` 一帧；玩家回合在 `0x4082c4` 写 `0x10000`（全员待机）；growth false 在 `0x43eefb`／`0x44345d` 前清 +0x1f8／+0x1fa；首个 `0x407340` 前注入与写种子（`0x4795d4／0x4795d8`、`0x4c1e8c`=1、伤害 `0x4c3044／0x4c3040`）；`resume_after` 用 `0x4074a0(1)`；缓存 `ignored/native_cache/battle_machine/`。`compare` 输出 `ORACLE_MATCH`／`ORACLE_DRAWS`；`batch` 并行跑关卡 × 种子。
- 重制对应端 `tests/diagnostics/export_enemy_turns.gd`（[battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)）：actor 用重制单位 id，格 = 像素 >> 5；`--lines` 按 SITE_MAP 改名，`--bare-lines` 置空 draws。
- 全局流在重制由 `game/sim/GlobalRandomStream.gd` 与 `game/sim/loop/BattleLoopInit.gd` 提供（惰性种子 `0x458c19..0x458c28` 存 [t, t ^ 0xe54a231c]），不入存档。

## 复现

`python3 tools/hsl.py check enemy_turn`（离线校验回执；重跑原程序：`uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate enemy_turn`；任意关卡：`python3 tools/hsltools/probes/_enemy_level.py --level N [--board FILE --board-key KEY] [--set ID.FIELD=V] [--seed S1 S2] --brief`）。

## 边界

- 玩家回合从 `+0x8c=0x10000` 起跑，不经待機菜单输入；菜单是否抽随机数未验证；玩家计划只支持全员待机。
- 全局流样本起点是伪影；录屏那一局的时钟拿不到。
- 绝技与道具在原版一侧未出现过；call／other 不产出。
- SITE_MAP 只按反汇编对照站点，未逐值对拍；原版先抽优先级链，重制省掉不可能出手分支上的抽取，第一个分歧落在第 1–6 次抽取（[AI 决策包](original_ai_decisions.md#证据)）。
- 死亡注入不跑死亡字幕／事件 `0x446b60/0x446c40`，不给击杀者经验与金钱；当前行动者不能注入死亡。
- 按帧采样：同一帧内连走的多个零帧回合（LEVEL037 的宝石 067、LEVEL012／026 的船壳 101）只记第一个；要看全部交接用 `_turn_queue_trace.py`。
- 魔法入场对象身份未查。
- 四个画面桩必须保留；去掉需要真正解码形状与提供表面。

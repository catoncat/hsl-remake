# 原版裁判批量对照：AI 首轮回放判定与行动种类频率

> evidence: runtime-measured: 原版 127 关 × 3 种子首轮逐行对照重制导出，规则候选以喂原版抽签的整轮回放判定，行动种类频率按关分层检验; provisional: 分布等价只靠频率对拍、重制治疗通道次序 · status: record-only · functions: 0x407340, 0x407510, 0x409090, 0x409e40, 0x40bb80, 0x40c3a0, 0x40c570, 0x40c770, 0x40d8b0, 0x40dd80, 0x413740, 0x426680, 0x42cb30, 0x42da60, 0x440375, 0x45fc01, 0x45fd4b, 0x4602d4 · tools: export_ai_action_frequency.gd, export_enemy_turns.gd, hsltools/probes/_batch_rules.py, hsltools/probes/_enemy_level.py, hsltools/probes/ai_action_frequency.py, hsltools/probes/ai_replay.py, replay_ai_actions.gd, test_hsl_enemy_level.py · updated: 2026-09-30

## 结论

- 回放判定：批量分类器标出的规则候选所在 49 关 × 3 种子，原版首轮 1965 行喂原版抽签回放，**确证规则差异 0 行**（一致 1877、随机 46、口径 42、未走到 0）（runtime-measured）。
- 行动种类频率（127 关，原版 11067 次对重制 11056 次行动，3 回合）：按关分层合计普攻、待机、追击、守候 p 0.7–0.94；唯一 p<0.01 的法术进攻（34 对 65）由两簇 16 种子复跑归为抽样误差（四关合计 25 对 33，p=0.36）（runtime-measured）。
- 重制：AI 规则不因本批改动；「原版偏持雷歐納德」类候选在回放中全部一致，是两边生成器不同而非规则（runtime-measured）。
- 队列同速排序：原版 `0x407340` 按 (−速度, 登记槽) 排，古代神殿遺跡 · 守護者之戰（LEVEL037）的守卫登记槽即 STORY037 插入序；重制同序，原先 18 行未走到是按开场格命名的口径（runtime-measured）。
- 边界：只回放第 1 回合；状态不跟原版改写；「随机」只说明原版决定在某种合法喂法下可达，分布等价靠频率对拍（provisional）。

## 证据

**回放判定**（报表 [ai_replay.md](../../../../content/generated/hsl/development/ai_replay.md)，任务 `ai_replay`）。分类器在这 49 关（16／32 种子分布）重跑出规则行 74 行，回放结论：

| 结果 | 行 | 内容 |
| --- | ---: | --- |
| 一致 | 63 | 站位 44、持有目标 18（其中原版持雷歐納德 10）、法术分支 1：落点、动作、目标逐字段相同 |
| 随机 | 3 | 最終的序曲 · 妖精王（LEVEL076）s3 065_6、薩魯司海岸 · 遭遇戰（LEVEL558）s1 049_2 法术分支；接觸・妖精王 · 地劫神的終局（LEVEL078）s1 065_6 站位 |
| 口径 | 6 | 拉格納沼地 · 毒霧中的戰鬥（LEVEL032）4 行（更早有地图抽取 0x451ecf 与噴人沼氣 0x43c8xx，中毒不回放）；巴瀚納海峽（LEVEL012）1 行；LEVEL076 s2 049_2 1 行（重制在 0x40bb80、0x413740 硬币与援助链首掷上抽得更多） |
| 原版无此行 | 2 | 亞雷比斯 · 海上的亡靈（LEVEL026）s1 038_2、戈爾山道 · 遭遇戰（LEVEL502）s1 036_2 |

未走到的 18 行都在古代神殿遺跡 · 守護者之戰（LEVEL037），是裁判命名口径：守卫由 `actInsertObjectRandomPos` 落在洗牌后的槽上，按开场格命名把原版第 1 个插入的守卫（登记槽最前）叫成了 guard066_3。`enemy_turn.remake_names` 改为随机槽单位按登记槽（插入）序命名后，LEVEL037 三种子原版首轮 17 行队列与重制逐位相同，回放 51 行全部一致；全量重跑后报表未走到 0 行（49 关原版批跑与重制分布重导出）。

回放做法（`tests/diagnostics/replay_ai_actions.gd`＋`tools/hsltools/probes/ai_replay.py`）：原版 `_enemy_level.py batch --turns 1 --align --mix 20`，meta 含 `action_after`（hp 增量、行动后 +0x88、每次全局抽取的调用地址）与 `handoff_after`；重制按原版队列逐槽走，AI 抽签由 Feeder 按 (site, n) 各一条 FIFO 取原版同槽的下一个值，盘面每槽前后对齐原版 `from`／`to`、持有目标与 hp 增量。每行四种喂法：first（全部原版值）、final（去掉优先级链回跳的轮次，即第一个到最后一个 0x440db5 之间）、low／high（final 上把用尽答成 0／n−1）；原版第一个链抽取之前的值只喂重制链前抽签（曼多力亞 · 對峙（LEVEL900）s1 027_1 链前抽了 85 枚 0x41385d）。first 一致记一致；否则三种任一一致记随机；四种都不一致时有 `board_event`／探针缺口／死亡不符记口径，first 或 final 未用尽记规则，都用尽记口径。映射补充：`0x440a86`（增益援助硬币）→ `AISupportPlanning.choose` 的 special_first；`BattleLoopAI._ai_lock_check` 新掷骰 → 原版本槽最后一个链掷骰。唯一无原版对应的重制抽取点是 `AISupportPlanning.choose/99`（用尽 185 行）；其余用尽为重制多抽（0x413740 硬币 70、0x40bb80 硬币 34、法术表 14／10、类别 13、侧走 11）；非 AI 全局抽取 49 个站点不喂。

结果行：

- `BATCH levels=49 seeds=3 jobs=2 original_wall=109.0s total_wall=109.0s`；全量重跑 `BATCH levels=49 seeds=3 jobs=5 original_wall=44.9s total_wall=44.9s`
- `BATCH_RULES levels=49 dist_levels=49 actions=1975 agree=1013 rule=74 random=873 injection=0 caliber=12 pending=3`（上表 74 行所据：改名前、主线 32／其余 16 种子分布）
- `AI_REPLAY_CHECK_PASS levels=49 runs=147 rows=1965 agree=1877 random=46 rule=0 caliber=42 unreached=0 batch_rule=43 batch_rule_confirmed=0`（全量重跑；分布 49 关一律 32 种子，分类器规则行 74→43、均未确证）
- `BATCH_RULES levels=49 dist_levels=49 actions=1975 agree=1015 rule=43 random=905 injection=0 caliber=12 pending=0`

**行动种类频率**（报表 [ai_action_frequency.md](../../../../content/generated/hsl/development/ai_action_frequency.md)；原版 `_enemy_level.py batch --turns 3 --align --mix 20 --no-remake`，127 关（200 关除外）× 种子 1–3，growth false、每种子独立全局流与伤害流、LEVEL900 开场菜单选第 2 项；重制 `ai_action_frequency.py export` 以 adjust_level [0,0] 出生、`--select 900=1`）

- 原版 380 局 11067 次、重制 381 局 11056 次；原版独有 22 条、重制独有 30 条、比例超 2 倍 8 条；逐行无一条 p<0.01。
- 给药救人 19 对 10（p=0.11）；法术进攻 34 对 65（p=0.0056），去掉探针口径关 73、75 后 34 对 57。
- 两簇复跑（16 种子 × 3 回合）：

| 关 | 原版法术进攻 | 重制法术进攻 | 其中 041 风刃／049 精神系 |
| --- | ---: | ---: | --- |
| 019 | 10 | 16 | 风刃 10 对 16（041_1 2 对 8，041_2 8 对 8） |
| 904 | 10 | 16 | 同 019，逐局相同 |
| 033 | 7 | 12 | MIND02＋03 5 对 9 |
| 561 | 5 | 7 | 4 对 5 |
| 563 | 5 | 8 | 3 对 4 |
| 564 | 8 | 6 | 5 对 4 |

041（ai_att_magic 26、无绝技）每次先抽完优先级链，`0x43fe0c` 调 `0x40c570`（偶数先试法术，奇数时绝技位不可用、法术用同一个数，≤26 进法术），再以风刃 use_ratio 90 掷一次，过则原地放 magicAIR01，否则侧移 rand(100) 后普攻；原版 019 种子 1–40 第 2 回合 80 次行动中法术位掷中 16 次，13 次放风刃，3 次 use_ratio 掷 97／98／96 落空。种子 13 两边 041 行逐项相同。049（ai_att_magic 40）033 种子 9 第 2 回合两边同站位、同法术、同目标。

**规则候选分类**（`hsltools/probes/_batch_rules.py`，首轮，重制分布主线 26 关 32 AI 种子、其余 101 关 16 种子）：

| 口径 | 关 | 行动 | 一致 | 规则 | 随机 | 注入缺口 | 口径 | 待定 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 旧口径（模板阵容、共用伤害流） | 127 | 4471 | 2454 | 73 | 1803 | 65 | 18 | 58 |
| 新口径 | 127 | 4454 | 2492 | 76 | 1802 | 48 | 26 | 10 |

新口径规则 76 行：站位 48、持有目标 19、道具 3（032）、法术分支 3（076、558）、行动有无 2（026、502）、持有目标·重制无目标 1（032）；其中 74 行所在 49 关即上面回放判定的范围。`BATCH_RULES levels=127 dist_levels=127 actions=4454 agree=2492 rule=76 random=1802 injection=48 caliber=26 pending=10`。

**做法**（分类器）：同一行动者 from／to／action／target 四项全同为一致（技能名另列）。分类依次为：①注入缺口（from 不同；目标或行动者在重制名单外）；②前缀：取原版该种子首轮为期望，重制各 AI 种子的最长一致前缀 j，走到第 j+1 行的种子 ≥10 个且卡在同一字段、或 ≥3 个且结果只有一种，且该字段单现值占比 ≤0.1（Good–Turing），判规则（前缀确证），j 之前算随机，有种子整轮复现则全部随机；③边际：原版值从未在重制同一行动者第 k 次行动出现且单现值占比 ≤0.1 判规则，>0.1 或行动不到 8 次判待定，出现过判随机；④同种子已有 from 不同则其余待定；⑤原版 to 为空且首轮内战斗结束记口径。复现度＝原版 3 种子中该行动者第 k 次行动同值的种子数。类别：action 不同（任一侧法术 → 法术分支；攻击对待机 → 地形射程）；target 不同（原版法术 → 法术目标，待机 → 持有目标，攻击 → 选目标）；只有 to 不同 → 站位。

**注入缺口与探针口径**：

- 注入缺口：18 关开局事件在停点后又挪了单位（36 行）；53 关 enemy023_2／023_3 在停点后才由事件装上（12 行）。
- 探针口径：37 关宝石 guard067_2–067_5 与 067_1 在同一帧内各过一次 `0x407510` 后回合结束，探针按帧只记 067_1（`_turn_queue_trace.py` 三种子读数，原版首轮在 067_5 后结束，与重制相同）；73、75 关原版首轮内战斗结束；12、26 关船壳 actor101_x 零帧回合（026 s1 首轮 47 项中 26 个 101，各过一次 `0x407510`），两边船壳行都去掉；装备 action_twice 的单位（59 关 060_1、76／78 关 058_1、79 关 057_1）重制两行合为一行；麻痺跳过在重制按原地待机计。
- 裁判读法：`0x409e40(target, code, user, 0)` 在 `0x409e55` 读 `target+0xa4` 的活记录号，AI 路径 `0x440375` 传入的 `[0x4c1cec]`＝`0x4c42a0` 是装着目标记录号的静态对象，`enemy_turn.EnemyTurn.item_target` 按记录号还原单位（玩家第 2 场 · 惡夢的終曲（LEVEL052）s1 ally024_1 的 241 → ally023_2，HP +11）。
- 帧循环中途经 `0x4602d4` 载资源时资源号超过表长 `[0x4bbb38]`，`0x45fd4b` 返回句柄 0；`_enemy_level.EmptyFiles` 把未知句柄当空文件，之后在 `0x4603ca` 停机（31 局），停机那一回合截掉，532 s1 首轮内停机不比。

逐关数据：[oracle_batch.json](oracle_batch.json)（旧口径首轮 128 关 × 3 种子）、[oracle_batch_ai_prio.json](oracle_batch_ai_prio.json)（`ai_action_frequency.py` 读取其关卡清单）。旧口径各轮的叙述由上面的回放判定与新口径复跑取代。

## 劫數 · 地劫神（LEVEL059）法术落空后的普攻

地劫神（actor060_1）是 3×3 身体、移动力 0，武器槽装物品 55（action_twice、range5CellCircle）。局面把雷歐納德放在离身体中心 [40,16] 5 格的 [40,21]、[37,19]、[35,16]，max_hp／hp 999，玩家待机；`_enemy_level.py batch --levels 59 --seeds 1,2,3,4,5,6,7,8 --turns 2 --align --mix 20 --jobs 1`，三格各 8 个种子。

| 侧 | 回合 | 法术落空后的侧移掷骰 | 其中掷后落到普通进攻 | 普攻出手 |
| --- | ---: | ---: | ---: | ---: |
| 原版 | 45（另 2 个在 `0x4603ca` 停机） | 32（`0x43ff32`） | 26（掷值 >10） | 0 |
| 重制（改前） | 48（74 行） | 11（`AIDecisionRules.side_walk_roll`） | 11 | 14（11 次在侧移掷骰后，3 次由类别直接选中） |
| 重制（改后） | 48（86 行） | 11 | 11 | 0 |

- 原版：每次法术落空，`0x43feba` 掷 `0x43ff32`，掷值 >10 落到 `0x440041` 普通进攻，`0x409090` 查武器槽（物品 55，非 0）后 `0x40d8b0` 找普攻站位。26 次都没有出手，这一次行动就此结束：带侧移掷骰的回合伤害只有另一次行动的法术（123–423，其中 123、227 是打掉剩余血量），种子 6、7 第 1 回合整回合待机。逐指令追踪（`_normal_attack_trace.py`）定位的出口是移动力 0：`0x40d8b0` 以 live+0x12c＝0 作洪泛半径，`0x40f200` 在 `0x40f247` 测半径、`0x40f24b` 为 0 即跳过中心格返回，`0x413390` 两支（`0x41345a..0x413464`、`0x4135a2..0x4135a8`）都只收洪泛字非零且无 0x80 的格，一格站位也收不到，返回 0；`0x440094` 读到移动力 0 跳 `0x441eb8` 结束回合，33 次进入全同（[original_ai_navigation](../../static_reverse/original_ai_navigation.md)）。
- 重制改前：同局面侧移不成立后照常走普通类别并原地普攻，单次 108–518。种子 1 第 1 回合整回合伤害原版 409（一次 EARTH magicCode04），重制 891（普攻 454＋EARTH magicCode04 437）。
- 重制改后：`AINavigationRules.attack_stations` 移动力 0 时没有站位，`BattleLoopAI._ai_offense` 站位落空且移动力 0 时照 `0x440094` 结束回合、不追击；三格 8 种子普攻 0，法术落空的那次行动记为待机（`immobile_no_station`）；种子 1 第 1 回合 [40,21] 是待机＋EARTH magicCode04 423。原版的一行对应重制两行（action_twice 两次行动），行数差是导出口径。
- 停机：[37,19] 种子 1 第 2 回合、种子 4 第 1 回合在 `0x4603ca` 停机，种子 4 第 2 回合因此没跑；停机回合不比。
- 5 格不普攻已照原版。剩余差异在法术落空：同探点原版落空 32 次、重制 11 次（8 种子 × 3 探点），整回合伤害量级只有种子 1 第 1 回合 409 对 423 一组对照；落空判定或法术目标选择的读法未读，登记为 `boss-twice-action-spell-miss-rate`。
- 两边每个造成伤害的回合都足以打倒 163 血的雷歐納德，所以对这一关的胜负性质没有改变。离中心 2–4 格（[40,18]、[40,19]、[40,20]）8 种子：原版 6 次落到普通进攻、0 次出手（24 局中 18 局在 `0x4603ca` 停机），重制改前普攻 5 次、改后 0。

## 重制接线

- 重制导出 `tests/diagnostics/export_enemy_turns.gd`、`tests/diagnostics/export_ai_action_frequency.gd`，回放 `tests/diagnostics/replay_ai_actions.gd`；只加诊断，不改规则。
- 分类器 `tools/hsltools/probes/_batch_rules.py` 读 `ignored/ai_action_frequency/{original,remake,dist}/`；频率报表与回放报表分别由任务 `ai_action_frequency`、`ai_replay` 生成。

## 复现

不可再生：原版侧唯一记录（重制侧报表：`python3 tools/hsl.py generate ai_replay`，输入先由 `uv run --no-project --with unicorn==2.1.4 python3 tools/hsltools/probes/_enemy_level.py batch --levels <关> --seeds 1,2,3 --turns 1 --align --mix 20 --no-remake --out ignored/ai_action_frequency/original` 与 `python3 tools/hsltools/probes/ai_replay.py export --levels <关>` 产出）。

## 边界

- 只回放第 1 回合；两簇法术进攻（利魯瑪山地 041_x 第 2 回合 magicAIR01、049_x 精神系）靠频率复跑归类，未回放。
- 状态（中毒、增益、麻痺计数）不跟原版改写，以 `board_event` 与死亡标记兜底。
- 链内按调用点喂有语义错位（重制预先跳过不可用类别时第 k 个掷骰对应的类别不同），只由 final／low／high 兜住，不是逐值等价。
- 重制分布只换 AI 源、全局流固定在种子 1，全局流驱动的分支（噴人沼氣喷点、出生携带）采不到；101 关只有 16 种子。
- AI 治疗／驱毒：原版对症药分支 `0x44086e..0x4408dd` 取状态 mask 找首件对症药、找不到转 `0x40c3a0`（[original_item_actions](../../static_reverse/original_item_actions.md)），桶 7 净化行的抽签 `0x40dd80`／`0x40c770` 已读（[original_skill_function_bits](../../static_reverse/original_skill_function_bits.md)）；重制 `AISelfPreservation.choose_cure` 先魔法桶、再绝技桶、最后对症药，这一通道次序是重制组合（provisional）。
- 回音之谷（LEVEL021）041_1 的 1 对 0 与全部关 MIND04 的 0 对 5 未复跑。
- 资源号未建模（`0x45fc01` 顺序发号），是既有图形桩边界。

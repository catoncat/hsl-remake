# 职业：主线角色模板、四种新增职业刷新与学习来源

> evidence: static-derived; resource-derived: PLAYERS／OBJ 源字段 · status: live · functions: 0x42c700, 0x42caa0, 0x42cac0, 0x4373f0, 0x437970, 0x437a40, 0x44cb10 · tools: hsltools/data/campaign_actors.py, hsltools/probes/campaign_actor.py, run_job_stats_tests.gd, test_hsl_level_battle.py · updated: 2026-09-27

## 结论

- 原版 34 个未放置角色模板（含最终章 059／060、第 37／80 关 066／067／068）经 `0x448840` 刷新的结果、推级／配额／出生调整与学习调用已完整执行；新增职业 93／95／96／98 各有独立刷新分支、上限行与学习归属，源 HP 半字按有符号读（static-derived）。
- 重制由 `tools/hsltools/data/campaign_actors.py` 生成 `content/generated/hsl/actors/0NN.json` 与 `roles/profiles.json`，职业公式入 `content/authored/roles/job_formulas.json`、学习表入 `roles/growth_lifecycle.json`，`game/sim/JobStatsRules.gd`／`LearningRules.gd` 消费（static-derived）。
- 已知差异：008 源装备 32 的 `range3CellCircle` 攻击范围未支持，原样初始化返回 `unsupported_equipment`；模板坐标 `[0,0]` 是未放置标记（provisional）。

## 证据

**static-derived**（EXE SHA256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；[original_campaign_actors.json](original_campaign_actors.json)）：34 角色 × 15 输入 × 2 次完整刷新（1020 返回）、99 个推级／配额／出生调整、206 个学习调用、4 个新玩家槽 16 次完整 helper 返回与 4 个工厂前段；原 callee 全部执行，模板、队伍等级与字符串缓冲区是夹具。

| 职业 | 刷新分支 | 上限（力／敏／精／体） | 学习归属 |
| --- | --- | --- | --- |
| 93 `jobWindWarrior` | `0x44a446`，接翼战士公共数值分支；魔法 +20 在基础上限之后 | 550／770／390／730 | `0x4783fc` tier 2；先查高阶风系门槛，再落入基础风系 |
| 95 `jobCrazyWarrior` | `0x44a8a6`，接兽战士公共数值分支 | 750／500／350／850 | `0x478444` tier 2；无等级自动魔法 |
| 96 `jobMutantMonster` | `0x44ab84` | 80／84／80／106 | 魔法／特殊学习分派均无该职业分支；源初始持有不受影响 |
| 98 `jobMagicSwordMan` | `0x44b168`、`0x44b430` | 90／82／90／90 | `0x4784ac` tier 1；独立土／精神／风魔法门槛 |

- `0x4786bc` 20 行上限与 `0x44b820` 职业跳表有原字节指纹；93／95 抗性系数各自保留，96／98 用各自整数除法顺序；公共收尾把装备／源加成后为负的攻、防、魔攻、速度夹到 0（032 的基础输入命中此边界）。
- 学习：`0x4373f0` 以存储等级+1 查魔法；`0x437a40` 选职业特殊表，`0x437970` 返回第一项未持有且满足基础属性／tier 的技能。初始 mask 来自 PLAYERS 与 mag-spc.h。
- 066（第 37 关守卫，`jobCrazyWarrior`、pmEnemy、`hit_point -10000`）与 067（柱子寶石，`jobCrazyWarrior`、pmMagicAttack、`no_attack 1`、`hit_point -10000`）：源 HP 半字 `+0x1b6` 按有符号读，公式值加 −10000 后公共收尾夹到 **最大 HP 1**；再由 STORY037 `actSetPlayerUndead` 设不死身，普通攻击「毫無效果」（WINFAIL037 2096）。`0x40e870` 同样按有符号 16 位读该半字。
- 068（第 80 关怨念體，`jobPriestMaster` 86、pmEnemy、`size_type 1`、1200 HP、move 0）：1 级最大 HP 1293、MP 92；源魔法 8 种都是已支持技能 id。
- 玩家 005／007／008／009 的槽 4／6／7／8 经 `0x42c700`、`0x42caa0`、`0x42cac0` 与完整 `0x44cb10` 复制核对；工厂 `0x407eff→0x407f14` 只作有界前段。

**resource-derived**

- global.obs 物件 804／806／807／808 与 SID_PLAYER4／6／7／8 是独立资源声明；来源 mode、当前阵营、可控性、原对象种类互不替代（064 `pmNPCPlayer`、024 `pmPlayer` 不因此成为受控伙伴）。
- 敌方克羅蒂 `Enemy053`（第 21／24／30／36／71／903 关 obs）写 `obj_Data6 = SID_ENEMY053`、`obj_Data7 = 53`、造型 `SHAPE\009-00001.SHP`；构造器 `0x407ec0` 复制 PLAYERS 行 `obj_Data7`，故规则模板是 053（`jobDarkSwordMan` 99、源 HP 220、`FACE0008`、`level_adjust_range 30,1`），画面走 SHAPEDEF `SID_ENEMY053` 块的 `SHAPE\009-*`，死亡姿势 `SHAPE\009-P.SHP`，切入取 ANIMAL `SID_ENEMY053` 块的 P053 条（s_shape P009_201）。
- SHAPEDEF 的 `SID_PLAYER17`（018）块未被注释、绑定 `SHAPE\053-*`；被注释掉的是另一份 `SHAPE\018-*` 块。「018 无 SHAPEDEF 绑定、转职后保留 009 形态」的读法与资源不符（未改，属转职表现）。
- 飞行不随职业继承：声明飞行的是 038／035／041／043／056／051；034 与 036 同为翼战士但无源飞行；051 另有 `size_type=1`；`no_block` 均为 false。
- 005／008／067 缺 `find_type`、`find_range`、`ai_call_range`、`ai_fixed`，模板保留缺项（`source.ai.missing_required`），不借他人策略。

## 重制接线

- `tools/hsltools/data/campaign_actors.py`（`CAMPAIGN_ACTORS` 驱动）→ `content/generated/hsl/actors/0NN.json`（`hsl_source_actor_template.v1`）与 `roles/profiles.json`；每条带 PLAYERS.TXT 行号／哈希、职业 symbol／TYPE.H 值、初始等级是否声明、证据等级与原函数结果。
- `content/authored/roles/job_formulas.json`、`learning_tables.json` 的 evidence 字段引用本包；`game/sim/JobStatsRules.gd`、`game/sim/LearningRules.gd` 消费。
- `tools/hsltools/levels/battle.py`：对预览带 `source_actor_code` 的 EVEF 敌人按该行建（第 30 关克羅蒂为 `actor053_1`）。
- `tools/hsltools/sources/actor_walk_frames.py` `_shape_fields`：先认演员自己的 `SID_ENEMYnnn` 块再按造型编号猜；`actor_hit_poses` 同理。
- 未声明的 level1／EXP0 只作出生前核对输入；实际战斗等级由 `InitialRosterGrowthRules`／`EntryGrowthRules` 产生（[original_auto_growth.md](original_auto_growth.md)）。
- `hsltools/probes/auto_growth.py` 的回读与期望模型按有符号 16 位回绕。

## 复现

`python3 tools/hsl.py check campaign_actor`

## 边界

- 008 源装备 32 的 `range3CellCircle` 未支持，`source.runtime_blockers` 保留；替换证据是原范围 builder／矩阵及玩家、AI、反击的共同范围测试。Godot 只以无装备数值夹具对拍其 96 分支。
- 模板坐标 `[0,0]` 须由组装方用本关 EVEF／脚本锚点替换（provisional）。
- 敌方过程均为 `defProcEnemy`、玩家 `defProcPlayer`，不代表整个原 dispatcher 的行为。
- 转职事务、原完整 parser／constructor、全局随机流、负属性／溢出区间不在本包。

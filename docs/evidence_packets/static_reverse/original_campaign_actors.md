# 职业：主线角色模板、四种新增职业刷新与学习来源

> evidence: static-derived; resource-derived: PLAYERS／OBJ 源字段; provisional: 模板坐标、reserve 状态字、HP≤0 重装与名单排序 · status: live · functions: 0x4075e0, 0x407ec0, 0x4080b0, 0x42c640, 0x42c700, 0x42c7e0, 0x42caa0, 0x42cac0, 0x42caf0, 0x42cb30, 0x4348f0, 0x4373f0, 0x437970, 0x437a40, 0x4483c0, 0x448840, 0x44cb10 · tools: hsltools/data/campaign_actors.py, hsltools/probes/campaign_actor.py, run_campaign_tests.gd, run_growth_lifecycle_tests.gd, run_job_stats_tests.gd, test_hsl_level_battle.py · updated: 2026-10-06

## 结论

- 原版 34 个未放置角色模板（含最终章 059／060、古代神殿遺跡（LEVEL037）／禁忌之魂・墳場地下（LEVEL080）的 066／067／068）经 `0x448840` 刷新的结果、推级／配额／出生调整与学习调用已完整执行；新增职业 93／95／96／98 各有独立刷新分支、上限行与学习归属，源 HP 半字按有符号读（static-derived）。
- 重制由 `tools/hsltools/data/campaign_actors.py` 生成 `content/generated/hsl/actors/0NN.json` 与 `roles/profiles.json`，职业公式入 `content/authored/roles/job_formulas.json`、学习表入 `roles/growth_lifecycle.json`，`game/sim/JobStatsRules.gd`／`LearningRules.gd` 消费（static-derived）。
- 注册移除不清记录：WINFAIL053 win 0 `actDeletePlayerCode SID_PLAYER1, 0` 只清槽 1 的注册码，緹娜 的 live 记录（索引 2）连同玩家第 3 场 · 逃出克萊恩城（LEVEL053）的等级、经验与学会的魔法留着；玩家第 5 场 · 戈爾山道（LEVEL002）的 `obj_Story_Player2` 重装槽 1 时构造器不复制模板，沿用该记录。重制以 carry 的 `reserve_units` 承接，LEVEL002 重装与之后各关保留（static-derived）。
- 跨关承接：注册表 `0x4c4360` 只存槽码，状态全在 live 记录；每关入口 `0x4075e0` 对所有已注册槽回满 HP／MP、ST 归零（`actKeepPlayerST` 时保留），阵亡不注销，未上场成员照样随队；重制 carry 照此传下未上场成员、脚本插入沿用其记录，reserve 带走离场时的 HP／MP／ST（static-derived）。
- 008 源装备 32 的 `range3CellCircle` 由[武器范围](original_weapon_ranges.md)接入：`content/generated/hsl/equipment/items.json` 32 号 `supported: true`，`actors/008.json` 的 `runtime_blockers` 为空，原样初始化不再被拒（resource-derived 生成物）。
- 已知差异：模板坐标 `[0,0]` 是未放置标记（provisional）。

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
- 注册移除（opcode 71）：跳表项 `0x450dd0` 以脚本两参数 `(slot, clear)` 调 `0x42caf0`；`0x42cafa` 无条件把 `0x4c4360[slot]` 写 0，`0x42cb05` 在 `clear == 0` 时直接返回，否则 `0x42cb09..0x42cb21` 把 `*0x4c1bc8 + (slot+1)×0x1fc` 的 127 个双字清零。全部剧本只有两处：WINFAIL053 win 0（`SID_PLAYER1, 0`，记录保留）与 WINFAIL015 event 4（`SID_咕嚕, 1`，记录清零）（注册与离队为 static-derived：`0x4080b0`／`0x42caf0`；脚本出处 resource-derived，`content/imported/hsl/story_corpus/scripts/`）。WINFAIL015 的 event 4 是 event 2（第 27 回合）选项「2.不救」的分支；event 2 先 `actInsertStoryObject obj_Story_Player8` 装入咕嚕，OBJ-015.OBS 的 code 13（`obj_Story_Player8`，OBJ-ALL.H）是 `defProcPlayerInstall`、`obj_Data9 = 7`、无 Data8 的普通安装，经 `0x42cb30` 注册槽 7，所以 event 4 注销的是已注册的咕嚕：选「不救」后他不再是队员、记录清空；选「1.救」走 event 3，不注销（resource-derived，原 PAK `@:\data\obj-015.obs`）。
- 重装：构造器 `0x407ec0` 对玩家对象只在 live 工作属性 `+0x4c..+0x58` 全零时走模板复制 `0x44cb10(slot, 1)`，否则只写本次安装参数并 `0x448840` 刷新（[original_level37_tokens.md](original_level37_tokens.md)）；魔法位在记录里，随记录保留。第 2 关 STORY002 event0 的 OBJ-002（`defProcPlayerInstall`、`obj_Data9=1`，[original_player_install.md](original_player_install.md)）经 `0x42cb30` 重新注册空槽 1（801）后进构造器。
**注册表字段与交接写回**（static-derived，r2 读 `0x42c7e0`／`0x42c640`／`0x4075e0`／`0x4080b0`／`0x407ec0` 与注册表全部访问点）：

| 字段 | 交接（关卡结束→下一关入口）写什么 | 装人读什么 | 阵亡／未上场 |
| --- | --- | --- | --- |
| 槽码 `0x4c4360[0..19]`（`800+槽`，转职后为 Up 码；bit 31＝禁用） | 关卡结束不写；只由新游戏 `0x42c7e0`（全清后槽 0 写 800）、安装启用 `0x42cb30`、转职 `0x4348f0`→`0x42c700`、脚本移除 `0x42caf0` 改写；无调用者写 bit 31 | `0x4080b0`：`0x42caa0(Data9)` 非零→`0x407ec0` 构造；为零且 Data8＝0→`0x42cb30` 注册后构造；为零且 Data8≠0（有才產生）→删占位不装 | 阵亡不注销（死亡路径 `0x407720` 只清对象队列）；未安装的注册槽保持注册 |
| live 记录 `*0x4c1bc8 + (槽+1)×0x1fc` 的 HP `+0xd8`／MP `+0xe0` | 入口 `0x42c640`→`0x4075e0` 对 `0x42caa0` 非零的槽写 HP＝`+0xdc`、MP＝`+0xe4`；战斗中对象直接改这份记录，结束时不另写 | 构造 `0x407ec0`：工作属性 `+0x4c..+0x58` 全零才复制模板 `0x44cb10`；否则沿用记录，HP≤0 时删对象不装（`0x407f4f`），随后 `0x448840` 刷新夹到上限 | 阵亡与未上场的注册成员下一关同样回满；已移除注册的记录（reserve）不被回满 |
| ST `+0xe8` | 同一循环：`[0x4c1af0]==0` 时写 0（`0x407632`）；`actKeepPlayerST`（opcode 69，`0x452a06`）置 1，循环后清 | 沿用记录 | 未上场成员同样清零／保留；reserve 不经入口，保留离场值 |
| 临时字 `+0x24`、`+0x30..+0x48`、`+0xb0` | 同一循环 `0x4483c0` 清零后 `0x448840` 刷新；`+0xa8` 写 0 | 沿用记录 | reserve 不清 |
| 等级／经验／属性／装备／物品／魔法 | 不写 | 沿用记录 | 全部随记录保留 |

- 槽 0..19 以外（索引 21 起）是本关演员的临时记录，`0x44cb10` 每次安装从模板复制，不跨关。

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
- `game/sim/CampaignCarryRules.gd`：carry 代表注册槽表——`apply` 对开场名单里的承接成员回满 HP／MP、ST 按 `keep_stamina`，未在名单的承接记录存入回执 `unfielded_units`；`capture` 把本场既未上场也未被脚本插入的成员原样传下（阵亡成员照带）。`RESERVE`（`reserve_units`）＝注册被移除、记录保留的成员；`separate_party_carry` 把 separate party（53 关）的成员连同离场 HP／MP／ST 记为 reserve，`capture` 把未上场的 reserve 原样传下，`apply` 对预置单位套用（HP／MP 夹到刷新后上限）；`game/sim/ScriptActorCreationRules.gd` 的 `registered_player` 插入对已承接成员套用 `unfielded_units` 记录（`script_creation.carried_record`），对 reserve 成员套用 reserve 记录（`script_creation.reserve_record`）。reserve 不进城镇名单、不参与条件安装。`tests/run_growth_lifecycle_tests.gd` `reserve_member_learning` 钉 53 学会 水剎 → 1 关 → 2 关重装保留。
- `hsltools/probes/auto_growth.py` 的回读与期望模型按有符号 16 位回绕。

## 复现

`python3 tools/hsl.py check campaign_actor`

## 边界

- Godot 只以无装备数值夹具对拍 008 的 96 分支；带 32 号武器的刷新走通用装备叠加。
- 模板坐标 `[0,0]` 须由组装方用本关 EVEF／脚本锚点替换（provisional）。
- 敌方过程均为 `defProcEnemy`、玩家 `defProcPlayer`，不代表整个原 dispatcher 的行为。
- reserve 记录的状态字（`+0x24` 等）原版随记录保留，重制不带状态；HP≤0 的注册记录被重装时原版删对象不装，重制未建模（第一章无此局面，provisional）。LEVEL053 的金钱与战利品仍按 separate party 不带走（重制策略）。
- 原版战斗中途注册成员阵亡后又被同关脚本重装的删对象路径、城镇名单按槽序排列与重制 carry 字典序的差别未对齐（provisional）。
- 转职事务、原完整 parser／constructor、全局随机流、负属性／溢出区间不在本包。

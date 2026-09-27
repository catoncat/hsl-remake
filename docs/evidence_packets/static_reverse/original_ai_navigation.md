# AI持有目标、等待与地图选点

> evidence: static-derived; resource-derived: EVEF 字值; provisional: 固定点逐格路线 · status: live · functions: 0x40c9a0, 0x40cca0, 0x40d530, 0x40d800, 0x40d8b0, 0x40f8b0, 0x40fa80, 0x40fb20, 0x411080, 0x411a30, 0x411b90, 0x413390, 0x413740, 0x42bd50, 0x43fbd6, 0x45ec32, 0x45ec63 · tools: hsltools/levels/seed.py, hsltools/probes/ai_navigation.py, run_ai_navigation_tests.gd, run_battle_reward_tests.gd · updated: 2026-09-25

2026-09-17。基线为`6cce138`，继续已有伤害／经验、自保和友军支援链。当前批次的玩家结果是：敌人可以绕过障碍持续追击，失去目标后重新决策，范围法术可瞄准空格，原初始等待和守备范围进入相同行动出口。默认第一战技能、库存、等级和速度不因测试新增能力。

## 对照与本批选择

| 体验 | 原证据与原有实现 | 接入结果 |
| --- | --- | --- |
| 连续敌人行动 | 原`object+0x88`持有对象槽号；旧实现每行动都从头选敌 | PlayLoop单位保存稳定`ai_target_id`，依原距离／概率保留或替换；死亡、离场和终态清除 |
| 等待与战斗节奏 | wait_round源字段及`0x43f603`的受伤／状态／近敌分支；旧实现未保留剩余等待 | 一次Wait递减一次；受伤、异常或八格圆域近敌结束等待；真实短待机反馈后交接 |
| 追击与站位 | 旧贪心只选择离敌人更近的可达格，在墙角停滞 | 在整个当前合法地图上寻找真正能发动已有行动的格子，沿最便宜路径走本行动预算；允许暂时远离敌人绕路 |
| 空地法术中心 | 原`0x40c9a0`遍历正值施法格，不要求格内有角色；旧规划只遍历角色格 | 玩家／敌方／支援共用真实目标加独立中心，枚举全部有效空格／角色格中心，按有效覆盖选点 |
| 回退与目标失效 | 已有自保、残血机会、同伴支援、源行动桶和概率 | 继续原有优先链；永久无效果或没有合法接近路线的目标不阻塞其他目标；无行动时Wait，守备者可返回出生锚点 |
| 路径／数值／界面 | 已有源演员、脚步、施法、逐目标反馈、经验与收尾 | 路径标记读取实际receipt；中心预告、玩家悬停人数及效果同坐标；保留完整特效／数字／经验后交接 |

已成立的普通伤害、暴击／反击、气力、风火、支援贡献和EXP公式直接复用。本包不由测试通过升级这些独立来源的等价范围。

## 原指令证据

[原结果JSON](original_ai_navigation.json)由[hsltools/probes/ai_navigation.py](../../../tools/hsltools/probes/ai_navigation.py)执行固定SHA的`hsl01.exe`生成。全部目标和输入状态是合成数据，原代码与调用者字节只读，没有函数stub或替换返回值。

| 路径 | 覆盖 | 明确终点 |
| --- | --- | --- |
| `0x45ec32`圆域与`0x45ec63`曼哈顿域 | 52组，轴向／四斜向、3–4距离、边界内外 | 完整正常返回，包括期望调用栈归还地址 |
| `0x43f55f`已有目标前段 | 30组，移除、搜索距离、守备半径 | 到下一新搜索或保留分支；不是整dispatcher返回 |
| `0x43f603`初始等待 | 12组，0/1/3次剩余、健康／受伤／毒／禁魔 | 停在近敌查询或正常决策入口，不运行全回合 |
| `0x441002`锁定比较 | 24组，0/30/60/100与临界roll | 停在重新搜索或保留分支；不是整回合随机流 |

三个loader锚点分别确认`wait_round→live+0x1b8`（缺省0）、`ai_fixed→+0x1d0`、`ai_lock→+0x1e8`。`ai_fixed`是以原对象出生坐标为中心的**半径**，不能按字段名解释成固定不动开关。`ai_lock`比较1..99的已有样本或相应新样本；0不保留，100总保留。

新目标查询使用圆域；已有目标保留使用曼哈顿域。固定半径新查询也使用圆域，保留路径使用曼哈顿域。这两个函数不同，不能统一改成同一种“距离”。八个方向的临界例直接和原返回对照。

当前移动力的来源已经进一步连通：源`move_point`载入角色`+0x130`，`0x448987..0x448998`刷新复制到`+0x12c`，后续装备可叠加。当前AI近域以live `move_point`绑定；本批同时修复了实际路径仍优先读取旧`move_range`镜像的问题。PlayLoop的玩家可达格、AI当前格搜索和追击预算现在统一读取live `move_point`。

## 地图搜索的已证合同与适配边界

`0x40c9a0`按原施法矩阵遍历中心；`0x40cca0`遍历移动矩阵中的合法站位，保留最大覆盖候选。源循环一次update的1/2/5/8个工作预算会保存游标继续，不能当作总共只搜索几个格子。原移动候选缓存最多250项；当前地图规划遍历全部合法站位，不复刻该缓存容量。候选生成、当前WRD地形和occupancy仍走共享`TacticalGridRules`，不是重新执行原引擎全套地图flag处理。

`SkillTargetRules.candidate_centers`使用每个真实目标的反向效果矩阵，获得所有可能有效的地图中心，再与某站位的施法矩阵相交。这与遍历整图再排除空效果格的集合相同，不要求中心里有对象。选择中心不会伪造角色、血量或经验接收者；收据分别存`cast_center`和真实`defender_id/affected_targets`。全区域资格和数值在任何RNG、扣费、移动前验证。玩家`attack_coord`、悬停预览与AI使用同一入口。

原中心循环分别维护全部覆盖和包含主目标的覆盖，有独立的平分随机流；只有一个有效主目标且其自身格可施放时，优先目标格。当前保留主目标的有效覆盖、目标格单体优先与等覆盖中心随机替换已经接入；**完整双候选流和原全局RNG顺序仍未等价**。原站位“离近处威胁更远”后缀继续复用已有独立原结果。

`0x40d530`中的八个周边格加中心是**大体型目标占地**的接近候选，不能推出普通角色可斜向走路。普通地图仍按四方向路径走格，八方向目标位置接受各自技能／武器矩阵校验。原大型占地、特殊移动模式、全部高差／地块flags仍在独立后续边界内。

全图追击先求实际能到达的攻击／已有可用技能站位（决定目标是否可追），本回合走法则是下文「普通追击也走同一条精化链」的 `0x4111a0` 精化（lane R7-AI51 接入，`AINavigationRules.approach_point`）。不拥有、付不起、禁魔、概率为0以及永久无效的毒目标不会生成对应技能接近点；仍能普通攻击的目标保留普通接近点。接近点的最短路径平分顺序、不同未来动作的路径比较是明确的重制组合。它保证不穿占用或阻挡，不声称重现原所有模式的寻路。

本批收尾另有[四邻扩展与邻接代价](original_movement.md)：58份完整原扩展、80份邻格helper返回，已接入共享范围／路径／本行动预算。先登记落脚余量再扣继续扩展的邻接费用；0xff地形墙与低位对象阻挡分别处理。路径和累计成本在全部更新后一起构造，原全地图模式与通行资格仍按该包边界保留。

## 状态、回退和表现

`AINavigationRules`只提案；PlayLoop预检完全部输入后才执行选择。被接受的一次动作才提交新的持有目标和剩余等待。原普通目标与临时残血机会／援助患者继续分开，呼叫也保持独立字段；援助不会把自己的同伴存成敌人锁定。用稳定ID、清理死亡／剧情离场引用是当前适配策略，原对象槽复用生命周期未宣称等价。

共享原优先级保留自救、残血敌方机会、自清毒、友军治疗／驱毒／真实药品，之后合法普通／魔法／绝技选择和追击。未接受的类别不会付款；目标失效、MP不足、禁魔或无有效支援按已支持动作继续。全部无效则显示待机并结束一次行动。格式错误仍是明确scenario_error，不通过Wait掩盖。

`BattleNavigationCue`仅消费实际路径，画细路径与落点；沿ActorRuntime的真实移动状态清除，脚步仍由原演员播放。Wait增加0.55秒“待機”短反馈，纳入现有`combat_busy`屏障；这是可读性的重制取舍，没有新战斗phase或排队状态。显式开发fast-forward可以清掉它，但不再扣资源或推进状态。

空格预告、技能名、受影响人数和效果使用同一中心与world→logical投影；逐目标数字继续绑定各自角色。伤害／支援经验、死亡、领取、后继与胜負仍由已有事务和只读收尾执行。存档包含持有ID、守备锚点和剩余等待，恢复不重抽决策。终态清理目标并冻结后续AI步骤。

## EVEF 实例覆盖：友军护送目标与物品

2026-09-22，lane R16（起因：[17 关护送战对照](../runtime_observations/original_level17_escort/README.md)里原版 克里夫 064 每回合移动并自疗，重制 064／062 全部待机）。以下为 `pD` 线性读法（static-derived），未做有界执行；EVEF 字值 resource-derived（`tools/hsltools/levels/seed.py` `_actor_instance`，总表 [evef_instances.json](../../../content/generated/hsl/development/evef_instances.json)）。

**没有按阵营分支的移动模式。** AI 过程 `0x43ede0` 只经 `0x40ba20`（自身侧位）／`0x40ba80`（`~mode & 0x70000` 敌方搜索 mask，0x50000 → 0x20000）／`0x40bab0`（地面模式 2／3／7）读取 `+0x28` 阵营字；`0x40bb80` 的排除条件是 `own & other & 0x870000`，友军（0x50000）把玩家（0x10000）当同侧、敌军（0x20000）当目标。友军与敌军走同一 dispatcher。

**无武器的普通路径不移动。** `0x409090(actor)` 返回武器射程索引：`+0xec`（武器）为 0 时返回 0。普通进攻 case 7（`0x43fd4b`）在 `0x43ff1f`／`0x440041` 调它，返回 0 直接跳 `0x441eb8`（`+0x8c = 0x640001`，本回合结束，不进入追击）。17 关三名 062（`weapon_equip` 空）因此原地不动——与重制 `approaches` 为空后的 `no_valid_action` 待机是同一结果（重制过滤器回执见 `ai_decision.candidate_filters`）。

**实例安装回调 `0x42bd50`。** 关卡创建入口把它作为 EVEF 实例回调（同宝箱包）。对象过程 3（defProcPlayer）／5（defProcEnemy）分支（`0x42bd96..`）在 `0x44cb10` 取得 live 记录后：

| 实例记录字 | 写入 | 读法 |
| --- | --- | --- |
| `0x10..0x2C` 八个 DWORD | live `+0x138` 八个物品槽 | `0x42be2e..0x42be79`：逐字找第一个空槽写入（游标不回退），非零才写；模板背包之后追加 |
| `0x50 + 4·i`，i = 0..31（`0x42bf4c..0x42c08b`，跳转表 `0x42c0a8`） | i=0 `+0x98` gold；1 `+0x1c0` find_type；2 `+0x1c4` find_flag；3 `+0x1c8` find_range；4 `+0x1cc` ai_call_range；5 `+0x1d0` ai_fixed；6 `+0x1d4` ai_check_dying；7 `+0x1d8` ai_check_hp；8 `+0x1dc` ai_help_otherhp；9 `+0x1e0` ai_help_status；10 `+0x1e4` ai_help_attack；11 `+0x1e8` ai_lock；12 `+0x1ec` ai_att_special；13 `+0x1f0` ai_att_magic；14 `+0x1b8` wait_round；16 `+0x1fa`／17 `+0x1f8` 调级范围高／低字（16 位）；18–23 `+0xec..+0x100` 六个装备槽；24 `+0xe8` 气力 | 零值跳过；字段名按 PLAYERS loader `0x44c7e0` 的同一偏移（`ai_att_special` 写 `+0x1ec` 于 `0x44ca2f`） |
| i=15（`0x42c012`） | 对象 `+0x80 \|= 0x4000`；live `+0x1d0 = 8`；对象 `+0x46`（x）＝(高 16 位 & ~0x1f)+0x10，`+0x44`（y）＝(低 16 位 & ~0x1f)+0x10（像素，格心） | 「跑到固定点」：17 关记录 8 的 `0x04A00240` → (37,18)；34 关三名村民 → (5,19)／(7,13)／(24,5)；1 关八名村民 → 左上角 (6..9, 2..4)／(21,12) |

`+0x44`／`+0x46` 即守备锚点：`0x43f5b1` 与 `0x440f30` 把它们与目标像素一起传给 `0x45ec63`／`0x45ec32`（第 1／2 参数 = `+0x46`，`+0x44`；`0x45ec63` 计算 |a1−a3|+|a2−a4| ≤ r）。

**固定点守备的移动（mode 5 sub 0）。** 优先级检查之后 `0x440ef1`：`ai_fixed ≠ 0` 时先 `0x409090`，无武器（或持有目标不在锚点圆域内且重搜失败）→ `0x440fd3` 写 `+0x8c = 0x50000` → 下一帧 `0x43fbd6`：对象像素 == 锚点 时，若 flag 0x4000 置位则清位并写 `ai_fixed = 0`（`0x43fbf1..0x43fc0e`）后结束回合；否则 `0x43bf30(actor,0)` 非零 → `0x4111a0(actor, +0x46, +0x44, 0x12, +0x12c 移动力)` → `0x411080`：以 `max(18, 移动力)` 为半径 `0x40f440` 洪泛，`0x413900(x,y)` 取洪泛内离目标点曼哈顿最近的可停格（`0x413740`：跳过含任何单位的格 mask 0x70000，等距时 `0x458c10 & 1` 非零换新；`0x40d800(格) ≥ 3` 时 `rand(100) < 80` 跳过），再以该格为新目标半径减 2 重复直到半径＝移动力，最后 `0x410a50` 提交。到达点后 `ai_fixed = 0`，此后按普通路径（无武器即不动）。`actSetPlayerFixPos`（WINFAIL017 事件 1，第 6 回合 `SID_ENEMY064 1 1024 416 1`；WINFAIL012 第 8 回合 32 名 038 的图外撤退点）同样写锚点 `+0x46`／`+0x44` 与 `ai_fixed`（distance≠0 时），不移动对象——opcode 体读法见 [original_fixpos_fly_prev_insert.md](original_fixpos_fly_prev_insert.md)。

**重制接法。** `seed.py` 把实例字解码进 `placements[].actor_instance`，`battle.py`／`scenario.py` 挂到单位 `evef_instance`（items／overrides）；运行时 `ActorInitializationRules.apply_instance_words`（物品补进空槽、气力）、`AINavigationRules.instance_profile`（1..14 逐字段覆盖声明 profile；固定点未到达时 `ai_fixed = 8`，到达后 0）、`initialize`（wait_round 进 `ai_wait_remaining`，固定点写 `ai_home_coord` 并置 `ai_fixed_point_pending`）、`ReinforcementGrowthRules.prepare`（16／17 替换调级参数；金钱输入经 `BattleRewardRules.kill_gold`）、`BattleRewardRules.kill_gold`（字 0 gold 覆盖击杀金钱，R27）；`_ai_take_turn` 无合法目标且 `ai_fixed > 0` 时：站在锚点→清 pending 并抹掉脚本半径 `ai_fixed_radius`（`wait_reason=fixed_point_reached`），否则 `approach_home`（lane R23 起复刻 `0x411080` 精化）：以 `max(18, 移动力)` 为预算从演员洪泛（重制移动代价洪泛），取洪泛内可停格中离目标点**曼哈顿**最近者（跳过含单位的格，含自身格；等距抛 `rand(2)` 硬币换新），再以该格为新目标、半径减 2 重复至半径＝移动力，最后一格即本回合终点；回执 `home_approach.refinements` 逐级记录半径／目标／选格。脚本锚点在图外（WINFAIL012）时曼哈顿距离照算，单位走到最近的图边。`0x40d800` 的 80% 拒绝自 lane R7-NPC 起复刻（见下文「候选过滤与攻击站位」）；仍 provisional：洪泛的原生代价度量与候选遍历顺序、奇数移动力最后一级的收缩方式；装备字 18–23 只记录不应用（数据 0 单位）；gold 字自 R27 起为击杀金钱覆盖。

**边界（precise provisional，2026-09-24 lane R25 改写）。** 字段映射本身不是 provisional：跳转表 25 个 case 的写点已由反汇编读出（`0x42bf50 mov eax,[rec+edx*4+0x50]`；`0x42bf5a je` 零值跳过；`0x42bf60 cmp edx,0x18; ja` 超过 24 走 default；case 18–24 的装备／气力 store 在 `0x42c055`（+0xec）、`0x42c05d`（+0xf4）、`0x42c065`（+0xf0）、`0x42c06d`（+0xf8）、`0x42c075`（+0xfc）、`0x42c07d`（+0x100）、`0x42c085`（+0xe8）；`0x42c096 call 0x448840`），字段名来自 PLAYERS loader `0x44b980` 对同一偏移的写入（`gold→+0x98`、`weapon_equip→+0xec`、`head→+0xf0`、`armor→+0xf4`、`foot→+0xf8`、`other1→+0xfc`、`other2→+0x100`、`stamina→+0xe8`），与 `seed.py ACTOR_INSTANCE_OVERRIDE_FIELDS` 逐项一致。「装备字只记录不应用」对已注册数据是空操作，gold 接通亦无数值变化（resource-derived，`evef_instances.json totals.override_fields`）：70 关 569 个演员实例里六个装备字 0 次；gold 仅 53 关记录 Enemy023 [30,36] 写 100，而 PLAYERS 023 模板 gold 本就是 100（`content/generated/hsl/combat/rewards.json`），覆盖前后同值。

仍是 provisional 的只有走位的度量与两处未复刻分支——**lane R23 已在 `AINavigationRules.approach_home` 复刻上述精化**：半径 `r = max(18, 移动力)` 起以重制移动代价洪泛（对应 `0x40f440`），取可停格中到目标格曼哈顿最近者（含单位的格与自身格跳过，等距 `rand(2)` 换新，对应 `0x413740` 的 `0x458c10 & 1`），`r −= 2`（下限移动力）以该格为新目标重复，`r == 移动力` 时的选格即终点；回执 `home_approach.refinements` 逐级记录半径／目标／选格。`0x40d800` 候选过滤与最后一级的自身侧 mask 已由 lane R7-NPC 复刻（见下文「候选过滤与攻击站位」）；仍 provisional：原生洪泛的代价度量与候选遍历顺序、奇数移动力最后一级的收缩方式。对照（[original_level17_escort](../runtime_observations/original_level17_escort/README.md)，all-wait seed 1）：064 第 1 回合原版两次运行都落 (33,15)，R16 路径距离排名落 (32,17)，R23 精化后落 **(33,15)**（精化链 (37,18)→(36,18)→(36,16)→(34,16)→(33,15)）；第 2 回合原版 (34,18)／(36,16)（run 2 第 3 回合），重制 (36,16)；第 3 回合到达 (37,18) 释放。逐格一致只在两次原版运行都一致处声明。替换证据：对 `0x411080` 用 17 关 WRD／占位做有界执行逐回合对照（可同时读出 `0x40d800` 阈值 3 的「被围」语义），或 Wine 12 关第 8–10 回合观察 038 的撤退路线。当前实现不支持的结论：护送战全程逐格与原版一致；80% 拒绝对路线的影响。69 号演员在 52 关装入时由 EVEF obj_Data9 1 换成敌方（`0x407ec0`），第 1 回合原地待机（runtime-measured），已进重制 52 关名单；62 关不在本包范围。

**52 关（user-confirmed 对照）。** 用户实机打过重制前两战后报告：原版第二战（惡夢的終曲）皇帝与上方队（法师＋重装兵）**不会立刻下来**，重制则一开始就冲锋，并预期多数关卡有同样差异——与 EVEF 解码一致：记录 5 皇帝 025 `wait_round 8`／`find_range 10`，记录 8／9 两名 026 `wait_round 2`／`find_range 12`（重装兵 069 记录 34／35 `find_type 6`／`wait_round 5`，未上场）。重制 all-wait 复跑（[remake_all_wait_trace_level52.txt](../runtime_observations/original_level17_escort/remake_all_wait_trace_level52.txt)，`HSL_TRACE_PLAYER_HP=9999` 只为让等待计数跑完）：皇帝第 1–8 回合 `wait_round` 7→0，第 9 回合起 `no_valid_action`（find_range 10 内无敌）仍留在原地；两名 026 第 1–2 回合等待，第 3 回合才动。这是 user-confirmed ＋ resource-derived 的组合，不是 runtime-measured 的原版逐回合数据。

**普通追击也走同一条精化链（static-derived，lane R28，2026-09-22）。** r2 有界读 AI 过程 `0x43ede0` state 0xb（`+0x8c = 0xb0000`，普通进攻）sub 0：`0x409090`（武器射程索引）→ `0x40fa80(actor, range)` → `0x40fb20(持有目标, &0x4c2980, &0x4c297c)` 非零→ `+0x8c = 7`（本回合可攻击，去站位）；为零时 `0x440d5c..0x440d84`：`0x4111a0(actor, 目标+4, 目标+8, 0x12, actor+0x12c)`，即与固定点行走（`0x43fbd6 → 0x4111a0(actor, +0x46, +0x44, 0x12, +0x12c)`）**同一个入口、同一组参数**，只是目标点换成持有目标的像素坐标；非零则 sub++、`+0x94 = 0xc`（走路），为零且 flag 0x10000 未置则结束回合。因此 `AINavigationRules.approach_home` 复刻的 `0x411080` 精化（半径 max(18, 移动力) 洪泛 → `0x413900` 曼哈顿最近可停格 → 半径 −2 重复）就是原版**通用**逃近算法，可直接复用于目标追击（现在 `_ai_take_turn` 末尾的 pursuit 仍是 `route_to_goals` 最短路＋`advance_path` 前缀，重制组合）。另据 `0x413740` 反编译：`0x40d800(x, y, mask|0x4000)` 只数四邻中命中敌方侧位或 0x4000 障碍位的格，WRD 0xff 悬崖不带 0x4000（[原移动包](original_movement.md)），所以 80% 拒绝只在被 ≥3 名敌单位／对象障碍包围的落脚格上触发，不会因地形走廊触发；`param_1`＝1 的 `0x413930`（`0x40e6e0` 调）是同一扫描的“最远”变体。**已接入（lane R7-AI51）**：`_ai_pursuit` 改走 `AINavigationRules.approach_point`（与 `approach_home` 同核，目标＝持有目标格），回执 `ai_decision.pursuit_approach`；无普通攻击（`no_attack`）只去施法位的单位保留最短路前缀（provisional，待读 `0x43ede0` 法术进攻状态的移动分支）。第一战录屏第 1 回合（原版与重制起始局面相同）12 个 AI 落点里 5 个在旧最短路前缀下不可能出现，接入后全部落在重制可产出集合内，逐项见 [battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)；`run_ai_navigation_tests.gd` `pursuit_walk_cases` 钉住并可消融。`0x40d800` 的 80% 拒绝已由 lane R7-NPC 接入（下节）。参看 [53 关包](../runtime_observations/battle_053/README.md)。

## 候选过滤与攻击站位

lane R7-NPC，2026-09-25。r2 线性读与 r2ghidra 反编译（同一 EXE），static-derived。

**`0x413740` 的候选过滤。** 洪泛矩阵行主序（y 外层、x 内层）逐格：未到达（字节 0 或带 0x80）跳过；格上有单位（`& 0x70000`）跳过；距目标像素曼哈顿距离等于当前最佳时先抽 `0x458c10 & 1`，为 0 跳过；严格更近（或等距且抽到 1）才进过滤：`0x40d800(x, y, mask)` 数四个**图内**邻格（左、右、上、下）的格字命中 mask 的个数，≥ 3 时 `rand(100)`（`0x458c80`）< 80 跳过（`0x413889..0x41389b`），被跳过的格不更新最佳。mask 由调用参数换算（`0x413775..0x4137ae`）：`0x10000 → 0x60000`、`0x20000 → 0x50000`、`0x40000 → 0x30000`，其他值原样，再或上 `0x4000`。`0x411080` 的收窄各级传 0（`0x41112b`：只数 0x4000 硬阻挡格），最后一级传 `0x40ba20(actor)` 的自身侧位（`0x41114d`：敌对单位也算）。重制 `AINavigationRules._nearest_stoppable` 按此过滤，格字取 `neighbour_words`（占位单位的侧位字、WRD 硬阻挡 0x4000，含战中地形编辑），回执 `refinements[].crowded_skips`。

**攻击站位 `0x40d8b0` → `0x413390`。** 普通进攻（`0x440041`）先用 `0x40d8b0(actor, 持有目标槽)` 从持有目标起逐槽找第一个有站位的敌对目标：抹掉自身占位（`0x411b90`）、按移动力洪泛，对目标以攻击者武器射程建范围（`0x40fa80`），`0x413390` 收集「洪泛到达 ∩ 射程格 ∩ 无单位」的格（自身格因已抹掉占位而可入选），行主序、上限 500；3×3 目标依 (−1,−1)、(0,−1)、(1,−1)、(−1,1)、(0,1)、(1,1)、(−1,0)、(1,0)、(0,0) 九个身体格为中心逐个试，取第一个有站位的。收集后**按离射程中心的半格偏置距离降序**插入排序：站位字存格中心像素（`cell*32+16`，`0x4134be..0x4134cc`），射程中心只左移 5 位、不加半格（`0x41363e..0x41364c`），所以键值是 `|2dx+1| + |2dy+1|`（半格单位，dx／dy＝站位格−中心格）——中心右侧／下侧的格比左侧／上侧同曼哈顿距离的格算得更远（lane AI-PRIO，2026-09-25；模拟器实测：第 3 关 028_1 16/16 种子取 leonard 右侧 (6,10) 而非上方 (5,9)，无抽取）。只有与紧前一项键值相等时抽 `rand() & 1` 交换，更远的项前移、更近的不动（`0x41362f..0x413716`），第一项即站位。state 0xb sub 0（`0x440b2c`）：站位离目标（对象像素）不比攻击者远、且攻击者四邻有敌（`0x40d890`，mask＝`0x40ba80` 搜索 mask）时，`rand(99)+1` 大于 92（武器射程索引 < 2，近战）或 78（远程）就仍走到站位；否则目标已在当前射程内（`0x40fb20`）就原地攻击（`+0x8c = 7`）；都不成立则 `0x410a50` 走到站位，到达后 sub 7 再判射程并攻击。站位比攻击者更远时直接走过去——远程单位会退到射程边缘。旧重制「路径最便宜、横移最少」的站位组合由此取代：`AINavigationRules.attack_stations`（预检，无随机）＋`attack_station`（提交时抽样），回执 `ai_decision.attack_station`（`order`／`draws`／`roll`／`reason`）。

**站位与出手按地形射程（static-derived，lane AI-PRIO，2026-09-25）。** 上述两处「射程」都是 `0x40f8b0` 地形洪泛（[原版武器射程](original_weapon_ranges.md)：`0x4000` 墙停、墙边前方检查 `0x40eb80` 截断、占位者按侧位不写），不是平铺 RANGE 记录：站位集合是**以目标为原点**的覆盖——`0x40d8b0` 在 `0x40d8c3` 先 `0x411b90` 抹掉行动者占位，普通目标 `0x40fa80(目标, 0x409090 射程, 0x40bab0 mode, 0)`（`0x40dbe6..0x40dbfa`），3×3 目标逐身体格 `0x40f8b0(px±32, py±32, 射程, mode, 0)`；「目标已在射程内」是**以行动者为原点**的覆盖——`0x40fa80(行动者, 射程, mode, 1)` → `0x40fb20(持有目标)`（`0x440d16..0x440d42`，另见 `0x440c4b..0x440c77`、`0x43fc8e..0x43fcc2`）。洪泛在墙边不对称，站位看得见目标不代表站位上的行动者打得到目标：`0x410a50` 走到站位后，`0x441311..0x441369` 清 `0x10000`、`0x411a30` 放回占位、再以 flag 1 建行动者覆盖测持有目标，为零 `je 0x441eb8` 结束回合、不出手，非零才 `+0x94 = 6` 写接触像素出手。重制：`AINavigationRules.weapon_terrain`（每回合一次）→ `attack_stations(…, terrain)`，`BattleLoopAI._ai_station_attack` 到站后 `AINavigationRules.target_in_range`，失败回 `move`（站位即自身格回 `wait`），`wait_reason = station_out_of_range`、`attack_station.arrival_in_range = false`。探针（504 的 036_1、003 的 028_2 换远程武器 61／32，放到 gulu／hu 周围 5 格内每个空格，每格 3 个种子）：隔墙出手——即被打者不在出手格的地形覆盖（攻击提示 `strike_range_cells` 的几何）里——平铺 8／15／21／27 次 → 地形 0 次；`run_ai_navigation_tests.gd` `terrain_range_cases` 钉住（消融到站复查、或站位退回平铺，各有 FAIL）。第一战 r1／first_control 与第 3、6、10、52 关开场都是近战或射程内无墙，裁判对照不变。

**录屏 R3-24 复核。** 021_3 在 (12,11) 打 (14,10) 的 023_2：站位 (13,10)（中心上方）、(14,11)（中心下方）曼哈顿等距，但半格偏置下 (14,11) 键值 4、(13,10) 键值 2，(14,11) 不抽硬币直接排第一——与原版 (14,11) 一致（lane AI-PRIO 起确定；R7-NPC 按无偏曼哈顿距离排序时同一注入局面 32 个种子 (13,10)×12、(14,11)×20，旧实现 (13,10)×16），见 [battle_051_ai_moves](../runtime_observations/battle_051_ai_moves/README.md)。

魔法进攻分支里「本回合无法术目标」时的 11% 支线（`0x43feba`：`rand(100) < 11` 且有站位时，以自身侧 mask 取离站位最近的可停格走过去再判射程，`0x413900`；抽取点 `0x43ff32`）已由 lane AI-PRIO 复刻（`AIDecisionRules.side_walk_roll`、`BattleLoopAI._ai_side_walk`）。选格的洪泛不是移动范围：`0x43ff68` 先调 `0x40f440(actor, 1, 0x40bab0 模式)`（预算 1，只走一步），`0x413900` 在这张图里取格，`0x440020` 的移动力洪泛只负责走过去（runtime-measured，lane AI-PRIO-2：17 关 s2 的 035_1 实测 `0x40f440(035_1, 1, 3)` → `0x413900` 取 (28,14)、站位 (30,14)、一次 rand(2)；重制此前在整个移动范围里取到站位本身再攻击，现同原版一步后待机）。**未复刻**（provisional）：原 `0x410a50` 走向自身格的返回值未执行（重制把站位即自身格当原地攻击，到站复查照做：地形下自身格可在目标覆盖里而目标不在自身覆盖里，此时结束回合）；`approach_goals`（`candidate_filters.without_approach` 回执、`no_attack` 追击的武器目标格）仍按平铺 RANGE 记录。`0x40d8b0` 逐槽换目标已由 lane AI-PRIO 复刻（`BattleLoopAI._ai_station_switch`，见上）。替换证据：对 `0x43feba` 与 `0x410a50`（自身格）的有界原指令执行。

## 复跑与验收

```sh
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate ai_navigation --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
tools/godot.sh --headless --script res://tests/run_ai_navigation_tests.gd
```

普通checker只核对保存结果；只有`--execute`重新执行原字节。渲染输入、默认战斗路线与图片分别见[可玩验收](../runtime_observations/ai_navigation/README.md)。图证不能替代原函数证据，合成HP、控制权或技能授予也不代表正式关卡新增角色能力。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/loop/BattleLoopAI.gd` rules：retained target without reachability 0x43f55f, wait entry, guard radius, fixed-point guard 0x440ef1 and return-home 0x43fbd6, lock 0x441002 over any held target, registry-order scans 0x4c34c0, pursuit walk 0x440d5c → 0x4111a0, attack station 0x40d8b0／0x413390 and the state 0xb sub 0 reposition roll over the weapon terrain, the arrival re-test 0x441311..0x441369 that ends the turn at 0x441eb8 when the station does not see the held target back, the ordinary state 0xa category 0x440041..0x440085 that rewrites +0x88 to the first registry slot from the held one with an attack station — no range／guard test — and the unconditional category draw 0x40c570 at 0x43fe0c with no category cycle

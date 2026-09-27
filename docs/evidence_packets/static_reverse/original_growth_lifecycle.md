# 生成、交锋成长与玩家学习的独立入口

> evidence: static-derived · status: live · functions: 0x40e870, 0x4348f0, 0x437080, 0x4373f0, 0x437970, 0x437a40, 0x439f80, 0x442720, 0x450840 · tools: capture_growth_lifecycle_review.gd, hsltools/data/growth_lifecycle.py, hsltools/data/growth_lifecycle_trial.py, hsltools/probes/growth_lifecycle.py, hsltools/probes/job_up_learning.py, run_growth_lifecycle_tests.gd · updated: 2026-09-25

本包来自同一已固定SHA的原`hsl01.exe`指令执行、PLAYERS／ITEM／MAGIC／SPECIAL表及调用者地址。`static-derived`回执为[original_growth_lifecycle.json](original_growth_lifecycle.json)，复跑工具为[原指令探针](../../../tools/hsltools/probes/growth_lifecycle.py)。函数目录只用于定位；本次没有提交模型推断或重新请求Jev判断。

## 原入口和验证边界

| 环节 | 原地址与字段 | 已执行范围 |
| --- | --- | --- |
| NPC交锋升级 | `0x442720`，阶段`0x4c432c=8`；`0x44299c..0x442a32`检查EXP门槛和四项容量，再调用`0x439f80(actor,5)` | 78组，六职业、两种对象kind、连续等级、低于／达到门槛、部分／全封顶；NPC与无升级分支正常返回，玩家有剩余点数的分支止于`0x442a45`、尚未创建UI |
| 玩家魔法学习 | `0x4373f0`按job和**存储等级+1**检查；`0x437080`更新`+0x174..0x188`魔法位 | 与绝技合计278组完整返回，已拥有／未拥有、临界上下、多个门槛和六个当前职业；名字字符串／表指针是夹具输入，原位操作和原字符串函数实际执行 |
| 玩家绝技学习 | `0x437a40`选职业表和阶级，`0x437970`逐行检查`+0x64..0x70`四项基础属性；`0x437080`写`+0x158..0x170` | 表记录从EXE原字节解码；一次调用只接受第一条符合条件且未拥有的能力。非空文字buffer只预览，null buffer才写位；完整返回验证 |
| 脚本全员重调入口（旧称"初始全阵容调级"） | `0x43f3a5..0x43f3fb`一般对象、`0x4438d4..0x44393c`玩家对象；同时要求全局phase位`0x4000000`和`0x4c1d48`非零——`0x4c1d48`只由opcode 73（`actAdjustAllPlayerLevel`，全库仅STORY006）置位，开战出生调级走对象初始化分支、无此条件（[触发条件](original_auto_growth.md#开战调级的触发条件)） | 16组有界caller，只有两个条件齐备才传入原`+0x1f8`高／低字参数并完整执行`0x40e870`，随后止于后续行动之前 |
| 脚本全员调级 | VM`0x450840`，opcode73；设置点`0x452408`、恢复点`0x452f1a` | 两次正常返回：首次消耗一个token、置阶段与全局latch；恢复清latch且不再次推进游标。VM本身不修改角色记录，实际调级在对象callback |

原source出生规则与配额函数沿用[SR-071完整返回证据](original_auto_growth.md)。本包追加了它们的真实交锋caller，而不是把出生附加值再次加到每次升级里。

## 三种来源不混合

一般NPC的交锋升级使用当前EXP、等级和属性容量，按职业配额分配五点，直到不能继续升级。配额不足后的原封顶退路仍沿`EntryGrowthRules.allocate`保留，不改成平均分配。该分支不调用玩家学技函数，也没有新的出生HP／MP／攻击／经验奖励／金币偏移。玩家对象kind3则进入手动分配UI；底层经验、点数和四项基础属性保持各自含义。

`0x4373f0`的门槛输入是存储等级加一。当前事务在批准一个或多个等级提升后，以将要取得的新等级检查同一门槛，把等级和新技能一起提交；提示在交锋和EXP之后显示。原手动UI对象的逐tick创建／点击时序没有整体执行，本轮不据此声称播放时钟或全部UI阶段等价。原调用者`0x437d6c`和`0x43808f/0x4380d9`分别锚定魔法消息及绝技预览／提交，NPC自动分配caller不经过这些入口。

六个live职业中：80战士、88盗贼、94兽类在所测玩家魔法分支不追加魔法；85祭司、90法师、92翼战士具有各自门槛。以当前学习表的门槛值计，祭司6可取得驅毒、法师8可取得治癒之水、翼战士8可取得毒术。职业号和元素／bit均使用原表，不用角色名称猜测。绝技另外检查阶级与四项属性，不由等级或装备加成替代；例如战士首条表记录要求基础`26/20/20/24`。完整表、原字节及其SHA均入包。

## 上位职业的学习表（static-derived）

两处学习函数都以角色记录`+0x18`的**当前**职业号分派，转职（`0x4348f0`）只改写职业号并保留已学位，因此转职后的成员从下一次升级／确认属性起按上位表学习。分派结构与各上位职业表由[原生探针](../../../tools/hsltools/probes/job_up_learning.py)对`0x4373f0`／`0x437a40`以基础职业相同的合成夹具完整执行714组（门槛上下、已拥有、预览／提交、四属性各减一），回执为[original_job_up_learning.json](original_job_up_learning.json)；表数据经`hsltools/data/growth_lifecycle.py`合并到`growth_lifecycle.json`，现覆盖80–99共二十个职业。

| 职业 | 魔法（`0x4373f0`：`0x437950`索引字节→`0x437920`case；上位case先检查自身门槛，再落入基础职业case） | 绝技（`0x437a40`：`0x437bd4`跳表，表＝基础职业表，阶级更高） |
| --- | --- | --- |
| 81 劍豪 | 24 治癒之水、31 生命之水、34 滅 | 战士表`0x4782b0` tier 2（慌雨斬／精神統一／皇龍閃可学） |
| 82 劍王 | 45 女神之淚，再落入81 | 战士表 tier 3（再加孤月斬／闇瑩蝶舞／無想冥殺） |
| 84 弓聖 | 无 | 弓手表`0x478378` tier 2 |
| 86 神官長 | 26 赤炎波動、28 地靈聖護、30 大地之癒、32 女神之淚，再落入85祭司全部 | 祭司表`0x478314` tier 2 |
| 87 賢者 | 48 魔障壁、48 大地之惠、56 極，再落入86 | 祭司表 tier 3 |
| 89 刺客 | 无 | 盗贼表`0x4783c0` tier 2 |
| 91 jobElfMan | 25 魔燒焚燼／逆風裂空、27 烈蝕水彈／生命之水、30 天地鳴動、39 怒炎魔獄燋、40 極零裂凍破，再落入90法师全部 | 无表（与90／96同为默认返回） |
| 97 邪獸 | 无 | 自有两行表`0x47848c` tier 2：神罰（1/1/1/1）、神怒（80/40/28/45） |
| 99 DarkAngel | 26 地靈縛、27 封魔滅殺、28 天地鳴動、30 咒靈縛剎、37 怒濤地裂崩、42 死骸腐靈獄，再落入98魔剑士全部 | 魔剑士表`0x4784ac` tier 2 |

93／95的tier 2表和98已在[主线角色来源](original_campaign_actors.md)中；83／88／94–97不学魔法。重制侧`LearningRules.acquire`本就读成员当前`job_code`选表，转职前学到的记录保留其取得时职业并按`job_up_history`校验，未改代码；定向回归在`tests/run_growth_lifecycle_tests.gd`的`job_up_learning`（011神官長实际施法跨25→26学赤炎波動、同级祭司不学；010劍豪在job80已学天雷猛襲劍后实际分配一点学tier 2慌雨斬、未转职劍士不学）。未证明：原升级UI对上位表的提示时序，以及转职当刻不升级时是否有额外补学入口（本包只在升级／分配时调用学习函数，与原caller `0x437d6c`／`0x43808f`一致）。

声明过的初始技能、后来取得的技能位、装备能力分别保存。重复学习不增加记录或重复提示；缺少完整玩法实现的原技能仍记录为已取得，明确显示“尚未可用”，菜单隐藏，不借用另一技能。升级不为NPC套用玩家学习表，临时由AI操作的已登记玩家仍保留其既定成长身份。

## 随机流

原经验自动分配和这两类玩家学技均不抽随机数；78+278组完整轨迹确认随机全局字不变。入场调级与出生加成由`0x40e870`调用原随机函数`0x458c80`，抽的是全局流（状态`0x4795d4/0x4795d8`，[敌人回合裁判](original_enemy_turn.md)模拟器实测；此前误写成伤害流的`0x4c3040/0x4c3044`）。

**2026-09-25 lane RNG-A 起，重制也改抽全局流**：独立的 Park-Miller `initialization_rng` 退役，出生调级、新援、脚本建角都从 loop 的`global_rng`（`GlobalRandomStream`，与原版同一生成器、`rand(n)`与每次调用的抽取次数）抽。全局流照原版不入存档、不随战役承接：进程首次使用时按时钟播种（无窗口运行取`HSL_RNG_SEED`），每场战斗接着进程当前的字往下抽，读档保留当时的活字。所以下面几条旧合同随之改变：跨战不再传游标，新场景重开从活的全局流重新出生（不再复用入场游标），F9 读档恢复已出生的actor与receipt但不回拨全局流。自动加点、手动点数、学技、换装、第二行动仍不抽随机数。

原全局跨子系统精确抽样顺序仍未复现：AI 决策链、出手动画延迟等其它全局抽取还不是原版的次数（见 [original_enemy_turn.md](original_enemy_turn.md) 与 lane RNG-A 的对拍），所以同一时钟种子下的出生等级不等于原版那一局。

## Live合同与可玩入口

`BattleSceneRuntime`在campaign carry后、生成可交互角色前调用唯一PlayLoop的`initialize_roster_growth`。先处理登记玩家：新玩家按基础属性推等级并刷新一次，已承接玩家保持取得的等级／点数／技能；再按场景阵容顺序调用NPC出生提案。这个可复跑调度顺序是重制选择，未声称与原对象表逐帧顺序相同。显式原始模板单测可在此前检查source值；正式运行不会绕过初始化。

`learned_skills`存精确ID、名称、职业、取得等级、取得时四项属性和触发类型。初始化声明没有被重写；临时状态、永久加成和装备字段不写进该记录。保存验证绑定角色与职业、原规则、取得条件、重复ID和当前属性／等级单调性。`CampaignCarryRules`和正式campaign policy携带取得记录（不再携带生成流游标：全局流不随承接，旧carry里的`initialization_rng`读入时忽略）；旧配置签名不同的战斗快照明确拒绝，不以重新生成角色伪装迁移。单战快照升到 v6（出生收据记全局流的两个字），v5 按名拒绝，不迁移。

独立队伍（正式第三战）不把Leonard的人物／金币套给緹娜；战斗侧`GrowthCampaignProgress`薄子类在父控制器完成目的地／world／story处理后，只交接伤害流，原队伍记录继续原样传递。父`CampaignProgress`与world/town文件不修改。lane RNG-A 前这里只传`initialization_rng`游标，真实第三战红例证明过的“入场重置”和“出场丢失推进”两项，随全局流不入承接一起失去对象；`run_growth_lifecycle_tests`现在钉住：无串队、开场出生从进程全局流起抽、出场承接不带全局流、重开在活的全局流上重新出生。

战役JSON会把取得记录中的职业／等级／属性读取为浮点数；完整来源和整数域验证通过之后，共享刷新才把这些字段规范为整数，保持与实际取得回执精确一致。5.5等级等非法值在规范化前拒绝，不以四舍五入掩盖未满足的条件。单战快照使用带校验和的Variant格式，不重放这次学习。该问题由真实恢复画面路线暴露，并另有JSON往返红绿回归。

NPC升级、玩家升级和新能力都由原交锋事务提交；`BattleAftermath`只显示已提交消息，并继续阻塞下一行动／结果页。手动分配确认后才取得绝技，取消或空分配不会学技。最后一次行动的状态／资源尾部、`double_attack`每串、`action_twice`独立行动沿既有事务，不因学技增加一次付款或尾部。

开发入口：`game/battle/development/GrowthLifecycleTrial.tscn`。这是源051地图上的明示成长演练，设置等级、近门槛经验、耐久和装备，原公式与技能资格照常执行；不修改正式初始法术／装备。数据生成器：[hsltools/data/growth_lifecycle_trial.py](../../../tools/hsltools/data/growth_lifecycle_trial.py)。

## 验证与后续边界

定向入口：`tools/godot.sh --headless --script res://tests/run_growth_lifecycle_tests.gd`。实际输入入口：`tools/godot.sh --screen 1 --script res://tests/capture_growth_lifecycle_review.gd`。完整非GUI门禁仍为`tools/verify.sh`；真实最终进程、场景回执和截图在[成长实玩记录](../runtime_observations/growth_lifecycle/README.md)中归档。

转职事务本身见[原城镇转职](original_town_job_up.md)；未注册技能的具体效果、整个原高位调度器及全局随机流身份不由本包证明。`actAdjustAllPlayerLevel`的VM／callback条件已有原指令回执，但没有把宏观全局phase模拟成另一个可变战斗所有者，也没有为“重复触发”重新应用既存出生加成。下一步优先把学习后仍不可用、且数值／资源有直接原证据的早期水／地魔法接完整；它们使用现有资格与保存记录，不再另建学技表。

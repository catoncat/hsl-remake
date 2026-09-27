# 初始阵容、自动成长与学习：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_growth_lifecycle_review.gd, run_growth_lifecycle_tests.gd · updated: 2026-09-18

这是Godot重制版的运行证据，不是原引擎录像。原指令的完整返回／有界前段、源表和未确认部分独立放在[成长研究](../../static_reverse/original_growth_lifecycle.md)。[机器回执](receipt.json)逐路线保留起止人物、学习记录、真实交锋序号、AI动作、资源、声音、存档次数和原始日志SHA；不把失败进程中已完成的路线写成整进程PASS。

## 玩家入口

```sh
tools/godot.sh --headless --import
tools/godot.sh --screen 1 res://game/battle/development/GrowthLifecycleTrial.tscn
```

本次机器内建屏为1；换机器先确认屏幕，不硬编码占用外接显示器。演练使用源051地图、002祭司与001剑士身份、源技能／装备。初始毒、近升级经验、耐久、速度、位置及库存是清楚标注的开发配置，既不改正式第一战，也不等价于原STORY初始数值。

操作：緹娜先两次待机，同伴待机受到毒伤；再用治癒之水治疗同伴，最终EXP令緹娜升到六级并显示新学驅毒。白光之翼的第二次独立行动立即可用驅毒。可用F5／F9比较取得前后；剑士达到升级条件后确认基础力量达到26，才会记录天雷猛襲劍。尚未接入效果的源能力明确显示“尚未可用”，不会混入可执行菜单或AI假施放。

![真实升级后才显示取得](public-learn-2.png)

![新取得驱毒的当前目标](public-target-magicCode05.png)

![确认基础属性后记录绝技，长名称在左栏换行](special-learn-special.png)

## 实际路线及覆盖

| 路线 | 实际输入与观察 | 边界 |
| --- | --- | --- |
| public／initial | 公开演练无运行后改值的待机→治疗→升级→驱毒；正式第二战product opening后状态检查和F5/F9 | public是配置化演练；initial使用第二战正式开场，不冒称全部关卡 |
| initial_dev | 第二战显式开发快进后真实点击移动、显示范围、取消及F5/F9，检查NPC已提交成长不重跑 | 仅此命名开发入口跳过前置演出；正式开场继续完整播放 |
| unlock／below／multilevel | 真实治疗跨或未跨六级、单次击杀多级，已声明治疗不重复计作新学；Water01／Water05及九级Earth06各按实际等级判定 | multilevel明确高kill_exp／1HP靶与保留另一敌人；不固定真实随机经验的结果 |
| special／npc | 001剑士确认四基础属性后一次学习；一般NPC在双击／反击的实际最终EXP后自动按职业配额成长 | NPC临时可控不变玩家学习身份；两机制不混为一次出生调级 |
| ai_learn | 暂交AI的登记玩家先普攻取得六级，再于独立第二行动重新选择刚学的驅毒 | 不强制第一行动治疗；按不可变sequence去重跨轮保留回执 |
| mobile／limited／paralyzed | 新学后换移动施法装备并移动施放；MP不足保留学技但拒绝施法、使用现有MP药；麻痺入口跳过、期满再治疗与学习 | 原技能费用、法术／物品条件和最后行动尾部不放宽 |
| permanent | 实际使用背包中的永久道具253，F5/F9后治疗升级和确认分配，再换装备，核对同一永久取得值 | 不在运行后直接写永久字段；其余九类原数值／抗性边界复用已闭合永久道具切片与完整门禁 |
| carry | 胜利撤离后写隔离战役JSON，实际点击续战创建新场景；学习／永久层与生成游标延续，随后F5/F9 | 同一进程创建新场景，未把它称为两个独立进程实测 |
| victory／defeat／escape | 真实致命攻击／反击、移动撤离，检查结果冻结、F5/F9及点击重开 | 终态后不补成长／学习，重开回未取得的演练入口 |

![多级结算仍只在最终经验之后成长](multilevel-experience-1.png)

![AI第一行动后取得技能](ai_learn-learn-2.png)

![移动施法装备读取当前派生值](mobile-equipment-232.png)

![学会不等于资源足够](limited-no-mp.png)

![麻痺入口不偷发成长或第二行动](paralyzed-paralysis.png)

## 实测发现并修复的问题

真实第三战运行回归先证明：separate_party入口跳过carry会重置生成流，出口整份传回旧carry又丢弃本战推进。薄`GrowthCampaignProgress`不修改presentation父控制器，接收时仅过滤人物／钱包，出场只更新唯一PlayLoop的游标；正式第三战和重开红绿测试同时检查原队伍记录不变。`separate-party-red/green.json`记录退出1→0；早期红例的测试清理诊断原样保留，green无资源泄漏诊断。

真实JSON续战另暴露学习记录的整数／浮点表示不一致。添加完整JSON往返红例后，在共享刷新完整检查通过之后规范职业、取得等级及四项属性；非法5.5级仍拒绝，绝不通过取整伪造条件。`carry-json-red/green.json`记录失败→1381项通过，纯回归不是渲染替代。

公开演练原先错用024重装兵作为001剑士成长配置，且只改grid_coord而没有改运行入口真正读取的coord；最终场景已用真实源身份与同一位置。长绝技取得文字加原左栏换行。其余旧失败分别是：把初始治疗算入新技能数量、强制AI先治疗、同一回执随轮次重复计数；均修正明确夹具／验收器，没有降低规则、付款或原条件。

首轮完整门禁在482项Python、源检查／冷导入后暴露旧交接夹具：直接覆盖出生后live防御／速度被来源一致性校验拒绝；其夹具改为source层调整并统一刷新。旧断言“NPC永不成长”和“跨战随机种子重置”由本批明确的新行为替代，纯source模板仍保持不能收EXP。普通攻击／反击现在可能有两条实际EXP回执，呈现测试逐条等待，期间仍禁止输入／队列推进。第二战原有测试（未修改）又证明显式开发快进只跳过规则前缀却留下最后一条EXP演出；Runtime现复用既有AI快进的视觉收口，不改成长结果，也不跳过正式开场。完整首轮失败记录在`ignored/growth-lifecycle/verify-action-handoff-red.json`，其后定向修复不冒称全仓门禁通过。

![隔离进度文件经真实按钮续战](carry-campaign-resume.png)

![正式第二战开场和前置行动后首次操作](initial-ready-11.png)

![开发快进后移动按钮与范围确实可用](initial_dev-move-range.png)

![歼灭结果](victory-result.png)

![失败结果](defeat-result.png)

![撤离结果](escape-result.png)

## 回执口径与复跑

本包汇总17条**已完成命名路线**，原进程状态独立保留：mobile／limited／paralyzed／npc的四路线进程、最终public／special进程、permanent和initial_dev单路线进程完整PASS；unlock／below、multilevel、ai_learn、carry／三个终态／initial取自后来其他路线失败之前已完成的记录。每次失败的原因、退出值和哈希在receipt中，不将前缀成功说成全进程通过；后续修正以针对性重跑闭合，不为追回日志重跑全部旧路线。三个终态的F5/F9位于路线计数快照之后、completed记录追加之前，driver有明确断言，因此回执保留这一计数边界而不改写原数据。

```sh
tools/godot.sh --headless --script res://tests/run_growth_lifecycle_tests.gd
tools/godot.sh --screen 1 --script res://tests/capture_growth_lifecycle_review.gd -- public special
tools/godot.sh --screen 1 --script res://tests/capture_growth_lifecycle_review.gd -- ai_learn carry victory defeat escape initial
tools/verify.sh
```

真实窗口640×480、time_scale=1，截图取游戏视口而非全桌面，音频记录实际播放的源stream。未证明原墙钟／混色／完整调度器，生成流与其他战斗随机流尚未合并为原全局序列；首次登记顺序、跨战补满和独立队伍延续为明示重制合同。旧配置快照明确拒绝，不静默重新成长。最后完整门禁的进程退出与稳定差异哈希记录在本地提交说明及`ignored/growth-lifecycle/verify-close.json`，不由上述定向或截图代替。

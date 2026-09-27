# AI续追、等待与空格选点实玩

> evidence: runtime-measured · status: live · tools: capture_ai_navigation_review.gd, run_first_battle_playthrough.gd · updated: 2026-09-17

2026-09-17，`6cce138`之后的导航批次。所有图来自Godot正式Runtime与同一PlayLoop的真实控件输入，正常时钟。原规则来源和不支持的等价声明见[导航原证据](../../static_reverse/original_ai_navigation.md)及[四邻／邻接代价](../../static_reverse/original_movement.md)。[精简回执](receipt.json)保留12条导航、3条移动施援复验、各进程设置、两条默认战斗、声音采样与图片哈希。

## 已走通的玩法

| 路线 | 实际可见结果 |
| --- | --- |
| detour | 四个真实回合保持目标，绕开原WRD障碍后移动攻击；首回合因同伴邻接代价只到`(7,9)`，随后经过`(8,8)→(9,9)→(10,9)`，每次累计成本不超过两点 |
| unreachable | 近目标在另一个原WRD连通区域，AI改追可达的远目标；没有修改地形制造墙 |
| target_death | 已锁定的1HP目标被原普通攻击击败，完整遗言／淡出后，下一回合清除旧目标并选择新目标 |
| wait／no_action | 原初始等待只递减一次；完全没有合法动作时也显示有限“待機”，再交接后继，不制造伤害或额外资源消耗 |
| empty_mp／silenced | 缺MP或禁魔时沿合法路径继续物理接近，不支付魔法费用 |
| empty_center／cure_center | 四个真实角色围绕空格`(10,9)`，AI选择空地为酸蝕幻霧／驱毒中心，一次MP、四份各自的状态结果 |
| player_center | 真实魔法列表→空地悬停显示4目标→取消→再次选择→确认，角色、范围、MP和后继与AI共享事务 |
| moving_cast | 首行动用四点预算接近，不提前扣MP；下一回合移动到合法站位，演员抵达且路径标记消失后开始风火前摇，实际施法音、一次命中和数值反馈后交接 |
| defeat | 真实AI攻击击败1HP主角，命中／结束对白后显示败北并播放Game Over；目标引用清空、终态不继续行动，真实鼠标重开恢复新战斗 |

这些是明确设置的导航夹具：保留正式WRD／素材，修改位置、HP、速度、控制资格、部分源AI倾向；范围毒／驱毒按测试需要授予现有原技能。移动后施法有四格移动力，其余测试AI两格；致死路径的1HP与命中积累明确记录。没有替换RNG、覆盖伤害或结局，也没有加速时钟。初始哨兵只用于真实Wait触发AI；失败后修正了早期哨兵阵营夹具，不借此调整产品敌人行为。

风火有自己的前摇与效果声音，不发普通挥击的release信号；最终验收观察实际cast_started、混音已推进的`cast_magic.wav`和一次impact。状态与支援clip的release/impact单独计数。移动治疗、驱毒和用药另以既有真实输入夹具复验三条，预算、到达、效果、支援经验和后继均通过。不能把“听到了声音”扩大为所有原作音效时钟一致。

加入原邻接代价后，旧夹具先后暴露固定“两格／三回合”和“首回合必施法”的断言不再成立。修正为真实累计代价并继续实际回合直到攻击／施法。最终前十条来自一个随后在第十一条失败的进程；这十条无各自断言失败，但没有把该进程冒称PASS。最终移动施法／败北两条和施援三条各自进程均退出0，过程边界保存在回执。

## 默认第一战

`run_first_battle_playthrough.gd`没有覆盖战斗数值或角色授予，使用正常开场、控件和时钟。最终hold在第8回合、193.329秒撤离成功，advance在第5回合、162.508秒主角败北；两条均真实鼠标重开成功。advance自然攻击、积气并升到2级分配五点；本次未在败北前施放氣刃斬。此前未加入邻接代价的清场路线不作为这版默认结局。两次路线不等于难度统计或所有自主打法均衡。

## 人工查看的图

[绕路路径](detour-path.png)、[不可达改选](unreachable-path.png)、[旧目标死亡后新路径](target_death-path.png)、[可见待机](wait-wait.png)、[四目标毒雾](empty_center-impact.png)、[四目标驱毒](cure_center-impact.png)、[玩家空格预览](player_center-preview.png)、[抵达后施法](moving_cast-cast-lead.png)、[败北](defeat-result.png)、[默认撤离](default-escape.png)、[默认败北](default-defeat.png)。

路径与落点细线、待机字样、强光上方逐目标反馈及最后结果页面已逐图查看。图片展示当前重制编排，原字体、完整移动flags、双中心随机流和精确时钟仍按原证据包保留边界。

## 复跑

先查询内建屏索引，再替换下面示例中的1；一次只运行一个可见窗口。

```sh
tools/play.sh --screen 1 --script res://tests/capture_ai_navigation_review.gd
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- hold
tools/play.sh --screen 1 --script res://tests/run_first_battle_playthrough.gd -- advance
tools/verify.sh
```

12条夹具也可通过参数选择，名称见表；新导航套件、原结果checker、既有全部AI、技能事务、场景、领取／保存、第二场和主入口均归完整门禁。最终退出码与提交身份记录在本批提交说明；不会只凭PASS字样忽略脚本异常或泄漏。

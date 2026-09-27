# 盗贼／翼战士、末击削魔与跨战：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_mobile_jobs_review.gd, run_mobile_jobs_tests.gd · updated: 2026-09-18

SR-067基线`d1925e3`。原指令证据见[独立职业与削魔来源](../../static_reverse/original_mobile_jobs.md)，本页只记录Godot实际运行。二十条具名路线使用原地图／动作／肖像／声音、真实按钮及鼠标键盘事件，640×480、正常时钟、内建屏1。完整机读输入、结果、逐击收据、道具、AI源配置、存档次数与逐进程退出范围见[receipt.json](receipt.json)。

## 走通的链路

| 路线 | 实际操作与结果 |
| --- | --- |
| manual、single、double、counter | 公开演练的006先行动，飞行移动后仍须实际装备冥晦之輪才能施放自己的風刃；004查看源初值并装备宿魔刀。普通单击／双击／双击反击按各自末击削MP，逐个影响帧核对显示值，卸装和第二行动保存不重发 |
| miss、low_mp、zero_mp、late_kill | 真实落空不触发武器尾部；目标MP1／0夹到0，实际第二击击杀按剩余HP算贡献，死亡／EXP／掉落和后继不重复 |
| growth、wing_growth、wing_move | 实际永久药→击杀最终EXP→五点成长→换装→保存；006按当前源范围选合法位置再施風刃。取消移动恢复施法资格，第二行动卸掉最后权限后立即失去移动施法，仍能移动后用MP药 |
| support、mixed、paralysis | 004移动给002加持、取得永久值后由002实际治疗；毒／禁魔／防御增益与削魔共存；麻痺入口跳过一次，不额外触发白光之翼，禁魔解除后才施放源風刃 |
| ai_drain、ai_wing | 026被削到MP0后使用当前资源重新选择合法动作；006显式演练AI先施放自己拥有的風刃，第二行动因MP0转为普通动作，没有重放旧法术意图 |
| victory、defeat、escape、carry | 清敌／被反击击败／撤离均实际保存与点击重开；隔离战役JSON经真实“继续”控件载入新的公开演练，保留永久值和当前宿魔刀，新战清空临时状态与旧收据；自然交锋结束后再次点击重开仍保留该战进入值 |

`manual`本身是公开开发场景，库存为明确演练供应；其余路线在输入开始前设置有限库存、耐久、速度、命中补偿、初始MP／状态和部分概率／双击条件，原输入及源记录都保留。反击MP位是能力夹具，不能写成026合法持有宿魔刀；006的AI策略也明确为演练配置，不能把它没有声明的策略冒充原表。004／006都沿自己的职业／装备／技能来源，未替换战斗RNG或提交结果。

## 图证与可见反馈

[源翼战士初值](manual-002-stats-wing.png)、[源盗贼初值](manual-012-stats-thief.png)、[飞行路径与移动后施法限制](manual-004-move-preview.png)、[宿魔刀装卸说明](manual-014-equipment-108.png)展示玩家实际看到的来源与资格。

[普通第二击削魔](double-010-impact-2-attack.png)与[反击第二击削魔](counter-010-impact-2-counter.png)仅在该击影响帧更新MP；[第二击击杀](late_kill-010-impact-2-attack.png)使用最后剩余HP。[翼战士成长](wing_growth-012-growth.png)保留新职业派生和永久来源；[禁魔](paralysis-007-silence.png)不被第二行动或装备绕过。[AI風刃](ai_wing-003-cast-1-wind-true.png)与[下一次普通行动](ai_wing-006-cast-2-ordinary-true.png)分别记录资源耗尽前后。

[清敌结果](victory-010-result.png)、[败北结果](defeat-011-result.png)、撤离结果及其真实重开位于机读回执；[战役继续](carry-012-campaign-resume.png)、[新战自然终态](carry-019-carried-terminal.png)、[重开后恢复](carry-021-restored-3.png)覆盖另一场战斗的来源重建。十七张整理截图有对应哈希，已按原尺寸检查；构图缩放／演出时长属于重制取值，不构成原逐帧等价声明。

## 发现、修正与有效范围

真实回归：新的AI身份生成脚本已经更正，但生成文件仍旧，导致准备新角色时拒绝；重建后定向通过。新角色004的死亡消息记录遗漏，败北地图收尾断言；把004／006／028／036统一加入原消息编译并新增来源检查，修正后的败北／撤离与跨战终态已完成。产品保留无源遗言时的明确空记录，不编造对白。

夹具修正另记：公开场景真实行动顺序是速度43的006先于速度25的004；命中有原10%下限，不能把一个未读取的字段当成保证落空；次击击杀HP、移动后法术射程与占格须符合当前源规则；跨战自然等待仍允许反击，可能清敌胜利，不能强写成败北。库存／装备JSON比较按验证过的整数身份及槽顺序，而不要求JSON浮点与原Variant整数类型相同。上述问题没有通过修改已发生的战斗结果绕过。

八份采纳回执合计二十条唯一路线。早期进程分别在后续夹具失败或死亡资源错误处退出1／143，机读回执只采纳其此前具名成功路线；不得称这些进程整体通过。公开／单击、最后跨战和正向MP反击的对应进程退出0。旧反击曾覆盖不足三点伤害的零MP损失，后来补拍正向损失并以新回执为准，不重复计路线。

完整非GUI门禁的最终退出和日志位置写入本批提交说明；单战／跨战定向、原数据／回执检查和所有既有场景仍由同一门禁运行。不会把截图或一行PASS替代最终进程结果。

```sh
tools/godot.sh --headless --script res://tests/run_mobile_jobs_tests.gd
tools/godot.sh --screen 1 --script res://tests/capture_mobile_jobs_review.gd
tools/godot.sh --screen 1 res://game/battle/development/MobileJobsTrial.tscn
tools/verify.sh
```

所有演练只写`ignored/mobile-jobs-review`的单战／战役文件，不覆盖用户的继续游戏记录。原完整初始化／动态调级／学技、全局随机流与其它职业仍见源合同的限制。

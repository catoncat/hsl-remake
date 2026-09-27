# 永久能力与原始抗性：实际操作验收

> evidence: runtime-measured · status: live · tools: capture_permanent_carry_review.gd, capture_permanent_items_review.gd, run_permanent_carry_tests.gd, run_permanent_items_tests.gd · updated: 2026-09-18

SR-066在`eedf752`之后的改动使用公开`PermanentItemsTrial.tscn`及相同正式Runtime／PlayLoop。所有后续操作由实际鼠标／键盘控件完成，正常时钟、640×480、已确认的内建屏1；检查点隔离在`ignored/permanent-items-review`，未写共用战役续战文件。原指令证据见[永久来源与两处上限](../../static_reverse/original_permanent_items.md)，机器回执为[receipt.json](receipt.json)。

## 已走通的路线

| 路线 | 实际结果 |
| --- | --- |
| manual、repeat | 公开002祭司／024同伴库存可实际取得并使用；预览取消不消费，连续两次使用分别获得原抽样增量、同一最终行动尾部，F5/F9不重复取得 |
| magic、melee | 永久魔击进入移动后的風刃，MP耗尽仍禁止治疗；永久防御进入主攻／反击各两击、暴击和共同气力／EXP结算 |
| growth、movement | 永久攻击后击杀升级及真实加点，换法杖／移动饰品后保留收益；死亡格释放后移动治疗；先移动为同伴用永久道具，再在独立第二行动原地施援 |
| resistance、cap、details | 装备使显示抗性达到80仍可取得有用的原始增量，卸装显示76；原始79→80后拒绝下一次无效使用；状态页提示区分来源与两处上限 |
| mixed、paralysis | 毒／禁魔／攻防临时层共存时仍可用物品；敌方退魔移除临时两项、永久值与异常保留，破魔清禁魔；麻痺跳过时不偷消费，下一合法行动可在禁魔下取得 |
| ai、speed | 友军AI收到永久攻击后用现属性重新决策，不凭空消耗自己的稀有库存；永久速度不重排已排好的本轮，下一轮真实队列重建使用新速度 |
| victory、defeat、escape | 第一次取得、保存恢复后第二次分别清敌、被反击击倒或撤离；三终态都拒绝继续物品／AI／尾部事务，结果页保存恢复与真实按钮重开成立 |

四次完整进程分别完成4、5、6、1条路线，均取得退出0，日志无Godot诊断。哈希、逐进程范围、实际使用收据、初始／最终单位、观察到的声音和保存次数分别记录。完整非GUI门禁的最终退出码以本批提交正文及真实日志为准；这些窗口回执不代替仓库门禁。

## 跨战斗与跨进程补充

另有两个独立进程的[跨战回执](carry_receipt.json)，均退出0且无Godot诊断。第一条在声明的第一战第6回合夹具中实际使用力之源，F5/F9后利用白光之翼第二行动走到撤离格，待机完成撤离并点击「下一戰」。九类永久取得值在第二战初始化时原样进入共同派生刷新，不携带临时状态或上一战物品序列。第二条在新进程读取该战役记录，点击原生「繼續」对话框，完整播放第二战开场，再查看状态、F5/F9，实际待机让敌方行动至败北后点击结果页重开；进入值保持不变。

战役文件被验收脚本重定向到`ignored/permanent-carry-review/campaign.json`，所用`prepare_handoff`、`save_progress`、`load_progress`、`take_handoff`、应用与场景重载均为产品入口；继续对话框接收这份隔离记录。没有覆盖用户共用战役文件。九项既有+1为明确初态，新+2攻击由本次实际物品抽样取得；不把夹具初态当作自然九件取得路线。38项跨战定向检查另外覆盖九件实际物品提交、JSON数值校验、非法小数／超过原始80拒绝、独立队伍隔离、升级／卸装及新战役归零。

补图：[实际取得](carry-prepare-item-1.png)、[撤离后下一战](carry-prepare-next-battle.png)、[第二战开场](carry-prepare-second-opening.png)、[新进程继续](carry-resume-resume-prompt.png)、[承接后的属性与永久摘要](carry-resume-stats-leonard.png)、[实际败北](carry-resume-defeat-before-retry.png)、[重开进入状态](carry-resume-retry-entry.png)。图证按原尺寸检查；七张哈希与两次进程的准确范围在补充回执中，原16条单战回执不追溯改称跨战测试。

末尾图审补充了常驻永久收益摘要，`details`再以九项已有收益的明确初态和一次实际使用补拍，确认长摘要截在属性栏内、完整悬停内容可读且不压住返回／保存控件。其它15条先前有效数值／事务回执不因纯显示补充而重跑；旧状态页图片保留当时的准确界面，完整门禁覆盖最终合并改动。

## 图证

[永久攻击取得](repeat-item-1.png)与[同伴永久水抗性](manual-item-2.png)显示实际增量；[卸装后的抗性](resistance-stats-tina.png)、[永久值说明](details-permanent-detail.png)、[原始与最终抗性说明](details-resistance-detail.png)区分来源。[击杀后的升级](growth-growth.png)、[换装移动后治疗](growth-cast-2-heal-true.png)、[退魔与解除禁魔后保留永久层／中毒](mixed-stats-tina.png)、[麻痺入口](paralysis-skip.png)和[同伴速度取得](speed-item-1.png)覆盖玩法连接。

三种结局：[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)。图片按原始尺寸人工检查，文件哈希见回执；动画时钟／绿色取得文字为现行重制表现合同，不升级为原版逐帧等价。

## 失败修正与边界

首次公开路线发现生成器把同伴永久道具写到023，但实际继承场景是024，导致部分物品在可玩场景中取不到；进程退出1且未收录为有效路线。生成器现按场景真实`companion.actor_id`写库存，Python同时检查可控角色的九类物品覆盖，修正后的公开路线独立退出0。

除manual外，其余路线是明确设置的耐久／EXP99、目标HP1、阶段／状态、源能力／AI概率及之前取得的临界抗性；所有设置集中在启动前，初态保留于回执，之后不改战斗结果或RNG。没有向正式初始库存赠送九种物品，不声称自然取得路线或稀有道具主动AI。跨战范围由上述独立补充覆盖；暂存于自己的`ignored`检查点不代表原作存档兼容。

跨战补拍的早期失败均未列为通过：两人夹具被报信撤走唯一敌人后正确提前清敌；继承祭司移动助手错误等待緹娜；新进程已走通继续／查看／读档后，脚本在非终态直接请求重开而被产品正确拒绝。修正夹具与助手后，最终路线实际走到败北并点击重开；独立日志保留失败退出1，最后两条成功进程退出0。JSON浮点数字只在完整非负整数／来源上限校验通过后规范为运行时整数，不通过强制转换吞掉非法输入。

```sh
tools/godot.sh --screen 1 --script res://tests/capture_permanent_items_review.gd
tools/godot.sh --headless --script res://tests/run_permanent_items_tests.gd
tools/godot.sh --headless --script res://tests/run_permanent_carry_tests.gd
tools/godot.sh --screen 1 --script res://tests/capture_permanent_carry_review.gd -- carry-prepare
tools/godot.sh --screen 1 --script res://tests/capture_permanent_carry_review.gd -- carry-resume
tools/verify.sh
```

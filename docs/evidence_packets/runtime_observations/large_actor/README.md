# 大型角色：实际输入、空间与战斗验收

> evidence: runtime-measured · status: live · tools: capture_large_actor_review.gd, run_large_actor_tests.gd · updated: 2026-09-18

基线main@07ae25f的SR-060实现；机器入口为[receipt.json](receipt.json)，原规则另见[原指令证据](../../static_reverse/original_large_actor.md)。十三条路线使用真实Godot鼠标／键盘控件、正常时钟、640×480内建屏窗口，沿同一PlayLoop与原051地图运行。角色控制、库存、技能、HP／等级／概率及遭遇位置明确为夹具；没有覆盖RNG、凭截图写回战斗状态，也没有把039加入正式第一／第二战编队。

## 走通的链路

| 路线 | 实际输入及结果 |
| --- | --- |
| trial | 打开独立开发场景，通过非当前角色身体边缘检查海輝魔状态；源“獸族／觸手”、真实空爪图与单一actor保持；F5/F9恢复 |
| movement | 两个移动饰品按当前槽叠加；整块受阻拒绝、沿可通3×3走廊绕路，保存后取消恢复全部原占格，再移动攻击 |
| edge_series | 小角色从身体边缘攻击中心不在射程的大角色，四次普通／反击impact；第一次行动不扣毒，第二行动末一次收尾与交接 |
| giant_combat | 大角色第一击杀死大目标，截断第二击、九格全部释放、一次奖励／EXP并实际加点；保存第二行动，再移动攻击另一个身体边缘 |
| empty_area | 移动后的法师对真实空格施放地靈縛，同时命中一个大角色与一个小角色；两人各一次效果／贡献、只付款一次 |
| support | 大角色移动后治疗另一大型友军，再于第二行动移动至新位置范围驱毒；按两人身份去重，保留麻痺／禁魔，保存恢复不再结算 |
| cure_item | 移动后因缺MP／禁魔禁用法术，仍可在身体边缘通过物品解除友军麻痺；一次扣物、一次交接 |
| skip_resume | 读取有一拍剩余麻痺的大角色，跳过与毒伤／回魔／到期各一次，无额外行动；重读同一旧存档复现相同状态，再正常进入后续行动 |
| ai_resource | AI第一行动施法后MP耗尽，第二行动重新采用普通攻击；麻痺目标不反击，没有复用旧技能付款或重复范围效果 |
| ai_retarget | AI首击击杀当前大目标，第二行动以释放后的空间和另一候选重新移动／攻击；逐击视听与占格一致 |
| victory／defeat／escape | 大角色清敌、致命反击与Leonard移动撤离三种终态；结果前完整演出，结果后冻结，F5/F9及实际按钮重开 |

定向回归另覆盖原56份flood逐格费用、飞行仅经过不可停、变化后的目标／路径／状态／资源／装备资格零RNG拒绝、坏存档身体和重叠占格拒绝。它们与上述实际控件路线分开，不把定向检查数量当作自然通关证明。

## 关键画面

[源039状态](trial-source039-status.png)、[整块受阻](movement-whole-body-blocked.png)、[完整路径与落点](movement-range.png)、[边缘反击第二击](edge_series-impact-0-4.png)和[实际成长](giant_combat-growth-0.png)连接角色、空间和战斗。

[空格中心／两个目标](empty_area-cast-center-0.png)与[各自一次麻痺](empty_area-impact-0-1.png)、[边缘治疗预览](support-cast-center-0.png)、[道具解围](cure_item-item-effect.png)显示范围和真实接收者分离；[跳过](skip_resume-entry-2-0.png)与[尾部到期](skip_resume-tail-2-2.png)保留行动次序。[AI换目标后的第二击](ai_retarget-impact-0-3.png)使用新对象的实际HP。

[清敌结果](victory-result.png)、[败北结果](defeat-result.png)、[撤离结果](escape-result.png)均有随后恢复／重开的路线检查。图片哈希与原始进程分组见回执；文字／轮廓／时间是重制可读性选择。

## 原始回执与失败边界

第一组PID72630的四条路线有匹配`LARGE_ACTOR_RENDER_PASS routes=4`和JSON；本次接续未保留原终端退出码，未补造。第二组PID30505在empty_area／support／cure_item完成后，skip_resume夹具错误地调用新施加1回合麻痺，触发现有验证失败；只采纳此前三条无失败路线。进程已结束，但身份恢复后工具拒绝接管原匿名进程，无法取回退出码；日志明确有诊断，不称整个进程通过。

修正为合法状态的一拍剩余时间后，第三组PID46330完成剩余六条，真实终端退出0，`LARGE_ACTOR_RENDER_PASS routes=6`且无Godot诊断。较早的错误开发入口、未注册039进度、占格查询表混用以及满操作窗口前点击的问题留在ignored原日志，未升级为通过证据。源头像／声音／空图均在对应生成器核对，不以本页画面证明原加载器完整等价。

```sh
tools/godot.sh --screen 0 --script res://tests/capture_large_actor_review.gd
tools/godot.sh --headless --script res://tests/run_large_actor_tests.gd
tools/verify.sh
```

屏幕索引须先查询当前内建屏；主缓存／窗口与完整门禁顺序独占。最终完整门禁的实际日志和退出码记入本批提交说明。

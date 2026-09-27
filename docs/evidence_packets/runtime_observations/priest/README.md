# 002祭司：实际输入、成长与资源行动

> evidence: runtime-measured · status: live · tools: capture_priest_review.gd, run_support_magic_tests.gd · updated: 2026-09-18

本批在`20f4dd4`之后接入002祭司与非Leonard主角。原玩家槽／模板复制、job85派生、原普通运动和回魔物品分别见[研究依据](../../static_reverse/original_priest.md)；本页为Godot真实控件流程，机器回执见[receipt.json](receipt.json)。

## 已完成路线

| 路线 | 玩家结果与核对 |
| --- | --- |
| manual | 直接启动已发布PriestTrial，原002肖像／錫杖／治癒之水可用；通过真实队列治疗受伤同伴，F5/F9保留非Leonard主角 |
| healing_growth | 治疗贡献进入最终EXP和祭司成长，完整分配后才开放白光之翼第二行动；换成原合法法杖87再攻击，保存不重复成长 |
| mana_extra | 耗尽MP后技能不可用；实际使用244恢复19点缺失MP，完成蓝色反馈后第二行动治疗，MP剩13，物品只消耗一次 |
| phase_mobility | 装备移动施法环、选择／取消法术与撤回移动，再移动治疗；第二行动卸环立即恢复限制，毒只在最后行动扣一次 |
| melee_series | 两次独立行动中各播放主攻双击和反击双击，共八个实际impact；逐击数值、升级、气力和两次保存不重复。最后构图补拍保留原起跳／落地轨迹 |
| ai_heal、ai_silence、ai_paralysis | AI使用真实初始治疗，支付后MP不足则第二行动重新回退；禁魔时使用已有HP药，麻痺只跳过一次且不再授予第二行动 |
| victory、defeat、escape | 实际击杀、致命反击、移动至开发撤离区；结果使用緹娜姓名，三终态F5/F9和鼠标重开均保持配置主角，终态禁止后续结算 |

所有路线为正常时钟、640×480窗口、内建屏0。manual使用已发布开发场原样；其余路线的初始HP加值、固定速度、受伤同伴、经验99、状态、命中补偿、反击参数及双击来源覆盖都保存到回执。原002初始法术和法杖来自源表，白光之翼、移动饰品等额外库存属于开发设置；不称正式第三战或自然授予。

## 图证与真实失败范围

[初始界面](manual-entry.png)、[治疗后成长](healing_growth-growth.png)、[合法祭司法杖](healing_growth-equipment-87.png)、[回魔反馈](mana_extra-item-1.png)、[移动选点](phase_mobility-move-preview.png)、[完整起跳构图](melee_series-jump.png)、[末次反击](melee_series-impact-8.png)、[AI治疗](ai_heal-impact-1.png)、[麻痺跳过](ai_paralysis-skip.png)、[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)各自哈希进入回执。

早期进程已完成三条玩家路线，随后melee_series的八次impact断言失败；这三个具名完成范围被保留，不将该进程标为全部通过。之后八条路线具备匹配PASS日志和完成JSON。起跳实拍发现头部／法杖越过画面上沿，已用整段运动及pose边界计算固定构图比例，随后重跑melee_series，仍为八次impact／两次保存。这次补拍替换该路线的视听证据，不增加路线数。

本次接续能读取上述日志、完整JSON和图片；前两组旧进程退出码未保留，回执明确写null。构图补拍的后台session93586随后恢复并返回exit0，单独登记这项真实终端结果。最终完整门禁的退出码独立取回并写入本批提交说明。`908`项定向通过不替代整批门禁或人工看图。

收尾门禁还捕获符号目录类别与旧三职业断言两处不一致，已按四职业和现有合法类别修正。一次祭司测试在PASS后报告退出资源残留；重新导入后四次诊断均无残留，测试退出改为等待异步场景清理返回后延迟退出，随后整次完整门禁exit0且无诊断。保留失败日志和严格资源检查，不将早期PASS字符串代替零退出结果。

```sh
tools/godot.sh --screen 0 res://game/battle/development/PriestTrial.tscn
tools/godot.sh --screen 0 --script res://tests/capture_priest_review.gd
tools/godot.sh --headless --script res://tests/run_all.gd -- run_support_magic_tests.gd
tools/verify.sh
```

角色绑定与职业公式是原指令／资源证据；手动五点分配、固定NPC、窗口布局与精确播放时钟保留各自重制边界。伙伴自动入队调级／学技、jobWise、未实现月花圓舞和第三战脚本胜負另需证据及独立接入。

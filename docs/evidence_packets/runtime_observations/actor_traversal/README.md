# 角色通行与移动后行动：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_actor_traversal_review.gd, run_actor_traversal_tests.gd · updated: 2026-09-17

2026-09-17，`e7aa141`上的SR-054实现，随后保留无关的函数目录提交`e6fba50`。本包是Godot正常时钟的实际Control／鼠标／键盘输入，原作机制证据见[单格角色通行](../../static_reverse/original_actor_traversal.md)。画面和回归不能升级为原版像素／时钟或全AI等价。

## 已走通的完整链路

| 路线 | 实际操作和验收 |
| --- | --- |
| ally_attack／ally_cast／ally_support | Move悬停队友格→明确可通行不可停→点击不提交→悬停后方空格查看真实路径／费用→取消→重新移动穿过队友→普通攻击／風刃／治癒之水→数值／声音／最终EXP→后继 |
| restore | 穿过队友移动→预览／取消／确认舞空之靴→F5／F9→取消恢复原位置→按新装备预算再移动→Wait→后继；装备不丢失或叠加 |
| flying | 使用明确授予的源飞行能力，在原WRD上验证地面不可达的落点→飛行路径和费用→确认→保存恢复→取消／再次移动→Wait；不修改地图阻挡 |
| ai_cutoff | 实际Wait触发AI；唯一最短路线先经过同伴，预算1不能停在同伴格，AI留在原位置并完成一次待机 |
| ai_cast／ai_support | Wait→AI穿过同侧单位，到合法空格后施放風刃／治疗友军→实际资源与反馈→一个可控后继；分别核对技能ID和一次扣费 |
| ai_no_mp／ai_silence | Wait→AI按同一通路移动后普通攻击；无MP或禁魔不扣法术费，也不多执行第二行动 |
| victory | 穿过队友→实际击杀最后敌人→遗言／淡出→EXP和升到2级→领取／结局→清敌胜利→终态保存恢复→鼠标重开 |
| defeat | Wait→敌方穿过其同伴→致命攻击→败北页；AI播放标记清零，保存恢复和鼠标重开不重放伤害 |
| escape | 原剧情目标切换后的真实撤离格→经过同伴→落点确认／Wait→撤离胜利→终态保存恢复→鼠标重开 |

13条具名路线均通过。范围与路径按现有原WRD执行，供给的遭遇位置、速度、HP、技能和概率详列于[receipt.json](receipt.json)。它们是声明过的夹具：首战默认没有获得治疗或飞行，飞行演示沿用测试角色现有步行动画，不能当作后续飞行角色美术已经完成。

前3条成功路线所在进程，随后因restore夹具的远处敌人误放原地形墙而退出1；修正后restore／flying进程退出0。victory成功后，同进程的defeat发现真实终态AI播放未清零；最终defeat／escape进程退出0。回执保留这两个早期失败进程的范围，不把整次失败改写成PASS，失败路线由后续成功结果替换。13条名字与各自断言均单独可查。

## 关键图证

| 主题 | 图像 |
| --- | --- |
| 经过与停留的区别 | [队友格](ally_attack-transit.png)、[空格路径与费用](ally_attack-path.png) |
| 到达后原法术／支援 | [風刃实际HP反馈](ally_cast-impact.png)、[治疗正向反馈](ally_support-impact.png) |
| 原地形的飞行通路 | [飛行路径与4/5预算](flying-path.png) |
| AI移动与友军治疗 | [实际行走中路径](ai_cast-ai-move.png)、[到达后治疗](ai_support-impact.png) |
| 终局仍包含经验与成长 | [击杀后EXP／升级](victory-experience.png)、[败北](defeat-result.png)、[撤离](escape-result.png) |

以上关键帧已人工查看，文件SHA保存在回执。路径线、文字位置和精确时间是重制编排；数值与动作通过正式事务结算，截图不是第二份战斗状态。

## 默认场景整场流程

两条均使用正式开场、默认属性／装备／库存和源伤害，没有额外授予或覆盖RNG，使用正常动画时钟和实际输入。

| 策略 | 结果 | 后续 |
| --- | --- | --- |
| hold | 第7回合撤离，206.061秒 | 鼠标重开通过；[结果](default-hold-result.png) |
| advance | 第3回合败北，78.799秒 | 鼠标重开通过；[结果](default-advance-result.png) |

新同侧通行改变了双方实际路线和接敌过程。上述是本次路线证据，不是长期难度统计，也不据此调整未发生变化的伤害、库存或成长。原日志在`ignored/actor-traversal/default-hold.log`与`default-advance.log`；精简整场记录在本包receipt的default_playthroughs。

## 回归与复跑

`run_actor_traversal_tests.gd`覆盖80份原完整通行余量、同路累计费用、地面／飞行／不阻挡／高差、落点与预算前缀、占用变化／死亡、移动后攻法援、MP／禁魔、保存一致性、成长、预览坐标和终态。先用原实现复现6项通行差异；后续真实败北残留AI播放及坏地形仍可初始化分别有red，修复后8601项通过。Python另验证保存的原结果、停止边界／锚点篡改拒绝、源能力和两个WRD字节重建。

```sh
tools/godot.sh --headless --import
tools/godot.sh --headless --script res://tests/run_actor_traversal_tests.gd
# 先查询当前内建屏索引。本次为1，不能假定所有机器或以后都相同。
tools/godot.sh --screen 1 --script res://tests/capture_actor_traversal_review.gd
# 或只重验有新改动的具名路线，例如：
tools/godot.sh --screen 1 --script res://tests/capture_actor_traversal_review.gd -- defeat escape
```

仅在内建屏打开一个可见验收窗口，前一进程退出后再执行下一条；不与清理缓存的完整verify并行。本批未启动Wine、未操作原作存档或用户鼠标桌面。现有原音效随真实播放记录，未宣称完成原作混音听感对照。完整门禁最终结果与提交身份以本批Git提交说明为准。

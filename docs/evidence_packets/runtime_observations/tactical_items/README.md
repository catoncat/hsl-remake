# 战内道具、解除禁魔与气力：实际输入验收

> evidence: runtime-measured · status: live · tools: capture_tactical_items_review.gd, run_tactical_items_tests.gd · updated: 2026-09-18

SR-065基线`d28e33a`，正常时钟、640×480，全部后续交互经真实控件。本次显示器查询确认内建屏1，新增AI／麻痺／终态／无效目标路线均在屏1；先前十条回执记录屏0，保留当时索引，不据当前显示器顺序补称它是内建屏。源规则见[战斗道具](../../static_reverse/original_tactical_items.md)；[机器回执](receipt.json)记录17条具名路线的初末状态、独立物品收据／抽样、交锋、状态尾部、声音、保存和终态。默认物品与技能没有额外赠予；manual使用公开`TacticalItemsTrial`，其它路线的耐久／库存／状态／概率覆盖均在回执中声明。

| 路线 | 实际覆盖 |
| --- | --- |
| manual、repeat、expiry | 公开演练首次使用、取消不消费／不抽样、第二行动重复只延时、保存恢复同一强度、自然队列推进到到期及数值恢复 |
| mixed、dispel、cure | 道具与法术互相施加后按各自原合并规则；敌人退魔清道具增益但保留禁魔；破魔咒保留毒与两种增益，第二行动支付实际治疗 |
| stamina、melee、growth、movement | 无MP／禁魔时饮酒资助20气力月花圓舞；增益下两击／两反击与暴击；击杀EXP／分配成长及换装后移动治疗；先移动用药、第二行动重新获得原地施法资格 |
| ai_self、ai_ally、paralysis | 实际库存的首个匹配解除物、自救后重建拥有的治疗、友军解除后第二次不重用；麻痺跳过无消耗、下一合法入口才解除禁魔并治疗 |
| invalid | 自身无禁魔／气力已满时目标禁用，点击与取消无状态／库存／随机变化；对有效友军连续使用后，背包显示空且无遗留使用按钮 |
| victory、defeat、escape | 用药后第二行动击杀胜利、致命反击败北、原地形移动撤离；终态保存恢复、拒绝后续物品／AI／尾部调用、鼠标重开回初始状态 |

## 已检查图证

[重复维持6点只延至6回](repeat-item-2.png)、[自然到期减6](expiry-tail-7-0.png)、[敌方退魔](dispel-cast-1-dispel-true.png)、[破魔后毒与攻防仍在](cure-stats-tina.png)、[实际20气力](stamina-item-1.png)、[增益下独立双击／暴击](melee-cast-1-ordinary-true.png)、[击杀后成长](growth-growth.png)、[AI自用破魔](ai_self-item-1.png)、[库存耗尽](invalid-empty-inventory.png)。终态：[胜利](victory-result.png)、[败北](defeat-result.png)、[撤离](escape-result.png)。12张图片按原尺寸检查，哈希保存在回执；复用源物品声及后续真实交锋／技能声音，提示0.7秒为重制时钟。

## 进程与修正范围

早期manual完成后，repeat夹具的取消菜单展开等待不足导致失败；只采用manual已完成范围，原终端退出码未在接续时取回。修正后的五条强化路线、四条后续动作路线有无诊断PASS日志和完整JSON，原终端退出码同样保留为未知，不能只凭PASS补造退出0。

本次AI自救和友援完成后，麻痺路线的装备页读取槽内可省略的`name`产生脚本错误。改为按实际装备编号读取统一目录名称；该进程主动终止退出143，只接受错误前的两条AI路线，不接受之后曾生成的其它结果。修正后麻痺／三终态四条同进程退出0，无诊断；另行增加的invalid路线在修正其脚本缩进后退出0。原失败日志均留`ignored/tactical-items/`，最终收录范围逐进程标注。

回执中的17条具名路线不等于17个独立进程，也不把设置过数据的演练写成默认自然通关。共享战斗／默认场景完整门禁由本批最终`tools/verify.sh`负责，最终退出码与检查数量写入提交正文。原完整物品dispatcher、全局随机流、主动AI饮酒／强化策略、永久成长道具仍不由本批推导。

完整门禁暴露的旧测试合同也已校正：带毒法师持有246解毒草时会正确先自救，“反击后毒伤”、普通AI与呼叫攻击回退夹具现明确空背包；玩家／AI物品收据新增真实调用者快照后不能整字典相等，改为逐一保留并检查不同角色来源，同时比较完整效果／库存／随机／序号部分。没有为了通过旧断言撤销已验证的自救或删除保存重放校验。

```sh
tools/godot.sh --screen 1 --script res://tests/capture_tactical_items_review.gd
tools/godot.sh --headless --script res://tests/run_tactical_items_tests.gd
tools/verify.sh
```

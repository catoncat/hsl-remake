# 永久能力道具、原始抗性与派生刷新

> evidence: resource-derived; static-derived · status: live · functions: 0x409e10, 0x409e40, 0x448840 · tools: hsltools/data/permanent_items.py, hsltools/probes/permanent_items.py · updated: 2026-09-27

证据等级：原表字段为`resource-derived`；固定EXE内的有界执行为`static-derived`。独立随机流、开发库存和战役承接属于明示重制策略。与临时攻防状态的规则见[战斗道具](original_tactical_items.md)及[攻防增益／退魔](original_stat_magic.md)。

## 原表与实际作用字段

| 原道具 | ITEM字段 | 原角色持久字段 | 每次成功使用 |
| --- | --- | --- | --- |
| 253 力之源 | `global_add_weapon_power` | `+0x1a4` | 原攻击来源增加1～5 |
| 254 禦之源 | `global_add_defense` | `+0x1ac` | 原防御来源增加1～5 |
| 255 魔之源 | `global_add_magic_power` | `+0x1a8` | 原魔击来源增加1～5 |
| 256 速之源 | `global_add_speed` | `+0x1b0` | 原速度来源增加1～5 |
| 257／259／260／258／261 土／水／風／火／靈之源 | 对应`global_add_resist_*` | `+0x118..0x128` | 对应原始抗性增加1，封顶80 |

这些字段与力量／反应／精神／体质不同，也不是装备delta或攻防状态word。原`0x409e40`经`0x409e10`对正向区间作一次含两端的抽样；固定1仍调用bound1。重复使用再次取得独立增量，不沿用临时會心／鐵壁“只延长持续”的分支。获得后调用共同`0x448840`，不是直接给显示值加一次就结束。

原始抗性和最终抗性是两个不同位置的限幅：道具先将原始抗性限制到0～80；职业计算自己的抗性部分、加入原始值及当前装备之后，派生刷新再把最终抗性限制到0～80。显示已经80而原始尚未80时，仍可增加原始值；卸掉装备后可以看到这部分保留的收益。80不是命中概率或通用免疫位，魔法数值／状态仍经过各自已验证的roll和装备防护门禁。

## 原指令验证

[`original_permanent_items.json`](original_permanent_items.json)由`tools/hsltools/probes/permanent_items.py`实际执行生成，锁定原EXE哈希、ITEM／PLAYERS／TYPE来源和四段原字节。82组输入包括001剑士、002祭司、026法师、024兽战士，初值／已取得加值、1／20／80级、当前装备、毒／禁魔／麻痺与攻防增益，以及五系原始抗性79／80边界。

每组先完整执行原属性刷新，再连续两次执行道具前段，最后分别执行相同状态重复刷新、升一级刷新和卸掉装备后的刷新。因此含164次道具前段、328次独立完整属性刷新返回；道具内部的刷新调用另有计数。道具前段止于`0x40a343`音效入口之前，不替换被调用函数；没有执行原caller的库存付款、队列交接或整个表现dispatcher。

每一步比较九个持久字段、攻击／防御／魔击／速度、HP／MP上限、移动和五抗性。还逐字节确认四基础属性、现有异常、装备、库存、EXP及当前HP／MP／ST未被道具前段误改。后续刷新前故意污染缓存派生值，确认从持久来源恢复；不能依赖上一帧的派生值。

## Godot的同一来源链

`PermanentCapabilityRules`保存九个具名`permanent_gains`，与不可变`growth_profile.source`分开；纯`effective_profile`将二者组合后交给已有四职业`JobStatsRules`，再合并当前装备与临时状态。所有当前单位和增援模板初始化为空收益；获得仅发生在实际库存物使用被接受时。升级／装卸／到期／退魔使用相同重算入口，不能把收益反写到模板或叠加上次派生值。

`ItemUseRules`只作预览，`ItemResolutionRules`在同一提案中完成实际库存扣除、永久字段变化、派生刷新、随机流和不可变收据，PlayLoop一次提交并走共同动作完成出口。一次道具使用不赠送EXP、HP、MP、ST或额外行动。`action_twice`允许下一次独立使用，最终状态尾部仍仅执行一次；禁魔不禁止物品，麻痺禁止主人行动但不禁止友军帮助。物品距离、移动后使用、取消与过期请求沿用已成立的库存／阶段合同。

道具施加后普通／反击／暴击读取当前攻防，魔法读取当前魔击与最终抗性；`double_attack`不会重用物品，临时退魔不会清永久来源。当前轮的速度队列快照保留，下次正常重建才按新速度排序。AI对当前已改变的数值重新生成合法动作；尚无原作证据支持主动消耗稀有永久物的优先级，不能为了演示新增该策略。

Checkpoint保存获得值和原item收据，恢复只验证、不再次施加或抽样。九个字段、非负整数、原始抗性及派生一致性受校验；1000000是重制的保存输入安全上界，不宣称原EXE不存在整数溢出。原始抗性已满时原指令仍抽样、再夹回同一个80，物品照常消耗一件（`0x444aba`，见[物品命令包](original_item_actions.md)）。当前正式初始库存不加这些稀有物；[公开演练](../../../game/battle/development/PermanentItemsTrial.tscn)使用声明的额外库存，按实际002／024角色编号分配。

战役承接把`permanent_gains`作为独立字段捕获、写入JSON，再应用到相同ID／原角色编号的新单位；先校验数值和来源，再规范JSON整数表示并共同刷新。不会把临时攻防、旧RNG／物品收据或上次派生缓存当作永久来源。第二战重开恢复本战进入值，新战役从原始模板开始；独立队伍不接收另一角色的收益。HP/MP回满与队伍承接仍是既有重制策略，不作为原作跨关handler的证据。实际跨进程范围见[补充验收](#复现)。

## 实际体验与后续边界

已支持战斗但尚未实现职业成长的角色可以保留全零永久账本并继续既有行为；缺少原始来源时永久道具明确拒绝。非零取得值没有对应来源、或已有来源结构损坏时仍拒绝，不能用零值或另一个职业补齐。这项兼容边界由已有027友援路线和新增无消费回归共同检查。

GUI与原指令证据分开，见[永久道具实际输入与截图](#复现)。未验证范围包括负区间道具、原溢出行为、所有职业、原全局随机序列、自然取得这九件物品的完整关卡路线及主动稀有道具AI。扩展这些能力需要对应原caller／职业的独立验证；本批不以现有四职业和合成演练替代它们。

## 复现

`python3 tools/hsl.py check permanent_items`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [permanent_items](../runtime_observations/permanent_items/receipt.json) | manual、repeat、magic、melee、growth、movement、resistance、cap、details、mixed、paralysis、ai、speed、victory、defeat、escape | `capture_permanent_carry_review.gd`、`capture_permanent_items_review.gd`、`run_permanent_items_tests.gd`；`run_permanent_carry_tests.gd` 驱动已退役，回执为历史记录 |

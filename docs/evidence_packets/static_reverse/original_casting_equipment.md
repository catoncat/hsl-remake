# 施法装备：生命转魔力、状态防护与魔法命中

> evidence: resource-derived; static-derived · status: live · functions: 0x406fe0, 0x4094c0, 0x40e210, 0x40e430, 0x439f80, 0x448420, 0x448840 · tools: capture_casting_equipment_review.gd, hsltools/probes/casting_equipment.py, run_position_equipment_tests.gd · updated: 2026-09-18

本批以已提交的三职业刷新、资源尾部和独立两次行动为基础。新增证据为[原指令回执](original_casting_equipment.json)，类型为`resource-derived`／`static-derived`。原EXE只读，Unicorn执行使用合成内存、边界保护和独立整数预期，没有替换原callee；不是原作自然游玩记录。

## 系统对照与选择

| 差距 | 当前依据与集成范围 | 本轮处理 |
| --- | --- | --- |
| 资源消耗与装备取舍 | 减耗、自动回复已通；怨念血衣的第二效果字与原转化函数可隔离执行 | 完成有代价的HP→MP，进入当前职业派生上限、末次行动、实际反馈、AI下一轮可支付性和保存 |
| 状态与施法装备 | 装备表有明确防毒／防禁魔及命中增量；既有状态免疫与原魔法roll已恢复 | 开放六件全部字段可解释的装备，装卸和成长后重新读取当前效果，原子提交及逐目标反馈 |
| 伙伴自动成长／学技 | `0x439f80`仍涉及职业余量分配与`0x43ae60`资格更新，完整控制／初始化合同未连通 | 保持既定固定NPC模板策略；不以新增职业profile推定伙伴自动升级已完成 |
| 大型占地与高位状态机 | 单格通行已成立，大型仍缺占格、攻击范围、脚点与保存的共同合同；其余高位状态分支相互关联 | 保留明确拒绝及独立后续，不为本轮施法装备放宽size_type或其他状态 |

定位使用ITEM字段、已登记`0x448420/0x40e430`和确定性caller引用。函数目录用于查已有名称，没有付费重判或用模型概率作证。新确认的`0x4094c0`及`0x40e210`登记回known_functions，离线build将名称挂回目录；原判断仍只是候选。

## 来源与执行边界

| 原入口／字段 | 已确认行为 | 回执范围 |
| --- | --- | --- |
| ITEM loader `0x447983` | `add_magic_hit`存item+0x1c；装备应用`0x4485b6`累加actor+0xd4 | 字节锚点及80次完整refresh；不把+0xd4加到独立状态成功率 |
| loader `0x4480e5` | `avoid_poison`=主效果0x800000，`avoid_nomagic`=0x1000000 | 字节锚点、原refresh合并及已有免疫helper；能力位／状态位不混用 |
| loader `0x4481b8`，getter `0x40e210` | `hp_transfer_mp`属于item+0xa4、actor+0x190的位1；与主效果字不同 | 完整转化调用路径及字段锚点 |
| `0x448840→0x448420` | 清旧工作值，再从当前装备累加命中与OR防护／转化；保留当前已有中毒／禁魔 | 40组×两次=80次完整返回；每次预置脏工作值，结果不叠加，HP／MP／ST／EXP与状态原样保留 |
| `0x4094c0→0x406fe0` | 两次三角采样，按实际可付生命换魔力；HP最低1，MP独立封顶 | 243组：144有效前段停在0x40959f首个数字renderer前；99无损耗正常返回，包含1HP仍抽样 |
| `0x40e56b` | 已有HP回复、MP回复之后才调用转化 | source caller字节；不声称执行完整含renderer的末次行动dispatcher |

装备refresh样例覆盖job80／90、六件新装备及组合、已有毒／禁魔。源item值和synthetic job字段分开记录；原refresh应用函数不检查职业资格，所以这些原样例不能证明每个职业都可穿每件衣服。Godot换装仍通过当前源`use_job`。原PAK／PLAYERS差异和完整随机初始化结论不因这些样例改变。

## 生命转魔力的实际规则

怨念血衣145在最后一次行动尾部读取**当前最大HP**。先令`low=max(1,floor(max_hp×8/100))`、`high=max(low+1,floor(max_hp×12/100))`，`half=floor((high-low)/2)`；两个原随机数都取`0..half`，结果为`low+half-r1+r2`。奇数跨度不等价于包含两端的均匀采样。

实际扣血为`min(hp-1, sampled)`，回魔为`min(max_mp-mp, actual_hp_loss)`。因此魔力已满或职业最大MP为0时，仍会扣掉生命；生命已为1时不扣血、不回魔，但启用转化的路径仍执行两次抽样。未启用时不抽样。有效前段已同时提交HP和MP，首个数字参数包含实际HP损耗；后续MP数字的调用次序由原字节记录，未跳过renderer伪造完整返回。

Godot照原版从共用的[伤害随机流](original_damage_random.md)`damage_rng`抽这两次，保留两次抽样上界及实际结果。`ResourceRecoveryRules`在自动回复后的工作值上转化，`TurnEndRules`一次提交顺序为毒伤→HP回复→MP回复→转化扣HP→转化加MP。只有变化非零的数字进入反馈队列；1HP无数字也能正常交接。已有毒伤最低1、状态时间和连杀清理维持同一最后行动出口。白光之翼的第一行动不运行这个出口，两次独立攻击各自的EXP／资源支付不被合并或重放。

## 防护与命中的当前效果

| 装备 | 生效内容 |
| --- | --- |
| 怨念血衣145 | 当前职业允许装卸后，最后行动生命转魔力；含原防御数值 |
| 清心法衣128／銀製髮飾217 | 当前装备并集防止后续中毒；移除一个来源不会取消另一个来源 |
| 深紅之瞳219 | 防止后续禁魔；复合技能前段伤害照常结算 |
| 學者眼鏡215／魔操玉226 | 各+10魔法命中修正；魔操玉同时保留原魔击增量，两件合计+20 |

换防护装备**不解除已有状态**。中毒仍需解毒或自然到期；禁魔已经存在时，魔法菜单仍禁用，物品／普通行动保留当前资格。源魔法主命中使用`hit_ratio + hit_bonus + magic_hit_bonus`，状态成功检查`proc&4`只使用`status_hit_ratio`；命中饰品不能悄悄增加禁魔／中毒的独立成功率。

玩家、AI、范围目标和存档检查使用同一个`StatusApplicationRules.modifiers`。全免疫毒雾不产生有益候选，AI继续已有物理／移动／等待退路；混合范围逐目标应用免疫，一次付款，免疫目标没有虚构贡献。已有源天赋的非空装备映射仍保留，装备预览同时考虑天赋，避免移除一件道具后错误显示防护消失。

## 产品、表现与恢复

Item→Equip使用真实职业资格及八槽交换；预览和Status说明明确“满魔仍耗生命”和“防护不解除已有状态”，原有滚动区域容纳完整说明。成长、换装、取消和读档不会存第二份能力真相，费用、魔法命中和防护每次从当前装备重算。坏数据在换装／动作／保存前拒绝，不先回收旧装备或支付资源。

转化复用当前末尾反馈，先红色生命损耗，再蓝色魔力增加；镜头／坐标仍使用已提交行动者，原普通攻击／魔法／物品动画声音先完成，数字逐段清除后才开放后继菜单。没有为转化发明原作音效或新战斗状态。0.7秒反馈时钟是重制可读性选择，不能称原版逐帧相同。

保存policy升级为`source_resource_tail_v2`，收据的原资源、装备效果、随机状态、事件及最终资源可重算校验；旧规则配置明确不兼容，不能缺字段就静默走另一套规则。胜利、败北、撤离冻结尚未执行的末尾能力，重开恢复默认初始化；本批装备不加入默认第一战库存。

## 验证入口与剩余边界

```sh
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate casting_equipment --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
python3 tools/hsl.py check casting_equipment
tools/godot.sh --headless --script res://tests/run_all.gd -- run_position_equipment_tests.gd
tools/godot.sh --screen 1 --script res://tests/capture_casting_equipment_review.gd
tools/verify.sh
```

数值与能力合同由原指令回执支撑；实际玩法见[十六条具名验收](../runtime_observations/casting_equipment/README.md)，完整门禁最终退出码另写提交说明。仍未接入伙伴自动成长／动态学习、大型占地、其他命中附带状态和完整高位dispatcher。替换这些边界需要源初始化／控制与学习调用链的有界执行，或同时覆盖占格／目标范围／表现／保存的大型角色合同；不能用本批装备或测试通过推导它们已经还原。

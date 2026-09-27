# 攻防增益、退魔与最终行动计时

> evidence: resource-derived; static-derived · status: live · functions: 0x40aa80, 0x40b910, 0x40c2d0, 0x40c480, 0x40dcf0, 0x448840 · tools: hsltools/data/stat_magic.py, hsltools/probes/ai_stat.py, hsltools/probes/stat_magic.py, run_support_magic_tests.gd · updated: 2026-09-18

本包区分源表、隔离原指令、当前游戏事务和表现。`resource-derived`字段来自tracked MAGIC／PLAYERS／mag-spc.h；`static-derived`数值来自原EXE有界执行，不是Jev或函数目录判断。机器回执为[original_stat_magic.json](original_stat_magic.json)与[original_ai_stat.json](original_ai_stat.json)。后者不是完整AI dispatcher的等价声明。

## 源身份与数值

| 技能 | 原身份／function | 费用／施放范围 | 当前初始拥有权 |
| --- | --- | --- | --- |
| 地精守護 | EARTH code06／0x20 | 12MP／range3CellCircle；单目标 | 按PLAYERS逐角色声明，045有声明 |
| 灼熱波動 | FIRE code05／0x40 | 19MP／range3CellCircle；单目标 | 按PLAYERS逐角色声明，045有声明 |
| 退魔 | MIND code06／0x4000 | 18MP／range4CellCircle；单目标 | 027等源声明拥有，002不因此获得 |

三项均沿现有减耗、禁魔、麻痺、移动后施法资格和共同技能事务。正式第一战及002默认授予不变；`StatMagicTrial.tscn`明确向002提供三技能、向026提供退魔，并声明额外资源／装备与遭遇设置。该开发场景不是原关卡或动态学技的证明。

增益是当前攻击／防御上的**固定数值加值**，不是百分比，也不是每次刷新继续累加一层。应用前段保留原数值helper的全部调用和命中补偿：防御先proc1，攻击先proc3，随后均`rand(4)+2`采样2～5回，再以proc3采样实际强度。第二次proc3不把等级、精神、魔攻或元素抗性乘进强度。源damage范围分别16～24与12～24，但应用器还有自己的归一规则：防御低值以12为步长抬升、高于100以10递减；攻击低值以16抬升、高于96以8递减。不是简单clamp。helper主命中失败返回0后，也继续原应用路径；归一可得到最低强度，不另造“未命中则立即取消增益”的分支。

高16位保存强度、低16位保存剩余回数。重复施加保留`max(旧强度, floor((旧强度+新强度)/2))`，剩余回数相加后封顶9；不会把两个完整加值相加。每目标支援贡献为实际新增回数×2；无新增回数不凭空发放刷新经验。原经验helper仍处理等级差、随机折减和装备最终加倍，游戏在本次技能交锋收尾统一发放并开放成长，不在整场胜利再次奖励。

退魔原分支不再抽主命中随机数，只清攻击flag0x10／word+0x40与防御flag0x20／word+0x44，再调用派生刷新。毒、禁魔、麻痺的位与完整计数字保持不变；每个清除效果贡献`12×(原剩余回数+1)`。无增益的玩家目标在准备阶段拒绝，无费用、无随机数、无队列推进。法术本身既不扣HP，也不回复MP。

## 原指令边界

| 路径 | 回执与停止点 | 支持的结论 |
| --- | --- | --- |
| `0x40aa80`目标应用，含`0x40b01c/0x40b112/0x40b299` | 61组前段，在`0x40b831`后续EXP转换前停止；内部实际执行helper与`0x448840` | 源随机调用、合并、清除、贡献及HP／MP／气力／EXP不被该段越权修改 |
| `0x448840`派生刷新 | 64种输入各执行两次，128次正常返回 | 四当前职业、不同等级／装备、单独／共同增益；已有派生值不被第二次刷新再叠加 |
| `0x40b910`最终计时 | 16次完整返回，含需要的真实刷新调用 | 剩余回数递减、最后一回清word／flag并恢复派生攻防 |
| `0x440e3d`辅助优先级 | 96个有界后缀，到下一阶段入口前停止 | 回复／解除之后，`ai_help_attack`使用独立attempted0x10和mode6 |
| `0x40dcf0`、`0x40c480`及`0x40c2d0` | 48次有用性与16次连续扫描正常返回；getter在扫描内真实运行 | 已有对应正向状态不再成为该技能的AI加持目标；同阵营、8格方形邻域、排除自己、扫描游标延续 |

探针原文件SHA和字节锚点哈希固定，离线checker会拒绝修改应用后派生值、到期后派生值、返回边界和锚点字节。没有stub原callee、无审查外调用、无跳过失败的“正常返回”。合成角色内存／原技能字段覆盖范围、未覆盖条件分别保存在JSON limits中。

`known_functions`纠正旧`0x40aa80 turn_tick`路由名为`apply_skill_target_effects`；已正常返回的计时与三个AI helper登记到本包。`0x40b01c/0x40b112/0x40b299`是函数内部应用分支，不伪装成新的独立函数入口。目录构建复用已有判断，不因此重新调用Jev。

## 当前可玩事务

`StatEnhancementRules`只提案packed状态，`StatMagicRules`只提案单目标结果，`SkillResolutionRules`在一次准备中核对所有对象和费用，再产生不可变收据。PlayLoop仍是唯一写入者。对自身施法仅提交目标状态／派生攻防，MP付款单独归施法者，避免目标刷新覆盖已经支付的MP。

当前装备和底层职业属性每次重算时只加一次有效强度；装卸、升级、恢复均使用同一来源。普通／暴击反击与双击读取当前物理攻防，风火魔法和治疗仍用原魔法数值。`double_attack`不多施一次增益，`action_twice`不早减一次回数。第二行动新建当前候选；加持AI从尚缺的同类状态中选友军，退魔AI从当前有增益的敌人中选目标，首行动清除后第二行动不再次支付无效退魔。

最终行动尾部先生成完整毒伤／资源／计时提案；增益到期需刷新派生值时，在写回任何HP／MP／RNG／队列前完成校验。之后一次提交并交接。麻痺跳过一个角色槽仍执行一次尾部；武器取消未来槽沿其既有无尾部语义。死亡清理增益及占格，胜利／败北／撤离后禁止再结算尾部。Checkpoint保存v4尾部与新技能配置，回放校验只验证不重施；篡改派生加值或收据会被拒绝。

## 原图、声音与重制表现

三法术提升37张原图帧、9段原声音到`content/imported/hsl/chapter01/stat_magic/manifest.json`。退魔的MIN12按原PAK连续成员01～03、11～13、21～23、31～33取帧，不把“连续成员”错读成文件名01～12。资源检查保留原文本binding和每张图／每段音频哈希。

粒子位置、100效果tick映射和共同0.4播放倍率是明确重制时钟，不声称原秒数。数值在impact回调出现、最后粒子淡出后才交接；状态页显示总攻防及`(+增益)`、剩余回数，最后独立行动才计时。到期有明确减少值提示。自动检查不能代替实玩图证；实际回执见[增益／退魔验收](../runtime_observations/stat_magic/README.md)。

## 系统对照与仍有边界

本批补上了此前普通伤害已经读取当前攻防、却没有完整正向状态来源／反制／到期和AI调度的缺口。已有移动、施法资源、经验、成长、双击、两次行动与3×3占地直接复用，没有为新法术创建第二套状态机。

剩余主要差异是其它高位效果与原初始化自动成长，尤其MP打击／吸收和弱化等仍未接装备字段。原全局随机流、完整dispatcher、原粒子时钟、全部职业和动态学习未由本批证明；扩展须独立追踪真实callee和调用边界，不能按相邻位或函数目录标签推断。

```sh
python3 tools/hsl.py check stat_magic
python3 tools/hsl.py check ai_stat
python3 tools/hsl.py check stat_magic_data
tools/godot.sh --headless --script res://tests/run_all.gd -- run_support_magic_tests.gd
tools/godot.sh --screen 0 res://game/battle/development/StatMagicTrial.tscn
```

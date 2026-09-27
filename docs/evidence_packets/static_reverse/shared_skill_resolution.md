# 当前三种技能的共同结算与初始拥有权

> evidence: static-derived · status: record-only · functions: 0x408fe0, 0x409040, 0x409850, 0x409870, 0x409890, 0x409980, 0x4100e0, 0x4104d0 · tools: hsltools/data/skill_book.py, run_skill_resolution_tests.gd · updated: 2026-09-13

历史批次：2026-09-13。接续 [费用](original_skill_resources.md) 和 [目标](original_skill_targets.md)，当时把三种技能与明确的重制效果规则连接起来。下文公式／数量是该批历史；当前風刃／幻火已由[原伤害链](original_magic_damage.md)替换，伤害与支援贡献已进入[原最终EXP](original_experience.md)，技能注册也已扩充。特殊技伤害、动态学习等不能由共同结算升级为全原作等价。

## 来源与证据边界

`hsltools/data/skill_book.py` 将当前受支持定义、`PLAYERS.TXT` 的 **character** 段和 `mag-spc.h` 别名位连接，输出 `content/generated/hsl/skills/initial_book.json`。机器数据保存各导入表哈希、三种稳定技能ID、66个原角色的相关原文声明和受支持初始列表，等级为resource-derived。

| 稳定ID | 名称／初始来源 | 定义与别名 |
| --- | --- | --- |
| `special:magicOTHER:magicCode01` | 001的special_other=氣刃斬 | SPECIAL magicOTHER/Code01；氣刃斬别名0x1 |
| `magic:magicAIR:magicCode01` | 026的magic_wind=風刃 | MAGIC magicAIR/Code01；風刃别名0x1 |
| `magic:magicFIRE:magicCode01` | 026的magic_fire=幻火 | MAGIC magicFIRE/Code01；幻火别名0x1 |

021/023/024没有这些字段，生成数据明确保存空声明和空受支持列表，不把缺声明写成已证明原runtime始终没有能力。025虽有magic_wind=酸蝕幻霧，其别名是0x10，不会获得Code01風刃；其水系技能和未支持能力不自动开放。其他角色的相关位只决定这些受支持技能的初始声明。原动态学习、升级解锁、转职、禁用状态和角色模式仍单独未证；用户允许的模拟第二位可控角色不能靠有ST而自动获得氣刃斬。

**本批来源限制：** 新的 `--pak` 校验在PLAYERS原字节与导入表比较时失败；尝试读取差异的工具两次被阻断，尚未查明差异，不能推断只是换行或声称完整原包复核通过。严格校验入口保留为后续复核，普通 `--check` 只比较生成数据与当前tracked表。此前费用/目标包已完成的原PAK及EXE证明原样复用；本批没有新原函数执行。新的魔法结算反汇编读取也被阻断，未更换工具绕过。

复用地址包括：费用getter/门槛 `0x409890/0x409980/0x408fe0/0x409040`，原MP扣费块 `0x442ba9..0x442bcf`；目标function getter/模式 `0x409850/0x409870/0x444e9e/0x44504a`，覆盖/枚举 `0x4100e0/0x4104d0`。完整返回与内部代码块的区别继续按前两包记录。这些证明费用和所选目标路径，**不证明下面的效果公式或完整资格等价**。

## 保留的效果合同

本批实际读过旧 `_resolve_special` 和 `_try_mage_turn`：二者原先都对damage字段使用**含上下界**的抽样，再抽0..99命中；抽出后的行为相同，没有统一时改变抽样端点。二者伤害策略不同，继续明确区分：

| 技能 | source damage／hit | 当前效果策略（provisional） | 确定输入示例 |
| --- | --- | --- | --- |
| 氣刃斬 | 36..54，98 | 抽样值减当前物防，最低1 | 物防10：命中低/高端26/44；20ST扣至0 |
| 風刃 | 12..26，96 | 按风抗0..80衰减，整数截断且最低1；不减物防 | 风抗25：低/高端9/19；8MP扣至0 |
| 幻火 | 18..32，96 | 按火抗0..80衰减，整数截断且最低1；不减物防 | 火抗25：低/高端13/24；8MP扣至0 |

命中抽样在伤害抽样之后；命中阈值使用source hit_ratio，落空仍支付一次资源但HP不变。目标HP最低0，receipt另保存actual_damage用于真实HP变化和现有经验规则；致死不复制经验。当前经验仍是实际伤害加kill_exp的重制合同，不由共同结算证明原EXP规则。

## 单一准备、结算和提交

纯 `SkillResolutionRules.available/prepare/resolve` 按稳定ID核对定义type/code、初始拥有权、已支持function/范围、当前角色/目标资格、当前MP/ST和必要防御/抗性。damage必须两个非负整数且上下界合理；hit_ratio必须0..100；未知ID、缺字段、费用或目标数值非法时在RNG前拒绝。无效定义不得默认0伤害/0费用，也不能被改成普通攻击。所有原始输入字典都不被修改。

`resolve` 只返回 `{ok,caster_changes,target_changes,receipt}`；receipt包含skill_id、damage_roll、hit_roll、实际HP前后、资源before/amount/after及provisional公式标签。不能把返回的提案当成已提交的战斗结果。

PlayLoop `_resolve_skill` 是唯一资源／HP提交点，玩家特殊技和法师AI共同调用。准备和抽样成功后才提交位移、费用和目标状态，再通过既有 `_award_experience` 及统一战斗receipt编号接入表现。玩家`attack_target`负责当前角色/选敌阶段/重复请求校验，之后的行动结束仍走已恢复公共出口；AI只决定合法位置、目标和技能，保留现有选择顺序，不再维护另一份伤害或MP公式。删除旧 `_resolve_special` 的独立结算体及AI中平行公式。

公共AI入口遇到缺必需费用/命中/伤害、未知技能或选中目标缺抗性时明确scenario_error，单位和队列不变；缺抗性并不允许静默选择物理攻击。合法但资源不足或无目标仍可以选择其他已有动作，这与坏数据不同。角色没有受支持初始能力也不会被强行授予。

## 验证与复跑

`run_skill_resolution_tests.gd` 实际134项检查：三技能低/高端、命中/落空、实际RNG次数与次序、纯输入不变、换控制角色仍用同一公式、错误ID/拥有者/字段、缺物防、过量伤害截断、移动前后取消、费用/HP/经验一次提交、下一队友与重复确认，以及公共AI坏数据停止不半提交。旧费用212项、目标811项、行动508项和core/runtime均保持通过。

新增缺抗性测试最初仍允许AI选择另一名合法目标，导致测试预期不成立；已将夹具限制为唯一候选后重新通过，没有把合法选择误当产品错误。初始源码检查曾误用player段，实际是character段，已修正生成器入口。三项Python检查验证声明/别名及生成数据，未把它们写成EXE执行测试。

```sh
python3 tools/hsl.py check initial_skill_book
godot --headless --path . --script res://tests/run_skill_resolution_tests.gd
```

待恢复的严格归档复核入口为 `python3 tools/hsl.py check initial_skill_book`；本次该校验未通过，不纳入已通过声明。短Control路线和实际结果见 [skill_resolution](../runtime_observations/skill_resolution/README.md)。完整非GUI门禁最终结果写在本批提交说明。下一个机制优先追原状态禁止与效果生命周期，同时复核上述PLAYERS归档差异，不能靠改动当前函数猜原公式。

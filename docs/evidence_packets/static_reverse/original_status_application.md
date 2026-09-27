# 中毒／禁魔施加与公共结算

> evidence: resource-derived; static-derived · status: live · functions: 0x40a7b0, 0x40aa80, 0x40b910, 0x40e240, 0x40e2f0, 0x42c780 · tools: hsltools/probes/status_lifecycle.py, hsltools/probes/status_roll.py, run_status_application_tests.gd · updated: 2026-09-14

Checked 2026-09-14。接续 [已有状态生命周期](original_status_effects.md) 和 [共同技能结算](shared_skill_resolution.md)。新增机器证据为 [original_status_rolls.json](original_status_rolls.json) 与 [original_status_application.json](original_status_application.json)。证据等级为 `resource-derived`／`static-derived`；这里的原指令执行使用独立合成内存，不是原作自然游玩记录。

## 已接入的来源与规则

`MAGIC.TXT` 的 `magicAIR/magicCode05`（酸蝕幻霧，function=Poison）与 `magicMIND/magicCode02`（封魔相关复合技能，function=Attack+NoMagic）加入原有三技能注册表。身份、名称、拥有权分别来自 MAGIC、RESOURCE 与 PLAYERS/MAG-SPC 的精确声明和位；025 的酸蝕幻霧以及测试使用的045技能仍要通过同一拥有权校验。正常第一战名单和起始技能没有被改成状态演示夹具。第二战025模板补齐精神、魔击力、MP及命中补偿初值，保持当前未调整模板基线的既有边界。

| 来源 | 恢复行为 | 产品落点 |
| --- | --- | --- |
| `0x40aa80`，函数读取 `0x409868` | Magic record+0x24 function；Poison=8、NoMagic=16，不是 actor 位序 | `SkillTargetRules` 校验支持的1/8/17组合；其余明确拒绝 |
| `0x40a7b0`，随机函数 `0x42c780` | 成功率、双次三角采样、等级／精神／魔击力、元素抗性与命中补偿 | `NativeMagicRollRules`；22组完整原 helper 返回逐项比较 |
| `0x40e2f0→0x40e240` | 目标装备效果并集；keep_status_good=0x80 与特定免疫位 | 10组原 helper 返回；`StatusApplicationRules.prepare` 检查当前装备 |
| `0x448709..0x448783` | 装备效果 OR；非空装备应用后 source no_poison/no_disablemagic 映射免疫 | 显式元数据；能力位和已应用装备效果不混用 |
| `0x40ac34` | 先处理主伤害；目标HP为0跳过后续状态施加 | 复合技能致死时不消耗状态随机数，也不留下新状态 |
| `0x40ad2c..0x40ae1c` | 施毒成功抽签；加2+rand(2)次，累计上限9；另抽强度并合并 | `StatusApplicationRules` 采样，`StatusEffectRules.apply` 唯一状态合并规则 |
| `0x40ae3d..0x40aeaa` | 禁魔免疫／成功抽签；同样累计2～3次并封顶9；设置actor bit2 | 仅阻止魔法；普通动作和特殊技保留各自资格 |
| `0x40b910` | 低16持续时间递减；到期清完整DWORD和对应状态位 | 12组原函数正常返回，与公共行动收尾规则对照 |

毒强度抽样先把高于50的值按10折回41～50，把低于5的值按5折回5～9。重复施毒时，旧强度为0则采用新强度；否则取 `max(old, floor((old+incoming)/2))`，不会因较弱新毒降低旧强度。低16的次数单独相加并封顶9。计时是该角色完成的行动次数，不是帧数或全队轮次。已有规则先扣毒伤且最低1HP，再递减并清到期状态；解毒清毒位和完整毒word，保留其他状态。

## 原执行边界

`hsltools/probes/status_roll.py` 的22组数值和10组免疫查询均完整执行原 helper 并正常返回。`hsltools/probes/status_lifecycle.py` 的30组施加样例执行 `0x40aa80` 的纯施毒或纯禁魔分支，**停在0x40b831，未执行表现／经验回调，也不是完整施法函数正常返回**。另外12组仅中毒／禁魔计时样例从 `0x40b910` 执行到真实 return，其余计时字段为0；该 helper 不负责毒伤扣HP，毒伤来自前包已读的玩家／AI调用者。

每组记录原RNG调用上界／结果、读写字段、实际停止地址、指令数和正常返回标记。执行校验原EXE SHA-256、限制已读代码范围并在4096条指令内结束；没有替换callee、Wine进程、OS输入或全场自动游玩。保存结果由独立整数预期重算，Godot再消费相同原RNG序列比较，不能通过篡改返回标记把片段升级成完整函数。

此前 PLAYERS 原包对照差异仍未解决；本包没有重做或宣称通过该对照。新 helper 证据只支持各自字段／数值／边界，不升级来源名单到实际关卡初始化完全等价。

## 原子性与界面

`SkillResolutionRules.prepare_cast` 先验证当前施法者、精确拥有权、费用、范围和范围内每一个可受影响的存活敌人，全部通过才调用随机数。随后 `resolve_cast` 返回一份扣费、每目标状态／HP提案和不可变收据；PlayLoop一次提交。错误不会先扣MP、移动角色、改部分目标或推进队列。免疫／落空是合法已执行结果，按接受的施法一次扣费；重复目标输入不能再结算。

玩家通过来源BCMD09魔法入口选择真实拥有的法术，再点击地图目标。取消和旧／关闭／禁用控件回调不改战斗状态；选法术时同步地图输入阶段，取消时恢复可见行动菜单。AI沿相同资格和效果路径；缺少状态数值明确报场景数据错误，不吞掉错误改用普通攻击。AI目前的目标排序、无益施毒过滤和动作倾向仍是另一个待恢复的决策层。

酸蝕幻霧范围使用来源矩阵；存活敌我适配与稳定roster遍历是当前重制合同。只扣一次费、各目标独立抽签已验证，尚未把原单格覆盖探针扩大声称为完整原多格枚举／阻挡传播等价。复合伤害与状态先后顺序有静态和分组件证据，未执行整个复合原施法入口。

场景与 `StatusMagicPresentation` 只读收据显示技能、状态成功／免疫／未生效及生命变化。该短效果为明确重制表现。真实Control／地图点击、范围施法、取消重开、下一角色和AI毒伤／禁魔解除的图证见 [status_application](../runtime_observations/status_application/README.md)。

## 失败、死亡和终局

非法／缺失字段在RNG之前拒绝。死亡目标不接受新状态；已有死亡槽跳过，不以毒伤的1HP下限复活。已结束战斗不再接受动作或计时，保留最终快照；重新创建场景采用显式健康初值。**这不是原版死亡／战斗结束时全局清状态的证据**，相关原调用者尚未完整恢复。麻痺的wake/skip、弱化／增益refresh、动态学习、原EXP和其他被动依然独立列为缺口。

## 复跑

```sh
python3 tools/hsl.py check status_roll
python3 tools/hsl.py check status_lifecycle
godot --headless --path . --script res://tests/run_status_application_tests.gd
uv run --with unicorn==2.1.4 python3 tools/hsl.py generate status_lifecycle --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
tools/verify.sh
```

纯规则回归包含原数值／计时对照、重复施加、免疫、落空、死亡、终局、满血解毒、封魔前后资格、范围原子失败、一次扣费、重复输入和玩家／AI交接。完整非GUI门禁最终结果写入本批提交说明；自动测试不替代图证的人工检查。

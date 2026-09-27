# 减耗与最终行动后的生命／魔力回复

> evidence: static-derived · status: live · functions: 0x4094c0, 0x40e310, 0x40e330, 0x40e430 · tools: hsltools/probes/recovery.py, run_resource_recovery_tests.gd · updated: 2026-09-17

## 来源和可复现证据

源ITEM的`mp_use_half`费用门槛／实际扣费已有[技能资源包](original_skill_resources.md)支持，本轮复用它，不重复把既有32组成本探针跑成新成果。新增HP／MP回复来自原`0x40e430`和其玩家／AI收尾调用者；[机器包](original_resource_recovery.json)保存582个有界有效／无效前段以及6个完全无效果调用的完整返回。

有效HP段从`0x40e430`进入，在数字绘制前停下；MP段从`0x40e4e5`开始，显式准备调用者栈帧及之前的显示延迟，在自身绘制前停下。它们不是整函数返回，没有用stub跳过renderer。原RNG实际执行，所有有效样本调用rand(6)，九个原状态seed覆盖0至5六种返回。六个满条／缺效果组合执行完整函数，确认无RNG、无renderer、无actor变化并正常返回。

| 原指令／字段 | 确认规律 |
| --- | --- |
| ITEM loader `0x447ec4`起 | `hp_auto_restore`与`mp_auto_restore`独立置效果位0x100／0x200，不是气力、连续行动或HP转MP |
| `0x40e310`／`0x40e330` | 从当前装备工作效果字读取HP／MP回复能力 |
| `0x40e47e`起HP段 | `floor(maxHP×(5+rand6)/100)`；结果小于3时再加3，最后夹到真实缺失HP |
| `0x40e506`起MP段 | `floor(maxMP×(3+rand6)/100)`；结果小于3时再加2，最后夹到真实缺失MP |
| 数字调用实参 | HP使用type2，MP使用type3，脚点上方48；HP后MP延迟40原tick。未恢复tick到秒的换算，也未证明额外音效 |
| 玩家 `0x443bba`／AI `0x44202d`后 | 回复位于最终行动收尾，继承白光之翼首次行动跳过尾部的门禁；随后才结束状态／连杀／queue尾部 |

小数值不是简单`max(3, amount)`：例如39最大HP、roll0会回复4，60最大MP、roll0会回复3。满条／没有能力／MP上限0不抽样；重复装备来源按位OR，不回复两遍。

旧毒伤部分和持续时间来源复用[状态证据](original_status_application.md)；当前共同提交先算毒伤（至少留1HP），再算生命与魔力回复，最后输出一次持续时间／queue收尾。自动回复不移除禁魔，不复活、不发EXP、不退还攻击费用。两次行动第一段的每击气力／该段最终EXP照常结算，但自动回复与毒计时只在最后一段。

## 产品接入与保存

新支持逆十字218、至福之像223、聖魔之像224的正常装备和预览，支配者之杖94也通过当前法师完整换装与成长实玩。其他有相同已证明字段的条目仍受source use_job与范围限制；例如舞空之靴193不能给当前法师或重装兵，不因公共刷新开放而绕开资格。

`ResourceRecoveryRules`只读取当前装备能力和上限，`TurnEndRules`生成不可变尾部提案，`BattlePlayLoop`唯一提交HP／MP／持续时间／编号／RNG／queue。回复抽样照原版经0x42c780从唯一的[伤害随机流](original_damage_random.md)抽（loop键`damage_rng`，与交锋／施法／道具共用，随存档保存），不扰动战利品流；收据记下抽样前后状态，读档只自证重算。

最后一个接受的尾部receipt记录before/after、实际事件与抽样，保存验证可确定性重建这一结果，但不会真的再次扣血／回复或推进随机流。版本配置包含职业刷新及资源尾部policy；旧配置被明确拒绝，不静默猜升级数据。终态在收尾前判定时不补一次回复，死亡、撤离、读档和重开不能重新授予白光之翼或回复次数。

`BattleTurnEndCue`等待此前移动、交锋、遗言／EXP、领取、成长或用药反馈完成，按毒伤→HP→MP展示实际数字，完成后交回后继输入。移动后AI用药的反馈是回复尾部的前置，不能被尾部pending反向阻塞。读档对齐仅表现游标，不重放。新数字采用0.7秒／项的可读性时钟；自动回复本身不附会新原音效，原移动／攻击／施法／用药声音仍沿各自动作。

## 复跑

```sh
python3 tools/hsl.py check recovery
uv run --no-project --with unicorn==2.1.4 --with pillow python3 tools/hsl.py generate recovery --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
tools/godot.sh --headless --script res://tests/run_resource_recovery_tests.gd
```

源字节、原返回范围、原seed输入和坏证据拒绝由独立Python检查保护；Godot对拍算术并检查玩家／AI重决策、最终行动门禁、费用、禁魔、重复装备、卸装／升级、保存／终態。实际输入与图像记录见[职业与资源验收](../runtime_observations/role_resources/README.md)。

## 仍未支持

`hp_transfer_mp`使用另一个效果字（原`0x4094c0`），正分支会转移资源并绘制，本轮没有把它当普通回复或解锁装备145。高位状态机其余入口、更多职业、复活、动态学技、完整随机初始化和全局RNG仍需各自证据。隔离函数结果、当前Godot可玩链、原作整体等价是不同结论。

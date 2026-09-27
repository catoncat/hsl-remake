# 普通攻击与特殊技完成后的行动预算

> evidence: static-derived · status: live · tools: hsltools/evidence/offense_completion.py, run_action_handoff_tests.gd · updated: 2026-09-13

Checked: 2026-09-13。原文件身份与机器锚点在 [original_offense_completion.json](original_offense_completion.json)。来源为原 PAK `obj-051.obs` 的命令 Data8、原 EXE `hsl01.exe` 的玩家／战斗结算分派；工具 `hsltools/evidence/offense_completion.py` 已实际核对完整 EXE SHA-256、17段审阅指令、18个状态目的地和 PAK 来源。等级为 **static-derived**，没有执行攻击／特殊技原函数。

## 正常完成、落空和反击

普通攻击 state82 在 `0x4445cf` 调用结算函数，返回1表示完成、2表示待反击、0表示尚未完成。`0x44249e/0x4424b7/0x4424f9` 保留原返回路径；零经验和落空不会被转成“可以补移动”。存活目标的完成1支路 `0x4446ca` 到公共低位+2，因此82→84。84在奖励工作结束后经 `0x444770`／`0x444798` 进入 `0x4454a5`。

需要反击时82→85；`0x44460a` 等待反击完成，随后87→88，必要时89处理后续奖励。`0x44481e`／`0x444855` 同样通向 `0x4454a5`。这里没有检查移动外层是否为21，因此未移动先攻击、移动后攻击和普通落空都结束该角色的本次行动。反击死亡或战斗终局仍可能进入其他流程，不能在产品终局后继续推进。

## 特殊技

153/154为起手等待，155/156为施放等待。157开始目标枚举；158/159/160逐目标处理，161收束奖励。`0x445305` 无剩余目标时和 `0x44548b` 奖励完成时均进入 `0x4454a5`，不根据是否先移动恢复操作。此包覆盖所追普通特殊技完成协议，不宣称所有技能类别、MP/ST消耗、状态效果、反击/双击随机次序或动画时钟已恢复。

## 输入、输出与接入

输入状态是合法当前玩家已确认目标且已经完成攻击或特殊技结算。正常返回后的语义为：攻击资格已消耗，pending move已经提交，待对应演出和奖励展示完成后结束一次角色行动。确认前取消、目标无效、气力不足不满足这一输入，保持选择或回原菜单；所有资源和坐标保持不变。

纯 `ActionBudgetRules.outcome("attack"/"special")` 产生 `await_presentation`；PlayLoop写唯一行动状态并保留只读战斗收据。场景在cue/cutin/移动/模态展示结束后调用 `finish_exhausted_action`，通过同一个 `_settle_action → begin_wait_resolution → _advance_current_actor` 交接。重复调用已完成出口对新角色不生效。当前改动替换了旧的“必须 moved && attacked 才结束”假设，未改伤害公式。

组合回归在 `tests/run_action_handoff_tests.gd`：未移动/已移动、普通攻击/特殊技、命中/落空、玩家/AI后继；每次检查收据只结算一次、队列不提前推进、完成后紧接角色不跳过、失败不抽随机数、库存/坐标及队尾边界。真实Control短路线和截图另见 [action_state](../runtime_observations/action_state/README.md)。完整公共矩阵见 [original_action_state_machine.md](original_action_state_machine.md)。

```sh
PYTHONPATH=tools python3 -m hsltools.evidence.offense_completion --exe $HSL_ORIGINAL_DIR/hsl01.exe --pak $HSL_ORIGINAL_DIR/hsl.pak
python3 -m unittest tools.test_hsl_offense_completion_evidence -v
godot --headless --path . --script res://tests/run_action_handoff_tests.gd
```

首次中断工作只保存反汇编笔记；本次续接已经真正完成上述逐字节验证。此更正不会把静态证据变成原函数执行；新的八组队列选择原函数样例由独立 `original_turn_selection_native.json` 保存。

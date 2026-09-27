# 公共行动状态：命令分派、移动撤销、攻击完成与一次交接

> evidence: static-derived · status: live · functions: 0x407340, 0x4074a0, 0x407510, 0x40b910, 0x411900, 0x411990, 0x411a30, 0x411b90, 0x43bf30 · tools: capture_give_review.gd, hsltools/evidence/action_state.py, hsltools/evidence/offense_completion.py, hsltools/probes/turn_select.py · updated: 2026-09-27

## 结论

- 原版：13 个命令对象的 `obj_Data8` 决定低位 state；Move 进外层 20、走完进外层 21；移动后取消经 74→75→`0x44429b` 写回原坐标并重开选格；普通攻击（含落空、反击）、特殊技、Wait、Use 的正常完成都到公共出口 `0x4454a5`，不论是否先移动都结束该角色，随后 `0x407510` 选一次后继（static-derived）。
- 队列选择器 `0x4074a0` 选中时清 ready，向后扫描再环回，环回不增加 round；全队列无 ready 才经 `0x407340` 重建并加 round（static-derived；8 组有界原函数执行）。
- 重制：`game/sim/ActionBudgetRules.gd` 纯计算结果（保持／选移动／恢复移动／等待演出／结束），`BattlePlayLoop._settle_action → _advance_current_actor` 唯一交接；撤销移动后直接显示原位置可达格；攻击／特殊技完成在演出结束后经 `finish_exhausted_action` 交接一次（static-derived 规则；实现合同）。
- 差异：Godot 的 `action_ready` 在完成时清除，原版在选中时清除，语义不同但交接次序一致（static-derived）；移动谓词与大体型占格归 [original_movement.md](original_movement.md)，异步动画与死亡／成长回调不在本包范围。

## 证据

**static-derived**（机器包 [original_action_state_machine.json](original_action_state_machine.json)、[original_offense_completion.json](original_offense_completion.json)；原 EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`，原 PAK `@:\data\obj-051.obs` SHA-256 `f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8`）

`object+0x8e` 高位为外层 phase，`object+0x8c` 低位为子 state；外层分派 `0x44567c/0x445668`，普通低位分派 `0x445758/0x445694`。DWORD `0x00140000` 是外层 20／低位 0，不是普通 state20。

| 原对象／操作 | Data8 | 分派目的地 |
| --- | --- | --- |
| 110 移动 | 1 | `0x4440f7` |
| 111 攻击 | 2 | `0x44413d` |
| 112 物品 | 3 | `0x44416c` |
| 113 待机 | 4 | `0x4454a5` |
| 114 使用 | 5 | `0x444a8b` |
| 115 给予 | 6 | `0x444d6a` |
| 116 装备 | 7 | `0x444185` |
| 117 丢弃 | 8 | `0x4441ac` |
| 118 魔法／119 特殊技 | 9／10 | `0x4441e8`／`0x444223` |
| 120／121 | 11／12 | `0x4447a7` 公共返回（不是右键取消路径） |
| 122 状态 | 13 | `0x44425f` |

| 状态变化 | 指令／字段 | 结论 |
| --- | --- | --- |
| 选择 Move | `0x44412e` 写 `+0x8c=0x00140000` | 外层 20 入口 `0x443c4a`，移动子表 `0x445820` |
| 路径谓词成功 | `0x443d7f..0x443d91` 把 +4/+8 坐标存到 +0x96/+0x94 | 保存移动前位置；谓词内部规则归 [original_movement.md](original_movement.md) |
| 走完移动 | `0x444086` 写 `+0x8c=0x00150000` | 外层 21／低位 0 |
| 移动后菜单 | `0x4440d1..0x4440f2` | 低位 0 开 mode1 菜单后写低位 74；其他低位走普通分派并保留外层 |
| 取消移动后菜单 | `0x43e96c..0x43e9ae` | 74→75，state75 = `0x44429b` |
| 恢复位置 | `0x44429b..0x4442df` | +0x96/+0x94 写回 +4/+8，`0x411b90→0x411990` 清旧格掩码、`0x411a30→0x411900` 设新格掩码，清 DWORD 后写低位 1 重新请求 Move |
| 未走动时取消选格 | 子 state9→`0x444095`，`0x4440a8` 清 DWORD | 回外层 0／低位 0 |
| 镜头 | `0x43bf30(arg=1)` 经 `0x43c0bc` | 角色坐标减 320/192 后调 camera helper |
| 装备／丢弃 | 76→77→3 低位 word 写入 | 不清外层 21：移动前后均可操作，之后仍可攻击或撤销移动 |

| 完成路径 | 指令 | 结论 |
| --- | --- | --- |
| 普通攻击 state82 | `0x4445cf` 调结算，返回 1 完成／2 待反击／0 未完成；`0x44249e/0x4424b7/0x4424f9` | 零经验与落空不转成「可补移动」 |
| 目标存活 | `0x4446ca` 低位 +2：82→84；奖励后 `0x444770`／`0x444798`→`0x4454a5` | 结束本次行动 |
| 反击 | 82→85，`0x44460a` 等反击完成，87→88，必要时 89 奖励；`0x44481e`／`0x444855`→`0x4454a5` | 不检查外层是否为 21 |
| 特殊技 | 153/154 起手等待，155/156 施放等待，157 枚举目标，158–160 逐目标，161 奖励；`0x445305`（无剩余目标）／`0x44548b`（奖励完）→`0x4454a5` | 不按是否先移动恢复操作 |
| 公共出口 | `0x4454ac` 写 `0x10000` 再加低位 1 → 外层 1／低位 1；phase1 子表 `0x4457fc` 9 入口 | 两条终路 `0x443c1a`／`0x443c38` 先 `0x40b910`（状态持续）再一次 `0x407510` |
| 队列选择 | 当前索引 `0x4c6e48`；12 字节记录对象指针 `0x4c3940+12*i`、ready `0x4c3948+12*i`；重建 `0x4074ec`→`0x407340`，round `0x4c1bbc` | 不存在「我方全部行动后才轮到敌方」 |

**有界原函数执行**：[original_turn_selection_native.json](original_turn_selection_native.json)——`0x4074a0` 在 Unicorn x86-32 上以原指令运行，合成 200 槽、4096 条指令上限、不 stub callee；8 组（空参数、直接后继、空指针、ready=0、非布尔 ready、最后一槽、环回、环回跳过）全部正常返回，目标槽 ready 清零，其余槽不变。重建支路只静态校验，探针遇到即拒绝。

**重制侧回执**（Godot 4.7.2，640×480，viewport 输入，正常时钟；夹具把 `enemy023_1` 设为第二位可控角色，速度 Leonard 30／该角色 29，不代表正常第一战）：

| 路线 | 结果 |
| --- | --- |
| Wait／Use 241 治疗自己／Give 241 后结束 | 队列 index1、round0，后继 `enemy023_1` 可开 Status 并选 Move；Use 后 HP 10→30，库存 `[241,241,246,…]`→`[241,246,…]` |
| Drop → Attack → 后继 | 丢一件后仍可攻击；未移动攻击演出完成后只交接一次 |
| Move → Cancel → Move → Give → 后继 | (15,17)→(14,17)，撤销回 (15,17) 并立即显示可达格，重走到 (14,17)；Give 会话关闭前不换人 |
| Special → 后继 | 未移动特殊技完整演出后交接，后继不被跳过 |

四条路线后继 phase=`action_menu`、无 AI 播放；Wait 与 Special 不改库存，Drop 与 Give 只扣一件。

## 重制接线

| 输入 | 重制结果 | 拒绝／取消 |
| --- | --- | --- |
| Move | 保存原坐标，移动后可继续选命令 | 无效目的地无变化；选格返回菜单不耗动作 |
| Cancel moved | 恢复坐标与移动资格并重开选格；已确认的丢弃／装备／同 code 交换保留 | 已完成攻击或 Give 会话中拒绝 |
| Attack／Special 完成或落空 | 结束当前角色，等演出／奖励后交接 | 选敌取消、无效目标、气力不足不进出口 |
| Use | 治疗与扣物原子提交，结束角色 | 满血／无物／无效目标拒绝 |
| Give | 连续交易不换人，结束会话交接一次；同 code 可改槽序且保留撤销与攻击资格 | 满包未选交换、失效请求整笔拒绝 |
| Drop／Equip | 免费，移动前后可用 | important／take_off 及原子校验失败不扣物 |
| Wait | 移动前后均结束角色 | 非当前、死亡、终局、非法阶段拒绝 |
| Item／Status | 只显示，不耗行动 | 等待攻击演出时不能开新动作 |
| 后继 | 按实际队列选一个；最后可控角色不跳过紧接 AI 槽；队尾重建一次 | 重复信号不 double-advance；终局停止交接 |

- `game/sim/ActionBudgetRules.gd`：`outcome("attack"/"special")` 产生 `await_presentation`；provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_action_state_machine.md`。
- `game/sim/loop/BattlePlayLoop.gd`：`_settle_action`、`finish_exhausted_action`、`begin_wait_resolution`、`_advance_current_actor`；UI 只读权威坐标／phase，规则拒绝后不移动 actor mirror。
- 场景侧 `_resume_turn_presentation` 只读已结算的 PlayLoop，不写战斗状态（修正了后继仍可控时被二次结束而跳过的缺陷）。
- 存活／相邻同侧目标、确认前不取物、取消保持槽序是重制合同（provisional），替换点为对应原函数读出后。

## 复现

`PYTHONPATH=tools python3 -m hsltools.evidence.action_state --exe $HSL_ORIGINAL_DIR/hsl01.exe --pak $HSL_ORIGINAL_DIR/hsl.pak`（攻击完成段换 `hsltools.evidence.offense_completion`；选择器 `uv run --with unicorn==2.1.4 python3 tools/hsl.py generate turn_select --exe $HSL_ORIGINAL_DIR/hsl01.exe`）。重制侧路线：`tools/godot.sh --script tests/capture_give_review.gd -- actions`。

## 边界

- 移动谓词（资格／路径）、大体型占格归 [original_movement.md](original_movement.md)；镜头时钟不在本包范围。
- 异步动画、死亡／成长通知、status tick 的内部规则不在本包范围。
- 反击死亡或战斗终局可进入其他流程；重制在终局后不再推进。
- 所有技能类别、MP/ST 消耗、状态效果、反击／双击随机次序与动画时钟不由本包证明。
- 选择器的重建支路只静态校验，未执行。
- 夹具截图只证明重制后继控制，不证明原版多队友初始化或数值。

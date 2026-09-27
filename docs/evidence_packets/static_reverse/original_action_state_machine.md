# 公共行动状态、移动阶段与一次性交接

> evidence: static-derived · status: live · functions: 0x407340, 0x4074a0, 0x407510, 0x40b910, 0x411900, 0x411990, 0x411a30, 0x411b90, 0x43bf30 · tools: capture_give_review.gd, hsltools/evidence/action_state.py, hsltools/evidence/offense_completion.py, hsltools/probes/turn_select.py, run_action_handoff_tests.gd · updated: 2026-09-13

Checked: 2026-09-13。接续 [给予／交换矩阵](original_give_exchange.md)。当前已接入普通命令的公共结果、移动撤销后重选、攻击／特殊技完成和一次队列交接；完整状态效果、所有角色控制位和原异步回调仍有明确边界。

## 原版状态结构

机器包为 [original_action_state_machine.json](original_action_state_machine.json)，工具为 `tools/hsltools/evidence/action_state.py`。同一原 EXE SHA-256 为 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；原 PAK `@:\data\obj-051.obs` SHA-256 为 `f6621854fdf4a50677877744da09015f429d2d1a627d7c8490e2bd420d5428a8`。

本轮实际从原 PAK 重读13个命令对象的 `obj_Data8`，并核对原 EXE 的普通命令分派、4个外层 phase 和12个移动子状态。`object+0x8e` 的高位阶段与 `object+0x8c` 的低位子状态分别分派：外层使用 `0x44567c/0x445668`，普通低位使用 `0x445758/0x445694`。不能把 `0x00140000` 的 DWORD 状态写入解释成普通 state20。

| 原对象／操作 | Data8／低位 state | 原分派目的地 |
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
| 120／121 | 11／12 | `0x4447a7` 公共返回，不能把这些 Data8 当作右键取消路径 |
| 122 状态 | 13 | `0x44425f` |

## 移动与取消的已读路径

最初的交接修复只保存人工反汇编和分派表；后续 SR-023 已直接校验本机 EXE／PAK，并新增11段移动／结束／队列指令锚点。机器包逐项列出真正校验的地址和字节，其他解码笔记仍单列；本 checker 不执行原代码。

| 状态变化 | 指令／字段 | 可以确定的结论 |
| --- | --- | --- |
| 选择 Move | `0x44412e` 写 DWORD `+0x8c=0x00140000` | 进入外层20／低位0；外层20入口为 `0x443c4a`，移动子表 `0x445820` |
| 路径谓词成功后 | `0x443d7f..0x443d91` 把 object+4/+8 的坐标保存到 +0x96/+0x94 | 原流程保存移动前位置，用于后续返回；谓词内部所有资格／路径规则仍未在本批展开 |
| 走完移动 | `0x444086` 写 DWORD `+0x8c=0x00150000` | 进入外层21／低位0 |
| 移动后菜单 | `0x4440d1..0x4440f2` | 低位0打开 mode1 菜单后写低位74；其他低位通过普通命令分派继续，保留外层阶段 |
| 取消移动后菜单 | `0x43e96c..0x43e9ae` 的取消输入分支增加父低位 state | 74→75；state75 已由原表核对到 `0x44429b` |
| 恢复位置 | `0x44429b..0x4442df` | 从 +0x96/+0x94 写回坐标+4/+8，更新相关占格调用，清 DWORD 状态，再写低位1，重新请求 Move |
| 尚未走动时取消选格 | 移动子state9→`0x444095`，`0x4440a8` 清 DWORD 状态 | 返回普通外层0／低位0 |

装备／丢弃进入76和回物品菜单3均为**低位 word 写入**，没有由这两条写入清除已移动的外层21；Give 的回110和未使用退出回3也需结合外层理解。之前把“回到了低位菜单”直接等同“所有行动标记清零”会失去这个区别。

Live 已按该路径改为撤销后直接显示 `move_select` 及原位置的新移动范围，不必再点击 Move。恢复操作只写坐标和移动资格，已经确认的丢弃、装备以及同 code 交换保留；不能恢复一份旧 battle snapshot。其子调用 `0x411b90→0x411990` 清当前格的掩码，`0x411a30→0x411900` 设置恢复格掩码；单格支路只修改地图标志。`0x43bf30(arg=1)` 经 `0x43c0bc` 计算角色坐标减320/192并调用 camera helper。大体型占格、完整移动谓词和镜头时钟继续单独恢复。

## 公共结束与队列选择

普通攻击、反击及特殊技正常完成都到 `0x4454a5`，与 Wait／Use 共用。该处 `0x4454ac` 写 DWORD `0x10000`，再加低位1，进入**外层1／低位1**；不根据是否先移动退回菜单。phase1 子表 `0x4457fc` 的9个入口已经校验。两条最终路径 `0x443c1a`／`0x443c38` 都先调用 `0x40b910` 状态持续时间处理，再调用一次 `0x407510`，随后返回。详细攻击／落空／特殊技路径见 [original_offense_completion.md](original_offense_completion.md)。异步动画、死亡／成长通知和 status tick 的全部内部规则不是本包的实现范围。

新 [original_turn_selection_native.json](original_turn_selection_native.json) 是**真实有界原函数执行**：`0x4074a0` 在 Unicorn x86-32 上使用原始指令、合成200个队列槽和4096条指令上限，8组无重建分支全部正常返回，不 stub 任意 callee。案例覆盖空参数、直接后继、空指针、ready=0、非布尔 ready、最后一槽、环回和环回跳过。目标槽的 ready 字会清零，其他槽的指针／速度／标志保持原样。

选择器使用 `0x4c6e48` 当前索引；12字节记录的对象指针／ready 分别在 `0x4c3940 + 12*i` 和 `0x4c3948 + 12*i`。先向后扫描，再环回找仍 ready 的槽；**环回找到旧槽不会增加 round**。全队列没有 ready 后才由 `0x4074ec` 调 `0x407340` 重建并增加 `0x4c1bbc`；该重建支路仅静态校验，探针遇到它会拒绝执行。不存在“全部我方行动后才一律轮到敌方”的推导，后继取决于队列和控制资格。

Godot 的 `action_ready` 仍是完成时清除的队列元数据；原版在选中时清除 readiness，两者不能直接当成同一个位。普通完整速度轮次、当前轮快照和下一轮重建沿已验证产品合同运行，原复杂重新激活、角色注册与状态位生命周期继续保留。

## 当前行动矩阵与支持范围

| 输入／结果 | 进入条件与原版证据 | 成功结果／移动后组合 | 失败／取消 |
| --- | --- | --- | --- |
| Move | 当前可控角色、尚未移动；Data8=1→phase20 | 保存原坐标、移动后phase21；继续选其他命令 | 无效目的地无变化；选格返回菜单不扣动作 |
| Cancel moved | phase21菜单74→75→`0x44429b` | 恢复坐标、移动资格并重开选格；保留已确认物品／装备 | 已完成攻击或正在 Give 时拒绝；取消新选格返回菜单 |
| Attack／Special 正常完成、落空 | Data8=2/10，原完成出口共用`0x4454a5` | 无论是否已移动均结束当前角色；等待原对应的演出／奖励阶段后交接 | 选敌取消、无效目标、气力不足不进入完成出口；原完整资格和伤害公式另列 |
| Use 正常完成 | state118→4，与 Wait 共用出口 | 治疗和扣物原子提交、位置提交、结束角色 | 当前满血／无物／无效目标拒绝；所有药品资格与效果仍不由单一出口证明 |
| Give 正常给出／不同 code 交换 | sticky `0x10000`，退出才去公共结束 | 连续交易不换人，结束会话提交位置并交接一次 | 下次预览取消保留前面已确认交易和使用标记 |
| Give 同 code、空会话 | 比较相等不新增位；无位退出回3 | 同 code可改变槽序；退出保留移动撤销和攻击资格 | 未确认取消保持原状态；满包未选交换、失效请求整笔拒绝 |
| Drop／Equip | 普通关闭76→77→3；低位写保留phase21 | 免费；移动前后均可操作；之后可攻击或撤销移动 | important／take_off及原子校验失败不扣物不耗动作 |
| Wait | Data8=4→`0x4454a5` | 移动前后均结束角色并推进一次 | 非当前、死亡、终局和非法交互阶段均拒绝 |
| Item／Status、返回面板 | 命令及已证子UI关闭入口 | 只显示；退出不消耗当前角色 | 已完成攻击等待演出时不能通过菜单开启新动作 |
| 后继玩家／AI／下一轮 | 原selector核对；完整角色资格仍partial | 按实际队列选择一个后继；最后一可控角色不跳过紧接AI槽；队尾普通重建一次 | 重复已处理的信号不double-advance；终局停止交接 |

上述原出口是 `static-derived`，selector的8例独立标明 bounded native execution。存活／相邻同侧目标、确认前不取物、取消保持原槽序，以及未恢复的完整状态／法术资格属于当前产品合同，不能将整张表称为所有原版变体等价。

`ActionBudgetRules.outcome` 是纯结果计算：保持角色、选移动、选目标、恢复移动、等待演出或结束。PlayLoop `_settle_action` 应用结果，所有正常玩家／AI队列交接最后走 `_advance_current_actor`。结果不另存一份战斗真相；UI只调用规则并读取权威坐标／phase，规则拒绝后不得自行移动 actor mirror。`ItemActionRules` 的旧路径已移除。

## 实际缺陷与修复

原 Runtime 的 `_begin_ai_playback` 同时承担“必要时结束玩家行动”和“显示后继状态”。`choose_command(wait)` 与 `use_item` 已由 PlayLoop 推进队列；后继若仍是可控角色，interaction 已回到 `action_menu`，这个 helper 又结束一次，把该角色跳过。默认第一战只有 Leonard 可控时不容易显现。

本轮先建立两个连续可控角色的专用夹具：Wait／Use 的非队尾和队尾四组各出现完整状态／后继／表现／阶段的错误，合计16项断言失败；Give 新会话路径原本通过。修复后 `_resume_turn_presentation` 只读取已结算的 PlayLoop，无任何战斗 mutation。自动耗尽独立调用纯 `BattlePlayLoop.finish_exhausted_action`，再启动同一表现路径。开场、Wait、Use、Give 和自动耗尽均复用这一交接，不新增第二套队列或延迟战斗快照。

`run_action_handoff_tests.gd` 现扩展为真实移动前后九类结果、坐标／库存／equipment／ready／order／phase断言，包含撤销后重走、两次同code Give→Drop→Attack、最后可控角色→AI、普通攻击／特殊技命中与落空等待演出、死亡／敌军／错当前／终局拒绝。保留先前 Use/Wait 后继和队尾回归；未改变默认第一战的角色控制。两处旧测试假设（必须先移动才耗尽、撤销后应停菜单）已按新证据更新；修复了新增测试中诊断字段缺省和类型／缩进错误，最终以完整门禁诊断检查为准，不能只看脚本打印的 PASS。

```sh
PYTHONPATH=tools python3 -m hsltools.evidence.action_state --exe $HSL_ORIGINAL_DIR/hsl01.exe --pak $HSL_ORIGINAL_DIR/hsl.pak
python3 -m unittest tools.test_hsl_action_state_evidence -v
PYTHONPATH=tools python3 -m hsltools.evidence.offense_completion --exe $HSL_ORIGINAL_DIR/hsl01.exe --pak $HSL_ORIGINAL_DIR/hsl.pak
uv run --with unicorn==2.1.4 python3 tools/hsl.py generate turn_select --exe $HSL_ORIGINAL_DIR/hsl01.exe
godot --headless --path . --script res://tests/run_action_handoff_tests.gd
godot --path . --position 160,160 --resolution 640x480 --script res://tests/capture_give_review.gd -- actions
tools/verify.sh
```

GUI坐标只适用于本次核实的单内建屏布局，其他布局先查内建屏。此前 Wait／Use／Give 的 [action_handoff 回执](../runtime_observations/action_handoff/README.md)原样保留其当时媒体归档限制。本批新增短路线与当前图证见 [action_state/README.md](../runtime_observations/action_state/README.md)。完整状态效果、每角色能力和技能目标资格继续从 PROJECT 的唯一 Next steps 接续。

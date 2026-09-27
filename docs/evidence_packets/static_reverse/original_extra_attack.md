# 追加攻击：`double_attack` 一次追加打击与完整普通交锋

> evidence: static-derived · status: live · functions: 0x4092a0, 0x4423c0 · tools: hsltools/probes/extra_attack.py, run_extra_attack_tests.gd · updated: 2026-09-28

## 结论

- 原版效果 `0x8000`（装备 `double_attack` 或角色天赋 capability `0x200` 映射而来，二者 OR 不叠成第三击）让一个普通系列最多两击；主攻与反击系列都可追加；目标死亡立即截断余击与反击；中间一击不积气，最后一击命中才按其 queued 伤害积气（static-derived）。
- 重制 `game/sim/CombatSequenceRules.gd` 的 `attack_count` 给出 1／2，`BattlePlayLoop._resolve_attack_series` 在同一战斗状态逐击结算，收据以 `followups`／`counter` 分记，全交锋结束后每参与者一次 EXP 入账（static-derived）。
- 一致：43 组原指令结果（7+6 组完整返回、30 组有界前段／后缀）与重制合同相符；原版每击只出数字（`0x404643`），重制原版值同样只出数字；逐击说明文字（連擊 1/2 等）是重制反馈，只在 OPT-INFO＝公開 下显示（remake-invented，见 `BattlePresentation.strike_words`）。命中附带状态等其他被动未随本调度恢复（未读）。

## 证据

**static-derived**（SHA 锁定 EXE，未改函数、未替换返回、未 stub；[original_extra_attack.json](original_extra_attack.json) 存 43 组结果、停止地址、随机调用与九段字节锚点）

| 范围 | 原路径 | 确认内容 |
| --- | --- | --- |
| 7 组效果查询 | `0x4092a0` 完整返回 | `0x8000` 产生一次追加；`8`、`0x200`、`0x10000` 本身不是该效果 |
| 12 组天赋映射 | `0x448747 → 0x44875b` | 装备应用阶段把 capability `0x200` 映射为 `0x8000`，与装备来源 OR |
| 8 组系列初始化 | `0x4423c0 → 0x442641/0x4426f2` | 先清旧额外击／反击状态再取追加次数，早于反击模式判断 |
| 16 组完成状态 | `0x4423c0` state4（含原 EXP 调用） | 存活且有余击先重开动画；死亡清余击与反击；最后有贡献的击才到状态／气力回调；无贡献分支正常返回（另 6 组无效果收尾完整返回） |
| 积气时机 | `0x4424be` 追加分支跳回动画，绕过 `0x442483` 之后的状态／积气尾部 | 最后一击落空不补发中间一击的气力 |

源数据：ITEM 12（極光之劍）、55、69 声明 `double_attack`，只有 12 其余字段全支持（55 含 `action_twice` 与未知范围，69 含未知范围）；loader `0x447fea` 生成 `0x8000`，`action_twice` 在 `0x447e1f` 生成 `8`。PLAYERS 019／057 声明天赋，loader `0x44c46b` 生成 capability `0x200`；第一战 001／021／023／024／026 无天赋。

## 重制接线

- `game/sim/CombatSequenceRules.gd`：读当前装备与源声明，返回 1／2，缺失或非布尔声明在 RNG 前拒绝；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_extra_attack.md`。
- `game/sim/loop/BattlePlayLoop.gd` `_resolve_attack_series`：逐击调用原伤害／命中／暴击与经验换算；第一击落空仍可追加、落空补偿进入第二击；HP 归 0 即停，不抽第二击、不执行已排反击。收据字段 `strike_number`、`series_size`、`planned_strikes`；死亡、掉落与播放共用序列遍历。
- EXP：每参与者全部击先汇总，再应用幸運緞帶一次加倍；主攻升级不影响未结算的反击；死于末击反击者不作死后成长。击杀链在系列完成时更新，实际击杀只加一次总击杀、连续数与掉落。
- 表现：每实际击一条原尺寸出招／受击 clip（原帧序、挥击声、命中／落空声），impact 后显示本击暴击与 actual_damage；特写从每击 immutable before 构造 HP/ST 快照；全部 clip 结束前菜单、经验、死亡、结果由 busy 门禁阻塞（provisional：阶段文字）。
- Wait、撤离、免费换装、法术、氣刃斬不获额外行动或复制费用；存档恢复不再抽样或发奖。

## 复现

`python3 tools/hsl.py check extra_attack`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [extra_attack](../runtime_observations/extra_attack/receipt.json) | equip_move、double_counter、early_kill、late_kill、counter_defeat、ai_move、miss、special、final_kill、escape | `run_extra_attack_tests.gd`、`run_first_battle_playthrough.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 原完整 dispatcher 未执行；30 组为有界前段／后缀。
- 命中附带状态回调的其他被动未恢复。
- 原全局 RNG、全部角色初始化、逐帧时钟不在本包。
- 追加打击不是额外回合；额外行动见 [original_extra_action.md](original_extra_action.md)。
- 首战默认授予与装备不变。

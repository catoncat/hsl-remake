# 状态：中毒／禁魔的字段、施加、行动末毒伤与计时

> evidence: resource-derived; static-derived · status: live · functions: 0x40a7b0, 0x40aa80, 0x40b910, 0x40e240, 0x40e2f0, 0x42c780 · tools: hsltools/evidence/status.py, hsltools/probes/status_lifecycle.py, hsltools/probes/status_roll.py, run_status_application_tests.gd · updated: 2026-09-28

## 结论

- 原版：中毒是 actor+0x24 bit1（+0x30 低 16 次数、高 16 强度），禁魔 bit2（+0x34），麻痺 bit4（+0x3c）；`0x40aa80` 按技能 function（Poison=8、NoMagic=16）施加，各自抽成功、次数加 2+rand(2) 封顶 9，毒强度按 `max(old, floor((old+new)/2))` 合并；主伤害致死则不施加状态（static-derived；22＋10 组 helper 完整返回、30 组施加前段、12 组计时完整返回）。
- 行动结束先以强度扣 HP（最低 1），再 `0x40b910` 递减所有计时、到期清 flag 与整个 DWORD；禁魔只禁魔法，不禁特殊技；解毒（ITEM `cure_poison`）清毒位与整个毒 DWORD（static-derived）。
- 重制：`StatusApplicationRules`、`NativeMagicRollRules`、`StatusEffectRules`（唯一合并规则）、`ItemUseRules`；PlayLoop 在唯一交接出口合并状态提案（static-derived）。
- 差异：原 flags／counter 不一致、负值等异常输入重制明确拒绝；状态短演出为重制表现（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；结果见 [original_status_rolls.json](original_status_rolls.json)、[original_status_application.json](original_status_application.json)、[original_status_effects.json](original_status_effects.json)）

字段与已有状态：

| 来源／入口 | 行为 |
| --- | --- |
| TYPE.H `magicFun_Poison=8`；`0x40ad49`／`0x40ad71`／`0x40ae1c` | actor+0x24 bit1；+0x30 低 16 持续、高 16（+0x32）强度 |
| `magicFun_NoMagic=16`；`0x40ae82`／`0x40aeaa` | bit2；+0x34 低 16 持续 |
| `magicFun_Paralysis=4`；`0x40ac97`／`0x40acc0` | bit4；+0x3c 持续（旧 `action_ready_gate` 名称错误） |
| `0x43eaf0`；`0x40c5bc`／`0x40c5d9` | 玩家菜单与 AI 都用 bit2 排除魔法，特殊技不受此位 |
| ITEM code246 解毒草 `cure_poison=1`；loader `0x447f70`／`0x447f85` → ITEM+0xa0 bit31 | 与 take_off、important、no_magic 被动不同 |
| `0x40a2e6..0x40a2f9` | 清毒 flag1 与整个 DWORD+0x30，其他状态保留 |
| 玩家 `0x443ad1`，`0x443ade..0x443b02` | 行动末按强度扣 HP，最低 1 |
| AI `0x441f50`，`0x441f69..0x441f8d` | 另查 flag1，同样数值 |
| `0x40b910` | 非零 DWORD 低 16 递减（signed word），到 0 清整个 DWORD 与状态位；也处理麻痺、弱化、增益，部分过期调属性 refresh |
| `0x443c1a→0x443c22`、`0x443c38→0x443c40` | 先 tick 再队列 advance |

`core_logic.json` 的历史 `turn_tick` 键把 `0x40aa80` 写成每回合处理；它实际按 function 施加效果，计时递减是 `0x40b910`（键名保留兼容）。

施加：

| 来源 | 行为 | 执行范围 |
| --- | --- | --- |
| `0x40aa80` 读 `0x409868` | Magic record+0x24 function | — |
| `0x40a7b0`，随机 `0x42c780` | 成功率、双次三角采样、等级／精神／魔击力、元素抗性、命中补偿 | 22 组 helper 完整返回 |
| `0x40e2f0` → `0x40e240` | 目标装备效果并集；keep_status_good=0x80 与特定免疫位 | 10 组完整返回 |
| `0x448709..0x448783` | 装备效果 OR；非空装备应用后 no_poison／no_disablemagic 映射免疫 | 静态 |
| `0x40ac34` | 主伤害后目标 HP 为 0 跳过状态施加，不耗状态随机数 | 静态 |
| `0x40ad2c..0x40ae1c` | 施毒成功抽签；次数加 2+rand(2) 封顶 9；强度抽样高于 50 按 10 折回 41..50，低于 5 按 5 折回 5..9；旧强度 0 取新值，否则 `max(old, floor((old+incoming)/2))` | 30 组前段停在 `0x40b831` |
| `0x40ae3d..0x40aeaa` | 禁魔免疫／成功抽签，次数同样累计封顶 9 | 同上 |
| `0x40b910` | 计时 | 12 组从入口到 return |

例：HP30、中毒强度 7／剩 2 次、禁魔剩 1 次，行动结束后 HP23、中毒 7／剩 1、禁魔解除；HP3／强度 7 降到 1。先用解毒草则无毒伤，禁魔仍递减一次。Drop、Equip、查看、取消、未结束的 Give 会话不触发；Give 成功关闭、Use、Wait、攻击／特殊技演出完成与 AI 完成共用唯一交接入口。原 UI 选目标不查中毒（`0x44492a..0x4449b6`），无毒目标照样用药并消耗（`0x444aba`）。

**resource-derived**：`MAGIC.TXT` magicAIR／magicCode05 酸蝕幻霧（function=Poison）、magicMIND／magicCode02（Attack+NoMagic）；拥有权来自 PLAYERS／MAG-SPC 声明（025 拥有酸蝕幻霧）；第二战 025 模板补齐精神、魔击力、MP 与命中补偿初值。

**runtime-measured**（重制侧 Control 回执，已随回执目录删除）：025 施酸蝕幻霧，两敌各自施毒，MP 100→90 只扣一次；法师完成普通行动后 HP 1000→976、中毒 2→1 且强度 24 不变、禁魔 1→0。Leonard 中毒 7／2、禁魔 2 时用解毒草：中毒字段清零、禁魔只递减一次、只消耗一件，健康目标被拒。

## 重制接线

- `game/sim/StatusApplicationRules.gd`：`prepare` 查当前装备免疫并采样；`game/sim/NativeMagicRollRules.gd` 按原数值；`game/sim/StatusEffectRules.gd` `apply` 是唯一合并规则，三个 counter 只接受 0..9，flag／counter 不一致或未支持高位明确失败。
- `SkillTargetRules` 按 function 掩码白名单放行（含 1／8／9／17 在内的全部源数据组合，见 [original_skill_targets](original_skill_targets.md)「结论」）；`SkillResolutionRules.prepare_cast` 先验证施法者、拥有权、费用、范围与每个受影响存活敌人，全部通过才抽样；`resolve_cast` 返回一次扣费与每目标提案，PlayLoop 一次提交；免疫／落空仍按接受的施法扣费。
- PlayLoop `_advance_current_actor` 在唯一队列出口合并状态提案；`ItemUseRules` 生成用药效果，收据负责文案；`SkillResolutionRules.available` 在扣费与 RNG 前查禁魔。
- 死亡目标不接受新状态；已结束战斗不再计时（provisional：不是原版全局清状态的证据）。`StatusMagicPresentation` 只读收据显示成功／免疫／未生效（provisional）。

## 复现

`python3 tools/hsl.py check status_roll`；`python3 tools/hsl.py check status_lifecycle`；`python3 tools/hsl.py check status_evidence`；重制侧 `tools/godot.sh --headless --script tests/run_status_application_tests.gd`。施加与解毒的 Control 回执已随回执目录删除；解毒截图驱动 `tests/capture_status_review.gd` 保留（`tools/oss_screenshots.py` 使用）。

## 边界

- 30 组施加是 `0x40aa80` 纯施毒或纯禁魔分支前段，未执行表现／经验回调，也不是完整施法函数返回。
- 复合伤害与状态的先后只有静态与分组件证据，整个复合施法入口未执行。
- 原单格覆盖探针不扩大为多格枚举与阻挡传播等价。
- 原版死亡与战斗结束时的全局状态清理调用者未读。
- PLAYERS 原包对照差异未解决，拥有权只按导入表。
- 麻痺的入口跳过与解除见 [original_paralysis.md](original_paralysis.md)；弱化／增益 refresh 见 [original_stat_magic.md](original_stat_magic.md)。

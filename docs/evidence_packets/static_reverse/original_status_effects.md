# 中毒、禁魔与解毒的公共规则

> evidence: static-derived · status: live · functions: 0x40aa80, 0x40b910 · tools: hsltools/evidence/status.py, run_status_effect_tests.gd · updated: 2026-09-26

Checked: 2026-09-13。机器记录：[original_status_effects.json](original_status_effects.json)。本批是 `6217b4f` 共同技能结算的后续。原始函数只做静态阅读；没有新原函数执行结果。

2026-09-14 后续：[状态施加证据](original_status_application.md) 已补入实际原helper／施加片段执行，接通酸蝕幻霧和复合禁魔；下文的“施加未开放”和“本批未执行”描述的是9月13日批次，不再是当前产品状态。原包差异仍保持原边界。

## 来源与字段

原安装路径仍为 `$HSL_ORIGINAL_DIR/hsl01.exe`；预期 SHA-256 沿用已有证据的 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。本轮成功读过下列 r2 反汇编，随后新的原文件字节取样调用连续两次被工具拒绝；没有换工具绕过，也没有创建或运行 native probe。因此新增 checker 核对 tracked 表与审阅合同，不声称新 EXE 哈希／逐字节核对或原 PAK 对照通过。PLAYERS 原包与导入差异沿 [共同结算](shared_skill_resolution.md) 保留。

| 来源／入口 | 已读行为 | 接入边界 |
| --- | --- | --- |
| TYPE.H `magicFun_Poison=8`；`0x40ad49/0x40ad71/0x40ae1c` | actor+0x24 bit1；+0x30 低16为持续时间，高16（+0x32）为强度 | 处理已有中毒；施加概率与强度计算未开放 |
| `magicFun_NoMagic=16`；`0x40ae82/0x40aeaa` | actor+0x24 bit2；+0x34 低16为持续时间 | 当前玩家／AI共同技能资格读取禁魔 |
| `magicFun_Paralysis=4`；`0x40ac97/0x40acc0` | actor+0x24 bit4；+0x3c 持续时间 | 更正旧 action_ready_gate 名称；完整麻痺跳过／恢复待接入 |
| `0x43eaf0`；`0x40c5bc/0x40c5d9` | 玩家菜单与 AI 都用 status bit2 排除魔法，特殊技不受此位排除 | 不把禁魔等同于所有技能禁用 |
| ITEM.TXT code246，`cure_poison=1` | 解毒草，初始背包已有一件 | 不新增起始道具 |
| loader `0x447f70/0x447f85` → ITEM+0xa0 bit31 | 非零 cure_poison 设置 `0x80000000` | 不与装备 take_off、important 或 no_magic 被动混用 |
| `0x40a2e6..0x40a2f9` | item effect 清中毒 flag1，并清整个 DWORD+0x30 | 持续时间和强度同时清除，其他状态保留 |

`core_logic.json` 的历史 `turn_tick` key 原先把 `0x40aa80` 描述为每回合处理、把 bit4 叫 action_ready_gate，两个名称均不准确。该函数按魔法／特殊技 function 施加效果；真正的持续时间递减是 `0x40b910`。本批纠正描述和 checker，保留原 key 以兼容旧索引；原队列 ready 位仍是另一份字段。

## 行动结束时的顺序

玩家 `0x443ad1` 检查中毒 DWORD，`0x443ade..0x443b02` 以高16强度扣当前 HP，结果最低1。AI `0x441f50` 另检查中毒 flag1，`0x441f69..0x441f8d` 使用同样数值处理。角色属性值是独立输入，不把强度误解释为百分比。本批只接受 flags 与 counters 一致的存活角色；原异常组合中玩家／AI门禁差异被保留，没有宣称两条原函数所有输入等价。

随后 `0x40b910` 对非零 DWORD 递减低16，结果按 signed word 判断；到0时清整个 DWORD 及对应状态位。中毒过期还要清强度。`0x443c1a→0x443c22`、`0x443c38→0x443c40` 显示先 tick 再队列 advance。该函数还处理麻痺、弱化及增益，其中一些过期调用属性 refresh；本批产品只实现中毒／禁魔，不默默执行未恢复的属性变更。

示例：HP30、中毒强度7／剩余2次、禁魔剩余1次，角色本次行动结束后为 HP23、中毒强度7／剩余1次、禁魔解除。HP3／强度7则降到1，不会被此次毒伤击败。同一输入先成功使用解毒草，则先清中毒，再结束行动；没有毒伤，禁魔仍递减一次。Drop、Equip、查看、取消、未结束的 Give 会话不会触发这一步。Give 成功会话关闭、Use、Wait、攻击／特殊技演出完成与 AI 完成共用唯一交接入口。

## 产品实现与失败原子性

单位的 `status_flags`、`status_counters`、HP 和 inventory 都归 PlayLoop。生成器要求当前六类源角色显式 `status=0`；无状态的两个初始 counter=0 是明确的重制序列化合同。坏／缺字段不被解释为健康。初始地图角色和当前三技能没有被擅自添加施毒能力；状态施加链还待下一批恢复。

`StatusEffectRules` 只生成状态／HP提案；`ItemUseRules` 生成用药效果；`SkillResolutionRules.available` 在扣费和 RNG 前检查禁魔。PlayLoop 的 `_advance_current_actor` 在唯一队列出口合并状态提案，场景只启动既有表现。`use_item` 校验目标、所选库存格与效果后提交药品和状态，沿既有 Use outcome 结束一次行动。物品收据负责反馈文案，不能再用“HP是否增加”判断解毒是否成功。

确认前不取药和取消完整保留槽序属于重制交互。原 cure block 本身即使无毒也能清位；原 UI 选目标时不查中毒（`0x44492a..0x4449b6`），无毒目标照样用药并消耗解毒草（`0x444aba`），范围是相邻一格与自己（见[物品命令包](original_item_actions.md)）。原 flags/counter 不一致、负值、非整数和低16不在1..9的活动输入在当前模型中明确拒绝。其他状态位只保留，未支持状态的完整行动效果不由本包背书。

## 验证与复跑

```sh
python3 tools/hsl.py check status_evidence
python3 -m unittest tools.test_hsl_status_evidence -v
godot --headless --path . --import
godot --headless --path . --script res://tests/run_status_effect_tests.gd
R2_NOPLUGINS=1 r2 -N -q -e bin.relocs.apply=true -e scr.color=0 \
  -c 'pD 258 @ 0x40b910' -c 'pD 128 @ 0x443ad1' \
  -c 'pD 112 @ 0x441f50' -c 'pD 29 @ 0x447f70' \
  -c 'pD 19 @ 0x40a2e6' $HSL_ORIGINAL_DIR/hsl01.exe
```

Godot 回归覆盖有毒／健康／满血解毒、另一角色、失败／取消／重复、强度与时间的组合、1HP下限、免费操作与实际行动的时间区别、攻击演出后恰好 tick 一次、AI 禁魔与到期、队友和速度队列。它们验证实现合同，不是新的原执行 oracle。短 Control 路线和显示证据见 [status_effects](../runtime_observations/status_effects/README.md)。完整门禁最终结果记录在提交说明。

后续缺口为麻痺完整可行动／恢复路径、弱化与增益的 refresh、状态演出／恢复被动和原全局死亡／终局清理。施加概率、当前抗性／免疫与强度合并已见9月14日后续包；原完整魔法伤害与经验公式不由本包一并解决。

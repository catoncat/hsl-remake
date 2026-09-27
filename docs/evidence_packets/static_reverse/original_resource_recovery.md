# 装备：最终行动后的生命／魔力自动回复

> evidence: static-derived · status: live · functions: 0x4094c0, 0x40e310, 0x40e330, 0x40e430 · tools: hsltools/probes/recovery.py, run_resource_recovery_tests.gd · updated: 2026-09-27

## 结论

- 原版 `hp_auto_restore`／`mp_auto_restore` 装备在最终行动收尾各抽一次 rand(6)：HP 回 `floor(maxHP×(5+r)/100)`（<3 再加 3）、MP 回 `floor(maxMP×(3+r)/100)`（<3 再加 2），都夹到真实缺失量；满条、无能力或 MP 上限 0 不抽样；白光之翼首次行动跳过（static-derived）。
- 重制 `game/sim/ResourceRecoveryRules.gd` 读当前装备能力与上限，`game/sim/TurnEndRules.gd` 生成 毒伤→HP→MP 的不可变尾部提案，`BattlePlayLoop` 唯一提交；抽样取共用 [伤害随机流](original_damage_random.md) `damage_rng`（static-derived）。
- 一致：582 个有界前段与 6 次完整返回与重制算术逐项相同；数字反馈 0.7 秒／项为重制时钟，原 40 tick 间隔未换算成秒（provisional）。减耗 `mp_use_half` 见 [original_skill_resources.md](original_skill_resources.md)。

## 证据

**static-derived**（[original_resource_recovery.json](original_resource_recovery.json)；原 RNG 实际执行，九个原状态 seed 覆盖 rand(6) 全部返回 0..5）

| 原指令／字段 | 规律 |
| --- | --- |
| ITEM loader `0x447ec4` 起 | `hp_auto_restore`／`mp_auto_restore` 独立置效果位 `0x100`／`0x200` |
| `0x40e310`／`0x40e330` | 从当前装备工作效果字读 HP／MP 回复能力 |
| `0x40e47e` 起 HP 段 | `floor(maxHP×(5+rand6)/100)`，<3 加 3，夹到缺失 HP |
| `0x40e506` 起 MP 段 | `floor(maxMP×(3+rand6)/100)`，<3 加 2，夹到缺失 MP |
| 数字调用实参 | HP type2、MP type3，脚点上方 48；HP 后 MP 延迟 40 原 tick |
| 玩家 `0x443bba`／AI `0x44202d` 后 | 位于最终行动收尾，继承白光之翼首次行动跳过尾部的门禁；之后才结束状态／连杀／queue 尾部 |

有效 HP 段从 `0x40e430` 进入、MP 段从 `0x40e4e5` 起（显式准备调用者栈帧与显示延迟），都在数字绘制前停下，不是整函数返回，未 stub renderer；6 个满条／缺效果组合完整返回，确认无 RNG、无 renderer、无 actor 变化。例：最大 HP 39、roll0 回 4；最大 MP 60、roll0 回 3。重复装备来源按位 OR，不回两遍。

**resource-derived**：逆十字 218、至福之像 223、聖魔之像 224、支配者之杖 94 带回复字段；装备仍受源 `use_job` 限制。

## 重制接线

- `game/sim/ResourceRecoveryRules.gd`、`game/sim/TurnEndRules.gd`：毒伤（至少留 1HP，见 [original_status_application.md](original_status_application.md)）→HP→MP→一次持续时间／queue 收尾；自动回复不解禁魔、不复活、不发 EXP、不退攻击费用。
- 尾部 receipt 记 before/after、事件与抽样前后状态；读档只重算自证，不再扣血回复或推进随机流；旧配置明确拒绝；终态不补回复。
- `BattleTurnEndCue`：等此前移动、交锋、遗言／EXP、领取、成长或用药反馈完成后按毒伤→HP→MP 显示；不附会新原音效。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_resource_recovery.md`。

## 复现

`python3 tools/hsl.py check recovery`

重制侧实际输入回执见 [original_job_stats.md](original_job_stats.md#复现) 的 role_resources 行。

## 边界

- tick 到秒的换算与回复额外音效未证。
- 生命转魔力 `hp_transfer_mp`（`0x4094c0`）是另一效果字，见 [original_casting_equipment.md](original_casting_equipment.md)。
- 高位状态机其余入口、复活、动态学技、完整随机初始化不在本包。

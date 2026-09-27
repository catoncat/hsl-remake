# 攻防增益、退魔与最终行动计时

> evidence: resource-derived; static-derived · status: live · functions: 0x40aa80, 0x40b910, 0x40c2d0, 0x40c480, 0x40dcf0, 0x448840 · tools: hsltools/data/stat_magic.py, hsltools/probes/ai_stat.py, hsltools/probes/stat_magic.py, run_support_magic_tests.gd · updated: 2026-09-27

## 结论

- 原版地精守護／灼熱波動给当前防御／攻击固定数值加值（高 16 位强度、低 16 位剩余回数），重复施加强度取 `max(旧, floor((旧+新)/2))`、回数相加封顶 9；退魔不抽命中、只清攻防两项增益并刷新派生值；最后一回由 `0x40b910` 清除（static-derived）。
- 重制 `StatEnhancementRules`／`StatMagicRules` 提案、`SkillResolutionRules` 一次准备生成收据，PlayLoop 唯一写入；AI 加持／退魔目标按原有用性与扫描规则选择（static-derived）。
- 一致：61 组应用前段、128 次派生刷新、16 次计时与 AI helper 返回均与重制对上；粒子位置与播放时钟为重制取值（provisional）。

## 证据

**resource-derived**（MAGIC／PLAYERS／mag-spc.h）

| 技能 | 原身份／function | 费用／范围 | 初始拥有 |
| --- | --- | --- | --- |
| 地精守護 | EARTH code06／0x20 | 12MP／range3CellCircle，单目标 | 按 PLAYERS 逐角色；045 有 |
| 灼熱波動 | FIRE code05／0x40 | 19MP／range3CellCircle，单目标 | 按 PLAYERS 逐角色；045 有 |
| 退魔 | MIND code06／0x4000 | 18MP／range4CellCircle，单目标 | 027 等源声明；002 没有 |

源 damage 范围：防御 16～24、攻击 12～24。原图 37 帧、原声 9 段，见 `content/imported/hsl/chapter01/stat_magic/manifest.json`；退魔 MIN12 按 PAK 连续成员 01～03、11～13、21～23、31～33 取帧。

**static-derived**（[original_stat_magic.json](original_stat_magic.json)、[original_ai_stat.json](original_ai_stat.json)；未 stub 原 callee）

| 路径 | 回执与停止点 | 结论 |
| --- | --- | --- |
| `0x40aa80` 目标应用（内部分支 `0x40b01c`／`0x40b112`／`0x40b299`） | 61 组前段，停在 `0x40b831` EXP 转换前 | 防御先 proc1、攻击先 proc3，再 `rand(4)+2` 取 2～5 回，再以 proc3 取强度（不乘等级、精神、魔攻或抗性）；归一：防御低值以 12 为步长抬升、高于 100 以 10 递减，攻击低值以 16 抬升、高于 96 以 8 递减；主命中失败仍走应用路径 |
| 同上，退魔分支 | 同上 | 清攻击 flag 0x10／word +0x40 与防御 flag 0x20／word +0x44 后刷新；毒、禁魔、麻痺位与计数不变；每项贡献 `12×(原剩余回数+1)` |
| 贡献 | 同上 | 每目标实际新增回数 ×2；无新增回数无贡献；HP／MP／气力／EXP 不被该段修改 |
| `0x448840` 派生刷新 | 64 种输入 × 2，128 次正常返回 | 四职业、不同等级／装备、单独／共同增益；第二次刷新不叠加 |
| `0x40b910` 最终计时 | 16 次完整返回 | 剩余回数递减；最后一回清 word／flag 并恢复派生攻防 |
| `0x440e3d` 辅助优先级 | 96 个有界后缀，到下一阶段入口前停 | 回复／解除之后，`ai_help_attack` 用独立 attempted 0x10 与 mode6 |
| `0x40dcf0`、`0x40c480`、`0x40c2d0` | 48 次有用性、16 次连续扫描正常返回 | 已有同类正向状态不再成为加持目标；同阵营、8 格方形邻域、排除自己、扫描游标延续 |

`known_functions` 中 `0x40aa80` 名为 `apply_skill_target_effects`（旧名 `turn_tick` 有误）。

## 重制接线

- `game/sim/StatEnhancementRules.gd`（packed 状态）、`game/sim/StatMagicRules.gd`（单目标结果）、`game/sim/SkillResolutionRules.gd`（一次核对对象与费用）；自施法时 MP 付款单独归施法者。
- `game/sim/AISupportRules.gd`：加持 AI 从缺同类状态的友军选，退魔 AI 从有增益的敌人选；第二行动重建候选。
- 装备与职业属性每次重算只加一次有效强度；`double_attack` 不多施一次，`action_twice` 不早减回数。最终行动尾部先完整提案、校验后一次提交；麻痺跳过仍执行一次尾部；终态后不再结算。Checkpoint v4 保存尾部与技能配置，篡改派生加值或收据会被拒绝。
- `game/battle/development/StatMagicTrial.tscn`：开发场，向 002 提供三技能、026 提供退魔及额外资源；不是原关卡。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_stat_magic.md`。

## 复现

`python3 tools/hsl.py check stat_magic`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [stat_magic](../runtime_observations/stat_magic/receipt.json) | manual、repeat、expiry、dispel、movement、melee、growth、empty_mp、silence、paralysis、ai_buff、ai_dispel、ai_blocked、victory、defeat、escape | `run_support_magic_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 粒子位置、100 效果 tick 映射与 0.4 播放倍率是重制时钟。
- MP 打击／吸收、弱化等高位效果未接装备字段。
- 原全局随机流、完整 AI dispatcher、全部职业与动态学习未证明。
- 合成角色内存与未覆盖条件记录在 JSON limits。

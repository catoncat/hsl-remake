# 成长：五点预算、四属性上限与 SwordMan 派生刷新

> evidence: static-derived; runtime-measured: 重制侧成长面板读数 · status: live · functions: 0x439f20, 0x439f70, 0x448370, 0x448840 · tools: hsl_native_growth_probe.py, hsl_native_growth_refresh_probe.py, hsltools/data/first_battle_formation.py · updated: 2026-09-28

## 结论

- 原版每次升级请求 5 点，预算 = `max(0, min(5, Σ(上限 − 基础值)))`，只加在 str／dex／mind／con 四项基础属性上；上限按职业查表，jobSwordMan=80 为 90/88/80/94；`0x448840` 按职业分支重算派生值，升级与加点都不回满当前 HP/MP，只在新上限更低时向下夹（static-derived）。
- 重制 `game/sim/ProgressionRules.gd` 用同一预算、上限表和刷新公式，`BattlePlayLoop` 持有四项基础属性与派生值，成长面板只持草稿；跨多级的点数先合成一个待分配池，再由 `BattleGrowthPanel` 按级拆成每级一窗（provisional：原版逐级开窗，总点数相同，见 [original_growth_window.md](original_growth_window.md)）。
- 与原版一致：SwordMan 分支 10 组完整返回全部对上，重制面板读数与原函数夹具逐项相同（static-derived；runtime-measured）。其他职业分支见 [original_job_stats.md](original_job_stats.md)。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）

| 项 | 锚点 | 读法 |
| --- | --- | --- |
| 预算 wrapper | `0x439f70` | 以参数 5 调 `0x439f20`；测试额外传入的请求参数不影响 |
| 预算 helper | `0x439f20` | 由对象 `+0xa4` 查全局角色表 `0x4c1bc8`（步长 `0x1fc`）；基础 `+0x64/+0x68/+0x6c/+0x70`，上限 `+0x74/+0x78/+0x7c/+0x80`；先求和再夹紧，负余量不逐项归零 |
| 升级调用方 | `0x43a1ca..0x43a1f8`、`0x43a224..0x43a265` | 保存预算、清四项分配计数；等级 +1、扣旧门槛、负经验夹到 0 |
| 上限表 | `0x448370`、`0x4786bc` | 20 行 × 4 个 u16，索引 = job − 80；全 20 行存于 JSON |
| 派生刷新 | `0x448840`（执行区间 `0x448370 ≤ pc < 0x44b820`，每组 12 000 指令上限，不 stub 被调函数） | 复制四基础值→按 job−80 分派→装备→模板 HP/MP 附加→门槛→向下夹 HP/MP |

SwordMan 分支（装备增量前）：

```text
max_hp  = level + floor(180*con/100) + floor(str/8) + hit_point
max_mp  = floor(80*mind/100) + floor(con/6) + magic_point      （无魔法时为 0）
attack  = attack_power + floor(116*floor(str/2)/100) + floor(36*dex/100) + 16 + level_attack_bonus(level)
defense = defense + floor(20*str/100) + floor(mind/5) + floor(dex/3) + floor(con/3)
magic_attack = magic_attack_power + min(floor(10*mind/100) + level + 16, 76)
speed   = speed + floor(90*dex/100)
exp_threshold = min(2000, (level + 1) * 50)
```

五项抗性加值各自上限 40：(40% mind + con/4)、(26% mind + con/5)、(20% mind + con/5)、(46% mind + con/4)、(10% mind + con/6)。Leonard 初始装备在全部夹具上恒为 攻 +23、防 +24、命中 +98。

| 夹具（Leonard，SwordMan） | 当前 HP / 上限 | 攻 | 防 | 速 |
| --- | --- | ---: | ---: | ---: |
| Lv1 | 17 / 30 | 54 | 43 | 14 |
| Lv2 未加点 | 17 / 31 | 55 | — | — |
| Lv2，str+2 dex+1 mind+1 con+1 | 17 / 33 | 57 | 43 | 15 |
| 全上限 Lv99，当前 HP 故意超上限 | 夹到 285 | — | — | — |

预算 helper 另有 9 种输入 × 2 个入口共 18 次完整返回（普通余量、只剩 3／1 点、全到顶、合成超上限、正负余量混合、请求 0／12／负值）；输入里的上限是合成值。结果：[original_mechanics_audit_growth.json](original_mechanics_audit_growth.json)、[original_growth_refresh.json](original_growth_refresh.json)。

**runtime-measured**（重制侧，真实成长面板鼠标输入）

Leonard Lv1→2，草稿 str+2 dex+1 mind+1 con+1：确认后基础 18/17/9/13，上限 HP 33、当前 HP 30（不回满）、攻 57、防 43、魔攻 18、速 15；与上表原函数夹具同值。

## 重制接线

- `game/sim/ProgressionRules.gd`：预算、上限、SwordMan 刷新；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_growth_refresh.md`。
- `BattleGrowthPanel`：草稿与按级拆窗（provisional，替换点为逐级开窗）。
- `tools/hsltools/data/first_battle_formation.py`：生成场景单位时复用同一刷新结果。

## 复现

`uv run --with unicorn==2.1.4 python tools/hsl_native_growth_refresh_probe.py --check`

## 边界

- 夹具角色是合成的：只含 Leonard 模板、四基础属性、等级、当前 HP/MP、基础抗性与可选初始装备。
- 转职的字段交换由 [original_town_job_up.md](original_town_job_up.md) §Exchange helper 读出：`0x4348f0` 照抄 job code 与形态、累加抗性／移动／数值层，不动等级与四基础属性，随后调 `0x448840` 按新职业分支刷新；本包夹具不含转职后的刷新样例。
- 临时状态／增益标志等刷新分支不在夹具内。
- 经验获得公式另见 [original_experience.md](original_experience.md)，本包只证门槛。

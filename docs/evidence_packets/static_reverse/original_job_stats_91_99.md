# 职业：job 91 jobElfMan 与 job 99 jobDarkAngel 的刷新分支

> evidence: static-derived · status: live · functions: 0x448370, 0x448800, 0x448840 · tools: hsltools/probes/campaign_actor.py, hsltools/probes/job_stats.py · updated: 2026-09-27

## 结论

- 原版 `0x448840` 的 switch 对 job 91（case `0x5b`）与 job 99（case `0x63`）各有独立公式与上限行（cap 表第 11／19 行），之后接公共尾部（源加成、装备、HP/MP 夹取、抗性 0..80、移动 0..12、EXP 门槛）（static-derived）。
- 重制 `game/sim/JobStatsRules.gd` 从 `content/authored/roles/job_formulas.json` 的 91／99 表行求值，公共尾部在 `game/sim/ProgressionRules.gd`（static-derived）。
- 一致：两名代表角色（050、058）1 级源装备刷新两次正常返回，结果与公式一致；只证刷新公式，不证转职事务或整场战斗（static-derived）。

## 证据

**static-derived**（SHA 锁定 `hsl01.exe`，`hsltools/probes/job_stats.py` 的 `--execute` 后端；第二次刷新前注入陈旧派生值，结果相同）

| 角色 | 职业 | 输入 | 魔攻 | 抗性 地／水／风／火／心 | 返回指令数 |
| --- | ---: | --- | ---: | --- | --- |
| 050 | 99 | PLAYERS 初始行，1 级，源装备 | 69 | 80/71/59/80/80 | 608, 606 |
| 058 | 91 | PLAYERS 初始行，1 级，源装备 | 139 | 80/80/80/80/80 | 605, 603 |

公共部分：`0x448840` 清派生字段后按职业码分派；源 mode 位 `0x10000` 只门控 HP 等级项；`0x448370` 按职业索引读上限（91 → 第 11 行，99 → 第 19 行）；攻击等级增量来自 `0x448800`，加在分支攻击算式之后。全部为 32 位整数除法；源抗性行与装备效果在分支值之后相加，公共尾部把五项抗性夹到 0..80。

job 91 jobElfMan（先给源魔攻 +15）：

| 字段 | 公式 |
| --- | --- |
| 上限 | `str=430, dex=610, mind=1250, con=500` |
| max HP | `str/5 + hp_level + 150*con/100` |
| max MP | `120*mind/100 + con/2` |
| attack | `20*dex/100 + 96*(str/3)/100 + 6` |
| defense | `36*str/100 + mind/8 + dex/4 + con/4` |
| magic attack | `source_magic + 15 + q + 55`，`q = 40*mind/100 + 2*level`，`q > 50` 时 `q = (q-50)/2 + 50` |
| speed | `94*dex/100` |
| 地／水／风／火／心抗 | `min(64, con/3 + 50*mind/100)`／`min(64, 56*mind/100 + con/4)`／`min(64, con/3 + 34*mind/100)`／`min(64, 50*mind/100 + con/4)`／`min(64, con/3 + 42*mind/100)` |

job 99 jobDarkAngel（先给源魔攻 +26）：

| 字段 | 公式 |
| --- | --- |
| 上限 | `str=560, dex=710, mind=530, con=690` |
| max HP | `str/8 + hp_level + 110*con/100` |
| max MP | `36*con/100 + 90*mind/100` |
| attack | `42*dex/100 + 99*(str/2)/100 + 9` |
| defense | `dex/3 + mind/5 + 22*str/100 + con/4` |
| magic attack | `source_magic + 26 + min(86, 28*mind/100 + 26 + level)` |
| speed | `88*dex/100` |
| 地／水／风／火／心抗 | `min(56, 30*mind/100 + con/4)`／`min(56, con/3 + 60*mind/100)`／`min(56, 40*mind/100 + con/4)`／`min(56, con/3 + 46*mind/100)`／`min(56, 72*mind/100 + con/2)` |

角色级回执另见 [original_campaign_actors.json](original_campaign_actors.json)。

## 重制接线

- `game/sim/JobStatsRules.gd`：provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_job_stats_91_99.md`。
- `content/authored/roles/job_formulas.json` → `content/generated/hsl/roles/job_formulas.json`：91／99 表行。
- 公共刷新与装备见 [original_job_stats.md](original_job_stats.md)。

## 复现

`python3 tools/hsl.py check campaign_actor`（050／058 的代表执行存于 original_campaign_actors.json）

## 边界

- 转职事务、原全局对象调度与整场战斗执行不在本包。
- 只有两名代表角色的 1 级源装备返回；其他等级与装备组合只由公式推出。

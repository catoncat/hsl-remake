# 第一战 NPC 等级选择与重制难度决定

> evidence: static-derived · status: record-only · functions: 0x40e7a0, 0x40e800, 0x40e870 · tools: hsl_native_level_probe.py · updated: 2026-09-25

2026-09-05；`static-derived`，探针对象初始化和随机输入为合成条件。原作 EXE SHA256 与输入 PLAYERS 哈希见 `first_battle_level_selection.json`。

原版 `0x40e800` 从 str/dex/mind/con 的总和推导基础等级：总和不超过 52 时为 1，否则为 `1 + ceil((sum - 52) / 5)`。第一战五类模板总和都是 52。

`level_adjust_range` 并不是目标等级。解析器 `0x44ca64..0x44cab0` 将 range 放在角色记录 `+0x1fa`，dispersion 放在 `+0x1f8`；`0x43ef0f..0x43ef26` 把这两个 word 传给 `0x40e870`。该函数先推导基础等级，object `+0x64 == 3` 时跳过动态调整；其他分支以 `0x40e7a0` 计算的玩家登记槽位平均等级为参考，先限制在基础等级 ± range 内，再应用 dispersion 与两次有界抽样。它不是“模板里的 24 就升 24 级”。

`tools/hsl_native_level_probe.py` 在隔离 x86 仿真中执行这段原始代码：合成一个登记玩家，分别使用平均等级 1/2/5，对 object class 2/3 与随机返回 0/上界减一运行 48 个样本。仿真只允许等级选择、均级与基础等级三个函数区间，拦截已知 RNG 调用；在选定目标等级或跳过调整后立即停止，不执行属性成长。它不启动 Wine，也不控制输入。

| 模板 | range / dispersion | 队伍均级 1、可调整分支的端点 | class 3 分支 |
| --- | --- | --- | --- |
| 021 | 24 / 0 | 1–2 | 1 |
| 023 | 18 / 2 | 1–3 | 1 |
| 024 | 24 / 2 | 1–3 | 1 |
| 026 | 22 / 2 | 1–3 | 1 |

这不是原作现场实际等级：EVEF 对象的最终 class、脚本覆盖和原始随机序列尚未合并；端点采样也不是概率分布。更不能由此直接推导调整后的 HP/攻防。后续分支会修改附加属性并分配成长点，仍需完整初始化才可声明现场数值。

## 2026-09-25 更正（lane R7-NPC）

下节"保留一级模板基线"的决定已失效：`InitialRosterGrowthRules` 现按原出生调级给每名 NPC 抽等级，本表的端点 1–2／1–3 就是重制现场的取值范围；用户录屏的 023_2（L3 41/41）落在其中。触发条件与完整解释见 [original_auto_growth](original_auto_growth.md#开战调级的触发条件)。

## 当前重制版决定（已失效，2026-09-05 记录）

遵循用户允许改善规则与节奏的方向，本战保留可复现的一级模板基线，不引入动态追级或随机 NPC 成长。现有同级角色已由职业、武器、装备、法术与 AI 区分；实际坚守路线可撤离，盲目前出路线会战败。没有证据证明把所有 NPC 统一提高到上述上界会改善第一战。固定基线是明确的重制难度选择，不再作为“必须先恢复原版随机初始化才能完成第一战”的阻塞项。

若后续实际游玩显示压力过低或高，应针对可观察的战斗路线调整，而不是套用字段名或把仿真端点当原版必然结果。本轮不改变任何游戏数值。

复跑：

```sh
uv run --with unicorn==2.1.4 python tools/hsl_native_level_probe.py --output ignored/native-stats/level-selection.json
cmp ignored/native-stats/level-selection.json docs/evidence_packets/static_reverse/first_battle_level_selection.json
```

48 个有界样本提供了分支与队伍等级变化的对照，不是新游戏依赖或泛用仿真框架。没有值得进一步拆分或删除的独立抽象；不增加 Wine/full-playthrough 来重复验证未改动的战斗数值。

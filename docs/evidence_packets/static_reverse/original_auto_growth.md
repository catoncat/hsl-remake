# 成长：入场调级、自动属性分配与脚本增援

> evidence: static-derived; runtime-measured: 第一战录屏 023_2 L3 41/41、模拟器 129 关玩家出生对拍 · status: live · functions: 0x407cc0, 0x40e7a0, 0x40e800, 0x40e870, 0x439f80, 0x43eed1, 0x43f3a5, 0x4438d4, 0x44ca5c, 0x450840, 0x452408, 0x45f5f7 · tools: hsl_native_level_probe.py, hsltools/data/entry_growth.py, hsltools/probes/auto_growth.py, run_entry_growth_tests.gd · updated: 2026-09-28

## 结论

- 原版每个对象在自己第一次 tick 由 `0x40e870` 调级一次：按四项基础属性总和推基础等级，再以登记玩家平均等级、范围与离散值随机上调（只升不降），按职业配额自动分配 Δ×5 点并回满 HP/MP；剧情 opcode 73 让在场对象再调一次，全库只有 STORY006 使用（static-derived）。
- 重制 `InitialRosterGrowthRules`（开场阵容）与 `ReinforcementGrowthRules`（脚本增援）按同一规则、同一全局随机流抽样；第 6 关两段式调级按静态读法接入（static-derived）。
- 对拍：129 关新开局 1014 次玩家出生中 1013 次等级／最大 HP／攻击与重制开局值相同，余下 1 次（第 3 关漢克斯）已对齐；第一战录屏 023_2 L3 41/41 落在重制分布内（runtime-measured）。已知差异：同一阶段按阵容顺序抽样、开场前后其它全局抽取次数不是原版的，同一种子下等级不等于原版那一局（provisional）。

## 证据

**static-derived**（128 组数值函数与 16 组 VM 序列正常返回，逐次随机调用与源角色资料见 [original_auto_growth.json](original_auto_growth.json)；未替换 callee 或随机结果）

| 地址 | 结果 |
| --- | --- |
| `0x40e800` | 基础等级 `1 + max(0, ceil((sum-52)/5))`，sum 为四基础属性和；不刷新经验阈值 |
| `0x40e7a0` | 注册数组 `0x4c34c0` 槽 0..19 非空对象等级的整数平均；空集合或零平均返回 1；不按 HP 过滤 |
| `0x439f80` | 请求点数夹到剩余职业容量，每次至多 5 点：扣当前阈值、升一级、刷新、按职业配额分配、再刷新。配额处理后仍有预算时 fallback 循环不再截断，把其余属性填到职业上限 |
| `0x40e870` | 对象 kind3 或两参数皆 0 跳过随机上调；否则见下式；末尾刷新并把 HP/MP 设到上限 |
| `0x450840 → 0x450ba4` | opcode 56 `actSetPrevInsertObjectAdjustLevel`：范围写高 16 位、离散写低 16 位到上次插入对象 `+0x1f8`，不立即成长；游标前进 6 字后由 opcode 88 让出 |
| `0x44ca64..0x44cab0`、`0x43ef0f..0x43ef26` | PLAYERS `level_adjust_range` 存 `+0x1fa`、`level_adjust_disp_range` 存 `+0x1f8`，caller 把两字传给 `0x40e870`；`0x44ca5c`／`0x44ca8f` 读字段前把输出预置为 0，缺字段即 0,0 不调级 |

职业配额：job 80／88／94 为 力2 反1 精1 体1；job 85／90／92 为 力1 反1 精1 体2。

随机上调（B 基础等级，R 范围，D 离散，整数除法）：

```text
center = clamp(队伍平均, max(1, B-R), max(low+1, B+R))
low = max(1, center - min(D, 4));  high = max(low+1, center + D);  W = high - low + 1
目标 = low + rand((W+1)/2 + 1) + rand(W/2)
```

目标高于 B 时按 Δ：击杀经验增长百分比夹 15..150、金币夹 10..80，各 `(rand(4)+7)*Δ`，金币向上取整到十位；源 HP `+(rand(100)+250)*Δ/100`、MP `+(rand(150)+150)*Δ/100`、敏捷 `+(rand(20)+20)*Δ/100`、攻击 `+(rand(60)+50)*Δ/100`、魔击 `+(rand(10)+10)*Δ/100`；原气力为 0 才另抽 `rand(11)`。第一次自动分配用进入时的旧阈值。

### 开战调级的触发条件

全 EXE 四处 `call 0x40e870`：

| 入口 | 条件 |
| --- | --- |
| 出生：`0x43eed1..0x43ef35`（一般对象）、`0x44341b..0x44347d`（玩家对象） | 调用字带 `0x20000000` 的第一次 tick：清位、置 `0x100000`、`0x407cc0`（站位取整、`0x407dba` 出手延迟 `rand(24)`、pmEnemy 在 `0x407c86` 逐项 `rand(101)` 掷携带、`0x407dd1` 注册），再调级；玩家对象为 kind3，只推等级 |
| 全员重调：`0x43f3a5..0x43f3fb`、`0x4438d4..0x44393c` | `0x4c1b00 & 0x4000000` 且 `0x4c1d48` 非零；`0x4c1d48` 由 opcode 73 设置点 `0x452408` 置位、`0x452f1a` 清零、关卡初始化 `0x42c6c8` 清零 |

出生时的队伍均级：`0x45f5f7` 按 plane 0..max 调过程；玩家安装与玩家对象在 planeIcon(3)、一般敌人在 planeObject1(4)，故 EVEF 敌人出生时已看到全部 EVEF 安装的玩家；剧情插入玩家的关（6、53、56）EVEF 对象第 1 帧出生时均级为 1。随机抽样走全局生成器 `0x458c10`（状态 `0x4795d4`／`0x4795d8`，抽取点 `0x40e92c`／`0x40e938` 起），不换入伤害流 `0x4c3044`／`0x4c3040`。

第一战模板端点（`hsl_native_level_probe.py`，合成一名登记玩家，48 个有界样本；端点不是概率分布）：

| 模板 | 范围／离散 | 队伍均级 1 时可调分支端点 | kind3 |
| --- | --- | --- | --- |
| 021 | 24 / 0 | 1–2 | 1 |
| 023 | 18 / 2 | 1–3 | 1 |
| 024 | 24 / 2 | 1–3 | 1 |
| 026 | 22 / 2 | 1–3 | 1 |

**runtime-measured**

| 出处 | 读数 |
| --- | --- |
| 第一战录屏 99.5 s／151.5 s | 友军 023_2 L3、41/41；按上式 `1 + rand(3) + rand(1)` 取 3 时源 HP +5 或 6、再分 10 点，得 40 或 41 HP、速 16 |
| 模拟器，第 53 关緹娜 `0x44346e` 前后 | L1 35/35 攻 37 → L2 36/36 攻 38（基础和 57） |
| 模拟器，129 关新开局 1014 次玩家出生 | 1013 次与重制开局值相同；第 6 关 雷歐納德 1/30/54、緹娜 2/36/38、胡 4/40/46、漢克斯 7/50/64 |
| 模拟器，第 3 关漢克斯 | 出生刷新时 `+0x28 = 0x10000`（pmPlayer），`0x448851 test eax,0x10000` 计入等级项得 L7 50/50 攻 64；第 63 帧 `0x450710` 改为 `0x20000`，不再刷新 |
| 第 5 关实测 | 队伍均级 6 时 036 为 6/5/8/8/4 |

## 重制接线

- `game/sim/InitialRosterGrowthRules.gd`：先登记玩家、再按阵容顺序给 NPC 出生；第 6 关按 `opening_birth`（`story_insert` 序号、`adjust_all_level`）两段调级，二段 `entry_readjust` 从出生后状态再跑一次。
- `game/sim/ReinforcementGrowthRules.gd`、`EntryGrowthRules`：脚本增援在真实出生点应用一次；显式 `[0,0]` 覆盖模板，未写脚本参数读模板，模板未声明读作 0,0。出生收据记录全局流前后两字与抽样次序（单战快照 v6）。
- `tools/hsltools/data/entry_growth.py`：只连接已有派生公式验证的 30 个角色来源。
- 待入场队列保护 `actCheckEnemyTotalNumber` 与同兵种 `actCheckEnemyNumber` 的胜利判断；新援落点受阻时依赖敌人数的胜利等待阵容完成（重制事务合同）。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_auto_growth.md`。

## 复现

`python3 tools/hsl.py check auto_growth`

重制侧实际输入回执：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [entry_growth](../runtime_observations/entry_growth/receipt.json) | mage、thief、wing、large、zero、repeat、blocked、support、states、paralysis、victory、defeat、escape、carry、class_blocked | `run_entry_growth_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- NPC 战斗经验自动升级（奖励路径 caller `0x442729`／`0x4429af`）已由 `ProgressionRules.apply_level_ups` 的 automatic 分支经 `EntryGrowthRules` 接入，见 [original_growth_lifecycle.md](original_growth_lifecycle.md) §重制接线；该入口在奖励状态机里的逐 tick 先后未执行。
- 同一阶段内抽样次序与开场前后其它全局抽取次数不是原版的（provisional）。
- 原 HP/MP 源字段与 VM 参数均 16 位；重制只接受 0..1000 参数并拒绝 HP/MP 超 65535 的组合，不声称原版也有此限制。
- 第 200 关在帧上限内没有玩家出生，未测。
- 动态学技、未支持职业与完整对象构造不在本包。

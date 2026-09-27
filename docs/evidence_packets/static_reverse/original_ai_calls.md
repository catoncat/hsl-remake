# 原 AI：呼叫目标的广播与消费

> evidence: static-derived · status: live · functions: 0x40ba20, 0x40bb80, 0x40bee0, 0x40c110, 0x45ec32 · tools: hsltools/probes/ai_call.py, run_ai_skill_tests.gd · updated: 2026-09-27

## 结论

- 原版：普通目标查找成功时按 `ai_call_range`（+0x1cc）以圆形距离向阵营掩码精确相等的对象广播，覆盖其 +0x8a，不消费自己的旧标记；查找失败时才采用自己的呼叫标记为目标并清空，采用时不再检查自己的 `find_range`（static-derived；28 组 `0x40bee0` 正常返回＋12 组 caller prefix）。
- 重制：`game/sim/AICallRules.gd` 无 RNG 计算收件者与「普通目标优先、无则消费呼叫」分支；`BattleLoopAI` 在成功行动事务里按行动前坐标写入稳定单位 ID `ai_call_target_id`（static-derived 规则＋重制组合）。
- 差异：原广播不过滤 removed／HP，重制排除已死亡／离场单位并在击杀、离场、终局时清理引用；原分帧目标获取、锁定、等待时序未复刻（provisional）。

## 证据

**static-derived**（[original_ai_calls.json](original_ai_calls.json)，`hsltools/probes/ai_call.py`，固定 SHA 的 hsl01.exe；`0x40ba20`、`0x45ec32` 同时实际执行，无 stub，每组 ≤8192 条指令；比较全部合成对象内存，只允许目标 word 写入）

| 锚点 | 结论 |
| --- | --- |
| `0x40bee0..0x40bf66` | 遍历 200 槽，跳过空槽与自身；双方 `&0x870000` 必须精确相等；圆形距离含边界；直接覆盖收件者 +0x8a；不查 removed 或 HP；半径 0 仍写同坐标对象 |
| caller | `ai_call_range == 0` 跳过整次广播 |
| `0x43f6c2..0x43f6c6` | 普通查找返回写 +0x88；非零则广播，不消费旧 +0x8a；为零才读呼叫标记、写目标并清空（采用始于 `0x43f6e6`） |
| `0x43f709..0x43f737` | 检查呼叫对象为空、removed，以及排除 word 与对象 +0xa2（object word，不是 actor SID；0 表示不检查）；失效时目标归零进 `0x40c110` |
| prefix 终点 | `0x43f73e`（辅助处理前）或 `0x43f74e`（技能桶前） |
| `0x43f544..0x43f5f5` | 已有目标保留与锁定范围，见 [original_ai_navigation.md](original_ai_navigation.md) |

夹具覆盖 3–4–5 圆边界、圆外对角格、相交但不相等的阵营、非阵营 flag、removed 对象、空槽、旧标记覆盖。

## 重制接线

- `game/sim/AICallRules.gd`、`game/sim/loop/BattleLoopAI.gd`：provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_ai_calls.md`。
- `ai_call_target_id` 是 PlayLoop 单位记录的字段；新战斗与增援初始化为空，后来的呼叫覆盖旧值。
- AI 准备阶段同时验证可能采用的呼叫目标（含超出自身搜索半径但可施法的目标）；采用后沿用移动包络、武器范围与公共技能事务，发一次收据、交接一次；无目标结算一次 Wait。
- 坏标记类型、重复单位 ID、技能数据损坏在 RNG 前返回命名错误，不消费标记、不广播。
- 重制适配（provisional）：阵营用 live 角色阵营映射；目标须为存活敌方并应用 actor SID 预排除；呼叫写入与成功行动一起发布。

## 复现

`python3 tools/hsl.py check ai_call`（重执行：`uv run --with unicorn==2.1.4 python3 tools/hsl.py generate ai_call --exe "$HSL_ORIGINAL_DIR/hsl01.exe"`）。

## 边界

- 原 caller 的 object+0xa2 比较与零哨兵语义独立保留，不等同重制的 SID 预排除。
- 原引擎分帧目标获取、锁定、等待与辅助处理时序未复刻。
- 呼叫接通不代表整体 AI 或治疗系统完成。

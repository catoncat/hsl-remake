# Winfail 执行模式与系统到达点：actSetPlayerExecMode／actRandomSetSysArrivePos／actCheckPlayerArriveSysPos

> evidence: static-derived; resource-derived: ACTION.H 值与 WINFAIL017／902 用法; provisional: 同一时钟种子选中哪一组 · status: live · functions: 0x44fad0, 0x450840, 0x458c10, 0x458c80 · tools: run_winfail_rules_tests.gd · updated: 2026-09-27

## 结论

- 原版 `actSetPlayerExecMode` 把对象 `+0x64` 写成 3（参数 0）或 5（参数非 0），与 `actSetPlayerMode` 分开；`actRandomSetSysArrivePos` 用一次 `0x458c80(N)` 从 N 组候选里选一组、两轴各按 32 像素对齐存进全局；`actCheckPlayerArriveSysPos` 以同样对齐的对象像素比较（static-derived）。
- 重制 `game/sim/WinfailActions.gd`／`WinfailScenarioRules.gd` 按此记录 `player_exec_mode` 与系统到达点，抽取走 loop 的全局流 `global_rng`（static-derived）。
- 差异：抽取之前的全局流消费（AI 决策链、动画延迟）尚未与原版一致，同一时钟种子不一定选中原版那一组（provisional）。

## 证据

### resource-derived

| token | 值 | 参数 |
| --- | --- | --- |
| `actSetPlayerExecMode` | 83（`0x53`） | `[code][serial][mode]` |
| `actRandomSetSysArrivePos` | 86（`0x56`） | `[num][x1][y1][x2][y2]...` |
| `actCheckPlayerArriveSysPos` | 87（`0x57`） | `[code][serial]` |

`WINFAIL017` 在 win 段用 `actSetPlayerExecMode SID_嚎,1,0`，脚本到达后用 mode 1；`WINFAIL902` 安装 嚎 后用 mode 1，从五个系统到达候选中选一，逐个检查队员是否到达选中点后给物品 281。

### static-derived（`0x450840` 分派）

| case | 原版 |
| --- | --- |
| `0x53` | `0x44fad0(code, serial)` 找 actor，第三参为 0 时对象 `+0x64`（十进制 100）写 3，非 0 写 5；与 case `0x42`（`actSetPlayerMode`，写 player-table 模式并改表现／AI 角色）分开 |
| `0x56` | 第一参为候选数，`0x458c80(count)`（调用点 `0x451787`）选一组 (x,y)，各与 `0xffffffe0` 相与后写全局 `0x4c2968`／`0x4c296c`：低 5 位丢弃，存的点按 32 像素对齐 |
| `0x57` | 找 actor，比较对象 `+0x4`／`+0x8` 与 `0xffffffe0` 相与后的值与两个全局：是对齐像素比较，不是格坐标比较 |
| `0x458c80` | 界为 0 返回 0；否则调 `0x458c10`，界 < `0x10000` 时取低 16 位对界取模，更大时取全值取模 |

## 重制接线

- `game/sim/WinfailActions.gd`：`actSetPlayerExecMode` 在解析出的单位上写 `player_exec_mode` 与原生 3／5 值，记 `exec_mode_changes`；不改 `battle_actor_role` 与 `player_commandable`。
- `actRandomSetSysArrivePos` 在 `winfail_runtime.system_arrival_position` 与 `system_arrival_position_changes` 记对齐后的候选表、选中下标、选中像素、触发序号与全局流 `global_rng`（`GlobalRandomStream`，原版 `0x4795d4`／`0x4795d8`）前后两个字；`actCheckPlayerArriveSysPos` 把单位格坐标按 `cell_size` 换成像素后与同一对齐点比较。
- 边界 id `exec_mode`、`random_sys_arrive_pos` 见 [winfail_claim_limits](winfail_claim_limits.md)。

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`（`_exec_mode_and_system_arrival`）

## 边界

- 原版全局随机序列未重建；抽取前的全局流消费与原版不同，选中哪一组仍是 provisional。
- 执行模式 3／5 的消费者（该字影响哪些对象过程分支）本包未读。

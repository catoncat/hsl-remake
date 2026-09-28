# 脚本玩家安装：普通安装与条件队员

> evidence: static-derived · status: live · functions: 0x407ec0, 0x4080b0, 0x42c700, 0x42caa0, 0x42caf0, 0x42cb30, 0x4348f0, 0x43bf30, 0x44fbd0, 0x45e3ed, 0x46ee10 · tools: hsltools/probes/player_install.py · updated: 2026-09-28

## 结论

- 原版：`defProcPlayerInstall`（`0x4080b0`）以 Data9 为零起始注册槽；Data8 缺省（0）是普通安装，经 `0x42cb30` 启用该槽（空槽设 `800+slot`）后请求构造；Data8=1 是条件安装，只有已存在且启用的槽进入构造器，空槽或禁用槽走占位物删除（static-derived；51 次有界原指令执行）。
- 重制：`game/sim/ScriptActorCreationRules.gd` 与 `game/sim/loop/BattleLoopScript.gd` 按普通安装创建脚本玩家；`game/sim/ConditionalPartyRules.gd` 让随机遭遇里标 `install_if_carried` 的九个槽只上场战役承接中持有的成员（static-derived 规则＋重制组合）。
- 「已注册但禁用」槽在原版不可达：`0x42caa0` 测 `0x80000000`，但注册表唯一写入者 `0x42c700` 只从 `0x42c869`（新游戏槽 0 写 800）、`0x42cb47`（空槽写 800+slot）、`0x43493d`（转职写升级对象码）调用，`0x42cb50` 取低 16 位，`0x42cafa` 只清零；承接名单代替注册启用表不丢原版可达状态（static-derived）。
- 差异：原对象调度与跨关注册表存档格式未复原（provisional）；安装链的抽数顺序（落点替代先于 NPC 出生）与出生张延迟已照原版（[脚本入场包](original_script_entry.md#安装时的随机数消费顺序)），链外其它全局流抽取仍不同。

## 证据

**static-derived**（[original_player_install.json](original_player_install.json)，`hsltools/probes/player_install.py`，匹配固定 SHA 的 EXE；原 PAK 只读，OBJ-002／OBJ-012 记录各带原字节哈希并与关卡 seed 的 OBS 哈希互核）

| 路径 | 行为 | 执行边界 |
| --- | --- | --- |
| `0x4080b0` PlayerInstall | Data9（+0xac）零起始注册槽；Data8（+0xa8）区分普通／条件 | 30 次分派前段，停在构造器 `0x407ec0` 或删除入口 `0x45e3ed` |
| `0x42caa0` | 注册值带 `0x80000000` 为禁用，否则返回对象代码 | 在分派内正常返回 |
| `0x42cb30` | 空槽写 `800+slot`；已有槽取低 16 位（可重新启用禁用记录） | 15 次完整返回，其余 19 槽不变 |
| `0x42c700` | 把对象代码写入注册槽 | 由 `0x42cb30` 实际调用 |
| `0x4080b0` 初始化消息 | 位置 `(pixel & ~31)+16` 对齐；清初始化位、更新形状低字 | 4 次前段，停在 `0x43bf30` 前（含负坐标、非对齐输入） |
| 注册表 `0x4c4360` 全部 9 处引用 | 写：`0x42c70d`（`0x42c700`，调用点 `0x42c869`／`0x42cb47`／`0x43493d`，写入值 800、800+slot、record+0x60 升级对象码）、`0x42cb55`（低 16 位）、`0x42cafa`（清零）、`0x42c867` 新游戏清表、`0x42e9c0` 读档搬 0x54 字节；读：`0x42caa4`、`0x42cb34`、`0x42cac0` 反查、`0x42e3dd` 存档；没有写 `0x80000000` 的指令 | 反汇编逐条读，未执行 |
| `0x45dd2d`、`0x45e0d7` | OBS 记录先由 `0x46ee10` 清 176 字节；缺 Data8／Data9 时读取保留 0 | 2 组前段，停 `0x45dd3d`／`0x45e11b` |

受测路径都不改变两个 RNG 状态字。

**resource-derived**：
- OBJ-002 `obj_Code=7` 緹娜：`defProcPlayerInstall`、`obj_Data9=1`、无 Data8 → 普通安装启用槽 1，请求代码 801。
- OBJ-012 代码 180–188：`obj_Data8=1` 的九个条件安装，Data9 0..8（与原名「有才產生」一致，结论来自字段与执行）。
- STORY002／WINFAIL002 两阶段：初始 001、003 与五名 028；event0 在敌人剩一名时插入緹娜与四名 023、旧 028 离场，启用第二阶段 win0 与緹娜败北条件；`actMEssage` 与 `actMessage` 是同一 token；第二阶段胜利后进 55 营地，无撤离区。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_player_install.md`：`game/sim/ScriptActorCreationRules.gd`、`game/sim/loop/BattleLoopScript.gd`、`game/sim/ConditionalPartyRules.gd`。
- `ActorInitializationRules` 准备来源；`InitialRosterGrowthRules.prepare_player` 只推导新注册玩家的初始等级；`ReinforcementGrowthRules` 从登记队伍取追兵等级基础；`ScriptActorCreationRules` 返回完整提案，PlayLoop 一次提交角色、位置与随机游标；已注册人物不重置生命、物品、装备、成长。
- `ConditionalPartyRules`：不能上场的槽（`conditional_party.unavailable_slots`）由 `blocked_members()` 显式报出；无战役承接的开发启动上场全部槽（remake-invented）。
- 脚本目标格被占或不可站时照原版落点替代 `0x44fbd0` 挪格（[脚本入场包](original_script_entry.md#结论)）。

## 复现

`python3 tools/hsl.py check player_install`（重执行：`--execute <hsl01.exe> --write`）。

## 边界

- 整次对象安装／删除、构造器与 `0x43bf30` 可视初始化未执行。
- 禁用位不可达的结论来自 .text 全部引用的静态阅读；若外部改写存档写入 `0x80000000`，读档会原样恢复，重制不承接这种存档。
- 原对象调度、跨关注册表保存格式、全局 RNG 与墙钟不在本包范围；创建顺序、保存格式与渲染节奏是重制合同。
- 生成后的成长与装备刷新见 [original_priest.md](original_priest.md)、[original_growth_lifecycle.md](original_growth_lifecycle.md)、[original_auto_growth.md](original_auto_growth.md)。

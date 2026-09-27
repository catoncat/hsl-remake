# 原作 actUseItem／actInsertStoryObjectWaitPos／actCheckNextSerialNumber／actSetPlayerNoAttack

> evidence: static-derived · status: live · functions: 0x409e40, 0x44fad0, 0x450390, 0x450840, 0x458c80, 0x45e307 · tools: hsltools/checks/function_catalog.py, hsltools/data/winfail_coverage.py · updated: 2026-09-27

## Token 常量

**resource-derived**：`content/imported/hsl/global/tables/ACTION.H` 定义：

| token | value | arguments |
| --- | ---: | --- |
| actUseItem | 93 (0x5d) | `code` `serial` `item id` |
| actInsertStoryObjectWaitPos | 99 (0x63) | `object code` `position count` `x/y pairs...` |
| actCheckNextSerialNumber | 100 (0x64) | [number] |
| actSetPlayerNoAttack | 101 (0x65) | `player id` `serial` `mode` |

## Static findings

**static-derived**：剧情 VM bridge 是 `0x450840`。

- case `0x5d` (`actUseItem`) 先以 `code` `serial` 经 `0x44fad0` 找到 actor，调用 `0x450390(code, serial, 0)` 建立使用道具的等待阶段，再调用 `0x409e40(actor, item_id)`。道具效果失败时，VM 仍只前进脚本指针；dispatcher 不把 item id 解释成另一个 actor 或目标。
- case `0x63` (`actInsertStoryObjectWaitPos`) 读取 object code、位置数和位置表，经 `0x458c80` 选择一组坐标，调用 `0x45e307(x, y, object_code, 0)` 安装对象，并把脚本返回指针写入对象等待状态。位置表是世界／像素坐标，不是 grid cell。
- case `0x64` (`actCheckNextSerialNumber`) 是交接计数 `0x4c1ad4`（`0x407510` 每次交接加 1）上的定时器：截止字 `0x4c1ad6` 为 0 时写成计数＋参数，计数到截止时成立并清 0。读法与整镜像实测见 [噴人沼氣包](original_poison_gas.md)（2026-09-27 更正：此前读作安装 serial 的容量上限）。
- case `0x65` (`actSetPlayerNoAttack`) 经 `0x44fad0(code, serial)` 找到 player record，在 `PLAYER_TABLE + 0xa0` 清除或设置 bit `0x2`。这是 no-attack 标志，不是 undead bit `0x4`，也不改变 mode。

`0x409e40` 的既有静态 packet 只覆盖永久道具 253..261 的 stat/resistance 分支。item 252 的恢复 HP、MP 和清除状态字段来自 `ITEM.TXT` 的 **resource-derived** 记录；remake 使用已存在的 `ItemResolutionRules.prepare`，因此 252 的 dispatcher 等价性保持 **provisional**，不把 0x409e40 的局部静态范围扩大成整个 item dispatcher。

## Remake boundary

`WinfailScenarioRules` 仍是无状态解释器：

- `actUseItem` 解析唯一 `[SID, serial]` actor，调用同一 `ItemResolutionRules.prepare`，提交到同一 loop dictionary 的 HP/status/inventory 字段，并记录 `item_requests` 与 receipt；不新增 battle state owner。缺 actor、catalog、inventory 或 item 会显式记录拒绝原因。
- `actInsertStoryObjectWaitPos` 记录完整世界坐标表，位置表非空时照 `0x451ecf` 在 loop 的全局流 `global_rng`（`GlobalRandomStream`，原版 `0x4795d4`／`0x4795d8`）抽一次 `rand(count)` 选位置（lane RNG-A 2026-09-25），收据记全局流前后两个字，并记录等待安装请求。它不伪造 playable actor；defProcPoisonGas 对象的喷毒见 [噴人沼氣包](original_poison_gas.md)。
- `actCheckNextSerialNumber` 照交接计数定时器实现（`WinfailConditions`／`WinfailScenarioRules`，[噴人沼氣包](original_poison_gas.md)）。
- `actSetPlayerNoAttack` 写入唯一单位字典的 `no_attack`，并记录变更 receipt。玩家的普通 attack command 和 direct attack resolver 都拒绝该标志；magic/special 与 source-specific AI policy 仍是独立能力。

## Sources and limits

- `content/imported/hsl/global/tables/ACTION.H`、`content/imported/hsl/global/tables/ITEM.TXT`（resource-derived）。
- `hsl01.exe` `0x450840` cases `0x5d`/`0x63`/`0x64`/`0x65`、`0x450390`、`0x44fad0`、`0x45e307`（static-derived）。
- `docs/evidence_packets/static_reverse/original_tactical_items.md`（0x409e40 的既有局部范围）。
- 没有 bounded native execution；安装对象渲染、道具等待时序、packed serial 的完整边界与 no-attack 的所有 AI 分支仍 provisional。

## Replay

`python3 tools/hsl.py check function_catalog`
`PYTHONPATH=tools python3 -m hsltools.data.winfail_coverage --pak $HSL_ORIGINAL_DIR/hsl.pak --check`

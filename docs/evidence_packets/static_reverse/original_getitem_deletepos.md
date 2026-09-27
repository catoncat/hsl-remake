# 原作 actGetItem／actDeletePosObject

> evidence: static-derived · status: live · functions: 0x40e690, 0x42c400, 0x44ef70, 0x44f080, 0x44f100, 0x4506a0, 0x450840, 0x45e3ed · tools: hsltools/checks/function_catalog.py, hsltools/data/winfail_coverage.py · updated: 2026-09-20

**static-derived**（r2ghidra 反编译阅读与 r2 常量定位；原始 EXE sha256 前缀为 f0b5f835，未执行 Wine／VM）。本包只登记两个 ACTION token 的参数形状、分派路径和重制接线边界；不把目录候选或测试通过升级为原版等价。

## Token 常量

表 DATA\ACTION.H 给出：

| token | value | arguments |
| --- | ---: | --- |
| actDeletePosObject | 77 (0x4d) | x, y, range, proc code |
| actGetItem | 85 (0x55) | item id, number |

剧情 VM bridge 是 0x450840。其 0x4d case 调用 0x42c400(x, y, range, proc_code)，命中后调用 0x4506a0(object)。其 0x55 case 拒绝 zero item/count，测试 0x40e690(item)，再按重要物品调用 0x44ef70(item, count)，普通物品调用 0x44f100(item, count)。

## Static findings

- 0x40e690 测试 ITEM record offset +0xa0 的 bit 0x08000000，即 important-item capability bit。
- 0x44ef70 将 item/count 合并到重要 party list 0x4c1d10：已有 code 增量，否则在容量允许时追加 pair。
- 0x44f100 对普通 party list 0x4c1d1c 执行相同合并。
- 0x42c400 通过 object iterator 遍历 live objects，保留 process code 等于参数者；对象绝对 x/y 与请求 x/y 的差分别不超过 range 才命中。精确命中立即返回，否则保留 closest candidate（以较小轴距更新）。
- 0x4506a0 执行 object removal lifecycle：process mode 3 或 5 先走 standing/departure cleanup，再经 0x45e3ed 释放对象。dispatcher 不解析 grid cell 或 unit id。

因此 coordinate hit 是按世界／像素坐标、process code 和方形范围匹配，不是单位删除，也不是 grid-cell equality。exact tie-break 与 object-list iteration order 仍只有 static-derived 证据；重制记录 request，并由既有 world-coordinate map-object mirror 隐藏匹配的表现节点。

## Remake boundary

战斗侧 actGetItem request 由唯一 BattlePlayLoop owner 消费，复用 InventoryRules 的 eight-slot 操作写入 controlled party inventory；CampaignCarryRules.capture 随后携带同一 inventory，不新增 party item store。满包是显式 scenario error，不静默丢弃。

战斗侧 actDeletePosObject 保留在 winfail_runtime，由 BattleSceneRuntime 仅作为 presentation mirror 消费：按 candidate world anchor、requested process code 与 square radius 隐藏匹配 map-object nodes。可变战斗真相仍归 BattlePlayLoop；这是静态合同的 remake implementation，不声称 renderer object list 或 timing 原生等价。

## Sources and limits

- content/imported/hsl/global/tables/ACTION.H（resource-derived token values and argument comments）。
- hsl01.exe 0x450840 cases 0x4d and 0x55，以及 direct callees 0x42c400、0x4506a0、0x40e690、0x44ef70、0x44f100 和 helper 0x44f080（static-derived）。
- 本包没有 bounded native execution。全局 capacity overflow handling、renderer timing 和 script VM re-entry timing 仍 provisional；需要 targeted runtime evidence 才能升级结论。

## Replay

```sh
python3 tools/hsl.py check function_catalog
python3 tools/hsl.py check winfail_coverage
```
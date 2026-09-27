# 原作 actGetItem／actDeletePosObject：发放物品与按坐标删除对象

> evidence: static-derived · status: live · functions: 0x40e690, 0x42c400, 0x44ef70, 0x44f080, 0x44f100, 0x4506a0, 0x450840, 0x45e3ed · tools: hsltools/checks/function_catalog.py, hsltools/data/winfail_coverage.py · updated: 2026-09-27

## 结论

- 原版 `actGetItem` 按重要物品位分流到重要／普通两个 party 列表合并；`actDeletePosObject` 按世界像素坐标、process code 与方形范围找对象并走对象移除流程——是对象请求，不是单位删除、也不是格相等（static-derived，r2ghidra 阅读，未执行）。
- 重制由 `BattlePlayLoop` 消费 actGetItem，经 `InventoryRules` 八格写入受控队伍背包；actDeletePosObject 留在 `winfail_runtime`，由 `BattleSceneRuntime` 只作表现镜像隐藏匹配的地图物件节点（static-derived 输入）。
- 差异：容量溢出、渲染时序、VM 重入时序未读（provisional）。

## 证据

### resource-derived

`DATA\ACTION.H`：actDeletePosObject = 77（0x4d），`x, y, range, proc code`；actGetItem = 85（0x55），`item id, number`。

### static-derived（EXE sha256 前缀 f0b5f835）

| 地址 | 原版 |
| --- | --- |
| `0x450840` case 0x4d | 调 `0x42c400(x, y, range, proc_code)`，命中后调 `0x4506a0(object)` |
| `0x450840` case 0x55 | 拒绝 item／count 为 0；测 `0x40e690(item)`，重要物品调 `0x44ef70(item, count)`，普通物品调 `0x44f100(item, count)` |
| `0x40e690` | ITEM record `+0xa0` 的 bit `0x08000000`（重要物品位） |
| `0x44ef70` | 合并到重要 party 列表 `0x4c1d10`：已有 code 增量，否则容量允许时追加一对 |
| `0x44f100` | 对普通 party 列表 `0x4c1d1c` 做同样合并（辅助 `0x44f080`） |
| `0x42c400` | 经对象迭代器遍历活对象，保留 process code 相等者；绝对 x／y 与请求差都不超过 range 才命中；精确命中立即返回，否则保留较小轴距的最近候选 |
| `0x4506a0` | 对象移除：process mode 3 或 5 先走站立／离场清理，再经 `0x45e3ed` 释放；不解析格或 unit id |

## 重制接线

- actGetItem：唯一 `BattlePlayLoop` owner 消费请求，复用 `InventoryRules` 的八格操作写受控队伍背包；`CampaignCarryRules.capture` 随后携带同一背包；满包是显式 scenario error，不静默丢弃。
- actDeletePosObject：记在 `winfail_runtime`，`BattleSceneRuntime` 按候选世界锚点、process code 与方形半径隐藏匹配的地图物件节点；可变战斗真相仍归 `BattlePlayLoop`。

## 复现

`python3 tools/hsl.py check function_catalog winfail_coverage`

## 边界

- 最近候选的精确平局规则与对象列表遍历次序只有静态证据。
- 全局容量溢出处理、渲染时序与脚本 VM 重入时序未读；没有有界原生执行。

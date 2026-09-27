# 剧情走位：逐格路径、Wait 与并行

> evidence: static-derived; provisional: 同距平局次序、围死时的最近格度量、按键快进（remake-invented） · status: live · functions: 0x40eb40, 0x40ed50, 0x40f350, 0x40f440, 0x410a50, 0x411080, 0x4111d0, 0x450840, 0x453b90 · tools: run_story_object_terrain_tests.gd · updated: 2026-09-27

## 结论

- 原版：剧情走位 token 经 `0x4111d0 → 0x411080`（`0x40f350` 洪泛，唯一差别是放开地图像素边界）按四邻逐格绕开墙、悬崖、0x4000 硬阻挡与高差；非 Wait 变体写完目的格即放行 VM，与后续 token 并行，只有 Wait 变体在走完时放行 VM（static-derived，反汇编与反编译读法）。
- 重制：`game/battle/runtime/opening/ScriptWalkPath.gd` 在场景地形上四邻 BFS 求路、逐格走；`BattleOpeningCoordinator` 默认不阻塞，只有 Wait 变体经 `_block_on(unit_id)` 等自己的走位者；token 速度参数照传（static-derived 结构；199 场景盘点 1375 条可定位走位全部只进可通行格）。
- 差异：同距平局次序、洪泛半径 18 的分段续算、围死时的最近格度量是重制组合；按键快进是 remake-invented（provisional，差异清单 `script-walk-path`／`script-fast-forward`）。

## 证据

**static-derived**（`hsl01.exe` 反汇编与反编译）

| 地址 | 读法 |
| --- | --- |
| `0x450840` case 2..7 → `0x44fcf0`／`0x44fd90` | actWalk*／actWalkDisp* 写目的格心到 +0x4a/+0x48、速度到 +0x98；Wait 变体另把 VM 指针写进 +0x50，VM 停在该 token；非 Wait 变体立即执行下一条（[剧情镜头读法](original_script_camera_scroll.md)） |
| `0x453b90` 状态 0x32 sub 0 | （Wait 变体先居中镜头）调 `0x4111d0(actor, dest_x, dest_y, 0x12, 0xc)`；返回 0 → sub 7 不移动；否则复制全局路径缓冲 `0x4c63c0`（0x65 dword） |
| `0x453b90` sub 3／6 | 每 tick 按方向码（1 上、2 下、3 左、4 右）移动 `步长` 像素，每 `0x20/步长` tick 取下一格；缓冲走完未到目的格再调 `0x4111d0` 续算，失败则停在当前格 |
| `0x453b90` sub 7 | 清状态；+0x50 非零时 VM `+0x8c` 加一（只放行 Wait 变体） |
| 状态 0x36 actWalkAndDelete* | 走路同 0x32；sub 7／8 置 16 tick 后注销（同 [离场包](original_script_departure.md)） |
| `0x4111d0 → 0x411080(…, param_6=1)` | 半径 `max(0x12, 0xc)` 洪泛，`param_6=1` 选 `0x40f350`；不可达时 `0x413900` 取曼哈顿最近格、半径 −2 重试；`0x410a50` 生成路径 |
| `0x40f350`／`0x40f440` | 只差 `*0x4c1a74` = 1／0 |
| `0x40ed50` | `*0x4c1a74≠0` 跳过地图像素范围检查；其余不变：`0x40eb40` 读格字，高差 >2 停（飞行模式 6 除外），格字 `& mask` 且无可穿越对象时停 |
| `0x40eb40` | 地图外返回「当前高度 << 24」且无旗标：可走出地图边 |

**resource-derived**：WINFAIL006 win_0 撤退为九条 `actWalkAndDelete`（间隔 `actDelay,2`）加一条 `actWalkAndDeleteWait`，十名士兵几乎同时出发；STORY006、WINFAIL006 event_1 入场为 `actWalkPrevInsertObject`（非 Wait）＋`actDelay,30`，30 tick 错开同时走；WINFAIL006 撤退 speed 8。

**重制盘点**（`run_story_object_terrain_tests.gd`，199 个场景的开场时间线与全部 winfail 链）：

```
SCRIPT_WALK_ROUTES scenarios=199 walks=1817 routed=1375 straight_crossed=167 nearest_reachable=17 unresolved_start=442
```

167 条是旧直线会穿过不可通行格的走位；17 条目标被围死（多为脚本终点落在悬崖格），逐条打印 `SCRIPT_WALK_WALLED_OFF`；442 条起点无法静态确定，运行时仍走同一路径函数。第 6 关撤退由逐个出发（18.5 s）变为 10 人同走（2.7 s）。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_script_walk_path.md`：`game/battle/runtime/opening/ScriptWalkPath.gd`、`game/battle/runtime/opening/OpeningStoryObjects.gd`、`game/battle/runtime/BattleOpeningCoordinator.gd`。
- `ScriptWalkPath.route`：战斗读 PlayLoop tiles，剧情场景读关卡 WRD；起讫点在图外时才把外圈一格纳入搜索；围死时停在最近可达格；不读单位占用（剧情走位是已提交结果的表现）。
- `BattleScriptActorPresentation` 取 `actWalk*` 第 5 参／`actWalkPrevInsertObject*` 第 3 参为速度。
- 按键快进（remake-invented）：对白以外 token 期间 Enter／Space／左键让走位落到终点、镜头落位、当前等待缩到一 tick，脚本次序与落点不变。

## 复现

`tools/godot.sh --headless --script res://tests/run_story_object_terrain_tests.gd`（输出上面的 `SCRIPT_WALK_ROUTES` 行）。

## 边界

- 同距路径平局次序（重制 BFS 上／下／左／右）、洪泛半径 18 的分段续算、围死时的最近格度量：替换证据是对 `0x411080`／`0x410a50` 的有界执行逐格对照。
- 洪泛缓冲 `*0x4c1a64`／`*0x4c1a68` 的具体尺寸（地图外能走多远）未读；
- 不声明原版逐格路线与重制完全一致，只声明「按地形逐格、不穿墙」与「非 Wait 并行」两条结构。

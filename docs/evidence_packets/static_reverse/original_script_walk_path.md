# 剧情走位：逐格路径、Wait 与并行

> evidence: static-derived; provisional: 同距平局次序、围死时的最近格度量、按键快进（remake-invented） · status: live · functions: 0x40eb40, 0x40ed50, 0x40f350, 0x40f440, 0x410a50, 0x411080, 0x4111d0, 0x450840, 0x453b90 · tools: run_script_walk_path_tests.gd, run_script_walk_tests.gd · updated: 2026-09-24

2026-09-24，lane R5-L4。用户实玩第 6 关：队长倒下后"每个小兵撤退的路线都是错的，直接穿过阶梯走掉……为什么是一个一个轮流撤退？"本包回答两件事：原版剧情走位是否按地形走、是否顺序。全部为只读反编译（`hsl01.exe`，r2ghidra 目录 `ignored/static/hsl01/catalog/decompiled`）与 r2 反汇编，未开原作。

## 原版读法（static-derived）

| 地址 | 读法 |
| --- | --- |
| `0x450840` case 2..7 → `0x44fcf0`／`0x44fd90` | actWalk*／actWalkDisp* 只把目的格心写进对象 `+0x4a/+0x48`、速度 `+0x98`；**Wait 变体**另把 VM 指针写进对象 `+0x50`，VM 停在这条 token 上；非 Wait 变体 VM 立刻执行下一条 token（[剧情镜头读法](original_script_camera_scroll.md)） |
| `0x453b90` 状态 0x32 sub 0 | （Wait 变体先居中镜头）然后 `0x4111d0(actor, dest_x, dest_y, 0x12, 0xc)`；返回 0 → sub 7（走位结束、不移动）；否则把全局路径缓冲 `0x4c63c0`（0x65 个 dword）复制给演员 |
| `0x453b90` sub 3／6 | 每 tick 按缓冲里的方向码（1 上、2 下、3 左、4 右）移动演员 `步长` 像素，每 `0x20/步长` tick 取下一格；方向码 0（缓冲走完）时若未到目的格再调一次 `0x4111d0` 续算，续算失败就在当前格结束 |
| `0x453b90` sub 7 | 清状态；`+0x50` 非零时把 VM 的 `+0x8c` 加一——只有 Wait 变体的 VM 在这里被放行 |
| 状态 0x36（actWalkAndDelete*） | sub 0..6 同 0x32 的走路；sub 7／8 置 16 tick 计时后注销对象（与[离场包](original_script_departure.md)的 16 tick 相同） |
| `0x4111d0` → `0x411080(…, param_6 = 1)` | 以 `max(0x12, 0xc)` 为半径洪泛，`param_6 = 1` 选 `0x40f350`（普通 AI 选 `0x40f440`）；到不了就用 `0x413900` 取洪泛内离目标曼哈顿最近的格、半径减 2 重试；最后 `0x410a50` 生成路径 |
| `0x40f350` 与 `0x40f440` | 两者只差一行：`0x40f350` 置 `*0x4c1a74 = 1`，`0x40f440` 置 0 |
| `0x40ed50` | `*0x4c1a74 != 0` 时跳过「格在地图像素范围内」的检查（仍受洪泛缓冲尺寸限制）；其余地形规则不变：`0x40eb40` 读格字，高度差 > 2 停（飞行模式 6 除外），格字 `& mask`（地面模式含 0x4000）且格上没有可穿越对象时停 |
| `0x40eb40` | 地图外的格返回「当前高度 << 24」且无旗标——剧情走位可以走出地图边（入场／撤出），地图外不挡路 |

结论：**原版剧情走位按四邻逐格路径绕开墙、悬崖、0x4000 硬阻挡与高差，不是直线滑过去；非 Wait 走位与后续 token 并行，只有 Wait 变体等自己这名走位者。** WINFAIL006 win_0 的撤退是九条 `actWalkAndDelete`（间隔 `actDelay,2`）加最后一条 `actWalkAndDeleteWait`，原版十名士兵几乎同时出发；入场（STORY006、WINFAIL006 event_1）是 `actWalkPrevInsertObject`（非 Wait）＋ `actDelay,30`，按 30 tick 错开同时走。

## 重制的根因与修复

- **顺序播放**：`BattleOpeningCoordinator._apply_event` 把每条 token 的 `_blocking_motion` 默认设为 true，只有非 Wait 走位自己改成 false；于是走位后面的 `actDelay` 也要等**所有**演员停下，十名士兵变成一个接一个（修复前第 6 关撤退一次只有 1 人在走，共 18.5 s；修复后 10 人同走，2.7 s——`run_script_walk_tests.gd` 的 `SCRIPT_WALK_RETREAT` 行）。现在默认不等，只有 Wait 变体（及 actWaitPlayer）经 `_block_on(unit_id)` 等**自己的**走位者。
- **直线穿墙**：`OpeningStoryObjects._move_actor` 以两点 tween 直线移动。现在经 `ScriptWalkPath.route` 在场景地形（战斗读 PlayLoop 的 tiles，剧情场景读关卡 WRD）上按四邻 BFS 求路，演员逐格走，时长按实走长度；起点或终点在地图外时才把地图外一圈纳入搜索（入场／撤出）；目标被围死时停在离目标最近的可达格（对应原版续算失败即停）。单位占用不读——剧情走位只是已提交 PlayLoop 结果的表现，沿用「剧情离场忽略角色占用、遵守地形」的既有合同。
- **撤退速度**：`BattleScriptActorPresentation` 此前不传 token 的速度参数，WINFAIL006 的 speed 8 被当成默认 4；现在按 token 形状取 `actWalk*` 第 5 参／`actWalkPrevInsertObject*` 第 3 参。
- **按键快进（remake-invented）**：对白以外的 token 期间按 Enter／Space／左键，所有正在走的演员落到本次走位的终点、镜头滚动落位、当前等待缩到一 tick；脚本次序与落点不变。原版这里没有跳过。

## 全游戏盘点（`run_script_walk_path_tests.gd`）

对 199 个注册场景的开场时间线与全部 winfail 状态链，按静态已知位置（EVEF／绑定像素、插入像素、上一段走位终点）重放每条走位 token：

```
SCRIPT_WALK_ROUTES scenarios=199 walks=1817 routed=1375 straight_crossed=167 nearest_reachable=17 unresolved_start=442
```

- 1375 条可静态定位起点的走位全部逐格、只进可通行格（检查覆盖全部）。
- 167 条旧直线穿过不可通行格——这些就是本次修复改变的走位（消融：把 `route` 改回直线，场景套件的「grid path／不踩不可通行格」断言失败）。
- 17 条目标被围死（多为「(有才產生)」雷特、嚎等脚本终点本身落在悬崖格，战斗里首控时再落到 PlayLoop 的最近空格，是既有 provisional 站位边界），逐条打印为 `SCRIPT_WALK_WALLED_OFF`。
- 442 条起点无法静态确定（绑定不到 EVEF 像素的单位、跟随走位），运行时仍走同一路径函数，只是不进本盘点。

## 边界

- 同距路径的平局次序（重制 BFS 上／下／左／右）、洪泛半径 18 的分段续算细节、围死时的最近格度量：provisional；替换证据是对 `0x411080`／`0x410a50` 做有界执行对照逐格缓冲。
- 洪泛缓冲 `*0x4c1a64`／`*0x4c1a68` 的具体尺寸（地图外能走多远）未读；重制只在起讫点在图外时放开外圈一格。
- 本包不声明原版逐格路线与重制完全一致，只声明「按地形逐格、不穿墙」与「非 Wait 并行」两条结构。

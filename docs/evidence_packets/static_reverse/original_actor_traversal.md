# 通行：单格角色的地形高度、同侧经过与合法停留

> evidence: static-derived · status: live · functions: 0x40bab0, 0x40ed50, 0x40f200, 0x40f440, 0x446ad0, 0x446b30 · tools: hsl_wrd_decode.py, hsltools/data/terrain_heights.py, hsltools/probes/traversal.py · updated: 2026-09-27

## 结论

- 原版地面移动四邻扩展：按阵营 mask 阻挡，同侧可经过，高差绝对值 ≥3 禁入、上坡 1／2 加费 1／2；飞行（mode6）只受 `0x4000` 限制、不读高差；落点另查占格与 `0x100000`，可经过的格不一定能停；起点格本身不受检查，但其高度参与第一步高差，故站在 0xff 格的地面单位走不下悬崖（static-derived）。
- 重制 `game/sim/ActorTraversalRules.gd` 读源能力，`game/sim/TacticalGridRules.gd` 返回可停格、transit 格与每条路径累计代价，玩家与 AI 共用同一查询；地形高度由原 WRD 高字节重建（static-derived）。
- 一致：80 份单格原返回与重制洪泛逐格相同；全图最短路径与平分顺序是重制组合，未证与原递归缓存／搜索顺序一致（provisional）。大型角色见 [original_large_actor.md](original_large_actor.md)。

## 证据

**static-derived**（`hsltools/probes/traversal.py` 执行 SHA 锁定 EXE，结果 [original_actor_traversal.json](original_actor_traversal.json)；未替换或 stub 被调函数；输入角色与地图是合成夹具）

| 入口 | 结果 | 范围 |
| --- | --- | --- |
| `0x40bab0`／`0x446ad0`／`0x446b30` | 28 组 × 3 次完整返回 | 阵营地面模式、飞行 bit1、不阻挡 bit `0x10` 查询；不修改角色 |
| `0x40f440`→`0x40f200`→`0x40ed50` | 92 次完整返回 | mode 2/3/6/7、四邻覆盖、对象邻接代价、高差、飞行与不阻挡例外、起点 0xff；逐格余量对照独立模型 |
| `0x443c6f` 玩家落点前段 | 28 次有界前段 | 停在 `0x443cba`（检查对象）、`0x443d4e`（后续可达检查前）或 `0x443d9d`（取消）；不执行移动、UI 或完整玩家 dispatcher |

另存玩家 Move、AI 施法选点、PLAYERS 字段 loader 与落点的 10 段字节锚点。

| 规则 | 读法 |
| --- | --- |
| 地面模式 | side bit：player 2、enemy 3、NPC 7；阻挡 mask `0x64000`／`0x54000`／`0x34000`。重制把 friendly_ai 与 player_controlled 映射到同侧 |
| 飞行 | mode6，mask 仅 `0x4000`，忽略高度与对象邻接附加费；不允许停在普通角色身上 |
| 高差 | 高字节差绝对值 ≥3 禁入；上坡 1／2 加 1／2，下坡不加；起始高度 128 分支：目标 255 差 16，否则 0 |
| 邻接附加费 | 初始格不收；后续格除来路外邻接 masked 对象加 1；保留来路方向，单一 parent 不足以表示成本状态 |
| 落点 | 普通占格进入检查角色而非移动；no_block 对象可通过；无占格但有 `0x100000` 的格可经过不可停；AI `path_stops` 按此截取 |

<a id="起点在0xff格lane-r5-l4c2026-09-25"></a>

### 起点在0xff格

原版安装不查地形（[actor_placement_initialization.md](actor_placement_initialization.md#install-has-no-terrain-test)），第 6 关 061_1、552 咕嚕、574 actor032_3、903 actor031_8 开场站在 0xff 格。

| 地址 | 行为 |
| --- | --- |
| `0x40f29e` | 起点格直接写 `budget+1`，此前无地形或旗标判定 |
| `0x40f2a1`／`0x40f2ae` | `0x40eb40` 读起点格字，`>> 24` 取起点高度；地图外改 `0x80`（`0x40f2cd`） |
| `0x40f2d5..0x40f33b` | 该高度作为来路高度传给四次 `0x40ed50` |
| `0x40ee0c` | `目标高度 − 来路高度` 存 `0x4c6558`；下坡且差 < 3 时上坡费 `0x4c6d48` 置 0 |
| `0x40ef6b..0x40ef78` | 地面模式取绝对值，≥3 拒绝；飞行 mode6 走 `0x40eebd`，不读高差 |

原指令 12 组（flood 末尾）：起点 (3,3)=0xff，mode 2/3/6/7 × 三种地形——四周全 0：地面可达 0 格、飞行 36 格；第 3 行整行 0xff：地面沿行可达 6 格；四邻 253／254／252：地面只进 253、254。与独立模型逐格一致。

**resource-derived**

- PLAYERS `move_fly`、`no_block`、`size_type` 经原 loader 字节定位；正式 001／021／023／024／025／026 为地面、会阻挡、单格；源 006 飞行、101 不阻挡、017 大体型只登记记录。
- 旧 WRD 包的 b 只表示高字节 = 255；`hsl_wrd_decode.py` v2 保留 `h`，`terrain_heights.py` 从原 PAK 重取 051／052，离线由 header、tile id、h 重建完整源字节并对照原 SHA 与长度。
- 第 6 关 WINFAIL552：胜利为敌全灭、失败为雷歐納德阵亡，不依赖咕嚕移动。

## 重制接线

- `game/sim/ActorTraversalRules.gd`：只读源能力／当前角色与地形。
- `game/sim/TacticalGridRules.gd`：`movement_reachability_envelope` 起点来路高度取 `heights[start]`；返回可停格、transit 格、累计代价与可停标记；玩家确认、AI 进攻／支援／物品／续追共用。
- `game/sim/MobilityRules.gd`：换装与升级重算唯一 move_point；traversal 是源固有能力，不作装备叠加缓存；存档校验其与源声明一致。
- 运行时拒绝旧格式、缺失或不一致的高度与错误网格，PlayLoop 拒绝初始化。
- 路径线、费用文字、飞行标签是重制可读性选择；空间参考见 [录像参考 V02](../runtime_observations/original_gameplay_reference/README.md)。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_actor_traversal.md`。

## 复现

`python3 tools/hsl.py check traversal`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [actor_traversal](../runtime_observations/actor_traversal/receipt.json) | ally_attack、ally_cast、ally_support、restore、flying、ai_cutoff、ai_cast、ai_support、ai_no_mp、ai_silence、victory、defeat、escape | `run_actor_traversal_tests.gd`；截图驱动已退役，回执为历史记录 |

`tests/run_actor_traversal_tests.gd` 的 `blocked_start_cases` 核对第 6 关四名单位只在各自 0xff 格群移动（061_1 23 格、咕嚕 10 格、actor032_3 13 格、actor031_8 3 格）。

## 边界

- 全图最短路径平分顺序与原递归缓存未对拍（provisional）。
- 原版 AI 是否为悬崖上的目标另选接近格未读；重制 AI 读同一洪泛。
- 第 6 关四名 0xff 单位第 1 回合后的实机位置未观察（可看 061_1 是否留在 (25,15) 附近）。
- 特殊地图 flags 的生成与生命周期、飞行动作美术不在本包。
- 本包只证单格；大型 size_type1 的空间合同见 [original_large_actor.md](original_large_actor.md)。

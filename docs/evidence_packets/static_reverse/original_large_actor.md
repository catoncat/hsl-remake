# 大型角色：3×3 占地、四邻整块通行与单一目标身份

> evidence: static-derived · status: live · functions: 0x407800, 0x409090, 0x40ecc0, 0x40ed50, 0x40f200, 0x40f440, 0x4104d0, 0x411940, 0x411990, 0x411ae0, 0x411b90, 0x448840, 0x46dd50, 0x46de70 · tools: hsltools/data/large_actor.py, hsltools/probes/large_actor.py, run_large_actor_tests.gd · updated: 2026-09-27

## 结论

- 原版 `size_type` 非零的对象以格中心为锚占周围 3×3 九格，但仍是一个对象、一个 HP、一个队列身份；地面整块扩展只走上下左右四邻，不借友军／no_block 例外挤过窄缝；武器范围索引 +17 夹到 20；区域命中同一大对象只返回一次（static-derived）。
- 重制 `game/sim/FootprintRules.gd`（几何）、`game/sim/ActorTraversalRules.gd`（占用／通行上下文）、`game/sim/TacticalGridRules.gd`（可停／仅通行目的格、费用、路径）供玩家与 AI 共用；原 039 海輝魔只在开发场景 `LargeActorTrial` 可玩（static-derived）。
- 一致：54 次命中查询、56 次完整 flood、8 次刷新等正常返回与重制合同相符；全图最短路径的等价择一是重制组合，不等同原递归缓存访问次序（provisional）。旧单格包曾写的“大型八方向扩展”是误读，已由 flood 更正。

## 证据

**static-derived**（SHA 锁定 EXE，合成地图／对象表，不替换指令、不 stub；[original_large_actor.json](original_large_actor.json)；主空间锚点拼接 SHA-256 `93af4ac92f6384742952f664de6413c1b8003ea5aecc4095c997248cb433c848`，十二段 AI loader 字节拼接 `2ed055ef5675211d8c0159bd49cd892adc80c0a7ac2bd27b4243650f7648f65f`）

| 范围 | 执行 | 读法与边界 |
| --- | --- | --- |
| `0x407800` 位置命中 | 54 次正常返回 | 单格／3×3、中心／边缘／外侧；重叠时普通阻挡对象优先，最后一个 no_block 为后备；本函数无死亡 HP 检查 |
| `0x411ae0`／`0x411b90` | 6 组写入与清除 | 经 `0x411940`／`0x411990` 更新整块占格；地图边界裁剪，保留无关位 |
| `0x40f440 → 0x40f200 → 0x40ed50`／`0x40ecc0` | 56 次完整 flood | 阵营／飞行、普通／不阻挡占用、整块障碍、上下坡与边缘；逐格覆盖／剩余预算对照独立模型；wrapper 只清自己的外围占用标记。`0x40ecc0` 检查周围九格，不允许对角移动 |
| `0x4104d0` | 3 组枚举至返回零 | 输入为已生成区域 mask；多格命中同一大对象只返回一次 |
| `0x448840`，039／job94 | 4 组 × 2 次，8 次完整返回 | 一级、升级、属性变化、装备后重刷 |
| `0x44c93a` 等六段 AI 字段 loader | 12 次有界前段 | 两种脏初值，真实调用 `0x46de70 → 0x46dd50` 缺字段路径：调用者先清零、未找到最终写零 |
| `0x409090` 大型武器范围 | 原字节 | 索引 +17 夹到 20：普通一格武器读索引 18 `range2CellFull`，范围饰品到 19，20 封顶（getter 样例见 [original_position_equipment.md](original_position_equipment.md)） |

空间规则：
- 地面整块检查 `0x74000` 占用／硬障碍与高度 255；飞行整块可经普通占用，但覆盖值带 `0x80` 的目的锚不能停，整块硬障碍拒绝。源锚须在图内，外围格按原地图查询裁剪。
- 法术施放范围仍以施法者锚点与原法术矩阵计算，不因体型扩大；目标身体边缘可被施放与效果范围命中。

**resource-derived**
- [039 模板](../../../content/generated/hsl/actors/039.json)：PLAYERS 海輝魔、`jobBeastWarrior=94`、`classBeast`、武器 40 觸手、移动 4；`kill_exp=300`、金币 600。缺失的 `ai_att_magic`、`ai_att_special`、三种友军支持概率与 `ai_magic_multi_first` 取 loader 零值。
- 30 张地图站立／四向行走帧、5 张交锋姿势、头像与行走／攻击／死亡声；TYPE／RESOURCE 关联“海輝魔／獸族”。`SHAPE\I_CLAW.SHP` 为 36 字节、0×0 的原空图，SHA-256 `50ffd4edfc78024d3da5fd92de322915e3bf46204bc9692e6dea0146354c8ce0`。
- `resource.h` 六种通常武器命中音效中没有 claw 别名。

## 重制接线

- `game/sim/FootprintRules.gd`、`ActorTraversalRules.gd`、`TacticalGridRules.gd`：玩家确认／撤销、AI 攻法援物选点与执行前复核共用；只接入 `size_type` 0／1。provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_large_actor.md`。
- 技能区域先枚举效果格再按角色身份去重；点身体边缘保留点击中心，空格中心保持空格；一次支付、每目标一次效果／贡献、动作末一次 EXP 汇总；死亡同时释放九格。
- `game/battle/runtime/ActorRuntime.gd`：一个角色按原锚点移动，镜头／遮挡／音效不复制九份；移动预览显示路径、花费与 3×3 落点（边框为 provisional）。
- 初始化、增援与存档先验证身体与源声明再查位置；重叠占格拒绝保存；恢复不重授能力、不补扣毒伤、不重发经验。
- 觸手攻击用角色声明的 ATTACK08 一次（provisional：声音编排）；面板保留“觸手”文字、记为 empty 资源。
- `tools/hsltools/data/large_actor.py` 生成 039 数据；开发场景 `game/battle/development/LargeActorTrial.tscn`（[content/battles/large_actor_trial.json](../../../content/battles/large_actor_trial.json)，原 051 地图，Leonard 与可控海輝魔）；一级／零 EXP 为开发模板策略，正式编队不含大型角色。

## 复现

`python3 tools/hsl.py check large_actor`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| `large_actor/`（目录已删，见 Git 历史） | trial、movement、edge_series、giant_combat、empty_area、support、cure_item、skip_resume、ai_resource、ai_retarget、victory、defeat、escape | `run_large_actor_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- `0x4104d0` 只证枚举，完整区域生成／传播未重新执行。
- AI loader 12 次是前段，不是完整 PLAYERS loader 返回。
- 合成一级 039 不是原现场 NPC 等级；现场等级见 [original_auto_growth.md](original_auto_growth.md)。
- 全部道具 dispatcher、全图 flags 生命周期、全局 RNG、未知职业／形态与精确演出时钟未读。
- 身体边缘道具／给予的最近格邻接、停止标记在 footprint 上的适配、AI 候选平分选择是重制组合。
- 任意自定义长宽不支持。

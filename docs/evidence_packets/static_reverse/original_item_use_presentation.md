# 用药演出：AI 引导、Show_Magic_Star 效果、目标小条与数字

> evidence: static-derived; resource-derived; provisional: 0x401390 发射器（气力／永久／临时加成三类效果的画面）未读，重制只按它们的等待时长；0x43b3f0 小条的 cur/max 文字（位 0x100，0x411d70）未画；AI 引导的射程格按"自身格＋四邻无敌对占位"近似 0x40f440 模式4 泛洪；小条 y 上限的 [0x4c094c] 按地图高 · status: live · functions: 0x408b20, 0x408df0, 0x409e40, 0x43b3f0, 0x43b4c0, 0x440132, 0x440176, 0x4401c7, 0x440211, 0x4402ed, 0x440391, 0x440437, 0x4449a7, 0x444ab2, 0x444ac9, 0x444be4, 0x45e575, 0x45eb9d, 0x45ebdc · updated: 2026-09-27

## 结论

- 原版 AI 用药有引导段：先画移动色射程 12 tick，光标从用药者滑到目标，目标亮起 12 tick，再出姿势、`0x409e40` 生效；玩家用药没有引导段，其余共用（static-derived）。
- 玩家选用药目标是地图选格（`0x444be4` 开选格，`0x44492a..0x4449b6` 取格），不是窗口；确认直接进 0x69 `0x4449a7` 姿势，目标框原地消失，没有收窗滑出。重制确认用药时不让物品面板的收窗快照（`BattlePanelMotion`）把目标框和悬停小条滑出屏幕（static-derived）。
- `0x409e40` 有效果就放 402 sfxUseItem，按固定顺序生成 Show_Magic_Star 等效果对象，第一个生成的带等待；随后挂目标 HP／MP 小条、浮绿／蓝数字，最后一个数字放行后撤条（static-derived）。
- 重制：`game/battle/scene/BattleItemUsePresentation.gd` 按同一序列播放用药回执，AI 引导经 `BattleAttackCue.begin_item`（static-derived）。
- 差异：case 5／6／7 的 `0x401390` 发射器画面与小条 cur/max 文字未做，射程格为近似；无原字形的说明行用白字 Label（差异清单 `ai-item-use-presentation`、`floater-extra-words`；provisional）。

## 证据

**static-derived**（r2 静态读 `hsl01.exe`，SHA-256 `f0b5f835…70f7`；对象定义读 PAK `obj-051.obs`；`PROCESS.DEF defProcShowMagicStar = 27` → 过程表 `0x477c2c` 第 27 项 `0x408df0`。原版录屏参考里没有 AI 用药段）

AI 对象过程按 +0x8e 高字分派（`0x43f4cf`，字节表 `0x4421f4` → 指针表 `0x4421b4`）：高字 `0xc`（自救／友军回复的 `0xc0000`、`0xe0000`）走 `0x440132`，再按 +0x8c 低字经 `0x4422a0` → `0x44227c` 分派；低字 1–6 与攻击共用 `0x440b2c`（镜头、移动）。

| 低字 | 入口 | 行为 | tick |
| --- | --- | --- | --- |
| 7 | `0x440176` | `0x40f440(user, 体型 1／2, 0x40bab0(user))` 标射程；[+0x94] = 12；光标 `(0x4c2c90, 0x4c2c8c)` = 用药者 (x − 16, y − 16) | 1（不画） |
| 8 | `0x4401c7` | 每 tick `0x411200(user, 0)` 画射程（移动色，见 [original_range_cells.md](original_range_cells.md)）＋ `0x430230` 光标；数到 0 进 9 并重置 12 | 12 |
| 9 | `0x440211` | 仍画射程；`0x440233` 起与攻击共用光标滑行（`0x45e882`，步长 max(2, min(16, 距离>>3))），镜头随光标 `0x42dc50`；到达 `0x440272` 写 `0x4c1ce8 = user`、`0x430020(target)`、[+0x94] = 12 | 滑行 tick 数 |
| 10 | `0x4402ed` | `target+0x80 |= edi`（与攻击目标停留 `0x441449` 同一标志）；数完后 +0x8c += 2、`0x40c1d0` 取药、`0x436e80` 出包、`0x4071e0` 姿势、`0x409e40(target, code, user, 0)`；非零返回则 +0x8c −= 1 进 11 | 12 |
| 11 | `0x4420ba` 直接返回 | 等效果对象删除时 +0x8c 加一 | — |
| 12 | `0x440391` | `0x43b3f0(target)` 挂小条；HP 写了（`0x4c1a44 ≥ 0`）在 (x, y − 0x30) 生 kind 2 绿数字，MP 写了再生 kind 3 蓝数字 hold 40；最后一个数字带等待引用，成功则进 13 等待；都没写直接进 14 | — |
| 14 | `0x440437` | `0x43b4c0` 撤小条，跳 `0x441eb8` 结束行动 | 1 |

解状态药（`0x100000` 路径）走 `0x440441` 起同型一段，取药换 `0x40c230`（`0x4404c7` 姿势、`0x4404d6` 用药）。原地自救（`0x4406d7`）同样进 7，光标一 tick 到达。玩家确认用药：状态 0x69 `0x4449a7` 姿势 → 0x6a `0x444ab2` 调 `0x409e40` → 108 `0x444ac9` 调 `0x43b3f0` 与数字 → 0x75 等数字放行。

`0x409e40` 的效果：`0x409e98` 效果点 = 目标 (x, y − 0x34)，大体型（`0x446ad0`）再减 16（`0x409eb6`）。`0x40a1b9..0x40a2c8` 按 HP 加值、MP 加值、气力 +0xe8（上限 60）、永久能力（`0x448840` 刷新）、临时加成、状态解除位计效果数 edi，非零在 `0x40a349` 放 402 sfxUseItem（`WAV\MHEAL001.WAV`）；满值照样有加值字段，满血喝药也放音。调用顺序 `0x408b20(x, y, case, 等待对象, 延迟)`：解状态 2 → 临时加成 7 → 永久 6 → 气力 5 → MP 1 → HP 0；第 i 个（共 n 个）延迟 `(n − 1 − i) × 25` tick，第一个生成的带等待对象（`0x40a3c0` 压 esi）。

对象 176 `Show_Magic_Star`（planeMenu2，`MAGIC\WAT04_01.SHP` 4 张）：

| case | 生成（`0x408b20`） | 过程（`0x408df0`） |
| --- | --- | --- |
| 0 回血／1 回魔 | `0x408d48`：16 个对象；方向 `rand(48)`，奇数个取 `128 − 它`（256 步圆，64 = 正下）；`0x45eb9d(方向, 0x20000)` 初速 2 px／tick；+0xa8 首个 = 延迟，之后累加 `1 + rand(3)`；最后一个带等待对象 | 延迟到时初始化 `[esi] = 0x4000000`（加色）、层级 16、+0x7c = 0x50005、+0x78 = 0x40004；case 1 换 `MAGIC\WAT01_01.SHP`；每 tick `0x45ebdc` 位移，x 速度向 0 减 `0x1800`，y 速度加 `0x2000` 到 `0x30000`；`0x45e575` 每 6 tick 进一张，第 24 tick 放行并删除 |
| 2 解状态 | 单个对象 | 换 `SHAPE\NUM510.SHP`、`[esi] = 0x2c000000`、缩放 1.0；子状态 0 每 tick 层级 +1、缩放 x +0x4000／y +0x6400 到 16；子状态 1 回减，归 0 放行删除（共 32 tick） |
| 5 气力／6 永久 | `0x401390(x, y + 0x30, 0x18d／0x18e, …)` 发射器，外加带 `0x4000` 标志、+0xa8 = 延迟 + 108 的对象 | 带 0x4000 的对象到时放行删除，不画 |
| 7 临时加成 | `0x401390(x, y + 0x10, 0x18c, …)` ×2，外加 +0xa8 = 延迟 + 90 的等待对象 | 同上 |

小条：`0x43b3f0` 经 `0x43ace0` 建 Bar_HP（对象 145，`SHAPE\BAR_HP1.SHP` 起 6 张），位置 (x − 21, min(y + 8, [0x4c094c] − 36))、shape +3（`BAR_HP4` 框 45×8，原点 (4,3)）、+0x80 |= 0x100；`0x43ad30` 建 Bar_MP（对象 146）于其下 16 px；条过程 `0x4364e0` 以 live cur/max 画填充（HP `BAR_HP5`、MP `BAR_HP6`，各 39×2，读法见 [original_identity_bar.md](original_identity_bar.md)）；`0x43b4c0` 行动收尾删除。

**resource-derived**：402 sfxUseItem 的 WAV 见 [first_battle_audio.md](first_battle_audio.md)；用药姿势见 [map_pose_floaters](../runtime_observations/map_pose_floaters/README.md#1-use_magic-姿势0x4071e0)。

## 重制接线

- `game/battle/scene/BattleItemUsePresentation.gd`：AI 用药先 `BattleAttackCue.begin_item`（镜头 → 射程 12 tick → 滑行 → 目标高亮 12 tick，射程用移动色）；效果段姿势、`use_item` 音、按顺序生成星点／闪光，等第一个效果放行；再挂小条、浮数字，最后一个数字第 32 tick 放行、撤条。玩家用药跳过引导段；`BattleSceneMenus.use_inventory_item` 关物品面板后立即 `BattlePanelMotion.finish()`，目标页不留收窗快照。规则层不动。
- 用药规则（谁用、给谁、消耗）见 [original_item_actions.md](original_item_actions.md#证据)。

## 复现

`r2 -q -c 's 0x440176; pD 0x2d0' $HSL_ORIGINAL_DIR/hsl01.exe`（用药低字 7–14；分派表 `pxw 0x34 @ 0x44227c`，效果顺序 `s 0x40a300; pD 0x2d0`，星点 `s 0x408df0; af; pdf`，小条 `s 0x43b3f0; pD 0xd0`）。

## 边界

- `0x401390` 发射器（气力／永久／临时加成画面）未读。
- 小条 cur/max 文字（位 0x100，`0x411d70`）未画。
- AI 引导射程格是「自身格＋四邻无敌对占位」近似，不是逐格 `0x40f440` 模式4 泛洪。
- 小条 y 上限的 [0x4c094c] 按地图高取值，未逐关核对。
- 玩家确认用药后的原版帧未截：选格时底部的资料板（原版选格帧可见）在确认那一 tick 是否即时撤掉，只由 `0x4449a7` 直进姿势推定（provisional）。

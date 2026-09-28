# 用药演出：AI 引导、Show_Magic_Star 效果、目标小条与数字

> evidence: static-derived; resource-derived; runtime-measured: 2026-09-27 原版玩家第 1 場「棄卒」（LEVEL051）用回復藥选目标时指针处是道具图标、无权杖、周围五格十字蓝框、悬停己格开资料窗; provisional: 0x401390 三类效果对象的加色＋engMIX 按"加色 × 层级/16"画、随机数用重制种子；AI 引导与玩家选格的射程格按"自身格＋四邻无敌对占位"近似 0x40f440 模式4 泛洪；小条 y 上限的 [0x4c094c] 按地图高 · status: live · functions: 0x401390, 0x408b20, 0x408df0, 0x409e40, 0x40f440, 0x40f560, 0x411200, 0x411d70, 0x416d04, 0x41f43b, 0x430230, 0x4364e0, 0x437020, 0x439997, 0x43b3f0, 0x43b4c0, 0x440132, 0x440176, 0x4401c7, 0x440211, 0x4402ed, 0x440391, 0x440437, 0x4448f4, 0x4449a7, 0x4449bb, 0x444a5c, 0x444ab2, 0x444aba, 0x444ac9, 0x444be4, 0x45e575, 0x45eb9d, 0x45ebdc · updated: 2026-09-28

## 结论

- 原版 AI 用药有引导段：先画移动色射程 12 tick，光标从用药者滑到目标，目标亮起 12 tick，再出姿势、`0x409e40` 生效；玩家用药没有引导段，其余共用（static-derived）。
- 玩家选用药目标是地图选格，不是窗口：点道具即持物并关用药窗；state104 `0x4448f4` 用 `0x40f440(user, 1／大体型 2, 模式4)` 标范围（自己＋四邻，敌方／NPC 占位格不进）；state105 每 tick 以移动调色板 `0x411200` 画范围、`0x430230` 画格光标；光标下有任何一方的单位就开身份栏（`0x4449bb`，范围外也开）；左键只在范围格且格上是己方、非 no_attack 单位时确认，别处点击无反应；右键放回道具、重开用药窗（static-derived；帧 runtime-measured）。
- 确认那一 tick 进 0x69 `0x4449a7` 姿势、不再画范围与光标；下一 tick `0x444ab2` 生效、`0x444aba` 清持物——持物图标只多留一 tick，不是"留到姿势结束"（static-derived）。
- 重制照此：点道具当帧持物图标就在指针处（压在收窗快照之上），道具窗滑出收起，地图画移动色范围、I_RECT01 格光标与悬停身份栏，左键范围内己方格走原 `use_item`，右键回道具列表；确认时范围／光标／身份栏原地消失，持物图标多留一个原版 tick，不留收窗快照（static-derived）。
- `0x409e40` 有效果就放 402 sfxUseItem，按固定顺序生成 Show_Magic_Star 等效果对象，第一个生成的带等待；随后挂目标 HP／MP 小条、浮绿／蓝数字，最后一个数字放行后撤条（static-derived）。
- 气力／永久能力两类各由 `0x401390` 在目标脚边撒 32 颗上飘星（397 WAT04／398 WAT01，effProcFlyUp2：0.5–1.44 px／tick 上升、4 张、末张后 16 级淡出）；临时加成撒 12＋8 颗 396 WAT01（effProcCollectFadeShape：从 64–127 px 外每 tick 1.5 px 向落点聚拢、每 2 tick 亮一级，到点后逐级淡出）（static-derived；模板 resource-derived）。
- 小条两条都置 `+0x80` 位 0x100：条右侧 (填充 x + 39 + 5, 条 y − 6) 以 FONT.15 白字（0x8430 影）印 live `cur/max`，无补位（static-derived）。
- 重制：`game/battle/scene/BattleItemUsePresentation.gd` 按同一序列播放用药回执，AI 引导经 `BattleAttackCue.begin_item`（static-derived）。
- 差异：射程格为近似；三类效果对象的随机数用重制种子、加色层级混合按近似；无原字形的说明行用白字 Label（差异清单 `ai-item-use-presentation`、`floater-extra-words`、`item-use-rules`；provisional）。

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

玩家持药选目标：用药窗点道具 `0x439997` → `0x437020` 把道具取进持物 `[0x4c1ce4]`；光标对象 `0x430410` → `0x430310` 在指针处画该道具图标、权杖不画。玩家状态经字节表 `0x445758` → 指针表 `0x445694` 分派，用药一段：

| state | 入口 | 行为 |
| --- | --- | --- |
| 102 | `0x4448ba` | 建 mode6 用药窗（103 等窗口关） |
| 104 | `0x4448f4` | 持物非 0：`0x40f440(user, [record+0x2c] ? 2 : 1, 4)` 标范围（写移动缓冲 `*0x4c1b44`），`0x444be4` 置 `[0x4c1b00] |= 0x200000` 进 105；持物为 0 回 state3 |
| 105 | `0x44492a` | 左键（`[0x4c6398] & ebx`）：`0x40f560(mx, my)` 查移动缓冲 bit 0x80（范围格），`0x411c40` 格字 `& 0x10000`（pmPlayer），`0x407800` 取对象写 `0x4c1cec`，`0x446b00`（模板 +0xa0 bit 2 no_attack）为 0 才 `0x4449a7` 调 `0x4071e0` 姿势、进 106；任一不成立落到悬停 |
| 105 悬停 | `0x4449bb` | 格字 `& 0x70000`（任一方单位）→ 对象 `+0x80 |= ebp`、`0x436490(+0xa0, 3, -1)`、`0x43b4e0(unit, 3, esi)`：身份栏（与移动／攻击选格的 `0x43e570` 同一对） |
| 105 取消 | `0x444a3c` | 右键（`0x20000` 且非左键）或 `[0x4c6390] & 0x100000`：`0x436e30` 放回、`0x444a81` 清持物、回 102 |
| 105 绘制 | `0x444d78` | `0x411200(user, 0)` 移动色范围、`0x430230(mx, my, 0)` 格光标；确认那一 tick 跳过 |
| 106 | `0x444a99` | `0x409e40(target, 持物, user, 0)` 生效，`0x444aba` 清持物，进 107 等效果 |
| 108 | `0x444ac9` | 小条与数字 |

模式4 泛洪（`0x40ed50` 跳表 `0x40f1c4` 第 4 项 `0x40ef16`）：地形代价与高差都记 0，只挡格字含 `0x24000`（pmEnemy／pmNPC）且占位者非 no_block（`0x446b30`）的格，出图格不收；物品本身没有射程字段参与。

2026-09-27 原版截帧（LEVEL051 雷歐納德 → 回復藥）：范围外与悬停本格都见回復藥布袋图标、无权杖，雷歐納德周围十字五格蓝框，悬停本格下方开资料窗；确认后图标与十字蓝框一起消失（详见 [游戏光标](../runtime_observations/game_cursor/README.md#证据)）。2026-09-27 原版截帧（LEVEL051 雷歐納德 → 回復藥）：范围外与悬停本格都见回復藥布袋图标、无权杖，确认后图标与十字蓝框一起消失（详见 [游戏光标](../runtime_observations/game_cursor/README.md#证据)）。

`0x409e40` 的效果：`0x409e98` 效果点 = 目标 (x, y − 0x34)，大体型（`0x446ad0`）再减 16（`0x409eb6`）。`0x40a1b9..0x40a2c8` 按 HP 加值、MP 加值、气力 +0xe8（上限 60）、永久能力（`0x448840` 刷新）、临时加成、状态解除位计效果数 edi，非零在 `0x40a349` 放 402 sfxUseItem（`WAV\MHEAL001.WAV`）；满值照样有加值字段，满血喝药也放音。调用顺序 `0x408b20(x, y, case, 等待对象, 延迟)`：解状态 2 → 临时加成 7 → 永久 6 → 气力 5 → MP 1 → HP 0；第 i 个（共 n 个）延迟 `(n − 1 − i) × 25` tick，第一个生成的带等待对象（`0x40a3c0` 压 esi）。

对象 176 `Show_Magic_Star`（planeMenu2，`MAGIC\WAT04_01.SHP` 4 张）：

| case | 生成（`0x408b20`） | 过程（`0x408df0`） |
| --- | --- | --- |
| 0 回血／1 回魔 | `0x408d48`：16 个对象；方向 `rand(48)`，奇数个取 `128 − 它`（256 步圆，64 = 正下）；`0x45eb9d(方向, 0x20000)` 初速 2 px／tick；+0xa8 首个 = 延迟，之后累加 `1 + rand(3)`；最后一个带等待对象 | 延迟到时初始化 `[esi] = 0x4000000`（加色）、层级 16、+0x7c = 0x50005、+0x78 = 0x40004；case 1 换 `MAGIC\WAT01_01.SHP`；每 tick `0x45ebdc` 位移，x 速度向 0 减 `0x1800`，y 速度加 `0x2000` 到 `0x30000`；`0x45e575` 每 6 tick 进一张，第 24 tick 放行并删除 |
| 2 解状态 | 单个对象 | 换 `SHAPE\NUM510.SHP`、`[esi] = 0x2c000000`、缩放 1.0；子状态 0 每 tick 层级 +1、缩放 x +0x4000／y +0x6400 到 16；子状态 1 回减，归 0 放行删除（共 32 tick） |
| 5 气力／6 永久 | `0x401390(x, y + 0x30, 0x18d／0x18e, …)` 发射器，外加带 `0x4000` 标志、+0xa8 = 延迟 + 108 的对象 | 带 0x4000 的对象到时放行删除，不画 |
| 7 临时加成 | `0x401390(x, y + 0x10, 0x18c, …)` ×2，外加 +0xa8 = 延迟 + 90 的等待对象 | 同上 |

`0x401390(x, y, code, w, h, delay, jitter, count)`（`0x4013cf` 循环）：每颗 dx = rand(w)，大于 w/2 折成 w/2 − dx，dy 同法；`0x45e307(x + dx, y + dy, code, 0)` 建对象、`+0xae` = delay，delay 每颗加 `rand(jitter) + 1`，对象互相 `0x45e485` 链接，返回首个。调用点：case 5／6 `0x408bfe`／`0x408c67` 为 `(x, y + 0x30, 0x18d／0x18e, 68, 16, 延迟, 6, 32)`；case 7 `0x408cd0` 为 `(x, y + 0x10, 0x18c, 8, 8, 延迟, 1, 12)`，`0x408ce8` 再 `(x, y + 0x10, 0x18c, 8, 8, 延迟 + 12, 1, 8)`。

global.obs 模板（`TYPE.H`：effProcFlyUp2 = 16、effProcCollectFadeShape = 80，跳表 `0x4231b0`；三者都是 planeEffect2、defProcEffectProcess1，过程序言 `0x415dc0` 数完 `+0xae` 才画、首次置加色 0x4000000 与层级 16）：

| code | 名 | 形状 | 张数／延迟 | 程序 | 字段 |
| --- | --- | --- | --- | --- | --- |
| 396 | Cast_Star_Add_Misc2 | `MAGIC\WAT01_01.SHP` | 4／2 | effProcCollectFadeShape | Data3 0x18000、Data5 0x400000、Data6 0x800000 |
| 397 | Cast_Star_Add_ST | `MAGIC\WAT04_01.SHP` | 4／16 | effProcFlyUp2 | Data5 0xf000、Data6 0x8000 |
| 398 | Cast_Star_Add_Misc | `MAGIC\WAT01_01.SHP` | 4／16 | effProcFlyUp2 | Data5 0xf000、Data6 0x8000 |

effProcFlyUp2（`0x416d04`）首次：速度 = (rand & +0x9c) + +0xa0（0x8000..0x17000，16.16），`0x45eb9d(0xc0, 速度)` 朝正上，`+0x7c += 6 + (rand & 7)`；每次先 `0x45ebdc` 位移，再 `0x45e575` 走 4 张（首张 16 + 6..13 + 1 tick，其余每张 17 tick），走完置 0x20000000，此后 `0x422c9a` 层级每 tick −1、归零删除。

effProcCollectFadeShape（`0x41f43b`）子状态 0：起始张 + rand(4) 并定住（`+0x78 = 0x10001`）、置 0x20000000、层级 0；圆心 = 当前 (x, y)，角 = rand & 0xff，半径 = rand(|Data6 − Data5| >> 16 = 64) << 16 + Data5（64..127 px），速度 +0x94 = Data3（1.5 px，为 0 时 2），`+0xa0 = 0x20002`。子状态 1：`+0xa0` 每 2 tick 层级 +1，到 16（`ebx`）即清 0x20000000；半径 −速度，到 `edx` = 0x10000（1 px，`0x415e94`）即置 0x20000000 进子状态 2。子状态 2：层级每 tick −1，归零删除。每 tick 以 `0x45e9bc(角, 半径)` 求偏移、位置 = 圆心 + 偏移。

小条：`0x43b3f0` 经 `0x43ace0` 建 Bar_HP（对象 145，`SHAPE\BAR_HP1.SHP` 起 6 张），位置 (x − 21, min(y + 8, [0x4c094c] − 36))、shape +3（`BAR_HP4` 框 45×8，原点 (4,3)）、+0x80 |= 0x100；`0x43ad30` 建 Bar_MP（对象 146）于其下 16 px；条过程 `0x4364e0` 以 live cur/max 画填充（HP `BAR_HP5`、MP `BAR_HP6`，各 39×2，读法见 [original_identity_bar.md](original_identity_bar.md)）；`0x43b4c0` 行动收尾删除。两条都 `+0x80 |= 0x100`（`0x43b465`、`0x43b49d`），`0x4365f0` 见该位：x = 条 x + 填充宽 + 5（`0x436602`）、y = 条 y − 6（`0x436605`），`+0xa0` 为 0 取 HP（+0xd8／+0xdc）否则 MP（+0xe0／+0xe4），`0x45b6de(值, 缓冲, 10, 5, 0)` 不补位拼成 `cur/max`，`0x411d70(x, y, 串, 50, 0, 16, 0, 0, 60000, 60000)` 以 FONT.15 面 `[0x4c1adc]`（半角 8 px）先 (+1, +1) 画 0x8430 影、再原位画 0xffff。

**resource-derived**：402 sfxUseItem 的 WAV 见 [first_battle_audio.md](first_battle_audio.md)；用药姿势见 [map_pose_floaters](../runtime_observations/map_pose_floaters/README.md#1-use_magic-姿势0x4071e0)。

## 重制接线

- `game/battle/scene/BattleItemUsePresentation.gd`：AI 用药先 `BattleAttackCue.begin_item`（镜头 → 射程 12 tick → 滑行 → 目标高亮 12 tick，射程用移动色）；效果段姿势、`use_item` 音、按顺序生成星点／闪光与 `EMITTERS`（`_emit` 照 `0x401390` 撒点，`star_state` 按 FlyUp2／CollectFadeShape 逐 tick 求张、偏移、层级，画在加色层），等第一个效果放行；再挂小条（`BattleUISkin.text` 在 `BAR_TEXT_OFFSET` 印 `cur/max`）、浮数字，最后一个数字第 32 tick 放行、撤条。玩家用药跳过引导段。规则层不动。
- 玩家选格：`BattleItemPanel._show_use_pick` 进 page `target`，页面经 `BattlePanelMotion.slide_out` 按收窗滑出，只留 `HeldItem`（跟指针、入组 `game_cursor_held_items` 使权杖不画）；指针移动与左键经 `use_pick_pointer` 交 `BattleSceneMenus`：`_begin_item_pick` 取 `BattleItemUsePresentation.use_cells`，`BattleSceneOverlays.show_item_range` 以 move 调色板画；`refresh_item_pick` 每帧画 I_RECT01 格光标（`BattleSelectionCursor`）与悬停身份栏（`BattlePresentation.preview_hovered_unit`）；`_item_pick_pointer` 在格属范围且 `recovery_target_ids` 含格上单位时调 `use_inventory_item`；右键／Esc `cancel` 回道具列表并 `slide_in`。`use_inventory_item` 关面板后 `BattlePanelMotion.finish()`，不留收窗快照；`HeldItem` 点道具当帧挂上（`z_index` 1 压过收窗快照），确认隐藏面板时 `_release_held_icon` 把它移出面板再留一个原版 tick。
- 用药规则（谁用、给谁、消耗）见 [original_item_actions.md](original_item_actions.md#证据)。

## 复现

`r2 -q -c 's 0x440176; pD 0x2d0' $HSL_ORIGINAL_DIR/hsl01.exe`（用药低字 7–14；玩家选格 `s 0x4448f4; pD 0x200`、分派 `pxw 0x14 @ 0x4456fc`、绘制 `s 0x444d78; pD 0x20`；分派表 `pxw 0x34 @ 0x44227c`，效果顺序 `s 0x40a300; pD 0x2d0`，星点 `s 0x408df0; af; pdf`，小条 `s 0x43b3f0; pD 0xd0`，条上数字 `s 0x4365f0; pD 0xe0`，发射器 `s 0x401390; af; pdf`，调用点 `s 0x408bf2; pD 0x150`，FlyUp2 `s 0x416d04; pD 0xb8`，CollectFadeShape `pxw 4 @ 0x4232f0` → `s 0x41f43b; pD 0x1a0`；模板读 `content/imported/hsl/shared/first_skill/global.obs` 的 code 396–398）。

## 边界

- 三类效果对象的随机数（位置、延迟、速度、张、角、半径）由重制按本次用药种子抽，不是原版 `0x458c10` 全局流；加色＋engMIX 按"加色 × 层级/16"画（同 LevelUpStars 读法）；`0x45e9bc` 极坐标按浮点 cos／sin 向下取整，未用原版三角表。
- AI 引导与玩家选格的射程格都是「自身格＋四邻无敌对占位」近似（`use_cells`）：模式4 实际只挡 pmEnemy／pmNPC 且非 no_block 的占位，重制按 `ActorRoleRules.hostile` 挡；大体型使用者的 range 2 未建模。
- 选格期间地图不随指针贴边卷动（重制模态期间不卷；原版 state105 是否卷动未读）；悬停时原版给单位置 `+0x80 |= ebp` 亮起；重制的单位高亮（[dialogue_death §5](../runtime_observations/dialogue_death/README.md#5-单位高亮)）只在选攻击目标时全场点亮，道具选格期间未接（差异清单 `highlight-colours`：道具选目标的原版帧未拍）。
- 小条 y 上限的 [0x4c094c] 按地图高取值，未逐关核对。
- 给予流程原版同样经持物（`0x438c86`）与地图选格（state113 `0x444c27`），重制给予仍是窗口选人（本轮未改）。

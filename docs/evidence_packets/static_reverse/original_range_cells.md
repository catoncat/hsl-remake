# 移动／攻击／技能范围格：ICONBOX 半透明填充、I_rect 边框帧与逐 tick 脉动

> evidence: static-derived; resource-derived; runtime-measured · status: live · functions: 0x411200, 0x411480, 0x4116a0, 0x4504d0, 0x450d4b, 0x450d69, 0x4684b6 · tools: hsl_original_control.py, hsl_win32_memread.c, hsltools/assets/range_cells.py · updated: 2026-09-26

Checked: 2026-09-22。起因：实玩反馈——原版范围格会闪烁（复述），重制版（旧 `BattleSceneOverlays` 的 Line2D＋Polygon2D）不闪。本包恢复三个范围绘制函数画什么、用哪几个 PAK 资源、颜色怎样随 tick 变化，并以一次受控 Wine 采样核对像素与计数器。几何（32 px 轴对齐格、格原点）不在本包改动范围，仍是空间合同的一部分。导入器 `hsl generate range_cells` 产出 `content/imported/hsl/shared/range_cells/`（四张 256×32 边框 sprite sheet ＋ `manifest.json` 内的颜色表／计时字段），运行时入口 `game/battle/runtime/RangeCellOverlay.gd`。

## 三个绘制函数（static-derived，EXE SHA-256 `f0b5f835…70f7`）

| 函数 | 用途 | 覆盖缓冲 | 脉动计数器 | 颜色表 | 帧计时器 | 边框 SHP |
| --- | --- | --- | --- | --- | --- | --- |
| `0x411200` | 移动范围 | `*0x4c1b44` | `0x4c1a7c` | `0x476be4`（9 项） | `0x476bf8` | `I_rect11..18` |
| `0x411480` | 武器攻击范围 | `*0x4c1b48` | `0x4c1a80` | `0x476c00`（9 项） | `0x476c14` | `I_rect21..28` |
| `0x4116a0` param_4=0 | 魔法目标／footprint | `*0x4c1b4c` | `0x4c1a84` | `0x476c1c`（9 项） | `0x476c44` | `I_rect31..38` |
| `0x4116a0` param_4=1 | 绝技目标／footprint | `*0x4c1b4c` | `0x4c1a84` | `0x476c30`（9 项） | `0x476c44` | `I_rect41..48` |

三者结构相同：以摄像机原点（`0x4c091c／0x4c0920`）遍历 `0x476b3c × 0x476b40` 格，覆盖缓冲字节非零的格先后画两层：

1. **填充**：`fcn.0046c091(x,y)` 定位后以绘制标志 `0x40000000`、`uStack_28 = 4`（源矩形 `0x4c38c8..d4 = 0,0,32,32`）blit `*0x4c1b30` 指向的 `ICONBOX.SHP`（32×32 全 `0xffff` 实心块，`hsl generate range_cells` 校验），颜色参数取 `ramp[abs(counter)]`。`0x4684b6` 的 span 分派 case 6：`dst = ((dst & 0xf7de) + (colour & 0xf7de)) >> 1`——RGB565 各通道先抹最低位再取平均，即 50／50 混色。
2. **边框**：同格同位置 blit `I_rect<调色板><帧+1>.shp`（32×32，外圈 1 px 透明、内圈实心渐变边框，中心透明），不混色。

`0x4116a0` 的调色板参数来源：`0x441913／0x4419a5`（走 `0x4097f0` 查 `0x4c2ca0` MAGIC 表）传 0，`0x441c19／0x441c9b`（走 `0x409810` 查 `0x4c3920` SPECIAL 表）传 1，两表身份见 [技能资源与消耗](original_skill_resources.md)。故调色板 0＝魔法（黄色 ramp `0xffea…0xd6a5`），1＝绝技（青绿 ramp `0x6ef7…0x45b2`）。

### 脉动（每绘制 tick 一步）

`0x411442..0x41145e`（移动；其余两函数同构）：绘制完成后 `counter >= 0` 时 `counter += 1`，若 `ramp[counter] == 0`（越过第 9 项）则 `counter = 1 - counter`；`counter < 0` 时仅 `counter += 1`。存储序列 `0,1,…,8,-8,-7,…,-1,0…`，17 tick 一周；绘制用 `ramp[abs(counter)]`，因此最暗项（索引 8）连续显示两 tick。四张 ramp 均由亮到暗排列（移动 `0x529f → 0x295a`）。

### 边框帧计时

`0x4113ff..0x411438`：`delay -= 1`，到 0 时 `delay = reload`（字 `0x476bfa` = 8），`frame = (frame + 1) mod count`（字 `0x476bfe` = 8）。每 8 tick 换一帧，8 帧 64 tick 一圈；初始 `delay = 8, frame = 0`。tick = 原主循环一次迭代，见 [原版 tick 率](../runtime_observations/original_tick_rate/README.md)。

## 过场位置标记 obj_Story_Show_Pos（static-derived；runtime-reference）

Checked: 2026-09-26（同一 EXE）。开场与胜负脚本的 `actInsertShowPosObject,x,y` 画的也是本包的魔法格外观。

- **插入**：opcode 58（表 `0x4537f4`＋58×4 → `0x450d4b`）调 `0x45e307(x, y, 702, 0)`。`global.obs` 中 702＝`obj_Story_Show_Pos`：planeMenu1，占位 shape `MAGIC\WAVEUP002.SHP`（不被绘制），process `defProcStoryShowPos`＝64；`PROCESS.DEF` 表 `0x477c2c` 第 64 项 → `0x4504d0`。
- **删除**：opcode 59 `actDeleteShowPosObject`（`0x450d69`）在计数 `0x4c1d40` 非 0 时置 `0x80000000`。之后每个标记在自己的 process 里把计数减 1，再调 `0x45e3ed` 删除自己，所以全部标记在下一 tick 消失。
- **`0x4504d0` 每 tick**：
  1. 首次调用（标志 `0x20000000`）：若计数为 0（本批第一个标记），重置帧计时 `0x479358`＝6／6、帧 `0x47935c`＝0／帧数 8，并给自己置 `0x10000`（领头）；然后计数加 1。
  2. 绘制格原点 `([obj+4] & ~31, [obj+8] & ~31)`：脚本像素不对齐时也画它所在的整格。先以标志 `0x40000000` blit `*0x4c1b30`（ICONBOX），颜色 `0x479344[abs(0x4c1d50)]`；`0x479344` 的 9 项与魔法 ramp `0x476c1c` 逐字相同（`0xffea…0xd6a5`）。再 blit `[0x4c1b34]+0x18+frame`，与 `0x4116a0` param_4=0 的 `[0x4c1b34]+frame+0x18` 是同一组 `I_rect31..38`。
  3. 只有领头标记推进：`0x479358` 减 1，到 0 时重装为 6，帧＋1 mod 8（每 6 tick 换帧，48 tick 一圈）；`0x4c1d50` 走与范围格相同的 17 tick 三角脉动。
- **结论**：过场标记＝黄 ramp 半透明填充＋`I_rect31..38` 边框，与魔法目标格同一外观。区别只有两点：换帧间隔 6 tick（范围格是 8），以及用自己的一套计时器。
- **录屏（runtime-reference）**：2026-09-24 录屏（60 fps，游戏窗口 2×，第 51 关撤退切换，脚本 `(267,209)`）约 402.1 s 时标记画在格 (8,6)，即世界 (256,192)–(288,224) 整格，是黄色脉动填充加动画边框。约 401.8–405.4 s 可见（胜负板显示于 402.8–405.0 s），405.6 s 已消失；之后的玩家回合（抽帧 406 s、415 s 及 405–465 s）地图上没有常驻的目的地格。抽帧存于 `ignored/escapemark/orig/`（不入库）。

## 资源（resource-derived）

`hsl.pak` `@:\shape\`：`ICONBOX.SHP`（实心块）、`I_rect11..48.shp`（32 帧边框）；`I_rect01..08`（无调色板前缀）存在但三函数都不引用，`ICONRECT.SHP` 亦不被引用（negative-evidence：仅按三函数的字符串引用判断，未穷举全部调用方）。导入器把每个调色板的 8 帧横向拼成 `range_border_<palette>.png`（帧顺序 1..8），并记录每帧源 sha256 与四张 ramp 的 RGB565／RGB 值；`hsl check range_cells` 校验 sheet 尺寸、9 项 ramp、8 帧×8 tick 与"外圈透明、内圈不透明、中心透明"的形状。

## Runtime-measured

2026-09-22 一次 Wine 会话（`tools/hsl_original_control.py`，10.5 分钟，标题→戰場記錄→存档 3→開始遊戲→跳过开场→雷奧納德 移动／攻击选择；原始 PNG 与 memread 样本在 `ignored/`，存档未写）：

- **像素**：移动选择帧中光标所在格 `(352,160)`，边框行 `(353..382, 161)` 的 RGB565 序列 `06ff 06ff 06ff 05ff ×4 04ff ×4 03ff ×4 02ff ×3 01fc ×4 0119 ×3 0077 ×3 06ff 06ff` 与 `I_rect11` 首行逐像素一致；同帧三个不同格的填充像素满足 `ov = ((bg & 0xf7de) + (0x295a & 0xf7de)) >> 1`（bg 取菜单打开、无范围格的前一帧同位置像素），即当时 `abs(counter) = 8`。攻击选择帧中四邻格边框行 `f000 d800 d800 c000 a800 9800 fd14 …` 与 `I_rect21` 首行一致，填充符合红 ramp 索引 2（`0xf228`）的平均。
- **计数器**：`hsl_win32_memread.exe --repeat`（240 样本、约 30 ms 间隔）读 `0x4c1a7c`：观测到全部 17 个值 `-8..8`（含 8 与 -8 各 16／17 样本），符合"17 tick 一周、索引 8 连续两 tick"；同一样本里 `0x476bf8` 字在 8→1 之间递减、`0x476bfc` 帧在 0..7 循环。
- **状态**：范围格只在移动／攻击选择态绘制；行动环打开时不画（同一会话 `hover_enemy` 帧）。

## 重制接线

`RangeCellOverlay`（挂在 `World/MoveOverlay`）读取 manifest：每格一个子节点，`Polygon2D` 填充用 `ramp[abs(index)]` 以 alpha 0.5 叠加（8 bit 平均替代 565 抹位平均，差 ≤1 级），`Sprite2D` 以 sheet 的 `hframes = 8` 取边框帧；一个运行 tick（`OriginalTick.ticks(delta)`）同时驱动 17 tick 脉动与 8 tick 换帧，新加入的格与已有格同相。`BattleSceneOverlays` 只决定格集合与调色板（移动＝move，`SELECTED_ATTACK` 空／normal＝attack，magic＝magic，special＝special）。旧的"可选 vs 仅 footprint"双线宽区分（remake-invented）随之移除——原版 footprint 只有一种画法。

## 不支持的结论

- `0x4116a0` 的调色板参数来源 `0x441913`／`0x4419a5`／`0x441c19`／`0x441c9b` 落在 AI 施法起手的滑动／目标状态里（魔法 `0x44182a`／`0x441947`、绝技 `0x441b35`／`0x441c4c`，见[施法覆盖层](original_cast_overlays.md)）；UI6 起 `BattleAttackCue` 用本包的 manifest 画起手格。过场里是否调用未核对。
- 未复现 `I_rect01..08` 与 `ICONRECT.SHP` 的用途。
- 565 抹位平均与 8 bit alpha 0.5 的 ≤1 级差异未做逐像素 Godot 截图对比；玩家可见效果以人工验收为准。

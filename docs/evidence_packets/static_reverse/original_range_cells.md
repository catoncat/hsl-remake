# 范围格：ICONBOX 半透明填充、I_rect 边框帧与逐 tick 脉动

> evidence: static-derived; resource-derived; runtime-measured · status: live · functions: 0x40fa80, 0x4100e0, 0x411200, 0x411480, 0x4116a0, 0x444fb3, 0x445256, 0x4504d0, 0x450d4b, 0x450d69, 0x4684b6 · tools: hsl_original_control.py, hsl_win32_memread.c, hsltools/assets/range_cells.py · updated: 2026-09-27

## 结论

- 原版：移动、武器攻击、魔法、绝技四种范围格都是「ICONBOX 实心块按 ramp 颜色 50／50 混色＋`I_rect` 边框帧」；ramp 按 17 tick 三角脉动（最暗项连显两 tick），边框每 8 tick 换帧、8 帧一圈；过场标记 `obj_Story_Show_Pos` 用魔法格同一外观，但每 6 tick 换帧、计时独立（static-derived；Wine 采样 runtime-measured）。
- 原版选魔法／绝技目标：可选射程一律用武器攻击红格（`0x411480`），光标所在处的作用脚印用魔法黄（`0x4116a0` 传 0）／绝技青绿（传 1），每 tick 先画射程、后画脚印，脚印叠在红格上（static-derived）。
- 重制：`game/battle/runtime/RangeCellOverlay.gd` 读 `content/imported/hsl/shared/range_cells/manifest.json`，一个运行 tick 同时驱动脉动与换帧；`BattleSceneOverlays` 只决定格集合与调色板（static-derived）。
- 差异：8 bit alpha 0.5 代替 RGB565 抹位平均，差 ≤1 级；未做逐像素截图对比（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835…70f7`）

| 函数 | 用途 | 覆盖缓冲 | 脉动计数器 | 颜色表 | 帧计时器 | 边框 SHP |
| --- | --- | --- | --- | --- | --- | --- |
| `0x411200` | 移动 | `*0x4c1b44` | `0x4c1a7c` | `0x476be4`（9 项） | `0x476bf8` | `I_rect11..18` |
| `0x411480` | 武器攻击 | `*0x4c1b48` | `0x4c1a80` | `0x476c00` | `0x476c14` | `I_rect21..28` |
| `0x4116a0` param_4=0 | 魔法目标／footprint | `*0x4c1b4c` | `0x4c1a84` | `0x476c1c` | `0x476c44` | `I_rect31..38` |
| `0x4116a0` param_4=1 | 绝技目标／footprint | `*0x4c1b4c` | `0x4c1a84` | `0x476c30` | `0x476c44` | `I_rect41..48` |

| 条目 | 读法 |
| --- | --- |
| 遍历 | 以摄像机原点 `0x4c091c／0x4c0920` 遍历 `0x476b3c × 0x476b40` 格，覆盖字节非零的格画两层 |
| 填充 | `fcn.0046c091(x,y)` 定位，标志 `0x40000000`、`uStack_28 = 4`（源矩形 `0x4c38c8..d4 = 0,0,32,32`）blit `*0x4c1b30`（ICONBOX.SHP），颜色 `ramp[abs(counter)]`；`0x4684b6` case 6：`dst = ((dst & 0xf7de) + (colour & 0xf7de)) >> 1` |
| 边框 | 同位置 blit `I_rect<调色板><帧+1>.shp`，不混色 |
| 调色板来源 | `0x441913`／`0x4419a5`（经 `0x4097f0` 查 MAGIC 表 `0x4c2ca0`）传 0＝魔法黄 ramp `0xffea…0xd6a5`；`0x441c19`／`0x441c9b`（经 `0x409810` 查 SPECIAL 表 `0x4c3920`）传 1＝绝技青绿 ramp `0x6ef7…0x45b2` |
| 脉动 `0x411442..0x41145e` | 绘制后 `counter >= 0` 时 +1，`ramp[counter] == 0` 则 `counter = 1 - counter`；`counter < 0` 时仅 +1；序列 `0,1,…,8,-8,…,-1`，17 tick 一周；四张 ramp 由亮到暗（移动 `0x529f → 0x295a`） |
| 选目标叠画 | 玩家魔法态 `0x79`：`0x444eb7` 调 `0x40fa80`→`0x40f8b0` 把射程写进 `*0x4c1b48`，`0x444f08`／`0x444f1b` 调 `0x4100e0` 把光标格脚印写进 `*0x4c1b4c`；每 tick `0x444fb3` 调 `0x411480`（红），随后 `0x444fca` 调 `0x4116a0(x, y, 0, 0)`。绝技态 `0x98`：`0x445075`／`0x44508f` 写射程、`0x4450e0`／`0x4450f4` 写脚印，`0x445256` 画红、`0x44526b` 调 `0x4116a0(…, 1)`。AI 起手同序：魔法 `0x441779`／`0x4418fd` 写、`0x44198f` 红→`0x4419a5` 黄；绝技 `0x441a73`／`0x441c02` 写、`0x441c84` 红→`0x441c9b` 青绿 |
| 计数器归属 | 三个脉动计数器 `0x4c1a7c`／`0x4c1a80`／`0x4c1a84` 与三组帧计时（字 `0x476bf8`／`0x476c14`／`0x476c44`，帧 `0x476bfc`／`0x476c18`／`0x476c48`）在全 EXE 的引用只在各自绘制函数体内（`0x411248..0x41146c`、`0x4114bc..0x411692`、`0x411709..0x4118f1`）：不在别处复位，各层只在自己被画的 tick 前进一格；魔法与绝技脚印共用 `0x4116a0` 的一组 |
| 自中心绝技射程层 | 绝技态写射程前 `0x445026` 调 `0x409830` 取该绝技的射程，`0x445075`／`0x44508f` 以施法者为原点 `0x40fa80(施法者, 射程, -1, 0)`——自中心绝技（射程 `range0Cell`）也一样，红层只有传播后的施法者格；`0x4450ab` 以 `0x40fab0` 查光标格在射程缓冲里才 `0x4450e0` 以光标格调 `0x4100e0` 写脚印，否则 `0x4450f4` 清空 |
| 帧计时 `0x4113ff..0x411438` | `delay -= 1`，到 0 重装为字 `0x476bfa` = 8，`frame = (frame+1) mod` 字 `0x476bfe` = 8；初始 delay 8、frame 0 |

tick 定义见 [original_tick_rate](../runtime_observations/original_tick_rate/README.md)。

过场标记：opcode 58（表 `0x4537f4`＋58×4 → `0x450d4b`）调 `0x45e307(x, y, 702, 0)`；`global.obs` 702＝`obj_Story_Show_Pos`（planeMenu1，占位 shape `MAGIC\WAVEUP002.SHP` 不绘制，process 64 → 表 `0x477c2c` 第 64 项 `0x4504d0`）。opcode 59 `actDeleteShowPosObject`（`0x450d69`）在计数 `0x4c1d40` 非 0 时置 `0x80000000`，各标记下一 tick 减计数并 `0x45e3ed` 删除自己。`0x4504d0` 每 tick：首次调用（`0x20000000`）若计数为 0 则重置 `0x479358`＝6／6、`0x47935c`＝0／8 并置 `0x10000`（领头），计数 +1；在 `([obj+4] & ~31, [obj+8] & ~31)` 先 blit ICONBOX（颜色 `0x479344[abs(0x4c1d50)]`，9 项与 `0x476c1c` 逐字相同），再 blit `[0x4c1b34]+0x18+frame`（即 `I_rect31..38`）；只有领头推进：每 6 tick 换帧、48 tick 一圈，`0x4c1d50` 走 17 tick 三角脉动。

**resource-derived**：`hsl.pak` `@:\shape\` 的 `ICONBOX.SHP`（32×32 全 `0xffff`）与 `I_rect11..48.shp`（32×32，外圈 1 px 透明、内圈渐变边框、中心透明）；`I_rect01..08` 与 `ICONRECT.SHP` 不被三个函数引用（negative-evidence：只按三函数的字符串引用判断）。导入器把每调色板 8 帧拼成 `range_border_<palette>.png`（256×32），记录源 sha256 与四张 ramp 的 RGB565／RGB 值。

**runtime-measured**（一次 Wine 会话，`tools/hsl_original_control.py`，标题→戰場記錄→存档 3→開始遊戲→跳过开场→雷奧納德 移动／攻击选择）

| 读数 | 结果 |
| --- | --- |
| 移动选择帧光标格 `(352,160)` 边框行 `(353..382, 161)` | `06ff 06ff 06ff 05ff ×4 04ff ×4 03ff ×4 02ff ×3 01fc ×4 0119 ×3 0077 ×3 06ff 06ff`，与 `I_rect11` 首行一致 |
| 同帧三格填充 | 满足 `((bg & 0xf7de) + (0x295a & 0xf7de)) >> 1`，即 `abs(counter) = 8` |
| 攻击选择帧四邻格 | 边框行 `f000 d800 d800 c000 a800 9800 fd14 …` 与 `I_rect21` 首行一致；填充符合红 ramp 索引 2（`0xf228`） |
| `hsl_win32_memread.exe --repeat`（240 样本、约 30 ms）读 `0x4c1a7c` | 全部 17 个值 −8..8；`0x476bf8` 字 8→1 递减，`0x476bfc` 帧 0..7 循环 |
| 状态 | 范围格只在移动／攻击选择态绘制，行动环打开时不画 |

过场标记录屏（60 fps，第 51 关撤退切换，脚本 `(267,209)`）：约 402.1 s 标记画在格 (8,6) 整格，黄色脉动填充加动画边框；约 401.8–405.4 s 可见，405.6 s 消失；之后玩家回合（405–465 s）地图无常驻目的地格。

## 重制接线

- `game/battle/runtime/RangeCellOverlay.gd`（挂 `World/MoveOverlay`）：每格一个子节点，`Polygon2D` 用 `ramp[abs(index)]` alpha 0.5 叠加，`Sprite2D` 以 `hframes = 8` 取边框帧；`OriginalTick.ticks(delta)` 驱动；按 `DRAWERS` 每个绘制函数（移动／攻击／脚印）一个运行 tick，只在该层有格时前进，新格与同层已有格同相，射程红层与脚印层各走各的相位。
- `BattleSceneOverlays`：移动＝move；武器、魔法、绝技的可选射程都＝attack；`refresh_skill_footprint` 在光标格画脚印，魔法＝magic、绝技＝special，后加的子节点叠在射程格上；自中心绝技的射程层同样是 `attack_cells`（`range0Cell` 的传播格）用攻击调色板，光标落在射程格上时 `refresh_skill_footprint` 才画作用范围（`cast_footprint` 先查射程，同 `0x40fab0`）。
- `BattleAttackCue` 用同一 manifest 画 AI 施法起手格（见 [original_cast_overlays.md](original_cast_overlays.md)）。

## 复现

`python3 tools/hsl.py check range_cells`（sheet 尺寸、9 项 ramp、8 帧×8 tick、边框形状）。

## 边界

- 过场里是否调用 `0x4116a0` 的起手格未核对。
- 原版计数器跨战斗不复位；重制每场新建 `RangeCellOverlay`，各层从 0 起数，开场相位不同（看不出）。
- 绝技态 `0x445060`／`0x445067`（`0x40ba80`→`0x411a30`，在 `test ebx, eax` 成立时）的用途未读。
- 选魔法／绝技目标的叠画只有静态读法，没有原版帧读数（provisional）：第 51 战首控存档里 雷歐納德 气力不足、氣刃斬（气格消耗 1）选不中，队中无魔法角色；替换路线：用气力 ≥1 格或有魔法角色的存档截选目标帧，按上表读法核对填充 ramp 与边框首行。
- `ICONRECT.SHP` 的用途未复现；`I_rect01..08` 是选格光标帧，见 [施法覆盖层包](original_cast_overlays.md#窗与光标)。
- 565 抹位平均与 alpha 0.5 的 ≤1 级差异未做逐像素对比。

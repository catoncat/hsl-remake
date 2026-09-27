# 行动菜单：原函数执行对照（集合、布局、换帧、展开、说明字）

> evidence: static-derived; runtime-measured: 2026-09-27 Wine 原版地图边缘行动环一帧、原版悬停录像一帧（说明字位置与颜色） · status: live · functions: 0x409090, 0x43bf30, 0x43e5d0, 0x43ea30, 0x4477b0, 0x45e5a6, 0x45e5d9, 0x45e80d, 0x460884 · tools: hsl_native_presentation_probe.py, hsltools/assets/combat_animation.py, hsltools/assets/command_frames.py, hsltools/assets/menu_layout.py, run_presentation_contract_tests.gd · updated: 2026-09-28

## 结论

- 原版行动菜单由 `0x43ea30` 按 EXE 内 UTF-16 字符表选图标集合，用 256 项整数表 `0x4a35fc／0x4a39fc`（横 ×66、纵 ×72、右移 16，中心 y−28，六项步进 +1、七项索引掩 `~7`）排位；换帧走 `0x45e5a6`（循环）／`0x45e5d9`（往返），展开走 `0x45e80d`（容差 2、步进上限 8）；地图边缘处环心仍在行动者，只把全部图标目标整体平移到图标中心离地图边 ≥`0x15` px，不看视口——开环前 `0x43bf30` 已把镜头对准行动者（static-derived）。
- 每个图标下都印中文说明字，原版默认就画，与数据包版本无关（EXE 代码）：`0x43e5d0` 消息 −1 取 `+0xac`（obj_Data9 `bcommand_N` → resource.h id 17／18／19／20／23／24／25／26／28／29／40）经 `0x4477b0` 查 RESOURCE 串，用 FONT.15 面 `[0x4c1adc]` 以 `0x460884` 画两遍：阴影 (x+1, cy+14)、正文 (x, cy+13)，`x = cx − 21 + (42 − 8·字节数)/2`（42 px 内按字节居中）；颜色 RGB565 正文 `0xffff`／阴影 `0x8430`，对象 `+0x80` 带 `0x02000000`（悬停换帧同一位）时 `0xffef`／`0x8420`（浅黄／橄榄）；位置只跟中心走，悬停放大后字压在放大图标下半部（static-derived，两帧原版像素相符）。字形繁简随数据包 RESOURCE 文本：本机 Wine 包显示简体，导入的 RESOURCE.TXT 为 Big5 繁体，同一 id。
- 重制 `CommandPresentationRules`／`BattleCommandMenu` 消费（边缘平移在 `BattleCommandMenu.place_near`，收地图矩形） `menu_layout.py` 生成的 `native_layout.json` 与 `command_frames.py` 的源帧；三个 helper 在隔离 x86 仿真里逐次执行，Godot 用同一输入逐步比较（static-derived）。
- 菜单每 tick 更新一次，按原版设计周期 16 ms（62.5 次/秒，`OriginalTick.TICKS_PER_SECOND`），见 [original_tick_rate](../runtime_observations/original_tick_rate/README.md) §结论；差异：菜单事件位的完整语义、行动后留哪几项的上层选择不由本包证明（未读）。

## 证据

**static-derived（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）**

| 内容 | 原版入口 | 读数 |
| --- | --- | --- |
| 菜单对象过程 | `0x43e5d0` `defProcBattleCommandString`（process table slot 14） | 菜单入口；`0x4038a0` 是 slot 23 `defProcAnimalDefense`，不是菜单 handler；`0x45b554` 是输入位测试 |
| 集合字符表 | `0x4784fc` `nopqz`／`0x478508` `nopqzw`／`0x478514` `nopqzv`／`0x478520` `nopqzvw`／`0x478530` `oqz`／`0x478538` `oqzv`／`0x478540` `oqzw`／`0x478548` `oqzvw`／`0x478554` `rtus` | 字符 `n..z` ＝ 对象 110..122（move／attack／item／wait／use／give／equip／drop／magic／special／ok／cancel／status，OBJ-ALL.H） |
| mode 分支 | `0x43eb32..0x43eb39` `add esi,2; dec ecx` | mode 1 跳过首字符 Move（不是去掉 Wait）；mode 2 是 `oqz` 系列；玩家入口 `0x443a3c` 调 mode 0、`0x4440e1` 调 mode 1、`0x44416f` 调 mode 3（道具子菜单） |
| `0x409090` | 按 actor 索引读武器表 `+0x84`，另有 `+0x18c／+0x2c` 分支 | 决定是否跳过 `o`（攻击）；不是「本行动已攻击」布尔值 |
| 布局算术 | `0x43ebf3..0x43edc1` | `step = 256 / N`（N＝6 时 +1），起始角 192，`index = angle & mask`，`x = cx + (table_x[index]·66) >> 16`，`y = cy + (table_y[index]·72) >> 16`，`angle = (angle − step) & 255`；中心 `(owner_x, owner_y − 28)`（owner `+4／+8`，地图像素） |
| 地图边平移 | `0x43eca2..0x43ed06`、`0x43eda6..0x43edc1` | 每轴一个平移量（初值 0），按图标顺序逐个判：中心 `< 0x15` 且 `中心 − 0x15` 更小则取之；中心 `> W − 0x15`（W＝`*0x4c0934 << 5`，y 轴用 `*0x4c0938`）且 `中心 − W + 0x15` 大于当前值则取之；建完后沿兄弟链 `+0x60` 从每个图标的 `+0x9e／+0x9c` 减去。生成点不减——展开从行动者处滑向平移后的目标 |
| 开环前镜头 | `0x443a1d` → `0x43bf30(owner, 0)` | 玩家过程状态 0 先调镜头：目标左上 `(x − 0x140, y − 0xc0)` 夹到 `[0, *0x4c0958]×[0, *0x4c095c]`，未到位返回 0 就不开环，到位后才 `0x443a3c` 调 `0x43ea30`；故只有镜头贴地图边时环才会碰边 |
| 目标坐标 | `0x43ed1a` | 图标在中心生成，目标写 `+0x9e`（x）／`+0x9c`（y）；`0x43e5d0` 的 `0x20000000` 事件分支读它们并调 `0x45e80d` |
| 展开步进 | `0x43e72a..0x43e73b` → `0x45e80d` | 两轴距离都 ≤2 才吸附；否则距离算术右移一位，限制在 ±8 |
| 悬停分支 | `0x43e7ea..0x43e822` | 事件位 `0x02000000` 置对象标志、调 `0x45f0d1`，按 `+0x94` 选 `0x45e5a6` 或 `0x45e5d9`；`0x43e824..0x43e841` 另一分支从保存字段恢复帧号、计数与帧数 |
| 初始化计数 | `0x43e786` | 写 `+0x7c = 0x00060006`（当前／重置计数都为 6） |
| 悬停缩放 | `0x43e7b6` | 16.16 值 `0x15800`；原图 42 px |
| 选择交接 | `0x43e887..0x43e891` | 图标 `+0xa8` 的 16 位值写入 owner `+0x8c` |
| 循环换帧 | `0x45e5a6..0x45e5d8`（18 条指令） | `+0x7c` 减 1，≥0 不推进；否则从 `+0x7e` 恢复计数、帧号 `+0x30` 加 1、剩余帧 `+0x78` 减 1，耗尽时从 `+0x7a` 恢复并回绕；计数 D 时每 D+1 次调用推进一帧 |
| 说明字 | `0x43e5d0..0x43e6c1`（消息 −1，`+0x90` 位 0 为隐藏时跳过） | `0x4477b0([esi+0xac])`＝`[0x4c1b3c][id]`；`strlen·8`；`0x460884(面 [0x4c1adc], 0x800000, x+1, cy+0xe, 串, [esi+0xc], 0x8430／0x8420)` 再 `(x, cy+0xd, …, 0xffff／0xffef)`；`+0x80 & 0x02000000` 选第二组色 |
| 往返换帧 | `0x45e5d9..0x45e641` | 两端不重复：三帧为 0→1→2→1→0 |

**resource-derived**

| 内容 | 出处 |
| --- | --- |
| 图标身份、帧数、循环方式 | `data\obj-051.obs` 的 `defProcBattleCommandString` Data3／Data8（Data3 非零循环、零往返）；BCMD SHP：移动／攻击／道具／待机／特殊技各 3 帧、状态 5 帧（`BCMD01／02／03／04／10／13_1.SHP` 起），原包字节 SHA-256 与 manifest `source_sha256` 一致 |
| 普通攻击程序 | `data\ANIMAL.TXT`（CP950，与 tracked 副本逐字节相同）：雷歐納德 `aniDelay,12,aniSetShape,1,aniDelay,8,aniSetShape,2,aniDelay,3` / `aniInsertAttackFlash,-90,-120,aniSetShape,3,aniDelay,30` |

| 说明字串 | `data\obj-051.obs` 13 个 `defProcBattleCommandString` 的 `obj_Data9`＝`bcommand_0..12`；`resource.h` `bcommand_0..12`＝17、18、19、20、23、24、25、26、28、29、21、22、40；RESOURCE：移動、攻擊、道具、待機、使用、交換、裝備、丟棄、魔法、特殊技、確定、取消、狀態 |

**runtime-measured（原版像素）**：Wine 实拍玩家第 2 场 · 惡夢的終曲（LEVEL052）雷歐納德 在最下行开环，「攻击」「道具」「特殊技」等字白色 (248,252,248)、阴影 (128,132,128)（＝`0xffff`／`0x8430` 的 565 显示值），字压住图标下沿；`presentation_reference/media/original-hover-loop.mp4` 悬停「移动」放大后字仍在原位、呈浅黄（约 (250,254,140)，压缩后的 `0xffef`）。

**原函数执行对照**：`hsl_native_presentation_probe.py` 装入 PE sections，显式构造栈、返回地址与对象字段，每次只允许三个 helper 之一的指令地址、上限 256 条、确认返回到停止地址。换帧覆盖循环／往返各 1、2、3、5 帧，每例初态＋84 次更新，共 680 个帧号样本；展开覆盖垂直、斜向、负坐标、临界吸附、非零起点六条轨迹。输出 [native_presentation_helpers.json](native_presentation_helpers.json)。

**runtime-measured（原版录像，历史样本）**：`runtime_observations/presentation_reference/media/` 里 `original-hover-loop.mp4`（持续悬停循环，不含进入／退出）、`original-five-menu.mp4`（移动后攻击移到顶点、其余五项重排）、`menu_after_both-original.mp4`（第一战雷歐納德移动后普攻，目标 22→2 HP，演出后直接进入下一角色）；覆盖清单 `cases.json` 无一条标 `matched`。

**runtime-measured（2026-09-27 Wine 原版，cnc-ddraw 游戏窗截图，帧在 `ignored/edgering/`，不入库）**：戰場記錄 读档进玩家第 2 场 · 惡夢的終曲（LEVEL052），雷歐納德 移到地图最下一行（脚点 y≈464）后开的五项环：镜头不动（视口底已是地图底），待機／狀態 图标中心 y≈459（＝480−`0x15`）、攻擊 y≈330，与环心 436、下侧图标偏移 +58、平移 35 的算术一致；环整体上移、不以视口为界、仍围在行动者上方。

## 重制接线

- `tools/hsltools/assets/menu_layout.py` → `content/imported/hsl/shared/command_menu/native_layout.json` → `game/battle/runtime/CommandPresentationRules.gd`（`centers`）。
- `tools/hsltools/assets/command_frames.py` → `source_objects.json`／manifest → `game/battle/scene/BattleCommandMenu.gd`（`frame_at(..., looped)`、`opening_step`）。
- 说明字：`BattleCommandMenu.gd` 每个图标子节点 `Caption`，默认就画（不读 OPT-GUIDE）；字号 14＝FONT.15 面，88×16 框以中心居中、顶在中心 y+13，阴影偏移 (1,1)，色 `CAPTION_*` 四常量，悬停换色；串为 RESOURCE 同 id 的繁体，简体显示走字形替换层。
- 普通攻击：`PYTHONPATH=tools python3 -m hsltools.assets.combat_animation --bind-programs` 按 [ANIMAL 完整程序](animal_program_execution.md) 保留指令原序（Delay 的设置与退出各占一次调用、SetShape 让出、Flash 继续读后继指令），雷歐納德帧 1／2／3 出现在第 14／24／29 次调用、末段等待收束于 60 次。
- provenance 写法：`## provenance:` 维度写 `static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md`。`CommandPresentationRules.gd` rules：0x43ea30 整数表 0x4a35fc／0x4a39fc 与六／七项索引；`BattleCommandMenu.gd` layout：经 CommandPresentationRules 取整数中心，`place_near(anchor, 地图矩形)` 做地图边平移（`BattleSceneMenus.map_logical_rect`；道具子菜单同）。
- 菜单更新：`BattleCommandMenu.HOVER_UPDATES_PER_SECOND` 取 `OriginalTick.TICKS_PER_SECOND`（16 ms/tick），依据 [原版 tick 速率](../runtime_observations/original_tick_rate/README.md) 的调度结论。

## 复现

`uv run --no-project --with 'unicorn>=2,<3' python tools/hsl_native_presentation_probe.py --output ignored/presentation-reference/native-helpers-rerun.json`，与 `native_presentation_helpers.json` 比较；数据侧 `python3 tools/hsl.py check menu_layout command_frames`。

## 边界

- 事件位 `0x02000000`／`0x20000000` 由哪种输入产生未读，不把它们命名为已证明的 hover-enter／leave。
- 行动后实际留哪几项由 `0x443330` 玩家过程与行动交接决定，本包只证明集合与几何；行动收尾见 [公共行动恢复](original_action_state_machine.md)。
- 函数调用次数等价不证明原主循环每秒调用次数、Wine 显示帧率，也不能推出 ANIMAL `aniDelay` 的秒数。
- 完整施法、受击、死亡、战利品的时间轴不由菜单 helper 推出。
- 说明字悬停色的 `+0x80` 位由谁置未读，只由录像确认悬停时变黄；禁用图标（重制半透明）原版是否另画未读。

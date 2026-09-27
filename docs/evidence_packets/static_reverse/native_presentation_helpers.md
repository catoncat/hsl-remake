# 行动菜单：原函数执行对照（集合、布局、换帧、展开）

> evidence: static-derived · status: live · functions: 0x409090, 0x43ea30, 0x45e5a6, 0x45e5d9, 0x45e80d · tools: hsl_native_presentation_probe.py, hsltools/assets/combat_animation.py, hsltools/assets/command_frames.py, hsltools/assets/menu_layout.py, run_presentation_contract_tests.gd · updated: 2026-09-27

## 结论

- 原版行动菜单由 `0x43ea30` 按 EXE 内 UTF-16 字符表选图标集合，用 256 项整数表 `0x4a35fc／0x4a39fc`（横 ×66、纵 ×72、右移 16，中心 y−28，六项步进 +1、七项索引掩 `~7`）排位；换帧走 `0x45e5a6`（循环）／`0x45e5d9`（往返），展开走 `0x45e80d`（容差 2、步进上限 8）（static-derived）。
- 重制 `CommandPresentationRules`／`BattleCommandMenu` 消费 `menu_layout.py` 生成的 `native_layout.json` 与 `command_frames.py` 的源帧；三个 helper 在隔离 x86 仿真里逐次执行，Godot 用同一输入逐步比较（static-derived）。
- 差异：菜单更新频率按每秒 60 次是重制时钟选择（provisional）；菜单事件位的完整语义、行动后留哪几项的上层选择不由本包证明（未读）。

## 证据

**static-derived（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`）**

| 内容 | 原版入口 | 读数 |
| --- | --- | --- |
| 菜单对象过程 | `0x43e5d0` `defProcBattleCommandString`（process table slot 14） | 菜单入口；`0x4038a0` 是 slot 23 `defProcAnimalDefense`，不是菜单 handler；`0x45b554` 是输入位测试 |
| 集合字符表 | `0x4784fc` `nopqz`／`0x478508` `nopqzw`／`0x478514` `nopqzv`／`0x478520` `nopqzvw`／`0x478530` `oqz`／`0x478538` `oqzv`／`0x478540` `oqzw`／`0x478548` `oqzvw`／`0x478554` `rtus` | 字符 `n..z` ＝ 对象 110..122（move／attack／item／wait／use／give／equip／drop／magic／special／ok／cancel／status，OBJ-ALL.H） |
| mode 分支 | `0x43eb32..0x43eb39` `add esi,2; dec ecx` | mode 1 跳过首字符 Move（不是去掉 Wait）；mode 2 是 `oqz` 系列；玩家入口 `0x443a3c` 调 mode 0、`0x4440e1` 调 mode 1、`0x44416f` 调 mode 3（道具子菜单） |
| `0x409090` | 按 actor 索引读武器表 `+0x84`，另有 `+0x18c／+0x2c` 分支 | 决定是否跳过 `o`（攻击）；不是「本行动已攻击」布尔值 |
| 布局算术 | `0x43ebf3..0x43edc1` | `step = 256 / N`（N＝6 时 +1），起始角 192，`index = angle & mask`，`x = cx + (table_x[index]·66) >> 16`，`y = cy + (table_y[index]·72) >> 16`，`angle = (angle − step) & 255`；中心 `(owner_x, owner_y − 28)`；边距 `0x15` 与地图尺寸 `*0x4c0934／38 << 5` 做边界偏移 |
| 目标坐标 | `0x43ed1a` | 图标在中心生成，目标写 `+0x9e`（x）／`+0x9c`（y）；`0x43e5d0` 的 `0x20000000` 事件分支读它们并调 `0x45e80d` |
| 展开步进 | `0x43e72a..0x43e73b` → `0x45e80d` | 两轴距离都 ≤2 才吸附；否则距离算术右移一位，限制在 ±8 |
| 悬停分支 | `0x43e7ea..0x43e822` | 事件位 `0x02000000` 置对象标志、调 `0x45f0d1`，按 `+0x94` 选 `0x45e5a6` 或 `0x45e5d9`；`0x43e824..0x43e841` 另一分支从保存字段恢复帧号、计数与帧数 |
| 初始化计数 | `0x43e786` | 写 `+0x7c = 0x00060006`（当前／重置计数都为 6） |
| 悬停缩放 | `0x43e7b6` | 16.16 值 `0x15800`；原图 42 px |
| 选择交接 | `0x43e887..0x43e891` | 图标 `+0xa8` 的 16 位值写入 owner `+0x8c` |
| 循环换帧 | `0x45e5a6..0x45e5d8`（18 条指令） | `+0x7c` 减 1，≥0 不推进；否则从 `+0x7e` 恢复计数、帧号 `+0x30` 加 1、剩余帧 `+0x78` 减 1，耗尽时从 `+0x7a` 恢复并回绕；计数 D 时每 D+1 次调用推进一帧 |
| 往返换帧 | `0x45e5d9..0x45e641` | 两端不重复：三帧为 0→1→2→1→0 |

**resource-derived**

| 内容 | 出处 |
| --- | --- |
| 图标身份、帧数、循环方式 | `data\obj-051.obs` 的 `defProcBattleCommandString` Data3／Data8（Data3 非零循环、零往返）；BCMD SHP：移动／攻击／道具／待机／特殊技各 3 帧、状态 5 帧（`BCMD01／02／03／04／10／13_1.SHP` 起），原包字节 SHA-256 与 manifest `source_sha256` 一致 |
| 普通攻击程序 | `data\ANIMAL.TXT`（CP950，与 tracked 副本逐字节相同）：雷歐納德 `aniDelay,12,aniSetShape,1,aniDelay,8,aniSetShape,2,aniDelay,3` / `aniInsertAttackFlash,-90,-120,aniSetShape,3,aniDelay,30` |

**原函数执行对照**：`hsl_native_presentation_probe.py` 装入 PE sections，显式构造栈、返回地址与对象字段，每次只允许三个 helper 之一的指令地址、上限 256 条、确认返回到停止地址。换帧覆盖循环／往返各 1、2、3、5 帧，每例初态＋84 次更新，共 680 个帧号样本；展开覆盖垂直、斜向、负坐标、临界吸附、非零起点六条轨迹。输出 [native_presentation_helpers.json](native_presentation_helpers.json)。

**runtime-measured（原版录像，历史样本）**：`runtime_observations/presentation_reference/media/` 里 `original-hover-loop.mp4`（持续悬停循环，不含进入／退出）、`original-five-menu.mp4`（移动后攻击移到顶点、其余五项重排）、`menu_after_both-original.mp4`（第一战雷歐納德移动后普攻，目标 22→2 HP，演出后直接进入下一角色）；覆盖清单 `cases.json` 无一条标 `matched`。

## 重制接线

- `tools/hsltools/assets/menu_layout.py` → `content/imported/hsl/shared/command_menu/native_layout.json` → `game/battle/runtime/CommandPresentationRules.gd`（`centers`）。
- `tools/hsltools/assets/command_frames.py` → `source_objects.json`／manifest → `game/battle/scene/BattleCommandMenu.gd`（`frame_at(..., looped)`、`opening_step`）。
- 普通攻击：`PYTHONPATH=tools python3 -m hsltools.assets.combat_animation --bind-programs` 按 [ANIMAL 完整程序](animal_program_execution.md) 保留指令原序（Delay 的设置与退出各占一次调用、SetShape 让出、Flash 继续读后继指令），雷歐納德帧 1／2／3 出现在第 14／24／29 次调用、末段等待收束于 60 次。
- provenance 写法：`## provenance:` 维度写 `static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md`。`CommandPresentationRules.gd` rules：0x43ea30 整数表 0x4a35fc／0x4a39fc 与六／七项索引；`BattleCommandMenu.gd` layout：经 CommandPresentationRules 取整数中心。
- provisional：菜单更新按每秒 60 次；替换点是 [原版 tick 速率](../runtime_observations/original_tick_rate/README.md) 的调度结论。

## 复现

`uv run --no-project --with 'unicorn>=2,<3' python tools/hsl_native_presentation_probe.py --output ignored/presentation-reference/native-helpers-rerun.json`，与 `native_presentation_helpers.json` 比较；数据侧 `python3 tools/hsl.py check menu_layout command_frames`。

## 边界

- 事件位 `0x02000000`／`0x20000000` 由哪种输入产生未读，不把它们命名为已证明的 hover-enter／leave。
- 行动后实际留哪几项由 `0x443330` 玩家过程与行动交接决定，本包只证明集合与几何；行动收尾见 [公共行动恢复](original_action_state_machine.md)。
- 函数调用次数等价不证明原主循环每秒调用次数、Wine 显示帧率，也不能推出 ANIMAL `aniDelay` 的秒数。
- 完整施法、受击、死亡、战利品的时间轴不由菜单 helper 推出。

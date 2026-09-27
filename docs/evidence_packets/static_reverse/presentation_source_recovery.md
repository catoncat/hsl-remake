# 原版表现逻辑的离线恢复：行动菜单与攻击动画

> evidence: static-derived · status: live · functions: 0x409090, 0x43ea30, 0x448840, 0x45b554, 0x45e5a6, 0x45e5d9, 0x45e80d, 0x45f0d1 · tools: hsl_exe_decompile.py, hsl_native_stats_probe.py, hsltools/assets/combat_animation.py, hsltools/assets/command_frames.py · updated: 2026-09-11

研究日期：2026-09-11。首次核对发生于 15:28–15:33 UTC（台北 23:28–23:33），随后补充为可接续的研究文档。

本包记录已经实际读取的原版资源、EXE 指令、成功与失败的复跑方法，以及尚未证明的部分。它是长期证据入口，不是新的项目状态表。当前产品进度与交付范围仍看 [PROJECT.md](../../PROJECT.md)。

## 1. 给正在做画面对照的 agent

用户提出的问题是：Wine 下反复操作、截图和录屏成本很高，能否从原版程序与资源直接恢复画面和动画。随后要求把研究细节保存在项目里，供另一条正在进行表现修复的对话读取。

本次查证支持把调查顺序调整为：**先读资源和动作定义，再追驱动它们的程序逻辑，再做离线表现验证，最后用有明确问题的原版短片验证剩余差异。** 这是一条有实际证据的研究路线；不是宣称已经恢复完整引擎，也不撤销既有人工验收。

接手时先读第 3–6 节的具体发现，以及第 10 节的建议步骤。需要复核时直接执行第 8 节；不必先重新操作原版。

必须保持的区分：

- 资源包里有原始脚本、表格和图像，不代表我们拥有完整原始 C/C++ 开发工程。
- 提取全部帧，不代表已经恢复选择帧、计时、插入特效、切镜、结束动作的逻辑。
- 指令中有延迟计数，不代表该数字就是毫秒，或可以直接除以 60。
- 菜单生成函数能计算某个菜单集合，不代表已经证明玩家在哪个行动阶段会请求该集合。
- 现有状态覆盖清单、人工图证和声音参考继续有效。离线分析可以回答其中一部分问题；不能把缺录像的 case 自动改为 `matched`。

用户此前允许改善交互、规则与配乐，本研究不把项目目标改成全游戏逐像素复刻，也不自动扩大到第二关、全装备系统或通用 Windows 模拟器。

## 2. 实际检查的输入与研究范围

### 2.1 本机输入

| 输入 | 位置／身份 | 本次用途 |
| --- | --- | --- |
| 原版 EXE | `$HSL_ORIGINAL_DIR/hsl01.exe`，798720 字节 | 直接读取菜单和动画更新指令、菜单字符表 |
| EXE SHA-256 | `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7` | 本包所有绝对虚拟地址的版本约束 |
| 原版资源包 | `$HSL_ORIGINAL_DIR/hsl.pak` | 逐成员核对菜单源帧与 `data\ANIMAL.TXT` |
| 原始攻击定义的 SHA-256 | `e27783ef3148bad8523af95c7d111f1a3ed66c7c0844c7b7cfdabefb4ef9b4ea` | 包中 ANIMAL 文本与 tracked 文本逐字节一致 |
| 首次研究的 Git 基线 | `9c9a63b`，`main` | 下文对重制版实现的观察基线，不代表后续并行修改 |
| 首次研究 raw 输出 | `ignored/source-route-proof-23313/` | 三个函数的反汇编，继续保持 ignored |

首次研究只读原作文件和现有工程，没有启动 Wine、注入游戏输入、修改 EXE、安装或修复反编译插件，也没有修改游戏代码。现有菜单帧和攻击导入器是项目原有成果；本次做了源包复核与新的指令阅读，不把这些导入器记成本次新实现。

写本文时另一对话已在修改菜单、状态和装备表现，包括 `BattleCommandMenu.gd`、`BattleStatusPanel.gd`、`hsltools/assets/command_frames.py` 等。接手必须重新看 `git status` 和实际 diff；不要用本文中的基线代码描述覆盖并行成果。特别是“六类、20 帧”指本次核对的明确子集，不是未来整个 BCMD 资源库的总数。

### 2.2 证据分层

| 分类 | 本包中的内容 | 能支持的结论 |
| --- | --- | --- |
| `resource-derived` | PAK 源字节、SHP 帧数、ANIMAL token 与参数 | 帧存在、脚本顺序和数字确实来自原包 |
| `static-derived` | 指定 EXE 中的指令、字符表和已建立的对象编号关联 | 分支、内存写入、计数和布局算术 |
| `runtime-measured` | 已有 presentation reference 包 | 特定路线中实际看到／听到的现象；本次没有新增原版 runtime 样本 |
| `provisional` | 当前 8 fps、ANIMAL 的 60 tick/s 映射、未追通的事件语义 | 可替换的重制参数或研究假设 |
| `negative-evidence` | 本次反编译失败；某条记录不包含悬停进入／退出 | 该工具或证据目前不能支持对应声明 |

原始函数的隔离仿真沿用现有项目证据约定：原版指令与合成输入要分开记录，不能称为完整原作现场测量。详见 [CONTEXT.md](../../../CONTEXT.md)。

## 3. 已直接从资源包复核的内容

### 3.1 行动菜单的六类 20 帧

原有入口是 [hsltools/assets/command_frames.py](../../../tools/hsltools/assets/command_frames.py)，生成数据是 [command_menu/manifest.json](../../../content/imported/hsl/shared/command_menu/manifest.json)。定义的帧数来自 [ui_resources.json](../../../content/imported/hsl/chapter01/ui_resources.json)。

| 命令 | 源文件组 | 已核对帧数 |
| --- | --- | ---: |
| 移动 | `SHAPE\BCMD01_1.SHP` 起 | 3 |
| 攻击 | `SHAPE\BCMD02_1.SHP` 起 | 3 |
| 道具 | `SHAPE\BCMD03_1.SHP` 起 | 3 |
| 待机 | `SHAPE\BCMD04_1.SHP` 起 | 3 |
| 特殊技 | `SHAPE\BCMD10_1.SHP` 起 | 3 |
| 状态 | `SHAPE\BCMD13_1.SHP` 起 | 5 |

首次原包复核逐个查找 `@:\` 开头的 PAK 成员，要求唯一匹配，并计算原始 SHP 字节的 SHA-256，与 manifest 的 `source_sha256` 比较。实际输出是 `ORIGINAL_PAK_MENU_BYTES_PASS: 20 frames`。

这比仅检查 PNG 文件存在多了一层来源复核，但仍不证明动画速度、循环方向、悬停进入／退出、点击状态、缩放、颜色和布局。源文件数字后缀是定位方式；播放方式还需要 handler 证据。

`python3 tools/hsl.py check command_frames` 在首次研究时也输出 `COMMAND_FRAMES_CHECK_PASS`。该检查核对定义集合、帧数与 PNG 哈希；它不重新读取原版 PAK，不能把它与上述原包复核混为一项。

### 3.2 原始攻击动作定义

原有入口是 [hsltools/assets/combat_animation.py](../../../tools/hsltools/assets/combat_animation.py)。本次确认 PAK 中的 `data\ANIMAL.TXT` 与 [tracked ANIMAL.TXT](../../../content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT) 字节完全相同；文本按 CP950 解码。

雷欧纳德对应的原文如下：

```text
code     = SID_PLAYER0
shape    = ANIMAL\P001_001.SHP
number   = 5
action   = aniDelay,12,aniSetShape,1,aniDelay,8,aniSetShape,2,aniDelay,3
action   = aniInsertAttackFlash,-90,-120,aniSetShape,3,aniDelay,30
```

由此可以直接保留延迟 token `12/8/3/30`、显式换帧 `1/2/3`，以及闪光插入在 `aniSetShape,3` 之前、参数为 `(-90,-120)`。当前导入器把起始帧建模为 0，生成 `[0,1,2,3]` 的 timeline；起始状态与每个 opcode 的完整执行语义仍须结合原版解释器核对。

当前导入器也读取 SHP 绘制锚点、攻击闪光和雷欧纳德特殊技帧。其 `--check` 首次研究输出 `COMBAT_ANIMATION_CHECK_PASS`。这并不意味着本次重新逐帧检查了所有攻击 SHP 的原包字节；本次额外原包复核的是 ANIMAL 文本和上面的 20 个菜单帧。

尚未解决的边界：

- manifest 中 `presentation_fps: 60` 是暂定映射，原文 `aniDelay,12` 没有直接说明“12/60 秒”。
- `aniDelay` 的解释器与第 5 节的通用 SHP 延迟 helper 不是已经证明相同的计时机制，不能直接把后者的 `D+1` 套给 ANIMAL。
- 第五张攻击图被重制版当作受击姿态，是已记录的图像观察和重制绑定，原版受击 handler 尚未证明。
- `k_action` 不能当作 sprite facing 的同义词；导入器已经分别保留 `source_k_action` 与人工检查的 `sprite_facing`。
- 一条攻击者脚本不包含完整目标镜头、受击、恢复、死亡、战利品、声音派发和回到地图的全部合同。

因此有两种不同的工作：完整保留源脚本里的事件；追解释器和调用方如何执行它们。只提取帧与 delay 列表会丢掉其他 opcode 的行为。

## 4. 行动菜单函数：对象身份、布局与旧摘要矛盾

### 4.1 应从哪个函数继续

现有 [core_logic.json](../../../content/generated/hsl/static/hsl01/core_logic.json) 中的 `bcmd_click_process`、`player_menu_entry` 和 `bcmd_icon_codes` 提供入口关联：

| 地址 | 已有定位 | 本次检查程度 |
| --- | --- | --- |
| `0x43ea30` | 行动菜单集合选择与对象生成 | 已导出并逐段阅读 |
| `0x43e5d0` | `defProcBattleCommandString`，process table slot 14 | 已导出并阅读布局过程、动画分支及点击交接 |
| `0x45e5a6` | 通用循环帧更新 helper | 已导出并阅读完整 18 条指令 |
| `0x443330` | 玩家对象 process，消费菜单结果 | 已有入口资料；本次未追完 |
| `0x4038a0` | `defProcAnimalDefense`，slot 23 | 已有纠错资料；不是菜单 handler，本次未重新导出 |

不要因为旧记录把 `0x4038a0` 称作 `player_command_process` 就从它研究菜单。原包 process table 关联已在 compact packet 中纠正，slot 14 才是菜单入口。`0x45b554` 是 input bit test，也不是菜单派发器。

### 4.2 菜单字符表确实在 EXE 中

补文档时直接按 PE section 将虚拟地址映射到文件字节，并以 UTF-16LE 读取以下固定长度片段：

| 虚拟地址 | 实读字符 | 含义／边界 |
| --- | --- | --- |
| `0x4784fc` | `nopqz` | 移动、攻击、道具、待机、状态 |
| `0x478508` | `nopqzw` | 上述集合加特殊技 |
| `0x478514` | `nopqzv` | 上述集合加魔法 |
| `0x478520` | `nopqzvw` | 上述集合加魔法、特殊技 |
| `0x478530` | `oqz` | 攻击、待机、状态 |
| `0x478538` | `oqzv` | 上述三项加魔法 |
| `0x478540` | `oqzw` | 上述三项加特殊技 |
| `0x478548` | `oqzvw` | 上述三项加魔法、特殊技 |
| `0x478554` | `rtus` | 使用、装备、丢弃、交换 |

字符到对象的关联来自 [OBJ-ALL.H](../../../content/imported/hsl/global/tables/OBJ-ALL.H) 与现有 `bcmd_icon_codes`：`n/o/p/q/r/s/t/u/v/w/x/y/z` 分别为对象 `110..122`，即 move/attack/item/wait/use/give/equip/drop/magic/special/ok/cancel/status。

**需要纠正的旧摘要：** `core_logic.json` 的 `player_menu_entry.menu_builder.param_2_modes["1"]` 仍写着“variant without wait entry”。本次指令在 `0x43eb32..0x43eb39` 对该分支执行 `add esi,2; dec ecx`，而上述完整集合的首个 UTF-16 字符是 `n`（Move）。这个局部操作是跳过 Move，不是去掉 Wait。

同样，mode 2 的基础片段包含 `o/q/z`，不能只用“special/magic-only subset”概括。本文保留冲突并给出复核方法，没有悄悄改掉全局 compact packet 或给玩家状态重新命名。下一次正式恢复这些调用关系时，应同步修正旧摘要及其 checker。

**这仍然没有证明“行动后一定留下哪两个菜单”。** `0x409090` 的结果影响是否跳过 `o`（攻击），调用方传入的 mode、能力与状态条件也参与集合选择。即使某种合成输入可以产生两个图标，也需要追 `0x443330` 和行动交接才能证明玩家实际会进入该分支。

### 4.3 布局算术可以从指令读出

以下是 `0x43ea30` 中可复核的局部运算，不是已经执行验证过的完整菜单重实现：

| 指令区间 | 实际操作 |
| --- | --- |
| `0x43ebf3..0x43ec10` | `0x100 / ecx` 整数除法，保存步进；初始角度索引为 `0xc0`（192） |
| `0x43ec14..0x43ec25` | 七项时查表索引 mask 改为 `0xfffffff8`；六项时步进加 1 |
| `0x43ec29..0x43ec3f` | 读取 owner 的 x/y；中心 y 先减 `0x1c`（28） |
| `0x43ec6c..0x43eca0` | 查 `0x4a35fc` 和 `0x4a39fc` 两张表；x 分量乘 66 后算术右移 16，y 分量乘 72 后算术右移 16 |
| `0x43eca2..0x43ed06` | 用 `0x15`（21）边距和 `*0x4c0934/38 << 5` 检查目标坐标，累计偏移 |
| `0x43ed0a..0x43ed6e` | 在中心生成对象；写 owner 关联和目标坐标；将图标连成列表 |
| `0x43ed74..0x43ed84` | 角度索引减步进，再 `& 0xff` |
| `0x43eda6..0x43edc1` | 遍历已生成图标，对目标坐标应用累计边界偏移 |

忽略集合构造、溢出与边界分支，仅把中间坐标算术写成便于阅读的形式：

```text
N = 几何使用的项数（注意有跳过攻击的分支，不能总用源字符串长度）
step = integer_divide(256, N)
if N == 6: step += 1
mask = 0xfffffff8 if N == 7 else 0xffffffff
angle = 192
center = (owner_x, owner_y - 28)

index = angle & mask
target_x = center.x + arithmetic_shift_right(table_x[index] * 66, 16)
target_y = center.y + arithmetic_shift_right(table_y[index] * 72, 16)
angle = (angle - step) & 255
```

这里只给出指令层面确定的查表算术；本次没有恢复两张表的初始化与完整坐标调用链，也没有执行原版菜单函数来导出全部图标目标坐标。不要把 table_x/table_y 直接替换成未经核对的浮点 sin/cos，也不要先写死像素坐标再宣布等价。

额外值得继续追的部分：`0x43ed1a` 生成对象时传入的是中心坐标，目标坐标随后写入 `object+0x9e`（x）和 `object+0x9c`（y）。`0x43e5d0` 的 `0x20000000` 事件分支又读取这些目标，并调用 `0x45e80d` 更新位置。这是菜单展开过程的直接调查入口，helper 的速度与终止语义尚未恢复。

这解释了为什么“按剩余数量画一个数学上的圆”仍可能有差异：原版有整数查表、横纵不同系数、特定项数处理、中心偏移、边界修正与位置更新过程。

## 5. 悬停与循环更新：已经知道什么

### 5.1 菜单对象的分支

在 `0x43e5d0` 的更新路径中，以下指令不依赖反编译插件即可检查：

| 指令区间 | 可确认的行为 | 尚未确认的语义 |
| --- | --- | --- |
| `0x43e7ea..0x43e822` | 测试传入事件位 `0x02000000`；设置对象标志，调用 `0x45f0d1`；按 `object+0x94` 是否非零选择 `0x45e5a6` 或 `0x45e5d9` | 事件位如何由输入／命中测试产生；另一 helper 的完整行为 |
| `0x43e824..0x43e841` | 另一分支恢复帧号、延迟计数与帧数，来源为保存的初始字段 | 与鼠标移出、取消、隐藏的完整对应关系 |
| `0x43e786` | 写 `object+0x7c = 0x00060006`，两个相邻 16 位值都为 6 | 此初始化事件的调用时序；不能单独换算原版 fps |
| `0x43e887..0x43e891` | 将图标 `+0xa8` 的 16 位值写入 owner 的 `+0x8c` | 玩家对象之后如何消费每种选择 |

现有原版 `original-hover-loop.mp4` 提供“持续悬停有循环动画”的独立观察，因此事件位分支是合理的调查方向。但本次没有新增鼠标输入与该事件位的同步观测，文档不把所有位直接命名成已证明的 hover-enter/leave。

### 5.2 `0x45e5a6` 的完整计数机制

函数只包含 18 条已导出的指令。关键位置：

- `0x45e5ad`：对 `object+0x7c` 的 16 位延迟计数减 1。
- `0x45e5b1`：结果大于等于零时直接走不推进分支。
- `0x45e5b3..0x45e5b7`：从 `+0x7e` 恢复延迟计数。
- `0x45e5bb..0x45e5c3`：帧号 `+0x30` 加 1，剩余帧数 `+0x78` 减 1。
- `0x45e5c5..0x45e5cd`：剩余帧数用 `+0x7a` 恢复；帧号减去总帧数，形成循环。

若初始／重置计数为非负整数 D，且每次动画更新恰好调用一次该 helper，则相邻推进要经历 D+1 次调用。这是函数调用次数，不是秒数。当前／重置字段分别为 `+0x7c/+0x7e`；当前／重置帧数为 `+0x78/+0x7a`，都要保留其 16 位读写语义。

已有 [actor_animation_groups.md](actor_animation_groups.md) 独立记录了站立计数 10、行走计数 2，并追到同一 helper，所以对应 11／3 次更新的描述有依据。但不能用站立的 10 代替菜单的初始化计数，也不能把这个结论传播到尚未检查的 ANIMAL opcode。

下一步计时调查应明确：哪个调度器调用它、同一展示帧是否可能调用多次、暂停与切换阶段是否推进、Wine／ddraw 的显示速率是否与游戏更新速率相同。录到 60 fps 视频本身不能回答这些问题。

## 6. 与重制版当前实现的接点

以下是首次研究基线 `9c9a63b` 中 [BattleCommandMenu.gd](../../../game/battle/scene/BattleCommandMenu.gd) 的观察，不是要求还原旧文件：

| 重制版参数／行为 | 基线值 | 来源边界 |
| --- | --- | --- |
| 悬停计时 | `HOVER_FPS := 8.0`，用 delta 累加 | 暂定速度，非原版调度器恢复 |
| 布局 | `RADIUS := 72.0`，按 `TAU / active_ids.size()` 均分 | 浮点圆形排列，未消费原版整数表与六／七项分支 |
| 菜单中心 | `anchor + Vector2(0,-32)` | 当前表现选择；原版生成函数中局部偏移为 -28，仍需对齐坐标合同 |
| 悬停大小 | 42 → 54 | 当前交互参数，不等于原版缩放过程 |
| 帧复位 | 换 hovered id 时归零；非 active 图标回第一帧 | 当前实现合同，仍需核对原版进入／退出与点击阶段 |

原版局部的 -28 与重制版 -32 不是可以孤立替换的“4 像素 bug”结论。Camera、viewport/logical/world/grid、脚点、SHP draw origin、命中区域和边界修正必须一起检查。

战斗部分继续使用现有 `CombatPresentationTiming` 和共享演出模块；不要把原版 handler 的调查变成第二套战斗状态机。HP、行动预算、目标与结果继续由 `BattlePlayLoop` 拥有。资源解析器与 EXE 仿真只在开发工具层使用，游戏运行时只消费被整理过的数据。

## 7. 已有隔离执行实例及其适用范围

[hsl_native_stats_probe.py](../../../tools/hsl_native_stats_probe.py) 已经把指定 EXE 的 `0x448840` 放入隔离 x86 仿真，构造 PLAYERS／ITEM／TYPE 输入，读取结果。已有报告见 [first_battle_template_stats.md](first_battle_template_stats.md) 和 [对应 JSON](first_battle_template_stats.json)。本次只是检查了这套既有实现和报告，没有重新执行属性探针。

可复用的具体约束包括：核对 EXE 哈希、按 PE sections 装载、显式构造栈和输入、限制可执行地址、限制指令条数、确认返回到预定停止地址。既有脚本使用 10000 条指令预算，并在预算耗尽时明确失败。

这证明“完全不启动 Wine，执行依赖可控的原始函数”在本项目有先例。它不证明菜单／渲染已经能用同一合成输入运行。菜单生成涉及对象分配、列表、表格和状态；展开与帧更新又有其他调用。需要逐个盘点依赖，不能把未知函数全部 stub 成成功再把输出当真值。

建议先选 `0x45e5a6` 这种输入输出很小的 helper，再考虑菜单布局。探针应记录输入、原版返回与字段变化，并与重制实现的同一输入比较。PNG contact sheet、离线预览或 Godot Movie Maker 可以检查复原后的表现，但应明确标为离线渲染；尚未建立一个原版引擎离线重放器。

## 8. 可复跑命令

以下命令从仓库根目录执行。只读取本机原作文件；导出写入 `ignored/`。不启动原版、不控制键鼠、不覆盖 tracked 资源。

### 8.1 已有导入结果校验

```sh
/opt/homebrew/bin/python3 tools/hsl.py check command_frames
/opt/homebrew/bin/python3 tools/hsl.py check combat_animation
```

如果另一 agent 正在扩展命令集合，应先确认 importer 与 manifest 是否已经同时更新。不能为让旧检查通过而删掉其新增命令。不要把 `--check` 换成无参数生成或 `--pak` 导入，它们会写产品资源。

### 8.2 复核原版 PAK 的 20 个菜单帧与 ANIMAL 文本

```sh
/opt/homebrew/bin/python3 - <<'PY'
import hashlib
import json
import re
import os
from pathlib import Path
from tools.hsl_resource_scanner import (
    find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes,
)

pak = Path(os.environ['HSL_ORIGINAL_DIR'], 'hsl.pak')
packages = find_decoded_paks_packages(pak)

def source_bytes(member):
    matches = []
    for package in packages:
        record = find_paks_record_by_name(package['records'], '@:\\' + member)
        if record:
            matches.append((package, record))
    if len(matches) != 1:
        raise ValueError(f'Missing/ambiguous PAK member: {member}, matches={len(matches)}')
    package, record = matches[0]
    return read_paks_record_bytes(
        package['path'], record,
        data_end_offset=int(package['paks']['candidate_index_offset']),
    )

menu = json.loads(Path('content/imported/hsl/shared/command_menu/manifest.json').read_text())
expected = {'move': 3, 'attack': 3, 'item': 3, 'wait': 3, 'special': 3, 'status': 5}
count = 0
for name, frame_count in expected.items():
    frames = menu['commands'][name]['frames']
    if len(frames) != frame_count:
        raise ValueError(f'Unexpected frame count for {name}: {len(frames)}')
    for frame in frames:
        raw = source_bytes(frame['source_member'])
        if hashlib.sha256(raw).hexdigest() != frame['source_sha256']:
            raise ValueError(f"Source digest mismatch: {frame['source_member']}")
        count += 1
    print(f'{name}: {len(frames)} original SHP frames verified')
print(f'ORIGINAL_PAK_MENU_BYTES_PASS: {count} frames')
raw = source_bytes('data\\ANIMAL.TXT')
tracked = Path('content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT')
if raw != tracked.read_bytes():
    raise ValueError('ANIMAL.TXT differs from original PAK member')
print('ORIGINAL_ANIMAL_TEXT_BYTES_PASS')
print('ANIMAL sha256:', hashlib.sha256(raw).hexdigest())
block = next(b for b in raw.decode('cp950').split('[animal]')
             if re.search(r'^code\s*=\s*SID_PLAYER0\s*$', b, re.M))
for line in block.splitlines():
    if re.match(r'^(code|shape|number|action)\s*=', line):
        print(line)
PY
```

这里明确选择原研究的六类，允许 manifest 后续包含更多命令；额外命令不包含在本次 20 帧结论中。

### 8.3 绕过失效插件，重新导出三个函数

```sh
/opt/homebrew/bin/python3 - <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path

exe = Path(os.environ['HSL_ORIGINAL_DIR'], 'hsl01.exe')
expected = 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7'
actual = hashlib.sha256(exe.read_bytes()).hexdigest()
if actual != expected:
    raise ValueError(f'Unsupported EXE sha256: {actual}')
out = Path('ignored/presentation-source-recovery')
out.mkdir(parents=True, exist_ok=True)
print('EXE sha256:', actual)
for address in ('0x43e5d0', '0x43ea30', '0x45e5a6'):
    result = subprocess.run(
        ['r2', '-N', '-e', 'bin.relocs.apply=true', '-e', 'scr.color=0',
         '-q', '-c', 's ' + address, '-c', 'af', '-c', 'pdfj', str(exe)],
        env={**os.environ, 'R2_NOPLUGINS': '1'},
        capture_output=True, text=True, timeout=30, check=True,
    )
    data = json.loads(result.stdout)
    ops = data.get('ops')
    if not ops:
        raise ValueError(f'No decoded instructions at {address}: {result.stderr}')
    lines = []
    for op in ops:
        pc = op.get('addr', op.get('offset'))
        if pc is None:
            raise ValueError(f'Instruction has no address: {op}')
        lines.append(f"{pc:#x}  {op.get('disasm', op.get('opcode', ''))}")
    target = out / (address + '.asm')
    target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    (out / (address + '.json')).write_text(result.stdout, encoding='utf-8')
    print(f'{address}: {len(ops)} instructions; {target}')
PY
```

本机研究时为 radare2 `6.2.0`、ABI `132`。原始结果分别为 353、288、18 条指令。该数量用于识别原始记录，不应作为不同反汇编器版本的唯一通过条件；仍须确认起始地址、分支及关键 opcode。

`R2_NOPLUGINS=1` 绕过插件加载，`-N` 避开个人启动脚本；这里没有加载旧 `hsl01_core` 项目，也没有使用 `pdg/pdd`。`bin.relocs.apply=true` 是分析配置，不是向原 EXE 写补丁。这条命令只做静态读取。

### 8.4 不依赖 r2，复核菜单字符表

```sh
/opt/homebrew/bin/python3 - <<'PY'
import hashlib
import struct
import os
from pathlib import Path

raw = (Path(os.environ['HSL_ORIGINAL_DIR'], 'hsl01.exe')).read_bytes()
expected = 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7'
if hashlib.sha256(raw).hexdigest() != expected:
    raise ValueError('Unsupported EXE')
pe = struct.unpack_from('<I', raw, 60)[0]
n = struct.unpack_from('<H', raw, pe + 6)[0]
optional = struct.unpack_from('<H', raw, pe + 20)[0]
base = struct.unpack_from('<I', raw, pe + 52)[0]

def bytes_at(va, count):
    rva = va - base
    for i in range(n):
        _, section_rva, size, offset = struct.unpack_from(
            '<IIII', raw, pe + 24 + optional + 40 * i + 8)
        if section_rva <= rva and rva + count <= section_rva + size:
            start = offset + rva - section_rva
            return raw[start:start + count]
    raise ValueError(f'Address not backed by section bytes: {va:#x}')

tables = [(0x4784fc, 'nopqz'), (0x478508, 'nopqzw'),
          (0x478514, 'nopqzv'), (0x478520, 'nopqzvw'),
          (0x478530, 'oqz'), (0x478538, 'oqzv'),
          (0x478540, 'oqzw'), (0x478548, 'oqzvw'), (0x478554, 'rtus')]
for va, expected_text in tables:
    text = bytes_at(va, len(expected_text) * 2).decode('utf-16le')
    if text != expected_text:
        raise ValueError(f'Table mismatch at {va:#x}: {text!r}')
    print(f'{va:#x} {text}')
print('BCMD_STRING_TABLES_PASS')
PY
```

此处使用的是 PE 虚拟地址映射，不能把 `0x4784fc` 直接当作文件偏移 seek。

## 9. 工具故障、原始产物与复现边界

### 9.1 C 伪代码导出失败

本次实际尝试了 [hsl_exe_decompile.py](../../../tools/hsl_exe_decompile.py)，对 `0x43e5d0` 和 `0x43ea30` 使用默认 `pdg` 后端，两次都失败，退出码 1。错误包含：

```text
ABI mismatch: Expect 132 vs 110 ... libcore_pdd.dylib
Po is deprecated, use 'P [prjname]' instead
variable 'r2dec.*' not found
variable 'r2ghidra.*' not found
No previous search done
```

错误中的 `libcore_pdd` ABI 不匹配和 `pdg`／旧项目配置不可用要分别记录，不能只凭这一段输出断言唯一根因。成功路线是第 8.3 节的无插件反汇编；本次没有修复 C 反编译环境，也没有得到这两个函数的新 `.pdg.c` 文件。

旧目录 `ignored/static/hsl01/decompiled/` 当时只有其他函数的历史 `.pdg.c`，不能把它们误认为本轮成功生成的菜单 C 代码。后续确实需要高层反编译时再单独修工具环境，不要让这件事阻塞已经可读的窄指令分析。

### 9.2 r2 JSON 字段差异

首次解析直接反汇编结果曾因 `KeyError: 'offset'` 失败。检查 `pdj` 的真实输出后发现当前版本字段是 `addr`；更正后成功导出。第 8.3 节兼容两种字段并在都缺失时失败，避免生成缺地址的伪证据。

### 9.3 已保存的 raw 文件

以下是首次研究文件的 SHA-256，可用于检查同机文件是否仍是当时版本；它们不是 tracked 产品依赖：

| 文件（相对 `ignored/source-route-proof-23313/`） | 指令行数 | SHA-256 |
| --- | ---: | --- |
| `0x43e5d0.asm` | 353 | `a9a5dae58c49153e5f84a9744c62078dbb00bfcf7f994a1a0f9730891ffc7b53` |
| `0x43ea30.asm` | 288 | `cb7338f1a8e9515ebddb447aecd0ec81d1627f17aecb10e47a2e3165e7ca69a9` |
| `0x45e5a6.asm` | 18 | `a18637f22e8ecf1f8fe10d344b29e0f47ef14abf4abf409172c8f0947293bcfe` |

反汇编器生成的符号名或格式变化会改变文本哈希；真正的版本边界仍是 EXE 哈希和相应机器指令。删除 ignored 目录后，可以从第 8 节重新生成，不需要依赖会话录制或旧临时路径。

本机 Chat On Steroids 录制的补充定位是 session `2026-09-11-831d7d09`：`TZ` 为 PAK 核对，`T18` 为成功反汇编，`T10` 为失败的反编译结果，`T13` 为 JSON 字段诊断。接手可先 `session search` 搜索 `source-route-proof-23313` 再读取该 session。录制只用于排查历史命令，不作为产品输入；本文已保存继续研究所需的实质内容。

## 10. 建议接续：用行动菜单做一个完整样板

这是研究建议，不是宣称下列实现已经完成。已有明确问题才继续原版采样；若某个边界只影响可接受的重制选择，应保留来源说明并推进产品。

### 步骤 A：完成资源与对象定义关联

保留六类 20 帧的来源复核；扩展命令时复用同一 importer。进一步读取原包中 `obj_BCmd*` 的对象定义，确认帧起点、数量、初始计数、`Data8/Data9` 和 process 绑定。不要仅按文件名数字猜语义，也不要把新增素材误当作已实现玩法。

交付应是可复跑提取与 compact 字段，而不是一堆截图。已知入口为 `ui_resources.json`、`OBJ-ALL.H`、resource inventory 和 `bcmd_click_process.obs_join`。

### 步骤 B：恢复菜单状态选择，再恢复几何

从 `0x443330 → 0x43ea30` 的调用点追 mode 和能力／状态判断，明确未移动、已移动、已攻击但仍可移动、移动后攻击、取消、查看状态等情形。把致死、非致死与战利品阶段分开。

先修正 mode 1 的旧摘要矛盾；再用显式输入核对实际图标列表和顺序。几何应覆盖不同项数、边界与中心展开，不以截图手调半径代替已可读取的算术。候选小样本包括中心、边缘、六／七项和两项；两项必须注明实际触发条件是否已经证明。

交付应包含源输入 → 原版结果 → 重制结果的对照。可以先做纯数据／合成输入探针；尚未运行完整原版函数时，要清楚区分“按指令转写的模型”和“原函数实际执行输出”。

### 步骤 C：恢复悬停与展开的时间轴

继续检查 `0x45e80d`、`0x45f0d1`、`0x45e5d9` 和产生事件位的调用方。覆盖移入、持续、移出、再次移入、按下后移出、重建和隐藏；不能只证明中间循环。先保存更新次数，再找时钟／调度器或做一次有界计时测量。

交付应把“帧序与计数”“进入／退出状态”“每秒调用次数”“位置／缩放过程”分开记录。若只恢复其中一部分，剩余值仍标为 provisional。

### 步骤 D：在重制版验证，再进行少量原版核对

把成果接到现有共享菜单与输入路径，保留 PlayLoop 单一状态所有权。使用必要的定向测试检查真行为差异，例如计数边界、状态选择、取消和几何边缘；不为静态文档新增复述实现的测试。

已有 [presentation_reference/README.md](../runtime_observations/presentation_reference/README.md) 和 `cases.json` 继续管理覆盖。Godot Movie Maker 可以生成确定性参考片，但它是重制版渲染，不是原版证据；真实可见布局和动效变化仍需要人工截图／录屏验收。

原版只对剩余具体问题走已有单步工具，遵守 built-in display、window-only、显式身份和有界动作要求。已有“只录持续悬停”的片段不能证明进入／退出；已有移动后五菜单不能证明非致死攻击后的两菜单策略。

### 后续推广顺序

菜单样板验证这套方法后，再逐步用于 ANIMAL opcode／独立受击过程、施法起手与目标特效、状态／物品／成长／战利品面板。先恢复共享过程与事件顺序，再填不同角色和法术的数据；不要为每张截图创建独立专用行为。

## 11. 本研究的交付与验证边界

首次研究已完成：20 个菜单源帧的 PAK 哈希核对、ANIMAL 文本逐字节核对、两个现有 importer checker、三个函数的直接反汇编与本文中的局部指令分析。补文档时还直接核对了九段菜单字符表和 raw 文件哈希。

尚未完成：原版菜单函数隔离执行、菜单事件位完整语义、每秒更新频率、全部行动状态的菜单选择、原版完整攻击／受击／施法时间轴、全部原版 UI 状态的视觉接受。本文不提升这些项目的完成度，也不更改任何 case 的 matched 状态。

文档变更的收尾需要检查链接、复跑第 8 节的只读／ignored 输出步骤，以及执行项目的 `tools/verify.sh`。共享工作区另有 agent 时，要注意该脚本会清理 `.godot` 和 import cache；可在指定提交加本次文档改动的临时独立验证副本中执行原脚本，记录准确基线，不能把该通过结果说成验证了另一 agent 的未提交修改。最终结果以本次交付报告或提交说明为准。

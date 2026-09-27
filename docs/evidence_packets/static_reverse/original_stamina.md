# 原作战斗气力、装备修饰与绝技门槛

> evidence: static-derived; runtime-measured: 开场实测——整映像模拟器照 0x42da60 进关逐次记录 live +0xe8 写入，Wine 原版首控存档 HSLBAT_first_control · status: live · functions: 0x4075e0, 0x407ec0, 0x40e240, 0x40e2e0, 0x40e590, 0x40e870, 0x42c640, 0x42da60, 0x4368c0, 0x43b4e0, 0x44cb10, 0x461479 · tools: hsltools/data/equipment.py, hsltools/probes/_stamina_trace.py, hsltools/probes/stamina.py, run_stamina_tests.gd · updated: 2026-09-27

2026-09-16。接续 [费用证据](original_skill_resources.md) 和 [AI技能选择](original_ai_skills.md)，本包把普通攻击／受击积气、装备修饰、60上限和现有气刃斩串成同一个可玩资源循环。状态只在BattlePlayLoop保存；原版开场气力见 [开场实测](#开场实测)，整体伤害与全局随机序列仍各有边界。

## 体验缺口与结果

此前每次造成正伤害，已有stamina字段的双方固定增加5，场景另存上限60，而状态条按100绘制。结果是攻击与受击同速积气，实际满气也只填到六成；尚未带该字段的其他角色没有对应资源。凝氣之環和鬼面的源被动列为不支持，玩家无法通过装备改变这一循环。

现在所有活跃角色具有明确的气力字段；普通有效伤害与反击按各自攻击／防守身份积累，最高60。只有源技能书实际授予气刃斩的角色才显示绝技，不能因为出现stamina字段给全队解锁。气刃斩仍用已证实的20×expend费用，恰好20可用，取消不扣，命中或落空都一次扣费。魔法与绝技不套用普通打击积气，没有虚构的施法返还。

## 原指令证据

原EXE SHA-256为`f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。由 [hsltools/probes/stamina.py](../../../tools/hsltools/probes/stamina.py) 生成的 [original_stamina.json](original_stamina.json) 包含168组完整正常返回、实际内存写入和8段字节锚点。Unicorn执行原机器码及真实谓词，不使用stub，不调用RNG，不启动原作游戏；证据等级是`static-derived`，不是实际战局`runtime-measured`。

| 原地址 | 已确认用途 |
| --- | --- |
| `0x40e590..0x40e68c` | 完整攻击／受击气力增长函数，正常返回；只允许两个actor的ST字段改变 |
| `0x40e240`、`0x40e2e0` | 读取actor+0x18c的有效修饰位；加倍谓词查询0x40 |
| `0x44246c..0x44249b` | 普通交锋在有效结果后传入已准备伤害，调用增长；反击复用普通交锋 |
| `0x447e82` | ITEM `st_x2`写入有效掩码0x40 |
| `0x448183` | ITEM `no_addst`写入有效掩码0x400 |
| `0x448709` | 装备效果字并入actor+0x18c，多个相同效果是OR，不重复乘倍率 |
| `0x44b678` | 下一等级阈值计算使用actor+0x9c，辅助核对等级字段 |

增长函数通过object+0xa4找到stride0x1fc的actor记录；读取等级+0x9c、结算后HP+0xd8、最大HP+0xdc、ST+0xe8及效果+0x18c。先取`maxHP=max(10, defender.maxHP)`，伤害上限裁到该值，再按下表计算基础量：

| 条件 | 基础量处理 |
| --- | --- |
| 伤害小于`floor(maxHP/2)` | 初值3 |
| 伤害达到该阈值 | 初值4 |
| 防守者结算后HP≤0 | 加1 |
| 攻击者等级比防守者高超过3 | 减1 |

攻击者增加基础量，防守者增加基础量的两倍。各自有0x40时再加倍，有0x400时保持原ST且不发生写入；禁止增长优先于加倍。最后限到60。奇数最大HP使用整数向下取半，低于10的最大HP仍按10作为分母，过量伤害的阈值判断使用裁剪值。

168组执行覆盖阈值上下、奇数／极小HP、死亡和未死亡、等级差3／4、过量伤害、接近上限／满气，以及加倍／锁定组合。每组核对正常返回、零RNG、准确写入次数与值，以及其他actor字节未变；Godot独立重放这些已保存的原结果。

原调用点传入准备好的伤害，不是事后按剩余HP裁掉的实际损血。当前PlayLoop将现行伤害规则的strike.damage传给新模块，受击后HP单独传入。**增长helper的等价不证明输入它的整套伤害公式也等价**。本次查到的直接调用位于普通物理交锋；技能路径没有这一调用，因此不把该规则扩展到魔法或特殊技。原helper直接收到0也能计算基础量，但正常产品入口只在有效正伤害时调用，落空不积气。

## 开场实测

lane STAMINA-MEASURE，2026-09-26。问题：原版把控制交给每名玩家时，他的气力字 live `+0xe8` 是多少，由谁写入。只写原版事实。

### 进关时写气力字的三处（static-derived）

证据来自 r2 只读反汇编同一 EXE，下一节的写入 EIP 逐一对上。

| 地址 | 何时运行 | 对 `+0xe8` 的作用 |
| --- | --- | --- |
| `0x44cb41`，即 `0x44cb10(code, 1)` 的 `rep movsd` | 玩家对象构造 `0x407ec0` 在 `0x407f41` 调用。条件：注册槽 n 的记录（索引 n+1）四项基础属性 `+0x4c/+0x50/+0x54/+0x58` 之和为 0，即从未登记过 | 从 PLAYERS 模板表 `*0x4c1afc` 整条复制 0x1fc 字节，气力＝PLAYERS `stamina` |
| `0x407632`，在 `0x4075e0` 内 | 每次进关都跑：`0x42da60` → `0x42da8d` 调 `0x42c640` → `0x42c695` 调 `0x4075e0`。它遍历注册表 21 槽，只处理启用槽（`0x42caa0` 非 0）：先 `0x4483c0(rec)`，再 HP＝`+0xdc`、MP＝`+0xe4`、`+0xa8`＝0 | `[0x4c1af0]` 为 0 时写 0；循环结束后 `0x407648` 把 `[0x4c1af0]` 清 0 |
| `0x452a06` | STORY／WINFAIL 的 opcode 69 `actKeepPlayerST`（跳表 `0x4537f4[69]`＝`0x452a02`） | 把 `[0x4c1af0]` 置 1，下一次进关就跳过上面的清零 |

- **`0x4c1af0` 的引用：** 全 EXE 只有三处，`0x407627` 读、`0x40764a` 清、`0x452a08` 置。
- **已登记的记录：** 构造器不再复制模板。HP≤0 时走 `0x45e3ed` 删对象，否则原样保留。
- **进关的其余清理：** `0x42c640` 最后调 `0x44cbd0`，把索引 20 起的记录清零（`+0x27b0` 起 `0x59cb` 个 dword），不含注册槽 0..19 的玩家记录。
- **出生调级不碰玩家气力：**
  - 玩家出生在 `0x44346e` 调 `0x40e870`。kind3 在 `0x40e89d` 跳到 `0x40eb18`，越过 `0x40eaed..0x40eb01`。
  - 被越过的这段是：`+0xe8` 为 0 时写入 `rand(11)`（`0x458c80(0xb)`）。所以这一步只作用于 NPC。
- **PLAYERS 的 `stamina` 列（resource-derived，与运行时模板表 `PLAYERS_templates_runtime.bin` 的 `+0xe8` 一致）：** 001 雷歐納德 20，006 雷特 8，其余 0。
- **写 `actKeepPlayerST` 的脚本（resource-derived）：** 284 份 STORY／WINFAIL 里只有 6 份。
  - WINFAIL051 win 0／1 → 下一关 52
  - WINFAIL045 win → 75
  - WINFAIL075 win → 57
  - STORY057 → 下一关由 `actSetNextPlayLevelGetOverEvent 0` 决定，未追
  - WINFAIL076 win → 81
  - STORY081 → 59
- `0x42da60` 的唯一调用者是 `0x42f7dd`，剧情关同样经过它。所以这个标志只管紧接着的那一次进关。

### 模拟器实测（runtime-measured）

- **工具与进关方式：** [`_stamina_trace.py`](../../../tools/hsltools/probes/_stamina_trace.py) 借回合裁判 `_enemy_level`（[用法](original_enemy_turn.md#11-任意关卡回合裁判-_enemy_levelpy)）。整映像机器照 WinMain 启动，以载入标志清零调 `0x42da60(level)`。
- **写入观察：** 进关之前就在整张 201×0x1fc 的 live 表上挂写入钩子，记录每一次改动气力字的写入。
- **运行条件：** 成长字按原版（growth true）。玩家回合一律待机。全局流在第 1 回合排序停点写 (1,2)。
- **开场与首控：** 「开场」取该停点的 `install_board`；「首控」取该玩家第一次成为当前行动者时的值。
- **三种队伍状态：**
  - 首次登记：新开局，每名玩家都在本关初次登记。
  - 携带余气 37、无 keep：`--carry 37`，用原版的 `0x42cb30`＋`0x44cb10` 先登记，再写入 37，代表上一场结束时剩的气。
  - 携带余气 37＋keep：同上，再加 `--keep`，把 `[0x4c1af0]` 置 1，相当于上一段脚本执行过 `actKeepPlayerST`。

| 关 | 玩家 | PLAYERS `stamina` | 首次登记：开场／首控 | 携带余气37、无 keep：开场／首控 | 携带余气37＋keep：开场／首控 |
| --- | --- | --- | --- | --- | --- |
| 51 | 雷歐納德 001 | 20 | 20／20 | 0／0 | 37／37 |
| 52 | 雷歐納德 001 | 20 | 20／20 | 0／0 | 37／37 |
| 53 | 緹娜 002 | 0 | —／0 | —／0 | —／37 |
| 1 | 雷歐納德 001 | 20 | 20／20 | 0／0 | 37／37 |
| 1 | 胡 003 | 0 | 0／0 | 0／0 | 37／37 |
| 3 | 雷歐納德 001 | 20 | 20／28 | 0／8 | 37／45 |
| 3 | 緹娜 002 | 0 | 0／0 | 0／0 | 37／37 |
| 3 | 胡 003 | 0 | 0／0 | 0／0 | 37／37 |
| 6 | 雷歐納德 001 | 20 | 20／32 | 0／12 | 37／49 |
| 6 | 緹娜 002 | 0 | 0／0 | 0／0 | 37／37 |
| 6 | 胡 003 | 0 | 0／0 | 0／0 | 37／37 |
| 6 | 漢克斯 004 | 0 | 0／0 | 0／0 | 37／37 |
| 12 | 雷特 006 | 8 | 8／8 | 未跑 | 未跑 |

- **写入者只有两处：** 首次登记的开场值全部由 `0x44cb41` 写入。携带时全部由 `0x407632` 从 37 写成 0；加 keep 后这一写入消失，值保持 37。
- **首控高于开场的格子：** 都是敌人抢在该玩家第一回合前打了他，由受击增长 `0x40e682` 写入：
  - 第 3 关：028_1 打雷歐納德 +8
  - 第 6 关：guard023_1、guard023_2 各打雷歐納德一次 +6
- **第 53 关的緹娜：** 在停点之后才装入，所以没有「开场」列，结果行按代码记为 `code002`。
- **第 3 关的漢克斯：** 开场值 0。他第 1 回合是敌方阵营（`actSetPlayerMode`），没有交控制，表中不列。
- **第 12 关（新开局）：** 同时开场的其余 7 名玩家，雷歐納德 20，其余 0。

结果行原样：

```
STAMINA_FIRST_CONTROL level=051 mode=fresh leonard=20 stop=round_end
STAMINA_FIRST_CONTROL level=052 mode=fresh leonard=20 stop=round_end
STAMINA_FIRST_CONTROL level=053 mode=fresh code002=0 stop=round_end
STAMINA_FIRST_CONTROL level=001 mode=fresh hu=0 leonard=20 stop=round_end
STAMINA_FIRST_CONTROL level=003 mode=fresh hu=0 leonard=28 tina=0 stop=round_end
STAMINA_FIRST_CONTROL level=006 mode=fresh hanks=0 hu=0 leonard=32 tina=0 stop=round_end
STAMINA_FIRST_CONTROL level=012 mode=fresh claudie=0 rett=8 hanks=0 shera=0 howl=0 hu=0 leonard=20 gulu=0 tina=0 stop=round_end
STAMINA_FIRST_CONTROL level=051 mode=carry37 leonard=0 stop=round_end
STAMINA_FIRST_CONTROL level=052 mode=carry37 leonard=0 stop=round_end
STAMINA_FIRST_CONTROL level=053 mode=carry37 code002=0 stop=round_end
STAMINA_FIRST_CONTROL level=001 mode=carry37 hu=0 leonard=0 stop=round_end
STAMINA_FIRST_CONTROL level=003 mode=carry37 hu=0 leonard=8 tina=0 stop=round_end
STAMINA_FIRST_CONTROL level=006 mode=carry37 hanks=0 hu=0 leonard=12 tina=0 stop=round_end
STAMINA_FIRST_CONTROL level=051 mode=carry37_keep leonard=37 stop=round_end
STAMINA_FIRST_CONTROL level=052 mode=carry37_keep leonard=37 stop=round_end
STAMINA_FIRST_CONTROL level=053 mode=carry37_keep code002=37 stop=round_end
STAMINA_FIRST_CONTROL level=001 mode=carry37_keep hu=37 leonard=37 stop=round_end
STAMINA_FIRST_CONTROL level=003 mode=carry37_keep hu=37 leonard=45 tina=37 stop=round_end
STAMINA_FIRST_CONTROL level=006 mode=carry37_keep hanks=37 hu=37 leonard=49 tina=37 stop=round_end
```

- **与真实游戏交叉核对（runtime-measured）：** Wine 原版在第 51 关雷歐納德第一次行动菜单写下的 [HSLBAT_first_control.SAV](original_save_format/HSLBAT_first_control.SAV)，记录 1（雷歐納德）`+0xe8` = 20，与模拟器首次登记一列相同。
- **同一存档里的 NPC：** 其余 11 名 NPC 为 0／8／7／1／0／9／4／0／0／4／1。L1 的都是 0，L2／L3 的在 0..9 之间，与上文 NPC 出生 `rand(11)` 一致。
- **NPC 的 rand(11) 何时发生：** 模拟器第 51 关 growth true 时，出生升过级的 7 名 NPC（L2／L3）各有一次 `0x40eb01` 写入，L1 的 4 名没有；growth false 时一次都没有。

### 战斗中的增长（核对上文读法）

- **写入点：** 各关、各种队伍状态下，回合内改动气力字的写入只有 `0x40e590` 里的两处：`0x40e643`（攻击方）与 `0x40e682`（防守方）。
  - 回合边界、待机、玩家回合开始都没有写入。
  - 第 51 关两回合里，雷歐納德两次交到控制时都是 20。
- **反击实例：** 第 51 关，board 文件内容为 `{"growth": false}`，另加 `--damage-seed 23 304 --set 021_1.cell=15/16 --set 021_1.max_hp=200 --set 021_1.hp=200`。
  - 021_1 攻击雷歐納德：雷歐納德作为防守方 `0x40e682` 20→26，021_1 作为攻击方 `0x40e643` 0→3。
  - 雷歐納德反击：他作为攻击方 `0x40e643` 26→29，021_1 作为防守方 `0x40e682` 3→9。
  - 增量是基础量 3 的一倍与两倍，与上文 168 组对拍的读法一致。
- **其他出现过的写入点（本问题之外）：**
  - `0x44cb88`：NPC 的模板复制，`0x44cb10` 的 flag 0 分支。
  - `0x44cbe4`：上文的 `0x44cbd0`。
  - `0x43f437`：在 NPC 进程 `0x43ea30` 内写 0，位置紧跟 `0x43f3f3` 调 `0x40e870`、`0x411a30` 占格与 `0x4483f0` 之后。第 12 关出现 272304 次，都是在值已为 0 时，没有改值。它与玩家开场气力无关，本节不再展开。

### 结论

原版开场气力分两种情况：

- **首次登记的玩家：** 取 PLAYERS `stamina`。写入者是 `0x44cb10` 的模板复制 `0x44cb41`，只有雷歐納德 20、雷特 8，其余都是 0。
- **携带的玩家：** 每次进关由 `0x4075e0` 在 `0x407632` 清成 0。例外是上一段脚本执行过 `actKeepPlayerST`，这时保留上一场结束时的余气。

照这条规则套本 lane 的六关：

| 关 | 情况 | 开场气力 |
| --- | --- | --- |
| 51 | 新开局首次登记 | 雷歐納德 20（Wine 存档同） |
| 52 | 雷歐納德携带；WINFAIL051 执行过 `actKeepPlayerST` | 第 51 关结束时的余气，不是定值 |
| 53 | 緹娜 PLAYERS 为 0 | 0 |
| 1、3、6 | 前一关都没有 keep | 开场 0 |

- 第 1、3、6 关的首控可能高于 0，前提是敌人先手打了该玩家。
- 雷特首次登记那一场开场为 8。他在实际流程中哪一关首次登记，本 lane 未核。

### 复跑

```sh
U="uv run --no-project --with unicorn==2.1.4 --python /opt/homebrew/bin/python3 python3"
$U tools/hsltools/probes/_stamina_trace.py --level 51 --seed 1 2 --turns 1 --out ignored/stamina/L051_fresh.json
$U tools/hsltools/probes/_stamina_trace.py --level 3 --seed 1 2 --turns 1 --carry 37 --out ignored/stamina/L003_carry.json
$U tools/hsltools/probes/_stamina_trace.py --level 3 --seed 1 2 --turns 1 --carry 37 --keep --out ignored/stamina/L003_keep.json
```

- 每次都冷进关，不读也不写关卡缓存。首次建启动缓存约 50 s；启动缓存已在时，本机每关约 3–8 s。
- 第 12 关另跑 `--level 12 --seed 1 2 --turns 1`。

## 装备与玩家决策

`hsltools/data/equipment.py`从同一ITEM表为每件装备生成明确的stamina_effect_flags，仅新增st_x2与no_addst两项受支持被动，其他未实现效果仍拒绝装备。

| 源物品 | 数据 | 实际行为 |
| --- | --- | --- |
| 225 凝氣之環 | st_x2 →0x40 | 攻击及受击积气加倍；两枚仍是同一效果位，不能四倍 |
| 169 鬼面 | no_addst →0x400 | 保留当前已有气力，之后的普通伤害不再增加；与戒指同装时优先停止 |

换装继续走EquipmentRules提案、PlayLoop一次确认和SwordMan派生刷新。预览解释“氣力累積 正常→加倍／停止”；取消不改库存，确认不送气力，不消耗当前行动，不重排本轮队列。卸下鬼面后，下一次伤害立即读取仍装备的戒指并恢复加倍。所有修饰从当前装备只读计算，不缓存另一份可变effect状态。

BattleVitals的氣力条由`BattleStaminaBar`按下节原画法绘制：20／40／60分别点亮一段／两段／全满，亮起一段恰好等于多付得起一次expend 1绝技。菜单是否可用继续查询同一费用／拥有权规则。预览文案是重制UI接线，不宣称原作信息公开条件等价。

### 氣力条的画法

lane R5-L5（2026-09-28，static-derived：r2 只读反汇编 `hsl01.exe` sha256 `f0b5f835…70f7`）。用户实玩问「气力满了一格却放不出绝技」：旧条按0..60线性填充215 px 的 BAR_ST2，而 BAR_ST1 的第一道分隔在 x 59（≈27%），约16点就「看着满一格」，但绝技要20。原条是对象过程表 `0x477c80` 项 **`0x4368c0`**（紧随 HP／MP 条 `0x4364e0` 的 `0x477c7c`），绘制分支读 live 记录 `+0xe8`（ST）：

| 地址 | 读法 |
| --- | --- |
| `0x436904`／`0x43696a`／`0x4369c9` | `cmp esi, 0x14／0x28／0x3c`：按 ST 所在阶段分支（≤20、≤40、≤60、>60） |
| `0x436928`／`0x436986`／`0x4369e5` | 取参照 shape 尺寸 `0x4606a9(ebx+2／ebx+3／ebx+1)`：阶段内的填充宽 = `((ST << 16) / (20×阶段)) × 参照宽 >> 16`（`0x66666667`＋`sar 3`＝/20、`sar 4`＝/40、`0x88888889`＋`sar 5`＝/60） |
| `0x43695c`／`0x4369ba`／`0x436a1b`／`0x436a51` | 已完成段数 esi：`ST==20`→1 否则0；`1+(ST==40)`；`2+(ST==60)`；>60 为3 |
| `0x436a86` | esi≠3 时以 `0x4607f9(0x1000000, x+1, y+1, shape ebx+1, …, clip x..x+宽)` 画红色填充 |
| `0x436ab2..0x436ae8` | esi=1／2／3 分别以 `0x460799(0x20000000, x+1, y+1, ebx+2／ebx+3／ebx+1, 混合级 +0x28)` 叠画已完成段 |
| `0x436a96..0x436aaf` | 对象 `+0x80 & 0x10000` 置位时混合级 `+0x28 = |0x4c1ce0| + 12`（`0x4c1ce0` 在 −4..4 循环，即 12..16 级脉动） |
| `0x436afe..0x436b32` | 同一位置位时（绘制之后）字 `[0x4782a4]` 每画一次减一，旧值为 0 时从 `[0x4782a6]`＝4 重装并令 `0x4c1ce0` 加一、到 5 回 −4——每 5 tick 走一步，−4..4 共 9 步＝45 tick 一周；四处引用只有本过程，全局共用 |
| `0x436b57..0x436bab` | 该位未置时改走对象自己的计数：字 `+0xa0` 每画一次减一，旧值为 0 时从 `+0xa2` 重装、`+0x98` 加一（到 5 回 −4）、`+0x28 = |+0x98| + 12`。Bar_ST 模板没有 obj_Data6（`+0xa0` 双字，`+0xa2` 是其高半字），`0x43ad80` 也不写，故 `+0xa2 = 0`：每 tick 走一步，9 tick 一周，开页从 `+0x98 = 0` 起 |
| `0x43b4e0` case 2／3 | 全程序只有这两种模式给 Bar_ST 置 `0x10000`（同时给 WINDOW10 等置）：case 2 是切入身份栏（`0x403512`／`0x404bf3` AnimalAttack／AnimalDefense `push 2`），case 3 是悬停／选目标身份栏（`0x43e5bf` 等 `push 3`）；状态页 0／1、物品 4／5、交换 6／7、技能页 8／9、升级 10、獲得物品 0xb 都不置 |
| `0x461479` | 旗标 `0x20000000` 的参数（`+0x28`）大于 16 时进错误分支 `0x46e100(7,0)`：混合级以 16 为满 |
| `0x436a56..0x436a86`＋`0x4612ba` | 红色填充的 clip＝(x, y, x＋填充宽, y＋高＋1)，形状画在 (x+1, y+1)；默认 clip 是 `0x4612ba` 设的 (0, 0, 屏宽 640, 屏高 480)，右／下界不含端点——红色实际只占 x+1..x+填充宽−1，比填充宽少 1 px |

对象自身 shape（ebx+0）是 BAR_ST1 空条。PAK 目录记录 4953–4956 依次为 `bar_st1..bar_st4`（resource-derived），与画法自洽：BAR_ST3 宽58＝第一段、BAR_ST4 宽122＝前两段、BAR_ST2 宽215＝全条，且 BAR_ST2 的段间透明列 x 58／122 画在 (1,1) 偏移后正落在 BAR_ST1 的分隔 x 59／123。

结论：填充在每个20点阶段内按该阶段参照宽比例增长，**一段只有到20点才被叠画点亮**（19点红色填充到55 px，不叠画；20点蓝色 BAR_ST3 覆盖第一段；40点黄色 BAR_ST4 覆盖两段；60点 BAR_ST2 覆盖全条）。原录像 `06_status_and_stats_screen/frame_006`（runtime-reference）的状态页气力条恰是蓝色 BAR_ST3 盖住第一段（约 58 px）、其后无红色填充，与 ST=20（PLAYERS raw 20）时本画法的输出一致。重制 `game/battle/scene/BattleStaminaBar.gd` 照此绘制，`run_stamina_tests.presentation_cases` 逐点断言 0／1／19／20／21／39／40／41／59／60 的填充宽与点亮段数，并断言点亮段数 = `ST / SkillResourceRules.ST_PER_EXPEND`。叠画与右界（lane STATUSPAGE，2026-09-27，static-derived，同一 EXE）：已点亮段按混合级 `+0x28`／16 叠在底条上，级数在 12..16 间三角往复；切入栏与悬停栏（`0x10000`）共用 `0x4c1ce0`，每 5 tick 一步、45 tick 一周，状态页等窗口用对象自己的 `+0x98`，每 tick 一步、9 tick 一周；红色填充少画最右 1 px（上表末三行）。重制 `BattleStaminaBar` 照此：`shared_pulse` 默认真（悬停／切入栏），`BattleStatusPanel` 置假；叠画 `modulate` α＝级数/16（逐像素混合公式在光栅器里，按常规 α 混合，未逐字读）；红色区域宽＝`fill_width() − 1`，`fill_width()` 仍是原式的 clip 宽。

普通／反击特写按当前strike的气力收据投影命中前后，不能提前显示已结算的未来反击增长；落空且只有反击增长时同样使用反击前值。此处只调整只读镜头快照，不改变结算和表现时钟。发现经过定向red／green与实际受击前后图证，见下方验收入口。

## 提交与失败边界

StaminaRules只返回提案，PlayLoop在提交普通伤害时一次写入双方资源并保存stamina_gain；反击重新以相反身份调用同一规则。玩家交锋在反击和命中RNG前检查两方气力／装备数据，AI在选择目标之前检查活跃单位。气力缺失、负值、非整数、超过60或缺装备修饰元数据，都不能先抽随机数／移动／扣费再失败。

开场气力按[开场实测](#开场实测)的原版规则初始化（接线见 `ActorInitializationRules`、`CampaignCarryRules` 文件头）。NPC 出生的 `rand(11)`（出生升过级且气力为 0 时，全局流，排在五项源能力抽取之后）与 [入场调级](original_auto_growth.md) 的原函数回执逐次一致。源角色天赋位、其他导致气力变化的机制尚未由本包接入。死亡仍经过现有清理把被击败者ST清零；增长收据保留清理前提案，不能据此声明原完整死亡handler已经恢复。

场景里的重复stamina_cap／normal_hit_gain已删除；上限只有新纯规则中的原常量。现有配置指纹包含装备目录及skill_rules，旧规则存档在恢复前明确拒绝。新保存仍记录唯一PlayLoop，不另存一份气力或装备缓存，不提供旧版本迁移。

## 验证入口与后续依据

[run_stamina_tests.gd](../../../tests/run_stamina_tests.gd)覆盖原168组对拍、攻击／受击／反击、落空、击杀、魔法和特殊技不返还、上限、源技能拥有权、两枚戒指／鬼面／卸下、错误数据零变更和实际条值。原行动交接、战斗收尾、费用、装备与第一战runtime测试继续覆盖共同路径。

实际鼠标操作的积气、装备预览、取消、绝技释放及默认数值整场结果见 [可见验收](../runtime_observations/stamina/README.md)。可见夹具与正式默认战斗分开；原数值对拍与重制图证也分开。

```sh
python3 tools/hsl.py check stamina
python3 -m unittest tools.test_hsl_native_stamina_probe tools.test_hsl_equipment_data
tools/godot.sh --headless --script res://tests/run_stamina_tests.gd
uv run --no-project --with unicorn==2.1.4 python3 tools/hsl.py generate stamina --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
```

仅显式--execute重新执行原EXE；--write必须同时执行。普通完整门禁不需要安装原作或Unicorn。后续公共系统继续从PROJECT唯一Next steps进入，优先辅助技能／行动资格及原完整伤害／EXP，复用本次已证实的气力和费用规则。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/loop/BattleLoopCombat.gd` rules：0x44248e queued pre-critical damage into the stamina tail

# 气力：攻击／受击积气、装备修饰、开场值与氣力条画法

> evidence: static-derived; runtime-measured: 开场实测——整映像模拟器照 0x42da60 进关逐次记录 live +0xe8 写入，Wine 原版首控存档 HSLBAT_first_control · status: live · functions: 0x4075e0, 0x407ec0, 0x40e240, 0x40e2e0, 0x40e590, 0x40e870, 0x42c640, 0x42da60, 0x4368c0, 0x43b4e0, 0x44cb10, 0x461479 · tools: hsltools/data/equipment.py, hsltools/probes/_stamina_trace.py, hsltools/probes/stamina.py, run_ordinary_special_tests.gd · updated: 2026-09-27

## 结论

- 原版：普通交锋（含反击）有效结果后按 queued 伤害积气——伤害 < maxHP/2 基础 3，否则 4，击杀 +1，攻击方等级高 3 以上 −1；攻击方加基础量、防守方加两倍；`st_x2` 加倍、`no_addst` 停止（停止优先），上限 60；魔法与特殊技不积气（static-derived；168 组完整返回）。
- 开场：首次登记的玩家取 PLAYERS `stamina`（雷歐納德 20、雷特 8，其余 0）；携带的玩家每次进关清 0，上一段脚本执行过 `actKeepPlayerST` 时保留余气；NPC 出生升过级且气力为 0 时抽 `rand(11)`（static-derived；模拟器与 Wine 存档 runtime-measured）。
- 氣力条：每 20 点一个阶段，阶段内红色按比例填充，到 20／40／60 才叠画点亮一段／两段／全条，亮段数＝可付的 expend 1 绝技次数（static-derived）。
- 重制：`StaminaRules` 出提案、PlayLoop 一次写入双方；开场由 `ActorInitializationRules`／`CampaignCarryRules` 初始化；`game/battle/scene/BattleStaminaBar.gd` 照原画法绘制（static-derived；叠画 α 混合公式 provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；168 组结果与 8 段锚点见 [original_stamina.json](original_stamina.json)，Unicorn 执行原机器码，无 stub、无 RNG）

| 原地址 | 用途 |
| --- | --- |
| `0x40e590..0x40e68c` | 攻击／受击增长函数；只允许两个 actor 的 ST 改变；写入点 `0x40e643`（攻击方）、`0x40e682`（防守方） |
| `0x40e240`、`0x40e2e0` | 读 actor+0x18c 有效修饰位；加倍谓词查 0x40 |
| `0x44246c..0x44249b` | 普通交锋有效结果后传入准备好的伤害调用增长；反击复用 |
| `0x447e82`／`0x448183` | ITEM `st_x2` → 0x40；`no_addst` → 0x400 |
| `0x448709` | 装备效果字 OR 进 actor+0x18c，同效果不重复乘 |
| `0x44b678` | 下一等级阈值用 actor+0x9c（辅助核对等级字段） |

增长函数经 object+0xa4 找 stride 0x1fc 的记录，读等级 +0x9c、结算后 HP +0xd8、maxHP +0xdc、ST +0xe8、效果 +0x18c；`maxHP=max(10, defender.maxHP)`，伤害裁到该值，阈值 `floor(maxHP/2)`。

开场写入：

| 地址 | 何时 | 作用 |
| --- | --- | --- |
| `0x44cb41`（`0x44cb10(code, 1)` 的 `rep movsd`） | 玩家对象构造 `0x407ec0` 在 `0x407f41` 调用，条件是注册槽 n 的记录四项基础属性 +0x4c／+0x50／+0x54／+0x58 之和为 0 | 从 PLAYERS 模板表 `*0x4c1afc` 复制 0x1fc 字节，气力＝PLAYERS `stamina` |
| `0x407632`（`0x4075e0` 内） | 每次进关：`0x42da60` → `0x42da8d` 调 `0x42c640` → `0x42c695` 调 `0x4075e0`，遍历 21 槽中启用者（`0x42caa0` 非 0），先 `0x4483c0(rec)`，HP＝+0xdc、MP＝+0xe4、+0xa8＝0 | `[0x4c1af0]` 为 0 时写 0；`0x407648` 随后清 `[0x4c1af0]` |
| `0x452a06` | opcode 69 `actKeepPlayerST`（跳表 `0x4537f4[69]`＝`0x452a02`） | 置 `[0x4c1af0]` = 1，下一次进关跳过清零 |

`0x4c1af0` 全 EXE 只有 `0x407627` 读、`0x40764a` 清、`0x452a08` 置。已登记记录构造时不再复制模板。`0x42c640` 末尾 `0x44cbd0` 清索引 20 起的记录，不含槽 0..19。玩家出生 `0x44346e` 调 `0x40e870`，kind3 在 `0x40e89d` 跳到 `0x40eb18`，越过 `0x40eaed..0x40eb01` 的 `rand(11)`（`0x458c80(0xb)`），所以该抽只作用于 NPC。`0x42da60` 唯一调用者 `0x42f7dd`，剧情关同样经过。

氣力条（对象过程表 `0x477c80` 项 `0x4368c0`，读 live +0xe8）：

| 地址 | 读法 |
| --- | --- |
| `0x436904`／`0x43696a`／`0x4369c9` | `cmp esi, 0x14／0x28／0x3c` 分阶段（≤20、≤40、≤60、>60） |
| `0x436928`／`0x436986`／`0x4369e5` | 参照 shape `0x4606a9(ebx+2／+3／+1)`；阶段内填充宽 `((ST << 16) / (20×阶段)) × 参照宽 >> 16` |
| `0x43695c`／`0x4369ba`／`0x436a1b`／`0x436a51` | 已完成段数：`ST==20`→1 否则 0；`1+(ST==40)`；`2+(ST==60)`；>60 为 3 |
| `0x436a86` | 段数≠3 时 `0x4607f9(0x1000000, x+1, y+1, ebx+1, …, clip x..x+宽)` 画红色填充 |
| `0x436ab2..0x436ae8` | 段数 1／2／3 以 `0x460799(0x20000000, x+1, y+1, ebx+2／+3／+1, 混合级 +0x28)` 叠画 |
| `0x436a96..0x436aaf`、`0x436afe..0x436b32` | 对象 +0x80 & 0x10000 置位时 +0x28 = \|`0x4c1ce0`\| + 12；全局字 `[0x4782a4]` 每画一次减一，为 0 时从 `[0x4782a6]`＝4 重装并令 `0x4c1ce0` 加一（到 5 回 −4）：每 5 tick 一步、45 tick 一周 |
| `0x436b57..0x436bab` | 该位未置时用对象自己的 +0xa0／+0xa2／+0x98；Bar_ST 模板 +0xa2 = 0，每 tick 一步、9 tick 一周 |
| `0x43b4e0` case 2／3 | 只有切入身份栏（`0x403512`／`0x404bf3` 的 `push 2`）与悬停／选目标身份栏（`0x43e5bf` 等 `push 3`）给 Bar_ST 置 0x10000 |
| `0x461479` | 旗标 0x20000000 的 +0x28 大于 16 进错误分支：混合级以 16 为满 |
| `0x436a56..0x436a86`＋`0x4612ba` | 红色 clip 右／下界不含端点，实际少画最右 1 px |

**runtime-measured**（[`_stamina_trace.py`](../../../tools/hsltools/probes/_stamina_trace.py) 借回合裁判 `_enemy_level`，整映像照 WinMain 启动后调 `0x42da60(level)`，全表写入钩子；growth true、玩家回合待机、全局流第 1 回合写 (1,2)；carry37＝用 `0x42cb30`＋`0x44cb10` 先登记再写 37，keep＝再置 `[0x4c1af0]`）

| 关 | 玩家 | PLAYERS `stamina` | 首次登记 开场／首控 | 携带 37 开场／首控 | 携带 37＋keep 开场／首控 |
| --- | --- | --- | --- | --- | --- |
| 51 | 雷歐納德 001 | 20 | 20／20 | 0／0 | 37／37 |
| 52 | 雷歐納德 001 | 20 | 20／20 | 0／0 | 37／37 |
| 53 | 緹娜 002 | 0 | —／0 | —／0 | —／37 |
| 1 | 雷歐納德／胡 | 20／0 | 20／20、0／0 | 0／0、0／0 | 37／37、37／37 |
| 3 | 雷歐納德／緹娜／胡 | 20／0／0 | 20／28、0／0、0／0 | 0／8、0／0、0／0 | 37／45、37／37、37／37 |
| 6 | 雷歐納德／緹娜／胡／漢克斯 | 20／0／0／0 | 20／32，其余 0／0 | 0／12，其余 0／0 | 37／49，其余 37／37 |
| 12 | 雷特 006 | 8 | 8／8（同场其余 7 人：雷歐納德 20，其余 0） | 未跑 | 未跑 |

首控高于开场的格子都是敌人先手打了该玩家（`0x40e682`）：第 3 关 028_1 打雷歐納德 +8，第 6 关 guard023_1、guard023_2 各 +6。第 53 关緹娜在停点后装入（记为 `code002`）；第 3 关漢克斯第 1 回合是敌方阵营，不列。回合边界、待机、回合开始都没有气力写入。反击实例（第 51 关，`{"growth": false}`、`--damage-seed 23 304 --set 021_1.cell=15/16 --set 021_1.max_hp=200 --set 021_1.hp=200`）：021_1 攻击雷歐納德，雷歐納德 20→26、021_1 0→3；雷歐納德反击 26→29、021_1 3→9。

Wine 原版第 51 关首次行动菜单存档 [HSLBAT_first_control.SAV](original_save_format/HSLBAT_first_control.SAV)：雷歐納德 +0xe8 = 20；其余 11 名 NPC 为 0／8／7／1／0／9／4／0／0／4／1（L1 都是 0，L2／L3 在 0..9）。模拟器第 51 关 growth true 时出生升过级的 7 名 NPC 各有一次 `0x40eb01` 写入，L1 的 4 名没有。原录像 `06_status_and_stats_screen/frame_006` 状态页气力条是蓝色 BAR_ST3 盖住第一段、其后无红色填充，与 ST=20 的画法输出一致。

**resource-derived**：写 `actKeepPlayerST` 的只有 6 份脚本——WINFAIL051 win 0／1 → 52、WINFAIL045 win → 75、WINFAIL075 win → 57、STORY057（下一关由 `actSetNextPlayLevelGetOverEvent 0` 决定，未追）、WINFAIL076 win → 81、STORY081 → 59。PAK 记录 4953–4956 为 `bar_st1..bar_st4`：BAR_ST3 宽 58、BAR_ST4 宽 122、BAR_ST2 宽 215，段间透明列 x 58／122 画在 (1,1) 后落在 BAR_ST1 分隔 x 59／123。装备：225 凝氣之環 `st_x2`（两枚不叠成四倍），169 鬼面 `no_addst`（与戒指同装时停止优先）。

## 重制接线

- `game/sim/StaminaRules.gd`：只返回提案；PlayLoop 提交普通伤害时一次写双方并保存 `stamina_gain`，反击以相反身份再调；传入 `strike.damage`（queued，见 `game/sim/loop/BattleLoopCombat.gd`：`0x44248e` 把暴击前 queued 伤害交给积气尾部），受击后 HP 单独传入；落空不积气。
- 玩家交锋在反击与命中 RNG 前、AI 在选目标前检查气力／装备数据；缺失、负值、非整数、>60 或缺修饰元数据零变更拒绝。上限只在规则常量中，场景旧 `stamina_cap`／`normal_hit_gain` 已删。
- 开场：`ActorInitializationRules`、`CampaignCarryRules` 按首次登记／清零／keep 初始化；NPC `rand(11)` 排在五项源能力抽取之后，与 [original_auto_growth.md](original_auto_growth.md) 的回执逐次一致。
- `hsltools/data/equipment.py` 生成 `stamina_effect_flags`（只开放 `st_x2`、`no_addst`）；换装预览显示「氣力累積 正常→加倍／停止」（provisional 文案）。
- `BattleStaminaBar`：`shared_pulse` 默认真（悬停／切入栏），`BattleStatusPanel` 置假；叠画 modulate α＝级数/16（原逐像素混合公式未逐字读，provisional）；红色宽＝`fill_width() − 1`。特写按当前 strike 的气力收据投影前后值，不提前显示未来反击增长。

## 复现

`python3 tools/hsl.py check stamina`；开场实测 `uv run --no-project --with unicorn==2.1.4 python3 tools/hsltools/probes/_stamina_trace.py --level 51 --seed 1 2 --turns 1 --out ignored/stamina/L051_fresh.json`（`--carry 37`、`--keep` 换队伍状态）；重制侧 `tools/godot.sh --headless --script tests/run_ordinary_special_tests.gd`。Control 回执（`runtime_observations/stamina/receipt.json`）驱动已退役，回执为历史记录。

## 边界

- 增长 helper 等价不证明输入它的整套伤害公式等价。
- 雷特在实际流程中哪一关首次登记未核；STORY057 之后的下一关未追。
- 源角色天赋位等其他改变气力的机制未接入；死亡清 ST 不代表原完整死亡 handler。
- `0x43f437` 在 NPC 进程 `0x43ea30` 内写 0 的用途未展开（观测到时值已为 0）。

# 地图人物的施法姿势、升级星光与红色伤害数字：原版读法与重制

> evidence: static-derived: 0x4071e0 姿势入口与 0x446c40 状态 7、0x45e525／0x45e575／0x45e660 帧程序、敌我过程 0x43f1dc..0x43f24c／0x4436f9..0x443770 与 0x44212a..0x442161 回站立、0x4071e0 的调用点（0x402fd1／0x403128 法术引导末、0x4449a7／0x440366／0x4404c7 用道具、0x442720 升级）、0x408b20 case 3 → 0x415c10 撒星、effProcFlyUpShape 0x41f5db → effProcFlyUp2 0x416d04、0x45ebdc 位移、0x422c9a 淡出、0x408580 kind 0 分支 0x40863e..0x40888e; runtime-measured: 2026-09-24 用户录屏 470.05–471.58 s（026 施法姿势）、339.60–340.6 s（LEVEL UP 星光）、203.25 s（特写伤害数字「2」→「22」）; resource-derived: SHAPEDEF use_magic／use_magic_num、hsl.pak NNN-M0001..6、AIR06_03..06、NUM100..109、NUM510; provisional: 无 m_shape 引导者的姿势起点、加色层级混合的 alpha 读法 · status: live · functions: 0x402fd1, 0x403128, 0x406d20, 0x4071e0, 0x408580, 0x408b20, 0x415c10, 0x415dc0, 0x416d04, 0x41f5db, 0x422c9a, 0x43f1dc, 0x440366, 0x4404c7, 0x442720, 0x4436f9, 0x4449a7, 0x446c40, 0x45dc5c, 0x45e525, 0x45e575, 0x45e660, 0x45eb9d, 0x45ebdc · tools: capture_map_pose_floaters_review.gd, run_combat_aftermath_tests.gd, run_map_pose_floaters_tests.gd · updated: 2026-09-27

## 结论

- 原版 `0x4071e0` 让地图人物放 SHAPEDEF `use_magic` 帧：正放、停 40 tick、倒放，n 张共 8n＋40 tick；法术引导末、用道具、升级时调用，绝技不做（static-derived，录屏 026 施法 1.53 s 相符：runtime-measured）。
- 原版升级撒 36 颗 `obj_LevelUp_Star` 加色星光，围着受益者上升淡出；红色伤害数字逐位 2× 揭出、白闪、不上浮，寿命 10×位数＋34 tick（static-derived；runtime-measured）。
- 重制 `ActorRuntime.play_use_magic`、`LevelUpStars`、`DamageNumberFloater`／`ResultNumberFloater` 按这些读法实现（static-derived）。
- 差异：无 m_shape 引导者的姿势起点、加色层级混合 alpha 为 provisional（差异清单 `cast-strip-missing`、`additive-level-blend`）；星光与姿势用表现 RNG（remake-invented）；效果开始是否等姿势未读（`cast-lead-phase`）。

## 证据

静态读 `hsl01.exe`（SHA-256 `f0b5f835…70f7`；r2 反汇编）。像素取原版录屏（`crop=1280:960:112:140` 缩到 640×480，PTS 秒；本机 tick ≈ 19.4 ms、设计 16 ms，见 [tick 率](../original_tick_rate/README.md)）。原始帧不入库。

### 1. use_magic 姿势：`0x4071e0`

**入口**（static-derived）：`0x4071e0(actor)` 调 `0x446c40(actor, actor+0xa2 = SID, 7, 3)`；成功则 `+0x92 = 40`、`+0x98 = 0`、`+0x90 = 0xffff`、`+0x80 = (+0x80 & ~0x800) | 0x1000`。`0x446c40` 状态 7 读 SHAPEDEF 记录 `+0x34`／`+0x38`（解析器 `0x446a8c` 把 `use_magic`／`use_magic_num` 写在那里），经 `0x45e525` 置起始张、张数与**张延迟 3**（每张 4 tick）。

**逐 tick**（敌 `0x43f1dc..0x43f24c`、我 `0x4436f9..0x443770`，同一段）：`+0x80` 有 0x1000 且无 0x800 时按 `+0x98` 分三段——0：`0x45e575` 正放一次，放完（末张）进 1；1：`+0x92` 倒数 40 进 2；2：`0x45e660` 倒放回首张，放完清 0x1000。之后 `0x44212a..0x442161` 见 `+0x90`（−1）与期望状态 0 不同，重选站立序列（延迟 10）。n 张的姿势：tick t 的张＝t÷4（到 n−1 为止）直到 4n，停 n−1 到 4n＋40，再每 4 tick 退一张，**8n＋40 tick 结束**（常见 6 张＝88 tick＝1.41 s）。

**调用点**（r2 交叉引用 `0x4071e0` 全部七处）：

| 调用点 | 场合 | 同刻 |
| --- | --- | --- |
| `0x402fd1` | 施法对象 `0x401c20` 子状态 4：引导淡出计到 `+0x84 = 32` | `0x408b20(x, y − h, 4)` Cast_Star、放 `0x193`（施法音） |
| `0x403128` | 同对象另一子状态（`0x4c1408 == 0`，无外部释放程序），等 `+0x90` 后 | 同上 |
| `0x406e6b` | `0x406d20` 插入施法对象失败的退路（kind 1） | Cast_Star 于 (x, y − 42)、`0x193` |
| `0x4449a7` | 玩家状态 0x69（道具选目标）确认 | 下一 tick 状态 0x6a `0x409e40` 用道具 |
| `0x440366`／`0x4404c7` | AI 回复道具（`0x40c1d0`）／解除道具（`0x40c230`）入口 | 随后 `0x409e40` |
| `0x44295d` | 结算 `0x442720` 阶段 6（升级） | `0x4084e0` kind 6：LEVEL UP、星光、`0x191` 升级音 |

`0x4c1408`（绝技的外部释放程序）非零时子状态 4 走 phase 103，不经 `0x402fd1`——**绝技不做地图姿势**，法术（kind 1，`0x4c1408 = 0`）做。

**资源**：SHAPEDEF 66 行有 `use_magic`；按走行帧键（`ActorRuntime.actor_id`）解析后 60 键有独立帧（356 张，`content/imported/hsl/shared/actor_magic_poses/`，任务 `actor_magic_poses`）；060、068 的 use_magic 就是站立帧（`use_magic_is_stand`）；作者关 102／103 无 SHAPEDEF 行。`044-M0002.SHP` 由 use_magic＋张数推出但 hsl.pak 没有（negative-evidence），044 按现存 5 张放。

**像素**（runtime-measured，026 帝國法師 施放 幻火）：469.60–469.65 s 仍在选目标；470.05 s 起斗篷张开（M 帧），470.30–470.35 s 双手高举并伴绿色 Cast_Star 星点，保持到 ≈471.40 s，471.45–471.55 s 倒放回斗篷张开，471.60 s 回站立、同刻画面压暗火球开始。可见段 470.05–471.58 s＝1.53 s（≈79 个 19.4 ms tick）；M0001 与站立帧相近，起点可能早 1–3 个采样帧，与 88 tick 相符。姿势与星点**同时**出现（026 没有 m_action 引导，引导段几乎为零）。

### 2. 升级星光：`0x408b20` case 3 → `0x415c10`

**撒星**（static-derived）：kind 6 的 `0x4084e0(x, y − 0x30, …)` 调 `0x408b20(x, y − 0x30, 3)` → `0x415c10(x, y, 0x95, 0x40, 0x18, 0, 6, 0x24, 0)`：插 **36** 颗对象 149 `obj_LevelUp_Star`（`MAGIC\AIR06_03.SHP` 起 4 张，`defProcEffectProcess1`，obj_Data6 `0x4000`，obj_Data9 effProcFlyUpShape＝81），第 k 颗在 (x＋dx, y＋dy)：dx＝rand(64) 大于 32 时折成 32−dx（−31..32）、dy 同法（−11..12）；插入延迟 `+0xae` 首颗 0、之后每颗累加 1＋rand(6)。(x, y) 是受益者对象坐标（格中心），星光围着身体。

**运动**（`0x415dc0` 数完 `+0xae` 才画——延迟 0、1 都在第一 tick 出现）：effProcFlyUpShape（跳表 `0x4231b0[81] = 0x41f5db`）只跑一次：起始张＋rand(4)、`+0x78 = 0x10001`（定住该张）、速度 `+0xa0`（0x4000）＋(rand & 0x1f000)（16.16，0.25 + k/16 px／tick，k∈0..31）、角 0xc0（正上）、`+0x7c`（张延迟 0）＋6＋(rand & 7)，然后把程序换成 16 effProcFlyUp2（`0x416d04`）。FlyUp2 每 tick 先 `0x45ebdc` 位移（只存小数，等速），再 `0x45e575`：`+0x7c` 数到负即置 0x20000000；之后 `0x422c9a` 每 tick `+0x28`（层级 16）减 1，归零删除。每颗：出现后 hold＋1 tick 满层级（hold 6..13），再 16 tick 淡出，边淡边上升。对象 `[esi] |= 0x4000000`：加色（RGB565 饱和加法）；层级混合按加色 × 层级/16 读（provisional，同死亡消散的读法）。

**像素**：LEVEL UP 339.60 s 出现后，受益者身上有黄色光点闪现，339.65–340.6 s 持续，与加点窗打开（≈340.7 s）重叠。

### 3. 红色伤害数字：`0x408580` kind 0

**初始化**（hold 数完，`0x4085ef`）：层级 16；`+0x90 = 0x20005`（半步计数 5、重载 2）、`+0x94 = 0x10000`（上一位 0、当前位 1）、`+0x98 = 0xa000a`（每 10 tick 进一位）、`+0x9c = 0x10006`（闪光：第 1 位、6 tick）。

**逐 tick**（`0x40863e..0x40888e`）：当前位非零时 `+0x98` 倒数 10，归零则「上一位＝当前位、当前位＋1」，越过位数时当前位归 0，否则闪光移到新位、计 6；`+0x90` 每到期（先 5 后每 2）清掉上一位，当前位已归 0 时改为 18 tick 一次、之后每 tick 层级减 1，层级归 0 删除（放行等待者见 [tick 包 §1](../../static_reverse/original_tick_counts.md#1-defprocshownumber0x408580地图数字的寿命与上浮)）。**画**：只画第 1..max(当前, 上一) 位（揭完后画全部），首位 x − 7×(位数 − 1)、每位 +14；上一位 1.5×（0x18000）、当前位 2.0×（0x20000），其余 1×；闪光位另画 NUM510（`基址 + 0x32`）4.0×、模式 0x2c000000（加色＋缩放＋层级）、层级＝闪光计数＋10（16→11）；绘制模式 0x20000000／0x28000000／0x2c000000（`0x408746..0x408888`）。字形＝`基址 + 数字`，基址是 obj_ShowNumber 177 的 NUM100 段：NUM100..109 红字。kind 0 分支在 `0x40888e` 直接返回，**不经** `0x408ad8` 的 0x10000 上浮翻转——**伤害数字不上浮**（kind 1–6 才每 2 tick 上 1 px）。寿命 1＋10×位数＋18＋15＝**10×位数＋34 tick**（1 位 44、2 位 54）。

**揭位顺序**：按数字字符串从左（高位）到右。录屏 203.25 s 特写里先出现 2× 的「2」带白色光晕、约 10 tick 后成「22」、之后小字停住；两位相同，无法从像素区分先高位还是先个位——顺序以静态为准。

**录像对照**（runtime-measured）：地图法术红字「19」的墨框中心比量表顶高约 57 px，道具绿字「29」高约 52.5 px——量表顶取 y＋5 时两者分别合 (y−0x34) 与 (y−0x30)（字形原点在字高一半）；两位逐位 2× 放大、白闪，第二位约晚 0.217 s（按本机 19.4 ms/tick ≈ 11 tick，静态 10），不上浮，可见约 0.98 s（≈ 51 tick，静态 54，末几级近乎不可见）。绿字回复（道具）约 16 tick 后开始淡出，每 2 tick 上 1 px，与 kind 2 一致。录像里没有蓝色 MP 数字。

## 重制接线

- `ActorRuntime.play_use_magic()` 按 §1 公式逐 tick 放（`magic_pose_frame`），走路、死亡 hit 姿势、脚本换形都立即结束它。挂钩：地图法术 `BattlePresentation._sync_cast_pose` 每次 refresh 看正在播的法术片段——施法者有导入的 m_shape 引导时等片段 `released`（引导结束，对应 `0x402fd1`）；没有引导的施法者（026 等）在片段开始就姿势，与重制的 Cast_Star 环同时（**provisional**：环是重制替身，原版 `0x403128` 的等待 `+0x90` 计数未读；录屏支持同时出现）。用道具 `show_item_use` 让 receipt 的 `actor_id` 姿势；升级 `BattleAftermath._present_level_up`。
- `LevelUpStars`：36 颗 AIR06_03..06 加色精灵；参数由交锋序号＋受益者 id 种子的表现 RNG 抽（原全局 `0x458c10` 流不复现，remake-invented）。`BattleAftermath._present_level_up` 同一刻：受益者 `play_use_magic()`、LEVEL UP 美术字、星光（进 `trailing`，跟地图移动）、升级音。
- `game/battle/scene/DamageNumberFloater.gd`（`state_at` 逐 tick 重放 §3 计数器；NUM100..109、NUM510 由 `hsl generate reward_floats` 导入），经 `ResultNumberFloater`（kind 0／2／3／5 一个入口：hold、寿命、上浮、字形布局）用于特写（普通一击 (320,200)、命中后 40 tick；脚本一击 (320,180)；`BattleCombatCutin.result_number`）、地图一击与地图法术（`MagicImpactPresentation`，目标 (x, y−0x34)）、法术状态结果、道具（(x, y−0x30)）与回合末（(x, y−48)）。`CombatPresentationTiming.damage_number_seconds` 为 34＋10×位数。MISS 是 NUM513 字形（kind 5）；原版无字形的说明词（中毒、解毒、增益等）是白色 Label，放在数字上方。provenance layout：`0x408746..0x408888` 首位 x − 7 × (位数 − 1)、间隔 14 px，缩放 0x20000 最新位、0x18000 上一位、0x40000 闪光；timing：`0x4085ef` 初值、hold 1 tick、每 10 tick 进一位、收尾 0x10012、每 tick 层级 −1、寿命 10 × 位数 + 34 tick。
- provenance 写法：`static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md`。

## 复现

`tools/godot.sh --headless --script res://tests/run_all.gd -- run_map_pose_floaters_tests.gd`（姿势程序、调用点只有三类、星光参数与层级、kind 0 状态机、揭位顺序、不上浮）；目审截帧 `tests/capture_map_pose_floaters_review.gd`（写 `ignored/map_pose_floaters/`）。

## 边界

- 特写片段的结尾由片段自己的时钟决定：脚本一击 `RESULT_HOLD_TICKS` 40 tick 后收片段，两位红字（54 tick）的淡出尾会被截掉；普通一击同理。
- 无 m_shape 引导的施法者：原版 `0x403128` 前等待的 `+0x90` 计数未读；录屏支持姿势与 Cast_Star 同时，重制在片段开始姿势（provisional）。原版施法音 `0x193` 在引导**结束**、与姿势同刻放，重制在引导开始放（`SkillEffectScriptPlayer`）。
- 录屏 026 的火球在姿势结束（471.60 s）才开始，重制的效果在 1.1 s Cast_Star 环后开始、与 88 tick 姿势有 ≈0.3 s 重叠；效果开始是否等姿势，由施法对象子状态 5 之后的逐 tick 读决定（未读）。
- 脚本 `actInsertLevelUpStar`（WINFAIL，记 `level_up_star_requests`）的星光未接到 `LevelUpStars`。
- 星光与姿势用表现 RNG，原全局随机流不复现；加色层级混合的像素例程未逐条读。

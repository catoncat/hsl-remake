# 魔法伤害：風刃／幻火原公式、HP 结算与共同技能事务

> evidence: static-derived; runtime-measured: 2026-09-24 录屏 474.5–476.0 s 受者条与数字的出现／换值／消失时刻; resource-derived: 初始拥有权 · status: live · functions: 0x407230, 0x4084e0, 0x409920, 0x409940, 0x40a7b0, 0x40aa80, 0x40b8d0, 0x40e390, 0x4104d0, 0x415ba0, 0x423a20, 0x430020, 0x4364e0, 0x43ace0, 0x43ad30, 0x43b3f0, 0x43b4c0, 0x43bf30, 0x442a90 · tools: hsltools/data/skill_book.py, hsltools/probes/magic_damage.py, run_magic_experience_tests.gd, run_skill_resolution_tests.gd · updated: 2026-09-29

## 结论

- 原版：`0x40a7b0` magic／proc0 先抽 1..100 命中（含施法者命中加成与装备魔法命中，落空累计补偿），命中后三角取值 `S`，加等级（1..80）与精神贡献，乘魔击力百分比，低值折返，再按元素抗性（≤80）缩减；不减物理防御；实际损失封顶当前 HP，并作为经验贡献（static-derived；68 组完整返回、24 组 HP 应用前段）。
- 原版风火都是单体；damage 字段 12,26／18,32 不是固定伤害也不是均匀含端点抽样（static-derived）。
- 重制：`SkillResolutionRules` 把风火接入 `NativeMagicRollRules`／`StatusApplicationRules`，PlayLoop 唯一提交；玩家与 AI 同一结算，初始拥有权来自 `content/generated/hsl/skills/initial_book.json`（static-derived；拥有权 resource-derived）。
- 原版法术受者条是施法例程 `0x442a90` 每个受者调一次的 `0x43b3f0`——与用药同一对小条（BAR_HP4 框、BAR_HP5／BAR_HP6 填充、条旁 cur/max）；条先示命中前 HP 24 tick，`0x40b8d0` 结算的同一 tick 换成命中后 HP 并生成数字，再 40 tick 撤条；击杀先等 30 tick，再多 8（eff_proc_Local）／16（Global）tick；全局只有一个条槽，受者逐个接力（static-derived，见「受者条」）。录屏 21／29／60 tick 与之同序，差值在 19.4 ms/tick 折算误差内。
- 多受者时原版逐人处理：前一人撤条后镜头以战斗步长滑向下一人、到位才往下，Local 在他身上再建一份效果、效果完了才出条；受击态从每人扣血那 tick 起；击杀受者在扣血后 30 tick 标死亡，死亡演出与后续受者并行（static-derived，见「逐受者序列」）。
- `0x442a90` 不按魔法功能分支：回复、状态、增益、解除与伤害法术同样逐受者接力。第 24 tick 的 `0x40b8d0` 即 `0x40aa80` 通道 0，每个受者至多出一个数——命中伤害红字，否则 Heal 位的绿字（回复 0 也出），否则什么都没生效时 MISS；状态、增益、解除生效不出字，地图路径没有蓝色 MP 数字；只有命中伤害或负面状态抽判成功的受者进受击态（static-derived，见「结算分派」）。
- 重制 `MagicImpactPresentation` 对所有地图法术照上述画法、计数、逐受者序列与结算分派（static-derived）；首个受者前的镜头滑动照原版：Global 在效果后（状态 9 入口，`MagicImpactPresentation._lead`）、Local 在效果前（`SkillEffectScriptPlayer._first_receiver_glide`），镜头已在 `0x43bf30` 容差内时不动；魔法效果阶段位（`[0x4c1b00]` 0x1000000）Global 在效果脚本走到 op 0 时清（状态 9 入口，随后才滑镜、出条）、Local 撑到最后一人撤条且最后一段效果脚本走完后清，压暗、抬层与影子藏匿都读它（static-derived）。

## 证据

**static-derived**（EXE SHA 同 [original_experience.md](original_experience.md)；结果见 [original_magic_damage.json](original_magic_damage.json)）

| 步骤 | 规则 |
| --- | --- |
| 源值 | 風刃 damage 12,26，幻火 18,32；hit_ratio 96、MP 8、eff_proc_Local、range3CellCircle、effect_range0Cell |
| 命中 | 1..100 抽样，含 caster hit_bonus 与装备魔法命中；落空不抽伤害，累计补偿增加；命中清零 |
| 取值 | `h=floor((high-low)/2)`，`S=low+h-rand(h+1)+rand(h+1)` |
| 能力 | 等级夹 1..80；精神 <36 贡献精神/2，否则 18+(精神−36)/4；(等级+精神贡献+S)×魔击力/100 |
| 修正 | 不足 3 走原折返；按元素抗性（最高 80）缩减；无物理防御减法 |
| 结算 | `0x40ab55..0x40ab81` 把损失限制到当前 HP，同值作为经验贡献 |

68 组覆盖等级、精神 36 分界、低魔击折返、0／80 抗性、命中失败／补偿／装备加成与 no_attack 资格；24 组前段覆盖 1／5／100HP 的过量扣血与未命中，止于 `0x40ab87` 或 `0x40abb0`，未执行显示回调；经验尾部见 [original_experience.md](original_experience.md)。

**resource-derived**（`hsltools/data/skill_book.py` 连接 PLAYERS **character** 段与 `mag-spc.h` 别名位，输出各表哈希、66 个角色的相关声明与受支持初始列表）

| 稳定 ID | 初始来源 | 定义与别名 |
| --- | --- | --- |
| `special:magicOTHER:magicCode01` | 001 的 special_other=氣刃斬 | SPECIAL magicOTHER/Code01，别名 0x1 |
| `magic:magicAIR:magicCode01` | 026 的 magic_wind=風刃 | MAGIC magicAIR/Code01，别名 0x1 |
| `magic:magicFIRE:magicCode01` | 026 的 magic_fire=幻火 | MAGIC magicFIRE/Code01，别名 0x1 |

021／023／024 无这些字段，生成空声明；025 的 magic_wind=酸蝕幻霧 别名 0x10，不获得 Code01 風刃。

**runtime-measured**（原版录像 V08 `14_tactical_map_magic_aoe/frame_041.png`、`frame_046.png`）：前者是目标脚边的短 HP/MP 条与当前/上限数字，后者换成伤害数字；不是半屏状态页。

**runtime-measured**（`录屏2026-09-24 中午12.03.22.mov`，私有档案只读；游戏区 `crop=1280:960:112:140` 缩 640×480，30 fps 逐帧；第一战帝國法師幻火命中桥上一般兵，伤害 19；本机 19.4 ms/tick，见 [tick 率](../runtime_observations/original_tick_rate/README.md)）：

| 时刻 | 画面 | 距条出现 | 折 tick |
| --- | --- | --- | --- |
| 474.600 s | 受者脚边出现 HP 条 `30/40`、MP 条 `0/0`，受者白亮 | 0 | 0 |
| 475.000 s | HP 条换成 `11/40`，受者换受击姿势 | 0.400 s | 20.6 → 21 |
| 475.167 s | 头上出现数字首位 `1`（逐位揭示，475.40 s 成 `19`） | 0.567 s | 29.2 → 29 |
| 475.767 s | 两条消失，数字留下 | 1.167 s | 60.1 → 60 |

每档 ±1 帧（33 ms ≈ ±1.7 tick）。本例单受者。

### 受者条

**static-derived**（`r2 -q -c 's 0x442d00; pD 0x220' hsl01.exe`、`s 0x443040; pD 0x290`、`s 0x43b3f0; pD 0x40`、`s 0x43b4c0; pD 0x20`；子状态表 `pxw 0x3c @ 0x4432c8`、`px 0x1e @ 0x443304`）

`0x43b3f0` 的全部调用点是用药两处（`0x440398`、`0x444acf`）与施法例程 `0x442a90` 两处（`0x442dd3`、`0x4430af`）；`0x43b4c0` 撤条在施法例程里是 `0x442ea1`、`0x44323a`。`0x442a90` 开头按 MAGIC 行 `+0x2c`（`effect_proc`，`0x409920`）分两条轨道：非 0（Global）进子状态 1 起，为 0（Local）`0x442bf1` 置子状态 0x14。两条轨道的受者段同型：

| 子状态（Global／Local） | 地址 | 每 tick 做什么 |
| --- | --- | --- |
| 效果建好后 | `0x442d4e`／`0x443054` | 置 `+0x9c = 24`（`0x18`） |
| 9／0x1b | `0x442da3`／`0x4430a9` | `0x43b3f0(受者)`（`[0x4c1cc8]` 非 0 即返回，只建一次）；`+0x9c` 减一，到 0：置 `+0x9c = 40`（`0x28`）、`+0x9e = 0`，`0x40b8d0` → `0x40aa80` 扣 HP 并由 `0x40aba0` 生成数字；受者 live HP ≤ 0 时 `0x40e390`、`+0x9c += 16`（`0x442e6f`）／`+= 8`（`0x443143`）、`+0x9e += 30`（`0x44314b`） |
| 10／0x1c | `0x442e7c`／`0x443181` | `+0x9e` 非 0 先逐 tick 减，到 0 那 tick 给受者置死亡标 `0x8000000`（`0x4431a0`）；之后 `+0x9c` 减到 0：`0x43b4c0` 撤条，`0x4104d0(1)` 取下一受者，有则回 9（Global，镜头滚向它）／0x19（Local，镜头滚向它并在它身上再建一份效果） |

### 逐受者序列

**static-derived**（`r2 -q -c 's 0x442da3; pD 0x160' hsl01.exe`、`s 0x442ef5; pD 0x150`、`s 0x442cef; pD 0xb4`、`s 0x430020; pD 0x60`、`s 0x423a20; pD 0x70`；`[0x4c432c]` 即施法上下文 `0x4c42a0 + 0x8c` 的子状态）

| 步 | 地址 | 做什么 |
| --- | --- | --- |
| 取下一受者 | `0x442ea8`／`0x443241` | 撤条后 `0x4104d0(1)` 写 `0x4c1cec`；有下一人：Global 子状态减 1 回 9、Local 减 3 回 0x19，并 `0x430020(受者)` 登记；`+0x9c = 24`；没有：Global 置 0x1d、Local 清 `[0x4c1b00]` 的 0x1000000 并加 1 到 0x1d |
| 镜头 | `0x442dbd`（Global 子状态 9）／`0x44301e`（Local 0x19） | 每 tick 调 `0x43bf30(受者, 0／0x80000000)`，返回 0 就直接返回——不建条、不减 `+0x9c`；到位那 tick 才往下（战斗步长与容差见 [original_script_camera_scroll.md](original_script_camera_scroll.md)） |
| Local 重建效果 | `0x44302e..0x443097` | 到位后 `0x409940` 取效果号、`0x415ba0` 放声，子状态进 0x1a（空转），`0x423a20(受者 +4, +8, 效果, 0x4c42a0, 1)` 建效果对象；建成就等它结束时把上下文 `+0x8c` 加 1 进 0x1b，建不成直接进 0x1b；首个受者走的也是 0x19 这一步，所以每个受者一份、前后不重叠 |
| 条与扣血 | 子状态 9／0x1b | 同「受者条」：条第 24 tick `0x40b8d0` 扣血，`0x40aa80` 的 `0x40b831` 让受伤受者进受击态 `0x407230`——受击姿势从这一 tick 起 |
| 击杀 | `0x442e5c`／`0x443130` → 0x1c `0x443181..0x4431c8` | `0x40e390` 记击杀，`+0x9e = 30`；之后每 tick 只减 `+0x9e`（`+0x9c` 不动），减到 0 那 tick 给受者 `+0x80 |= 0x8000000`、`+0x9c = 0`、`+0xa8 = 施法者`、`+0xac = 0`；受者自己的过程由此进死亡入口（`0x43ef36`／`0x44347e`，台词、拉伸消散，见 [original_death_disposal.md](original_death_disposal.md)），施法例程接着把 `+0x9c` 的 40＋8／16 减完再撤条、取下一受者，两边各走各的 |

击杀受者的条共 24＋30＋48（Local）／56（Global）tick；死亡标在条内第 54 tick（扣血后第 30 tick）。

条由 `0x43b3f0` 经 `0x43ace0`／`0x43ad30` 建，画法、位置与条旁 cur/max 见 [original_item_use_presentation.md](original_item_use_presentation.md)；条过程 `0x4364e0` 读 live cur/max，所以扣血那 tick 起条就是命中后 HP。条槽 `[0x4c1cc8]` 全局只有一个，受者逐个出条，不会两条同时在场。

### 结算分派

**static-derived**（`r2 -q -e scr.color=0 -e asm.bytes=false -c 'pD 0x40 @ 0x40b8d0; pD 0xdb1 @ 0x40aa80; pD 0x60 @ 0x40b831' hsl01.exe`、`pd 30 @ 0x40b883`、`pd 60 @ 0x4084e0; pd 40 @ 0x442e00; pd 40 @ 0x4430d8`、`pD 0x2d0 @ 0x40a7b0`）

`0x40b8d0` 只是 `0x40aa80(施法者, 受者, 序号, 魔法码, 通道 0)`（`0x40b8f0` 同形、通道 1 是近景）。`0x40aa80` 的局部量：显示标 `[esp+0x38]`（`0x40aae1` 清 0）、受击计数 `[esp+0x14]`、本地 EXP `[esp+0x18]`（`0x40ab0a` 清 0）；`0x4c13fc` 是本次贡献（`0x40aaf4` 清 0）。按 MAGIC 行 function 位逐支执行；出数经 `0x4084e0(x, y−0x34, 值, 等待引用, 种类, 停留)`，先建对象 0xb1（`0x45e307`）再经 `0x45b6de` 写数字，不判 0。第 24 tick 每个受者：

| function（位） | 做什么 | 第 24 tick 出什么 | 零变化 | 受击计数 |
| --- | --- | --- | --- | --- |
| Attack（1） | `0x40a7b0` proc0 非 0：扣 HP 夹到当前 HP，计数置 1（`0x40ab73`），显示标 1 | 红 kind 0 伤害（`0x40aba0`） | 落空不出数、不计数 | 命中即进 |
| Heal（2） | proc1 非 0：加 HP 夹到上限，`0x4c13fc += 回复/2` | 显示标仍 0 时绿 kind 2，值为夹后回复（`0x40ac24`），显示标 1 | 满血回复 0 也出绿 `0` | 不计 |
| — | `0x40ac34` 受者 HP 为 0 | 以下各支全部跳过（到 `0x40b81f`） | — | — |
| Paralysis（4）／Poison（8）／NoMagic（0x10）／Weaken（0x1000） | 各自抽判（先查免疫位 `0x40e2f0`）；成功计数加一、`0x4c13fc` 加贡献（麻痹、中毒为 10×实加层数，层数封顶 9），`0x4c13fc ≠ 0` 置显示标（`0x40ace5`、`0x40ae31`、`0x40aed4`、`0x40b014`） | 不出数 | 全落空且无别的贡献 → MISS；层数已 9 时贡献 0 → MISS，但计数已加 | 抽判成功即进 |
| DefUp（0x20，`0x40b01c`）／AttUp（0x40，`0x40b112`）／AllUp（0x100，`0x40b1ee`） | 加 `0x4c13fc`，非 0 置显示标（`0x40b10a`、`0x40b1e6`、`0x40b291`） | 不出数 | 贡献 0 → MISS | 不计 |
| ClearAtDfUp（0x4000，`0x40b29d`）／CureWeaken（0x2000，`0x40b30f`）／CureParalysis（0x200，`0x40b35c`）／CurePoison（0x400，`0x40b3a6`）／CureNoMagic（0x800，`0x40b3ec`） | 受者有该状态才动：清位、`0x4c13fc += 12×(层数+1)`、置显示标（`0x40b303`、`0x40b354`、`0x40b39e`、`0x40b3e4`、`0x40b42a`） | 不出数 | 没有该状态 → 无贡献 → MISS | 不计 |
| HealMP（0x8000，`0x40b432..0x40b4aa`） | proc1 加 MP 夹到 `+0xe4`；夹后非 0 则本地 EXP = `0x40a5d0(…)` | 不出数（地图路径无蓝字） | 夹后 0 不记 EXP；MAGIC.TXT 39 个法术都没有此位 | 不计 |

收尾：`0x40b831` 通道 0 且计数非 0 → `0x407230(受者)` 进受击态；`0x40b84b` 本地 EXP 非 0 直接带经验返回、不判 MISS；否则 `0x40b883` 通道 0 且显示标为 0 → `0x40b8a3` kind 5 MISS（同点 x, y−0x34）。所以每个受者至多一个数，红伤害优先，其次绿回复，其次 MISS；施加成功的状态、增益、解除不出字。施法例程两处调用点 `0x442e18`／`0x4430f4` 只在返回经验非 0 时查击杀。`0x40aa80` 另有 0x10000–0x100000 五个位分支也给受击计数加一，但通道 0 只由这两处施法调用（读 MAGIC 表 `0x4c2ca0`），MAGIC.TXT 没有这些位，地图法术走不到。

## 重制接线

- `game/sim/SkillResolutionRules.gd` `available`／`prepare`／`resolve`：按稳定 ID 核对定义、初始拥有权、已支持 function／范围、资格、MP／ST 与抗性；非法字段在 RNG 前拒绝；只返回 `{ok, caster_changes, target_changes, receipt}` 提案，不改输入。
- PlayLoop `_resolve_skill`：玩家特殊技与法师 AI 的唯一资源／HP 提交点；所有目标资格与数值准备好后才抽样；一次提交付款、全目标状态、连续数与最终经验；缺抗性等坏数据以 `scenario_error` 停下，不改用物理攻击。
- `MagicImpactPresentation`：所有带 `magic_key` 的地图法术（`is_relayed`；回复、状态、增益、解除与伤害同样）受者逐个接力，`SkillEffectScriptPlayer` 的 Local 效果据同一判定只放在首个受者；第 2 人起在前一人撤条那 tick 以 `BattleCameraController.scroll_to`（战斗步长）滑向他，滑完才往下；Local 再用 `SkillEffectScriptPlayer.draw` 在他格中心重放施法的效果时间线，条在重放的 impact tick 出（与首个受者相对施法效果的关系相同）；条与数字每帧按镜头重算屏幕位置。`MapHitState.begin` 由接力在每人结算那 tick 只对 `MapHitState.hurt` 的受者调（命中且伤害 >0 或负面状态施加成功、受者未死；`BattlePresentation._present_impact` 不再全体同起）；击杀受者扣血后 30 tick `death_released` 放行，`BattleAftermath.advance` 在接力进行中只起已放行的死亡任务，EXP／$ 仍等接力结束。每人用 `BattleItemUsePresentation` 的小条常量与 BAR_HP4..6 画两条，先示前态 HP／MP（不可变收据 `defender_before`）24 tick，第 24 tick 两条换后态（HP 取 `defender_hp_after`，MP 加 `restored_mp`）并按 `settle_number` 出数——收据 `actual_damage` >0 红字，否则技能行 function 含 `magicFun_Heal` 出绿 `healing`（含 0），否则 `native_contribution` 为 0 且 `immediate_contributions` 为空出 MISS，其余不出数；OPT-INFO=公開 时 `captions` 回调（`BattlePresentation._present_receiver_captions`）在同一 tick 把状态名、免疫／未生效与 HP／MP 字排在该受者数字上方，原版路径不出这些字；再 40 tick 撤条（击杀 +30 再 +8／+16，按技能行 `effect_proc`）（`BEFORE_TICKS`／`AFTER_TICKS`／`KILL_*`，按 16 ms/tick 播放）；之后遗言／淡出 → KILL 连续数 → 最终 EXP → 金币／领取 → 成长／交接。
- 共享规则能处理注册允许的区域攻击，但风火本身保持单体；多目标支援使用原驱毒范围。

## 复现

`python3 tools/hsl.py check magic_damage`；`python3 tools/hsl.py check initial_skill_book`；重制侧 `tools/godot.sh --headless --script tests/run_magic_experience_tests.gd`。八条 Control 回执（`runtime_observations/magic_experience/receipt.json`：wind、fire_kill、mixed_area、heal_xp、cure_xp、empty_mp、silence、final_kill）驱动已退役，回执为历史记录。

## 边界

- 原 PLAYERS 字节与导入表的严格 `--pak` 比较曾不一致，差异未查明，拥有权只按导入表声明。
- 动态学习、升级解锁、转职、禁用状态与角色模式对拥有权的影响未读。
- `0x43bf30` 第二参数 Local 为 0x80000000、Global 为 0，含义未读；重制两边同用战斗步长。
- Local 重放只画效果时间线的对象与声音；`[0x4c1b00]` 0x1000000 在 0x19 重新置位，重制的位从首个受者撑到最后一人撤条且最后一段重放的脚本走完，压暗不中断，结果相同。OtherBBall1 镜头轨迹与 IconBGSet／FireBGSet 波纹只出现在 Global 法术里，Local 重放碰不到。重放的条在 impact tick（最后一个 cue）出，原版 `0x1a` 等解释器走到 op 0 才出条，与首个受者一致；Local 清位因此仍比原版早，见 [original_cast_overlays.md](original_cast_overlays.md) 边界。
- 死亡受者的入口 `0x43eff9` 也调 `0x43bf30(受者)` 等镜头，与施法例程滑向下一受者同帧争镜头时谁先到未读；重制死亡任务不滑镜头。台词窗期间接力照走（原版台词由受者过程 `+0x9c` 轮询关闭，施法例程不等它）。
- 受者顺序按收据 `affected_targets`；`0x4104d0` 的遍历顺序未与之逐一对照。
- 结算分派在重制侧由收据推断（sim 不改）：`native_contribution`／`immediate_contributions` 代 `0x4c13fc`／本地 EXP；收据分不出回复抽判落空与满血，重制凡 Heal 位一律出绿字，按 MAGIC.TXT 回复法术 hit_ratio 均为 100、proc1 不会落空推断。
- 麻痹／中毒／封魔／虚弱层数已 9 时原版出 MISS 却仍进受击态；重制 MISS 相同（贡献 0），受击态依收据 `status_effects` 的 `applied`，sim 对这一情形怎么记未逐一对照。
- 受者提亮闪光（`MagicImpactPresentation` 按命中提亮）只有伤害法术录屏为据，原版条件未读；现在接力扩到全部地图法术，回复、增益、解除的受者也会提亮。
- 氣刃斬与普通交锋公式见 [original_ordinary_special.md](original_ordinary_special.md)；费用见 [original_skill_resources.md](original_skill_resources.md)。

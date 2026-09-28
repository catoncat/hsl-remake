# 魔法伤害：風刃／幻火原公式、HP 结算与共同技能事务

> evidence: static-derived; runtime-measured: 2026-09-24 录屏 474.5–476.0 s 受者条与数字的出现／换值／消失时刻 · status: live · functions: 0x407230, 0x40a7b0, 0x4104d0, 0x423a20, 0x430020, 0x43b3f0, 0x43b4c0, 0x43bf30, 0x442a90 · tools: hsltools/data/skill_book.py, hsltools/probes/magic_damage.py, run_magic_experience_tests.gd, run_skill_resolution_tests.gd · updated: 2026-09-28

## 结论

- 原版：`0x40a7b0` magic／proc0 先抽 1..100 命中（含施法者命中加成与装备魔法命中，落空累计补偿），命中后三角取值 `S`，加等级（1..80）与精神贡献，乘魔击力百分比，低值折返，再按元素抗性（≤80）缩减；不减物理防御；实际损失封顶当前 HP，并作为经验贡献（static-derived；68 组完整返回、24 组 HP 应用前段）。
- 原版风火都是单体；damage 字段 12,26／18,32 不是固定伤害也不是均匀含端点抽样（static-derived）。
- 重制：`SkillResolutionRules` 把风火接入 `NativeMagicRollRules`／`StatusApplicationRules`，PlayLoop 唯一提交；玩家与 AI 同一结算，初始拥有权来自 `content/generated/hsl/skills/initial_book.json`（static-derived；拥有权 resource-derived）。
- 原版法术受者条是施法例程 `0x442a90` 每个受者调一次的 `0x43b3f0`——与用药同一对小条（BAR_HP4 框、BAR_HP5／BAR_HP6 填充、条旁 cur/max）；条先示命中前 HP 24 tick，`0x40b8d0` 结算的同一 tick 换成命中后 HP 并生成数字，再 40 tick 撤条；击杀先等 30 tick，再多 8（eff_proc_Local）／16（Global）tick；全局只有一个条槽，受者逐个接力（static-derived，见「受者条」）。录屏 21／29／60 tick 与之同序，差值在 19.4 ms/tick 折算误差内。
- 多受者时原版逐人处理：前一人撤条后镜头以战斗步长滑向下一人、到位才往下，Local 在他身上再建一份效果、效果完了才出条；受击态从每人扣血那 tick 起；击杀受者在扣血后 30 tick 标死亡，死亡演出与后续受者并行（static-derived，见「逐受者序列」）。
- 重制 `MagicImpactPresentation` 照上述画法、计数与逐受者序列（static-derived）。

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

## 重制接线

- `game/sim/SkillResolutionRules.gd` `available`／`prepare`／`resolve`：按稳定 ID 核对定义、初始拥有权、已支持 function／范围、资格、MP／ST 与抗性；非法字段在 RNG 前拒绝；只返回 `{ok, caster_changes, target_changes, receipt}` 提案，不改输入。
- PlayLoop `_resolve_skill`：玩家特殊技与法师 AI 的唯一资源／HP 提交点；所有目标资格与数值准备好后才抽样；一次提交付款、全目标状态、连续数与最终经验；缺抗性等坏数据以 `scenario_error` 停下，不改用物理攻击。
- `MagicImpactPresentation`：受者逐个接力；第 2 人起在前一人撤条那 tick 以 `BattleCameraController.scroll_to`（战斗步长）滑向他，滑完才往下；Local 再用 `SkillEffectScriptPlayer.draw` 在他格中心重放施法的效果时间线，条在重放的 impact tick 出（与首个受者相对施法效果的关系相同）；条与数字每帧按镜头重算屏幕位置。`MapHitState.begin` 由接力在每人扣血那 tick 调（`BattlePresentation._present_impact` 对接力法术不再全体同起）；击杀受者扣血后 30 tick `death_released` 放行，`BattleAftermath.advance` 在接力进行中只起已放行的死亡任务，EXP／$ 仍等接力结束。每人用 `BattleItemUsePresentation` 的小条常量与 BAR_HP4..6 画两条，先示前态 HP（不可变收据 `defender_before`）24 tick，第 24 tick 换后态并出实际伤害／闪避数字，再 40 tick 撤条（击杀 +30 再 +8／+16，按技能行 `effect_proc`）（`BEFORE_TICKS`／`AFTER_TICKS`／`KILL_*`，按 16 ms/tick 播放）；之后遗言／淡出 → KILL 连续数 → 最终 EXP → 金币／领取 → 成长／交接。
- 共享规则能处理注册允许的区域攻击，但风火本身保持单体；多目标支援使用原驱毒范围。

## 复现

`python3 tools/hsl.py check magic_damage`；`python3 tools/hsl.py check initial_skill_book`；重制侧 `tools/godot.sh --headless --script tests/run_magic_experience_tests.gd`。八条 Control 回执（`runtime_observations/magic_experience/receipt.json`：wind、fire_kill、mixed_area、heal_xp、cure_xp、empty_mp、silence、final_kill）驱动已退役，回执为历史记录。

## 边界

- 原 PLAYERS 字节与导入表的严格 `--pak` 比较曾不一致，差异未查明，拥有权只按导入表声明。
- 动态学习、升级解锁、转职、禁用状态与角色模式对拥有权的影响未读。
- 首个受者前的镜头：原版 Global 在效果后、Local 在效果前也各滑一次到首个受者（子状态 9／0x19 对每人同样执行），重制只对第 2 人起滑镜头，首个受者沿用施法效果时的镜头。
- `0x43bf30` 第二参数 Local 为 0x80000000、Global 为 0，含义未读；重制两边同用战斗步长。
- Local 重放只画效果时间线的对象与声音，不重做压暗（`[0x4c1b00]` 0x1000000 在 0x19 重新置位）与 OtherBBall1 的镜头轨迹、IconBGSet 波纹；重放的条在 impact tick 出而非等效果对象删除，与首个受者一致。
- 死亡受者的入口 `0x43eff9` 也调 `0x43bf30(受者)` 等镜头，与施法例程滑向下一受者同帧争镜头时谁先到未读；重制死亡任务不滑镜头。台词窗期间接力照走（原版台词由受者过程 `+0x9c` 轮询关闭，施法例程不等它）。
- 受者顺序按收据 `affected_targets`；`0x4104d0` 的遍历顺序未与之逐一对照。
- 氣刃斬与普通交锋公式见 [original_ordinary_special.md](original_ordinary_special.md)；费用见 [original_skill_resources.md](original_skill_resources.md)。

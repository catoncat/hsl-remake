# 魔法伤害：風刃／幻火原公式、HP 结算与共同技能事务

> evidence: static-derived; runtime-measured: 2026-09-24 录屏 474.5–476.0 s 受者条与数字的出现／换值／消失时刻 · status: live · functions: 0x40a7b0 · tools: hsltools/data/skill_book.py, hsltools/probes/magic_damage.py, run_magic_experience_tests.gd, run_skill_resolution_tests.gd · updated: 2026-09-27

## 结论

- 原版：`0x40a7b0` magic／proc0 先抽 1..100 命中（含施法者命中加成与装备魔法命中，落空累计补偿），命中后三角取值 `S`，加等级（1..80）与精神贡献，乘魔击力百分比，低值折返，再按元素抗性（≤80）缩减；不减物理防御；实际损失封顶当前 HP，并作为经验贡献（static-derived；68 组完整返回、24 组 HP 应用前段）。
- 原版风火都是单体；damage 字段 12,26／18,32 不是固定伤害也不是均匀含端点抽样（static-derived）。
- 重制：`SkillResolutionRules` 把风火接入 `NativeMagicRollRules`／`StatusApplicationRules`，PlayLoop 唯一提交；玩家与 AI 同一结算，初始拥有权来自 `content/generated/hsl/skills/initial_book.json`（static-derived；拥有权 resource-derived）。
- 原版法术命中时受者脚边的 HP／MP 条先显示命中前 HP，约 21 tick 后换成命中后 HP，约 29 tick 出数字，约 60 tick 条消失而数字留下（runtime-measured，19.4 ms/tick 折算）；重制 `MagicImpactPresentation` 按这三个节拍，多受者各在本格、不互相避让（runtime-reference）。
- 差异：短资源条的尺寸与颜色是重制画法（provisional）。

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

每档 ±1 帧（33 ms ≈ ±1.7 tick）。条寿命 60 tick 与受击态 `0x407230` 写入的 `+0x92 = 60` 同长，是否同一计数未读。本例单受者，未见多受者时条的排布。

## 重制接线

- `game/sim/SkillResolutionRules.gd` `available`／`prepare`／`resolve`：按稳定 ID 核对定义、初始拥有权、已支持 function／范围、资格、MP／ST 与抗性；非法字段在 RNG 前拒绝；只返回 `{ok, caster_changes, target_changes, receipt}` 提案，不改输入。
- PlayLoop `_resolve_skill`：玩家特殊技与法师 AI 的唯一资源／HP 提交点；所有目标资格与数值准备好后才抽样；一次提交付款、全目标状态、连续数与最终经验；缺抗性等坏数据以 `scenario_error` 停下，不改用物理攻击。
- `MagicImpactPresentation`：短资源条（42×7）先示前态 HP（不可变收据 `defender_before`），第 21 tick 换后态，第 29 tick 起出实际伤害／闪避数字，第 60 tick 条消失（`BEFORE_TICKS`／`NUMBER_TICKS`／`BAR_TICKS`，按 16 ms/tick 播放）；多受者各在本格，不做避让；之后遗言／淡出 → KILL 连续数 → 最终 EXP → 金币／领取 → 成长／交接（provisional：条的位置、尺寸、颜色）。
- 共享规则能处理注册允许的区域攻击，但风火本身保持单体；多目标支援使用原驱毒范围。

## 复现

`python3 tools/hsl.py check magic_damage`；`python3 tools/hsl.py check initial_skill_book`；重制侧 `tools/godot.sh --headless --script tests/run_magic_experience_tests.gd`。八条 Control 回执（`runtime_observations/magic_experience/receipt.json`：wind、fire_kill、mixed_area、heal_xp、cure_xp、empty_mp、silence、final_kill）驱动已退役，回执为历史记录。

## 边界

- 原 PLAYERS 字节与导入表的严格 `--pak` 比较曾不一致，差异未查明，拥有权只按导入表声明。
- 动态学习、升级解锁、转职、禁用状态与角色模式对拥有权的影响未读。
- 原 UI 句柄不在本包；受者条的绘制函数与三个节拍的计数没有静态读出，只有录屏折算（runtime-reference）；替换路线：从 `0x40aa80` 尾部与 `0x40aba0` 的调用者往上找建条对象。
- 多受者法术时各条是否重叠没有原版帧（provisional）。
- 氣刃斬与普通交锋公式见 [original_ordinary_special.md](original_ordinary_special.md)；费用见 [original_skill_resources.md](original_skill_resources.md)。

# 魔法伤害：風刃／幻火原公式、HP 结算与共同技能事务

> evidence: static-derived · status: live · functions: 0x40a7b0 · tools: hsltools/data/skill_book.py, hsltools/probes/magic_damage.py, run_magic_experience_tests.gd, run_skill_resolution_tests.gd · updated: 2026-09-27

## 结论

- 原版：`0x40a7b0` magic／proc0 先抽 1..100 命中（含施法者命中加成与装备魔法命中，落空累计补偿），命中后三角取值 `S`，加等级（1..80）与精神贡献，乘魔击力百分比，低值折返，再按元素抗性（≤80）缩减；不减物理防御；实际损失封顶当前 HP，并作为经验贡献（static-derived；68 组完整返回、24 组 HP 应用前段）。
- 原版风火都是单体；damage 字段 12,26／18,32 不是固定伤害也不是均匀含端点抽样（static-derived）。
- 重制：`SkillResolutionRules` 把风火接入 `NativeMagicRollRules`／`StatusApplicationRules`，PlayLoop 唯一提交；玩家与 AI 同一结算，初始拥有权来自 `content/generated/hsl/skills/initial_book.json`（static-derived；拥有权 resource-derived）。
- 差异：地图短资源条、数字的颜色与时长是重制编排（provisional）。

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

## 重制接线

- `game/sim/SkillResolutionRules.gd` `available`／`prepare`／`resolve`：按稳定 ID 核对定义、初始拥有权、已支持 function／范围、资格、MP／ST 与抗性；非法字段在 RNG 前拒绝；只返回 `{ok, caster_changes, target_changes, receipt}` 提案，不改输入。
- PlayLoop `_resolve_skill`：玩家特殊技与法师 AI 的唯一资源／HP 提交点；所有目标资格与数值准备好后才抽样；一次提交付款、全目标状态、连续数与最终经验；缺抗性等坏数据以 `scenario_error` 停下，不改用物理攻击。
- `MagicImpactPresentation`：短资源条（42×7）→ 实际伤害／闪避数字，之后遗言／淡出 → KILL 连续数 → 最终 EXP → 金币／领取 → 成长／交接；前态 HP/MP/等级来自不可变收据（provisional：位置、颜色、0.45 秒条值／0.75 秒数字）。
- 共享规则能处理注册允许的区域攻击，但风火本身保持单体；多目标支援使用原驱毒范围。

## 复现

`python3 tools/hsl.py check magic_damage`；`python3 tools/hsl.py check initial_skill_book`；重制侧 `tools/godot.sh --headless --script tests/run_magic_experience_tests.gd`。八条 Control 回执（`runtime_observations/magic_experience/receipt.json`：wind、fire_kill、mixed_area、heal_xp、cure_xp、empty_mp、silence、final_kill）驱动已退役，回执为历史记录。

## 边界

- 原 PLAYERS 字节与导入表的严格 `--pak` 比较曾不一致，差异未查明，拥有权只按导入表声明。
- 动态学习、升级解锁、转职、禁用状态与角色模式对拥有权的影响未读。
- 原 UI 句柄与精确时钟不在本包。
- 氣刃斬与普通交锋公式见 [original_ordinary_special.md](original_ordinary_special.md)；费用见 [original_skill_resources.md](original_skill_resources.md)。

# 技能资源：MP／ST 费用、使用门槛与扣除

> evidence: static-derived · status: live · functions: 0x408fe0, 0x409040, 0x409890, 0x409980, 0x40e240, 0x40e290 · tools: hsltools/probes/skill_cost.py, run_skill_resolution_tests.gd · updated: 2026-09-27

## 结论

- 原版：魔法费用＝表值 expend，减耗位（actor+0x18c bit1，来自 ITEM `mp_use_half`）时门槛用 `floor(expend/2)`；特殊技费用＝`20×expend` 比较当前 ST，等于门槛允许；魔法扣费把减半结果为 0 的改成 1，门槛却不改，所以 expend=1、减耗、MP=0 时原版允许施放并扣到 MP=-1（static-derived；32 组 getter／门槛完整返回与一段扣费代码块执行）。
- 重制：`SkillResourceRules.amounts/quote` 由玩家特殊技、法师 AI 与 `BattlePlayLoop.can_use_special` 共用；命中／落空都付一次，取消、错误目标、旧确认无扣除（static-derived）。
- 差异：重制要求实际资源足以支付扣除额，禁止负 MP／ST——只在上述极小减耗边界比原版严（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；原 PAK `@:\data\magic.txt`、`special.txt`、`item.txt` 与导入表只差行尾和 SPECIAL 末尾空行；28 段锚点与 32 组结果见 [original_skill_resources.json](original_skill_resources.json)）

| 资源操作 | 原入口／字段 | 行为 |
| --- | --- | --- |
| 表加载 | special：`0x44d571` 读段，`0x44d5f3`／`0x44d602` 登记到 `0x4c3920`，`0x44d699` 找 `expend`，`0x44d6b3` 存 +0x10；magic：`0x44d9d4` 起，`0x44da60`／`0x44da6f` 登记到 `0x4c2ca0`，`0x44db06`／`0x44db20` 存 +0x10 | — |
| 魔法基础费用 | `0x409890`，Magic 记录 +0x10 | 返回 expend |
| 魔法是否足够 | `0x408fe0`，actor+0xe0 | 普通用 expend；减耗位时用 `floor(expend/2)` 比较 MP |
| 特殊技费用 | `0x409980`，Special 记录 +0x10 | `lea x*5; shl 2`，即 `20×expend` |
| 特殊技是否足够 | `0x409040`，actor+0xe8 | 与 `20×expend` 比较，相等允许 |
| 减耗谓词 | `0x40e290` → `0x40e240` | actor+0x18c bit1（掩码 2） |
| 减耗来源 | ITEM `mp_use_half`：`0x447ddf` 读，`0x447df4` 置掩码 2，`0x4481b1` 写 ITEM+0xa0；`0x448709..0x448717` 并入 actor+0x18c | 与 actor+0xa0 掩码 2（禁攻击）、ITEM+0xa4 掩码 2（take_off）不同 |
| 魔法扣费 | `0x442b99` 读费用，`0x442ba1` 查减耗；`0x442bad..0x442bbc` 除 2 截断、0 改 1；`0x442bc1..0x442bce` 从 MP 减 | 门槛不做最低 1 修正，扣费做 |
| 特殊技扣费 | 玩家 `0x44529e` 调 getter、`0x4452af` 存扣后 ST；另一路径 `0x441cf3`／`0x441d00` 同 getter | caller 只做静态字节核对 |

执行范围：32 组覆盖 magic／special、expend 0／1／3／6、减耗开关、门槛下 1／恰好／上 1，在合成对象上两次执行原 getter 与门槛（无 stub，512 条指令上限，actor 内存不变）；魔法例另从 `0x442ba9` 执行到 `0x442bcf`（128 条上限，只允许 MP 变），是内部代码块，机器包 `full_spell_function_return=false`。

**resource-derived**：Leonard 的氣刃斬来自 `PLAYERS.TXT` 角色 1 `special_other=氣刃斬`，`mag-spc.h` 映射到 Other 组 bit1，`SPECIAL.TXT` magicOTHER／magicCode01（RESOURCE 137）；该行 range2Cell、effect_range range0Cell、expend 1、damage 36–54、hit_ratio 98、attackpow_ratio 100、specCode01／02。PAK `data/effects.txt` 把 specCode01 关联到 `MAGIC/SP00_001.SHP`、对象 410 与 `WAV/SP01-001.WAV`；specCode02 延迟 20 插对象 411、等 10、aniProcessHitMiss、插命中对象 412／413、再等 60 调 aniShowHitResult；`global.obs` 给出 SP01_001 两帧、SP01_011 五帧、SP01_021 五帧，延迟 4／1／3／6。导入物在 `content/imported/hsl/shared/first_skill/`。

**runtime-measured**（重制侧 Control 回执，已随回执目录删除）：19ST 时特殊技按钮禁用、点击不改状态；20ST 可用；移动一格后选敌、右键取消保持 20ST 与 pending move；确认后收据 before 20／amount 20／after 0、`native_required=20`，演出后后继 `enemy023_1`、queue.index 1。

## 重制接线

- `game/sim/SkillResourceRules.gd`：`amounts`／`quote` 读来源 expend、当前资源与只读装备 catalog（`mp_use_half` 生成为布尔字段）；收据分存 `native_required` 与实际 `amount`；缺失、负数、非整数、非有限、超 32 位费用域明确失败。
- `BattlePlayLoop.can_use_special`、特殊技提交与法师 AI 费用筛选共用 quote；坏数据进入 `scenario_error` 保留坐标／资源／队列，MP 不足仍可选其他动作。
- 场景旧 `stamina_per_expend` 配置已移除。积气与开场 ST 见 [original_stamina.md](original_stamina.md)；技能初始拥有权见 [original_magic_damage.md](original_magic_damage.md)。

## 复现

`python3 tools/hsl.py check skill_cost`；`python3 tools/hsl.py check first_skill`；重制侧 `tools/godot.sh --headless --script tests/run_skill_resolution_tests.gd`。

## 边界

- 完整特殊技函数与完整魔法函数没有正常返回，特殊技扣费 caller 只有静态字节。
- 另一条 ST 扣费路径 `0x441cf3` 不据此宣称原 AI 路径已恢复。
- 技能拥有权、目标阵营／状态资格、效果公式与 AI 策略不在本包，目标见 [original_skill_targets.md](original_skill_targets.md)。

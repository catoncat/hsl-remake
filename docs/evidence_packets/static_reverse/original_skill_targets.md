# 技能目标：function 到目标模式、覆盖构建与共享来源范围

> evidence: static-derived · status: live · functions: 0x407800, 0x409850, 0x409870, 0x40ba80, 0x40fc90, 0x4100e0, 0x4104d0, 0x446b30 · tools: hsltools/data/skill_targeting.py, hsltools/probes/skill_target.py, run_skill_resolution_tests.gd · updated: 2026-09-28

## 结论

- 原版：玩家施放按技能 function 选目标模式——Magic 用掩码 `0xf62`、Special 用 `0x18f62`，命中为 mode3（排除 pmEnemy），否则 mode2（排除 pmPlayer）；HealMP、ActiveAgain 在 Magic 下是 mode2、在 Special 下是 mode3；覆盖由 `0x4100e0` 按 RANGE 结构写缓冲，`0x4104d0` 去重枚举角色（static-derived；32 组单格夹具完整返回）。
- 重制：`SkillTargetRules` 由玩家特殊技、法师 AI 与战斗预告共用来源 RANGE 矩阵；`definition_error` 按 function 掩码白名单放行，源数据出现的组合都在白名单内（技能无拒绝项，差异清单 `unimplemented-abilities`），白名单外的组合明确报错（static-derived）。
- 差异：敌我判断走重制 role 适配，不是原全部 pm 组合；AI 候选顺序与随机抽选是重制策略（provisional）。

## 证据

**static-derived**（EXE SHA-256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`；TYPE.H／RANGE.TXT 原始与导入哈希分别记录，只允许行尾 ASCII 空白规范化；20 段锚点与 32 组结果见 [original_skill_targets.json](original_skill_targets.json)）

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| function getter | Magic `0x409850`（`0x4c2ca0`，记录 +0x24）；Special `0x409870`（`0x4c3920`，+0x28） | 当前氣刃斬、風刃、幻火均为 `magicFun_Attack=1` |
| Magic 模式 | `0x444e8e` 调 getter，function=0 拒绝；`0x444e9e..0x444eb2` `(function & 0xf62)!=0` → mode3，否则 mode2 | — |
| Special 模式 | `0x44503a` 调 getter；`0x44504a` 掩码 `0x18f62`；`0x445053`／`0x44507f` 写 mode3／2 | ActiveAgain 另进 `0x40ba80` 相关调用 |
| 覆盖构建 | Magic `0x444f08`、Special `0x4450e0` 调 `0x4100e0(角色, XY, effect_range, mode)`；分发表 `0x410498`：mode2 → `0x410155` 排除 0x10000，mode3 → `0x410161` 排除 0x20000 | pmPlayer 0x10000、pmEnemy 0x20000、pmNPC 0x40000 |
| 单格 center | `0x4103cc` 查排除位，0x70000 组合例外；`0x40fc90` 在角色指针非零时清临时地图位，`0x410410` 查 0x850000 标记 | 地图位与有无角色共同决定覆盖 |
| `0x446b30` | actor+0xa0 的 0x10 位 | 语义未命名 |
| 目标枚举 | `0x4104d0(0)` 遍历非零覆盖格经 `0x407800` 查角色，`0x410579` 指针去重，`0x410585` 追加；非零参数取缓存，`0x4105da` 耗尽返回 0 | — |

| function 示例 | Magic 模式 | Special 模式 |
| --- | --- | --- |
| Attack、Poison 等不在掩码中的位 | 2 | 2 |
| Heal、DefUp、AttUp、AllUp、CureParalysis／Poison／NoMagic | 3 | 3 |
| HealMP、ActiveAgain | 2 | 3 |

执行：32 个 1×1 地图／range0Cell 夹具（mode2／3 × 八种地图位 × 有无角色），每例完整执行一次 `0x4100e0`、两次 `0x4104d0`，均正常返回，后继枚举为 0，角色与地图不变；无 stub，8192 指令上限。

**resource-derived**：`range2Cell` 两格十字，`range3CellCircle` 三格菱形，`range0Cell` 单格；矩阵非零值即范围，不按名字推半径。

**runtime-measured**（重制侧 Control 回执，已随回执目录删除）：雷歐納德 (15,17)、20ST，特殊技选格显示 range2Cell 十字；(16,16) 曼哈顿距离 2 但矩阵为 0，点击返回 out_of_range 且状态不变；取消仍 20ST；选 (15,15) 轴向敌人确认后 ST=0，后继 `enemy023_1`、queue.index 1。

## 重制接线

- `game/sim/SkillTargetRules.gd`：解析 TYPE 符号，严格验证来源矩阵与单目标 effect_range；function 掩码不在白名单（源数据以外的组合）时报 `unsupported_skill_function`，不走扣费后伤害路径；效果区域由所选 resolver 逐目标准备。
- `hsltools/data/skill_targeting.py` 生成 `content/generated/hsl/skills/targeting.json`（function 位与来源矩阵）。
- PlayLoop 特殊技选择／确认／提交、AI 法术可达性与战斗预告共用这份范围；法师先按候选位置与真实状态逐法术筛选，再从能命中的法术中抽选；无合法目标不耗 RNG 或资源；先查可行计划再抽倾向的顺序不宣称原 AI 等价（provisional）。
- 场景初始化与 AI 入口 `_skill_input_error` 联合验证费用与目标，失败前不移动、不耗资源、不切队列。
- 方向型范围见 [original_line_ranges.md](original_line_ranges.md)；地形传播 `0x40f8b0`／`0x40fdc0` 见 [original_weapon_ranges.md](original_weapon_ranges.md)。

## 复现

`python3 tools/hsl.py check skill_target`；`python3 tools/hsl.py check skill_target_data`；重制侧 `tools/godot.sh --headless --script tests/run_skill_resolution_tests.gd`。

## 边界

- 同一大角色跨多格的去重分支只有静态锚点，单格夹具未执行。
- 大体型与全部地图标志的生命周期未读。
- `0x446b30` 的 0x10 位来源写入未追，不命名为死亡或禁魔。
- ActiveAgain 的 `0x40ba80` 调用未推成完整再动规则。

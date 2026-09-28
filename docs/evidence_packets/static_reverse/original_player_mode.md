# 换阵营与不死：actSetPlayerMode、actSetPlayerUndead、HPLow 与击杀结算

> evidence: static-derived; provisional: 不死防守方致死后是否仍反击（差异清单 undead-counter-kill） · status: live · functions: 0x40a5d0, 0x40e390, 0x43ede0, 0x4423c0, 0x442720, 0x446bb0, 0x44f580, 0x44fad0, 0x450710, 0x450840, 0x452885 · tools: run_battle_reward_tests.gd, run_battle_scene_runtime_tests.gd, run_winfail_rules_tests.gd · updated: 2026-09-28

## 结论

- 原版：`actSetPlayerUndead` 设／清 live `+0xa0` 位 4；不死单位 HP 归零时照写死亡旗，下一 tick 自己撤销并以 HP 1 继续存活，不减伤也不免疫；`actSetPlayerMode` 改 +0x28、过程码与着色，不刷新属性（max HP 保持旧模式的值）（static-derived）。
- `actCheckPlayerHPLow code,serial,ratio` 在 `HP ≤ max(1, max_hp×ratio/100)` 时成立，ratio 0 即 HP ≤ 1，所以不死 Boss 在「本该致死」的那一击触发条件（static-derived）。
- 击杀不死防守方照付含击杀 EXP 的整击 EXP 与击杀金钱，但不掷掉落；被反击打死的不死攻击者复活后直接结束行动，双方都不领这次交锋的奖励（static-derived）。
- 重制：`BattleLoopCombat._undead_revives`／`_attacker_revived`、`BattleRewardRules.undead_kill`、`WinfailConditions.hp_low_threshold`、`WinfailActions` 按上述读法实现；`run_winfail_rules_tests.gd` 的 `run_winnability_census` 覆盖全部已注册战斗的 HPLow 目标（static-derived 规则）。
- 差异：重制在出手内部复活不死防守方，因而它还能反击；原版致死分支是否跳过反击未追（provisional，差异清单 `undead-counter-kill`）。

## 证据

**resource-derived**：STORY003 开场 `actSetPlayerMode SID_漢克斯,1,pmEnemy,1` ＋ `actSetPlayerUndead SID_漢克斯,1,1`；WINFAIL003 无条件 win 段（六组对白、774 之后，写点 3 与 `actSetNextPlayLevelEvent 61,61` 之前）`pmPlayer` ＋ undead 0。

| WINFAIL003 段 | 条件 | 参数 |
| --- | --- | --- |
| fail 0／1 | `actCheckPlayer` | 雷歐納德／緹娜阵亡 |
| event 0 | `actCheckPlayerHPLow` | 漢克斯，30% |
| event 1／3 | `actCheckPlayerAttacked` | 緹娜 攻 漢克斯 |
| event 2／4 | `actCheckPlayerAttacked` | 漢克斯 攻 緹娜 |

事件链删对向事件、印 834／835、插 win 0；event 0 另删 1–4、印 836、执行 winfail。ACTION.H：`actCheckPlayerAttacked=0x2a`、`actSetPlayerUndead=0x40`、`actCheckPlayerHPLow=0x41`、`actSetPlayerMode=0x42`。ratio 0 的 HPLow 目标全部是脚本设为不死的单位（030／031／032／033／036／037／041／059／075–079）。

**static-derived**

| 锚点 | 读法 |
| --- | --- |
| `0x450840` case 0x40 | `0x44fad0(code, serial)` 解析，按第 3 参设／清 `+0xa0` 位 4 |
| case 0x42 → `0x450710` | 写 +0x28（`0x450763`，前 `0x40ba20`／`0x411b90`，后 `0x411a30`）、过程码 3／5 与着色；不调 `0x448840`；第 4 参非零更新全局模式标记 |
| case 0x41 `0x452885` | `0x4528a4` 查不到 → 不成立；`0x4528cc..0x4528e0` `+0xdc × ratio / 100`（有符号）；`0x4528e2..0x4528e7` 下限 1；`0x4528ec..0x4528f8` +0xd8 大于阈值不成立 |
| `0x446bb0` | 返回 `(live +0xa0) & 4 ≠ 0`；调用者 `0x44f580`（跳过 8 槽掉落）、`0x43ee66`、`0x4433b6` |
| `0x43ee66`（敌方，死亡分支 `0x43ee1f`）／`0x4433b6`（玩家） | 不死：清 `0x8000000`，`+0xd8 = 1`（`0x43ee88`／`0x4433d8`），若是当前行动者调 `0x407510`（`0x43ee92..0x43ee9b`／`0x4433e2..0x4433eb`），有连接对象则 `inc [[+0xac]+0x8c]`，清 +0x9c／+0xa8／+0xac／+0x8c；否则走 `0x43ef36` 死亡 |
| `0x4423c0` state 4 → `0x40a5d0` | 整击 EXP 在出手内算：目标 +0xd8 < 1 时加击杀 EXP（+0x90，击杀连锁 +0xa8 上限 8）；主击累加 `0x4c2c7c`（`0x4445c8`／AI `0x441499`），反击 `0x4c2970`（`0x4445fb`／`0x4414cc`）；开局清零 `0x444370..0x44437c`、`0x441431..0x441443` |
| 击杀段 `0x4446ab`（AI `0x4415ac..0x4415ce`，法术 `0x442e4e..0x442e69`、`0x443126..0x44313d`） | 目标 HP ≤ 0：`gold += 0x40e390(victim)`（只读 +0x98），置 `0x8000000`；复活在目标自己的 tick，不回收 |
| `0x442720(recipient, exp, gold)` | state 0 加 EXP 到 +0x88（`0x40e2c0` 翻倍）；state 2 金钱：0 跳过（`0x442812`），`0x40e2d0` 翻倍（`0x442819..0x442825`），`0x40ba20` 恰为 `0x10000` 进队伍 `0x4c1bcc`（上限 `0x3b9ac9ff`），否则进自身记录 +0x98（`0x442856..0x442875`）；state 4 非玩家过程（`0x44272b..0x44273a`）走 `0x44f600` 而非拾取窗 |
| 支付顺序 | 攻击者 `0x4447d8..0x4447e6`（AI `0x4416bc..0x4416ca`），再反击者 `0x44483c..0x44484b`（AI `0x441724..0x441738`）；被反击打死的 AI 发起者由死亡序列付 `0x4c2978`（`0x44151d`、`0x43f0f2..0x43f150`）；玩家过程发起者被反杀付 0（`0x444641`、`0x443660`） |
| `0x44f600` | 逐个不同 code（`0x44f2d0` 合并同 code，`0x44f290`／`0x44f39b`）插一件到首个空槽 `0x436e30`；失败则 `0x44f510`／`0x436e80` 丢首个非重要物品再试一次，再失败结束；`0x44f4e0` 清空集合 |
| 掉落来源 | `0x44f580` 由 `0x441587`、`0x44163e`、`0x441e2a`／`0x441e49`、`0x44469e`、`0x44474d`、`0x4453e9`、`0x445408` 调用；StealItem `0x40b629`→`0x44f2d0`；StealGold `0x40b562..0x40b578` 从队伍扣，不降目标 +0x98 |

**runtime-measured**（原版模拟器 3 关）：STORY003 pmEnemy 后漢克斯 L7 50/50 不变（`0x450710` 不刷新）。

## 重制接线

- provenance 头 `## provenance: docs/evidence_packets/static_reverse/original_player_mode.md`：`game/sim/loop/BattleLoopCombat.gd`、`game/sim/BattleRewardRules.gd`、`game/sim/WinfailActions.gd`、`game/sim/loop/BattleLoopRewards.gd`。
- `WinfailActions`：pmPlayer→`player_controlled`、pmNPCPlayer→`friendly_ai`、pmEnemy→`enemy_ai`，同步 `player_commandable`；`actSetPlayerUndead` 写单位 `undead` 并留收据。3 关漢克斯以 `enemy_ai`、undead 起始，win 段转为受控并清不死。
- `BattleLoopCombat._undead_revives`：HP 归零的不死目标置 1，收据 `undead_revived`；致死一击仍按击杀结算（连击截断、气力尾、击杀连锁／EXP）。`_attacker_revived`：被反杀的不死攻击者双方不付 EXP（`undead_action_ended`）。
- `BattleRewardRules`：`undead_kill`（付击杀金钱、不掷背包、不记死亡）、`accrues`／`accrue`（非受控非队伍击杀者的 `carried_gold_gained`）、`gold_multiplier`（ITEM `gold_x2`，230 黃金的聖杯）、`party_recipient`／`pay_party`、`taken`／`hand_over`（AI 接收者的待领物品）；`BattleLoopRewards._apply_gold_effects`、`_commit_rewards`。
- `WinfailConditions.hp_low_threshold` 用 `max(1, max_hp×ratio/100)`。
- 回归钉点：`run_battle_scene_runtime_tests._test_undead_survives_lethal_strike`、`run_battle_reward_tests`（`undead_victim_cases`、`undead_counter_cases`、`carried_gold_cases`、`gold_double_cases`、`party_recipient_cases`、`ai_handoff_cases`）。

## 复现

`tools/godot.sh --headless --script res://tests/run_winfail_rules_tests.gd`（`run_winnability_census` 逐个 HPLow 条件检查目标在复活 HP 下成立）。

## 边界

- 重制在出手内复活不死防守方后仍让其反击；原版 `0x4415b5`／`0x4446cc` 致死分支是否跳过反击未追。替换证据：原版 3 关漢克斯（不死）攻击并死于緹娜反击，读双方 +0x88 前后。
- 已阵亡单位在重制中按 HP 0 读 HPLow（成立）；原版查找在注销后失败，但扫描是否早于 `0x43ef36` 注销未读。
- AI 击杀者自得的击杀金钱（`BattleRewardRules.accrue` 记入 `carried_gold_gained`）上方 `$` 浮字未接——`BattleAftermath` 的 `$` 只飘玩家方 `rewards.gold` 与偷钱 `gold_effects`；偷钱一侧双方都已照 `0x40b556..0x40b574` 飘（provisional）；`+0x18c` 位 0x20 只建模了装备来源。
- 同一收据内击杀掉落先于 StealItem 的次序是重制次序（provisional）。
- 开场到战斗的原生时序未追；`0x44f580` 的装备跳过与 `+0xac` 连接对象不在本包结论内。

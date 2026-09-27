# 职业：盗贼 88／翼战士 92 的独立刷新与宿魔刀末击削魔

> evidence: static-derived · status: live · functions: 0x409460, 0x448840, 0x46de70 · tools: hsltools/assets/job_casts.py, hsltools/data/mobile_jobs.py, hsltools/probes/mana_strike.py, hsltools/probes/mobile_jobs.py, hsltools/probes/mobile_motion.py, hsltools/probes/mobile_source.py, run_mobile_jobs_tests.gd · updated: 2026-09-28

## 结论

- 原版 job88 盗贼与 job92 翼战士在 `0x448840` 有各自分支（`0x449a55`、`0x44a2e5`）与上限行；宿魔刀（ITEM 108，`attack_decmp` 效果位 `0x400000`）在一串普通攻击的末端由 `0x409460` 按本击实际 HP 损失削目标 MP：`max(0, mp − loss/3)`，不抽样、不回使用者 MP（static-derived）。
- 重制 `game/sim/JobStatsRules.gd` 按原整数顺序实现两分支；`game/sim/WeaponEffectRules.gd` 提出末击效果、`BattlePlayLoop` 一次提交，主攻／反击各有串末端（static-derived）。
- 一致：92 组职业输入 × 2 次完整返回与重制相同。已知差异：006／028／036 未声明等级时固定 level1（provisional）；动作位移的镜头取值与残影墙钟节奏为重制表现（provisional）。

## 证据

**static-derived**（机器包：[职业刷新](original_mobile_jobs.json)、[末击削魔](original_mana_strike.json)、[角色绑定／缺省字段](original_optional_source_field.json)、[动作位移](original_mobile_motion.json)）

| 原角色 | 职业／武器 | 模板 HP／MP／速度 | 源能力 |
| --- | --- | --- | --- |
| 004 | job88 盗贼／102 | 43／0／25 | 玩家槽 3 映射记录 004；无已支持初始法术；銀之手由 `SpecialUtilityRules` 按纯 StealGold 行结算（见 [original_skill_function_bits.md](original_skill_function_bits.md)「重制接线」） |
| 006 | job92 翼战士／43 | 85／21／43 | 玩家槽 5 映射记录 006；源 `move_fly` 与風刃；連續突刺未支持 |
| 028 | job88 盗贼／21 | 26／0／16 | 源敌人装备与 AI 配置 |
| 036 | job92 翼战士／33 | 40／0／12 | 未声明飞行，不按职业补飞行或風刃 |

- 刷新：92 组覆盖等级拐点、四属性增加、职业上限、空装备、来源 mode 与多种装备；第二次先污染派生缓存仍同值。上限 job88 = 92／96／74／90，job92 = 92／84／78／98。
- 缺省字段：`0x46de70` 字段查找对不存在的字段保留 caller 传入值并返回 0；角色 loader 先把输出置 0（006／036 未写 status）。玩家槽 3／5 另执行绑定与模板复制，不凭 sprite token 名推角色编号。
- 削魔 `0x409460`：读本击已夹到剩余 HP 的贡献值，`target_mp_after = max(0, target_mp_before − actual_last_hp_loss / 3)`，非负整数截断；暴击先影响实际 HP 损失再算；目标 MP 为 0 时无提示。
- caller 75 组有界前段：先完成该击 HP 与贡献→EXP；只有正 EXP 且整串结束、或目标已 0 HP 时，调一次武器末端效果，再进气力／死亡出口。额外攻击的非致死首击不触发；末击落空不补发前一击效果；致死首击停止后续击。54 组 HP 应用前段、8 组装备配置两次刷新与字段 OR 分开保存。
- 动作：004／006 的相对 XY、水平加减速、停止与缩放按原 ANIMAL 指令编译；53 次位移更新与 6 组镜像 XY 前段（从可选残影构造之后开始）。

## 重制接线

- `game/sim/JobStatsRules.gd`：job88／92 表行；源属性、永久取得、装备增量与临时攻防分别进 `game/sim/ProgressionRules.gd`，装卸／升级／跨战重算。
- `game/sim/WeaponEffectRules.gd`：只提出当前装备效果；法术、回复、驱毒、道具、等待不调用削魔；`action_twice` 第二行动重读装备与 MP；AI 下次决策重新报价技能。
- 特写：各击影响帧前显示 `defender_before.mp`，之后才显示 `defender_after.mp` 与非零削魔文字；显示层不重算、不动 RNG。
- 跨战只带源角色属性、取得、当前装备与库存，不带临时增益或旧削魔。
- `tools/hsltools/data/mobile_jobs.py`、`tools/hsltools/assets/job_casts.py` 生成数据与施放画面；开发入口 `game/battle/development/MobileJobsTrial.tscn`（演练库存与受伤 002 为夹具，正式编队不变）。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_mobile_jobs.md`。

## 复现

`python3 tools/hsl.py check mobile_jobs`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [mobile_jobs](../runtime_observations/mobile_jobs/receipt.json) | manual、single、double、counter、miss、low_mp、zero_mp、late_kill、growth、wing_growth、wing_move、support、mixed、paralysis、ai_drain、ai_wing、victory、defeat、escape、carry | `run_mobile_jobs_tests.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- `level_adjust_range`、自动分配与动态学技未由这些刷新探针执行；固定 level1 的替换点是原初始化入口的调用条件与随机过程。
- 006 源表缺必需 AI 策略，不从 026 复制；测试里的 006 AI 策略是夹具。
- 职业 83、完整对象 dispatcher、全部大型角色特写、原全局随机流不在本包。
- 残影与原墙钟节奏未执行。

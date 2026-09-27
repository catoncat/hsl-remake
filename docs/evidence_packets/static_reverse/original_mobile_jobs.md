# 盗贼／翼战士的独立职业来源与普通交锋末击削魔

> evidence: static-derived · status: live · functions: 0x409460, 0x448840, 0x46de70 · tools: capture_mobile_jobs_review.gd, hsltools/assets/job_casts.py, hsltools/data/mobile_jobs.py, hsltools/probes/mana_strike.py, hsltools/probes/mobile_jobs.py, hsltools/probes/mobile_motion.py, hsltools/probes/mobile_source.py, run_mobile_jobs_tests.gd · updated: 2026-09-18

本批沿现有确定性职业跳转表、装备字段和交锋 caller 复核，没有使用模型判断作为规则证据。原 EXE 身份、输入、停止地址、逐字段结果和限制分别保存在 [职业刷新](original_mobile_jobs.json)、[末击削魔](original_mana_strike.json)、[角色绑定／缺省字段](original_optional_source_field.json)及[动作位移](original_mobile_motion.json)。有界原指令执行为 `static-derived`；Godot 检查与可玩路线分别验收，不互相冒充。

玩家与AI的二十条真实输入、跨战／重开和十七张已检图见[实玩回执](../runtime_observations/mobile_jobs/README.md)，其中失败进程的已完成范围与后续修正明确分开。

## 从角色表到同一战斗事务

| 原角色 | 职业／武器 | 本批固定模板 HP／MP／速度 | 源能力差异 |
| --- | --- | --- | --- |
| 004 | job88 盗贼／102 | 43／0／25 | 玩家槽3映射记录004；无已支持的初始法术；未实现的銀之手不以别的技能替代 |
| 006 | job92 翼战士／43 | 85／21／43 | 玩家槽5映射记录006；源 `move_fly` 与風刃；連續突刺仍未支持 |
| 028 | job88 盗贼／21 | 26／0／16 | 源敌人装备和 AI 配置，不能套用004的默认刀具 |
| 036 | job92 翼战士／33 | 40／0／12 | 未声明飞行；不能由职业名称补上飞行或風刃 |

这些是当前模板的确定输入：004声明 level1，006／028／036未声明等级时仍采用显式 `provisional` 固定 level1。`level_adjust_range`、原自动分配属性与动态学技没有被这些刷新探针执行；替换固定等级策略须补原初始化入口的调用条件与随机过程。当前玩家／敌人控制权与原角色 `mode` 独立，不能换阵营就改变 HP 的等级项。

92组职业输入各执行两次 `0x448840` 完整返回，覆盖等级拐点、四属性增加、职业上限、空装备、来源mode和多种装备。第二次故意污染派生缓存，仍返回相同源结果。job88属性上限为92／96／74／90，job92为92／84／78／98；两分支分别在`0x449a55`与`0x44a2e5`，不使用战士／法师的近似公式。Python来源编译与`JobStatsRules`均保持原整数运算顺序。源属性、永久取得、装备增量和临时攻防增益分别进入已有`ProgressionRules`，装卸／升级／跨战重新计算同一组值。

006／036未写status的情况另外执行了`0x46de70`及其字段查找：不存在的字段保留caller传入值，返回0；角色loader先把输出初始化为0。玩家槽3／5另执行绑定及模板复制，不能凭 sprite token 的名字推导角色编号。006源表缺失必需AI策略时不从026复制；测试中的006 AI策略必须显式声明为夹具，正式玩家能力仍来自006自己的技能位。

## 宿魔刀的效果是削减目标MP，不是回魔

原ITEM中`attack_decmp`对应效果位`0x400000`，当前唯一该字段的来源是108 **宿魔刀**。其职业资格来自原装备掩码，不为演示而开放给翼战士。`0x409460`读取本击已经夹到剩余HP的贡献值：

```text
target_mp_after = max(0, target_mp_before - actual_last_hp_loss / 3)
```

除法按非负整数截断。该函数不抽样、不写使用者MP，也不因使用者是否满魔改变结果。目标MP不足夹到0，原先为0则无虚假恢复／扣除提示。暴击先影响实际HP损失，再由该实际值算削魔；不是未夹取的伤害，也不是整串总伤害。

原caller的75组有界前段显示：先完成该击HP与贡献→EXP转换；只有正EXP且整串结束，或目标已到0HP时，才调用一次武器末端效果，之后进入气力／死亡出口。额外攻击的非致死首击不会触发；最后一击落空不会补发前一击的效果。致死首击停止后续击，但原helper仍可以处理已经为0HP的目标记录，这不等于终态后开启新事务。54组HP应用前段与削魔函数完整返回分开保存；8组装备配置两次刷新、字段OR与既有附毒／取消分支保持各自证据边界。

`WeaponEffectRules`只提出当前装备效果；PlayLoop接受后一次提交。主攻／反击各有自己的串末端，不能合并成一个“每次点击只触发一次”，也不能按每击触发。法术、回复、驱毒、道具与单纯等待不会调用普通武器削魔；`action_twice`的第二行动重新读取当前装备与MP。目标下一次AI决策必须重新报价技能，旧的可施法意图不能越过新MP状态。

## 表现与持久化

004／006动作中的相对XY、水平加减速、停止与缩放按原ANIMAL指令编译。53次位移更新和6组镜像XY前段与完整动作帧／释放点分别记录；XY前段从可选残影构造之后开始，未执行的残影与原墙钟节奏不宣称还原。新的位移画面沿现有特写布局缩放以容纳完整动作，镜头取值仍属于重制表现。

特写在各击影响帧前显示该击`defender_before.mp`，影响帧后才显示`defender_after.mp`及非零削魔文字；第二击或反击尚未播放时不能提前泄漏其MP结果。显示层不重新计算效果、不改变规则RNG。保存直接恢复已经提交的资源和串收据；跨战只携带源角色对应的属性、取得、当前装备与库存，重新初始化新场状态，不携带临时增益或重放旧削魔。

公开入口为`game/battle/development/MobileJobsTrial.tscn`，显式供应演练库存和受伤002。第一战正式编队／默认授予保持原数据。测试中的耐久、速度、命中补偿、双击、致死HP及006 AI策略均须在真实输入回执列明；它们不能作为原章节自然遭遇证据。

## 复跑与尚未覆盖

```sh
python3 tools/hsl.py check mobile_jobs
python3 tools/hsl.py check mana_strike
python3 tools/hsl.py check mobile_motion
python3 tools/hsl.py check mobile_source
python3 tools/hsl.py check mobile_jobs_data
python3 tools/hsl.py check mobile_jobs_assets
tools/godot.sh --headless --script res://tests/run_mobile_jobs_tests.gd
tools/godot.sh --screen 1 --script res://tests/capture_mobile_jobs_review.gd
```

默认探针只核对整理后的回执。明确传`--execute <原EXE> --write`才重新执行固定原指令。上述记录不覆盖原完整对象dispatcher、自动NPC调级／学技、未支持职业83、所有大型角色特写或原全局随机流。

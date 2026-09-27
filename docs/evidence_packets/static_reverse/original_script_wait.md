# 脚本等待、守备唤醒与指定对象同步

> evidence: static-derived · status: live · functions: 0x450840 · tools: hsltools/probes/script_wait.py, run_script_wait_tests.gd · updated: 2026-09-28

由`ACTION.H`、已有VM／AI符号和原指令确定性定位，没有调用Jev。原EXE保持只读；[机器回执](original_script_wait.json)由`tools/hsltools/probes/script_wait.py`实际执行生成，离线检查固定原指令哈希、来源哈希、逐例结果与停止边界。

## 原指令结论

| 入口／分支 | 已确认行为 | 证据范围 |
| --- | --- | --- |
| `0x450840` → `0x452388` | opcode33／`actSetPrevInsertObjectWaitRound`把参数写入上次插入对象对应角色的`+0x1b8`。覆盖旧值，不增加旧值；VM前进opcode及一个参数 | 和opcode34共80组setter，完整VM单步返回，逐字节确认除此DWORD没有角色变化 |
| `0x450840` → `0x4523b8` | opcode34／`actSetWaitRound`解析当前登记的code／serial，只替换选中角色的等待值；找不到对象仍消费三个参数。序号0／1选择首个，同code多实例不是全体赋值 | 同上；code26双实例、code23及缺失code999分别覆盖 |
| `0x450840` → `0x4513b4` | opcode88／`actWaitPlayer`读取选中对象`+0x8c`。非零便退回本opcode；指定对象空闲或不存在就继续。其他对象忙碌不阻止它 | 40组同步样例；busy→idle的9例再次正常调用，共129次完整VM返回。角色和队列字节保持不变 |
| `0x43f603..0x43f62b/0x43f67f` | 到达AI等待入口时，非零等待先减一；HP不是满值或任意状态位非零会清等待并走普通决策入口 | 28组有界后缀，止于近敌扫描或优先级分派之前，不能称完整AI执行 |
| `0x43f644` | 近敌结果有效便清等待；缺失／已移除目标仍可留在等待分支 | 固定调用者字节；完整近敌／保留目标／路径算法沿[既有导航证据](original_ai_navigation.md)复用，不重复扩探针 |

原setter存整个DWORD，不做`0..10000`夹取。`-1`样例真实留下`0xffffffff`；Godot沿现有AI状态校验只接受非负`0..10000`，明确拒绝超出这个可玩范围的脚本输入，不能声称原作也有这个上限。同步等待不是“跳过角色一回合”，也不扣MP、扣库存、结算毒伤或发放经验。

## 证据

逐例范围见上表「证据范围」列；[机器回执](original_script_wait.json)由 `tools/hsltools/probes/script_wait.py` 实际执行生成，离线检查固定原指令哈希、来源哈希、逐例结果与停止边界（static-derived）。

## 重制接线：系统对照与接入

第二战STORY052有八次普通卫兵插入，其中前四次随后声明等待2；此前协调器只记录token，战斗仍使用PLAYERS的默认等待。现在`ScriptWaitRules.initial_source`按开场token顺序与现有对象绑定编译不可变来源，PlayLoop在创建时只应用一次，第一次交还控制、装备／成长刷新和F9都不重新设置。第三战未声明等待的插入保持原默认值。原脚本和正式默认授予未改动。

事件里的设置按当前登记对象解析并记录唯一身份、firing索引和参数。`script_wait_cursor`只消费新请求：当前角色替换等待值，尚未落地的增援保留自己的最终设置；后续生成时绑定唯一unit id。连续“上次插入设2→指定实例设7→上次插入设1”最终为1，不能用静态折叠值抢在中间指令之前应用。缺失、已离场和已死亡角色不重建、不进队列，也不影响其他实例；已经生成的最后插入对象仍可被下一次setter重新指定。

`actWaitPlayer`的身份随该次事件保留，允许离场演出结束前等待当前留存的sprite，但不能在下一次重复事件中绑定上一次已离场实例。`BattleScriptCoordinator`子类只在战斗模式覆盖同步：等目标行走／离场淡出结束，不等无关角色。旧编译timeline中把它标成`cutscene_skip`的记录也通过这个有界适配恢复同步；世界和story-only父协调器未改动。镜头、脚步、战斗光效、状态／道具数字继续使用既有只读表现入口。

AI仍共用已有导航和优先级。设置等待不强行清除已锁定目标，不覆盖home、职业、装备、能力或资源。每次实际进入等待判断才使用上述原后缀；重制的第二次独立行动重新进入现有决策，麻痺入口则在此之前跳过。两次行动的毒、禁魔、增益和资源尾部仍只在最后一次结束时执行。受伤／状态／近敌唤醒后的攻法援物使用当前MP、持有技能、装备和路径，拒绝陈旧目标。两次独立行动与原整段dispatcher的组合等价性，仍不能由单个等待后缀推断。

## 复现

`python3 tools/hsl.py check script_wait`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [script_wait](../runtime_observations/script_wait/receipt.json) | opening、guard、double_guard、wounded、silenced、paralyzed、ai_chain、event、mage、support、sync、depart、kill、victory、defeat、escape、carry | `run_script_wait_tests.gd`；截图驱动已退役，回执为历史记录 |

## 保存与边界

保存配置加入`script_wait_source`及版本，状态保存消费游标、不可变末批回执、当前等待次数和插入实例绑定。加载核对请求／firing／回执／插入身份，直接恢复结果，不重放setter。旧存档缺少新来源版本或配置签名时明确不兼容，保留原文件，不猜测等待次数。跨战斗只沿现有队伍carry传递角色成长等字段，新战斗使用自己的开场等待；重开重建本战来源和空事件游标。

胜利／败北／撤离被确认时，结果脚本中的合法等待赋值可以随结果事务提交；终态冻结后任何重复AI／wait／收尾回调不再推进倒数、资源或演出。对象同步只阻塞可见脚本，并不保存另一个可变战斗状态。

守候提示“尚餘N次”取本次已提交AI收据，0.55秒提示时长仍为已有重制可读性参数。实玩证据与失败修正见[窗口验收](#复现)。原全局时钟、整个VM连续生命周期、story-only及世界场景同步、负数等待的无限行为不在本批等价声明内。

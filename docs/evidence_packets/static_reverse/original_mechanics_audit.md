# 原作机制来源与重制差异审计

> evidence: static-derived · status: live · functions: 0x40ba20, 0x40bb80, 0x40bee0, 0x40bf70, 0x40c570, 0x42dc50, 0x439f20, 0x439f70, 0x43e4a0, 0x43ea30, 0x448370, 0x448420, 0x448840 · tools: hsl_native_animal_probe.py, hsl_native_growth_probe.py, hsl_native_map_scroll_probe.py, hsltools/assets/animal_programs.py, hsltools/data/consumables.py, hsltools/data/progression.py · updated: 2026-09-13

日期：2026-09-11。本轮从 `6e6501f` 的共享工作区开始，包含另一条表现线正在修改的代码；这是对已读实现的研究快照，不替代持续更新的 PROJECT。文件哈希和复核位置见同目录 [`original_mechanics_audit.json`](original_mechanics_audit.json)。

2026-09-12 接入更新：本研究已归档为 `19b387b`，随后 `0d5f7c1` 已接入鼠标边缘浏览、源指令菜单和六类角色的普通 action。因此下文“镜头只有键盘”“菜单 helper 正在接入”等描述仅适用于原审计快照；原始文件哈希／探针 JSON 保留不变。其他系统差异以 [PROJECT 当前摘要与 Next steps](../../PROJECT.md#next-steps)及[机制矩阵](../../MECHANICS_EVIDENCE_MATRIX.md)更新。本次说明不改变原函数证据，也不把后续 live 接入冒充研究当时已经完成。

2026-09-13 成长后续：原审计里“cap 初始化／派生刷新／HP/MP 处理未知、三选项仍 live”的描述也已成为历史快照。新 [`original_growth_refresh.md`](original_growth_refresh.md) / JSON 证明 `0x448370` 职业 cap loader、Leonard `jobSwordMan=80` 的 `90/88/80/94` 上限以及 `0x448840` SwordMan 派生刷新；产品已用五点 str/dex/mind/con 替换旧三选项。下文第 2 节保留的是 9 月 11 日研究当时的边界，不应覆盖该后续证据。

用户要求从原版包和程序系统查明行为，不只补录像里看见的 UI。鼠标浏览、升级、AI、后续队友和背包只是其举出的例子。本文按机制组织原始来源、当前替代规则和可执行的下一条证据链；不把这些例子扩张成未经授权的整游戏改写，也不把它们缩成几个控件修补。

原始资源、EXE 与 synthetic 探针沿用项目的 evidence tier。本文所用“已接入”“待接入”“重制选择”“部分恢复”是实现状态，不是新的证据等级。旧的改善交互／规则授权仍保留，但“允许自行设计”不能代替告诉用户哪里与原作不同。当前需要恢复的规则先取得证据，再由负责产品的工作线按完整合同接入。

## 1. 本轮已经得到的原规则

| 结果 | 本轮实际完成 | 尚未表示 |
| --- | --- | --- |
| 战斗动作程序 | 完整解析 ANIMAL 的 66 角色、103 程序、663 条指令；六组原分派前段实验 | 完整受击／施法及声音、共同尾部和真实 tick 都已恢复 |
| 成长点数预算 | 两个原始函数完整返回，18 组输入；每次请求 5 点，受四项基础属性剩余空间限制 | 把现在的 3 改成 5 就恢复了四维成长、属性上限、派生数值和升级 UI |
| 鼠标边缘浏览 | 两个原始函数完整返回，52 组输入；视口边缘触发各轴滚动请求 | 每秒速度、最终地图边界、弹窗屏蔽和所有页面纯鼠标操作都已证明 |

第一项见 [`animal_program_execution.md`](animal_program_execution.md)。后两项的工具和精确边界在下文。以上均未更改 live 游戏规则，原作程序也没有被修改。

## 2. 成长：五点预算和四项属性是两件事

新工具：[`hsl_native_growth_probe.py`](../../../tools/hsl_native_growth_probe.py)。结果：[`original_mechanics_audit_growth.json`](original_mechanics_audit_growth.json)。原 EXE SHA-256 为 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。

`0x439f70` 直接以参数 5 调用 `0x439f20`。后者从 object `+0xa4` 得到角色登记索引，查全局 `0x4c1bc8`、步长 `0x1fc` 的角色表，计算四组字段的差：

```text
基础字段：+0x64、+0x68、+0x6c、+0x70（str、dex、mind、con）
对应上限字段：+0x74、+0x78、+0x7c、+0x80
可分配预算 = max(0, min(请求点数, 四项「上限 - 基础值」之和))
升级调用的请求点数 = 5
```

属性名与既有 stat-refresh 字段证据相接，不由显示文字或字段顺序臆测；上限读取也与调用方 `0x43a371..0x43a37d` 的逐属性比较相符。`0x43a1ca..0x43a1f8` 保存该预算并清空四项分配计数；紧接的 `0x43a224..0x43a265` 增加角色等级、扣旧经验门槛并把负经验夹到零。这些短指令锚点保存在 JSON。

九种输入分别执行一般 allowance helper 和固定五点 wrapper，共 18 次完整返回；没有 stub 内部调用。覆盖普通余量、只剩三点／一点、全部到顶、合成超上限、正负余量混合及请求 0／12／负值。混合余量先求和后夹紧，不能自行将每项负值提前归零。wrapper 不受测试额外传入的请求参数影响，仍请求 5。

这些输入中的 cap 是合成值，不代表某角色现场的原版上限。尚未执行上限初始化、鼠标增减／确认、点数是否可保存、升级后 HP/MP 如何变化、转职和完整 stat refresh。五点预算不是五个可选属性，也不保证临近全部上限时仍能分五点。

**当前重制差异可明确定位**：[`ProgressionRules.gd`](../../../game/sim/ProgressionRules.gd) 的 `POINTS_PER_LEVEL=3`，选项是生命／攻击／防御，分别直接增加派生属性。注释已明确标为重制选择。原作预算与基础属性合同现在有更强证据，后续恢复应连同四属性、上限、派生刷新及已有属性显示一起处理；不应只改常量、换面板标题后宣称已一致。

经验门槛另有已恢复的 `min(2000,(level+1)*50)`，见 `hsltools/data/progression.py` 与 `0x44b678`；经验数量目前仍按实际扣血加击败奖励，不能因为门槛恢复就认定获得经验公式也恢复。

## 3. 鼠标：恢复的是边缘滚动请求

新工具：[`hsl_native_map_scroll_probe.py`](../../../tools/hsl_native_map_scroll_probe.py)。结果：[`original_mechanics_audit_scroll.json`](original_mechanics_audit_scroll.json)。执行真实 `0x43e4a0` 及其唯一调用的 `0x42dc50` 到正常返回，最多 512 指令；只允许这两个代码区间。

`0x43e4cc..0x43e4db` 从 cursor 全局减 camera origin，得到被检查的视口坐标。边缘分支使用严格不等号：

| 条件（未按方向输入时） | 本次请求 |
| --- | --- |
| x < 10 | 横向 -12 |
| x > 630 | 横向 +12 |
| y < 10 | 纵向 -12 |
| y > 470 | 纵向 +12 |

所以正好处在 x=10/630 或 y=10/470 不触发对应边缘；四角两个轴分别产生请求。输入全局 `0x4c6390` 的低四位也能触发相应方向，mask `0x600` 让同一循环执行两遍。本包没有继续把该 mask 命名成某个物理键。

`0x42dc50` 增加 `0x4c1b98/0x4c1b9c` 的累计量，**不直接写 `0x4c091c/0x4c0920` 的镜头位置**。52 组测试使用边界内外、四角、方向位、加速位和两种不同 camera origin；预置非零请求量以核对是相加而非覆盖，并核对 camera origin 保持不变。

这也纠正一个早期索引的解释风险：`index.json` 把 `0x4c1b98/0x4c1b9c` 留作 menu-local 候选，此处明确用作滚动请求累计量。cursor 全局在 input aggregator `0x415b35..0x415b66` 加入 camera origin，不能不分调用位置一概当屏幕像素。索引候选标签不应覆盖新的明确使用证据。

**当前重制差异**：[`BattleSceneRuntime.gd`](../../../game/battle/scene/BattleSceneRuntime.gd) 的镜头输入仍是 `_process` 中的 `Input.get_vector("ui_left", ...)`；鼠标移动只调用 pointer/hit-test 更新。[`BattleCameraController.gd`](../../../game/battle/runtime/BattleCameraController.gd) 已有 pan 和地图限制，可作为接入点，但调用方还没有提供边缘鼠标方向。

后续接入要同时验证窗口失焦／指针离开、打开菜单／面板、剧情／演出占用、地图到边、悬停命中位置更新以及两轴滚动。原请求累计量如何消费成最终 camera 位置、哪些调用方允许滚动、真实每秒更新频率仍未恢复。因此不能用 12×60 直接宣称原版速度，也不能用此函数证明整个游戏所有页面都可以只用鼠标完成。

## 4. 交互与规则差异登记

以下按机制登记，避免“某个 UI 已补齐”掩盖未恢复的规则。当前代码的位置以函数名为主要定位；另一工作线完成新实现后，需要更新本节对应行，保留原始证据与新结论的区别。

| 机制 | 原版来源／已有证据 | 当前消费与明确差异 | 需要闭合的关系 |
| --- | --- | --- | --- |
| 地图浏览和命中 | 本包 `0x43e4a0/0x42dc50`，input/camera globals | 镜头只有键盘 pan；pointer hit-test 与 camera 分开入口 | 边缘输入→允许状态→请求消费／夹紧→所有空间坐标同步 |
| 行动菜单与行动预算 | OBJ-ALL 的命令编号、`0x43ea30`；原始玩家过程 `0x443330` | 菜单 helper 正在由表现线接入；行动仍由 moved/attacked flags 和当前 actor 控制 | 命令可见性、按下／释放、拒绝、取消、资源消耗、行动交接必须各自核对 |
| 成长及经验 | 本包五点 helper；原始 stat-refresh 门槛；PLAYERS kill_exp | 每级三点，直接增加生命／攻／防；实际扣血+击败奖励是重制策略 | 四基础属性、cap、预算、派生刷新、经验与升级交接、确认／撤销 |
| 使用物品 | PLAYERS 初始 item1..8；ITEM 的效果字段；原命令 114 | 仅已导入回血物品生效，满血拒绝，自用／相邻友军，用后结束行动 | 效果资格、范围、是否耗行动、状态解除、用完空槽、失败与取消 |
| 交换／给予／丢弃 | 原菜单 mode3 字符表 `rtus`，OBJ-ALL 对应 114/116/117/115 | 表现线已接入给予一件、丢弃一件；共享同侧相邻限制，成功后结束行动 | 原“交换”是单向给予还是可互换、对方满包、整组／单件、耗时与确认 |
| 背包结构与整理 | PLAYERS 明确有八个初始 item 字段 | 导入时 Counter 合并重复物品；live 为 item_code→数量，UI 再逐件展开 | 初始槽不等于已证明最大容量；顺序、堆叠、整理、空槽和持久化都未闭合 |
| 换装与状态数值 | PLAYERS 六装备字段、ITEM/TYPE；属性函数 `0x448420/0x448840` | 显示初始装备；本次已读的 equip 页过滤耗材，但选中后无 equip 事务分支 | 卸下／穿上、背包回收、资格、派生刷新、当前 HP/MP、是否耗行动 |
| AI 选目标 | PLAYERS find_type/find_flag/find_range 等，`0x40bb80`，side helper `0x40ba20` | live 优先可达攻击的最低移动成本，再低 HP，再少横移；无可达攻击才靠近最近者 | 目标过滤、职业／阵营条件、距离、锁定、同分顺序和不同模板策略 |
| AI 选动作／协助 | `0x40c570`；PLAYERS ai_help_*、ai_att_*、ai_call_range、ai_lock 等 | 法师消费已导入施法概率与 MP，随机选可负担法术；完整救援、特殊技和模板策略未接入 | 每项表字段到底由哪个分支消费、RNG 顺序、可用能力与行动预算 |
| 队友与控制权 | PLAYERS mode、对象 process、EVEF、剧情指令；ActorRoleRules 的保留模型 | 队列遇 player_commandable 可交给玩家，基础并非只能登记一人；正式首战只验证雷欧纳德 | 招募→登记→所有权→每人能力／物品→轮到其行动→跨关保存及离队 |
| 战斗数值与反击 | core_logic 的 hit/damage/counter 地址和原表范围 | 普通路径有来源；部分随机序列、伤害分支、技能公式仍为重制／provisional | 规则结果、随机调用顺序、目标状态、反击／连击与 EXP 的整体顺序 |
| 回合、增援、剧情 | STORY/WINFAIL、WRD/EVEF、原队列；事件 adapter | 一次队列遍历映射一回合；增援数量读取脚本，出生点／交接时机仍有约定 | 原可见回合与事件调用时机、入口占格、退场与队列移除 |
| 技能、状态、职业 | MAGIC/SPECIAL/TYPE/PLAYERS；独立公式与施法过程 | 当前指定技能和两种敌法术可用；转职 helper staged，解毒无 live 中毒状态 | 学习／选择／消耗／作用对象、持续状态、回合变化、职业资格与角色能力 |
| 跨关与持久进度 | 当前 scenario adapter、level52 seed、原脚本 next-level | 第二战仅有开发入口；当前正式首战结果后重开 | 队伍／装备／经验／库存／剧情变量的统一持久状态；不能从 roster 数量推断已完成 |

“表中存在一个字段”“程序中有一个函数”“界面显示一个按钮”分别证明不同的事。每行都需要看数据进入什么实际分支、发生了什么状态变更，再判断是否完成。

### 背包不能由当前列表外观反推原规则

[`hsltools/data/consumables.py`](../../../tools/hsltools/data/consumables.py) 只从 Leonard 的八个初始 item 字段构造当前可用库存，重复的三份回复药会合并数量，其余角色缺省空字典。原字段能证明这份模板的初始内容，不能独立证明运行时八格上限、排序策略或每件最多一个。

[`BattlePlayLoop.use_item`](../../../game/battle/scene/BattlePlayLoop.gd) 目前只处理 heal_hp>0，并在成功后 `begin_wait_resolution`。`transfer_inventory_item` 也在给予／丢弃后结束行动；这个函数自己的注释明确保留原版免费操作语义未知。因此目前“有给予／丢弃按钮且库存能变化”是真进展，“原版背包完整恢复”仍不成立。

已读的 `BattleItemPanel._select_item` 只处理 drop/use/give，equip 列表并无对应成功事务。当前初始库存只有耗材，过滤后为空，这个入口缺口容易被自然游玩隐藏。后续应使用合法装备库存和满包目标等正常规则边界验证，不能仅看一个空页面就认定换装工作完成。

### AI 不应只看它会不会走向玩家

[`core_logic.json`](../../../content/generated/hsl/static/hsl01/core_logic.json) 的 `ai_decision_layers` 已分别定位 `0x40c570` 动作选择、`0x40bb80` 目标选择、`0x40bee0` 同侧呼叫标记及 `0x40bf70` 低血量扫描，证据强度并不相同。这里沿用已有静态 packet，未在本次重新执行整套 AI。`TYPE.H` 的 AI_NEAREST、AI_HPMIN/HPMAX、AI_FAREST 等是不同模式，不能只用一个“最近敌人”概括。

当前 `_ai_take_turn` 明确写着 `remake reachable-strike priority; not original ... parity`；最低移动成本、低 HP 及少横移的排序是实际代码合同。`_try_mage_turn` 已消费某些原字段，但选法术、搜格和元素伤害计算含重制策略。不能因为参数名称来自 PLAYERS 就给整段策略贴上原版等价。

后续原函数实验应该固定小 roster、地形、状态、MP 和 RNG 输入，分别核对目标候选集合、返回目标、动作类型、所耗随机数，再在调用方核对它们的执行次序。不能为了运行巨大函数把所有未知 callee 都 stub 成“成功”，否则得到的只是在验证自己填写的假设。

### 多队友已有基础，但不能据此宣称完整

`begin_battle`、`step_ai_turn`、`_finish_ai_or_continue` 都检查当前单位的 `player_commandable`，`_return_to_player` 接受具体 unit_id；因此说当前“只能有一个可控对象”过于绝对。但完整多队友仍受实际加载的 progression、inventory、技能清单、角色能力和正式剧情路径限制。

例如 `_menu_for_unit` 当前根据 stamina 是否存在决定特殊技，并显式把 magic availability 传为 false；创建阶段的模板导入只覆盖已导入角色。增加一个场景单位不能自动得到原作每人的魔法、专属技能、初始包、招募条件和跨关保留。`player_unit_id` 还承担当前关卡特定主角判断，不能与“所有可控伙伴集合”混为一谈。

## 5. 如何把这张表变成持续交付

每次研究只闭合一个明确机制合同，但要记录其完整边界：进入条件、数据输入、可选动作、确认／取消、资源和行动消耗、拒绝条件、后继状态、必须保持不变的状态。这样既能逐项推进，又不会漏掉用户只能靠实玩才发现的隐藏规则。

以下是原审计时的研究分组；2026-09-12 后的具体执行顺序统一看 [PROJECT 的 Next steps](../../PROJECT.md#next-steps)，不再把本节作为另一份当前任务计划：

1. **状态和交易合同**：输入／镜头、行动可用性、物品事务和每角色所有权。这些错误会同时影响多个面板和战斗阶段。本轮已为边缘滚动提供原函数输入输出，inventory 的耗行动规则还需原始调用方。
2. **角色数据闭环**：四维成长、cap、派生刷新、装备和能力集合。五点预算已有直接结果，应该用完整状态更新连接 UI，避免边修状态页边继续用另一套属性真相。
3. **决策与剧情**：AI 的目标／动作／协助、队友加入离开、增援及跨关保存。按小 roster 的确定输入核对，比重录整场战斗更容易识别分支缺失。
4. **剩余表现**：将完整 ANIMAL 程序与真实状态结果连接，再用短片核对时钟、声音、空间和阶段交接。已存在的媒体仍有验收价值，不因静态证据而自动标 matched。

这份顺序是研究建议，不能覆盖后续用户指定的优先级。未知机制应留下输入／函数／证据替换点；明确允许的重制策略也应列在差异登记里，避免后续 agent 误认它是已恢复的原规则。

全局对象上的单个 `evidence_tier: static-derived` 尤其不足以概括所有字段：当前 PlayLoop 内有原规则、原数据、重制公式和临时映射。后续生成 provenance 应在机制或字段层表达，而不是凭这个对象标签认定所有 UI、AI、成长和背包都正确。本轮只记录这个风险，不抢改表现线的共享 runtime。

## 6. 复跑与交付边界

无需 Wine／EXE 的源程序及记录回归：

```sh
/opt/homebrew/bin/python3 tools/hsl.py check animal_programs
/opt/homebrew/bin/python3 -m unittest tools.test_hsl_animal_programs \
  tools.test_hsl_native_growth_probe tools.test_hsl_native_map_scroll_probe -v
```

重新执行本机指定 EXE 的原指令（Unicorn 仅分析依赖）：

```sh
uv run --with unicorn==2.1.4 python tools/hsl_native_animal_probe.py --check
uv run --with unicorn==2.1.4 python tools/hsl_native_growth_probe.py --check
uv run --with unicorn==2.1.4 python tools/hsl_native_map_scroll_probe.py --check
```

ANIMAL 是六组**前段**实验；成长 18 组和滚动 52 组是两个小函数组的**完整返回**。不把两类结果合并成“76 组完整游戏逻辑测试”。所有 probe 都限定 EXE 哈希、可执行地址与指令数，无原作进程修改或鼠标输入。

普通 full verify 会通过 unittest discovery 包含新增回归；它重建源程序并检查记录合同，但不会强迫每次测试安装 Unicorn 或启动原作。重新跑原指令仍使用上面单独入口。完整门禁在基线加本线文件的独立副本中执行；结果记在提交说明与研究线 READY，不能证明表现线仍未提交的修改也通过。

协作通信见 [`source-research.md`](../../collaboration/source-research.md)。另一工作线已确认 ANIMAL 与资源头的文件范围，扩展机制研究的具体状态以其实际 ACK 为准。本审计不会更改现有菜单、物品／成长界面或已有脚本输入，便于接入方在自己的提交中审核规则改变。

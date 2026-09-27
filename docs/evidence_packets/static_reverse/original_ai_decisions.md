# 原 AI 目标与进攻类别选择

> evidence: static-derived · status: live · functions: 0x40ba20, 0x40bb80, 0x40bee0, 0x40bf70, 0x40c110, 0x40c570, 0x40c620, 0x40d4e0, 0x42c780, 0x458c10, 0x458c80, 0x45ec32 · tools: hsltools/data/ai_profiles.py, hsltools/probes/ai.py, run_ai_decision_tests.gd · updated: 2026-09-14

Checked 2026-09-14，SR-035，接续状态施加提交 `3e97651`。原EXE SHA-256：`f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`。

机器证据：[original_ai_decisions.json](original_ai_decisions.json)，由 `tools/hsltools/probes/ai.py` 执行原 x86 指令产生。200组均正常返回，原调用者／RNG不替换，不运行Wine或发送系统输入。独立Python解释模型先逐组对比，`AIDecisionRules`再使用相同RNG样本核对返回值与调用次数。这是 `static-derived` 的合成内存原函数执行，不是原作自然游玩或整场等价证明。

## 来源与公共输入

`hsltools/data/ai_profiles.py` 把 PLAYERS、TYPE、SHAPEDEF 的66个声明生成 `content/generated/hsl/ai/profiles.json`。明确保存 find_type、find_range、find_flag、find_no_id、魔法／特殊技倾向、ai_call_range、ai_fixed、职业及当前角色绑定所需SID。缺少必要策略字段的角色保留 `missing_required`，不复制另一角色策略。当前两战使用的001/021/023/024/025/026都有必要字段。

`ai_profiles`是PlayLoop一次加载的不可变规则输入；生命、位置、等级、阵营、状态、MP/ST、库存仍取当前units。SID绑定复用当前资源动画身份；未映射角色明确失败。缺省可选find_flag=0/no_id=-1只是明示的序列化合同，未把原解析器默认初始化伪装成新证据。旧初始技能注册表不再承担AI倾向，避免同时保留两套策略字段。

## 0x40bb80：目标选择

原函数扫描最多200个对象槽，跳过null、自身和对象+0x80的移除位0x8000000。`0x40ba20`取得阵营掩码，双方 `&0x870000` 有交集则排除。搜索半径通过 `0x45ec32` 使用平方欧氏距离、包含边界；排序距离则是曼哈顿距离，二者不同。

| find_type | 比较值 |
| --- | --- |
| 0 AI_NORMAL | 顺序扫描，已有候选时抽签是否替换 |
| 1/2 HPMIN/HPMAX | 当前HP最小／最大 |
| 3/4 NEAREST/FAREST | 世界坐标曼哈顿距离最小／最大 |
| 5/6 LEVELMIN/LEVELMAX | live+0x9c等级最小／最大，不是气力代理 |

严格改善候选时，原函数**先更新比较基准，再抽 `0x458c10() & 1`** 决定保留旧目标还是换新目标。因此它不等于普通排序后随机打平。职业偏好另在 owner live+0x12c 的圆形近域内覆盖一般选择；该近域与find_range分别传入。

职业分组来自函数跳转表和TYPE：施法者85/87/90/91/97/98/99/100；弓83/84；剑80/81/82；盗88/89；翼92/93；兽94/95/96。多个优选对象同样抽保留签。原优选索引用0作sentinel，恰好与真实第0槽冲突；纯函数保留此行为，并用交换owner槽的样例检查。排除SID命中时会回退此前候选，某些扫描路径可能保留旧比较基准；机器包只声称已初始化、已执行的路径，不推断未定义栈值。

104组目标样例覆盖7种排序×7种职业偏好×2个种子、范围0/4/8、近域0/5、排除SID、阵营、已移除对象、空槽、远处角色及第0槽sentinel。每组核对返回槽+1和全部抽签；返回0表示无目标。函数不直接验证HP0，产品入口把当前死亡角色视为移除，防止死亡目标进入行动。

## 0x40c570：普通／魔法／特殊技

原函数接受当前角色和已准备的魔法／特殊技可用标记，返回0普通、1魔法、2特殊技。它使用 `0x458c80(99)+1`，样本范围1～99；**同一个样本的奇偶** 决定先试哪类：奇数先特殊技，偶数先魔法。随后也用这个样本与该类倾向做 `<=` 比较。

先试类别不存在时，第二类继续复用原样本；先试类别存在但概率未通过时，第二类才再抽一次99。禁魔位2使魔法不可用，不禁止特殊技。两类均不通过才返回普通。原摘要所谓“另抛硬币决定先后”已被更正。

96组动作样例覆盖6组倾向、4种可用组合、禁魔与否和2个种子。纯规则与原代码核对类别和RNG消耗；特别检查95/0、0/100、50/50、20/90等组合，而不只测试100%固定结果。

这两个AI函数的RNG是 **0x458c10/0x458c80，状态0x4795d4/0x4795d8**；不同于伤害／状态helper用的0x42c780及另一组状态。原调用序列从 `0x43fa8d..0x43face` 可见：先试返回类别，失败后 `(kind+1)%3` 轮换。纯规则保存该顺序；完整调用者未整体执行。

## 已接入第一战的动作事务

`_prepare_ai_turn`先验证来源身份、策略、移动输入、技能字段及可施放对象；全部完成后才进行目标／类别抽签。必要字段不完整时返回命名scenario_error，units、队列和既有收据保持不变，不偷偷改用普通攻击。正常缺MP/ST或禁魔则仅改变可用类别。

玩家与AI使用相同 `SkillResolutionRules` 拥有权、费用、范围、状态资格和效果提案。魔法与特殊技统一进入 `_try_skill_turn→_resolve_skill`，只有PlayLoop提交扣费／移动／所有目标变化。旧 `_try_mage_turn` 独立100上界施法概率已删除。普通攻击继续使用共享交换／反击路径。选择结束后只推进一次当前槽，状态收尾和下一可控队友交接保持同一合同。

原函数外仍保留以下**明确重制组合规则**，不升级成原整体AI等价：

- 源范围内存在本回合可攻击目标时，先保留可攻击集合，再由原目标规则排序；保留用户此前批准的绕开封闭最近敌人、长枪原地保持距离的行为。
- 源SID排除在产品候选生成前执行，防止被排除的最近对象压掉其余合法目标；纯原函数的回退quirk仍单独对照。
- 原 owner+0x12c 近域在产品暂用当前move_point适配；字段初始化的完整连接仍待证明。
- 选定目标后沿现有WRD合法移动包络，普通攻击取最低移动费用与横向偏移；魔法取最小位移、受支持法术中选择一项。未声称原路径／法术评分完全恢复。
- 没有本回合可攻击目标时，向选定目标推进；源搜索无结果时现可采用队友呼叫，仍无有效目标才Wait。呼叫分支独立于find_range，详见后续证据。

实际整回合回归覆盖敌方普通攻击、法师MP事务、友军气刃斩ST事务、死亡／无目标、搜索半径、移动路径、缺MP、禁魔解除和毒伤、坏身份／抗性／策略在RNG之前拒绝，以及只交接一次。新图证通过实际Wait按钮触发Runtime AI与演出，见 [AI Control验收](../runtime_observations/ai_decisions/README.md)。测试夹具授予Leonard ST100和AI控制权，不修改正常第一战起始ST0与控制权。

## 协助、低HP分支与未恢复部分

SR-036 已将 `0x40bee0` 广播与 `0x43f6c2..0x43f74e` 普通搜索失败时的呼叫消费接入公共行动：28组原正常返回及12组明确有界prefix验证精确阵营、圆边界、直接覆盖、普通目标优先及采用时清空。旧文“0x43f660先消费标记”错误，实际采用始于0x43f6e6。PlayLoop 使用稳定单位ID，死亡／离场／终局清理为明示重制策略；原helper没有removed过滤，原排除word与live SID适配也分别记录。详见 [AI呼叫证据](original_ai_calls.md)。

已读 `0x40c620..0x40c76c`：准备已拥有且资源足够的特殊技／魔法function桶，包含ST倍率、MP和禁魔检查；**它不是地图洪泛或移动扫描函数**。SR-037进一步执行`0x40bf70`残血敌方方域扫描、`0x40c110`自身低HP、首件回血药和优先级前段，接入共同用药自救／机会进攻，见 [original_ai_priority.md](original_ai_priority.md)。原桶的全部技能与评分仍未复原；`0x40d4e0`已证为单体／范围先后选择，`0x40c970`是c770尾部，实际后继入口c9a0。当前未注册治疗／辅助技能不会由AI私造效果。

原整体16状态机、已有目标的锁定／等待、原引擎标记清理与slot复用、治疗和辅助优先级、麻痺wake/skip、ai_fixed、完整原路径选择、全部能力和NPC动态等级初始化仍为缺口。PLAYERS原包字节差异不因本包消失。这里交付的是可复用且已接入的目标／进攻类别公共切片，呼叫接入不代表原整体AI完成。

## 复跑

```sh
python3 tools/hsl.py check ai_profiles
python3 tools/hsl.py check ai
godot --headless --path . --script res://tests/run_ai_decision_tests.gd
uv run --with unicorn==2.1.4 python3 tools/hsl.py generate ai --exe "$HSL_ORIGINAL_DIR/hsl01.exe"
tools/verify.sh
```

默认checker不重新执行原EXE，只重算已保存200组结果与边界。`--execute`才在最多16384条原指令、已读callee allowlist内重新执行，并确认输入对象／角色内存未改变；`--write`必须同时要求实际执行。

## 来源头迁入的备注

RULESCUT（2026-09-26）把 `game/` 模块 `## provenance:` 头里的长备注原样移到这里：头里 static-derived／resource-derived 只留 `tag path`，每条来源项不超过 200 字符（`hsl check provenance`）。每行是「模块 维度：原备注」。

- `game/sim/AIDecisionRules.gd` rules：0x40bb80 target selection over the registry order 0x4c34c0, 0x40c570 action category

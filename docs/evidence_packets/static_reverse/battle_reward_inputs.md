# 战斗奖励来源输入

> evidence: resource-derived; static-derived; runtime-measured: 携带 0x407c86 与掉落 0x44f5d3 的抽样都在全局流 0x458c10（整镜像模拟器） · status: live · functions: 0x407c40, 0x407cc0, 0x40ba20, 0x43ede0, 0x44e100, 0x44f580, 0x458c10 · tools: hsltools/data/battle_rewards.py, hsltools/evidence/reward.py, hsltools/probes/_reward_rng_trace.py, test_hsl_battle_rewards.py · updated: 2026-09-26

Checked: 2026-09-19

本包保存 `resource-derived` 来源字段及后来核对的 `static-derived` 携带／掉落分支。当前已由 BattleRewardRules、PlayLoop 和领取／存档界面消费；来源、重制选择和产品验收分别记录。此前地图遗言／经验见 [战斗收尾验收](../runtime_observations/combat_aftermath/README.md)，领取与恢复见 [奖励验收](../runtime_observations/battle_rewards/README.md)。

## 来源与可复跑产物

- `content/imported/hsl/global/tables/PLAYERS.TXT`：全部 66 个 `[character]` 行的 `gold`、`carry_item` 和原始 `status` 值（2026-09-19 起不再限于第一章六类模板；一场战斗只消费其名单内演员的行，`BattleRewardRules.data_error` 仍拒绝缺行或 `status` 非零的演员）。
- `content/imported/hsl/global/tables/ITEM.TXT`：239 个物品的 `get_ratio` 与 `important` 字段。
- 原包 `@:\data\TOWNDEF.TXT`：提取上述角色行引用的全部 27 个携带候选表（26–36、38–46、48–52、55、56、58；此前只有第一章模板引用的 26、28、29、30、31、35），保存在 `content/imported/hsl/global/tables/carry_items.json`，保留成员 SHA-256。
- `content/generated/hsl/combat/rewards.json`：上述来源的关联结果及三个输入文件的 SHA-256；当前标记 `live: true` 仅表示已被产品消费，不表示原完整结算等价。

第一战相关模板 021／023 的 `gold` 字段为 100，024／026 为 120；已有第二战开发模板 025 为 500，001 为 0；后续正式战斗与遭遇战的怪物行如 036 为 10、037／038 为 80、049 为 700（携带表 46）。这只是表值，不能据此推断所有击杀都发放金币，也不能推断金币接收者、发放时机或跨关余额。保留 025 不表示第二战产品路线已完成。

候选表保留原顺序和重复值。例如 29 的条目是 `241,241,247,248,201`，不能去重成集合。001 没有声明 `carry_item`；产物用 `carry_list_declared: false` 区分未声明与显式列表，空列表不证明原版初始化分支。`status_raw` 保留源整数，不把尚未验证的位解释写成运行时掉落资格。

PLAYERS 的 tracked 表与此前原包核对存在的差异仍未解决。本次 `--pak` 只核对 TOWNDEF 成员和五份候选表，不会把它升级成 PLAYERS 全表原包一致性证明。`--check` 不需要原作安装；加 `--pak` 才读取本机原包，且不启动 Wine。

```sh
# 从当前已跟踪输入重建并检查生成数据。
python3 tools/hsl.py generate battle_rewards
python3 tools/hsl.py check battle_rewards

# 原包对照只读；不重写 carry_items.json 或 rewards.json。
python3 tools/hsl.py check battle_rewards

# 仅在明确更新原始携带表时使用，不能与 --check 合用。
PYTHONPATH=tools python3 -m hsltools.data.battle_rewards --import-carry \
  --pak "$HSL_ORIGINAL_DIR/hsl.pak"

PYTHONPATH=tools python3 -m unittest tools/test_hsl_battle_rewards.py
tools/verify.sh
```

## 已检查的边界

生成器拒绝重复角色、缺少第一章模板（`REQUIRED_ACTORS`）的表、重复物品 code、重复或缺失携带表、损坏的列表和不存在的物品引用。来源解析和数据检查保留列表顺序；陈旧产物、原包候选表不一致均明确失败，`--check` 不自动修复文件。八项 Python 回归覆盖这些路径，普通数据检查已进入完整门禁。

最初来源检查点没有游戏布局或动画改动；其 `d5f455c` 死亡／经验图证不追溯覆盖后来新增的领取。后续奖励实现及独立图证见下文；最终完整门禁 exit 和提交号以对应提交说明为准。

本次首次完整门禁的 Python／来源检查通过，Godot 冷导入阶段收到 `SIGKILL`，没有脚本错误诊断；不能据此断言具体终止原因。日志同时显示正在导入 `ignored/` 的临时截图，这些不是产品资源。门禁现仅在缺失时创建本地 `ignored/.gdignore`，保留原输出文件及已有标记，随后仍冷导入全部产品资源并执行所有套件；最终通过结果记录在提交说明中。

## 已核对的原指令分支

`battle_reward_branches.json` 保存 13 段原字节锚点。`PYTHONPATH=tools python3 -m hsltools.evidence.reward --exe "$HSL_ORIGINAL_DIR/hsl01.exe"` 已核对已知 SHA-256 的原 EXE；默认只检查紧凑证据包，不运行 Wine 或原函数。

- 携带选择 `0x407c40` 从阈值24开始；原 `rand(101)` 样本小于等于阈值时接受，未接受后阈值在不低于10时减6；`-1` 不抽样但继续降低阈值，0结束，首个接受项进入背包。**调用位置（lane P4，2026-09-26，static-derived）**：全 EXE 唯一调用者是敌方对象过程 `0x43ede0` 初始化分支 `0x43eef6` → `0x407cc0`（站位取整、`0x458c80(0x18)` 加到对象 `+0x7c` 张延迟计数、`0x407660`）→ 仅当 live 模式 `0x40ba20(actor) == 0x20000`（pmEnemy）时 `0x407c40(actor)`：读该演员 shape record `+0x2e`（PLAYERS `carry_item`）→ `0x44e100` 取 TOWNDEF 候选表 → 首个接受项经 `0x436e30` 进背包。因此**任何在首次过程 tick 时已是敌方的演员**都掷一次，包括剧情插入后被 `0x407ec0` 按 obj_Data9 换成 pmEnemy 的 023／024（R33 在 53 关看到的三名 023 携带 246／249／249 都是 023 `carry_item = 28` 表 `[246, 241, 247, 248, 249]` 的成员；模板背包本身为空）。它不在安装路径 `0x407ec0`／`0x4080b0`，也不是 EVEF 或 PLAYERS 的显式携带表。**抽样流与出生内次序（lane RNGC，2026-09-26，runtime-measured，`tools/hsltools/probes/_reward_rng_trace.py`）**：整镜像模拟器里每个对象的出生 `0x407cc0` 依次抽 `0x407dba` 的 `rand(24)`（张延迟，玩家方对象也抽）→ 仅 pmEnemy 在 `0x407c86` 逐项 `rand(101)` 到接受为止 → 等级调整 `0x40e870`（首抽 `0x40e92c`）；三处都经 `0x458c80` 抽全局流 `0x458c10`（字 `0x4795d4／0x4795d8`），不经伤害流换入 `0x42c780`。51 关开局 12 次出生逐个按此次序；53 关 enemy023_1（表 28 `[246, 241, 247, 248, 249]`）固定其余局面、换 32 个全局流种子 `[s, s^0xe54a231c]`，每次的抽值个数、接受项和抽后全局字都等于上面阈值序列在同一状态上的结果。
- 掉落 `0x44f580` 先检查排除条件（不死记录 `0x446bb0` 整包跳过），再扫描当前背包八槽；重要物品不抽样，普通物品仅当 `rand(100)+1 < get_ratio` 才加入一件。不能把 `get_ratio=100` 写成一定掉落。重复 code 按实际槽位分别处理。**抽样流（lane RNGC，runtime-measured）**：`rand(100)` 在 `0x44f5d3`，同样经 `0x458c80` 抽全局流 `0x458c10`。51 关 actor021_1 背包 `[241, 246, 1, 281, 210, 227, 32, 249]` 换 32 个全局流种子，281（重要）不抽、其余七项各抽一次；另一局自然击杀（51 关第 2 回合 actor023_2，背包 `[1, 2, 3, 227]`）在击杀结算里连抽四次 92／75／10／65，一件不掉。
- 携带与掉落的抽样流、抽样点已实测；完整奖励／经验／取物状态机仍不是隔离执行。源 status 非零模板当前明确拒绝，不用未解位值猜资格。

## 当前提交与恢复合同

PlayLoop 初始化及增援时为敌方执行携带选择；当前可控角色击败敌方获得共享金币与其现有背包掉落，含反击。非可控击杀者照原版 `0x442720`：状态 2 在 `0x40ba20` 恰为 `0x10000` 时把击杀金付进队伍金钱（`0x442837..0x44284a`，封顶 `0x3b9ac9ff`），否则加到它自己的记录 `+0x98`；状态 4 对非玩家进程由 `0x44f600` 把本次收集（受害者掉落、它的金之手所得）收进它自己的包，不进玩家获得物品窗（[player mode](original_player_mode.md)）。装备 230 黃金的聖杯（ITEM `gold_x2`）时付款先翻倍（`0x442819..0x442825`）。不死受击者每次致死都照发击杀金、不掷掉落、不记阵亡；不死攻击者被反击打死整次交换不发。剧情离场和主角失败不凭空发玩家奖励。这些资格与初始余额0是明确重制策略；携带与掉落的抽样流是原版全局流（见上）。

一次完整交锋生成带 sequence 的奖励收据、死亡去重记录和待领取实例。范围状态伤害对所有唯一目标累计实际扣血及来源 kill_exp，一次扣费；成长刷新仍会夹紧 HP/MP。死亡清除异常、命中补偿、气力、行动与呼叫状态，掉落生成后清空死者背包；战斗数值、库存、余额和领取进度全部由唯一 PlayLoop 提交。

领取使用 sequence/revision/实例ID 与接收者真实槽位校验；满包显式交换，换出物留在待领池。取消不移动物品，普通剩余物可以二次确认放弃，重要物品不能放弃；“稍後領取”保留它们跨后续交锋，并可从状态页或结果页重新打开。UI 另校验实际控件和显示 epoch，读档后同编号旧按钮也不能重复提交。

F5 在安静行动／领取／结果边界保存，F9 从这些边界或新启动开场恢复。同一版本的校验和存档原子替换，恢复完整单位、队列、库存／成长、余额与领取状态；已结算交锋直接标记为已展示，不重放初始化、攻击、死亡或发奖。配置不同／损坏拒绝且保留当前游戏。它是单战手动存档，不能据此声称原版存档兼容、跨关承接或任意动画中途恢复。

原完整 EXP 公式、掉落资格、原取物暂持／取消 handler、原 UI 排版和跨关经济仍为独立未恢复边界。替换当前策略需对应 caller／连续原片段或原函数执行证据，不能仅根据录像中的一次 `$100` 修改全局规则。

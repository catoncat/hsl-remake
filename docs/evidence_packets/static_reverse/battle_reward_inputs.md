# 战斗奖励：携带选择、掉落、击杀金与地图收尾

> evidence: resource-derived; static-derived; runtime-measured: 携带 0x407c86 与掉落 0x44f5d3 的抽样都在全局流 0x458c10（整镜像模拟器） · status: live · functions: 0x407c40, 0x407cc0, 0x40ba20, 0x43ede0, 0x44e100, 0x44f580, 0x458c10 · tools: hsltools/data/battle_rewards.py, hsltools/data/combat_aftermath.py, hsltools/evidence/reward.py, hsltools/probes/_reward_rng_trace.py, run_battle_reward_tests.gd, run_combat_aftermath_tests.gd · updated: 2026-09-27

## 结论

- 原版：任何在首次过程 tick 时已是 pmEnemy 的演员出生时按 PLAYERS `carry_item` 取 TOWNDEF 候选表，从阈值 24 起逐项 `rand(101)` 选首个接受项放进背包；击杀时扫描受害者八槽，重要物品不抽，普通物品 `rand(100)+1 < get_ratio` 才掉一件；两处都抽全局流 `0x458c10`，不经伤害流（static-derived；runtime-measured）。
- 击杀金：可控方击杀付进队伍金钱（封顶 `0x3b9ac9ff`，黃金的聖杯翻倍），非可控击杀者加到自己记录 +0x98，其收集进自己背包（static-derived）。
- 重制：`BattleRewardRules` 与 PlayLoop 在初始化与增援时执行携带选择、击杀时生成带 sequence 的奖励收据与待领实例；地图收尾为遗言→淡出→地图 EXP→金币→領取→成长→后继（static-derived；收尾时长 provisional）。
- 差异：玩家奖励资格与初始余额 0 是重制策略；领取为确认／延期交互，单战 F5／F9 存档是重制功能（provisional）。

## 证据

**static-derived**（13 段原字节锚点见 [battle_reward_branches.json](battle_reward_branches.json)）

| 条目 | 锚点 | 行为 |
| --- | --- | --- |
| 调用位置 | 全 EXE 唯一调用者：敌方对象过程 `0x43ede0` 初始化分支 `0x43eef6` → `0x407cc0` | 站位取整、`0x458c80(0x18)` 加到对象 +0x7c 张延迟、`0x407660`；仅当 `0x40ba20(actor) == 0x20000` 时调 `0x407c40` |
| 携带选择 | `0x407c40` | 读 shape record +0x2e（PLAYERS `carry_item`）→ `0x44e100` 取候选表；阈值 24 起，`rand(101)` ≤ 阈值接受，未接受且阈值 ≥10 时减 6；`-1` 不抽样但降阈值，0 结束；首个接受项经 `0x436e30` 进背包 |
| 覆盖对象 | — | 剧情插入后被 `0x407ec0` 按 obj_Data9 换成 pmEnemy 的 023／024 也掷；不在安装路径 `0x407ec0`／`0x4080b0`，也不是 EVEF 显式携带 |
| 掉落 | `0x44f580` | 先查排除（不死记录 `0x446bb0` 整包跳过），扫描八槽；重要物品不抽；普通 `rand(100)+1 < get_ratio` 加一件；重复 code 按槽分别处理；`get_ratio=100` 不是必掉 |
| 击杀金 | `0x442720` 状态 2：`0x40ba20` 恰为 `0x10000` 时付进队伍金钱（`0x442837..0x44284a`），否则加到击杀者 +0x98；`0x442819..0x442825` 装备 230（`gold_x2`）先翻倍 | 状态 4 对非玩家进程 `0x44f600` 把收集收进自己背包（见 [original_player_mode.md](original_player_mode.md)） |

不死受击者每次致死照发击杀金、不掷掉落、不记阵亡；不死攻击者被反击打死整次交换不发。

**runtime-measured**（`tools/hsltools/probes/_reward_rng_trace.py`，整镜像模拟器）

| 场景 | 读数 |
| --- | --- |
| 出生内次序 | 每个对象出生依次抽 `0x407dba` 的 `rand(24)`（玩家方也抽）→ 仅 pmEnemy 在 `0x407c86` 逐项 `rand(101)` → 等级调整 `0x40e870`（首抽 `0x40e92c`）；三处经 `0x458c80` 抽全局流（字 `0x4795d4`／`0x4795d8`），不经 `0x42c780` |
| 51 关开局 | 12 次出生逐个按此次序 |
| 53 关 enemy023_1（表 28 `[246, 241, 247, 248, 249]`） | 32 个全局流种子 `[s, s^0xe54a231c]`，抽值个数、接受项、抽后全局字都等于阈值序列的结果；三名 023 携带 246／249／249 都属表 28 |
| 51 关 actor021_1 背包 `[241, 246, 1, 281, 210, 227, 32, 249]` | 32 个种子下 281（重要）不抽，其余七项各抽一次 |
| 51 关第 2 回合 actor023_2 自然击杀，背包 `[1, 2, 3, 227]` | 连抽四次 92／75／10／65，一件不掉 |

原版录像：普通致死接触表（原版帧见私有档案：`runtime_observations/original_gameplay_reference/12_leonard_normal_attack/contact_sheet.jpg`） 显示受击、回到地图及遗言；地图 EXP 原帧（原版帧见私有档案：`runtime_observations/original_gameplay_reference/15_post_attack_settlement_floats/frame_006.png`） 经验提示在地图上。

**resource-derived**（`content/generated/hsl/combat/rewards.json` 记录三份输入 SHA-256）

- `PLAYERS.TXT` 66 个 `[character]` 行的 `gold`、`carry_item`、原始 `status`；021／023 gold 100，024／026 120，025 500，001 0，036 10，037／038 80，049 700（携带表 46）。001 未声明 `carry_item`（`carry_list_declared: false`）。
- `ITEM.TXT` 239 个物品的 `get_ratio` 与 `important`。
- 原包 `@:\data\TOWNDEF.TXT` 的 27 个候选表（26–36、38–46、48–52、55、56、58），存 `content/imported/hsl/global/tables/carry_items.json`，保留顺序与重复（例：29 为 `241,241,247,248,201`）。
- 遗言与称号：`hsltools/data/combat_aftermath.py` 联接 PLAYERS `dead_message`／`job_show_name` 与 RESOURCE，保留非零变体，缺引用明确失败。

## 重制接线

- `game/sim/BattleRewardRules.gd`：`data_error` 拒绝缺行或 `status` 非零的演员；初始化与增援为敌方执行携带选择；可控角色击败敌方（含反击）获得共享金币与掉落；剧情离场与主角失败不发奖。
- PlayLoop：一次完整交锋生成奖励收据、死亡去重与待领实例；范围伤害累计实际扣血与 kill_exp，一次扣费；死亡清异常、命中补偿、气力、行动与呼叫状态，掉落生成后清空死者背包。
- 领取：sequence／revision／实例 ID 与接收者真实槽位校验；满包显式交换，换出物留池；普通剩余物二次确认放弃，重要物品不能放弃；「稍後領取」保留跨交锋，可从状态页或结果页重开（provisional）。
- 地图收尾：不可变收据驱动遗言（BOARD02／肖像／分页，取第一条非零遗言，不耗战斗 RNG）→ 淡出 0.45 秒 → 地图 EXP 1 秒（紫色上浮）→ 金币 → 領取 → 成长 → 后继；终局台词与结果页等待（provisional：时长、颜色、字体）。
- F5／F9：安静行动、领取、结果边界的单战存档，校验和原子替换，恢复不重放发奖；配置不同或损坏拒绝（provisional，不是原版存档兼容）。

## 复现

`python3 tools/hsl.py check battle_rewards`；`python3 tools/hsl.py check reward_evidence`；`python3 tools/hsl.py check combat_aftermath_data`；重制侧 `tools/godot.sh --headless --script tests/run_battle_reward_tests.gd` 与 `tests/run_combat_aftermath_tests.gd`。截图驱动 `tests/capture_battle_reward_review.gd`、`tests/capture_combat_aftermath_review.gd` 保留（`tools/oss_screenshots.py` 使用），旧回执在 `runtime_observations/battle_rewards/`、`combat_aftermath/`。

## 边界

- 完整奖励／经验／取物状态机没有隔离执行。
- 源 `status` 非零模板的掉落资格未解，重制明确拒绝。
- PLAYERS tracked 表与原包差异未解决；`--pak` 只核对 TOWNDEF 与候选表。
- 原遗言随机选择、完整死亡 handler、原取物暂持／取消 handler 与跨关经济未读；獲得物品窗见 [original_getitem_window.md](original_getitem_window.md)。

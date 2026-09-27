# 额外行动：白光之翼与同一角色连续两次行动

> evidence: static-derived · status: live · functions: 0x40e240, 0x40e2b0 · tools: hsltools/probes/extra_action.py, run_extra_attack_tests.gd · updated: 2026-09-28

## 结论

- 原版装备效果 bit8（源 ITEM227 白光之翼 `action_twice=1`）让同一角色在完成一次完整行动后立即重新进入自己的菜单／AI 决策；第一次重入跳过毒伤、状态递减与队列推进，第二次完成才走最终出口；已授予的第二次不因卸装消失，也不会叠出第三次（static-derived）。
- 重制 `game/sim/ExtraActionRules.gd` 提出授予，`game/sim/loop/BattlePlayLoop.gd` 的 `extra_action`（owner_id、pending、sequence）是唯一状态，原版没有“再次行動”提示也不停顿，重制原版值同样不提示；`game/battle/scene/BattleExtraActionCue.gd` 只在 OPT-GUIDE＝提示 时显示并停 0.55 秒（static-derived；提示为 remake-invented）。
- 一致：5 组 getter 完整返回与 20 组玩家／AI 收尾前段均与重制合同相符；完整高位 dispatcher 资格与原全局 RNG 未读（static-derived）。

## 证据

**static-derived**（SHA 锁定 EXE；原代码与 getter 均未替换或 stub；[original_extra_action.json](original_extra_action.json)）

| 项 | 锚点 | 读法 |
| --- | --- | --- |
| 字段 loader | `0x447e1f` | ITEM `action_twice` → 装备效果 bit8；`double_attack` 是另一位（`0x447fea` → `0x8000`），可独立存在 |
| getter | `0x40e2b0` → `0x40e240` | 读当前角色装备效果 mask8 |
| 玩家收尾门 | `0x443a86`，最终 phase `0x10003` | 用原全局计数 `0x4c1cf0` |
| AI 收尾门 | `0x441f08`，最终 phase `0x640001` | 同上 |
| 下游（第一次重入不经过） | 毒 HP `0x443ad1`；kill-chain 清理、状态递减、队列推进 `0x443c09`、`0x442080` | 最后一次行动才处理 |

| 已用额外行动 | 当前装备 bit8 | 原分支 |
| --- | --- | --- |
| 否 | 无 | 最终状态／队列出口 |
| 否 | 有 | 置已进入第二次，phase 回 0，立即重入同一角色菜单／AI |
| 是 | 任意 | 清标记进最终出口，不再调 getter |

- 原菜单初始化不重置该标记：第一段后卸下白光之翼，第二次仍在；第二段再装备不产生第三次。
- 第一次后禁魔仍有效，毒不扣 HP 也不减时间；无效果物品／取消／免费装卸不调用成功行动出口。
- 源 ITEM 53／55／57／58 也声明 `action_twice`，但含未知附带字段或不支持的范围，保持拒绝装备；227 其余字段均已支持。

| 执行类别 | 覆盖 | 不能据此声明 |
| --- | --- | --- |
| getter 完整返回 | 5 组：无 flag、仅 bit8、仅 double_attack、二者、复合 mask；返回／栈／输入不变 | 整个装备 loader／角色初始化已运行 |
| 玩家／AI 收尾前段 | 20 组：两入口 × 五种效果 × 首次／第二次；第二次 getter 调用数 0，HP／状态／kill-chain／队列游标不变 | 完整回合、UI、状态或渲染返回 |
| 原字节锚点 | 8 段：loader、getter、两类门、毒处理、最终出口、菜单重入 | 下游状态／队列沿既有证据复用 |

## 重制接线

- `game/sim/ExtraActionRules.gd`：装备查询、状态校验与 repeat 提案；provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_extra_action.md`。
- `game/sim/loop/BattlePlayLoop.gd`：`extra_action` 在同一战斗字典；pending 只属当前存活行动者，死亡、剧情离场与三种终态清空；首次完成按现装备授予并重置本段移动／攻击资格，再次完成经 `game/sim/CoreTurnQueue.gd` 原出口。每段新 sequence；旧 `finish_exhausted_action` 在新段无效。
- AI 两段各自重新规划（目标死亡、已治愈、MP 耗尽、禁魔走当前合法动作或 Wait），不重放第一段意图。
- `game/battle/runtime/BattleCheckpoint.gd`：F5/F9 保留第二段、现装备与已确认位置，读取不调用授予入口（重制存档格式，不兼容原作存档）。
- `game/battle/scene/BattleExtraActionCue.gd`：读 pending 与 sequence；原版值不显示、不停顿（原版无此提示）；OPT-GUIDE＝提示 时在前一段移动／交锋／遗言／EXP／领取／成长结束后显示，0.55 秒后开放菜单，避开 `BattleCommandMenu.layout_bounds()`；不加新音效（remake-invented：文字与时长）。

## 复现

`python3 tools/hsl.py check extra_action`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [extra_action](../runtime_observations/extra_action/receipt.json) | wait_status、equip_restore、move_attack_cast、double_series、growth_kill、support_cure、ai_cast、ai_support、ai_no_mp、ai_silence、victory、defeat、escape | `run_extra_attack_tests.gd`、`run_first_battle_playthrough.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- 玩家／AI 高位完整 dispatcher 资格未执行，收尾只跑到共同 dispatcher 尾前。
- 原全局 RNG、全部角色初始化与其他未实现异常／被动不在本包。
- 原时钟与逐帧 UI 未读；“再次行動”提示是重制反馈，只在 OPT-GUIDE＝提示 下出现。
- 首战默认不授予白光之翼。

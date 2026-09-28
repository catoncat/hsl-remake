# 脚本离场、角色在场资格与演出游标

> evidence: static-derived · status: live · functions: 0x407720, 0x411b90, 0x44cb90, 0x44fad0, 0x44fbd0, 0x450410, 0x450450, 0x453b90, 0x45e3ed · tools: hsltools/probes/departure.py, run_departure_tests.gd · updated: 2026-09-28

## 结论

- 原版脚本删除（`0x450410`）与行走删除（`0x450450`）按 code／serial 找已注册对象并置删除状态；删除阶段先置 16 逻辑 tick 再递减，最后一 tick 才依次清地图占用、行动队列、模板记录头与对象链接；HP／库存等记录字节不变，不走伤害、经验或死亡奖励（static-derived）。
- 重制 `game/sim/BattlePresenceRules.gd` 由唯一 PlayLoop 提交 `departed`、来源序号与队列移除，所有行动与 AI 共用同一在场查询；`BattleScriptPresentation`／`BattleDepartureView` 播放离场，快照保存已消费游标（static-derived）。
- 删除阶段的 16 tick 是 engMIX 层级 16→1 的逐 tick 淡出，重制 `BattleDepartureView` 同样每 tick 降一级、16 tick 淡完（static-derived，[original_script_entry](original_script_entry.md)「结论」）。
- 差异：重制先提交在场变化再播淡出，原版最后一 tick 才清占用与队列，这段逐 tick 交错未恢复（provisional）。

## 证据

**static-derived**（固定哈希原 EXE；[original_script_departure.json](original_script_departure.json)：56 组状态前段／返回、12 次删除请求与 16 次行走删除请求完整返回，另 4 组组合执行；未替换 callee）

| 地址 | 结论 |
| --- | --- |
| `0x450410` → `0x44fad0` | 按已注册对象 code／serial 查找，置状态 `0x350000` 并关联脚本父对象；serial 0 与 1 选首个，超出匹配数选最后一个，无匹配返回 0 |
| `0x450450` | 只接收空闲对象；写目标坐标、速度参数与父对象，进入 `0x360063`；16 例覆盖两个 code、有／无匹配、空闲／忙碌、两组坐标／速度，目的地均为合法空地 |
| `0x44fbd0` | 16 例只经过其无修正返回分支 |
| `0x453b90` 中 `0x454286`、`0x4542a7` | 阶段 0x35／0x36 相应子阶段先置 16 逻辑 tick 再递减，仅最后 tick 注销；计时未完不清地图与队列 |
| `0x411b90` → `0x407720` → `0x44cb90` → `0x45e3ed` | 依次清地图占用、行动注册／队列、模板记录头、对象链接；1 格与 3×3 同序；移除当前队列项选下一有效项，移除其他项保留当前项 |

56 组状态覆盖 0x35 子阶段 0／1、0x36 子阶段 7／8／99，当前／非当前对象、1 格／3×3、有／无父对象：非当前对象完整返回；当前对象注销后停在 `0x4542ff`（其后 renderer/reset 未执行）。4 组组合执行先注销一个同 code 对象，再以 serial 0／1／2／9 删除，确认后续查找只计尚注册对象。

## 重制接线

- `game/sim/BattlePresenceRules.gd`：离场不伪造成 HP0 或击杀；大型角色一次释放九格；过期目标在付款与 RNG 前拒绝；当前角色离场撤销待移动／额外行动，保留资源、状态计时与已完成收据；其他角色离场不消耗当前行动。
- `game/sim/WinfailActions.gd`：记录每次触发的身份与 `firing_index`，PlayLoop 消费一次；玩家与 AI 新交锋序号进入攻击后事件入口，等待／物品／旧收据不重触发。
- `game/battle/scene/BattleScriptCoordinator.gd`：只扩展战斗绑定查询，以 `firing_index`／原 token 参数／稳定 unit ID 确定离场对象；story-only／世界／城镇不读战斗离场记录。
- `game/battle/scene/BattleScriptPresentation.gd`、`game/battle/scene/BattleDepartureView.gd`：交锋、死亡／EXP／领取／成长与用药完成后才播脚本，第二行动提示在脚本之后；演出期间阻塞控制。
- `game/sim/loop/BattleLoopScript.gd`：快照保存规则执行记录与已消费游标，配置摘要绑定状态脚本、timeline 与对象绑定；未播完的脚本不是存档边界；旧版缺字段快照拒绝；重开清除离场与游标；战役 carry 不承接离场。
- provenance 头写 `rules: static-derived docs/evidence_packets/static_reverse/original_script_departure.md`。

## 复现

`python3 tools/hsl.py check departure`

重制侧实际输入回执（Godot 正常时钟、真实控件；夹具与进程边界见各回执 JSON）：

| 重制回执 | 路线 | 驱动 |
| --- | --- | --- |
| [script_departure](../runtime_observations/script_departure/receipt.json) | walk、delete、giant、second、blocked、mage、support、ai、paralysis、kill、victory、defeat、escape、carry、rearm | `run_departure_tests.gd`、`run_first_battle_playthrough.gd`；截图驱动已退役，回执为历史记录 |

## 边界

- `0x44fbd0` 的障碍替代位置搜索本包未执行，静态读法见 [original_script_entry](original_script_entry.md)。
- 对象后续全部移动阶段、全局时钟与内存槽复用不在等价声明内。
- 在场变化先提交、演出后读取是重制原子事务，不推导原 VM 逐 tick 交错相同。
- 跨战回血与阵容承接是重制策略。

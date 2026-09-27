# 原结局分派：actSetNextPlayLevelGetOverEvent 的 over score／flag 选择

> evidence: static-derived · status: live · functions: 0x42c4b0, 0x42c4d0, 0x42c520, 0x42c7e0, 0x42cc10, 0x42cc60, 0x42e070, 0x42e640, 0x450840, 0x454e20, 0x45b531 · tools: run_story_scene_tests.gd · updated: 2026-09-27

## 结论

- 原版 `actSetNextPlayLevelGetOverEvent`（STORY057 传 0）由 `0x42c520` 选结局：三个 over score 按分数降序（同分保 1、2、3 原序），第一个 flag 条件成立的 id 决定 76／77／78，ID1 的条件是「没有任何 flag」，都不成立返回 76（static-derived，未执行）。
- 重制 `game/sim/EndingDispatchRules.gd` `route(over_score, over_flag)` 实现同一排序与判定，`BattleOpeningCoordinator._end_route_choices` 按结果只列该结局一行（static-derived 输入）。
- 差异：开发者按键覆盖不建模；预览关只有 `skip_battle` 第一胜利段的分数到账（provisional）。

## 证据

### static-derived

来自 SHA256 `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7` 的 `hsl01.exe`（与[原宝箱](original_treasure.md)同一映像）：以 `r2 -q -e scr.color=0 -c "s ADDR; pd N" hsl01.exe` 直接读反汇编，函数边界与调用点由 .text 段的 `E8` 相对调用逐字节扫描核对（`0x42c520` 只被 `0x452a26` 调用；`0x42c4b0` 被 `0x451182` 调用；`0x42c4d0` 被 `0x451196`（剧情解释器）与 `0x455494`（城镇解释器 `0x454e20`，teAddOverScore）调用）。脚本侧写入清单来自 tracked 语料库 `content/imported/hsl/story_corpus/scripts/` 与 `content/imported/hsl/global/world_map/towndef.json`。

ACTION.H：`actSetOverFlag 127 [flag]`、`actAddOverScore 128 [id][score]`、`actSetNextPlayLevelGetOverEvent 129 [level]`；TYPE.H：`gameoverflagFreeEnemy 0x1`、`gameoverflagEnemyJobUp 0x2`、`gameoverID1..3 = 1..3`。

#### 函数与全局

| 地址 | 作用（本项目标签，非原符号） | 读法要点 |
| --- | --- | --- |
| `0x450840` 剧情脚本解释器，case `0x7f`（`0x45117c`）／`0x80`（`0x45118c`）／`0x81`（`0x452a1a`） | 三个 act 令牌的分派 | `0x7f` 取一参调用 `0x42c4b0`；`0x80` 取两参调用 `0x42c4d0`；`0x81` 把对象状态 `+0x8c` 置 `0x2b0000`（与 `actSetNextPlayLevelEvent` case `0x2b` 相同的「换关」状态），`edi = [level]` 参数，调用 `0x42c520` 得结果 `eax`；`level == 0` 时 `level = eax`；结果 ≠ 49（gameBigMapLevel）时 `0x42cc10(level, eax)` 写下一关／事件——STORY057 传 0，因而得到 `[76,76]`／`[77,77]`／`[78,78]`；结果为 49 时另走 `0x42cc60` 后 `0x42cc10(49,49)`（脚本中不出现） |
| `0x42c4b0` | over flag 置位 | `[0x4c1bd8] |= arg`（OR，不清位） |
| `0x42c4d0` | over score 累加 | id 1／2／3 → `[0x4c1bdc]`／`[0x4c1be0]`／`[0x4c1be4] += score`；其他 id 无操作；负分照加（TOWNDEF 37 写 `gameoverID2,-2`） |
| `0x42c520` | 结局选择 | 见下节 |
| `0x42c7e0` 新游戏世界初始化（读 `DATA\\BIGMAP.DAT`） | 清零 | `0x42ca82–0x42ca94` 把 flag 与三分全部写 0（ebx=0） |
| `0x42e070` 存档 `SAVES\\HSLBATnn.SAV`／`0x42e640` 读档 | 持久化 | `0x42e2d0–0x42e2ea` 把四个 DWORD 写入存档，读档对应恢复——over 状态随原 戰場記錄 保存 |

#### `0x42c520` 的选择算法

1. 栈上建三对 `(id, score)`：`(1, [0x4c1bdc])`、`(2, [0x4c1be0])`、`(3, [0x4c1be4])`。
2. 最多三趟冒泡（`0x42c563–0x42c5a1`）：相邻两对比较 `cmp ebx, ebp; jge`——只有前一对分数**严格小于**后一对时交换，因此同分保持 1、2、3 的原序；无交换即提前结束。
3. 若 `[0x4c1ae8] != 0`（`main` 按命令行开关置 1 的开发者模式），`0x45b531(2/3/4)` 读键位表 `0x4c2374`：按下 2／3／4 直接返回 76／77／78。产品不带该开关，重制不建模。
4. 取 `cl = byte [0x4c1bd8]`，按排序后顺序逐个判定（`0x42c5de–0x42c606`）：
   - id 1：`test cl, 3; je` → 两个 flag 都未置才返回 **76**（妖精王）；否则看下一个；
   - id 2：`test cl, 1; jne` → 置了 `gameoverflagFreeEnemy` 才返回 **77**（席德爾）；
   - id 3：`test cl, 2; jne` → 置了 `gameoverflagEnemyJobUp` 才返回 **78**（接觸）。
5. 三个都不满足（`edx >= 3`）返回预置的 `edi = 0x4c` = **76**。

即：**分最高、且其 flag 条件成立的 gameoverID 决定结局；ID1 的条件是「没有任何 flag」。**

### resource-derived：脚本侧的输入

| 写入 | 位置 |
| --- | --- |
| `actAddOverScore gameoverID1,3`＋`gameoverID3,1` | WINFAIL017 win 0（艾瓦台地 胜利） |
| `actAddOverScore gameoverID2,2` | WINFAIL021 win 0（回音之谷 到达胜利） |
| `actAddOverScore gameoverID1,1`＋`gameoverID3,2` | WINFAIL021 win 1（回音之谷 HP 低胜利） |
| `actAddOverScore gameoverID1,1`＋`gameoverID2,2` | WINFAIL900 event 0（曼多力亞 選擇一，踢开士兵不战） |
| `actAddOverScore gameoverID1,2`＋`gameoverID3,1` | WINFAIL900 event 1（選擇二，开战） |
| `actAddOverScore gameoverID2,3` | WINFAIL902 win 0（艾瓦台地・尋 到达胜利） |
| `teAddOverScore gameoverID3,2`＋`gameoverID2,-2` | TOWNDEF 事件 37 |
| `teAddOverScore gameoverID2,2` | TOWNDEF 事件 38 |
| `teAddOverScore gameoverID1,2`＋`gameoverID3,1` | TOWNDEF 事件 185 |
| `actSetOverFlag gameoverflagEnemyJobUp` | WINFAIL037 event 48（`actCheckPlayerAttacked` 触发的敌方 `actPlayerJobUpProcess` 段） |
| `actSetOverFlag gameoverflagFreeEnemy` | WINFAIL073 event 1（`actTRUE` 分支尾：選擇二 放走 席德爾） |

没有脚本清 flag 或减到负的分以外的写法；`actSetNextPlayLevelGetOverEvent` 只出现在 STORY057。

## 重制接线

- `game/sim/EndingDispatchRules.gd`（`hsl_ending_dispatch.v1`，static-derived）实现第 2／4／5 步（不含开发者按键）；`route(over_score, over_flag)` 返回 `{level, over_score_id, order, scores, over_flag, reason}`，`next_level_event` 给出 `[level, level]`。
- 存储：世界状态 `hsl_world_state.v1` 的 `over_score`（已由 TOWNDEF `teAddOverScore` 使用）与新增 `over_flag`；剧情侧 `actAddOverScore`／`actSetOverFlag` 由 `WinfailScenarioRules.WORLD_FLAG_ACTIONS`（正式战斗）与 `WorldScriptActions.STORY_KIND_ACTIONS`（剧情场景 `game_over_score_add`／`game_over_flag` 记录、`skip_battle.world_actions`）送入 `TownEventRules` 的 `teAddOverScore`／新 `teSetOverFlag`，与城镇写入同一存储；随 `campaign_progress` 一起持久化（对应原存档的四个 DWORD）。
- `BattleOpeningCoordinator._end_route_choices` 用 hand-off 世界状态求 `route`，卡片只列该结局一行（`opening.end_routes` 按 level 匹配，行带 `over_score_id`／`over_flag_condition`）；确认后按 `[level, level]` 交接，记录 `end_route_chosen`（static-derived，含 decision）。

## 复现

`tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_story_scene_tests.gd`（level 57 结束卡的 `EndingDispatchRules.route` 用例）

## 边界

- 开发者模式（`[0x4c1ae8]`）的按键覆盖不建模。
- 仍为预览场景的关只有 `skip_battle` 第一胜利段的分数会到账；其他胜利段与事件段的分数／flag 由正式战斗的解释器现场触发。
- `actEnterStorageWindow`／`actKeepPlayerST` 只记录。
- 没有有界执行。

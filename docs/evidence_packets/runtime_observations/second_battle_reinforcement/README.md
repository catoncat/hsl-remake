# 第二战 event1 增援入场（runtime-measured，重制节奏）

> evidence: runtime-measured · status: live · tools: capture_second_battle_reinforcement_review.gd · updated: 2026-09-23

来源：`tests/capture_second_battle_reinforcement_review.gd` 在 640x480 窗口以 `dev_first_control` 进入 level 52，击破 021 至剩一名后跑回合钩子，让解释器真实触发 WINFAIL052 event1（`actCheckEnemyNumber SID_ENEMY021 2`，严格小于）；`ScriptActorCreationRules` 以该关的 `script_actor_templates`（`obj_Story_Level52_Enemy21`）在脚本插入像素出生四名 `Enemy021_script_0_*`，落在 `actWalkPrevInsertObjectWait` 目标格 (7,38)、(12,38)、(4,30)、(14,30)，event_1 过场按事务回执（`BattleScriptActorPresentation.apply_event`）逐个显形并走入。R35 起与其他关的增援同一条路径；旧 `present_spawned_actor` 按格反查镜像的入场表现已删除。

| 截图 | 内容 |
| --- | --- |
| [00-inserted-at-edges](00-inserted-at-edges.png) | 第一名增援在脚本 `actInsertObject` 的底边插入点（227,1356）显形（链是顺序的：每个 `actWalkPrevInsertObjectWait` 阻塞到到位再插入下一名） |
| [01-walking-in](01-walking-in.png) | 沿 `actWalkPrevInsertObjectWait` 目标向上走入 (7,38) |
| [02-arrived](02-arrived.png) | 四名全部停在各自的 PlayLoop 格；`has_actor_motion()` 归零，行动菜单回到 雷歐納德 |

[manifest.json](manifest.json) 记录每名增援的 `insert_pixel`／`cell`／`target_world` 与触发方式。

## 结论与边界

- runtime-measured：增援由解释器触发、`ScriptActorCreationRules` 出生（事务 `script_actor_transactions[0]` 四个 `created_ids`，`reinforcement_deficits` 归零），起点为脚本插入像素、终点为 PlayLoop 格心；走速沿用开场的 160 px/s（重制值）。
- provisional：原作 `actCheckEnemyNumber(SID_ENEMY021, 2)` 的比较极性、插入对象的寿命、是否伴随镜头移动与等待回合均未证实；脚本未自重武装，解释器只触发一次 4 名增援。
- 不证明原版等价；本回放用 `_set_unit_defeated` 直接把 021 减到一名，只验证触发→出生→过场走入这条链。

复跑：`tools/play.sh --screen 0 --position 60,80 --resolution 640x480 --script res://tests/capture_second_battle_reinforcement_review.gd`（不要与 `tools/verify.sh` 的缓存清理并行）。

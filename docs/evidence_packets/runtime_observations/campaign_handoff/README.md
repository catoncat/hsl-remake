# 战役承接与正式战斗强制胜利回执：跨关 carry、续战存档、各关结算流转

> evidence: runtime-measured; resource-derived: 各关 STORY／WINFAIL token、EVEF 编队与宝箱字; static-derived: WINFAIL080 闸门 opcode; provisional · status: live · tools: capture_battle_review.gd, capture_campaign_handoff_review.gd, run_battle_sweep_tests.gd, run_campaign_tests.gd · updated: 2026-09-27

## 结论

- 原版关卡之间 HP/MP 是否回满、金币／物品如何结算、跨关存档流程均未读（provisional）。
- 重制只承接 `player_controlled` 单位的等级／经验／未用点数／四属性／装备／库存／击杀数与 loop 级金币，在 `BattlePlayLoop.create` 之后、`begin_battle` 之前经 `apply_campaign_carry` 施加，派生数值走 `ProgressionRules.refresh_growth_stats`；下一场景由 `CampaignProgress` 交接并写 `user://campaign_progress.json`（runtime-measured）。
- 各正式战斗在强制胜利夹具下都能从开场走到首次控制、结果页与战役交接；夹具只证明流转，不证明 AI、平衡、节奏或原版等价（runtime-measured）。
- 与原版的差异归差异清单 `carry-model`、`script-entry-paths`、`winfail-readings`（provisional）。

## 证据

### runtime-measured：承接合同

| 项 | 读数 |
| --- | --- |
| 第一战→第二战 | 结局台词 371 先于结果页；结果页「下一戰 · 惡夢的終曲」与「查看待領物品」同位互斥；重载后 Leonard 带等级／金币进入同一 PlayLoop（`01-closing-line.png`、`02-result-next-battle.png`、`03-next-battle-opening.png`；[review-manifest.json](review-manifest.json)：`applied_unit_ids=["leonard"]`） |
| 承接后 | HP/MP 回刷新后上限，气力按场景初值重置；其余单位与场景规则不变；开战后或空 carry 的应用为 no-op；actor 不符的单位跳过 |
| 续战存档 | 每次 hand-off 写 `{scenario_path, carry, from_scenario_id}`（`hsl_campaign_progress_save.v1`）；新进程进首关且存档指向更后关卡时，第一帧暂停并弹「偵測到戰役進度」提示（`resume-prompt.png`），「繼續」重载该关（`resumed-story-scene.png`），「從第一戰重新開始」删档；只存战役位置与受控单位 carry，不存战斗中途状态 |
| 序章链 | 52 胜利经 WINFAIL052 win_0 播 378 → 结果页「繼續 · 沃斯菲塔王座廳」→ story 058 → 060 → 53（`party: separate`，carry 不施加于緹娜）→ 结果页按 winfail `[1,1]` 进 level 1；loop.gold 三次交接后不变（`chain-01`…`chain-11`，[chain-review-manifest.json](chain-review-manifest.json)） |

### runtime-measured＋resource-derived：各关强制胜利回执

首次控制人数与胜利键来自 `tests/capture_battle_review.gd -- --level=N` 的窗口化运行；编队、宝箱字、事件回合来自该关 seed／WINFAIL。

| level | 场景 | 首次控制（单位／受控） | 胜利键 → 结果 | 独有读数 |
| --- | --- | --- | --- | --- |
| 3 盜賊洞窟 | `battle_003.json` | 17／3＋漢克斯 | win → 漢克斯加入 | 漢克斯开场 pmEnemy／undead，WINFAIL003 胜利段转 pmPlayer、清 undead；EVEF record 27 宝箱；→ STORY061 |
| 7 寧靜之森 | `battle_007.json` | 25／4 | win_0 → `victory_boss` | 第 5 回合 6 名 023＋2 名 024 增援，第 6 回合雪拉 005 以 `player_controlled` 加入；→ story 064 |
| 10 帕尼西亞城 廢墟 | `battle_010.json` | 6／2 | win_0 → `victory_optional_clear` | win status 在第 5 回合 event 3 才武装；1 宝箱 |
| 12 巴瀚納海峽 | `battle_012.json` | 39／7 | win_0 → `victory_script` | 45×60 格；62 个 Enemy101 船殼为静态物件；第 8 回合 actSetPlayerFixPos 把 32 名 038 的守备锚点改到四个图外撤退点（半径 1，走过去而非瞬移），第 10 回合 actWalkAndDelete 离场；事件回合 8／10／16／23 |
| 13 龍之息 | `battle_013.json` | 16／7 | win_0 → `victory_escape` | 到达矩形 (416,288)-(448,288) |
| 19 利魯瑪山地 | `battle_019.json` | 5／1（雷特） | win_0 → `victory_optional_clear` | event 1／2 增援 041／043／038；宝箱 record 9 [228]、10 [225]、11 [242,244] |
| 22 尼布魯瀑布 | `battle_022.json` | 15／7 | win_0 → `victory_boss` | 条件槽 008／009 未安装；041／043 增援、051 事件、actGetItem(14,1) |
| 26 亞雷比斯 | `battle_026.json` | 20／8 | win_0 → `victory_optional_clear` | 26 个 Enemy101 船壳为静态物件；第 14 回合 event_0 插入 7 名 035；win_0 = actCheckEnemyTotalNumber(0)；宝箱 record 52 (2,15) 物品 [68]；038 终点 (16,5) 为阻挡格，取最近可用格 |
| 28 眾神的宮殿遺址 | `battle_028.json` | 16／7 | win_0 → `victory_script` | win_0 由第 4 回合 round-display／event 链武装；九个非对齐终点取最近合法格 |
| 29 約瑟河 | `battle_029.json` | — | win_0 → `victory_boss` | next-level／大地图写入走 winfail hand-off |
| 31 漆黑之森 | `battle_031.json` | 9／3 | event_4 → 结果页 | 续接 actSetNextPlayLevelEvent(31,71)；item 252 |
| 32 拉格納沼地 | `battle_032.json` | 22／3 | 强制胜利 | 大地图 hand-off 33,34；actCheckNextSerialNumber、actInsertStoryObjectWaitPos；噴人沼氣见 [original_poison_gas](../../static_reverse/original_poison_gas.md) |
| 33 黃昏之丘　陰 | `battle_033.json` | 15／4 | event_4 玩家计数 → 结果页 | 原脚本走大地图 walk hand-off，review 规范为结果页 |
| 34 沙羅尼亞近郊 | `battle_034.json` | — | win_0 → `victory_boss` | STORY034 只写 fail／event status，正式战斗以 `initial_status_overrides.win=[0]` 武装 win_0（provisional）；无 next-level，actSetBMWalkToPoint |
| 36 薩魯司海岸 | `battle_036.json` | 16／7 | event_1 → 结果页 | 克羅蒂 009 条件安装与 no-attack；宝箱 record 24 在图外，记 `skipped_out_of_bounds`；续接 actSetNextPlayLevelEvent(36,gameBigMapLevel) |
| 38 幽闇墳場 | `battle_038.json` | 42／7 | win_0 → `victory_script` | 逃出区 [7,3]／[7,4]／[7,5]；event_1–7 离场，条件 event_8／9 因成员缺席跳过；win_0 结果前往 80 |
| 40 聖靈之森 | `battle_040.json` | 17／8 | win_0 → `victory_boss` | 第 14 回合六名脚本增援；3 个运行时安装槽 |
| 41 悲嘆之湖 | `battle_041.json` | 24／8 | win_0 → `victory_boss` | 胜利进 73 |
| 43 大地的裂縫 | `battle_043.json` | 25／7 | win_0 → `victory_optional_clear` | actDeletePosObject(816,111,4,defProcStandObject) 为对象请求，不判单位离场；actGetItem(16,1) |
| 73 兄弟的抉擇 | `battle_073.json` | 无首次控制 | 事件结束 → 大地图 | WINFAIL073 无 win／fail 段；event_0／event_1 两个选择分支都链到无条件 event_2 |
| 80 禁忌之魂・墳場地下 | `battle_080.json` | 30／7 | win_0 → `victory_script` | 到达两处删站立物件并发物品 112／15；见下行闸门；怨念體 068 以 `engADDCOLOR` 加色绘制，落点 (25,9) provisional |
| 901 菲納斯河畔 伏擊 | `battle_901.json` | 22／5 | win_0 → `victory_optional_clear` | — |
| 904 利魯瑪山地 再訪 | `battle_904.json` | 5／1 | win_0 → `victory_optional_clear` | — |

### static-derived

| 项 | 锚点 |
| --- | --- |
| WINFAIL080 两条宝物链末尾的 `actCheckEventNotExist 1,<另一条>` 是闸门：只有第二个宝物到手才武装 win_0；下方宝物在墙后，墙要 怨念體 068 倒下（event 3）才开 | `0x450840` case 0x72；`tests/run_winfail_rules_tests.gd` 的 `run_winnability_census`（80 关宝箱顺序） |

## 重制接线

- `content/battles/campaign.json`：关卡注册、`party: separate`、`next_level_event`（来自各战 winfail）。
- `game/sim/loop/BattlePlayLoop.gd` `apply_campaign_carry`；`game/sim/ProgressionRules.gd` `refresh_growth_stats`。
- `game/battle/runtime/CampaignProgress.gd`：一次性 `pending`、`next_destination`、`user://campaign_progress.json`。
- 正式战斗场景由 `tools/hsltools/levels/battle.py`（`python3 tools/hsl.py generate level_battle:N`）从预览、seed、EVEF 与演员模板组装；WINFAIL 由数据驱动解释器消费。

## 复现

`tools/godot.sh --headless --script res://tests/run_campaign_tests.gd`（承接合同）；各关回执 `tools/godot.sh --script res://tests/capture_battle_review.gd -- --level=N`。

## 边界

- 原版关卡间 HP/MP、金币、物品结算与关间剧情／商店未读；承接策略为重制选择（provisional）。
- 强制胜利夹具不是自然通关；增援落点、阻挡格最近合法落点、条件成员（咕嚕 008、克羅蒂 009）资格与安装时序、船壳计数条件、对象身份与 native scheduler 均为 provisional。
- 镜头、走位、对白时钟与结果页文案是重制表现，不作原版视觉依据。
- 各工作树的 Godot 测试共用 `user://`，并发 campaign 测试会清掉落盘文件。

# Level profiles: `content/battles/levels/NNN.json`

一关全部**逐关知识**（不能从导入的原作资源推导、由人决定的那部分）放在一个文件里：`content/battles/levels/NNN.json`（`hsl_level_profile.v1`，文件名即关卡号）。四个 Python 消费者与一个测试夹具只读它，自己不保留任何逐关字典或 `if level == N` 分叉；加一关的逐关知识＝写这一个 JSON。读取与结构检查：`tools/hsltools/levels/profile.py`（`hsl check level_profile:N`）。

## 分区（section）

| 键 | 消费者 | 内容 |
| --- | --- | --- |
| `battle` | `hsltools/levels/battle.py`（`level_battle:N` → `content/battles/battle_NNN.json`＋`content/generated/hsl/treasures/battle_NNN.json`） | `id`、`title`、`initial_focus_unit_id`、`initial_objective_phase`、`result_labels`；可选 `expected {units, players}`（写了就断言组装后的名册人数，防 seed／预览漂移）、`role_overrides`（**只写例外**：角色默认由放置推导——EVEF 玩家安装或 obj_Story_PlayerN 插入＝player_controlled，其余按对象安装后的 `player_mode`（PLAYERS mode → obj_Data9 互换 → obj_X1 覆盖，[阵营位读法](../evidence_packets/static_reverse/original_player_mode_sides.md)）：含 pmPlayer 位＝friendly_ai、否则＝enemy_ai；现存唯一例外是 003 的 漢克斯 `enemy_ai`，覆盖同时把 `player_mode` 拉到对应侧）、`initial_unit_state`、`initial_status_overrides`、`footprint_radius_overrides`、`treasure_exclusions`（key 为 EVEF record_index 字串）、`treasures: false`、`job_up_targets`、`derive_escape_zone`、`template_insert_skips`、`unit_ids`（`{EVEF token 或 STORY 插入符号: id 模式}`，模式里的 `{n}` 按开场顺序（EVEF record 序 → STORY 插入序）计数，同一模式串共用计数器：053 的 `SID_ENEMY023`／`obj_Story_Level53_Enemy23` 都写 `enemy023_{n}` 得 enemy023_1..3；未列出的单位沿用预览 id `actor{code}_{n}`／`guard{code}_{n}`／`leonard`）、`unresolved_semantics`（进生成物的说明句）。`initial_unit_state` 不接受 `coord`（起始格一律是追踪出的 STORY 终点整除读法，组装器遇到即报错）；winfail 插入一律生成 `script_actor_templates`（`ScriptActorCreationRules` 在插入像素出生、走到 `actWalkPrevInsertObject` 目标），没有逐关的落点策略 |
| `story_scene` | `hsltools/levels/story_scene.py`（`story_scene:N` → `content/battles/story_NNN.json`） | `id`、`title`、`player_token`；可选 `battle_opening_preview`、`player_installs`、`player_slot_inserts`、`standing_actor_inserts`、`token_overrides`、`static_bindings`、`shapeless_objects`、`excluded_source_actors`（`[{source_sid, source_actor_code, map_sprite_code?, reason}]`：预览与战斗都不出场的 EVEF 敌军 token，带理由；052 的 069 两名翼战士）、`lead_unit_id`、`end_card`、`end_exit`、`end_routes`、`end_routes_evidence`；`map_alias_note`（seed 有 `alias_of_level` 时：`shape_of_its_own`＝本关有自己的 shape 但 obs 地圖管理員 指向别关／`no_shape`（默认）＝本关没有 shape／`none`＝不写别名句）；`notes`＝该关追加进 `unresolved_semantics` 的说明句（原来散在 `if level == N` 块、`_CH2A_NOTES`、`unresolved_notes`、`unresolved` 四处，现合并为一列，插在派生句之后） |
| `cast` | `hsltools/levels/actors.py`（`level_actors:N` → 该关 walk／portrait／audio manifest；`battle.py` 的 `cast_gaps`／`missing_portraits` 也据此拒绝越界演员） | `actors`（EVEF／STORY／winfail 会绑定的 PLAYERS 三位码）、`speakers`（有肖像的说话人；有死亡台词的演员自动补入）、可选 `shape_sets`（actChangeShape 序列）、`shape_faces`（actShapeMessage 脸图） |
| `speakers` | `tools/hsltools/levels/message_text.py`（`SPEAKER_IDS[N]`，被 `story_scene`／`story_corpus` 引用；导入命令行 `tools/hsl_chapter_dialogue.py`） | `{脚本 token: RESOURCE.TXT id}`；随机遭遇 501–578 不建文件，共用代码里的 `ENCOUNTER_SPEAKERS`（按范围派生，不是逐关知识） |
| `speaker_policy` | 同上（`SPEAKER_POLICY[N]`，写进 `message_text_evidence.json` 的 `speaker_name_policy`） | 每个 token 的命名来源句（resource-derived／provisional）；`defNoOne` 与动作名键是说明行 |
| `sweep_fixture` | `tests/support/BattleForceWin.gd`（`run_battle_sweep_tests` 与 `run_story_mode_explorer_tests` 的强制胜利夹具） | 见下表；缺省＝`clear` |
| `comments` | 无（作者备注） | 原 Python 字典条目上方与内部的注释行，按 `battle`／`story_scene`／`cast`／`speakers` 分组保留 |

一个文件可以只含部分分区：正式战斗关有 `battle`＋`story_scene`（开场预览）＋`cast`＋`speakers`（051／052／053 三关自 S5／S11 起也是这一形态）；纯过场关没有 `battle`；`500.json` 只有共享遭遇演员池的 `cast`。

## `sweep_fixture` 模式

夹具的目的只是把一场注册战斗推到胜利结束（`battle_finished`）／战役交接，让 sweep 与 explorer 能继续走；它不是原版平衡或节奏的证据。五种模式覆盖原先 18 个逐关函数：

| `mode` | 做什么 | 参数 | 原函数 |
| --- | --- | --- | --- |
| `clear`（默认） | 保护受控名册、清空 fail status、逐相位击倒全部存活敌人并解算，直到战斗结束；仍无结果时走场景自带的 `escape_zone` 到达回退 | `arm_win_statuses`（首次控制时 win 为空则先装上并清空 event）、`advance_turn`（win 为空时先把回合推到 N 并跑一次 round hooks） | 通用体；080（arm）、010／045（event 3 → 回合 5） |
| `status` | 不清敌：按数据改状态后跑 hooks／解算，等战斗结束或战役交接 | `players`（`defeat`／`depart`）、`arrive {unit, cell | "escape_zone", restore}`、`turn`、`event_statuses`、`win_statuses`、`run_hooks`（默认 true）、`expect_no_outcome`、`expect_win_status`、`expect_victory_resolved`、`commit_outcome`（`{result, reason}` BattleOutcome 结构）、`finish`（`result` 默认／`pending_handoff`＝只等过场武装的战役交接，没有就调 `start_next_battle`／`handoff_or_result`＝等交接或战斗结束）＋`expect_handoff`（`"world_map"` 或 `{battle: "79"}`） | 013、028、030、031、033、036、037、038、073、078、902 |
| `rounds` | 逐个把回合设为 N 并跑 hooks／解算（每步清 fail），可选再分相位清敌 | `rounds`、`clear_phases`、`expect_win_unarmed_before`、`expect_undecided_after_rounds`、`expect_win_status` | 012、017、034 |
| `play_to_round` | 用真实的 wait 指令／AI 推进把战斗打到回合 N，再清敌解算并结算奖励 | `rounds`、`expect_units [{id, actor_id, role}]` | 007 |
| `choice_branch` | 逐回合推进并与协调器交互，到达 actSelectInsertEvent 时选行 | `rounds [{turn, expect_event_status?, select_option?}]`、`expect_install_unit` | 015 |

任何模式都可带：`opening_select_option`（开场 actSelectInsertEvent 选第几行，`play_opening`／`Autoplay.reach_first_control` 读；900 选 1）、`skip_opening`（脚本从进战即开事件链、没有首次控制阶段，调用方不播开场；073）、`note`（来源脚本时序说明）。调用方（sweep／explorer）用 `BattleForceWin.skips_opening`／`arms_own_handoff`（`finish` 不是 `result`）决定是否播开场、是否再调 `start_next_battle`。夹具按 `first_battle_scenario.level` 取文件；没有文件或没有 `sweep_fixture` 的关（含 5NN 遭遇、手工场景）走 `clear`。

## Tracer：level 200（S1 第 4 步，临时文件已删；S4 起 200 是正式的授权关）

S4 之后 `content/battles/levels/200.json` 只有 `battle` 分区，其余输入在 `content/authored/level200/`，由 `authored_level:200` 组装（[加关卡与角色逐步表](../MODDING_LEVELS.md)）；下面是 S1 用导入链复制品量出的记录，其中前两点已由 S4 的作者格式与 `CampaignProgress` 进谢幕解决。

把 level 5 的 seed（`battle200_seed.json`）与导入目录（`battle200/`）复制为输入，只手写 `levels/200.json`（`battle`／`story_scene`／`cast`／`speakers`／`sweep_fixture: clear`）＋ `campaign.json` 一行：`level_profile:200`、`level_actors:200`、`story_scene:200`（生成 `story_200.json`）、`level_battle:200`（生成 `battle_200.json`，13 单位／4 受控，标题与结果标签来自 200.json）、`level_map_objects`／`level_sounds`／`level_source_texts:200` 全部 PASS，不改任何 Python／GDScript；`HSL_SWEEP_LEVELS=200` 的 sweep 启动、播完开场、`clear` 夹具到达胜利结束。仍需代码或非本文件数据的地方：

- 导入链本身（seed／timeline／message_text_evidence／map_objects／actor manifest）来自 `hsl.pak` 的按关任务：复制来的 `battle_seed:200`／`message_text_evidence_check:200` 因来源校验（PAK 记录、evidence 的 `level` 字段）不通过——作者格式由 S4 lane 负责。
- 战后交接：脚本没有 `actSetNextPlayLevelEvent` 时回到该关自己的大地图点，200 不在 `world_map.point_level_range` 内，所以战斗结束后不武装交接（`CampaignProgress.next_destination`）；真正的新关要在 WINFAIL 写下一关或在大地图数据里有点位。
- `content/battles/campaign.json` 注册一行（流转不是逐关知识，是战役表）。
- 需要新 opcode 表现或新的 winfail token 支持时改 `timeline.py`／`WinfailScenarioRules`。
- 随机遭遇 501–578 的说话人表仍是 `hsltools/levels/message_text.py` 的 `ENCOUNTER_SPEAKERS`（按范围派生）；`hsltools/levels/seed.py` 的解码不在本文件内。`hsltools/levels/scenario.py` 已没有逐关 profile：只剩装配器共用的 winfail 读法（`SHARED_RESOURCES`、`status_timelines`）。

## 消融（S1 第 5 步）

- `role_overrides`：43 关的覆盖全部等于"该关 EVEF 玩家安装 → player_controlled"（预览 `story_actors[].role == 'player'` 已有此信息），只有 003 的 漢克斯 是真例外；组装器改为按放置推导默认角色，43 关的覆盖删除后 122 份 `battle_*.json` 逐字节不变。
- `expected`：只有 `battle.build` 的名册人数断言读它；改为可选（写了就断言），44 关保留。

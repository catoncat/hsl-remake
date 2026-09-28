extends RefCounted
## Seed → rules: the compile step of the winfail script interpreter. Reads a battle seed's
## `scripts.winfail` (win / fail / event sections, each a leading condition chain followed
## by a result-action chain), classifies every token against the vocabulary below and
## folds the insert setters into per-status insert records. Pure functions over the seed;
## the loop state machine is WinfailScenarioRules, the interpreters WinfailConditions /
## WinfailActions. Schema: hsl_winfail_script_rules.v1.
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: static-derived docs/evidence_packets/static_reverse/winfail_claim_limits.md
##   rules: provisional
##     (AND-combined condition prefix, fixture only — ids in
##     docs/evidence_packets/static_reverse/winfail_claim_limits.md)

const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")

const RULES_SCHEMA := "hsl_winfail_script_rules.v1"
## TYPE.H level symbols the scripts pass to actSetNextPlayLevelEvent.
const SCRIPT_LEVEL_SYMBOLS := {"gameBigMapLevel": 49}
const DEFAULT_CELL_SIZE := 32
const STATUS_KINDS := ["win", "fail", "event"]
const NARRATION_TOKENS := ["defNoOne", "-3"]

## Condition tokens the interpreter evaluates. tools/hsltools/data/winfail_coverage.py reads these
## constants (one token per line) for the support set and docs/WINFAIL_TOKENS.md, so the
## vocabulary has one source of truth.
const SUPPORTED_CONDITIONS := [
	"actCheckPlayer",  # 所列 id 中至少 num 个不再在场；已绑定但本战未上场的不计，无法解析的 token 永不计
	"actCheckRoundNumber",  # 当前回合 ≥ num
	"actCheckEnemyTotalNumber",  # 在场敌军总数 ≤ num
	"actCheckEnemyNumber",  # code 的在场数（含场景声明的静态敌物件）< num；token 无法解析则不成立
	"actCheckPlayerArrivePos",  # code／serial 指定的在场单位站在像素矩形 (x1,y1)-(x2,y2) 覆盖的任一格
	"actCheckPlayerAttacked",  # 仅攻击行动的完成扫描：本行动攻击者属 attack id（-1＝任意）、受击者之一属 attacked id
	"actCheckSerialPlayerAttacked",  # 仅攻击行动的完成扫描：受击者之一是 id／serial 指定的单位
	"actCheckNotPlayerAttacker",  # 完成扫描：本行动攻击者不属于 id（未攻击的行动也成立）
	"actFALSE",  # 永不成立；以它开头的 status 永不触发
	"actCheckEnemy",  # 与 actCheckPlayer 同一计数：所列 id 至少 num 个不再在场
	"actCheckPlayerHPLow",  # code／serial 指定单位 hp ≤ max(1, max_hp×ratio÷100)（截断）；已倒下按 hp 0；ratio 0 即 hp ≤ 1（不死身复活后的 1 HP 成立）
	"actCheckEventNotExist",  # 所列 event 编号目前都未武装；在结果链中间（WINFAIL037／080 的全部 32 处）作闸门：有一个仍武装即中止该链余下动作
	"actTRUE",  # 恒成立；无条件结果链，status 一武装即触发
	"actCheckPlayerTotalNumber",  # 在场我方（受控＋友军）总数 ≤ num
	"actCheckAnyPlayerArrivePos",  # 任一在场我方单位站在像素矩形覆盖的格
	"actCheckNextSerialNumber",  # 行动计数 0x4c1ad4 的定时器：截止字 0x4c1ad6 为 0 时置为计数＋num，计数到截止成立并清零
	"actCheckPlayerArriveSysPos",  # code／serial 指定单位站在 actRandomSetSysArrivePos 抽中的系统到达点
	"actCheckRoundDisp",  # 当前回合 ≥ number，与 actCheckRoundNumber 同读法
	"actDetectRoundDispDisp",  # 当前回合 ≥ 建 loop 时的回合基线 + num
]
## Condition tokens the result chain itself evaluates when they follow the leading
## prefix. static-derived (hsl01.exe 0x450840 case 0x72 ← 0x453b30 status-object tick):
## actCheckEventNotExist walks its listed codes through 0x44e820 (any of the 20 event
## slots holding the code); one still armed sets +0x8c = -1 and returns 1, which the tick
## reads as the chain's end — the remaining actions never run. None armed advances the
## pc and the chain continues. The PAK uses it only mid-chain (WINFAIL037 events 1–37,
## WINFAIL080 events 0／1).
const CHAIN_GATE_CONDITIONS := ["actCheckEventNotExist"]
## Condition tokens recognised as conditions (they head a status) but not
## evaluated: a status starting with one of them can never fire and is reported.
const KNOWN_UNSUPPORTED_CONDITIONS := []
## Result-action tokens whose effect reaches the loop dictionary or a record the
## PlayLoop consumes (statuses, inserts, departures, messages, carry).
const APPLIED_ACTIONS := [
	"actMessage",  # 推入一句对白（actor token、message id），同 status 内按 id 去重
	"actMessageIfExist",  # check codes 全部在场则推 true id，否则推 false id；0 或空不推
	"actGetItem",  # 向受控角色的队伍背包放入 number 个 item id；无效或背包满则 scenario_error
	"actInsertObject",  # 请求在像素 (x,y) 插入 code 对应的增援；class 由 script_objects obj_Data7 决定
	"actInsertObjectRandomPos",  # 随机槽 pos id 的锚点加位移所在格插入增援，不抽随机数（0x450f2c）
	"actInsertStoryObjectRandomPos",  # 同 actInsertObjectRandomPos，剧情物件版
	"actInsertRandomObject",  # 参数 code／slot／w／h／delay／count：每个对象在全局流抽 w、h、delay 三次（0x450f99），只记 presentation 请求
	"actDeleteRandomPosObject",  # 站在随机槽 id 锚点格上的单位离场（object_delete_requests）
	"actSetPlayerPosToRandom0",  # 以 player id／serial 单位的当前位置作为随机槽 0 的锚点
	"actWalkPrevInsertObject",  # 编译期折进上一条 insert：落点 (x,y) 整除 cell_size 为 walk_cell，附速度
	"actWalkPrevInsertObjectWait",  # 同 actWalkPrevInsertObject，等待版
	"actSetPrevInsertObjectWaitRound",  # 上一名增援的等待回合数，按动作顺序覆盖编译期折叠值
	"actSetPrevInsertObjectAdjustLevel",  # 编译期折进 insert：增援等级调整（range／disp range）
	"actSetPrevInsertObjectFly",  # 编译期折进 insert：增援飞行模式
	"actSetPrevInsertObjectST",  # 编译期折进 insert：增援体力
	"actSetPrevInsertObjectEquip",  # 编译期折进 insert：增援装备（id／part）
	"actInsertEventStatus",  # 武装 event 编号 code
	"actDeleteEventStatus",  # 撤下 event 编号 code
	"actInsertWinStatus",  # 武装 win 编号 code
	"actInsertFailStatus",  # 武装 fail 编号 code
	"actDeleteFailStatus",  # 撤下 fail 编号 code
	"actDeleteWinStatus",  # 撤下 win 编号 code
	"actExecWinFailProcess",  # 链结束后同一扫描再扫一轮（仍只启动一个 event），上限 MAX_PASSES
	"actSetNextPlayLevelEvent",  # 写 next_level_event=[level, event]（gameBigMapLevel=49）并记触发 status
	"actDeletePlayerCode",  # 记 deleted_player_codes（id、mode、解析到的单位）供 carry 注销
	"actKeepPlayerST",  # 记 carry_requests keep_stamina：下一次进关保留余气（CampaignCarryRules）
	"actSetPlayerMode",  # code／serial 单位阵营改为 mode：pmPlayer／pmEnemy／pmNPCPlayer／pmNPCEnemy
	"actSetPlayerExecMode",  # 写单位 player_exec_mode；0 对应原生状态 3，其余 5
	"actPlayerJobUpProcess",  # 按 job_up_targets／templates 对 player id／serial 单位执行原生转职并刷新成长
	"actRandomSetSysArrivePos",  # 从 num 对 (x,y) 中以全局流 rand(num) 抽一个系统到达点，对齐 32 像素
	"actSetPlayerUndead",  # 写单位 undead 标记，mode≠0 为开
	"actSetPlayerFixPos",  # 写 code／serial 单位的守备锚点 ai_home_coord＝(x,y)/32，distance≠0 时写 ai_fixed_radius；单位不瞬移，由固定点行走自己走去（锚点可在图外＝撤退点）
	"actSetPlayerFly",  # 写单位 traversal.flying，mode≠0 为开
	"actChangePrevInsertObjectID",  # 改上一条 insert 的 object_id；尚无 insert 时记 previous_insert_object_id
	"actWaitPlayer",  # 记 wait_requests wait_player：player id／serial 单位（含离场中的）
	"actSetWaitRound",  # 记 wait_requests wait_round：code／serial 单位或同 class 未落地 insert 等 num 回合
	"actDeleteObject",  # code／serial 解析为单位 id，记 departure_requests／departed_unit_ids；离场由 PlayLoop 执行
	"actDeletePosObject",  # 按绝对像素 (x,y)、range、proc code 记 object_delete_requests；表现镜像，不改名册
	"actWalkAndDelete",  # 同 actDeleteObject，另记 presentation 走位请求
	"actWalkAndDeleteWait",  # 同 actWalkAndDelete，等待版
	"actSetDeadMessage",  # 写目标单位的死亡台词字 dead_message（code／serial，msg1<<16|msg2；同链插入的目标由 ScriptActorCreationRules 回放时写）并记 dead_messages[code]=msg1（记录，结果页不再复述：原版两个读者都在死亡时由死者说出）
	"actUseItem",  # code／serial 单位对自身使用背包内的 item id（ItemResolutionRules）
	"actInsertStoryObjectWaitPos",  # pos number 组 (x,y) 中以全局流 rand(number) 抽一点（0x451ecf），记 story_object_wait_requests；defProcPoisonGas 对象当场喷毒（PoisonGasRules）
	"actInsertStoryObjectXRange",  # 自 (x,y) 起横向 x number 格，记 story_object_x_range_requests
	"actDeletePosPlayerXRange",  # 自 (x,y) 起横向 x number 格上、属 proc code 阵营的在场单位离场
	"actSetPlayerNoAttack",  # 写单位 no_attack，mode≠0 为开
	"actSetPlayerWalkShape",  # 写单位 walk_shape_serial 并记 walk_shape_changes／presentation 请求
]
## Town / big-map / campaign tokens: recorded as pending_world_flags for
## WorldScriptActions to apply at hand-off (the over score / flag feed the ending
## dispatch); never executed inside the battle.
const WORLD_FLAG_ACTIONS := [
	"actAddTE",  # 城镇 town id 的事件树在 parent 下加 child 节点
	"actDeleteTE",  # 城镇 town id 的事件树删除 child 节点
	"actSetTownExecEvent",  # 城镇 id 进城即执行 event
	"actSetTownExitExecEvent",  # 城镇 id 出城执行 event
	"actBMSetPointMode",  # 大地图点 id 的显示模式（gameBMShowHidden／Slow／Show）
	"actBMSetTrackMode",  # 大地图路线 id 的显示模式
	"actBMSetPointFlag",  # 大地图点 id 置 flag
	"actBMSetTrackFlag",  # 大地图路线 id 置 flag
	"actBMClearPointFlag",  # 大地图点 id 清 flag
	"actBMClearTrackFlag",  # 大地图路线 id 清 flag
	"actBMSetPointEvent",  # 大地图点 id 绑定 event 与类型 flag（visit／town／general／battle）
	"actBMSetPointEncounterRatio",  # 大地图点 id 的遭遇率
	"actBMSetShowTrackPoint",  # 显示路线端点 id
	"actSetBMWalkToPoint",  # 大地图队伍从 from point 走到 point
	"actSetBMWalkerPlayerID",  # 大地图行走者改用 player id 的形象
	"actAddOverScore",  # 结局分派：id 的 over score 加 score
	"actSetOverFlag",  # 结局分派：置 over flag（gameoverflagFreeEnemy／EnemyJobUp）
]
## Presentation-only tokens: recorded in order as presentation_requests for a
## coordinator; the rules never wait, walk, scroll or play anything.
const PRESENTATION_ACTIONS := [
	"actDelay",  # 演出停顿 delay counter
	"actWalk",  # code／serial 走到像素 (x,y)
	"actWalkWait",  # 同 actWalk，等待走完
	"actWalkDisp",  # code／serial 相对位移走位
	"actWalkDispWait",  # 同 actWalkDisp，等待走完
	"actMoveDispWait",  # code／serial 相对位移瞬移，等待
	"actShowSectionName",  # 显示章节名 section level code
	"actSelectInsertEvent",  # 二至八选一提示；所选 event 由 select_event_status 插入同一循环
	"actWalkToPlayerDisp",  # code／serial 走到另一单位旁的相对位移
	"actWalkToPlayerDispWait",  # 同 actWalkToPlayerDisp，等待走完
	"actScrollBGToPos",  # 镜头滚到像素 (x,y)
	"actScrollBGToObject",  # 镜头滚到 code／serial 单位
	"actScrollBGToPosSpeed",  # 镜头按 speed 滚到像素 (x,y)
	"actSetBGToObject",  # 镜头直接对准 code／serial 单位
	"actSetBGToPos",  # 镜头直接对准像素 (x,y)
	"actPlaySound",  # 播放音效 sound code
	"actPlayMusic",  # 播放乐曲 track id
	"actPlayLevelMusic",  # 恢复本关配乐
	"actChangeShape",  # code／serial 换形象 shape name／number
	"actChangeShapeWait",  # 同 actChangeShape，等待
	"actRestoreShape",  # code／serial 恢复原形象
	"actSetUseShapeWait",  # code／serial 播放使用形象并等待
	"actShowWinFailStatus",  # 显示胜负条件看板
	"actInsertStoryObject",  # 在像素 (x,y) 插入剧情物件 code（演员由 ScriptActorCreationRules 建）
	"actInsertStoryObjectWait",  # 同 actInsertStoryObject，等待；defProcDropLightn 对象当场落雷（DropLightningRules）
	"actInsertShowPosObject",  # 在像素 (x,y) 显示位置标记
	"actDeleteShowPosObject",  # 删除位置标记
	"actDarkScreen",  # 画面变暗
	"actDeleteDarkScreen",  # 撤销变暗
	"actEarthQuake",  # 地震抖屏 delay
	"actSetWalkSoundMode",  # 走位脚步声模式
	"actWaitPrevInsertPlayer",  # 等待上一名插入的剧情角色就位
	"actEnterStorageWindow",  # 进入仓库窗口
	"actSetDoublePageMode",  # 双页对话模式 mode
	"actInsertLevelUpStar",  # 升级星光特效与音效 sound id（记 level_up_star_requests）
	"actPlayMovie",  # 播放影片；140 为结局影片（记 movie_requests）
]
## Claim-limit ids; the text of each boundary and its evidence tier live in
## docs/evidence_packets/static_reverse/winfail_claim_limits.md (same order).
const CLAIM_LIMIT_IDS := [
	"script_structure_not_timing",
	"and_chain_status_fire",
	"enemy_number_checks",
	"player_enemy_fallen_checks",
	"status_consumed_rearm",
	"token_resolution",
	"player_attacked_insert_object",
	"attacked_contexts",
	"player_job_up_process",
	"player_mode_undead",
	"undead_revive_at_one_hp",
	"fix_pos",
	"fly_prev_insert",
	"exec_mode",
	"random_sys_arrive_pos",
	"recorded_only_tokens",
	"player_total_arrive_counts",
	"round_display",
	"delete_pos_x_range",
	"level_up_star_movie",
]


## ---------------------------------------------------------------------------
## Seed → rules

static func action_supported(name: String) -> bool:
	return APPLIED_ACTIONS.find(name) != -1 or WORLD_FLAG_ACTIONS.find(name) != -1 or PRESENTATION_ACTIONS.find(name) != -1


static func canonical_action(name: String) -> String:
	# WINFAIL002 contains actMEssage. Resolve only existing opcode names; unknown
	# commands and the source arguments remain unchanged and explicitly unsupported.
	for candidate in SUPPORTED_CONDITIONS + KNOWN_UNSUPPORTED_CONDITIONS + APPLIED_ACTIONS + WORLD_FLAG_ACTIONS + PRESENTATION_ACTIONS:
		if name.to_lower() == str(candidate).to_lower(): return str(candidate)
	return name


static func seed_has_winfail(seed: Dictionary) -> bool:
	if str(seed.get("schema", "")) != "hsl_battle_seed.v1":
		return false
	var winfail: Variant = (seed.get("scripts", {}) as Dictionary).get("winfail")
	if typeof(winfail) != TYPE_DICTIONARY:
		return false
	return not (winfail as Dictionary).get("sections", []).is_empty()


static func rules_from_seed(seed: Dictionary, cell_size: int = DEFAULT_CELL_SIZE) -> Dictionary:
	var statuses := {"win": [], "fail": [], "event": []}
	var unsupported: Array = []
	var token_counts := {}
	var section_order: Array = []
	var winfail: Dictionary = (seed.get("scripts", {}) as Dictionary).get("winfail", {}) if typeof((seed.get("scripts", {}) as Dictionary).get("winfail")) == TYPE_DICTIONARY else {}
	for section_value in winfail.get("sections", []):
		if typeof(section_value) != TYPE_DICTIONARY:
			continue
		var section: Dictionary = section_value
		var kind := str(section.get("name", ""))
		if STATUS_KINDS.find(kind) == -1:
			continue
		var status := _compile_section(seed, section, kind, cell_size, token_counts, unsupported)
		(statuses[kind] as Array).append(status)
		section_order.append(status["key"])
	unsupported.sort()
	var initial := _initial_statuses(seed)
	return {
		"schema": RULES_SCHEMA,
		"source_level": int(seed.get("level", 0)),
		"cell_size": cell_size,
		"statuses": statuses,
		"section_order": section_order,
		"initial_statuses": initial["statuses"],
		"initial_status_source": initial["source"],
		"dead_messages": _story_dead_messages(seed),
		"story_object_terrain": _story_object_terrain(seed),
		"poison_gas_objects": _process_shape_counts(seed, "defProcPoisonGas"),
		"drop_lightning_objects": _process_shape_counts(seed, "defProcDropLightn"),
		"token_counts": token_counts,
		"unsupported_tokens": unsupported,
		"fully_supported": unsupported.is_empty(),
		"claim_limits": CLAIM_LIMIT_IDS.duplicate(),
	}


## One win／fail／event section compiled to its status: the condition prefix, the action
## chain and the inserts its follow-up actions refine; counts tokens and records
## unsupported names into `token_counts`／`unsupported`.
static func _compile_section(seed: Dictionary, section: Dictionary, kind: String, cell_size: int, token_counts: Dictionary, unsupported: Array) -> Dictionary:
	var codes: Array = section.get("codes", [])
	var code := int(str(codes[0])) if not codes.is_empty() else 0
	var status := {
		"kind": kind,
		"code": code,
		"key": "%s_%d" % [kind, code],
		"result_message": _result_message(section.get("messages", [])),
		"conditions": [],
		"actions": [],
		"unsupported": [],
		"inserts": [],
	}
	var in_prefix := true
	var pending_insert: Dictionary = {}
	for action_value in section.get("actions", []):
		if typeof(action_value) != TYPE_DICTIONARY:
			continue
		for command_value in (action_value as Dictionary).get("chain", []):
			if typeof(command_value) != TYPE_DICTIONARY:
				continue
			var command: Dictionary = command_value
			var name := canonical_action(str(command.get("name", "")))
			var args: Array = string_args(command.get("args", []))
			if name == "":
				continue
			token_counts[name] = int(token_counts.get(name, 0)) + 1
			var is_condition := SUPPORTED_CONDITIONS.find(name) != -1 or KNOWN_UNSUPPORTED_CONDITIONS.find(name) != -1
			if in_prefix and is_condition:
				(status["conditions"] as Array).append({"name": name, "args": args, "supported": SUPPORTED_CONDITIONS.find(name) != -1})
				if SUPPORTED_CONDITIONS.find(name) == -1:
					_append_unique(status["unsupported"], name)
					_append_unique(unsupported, name)
				continue
			in_prefix = false
			var record := {"name": name, "args": args, "supported": action_supported(name) or CHAIN_GATE_CONDITIONS.has(name)}
			if CHAIN_GATE_CONDITIONS.has(name):
				record["chain_gate"] = true
			(status["actions"] as Array).append(record)
			if not record["supported"]:
				_append_unique(status["unsupported"], name)
				_append_unique(unsupported, name)
			pending_insert = _record_insert_action(seed, status, pending_insert, name, args, cell_size)
	return status


## An insert action starts a new pending insert (appended to the status); the
## actSetPrevInsertObject*／actWalkPrevInsertObject* actions refine the pending one.
## Returns the pending insert after `name`.
static func _record_insert_action(seed: Dictionary, status: Dictionary, pending_insert: Dictionary, name: String, args: Array, cell_size: int) -> Dictionary:
	match name:
		"actInsertObject", "actInsertObjectRandomPos", "actInsertStoryObjectRandomPos":
			pending_insert = {
				"object_symbol": arg(args, 0),
				"class_id": _insert_class_id(seed, arg(args, 0)),
				"insert_xy": [int(arg(args, 1)), int(arg(args, 2))] if args.size() >= 3 else [],
				"random_position": name != "actInsertObject",
				"position_slot": int_arg(args, 3) if name != "actInsertObject" else 0,
				"walk_xy": [],
				"walk_cell": [],
				"speed_arg": 0,
				"wait_round": 0,
				"adjust_level": [],
				"fly": -1,
				"stamina": -1,
				"equip": [],
			}
			(status["inserts"] as Array).append(pending_insert)
		"actWalkPrevInsertObject", "actWalkPrevInsertObjectWait":
			if not pending_insert.is_empty() and args.size() >= 2:
				pending_insert["walk_xy"] = [int(arg(args, 0)), int(arg(args, 1))]
				pending_insert["walk_cell"] = [int(arg(args, 0)) / cell_size, int(arg(args, 1)) / cell_size]
				pending_insert["speed_arg"] = int(arg(args, 2))
		"actSetPrevInsertObjectWaitRound":
			if not pending_insert.is_empty() and args.size() >= 1:
				pending_insert["wait_round"] = int(arg(args, 0))
		"actSetPrevInsertObjectAdjustLevel":
			if not pending_insert.is_empty() and args.size() >= 2:
				pending_insert["adjust_level"] = [int(arg(args, 0)), int(arg(args, 1))]
		"actSetPrevInsertObjectFly":
			if not pending_insert.is_empty() and args.size() >= 1:
				pending_insert["fly"] = int(arg(args, 0))
		"actSetPrevInsertObjectST":
			if not pending_insert.is_empty() and args.size() >= 1:
				pending_insert["stamina"] = int(arg(args, 0))
		"actSetPrevInsertObjectEquip":
			if not pending_insert.is_empty() and args.size() >= 2:
				(pending_insert["equip"] as Array).append([int(arg(args, 0)), int(arg(args, 1))])
	return pending_insert


static func insert_walk_cells(rules: Dictionary) -> Array:
	## Script landing cells in section order, de-duplicated, as Vector2i (the
	## actWalkPrevInsertObject targets ScriptActorCreationRules walks each insert to).
	var cells: Array = []
	for status in all_statuses(rules):
		for insert_value in (status as Dictionary).get("inserts", []):
			var cell: Array = (insert_value as Dictionary).get("walk_cell", [])
			if cell.size() == 2:
				var value := Vector2i(int(cell[0]), int(cell[1]))
				if cells.find(value) == -1:
					cells.append(value)
	return cells


static func _insert_class_id(seed: Dictionary, symbol: String) -> String:
	## Resource-derived join: the seed's script_objects carry the header symbol
	## → object → obj_Data7 (actor number). No name heuristics.
	if symbol == "":
		return ""
	for object_value in seed.get("script_objects", []):
		if typeof(object_value) != TYPE_DICTIONARY:
			continue
		var object: Dictionary = object_value
		if str(object.get("symbol", "")) != symbol:
			continue
		var fields: Dictionary = object.get("object_data_fields", {})
		var actor := str(fields.get("obj_Data7", ""))
		if actor.is_valid_int():
			return "Enemy%03d" % int(actor)
		var sid := str(fields.get("obj_Data6", ""))
		if sid.begins_with("SID_ENEMY") and sid.trim_prefix("SID_ENEMY").is_valid_int():
			return "Enemy%03d" % int(sid.trim_prefix("SID_ENEMY"))
	return ""


static func _initial_statuses(seed: Dictionary) -> Dictionary:
	## The STORY script arms the initial win/fail/event statuses
	## (actInsert*Status / actDelete*Status in order). Without them nothing is
	## armed and the source is reported instead of guessed.
	var statuses := {"win": [], "fail": [], "event": []}
	var found := false
	var story: Variant = (seed.get("scripts", {}) as Dictionary).get("story")
	if typeof(story) == TYPE_DICTIONARY:
		for section_value in (story as Dictionary).get("sections", []):
			if typeof(section_value) != TYPE_DICTIONARY:
				continue
			for action_value in (section_value as Dictionary).get("actions", []):
				if typeof(action_value) != TYPE_DICTIONARY:
					continue
				for command_value in (action_value as Dictionary).get("chain", []):
					if typeof(command_value) != TYPE_DICTIONARY:
						continue
					var command: Dictionary = command_value
					var name := str(command.get("name", ""))
					var args: Array = string_args(command.get("args", []))
					if args.is_empty():
						continue
					var kind := status_kind_of(name)
					if kind == "":
						continue
					found = true
					# Same slot rules as the chain actions (0x44e7b0 first free slot, no
					# duplicate check; 0x44e8d0 frees the last copy); provisional: a hole a
					# STORY delete leaves is compacted instead of kept for the next insert.
					if name.begins_with("actInsert"):
						if (statuses[kind] as Array).size() < int(STATUS_SLOT_COUNTS[kind]):
							(statuses[kind] as Array).append(int(arg(args, 0)))
					elif name.begins_with("actDelete"):
						var last := (statuses[kind] as Array).rfind(int(arg(args, 0)))
						if last != -1:
							(statuses[kind] as Array).remove_at(last)
	return {"statuses": statuses, "source": "story_script" if found else "none"}


static func _story_object_terrain(seed: Dictionary) -> Dictionary:
	## Resource-derived join like _insert_class_id: script object symbol → the map edit
	## its obj_Data9 kind makes when inserted (TerrainEditRules.EDITS_BY_OBJECT_KIND).
	var edits := {}
	for object_value in seed.get("script_objects", []):
		if typeof(object_value) != TYPE_DICTIONARY:
			continue
		var object: Dictionary = object_value
		var kind := str((object.get("object_data_fields", {}) as Dictionary).get("obj_Data9", ""))
		if TerrainEditRules.EDITS_BY_OBJECT_KIND.has(kind):
			edits[str(object.get("symbol", ""))] = (TerrainEditRules.EDITS_BY_OBJECT_KIND[kind] as Dictionary).duplicate()
	return edits


static func _process_shape_counts(seed: Dictionary, process: String) -> Dictionary:
	## Resource-derived join: script object symbol → its obj_Shape_Number for the objects whose
	## OBS process is `process` (defProcPoisonGas PROCESS.DEF 71 → 0x43c7c0, original_poison_gas.md;
	## defProcDropLightn 67 → 0x43ca70, original_drop_lightning.md).
	var result := {}
	for object_value in seed.get("script_objects", []):
		if typeof(object_value) != TYPE_DICTIONARY or str(object_value.get("object_process", "")) != process:
			continue
		var shapes: Variant = object_value.get("shape_number")
		result[str(object_value.get("symbol", ""))] = int(shapes) if shapes != null else 0
	return result


static func _story_dead_messages(seed: Dictionary) -> Dictionary:
	var result := {}
	var story: Variant = (seed.get("scripts", {}) as Dictionary).get("story")
	if typeof(story) != TYPE_DICTIONARY:
		return result
	for section_value in (story as Dictionary).get("sections", []):
		if typeof(section_value) != TYPE_DICTIONARY:
			continue
		for action_value in (section_value as Dictionary).get("actions", []):
			if typeof(action_value) != TYPE_DICTIONARY:
				continue
			for command_value in (action_value as Dictionary).get("chain", []):
				if typeof(command_value) != TYPE_DICTIONARY:
					continue
				var command: Dictionary = command_value
				var args: Array = string_args(command.get("args", []))
				if str(command.get("name", "")) == "actSetDeadMessage" and args.size() >= 3:
					result[arg(args, 0)] = arg(args, 2)
	return result


static func status_kind_of(name: String) -> String:
	match name:
		"actInsertWinStatus", "actDeleteWinStatus":
			return "win"
		"actInsertFailStatus", "actDeleteFailStatus":
			return "fail"
		"actInsertEventStatus", "actDeleteEventStatus":
			return "event"
		_:
			return ""


static func first_next_level_event(rules: Dictionary) -> Array:
	## Campaign hand-off default: the first win status carrying actSetNextPlayLevelEvent;
	## a fired status with its own token overwrites this in the loop.
	for status_value in rules["statuses"]["win"]:
		for action_value in (status_value as Dictionary).get("actions", []):
			var action: Dictionary = action_value
			if str(action["name"]) == "actSetNextPlayLevelEvent" and (action["args"] as Array).size() >= 2:
				return [level_arg(arg(action["args"], 0)), level_arg(arg(action["args"], 1))]
	return []


## Level arguments are numbers or the TYPE.H symbol gameBigMapLevel (49): "N,
## gameBigMapLevel" returns to the big map standing at point N (script reading
## recorded by tools/hsltools/data/big_map_flow.py).


static func level_arg(value: Variant) -> int:
	var text := str(value).strip_edges()
	return SCRIPT_LEVEL_SYMBOLS[text] if SCRIPT_LEVEL_SYMBOLS.has(text) else int(text)


static func all_statuses(rules: Dictionary) -> Array:
	var result: Array = []
	for key in rules.get("section_order", []):
		var status := status_by_key(rules, str(key))
		if not status.is_empty():
			result.append(status)
	return result


static func status_by_key(rules: Dictionary, key: String) -> Dictionary:
	for kind in STATUS_KINDS:
		for status_value in (rules.get("statuses", {}) as Dictionary).get(kind, []):
			if str((status_value as Dictionary).get("key", "")) == key:
				return status_value
	return {}


static func _result_message(messages: Array) -> Dictionary:
	if messages.is_empty():
		return {}
	var parts := str(messages[0]).split(",")
	if parts.size() < 2:
		return {}
	return {"actor_token": parts[0].strip_edges(), "message_id": parts[1].strip_edges()}


static func string_args(values: Variant) -> Array:
	var result: Array = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value in values:
		result.append(str(value).strip_edges())
	return result


static func arg(args: Array, index: int, default: String = "") -> String:
	## Script argument `index` as text; `default` when the chain is shorter. `int(arg(...))`
	## keeps GDScript's digit-scraping int() for sites that never validated the literal.
	return str(args[index]) if index < args.size() else default


static func int_arg(args: Array, index: int, default: int = 0) -> int:
	## Script argument `index` when it is an integer literal; `default` when missing or not
	## an integer (same contract as TownEventRules.int_arg).
	var value := arg(args, index)
	return int(value) if value.is_valid_int() else default


static func zone_cells(zone_px: Array, cell_size: int) -> Array:
	var cells: Array = []
	if zone_px.size() < 4 or cell_size <= 0:
		return cells
	var x0: int = mini(int(zone_px[0]), int(zone_px[2])) / cell_size
	var x1: int = maxi(int(zone_px[0]), int(zone_px[2])) / cell_size
	var y0: int = mini(int(zone_px[1]), int(zone_px[3])) / cell_size
	var y1: int = maxi(int(zone_px[1]), int(zone_px[3])) / cell_size
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			cells.append([x, y])
	return cells


## static-derived (hsl01.exe 0x44ebf0／0x44ecb0／0x44ed70, 0x44e7b0, 0x44e8d0): the
## original keeps 10 win, 10 fail and 20 event slots (stride 0xb4, code -1 = free).
## actInsert*Status writes the code into the first free slot without a duplicate check,
## actDelete*Status frees the last slot holding the code, and a scan walks the slots in
## index order and disarms the slot that fires. `<kind>_statuses` stays the compacted
## view (slot order, duplicates kept); the slots with their holes live in
## winfail_runtime.status_slots and are rebuilt from the view when the two disagree.
const STATUS_SLOT_COUNTS := {"win": 10, "fail": 10, "event": 20}


static func status_slots(battle: Dictionary, kind: String) -> Array:
	var armed: Array = battle.get("%s_statuses" % kind, [])
	var runtime: Variant = battle.get("winfail_runtime")
	if typeof(runtime) == TYPE_DICTIONARY:
		var slots: Variant = ((runtime as Dictionary).get("status_slots", {}) as Dictionary).get(kind)
		if slots is Array and _compacted(slots) == _ints(armed):
			return (slots as Array).duplicate()
	return _ints(armed)


static func status_slot_insert(battle: Dictionary, kind: String, code: int) -> void:
	var slots := status_slots(battle, kind)
	var hole := slots.find(-1)
	if hole != -1:
		slots[hole] = code
	elif slots.size() < int(STATUS_SLOT_COUNTS.get(kind, 20)):
		slots.append(code)
	_store_slots(battle, kind, slots)


static func status_slot_delete(battle: Dictionary, kind: String, code: int) -> void:
	var slots := status_slots(battle, kind)
	var index := slots.rfind(code)
	if index != -1:
		slots[index] = -1
		_store_slots(battle, kind, slots)


static func status_slot_disarm(battle: Dictionary, kind: String, code: int) -> void:
	var slots := status_slots(battle, kind)
	var index := slots.find(code)
	if index != -1:
		slots[index] = -1
		_store_slots(battle, kind, slots)


static func _store_slots(battle: Dictionary, kind: String, slots: Array) -> void:
	battle["%s_statuses" % kind] = _compacted(slots)
	var runtime: Variant = battle.get("winfail_runtime")
	if typeof(runtime) == TYPE_DICTIONARY:
		var all: Dictionary = (runtime as Dictionary).get("status_slots", {})
		all[kind] = slots
		(runtime as Dictionary)["status_slots"] = all


static func _compacted(slots: Array) -> Array:
	var result: Array = []
	for value in slots:
		if int(value) != -1:
			result.append(int(value))
	return result


static func _ints(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(int(value))
	return result


static func without(values: Array, code: int) -> Array:
	var result: Array = []
	for value in values:
		if int(value) != code:
			result.append(int(value))
	return result


static func _append_unique(values: Array, value: String) -> void:
	if values.find(value) == -1:
		values.append(value)

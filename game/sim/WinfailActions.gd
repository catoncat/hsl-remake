extends RefCounted
## Action step of the winfail script interpreter: applies a fired status' result chain to
## the PlayLoop dictionary (statuses, inserts, departures, messages, carry, actor state)
## and records the requests the PlayLoop / presentation consume in `winfail_runtime`.
## It owns no state of its own. Rule compilation is WinfailCompiler, condition reads
## WinfailConditions, the outcome state machine WinfailScenarioRules.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_check_targets.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_fixpos_fly_prev_insert.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_story_object_terrain.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_exec_mode_sys_arrive.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_use_item_no_attack.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_drop_lightning.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_random_position.md
##   rules: provisional
##     (insert lifecycle, wait／fly／exec-mode readings — ids in
##     docs/evidence_packets/static_reverse/winfail_claim_limits.md)

const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const ItemResolutionRules = preload("res://game/sim/ItemResolutionRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
const JobUpRules = preload("res://game/sim/JobUpRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const PoisonGasRules = preload("res://game/sim/PoisonGasRules.gd")
const DropLightningRules = preload("res://game/sim/DropLightningRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")

## actSetPlayerMode (0x450710): exactly pmPlayer makes the object player-driven (process 3),
## every other mode AI-driven (process 5); the remake role follows that, friendly_ai when the
## side keeps the pmPlayer bit (pmNPCPlayer, pmPlayerEnemy). The mode itself is kept on the
## unit as player_mode for ActorRoleRules.side_mask. pmMagicAttack (0x870000, the level-37
## gems) keeps the pmPlayer bit too; its pmALL side is read by ActorRoleRules.player_range_selectable.
const PLAYER_MODE_ROLES := {
	0x10000: "player_controlled",
	0x20000: "enemy_ai",
	0x30000: "friendly_ai",
	0x40000: "enemy_ai",
	0x50000: "friendly_ai",
	0x60000: "enemy_ai",
	0x870000: "friendly_ai",
}


## Token → handler table of the result chain (apply_actions). Every handler takes the chain
## context `c` (next, runtime, key, message_key, status, fired, insert_index, rerun), the token
## name and its args. A token missing here takes _act_unlisted: WinfailCompiler's world-flag and
## presentation vocabularies are recorded for their consumers, anything else as unsupported.
static var ACTION_HANDLERS := {
	"actMessage": _act_message,
	"actMessageIfExist": _act_message_if_exist,
	"actGetItem": _act_get_item,
	"actInsertObject": _act_insert_object,
	"actInsertObjectRandomPos": _act_insert_object,
	"actInsertStoryObjectRandomPos": _act_insert_object,
	"actInsertRandomObject": _act_insert_random_object,
	"actSetPlayerPosToRandom0": _act_set_player_pos_to_random0,
	"actDeleteRandomPosObject": _act_delete_random_pos_object,
	"actSetDoublePageMode": _act_set_double_page_mode,
	"actSetPrevInsertObjectWaitRound": _act_set_prev_insert_object_wait_round,
	"actWalkPrevInsertObject": _act_folded_into_insert,
	"actWalkPrevInsertObjectWait": _act_folded_into_insert,
	"actSetPrevInsertObjectAdjustLevel": _act_folded_into_insert,
	"actSetPrevInsertObjectFly": _act_folded_into_insert,
	"actSetPrevInsertObjectST": _act_folded_into_insert,
	"actSetPrevInsertObjectEquip": _act_folded_into_insert,
	"actInsertEventStatus": _act_insert_status,
	"actInsertWinStatus": _act_insert_status,
	"actInsertFailStatus": _act_insert_status,
	"actDeleteEventStatus": _act_delete_status,
	"actDeleteWinStatus": _act_delete_status,
	"actDeleteFailStatus": _act_delete_status,
	"actSetNextPlayLevelEvent": _act_set_next_play_level_event,
	"actSetPlayerMode": _act_set_player_mode,
	"actPlayerJobUpProcess": _act_player_job_up_process,
	"actSetPlayerWalkShape": _act_set_player_walk_shape,
	"actSetPlayerExecMode": _act_set_player_exec_mode,
	"actRandomSetSysArrivePos": _act_random_set_sys_arrive_pos,
	"actKeepPlayerST": _act_keep_player_st,
	"actDeletePlayerCode": _act_delete_player_code,
	"actExecWinFailProcess": _act_exec_win_fail_process,
	"actSetPlayerUndead": _act_set_player_undead,
	"actSetPlayerFixPos": _act_set_player_fix_pos,
	"actSetPlayerFly": _act_set_player_fly,
	"actSetPlayerNoAttack": _act_set_player_no_attack,
	"actUseItem": _act_use_item,
	"actInsertStoryObjectWaitPos": _act_insert_story_object_wait_pos,
	"actInsertStoryObjectXRange": _act_insert_story_object_x_range,
	"actInsertStoryObject": _act_insert_story_object,
	"actInsertStoryObjectWait": _act_insert_story_object_wait,
	"actDeletePosPlayerXRange": _act_delete_pos_player_x_range,
	"actInsertLevelUpStar": _act_insert_level_up_star,
	"actPlayMovie": _act_play_movie,
	"actChangePrevInsertObjectID": _act_change_prev_insert_object_id,
	"actWaitPlayer": _act_wait_player,
	"actSetWaitRound": _act_set_wait_round,
	"actDeleteObject": _act_delete_object,
	"actDeletePosObject": _act_delete_object,
	"actWalkAndDelete": _act_delete_object,
	"actWalkAndDeleteWait": _act_delete_object,
	"actSetDeadMessage": _act_set_dead_message,
}


## ---------------------------------------------------------------------------
## Result chain

static func apply_actions(next: Dictionary, status: Dictionary, context: String, dialogue_key: String = "") -> bool:
	## Applies a fired status' result chain to the loop; returns true when the
	## chain asked for an immediate re-evaluation (actExecWinFailProcess).
	var runtime: Dictionary = next["winfail_runtime"]
	var key := str(status["key"])
	var message_key := dialogue_key if dialogue_key != "" else key
	var fired: Array = runtime.get("fired", [])
	fired.append({"key": key, "turn": int(next.get("turn", 1)), "context": context})
	runtime["fired"] = fired
	var event_log: Array = next.get("event_log", [])
	if event_log.find(key) == -1:
		event_log.append(key)
	next["event_log"] = event_log
	var c := {"next": next, "runtime": runtime, "key": key, "message_key": message_key, "status": status, "fired": fired, "insert_index": 0, "rerun": false}
	var actions: Array = status.get("actions", [])
	for action_index in range(actions.size()):
		var action: Dictionary = actions[action_index]
		var name := str(action["name"])
		var args: Array = action["args"]
		if bool(action.get("chain_gate", false)):
			# 0x450840 case 0x72 inside the status-object tick 0x453b30: a listed event
			# still armed ends the chain here (WinfailCompiler.CHAIN_GATE_CONDITIONS). The
			# stop is recorded on the firing so actor creation and the cutscene replay the
			# same prefix of the chain; a rescan already requested stays requested (the tick
			# reads 0x4c1d44 whichever way the chain ended).
			if not WinfailConditions.condition_holds(next, name, args, context):
				(fired.back() as Dictionary)["chain_stop_index"] = action_index + (status.get("conditions", []) as Array).size()
				break
			continue
		var handler: Callable = ACTION_HANDLERS.get(name, Callable())
		if handler.is_valid():
			handler.call(c, name, args)
		else:
			_act_unlisted(c, name, args)
	next["last_action"] = "Event hook: winfail%03d %s fired (%s)." % [int(next["winfail_script_rules"].get("source_level", 0)), key, context]
	return bool(c["rerun"])


## Index of this chain's firing record (the entry apply_actions appended to runtime.fired).
static func _firing(c: Dictionary) -> int:
	return (c["fired"] as Array).size() - 1


static func _act_message(c: Dictionary, _name: String, args: Array) -> void:
	if args.size() >= 3:
		_push_dialogue(c["runtime"], c["message_key"], _arg(args, 0), _arg(args, 2))


static func _act_message_if_exist(c: Dictionary, _name: String, args: Array) -> void:
	# [player code][serial][true id][false id][check number][check codes...]
	if args.size() >= 5:
		var count := int(_arg(args, 4))
		var all_alive := true
		for offset in range(count):
			var index := 5 + offset
			if index >= args.size() or WinfailConditions.alive_units_for_token(c["next"], _arg(args, index)).is_empty():
				all_alive = false
				break
		var chosen := _arg(args, 2) if all_alive else _arg(args, 3)
		if chosen != "" and chosen != "0":
			_push_dialogue(c["runtime"], c["message_key"], _arg(args, 0), chosen)


static func _act_get_item(c: Dictionary, _name: String, args: Array) -> void:
	# 0x450840 case 0x55 writes the same party item store used by
	# ordinary treasure/carry. The controlled actor's eight slots are
	# the remake's single party inventory representation.
	_apply_item_grant(c["next"], c["runtime"], c["key"], args, _firing(c))


## actInsertObject／actInsertObjectRandomPos／actInsertStoryObjectRandomPos: the next parsed
## insert record (status.inserts, in chain order) is queued on runtime.inserts.
static func _act_insert_object(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	var key: String = c["key"]
	var inserts: Array = (c["status"] as Dictionary).get("inserts", [])
	var insert_index := int(c["insert_index"])
	var pending_insert: Dictionary = (inserts[insert_index] as Dictionary).duplicate(true) if insert_index < inserts.size() else {}
	c["insert_index"] = insert_index + 1
	if pending_insert.is_empty():
		return
	pending_insert["key"] = key
	pending_insert["firing_index"] = _firing(c)
	if name != "actInsertObject":
		var placed := _slot_position(next, int(pending_insert.get("position_slot", 0)), Vector2i(int(_arg(args, 1)), int(_arg(args, 2))))
		if not placed["ok"]:
			record_unresolved(runtime, name, key)
			return
		pending_insert["position_xy"] = placed["pixel"]
		(runtime["presentation_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate(), "position": placed["pixel"], "coord": placed["coord"]})
	# Apply wait setters in action order rather than the parser's final fold.
	pending_insert["wait_round_set"] = false
	pending_insert["wait_round"] = 0
	(runtime["inserts"] as Array).append(pending_insert)
	var class_id := str(pending_insert.get("class_id", ""))
	if class_id == "":
		record_unresolved(runtime, str(pending_insert.get("object_symbol", "")), key)
	else:
		var target: Dictionary = runtime["spawn_target"]
		target[class_id] = int(target.get(class_id, 0)) + 1


static func _act_insert_random_object(c: Dictionary, _name: String, args: Array) -> void:
	_record_random_effect(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_pos_to_random0(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	var key: String = c["key"]
	var ids := WinfailConditions.units_for_token(next, _arg(args, 0), _int_arg(args, 1))
	if ids.is_empty():
		record_unresolved(runtime, name, key)
		return
	var actor := WinfailConditions.unit(next, str(ids[0]))
	var coord: Vector2i = actor.get("coord", Vector2i.ZERO)
	(runtime["random_position_slots"] as Dictionary)["0"] = [coord.x * WinfailCompiler.DEFAULT_CELL_SIZE, coord.y * WinfailCompiler.DEFAULT_CELL_SIZE]
	(runtime["presentation_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate(), "position_slot": 0, "coord": coord, "unit_ids": ids.duplicate()})


static func _act_delete_random_pos_object(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	var key: String = c["key"]
	var slot_id := _int_arg(args, 0)
	var slot: Array = (runtime.get("random_position_slots", {}) as Dictionary).get(str(slot_id), [])
	var deleted: Array = []
	if slot.size() == 2:
		var target_coord := Vector2i(floori(float(slot[0]) / WinfailCompiler.DEFAULT_CELL_SIZE), floori(float(slot[1]) / WinfailCompiler.DEFAULT_CELL_SIZE))
		for unit in next.get("units", []):
			if typeof(unit) == TYPE_DICTIONARY and unit.get("coord", Vector2i(-1, -1)) == target_coord and not bool(unit.get("defeated", false)):
				deleted.append(str(unit.get("id", "")))
	(runtime["object_delete_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate(), "position": slot.duplicate(), "position_slot": slot_id, "unit_ids": deleted.duplicate()})
	for unit_id in deleted:
		if (runtime["departed_unit_ids"] as Array).find(unit_id) == -1: (runtime["departed_unit_ids"] as Array).append(unit_id)


static func _act_set_double_page_mode(c: Dictionary, name: String, args: Array) -> void:
	(c["runtime"]["presentation_requests"] as Array).append({"key": c["key"], "name": name, "args": args.duplicate(), "mode": _int_arg(args, 0)})


static func _act_set_prev_insert_object_wait_round(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	var previous: int = runtime["inserts"].size() - 1
	var previous_id := str(runtime["inserts"][previous].get("unit_id", "")) if previous >= 0 else str(next.get("script_wait_source", {}).get("previous_insert_unit_id", ""))
	_record_wait(next, c["key"], name, args, [previous_id] if previous_id != "" else [], -1 if previous_id != "" else previous, _firing(c))


## actWalkPrevInsertObject(Wait)／actSetPrevInsertObjectAdjustLevel／Fly／ST／Equip.
static func _act_folded_into_insert(_c: Dictionary, _name: String, _args: Array) -> void:
	pass  # folded into the insert record at parse time


static func _act_insert_status(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	if args.size() >= 1:
		var kind := WinfailCompiler.status_kind_of(name)
		var list: Array = next.get("%s_statuses" % kind, []).duplicate()
		if list.find(int(_arg(args, 0))) == -1:
			list.append(int(_arg(args, 0)))
		next["%s_statuses" % kind] = list


static func _act_delete_status(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	if args.size() >= 1:
		var kind := WinfailCompiler.status_kind_of(name)
		next["%s_statuses" % kind] = WinfailCompiler.without(next.get("%s_statuses" % kind, []), int(_arg(args, 0)))


static func _act_set_next_play_level_event(c: Dictionary, _name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	if args.size() >= 2:
		next["next_level_event"] = [WinfailCompiler.level_arg(_arg(args, 0)), WinfailCompiler.level_arg(_arg(args, 1))]
		next["next_level_event_status"] = c["key"]


static func _act_set_player_mode(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_mode(c["next"], c["runtime"], c["key"], args)


static func _act_player_job_up_process(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_job_up(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_walk_shape(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_walk_shape(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_exec_mode(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_exec_mode(c["next"], c["runtime"], c["key"], args)


static func _act_random_set_sys_arrive_pos(c: Dictionary, _name: String, args: Array) -> void:
	_apply_random_system_arrival_position(c["next"], c["runtime"], c["key"], args, _firing(c))


static func _act_keep_player_st(c: Dictionary, _name: String, _args: Array) -> void:
	(c["runtime"]["carry_requests"] as Array).append({"key": c["key"], "kind": "keep_stamina"})


static func _act_delete_player_code(c: Dictionary, _name: String, args: Array) -> void:
	(c["runtime"]["deleted_player_codes"] as Array).append({"key": c["key"], "actor_token": _arg(args, 0), "mode": int(_arg(args, 1)), "unit_ids": WinfailConditions.units_for_token(c["next"], _arg(args, 0))})


static func _act_exec_win_fail_process(c: Dictionary, _name: String, _args: Array) -> void:
	c["rerun"] = true


static func _act_set_player_undead(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_undead(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_fix_pos(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_fix_pos(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_fly(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_fly(c["next"], c["runtime"], c["key"], args)


static func _act_set_player_no_attack(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_no_attack(c["next"], c["runtime"], c["key"], args)


static func _act_use_item(c: Dictionary, _name: String, args: Array) -> void:
	_apply_item_use(c["next"], c["runtime"], c["key"], args, _firing(c))


static func _act_insert_story_object_wait_pos(c: Dictionary, _name: String, args: Array) -> void:
	_apply_story_object_wait_pos(c["next"], c["runtime"], c["key"], args, _firing(c))


static func _act_insert_story_object_x_range(c: Dictionary, _name: String, args: Array) -> void:
	_apply_story_object_x_range(c["next"], c["runtime"], c["key"], args, _firing(c))


static func _act_insert_story_object(c: Dictionary, name: String, args: Array) -> void:
	(c["runtime"]["presentation_requests"] as Array).append({"key": c["key"], "name": name, "args": args.duplicate()})
	_apply_story_object_terrain(c["next"], c["key"], args)


static func _act_insert_story_object_wait(c: Dictionary, name: String, args: Array) -> void:
	var request := {"key": c["key"], "name": name, "args": args.duplicate()}
	_apply_drop_lightning(c["next"], request, _arg(args, 0))
	(c["runtime"]["presentation_requests"] as Array).append(request)


static func _act_delete_pos_player_x_range(c: Dictionary, _name: String, args: Array) -> void:
	_apply_player_x_range_delete(c["next"], c["runtime"], c["key"], args, _firing(c))


static func _act_insert_level_up_star(c: Dictionary, name: String, args: Array) -> void:
	(c["runtime"]["level_up_star_requests"] as Array).append({"key": c["key"], "name": name, "args": args.duplicate(), "sound_id": _arg(args, 0), "firing_index": _firing(c), "status": "skipped_no_level_up_star_sprite"})


static func _act_play_movie(c: Dictionary, name: String, args: Array) -> void:
	(c["runtime"]["movie_requests"] as Array).append({"key": c["key"], "name": name, "args": args.duplicate(), "movie": "end" if not args.is_empty() and _arg(args, 0) == "140" else "", "firing_index": _firing(c), "status": "pending_movie_player"})


static func _act_change_prev_insert_object_id(c: Dictionary, _name: String, args: Array) -> void:
	_apply_previous_insert_id(c["runtime"], c["key"], args)


static func _act_wait_player(c: Dictionary, name: String, args: Array) -> void:
	var target := _wait_target(c["next"], args, true)
	_record_wait(c["next"], c["key"], name, args, target["unit_ids"], target["insert_index"], _firing(c))


static func _act_set_wait_round(c: Dictionary, name: String, args: Array) -> void:
	var target := _wait_target(c["next"], args, false)
	_record_wait(c["next"], c["key"], name, args, target["unit_ids"], target["insert_index"], _firing(c))


## actDeleteObject／actDeletePosObject／actWalkAndDelete／actWalkAndDeleteWait.
static func _act_delete_object(c: Dictionary, name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	var key: String = c["key"]
	# Resolve once into stable IDs. PlayLoop owns the actual departure;
	# its record remains available to the script presentation and saves.
	if name == "actDeletePosObject":
		# 0x42c400 selects live objects by absolute world position,
		# process code and square range. BattleSceneRuntime consumes this
		# presentation mirror; it never changes the unit roster.
		var position_request := {"key": key, "name": name, "args": args.duplicate(), "x": int(_arg(args, 0)), "y": int(_arg(args, 1)), "range": int(_arg(args, 2)), "proc_code": _arg(args, 3), "firing_index": _firing(c)}
		(runtime["object_delete_requests"] as Array).append(position_request)
		if args.size() < 4:
			record_unresolved(runtime, name, key)
		return
	if name != "actDeleteObject":
		(runtime["presentation_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate()})
	var token := _arg(args, 0)
	var serial := int(_arg(args, 1))
	var candidates := WinfailConditions.alive_units_for_token(next, token)
	if not candidates.is_empty():
		# Original0x44fad0:0/1 select first, oversize selects last match.
		# Count currently registered actors, not a frozen opening ordinal.
		candidates = [candidates[clampi(serial - 1, 0, candidates.size() - 1)]]
	if not runtime.has("departure_requests"): runtime["departure_requests"] = []
	(runtime["departure_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate(true), "unit_ids": candidates.duplicate(), "firing_index": _firing(c)})
	var departed: Array = runtime["departed_unit_ids"]
	for unit_id in candidates:
		if departed.find(unit_id) == -1:
			departed.append(unit_id)


static func _act_set_dead_message(c: Dictionary, _name: String, args: Array) -> void:
	var next: Dictionary = c["next"]
	var runtime: Dictionary = c["runtime"]
	if args.size() >= 3:
		runtime["dead_messages"][_arg(args, 0)] = _arg(args, 2)
	if not next.has("script_actor_source"):
		# A level without script actor inserts: the token can only name a unit that
		# already stands, so the word is written now. With inserts, the same-chain
		# insert may be the target: ScriptActorCreationRules replays the chain in
		# action order and writes it there.
		_apply_dead_message(next, runtime, c["key"], args)


## A token with no handler: world-flag and presentation vocabulary is recorded for its
## consumer; anything else is recorded as unsupported.
static func _act_unlisted(c: Dictionary, name: String, args: Array) -> void:
	var runtime: Dictionary = c["runtime"]
	var key: String = c["key"]
	if WinfailCompiler.WORLD_FLAG_ACTIONS.find(name) != -1:
		(runtime["pending_world_flags"] as Array).append({"key": key, "name": name, "args": args.duplicate()})
	elif WinfailCompiler.PRESENTATION_ACTIONS.find(name) != -1:
		(runtime["presentation_requests"] as Array).append({"key": key, "name": name, "args": args.duplicate()})
	else:
		(runtime["unsupported_encountered"] as Array).append({"key": key, "name": name, "args": args.duplicate()})


## actInsertObjectRandomPos 107 (0x450f2c → 0x407ec0) and actInsertStoryObjectRandomPos 108
## (0x451e64 → 0x45e307): the object goes to random slot [pos id] plus (disp x, disp y), in the
## cell holding that pixel. Neither handler draws; the randomness is the slot order actSetRandomPos
## 106 shuffled. A taken or blocked cell is the insert consumer's (ScriptActorCreationRules).
static func _slot_position(next: Dictionary, slot: int, offset: Vector2i = Vector2i.ZERO) -> Dictionary:
	var runtime: Dictionary = next["winfail_runtime"]
	var anchor: Array = (runtime.get("random_position_slots", {}) as Dictionary).get(str(slot), [])
	if anchor.size() != 2:
		return {"ok": false, "reason": "random_position_slot_unset"}
	var requested := Vector2i(int(anchor[0]) + offset.x, int(anchor[1]) + offset.y)
	var cell := Vector2i(floori(float(requested.x) / WinfailCompiler.DEFAULT_CELL_SIZE), floori(float(requested.y) / WinfailCompiler.DEFAULT_CELL_SIZE))
	var size: Vector2i = next.get("map_size", Vector2i.ZERO)
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return {"ok": false, "reason": "random_position_off_map"}
	return {"ok": true, "coord": cell, "pixel": [cell.x * WinfailCompiler.DEFAULT_CELL_SIZE, cell.y * WinfailCompiler.DEFAULT_CELL_SIZE], "requested": requested}


## 0x450f99's fold of one rand(n) draw into a signed offset: up to n/2 (toward zero) stays, a
## larger v becomes n/2 − v.
static func _folded(value: int, bound: int) -> int:
	var half := int(bound / 2)
	return half - value if value > half else value


## actInsertRandomObject 121 (0x450f99): [code][slot][width][height][delay][count]. Per object on
## the global stream: rand(width or 1) 0x450fe6 and rand(height or 1) 0x451012, folded onto the
## slot's x／y, 0x45e307 makes the object with the delay summed so far (+0xae), then rand(delay)
## 0x451075 adds to that sum. Presentation only; the draws still advance the stream.
static func _record_random_effect(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if not GlobalRandomStream.valid(next.get(GlobalRandomStream.LOOP_KEY)):
		record_unresolved(runtime, "actInsertRandomObject", key)
		return
	var anchor: Array = (runtime.get("random_position_slots", {}) as Dictionary).get(str(_int_arg(args, 1)), [])
	var width := _int_arg(args, 2)
	var height := _int_arg(args, 3)
	if width == 0: width = 1
	if height == 0: height = 1
	var rng_before: Array = (next[GlobalRandomStream.LOOP_KEY] as Array).duplicate()
	var objects: Array = []
	var delay := 0
	for _index in range(maxi(0, _int_arg(args, 5))):
		var dx := _folded(GlobalRandomStream.loop_draw(next, width), width)
		var dy := _folded(GlobalRandomStream.loop_draw(next, height), height)
		var row := {"offset": [dx, dy], "delay": delay}
		if anchor.size() == 2: row["position"] = [int(anchor[0]) + dx, int(anchor[1]) + dy]
		objects.append(row)
		delay += GlobalRandomStream.loop_draw(next, _int_arg(args, 4))
	(runtime["presentation_requests"] as Array).append({"key": key, "name": "actInsertRandomObject", "args": args.duplicate(), "objects": objects, "slot_set": anchor.size() == 2, "rng_before": rng_before, "rng_after": (next[GlobalRandomStream.LOOP_KEY] as Array).duplicate()})


static func _apply_item_grant(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	var code := _int_arg(args, 0)
	var count := _int_arg(args, 1)
	var target_id := str(next.get("player_unit_id", ""))
	var request := {"key": key, "name": "actGetItem", "args": args.duplicate(), "item_code": code, "count": count, "target_id": target_id, "firing_index": firing_index, "status": "pending", "slots": []}
	(runtime["item_requests"] as Array).append(request)
	if code <= 0 or count <= 0 or target_id == "":
		request["status"] = "rejected_invalid_item_or_count"
		runtime["unsupported_encountered"].append({"key": key, "name": "actGetItem", "args": args.duplicate(), "reason": "invalid_item_or_count"})
		return
	var actor := WinfailConditions.unit(next, target_id)
	if actor.is_empty() or not InventoryRules.valid(actor.get("inventory")) or not next.get("equipment_items", {}).has(str(code)):
		request["status"] = "rejected_missing_item_or_inventory"
		next.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": "invalid_script_item_grant"}, true)
		return
	for _index in range(count):
		var inserted := InventoryRules.insert(actor["inventory"], code)
		if not inserted["ok"]:
			request["status"] = "rejected_inventory_full"
			next.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": "script_item_inventory_full"}, true)
			return
		actor["inventory"] = inserted["inventory"]
		(request["slots"] as Array).append(int(inserted["slot"]))
	request["status"] = "applied"


## The message ids a live +0x14 death word offers, as the death branches read it (0x43ef91
## in 0x43ea30, 0x4434b2 in 0x442a90): 0 → none; first = high half, second = low half, a
## zero half copies the other (hsltools/levels/battle.py:dead_message_ids, the same read).
static func dead_message_ids(word: int) -> Array:
	word &= 0xffffffff
	if word == 0:
		return []
	var high := word >> 16
	var low := word & 0xffff
	var first := high if high != 0 else low
	var second := low if low != 0 else high
	return [str(first)] if first == second else [str(first), str(second)]


## actSetDeadMessage (opcode 60, jump table 0x4537f4[60] → 0x452197): 0x44fad0(code, serial)
## finds the serial-th live object of the token (0／1 the first, an oversize serial the last)
## and writes its live +0x14 = msg1 << 16 | msg2 — the last writer over the constructor's
## obj_Data8 word and the PLAYERS pair (original_field_coverage.md §4; the STORY opening's
## lines are applied by the level assembler, hsltools/levels/battle.py:script_dead_message).
## The unit's `dead_message` becomes that word's death read with ids only: BattleAftermath
## resolves the text from the level's message texts. The speaker stays the installed 稱號
## (live +0x1c), else the word's previous speaker, else the token's winfail speaker id.
static func _apply_dead_message(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if not dead_message_args_valid(args):
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetDeadMessage", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var candidates := WinfailConditions.alive_units_for_token(next, _arg(args, 0))
	if candidates.is_empty():
		return
	write_dead_message(WinfailConditions.unit(next, str(candidates[clampi(_int_arg(args, 1) - 1, 0, candidates.size() - 1)])), runtime, key, args)


static func dead_message_args_valid(args: Array) -> bool:
	return args.size() >= 4 and _arg(args, 1).is_valid_int() and _arg(args, 2).is_valid_int() and _arg(args, 3).is_valid_int()


## Writes the actSetDeadMessage word onto the resolved unit (see _apply_dead_message).
static func write_dead_message(unit: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	var token := _arg(args, 0)
	var word := ((_int_arg(args, 2) & 0xffff) << 16) | (_int_arg(args, 3) & 0xffff)
	var previous: Dictionary = unit.get("dead_message", {})
	var speaker := str(unit.get("title", ""))
	if speaker == "":
		speaker = str(previous.get("speaker", ""))
	var record := {"speaker": speaker, "messages": dead_message_ids(word).map(func(id: String) -> Dictionary: return {"id": id})}
	if speaker == "":
		record["speaker_id"] = str((runtime.get("speaker_resource_ids", {}) as Dictionary).get(token, ""))
	unit["dead_message"] = record
	unit["dead_message_source"] = "%s actSetDeadMessage %s → live +0x14 = 0x%x (0x452197, after install: last writer wins)" % [key, ",".join(PackedStringArray(args)), word]


static func apply_story_player_state(next: Dictionary, seed: Dictionary) -> void:
	var runtime: Dictionary = next.get("winfail_runtime", {})
	var story: Dictionary = seed.get("scripts", {}).get("story", {})
	for section_value in story.get("sections", []):
		var section: Dictionary = section_value
		for action_value in section.get("actions", []):
			var action: Dictionary = action_value
			for command_value in action.get("chain", []):
				var command: Dictionary = command_value
				var name := str(command.get("name", ""))
				if name != "actSetPlayerMode" and name != "actSetPlayerUndead":
					continue
				var args := WinfailCompiler.string_args(command.get("args", []))
				if name == "actSetPlayerMode":
					_apply_player_mode(next, runtime, "story_%d_mode" % int(section.get("index", 0)), args)
				else:
					_apply_player_undead(next, runtime, "story_%d_undead" % int(section.get("index", 0)), args)


static func _apply_player_job_up(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 2 or not _arg(args, 1).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actPlayerJobUpProcess", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	var targets: Dictionary = next.get("job_up_targets", {})
	var templates: Dictionary = next.get("job_up_templates", {})
	var receipts: Array = runtime["job_up_changes"]
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		# 0x4348f0 reads the job-up code of the row the member currently stands on
		# (record+0x60, copied from the last target): 008's obj_Player8Up1 resolves to 017
		# (global.obs 816 obj_Data7), and a row that declares job_up 0 (012–018) leaves the
		# function before any exchange — a silent no-op, not a failure (static-derived,
		# original_level37_tokens.md). The declared table names only the rows that continue.
		var current_row := JobUpRules.current_template_actor_id(unit)
		if JobUpRules.town_target_actor_id(unit) == "":
			receipts.append({"policy": "job_up_code_zero_noop", "unit_id": str(unit_id), "actor_id": str(unit.get("actor_id", "")), "from_actor_id": current_row, "to_actor_id": "", "key": key, "actor_token": token, "serial": serial})
			continue
		var target_id := str(targets.get(current_row, ""))
		var template: Dictionary = templates.get(target_id, {})
		if target_id == "" or template.is_empty():
			runtime["unsupported_encountered"].append({"key": key, "name": "actPlayerJobUpProcess", "args": args.duplicate(), "reason": "missing_job_up_target_template", "unit_id": unit_id})
			continue
		var result := JobUpRules.merge_source_template(unit, template, JobUpRules.NATIVE_JOB_UP_FLAG)
		if not result["ok"]:
			runtime["unsupported_encountered"].append({"key": key, "name": "actPlayerJobUpProcess", "args": args.duplicate(), "reason": result["reason"], "unit_id": unit_id})
			continue
		# 0x448840 follows the exchange: the new job branch derives HP/MP/attack/defence
		# from the member's unchanged attributes through the shared refresh.
		var equipment_items: Dictionary = next.get("equipment_items", {})
		var refresh_error := ProgressionRules.refresh_input_error(result["actor"], equipment_items)
		if refresh_error != "":
			runtime["unsupported_encountered"].append({"key": key, "name": "actPlayerJobUpProcess", "args": args.duplicate(), "reason": "job_up_refresh_" + refresh_error, "unit_id": unit_id})
			continue
		# Current HP/MP are kept: 0x4348f0 writes none of the vitals (+0xd8..+0xe4), the
		# player constructor 0x407ec0 that re-installs obj_Story_Player8 only calls
		# 0x448840, and 0x448840 clamps a current value downward to the new maximum
		# without refilling (static-derived, original_level37_tokens.md /
		# original_growth_refresh.md) — the shared refresh applies that same clamp.
		var refreshed := ProgressionRules.refresh_growth_stats(result["actor"], equipment_items)
		unit.merge(refreshed, true)
		var receipt: Dictionary = result["receipt"]
		receipt["key"] = key
		receipt["actor_token"] = token
		receipt["serial"] = serial
		receipts.append(receipt)
		# The source delete is the cinematic removal immediately before the native
		# job-up/install. The registered player remains the same logical unit.
		(runtime["departed_unit_ids"] as Array).erase(unit_id)
		for request_value in runtime.get("departure_requests", []):
			(request_value["unit_ids"] as Array).erase(unit_id)
	if ids.is_empty():
		runtime["unsupported_encountered"].append({"key": key, "name": "actPlayerJobUpProcess", "args": args.duplicate(), "reason": "unresolved_actor"})


static func _apply_player_walk_shape(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 2 or not _arg(args, 1).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerWalkShape", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	(runtime["walk_shape_changes"] as Array).append({"key": key, "actor_token": token, "serial": serial, "unit_ids": ids.duplicate(), "status": "pending_actor_runtime" if not ids.is_empty() else "skipped_unresolved_actor"})
	(runtime["presentation_requests"] as Array).append({"key": key, "name": "actSetPlayerWalkShape", "args": args.duplicate(), "unit_ids": ids.duplicate(), "status": "pending_actor_runtime" if not ids.is_empty() else "skipped_unresolved_actor"})
	for unit_id in ids:
		WinfailConditions.unit(next, str(unit_id))["walk_shape_serial"] = serial


static func _apply_player_mode(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 4 or not _arg(args, 1).is_valid_int() or not _arg(args, 3).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerMode", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var mode := _player_mode_arg(_arg(args, 2))
	var role: String = PLAYER_MODE_ROLES.get(mode, "")
	var ids := WinfailConditions.units_for_token(next, token, serial)
	# 0x45073c: every call flips the found object's side-swap bit (+0xa0 ^= 8) before it
	# compares the mode — also when the mode is unchanged or unsupported here; 0x446be0 reads
	# the bit to mirror the object's close-up (BattleCombatCutin.side_swapped).
	var swapped: Array = []
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if not unit.is_empty():
			unit["side_swapped"] = not bool(unit.get("side_swapped", false))
			swapped.append(unit["side_swapped"])
	var receipt := {"key": key, "actor_token": token, "serial": serial, "mode": mode, "flag": _int_arg(args, 3), "unit_ids": ids.duplicate(), "role": role, "side_swapped": swapped}
	(runtime["mode_changes"] as Array).append(receipt)
	if role == "":
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerMode", "args": args.duplicate(), "reason": "unsupported_mode"})
		return
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if unit.is_empty():
			continue
		unit["battle_actor_role"] = role
		unit["player_commandable"] = role == "player_controlled"
		unit["player_mode"] = mode


static func _apply_player_exec_mode(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerExecMode", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var mode := _int_arg(args, 2)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	var receipt := {"key": key, "actor_token": token, "serial": serial, "mode": mode, "native_state": 3 if mode == 0 else 5, "unit_ids": ids.duplicate()}
	(runtime["exec_mode_changes"] as Array).append(receipt)
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if unit.is_empty():
			continue
		unit["player_exec_mode"] = mode
		unit["player_exec_mode_native"] = receipt["native_state"]


static func _apply_random_system_arrival_position(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	if args.is_empty() or not _arg(args, 0).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actRandomSetSysArrivePos", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var requested := _int_arg(args, 0)
	var pair_count := mini(requested, (args.size() - 1) / 2)
	if pair_count <= 0:
		(runtime["unresolved_tokens"] as Array).append({"key": key, "token": "actRandomSetSysArrivePos", "reason": "no_position_pairs"})
		return
	var candidates: Array = []
	for index in range(pair_count):
		var x := int(_arg(args, 1 + index * 2))
		var y := int(_arg(args, 2 + index * 2))
		candidates.append([x & -32, y & -32])
	# 0x451787: one rand(count) 0x458c80 on the global stream picks the pair.
	var rng_before: Array = (next.get(GlobalRandomStream.LOOP_KEY, []) as Array).duplicate()
	var selected_index := GlobalRandomStream.loop_draw(next, pair_count)
	var receipt := {"key": key, "candidates": candidates, "selected_index": selected_index, "position": candidates[selected_index], "rng_before": rng_before, "rng_after": (next[GlobalRandomStream.LOOP_KEY] as Array).duplicate(), "firing_index": firing_index}
	runtime["system_arrival_position"] = receipt.duplicate(true)
	(runtime["system_arrival_position_changes"] as Array).append(receipt)


static func _player_mode_arg(value: Variant) -> int:
	var text := str(value)
	if text.is_valid_int():
		return int(text)
	return {
		"pmPlayer": 0x10000,
		"pmEnemy": 0x20000,
		"pmPlayerEnemy": 0x30000,
		"pmNPCPlayer": 0x50000,
		"pmNPCEnemy": 0x60000,
		"pmNPCPlayerNoMagic": 0x850000,
		"pmMagicAttack": 0x870000,
	}.get(text, 0)


static func _apply_player_fix_pos(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 5 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int() or not _arg(args, 3).is_valid_int() or not _arg(args, 4).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerFixPos", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var x := _int_arg(args, 2)
	var y := _int_arg(args, 3)
	var distance := _int_arg(args, 4)
	# 0x450840 case 0x54 (original_fixpos_fly_prev_insert.md): the resolved object's guard
	# anchor +0x46/+0x44 takes the source pixels and, for a nonzero distance, the live
	# record's ai_fixed (+0x1d0) takes the distance. The unit is not moved: it is the
	# fixed-point walk (0x43fbd6 -> 0x411080) that carries it toward the anchor on its own
	# turns, and an anchor beyond the map edge (WINFAIL012 round 8: -160,1824 etc.) is a
	# retreat point the unit walks toward until actWalkAndDelete removes it two rounds later.
	var ids := WinfailConditions.units_for_token(next, token, serial)
	var map_size: Vector2i = next.get("map_size", Vector2i(0, 0))
	var coord := Vector2i(floori(float(x) / float(WinfailConditions.cell_size(next))), floori(float(y) / float(WinfailConditions.cell_size(next))))
	var off_map := map_size.x <= 0 or map_size.y <= 0 or coord.x < 0 or coord.y < 0 or coord.x >= map_size.x or coord.y >= map_size.y
	var receipt := {"key": key, "actor_token": token, "serial": serial, "pixel": [x, y], "coord": coord, "distance": distance, "unit_ids": ids.duplicate(), "off_map": off_map}
	(runtime["fixed_position_changes"] as Array).append(receipt)
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if unit.is_empty():
			continue
		unit["ai_home_coord"] = coord
		if distance != 0:
			unit["ai_fixed_radius"] = distance


static func _apply_player_fly(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerFly", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var mode := _int_arg(args, 2)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	var enabled := mode != 0
	(runtime["fly_changes"] as Array).append({"key": key, "actor_token": token, "serial": serial, "mode": mode, "enabled": enabled, "unit_ids": ids.duplicate()})
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if unit.is_empty():
			continue
		var traversal: Dictionary = unit.get("traversal", {}).duplicate(true)
		traversal["flying"] = enabled
		if not traversal.has("no_block"): traversal["no_block"] = false
		if not traversal.has("size_type"): traversal["size_type"] = 0
		unit["traversal"] = traversal


static func _apply_previous_insert_id(runtime: Dictionary, key: String, args: Array) -> void:
	if args.is_empty() or not _arg(args, 0).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actChangePrevInsertObjectID", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var object_id := _int_arg(args, 0)
	var inserts: Array = runtime.get("inserts", [])
	var insert_index := inserts.size() - 1
	var previous_id: Variant = null
	if insert_index >= 0:
		var insert: Dictionary = inserts[insert_index]
		previous_id = insert.get("object_id", null)
		insert["object_id"] = object_id
	else:
		runtime["previous_insert_object_id"] = object_id
	(runtime["previous_insert_id_changes"] as Array).append({"key": key, "object_id": object_id, "previous_object_id": previous_id, "insert_index": insert_index})


static func _apply_player_no_attack(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerNoAttack", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var mode := _int_arg(args, 2)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	(runtime["no_attack_changes"] as Array).append({"key": key, "actor_token": token, "serial": serial, "mode": mode, "enabled": mode != 0, "unit_ids": ids.duplicate()})
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if not unit.is_empty():
			unit["no_attack"] = mode != 0


static func _apply_item_use(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actUseItem", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var item_code := _arg(args, 2)
	var ids := WinfailConditions.units_for_token(next, token, serial)
	var request := {"key": key, "name": "actUseItem", "args": args.duplicate(), "actor_token": token, "serial": serial, "item_code": int(item_code), "unit_ids": ids.duplicate(), "firing_index": firing_index, "status": "pending"}
	(runtime["item_requests"] as Array).append(request)
	if ids.size() != 1:
		request["status"] = "rejected_unresolved_actor"
		runtime["unsupported_encountered"].append({"key": key, "name": "actUseItem", "args": args.duplicate(), "reason": "unresolved_actor"})
		return
	var actor := WinfailConditions.unit(next, str(ids[0]))
	var definition: Dictionary = (next.get("consumables", {}) as Dictionary).get(item_code, {})
	var catalog: Dictionary = next.get("equipment_items", {}) as Dictionary
	if actor.is_empty() or definition.is_empty() or not catalog.has(item_code) or not actor.get("inventory") is Array:
		request["status"] = "rejected_missing_item_rule_input"
		runtime["unsupported_encountered"].append({"key": key, "name": "actUseItem", "args": args.duplicate(), "reason": "missing_item_rule_input"})
		return
	var rng: Array = DamageRandomStream.from_words(next.get(DamageRandomStream.LOOP_KEY))
	var sequence := int(next.get("item_use_sequence", 0)) + 1
	var proposed := ItemResolutionRules.prepare(actor, actor, item_code, -1, definition, catalog, rng, sequence)
	if not proposed.get("ok", false):
		request["status"] = "rejected_%s" % str(proposed.get("reason", "item_rule"))
		runtime["unsupported_encountered"].append({"key": key, "name": "actUseItem", "args": args.duplicate(), "reason": str(proposed.get("reason", "item_rule"))})
		return
	actor.merge(proposed["target_changes"], true)
	actor["inventory"] = proposed["inventory"]
	next[DamageRandomStream.LOOP_KEY] = proposed["rng"]
	next["item_use_sequence"] = proposed["receipt"]["sequence"]
	next["last_item_use"] = proposed["receipt"]
	request["status"] = "applied"
	request["receipt"] = proposed["receipt"]


static func _x_range_positions(next: Dictionary, args: Array, insertion: bool = true) -> Array:
	var x_index := 1 if insertion else 0
	var y_index := 2 if insertion else 1
	var count_index := 3 if insertion else 2
	if args.size() <= count_index or not _arg(args, x_index).is_valid_int() or not _arg(args, y_index).is_valid_int() or not _arg(args, count_index).is_valid_int():
		return []
	var count := _int_arg(args, count_index)
	if count <= 0:
		return []
	var cell_size := WinfailConditions.cell_size(next)
	var start_x := floori(float(_int_arg(args, x_index)) / float(cell_size))
	var row := floori(float(_int_arg(args, y_index)) / float(cell_size))
	var positions: Array = []
	for offset in range(count):
		positions.append({"cell": Vector2i(start_x + offset, row), "pixel": [int((start_x + offset) * cell_size + cell_size / 2), int(row * cell_size + cell_size / 2)]})
	return positions


static func _x_range_process_matches(unit: Dictionary, proc_code: String) -> bool:
	if proc_code == "defProcPlayer":
		return WinfailConditions.player_side(unit)
	if proc_code == "defProcEnemy":
		return not WinfailConditions.player_side(unit)
	return false


static func _apply_story_object_x_range(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	var positions := _x_range_positions(next, args)
	if positions.is_empty():
		runtime["unsupported_encountered"].append({"key": key, "name": "actInsertStoryObjectXRange", "args": args.duplicate(), "reason": "invalid_x_range"})
		return
	(runtime["story_object_x_range_requests"] as Array).append({"key": key, "name": "actInsertStoryObjectXRange", "args": args.duplicate(), "object_symbol": _arg(args, 0), "positions": positions, "firing_index": firing_index, "status": "applied"})
	# A terrain stand object (obj_Story_Block) edits its cells' map word as it is created.
	TerrainEditRules.record(next, _arg(args, 0), positions.map(func(value): return value["cell"]), "winfail%03d %s actInsertStoryObjectXRange %s" % [int(next.get("winfail_script_rules", {}).get("source_level", 0)), key, _arg(args, 0)])


## actInsertStoryObject of a terrain stand object (WINFAIL028／080 obj_Story_Level_ClearWall,
## mapobjClearWall) edits its cell's map word as it is created; any other story object is
## presentation only (the record is a no-op for a symbol without a terrain edit).
static func _apply_story_object_terrain(next: Dictionary, key: String, args: Array) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		return
	var cell_size := WinfailConditions.cell_size(next)
	var cell := Vector2i(floori(float(_int_arg(args, 1)) / float(cell_size)), floori(float(_int_arg(args, 2)) / float(cell_size)))
	TerrainEditRules.record(next, _arg(args, 0), [cell], "winfail%03d %s actInsertStoryObject %s" % [int(next.get("winfail_script_rules", {}).get("source_level", 0)), key, _arg(args, 0)])


static func _apply_player_x_range_delete(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	var positions := _x_range_positions(next, args, false)
	var proc_code := _arg(args, 3)
	if positions.is_empty() or proc_code not in ["defProcPlayer", "defProcEnemy"]:
		runtime["unsupported_encountered"].append({"key": key, "name": "actDeletePosPlayerXRange", "args": args.duplicate(), "reason": "invalid_x_range_or_process"})
		return
	var cells: Array = positions.map(func(value): return value["cell"])
	var ids: Array = []
	for unit_value in next.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if not WinfailConditions.unit_alive(next, str(unit.get("id", ""))) or not _x_range_process_matches(unit, proc_code):
			continue
		var coord: Variant = unit.get("coord", null)
		if coord is Vector2i and cells.has(coord):
			ids.append(str(unit.get("id", "")))
	var request := {"key": key, "name": "actDeletePosPlayerXRange", "args": args.duplicate(), "x": _int_arg(args, 0), "y": _int_arg(args, 1), "x_number": _int_arg(args, 2), "proc_code": proc_code, "cells": cells, "unit_ids": ids.duplicate(), "firing_index": firing_index}
	(runtime["player_x_range_delete_requests"] as Array).append(request)
	(runtime["departure_requests"] as Array).append(request.duplicate(true))
	var departed: Array = runtime["departed_unit_ids"]
	for unit_id in ids:
		if departed.find(unit_id) == -1:
			departed.append(unit_id)


static func _apply_story_object_wait_pos(next: Dictionary, runtime: Dictionary, key: String, args: Array, firing_index: int) -> void:
	if args.size() < 2 or not _arg(args, 1).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actInsertStoryObjectWaitPos", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var count := _int_arg(args, 1)
	var positions: Array = []
	for index in range(count):
		var offset := 2 + index * 2
		if offset + 1 >= args.size() or not _arg(args, offset).is_valid_int() or not _arg(args, offset + 1).is_valid_int():
			runtime["unsupported_encountered"].append({"key": key, "name": "actInsertStoryObjectWaitPos", "args": args.duplicate(), "reason": "invalid_position_table"})
			return
		positions.append([_int_arg(args, offset), _int_arg(args, offset + 1)])
	# 0x451ecf: a non-empty table draws one rand(count) 0x458c80 on the global stream (clamped
	# to count-1) to pick the pair; an empty table draws nothing.
	var rng_before: Array = (next.get(GlobalRandomStream.LOOP_KEY, []) as Array).duplicate()
	var selected_index := -1
	if not positions.is_empty():
		selected_index = mini(GlobalRandomStream.loop_draw(next, positions.size()), positions.size() - 1)
	var selected: Array = positions[selected_index] if selected_index >= 0 else []
	var request := {"key": key, "name": "actInsertStoryObjectWaitPos", "args": args.duplicate(), "object_symbol": _arg(args, 0), "position_count": count, "positions": positions, "selected_index": selected_index, "selected_position": selected, "rng_before": rng_before, "rng_after": (next.get(GlobalRandomStream.LOOP_KEY, []) as Array).duplicate(), "firing_index": firing_index, "status": "applied"}
	# The installed object runs its own process; a defProcPoisonGas one (0x43c7c0) spews once
	# at that position before it frees the script's wait. The chain waits on it, so the
	# burst lands before the chain goes on (original_poison_gas.md).
	var gas: Dictionary = (next.get("winfail_script_rules", {}) as Dictionary).get("poison_gas_objects", {})
	if not selected.is_empty() and gas.has(_arg(args, 0)):
		request["poison_gas"] = PoisonGasRules.spew(next, selected, int(gas[_arg(args, 0)]), WinfailConditions.cell_size(next))
	(runtime["story_object_wait_requests"] as Array).append(request)


## The installed object runs its own process; a defProcDropLightn one (0x43ca70) strikes once
## before it frees the script's wait, so the chain goes on after the bolt
## (original_drop_lightning.md). Its view is the presentation's camera (presentation_view,
## written by the scene); without one it centres the actor whose action just ended.
static func _apply_drop_lightning(next: Dictionary, request: Dictionary, symbol: String) -> void:
	var bolts: Dictionary = (next.get("winfail_script_rules", {}) as Dictionary).get("drop_lightning_objects", {})
	if not bolts.has(symbol):
		return
	var cell_size := WinfailConditions.cell_size(next)
	var map_size: Vector2i = next.get("map_size", Vector2i.ZERO)
	var focus := Vector2i((map_size.x * cell_size) >> 1, (map_size.y * cell_size) >> 1)
	var current_id := str(CoreTurnQueue.current(next.get("turn_queue", {})).get("id", ""))
	for unit in next.get("units", []):
		if unit is Dictionary and str(unit.get("id", "")) == current_id and unit.get("coord") is Vector2i:
			focus = (unit["coord"] as Vector2i) * cell_size + Vector2i.ONE * (cell_size >> 1)
	request["drop_lightning"] = DropLightningRules.strike(next, focus, int(bolts[symbol]), cell_size, next.get("presentation_view"))


static func _apply_player_undead(next: Dictionary, runtime: Dictionary, key: String, args: Array) -> void:
	if args.size() < 3 or not _arg(args, 1).is_valid_int() or not _arg(args, 2).is_valid_int():
		runtime["unsupported_encountered"].append({"key": key, "name": "actSetPlayerUndead", "args": args.duplicate(), "reason": "invalid_arguments"})
		return
	var token := _arg(args, 0)
	var serial := _int_arg(args, 1)
	var enabled := _int_arg(args, 2) != 0
	var ids := WinfailConditions.units_for_token(next, token, serial)
	(runtime["undead"] as Array).append({"key": key, "actor_token": token, "serial": serial, "mode": _int_arg(args, 2), "enabled": enabled, "unit_ids": ids.duplicate()})
	for unit_id in ids:
		var unit := WinfailConditions.unit(next, str(unit_id))
		if not unit.is_empty():
			unit["undead"] = enabled


static func _wait_target(battle: Dictionary, args: Array, include_leaving: bool) -> Dictionary:
	var candidates: Array = []
	var token := _arg(args, 0)
	var serial := int(_arg(args, 1))
	var runtime: Dictionary = battle["winfail_runtime"]
	for id in WinfailConditions.units_for_token(battle, token):
		var actor := WinfailConditions.unit(battle, id)
		if not BattlePresenceRules.living(actor): continue
		if not include_leaving and runtime.get("departed_unit_ids", []).has(id): continue
		candidates.append({"unit_ids": [id], "insert_index": -1})
	for index in range(runtime["inserts"].size()):
		var insert: Dictionary = runtime["inserts"][index]
		if str(insert.get("unit_id", "")) != "": continue
		if token.begins_with("SID_ENEMY") and insert.get("class_id") == "Enemy" + token.trim_prefix("SID_ENEMY"):
			candidates.append({"unit_ids": [], "insert_index": index})
	return {"unit_ids": [], "insert_index": -1} if candidates.is_empty() else candidates[clampi(serial - 1, 0, candidates.size() - 1)]


static func _record_wait(battle: Dictionary, key: String, name: String, args: Array, ids: Array, insert_index: int, firing_index: int) -> void:
	var runtime: Dictionary = battle["winfail_runtime"]
	var slot := 0 if name == "actSetPrevInsertObjectWaitRound" else 2
	var value := _int_arg(args, slot, -1)
	var kind := "wait_player" if name == "actWaitPlayer" else "wait_round"
	if kind == "wait_round" and insert_index >= 0:
		runtime["inserts"][insert_index]["wait_round"] = value
		runtime["inserts"][insert_index]["wait_round_set"] = true
	runtime["wait_requests"].append({"key": key, "name": name, "args": args.duplicate(), "kind": kind,
		"actor_token": _arg(args, 0), "unit_ids": ids,
		"insert_index": insert_index, "rounds": value, "firing_index": firing_index})


static func _push_dialogue(runtime: Dictionary, key: String, token: String, message_id: String) -> void:
	var dialogue: Array = runtime["dialogue"]
	if dialogue_has(dialogue, key, message_id):
		return
	dialogue.append({"key": key, "actor_token": token, "message_id": message_id})


static func dialogue_has(dialogue: Array, key: String, message_id: String) -> bool:
	for record_value in dialogue:
		var record: Dictionary = record_value
		if str(record.get("key", "")) == key and str(record.get("message_id", "")) == message_id:
			return true
	return false


static func record_unresolved(runtime: Dictionary, token: String, key: String) -> void:
	var unresolved: Array = runtime.get("unresolved_tokens", [])
	for record_value in unresolved:
		if str((record_value as Dictionary).get("token", "")) == token:
			return
	unresolved.append({"token": token, "key": key})
	runtime["unresolved_tokens"] = unresolved


## ---------------------------------------------------------------------------
## Helpers

static func _arg(args: Array, index: int, default: String = "") -> String:
	return WinfailCompiler.arg(args, index, default)


static func _int_arg(args: Array, index: int, default: int = 0) -> int:
	return WinfailCompiler.int_arg(args, index, default)

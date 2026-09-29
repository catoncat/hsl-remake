extends RefCounted
## Stateless interpreter for the TOWNDEF town-event scripts (te tokens): the
## menu-driven town layer of the original (enter town -> exec event, pick menu
## entries -> run their te chains). It owns no state: every call takes the shared
## world state (schema hsl_world_state.v1, created by the world-map runtime) and a
## party dictionary and returns new copies plus an ordered effect list for a UI.
##
## Evidence: token names, argument order and signatures come from TOWNDEF.H
## (resource-derived, via content/imported/hsl/global/world_map/towndef.json);
## the initial menu trees come from content/world/town_initial_trees.json
## (provisional). Everything about *behaviour* below is a provisional reading of
## those signatures (PACKET_READING_TOKENS; the reading text lives in
## docs/evidence_packets/static_reverse/town_event_semantics.md); nothing here
## claims native handler timing, pricing or equivalence.
##
## Execution model (static-derived: town BOSS 0x4561d0 state machine over the one-pointer
## VM 0x454e20, town_event_semantics.md): the original keeps a single token pointer and a
## sub-menu flag, no call stack. Here a run holds the parked sub-menu frames plus the one
## running frame. teExecEvent and a select row's event replace the running frame (0x4556ea,
## phase 0xf／0x1e 0x455ef0: jump, event 0 or an unknown id continues past the token, a row
## event -1 ends the event); teCreateSubEventMenu (case 10, VM return 2) parks the frame on
## the token while the player picks children (each pick pushes a frame, exit resumes after
## the token — 0x4c27d4); the end of an event, and a condition's "end the event", are the
## same VM return 1: every frame above the nearest parked sub-menu goes and that sub-menu
## re-opens (BOSS state 2 with 0x4000 still set), else the run is done and the root menu
## returns; teMenuMoveOut only slides the stone board out for 20 ticks (VM return 4) and
## leaves the sub-menu open; teSetNextPlayLevelEvent parks the VM (phase 0xd has no
## handler), so the run ends (leaving town). Condition semantics follow the static readings in
## docs/evidence_packets/static_reverse/original_world_town.md (SR-069). Town-level state changed here: towns[*].exec_event /
## exit_exec_event / tree / secret_man / secret_appear_ratio; world-level:
## point_flags, track_flags, point_events, encounter_ratios, point_modes,
## track_modes, show_track_points, bigmap_walker_player_id, over_score, over_flag (the ending dispatch's
## inputs — actAddOverScore / actSetOverFlag reach here through
## WorldScriptActions as teAddOverScore / teSetOverFlag; EndingDispatchRules reads
## them). current_point and visited_points belong to the caller (teSetBMWalkToPoint
## only leaves pending_walk for it).
## provenance:
##   rules: resource-derived content/imported/hsl/global/world_map/towndef.json
##   rules: resource-derived content/world/town_initial_trees.json
##   rules: static-derived content/world/town_job_up_writes.json
##   rules: static-derived content/generated/hsl/static/hsl01/secret_man_goods.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_world_town.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_town_job_up.md
##   rules: static-derived docs/evidence_packets/static_reverse/town_event_semantics.md
##     (execution model: 0x4561d0 BOSS states and the 0x456c84 return table over 0x454e20)
##   rules: provisional
##     (behaviour readings the packet marks provisional and the initial menu trees —
##     docs/evidence_packets/static_reverse/town_event_semantics.md)
##   strings: resource-derived content/imported/hsl/global/world_map/town_messages.json

const WORLD_STATE_SCHEMA := "hsl_world_state.v1"
const RUN_SCHEMA := "hsl_town_event_run.v1"
const TOWNDEF_SCHEMA := "hsl_towndef.v1"
const WORLD_MAP_SCHEMA := "hsl_world_map.v1"
const INITIAL_TREES_SCHEMA := "hsl_town_initial_trees.v1"
const ROOT_KEY := "0"
## TYPE.H gameoverflagFreeEnemy / gameoverflagEnemyJobUp — the over-flag bits
## actSetOverFlag ORs in (no te token sets them; the story route is the only writer).
const OVER_FLAGS := {"gameoverflagFreeEnemy": 1, "gameoverflagEnemyJobUp": 2}
const MAX_STEPS := 4000
const MAX_DEPTH := 24

## te tokens the interpreter executes (state or effect); every other token is
## recorded as recorded_only and skipped, never silently dropped.
const SUPPORTED_TOKENS := [
	"teAddSelfTE", "teDeleteSelfTE", "teAddTE", "teDeleteTE",
	"tePlayerMessage", "teDeletePlayerMessage", "teShapeMessage", "teDeleteShapeMessage",
	"teCreateShop", "teCreateSubEventMenu", "teMenuMoveOut",
	"teSetExecEvent", "teSetTownExecEvent", "teSetTownExitExecEvent", "teSetNextPlayLevelEvent",
	"teExecEvent", "teSelectInsertEvent", "tePlayerSelectInsertEvent",
	"teGetGold", "teGetItem", "teDelay", "tePlaySound", "teAddOverScore", "teSetOverFlag",
	"teCheckMoney", "teCheckPlayerExist", "teCheckItemExist", "teCheckItemExecEvent", "teCheckTEExist", "teCheckJobUp", "teCheckJobUp2",
	"teBMSetPointFlag", "teBMClearPointFlag", "teBMSetTrackFlag", "teBMClearTrackFlag",
	"teBMSetShowTrackPoint", "teBMSetPointEvent", "teBMSetPointEventNotVisit",
	"teBMSetPointMode", "teBMSetTrackMode", "teSetBMWalkToPoint", "teSetBMWalkerPlayerID", "teBMSetPointEncounterRatio",
	"teAppearSecretMan", "teDeleteSecretMan", "teSetSecretAppearRatio", "teSecretManBuyThing",
]
## Recognised but only recorded: teCheckJobUpDeny (token 100) is not in the
## original VM's dispatch table (negative-evidence, original_town_job_up.md);
## the other has no remade system.
const RECORDED_ONLY_TOKENS := ["teCheckJobUpDeny", "teCheckMoney2"]
const JobUpRules = preload("res://game/sim/JobUpRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
## Job caps per PLAYERS template row (roles/profiles.json actors[id].profile.caps),
## the same rows the native cap loader 0x448370 writes for 0x434770's comparison.
const ROLE_PROFILES_PATH := "res://content/generated/hsl/roles/profiles.json"
const ROLE_PROFILES_SCHEMA := "hsl_live_role_profiles.v1"
## 0x434680 after teCheckJobUp2: once every listed member holds its last title, the
## listed town is rewritten (shops closed, exec event and closed-shop entries) through
## the te tree/exec-event writers. The members, town and write list are data
## (content/world/town_job_up_writes.json, hsl check town_job_up_writes); a missing or
## mismatched file is an explicit check_failed effect, never a built-in list.
const TOWN_JOB_UP_WRITES_PATH := "res://content/world/town_job_up_writes.json"
const TOWN_JOB_UP_WRITES_SCHEMA := "hsl_town_job_up_writes.v1"

## te tokens whose interpreter reading is recorded in
## docs/evidence_packets/static_reverse/town_event_semantics.md (迁出表); records
## reference them as READING_REFERENCE_PREFIX + token.
const READING_REFERENCE_PREFIX := "town_event_semantics:"
const PACKET_READING_TOKENS := [
	"teAddSelfTE",
	"teAddTE",
	"teDeleteSelfTE",
	"teDeleteTE",
	"teExecEvent",
	"teSelectInsertEvent",
	"tePlayerSelectInsertEvent",
	"teCreateShop",
	"teCreateSubEventMenu",
	"teMenuMoveOut",
	"teCheckMoney",
	"teCheckPlayerExist",
	"teCheckItemExist",
	"teCheckItemExecEvent",
	"teCheckTEExist",
	"teCheckJobUp",
	"teCheckJobUp2",
	"teSecretManBuyThing",
	"teGetGold",
	"teSetNextPlayLevelEvent",
	"teBMSetPointEventNotVisit",
	"teSetBMWalkToPoint",
	"teAppearSecretMan",
	"teSetSecretAppearRatio",
	"teDeleteSecretMan",
]

## 0x4793b0 / 0x479398: the secret man's nine price rows and their tavern events
## (rows[*].event — teAppearSecretMan's pick), indexed by the purchase counter
## secret_man_index (0x4c1bd4; hsl generate secret_man_goods). A missing or mismatched
## table is an explicit check_failed effect, never a built-in list.
const SECRET_MAN_GOODS_PATH := "res://content/generated/hsl/static/hsl01/secret_man_goods.json"
const SECRET_MAN_GOODS_SCHEMA := "hsl_secret_man_goods.v1"
const SECRET_MAN_MAX_INDEX := 8
## The original default appear ratio is not established; 8 is the only value the
## data sets (瑪哈亞鎮 event 96). Provisional.
const DEFAULT_SECRET_APPEAR_RATIO := 8

## Token → handler tables of the te interpreter. STEP_HANDLERS: tokens of a running town event
## (_step; handler(run, ctx, frame, name, args, pc) → "next"／"jump"／"abort"／"stop"／
## "pending_hold"). WORLD_TOKEN_HANDLERS: writes to the shared world state (towns／big map),
## reached from _step for tokens without a step handler and from apply_script_town_actions for
## script act* actions (_apply_world_token; handler(ctx, name, args)). A token in neither table
## is recorded (recorded_only／unknown_token) and skipped.
static var STEP_HANDLERS := {
	"tePlayerMessage": _te_player_message,
	"teDeletePlayerMessage": _te_delete_player_message,
	"teShapeMessage": _te_shape_message,
	"teDeleteShapeMessage": _te_delete_shape_message,
	"teDelay": _te_delay,
	"tePlaySound": _te_play_sound,
	"teGetGold": _te_get_gold,
	"teGetItem": _te_get_item,
	"teCreateShop": _te_create_shop,
	"teCreateSubEventMenu": _te_create_sub_event_menu,
	"teMenuMoveOut": _te_menu_move_out,
	"teExecEvent": _te_exec_event,
	"teSelectInsertEvent": _te_select_insert_event,
	"tePlayerSelectInsertEvent": _te_player_select_insert_event,
	"teCheckMoney": _te_check_money,
	"teCheckPlayerExist": _te_check_exist_noop,
	"teCheckItemExist": _te_check_exist_noop,
	"teCheckItemExecEvent": _te_check_item_exec_event,
	"teCheckTEExist": _te_check_te_exist,
	"teSecretManBuyThing": _te_secret_man_buy_thing,
	"teCheckJobUp": _te_check_job_up,
	"teCheckJobUp2": _te_check_job_up,
	"teSetNextPlayLevelEvent": _te_set_next_play_level_event,
}
static var WORLD_TOKEN_HANDLERS := {
	"teAddSelfTE": _world_tree_edit,
	"teDeleteSelfTE": _world_tree_edit,
	"teAddTE": _world_tree_edit,
	"teDeleteTE": _world_tree_edit,
	"teSetExecEvent": _world_set_exec_event,
	"teSetTownExecEvent": _world_set_exec_event,
	"teSetTownExitExecEvent": _world_set_town_exit_exec_event,
	"teBMSetPointFlag": _world_bm_flag,
	"teBMClearPointFlag": _world_bm_flag,
	"teBMSetTrackFlag": _world_bm_flag,
	"teBMClearTrackFlag": _world_bm_flag,
	"teBMSetShowTrackPoint": _world_bm_set_show_track_point,
	"teBMSetPointEvent": _world_bm_set_point_event,
	"teBMSetPointEventNotVisit": _world_bm_set_point_event,
	"teBMSetPointMode": _world_bm_set_mode,
	"teBMSetTrackMode": _world_bm_set_mode,
	"teBMSetPointEncounterRatio": _world_bm_set_point_encounter_ratio,
	"teSetBMWalkToPoint": _world_set_bm_walk_to_point,
	"teSetBMWalkerPlayerID": _world_set_bm_walker_player_id,
	"teAddOverScore": _world_add_over_score,
	"teSetOverFlag": _world_set_over_flag,
	"teAppearSecretMan": _world_appear_secret_man,
	"teDeleteSecretMan": _world_delete_secret_man,
	"teSetSecretAppearRatio": _world_set_secret_appear_ratio,
}



## ---------------------------------------------------------------------------
## Loading

static func load_towndef(path: String) -> Dictionary:
	return _load_json(path, TOWNDEF_SCHEMA)


static func load_world_map(path: String) -> Dictionary:
	return _load_json(path, WORLD_MAP_SCHEMA)


static func load_initial_trees(path: String) -> Dictionary:
	return _load_json(path, INITIAL_TREES_SCHEMA)


static func _load_json(path: String, schema: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "missing_file", "path": path}
	var parsed: Variant = ContentPaths.read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "invalid_json", "path": path}
	var data: Dictionary = parsed
	if str(data.get("schema", "")) != schema:
		return {"error": "schema_mismatch", "path": path, "expected": schema, "actual": str(data.get("schema", ""))}
	return data


## ---------------------------------------------------------------------------
## Town state

static func initial_town_state(towndef: Dictionary, initial_trees: Dictionary) -> Dictionary:
	## The "towns" member of hsl_world_state.v1: one entry per extras.h town_*
	## symbol, keyed by point id (string), tree {"parent": [children]} from the
	## provisional initial-tree table (root key "0").
	var towns := {}
	if str(towndef.get("schema", "")) != TOWNDEF_SCHEMA:
		return {"error": "towndef_schema_mismatch"}
	if str(initial_trees.get("schema", "")) != INITIAL_TREES_SCHEMA:
		return {"error": "initial_trees_schema_mismatch"}
	var tree_towns: Dictionary = initial_trees.get("towns", {})
	for symbol in town_symbols(towndef).keys():
		var town_id := int(town_symbols(towndef)[symbol])
		var tree := {ROOT_KEY: []}
		var source: Dictionary = (tree_towns.get(symbol, {}) as Dictionary).get("tree", {})
		for parent in source.keys():
			var children: Array = []
			for child in source[parent]:
				children.append(int(child))
			tree[str(parent)] = children
		if not tree.has(ROOT_KEY):
			tree[ROOT_KEY] = []
		towns[str(town_id)] = {"exec_event": 0, "exit_exec_event": 0, "tree": tree, "secret_man": null, "secret_appear_ratio": 0}
	return towns


static func town_symbols(towndef: Dictionary) -> Dictionary:
	## {"town_歐姆村": 1, ...} from towndef.symbols (extras.h defines).
	var result := {}
	var symbols: Dictionary = towndef.get("symbols", {})
	for key in symbols.keys():
		if str(key).begins_with("town_") and symbols[key] != null:
			result[str(key)] = int(symbols[key])
	return result


static func menu_entries(state: Dictionary, towndef: Dictionary, town_id: int, parent_code: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var town := _town(state, town_id)
	if town.is_empty():
		return result
	var index := _event_index(towndef)
	for code_value in (town.get("tree", {}) as Dictionary).get(str(parent_code), []):
		var code := int(code_value)
		var event: Dictionary = index.get(str(code), {})
		var show: Dictionary = event.get("show_name", {}) if typeof(event.get("show_name")) == TYPE_DICTIONARY else {}
		result.append({
			"code": code,
			"show_name_id": int(show.get("resource_id", 0)),
			"show_name_text": str(show.get("text", "")) if show.get("text") != null else "",
			"item_code": int(event.get("item_code", 0)) if event.get("item_code") != null else 0,
			"sub_menu": _has_token(event, "teCreateSubEventMenu"),
			"known": not event.is_empty(),
		})
	return result


## ---------------------------------------------------------------------------
## Runs

static func begin_event(state: Dictionary, party: Dictionary, towndef: Dictionary, town_id: int, event_code: int) -> Dictionary:
	var run := {
		"schema": RUN_SCHEMA,
		"town_id": town_id,
		"state": state.duplicate(true),
		"party": _normalized_party(party),
		"effects": [],
		"records": [],
		"pending": null,
		"done": false,
		"next_level_event": [],
		"frames": [],
		"steps": 0,
		"towndef": towndef,
	}
	var error := _state_error(state, town_id)
	if error != "":
		run["error"] = error
		run["done"] = true
		return run
	if str(towndef.get("schema", "")) != TOWNDEF_SCHEMA:
		run["error"] = "towndef_schema_mismatch"
		run["done"] = true
		return run
	if not _event_index(towndef).has(str(event_code)):
		run["error"] = "unknown_event:%d" % event_code
		run["done"] = true
		return run
	(run["frames"] as Array).append(_frame(event_code))
	_execute(run)
	return run


static func resume(run: Dictionary, choice: Variant = null) -> Dictionary:
	var next := _copy_run(run)
	if bool(next.get("done", false)) or next.has("error"):
		_record(next, 0, -1, "resume", [], "ignored_after_done")
		return next
	var pending: Variant = next.get("pending")
	if typeof(pending) != TYPE_DICTIONARY:
		_record(next, 0, -1, "resume", [], "ignored_no_pending")
		return next
	var kind := str((pending as Dictionary).get("kind", ""))
	var frames: Array = next["frames"]
	next["pending"] = null
	match kind:
		"select", "player_select":
			# Phase 0xf／0x1e (0x455ef0): a row whose event is -1 (tePlayerSelect's「離開」,
			# resumed as -1) ends the event; a known event replaces the running frame; event 0,
			# an unknown id or no row continues past the token.
			var options: Array = (pending as Dictionary).get("options", [])
			var index := _choice_index(choice, options)
			var target := int((options[index] as Dictionary).get("event", 0)) if index != -1 else (-1 if _choice_event(choice) == -1 else 0)
			if target == -1:
				_record(next, _top_event(frames), -1, "resume", [str(index), "-1"], "end_event")
				_end_event(next, frames)
			elif index == -1:
				_record(next, _top_event(frames), -1, "resume", [str(choice)], "invalid_choice")
			elif target > 0 and _event_index(next["towndef"]).has(str(target)):
				_record(next, _top_event(frames), -1, "resume", [str(index), str(target)], "jump")
				frames[frames.size() - 1] = _frame(target)
			else:
				_record(next, _top_event(frames), -1, "resume", [str(index), str(target)], "continue")
		"sub_menu":
			var target := _choice_event(choice)
			if target > 0:
				_record(next, _top_event(frames), -1, "resume", [str(target)], "push")
				_push_frame(next, target)
			else:
				_record(next, _top_event(frames), -1, "resume", [], "menu_exit")
				if not frames.is_empty():
					var top: Dictionary = frames[frames.size() - 1]
					top["menu_open"] = false
					top["pc"] = int(top["pc"]) + 1
		"shop":
			_record(next, _top_event(frames), -1, "resume", [], "shop_closed")
		_:
			_record(next, _top_event(frames), -1, "resume", [kind], "unknown_pending")
	_execute(next)
	return next


## ---------------------------------------------------------------------------
## Script (winfail / STORY act*) town and big-map actions

static func apply_script_town_actions(state: Dictionary, actions: Array, towndef: Dictionary) -> Dictionary:
	## actAddTE / actDeleteTE / actSetTownExecEvent / actSetTownExitExecEvent /
	## actBM* / actSetBMWalkToPoint with the te argument shapes; unknown names are
	## recorded. Returns {state, effects, records}.
	var ctx := {"state": state.duplicate(true), "towndef": towndef, "town_id": 0, "effects": [], "records": []}
	var error := _state_error(state, 0)
	if error != "":
		return {"state": state.duplicate(true), "effects": [], "records": [], "error": error}
	var index := 0
	for action_value in actions:
		if typeof(action_value) != TYPE_DICTIONARY:
			index += 1
			continue
		var action: Dictionary = action_value
		var name := str(action.get("name", action.get("token", "")))
		var args := WinfailCompiler.string_args(action.get("args", []))
		var te_name := "te" + name.trim_prefix("act") if name.begins_with("act") else name
		if _apply_world_token(ctx, te_name, args, 0, index):
			_record(ctx, 0, index, name, args, "applied")
		else:
			(ctx["effects"] as Array).append({"kind": "recorded_only", "token": name, "args": args})
			_record(ctx, 0, index, name, args, "recorded_only")
		index += 1
	return {"state": ctx["state"], "effects": ctx["effects"], "records": ctx["records"]}


## ---------------------------------------------------------------------------
## Interpreter core

static func _execute(run: Dictionary) -> void:
	var frames: Array = run["frames"]
	var towndef: Dictionary = run["towndef"]
	var index := _event_index(towndef)
	var ctx := {"state": run["state"], "towndef": towndef, "town_id": int(run["town_id"]), "effects": run["effects"], "records": run["records"], "index": index}
	while run.get("pending") == null and not bool(run["done"]):
		if frames.is_empty():
			run["done"] = true
			break
		run["steps"] = int(run["steps"]) + 1
		if int(run["steps"]) > MAX_STEPS:
			run["error"] = "step_limit"
			run["done"] = true
			break
		var frame: Dictionary = frames[frames.size() - 1]
		var event_code := int(frame["event"])
		var tokens: Array = (index.get(str(event_code), {}) as Dictionary).get("events", [])
		var pc := int(frame["pc"])
		if pc >= tokens.size():
			_end_event(run, frames)  # token 0: VM return 1
			continue
		var command: Dictionary = tokens[pc]
		var name := str(command.get("token", ""))
		var args := WinfailCompiler.string_args(command.get("args", []))
		var outcome := _step(run, ctx, frame, name, args, pc)
		match outcome:
			"next":
				frame["pc"] = pc + 1  # also after a shop / select pending: resume continues past the token
			"pending_hold":
				pass  # teCreateSubEventMenu stays parked until exit
			"abort":
				_end_event(run, frames)  # a condition's VM return 1 ends the whole event
			"stop":
				frames.clear()
				run["done"] = true
			_:
				pass  # jump / push already adjusted the frames


static func _end_event(run: Dictionary, frames: Array) -> void:
	## VM return 1 (the end token, a failed condition, a select row event -1): the town BOSS
	## goes back to state 2 (0x4568b7 → 0x456c84 case 1), which slides the stone board in
	## and lists the open sub-menu while flag 0x4000 stands, else the root menu. So every
	## frame above the nearest parked sub-menu goes and that sub-menu re-opens; with none
	## left the run is done.
	while not frames.is_empty() and not bool((frames[frames.size() - 1] as Dictionary).get("menu_open", false)):
		frames.pop_back()
	if not frames.is_empty():
		_open_sub_menu(run, frames[frames.size() - 1])


static func _step(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	## One te token of the running frame (STEP_HANDLERS); a token without a step handler is
	## tried as a world-state write (WORLD_TOKEN_HANDLERS), else recorded and skipped.
	var handler: Callable = STEP_HANDLERS.get(name, Callable())
	if handler.is_valid():
		return handler.call(run, ctx, frame, name, args, pc)
	var event_code := int(frame["event"])
	if _apply_world_token(ctx, name, args, event_code, pc):
		_record(run, event_code, pc, name, args, "applied")
		return "next"
	(run["effects"] as Array).append({"kind": "recorded_only", "token": name, "args": args.duplicate()})
	_record(run, event_code, pc, name, args, "recorded_only" if RECORDED_ONLY_TOKENS.has(name) else "unknown_token")
	return "next"


static func _te_player_message(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var effects: Array = run["effects"]
	effects.append({"kind": "player_message", "player_token": _arg(args, 0), "player_id": _symbol_int(run["towndef"], _arg(args, 0), -1), "message_id": _int_arg(args, 1), "wait": _int_arg(args, 2) != 0})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_delete_player_message(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append({"kind": "delete_player_message"})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_shape_message(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append(_shape_message(_arg(args, 0), _int_arg(args, 1), _int_arg(args, 2), _int_arg(args, 3) != 0))
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_delete_shape_message(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append({"kind": "delete_shape_message"})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_delay(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append({"kind": "delay", "ticks": _int_arg(args, 0)})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_play_sound(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append({"kind": "play_sound", "sound": _arg(args, 0)})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_get_gold(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var party: Dictionary = run["party"]
	var raw := _int_arg(args, 0)
	var display := raw < 0 or (raw & 0x80000000) != 0
	var amount := raw & 0x7fffffff
	party["gold"] = int(party.get("gold", 0)) + amount
	(run["effects"] as Array).append({"kind": "get_gold", "amount": amount, "display": display})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_get_item(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var item_id := _int_arg(args, 0)
	var count := maxi(_int_arg(args, 1), 1)
	_party_add_item(run["party"], item_id, count)
	(run["effects"] as Array).append({"kind": "get_item", "item_id": item_id, "count": count})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


static func _te_create_shop(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var event: Dictionary = (ctx["index"] as Dictionary).get(str(event_code), {})
	var item_code := int(event.get("item_code", 0)) if event.get("item_code") != null else 0
	run["pending"] = {"kind": "shop", "shop_name_id": _int_arg(args, 0), "item_code": item_code, "item_ids": _shop_item_ids(run["towndef"], item_code), "event": event_code}
	_record(run, event_code, pc, name, args, "pending")
	return "next"


static func _te_create_sub_event_menu(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	frame["menu_open"] = true
	_open_sub_menu(run, frame)
	_record(run, int(frame["event"]), pc, name, args, "pending")
	return "pending_hold"


## teMenuMoveOut (case 0x28): phase 0xe with 0x4c1d54 = 20 and VM return 4 — the BOSS slides
## the stone board out (state 89) and waits the 20 ticks; flag 0x4000 is untouched, so an
## open sub-menu re-opens when the event ends.
static func _te_menu_move_out(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	(run["effects"] as Array).append({"kind": "menu_move_out"})
	_record(run, int(frame["event"]), pc, name, args, "applied")
	return "next"


## teExecEvent (case 0x11 → 0x4556ea): a found event replaces the token pointer; event 0 or an
## id 0x44e0e0 does not find continues past the token.
static func _te_exec_event(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var target := _int_arg(args, 0)
	if target > 0 and (ctx["index"] as Dictionary).has(str(target)):
		_record(run, int(frame["event"]), pc, name, args, "jump")
		var frames: Array = run["frames"]
		frames[frames.size() - 1] = _frame(target)
		return "jump"
	_record(run, int(frame["event"]), pc, name, args, "continue")
	return "next"


static func _te_select_insert_event(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var options: Array = []
	var count := _int_arg(args, 1)
	var position := 2
	while position + 1 < args.size() and options.size() < maxi(count, 0):
		options.append({"message_id": _int_arg(args, position), "event": _int_arg(args, position + 1)})
		position += 2
	run["pending"] = {"kind": "select", "speaker": _arg(args, 0), "speaker_id": _symbol_int(run["towndef"], _arg(args, 0), -1), "options": options, "event": event_code}
	_record(run, event_code, pc, name, args, "pending")
	return "next"


## tePlayerSelectInsertEvent [shape][mode][count]{[player][event]} (0x454e20 case 0x1e,
## 0x4557ad–0x455827): a candidate is listed only when 0x42caa0 finds it in the party and
## its record +0x134 job-up bits pass the mode — mode 1 lists members with neither
## 0x80000000 nor 0x40000000 (0x4557fb), mode 2 members with 0x80000000 but not 0x40000000
## (0x4557e5); any other mode lists every present member. The bits are written by
## 0x4348f0: teCheckJobUp / actPlayerJobUpProcess 0x80000000, teCheckJobUp2 0x40000000.
## At most nine member rows (0x4557c3), then「離開」.
const PLAYER_SELECT_MAX_ROWS := 9


static func player_select_mode_passes(mode: int, job_up_flags: int) -> bool:
	match mode:
		1:
			return (job_up_flags & (JobUpRules.NATIVE_JOB_UP_FLAG | JobUpRules.SECOND_TIER_FLAG)) == 0
		2:
			return (job_up_flags & JobUpRules.NATIVE_JOB_UP_FLAG) != 0 and (job_up_flags & JobUpRules.SECOND_TIER_FLAG) == 0
	return true


static func _te_player_select_insert_event(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var party: Dictionary = run["party"]
	var towndef: Dictionary = run["towndef"]
	var options: Array = []
	var count := _int_arg(args, 2)
	var position := 3
	while position + 1 < args.size() and options.size() < maxi(count, 0):
		var token := _arg(args, position)
		options.append({"player_token": token, "player_id": _symbol_int(towndef, token, -1), "event": _int_arg(args, position + 1), "in_party": _party_has_member(party, towndef, token)})
		position += 2
	var mode := _int_arg(args, 1)
	var records: Dictionary = party.get("member_records", {}) if typeof(party.get("member_records")) == TYPE_DICTIONARY else {}
	var listed: Array = []
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var record: Dictionary = records.get(str(option["player_token"]), {}) if typeof(records.get(str(option["player_token"]))) == TYPE_DICTIONARY else {}
		if bool(option["in_party"]) and listed.size() < PLAYER_SELECT_MAX_ROWS and player_select_mode_passes(mode, int(record.get("job_up_flags", 0))):
			listed.append(index)
	run["pending"] = {"kind": "player_select", "shape": _arg(args, 0), "mode": mode, "options": options, "listed": listed, "event": event_code}
	_record(run, event_code, pc, name, args, "pending")
	return "next"


static func _te_check_money(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var party: Dictionary = run["party"]
	var effects: Array = run["effects"]
	var needed := _int_arg(args, 0)
	var have := int(party.get("gold", 0))
	if have >= needed:
		party["gold"] = have - needed
		effects.append({"kind": "spend_gold", "amount": needed})
		_record(run, event_code, pc, name, args, "applied")
		return "next"
	effects.append(_shape_message(_arg(args, 1), _int_arg(args, 2), _int_arg(args, 3), false))
	effects.append({"kind": "check_failed", "token": name, "needed": needed, "have": have})
	_record(run, event_code, pc, name, args, "abort")
	return "abort"


## teCheckPlayerExist／teCheckItemExist.
static func _te_check_exist_noop(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	# The original VM advances past these opcodes without a check (0x454e20).
	_record(run, int(frame["event"]), pc, name, args, "noop")
	return "next"


static func _te_check_item_exec_event(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var party: Dictionary = run["party"]
	var item_id := _int_arg(args, 0)
	var target := _int_arg(args, 1)
	if _party_item_count(party, item_id) <= 0:
		_record(run, event_code, pc, name, args, "applied")
		return "next"
	if _int_arg(args, 2) != 0:
		_party_remove_item(party, item_id, 1)
		(run["effects"] as Array).append({"kind": "remove_item", "item_id": item_id, "count": 1})
	if target > 0 and (ctx["index"] as Dictionary).has(str(target)):
		_record(run, event_code, pc, name, args, "jump")
		var frames: Array = run["frames"]
		frames[frames.size() - 1] = _frame(target)
		return "jump"
	_record(run, event_code, pc, name, args, "applied")
	return "next"


static func _te_check_te_exist(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var event_code := int(frame["event"])
	var town_id := _town_arg(run["towndef"], _arg(args, 0), int(run["town_id"]))
	var target := _int_arg(args, 3)
	if _tree_has_child(run["state"], town_id, _int_arg(args, 1), _int_arg(args, 2)):
		if target == 0:
			_record(run, event_code, pc, name, args, "abort")
			return "abort"
		if (ctx["index"] as Dictionary).has(str(target)):
			_record(run, event_code, pc, name, args, "jump")
			var frames: Array = run["frames"]
			frames[frames.size() - 1] = _frame(target)
			return "jump"
	_record(run, event_code, pc, name, args, "applied")
	return "next"


static func _te_secret_man_buy_thing(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	# [shape][name][fail msg][fail event] — the tavern 神秘男子's gift (0x454e20 case 0x27).
	var event_code := int(frame["event"])
	var party: Dictionary = run["party"]
	var state: Dictionary = run["state"]
	var effects: Array = run["effects"]
	var goods := _load_json(SECRET_MAN_GOODS_PATH, SECRET_MAN_GOODS_SCHEMA)
	var index := clampi(int(state.get("secret_man_index", 0)), 0, SECRET_MAN_MAX_INDEX)
	var rows: Array = goods.get("rows", [])
	if goods.has("error") or index >= rows.size():
		effects.append({"kind": "check_failed", "token": name, "reason": "missing_secret_man_goods", "error": str(goods.get("error", "row"))})
		_record(run, event_code, pc, name, args, "abort")
		return "abort"
	var row: Dictionary = rows[index]
	var price := int(row.get("price", 0))
	var have := int(party.get("gold", 0))
	if have < price:
		var face := _arg(args, 0)
		effects.append(_shape_message("" if face == "-1" else face, _int_arg(args, 1), _int_arg(args, 2), false))
		effects.append({"kind": "check_failed", "token": name, "needed": price, "have": have})
		var target := _int_arg(args, 3)
		if target > 0 and (ctx["index"] as Dictionary).has(str(target)):
			_record(run, event_code, pc, name, args, "jump")
			var frames: Array = run["frames"]
			frames[frames.size() - 1] = _frame(target)
			return "jump"
		_record(run, event_code, pc, name, args, "applied")
		return "next"
	var slots: Array = []
	for code in row.get("items", []):
		if int(code) != 0:
			slots.append(int(code))
	if slots.is_empty():
		effects.append({"kind": "check_failed", "token": name, "reason": "empty_secret_man_row", "index": index})
		_record(run, event_code, pc, name, args, "abort")
		return "abort"
	party["gold"] = have - price
	var pick := _secret_pick(state, slots.size())
	var item_id := int((row["items"] as Array)[pick])
	_party_add_item(party, item_id, 1)
	state["secret_man_index"] = mini(index + 1, SECRET_MAN_MAX_INDEX)
	effects.append({"kind": "spend_gold", "amount": price})
	effects.append({"kind": "get_item", "item_id": item_id, "count": 1})
	effects.append({"kind": "secret_man", "action": "purchase", "index": index, "price": price, "item_id": item_id, "pick": pick, "next_index": int(state["secret_man_index"])})
	_record(run, event_code, pc, name, args, "applied")
	return "next"


## teCheckJobUp／teCheckJobUp2 (_step_check_job_up below).
static func _te_check_job_up(run: Dictionary, ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	return _step_check_job_up(run, ctx, name, args, int(frame["event"]), pc)


static func _te_set_next_play_level_event(run: Dictionary, _ctx: Dictionary, frame: Dictionary, name: String, args: Array, pc: int) -> String:
	var towndef: Dictionary = run["towndef"]
	var level_no := _symbol_int(towndef, _arg(args, 0), _int_arg(args, 0))
	var event := _symbol_int(towndef, _arg(args, 1), _int_arg(args, 1))
	run["next_level_event"] = [level_no, event]
	(run["effects"] as Array).append({"kind": "next_level", "level": level_no, "event": event})
	_record(run, int(frame["event"]), pc, name, args, "stop")
	return "stop"


## teCheckJobUp / teCheckJobUp2 [player][fail message][fail event] (0x454e20 case
## 0x1f / 0x20). The party view carries member_records (WorldPartyRules); the
## condition is 0x434770 on the member's attributes and current job caps, the
## exchange is JobUpRules.merge_source_template on that record, and the caller
## writes the record back into the carry.
static func _step_check_job_up(run: Dictionary, ctx: Dictionary, name: String, args: Array, event_code: int, pc: int) -> String:
	var party: Dictionary = run["party"]
	var state: Dictionary = run["state"]
	var towndef: Dictionary = run["towndef"]
	var effects: Array = run["effects"]
	var token := _arg(args, 0)
	var fail_message := _int_arg(args, 1)
	var fail_event := _int_arg(args, 2)
	var flag := JobUpRules.SECOND_TIER_FLAG if name == "teCheckJobUp2" else JobUpRules.NATIVE_JOB_UP_FLAG
	var records: Dictionary = party.get("member_records", {}) if typeof(party.get("member_records")) == TYPE_DICTIONARY else {}
	var record: Dictionary = records.get(token, {}) if typeof(records.get(token)) == TYPE_DICTIONARY else {}
	var verdict := {"ok": false, "reason": "member_not_in_party", "target_actor_id": ""}
	var template: Dictionary = {}
	var current_job := -1
	if not record.is_empty():
		var profiles := _load_json(ROLE_PROFILES_PATH, ROLE_PROFILES_SCHEMA)
		var current := JobUpRules.current_template_actor_id(record)
		var profile: Dictionary = ((profiles.get("actors", {}) as Dictionary).get(current, {}) as Dictionary).get("profile", {})
		var caps: Dictionary = profile.get("caps", {})
		current_job = int(profile.get("job_code", -1))
		if profiles.has("error") or caps.is_empty():
			verdict = {"ok": false, "reason": "missing_job_caps_" + current, "target_actor_id": ""}
		else:
			verdict = JobUpRules.town_condition(record, record.get("attributes", {}), caps)
			if verdict["ok"]:
				template = JobUpRules.load_source_template(str(verdict["target_actor_id"]))
				if template.is_empty():
					verdict = {"ok": false, "reason": "missing_job_up_template_" + str(verdict["target_actor_id"]), "target_actor_id": verdict["target_actor_id"]}
	if verdict["ok"]:
		# The carry record has no growth_profile of its own: the merge runs on a
		# minimal view (current job + caps) so the summed source layer is replayed
		# from job_up_history by CampaignCarryRules when the next battle is built.
		var view := {"id": str(record.get("unit_id", "")), "actor_id": str(record.get("actor_id", "")), "growth_profile": {"job_code": current_job, "caps": {}, "source": {}}, "base_move_point": 0, "weapon_code": 0, "equipment": [],
			"job_up_flags": int(record.get("job_up_flags", 0)), "job_up_target_actor_id": str(record.get("job_up_target_actor_id", "")), "job_up_history": (record.get("job_up_history", []) as Array).duplicate(true)}
		var merged := JobUpRules.merge_source_template(view, template, flag)
		if not merged["ok"]:
			verdict = {"ok": false, "reason": str(merged["reason"]), "target_actor_id": verdict["target_actor_id"]}
		else:
			var actor: Dictionary = merged["actor"]
			var from_actor_id := JobUpRules.current_template_actor_id(record)
			record["job_up_flags"] = int(actor["job_up_flags"])
			record["job_up_target_actor_id"] = str(actor["job_up_target_actor_id"])
			record["job_up_history"] = actor["job_up_history"]
			records[token] = record
			party["member_records"] = records
			effects.append({"kind": "job_up", "token": name, "player_token": token, "player_id": _symbol_int(towndef, token, -1), "unit_id": str(record.get("unit_id", "")), "actor_id": str(record.get("actor_id", "")),
				"from_actor_id": from_actor_id, "to_actor_id": str(actor["job_up_target_actor_id"]), "job_code": int(merged["receipt"]["job_code"]), "flag": flag, "checks": verdict.get("checks", {})})
			if name == "teCheckJobUp2":
				_apply_second_tier_town_writes(run, ctx, records, event_code, pc)
			_record(run, event_code, pc, name, args, "applied")
			return "next"
	effects.append({"kind": "player_message", "player_token": token, "player_id": _symbol_int(towndef, token, -1), "message_id": fail_message, "wait": false})
	effects.append({"kind": "check_failed", "token": name, "reason": str(verdict["reason"]), "player_token": token, "target_actor_id": str(verdict.get("target_actor_id", "")), "checks": verdict.get("checks", {})})
	_record(run, event_code, pc, name, args, "fail_branch")
	if fail_event >= 0 and (ctx["index"] as Dictionary).has(str(fail_event)):
		var frames: Array = run["frames"]
		frames[frames.size() - 1] = _frame(fail_event)
		return "jump"
	return "abort"


## 0x434680: every member of second_tier.members (the original: player slots 0 and 1)
## must be in the party with job-up code 0 — i.e. standing on its last row — before
## the town writes run.
static func _apply_second_tier_town_writes(run: Dictionary, ctx: Dictionary, records: Dictionary, event_code: int, pc: int) -> void:
	var table := _load_json(TOWN_JOB_UP_WRITES_PATH, TOWN_JOB_UP_WRITES_SCHEMA)
	var second_tier: Dictionary = table.get("second_tier", {}) if typeof(table.get("second_tier")) == TYPE_DICTIONARY else {}
	if table.has("error") or second_tier.is_empty():
		(run["effects"] as Array).append({"kind": "check_failed", "token": "teCheckJobUp2", "reason": "missing_town_job_up_writes", "error": str(table.get("error", "second_tier"))})
		return
	for member in second_tier.get("members", []):
		var record: Dictionary = records.get(str(member), {}) if typeof(records.get(str(member))) == TYPE_DICTIONARY else {}
		if record.is_empty() or JobUpRules.town_target_actor_id(record) != "":
			return
	var writes: Array = second_tier.get("writes", [])
	for entry in writes:
		var write_name := str((entry as Dictionary).get("token", ""))
		var write_args: Array = WinfailCompiler.string_args((entry as Dictionary).get("args", []))
		_apply_world_token(ctx, write_name, write_args, event_code, pc)
		_record(run, event_code, pc, write_name, write_args, "applied_second_tier_job_up")
	(run["effects"] as Array).append({"kind": "job_up_town_writes", "town": str(second_tier.get("town", "")), "count": writes.size()})


static func _apply_world_token(ctx: Dictionary, name: String, args: Array, event_code: int, pc: int) -> bool:
	## Tokens that only rewrite the shared world state (towns / big map); shared
	## between te chains and script act* actions (WORLD_TOKEN_HANDLERS). Returns false
	## when unhandled.
	var handler: Callable = WORLD_TOKEN_HANDLERS.get(name, Callable())
	if not handler.is_valid():
		return false
	handler.call(ctx, name, args)
	return true


## teAddSelfTE／teDeleteSelfTE／teAddTE／teDeleteTE: the town menu tree.
static func _world_tree_edit(ctx: Dictionary, name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var effects: Array = ctx["effects"]
	var self_town := int(ctx["town_id"])
	var has_town := name == "teAddTE" or name == "teDeleteTE"
	var town_id := _town_arg(ctx["towndef"], _arg(args, 0), self_town) if has_town else self_town
	var rest: Array = args.slice(1) if has_town else args
	if rest.size() < 2:
		effects.append({"kind": "check_failed", "token": name, "reason": "short_args"})
		return
	var parent := int(str(rest[0]))
	var num := int(str(rest[1]))
	var children: Array = []
	for value in rest.slice(2):
		if str(value).is_valid_int():
			children.append(int(str(value)))
	var change: Dictionary
	if name.begins_with("teAdd"):
		change = _tree_add(state, town_id, parent, num, children)
	else:
		change = _tree_delete(state, town_id, parent, num, children)
	effects.append({"kind": "tree_change", "town_id": town_id, "parent": parent, "added": change["added"], "removed": change["removed"]})


## teSetExecEvent／teSetTownExecEvent.
static func _world_set_exec_event(ctx: Dictionary, name: String, args: Array) -> void:
	var effects: Array = ctx["effects"]
	var town_id := _town_arg(ctx["towndef"], _arg(args, 0), int(ctx["town_id"]))
	var town := _town(ctx["state"], town_id)
	if town.is_empty():
		effects.append({"kind": "check_failed", "token": name, "reason": "unknown_town", "town": _arg(args, 0)})
		return
	town["exec_event"] = _int_arg(args, 1)
	effects.append({"kind": "set_exec_event", "town_id": town_id, "event": _int_arg(args, 1)})


static func _world_set_town_exit_exec_event(ctx: Dictionary, name: String, args: Array) -> void:
	var effects: Array = ctx["effects"]
	var town_id := _town_arg(ctx["towndef"], _arg(args, 0), int(ctx["town_id"]))
	var town := _town(ctx["state"], town_id)
	if town.is_empty():
		effects.append({"kind": "check_failed", "token": name, "reason": "unknown_town", "town": _arg(args, 0)})
		return
	town["exit_exec_event"] = _int_arg(args, 1)
	effects.append({"kind": "set_exit_exec_event", "town_id": town_id, "event": _int_arg(args, 1)})


## teBMSetPointFlag／teBMClearPointFlag／teBMSetTrackFlag／teBMClearTrackFlag.
static func _world_bm_flag(ctx: Dictionary, name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var is_point := name.contains("Point")
	var set_flag := name.begins_with("teBMSet")
	var id := _town_arg(ctx["towndef"], _arg(args, 0), -1) if is_point else _int_arg(args, 0)
	var flag := _arg(args, 1)
	var table: Dictionary = state.get("point_flags" if is_point else "track_flags", {})
	var flags: Array = table.get(str(id), [])
	if set_flag and not flags.has(flag):
		flags.append(flag)
	elif not set_flag:
		flags.erase(flag)
	table[str(id)] = flags
	state["point_flags" if is_point else "track_flags"] = table
	(ctx["effects"] as Array).append({"kind": "bm_flag_change", "target": "point" if is_point else "track", "id": id, "flag": flag, "set": set_flag})


static func _world_bm_set_show_track_point(ctx: Dictionary, _name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var id := _town_arg(ctx["towndef"], _arg(args, 0), -1)
	var shown: Array = state.get("show_track_points", [])
	if not shown.has(id):
		shown.append(id)
	state["show_track_points"] = shown
	(ctx["effects"] as Array).append({"kind": "bm_show_track_point", "point": id})


## teBMSetPointEvent／teBMSetPointEventNotVisit.
static func _world_bm_set_point_event(ctx: Dictionary, name: String, args: Array) -> void:
	# 0x426c70(point, event, flags) — static-derived (SR-069): event -1 keeps the
	# current event; a non-zero flags word first clears Visit, and when it
	# carries Town / General / Battle the old type bits go before it is ORed in;
	# flags 0 touches neither. The NotVisit variant is read as the same write
	# that leaves Visit alone (provisional: its handler was not executed).
	var state: Dictionary = ctx["state"]
	var id := _town_arg(ctx["towndef"], _arg(args, 0), -1)
	var flag := _arg(args, 2)
	if flag == "0" or flag == "":
		flag = ""
	var event := _int_arg(args, 1)
	var table: Dictionary = state.get("point_events", {})
	var current: Dictionary = table.get(str(id), {}) if typeof(table.get(str(id))) == TYPE_DICTIONARY else {}
	if event == -1:
		event = int(current.get("event", id))
	table[str(id)] = {"event": event, "flag": flag}
	state["point_events"] = table
	if flag != "":
		var flags_table: Dictionary = state.get("point_flags", {})
		var flags: Array = (flags_table.get(str(id), []) as Array).duplicate()
		if not name.ends_with("NotVisit"):
			flags.erase("bmpmVisit")
		if flag in ["bmpmTown", "bmpmGeneral", "bmpmBattle"]:
			for type_name in ["bmpmTown", "bmpmGeneral", "bmpmBattle"]:
				flags.erase(type_name)
		if not flags.has(flag):
			flags.append(flag)
		flags_table[str(id)] = flags
		state["point_flags"] = flags_table
	(ctx["effects"] as Array).append({"kind": "bm_point_event", "point": id, "event": event, "flag": flag, "not_visit": name.ends_with("NotVisit")})


## teBMSetPointMode／teBMSetTrackMode: the TYPE.H bm* display mode of a point or track.
static func _world_bm_set_mode(ctx: Dictionary, name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var towndef: Dictionary = ctx["towndef"]
	var is_point := name == "teBMSetPointMode"
	var id := _town_arg(towndef, _arg(args, 0), -1) if is_point else _int_arg(args, 0)
	var mode := _symbol_int(towndef, _arg(args, 1), _int_arg(args, 1))
	var key := "point_modes" if is_point else "track_modes"
	var table: Dictionary = state.get(key, {})
	table[str(id)] = mode
	state[key] = table
	(ctx["effects"] as Array).append({"kind": "bm_point_mode" if is_point else "bm_track_mode", "id": id, "mode": mode, "mode_symbol": _arg(args, 1)})


static func _world_bm_set_point_encounter_ratio(ctx: Dictionary, _name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var id := _town_arg(ctx["towndef"], _arg(args, 0), -1)
	var table: Dictionary = state.get("encounter_ratios", {})
	table[str(id)] = _int_arg(args, 1)
	state["encounter_ratios"] = table
	(ctx["effects"] as Array).append({"kind": "bm_encounter_ratio", "point": id, "ratio": _int_arg(args, 1)})


static func _world_set_bm_walk_to_point(ctx: Dictionary, _name: String, args: Array) -> void:
	# The walk itself belongs to the world-map runtime: it consumes pending_walk
	# when the town closes / the map opens (the harbour events that ship the party
	# between two points; the pairs are the TOWNDEF data).
	var towndef: Dictionary = ctx["towndef"]
	var walk := {"from": _town_arg(towndef, _arg(args, 0), -1), "to": _town_arg(towndef, _arg(args, 1), -1)}
	(ctx["state"] as Dictionary)["pending_walk"] = walk
	(ctx["effects"] as Array).append({"kind": "bm_walk_to_point", "from_point": int(walk["from"]), "to_point": int(walk["to"])})


## teSetBMWalkerPlayerID／actSetBMWalkerPlayerID (script opcode 96, 0x4518d5): the operand
## goes straight into the walker designation 0x4c1acc — the start slot of the next big-map
## walker (WorldMapRules.walker_unit_id), which clears it once built. SID_* resolve through
## the TOWNDEF symbols (SID_琥 = 2).
static func _world_set_bm_walker_player_id(ctx: Dictionary, _name: String, args: Array) -> void:
	var slot := _symbol_int(ctx["towndef"], _arg(args, 0), _int_arg(args, 0))
	(ctx["state"] as Dictionary)["bigmap_walker_player_id"] = slot
	(ctx["effects"] as Array).append({"kind": "bm_walker_player_id", "player_id": slot})


static func _world_add_over_score(ctx: Dictionary, _name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var id := _symbol_int(ctx["towndef"], _arg(args, 0), _int_arg(args, 0))
	var table: Dictionary = state.get("over_score", {})
	var total := int(table.get(str(id), 0)) + _int_arg(args, 1)
	table[str(id)] = total
	state["over_score"] = table
	(ctx["effects"] as Array).append({"kind": "over_score", "id": id, "delta": _int_arg(args, 1), "total": total})


static func _world_set_over_flag(ctx: Dictionary, _name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var flag_arg := _arg(args, 0)
	var bits := int(flag_arg) if flag_arg.is_valid_int() else int(OVER_FLAGS.get(flag_arg, _symbol_int(ctx["towndef"], flag_arg, 0)))
	var flag := int(state.get("over_flag", 0)) | bits
	state["over_flag"] = flag
	(ctx["effects"] as Array).append({"kind": "over_flag", "flag": flag_arg, "bits": bits, "total": flag})


static func _world_appear_secret_man(ctx: Dictionary, name: String, args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var effects: Array = ctx["effects"]
	var town_id := _town_arg(ctx["towndef"], _arg(args, 0), int(ctx["town_id"]))
	var town := _town(state, town_id)
	if town.is_empty():
		effects.append({"kind": "check_failed", "token": name, "reason": "unknown_town", "town": _arg(args, 0)})
		return
	var tavern := _int_arg(args, 1)
	var force := _int_arg(args, 2) != 0
	var current: Variant = town.get("secret_man")
	var cache := int((current as Dictionary).get("cache", 0)) if typeof(current) == TYPE_DICTIONARY else 0
	if cache != 0 and not force:
		effects.append({"kind": "secret_man", "action": "cached", "town_id": town_id, "tavern_event": tavern, "cache": cache})
		return
	var goods := _load_json(SECRET_MAN_GOODS_PATH, SECRET_MAN_GOODS_SCHEMA)
	var rows: Array = goods.get("rows", [])
	if goods.has("error") or rows.is_empty():
		effects.append({"kind": "check_failed", "token": name, "reason": "missing_secret_man_goods", "error": str(goods.get("error", "rows"))})
		return
	var ratio := int(town.get("secret_appear_ratio", 0))
	if ratio <= 0:
		ratio = DEFAULT_SECRET_APPEAR_RATIO  # unset (no script has set it yet)
	var roll := _secret_roll(state)
	if force or roll < ratio:
		var index := clampi(int(state.get("secret_man_index", 0)), 0, rows.size() - 1)
		var event := int((rows[index] as Dictionary).get("event", 0))
		_tree_add(state, town_id, tavern, 1, [event])
		town["secret_man"] = {"cache": event, "tavern_event": tavern, "roll": roll, "ratio": ratio, "forced": force}
		effects.append({"kind": "secret_man", "action": "appear", "town_id": town_id, "tavern_event": tavern, "event": event, "roll": roll, "ratio": ratio, "forced": force})
	else:
		town["secret_man"] = {"cache": -1, "tavern_event": tavern, "roll": roll, "ratio": ratio, "forced": false}
		effects.append({"kind": "secret_man", "action": "absent", "town_id": town_id, "tavern_event": tavern, "roll": roll, "ratio": ratio})


static func _world_delete_secret_man(ctx: Dictionary, _name: String, _args: Array) -> void:
	var state: Dictionary = ctx["state"]
	var self_town := int(ctx["town_id"])
	var town := _town(state, self_town)
	if not town.is_empty():
		var current: Variant = town.get("secret_man")
		if typeof(current) == TYPE_DICTIONARY and int((current as Dictionary).get("cache", 0)) > 0:
			_tree_delete(state, self_town, int((current as Dictionary).get("tavern_event", 0)), 1, [int((current as Dictionary).get("cache", 0))])
		town["secret_man"] = null
	(ctx["effects"] as Array).append({"kind": "secret_man", "action": "delete", "town_id": self_town})


static func _world_set_secret_appear_ratio(ctx: Dictionary, _name: String, args: Array) -> void:
	var self_town := int(ctx["town_id"])
	var town := _town(ctx["state"], self_town)
	if not town.is_empty():
		town["secret_appear_ratio"] = _int_arg(args, 0)
	(ctx["effects"] as Array).append({"kind": "secret_man", "action": "ratio", "town_id": self_town, "ratio": _int_arg(args, 0)})


## ---------------------------------------------------------------------------
## Tree helpers

static func _tree_add(state: Dictionary, town_id: int, parent: int, num: int, children: Array) -> Dictionary:
	var added: Array = []
	var town := _town(state, town_id)
	if town.is_empty():
		return {"added": added, "removed": [], "error": "unknown_town"}
	var tree: Dictionary = town.get("tree", {})
	if not tree.has(ROOT_KEY):
		tree[ROOT_KEY] = []
	if num == 0:
		if not (tree[ROOT_KEY] as Array).has(parent):
			(tree[ROOT_KEY] as Array).append(parent)
			added.append(parent)
	else:
		if not _tree_contains(tree, parent):
			(tree[ROOT_KEY] as Array).append(parent)
			added.append(parent)
		var list: Array = tree.get(str(parent), [])
		for child in children:
			if not list.has(child):
				list.append(child)
				added.append(child)
		tree[str(parent)] = list
	town["tree"] = tree
	return {"added": added, "removed": []}


static func _tree_delete(state: Dictionary, town_id: int, parent: int, num: int, children: Array) -> Dictionary:
	var removed: Array = []
	var town := _town(state, town_id)
	if town.is_empty():
		return {"added": [], "removed": removed, "error": "unknown_town"}
	var tree: Dictionary = town.get("tree", {})
	if num == 0:
		for key in tree.keys():
			var list: Array = tree[key]
			if list.has(parent):
				list.erase(parent)
				if not removed.has(parent):
					removed.append(parent)
		_erase_subtree(tree, parent)
	else:
		var list: Array = tree.get(str(parent), [])
		for child in children:
			if list.has(child):
				list.erase(child)
				removed.append(child)
				_erase_subtree(tree, child)
		tree[str(parent)] = list
	town["tree"] = tree
	return {"added": [], "removed": removed}


static func _erase_subtree(tree: Dictionary, code: int) -> void:
	if not tree.has(str(code)):
		return
	var children: Array = tree[str(code)]
	tree.erase(str(code))
	for child in children:
		_erase_subtree(tree, int(child))


static func _tree_contains(tree: Dictionary, code: int) -> bool:
	for key in tree.keys():
		if (tree[key] as Array).has(code):
			return true
	return false


static func _tree_has_child(state: Dictionary, town_id: int, parent: int, child: int) -> bool:
	var town := _town(state, town_id)
	if town.is_empty():
		return false
	return ((town.get("tree", {}) as Dictionary).get(str(parent), []) as Array).has(child)


static func _open_sub_menu(run: Dictionary, frame: Dictionary) -> void:
	var parent := int(frame["event"])
	var town_id := int(run["town_id"])
	var children: Array = []
	for code in ((_town(run["state"], town_id).get("tree", {}) as Dictionary).get(str(parent), []) as Array):
		children.append(int(code))
	run["pending"] = {"kind": "sub_menu", "parent_code": parent, "children": children, "entries": menu_entries(run["state"], run["towndef"], town_id, parent)}


## ---------------------------------------------------------------------------
## Party helpers (gold / items only)

static func _normalized_party(party: Dictionary) -> Dictionary:
	var next := party.duplicate(true)
	next["gold"] = int(next.get("gold", 0))
	var items: Array = []
	for item_value in next.get("items", []):
		if typeof(item_value) == TYPE_DICTIONARY:
			items.append({"id": int((item_value as Dictionary).get("id", 0)), "count": int((item_value as Dictionary).get("count", 1))})
	next["items"] = items
	if not next.has("members"):
		next["members"] = []
	return next


static func _party_item_count(party: Dictionary, item_id: int) -> int:
	var total := 0
	for item in party.get("items", []):
		if int((item as Dictionary).get("id", 0)) == item_id:
			total += int((item as Dictionary).get("count", 0))
	return total


static func _party_add_item(party: Dictionary, item_id: int, count: int) -> void:
	var items: Array = party.get("items", [])
	for item in items:
		if int((item as Dictionary).get("id", 0)) == item_id:
			item["count"] = int(item.get("count", 0)) + count
			return
	items.append({"id": item_id, "count": count})
	party["items"] = items


static func _party_remove_item(party: Dictionary, item_id: int, count: int) -> void:
	var items: Array = party.get("items", [])
	var remaining := count
	var kept: Array = []
	for item in items:
		var entry: Dictionary = item
		if int(entry.get("id", 0)) == item_id and remaining > 0:
			var take := mini(remaining, int(entry.get("count", 0)))
			entry["count"] = int(entry.get("count", 0)) - take
			remaining -= take
		if int(entry.get("count", 0)) > 0:
			kept.append(entry)
	party["items"] = kept


static func _party_has_member(party: Dictionary, towndef: Dictionary, token: String) -> bool:
	var members: Array = party.get("members", [])
	if members.has(token):
		return true
	var id := _symbol_int(towndef, token, -1)
	if id == -1:
		return false
	for member in members:
		if str(member).is_valid_int() and int(str(member)) == id:
			return true
	return false


## ---------------------------------------------------------------------------
## Lookup helpers

static func _event_index(towndef: Dictionary) -> Dictionary:
	## code (string) -> town_event record (pure; 191 records, rebuilt per call).
	var index := {}
	for record in towndef.get("town_events", []):
		if typeof(record) == TYPE_DICTIONARY:
			index[str(int((record as Dictionary).get("code", 0)))] = record
	return index


static func _shop_item_ids(towndef: Dictionary, item_code: int) -> Array:
	var ids: Array = []
	if item_code <= 0:
		return ids
	for record in towndef.get("items", []):
		if typeof(record) == TYPE_DICTIONARY and int((record as Dictionary).get("code", 0)) == item_code:
			for value in (record as Dictionary).get("item_ids", []):
				ids.append(int(value))
			return ids
	return ids


static func _has_token(event: Dictionary, token: String) -> bool:
	for command in event.get("events", []):
		if typeof(command) == TYPE_DICTIONARY and str((command as Dictionary).get("token", "")) == token:
			return true
	return false


## 1..100 like the original rand(100)+1; tests fix it through state["secret_roll"].
static func _secret_roll(state: Dictionary) -> int:
	if state.has("secret_roll"):
		return int(state["secret_roll"])
	return int(randi() % 100) + 1


## rand(n) over the goods row's non-zero slots (0x458c80(n)); state.secret_pick pins it for tests.
static func _secret_pick(state: Dictionary, count: int) -> int:
	if state.has("secret_pick"):
		return clampi(int(state["secret_pick"]), 0, count - 1)
	return int(randi() % count)


static func _town(state: Dictionary, town_id: int) -> Dictionary:
	var towns: Dictionary = state.get("towns", {})
	var value: Variant = towns.get(str(town_id))
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _town_arg(towndef: Dictionary, arg: String, fallback: int) -> int:
	## town_XXX symbol (extras.h) or a numeric point id; fallback otherwise.
	if arg.is_valid_int():
		return int(arg)
	var symbols: Dictionary = towndef.get("symbols", {})
	if arg.begins_with("town_") and symbols.has(arg) and symbols[arg] != null:
		return int(symbols[arg])
	return fallback


static func _symbol_int(towndef: Dictionary, arg: String, fallback: int) -> int:
	if arg.is_valid_int():
		return int(arg)
	var symbols: Dictionary = towndef.get("symbols", {})
	if symbols.has(arg) and symbols[arg] != null:
		var value: Variant = symbols[arg]
		if typeof(value) == TYPE_STRING and str(value).begins_with("0x"):
			return str(value).hex_to_int()
		if typeof(value) == TYPE_STRING and str(value).is_valid_int():
			return int(str(value))
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			return int(value)
	return fallback


static func _shape_message(face_member: String, name_id: int, message_id: int, wait: bool) -> Dictionary:
	return {"kind": "shape_message", "face_member": face_member, "name_resource_id": name_id, "message_id": message_id, "wait": wait}


static func _state_error(state: Dictionary, town_id: int) -> String:
	if str(state.get("schema", "")) != WORLD_STATE_SCHEMA:
		return "state_schema_mismatch"
	if typeof(state.get("towns")) != TYPE_DICTIONARY:
		return "state_missing_towns"
	if town_id != 0 and not (state["towns"] as Dictionary).has(str(town_id)):
		return "unknown_town:%d" % town_id
	return ""


static func _frame(event_code: int) -> Dictionary:
	return {"event": event_code, "pc": 0, "menu_open": false}


## A sub-menu child runs above its parked menu frame (the only push: selects and jumps
## replace the running frame).
static func _push_frame(run: Dictionary, event_code: int) -> void:
	var frames: Array = run["frames"]
	var index := _event_index(run["towndef"])
	if frames.size() >= MAX_DEPTH:
		run["error"] = "depth_limit"
		run["done"] = true
		return
	if not index.has(str(event_code)):
		(run["effects"] as Array).append({"kind": "check_failed", "token": "resume", "reason": "unknown_event", "event": event_code})
		return
	frames.append(_frame(event_code))


static func _copy_run(run: Dictionary) -> Dictionary:
	## Deep-copies the run without duplicating the (read-only) towndef reference.
	var towndef: Variant = run.get("towndef", {})
	var shallow := run.duplicate(false)
	shallow.erase("towndef")
	var next := shallow.duplicate(true)
	next["towndef"] = towndef
	return next


static func _top_event(frames: Array) -> int:
	return int((frames[frames.size() - 1] as Dictionary).get("event", 0)) if not frames.is_empty() else 0


static func _choice_index(choice: Variant, options: Array) -> int:
	var index := -1
	if typeof(choice) == TYPE_INT or typeof(choice) == TYPE_FLOAT:
		index = int(choice)
	elif typeof(choice) == TYPE_DICTIONARY:
		var choice_dict: Dictionary = choice
		if choice_dict.has("index"):
			index = int(choice_dict["index"])
		elif choice_dict.has("event"):
			for offset in range(options.size()):
				if int((options[offset] as Dictionary).get("event", -1)) == int(choice_dict["event"]):
					return offset
	return index if index >= 0 and index < options.size() else -1


static func _choice_event(choice: Variant) -> int:
	if typeof(choice) == TYPE_INT or typeof(choice) == TYPE_FLOAT:
		return int(choice)
	if typeof(choice) == TYPE_DICTIONARY and (choice as Dictionary).has("event"):
		return int((choice as Dictionary)["event"])
	return 0


static func _record(target: Dictionary, event_code: int, pc: int, token: String, args: Array, status: String) -> void:
	## Appends to target["records"] (a run or a script-action ctx); act* names
	## look up the provisional reading of their te twin.
	var te_name := "te" + token.trim_prefix("act") if token.begins_with("act") else token
	var record := {"event": event_code, "index": pc, "token": token, "args": args.duplicate(), "status": status}
	if PACKET_READING_TOKENS.has(te_name):
		record["provisional"] = READING_REFERENCE_PREFIX + te_name
	(target["records"] as Array).append(record)


static func _arg(args: Array, index: int) -> String:
	return str(args[index]) if index < args.size() else ""


static func _int_arg(args: Array, index: int) -> int:
	var value := _arg(args, index)
	return int(value) if value.is_valid_int() else 0

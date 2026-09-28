extends RefCounted
## Ordered installation and placement proposals for a fired battle status.
## Templates are immutable configuration; only PlayLoop commits the result.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_install.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_campaign_actors.md
##     (a reserve or carried member's re-install keeps its live record, 0x407ec0)
##   rules: remake-invented (atomic whole-event install; the landing is checked once, at the final cell)
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_entry.md
##     (blocked landing 0x44fbd0: flood 12, nearest Manhattan, row-major, rand&1 ties)
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_walk_path.md
##     (a walk commits the cell its 0x453b90 chain stops on, 0x411a30 at 0x4541a1)
##   rules: provisional (walk draws per unit after its landing draws, skipping standing and placed units;
##     the original interleaves VM rounds with walker ticks, so its draw and registration order may differ)
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: runtime-measured tools/hsltools/probes/_reward_rng_trace.py
##     (birth: carry 0x407c86 on the global stream, then level adjustment 0x40e92c)
##   rules: resource-derived content/imported/hsl/chapter01/battle051/source_texts/winfail051.txt
const POLICY := "source_script_actor_v1"
const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const InitialRosterGrowthRules = preload("res://game/sim/InitialRosterGrowthRules.gd")
const ReinforcementGrowthRules = preload("res://game/sim/ReinforcementGrowthRules.gd")
const ActorTraversalRules = preload("res://game/sim/ActorTraversalRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const ScriptWalkPath = preload("res://game/sim/ScriptWalkPath.gd")
## 0x44fbd0 -> 0x40f440(copy, 12, mode): the blocked-landing flood radius.
const LANDING_FLOOD_RADIUS := 12
const MOVE_ABSOLUTE := ["actWalk", "actWalkWait"]
const MOVE_RELATIVE := ["actWalkDisp", "actWalkDispWait"]
const MOVE_TO_ACTOR := ["actWalkToPlayerDisp", "actWalkToPlayerDispWait"]
const DEPART := ["actWalkAndDelete", "actWalkAndDeleteWait", "actDeleteObject"]
const RANDOM_INSERTS := ["actInsertObjectRandomPos", "actInsertStoryObjectRandomPos"]


static func source_error(templates: Variant) -> String:
	# An empty set is a level whose chains only walk units that already stand (walk_only_source).
	if not templates is Dictionary: return "invalid_script_actor_templates"
	var player_ids := {}
	for symbol in templates:
		var spec: Variant = templates[symbol]
		if not symbol is String or symbol == "" or not spec is Dictionary or spec.get("kind") not in ["registered_player", "npc"] or not spec.get("actor") is Dictionary:
			return "invalid_script_actor_template"
		var actor: Dictionary = spec["actor"]
		if not spec.get("token") is String or not spec["token"].begins_with("SID_") or not spec.get("aliases") is Array: return "invalid_script_actor_binding"
		for alias in spec["aliases"]:
			if not alias is String or not alias.begins_with("SID_"): return "invalid_script_actor_binding"
		if not actor.get("id") is String or actor["id"] == "" or spec.get("source_actor_id") != actor.get("actor_id"): return "invalid_script_actor_identity"
		if actor.has("entry_growth") or actor.has("script_creation") or not actor.get("learned_skills", []).is_empty(): return "progressed_script_actor_template"
		if spec["kind"] == "registered_player":
			if actor.get("source_object_kind") != 3 or actor.get("growth_profile", {}).get("allocation") != "manual" or actor.get("player_commandable") != true or actor.get("battle_actor_role") != "player_controlled" or player_ids.has(actor["id"]):
				return "invalid_registered_player_template"
			player_ids[actor["id"]] = true
		elif actor.get("player_commandable") != false or actor.get("battle_actor_role") not in ["enemy_ai", "friendly_ai"]:
			return "invalid_script_npc_template"
	return ""


## A level with no script inserts still runs its fired chains through the transaction when
## one of them walks a unit: the original walk moves the object itself (LEVEL900 event 1,
## chosen in STORY900: the three villagers walk to [18,34]／[20,33]／[20,35] before the first
## actor; original_select_insert_event.md). An empty template set, as a scenario would give.
static func walk_only_source(rules: Dictionary) -> Dictionary:
	for kind in WinfailCompiler.STATUS_KINDS:
		for status in (rules.get("statuses", {}) as Dictionary).get(kind, []):
			for action in (status as Dictionary).get("actions", []):
				if str((action as Dictionary).get("name", "")) in MOVE_ABSOLUTE + MOVE_RELATIVE + MOVE_TO_ACTOR:
					return {"policy": POLICY, "templates": {}}
	return {}


static func pending(loop: Dictionary) -> bool:
	return loop.has("script_actor_source") and loop.get("script_actor_transactions", []).size() < loop.get("winfail_runtime", {}).get("fired", []).size()


static func prepare(loop: Dictionary) -> Dictionary:
	if not pending(loop): return {"ok": true, "loop": loop}
	if BattleOutcome.decided(loop) or not loop.get("scenario_ok", false): return {"ok": false, "reason": "invalid_script_creation_boundary"}
	var error := source_error(loop["script_actor_source"].get("templates"))
	if error != "": return {"ok": false, "reason": error}
	var next := BattleLoopConfig.copy(loop)
	var fired: Array = next["winfail_runtime"]["fired"]
	while next["script_actor_transactions"].size() < fired.size():
		var index: int = next["script_actor_transactions"].size()
		var status := WinfailCompiler.status_by_key(next["winfail_script_rules"], fired[index]["key"])
		if status.is_empty(): return {"ok": false, "reason": "missing_script_creation_program"}
		var result := _apply_status(next, status, index)
		if not result["ok"]: return result
		next["script_actor_transactions"].append(result["receipt"])
	return {"ok": true, "loop": next}


static func _apply_status(loop: Dictionary, status: Dictionary, firing: int) -> Dictionary:
	var runtime: Dictionary = loop["winfail_runtime"]
	var templates: Dictionary = loop["script_actor_source"]["templates"]
	var receipt := {"policy": POLICY, "firing_index": firing, "key": status["key"],
		"actions": [], "created_ids": [], "placements": []}
	var positions := {}
	for actor in loop["units"]: positions[actor["id"]] = TacticalGridRules.cell_pixel(actor["coord"])
	var departed: Array = []
	var touched: Array = []
	var births: Array = []
	var previous := ""
	var insert_number := 0
	var requests: Array = runtime["inserts"].filter(func(row): return row.get("key") == status["key"] and int(row.get("firing_index", -1)) == firing)
	# A chain gate that ended this firing (WinfailActions: actCheckEventNotExist) leaves
	# the rest of the chain unexecuted; its rows stay in the receipt, marked skipped.
	var chain_stop := int(runtime["fired"][firing].get("chain_stop_index", -1))
	for action_index in range(status["actions"].size()):
		var action: Dictionary = status["actions"][action_index]
		var name: String = action["name"]
		var args: Array = action["args"]
		var row := {"source_index": action_index + status["conditions"].size(), "name": name, "args": args.duplicate(), "bindings": {}}
		if chain_stop >= 0 and int(row["source_index"]) >= chain_stop:
			row["skipped"] = "chain_stopped"
			receipt["actions"].append(row)
			continue
		var insert_request: Dictionary = {}
		# Random-position inserts (actInsertObjectRandomPos / actInsertStoryObjectRandomPos)
		# carry their resolved pixel in the interpreter's insert request; args[1..2] are offsets.
		var random_insert := name in RANDOM_INSERTS
		if name == "actInsertObject" or random_insert:
			if args.size() < 3: return {"ok": false, "reason": "unsupported_script_actor_symbol"}
			if not templates.has(args[0]):
				row["presentation_only"] = true
			else:
				if insert_number >= requests.size(): return {"ok": false, "reason": "missing_script_insert_request"}
				insert_request = requests[insert_number]
				insert_number += 1
				if random_insert and (insert_request.get("position_xy", []) as Array).size() != 2:
					return {"ok": false, "reason": "missing_random_insert_position"}
		if (name in ["actInsertObject", "actInsertStoryObject", "actInsertStoryObjectWait"] or random_insert) and args.size() >= 3 and templates.has(args[0]):
			var symbol: String = args[0]
			var spec: Dictionary = templates[symbol]
			# A template the assembler declared as insert_skip (level 15's 咕嚕 008:
			# its source 3CellCircle weapon is deliberately not modelled) keeps the
			# script transaction explicit instead of substituting another weapon.
			if spec.has("insert_skip"):
				row["skipped"] = str(spec["insert_skip"])
				receipt["actions"].append(row)
				continue
			var installed := _install_row(loop, spec, symbol, firing, action_index, insert_request, random_insert, args, receipt, positions, touched, departed, row)
			if not installed["ok"]: return installed
			previous = installed["unit_id"]
			if installed.get("birth_pending", false): births.append({"unit_id": previous, "request": insert_request})
		elif name in ["actWalkPrevInsertObject", "actWalkPrevInsertObjectWait"] and args.size() >= 2 and previous != "":
			_move(positions, touched, row, previous, Vector2i(int(args[0]), int(args[1])))
		elif name == "actChangePrevInsertObjectID" and not args.is_empty() and str(args[0]).is_valid_int() and previous != "":
			# The renamed object answers to its new numeric id for the rest of the script
			# (WINFAIL051 event 3: the messenger 10000 walks, speaks 368 and leaves; WINFAIL012
			# addresses its renamed inserts the same way). Original: 0x450840 case 0x20 writes
			# the id to the previous insert's roster word +0x84, the code 0x44fa80 returns to
			# the 0x44fad0 lookup (docs/evidence_packets/static_reverse/original_story_object_terrain.md).
			loop["winfail_runtime"]["actor_bindings"]["%s/1" % str(args[0])] = previous
			row["object_id_binding"] = {"unit_id": previous, "token": str(args[0])}
			row["bindings"] = _bindings(loop, departed)
		elif name in MOVE_ABSOLUTE + MOVE_RELATIVE + MOVE_TO_ACTOR + DEPART:
			var moved := _motion_row(loop, runtime, status, firing, receipt, positions, touched, departed, row, name, args)
			if not moved["ok"]: return moved
		elif name == "actSetDeadMessage" and WinfailActions.dead_message_args_valid(args):
			# 0x452197 addresses the object like the walks above: a same-chain insert (level 6's
			# second 隊長 969, the party members WINFAIL007／010／017／019 install) already exists here.
			var id := _actor_id(loop, str(args[0]), int(args[1]), departed)
			row["bindings"] = _bindings(loop, departed)
			if id != "":
				WinfailActions.write_dead_message(WinfailConditions.unit(loop, id), runtime, status["key"], args)
				row["dead_message"] = {"unit_id": id}
			else:
				row["missing_actor"] = true
		else:
			row["bindings"] = _bindings(loop, departed)
		receipt["actions"].append(row)
	var placed := _place_touched(loop, runtime, receipt, positions, touched, departed)
	if not placed["ok"]: return placed
	# An NPC (SID_ENEMY, +0xa0 >= 0x14) is born on its first object tick, after the VM has run
	# the chain's tokens and their 0x44fbd0 landings; only SID < 0x14 players are born inside
	# the constructor (0x407ec0 calls the process at 0x40809e), and their birth draws nothing here.
	for pending in births:
		var born := _npc_birth(loop, pending["unit_id"], pending["request"])
		if not born["ok"]: return born
	return {"ok": true, "receipt": receipt}


## An installing insert: installs the template actor and records the row; a created
## unit takes its insert pixel and joins `touched`. Returns install_actor's result.
static func _install_row(loop: Dictionary, spec: Dictionary, symbol: String, firing: int, action_index: int, insert_request: Dictionary, random_insert: bool, args: Array, receipt: Dictionary, positions: Dictionary, touched: Array, departed: Array, row: Dictionary) -> Dictionary:
	var installed := install_actor(loop, spec, symbol, firing, action_index, insert_request, true)
	if not installed["ok"]: return installed
	var id: String = installed["unit_id"]
	if installed["created"]:
		receipt["created_ids"].append(id)
		positions[id] = Vector2i(int(insert_request["position_xy"][0]), int(insert_request["position_xy"][1])) if random_insert else Vector2i(int(args[1]), int(args[2]))
		if not touched.has(id): touched.append(id)
	row["install"] = {"unit_id": id, "actor_id": spec["actor"]["actor_id"], "symbol": symbol,
		"position": positions[id], "created": installed["created"]}
	row["bindings"] = _bindings(loop, departed)
	return installed


## A move／depart action on a bound actor: records its departure or motion (moves also
## update `positions`／`touched`), or marks the row missing_actor.
static func _motion_row(loop: Dictionary, runtime: Dictionary, status: Dictionary, firing: int, receipt: Dictionary, positions: Dictionary, touched: Array, departed: Array, row: Dictionary, name: String, args: Array) -> Dictionary:
	var id := _actor_id(loop, str(args[0]) if not args.is_empty() else "", int(args[1]) if args.size() >= 2 else 1, departed)
	row["bindings"] = _bindings(loop, departed)
	if id != "":
		if name in DEPART:
			row["departure"] = {"unit_id": id}
			if args.size() >= 4: row["motion"] = {"unit_id": id, "from": positions[id], "to": Vector2i(int(args[2]), int(args[3]))}
			departed.append(id)
			if receipt["created_ids"].has(id):
				# The interpreter resolved this delete before the unit existed (it is
				# inserted by the same chain: WINFAIL051's messenger); the transaction
				# completes its departure request so the PlayLoop retires the unit too.
				_complete_departure_request(runtime, status["key"], firing, name, args, id)
		elif args.size() >= 4 and name in MOVE_ABSOLUTE + MOVE_RELATIVE:
			var target := Vector2i(int(args[2]), int(args[3]))
			if name in MOVE_RELATIVE: target += positions[id]
			_move(positions, touched, row, id, target)
		elif args.size() >= 6 and name in MOVE_TO_ACTOR:
			var leader := _actor_id(loop, str(args[2]), int(args[3]), departed)
			if leader == "": return {"ok": false, "reason": "missing_script_relative_actor"}
			_move(positions, touched, row, id, positions[leader] + Vector2i(int(args[4]), int(args[5])))
	else:
		row["missing_actor"] = true
	return {"ok": true}


## Commits every touched, not departed actor to its 0x44fbd0 landing cell and ends
## its last visual move there. Returns {"ok": true} or the failed landing.
static func _place_touched(loop: Dictionary, runtime: Dictionary, receipt: Dictionary, positions: Dictionary, touched: Array, departed: Array) -> Dictionary:
	# Temporary insertion pixels and cinematic overlaps are not occupancy. A blocked
	# final source cell takes 0x44fbd0's replacement (nearest_landing).
	var occupants: Array = loop["units"].filter(func(a): return not touched.has(a["id"]) and not runtime["departed_unit_ids"].has(a["id"]))
	for id in touched:
		if departed.has(id): continue
		var actor := WinfailConditions.unit(loop, id)
		var requested: Vector2i = positions[id] / TacticalGridRules.CELL_PIXELS
		var last := {}
		for index in range(receipt["actions"].size() - 1, -1, -1):
			var row: Dictionary = receipt["actions"][index]
			if row.get("motion", {}).get("unit_id") == id or row.get("install", {}).get("unit_id") == id:
				last = row
				break
		# The random-position insert (0x450f55) constructs without 0x44fbd0; actInsertObject
		# (0x450ee2) and every walk destination pass through it.
		var landing := {"ok": true, "coord": requested, "draws": []} if last.has("install") and str(last["name"]) in RANDOM_INSERTS else nearest_landing(actor, requested, occupants, loop)
		if not landing["ok"]: return landing
		# The walker 0x453b90 walks the 0x44fbd0-fixed destination along the 0x4111d0 chain and
		# registers the cell it stops on (0x411a30 at 0x4541a1): a ground walker the chain cannot
		# bring there stops short; a flying one (mode 6) reaches it. Its 0x413740 scans skip the
		# cells `occupants` hold (the first chain call its own start cell too) and draw ties and
		# crowded drops on the global stream, after this unit's landing draws. A 3x3 body keeps
		# its landing (large footprint not ported); an occupied stop cell keeps the landing.
		var walk_stop := Vector2i(-1, -1)
		var walk := {}
		if last.has("motion") and int(actor.get("traversal", {}).get("size_type", 0)) == 0:
			var from_cell: Vector2i = Vector2i(last["motion"]["from"]) / TacticalGridRules.CELL_PIXELS
			var taken: Dictionary = AINavigationRules.SkillTargetRules.Footprint.occupants(occupants)
			walk = {"rng": GlobalRandomStream.loop_source(loop) if GlobalRandomStream.valid(loop.get(GlobalRandomStream.LOOP_KEY)) else null, "draws": [], "taken": taken,
				"words": AINavigationRules.neighbour_words({"tiles": loop.get("tiles", {}), "terrain_edits": loop.get("terrain_edits", []), "units": occupants}), "side": AINavigationRules.side_word(actor)}
			var stop := ScriptWalkPath.stop_cell(TerrainEditRules.tiles(loop), loop["map_size"], from_cell, landing["coord"], TacticalGridRules.CELL_PIXELS, bool(actor.get("traversal", {}).get("flying", false)), walk)
			if stop != landing["coord"] and not taken.has(stop):
				walk_stop = landing["coord"]
				landing["coord"] = stop
		actor["coord"] = landing["coord"]
		actor["grid_coord"] = actor["coord"]
		if receipt["created_ids"].has(id): actor["ai_home_coord"] = actor["coord"]
		occupants.append(actor)
		receipt["placements"].append({"unit_id": id, "requested": requested, "coord": actor["coord"], "adjusted": requested != actor["coord"], "draws": landing["draws"]})
		if walk_stop.x >= 0: receipt["placements"].back()["walk_stop_from"] = walk_stop
		if not walk.is_empty(): receipt["placements"].back()["walk_draws"] = walk["draws"]
		# The last visual move ends at the committed cell. Earlier cinematic paths
		# remain source pixels and do not write back to gameplay state.
		if last.has("motion"): last["motion"]["to"] = TacticalGridRules.cell_pixel(actor["coord"])
		elif last.has("install"): last["install"]["position"] = TacticalGridRules.cell_pixel(actor["coord"])
	return {"ok": true}


## `defer_birth` leaves an NPC's birth draws (carry, level adjustment) to `_npc_birth`, which
## the chain runs after its landings (the result carries "birth_pending").
static func install_actor(loop: Dictionary, spec: Dictionary, symbol: String, firing: int, action: int, request: Dictionary, defer_birth := false) -> Dictionary:
	var actor: Dictionary = spec["actor"].duplicate(true)
	var registered: bool = spec["kind"] == "registered_player"
	var id := str(actor["id"]) if registered else "%s_script_%d_%d" % [actor["class_id"], firing, action]
	var existing := WinfailConditions.unit(loop, id)
	if not existing.is_empty():
		if not registered or existing["actor_id"] != spec["source_actor_id"]: return {"ok": false, "reason": "script_actor_id_collision"}
		return {"ok": true, "unit_id": id, "created": false}
	actor["id"] = id
	actor["defeated"] = false
	var record := {"policy": POLICY, "symbol": symbol, "firing_index": firing, "action_index": action, "kind": spec["kind"]}
	if registered:
		var grown := InitialRosterGrowthRules.prepare_player(actor, loop["equipment_items"])
		if not grown["ok"]: return grown
		actor = grown["actor"]
		# SID_PLAYERn is born inside its construction (0x40805d), before the landing draws.
		InitialRosterGrowthRules.draw_frame_delay(loop, actor)
		record["player_growth"] = grown["receipt"]
		# A carried member is already registered: 0x407ec0 copies no template over its record,
		# so the insert takes the carried record with the ST this entry left it (CampaignCarryRules).
		var carried: Dictionary = loop.get("campaign_carry_receipt", {}).get("unfielded_stamina", {})
		if carried.has(id): actor["stamina"] = int(carried[id])
		var carried_record: Variant = loop.get("campaign_carry_receipt", {}).get(CampaignCarryRules.UNFIELDED, {}).get(id)
		if carried.has(id) and carried_record is Dictionary:
			var carried_error := CampaignCarryRules.apply_unfielded_record(loop, actor, carried_record, int(carried[id]))
			if carried_error != "": return {"ok": false, "reason": "carried_record_" + carried_error}
			record["carried_record"] = true
		# A reserve member (registration removed, live record kept) re-installs with its record.
		var reserve: Dictionary = loop.get("campaign_carry_receipt", {}).get(CampaignCarryRules.RESERVE, {})
		if reserve.has(id):
			var reserve_error := CampaignCarryRules.apply_reserve_record(loop, actor, reserve[id])
			if reserve_error != "": return {"ok": false, "reason": "reserve_record_" + reserve_error}
			record["reserve_record"] = true
	else:
		if request.is_empty(): return {"ok": false, "reason": "missing_npc_script_insert"}
		request["unit_id"] = id
		if request.get("wait_round_set", false): actor["ai_wait_remaining"] = int(request["wait_round"])
	actor["script_creation"] = record
	loop["units"].append(actor)
	for token in [spec["token"]] + spec["aliases"]:
		var all: Array = WinfailConditions.units_for_token(loop, token)
		var serial := 1 if registered else all.size()
		loop["winfail_runtime"]["actor_bindings"]["%s/%d" % [token, serial]] = id
	if not registered and defer_birth: return {"ok": true, "unit_id": id, "created": true, "birth_pending": true}
	if not registered:
		var born := _npc_birth(loop, id, request)
		if not born["ok"]: return born
	return {"ok": true, "unit_id": id, "created": true}


## An NPC's birth draws: 0x407cc0 draws the frame delay (0x407dba), rolls a pmEnemy's carry
## (0x407c40) on the global stream, then the level adjustment 0x40e870 draws. The grown record replaces the live one in place.
static func _npc_birth(loop: Dictionary, id: String, request: Dictionary) -> Dictionary:
	var index := 0
	while str(loop["units"][index]["id"]) != id: index += 1
	var actor: Dictionary = loop["units"][index]
	InitialRosterGrowthRules.draw_frame_delay(loop, actor)
	if BattleRewardRules.install_carry(loop, actor) != "": return {"ok": false, "reason": "script_carry_inventory_full"}
	var grown := ReinforcementGrowthRules.prepare(loop, actor, request)
	if not grown["ok"]: return grown
	loop["units"][index] = grown["actor"]
	loop[GlobalRandomStream.LOOP_KEY] = grown["rng"]
	return {"ok": true}


static func _complete_departure_request(runtime: Dictionary, key: String, firing: int, name: String, args: Array, id: String) -> void:
	for request_value in runtime.get("departure_requests", []):
		var request: Dictionary = request_value
		if str(request.get("key", "")) != key or int(request.get("firing_index", -1)) != firing or str(request.get("name", "")) != name or request.get("args", []) != args:
			continue
		if (request["unit_ids"] as Array).is_empty():
			request["unit_ids"] = [id]
			if (runtime["departed_unit_ids"] as Array).find(id) == -1:
				(runtime["departed_unit_ids"] as Array).append(id)
			return


static func _move(positions: Dictionary, touched: Array, row: Dictionary, id: String, target: Vector2i) -> void:
	row["motion"] = {"unit_id": id, "from": positions[id], "to": target}
	positions[id] = target
	if not touched.has(id): touched.append(id)


static func _actor_id(loop: Dictionary, token: String, serial: int, departed: Array) -> String:
	var ids: Array = WinfailConditions.units_for_token(loop, token)
	ids = ids.filter(func(id): return not departed.has(id) and not WinfailConditions.unit(loop, id).get("defeated", false) and not WinfailConditions.unit(loop, id).get("departed", false))
	return "" if ids.is_empty() else str(ids[clampi(serial - 1, 0, ids.size() - 1)])


static func _bindings(loop: Dictionary, departed: Array) -> Dictionary:
	var tokens := {}
	for key in loop["winfail_runtime"]["actor_bindings"]: tokens[str(key).get_slice("/", 0)] = true
	for spec in loop["script_actor_source"]["templates"].values(): tokens[spec["token"]] = true
	for actor in loop["units"]:
		if str(actor.get("class_id", "")).begins_with("Enemy"): tokens["SID_ENEMY" + str(actor["actor_id"])] = true
	var result := {}
	for token in tokens:
		var ids: Array = WinfailConditions.units_for_token(loop, token).filter(func(id): return not departed.has(id) and not WinfailConditions.unit(loop, id).get("defeated", false) and not WinfailConditions.unit(loop, id).get("departed", false))
		for serial in range(1, maxi(ids.size(), 1) + 1):
			var id := "" if ids.is_empty() else str(ids[serial - 1])
			result["%s/%d" % [token, serial]] = {"unit_id": id, "actor_id": str(WinfailConditions.unit(loop, id).get("actor_id", ""))}
	return result


## 0x44fbd0(obj, &x, &y), called on every install (0x450ee2) and walk destination: the
## requested cell is kept unless its word carries a unit or the hard block (& 0x74000) or it
## is a 0xff cell for a walker. Then a copy of the actor stands on it with that cell's word
## cleared to its low 12 bits (0x411940: height 0, no flags), floods 12 (0x40f440,
## mode 1 walking with terrain and height only, no unit blocks; mode 6 flying), the
## centre is cleared (0x40f520(0)) and 0x413900 takes the flooded unoccupied cell nearest
## (Manhattan) in row-major order, an equal one replacing the held one on rand() & 1, a
## cell with three hard-blocked neighbours skipped when rand(100) < 80 (side 0,
## 0x413740). No candidate keeps the requested cell.
static func nearest_landing(actor: Dictionary, requested: Vector2i, occupants: Array, loop: Dictionary) -> Dictionary:
	var size: Vector2i = loop["map_size"]
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	var origin := Vector2i(clampi(requested.x, 0, size.x - 1), clampi(requested.y, 0, size.y - 1))
	var candidate := actor.duplicate(true)
	candidate["coord"] = origin
	var taken: Dictionary = AINavigationRules.SkillTargetRules.Footprint.occupants(occupants)
	var tile: Dictionary = tiles.get(origin, {})
	var flying := bool(actor.get("traversal", {}).get("flying", false))
	var blocked: bool = taken.has(origin) or (int(tile.get("movement_flags", 0)) & AINavigationRules.HARD_BLOCK_FLAG) != 0 or (not flying and ActorTraversalRules.elevation(tile) == 255)
	if not blocked: return {"ok": true, "coord": origin, "draws": []}
	# 0x4119d0(x, y, 0) → 0x411940 keeps only the low 12 bits of the requested cell's word for
	# the flood: height 0, no flags, so a walker on a 0xff cell steps only onto neighbours
	# within the height rule and never onto the surrounding 0xff cells (static-derived, original
	# instructions executed on LEVEL034／038／080, original_script_entry.md).
	var flood_tiles := tiles.duplicate()
	var cleared: Dictionary = tile.duplicate()
	cleared["movement_flags"] = 0
	cleared["elevation"] = 0
	cleared["blocks_movement"] = false
	flood_tiles[origin] = cleared
	var flood := TacticalGridRules.movement_reachability_envelope(candidate, [], flood_tiles, size, LANDING_FLOOD_RADIUS)
	if not flood["ok"]: return {"ok": false, "reason": flood["reason"]}
	var large := int(actor.get("traversal", {}).get("size_type", 0)) != 0
	var cells: Array = []
	for cell in (flood["reachable_by_coord"].keys() + flood["transit_by_coord"].keys()):
		if taken.has(cell): continue
		# A 3x3 body also keeps the remake's footprint legality (0x413740 reads the centre only).
		if large:
			candidate["coord"] = cell
			if ActorTraversalRules.placement_error(candidate, occupants, tiles, size) != "": continue
		cells.append(cell)
	var rng: Variant = GlobalRandomStream.loop_source(loop) if GlobalRandomStream.valid(loop.get(GlobalRandomStream.LOOP_KEY)) else null
	var draws: Array = []
	var pick: Dictionary = AINavigationRules.nearest_stoppable(cells, origin, origin, rng, draws, AINavigationRules.neighbour_words(loop), AINavigationRules.blocker_mask(0), size)
	return {"ok": true, "coord": pick.get("cell", origin), "draws": draws}


static func state_error(loop: Dictionary) -> String:
	if not loop.has("script_actor_source"): return ""
	var source: Variant = loop["script_actor_source"]
	if not source is Dictionary or source.get("policy") != POLICY: return "invalid_script_actor_source"
	var error := source_error(source.get("templates"))
	if error != "": return error
	var records: Variant = loop.get("script_actor_transactions")
	var fired: Array = loop.get("winfail_runtime", {}).get("fired", [])
	if not records is Array or records.size() != fired.size(): return "pending_script_actor_transaction"
	var created := {}
	for index in range(records.size()):
		var row: Variant = records[index]
		if not row is Dictionary or row.get("policy") != POLICY or row.get("firing_index") != index or row.get("key") != fired[index].get("key") or not row.get("created_ids") is Array or not row.get("actions") is Array or not row.get("placements") is Array:
			return "invalid_script_actor_transaction"
		var program := WinfailCompiler.status_by_key(loop["winfail_script_rules"], row["key"])
		if program.is_empty() or row["actions"].size() != program["actions"].size(): return "script_actor_program_mismatch"
		var installed := {}
		for ordinal in range(row["actions"].size()):
			var step: Variant = row["actions"][ordinal]
			var original: Dictionary = program["actions"][ordinal]
			if not step is Dictionary or step.get("source_index") != ordinal + program["conditions"].size() or step.get("name") != original["name"] or step.get("args") != original["args"] or not step.get("bindings") is Dictionary:
				return "script_actor_action_mismatch"
			if step.has("install"):
				var install: Variant = step["install"]
				if not install is Dictionary or install.get("symbol") != original["args"][0] or not install.get("position") is Vector2i or not install.get("created") is bool: return "invalid_script_install_receipt"
				var spec: Dictionary = source["templates"].get(install["symbol"], {})
				if spec.is_empty() or install.get("actor_id") != spec["source_actor_id"] or WinfailConditions.unit(loop, str(install.get("unit_id", ""))).is_empty(): return "script_install_identity_mismatch"
				if install["created"]:
					if installed.has(install["unit_id"]): return "duplicate_script_install"
					installed[install["unit_id"]] = ordinal
			if step.has("motion"):
				var motion: Variant = step["motion"]
				if not motion is Dictionary or not motion.get("from") is Vector2i or not motion.get("to") is Vector2i or WinfailConditions.unit(loop, str(motion.get("unit_id", ""))).is_empty(): return "invalid_script_motion_receipt"
		if installed.keys() != row["created_ids"]: return "script_actor_creation_order_mismatch"
		for id in row["created_ids"]:
			var actor := WinfailConditions.unit(loop, id)
			var birth: Variant = actor.get("script_creation")
			if actor.is_empty() or created.has(id) or not birth is Dictionary or birth.get("policy") != POLICY or birth.get("firing_index") != index:
				return "invalid_script_created_identity"
			if birth.get("action_index") != installed[id]: return "script_birth_order_mismatch"
			var spec: Dictionary = source["templates"].get(birth.get("symbol", ""), {})
			if spec.is_empty() or spec.get("source_actor_id") != actor["actor_id"] or spec.get("kind") != birth.get("kind"): return "invalid_script_created_source"
			if birth["kind"] == "registered_player":
				var growth: Dictionary = birth.get("player_growth", {})
				if actor["id"] != spec["actor"]["id"] or growth.get("actor_id") != actor["actor_id"] or growth.get("unit_id") != id or growth.get("attributes") != _attributes(spec["actor"]): return "invalid_script_player_growth"
				if growth.get("level") != ReinforcementGrowthRules.Entry.inferred_level(growth["attributes"]) or int(actor["level"]) < int(growth["level"]): return "script_player_growth_rollback"
				for key in ReinforcementGrowthRules.Entry.KEYS:
					if int(actor["combat_profile"][key]) < int(growth["attributes"][key]): return "script_player_attribute_rollback"
			elif not actor.has("entry_growth"):
				return "invalid_script_npc_growth"
			created[id] = true
		var placed := {}
		for placement in row["placements"]:
			if not placement is Dictionary or not placement.get("requested") is Vector2i or not placement.get("coord") is Vector2i or not placement.get("adjusted") is bool or placed.has(placement.get("unit_id")) or WinfailConditions.unit(loop, str(placement.get("unit_id", ""))).is_empty(): return "invalid_script_placement_receipt"
			if placement["adjusted"] != (placement["coord"] != placement["requested"]): return "inconsistent_script_landing"
			var coord: Vector2i = placement["coord"]
			if coord.x < 0 or coord.y < 0 or coord.x >= loop["map_size"].x or coord.y >= loop["map_size"].y: return "script_landing_outside_map"
			placed[placement["unit_id"]] = true
	for actor in loop["units"]:
		if actor.has("script_creation") and not created.has(actor["id"]): return "unrecorded_script_actor"
	return ""


static func _attributes(actor: Dictionary) -> Dictionary:
	var attributes := {}
	for key in ReinforcementGrowthRules.Entry.KEYS: attributes[key] = int(actor["combat_profile"][key])
	return attributes

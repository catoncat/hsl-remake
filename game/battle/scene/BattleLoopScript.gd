extends RefCounted
## Battle loop script progression: `_resolve_outcome` is the one seam that, after every
## settled action, consumes the scenario script's pending transactions on the loop —
## fired actor installs (ScriptActorCreationRules), event wait counters (ScriptWaitRules),
## departures (BattlePresenceRules), winfail reinforcement pressure
## (`_maintain_script_pressure` materializing `reinforcement_deficits` at the spawn
## cells) — then asks the scenario rule adapter for the victory state and freezes the
## loop on a terminal outcome after the adapter has committed the deciding status' result
## chain. Static functions over the one loop dictionary; BattlePlayLoop forwards to
## them and stays the single mutable battle-state owner. The winfail interpreter itself
## (WinfailScenarioRules and its three modules) is reached only through
## BattleScenarioRuleAdapter.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_departure.md; static-derived docs/evidence_packets/static_reverse/original_script_wait.md; static-derived docs/evidence_packets/static_reverse/original_player_install.md; static-derived docs/evidence_packets/static_reverse/original_auto_growth.md; provisional (reinforcement spawn-cell fill order and nearest-legal landing, outcome commit ordering — docs/architecture/BATTLE_SYSTEMS.md#winfailscenariorulesgd); remake-invented (one-transaction materialization: a failed proposal leaves no partial actors)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Rewards = preload("res://game/battle/scene/BattleLoopRewards.gd")
const AI = preload("res://game/battle/scene/BattleLoopAI.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const TraversalRules = preload("res://game/sim/ActorTraversalRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const ScriptWait = preload("res://game/sim/ScriptWaitRules.gd")
const ReinforcementGrowth = preload("res://game/sim/ReinforcementGrowthRules.gd")
const ScriptActors = preload("res://game/sim/ScriptActorCreationRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const SharedRecord = preload("res://game/sim/SharedRecordRules.gd")


static func _resolve_outcome(next: Dictionary) -> Dictionary:
	# Pieces sharing one live record (level 12／26 hulls) settle the action's HP into one pool.
	SharedRecord.sync(next)
	if BattleOutcome.decided(next):
		return next
	_consume_script_actors(next)
	if not next["scenario_ok"]: return next
	var old_current := str(CoreTurnQueue.current(next["turn_queue"]).get("id", ""))
	_consume_script_waits(next)
	if not next["scenario_ok"]: return next
	_consume_script_departures(next)
	if not next["scenario_ok"]: return next
	# A fired insertion is part of this action's script transaction. Materialize
	# it before a second action or clear-victory query can observe the old roster.
	# The separate first-battle pressure policy keeps its existing handoff seam.
	if next.get("rule_adapter") == "winfail":
		_maintain_script_pressure(next)
		if not next["scenario_ok"]: return next
	var result := BattleScenarioRuleAdapter.victory_state(next, next.get("escape_zone", []))
	if not result.is_empty():
		Loop._clear_extra_action(next)
		# Scenario rules record the deciding status and apply its result chain once
		# (next level event, hand-off carry, dialogue) before the loop freezes.
		var committed := BattleScenarioRuleAdapter.commit_outcome(next)
		for key in committed.keys():
			next[key] = committed[key]
		_consume_script_actors(next)
		if not next["scenario_ok"]: return next
		# The already-decided win/fail chain may itself order a retreat. Finish its
		# presence cleanup once, before freezing, without firing another victory.
		_consume_script_departures(next)
		_consume_script_waits(next)
		if not next["scenario_ok"]: return next
		next["battle_outcome"] = result
		next["interaction"] = "battle_result"
		next["selected_unit_id"] = ""
		next["pending_move"] = false
		next["command_menu"] = {"commands": []}
		if BattleOutcome.is_victory(result) and not next.get("settlement", {}).get("pending", []).is_empty():
			next["settlement"]["closed"] = false
		AI._prune_ai_calls(next)
	elif old_current != str(CoreTurnQueue.current(next["turn_queue"]).get("id", "")):
		return Loop._finish_ai_or_continue(next)
	return next


static func _consume_script_actors(loop: Dictionary) -> void:
	if not ScriptActors.pending(loop): return
	var result := ScriptActors.prepare(loop)
	if not result["ok"]:
		loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": result["reason"]}, true)
		return
	loop.merge(result["loop"], true)


static func _consume_script_waits(loop: Dictionary) -> void:
	if BattleOutcome.decided(loop): return
	var proposal := ScriptWait.prepare(loop)
	if not proposal["ok"]:
		loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": proposal["reason"]}, true)
		return
	for id in proposal["values"]: Loop._unit(loop, id)["ai_wait_remaining"] = proposal["values"][id]
	loop["script_wait_cursor"] = proposal["cursor"]
	loop["last_script_wait"] = proposal["receipt"]


static func _commit_departures(loop: Dictionary, ids: Array, source: String, key: String = "") -> bool:
	var proposal := Presence.prepare(loop, ids, source, key)
	if not proposal["ok"]:
		loop.merge({"scenario_ok": false, "scenario_error": proposal["reason"], "interaction": "scenario_error"}, true)
		return false
	if not proposal["changed"]: return false
	for change in proposal["units"]: Loop._unit(loop, change["id"]).merge(change["changes"], true)
	loop["turn_queue"] = proposal["queue"]
	loop["last_departure"] = proposal["receipt"]
	loop["departure_sequence"] = proposal["receipt"]["sequence"]
	if proposal["receipt"]["unit_ids"].has(loop["extra_action"]["owner_id"]): Loop._clear_extra_action(loop)
	if proposal["receipt"]["unit_ids"].has(loop.get("selected_unit_id", "")):
		loop.merge({"selected_unit_id": "", "interaction": "ai_resolving", "pending_move": false,
			"moved_this_action": false, "attacked_this_action": false, "command_menu": {"commands": []}, "give_session": {}}, true)
	AI._prune_ai_calls(loop)
	return true


static func _consume_script_departures(loop: Dictionary) -> void:
	var fired: Array = loop.get("winfail_runtime", {}).get("fired", [])
	for request in loop.get("winfail_runtime", {}).get("departure_requests", []):
		if not request is Dictionary or not request.get("unit_ids") is Array or not request.get("key") is String:
			loop.merge({"scenario_ok": false, "scenario_error": "invalid_script_departure", "interaction": "scenario_error"}, true)
			return
		var index: Variant = request.get("firing_index")
		if not index is int or index < 0 or index >= fired.size() or fired[index].get("key") != request["key"]:
			loop.merge({"scenario_ok": false, "scenario_error": "invalid_departure_firing", "interaction": "scenario_error"}, true)
			return
		_commit_departures(loop, request["unit_ids"], "winfail", request["key"])
		if not loop["scenario_ok"]: return


static func _maintain_script_pressure(loop: Dictionary) -> void:
	if BattleOutcome.decided(loop) or not loop.get("scenario_ok", false): return
	if BattleScenarioRuleAdapter.reinforcement_deficits(loop).is_empty(): return
	var proposed := Loop.copy(loop)
	_materialize_script_pressure(proposed)
	if not proposed["scenario_ok"]:
		loop.merge({"scenario_ok":false,"interaction":"scenario_error","scenario_error":proposed["scenario_error"]},true)
		return
	loop.merge(proposed,true)


static func _materialize_script_pressure(loop: Dictionary) -> void:
	var deficits := BattleScenarioRuleAdapter.reinforcement_deficits(loop)
	for template in loop.get("reinforcement_templates", []):
		var class_id := str(template["class_id"])
		var remaining := int(deficits.get(class_id, 0))
		for coord in loop.get("reinforcement_spawn_cells", []):
			if remaining <= 0:
				break
			if Loop.unit_id_at_coord(loop, coord) != "" or bool(TerrainEdits.tiles(loop).get(coord, {}).get("blocks_movement", false)):
				continue
			var size: Vector2i = loop["map_size"]
			if coord.x < 0 or coord.y < 0 or coord.x >= size.x or coord.y >= size.y:
				continue
			var recruit: Dictionary = template.duplicate(true)
			recruit["id"] = "%s_reinforcement_%d" % [class_id, loop["units"].size()]
			recruit["coord"] = coord
			recruit["grid_coord"] = coord
			recruit["hp"] = int(recruit["max_hp"])
			recruit["defeated"] = false
			if TraversalRules.placement_error(recruit, loop["units"], TerrainEdits.tiles(loop), size) != "":
				continue
			recruit["hit_bonus_accum"] = 0
			recruit["ai_call_target_id"] = ""
			AINavigationRules.initialize(recruit, loop["ai_profiles"]["actors"][recruit["actor_id"]]["profile"])
			# The birth 0x407cc0 rolls a pmEnemy's carry (0x407c40) before its level adjustment 0x40e870.
			recruit["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
			Rewards._initial_carry(loop, recruit)
			var insertion := ScriptWait.next_insert(loop, class_id)
			if insertion >= 0:
				var request: Dictionary = loop["winfail_runtime"]["inserts"][insertion]
				if request.get("wait_round_set", false):
					if not ScriptWait.valid_count(request["wait_round"]):
						loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": "invalid_insert_wait"}, true)
						return
					recruit["ai_wait_remaining"] = int(request["wait_round"])
				var growth := ReinforcementGrowth.prepare(loop, recruit, request)
				if not growth["ok"]:
					loop.merge({"scenario_ok":false,"interaction":"scenario_error","scenario_error":growth["reason"]},true)
					return
				recruit = growth["actor"]
				loop[ReinforcementGrowth.GlobalRandom.LOOP_KEY] = growth["rng"]
				request["unit_id"] = recruit["id"]
			loop["units"].append(recruit)
			remaining -= 1

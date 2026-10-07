extends RefCounted
## Data-driven, stateless interpreter for the winfail scripts that every battle
## seed already carries (`scripts.winfail`): win / fail / event statuses, each a
## leading condition chain followed by a result-action chain. It owns no battle
## state and only transforms the PlayLoop dictionary, like the level-52/53
## modules it generalises. Schema: hsl_winfail_script_rules.v1.
##
## This file is the facade and the outcome state machine (status arming, evaluation
## passes, terminal status, party wipe). Seed → rules is WinfailCompiler, condition
## reads WinfailConditions, result actions WinfailActions; all four are static modules
## over the same loop dictionary.
##
## Evidence: section/action structure, argument order and ACTION.H argument
## shapes are resource-derived. Condition polarity (<= for counts, >= for the
## round counter), one-shot status consumption, AND-combination of a leading
## condition prefix and the insert lifecycle are remake readings established by
## Second/ThirdBattle ScenarioRules and marked provisional in `claim_limits` (ids into
## docs/evidence_packets/static_reverse/winfail_claim_limits.md). The scan shape — one
## event started per scan, one rescan after an actExecWinFailProcess chain — is
## static-derived (original_round_display.md «Scan shape»).
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: static-derived docs/evidence_packets/static_reverse/original_check_targets.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_round_display.md
##   rules: static-derived docs/evidence_packets/static_reverse/winfail_claim_limits.md
##   rules: provisional
##     (MAX_PASSES bound, a fail chain with waiting actions read as ending first — ids in
##     docs/evidence_packets/static_reverse/winfail_claim_limits.md)
##   rules: remake-invented (party_wiped defeat rule — negative-evidence in original_check_targets.md §R8)

const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

## Remake guard on the actExecWinFailProcess rescan chain (one event per pass); the
## original's chain is unbounded. Its 20 event slots (0x44ee20 walks 0xe10 / 0xb4) bound a
## chain of distinct statuses; self re-arming chains (WINFAIL032 event 9: three gas
## objects) add a few. WINFAIL038's ten arrival／evacuation events chain end to end.
const MAX_PASSES := 32
## Shared defeat outcome: the controlled player fell (presentation labels are scenario-owned).
const DEFEAT_OUTCOME := BattleOutcome.DEFEAT_FALLEN
## Dialogue namespace of the deciding status' own actMessage lines (winfail_runtime.dialogue
## keys, the presentation's shown-story cursor); event statuses use their status key.
const TERMINAL_DIALOGUE_KEY := "terminal"
## Remake rule (no original-equivalence claim; the original has no non-script defeat path —
## negative-evidence in original_check_targets.md §R8): every player-controlled unit
## this battle fielded and still holds is defeated and no script status decided → defeat.
## Lowest priority; recorded as the resolution key so the battle end takes the ordinary
## defeat path while no script fail chain runs.
const PARTY_WIPE_KEY := "party_wiped"
const PARTY_WIPE_POLICY := "remake_party_wipe_defeat_v1"


## ---------------------------------------------------------------------------
## Loop state

static func initialize_script_state(battle: Dictionary, scenario: Dictionary, seed: Dictionary) -> Dictionary:
	var next := BattleLoopConfig.copy(battle)
	if not WinfailCompiler.seed_has_winfail(seed):
		# A battle level without a winfail script cannot run this module; fail
		# explicitly instead of quietly running another rule set.
		next["scenario_ok"] = false
		next["interaction"] = "scenario_error"
		next["scenario_error"] = "missing_winfail_script"
		return next
	var config: Dictionary = scenario.get("scenario_rules", {})
	var rules := WinfailCompiler.rules_from_seed(seed, int(config.get("cell_size", WinfailCompiler.DEFAULT_CELL_SIZE)))
	var opening: Dictionary = scenario.get("opening", {})
	next["winfail_script_rules"] = rules
	# Immutable presentation identity accompanies the original rule program. A
	# save must not replay its cursor against different lines/bindings after an
	# update. This is configuration, not another script execution state.
	var timelines: Dictionary = config.get("status_timelines", {})
	var playable: Array = []
	for key in timelines:
		if int(timelines[key].get("playable_event_count", 0)) > 0: playable.append(str(key))
	playable.sort()
	next["script_presentation_source"] = {"policy":"script_cursor_v1", "playable_keys":playable,
		"digest":var_to_bytes([timelines, opening]).hex_encode().sha256_text()}
	next["script_rule_source"] = "battle%03d_seed" % int(rules.get("source_level", 0))
	# Both tables live in scenario_rules (tools/hsltools/levels/battle.py LEVELS job_up_targets);
	# reading the templates from the scenario root left level 37 without a target.
	next["job_up_templates"] = (config.get("job_up_templates", {}) as Dictionary).duplicate(true)
	next["job_up_targets"] = (config.get("job_up_targets", {}) as Dictionary).duplicate(true)
	for kind in WinfailCompiler.STATUS_KINDS:
		next["%s_statuses" % kind] = (rules["initial_statuses"][kind] as Array).duplicate()
	var initial_overrides: Dictionary = scenario.get("scenario_rules", {}).get("initial_status_overrides", {})
	for kind in WinfailCompiler.STATUS_KINDS:
		if initial_overrides.get(kind) is Array:
			var normalized: Array = []
			for code in initial_overrides[kind]:
				normalized.append(int(code))
			next["%s_statuses" % kind] = normalized
	next["event_log"] = next.get("event_log", []).duplicate()
	next["script_flags"] = (next.get("script_flags", {}) as Dictionary).duplicate(true)
	var initial_ids := _initial_class_unit_ids(next, rules)
	var bindings := _opening_actor_bindings(next, opening)
	next["winfail_runtime"] = _new_winfail_runtime(next, rules, opening, config, bindings, initial_ids)
	next["next_level_event"] = WinfailCompiler.first_next_level_event(rules)
	# Which fired status actually wrote next_level_event ("" for the win-section
	# default above). The runtime ends an undecided battle only from the cutscene
	# of that status (WINFAIL073 event_2 / WINFAIL078 event_3 / WINFAIL900 event_4);
	# a dialogue-only event (WINFAIL010 event_6) must never hand off on the default.
	next["next_level_event_status"] = ""
	_record_token_resolution(next)
	WinfailActions.apply_story_player_state(next, seed)
	_refresh_objective(next)
	return next


## The ids of the opening units of each class a status inserts (class id -> unit ids).
static func _initial_class_unit_ids(next: Dictionary, rules: Dictionary) -> Dictionary:
	var initial_ids := {}
	for status in WinfailCompiler.all_statuses(rules):
		for insert_value in (status as Dictionary).get("inserts", []):
			var class_id := str((insert_value as Dictionary).get("class_id", ""))
			if class_id == "" or initial_ids.has(class_id):
				continue
			var ids: Array = []
			for unit_value in next.get("units", []):
				if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("class_id", "")) == class_id:
					ids.append(str((unit_value as Dictionary).get("id", "")))
			initial_ids[class_id] = ids
	return initial_ids


## Token -> unit id: the opening's actor bindings, then every registered-player template
## token and alias as `<token>/1`.
static func _opening_actor_bindings(next: Dictionary, opening: Dictionary) -> Dictionary:
	var bindings := {}
	for key in (opening.get("actor_bindings", {}) as Dictionary).keys():
		var binding: Variant = opening["actor_bindings"][key]
		if typeof(binding) != TYPE_DICTIONARY or str((binding as Dictionary).get("unit_id", "")) == "":
			continue
		var binding_dict: Dictionary = binding
		bindings[str(key)] = str(binding_dict.get("unit_id", ""))
	for spec in next.get("script_actor_source", {}).get("templates", {}).values():
		if spec["kind"] != "registered_player": continue
		for token in [spec["token"]] + spec["aliases"]:
			bindings[str(token) + "/1"] = str(spec["actor"]["id"])
	return bindings


## The fresh script interpreter runtime of a battle (hsl_winfail_runtime.v1).
static func _new_winfail_runtime(next: Dictionary, rules: Dictionary, opening: Dictionary, config: Dictionary, bindings: Dictionary, initial_ids: Dictionary) -> Dictionary:
	return {
		"schema": "hsl_winfail_runtime.v1",
		"actor_bindings": bindings,
		"speaker_resource_ids": (opening.get("speaker_resource_ids", {}) as Dictionary).duplicate(true),
		"player_token": str(config.get("player_token", "")),
		"initial_class_unit_ids": initial_ids,
		"static_enemy_counts": (config.get("static_enemy_counts", {}) as Dictionary).duplicate(true),
		"spawn_target": {},
		"item_requests": [],
		"story_object_wait_requests": [],
		"story_object_x_range_requests": [],
		"object_delete_requests": [],
		"player_x_range_delete_requests": [],
		"level_up_star_requests": [],
		"movie_requests": [],
		"inserts": [],
		"random_position_slots": {},
		"fired": [],
		"dialogue": [],
		"dead_messages": (rules["dead_messages"] as Dictionary).duplicate(true),
		"presentation_requests": [],
		"select_requests": [],
		"wait_requests": [],
		"carry_requests": [],
		"undead": [],
		"mode_changes": [],
		"fixed_position_changes": [],
		"fly_changes": [],
		"no_attack_changes": [],
		"exec_mode_changes": [],
		"system_arrival_position": {},
		"system_arrival_position_changes": [],
		"previous_insert_id_changes": [],
		"handoff_counter": 0,
		"serial_deadline": 0,
		# 0x42c640 writes dword 0x4c1bbc = 1: round 1, display baseline word 0 (unset).
		"round_display_baseline": 0,
		"deleted_player_codes": [],
		"job_up_changes": [],
		"walk_shape_changes": [],
		"departed_unit_ids": [],
		"departure_requests": [],
		"pending_world_flags": [],
		"unsupported_encountered": [],
		"unresolved_tokens": [],
		"token_resolution": {},
		"resolved": {},
		"pass_limit_hit": false,
	}


static func run_event_hooks(battle: Dictionary, attacked: bool = false) -> Dictionary:
	## One completed-action scan (0x407510 → 0x408370 → 0x44ee20). `attacked`: the
	## finishing actor attacked during this action, so the attacker global 0x4c1ce8 and
	## the attacked list 0x4c29a0 that 0x450840 cases 0x2a／0x6e／0x74 read still hold
	## that attack (both are reset when an action starts) — the only scan in which
	## actCheckPlayerAttacked, actCheckSerialPlayerAttacked and actCheckNotPlayerAttacker
	## can hold.
	return _evaluate(battle, "attack" if attacked else "round")


static func select_event_status(battle: Dictionary, event_code: int) -> Dictionary:
	## Resolve a formal-battle actSelectInsertEvent choice. The event status is
	## inserted into the same loop before its unconditional chain is evaluated;
	## presentation marks the resulting fired entry as inlined because the
	## coordinator splices that status timeline into the open choice cutscene.
	var next := BattleLoopConfig.copy(battle)
	var rules: Dictionary = next.get("winfail_script_rules", {})
	var runtime: Dictionary = next.get("winfail_runtime", {})
	var key := "event_%d" % event_code
	var status := WinfailCompiler.status_by_key(rules, key)
	if rules.is_empty() or runtime.is_empty() or status.is_empty():
		next["scenario_ok"] = false
		next["interaction"] = "scenario_error"
		next["scenario_error"] = "select_event_status_missing:%s" % key
		return next
	WinfailCompiler.status_slot_insert(next, "event", event_code)
	(runtime["select_requests"] as Array).append({"event_code": event_code, "status_key": key, "turn": int(next.get("turn", 1))})
	var before := (runtime.get("fired", []) as Array).size()
	next["winfail_runtime"] = runtime
	next = _evaluate(next, "selection")
	var selected_runtime: Dictionary = next.get("winfail_runtime", {})
	var fired: Array = selected_runtime.get("fired", [])
	for index in range(before, fired.size()):
		if typeof(fired[index]) == TYPE_DICTIONARY:
			(fired[index] as Dictionary)["presentation_inlined"] = true
	next["winfail_runtime"] = selected_runtime
	return next


static func reinforcement_deficits(battle: Dictionary) -> Dictionary:
	## {class_id: count} the PlayLoop should append now: inserts of fired statuses
	## not yet reflected by spawned units of that class (every unit of the class
	## that was not in the initial roster counts as spawned).
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	var result := {}
	for class_id in (runtime.get("spawn_target", {}) as Dictionary).keys():
		var owed := int(runtime["spawn_target"][class_id]) - spawned_reinforcement_count(battle, str(class_id))
		if owed > 0:
			result[str(class_id)] = owed
	return result


static func _script_actors_pending(battle: Dictionary) -> bool:
	## A fired status the PlayLoop has not yet run through ScriptActorCreationRules
	## (same test as ScriptActorCreationRules.pending, kept here so this module
	## stays free of that dependency): the roster is still pre-insertion.
	if not battle.has("script_actor_source"):
		return false
	var fired: Array = (battle.get("winfail_runtime", {}) as Dictionary).get("fired", [])
	return (battle.get("script_actor_transactions", []) as Array).size() < fired.size()


static func spawned_reinforcement_count(battle: Dictionary, class_id: String) -> int:
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	var initial: Array = (runtime.get("initial_class_unit_ids", {}) as Dictionary).get(class_id, [])
	var spawned := 0
	for unit_value in battle.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("class_id", "")) == class_id and initial.find(str(unit.get("id", ""))) == -1:
			spawned += 1
	return spawned


static func victory_state(battle: Dictionary, _escape_zone: Array = []) -> Dictionary:
	## Pure: the first holding fail／win status (_terminal_status decides a shared
	## scan), then the remake party-wipe defeat; `{}`
	## while the battle is ongoing. Attack-context conditions never decide here.
	var terminal := _terminal_status(battle)
	var outcome: Dictionary = terminal["outcome"]
	if outcome.is_empty() and party_wiped(battle):
		return DEFEAT_OUTCOME.duplicate()
	return outcome


static func party_wiped(battle: Dictionary) -> bool:
	## PARTY_WIPE_POLICY: the player-controlled units on the field (not script-removed
	## or departed) are non-empty and every one is defeated. Script fail
	## statuses decide first (_terminal_status); WINFAIL5NN names only 雷歐納德, so a
	## party fielded without him (levels 30-34) could otherwise be wiped with no verdict
	## and the enemies acting forever (autoplay dead_end party_wiped_no_defeat).
	if (battle.get("winfail_script_rules", {}) as Dictionary).is_empty():
		return false
	var departed: Array = (battle.get("winfail_runtime", {}) as Dictionary).get("departed_unit_ids", [])
	var fielded := 0
	for unit_value in battle.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("battle_actor_role", "")) != WinfailActions.PLAYER_MODE_ROLES[0x10000]:
			continue
		if bool(unit.get("departed", false)) or departed.find(str(unit.get("id", ""))) != -1:
			continue
		fielded += 1
		if not bool(unit.get("defeated", false)):
			return false
	return fielded > 0


static func commit_outcome(battle: Dictionary) -> Dictionary:
	## Optional mutation seam for the PlayLoop's outcome resolution: records the
	## deciding status and applies its result actions (next level event, deleted
	## player code, world flags, messages) once. victory_state stays pure.
	var next := BattleLoopConfig.copy(battle)
	var runtime: Dictionary = next.get("winfail_runtime", {})
	if runtime.is_empty() or not (runtime.get("resolved", {}) as Dictionary).is_empty():
		return next
	var terminal := _terminal_status(next)
	if (terminal["outcome"] as Dictionary).is_empty():
		if party_wiped(next):
			runtime["resolved"] = {"key": PARTY_WIPE_KEY, "kind": "fail", "code": -1, "outcome": DEFEAT_OUTCOME.duplicate(), "policy": PARTY_WIPE_POLICY}
			next["winfail_runtime"] = runtime
		return next
	var status: Dictionary = terminal["status"]
	runtime["resolved"] = {"key": status["key"], "kind": status["kind"], "code": int(status["code"]), "outcome": (terminal["outcome"] as Dictionary).duplicate()}
	next["winfail_runtime"] = runtime
	# The deciding status stays listed so objective_board keeps its label after the
	# loop froze; its result chain runs once under the terminal dialogue key.
	WinfailActions.apply_actions(next, status, "terminal", TERMINAL_DIALOGUE_KEY)
	return next


static func story_dialogue_messages(battle: Dictionary) -> Array[Dictionary]:
	## Ordered {key, speaker_id, message_id, actor_token}: fired event messages in
	## fire order, then the outcome status's own actMessage lines. Resource ids
	## only; the caller de-duplicates by key+id. The fallen unit's death word is
	## not repeated here: the original's two readers of live +0x14 (0x43ef91 /
	## 0x4434b2) both speak at death by the dying actor, which BattleAftermath
	## already does from the unit's dead_message (R29／R31); the battle end has
	## no reader of its own.
	var result: Array[Dictionary] = []
	var rules: Dictionary = battle.get("winfail_script_rules", {})
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	if rules.is_empty() or runtime.is_empty():
		return result
	var speakers: Dictionary = runtime.get("speaker_resource_ids", {})
	for message_value in runtime.get("dialogue", []):
		var message: Dictionary = message_value
		_append_message(result, message, str(message.get("key", "")), speakers)
	var outcome := BattleOutcome.of(battle)
	if outcome.is_empty():
		return result
	var terminal := _terminal_status(battle, outcome)
	if terminal.get("status", {}).is_empty():
		return result
	var status: Dictionary = terminal["status"]
	var already: Array = runtime.get("dialogue", [])
	for action_value in status.get("actions", []):
		var action: Dictionary = action_value
		if str(action["name"]) != "actMessage" or (action["args"] as Array).size() < 3:
			continue
		var record := {"key": TERMINAL_DIALOGUE_KEY, "actor_token": _arg(action["args"], 0), "message_id": _arg(action["args"], 2)}
		if WinfailActions.dialogue_has(already, TERMINAL_DIALOGUE_KEY, record["message_id"]) or not WinfailActions.speaker_present(battle, record["actor_token"]):
			continue
		_append_message(result, record, TERMINAL_DIALOGUE_KEY, speakers)
	return result


static func objective_board(battle: Dictionary) -> Dictionary:
	## {"win": rows, "fail": rows, "event": rows} from the `message = SID,ID`
	## labels of the currently armed statuses ("if assign, show in Win Board";
	## e.g. winfail051 event 3 labels the hold phase with 361). Disarmed
	## statuses drop off the board, unlike the hand-written level modules.
	var rules: Dictionary = battle.get("winfail_script_rules", {})
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	var board := {"win": [], "fail": [], "event": []}
	if rules.is_empty():
		return board
	var speakers: Dictionary = runtime.get("speaker_resource_ids", {})
	for kind in WinfailCompiler.STATUS_KINDS:
		var rows: Array[Dictionary] = []
		var armed: Array = battle.get("%s_statuses" % kind, [])
		for status_value in rules["statuses"][kind]:
			var status: Dictionary = status_value
			if armed.find(int(status["code"])) == -1:
				continue
			var label: Dictionary = status.get("result_message", {})
			if label.is_empty():
				continue
			_append_message(rows, label, kind, speakers)
		board[kind] = rows
	return board


static func result_message_id(battle: Dictionary, outcome: Dictionary) -> String:
	## winfail `message = SID,ID` board label of the status that produced `outcome`.
	if outcome.is_empty():
		return ""
	var terminal := _terminal_status(battle, outcome)
	var status: Dictionary = terminal.get("status", {})
	if status.is_empty():
		return ""
	return str((status.get("result_message", {}) as Dictionary).get("message_id", ""))


## ---------------------------------------------------------------------------
## Evaluation

static func _evaluate(battle: Dictionary, context: String) -> Dictionary:
	var next := BattleLoopConfig.copy(battle)
	var rules: Dictionary = next.get("winfail_script_rules", {})
	var runtime: Dictionary = next.get("winfail_runtime", {})
	if rules.is_empty() or runtime.is_empty() or BattleOutcome.decided(next):
		return next
	# static-derived (original_round_display.md «Scan shape»): the event walk of
	# 0x44ee20 returns after the first armed status whose conditions hold — it disarms
	# that slot and starts its chain (0x453ac0), so one scan starts at most one event.
	# A chain that ran actExecWinFailProcess (case 0x44 sets 0x4c1d44) makes the status
	# object rescan once when it ends (0x453b69 → 0x453b7c call 0x44ee20): that is the
	# next pass, again starting at most one event.
	var passes := 0
	var again := true
	while again and passes < MAX_PASSES:
		passes += 1
		if passes == 2 and context in ["round", "attack"]:
			# 0x407510 bumps the handoff counter 0x4c1ad4 right after its scan started a
			# chain; the chain's own rescan (0x453b7c) comes frames later, so it reads c + 1.
			_bump_handoff_counter(runtime)
		again = false
		# 0x44ed70 walks the 20 slots in index order (static-derived), not the sections.
		for code_value in WinfailCompiler.status_slots(next, "event"):
			var code := int(code_value)
			var status := WinfailCompiler.status_by_key(rules, "event_%d" % code) if code != -1 else {}
			if status.is_empty():
				continue
			if not WinfailConditions.conditions_hold(next, status, context):
				continue
			if _self_rearming(status) and not _inserts_settled(next, status):
				# provisional: a self re-arming insert event waits for its previous
				# recruit to land before asking for the next one.
				continue
			WinfailCompiler.status_slot_disarm(next, "event", code)
			again = WinfailActions.apply_actions(next, status, context)
			break
	if passes == 1 and context in ["round", "attack"]:
		_bump_handoff_counter(runtime)
	if again:
		next["winfail_runtime"]["pass_limit_hit"] = true
	# Record the deciding win/fail status when the same pass makes one hold, so
	# next_level_event and the result actions are committed before the PlayLoop
	# freezes the outcome. victory_state itself stays pure.
	# Pending actor creation is committed by the sole PlayLoop next. Deciding a
	# clear result from the pre-insertion roster would freeze an obsolete outcome;
	# likewise a fired status whose script actors (actInsertStoryObject and
	# friends) are not created yet must not let actCheckPlayer/actCheckEnemy read
	# a bound-but-uncreated unit as fallen (WINFAIL007 event 2 inserts SID_雪拉 and
	# arms fail 1 on her in the same section).
	if (next["winfail_runtime"].get("resolved", {}) as Dictionary).is_empty() and reinforcement_deficits(next).is_empty() and not _script_actors_pending(next):
		var terminal := _terminal_status(next)
		if not (terminal["outcome"] as Dictionary).is_empty():
			next = commit_outcome(next)
	_refresh_objective(next)
	return next


static func _bump_handoff_counter(runtime: Dictionary) -> void:
	## `inc word [0x4c1ad4]` in 0x407510: one per completed-action handoff (u16).
	runtime["handoff_counter"] = (int(runtime.get("handoff_counter", 0)) + 1) & 0xffff


static func _terminal_status(battle: Dictionary, wanted_outcome: Dictionary = {}) -> Dictionary:
	## {status, outcome}; the first holding win and fail status of one scan, decided by
	## _win_chain_first_tick; outcome `{}` while ongoing. With
	## `wanted_outcome` set (dialogue / board lookups after the loop froze), the
	## recorded resolution wins, then the first armed status of the matching kind.
	var rules: Dictionary = battle.get("winfail_script_rules", {})
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	if rules.is_empty():
		return {"status": {}, "outcome": {}}
	var resolved: Dictionary = runtime.get("resolved", {})
	if str(resolved.get("key", "")) == PARTY_WIPE_KEY and (wanted_outcome.is_empty() or wanted_outcome == DEFEAT_OUTCOME):
		# The remake party wipe owns the defeat: no script fail status (its dead message
		# and board label name a member who may not even be fielded) speaks for it.
		return {"status": {}, "outcome": DEFEAT_OUTCOME.duplicate()}
	if not resolved.is_empty() and (wanted_outcome.is_empty() or resolved.get("outcome", {}) == wanted_outcome):
		var status := WinfailCompiler.status_by_key(rules, str(resolved.get("key", "")))
		if not status.is_empty():
			return {"status": status, "outcome": (resolved["outcome"] as Dictionary).duplicate()}
	if wanted_outcome.is_empty():
		var started := {}
		for kind in ["win", "fail"]:
			# 0x44ebf0／0x44ecb0 walk the 10 slots in index order and start the first
			# holding status (static-derived).
			for code_value in WinfailCompiler.status_slots(battle, kind):
				var status := WinfailCompiler.status_by_key(rules, "%s_%d" % [kind, int(code_value)]) if int(code_value) != -1 else {}
				if status.is_empty() or _pending_enemy_count_result(battle, status): continue
				if not WinfailConditions.conditions_hold(battle, status, "round"):
					continue
				started[kind] = status
				break
		if started.has("win") and started.has("fail"):
			# static-derived (0x453ac0 → 0x45e307(…, 799, 0) appends each status object at
			# the tail of its plane list; 0x45f5f7 ticks head to tail): the win object runs
			# first each frame, and the first of 0x42cc10／0x42cbd0 to run decides
			# (0x4c1b00 & 0x38000000). The win decides only when its chain reaches
			# actSetNextPlayLevelEvent (case 0x2b calls 0x42cc10) or its end within the
			# first tick; otherwise the fail chain ends first. provisional: a fail chain
			# with its own waiting actions is still read as ending first.
			var winner: Dictionary = started["win"] if _win_chain_first_tick(started["win"]) else started["fail"]
			return {"status": winner, "outcome": outcome_for(winner)}
		for kind in ["fail", "win"]:
			if started.has(kind):
				return {"status": started[kind], "outcome": outcome_for(started[kind])}
		return {"status": {}, "outcome": {}}
	var kind := "fail" if BattleOutcome.is_defeat(wanted_outcome) else "win"
	var armed_now: Array = battle.get("%s_statuses" % kind, [])
	for status_value in rules["statuses"][kind]:
		var status: Dictionary = status_value
		if _pending_enemy_count_result(battle, status): continue
		if outcome_for(status) == wanted_outcome and (armed_now.find(int(status["code"])) != -1 or WinfailConditions.conditions_hold(battle, status, "round")):
			return {"status": status, "outcome": wanted_outcome.duplicate()}
	for status_value in rules["statuses"][kind]:
		var status: Dictionary = status_value
		if _pending_enemy_count_result(battle, status): continue
		if outcome_for(status) == wanted_outcome:
			return {"status": status, "outcome": wanted_outcome.duplicate()}
	return {"status": {}, "outcome": {}}


## Result tokens the VM 0x450840 runs without ending its tick (their case jumps back to
## the token loop 0x4511e6／0x4511e9; static-derived): every other token yields the frame.
const NON_YIELDING_RESULT_TOKENS := [
	"actWalkAndDelete",  # 4
	"actPlaySound",  # 15
	"actDeleteFailStatus",  # 26
	"actSetTownExecEvent",  # 70
	"actDeletePlayerCode",  # 71
	"actSetTownExitExecEvent",  # 98
	"actAddOverScore",  # 128
	"actBMSetPointEvent",  # 136
	"actBMSetPointEncounterRatio",  # 137
]


static func _win_chain_first_tick(status: Dictionary) -> bool:
	## The win chain reaches actSetNextPlayLevelEvent or its end in its first tick.
	for action_value in status.get("actions", []):
		var name := str((action_value as Dictionary).get("name", ""))
		if name == "actSetNextPlayLevelEvent":
			return true
		if not NON_YIELDING_RESULT_TOKENS.has(name):
			return false
	return true


static func _pending_enemy_count_result(battle: Dictionary, status: Dictionary) -> bool:
	# Placement can defer a fired insertion. An enemy-count victory must observe
	# the completed roster; escape and defeat conditions remain independently live.
	if status.get("kind") != "win": return false
	var pending := reinforcement_deficits(battle)
	if pending.is_empty(): return false
	for condition in status.get("conditions", []):
		if condition.get("name") == "actCheckEnemyTotalNumber": return true
		if condition.get("name") != "actCheckEnemyNumber" or condition.get("args", []).size() < 2: continue
		var token := _arg(condition["args"], 0)
		# Serial-less SID_ENEMYnnn resolves the whole class, including new inserts.
		# Other bindings name existing instances, so an unrelated pending class
		# must not keep their already-satisfied result from being committed.
		if not token.begins_with("SID_ENEMY"): continue
		var digits := token.trim_prefix("SID_ENEMY")
		if digits.is_valid_int() and pending.has("Enemy%03d" % int(digits)): return true
	return false


static func outcome_for(status: Dictionary) -> Dictionary:
	## The outcome a compiled win／fail status decides: every fail status the shared
	## defeat, a win status the reason named by its head condition.
	if str(status["kind"]) == "fail":
		return DEFEAT_OUTCOME.duplicate()
	var conditions: Array = status.get("conditions", [])
	var head := str((conditions[0] as Dictionary).get("name", "")) if not conditions.is_empty() else ""
	match head:
		"actCheckPlayerArrivePos", "actCheckAnyPlayerArrivePos":
			return BattleOutcome.victory(BattleOutcome.REASON_ESCAPE)
		"actCheckEnemyTotalNumber":
			return BattleOutcome.victory(BattleOutcome.REASON_ENEMIES_CLEARED)
		"actCheckPlayer", "actCheckEnemy", "actCheckPlayerHPLow", "actCheckEnemyNumber":
			return BattleOutcome.victory(BattleOutcome.REASON_BOSS)
		_:
			return BattleOutcome.victory(BattleOutcome.REASON_SCRIPT)


static func _refresh_objective(next: Dictionary) -> void:
	## Presentation mirrors: the armed win statuses decide the objective phase
	## and the escape cells; nothing here is combat truth.
	var rules: Dictionary = next.get("winfail_script_rules", {})
	if rules.is_empty():
		return
	var armed: Array = next.get("win_statuses", [])
	var cells: Array = []
	var phase := "hold"
	var win_condition := ""
	for status_value in rules["statuses"]["win"]:
		var status: Dictionary = status_value
		if armed.find(int(status["code"])) == -1:
			continue
		var conditions: Array = status.get("conditions", [])
		if conditions.is_empty():
			continue
		var head: Dictionary = conditions[0]
		var args: Array = head["args"]
		var zone: Array = []
		if str(head["name"]) == "actCheckPlayerArrivePos" and args.size() >= 6:
			zone = [int(_arg(args, 2)), int(_arg(args, 3)), int(_arg(args, 4)), int(_arg(args, 5))]
		elif str(head["name"]) == "actCheckAnyPlayerArrivePos" and args.size() >= 4:
			zone = [int(_arg(args, 0)), int(_arg(args, 1)), int(_arg(args, 2)), int(_arg(args, 3))]
		if not zone.is_empty():
			phase = "escape"
			win_condition = "escape_player"
			for cell in WinfailCompiler.zone_cells(zone, int(rules.get("cell_size", WinfailCompiler.DEFAULT_CELL_SIZE))):
				if cells.find(cell) == -1:
					cells.append(cell)
		elif phase != "escape":
			phase = {"actCheckEnemyTotalNumber": "clear", "actCheckPlayer": "defeat_boss", "actCheckEnemy": "defeat_boss", "actCheckPlayerHPLow": "defeat_boss"}.get(str(head["name"]), "script")
			win_condition = str(head["name"])
	next["objective_phase"] = phase
	next["win_condition"] = win_condition
	next["escape_zone_cells"] = cells
	if not cells.is_empty():
		var escape: Array = []
		for cell in cells:
			escape.append(Vector2i(int(cell[0]), int(cell[1])))
		next["escape_zone"] = escape


static func _record_token_resolution(next: Dictionary) -> void:
	## Initialization-time map of every actor token the script names → how it
	## resolves against the current roster. Diagnostics for the integrator; the
	## evaluation itself stays pure.
	var runtime: Dictionary = next["winfail_runtime"]
	var rules: Dictionary = next["winfail_script_rules"]
	for status in WinfailCompiler.all_statuses(rules):
		var records: Array = (status as Dictionary).get("conditions", []).duplicate()
		records.append_array((status as Dictionary).get("actions", []))
		for record_value in records:
			var record: Dictionary = record_value
			for arg in record.get("args", []):
				var token := str(arg)
				if not token.begins_with("SID_") and WinfailCompiler.NARRATION_TOKENS.find(token) == -1:
					continue
				if (runtime["token_resolution"] as Dictionary).has(token):
					continue
				var source := WinfailConditions.token_source(next, token)
				runtime["token_resolution"][token] = {"source": source, "unit_ids": WinfailConditions.units_for_token(next, token)}
				if source == "unresolved":
					WinfailActions.record_unresolved(runtime, token, str((status as Dictionary).get("key", "")))


static func _self_rearming(status: Dictionary) -> bool:
	if (status.get("inserts", []) as Array).is_empty():
		return false
	for action_value in status.get("actions", []):
		var action: Dictionary = action_value
		if str(action["name"]) == "actInsertEventStatus" and (action["args"] as Array).size() >= 1 and int(_arg(action["args"], 0)) == int(status["code"]):
			return true
	return false


static func _inserts_settled(battle: Dictionary, status: Dictionary) -> bool:
	var deficits := reinforcement_deficits(battle)
	for insert_value in status.get("inserts", []):
		if deficits.has(str((insert_value as Dictionary).get("class_id", ""))):
			return false
	return true


static func _append_message(result: Array[Dictionary], message: Dictionary, key: String, speakers: Dictionary) -> void:
	var token := str(message.get("actor_token", ""))
	var message_id := str(message.get("message_id", ""))
	if message_id == "" or message_id == "-1":
		return
	var speaker_id := str(speakers.get(token, ""))
	var record := {"key": key, "speaker_id": speaker_id, "message_id": message_id, "actor_token": token}
	if WinfailCompiler.NARRATION_TOKENS.find(token) != -1:
		record["narration"] = true
	result.append(record)


## ---------------------------------------------------------------------------
## Facade: compile step, and the argument reader this file uses. Tests and other modules
## reach the condition／action／compiler seams on WinfailConditions／WinfailActions／
## WinfailCompiler directly.

static func action_supported(name: String) -> bool:
	return WinfailCompiler.action_supported(name)


static func canonical_action(name: String) -> String:
	return WinfailCompiler.canonical_action(name)


static func seed_has_winfail(seed: Dictionary) -> bool:
	return WinfailCompiler.seed_has_winfail(seed)


static func rules_from_seed(seed: Dictionary, cell_size: int = WinfailCompiler.DEFAULT_CELL_SIZE) -> Dictionary:
	return WinfailCompiler.rules_from_seed(seed, cell_size)


static func insert_walk_cells(rules: Dictionary) -> Array:
	return WinfailCompiler.insert_walk_cells(rules)


static func _arg(args: Array, index: int, default: String = "") -> String:
	return WinfailCompiler.arg(args, index, default)

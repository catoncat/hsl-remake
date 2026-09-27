extends "res://tests/support/TestSuite.gd"

## Winfail scan cadence through the PlayLoop (static-derived,
## docs/evidence_packets/static_reverse/original_round_display.md «Evaluation cadence»):
## every completed action runs its status tail (0x40b910), then 0x407510 scans
## win／fail／event statuses (0x408370 → 0x44ee20) before 0x4074a0 advances the
## queue and bumps the round counter at wrap. So (1) a round-N event of the live
## level 51 fires after round N's first completed action, not at the boundary;
## (2) a Wait re-reads statuses after its poison tick; (3) an item use re-reads
## statuses, and a win armed by the event it fires decides in that same action.
## Scan shape (same packet «Scan shape»): (4) the event walk of 0x44ee20 returns after
## the first status that fires, so level 51's two reinforcement events that one kill
## satisfies together start on two consecutive completed actions; (5) only a chain
## that ran actExecWinFailProcess rescans at once (0x453b7c), so a second holding event
## joins the same action only behind such a chain. Attack context (packet «Attack
## context»): (6) actCheckPlayerAttacked is read by the attack action's completion scan
## (0x450840 case 0x2a reads the attacker global 0x4c1ce8) — not right after the strike —
## and the next action's scan no longer sees that attack (0x4c1ce8 is cleared when an
## action starts).

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")

const SCENARIO_PATH := "res://content/battles/battle_051.json"


func _init() -> void:
	tag = "EVENT_CADENCE_TESTS"


func run() -> void:
	_round_event_after_first_completed_action()
	_wait_rereads_after_poison_tail()
	_item_use_rereads_and_decides()
	_one_event_per_scan()
	_exec_winfail_process_rescans()
	_attack_read_by_completion_scan()


func _battle() -> Dictionary:
	var loop := BattlePlayLoop.create([], "", BattleScenario.load_file(SCENARIO_PATH), 7)
	_assert_true(bool(loop.get("scenario_ok", false)), "battle_051 PlayLoop creates (%s)" % str(loop.get("scenario_error", "")))
	return BattlePlayLoop.begin_battle(loop)


func _complete_action(loop: Dictionary) -> Dictionary:
	## One completed action: the player's Wait, or an AI slot ended without a decision
	## (deterministic; no RNG, no strike, so no attack-context scan interferes).
	match str(loop.get("interaction", "")):
		"action_menu":
			return BattlePlayLoop.begin_wait_resolution(loop)
		"ai_resolving":
			return BattlePlayLoop._advance_current_actor(loop)
	_assert_true(false, "no completable action in %s (%s)" % [str(loop.get("interaction", "")), str(loop.get("scenario_error", ""))])
	return loop


func _fired(loop: Dictionary) -> Array:
	return (loop.get("winfail_runtime", {}) as Dictionary).get("fired", [])


func _fired_entry(loop: Dictionary, key: String) -> Dictionary:
	for entry in _fired(loop):
		if str((entry as Dictionary).get("key", "")) == key:
			return entry
	return {}


func _reach_player(loop: Dictionary) -> Dictionary:
	var next := loop
	for _step in range(64):
		if str(next.get("interaction", "")) == "action_menu":
			return next
		next = _complete_action(next)
	_assert_true(false, "the player's action menu is reached")
	return next


func _round_event_after_first_completed_action() -> void:
	## WINFAIL051 event 2 = actCheckRoundNumber 4 (waiting lines), event 3 =
	## actCheckRoundNumber 6 (objective switch arming both win statuses).
	var loop := _battle()
	for spec in [[4, "event_2"], [6, "event_3"]]:
		var round_number: int = spec[0]
		var key: String = spec[1]
		var guard := 0
		while int(loop.get("turn", 1)) < round_number and guard < 256:
			_assert_true(_fired_entry(loop, key).is_empty(), "%s has not fired during round %d" % [key, int(loop.get("turn", 1))])
			loop = _complete_action(loop)
			guard += 1
		_assert_eq(int(loop.get("turn", 1)), round_number, "the queue wrapped into round %d" % round_number)
		_assert_true(_fired_entry(loop, key).is_empty(), "%s does not fire at the round-%d boundary (the boundary scan still reads %d)" % [key, round_number, round_number - 1])
		if key == "event_3":
			_assert_eq(loop.get("win_statuses", []), [], "the round-6 win statuses are not armed before round 6's first action")
		var fired_before := _fired(loop).size()
		loop = _complete_action(loop)
		var entry := _fired_entry(loop, key)
		_assert_true(not entry.is_empty(), "%s fires after round %d's first completed action" % [key, round_number])
		_assert_eq(int(entry.get("turn", 0)), round_number, "%s records round %d" % [key, round_number])
		_assert_eq(_fired(loop).size(), fired_before + 1, "%s is the only status that first action fires" % key)
		if key == "event_3":
			_assert_eq((loop.get("win_statuses", []) as Array).size(), 2, "round 6's first action arms both win statuses")


func _fired_keys(loop: Dictionary, from: int = 0) -> Array:
	var keys: Array = []
	for entry in _fired(loop).slice(from):
		keys.append(str((entry as Dictionary).get("key", "")))
	return keys


func _one_event_per_scan() -> void:
	## WINFAIL051 event 0 (actCheckEnemyNumber SID_ENEMY021 3) and event 1
	## (actCheckEnemyNumber SID_ENEMY026 2) both hold once three of the five 021 and one
	## of the two 026 are down. The original's scan starts event 0 only (first armed slot);
	## its recruit refills 021 to three, so the next completed action starts event 1.
	var loop := _reach_player(_battle())
	var downed := {"Enemy021": 3, "Enemy026": 1}
	for unit in loop["units"]:
		var class_id := str(unit.get("class_id", ""))
		if int(downed.get(class_id, 0)) > 0:
			BattlePlayLoop._set_unit_defeated(loop, str(unit["id"]), true)
			downed[class_id] = int(downed[class_id]) - 1
	_assert_eq(downed, {"Enemy021": 0, "Enemy026": 0}, "three 021 and one 026 are down")
	_assert_eq(loop.get("event_statuses", []), [0, 1, 2, 3], "both reinforcement events are armed")
	var before := _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_0"], "one completed action starts only the first holding event (0x44ee20 returns after it)")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy026"), 0, "the 026 recruit is not asked for in the same scan")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy021"), 1, "event 0's recruit landed")
	before = _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_1"], "the next completed action starts event 1")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy026"), 1, "event 1's recruit landed one action later")


func _exec_winfail_process_rescans() -> void:
	## Four unconditional events on one completion. Event 50 ends in
	## actExecWinFailProcess (case 0x44 → 0x4c1d44), so its chain's end rescans and
	## starts event 51; event 51 does not, so events 52 and 53 wait for the next two
	## completed actions.
	var loop := _custom_rules(_reach_player(_battle()), [
		_section("event", 50, [["actTRUE"], ["actExecWinFailProcess"]]),
		_section("event", 51, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 777]]),
		_section("event", 52, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 778]]),
		_section("event", 53, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 779]]),
	])
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop), ["event_50", "event_51"], "actExecWinFailProcess rescans once after its chain; the plain chain stops the scan")
	_assert_eq(loop.get("event_statuses", []), [52, 53], "the other holding events stay armed")
	var before := _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_52"], "the next completed action starts the next armed event only")
	before = _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_53"], "and the one after starts the last")


func _attack_read_by_completion_scan() -> void:
	var loop := _custom_rules(_reach_player(_battle()), [
		_section("event", 60, [["actCheckPlayerAttacked", "SID_PLAYER0", "SID_ENEMY021"], ["actMessage", "SID_PLAYER0", 1, 780]]),
	])
	var armed := BattlePlayLoop.choose_command(loop, "attack")
	var target_id := ""
	for cell in BattlePlayLoop.attack_cells(armed, "leonard"):
		if BattlePlayLoop.unit_id_at_coord(armed, cell) == "":
			for unit in armed["units"]:
				if str(unit.get("class_id", "")) == "Enemy021" and not bool(unit.get("defeated", false)):
					target_id = str(unit["id"])
					BattlePlayLoop._set_unit_coord(armed, target_id, cell)
					unit["max_hp"] = 9999  # survives the strike: no loot settlement to close first
					unit["hp"] = 9999
					break
			break
	_assert_true(target_id != "", "a 021 stands in Leonard's attack range")
	var turn_before := int(armed.get("turn", 1))
	var struck := BattlePlayLoop.attack_target(armed, target_id, zero)
	_assert_true(not (struck.get("last_attack", {}) as Dictionary).is_empty(), "Leonard's strike settled")
	_assert_true(_fired_entry(struck, "event_60").is_empty(), "the strike itself scans nothing (the original has no per-strike scan)")
	var done := BattlePlayLoop.finish_exhausted_action(struck)
	var entry := _fired_entry(done, "event_60")
	_assert_true(not entry.is_empty(), "the attack action's completion scan reads the attacker and fires the attacked event")
	_assert_eq(str(entry.get("context", "")), "attack", "the completion scan of an attack action runs in the attack context")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "it precedes the queue advance")
	_assert_eq(_fired_keys(done).count("event_60"), 1, "an attack action is scanned once")
	var rearmed := BattlePlayLoop.copy(done)
	(rearmed["event_statuses"] as Array).append(60)
	var before := _fired(rearmed).size()
	rearmed = _complete_action(rearmed)
	_assert_eq(_fired_keys(rearmed, before), [], "the next action's completion scan no longer sees Leonard's attack (0x4c1ce8 is cleared when an action starts)")


func _custom_rules(loop: Dictionary, sections: Array) -> Dictionary:
	## Replace the level's script with a fixture program on the same PlayLoop (the
	## opening bindings keep SID_PLAYER0/1 → leonard).
	var seed := {"schema": "hsl_battle_seed.v1", "level": 999, "evidence_tier": "test-fixture", "script_objects": [],
		"scripts": {"story": {"sections": []}, "winfail": {"sections": sections}}}
	var next := BattlePlayLoop.copy(loop)
	var rules := WinfailScenarioRules.rules_from_seed(seed)
	next["winfail_script_rules"] = rules
	for kind in ["win", "fail", "event"]:
		next["%s_statuses" % kind] = []
	for status in rules["statuses"]["event"]:
		(next["event_statuses"] as Array).append(int(status["code"]))
	return next


func _section(name: String, code: int, commands: Array) -> Dictionary:
	var actions: Array = []
	for command in commands:
		var args: Array = []
		for arg in command.slice(1):
			args.append(str(arg))
		actions.append({"primary": str(command[0]), "chain": [{"name": str(command[0]), "args": args}]})
	return {"index": 0, "name": name, "codes": [str(code)], "messages": [], "actions": actions}


func _wait_rereads_after_poison_tail() -> void:
	## Leonard at 60 % HP carries poison worth a fifth of his max HP. His Wait's tail
	## ticks him to 40 %; the completion scan that follows reads the new HP and fires
	## the HP-low event in the same action, before the queue advances.
	var loop := _custom_rules(_reach_player(_battle()), [_section("event", 40, [["actCheckPlayerHPLow", "SID_PLAYER0", 1, 50], ["actMessage", "SID_PLAYER0", 1, 777]])])
	_assert_eq(str(loop.get("selected_unit_id", "")), "leonard", "Leonard holds the action menu")
	var leonard := BattlePlayLoop._unit(loop, "leonard")
	var max_hp := int(leonard["max_hp"])
	leonard["hp"] = max_hp * 6 / 10
	var poisoned := StatusEffectRules.apply(leonard, "poison", 2, max_hp / 5)
	_assert_true(bool(poisoned.get("ok", false)), "Leonard is poisoned (%s)" % str(poisoned.get("reason", "")))
	leonard.merge(poisoned.get("changes", {}), true)
	var turn_before := int(loop.get("turn", 1))
	var after := BattlePlayLoop.choose_command(loop, "wait")
	_assert_true(int(BattlePlayLoop.unit(after, "leonard")["hp"]) * 100 <= 50 * max_hp, "the Wait's poison tick drops Leonard to half HP or below")
	var entry := _fired_entry(after, "event_40")
	_assert_true(not entry.is_empty(), "the HP-low event fires after the poisoned Wait completes")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "the scan precedes the queue advance (fired in round %d)" % turn_before)
	_assert_eq(str(entry.get("context", "")), "round", "a non-attack completion scans in the non-attack context")


func _item_use_rereads_and_decides() -> void:
	## Leonard moves onto a cell and drinks a potion. The item completion scans the
	## arrival event, whose chain arms an unconditional win: the battle is decided in
	## that action, in the same round, without waiting for a strike or a boundary.
	var loop := _reach_player(_battle())
	var leonard := BattlePlayLoop._unit(loop, "leonard")
	var cells: Array = BattlePlayLoop.movement_cells(BattlePlayLoop.choose_command(loop, "move"), "leonard")
	var destination: Vector2i = leonard["coord"]
	for cell in cells:
		if cell != leonard["coord"]:
			destination = cell
			break
	_assert_true(destination != leonard["coord"], "Leonard has a cell to move to")
	var px := destination.x * 32
	var py := destination.y * 32
	loop = _custom_rules(loop, [
		_section("event", 41, [["actCheckPlayerArrivePos", "SID_PLAYER0", 1, px, py, px + 31, py + 31], ["actInsertWinStatus", 0]]),
		_section("win", 0, [["actTRUE"]]),
	])
	leonard = BattlePlayLoop._unit(loop, "leonard")
	leonard["hp"] = maxi(1, int(leonard["max_hp"]) / 2)
	var inventory: Array = leonard["inventory"]
	if not inventory.has(241):
		inventory[inventory.find(0)] = 241
	loop = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop, "move"), destination)
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["coord"], destination, "Leonard moved onto the arrival cell")
	_assert_true(_fired_entry(loop, "event_41").is_empty(), "moving alone completes no action and scans nothing")
	var turn_before := int(loop.get("turn", 1))
	loop = BattlePlayLoop.use_item(loop, "241")
	_assert_true(int(loop.get("item_use_sequence", 0)) > 0, "the potion was used")
	var entry := _fired_entry(loop, "event_41")
	_assert_true(not entry.is_empty(), "the arrival event fires after the item use completes")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "the item completion scan precedes the queue advance")
	_assert_true(BattleOutcome.won(loop), "the win status the event armed decides in the same action")
	_assert_eq(int(loop.get("turn", 1)), turn_before, "the decided battle freezes before the queue advance")

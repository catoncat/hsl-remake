extends SceneTree
const GameOptions = preload("res://game/settings/GameOptions.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const run_ai_decision_tests = preload("res://tests/run_ai_decision_tests.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const AISkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const ActorInitializationRules = preload("res://game/sim/ActorInitializationRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const POISON := "magic:magicAIR:magicCode05"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	native_cases()
	movement_cases()
	registry_cases()
	route_cases()
	memory_cases()
	instance_cases()
	script_anchor_cases()
	pursuit_walk_cases()
	crowded_filter_cases()
	self_cast_flee_cases()
	attack_station_cases()
	terrain_range_cases()
	print("AI_NAVIGATION_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


static func fixture(mode: String = "detour") -> Dictionary:
	var mage := mode in ["cast", "empty_mp", "silenced", "empty_center", "cure_center"]
	var loop := run_ai_decision_tests.live_fixture("enemy026_1" if mage else "enemy021_1")
	var actor: Dictionary = loop["units"][0]
	if mage: TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["move_magic_use"] = true # Explicit mobile-navigation fixture.
	var target: Dictionary = loop["units"][1]
	var next: Dictionary = loop["units"][2]
	loop["map_size"] = Vector2i(20, 18)
	actor.merge({"coord": Vector2i(2, 5), "base_move_point": 2, "move_point": 2, "inventory": [0,0,0,0,0,0,0,0]}, true)
	target["coord"] = Vector2i(6, 5)
	next["coord"] = Vector2i(14, 14)
	var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"][actor["actor_id"]]["profile"]
	profile.merge({"find_range": 30, "ai_lock": 100, "ai_check_dying": 0, "ai_help_selfhp": 0, "ai_help_otherhp": 0, "ai_help_status": 0}, true)
	if mode == "detour":
		for y in range(1, 10): TestSuite.own(loop, "tiles")[Vector2i(3,y)] = {"blocks_movement": true, "move_cost": 1}
	elif mode == "unreachable":
		for y in range(18): TestSuite.own(loop, "tiles")[Vector2i(3,y)] = {"blocks_movement": true, "move_cost": 1}
		next["coord"] = Vector2i(1, 12)
	elif mode == "wait":
		actor["ai_wait_remaining"] = 3
		target["coord"] = Vector2i(14, 5)
	elif mode == "empty_mp":
		actor["mp"] = 0
	elif mode == "silenced":
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor, "no_magic", 2)["changes"], true)
	elif mode == "no_action":
		actor["no_attack"] = true
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor, "poison", 2, 7)["changes"], true)
		actor.merge(BattlePlayLoop.StatusEffectRules.Enhancements.apply(actor, "attack_up", 3, 20)["actor"], true)
		actor["combat_profile"] = BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"])["combat_profile"]
		actor.merge({"hit_bonus_accum": 4, "stamina": 30}, true)
	elif mode in ["empty_center", "cure_center"]:
		actor["coord"] = Vector2i(4, 5)
		actor["base_move_point"] = 0
		actor["move_point"] = 0
		actor["mp"] = 100
		actor["max_mp"] = 100
		var skill := run_support_magic_tests.CURE if mode == "cure_center" else POISON
		TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["supported_initial_ids"] = [skill]
		TestSuite.own(loop, "skill_book")["skills"][skill]["fields"]["use_ratio"] = "100"
		profile["ai_att_magic"] = 100
		profile["ai_help_status"] = 100
		var coords := [Vector2i(6,5), Vector2i(8,5), Vector2i(7,4), Vector2i(7,6)]
		target["coord"] = coords[0]
		next["coord"] = coords[1]
		for index in [2,3]:
			var extra := next.duplicate(true)
			extra["id"] = "navigation_target_%d" % index
			extra["coord"] = coords[index]
			extra["live_speed"] = 80 - index
			loop["units"].append(extra)
		if mode == "cure_center":
			actor["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY
			for unit in loop["units"].slice(1): unit.merge(BattlePlayLoop.StatusEffectRules.apply(unit, "poison", 2, 7)["changes"], true)
	for unit in loop["units"]:
		unit["grid_coord"] = unit["coord"]
		unit["ai_home_coord"] = unit["coord"]
		unit["ai_call_target_id"] = ""
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return loop


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_navigation.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var kind: String = input["kind"]
		if kind in ["circle", "diamond"]:
			check(int(AINavigationRules.within(Vector2i.ZERO, Vector2i(int(input["delta"][0]), int(input["delta"][1])), int(input["radius"]), kind == "diamond")) == int(row["native"]["value"]), "distance equals original normal return in all eight directions")
		elif kind == "wait":
			var loop := fixture("wait")
			var actor: Dictionary = loop["units"][0]
			actor.merge({"hp": int(input["hp"]), "max_hp": 100, "ai_wait_remaining": int(input["wait"]), "status_flags": int(input["flags"])}, true)
			actor["status_counters"] = {"poison": (7<<16)|2 if input["flags"] == 1 else 0, "paralysis": 2 if int(input["flags"]) & 4 else 0, "no_magic": 2 if input["flags"] == 2 else 0}
			var prepared := BattleLoopAI.prepare_ai_turn(loop, actor["id"])
			check(prepared["ok"], "native wait fixture preflight")
			if not prepared["ok"]: continue
			var selected := AINavigationRules.acquire(actor, loop["units"], prepared, zero)
			check(selected["wait_remaining"] == int(row["native"]["wait"]) and ("nearby" if selected["wait"] else "normal") == row["native"]["next"], "actual AI entry matches native waiting/wake boundary")
		elif kind == "retain":
			var loop := fixture("cast")
			var actor: Dictionary = loop["units"][0]
			actor["coord"] = Vector2i(5,5)
			actor["ai_home_coord"] = actor["coord"]
			actor["ai_target_id"] = loop["units"][1]["id"]
			loop["units"][1]["coord"] = actor["coord"] + Vector2i(int(input["delta"][0]), int(input["delta"][1]))
			if input["removed"]: loop["units"][1].merge({"hp": 0, "defeated": true}, true)
			var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"][actor["actor_id"]]["profile"]
			profile.merge({"find_range": 8, "ai_fixed": int(input["fixed"])}, true)
			var prepared := BattleLoopAI.prepare_ai_turn(loop, actor["id"])
			check(prepared["ok"], "native retained target fixture preflight")
			if prepared["ok"]: check(AINavigationRules.acquire(actor, loop["units"], prepared, zero)["retained"] == (row["native"]["next"] == "retain"), "retention matches original removal, diamond range and home-radius prefix")
		elif kind == "lock":
			var loop := fixture("plain")
			var actor: Dictionary = loop["units"][0]
			actor["ai_target_id"] = "leonard"
			# Leonard within one move of a strike: the station switch 0x40d8b0 starts at the held
			# slot, so whichever object the lock leaves held keeps it and the branch shows.
			loop["units"][1]["coord"] = Vector2i(5,5)
			loop["units"][2]["coord"] = Vector2i(1,5)
			TestSuite.own(loop, "ai_profiles")["actors"][actor["actor_id"]]["profile"]["ai_lock"] = int(input["rate"])
			var step := BattleLoopAI.ai_take_turn(loop, actor["id"], func(bound): return int(input["roll"])-1 if bound == 99 else 0)
			check(step["loop"]["scenario_ok"] and BattlePlayLoop.unit(step["loop"], actor["id"])["ai_target_id"] == ("leonard" if row["native"]["next"] == "retain" else "enemy023_1"), "actual retained-target branch matches every native lock probability boundary")


func registry_cases() -> void:
	# The object array 0x4c34c0: registered players in their PLAYERS slots (code − 1), every
	# other unit from slot 20 in roster order (0x407660; battle 051 r1 measured +0x88 values).
	var units := [{"id": "npc_owner", "registered_slot": -1}, {"id": "npc_foe", "registered_slot": -1}, {"id": "p3", "registered_slot": 2}, {"id": "p1", "registered_slot": 0}]
	var layout: Array = BattlePlayLoop.CoreTurnQueue.registry_layout(units)
	check(layout.size() == 22 and layout[0] == 3 and layout[1] == -1 and layout[2] == 2 and layout[20] == 0 and layout[21] == 1, "registry layout: PLAYERS code 1 in slot 0, code 3 in slot 2, NPCs from slot 20 in roster order: %s" % str(layout))
	var row := func(coord: Vector2i, side: int) -> Dictionary: return {"coord": coord, "removed": false, "hp": 10, "level": 1, "job": 1, "side": side, "sid": 0}
	var rows := [row.call(Vector2i(5,5), 0x10000), row.call(Vector2i(6,5), 0x20000), row.call(Vector2i(5,7), 0x20000), row.call(Vector2i(8,5), 0x20000)]
	var profile := {"find_type": 0, "find_flag": 0, "find_range": 20, "ai_att_special": 0, "ai_att_magic": 0, "ai_call_range": 0, "ai_fixed": 0, "job": 1, "find_no_id": -1}
	var keep_first := func(_bound: int) -> int: return 1
	var registered: Dictionary = AIDecisionRules.select_registered_target(rows, layout, 0, profile, 0, keep_first)
	check(registered["index"] == 3 and registered["native_index"] == 1, "0x40bb80 meets registry slot 0 (PLAYERS code 1) first, not the first roster row: %s" % str(registered))
	# Lock 0x441002..0x44102e: the dispatcher roll above ai_lock rescans and replaces a target
	# acquired this very turn (battle 051 r1 seed 1: 021_1 acquires Leonard, 83 > 39, holds 023_1).
	for roll in [51, 50]:
		var fresh := fixture("plain")
		var owner: Dictionary = fresh["units"][0]
		fresh["units"][2]["coord"] = Vector2i(2,10)   # out of this turn's reach, like Leonard
		TestSuite.own(fresh, "ai_profiles")["actors"][owner["actor_id"]]["profile"].merge({"find_type": 0, "find_flag": 0, "ai_lock": 50}, true)
		var coins := [1, 0]   # acquisition keeps Leonard (slot 0), the lock's rescan takes 023_1
		var scripted := func(bound: int) -> int:
			if bound == 99: return roll - 1
			return int(coins.pop_front()) if bound == 2 and not coins.is_empty() else 0
		var step := BattleLoopAI.ai_take_turn(fresh, owner["id"], scripted)
		var held: String = BattlePlayLoop.unit(step["loop"], owner["id"])["ai_target_id"]
		check(step["loop"]["scenario_ok"] and step["action"]["ai_decision"]["target_selection"]["reason"] == "new_target" and held == ("enemy023_1" if roll > 50 else "leonard"), "the lock also replaces a target acquired this turn (roll %d, ai_lock 50): %s" % [roll, held])


func route_cases() -> void:
	for mode in ["detour", "unreachable", "empty_mp", "silenced", "cast", "no_action"]:
		var loop := fixture(mode)
		var before := loop.duplicate(true)
		var after := BattlePlayLoop.step_ai_turn(loop, zero)
		check(after["scenario_ok"], "navigation commits: " + mode + " " + str(after.get("scenario_error", "")))
		if not after["scenario_ok"]: continue
		var action: Dictionary = after["last_ai_action"]
		check(after["last_ai_actions"].size() == 1 and after["turn_queue"]["index"] == 1 and after["selected_unit_id"] == "enemy023_1", "one navigation action hands off once: " + mode)
		check(loop == before, "planning/commit preserves the caller: " + mode)
		var path: Array = action.get("path", [])
		var costs := BattlePlayLoop.TacticalGridRules.path_costs(path, loop["units"], loop["tiles"], loop["units"][0]["id"])
		for index in range(1, path.size()):
			check(BattlePlayLoop.TacticalGridRules.manhattan(path[index], path[index-1]) == 1 and not loop["tiles"].get(path[index], {}).get("blocks_movement", false) and BattlePlayLoop.unit_id_at_coord(loop, path[index]) == "", "every path edge respects shared terrain, directions and occupied cells")
		check(path.is_empty() or (costs.size() == path.size() and int(costs.back()) <= int(loop["units"][0]["move_point"])), "actual path obeys this action's terrain and clearance budget")
		if mode == "detour": check(action["kind"] == "move" and BattlePlayLoop.TacticalGridRules.manhattan(action["to"], loop["units"][1]["coord"]) > BattlePlayLoop.TacticalGridRules.manhattan(loop["units"][0]["coord"], loop["units"][1]["coord"]), "AI takes the necessary step away from its target to pass a long wall")
		# 0x40bb80 reads positions, never routes: the walled-off closest enemy is the pick and
		# the armed unit walks toward its cell (0x440d5c／0x4111a0 needs no route to it).
		if mode == "unreachable": check(action["kind"] == "move" and action.get("toward") == "leonard" and BattlePlayLoop.unit(after, loop["units"][0]["id"])["ai_target_id"] == "leonard", "a sealed-off closest enemy is still the scan's pick and the pursuit walks toward it (0x40bb80 without reachability)")
		if mode in ["empty_mp", "silenced"]: check(not action.has("skill_id") and BattlePlayLoop.unit(after, loop["units"][0]["id"])["mp"] == loop["units"][0]["mp"], "unavailable magic falls through to a legal physical approach without a debit")
		if mode == "cast": check(action["kind"] == "move_then_attack" and action.has("magic_key") and not path.is_empty(), "moving cast joins the existing shared skill transaction")
		if mode == "no_action":
			check(action["kind"] == "wait" and not after.has("last_combat"), "no valid category waits honestly without a fake hit")
			var idle: Dictionary = BattlePlayLoop.unit(after, loop["units"][0]["id"])
			var refreshed := BattlePlayLoop.ProgressionRules.refresh_growth_stats(idle, after["equipment_items"])
			check(int(idle["status_flags"]) == 0 and idle["status_counters"] == BattlePlayLoop.StatusEffectRules.cleared_counters() and int(idle["hit_bonus_accum"]) == 0 and int(idle["stamina"]) == 0
				and idle["combat_profile"] == refreshed["combat_profile"] and int(idle["combat_profile"]["live_attack_damage"]) < int(loop["units"][0]["combat_profile"]["live_attack_damage"]),
				"a no_attack AI turn clears status, counters, +0xb0 and stamina, then refreshes (0x43f42d → 0x4483f0 → 0x4483c0／0x448840, 0x43f437)")
			var frozen := fixture("no_action")
			var npc: Dictionary = frozen["units"][0]
			npc.merge(BattlePlayLoop.StatusEffectRules.apply(npc, "paralysis", 2)["changes"], true)
			var bystander: Dictionary = frozen["units"][2]
			bystander.merge({"no_attack": true, "player_commandable": false}, true)
			bystander.merge(BattlePlayLoop.StatusEffectRules.apply(bystander, "poison", 2, 7)["changes"], true)
			var thawed := BattlePlayLoop.step_ai_turn(frozen, zero)
			check(thawed["scenario_ok"] and thawed["last_ai_action"].get("wait_reason") == "no_attack" and int(BattlePlayLoop.unit(thawed, npc["id"])["status_flags"]) == 0
				and int(BattlePlayLoop.unit(thawed, bystander["id"])["status_flags"]) == 0 and BattlePlayLoop.unit(thawed, bystander["id"])["status_counters"] == BattlePlayLoop.StatusEffectRules.cleared_counters(),
				"the no_attack clear is per-tick process code: it frees a paralyzed one before the gate (0x43f47b) and clears one that is not the current actor (0x43f42d before 0x407540)")
	var weighted := fixture("cast")
	TestSuite.own(weighted, "tiles")[Vector2i(3,5)] = {"move_cost": 8}
	var full := AINavigationRules.full_routes(weighted, weighted["units"][0])
	var route: Dictionary = full["reachable_by_coord"][Vector2i(5,5)]
	check(route["cost"] == 5 and not route["path"].has(Vector2i(3,5)), "full-map search finds a lower-cost detour instead of blindly following geometric distance")
	var pointless := fixture("cast")
	var caster: Dictionary = pointless["units"][0]
	caster["weapon_code"] = 0  # no ordinary attack: 0x409090 zero (a no_attack unit would end its turn at 0x43f413 before any cast)
	TestSuite.own(pointless, "skill_book")["actors"][caster["actor_id"]]["supported_initial_ids"] = [POISON]
	TestSuite.own(pointless, "skill_book")["skills"][POISON]["fields"]["use_ratio"] = "100"
	pointless["units"][1]["status_flags"] = 1
	pointless["units"][1]["status_counters"]["poison"] = (50 << 16) | 9
	var reconsidered := BattlePlayLoop.step_ai_turn(pointless, zero)
	# 0x40bb80 scores hp／level／distance, not the use of the caster's spells: the poisoned
	# closest foe stays the pick; with no useful cast and no ordinary attack the turn ends
	# (0x43ff1f／0x440041: 0x409090 zero → 0x441eb8; no_attack read as unarmed, provisional).
	check(reconsidered["scenario_ok"] and BattlePlayLoop.unit(reconsidered, caster["id"])["ai_target_id"] == "leonard" and reconsidered["last_ai_action"]["kind"] == "wait" and reconsidered["last_ai_action"].get("wait_reason") == "no_valid_action", "a pointless poison-only target is still held and the caster without an ordinary attack ends its turn")


func movement_cases() -> void:
	var grid = BattlePlayLoop.TacticalGridRules
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_movement.json"))
	for row in packet["flood"]:
		var input: Dictionary = row["input"]
		var origin := Vector2i(int(input["origin"][0]), int(input["origin"][1]))
		var size := Vector2i(int(input["size"][0]), int(input["size"][1]))
		var budget := int(input["budget"])
		var actor := {"id": "native-mover", "coord": origin, "move_point": budget, "hp": 100,
			"battle_actor_role": "player_controlled", "traversal": {"flying": false, "no_block": false, "size_type": 0}}
		var tiles := {}
		for cell in input["cells"]:
			tiles[Vector2i(int(cell[0]), int(cell[1]))] = {"move_cost": 1, "blocks_movement": (int(cell[2]) >> 24) == 0xff, "movement_flags": int(cell[2]) & grid.OBSTACLE_MASK}
		var envelope: Dictionary = grid.movement_reachability_envelope(actor, [actor], tiles, size)
		var expected: Array = row["native"]
		for y in range(expected.size()):
			for x in range(expected[y].size()):
				var coord := origin + Vector2i(x-budget,y-budget)
				if coord == origin: continue
				var path: Dictionary = envelope["reachable_by_coord"].get(coord, {})
				check(path.is_empty() == (int(expected[y][x]) == 0), "Godot reachable membership matches original four-neighbor flood")
				if path.is_empty(): continue
				check(int(path["cost"]) == budget+1-int(expected[y][x]), "arrival cost matches original flag/cliff/adjacency return")
				check(path["path_costs"] == grid.path_costs(path["path"], [actor], tiles, actor["id"]), "final path and cumulative costs stay consistent after all relaxations")
	var loop := fixture("plain")
	var actor: Dictionary = loop["units"][0]
	actor["coord"] = Vector2i(5,5)
	actor["move_point"] = 3
	loop["units"][1]["coord"] = Vector2i(6,6)
	var full := AINavigationRules.full_routes(loop, actor)
	var route := AINavigationRules.route_to_goals(full, [Vector2i(8,5)])
	check(route["cost"] == 4 and route["path_costs"] == [0,1,3,4], "passing a living occupied neighbor costs an extra point only after arrival")
	var advance := AINavigationRules.advance_path(actor, route)
	var current := BattlePlayLoop.movement_envelope(loop, actor["id"])
	check(advance["to"] == Vector2i(7,5) and advance["cost"] == current["reachable_by_coord"][advance["to"]]["cost"], "full pursuit prefix and actual action envelope share one budget")
	check(not current["reachable_coords"].has(Vector2i(8,5)), "player range cannot offer a destination beyond the actual clearance budget")
	loop["units"][1].merge({"hp": 0, "defeated": true}, true)
	var opened := BattlePlayLoop.movement_envelope(loop, actor["id"])
	check(opened["reachable_by_coord"][Vector2i(8,5)]["cost"] == 3, "defeated occupant immediately releases both occupancy and adjacency cost")
	var blocked := fixture("cast")
	var prepared := BattleLoopAI.prepare_ai_turn(blocked, blocked["units"][0]["id"])
	var proposal: Dictionary = AISkillPlanning.choose(prepared["skills"]["magic"]["leonard"], zero)["intent"]
	TestSuite.own(blocked, "tiles")[proposal["destination"]] = {"blocks_movement": true, "move_cost": 1, "movement_flags": 0x4000}
	var before := blocked.duplicate(true)
	check(BattleLoopAI.execute_ai_skill_choice(blocked, blocked["units"][0]["id"], proposal, forbidden_rng).is_empty() and blocked == before, "an invalidated moving-cast destination cannot teleport or spend MP")
	var replanned := BattlePlayLoop.step_ai_turn(blocked, zero)
	check(replanned["scenario_ok"] and replanned["last_ai_action"].get("to") != proposal["destination"] and replanned["last_ai_actions"].size() == 1, "normal AI entry recomputes a legal action after a planned cell becomes blocked")
	var sealed := fixture("unreachable")
	sealed["units"][0]["ai_target_id"] = "leonard"
	var switched := BattlePlayLoop.step_ai_turn(sealed, zero)
	# 0x43f55f..0x43f5f5 keeps a living held object inside find range (0x40bb50) and the
	# home circle; whether a route reaches it is never asked.
	check(BattlePlayLoop.unit(switched, sealed["units"][0]["id"])["ai_target_id"] == "leonard" and switched["last_ai_action"].get("toward") == "leonard", "a newly walled-off held target stays held (retention checks range, not reachability)")


func memory_cases() -> void:
	var loop := fixture("detour")
	var first := BattlePlayLoop.step_ai_turn(loop, zero)
	var owner: String = loop["units"][0]["id"]
	var remembered: String = BattlePlayLoop.unit(first, owner)["ai_target_id"]
	check(remembered == "leonard", "accepted pursuit persists only the target identity in the PlayLoop actor")
	# A nearer enemy with no attack station this turn (two moves short of a cell beside it):
	# the lock alone decides, the station switch 0x40d8b0 finds nobody to strike.
	BattlePlayLoop.unit_ref(first, "enemy023_1")["coord"] = Vector2i(2,8)
	var next_round := next_owner(first, owner)
	check(next_round["turn_queue"]["round"] == 1, "ordinary player waits really reach the next queue round")
	var second := BattlePlayLoop.step_ai_turn(next_round, zero)
	check(second["last_ai_action"]["ai_decision"]["target_selection"]["retained"] and BattlePlayLoop.unit(second, owner)["ai_target_id"] == remembered, "100-percent source lock preserves pursuit when a nearer enemy appears")
	# 0x440052..0x440085: the lock keeps Leonard, but the ordinary category's switch 0x40d8b0
	# walks the object array from Leonard's slot to the first object with a station — the
	# enemy now beside the actor — writes it to +0x88 and state 0xb sub 0 strikes it.
	var strikeable := next_owner(first, owner)
	BattlePlayLoop.unit_ref(strikeable, "enemy023_1")["coord"] = BattlePlayLoop.unit(strikeable, owner)["coord"] + Vector2i(-1, 0)
	var struck := BattlePlayLoop.step_ai_turn(strikeable, zero)
	var struck_decision: Dictionary = struck["last_ai_action"]["ai_decision"]
	check(struck_decision["target_selection"]["retained"] and struck_decision["station_switch"]["held_id"] == "leonard" and struck["last_ai_action"]["kind"] == "attack" and struck["last_ai_action"]["target_id"] == "enemy023_1" and BattlePlayLoop.unit(struck, owner)["ai_target_id"] == "enemy023_1", "a retained target without a station yields to the first registry object with one (0x40d8b0 switch, +0x88 rewritten at 0x440069)")
	var unlocked := next_round.duplicate(true)
	TestSuite.own(unlocked, "ai_profiles")["actors"]["021"]["profile"]["ai_lock"] = 0
	var changed := BattlePlayLoop.step_ai_turn(unlocked, zero)
	check(BattlePlayLoop.unit(changed, owner)["ai_target_id"] == "enemy023_1", "declined source lock performs a fresh legal target selection")
	var dead := next_round.duplicate(true)
	BattlePlayLoop.set_unit_hp(dead, remembered, 0)
	BattlePlayLoop.set_unit_defeated(dead, remembered, true)
	var replanned := BattleLoopAI.ai_take_turn(dead, owner, zero)
	check(replanned["loop"]["scenario_ok"] and BattlePlayLoop.unit(replanned["loop"], owner)["ai_target_id"] == "enemy023_1", "dead held target is replaced without replaying the prior attack or route")
	for outcome in [BattleOutcome.VICTORY_ESCAPE, BattleOutcome.VICTORY_ENEMIES_CLEARED, BattleOutcome.DEFEAT_FALLEN]:
		var terminal := second.duplicate(true)
		terminal["battle_outcome"] = outcome
		BattleLoopAI.prune_ai_calls(terminal)
		var saved := terminal.duplicate(true)
		check(terminal["units"].all(func(unit): return unit["ai_target_id"] == "" and unit["ai_call_target_id"] == ""), "terminal clears every pending target: "+BattleOutcome.describe(outcome))
		check(BattlePlayLoop.step_ai_turn(terminal, forbidden_rng) == saved, "terminal cannot debit, move or start another turn: "+BattleOutcome.describe(outcome))
	var guard := fixture("cast")
	var actor: Dictionary = guard["units"][0]
	actor["ai_home_coord"] = Vector2i(1,5)
	TestSuite.own(guard, "ai_profiles")["actors"][actor["actor_id"]]["profile"]["ai_fixed"] = 2
	var returning := BattlePlayLoop.step_ai_turn(guard, zero)
	check(returning["last_ai_action"].get("purpose") == "return_home" and BattlePlayLoop.unit(returning, actor["id"])["coord"] == Vector2i(1,5), "source fixed-radius guard returns to its anchor instead of chasing outside its post")


static func escort_fixture(point: Vector2i, items: Array = [241, 241]) -> Dictionary:
	# Level-17 shape: an unarmed friendly NPC (weapon 0 -> range0, no attack goal) whose EVEF
	# instance words grant 回復藥 and a fixed point, with one enemy far away.
	var loop := fixture("detour")
	var actor: Dictionary = loop["units"][0]
	actor.merge({"battle_actor_role": BattlePlayLoop.ROLE_FRIENDLY, "player_commandable": false, "weapon_code": 0, "equipment": [],
		"combat_profile": actor["combat_profile"].duplicate(true), "evef_instance": {"evidence_tier": "resource-derived", "record_index": 8,
		"items": items, "overrides": {"fixed_point": [point.x, point.y]}}}, true)
	loop["units"][1]["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	loop["units"][1]["coord"] = Vector2i(6, 12)
	loop["units"][2].merge({"battle_actor_role": BattlePlayLoop.ROLE_ENEMY, "player_commandable": false, "coord": Vector2i(14, 14)}, true)
	TestSuite.own(loop, "ai_profiles")["actors"][actor["actor_id"]]["profile"]["ai_check_hp"] = 100
	AINavigationRules.initialize(actor, loop["ai_profiles"]["actors"][actor["actor_id"]]["profile"])
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return loop


func instance_cases() -> void:
	# EVEF instance words (0x42bd50 actor branch): items compact into the first empty slots, stamina replaces +0xe8.
	var template := {"inventory": [241, 0, 0, 0, 0, 0, 0, 0], "stamina": 60, "evef_instance": {"items": [241, 241], "overrides": {"stamina": 36}}}
	ActorInitializationRules.apply_instance_words(template)
	check(template["inventory"] == [241, 241, 241, 0, 0, 0, 0, 0] and template["stamina"] == 36, "instance items fill the first empty slots after the template inventory and the stamina word replaces the initial value")
	var full := {"inventory": [1, 2, 3, 4, 5, 6, 7, 8], "stamina": 1, "evef_instance": {"items": [241]}}
	ActorInitializationRules.apply_instance_words(full)
	check(full["inventory"] == [1, 2, 3, 4, 5, 6, 7, 8], "a full inventory drops the instance item like the native slot scan")
	# Indices 1..14 replace the PLAYERS strategy per unit; the fixed point is ai_fixed 8 until arrival.
	var declared := {"wait_round": 0, "find_range": 80, "ai_fixed": 0, "ai_lock": 60}
	var waiter := {"evef_instance": {"overrides": {"wait_round": 8, "find_range": 10}}}
	var merged := AINavigationRules.instance_profile(waiter, declared)
	check(merged["wait_round"] == 8 and merged["find_range"] == 10 and merged["ai_fixed"] == 0 and merged["ai_lock"] == 60 and declared["wait_round"] == 0, "instance strategy words override only their own fields and leave the declared profile untouched")
	check(AINavigationRules.instance_profile({}, declared) == declared, "a unit without instance words keeps the declared profile")
	waiter["coord"] = Vector2i(5, 5)
	AINavigationRules.initialize(waiter, merged)
	check(waiter["ai_wait_remaining"] == 8 and waiter["ai_home_coord"] == Vector2i(5, 5) and not waiter.has("ai_fixed_point_pending"), "instance wait_round seeds the live wait counter (level 52 emperor: 8 rounds)")
	var runner := {"coord": Vector2i(31, 14), "evef_instance": {"overrides": {"fixed_point": [37, 18]}}}
	AINavigationRules.initialize(runner, declared)
	check(runner["ai_home_coord"] == Vector2i(37, 18) and runner["ai_fixed_point_pending"] == true, "fixed point word replaces the spawn anchor and arms the arrival release")
	check(AINavigationRules.instance_profile(runner, declared)["ai_fixed"] == 8, "an armed fixed point is a radius-8 guard")
	runner["ai_fixed_point_pending"] = false
	check(AINavigationRules.instance_profile(runner, declared)["ai_fixed"] == 0, "after arrival the unit is a free actor (ai_fixed cleared)")
	# Live turns: the unarmed friendly has no approach to any foe, walks toward its point, is released on arrival.
	var point := Vector2i(9, 5)
	var loop := escort_fixture(point)
	var actor_id: String = loop["units"][0]["id"]
	var home_distances: Dictionary = AINavigationRules.full_routes(loop, loop["units"][0].duplicate(true).merged({"coord": point}, true))["reachable_by_coord"]
	var stepped := BattlePlayLoop.step_ai_turn(loop, zero)
	check(stepped["scenario_ok"], "unarmed friendly escort turn resolves: " + str(stepped.get("scenario_error", "")))
	var action: Dictionary = stepped["last_ai_action"]
	var filters: Dictionary = action["ai_decision"]["candidate_filters"]
	check(filters["unarmed"] and filters["living_foes"] == 1 and filters["without_approach"] == 1 and action["ai_decision"]["target_selection"]["index"] == -1, "unarmed friendly loses every foe at the approach filter, not at side or guard checks")
	var landed: Vector2i = BattlePlayLoop.unit(stepped, actor_id)["coord"]
	check(action["kind"] == "move" and action.get("purpose") == "return_home" and landed != Vector2i(2, 5) and int(home_distances[landed]["cost"]) < int(home_distances[Vector2i(2, 5)]["cost"]), "fixed-point guard's refined walk (0x411080: flood 18 down to move, nearest cell to the previous pick) rounds the wall instead of pressing against it")
	var approach: Dictionary = action["ai_decision"]["home_approach"]
	var refinements: Array = approach["refinements"]
	check(approach["goal"] == point and int(approach["route_cost"]) == BattlePlayLoop.TacticalGridRules.manhattan(landed, point) and BattlePlayLoop.unit(stepped, actor_id)["ai_fixed_point_pending"], "approach receipt names the point and the Manhattan distance left; the release is still armed")
	check(refinements.size() == 9 and int(refinements[0]["radius"]) == AINavigationRules.FIXED_POINT_FLOOD_RADIUS and refinements[0]["target"] == point and refinements[0]["pick"] == point and int(refinements.back()["radius"]) == 2 and refinements.back()["pick"] == landed, "refinement floods 18,16,..,2: the first pick is the free point itself, each later flood targets the previous pick, the last is the move")
	var walking := stepped
	var arrived := false
	for _turn in range(12):
		walking = next_owner(walking, actor_id)
		walking = BattlePlayLoop.step_ai_turn(walking, zero)
		if not walking["scenario_ok"]: break
		if walking["last_ai_action"].get("wait_reason") == "fixed_point_reached":
			arrived = true
			break
	check(arrived and BattlePlayLoop.unit(walking, actor_id)["coord"] == point and not BattlePlayLoop.unit(walking, actor_id)["ai_fixed_point_pending"], "standing on the fixed point clears the release flag in that turn (0x43fbf1..0x43fc0e)")
	var freed := BattlePlayLoop.step_ai_turn(next_owner(walking, actor_id), zero)
	check(freed["last_ai_action"]["kind"] == "wait" and freed["last_ai_action"].get("wait_reason") == "no_valid_action" and BattlePlayLoop.unit(freed, actor_id)["coord"] == point, "a released unarmed NPC stays put like the three 062 (0x409090 = 0 ends the turn)")
	# Self-heal precedes the walk: ai_check_hp 100 and HP inside the 12..29% band spend a 回復藥.
	var hurt := escort_fixture(point)
	var npc: Dictionary = hurt["units"][0]
	npc["inventory"] = [241, 241, 0, 0, 0, 0, 0, 0]
	npc["hp"] = 40
	var healed := BattlePlayLoop.step_ai_turn(hurt, zero)
	check(healed["scenario_ok"] and healed["last_ai_action"]["kind"] == "use_item" and BattlePlayLoop.unit(healed, actor_id)["hp"] == 80 and BattlePlayLoop.unit(healed, actor_id)["inventory"][1] == 0 and BattlePlayLoop.unit(healed, actor_id)["coord"] == Vector2i(2, 5), "low-HP friendly drinks its instance 回復藥 (+40) instead of walking (0x440db1 self check before mode 5)")


func script_anchor_cases() -> void:
	# actSetPlayerFixPos (0x450840 case 0x54, WINFAIL012 round 8): the anchor +0x46/+0x44 and the
	# live ai_fixed take the script's pixels and distance; the unit stays put and walks toward
	# the anchor on its own turns. The level-12 anchors lie beyond the 45x60 map (-160,1824 ->
	# (-5,57)): before this reading the interpreter teleported the unit there and the next AI
	# turn failed with unsupported_ai_coordinates (autoplay dead_end reason=exception).
	var declared := {"wait_round": 0, "find_range": 80, "ai_fixed": 0, "ai_lock": 60}
	var retreating := {"coord": Vector2i(2, 5), "ai_target_id": "", "ai_wait_remaining": 0, "ai_home_coord": Vector2i(-5, 57), "ai_fixed_radius": 1}
	check(AINavigationRules.instance_profile(retreating, declared)["ai_fixed"] == 1 and AINavigationRules.instance_profile({"ai_fixed_radius": 3, "evef_instance": {"overrides": {"fixed_point": [4, 4]}}, "ai_fixed_point_pending": true}, declared)["ai_fixed"] == 3, "the script distance is the live ai_fixed, written after the instance words")
	check(AINavigationRules.state_error(retreating, 1) == "" and AINavigationRules.state_error({"ai_target_id": "", "ai_wait_remaining": 0, "ai_home_coord": Vector2i(-5, 57)}, 1) == "", "an anchor beyond the map edge is a legal guard destination")
	# Live turn: an armed enemy whose anchor is off the map west drops every foe at the guard
	# filter and walks to its westmost reachable cell (the retreat the level-12 script stages
	# two rounds before actWalkAndDelete).
	var loop := fixture("detour")
	var actor: Dictionary = loop["units"][0]
	actor.merge({"coord": Vector2i(6, 12), "ai_home_coord": Vector2i(-5, 57), "ai_fixed_radius": 1}, true)
	loop["units"][1]["coord"] = Vector2i(7, 12)
	var stepped := BattlePlayLoop.step_ai_turn(loop, zero)
	check(stepped["scenario_ok"], "retreat turn resolves: " + str(stepped.get("scenario_error", "")))
	if stepped["scenario_ok"]:
		var action: Dictionary = stepped["last_ai_action"]
		var landed: Vector2i = BattlePlayLoop.unit(stepped, actor["id"])["coord"]
		check(action["kind"] == "move" and action.get("purpose") == "return_home" and action["ai_decision"]["candidate_filters"]["guard_excluded"] == 2 and not stepped.has("last_combat"), "an adjacent foe outside the anchor radius is not attacked; the guard walks instead (0x440ef1 -> 0x440fd3)")
		check(landed == Vector2i(4, 12) and int(action["ai_decision"]["home_approach"]["route_cost"]) == BattlePlayLoop.TacticalGridRules.manhattan(landed, Vector2i(-5, 57)), "the retreating unit spends its move toward the off-map anchor and the receipt keeps the Manhattan distance left")
	# A living unit standing off the map has no AI branch: the preflight names it instead of
	# the current actor's row kernel failing.
	var stranded := fixture("detour")
	stranded["units"][2]["coord"] = Vector2i(-5, 57)
	var prepared := BattleLoopAI.prepare_ai_turn(stranded, stranded["units"][0]["id"])
	check(not prepared["ok"] and prepared["reason"] == "ai_unit_off_map:" + str(stranded["units"][2]["id"]), "a unit outside the map is an explicit, named scenario error")


## Ordinary pursuit is the fixed-point walk aimed at the held target (0x440d5c..0x440d84
## -> 0x4111a0 -> 0x411080). Boards are level 51 round 1 as the original recording shows
## them (docs/evidence_packets/runtime_observations/battle_051_ai_moves/README.md).
func pursuit_walk_cases() -> void:
	var base := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_051.json"), 1))
	# Round 1 opens with Enemy021 at (6,9); the recording shows it stepping to (10,8)
	# around its comrade at (10,9); the shortest-path prefix stopped short at (9,9).
	var landed := {}
	for seed in range(1, 9):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var step: Dictionary = BattleLoopAI.ai_take_turn(base, "actor021_3", rng)
		landed[step["action"]["to"]] = step["action"]
	var action: Dictionary = landed.values()[0]
	var refinements: Array = action["ai_decision"].get("pursuit_approach", {}).get("refinements", [])
	check(landed.keys() == [Vector2i(10, 8)] and action["kind"] == "move" and action["purpose"] == "pursuit", "level 51 round 1: Enemy021 (6,9) walks to (10,8) like the recording, not the path prefix (9,9): %s" % str(landed.keys()))
	check(refinements.size() > 1 and int(refinements[0]["radius"]) == AINavigationRules.FIXED_POINT_FLOOD_RADIUS and int(refinements.back()["radius"]) == 5 and refinements.back()["pick"] == Vector2i(10, 8), "pursuit receipt records the refinement floods 18 down to the move budget")
	# Enemy021 (17,6) after the first two moves: the recording has (12,6); equal cells are
	# a rand(2) coin, so (12,6) is one of the seeded outcomes (the prefix only gave (13,7)).
	var board := BattlePlayLoop.copy(base)
	BattlePlayLoop.unit_ref(board, "actor021_3")["coord"] = Vector2i(10, 8)
	BattlePlayLoop.unit_ref(board, "actor023_2")["coord"] = Vector2i(14, 14)
	var reached := {}
	for seed in range(1, 17):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		reached[BattleLoopAI.ai_take_turn(board, "actor021_1", rng)["action"]["to"]] = true
	check(reached.has(Vector2i(12, 6)) and reached.has(Vector2i(13, 7)) and reached.size() == 2, "level 51 round 1: Enemy021 (17,6) ties (12,6)／(13,7) on the walk's coin: %s" % str(reached.keys()))


func crowded_filter_cases() -> void:
	# 0x413740 -> 0x40d800: a single side becomes the two others, any other word stays;
	# 0x4000 (hard block) is always in the mask. The shrinking levels pass side 0.
	check(AINavigationRules.blocker_mask(0x10000) == 0x64000 and AINavigationRules.blocker_mask(0x20000) == 0x54000 and AINavigationRules.blocker_mask(0x40000) == 0x34000 and AINavigationRules.blocker_mask(0x50000) == 0x54000 and AINavigationRules.blocker_mask(0) == 0x4000, "0x413740 mask: one side -> the two others | 0x4000, other words kept")
	var size := Vector2i(6, 6)
	var words := {Vector2i(1, 2): 0x20000, Vector2i(3, 2): 0x20000, Vector2i(2, 1): AINavigationRules.HARD_BLOCK_FLAG, Vector2i(2, 3): 0x10000, Vector2i(0, 1): 0x20000}
	check(AINavigationRules.adjacent_blockers(Vector2i(2, 2), 0x64000, words, size) == 3 and AINavigationRules.adjacent_blockers(Vector2i(2, 2), 0x4000, words, size) == 1, "0x40d800 counts the four neighbours meeting the mask (hostile occupants, 0x4000 cells), not allies")
	check(AINavigationRules.adjacent_blockers(Vector2i(0, 0), 0x64000, words, size) == 1, "0x40d800 skips off-map neighbours")
	# Crowded (2,2) is nearest to (2,1); (4,0) is farther. rand(100) < 80 skips the crowded
	# cell and the held best stays; 80..99 keeps it.
	var cells := [Vector2i(4, 0), Vector2i(2, 2)]
	var skip_draws: Array = []
	var skipped: Dictionary = AINavigationRules.nearest_stoppable(cells.duplicate(), Vector2i(2, 1), Vector2i(5, 5), func(bound): return 79 if bound == 100 else 0, skip_draws, words, 0x64000, size)
	check(skipped["cell"] == Vector2i(4, 0) and int(skipped["crowded_skips"]) == 1 and skip_draws == [{"bound": 100, "value": 79}], "0x413740: a cell with >= 3 flagged neighbours is skipped when rand(100) < 80: %s" % str(skipped))
	var kept_draws: Array = []
	var kept: Dictionary = AINavigationRules.nearest_stoppable(cells.duplicate(), Vector2i(2, 1), Vector2i(5, 5), func(bound): return 80 if bound == 100 else 0, kept_draws, words, 0x64000, size)
	check(kept["cell"] == Vector2i(2, 2) and int(kept["crowded_skips"]) == 0, "0x413740: rand(100) >= 80 keeps the crowded nearest cell")
	var level_draws: Array = []
	var level: Dictionary = AINavigationRules.nearest_stoppable(cells.duplicate(), Vector2i(2, 1), Vector2i(5, 5), func(bound): return 0, level_draws, words, 0x4000, size)
	check(level["cell"] == Vector2i(2, 2) and level_draws.is_empty(), "a shrinking level (side 0) counts only hard-blocked cells, so one 0x4000 neighbour draws nothing")
	# 0x413740 mode 1 (0x413930): same scan, held distance starts at 0, a strictly farther cell wins.
	var far_draws: Array = []
	var far: Dictionary = AINavigationRules.farthest_stoppable([Vector2i(4, 0), Vector2i(2, 2), Vector2i(0, 5)], Vector2i(2, 1), Vector2i(5, 5), func(_bound): return 0, far_draws, words, 0x64000, size)
	check(far["cell"] == Vector2i(0, 5) and int(far["candidates"]) == 3 and far_draws.is_empty(), "0x413740 mode 1: the farthest cell from the threat, nearer ones never draw: %s" % str(far))
	var tie_kept: Dictionary = AINavigationRules.farthest_stoppable([Vector2i(0, 2), Vector2i(4, 0)], Vector2i(2, 1), Vector2i(5, 5), func(_bound): return 0, [], words, 0x64000, size)
	var tie_moved: Dictionary = AINavigationRules.farthest_stoppable([Vector2i(0, 2), Vector2i(4, 0)], Vector2i(2, 1), Vector2i(5, 5), func(_bound): return 1, [], words, 0x64000, size)
	check(tie_kept["cell"] == Vector2i(4, 0) and tie_moved["cell"] == Vector2i(0, 2), "0x413740 mode 1: an equal distance replaces the held cell on rand() & 1, row-major order")
	var held_zero: Dictionary = AINavigationRules.farthest_stoppable([Vector2i(2, 1)], Vector2i(2, 1), Vector2i(5, 5), func(_bound): return 0, [], words, 0x64000, size)
	check(held_zero.is_empty(), "0x413740 mode 1: distance 0 equals the initial held 0, so it draws the coin before anything is kept")
	var far_crowded: Dictionary = AINavigationRules.farthest_stoppable([Vector2i(2, 2)], Vector2i(2, 1), Vector2i(5, 5), func(bound): return 79 if bound == 100 else 0, [], words, 0x64000, size)
	check(far_crowded.is_empty(), "0x413740 mode 1 keeps the 0x40d800 crowded drop")


func self_cast_flee_cases() -> void:
	# 0x40cca0 with the actor as cast target: 0x40bb80 threat, 0x413930 farthest cell, 0x410a50.
	var size := Vector2i(8, 8)
	var origin := Vector2i(3, 3)
	var routes := {Vector2i(2, 3): {"path": [Vector2i(2, 3)], "cost": 1}, Vector2i(4, 3): {"path": [Vector2i(4, 3)], "cost": 1}, Vector2i(3, 5): {"path": [Vector2i(3, 4), Vector2i(3, 5)], "cost": 2}}
	var field := {"ok": true, "origin": origin, "cells": [origin, Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 5), Vector2i(0, 7)], "words": {}, "mask": 0x64000, "map_size": size, "routes": routes, "range0": {"heal0": true}}
	var never := func(_bound): return 0
	var none: Dictionary = AINavigationRules.flee(field, null, never)
	check(none["to"] == origin and none["reason"] == "no_threat", "no threat (0x40ce64 → 0x40d17e): the actor casts in place")
	var unreachable: Dictionary = AINavigationRules.flee(field, Vector2i(3, 0), never)
	check(unreachable["to"] == origin and unreachable["pick"] == Vector2i(0, 7) and unreachable["reason"] == "no_path", "0x410a50 failing on the farthest cell (0x40d17e): the actor casts in place")
	var reachable := field.duplicate()
	reachable["cells"] = [origin, Vector2i(2, 3), Vector2i(4, 3), Vector2i(3, 5)]
	var own := {"skill_id": "heal0", "target_id": "a", "primary_target_id": "a", "center_is_primary": true, "destination": origin, "score": 1, "movement_cost": 0, "path": []}
	var plan := {"primary_target_id": "a", "channel": "special", "skills": [], "threat": Vector2i(3, 0), "origin": origin, "flee": reachable}
	var range0: Dictionary = AISkillPlanning.cast_station(plan, {"skill_id": "heal0", "intents": [own]}, never, {})
	check(range0["intent"]["destination"] == Vector2i(3, 5) and range0["intent"]["target_id"] == "a" and range0["intent"]["path"] == [Vector2i(3, 4), Vector2i(3, 5)] and range0["decision"]["flee_branch"].begins_with("0x40cdd9"), "effect range 0 on the actor (0x40cdd3 → 0x40cdd9): flee to the farthest reachable cell, then cast on itself: %s" % str(range0["intent"]))
	var single := func(cell: Vector2i, score: int) -> Dictionary: return {"skill_id": "heal1", "target_id": "a", "primary_target_id": "a", "center_is_primary": true, "destination": cell, "score": score, "movement_cost": 1, "path": [cell]}
	var one: Dictionary = AISkillPlanning.cast_station(plan, {"skill_id": "heal1", "intents": [single.call(Vector2i(2, 3), 1), single.call(Vector2i(4, 3), 1)]}, never, {})
	check(one["intent"]["destination"] == Vector2i(3, 5) and one["decision"]["flee_branch"].begins_with("0x40d0ed"), "highest coverage 1 on the actor (0x40d0ed): flee instead of the farthest station")
	var two: Dictionary = AISkillPlanning.cast_station(plan, {"skill_id": "heal1", "intents": [single.call(Vector2i(2, 3), 2), single.call(Vector2i(4, 3), 2)]}, never, {})
	check(not two["decision"].has("flee_branch") and two["intent"]["destination"] in [Vector2i(2, 3), Vector2i(4, 3)], "highest coverage 2: the ordinary farthest-station pick (0x40d1a8), no flee")
	var fixed := plan.duplicate()
	fixed["channel"] = "magic"
	fixed["threat_scan"] = {"move_magic_use": false}
	var in_place: Dictionary = AISkillPlanning.cast_station(fixed, {"skill_id": "heal0", "intents": [own]}, never, {})
	check(in_place["intent"]["destination"] == origin and not in_place["decision"].has("flee_branch"), "MAGIC without move_magic_use never enters 0x40cca0: cast in place")


func attack_station_cases() -> void:
	var never := func(_bound): return 0
	# 0x413390 sorts the row-major stations by distance from the target centre, farthest
	# first; only an entry equal to the one just before it can swap (rand & 1). The key is
	# |2dx + 1| + |2dy + 1| (station words are cell centres, the range centre has no half
	# cell): (5,2) 6, (4,4) 2, (5,4) 2, (6,4) 4 — (4,4)／(5,4) tie and draw, (6,4) moves up.
	var ranged := {"centre": Vector2i(5, 5), "anchor": Vector2i(5, 5), "melee": false, "in_place": false,
		"stations": [{"cell": Vector2i(5, 2)}, {"cell": Vector2i(4, 4)}, {"cell": Vector2i(5, 4)}, {"cell": Vector2i(6, 4)}]}
	var sorted: Dictionary = AINavigationRules.attack_station(ranged, Vector2i(5, 9), 0, never)
	check(sorted["order"] == [Vector2i(5, 2), Vector2i(6, 4), Vector2i(4, 4), Vector2i(5, 4)] and sorted["draws"] == [{"bound": 2, "value": 0}] and sorted["to"] == Vector2i(5, 2) and sorted["reason"] == "walk_to_station", "0x413390: descending half-cell-biased distance insertion sort, the farthest station is the walk target: %s" % str(sorted["order"]))
	# Recording R3-24: 021_3 at (12,11) strikes 023_2 at (14,10). (14,11) below the target
	# keys 4, (13,10) left of it 2, so (14,11) leads without a coin — the original took (14,11).
	var melee := {"centre": Vector2i(14, 10), "anchor": Vector2i(14, 10), "melee": true, "in_place": false,
		"stations": [{"cell": Vector2i(13, 10)}, {"cell": Vector2i(14, 11)}]}
	var heads: Dictionary = AINavigationRules.attack_station(melee, Vector2i(12, 11), 0, func(_bound): return 1)
	var tails: Dictionary = AINavigationRules.attack_station(melee, Vector2i(12, 11), 0, never)
	check(heads["to"] == Vector2i(14, 11) and tails["to"] == Vector2i(14, 11) and heads["draws"].is_empty() and tails["draws"].is_empty(), "0x413390: a station below the target outranks one left of it with no coin (0x41363e..0x41364c half-cell bias; R3-24 lands on (14,11))")
	# Level 3 opening: 028_1 at (9,9) strikes leonard at (5,10) from (5,9) above (key 2) or
	# (6,10) right (key 4) — the original walks to (6,10) and draws nothing at 0x4136ba.
	var level3 := {"centre": Vector2i(5, 10), "anchor": Vector2i(5, 10), "melee": true, "in_place": false,
		"stations": [{"cell": Vector2i(5, 9)}, {"cell": Vector2i(6, 10)}]}
	var level3_station: Dictionary = AINavigationRules.attack_station(level3, Vector2i(9, 9), 0, func(_bound): return 1)
	check(level3_station["to"] == Vector2i(6, 10) and level3_station["draws"].is_empty(), "0x413390: level-3 028_1 takes (6,10) right of leonard over (5,9) above him without a draw (emulator: 16/16 seeds)")
	var mirrored := {"centre": Vector2i(5, 10), "anchor": Vector2i(5, 10), "melee": true, "in_place": false,
		"stations": [{"cell": Vector2i(5, 9)}, {"cell": Vector2i(4, 10)}]}
	var mirrored_heads: Dictionary = AINavigationRules.attack_station(mirrored, Vector2i(1, 1), 0, func(_bound): return 1)
	check(mirrored_heads["to"] == Vector2i(4, 10) and mirrored_heads["draws"] == [{"bound": 2, "value": 1}], "0x413390: above and left of the centre key alike (2) and still swap on the coin")
	# Already adjacent (in place) with a foe beside it: rand(99) + 1 above 92 still moves to
	# the station; otherwise it strikes where it stands. No foe beside it: no draw.
	var beside := {"centre": Vector2i(14, 10), "anchor": Vector2i(14, 10), "melee": true, "in_place": true,
		"stations": [{"cell": Vector2i(13, 10)}, {"cell": Vector2i(15, 10)}]}
	var moved: Dictionary = AINavigationRules.attack_station(beside, Vector2i(13, 10), 1, func(bound): return 92 if bound == 99 else 0)
	var stayed: Dictionary = AINavigationRules.attack_station(beside, Vector2i(13, 10), 1, func(bound): return 91 if bound == 99 else 0)
	var quiet: Dictionary = AINavigationRules.attack_station(beside, Vector2i(13, 10), 0, never)
	check(moved["to"] == Vector2i(15, 10) and moved["reason"] == "reposition_roll" and int(moved["roll"]) == 93, "state 0xb sub 0: rand(99)+1 = 93 > 92 moves a melee attacker to the station")
	check(stayed["to"] == Vector2i(13, 10) and stayed["reason"] == "attack_in_place" and int(stayed["roll"]) == 92, "state 0xb sub 0: rand(99)+1 = 92 attacks in place")
	check(quiet["to"] == Vector2i(13, 10) and quiet["reason"] == "attack_in_place" and quiet["draws"].is_empty(), "no foe beside the actor: attack in place without the reposition draw")
	var ranged_roll: Dictionary = AINavigationRules.attack_station(beside.merged({"melee": false}, true), Vector2i(13, 10), 1, func(bound): return 78 if bound == 99 else 0)
	check(ranged_roll["reason"] == "reposition_roll", "ranged weapons reposition above 78")
	# A station farther from the target than the actor is walked to even when the actor
	# could strike in place (a bowman steps back to full range).
	var back := {"centre": Vector2i(5, 5), "anchor": Vector2i(5, 5), "melee": false, "in_place": true,
		"stations": [{"cell": Vector2i(5, 2)}, {"cell": Vector2i(5, 4)}]}
	var stepped: Dictionary = AINavigationRules.attack_station(back, Vector2i(5, 4), 1, never)
	check(stepped["to"] == Vector2i(5, 2) and stepped["reason"] == "walk_to_station" and int(stepped["roll"]) == 0, "a farther station is walked to without the reposition draw")


## A ranged AI on the battle_504 opening board (036_1 given weapon 61, range3CellShoot)
## beside the walled pocket around gulu／rett／leonard.
static func walled_board(cell: Vector2i, level: String = "battle_504", actor_id: String = "actor036_1", weapon: int = 61) -> Dictionary:
	var loop := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/%s.json" % level), 1)
	BattlePlayLoop.unit_ref(loop, actor_id)["weapon_code"] = weapon
	BattlePlayLoop.set_unit_coord(loop, actor_id, cell)
	return loop


func terrain_range_cases() -> void:
	# 0x40d8b0 builds each target's coverage with the actor lifted (0x411b90 at 0x40d8c3,
	# 0x40fa80 flag 0 at 0x40dbe6..0x40dbfa) and 0x40fb20 tests the actor's own coverage
	# (0x40fa80 flag 1, 0x440d16..0x440d42): walls stop both floods. From (10,16) the flat
	# record puts leonard (11,14) in reach and lists (10,16) as a station; the terrain flood
	# does neither, so the actor walks to (12,16) and strikes from there.
	var loop := walled_board(Vector2i(10, 16))
	var actor := BattlePlayLoop.unit(loop, "actor036_1")
	var leonard := BattlePlayLoop.unit(loop, "leonard")
	var pattern := BattlePlayLoop.weapon_pattern(loop, actor)
	var routes: Dictionary = BattlePlayLoop.movement_envelope(loop, "actor036_1")["reachable_by_coord"]
	var flat := AINavigationRules.attack_stations(actor, leonard, pattern["offsets"], false, routes)
	var land := AINavigationRules.attack_stations(actor, leonard, pattern["offsets"], false, routes, AINavigationRules.weapon_terrain(loop, actor, pattern))
	check(flat["in_place"] and flat["stations"].map(func(s): return s["cell"]) == [Vector2i(10, 16), Vector2i(11, 16), Vector2i(12, 16)], "flat record: (10,16) reaches leonard and is a station (the pre-terrain AI path)")
	check(not land["in_place"] and land["stations"].map(func(s): return s["cell"]) == [Vector2i(11, 16), Vector2i(12, 16)], "0x40d8b0／0x40fb20 on terrain: leonard is out of reach from (10,16) and (10,16) is no station: %s" % str(land["stations"].map(func(s): return s["cell"])))
	var walked: Dictionary = BattleLoopAI.ai_take_turn(loop, "actor036_1", zero)["action"]
	check(walked.get("kind") == "move_then_attack" and walked.get("target_id") == "leonard" and walked.get("to") == Vector2i(12, 16), "a terrain station is walked to before the strike (504, (10,16) → (12,16)): %s %s" % [walked.get("kind"), walked.get("to")])
	# The flood is not symmetric: (6,16) is in rett's coverage (a station) but rett (8,15)
	# is not in the coverage from (6,16). After the walk 0x441311..0x441369 tests the held
	# target again from the station (0x40fa80 flag 1 → 0x40fb20); a miss jumps to 0x441eb8
	# and the turn ends there without a strike.
	var short := walled_board(Vector2i(8, 16))
	var rett_hp := int(BattlePlayLoop.unit(short, "rett")["hp"])
	var step: Dictionary = BattleLoopAI.ai_take_turn(short, "actor036_1", zero)
	var missed: Dictionary = step["action"]
	check(missed.get("kind") == "move" and missed.get("toward") == "rett" and missed.get("to") == Vector2i(6, 16) and missed.get("wait_reason") == "station_out_of_range" and not missed["ai_decision"]["attack_station"]["arrival_in_range"], "0x441311..0x441369: the station (6,16) does not see rett back, so the walk ends the turn without a strike: %s %s %s" % [missed.get("kind"), missed.get("to"), missed.get("wait_reason")])
	check(int(BattlePlayLoop.unit(step["loop"], "rett")["hp"]) == rett_hp and BattlePlayLoop.unit(step["loop"], "actor036_1")["coord"] == Vector2i(6, 16), "the failed arrival test settles no exchange and keeps the walk")
	# Probe sweep: a ranged AI placed on every open cell near the walled targets of battle_003
	# (hu) and battle_504 (gulu) strikes only a target inside its own terrain coverage from
	# the cell it strikes from (weapon_cells, the attack cue's geometry).
	var strikes := 0
	var outside: Array = []
	for probe in [["battle_504", "gulu", "actor036_1", 61], ["battle_504", "gulu", "actor036_1", 32], ["battle_003", "hu", "actor028_2", 32]]:
		var opening := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/%s.json" % probe[0]), 1)
		var anchor: Vector2i = BattlePlayLoop.unit(opening, probe[1])["coord"]
		for y in range(anchor.y - 3, anchor.y + 4):
			for x in range(anchor.x - 3, anchor.x + 4):
				var cell := Vector2i(x, y)
				var tile: Dictionary = BattlePlayLoop.TerrainEdits.tiles(opening).get(cell, {})
				if tile.is_empty() or int(tile.get("movement_flags", 0)) & 0x4000 or BattlePlayLoop.unit_id_at_coord(opening, cell) not in ["", probe[2]]: continue
				var board := walled_board(cell, probe[0], probe[2], probe[3])
				var action: Dictionary = BattleLoopAI.ai_take_turn(board, probe[2], zero)["action"]
				if str(action.get("kind", "")) not in ["attack", "move_then_attack"]: continue
				strikes += 1
				var struck: Vector2i = BattlePlayLoop.unit(board, str(action["target_id"]))["coord"]
				BattlePlayLoop.set_unit_coord(board, probe[2], action["to"])
				if not BattlePlayLoop.attack_cells(board, probe[2]).has(struck): outside.append([probe[0], probe[3], cell, action["to"], action["target_id"]])
	check(strikes > 40 and outside.is_empty(), "no AI strike through a wall on the battle_003／504 probe boards (%d strikes): %s" % [strikes, str(outside)])


func next_owner(loop: Dictionary, owner: String) -> Dictionary:
	var next := loop.duplicate(true)
	for _attempt in range(12):
		if BattlePlayLoop.CoreTurnQueue.current(next["turn_queue"]).get("id") == owner: return next
		if next["interaction"] == "action_menu": next = BattlePlayLoop.begin_wait_resolution(next)
		elif next["interaction"] == "ai_resolving": next = BattlePlayLoop.step_ai_turn(next, zero)
		else: break
	check(false, "normal queue handoffs must return to the owner")
	return next


static func zero(_bound: int) -> int:
	return 0


func forbidden_rng(_bound: int) -> int:
	check(false, "this waiting/rejected/terminal route must not consume RNG")
	return 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

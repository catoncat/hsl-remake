extends "res://tests/support/TestSuite.gd"
const Rules = preload("res://game/sim/AIDecisionRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "AI_DECISION_TESTS"


static func profile() -> Dictionary:
	return {"find_type": 3, "find_flag": 0, "find_range": 80, "find_no_id": -1,
		"ai_att_magic": 95, "ai_att_special": 100, "ai_call_range": 4, "ai_fixed": 0, "job": 90}


func run() -> void:
	native_cases()
	decision_cases()
	live_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_decisions.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var original: Dictionary = input.duplicate(true)
		var cursor := [0]
		var rng := func(bound):
			check(cursor[0] < row["draws"].size(), "no additional AI random call")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]
			cursor[0] += 1
			check(bound == int(draw["bound"]), "AI uses original random bound")
			return int(draw["value"])
		var strategy := profile()
		var result: Dictionary
		if input["kind"] == "action":
			strategy["ai_att_magic"] = input["magic_rate"]
			strategy["ai_att_special"] = input["special_rate"]
			result = Rules.select_action(strategy, 2 if input["silenced"] else 0, input["magic_available"], input["special_available"], rng)
			check(result["ok"] and result["kind"] == int(row["native"]), "action class matches original normal return")
		else:
			strategy["find_type"] = input["mode"]
			strategy["find_flag"] = input["preference"]
			strategy["find_range"] = input["range"]
			strategy["find_no_id"] = input["excluded_sid"]
			var units: Array = input["units"].duplicate(true)
			for unit in units:
				if unit != null: unit["coord"] = Vector2i(int(unit["coord"][0]), int(unit["coord"][1]))
			result = Rules.select_target(units, int(input["owner"]), strategy, int(input["near_range"]), rng)
			check(result["ok"] and result["native_index"] == int(row["native"]), "target slot matches original normal return")
		check(cursor[0] == row["draws"].size() and row["normal_return"], "all and only native AI draws consumed")
		check(input == original, "AI selection cannot mutate the source or battle input")


func decision_cases() -> void:
	var settings := profile()
	var one := func(bound): check(bound == 99, "action chooser uses 99, not percentage100"); return 0
	check(Rules.select_action(settings, 0, true, true, one)["kind"] == 2, "odd first sample prioritizes owned affordable special")
	check(Rules.select_action(settings, 0, true, false, one)["kind"] == 1, "unavailable first class reuses its sample for magic")
	check(Rules.select_action(settings, 2, true, true, func(_n): return 1)["kind"] == 2, "silence skips magic and retains special")
	settings["ai_att_magic"] = 0
	var attempts := [0]
	var choice := Rules.select_action(settings, 0, true, true, func(_n): attempts[0] += 1; return 1)
	check(attempts[0] == 2 and choice["kind"] == 2, "failed available first class draws again before second class")
	check(Rules.action_order(2) == [2, 0, 1], "caller cycles special to physical to magic without another preference draw")
	var untouched := settings.duplicate(true)
	settings.erase("ai_att_magic")
	var bad := Rules.select_action(settings, 0, true, true, func(_n): check(false, "invalid AI data must not draw"); return 0)
	check(not bad["ok"] and bad["reason"] == "missing_ai_profile_ai_att_magic", "missing strategy is a named failure rather than a default policy")
	settings = untouched
	var units := [_row(Vector2i(10, 10), 2), _row(Vector2i(16, 10), 1), _row(Vector2i(14, 10), 1), _row(Vector2i(15, 10), 1)]
	check(Rules.select_target(units, 0, settings, 5, func(_n): return 1)["index"] == 1, "strictly improved score can retain old target and affects later comparison")
	units[1]["coord"] = Vector2i(11, 10)
	units[2]["job"] = 90
	settings["find_flag"] = 1
	check(Rules.select_target(units, 0, settings, 5, func(_n): return 0)["index"] == 2, "nearby preferred profession can override a closer other profession")
	units[2]["removed"] = true
	check(Rules.select_target(units, 0, settings, 5, func(_n): return 0)["index"] == 1, "removed preferred target is filtered before occupation scoring")


static func _row(coord: Vector2i, side: int) -> Dictionary:
	return {"coord": coord, "side": side * 0x10000, "hp": 100, "level": 1, "job": 80, "sid": 21, "removed": false}


static func live_fixture(owner: String = "enemy026_1") -> Dictionary:
	var loop := BattleFixture.loop()
	var actor := Loop.unit(loop, owner)
	var target := Loop.unit(loop, "enemy021_1" if owner == "leonard" else "leonard")
	var next := Loop.unit(loop, "enemy023_1")
	actor["coord"] = Vector2i(3, 3)
	actor["live_speed"] = 100
	actor["player_commandable"] = false
	actor["battle_actor_role"] = Loop.ROLE_FRIENDLY if owner == "leonard" else Loop.ROLE_ENEMY
	target["coord"] = Vector2i(4, 3)
	target["live_speed"] = 10
	next["coord"] = Vector2i(10, 10)
	next["live_speed"] = 90
	next["player_commandable"] = true
	next["battle_actor_role"] = Loop.ROLE_PLAYER
	loop["units"] = [actor, target, next]
	for unit in loop["units"]:
		unit["hp"] = 400
		unit["max_hp"] = 400
		unit["combat_profile"]["attack_back"] = 0
	loop["tiles"] = {}
	loop["map_size"] = Vector2i(16, 16)
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop["interaction"] = "ai_resolving"
	loop["selected_unit_id"] = ""
	return loop


func live_cases() -> void:
	for owner in ["enemy021_1", "enemy026_1", "leonard"]:
		var loop := live_fixture(owner)
		if owner == "leonard": Loop._unit(loop, owner)["stamina"] = 60
		var before := loop.duplicate(true)
		var used: Array = []
		var after := Loop.step_ai_turn(loop, func(bound): used.append(bound); return 0)
		check(after["scenario_ok"], "live source strategy accepts " + owner + ": " + str(after.get("scenario_error", "")))
		if not after["scenario_ok"]: continue
		var action: Dictionary = after["last_ai_action"]
		check(not used.is_empty() and used[0] == 99 and action["ai_decision"]["action_selection"]["draws"].size() == 1, "live action decision uses one original preference draw for " + owner)
		check(after["selected_unit_id"] == "enemy023_1" and after["interaction"] == "action_menu" and after["turn_queue"]["index"] == 1, "one AI action hands directly to next controllable ally")
		check(loop == before and after["last_ai_actions"].size() == 1, "AI publishes one receipt and preserves caller snapshot")
		if owner == "enemy026_1":
			check(action.get("skill_id") == "magic:magicFIRE:magicCode01" and Loop.unit(after, owner)["mp"] == Loop.unit(before, owner)["mp"] - action["resource_payment"]["amount"], "source-prepended fire enters one shared MP transaction")
		elif owner == "leonard":
			check(action.get("skill_id") == "special:magicOTHER:magicCode01" and action["ai_decision"]["action_selection"]["kind"] == 2 and Loop.unit(after, owner)["stamina"] == 60 - action["resource_payment"]["amount"], "source-owned friendly AI special uses same ST and receipt as player")
		else:
			check(not action.has("skill_id") and action["ai_decision"]["action_selection"]["kind"] == 0 and action["defender_id"] == "leonard", "no source ability is substituted for ordinary attack")
	var silenced := live_fixture()
	var mage := Loop._unit(silenced, "enemy026_1")
	mage["inventory"] = [0,0,0,0,0,0,0,0] # Isolate ordinary fallback; source-stocked cures now take the self-aid route.
	mage["status_flags"] = 3
	mage["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var after := Loop.step_ai_turn(silenced, func(_n): return 0)
	check(not after["last_ai_action"].has("magic_key") and Loop.unit(after, mage["id"])["mp"] == mage["mp"], "silence changes AI action availability before source selection")
	check(Loop.unit(after, mage["id"])["hp"] == 393 and Loop.unit(after, mage["id"])["status_counters"] == {"poison": (7 << 16) | 1, "paralysis": 0, "no_magic": 0}, "AI ordinary action ticks poison and expires silence exactly once")
	var broke := live_fixture()
	Loop._unit(broke, "enemy026_1")["mp"] = 0
	var ordinary := Loop.step_ai_turn(broke, func(_n): return 0)
	check(not ordinary["last_ai_action"].has("skill_id") and Loop.unit(ordinary, "enemy026_1")["mp"] == 0, "empty MP cannot create a free spell")
	for corruption in ["strategy", "identity", "resistance", "movement"]:
		var invalid := live_fixture()
		match corruption:
			"strategy": own(invalid, "ai_profiles")["actors"]["026"]["profile"].erase("ai_att_magic")
			"identity": own(invalid, "ai_profiles")["actors"]["001"]["sid"] = null
			"resistance": Loop._unit(invalid, "leonard")["combat_profile"].erase("resist_by_type")
			"movement": Loop._unit(invalid, "enemy026_1")["move_point"] = -1
		var saved := invalid.duplicate(true)
		var rejected := Loop.step_ai_turn(invalid, func(_n): check(false, "invalid AI data must reject before first RNG: " + corruption); return 0)
		check(not rejected["scenario_ok"] and rejected["interaction"] == "scenario_error", "malformed AI input is a named scenario failure: " + corruption)
		check(rejected["units"] == saved["units"] and rejected["turn_queue"] == saved["turn_queue"] and rejected["last_ai_actions"] == saved["last_ai_actions"] and invalid == saved, "failure cannot move, debit, damage or advance: " + corruption)
	var distant := live_fixture("enemy021_1")
	Loop._unit(distant, "leonard")["coord"] = Vector2i(14, 3)
	Loop._unit(distant, "enemy023_1")["defeated"] = true
	# The dispatcher roll (0x440db5, rand(99)+1, read again by the lock 0x441002) and the state 0xa
	# category roll (0x40c570 at 0x43fe0c: rand(99)+1 at 0x40c58d, drawn whatever the target offers) come first;
	# after it the pursuit walk's equal-candidate coin (0x413740: 0x458c10 & 1) is the only draw.
	var walk_draws: Array = []
	var walked := LoopAI._ai_take_turn(distant, "enemy021_1", func(n): walk_draws.append(n); return 0)
	check(walk_draws.size() > 2 and walk_draws.slice(0, 2) == [99, 99] and walk_draws.slice(2).all(func(n): return n == 2), "single unreachable target draws the dispatcher and category rolls, then only walk coins: %s" % str(walk_draws))
	check(walked["action"]["kind"] == "move" and walked["action"]["toward"] == "leonard" and not walked["action"]["path"].is_empty(), "unreachable source target produces an actual legal chase path")
	# A one-row corridor leaves every refinement flood one strictly nearest cell: no coin.
	var corridor := distant.duplicate(true)
	for y in range(16):
		for x in range(16):
			if y != 3: own(corridor, "tiles")[Vector2i(x, y)] = {"blocks_movement": true, "move_cost": 1}
	var corridor_draws: Array = []
	var straight := LoopAI._ai_take_turn(corridor, "enemy021_1", func(n): corridor_draws.append(n); return 0)
	check(corridor_draws == [99, 99] and straight["action"]["kind"] == "move" and straight["action"]["to"] == Vector2i(3 + int(Loop._unit(corridor, "enemy021_1")["move_point"]), 3), "pursuit with one nearest cell at every refinement draws nothing after the dispatcher and category rolls: %s" % str(corridor_draws))
	var restricted := distant.duplicate(true)
	own(restricted, "ai_profiles")["actors"]["021"]["profile"]["find_range"] = 1
	var waited := LoopAI._ai_take_turn(restricted, "enemy021_1", func(_n): check(false, "out-of-search target is rejected before RNG"); return 0)
	check(waited["action"]["kind"] == "wait" and waited["loop"]["units"] == restricted["units"], "source search radius is honored without default global chase")

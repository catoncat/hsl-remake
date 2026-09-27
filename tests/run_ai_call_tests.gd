extends "res://tests/support/TestSuite.gd"
const Rules = preload("res://game/sim/AICallRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const LoopScript = preload("res://game/battle/scene/BattleLoopScript.gd")
const Fixtures = preload("res://tests/run_ai_decision_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


func _init() -> void:
	tag = "AI_CALL_TESTS"


func run() -> void:
	native_cases()
	live_chain()
	status_and_movement()
	lifecycle_cases()
	atomic_failures()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_calls.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var saved := input.duplicate(true)
		var rows: Array = []
		for unit in input["units"]:
			if unit == null:
				rows.append(null)
				continue
			rows.append({"coord": Vector2i(int(unit["coord"][0]), int(unit["coord"][1])), "side": unit["side"],
				"removed": unit["removed"], "hp": 100, "level": 1, "job": 90, "sid": unit["object_code"]})
		var before := rows.duplicate(true)
		var recipients := Rules.recipients(rows, int(input["owner"]), int(input["radius"]))
		check(recipients["ok"] and rows == before, "call geometry is pure")
		var tags: Array = input["units"].map(func(unit): return null if unit == null else int(unit["tag"]))
		if input["kind"] == "broadcast":
			check(recipients["indices"] == row["result"]["recipients"].map(func(index): return int(index)), "recipients match original full return, including removed and exact side flags")
			for index in recipients["indices"]: tags[index] = int(input["tag"])
		else:
			var pending := int(input["units"][int(input["owner"])]["tag"])
			var candidate: Variant = input["units"][pending - 1] if pending > 0 else null
			var eligible: bool = candidate != null and not candidate["removed"] and (int(input["excluded_word"]) == 0 or candidate["object_code"] != input["excluded_word"])
			var adoption := Rules.adopt(int(input["ordinary"]) - 1, pending - 1, pending > 0, eligible)
			check(adoption["index"] + 1 == int(row["result"]["target"]), "adoption matches original prefix target")
			if adoption["consumed"]: tags[int(input["owner"])] = 0
			if adoption["broadcast"] and int(input["radius"]) > 0:
				for index in recipients["indices"]: tags[index] = int(input["ordinary"])
		check(tags == row["result"]["tags"].map(func(tag): return null if tag == null else int(tag)) and input == saved, "entire pending-tag table matches original with immutable input")
	check(not Rules.recipients([], 0, 5)["ok"], "missing owner is rejected")


static func chain_fixture() -> Dictionary:
	var loop := Fixtures.live_fixture()
	var caller := Loop.unit(BattleFixture.loop(), "enemy021_1")
	caller["coord"] = Vector2i(5, 3)
	caller["live_speed"] = 110
	caller["hp"] = 400
	caller["max_hp"] = 400
	caller["combat_profile"]["attack_back"] = 0
	loop["units"].push_front(caller)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
	own(loop, "ai_profiles")["actors"]["021"]["profile"]["ai_call_range"] = 4
	Loop._unit(loop, "enemy026_1")["ai_call_target_id"] = "enemy023_1"
	return loop


func live_chain() -> void:
	var start := chain_fixture()
	var saved := start.duplicate(true)
	var first := Loop.step_ai_turn(start, func(_n): return 0)
	check(first["scenario_ok"] and first["last_ai_action"]["defender_id"] == "leonard", "caller executes ordinary source-selected attack")
	check(Loop.unit(first, "enemy026_1")["ai_call_target_id"] == "leonard", "actual caller overwrites older nearby same-side call")
	check(Loop.CoreTurnQueue.current(first["turn_queue"])["id"] == "enemy026_1" and first["interaction"] == "ai_resolving", "caller advances once to the receiving AI")
	check(start == saved, "broadcast never changes the input battle")
	var reordered := first.duplicate(true)
	reordered["units"].reverse()
	var draws: Array = []
	var second := Loop.step_ai_turn(reordered, func(bound): draws.append(bound); return 0)
	check(second["scenario_ok"] and second["last_ai_action"].get("defender_id") == "leonard", "stable call ID survives roster reordering")
	var action: Dictionary = second["last_ai_action"]
	check(action["ai_decision"]["target_selection"]["index"] == -1 and action["ai_decision"]["call_target"]["adoption"]["used"], "call reaches a target outside receiver source search radius")
	check(action.get("skill_id") in ["magic:magicAIR:magicCode01", "magic:magicFIRE:magicCode01"] and draws[0] == 99, "adopted target still uses source magic class and shared skill ownership")
	check(Loop.unit(second, "enemy026_1")["mp"] == Loop.unit(first, "enemy026_1")["mp"] - action["resource_payment"]["amount"], "receiver pays MP exactly once")
	check(Loop.unit(second, "enemy026_1")["ai_call_target_id"] == "" and action["ai_decision"]["call_target"]["recipient_ids"].is_empty(), "consumed fallback is cleared without rebroadcast")
	check(second["selected_unit_id"] == "enemy023_1" and second["interaction"] == "action_menu" and second["turn_queue"]["index"] == 2 and second["last_ai_actions"].size() == 2, "two actual AI actions hand directly to controllable successor")
	var ordinary := Fixtures.live_fixture("enemy021_1")
	Loop._unit(ordinary, "enemy021_1")["ai_call_target_id"] = "enemy023_1"
	var kept := Loop.step_ai_turn(ordinary, func(_n): return 0)
	check(kept["last_ai_action"]["defender_id"] == "leonard" and Loop.unit(kept, "enemy021_1")["ai_call_target_id"] == "enemy023_1", "ordinary target has priority and does not consume a valid pending call")
	var disabled := chain_fixture()
	Loop._unit(disabled, "enemy026_1")["ai_call_target_id"] = ""
	own(disabled, "ai_profiles")["actors"]["021"]["profile"]["ai_call_range"] = 0
	var no_call := Loop.step_ai_turn(disabled, func(_n): return 0)
	check(Loop.unit(no_call, "enemy026_1")["ai_call_target_id"] == "", "zero call_range disables the caller broadcast")
	var waiting := Loop.step_ai_turn(no_call, func(_n): check(false, "no source target and no call requires no draw"); return 0)
	check(waiting["last_ai_action"]["kind"] == "wait" and waiting["selected_unit_id"] == "enemy023_1", "no call yields a real Wait and one successor handoff")


func status_and_movement() -> void:
	var loop := Fixtures.live_fixture()
	own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
	var mage := Loop._unit(loop, "enemy026_1")
	mage["ai_call_target_id"] = "leonard"
	mage["inventory"] = [0,0,0,0,0,0,0,0] # Called attack fallback after no available self-cure.
	mage["status_flags"] = 3
	mage["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var after := Loop.step_ai_turn(loop, func(_n): return 0)
	check(after["scenario_ok"] and after["last_ai_action"].get("defender_id") == "leonard" and not after["last_ai_action"].has("skill_id"), "called target cannot bypass silence to cast magic")
	check(Loop.unit(after, "enemy026_1")["mp"] == mage["mp"] and Loop.unit(after, "enemy026_1")["ai_call_target_id"] == "", "silenced action consumes the call without an MP debit")
	check(Loop.unit(after, "enemy026_1")["hp"] == 393 and Loop.unit(after, "enemy026_1")["status_counters"] == {"poison": (7 << 16) | 1, "paralysis": 0, "no_magic": 0} and after["selected_unit_id"] == "enemy023_1", "called action ticks poison and expires silence once before the player handoff")
	var distant := Fixtures.live_fixture("enemy021_1")
	Loop._unit(distant, "leonard")["coord"] = Vector2i(14, 3)
	Loop._unit(distant, "enemy023_1")["defeated"] = true
	own(distant, "ai_profiles")["actors"]["021"]["profile"]["find_range"] = 1
	Loop._unit(distant, "enemy021_1")["ai_call_target_id"] = "leonard"
	var saved := distant.duplicate(true)
	# The dispatcher roll (0x440db5, read by the lock 0x441002 for the adopted call target too) and
	# the state 0xa category roll (0x40c570 at 0x43fe0c, drawn whatever the target offers)
	# comes first; after it the pursuit walk's equal-candidate coin (0x413740) is the only draw.
	var walk_draws: Array = []
	var walked := LoopAI._ai_take_turn(distant, "enemy021_1", func(n): walk_draws.append(n); return 0)
	check(walk_draws.size() > 2 and walk_draws.slice(0, 2) == [99, 99] and walk_draws.slice(2).all(func(n): return n == 2), "unreachable call target draws the dispatcher and category rolls, then only walk coins: %s" % str(walk_draws))
	check(walked["loop"]["scenario_ok"] and walked["action"]["kind"] == "move" and walked["action"]["toward"] == "leonard", "distant call target produces a chase without expanding ordinary find_range")
	check(not walked["action"]["path"].is_empty() and Loop.movement_cells(distant, "enemy021_1").has(walked["action"]["to"]), "called movement remains inside the existing legal movement envelope")
	check(Loop.unit(walked["loop"], "enemy021_1")["ai_call_target_id"] == "" and distant == saved, "movement consumes only the published call, leaving the input battle intact")
	# A one-row corridor leaves every refinement flood one strictly nearest cell: no coin.
	var corridor := distant.duplicate(true)
	for y in range(16):
		for x in range(16):
			if y != 3: own(corridor, "tiles")[Vector2i(x, y)] = {"blocks_movement": true, "move_cost": 1}
	var corridor_draws: Array = []
	var straight := LoopAI._ai_take_turn(corridor, "enemy021_1", func(n): corridor_draws.append(n); return 0)
	check(corridor_draws == [99, 99] and straight["action"]["kind"] == "move" and straight["action"]["toward"] == "leonard", "called pursuit with one nearest cell at every refinement draws nothing after the dispatcher and category rolls: %s" % str(corridor_draws))


func lifecycle_cases() -> void:
	for invalid in ["missing", "dead", "friendly", "excluded"]:
		var loop := Fixtures.live_fixture()
		own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
		var actor := Loop._unit(loop, "enemy026_1")
		actor["ai_call_target_id"] = "leonard"
		match invalid:
			"missing": actor["ai_call_target_id"] = "departed"
			"dead": Loop._unit(loop, "leonard")["defeated"] = true
			"friendly": Loop._unit(loop, "leonard")["battle_actor_role"] = Loop.ROLE_ENEMY
			"excluded": own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_no_id"] = loop["ai_profiles"]["actors"]["001"]["sid"]
		var result := LoopAI._ai_take_turn(loop, "enemy026_1", func(_n): check(false, "invalid call cannot consume randomness: " + invalid); return 0)
		check(result["loop"]["scenario_ok"] and result["action"]["kind"] == "wait" and Loop.unit(result["loop"], "enemy026_1")["ai_call_target_id"] == "", "invalid call is consumed without effects: " + invalid)
		check(Loop.unit(result["loop"], "enemy026_1")["mp"] == actor["mp"], "invalid call never debits MP: " + invalid)
	var killed := chain_fixture()
	Loop._unit(killed, "leonard")["hp"] = 1
	var ended := Loop.step_ai_turn(killed, func(_n): return 0)
	check(BattleOutcome.decided(ended) and ended["units"].all(func(actor): return actor["ai_call_target_id"] == ""), "actual lethal strike and terminal outcome clear every pending reference")
	var cast := Fixtures.live_fixture()
	own(cast, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
	Loop._unit(cast, "enemy026_1")["ai_call_target_id"] = "leonard"
	Loop._unit(cast, "leonard")["hp"] = 1
	var cast_result := LoopAI._ai_take_turn(cast, "enemy026_1", func(_n): return 0)
	check(cast_result["action"].has("skill_id") and Loop.unit(cast_result["loop"], "leonard")["defeated"] and Loop.unit(cast_result["loop"], "enemy026_1")["ai_call_target_id"] == "", "shared lethal skill consumes and prunes the call before another action")
	var depart := Fixtures.live_fixture("leonard")
	Loop._unit(depart, "leonard")["ai_call_target_id"] = "enemy021_1"
	var departed := depart.duplicate(true)
	LoopScript._commit_departures(departed, ["enemy021_1"], "winfail", "event_3")
	check(Loop.unit(departed, "enemy021_1")["departed"] and not Loop.Presence.living(Loop.unit(departed, "enemy021_1")) and Loop.unit(departed, "leonard")["ai_call_target_id"] == "", "story departure preserves history but clears all call references to the retired actor")
	check(departed["turn_queue"]["slots"].all(func(slot):return slot["id"] != "enemy021_1"), "retired history never becomes an AI queue candidate")


func atomic_failures() -> void:
	for corruption in ["tag", "duplicate_id", "receiver_target"]:
		var loop := Fixtures.live_fixture()
		own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
		Loop._unit(loop, "enemy026_1")["ai_call_target_id"] = "leonard"
		match corruption:
			"tag": Loop._unit(loop, "enemy026_1")["ai_call_target_id"] = 17
			"duplicate_id": loop["units"][2]["id"] = "leonard"
			"receiver_target": Loop._unit(loop, "leonard")["combat_profile"].erase("resist_by_type")
		var before := loop.duplicate(true)
		var result := Loop.step_ai_turn(loop, func(_n): check(false, "preflight failure precedes all RNG: " + corruption); return 0)
		check(not result["scenario_ok"] and result["interaction"] == "scenario_error", "invalid call input rejects the action: " + corruption)
		check(loop == before and result["units"] == before["units"] and result["turn_queue"] == before["turn_queue"] and result["last_ai_actions"] == before["last_ai_actions"], "failure preserves resources, calls, queue and receipts: " + corruption)

extends "res://tests/support/TestSuite.gd"

## Direct PlayLoop coverage for the formal level-7 event handoff. The test drives
## ordinary Wait actions until the round-5 and round-6 winfail events fire (after
## each round's first completed action, not at the wrap); it
## does not force a victory before those scripted installations occur.

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const SCENARIO_PATH := "res://content/battles/battle_007.json"


func _init() -> void:
	tag = "LEVEL7_RUNTIME_TESTS"
	report_checks = false


func _reach_player(loop: Dictionary, label: String) -> Dictionary:
	var next := loop
	for _step in range(512):
		if str(next.get("interaction", "")) == "action_menu":
			return next
		if str(next.get("interaction", "")) != "ai_resolving":
			_assert_true(false, "%s stops in %s (%s)" % [label, str(next.get("interaction", "")), str(next.get("scenario_error", ""))])
			return next
		next = Loop._advance_current_actor(next)
	_assert_true(false, "%s did not return to a player action" % label)
	return next


func _wait_to_round(loop: Dictionary, target_round: int) -> Dictionary:
	var next := loop
	var guard := 0
	while int(next.get("turn", 0)) < target_round and guard < 128:
		_assert_eq(str(next.get("interaction", "")), "action_menu", "round %d starts with a controlled Wait" % (int(next.get("turn", 0)) + 1))
		next = Loop.choose_command(next, "wait")
		next = _reach_player(next, "round %d" % target_round)
		guard += 1
	_assert_true(int(next.get("turn", 0)) >= target_round, "turn reaches scripted round %d" % target_round)
	return next


func _first_action_of_round(loop: Dictionary) -> Dictionary:
	_assert_eq(str(loop.get("interaction", "")), "action_menu", "round %d opens with the player's action" % int(loop.get("turn", 0)))
	return _reach_player(Loop.choose_command(loop, "wait"), "after round %d's first action" % int(loop.get("turn", 0)))


## Runtime inserts take later registration slots: 0x407660 hands every non-player actor the
## next cursor slot (0x4c1a3c, reset to 20 only at level load: 0x42da92 → 0x407260), so the
## round-5 WINFAIL007 soldiers rank after every equal-speed EVEF NPC in the round-6 queue
## (0x407340 stable sort); ScriptActorCreationRules appends them to the roster end.
## static-derived docs/evidence_packets/static_reverse/initial_battle_initiative.md.
func _assert_runtime_inserts_take_later_slots(loop: Dictionary) -> void:
	var slots: Array = loop["turn_queue"]["slots"]
	var order: Array = slots.map(func(slot): return str(slot["id"]))
	var captains: Array = loop.get("units", []).filter(func(actor): return str(actor.get("actor_id", "")) == "024").map(func(actor): return str(actor["id"]))
	var last_evef := order.find("actor038_6")
	_assert_true(last_evef >= 0 and captains.size() == 2, "round 6 queue holds EVEF 038_6 and the two inserted 024 captains")
	if last_evef < 0 or captains.size() != 2:
		return
	for id in captains:
		var at := order.find(id)
		_assert_eq([int(slots[at]["live_speed"]), at > last_evef], [int(slots[last_evef]["live_speed"]), true], "round 6: inserted captain %s shares speed with EVEF 038_6 and acts after it" % id)
	var roster := {}
	var units: Array = loop["units"]
	for index in range(units.size()):
		roster[str(units[index]["id"])] = index
	var inversions: Array = []
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var a := str(slots[i]["id"])
			var b := str(slots[j]["id"])
			var npc := str(Loop.unit(loop, a).get("battle_actor_role", "")) != Loop.ROLE_PLAYER and str(Loop.unit(loop, b).get("battle_actor_role", "")) != Loop.ROLE_PLAYER
			if npc and int(slots[i]["live_speed"]) == int(slots[j]["live_speed"]) and int(roster[a]) > int(roster[b]):
				inversions.append("%s/%s" % [a, b])
	_assert_eq(inversions, [], "round 6: equal-speed NPCs (EVEF and runtime inserts) act in registration order")


func run() -> void:
	var scenario: Dictionary = BattleScenario.load_file(SCENARIO_PATH)
	var loop := Loop.create([], "", scenario, 7)
	_assert_true(bool(loop.get("scenario_ok", false)), "level 7 PlayLoop creates (%s)" % str(loop.get("scenario_error", "")))
	if not bool(loop.get("scenario_ok", false)):
		return
	var templates: Dictionary = loop.get("script_actor_source", {}).get("templates", {})
	for symbol in ["obj_Story_Level7_Enemy23", "obj_Story_Level7_Enemy24", "obj_Story_Player5"]:
		_assert_true(templates.has(symbol), "level 7 script actor template exists: " + symbol)
	_assert_true(not loop.get("units", []).any(func(actor): return str(actor.get("actor_id", "")) == "005"), "005 is not installed before event section 5")

	loop = Loop.begin_battle(loop)
	loop = _reach_player(loop, "battle start")
	loop = _wait_to_round(loop, 5)
	# The round-5 event fires after round 5's first completed action (0x407510 scans
	# before 0x4074a0 bumps the counter), not at the wrap: the player opens round 5.
	_assert_eq(loop.get("script_actor_transactions", []).size(), 0, "round 5 installs nothing before its first completed action")
	loop = _first_action_of_round(loop)
	var enemy23: Array = loop.get("units", []).filter(func(actor): return str(actor.get("actor_id", "")) == "023")
	var enemy24: Array = loop.get("units", []).filter(func(actor): return str(actor.get("actor_id", "")) == "024")
	_assert_eq(enemy23.size(), 6, "round 5 installs six 023 soldiers")
	_assert_eq(enemy24.size(), 2, "round 5 installs two 024 captains")
	# WINFAIL007 follows every round-5 actInsertObject with actSetPrevInsertObjectAdjustLevel,2,1:
	# ScriptActorCreationRules births the insert with the token's +0x1f8 halves, not the template's.
	for soldier in enemy23 + enemy24:
		_assert_eq((soldier.get("entry_growth", {}) as Dictionary).get("input", {}).get("parameters"), [2, 1], "%s is born under the script's 2,1 halves" % str(soldier.get("id", "")))
		_assert_eq((soldier.get("entry_growth", {}) as Dictionary).get("origin"), "script", "%s birth origin is the runtime script insert" % str(soldier.get("id", "")))
	var round5_transactions: Array = loop.get("script_actor_transactions", [])
	_assert_eq(round5_transactions.size(), 1, "round 5 writes one script actor transaction")
	if round5_transactions.size() >= 1:
		_assert_eq(round5_transactions[0].get("created_ids", []).size(), 8, "round 5 transaction records eight created units")
	_assert_eq(Loop.BattleScenarioRuleAdapter.reinforcement_deficits(loop), {}, "round 5 insert deficit is settled by ScriptActorCreationRules")

	loop = _wait_to_round(loop, 6)
	_assert_true(Loop.unit(loop, "shera").is_empty(), "round 6 installs Shera only after its first completed action")
	_assert_runtime_inserts_take_later_slots(loop)
	loop = _first_action_of_round(loop)
	var shera := Loop.unit(loop, "shera")
	_assert_true(not shera.is_empty(), "round 6 installs Shera 005")
	_assert_eq(str(shera.get("actor_id", "")), "005", "round 6 installed actor is 005")
	_assert_eq(str(shera.get("battle_actor_role", "")), Loop.ROLE_PLAYER, "round 6 Shera is player controlled")
	var round6_transactions: Array = loop.get("script_actor_transactions", [])
	_assert_eq(round6_transactions.size(), 2, "round 6 writes the registered-player transaction")
	if round6_transactions.size() >= 2:
		_assert_eq(round6_transactions[1].get("created_ids", []), ["shera"], "round 6 transaction creates Shera once")

	for actor in loop.get("units", []):
		if str(actor.get("battle_actor_role", "")) == Loop.ROLE_ENEMY:
			Loop._set_unit_defeated(loop, str(actor.get("id", "")), true)
	loop = Loop._resolve_outcome(loop)
	_assert_true(BattleOutcome.won(loop), "level 7 resolves victory after scripted handoffs")
	var carry: Dictionary = CampaignCarryRules.capture(loop)
	_assert_true(carry.get("units", {}).has("shera"), "campaign carry includes Shera 005 after victory")
	_assert_eq(carry.get("units", {}).get("shera", {}).get("actor_id", ""), "005", "campaign carry preserves Shera actor id")

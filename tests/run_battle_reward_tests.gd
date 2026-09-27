extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const BattleLoopRewards = preload("res://game/sim/loop/BattleLoopRewards.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BattleAftermath = preload("res://game/battle/scene/BattleAftermath.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const EMPTY := [0, 0, 0, 0, 0, 0, 0, 0]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void: call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)


static func fixture(full: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	player["live_speed"] = 100
	player["coord"] = Vector2i(15, 15)
	player["exp"] = 99
	player["inventory"] = [241, 241, 241, 246, 241, 241, 241, 241] if full else [241, 241, 241, 246, 0, 0, 0, 0]
	var next := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	next["live_speed"] = 99
	next["player_commandable"] = true
	next["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	next["coord"] = Vector2i(10, 10)
	var target := BattlePlayLoop.unit_ref(loop, "enemy021_1")
	target["coord"] = player["coord"] + Vector2i.RIGHT
	target["hp"] = 1
	target["inventory"] = [281, 282, 0, 0, 0, 0, 0, 0] # Two guaranteed important drops.
	target["status_flags"] = 3
	target["status_counters"] = {"poison": (10 << 16) | 3, "paralysis": 0, "no_magic": 2}
	target["ai_call_target_id"] = "leonard"
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, "leonard")


static func attack(loop: Dictionary) -> Dictionary:
	return BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop, "attack"), "enemy021_1", func(_n): return 0)


func run() -> void:
	roll_cases()
	settlement_cases()
	area_cases()
	counter_and_end_cases()
	carried_gold_cases()
	undead_counter_cases()
	party_recipient_cases()
	gold_double_cases()
	ai_handoff_cases()
	undead_victim_cases()
	checkpoint_cases()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("BATTLE_REWARD_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func roll_cases() -> void:
	var source: Dictionary = BattleFixture.loop()["reward_data"]
	# One global-stream state per rand(100) outcome (drops draw 0x44f5d3 on the global stream).
	var by_roll := {}
	var start := 1
	while by_roll.size() < 100:
		var words := GlobalRandomStream.seeded(start)
		var first_roll := int(GlobalRandomStream.rand(words, 100)["value"])
		if not by_roll.has(first_roll): by_roll[first_roll] = words
		start += 1
	for rate in [0, 1, 50, 100]:
		var items := {"241": {"get_ratio": rate, "important": false}}
		var reached := {}
		for roll in range(100):
			var value: int = GlobalRandomStream.rand(by_roll[roll], 100)["value"]
			reached[value] = true
			var result := BattleRewardRules.drops([241, 0, 0, 0, 0, 0, 0, 0], items, by_roll[roll])
			check(result["items"].size() == (1 if value + 1 < rate else 0), "native strict drop boundary rate=%d roll=%d" % [rate, value])
		check(reached.size() == 100, "drop boundary cases cover all 100 possible samples")
	var seven := GlobalRandomStream.seeded(7)
	var important := BattleRewardRules.drops([281, 281, 0, 0, 0, 0, 0, 0], source["items"], seven)
	check(important["state"] == seven and important["items"].size() == 2, "important duplicate slots each drop, without random consumption")
	check(BattleRewardRules.carry([0, 241], seven) == {"code": 0, "state": seven}, "zero terminates carry list")
	check(BattleRewardRules.carry([-1, -1, -1, 0], seven) == {"code": 0, "state": seven}, "minus-one sentinel consumes no RNG")
	for seed in range(1, 102):
		var first := GlobalRandomStream.rand(GlobalRandomStream.seeded(seed), 101)
		var result := BattleRewardRules.carry([-1, 241], GlobalRandomStream.seeded(seed))
		check(result["code"] == (241 if first["value"] <= 18 else 0), "sentinel still lowers the next carry threshold")
	check(BattlePlayLoop.initialize_roster_growth(BattleFixture.loop([], "", 19)) == BattlePlayLoop.initialize_roster_growth(BattleFixture.loop([], "", 19)), "same authored scenario and seed replay initial carries (rolled with the births on the global stream)")


func settlement_cases() -> void:
	var before := fixture()
	var loop := attack(before)
	check(before["gold"] == 0 and BattlePlayLoop.unit(before, "enemy021_1")["hp"] == 1, "attack does not mutate its caller")
	check(loop["gold"] == 100 and loop["settlement"]["pending"].size() == 2, "one actual lethal strike generates wallet and two carried items")
	var native_exp: int = BattlePlayLoop.ExperienceRules.from_contribution(1, 1, 1, 0, int(BattlePlayLoop.unit(loop, "enemy021_1")["kill_exp"]), 0, func(_n): return 0)["points"]
	check(BattlePlayLoop.unit(loop, "leonard")["level"] == 2 and loop["last_combat"]["experience"]["gained"] == native_exp, "capped actual loss enters the native kill/level EXP conversion before final award")
	var dead := BattlePlayLoop.unit(loop, "enemy021_1")
	check(dead["inventory"] == EMPTY and dead["status_flags"] == 0 and dead["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 0} and dead["ai_call_target_id"] == "", "lethal settlement clears carried stock and unusable status/call state")
	check(not BattlePlayLoop.unit_coords(loop).has(dead["id"]), "defeated actor no longer occupies a tactical cell")
	var immutable := loop.duplicate(true)
	BattleLoopRewards.commit_rewards(loop, loop["last_combat"])
	check(loop == immutable, "duplicate sequence does not reroll, regrant or clear claims")
	check(BattlePlayLoop.begin_wait_resolution(loop) == loop and BattlePlayLoop.finish_exhausted_action(loop) == loop and BattlePlayLoop.choose_command(loop, "move") == loop, "unclaimed loot blocks successor action mutation")
	var id: String = loop["settlement"]["pending"][0]["id"]
	var first := BattlePlayLoop.claim_reward(loop, 1, 0, id, "leonard")
	check(BattlePlayLoop.unit(first, "leonard")["inventory"].has(281) and first["settlement"]["pending"].size() == 1, "claim uses the live first empty inventory slot")
	check(BattlePlayLoop.claim_reward(first, 1, 0, id, "leonard") == first and BattlePlayLoop.finish_rewards(first, 1, 0, true) == first, "stale claim and stale finish do nothing")
	check(BattlePlayLoop.finish_rewards(first, 1, 1, true) == first, "important remaining item cannot be abandoned")
	var deferred := BattlePlayLoop.finish_rewards(first, 1, 1, false, true)
	check(not BattlePlayLoop.loot_waiting(deferred) and deferred["settlement"]["pending"].size() == 1, "defer preserves remaining important stock and releases the modal")
	var reopened := BattlePlayLoop.reopen_rewards(deferred)
	check(BattlePlayLoop.loot_waiting(reopened) and reopened["settlement"]["revision"] == 3, "same action can reopen exact deferred items")
	var done := BattlePlayLoop.claim_reward(reopened, 1, 3, reopened["settlement"]["pending"][0]["id"], "leonard")
	done = BattlePlayLoop.finish_rewards(done, 1, 4)
	check(not BattlePlayLoop.loot_waiting(done) and done["gold"] == 100 and done["turn_queue"] == loop["turn_queue"], "finish never pays or advances on its own")
	done = BattlePlayLoop.finish_exhausted_action(done)
	check(done["selected_unit_id"] == "enemy023_1" and done["turn_queue"]["index"] == 1, "post-presentation action advances to the exact next controlled actor")
	check(BattlePlayLoop.finish_exhausted_action(done) == done, "repeated finish cannot spend successor action")
	var full := attack(fixture(true))
	id = full["settlement"]["pending"][0]["id"]
	check(BattlePlayLoop.claim_reward(full, 1, 0, id, "leonard") == full, "full inventory rejects auto insertion with all state intact")
	var swap := BattlePlayLoop.claim_reward(full, 1, 0, id, "leonard", 2, 241)
	check(BattlePlayLoop.unit(swap, "leonard")["inventory"] == [241, 241, 246, 241, 241, 241, 241, 281] and swap["settlement"]["pending"][0]["code"] == 241, "full swap compacts source slot and retains displaced item in loot")
	check(BattlePlayLoop.claim_reward(swap, 1, 0, id, "leonard", 2, 241) == swap, "old exchange request cannot swap the returned item again")
	var invalid := BattlePlayLoop.choose_command(fixture(), "attack")
	TestSuite.own(invalid, "reward_data")["items"]["281"]["get_ratio"] = NAN
	var rejected := BattlePlayLoop.attack_target(invalid, "enemy021_1", func(_n): check(false, "bad reward data must reject before combat RNG"); return 0)
	check(rejected["units"] == invalid["units"] and rejected["gold"] == 0, "invalid rewards cannot half-settle combat")


func area_cases() -> void:
	var loop := fixture()
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	player["mp"] = 100
	player["max_mp"] = 100
	var skill := "magic:magicMIND:magicCode02"
	# Synthetic ownership and cross footprint exercise the common resolver, not a
	# new production spell grant or a claim that native Seal is an area spell.
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"].append(skill)
	TestSuite.own(loop, "skill_book")["skills"][skill]["fields"]["effect_range"] = "range1Cell"
	var secondary := BattlePlayLoop.unit_ref(loop, "enemy021_2")
	secondary["coord"] = Vector2i(17, 15)
	secondary["hp"] = 2
	secondary["inventory"] = [283, 0, 0, 0, 0, 0, 0, 0]
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	loop = BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop, "magic"), skill)
	var result := BattlePlayLoop.attack_target(loop, "enemy021_1", func(_n): return 0)
	check(result.get("last_combat", {}).get("affected_targets", []).size() == 2, "actual area cast has two distinct settled targets: " + str(result.get("last_attack_reject", {})))
	if result.get("last_combat", {}).get("affected_targets", []).size() != 2: return
	check(BattlePlayLoop.unit(result, "enemy021_1")["hp"] == 0 and BattlePlayLoop.unit(result, "enemy021_2")["hp"] == 0, "both area deaths commit in the same transaction")
	var expected := 0
	for hit in result["last_combat"]["affected_targets"]:
		expected += int(hit["experience_basis"]["points"])
	check(result["last_combat"]["experience"]["gained"] == expected and BattlePlayLoop.unit(result, "leonard")["exp"] == 99 + expected - 100, "secondary target's converted EXP contributes exactly once before growth")
	check(result["gold"] == 200 and result["settlement"]["pending"].size() == 3, "area rewards include every target's gold and carried drops")
	var payment: Dictionary = result["last_combat"]["resource_payment"]
	check(payment["before"] == 100 and payment["after"] == 77, "area payment debits once before growth refresh: " + str(payment))
	check(BattlePlayLoop.unit(result, "leonard")["mp"] == mini(77, int(BattlePlayLoop.unit(result, "leonard")["max_mp"])), "level refresh clamps synthetic MP to the new SwordMan maximum after the one payment")
	var no_replay := BattlePlayLoop.attack_target(result, "enemy021_2", func(_n): check(false, "repeated area cast cannot draw"); return 0)
	check(no_replay == result, "area sequence is fully idempotent at the public action gate")


func counter_and_end_cases() -> void:
	var loop := fixture()
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	player["combat_profile"]["attack_back"] = 100
	var strike := BattleLoopCombat.resolve_exchange(loop, "enemy021_1", "leonard", func(_n): return 0)
	check(not strike.get("counter", {}).is_empty() and BattlePlayLoop.unit(loop, "enemy021_1")["defeated"], "controlled defender kills incoming attacker on its one counter")
	check(loop["gold"] == 100 and BattlePlayLoop.loot_waiting(loop), "counter kill grants the same party reward once")
	var final := fixture()
	final["units"] = final["units"].filter(func(actor): return actor["id"] in ["leonard", "enemy021_1"])
	final["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(final["units"])
	final = attack(final)
	check(final["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED and BattlePlayLoop.loot_waiting(final), "last enemy victory retains the pending reward modal")
	final = BattlePlayLoop.finish_rewards(final, 1, 0, false, true)
	check(BattlePlayLoop.resolve_outcome(final) == final, "repeated terminal evaluation cannot reopen already deferred loot")
	check(BattlePlayLoop.loot_waiting(BattlePlayLoop.reopen_rewards(final)), "result screen can reopen deferred loot instead of stranding it at victory")
	var failure := fixture()
	BattlePlayLoop.unit_ref(failure, "leonard")["hp"] = 1
	BattlePlayLoop.unit_ref(failure, "leonard")["combat_profile"]["live_defense"] = 0
	BattleLoopCombat.resolve_exchange(failure, "enemy021_1", "leonard", func(_n): return 0)
	failure = BattlePlayLoop.resolve_outcome(failure)
	check(failure["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN and failure["gold"] == 0, "player defeat has no fabricated player rewards")
	var miss := fixture()
	miss = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(miss, "attack"), "enemy021_1", func(n): return n - 1)
	check(miss["gold"] == 0 and not BattlePlayLoop.loot_waiting(miss) and miss["last_combat"].get("experience", {}).is_empty(), "miss creates neither EXP nor loot")


## Enemy A (enemy021_1) kills controlled B (enemy023_1, actor 023) with its own strike.
static func enemy_kill(loop: Dictionary) -> Dictionary:
	var victim := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	victim["coord"] = BattlePlayLoop.unit(loop, "enemy021_1")["coord"] + Vector2i.DOWN
	victim["hp"] = 1
	victim["combat_profile"]["live_defense"] = 0
	return BattleLoopCombat.resolve_exchange(loop, "enemy021_1", "enemy023_1", func(_n): return 0)


func carried_gold_cases() -> void:
	# 0x442720 state 2 (0x442827..0x442875): gold paid to a recipient whose 0x40ba20 is not exactly
	# 0x10000 adds to its own record +0x98, the word kill gold 0x40e390 and the StealGold cap read.
	var gold_of := func(source: Dictionary, actor: String) -> int: return int(source["reward_data"]["actors"][actor]["gold"])
	var loop := fixture()
	var victim_gold: int = BattleRewardRules.carried_gold(BattlePlayLoop.unit(loop, "enemy023_1"), gold_of.call(loop, "023"))
	var strike := enemy_kill(loop)
	check(victim_gold > 0 and BattlePlayLoop.unit(loop, "enemy023_1")["defeated"] and loop["gold"] == 0, "enemy A's strike kills controlled B without touching the party gold")
	check(int(BattlePlayLoop.unit(loop, "enemy021_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == victim_gold and strike["rewards"].get("carried", []) == [{"unit_id": "enemy021_1", "defender_id": "enemy023_1", "gold": victim_gold}], "B's kill gold goes to A's own record +0x98: " + str(strike.get("rewards", {})))
	check(BattleRewardRules.carried_gold(BattlePlayLoop.unit(loop, "enemy021_1"), gold_of.call(loop, "021")) == gold_of.call(loop, "021") + victim_gold, "A's live +0x98 is its template gold plus B's kill gold")
	loop = attack(loop)
	check(loop["gold"] == gold_of.call(loop, "021") + victim_gold and loop["settlement"]["kills"][0]["gold"] == gold_of.call(loop, "021") + victim_gold, "killing A pays the template gold + B's kill gold: " + str(loop["gold"]))
	var instance := fixture()
	BattlePlayLoop.unit_ref(instance, "enemy021_1")["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 17, "overrides": {"gold": 250}}
	enemy_kill(instance)
	instance = attack(instance)
	check(instance["gold"] == 250 + victim_gold, "killing A pays the EVEF instance gold + B's kill gold: " + str(instance["gold"]))
	# A controlled initiator killed by the counter pays nobody (0x444641 adds no 0x40e390; the
	# player death sequence 0x443660 pays gold 0).
	var countered := fixture()
	var initiator := BattlePlayLoop.unit_ref(countered, "enemy023_1")
	initiator["coord"] = BattlePlayLoop.unit(countered, "enemy021_1")["coord"] + Vector2i.DOWN
	initiator["hp"] = 1
	initiator["combat_profile"]["live_defense"] = 0
	BattlePlayLoop.unit_ref(countered, "enemy021_1")["hp"] = 1000
	BattlePlayLoop.unit_ref(countered, "enemy021_1")["combat_profile"]["attack_back"] = 100
	var counter_strike := BattleLoopCombat.resolve_exchange(countered, "enemy023_1", "enemy021_1", func(_n): return 0)
	check(not counter_strike.get("counter", {}).is_empty() and BattlePlayLoop.unit(countered, "enemy023_1")["defeated"], "enemy counter kills the controlled initiator")
	check(not BattlePlayLoop.unit(countered, "enemy021_1").has(BattleRewardRules.CARRIED_GAINED) and not counter_strike["rewards"].has("carried") and countered["gold"] == 0, "a controlled initiator killed by the counter adds nothing to the counterer's +0x98")
	# An NPC (pmNPC 0x40000) whose counter kills an enemy initiator keeps the kill gold (death
	# sequence 0x43f150 pays the killer); a friendly AI on exactly 0x10000 pays the party
	# (0x442827..0x44284a).
	for mode in [0x40000, 0x10000]:
		var npc_loop := fixture()
		var npc := BattlePlayLoop.unit_ref(npc_loop, "enemy023_1")
		npc["player_commandable"] = false
		npc["battle_actor_role"] = "friendly_ai"
		npc["player_mode"] = mode
		npc["coord"] = BattlePlayLoop.unit(npc_loop, "enemy021_1")["coord"] + Vector2i.DOWN
		npc["hp"] = 1000
		npc["combat_profile"]["attack_back"] = 100
		var npc_strike := BattleLoopCombat.resolve_exchange(npc_loop, "enemy021_1", "enemy023_1", func(_n): return 0)
		var expected: int = gold_of.call(npc_loop, "021") if mode == 0x40000 else 0
		var party: int = gold_of.call(npc_loop, "021") - expected
		check(BattlePlayLoop.unit(npc_loop, "enemy021_1")["defeated"] and int(BattlePlayLoop.unit(npc_loop, "enemy023_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == expected and npc_loop["gold"] == party, "counter kill by a friendly AI with mode 0x%x adds %d to its +0x98 and %d to the party: %s" % [mode, expected, party, str(npc_strike.get("rewards", {}))])
	# The gained gold is battle state: it survives the checkpoint and a bad value is refused.
	var saved := fixture()
	enemy_kill(saved)
	var meta := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": false, "growth_notified_level": 1}
	var encoded := BattleCheckpoint.encode(saved, meta)
	check(encoded["ok"] and BattleCheckpoint.decode(encoded["bytes"], saved)["snapshot"]["loop"] == saved, "the checkpoint keeps A's gained carried gold exactly")
	for bad in [-1, 1.5, "100", 2147483648]:
		var tampered := BattlePlayLoop.copy(saved)
		BattlePlayLoop.unit_ref(tampered, "enemy021_1")[BattleRewardRules.CARRIED_GAINED] = bad
		check(BattlePlayLoop.reward_input_error(tampered) == "invalid_carried_gold" and not BattleCheckpoint.encode(tampered, meta)["ok"], "a carried gold of %s is refused" % str(bad))


## An undead attacker the counter kills revives in its own process and, as the current actor, ends
## the action through 0x407510 (0x4433e2..0x4433eb player／0x43ee92..0x43ee9b enemy): neither its
## completion award (0x4447d8／0x4416bc) nor the counterer's death-sequence payout (0x443660／0x43f150)
## runs, so nobody is paid for the exchange.
func undead_counter_cases() -> void:
	for undead in [false, true]:
		# Enemy initiator, controlled counterer.
		var loop := fixture()
		BattlePlayLoop.unit_ref(loop, "leonard")["combat_profile"]["attack_back"] = 100
		BattlePlayLoop.unit_ref(loop, "enemy021_1")["undead"] = undead
		var strike := BattleLoopCombat.resolve_exchange(loop, "enemy021_1", "leonard", func(_n): return 0)
		var counter: Dictionary = strike.get("counter", {})
		check(not counter.is_empty() and bool(counter.get("undead_revived", false)) == undead, "the counter lands its lethal strike on the initiator (undead=%s)" % str(undead))
		if counter.is_empty(): continue
		var counter_award: Dictionary = counter.get("experience_settlement", {})
		if not undead:
			check(int(counter_award.get("awarded", 0)) > 0 and int(BattlePlayLoop.unit(loop, "leonard")["exp"]) != 99, "control: a counter kill of an ordinary initiator pays the counterer its EXP: " + str(counter_award))
			continue
		check(int(BattlePlayLoop.unit(loop, "enemy021_1")["hp"]) == 1 and not bool(BattlePlayLoop.unit(loop, "enemy021_1")["defeated"]), "the undead initiator stands back up at 1 HP after the counter")
		check(counter_award.get("reason") == "undead_action_ended" and int(counter_award.get("awarded", -1)) == 0 and int(BattlePlayLoop.unit(loop, "leonard")["exp"]) == 99 and not counter.has("experience"), "the counterer gets no EXP for killing an undead initiator (death-sequence payout never runs): " + str(counter_award))
		check(strike.get("experience_settlement", {}).get("reason") == "undead_action_ended" and int(strike["experience_settlement"]["awarded"]) == 0 and not strike.has("experience"), "the revived undead initiator gets no completion award: " + str(strike.get("experience_settlement", {})))
		check(loop["gold"] == 0 and not BattlePlayLoop.loot_waiting(loop) and strike["rewards"]["kills"].is_empty() and not strike["rewards"].has("carried"), "no kill gold, drops or carried gold for the revived initiator: " + str(strike["rewards"]))
	# Controlled undead initiator whose primary strike earns EXP, killed by the enemy's counter.
	var own := fixture()
	var initiator := BattlePlayLoop.unit_ref(own, "leonard")
	initiator["undead"] = true
	initiator["hp"] = 1
	initiator["combat_profile"]["live_defense"] = 0
	BattlePlayLoop.unit_ref(own, "enemy021_1")["hp"] = 1000
	BattlePlayLoop.unit_ref(own, "enemy021_1")["combat_profile"]["attack_back"] = 100
	var own_strike := BattleLoopCombat.resolve_exchange(own, "leonard", "enemy021_1", func(_n): return 0)
	var basis := 0
	for hit in BattlePlayLoop.CombatSequence.participant_outcomes(own_strike): basis += int(hit["experience_basis"]["points"])
	check(basis > 0 and bool(own_strike.get("counter", {}).get("undead_revived", false)) and int(BattlePlayLoop.unit(own, "leonard")["hp"]) == 1, "the controlled undead initiator's strike has an EXP basis and the counter revives it at 1 HP")
	check(own_strike["experience_settlement"]["reason"] == "undead_action_ended" and int(BattlePlayLoop.unit(own, "leonard")["exp"]) == 99 and int(own_strike["experience_settlement"]["base"]) == basis, "the revived controlled initiator keeps its basis on the receipt but is paid nothing: " + str(own_strike["experience_settlement"]))


static func friendly(loop: Dictionary, mode: int) -> Dictionary:
	var ally := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	ally["player_commandable"] = false
	ally["battle_actor_role"] = "friendly_ai"
	ally["player_mode"] = mode
	ally["coord"] = BattlePlayLoop.unit(loop, "enemy021_1")["coord"] + Vector2i.DOWN
	return ally


## 0x442720 state 2: 0x40ba20(recipient) — live +0x28 & 0x870000 — exactly 0x10000 pays the party
## 0x4c1bcc (0x442837..0x44284a, capped at 0x3b9ac9ff); anything else adds to its record +0x98.
func party_recipient_cases() -> void:
	var gold_of := func(source: Dictionary, actor: String) -> int: return int(source["reward_data"]["actors"][actor]["gold"])
	for mode in [0x10000, 0x50000, 0x870000]:
		var loop := fixture()
		friendly(loop, mode)
		var strike := BattleLoopCombat.resolve_exchange(loop, "enemy023_1", "enemy021_1", func(_n): return 0)
		var kill_gold: int = gold_of.call(loop, "021")
		var party := kill_gold if mode == 0x10000 else 0
		check(kill_gold > 0 and BattlePlayLoop.unit(loop, "enemy021_1")["defeated"] and loop["gold"] == party and int(BattlePlayLoop.unit(loop, "enemy023_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == kill_gold - party, "a friendly AI with mode 0x%x killing an enemy pays %d to the party, the rest to its +0x98: %s" % [mode, party, str(strike.get("rewards", {}))])
		if mode == 0x10000:
			check(strike["rewards"]["kills"] == [{"attacker_id": "enemy023_1", "defender_id": "enemy021_1", "gold": kill_gold}] and not strike["rewards"].has("carried") and loop["settlement"]["gold"] == kill_gold, "the 0x10000 friendly AI's kill is a party payment on the receipt and the settlement: " + str(strike["rewards"]))
	# The cap (0x44283e cmp 0x3b9ac9ff; jle → 0x44284a mov 0x3b9ac9ff).
	var capped := fixture()
	capped["gold"] = BattleRewardRules.PARTY_GOLD_CAP - 10
	capped = attack(capped)
	check(capped["gold"] == BattleRewardRules.PARTY_GOLD_CAP and capped["settlement"]["gold"] == 10 and capped["settlement"]["gold_after"] == BattleRewardRules.PARTY_GOLD_CAP and capped["last_combat"]["rewards"]["gold"] == 100, "a kill payment stops the party gold at 999,999,999: " + str(capped["gold"]))
	var above := fixture()
	above["gold"] = BattleRewardRules.PARTY_GOLD_CAP + 5
	above = attack(above)
	check(above["gold"] == BattleRewardRules.PARTY_GOLD_CAP + 5, "a remake balance above the cap is not lowered by a payment")
	# StealGold's take is paid through the same state 2: +0x28 bit 0x10000 takes from the target's
	# +0x98 (0x40b548..0x40b554), any other drains the party at once (0x40b55c..0x40b578); the take
	# then goes to the party only for exactly 0x10000, else to the caster's own +0x98.
	for row in [[0x10000, "target_carry", 80, 0], [0x50000, "target_carry", 50, 30], [0x20000, "party", 20, 30]]:
		var loop := fixture()
		loop["gold"] = 50
		friendly(loop, int(row[0]))
		var strike := {"attacker_id": "enemy023_1"}
		BattleLoopRewards.apply_gold_effects(loop, strike, [{"kind": "steal_gold", "amount": 30, "from": row[1], "unit_id": "enemy021_1"}])
		check(loop["gold"] == row[2] and int(BattlePlayLoop.unit(loop, "enemy023_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == row[3] and int(strike["gold_effects"][0]["paid"]) == 30 and (strike["gold_effects"][0].get("carried_by", "") == "enemy023_1") == (int(row[3]) > 0), "StealGold by mode 0x%x from %s leaves the party at %d and the caster's +0x98 gain at %d: %s" % [row[0], row[1], row[2], row[3], str(strike["gold_effects"])])
	var steal_cap := fixture()
	steal_cap["gold"] = BattleRewardRules.PARTY_GOLD_CAP - 10
	BattleLoopRewards.apply_gold_effects(steal_cap, {"attacker_id": "leonard"}, [{"kind": "steal_gold", "amount": 30, "from": "target_carry", "unit_id": "enemy021_1"}])
	check(steal_cap["gold"] == BattleRewardRules.PARTY_GOLD_CAP, "a StealGold take paid to the party is capped the same way")


static func wear_gold_cup(loop: Dictionary, id: String, slots: Array = ["accessory1"]) -> void:
	for slot in slots:
		BattlePlayLoop.unit_ref(loop, id)["equipment"].append({"slot": slot, "item_code": 230, "name": "黃金的聖杯"})


## 0x442720 state 2 (0x442819..0x442825): before either branch, 0x40e2d0(recipient) tests the live
## +0x18c bit 0x20 (0x40e240) and doubles the payment; ITEM gold_x2 is that bit (0x447e7c), OR-ed
## into the wearer's +0x18c by the equipment refresh (0x448709..0x448717). 230 黃金的聖杯 is the row.
func gold_double_cases() -> void:
	var gold_of := func(source: Dictionary, actor: String) -> int: return int(source["reward_data"]["actors"][actor]["gold"])
	var table: Dictionary = fixture()["equipment_items"]
	var doubling: Array = table.keys().filter(func(code): return bool(table[code].get("gold_double", false)))
	check(doubling == ["230"] and bool(table["230"]["supported"]), "ITEM gold_x2 is 230 黃金的聖杯 alone, now equippable: " + str(doubling))
	check(BattleEquipmentView.description_lines(table["230"]).has("獲得金錢加倍") and not BattleEquipmentView.description_lines(table["228"]).has("獲得金錢加倍"), "the equipment description names the gold doubling on 230 only")
	# A controlled killer wearing it: the kill gold reaches the party doubled.
	for slots in [["accessory1"], ["accessory1", "accessory2"]]:
		var loop := fixture()
		wear_gold_cup(loop, "leonard", slots)
		var kill_gold: int = gold_of.call(loop, "021")
		loop = attack(loop)
		check(BattlePlayLoop.unit(loop, "enemy021_1")["defeated"] and loop["gold"] == 2 * kill_gold and loop["settlement"]["gold"] == 2 * kill_gold and loop["last_combat"]["rewards"]["gold"] == 2 * kill_gold and loop["settlement"]["kills"] == [{"attacker_id": "leonard", "defender_id": "enemy021_1", "gold": 2 * kill_gold, "gold_multiplier": 2}], "Leonard wearing %d gold cup(s) is paid %d for a %d kill (doubled once): %s" % [slots.size(), 2 * kill_gold, kill_gold, str(loop["last_combat"]["rewards"])])
	# The counterer is the recipient of a counter kill (0x43f150 → 0x442720 with the counterer).
	var countered := fixture()
	wear_gold_cup(countered, "leonard")
	BattlePlayLoop.unit_ref(countered, "leonard")["combat_profile"]["attack_back"] = 100
	var counter_strike := BattleLoopCombat.resolve_exchange(countered, "enemy021_1", "leonard", func(_n): return 0)
	check(BattlePlayLoop.unit(countered, "enemy021_1")["defeated"] and countered["gold"] == 2 * gold_of.call(countered, "021"), "a counter kill by Leonard wearing it pays the party double: " + str(counter_strike.get("rewards", {})))
	# An enemy killer wearing it doubles what its own +0x98 gains.
	var enemy := fixture()
	wear_gold_cup(enemy, "enemy021_1")
	var victim_gold: int = BattleRewardRules.carried_gold(BattlePlayLoop.unit(enemy, "enemy023_1"), gold_of.call(enemy, "023"))
	var strike := enemy_kill(enemy)
	check(int(BattlePlayLoop.unit(enemy, "enemy021_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == 2 * victim_gold and strike["rewards"].get("carried", []) == [{"unit_id": "enemy021_1", "defender_id": "enemy023_1", "gold": 2 * victim_gold, "gold_multiplier": 2}] and enemy["gold"] == 0, "an enemy wearing it adds double the kill gold to its +0x98: " + str(strike.get("rewards", {})))
	# A friendly AI on exactly 0x10000 wearing it pays the party double.
	var ally := fixture()
	friendly(ally, 0x10000)
	wear_gold_cup(ally, "enemy023_1")
	BattleLoopCombat.resolve_exchange(ally, "enemy023_1", "enemy021_1", func(_n): return 0)
	check(ally["gold"] == 2 * gold_of.call(ally, "021") and not BattlePlayLoop.unit(ally, "enemy023_1").has(BattleRewardRules.CARRIED_GAINED), "a 0x10000 friendly AI wearing it pays the party double")
	# Doubled before the cap (0x442825 precedes 0x44283e).
	var capped := fixture()
	capped["gold"] = BattleRewardRules.PARTY_GOLD_CAP - 10
	wear_gold_cup(capped, "leonard")
	capped = attack(capped)
	check(capped["gold"] == BattleRewardRules.PARTY_GOLD_CAP and capped["last_combat"]["rewards"]["gold"] == 2 * gold_of.call(capped, "021"), "the doubled payment is still capped at 999,999,999")
	# StealGold's take rides the same state 2: doubled for the caster wearing it.
	for row in [["leonard", 0, "target_carry", 110, 0], ["enemy023_1", 0x20000, "party", 20, 60]]:
		var loop := fixture()
		loop["gold"] = 50
		if int(row[1]) != 0: friendly(loop, int(row[1]))
		wear_gold_cup(loop, row[0])
		var steal := {"attacker_id": row[0]}
		BattleLoopRewards.apply_gold_effects(loop, steal, [{"kind": "steal_gold", "amount": 30, "from": row[2], "unit_id": "enemy021_1"}])
		var applied: Dictionary = steal["gold_effects"][0]
		check(loop["gold"] == row[3] and int(BattlePlayLoop.unit(loop, row[0]).get(BattleRewardRules.CARRIED_GAINED, 0)) == row[4] and int(applied["paid"]) == 60 and int(applied["amount"]) == 30 and int(applied.get("gold_multiplier", 1)) == 2, "StealGold of 30 by %s wearing it (from %s) pays 60: party %d, +0x98 gain %d: %s" % [row[0], row[2], row[3], row[4], str(applied)])
	# The $ float shows the paid (doubled) take (0x44288a pushes the doubled esi).
	var aftermath: Node = BattleAftermath.new()
	root.add_child(aftermath)
	var units := [{"id": "hero", "actor_id": "001", "coord": Vector2i(2, 2), "dead_message": {"messages": []}},
		{"id": "foe", "actor_id": "021", "coord": Vector2i(2, 3), "dead_message": {"messages": []}}]
	aftermath.prepare({"sequence": 1, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 5, "defender_hp_after": 5, "hit": true,
		"gold_effects": [{"kind": "steal_gold", "amount": 30, "paid": 60, "from": "target_carry", "unit_id": "foe"}], "rewards": {"gold": 0, "kills": []}}, units)
	check(aftermath.jobs.map(func(job): return [job["kind"], int(job.get("gold", 0))]) == [["gold", 60]], "the $ float shows the paid StealGold take: " + str(aftermath.jobs))
	aftermath.cursor = aftermath.jobs.size()
	aftermath.queue_free()


## A killer that is not a player process rolls its victim's bag like any kill (0x44f580 from 0x44163e,
## 0x441587, 0x44469e, …) and 0x442720 state 4 gives it the collection through 0x44f600 instead of the
## get-item window (0x44272b／0x4428c3): one of each distinct code (0x44f290／0x44f39b) into the first
## empty slot (0x436e30); a full bag drops its first non-important item (0x44f510／0x436e80) and retries
## once; a second failure stops the walk; 0x44f4e0 then empties the collection.
func ai_handoff_cases() -> void:
	# Enemy A kills controlled B, whose bag holds two 281s and a 282 (important: always rolled).
	var loop := fixture()
	BattlePlayLoop.unit_ref(loop, "enemy021_1")["inventory"] = [241, 0, 0, 0, 0, 0, 0, 0]
	BattlePlayLoop.unit_ref(loop, "enemy023_1")["inventory"] = [281, 282, 281, 0, 0, 0, 0, 0]
	var strike := enemy_kill(loop)
	var sequence := int(strike["sequence"])
	check(BattlePlayLoop.unit(loop, "enemy023_1")["defeated"] and BattlePlayLoop.unit(loop, "enemy021_1")["inventory"] == [241, 281, 282, 0, 0, 0, 0, 0], "enemy A takes one of each code from B's bag into its first empty slots: " + str(BattlePlayLoop.unit(loop, "enemy021_1")["inventory"]))
	check(strike["rewards"].get("taken", []) == [{"code": 281, "slot": 1, "sources": ["%d:enemy023_1:0" % sequence, "%d:enemy023_1:2" % sequence], "unit_id": "enemy021_1"}, {"code": 282, "slot": 2, "sources": ["%d:enemy023_1:1" % sequence], "unit_id": "enemy021_1"}], "the receipt lists the hand-over, the repeated 281 folded into one entry: " + str(strike["rewards"].get("taken", [])))
	check(BattlePlayLoop.unit(loop, "enemy023_1")["inventory"] == EMPTY and not BattlePlayLoop.loot_waiting(loop) and loop["settlement"]["pending"].is_empty() and int(strike["rewards"]["item_count"]) == 0, "nothing reaches the party's get-item window and B's bag is emptied")
	# Killing A afterwards drops what it took (important items always roll).
	loop = attack(loop)
	var dropped: Array = loop["settlement"]["pending"].map(func(item): return int(item["code"]))
	check(dropped.filter(func(code): return code != 241) == [281, 282], "killing A puts the taken items in the party's window: " + str(dropped))
	# A full bag gives up its first non-important item and retries once.
	var full := fixture()
	BattlePlayLoop.unit_ref(full, "enemy021_1")["inventory"] = [281, 241, 246, 241, 241, 241, 241, 241]
	BattlePlayLoop.unit_ref(full, "enemy023_1")["inventory"] = [282, 0, 0, 0, 0, 0, 0, 0]
	var full_strike := enemy_kill(full)
	check(BattlePlayLoop.unit(full, "enemy021_1")["inventory"] == [281, 246, 241, 241, 241, 241, 241, 282] and full_strike["rewards"].get("taken", []) == [{"code": 282, "slot": 7, "sources": ["%d:enemy023_1:0" % int(full_strike["sequence"])], "discarded": 241, "unit_id": "enemy021_1"}], "a full bag drops its first non-important item (241 behind the important 281) and the rest close up: " + str(full_strike["rewards"].get("taken", [])))
	# An all-important full bag cannot make room: the first failure stops the walk, the collection is emptied.
	var locked := fixture()
	var locked_bag := [281, 282, 283, 284, 285, 281, 282, 283]
	BattlePlayLoop.unit_ref(locked, "enemy021_1")["inventory"] = locked_bag.duplicate()
	BattlePlayLoop.unit_ref(locked, "enemy023_1")["inventory"] = [284, 285, 0, 0, 0, 0, 0, 0]
	var locked_strike := enemy_kill(locked)
	check(BattlePlayLoop.unit(locked, "enemy021_1")["inventory"] == locked_bag and locked_strike["rewards"].get("taken", []).map(func(row): return int(row["slot"])) == [-1, -1] and BattlePlayLoop.unit(locked, "enemy023_1")["inventory"] == EMPTY and not BattlePlayLoop.loot_waiting(locked), "an all-important full bag keeps its items and the taken ones are lost: " + str(locked_strike["rewards"].get("taken", [])))
	# The dead controlled initiator's bag goes to the enemy whose counter killed it (0x44469e).
	var countered := fixture()
	var initiator := BattlePlayLoop.unit_ref(countered, "enemy023_1")
	initiator["coord"] = BattlePlayLoop.unit(countered, "enemy021_1")["coord"] + Vector2i.DOWN
	initiator["hp"] = 1
	initiator["combat_profile"]["live_defense"] = 0
	initiator["inventory"] = [283, 0, 0, 0, 0, 0, 0, 0]
	BattlePlayLoop.unit_ref(countered, "enemy021_1")["hp"] = 1000
	BattlePlayLoop.unit_ref(countered, "enemy021_1")["combat_profile"]["attack_back"] = 100
	BattlePlayLoop.unit_ref(countered, "enemy021_1")["inventory"] = EMPTY.duplicate()
	BattleLoopCombat.resolve_exchange(countered, "enemy023_1", "enemy021_1", func(_n): return 0)
	check(BattlePlayLoop.unit(countered, "enemy023_1")["defeated"] and BattlePlayLoop.unit(countered, "enemy021_1")["inventory"] == [283, 0, 0, 0, 0, 0, 0, 0] and not BattlePlayLoop.loot_waiting(countered), "the counterer takes the dead controlled initiator's item: " + str(BattlePlayLoop.unit(countered, "enemy021_1")["inventory"]))
	# A friendly AI on 0x10000 pays the party its gold, but the drops still go to its own bag.
	var ally := fixture()
	friendly(ally, 0x10000)
	BattlePlayLoop.unit_ref(ally, "enemy023_1")["inventory"] = EMPTY.duplicate()
	var ally_strike := BattleLoopCombat.resolve_exchange(ally, "enemy023_1", "enemy021_1", func(_n): return 0)
	check(BattlePlayLoop.unit(ally, "enemy021_1")["defeated"] and BattlePlayLoop.unit(ally, "enemy023_1")["inventory"] == [281, 282, 0, 0, 0, 0, 0, 0] and not BattlePlayLoop.loot_waiting(ally) and ally["gold"] == int(ally["reward_data"]["actors"]["021"]["gold"]), "a 0x10000 friendly AI's kill pays the party but its drops go to its own bag: " + str(ally_strike["rewards"]))
	# 金之手 by an AI caster: 0x44f2d0 puts the take in the caster's own collection (state 4 → its bag);
	# a controlled caster keeps the get-item window.
	for caster in ["enemy023_1", "leonard"]:
		var steal := fixture()
		friendly(steal, 0x10000)
		BattlePlayLoop.unit_ref(steal, "enemy023_1")["inventory"] = EMPTY.duplicate()
		var receipt := {"sequence": BattleRewardRules.combat_sequence(steal["settlement"]) + 1, "attacker_id": caster, "defender_id": "enemy021_1", "defender_hp_before": 1, "defender_hp_after": 1, "hit": true,
			"stolen_items": [{"kind": "steal_item", "code": 281, "source_slot": 0, "unit_id": "enemy021_1", "steal_roll": 7}]}
		BattleLoopRewards.commit_rewards(steal, receipt)
		if caster == "enemy023_1":
			check(BattlePlayLoop.unit(steal, "enemy023_1")["inventory"] == [281, 0, 0, 0, 0, 0, 0, 0] and not BattlePlayLoop.loot_waiting(steal) and receipt["rewards"].get("taken", []).size() == 1, "an AI caster's 金之手 take goes into its own bag: " + str(receipt["rewards"]))
		else:
			check(BattlePlayLoop.loot_waiting(steal) and steal["settlement"]["pending"].map(func(item): return int(item["code"])) == [281] and not receipt["rewards"].has("taken"), "control: a controlled caster's 金之手 take waits in the get-item window")


## A lethal hit on an undead defender: the kill sections read the victim's +0xd8 <= 0 before its own
## tick revives it (0x4446d3 player／0x4415bc AI／0x442e5c・0x443130 spells; 0x43ee66／0x4433b6), so
## the kill gold 0x40e390 — a plain read of +0x98 — is paid on every such hit; 0x44f580 rolls no drops
## for an undead record (0x446bb0) and the revived unit is no death.
func undead_victim_cases() -> void:
	var gold_of := func(source: Dictionary, actor: String) -> int: return int(source["reward_data"]["actors"][actor]["gold"])
	var meta := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": false, "growth_notified_level": 1}
	# Exchange: Leonard's lethal strike on an undead enemy, twice.
	var loop := fixture()
	BattlePlayLoop.unit_ref(loop, "enemy021_1")["undead"] = true
	var kill_gold: int = gold_of.call(loop, "021")
	var first := BattleLoopCombat.resolve_exchange(loop, "leonard", "enemy021_1", func(_n): return 0)
	check(bool(first.get("undead_revived", false)) and int(BattlePlayLoop.unit(loop, "enemy021_1")["hp"]) == 1 and not BattlePlayLoop.unit(loop, "enemy021_1")["defeated"], "the undead enemy gets up at 1 HP after Leonard's lethal strike")
	check(loop["gold"] == kill_gold and first["rewards"]["kills"] == [{"attacker_id": "leonard", "defender_id": "enemy021_1", "gold": kill_gold}], "the lethal strike on the undead enemy pays its kill gold: " + str(first["rewards"]))
	check(not BattlePlayLoop.loot_waiting(loop) and BattlePlayLoop.unit(loop, "enemy021_1")["inventory"] == [281, 282, 0, 0, 0, 0, 0, 0] and not loop["rewarded_unit_ids"].has("enemy021_1"), "no drops are rolled, its bag stays and it is not in the death ledger")
	BattleLoopCombat.resolve_exchange(loop, "leonard", "enemy021_1", func(_n): return 0)
	check(loop["gold"] == 2 * kill_gold and int(BattlePlayLoop.unit(loop, "enemy021_1")["hp"]) == 1, "the next lethal strike on it pays the kill gold again (0x40e390 only reads +0x98): " + str(loop["gold"]))
	check(BattleCheckpoint.encode(loop, meta)["ok"], "the checkpoint accepts the battle after the undead enemy got up")
	# Spell: an area cast kills an undead and an ordinary enemy together.
	var cast := fixture()
	var player := BattlePlayLoop.unit_ref(cast, "leonard")
	player["mp"] = 100
	player["max_mp"] = 100
	var skill := "magic:magicMIND:magicCode02"
	TestSuite.own(cast, "skill_book")["actors"]["001"]["supported_initial_ids"].append(skill)
	TestSuite.own(cast, "skill_book")["skills"][skill]["fields"]["effect_range"] = "range1Cell"
	BattlePlayLoop.unit_ref(cast, "enemy021_1")["undead"] = true
	var secondary := BattlePlayLoop.unit_ref(cast, "enemy021_2")
	secondary["coord"] = Vector2i(17, 15)
	secondary["hp"] = 2
	secondary["inventory"] = [283, 0, 0, 0, 0, 0, 0, 0]
	cast = BattlePlayLoop.select_player_unit(cast, "leonard")
	cast = BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(cast, "magic"), skill)
	var result := BattlePlayLoop.attack_target(cast, "enemy021_1", func(_n): return 0)
	check(result.get("last_combat", {}).get("undead_revived", []) == ["enemy021_1"] and int(BattlePlayLoop.unit(result, "enemy021_1")["hp"]) == 1 and BattlePlayLoop.unit(result, "enemy021_2")["defeated"], "the area cast revives the undead target and kills the other: " + str(result.get("last_attack_reject", {})))
	check(result["gold"] == 2 * kill_gold and result["settlement"]["pending"].map(func(item): return int(item["code"])) == [283], "both kill golds are paid; only the ordinary enemy's bag is rolled: " + str(result["settlement"]["pending"]))
	check(result["rewarded_unit_ids"] == ["enemy021_2"] and BattlePlayLoop.unit(result, "enemy021_1")["inventory"] == [281, 282, 0, 0, 0, 0, 0, 0], "the revived target is not recorded as a death and keeps its bag")
	var encoded := BattleCheckpoint.encode(result, meta)
	check(encoded["ok"], "the checkpoint accepts the cast (the revived unit is no longer a death-ledger entry): " + str(encoded.get("reason", "")))
	# An enemy's lethal strike on an undead controlled unit: its +0x98 gains the kill gold, no bag is handed over.
	var enemy := fixture()
	var victim := BattlePlayLoop.unit_ref(enemy, "enemy023_1")
	victim["undead"] = true
	victim["inventory"] = [283, 0, 0, 0, 0, 0, 0, 0]
	BattlePlayLoop.unit_ref(enemy, "enemy021_1")["inventory"] = EMPTY.duplicate()
	var victim_gold: int = BattleRewardRules.carried_gold(victim, gold_of.call(enemy, "023"))
	var strike := enemy_kill(enemy)
	check(int(BattlePlayLoop.unit(enemy, "enemy023_1")["hp"]) == 1 and int(BattlePlayLoop.unit(enemy, "enemy021_1").get(BattleRewardRules.CARRIED_GAINED, 0)) == victim_gold and BattlePlayLoop.unit(enemy, "enemy021_1")["inventory"] == EMPTY and BattlePlayLoop.unit(enemy, "enemy023_1")["inventory"] == [283, 0, 0, 0, 0, 0, 0, 0] and not strike["rewards"].has("taken"), "an enemy's lethal strike on an undead unit adds its kill gold to the enemy's +0x98 and takes no item: " + str(strike["rewards"]))


func checkpoint_cases() -> void:
	var loop := attack(fixture())
	var meta := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": false, "growth_notified_level": 1}
	var expected := BattleCheckpoint.configuration(loop)
	for stage in range(4):
		var encoded := BattleCheckpoint.encode(loop, meta)
		check(encoded["ok"], "save accepts an actual settlement boundary: " + str(encoded.get("reason", "")))
		if not encoded["ok"]: return
		var decoded := BattleCheckpoint.decode(encoded["bytes"], loop)
		check(decoded["ok"] and decoded["snapshot"]["loop"] == loop, "restore preserves gold, stock, EXP, queue, damage stream and claims exactly")
		var different := BattlePlayLoop.copy(loop)
		different["skill_rules"] = {"initial_stamina": 0}
		check(not BattleCheckpoint.decode(encoded["bytes"], different)["ok"], "different configuration cannot restore")
		var bytes: PackedByteArray = encoded["bytes"].duplicate()
		bytes[bytes.size() - 2] ^= 1
		check(not BattleCheckpoint.decode(bytes, loop)["ok"], "damaged save rejects before state replacement")
		if stage < 2:
			loop = BattlePlayLoop.claim_reward(loop, 1, stage, loop["settlement"]["pending"][0]["id"], "leonard")
		elif stage == 2: loop = BattlePlayLoop.finish_rewards(loop, 1, 2)
	var invalid := loop.duplicate(true)
	invalid["units"].append(invalid["units"][0].duplicate(true))
	check(not BattleCheckpoint.encode(invalid, meta)["ok"], "duplicate actor identity cannot become a resumable save")
	var retired := {"schema": "hsl_battle_checkpoint.v1", "configuration": expected, "loop": loop, "view": meta}
	check(BattleCheckpoint.validate(retired, loop) == "unsupported_save_schema", "a v1 snapshot (first-battle skill manifests in its configuration) is refused by name, not as a generic format error")
	var whole := {"schema": "hsl_battle_checkpoint.v2", "configuration": expected, "loop": loop, "view": meta}
	check(BattleCheckpoint.validate(whole, loop) == "unsupported_save_schema", "a v2 snapshot (whole loop with its configuration written) is refused by name")
	var keyed := BattleCheckpoint.state(loop)
	keyed["battle_outcome"] = "victory_escape"
	var v3 := {"schema": "hsl_battle_checkpoint.v3", "configuration": expected, "loop": keyed, "view": meta}
	check(BattleCheckpoint.validate(v3, loop) == "unsupported_save_schema", "a v3 snapshot (battle_outcome written as a key string) is refused by name: no save migration")
	var v5 := {"schema": "hsl_battle_checkpoint.v5", "configuration": expected, "loop": BattleCheckpoint.state(loop), "view": meta}
	check(BattleCheckpoint.validate(v5, loop) == "unsupported_save_schema", "a v5 snapshot (Park-Miller initialization_rng birth receipts) is refused by name: no save migration")
	check(TestSuite.carries_no_stream(BattleCheckpoint.state(loop)), "the global stream is left out of the saved state (0x4795d4／0x4795d8 are outside the original's save)")
	var relabeled := {"schema": BattleCheckpoint.SCHEMA, "configuration": expected, "loop": keyed, "view": meta}
	check(BattleCheckpoint.validate(relabeled, loop) == "invalid_saved_outcome", "a v4-labelled snapshot still carrying a key-string outcome is refused as an invalid outcome")
	for bad_outcome in [{"result": "victory"}, {"result": "draw", "reason": "escape"}, {"result": "victory", "reason": "leonard"}]:
		var malformed := BattleCheckpoint.state(loop)
		malformed["battle_outcome"] = bad_outcome
		check(BattleCheckpoint.validate({"schema": BattleCheckpoint.SCHEMA, "configuration": expected, "loop": malformed, "view": meta}, loop) == "invalid_saved_outcome", "a malformed outcome %s is refused" % str(bad_outcome))
	var state_only := BattleCheckpoint.state(loop)
	check(BattlePlayLoop.CONFIG_SHARED.all(func(key): return not state_only.has(key)) and state_only.has("units") and var_to_bytes(state_only).size() * 2 < var_to_bytes(loop).size(), "v4 writes the state half only; the configuration stays with the running battle")
	var path := "res://ignored/battle-settlement/test.save"
	check(BattleCheckpoint.write(path, loop, meta)["ok"], "atomic save file write succeeds")
	var from_disk := BattleCheckpoint.read(path, loop)
	check(from_disk["ok"] and from_disk["snapshot"]["loop"] == loop, "fresh file read preserves completed settlement")
	DirAccess.remove_absolute(path)


func stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer: TestSuite.stop_audio(node)
	for child in node.get_children(): stop_audio(child)

extends "res://tests/support/TestSuite.gd"
const GameOptions = preload("res://game/settings/GameOptions.gd")
## The two extra turns of the source. Extra attack (double_attack): the complete ordinary
## series — source numeric helpers have their own oracles; these cases protect composition,
## one award, and player-visible timing. Extra action (White Wings／action_twice): the
## original_extra_action.json prefixes, then the second decision and the owner-turn handoff.
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const run_ordinary_special_tests = preload("res://tests/run_ordinary_special_tests.gd")
const CombatSequenceRules = preload("res://game/sim/CombatSequenceRules.gd")
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const BattleAftermath = preload("res://game/battle/scene/BattleAftermath.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const ExtraActionRules = preload("res://game/sim/ExtraActionRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const HEAL := "magic:magicWATER:magicCode06"
const CURE := "magic:magicWATER:magicCode05"
const WIND := "magic:magicAIR:magicCode01"
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}


func _init() -> void:
	tag = "EXTRA_ATTACK_TESTS"


func run() -> void:
	source_cases()
	series_cases()
	miss_cases()
	action_native_cases()
	wait_cases()
	series_and_outcome_cases()


static func fixture(primary: bool = true, counter: bool = false) -> Dictionary:
	var loop := run_ordinary_special_tests.fixture()
	own(loop, "skill_book")["actors"]["001"]["double_attack"] = primary
	own(loop, "skill_book")["actors"]["021"]["double_attack"] = counter
	return loop


func source_cases() -> void:
	var stock := BattleFixture.loop()
	check(stock["units"].all(func(actor): return BattlePlayLoop.attack_count(stock, actor)["count"] == 1), "default first-battle actors retain their source single strikes")
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_extra_attack.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		if input["kind"] not in ["query", "innate"]: continue
		var unit := BattlePlayLoop.unit(stock, "leonard")
		var items: Dictionary = stock["equipment_items"].duplicate(true)
		for slot in unit["equipment"]: items[str(int(slot["item_code"]))]["double_attack"] = (int(input["effects"]) & 0x8000) != 0
		var source := {"double_attack": (int(input.get("capability", 0)) & 0x200) != 0}
		var actual := CombatSequenceRules.attack_count(unit, source, items)
		var extra := int(row["native"]["extra"]) if input["kind"] == "query" else int((int(row["native"]["effects"]) & 0x8000) != 0)
		check(actual["ok"] and actual["count"] == 1 + extra, "source query/innate OR mapping agrees with original output")
	var actor := BattlePlayLoop.unit(stock, "leonard")
	actor["equipment"] = []
	check(CombatSequenceRules.attack_count(actor, {"double_attack": true}, stock["equipment_items"])["count"] == 1, "innate mapping retains the original nonempty-equipment boundary")
	actor["equipment"] = [{"slot":"weapon", "item_code":12}, {"slot":"accessory1", "item_code":12}]
	check(CombatSequenceRules.attack_count(actor, {"double_attack":true}, stock["equipment_items"])["count"] == 2, "multiple source flags OR together and never create a third strike")
	check(stock["equipment_items"]["12"]["supported"] and stock["equipment_items"]["69"]["supported"] and stock["equipment_items"]["69"]["double_attack"] and stock["equipment_items"]["55"]["supported"], "independently verified sword12 and bow69 open; weapon55 is supported through its compiled range5CellCircle, not through them")


func series_cases() -> void:
	for count in [1, 2]:
		var loop := fixture(true, count == 2)
		BattlePlayLoop.unit_ref(loop, "enemy021_1")["combat_profile"]["attack_back"] = 100
		var before := loop.duplicate(true)
		var after := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop, "attack"), "enemy021_1", func(_n): return 0)
		var receipt: Dictionary = after["last_attack"]
		var strikes := CombatSequenceRules.strikes(receipt)
		check(strikes.size() == 2 + count and strikes.slice(0,2).all(func(hit): return not hit["is_counter"]), "all main strikes finish before the single counter series")
		check(strikes.slice(2).all(func(hit): return hit["is_counter"] and not hit.has("counter")), "counter series never recursively counters")
		check(BattlePlayLoop.unit(after,"enemy021_1")["hp"] == 60 and BattlePlayLoop.unit(after,"leonard")["hp"] == 100 - 16 * count, "every independently resolved main/counter hit changes HP exactly once")
		check(not receipt.has("stamina_gain") and receipt["followups"][0].has("stamina_gain"), "first nonlethal extra strike skips the native final ST tail")
		check(BattlePlayLoop.unit(after,"leonard")["stamina"] == 29 and BattlePlayLoop.unit(after,"enemy021_1")["stamina"] == 9, "ST is awarded once at each series end, not once per extra hit")
		check(receipt["experience"]["gained"] == receipt["experience_basis"]["points"] + receipt["followups"][0]["experience_basis"]["points"] and not receipt["followups"][0].has("experience"), "two contributions become one participant EXP award")
		check(loop == before and after["turn_queue"] == before["turn_queue"], "player accepts the whole exchange without mutating caller or advancing early")
		var finished := BattlePlayLoop.finish_exhausted_action(after)
		check(finished["selected_unit_id"] == "enemy023_1" and finished["turn_queue"]["index"] == 1 and BattlePlayLoop.finish_exhausted_action(finished) == finished, "one completion hands off once despite two or four strikes")
		var repeated := BattlePlayLoop.attack_target(after, "enemy021_1", no_rng)
		check(repeated["units"] == after["units"] and repeated["last_combat"] == after["last_combat"], "late repeated targeting cannot replay series or reward")
	for hp in [1, 30]:
		var loop := fixture()
		BattlePlayLoop.unit_ref(loop,"enemy021_1")["hp"] = hp
		BattlePlayLoop.unit_ref(loop,"enemy021_1")["combat_profile"]["attack_back"] = 100
		BattlePlayLoop.unit_ref(loop,"leonard")["kill_chain_word"] = 2
		var receipt := BattleLoopCombat.resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
		var strikes := CombatSequenceRules.strikes(receipt)
		check(strikes.size() == (1 if hp == 1 else 2) and receipt["counter"].is_empty(), "lethal first/final strike cancels every remaining hit and counter")
		check(strikes.back()["actual_damage"] == (1 if hp == 1 else 10) and strikes.back()["experience_basis"]["kill_chain_before"] == 2, "final hit uses actual remaining HP and the prior kill chain")
		check(BattlePlayLoop.unit(loop,"leonard")["kill_count"] == 1 and receipt["kill_chain"] == 3, "a lethal series adds one kill, not the number of blows")
		check(BattleAftermath.defeated_ids(receipt) == ["enemy021_1"] and receipt["rewards"]["kills"].size() == 1, "late-hit death is traversed by shared aftermath and loot exactly once")
		var reward_again := BattlePlayLoop.RewardRules.generate(receipt,loop["units"],loop["reward_data"],stream_of(loop, "reward"),loop["rewarded_unit_ids"])
		check(reward_again["gold"] == 0 and reward_again["deaths"].is_empty(), "saved death ledger prevents rewarding the series twice")
	var loop := fixture(false,true)
	BattlePlayLoop.unit_ref(loop,"leonard")["hp"] = 31
	BattlePlayLoop.unit_ref(loop,"enemy021_1")["combat_profile"]["attack_back"] = 100
	BattlePlayLoop.unit_ref(loop,"enemy021_1")["kill_chain_word"] = 2
	var receipt := BattleLoopCombat.resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
	check(receipt["counter"]["followups"][0]["experience_basis"]["kill_multiplier"] == 200 and receipt["counter"]["kill_chain"] == 3, "first nonlethal counter does not clear the chain before its second lethal hit")
	check(receipt["experience_settlement"]["reason"] == "actor_defeated" and not receipt.has("experience"), "a later fatal counter suppresses posthumous growth from the earlier strike")
	check(BattleAftermath.defeated_ids(receipt) == ["leonard"], "death from an additional counter remains visible to terminal aftermath")
	var grown := fixture()
	BattlePlayLoop.unit_ref(grown,"leonard")["exp"] = 99
	var growth_hit := BattleLoopCombat.resolve_exchange(grown,"leonard","enemy021_1",func(_n):return 0)
	check(growth_hit["followups"][0]["attacker_before"]["level"] == 1 and growth_hit["followups"][0]["attacker_before"]["exp"] == 99 and growth_hit["experience"]["level_after"] == 2, "first-hit contribution cannot level up or change second-hit damage early")


func miss_cases() -> void:
	for mode in ["first", "last", "all"]:
		var loop := fixture()
		BattlePlayLoop.unit_ref(loop,"leonard")["combat_profile"]["live_hit_ratio"] = 80
		var hundreds := [0]
		var receipt := BattleLoopCombat.resolve_exchange(loop,"leonard","enemy021_1",func(bound):
			if bound == 100:
				hundreds[0] += 1
				if (mode == "first" and hundreds[0] == 2) or (mode == "last" and hundreds[0] == 4) or mode == "all": return 99
			return 0)
		var hits := CombatSequenceRules.participant_strikes(receipt)
		check(hits.size() == 2, "an earlier miss still permits the source extra strike")
		check(hits[0]["hit"] == (mode == "last") and hits[1]["hit"] == (mode == "first"), "each strike samples its own hit and retains miss compensation")
		check(not hits[0].has("stamina_gain") and hits[1].has("stamina_gain") == (mode == "first"), "last-hit miss cannot recover skipped first-hit stamina")
		check(receipt.has("experience") == (mode != "all"), "only effective contributions enter final EXP even when a later strike misses")
		if mode == "first": check(hits[1]["hit_rate"] > hits[0]["hit_rate"], "the second strike reads the first miss's native hit bonus")


static func wings_fixture(wings: bool = true, ai: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var actor := BattlePlayLoop.unit(loop,"enemy026_1" if ai else "leonard")
	var ally := BattlePlayLoop.unit(loop,"enemy023_1")
	var enemy := BattlePlayLoop.unit(loop,"leonard" if ai else "enemy021_1")
	actor.merge({"coord":Vector2i(8,8),"live_speed":120,"hp":100,"max_hp":100,"mp":100,"max_mp":100,
		"inventory":[227,241,241,246,0,0,0,0]},true)
	ally.merge({"coord":Vector2i(8,9),"live_speed":100,"hp":100,"max_hp":100,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER},true)
	enemy.merge({"coord":Vector2i(10,8),"live_speed":90,"hp":500,"max_hp":500},true)
	loop["units"] = [actor,ally,enemy]; loop["tiles"] = {}; loop["map_size"] = Vector2i(20,20)
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	if ai:
		if wings: actor["equipment"].append({"slot":"accessory2","item_code":227})
		loop["interaction"] = "ai_resolving"
		return loop
	loop = BattlePlayLoop.select_player_unit(loop,actor["id"])
	return BattlePlayLoop.change_equipment(loop,"accessory2",0,227) if wings else loop


func wait_cases() -> void:
	var loop := wings_fixture()
	check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(loop,"leonard")["equipment"],"accessory2") == 227, "White Wings can be equipped through the normal free transaction")
	var poisoned := BattlePlayLoop.unit_ref(loop,"leonard")
	poisoned.merge(BattlePlayLoop.StatusEffectRules.apply(poisoned,"poison",3,7)["changes"],true)
	var before := loop.duplicate(true)
	var again := BattlePlayLoop.choose_command(loop,"wait")
	check(again["selected_unit_id"] == "leonard" and again["interaction"] == "action_menu" and again["turn_queue"] == before["turn_queue"], "first Wait grants the same actor a fresh action before any queue change")
	check(BattlePlayLoop.unit(again,"leonard")["hp"] == poisoned["hp"] and BattlePlayLoop.unit(again,"leonard")["status_counters"] == poisoned["status_counters"], "poison and duration do not tick between the two actions")
	var ended := BattlePlayLoop.choose_command(again,"wait")
	check(ended["selected_unit_id"] == "enemy023_1" and ended["turn_queue"]["index"] == 1, "second Wait hands off exactly once")
	check(BattlePlayLoop.unit(ended,"leonard")["hp"] == int(poisoned["hp"]) - 7 and (int(BattlePlayLoop.unit(ended,"leonard")["status_counters"]["poison"]) & 0xffff) == 2, "whole owner turn applies one poison tick and one duration decrement")


func action_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_extra_action.json"))
	for row in packet["prefixes"]:
		var input: Dictionary = row["input"]
		var state := {"owner_id":"unit" if int(input["latch"]) == 1 else "", "pending":int(input["latch"]) == 1,"sequence":7}
		var actual := ExtraActionRules.complete(state,"unit",(int(input["effects"]) & 8) != 0)
		check(actual["repeat"] == row["native"]["again"] and int(actual["state"]["pending"]) == int(row["native"]["latch"]), "same pure gate agrees with original player/AI completion prefix")
		check(ExtraActionRules.state_error(actual["state"],"unit") == "", "native-composed extra-action state has one owner")
	var stock := BattleFixture.loop()
	for row in packet["queries"]:
		var catalog: Dictionary = stock["equipment_items"].duplicate(true)
		catalog["227"]["action_twice"] = (int(row["effects"]) & 8) != 0
		var actor := BattlePlayLoop.unit(stock,"leonard")
		actor["equipment"] = [{"slot":"accessory1","item_code":227},{"slot":"accessory2","item_code":227}]
		check(ExtraActionRules.equipment(actor,catalog)["count"] == 1 + int(row["native"]), "duplicate flags OR to at most two actions, separate from double_attack")
	check(stock["equipment_items"]["227"]["supported"] and stock["equipment_items"]["55"]["supported"], "supported Wings do not decide weapon55; its support comes from its compiled range5CellCircle")
	check(stock["units"].all(func(actor):return ExtraActionRules.equipment(actor,stock["equipment_items"])["count"] == 1), "default first-battle actors still have one action")


func cast(loop: Dictionary, id: String, target: String) -> Dictionary:
	return BattlePlayLoop.attack_target(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop,"magic"),id),target,zero)


func series_and_outcome_cases() -> void:
	var base: Dictionary = fixture(true,true)
	BattlePlayLoop.unit_ref(base,"leonard")["equipment"].append({"slot":"accessory2","item_code":227})
	BattlePlayLoop.unit_ref(base,"enemy021_1")["combat_profile"]["attack_back"] = 100
	BattlePlayLoop.unit_ref(base,"enemy021_1")["hp"] = 500
	BattlePlayLoop.unit_ref(base,"enemy021_1")["max_hp"] = 500
	var first := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(base,"attack"),"enemy021_1",zero)
	var first_receipt: Dictionary = first["last_combat"].duplicate(true)
	check(BattlePlayLoop.CombatSequence.strikes(first_receipt).size() == 4, "extra action and double_attack retain a complete independent primary/counter series")
	var next := BattlePlayLoop.finish_exhausted_action(first)
	var second := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(next,"attack"),"enemy021_1",zero)
	check(BattlePlayLoop.CombatSequence.strikes(second["last_combat"]).size() == 4 and second["last_combat"]["sequence"] == first_receipt["sequence"] + 1, "second action creates another complete series instead of replaying the first receipt")
	check(BattlePlayLoop.unit(second,"leonard")["stamina"] > BattlePlayLoop.unit(first,"leonard")["stamina"] and second["last_combat"].has("experience"), "second series supplies its own native stamina and final EXP")
	var counter_only := wings_fixture(false)
	BattlePlayLoop.unit_ref(counter_only,"leonard")["coord"] = Vector2i(9,8)
	BattlePlayLoop.unit_ref(counter_only,"leonard")["hp"] = 500
	BattlePlayLoop.unit_ref(counter_only,"leonard")["max_hp"] = 500
	BattlePlayLoop.unit_ref(counter_only,"enemy021_1")["equipment"].append({"slot":"accessory2","item_code":227})
	BattlePlayLoop.unit_ref(counter_only,"enemy021_1")["combat_profile"]["attack_back"] = 100
	counter_only = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(counter_only,"attack"),"enemy021_1",zero)
	check(not counter_only["last_combat"]["counter"].is_empty(), "equipped future actor can counter during someone else's action")
	counter_only = BattlePlayLoop.finish_exhausted_action(counter_only)
	check(counter_only["selected_unit_id"] == "enemy023_1" and not counter_only["extra_action"]["pending"], "a Wings counterattacker cannot receive an out-of-turn extra action")
	var kills := wings_fixture()
	BattlePlayLoop.unit_ref(kills,"leonard")["coord"] = Vector2i(9,8)
	BattlePlayLoop.unit_ref(kills,"leonard")["inventory"][0] = 228
	kills = BattlePlayLoop.change_equipment(kills,"accessory1",0,228)
	var second_foe := BattlePlayLoop.unit(kills,"enemy021_1")
	second_foe.merge({"id":"enemy021_2","coord":Vector2i(10,9),"hp":1,"inventory":[0,0,0,0,0,0,0,0]},true)
	kills["units"].append(second_foe)
	BattlePlayLoop.unit_ref(kills,"enemy021_1").merge({"hp":1,"inventory":[0,0,0,0,0,0,0,0]},true)
	kills = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(kills,"attack"),"enemy021_1",zero)
	check(kills["last_combat"]["experience"]["multiplier"] == 2, "first extra-action strike keeps the separately equipped native EXP modifier")
	kills = BattlePlayLoop.finish_exhausted_action(kills)
	check(BattlePlayLoop.unit(kills,"leonard")["kill_chain_word"] == 0x10001, "first lethal action retains the native kill mark into the immediate repeat")
	kills = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(kills,"move"),Vector2i(9,9))
	kills = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(kills,"attack"),"enemy021_2",zero)
	check(kills["last_combat"]["experience_basis"]["kill_multiplier"] == 150 and kills["last_combat"]["experience"]["multiplier"] == 2 and BattlePlayLoop.unit(kills,"leonard")["kill_count"] == 2, "second independent kill uses prior-chain150% and the same final EXP modifier exactly once")
	for ordinal in [1,2]:
		var kill := wings_fixture()
		BattlePlayLoop.unit_ref(kill,"leonard")["coord"] = Vector2i(9,8)
		BattlePlayLoop.unit_ref(kill,"leonard")["exp"] = 99
		BattlePlayLoop.unit_ref(kill,"enemy021_1")["hp"] = 1
		if ordinal == 2: kill = BattlePlayLoop.choose_command(kill,"wait")
		var won := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(kill,"attack"),"enemy021_1",zero)
		check(won["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED and not won["extra_action"]["pending"], "lethal action ends battle without a spare action: " + str(ordinal))
		check(BattlePlayLoop.unit(won,"leonard")["level"] == 2 and won["last_combat"].has("experience"), "terminal first/second action still commits final EXP and one level")
		check(BattleCheckpoint.encode(won,VIEW)["ok"] and BattlePlayLoop.finish_exhausted_action(won) == won, "terminal save/repeated finish does not grant or settle again")
		var flee := wings_fixture()
		if ordinal == 2: flee = BattlePlayLoop.choose_command(flee,"wait")
		BattlePlayLoop.unit_ref(flee,"leonard")["coord"] = flee["escape_zone"][0]
		var escaped := BattlePlayLoop.choose_command(flee,"wait")
		check(escaped["battle_outcome"] == BattleOutcome.VICTORY_ESCAPE and not escaped["extra_action"]["pending"], "escape ends either action instead of looping the current actor")
		var death := base.duplicate(true)
		if ordinal == 2: death = BattlePlayLoop.choose_command(death,"wait")
		BattlePlayLoop.unit_ref(death,"leonard")["hp"] = 1
		death = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(death,"attack"),"enemy021_1",zero)
		check(death["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN and not death["extra_action"]["pending"] and not death["last_combat"].has("experience"), "fatal counter cancels any extra action and posthumous growth")
	var departing := wings_fixture(true,true)
	departing = BattlePlayLoop.step_ai_turn(departing,zero)
	var changed := departing.duplicate(true)
	BattleLoopScript.commit_departures(changed, ["enemy026_1"], "winfail", "event_3")
	check(not changed["extra_action"]["pending"] and BattlePlayLoop.CoreTurnQueue.current(changed["turn_queue"])["id"] != "enemy026_1", "scripted departure discards only the departing actor's pending repeat")

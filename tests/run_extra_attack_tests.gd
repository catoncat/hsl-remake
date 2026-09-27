extends "res://tests/support/TestSuite.gd"
const GameOptions = preload("res://game/settings/GameOptions.gd")
## The two extra turns of the source. Extra attack (double_attack): the complete ordinary
## series — source numeric helpers have their own oracles; these cases protect composition,
## one award, and player-visible timing. Extra action (White Wings／action_twice): the
## original_extra_action.json prefixes, then the second decision and the owner-turn handoff.
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const LoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const Cases = preload("res://tests/run_ordinary_special_tests.gd")
const Sequence = preload("res://game/sim/CombatSequenceRules.gd")
const Cutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const Aftermath = preload("res://game/battle/scene/BattleAftermath.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Extra = preload("res://game/sim/ExtraActionRules.gd")
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
	equipment_and_rejection_cases()
	skill_and_terminal_cases()
	await presentation_cases()
	action_native_cases()
	wait_cases()
	command_cases()
	equipment_restore_cases()
	series_and_outcome_cases()
	ai_cases()
	await cue_cases()


static func fixture(primary: bool = true, counter: bool = false) -> Dictionary:
	var loop := Cases.fixture()
	own(loop, "skill_book")["actors"]["001"]["double_attack"] = primary
	own(loop, "skill_book")["actors"]["021"]["double_attack"] = counter
	return loop


func source_cases() -> void:
	var stock := BattleFixture.loop()
	check(stock["units"].all(func(actor): return Loop.attack_count(stock, actor)["count"] == 1), "default first-battle actors retain their source single strikes")
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_extra_attack.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		if input["kind"] not in ["query", "innate"]: continue
		var unit := Loop.unit(stock, "leonard")
		var items: Dictionary = stock["equipment_items"].duplicate(true)
		for slot in unit["equipment"]: items[str(int(slot["item_code"]))]["double_attack"] = (int(input["effects"]) & 0x8000) != 0
		var source := {"double_attack": (int(input.get("capability", 0)) & 0x200) != 0}
		var actual := Sequence.attack_count(unit, source, items)
		var extra := int(row["native"]["extra"]) if input["kind"] == "query" else int((int(row["native"]["effects"]) & 0x8000) != 0)
		check(actual["ok"] and actual["count"] == 1 + extra, "source query/innate OR mapping agrees with original output")
	var actor := Loop.unit(stock, "leonard")
	actor["equipment"] = []
	check(Sequence.attack_count(actor, {"double_attack": true}, stock["equipment_items"])["count"] == 1, "innate mapping retains the original nonempty-equipment boundary")
	actor["equipment"] = [{"slot":"weapon", "item_code":12}, {"slot":"accessory1", "item_code":12}]
	check(Sequence.attack_count(actor, {"double_attack":true}, stock["equipment_items"])["count"] == 2, "multiple source flags OR together and never create a third strike")
	check(stock["equipment_items"]["12"]["supported"] and stock["equipment_items"]["69"]["supported"] and stock["equipment_items"]["69"]["double_attack"] and stock["equipment_items"]["55"]["supported"], "independently verified sword12 and bow69 open; weapon55 is supported through its compiled range5CellCircle, not through them")


func series_cases() -> void:
	for count in [1, 2]:
		var loop := fixture(true, count == 2)
		Loop._unit(loop, "enemy021_1")["combat_profile"]["attack_back"] = 100
		var before := loop.duplicate(true)
		var after := Loop.attack_target(Loop.choose_command(loop, "attack"), "enemy021_1", func(_n): return 0)
		var receipt: Dictionary = after["last_attack"]
		var strikes := Sequence.strikes(receipt)
		check(strikes.size() == 2 + count and strikes.slice(0,2).all(func(hit): return not hit["is_counter"]), "all main strikes finish before the single counter series")
		check(strikes.slice(2).all(func(hit): return hit["is_counter"] and not hit.has("counter")), "counter series never recursively counters")
		check(Loop.unit(after,"enemy021_1")["hp"] == 60 and Loop.unit(after,"leonard")["hp"] == 100 - 16 * count, "every independently resolved main/counter hit changes HP exactly once")
		check(not receipt.has("stamina_gain") and receipt["followups"][0].has("stamina_gain"), "first nonlethal extra strike skips the native final ST tail")
		check(Loop.unit(after,"leonard")["stamina"] == 29 and Loop.unit(after,"enemy021_1")["stamina"] == 9, "ST is awarded once at each series end, not once per extra hit")
		check(receipt["experience"]["gained"] == receipt["experience_basis"]["points"] + receipt["followups"][0]["experience_basis"]["points"] and not receipt["followups"][0].has("experience"), "two contributions become one participant EXP award")
		check(loop == before and after["turn_queue"] == before["turn_queue"], "player accepts the whole exchange without mutating caller or advancing early")
		var finished := Loop.finish_exhausted_action(after)
		check(finished["selected_unit_id"] == "enemy023_1" and finished["turn_queue"]["index"] == 1 and Loop.finish_exhausted_action(finished) == finished, "one completion hands off once despite two or four strikes")
		var repeated := Loop.attack_target(after, "enemy021_1", no_rng)
		check(repeated["units"] == after["units"] and repeated["last_combat"] == after["last_combat"], "late repeated targeting cannot replay series or reward")
	for hp in [1, 30]:
		var loop := fixture()
		Loop._unit(loop,"enemy021_1")["hp"] = hp
		Loop._unit(loop,"enemy021_1")["combat_profile"]["attack_back"] = 100
		Loop._unit(loop,"leonard")["kill_chain_word"] = 2
		var receipt := LoopCombat._resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
		var strikes := Sequence.strikes(receipt)
		check(strikes.size() == (1 if hp == 1 else 2) and receipt["counter"].is_empty(), "lethal first/final strike cancels every remaining hit and counter")
		check(strikes.back()["actual_damage"] == (1 if hp == 1 else 10) and strikes.back()["experience_basis"]["kill_chain_before"] == 2, "final hit uses actual remaining HP and the prior kill chain")
		check(Loop.unit(loop,"leonard")["kill_count"] == 1 and receipt["kill_chain"] == 3, "a lethal series adds one kill, not the number of blows")
		check(Aftermath.defeated_ids(receipt) == ["enemy021_1"] and receipt["rewards"]["kills"].size() == 1, "late-hit death is traversed by shared aftermath and loot exactly once")
		var reward_again := Loop.RewardRules.generate(receipt,loop["units"],loop["reward_data"],stream_of(loop, "reward"),loop["rewarded_unit_ids"])
		check(reward_again["gold"] == 0 and reward_again["deaths"].is_empty(), "saved death ledger prevents rewarding the series twice")
	var loop := fixture(false,true)
	Loop._unit(loop,"leonard")["hp"] = 31
	Loop._unit(loop,"enemy021_1")["combat_profile"]["attack_back"] = 100
	Loop._unit(loop,"enemy021_1")["kill_chain_word"] = 2
	var receipt := LoopCombat._resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
	check(receipt["counter"]["followups"][0]["experience_basis"]["kill_multiplier"] == 200 and receipt["counter"]["kill_chain"] == 3, "first nonlethal counter does not clear the chain before its second lethal hit")
	check(receipt["experience_settlement"]["reason"] == "actor_defeated" and not receipt.has("experience"), "a later fatal counter suppresses posthumous growth from the earlier strike")
	check(Aftermath.defeated_ids(receipt) == ["leonard"], "death from an additional counter remains visible to terminal aftermath")
	var grown := fixture()
	Loop._unit(grown,"leonard")["exp"] = 99
	var growth_hit := LoopCombat._resolve_exchange(grown,"leonard","enemy021_1",func(_n):return 0)
	check(growth_hit["followups"][0]["attacker_before"]["level"] == 1 and growth_hit["followups"][0]["attacker_before"]["exp"] == 99 and growth_hit["experience"]["level_after"] == 2, "first-hit contribution cannot level up or change second-hit damage early")


func miss_cases() -> void:
	for mode in ["first", "last", "all"]:
		var loop := fixture()
		Loop._unit(loop,"leonard")["combat_profile"]["live_hit_ratio"] = 80
		var hundreds := [0]
		var receipt := LoopCombat._resolve_exchange(loop,"leonard","enemy021_1",func(bound):
			if bound == 100:
				hundreds[0] += 1
				if (mode == "first" and hundreds[0] == 2) or (mode == "last" and hundreds[0] == 4) or mode == "all": return 99
			return 0)
		var hits := Sequence.participant_strikes(receipt)
		check(hits.size() == 2, "an earlier miss still permits the source extra strike")
		check(hits[0]["hit"] == (mode == "last") and hits[1]["hit"] == (mode == "first"), "each strike samples its own hit and retains miss compensation")
		check(not hits[0].has("stamina_gain") and hits[1].has("stamina_gain") == (mode == "first"), "last-hit miss cannot recover skipped first-hit stamina")
		check(receipt.has("experience") == (mode != "all"), "only effective contributions enter final EXP even when a later strike misses")
		if mode == "first": check(hits[1]["hit_rate"] > hits[0]["hit_rate"], "the second strike reads the first miss's native hit bonus")


func equipment_and_rejection_cases() -> void:
	var loop := Cases.fixture()
	Loop._unit(loop,"leonard")["inventory"] = [12,228,1,0,0,0,0,0]
	var equipped := Loop.change_equipment(loop,"weapon",0,12)
	check(Loop.unit(equipped,"leonard")["weapon_code"] == 12 and Loop.attack_count(equipped,Loop.unit(equipped,"leonard"))["count"] == 2, "real source sword becomes effective through the existing equipment transaction")
	check(equipped["turn_queue"] == loop["turn_queue"] and Loop.unit(equipped,"leonard")["stamina"] == 20, "equipping extra attack does not spend an action or grant stamina")
	var actor := Loop.unit(equipped,"leonard")
	var replaced := Loop.change_equipment(equipped,"weapon",actor["inventory"].find(1),1)
	check(Loop.attack_count(replaced,Loop.unit(replaced,"leonard"))["count"] == 1 and Loop.attack_count(equipped,actor)["count"] == 2, "replacing the sword removes its passive without editing source data or the previous battle")
	equipped = Loop.change_equipment(equipped,"accessory1",actor["inventory"].find(228),228)
	var both := LoopCombat._resolve_exchange(equipped,"leonard","enemy021_1",func(_n):return 0)
	check(both["experience"]["multiplier"] == 2 and both["experience"]["gained"] == both["experience_settlement"]["base"] * 2, "ribbon doubles the series aggregate once")
	check(Loop.attack_count(equipped,Loop.unit(equipped,"leonard"))["count"] == 2, "growth refresh retains equipped extra attack")
	for mode in ["source", "equipment", "type", "target"]:
		var invalid := fixture()
		if mode == "source": own(invalid, "skill_book")["actors"]["001"].erase("double_attack")
		elif mode == "target": own(invalid, "skill_book")["actors"]["021"].erase("double_attack")
		else:
			var code := str(int(Loop.unit(invalid,"leonard")["equipment"][0]["item_code"]))
			if mode == "type": own(invalid, "equipment_items")[code]["double_attack"] = 1
			else: own(invalid, "equipment_items")[code].erase("double_attack")
		var selected := Loop.choose_command(invalid,"attack")
		check(Loop.attack_target(selected,"enemy021_1",no_rng) == selected, "missing/malformed series input refuses the whole player exchange before RNG: " + mode)
	var ai := preload("res://tests/run_ai_navigation_tests.gd").fixture("target_death")
	var id: String = ai["units"][0]["actor_id"]
	own(ai, "skill_book")["actors"][id].erase("double_attack")
	var denied := Loop.step_ai_turn(ai,no_rng)
	check(not denied["scenario_ok"] and denied["units"] == ai["units"] and denied["turn_queue"] == ai["turn_queue"], "bad series source cannot let AI move or choose a fallback after partial validation")


func skill_and_terminal_cases() -> void:
	var loop := fixture()
	var caster := Loop._unit(loop,"leonard")
	caster.merge(Loop.StatusEffectRules.apply(caster,"no_magic",2)["changes"],true)
	var special := Loop.attack_target(Loop.choose_special(Loop.choose_command(loop,"special"),"special:magicOTHER:magicCode01"),"enemy021_1",func(_n):return 0)
	check(not special["last_attack"].has("followups") and Loop.unit(special,"leonard")["stamina"] == 0, "extra ordinary attack does not duplicate a silenced actor's legal Qi Blade or its fee")
	var poisoned := fixture()
	var owner := Loop._unit(poisoned,"leonard")
	owner.merge(Loop.StatusEffectRules.apply(owner,"poison",3,5)["changes"],true)
	var attacked := Loop.attack_target(Loop.choose_command(poisoned,"attack"),"enemy021_1",func(_n):return 0)
	var finished := Loop.finish_exhausted_action(attacked)
	check(Loop.unit(finished,"leonard")["hp"] == Loop.unit(attacked,"leonard")["hp"] - 5 and (Loop.unit(finished,"leonard")["status_counters"]["poison"] & 0xffff) == 2, "one action poison tick follows the complete series, never each hit")
	var victory := fixture()
	Loop._set_unit_defeated(victory,"enemy021_far",true) # the shared fixture's bystander would keep the battle undecided
	Loop._unit(victory,"enemy021_1")["hp"] = 30
	var won := Loop.attack_target(Loop.choose_command(victory,"attack"),"enemy021_1",func(_n):return 0)
	check(won["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED and won["last_attack"]["defender_hp_after"] > 0 and won["last_attack"]["followups"][0]["defender_hp_after"] == 0, "terminal detection uses whole series state even when primary receipt was nonlethal")
	var died := fixture(false,true)
	Loop._unit(died,"leonard")["hp"] = 31
	Loop._unit(died,"enemy021_1")["combat_profile"]["attack_back"] = 100
	died = Loop.attack_target(Loop.choose_command(died,"attack"),"enemy021_1",func(_n):return 0)
	check(died["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN, "an additional counter ends battle through the usual defeat policy")
	var escaped := fixture()
	Loop._unit(escaped,"leonard")["coord"] = escaped["escape_zone"][0]
	var left := Loop.begin_wait_resolution(escaped)
	check(left["battle_outcome"] == BattleOutcome.VICTORY_ESCAPE and Loop.unit(left,"leonard")["exp"] == Loop.unit(escaped,"leonard")["exp"], "extra attack equipment has no extra action or victory EXP on Wait/escape")
	var encoded := Checkpoint.encode(won,{"camera":Vector2(320,240),"shown_story_events":[],"story_complete":false,"growth_notified_level":1})
	check(encoded["ok"], "terminal additional-hit receipt can be saved")
	if encoded["ok"]:
		var restored := Checkpoint.decode(encoded["bytes"], won)
		check(restored["ok"] and restored["snapshot"]["loop"] == won, "restoration preserves complete series/EXP/kill/loot without replay")
		check(Loop.begin_wait_resolution(restored["snapshot"]["loop"]) == won and Loop.finish_exhausted_action(won) == won, "terminal reentry cannot repeat growth or spend another turn")


func presentation_cases() -> void:
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	for double_counter in [false,true]:
		var loop := fixture(true,double_counter)
		Loop._unit(loop,"enemy021_1")["combat_profile"]["attack_back"] = 100
		var receipt := LoopCombat._resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
		var before := loop.duplicate(true)
		var cues: Array = []
		var release := func(s,_a,_d,c): cues.append(["release",c,s["strike_number"]])
		var impact := func(s,_a,_d,c): cues.append(["impact",c,s["strike_number"]])
		cutin.released.connect(release)
		cutin.impact.connect(impact)
		for strike in Sequence.strikes(receipt):
			var attacker := Loop.unit(loop,strike["attacker_id"])
			var defender := Loop.unit(loop,strike["defender_id"])
			# The view projects each receipt, even when the caller already sees the
			# complete series and its final EXP, ST and HP in the live units.
			cutin.play(strike,attacker,defender,strike["is_counter"])
		var expected: Array = []
		for strike in Sequence.strikes(receipt):
			var clip: Dictionary = cutin.clips[0]
			for target_shot in [false,true]:
				cutin._show_shot(clip,target_shot)
				var snapshot: Dictionary = strike["defender_before" if target_shot else "attacker_before"]
				check(cutin.vitals.st_bar.value == snapshot["stamina"], "each wind-up displays its own ST snapshot, never the following blow's gain")
				check(cutin.vitals.values["hp"].text == "%d / %d" % [snapshot["hp"],snapshot["max_hp"]], "each blow starts from the preceding accepted HP, not final-series HP")
			var schedule := cutin.Timing.ordinary(cutin.manifest["actors"][clip["attacker"]], clip["strike"])
			# 0x404290 spawns the red number 40 ticks after the hit; read it two ticks later.
			cutin._process((schedule["impact"] + cutin.Timing.scaled(cutin.OriginalTick.seconds(cutin.Timing.HIT_TO_NUMBER_TICKS + 2))) / cutin.Timing.PLAYBACK_SPEED)
			check(cutin.result_text().contains("%d" % strike["actual_damage"]) and not cutin.result_text().contains("−"), "each independently animated hit shows only its actual loss, unsigned")
			if strike["series_size"] > 1: check(not cutin.result_text().contains("%d/%d" % [strike["strike_number"],strike["series_size"]]), "an extra strike's shot shows its number alone, no N/M ordinal (UI6)")
			expected.append(["release",strike["is_counter"],strike["strike_number"]])
			expected.append(["impact",strike["is_counter"],strike["strike_number"]])
			cutin._process(100)
		check(cues == expected and not cutin.busy() and loop == before, "all extra/counter clips release and impact once in order without changing state")
		cutin.released.disconnect(release)
		cutin.impact.disconnect(impact)
	cutin.queue_free()
	await process_frame


static func wings_fixture(wings: bool = true, ai: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var actor := Loop.unit(loop,"enemy026_1" if ai else "leonard")
	var ally := Loop.unit(loop,"enemy023_1")
	var enemy := Loop.unit(loop,"leonard" if ai else "enemy021_1")
	actor.merge({"coord":Vector2i(8,8),"live_speed":120,"hp":100,"max_hp":100,"mp":100,"max_mp":100,
		"inventory":[227,241,241,246,0,0,0,0]},true)
	ally.merge({"coord":Vector2i(8,9),"live_speed":100,"hp":100,"max_hp":100,"player_commandable":true,"battle_actor_role":Loop.ROLE_PLAYER},true)
	enemy.merge({"coord":Vector2i(10,8),"live_speed":90,"hp":500,"max_hp":500},true)
	loop["units"] = [actor,ally,enemy]; loop["tiles"] = {}; loop["map_size"] = Vector2i(20,20)
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	if ai:
		if wings: actor["equipment"].append({"slot":"accessory2","item_code":227})
		loop["interaction"] = "ai_resolving"
		return loop
	loop = Loop.select_player_unit(loop,actor["id"])
	return Loop.change_equipment(loop,"accessory2",0,227) if wings else loop


func wait_cases() -> void:
	var loop := wings_fixture()
	check(Loop.EquipmentRules.equipped_code(Loop.unit(loop,"leonard")["equipment"],"accessory2") == 227, "White Wings can be equipped through the normal free transaction")
	var poisoned := Loop._unit(loop,"leonard")
	poisoned.merge(Loop.StatusEffectRules.apply(poisoned,"poison",3,7)["changes"],true)
	var before := loop.duplicate(true)
	var again := Loop.choose_command(loop,"wait")
	check(again["selected_unit_id"] == "leonard" and again["interaction"] == "action_menu" and again["turn_queue"] == before["turn_queue"], "first Wait grants the same actor a fresh action before any queue change")
	check(Loop.unit(again,"leonard")["hp"] == poisoned["hp"] and Loop.unit(again,"leonard")["status_counters"] == poisoned["status_counters"], "poison and duration do not tick between the two actions")
	var ended := Loop.choose_command(again,"wait")
	check(ended["selected_unit_id"] == "enemy023_1" and ended["turn_queue"]["index"] == 1, "second Wait hands off exactly once")
	check(Loop.unit(ended,"leonard")["hp"] == int(poisoned["hp"]) - 7 and (int(Loop.unit(ended,"leonard")["status_counters"]["poison"]) & 0xffff) == 2, "whole owner turn applies one poison tick and one duration decrement")


func action_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_extra_action.json"))
	for row in packet["prefixes"]:
		var input: Dictionary = row["input"]
		var state := {"owner_id":"unit" if int(input["latch"]) == 1 else "", "pending":int(input["latch"]) == 1,"sequence":7}
		var actual := Extra.complete(state,"unit",(int(input["effects"]) & 8) != 0)
		check(actual["repeat"] == row["native"]["again"] and int(actual["state"]["pending"]) == int(row["native"]["latch"]), "same pure gate agrees with original player/AI completion prefix")
		check(Extra.state_error(actual["state"],"unit") == "", "native-composed extra-action state has one owner")
	var stock := BattleFixture.loop()
	for row in packet["queries"]:
		var catalog: Dictionary = stock["equipment_items"].duplicate(true)
		catalog["227"]["action_twice"] = (int(row["effects"]) & 8) != 0
		var actor := Loop.unit(stock,"leonard")
		actor["equipment"] = [{"slot":"accessory1","item_code":227},{"slot":"accessory2","item_code":227}]
		check(Extra.equipment(actor,catalog)["count"] == 1 + int(row["native"]), "duplicate flags OR to at most two actions, separate from double_attack")
	check(stock["equipment_items"]["227"]["supported"] and stock["equipment_items"]["55"]["supported"], "supported Wings do not decide weapon55; its support comes from its compiled range5CellCircle")
	check(stock["units"].all(func(actor):return Extra.equipment(actor,stock["equipment_items"])["count"] == 1), "default first-battle actors still have one action")


func prepare_magic(loop: Dictionary, id: String) -> void:
	own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = [id]
	var actor := Loop._unit(loop,"leonard")
	actor["mp"] = 100; actor["max_mp"] = 100
	actor["combat_profile"].merge({"mind":20,"live_magic_attack":100},true)
	actor["growth_profile"]["source"]["has_magic"] = true


func cast(loop: Dictionary, id: String, target: String) -> Dictionary:
	return Loop.attack_target(Loop.choose_magic(Loop.choose_command(loop,"magic"),id),target,zero)


func command_cases() -> void:
	for command in ["wait","use","give","attack",WIND,HEAL,CURE]:
		var loop := wings_fixture()
		var actor := Loop._unit(loop,"leonard")
		actor["hp"] = 10
		var before := loop.duplicate(true)
		var completed := loop
		match command:
			"wait": completed = Loop.choose_command(loop,"wait")
			"use": completed = Loop.use_item(loop,"241","leonard",1)
			"give":
				completed = Loop.begin_give(loop)
				completed = Loop.confirm_give(completed,"enemy023_1",1,241,0,0,completed["item_revision"])
				completed = Loop.finish_give(completed,completed["item_revision"])
			"attack":
				Loop._unit(completed,"enemy021_1")["combat_profile"]["attack_back"] = 0
				completed = Loop.move_unit_to(Loop.choose_command(loop,"move"),Vector2i(9,8))
				completed = Loop.attack_target(Loop.choose_command(completed,"attack"),"enemy021_1",zero)
				completed = Loop.finish_exhausted_action(completed)
			_:
				prepare_magic(loop,command)
				if command == CURE: actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
				if command == HEAL: Loop._unit(loop,"enemy023_1")["hp"] = 4
				completed = Loop.finish_exhausted_action(cast(loop,command,"enemy021_1" if command == WIND else "enemy023_1" if command == HEAL else "leonard"))
		check(completed["selected_unit_id"] == "leonard" and completed["extra_action"]["pending"] and not completed["attacked_this_action"] and not completed["moved_this_action"], "a completed %s opens one fresh same-owner action" % command)
		check(completed["turn_queue"] == before["turn_queue"], "first %s does not rebuild or advance the queue" % command)
		check(Loop.finish_exhausted_action(completed) == completed, "late offense completion cannot consume the newly granted action")
		var second := Loop.move_unit_to(Loop.choose_command(completed,"move"),Vector2i(8,7))
		check(second["pending_move"] and Loop.unit(second,"leonard")["coord"] == Vector2i(8,7), "second action has an independent movement budget from its current position")
		second = Loop.cancel_pending_move(second)
		check(second["extra_action"] == completed["extra_action"] and Loop.unit(second,"leonard")["coord"] == Loop.unit(completed,"leonard")["coord"], "second-action cancellation preserves grant and earlier committed movement")
		second = Loop.cancel_interaction(second)
		var finished := Loop.choose_command(second,"wait")
		check(finished["selected_unit_id"] == "enemy023_1" and not finished["extra_action"]["pending"] and finished["turn_queue"]["index"] == 1, "second action ends %s pair at the original immediate successor" % command)
	var magic := wings_fixture()
	prepare_magic(magic,WIND)
	var first := cast(magic,WIND,"enemy021_1")
	var first_receipt: Dictionary = first["last_attack"].duplicate(true)
	var next := Loop.finish_exhausted_action(first)
	var paid: int = Loop.unit(next,"leonard")["mp"]
	var second := cast(next,WIND,"enemy021_1")
	check(second["last_attack"]["sequence"] == first_receipt["sequence"] + 1 and Loop.unit(second,"leonard")["mp"] == paid - int(first_receipt["resource_payment"]["amount"]), "each independent spell pays once and creates a new immutable receipt")
	for condition in ["mp","silence"]:
		var unavailable := next.duplicate(true)
		var caster := Loop._unit(unavailable,"leonard")
		if condition == "mp": caster["mp"] = 0
		else: caster.merge(Loop.StatusEffectRules.apply(caster,"no_magic",2)["changes"],true)
		var rejected := cast(unavailable,WIND,"enemy021_1")
		check(rejected["units"] == unavailable["units"] and rejected["extra_action"] == unavailable["extra_action"], "second-action unavailable magic cannot spend resources or the pending action")
	var cured := wings_fixture()
	prepare_magic(cured,CURE)
	Loop._unit(cured,"leonard").merge(Loop.StatusEffectRules.apply(Loop.unit(cured,"leonard"),"poison",3,7)["changes"],true)
	cured = Loop.choose_command(cured,"wait")
	var hp: int = Loop.unit(cured,"leonard")["hp"]
	cured = Loop.finish_exhausted_action(cast(cured,CURE,"leonard"))
	check(Loop.unit(cured,"leonard")["hp"] == hp and Loop.unit(cured,"leonard")["status_counters"]["poison"] == 0, "second-action self cure prevents the single final poison tick")


func equipment_restore_cases() -> void:
	var loop := wings_fixture()
	loop = Loop.choose_command(loop,"wait")
	var before := loop.duplicate(true)
	var removed := Loop.change_equipment(loop,"accessory2",-1,0)
	check(removed["extra_action"] == before["extra_action"] and not Extra.equipment(Loop.unit(removed,"leonard"),removed["equipment_items"])["enabled"], "removing Wings during the second action neither erases nor replenishes the grant")
	var encoded := Checkpoint.encode(removed,VIEW)
	check(encoded["ok"], "pending second action with Wings removed is a valid save")
	if encoded["ok"]:
		var decoded := Checkpoint.decode(encoded["bytes"], removed)
		check(decoded["ok"] and decoded["snapshot"]["loop"] == removed, "restoration preserves the consumed first action and current equipment")
		var restored: Dictionary = decoded["snapshot"]["loop"]
		var index: int = Loop.unit(restored,"leonard")["inventory"].find(227)
		restored = Loop.change_equipment(restored,"accessory2",index,227)
		var ended := Loop.choose_command(restored,"wait")
		check(ended["selected_unit_id"] == "enemy023_1" and not ended["extra_action"]["pending"], "re-equipping after load cannot create a third action")
	var bare := wings_fixture(false)
	bare = Loop.change_equipment(bare,"accessory2",0,227)
	check(Loop.choose_command(bare,"wait")["selected_unit_id"] == "leonard", "equipping before first completion applies to this owner turn immediately")
	var removed_first := Loop.change_equipment(wings_fixture(),"accessory2",-1,0)
	check(Loop.choose_command(removed_first,"wait")["selected_unit_id"] == "enemy023_1", "removing the item before first completion prevents the grant")
	for bad in ["owner","pending","sequence","effect"]:
		var broken := before.duplicate(true)
		match bad:
			"owner": broken["extra_action"]["owner_id"] = "enemy023_1"
			"pending": broken["extra_action"]["pending"] = 2
			"sequence": broken["extra_action"]["sequence"] = -1
			"effect": own(broken, "equipment_items")["227"]["action_twice"] = "true"
		check(not Checkpoint.encode(broken,VIEW)["ok"], "corrupt extra-action save data is refused: " + bad)
		var refuse := Loop.attack_target(Loop.choose_command(broken,"attack"),"enemy021_1",no_rng)
		check(refuse["units"] == broken["units"] and refuse["turn_queue"] == broken["turn_queue"], "invalid grant/equipment rejects before any partial combat: " + bad)
	var dead_owner := before.duplicate(true)
	# A forged save can have internally consistent HP/defeated but a stale grant.
	Loop._unit(dead_owner,"leonard").merge({"hp":0,"defeated":true},true)
	check(not Checkpoint.encode(dead_owner,VIEW)["ok"], "a pending second action cannot be restored for a dead owner")
	# Consecutive equipped actors keep distinct turns and independent grants.
	var chain := wings_fixture()
	Loop._unit(chain,"enemy023_1")["equipment"].append({"slot":"accessory2","item_code":227})
	for index in range(4):
		chain = Loop.choose_command(chain,"wait")
		check(chain["turn_queue"]["index"] == (index + 1) / 2, "two equipped neighbors retain exact action/action/successor ordering")
	check(not chain["extra_action"]["pending"] and chain["extra_action"]["sequence"] == 2, "independent two-action turns produce only two grants")


func series_and_outcome_cases() -> void:
	var base: Dictionary = fixture(true,true)
	Loop._unit(base,"leonard")["equipment"].append({"slot":"accessory2","item_code":227})
	Loop._unit(base,"enemy021_1")["combat_profile"]["attack_back"] = 100
	Loop._unit(base,"enemy021_1")["hp"] = 500
	Loop._unit(base,"enemy021_1")["max_hp"] = 500
	var first := Loop.attack_target(Loop.choose_command(base,"attack"),"enemy021_1",zero)
	var first_receipt: Dictionary = first["last_combat"].duplicate(true)
	check(Loop.CombatSequence.strikes(first_receipt).size() == 4, "extra action and double_attack retain a complete independent primary/counter series")
	var next := Loop.finish_exhausted_action(first)
	var second := Loop.attack_target(Loop.choose_command(next,"attack"),"enemy021_1",zero)
	check(Loop.CombatSequence.strikes(second["last_combat"]).size() == 4 and second["last_combat"]["sequence"] == first_receipt["sequence"] + 1, "second action creates another complete series instead of replaying the first receipt")
	check(Loop.unit(second,"leonard")["stamina"] > Loop.unit(first,"leonard")["stamina"] and second["last_combat"].has("experience"), "second series supplies its own native stamina and final EXP")
	var counter_only := wings_fixture(false)
	Loop._unit(counter_only,"leonard")["coord"] = Vector2i(9,8)
	Loop._unit(counter_only,"leonard")["hp"] = 500
	Loop._unit(counter_only,"leonard")["max_hp"] = 500
	Loop._unit(counter_only,"enemy021_1")["equipment"].append({"slot":"accessory2","item_code":227})
	Loop._unit(counter_only,"enemy021_1")["combat_profile"]["attack_back"] = 100
	counter_only = Loop.attack_target(Loop.choose_command(counter_only,"attack"),"enemy021_1",zero)
	check(not counter_only["last_combat"]["counter"].is_empty(), "equipped future actor can counter during someone else's action")
	counter_only = Loop.finish_exhausted_action(counter_only)
	check(counter_only["selected_unit_id"] == "enemy023_1" and not counter_only["extra_action"]["pending"], "a Wings counterattacker cannot receive an out-of-turn extra action")
	var kills := wings_fixture()
	Loop._unit(kills,"leonard")["coord"] = Vector2i(9,8)
	Loop._unit(kills,"leonard")["inventory"][0] = 228
	kills = Loop.change_equipment(kills,"accessory1",0,228)
	var second_foe := Loop.unit(kills,"enemy021_1")
	second_foe.merge({"id":"enemy021_2","coord":Vector2i(10,9),"hp":1,"inventory":[0,0,0,0,0,0,0,0]},true)
	kills["units"].append(second_foe)
	Loop._unit(kills,"enemy021_1").merge({"hp":1,"inventory":[0,0,0,0,0,0,0,0]},true)
	kills = Loop.attack_target(Loop.choose_command(kills,"attack"),"enemy021_1",zero)
	check(kills["last_combat"]["experience"]["multiplier"] == 2, "first extra-action strike keeps the separately equipped native EXP modifier")
	kills = Loop.finish_exhausted_action(kills)
	check(Loop.unit(kills,"leonard")["kill_chain_word"] == 0x10001, "first lethal action retains the native kill mark into the immediate repeat")
	kills = Loop.move_unit_to(Loop.choose_command(kills,"move"),Vector2i(9,9))
	kills = Loop.attack_target(Loop.choose_command(kills,"attack"),"enemy021_2",zero)
	check(kills["last_combat"]["experience_basis"]["kill_multiplier"] == 150 and kills["last_combat"]["experience"]["multiplier"] == 2 and Loop.unit(kills,"leonard")["kill_count"] == 2, "second independent kill uses prior-chain150% and the same final EXP modifier exactly once")
	for ordinal in [1,2]:
		var kill := wings_fixture()
		Loop._unit(kill,"leonard")["coord"] = Vector2i(9,8)
		Loop._unit(kill,"leonard")["exp"] = 99
		Loop._unit(kill,"enemy021_1")["hp"] = 1
		if ordinal == 2: kill = Loop.choose_command(kill,"wait")
		var won := Loop.attack_target(Loop.choose_command(kill,"attack"),"enemy021_1",zero)
		check(won["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED and not won["extra_action"]["pending"], "lethal action ends battle without a spare action: " + str(ordinal))
		check(Loop.unit(won,"leonard")["level"] == 2 and won["last_combat"].has("experience"), "terminal first/second action still commits final EXP and one level")
		check(Checkpoint.encode(won,VIEW)["ok"] and Loop.finish_exhausted_action(won) == won, "terminal save/repeated finish does not grant or settle again")
		var flee := wings_fixture()
		if ordinal == 2: flee = Loop.choose_command(flee,"wait")
		Loop._unit(flee,"leonard")["coord"] = flee["escape_zone"][0]
		var escaped := Loop.choose_command(flee,"wait")
		check(escaped["battle_outcome"] == BattleOutcome.VICTORY_ESCAPE and not escaped["extra_action"]["pending"], "escape ends either action instead of looping the current actor")
		var death := base.duplicate(true)
		if ordinal == 2: death = Loop.choose_command(death,"wait")
		Loop._unit(death,"leonard")["hp"] = 1
		death = Loop.attack_target(Loop.choose_command(death,"attack"),"enemy021_1",zero)
		check(death["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN and not death["extra_action"]["pending"] and not death["last_combat"].has("experience"), "fatal counter cancels any extra action and posthumous growth")
	var departing := wings_fixture(true,true)
	departing = Loop.step_ai_turn(departing,zero)
	var changed := departing.duplicate(true)
	LoopScript._commit_departures(changed, ["enemy026_1"], "winfail", "event_3")
	check(not changed["extra_action"]["pending"] and Loop.CoreTurnQueue.current(changed["turn_queue"])["id"] != "enemy026_1", "scripted departure discards only the departing actor's pending repeat")


func ai_cases() -> void:
	for condition in ["magic","last_mp","mp","silence","wait"]:
		var loop := wings_fixture(true,true)
		var actor := Loop._unit(loop,"enemy026_1")
		var profile: Dictionary = own(loop, "ai_profiles")["actors"]["026"]["profile"]
		profile.merge({"ai_att_magic":100,"ai_help_selfhp":0,"ai_check_dying":0,"find_range":20},true)
		if condition in ["mp","wait"]: actor["mp"] = 0
		if condition == "last_mp":
			actor["mp"] = int(Loop.skill_fields(loop,WIND)["expend"])
			own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
			own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
		if condition == "silence": actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
		if condition == "wait":
			actor["no_attack"] = true
			own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = []
		var before := loop.duplicate(true)
		var first := Loop.step_ai_turn(loop,zero)
		check(first["scenario_ok"] and first["interaction"] == "ai_resolving" and first["extra_action"]["pending"] and first["turn_queue"] == before["turn_queue"], "AI first decision retains current actor for an independent next action: " + condition)
		if condition == "silence": check(Loop.unit(first,actor["id"])["status_counters"]["no_magic"] == 2, "silence remains effective for the second action")
		var second := Loop.step_ai_turn(first,zero)
		check(second["scenario_ok"] and second["selected_unit_id"] == "enemy023_1" and second["last_ai_actions"].size() == 2 and second["turn_queue"]["index"] == 1, "two AI receipts hand off once without skipping the successor")
		if condition == "wait": check(second["last_ai_actions"].all(func(action):return action["kind"] == "wait"), "unavailable AI action stays bounded at two Waits")
		if condition == "magic": check(second["last_combat"]["sequence"] == first["last_combat"]["sequence"] + 1 and Loop.unit(second,actor["id"])["mp"] < Loop.unit(first,actor["id"])["mp"], "AI reevaluates and pays for each actual new cast")
		if condition == "last_mp": check(first["last_ai_action"].get("skill_id") == WIND and Loop.unit(first,actor["id"])["mp"] == 0 and not second["last_ai_action"].has("skill_id"), "MP exhausted by the first cast causes a fresh legal second-action fallback")
	var wrap := wings_fixture()
	var support := wings_fixture(true,true)
	var healer := Loop._unit(support,"enemy026_1")
	healer["no_attack"] = true
	healer["combat_profile"]["live_magic_attack"] = 1000
	own(support, "skill_book")["actors"]["026"]["supported_initial_ids"] = [HEAL]
	own(support, "skill_book")["skills"][HEAL]["fields"]["use_ratio"] = "100"
	var aided := Loop._unit(support,"enemy023_1")
	aided["battle_actor_role"] = Loop.ROLE_ENEMY
	aided["hp"] = 4
	own(support, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_help_otherhp":100,"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":0},true)
	var healed := Loop.step_ai_turn(support,zero)
	check(healed["last_ai_action"].get("skill_id") == HEAL and Loop.unit(healed,aided["id"])["hp"] == 100, "first support action can remove the previously urgent need")
	var reconsidered := Loop.step_ai_turn(healed,zero)
	check(reconsidered["last_ai_action"]["kind"] == "wait" and Loop.unit(reconsidered,healer["id"])["mp"] == Loop.unit(healed,healer["id"])["mp"], "second action reevaluates current health and never replays a stale healing intent")
	wrap["units"][0]["live_speed"] = 10
	wrap["turn_queue"] = Loop.CoreTurnQueue.rebuild(wrap["units"])
	wrap["turn_queue"]["index"] = 2
	wrap = Loop._return_to_player(wrap,"leonard")
	var first := Loop.choose_command(wrap,"wait")
	check(first["turn_queue"]["round"] == 0 and first["turn"] == wrap["turn"], "first extra action at the end of a round does not start the next round early")
	var second := Loop.choose_command(first,"wait")
	check(second["turn_queue"]["round"] == 1 and second["turn"] == int(wrap["turn"]) + 1, "second action wraps one round and dispatches ordinary scenario hooks once")


func cue_cases() -> void:
	GameOptions.environment_preset = "comfort"  # the OPT-GUIDE 提示 branch (原版 draws none of this)
	var cue = preload("res://game/battle/scene/BattleExtraActionCue.gd").new()
	root.add_child(cue)
	await process_frame
	var loop := Loop.choose_command(wings_fixture(),"wait")
	var before := loop.duplicate(true)
	check(cue.busy(loop), "same-owner transition blocks stale controls before the cue starts")
	cue.refresh(loop,Vector2(320,240),false,10)
	check(cue.pending(loop) and not cue.label.visible, "previous combat or a modal cannot consume the pending extra-action cue invisibly")
	cue.refresh(loop,Vector2(320,240),true,0)
	check(cue.label.visible and cue.label.text == "再次行動" and cue.busy(loop), "actual cue gives the player a readable second-action transition")
	cue.refresh(loop,Vector2(320,240),true,1)
	check(not cue.busy(loop) and cue.label.visible, "second action becomes interactive while its same-owner label stays legible")
	for bounds in [Rect2(190,110,260,245),Rect2(190,12,260,245)]:
		cue.refresh(loop,Vector2(320, bounds.position.y + 130),true,0,bounds)
		check(not cue.label.get_rect().grow(4).intersects(bounds) and Rect2(8,8,624,464).encloses(cue.label.get_rect()), "persistent second-action cue avoids the complete source menu including captions at viewport edges")
	cue.finish(loop)
	cue.refresh(loop,Vector2(320,240),true,0)
	check(not cue.busy(loop) and loop == before, "restored/fast-forward cue never grants or repeats the action")
	cue.finish({"extra_action":Extra.empty()})
	check(cue.pending(loop), "restoring an earlier snapshot cannot suppress its next fresh repeat transition")
	cue.refresh(Loop.choose_command(loop,"wait"),Vector2.ZERO,true,0)
	check(not cue.label.visible, "successor clears the previous actor's label")
	cue.queue_free()
	GameOptions.environment_preset = ""
	await process_frame
	var panel = preload("res://game/battle/scene/BattleItemPanel.gd").new()
	root.add_child(panel)
	await process_frame
	var unequipped := wings_fixture(false)
	panel.source_unit = Loop.unit(unequipped,"leonard")
	panel.attack_source = unequipped["skill_book"]["actors"]["001"]
	panel.selected_item = "227"
	panel.selected_index = 0
	panel._show_equipment_confirmation("accessory2")
	var preview := ""
	for label in panel.page_root.find_children("*","Label",true,false): preview += label.text + "\n"
	check(preview.contains("輪到時連續行動  1次 → 2次") and not preview.contains("1擊 → 2擊") and not panel.confirm_button.disabled, "Wings preview shows its independent action-count change without requiring extra-strike equipment")
	check(not Extra.equipment(panel.source_unit,unequipped["equipment_items"])["enabled"] and unequipped["extra_action"] == Extra.empty(), "equipment preview cannot grant or commit an action")
	panel.queue_free()
	await process_frame

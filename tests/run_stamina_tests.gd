extends "res://tests/support/TestSuite.gd"
const Rules = preload("res://game/sim/StaminaRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const LoopCombat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const AIFixtures = preload("res://tests/run_ai_decision_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "STAMINA_TESTS"


func run() -> void:
	native_cases()
	combat_cases()
	equipment_cases()
	invalid_cases()
	await presentation_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_stamina.json"))
	for row in packet["cases"]:
		var c: Dictionary = row["input"]
		var before := c.duplicate(true)
		var amount := Rules.amounts(int(c["max_hp"]), int(c["hp_after"]), int(c["damage"]), int(c["attacker_level"]), int(c["defender_level"]), int(c["attacker_st"]), int(c["defender_st"]), int(c["attacker_flags"]), int(c["defender_flags"]))
		check(amount["attacker"]["after"] == row["native"]["attacker"] and amount["defender"]["after"] == row["native"]["defender"], "both gains equal complete original x86 return")
		check(row["normal_return"] and row["rng_calls"] == 0 and c == before, "native stamina case has complete return, zero RNG and no input mutation")
	check(Rules.amounts(11, 1, 5, 1, 1, 0, 0, 0, 0)["base_gain"] == 4, "odd maxHP half threshold uses integer floor")
	check(Rules.amounts(1, 1, 4, 1, 1, 0, 0, 0, 0)["base_gain"] == 3, "maxHP below10 retains original minimum denominator")


static func fixture() -> Dictionary:
	var loop := BattleFixture.loop()
	var player := Loop._unit(loop, "leonard")
	var enemy := Loop._unit(loop, "enemy021_1")
	player["live_speed"] = 100
	for unit in loop["units"]:
		unit["combat_profile"]["attack_back"] = 0
	for unit in [player, enemy]:
		unit["hp"] = 500
		unit["max_hp"] = 500
		unit["level"] = 1
		unit["combat_profile"]["live_hit_ratio"] = 200
		unit["combat_profile"]["live_defense"] = 0
		unit["combat_profile"]["live_attack_damage"] = 10
		enemy["coord"] = player["coord"] + Vector2i.UP
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop.select_player_unit(loop, "leonard")


func combat_cases() -> void:
	var loop := fixture()
	check(loop["units"].all(func(unit): return unit["stamina"] == 0), "every roster actor starts at explicit zero ST")
	for unit in loop["units"]:
		if unit["id"] == "leonard": continue
		check(not Loop._menu_for_unit(loop, unit["id"])["commands"].any(func(command): return command["command"] == "special"), "having ST never grants another actor Leonard's ability")
	var player := Loop._unit(loop, "leonard")
	var enemy := Loop._unit(loop, "enemy021_1")
	for index in range(5):
		var attacking: String = "leonard" if index % 2 == 0 else "enemy021_1"
		var defending: String = "enemy021_1" if index % 2 == 0 else "leonard"
		var before := [player["stamina"], enemy["stamina"]]
		var strike := LoopCombat._apply_strike(loop, attacking, defending, func(_bound): return 0)
		check(strike["stamina_gain"]["attacker"]["delta"] == 3 and strike["stamina_gain"]["defender"]["delta"] == 6, "ordinary light damage has asymmetric native gain")
		check(player["stamina"] == before[0] + (3 if attacking == "leonard" else 6), "committed player ST matches role")
	check(player["stamina"] == 21 and Loop.can_use_special(loop, "leonard"), "earned charge unlocks the real20-cost skill")
	var canceled := Loop.cancel_interaction(Loop.choose_command(loop, "special"))
	check(canceled["units"] == loop["units"], "canceling earned special preserves exact charges")
	var selected := Loop.choose_special(Loop.choose_command(loop, "special"), "special:magicOTHER:magicCode01")
	for hit in [true, false]:
		var cast := Loop.attack_coord(selected, enemy["coord"], func(bound): return 0 if hit or bound != 100 else 99)
		check(Loop.unit(cast, "leonard")["stamina"] == 1 and Loop.unit(cast, enemy["id"])["stamina"] == enemy["stamina"], "special pays20 once on hit or miss, with no invented normal-attack gain")
	var counter_loop := fixture()
	Loop._unit(counter_loop, "enemy021_1")["combat_profile"]["attack_back"] = 200
	var exchange := LoopCombat._resolve_exchange(counter_loop, "leonard", "enemy021_1", func(_n): return 0)
	check(not exchange["counter"].is_empty() and Loop.unit(counter_loop, "leonard")["stamina"] == 9 and Loop.unit(counter_loop, "enemy021_1")["stamina"] == 9, "counter exchanges gain independently with reversed roles")
	var missed := fixture()
	Loop._unit(missed, "leonard")["combat_profile"]["live_hit_ratio"] = 0
	var miss := LoopCombat._apply_strike(missed, "leonard", "enemy021_1", func(_n): return 99)
	check(not miss["hit"] and not miss.has("stamina_gain") and Loop.unit(missed, "leonard")["stamina"] == 0 and Loop.unit(missed, "enemy021_1")["stamina"] == 0, "miss grants neither participant stamina")
	var mage_loop := AIFixtures.live_fixture()
	var magic := LoopAI._try_skill_turn(mage_loop, "enemy026_1", [Loop.unit(mage_loop, "leonard")], func(_n): return 0)
	check(not magic.is_empty() and Loop.unit(mage_loop, "leonard")["stamina"] == 0 and Loop.unit(mage_loop, "enemy026_1")["stamina"] == 0, "magic damage retains the separate original no-ST-gain channel")
	var killed := fixture()
	Loop._unit(killed, "enemy021_1")["hp"] = 1
	var death := LoopCombat._apply_strike(killed, "leonard", "enemy021_1", func(_n): return 0)
	check(death["stamina_gain"]["base_gain"] == 4 and death["stamina_gain"]["defeated"] and Loop.unit(killed, "leonard")["stamina"] == 4, "lethal strike includes the source kill increment once")
	var capped := fixture()
	Loop._unit(capped, "leonard")["stamina"] = 59
	LoopCombat._apply_strike(capped, "leonard", "enemy021_1", func(_n): return 0)
	check(Loop.unit(capped, "leonard")["stamina"] == 60, "earned charges never exceed source cap60")


func equipment_cases() -> void:
	var loop := fixture()
	Loop._unit(loop, "leonard")["inventory"] = [225, 225, 169, 0, 0, 0, 0, 0]
	var before := loop.duplicate(true)
	var equipped := Loop.change_equipment(loop, "accessory1", 0, 225)
	check(Loop.EquipmentRules.equipped_code(Loop.unit(equipped, "leonard")["equipment"], "accessory1") == 225 and loop == before, "source ring equips through actual immutable player transaction")
	check(equipped["turn_queue"] == loop["turn_queue"] and Loop.unit(equipped, "leonard")["stamina"] == 0, "equipping grants no free ST and preserves current turn")
	equipped = Loop.change_equipment(equipped, "accessory2", Loop.unit(equipped, "leonard")["inventory"].find(225), 225)
	var old_st: int = Loop.unit(equipped, "leonard")["stamina"]
	var strike := LoopCombat._apply_strike(equipped, "leonard", "enemy021_1", func(_n): return 0)
	check(strike["stamina_gain"]["attacker"]["doubled"] and Loop.unit(equipped, "leonard")["stamina"] == old_st + 6, "two source rings set one native bit; gains double, never quadruple")
	equipped = Loop.change_equipment(equipped, "head", Loop.unit(equipped, "leonard")["inventory"].find(169), 169)
	check(Loop.EquipmentRules.equipped_code(Loop.unit(equipped, "leonard")["equipment"], "head") == 169, "Ghost Mask is actually equipable with supported effects")
	old_st = Loop.unit(equipped, "leonard")["stamina"]
	var locked := LoopCombat._apply_strike(equipped, "leonard", "enemy021_1", func(_n): return 0)
	check(locked["stamina_gain"]["attacker"]["blocked"] and Loop.unit(equipped, "leonard")["stamina"] == old_st, "source no_addst takes precedence over double gain")
	var mask_removed := Loop.change_equipment(equipped, "head", -1, 0)
	check((int(Rules.effects(Loop.unit(mask_removed, "leonard"), mask_removed["equipment_items"])["flags"]) & Rules.BLOCK) == 0, "unequip removes effective block immediately without resetting earned ST")
	var resumed := LoopCombat._apply_strike(mask_removed, "leonard", "enemy021_1", func(_n): return 0)
	check(resumed["stamina_gain"]["attacker"]["delta"] == 6, "normal progression refresh preserves passive gain behavior")


func invalid_cases() -> void:
	for value in [null, -1, 61, true, 1.5, "20"]:
		var loop := fixture()
		Loop._unit(loop, "enemy021_1")["stamina"] = value
		var selected := Loop.choose_command(loop, "attack")
		var before := selected.duplicate(true)
		var denied := Loop.attack_coord(selected, Loop.unit(loop, "enemy021_1")["coord"], func(_n): check(false, "invalid target ST must fail before counter/hit RNG"); return 0)
		check(denied == before, "bad stamina leaves player HP, resources, queue and receipts unchanged")
		var ai := AIFixtures.live_fixture("enemy021_1")
		Loop._unit(ai, "leonard")["stamina"] = value
		var rejected := Loop.step_ai_turn(ai, func(_n): check(false, "invalid stamina fails before AI selection RNG"); return 0)
		check(not rejected["scenario_ok"] and rejected["scenario_error"] == "invalid_stamina" and rejected["units"] == ai["units"] and rejected["turn_queue"] == ai["turn_queue"], "AI malformed stamina rejects the whole uncommitted action")
	var corrupt := fixture()
	Loop._unit(corrupt, "leonard")["inventory"][0] = 225
	own(corrupt, "equipment_items")["225"].erase("stamina_effect_flags")
	check(Loop.change_equipment(corrupt, "accessory1", 0, 225) == corrupt, "missing equipment effect cannot mutate inventory or grant a passive")


func presentation_cases() -> void:
	var view = preload("res://game/battle/scene/BattleVitals.gd").new()
	root.add_child(view)
	var loop := fixture()
	var unit := Loop._unit(loop, "leonard")
	# 0x4368c0: fill width per stage (BAR_ST3 58／BAR_ST4 122／BAR_ST2 215 px) and completed
	# segments lit; a segment lights exactly when one more expend-1 絕技 is paid for.
	var expected := {0: [0, 0], 1: [2, 0], 19: [55, 0], 20: [58, 1], 21: [64, 1], 39: [118, 1], 40: [122, 2], 41: [146, 2], 59: [211, 2], 60: [0, 3]}
	for value in [0, 1, 19, 20, 21, 39, 40, 41, 59, 60]:
		unit["stamina"] = value
		view.show_unit(unit)
		check(view.st_bar.value == value and view.st_bar.fill_width() == expected[value][0] and view.st_bar.lit_segments() == expected[value][1], "original ST bar at %d: fill %d px, %d lit segments (0x4368c0) got %d／%d" % [value, expected[value][0], expected[value][1], view.st_bar.fill_width(), view.st_bar.lit_segments()])
		check(view.st_bar.lit_segments() == value / preload("res://game/sim/SkillResourceRules.gd").ST_PER_EXPEND, "each lit ST segment is one expend-1 絕技 (20×expend)")
		# 特殊技 opens the skill page at any stamina (menus_ui/README.md#5); the page row pays.
		check(Loop._menu_for_unit(loop, "leonard")["commands"].filter(func(command): return command["command"] == "special")[0]["enabled"] and Loop.can_use_special(loop, "leonard") == (value >= 20), "the skill page opens at any stamina; its row readiness agrees with displayed stamina")
	view.queue_free()
	await process_frame
	var cutin := preload("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	for hit in [true, false]:
		var combat := fixture()
		Loop._unit(combat, "enemy021_1")["combat_profile"]["attack_back"] = 200
		if not hit: Loop._unit(combat, "leonard")["combat_profile"]["live_hit_ratio"] = 0
		var strike := LoopCombat._resolve_exchange(combat, "leonard", "enemy021_1", func(bound): return 99 if not hit and bound == 100 else 0)
		var settled := combat.duplicate(true)
		cutin.play(strike, Loop.unit(combat, "leonard"), Loop.unit(combat, "enemy021_1"), false)
		var clip: Dictionary = cutin.clips[0]
		cutin._show_shot(clip, false)
		check(cutin.vitals.st_bar.value == 0, "wind-up cannot reveal already-settled attack/counter stamina")
		cutin._show_shot(clip, true)
		check(cutin.vitals.st_bar.value == 0, "pre-impact receiver retains stamina before this strike")
		clip["impact_emitted"] = true
		cutin._show_shot(clip, true)
		check(cutin.vitals.st_bar.value == (6 if hit else 0), "primary impact reveals only its receiving gain, not a future counter")
		cutin.clips.clear()
		cutin.play(strike["counter"], Loop.unit(combat, "enemy021_1"), Loop.unit(combat, "leonard"), true)
		clip = cutin.clips[0]
		cutin._show_shot(clip, false)
		check(cutin.vitals.st_bar.value == (6 if hit else 0), "counter wind-up starts from the preceding strike's settled stamina")
		clip["impact_emitted"] = true
		cutin._show_shot(clip, true)
		check(cutin.vitals.st_bar.value == (9 if hit else 6) and combat == settled, "counter impact projects its receipt without mutating combat truth")
		cutin.clips.clear()
	cutin.queue_free()
	await process_frame

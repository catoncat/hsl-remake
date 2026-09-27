extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Exp = preload("res://game/sim/ExperienceRules.gd")
const Rolls = preload("res://game/sim/NativeMagicRollRules.gd")
const Application = preload("res://game/sim/StatusApplicationRules.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WIND := "magic:magicAIR:magicCode01"
const FIRE := "magic:magicFIRE:magicCode01"
const HEAL := "magic:magicWATER:magicCode06"
const CURE := "magic:magicWATER:magicCode05"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	native_cases()
	damage_cases()
	support_cases()
	chain_and_growth_cases()
	atomic_cases()
	checkpoint_cases()
	await presentation_cases()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("MAGIC_EXPERIENCE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


static func fixture() -> Dictionary:
	var loop := BattleFixture.loop()
	var caster := Loop.unit(loop, "leonard")
	var friend := Loop.unit(loop, "enemy023_1")
	var first := Loop.unit(loop, "enemy021_1")
	var second := Loop.unit(loop, "enemy021_2")
	caster.merge({"coord": Vector2i(8, 8), "live_speed": 100, "mp": 100, "max_mp": 100}, true)
	caster["combat_profile"].merge({"mind": 20, "live_magic_attack": 100}, true)
	caster["growth_profile"]["source"]["has_magic"] = true
	caster["growth_profile"]["source"]["magic_point"] = 100
	friend.merge({"coord": Vector2i(7, 8), "hp": 20, "max_hp": 100, "live_speed": 90, "player_commandable": true, "battle_actor_role": Loop.ROLE_PLAYER}, true)
	first.merge({"coord": Vector2i(10, 8), "hp": 100, "max_hp": 100, "live_speed": 10}, true)
	second.merge({"coord": Vector2i(10, 9), "hp": 100, "max_hp": 100, "live_speed": 9}, true)
	# A distant bystander keeps the development fixture undecided when both targets fall
	# (its objectives end the battle on enemy clear), so action hand-offs stay observable.
	var bystander: Dictionary = Loop.unit(loop, "enemy021_3")
	bystander.merge({"coord": Vector2i(0, 0), "hp": 100, "max_hp": 100, "live_speed": 1, "no_attack": true, "move_point": 0, "base_move_point": 0}, true)
	loop["units"] = [caster, friend, first, second, bystander]
	for unit in loop["units"]: unit["combat_profile"]["attack_back"] = 0
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = [WIND, FIRE, HEAL, CURE, "special:magicOTHER:magicCode01"]
	loop["tiles"] = {}
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop._return_to_player(loop, "leonard")


static func selected(loop: Dictionary, id: String) -> Dictionary:
	return Loop.choose_magic(Loop.choose_command(loop, "magic"), id)


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_experience.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var draws: Array = row["draws"].duplicate(true)
		var result := Exp.from_contribution(int(input["contribution"]), int(input["attacker_level"]), int(input["target_level"]), int(input["target_hp"]), int(input["kill_exp"]), int(input["kill_word"]), func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]), "native EXP draw bound including zero")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(result["points"] == int(row["native"]) and draws.is_empty(), "per-target EXP agrees with the full original return")
	for row in packet["suffixes"]:
		var input: Dictionary = row["input"]
		if input["kind"] == "finish":
			check(Exp.after_action(int(input["word"])) == int(row["native"]["word"]), "kill mark decays at the original action-finish boundary")
		elif input["kind"] == "award":
			var loop := fixture()
			var actor := Loop.unit(loop, "leonard")
			actor["equipment"] = [{"item_code": 228}] if int(input["effects"]) & 16 else []
			check(int(input["exp"]) + int(input["amount"]) * int(Exp.multiplier(actor, loop["equipment_items"])["value"]) == int(row["native"]["exp"]), "actual equipment factor matches final native EXP store")
	for row in packet["status_contributions"]:
		var input: Dictionary = row["input"]
		var target := {"hp": int(input["hp"]), "defeated": false,
			"status_flags": (1 if input["words"]["poison"] else 0) | (2 if input["words"]["no_magic"] else 0),
			"status_counters": {"poison": int(input["words"]["poison"]), "paralysis": 0, "no_magic": int(input["words"]["no_magic"])}}
		var draws: Array = row["draws"].duplicate(true)
		var result := Application.resolve({"function_mask": 8 if input["status"] == "poison" else 16, "immunities": int(input["effects"]), "roll_input": input}, target, func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]), "status contribution observes the original effect draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(result["native_contribution"] == int(row["native"]["contribution"]) and draws.is_empty(), "status contribution counts only actual newly added duration before final EXP")
	var damage: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_magic_damage.json"))
	for row in damage["rolls"]:
		var draws: Array = row["draws"].duplicate(true)
		var output := Rolls.roll(row["input"], func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]), "native wind/fire hit then triangular draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(output["value"] == int(row["native"]["value"]) and output["hit_bonus_after"] == int(row["native"]["hit_bonus_after"]) and draws.is_empty(), "wind/fire helper native value, resistance and miss bonus")
	for row in damage["applications"]:
		var input: Dictionary = row["input"]
		var target := {"hp": int(input["hp"]), "defeated": false, "status_flags": 0, "status_counters": {"poison": 0, "paralysis": 0, "no_magic": 0}}
		var draws: Array = row["draws"].duplicate(true)
		var output := Application.resolve({"function_mask": 1, "immunities": 0, "roll_input": input}, target, func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]), "HP application uses native draw sequence")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(output["damage"] == int(row["native"]["actual_damage"]) and output["target_changes"]["hp"] == int(row["native"]["hp"]), "actual overkill-capped HP effect equals original prefix")
		check(output["native_contribution"] == int(row["native"]["contribution"]) and draws.is_empty(), "native contribution is actual loss, not unbounded sampled damage")


func damage_cases() -> void:
	for id in [WIND, FIRE]:
		for health in [1, 100]:
			var loop := fixture()
			Loop._unit(loop, "enemy021_1")["hp"] = health
			var before := selected(loop, id)
			var saved := before.duplicate(true)
			var after := Loop.attack_target(before, "enemy021_1", zero)
			var hit: Dictionary = after["last_attack"]
			check(hit.get("formula_source") == "0x40a7b0_proc0_and_0x40ab55_hp_cap", "native wind/fire uses actual applicator")
			if not hit.has("experience_basis"): continue
			check(hit["actual_damage"] == health - Loop.unit(after, "enemy021_1")["hp"] and hit["damage"] <= health, "damage feedback reports actual HP loss")
			check(hit["experience"]["gained"] == hit["experience_basis"]["points"] and hit["experience_basis"]["contribution"] == hit["actual_damage"], "one converted EXP award instead of direct damage plus kill_exp")
			check(Loop.unit(after, "leonard")["mp"] == 100 - hit["resource_payment"]["amount"] and before == saved, "one native magic payment with immutable caller")
			check(Loop.unit(after, "leonard")["kill_count"] == (1 if health == 1 else 0), "fatal and nonfatal update only actual kill count")
			var finished := Loop.finish_exhausted_action(after)
			check(finished["selected_unit_id"] == "enemy023_1" and finished["turn_queue"]["index"] == 1, "native magic hands off once after exhaustion")
			check(Loop.finish_exhausted_action(finished) == finished, "no second handoff or XP payout")
	var loop := fixture()
	Loop.skill_fields(loop, FIRE)["effect_range"] = "range1Cell" # Synthetic geometry, not the original fire range.
	Loop._unit(loop, "leonard")["exp"] = 99
	Loop._unit(loop, "enemy021_2")["hp"] = 1
	var before := selected(loop, FIRE)
	var calls: Array = []
	var after := Loop.attack_target(before, "enemy021_1", func(bound): calls.append(bound); return 0)
	var receipt: Dictionary = after["last_attack"]
	check(receipt["affected_targets"].size() == 2 and receipt["affected_targets"][0]["defender_hp_after"] > 0 and receipt["affected_targets"][1]["defender_hp_after"] == 0, "one footprint supports mixed surviving and lethal outcomes")
	var total := 0
	for hit in receipt["affected_targets"]:
		total += int(hit["experience_basis"]["points"])
		check(hit["experience_basis"]["attacker_level"] == 1 and hit["attacker_before"]["combat_profile"]["live_magic_attack"] == 100, "no mid-cast level or magic-power change for a later target")
	check(receipt["experience"]["gained"] == total and receipt["experience"]["level_before"] == 1 and receipt["experience"]["level_after"] == 2, "all targets accumulate before exactly one growth transaction")
	check(calls.size() == 10 and calls[0] == 100 and calls[5] == 100, "per-target hit/value -> EXP -> next-target ordering")
	check(Loop.unit(after, "leonard")["exp"] == total - 1 and Loop.unit(after, "leonard")["pending_stat_points"] == 5, "final amount reaches current growth and pending allocation")
	loop = fixture()
	Loop.skill_fields(loop, WIND)["hit_ratio"] = "0"
	var missed := Loop.attack_target(selected(loop, WIND), "enemy021_1", func(bound): return bound - 1)
	check(missed["last_attack"]["native_damage_roll"]["hit_check_passed"] == false and missed["last_attack"]["damage"] == 0 and not missed["last_attack"].has("experience"), "miss preserves target and has no contribution or EXP")
	check(Loop.unit(missed, "leonard")["hit_bonus_accum"] == 10 and Loop.unit(missed, "leonard")["mp"] < 100, "native miss accumulation and one paid cast")


func support_cases() -> void:
	for id in [HEAL, CURE]:
		var loop := fixture()
		var actor := Loop._unit(loop, "leonard")
		actor["exp"] = 99
		if id == CURE:
			for target in [actor, Loop._unit(loop, "enemy023_1")]: target.merge(Loop.StatusEffectRules.apply(target, "poison", 2, 10)["changes"], true)
		var after := Loop.attack_target(selected(loop, id), "enemy023_1", zero)
		var hit: Dictionary = after["last_attack"]
		var total := 0
		for target in hit["affected_targets"]:
			total += int(target["experience_basis"]["points"])
			check(target["experience_basis"]["contribution"] == target["native_contribution"] and target["native_contribution"] > 0, "recorded support contribution now reaches native conversion")
		check(hit["experience"]["gained"] == total and Loop.unit(after, "leonard")["level"] == 2, "support award reaches one actual level-up")
		check(Loop.unit(after, "leonard")["kill_count"] == 0 and hit["damage"] == 0 and not Loop.loot_waiting(after), "support cannot invent damage, kills or loot")
		if id == CURE:
			check(hit["affected_targets"].size() == 2 and not Loop.StatusEffectRules.poisoned(Loop.unit(after, "leonard")), "all-target cure contributes once for each actual cleared poison")
		else:
			check(hit["native_contribution"] == hit["healing"] / 2, "healing contribution uses capped restored HP divided by two")
	var empty := fixture()
	var rejected := Loop.attack_target(selected(empty, CURE), "leonard", no_rng)
	check(rejected["units"] == empty["units"] and rejected["turn_queue"] == empty["turn_queue"], "empty cure grants neither payout nor free progress")


func chain_and_growth_cases() -> void:
	var loop := fixture()
	var actor := Loop._unit(loop, "leonard")
	actor["kill_chain_word"] = 1
	Loop._unit(loop, "enemy021_1")["hp"] = 1
	Loop._unit(loop, "enemy021_2")["hp"] = 1
	Loop.skill_fields(loop, FIRE)["effect_range"] = "range1Cell"
	var after := Loop.attack_target(selected(loop, FIRE), "enemy021_1", zero)
	var rows: Array = after["last_attack"]["affected_targets"]
	check(rows[0]["experience_basis"]["kill_multiplier"] == 150 and rows[1]["experience_basis"]["kill_multiplier"] == 200, "first kill increments chain before subsequent area target conversion")
	check(Loop.unit(after, "leonard")["kill_count"] == 2 and (int(Loop.unit(after, "leonard")["kill_chain_word"]) & 0xffff) == 2, "area kills count individually while chain increments once")
	check(Loop.unit(Loop.finish_exhausted_action(after), "leonard")["kill_chain_word"] == 2, "own action completion preserves earned low-word chain")
	var waiting := fixture()
	Loop._unit(waiting, "leonard")["kill_chain_word"] = 4
	check(Loop.unit(Loop.begin_wait_resolution(waiting), "leonard")["kill_chain_word"] == 0, "wait with no kill resets chain without EXP")
	var normal := fixture()
	var doubled := normal.duplicate(true)
	var owner := Loop._unit(doubled, "leonard")
	owner["inventory"][0] = 228
	doubled = Loop.change_equipment(doubled, "accessory1", 0, 228)
	check(Loop.InventoryRules.find_item(Loop.unit(doubled, "leonard")["inventory"], 228) == -1 and Exp.multiplier(Loop.unit(doubled, "leonard"), doubled["equipment_items"])["value"] == 2, "source lucky ribbon equips through the real inventory transaction")
	# Equipment refresh changes magic power too; isolate EXP by using the same refreshed stats.
	normal["units"][0]["combat_profile"] = Loop.unit(doubled, "leonard")["combat_profile"].duplicate(true)
	var first := Loop.attack_target(selected(normal, FIRE), "enemy021_1", zero)
	var second := Loop.attack_target(selected(doubled, FIRE), "enemy021_1", zero)
	check(second["last_attack"]["experience"]["gained"] == first["last_attack"]["experience"]["gained"] * 2, "equipment doubles the final native award, not damage or individual random draws")
	var capped := fixture()
	owner = Loop._unit(capped, "leonard")
	for key in Loop.ProgressionRules.GROWTH_CHOICES: owner["growth_profile"]["caps"][key] = owner["combat_profile"][key]
	var blocked := Loop.attack_target(selected(capped, FIRE), "enemy021_1", zero)
	check(blocked["last_attack"]["experience_settlement"]["reason"] == "growth_capacity_exhausted" and Loop.unit(blocked, "leonard")["exp"] == owner["exp"], "native zero-capacity gate discards EXP but keeps the real spell")
	var small := fixture()
	owner = Loop._unit(small, "leonard")
	owner["exp"] = 99
	for key in Loop.ProgressionRules.GROWTH_CHOICES: owner["growth_profile"]["caps"][key] = owner["combat_profile"][key] + (3 if key == "str" else 0)
	var grown := Loop.ProgressionRules.resolve_experience(owner, 300, small["equipment_items"])
	check(grown["level"] == 2 and grown["pending_stat_points"] == 3 and grown["exp"] == 299, "reserved last three growth points cannot create unlimited zero-point levels")
	check(Loop.ProgressionRules.resolve_experience(grown, 10, small["equipment_items"]) == grown, "pending allocation reserves exhausted capacity")


func atomic_cases() -> void:
	for corruption in ["no_mp", "silence", "target_exp", "caster_exp", "chain", "equipment", "growth", "area"]:
		var loop := fixture()
		var actor := Loop._unit(loop, "leonard")
		match corruption:
			"no_mp": actor["mp"] = 0
			"silence": actor.merge(Loop.StatusEffectRules.apply(actor, "no_magic", 2)["changes"], true)
			"target_exp": Loop._unit(loop, "enemy021_1")["kill_exp"] = "bad"
			"caster_exp": actor["exp"] = -1
			"chain": actor["kill_chain_word"] = 0x20000
			"equipment": TestSuite.own(loop, "equipment_items")[str(int(actor["equipment"][0]["item_code"]))].erase("experience_double")
			"growth": actor["growth_profile"]["source"].erase("speed")
			"area":
				Loop.skill_fields(loop, FIRE)["effect_range"] = "range1Cell"
				Loop._unit(loop, "enemy021_2")["kill_exp"] = null
		var started := selected(loop, FIRE)
		var before := started.duplicate(true)
		var result := Loop.attack_target(started, "enemy021_1", no_rng)
		check(result["units"] == before["units"] and result["turn_queue"] == before["turn_queue"] and started == before, "invalid native effect/EXP rejects before any RNG or mutation: " + corruption)


func checkpoint_cases() -> void:
	var loop := fixture()
	Loop._unit(loop, "leonard")["kill_chain_word"] = 2
	var settled := Loop.finish_exhausted_action(Loop.attack_target(selected(loop, HEAL), "enemy023_1", zero))
	var view := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": false, "growth_notified_level": 1}
	var encoded := Save.encode(settled, view)
	check(encoded["ok"], "native support EXP and kill state serialize at a quiet boundary")
	if not encoded["ok"]: return
	var decoded := Save.decode(encoded["bytes"], settled)
	check(decoded["ok"] and decoded["snapshot"]["loop"] == settled, "restoring a paid support cast cannot re-award contributions")
	var invalid: Dictionary = decoded["snapshot"].duplicate(true)
	invalid["loop"]["units"][0]["kill_chain_word"] = -1
	check(Save.validate(invalid, settled) == "invalid_saved_experience", "saved chain corruption fails closed")
	var terminal := settled.duplicate(true)
	terminal["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	terminal["interaction"] = "battle_result"
	var saved := terminal.duplicate(true)
	check(Loop._resolve_outcome(terminal) == saved and Loop.attack_target(terminal, "enemy021_1", no_rng) == saved, "escape or repeated final-state input cannot distribute EXP again")


func presentation_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	TestSuite.stop_audio(scene.get_node("BattleMusic"))
	var loop := fixture()
	Loop._unit(loop, "leonard")["exp"] = 99
	var presentation = scene.get_node("BattlePresentation")
	# The casting-target strip (magic／support preview) masks an enemy the player has not
	# fought, like every other 0x434d10 display; the cast itself makes the target known.
	var casting := selected(loop, FIRE)
	scene.apply_loop(casting, "test")
	presentation.preview_target(casting, "", Vector2i(10, 8))
	check(presentation.target_vitals.visible and presentation.target_vitals.values["hp"].text == "???" and presentation.combat_label.text.ends_with("個目標"), "the casting-target strip masks an enemy the player has not fought")
	var revealed := casting.duplicate(true)
	revealed[preload("res://game/sim/LoopKeys.gd").KNOWN_UNIT_IDS].append("enemy021_1")
	presentation.preview_target(revealed, "", Vector2i(10, 8))
	check(presentation.target_vitals.visible and presentation.target_vitals.values["hp"].text == "100 / 100", "the casting-target strip shows the numbers of a fought enemy")
	loop = Loop.attack_target(casting, "enemy021_1", zero)
	check(Loop.unit_known(loop, "enemy021_1"), "the cast makes its target known (0x442b3c)")
	scene.apply_loop(loop, "test")
	var hit: Dictionary = loop["last_attack"]
	var saved := loop.duplicate(true)
	presentation.magic_impact.begin(hit, scene)
	presentation.magic_impact.set_process(false)
	check(presentation.magic_impact.busy() and presentation.magic_impact.entries[0]["panel"].visible and not presentation.magic_impact.entries[0]["amount"].visible, "native map receiver vitals precede damage digits")
	check(presentation.magic_impact.entries[0]["panel"].get_child(0).size == Vector2(42, 7), "theme minimum font size cannot enlarge the short map resource strip")
	presentation.magic_impact._process(0.5)
	check(not presentation.magic_impact.entries[0]["panel"].visible and presentation.magic_impact.entries[0]["amount"].visible, "map damage follows temporary HP/MP bars")
	presentation.magic_impact._process(presentation.magic_impact.float_seconds())  # the red number lives 10 ticks per digit + 34
	await process_frame
	check(not presentation.magic_impact.busy() and scene.play_loop == saved, "receiver cleanup restores actor without replaying logical damage or EXP")
	presentation._show_strike(hit, loop, scene.map_config, false)
	var clip: Dictionary = presentation.cutin.clips.back()
	check(clip["attacker_unit"]["level"] == 1 and clip["attacker_unit"]["max_hp"] == hit["attacker_before"]["max_hp"], "a pending cast cannot reveal post-award level or maxima")
	presentation.cutin.clips.clear()
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func zero(_bound: int) -> int:
	return 0


func no_rng(_bound: int) -> int:
	check(false, "rejected/terminal transaction consumed RNG")
	return 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

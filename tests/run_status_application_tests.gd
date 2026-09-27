extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const NativeMagicRollRules = preload("res://game/sim/NativeMagicRollRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const POISON := "magic:magicAIR:magicCode05"
const SEAL := "magic:magicMIND:magicCode02"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void: call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


static func fixture() -> Dictionary:
	var units: Array = BattleFixture.loop()["units"].duplicate(true)
	var source := BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json")
	var boss: Dictionary = BattlePlayLoop.BattleScenario.units(source).filter(func(unit): return unit["actor_id"] == "025")[0]
	boss["coord"] = Vector2i(8, 8)
	boss["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	boss["player_commandable"] = true
	boss.erase("player_mode") # the fixture flips his side by battle_actor_role below; without an installed word the side is role-implied
	units.append(boss)
	var loop := BattleFixture.loop(units)
	# The shared initializer now refreshes every source job. Install the bounded
	# cast fixture after that refresh, just as the rendered encounter fixtures do.
	BattlePlayLoop._unit(loop, str(boss["id"])).merge({"live_speed": 100, "mp": 100, "max_mp": 100}, true)
	BattlePlayLoop._unit(loop, "leonard")["live_speed"] = 99
	BattlePlayLoop._unit(loop, "leonard")["coord"] = Vector2i(8, 7)
	BattlePlayLoop._unit(loop, "enemy021_1")["coord"] = Vector2i(9, 8)
	BattlePlayLoop._unit(loop, "enemy021_2")["coord"] = Vector2i(10, 8)
	BattlePlayLoop._unit(loop, "enemy023_1")["coord"] = Vector2i(9, 9)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, str(boss["id"]))


func select_poison(loop: Dictionary) -> Dictionary:
	return BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop, "magic"), POISON)


func run() -> void:
	native_roll_cases()
	native_lifecycle_cases()
	merge_cases()
	cast_cases()
	seal_cases()
	decay_cases()
	ai_cases()
	lifecycle_cases()
	await panel_cases()
	print("STATUS_APPLICATION_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func native_roll_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_status_rolls.json"))
	for case in packet["cases"]:
		var cursor := [0]
		var random := func(bound):
			check(cursor[0] < case["draws"].size(), "pure replay cannot consume unobserved random values")
			if cursor[0] >= case["draws"].size(): return 0
			var draw: Dictionary = case["draws"][cursor[0]]
			check(bound == int(draw["bound"]), "random bound matches original executed helper")
			cursor[0] += 1
			return int(draw["value"])
		var output := NativeMagicRollRules.roll(case["input"], random)
		check(output["value"] == case["native"]["value"] and output["hit_bonus_after"] == case["native"]["hit_bonus_after"], "Godot numerical output matches actual native return")
		check(cursor[0] == case["draws"].size(), "all native random draws replayed once")


func merge_cases() -> void:
	for old_power in [0, 5, 20, 50]:
		for new_power in [5, 25, 50]:
			for duration in [2, 8, 9]:
				var old: int = (old_power << 16) | duration
				var actor := {"hp": 100, "status_flags": 1, "status_counters": {"poison": old, "paralysis": 0, "no_magic": 0}}
				var proposal := StatusEffectRules.apply(actor, "poison", 3, new_power)
				var next: int = proposal["after_word"]
				check((next & 0xffff) == mini(9, duration + 3), "reapplication extends duration and caps at nine")
				check((next >> 16) == (new_power if old_power == 0 else maxi(old_power, (old_power + new_power) / 2)), "poison strength combines without weakening existing power")
	for pair in [[0, 5], [1, 6], [3, 8], [4, 9], [50, 50], [51, 41], [60, 50], [100, 50]]:
		check(StatusApplicationRules.poison_strength(pair[0]) == pair[1], "native potency folding is not a min/max clamp")


func cast_cases() -> void:
	var loop := fixture()
	check(loop["scenario_ok"], "source-owned caster fixture loads")
	var owner: String = loop["selected_unit_id"]
	check(BattlePlayLoop.magic_options(loop, "leonard").is_empty(), "normal Leonard has not gained a magic skill")
	var selected := select_poison(loop)
	check(selected["interaction"] == "attack_select", "source-owned spell selected through Magic command")
	var before := selected.duplicate(true)
	var preparation := SkillResolutionRules.prepare_cast(BattlePlayLoop.unit(selected, owner), BattlePlayLoop.unit(selected, "enemy021_1"), selected["units"], POISON, BattlePlayLoop.skill_fields(selected, POISON), selected["skill_book"], selected["skill_target_data"], selected["equipment_items"], BattlePlayLoop.unit(selected, owner)["coord"], selected["map_size"])
	check(preparation["ok"], "source fixture prepares all status targets: " + str(preparation.get("reason", "")))
	var cast := BattlePlayLoop.attack_target(selected, "enemy021_1", func(_n): return 0)
	check(StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy021_1")) and StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy021_2")), "source cross footprint applies poison to both opponents")
	check(not StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy023_1")), "allied unit in area is not affected by hostile target adapter")
	check(BattlePlayLoop.unit(cast, owner)["mp"] == 90 and cast["turn_queue"] == before["turn_queue"], "area cast charges one fee and waits for presentation")
	check(BattlePlayLoop.unit(cast, "enemy021_1")["hp"] == BattlePlayLoop.unit(before, "enemy021_1")["hp"], "pure poison infliction does not deal immediate HP damage")
	check(selected == before, "cast proposal does not mutate caller input")
	var replay := BattlePlayLoop.attack_target(cast, "enemy021_1", func(_n): check(false, "repeat cast must not draw"); return 0)
	check(replay["units"] == cast["units"] and replay["turn_queue"] == cast["turn_queue"] and replay["last_combat"] == cast["last_combat"], "repeat cast cannot charge, afflict or enqueue presentation twice")
	var other_center := SkillResolutionRules.resolve_cast(BattlePlayLoop.unit(before, owner), BattlePlayLoop.unit(before, "enemy021_2"), before["units"], POISON, BattlePlayLoop.skill_fields(before, POISON), before["skill_book"], before["skill_target_data"], before["equipment_items"], BattlePlayLoop.unit(before, owner)["coord"], before["map_size"], func(_n): return 0)
	check(other_center["receipt"]["defender_id"] == "enemy021_2" and other_center["target_changes"] == other_center["targets"][1]["changes"], "primary receipt and primary changes agree even when center is later in roster order")
	var end := BattlePlayLoop.finish_exhausted_action(cast)
	check(end["selected_unit_id"] == "leonard" and end["turn_queue"]["round"] == cast["turn_queue"]["round"], "one completion reaches next ally without mid-round rebuild")
	check(BattlePlayLoop.finish_exhausted_action(end) == end, "duplicate completion is inert")
	var immune := before.duplicate(true)
	TestSuite.own(immune, "skill_book")["actors"]["021"]["status_capability_flags"] = 0x40
	var draws := [0]
	var protected := BattlePlayLoop.attack_target(immune, "enemy021_1", func(_n): draws[0] += 1; return 0)
	check(draws[0] == 0 and not StatusEffectRules.poisoned(BattlePlayLoop.unit(protected, "enemy021_1")), "all-immune cast skips effect RNG but still settles a valid spell")
	check(BattlePlayLoop.unit(protected, owner)["mp"] == 90 and protected["attacked_this_action"], "immune outcome consumes exactly one cast")
	var repeated := loop.duplicate(true)
	for id in ["enemy021_1", "enemy021_2"]:
		BattlePlayLoop._unit(repeated, id)["status_flags"] = 1
		BattlePlayLoop._unit(repeated, id)["status_counters"]["poison"] = (50 << 16) | 8
	var renewed := BattlePlayLoop.attack_target(select_poison(repeated), "enemy021_1", func(_n): return 0)
	check(BattlePlayLoop.unit(renewed, "enemy021_1")["status_counters"]["poison"] == (50 << 16) | 9, "whole-cast reapplication caps duration and preserves stronger old potency")
	for error in ["secondary_missing", "out_of_range", "dead", "terminal", "poor", "silenced"]:
		var invalid := before.duplicate(true)
		match error:
			"secondary_missing": BattlePlayLoop._unit(invalid, "enemy021_2").erase("status_counters")
			"out_of_range": BattlePlayLoop._unit(invalid, "enemy021_1")["coord"] = Vector2i(20, 20)
			"dead": BattlePlayLoop._unit(invalid, owner)["hp"] = 0
			"terminal": invalid["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
			"poor": BattlePlayLoop._unit(invalid, owner)["mp"] = 9
			"silenced":
				BattlePlayLoop._unit(invalid, owner)["status_flags"] = 2
				BattlePlayLoop._unit(invalid, owner)["status_counters"]["no_magic"] = 2
		var untouched := invalid.duplicate(true)
		var result := BattlePlayLoop.attack_target(invalid, "enemy021_1", func(_n): check(false, "invalid casts must consume no RNG"); return 0)
		check(result["units"] == untouched["units"] and result["turn_queue"] == untouched["turn_queue"] and not result["attacked_this_action"], "all targets/resource/action fail atomically: " + error)
	var cancelled := BattlePlayLoop.cancel_interaction(before)
	var stale := BattlePlayLoop.attack_target(cancelled, "enemy021_1", func(_n): check(false, "cancel must not draw"); return 0)
	check(stale["units"] == cancelled["units"] and stale["turn_queue"] == cancelled["turn_queue"], "stale target after cancel cannot cast")


func seal_cases() -> void:
	var loop := fixture()
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["actor_id"] = "045" # Numerical fixture with an actual source owner, not a new starting grant.
	var target := BattlePlayLoop._unit(loop, "enemy021_1")
	var fields := BattlePlayLoop.skill_fields(loop, SEAL)
	var result := SkillResolutionRules.resolve(actor, target, SEAL, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"], func(_n): return 0)
	check(result["ok"], "source Seal fixture prepares: " + str(result.get("reason", "")))
	if not result["ok"]: return
	check(result["ok"] and (int(result["target_changes"]["status_flags"]) & 2) != 0 and int(result["target_changes"]["hp"]) < int(target["hp"]), "Seal applies damage then no-magic via shared resolver")
	check(result["caster_changes"]["mp"] == 77, "mixed effect spell charges one fee")
	target["hp"] = 1
	var draws := [0]
	var lethal := SkillResolutionRules.resolve(actor, target, SEAL, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"], func(_n): draws[0] += 1; return 0)
	check(lethal["target_changes"]["defeated"] and lethal["target_changes"]["status_flags"] == 0 and draws[0] == 3, "lethal primary damage skips later status and its random draws")


## 死骸腐靈獄 (magic:magicMIND:magicCode05, wave 9 lane A2): the only MAGIC row with every status bit.
## 0x40aa80 visits Attack, then Paralysis／Poison／NoMagic／Weaken in that order; each status has its
## own proc6 check on status_hit_ratio 30 and (poison／weaken) a 30%-scaled magnitude; 100 MP once.
func decay_cases() -> void:
	const DECAY := "magic:magicMIND:magicCode05"
	var loop := fixture()
	check(loop["skill_book"]["actors"]["059"]["supported_initial_ids"].has(DECAY) and loop["skill_book"]["actors"]["068"]["supported_initial_ids"].has(DECAY), "059／068 declare 死骸腐靈獄 in magic_mind")
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["actor_id"] = "059"
	actor["mp"] = 120
	actor["max_mp"] = 120
	TestSuite.own(loop, "skill_book")["actors"]["025"]["supported_initial_ids"].append(DECAY)
	actor["actor_id"] = "025"
	check(BattlePlayLoop.magic_options(BattlePlayLoop.choose_command(loop, "magic"), actor["id"]).any(func(option): return option["id"] == DECAY and option["quote"]["ok"]), "the learned spell is listed and affordable in the magic menu")
	var picked := BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop, "magic"), DECAY)
	check(picked["interaction"] == "attack_select" and BattlePlayLoop.attack_cells(picked).has(Vector2i(10, 8)), "range5CellCircle target selection opens")
	var target := BattlePlayLoop._unit(picked, "enemy021_2")
	target["hp"] = 900
	target["max_hp"] = 900
	target["combat_profile"]["resist_by_type"]["4"] = 0
	var neighbour := BattlePlayLoop._unit(picked, "enemy021_1")
	neighbour["hp"] = 900
	neighbour["max_hp"] = 900
	var settled := BattlePlayLoop.attack_target(picked, "enemy021_2", func(_n): return 0)
	var receipts: Array = settled.get("last_attack", {}).get("affected_targets", [])
	check(settled["attacked_this_action"] and settled["last_attack"].get("skill_id") == DECAY and BattlePlayLoop.unit(settled, actor["id"])["mp"] == 20, "one 100 MP payment settles the cast")
	var struck_ids: Array = receipts.map(func(receipt): return receipt["defender_id"])
	check(struck_ids.has("enemy021_1") and struck_ids.has("enemy021_2") and not struck_ids.has("leonard"), "the range3CellCircle footprint reaches the neighbour and the center, never the ally")
	for receipt in receipts.filter(func(receipt): return receipt["defender_id"] in ["enemy021_1", "enemy021_2"]):
		var applied: Array = receipt["status_effects"].filter(func(effect): return effect["applied"]).map(func(effect): return effect["status"])
		check(int(receipt["damage"]) > 0 and applied == ["paralysis", "poison", "no_magic", "weaken"], "damage first, then every status in native visit order on a zero roll: " + receipt["defender_id"])
		var unit := BattlePlayLoop.unit(settled, receipt["defender_id"])
		check((int(unit["status_flags"]) & 15) == 15 and StatusEffectRules.weaken_power(unit) >= 2 and (int(unit["status_counters"]["poison"]) >> 16) >= 5, "the target carries paralysis, poison, no-magic and a weaken power after the cast: " + receipt["defender_id"])
		check(int(unit["combat_profile"]["str"]) <= int(BattlePlayLoop.unit(picked, receipt["defender_id"])["combat_profile"]["str"]), "weaken refreshes the live attributes downward: " + receipt["defender_id"])
	var lethal := fixture()
	var caster := BattlePlayLoop._unit(lethal, lethal["selected_unit_id"])
	caster["mp"] = 120
	TestSuite.own(lethal, "skill_book")["actors"]["025"]["supported_initial_ids"].append(DECAY)
	var victim := BattlePlayLoop._unit(lethal, "enemy021_1")
	victim["hp"] = 1
	var draws := [0]
	var killed := SkillResolutionRules.resolve(caster, victim, DECAY, BattlePlayLoop.skill_fields(lethal, DECAY), lethal["skill_book"], lethal["skill_target_data"], lethal["equipment_items"], caster["coord"], lethal["map_size"], func(_n): draws[0] += 1; return 0)
	check(killed["ok"] and killed["target_changes"]["defeated"] and killed["target_changes"]["status_flags"] == 0 and draws[0] == 3 and killed["receipt"]["status_effects"].all(func(effect): return not effect["applied"] and effect["reason"] == "target_defeated"), "a lethal primary hit skips all four status checks and their draws")

func ai_cases() -> void:
	var loop := fixture()
	var owner: String = loop["selected_unit_id"]
	var actor := BattlePlayLoop._unit(loop, owner)
	actor["player_commandable"] = false
	actor["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	var target := BattlePlayLoop._unit(loop, "leonard")
	var result := BattleLoopAI._try_skill_turn(loop, owner, [target], func(_n): return 0)
	check(not result.is_empty() and result.get("magic_key") == "poison" and StatusEffectRules.poisoned(BattlePlayLoop.unit(loop, "leonard")), "AI source-owned poison uses the same application path")
	var immune := fixture()
	actor = BattlePlayLoop._unit(immune, owner)
	actor["player_commandable"] = false
	actor["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	TestSuite.own(immune, "skill_book")["actors"]["001"]["status_capability_flags"] = 0x40
	TestSuite.own(immune, "skill_book")["actors"]["023"]["status_capability_flags"] = 0x40
	var before := immune.duplicate(true)
	var plan:=BattleLoopAI._ai_skill_candidates(immune,owner,[BattlePlayLoop.unit(immune,"leonard")],"magic")
	check(plan["ok"] and plan["targets"]["leonard"]["skills"].all(func(s):return s["skill_id"]=="magic:magicWATER:magicCode01") and immune==before,"read-only AI planning excludes immune poison while retaining source025's effective water spell")
	var water:=BattleLoopAI._try_skill_turn(immune,owner,[BattlePlayLoop.unit(immune,"leonard")],func(_n):return 0)
	check(water.get("magic_key")=="water" and BattlePlayLoop.unit(immune,owner)["mp"]==BattlePlayLoop.unit(before,owner)["mp"]-8 and not StatusEffectRules.poisoned(BattlePlayLoop.unit(immune,"leonard")),"AI water fallback has one real cost and no rejected poison effect")
	var invalid := fixture()
	BattlePlayLoop._unit(invalid, owner)["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	BattlePlayLoop._unit(invalid, owner).erase("hit_bonus_accum")
	var untouched := invalid.duplicate(true)
	var refused := BattleLoopAI._try_skill_turn(invalid, owner, [BattlePlayLoop.unit(invalid, "leonard")], func(_n): check(false, "missing status input must not draw"); return 0)
	check(refused.get("kind") == "invalid_skill_input" and refused.get("reason") == "invalid_status_skill_profile" and invalid == untouched, "AI reports bad status inputs rather than quietly choosing another attack")


func native_lifecycle_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_status_application.json"))
	for row in packet["application_cases"]:
		var input: Dictionary = row["input"]
		var cursor := [0]
		var draws: Array = row["draws"]
		var target := {"hp": input["hp"], "defeated": input["hp"] == 0, "status_flags": (1 if input["words"]["poison"] else 0) | (2 if input["words"]["no_magic"] else 0), "status_counters": input["words"].duplicate(true)}
		target["status_counters"]["paralysis"] = 0 # The older native packet only authored poison/silence.
		var result := StatusApplicationRules.resolve({"function_mask": 8 if input["status"] == "poison" else 16, "immunities": input["effects"], "roll_input": input}, target, func(bound):
			check(cursor[0] < draws.size() and bound == int(draws[cursor[0]]["bound"]), "application follows native random-call bounds")
			var value := int(draws[cursor[0]]["value"])
			cursor[0] += 1
			return value)
		for key in ["hp", "status_flags"]:
			check(result["target_changes"][key] == row["native"][key], "application proposal matches original executed branch: " + key)
		for key in row["native"]["status_counters"]:
			check(int(result["target_changes"]["status_counters"][key]) == int(row["native"]["status_counters"][key]), "application counter matches original branch: %s actual=%s expected=%s" % [key, result["target_changes"]["status_counters"][key], row["native"]["status_counters"][key]])
		check(result["hit_bonus_after"] == row["native"]["hit_bonus_after"] and cursor[0] == draws.size(), "application matches original bonus and full random sequence")
		check(not row["normal_return"] and row["stop_address"] == "0x40b831", "application evidence remains a prefix, not a whole spell return")
	for row in packet["tick_cases"]:
		var words: Dictionary = row["input"].duplicate(true)
		words["paralysis"] = 0
		var actor := {"hp": 100, "status_flags": (1 if words["poison"] else 0) | (2 if words["no_magic"] else 0), "status_counters": words}
		var tick := StatusEffectRules.after_action(actor)
		check(int(tick["changes"]["status_flags"]) == int(row["native"]["status_flags"]), "status flags match normally-returned original tick helper")
		for key in row["native"]["status_counters"]:
			check(int(tick["changes"]["status_counters"][key]) == int(row["native"]["status_counters"][key]), "counter update matches normally-returned original tick helper: " + key)


func lifecycle_cases() -> void:
	var loop := fixture()
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["status_flags"] = 3
	actor["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var sealed := BattlePlayLoop.choose_command(loop, "magic")
	check(BattlePlayLoop.choose_magic(sealed, POISON) == sealed, "silence blocks selected magic without spending the action")
	loop = BattlePlayLoop.cancel_interaction(sealed)
	var first := BattlePlayLoop.choose_command(loop, "wait")
	var after := BattlePlayLoop.unit(first, actor["id"])
	check(after["hp"] == actor["hp"] - 7 and after["status_flags"] == 1 and after["status_counters"] == {"poison": (7 << 16) | 1, "paralysis": 0, "no_magic": 0}, "owner completion damages before independently expiring silence")
	check(first["turn_queue"]["index"] == 1 and first["interaction"] == "action_menu" and first["selected_unit_id"] == "leonard", "status completion preserves current actor, phase and within-round order")
	check(SkillResolutionRules.available(after, POISON, BattlePlayLoop.skill_fields(first, POISON), first["skill_book"], first["skill_target_data"], first["equipment_items"])["ok"], "expired silence restores the same source-owned spell")
	var healed := StatusEffectRules.cure_poison(after)
	check(healed["status_flags"] == 0 and healed["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 0}, "cure clears full poison word including potency")
	var last := StatusEffectRules.after_action(after)
	check(last["changes"]["hp"] == actor["hp"] - 14 and last["changes"]["status_flags"] == 0 and last["changes"]["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 0}, "last poison action damages once then clears potency and duration")
	var dead := after.duplicate(true)
	dead["hp"] = 0
	dead["defeated"] = true
	check(not StatusEffectRules.after_action(dead)["ok"] and not StatusEffectRules.apply(dead, "poison", 2, 8)["ok"], "dead recipients cannot tick, be revived by poison flooring or accept new status")
	var ending := loop.duplicate(true)
	ending["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
	ending["interaction"] = "battle_result"
	check(BattlePlayLoop.begin_wait_resolution(ending) == ending and BattlePlayLoop.finish_exhausted_action(ending) == ending, "terminal battle snapshot stays frozen without another damage or duration step")
	var ai := fixture()
	var dead_actor := BattlePlayLoop._unit(ai, ai["selected_unit_id"])
	dead_actor["hp"] = 0
	dead_actor["defeated"] = true
	dead_actor["status_flags"] = 1
	dead_actor["status_counters"]["poison"] = (8 << 16) | 2
	ai["interaction"] = "ai_resolving"
	ai["selected_unit_id"] = ""
	var skipped := BattlePlayLoop.step_ai_turn(ai, func(_n): check(false, "dead slot must not attack"); return 0)
	check(BattlePlayLoop.unit(skipped, dead_actor["id"]) == dead_actor and skipped["selected_unit_id"] == "leonard", "dead slot is skipped without ticking or clearing frozen status")


func panel_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.apply_loop(fixture(), "test")
	scene.menus.choose_command("magic")
	check(scene.magic_panel.visible and scene.play_loop["interaction"] == "magic_select", "runtime opens source-owned magic panel")
	var stale_spell: Button = scene.magic_panel.choices[POISON]
	scene.menus.cancel_magic()
	check(scene.action_menu.visible, "magic cancel makes the action menu available for another actual click")
	var cancelled: Dictionary = scene.play_loop.duplicate(true)
	stale_spell.pressed.emit()
	check(scene.play_loop == cancelled, "closed-panel callback cannot select a spell")
	scene.menus.choose_command("magic")
	var reopened: Dictionary = scene.play_loop.duplicate(true)
	stale_spell.pressed.emit()
	check(scene.play_loop == reopened and scene.magic_panel.visible, "an old spell control cannot act on a reopened menu")
	scene.magic_panel.choices[POISON].pressed.emit()
	check(not scene.magic_panel.visible and scene.play_loop["interaction"] == "attack_select" and scene.interaction_state == "attack_select", "current control selects spell and synchronizes map input phase")
	scene.cancel_current_interaction()
	check(scene.interaction_state == "action_menu" and scene.play_loop["interaction"] == "action_menu", "map-target cancel restores the action menu in both input and battle state")
	var actor := BattlePlayLoop._unit(scene.play_loop, scene.selected_unit_id)
	actor["status_flags"] = 2
	actor["status_counters"]["no_magic"] = 2
	scene.menus.choose_command("magic")
	var silenced: Dictionary = scene.play_loop.duplicate(true)
	check(scene.magic_panel.choices[POISON].disabled, "silenced owned spell is visibly disabled")
	scene.magic_panel.choices[POISON].pressed.emit()
	check(scene.play_loop == silenced, "disabled control signal cannot change selection, MP or status")
	await feedback_cases(scene)
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func feedback_cases(scene: Node) -> void:
	var ids := ["enemy021_1", "enemy021_2", "enemy023_1"]
	for index in range(ids.size()):
		BattlePlayLoop._unit(scene.play_loop, ids[index])["coord"] = Vector2i(8 + index, 8)
	scene.apply_loop(scene.play_loop, "test")
	var before: Dictionary = scene.play_loop.duplicate(true)
	# Settled mixed-result fixture: all three per-target outcomes must stay readable.
	var receipt := {"affected_targets": [
		{"defender_id": ids[0], "actual_damage": 0, "status_effects": [{"applied": true, "status": "poison"}]},
		{"defender_id": ids[1], "actual_damage": 12, "status_effects": [{"applied": true, "status": "no_magic"}]},
		{"defender_id": ids[2], "actual_damage": 0, "status_effects": [{"applied": false, "reason": "immune"}]}]}
	var saved := receipt.duplicate(true)
	var presentation = scene.get_node("BattlePresentation")
	presentation._present_status_effects(receipt)
	var labels: Array = presentation.status_feedback.get_children()
	check(presentation.status_feedback.layer > presentation.cutin.layer, "status results remain above the source spell's additive light")
	# One node per part: the second target's damage number (the original red glyphs, unsigned) stacks under its 禁魔 caption.
	check(labels.size() == 4 and labels.map(func(label): return label.text) == ["中毒", "12", "禁魔", "免疫"], "adjacent feedback retains each individual status, damage and immune result")
	var Style = preload("res://game/battle/runtime/ShowNumberStyle.gd")
	check(labels.size() == 4 and labels[1] is Node2D and labels[1].kind == "damage" and labels[2].get_theme_color("font_color") == Style.CAPTION and feedback_rect(labels[1]).get_center().y > feedback_rect(labels[2]).get_center().y, "the damage number is red and sits below the white status caption of the same target")
	var owners := [ids[0], ids[1], ids[1], ids[2]]
	for index in range(labels.size()):
		var actor = scene.actor_node_for_unit(owners[index])
		var center_x: float = labels[index].position.x if labels[index] is Node2D else labels[index].get_rect().get_center().x
		check(is_equal_approx(center_x, scene.world_to_logical_position(actor.position).x), "status feedback stays centered on its own projected target")
		for other in range(index):
			check(not feedback_rect(labels[index]).grow(4).intersects(feedback_rect(labels[other]).grow(4)), "adjacent mixed-result text and outlines do not collide")
	await create_timer(0.2).timeout
	for index in range(labels.size()):
		for other in range(index):
			check(not feedback_rect(labels[index]).grow(4).intersects(feedback_rect(labels[other]).grow(4)), "floating status text remains separated throughout movement")
	check(receipt == saved and scene.play_loop == before, "status layout never changes receipt, targets, resources or queue")
	await create_timer(0.8).timeout
	check(labels.all(func(label): return not is_instance_valid(label)), "all per-target feedback clears on its existing finite clock")


## A caption Label's rect, or a result number's glyph rect at its current rise.
func feedback_rect(node: Node) -> Rect2:
	if node is Node2D:
		var rect: Rect2 = node.bounds()
		return rect if node.number == null else Rect2(rect.position + node.number.position, rect.size)
	return node.get_rect()

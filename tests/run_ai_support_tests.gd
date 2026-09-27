extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const AISupportRules = preload("res://game/sim/AISupportRules.gd")
const AISupportPlanning = preload("res://game/sim/AISupportPlanning.gd")
const run_magic_experience_tests = preload("res://tests/run_magic_experience_tests.gd")
const AISkillDecisionRules = preload("res://game/sim/AISkillDecisionRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const HEAL := "magic:magicWATER:magicCode06"
const GREATER := "magic:magicWATER:magicCode07"
const LIFE := "magic:magicWATER:magicCode08"
const CURE := "magic:magicWATER:magicCode05"
const GATHER := "special:magicWATER:magicCode02"
const PURGE := "special:magicWATER:magicCode03"
const WIND_WALL := "special:magicAIR:magicCode05"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	native_cases()
	moving_geometry()
	ally_actions()
	item_assistance()
	selection_and_rejection()
	useful_bucket_acceptance()
	special_channel_actions()
	await moving_item_feedback()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("AI_SUPPORT_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


static func fixture(skill_id: String = HEAL) -> Dictionary:
	var loop := run_magic_experience_tests.fixture()
	loop["map_size"] = Vector2i(24, 24)
	var caster := BattlePlayLoop._unit(loop, "leonard")
	# Source stationary casting is tested separately. This suite exercises mobile
	# aid with an explicitly equipped source ring, preserving spell ownership.
	caster["equipment"] = caster["equipment"].filter(func(s):return s["slot"] != "accessory2")
	caster["equipment"].append({"slot":"accessory2","item_code":232})
	caster.merge({"player_commandable": false, "battle_actor_role": BattlePlayLoop.ROLE_FRIENDLY, "move_point": 3}, true)
	caster["hp"] = caster["max_hp"]
	BattlePlayLoop._unit(loop, "enemy023_1").merge({"coord": Vector2i(14, 8), "hp": 4}, true)
	var second := BattlePlayLoop._unit(loop, "enemy021_2")
	second.merge({"coord": Vector2i(14, 9), "hp": 4, "battle_actor_role": BattlePlayLoop.ROLE_FRIENDLY}, true)
	BattlePlayLoop._unit(loop, "enemy021_1")["coord"] = Vector2i(17, 10)
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = [skill_id]
	TestSuite.own(loop, "skill_book")["skills"][skill_id]["fields"]["use_ratio"] = "100"
	var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"]["001"]["profile"]
	profile.merge({"ai_check_hp": 100, "ai_check_dying": 0, "ai_help_otherhp": 100, "ai_help_status": 100, "ai_att_magic": 100}, true)
	for unit in loop["units"]: unit["inventory"] = [0,0,0,0,0,0,0,0]
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop["selected_unit_id"] = ""
	loop["interaction"] = "ai_resolving"
	return loop


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_support.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var draws: Array = row["draws"].duplicate(true)
		var random := func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]), "native support random-call bound/order")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0
		if input["kind"] == "priority":
			var result := AISupportRules.next_check({"ai_help_otherhp": int(input["rates"][0]), "ai_help_status": int(input["rates"][1])}, int(input["attempted"]), int(input["roll"]), random)
			for key in ["mode", "attempted", "next_roll"]: check(result[key] == int(row["result"][key]), "native aid priority suffix " + key)
		else:
			var rows: Array = input["units"].duplicate(true)
			for unit in rows:
				if unit != null: unit["coord"] = Vector2i(int(unit["coord"][0]), int(unit["coord"][1]))
			var cursor := 0
			var indices: Array = []
			var masks: Array = []
			for _iteration in range(rows.size() + 1):
				var result := AISupportRules.scan(rows, int(input["owner"]), input["kind"], cursor, int(input["radius"]), random)
				indices.append(result["index"] + 1)
				if result["index"] < 0: break
				if input["kind"] == "status": masks.append(result["mask"])
				check(result["next_cursor"] > cursor, "native continuation resumes after selected ally")
				cursor = result["next_cursor"]
			check(indices == row["result"]["indices"].map(func(value): return int(value)) and masks == row["result"]["masks"].map(func(value): return int(value)), "same-side square scan/continuation matches full original returns: %s radius%s %s %s" % [input["kind"], input["radius"], indices, row["result"]["indices"]])
		check(draws.is_empty(), "support kernel consumes all and only original random draws")


func moving_geometry() -> void:
	var loop := fixture(CURE)
	var caster := BattlePlayLoop._unit(loop, "leonard")
	var target := BattlePlayLoop._unit(loop, "enemy023_1")
	target["coord"] = Vector2i(12, 8)
	for unit in [caster, target]: unit.merge(BattlePlayLoop.StatusEffectRules.apply(unit, "poison", 2, 10)["changes"], true)
	var before := loop.duplicate(true)
	var prepared := BattlePlayLoop.SkillResolutionRules.prepare_cast(caster, target, loop["units"], CURE, BattlePlayLoop.skill_fields(loop, CURE), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], Vector2i(11,8), loop["map_size"])
	check(prepared["ok"], "moved cure proposal remains legal")
	if prepared["ok"]:
		check(prepared["targets"].map(func(unit): return unit["id"]).has("leonard"), "moved caster belongs to the destination footprint, not the old occupied cell")
	check(loop == before, "moving-caster preflight cannot alter any live coordinate or status")
	var receipt := BattleLoopCombat._resolve_skill(loop, "leonard", target["id"], CURE, BattlePlayLoop.skill_fields(loop,CURE), Vector2i(11,8), zero)
	check(not receipt.is_empty() and receipt["affected_targets"].size() == 2, "one moving cast commits both destination friends")
	check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(loop,"leonard")) and BattlePlayLoop.unit(loop,"leonard")["mp"] == 96, "self target change preserves one payment and clears poison after movement")
	loop = before.duplicate(true)
	caster = BattlePlayLoop._unit(loop,"leonard")
	target = BattlePlayLoop._unit(loop,"enemy023_1")
	target["coord"] = Vector2i(9,8)
	receipt = BattleLoopCombat._resolve_skill(loop,"leonard",target["id"],CURE,BattlePlayLoop.skill_fields(loop,CURE),Vector2i(6,8),zero)
	check(receipt["affected_targets"].size() == 1 and BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(loop,"leonard")), "leaving an allied footprint cannot retain the old-cell self effect")


func ally_actions() -> void:
	for id in [HEAL, GREATER, LIFE]:
		var loop := fixture(id)
		var before := loop.duplicate(true)
		var after := BattlePlayLoop.step_ai_turn(loop, zero)
		check(after["scenario_ok"], "AI ally heal preflight " + str(after.get("scenario_error", "")))
		if not after["scenario_ok"]: continue
		var receipt: Dictionary = after["last_ai_action"]
		check(receipt.get("skill_id") == id and receipt.get("defender_id") == "enemy023_1", "registered ally gets source-ordered " + id)
		if receipt.get("skill_id") != id: continue
		check(receipt["kind"] == "move_then_attack" and receipt["path"].size() > 1 and receipt["path"].back() == receipt["to"], "AI uses the real movement path before supporting")
		var costs := BattlePlayLoop.TacticalGridRules.path_costs(receipt["path"], before["units"], before["tiles"], "leonard")
		check(not costs.is_empty() and int(costs.back()) <= int(BattlePlayLoop.unit(before,"leonard")["move_point"]), "support remains inside the actual movement and clearance budget")
		check(BattlePlayLoop.unit(after,"leonard")["mp"] == 100 - int(BattlePlayLoop.skill_fields(before,id)["expend"]), "ally heal pays one source cost")
		check(BattlePlayLoop.unit(after,"enemy023_1")["hp"] > 4 and BattlePlayLoop.unit(after,"enemy021_1")["hp"] == 100, "support heals the selected friend without also attacking")
		check(receipt["experience"]["gained"] > 0 and receipt["experience_settlement"]["awarded"] == receipt["experience"]["gained"], "AI with supported growth receives its own final support EXP")
		check(after["selected_unit_id"] == "enemy023_1" and after["turn_queue"]["index"] == 1 and after["last_ai_actions"].size() == 1, "one support action reaches the next controllable ally")
		check(loop == before, "support planning/AI step preserves caller state")
	var area := fixture(CURE)
	for id in ["enemy023_1", "enemy021_2"]:
		var unit := BattlePlayLoop._unit(area,id)
		unit.merge(BattlePlayLoop.StatusEffectRules.apply(unit,"poison",2,10)["changes"],true)
	BattlePlayLoop._unit(area,"enemy023_1").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(area,"enemy023_1"),"no_magic",2)["changes"],true)
	var cured := BattlePlayLoop.step_ai_turn(area, zero)
	check(cured["last_ai_action"].get("skill_id") == CURE, "AI chooses area cure for a poisoned ally")
	if cured["last_ai_action"].get("skill_id") == CURE:
		var receipt: Dictionary = cured["last_ai_action"]
		check(receipt["affected_targets"].size() == 2 and BattlePlayLoop.unit(cured,"leonard")["mp"] == 96, "area planner maximizes actually poisoned friends and pays once")
		check(BattlePlayLoop.unit(cured,"enemy023_1")["status_counters"] == {"poison":0,"paralysis":0,"no_magic":2}, "ally cure preserves its unspent silence counter: "+str(BattlePlayLoop.unit(cured,"enemy023_1")["status_counters"]))
		var base := 0
		for hit in receipt["affected_targets"]: base += int(hit["experience_basis"]["points"])
		check(receipt["experience"]["gained"] == base and base > 0, "two cure contributions combine into the correct caster's final award")
		var exp_before: int = BattlePlayLoop.unit(cured,"leonard")["exp"]
		var other: Dictionary = BattlePlayLoop._unit(cured,"enemy023_1")
		other["growth_profile"] = BattlePlayLoop.unit(cured,"leonard")["growth_profile"].duplicate(true)
		other["mp"] = 100
		other["max_mp"] = 100
		other["status_flags"] = 0
		other["status_counters"]["no_magic"] = 0
		other["combat_profile"].merge({"mind":20,"live_magic_attack":100}, true)
		TestSuite.own(cured, "skill_book")["actors"][other["actor_id"]]["supported_initial_ids"] = [HEAL]
		var second := BattlePlayLoop.attack_target(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(cured,"magic"), HEAL), "enemy021_2", zero)
		check(second["last_attack"].get("skill_id") == HEAL and BattlePlayLoop.unit(second,"enemy023_1")["exp"] > 0, "a different supported participant receives their own heal contribution")
		check(BattlePlayLoop.unit(second,"leonard")["exp"] == exp_before, "later ally contribution cannot repeat the prior caster's award")


## 0x40c620 fills SPECIAL buckets beside MAGIC; 0x40c570(actor, 0x40dc50(), 0x40e0e0()) offers the
## special heal category and 0x40df70 walks it through 0x40dd80.
func special_channel_actions() -> void:
	var loop := fixture(GATHER)
	var caster := BattlePlayLoop._unit(loop, "leonard")
	caster["stamina"] = 60
	TestSuite.own(loop, "ai_profiles")["actors"]["001"]["profile"].merge({"ai_att_special": 100, "ai_att_magic": 0}, true)
	BattlePlayLoop._unit(loop, "enemy023_1")["coord"] = Vector2i(12, 8)
	var before := loop.duplicate(true)
	var after := BattlePlayLoop.step_ai_turn(loop, zero)
	check(after["scenario_ok"], "AI special heal preflight " + str(after.get("scenario_error", "")))
	if not after["scenario_ok"]: return
	var receipt: Dictionary = after["last_ai_action"]
	check(receipt.get("skill_id") == GATHER and receipt.get("special_key") == "special_support" and receipt["ai_decision"]["priority"]["kind"] == "ally_skill", "friendly AI heals a hurt ally through the special channel (萬息集氣法)")
	if receipt.get("skill_id") != GATHER: return
	var affected: Array = receipt["affected_targets"].map(func(hit): return str(hit["defender_id"]))
	check(affected.has("enemy023_1") and BattlePlayLoop.unit(after, "enemy023_1")["hp"] > 4 and BattlePlayLoop.unit(after, "leonard")["stamina"] == 20 and BattlePlayLoop.unit(after, "leonard")["mp"] == 100, "the self-centred special footprint reaches the ally and pays 40ST, not MP")
	var support: Dictionary = receipt["ai_decision"]["priority"]["support_decision"]
	var attempt: Dictionary = support["attempts"][0]
	var accepted: Array = attempt["attempts"].filter(func(walk): return int(walk["index"]) >= 0)
	check(attempt["action_selection"]["kind"] == 2 and attempt["attempts"].all(func(walk): return walk["source"] == "0x40dd80") and accepted.size() == 1 and int(accepted[0]["bucket"]) == 1, "0x40c570 picks the special category and the SPECIAL area-heal bucket is walked by 0x40dd80")
	check(loop == before, "special support planning preserves caller state")
	# Self heal: 0x43fa29 offers the same two channels to 0x40c570 before the self bucket walk.
	var alone := fixture(GATHER)
	var wounded := BattlePlayLoop._unit(alone, "leonard")
	wounded.merge({"stamina": 60, "hp": 1}, true)
	TestSuite.own(alone, "ai_profiles")["actors"]["001"]["profile"].merge({"ai_att_special": 100, "ai_att_magic": 0, "ai_help_otherhp": 0, "ai_help_status": 0}, true)
	var healed := BattlePlayLoop.step_ai_turn(alone, zero)
	check(healed["scenario_ok"] and healed["last_ai_action"].get("skill_id") == GATHER and healed["last_ai_action"]["ai_decision"]["priority"]["kind"] == "self_skill" and BattlePlayLoop.unit(healed, "leonard")["hp"] > 1 and BattlePlayLoop.unit(healed, "leonard")["stamina"] == 20, "AI self-heals with the special channel when 0x40c570 selects it")
	# Self-cure adapter: the SPECIAL cure bucket (萬息秘孔術) follows the empty MAGIC one before the item fallback.
	var sick := fixture(PURGE)
	var poisoned := BattlePlayLoop._unit(sick, "leonard")
	poisoned["stamina"] = 60
	poisoned.merge(BattlePlayLoop.StatusEffectRules.apply(poisoned, "poison", 2, 10)["changes"], true)
	TestSuite.own(sick, "ai_profiles")["actors"]["001"]["profile"].merge({"ai_check_hp": 0, "ai_help_otherhp": 0, "ai_help_status": 0}, true)
	var purged := BattlePlayLoop.step_ai_turn(sick, zero)
	check(purged["scenario_ok"] and purged["last_ai_action"].get("skill_id") == PURGE and purged["last_ai_action"]["ai_decision"]["priority"]["kind"] == "self_skill" and BattlePlayLoop.unit(purged, "leonard")["status_counters"]["poison"] == 0, "AI cures its own poison with the special cure bucket")
	# Special self-buffs are range0Cell/range0Cell: 0x40c480 counts them (0x40e180) but no ally is ever inside;
	# only the caster itself is planned (0x43fce1..0x43fd46 falls back to self when the ally scan finds nobody).
	var walled := fixture(WIND_WALL)
	BattlePlayLoop._unit(walled, "leonard")["stamina"] = 60
	TestSuite.own(walled, "ai_profiles")["actors"]["001"]["profile"].merge({"ai_help_attack": 100, "ai_help_otherhp": 0, "ai_help_status": 0}, true)
	var plan := BattleLoopAI._prepare_ai_turn(walled, "leonard")
	check(plan["ok"] and plan["ally_support"]["buff_masks"] == [0x20] and plan["ally_support"]["buff"].keys() == ["leonard"], "a self-only special buff joins the 0x40c480 scan masks and plans only the caster, no allied intent")


func item_assistance() -> void:
	for mode in ["item_only","magic_first","item_first","empty_mp","silenced","declined","adjacent"]:
		var loop := fixture()
		var owner := BattlePlayLoop._unit(loop,"leonard")
		owner["inventory"][0] = 241
		BattlePlayLoop._unit(loop,"enemy023_1")["coord"] = Vector2i(9,8) if mode == "adjacent" else Vector2i(12,8)
		match mode:
			"item_only": TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = []
			"item_first": TestSuite.own(loop, "ai_profiles")["actors"]["001"]["profile"]["ai_att_magic"] = 0
			"empty_mp": owner["mp"] = 0
			"silenced": owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"no_magic",2)["changes"],true)
			"declined": TestSuite.own(loop, "skill_book")["skills"][HEAL]["fields"]["use_ratio"] = "0"
			"adjacent": TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = []
		var before := loop.duplicate(true)
		var after := BattlePlayLoop.step_ai_turn(loop,zero)
		check(after["scenario_ok"],"ally item preflight " + mode)
		var action: Dictionary = after["last_ai_action"]
		if mode == "magic_first":
			check(action.get("skill_id") == HEAL and BattlePlayLoop.unit(after,"leonard")["inventory"][0] == 241,"source magic category can precede available ally medicine")
		else:
			# 0x40d530 keeps the helper's own cell out of the stations: already adjacent, it still steps to another side.
			check(action.get("kind") == "move_then_item" and action.get("target_id") == "enemy023_1", "real medicine can aid an ally: " + mode)
			if not action.has("item_use"): continue
			check(BattlePlayLoop.unit(after,"leonard")["inventory"][0] == 0 and BattlePlayLoop.unit(after,"enemy023_1")["hp"] == 44, "one inventory removal agrees with actual shared healing")
			check(BattlePlayLoop.unit(after,"leonard")["mp"] == owner["mp"] and BattlePlayLoop.unit(after,"leonard")["exp"] == owner["exp"] and not action.has("experience"),"item assistance does not impersonate magic cost or contribution")
		check(after["selected_unit_id"] == "enemy023_1" and after["turn_queue"]["index"] == 1 and loop == before,"one complete ally assistance action preserves caller and hands off once")
	var stale := fixture()
	BattlePlayLoop._unit(stale,"leonard")["inventory"][0] = 241
	TestSuite.own(stale, "skill_book")["actors"]["001"]["supported_initial_ids"] = []
	BattlePlayLoop._unit(stale,"enemy023_1")["coord"] = Vector2i(12,8)
	var prepared := BattleLoopAI._prepare_ai_turn(stale,"leonard")
	var intent: Dictionary = prepared["ally_support"]["items"]["enemy023_1"]
	var blocked := stale.duplicate(true)
	TestSuite.own(blocked, "tiles")[intent["destination"]] = {"blocks_movement":true}
	var old := blocked.duplicate(true)
	check(BattleLoopAI._execute_ai_support_item(blocked,"leonard",intent).is_empty() and blocked == old,"changed movement legality refuses before item/HP/coordinate commit")
	BattlePlayLoop._unit(stale,"leonard")["inventory"][0] = 0
	old = stale.duplicate(true)
	check(BattleLoopAI._execute_ai_support_item(stale,"leonard",intent).is_empty() and stale == old,"stale medicine intent cannot heal or move without the original item")


func selection_and_rejection() -> void:
	var declared := fixture()
	declared["skill_book"] = BattleFixture.loop()["skill_book"]
	var real_healer := BattlePlayLoop._unit(declared,"leonard")
	real_healer["actor_id"] = "027"
	real_healer.erase("growth_profile")
	var source_plan := BattleLoopAI._prepare_ai_turn(declared,"leonard")
	check(source_plan["ok"] and source_plan["ally_support"]["heal"].has("enemy023_1"), "source027 water ownership enables allied plans with the explicit movement ring and no synthetic spell grants")
	if source_plan["ok"] and source_plan["ally_support"]["heal"].has("enemy023_1"):
		check(source_plan["ally_support"]["heal"]["enemy023_1"]["skills"].all(func(skill): return skill["skill_id"] == HEAL), "unmodified source healer is not granted higher water spells")
	var blocked := fixture()
	for y in range(24): TestSuite.own(blocked, "tiles")[Vector2i(11,y)] = {"blocks_movement":true}
	BattlePlayLoop._unit(blocked,"enemy021_2")["coord"] = Vector2i(8,12)
	var moved := BattlePlayLoop.step_ai_turn(blocked,zero)
	check(moved["last_ai_action"].get("defender_id") == "enemy021_2", "an unreachable first sick ally does not hide a later legal patient")
	if moved["last_ai_action"].has("path"):
		check(moved["last_ai_action"]["path"].all(func(cell): return cell.x < 11), "support route never crosses the blocked wall")
	var longer := fixture(HEAL)
	BattlePlayLoop._unit(longer,"enemy023_1")["coord"] = Vector2i(16,8)
	TestSuite.own(longer, "skill_book")["actors"]["001"]["supported_initial_ids"].append(LIFE)
	var ranges := BattleLoopAI._prepare_ai_turn(longer,"leonard")
	check(ranges["ally_support"]["heal"]["enemy023_1"]["skills"].all(func(skill): return skill["skill_id"] == LIFE), "short heal cannot borrow the long spell's casting position")
	check(BattlePlayLoop.step_ai_turn(longer,zero)["last_ai_action"].get("skill_id") == LIFE, "each skill retains its own range and legal casting positions")
	var no_foe := fixture()
	TestSuite.own(no_foe, "ai_profiles")["actors"]["001"]["profile"]["find_range"] = 1
	check(BattlePlayLoop.step_ai_turn(no_foe,zero)["last_ai_action"].get("skill_id") == HEAL, "ally support remains available without an acquired hostile target")
	var dead := fixture()
	BattlePlayLoop._unit(dead,"enemy023_1").merge({"hp":0,"defeated":true},true)
	BattlePlayLoop._unit(dead,"enemy021_2")["coord"] = Vector2i(11,8)
	check(BattlePlayLoop.step_ai_turn(dead,zero)["last_ai_action"].get("defender_id") == "enemy021_2", "live adapter excludes dead patients before native scan and continues to a living ally")
	var stale := fixture()
	var prepared := BattleLoopAI._prepare_ai_turn(stale,"leonard")
	var chosen := AISupportPlanning.choose(prepared["ally_support"],BattlePlayLoop.unit(stale,"leonard"),prepared["profile"],stale["units"],zero)
	check(chosen["kind"] == "ally_skill", "stale-target fixture starts with an accepted support intent")
	if chosen["kind"] == "ally_skill":
		BattlePlayLoop._unit(stale,chosen["intent"]["target_id"])["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		var old := stale.duplicate(true)
		check(BattleLoopAI._execute_ai_skill_choice(stale,"leonard",chosen["intent"],no_rng).is_empty() and stale == old, "commit revalidates a changed alliance before payment, motion or EXP")
	var foe_support := fixture()
	BattlePlayLoop._unit(foe_support,"leonard")["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	BattlePlayLoop._unit(foe_support,"enemy021_1").merge({"hp":4,"coord":Vector2i(12,8)},true)
	var assisted := BattlePlayLoop.step_ai_turn(foe_support,zero)
	check(assisted["last_ai_action"].get("defender_id") == "enemy021_1" and BattlePlayLoop.unit(assisted,"enemy023_1")["hp"] == 4, "enemy healers assist only their own side")
	for mode in ["mp", "silence", "healthy", "rate", "aid_rate", "distance"]:
		var unavailable := fixture()
		var caster := BattlePlayLoop._unit(unavailable,"leonard")
		match mode:
			"mp": caster["mp"] = 0
			"silence": caster.merge(BattlePlayLoop.StatusEffectRules.apply(caster,"no_magic",2)["changes"],true)
			"healthy":
				BattlePlayLoop._unit(unavailable,"enemy023_1")["hp"] = 100
				BattlePlayLoop._unit(unavailable,"enemy021_2")["hp"] = 100
			"rate": TestSuite.own(unavailable, "skill_book")["skills"][HEAL]["fields"]["use_ratio"] = "0"
			"aid_rate": TestSuite.own(unavailable, "ai_profiles")["actors"]["001"]["profile"]["ai_help_otherhp"] = 0
			"distance":
				BattlePlayLoop._unit(unavailable,"enemy023_1")["coord"] = Vector2i(17,8)
				BattlePlayLoop._unit(unavailable,"enemy021_2")["coord"] = Vector2i(17,9)
		var after := BattlePlayLoop.step_ai_turn(unavailable, zero)
		check(after["scenario_ok"] and not after["last_ai_action"].has("skill_id"), "unavailable ally spell leaves ordinary action usable: " + mode)
		check(BattlePlayLoop.unit(after,"leonard")["mp"] == caster["mp"] and BattlePlayLoop.unit(after,"leonard")["exp"] == caster["exp"], "no failed support cost or fabricated EXP: " + mode)
	var status_only := fixture(CURE)
	BattlePlayLoop._unit(status_only,"enemy023_1").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(status_only,"enemy023_1"),"no_magic",2)["changes"],true)
	BattlePlayLoop._unit(status_only,"enemy021_2").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(status_only,"enemy021_2"),"poison",2,10)["changes"],true)
	var planned := BattleLoopAI._prepare_ai_turn(status_only,"leonard")
	check(planned["ok"] and not planned["ally_support"]["status"].has("enemy023_1") and planned["ally_support"]["status"].has("enemy021_2"), "clean/unsupported status is not counted as useful cure coverage")
	for mode in ["profile", "status", "experience"]:
		var invalid := fixture(CURE)
		BattlePlayLoop._unit(invalid,"enemy023_1").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(invalid,"enemy023_1"),"poison",2,10)["changes"],true)
		if mode == "profile": TestSuite.own(invalid, "ai_profiles")["actors"]["001"]["profile"]["ai_help_status"] = -1
		elif mode == "status": BattlePlayLoop._unit(invalid,"enemy023_1")["status_flags"] = 0
		else: BattlePlayLoop._unit(invalid,"enemy023_1")["level"] = -1
		var before := invalid.duplicate(true)
		var after := BattlePlayLoop.step_ai_turn(invalid,no_rng)
		check(not after["scenario_ok"] and after["units"] == before["units"] and after["turn_queue"] == before["turn_queue"], "bad ally preflight rejects atomically before randomness: " + mode)


## 0x40c770 replaces the rand(100)+1 roll with 0 for a useful MAGIC buff (bucket 5, 0x40c8dd..0x40c8e1)
## or cure (bucket 7, 0x40c89d: 200 - 200) row; use_ratio (+0x28) is never read, the rand(100) is still
## drawn. 0x40dd80 keeps the roll for every SPECIAL bucket; both keep it for the offensive buckets 3/4.
func useful_bucket_acceptance() -> void:
	for row in [["magic", 5, 1], ["magic", 7, 1], ["special", 5, -1], ["special", 7, -1], ["magic", 3, -1], ["magic", 4, -1], ["special", 3, -1], ["magic", 1, -1], ["magic", -1, -1]]:
		var draws: Array = []
		var random := func(bound):
			draws.append(bound)
			return bound - 1
		var selected := AISkillDecisionRules.select_index([0, 0], random, row[0], int(row[1]))
		check(int(selected["index"]) == int(row[2]) and selected["useful_accepts"] == (row[0] == "magic" and int(row[1]) in [5, 7]), "use_ratio 0 rows: %s bucket %s -> %s" % [row[0], row[1], selected["index"]])
		check(draws == [32, 100] if int(row[2]) >= 0 else draws == [32, 100, 100], "the kernel still draws rand(32) and one rand(100) per visited node: %s bucket %s %s" % [row[0], row[1], draws])
	var started := AISkillDecisionRules.select_index([100, 100], func(bound): return bound - 1, "magic", 5)
	check(int(started["index"]) == 1 and started["visited"] == [1], "a useful MAGIC buff row is accepted at the rand(32)%count start without visiting the rest")
	for channel in ["magic", "special"]:
		var id := CURE if channel == "magic" else PURGE
		var loop := fixture(id)
		BattlePlayLoop._unit(loop, "leonard")["stamina"] = 60
		TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "0"
		TestSuite.own(loop, "ai_profiles")["actors"]["001"]["profile"].merge({"ai_att_special": 100, "ai_att_magic": 100, "ai_help_otherhp": 0}, true)
		var sick := BattlePlayLoop._unit(loop, "enemy023_1")
		sick["coord"] = Vector2i(12, 8)
		sick.merge(BattlePlayLoop.StatusEffectRules.apply(sick, "poison", 2, 10)["changes"], true)
		var after := BattlePlayLoop.step_ai_turn(loop, zero)
		check(after["scenario_ok"], "use_ratio 0 cure preflight " + channel + str(after.get("scenario_error", "")))
		if not after["scenario_ok"]: continue
		var action: Dictionary = after["last_ai_action"]
		if channel == "magic":
			check(action.get("skill_id") == CURE and BattlePlayLoop.unit(after, "enemy023_1")["status_counters"]["poison"] == 0, "0x40c770 casts a useful MAGIC cure (bucket 7) regardless of use_ratio")
			var attempts: Array = action["ai_decision"]["priority"]["support_decision"]["attempts"]
			check(attempts.size() == 1 and attempts[0]["attempts"].size() == 1 and attempts[0]["attempts"][0]["useful_accepts"] and int(attempts[0]["attempts"][0]["bucket"]) == 7 and attempts[0]["attempts"][0]["source"] == "0x40c770", "the accepted MAGIC cure walk records the unconditional bucket-7 acceptance")
		else:
			check(not action.has("skill_id") and BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(after, "enemy023_1")), "0x40dd80 still rolls use_ratio for a useful SPECIAL cure (bucket 7): rate 0 declines")
			var attempts: Array = action["ai_decision"]["priority"]["support_decision"]["attempts"]
			check(attempts.size() == 1 and attempts[0]["attempts"].size() == 1 and not attempts[0]["attempts"][0]["useful_accepts"] and int(attempts[0]["attempts"][0]["index"]) == -1 and attempts[0]["attempts"][0]["source"] == "0x40dd80", "the declined SPECIAL cure walk records one bucket-7 roll")


func moving_item_feedback() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var loop := fixture()
	BattlePlayLoop._unit(loop,"leonard")["inventory"][0] = 241
	BattlePlayLoop._unit(loop,"enemy023_1")["coord"] = Vector2i(12,8)
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = []
	scene.apply_loop(loop, "test")
	scene.resume_turn_presentation()
	scene.tick_ai_playback(1.0)
	var view = scene.get_node("BattlePresentation")
	var settled: Dictionary = scene.play_loop.duplicate(true)
	check(scene.play_loop["last_ai_action"].get("kind") == "move_then_item" and scene.has_actor_motion(), "normal runtime starts the moved medicine action")
	check(not view.item_feedback_busy() and not scene.action_menu.visible, "medicine feedback cannot appear before arrival")
	await create_timer(0.2).timeout
	scene.tick_ai_playback(100.0)
	check(scene.has_actor_motion() and not view.item_feedback_busy() and scene.ai_playback_active, "long AI wait delta cannot skip remaining actor movement")
	var deadline := Time.get_ticks_msec() + 2000
	while scene.has_actor_motion() and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	scene.tick_ai_playback(0.0)
	check(view.item_feedback_busy() and not scene.action_menu.visible and scene.ai_playback_active, "arrival starts shared medicine feedback before successor input")
	# sfxUseItem plays as the item applies, after the AI lead-in (range, cursor glide, target hold).
	deadline = Time.get_ticks_msec() + 3000
	while view.item_use.stage == "lead" and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	await wait_for_mixer(scene.ui_audio)
	var voice: WeakRef = weakref(scene.ui_audio.get_stream_playback())
	for _iteration in range(5): scene.tick_ai_playback(1.0)
	check(voice.get_ref() == scene.ui_audio.get_stream_playback() and scene.play_loop == settled, "repeat playback ticks neither restart medicine audio nor replay its transaction")
	deadline = Time.get_ticks_msec() + 4000
	while view.item_feedback_busy() and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	scene.tick_ai_playback(0.0)
	await create_timer(0.3).timeout
	check(not scene.ai_playback_active and scene.selected_unit_id == "enemy023_1" and scene.action_menu.visible, "finished item feedback releases the precise next actor")
	check(scene.play_loop == settled and not view.show_item_use(settled["last_item_use"],Vector2.ZERO), "sequence remains consumed after successor input opens")
	scene.ui_audio.stop()
	scene.ui_audio.stream = null
	scene.queue_free()
	await process_frame
	deadline = Time.get_ticks_msec() + 2000
	while voice.get_ref() != null and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(voice.get_ref() == null, "completed medicine playback releases its mixer voice")


func wait_for_mixer(player: AudioStreamPlayer) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while player.playing and player.get_playback_position() <= 0.0 and Time.get_ticks_msec() < deadline: await create_timer(0.01).timeout
	check(player.get_playback_position() > 0.0, "mixer observes the actual started sound")


func zero(_bound: int) -> int:
	return 0


func no_rng(_bound: int) -> int:
	check(false,"invalid support must reject before RNG")
	return 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

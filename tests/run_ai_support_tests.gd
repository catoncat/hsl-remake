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
	ally_actions()
	item_assistance()
	selection_and_rejection()
	useful_bucket_acceptance()
	special_channel_actions()
	await run_ai_priority()
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


# ---- run_ai_support_tests.gd ----
const AIPriorityRules = preload("res://game/sim/AIPriorityRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const run_ai_decision_tests = preload("res://tests/run_ai_decision_tests.gd")
func run_ai_priority() -> void:
	native_cases_ai_priority()
	healing_cases()
func native_cases_ai_priority() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_priority.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var before := input.duplicate(true)
		var cursor := [0]
		var rng := func(bound):
			check(cursor[0] < row["draws"].size(), "no additional priority RNG")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]
			cursor[0] += 1
			check(bound == int(draw["bound"]), "priority RNG bound matches original")
			return int(draw["value"])
		var result: Dictionary
		match input["kind"]:
			"priority":
				result = AIPriorityRules.choose_check({"ai_check_hp": input["self_rate"], "ai_check_dying": input["dying_rate"]}, int(input["attempted"]), rng)
				for key in ["kind", "attempted", "next_roll"]:
					check(result["ok"] and result[key] == int(row["result"][key]), "priority prefix output " + key)
			"self_hp":
				result = AIPriorityRules.self_recovery(input, rng)
				check(result["ok"] and int(result["needed"]) == int(row["result"]["native"]) and result["threshold"] == int(row["result"]["threshold"]), "self HP remainder threshold matches original")
			"dying":
				var units: Array = input["units"].duplicate(true)
				for unit in units:
					if unit != null:
						unit["coord"] = Vector2i(int(unit["coord"][0]), int(unit["coord"][1]))
						unit.merge({"level": 1, "job": 80})
				result = AIPriorityRules.low_hp_target(units, int(input["owner"]), int(input["radius"]), int(input["excluded"]), int(input["cursor"]), rng)
				check(result["ok"] and result["native_index"] == int(row["result"]["native"]), "dying target matches original full return")
				check(result["evaluated"] == row["result"]["evaluated"].map(func(value): return {"index": int(value["index"]), "threshold": int(value["threshold"])}), "every absolute threshold and cursor matches original")
			"heal_item":
				var catalog := {}
				for code in input["items"]:
					var item: Dictionary = input["items"][code]
					# Live catalog is a registered subset of source type1 consumables.
					if int(item["type"]) == 1: catalog[code] = {"heal_hp": int(item["heal_hp"]), "cure_poison": 1 if int(item["heal_hp"]) == 0 else 0, "cure_paralysis": 0}
				result = ItemUseRules.first_healing_slot(input["slots"], catalog)
				check(result["ok"] and result["index"] + 1 == int(row["result"]["native"]), "first registered healing slot follows native inventory order")
		check(input == before and cursor[0] == row["draws"].size(), "immutable input and exact source random consumption")


static func healing_code(loop: Dictionary) -> int:
	for code in loop["consumables"]:
		if int(loop["consumables"][code]["heal_hp"]) > 0: return int(code)
	return 0


static func opportunity_fixture(owner: String = "enemy021_1") -> Dictionary:
	var loop := run_ai_decision_tests.live_fixture(owner)
	var wounded := BattlePlayLoop.unit(loop, "leonard")
	wounded.merge({"id": "priority-wounded", "coord": Vector2i(6, 3), "hp": 8, "max_hp": 100, "live_speed": 1, "player_commandable": false}, true)
	loop["units"].append(wounded)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return loop


static func recovery_fixture() -> Dictionary:
	var loop := opportunity_fixture()
	var actor := BattlePlayLoop._unit(loop, "enemy021_1")
	actor["hp"] = 4
	actor["inventory"] = [healing_code(loop), healing_code(loop), 0, 0, 0, 0, 0, 0]
	return loop


func healing_cases() -> void:
	var before := recovery_fixture()
	var saved := before.duplicate(true)
	var actor := BattlePlayLoop.unit(before, "enemy021_1")
	var after := BattlePlayLoop.step_ai_turn(before, func(_n): return 0)
	check(after["scenario_ok"], "self recovery preflight accepts valid source inputs")
	if not after["scenario_ok"]: return
	var action: Dictionary = after["last_ai_action"]
	var healed := BattlePlayLoop.unit(after, actor["id"])
	check(action["kind"] == "use_item" and action["ai_decision"]["priority"]["checks"][0]["kind"] == 2, "source self-recovery priority precedes reachable dying foe")
	check(healed["hp"] == 4 + mini(int(before["consumables"][str(healing_code(before))]["heal_hp"]), 396), "one shared healing effect is applied")
	check(healed["inventory"] == [healing_code(before), 0, 0, 0, 0, 0, 0, 0] and healed["coord"] == actor["coord"], "one ordered item is consumed without movement")
	check(after["selected_unit_id"] == "enemy023_1" and after["turn_queue"]["index"] == 1 and after["last_ai_actions"].size() == 1, "AI item ends exactly one action")
	check(before == saved and not action.has("damage") and BattlePlayLoop.unit(after, "priority-wounded")["hp"] == 8, "healing cannot also attack or mutate input")
	check(BattlePlayLoop.step_ai_turn(after, func(_n): check(false, "completed AI cannot act again"); return 0) == after, "duplicate AI step is inert after player handoff")
	var player := before.duplicate(true)
	BattlePlayLoop._unit(player, actor["id"])["player_commandable"] = true
	BattlePlayLoop._unit(player, actor["id"])["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	player = BattlePlayLoop._return_to_player(player, actor["id"])
	var used := BattlePlayLoop.use_item(player, str(healing_code(player)), actor["id"], 0)
	var player_effect:Dictionary = used["last_item_use"].duplicate(true)
	var ai_effect:Dictionary = after["last_item_use"].duplicate(true)
	check(player_effect["actor_before"]["battle_actor_role"] == BattlePlayLoop.ROLE_PLAYER and ai_effect["actor_before"]["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY, "item replay snapshots retain the actual caller's role and decision provenance")
	for receipt in [player_effect,ai_effect]:
		for key in ["actor_before","target_before"]: receipt.erase(key)
	check(player_effect == ai_effect and BattlePlayLoop.unit(used, actor["id"])["inventory"] == healed["inventory"], "player and AI share the complete effect, inventory, RNG and sequence receipt despite distinct caller snapshots")
	var poisoned := before.duplicate(true)
	BattlePlayLoop._unit(poisoned, actor["id"])["status_flags"] = 3
	BattlePlayLoop._unit(poisoned, actor["id"])["status_counters"] = {"poison": (5 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var settled := BattlePlayLoop.step_ai_turn(poisoned, func(_n): return 0)
	check(settled["last_ai_action"]["kind"] == "use_item" and BattlePlayLoop.unit(settled, actor["id"])["hp"] == healed["hp"] - 5 and BattlePlayLoop.unit(settled, actor["id"])["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "self medicine is allowed under silence and ticks poison/status once")
	for health in [395, 400]:
		var healthy := before.duplicate(true)
		BattlePlayLoop._unit(healthy, actor["id"])["hp"] = health
		var attacked := BattlePlayLoop.step_ai_turn(healthy, func(_n): return 0)
		# The strike kills priority-wounded; 0x442720 state 4 hands its rolled drops to this non-player
		# killer through 0x44f600 (0x4428cd), so only the slots the hand-over filled may differ.
		var taken: Array = attacked.get("last_combat", {}).get("rewards", {}).get("taken", [])
		var kept: Array = BattlePlayLoop.unit(attacked, actor["id"])["inventory"].duplicate()
		for row in taken:
			if int(row["slot"]) >= 0: kept[int(row["slot"])] = 0
		check(attacked["last_ai_action"]["kind"] != "use_item" and kept == actor["inventory"], "full or nearly full HP preserves medicine and allows offense")
		check(taken.map(func(row): return [int(row["code"]), int(row["slot"])]) == [[246, 2]] and BattlePlayLoop.unit(attacked, actor["id"])["inventory"] == [healing_code(attacked), healing_code(attacked), 246, 0, 0, 0, 0, 0], "the kill hands the victim's drop to the AI killer's first empty slot (0x44f600): " + str(taken))

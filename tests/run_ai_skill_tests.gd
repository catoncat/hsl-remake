extends "res://tests/support/TestSuite.gd"
const AISkillDecisionRules = preload("res://game/sim/AISkillDecisionRules.gd")
const AISkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const run_ai_decision_tests = preload("res://tests/run_ai_decision_tests.gd")
const POISON := "magic:magicAIR:magicCode05"


func _init() -> void:
	tag = "AI_SKILL_TESTS"


func run() -> void:
	native_cases()
	area_cases()
	special_bucket_walk()
	held_target_free_cast()
	centre_scan_cases()
	move_search_cases()
	side_walk_cases()
	run_ai_call()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_skills.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var before := input.duplicate(true)
		var cursor := [0]
		var rng := func(bound):
			check(cursor[0] < row["draws"].size(), "no extra native skill draw")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]
			cursor[0] += 1
			check(bound == int(draw["bound"]), "skill/position RNG bound matches original")
			return int(draw["value"])
		var result: Variant
		match input["kind"]:
			"buckets": result = AISkillDecisionRules.buckets(int(input["mask"]), bool(input["area"]))
			"order": result = int(AISkillDecisionRules.area_order(int(input["flag"]), rng)["area_first"])
			"select": result = AISkillDecisionRules.select_index(input["rates"], rng)["index"]
			"position_suffix":
				var points: Array = input["positions"].map(func(point): return Vector2i(int(point[0]), int(point[1])))
				result = AISkillDecisionRules.farthest_index(points, Vector2i(int(input["threat"][0]), int(input["threat"][1])), rng)["index"]
		var expected: Variant = row["native"].map(func(value): return int(value)) if input["kind"] == "buckets" else row["native"]
		check(result == expected, "kernel result equals original: " + input["kind"])
		check(cursor[0] == row["draws"].size() and input == before, "all native draws used and input unchanged")
		check(bool(row["normal_return"]) == (input["kind"] != "position_suffix"), "position suffix is not reported as whole planner return")


static func area_fixture() -> Dictionary:
	var loop := run_ai_decision_tests.live_fixture()
	var mage := BattlePlayLoop.unit_ref(loop, "enemy026_1")
	# Source-owned 025 poison on an isolated synthetic roster, never a 026 grant.
	mage["actor_id"] = "025"
	mage["coord"] = Vector2i(4, 6)
	mage["mp"] = 100
	mage["max_mp"] = 100 # Synthetic capacity belongs to this area-cast fixture.
	var primary := BattlePlayLoop.unit_ref(loop, "leonard")
	primary["coord"] = Vector2i(6, 6)
	var center := primary.duplicate(true)
	center.merge({"id": "area-center", "coord": Vector2i(7, 6), "live_speed": 9}, true)
	var outer := primary.duplicate(true)
	outer.merge({"id": "area-outer", "coord": Vector2i(8, 6), "live_speed": 8}, true)
	loop["units"].append_array([center, outer])
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return loop


func area_cases() -> void:
	var loop := area_fixture()
	var before := loop.duplicate(true)
	var prepared := BattleLoopAI.ai_skill_candidates(loop, "enemy026_1", [BattlePlayLoop.unit(loop, "leonard")], "magic")
	check(prepared["ok"], "source-owned poison area prepares: " + str(prepared.get("reason", "")))
	if not prepared["ok"]: return
	var plan: Dictionary = prepared["targets"]["leonard"]
	var chosen := AISkillPlanning.choose(plan, func(_bound): return 0)
	check(chosen["intent"]["target_id"] == "area-center" and chosen["intent"]["primary_target_id"] == "leonard", "area center can differ while preserving originally selected target inside the effect")
	check(chosen["decision"]["coverage"] == 3 and loop == before, "area maximizes useful beneficiaries before caster separation")
	var action := BattleLoopAI.execute_ai_skill_choice(loop, "enemy026_1", chosen["intent"], func(_bound): return 0)
	check(action["affected_targets"].size() == 3 and BattlePlayLoop.unit(loop, "enemy026_1")["mp"] == 90, "three-target poison casts once and pays one fee")
	for id in ["leonard", "area-center", "area-outer"]:
		check(BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(loop, id)) and BattlePlayLoop.unit(loop, id)["hp"] == 400, "each poison target settles a status without invented damage")
	check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(loop, "enemy026_1")), "caster is never included in hostile footprint")
	var immune := area_fixture()
	own(immune, "skill_book")["actors"]["001"]["status_capability_flags"] = 0x40
	var saved := immune.duplicate(true)
	var immune_plan := BattleLoopAI.ai_skill_candidates(immune,"enemy026_1",[BattlePlayLoop.unit(immune,"leonard")],"magic")
	check(immune_plan["ok"] and immune_plan["targets"]["leonard"]["skills"].all(func(s):return s["skill_id"]=="magic:magicWATER:magicCode01") and immune==saved,"poison immunity removes useless poison proposals, not source025's useful Water Strike")
	var fallback:=BattleLoopAI.try_skill_turn(immune,"enemy026_1",[BattlePlayLoop.unit(immune,"leonard")],func(_n):return 0)
	check(fallback.get("skill_id")=="magic:magicWATER:magicCode01" and BattlePlayLoop.unit(immune,"enemy026_1")["mp"]==92,"actual source-owned water fallback pays once instead of repeating ineffective poison")
	check(["leonard","area-center","area-outer"].all(func(id):return not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(immune,id))),"water fallback does not smuggle the rejected poison effect")
	var unavailable:=saved.duplicate(true)
	BattlePlayLoop.unit_ref(unavailable,"enemy026_1")["mp"]=7
	var unavailable_before:=unavailable.duplicate(true)
	check(BattleLoopAI.try_skill_turn(unavailable,"enemy026_1",[BattlePlayLoop.unit(unavailable,"leonard")],func(_n):check(false,"no useful affordable spell cannot draw");return 0).is_empty() and unavailable==unavailable_before,"no useful affordable source-owned proposal preserves resources and RNG")


## 0x43f7bf: 0x40d4e0 orders the offensive pair before 0x40c570 picks the channel; 0x40df70 then
## walks that (first, fallback) pair through 0x40dd80 (rand(32)%count start, rand(100)+1 <= use_ratio
## at +0x20) exactly as 0x40d340 walks it through 0x40c770. No uniform draw over the special rows.
func special_bucket_walk() -> void:
	const AREA := "special:magicAIR:magicCode03" # 流星降: range1Cell effect -> bucket 3
	const SINGLE := "special:magicOTHER:magicCode01" # 氣刃斬: range0Cell effect -> bucket 4
	var loop := run_ai_decision_tests.live_fixture()
	var mage := BattlePlayLoop.unit_ref(loop, "enemy026_1")
	mage["stamina"] = 60
	own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [SINGLE, AREA]
	var profile: Dictionary = own(loop, "ai_profiles")["actors"]["026"]["profile"]
	profile.merge({"ai_att_special": 100, "ai_att_magic": 0, "ai_check_hp": 0, "ai_check_dying": 0, "ai_help_otherhp": 0, "ai_help_status": 0, "ai_help_attack": 0}, true)
	var prepared := BattleLoopAI.ai_skill_candidates(loop, mage["id"], [BattlePlayLoop.unit(loop, "leonard")], "special")
	check(prepared["ok"], "two offensive specials prepare: " + str(prepared.get("reason", "")))
	if not prepared["ok"]: return
	var plan: Dictionary = prepared["targets"]["leonard"]
	check(plan["skills"].map(func(row): return int(row["bucket"])).has(3) and plan["skills"].map(func(row): return int(row["bucket"])).has(4), "special rows carry their 0x407010 offensive buckets")
	for flag in [0, 1]:
		plan["area_flag"] = flag
		var draws: Array = []
		var chosen := AISkillPlanning.choose(plan, func(bound):
			draws.append(bound)
			return 0)
		var expected := AREA if flag == 0 else SINGLE
		check(chosen["intent"].get("skill_id") == expected and chosen["decision"]["bucket_order"]["source"] == "0x40d4e0" and chosen["decision"]["bucket_order"]["order"] == ([3, 4] if flag == 0 else [4, 3]), "ai_magic_multi_first %d orders the special buckets like the magic ones: %s" % [flag, chosen["intent"].get("skill_id")])
		var attempts: Array = chosen["decision"]["attempts"]
		check(attempts.size() == 1 and attempts[0]["source"] == "0x40dd80" and int(attempts[0]["bucket"]) == (3 if flag == 0 else 4) and not attempts[0]["useful_accepts"], "the first offensive special bucket is walked by 0x40dd80 with a use_ratio roll")
		check(draws.slice(0, 3) == [100, 32, 100], "0x40d4e0 roll, then rand(32) start and one rand(100) per visited row: %s" % [draws])
	own(loop, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["use_ratio"] = "0" # 氣刃斬 fields live in the skill book like every other skill (skill_fields)
	own(loop, "skill_book")["skills"][AREA]["fields"]["use_ratio"] = "0"
	var declined := BattleLoopAI.ai_skill_candidates(loop, mage["id"], [BattlePlayLoop.unit(loop, "leonard")], "special")
	var walked := AISkillPlanning.choose(declined["targets"]["leonard"], func(_bound): return 0)
	check(walked["intent"].is_empty() and walked["decision"]["attempts"].size() == 2 and walked["decision"]["attempts"].all(func(attempt): return int(attempt["index"]) == -1 and attempt["visited"].size() == 1), "use_ratio 0 specials decline in both buckets instead of a uniform pick")
	var saved := loop.duplicate(true)
	var after := BattlePlayLoop.step_ai_turn(loop, func(_bound): return 0)
	check(after["scenario_ok"] and not after["last_ai_action"].has("skill_id") and BattlePlayLoop.unit(after, "enemy026_1")["stamina"] == 60 and loop == saved, "declined offensive specials fall through to the ordinary action without paying ST")
	var receipt: Array = after["last_ai_action"]["ai_decision"]["skill_attempts"]
	check(receipt.size() == 1 and receipt[0]["bucket_order"]["order"].size() == 2 and receipt[0]["attempts"].size() == 2, "the live receipt records the ordered two-bucket special walk")


## 0x43fe0c: 0x40c570(actor, 0x40dd60(), 0x40e1f0()) asks whether the actor owns an affordable
## MAGIC／SPECIAL row in bucket 3 or 4 (0x40c620), not whether the held target can be hit; the
## cast (0x43fea7 → 0x40d340 with flag 0) then takes the best coverage anywhere in reach.
func held_target_free_cast() -> void:
	const FIRE := "magic:magicFIRE:magicCode01"
	var loop := run_ai_decision_tests.live_fixture()
	BattlePlayLoop.unit_ref(loop, "enemy026_1")["ai_target_id"] = "leonard"
	BattlePlayLoop.unit_ref(loop, "leonard")["coord"] = Vector2i(3, 9) # held (retained), beyond every stationary range3CellCircle cast
	BattlePlayLoop.unit_ref(loop, "enemy023_1")["coord"] = Vector2i(3, 1)
	var prepared := BattleLoopAI.ai_skill_candidates(loop, "enemy026_1", [BattlePlayLoop.unit(loop, "leonard")], "magic")
	check(prepared["ok"] and not prepared["targets"].has("leonard") and bool(prepared["any_target"]["available"]), "the held target offers no spell, the actor still owns affordable offensive rows")
	var saved := loop.duplicate(true)
	var after := BattlePlayLoop.step_ai_turn(loop, func(_bound): return 0)
	var action: Dictionary = after["last_ai_action"]
	check(action["ai_decision"]["target_selection"]["reason"] == "retained_target" and action.get("skill_id") == FIRE and action.get("target_id") == "enemy023_1" and loop == saved, "state 0xa casts at the reachable foe while the held target stays out of reach: %s -> %s" % [action.get("skill_id"), action.get("target_id")])
	check(action["ai_decision"]["skill_attempts"][0]["held_target_free"] and action["ai_decision"]["skill_attempts"][0]["primary_target_id"] == "leonard", "the receipt keeps the held target as bookkeeping only")
	# Both foes in reach: the earlier row-major centre (0x40cb99 keeps it on raw 0) wins even though it is not the held one.
	var both := run_ai_decision_tests.live_fixture()
	BattlePlayLoop.unit_ref(both, "enemy023_1")["coord"] = Vector2i(3, 1)
	var chosen := BattlePlayLoop.step_ai_turn(both, func(_bound): return 0)["last_ai_action"] as Dictionary
	check(chosen["ai_decision"]["target_selection"]["index"] == 1 and chosen.get("target_id") == "enemy023_1", "an equal-coverage centre before the held target is kept at 0x40cb99 raw 0: %s" % chosen.get("target_id"))
	# Nothing in reach at all: availability is still the actor's (the rows are affordable), the
	# category roll takes magic and the empty search falls to the ordinary category.
	var castless := run_ai_decision_tests.live_fixture()
	BattlePlayLoop.unit_ref(castless, "enemy026_1")["ai_target_id"] = "leonard"
	BattlePlayLoop.unit_ref(castless, "leonard")["coord"] = Vector2i(3, 9)
	var none := BattleLoopAI.ai_skill_candidates(castless, "enemy026_1", [BattlePlayLoop.unit(castless, "leonard")], "magic")
	check(bool(none["any_target"]["available"]) and none["any_target"]["skills"].size() == 2 and none["any_target"]["skills"].all(func(row): return row["intents"].is_empty()), "castless affordable rows keep the channel available (0x40dd60 does not ask for a landing cell)")
	var fell_loop := BattlePlayLoop.step_ai_turn(castless, func(_bound): return 0)
	var fell: Dictionary = fell_loop["last_ai_action"]
	check(int(fell["ai_decision"]["action_selection"]["kind"]) == 1 and not fell.has("skill_id") and fell["ai_decision"]["skill_attempts"][0]["attempts"].size() == 2, "the magic category is drawn, both buckets are walked, no spell is paid")
	check(BattlePlayLoop.unit(fell_loop, "enemy026_1")["mp"] == 30, "a castless magic category pays nothing")


static func _intent(skill: String, destination: Vector2i, centre: Vector2i, affected: Array) -> Dictionary:
	return {"skill_id": skill, "target_id": affected[0], "cast_center": centre, "destination": destination,
		"affected_ids": affected, "useful_ids": affected, "score": affected.size(), "movement_cost": 0, "path": []}


static func _sequence(values: Array, bounds: Array) -> Callable:
	return func(bound):
		bounds.append(bound)
		return values.pop_front() if not values.is_empty() else 0


## 0x40c9a0 over one cast cell: centres row-major, the general best replaced by a higher count
## or, on an equal one, by raw & 1 (0x40cb99); a centre holding the held target first runs the
## contains-target best, whose equal count draws raw & 1 at 0x40cb54. Flag 0 returns the general best.
func centre_scan_cases() -> void:
	var cell := Vector2i(4, 4)
	var later := _intent("s", cell, Vector2i(5, 2), ["p"])
	var earlier := _intent("s", cell, Vector2i(2, 1), ["q"])
	for raw in [0, 1]:
		var draws: Array = []
		var scan := AISkillPlanning.centre_scan([later, earlier], "", func(_bound): return raw, draws)
		check(scan["intent"] == (earlier if raw == 0 else later) and draws == [{"bound": 2, "value": raw}], "equal coverage: row-major, raw %d at 0x40cb99 keeps %s" % [raw, "the earlier" if raw == 0 else "the later"])
	var held_a := _intent("s", cell, Vector2i(2, 1), ["h", "x"])
	var held_b := _intent("s", cell, Vector2i(5, 2), ["h", "y"])
	var held_draws: Array = []
	var held := AISkillPlanning.centre_scan([held_b, held_a], "h", _sequence([1, 0], []), held_draws)
	check(held["intent"] == held_a and held_draws.size() == 2, "two centres holding the target: 0x40cb54 draws first, the 0x40cb99 raw 0 then keeps the earlier: %s" % [held_draws])
	var only := _intent("s", cell, Vector2i(2, 1), ["h"])
	var wide := _intent("s", cell, Vector2i(6, 6), ["x", "y"])
	var free := AISkillPlanning.centre_scan([only, wide], "h", func(_bound): return 0, [])
	check(free["intent"] == wide and int(free["count"]) == 2, "flag 0 returns the best coverage even without the held target")
	# 0x40d340 bucket walk: a picked row with no centre falls to the fallback bucket once.
	var plan := {"channel": "magic", "area_flag": 0, "origin": cell, "move_search": false, "threat": null, "skills": [
		{"skill_id": "area", "source_order": 5, "use_ratio": 100, "bucket": 3, "intents": []},
		{"skill_id": "single", "source_order": 4, "use_ratio": 100, "bucket": 4, "intents": [_intent("single", cell, Vector2i(5, 4), ["x"])]}]}
	var walked := AISkillPlanning.choose_any(plan, "h", func(_bound): return 0)
	check(walked["intent"].get("skill_id") == "single" and walked["decision"]["bucket_order"]["order"] == [3, 4] and walked["decision"]["attempts"].size() == 2 and int(walked["decision"]["attempts"][0]["index"]) == 0, "the castless bucket-3 row falls to bucket 4 (0x40d494 → 0x40d3bc)")


## 0x40cca0 (SPECIAL always, MAGIC with move_magic_use): every flood cell but its own, the cells
## of the highest count kept, the one farthest from the threat taken; no move search or nothing
## found scans the actor's own cell.
func move_search_cases() -> void:
	var origin := Vector2i(4, 4)
	var intents := [_intent("s", origin, Vector2i(4, 5), ["a", "b", "c"]), _intent("s", Vector2i(5, 4), Vector2i(6, 4), ["a", "b"]),
		_intent("s", Vector2i(7, 4), Vector2i(8, 4), ["a", "c"]), _intent("s", Vector2i(3, 4), Vector2i(2, 4), ["a"])]
	var plan := {"channel": "special", "area_flag": 0, "origin": origin, "move_search": true, "threat": Vector2i(0, 4),
		"skills": [{"skill_id": "s", "source_order": 1, "use_ratio": 100, "bucket": 3, "intents": intents}]}
	var moved := AISkillPlanning.choose_any(plan, "", func(_bound): return 0)
	var search: Dictionary = moved["decision"]["attempts"][0]["search"]
	check(search["stations"] == [Vector2i(5, 4), Vector2i(7, 4)] and moved["intent"]["destination"] == Vector2i(7, 4) and int(moved["decision"]["coverage"]) == 2, "own cell skipped, the count-2 cells kept, the farthest from the threat taken: %s" % [search["stations"]])
	plan["threat"] = null
	var coin := AISkillPlanning.choose_any(plan, "", _sequence([0, 0, 0, 1], []))
	check(coin["intent"]["destination"] == Vector2i(7, 4) and coin["decision"]["attempts"][0]["search"]["position_draws"] == [{"bound": 2, "value": 1}], "no threat: rand(count) over the kept cells (0x40d1c8)")
	plan["threat"] = Vector2i(0, 4)
	plan["move_search"] = false
	var stayed := AISkillPlanning.choose_any(plan, "", func(_bound): return 0)
	check(stayed["intent"]["destination"] == origin and int(stayed["decision"]["coverage"]) == 3, "a stationary caster scans only its own cell")
	plan["move_search"] = true
	plan["skills"][0]["intents"] = [intents[0]]
	var home := AISkillPlanning.choose_any(plan, "", func(_bound): return 0)
	check(home["intent"]["destination"] == origin, "a move search that finds nothing scans the own cell (0x40d439..0x40d47e)")


## 0x43ff1f..0x44003c: a magic category that cast nothing rolls rand(100) (0x43ff32); at 10 or below
## the armed actor steps to the cell nearest the switched object's first station within a budget-1
## flood (0x40f440(actor, 1, mode) at 0x43ff68) and strikes the held target only if it is in weapon
## range from there.
func side_walk_cases() -> void:
	for raw in [10, 11]:
		var roll := run_ai_decision_tests.AIDecisionRules.side_walk_roll(func(bound):
			check(bound == 100, "the side walk draws rand(100)")
			return raw)
		check(bool(roll["taken"]) == (raw == 10), "rand(100) %d %s the side walk" % [raw, "takes" if raw == 10 else "skips"])
	for raw in [0, 10, 11]:
		var loop := run_ai_decision_tests.live_fixture()
		for id in ["magic:magicAIR:magicCode01", "magic:magicFIRE:magicCode01"]: own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "0"
		var after := BattlePlayLoop.step_ai_turn(loop, func(bound): return raw if bound == 100 else 0)
		var action: Dictionary = after["last_ai_action"]
		var side: Dictionary = action["ai_decision"].get("side_walk", {})
		if raw <= 10:
			check(side.get("taken") == true and action.get("purpose") == "side_walk" and action["kind"] == "move" and action["to"] == Vector2i(3, 4) and action.get("toward") == "leonard", "rand(100) %d: one step toward the first station (4, 4) — (4, 3) holds Leonard — and no strike from there: %s" % [raw, action.get("to")])
			check(side.get("switch_id") == "leonard" and side.get("station") == Vector2i(4, 4) and side.get("arrival_in_range") == false, "the station comes from the 0x40d8b0 switch and the wait from the arrival range check")
		else:
			check(side.get("taken") == false and action.get("purpose") != "side_walk" and action["kind"] == "attack" and action["to"] == Vector2i(3, 3), "rand(100) 11: the ordinary category strikes in place")
		check(not action.has("skill_id") and BattlePlayLoop.unit(after, "enemy026_1")["mp"] == 30, "the side walk never pays for the declined spell")


# ---- run_ai_skill_tests.gd ----
const AICallRules = preload("res://game/sim/AICallRules.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


func run_ai_call() -> void:
	native_cases_ai_call()
	status_and_movement()


func native_cases_ai_call() -> void:
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
		var recipients := AICallRules.recipients(rows, int(input["owner"]), int(input["radius"]))
		check(recipients["ok"] and rows == before, "call geometry is pure")
		var tags: Array = input["units"].map(func(unit): return null if unit == null else int(unit["tag"]))
		if input["kind"] == "broadcast":
			check(recipients["indices"] == row["result"]["recipients"].map(func(index): return int(index)), "recipients match original full return, including removed and exact side flags")
			for index in recipients["indices"]: tags[index] = int(input["tag"])
		else:
			var pending := int(input["units"][int(input["owner"])]["tag"])
			var candidate: Variant = input["units"][pending - 1] if pending > 0 else null
			var eligible: bool = candidate != null and not candidate["removed"] and (int(input["excluded_word"]) == 0 or candidate["object_code"] != input["excluded_word"])
			var adoption := AICallRules.adopt(int(input["ordinary"]) - 1, pending - 1, pending > 0, eligible)
			check(adoption["index"] + 1 == int(row["result"]["target"]), "adoption matches original prefix target")
			if adoption["consumed"]: tags[int(input["owner"])] = 0
			if adoption["broadcast"] and int(input["radius"]) > 0:
				for index in recipients["indices"]: tags[index] = int(input["ordinary"])
		check(tags == row["result"]["tags"].map(func(tag): return null if tag == null else int(tag)) and input == saved, "entire pending-tag table matches original with immutable input")
	check(not AICallRules.recipients([], 0, 5)["ok"], "missing owner is rejected")


func status_and_movement() -> void:
	var loop := run_ai_decision_tests.live_fixture()
	own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0
	var mage := BattlePlayLoop.unit_ref(loop, "enemy026_1")
	mage["ai_call_target_id"] = "leonard"
	mage["inventory"] = [0,0,0,0,0,0,0,0] # Called attack fallback after no available self-cure.
	mage["status_flags"] = 3
	mage["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var after := BattlePlayLoop.step_ai_turn(loop, func(_n): return 0)
	check(after["scenario_ok"] and after["last_ai_action"].get("defender_id") == "leonard" and not after["last_ai_action"].has("skill_id"), "called target cannot bypass silence to cast magic")
	check(BattlePlayLoop.unit(after, "enemy026_1")["mp"] == mage["mp"] and BattlePlayLoop.unit(after, "enemy026_1")["ai_call_target_id"] == "", "silenced action consumes the call without an MP debit")
	check(BattlePlayLoop.unit(after, "enemy026_1")["hp"] == 393 and BattlePlayLoop.unit(after, "enemy026_1")["status_counters"] == {"poison": (7 << 16) | 1, "paralysis": 0, "no_magic": 0} and after["selected_unit_id"] == "enemy023_1", "called action ticks poison and expires silence once before the player handoff")
	var distant := run_ai_decision_tests.live_fixture("enemy021_1")
	BattlePlayLoop.unit_ref(distant, "leonard")["coord"] = Vector2i(14, 3)
	BattlePlayLoop.unit_ref(distant, "enemy023_1")["defeated"] = true
	own(distant, "ai_profiles")["actors"]["021"]["profile"]["find_range"] = 1
	BattlePlayLoop.unit_ref(distant, "enemy021_1")["ai_call_target_id"] = "leonard"
	var saved := distant.duplicate(true)
	# The dispatcher roll (0x440db5, read by the lock 0x441002 for the adopted call target too) and
	# the state 0xa category roll (0x40c570 at 0x43fe0c, drawn whatever the target offers)
	# comes first; after it the pursuit walk's equal-candidate coin (0x413740) is the only draw.
	var walk_draws: Array = []
	var walked := BattleLoopAI.ai_take_turn(distant, "enemy021_1", func(n): walk_draws.append(n); return 0)
	check(walk_draws.size() > 2 and walk_draws.slice(0, 2) == [99, 99] and walk_draws.slice(2).all(func(n): return n == 2), "unreachable call target draws the dispatcher and category rolls, then only walk coins: %s" % str(walk_draws))
	check(walked["loop"]["scenario_ok"] and walked["action"]["kind"] == "move" and walked["action"]["toward"] == "leonard", "distant call target produces a chase without expanding ordinary find_range")
	check(not walked["action"]["path"].is_empty() and BattlePlayLoop.movement_cells(distant, "enemy021_1").has(walked["action"]["to"]), "called movement remains inside the existing legal movement envelope")
	check(BattlePlayLoop.unit(walked["loop"], "enemy021_1")["ai_call_target_id"] == "" and distant == saved, "movement consumes only the published call, leaving the input battle intact")
	# A one-row corridor leaves every refinement flood one strictly nearest cell: no coin.
	var corridor := distant.duplicate(true)
	for y in range(16):
		for x in range(16):
			if y != 3: own(corridor, "tiles")[Vector2i(x, y)] = {"blocks_movement": true, "move_cost": 1}
	var corridor_draws: Array = []
	var straight := BattleLoopAI.ai_take_turn(corridor, "enemy021_1", func(n): corridor_draws.append(n); return 0)
	check(corridor_draws == [99, 99] and straight["action"]["kind"] == "move" and straight["action"]["toward"] == "leonard", "called pursuit with one nearest cell at every refinement draws nothing after the dispatcher and category rolls: %s" % str(corridor_draws))

extends "res://tests/support/TestSuite.gd"
const ResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const Catalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")


func _init() -> void:
	tag = "SKILL_RESOURCE_TESTS"


## A damage-stream state whose first rand(100) is `roll` (the cast's hit roll draws first).
static func stream_rolling(roll: int) -> Array:
	for seed in range(1, 100000):
		if int(DamageRandom.rand(DamageRandom.seeded(seed), 100)["value"]) == roll: return DamageRandom.seeded(seed)
	return []


## Generator steps from one damage-stream state to another (-1 beyond 32).
static func steps_between(start: Array, end: Variant) -> int:
	var state := start.duplicate()
	for count in range(33):
		if state == end: return count
		state = DamageRandom.raw(state)["state"]
	return -1


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	return Loop.select_player_unit(loop, "leonard")


func run() -> void:
	var catalog := Catalog.items()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_skill_resources.json"))
	for case in oracle["cases"]:
		var amounts := ResourceRules.amounts(case["channel"],case["expend"],case["half_mp"])
		check(amounts["ok"],"native valid cost is accepted")
		var native_available: bool = case["available"] >= amounts["native_required"]
		check(native_available == bool(case["affordable"]),"required threshold matches complete native affordability helper")
		if case["channel"] == "magic":
			check(case["available"]-amounts["amount"] == case["debit_block"]["remaining_mp"],"charge matches native bounded MP debit")
		else:
			check(amounts["amount"] == case["base_cost"],"ST cost matches native complete getter")
		var fixture_items := {"1":{"mp_use_half":case["half_mp"]}}
		var actor := {"mp":int(case["available"]),"stamina":int(case["available"]),"equipment":[{"slot":"weapon","item_code":1}]}
		var before := actor.duplicate(true)
		var quote := ResourceRules.quote(actor,{"expend":case["expend"]},case["channel"],fixture_items)
		check(quote["ok"] == (case["available"] >= amounts["amount"]),"product rejects negative-resource corner explicitly")
		check(actor == before,"quote never owns or mutates actor resources")
	for invalid in [null,-1,1.5,"", "1.5","garbage",INF,NAN,true]:
		check(not ResourceRules.amounts("special",invalid)["ok"],"invalid or missing source cost cannot become free")
	check(not ResourceRules.amounts("special",2147483647)["ok"],"overflowing source cost is refused")
	check(ResourceRules.amounts("special","1")["amount"] == 20,"raw source text uses the same recovered cost")
	var loop := controlled()
	var actor := Loop._unit(loop,"leonard")
	actor["stamina"] = 19
	var page := Loop.choose_command(loop,"special")
	check(not Loop.can_use_special(loop,"leonard") and Loop.command_available(loop,"special") and page["interaction"] == "special_select" and page["units"] == loop["units"],"19 ST still opens the skill page (the original opens it with the gauge empty)")
	check(Loop.choose_special(page,"special:magicOTHER:magicCode01") == page,"19 ST cannot start the source cost20 skill from the page")
	check(Loop.cancel_interaction(page)["interaction"] == "action_menu","the page is left by cancelling back to the action menu")
	actor["stamina"] = 20
	var foe := Loop._unit(loop,"enemy021_1")
	foe["coord"] = actor["coord"] + Vector2i.UP
	foe["hp"] = 100
	foe["combat_profile"]["live_defense"] = 10000
	check(Loop.can_use_special(loop,"leonard"),"exact20 ST enables special")
	var selected := Loop.choose_special(Loop.choose_command(loop,"special"),"special:magicOTHER:magicCode01")
	var cancelled := Loop.cancel_interaction(selected)
	check(Loop.unit(cancelled,"leonard")["stamina"] == 20 and cancelled["turn_queue"] == loop["turn_queue"],"target cancel preserves resource and turn")
	for hit in [true,false]:
		var before := selected.duplicate(true)
		var result := Loop.attack_target(selected,"enemy021_1",func(n):return 0 if hit else n-1)
		check(Loop.unit(result,"leonard")["stamina"] == 0,"hit and miss charge exactly20 ST once")
		check(result["last_attack"]["hit"] == hit,"fixture actually exercises requested hit outcome")
		check(result["last_attack"]["resource_payment"]["before"] == 20 and result["last_attack"]["resource_payment"]["amount"] == 20,"receipt records settled authoritative resource cost")
		check(Loop.attack_target(result,"enemy021_1")["units"] == result["units"],"repeat confirmation cannot charge a second time")
		check(selected == before,"special transaction preserves input")
	var no_random := func(_n): check(false,"invalid resource/target must not consume RNG"); return 0
	var wrong_target := Loop.attack_target(selected,"enemy023_1",no_random)
	check(wrong_target["units"] == selected["units"] and wrong_target["turn_queue"] == selected["turn_queue"],"wrong-target special cannot spend any resource")
	var stale := selected.duplicate(true)
	Loop._unit(stale,"leonard")["stamina"] = 19
	var refused := Loop.attack_target(stale,"enemy021_1",no_random)
	check(refused["units"] == stale["units"] and not refused["attacked_this_action"],"cost rechecked after target selection")
	var missing := selected.duplicate(true)
	own(missing, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"].erase("expend")
	check(not Loop.can_use_special(missing,"leonard"),"missing cost disables availability")
	refused = Loop.attack_target(missing,"enemy021_1",no_random)
	check(refused["units"] == missing["units"] and refused["last_attack_reject"]["reason"] == "invalid_skill_cost","missing cost fails explicitly before settlement")
	for bad in [null,"20",-1,1.5,INF,NAN]:
		var invalid := actor.duplicate(true)
		invalid["stamina"] = bad
		check(not ResourceRules.quote(invalid,{"expend":"1"},"special",catalog)["ok"],"live resource must be a finite nonnegative integer")
	var halves: Array = catalog.keys().filter(func(code):return catalog[code]["mp_use_half"])
	check(not halves.is_empty(),"source catalog contains actual half-MP items")
	for half in [false,true]:
		var magic_loop := BattleFixture.loop()
		var mage := Loop._unit(magic_loop,"enemy026_1")
		var target := Loop._unit(magic_loop,"leonard")
		mage["coord"] = target["coord"] + Vector2i.RIGHT
		mage["move_point"] = 0 # Isolate cost/hit draws from the independent position tie chooser.
		target["hp"] = 100
		target["max_hp"] = 100
		if half and not halves.is_empty():
			# Only the resource modifier is exercised. This fixture does not unlock
			# otherwise unsupported equipment or claim its other passives work.
			mage["equipment"] = [{"slot":"accessory1","item_code":int(halves[0])}]
		var wind: Dictionary = magic_loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]
		own(magic_loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"].erase("fields")
		check(Loop._skill_input_error(magic_loop, mage) == "skill_identity_mismatch", "missing definition for a declared owned spell fails before enumeration")
		# This isolated cost route grants only wind; removing a definition alone
		# must no longer silently hide another source-owned spell.
		own(magic_loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = ["magic:magicAIR:magicCode01"]
		var price: int = ResourceRules.amounts("magic",wind["fields"]["expend"],half)["amount"]
		for hit in [true,false]:
			mage["mp"] = price
			var fixture := magic_loop.duplicate(true)
			# Selection draws from the AI decision source; the settlement — native hit, then
			# for a hit the two triangular samples and two EXP values — from the loop's
			# damage stream (0x42c780). A miss stops before both damage and EXP draws.
			set_stream(fixture, "damage", stream_rolling(0 if hit else 99))
			var start: Array = stream_of(fixture, "damage")
			var draws := [0,0,0]
			var bounds: Array = []
			var strike := LoopAI._try_skill_turn(fixture,"enemy026_1",[Loop._unit(fixture,"leonard")],func(n):
				bounds.append(n)
				check(not draws.is_empty(), "cost route received an unexpected random request")
				return draws.pop_front() if not draws.is_empty() else 0)
			check(not strike.is_empty() and strike["hit"] == hit,"AI exercises affordable actual source spell")
			check(draws.is_empty() and bounds == [100, 32, 100],"the decision source serves exactly the native selection draws")
			_assert_eq(steps_between(start, stream_of(fixture, "damage")), 5 if hit else 1, "the damage stream serves the native hit, and only a hit converts a contribution (triangular pair, EXP pair)")
			check(Loop.unit(fixture,"enemy026_1")["mp"] == 0 and strike["resource_payment"]["amount"] == price,"AI availability and debit share exact normal/half cost")
		mage["mp"] = price-1
		var poor := magic_loop.duplicate(true)
		check(LoopAI._try_skill_turn(magic_loop,"enemy026_1",[target],no_random).is_empty() and magic_loop == poor,"unaffordable AI choice cannot move, damage or consume RNG")
		mage["mp"] = price
		own(magic_loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"].erase("expend")
		var malformed := magic_loop.duplicate(true)
		check(LoopAI._try_skill_turn(magic_loop,"enemy026_1",[target],no_random).get("reason") == "invalid_skill_cost" and magic_loop == malformed,"malformed AI cost is explicitly rejected before effects or RNG")
		for index in range(magic_loop["turn_queue"]["slots"].size()):
			if magic_loop["turn_queue"]["slots"][index]["id"] == "enemy026_1":
				magic_loop["turn_queue"]["index"] = index
		magic_loop["interaction"] = "ai_resolving"
		var failed := Loop.step_ai_turn(magic_loop,no_random)
		check(not failed["scenario_ok"] and failed["scenario_error"] == "invalid_skill_cost" and failed["interaction"] == "scenario_error","invalid AI source fails explicitly instead of falling back to a physical attack")
		check(failed["units"] == magic_loop["units"] and failed["turn_queue"] == magic_loop["turn_queue"],"invalid AI data cannot partially move, spend or advance")
	var absent := actor.duplicate(true)
	absent["mp"] = 10
	var broken_catalog := catalog.duplicate(true)
	broken_catalog[str(int(absent["equipment"][0]["item_code"]))].erase("mp_use_half")
	check(ResourceRules.quote(absent,{"expend":3},"magic",broken_catalog)["reason"] == "missing_magic_cost_modifier","missing modifier metadata fails explicitly")

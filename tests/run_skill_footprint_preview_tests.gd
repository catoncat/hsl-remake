extends "res://tests/support/TestSuite.gd"
## Skill targeting preview = settlement: for every skill in the book, from a caster in the
## middle of an open field, every legal center's preview footprint
## (BattleLoopCombat.skill_cast_footprint — what BattleSceneOverlays.refresh_skill_footprint
## draws) must be exactly the cells whose occupants SkillResolutionRules.prepare_cast takes as
## targets. Every other cell the skill can reach — range reach plus effect reach from the
## caster (SkillTargetRules.cells／effect_cells never place a footprint cell farther) and one
## ring beyond, so a settlement past its own footprint still hits a dummy — holds a
## side-matching unit. Shapes are tallied by (range, effect_range) so the report names each
## class (single cell, cross, Dir line, self-centred area, circles …).
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SCENARIO := "res://content/battles/battle_003.json"
const MAP_SIZE := Vector2i(23, 23)
const ORIGIN := Vector2i(11, 11)
## Per-unit usefulness gates: a utility effect (steal, drain …) skips a unit that yields
## nothing, so its targets are a subset of the footprint's occupants, never outside it.
const SUBSET_POLICIES := ["native_special_utility"]


func _init() -> void:
	tag = "SKILL_FOOTPRINT_PREVIEW_TESTS"


func run() -> void:
	var base: Dictionary = BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file(SCENARIO)))
	check(bool(base.get("scenario_ok", false)), "level 3 initializes")
	var book: Dictionary = base["skill_book"].duplicate(true)
	var targeting: Dictionary = base["skill_target_data"]
	var equipment: Dictionary = base["equipment_items"]
	var caster: Dictionary = BattlePlayLoop.unit(base, "hu").duplicate(true)
	var ally_template: Dictionary = BattlePlayLoop.unit(base, "tina").duplicate(true)
	var foe_template: Dictionary = BattlePlayLoop.unit(base, "actor028_1").duplicate(true)
	# The birth carry is a global-stream roll (0x407c86; RNGC), so whether 028_1 was born holding
	# anything depends on the seed. StealItem's usefulness gate is slot 0 (SpecialUtilityRules,
	# 0x40b4e8 walk): give every foe dummy a stealable bag explicitly.
	if int(foe_template["inventory"][0]) == 0: foe_template["inventory"][0] = 241
	caster["coord"] = ORIGIN
	# Harness ownership and purse: the caster declares every skill and can pay any cost.
	book["actors"][str(caster["actor_id"])]["supported_initial_ids"] = book["skills"].keys()
	caster["max_mp"] = 9999
	caster["mp"] = 9000 # below the maximum: an MP heal on the caster has something to restore
	caster["stamina"] = 100
	_afflict(caster)
	var context := BattlePlayLoop.Combat._skill_context(base)
	var shapes := {}
	var verified := 0
	var unverified: Array[String] = []
	for skill_id in book["skills"]:
		var entry: Dictionary = book["skills"][skill_id]
		var fields: Dictionary = entry["fields"]
		var support := SkillTargetRules.is_support(fields, targeting)
		var units: Array = [caster]
		var radius := _reach(targeting["ranges"][fields["range"]]) + _reach(targeting["ranges"][fields["effect_range"]]) + 1
		for y in range(maxi(0, ORIGIN.y - radius), mini(MAP_SIZE.y, ORIGIN.y + radius + 1)):
			for x in range(maxi(0, ORIGIN.x - radius), mini(MAP_SIZE.x, ORIGIN.x + radius + 1)):
				var cell := Vector2i(x, y)
				if cell == ORIGIN: continue
				var dummy: Dictionary = (ally_template if support else foe_template).duplicate(true)
				dummy["id"] = "dummy_%d_%d" % [x, y]
				dummy["coord"] = cell
				_afflict(dummy)
				units.append(dummy)
		var preview_loop := {"units": [caster], "selected_unit_id": caster["id"], "selected_skill_id": skill_id,
			"interaction": "attack_select", "selected_attack": entry["channel"], "skill_book": book,
			"skill_target_data": targeting, "map_size": MAP_SIZE}
		var shape := "%s→%s" % [fields["range"], fields["effect_range"]]
		shapes[shape] = int(shapes.get(shape, 0)) + 1
		var centers := SkillTargetRules.cells(ORIGIN, fields, targeting, MAP_SIZE)
		check(not centers.is_empty(), "%s has cast centers" % skill_id)
		var skill_context: Dictionary = _utility_context(context, units, str(caster["id"]), str(fields["function"])) if entry["damage_policy"] == "native_special_utility" else context
		var skill_ok := true
		var reason := ""
		for center in centers:
			var preview: Array = BattlePlayLoop.Combat.skill_cast_footprint(preview_loop, center)
			check(not preview.is_empty(), "%s previews a footprint at legal center %s" % [skill_id, center])
			var expected := {}
			for cell in preview:
				if cell != ORIGIN or support: expected[cell] = true
			var primary: Dictionary = {}
			for unit in units:
				if expected.has(unit["coord"]) and (unit["coord"] == center or primary.is_empty()): primary = unit
			if primary.get("id") == caster["id"] and entry["damage_policy"] == "native_special_utility":
				# A queue utility cannot act on its own caster's slot; any other member it
				# reaches is the chosen unit (the center stays the caster's cell).
				for unit in units:
					if unit["id"] != caster["id"] and expected.has(unit["coord"]): primary = unit; break
			if primary.is_empty(): continue
			var prepared := SkillResolutionRules.prepare_cast(caster, primary, units, skill_id, fields, book, targeting, equipment, ORIGIN, MAP_SIZE, center, skill_context)
			if not prepared["ok"]:
				skill_ok = false
				reason = str(prepared["reason"])
				break
			var hit := {}
			for target in prepared["targets"]: hit[target["coord"]] = true
			var outside: Array = hit.keys().filter(func(cell): return not expected.has(cell))
			check(outside.is_empty(), "%s at %s settles no cell outside its preview (%s)" % [skill_id, center, outside])
			if entry["damage_policy"] not in SUBSET_POLICIES:
				var missed: Array = expected.keys().filter(func(cell): return not hit.has(cell))
				check(missed.is_empty(), "%s at %s settles every previewed occupant (missed %s)" % [skill_id, center, missed])
		if skill_ok: verified += 1
		else: unverified.append("%s:%s" % [skill_id, reason])
	var lines: Array[String] = []
	for shape in shapes: lines.append("%s=%d" % [shape, shapes[shape]])
	lines.sort()
	print("SKILL_FOOTPRINT_SHAPES %s" % " ".join(lines))
	print("SKILL_FOOTPRINT_VERIFIED skills=%d verified=%d unverified=%s" % [book["skills"].size(), verified, unverified])
	check(unverified.is_empty(), "every skill settles through prepare_cast on the filled field: %s" % [unverified])


## Chebyshev reach of a targeting pattern from its centre: a Dir line runs size − 1 cells past
## the chosen cell (SkillTargetRules.line_cells), a grid pattern reaches its farthest set cell.
static func _reach(pattern: Dictionary) -> int:
	if SkillTargetRules.is_line(pattern): return int(pattern["size"]) - 1
	var half := int(pattern["size"]) / 2
	var reach := 0
	for y in range(int(pattern["size"])):
		for x in range(int(pattern["size"])):
			if int(pattern["data"][y][x]) > 0: reach = maxi(reach, maxi(absi(x - half), absi(y - half)))
	return reach


## Every unit carries something each support effect can act on: half HP and poison (a
## cure-poison component is in every cure skill). Poison does not stop casting.
static func _afflict(unit: Dictionary) -> void:
	unit["hp"] = maxi(1, int(unit["max_hp"]) / 2)
	unit["status_flags"] = int(unit["status_flags"]) | BattlePlayLoop.StatusEffectRules.POISON
	unit["status_counters"]["poison"] = 3
	# An attack boost for 退魔 (magicFun_ClearAtDfUp) to clear; a further boost still stacks.
	unit["status_flags"] = int(unit["status_flags"]) | BattlePlayLoop.StatusEffectRules.Enhancements.FLAGS["attack_up"]
	unit["status_counters"]["attack_up"] = (5 << 16) | 3


## A queue the queue utilities can act on: 天鳴覺醒 (ActiveAgain) re-activates a member that
## already acted, 獅子吼 (CancelActive) cancels one still to act — every dummy stands on the
## eligible side of the caster's slot.
static func _utility_context(context: Dictionary, units: Array, caster_id: String, function_text: String) -> Dictionary:
	var queue: Dictionary = BattlePlayLoop.CoreTurnQueue.rebuild(units)
	var others: Array = queue["slots"].filter(func(slot): return slot["id"] != caster_id)
	var own: Array = queue["slots"].filter(func(slot): return slot["id"] == caster_id)
	var again := function_text.contains("ActiveAgain")
	queue["slots"] = others + own if again else own + others
	queue["index"] = others.size() if again else 0
	queue["round"] = 1
	var next := context.duplicate()
	next["turn_queue"] = queue
	return next

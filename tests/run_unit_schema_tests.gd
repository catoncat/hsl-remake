extends SceneTree
## game/sim/UnitSchema.gd against content/schema/unit.schema.json: every unit of every
## tracked scenario (assembled battle_NNN.json, hand-curated rosters, script actor
## templates, source actor templates) passes; the validator implements the same JSON
## Schema subset as tools/hsltools/schema/validate.py with the same first-error text;
## the wave-nine shapes (equipment as an int list, resist_by_type as an array, a key at
## the wrong level) are rejected; and the play loop refuses a scenario or carry whose
## roster violates the contract instead of initializing it.

const UnitSchema = preload("res://game/sim/UnitSchema.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Carry = preload("res://game/sim/CampaignCarryRules.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func run() -> void:
	_test_validator_subset()
	_test_every_tracked_unit_passes()
	_test_wave_nine_shapes_rejected()
	_test_initialized_and_carried_units_pass()
	_test_play_loop_refuses_violations()
	for failure in failures:
		push_error(failure)
	print("UNIT_SCHEMA_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _test_validator_subset() -> void:
	var schema := {"type": "object", "required": ["a"], "additionalProperties": false, "properties": {
		"id": {"type": "string"}, "a": {"type": "integer"}, "b": {"type": "string", "enum": ["x", "y"]},
		"c": {"type": "array", "items": {"type": "integer"}, "minItems": 2, "maxItems": 2},
		"d": {"type": ["integer", "null"]}}}
	check(UnitSchema.input_error({"a": 1, "b": "x", "c": [1, 2], "d": null}, schema) == "", "valid object passes")
	check(UnitSchema.input_error({"a": 1.0, "c": Vector2i(3, 4)}, schema) == "", "integral float is an integer and Vector2i is a two-integer array")
	check(UnitSchema.input_error({"b": "x"}, schema) == "$: missing required key 'a'", "required")
	check(UnitSchema.input_error({"a": true}, schema) == "$.a: expected integer, got boolean", "bool is not an integer")
	check(UnitSchema.input_error({"a": 1.5}, schema) == "$.a: expected integer, got number", "fractional float is a number")
	check(UnitSchema.input_error({"a": 1, "b": "z"}, schema) == "$.b: 'z' not in enum ['x', 'y']", "enum, Python repr")
	check(UnitSchema.input_error({"a": 1, "c": [1]}, schema) == "$.c: expected at least 2 items, got 1", "minItems")
	check(UnitSchema.input_error({"a": 1, "c": [1, 2, 3]}, schema) == "$.c: expected at most 2 items, got 3", "maxItems")
	check(UnitSchema.input_error({"a": 1, "c": [1, "two"]}, schema) == "$.c[1]: expected integer, got string", "items")
	check(UnitSchema.input_error({"a": 1, "zzz": 0}, schema) == "$: unexpected key 'zzz'", "additionalProperties=false")
	check(UnitSchema.input_error({"a": 1, "d": "no"}, schema) == "$.d: expected integer|null, got string", "type list")
	check(UnitSchema.input_error({}, {"type": "object", "pattern": "x"}) == "$: unsupported schema keyword(s) ['pattern']", "unknown keyword is a violation, not silently ignored")
	check(UnitSchema.input_error({}, {"type": "object"}, "units[leonard]") == "", "custom path label")
	check(UnitSchema.roster_error([{"a": 1}, {"b": "x"}], schema) == "units[1]: missing required key 'a'", "roster_error labels by id or index")
	check(UnitSchema.roster_error([{"id": "hero", "a": 1}, {"id": "orc"}], schema) == "units[orc]: missing required key 'a'", "roster_error uses the unit id")
	var tracked := UnitSchema.schema()
	check(tracked.get("$id") == "hsl_unit.v1" and tracked.get("additionalProperties") == false, "tracked schema loads with the expected id and top-level strictness")
	var equipment: Dictionary = tracked["properties"]["equipment"]["items"]
	check(equipment["required"] == ["item_code", "name", "slot"] and equipment["additionalProperties"] == false, "equipment entries are the six-slot {slot, item_code, name} records")


func _scenario_paths() -> Array:
	var paths: Array = []
	var dir := DirAccess.open("res://content/battles")
	for file in dir.get_files():
		if file.ends_with(".json") and not file.begins_with("story_") and file != "campaign.json":
			paths.append("res://content/battles/" + file)
	paths.sort()
	return paths


func _test_every_tracked_unit_passes() -> void:
	var scenarios := 0
	var units := 0
	var templates := 0
	for path in _scenario_paths():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not parsed.has("playable_units"):
			continue
		scenarios += 1
		for unit in parsed["playable_units"]:
			units += 1
			var found := UnitSchema.input_error(unit)
			check(found == "", path + " playable unit: " + found)
		for symbol in parsed.get("script_actor_templates", {}):
			templates += 1
			var found := UnitSchema.input_error(parsed["script_actor_templates"][symbol]["actor"], {}, symbol)
			check(found == "", path + " template: " + found)
		var normalized := BattleScenario.units(parsed)
		var roster_error := UnitSchema.roster_error(normalized)
		check(roster_error == "", path + " normalized roster: " + roster_error)
	var actors := DirAccess.open("res://content/generated/hsl/actors")
	var actor_templates := 0
	for file in actors.get_files():
		if not file.ends_with(".json"):
			continue
		actor_templates += 1
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/actors/" + file))
		var found := UnitSchema.input_error(parsed["actor"], {}, file)
		check(found == "", "actor template: " + found)
	check(scenarios >= 136 and units >= 2500 and templates >= 114 and actor_templates >= 54, "coverage: scenarios=%d units=%d templates=%d actor_templates=%d" % [scenarios, units, templates, actor_templates])


func _source_unit() -> Dictionary:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_037.json"))
	return (parsed["playable_units"][0] as Dictionary).duplicate(true)


func _test_wave_nine_shapes_rejected() -> void:
	var unit := _source_unit()
	unit["equipment"] = [82, 15]
	check(UnitSchema.input_error(unit) == "$.equipment[0]: expected object, got integer", "equipment written as an int list is rejected")
	unit = _source_unit()
	unit["equipment"] = [{"slot": "weapon", "item_code": 82}]
	check(UnitSchema.input_error(unit) == "$.equipment[0]: missing required key 'name'", "equipment entry without name is rejected")
	unit = _source_unit()
	unit["equipment"] = [{"slot": "ring", "item_code": 82, "name": ""}]
	check(UnitSchema.input_error(unit).begins_with("$.equipment[0].slot: 'ring' not in enum ["), "unknown equipment slot is rejected")
	unit = _source_unit()
	unit["combat_profile"]["resist_by_type"] = [0, 0, 0, 0, 0]
	check(UnitSchema.input_error(unit) == "$.combat_profile.resist_by_type: expected object, got array", "resist_by_type as an array is rejected")
	unit = _source_unit()
	unit["job_up_templates"] = {}
	check(UnitSchema.input_error(unit) == "$: unexpected key 'job_up_templates'", "a scenario-level key on a unit is rejected")
	unit = _source_unit()
	unit.erase("status_counters")
	check(UnitSchema.input_error(unit) == "$: missing required key 'status_counters'", "missing required key is rejected")
	unit = _source_unit()
	unit["battle_actor_role"] = "enemy"
	check(UnitSchema.input_error(unit) == "$.battle_actor_role: 'enemy' not in enum ['enemy_ai', 'friendly_ai', 'player_controlled']", "role vocabulary is closed")
	unit = _source_unit()
	unit["vitals_evidence_tier"] = "confirmed"
	check(UnitSchema.input_error(unit).begins_with("$.vitals_evidence_tier: 'confirmed' not in enum ['resource-derived', 'static-derived'"), "evidence tier vocabulary is closed")
	unit = _source_unit()
	unit["coord"] = [1]
	check(UnitSchema.input_error(unit) == "$.coord: expected at least 2 items, got 1", "coord needs two integers")


func _test_initialized_and_carried_units_pass() -> void:
	var scenario := BattleScenario.load_file("res://content/battles/battle_037.json")
	var loop := Loop.create([], "", scenario)
	check(bool(loop["scenario_ok"]), "battle 37 initializes: " + str(loop.get("scenario_error", "")))
	check(UnitSchema.roster_error(loop["units"]) == "", "initialized units keep the contract: " + UnitSchema.roster_error(loop["units"]))
	var grown := Loop.initialize_roster_growth(loop)
	check(UnitSchema.roster_error(grown["units"]) == "", "entry-grown units keep the contract: " + UnitSchema.roster_error(grown["units"]))
	var carry := Carry.capture(grown)
	var next := Loop.apply_campaign_carry(Loop.create([], "", scenario), carry)
	check(bool(next["scenario_ok"]) and next["campaign_carry_receipt"]["errors"].is_empty(), "carry applies cleanly")
	check(UnitSchema.roster_error(next["units"]) == "", "carried units keep the contract: " + UnitSchema.roster_error(next["units"]))
	for spec in loop.get("script_actor_source", {}).get("templates", {}).values():
		var found := UnitSchema.input_error(spec["actor"])
		check(found == "", "prepared script actor template keeps the contract: " + found)


func _test_play_loop_refuses_violations() -> void:
	var scenario := BattleScenario.load_file("res://content/battles/battle_037.json")
	var broken := scenario.duplicate(true)
	broken["playable_units"][2]["equipment"] = [82, 15]
	var loop := Loop.create([], "", broken)
	var unit_id := str(broken["playable_units"][2]["id"])
	check(not bool(loop["scenario_ok"]) and loop["interaction"] == "scenario_error", "scenario roster violating the contract fails initialization explicitly")
	check(str(loop.get("scenario_error", "")) == "unit_schema:units[" + unit_id + "].equipment[0]: expected object, got integer", "scenario error names the unit and the violation: " + str(loop.get("scenario_error", "")))
	broken = scenario.duplicate(true)
	var symbol: String = broken["script_actor_templates"].keys()[0]
	broken["script_actor_templates"][symbol]["actor"]["combat_profile"]["resist_by_type"] = [0, 0, 0, 0, 0]
	loop = Loop.create([], "", broken)
	check(str(loop.get("scenario_error", "")) == "unit_schema:script_actor_templates." + symbol + ".actor.combat_profile.resist_by_type: expected object, got array", "script actor template violating the contract fails initialization: " + str(loop.get("scenario_error", "")))
	var healthy := Loop.create([], "", scenario)
	var carry := Carry.capture(Loop.initialize_roster_growth(healthy))
	var carried_id: String = carry["units"].keys()[0]
	carry["units"][carried_id]["equipment"] = [82, 15]
	var applied := Loop.apply_campaign_carry(Loop.create([], "", scenario), carry)
	check(not bool(applied["scenario_ok"]) or not applied["campaign_carry_receipt"]["errors"].is_empty(), "carry with an int-list equipment cannot silently enter the battle")
	carry = Carry.capture(Loop.initialize_roster_growth(healthy))
	carry["units"][carried_id]["kill_count"] = "3"
	applied = Loop.apply_campaign_carry(Loop.create([], "", scenario), carry)
	check(str(applied.get("scenario_error", "")) == "unit_schema:units[" + carried_id + "].kill_count: expected integer, got string" and not bool(applied["scenario_ok"]), "carry field the progression rules do not inspect but the contract does fails the hand-off explicitly: " + str(applied.get("scenario_error", "")))
	var supplied := Loop.create(healthy["units"].duplicate(true), "", scenario)
	check(bool(supplied["scenario_ok"]), "a caller-supplied initialized roster still creates (the JSON entry points are the validated seam)")

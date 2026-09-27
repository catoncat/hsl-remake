extends RefCounted
## Shared loading and normalization for battle scenario data. A battle (rule_adapter in
## content/schema/battle.schema.json) is validated against that contract on load and
## its optional keys take the schema defaults; scenes that are not battles (story,
## world map) only parse. Scenario-specific rule payloads stay in their own adapter modules.
## provenance:
##   rules: remake-invented
##     (scenario JSON contract content/schema/battle.schema.json, normalisation and defaults; evidence tiers are carried
##     as data, not decided here)

const UnitSchema = preload("res://game/sim/UnitSchema.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const BATTLE_SCHEMA_PATH := "res://content/schema/battle.schema.json"
const BATTLE_CONTRACT := "hsl_battle.v1"

static var _cached_battle_schema: Dictionary = {}


static func battle_schema() -> Dictionary:
	if _cached_battle_schema.is_empty():
		var parsed: Variant = ContentPaths.read_json(BATTLE_SCHEMA_PATH) if FileAccess.file_exists(BATTLE_SCHEMA_PATH) else null
		_cached_battle_schema = parsed if parsed is Dictionary else {}
	return _cached_battle_schema


## Whether the document is a battle the play loop can run (its rule_adapter is one the
## contract names); story and world-map scenes are not.
static func is_battle(scenario: Dictionary) -> bool:
	var adapters: Array = (battle_schema().get("properties", {}) as Dictionary).get("rule_adapter", {}).get("enum", [])
	return adapters.has(scenario.get("rule_adapter"))


## First violation of a battle document against the contract, "" when valid (or when the
## document is not a battle). An unreadable contract file is itself the violation.
static func battle_error(scenario: Dictionary) -> String:
	var schema := battle_schema()
	if schema.is_empty():
		return "$: battle schema missing at " + BATTLE_SCHEMA_PATH
	if not is_battle(scenario):
		return ""
	return UnitSchema.input_error(scenario, schema)


## The battle with every optional contract key at its default, marked `contract` so the
## loop knows the check ran; a non-battle document is returned unchanged.
static func with_defaults(scenario: Dictionary) -> Dictionary:
	if not is_battle(scenario):
		return scenario
	var filled: Dictionary = UnitSchema.apply_defaults(scenario, battle_schema())
	filled["contract"] = BATTLE_CONTRACT
	return filled


static func load_file(path: String, expected_schema: String = "") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "missing_scenario", "path": path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_scenario_json", "path": path}
	var scenario: Dictionary = parsed
	if expected_schema != "" and str(scenario.get("schema", "")) != expected_schema:
		return {
			"ok": false,
			"error": "unsupported_scenario_schema",
			"path": path,
			"schema": str(scenario.get("schema", "")),
		}
	var violation := battle_error(scenario)
	if violation != "":
		return {"ok": false, "error": "battle_schema:" + violation, "path": path}
	scenario = with_defaults(scenario)
	scenario["ok"] = true
	scenario["path"] = path
	return scenario


static func resource_path(scenario: Dictionary, key: String) -> String:
	return str((scenario.get("resources", {}) as Dictionary).get(key, ""))


static func units(scenario: Dictionary) -> Array:
	var result: Array = []
	for value in scenario.get("playable_units", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = (value as Dictionary).duplicate(true)
		var coord := vector2i(unit.get("coord", []))
		unit["coord"] = coord
		unit["grid_coord"] = coord
		unit["speed"] = int(unit.get("speed", unit.get("live_speed", 0)))
		unit["defeated"] = bool(unit.get("defeated", false))
		result.append(unit)
	return result


static func logical_viewport_size(scenario: Dictionary) -> Vector2i:
	return vector2i((scenario.get("view", {}) as Dictionary).get("logical_viewport", [640, 480]), Vector2i(640, 480))


static func grid_projection(scenario: Dictionary) -> Dictionary:
	var source: Dictionary = (scenario.get("view", {}) as Dictionary).get("grid_projection", {})
	return {
		"origin": vector2(source.get("origin", [0, 0]), Vector2.ZERO),
		"cell_size": vector2(source.get("cell_size", [32, 32]), Vector2(32.0, 32.0)),
		"evidence_id": str(source.get("evidence_id", "")),
		"provisional": bool(source.get("provisional", true)),
	}


static func command_flags(scenario: Dictionary) -> Dictionary:
	var commands: Dictionary = scenario.get("commands", {})
	return {
		"has_magic": bool(commands.get("has_magic", false)),
		"has_special": bool(commands.get("has_special", false)),
	}


static func vector2i(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


static func vector2(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2:
		return value
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback

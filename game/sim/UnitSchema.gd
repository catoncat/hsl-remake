extends RefCounted
## The one unit dictionary contract, runtime side. content/schema/unit.schema.json is
## derived by tools/hsltools/schema/unit.py from every tracked unit; the Python
## assembler validates what it writes against it (hsltools/schema/validate.py) and this
## file validates what the runtime loads, with the same JSON Schema subset and the same
## first-error string "<path>: <reason>". Runtime representations map onto JSON: Vector2i
## is a two-integer array, an integral float (JSON numbers parse as float) is an integer.
## Required keys are the rule inputs only (unit.py RULE_KEYS); the evidence ledgers
## (unit.py PROVENANCE_KEYS: <ledger>_evidence_tier／<ledger>_source, …) are optional
## pass-through, and a unit that carries none is authored content.
## provenance:
##   rules: remake-invented (unit dictionary contract derived from remake data by tools/hsltools/schema/unit.py — content/schema/unit.schema.json)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const PATH := "res://content/schema/unit.schema.json"
## Evidence tier of a unit ledger nobody wrote a tier for: content authored for the
## remake, with no original to compare against.
const AUTHORED_TIER := "authored"
## `default` is ignored by the validator and filled in by apply_defaults().
const KEYWORDS := ["type", "required", "properties", "additionalProperties", "enum", "items", "minItems", "maxItems", "default", "$schema", "$id", "title", "description"]

static var _cached_schema: Dictionary = {}


static func schema() -> Dictionary:
	if _cached_schema.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_cached_schema = parsed if parsed is Dictionary else {}
	return _cached_schema


## First violation of unit against the schema as "<path>: <reason>", "" when valid.
## An unreadable schema file is itself the violation: the contract must exist.
static func input_error(unit: Variant, target: Dictionary = {}, path: String = "$") -> String:
	var active := target if not target.is_empty() else schema()
	if active.is_empty():
		return path + ": unit schema missing at " + PATH
	return _error(unit, active, path)


static func json_type(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "boolean"
		TYPE_INT: return "integer"
		TYPE_FLOAT: return "integer" if value == floorf(value) else "number"
		TYPE_STRING, TYPE_STRING_NAME: return "string"
		TYPE_ARRAY, TYPE_VECTOR2I, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY: return "array"
		TYPE_DICTIONARY: return "object"
	return type_string(typeof(value))


## Python repr of the scalar, so both validators print the same enum violation.
static func _repr(value: Variant) -> String:
	if value is String or value is StringName:
		return "'" + str(value) + "'"
	if value is bool:
		return "True" if value else "False"
	if value == null:
		return "None"
	return str(value)


static func _as_array(value: Variant) -> Array:
	if value is Vector2i:
		return [value.x, value.y]
	return Array(value)


static func _type_matches(value: Variant, expected: String) -> bool:
	var actual := json_type(value)
	if expected == "number":
		return actual == "integer" or actual == "number"
	return actual == expected


static func _error(value: Variant, active: Dictionary, path: String) -> String:
	for keyword in active.keys():
		if not KEYWORDS.has(keyword):
			return path + ": unsupported schema keyword(s) ['" + str(keyword) + "']"
	if active.has("type"):
		var allowed: Array = active["type"] if active["type"] is Array else [active["type"]]
		if not allowed.any(func(kind): return _type_matches(value, str(kind))):
			return path + ": expected " + "|".join(allowed.map(func(kind): return str(kind))) + ", got " + json_type(value)
	if active.has("enum") and not (active["enum"] as Array).has(value):
		return path + ": " + _repr(value) + " not in enum [" + ", ".join((active["enum"] as Array).map(_repr)) + "]"
	if value is Dictionary:
		var object: Dictionary = value
		for key in active.get("required", []):
			if not object.has(key):
				return path + ": missing required key '" + str(key) + "'"
		var properties: Dictionary = active.get("properties", {})
		for key in object.keys():
			if properties.has(key):
				var found := _error(object[key], properties[key], path + "." + str(key))
				if found != "":
					return found
			elif active.get("additionalProperties", true) == false:
				return path + ": unexpected key '" + str(key) + "'"
	if json_type(value) == "array":
		var items := _as_array(value)
		if active.has("minItems") and items.size() < int(active["minItems"]):
			return path + ": expected at least " + str(int(active["minItems"])) + " items, got " + str(items.size())
		if active.has("maxItems") and items.size() > int(active["maxItems"]):
			return path + ": expected at most " + str(int(active["maxItems"])) + " items, got " + str(items.size())
		if active.has("items"):
			for index in range(items.size()):
				var found := _error(items[index], active["items"], path + "[" + str(index) + "]")
				if found != "":
					return found
	return ""


## A copy of value with every missing object property that declares a `default`
## filled in, recursively (the same rule as hsltools/schema/validate.py apply_defaults).
static func apply_defaults(value: Variant, active: Dictionary) -> Variant:
	if not value is Dictionary or active.get("type") != "object":
		return value
	var result: Dictionary = (value as Dictionary).duplicate()
	var properties: Dictionary = active.get("properties", {})
	for key in properties:
		var subschema: Dictionary = properties[key]
		if not result.has(key) and subschema.has("default"):
			result[key] = subschema["default"].duplicate(true) if subschema["default"] is Dictionary or subschema["default"] is Array else subschema["default"]
		if result.has(key):
			result[key] = apply_defaults(result[key], subschema)
	return result


## The tier a unit declares for one ledger, `authored` when it declares none.
static func evidence_tier(unit: Dictionary, ledger: String) -> String:
	return str(unit.get(ledger + "_evidence_tier", AUTHORED_TIER))


## First violation across a roster, prefixed with the unit id: "units[<id>].<path>: <reason>".
static func roster_error(units: Array, target: Dictionary = {}) -> String:
	for index in range(units.size()):
		var unit: Variant = units[index]
		var label := "units[" + (str(unit.get("id", index)) if unit is Dictionary else str(index)) + "]"
		var found := input_error(unit, target, label)
		if found != "":
			return found
	return ""

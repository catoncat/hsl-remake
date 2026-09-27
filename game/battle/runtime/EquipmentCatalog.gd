extends RefCounted
## Immutable generated source data, separate from the mutable equipped codes.
## provenance:
##   rules: resource-derived content/generated/hsl/equipment/items.json
const PATH := preload("res://game/sim/ContentPaths.gd").EQUIPMENT_ITEMS
static var _items: Dictionary = {}


static func items() -> Dictionary:
	if _items.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary or parsed.get("schema", "") != "hsl_equipment_items.v1" or not parsed.get("items") is Dictionary:
			push_error("Missing or invalid generated equipment catalog")
			return {}
		_items = parsed["items"]
	return _items.duplicate(true)

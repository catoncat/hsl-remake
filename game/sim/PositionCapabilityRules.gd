extends RefCounted
## Current source/equipment capability proposals. No cached actor or map state.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_position_equipment.md
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")


static func equipment(actor: Dictionary, catalog: Dictionary) -> Dictionary:
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_position_equipment"}
	var result := {"move_magic_use": false, "add_attack_range": false}
	for slot in actor["equipment"]:
		if not slot is Dictionary or SkillResourceRules._integer(slot.get("item_code")) <= 0:
			return {"ok": false, "reason": "invalid_position_equipment"}
		var item: Variant = catalog.get(str(int(slot["item_code"])))
		for key in result:
			if not item is Dictionary or not item.get(key) is bool:
				return {"ok": false, "reason": "invalid_position_equipment_effect"}
			result[key] = result[key] or item[key]
	return {"ok": true, "effects": result}


static func effects(actor: Dictionary, book: Dictionary, catalog: Dictionary) -> Dictionary:
	var result := equipment(actor, catalog)
	if not result["ok"]: return result
	var source: Variant = book.get("actors", {}).get(str(actor.get("actor_id", "")))
	if not source is Dictionary or not source.get("move_magic_use") is bool:
		return {"ok": false, "reason": "missing_position_capability_source"}
	# Native source capability400 is mapped by a nonempty equipped slot.
	result["effects"]["move_magic_use"] = result["effects"]["move_magic_use"] or (source["move_magic_use"] and not actor["equipment"].is_empty())
	return result


static func cast_error(actor: Dictionary, book: Dictionary, catalog: Dictionary, channel: String, moved: bool) -> String:
	if channel != "magic": return ""
	var result := effects(actor, book, catalog)
	if not result["ok"]: return result["reason"]
	return "magic_unavailable_after_movement" if moved and not result["effects"]["move_magic_use"] else ""


static func attack_pattern(actor: Dictionary, catalog: Dictionary, patterns: Dictionary, weapons: Dictionary) -> Dictionary:
	var result := equipment(actor, catalog)
	if not result["ok"]: return result
	var code := SkillResourceRules._integer(actor.get("weapon_code"))
	var key: String = weapons.get(str(code), "")
	var pattern: Variant = patterns.get(key)
	if not pattern is Dictionary or SkillResourceRules._integer(pattern.get("index")) < 0 or not pattern.get("offsets") is Array:
		return {"ok": false, "reason": "missing_source_weapon_range"}
	if code == 0:
		if int(pattern["index"]) != 0 or not pattern["offsets"].is_empty(): return {"ok": false, "reason": "invalid_unarmed_range"}
		return {"ok": true, "index": 0, "name": key, "offsets": [], "extended": false}
	if int(pattern["index"]) == 0:
		# Source item 57 retains range0Cell: it is equipped, but has no hostile
		# normal target. Only code 0 is the unarmed state above.
		if not pattern["offsets"].is_empty(): return {"ok": false, "reason": "invalid_weapon_range"}
		return {"ok": true, "index": 0, "name": key, "offsets": [], "extended": false}
	var index := int(pattern["index"]) + (1 if result["effects"]["add_attack_range"] else 0)
	if int(actor["traversal"]["size_type"]) == 1: index = mini(20, index + 17)
	for name in patterns:
		if int(patterns[name]["index"]) == index:
			return {"ok": true, "index": index, "name": name, "offsets": patterns[name]["offsets"], "extended": result["effects"]["add_attack_range"]}
	return {"ok": false, "reason": "unsupported_extended_weapon_range"}

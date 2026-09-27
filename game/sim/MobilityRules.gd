extends RefCounted
## Source base+0x130 and equipment add_move refresh the sole live move_point.
## No path, action budget, actor position or UI cache belongs in this module.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_equipment_mobility.md
const CAP := 12
const SLOTS := ["weapon", "head", "armor", "foot", "accessory1", "accessory2"]


static func integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == int(value)


static func value(base: int, equipment_bonus: int) -> int:
	return clampi(base + equipment_bonus, 0, CAP)


static func prepare(actor: Dictionary, equipment: Dictionary) -> Dictionary:
	if not integer(actor.get("base_move_point")) or int(actor["base_move_point"]) < 0 or int(actor["base_move_point"]) > 10000:
		return {"ok": false, "reason": "invalid_base_move_point"}
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_mobility_equipment"}
	var bonus := 0
	var seen: Array = []
	for slot in actor["equipment"]:
		if not slot is Dictionary or not SLOTS.has(slot.get("slot")) or seen.has(slot["slot"]) or not integer(slot.get("item_code")) or int(slot["item_code"]) <= 0:
			return {"ok": false, "reason": "invalid_mobility_equipment"}
		seen.append(slot["slot"])
		var item: Variant = equipment.get(str(int(slot["item_code"])))
		if not item is Dictionary or not item.get("effects") is Dictionary or not integer(item["effects"].get("move_point")) or absi(int(item["effects"]["move_point"])) > 10000:
			return {"ok": false, "reason": "invalid_equipment_move_point"}
		bonus += int(item["effects"]["move_point"])
	return {"ok": true, "base": int(actor["base_move_point"]), "equipment_bonus": bonus,
		"value": value(int(actor["base_move_point"]), bonus)}


static func saved_error(actor: Dictionary, equipment: Dictionary) -> String:
	var proposed := prepare(actor, equipment)
	if not proposed["ok"]: return proposed["reason"]
	if not integer(actor.get("move_point")) or int(actor["move_point"]) != proposed["value"]:
		return "inconsistent_saved_move_point"
	return ""

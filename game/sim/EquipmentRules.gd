extends RefCounted
## Pure equipment rules. Callers supply the immutable generated item catalog.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_inventory_equipment.md
##   rules: resource-derived content/generated/hsl/roles/job_formulas.json
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const JobStatsRules = preload("res://game/sim/JobStatsRules.gd")
const SLOTS := ["weapon", "head", "armor", "foot", "accessory1", "accessory2"]
const TYPES := [2, 3, 4, 5, 6, 6]


static func equipped_code(equipment: Array, slot: String) -> int:
	for entry in equipment:
		if entry["slot"] == slot:
			return int(entry["item_code"])
	return 0


static func effect_delta(equipment: Array, catalog: Dictionary) -> Dictionary:
	var delta := {"attack": 0, "defense": 0, "hit_rate": 0, "magic_attack": 0,
		"max_hp": 0, "max_mp": 0, "speed": 0, "move_point": 0, "avoid_hit_ratio": 0, "attack_back": 0,
		"attack_damagex2": 0, "steal_ratio": 0, "resist_by_type": {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}}
	var seen: Array = []
	var weapon := {"weapon_magic_attack_type": -1, "weapon_damage_variance_lo": 0, "weapon_damage_variance_hi": 0}
	for entry in equipment:
		if not entry is Dictionary:
			return {"ok": false, "reason": "invalid_equipment_input"}
		var slot := str(entry.get("slot", ""))
		var index := SLOTS.find(slot)
		var item: Dictionary = catalog.get(str(int(entry.get("item_code", 0))), {})
		if index < 0 or seen.has(slot) or item.is_empty() or not bool(item.get("supported", false)) or int(item["type_code"]) != TYPES[index]:
			return {"ok": false, "reason": "unsupported_equipment"}
		if not item.get("effects") is Dictionary:
			return {"ok": false, "reason": "invalid_equipment_effects"}
		seen.append(slot)
		if slot == "weapon":
			var magic: Variant = item.get("weapon_magic")
			if not magic is Dictionary: return {"ok": false, "reason": "missing_weapon_magic"}
			for key in ["element", "low", "high"]:
				if typeof(magic.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(magic[key])) or magic[key] != int(magic[key]):
					return {"ok": false, "reason": "invalid_weapon_magic"}
			if int(magic["element"]) < -1 or int(magic["element"]) > 5 or mini(int(magic["low"]), int(magic["high"])) < 0 or maxi(int(magic["low"]), int(magic["high"])) > 10000:
				return {"ok": false, "reason": "invalid_weapon_magic"}
			weapon = {"weapon_magic_attack_type": int(magic["element"]), "weapon_damage_variance_lo": int(magic["low"]), "weapon_damage_variance_hi": int(magic["high"])}
		for key in delta:
			if key == "resist_by_type":
				if not item["effects"].get(key) is Dictionary:
					return {"ok": false, "reason": "invalid_equipment_effects"}
				for element in delta[key]:
					if typeof(item["effects"][key].get(element)) not in [TYPE_INT, TYPE_FLOAT]:
						return {"ok": false, "reason": "invalid_equipment_effects"}
					delta[key][element] += int(item["effects"][key][element])
			else:
				if typeof(item["effects"].get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item["effects"][key])) or item["effects"][key] != int(item["effects"][key]):
					return {"ok": false, "reason": "invalid_equipment_effects"}
				delta[key] += int(item["effects"][key])
	return {"ok": true, "delta": delta, "weapon": weapon}


static func replace(unit: Dictionary, slot: String, inventory_index: int, expected_code: int, catalog: Dictionary) -> Dictionary:
	var index := SLOTS.find(slot)
	if index < 0 or not InventoryRules.valid(unit.get("inventory")) or not unit.get("equipment") is Array:
		return {"ok": false, "reason": "invalid_equipment_input"}
	var equipment: Array = unit["equipment"]
	var previous_effects := effect_delta(equipment, catalog)
	if not previous_effects["ok"]:
		return previous_effects
	var old_code := equipped_code(equipment, slot)
	var old: Dictionary = catalog.get(str(old_code), {})
	if old_code > 0 and (old.is_empty() or bool(old["unequip_blocked"])):
		return {"ok": false, "reason": "equipment_cannot_be_removed"}
	if expected_code == old_code:
		return {"ok": false, "reason": "equipment_unchanged"}
	var bag: Array = unit["inventory"].duplicate()
	var item: Dictionary = {}
	if expected_code > 0:
		item = catalog.get(str(expected_code), {})
		if item.is_empty() or not bool(item.get("supported", false)):
			return {"ok": false, "reason": "unsupported_equipment"}
		var job := int(unit.get("growth_profile", {}).get("job_code", -1))
		if job != 1000 and (not JobStatsRules.has_job(job) or (int(item["job_mask"]) & JobStatsRules.job_mask_bit(job)) == 0):
			return {"ok": false, "reason": "wrong_job"}
		if int(item["type_code"]) != TYPES[index]:
			return {"ok": false, "reason": "wrong_equipment_slot"}
		var removed := InventoryRules.remove(bag, inventory_index, expected_code)
		if not removed["ok"]:
			return removed
		bag = removed["inventory"]
	elif expected_code < 0 or inventory_index != -1:
		return {"ok": false, "reason": "invalid_equipment_input"}
	if old_code > 0:
		var returned := InventoryRules.insert(bag, old_code)
		if not returned["ok"]:
			return returned
		bag = returned["inventory"]
	var next_equipment: Array = []
	for entry in equipment:
		if entry["slot"] != slot:
			next_equipment.append(entry.duplicate(true))
	if expected_code > 0:
		next_equipment.append({"slot": slot, "item_code": expected_code, "name": item["name"]})
	# Always emit the native six-slot order; list order cannot change effect order.
	next_equipment.sort_custom(func(a, b): return SLOTS.find(a["slot"]) < SLOTS.find(b["slot"]))
	var effects := effect_delta(next_equipment, catalog)
	if not effects["ok"]:
		return effects
	return {"ok": true, "inventory": bag, "equipment": next_equipment, "old_item_code": old_code}

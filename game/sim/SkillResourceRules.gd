extends RefCounted
## Original costs/gates: 0x409980 / 0x409040 and 0x409890 / 0x408fe0.
## One read-only quote serves availability and actual MP/ST debit.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_resources.md
const Values = preload("res://game/sim/Values.gd")
const ST_PER_EXPEND := 20
const MAX_SIGNED := 2147483647


static func amounts(channel: String, expend: Variant, half_mp: bool = false) -> Dictionary:
	var raw := Values.non_negative_int(expend, true)
	if raw < 0 or channel not in ["special", "magic"] or (channel == "special" and raw > MAX_SIGNED / ST_PER_EXPEND):
		return {"ok": false, "reason": "invalid_skill_cost"}
	var cost := raw * ST_PER_EXPEND if channel == "special" else raw
	var required := cost
	if channel == "magic" and half_mp:
		required = cost / 2
		cost = maxi(1, required)
	return {"ok": true, "resource": "stamina" if channel == "special" else "mp",
		"amount": cost, "native_required": required}


static func quote(unit: Dictionary, fields: Dictionary, channel: String, catalog: Dictionary) -> Dictionary:
	var half_mp := false
	if channel == "magic":
		if not unit.get("equipment") is Array:
			return {"ok": false, "reason": "missing_cost_equipment"}
		for entry in unit["equipment"]:
			if not entry is Dictionary or Values.non_negative_int(entry.get("item_code")) <= 0:
				return {"ok": false, "reason": "invalid_cost_equipment"}
			var item: Variant = catalog.get(str(int(entry["item_code"])))
			if not item is Dictionary or not item.get("mp_use_half") is bool:
				return {"ok": false, "reason": "missing_magic_cost_modifier"}
			half_mp = half_mp or item["mp_use_half"]
	var result := amounts(channel, fields.get("expend"), half_mp)
	if not result["ok"]:
		return result
	var available := Values.non_negative_int(unit.get(result["resource"]))
	if available < 0:
		return {"ok": false, "reason": "invalid_" + result["resource"]}
	result["before"] = available
	result["after"] = available - int(result["amount"])
	result["native_affordable"] = available >= int(result["native_required"])
	# Native half-MP gate can accept zero while its debit still costs one.
	# Keep that discrepancy visible, but never commit a negative product resource.
	if result["after"] < 0:
		result["ok"] = false
		result["reason"] = "insufficient_" + result["resource"]
	return result

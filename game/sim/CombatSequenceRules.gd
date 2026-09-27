extends RefCounted
## Source double_attack affects one ordinary attack/counter series, not turns.
## Receipt traversal is shared by playback, death handling and reward settlement.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_extra_attack.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Number = preload("res://game/sim/SkillResourceRules.gd")


static func attack_count(actor: Dictionary, source: Dictionary, equipment: Dictionary) -> Dictionary:
	if not source.get("double_attack") is bool or not actor.get("equipment") is Array:
		return {"ok": false, "reason": "missing_extra_attack_source"}
	var enabled := false
	for slot in actor["equipment"]:
		if not slot is Dictionary or Number._integer(slot.get("item_code")) <= 0:
			return {"ok": false, "reason": "invalid_extra_attack_equipment"}
		var item: Variant = equipment.get(str(int(slot["item_code"])))
		if not item is Dictionary or not item.get("double_attack") is bool:
			return {"ok": false, "reason": "missing_extra_attack_equipment_effect"}
		enabled = enabled or item["double_attack"]
	# Native innate capability0x200 maps into effect0x8000 when applying a
	# nonempty equipment slot. Duplicate sources OR together, never add strikes.
	enabled = enabled or (source["double_attack"] and not actor["equipment"].is_empty())
	return {"ok": true, "count": 2 if enabled else 1, "effect_flags": 0x8000 if enabled else 0}


static func participant_strikes(receipt: Dictionary) -> Array:
	var result: Array = [receipt]
	result.append_array(receipt.get("followups", []))
	return result


static func strikes(receipt: Dictionary) -> Array:
	var result := participant_strikes(receipt)
	if not receipt.get("counter", {}).is_empty(): result.append_array(participant_strikes(receipt["counter"]))
	return result


static func participant_outcomes(receipt: Dictionary) -> Array:
	if receipt.has("special_segments"): return receipt["special_segments"]
	var result: Array = []
	for strike in participant_strikes(receipt): result.append_array(strike.get("affected_targets", [strike]))
	return result


static func outcomes(receipt: Dictionary) -> Array:
	var result := participant_outcomes(receipt)
	if not receipt.get("counter", {}).is_empty(): result.append_array(participant_outcomes(receipt["counter"]))
	return result

extends RefCounted
## Native ally scan order/continuation and aid-check suffix. Live adapters filter
## unavailable actors and unsupported effects before committing an action.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_support.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_stat_magic.md
const AIPriorityRules = preload("res://game/sim/AIPriorityRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const Values = preload("res://game/sim/Values.gd")
const SEARCH_RADIUS := 8


static func profile_error(profile: Dictionary, include_buffs: bool = false) -> String:
	for key in (["ai_help_otherhp", "ai_help_status", "ai_help_attack"] if include_buffs else ["ai_help_otherhp", "ai_help_status"]):
		var value := Values.non_negative_int(profile.get(key))
		if value < 0 or value > 100: return "invalid_ai_support_" + key
	return ""


static func next_check(profile: Dictionary, attempted: int, roll: int, rng: Variant, include_buffs: bool = false) -> Dictionary:
	var draws: Array = []
	var mode := 0
	for flag in ([4, 8, 16] if include_buffs else [4, 8]):
		if attempted & flag: continue
		attempted |= flag
		if roll <= int(profile[{4: "ai_help_otherhp", 8: "ai_help_status", 16: "ai_help_attack"}[flag]]):
			mode = {4: 3, 8: 4, 16: 6}[flag]
			break
		roll = AIDecisionRules.recorded_draw(99, rng, draws) + 1
	return {"mode": mode, "attempted": attempted, "next_roll": roll, "draws": draws,
		"source": "0x440e3d..0x440ef1" if include_buffs else "0x440e3d..0x440eb5"}


static func scan(rows: Array, owner_index: int, kind: String, cursor: int, radius: int, rng: Variant, buff_masks: Array = []) -> Dictionary:
	var draws: Array = []
	var evaluated: Array = []
	var owner: Dictionary = rows[owner_index]
	for index in range(cursor, rows.size()):
		var row: Variant = rows[index]
		if row == null or index == owner_index: continue
		if (int(row["side"]) & 0x870000) != (int(owner["side"]) & 0x870000): continue
		if not AIPriorityRules.within_square(row["coord"], owner["coord"], radius): continue
		var needed := false
		var mask := int(row["status_flags"]) & StatusEffectRules.AFFLICTION_MASK
		if kind == "heal":
			var health := AIPriorityRules.self_recovery(row, rng)
			draws.append_array(health["draws"])
			evaluated.append({"index": index, "threshold": health["threshold"]})
			needed = health["needed"]
		elif kind == "buff":
			mask = int(row["status_flags"]) & 0x70
			needed = buff_useful(buff_masks, mask)
		else:
			needed = mask != 0
		if needed:
			return {"index": index, "next_cursor": index + 1, "mask": mask,
				"draws": draws, "evaluated": evaluated}
	return {"index": -1, "next_cursor": rows.size(), "mask": 0, "draws": draws, "evaluated": evaluated}


static func buff_useful(function_masks: Array, present_flags: int) -> bool:
	# Full original 0x40dcf0 return: select a buff with no matching live flag.
	# This is deliberately stricter than the player's legal duration refresh.
	for value in function_masks:
		var mask := int(value)
		var flag := (0x10 if mask & 0x40 else 0) | (0x20 if mask & 0x20 else 0) | (0x40 if mask & 0x100 else 0)
		if flag != 0 and (flag & present_flags) == 0: return true
	return false

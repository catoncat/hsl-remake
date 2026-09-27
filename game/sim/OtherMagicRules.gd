extends RefCounted
## magicOTHER damage magic (滅／裁): original 0x40a7b0 channel0/proc0 where the
## resistance switch on the record type has no case 5 (0x40aa64 default), so no
## resist_by_type slot is read. Hit equipment, level/mind/magic-attack terms and
## the capped HP application are the shared native magic path.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_special_element.md; static-derived docs/evidence_packets/static_reverse/original_magic_damage.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const StatusApplication = preload("res://game/sim/StatusApplicationRules.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const Target = preload("res://game/sim/SkillTargetRules.gd")
const Costs = preload("res://game/sim/SkillResourceRules.gd")


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary) -> Dictionary:
	if fields.get("type") != "magicOTHER": return {"ok": false, "reason": "unsupported_other_magic_type"}
	var error := Status.input_error(target)
	if error != "": return {"ok": false, "reason": error}
	var attacker_mods := StatusApplication.modifiers(caster, book, equipment)
	if not attacker_mods["ok"]: return attacker_mods
	var defender_mods := StatusApplication.modifiers(target, book, equipment)
	if not defender_mods["ok"]: return defender_mods
	var profile: Variant = caster.get("combat_profile")
	if not profile is Dictionary or not target.get("combat_profile") is Dictionary:
		return {"ok": false, "reason": "missing_status_skill_profile"}
	for value in [caster.get("level"), caster.get("hit_bonus_accum"), profile.get("mind"), profile.get("live_magic_attack")]:
		if Costs._integer(value) < 0 or int(value) > 100000:
			return {"ok": false, "reason": "invalid_status_skill_profile"}
	if Target.function_mask(fields.get("function"), targeting["function_bits"]) != 1: return {"ok": false, "reason": "unsupported_status_skill"}
	var hit_rate := Costs._integer(fields.get("hit_ratio"), true)
	var bounds: PackedStringArray = str(fields.get("damage", "")).split(",")
	if bounds.size() != 2 or hit_rate < 0 or hit_rate > 100:
		return {"ok": false, "reason": "invalid_status_skill_definition"}
	var low := Costs._integer(bounds[0].strip_edges(), true)
	var high := Costs._integer(bounds[1].strip_edges(), true)
	if low < 0 or high < low or high > 10000:
		return {"ok": false, "reason": "invalid_status_skill_definition"}
	# Same shape StatusApplicationRules.resolve consumes; resistance 0 is the
	# type-5 default path, not a missing-data fallback.
	return {"ok": true, "function_mask": 1, "immunities": defender_mods["effects"],
		"roll_input": {"low": low, "high": high, "hit_ratio": hit_rate, "status_hit_ratio": 0,
			"proc": 0, "level": int(caster["level"]), "mind": int(Status.weakened_attributes(caster)["mind"]), "magic_attack": int(profile["live_magic_attack"]),
			"hit_bonus": int(caster["hit_bonus_accum"]), "magic_hit_bonus": attacker_mods["magic_hit_bonus"],
			"no_attack": defender_mods["no_attack"], "resistance": 0, "element": "5"}}

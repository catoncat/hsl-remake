extends RefCounted
## Source specials: original 0x40a7b0 channel1/proc0 and capped HP application.
## Defense, magic power and magic-hit equipment never enter special damage. Only
## the target's resist_by_type[type] does, for SPECIAL types 0..4 (magicEARTH..
## magicMIND); magicOTHER (type 5) and magicOTHER2 (type 6, the enemy "2" rows) are above
## the switch bound (0x40a9f3 cmp eax,4 / ja 0x40aa64) and multiply nothing.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_special_element.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_ordinary_special.md
const ELEMENTS := {"magicEARTH": "0", "magicWATER": "1", "magicAIR": "2", "magicFIRE": "3", "magicMIND": "4", "magicOTHER": "5", "magicOTHER2": "6"}
const NO_RESIST_ELEMENTS := ["5", "6"]
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const Values = preload("res://game/sim/Values.gd")


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, equipment: Dictionary) -> Dictionary:
	var profile: Variant = caster.get("combat_profile")
	if not profile is Dictionary: return {"ok": false, "reason": "missing_special_profile"}
	for key in ["dex", "mind", "con"]:
		var value := Values.non_negative_int(profile.get(key))
		if value < 0 or value > 10000: return {"ok": false, "reason": "invalid_special_" + key}
	for key in ["level", "hit_bonus_accum"]:
		var value := Values.non_negative_int(caster.get(key))
		if value < 0 or value > 100000: return {"ok": false, "reason": "invalid_special_" + key}
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return {"ok": false, "reason": "invalid_special_power_ratio"}
	var modifiers := StatusApplicationRules.modifiers(target, book, equipment)
	if not modifiers["ok"]: return modifiers
	var limits: PackedStringArray = fields["damage"].split(",")
	if int(limits[1]) > 10000: return {"ok": false, "reason": "invalid_special_damage"}
	var resistance := element_resistance(target, fields)
	if not resistance["ok"]: return resistance
	# 0x40a7b0 channel1 reads live +0x50 dex / +0x54 mind / +0x58 con (0x448840: base minus active 衰弱).
	var live := StatusEffectRules.weakened_attributes(caster)
	return {"ok": true, "input": {"low": int(limits[0]), "high": int(limits[1]),
		"hit_ratio": int(fields["hit_ratio"]), "hit_bonus": int(caster["hit_bonus_accum"]),
		"attackpow_ratio": scale, "level": int(caster["level"]), "dex": int(live["dex"]),
		"mind": int(live["mind"]), "con": int(live["con"]), "no_attack": modifiers["no_attack"],
		"element": resistance["element"], "resistance": resistance["resistance"]}}


## Target resistance read by the proc0 switch: SPECIAL type 0..4 indexes
## resist_by_type; type 5 (magicOTHER) is the switch default and multiplies nothing.
static func element_resistance(target: Dictionary, fields: Dictionary) -> Dictionary:
	var element: String = ELEMENTS.get(fields.get("type"), "")
	if element == "": return {"ok": false, "reason": "unsupported_special_element"}
	if element in NO_RESIST_ELEMENTS: return {"ok": true, "element": element, "resistance": 0}
	var profile: Variant = target.get("combat_profile")
	var resists: Variant = profile.get("resist_by_type") if profile is Dictionary else null
	if not resists is Dictionary or Values.non_negative_int(resists.get(element)) < 0 or int(resists[element]) > 80:
		return {"ok": false, "reason": "missing_skill_resistance"}
	return {"ok": true, "element": element, "resistance": int(resists[element])}


static func roll(input: Dictionary, rng: Variant) -> Dictionary:
	var hit_rate := int(input["hit_ratio"]) + int(input["hit_bonus"])
	var draw := CoreCombatRules.native_draw(100, rng) + 1
	if not bool(input["no_attack"]) and draw > hit_rate:
		return {"value": 0, "hit_bonus_after": int(input["hit_bonus"]) + draw / 10,
			"hit_check_passed": false, "hit_rate": hit_rate, "hit_roll": draw}
	var half := absi(int(input["high"]) - int(input["low"])) / 2
	var sampled := maxi(int(input["low"]), int(input["low"]) + half - CoreCombatRules.native_draw(half + 1, rng) + CoreCombatRules.native_draw(half + 1, rng))
	var level := clampi(int(input["level"]), 1, 120)
	var value := sampled + CoreCombatRules.native_draw(level * 180 / 100, rng) + CoreCombatRules.native_draw(level * 150 / 100, rng)
	value += int(input["con"]) / 8 + int(input["mind"]) / 4 + int(input["dex"]) / 3
	value = value * int(input["attackpow_ratio"]) / 100
	if value < 3: value += 3 * ((5 - value) / 3)
	if str(int(input.get("element", 5))) not in NO_RESIST_ELEMENTS and int(input.get("resistance", 0)) != 0:
		value = (100 - mini(80, int(input["resistance"]))) * value / 100
	return {"value": value, "sampled": sampled, "hit_bonus_after": 0,
		"hit_check_passed": true, "hit_rate": hit_rate, "hit_roll": draw}

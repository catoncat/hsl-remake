extends RefCounted
## Original poison/paralysis/no-magic lifecycle; explicit serialized counters.
## Sources: original_status_effects.md and original_status_application.md.
## Receives sampled applications; it does not decide hit chance or consume RNG.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_effects.md; static-derived docs/evidence_packets/static_reverse/original_status_application.md; static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const POISON := 1
const NO_MAGIC := 2
const PARALYSIS := 4
## 衰弱 (magicFun_Weaken): 0x40aa80 bit 0x1000 sets actor flag 8, duration word +0x38
## (low 16) and power +0x3a (high 16); 0x448840 subtracts power from the four live
## attributes (floor 1) before the job refresh; 0x40b910 expires it with a refresh.
## The counter key is optional: absent means never weakened (like enhancements).
const WEAKEN := 8
const WEAKEN_KEY := "weaken"
const COUNTERS := {"poison": POISON, "paralysis": PARALYSIS, "no_magic": NO_MAGIC}
const ALL_FLAGS := {"poison": POISON, "paralysis": PARALYSIS, "no_magic": NO_MAGIC, "weaken": WEAKEN}
const Enhancements = preload("res://game/sim/StatEnhancementRules.gd")


static func _unsigned(value: Variant, maximum: int = 0xffffffff) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= maximum and value == int(value)


static func input_error(unit: Dictionary) -> String:
	if not _unsigned(unit.get("status_flags")) or not unit.get("status_counters") is Dictionary:
		return "missing_status_state"
	for key in COUNTERS:
		var word: Variant = unit["status_counters"].get(key)
		if not _unsigned(word):
			return "invalid_status_counter"
		# The live subset accepts coherent afflictions. Native inconsistent/negative
		# counter states are documented separately, not silently normalized here.
		if ((int(unit["status_flags"]) & COUNTERS[key]) != 0) != (int(word) != 0):
			return "inconsistent_status_state"
		if int(word) != 0 and (int(word) & 0xffff) not in range(1, 10):
			return "unsupported_status_duration"
		if key == "paralysis" and int(word) > 9:
			return "unsupported_paralysis_counter"
	var weaken_error := weaken_input_error(unit)
	if weaken_error != "": return weaken_error
	return Enhancements.input_error(unit)


static func weaken_input_error(unit: Dictionary) -> String:
	var word: Variant = unit["status_counters"].get(WEAKEN_KEY, 0)
	if not _unsigned(word): return "invalid_status_counter"
	if ((int(unit["status_flags"]) & WEAKEN) != 0) != (int(word) != 0): return "inconsistent_status_state"
	if int(word) != 0 and ((int(word) & 0xffff) not in range(1, 10) or (int(word) >> 16) < 2 or (int(word) >> 16) > 15):
		return "unsupported_weaken_word"
	return ""


static func weakened(unit: Dictionary) -> bool:
	return (int(unit["status_flags"]) & WEAKEN) != 0


static func weaken_power(unit: Dictionary) -> int:
	return int(unit.get("status_counters", {}).get(WEAKEN_KEY, 0)) >> 16


## 0x40aa80 Weaken magnitude folding: >15 wraps into 13..15, <2 lifts to 2..3.
static func weaken_strength(value: int) -> int:
	if value > 15: value -= 3 * ((value - 13) / 3)
	if value < 2: value += (3 - value) & ~1
	return value


static func apply_weaken(unit: Dictionary, turns: int, power: int) -> Dictionary:
	var error := input_error(unit)
	if error != "": return {"ok": false, "reason": error}
	if turns not in range(2, 4) or power < 2 or power > 15:
		return {"ok": false, "reason": "invalid_status_application"}
	if not _unsigned(unit.get("hp"), 0x7fffffff) or int(unit["hp"]) == 0 or bool(unit.get("defeated", false)):
		return {"ok": false, "reason": "status_actor_unavailable"}
	return _merge_application(unit, WEAKEN_KEY, turns, power)


## 0x448840 prologue: live str/dex/mind/con = base minus weaken power, floored to 1.
static func weakened_attributes(unit: Dictionary) -> Dictionary:
	var attributes: Dictionary = unit["combat_profile"].duplicate(true)
	var power := weaken_power(unit)
	if power > 0 and (int(unit.get("status_flags", 0)) & WEAKEN) != 0:
		for key in ["str", "dex", "mind", "con"]:
			attributes[key] = maxi(1, int(attributes[key]) - power)
	return attributes


static func cure_weaken(unit: Dictionary) -> Dictionary:
	# 0x40aa80 bit 0x2000: clear +0x38 word and flag 8, then 0x448840 refresh (caller).
	var words: Dictionary = unit["status_counters"].duplicate(true)
	words.erase(WEAKEN_KEY)
	return {"status_flags": int(unit["status_flags"]) & ~WEAKEN, "status_counters": words}


static func magic_blocked(unit: Dictionary) -> bool:
	return (int(unit["status_flags"]) & NO_MAGIC) != 0


static func poisoned(unit: Dictionary) -> bool:
	return (int(unit["status_flags"]) & POISON) != 0


static func paralyzed(unit: Dictionary) -> bool:
	return (int(unit["status_flags"]) & PARALYSIS) != 0


static func apply(unit: Dictionary, key: String, turns: int, power: int = 0) -> Dictionary:
	var error := input_error(unit)
	if error != "": return {"ok": false, "reason": error}
	if key not in COUNTERS or turns not in range(2, 4) or power < 0 or power > 65535 or (key != "poison" and power != 0):
		return {"ok": false, "reason": "invalid_status_application"}
	if not _unsigned(unit.get("hp"), 0x7fffffff) or int(unit["hp"]) == 0 or bool(unit.get("defeated", false)):
		return {"ok": false, "reason": "status_actor_unavailable"}
	return _merge_application(unit, key, turns, power)


## 0x409310 status helpers 0x4091b0 (poison) / 0x409240 (weaken) / 0x409210 (no_magic) / 0x409110
## (paralysis): flag |= bit, turns += rand(2)+1 capped at 9, power from 0x406fe0 (16..32 poison,
## 3..7 weaken; none for no_magic / paralysis) merged as max(old, (old+new)/2). They run after a
## lethal hit too; PlayLoop consumes the draws before clearing death.
const WEAPON_POWER_DOMAIN := {"poison": [16, 32], "weaken": [3, 7], "no_magic": [0, 0], "paralysis": [0, 0]}


static func weapon_status(unit: Dictionary, key: String, turns: int, power: int) -> Dictionary:
	var error := input_error(unit)
	if error != "": return {"ok": false, "reason": error}
	if not WEAPON_POWER_DOMAIN.has(key) or turns not in [1, 2] or power < int(WEAPON_POWER_DOMAIN[key][0]) or power > int(WEAPON_POWER_DOMAIN[key][1]):
		return {"ok": false, "reason": "invalid_weapon_%s_application" % key}
	return _merge_application(unit, key, turns, power)


static func _merge_application(unit: Dictionary, key: String, turns: int, power: int) -> Dictionary:
	var words: Dictionary = unit["status_counters"].duplicate(true)
	var previous := int(words.get(key, 0))
	var old_power := previous >> 16
	var combined := power if old_power == 0 else maxi(old_power, (old_power + power) / 2)
	words[key] = (combined << 16) | mini(9, (previous & 0xffff) + turns)
	return {"ok": true, "changes": {"status_flags": int(unit["status_flags"]) | int(ALL_FLAGS[key]), "status_counters": words},
		"before_word": previous, "after_word": words[key]}


static func cure_poison(unit: Dictionary) -> Dictionary:
	# ITEM cure_poison -> bit31 -> 0x40a2ed: clear flag1 AND the packed DWORD.
	var words: Dictionary = unit["status_counters"].duplicate(true)
	words["poison"] = 0
	return {"status_flags": int(unit["status_flags"]) & ~POISON,
		"status_counters": words}


static func cure_paralysis(unit: Dictionary) -> Dictionary:
	# Original item20000000 clears +3c and flag4; unrelated conditions remain.
	var words: Dictionary = unit["status_counters"].duplicate(true)
	words["paralysis"] = 0
	return {"status_flags": int(unit["status_flags"]) & ~PARALYSIS, "status_counters": words}


static func cure_no_magic(unit: Dictionary) -> Dictionary:
	# Item40000000 at40a2f9..40a30c clears only this complete word and flag.
	var words: Dictionary = unit["status_counters"].duplicate(true)
	words["no_magic"] = 0
	return {"status_flags": int(unit["status_flags"]) & ~NO_MAGIC, "status_counters": words}


static func after_action(unit: Dictionary) -> Dictionary:
	var error := input_error(unit)
	if error != "":
		return {"ok": false, "reason": error}
	if not _unsigned(unit.get("hp"), 0x7fffffff) or int(unit["hp"]) <= 0 or bool(unit.get("defeated", false)):
		return {"ok": false, "reason": "status_actor_unavailable"}
	var hp := int(unit["hp"])
	var flags := int(unit["status_flags"])
	var words: Dictionary = unit["status_counters"].duplicate(true)
	var damage := 0
	if (flags & POISON) != 0:
		damage = mini(hp - 1, int(words["poison"]) >> 16)
		hp -= damage
	var expired: Array[String] = []
	for key in COUNTERS:
		var word := int(words[key])
		if word == 0:
			continue
		var remaining := (word & 0xffff) - 1
		words[key] = (word & 0xffff0000) | remaining if remaining > 0 else 0
		if remaining <= 0:
			flags &= ~int(COUNTERS[key])
			expired.append(key)
	var weaken := int(words.get(WEAKEN_KEY, 0))
	if weaken != 0:
		# 0x40b910: low word decrements; expiry clears the word and flag 8 and refreshes.
		var remaining := (weaken & 0xffff) - 1
		if remaining > 0: words[WEAKEN_KEY] = (weaken & 0xffff0000) | remaining
		else:
			words.erase(WEAKEN_KEY)
			flags &= ~WEAKEN
			expired.append(WEAKEN_KEY)
	var enhancements := Enhancements.after_action(flags, words)
	flags = enhancements["flags"]
	words = enhancements["words"]
	expired.append_array(enhancements["expired"])
	return {"ok": true, "changes": {"hp": hp, "status_flags": flags, "status_counters": words},
		"poison_damage": damage, "expired": expired}

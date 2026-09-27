extends RefCounted
## Pure proposals for the reviewed heal / cure / HealMP branches of 0x40aa80.
## No spending, target selection, XP distribution or presentation occurs here.
## Channel1 (special) casts use the 0x40a7b0 channel1 helper (SpecialDamageRules.roll).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_support_magic.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Status = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplication = preload("res://game/sim/StatusApplicationRules.gd")
const Rolls = preload("res://game/sim/NativeMagicRollRules.gd")
const Special = preload("res://game/sim/SpecialDamageRules.gd")
const Progression = preload("res://game/sim/ProgressionRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
const Costs = preload("res://game/sim/SkillResourceRules.gd")
const Targets = preload("res://game/sim/SkillTargetRules.gd")
const HEAL := 2
const HEAL_MP := 0x8000
## 0x40aa80 visit order after the buff/dispel branches: CureWeaken, CureParalysis, CurePoison, CureNoMagic.
const CURE_BITS := {0x2000: "weaken", 0x200: "paralysis", 0x400: "poison", 0x800: "no_magic"}
const SUPPORT_MASK := HEAL | HEAL_MP | 0x2000 | 0x200 | 0x400 | 0x800


static func accepted(mask: int) -> bool:
	return mask > 0 and (mask & ~SUPPORT_MASK) == 0


static func afflicted(unit: Dictionary, key: String) -> bool:
	return (int(unit["status_flags"]) & int(Status.ALL_FLAGS[key])) != 0


## Any status this cure mask would actually remove from the unit.
static func cures_something(unit: Dictionary, mask: int) -> bool:
	for bit in CURE_BITS:
		if (mask & bit) != 0 and afflicted(unit, CURE_BITS[bit]): return true
	return false


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, channel: String = "magic") -> Dictionary:
	var error := Status.input_error(target)
	if error != "": return {"ok": false, "reason": error}
	var maximum := Costs._integer(target.get("max_hp"))
	if maximum <= 0 or maximum > 1000000 or Costs._integer(target.get("hp")) > maximum:
		return {"ok": false, "reason": "invalid_support_hp"}
	var mask := Targets.function_mask(fields.get("function"), targeting["function_bits"])
	if not accepted(mask): return {"ok": false, "reason": "unsupported_support_skill"}
	var useful := cures_something(target, mask)
	if (mask & 0x2000) != 0 and afflicted(target, "weaken"):
		# CureWeaken ends in 0x448840; the target must be refreshable before any RNG.
		var refresh_error := Progression.refresh_input_error(target, equipment)
		if refresh_error != "": return {"ok": false, "reason": refresh_error}
	var prepared := {"ok": true, "function_mask": mask, "channel": channel}
	if (mask & HEAL) != 0: useful = useful or int(target["hp"]) < maximum
	if (mask & HEAL_MP) != 0:
		var max_mp := Costs._integer(target.get("max_mp"))
		if max_mp < 0 or max_mp > 1000000 or Costs._integer(target.get("mp")) < 0 or int(target["mp"]) > max_mp:
			return {"ok": false, "reason": "invalid_support_mp"}
		useful = useful or int(target["mp"]) < max_mp
	prepared["useful"] = useful
	if (mask & (HEAL | HEAL_MP)) == 0: return prepared
	var caster_mods := StatusApplication.modifiers(caster, book, equipment)
	if not caster_mods["ok"]: return caster_mods
	var target_mods := StatusApplication.modifiers(target, book, equipment)
	if not target_mods["ok"]: return target_mods
	var profile: Variant = caster.get("combat_profile")
	if not profile is Dictionary: return {"ok": false, "reason": "missing_support_profile"}
	for value in [caster.get("level"), caster.get("hit_bonus_accum"), profile.get("mind"), profile.get("live_magic_attack")]:
		if Costs._integer(value) < 0 or int(value) > 100000: return {"ok": false, "reason": "invalid_support_profile"}
	var bounds: PackedStringArray = str(fields["damage"]).split(",")
	if int(bounds[1]) > 10000: return {"ok": false, "reason": "invalid_support_damage"}
	prepared["roll_input"] = {"proc": 1, "low": int(bounds[0]), "high": int(bounds[1]), "hit_ratio": int(fields["hit_ratio"]),
		"status_hit_ratio": 0, "level": int(caster["level"]), "mind": int(Status.weakened_attributes(caster)["mind"]),
		"magic_attack": int(profile["live_magic_attack"]), "hit_bonus": int(caster["hit_bonus_accum"]),
		"magic_hit_bonus": caster_mods["magic_hit_bonus"], "no_attack": target_mods["no_attack"], "resistance": 0}
	if channel == "special":
		# proc1 on channel1: hit_ratio + compensation, level/dex/con/mind terms, attackpow_ratio, no resistance.
		var special := Special.prepare(caster, target, fields, book, equipment)
		if not special["ok"]: return special
		prepared["roll_input"].merge(special["input"], true)
	return prepared


static func _roll(prepared: Dictionary, input: Dictionary, rng: Variant) -> Dictionary:
	return Special.roll(input, rng) if prepared.get("channel", "magic") == "special" else Rolls.roll(input, rng)


static func resolve(prepared: Dictionary, target: Dictionary, hit_bonus: int, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	var changes := {"hp": target["hp"], "defeated": false}
	var mask := int(prepared["function_mask"])
	var healing := 0
	var effects: Array = []
	var contribution := 0
	var immediate: Array = []
	if (mask & HEAL) != 0:
		var input: Dictionary = prepared["roll_input"].duplicate(true)
		input["hit_bonus"] = hit_bonus
		var value := _roll(prepared, input, rng)
		hit_bonus = value["hit_bonus_after"]
		healing = mini(int(target["max_hp"]) - int(target["hp"]), int(value["value"]))
		changes["hp"] = int(target["hp"]) + healing
		contribution = healing / 2
	var after := target.duplicate(true)
	var refresh_needed := false
	for bit in CURE_BITS:
		if (mask & bit) == 0: continue
		var key: String = CURE_BITS[bit]
		var before_word := int(after["status_counters"].get(key, 0))
		var removed := afflicted(after, key)
		if removed:
			# Native cure branches clear the whole packed word and its flag, nothing else.
			match key:
				"weaken":
					after.merge(Status.cure_weaken(after), true)
					refresh_needed = true
				"paralysis": after.merge(Status.cure_paralysis(after), true)
				"poison": after.merge(Status.cure_poison(after), true)
				"no_magic": after.merge(Status.cure_no_magic(after), true)
			contribution += ((before_word & 0xffff) + 1) * 12
		effects.append({"status": key, "removed": removed, "before_word": before_word, "after_word": 0})
	if not effects.is_empty():
		changes["status_flags"] = after["status_flags"]
		changes["status_counters"] = after["status_counters"]
	if refresh_needed:
		# 0x40b3c4 -> 0x448840: derived stats return to the unweakened attributes. Vitals stay
		# the caller's (a self-cast target must not overwrite its committed payment).
		var refreshed := Progression.refresh_growth_stats(after, equipment)
		for key in ["combat_profile", "max_hp", "max_mp", "live_speed", "move_point"]:
			changes[key] = refreshed[key]
	var restored_mp := 0
	if (mask & HEAL_MP) != 0:
		var input: Dictionary = prepared["roll_input"].duplicate(true)
		input["hit_bonus"] = hit_bonus
		var value := _roll(prepared, input, rng)
		hit_bonus = value["hit_bonus_after"]
		restored_mp = mini(int(target["max_mp"]) - int(target["mp"]), int(value["value"]))
		changes["mp"] = int(target["mp"]) + restored_mp
		# 0x40b482..0x40b4aa: rand(caster level)+1 replaces the running contribution, 0x40a5d0 (0x40b49e)
		# converts it at once, then the running contribution is restored for the tail conversion.
		if restored_mp != 0: immediate.append(Combat._rand_range(int(prepared["roll_input"]["level"]), rng) + 1)
	return {"target_changes": changes, "healing": healing, "restored_mp": restored_mp, "effects": effects,
		"native_contribution": contribution, "immediate_contributions": immediate, "hit_bonus_after": hit_bonus}

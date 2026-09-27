extends RefCounted
## Source special channel1: mind damage, independent poison check and magnitude.
## Pure proposals only. Resource payment, per-target EXP and turn commit stay shared.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_poison_arrow.md
const ID := "special:magicMIND:magicCode03"
const SpecialDamageRules = preload("res://game/sim/SpecialDamageRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Values = preload("res://game/sim/Values.gd")


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, equipment: Dictionary) -> Dictionary:
	var error := StatusEffectRules.input_error(target)
	if error != "": return {"ok": false, "reason": error}
	var base := SpecialDamageRules.prepare(caster, target, fields, book, equipment)
	if not base["ok"]: return base
	var resistance := Values.non_negative_int(target.get("combat_profile", {}).get("resist_by_type", {}).get("4"))
	if resistance < 0 or resistance > 80: return {"ok": false, "reason": "missing_skill_resistance"}
	var mods := StatusApplicationRules.modifiers(target, book, equipment)
	if not mods["ok"]: return mods
	base["input"]["resistance"] = resistance
	base["input"]["proc"] = 0
	base["immunities"] = mods["effects"]
	return base


static func roll(input: Dictionary, rng: Variant) -> Dictionary:
	var rolled: Dictionary
	if int(input.get("proc", 0)) == 0:
		rolled = SpecialDamageRules.roll(input, rng)
	else:
		# Unlike magic channel0, the special poison check uses hit_ratio plus the
		# current compensation; magic-hit gear and absent status_hit_ratio do not enter.
		var rate := int(input["hit_ratio"]) + int(input["hit_bonus"])
		var draw := CoreCombatRules.native_draw(100, rng) + 1
		var hit: bool = bool(input["no_attack"]) or draw <= rate
		var value := 0
		if hit:
			var half := (int(input["high"]) - int(input["low"])) / 2
			value = int(input["low"]) + half - CoreCombatRules.native_draw(half + 1, rng) + CoreCombatRules.native_draw(half + 1, rng)
			if value < 3: value += 3 * ((5 - value) / 3)
		rolled = {"value": value, "hit_bonus_after": int(input["hit_bonus"]), "hit_check_passed": hit, "hit_rate": rate, "hit_roll": draw}
	if bool(rolled["hit_check_passed"]): rolled["value"] = int(rolled["value"]) * (100 - mini(80, int(input["resistance"]))) / 100
	return rolled


static func resolve(prepared: Dictionary, target: Dictionary, rng: Variant) -> Dictionary:
	var input: Dictionary = prepared["input"].duplicate(true)
	var primary := roll(input, rng)
	input["hit_bonus"] = primary["hit_bonus_after"]
	var after := target.duplicate(true)
	var damage := mini(int(after["hp"]), int(primary["value"]))
	after["hp"] = int(after["hp"]) - damage
	after["defeated"] = int(after["hp"]) == 0
	var effect := {"status": StatusEffectRules.Catalog.POISON_KEY, "applied": false}
	var rolls: Array = [primary]
	var contribution := damage
	if int(after["hp"]) == 0:
		effect["reason"] = "target_defeated"
	elif int(prepared["immunities"]) & (0x800000 | 0x80):
		effect["reason"] = "immune"
	else:
		input["proc"] = 6
		var tested := roll(input, rng)
		rolls.append(tested)
		if int(tested["value"]) == 0:
			effect["reason"] = "miss"
		else:
			var turns := 2 + CoreCombatRules.native_draw(2, rng)
			input["proc"] = 0
			var intensity := roll(input, rng)
			rolls.append(intensity)
			input["hit_bonus"] = intensity["hit_bonus_after"]
			# Native40ada2 tests the saved Attack function bit even when it missed.
			var power := StatusApplicationRules.poison_strength(int(intensity["value"]) * 30 / 100)
			var applied := StatusEffectRules.apply(after, StatusEffectRules.Catalog.POISON_KEY, turns, power)
			assert(applied["ok"], "Prepared Poison Arrow status remains valid")
			after.merge(applied["changes"], true)
			var before := int(applied["before_word"])
			var merged := int(applied["after_word"])
			effect.merge({"applied": true, "before_word": before, "after_word": merged, "added_turns": turns,
				"sampled_power": power, "changed": before != merged}, true)
			contribution += ((merged & 0xffff) - (before & 0xffff)) * 10
	return {"target_changes": {"hp": after["hp"], "defeated": after["defeated"], "status_flags": after["status_flags"], "status_counters": after["status_counters"]},
		"damage": damage, "effects": [effect], "hit_bonus_after": input["hit_bonus"], "native_contribution": contribution,
		"native_damage_roll": primary, "native_poison_rolls": rolls}

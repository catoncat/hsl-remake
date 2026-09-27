extends RefCounted
## Original damaging/status magic proposals. No mutations or RNG during preview.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_application.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_paralysis.md
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const Rolls = preload("res://game/sim/NativeMagicRollRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const Catalog = preload("res://game/sim/StatusCatalog.gd")
const Values = preload("res://game/sim/Values.gd")
## 0x40aa80 immunity queries (catalog immunity_bit), in the 0x40aa80 visit order.
static var IMMUNITY: Dictionary = Catalog.by_key("immunity_bit", Catalog.MAGIC_ORDER)
## Status key -> function bit in native visit order (catalog magic_bit, MAGIC_ORDER).
static var STATUS_BITS: Dictionary = Catalog.by_key("magic_bit", Catalog.MAGIC_ORDER)
## 0x101d: 死骸腐靈獄 (Attack + Paralysis + Poison + NoMagic + Weaken) walks every status branch in
## the same 0x40aa80 order; each status draws its own proc6 check and a 30%-scaled magnitude.
const ACCEPTED_MASKS := [1, 4, 5, 8, 17, 0x1000, 0x1001, 0x101d]


static func modifiers(unit: Dictionary, book: Dictionary, equipment: Dictionary) -> Dictionary:
	var source: Variant = book.get("actors", {}).get(str(unit.get("actor_id", "")))
	if not source is Dictionary or not Values.is_integer_in(source.get("status_capability_flags"), 0, Values.MAX_UNSIGNED) or not unit.get("equipment") is Array:
		return {"ok": false, "reason": "missing_status_capabilities"}
	var equipped := equipment_modifiers(unit, equipment)
	if not equipped["ok"]: return equipped
	var effects := int(equipped["effects"])
	# 0x448420 maps capability bits (catalog capability_bit, e.g. PLAYERS no_weaken 0x44c3ec) onto
	# the immunity bits after applying a nonempty equipment slot.
	var capabilities := int(source["status_capability_flags"])
	if not unit["equipment"].is_empty():
		for key in Catalog.ENTRIES:
			if (capabilities & int(Catalog.ENTRIES[key]["capability_bit"])) != 0: effects |= int(Catalog.ENTRIES[key]["immunity_bit"])
	return {"ok": true, "effects": effects, "magic_hit_bonus": equipped["magic_hit_bonus"], "no_attack": (capabilities & 2) != 0}


static func equipment_modifiers(unit: Dictionary, equipment: Dictionary) -> Dictionary:
	if not unit.get("equipment") is Array: return {"ok": false, "reason": "invalid_status_equipment"}
	var effects := 0
	var magic_hit := 0
	for entry in unit["equipment"]:
		if not entry is Dictionary or not Values.is_integer_in(entry.get("item_code"), 0, Values.MAX_UNSIGNED) or int(entry["item_code"]) == 0:
			return {"ok": false, "reason": "invalid_status_equipment"}
		var item: Variant = equipment.get(str(int(entry["item_code"])))
		if not item is Dictionary or not Values.is_integer_in(item.get("status_effect_flags"), 0, Values.MAX_UNSIGNED) or Values.non_negative_int(item.get("magic_hit_bonus")) < 0:
			return {"ok": false, "reason": "missing_status_equipment_effects"}
		effects |= int(item["status_effect_flags"])
		magic_hit += int(item["magic_hit_bonus"])
	return {"ok": true, "effects": effects, "magic_hit_bonus": magic_hit}


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, channel: String = "magic") -> Dictionary:
	var error := StatusEffectRules.input_error(target)
	if error != "": return {"ok": false, "reason": error}
	var attacker_mods := modifiers(caster, book, equipment)
	if not attacker_mods["ok"]: return attacker_mods
	var defender_mods := modifiers(target, book, equipment)
	if not defender_mods["ok"]: return defender_mods
	var profile: Variant = caster.get("combat_profile")
	var target_profile: Variant = target.get("combat_profile")
	if not profile is Dictionary or not target_profile is Dictionary:
		return {"ok": false, "reason": "missing_status_skill_profile"}
	for value in [caster.get("level"), caster.get("hit_bonus_accum"), profile.get("mind"), profile.get("live_magic_attack")]:
		if Values.non_negative_int(value) < 0 or int(value) > 100000:
			return {"ok": false, "reason": "invalid_status_skill_profile"}
	var element: String = {"magicEARTH": "0", "magicWATER": "1", "magicAIR": "2", "magicFIRE": "3", "magicMIND": "4"}.get(fields.get("type"), "")
	var resists: Variant = target_profile.get("resist_by_type")
	# 0x40aa1e switch has no magicOTHER case: channel1 magicOTHER abilities skip resistance.
	var resistance := 0
	if not (channel == "special" and fields.get("type") == "magicOTHER"):
		if element == "" or not resists is Dictionary or Values.non_negative_int(resists.get(element)) < 0 or int(resists[element]) > 80:
			return {"ok": false, "reason": "missing_skill_resistance"}
		resistance = int(resists[element])
	var mask := SkillTargetRules.function_mask(fields.get("function"), targeting["function_bits"])
	# Special channel1 status checks read hit_ratio (0x40a7ec); SPECIAL.TXT has no status_hit_ratio.
	var status_rate := 0 if mask == 1 or channel == "special" else Values.non_negative_int(fields.get("status_hit_ratio"), true)
	var hit_rate := Values.non_negative_int(fields.get("hit_ratio"), true)
	var bounds: PackedStringArray = str(fields.get("damage", "")).split(",")
	if bounds.size() != 2 or status_rate < 0 or status_rate > 100 or hit_rate < 0 or hit_rate > 100:
		return {"ok": false, "reason": "invalid_status_skill_definition"}
	var low := Values.non_negative_int(bounds[0].strip_edges(), true)
	var high := Values.non_negative_int(bounds[1].strip_edges(), true)
	if low < 0 or high < low or high > 10000:
		return {"ok": false, "reason": "invalid_status_skill_definition"}
	if mask not in ACCEPTED_MASKS: return {"ok": false, "reason": "unsupported_status_skill"}
	for key in Catalog.keys_where("refresh", true):
		if (mask & int(STATUS_BITS[key])) == 0: continue
		# Weaken ends in 0x448840; the target must be refreshable before any RNG.
		var refresh_error := ProgressionRules.refresh_input_error(target, equipment)
		if refresh_error != "": return {"ok": false, "reason": refresh_error}
	return {"ok": true, "function_mask": mask, "immunities": defender_mods["effects"], "channel": channel,
		"roll_input": {"low": low, "high": high, "hit_ratio": hit_rate, "status_hit_ratio": status_rate,
			"proc": 0, "level": int(caster["level"]), "mind": int(StatusEffectRules.weakened_attributes(caster)["mind"]), "magic_attack": int(profile["live_magic_attack"]),
			"hit_bonus": int(caster["hit_bonus_accum"]), "magic_hit_bonus": attacker_mods["magic_hit_bonus"],
			"no_attack": defender_mods["no_attack"], "resistance": resistance}}


static func poison_strength(value: int) -> int:
	# Original folding, not a clamp: e.g. 3->8, 51->41, 60->50.
	if value > 50: value -= 10 * ((value - 41) / 10)
	if value < 5: value += 5 * ((9 - value) / 5)
	return value


## `roller` replaces the magic channel0 helper for special channel1 casts (see
## SpecialStatusRules); the status visit order, immunity gates, duration draws,
## magnitude folding and merge stay this one applicator.
static func resolve(prepared: Dictionary, target: Dictionary, rng: Variant, roller: Callable = Callable(), equipment: Dictionary = {}) -> Dictionary:
	var input: Dictionary = prepared["roll_input"].duplicate(true)
	var after := target.duplicate(true)
	var damage := 0
	var damage_roll := {}
	if (int(prepared["function_mask"]) & 1) != 0:
		var strike: Dictionary = roller.call(input, rng) if roller.is_valid() else Rolls.roll(input, rng)
		damage_roll = strike
		input["hit_bonus"] = strike["hit_bonus_after"]
		damage = mini(int(after["hp"]), int(strike["value"]))
		after["hp"] = int(after["hp"]) - damage
		after["defeated"] = int(after["hp"]) == 0
	var effects: Array = []
	var refresh_needed := false
	for key in STATUS_BITS:
		var function_bit: int = STATUS_BITS[key]
		if (int(prepared["function_mask"]) & function_bit) == 0: continue
		if int(after["hp"]) <= 0:
			effects.append({"status": key, "applied": false, "reason": "target_defeated"})
			continue
		if (int(prepared["immunities"]) & (int(IMMUNITY[key]) | 0x80)) != 0:
			effects.append({"status": key, "applied": false, "reason": "immune"})
			continue
		input["proc"] = 6
		var tested: Dictionary = roller.call(input, rng) if roller.is_valid() else Rolls.roll(input, rng)
		if int(tested["value"]) == 0:
			effects.append({"status": key, "applied": false, "reason": "miss"})
			continue
		var turns := 2 + CoreCombatRules.rand_range(2, rng)
		var power := 0
		if Catalog.ENTRIES[key]["power"]:
			input["proc"] = 0
			var intensity: Dictionary = roller.call(input, rng) if roller.is_valid() else Rolls.roll(input, rng)
			input["hit_bonus"] = intensity["hit_bonus_after"]
			var magnitude := int(intensity["value"])
			# 0x40ad8f / 0x40af5e: a saved Attack bit scales the magnitude to 30% first.
			if (int(prepared["function_mask"]) & 1) != 0: magnitude = magnitude * 30 / 100
			power = poison_strength(magnitude) if key == Catalog.POISON_KEY else StatusEffectRules.weaken_strength(magnitude)
		var application := StatusEffectRules.apply_weaken(after, turns, power) if key == Catalog.WEAKEN_KEY else StatusEffectRules.apply(after, key, turns, power)
		refresh_needed = refresh_needed or Catalog.ENTRIES[key]["refresh"]
		assert(application["ok"], "Prepared status application must remain valid")
		var previous: int = application["before_word"]
		var merged: int = application["after_word"]
		after.merge(application["changes"], true)
		effects.append({"status": key, "applied": true, "before_word": previous, "after_word": merged,
			"added_turns": turns, "sampled_power": power, "changed": previous != merged})
	var contribution := damage
	for effect in effects:
		if effect["applied"]:
			var weight: int = Catalog.ENTRIES[effect["status"]]["contribution"]
			contribution += ((int(effect["after_word"]) & 0xffff) - (int(effect["before_word"]) & 0xffff)) * weight
	var changes := {"hp": after["hp"], "defeated": bool(after.get("defeated", false)),
		"status_flags": after["status_flags"], "status_counters": after["status_counters"]}
	if refresh_needed:
		# 0x40afc4 -> 0x448840: derived stats, max HP/MP and their clamps follow the weakened attributes.
		var refreshed := ProgressionRules.refresh_growth_stats(after, equipment)
		for key in ["hp", "mp", "max_hp", "max_mp", "combat_profile", "live_speed", "move_point"]:
			changes[key] = refreshed[key]
	return {"target_changes": changes,
		"damage": damage, "effects": effects, "hit_bonus_after": input["hit_bonus"],
		"native_contribution": contribution, "native_damage_roll": damage_roll}

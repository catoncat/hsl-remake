extends RefCounted
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/shared_skill_resolution.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_magic_damage.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_ranges.md
##   rules: provisional (area policies over the current grid)
const Status = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplication = preload("res://game/sim/StatusApplicationRules.gd")
const SupportMagicRules = preload("res://game/sim/SupportMagicRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const Special = preload("res://game/sim/SpecialDamageRules.gd")
const RepeatedSpecialRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const StatMagic = preload("res://game/sim/StatMagicRules.gd")
const PoisonArrowRules = preload("res://game/sim/PoisonArrowRules.gd")
const OtherMagicRules = preload("res://game/sim/OtherMagicRules.gd")
const SpecialStatusRules = preload("res://game/sim/SpecialStatusRules.gd")
const SpecialUtilityRules = preload("res://game/sim/SpecialUtilityRules.gd")
const AREA_POLICIES := ["native_magic_status", "native_magic_support", "native_magic_damage", "native_magic_stat", "native_special_poison", "native_special_damage", "native_special_status", "native_special_support", "native_special_stat", "native_special_utility"]
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
## Stateless preparation and resolution shared by player and AI. Cost/target
## evidence remains independent from whole-engine initialization and global RNG.
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")


static func descriptor_error(skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary) -> String:
	if book.get("schema") != "hsl_initial_supported_skills.v1" or not book.get("skills") is Dictionary or not book.get("actors") is Dictionary:
		return "missing_skill_book"
	var entry: Variant = book["skills"].get(skill_id)
	if not entry is Dictionary:
		return "unknown_skill"
	if entry.get("channel") not in ["magic", "special"] or fields.get("type") != entry.get("type") or fields.get("code") != entry.get("code"):
		return "skill_identity_mismatch"
	if skill_id != "%s:%s:%s" % [entry["channel"], entry["type"], entry["code"]] or not entry.get("name") is String or entry["name"].is_empty():
		return "skill_identity_mismatch"
	if entry["channel"] == "magic" and entry.get("magic_key") not in ["wind", "fire", "water", "earth", "mind", "other", "poison", "silence", "paralysis", "cure_poison", "heal", "greater_heal", "life_heal", "attack_up", "defense_up", "dispel", "weaken", "cure_all", "decay", "resist_up"]:
		return "unknown_skill"
	var cost := SkillResourceRules.amounts(entry["channel"], fields.get("expend"))
	if not cost["ok"]:
		return cost["reason"]
	var error := SkillTargetRules.definition_error(fields, targeting)
	if error != "":
		return error
	if not fields.get("damage") is String:
		return "invalid_skill_damage"
	var limits: PackedStringArray = fields["damage"].split(",")
	if limits.size() != 2:
		return "invalid_skill_damage"
	var low := SkillResourceRules._integer(limits[0].strip_edges(), true)
	var high := SkillResourceRules._integer(limits[1].strip_edges(), true)
	if low < 0 or high < low or high == SkillResourceRules.MAX_SIGNED:
		return "invalid_skill_damage"
	var hit := SkillResourceRules._integer(fields.get("hit_ratio"), true)
	if hit < 0 or hit > 100:
		return "invalid_skill_hit_ratio"
	var policy: String = entry.get("damage_policy", "")
	if policy == "native_special_sequence": return RepeatedSpecialRules.definition_error(entry, fields)
	if policy == "native_special_poison":
		if skill_id != PoisonArrowRules.ID or entry["channel"] != "special" or entry.get("fields") != fields or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
		return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) == 9 else "unsupported_skill_function"
	if policy == "native_magic_damage":
		if entry["channel"] != "magic" or entry.get("magic_key") not in ["wind", "fire", "water", "earth", "mind", "other"] or entry.get("damage_bounds") != "native_triangular":
			return "skill_identity_mismatch"
		return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) == 1 else "unsupported_skill_function"
	if policy in ["native_magic_status", "native_magic_support", "native_magic_stat"]:
		if entry["channel"] != "magic" or entry.get("damage_bounds") != "native_triangular" or entry.get("fields") != fields:
			return "skill_identity_mismatch"
		var mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
		if policy == "native_magic_support": return "" if SupportMagicRules.accepted(mask) else "unsupported_skill_formula"
		var accepted: Array = StatusApplication.ACCEPTED_MASKS.filter(func(bit): return bit != 1) if policy == "native_magic_status" else [0x20, 0x40, 0x100, 0x4000]
		return "" if mask in accepted else "unsupported_skill_formula"
	if policy == "native_special_status": return _special_status_descriptor_error(entry, fields, targeting)
	if policy == "native_special_support": return _special_support_descriptor_error(entry, fields, targeting)
	if policy == "native_special_stat": return _special_stat_descriptor_error(entry, fields, targeting)
	if policy == "native_special_utility": return _special_utility_descriptor_error(entry, fields, targeting)
	var function_mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
	if function_mask != 1 and not (policy == "native_magic_status" and function_mask in [4, 5, 8, 17]):
		return "unsupported_skill_function"
	if policy == "native_special_damage":
		# Identity is the type/code pair already checked by descriptor_error; the live
		# source fields may legitimately differ from the book copy (fixtures, refreshes).
		if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
		var scale := SkillResourceRules._integer(fields.get("attackpow_ratio"), true)
		if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
		return ""
	var effect: Dictionary = targeting["ranges"][fields["effect_range"]]
	if int(effect["size"]) != 1 or int(effect["data"][0][0]) <= 0: return "unsupported_skill_effect_range"
	return "unsupported_skill_formula"


## 弱體箭 / 獸神怒號 (Attack+Weaken) and 影纏 (Paralysis): channel1 status branches of 0x40aa80.
static func _special_status_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary) -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := SkillResourceRules._integer(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) in [4, 0x1000, 0x1001] else "unsupported_skill_function"


## 萬息集氣法 (Heal) / 萬息降靈法 (HealMP) / 萬息臨界法 (Heal+HealMP) / 萬息秘孔術 (four cures): channel1 support.
static func _special_support_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary) -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := SkillResourceRules._integer(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if SupportMagicRules.accepted(SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])) else "unsupported_skill_formula"


## 千羽風靈壁 (DefUp) / 激怒 (AttUp) / 精神統一 (DefUp+AttUp): channel1 buffs on the shared stat applicator.
static func _special_stat_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary) -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := SkillResourceRules._integer(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if StatMagic.accepted(SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]), "special") else "unsupported_skill_formula"


## 天鳴覺醒 (ActiveAgain) / 獅子吼 (CancelActive) / 吸血劍 (Attack+StealHP): channel1 queue and drain effects.
static func _special_utility_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary) -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := SkillResourceRules._integer(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) in SpecialUtilityRules.ACCEPTED else "unsupported_skill_function"


static func ownership_error(actor: Dictionary, skill_id: String, book: Dictionary) -> String:
	var learned_error := preload("res://game/sim/LearningRules.gd").input_error(actor, book.get("learning", {}))
	if learned_error != "": return learned_error
	var actors: Variant = book.get("actors")
	if not actors is Dictionary:
		return "missing_skill_book"
	var source: Variant = actors.get(str(actor.get("actor_id", "")))
	if not source is Dictionary or not source.get("supported_initial_ids") is Array:
		return "missing_initial_skill_source"
	return "" if source["supported_initial_ids"].has(skill_id) or preload("res://game/sim/LearningRules.gd").owns(actor, skill_id) else "skill_not_owned"


static func available(actor: Dictionary, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary) -> Dictionary:
	var error := descriptor_error(skill_id, fields, book, targeting)
	if error == "": error = ownership_error(actor, skill_id, book)
	if error != "": return {"ok": false, "reason": error}
	if actor.get("battle_actor_role") not in SkillTargetRules.ROLES or not SkillTargetRules._living(actor) or SkillResourceRules._integer(actor.get("hp")) <= 0:
		return {"ok": false, "reason": "caster_unavailable"}
	error = Status.input_error(actor)
	if error != "": return {"ok": false, "reason": error}
	if Status.paralyzed(actor): return {"ok": false, "reason": "caster_paralyzed"}
	if book["skills"][skill_id]["channel"] == "magic" and Status.magic_blocked(actor):
		return {"ok": false, "reason": "magic_disabled_by_status"}
	return SkillResourceRules.quote(actor, fields, book["skills"][skill_id]["channel"], equipment)


static func prepare(caster: Dictionary, target: Dictionary, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, context: Dictionary = {}) -> Dictionary:
	var payment := available(caster, skill_id, fields, book, targeting, equipment)
	if not payment["ok"]: return payment
	var position_error := PositionCapabilityRules.cast_error(caster, book, equipment, book["skills"][skill_id]["channel"], caster.get("coord") != origin)
	if position_error != "": return {"ok": false, "reason": position_error}
	var error := SkillTargetRules.target_error(caster, target, origin, fields, targeting, map_size, context.get("range_terrain", {}))
	if error != "": return {"ok": false, "reason": error}
	if SkillResourceRules._integer(target.get("hp")) <= 0:
		return {"ok": false, "reason": "invalid_skill_target_hp"}
	var descriptor: Dictionary = book["skills"][skill_id]
	if descriptor["damage_policy"] == "native_special_utility":
		var utility := SpecialUtilityRules.prepare(caster, target, fields, book, targeting, equipment, context)
		if not utility["ok"]: return utility
		return {"ok": true, "resource_payment": payment, "utility": utility}
	if descriptor["damage_policy"] == "native_special_poison":
		var arrow := PoisonArrowRules.prepare(caster, target, fields, book, equipment)
		if not arrow["ok"]: return arrow
		return {"ok": true, "resource_payment": payment, "arrow": arrow}
	if descriptor["damage_policy"] in ["native_magic_stat", "native_special_stat"]:
		var stat_effect := StatMagic.prepare(caster, target, fields, book, targeting, equipment, descriptor["channel"])
		if not stat_effect["ok"]: return stat_effect
		return {"ok": true, "resource_payment": payment, "stat_effect": stat_effect}
	if descriptor["damage_policy"] in ["native_magic_support", "native_special_support"]:
		var support := SupportMagicRules.prepare(caster, target, fields, book, targeting, equipment, descriptor["channel"])
		if not support["ok"]: return support
		return {"ok": true, "resource_payment": payment, "support": support}
	if descriptor["damage_policy"] in ["native_magic_status", "native_magic_damage", "native_special_status"]:
		var status: Dictionary
		if descriptor["damage_policy"] == "native_special_status": status = SpecialStatusRules.prepare(caster, target, fields, book, targeting, equipment)
		elif descriptor.get("magic_key") == "other": status = OtherMagicRules.prepare(caster, target, fields, book, targeting, equipment)
		else: status = StatusApplication.prepare(caster, target, fields, book, targeting, equipment)
		if not status["ok"]: return status
		return {"ok": true, "resource_payment": payment, "status": status}
	var special := Special.prepare(caster, target, fields, book, equipment)
	if not special["ok"]: return special
	return {"ok": true, "resource_payment": payment, "special": special}


static func resolve(caster: Dictionary, target: Dictionary, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, rng: Variant = null, context: Dictionary = {}) -> Dictionary:
	if skill_id == RepeatedSpecialRules.ID:
		return resolve_cast(caster, target, [caster, target], skill_id, fields, book, targeting, equipment, origin, map_size, rng, origin)
	var ready := prepare(caster, target, skill_id, fields, book, targeting, equipment, origin, map_size, context)
	if not ready["ok"]: return ready
	if ready.has("support") and not ready["support"]["useful"]: return {"ok": false, "reason": "skill_has_no_effect"}
	if ready.has("utility") and not ready["utility"]["useful"]: return {"ok": false, "reason": "skill_has_no_effect"}
	if ready.has("stat_effect") and not ready["stat_effect"]["useful"]: return {"ok": false, "reason": "skill_has_no_effect"}
	var source: Variant = rng
	if source == null:
		source = RandomNumberGenerator.new()
		source.randomize()
	var descriptor: Dictionary = book["skills"][skill_id]
	if descriptor["damage_policy"] == "native_special_utility":
		return _resolve_utility(caster, target, skill_id, descriptor, ready, source)
	if descriptor["damage_policy"] in ["native_magic_stat", "native_special_stat"]:
		return _resolve_stat_magic(caster, target, skill_id, descriptor, ready, equipment, source)
	if descriptor["damage_policy"] in ["native_magic_support", "native_special_support"]:
		return _resolve_support(caster, target, skill_id, descriptor, ready, source, equipment)
	if descriptor["damage_policy"] in ["native_magic_status", "native_magic_damage", "native_special_poison", "native_special_status"]:
		return _resolve_status(caster, target, skill_id, descriptor, ready, source, equipment)
	return _resolve_special_damage(caster, target, skill_id, descriptor, ready, source)


static func _resolve_status(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	var arrow: bool = descriptor["damage_policy"] == "native_special_poison"
	var special_status: bool = descriptor["damage_policy"] == "native_special_status"
	var resolved: Dictionary
	if arrow: resolved = PoisonArrowRules.resolve(ready["arrow"], target, rng)
	elif special_status: resolved = SpecialStatusRules.resolve(ready["status"], target, rng, equipment)
	else: resolved = StatusApplication.resolve(ready["status"], target, rng, Callable(), equipment)
	var payment: Dictionary = ready["resource_payment"]
	var hit := int(resolved["damage"]) > 0
	for effect in resolved["effects"]:
		hit = hit or bool(effect["applied"])
	var receipt := {"skill_id": skill_id, "attacker_id": str(caster["id"]), "defender_id": str(target["id"]),
		"hit": hit, "damage": resolved["damage"], "actual_damage": resolved["damage"],
		"defender_hp_before": int(target["hp"]), "defender_hp_after": int(resolved["target_changes"]["hp"]),
		"resource_payment": payment, "magic_key": descriptor["magic_key"], "magic_name": descriptor["name"],
		"status_effects": resolved["effects"], "native_contribution": resolved["native_contribution"],
		"native_damage_roll": resolved["native_damage_roll"],
		"attacker_before": Combat.receipt_vitals(caster), "defender_before": Combat.receipt_vitals(target),
		"formula_source": "native_magic_roll_and_status_applicator"}
	if arrow:
		receipt.erase("magic_key")
		receipt.erase("magic_name")
		receipt.merge({"special_key": "poison_arrow", "skill_name": descriptor["name"], "native_poison_rolls": resolved["native_poison_rolls"],
			"formula_source": "0x40a7b0_channel1_and_0x40aa80_to_0x40b831"}, true)
	if special_status:
		receipt.erase("magic_key")
		receipt.erase("magic_name")
		receipt.merge({"special_key": "special_status", "skill_name": descriptor["name"],
			"formula_source": "0x40aa80_channel1_status_branches_and_0x40a7b0_channel1"}, true)
	if descriptor["damage_policy"] == "native_magic_damage":
		receipt["hit"] = bool(resolved["native_damage_roll"]["hit_check_passed"])
		receipt["formula_source"] = "0x40a7b0_proc0_and_0x40ab55_hp_cap"
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": resolved["hit_bonus_after"]},
		"target_changes": resolved["target_changes"], "receipt": receipt}


## One special-damage target (氣刃斬 alone, or each unit inside an area special's
## effect footprint): original 0x40a7b0 channel1/proc0 roll and capped HP application.
static func _resolve_special_damage(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant) -> Dictionary:
	var rolled := Special.roll(ready["special"]["input"], rng)
	var hp_before := int(target["hp"])
	var damage := mini(hp_before, int(rolled["value"]))
	var hp_after := hp_before - damage
	var payment: Dictionary = ready["resource_payment"]
	var receipt := {"skill_id": skill_id, "attacker_id": str(caster["id"]), "defender_id": str(target["id"]),
		"hit": rolled["hit_check_passed"], "hit_rate": rolled["hit_rate"], "hit_roll": rolled["hit_roll"],
		"damage": damage, "actual_damage": damage,
		"native_contribution": damage, "native_damage_roll": rolled,
		"defender_hp_before": hp_before, "defender_hp_after": hp_after,
		"resource_payment": payment, "skill_name": descriptor["name"],
		"attacker_before": Combat.receipt_vitals(caster), "defender_before": Combat.receipt_vitals(target),
		"formula_source": "0x40a7b0_channel1_proc0_and_0x40ab55_hp_cap"}
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": rolled["hit_bonus_after"]},
		"target_changes": {"hp": hp_after, "defeated": hp_after == 0}, "receipt": receipt}


static func _resolve_utility(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant) -> Dictionary:
	var resolved := SpecialUtilityRules.resolve(ready["utility"], caster, target, rng)
	var payment: Dictionary = ready["resource_payment"]
	var hp_after: int = int(resolved["target_changes"].get("hp", target["hp"]))
	var receipt := {"skill_id": skill_id, "attacker_id": str(caster["id"]), "defender_id": str(target["id"]),
		"hit": resolved["hit"], "hit_rate": resolved["roll"]["hit_rate"], "hit_roll": resolved["roll"]["hit_roll"],
		"damage": resolved["damage"], "actual_damage": resolved["damage"], "native_damage_roll": resolved["roll"],
		"defender_hp_before": int(target["hp"]), "defender_hp_after": hp_after,
		"resource_payment": payment, "skill_name": descriptor["name"], "special_key": "special_utility",
		"turn_effects": resolved["turn_effects"], "gold_effects": resolved["gold_effects"], "stolen_items": resolved["item_effects"], "direct_experience": resolved["direct_experience"],
		"stolen_hp": int(resolved["caster_changes"].get("hp", caster["hp"])) - int(caster["hp"]),
		"native_contribution": resolved["native_contribution"], "immediate_contributions": resolved["immediate_contributions"],
		"attacker_before": Combat.receipt_vitals(caster), "defender_before": Combat.receipt_vitals(target),
		"formula_source": "0x40aa80_bits_0x10000_0x80000_0x100000_and_0x40a7b0_channel1"}
	var caster_changes := {payment["resource"]: payment["after"], "hit_bonus_accum": resolved["hit_bonus_after"]}
	caster_changes.merge(resolved["caster_changes"], true)
	return {"ok": true, "caster_changes": caster_changes, "target_changes": resolved["target_changes"], "turn_effects": resolved["turn_effects"], "gold_effects": resolved["gold_effects"], "receipt": receipt}


static func _resolve_support(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	var resolved := SupportMagicRules.resolve(ready["support"], target, int(caster["hit_bonus_accum"]), rng, equipment)
	var payment: Dictionary = ready["resource_payment"]
	var hit: bool = int(resolved["healing"]) > 0 or int(resolved["restored_mp"]) > 0 or resolved["effects"].any(func(effect): return effect["removed"])
	var receipt := {"skill_id": skill_id, "attacker_id": str(caster["id"]), "defender_id": str(target["id"]),
		"hit": hit, "damage": 0, "actual_damage": 0, "healing": resolved["healing"], "restored_mp": resolved["restored_mp"], "support_effects": resolved["effects"],
		"native_contribution": resolved["native_contribution"], "immediate_contributions": resolved["immediate_contributions"], "defender_hp_before": int(target["hp"]),
		"defender_hp_after": int(resolved["target_changes"]["hp"]), "resource_payment": payment,
		"magic_key": descriptor["magic_key"], "magic_name": descriptor["name"],
		"formula_source": "native_heal_proc1_and_cure_poison_prefix"}
	if descriptor["channel"] == "special":
		receipt.erase("magic_key")
		receipt.erase("magic_name")
		receipt.merge({"special_key": "special_support", "skill_name": descriptor["name"], "formula_source": "0x40aa80_support_branches_and_0x40a7b0_channel1_proc1"}, true)
	receipt["attacker_before"] = Combat.receipt_vitals(caster)
	receipt["defender_before"] = Combat.receipt_vitals(target)
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": resolved["hit_bonus_after"]},
		"target_changes": resolved["target_changes"], "receipt": receipt}


static func _resolve_stat_magic(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, equipment: Dictionary, rng: Variant) -> Dictionary:
	var result := StatMagic.resolve(ready["stat_effect"], target, int(caster["hit_bonus_accum"]), equipment, rng)
	var payment: Dictionary = ready["resource_payment"]
	var before := Combat.receipt_vitals(target)
	before.merge({"combat_profile": target["combat_profile"].duplicate(true), "status_flags": target["status_flags"], "status_counters": target["status_counters"].duplicate(true)})
	var receipt := {"skill_id": skill_id, "attacker_id": caster["id"], "defender_id": target["id"], "hit": not result["effects"].is_empty(),
			"damage": 0, "actual_damage": 0, "defender_hp_before": target["hp"], "defender_hp_after": target["hp"],
		"resource_payment": payment, "magic_key": descriptor["magic_key"], "magic_name": descriptor["name"],
		"stat_effects": result["effects"], "native_contribution": result["native_contribution"], "native_stat_rolls": result["rolls"],
		"sampled_duration": result["sampled_duration"], "sampled_durations": result["sampled_durations"], "stats_before": result["stats_before"], "stats_after": result["stats_after"],
		"attacker_before": Combat.receipt_vitals(caster), "defender_before": before,
		"formula_source": "0x40b01c_0x40b112_0x40b299_with_full_stat_refresh"}
	if descriptor["channel"] == "special":
		receipt.erase("magic_key")
		receipt.erase("magic_name")
		receipt.merge({"special_key": "special_stat", "skill_name": descriptor["name"], "formula_source": "0x40aa80_buff_branches_and_0x40a7b0_channel1"}, true)
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": result["hit_bonus_after"]},
		"target_changes": result["target_changes"], "receipt": receipt}


static func prepare_cast(caster: Dictionary, center: Dictionary, units: Array, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, center_coord: Variant = null, context: Dictionary = {}) -> Dictionary:
	var position_error := PositionCapabilityRules.cast_error(caster, book, equipment, str(book.get("skills", {}).get(skill_id, {}).get("channel", "")), caster.get("coord") != origin)
	if position_error != "": return {"ok": false, "reason": position_error}
	# Moving AI casts are still proposals. Enumerate the caster at its proposed
	# destination so an allied footprint can include (or exclude) it correctly.
	# These local copies never move the actual unit before the atomic commit.
	if caster.get("coord") != origin:
		caster = caster.duplicate(true)
		caster["coord"] = origin
		if center.get("id") == caster["id"]: center = caster
		units = units.map(func(unit): return caster if unit is Dictionary and unit.get("id") == caster["id"] else unit)
	for actor in [caster, center]:
		var error := ExperienceRules.actor_error(actor)
		if error != "": return {"ok": false, "reason": error}
	var multiplier := ExperienceRules.multiplier(caster, equipment)
	if not multiplier["ok"]: return multiplier
	var payment := available(caster, skill_id, fields, book, targeting, equipment)
	if not payment["ok"]: return payment
	# `range_terrain` (RangePropagationRules.player_skill_terrain): the original 0x4000／occupant
	# propagation of the cast range (and of the area when it carries `area_modes`).
	var terrain: Dictionary = context.get("range_terrain", {})
	if book["skills"][skill_id]["damage_policy"] == "native_special_sequence":
		return RepeatedSpecialRules.prepare(caster, center, units, fields, book, targeting, equipment, origin, map_size, payment, center_coord, terrain)
	if book["skills"][skill_id]["damage_policy"] not in AREA_POLICIES:
		if center_coord != null and (not center_coord is Vector2i or not SkillTargetRules.Footprint.contains(center,center_coord)): return {"ok": false, "reason": "unsupported_skill_center"}
		var primary := prepare(caster, center, skill_id, fields, book, targeting, equipment, origin, map_size, context)
		if not primary["ok"]: return primary
		return {"ok": true, "targets": [center], "prepared": [primary]}
	var cast_cells := SkillTargetRules.cells(origin, fields, targeting, map_size, terrain)
	var cast_center: Variant = SkillTargetRules.Footprint.contact(center, cast_cells) if center_coord == null else center_coord
	if not cast_center is Vector2i or not cast_cells.has(cast_center): return {"ok": false, "reason": "out_of_range"}
	if not SkillTargetRules._living(center): return {"ok": false, "reason": "target_unavailable"}
	if center.get("battle_actor_role") not in SkillTargetRules.ROLES: return {"ok": false, "reason": "unsupported_target_role"}
	if not SkillTargetRules.side_matches(caster, center, fields, targeting): return {"ok": false, "reason": "not_ally" if SkillTargetRules.is_support(fields, targeting) else "not_enemy"}
	var footprint := SkillTargetRules.cast_footprint(origin, cast_center, fields, targeting, map_size, terrain)
	var targets: Array = []
	var prepared: Array = []
	var seen := {}
	var support: bool = book["skills"][skill_id]["damage_policy"] in ["native_magic_support", "native_special_support"]
	var stat: bool = book["skills"][skill_id]["damage_policy"] in ["native_magic_stat", "native_special_stat"]
	var arrow: bool = book["skills"][skill_id]["damage_policy"] == "native_special_poison"
	var special_damage: bool = book["skills"][skill_id]["damage_policy"] == "native_special_damage"
	var special_status: bool = book["skills"][skill_id]["damage_policy"] == "native_special_status"
	var utility: bool = book["skills"][skill_id]["damage_policy"] == "native_special_utility"
	var useful := false
	# Stable roster order is the current adapter policy; the original engine's
	# cross-object visitation order is not inferred from RANGE occupancy values.
	for unit in units:
		if not unit is Dictionary or not unit.get("coord") is Vector2i:
			return {"ok": false, "reason": "invalid_skill_roster"}
		if not SkillTargetRules.Footprint.overlaps(unit, footprint) or not SkillTargetRules._living(unit): continue
		if unit.get("battle_actor_role") not in SkillTargetRules.ROLES:
			return {"ok": false, "reason": "unsupported_target_role"}
		if not SkillTargetRules.area_side_matches(caster, unit, fields, targeting): continue
		var id := str(unit.get("id", ""))
		if id == "" or seen.has(id): return {"ok": false, "reason": "invalid_target_identity"}
		seen[id] = true
		var exp_error := ExperienceRules.actor_error(unit)
		if exp_error != "": return {"ok": false, "reason": exp_error}
		var status: Dictionary
		if arrow: status = PoisonArrowRules.prepare(caster, unit, fields, book, equipment)
		elif stat: status = StatMagic.prepare(caster, unit, fields, book, targeting, equipment, book["skills"][skill_id]["channel"])
		elif support: status = SupportMagicRules.prepare(caster, unit, fields, book, targeting, equipment, book["skills"][skill_id]["channel"])
		elif special_damage: status = Special.prepare(caster, unit, fields, book, equipment)
		elif special_status: status = SpecialStatusRules.prepare(caster, unit, fields, book, targeting, equipment)
		elif utility: status = SpecialUtilityRules.prepare(caster, unit, fields, book, targeting, equipment, context)
		elif book["skills"][skill_id].get("magic_key") == "other": status = OtherMagicRules.prepare(caster, unit, fields, book, targeting, equipment)
		else: status = StatusApplication.prepare(caster, unit, fields, book, targeting, equipment)
		if not status["ok"]: return status
		useful = useful or bool(status.get("useful", true))
		if utility and not bool(status["useful"]): continue # 0x4075a0/0x407550 would return 0 for this unit
		targets.append(unit)
		prepared.append({"ok": true, "resource_payment": payment, ("arrow" if arrow else "stat_effect" if stat else "support" if support else "special" if special_damage else "utility" if utility else "status"): status})
	if not seen.has(str(center["id"])): return {"ok": false, "reason": "missing_skill_center"}
	if not useful: return {"ok": false, "reason": "skill_has_no_effect"}
	if utility and not targets.any(func(unit): return unit["id"] == center["id"]): return {"ok": false, "reason": "skill_has_no_effect"}
	return {"ok": true, "targets": targets, "prepared": prepared, "cast_center": cast_center}


static func resolve_cast(caster: Dictionary, center: Dictionary, units: Array, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, rng: Variant = null, center_coord: Variant = null, context: Dictionary = {}) -> Dictionary:
	var ready := prepare_cast(caster, center, units, skill_id, fields, book, targeting, equipment, origin, map_size, center_coord, context)
	if not ready["ok"]: return ready
	var source: Variant = rng
	if source == null:
		source = RandomNumberGenerator.new()
		source.randomize()
	if book["skills"][skill_id]["damage_policy"] == "native_special_sequence":
		return RepeatedSpecialRules.resolve(caster, ready, book["skills"][skill_id], source)
	if book["skills"][skill_id]["damage_policy"] not in AREA_POLICIES:
		var one := resolve(caster, center, skill_id, fields, book, targeting, equipment, origin, map_size, source, context)
		var basis := ExperienceRules.record(caster, center, one["receipt"], source)
		one["receipt"]["experience_basis"] = basis
		one["caster_changes"].merge({"kill_chain_word": basis["kill_word_after"], "kill_count": int(caster["kill_count"]) + int(basis["kills_added"])})
		one["targets"] = [{"id": str(center["id"]), "changes": one["target_changes"]}]
		return one
	var working_caster := caster.duplicate(true)
	var changes: Array = []
	var receipts: Array = []
	var primary: Dictionary = {}
	var payment: Dictionary = ready["prepared"][0]["resource_payment"]
	var support: bool = book["skills"][skill_id]["damage_policy"] in ["native_magic_support", "native_special_support"]
	var stat: bool = book["skills"][skill_id]["damage_policy"] in ["native_magic_stat", "native_special_stat"]
	var arrow: bool = book["skills"][skill_id]["damage_policy"] == "native_special_poison"
	var special_damage: bool = book["skills"][skill_id]["damage_policy"] == "native_special_damage"
	var utility: bool = book["skills"][skill_id]["damage_policy"] == "native_special_utility"
	var turn_effects: Array = []
	var gold_effects: Array = []
	var stolen_items: Array = []
	var killed := false
	for index in range(ready["targets"].size()):
		var target: Dictionary = ready["targets"][index]
		var prepared: Dictionary = ready["prepared"][index].duplicate(true)
		var result: Dictionary
		if stat:
			result = _resolve_stat_magic(working_caster, target, skill_id, book["skills"][skill_id], prepared, equipment, source)
		elif support:
			result = _resolve_support(working_caster, target, skill_id, book["skills"][skill_id], prepared, source, equipment)
		elif special_damage:
			# Like the status/arrow rolls: a miss on an earlier footprint target raises
			# the compensation the next target's hit check reads within this cast.
			prepared["special"]["input"]["hit_bonus"] = working_caster["hit_bonus_accum"]
			result = _resolve_special_damage(working_caster, target, skill_id, book["skills"][skill_id], prepared, source)
		elif utility:
			prepared["utility"]["input"]["hit_bonus"] = working_caster["hit_bonus_accum"]
			result = _resolve_utility(working_caster, target, skill_id, book["skills"][skill_id], prepared, source)
			if result["caster_changes"].has("hp"): working_caster["hp"] = result["caster_changes"]["hp"]
			turn_effects.append_array(result["turn_effects"])
			gold_effects.append_array(result["gold_effects"])
			stolen_items.append_array(result["receipt"]["stolen_items"])
		else:
			if arrow: prepared["arrow"]["input"]["hit_bonus"] = working_caster["hit_bonus_accum"]
			else: prepared["status"]["roll_input"]["hit_bonus"] = working_caster["hit_bonus_accum"]
			result = _resolve_status(working_caster, target, skill_id, book["skills"][skill_id], prepared, source, equipment)
		working_caster["hit_bonus_accum"] = result["caster_changes"]["hit_bonus_accum"]
		# Native effect -> this target's EXP -> next target. No growth or extra
		# MP debit can change a later target's caster profile within this cast.
		var basis := ExperienceRules.record(working_caster, target, result["receipt"], source, killed)
		if int(result["receipt"].get("direct_experience", 0)) > 0:
			# 0x40b568: StealGold adds amount/2 + rand(amount/2) EXP without the contribution conversion.
			basis["direct_experience"] = int(result["receipt"]["direct_experience"])
			basis["points"] = int(basis["points"]) + int(result["receipt"]["direct_experience"])
		result["receipt"]["experience_basis"] = basis
		working_caster["kill_chain_word"] = basis["kill_word_after"]
		working_caster["kill_count"] = int(working_caster["kill_count"]) + int(basis["kills_added"])
		killed = killed or bool(basis["killed"])
		changes.append({"id": str(target["id"]), "changes": result["target_changes"]})
		receipts.append(result["receipt"])
		if target["id"] == center["id"]: primary = result["receipt"].duplicate(true)
	primary["affected_targets"] = receipts
	primary["cast_center"] = ready["cast_center"]
	var center_changes: Dictionary = {}
	for change in changes:
		if change["id"] == center["id"]: center_changes = change["changes"]
	var caster_changes := {payment["resource"]: payment["after"], "hit_bonus_accum": working_caster["hit_bonus_accum"],
		"kill_chain_word": working_caster["kill_chain_word"], "kill_count": working_caster["kill_count"]}
	if utility:
		if int(working_caster["hp"]) != int(caster["hp"]): caster_changes["hp"] = working_caster["hp"]
		primary["turn_effects"] = turn_effects
		primary["gold_effects"] = gold_effects
		primary["stolen_items"] = stolen_items
	return {"ok": true, "caster_changes": caster_changes, "targets": changes, "target_changes": center_changes, "receipt": primary, "turn_effects": turn_effects, "gold_effects": gold_effects}

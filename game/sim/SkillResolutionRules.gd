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
const MultiHitSpecialRules = preload("res://game/sim/MultiHitSpecialRules.gd")
const StatMagic = preload("res://game/sim/StatMagicRules.gd")
const PoisonArrowRules = preload("res://game/sim/PoisonArrowRules.gd")
const OtherMagicRules = preload("res://game/sim/OtherMagicRules.gd")
const SpecialStatusRules = preload("res://game/sim/SpecialStatusRules.gd")
const SpecialUtilityRules = preload("res://game/sim/SpecialUtilityRules.gd")
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
const Values = preload("res://game/sim/Values.gd")
const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
## Stateless preparation and resolution shared by player and AI. Cost/target
## evidence remains independent from whole-engine initialization and global RNG.
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
## 技能效果族登记表：技能书每行的 damage_policy 对应这里一行，五个入口（descriptor_error／prepare／
## resolve／prepare_cast／resolve_cast）只查表分派。加一种效果族：写一个规则模块提供下面三个函数，
## 在这里登记一行（Callable 指向模块函数，如 Callable(FooRules, "prepare")），再让生成器输出这个 policy。
##   descriptor_error  func(entry, fields, targeting, skill_id) -> String, after the shared identity/cost/
##                     range/damage/hit gates ("" accepts the descriptor).
##   prepare           func(caster, target, descriptor, fields, book, targeting, equipment, context) -> Dictionary:
##                     one target's RNG-free proposal ({"ok": false, "reason"} rejects the whole cast).
##   resolve           func(caster, target, skill_id, descriptor, ready, rng, equipment) -> Dictionary:
##                     {"ok", "caster_changes", "target_changes", "receipt"} for one target.
##   ready_key         key the proposal travels under in ready (resolve reads ready[ready_key]).
##   area              true: every living unit inside the effect footprint is a target, in roster order;
##                     false: the clicked target only.
##   hit_bonus_input   area casts copy the running hit_bonus_accum into ready[ready_key][this] before each
##                     target ("": resolve reads the caster's hit_bonus_accum itself).
##   subset            (optional) area casts keep only useful units, and the centre must be one of them.
##   caster_effects    (optional) resolve may change the caster's HP and carries turn/gold/item effects.
##   kind, channel     what AI planners ask: damage／status／support／stat／arrow／utility／sequence; magic／special.
##   prepare_cast, resolve_cast  (optional) the family owns the whole cast (連續技).
static var EFFECTS := {
	# NativeMagicRollRules proc0 through StatusApplicationRules (magic_key "other": OtherMagicRules).
	"native_magic_damage": {"kind": "damage", "channel": "magic", "area": true, "ready_key": "status", "hit_bonus_input": "roll_input",
		"descriptor_error": _magic_damage_descriptor_error, "prepare": _prepare_magic, "resolve": _resolve_magic_damage},
	# StatusApplicationRules: 0x40aa80 status branches.
	"native_magic_status": {"kind": "status", "channel": "magic", "area": true, "ready_key": "status", "hit_bonus_input": "roll_input",
		"descriptor_error": _magic_status_descriptor_error, "prepare": _prepare_magic, "resolve": _resolve_status},
	# SupportMagicRules.
	"native_magic_support": {"kind": "support", "channel": "magic", "area": true, "ready_key": "support", "hit_bonus_input": "",
		"descriptor_error": _magic_support_descriptor_error, "prepare": _prepare_support, "resolve": _resolve_support},
	# StatMagicRules.
	"native_magic_stat": {"kind": "stat", "channel": "magic", "area": true, "ready_key": "stat_effect", "hit_bonus_input": "",
		"descriptor_error": _magic_stat_descriptor_error, "prepare": _prepare_stat, "resolve": _resolve_stat_magic},
	# SpecialDamageRules.
	"native_special_damage": {"kind": "damage", "channel": "special", "area": true, "ready_key": "special", "hit_bonus_input": "input",
		"descriptor_error": _special_damage_descriptor_error, "prepare": _prepare_special_damage, "resolve": _resolve_special_damage},
	# SpecialStatusRules.
	"native_special_status": {"kind": "status", "channel": "special", "area": true, "ready_key": "status", "hit_bonus_input": "roll_input",
		"descriptor_error": _special_status_descriptor_error, "prepare": _prepare_special_status, "resolve": _resolve_special_status},
	# SupportMagicRules (channel1).
	"native_special_support": {"kind": "support", "channel": "special", "area": true, "ready_key": "support", "hit_bonus_input": "",
		"descriptor_error": _special_support_descriptor_error, "prepare": _prepare_support, "resolve": _resolve_support},
	# StatMagicRules (channel1).
	"native_special_stat": {"kind": "stat", "channel": "special", "area": true, "ready_key": "stat_effect", "hit_bonus_input": "",
		"descriptor_error": _special_stat_descriptor_error, "prepare": _prepare_stat, "resolve": _resolve_stat_magic},
	# SpecialUtilityRules.
	"native_special_utility": {"kind": "utility", "channel": "special", "area": true, "ready_key": "utility", "hit_bonus_input": "input",
		"subset": true, "caster_effects": true,
		"descriptor_error": _special_utility_descriptor_error, "prepare": _prepare_utility, "resolve": _resolve_utility},
	# PoisonArrowRules.
	"native_special_poison": {"kind": "arrow", "channel": "special", "area": true, "ready_key": "arrow", "hit_bonus_input": "input",
		"descriptor_error": _arrow_descriptor_error, "prepare": _prepare_arrow, "resolve": _resolve_arrow},
	# RepeatedSpecialRules owns the cast; a lone prepare/resolve takes the special-damage path.
	"native_special_sequence": {"kind": "sequence", "channel": "special", "area": false, "ready_key": "special", "hit_bonus_input": "input",
		"descriptor_error": _sequence_descriptor_error, "prepare": _prepare_special_damage, "resolve": _resolve_special_damage,
		"prepare_cast": Callable(RepeatedSpecialRules, "prepare"), "resolve_cast": Callable(RepeatedSpecialRules, "resolve")},
}
## A policy without a row never passes descriptor_error (function-mask 1 and effect-range gates, then
## unsupported_skill_formula), so prepare/resolve never reach its special-damage fallback.
static var UNLISTED := {"kind": "", "channel": "", "area": false, "ready_key": "special", "hit_bonus_input": "input",
	"descriptor_error": _unlisted_descriptor_error, "prepare": _prepare_special_damage, "resolve": _resolve_special_damage}


static func effect_for(policy: String) -> Dictionary:
	return EFFECTS.get(policy, UNLISTED)


## True when the policy's row is one of `kinds` (and on `channel` when given).
static func is_kind(policy: String, kinds: Array, channel: String = "") -> bool:
	var row := effect_for(policy)
	return row["kind"] in kinds and (channel == "" or row["channel"] == channel)


static func _effect_of(descriptor: Dictionary) -> Dictionary:
	return effect_for(str(descriptor.get("damage_policy", "")))


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
	var low := Values.non_negative_int(limits[0].strip_edges(), true)
	var high := Values.non_negative_int(limits[1].strip_edges(), true)
	if low < 0 or high < low or high == SkillResourceRules.MAX_SIGNED:
		return "invalid_skill_damage"
	var hit := Values.non_negative_int(fields.get("hit_ratio"), true)
	if hit < 0 or hit > 100:
		return "invalid_skill_hit_ratio"
	var check: Callable = _effect_of(entry)["descriptor_error"]
	return check.call(entry, fields, targeting, skill_id)


static func _unlisted_descriptor_error(_entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) != 1:
		return "unsupported_skill_function"
	var effect: Dictionary = targeting["ranges"][fields["effect_range"]]
	if int(effect["size"]) != 1 or int(effect["data"][0][0]) <= 0: return "unsupported_skill_effect_range"
	return "unsupported_skill_formula"


static func _sequence_descriptor_error(entry: Dictionary, fields: Dictionary, _targeting: Dictionary, _skill_id: String = "") -> String:
	return RepeatedSpecialRules.definition_error(entry, fields)


static func _arrow_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, skill_id: String = "") -> String:
	if skill_id != PoisonArrowRules.ID or entry["channel"] != "special" or entry.get("fields") != fields or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) == 9 else "unsupported_skill_function"


static func _magic_damage_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if entry["channel"] != "magic" or entry.get("magic_key") not in ["wind", "fire", "water", "earth", "mind", "other"] or entry.get("damage_bounds") != "native_triangular":
		return "skill_identity_mismatch"
	return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) == 1 else "unsupported_skill_function"


## Magic status／support／stat share this identity gate; each then accepts its own function masks.
static func _magic_identity_error(entry: Dictionary, fields: Dictionary) -> String:
	if entry["channel"] != "magic" or entry.get("damage_bounds") != "native_triangular" or entry.get("fields") != fields:
		return "skill_identity_mismatch"
	return ""


static func _magic_status_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	var error := _magic_identity_error(entry, fields)
	if error != "": return error
	var mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
	return "" if mask in StatusApplication.ACCEPTED_MASKS.filter(func(bit): return bit != 1) else "unsupported_skill_formula"


static func _magic_support_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	var error := _magic_identity_error(entry, fields)
	if error != "": return error
	var mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
	return "" if SupportMagicRules.accepted(mask) else "unsupported_skill_formula"


static func _magic_stat_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	var error := _magic_identity_error(entry, fields)
	if error != "": return error
	var mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
	return "" if mask in [0x20, 0x40, 0x100, 0x4000] else "unsupported_skill_formula"


static func _special_damage_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) != 1:
		return "unsupported_skill_function"
	# Identity is the type/code pair already checked by descriptor_error; the live
	# source fields may legitimately differ from the book copy (fixtures, refreshes).
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return ""


## 弱體箭 / 獸神怒號 (Attack+Weaken) and 影纏 (Paralysis): channel1 status branches of 0x40aa80.
static func _special_status_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]) in [4, 0x1000, 0x1001] else "unsupported_skill_function"


## 萬息集氣法 (Heal) / 萬息降靈法 (HealMP) / 萬息臨界法 (Heal+HealMP) / 萬息秘孔術 (four cures): channel1 support.
static func _special_support_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if SupportMagicRules.accepted(SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])) else "unsupported_skill_formula"


## 千羽風靈壁 (DefUp) / 激怒 (AttUp) / 精神統一 (DefUp+AttUp): channel1 buffs on the shared stat applicator.
static func _special_stat_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
	if scale < 0 or scale > 1000: return "invalid_special_power_ratio"
	return "" if StatMagic.accepted(SkillTargetRules.function_mask(fields["function"], targeting["function_bits"]), "special") else "unsupported_skill_formula"


## 天鳴覺醒 (ActiveAgain) / 獅子吼 (CancelActive) / 吸血劍 (Attack+StealHP): channel1 queue and drain effects.
static func _special_utility_descriptor_error(entry: Dictionary, fields: Dictionary, targeting: Dictionary, _skill_id: String = "") -> String:
	if entry["channel"] != "special" or entry.get("damage_bounds") != "native_triangular": return "skill_identity_mismatch"
	var scale := Values.non_negative_int(fields.get("attackpow_ratio"), true)
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
	if actor.get("battle_actor_role") not in SkillTargetRules.ROLES or not BattlePresenceRules.living(actor) or Values.non_negative_int(actor.get("hp")) <= 0:
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
	if Values.non_negative_int(target.get("hp")) <= 0:
		return {"ok": false, "reason": "invalid_skill_target_hp"}
	var descriptor: Dictionary = book["skills"][skill_id]
	var effect := _effect_of(descriptor)
	var prepare_target: Callable = effect["prepare"]
	var proposal: Dictionary = prepare_target.call(caster, target, descriptor, fields, book, targeting, equipment, context)
	if not proposal["ok"]: return proposal
	return {"ok": true, "resource_payment": payment, effect["ready_key"]: proposal}


static func _prepare_utility(caster: Dictionary, target: Dictionary, _descriptor: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, context: Dictionary) -> Dictionary:
	return SpecialUtilityRules.prepare(caster, target, fields, book, targeting, equipment, context)


static func _prepare_arrow(caster: Dictionary, target: Dictionary, _descriptor: Dictionary, fields: Dictionary, book: Dictionary, _targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	return PoisonArrowRules.prepare(caster, target, fields, book, equipment)


static func _prepare_stat(caster: Dictionary, target: Dictionary, descriptor: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	return StatMagic.prepare(caster, target, fields, book, targeting, equipment, descriptor["channel"])


static func _prepare_support(caster: Dictionary, target: Dictionary, descriptor: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	return SupportMagicRules.prepare(caster, target, fields, book, targeting, equipment, descriptor["channel"])


static func _prepare_special_status(caster: Dictionary, target: Dictionary, _descriptor: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	return SpecialStatusRules.prepare(caster, target, fields, book, targeting, equipment)


static func _prepare_magic(caster: Dictionary, target: Dictionary, descriptor: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	if descriptor.get("magic_key") == "other": return OtherMagicRules.prepare(caster, target, fields, book, targeting, equipment)
	return StatusApplication.prepare(caster, target, fields, book, targeting, equipment)


static func _prepare_special_damage(caster: Dictionary, target: Dictionary, _descriptor: Dictionary, fields: Dictionary, book: Dictionary, _targeting: Dictionary, equipment: Dictionary, _context: Dictionary) -> Dictionary:
	return Special.prepare(caster, target, fields, book, equipment)


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
	var resolve_target: Callable = _effect_of(descriptor)["resolve"]
	return resolve_target.call(caster, target, skill_id, descriptor, ready, source, equipment)


## native_magic_status: 0x40aa80 status branches on the StatusApplicationRules proposal.
static func _resolve_status(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	return _status_result(caster, target, skill_id, descriptor, ready, StatusApplication.resolve(ready["status"], target, rng, Callable(), equipment))


## native_magic_damage: the same applicator; the receipt's hit is the 0x40a7b0 proc0 hit check.
static func _resolve_magic_damage(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	var result := _resolve_status(caster, target, skill_id, descriptor, ready, rng, equipment)
	var receipt: Dictionary = result["receipt"]
	receipt["hit"] = bool(receipt["native_damage_roll"]["hit_check_passed"])
	receipt["formula_source"] = "0x40a7b0_proc0_and_0x40ab55_hp_cap"
	return result


## native_special_poison (毒箭).
static func _resolve_arrow(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, _equipment: Dictionary = {}) -> Dictionary:
	var resolved: Dictionary = PoisonArrowRules.resolve(ready["arrow"], target, rng)
	var result := _status_result(caster, target, skill_id, descriptor, ready, resolved)
	var receipt: Dictionary = result["receipt"]
	receipt.erase("magic_key")
	receipt.erase("magic_name")
	receipt.merge({"special_key": "poison_arrow", "skill_name": descriptor["name"], "native_poison_rolls": resolved["native_poison_rolls"],
		"formula_source": "0x40a7b0_channel1_and_0x40aa80_to_0x40b831"}, true)
	return result


## native_special_status: channel1 status branches.
static func _resolve_special_status(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
	var result := _status_result(caster, target, skill_id, descriptor, ready, SpecialStatusRules.resolve(ready["status"], target, rng, equipment))
	var receipt: Dictionary = result["receipt"]
	receipt.erase("magic_key")
	receipt.erase("magic_name")
	receipt.merge({"special_key": "special_status", "skill_name": descriptor["name"],
		"formula_source": "0x40aa80_channel1_status_branches_and_0x40a7b0_channel1"}, true)
	return result


static func _status_result(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, resolved: Dictionary) -> Dictionary:
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
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": resolved["hit_bonus_after"]},
		"target_changes": resolved["target_changes"], "receipt": receipt}


## One special-damage target (氣刃斬 alone, or each unit inside an area special's
## effect footprint): original 0x40a7b0 channel1/proc0 roll and capped HP application.
static func _resolve_special_damage(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, _equipment: Dictionary = {}) -> Dictionary:
	# aniProcessHitMissMulti settles one 0x40b8f0 per op 72 (MultiHitSpecialRules).
	if MultiHitSpecialRules.strikes(descriptor) > 1: return MultiHitSpecialRules.resolve(caster, target, skill_id, descriptor, ready, rng)
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


static func _resolve_utility(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, _equipment: Dictionary = {}) -> Dictionary:
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


static func _resolve_stat_magic(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant, equipment: Dictionary = {}) -> Dictionary:
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
	var descriptor: Dictionary = book["skills"][skill_id]
	var effect := _effect_of(descriptor)
	if effect.has("prepare_cast"):
		var whole: Callable = effect["prepare_cast"]
		return whole.call(caster, center, units, fields, book, targeting, equipment, origin, map_size, payment, center_coord, terrain)
	if not effect["area"]:
		if center_coord != null and (not center_coord is Vector2i or not SkillTargetRules.Footprint.contains(center,center_coord)): return {"ok": false, "reason": "unsupported_skill_center"}
		var primary := prepare(caster, center, skill_id, fields, book, targeting, equipment, origin, map_size, context)
		if not primary["ok"]: return primary
		return {"ok": true, "targets": [center], "prepared": [primary]}
	var cast_cells := SkillTargetRules.cells(origin, fields, targeting, map_size, terrain)
	var cast_center: Variant = SkillTargetRules.Footprint.contact(center, cast_cells) if center_coord == null else center_coord
	if not cast_center is Vector2i or not cast_cells.has(cast_center): return {"ok": false, "reason": "out_of_range"}
	if not BattlePresenceRules.living(center): return {"ok": false, "reason": "target_unavailable"}
	if center.get("battle_actor_role") not in SkillTargetRules.ROLES: return {"ok": false, "reason": "unsupported_target_role"}
	if not SkillTargetRules.side_matches(caster, center, fields, targeting): return {"ok": false, "reason": "not_ally" if SkillTargetRules.is_support(fields, targeting) else "not_enemy"}
	var footprint := SkillTargetRules.cast_footprint(origin, cast_center, fields, targeting, map_size, terrain)
	var targets: Array = []
	var prepared: Array = []
	var seen := {}
	var prepare_target: Callable = effect["prepare"]
	var ready_key: String = effect["ready_key"]
	var subset: bool = effect.get("subset", false)
	var useful := false
	# Stable roster order is the current adapter policy; the original engine's
	# cross-object visitation order is not inferred from RANGE occupancy values.
	for unit in units:
		if not unit is Dictionary or not unit.get("coord") is Vector2i:
			return {"ok": false, "reason": "invalid_skill_roster"}
		if not SkillTargetRules.Footprint.overlaps(unit, footprint) or not BattlePresenceRules.living(unit): continue
		if unit.get("battle_actor_role") not in SkillTargetRules.ROLES:
			return {"ok": false, "reason": "unsupported_target_role"}
		if not SkillTargetRules.area_side_matches(caster, unit, fields, targeting): continue
		var id := str(unit.get("id", ""))
		if id == "" or seen.has(id): return {"ok": false, "reason": "invalid_target_identity"}
		seen[id] = true
		var exp_error := ExperienceRules.actor_error(unit)
		if exp_error != "": return {"ok": false, "reason": exp_error}
		var status: Dictionary = prepare_target.call(caster, unit, descriptor, fields, book, targeting, equipment, context)
		if not status["ok"]: return status
		useful = useful or bool(status.get("useful", true))
		if subset and not bool(status["useful"]): continue # 0x4075a0/0x407550 would return 0 for this unit
		targets.append(unit)
		prepared.append({"ok": true, "resource_payment": payment, ready_key: status})
	if not seen.has(str(center["id"])): return {"ok": false, "reason": "missing_skill_center"}
	if not useful: return {"ok": false, "reason": "skill_has_no_effect"}
	if subset and not targets.any(func(unit): return unit["id"] == center["id"]): return {"ok": false, "reason": "skill_has_no_effect"}
	return {"ok": true, "targets": targets, "prepared": prepared, "cast_center": cast_center}


static func resolve_cast(caster: Dictionary, center: Dictionary, units: Array, skill_id: String, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, rng: Variant = null, center_coord: Variant = null, context: Dictionary = {}) -> Dictionary:
	var ready := prepare_cast(caster, center, units, skill_id, fields, book, targeting, equipment, origin, map_size, center_coord, context)
	if not ready["ok"]: return ready
	var source: Variant = rng
	if source == null:
		source = RandomNumberGenerator.new()
		source.randomize()
	var descriptor: Dictionary = book["skills"][skill_id]
	var effect := _effect_of(descriptor)
	if effect.has("resolve_cast"):
		var whole: Callable = effect["resolve_cast"]
		return whole.call(caster, ready, descriptor, source)
	if not effect["area"]:
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
	var resolve_target: Callable = effect["resolve"]
	var ready_key: String = effect["ready_key"]
	var hit_input: String = effect["hit_bonus_input"]
	var caster_effects: bool = effect.get("caster_effects", false)
	var turn_effects: Array = []
	var gold_effects: Array = []
	var stolen_items: Array = []
	var killed := false
	for index in range(ready["targets"].size()):
		var target: Dictionary = ready["targets"][index]
		var prepared: Dictionary = ready["prepared"][index].duplicate(true)
		# A miss on an earlier footprint target raises the compensation the next
		# target's hit check reads within this cast.
		if hit_input != "": prepared[ready_key][hit_input]["hit_bonus"] = working_caster["hit_bonus_accum"]
		var result: Dictionary = resolve_target.call(working_caster, target, skill_id, descriptor, prepared, source, equipment)
		if caster_effects:
			if result["caster_changes"].has("hp"): working_caster["hp"] = result["caster_changes"]["hp"]
			turn_effects.append_array(result["turn_effects"])
			gold_effects.append_array(result["gold_effects"])
			stolen_items.append_array(result["receipt"]["stolen_items"])
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
	if caster_effects:
		if int(working_caster["hp"]) != int(caster["hp"]): caster_changes["hp"] = working_caster["hp"]
		primary["turn_effects"] = turn_effects
		primary["gold_effects"] = gold_effects
		primary["stolen_items"] = stolen_items
	return {"ok": true, "caster_changes": caster_changes, "targets": changes, "target_changes": center_changes, "receipt": primary, "turn_effects": turn_effects, "gold_effects": gold_effects}

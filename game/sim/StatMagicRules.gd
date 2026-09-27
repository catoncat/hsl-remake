extends RefCounted
## Original positive-stat proposals. No live mutation or random preview.
## Channel1 (special) buffs (千羽風靈壁 DefUp, 激怒 AttUp, 精神統一 DefUp+AttUp) reuse the
## same 0x40aa80 branches; only the 0x40a7b0 helper channel differs.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_stat_magic.md
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const NativeMagicRollRules = preload("res://game/sim/NativeMagicRollRules.gd")
const SpecialDamageRules = preload("res://game/sim/SpecialDamageRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const Progression = preload("res://game/sim/ProgressionRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const Values = preload("res://game/sim/Values.gd")
const KINDS := {0x20: "defense_up", 0x40: "attack_up", 0x100: "resist_up", 0x4000: "dispel"}
## 0x40aa80 visits DefUp (0x20) before AttUp (0x40); 0x60 runs both blocks in that order.
## AllUp (0x100, 魔障壁): proc1 roll (value discarded, compensation kept), rand(4)+2 turns,
## rand(14)+7 strength added to the +0x4a word (cap 20) — no second helper roll — then 0x448840.
const SEQUENCES := {0x20: ["defense_up"], 0x40: ["attack_up"], 0x60: ["defense_up", "attack_up"], 0x100: ["resist_up"], 0x4000: ["dispel"]}


static func accepted(mask: int, channel: String) -> bool:
	return SEQUENCES.has(mask) and (channel == "magic" or mask != 0x4000)


static func kinds_for(mask: int) -> Array:
	return SEQUENCES.get(mask, [])


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, channel: String = "magic") -> Dictionary:
	for actor in [caster, target]:
		for error in [StatusEffectRules.input_error(actor), Progression.refresh_input_error(actor, equipment)]:
			if error != "": return {"ok": false, "reason": error}
	var mask := SkillTargetRules.function_mask(fields.get("function"), targeting["function_bits"])
	if not accepted(mask, channel): return {"ok": false, "reason": "unsupported_stat_magic"}
	var kinds: Array = kinds_for(mask)
	var kind: String = kinds[0]
	var modifiers := StatusApplicationRules.modifiers(caster, book, equipment)
	if not modifiers["ok"]: return modifiers
	var target_modifiers := StatusApplicationRules.modifiers(target, book, equipment)
	if not target_modifiers["ok"]: return target_modifiers
	var limits: PackedStringArray = fields["damage"].split(",")
	var input := {"low": int(limits[0]), "high": int(limits[1]), "hit_ratio": int(fields["hit_ratio"]),
		"status_hit_ratio": 0, "level": int(caster["level"]), "mind": int(StatusEffectRules.weakened_attributes(caster)["mind"]),
		"magic_attack": int(caster["combat_profile"]["live_magic_attack"]), "hit_bonus": int(caster["hit_bonus_accum"]),
		"magic_hit_bonus": modifiers["magic_hit_bonus"], "resistance": 0, "no_attack": target_modifiers["no_attack"],
		"channel": 0 if channel == "magic" else 1, "proc": 1 if kind in ["defense_up", "resist_up"] else 3}
	if channel == "special":
		# Channel1 proc1 adds level/dex/con/mind terms and attackpow_ratio; proc3 has no +0xd4 magic-hit term.
		var special := SpecialDamageRules.prepare(caster, target, fields, book, equipment)
		if not special["ok"]: return special
		input.merge(special["input"], true)
		input["magic_hit_bonus"] = 0
	var useful := false
	for each in kinds:
		var current := StatEnhancementRules.word(target, each) if each != "dispel" else 0
		useful = useful or ((int(target["status_flags"]) & 0x30) != 0 if each == "dispel" else ((current & 65535) < 9 or (current >> 16) < (96 if each == "attack_up" else StatEnhancementRules.RESIST_MAX if each == "resist_up" else 100)))
	return {"ok": true, "kind": kind, "kinds": kinds, "channel": channel, "roll_input": input, "useful": useful}


static func _roll(ready: Dictionary, input: Dictionary, rng: Variant) -> Dictionary:
	if ready.get("channel", "magic") == "special" and int(input["proc"]) == 1: return SpecialDamageRules.roll(input, rng)
	return NativeMagicRollRules.roll(input, rng)


static func resolve(ready: Dictionary, target: Dictionary, hit_bonus: int, equipment: Dictionary, rng: Variant) -> Dictionary:
	var input: Dictionary = ready["roll_input"].duplicate(true)
	input["hit_bonus"] = hit_bonus
	var rolls: Array = []
	var durations: Array = []
	var effects: Array = []
	var contribution := 0
	var actor := target
	for kind in ready.get("kinds", [ready["kind"]]):
		var result: Dictionary
		if kind == "dispel": result = StatEnhancementRules.dispel(actor)
		elif kind == "resist_up":
			# 0x40b1fb: proc1 helper (value discarded, compensation kept), rand(4)+2 turns,
			# then rand(14)+7 strength without a second helper call.
			input["proc"] = 1
			var first := _roll(ready, input, rng)
			input["hit_bonus"] = first["hit_bonus_after"]
			rolls.append(first)
			var duration := CoreCombatRules.rand_range(4, rng) + 2
			var strength := CoreCombatRules.rand_range(14, rng) + StatEnhancementRules.RESIST_MIN
			rolls.append({"value": strength, "hit_check_passed": true, "source": "0x40b24a_rand14_plus7"})
			result = StatEnhancementRules.apply(actor, kind, duration, strength)
			durations.append(duration)
		else:
			# First magnitude is discarded, but its hit compensation and draws remain.
			# DefUp starts with proc1; AttUp starts with proc3. Both end with proc3.
			input["proc"] = 1 if kind == "defense_up" else 3
			var first := _roll(ready, input, rng)
			input["hit_bonus"] = first["hit_bonus_after"]
			rolls.append(first)
			var duration := CoreCombatRules.rand_range(4, rng) + 2
			input["proc"] = 3
			var magnitude := _roll(ready, input, rng)
			rolls.append(magnitude)
			input["hit_bonus"] = int(magnitude["hit_bonus_after"])
			result = StatEnhancementRules.apply(actor, kind, duration, int(magnitude["value"]))
			durations.append(duration)
		actor = result["actor"]
		effects.append_array(result["effects"])
		contribution += int(result["contribution"])
	hit_bonus = int(input["hit_bonus"])
	var refreshed := Progression.refresh_growth_stats(actor, equipment)
	var changes := {}
	# Flat combat buffs cannot change vitals. In particular a self-cast target
	# must not overwrite its independently committed MP payment with pre-cast MP.
	for key in ["status_flags", "status_counters", "combat_profile", "live_speed", "move_point"]:
		changes[key] = refreshed[key]
	return {"target_changes": changes, "effects": effects, "native_contribution": contribution,
		"hit_bonus_after": hit_bonus, "rolls": rolls, "sampled_duration": durations[0] if not durations.is_empty() else 0,
		"sampled_durations": durations,
		"stats_before": {"attack": target["combat_profile"]["live_attack_damage"], "defense": target["combat_profile"]["live_defense"]},
		"stats_after": {"attack": refreshed["combat_profile"]["live_attack_damage"], "defense": refreshed["combat_profile"]["live_defense"]}}


static func receipt_error(receipt: Dictionary, book: Dictionary, children: bool = true) -> String:
	var entry: Dictionary = book.get("skills", {}).get(receipt.get("skill_id", ""), {})
	if entry.get("damage_policy") not in ["native_magic_stat", "native_special_stat"]:
		return "unexpected_stat_receipt" if receipt.has("stat_effects") else ""
	if not receipt.get("stat_effects") is Array or not receipt.get("defender_before") is Dictionary:
		return "missing_stat_receipt"
	var before: Dictionary = receipt["defender_before"]
	if StatusEffectRules.input_error(before) != "" or not before.get("combat_profile") is Dictionary: return "invalid_stat_receipt_before"
	var kinds: Array = [entry["magic_key"]] if entry["damage_policy"] == "native_magic_stat" else kinds_for(_mask_from_name(str(entry["fields"]["function"])))
	if kinds.is_empty(): return "invalid_stat_receipt_kind"
	var proposal := {"actor": before, "effects": [], "contribution": 0}
	var rolls: Variant = receipt.get("native_stat_rolls")
	var durations: Variant = receipt.get("sampled_durations", [receipt.get("sampled_duration")])
	if not durations is Array: return "invalid_stat_receipt_duration"
	var buffs := 0
	for index in range(kinds.size()):
		var kind: String = kinds[index]
		var step: Dictionary
		if kind == "dispel": step = StatEnhancementRules.dispel(proposal["actor"])
		else:
			if not rolls is Array or rolls.size() < 2 * (buffs + 1) or not rolls[2 * buffs + 1] is Dictionary or not Values.is_integer_in(rolls[2 * buffs + 1].get("value"), 0, 100000): return "invalid_stat_receipt_rolls"
			if durations.size() <= buffs or not Values.is_integer_in(durations[buffs], 0, 5) or int(durations[buffs]) < 2: return "invalid_stat_receipt_duration"
			step = StatEnhancementRules.apply(proposal["actor"],kind,int(durations[buffs]),int(rolls[2 * buffs + 1]["value"]))
			buffs += 1
		proposal["actor"] = step["actor"]
		proposal["effects"].append_array(step["effects"])
		proposal["contribution"] += int(step["contribution"])
	if rolls is Array and rolls.size() != 2 * buffs: return "invalid_stat_receipt_rolls"
	if proposal["effects"] != receipt["stat_effects"] or proposal["contribution"] != receipt.get("native_contribution"): return "inconsistent_stat_receipt_effects"
	if not receipt.get("stats_before") is Dictionary or not receipt.get("stats_after") is Dictionary: return "missing_stat_receipt_values"
	for key in ["attack","defense"]:
		var field := "live_attack_damage" if key == "attack" else "live_defense"
		var initial: Variant = before["combat_profile"].get(field)
		if not Values.is_integer_in(initial, 0, 10000000) or receipt["stats_before"].get(key) != initial: return "invalid_stat_receipt_values"
		var expected := int(initial) - StatEnhancementRules.power(before,key+"_up") + StatEnhancementRules.power(proposal["actor"],key+"_up")
		if receipt["stats_after"].get(key) != expected: return "inconsistent_stat_receipt_values"
	if receipt.get("defender_hp_after") != receipt.get("defender_hp_before") or receipt.get("actual_damage") != 0: return "invalid_stat_receipt_damage"
	var payment: Variant = receipt.get("resource_payment")
	if not payment is Dictionary or payment.get("resource") != ("mp" if entry["channel"] == "magic" else "stamina"): return "invalid_stat_receipt_payment"
	for key in ["before","after","amount"]:
		if not Values.is_integer_in(payment.get(key), 0, 1000000): return "invalid_stat_receipt_payment"
	if payment["amount"] < 1 or payment["before"]-payment["after"] != payment["amount"]: return "inconsistent_stat_receipt_payment"
	if children:
		var affected: Variant = receipt.get("affected_targets")
		if not affected is Array or affected.is_empty(): return "missing_stat_receipt_targets"
		for child in affected:
			if not child is Dictionary: return "invalid_stat_receipt_targets"
			var error := receipt_error(child,book,false)
			if error != "": return error
	return ""


## The skill book carries source rows but not the alias table; the three buff
## function spellings are fixed source text (mag-spc.h).
static func _mask_from_name(expression: String) -> int:
	var mask := 0
	for raw in expression.split(","):
		mask |= {"magicFun_DefUp": 0x20, "magicFun_AttUp": 0x40, "magicFun_AllUp": 0x100, "magicFun_ClearAtDfUp": 0x4000}.get(raw.strip_edges(), 0)
	return mask

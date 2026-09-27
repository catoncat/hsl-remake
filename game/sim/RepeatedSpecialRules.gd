extends RefCounted
## Moon Dance: immutable, target-major receiver proposals. PlayLoop commits once.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_moon_dance.md
const ID := "special:magicOTHER:magicCode06"
const PULSES := 5
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SpecialDamageRules = preload("res://game/sim/SpecialDamageRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")


static func definition_error(entry: Dictionary, fields: Dictionary) -> String:
	if entry.get("channel") != "special" or fields.get("type") != "magicOTHER" or fields.get("code") != "magicCode06" or entry.get("fields") != fields:
		return "skill_identity_mismatch"
	var sequence: Variant = entry.get("sequence")
	if not sequence is Dictionary or sequence.get("pulses") != PULSES or sequence.get("target_order") != "coverage_row_major_unique" or sequence.get("kill_accounting") != "after_all_targets":
		return "missing_special_sequence"
	if fields.get("range") != "range0Cell" or fields.get("effect_range") != "range1CellFull" or fields.get("function") != "magicFun_Attack":
		return "unsupported_special_sequence_geometry"
	return ""


## `terrain`: the player's skill terrain when the cast is a player command
## (RangePropagationRules.player_skill_terrain) — the area is then the 0x4100e0 mode 2 flood.
static func prepare(caster: Dictionary, primary: Dictionary, units: Array, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, origin: Vector2i, map_size: Vector2i, payment: Dictionary, center: Variant, terrain: Dictionary = {}) -> Dictionary:
	if center != null and center != origin: return {"ok": false, "reason": "out_of_range"}
	var area := SkillTargetRules.cast_footprint(origin, origin, fields, targeting, map_size, terrain)
	var targets: Array = []
	var prepared: Array = []
	var ids := {}
	# 0x4104d0 scans coverage row-major, returning each object pointer once.
	for cell in area:
		var unit := SkillTargetRules.Footprint.unit_at(units, cell)
		if unit.is_empty() or ids.has(unit["id"]) or not SkillTargetRules._living(unit): continue
		if unit.get("battle_actor_role") not in SkillTargetRules.ROLES: return {"ok": false, "reason": "unsupported_target_role"}
		if not SkillTargetRules.area_side_matches(caster, unit, fields, targeting): continue
		for error in [ExperienceRules.actor_error(unit), StatusEffectRules.input_error(unit), CoreCombatRules.input_error(unit)]:
			if error != "": return {"ok": false, "reason": error}
		var special := SpecialDamageRules.prepare(caster, unit, fields, book, equipment)
		if not special["ok"]: return special
		ids[unit["id"]] = true
		targets.append(unit)
		prepared.append({"ok": true, "resource_payment": payment, "special": special})
	if targets.is_empty(): return {"ok": false, "reason": "skill_has_no_effect"}
	if not ids.has(primary.get("id")): return {"ok": false, "reason": "out_of_range"}
	return {"ok": true, "targets": targets, "prepared": prepared, "cast_center": origin}


static func resolve(caster: Dictionary, ready: Dictionary, entry: Dictionary, rng: Variant) -> Dictionary:
	var payment: Dictionary = ready["prepared"][0]["resource_payment"]
	var owner := caster.duplicate(true)
	owner["coord"] = ready["cast_center"]
	var bonus := int(owner["hit_bonus_accum"])
	var initial_word := int(owner["kill_chain_word"])
	var segments: Array = []
	var summaries: Array = []
	var changes: Array = []
	var kills := 0
	var total_damage := 0
	for index in range(ready["targets"].size()):
		var target: Dictionary = ready["targets"][index].duplicate(true)
		var initial_hp := int(target["hp"])
		var first: Dictionary = {}
		for pulse in range(PULSES):
			var input: Dictionary = ready["prepared"][index]["special"]["input"].duplicate(true)
			input["hit_bonus"] = bonus
			var roll := SpecialDamageRules.roll(input, rng)
			bonus = int(roll["hit_bonus_after"])
			var before := int(target["hp"])
			var damage := mini(before, int(roll["value"]))
			var after := before - damage
			# Neither target death nor earlier target kills advance the chain here.
			var basis := ExperienceRules.from_contribution(damage, int(owner["level"]), int(target["level"]), after, int(target["kill_exp"]), initial_word, rng)
			var killed := before > 0 and after == 0
			basis.merge({"killed": killed, "kills_added": 1 if killed else 0, "kill_word_after": initial_word,
				"deferred_kill_accounting": true})
			var segment := {"skill_id": ID, "skill_name": entry["name"], "attacker_id": owner["id"], "defender_id": target["id"],
				"pulse": pulse + 1, "target_index": index, "segment_index": segments.size(), "hit": roll["hit_check_passed"],
				"hit_rate": roll["hit_rate"], "hit_roll": roll["hit_roll"], "native_damage_roll": roll,
				"damage": damage, "actual_damage": damage, "native_contribution": damage,
				"defender_hp_before": before, "defender_hp_after": after, "experience_basis": basis,
				"resource_payment": payment, "payment_applied": segments.is_empty(), "silent_after_defeat": before == 0,
				"attacker_before": CoreCombatRules.receipt_vitals(owner), "defender_before": CoreCombatRules.receipt_vitals(target),
				"cast_center": ready["cast_center"], "formula_source": "0x403968_opcode17_to_0x40b8f0"}
			if first.is_empty(): first = segment.duplicate(true)
			segments.append(segment)
			target["hp"] = after
			owner[payment["resource"]] = payment["after"]
			if killed: kills += 1
		# All five callbacks run, including original draws after HP reaches zero.
		first["damage"] = initial_hp - int(target["hp"])
		first["actual_damage"] = first["damage"]
		first["native_contribution"] = first["damage"]
		first["defender_hp_after"] = target["hp"]
		first["hit"] = int(first["damage"]) > 0
		first.erase("experience_basis")
		summaries.append(first)
		total_damage += int(first["damage"])
		changes.append({"id": target["id"], "changes": {"hp": target["hp"], "defeated": int(target["hp"]) == 0}})
	var receipt: Dictionary = summaries[0].duplicate(true)
	receipt.merge({"special_segments": segments, "affected_targets": summaries, "total_damage": total_damage,
		"pulses_per_target": PULSES, "sequence_policy": "target_major_deferred_kills", "counter": {}})
	return {"ok": true, "receipt": receipt, "targets": changes, "target_changes": changes[0]["changes"],
		"caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": bonus,
			"kill_chain_word": (initial_word | ExperienceRules.KILL_MARK) + 1 if kills > 0 else initial_word,
			"kill_count": int(caster["kill_count"]) + kills}}


static func receipt_error(receipt: Dictionary) -> String:
	if receipt.get("skill_id") != ID: return ""
	var parts: Variant = receipt.get("special_segments")
	if not parts is Array or parts.is_empty() or parts.size() % PULSES != 0 or receipt.get("sequence_policy") != "target_major_deferred_kills":
		return "invalid_saved_special_sequence"
	var seen := {}; var previous_hp := -1; var target_id := ""
	for index in range(parts.size()):
		var part: Variant = parts[index]
		if not part is Dictionary or part.get("skill_id") != ID or part.get("attacker_id") != receipt.get("attacker_id") or part.get("resource_payment") != receipt.get("resource_payment"):
			return "inconsistent_saved_special_sequence"
		if index % PULSES == 0:
			target_id = str(part.get("defender_id", ""))
			if target_id == "" or seen.has(target_id): return "duplicate_saved_special_target"
			seen[target_id] = true
			previous_hp = int(part.get("defender_hp_before", -1))
		if part.get("defender_id") != target_id or part.get("pulse") != index % PULSES + 1 or part.get("segment_index") != index or part.get("target_index") != index / PULSES:
			return "invalid_saved_special_order"
		if previous_hp < 0 or part.get("defender_hp_before") != previous_hp or int(part.get("damage", -1)) < 0 or int(part["damage"]) > previous_hp or part.get("defender_hp_after") != previous_hp - int(part["damage"]):
			return "inconsistent_saved_special_hp"
		if part.get("payment_applied") != (index == 0) or part.get("silent_after_defeat") != (previous_hp == 0): return "inconsistent_saved_special_phase"
		previous_hp = int(part["defender_hp_after"])
	return ""

extends RefCounted
## Multi-hit specials: one 0x40b8f0 settlement per op 72 of the defense objects.
## The defender script's aniProcessHitMissMulti (phase 18, 0x4047af) settles one strike per
## pending op 72 (0x4047d5 0x4c6f68--, then 0x4047e9): each strike clears [0x4c1418] and the
## HP／MP change words, calls 0x40b8f0 → 0x40aa80 (its own hit roll 0x40a7b0, damage, HP cap
## and 0x40a5d0 EXP conversion at 0x40b853) and adds the returned EXP to 0x4c13f0／0x4c2c7c.
## A strike on a zero-HP target still draws the hit and damage rolls; its capped damage and
## contribution are zero, so it converts no EXP and kills nothing (as Moon Dance's tail).
## The strike count is the number of defense-object instances whose objcomd program runs op 72
## (objcomd_motion.json `multi_hit`); every such object is inserted by a non-hit insert, so the
## count does not depend on the roll.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
const Special = preload("res://game/sim/SpecialDamageRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")

## Defense script (SPECIAL.TXT defense_code) → op 72 instances it inserts:
## specCode08／124 慌雨斬 Special04_02／62_02 ×4 + _03 ×1; specCode12 無想冥殺 Special06_06 ring ×8;
## specCode48 星辰落牙破 Special24_02 ×6; specCode60／112 殘影亂斬 Special30／56_01..05 2+2+1+1+1;
## specCode68／108 百裂突刺 Special34／54_03 ×8; specCode100 血之宴 Special50_01 2+2+8.
const STRIKES := {"specCode08": 5, "specCode124": 5, "specCode12": 8, "specCode48": 6, "specCode60": 7,
	"specCode112": 7, "specCode68": 8, "specCode108": 8, "specCode100": 12}


static func strikes(descriptor: Dictionary) -> int:
	var fields: Variant = descriptor.get("fields")
	if not fields is Dictionary: return 1
	return int(STRIKES.get(str(fields.get("defense_code", "")), 1))


## One target's strikes in settlement order. `caster` carries the running hit compensation,
## level and kill-chain word (unchanged within the defender script); `ready.special.input` is
## the channel1 input from SpecialDamageRules.prepare.
static func resolve(caster: Dictionary, target: Dictionary, skill_id: String, descriptor: Dictionary, ready: Dictionary, rng: Variant) -> Dictionary:
	var count := strikes(descriptor)
	var input: Dictionary = ready["special"]["input"].duplicate(true)
	var bonus := int(input["hit_bonus"])
	var hp := int(target["hp"])
	var parts: Array = []
	var total := 0
	var any_hit := false
	for index in range(count):
		input["hit_bonus"] = bonus
		var rolled := Special.roll(input, rng)
		bonus = int(rolled["hit_bonus_after"])
		var before := hp
		var damage := mini(before, int(rolled["value"]))
		hp = before - damage
		var basis := ExperienceRules.from_contribution(damage, int(caster["level"]), int(target["level"]), hp, int(target["kill_exp"]), int(caster["kill_chain_word"]), rng)
		any_hit = any_hit or bool(rolled["hit_check_passed"])
		total += damage
		parts.append({"segment": index + 1, "hit": rolled["hit_check_passed"], "hit_rate": rolled["hit_rate"], "hit_roll": rolled["hit_roll"],
			"native_damage_roll": rolled, "damage": damage, "actual_damage": damage, "native_contribution": damage,
			"defender_hp_before": before, "defender_hp_after": hp, "experience_points": int(basis["points"]), "experience_draws": basis["draws"]})
	var payment: Dictionary = ready["resource_payment"]
	var first: Dictionary = parts[0]
	var receipt := {"skill_id": skill_id, "attacker_id": str(caster["id"]), "defender_id": str(target["id"]),
		"hit": any_hit, "hit_rate": first["hit_rate"], "hit_roll": first["hit_roll"],
		"damage": total, "actual_damage": total, "native_contribution": total, "native_damage_roll": first["native_damage_roll"],
		"defender_hp_before": int(target["hp"]), "defender_hp_after": hp, "hit_segments": parts,
		"resource_payment": payment, "skill_name": descriptor["name"],
		"attacker_before": CoreCombatRules.receipt_vitals(caster), "defender_before": CoreCombatRules.receipt_vitals(target),
		"formula_source": "0x4047c7_per_op72_0x4047e9_to_0x40b8f0"}
	return {"ok": true, "caster_changes": {payment["resource"]: payment["after"], "hit_bonus_accum": bonus},
		"target_changes": {"hp": hp, "defeated": hp == 0}, "receipt": receipt}


## A saved receipt (and its area targets) keeps a continuous per-strike HP chain whose total is
## the receipt's damage.
static func receipt_error(receipt: Variant) -> String:
	if not receipt is Dictionary: return ""
	var parts: Array = [receipt]
	parts.append_array(receipt.get("affected_targets", []))
	for part in parts:
		if not part is Dictionary or not part.has("hit_segments"): continue
		var segments: Variant = part["hit_segments"]
		if not segments is Array or segments.is_empty(): return "invalid_saved_multi_hit"
		var hp := int(part.get("defender_hp_before", -1))
		var total := 0
		for index in range(segments.size()):
			var segment: Variant = segments[index]
			if not segment is Dictionary or segment.get("segment") != index + 1: return "invalid_saved_multi_hit_order"
			var damage := int(segment.get("damage", -1))
			if hp < 0 or segment.get("defender_hp_before") != hp or damage < 0 or damage > hp or segment.get("defender_hp_after") != hp - damage:
				return "inconsistent_saved_multi_hit_hp"
			hp -= damage
			total += damage
		if part.get("defender_hp_after") != hp or int(part.get("damage", -1)) != total: return "inconsistent_saved_multi_hit_total"
	return ""

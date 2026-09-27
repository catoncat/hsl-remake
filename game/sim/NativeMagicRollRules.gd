extends RefCounted
## Pure positive-domain 0x40a7b0 magic paths, checked against isolated native returns.
## See original_status_rolls.json. The supplied RNG follows explicit native bounds.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_rolls.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_magic_damage.md
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")


static func roll(input: Dictionary, rng: Variant) -> Dictionary:
	var status_check := (int(input["proc"]) & 4) != 0
	var hit := int(input["status_hit_ratio"]) if status_check else int(input["hit_ratio"]) + int(input["hit_bonus"]) + int(input["magic_hit_bonus"])
	var draw := CoreCombatRules.rand_range(100, rng) + 1
	var bonus := int(input["hit_bonus"])
	if not bool(input["no_attack"]) and draw > hit:
		return {"value": 0, "hit_bonus_after": bonus if status_check else bonus + draw / 10,
			"hit_check_passed": false, "hit_rate": hit, "hit_roll": draw}
	if not status_check: bonus = 0
	var half := (int(input["high"]) - int(input["low"])) / 2
	var sampled := int(input["low"]) + half - CoreCombatRules.rand_range(half + 1, rng) + CoreCombatRules.rand_range(half + 1, rng)
	var value := sampled
	if (int(input["proc"]) & 2) == 0:
		var mind := int(input["mind"])
		mind = mind / 2 if mind < 36 else (mind - 36) / 4 + 18
		value = (clampi(int(input["level"]), 1, 80) + mind + sampled) * int(input["magic_attack"]) / 100
	if value < 3: value += 3 * ((5 - value) / 3)
	if (int(input["proc"]) & 1) == 0:
		value = value * (100 - mini(80, int(input["resistance"]))) / 100
	return {"value": value, "hit_bonus_after": bonus, "hit_check_passed": true,
		"hit_rate": hit, "hit_roll": draw, "sampled": sampled}

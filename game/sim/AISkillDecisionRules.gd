extends RefCounted
## Original kernels; caller adapters and unsupported effects stay separate.
## docs/evidence_packets/static_reverse/original_ai_skills.md
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_skills.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")


static func buckets(mask: int, area: bool) -> Array:
	var result: Array = []
	if mask & 0x501d: result.append(3 if area else 4)
	if mask & 2: result.append(1 if area else 2)
	if mask & 0x160: result.append(5)
	if mask & 0x501c: result.append(6)
	if mask & 0x2e00: result.append(7)
	result.sort()
	return result


static func area_order(flag: int, rng: Variant) -> Dictionary:
	var draws: Array = []
	var roll := recorded_draw(100, rng, draws) + 1
	var first := roll > 30 if flag != 0 else roll <= 30
	return {"area_first": first, "order": [3, 4] if first else [4, 3], "draws": draws,
		"source": "0x40d4e0"}


## MAGIC buckets: 0x40c770 (use_ratio at descriptor+0x28). SPECIAL buckets: 0x40dd80 (buckets at
## +0x38.., use_ratio at descriptor+0x20) runs the same rand(32)%count start and per-node roll.
## 0x40c770 replaces the rand(100)+1 roll with 0 for a useful MAGIC buff (bucket 5,
## 0x40c8dd..0x40c8e1) or cure (bucket 7, 0x40c89d) row, so use_ratio is never read there; the
## rand(100) is still consumed. Bucket 5/7 callers pass only rows useful for the primary: bucket 7
## matches (0x40c89d gives a non-useful cure row 200), bucket 5 deviates (provisional) since
## 0x40c770 keeps the plain roll against use_ratio for a row whose buff the target already holds.
## In buckets 3/4 (0x40c910..0x40c94a) a row whose function
## (0x409850) holds 0x4000 (退魔, `test ah,0x40`) takes roll 0 when the caller's mask
## (0x40c2d0(target) = target +0x24 & 0x70) holds 0x60 (defense_up 0x20 / resist_up 0x40), else
## 200 (`and cl,0x60; neg; sbb; and cl,0x38; add 0xc8`): always taken or never, the rand(100)
## still drawn; every other bucket 3/4 row compares use_ratio. `mask` -1 (none passed) keeps the
## plain roll; `functions` holds each row's function mask. 0x40dd80 keeps the roll for every
## SPECIAL bucket 3/4 row: 0x40df70 reads a mask only for buckets 7/5 (0x40df9e..0x40dfd4, else
## [0x4c1a04] = 0).
static func select_index(rates: Array, rng: Variant, channel: String = "magic", bucket: int = -1, mask: int = -1, functions: Array = []) -> Dictionary:
	var source := "0x40dd80" if channel == "special" else "0x40c770"
	var useful_accepts := channel == "magic" and bucket in [5, 7]
	var dispel_gate := channel == "magic" and bucket in [3, 4] and mask >= 0
	var draws: Array = []
	var visited: Array = []
	if not rates.is_empty():
		var start := recorded_draw(32, rng, draws) % rates.size()
		for offset in range(rates.size()):
			var index := (start + offset) % rates.size()
			visited.append(index)
			var roll := recorded_draw(100, rng, draws) + 1
			if useful_accepts: roll = 0
			elif dispel_gate and index < functions.size() and int(functions[index]) & 0x4000: roll = 0 if mask & 0x60 else 200
			if roll <= int(rates[index]):
				return {"index": index, "visited": visited, "draws": draws, "source": source, "useful_accepts": useful_accepts}
	return {"index": -1, "visited": visited, "draws": draws, "source": source, "useful_accepts": useful_accepts}


static func farthest_index(positions: Array, threat: Vector2i, rng: Variant) -> Dictionary:
	var selected := 0
	var best := 0
	var draws: Array = []
	for index in range(positions.size()):
		var point: Vector2i = positions[index]
		var distance := TacticalGridRules.manhattan(point, threat)
		if distance > best:
			best = distance
			selected = index
		elif distance == best and recorded_draw(2, rng, draws) != 0:
			selected = index
	return {"index": selected, "distance": best, "draws": draws, "source": "0x40d200..0x40d2b0",
		"whole_native_planner": false}


static func recorded_draw(bound: int, rng: Variant, draws: Array) -> int:
	var value := CoreCombatRules.rand_range(bound, rng)
	draws.append({"bound": bound, "value": value})
	return value

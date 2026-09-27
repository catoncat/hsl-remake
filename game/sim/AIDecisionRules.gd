extends RefCounted
## Pure selectors. Native branches and RNG consumption are independently replayed.
## No movement, spell settlement, queue or scene mutation belongs here.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_decisions.md
##   rules: provisional (stable-id adapter)
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Values = preload("res://game/sim/Values.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
## 0x43ff3a: cmp eax, 0xa; jg 0x440041 — the side walk is taken on rand(100) <= 10.
const SIDE_WALK_AT_MOST := 10
const JOB_GROUPS := {
	1: [85, 87, 90, 91, 97, 98, 99, 100], 2: [83, 84],
	3: [80, 81, 82], 4: [88, 89], 5: [92, 93], 6: [94, 95, 96],
}


static func profile_error(profile: Dictionary) -> String:
	for key in ["find_type", "find_flag", "find_range", "ai_att_special", "ai_att_magic", "ai_call_range", "ai_fixed", "job"]:
		if Values.non_negative_int(profile.get(key)) < 0: return "missing_ai_profile_" + key
	if int(profile["find_type"]) > 6 or int(profile["find_flag"]) > 6 or int(profile["find_range"]) > 512 or int(profile["ai_call_range"]) > 512 or int(profile["ai_fixed"]) > 512:
		return "unsupported_ai_profile"
	if int(profile["ai_att_special"]) > 100 or int(profile["ai_att_magic"]) > 100:
		return "invalid_ai_probability"
	var excluded: Variant = profile.get("find_no_id")
	if excluded != -1 and (Values.non_negative_int(excluded) < 0 or Values.non_negative_int(excluded) > 32767):
		return "invalid_ai_exclusion"
	return ""


static func action_order(selected: int) -> Array:
	return [selected, (selected + 1) % 3, (selected + 2) % 3]


static func select_action(profile: Dictionary, status_flags: int, magic: bool, special: bool, rng: Variant = null) -> Dictionary:
	var error := profile_error(profile)
	if error != "": return {"ok": false, "reason": error}
	if status_flags < 0 or status_flags > 0xffffffff: return {"ok": false, "reason": "invalid_ai_status_flags"}
	var draws: Array = []
	var roll := recorded_draw(99, rng, draws) + 1
	var order := [2, 1] if roll & 1 else [1, 2]
	var selected := 0
	for index in range(2):
		var channel: int = order[index]
		var available := special if channel == 2 else magic and (status_flags & 2) == 0
		if not available: continue
		if roll <= int(profile["ai_att_special" if channel == 2 else "ai_att_magic"]):
			selected = channel
			break
		if index == 0: roll = recorded_draw(99, rng, draws) + 1
	return {"ok": true, "kind": selected, "order": action_order(selected), "draws": draws,
		"source": "0x40c570; caller cycle 0x43fa8d..0x43face"}


## 0x43ff30..0x43ff3d: after the magic category found no cast an armed actor draws
## rand(100) and takes the side walk at 10 or below (11 in 100).
static func side_walk_roll(rng: Variant) -> Dictionary:
	var draws: Array = []
	var roll := recorded_draw(100, rng, draws)
	return {"roll": roll, "taken": roll <= SIDE_WALK_AT_MOST, "draws": draws, "source": "0x43ff32"}


static func rows_error(units: Array, owner_index: int) -> String:
	if units.size() > 200 or owner_index < 0 or owner_index >= units.size() or units[owner_index] == null:
		return "invalid_ai_roster"
	for unit in units:
		if unit == null: continue
		if not unit is Dictionary or not unit.get("coord") is Vector2i or not unit.get("removed") is bool:
			return "invalid_ai_actor"
		if unit["coord"].x < 0 or unit["coord"].y < 0 or unit["coord"].x > 512 or unit["coord"].y > 512:
			return "unsupported_ai_coordinates"
		for key in ["hp", "level", "job", "side", "sid"]:
			if Values.non_negative_int(unit.get(key)) < 0: return "invalid_ai_actor_" + key
	return ""


static func select_target(units: Array, owner_index: int, profile: Dictionary, near_range: int, rng: Variant = null) -> Dictionary:
	var error := profile_error(profile)
	if error == "": error = rows_error(units, owner_index)
	if error != "": return {"ok": false, "reason": error}
	if near_range < 0 or near_range > 512: return {"ok": false, "reason": "invalid_ai_near_range"}
	var owner: Dictionary = units[owner_index]
	var minimum := 700000
	var maximum := 0
	var best := -1
	var previous := -1
	var preferred := 0
	var mode := int(profile["find_type"])
	var preference := int(profile["find_flag"])
	var draws: Array = []
	for index in range(units.size()):
		var unit: Variant = units[index]
		# A row removed only by find_no_id (`excluded`) is not the native removed bit
		# 0x8000000: the scan scores it, moving the baseline, and the SID test below then
		# restores the previous candidate (emulator-measured battle 052 r1: 023／024 allies
		# never hold 026_1, which scores worse than the excluded emperor 025 scanned before it).
		if unit == null or index == owner_index or (unit["removed"] and not unit.get("excluded", false)) or (int(owner["side"]) & int(unit["side"]) & 0x870000) != 0:
			continue
		var distance := squared_distance(unit["coord"], owner["coord"])
		if distance > int(profile["find_range"]) * int(profile["find_range"]): continue
		var score := int(unit["hp"]) if mode in [1, 2] else int(unit["level"]) if mode in [5, 6] else 32 * TacticalGridRules.manhattan(unit["coord"], owner["coord"])
		var improved := mode == 0 or (score < minimum if mode in [1, 3, 5] else score > maximum)
		if improved:
			# The native score changes BEFORE its retain-old-candidate coin draw.
			if mode in [1, 3, 5]: minimum = score
			if mode in [2, 4, 6]: maximum = score
			if best != -1 and recorded_draw(2, rng, draws) != 0: continue
			previous = best
			best = index
		elif preference == 0:
			continue
		if int(profile["find_no_id"]) != -1 and int(profile["find_no_id"]) == int(unit["sid"]):
			best = previous
			continue
		if distance > near_range * near_range or int(unit["job"]) not in JOB_GROUPS.get(preference, []): continue
		if preferred not in [0, -1] and recorded_draw(2, rng, draws) != 0: continue
		preferred = index
	var selected := preferred if preferred != 0 else best
	return {"ok": true, "index": selected, "native_index": selected + 1, "draws": draws,
		"source": "0x40bb80"}


## The rows in native registry order: entry k is `rows[layout[k]]` (CoreTurnQueue.
## registry_layout), null for an empty slot. An empty layout keeps the rows' own order.
static func registry_rows(rows: Array, layout: Array) -> Array:
	if layout.is_empty(): return rows
	var ordered: Array = []
	for index in layout: ordered.append(rows[int(index)] if int(index) >= 0 and int(index) < rows.size() else null)
	return ordered


## 0x40bb80 as the original runs it: over the object array 0x4c34c0 from slot 0, so the
## candidate order — every retain-old coin 0x40bd4f and the preferred-job sentinel 0,
## which is registry slot 0 (the PLAYERS code-1 unit), not the first roster row — follows
## registration (static-derived 0x40bb80 loop over 0x4c34c0; emulator-measured battle 051
## r1: Leonard, slot 0, is the first candidate every NPC scan meets). `index` is mapped
## back to `rows`; `native_index` stays the 1-based registry slot the original writes to
## +0x88. An empty layout scans the rows in their own order.
static func select_registered_target(rows: Array, layout: Array, owner_index: int, profile: Dictionary, near_range: int, rng: Variant = null) -> Dictionary:
	if layout.is_empty(): return select_target(rows, owner_index, profile, near_range, rng)
	var owner_slot := layout.find(owner_index)
	if owner_slot < 0: return {"ok": false, "reason": "invalid_ai_roster"}
	var result := select_target(registry_rows(rows, layout), owner_slot, profile, near_range, rng)
	if result["ok"] and int(result["index"]) >= 0: result["index"] = int(layout[int(result["index"])])
	return result


static func squared_distance(a: Vector2i, b: Vector2i) -> int:
	var delta := a - b
	return delta.x * delta.x + delta.y * delta.y


static func recorded_draw(bound: int, rng: Variant, draws: Array) -> int:
	var value := CoreCombatRules.rand_range(bound, rng)
	draws.append({"bound": bound, "value": value})
	return value

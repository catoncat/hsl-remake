extends RefCounted
## Read-only target memory decisions and complete current-map route proposals.
## Native distance/wait/lock kernels are separate from the shared WRD adapter.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_navigation.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_ranges.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_fixpos_fly_prev_insert.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_movement.md
##   rules: provisional
##     (shortest-path tie-breaks, guard routes, refinement flood metric and candidate order are remake composition;
##     approach_goals (candidate_filters, no_attack pursuit) use flat RANGE offsets)
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const AISkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")


# Live-record AI fields an EVEF instance word may replace (install callback 0x42bd50,
# jump table 0x42c0a8 indices 1..14). `fixed_point` (index 15) is handled as state.
const INSTANCE_PROFILE_FIELDS := ["find_type", "find_flag", "find_range", "ai_call_range", "ai_fixed", "ai_check_dying",
	"ai_check_hp", "ai_help_otherhp", "ai_help_status", "ai_help_attack", "ai_lock", "ai_att_special", "ai_att_magic", "wait_round"]
const FIXED_POINT_RADIUS := 8
# 0x4111a0 passes 0x12: the first refinement flood of the fixed-point walk (0x411080).
const FIXED_POINT_FLOOD_RADIUS := 18
# The coordinate magnitude the AI kernels accept (AIDecisionRules.rows_error); an anchor
# beyond it could not be measured against by any walk.
const COORDINATE_LIMIT := 512
# Cell-word bit of a hard-blocked WRD cell (buildings, pillars; TerrainEditRules clears it).
const HARD_BLOCK_FLAG := 0x4000
# 0x413740: a candidate with this many flagged neighbours (0x40d800) is skipped when
# rand(100) < 80 (0x413889..0x41389b).
const CROWDED_NEIGHBOURS := 3
const CROWDED_SKIP_BELOW := 80
# 0x40d8b0 tries a 3×3 target's body cells in this order (0x40d9bd..0x40dc06), taking the
# first centre that yields any attack station.
const LARGE_TARGET_CENTRES := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 0)]
# State 0xb sub 0 (0x440be7..0x440c24): standing no farther than the station and next to a
# foe, the actor still moves there when rand(99) + 1 exceeds 92 (weapon range index < 2)
# or 78 (ranged weapons).
const REPOSITION_ABOVE_MELEE := 92
const REPOSITION_ABOVE_RANGED := 78


static func initialize(actor: Dictionary, profile: Dictionary) -> void:
	actor["ai_target_id"] = ""
	actor["ai_wait_remaining"] = int(profile["wait_round"])
	actor["ai_home_coord"] = actor["coord"]
	var point: Variant = actor.get("evef_instance", {}).get("overrides", {}).get("fixed_point")
	if point is Array and point.size() == 2:
		# Index 15: object flag 0x4000, ai_fixed 8 and the instance point as home; the
		# guard walks there and is released (flag and ai_fixed cleared) on arrival.
		actor["ai_home_coord"] = Vector2i(int(point[0]), int(point[1]))
		actor["ai_fixed_point_pending"] = true


static func instance_profile(actor: Dictionary, declared: Dictionary) -> Dictionary:
	## The actor's PLAYERS strategy after its own EVEF instance words (per unit, not per
	## actor code). A fixed-point guard has ai_fixed 8 until it stands on the point. A
	## script actSetPlayerFixPos with a nonzero distance wrote the live ai_fixed (+0x1d0)
	## later than the install words, so its radius (`ai_fixed_radius`) is read last.
	var overrides: Variant = actor.get("evef_instance", {}).get("overrides", {})
	var radius: Variant = actor.get("ai_fixed_radius")
	if (not overrides is Dictionary or overrides.is_empty()) and radius == null: return declared
	var profile := declared.duplicate(true)
	if overrides is Dictionary:
		for key in INSTANCE_PROFILE_FIELDS:
			if overrides.has(key): profile[key] = int(overrides[key])
		if overrides.has("fixed_point"):
			profile["ai_fixed"] = FIXED_POINT_RADIUS if bool(actor.get("ai_fixed_point_pending", false)) else 0
	if radius != null: profile["ai_fixed"] = int(radius)
	return profile


static func state_error(actor: Dictionary, guard_radius: int = 0) -> String:
	if not actor.get("ai_target_id") is String: return "invalid_ai_target_id"
	if SkillResourceRules._integer(actor.get("ai_wait_remaining")) < 0 or int(actor["ai_wait_remaining"]) > 10000: return "invalid_ai_wait_remaining"
	if not actor.get("ai_home_coord") is Vector2i: return "invalid_ai_home_coord"
	if actor.has("ai_fixed_radius") and (SkillResourceRules._integer(actor["ai_fixed_radius"]) <= 0 or int(actor["ai_fixed_radius"]) > COORDINATE_LIMIT): return "invalid_ai_fixed_radius"
	# A free-moving actor never reads the guard anchor. A guard's anchor may lie beyond
	# the map (WINFAIL012 retreat points -160,1824 / 576,-160 / 1632,608 / 736,2112 on a
	# 45x60 map): the walk measures Manhattan distance to it and stops at the edge, so
	# only an anchor outside the coordinate range every AI kernel accepts is rejected.
	if guard_radius > 0 and not _measurable(actor["ai_home_coord"]): return "invalid_ai_home_coord"
	return ""


static func _measurable(anchor: Vector2i) -> bool:
	return absi(anchor.x) <= COORDINATE_LIMIT and absi(anchor.y) <= COORDINATE_LIMIT


static func profile_error(profile: Dictionary) -> String:
	if SkillResourceRules._integer(profile.get("wait_round")) < 0 or int(profile["wait_round"]) > 10000: return "invalid_ai_wait_round"
	if SkillResourceRules._integer(profile.get("ai_lock")) < 0 or int(profile["ai_lock"]) > 100: return "invalid_ai_lock"
	return ""


static func within(a: Vector2i, b: Vector2i, radius: int, diamond: bool) -> bool:
	var delta := a - b
	return absi(delta.x) + absi(delta.y) <= radius if diamond else delta.length_squared() <= radius * radius


static func guard_allows(actor: Dictionary, target: Dictionary, profile: Dictionary, retained: bool = false) -> bool:
	return int(profile["ai_fixed"]) == 0 or within(actor["ai_home_coord"], target["coord"], int(profile["ai_fixed"]), retained)


static func acquire(actor: Dictionary, units: Array, prepared: Dictionary, rng: Variant) -> Dictionary:
	var profile: Dictionary = prepared["profile"]
	var held := str(actor["ai_target_id"])
	var wait_left := int(actor["ai_wait_remaining"])
	var result := {"index": -1, "retained": false, "wait_remaining": wait_left, "wait": false,
		"previous_target_id": held, "reason": "new_target", "draws": [], "source": "original_ai_navigation"}
	for index in range(units.size()):
		var target: Dictionary = units[index]
		if target["id"] != held: continue
		# 0x43f55f..0x43f5f5: a living held object within find range (0x40bb50, diamond)
		# and the home radius is kept; whether it can be reached plays no part.
		if prepared["priority_rows"][index] != null and not prepared["priority_rows"][index]["removed"] and within(actor["coord"], target["coord"], int(profile["find_range"]), true) and guard_allows(actor, target, profile, true):
			result.merge({"index": index, "retained": true, "reason": "retained_target"}, true)
			return result
	result["reason"] = "target_unavailable" if held != "" else "new_target"
	var rows: Array = prepared["rows"].duplicate(true)
	var search_profile := profile.duplicate(true)
	if wait_left > 0:
		result["wait_remaining"] = wait_left - 1
		if int(actor["status_flags"]) != 0 or int(actor["hp"]) != int(actor["max_hp"]):
			result["wait_remaining"] = 0
			result["reason"] = "wait_interrupted"
		else:
			search_profile["find_range"] = 8
			result["wait"] = true
	for index in range(rows.size()):
		if rows[index] != null and not guard_allows(actor, units[index], profile): rows[index].merge({"removed": true, "excluded": false}, true)
	var selected := AIDecisionRules.select_registered_target(rows, prepared.get("registry", []), int(prepared["owner_index"]), search_profile, int(actor["move_point"]), rng)
	result.merge({"index": selected["index"], "selection": selected, "draws": selected["draws"]}, true)
	if result["wait"]:
		result["reason"] = "wait_round" if int(result["index"]) < 0 else "nearby_enemy"
		if int(result["index"]) >= 0:
			result["wait"] = false
			result["wait_remaining"] = 0
	return result


## `traversal`: the actor's accepted TacticalGridRules.Traversal context when the caller holds one.
## `route_cells`: the cells whose routes the caller will read (Grid's `route_cells`); null
## routes every reached cell. The actor's own cell always has its one-cell route.
static func full_routes(loop: Dictionary, actor: Dictionary, traversal: Dictionary = {}, route_cells: Variant = null) -> Dictionary:
	var size: Vector2i = loop["map_size"]
	if size.x <= 0 or size.y <= 0 or size.x > 256 or size.y > 256 or not SkillTargetRules._inside(actor["coord"], size): return {"ok": false, "reason": "invalid_ai_map"}
	# An accepted traversal context of this map has already passed every tile through
	# `tile_error` and carries the largest arrival cost; without one, check the map here.
	var max_cost := 1
	if not traversal.is_empty():
		max_cost = int(traversal["max_cost"])
	else:
		for tile in TerrainEditRules.tiles(loop).values():
			var error := TacticalGridRules.Traversal.tile_error(tile)
			if error != "": return {"ok": false, "reason": error}
			max_cost = maxi(max_cost, int(tile.get("move_cost", 1)))
	var result := TacticalGridRules.movement_reachability_envelope(actor, loop["units"], TerrainEditRules.tiles(loop), size, size.x * size.y * (max_cost + 3), traversal, route_cells)
	if not result["ok"]: return result
	result["reachable_by_coord"][actor["coord"]] = {"path": [actor["coord"]], "path_costs": [0], "path_stops": [true], "cost": 0}
	return result


## Per foe (in `foes` order), the cells an approach may end on: attack cells of the weapon
## pattern and cast positions of the actor's available offensive skills. Read-only; no RNG.
static func approach_goals(loop: Dictionary, actor: Dictionary, foes: Array, fields_by_id: Dictionary) -> Dictionary:
	var available: Array = []
	for id in loop["skill_book"]["skills"]:
		var entry: Dictionary = loop["skill_book"]["skills"][id]
		var fields: Dictionary = fields_by_id[id]
		if SkillTargetRules.is_support(fields, loop["skill_target_data"]) or SkillResolutionRules.ownership_error(actor, id, loop["skill_book"]) != "": continue
		if SkillResourceRules._integer(fields.get("use_ratio"), true) == 0: continue
		if SkillResolutionRules.available(actor, id, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])["ok"]: available.append({"id": id, "fields": fields})
	var result := {}
	var pattern := PositionCapabilityRules.attack_pattern(actor, loop["equipment_items"], loop["attack_patterns"], loop["weapon_ranges"])
	if not pattern["ok"]: return pattern
	var offsets: Array = pattern["offsets"]
	for target in foes:
		var goals := {}
		if not bool(actor.get("no_attack", false)):
			for point in SkillTargetRules.Footprint.cells(target):
				for offset in offsets:
					goals[point - Vector2i(int(offset[0]), int(offset[1]))] = true
		for skill in available:
			var fields: Dictionary = skill["fields"]
			if loop["skill_book"]["skills"][skill["id"]]["damage_policy"] == "native_magic_status":
				var effect := SkillResolutionRules.StatusApplication.prepare(actor, target, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])
				if not effect["ok"]: return effect
				if AISkillPlanning.useful_ids({"targets": [target], "prepared": [{"status": effect}]}).is_empty(): continue
			var range_data: Dictionary = loop["skill_target_data"]["ranges"][fields["range"]]
			var half := int(range_data["size"]) / 2
			for center in SkillTargetRules.candidate_centers(actor, [target], fields, loop["skill_target_data"], loop["map_size"], actor["coord"]):
				for y in range(int(range_data["size"])):
					for x in range(int(range_data["size"])):
						if int(range_data["data"][y][x]) <= 0 or (x == half and y == half and not SkillTargetRules.self_centered(fields)): continue
						goals[center - Vector2i(x - half, y - half)] = true
		result[target["id"]] = goals
	return {"ok": true, "goals": result}


## Each foe's cheapest full-map route to one of its `approach_goals` cells; foes without a
## reachable goal are left out.
static func approaches(full: Dictionary, goals_by_target: Dictionary) -> Dictionary:
	var result := {}
	for target_id in goals_by_target:
		var best := route_to_goals(full, goals_by_target[target_id].keys())
		if not best.is_empty(): result[target_id] = best
	return {"ok": true, "targets": result}


static func route_to_goals(full: Dictionary, goals: Array) -> Dictionary:
	var best := {}
	goals.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for goal in goals:
		if not full["reachable_by_coord"].has(goal): continue
		var route: Dictionary = full["reachable_by_coord"][goal]
		if best.is_empty() or int(route["cost"]) < int(best["cost"]): best = {"goal": goal, "cost": route["cost"], "path": route["path"], "path_costs": route["path_costs"], "path_stops": route["path_stops"]}
	return best


static func approach_home(loop: Dictionary, actor: Dictionary, envelope: Dictionary, rng: Variant) -> Dictionary:
	## 0x43fbd6 -> 0x4111a0(actor, anchor, 0x12, move): a guard standing off its point
	## walks toward it through the shared refinement walk.
	return approach_point(loop, actor, envelope, actor["ai_home_coord"], rng)


static func approach_point(loop: Dictionary, actor: Dictionary, envelope: Dictionary, home: Vector2i, rng: Variant) -> Dictionary:
	## 0x4111a0(actor, point, 0x12, move) -> 0x411080, the one walk both callers use: the
	## fixed-point guard (0x43fbd6, point = its anchor) and ordinary pursuit (state 0xb
	## sub 0 at 0x440d5c..0x440d84, point = the held target's position, taken when
	## 0x40fb20 finds no attack this turn). The native driver floods radius max(18, move) from the
	## actor and takes the flooded stoppable cell nearest (Manhattan) to the anchor
	## (0x413900 / 0x413740: cells holding any unit are skipped, an equal candidate
	## replaces the held one on rand() & 1), then floods again with the radius shrunk by
	## two toward that cell, until the radius is the move budget; the last pick is this
	## turn's destination. Every candidate that would be taken is first checked by
	## 0x40d800: with three or more flagged in-map neighbours it is skipped when
	## rand(100) < 80. The shrinking levels pass side 0 (only hard-blocked 0x4000 cells
	## count, 0x41112b); the last pick passes the actor's side word 0x40ba20 (0x41114d),
	## so hostile occupants count too. The remake replays that refinement over its own
	## movement-cost flood (provisional: the flood metric, the candidate iteration order
	## and an odd move budget's last shrink). An anchor beyond the map edge (WINFAIL012
	## retreat points) needs no map cell: the walk ends at the edge.
	var origin: Vector2i = actor["coord"]
	var move := int(actor["move_point"])
	var result := {"to": origin, "path": [origin], "cost": 0, "goal": home, "route_cost": -1, "draws": [], "candidates": 0, "refinements": [], "reason": "no_reachable_cell"}
	var target := home
	var radius := maxi(FIXED_POINT_FLOOD_RADIUS, move)
	var cell_words := neighbour_words(loop)
	while true:
		var flood: Dictionary = envelope
		if radius != move:
			flood = TacticalGridRules.movement_reachability_envelope(actor, loop["units"], TerrainEditRules.tiles(loop), loop["map_size"], radius)
			if not flood["ok"]:
				result["reason"] = flood["reason"]
				return result
		var mask := blocker_mask(side_word(actor) if radius == move else 0)
		var pick := _nearest_stoppable(flood["reachable_by_coord"].keys(), target, origin, rng, result["draws"], cell_words, mask, loop["map_size"])
		if pick.is_empty():
			return result
		result["refinements"].append({"radius": radius, "target": target, "pick": pick["cell"], "candidates": pick["candidates"], "crowded_skips": pick["crowded_skips"]})
		target = pick["cell"]
		if radius == move: break
		radius = maxi(radius - 2, move)
	result["candidates"] = int(result["refinements"].back()["candidates"])
	var route: Dictionary = envelope["reachable_by_coord"][target]
	result.merge({"to": target, "path": route["path"], "cost": route["cost"], "route_cost": absi(target.x - home.x) + absi(target.y - home.y), "reason": "nearest_to_point"}, true)
	return result


static func _nearest_stoppable(cells: Array, target: Vector2i, origin: Vector2i, rng: Variant, draws: Array, cell_words: Dictionary, mask: int, map_size: Vector2i) -> Dictionary:
	## 0x413900 over one flood, row-major: the stoppable cell nearest (Manhattan) to
	## `target`; the actor's own cell holds a unit and is skipped like any occupied cell
	## (mask 0x70000). A strictly nearer cell, or an equal one whose rand() & 1 is set, is
	## then filtered by 0x40d800 (see approach_point); a skipped cell leaves the held best.
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var best := {}
	var considered := 0
	var skipped := 0
	for cell in cells:
		if cell == origin: continue
		considered += 1
		var distance := absi(cell.x - target.x) + absi(cell.y - target.y)
		if not best.is_empty():
			if distance > int(best["distance"]): continue
			if distance == int(best["distance"]) and AIDecisionRules._draw(2, rng, draws) == 0: continue
		if adjacent_blockers(cell, mask, cell_words, map_size) >= CROWDED_NEIGHBOURS and AIDecisionRules._draw(100, rng, draws) < CROWDED_SKIP_BELOW:
			skipped += 1
			continue
		best = {"cell": cell, "distance": distance}
	if best.is_empty(): return {}
	best["candidates"] = considered
	best["crowded_skips"] = skipped
	return best


## The weapon terrain the AI's attack reads, once per actor turn: the attacker's RANGE rows,
## its 0x40bab0 builder mode (P 2, E 3, N 7) and two word maps — every living occupant (the
## in-range test of state 0xb sub 0: 0x40fa80(actor, range, mode, 1) → 0x40fb20(target),
## 0x440d16..0x440d42) and the same map with the attacker's own occupancy lifted (0x40d8b0
## runs 0x411b90 first, 0x40d8c3, so the station coverage 0x40fa80(target, range, mode, 0),
## 0x40dbe6..0x40dbfa, or 0x40f8b0 per body cell of a 3×3 target, can write its own cell).
## Empty (flat offsets) for an unarmed pattern or a pattern without RANGE rows.
static func weapon_terrain(loop: Dictionary, actor: Dictionary, pattern: Dictionary) -> Dictionary:
	if not bool(pattern.get("ok", false)) or pattern["offsets"].is_empty(): return {}
	var rows: Variant = loop["attack_patterns"].get(str(pattern.get("name", "")), {}).get("data")
	if not rows is Array: return {}
	var others: Array = loop["units"].filter(func(unit): return unit["id"] != actor["id"])
	return {"rows": rows, "mode": RangePropagationRules.offensive_mode(actor), "map_size": loop["map_size"],
		"words": RangePropagationRules.loop_words(loop), "lifted": RangePropagationRules.cell_words(TerrainEditRules.tiles(loop), others)}


## State 0xb's in-range test on the board as it stands: the actor's own weapon coverage
## (0x40fa80(actor, range, 0x40bab0 mode, 1), every occupant in place) holds a body cell of
## the target (0x40fb20). The flood is not symmetric — a station collected from the
## target's coverage need not see the target back — so the arrival re-test after the walk
## (0x441311..0x441369: a miss ends the turn at 0x441eb8) reads this, not the station set.
static func target_in_range(loop: Dictionary, actor: Dictionary, target: Dictionary, terrain: Dictionary) -> bool:
	var reach := RangePropagationRules.weapon_coverage(terrain["rows"], actor["coord"], RangePropagationRules.loop_words(loop), loop["map_size"], int(terrain["mode"]), true)
	for point in SkillTargetRules.Footprint.cells(target):
		if int(reach.get(point, 0)) > 0: return true
	return false


## Attack stations for one target (0x40d8b0 -> 0x413390), read-only: the actor's move
## flood (its own cell included — 0x40d8b0 lifts its occupancy first) intersected with the
## weapon coverage around the target centre, unoccupied, collected row-major. With a
## `terrain` (weapon_terrain) the coverage is the original flood from the target (walls
## 0x4000 stop it, the onward check cuts it next to walls) and "in place" is the target in
## the actor's own coverage; without one both fall back to the flat RANGE offsets. `routes`
## are the stoppable cells of the current envelope. A 3×3 target tries its body cells in
## LARGE_TARGET_CENTRES order and keeps the first centre with a station. Empty when no
## station exists (the turn then pursues through approach_point).
static func attack_stations(actor: Dictionary, target: Dictionary, offsets: Array, melee: bool, routes: Dictionary, terrain: Dictionary = {}) -> Dictionary:
	var origin: Vector2i = actor["coord"]
	var anchor: Vector2i = target["coord"]
	var centres: Array = [anchor]
	if SkillTargetRules.Footprint.radius(target) == 1: centres = LARGE_TARGET_CENTRES.map(func(delta): return anchor + delta)
	var in_place := false
	var reach := {}
	if not terrain.is_empty(): reach = RangePropagationRules.weapon_coverage(terrain["rows"], origin, terrain["words"], terrain["map_size"], int(terrain["mode"]), true)
	for point in SkillTargetRules.Footprint.cells(target):
		if not terrain.is_empty():
			if int(reach.get(point, 0)) > 0: in_place = true
			continue
		for offset in offsets:
			if point - Vector2i(int(offset[0]), int(offset[1])) == origin: in_place = true
	for centre in centres:
		var stations: Array = []
		var covered: Array = []
		if terrain.is_empty():
			for offset in offsets: covered.append(centre - Vector2i(int(offset[0]), int(offset[1])))
		else:
			covered = RangePropagationRules.cells(RangePropagationRules.weapon_coverage(terrain["rows"], centre, terrain["lifted"], terrain["map_size"], int(terrain["mode"]), false), centre)
		for cell in covered:
			if cell == origin: stations.append({"cell": cell, "cost": 0})
			elif routes.has(cell): stations.append({"cell": cell, "cost": int(routes[cell]["cost"])})
		if stations.is_empty(): continue
		stations.sort_custom(func(a, b): return a["cell"].y < b["cell"].y or (a["cell"].y == b["cell"].y and a["cell"].x < b["cell"].x))
		return {"stations": stations, "centre": centre, "anchor": anchor, "melee": melee, "in_place": in_place}
	return {}


## State 0xb sub 0 over the stations of attack_stations: 0x413390 insertion-sorts them by
## distance from the centre, farthest first, where an entry equal to the one just before it
## swaps with it on rand() & 1 (0x41362f..0x413716), and the walk target is the first. The
## key is pixel Manhattan between the station word — the cell centre, cell * 32 + 16
## (0x4134be..0x4134cc) — and the range centre [0x4c63a0]／[0x4c639c] shifted by 5 with no
## half cell (0x41363e..0x41364c), i.e. |2dx + 1| + |2dy + 1| half cells: a station right of
## or below the centre counts farther than its mirror left of or above it, so those pairs
## never tie (static-derived; the level-3 028_1 station (6,10) over (5,9) with no draw,
## emulator-observed). If that station is no farther from the target than the actor and a foe stands
## next to the actor (0x40d890 with the search mask 0x40ba80), rand(99) + 1 above 92 (melee)
## or 78 (ranged) still moves it there; otherwise an actor that can already hit the target
## attacks where it stands (0x40fb20), and one that cannot walks to the station
## (0x410a50). A station on the actor's own cell is an attack in place.
static func attack_station(choice: Dictionary, origin: Vector2i, foes_adjacent: int, rng: Variant) -> Dictionary:
	var sorted := station_order(choice, rng)
	var draws: Array = sorted["draws"]
	var station: Vector2i = sorted["order"][0]
	var anchor: Vector2i = choice["anchor"]
	var result := {"station": station, "order": sorted["order"], "draws": draws, "foes_adjacent": foes_adjacent, "roll": 0}
	var no_farther := absi(station.x - anchor.x) + absi(station.y - anchor.y) <= absi(origin.x - anchor.x) + absi(origin.y - anchor.y)
	if no_farther:
		if foes_adjacent != 0:
			result["roll"] = AIDecisionRules._draw(99, rng, draws) + 1
			if int(result["roll"]) > (REPOSITION_ABOVE_MELEE if bool(choice["melee"]) else REPOSITION_ABOVE_RANGED) and station != origin:
				result.merge({"to": station, "reason": "reposition_roll"}, true)
				return result
		if bool(choice["in_place"]):
			result.merge({"to": origin, "reason": "attack_in_place"}, true)
			return result
	result.merge({"to": station, "reason": "attack_in_place" if station == origin else "walk_to_station"}, true)
	return result


## 0x413390's insertion sort of one target's stations (see attack_station): farthest from the
## range centre first, an entry equal to the one just before it swapping on raw & 1. The
## first cell is the one 0x40d8b0 leaves at 0x4c6560.
static func station_order(choice: Dictionary, rng: Variant) -> Dictionary:
	var draws: Array = []
	var centre: Vector2i = choice["centre"]
	var order: Array = choice["stations"].duplicate()
	var far := func(entry: Dictionary) -> int: return absi(2 * (entry["cell"].x - centre.x) + 1) + absi(2 * (entry["cell"].y - centre.y) + 1)
	for i in range(1, order.size()):
		var held: Dictionary = order[i]
		var before := int(far.call(order[i - 1]))
		var distance := int(far.call(held))
		if before == distance:
			if AIDecisionRules._draw(2, rng, draws) & 1:
				order[i] = order[i - 1]
				order[i - 1] = held
		elif before < distance:
			var j := i - 1
			while j >= 0 and int(far.call(order[j])) < distance:
				order[j + 1] = order[j]
				j -= 1
			order[j + 1] = held
	return {"order": order.map(func(entry): return entry["cell"]), "draws": draws}


## 0x40ba80: the search mask of an actor — every side bit its own side word lacks.
static func search_mask(unit: Dictionary) -> int:
	return ~side_word(unit) & ActorRoleRules.SIDE_MASK


## The side word 0x40ba20 returns: the pmPlayer／pmEnemy／pmNPC bits of the live mode plus
## 0x800000, or the side the role implies when no mode is installed.
static func side_word(unit: Dictionary) -> int:
	if unit.has("player_mode"): return int(unit["player_mode"]) & (ActorRoleRules.SIDE_MASK | ActorRoleRules.MAGIC_ONLY_BIT)
	return ActorRoleRules.side_mask(unit)


## 0x413740's 0x40d800 mask: a single side is replaced by the two others (0x4137ae), any
## other word is kept; 0x4000 (hard block) is always added.
static func blocker_mask(side: int) -> int:
	var others := {ActorRoleRules.SIDE_PLAYER: ActorRoleRules.SIDE_ENEMY | ActorRoleRules.SIDE_NPC, ActorRoleRules.SIDE_ENEMY: ActorRoleRules.SIDE_PLAYER | ActorRoleRules.SIDE_NPC, ActorRoleRules.SIDE_NPC: ActorRoleRules.SIDE_PLAYER | ActorRoleRules.SIDE_ENEMY}
	return int(others.get(side, side)) | HARD_BLOCK_FLAG


## Cell words 0x40d800 reads, for cells that carry any: an occupant's side word
## (0x411a30 marks every footprint cell) and a hard-blocked cell's 0x4000.
static func neighbour_words(loop: Dictionary) -> Dictionary:
	var words := {}
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	for cell in tiles:
		if int(tiles[cell].get("movement_flags", 0)) & HARD_BLOCK_FLAG: words[cell] = HARD_BLOCK_FLAG
	var occupants := SkillTargetRules.Footprint.occupants(loop["units"])
	for cell in occupants:
		words[cell] = int(words.get(cell, 0)) | side_word(occupants[cell])
	return words


## 0x40d800(x, y, mask): how many of the four in-map neighbours (left, right, up, down)
## carry a cell word meeting `mask`; off-map neighbours never count.
static func adjacent_blockers(cell: Vector2i, mask: int, cell_words: Dictionary, map_size: Vector2i) -> int:
	var count := 0
	for delta in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var point: Vector2i = cell + delta
		if point.x < 0 or point.y < 0 or point.x >= map_size.x or point.y >= map_size.y: continue
		if int(cell_words.get(point, 0)) & mask: count += 1
	return count


static func advance_path(actor: Dictionary, route: Dictionary) -> Dictionary:
	var end_index := 0
	var cost := 0
	for index in range(1, route["path"].size()):
		var arrival := int(route["path_costs"][index])
		if arrival > int(actor["move_point"]): break
		if route["path_stops"][index]:
			cost = arrival
			end_index = index
	var path: Array = route["path"].slice(0, end_index + 1)
	return {"to": path.back(), "path": path, "cost": cost, "goal": route.get("goal", actor["coord"]), "route_cost": route.get("cost", 0)}

extends RefCounted
## Focused tactical-grid movement and range rules used by the live play loop.
##
## This module owns no scene state. Callers pass units, tiles, and map size.
## Original normal-mode four-neighbor costs are checked against full native
## floods. Map flags/occupancy adaptation and equal-cost path ties are separate.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_movement.md
##   rules: resource-derived content/generated/hsl/chapter01/attack_ranges.json
##   rules: provisional (equal-cost path ties, occupancy adaptation)
const OBSTACLE_MASK := 0x74000
const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const Traversal = preload("res://game/sim/ActorTraversalRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")


static func movement_range(unit: Dictionary, units: Array, tiles: Dictionary, map_size: Vector2i) -> Array:
	return movement_reachability_envelope(unit, units, tiles, map_size).get("reachable_coords", [])


## `traversal` is an accepted `Traversal.prepare(unit, units, tiles)` context the caller
## already holds for this unit and board (several floods of one AI turn); empty prepares one.
## `route_cells` (a set of cells) resolves only those cells after the same flood: routes,
## stop verdicts and reachable／transit membership exist for them alone (the AI's full-map
## approach asks for its goal cells); null resolves every reached cell.
static func movement_reachability_envelope(unit: Dictionary, units: Array, tiles: Dictionary, map_size: Vector2i, budget: int = -1, traversal: Dictionary = {}, route_cells: Variant = null) -> Dictionary:
	var start: Vector2i = unit.get("coord", Vector2i.ZERO)
	var move_budget: int = budget if budget >= 0 else int(unit["move_point"])
	var context: Dictionary = traversal if not traversal.is_empty() else Traversal.prepare(unit, units, tiles, {}, map_size)
	if not context["ok"]:
		return {"ok": false, "reason": context["reason"], "reachable_coords": [], "reachable_by_coord": {}, "transit_by_coord": {}, "blocked_coords": {}}
	# Incoming direction matters when a no-block actor was crossed: native
	# clearance excludes the previous cell. These states live only in this query: state
	# `(y * width + x) * 4 + incoming direction` for an in-map cell, one extra slot for the
	# start (no incoming direction; a start is never re-entered). `costs` (-1 unset) and
	# `parents` are indexed by state, `best_state` by cell; `best` keeps the cells in first-
	# reached order.
	var width := map_size.x
	var cell_count := maxi(0, map_size.x * map_size.y)
	var initial := cell_count * 4
	var frontier := PackedInt32Array([initial])
	var cursor := 0
	var costs := PackedInt32Array()
	costs.resize(initial + 1)
	costs.fill(-1)
	costs[initial] = 0
	var parents := PackedInt32Array()
	parents.resize(initial + 1)
	parents[initial] = initial
	var best_state := PackedInt32Array()
	best_state.resize(cell_count)
	best_state.fill(-1)
	var best := {start: initial}
	var reachable: Array = []
	var reachable_by_coord := {}
	var transit_by_coord := {}
	var blocked_coords := {}
	# A cell blocked from several neighbours keeps the last transition's reason; its
	# blocker receipt depends only on the cell, so it is built once per flood over one
	# roster-wide occupant map (Footprint.occupants, made at the first blocked cell).
	var blockers_by_coord := {}
	var occupants := {}
	# The single-cell transition, arrival cost and onward penalty are
	# Traversal.transition_error／arrival_cost／onward_penalty read inline from the same
	# context tables (one flood makes tens of thousands of transitions), through their
	# row-major copies over this map (`cell_*`); a 3×3 body keeps calling transition_error
	# for its footprint check.
	var flags: Dictionary = context["flags"]
	var heights: Dictionary = context["heights"]
	var occupied: Dictionary = context["occupied"]
	var mask := int(context["mask"])
	var flying := int(context["mode"]) == 6
	var large := int(context["radius"]) == 1
	var rows := context if context.get("size") == map_size else _cell_rows(context, map_size)
	var cell_flags: PackedInt32Array = rows["cell_flags"]
	var cell_heights: PackedInt32Array = rows["cell_heights"]
	var cell_costs: PackedInt32Array = rows["cell_costs"]
	var cell_pass: PackedByteArray = rows["cell_pass"]
	while cursor < frontier.size():
		var state := frontier[cursor]
		cursor += 1
		var current := start
		var previous := start
		var height_before := 0
		if state != initial:
			var cell := state >> 2
			current = Vector2i(cell % width, cell / width)
			previous = current - DIRECTIONS[state & 3]
			height_before = cell_heights[cell]
		else:
			height_before = int(heights.get(start, 0))
		# `state`'s own cost and its leaving penalty are the same for all four neighbours.
		var state_cost := costs[state]
		var penalty := 0
		if current != previous and not flying:
			for delta in DIRECTIONS:
				var point: Vector2i = current + delta
				if point == previous: continue
				var point_flags := cell_flags[point.y * width + point.x] if point.x >= 0 and point.y >= 0 and point.x < map_size.x and point.y < map_size.y else int(flags.get(point, 0))
				if point_flags & mask:
					penalty = 1
					break
		for direction in range(4):
			var next: Vector2i = current + DIRECTIONS[direction]
			if next == start or next.x < 0 or next.y < 0 or next.x >= map_size.x or next.y >= map_size.y: continue
			var next_cell := next.y * width + next.x
			var height_after := cell_heights[next_cell]
			var climb := ((16 if height_after == 255 else 0) if height_before == 128 else height_after - height_before)
			var error := ""
			if large:
				error = Traversal.transition_error(current, next, context, tiles)
			elif cell_flags[next_cell] & mask and (flying or cell_pass[next_cell] == 0):
				error = "target_occupied" if occupied.has(next) else "target_blocked_by_terrain"
			elif not flying and absi(climb) >= 3:
				error = "target_blocked_by_height"
			if error != "":
				if not blockers_by_coord.has(next):
					if occupants.is_empty(): occupants = Traversal.Footprint.occupants(units)
					blockers_by_coord[next] = _move_target_blockers(occupants.get(next, {}), next, tiles)
				blocked_coords[next] = {"reason": error, "blockers": blockers_by_coord[next]}
				continue
			var candidate := state_cost + cell_costs[next_cell] + (0 if flying else maxi(0, climb)) + penalty
			if candidate > move_budget: continue
			var next_state := next_cell * 4 + direction
			var known := costs[next_state]
			if known >= 0 and candidate >= known: continue
			costs[next_state] = candidate
			parents[next_state] = state
			frontier.append(next_state)
			var held := best_state[next_cell]
			if held < 0 or candidate < costs[held]:
				best_state[next_cell] = next_state
				best[next] = next_state
	# Each best state's path／costs／stops are its parent's arrays plus one cell: a state on
	# several best paths is built once (`routes_by_state`) and each cell's stop verdict is
	# asked once (`stop_errors`); every route keeps its own arrays.
	var routes_by_state := {initial: [[start], [0], [true]]}
	var stop_errors := {}
	for coord in best:
		if coord == start or (route_cells != null and not route_cells.has(coord)): continue
		var state: int = best[coord]
		var chain: Array[int] = []
		var cursor_state := state
		while not routes_by_state.has(cursor_state):
			chain.append(cursor_state)
			cursor_state = parents[cursor_state]
		for index in range(chain.size() - 1, -1, -1):
			var entry: int = chain[index]
			var parent_route: Array = routes_by_state[parents[entry]]
			var point := Vector2i((entry >> 2) % width, (entry >> 2) / width)
			if not stop_errors.has(point): stop_errors[point] = Traversal.stop_error(point, context)
			var path: Array = parent_route[0].duplicate()
			var path_cost: Array = parent_route[1].duplicate()
			var path_stops: Array = parent_route[2].duplicate()
			path.append(point)
			path_cost.append(costs[entry])
			path_stops.append(stop_errors[point] == "")
			routes_by_state[entry] = [path, path_cost, path_stops]
		var built: Array = routes_by_state[state]
		var path_cost: Array = built[1]
		var route := {"schema": "hsl_movement_target_cost.v1", "coord": coord, "cost": path_cost.back(),
			"path": built[0], "path_costs": path_cost, "path_stops": built[2],
			"cost_evidence": "static-derived", "cost_source": "0x40ed50/0x40eb80"}
		var error: String = stop_errors[coord]
		if error == "":
			reachable.append(coord)
			reachable_by_coord[coord] = route
			blocked_coords.erase(coord)
		else:
			transit_by_coord[coord] = route
			if occupants.is_empty(): occupants = Traversal.Footprint.occupants(units)
			blocked_coords[coord] = {"reason": error, "transit": true, "blockers": _move_target_blockers(occupants.get(coord, {}), coord, tiles)}
	return {
		"ok": true,
		"schema": "hsl_movement_reachability.v1",
		"actor_id": str(unit.get("id", "")),
		"start_coord": start,
		"move_budget": move_budget,
		"reachable_coords": reachable,
		"reachable_by_coord": reachable_by_coord,
		"transit_by_coord": transit_by_coord,
		"blocked_coords": blocked_coords,
		"cost_source": "0x40ed50/0x40eb80",
		"unresolved_semantics": [
			"original equal-cost path tie-break ordering",
			"full native map-flag lifecycle; body occupancy is derived from current actors",
			"runtime-confirmed movement budget for every actor",
		],
	}


## The flood's row-major tables for a context prepared without this `map_size` (e.g. by a
## caller of `Traversal.prepare` that passed no map): the same values read from the
## context's per-cell dictionaries.
static func _cell_rows(context: Dictionary, map_size: Vector2i) -> Dictionary:
	var width := maxi(0, map_size.x)
	var height := maxi(0, map_size.y)
	var cell_flags := PackedInt32Array()
	cell_flags.resize(width * height)
	var cell_heights := PackedInt32Array()
	cell_heights.resize(width * height)
	var cell_costs := PackedInt32Array()
	cell_costs.resize(width * height)
	var cell_pass := PackedByteArray()
	cell_pass.resize(width * height)
	for y in range(height):
		for x in range(width):
			var point := Vector2i(x, y)
			var cell := y * width + x
			cell_flags[cell] = int(context["flags"].get(point, 0))
			cell_heights[cell] = int(context["heights"].get(point, 0))
			cell_costs[cell] = int(context["move_costs"].get(point, 1))
			cell_pass[cell] = 1 if context["no_block"].has(point) else 0
	return {"cell_flags": cell_flags, "cell_heights": cell_heights, "cell_costs": cell_costs, "cell_pass": cell_pass}


static func path_costs(path: Array, units: Array, tiles: Dictionary, actor_id: String) -> Array:
	if path.is_empty(): return []
	var actor := {}
	for unit in units:
		if unit.get("id") == actor_id: actor = unit
	var context := Traversal.prepare(actor, units, tiles)
	if not context["ok"]: return []
	var costs: Array = [0]
	for index in range(1, path.size()):
		if _manhattan(path[index - 1], path[index]) != 1 or Traversal.transition_error(path[index - 1], path[index], context, tiles) != "": return []
		costs.append(int(costs.back()) + Traversal.step_cost(path[index - 1], path[index], path[maxi(0, index - 2)], context, tiles))
	return costs


static func attack_range(origin: Vector2i, min_range: int, max_range: int, map_size: Vector2i) -> Array:
	var lower := maxi(min_range, 0)
	var upper := maxi(max_range, lower)
	var coords: Array = []
	for y in range(map_size.y):
		for x in range(map_size.x):
			var coord := Vector2i(x, y)
			var distance := _manhattan(origin, coord)
			if distance >= lower and distance <= upper:
				coords.append(coord)
	return coords


static func attack_pattern_cells(origin: Vector2i, offsets: Array, map_size: Vector2i) -> Array:
	var result: Array = []
	for offset in offsets:
		var cell := origin + Vector2i(int(offset[0]), int(offset[1]))
		if cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y:
			result.append(cell)
	return result


## `occupant` is the unit standing on `coord` (Footprint.occupants／unit_at), {} for none.
static func _move_target_blockers(occupant: Dictionary, coord: Vector2i, tiles: Dictionary) -> Array:
	var blockers := []
	if not occupant.is_empty():
		var role := ActorRoleRules.battle_actor_role(occupant)
		blockers.append({
			"schema": "hsl_move_target_blocker.v1",
			"blocker_type": "map_object" if role == "map_object" else "unit",
			"actor_id": str(occupant.get("id", "")),
			"actor_role": role,
			"coord": coord,
			"unresolved_semantics": ["exact original occupancy/blocking semantics"],
		})
	var tile: Dictionary = tiles.get(coord, {})
	if bool(tile.get("blocks_movement", false)) or int(tile.get("movement_flags", 0)) & OBSTACLE_MASK:
		blockers.append({
			"schema": "hsl_move_target_blocker.v1",
			"blocker_type": "terrain",
			"terrain": str(tile.get("terrain", "unknown")),
			"coord": coord,
			"unresolved_semantics": ["exact original blocker footprint and path tie-break"],
		})
	return blockers


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

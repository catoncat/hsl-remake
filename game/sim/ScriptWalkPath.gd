extends RefCounted
## The cell route a scripted walk (actWalk*／actWalkPrevInsertObject*／actWalkFollow*)
## follows, ported from the original's script path chain. Walk state 0x453b90 state 0x32
## calls 0x4111d0(actor, dest, 0x12, 0xc) → 0x411080: floods of radius 18, 16, 14, 12
## (0x40f350 script mode: 0x4c1a74 lifts the map bounds, only the (2r+1)² buffer of
## 0x40f200 limits the flood); each wider flood only moves the destination to its nearest
## flooded cell (0x413900 → 0x413740, row-major, Manhattan), the radius-12 flood then yields
## the path by 0x410a50／0x410730 (strict-descent depth-first search, fixed direction
## order). When that path is walked and the actor is not on the target cell the chain runs
## again; it stops when 0x410a50 has nothing to walk (the nearest cell is the actor's own).
## The flood keeps 0x40ed50's mode 1 (ground)／mode 6 (flying) rules: WRD 0x4000 stops both;
## a ground step with a height gap of 3 or more stops, an uphill step of 1–2 costs that much
## extra budget after arrival. Cells outside the map read as the previous height with no
## flags (0x40eb40); a walk starting outside the map enters it at no height cost unless the
## cell is height 0xff (0x40f200 passes 0x80 as the source height).
## The flood reads the terrain only (0x40f350 mode 1／6 without unit blocks). A battle-time
## commit passes a `walk` context and 0x413740 runs as the original's: cells holding a unit
## (0x70000) are skipped, an equal-distance cell replaces the kept one when 0x458c10 is odd,
## and a candidate with three or more in-map neighbours meeting (mask | 0x4000) is dropped
## when rand(100) < 80, both drawn on the global stream (0x458c10／0x458c80). Which cells
## hold a unit is the caller's registration set (ScriptActorCreationRules) plus, for the
## first 0x4111d0 call only, the walker's own in-map start cell (see _registered). The opening
## presentation passes none: it draws nothing and keeps the first equal cell and every
## candidate, walking to the cells the opening snapshot commits.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_walk_path.md
##   rules: remake-invented (the opening presentation walks without draws: first equal cell kept, no candidate dropped)
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const HARD_BLOCK := 0x4000
const MAX_HEIGHT_STEP := 2
const OUTSIDE_SOURCE := 0x80
const RADII: Array[int] = [0x12, 0x10, 0xe, 0xc]
const MAX_SEGMENTS := 64
## 0x410730 direction codes: 1 up, 2 down, 3 left, 4 right.
const STEP := {1: Vector2i(0, -1), 2: Vector2i(0, 1), 3: Vector2i(-1, 0), 4: Vector2i(1, 0)}
## No cell: nearest_stoppable's origin skip is not used. The walker's start cell is skipped
## through `taken` in the first call only (_registered); a later call's flood origin, its
## registration lifted, stays a 0x413740 candidate.
const NO_ORIGIN := Vector2i(0x7fffffff, 0x7fffffff)


static func cell_of(world: Vector2, cell_size: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / cell_size.x), floori(world.y / cell_size.y))


static func cell_centre(cell: Vector2i, cell_size: Vector2) -> Vector2:
	return Vector2(cell) * cell_size + cell_size * 0.5


## True when a walker may step from `from_cell` onto `to_cell` under the flood's terrain
## rules. Cells outside the map read as the current height with no flags (0x40eb40), so
## leaving or re-entering the map never fails the height test here.
static func can_step(tiles: Dictionary, map_size: Vector2i, from_cell: Vector2i, to_cell: Vector2i, flying: bool) -> bool:
	if not _inside(map_size, to_cell):
		return true
	var tile: Dictionary = tiles.get(to_cell, {})
	if int(tile.get("movement_flags", 0)) & HARD_BLOCK:
		return false
	if flying:
		return true
	if bool(tile.get("blocks_movement", false)):
		return false
	if not _inside(map_size, from_cell):
		return true
	return absi(int(tile.get("elevation", 0)) - _height(tiles, map_size, from_cell)) <= MAX_HEIGHT_STEP


## {status, cells, points}: `cells` from the start cell to the end cell; `points` are the
## world points the actor walks through after its start (cell centres, the last one the
## script's exact target when that cell is reached). Status: `same_cell`, `grid_path`,
## `nearest_reachable` (the chain stopped short of the target) or `no_terrain`.
## `walk` (battle-time commit): {rng, draws, taken, words, side} — the global stream and the
## array its draws are recorded in, the cells holding a unit, the 0x40d800 cell words and the
## walker's side word (the radius-12 scan's mask); empty draws nothing (see the header).
static func route(tiles: Dictionary, map_size: Vector2i, start: Vector2, target: Vector2, cell_size: Vector2, flying: bool = false, walk: Dictionary = {}) -> Dictionary:
	var start_cell := cell_of(start, cell_size)
	var target_cell := cell_of(target, cell_size)
	if tiles.is_empty() or map_size.x <= 0 or map_size.y <= 0:
		return {"status": "no_terrain", "cells": [start_cell, target_cell], "points": [target]}
	if start_cell == target_cell:
		return {"status": "same_cell", "cells": [start_cell], "points": [target]}
	var cells: Array = [start_cell]
	var current := start_cell
	var seen := {start_cell: true}
	for segment_index in range(MAX_SEGMENTS):
		if current == target_cell:
			break
		var segment := _segment(tiles, map_size, current, target_cell, flying, _registered(walk, map_size, start_cell) if segment_index == 0 else walk)
		if segment.is_empty():
			break
		cells.append_array(segment)
		current = segment.back()
		if seen.has(current):
			break
		seen[current] = true
	var reached := current == target_cell
	var points: Array = []
	for index in range(1, cells.size()):
		points.append(cell_centre(cells[index], cell_size))
	if reached and not points.is_empty():
		points[points.size() - 1] = target
	return {"status": "grid_path" if reached else "nearest_reachable", "cells": cells, "points": points}


## `walk` for the first 0x4111d0 call (0x453d71): the walker still holds its registration on
## its start cell (0x411a30 at creation, 0x407c24／0x407dcb, or at its last stop, 0x4541a1;
## 0x411900 marks in-map cells only), so 0x413740 skips that cell and 0x40d800 reads the
## walker's side word there. 0x453b90 sub 0 lifts it (0x411b90 at 0x453dcb, when 0x407940 is
## 0) only after that call succeeds; the later calls (0x45412d) run without it.
static func _registered(walk: Dictionary, map_size: Vector2i, cell: Vector2i) -> Dictionary:
	if walk.is_empty() or not _inside(map_size, cell):
		return walk
	var first := walk.duplicate()
	first["taken"] = walk.get("taken", {}).duplicate()
	first["taken"][cell] = true
	first["words"] = walk.get("words", {}).duplicate()
	first["words"][cell] = int(first["words"].get(cell, 0)) | int(walk.get("side", 0))
	return first


## The cell a walk from `start_cell` to `target_cell` stops on: 0x453b90 registers the cell
## the chain ends on (0x411a30 at 0x4541a1), the target when reached, else the nearest
## reachable end. Rule side: ScriptActorCreationRules commits battle-time walks with it.
static func stop_cell(tiles: Dictionary, map_size: Vector2i, start_cell: Vector2i, target_cell: Vector2i, cell_size: int, flying: bool, walk: Dictionary = {}) -> Vector2i:
	var size := Vector2(cell_size, cell_size)
	var result := route(tiles, map_size, cell_centre(start_cell, size), cell_centre(target_cell, size), size, flying, walk)
	return target_cell if result["status"] == "no_terrain" else result["cells"].back()


## One 0x411080 call from `origin`: the cells walked (without `origin`), empty when the
## call returns 0. The wider floods scan with mask 0 (0x413900(dest, 0)), the radius-12 one
## with the walker's side word.
static func _segment(tiles: Dictionary, map_size: Vector2i, origin: Vector2i, target: Vector2i, flying: bool, walk: Dictionary = {}) -> Array:
	var dest: Variant = target
	var flood := {}
	for radius in RADII:
		flood = _flood(tiles, map_size, origin, radius, flying)
		var nearest: Variant = _nearest(flood, dest, walk, int(walk.get("side", 0)) if radius == RADII.back() else 0)
		if radius == RADII.back():
			dest = nearest
		elif nearest != null:
			dest = nearest
	if dest == null:
		return []
	return _descend(flood, dest)


## 0x40f200／0x40ed50: each cell's arrival budget (radius + 1 at the origin, 0 unreached)
## in the (2r+1)² buffer centred on `origin`.
static func _flood(tiles: Dictionary, map_size: Vector2i, origin: Vector2i, radius: int, flying: bool) -> Dictionary:
	var width := radius * 2 + 1
	var values := PackedByteArray()
	values.resize(width * width)
	values[radius * width + radius] = radius + 1
	var flood := {"origin": origin, "radius": radius, "width": width, "values": values, "tiles": tiles, "map_size": map_size, "flying": flying}
	var source := _height(tiles, map_size, origin) if _inside(map_size, origin) else OUTSIDE_SOURCE
	_flood_step(flood, origin + Vector2i(0, -1), radius, 0, source)
	_flood_step(flood, origin + Vector2i(0, 1), radius, 1, source)
	_flood_step(flood, origin + Vector2i(-1, 0), radius, 2, source)
	_flood_step(flood, origin + Vector2i(1, 0), radius, 3, source)
	return flood


## 0x40ed50, flood directions 0 up, 1 down, 2 left, 3 right: a cell stores the budget it is
## reached with when that beats its stored value, then passes on 1 + uphill extra less;
## an up／down cell goes on, then left, right; a left／right cell goes up, down, then on.
static func _flood_step(flood: Dictionary, cell: Vector2i, budget: int, direction: int, previous_height: int) -> void:
	var values: PackedByteArray = flood["values"]
	var origin: Vector2i = flood["origin"]
	var radius: int = flood["radius"]
	var width: int = flood["width"]
	var tiles: Dictionary = flood["tiles"]
	var map_size: Vector2i = flood["map_size"]
	var flying: bool = flood["flying"]
	while true:
		var bx := cell.x - origin.x + radius
		var by := cell.y - origin.y + radius
		if bx < 0 or by < 0 or bx >= width or by >= width:
			return
		var index := by * width + bx
		var inside := _inside(map_size, cell)
		if inside and int((tiles.get(cell, {}) as Dictionary).get("movement_flags", 0)) & HARD_BLOCK:
			return
		var height: int = _height(tiles, map_size, cell) if inside else previous_height
		var extra := 0
		if not flying:
			var gap := height - previous_height
			extra = gap if gap >= 0 else (-gap if -gap >= 3 else 0)
			if previous_height == OUTSIDE_SOURCE:
				extra = 0x10 if height == 0xff else 0
			if extra > MAX_HEIGHT_STEP:
				return
		if budget <= values[index]:
			return
		values[index] = budget
		budget -= 1 + extra
		if budget < 1:
			return
		previous_height = height
		match direction:
			0, 1:
				_flood_step(flood, cell + (Vector2i(0, -1) if direction == 0 else Vector2i(0, 1)), budget, direction, height)
				_flood_step(flood, cell + Vector2i(-1, 0), budget, 2, height)
				cell += Vector2i(1, 0)
				direction = 3
			2:
				_flood_step(flood, cell + Vector2i(0, -1), budget, 0, height)
				_flood_step(flood, cell + Vector2i(0, 1), budget, 1, height)
				cell += Vector2i(-1, 0)
			_:
				_flood_step(flood, cell + Vector2i(0, -1), budget, 0, height)
				_flood_step(flood, cell + Vector2i(0, 1), budget, 1, height)
				cell += Vector2i(1, 0)


static func _value(flood: Dictionary, cell: Vector2i) -> int:
	var origin: Vector2i = flood["origin"]
	var radius: int = flood["radius"]
	var width: int = flood["width"]
	var bx := cell.x - origin.x + radius
	var by := cell.y - origin.y + radius
	if bx < 0 or by < 0 or bx >= width or by >= width:
		return -1
	return (flood["values"] as PackedByteArray)[by * width + bx]


## 0x413740 (nearest mode): the flooded cell with the smallest Manhattan distance to `dest`,
## scanning the buffer row by row; null when none. Without `walk` the first of equal cells is
## kept and no candidate is dropped; with it AINavigationRules.nearest_stoppable compares
## the unoccupied cells (the walker's current cell included after the first call) with the
## coin and the crowded drop, 0x40d800 counting neighbours that meet blocker_mask(`side`).
static func _nearest(flood: Dictionary, dest: Vector2i, walk: Dictionary = {}, side: int = 0) -> Variant:
	var origin: Vector2i = flood["origin"]
	var radius: int = flood["radius"]
	var width: int = flood["width"]
	var values: PackedByteArray = flood["values"]
	var taken: Dictionary = walk.get("taken", {})
	var best := 600000
	var found: Variant = null
	var cells: Array = []
	for by in range(width):
		for bx in range(width):
			if values[by * width + bx] == 0:
				continue
			var cell := Vector2i(origin.x - radius + bx, origin.y - radius + by)
			if not walk.is_empty():
				if not taken.has(cell):
					cells.append(cell)
				continue
			var distance := absi(cell.x - dest.x) + absi(cell.y - dest.y)
			if distance < best:
				best = distance
				found = cell
	if walk.is_empty():
		return found
	var pick: Dictionary = AINavigationRules.nearest_stoppable(cells, dest, NO_ORIGIN, walk.get("rng"), walk["draws"], walk.get("words", {}), AINavigationRules.blocker_mask(side), flood["map_size"])
	return pick.get("cell")


## 0x410a50／0x410730: the cells from the flood origin to `dest`, each strictly lower in the
## buffer than the one before and not below `dest`. The first step's order follows the
## offset's signs and sizes; a later step tries its own direction first, then the
## perpendicular pair ordered by where `dest` lies from the origin. Empty when `dest` is
## the origin.
static func _descend(flood: Dictionary, dest: Vector2i) -> Array:
	var origin: Vector2i = flood["origin"]
	var floor_value := _value(flood, dest)
	if floor_value <= 0 or dest == origin:
		return []
	var dx := dest.x - origin.x
	var dy := dest.y - origin.y
	var order: Array
	if dx < 1:
		if dy < 1:
			order = [3, 1, 4, 2] if dy < dx else [1, 3, 2, 4]
		else:
			order = [3, 2, 4, 1] if dy < dx else [2, 3, 1, 4]
	else:
		if dy < 1:
			order = [4, 1, 3, 2] if dy < dx else [1, 4, 2, 3]
		else:
			order = [4, 2, 3, 1] if dy < dx else [2, 4, 1, 3]
	var search := {
		"flood": flood, "dest": dest, "floor": floor_value, "failed": {},
		"horizontal": [4, 3] if origin.x < dest.x else [3, 4],
		"vertical": [2, 1] if origin.y < dest.y else [1, 2],
	}
	var start_value := _value(flood, origin)
	for direction in order:
		var path := _descend_step(search, origin + STEP[direction], direction, 1, start_value)
		if not path.is_empty():
			return path
	return []


## 0x410730(x, y, direction, depth, previous value). Once the value test passes the result
## depends only on the cell and direction, so failures are remembered.
static func _descend_step(search: Dictionary, cell: Vector2i, direction: int, depth: int, previous: int) -> Array:
	if depth > 99:
		return []
	var value := _value(search["flood"], cell)
	if value < int(search["floor"]) or value >= previous:
		return []
	if cell == search["dest"]:
		return [cell]
	var key := Vector3i(cell.x, cell.y, direction)
	var failed: Dictionary = search["failed"]
	if failed.has(key):
		return []
	var turns: Array = [direction]
	turns.append_array(search["horizontal"] if direction <= 2 else search["vertical"])
	for turn in turns:
		var path := _descend_step(search, cell + STEP[turn], turn, depth + 1, value)
		if not path.is_empty():
			path.push_front(cell)
			return path
	failed[key] = true
	return []


## World length of walking `points` from `start`.
static func length(start: Vector2, points: Array) -> float:
	var total := 0.0
	var from := start
	for point in points:
		total += from.distance_to(point)
		from = point
	return total


static func _inside(map_size: Vector2i, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y


## 0x40eb40's height byte for an in-map cell: its WRD height, 0xff where it blocks movement.
static func _height(tiles: Dictionary, map_size: Vector2i, cell: Vector2i) -> int:
	var tile: Dictionary = tiles.get(cell, {})
	return 255 if bool(tile.get("blocks_movement", false)) else int(tile.get("elevation", 0))

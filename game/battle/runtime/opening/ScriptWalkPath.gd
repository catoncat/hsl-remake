extends RefCounted
## The cell route a scripted walk (actWalk*／actWalkPrevInsertObject*／actWalkFollow*)
## follows. The original walk state 0x453b90 state 0x32 asks 0x4111d0 → 0x411080 for a
## four-neighbour path buffer (direction codes 1..4, one per cell) from a script-mode flood
## (0x40f350 sets 0x4c1a74, which lifts the map-pixel bounds of 0x40ed50; 0x40eb40 reads an
## outside cell as the current height with no flags), and steps the actor cell by cell; it
## does not glide through walls. The flood keeps the terrain rules of 0x40ed50: the source
## height 0xff and a height gap above two stop ground walkers, the WRD 0x4000 hard block
## stops every mode. Unit occupancy is not read here: script walks are presentation of
## committed PlayLoop results (the existing script-departure contract ignores occupants).
## When the target is walled off the walker ends on the reachable cell nearest to it, as
## the original's retry at the path end (0x4111d0 returning 0) stops the walk.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_walk_path.md; provisional (breadth-first tie order up／down／left／right, nearest-reachable fallback metric)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const HARD_BLOCK := 0x4000
const MAX_HEIGHT_STEP := 2
const NEIGHBOURS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]


static func cell_of(world: Vector2, cell_size: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / cell_size.x), floori(world.y / cell_size.y))


static func cell_centre(cell: Vector2i, cell_size: Vector2) -> Vector2:
	return Vector2(cell) * cell_size + cell_size * 0.5


## True when a walker may step from `from_cell` onto `to_cell` (both already inside the
## search box). Cells outside the map read as the current height with no flags (0x40eb40),
## so leaving or re-entering the map never fails the height test (see `route` for when
## outside cells are searched at all).
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
## `nearest_reachable` (target walled off) or `no_terrain` (straight line).
static func route(tiles: Dictionary, map_size: Vector2i, start: Vector2, target: Vector2, cell_size: Vector2, flying: bool = false) -> Dictionary:
	var start_cell := cell_of(start, cell_size)
	var target_cell := cell_of(target, cell_size)
	if tiles.is_empty() or map_size.x <= 0 or map_size.y <= 0:
		return {"status": "no_terrain", "cells": [start_cell, target_cell], "points": [target]}
	if start_cell == target_cell:
		return {"status": "same_cell", "cells": [start_cell], "points": [target]}
	# Outside cells join the search only for a walk that starts or ends off the map (script
	# entrances and exits), one cell beyond the farther endpoint; an in-map walk never
	# detours around a wall through the map edge.
	var low := Vector2i.ZERO
	var high := map_size - Vector2i.ONE
	if not _inside(map_size, start_cell) or not _inside(map_size, target_cell):
		low = Vector2i(mini(0, mini(start_cell.x, target_cell.x)) - 1, mini(0, mini(start_cell.y, target_cell.y)) - 1)
		high = Vector2i(maxi(map_size.x - 1, maxi(start_cell.x, target_cell.x)) + 1, maxi(map_size.y - 1, maxi(start_cell.y, target_cell.y)) + 1)
	var previous := {start_cell: start_cell}
	var queue: Array[Vector2i] = [start_cell]
	var head := 0
	var reached := false
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == target_cell:
			reached = true
			break
		for offset in NEIGHBOURS:
			var next: Vector2i = cell + offset
			if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y or previous.has(next):
				continue
			if not can_step(tiles, map_size, cell, next, flying):
				continue
			previous[next] = cell
			queue.append(next)
	var end_cell := target_cell
	var status := "grid_path"
	if not reached:
		# Walled off: the reachable cell nearest the target (Manhattan, then the earlier
		# breadth-first visit, i.e. the shorter walk).
		status = "nearest_reachable"
		var best := -1
		for cell in queue:
			var distance: int = absi(cell.x - target_cell.x) + absi(cell.y - target_cell.y)
			if best < 0 or distance < best:
				best = distance
				end_cell = cell
	var cells: Array = []
	var walk := end_cell
	while walk != start_cell:
		cells.push_front(walk)
		walk = previous[walk]
	cells.push_front(start_cell)
	var points: Array = []
	for index in range(1, cells.size()):
		points.append(cell_centre(cells[index], cell_size))
	if reached and not points.is_empty():
		points[points.size() - 1] = target
	return {"status": status, "cells": cells, "points": points}


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


static func _height(tiles: Dictionary, map_size: Vector2i, cell: Vector2i) -> int:
	var tile: Dictionary = tiles.get(cell, {})
	return 255 if bool(tile.get("blocks_movement", false)) else int(tile.get("elevation", 0))

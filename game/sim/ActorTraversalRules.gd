extends RefCounted
## Source single-cell/3x3 ground/flying traversal and whole-body stopping.
## Only proposals/geometry; PlayLoop owns traits, coordinates and equipment.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_actor_traversal.md; static-derived docs/evidence_packets/static_reverse/original_large_actor.md; static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md; static-derived docs/evidence_packets/static_reverse/original_death_disposal.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Number = preload("res://game/sim/SkillResourceRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const HARD_BLOCK := 0x4000
const NO_STOP := 0x100000
const MAP_FLAGS := 0x974000
const MASKS := {2: 0x64000, 3: 0x54000, 6: HARD_BLOCK, 7: 0x34000}
## Side bits and the 0x40bab0 ground mode come from the unit's installed player_mode
## (ActorRoleRules.side_mask); a "npc" role is the development fixture for a pmNPC
## occupant without player_mode.
const Sides = preload("res://game/sim/ActorRoleRules.gd")
const FIXTURE_SIDES := {"npc": 0x40000}


static func trait_error(value: Variant) -> String:
	if not value is Dictionary or not value.get("flying") is bool or not value.get("no_block") is bool:
		return "missing_actor_traversal"
	var size := Number._integer(value.get("size_type"))
	if size < 0: return "invalid_actor_size"
	if size not in [0,1]: return "unsupported_actor_size"
	return ""


static func source(actor: Dictionary, book: Dictionary) -> Dictionary:
	var traits: Variant = book.get("actors", {}).get(str(actor.get("actor_id", "")), {}).get("traversal")
	var error := trait_error(traits)
	return {"ok": false, "reason": error} if error != "" else {"ok": true, "traits": traits.duplicate(true)}


static func actor_error(actor: Dictionary, book: Dictionary) -> String:
	if trait_error(actor.get("traversal")) != "": return "invalid_actor_traversal"
	var expected := source(actor, book)
	if not expected["ok"]: return expected["reason"]
	if actor.get("traversal") != expected["traits"]: return "inconsistent_actor_traversal"
	if _side(actor) == 0: return "invalid_traversal_side"
	return ""


static func _side(unit: Dictionary) -> int:
	var side := Sides.side_mask(unit)
	return side if side != 0 else int(FIXTURE_SIDES.get(str(unit.get("battle_actor_role", "")), 0))


static func mode(actor: Dictionary) -> int:
	if trait_error(actor.get("traversal")) != "": return -1
	if actor["traversal"]["flying"]: return 6
	# 0x40bab0: pmPlayer bit first -> 2, else pmEnemy -> 3, else pmNPC -> 7.
	var side := _side(actor)
	if side & 0x10000: return 2
	if side & 0x20000: return 3
	if side & 0x40000: return 7
	return -1


static func tile_error(tile: Variant) -> String:
	if not tile is Dictionary: return "invalid_traversal_tile"
	var cost := Number._integer(tile.get("move_cost", 1))
	if cost <= 0 or cost > 100: return "invalid_ai_move_cost"
	var flags := Number._integer(tile.get("movement_flags", 0))
	if flags < 0 or (flags & ~MAP_FLAGS) != 0: return "invalid_ai_movement_flags"
	var elevation := Number._integer(tile.get("elevation", 0))
	if elevation < 0 or elevation > 255: return "invalid_traversal_height"
	if tile.has("blocks_movement") and not tile["blocks_movement"] is bool: return "invalid_traversal_blocker"
	return ""


static func elevation(tile: Dictionary) -> int:
	# The existing explicit barrier flag means the original 0xff height, not the
	# independent hard-block map bit. Flying may cross height barriers.
	return 255 if tile.get("blocks_movement", false) else int(tile.get("elevation", 0))


## Per-cell tables read by every transition of a flood: map flags (unit side bits are
## OR-ed in by `prepare`), the source height (`elevation`) and the arrival cost, plus the
## largest arrival cost; the first `tile_error` in `tiles` order fails them. With a
## `map_size` the same three values are also laid out row-major over the map
## (`cell_flags`／`cell_heights`／`cell_costs`, missing tiles 0／0／1) for the flood's
## inner loop. They depend on `tiles` and `map_size` alone, so a caller holding a read-only
## map may build them once and pass them to every `prepare` over that map.
static func tile_tables(tiles: Dictionary, map_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var flags := {}
	var heights := {}
	var move_costs := {}
	var max_cost := 1
	var width := maxi(0, map_size.x)
	var height := maxi(0, map_size.y)
	var cell_flags := PackedInt32Array()
	cell_flags.resize(width * height)
	cell_flags.fill(0)
	var cell_heights := PackedInt32Array()
	cell_heights.resize(width * height)
	cell_heights.fill(0)
	var cell_costs := PackedInt32Array()
	cell_costs.resize(width * height)
	cell_costs.fill(1)
	for point in tiles:
		var tile: Dictionary = tiles[point]
		var error := tile_error(tile)
		if error != "": return {"ok": false, "reason": error}
		flags[point] = int(tile.get("movement_flags", 0))
		heights[point] = elevation(tile)
		move_costs[point] = int(tile.get("move_cost", 1))
		max_cost = maxi(max_cost, move_costs[point])
		if point is Vector2i and point.x >= 0 and point.y >= 0 and point.x < width and point.y < height:
			var cell: int = point.y * width + point.x
			cell_flags[cell] = flags[point]
			cell_heights[cell] = heights[point]
			cell_costs[cell] = move_costs[point]
	return {"ok": true, "flags": flags, "heights": heights, "move_costs": move_costs, "max_cost": max_cost,
		"size": Vector2i(width, height), "cell_flags": cell_flags, "cell_heights": cell_heights, "cell_costs": cell_costs}


## `tables`: `tile_tables(tiles, map_size)` when the caller holds them for this map; empty
## builds them here over `map_size`. The context shares `heights`／`move_costs`／
## `cell_heights`／`cell_costs` with the tables and owns `flags`／`cell_flags`; `cell_pass`
## marks the in-map cells of `no_block`.
static func prepare(actor: Dictionary, units: Array, tiles: Dictionary, tables: Dictionary = {}, map_size: Vector2i = Vector2i.ZERO) -> Dictionary:
	var movement_mode := mode(actor)
	if movement_mode < 0: return {"ok": false, "reason": "invalid_actor_traversal"}
	var map := tables if not tables.is_empty() else tile_tables(tiles, map_size)
	if not map["ok"]: return {"ok": false, "reason": map["reason"]}
	var flags: Dictionary = map["flags"].duplicate() if not tables.is_empty() else map["flags"]
	var cell_flags: PackedInt32Array = map["cell_flags"].duplicate() if not tables.is_empty() else map["cell_flags"]
	var size: Vector2i = map["size"]
	var heights: Dictionary = map["heights"]
	var move_costs: Dictionary = map["move_costs"]
	var occupied := {}
	var passable_actors := {}
	for other in units:
		if not Footprint.Presence.living(other) or other.get("id") == actor.get("id"): continue
		if trait_error(other.get("traversal")) != "": return {"ok": false, "reason": "invalid_occupant_traversal"}
		var side := _side(other)
		if side == 0: return {"ok": false, "reason": "invalid_traversal_side"}
		for point in Footprint.cells(other):
			flags[point] = int(flags.get(point, 0)) | side
			if point.x >= 0 and point.y >= 0 and point.x < size.x and point.y < size.y: cell_flags[point.y * size.x + point.x] |= side
			if other["traversal"]["no_block"]: passable_actors[point] = true
			else: occupied[point] = true
	for point in occupied: passable_actors.erase(point)
	var cell_pass := PackedByteArray()
	cell_pass.resize(size.x * size.y)
	cell_pass.fill(0)
	for point in passable_actors:
		if point.x >= 0 and point.y >= 0 and point.x < size.x and point.y < size.y: cell_pass[point.y * size.x + point.x] = 1
	return {"ok": true, "mode": movement_mode, "mask": MASKS[movement_mode], "flags": flags, "heights": heights, "move_costs": move_costs,
		"max_cost": map["max_cost"], "occupied": occupied, "no_block": passable_actors, "radius": Footprint.radius(actor), "origin": actor["coord"],
		"size": size, "cell_flags": cell_flags, "cell_heights": map["cell_heights"], "cell_costs": map["cell_costs"], "cell_pass": cell_pass}


## `_tiles` is the map the context was prepared from; the checks read the context's
## per-cell tables (the parameter stays so callers keep one shape with `prepare`).
static func transition_error(current: Vector2i, target: Vector2i, context: Dictionary, _tiles: Dictionary) -> String:
	var mode := int(context["mode"])
	if int(context["radius"]) == 1:
		for y in range(-1,2):
			for x in range(-1,2):
				var point := target + Vector2i(x,y)
				if point == context["origin"]: continue
				var flags := int(context["flags"].get(point,0))
				if mode == 6:
					if flags & HARD_BLOCK: return "footprint_blocked"
				elif flags & 0x74000 or int(context["heights"].get(point, 0)) == 255:
					return "footprint_blocked"
	var value := int(context["flags"].get(target, 0))
	if value & int(context["mask"]):
		if mode == 6 or not context["no_block"].has(target):
			return "target_occupied" if context["occupied"].has(target) else "target_blocked_by_terrain"
	if mode != 6 and absi(height_delta(current, target, context)) >= 3:
		return "target_blocked_by_height"
	return ""


static func height_delta(current: Vector2i, target: Vector2i, context: Dictionary) -> int:
	var heights: Dictionary = context["heights"]
	var before := int(heights.get(current, 0))
	var after := int(heights.get(target, 0))
	return (16 if after == 255 else 0) if before == 128 else after - before


static func stop_error(point: Vector2i, context: Dictionary) -> String:
	if int(context["radius"]) == 1:
		for y in range(-1,2):
			for x in range(-1,2):
				var cell := point + Vector2i(x,y)
				var flags := int(context["flags"].get(cell,0))
				if flags & 0x70000 or context["occupied"].has(cell) or context["no_block"].has(cell): return "footprint_occupied"
				if flags & (NO_STOP | HARD_BLOCK): return "footprint_cannot_stop"
	if (context["occupied"].has(point) or int(context["flags"].get(point, 0)) & 0x70000) and not context["no_block"].has(point): return "target_occupied"
	if int(context["flags"].get(point, 0)) & NO_STOP and not context["no_block"].has(point): return "target_cannot_stop"
	return ""


static func onward_penalty(current: Vector2i, previous: Vector2i, context: Dictionary) -> int:
	if current == previous or int(context["mode"]) == 6: return 0
	var flags: Dictionary = context["flags"]
	var mask := int(context["mask"])
	for delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var point: Vector2i = current + delta
		if point != previous and int(flags.get(point, 0)) & mask: return 1
	return 0


## The cost of arriving on `target` from `current` (tile cost plus climb); `step_cost`
## adds the onward-clearance penalty of leaving `current`, which depends on the cell left
## and the one before it, not on `target` — a flood adds it once per expanded state.
static func arrival_cost(current: Vector2i, target: Vector2i, context: Dictionary) -> int:
	var climb := maxi(0, height_delta(current, target, context)) if int(context["mode"]) != 6 else 0
	return int(context["move_costs"].get(target, 1)) + climb


static func step_cost(current: Vector2i, target: Vector2i, previous: Vector2i, context: Dictionary, _tiles: Dictionary) -> int:
	return arrival_cost(current, target, context) + onward_penalty(current, previous, context)


## A large actor's footprint check. `standing`: the actor already stands on `coord` (roster
## load, checkpoint restore) — the original installs an opening actor without a terrain test
## (install pixel 0x407ec0, STORY walk endpoint; the opening snapshot has 13 關 051 ×4, 59 關 060
## and 80 關 068 on 0xff cells at round 1), so only the other units' occupancy is checked; a new
## placement (script creation, recruit) is also a legal stop on the terrain.
static func placement_error(actor: Dictionary, units: Array, tiles: Dictionary, map_size: Vector2i, standing := false) -> String:
	if int(actor["traversal"]["size_type"]) == 0 or actor.get("defeated",false) or actor.get("departed",false): return ""
	var center: Vector2i = actor["coord"]
	if center.x < 0 or center.y < 0 or center.x >= map_size.x or center.y >= map_size.y: return "large_actor_center_outside_map"
	var context := prepare(actor, units, tiles)
	if not context["ok"]: return context["reason"]
	if standing:
		for point in Footprint.cells(actor):
			if (int(context["flags"].get(point, 0)) & 0x70000 or context["occupied"].has(point)) and not context["no_block"].has(point): return "footprint_occupied"
		return ""
	var error := stop_error(center, context)
	if error != "": return error
	for point in Footprint.cells(actor):
		if context["mode"] != 6 and elevation(tiles.get(point,{})) == 255: return "large_actor_overlaps_terrain"
	return ""

extends RefCounted
## Load level051 WRD terrain into TacticalGridRules-compatible tile dicts.
## Source: content/generated/hsl/static/hsl01/level051_terrain.json (static-derived).
## Keep the source height byte. Ground transitions reject height gaps above two;
## 0xff is a cliff, while flying ignores height. The WRD cell word's bits 12..23
## carry source map flags (the renderer reads only `& 0xfff` as the tile index); the
## map-flag bits the traversal rules know (0x974000, in practice the 0x4000 hard block
## the level WRDs mark under houses) become `movement_flags`.
## provenance:
##   rules: resource-derived content/generated/hsl/static/hsl01/level051_terrain.json; static-derived docs/evidence_packets/static_reverse/original_story_object_terrain.md; static-derived docs/evidence_packets/static_reverse/original_movement.md; static-derived docs/evidence_packets/static_reverse/original_actor_traversal.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const DEFAULT_PATH := "res://content/generated/hsl/static/hsl01/level051_terrain.json"
## Map-flag bits of the WRD word kept as movement_flags (ActorTraversalRules.MAP_FLAGS).
const WRD_MAP_FLAG_MASK := 0x974000


## `overrides`: the scenario's `terrain_overrides` ({cell: [x, y], height: 255} or
## {cell, clear_flags}), the map edits of terrain stand objects the level's scripts insert
## (tools/hsltools/levels/scenario.py terrain_overrides; defProcStandObject mapobjBlock
## ORs 0xff000000 into the cell, mapobjClearWall clears 0x4000 — static-derived,
## docs/evidence_packets/static_reverse/original_story_object_terrain.md).
static func load_tiles(path: String = DEFAULT_PATH, overrides: Array = []) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"schema": "hsl_wrd_terrain_tiles.v1",
			"ok": false,
			"error": "missing_terrain_json",
			"path": path,
			"map_size": Vector2i.ZERO,
			"tiles": {},
			"blocking_count": 0,
		}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"schema": "hsl_wrd_terrain_tiles.v1",
			"ok": false,
			"error": "invalid_json",
			"path": path,
			"map_size": Vector2i.ZERO,
			"tiles": {},
			"blocking_count": 0,
		}
	var root: Dictionary = parsed
	if root.get("schema") != "hsl_wrd_terrain.v2": return _invalid(path, "missing_source_heights")
	if not root.get("grid") is Array: return _invalid(path, "invalid_terrain_grid")
	var grid: Array = root.get("grid", [])
	var height := grid.size()
	var width := 0
	if height > 0 and typeof(grid[0]) == TYPE_ARRAY:
		width = (grid[0] as Array).size()
	if width <= 0 or height <= 0 or width > 256 or height > 256: return _invalid(path, "invalid_terrain_size")
	var tiles := {}
	var blocking_count := 0
	for y in range(height):
		if not grid[y] is Array or grid[y].size() != width: return _invalid(path, "invalid_terrain_row")
		var row: Array = grid[y]
		for x in range(row.size()):
			if not row[x] is Dictionary: return _invalid(path, "invalid_terrain_cell")
			var cell: Dictionary = row[x]
			var height_value: Variant = cell.get("h")
			if typeof(height_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(height_value)) or height_value != int(height_value) or height_value < 0 or height_value > 255:
				return _invalid(path, "invalid_terrain_height")
			var blocked := int(height_value) == 255
			if cell.get("b") != int(blocked): return _invalid(path, "inconsistent_terrain_height")
			if blocked:
				blocking_count += 1
			var coord := Vector2i(x, y)
			tiles[coord] = {
				"coord": coord,
				"tile_id": int(cell.get("t", 0)),
				"blocks_movement": blocked,
				"elevation": int(height_value),
				"movement_flags": int(cell.get("t", 0)) & WRD_MAP_FLAG_MASK, # 0xff cliff stays the height byte, not a flag.
				"move_cost": 1,
				"source": path,
			}
	for override_value in overrides:
		if not override_value is Dictionary or not (override_value as Dictionary).get("cell") is Array or (override_value["cell"] as Array).size() != 2:
			return _invalid(path, "invalid_terrain_override")
		var cell := Vector2i(int(override_value["cell"][0]), int(override_value["cell"][1]))
		if not tiles.has(cell):
			return _invalid(path, "terrain_override_outside_map")
		var tile: Dictionary = tiles[cell]
		if override_value.has("height"):
			var was_blocked: bool = tile["blocks_movement"]
			tile["elevation"] = int(override_value["height"])
			tile["blocks_movement"] = tile["elevation"] == 255
			blocking_count += int(tile["blocks_movement"]) - int(was_blocked)
		if override_value.has("clear_flags"):
			tile["movement_flags"] = int(tile["movement_flags"]) & ~int(override_value["clear_flags"])
		tile["override_source"] = str(override_value.get("source", ""))
	return {
		"schema": "hsl_wrd_terrain_tiles.v1",
		"ok": true,
		"path": path,
		"map_size": Vector2i(width, height),
		"tiles": tiles,
		"blocking_count": blocking_count,
		"source_schema": str(root.get("schema", "")),
		"unresolved_semantics": [
			"path tie-break parity",
			"mid-bit cost masks unused on level051",
		],
	}


static func _invalid(path: String, error: String) -> Dictionary:
	return {"schema": "hsl_wrd_terrain_tiles.v1", "ok": false, "error": error, "path": path,
		"map_size": Vector2i.ZERO, "tiles": {}, "blocking_count": 0}

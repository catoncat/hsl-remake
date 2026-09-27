extends RefCounted
## Map cell edits of terrain stand objects a battle script inserts mid-battle. The WRD
## terrain (`loop["tiles"]`) is shared read-only configuration; an edit is state: the
## winfail interpreter appends it to `loop["terrain_edits"]` when the insert fires
## (saved and restored with the state, compared by same_state), and every passability
## reader takes the map through `tiles(loop)`, the configuration with the edits laid over
## it. Original: the creation path 0x42eb70 sends message -3 to the new object and
## defProcStandObject 0x43ccf0 case 10 (mapobjBlock) ORs 0xff000000 into the cell word —
## height 0xff, a cliff for ground walkers — for each cell actInsertStoryObjectXRange
## creates (WINFAIL039's collapse after the third quake); case 15 (mapobjClearWall) clears
## 0x4000 in the cell word through 0x411a10／0x411990 — the door walls WINFAIL028 events
## 3..6 and WINFAIL080 event 3 open with actInsertStoryObject. Edits the opening applies
## before first control stay in the generator's terrain_overrides (WrdTerrainTiles).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_story_object_terrain.md
##   rules: resource-derived content/imported/hsl/chapter01/battle039/source_texts/winfail039.txt
##   rules: remake-invented (edits kept as a loop state list over the shared map, memoised edited copy)

## obj_Data9 kinds whose install edits the map word, as edit fields (the same fields as
## the scenario's terrain_overrides): mapobjBlock sets the height byte to 0xff,
## mapobjClearWall clears the 0x4000 hard-block bit.
const EDITS_BY_OBJECT_KIND := {"mapobjBlock": {"height": 255}, "mapobjClearWall": {"clear_flags": 0x4000}}

## The last edited map, keyed on the configuration block it was built from and the edit
## list: rules read the map many times per step, and BattlePlayLoop._tile_tables memoises
## per-cell tables on the returned reference. Outside the loop (never copied／saved).
static var _edited := {"base": null, "edits": [], "tiles": {}}


## The map the rules read: `tiles` with `terrain_edits` applied (the block itself when no
## edit has fired). Never writes the shared block.
static func tiles(loop: Dictionary) -> Dictionary:
	var base: Dictionary = loop.get("tiles", {})
	var edits: Array = loop.get("terrain_edits", [])
	if edits.is_empty():
		return base
	if is_same(_edited["base"], base) and _edited["edits"] == edits:
		return _edited["tiles"]
	var edited := base.duplicate()
	for edit in edits:
		var cell: Vector2i = edit["cell"]
		if edited.has(cell):
			edited[cell] = edited_tile(edited[cell], edit)
	_edited = {"base": base, "edits": edits.duplicate(true), "tiles": edited}
	return edited


## A copy of one WrdTerrainTiles cell with an edit ({height} or {clear_flags}) applied.
static func edited_tile(tile: Dictionary, edit: Dictionary) -> Dictionary:
	var out := tile.duplicate()
	if edit.has("height"):
		out["elevation"] = int(edit["height"])
		out["blocks_movement"] = out["elevation"] == 255
	if edit.has("clear_flags"):
		out["movement_flags"] = int(out.get("movement_flags", 0)) & ~int(edit["clear_flags"])
	out["edit_source"] = str(edit.get("source", ""))
	return out


## Appends the edit of `object_symbol` (if its kind edits the map) for every cell; the
## compiled winfail program carries the symbol → edit join (WinfailCompiler
## story_object_terrain). Returns the number of cells edited.
static func record(next: Dictionary, object_symbol: String, cells: Array, source: String) -> int:
	var edit: Dictionary = next.get("winfail_script_rules", {}).get("story_object_terrain", {}).get(object_symbol, {})
	if edit.is_empty():
		return 0
	var edits: Array = next.get("terrain_edits", [])
	var size: Vector2i = next.get("map_size", Vector2i.ZERO)
	var count := 0
	for cell in cells:
		if not cell is Vector2i or cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		var entry := edit.duplicate()
		entry["cell"] = cell
		entry["source"] = source
		edits.append(entry)
		count += 1
	next["terrain_edits"] = edits
	return count


## Saved-state check: a list of {cell: Vector2i inside the map, height 0..255 and／or
## clear_flags int, source String}.
static func state_error(loop: Dictionary) -> String:
	var edits: Variant = loop.get("terrain_edits")
	if not edits is Array:
		return "invalid_saved_terrain_edits"
	var size: Vector2i = loop.get("map_size", Vector2i.ZERO)
	for edit in edits:
		if not edit is Dictionary or not edit.get("cell") is Vector2i or not edit.get("source") is String:
			return "invalid_saved_terrain_edits"
		var cell: Vector2i = edit["cell"]
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			return "invalid_saved_terrain_edits"
		if not edit.has("height") and not edit.has("clear_flags"):
			return "invalid_saved_terrain_edits"
		if edit.has("height") and (not edit["height"] is int or edit["height"] < 0 or edit["height"] > 255):
			return "invalid_saved_terrain_edits"
		if edit.has("clear_flags") and not edit["clear_flags"] is int:
			return "invalid_saved_terrain_edits"
	return ""

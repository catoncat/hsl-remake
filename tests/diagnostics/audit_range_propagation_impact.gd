extends SceneTree

## Range-propagation impact audit (lane WRANGE, original_weapon_ranges.md「地形传播」):
## on every battlefield in content/battles, the flat RANGE projection of an older checkout
## against the current RangePropagationRules flood (original 0x40f8b0／0x4100e0).
## Diagnostic only, not a gate. The old rule files go into an ignored folder first; the
## flat ones are the tree before the lane (b0f0bee3):
##
##   mkdir -p ignored/wrange-old
##   git show b0f0bee3:game/sim/SkillTargetRules.gd >| ignored/wrange-old/SkillTargetRules.gd
##   git show b0f0bee3:game/sim/TacticalGridRules.gd >| ignored/wrange-old/TacticalGridRules.gd
##   tools/godot.sh --headless --script res://tests/diagnostics/audit_range_propagation_impact.gd -- ignored/wrange-old ignored/wrange-impact.json
##
## One combo per battle and weapon pattern／skill／effect area:
##   weapon_initial        some unit's weapon cells at its opening cell differ (walls + occupants)
##   weapon_initial_walls  the same with the map's 0x4000 words only
##   weapon_any_cell       from some non-wall cell of the map the walls change the cells (mode 2)
##   cast_initial          a skill's player cast cells (mode -1) differ at the owner's opening cell
##   cast_any_cell         from some non-wall cell the walls change a cast range (mode -1)
##   area_any_cell         some non-wall centre changes an effect area (mode 2／3; not wired yet)
## Each count is changed/total, plus unique (map, name) combos and battles touched. Prints
## one WRANGE_IMPACT line; the per-battle lists go to the output JSON.

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const KEYS := ["weapon_initial", "weapon_initial_walls", "weapon_any_cell", "cast_initial", "cast_any_cell", "area_any_cell"]

var OldTargets: GDScript
var OldGrid: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: -- <old rules dir> <output json>")
		quit(2)
		return
	var old_dir := _res(str(args[0]))
	OldTargets = load(old_dir.path_join("SkillTargetRules.gd"))
	OldGrid = load(old_dir.path_join("TacticalGridRules.gd"))
	if OldTargets == null or OldGrid == null:
		push_error("audit: %s needs SkillTargetRules.gd and TacticalGridRules.gd" % old_dir)
		quit(2)
		return
	var totals := {"battles": 0, "units": 0, "units_changed": 0}
	var unique := {}
	var touched := {}
	for key in KEYS:
		totals[key] = [0, 0]
		unique[key] = {}
		touched[key] = 0
	var maps := {}
	var cache := {}
	var report := {"old_rules": old_dir, "battles": []}
	var files: Array = Array(DirAccess.get_files_at("res://content/battles")).filter(func(name): return name.ends_with(".json") and not name.begins_with("story_") and name != "campaign.json")
	files.sort()
	for name in files:
		var scenario := BattleScenario.load_file("res://content/battles/" + name)
		var loop := BattlePlayLoop.create([], "", scenario, 1)
		if not bool(loop.get("scenario_ok", false)) or loop.get("tiles", {}).is_empty():
			push_error("audit: %s did not load" % name)
			quit(1)
			return
		totals["battles"] += 1
		var map_size: Vector2i = loop["map_size"]
		var walls := RangePropagationRules.cell_words(TerrainEditRules.tiles(loop), [])
		var map_key := "%s|%s" % [str(BattleScenario.resource_path(scenario, "terrain")), str(scenario.get("scenario_rules", {}).get("terrain_overrides", ""))]
		maps[map_key] = true
		var words := RangePropagationRules.loop_words(loop)
		var data: Dictionary = loop["skill_target_data"]
		var found := {}
		for key in KEYS: found[key] = {}
		var ranges := {}
		var areas := {}
		for unit in loop["units"]:
			if not BattlePlayLoop.Presence.living(unit): continue
			var pattern := BattlePlayLoop.weapon_pattern(loop, unit)
			if pattern.get("ok", false) and not pattern["offsets"].is_empty():
				var weapon := str(pattern["name"])
				var rows: Array = loop["attack_patterns"][weapon]["data"]
				var old := _sorted(OldGrid.attack_pattern_cells(unit["coord"], pattern["offsets"], map_size))
				var changed: bool = old != BattlePlayLoop.weapon_cells(loop, unit, pattern)
				totals["units"] += 1
				if changed: totals["units_changed"] += 1
				_mark(found, "weapon_initial", weapon, changed)
				_mark(found, "weapon_initial_walls", weapon, old != RangePropagationRules.cells(RangePropagationRules.weapon_coverage(rows, unit["coord"], walls, map_size, 2, true), unit["coord"]))
				var cache_key := "%s|w|%s" % [map_key, weapon]
				if not cache.has(cache_key): cache[cache_key] = _any_cell(rows, walls, map_size, 2)
				_mark(found, "weapon_any_cell", weapon, cache[cache_key])
			for id in loop["skill_book"]["skills"]:
				if SkillResolutionRules.ownership_error(unit, id, loop["skill_book"]) != "": continue
				var fields := BattlePlayLoop.skill_fields(loop, id)
				if BattlePlayLoop.SkillTargetRules.definition_error(fields, data) != "": continue
				var old_cells := _sorted(OldTargets.cells(unit["coord"], fields, data, map_size))
				var new_cells := _sorted(BattlePlayLoop.SkillTargetRules.cells(unit["coord"], fields, data, map_size, {"words": words, "cast_mode": RangePropagationRules.PLAYER_CAST_MODE}))
				_mark(found, "cast_initial", str(id), old_cells != new_cells)
				ranges[str(fields["range"])] = true
				areas["%s|%d" % [str(fields["effect_range"]), 3 if BattlePlayLoop.SkillTargetRules.is_support(fields, data) else 2]] = true
		for range_name in ranges:
			var pattern: Dictionary = data["ranges"][range_name]
			if BattlePlayLoop.SkillTargetRules.is_line(pattern): continue
			var cache_key := "%s|c|%s" % [map_key, range_name]
			if not cache.has(cache_key): cache[cache_key] = _any_cell(pattern["data"], walls, map_size, RangePropagationRules.PLAYER_CAST_MODE)
			_mark(found, "cast_any_cell", range_name, cache[cache_key])
		for area in areas:
			var parts: PackedStringArray = str(area).split("|")
			var pattern: Dictionary = data["ranges"][parts[0]]
			var cache_key := "%s|a|%s" % [map_key, area]
			if not cache.has(cache_key):
				cache[cache_key] = _any_line(int(pattern["size"]), walls, map_size, int(parts[1])) if BattlePlayLoop.SkillTargetRules.is_line(pattern) else _any_area(pattern["data"], walls, map_size, int(parts[1]))
			_mark(found, "area_any_cell", area, cache[cache_key])
		var entry := {"battle": name, "map": map_key}
		for key in KEYS:
			var changed: Array = []
			for item in found[key]:
				totals[key][1] += 1
				if found[key][item]:
					totals[key][0] += 1
					changed.append(item)
					unique[key]["%s|%s" % [map_key, item]] = true
			changed.sort()
			if not changed.is_empty(): touched[key] += 1
			entry[key] = changed
		report["battles"].append(entry)
	var line := "WRANGE_IMPACT battles=%d maps=%d units_changed=%d/%d" % [totals["battles"], maps.size(), totals["units_changed"], totals["units"]]
	report["totals"] = totals
	report["unique"] = {}
	report["battles_touched"] = touched
	for key in KEYS:
		line += " %s=%d/%d,unique=%d,battles=%d" % [key, totals[key][0], totals[key][1], unique[key].size(), touched[key]]
		report["unique"][key] = unique[key].size()
	var out := FileAccess.open(_res(str(args[1])), FileAccess.WRITE)
	if out == null:
		push_error("audit: cannot write %s" % str(args[1]))
		quit(1)
		return
	out.store_string(JSON.stringify(report, " ") + "\n")
	out.close()
	print(line)
	quit(0)


func _res(path: String) -> String:
	if path.begins_with("res://"): return path
	return ProjectSettings.localize_path(path) if path.is_absolute_path() else "res://" + path


func _mark(found: Dictionary, key: String, item: String, changed: bool) -> void:
	found[key][item] = bool(found[key].get(item, false)) or changed


func _sorted(cells: Array) -> Array:
	var copy := cells.duplicate()
	copy.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return copy


## Positive cells of the record around `anchor` on the map; the anchor only when `keep_anchor`.
func _flat(rows: Array, anchor: Vector2i, map_size: Vector2i, keep_anchor: bool) -> Dictionary:
	var result := {}
	var half := rows.size() / 2
	for y in range(rows.size()):
		for x in range(rows.size()):
			var cell := anchor + Vector2i(x - half, y - half)
			if int(rows[y][x]) > 0 and RangePropagationRules._inside(cell, map_size) and (keep_anchor or cell != anchor): result[cell] = true
	return result


## Weapon／cast range: 0x40f8b0 without the origin (flag 1 except the player's cast mode -1).
func _any_cell(rows: Array, walls: Dictionary, map_size: Vector2i, mode: int) -> bool:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var anchor := Vector2i(x, y)
			if walls.has(anchor): continue
			var new := {}
			for cell in RangePropagationRules.weapon_coverage(rows, anchor, walls, map_size, mode, mode != RangePropagationRules.PLAYER_CAST_MODE):
				if cell != anchor: new[cell] = true
			if new != _flat(rows, anchor, map_size, false): return true
	return false


## Effect area: 0x4100e0 matrix branch with the centre.
func _any_area(rows: Array, walls: Dictionary, map_size: Vector2i, mode: int) -> bool:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var center := Vector2i(x, y)
			if walls.has(center): continue
			var new := {}
			for cell in RangePropagationRules.area_coverage(rows, center, walls, map_size, mode): new[cell] = true
			if new != _flat(rows, center, map_size, true): return true
	return false


## Line area (RANGE 21..23): from each non-wall target, the four directions away from the caster.
func _any_line(size: int, walls: Dictionary, map_size: Vector2i, mode: int) -> bool:
	for y in range(map_size.y):
		for x in range(map_size.x):
			var target := Vector2i(x, y)
			if walls.has(target): continue
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var old := {}
				for index in range(size):
					var cell: Vector2i = target + step * index
					if not RangePropagationRules._inside(cell, map_size): break
					old[cell] = true
				var new := {}
				for cell in RangePropagationRules.line_coverage(size, target - step, target, walls, map_size, mode): new[cell] = true
				if old != new: return true
	return false

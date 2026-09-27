extends "res://tests/support/TestSuite.gd"

## Terrain edits of script-inserted stand objects (scenario `terrain_overrides`, applied by
## WrdTerrainTiles.load_tiles). STORY053 inserts obj_Story_Block (mapobjBlock) at (640,672)
## after 緹娜 slides down the rope: the original ORs 0xff000000 into cell (20,21)
## (defProcStandObject 0x43ccf0 case 10), sealing the rope shaft so she cannot climb back
## to the second-floor balcony. Ablation: the same loop without the overrides lets 緹娜
## walk back up the shaft.
## WINFAIL028 events 3..6 and WINFAIL080 event 3 open 0x4000 walls with
## actInsertStoryObject obj_Story_Level_ClearWall (mapobjClearWall, case 15) when they
## fire: loop terrain edits like the level-39 collapse. 28's events check the door guards
## STORY028 re-coded 5000..5003 (actChangePrevInsertObjectID); killing guard050_6 (id 5000)
## opens (4,48). Ablations: without the ClearWall join, or without the 5000 binding, the
## door stays shut. 80's event 3 checks Enemy068, a static enemy object the remake draws
## without a unit, so the class counts as fallen and the wall opens at the first hook run.
## WINFAIL039 event 5 (round 7, the third quake) deletes the units on ten pixel rows and
## inserts obj_Story_Block over them with actInsertStoryObjectXRange: mid-battle, so the
## edit is loop state (TerrainEditRules, `terrain_edits`), read through
## TerrainEditRules.tiles, saved with the state. Ablation: the compiled program without the
## obj_Story_Block → mapobjBlock join leaves the collapsed ground walkable.

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const WrdTerrainTiles = preload("res://game/sim/WrdTerrainTiles.gd")
const ScriptWalkPath = preload("res://game/sim/ScriptWalkPath.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")


func _init() -> void:
	tag = "STORY_OBJECT_TERRAIN_TESTS"


func run() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_053.json")
	var overrides: Array = scenario.get("terrain_overrides", [])
	check(overrides.size() == 1 and Vector2i(int(overrides[0]["cell"][0]), int(overrides[0]["cell"][1])) == Vector2i(20, 21) and int(overrides[0]["height"]) == 255, "battle_053 carries the obj_Story_Block cell edit: %s" % str(overrides))
	var loop: Dictionary = BattlePlayLoop.create([], "", scenario)
	check(bool(loop.get("scenario_ok", false)), "battle_053 loads (%s)" % str(loop.get("scenario_error", "")))
	check(bool(loop["tiles"][Vector2i(20, 21)]["blocks_movement"]), "cell (20,21) is a cliff after the block insert")
	var tina: Dictionary = BattlePlayLoop.unit(loop, "tina")
	check(tina.get("coord") == Vector2i(20, 23), "緹娜 starts at the foot of the rope (20,23): %s" % str(tina.get("coord")))
	var cells: Array = BattlePlayLoop.movement_cells(loop, "tina")
	check(not cells.has(Vector2i(20, 21)) and not cells.has(Vector2i(20, 20)), "緹娜 cannot step back into the rope shaft: %s" % str(cells))
	var path := BattleScenario.resource_path(scenario, "terrain")
	var sealed := WrdTerrainTiles.load_tiles(path, overrides)
	var open := WrdTerrainTiles.load_tiles(path)
	var start := Vector2(20 * 32 + 16, 23 * 32 + 16)
	var balcony := Vector2(20 * 32 + 16, 14 * 32 + 16)
	check(ScriptWalkPath.route(sealed["tiles"], sealed["map_size"], start, balcony, Vector2(32, 32))["status"] == "nearest_reachable", "no ground route leads back to the balcony")
	check(ScriptWalkPath.route(open["tiles"], open["map_size"], start, balcony, Vector2(32, 32))["status"] == "grid_path", "ablation: without the edit the balcony is reachable again")
	check(not WrdTerrainTiles.load_tiles(path, [{"cell": [999, 0], "height": 255}])["ok"], "an override outside the map is refused")
	_level39_collapse()
	_door_walls()
	run_script_walk_path()


func _level39_collapse() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_039.json")
	check(scenario.get("terrain_overrides", []).is_empty(), "battle_039 has no opening terrain override (its block rows are a WINFAIL event)")
	var loop: Dictionary = BattlePlayLoop.create([], "", scenario)
	check(bool(loop.get("scenario_ok", false)), "battle_039 loads (%s)" % str(loop.get("scenario_error", "")))
	check(loop.get("terrain_edits") == [], "no terrain edit before the collapse")
	check(loop["winfail_script_rules"].get("story_object_terrain", {}) == {"obj_Story_Block": {"height": 255}}, "the compiled program joins obj_Story_Block to its mapobjBlock edit: %s" % str(loop["winfail_script_rules"].get("story_object_terrain")))
	var hole := {}
	for action in WinfailScenarioRules.WinfailCompiler.status_by_key(loop["winfail_script_rules"], "event_5").get("actions", []):
		if action["name"] == "actInsertStoryObjectXRange":
			for offset in range(int(action["args"][3])):
				hole[Vector2i(int(action["args"][1]) / 32 + offset, int(action["args"][2]) / 32)] = true
	check(hole.size() == 89, "WINFAIL039 event 5 blocks 89 cells on ten rows: %d" % hole.size())
	var walkable_before := 0
	for cell in hole:
		walkable_before += int(not bool(loop["tiles"][cell]["blocks_movement"]))
	check(walkable_before == hole.size(), "every collapse cell is ground before the quake: %d" % walkable_before)
	var hero := str(loop["player_unit_id"])
	var edge := _hole_edge(loop, hole)
	check(edge != Vector2i(-1, -1), "a free ground cell borders the collapse")
	loop["units"] = loop["units"].map(func(unit): return _moved(unit, hero, edge))
	check(_reaches(BattlePlayLoop.movement_cells(loop, hero), hole), "before the quake the hero can step into the collapse area")
	var base_tiles: Dictionary = loop["tiles"]
	var armed := BattlePlayLoop.copy(loop)
	armed["event_statuses"] = [5]
	armed["turn"] = 7
	var collapsed: Dictionary = WinfailScenarioRules.run_event_hooks(armed)
	check(collapsed["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_5"), "event 5 fires at round 7")
	check((collapsed["terrain_edits"] as Array).size() == 89 and (collapsed["terrain_edits"] as Array).all(func(edit): return hole.has(edit["cell"]) and edit["height"] == 255), "the collapse records one 0xff edit per block cell")
	var tiles: Dictionary = TerrainEditRules.tiles(collapsed)
	check(hole.keys().all(func(cell): return bool(tiles[cell]["blocks_movement"]) and int(tiles[cell]["elevation"]) == 255), "every collapse cell is a cliff after the quake")
	check(is_same(collapsed["tiles"], base_tiles) and hole.keys().all(func(cell): return not bool(base_tiles[cell]["blocks_movement"])), "the shared WRD block is not written")
	check(not _reaches(BattlePlayLoop.movement_cells(collapsed, hero), hole), "after the quake the hero cannot step into the collapse")
	var fresh: Dictionary = BattlePlayLoop.create([], "", scenario)
	var restored: Dictionary = BattleCheckpoint.restored(BattleCheckpoint.state(collapsed), fresh)
	check(TerrainEditRules.state_error(restored) == "" and hole.keys().all(func(cell): return bool(TerrainEditRules.tiles(restored)[cell]["blocks_movement"])), "a save after the quake restores the collapse over a fresh battle's map")
	check(TerrainEditRules.state_error({"terrain_edits": [{"cell": Vector2i(99, 0), "height": 255, "source": ""}], "map_size": loop["map_size"]}) != "", "an edit outside the map is refused on load")
	var ablated := BattlePlayLoop.copy(armed)
	own(ablated, "winfail_script_rules")["story_object_terrain"] = {}
	var open: Dictionary = WinfailScenarioRules.run_event_hooks(ablated)
	check((open["terrain_edits"] as Array).is_empty() and _reaches(BattlePlayLoop.movement_cells(open, hero), hole), "ablation: without the mapobjBlock join the collapse stays walkable")


func _door_walls() -> void:
	var doors := {"028": {"event_3": Vector2i(4, 48), "event_4": Vector2i(26, 34), "event_5": Vector2i(12, 31), "event_6": Vector2i(14, 8)},
		"080": {"event_3": [Vector2i(21, 11), Vector2i(22, 12), Vector2i(23, 13), Vector2i(24, 13)]}}
	for level in doors:
		var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_%s.json" % level)
		check(scenario.get("terrain_overrides", []).is_empty(), "battle_%s opens no wall at load" % level)
		var loop: Dictionary = BattlePlayLoop.create([], "", scenario)
		check(bool(loop.get("scenario_ok", false)) and loop["winfail_script_rules"].get("story_object_terrain", {}) == {"obj_Story_Level_ClearWall": {"clear_flags": 0x4000}}, "battle_%s joins obj_Story_Level_ClearWall to its 0x4000 clear" % level)
		for key in doors[level]:
			var cells: Array = doors[level][key] if doors[level][key] is Array else [doors[level][key]]
			check(cells.all(func(cell): return int(loop["tiles"][cell]["movement_flags"]) & 0x4000), "battle_%s %s: the wall %s is shut before its event" % [level, key, str(cells)])
	var loop: Dictionary = BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_028.json"))
	var quiet: Dictionary = WinfailScenarioRules.run_event_hooks(loop)
	check(quiet["winfail_runtime"]["fired"].is_empty() and (quiet.get("terrain_edits", []) as Array).is_empty(), "battle_028: no door opens while its guards stand")
	var killed := BattlePlayLoop.copy(loop)
	killed["units"] = killed["units"].map(func(unit): return _defeated(unit, "guard050_6"))
	var opened: Dictionary = WinfailScenarioRules.run_event_hooks(killed)
	var tiles: Dictionary = TerrainEditRules.tiles(opened)
	check(opened["winfail_runtime"]["fired"].map(func(entry): return entry["key"]) == ["event_3"], "battle_028: killing guard 5000 fires event 3 only: %s" % str(opened["winfail_runtime"]["fired"]))
	check(not (int(tiles[Vector2i(4, 48)]["movement_flags"]) & 0x4000) and int(tiles[Vector2i(26, 34)]["movement_flags"]) & 0x4000, "battle_028: event 3 opens door (4,48), the other doors stay shut")
	check(int(opened["tiles"][Vector2i(4, 48)]["movement_flags"]) & 0x4000, "battle_028: the shared WRD block is not written")
	var restored: Dictionary = BattleCheckpoint.restored(BattleCheckpoint.state(opened), BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_028.json")))
	check(not (int(TerrainEditRules.tiles(restored)[Vector2i(4, 48)]["movement_flags"]) & 0x4000), "battle_028: a save after the door opened restores it open")
	var no_join := BattlePlayLoop.copy(killed)
	own(no_join, "winfail_script_rules")["story_object_terrain"] = {}
	check((WinfailScenarioRules.run_event_hooks(no_join).get("terrain_edits", []) as Array).is_empty(), "ablation: without the ClearWall join event 3 opens nothing")
	var no_binding := BattlePlayLoop.copy(killed)
	own(no_binding, "winfail_runtime")["actor_bindings"] = (killed["winfail_runtime"]["actor_bindings"] as Dictionary).duplicate()
	no_binding["winfail_runtime"]["actor_bindings"].erase("5000/1")
	check(WinfailScenarioRules.run_event_hooks(no_binding)["winfail_runtime"]["fired"].is_empty(), "ablation: without the 5000 binding the dead guard opens no door")
	var level80: Dictionary = WinfailScenarioRules.run_event_hooks(BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_080.json")))
	var tiles80: Dictionary = TerrainEditRules.tiles(level80)
	# R6-L10: the 怨念體 Enemy068 is PlayLoop unit actor068_1, so event 3 waits for its death.
	check(not level80["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_3") and doors["080"]["event_3"].all(func(cell): return int(tiles80[cell]["movement_flags"]) & 0x4000), "battle_080: event 3 keeps the wall shut while the 怨念體 stands")
	var fallen80 := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_080.json"))
	fallen80["units"] = fallen80["units"].map(func(unit): return _defeated(unit, "actor068_1"))
	var opened80: Dictionary = WinfailScenarioRules.run_event_hooks(fallen80)
	var open_tiles80: Dictionary = TerrainEditRules.tiles(opened80)
	check(opened80["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_3") and doors["080"]["event_3"].all(func(cell): return not (int(open_tiles80[cell]["movement_flags"]) & 0x4000)), "battle_080: the 怨念體's death fires event 3 and opens the wall")


func _defeated(unit: Dictionary, unit_id: String) -> Dictionary:
	if unit["id"] == unit_id:
		unit["hp"] = 0
		unit["defeated"] = true
	return unit


func _hole_edge(loop: Dictionary, hole: Dictionary) -> Vector2i:
	var taken := {}
	for unit in loop["units"]:
		taken[unit["coord"]] = true
	for cell in hole:
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + delta
			if not hole.has(next) and not taken.has(next) and loop["tiles"].has(next) and not bool(loop["tiles"][next]["blocks_movement"]) and int(loop["tiles"][next]["movement_flags"]) == 0:
				return next
	return Vector2i(-1, -1)


func _moved(unit: Dictionary, unit_id: String, coord: Vector2i) -> Dictionary:
	if unit["id"] == unit_id:
		unit["coord"] = coord
	return unit


func _reaches(cells: Array, hole: Dictionary) -> bool:
	return cells.any(func(cell): return hole.has(cell))


# ---- run_story_object_terrain_tests.gd ----
## Scripted walk routes (game/sim/ScriptWalkPath.gd): the original steps
## a script walker cell by cell along a four-neighbour path over the terrain (0x453b90 →
## 0x4111d0 path buffer), so no scripted entrance, retreat or story walk may glide through
## a wall. Unit cases pin the terrain tests; the census replays every walk token of every
## registered scenario (opening timeline and every winfail status chain) from statically
## known positions — EVEF／binding pixels, insert pixels, the previous walk's end — and
## checks each route only enters passable cells in four-neighbour steps. It also counts the
## walks whose old straight line crossed an impassable cell (the ablation: those are the
## walks the route changes) and lists the walled-off targets that end on the nearest cell.

const CELL := Vector2(32, 32)
const ABSOLUTE_WALKS := ["actor_walk", "actor_walk_wait", "actor_walk_and_delete", "actor_walk_and_delete_wait"]
const RELATIVE_WALKS := ["actor_walk_disp", "actor_walk_disp_wait"]
const INSERT_WALKS := ["inserted_object_walk_disp", "inserted_object_walk_disp_wait"]

var _census := {"scenarios": 0, "walks": 0, "routed": 0, "straight_crossed": 0, "nearest_reachable": 0, "unresolved_start": 0}
var _walled_off: Array[String] = []
var _flying_by_actor := {}


func run_script_walk_path() -> void:
	_unit_cases()
	_whole_game_census()


func _open(width: int, height: int) -> Dictionary:
	var tiles := {}
	for y in range(height):
		for x in range(width):
			tiles[Vector2i(x, y)] = {"blocks_movement": false, "movement_flags": 0, "elevation": 0}
	return tiles


func _unit_cases() -> void:
	var tiles := _open(7, 5)
	for y in range(0, 4):
		tiles[Vector2i(3, y)]["blocks_movement"] = true
	var route := ScriptWalkPath.route(tiles, Vector2i(7, 5), Vector2(16, 16), Vector2(6 * 32 + 16, 16), CELL)
	check(route["status"] == "grid_path", "a wall with a gap is walked around: %s" % route["status"])
	# 0x40ed50 in script mode (0x4c1a74) skips the map-bounds test, so the shorter detour
	# runs through the outside row above the wall instead of the far gap.
	check(not (route["cells"] as Array).has(Vector2i(3, 0)) and (route["cells"] as Array).has(Vector2i(3, -1)), "the detour goes round the wall through the outside row, not through the wall: %s" % str(route["cells"]))
	check((route["points"] as Array).back() == Vector2(6 * 32 + 16, 16), "the walk still ends on the script pixel")
	# Outside cells are open in script mode, so the sealed target is the centre of a 3×3
	# map ringed by its four in-map neighbours.
	var ring: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 2)]
	var hard := _open(3, 3)
	for cell in ring:
		hard[cell]["movement_flags"] = ScriptWalkPath.HARD_BLOCK
	var sealed := ScriptWalkPath.route(hard, Vector2i(3, 3), Vector2(16, 16), Vector2(48, 48), CELL, true)
	check(sealed["status"] == "nearest_reachable" and not (sealed["cells"] as Array).has(Vector2i(1, 1)) and not ring.has((sealed["cells"] as Array).back()), "the WRD 0x4000 block stops even a flyer; the walker ends on the nearest reachable cell: %s" % str(sealed))
	var cliff := _open(3, 3)
	for cell in ring:
		cliff[cell]["elevation"] = 3
	check(ScriptWalkPath.route(cliff, Vector2i(3, 3), Vector2(16, 16), Vector2(48, 48), CELL)["status"] == "nearest_reachable", "a height gap above two stops a ground walker")
	check(ScriptWalkPath.route(cliff, Vector2i(3, 3), Vector2(16, 16), Vector2(48, 48), CELL, true)["status"] == "grid_path", "a flyer ignores the height gap")
	var exit := ScriptWalkPath.route(_open(3, 3), Vector2i(3, 3), Vector2(48, 48), Vector2(48, 3 * 32 + 16), CELL)
	check(exit["status"] == "grid_path" and (exit["cells"] as Array).back() == Vector2i(1, 3), "a retreat may leave the map through the edge (outside cells read as open): %s" % str(exit["cells"]))


func _whole_game_census() -> void:
	var directory := DirAccess.open("res://content/battles")
	for file in directory.get_files():
		if not file.ends_with(".json") or file == "campaign.json":
			continue
		var scenario: Dictionary = BattleScenario.load_file("res://content/battles/" + file)
		if not scenario.has("opening") or not bool(scenario.get("ok", true)):
			continue
		var terrain := WrdTerrainTiles.load_tiles(BattleScenario.resource_path(scenario, "terrain"), scenario.get("terrain_overrides", []))
		if not bool(terrain.get("ok", false)):
			continue
		_census["scenarios"] += 1
		var timelines: Array = []
		var opening_path := BattleScenario.resource_path(scenario, "opening_timeline")
		if opening_path != "" and FileAccess.file_exists(opening_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(opening_path))
			if parsed is Dictionary:
				timelines.append({"key": "opening", "events": parsed.get("events", [])})
		var status_timelines: Dictionary = scenario.get("scenario_rules", {}).get("status_timelines", {})
		for key in status_timelines:
			timelines.append({"key": key, "events": status_timelines[key].get("events", [])})
		for timeline in timelines:
			_replay(file, scenario, terrain, timeline["key"], timeline["events"])
	print("SCRIPT_WALK_ROUTES scenarios=%d walks=%d routed=%d straight_crossed=%d nearest_reachable=%d unresolved_start=%d" % [_census["scenarios"], _census["walks"], _census["routed"], _census["straight_crossed"], _census["nearest_reachable"], _census["unresolved_start"]])
	for line in _walled_off:
		print("SCRIPT_WALK_WALLED_OFF " + line)
	check(_census["routed"] > 500, "the census reaches the scripted walks of the whole game: %s" % str(_census))
	check(_census["straight_crossed"] > 0, "ablation: some old straight-line walks crossed impassable cells (the route changes them): %s" % str(_census))


func _start_positions(scenario: Dictionary) -> Dictionary:
	var positions := {}
	for binding in (scenario.get("opening", {}).get("actor_bindings", {}) as Dictionary).values():
		var xy: Array = binding.get("placement_xy", [])
		if xy.size() == 2 and str(binding.get("unit_id", "")) != "":
			positions[str(binding["unit_id"])] = Vector2(float(xy[0]), float(xy[1])) + CELL * 0.5
	for unit in scenario.get("playable_units", []):
		var coord: Array = unit.get("coord", [])
		if coord.size() == 2 and not positions.has(str(unit.get("id", ""))):
			positions[str(unit["id"])] = Vector2(float(coord[0]), float(coord[1])) * CELL + CELL * 0.5
	return positions


func _replay(file: String, scenario: Dictionary, terrain: Dictionary, key: String, events: Array) -> void:
	var bindings: Dictionary = scenario.get("opening", {}).get("actor_bindings", {})
	var positions := _start_positions(scenario)
	var actor_ids := {}
	for binding in bindings.values():
		actor_ids[str(binding.get("unit_id", ""))] = str(binding.get("actor_id", ""))
	for unit in scenario.get("playable_units", []):
		actor_ids[str(unit.get("id", ""))] = str(unit.get("actor_id", ""))
	var inserts := {}
	var pending := ""
	for event in events:
		if not event is Dictionary:
			continue
		var kind := str(event.get("kind", ""))
		var args: Array = event.get("args", [])
		if kind == "object_insert" and args.size() >= 3:
			var symbol := str(args[0])
			inserts[symbol] = int(inserts.get(symbol, 0)) + 1
			pending = str(bindings.get("%s/insert%d" % [symbol, inserts[symbol]], {}).get("unit_id", ""))
			if pending != "":
				positions[pending] = Vector2(float(str(args[1])), float(str(args[2]))) + CELL * 0.5
			continue
		var unit_id := ""
		var target := Vector2.ZERO
		if kind in INSERT_WALKS and args.size() >= 2:
			unit_id = pending
			target = Vector2(float(str(args[0])), float(str(args[1]))) + CELL * 0.5
		elif (kind in ABSOLUTE_WALKS or kind in RELATIVE_WALKS) and args.size() >= 4:
			unit_id = pending if str(args[0]) == "-1" else str(bindings.get("%s/%s" % [str(args[0]), str(args[1])], {}).get("unit_id", ""))
			if kind in ABSOLUTE_WALKS:
				target = Vector2(float(str(args[2])), float(str(args[3]))) + CELL * 0.5
			elif positions.has(unit_id):
				target = positions[unit_id] + Vector2(float(str(args[2])), float(str(args[3])))
		else:
			continue
		_census["walks"] += 1
		if unit_id == "" or not positions.has(unit_id):
			_census["unresolved_start"] += 1
			continue
		var start: Vector2 = positions[unit_id]
		var flying := _flies(str(actor_ids.get(unit_id, "")))
		var route := ScriptWalkPath.route(terrain["tiles"], terrain["map_size"], start, target, CELL, flying)
		_census["routed"] += 1
		var cells: Array = route["cells"]
		for index in range(1, cells.size()):
			var cell: Vector2i = cells[index]
			var step: Vector2i = cell - cells[index - 1]
			check(absi(step.x) + absi(step.y) == 1, "%s %s %s: the route moves one cell at a time (%s)" % [file, key, str(event.get("id", "")), str(cells)])
			check(ScriptWalkPath.can_step(terrain["tiles"], terrain["map_size"], cells[index - 1], cell, flying), "%s %s %s: the route only enters passable cells (%s)" % [file, key, str(event.get("id", "")), str(cell)])
		if _straight_line_crosses(terrain, start, target, flying):
			_census["straight_crossed"] += 1
		if route["status"] == "nearest_reachable":
			_census["nearest_reachable"] += 1
			_walled_off.append("%s %s %s %s -> %s ends %s" % [file, key, str(event.get("id", "")), unit_id, str(ScriptWalkPath.cell_of(target, CELL)), str(cells.back())])
		positions[unit_id] = (route["points"] as Array).back() if not (route["points"] as Array).is_empty() else start


## The old presentation's straight segment, sampled every 4 px: true when it enters an
## in-map cell a ground walker cannot stand on (other than its own start and end cells).
func _straight_line_crosses(terrain: Dictionary, start: Vector2, target: Vector2, flying: bool) -> bool:
	var tiles: Dictionary = terrain["tiles"]
	var start_cell := ScriptWalkPath.cell_of(start, CELL)
	var end_cell := ScriptWalkPath.cell_of(target, CELL)
	var steps := maxi(1, ceili(start.distance_to(target) / 4.0))
	for index in range(steps + 1):
		var cell := ScriptWalkPath.cell_of(start.lerp(target, float(index) / float(steps)), CELL)
		if cell == start_cell or cell == end_cell or not tiles.has(cell):
			continue
		var tile: Dictionary = tiles[cell]
		if (bool(tile.get("blocks_movement", false)) and not flying) or int(tile.get("movement_flags", 0)) & ScriptWalkPath.HARD_BLOCK:
			return true
	return false


## The source traversal trait of an actor template (content/generated/hsl/actors/NNN.json).
func _flies(actor_id: String) -> bool:
	if actor_id == "":
		return false
	# The traversal PlayLoop installs (ActorTraversalRules.source reads the skill book's
	# actors; the per-actor template files carry no traversal for players such as 雷特 006).
	if _flying_by_actor.is_empty():
		var book: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/skills/initial_book.json"))
		var actors: Dictionary = book.get("actors", {}) if book is Dictionary else {}
		for code in actors:
			_flying_by_actor[str(code)] = bool((actors[code] as Dictionary).get("traversal", {}).get("flying", false))
	return bool(_flying_by_actor.get(actor_id, false))

extends "res://tests/support/TestSuite.gd"

## Scripted walk routes (game/battle/runtime/opening/ScriptWalkPath.gd): the original steps
## a script walker cell by cell along a four-neighbour path over the terrain (0x453b90 →
## 0x4111d0 path buffer), so no scripted entrance, retreat or story walk may glide through
## a wall. Unit cases pin the terrain tests; the census replays every walk token of every
## registered scenario (opening timeline and every winfail status chain) from statically
## known positions — EVEF／binding pixels, insert pixels, the previous walk's end — and
## checks each route only enters passable cells in four-neighbour steps. It also counts the
## walks whose old straight line crossed an impassable cell (the ablation: those are the
## walks the route changes) and lists the walled-off targets that end on the nearest cell.

const ScriptWalkPath = preload("res://game/battle/runtime/opening/ScriptWalkPath.gd")
const WrdTerrainTiles = preload("res://game/battle/runtime/WrdTerrainTiles.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const CELL := Vector2(32, 32)
const ABSOLUTE_WALKS := ["actor_walk", "actor_walk_wait", "actor_walk_and_delete", "actor_walk_and_delete_wait"]
const RELATIVE_WALKS := ["actor_walk_disp", "actor_walk_disp_wait"]
const INSERT_WALKS := ["inserted_object_walk_disp", "inserted_object_walk_disp_wait"]

var _census := {"scenarios": 0, "walks": 0, "routed": 0, "straight_crossed": 0, "nearest_reachable": 0, "unresolved_start": 0}
var _walled_off: Array[String] = []
var _flying_by_actor := {}


func _init() -> void:
	tag = "SCRIPT_WALK_PATH_TESTS"


func run() -> void:
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
	check(not (route["cells"] as Array).has(Vector2i(3, 0)) and (route["cells"] as Array).has(Vector2i(3, 4)), "the detour uses the gap, not the wall: %s" % str(route["cells"]))
	check((route["points"] as Array).back() == Vector2(6 * 32 + 16, 16), "the walk still ends on the script pixel")
	var hard := _open(3, 1)
	hard[Vector2i(1, 0)]["movement_flags"] = ScriptWalkPath.HARD_BLOCK
	var sealed := ScriptWalkPath.route(hard, Vector2i(3, 1), Vector2(16, 16), Vector2(80, 16), CELL, true)
	check(sealed["status"] == "nearest_reachable" and (sealed["cells"] as Array).back() == Vector2i(0, 0), "the WRD 0x4000 block stops even a flyer; the walker ends on the nearest reachable cell: %s" % str(sealed))
	var cliff := _open(3, 1)
	cliff[Vector2i(1, 0)]["elevation"] = 3
	check(ScriptWalkPath.route(cliff, Vector2i(3, 1), Vector2(16, 16), Vector2(80, 16), CELL)["status"] == "nearest_reachable", "a height gap above two stops a ground walker")
	check(ScriptWalkPath.route(cliff, Vector2i(3, 1), Vector2(16, 16), Vector2(80, 16), CELL, true)["status"] == "grid_path", "a flyer ignores the height gap")
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
	if not _flying_by_actor.has(actor_id):
		var path := "res://content/generated/hsl/actors/%s.json" % actor_id
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var traversal: Dictionary = {}
		if parsed is Dictionary:
			for part in ["actor", "source"]:
				if parsed.get(part) is Dictionary and parsed[part].get("traversal") is Dictionary:
					traversal = parsed[part]["traversal"]
					break
		_flying_by_actor[actor_id] = bool(traversal.get("flying", false))
	return _flying_by_actor[actor_id]

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

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const WrdTerrainTiles = preload("res://game/battle/runtime/WrdTerrainTiles.gd")
const ScriptWalkPath = preload("res://game/battle/runtime/opening/ScriptWalkPath.gd")
const Winfail = preload("res://game/sim/WinfailScenarioRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")


func _init() -> void:
	tag = "STORY_OBJECT_TERRAIN_TESTS"


func run() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_053.json")
	var overrides: Array = scenario.get("terrain_overrides", [])
	check(overrides.size() == 1 and Vector2i(int(overrides[0]["cell"][0]), int(overrides[0]["cell"][1])) == Vector2i(20, 21) and int(overrides[0]["height"]) == 255, "battle_053 carries the obj_Story_Block cell edit: %s" % str(overrides))
	var loop: Dictionary = Loop.create([], "", scenario)
	check(bool(loop.get("scenario_ok", false)), "battle_053 loads (%s)" % str(loop.get("scenario_error", "")))
	check(bool(loop["tiles"][Vector2i(20, 21)]["blocks_movement"]), "cell (20,21) is a cliff after the block insert")
	var tina: Dictionary = Loop.unit(loop, "tina")
	check(tina.get("coord") == Vector2i(20, 23), "緹娜 starts at the foot of the rope (20,23): %s" % str(tina.get("coord")))
	var cells: Array = Loop.movement_cells(loop, "tina")
	check(not cells.has(Vector2i(20, 21)) and not cells.has(Vector2i(20, 20)), "緹娜 cannot step back into the rope shaft: %s" % str(cells))
	var path := BattleScenario.resource_path(scenario, "terrain")
	var sealed := WrdTerrainTiles.load_tiles(path, overrides)
	var open := WrdTerrainTiles.load_tiles(path)
	var start := Vector2(20 * 32 + 16, 23 * 32 + 16)
	var balcony := Vector2(20 * 32 + 16, 14 * 32 + 16)
	check(ScriptWalkPath.route(sealed["tiles"], sealed["map_size"], start, balcony, Vector2(32, 32))["status"] == "nearest_reachable", "no ground route leads back to the balcony")
	check(ScriptWalkPath.route(open["tiles"], open["map_size"], start, balcony, Vector2(32, 32))["status"] == "grid_path", "ablation: without the edit the balcony is reachable again")
	check(int(sealed["blocking_count"]) == int(open["blocking_count"]) + 1, "the edit adds one blocked cell to the terrain count")
	check(not WrdTerrainTiles.load_tiles(path, [{"cell": [999, 0], "height": 255}])["ok"], "an override outside the map is refused")
	_level39_collapse()
	_door_walls()


func _level39_collapse() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_039.json")
	check(scenario.get("terrain_overrides", []).is_empty(), "battle_039 has no opening terrain override (its block rows are a WINFAIL event)")
	var loop: Dictionary = Loop.create([], "", scenario)
	check(bool(loop.get("scenario_ok", false)), "battle_039 loads (%s)" % str(loop.get("scenario_error", "")))
	check(loop.get("terrain_edits") == [], "no terrain edit before the collapse")
	check(loop["winfail_script_rules"].get("story_object_terrain", {}) == {"obj_Story_Block": {"height": 255}}, "the compiled program joins obj_Story_Block to its mapobjBlock edit: %s" % str(loop["winfail_script_rules"].get("story_object_terrain")))
	var hole := {}
	for action in Winfail.WinfailCompiler.status_by_key(loop["winfail_script_rules"], "event_5").get("actions", []):
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
	check(_reaches(Loop.movement_cells(loop, hero), hole), "before the quake the hero can step into the collapse area")
	var base_tiles: Dictionary = loop["tiles"]
	var armed := Loop.copy(loop)
	armed["event_statuses"] = [5]
	armed["turn"] = 7
	var collapsed: Dictionary = Winfail.run_event_hooks(armed)
	check(collapsed["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_5"), "event 5 fires at round 7")
	check((collapsed["terrain_edits"] as Array).size() == 89 and (collapsed["terrain_edits"] as Array).all(func(edit): return hole.has(edit["cell"]) and edit["height"] == 255), "the collapse records one 0xff edit per block cell")
	var tiles: Dictionary = TerrainEdits.tiles(collapsed)
	check(hole.keys().all(func(cell): return bool(tiles[cell]["blocks_movement"]) and int(tiles[cell]["elevation"]) == 255), "every collapse cell is a cliff after the quake")
	check(is_same(collapsed["tiles"], base_tiles) and hole.keys().all(func(cell): return not bool(base_tiles[cell]["blocks_movement"])), "the shared WRD block is not written")
	check(is_same(TerrainEdits.tiles(collapsed), tiles), "the edited map is memoised (tile tables stay cached)")
	check(not _reaches(Loop.movement_cells(collapsed, hero), hole), "after the quake the hero cannot step into the collapse")
	var fresh: Dictionary = Loop.create([], "", scenario)
	var restored: Dictionary = BattleCheckpoint.restored(BattleCheckpoint.state(collapsed), fresh)
	check(TerrainEdits.state_error(restored) == "" and hole.keys().all(func(cell): return bool(TerrainEdits.tiles(restored)[cell]["blocks_movement"])), "a save after the quake restores the collapse over a fresh battle's map")
	check(TerrainEdits.state_error({"terrain_edits": [{"cell": Vector2i(99, 0), "height": 255, "source": ""}], "map_size": loop["map_size"]}) != "", "an edit outside the map is refused on load")
	var ablated := Loop.copy(armed)
	own(ablated, "winfail_script_rules")["story_object_terrain"] = {}
	var open: Dictionary = Winfail.run_event_hooks(ablated)
	check((open["terrain_edits"] as Array).is_empty() and _reaches(Loop.movement_cells(open, hero), hole), "ablation: without the mapobjBlock join the collapse stays walkable")


func _door_walls() -> void:
	var doors := {"028": {"event_3": Vector2i(4, 48), "event_4": Vector2i(26, 34), "event_5": Vector2i(12, 31), "event_6": Vector2i(14, 8)},
		"080": {"event_3": [Vector2i(21, 11), Vector2i(22, 12), Vector2i(23, 13), Vector2i(24, 13)]}}
	for level in doors:
		var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_%s.json" % level)
		check(scenario.get("terrain_overrides", []).is_empty(), "battle_%s opens no wall at load" % level)
		var loop: Dictionary = Loop.create([], "", scenario)
		check(bool(loop.get("scenario_ok", false)) and loop["winfail_script_rules"].get("story_object_terrain", {}) == {"obj_Story_Level_ClearWall": {"clear_flags": 0x4000}}, "battle_%s joins obj_Story_Level_ClearWall to its 0x4000 clear" % level)
		for key in doors[level]:
			var cells: Array = doors[level][key] if doors[level][key] is Array else [doors[level][key]]
			check(cells.all(func(cell): return int(loop["tiles"][cell]["movement_flags"]) & 0x4000), "battle_%s %s: the wall %s is shut before its event" % [level, key, str(cells)])
	var loop: Dictionary = Loop.create([], "", BattleScenario.load_file("res://content/battles/battle_028.json"))
	var quiet: Dictionary = Winfail.run_event_hooks(loop)
	check(quiet["winfail_runtime"]["fired"].is_empty() and (quiet.get("terrain_edits", []) as Array).is_empty(), "battle_028: no door opens while its guards stand")
	var killed := Loop.copy(loop)
	killed["units"] = killed["units"].map(func(unit): return _defeated(unit, "guard050_6"))
	var opened: Dictionary = Winfail.run_event_hooks(killed)
	var tiles: Dictionary = TerrainEdits.tiles(opened)
	check(opened["winfail_runtime"]["fired"].map(func(entry): return entry["key"]) == ["event_3"], "battle_028: killing guard 5000 fires event 3 only: %s" % str(opened["winfail_runtime"]["fired"]))
	check(not (int(tiles[Vector2i(4, 48)]["movement_flags"]) & 0x4000) and int(tiles[Vector2i(26, 34)]["movement_flags"]) & 0x4000, "battle_028: event 3 opens door (4,48), the other doors stay shut")
	check(int(opened["tiles"][Vector2i(4, 48)]["movement_flags"]) & 0x4000, "battle_028: the shared WRD block is not written")
	var restored: Dictionary = BattleCheckpoint.restored(BattleCheckpoint.state(opened), Loop.create([], "", BattleScenario.load_file("res://content/battles/battle_028.json")))
	check(not (int(TerrainEdits.tiles(restored)[Vector2i(4, 48)]["movement_flags"]) & 0x4000), "battle_028: a save after the door opened restores it open")
	var no_join := Loop.copy(killed)
	own(no_join, "winfail_script_rules")["story_object_terrain"] = {}
	check((Winfail.run_event_hooks(no_join).get("terrain_edits", []) as Array).is_empty(), "ablation: without the ClearWall join event 3 opens nothing")
	var no_binding := Loop.copy(killed)
	own(no_binding, "winfail_runtime")["actor_bindings"] = (killed["winfail_runtime"]["actor_bindings"] as Dictionary).duplicate()
	no_binding["winfail_runtime"]["actor_bindings"].erase("5000/1")
	check(Winfail.run_event_hooks(no_binding)["winfail_runtime"]["fired"].is_empty(), "ablation: without the 5000 binding the dead guard opens no door")
	var level80: Dictionary = Winfail.run_event_hooks(Loop.create([], "", BattleScenario.load_file("res://content/battles/battle_080.json")))
	var tiles80: Dictionary = TerrainEdits.tiles(level80)
	# R6-L10: the 怨念體 Enemy068 is PlayLoop unit actor068_1, so event 3 waits for its death.
	check(not level80["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_3") and doors["080"]["event_3"].all(func(cell): return int(tiles80[cell]["movement_flags"]) & 0x4000), "battle_080: event 3 keeps the wall shut while the 怨念體 stands")
	var fallen80 := Loop.create([], "", BattleScenario.load_file("res://content/battles/battle_080.json"))
	fallen80["units"] = fallen80["units"].map(func(unit): return _defeated(unit, "actor068_1"))
	var opened80: Dictionary = Winfail.run_event_hooks(fallen80)
	var open_tiles80: Dictionary = TerrainEdits.tiles(opened80)
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

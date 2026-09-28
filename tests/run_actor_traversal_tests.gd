extends SceneTree
const GameOptions = preload("res://game/settings/GameOptions.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")
const HEAL := "magic:magicWATER:magicCode06"
const WIND := "magic:magicAIR:magicCode01"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	passage_cases()
	native_cases()
	source_and_save_cases()
	terrain_rejection_cases()
	blocked_start_cases()
	print("ACTOR_TRAVERSAL_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


static func mover(id: String, point: Vector2i, role: String = "player_controlled", fly: bool = false, no_block: bool = false) -> Dictionary:
	return {"id": id, "coord": point, "hp": 100, "move_point": 4, "battle_actor_role": role,
		"traversal": {"flying": fly, "no_block": no_block, "size_type": 0}}


func passage_cases() -> void:
	var actor := mover("walker", Vector2i.ZERO)
	var ally := mover("ally", Vector2i(1,0), "friendly_ai")
	var envelope := TacticalGridRules.movement_reachability_envelope(actor, [actor, ally], {}, Vector2i(5,1))
	check(envelope["reachable_coords"].has(Vector2i(3,0)), "a friendly corridor permits reaching the free cell beyond a teammate")
	check(not envelope["reachable_coords"].has(ally["coord"]), "a traversable teammate is not a legal stopping cell")
	var route: Dictionary = envelope["reachable_by_coord"].get(Vector2i(3,0), {})
	check(route.get("path", []).has(ally["coord"]) and route.get("cost") == 3, "same-side passage keeps the native cost and actual route through its cell")
	ally["battle_actor_role"] = "enemy_ai"
	check(RulesReadback.movement_range(actor, [actor, ally], {}, Vector2i(5,1)).is_empty(), "the same corridor is blocked by an enemy")
	ally["traversal"]["no_block"] = true
	check(RulesReadback.movement_range(actor, [actor, ally], {}, Vector2i(5,1)).has(Vector2i(2,0)), "an explicit no-block actor permits passage even across sides")
	var tiles := {Vector2i(1,0): {"blocks_movement": true, "elevation": 255}}
	check(RulesReadback.movement_range(actor, [actor], tiles, Vector2i(5,1)).is_empty(), "a ground walker cannot enter a cliff")
	actor["traversal"]["flying"] = true
	check(RulesReadback.movement_range(actor, [actor], tiles, Vector2i(5,1)).has(Vector2i(3,0)), "a source flying trait traverses the height barrier")
	tiles[Vector2i(1,0)]["movement_flags"] = 0x4000
	check(RulesReadback.movement_range(actor, [actor], tiles, Vector2i(5,1)).is_empty(), "flying cannot cross a hard obstruction")
	actor["traversal"]["flying"] = false
	tiles = {Vector2i(1,0): {"elevation": 2}}
	route = TacticalGridRules.movement_reachability_envelope(actor, [actor], tiles, Vector2i(5,1))["reachable_by_coord"].get(Vector2i(1,0), {})
	check(route.get("cost") == 3, "ascending two source height levels consumes three arrival points")
	tiles = {Vector2i(1,0): {"movement_flags": 0x100000}}
	envelope = TacticalGridRules.movement_reachability_envelope(actor, [actor], tiles, Vector2i(5,1))
	check(not envelope["reachable_coords"].has(Vector2i(1,0)) and envelope["reachable_coords"].has(Vector2i(2,0)), "no-stop terrain can be passed but cannot end a move")


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_actor_traversal.json"))
	for row in packet["flood"]:
		var input: Dictionary = row["input"]
		var origin := Vector2i(input["origin"][0], input["origin"][1])
		var actor := mover("native", origin, {2: "player_controlled", 3: "enemy_ai", 6: "player_controlled", 7: "npc"}[int(input["mode"])], int(input["mode"]) == 6)
		actor["move_point"] = int(input["budget"])
		var units: Array = [actor]
		var tiles := {}
		var size := Vector2i(input["size"][0], input["size"][1])
		for y in range(size.y):
			for x in range(size.x): tiles[Vector2i(x,y)] = {"elevation": int(input["base_height"])}
		for cell in input["cells"]:
			tiles[Vector2i(cell[0], cell[1])] = {"elevation": (int(cell[2]) >> 24) & 255, "movement_flags": int(cell[2]) & TacticalGridRules.Traversal.MAP_FLAGS}
		for index in range(input["occupants"].size()):
			var entry: Dictionary = input["occupants"][index]
			units.append(mover("occupant" + str(index), Vector2i(entry["coord"][0], entry["coord"][1]), "player_controlled" if int(entry["side"]) == 0x10000 else "enemy_ai", false, entry["no_block"]))
		var before: Array = [actor.duplicate(true), units.duplicate(true), tiles.duplicate(true)]
		var envelope := TacticalGridRules.movement_reachability_envelope(actor, units, tiles, size)
		check(envelope["ok"], "source flood input remains valid")
		var routes: Dictionary = envelope["reachable_by_coord"].duplicate()
		routes.merge(envelope["transit_by_coord"])
		for y in range(row["native"].size()):
			for x in range(row["native"][y].size()):
				var point := origin + Vector2i(x - actor["move_point"], y - actor["move_point"])
				if point == origin: continue
				var remaining := int(row["native"][y][x])
				check(routes.has(point) == (remaining > 0), "transit plus stopping coverage equals the full original flood")
				if not routes.has(point): continue
				var route: Dictionary = routes[point]
				check(route["cost"] == actor["move_point"] + 1 - remaining, "source uphill, faction, clearance and flight arrival costs agree")
				check(route["path_costs"] == TacticalGridRules.path_costs(route["path"], units, tiles, actor["id"]), "displayed path uses its own cumulative costs after all route relaxation")
		check(actor == before[0] and units == before[1] and tiles == before[2], "path queries do not mutate battle truth")


static func fixture(ai: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var actor := BattlePlayLoop.unit(loop, "enemy026_1" if ai else "leonard")
	var ally := BattlePlayLoop.unit(loop, "enemy023_1")
	var foe := BattlePlayLoop.unit(loop, "leonard" if ai else "enemy021_1")
	actor.merge({"coord": Vector2i(3,5), "base_move_point": 4, "move_point": 4, "hp": 100, "max_hp": 100,
		"mp": 100, "max_mp": 100, "live_speed": 110, "inventory": [0,0,0,0,0,0,0,0], "equipment": []}, true)
	actor["combat_profile"].merge({"mind": 20, "live_magic_attack": 100}, true)
	ally.merge({"coord": Vector2i(4,5), "hp": 100, "max_hp": 100, "live_speed": 90,
		"battle_actor_role": actor["battle_actor_role"], "player_commandable": false}, true)
	foe.merge({"coord": Vector2i(8,5), "hp": 400, "max_hp": 400, "live_speed": 50}, true)
	loop["units"] = [actor, ally, foe]
	loop["tiles"] = {}
	loop["map_size"] = Vector2i(12,10)
	for y in range(10):
		for x in range(12):
			if y != 5: TestSuite.own(loop, "tiles")[Vector2i(x,y)] = {"blocks_movement": true, "elevation": 255}
	loop["reinforcement_templates"] = []
	TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["supported_initial_ids"] = [WIND, HEAL]
	actor["equipment"].append({"slot":"accessory2","item_code":232}) # Explicit permission for mobile attack/support traversal cases.
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop["interaction"] = "ai_resolving" if ai else "idle"
	return loop if ai else BattlePlayLoop.select_player_unit(loop, actor["id"])


func source_and_save_cases() -> void:
	var loop := fixture()
	check(loop["skill_book"]["actors"]["006"]["traversal"]["flying"] and loop["skill_book"]["actors"]["101"]["traversal"]["no_block"], "source-only later traits are retained without granting them to the first battle")
	check(not BattlePlayLoop.unit(loop, "leonard")["traversal"]["flying"], "the default protagonist remains a ground unit")
	var moved := BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop, "move"), Vector2i(6,5))
	var view := {"camera": Vector2(320,240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}
	var encoded := BattleCheckpoint.encode(moved, view)
	check(encoded["ok"], "a pending move through a teammate is a valid save boundary")
	if encoded["ok"]:
		var loaded := BattleCheckpoint.decode(encoded["bytes"], moved)
		check(loaded["ok"] and loaded["snapshot"]["loop"] == moved, "save restore preserves traits, accepted location and all resources without reinitializing")
		var cancelled := BattlePlayLoop.cancel_pending_move(loaded["snapshot"]["loop"])
		check(BattlePlayLoop.unit(cancelled,"leonard")["coord"] == Vector2i(3,5), "restored pending movement remains cancellable")
	var corrupt := moved.duplicate(true)
	BattlePlayLoop.unit_ref(corrupt, "leonard")["traversal"]["flying"] = true
	check(not BattleCheckpoint.encode(corrupt, view)["ok"] and BattlePlayLoop.movement_cells(corrupt).is_empty(), "forged flying capability is refused instead of silently changing a loaded route")
	var bad := fixture(true)
	bad["units"][0]["traversal"].erase("no_block")
	var refused := BattlePlayLoop.step_ai_turn(bad, no_rng)
	check(not refused["scenario_ok"] and refused["units"] == bad["units"] and refused["turn_queue"] == bad["turn_queue"], "invalid actor traits reject AI before movement, payment or RNG")
	var grown: Dictionary = BattlePlayLoop.unit(loop, "leonard")
	grown["exp"] = 99
	grown = BattlePlayLoop.ProgressionRules.resolve_experience(grown, 1, loop["equipment_items"])
	check(grown["traversal"] == BattlePlayLoop.unit(loop,"leonard")["traversal"] and grown["move_point"] == 4, "level refresh preserves intrinsic traversal and the one derived movement budget")


func no_rng(_n: int) -> int:
	check(false, "rejected operation must not draw RNG")
	return 0


func terrain_rejection_cases() -> void:
	var path := "res://ignored/actor-traversal-invalid-terrain.json"
	for data in [
		{"schema":"hsl_wrd_terrain.v1","grid":[[{"t":0,"b":0}]]},
		{"schema":"hsl_wrd_terrain.v2","grid":{}},
		{"schema":"hsl_wrd_terrain.v2","grid":[[{"t":0,"b":0,"h":255}]]}]:
		FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(data))
		check(not BattlePlayLoop.WrdTerrainTiles.load_tiles(path)["ok"], "missing or inconsistent original height bytes cannot become free terrain")
		var loop := BattleFixture.loop([], path)
		check(not loop["scenario_ok"] and loop["interaction"] == "scenario_error", "invalid source terrain refuses battle initialization")
	DirAccess.remove_absolute(path)


## Ground units the original installs on a 0xff cell (no terrain test at install, R5-L4b):
## the flood reads the start cell's own height (0x40f200 → 0x40ed50, the origin rows of the
## native packet), so from 0xff a unit crosses only other 0xff／253／254 cells — it moves
## along its cliff and never steps down.
func blocked_start_cases() -> void:
	for entry in [["006", "actor061_1"], ["552", "gulu"], ["574", "actor032_3"], ["903", "actor031_8"]]:
		var loop := BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_%s.json" % entry[0]))
		check(loop["scenario_ok"], "battle_%s loads" % entry[0])
		var unit: Dictionary = BattlePlayLoop.unit(loop, entry[1])
		var start: Vector2i = unit.get("coord", Vector2i(-1, -1))
		check(not unit.is_empty() and not unit["traversal"]["flying"] and int(loop["tiles"][start]["elevation"]) == 255, "battle_%s %s is a ground unit standing on 0xff %s" % [entry[0], entry[1], str(start)])
		var cells: Array = BattlePlayLoop.movement_cells(loop, entry[1])
		check(not cells.is_empty() and cells.all(func(cell): return int(loop["tiles"][cell]["elevation"]) >= 253), "battle_%s %s moves only along its cliff: %s" % [entry[0], entry[1], str(cells)])


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

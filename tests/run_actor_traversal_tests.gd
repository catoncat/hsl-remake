extends SceneTree
const GameOptions = preload("res://game/settings/GameOptions.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Grid = preload("res://game/sim/TacticalGridRules.gd")
const Nav = preload("res://game/sim/AINavigationRules.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const HEAL := "magic:magicWATER:magicCode06"
const WIND := "magic:magicAIR:magicCode01"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	passage_cases()
	native_cases()
	transaction_cases()
	pursuit_cases()
	source_and_save_cases()
	terrain_rejection_cases()
	blocked_start_cases()
	await presentation_cases()
	print("ACTOR_TRAVERSAL_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


static func mover(id: String, point: Vector2i, role: String = "player_controlled", fly: bool = false, no_block: bool = false) -> Dictionary:
	return {"id": id, "coord": point, "hp": 100, "move_point": 4, "battle_actor_role": role,
		"traversal": {"flying": fly, "no_block": no_block, "size_type": 0}}


func passage_cases() -> void:
	var actor := mover("walker", Vector2i.ZERO)
	var ally := mover("ally", Vector2i(1,0), "friendly_ai")
	var envelope := Grid.movement_reachability_envelope(actor, [actor, ally], {}, Vector2i(5,1))
	check(envelope["reachable_coords"].has(Vector2i(3,0)), "a friendly corridor permits reaching the free cell beyond a teammate")
	check(not envelope["reachable_coords"].has(ally["coord"]), "a traversable teammate is not a legal stopping cell")
	var route: Dictionary = envelope["reachable_by_coord"].get(Vector2i(3,0), {})
	check(route.get("path", []).has(ally["coord"]) and route.get("cost") == 3, "same-side passage keeps the native cost and actual route through its cell")
	ally["battle_actor_role"] = "enemy_ai"
	check(Grid.movement_range(actor, [actor, ally], {}, Vector2i(5,1)).is_empty(), "the same corridor is blocked by an enemy")
	ally["traversal"]["no_block"] = true
	check(Grid.movement_range(actor, [actor, ally], {}, Vector2i(5,1)).has(Vector2i(2,0)), "an explicit no-block actor permits passage even across sides")
	var tiles := {Vector2i(1,0): {"blocks_movement": true, "elevation": 255}}
	check(Grid.movement_range(actor, [actor], tiles, Vector2i(5,1)).is_empty(), "a ground walker cannot enter a cliff")
	actor["traversal"]["flying"] = true
	check(Grid.movement_range(actor, [actor], tiles, Vector2i(5,1)).has(Vector2i(3,0)), "a source flying trait traverses the height barrier")
	tiles[Vector2i(1,0)]["movement_flags"] = 0x4000
	check(Grid.movement_range(actor, [actor], tiles, Vector2i(5,1)).is_empty(), "flying cannot cross a hard obstruction")
	actor["traversal"]["flying"] = false
	tiles = {Vector2i(1,0): {"elevation": 2}}
	route = Grid.movement_reachability_envelope(actor, [actor], tiles, Vector2i(5,1))["reachable_by_coord"].get(Vector2i(1,0), {})
	check(route.get("cost") == 3, "ascending two source height levels consumes three arrival points")
	tiles = {Vector2i(1,0): {"movement_flags": 0x100000}}
	envelope = Grid.movement_reachability_envelope(actor, [actor], tiles, Vector2i(5,1))
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
			tiles[Vector2i(cell[0], cell[1])] = {"elevation": (int(cell[2]) >> 24) & 255, "movement_flags": int(cell[2]) & Grid.Traversal.MAP_FLAGS}
		for index in range(input["occupants"].size()):
			var entry: Dictionary = input["occupants"][index]
			units.append(mover("occupant" + str(index), Vector2i(entry["coord"][0], entry["coord"][1]), "player_controlled" if int(entry["side"]) == 0x10000 else "enemy_ai", false, entry["no_block"]))
		var before: Array = [actor.duplicate(true), units.duplicate(true), tiles.duplicate(true)]
		var envelope := Grid.movement_reachability_envelope(actor, units, tiles, size)
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
				check(route["path_costs"] == Grid.path_costs(route["path"], units, tiles, actor["id"]), "displayed path uses its own cumulative costs after all route relaxation")
		check(actor == before[0] and units == before[1] and tiles == before[2], "path queries do not mutate battle truth")


static func fixture(ai: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var actor := Loop.unit(loop, "enemy026_1" if ai else "leonard")
	var ally := Loop.unit(loop, "enemy023_1")
	var foe := Loop.unit(loop, "leonard" if ai else "enemy021_1")
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
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop["interaction"] = "ai_resolving" if ai else "idle"
	return loop if ai else Loop.select_player_unit(loop, actor["id"])


func transaction_cases() -> void:
	for ability in ["attack", WIND, HEAL]:
		var loop := fixture()
		if ability == HEAL:
			loop["units"][1]["hp"] = 20
			loop["units"][1]["coord"] = Vector2i(8,5)
			loop["units"][2]["coord"] = Vector2i(10,5)
			var blocker := Loop.unit(loop, "enemy023_1")
			blocker["id"] = "pass-through-ally"
			blocker["coord"] = Vector2i(4,5)
			loop["units"].append(blocker)
		var selecting := Loop.choose_command(loop, "move")
		var refused := Loop.move_unit_to(selecting, Vector2i(4,5))
		check(refused == selecting, "clicking a transit-only ally cannot spend movement or overlap units")
		var before := selecting.duplicate(true)
		var destination := Vector2i(7,5) if ability == "attack" else Vector2i(6,5)
		var moved := Loop.move_unit_to(selecting, destination)
		check(Loop.unit(moved, "leonard")["coord"] == destination and moved["pending_move"], "player commits a path beyond the friendly corridor")
		var cancelled := Loop.cancel_pending_move(moved)
		check(Loop.unit(cancelled, "leonard")["coord"] == Vector2i(3,5) and cancelled["turn_queue"] == before["turn_queue"] and not cancelled["moved_this_action"], "cancel restores source coordinate and budget without ticking turns")
		moved = Loop.move_unit_to(cancelled, destination)
		var ready := Loop.choose_command(moved, "attack" if ability == "attack" else "magic")
		if ability != "attack": ready = Loop.choose_magic(ready, ability)
		var result := Loop.attack_target(ready, "enemy023_1" if ability == HEAL else "enemy021_1", func(_n): return 0)
		check(not result.get("last_attack", {}).is_empty(), "movement through a teammate can finish with attack, magic or friendly healing")
		check(Loop.unit(result, "leonard")["coord"] == destination and result["attacked_this_action"] and not result["pending_move"], "movement and follow-up action settle together")
		if ability == HEAL: check(result["last_attack"]["healing"] > 0 and Loop.unit(result, "leonard")["mp"] == 94, "friendly support uses the exact same movement endpoint and one payment")
		elif ability == WIND: check(result["last_attack"]["actual_damage"] > 0 and result["last_attack"]["skill_id"] == WIND, "native damaging spell follows the traversed route")
		check(Loop.attack_target(result, "enemy021_1", no_rng)["units"] == result["units"], "late duplicate input cannot repeat the committed offense")


func pursuit_cases() -> void:
	var loop := fixture(true)
	var actor: Dictionary = loop["units"][0]
	actor["base_move_point"] = 1
	actor["move_point"] = 1
	var full := Nav.full_routes(loop, actor)
	var route := Nav.route_to_goals(full, [Vector2i(7,5)])
	check(not route.is_empty() and route["path_stops"] == [true,false,true,true,true], "full-map paths distinguish each transit and stopping point")
	if route.is_empty(): return
	var cut := Nav.advance_path(actor, route)
	check(cut["to"] == actor["coord"] and cut["path"].size() == 1 and cut["cost"] == 0, "budget ending on an ally keeps the AI at the previous free cell")
	actor["move_point"] = 2
	cut = Nav.advance_path(actor, route)
	check(cut["to"] == Vector2i(5,5) and cut["path"].has(Vector2i(4,5)), "enough budget crosses an ally and ends on a free cell")
	loop["units"][1]["battle_actor_role"] = "player_controlled"
	check(Nav.route_to_goals(Nav.full_routes(loop, actor), [Vector2i(7,5)]).is_empty(), "changing a corridor occupant to hostile invalidates the old route")
	loop["units"][1].merge({"hp": 0, "defeated": true}, true)
	check(not Nav.route_to_goals(Nav.full_routes(loop, actor), [Vector2i(7,5)]).is_empty(), "a defeated blocker releases both transit and landing on the next decision")
	for unavailable in ["no_mp", "silence", "none"]:
		var current := fixture(true)
		var caster: Dictionary = current["units"][0]
		caster["mp"] = 0 if unavailable == "no_mp" else 100
		if unavailable == "silence": caster.merge(Loop.StatusEffectRules.apply(caster, "no_magic", 2)["changes"], true)
		if unavailable == "none":
			caster["no_attack"] = true
			TestSuite.own(current, "skill_book")["actors"][caster["actor_id"]]["supported_initial_ids"] = []
		var after := Loop.step_ai_turn(current, func(_n): return 0)
		check(after["scenario_ok"] and after["last_ai_actions"].size() == 1, "unavailable spells continue the normal one-action decision seam")
		check(Loop.unit(after, caster["id"])["coord"] != current["units"][1]["coord"], "AI fallback never stops inside its ally")
		if unavailable == "none": check(after["last_ai_action"]["kind"] == "wait", "no useful attack, support or item produces a single Wait")


func source_and_save_cases() -> void:
	var loop := fixture()
	check(loop["skill_book"]["actors"]["006"]["traversal"]["flying"] and loop["skill_book"]["actors"]["101"]["traversal"]["no_block"], "source-only later traits are retained without granting them to the first battle")
	check(not Loop.unit(loop, "leonard")["traversal"]["flying"], "the default protagonist remains a ground unit")
	var moved := Loop.move_unit_to(Loop.choose_command(loop, "move"), Vector2i(6,5))
	var view := {"camera": Vector2(320,240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}
	var encoded := Checkpoint.encode(moved, view)
	check(encoded["ok"], "a pending move through a teammate is a valid save boundary")
	if encoded["ok"]:
		var loaded := Checkpoint.decode(encoded["bytes"], moved)
		check(loaded["ok"] and loaded["snapshot"]["loop"] == moved, "save restore preserves traits, accepted location and all resources without reinitializing")
		var cancelled := Loop.cancel_pending_move(loaded["snapshot"]["loop"])
		check(Loop.unit(cancelled,"leonard")["coord"] == Vector2i(3,5), "restored pending movement remains cancellable")
	var corrupt := moved.duplicate(true)
	Loop._unit(corrupt, "leonard")["traversal"]["flying"] = true
	check(not Checkpoint.encode(corrupt, view)["ok"] and Loop.movement_cells(corrupt).is_empty(), "forged flying capability is refused instead of silently changing a loaded route")
	var bad := fixture(true)
	bad["units"][0]["traversal"].erase("no_block")
	var refused := Loop.step_ai_turn(bad, no_rng)
	check(not refused["scenario_ok"] and refused["units"] == bad["units"] and refused["turn_queue"] == bad["turn_queue"], "invalid actor traits reject AI before movement, payment or RNG")
	var grown: Dictionary = Loop.unit(loop, "leonard")
	grown["exp"] = 99
	grown = Loop.ProgressionRules.resolve_experience(grown, 1, loop["equipment_items"])
	check(grown["traversal"] == Loop.unit(loop,"leonard")["traversal"] and grown["move_point"] == 4, "level refresh preserves intrinsic traversal and the one derived movement budget")


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
		check(not Loop.WrdTerrainTiles.load_tiles(path)["ok"], "missing or inconsistent original height bytes cannot become free terrain")
		var loop := BattleFixture.loop([], path)
		check(not loop["scenario_ok"] and loop["interaction"] == "scenario_error", "invalid source terrain refuses battle initialization")
	DirAccess.remove_absolute(path)


## Ground units the original installs on a 0xff cell (no terrain test at install, R5-L4b):
## the flood reads the start cell's own height (0x40f200 → 0x40ed50, the origin rows of the
## native packet), so from 0xff a unit crosses only other 0xff／253／254 cells — it moves
## along its cliff and never steps down. Ablation: the same start cell read at the height
## of its lowest ground neighbour lets every one of them walk off.
func blocked_start_cases() -> void:
	for entry in [["006", "actor061_1"], ["552", "gulu"], ["574", "actor032_3"], ["903", "actor031_8"]]:
		var loop := Loop.create([], "", Loop.BattleScenario.load_file("res://content/battles/battle_%s.json" % entry[0]))
		check(loop["scenario_ok"], "battle_%s loads" % entry[0])
		var unit: Dictionary = Loop.unit(loop, entry[1])
		var start: Vector2i = unit.get("coord", Vector2i(-1, -1))
		check(not unit.is_empty() and not unit["traversal"]["flying"] and int(loop["tiles"][start]["elevation"]) == 255, "battle_%s %s is a ground unit standing on 0xff %s" % [entry[0], entry[1], str(start)])
		var cells: Array = Loop.movement_cells(loop, entry[1])
		check(not cells.is_empty() and cells.all(func(cell): return int(loop["tiles"][cell]["elevation"]) >= 253), "battle_%s %s moves only along its cliff: %s" % [entry[0], entry[1], str(cells)])
		var ablated := Loop.copy(loop)
		ablated["tiles"] = loop["tiles"].duplicate()
		var ground := 255
		for delta in Grid.DIRECTIONS:
			var height := int(loop["tiles"].get(start + delta, {}).get("elevation", 255))
			if height < 253: ground = mini(ground, height)
		ablated["tiles"][start] = {"elevation": ground, "blocks_movement": false, "movement_flags": 0}
		check(Loop.movement_cells(ablated, entry[1]).any(func(cell): return int(loop["tiles"][cell]["elevation"]) < 253), "ablation: battle_%s %s walks off when its start cell is read at ground height" % entry)


func presentation_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.15).timeout
	scene.apply_loop(fixture(), "test")
	for child in scene.actors_root.get_children(): scene.actors_root.remove_child(child); child.queue_free()
	scene.unit_grid_coords.clear()
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(Vector2i(4,5))
	scene.menus.choose_command("move")
	var before: Dictionary = scene.play_loop.duplicate(true)
	GameOptions.environment_preset = "comfort"  # the OPT-GUIDE 提示 branch (原版 draws none of this)
	var view = scene.get_node("BattlePresentation")
	view.refresh(scene.play_loop,scene.map_config,true,true)
	view.show_selection(scene.play_loop,Vector2i(4,5),scene.grid_cell_center_to_logical_position(Vector2i(4,5)),Vector2(32,32))
	check(view.movement_preview.visible and not view.selection_cursor.eligible and view.selection_cursor.caption.text.contains("可通過，不能停留"), "scene preview distinguishes passage through a teammate from an accepted stopping cell")
	view.show_selection(scene.play_loop,Vector2i(6,5),scene.grid_cell_center_to_logical_position(Vector2i(6,5)),Vector2(32,32))
	check(view.movement_preview.points.size() == 4 and view.selection_cursor.caption.text == "移動 3 / 4", "preview path and arrival cost are the same route used for confirmation")
	for index in range(view.movement_preview.points.size()):
		check(view.movement_preview.points[index] == scene.actor_world_position_for_grid(Vector2i(3+index,5)), "path line shares the actor foot/grid transform")
	check(scene.play_loop == before, "showing a path never changes resources, queue or targets")
	scene.scene_input.disarm_pointer_scroll()
	check(not view.movement_preview.visible and view.movement_preview.points.is_empty(), "focus loss clears the whole route and selection feedback")
	scene.scene_input.handle_pointer_cancel(Vector2.ZERO)
	scene._process(0)
	check(not view.movement_preview.visible and scene.interaction_state == "action_menu", "cancel leaves no path behind the menu")
	GameOptions.environment_preset = ""
	# Reproduce the actual terminal seam: an AI action has settled, its last
	# animation is over, and result visibility prevents the regular AI tick.
	Loop._set_unit_hp(scene.play_loop,"leonard",0)
	Loop._set_unit_defeated(scene.play_loop,"leonard",true)
	scene.apply_loop(Loop._resolve_outcome(scene.play_loop), "test")
	scene.ai_playback_active = true
	scene.ai_playback_wait_remaining = 0.5
	var terminal: Dictionary = scene.play_loop.duplicate(true)
	for _attempt in range(12):
		scene._process(0)
		if view.dialogue_active(): view.advance_dialogue()
		if view.battle_finished: break
	check(view.battle_finished and not scene.ai_playback_active and scene.ai_playback_wait_remaining == 0.0, "visible defeat finishes AI playback before terminal save/retry")
	check(scene.play_loop == terminal and not view.movement_preview.visible and not scene.action_menu.visible, "terminal playback cleanup cannot repeat a strike or advance the queue")
	var voices: Array[WeakRef] = []
	for player in scene.find_children("*","AudioStreamPlayer",true,false):
		if player.playing:
			var deadline := Time.get_ticks_msec() + 1000
			while player.playing and player.get_playback_position() <= 0 and Time.get_ticks_msec() < deadline: await create_timer(0.01).timeout
			if player.playing: voices.append(weakref(player.get_stream_playback()))
		player.stop(); player.stream = null
	scene.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while voices.any(func(voice):return voice.get_ref() != null) and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

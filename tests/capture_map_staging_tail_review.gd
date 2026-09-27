extends SceneTree

## Windowed review captures for lane R5-L4b: level 6's villager 061_1 on its original
## install cell (25,15); level 39's third-quake collapse (the first-control unit moved to
## the hole's south-east edge, its move range before and after WINFAIL039 event 5 inserts the
## obj_Story_Block rows); the original draw order next to a building (level 38's grave
## over the ground unit north of it, and 576's flying 雷特 drawn over the same grave).
## Saves the game viewport only (never the desktop) to the directory given after `--`
## (default user://map_staging_tail_review). Not a gate suite: the pictures are for
## manual acceptance.
##   tools/godot.sh --script res://tests/capture_map_staging_tail_review.gd -- /abs/output/dir

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const Winfail = preload("res://game/sim/WinfailScenarioRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")

## South-east edge of the level-39 collapse (row 28 of the block rows spans cells 12..19):
## from here the most collapse cells are in move range before the quake.
const HOLE_EDGE := Vector2i(20, 28)

var output := "user://map_staging_tail_review"
var failures: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")


func _note(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("MAP_STAGING_TAIL_NOTE %s" % message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	await _level_6()
	await _level_39()
	await _draw_order("res://content/battles/battle_038.json", "actor034_1", "level38_ground_unit_behind_grave")
	await _draw_order("res://content/battles/battle_576.json", "rett", "level576_flying_rett_over_grave")
	for failure in failures:
		push_warning(failure)
	print("MAP_STAGING_TAIL_REVIEW_DONE dir=%s notes=%d" % [output, failures.size()])
	quit(0)


func _boot(path: String) -> Node:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [output, name])
	print("MAP_STAGING_TAIL_REVIEW_SHOT %s" % name)


func _free(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _to_first_control(scene: Node) -> void:
	var coordinator = scene.opening_coordinator
	for _frame in range(20000):
		if coordinator == null or not coordinator.active:
			return
		if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
		await process_frame


func _look_at(scene: Node, cell: Vector2i) -> void:
	scene.camera.position = scene.camera_controller.clamped_position(scene.actor_world_position_for_grid(cell))


func _level_6() -> void:
	var scene = await _boot("res://content/battles/battle_006.json")
	await _to_first_control(scene)
	var villager: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "actor061_1")
	_note(villager.get("coord") == Vector2i(25, 15), "level 6: 061_1 stands on (25,15): %s" % str(villager.get("coord")))
	scene.menus.set_action_menu_visible(false)
	_look_at(scene, Vector2i(25, 15))
	await _shot("level06_villager_061_1_at_25_15")
	await _free(scene)


func _level_39() -> void:
	var scene = await _boot("res://content/battles/battle_039.json")
	await _to_first_control(scene)
	var rules = scene.BattlePlayLoop
	var mover := str(scene.play_loop.get("selected_unit_id", ""))
	var loop: Dictionary = rules.copy(scene.play_loop)
	rules._set_unit_coord(loop, mover, HOLE_EDGE)
	scene.apply_loop(loop, "test")
	scene.menus.choose_command("move")
	print("MAP_STAGING_TAIL_MOVE before mover=%s at=%s overlay=%d" % [mover, str(rules.unit(scene.play_loop, mover).get("coord")), scene.move_overlay_cells.size()])
	scene.center_camera_on_grid(HOLE_EDGE + Vector2i(-3, -2))
	await _shot("level39_move_range_before_collapse")
	scene.overlays.set_move_overlay_visible(false)
	# Round 7, WINFAIL039 event 5 armed: the third quake deletes the units on the ten
	# rows and inserts obj_Story_Block over them.
	scene.set_process(false)
	loop["event_statuses"] = [5]
	loop["turn"] = 7
	loop = Winfail.run_event_hooks(loop)
	_note((loop.get("terrain_edits", []) as Array).size() == 89, "level 39: the collapse edits 89 cells: %d" % (loop.get("terrain_edits", []) as Array).size())
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var coordinator = scene.opening_coordinator
	for _frame in range(4000):
		await process_frame
		if coordinator == null or not coordinator.active:
			break
		if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
	var cells: Array = rules.movement_cells(scene.play_loop, mover)
	var hole := {}
	for edit in scene.play_loop.get("terrain_edits", []):
		hole[edit["cell"]] = true
	_note(not cells.any(func(cell): return hole.has(cell)), "level 39: the move range avoids the collapse")
	_note(bool(TerrainEdits.tiles(scene.play_loop)[Vector2i(16, 25)]["blocks_movement"]), "level 39: (16,25) is a cliff after the quake")
	if str(scene.play_loop.get("selected_unit_id", "")) == mover and str(scene.play_loop.get("interaction", "")) == "action_menu":
		scene.menus.choose_command("move")
	else:
		_note(false, "level 39: %s is not the acting unit after the quake (%s)" % [mover, str(scene.play_loop.get("selected_unit_id", ""))])
	print("MAP_STAGING_TAIL_MOVE after mover=%s at=%s overlay=%d selected=%s" % [mover, str(rules.unit(scene.play_loop, mover).get("coord")), scene.move_overlay_cells.size(), scene.selected_unit_id])
	scene.center_camera_on_grid(HOLE_EDGE + Vector2i(-3, -2))
	await _shot("level39_move_range_after_collapse")
	await _free(scene)


func _draw_order(path: String, unit_id: String, name: String) -> void:
	var scene = await _boot(path)
	await _to_first_control(scene)
	var actor: Node = scene.actor_node_for_unit(unit_id)
	_note(actor != null, "%s: %s has a field actor" % [path, unit_id])
	if actor != null:
		print("MAP_STAGING_TAIL_DEPTH %s %s z=%d flying=%s" % [path.get_file(), unit_id, actor.z_index, str(actor.flying_depth)])
	scene.menus.set_action_menu_visible(false)
	_look_at(scene, scene.unit_grid_coord(unit_id) + Vector2i(0, 1))
	await _shot(name)
	await _free(scene)

extends SceneTree

## Windowed review captures for lane R5-L4c: encounter 552's player-controlled 咕嚕 on
## its original 0xff install cell (5,18) and the move range the shared flood gives it (the
## connected cliff cells only — the original reads the start cell's own height, see
## docs/evidence_packets/static_reverse/original_actor_traversal.md); level 28's first door
## (4,48) shut before WINFAIL028 event 3 and open after it (killing the door guard the STORY
## re-coded 5000 inserts obj_Story_Level_ClearWall, a loop terrain edit). The 咕嚕 overlay
## is the rule's movement_cells for 咕嚕 drawn while another unit holds the turn. Saves the
## game viewport only (never the desktop) to the directory given after `--` (default
## user://terrain_start_cells_review). Not a gate suite: the pictures are for manual
## acceptance.
##   tools/godot.sh --script res://tests/capture_terrain_start_cells_review.gd -- /abs/output/dir

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const Winfail = preload("res://game/sim/WinfailScenarioRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")

const GULU_CELL := Vector2i(5, 18)
const DOOR := Vector2i(4, 48)
## Corridor cell south of the level-28 first door: the room behind it is in move range only
## once the door is open.
const DOOR_APPROACH := Vector2i(4, 49)

var output := "user://terrain_start_cells_review"
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
		print("TERRAIN_START_CELLS_NOTE %s" % message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	await _gulu()
	await _door()
	for failure in failures:
		push_warning(failure)
	print("TERRAIN_START_CELLS_REVIEW_DONE dir=%s notes=%d" % [output, failures.size()])
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
	print("TERRAIN_START_CELLS_REVIEW_SHOT %s" % name)


func _free(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _play_coordinator(scene: Node, frames: int) -> void:
	var coordinator = scene.opening_coordinator
	for _frame in range(frames):
		if coordinator == null or not coordinator.active:
			return
		if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
		await process_frame


func _gulu() -> void:
	var scene = await _boot("res://content/battles/battle_552.json")
	await _play_coordinator(scene, 20000)
	var rules = scene.BattlePlayLoop
	var gulu: Dictionary = rules.unit(scene.play_loop, "gulu")
	_note(gulu.get("coord") == GULU_CELL, "552: 咕嚕 starts on (5,18): %s" % str(gulu.get("coord")))
	scene.menus.set_action_menu_visible(false)
	scene.center_camera_on_grid(GULU_CELL)
	await _shot("encounter552_gulu_on_cliff_opening")
	scene.set_process(false)
	scene.selected_unit_id = "gulu"
	scene.overlays.set_move_overlay_visible(true)
	var cells: Array = scene.move_overlay_cells
	var tiles: Dictionary = scene.play_loop["tiles"]
	_note(not cells.is_empty() and cells.all(func(cell): return int(tiles[cell]["elevation"]) == 255), "552: 咕嚕's range is cliff cells only: %s" % str(cells))
	print("TERRAIN_START_CELLS_GULU at=%s overlay=%d cells=%s" % [str(gulu.get("coord")), cells.size(), str(cells)])
	await _shot("encounter552_gulu_move_range")
	await _free(scene)


func _door() -> void:
	var scene = await _boot("res://content/battles/battle_028.json")
	await _play_coordinator(scene, 20000)
	var rules = scene.BattlePlayLoop
	var mover := str(scene.play_loop.get("selected_unit_id", ""))
	var loop: Dictionary = rules.copy(scene.play_loop)
	rules._set_unit_coord(loop, mover, DOOR_APPROACH)
	scene.apply_loop(loop, "test")
	scene.menus.choose_command("move")
	var before: Array = scene.move_overlay_cells.duplicate()
	_note(not before.any(func(cell): return cell.y < DOOR.y), "28: the room behind the shut door is out of range")
	print("TERRAIN_START_CELLS_DOOR before mover=%s at=%s overlay=%d cells=%s" % [mover, str(rules.unit(scene.play_loop, mover).get("coord")), before.size(), str(before)])
	scene.center_camera_on_grid(DOOR)
	await _shot("level28_door_4_48_before_event3")
	scene.overlays.set_move_overlay_visible(false)
	# The door guard re-coded 5000 (guard050_6) falls: WINFAIL028 event 3 inserts
	# obj_Story_Level_ClearWall at (128,1536) and clears the door's 0x4000.
	scene.set_process(false)
	loop = rules.copy(scene.play_loop)
	rules._set_unit_hp(loop, "guard050_6", 0)
	rules._set_unit_defeated(loop, "guard050_6", true)
	loop = Winfail.run_event_hooks(loop)
	_note(not (int(TerrainEdits.tiles(loop)[DOOR]["movement_flags"]) & 0x4000), "28: event 3 opens (4,48)")
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	for _frame in range(4000):
		await process_frame
		var coordinator = scene.opening_coordinator
		if coordinator == null or not coordinator.active:
			break
		if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
	var interaction := str(scene.play_loop.get("interaction", ""))
	if str(scene.play_loop.get("selected_unit_id", "")) != mover:
		_note(false, "28: %s is not the acting unit after event 3 (%s)" % [mover, str(scene.play_loop.get("selected_unit_id", ""))])
	elif interaction == "action_menu":
		scene.menus.choose_command("move")
	else:
		# Still choosing the move target (the event fired mid-selection): redraw the range
		# over the edited map.
		scene.overlays.set_move_overlay_visible(true)
	for _frame in range(360):
		await process_frame  # let the WhiteLight／Fire insert effects play out
	var after: Array = scene.move_overlay_cells
	_note(after.any(func(cell): return cell.y < DOOR.y), "28: the room behind the open door is in range")
	print("TERRAIN_START_CELLS_DOOR after mover=%s overlay=%d cells=%s" % [mover, after.size(), str(after)])
	scene.center_camera_on_grid(DOOR)
	await _shot("level28_door_4_48_after_event3")
	await _free(scene)

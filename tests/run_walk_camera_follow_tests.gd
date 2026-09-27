extends SceneTree

## Walk follow (camera_panel_motion §1): the original's battle walkers (defProcEnemy 0x4411cb,
## defProcPlayer 0x443f5a) and the script's Wait walks (0x453b90 state 0x32) request their own
## per-tick step for the camera through 0x42dc50 unless the walker stands within half a view of
## the map edge it walks toward; 0x46bede adds the requests and clamps (static-derived). The
## recording shows the camera turning with an AI walker's path at about 4 px per tick
## (110.74–111.30 s, runtime-measured). On level 51 this suite checks, on production frames:
## every AI walk of the first enemy turn hands the camera BattleCameraController's follow trace
## (not a glide to the destination), the player's own walk does the same, and Leonard's opening
## actWalkDispWait (speed 2) is followed 2 px per tick while a plain actWalkDisp is not.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleForceWin = preload("res://tests/support/BattleForceWin.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const HALF_VIEW := Vector2(320, 240)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	await _ai_and_player_walks()
	await _opening_wait_walk()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	if failures.is_empty():
		print("WALK_CAMERA_FOLLOW_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("WALK_CAMERA_FOLLOW_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _expected_trace(scene: Node, walker_start: Vector2, points: Array, pixels_per_tick: float) -> Array:
	return BattleCameraController.walk_follow_trace(scene.camera.position, walker_start, points, pixels_per_tick, HALF_VIEW, Vector2(scene.map_config.world_size))


## Consecutive camera positions differ by at most `step` per axis (the walker's own step).
func _steps_within(start: Vector2, trace: Array, step: float) -> bool:
	var previous := start
	for position in trace:
		var delta: Vector2 = position - previous
		if absf(delta.x) > step + 0.001 or absf(delta.y) > step + 0.001:
			return false
		previous = position
	return true


func _ai_and_player_walks() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	var presentation = scene.get_node("BattlePresentation")
	var controller = scene.camera_controller
	var preview = scene.ai_move_preview
	var frames := 0
	while frames < 600 and (scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state != "action_menu"):
		await process_frame
		frames += 1
	scene.menus.choose_command("wait")
	var walks := 0
	var followed := 0
	var off_trace := 0
	var unit_id := ""
	var origin := Vector2.ZERO
	var trace: Array = []
	frames = 0
	while frames < 3600 and not (scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion()):
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		var was_previewing: bool = preview.busy()
		if was_previewing:
			unit_id = preview._unit_id
			origin = scene.actor_node_for_unit(unit_id).position
		await process_frame
		frames += 1
		if was_previewing and not preview.busy():
			# The walk started this frame; the follow has not stepped yet (advance_camera runs
			# before the preview tick), so the camera still stands where the preview left it.
			walks += 1
			var actor = scene.actor_node_for_unit(unit_id)
			var expected := _expected_trace(scene, origin, actor.last_path, BattleCameraController.WALK_FOLLOW_PIXELS_PER_TICK)
			var moves: bool = expected.any(func(position: Vector2) -> bool: return position != scene.camera.position)
			if moves:
				followed += 1
				_assert_true(controller.scroll_mode == "follow", "AI walk of %s: the camera follows the walker instead of gliding to the destination (%s)" % [unit_id, controller.scroll_mode])
				_assert_true(controller._follow_trace == expected, "AI walk of %s: the follow is the 0x4411cb trace from the walker's origin" % unit_id)
				_assert_true(_steps_within(scene.camera.position, expected, 4.0), "AI walk of %s: the camera never steps more than the walker's 4 px per tick" % unit_id)
				trace = [scene.camera.position] + expected
			else:
				_assert_true(controller.scroll_mode != "follow", "AI walk of %s near the map edge leaves the camera where it is" % unit_id)
				trace = []
		elif controller.scroll_mode == "follow" and not trace.is_empty() and not trace.has(scene.camera.position):
			off_trace += 1
	_assert_true(walks >= 2, "the first enemy turn walks at least two AI units (%d)" % walks)
	_assert_true(followed >= 1, "at least one AI walk moves the camera with the walker (%d of %d)" % [followed, walks])
	_assert_eq_int(off_trace, 0, "while following, the camera only takes its start or the trace's positions")
	print("WALK_CAMERA_FOLLOW ai_walks=%d followed=%d" % [walks, followed])
	# The player's own walk: defProcPlayer runs the same follow block (0x443f5a).
	scene.flush_ai_playback()
	frames = 0
	while frames < 600 and (scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state != "action_menu"):
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		await process_frame
		frames += 1
	scene.select_actor("leonard")
	scene.menus.choose_command("move")
	var start_grid: Vector2i = scene.unit_grid_coord("leonard")
	var target := start_grid
	var best := -1
	for cell in scene.BattlePlayLoop.movement_cells(scene.play_loop, "leonard"):
		var distance: int = absi(cell.x - start_grid.x) + absi(cell.y - start_grid.y)
		if distance > best:
			best = distance
			target = cell
	# The selection glide lands first, so the follow starts from the view centred on Leonard.
	controller.finish_scroll()
	var grid_path: Array = scene.BattlePlayLoop.movement_path(scene.play_loop, "leonard", target)
	var world_path: Array = []
	for cell in grid_path.slice(1):
		world_path.append(scene.actor_world_position_for_grid(cell))
	var expected_player := _expected_trace(scene, scene.actor_world_position_for_grid(start_grid), world_path, BattleCameraController.WALK_FOLLOW_PIXELS_PER_TICK)
	scene.move_selected_actor_to_grid(target)
	_assert_true(scene.unit_grid_coord("leonard") == target, "Leonard walks to the farthest reachable cell %s" % [target])
	if expected_player.any(func(position: Vector2) -> bool: return position != scene.camera.position):
		_assert_true(controller.scroll_mode == "follow" and controller._follow_trace == expected_player, "the player's walk is followed along the same trace (%s)" % controller.scroll_mode)
		_assert_true(controller.scroll_target == expected_player.back(), "the follow ends where the walker's last step leaves the camera")
	else:
		_assert_true(controller.scroll_mode != "follow", "a player walk at the map edge leaves the camera alone")
	scene.queue_free()
	await process_frame


## STORY051: actWalkDispWait SID_PLAYER0 1 0 -96 2 (Leonard 3 cells north at speed 2).
func _opening_wait_walk() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	var controller = scene.camera_controller
	var checked := false
	for _frame in range(4000):
		if coordinator == null or not coordinator.active:
			break
		if not checked and coordinator.motion_records.size() == 1:
			checked = true
			var record: Dictionary = coordinator.motion_records[0]
			var walk: Dictionary = coordinator.story_objects._last_walk
			_assert_true(is_equal_approx(float(record.get("speed_arg", 0.0)), 2.0), "Leonard's opening walk is speed 2")
			_assert_true(is_equal_approx(float(walk.get("pixels_per_tick", 0.0)), 2.0), "the follow steps the walk's own 2 px per tick (%s)" % walk.get("pixels_per_tick"))
			var expected := _expected_trace(scene, walk["start"], walk["points"], 2.0)
			if expected.any(func(position: Vector2) -> bool: return position != scene.camera.position):
				_assert_true(controller.scroll_mode == "follow" and controller._follow_trace == expected, "Leonard's actWalkDispWait is followed by the camera (%s)" % controller.scroll_mode)
			else:
				# Walking north below the map's last half view: 0x453fbd requests nothing.
				_assert_true(controller.scroll_mode != "follow", "Leonard's walk inside the bottom half view leaves the camera clamped")
			print("WALK_CAMERA_FOLLOW opening_walk start=%s camera=%s world=%s follows=%s" % [walk["start"], scene.camera.position, scene.map_config.world_size, controller.scroll_mode == "follow"])
		if str(coordinator.summary().get("current_event_kind", "")) in BattleForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(BattleForceWin.click())
		await process_frame
	_assert_true(checked, "the opening reached Leonard's walk")
	# After the opening: a Wait walk that leaves the bottom half view is followed 4 px per tick
	# once Leonard is above it; the same walk as a plain actWalkDisp (+0x50 = 0) is not.
	if coordinator != null:
		var before: int = controller.follow_count
		coordinator.story_objects._walk_relative({"id": "test_plain_walk", "args": ["SID_PLAYER0", "1", "0", "-256", "4"], "kind": "actor_walk_disp"}, false)
		_assert_true(controller.follow_count == before and controller.scroll_mode != "follow", "a plain actWalkDisp does not move the camera with the walker")
		var leonard = scene.actor_node_for_unit("leonard")
		leonard.move_along([leonard.last_path[0]], 0.0)
		coordinator.story_objects._walk_relative({"id": "test_wait_walk", "args": ["SID_PLAYER0", "1", "0", "-256", "4"], "kind": "actor_walk_disp_wait"}, true)
		var walk: Dictionary = coordinator.story_objects._last_walk
		var expected := _expected_trace(scene, walk["start"], walk["points"], 4.0)
		_assert_true(controller.follow_count == before + 1 and controller._follow_trace == expected, "the Wait form of the same walk is followed (%s)" % controller.scroll_mode)
		_assert_true(expected.back().y < scene.camera.position.y and _steps_within(scene.camera.position, expected, 4.0), "the camera walks north with Leonard at 4 px per tick (%s → %s)" % [scene.camera.position, expected.back()])
	TestSuite.stop_audio(scene.get_node_or_null("BattleMusic"))
	scene.queue_free()
	await process_frame


func _assert_eq_int(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		failures.append("%s (got %d, expected %d)" % [message, actual, expected])

extends SceneTree

## Extended STORY token handling in BattleOpeningCoordinator: a minimal hand-built
## timeline (compiler kinds + params, not a tracked script) is fed to the coordinator
## inside the level-53 opening preview scene (story mode: EVEF cast, stand objects,
## message evidence 694-704). Each new kind is asserted through its record or its
## visible effect; record-only kinds must land in story_records, never in
## skipped_records. Pacing values are shortened; token order and semantics are unchanged.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const SceneTimeline = preload("res://game/battle/runtime/SceneTimeline.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleCameraController = preload("res://game/battle/runtime/BattleCameraController.gd")
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _event(index: int, kind: String, name: String, args: Array, extra: Dictionary = {}) -> Dictionary:
	var string_args: Array = []
	for value in args:
		string_args.append(str(value))
	var event := {
		"id": "token_%02d_%s" % [index, kind],
		"kind": kind,
		"source_script": "token_test",
		"source_file": "tests/run_opening_token_tests.gd",
		"source_action_index": index,
		"source_chain_index": 0,
		"script_action_name": name,
		"primary": name,
		"args": string_args,
		"source_token": "%s(%s)" % [name, ",".join(string_args)],
		"display_line": "%s test token" % kind,
		"message_id": "",
		"actor_token": str(args[0]) if not args.is_empty() and str(args[0]).begins_with("SID_") else "",
		"evidence_tier": "godot-rendered-provisional",
		"presentation_status": "test_fixture",
		"synthetic": false,
		"unresolved_semantics": ["hand-built test event"],
	}
	event.merge(extra, true)
	return event


func _click(coordinator: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	coordinator.handle_input(click)


func _records_of(summary: Dictionary, kind: String) -> Array:
	var result: Array = []
	for record in summary.get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == kind:
			result.append(record)
	return result


func _stand_object_at(scene: Node, anchor: Vector2) -> Node:
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		for child in layer.get_children():
			if child.has_meta("candidate_anchor_world") and (child.get_meta("candidate_anchor_world") as Vector2).is_equal_approx(anchor):
				return child
	return null


func _run() -> void:
	CampaignProgress.reset_campaign()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_053.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.story_mode, "the level-53 preview should host the coordinator in story mode")
	if coordinator == null:
		_finish(scene)
		return

	var bar = _stand_object_at(scene, Vector2(640, 488))
	_assert_true(bar != null and bar.visible, "bar002 stand object at EVEF (640,488) should be spawned for the position-delete check")

	# Hand-built timeline: kinds and params follow tools/hsl_opening_timeline_compile.py.
	var events: Array = [
		_event(0, "camera_position_set", "actSetBGToPos", [0, 96], {"params": {"x": 0, "y": 96}}),
		_event(1, "camera_position_target_speed", "actScrollBGToPosSpeed", [640, 448, 4], {"params": {"x": 640, "y": 448, "speed": 4}}),
		_event(2, "actor_walk_disp", "actWalkDisp", ["SID_ENEMY029", 1, 0, 32, 0]),
		_event(3, "actor_action_wait", "actWaitPlayer", ["SID_ENEMY029", 1], {"params": {"player_code": "SID_ENEMY029", "serial": 1}}),
		_event(4, "dialogue_message_if_exist", "actMessageIfExist", ["SID_ENEMY029", 1, 699, 700, 1, "SID_ENEMY029"],
			{"message_id": "699", "message_id_false": "700", "params": {"player_code": "SID_ENEMY029", "serial": 1, "message_id": 699, "message_id_false": 700, "check_number": 1, "check_player_codes": ["SID_ENEMY029"]}}),
		_event(5, "dialogue_message_if_exist", "actMessageIfExist", ["SID_ENEMY029", 1, 701, 702, 1, "SID_ENEMY023"],
			{"message_id": "701", "message_id_false": "702", "message_text_false": "（測試用備用對白）", "params": {"player_code": "SID_ENEMY029", "serial": 1, "message_id": 701, "message_id_false": 702, "check_number": 1, "check_player_codes": ["SID_ENEMY023"]}}),
		_event(6, "dialogue_message_if_exist", "actMessageIfExist", ["SID_ENEMY029", 1, 703, 0, 1, "SID_ENEMY023"],
			{"message_id": "703", "message_id_false": "", "params": {"player_code": "SID_ENEMY029", "serial": 1, "message_id": 703, "message_id_false": 0, "check_number": 1, "check_player_codes": ["SID_ENEMY023"]}}),
		_event(7, "show_position_marker", "actInsertShowPosObject", [640, 736]),
		_event(8, "position_object_delete", "actDeletePosObject", [640, 488, 2, "defProcStandObject"], {"params": {"x": 640, "y": 488, "range": 2, "proc_code": "defProcStandObject"}}),
		_event(9, "position_object_delete", "actDeletePosObject", [640, 736, 8, "defProcStandObject"], {"params": {"x": 640, "y": 736, "range": 8, "proc_code": "defProcStandObject"}}),
		_event(10, "actor_delete", "actDeleteObject", ["SID_ENEMY029", 1], {"params": {"code": "SID_ENEMY029", "serial": 1}}),
		_event(11, "actor_delete", "actDeleteObject", ["SID_ENEMY023", 1], {"params": {"code": "SID_ENEMY023", "serial": 1}}),
		_event(12, "screen_darken", "actDarkScreen", []),
		_event(13, "screen_darken_clear", "actDeleteDarkScreen", [], {"params": {}}),
		_event(14, "player_undead_flag", "actSetPlayerUndead", ["SID_ENEMY029", 1, 1], {"params": {"code": "SID_ENEMY029", "serial": 1, "mode": 1}}),
		_event(15, "town_event_add", "actAddTE", ["town_歐姆村", 0, 1, 9], {"params": {"town_id": "town_歐姆村", "parent": 0, "num": 1, "children": [9]}}),
		_event(16, "earthquake", "actEarthQuake", [20], {"params": {"delay": 20}}),
		{
			"id": "scene_end_ready", "kind": "scene_end_marker", "source_script": "token_test", "source_file": "tests/run_opening_token_tests.gd",
			"source_action_index": null, "source_chain_index": null, "script_action_name": "scene_end_ready", "primary": "scene_end_ready",
			"args": [], "source_token": "scene_end_ready", "display_line": "Scene-end marker", "evidence_tier": "godot-rendered-provisional",
			"presentation_status": "handoff_marker_only", "synthetic": true, "unresolved_semantics": ["test marker"],
		},
	]
	scene.scene_timeline = SceneTimeline.from_events(events)
	coordinator.walk_pixels_per_second = 1600.0  # the 32 px actWalkDisp lasts 0.02 s: longer than one step
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	coordinator.move_pixels_per_frame_hz = 60000.0
	coordinator.start()

	# actSetBGToPos applies immediately: the raw point (0,96) goes to the view's (320,192)
	# (0x43bf30 case 0x61, original_script_camera_scroll.md), clamped to the map.
	var expected_set: Vector2 = scene.camera_controller.clamped_position(Vector2(0, 96) + Vector2(0, 48))
	_assert_true(scene.camera.position.is_equal_approx(expected_set), "camera_position_set should put the clamped (0,96) point at the view's script focus immediately")
	var first_camera: Array = coordinator.summary().get("camera_records", [])
	_assert_eq(first_camera.size(), 1, "one camera record after the first token")
	if first_camera.size() == 1:
		_assert_eq((first_camera[0] as Dictionary).get("scroll"), false, "camera_position_set is recorded as a non-scrolling placement")
		_assert_eq((first_camera[0] as Dictionary).get("position_args"), [0, 96], "camera_position_set keeps the script x,y")

	var princess = scene.get_node_or_null("World/Actors/ActorRuntime_actor029_1")
	_assert_true(princess != null and princess.visible, "SID_ENEMY029/1 should be bound to a visible cast actor")
	var start_position: Vector2 = princess.position if princess != null else Vector2.ZERO

	var dialogue_speakers: Array[String] = []
	var dialogue_message_ids: Array[String] = []
	var dialogue_event_ids: Array[String] = []
	var resolved_kinds: Array[String] = []
	var dark_alpha_peak := 0.0
	var marker_peak := 0
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 3000:
		var current: Dictionary = scene.scene_timeline.current_event()
		if str(current.get("kind", "")) == "dialogue_message_id":
			_assert_true(scene.opening_overlay.visible, "a resolved conditional message must show the shared dialogue board")
			var event_id := str(current.get("id", ""))
			if not dialogue_event_ids.has(event_id):
				dialogue_event_ids.append(event_id)
				dialogue_speakers.append(str(scene.opening_overlay.speaker_label.text))
				dialogue_message_ids.append(str(current.get("message_id", "")))
				resolved_kinds.append(str(current.get("resolved_from_kind", "")))
			_click(coordinator)
		if coordinator.cinematics._dark_screen != null:
			dark_alpha_peak = maxf(dark_alpha_peak, coordinator.cinematics._dark_screen.color.a)
		marker_peak = maxi(marker_peak, coordinator.story_objects._position_markers.size())
		await process_frame
		frames += 1

	_assert_true(coordinator.story_finished, "the hand-built timeline should reach scene_end_marker within the frame budget")
	var summary: Dictionary = coordinator.summary()

	# camera_position_target_speed: 0x43c140 with step = speed 4, tolerance 1.
	var cameras: Array = summary.get("camera_records", [])
	_assert_true(cameras.size() >= 2, "the speed scroll should add a camera record")
	if cameras.size() >= 2:
		var scroll: Dictionary = cameras[1]
		_assert_eq(scroll.get("scroll"), true, "camera_position_target_speed scrolls")
		_assert_eq(scroll.get("speed_arg"), 4.0, "the speed argument is preserved")
		# actScrollBGToPosSpeed rounds (640,448) to its cell centre (656,464) first (VM stage 0).
		var expected_scroll: Vector2 = scene.camera_controller.clamped_position(Vector2(656, 464) + Vector2(0, 48))
		_assert_true((scroll.get("target") as Vector2).is_equal_approx(expected_scroll), "the scroll target puts the clamped (640,448) cell centre at the view's script focus")
		var expected_ticks := BattleCameraController.scroll_ticks(expected_set, expected_scroll, 4, BattleCameraController.SPEED_SCROLL_TOLERANCE)
		var expected_seconds: float = OriginalTick.seconds(expected_ticks) if expected_ticks > 1 else 0.0
		_assert_true(is_equal_approx(float(scroll.get("duration_seconds", 0.0)), expected_seconds), "scroll duration = the ticks of 0x43c140 (step = speed 4, tolerance 1)")

	# actor_walk_disp (non-blocking) + actor_action_wait: the wait sees the walk in flight.
	var waits := _records_of(summary, "actor_action_wait")
	_assert_eq(waits.size(), 1, "actWaitPlayer should be recorded once")
	if waits.size() == 1:
		_assert_eq((waits[0] as Dictionary).get("unit_id"), "actor029_1", "the wait binds SID_ENEMY029/1")
		_assert_eq((waits[0] as Dictionary).get("was_moving"), true, "the wait should start while the non-blocking walk is still running")
	if princess != null:
		_assert_true(princess.position.is_equal_approx(start_position + Vector2(0, 32)), "the walk should have completed 32px down before the queue moved on")

	# dialogue_message_if_exist: present check -> true id, absent check -> false id, absent + 0 -> nothing.
	_assert_eq(dialogue_message_ids, ["699", "702"], "true branch 699 (SID_ENEMY029 present) then false branch 702 (SID_ENEMY023 absent); 703/0 shows nothing")
	_assert_eq(resolved_kinds, ["dialogue_message_if_exist", "dialogue_message_if_exist"], "both shown messages are resolved conditional tokens")
	if dialogue_speakers.size() == 2:
		_assert_eq(dialogue_speakers[0], "緹娜：", "the conditional message keeps the speaker token's label")
		_assert_eq(dialogue_speakers[1], "緹娜：", "the false branch is spoken by the same token")
	var conditionals := _records_of(summary, "dialogue_message_if_exist")
	_assert_eq(conditionals.size(), 3, "every actMessageIfExist token leaves a record")
	if conditionals.size() == 3:
		_assert_eq((conditionals[0] as Dictionary).get("exists"), true, "check SID_ENEMY029 exists")
		_assert_eq((conditionals[0] as Dictionary).get("status"), "resolved_to_dialogue", "first conditional resolved")
		_assert_eq((conditionals[1] as Dictionary).get("exists"), false, "check SID_ENEMY023 (not yet inserted) is absent")
		_assert_eq((conditionals[1] as Dictionary).get("message_id"), "702", "the false id is shown when the check fails")
		_assert_eq((conditionals[2] as Dictionary).get("status"), "no_message_for_branch", "false id 0 shows nothing and auto-advances")
	var page_after_false: Dictionary = scene.scene_timeline.events[5]
	_assert_eq(str(page_after_false.get("kind", "")), "dialogue_message_id", "the resolved event is written back into the timeline")
	_assert_eq(str(page_after_false.get("message_text", "")), "（測試用備用對白）", "the false branch uses the compiled message_text_false")

	# position_object_delete: the bar002 stand object at (640,488) is hidden, the marker at (640,736) removed.
	_assert_true(bar != null and not bar.visible, "actDeletePosObject(640,488,2) should hide the bar002 stand object at that anchor")
	_assert_eq(marker_peak, 1, "one position marker was shown before its position delete")
	_assert_eq(coordinator.story_objects._position_markers.size(), 0, "actDeletePosObject(640,736,8) removes the marker on that cell")
	var deletes := _records_of(summary, "position_object_delete")
	_assert_eq(deletes.size(), 2, "both position deletes are recorded")
	if deletes.size() == 2:
		_assert_eq((deletes[0] as Dictionary).get("status"), "removed", "the stand-object delete matched")
		_assert_eq(((deletes[0] as Dictionary).get("removed") as Array).size(), 1, "exactly one stand object matched the 2px radius")
		_assert_eq((deletes[1] as Dictionary).get("status"), "removed", "the marker delete matched")

	# actor_delete: bound actor hidden and recorded; an unbound token is an explicit skip.
	if princess != null:
		_assert_true(not princess.visible, "actDeleteObject should hide the bound actor")
	var deleted := _records_of(summary, "actor_deleted")
	_assert_eq(deleted.size(), 1, "one actor_deleted record from actDeleteObject")
	if deleted.size() == 1:
		_assert_eq((deleted[0] as Dictionary).get("source_kind"), "actor_delete", "the record names the token kind")
	var skipped: Array = summary.get("skipped_records", [])
	_assert_eq(skipped.size(), 1, "only the unbound actDeleteObject(SID_ENEMY023) is skipped")
	if skipped.size() == 1:
		_assert_eq((skipped[0] as Dictionary).get("kind"), "actor_delete", "the skip names actor_delete")
		_assert_eq((skipped[0] as Dictionary).get("reason"), "unbound_actor", "the skip reason is the missing binding")

	# screen_darken then screen_darken_clear.
	_assert_true(dark_alpha_peak > 0.5, "actDarkScreen should have faded the dark rect in")
	_assert_true(coordinator.cinematics._dark_screen != null and coordinator.cinematics._dark_screen.color.a < 0.05, "actDeleteDarkScreen should fade the dark rect back out")
	_assert_eq(_records_of(summary, "screen_darken_clear").size(), 1, "the dark-screen clear is recorded")

	# Record-only kinds land in story_records with recorded_no_handler.
	for kind in ["player_undead_flag", "town_event_add", "earthquake"]:
		var records := _records_of(summary, kind)
		_assert_eq(records.size(), 1, "%s should be recorded once" % kind)
		if records.size() == 1:
			_assert_eq((records[0] as Dictionary).get("status"), "recorded_no_handler", "%s is record-only" % kind)
	var town := _records_of(summary, "town_event_add")
	if town.size() == 1:
		_assert_eq(((town[0] as Dictionary).get("params") as Dictionary).get("children"), [9], "record-only tokens keep their compiled params")
	_finish(scene)


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("OPENING_TOKEN_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("OPENING_TOKEN_TESTS_FAIL count=%d" % failures.size())
		quit(1)

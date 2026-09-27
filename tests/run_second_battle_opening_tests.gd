extends SceneTree

## Product-path opening for the level-52 scenario: the shared scene must start
## from the compiled STORY052 timeline through BattleOpeningCoordinator, play
## every token in source order and hand control to Leonard inside the same PlayLoop.

const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const Interaction = preload("res://game/sim/Interaction.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _run() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_052.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame

	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null, "second battle product opening should create BattleOpeningCoordinator")
	if coordinator == null:
		_finish(scene)
		return
	_assert_true(coordinator.active, "coordinator should be active right after startup")
	_assert_eq(scene.interaction_state, "opening_timeline", "product opening should block battle input while the STORY052 queue plays")
	_assert_eq(scene.runtime_entrypoint, "product_opening", "second battle should enter through the product opening entrypoint")
	_assert_eq(scene.opening_timeline_mode, "opening", "runtime timeline mode should report the running opening")
	_assert_eq(str(scene.scene_timeline.events[0].get("kind", "")), "background_object_target", "STORY052 starts on actSetBGToObject(SID_ENEMY025)")
	var first_camera: Array = coordinator.summary().get("camera_records", [])
	_assert_true(first_camera.size() >= 1 and str(first_camera[0].get("unit_id", "")) == "emperor025", "first camera record should target the emperor binding")
	_assert_true(not scene.action_menu.visible, "action menu must stay hidden during the opening")

	var boss = scene.get_node_or_null("World/Actors/ActorRuntime_emperor025")
	var boss_cell: Vector2i = scene.unit_grid_coord("emperor025")
	if boss != null:
		var boss_world: Vector2 = scene.camera_controller.grid_cell_center_world(boss_cell)
		_assert_true(boss.position.is_equal_approx(boss_world - Vector2(0, 96)), "the emperor should start 96px above his PlayLoop cell before actWalkDispWait(0,96)")
		_assert_true(scene.camera.position.distance_to(scene.camera_controller.clamped_position(boss.position + Vector2(0, 48))) < 1.0, "opening camera should frame the emperor where he stands (at the view's (320,192), 0x43bf30)")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	var leonard_cell: Vector2i = scene.unit_grid_coord("leonard")
	if leonard != null:
		var final_world: Vector2 = scene.camera_controller.grid_cell_center_world(leonard_cell)
		_assert_true(leonard.position.is_equal_approx(final_world + Vector2(0, 224)), "Leonard should start 224px below his PlayLoop cell before actWalkDispWait(0,-224)")
	var mage = scene.get_node_or_null("World/Actors/ActorRuntime_enemy026_1")
	if mage != null:
		var mage_final: Vector2 = scene.camera_controller.grid_cell_center_world(scene.unit_grid_coord("enemy026_1"))
		_assert_true(mage.position.is_equal_approx(mage_final - Vector2(0, 64)), "enemy026_1 accumulates both actWalkDispWait(0,32) tokens before its final cell")
	var guard = scene.get_node_or_null("World/Actors/ActorRuntime_enemy021_1")
	_assert_true(guard != null and not guard.visible, "scripted Enemy021 inserts must stay hidden until actInsertObject")

	# Explicit fast pacing for the headless run; token order and semantics are unchanged.
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	coordinator.title_seconds = 0.05

	var dialogue_speakers: Array[String] = []
	var dialogue_event_ids: Array[String] = []
	var guard_visible_after_insert := false
	var frames := 0
	while coordinator.active and frames < 3000:
		var current: Dictionary = coordinator.summary()
		var kind := str(current.get("current_event_kind", ""))
		if kind == "dialogue_message_id":
			_assert_true(scene.opening_overlay.visible, "dialogue token must show the shared dialogue board")
			var event_id := str(current.get("current_event_id", ""))
			if not dialogue_event_ids.has(event_id):
				dialogue_event_ids.append(event_id)
				dialogue_speakers.append(str(scene.opening_overlay.speaker_label.text))
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			coordinator.handle_input(click)
		if kind == "object_insert" and guard != null and guard.visible:
			guard_visible_after_insert = true
		await process_frame
		frames += 1

	_assert_true(not coordinator.active, "opening should finish within the bounded frame budget")
	_assert_eq(dialogue_speakers.size(), 12, "STORY052 opening should present twelve dialogue messages")
	if dialogue_speakers.size() >= 2:
		_assert_eq(dialogue_speakers[0], "帝國法師：", "first speaker label should be the remake mage label for SID_ENEMY026")
		_assert_eq(dialogue_speakers[1], "法蘭克：", "second speaker label should be the emperor's PLAYERS name")
	_assert_true(guard_visible_after_insert, "actInsertObject should reveal the bound Enemy021 actor")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq(int(final_summary.get("motion_count", 0)), 9 + 8 + 8, "nine actor walks, eight inserts and eight insert walks should be recorded")
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY052 token may be silently skipped")
	var sound_records: Array = final_summary.get("sound_records", [])
	_assert_eq(sound_records.size(), 1, "actPlaySound(CLIP001) is recorded once")
	if sound_records.size() == 1:
		_assert_eq(str((sound_records[0] as Dictionary).get("status", "")), "played", "the decoded CLIP001 resource should play through the coordinator's sound player")
	_assert_eq((final_summary.get("inserted_unit_ids", []) as Array).size(), 8, "all eight scripted Enemy021 inserts should bind to roster units")
	var tokens: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(tokens.get("win", []), ["0"], "actInsertWinStatus(0) should be registered")
	_assert_eq(tokens.get("fail", []), ["0"], "actInsertFailStatus(0) should be registered")
	_assert_eq(tokens.get("event", []), ["0", "1"], "both event statuses should be registered")
	_assert_eq(str((tokens.get("dead_message", {}) as Dictionary).get("message_id", "")), "394", "Leonard's STORY052 dead message should be registered")
	_assert_eq(scene.opening_timeline_mode, "first_control", "runtime should report first control after the opening")
	_assert_true(scene.interaction_state in ["ai_resolving", "action_menu"], "opening should hand off into the shared PlayLoop interaction")
	_assert_true(bool(scene.play_loop.get("battle_started", true)), "PlayLoop should have begun the battle")
	for unit_id in ["leonard", "ally023_1", "ally024_2", "enemy026_1", "enemy021_8", "emperor025"]:
		var actor = scene.get_node_or_null("World/Actors/" + ("ActorRuntimeLeonard" if unit_id == "leonard" else "ActorRuntime_%s" % unit_id))
		_assert_true(actor != null and actor.visible, "%s should be visible after the opening" % unit_id)
		if actor != null and not actor.is_moving():
			var expected: Vector2 = scene.camera_controller.grid_cell_center_world(scene.unit_grid_coord(unit_id))
			if scene.unit_grid_coord(unit_id) != Interaction.NO_CELL:
				_assert_true(actor.position.is_equal_approx(expected), "%s should stand on its PlayLoop cell after the opening" % unit_id)
	_assert_true(not scene.opening_overlay.visible, "dialogue board should be cleared at first control")
	await _check_reinforcement_entrance(scene, coordinator)
	_finish(scene)


func _check_reinforcement_entrance(scene: Node, coordinator: Node) -> void:
	## WINFAIL052 event 1 (fewer than two 021 alive) inserts four obj_Story_Level52_Enemy21:
	## ScriptActorCreationRules births them as script actor templates at the off-map insert
	## pixels and the event cutscene walks each one to its actWalkPrevInsertObjectWait cell —
	## the same path as every other level's reinforcements (no spawn-cell copy of the roster).
	var frames := 0
	while frames < 600 and (scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state != "action_menu"):
		await process_frame
		frames += 1
	var alive: Array = scene.play_loop["units"].filter(func(unit): return str(unit.get("class_id", "")) == "Enemy021" and int(unit.get("hp", 0)) > 0)
	for index in range(alive.size() - 1):
		scene.BattlePlayLoop._set_unit_defeated(scene.play_loop, str(alive[index]["id"]), true)
	scene.play_loop["turn"] = 2
	scene.apply_loop(scene.BattlePlayLoop._resolve_outcome(scene.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
	_assert_eq(scene.play_loop.get("event_statuses", []), [0], "event1 fires once and is consumed")
	_assert_eq(scene.BattleScenarioRuleAdapter.reinforcement_deficits(scene.play_loop), {}, "the four inserts are settled by ScriptActorCreationRules, nothing is owed to a spawn-cell policy")
	var transactions: Array = scene.play_loop.get("script_actor_transactions", [])
	_assert_eq(transactions.size(), 1, "event1 writes one script actor transaction")
	var recruits: Array = scene.play_loop["units"].filter(func(unit): return str(unit["id"]).begins_with("Enemy021_script_"))
	_assert_eq(recruits.size(), 4, "four Enemy021 recruits are created")
	var cells: Array = []
	for recruit in recruits:
		cells.append(recruit["coord"])
	_assert_eq(cells, [Vector2i(7, 38), Vector2i(12, 38), Vector2i(4, 30), Vector2i(14, 30)], "the recruits stand on the actWalkPrevInsertObjectWait cells (227,1228)/(403,1228)/(134,987)/(463,987)")
	# Sample walks from the frame the event fires: under a long real-clock frame or the fixed
	# clock a recruit's walk can start before cutscene_mode is raised.
	var seen_moving := {}
	var sample_moving := func() -> void:
		for recruit in recruits:
			var actor = scene.actor_node_for_unit(str(recruit["id"]))
			if actor != null and actor.is_moving():
				seen_moving[str(recruit["id"])] = true
	frames = 0
	while frames < 240 and not coordinator.cutscene_mode:
		sample_moving.call()
		await process_frame
		frames += 1
	_assert_true(coordinator.cutscene_mode and coordinator.cutscene_key == "event_1", "the fired event starts its cutscene at the next idle frame")
	frames = 0
	while frames < 3000 and coordinator.active:
		sample_moving.call()
		await process_frame
		frames += 1
	_assert_true(not coordinator.active, "the event1 cutscene finishes within the frame budget")
	_assert_eq(seen_moving.size(), 4, "every recruit walks in from its insert pixel (bottom edge 1356 / off-map -58 and 655)")
	var revealed: Array = coordinator.story_records.filter(func(record): return str(record.get("kind", "")) == "script_actor_revealed")
	_assert_eq(revealed.size(), 4, "the cutscene reveals each recruit at its actInsertObject token")
	frames = 0
	while frames < 600 and scene.has_actor_motion():
		await process_frame
		frames += 1
	for recruit in recruits:
		var actor = scene.actor_node_for_unit(str(recruit["id"]))
		var target: Vector2 = scene.camera_controller.grid_cell_center_world(recruit["coord"])
		_assert_true(actor != null and actor.visible and actor.position.is_equal_approx(target), "%s finishes on its PlayLoop cell %s" % [str(recruit["id"]), str(recruit["coord"])])


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	if failures.is_empty():
		print("SECOND_BATTLE_OPENING_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SECOND_BATTLE_OPENING_TESTS_FAIL count=%d" % failures.size())
		quit(1)

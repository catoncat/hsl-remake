extends SceneTree

const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

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
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame

	var summary: Dictionary = RuntimeReadback.runtime_contract_summary(scene)
	_assert_eq(summary.get("scenario_schema"), "hsl_level_battle.v1", "runtime should load the level-52 scenario through the same scene")
	_assert_eq(summary.get("runtime_entrypoint"), "dev_first_control_harness", "level-52 M2 should use the explicit dev first-control seam until opening is generalized")
	_assert_eq(summary.get("map_world_size"), Vector2i(640, 1280), "runtime should render the level-52 map dimensions")
	_assert_eq(summary.get("logical_viewport_size"), Vector2i(640, 480), "second battle should retain the shared logical viewport")
	_assert_eq(int(summary.get("actor_runtime_count", 0)), 18, "runtime should materialize the level-52 roster including the two 069 winged warriors")
	_assert_eq(int(summary.get("map_object_spawn_count", -1)), 23, "level-52 stand objects (lights, fires, shadows, pillars) should spawn from the promoted obj-052 manifest")
	_assert_eq(int(summary.get("scene_timeline_event_count", -1)), 58, "second battle should load the compiled STORY052 timeline (57 tokens + handoff marker), not the first-battle queue")
	_assert_eq(str(summary.get("opening_timeline_manifest_schema", "")), "hsl_first_scene_opening_timeline.v1", "compiled STORY052 timeline should use the shared opening timeline schema")
	_assert_eq(str(summary.get("message_text_status", "")), "resolved_from_resource_table", "level-52 dialogue text should come from the imported RESOURCE.TXT table")
	_assert_eq(str(summary.get("opening_timeline_mode", "")), "first_control", "dev first-control harness must still bypass the compiled opening until a scenario-driven coordinator exists")

	var loop: Dictionary = scene.play_loop
	_assert_true(bool(loop.get("scenario_ok", false)), "second battle should remain scenario-valid after runtime bootstrap")
	_assert_eq(loop.get("rule_adapter"), "winfail", "second battle runs on the data-driven winfail interpreter inside the same PlayLoop")
	_assert_eq(loop.get("map_size"), Vector2i(20, 40), "second battle should use the level-52 WRD grid")
	_assert_eq(str(loop.get("selected_unit_id", "")), "leonard", "dev first-control harness should settle the NPC prefix and hand off to Leonard")
	_assert_eq(str(loop.get("interaction", "")), "action_menu", "second battle should reach the shared player action-menu state")
	_assert_true((loop.get("last_ai_actions", []) as Array).size() > 0, "second battle should exercise the shared stepped AI path before Leonard")

	var boss = scene.get_node_or_null("World/Actors/ActorRuntime_emperor025")
	_assert_true(boss != null, "runtime should create the level-52 boss actor")
	if boss != null:
		var boss_summary: Dictionary = boss.runtime_summary()
		_assert_eq(int(boss_summary.get("manifest_frame_count", 0)), 37, "level-52 boss overworld animation should consume its SHAPEDEF-declared 37 frames")

	# The shared native menu now expands from the actor before accepting input.
	# Wait on real presentation time; this is not a level-specific bypass.
	await create_timer(0.25).timeout
	_assert_true(not scene.action_menu.is_expanding(), "second battle shares the completed menu expansion before clicks")
	var move_center: Vector2 = scene.scene_input.command_center_logical_position("move")
	_assert_true(move_center != Vector2.ZERO, "second battle should expose the shared Move command")
	if move_center != Vector2.ZERO:
		scene.scene_input.handle_pointer_left_pressed(move_center)
		scene.scene_input.handle_pointer_left_released(move_center)
		_assert_eq(scene.interaction_state, "move_select", "second battle Move should enter the shared move-selection state")
		_assert_true(scene.move_overlay_cells.size() > 1, "second battle Move should derive reachable cells from level-52 WRD")
		scene.scene_input.handle_pointer_cancel(Vector2(320, 240))
		_assert_eq(scene.interaction_state, "action_menu", "second battle cancel should return through the shared action menu")

	# Scenario story dialogue reaches the shared presentation through the rule adapter.
	var presentation = scene.get_node("BattlePresentation")
	var probe: Dictionary = scene.play_loop.duplicate(true)
	probe["last_attack"] = {"attacker_id": "leonard", "defender_id": "emperor025"}
	probe = RuleAdapter.run_event_hooks(probe, true)
	_assert_eq(probe.get("event_log", []), ["event_0"], "Leonard striking the emperor fires WINFAIL052 event0 through the adapter")
	presentation._queue_story_dialogue(probe)
	_assert_true(presentation.dialogue_active(), "event0 boss engagement should queue STORY052 dialogue")
	_assert_eq(presentation.current_message_id(), "392", "the emperor's engagement line should page first")
	presentation._update_dialogue_page()
	_assert_true(presentation.dialogue_view.visible, "the emperor's line should render with his portrait binding (speaker 382 -> actor 025)")
	_assert_eq(presentation._dialogue_messages.size(), 2, "rendering must not drop the emperor's line for a missing portrait binding")
	presentation._queue_story_dialogue(probe)
	_assert_eq(presentation._dialogue_messages.size(), 2, "re-queuing the same event must not duplicate its two messages")
	probe["battle_outcome"] = BattleOutcome.VICTORY_BOSS
	presentation._queue_story_dialogue(probe)
	_assert_eq(presentation._dialogue_messages.size(), 3, "victory should append Leonard's resource line 378 once")
	_assert_eq(str(presentation._dialogue_messages[2].get("message_id", "")), "378", "victory_boss should map to message 378")
	_assert_eq(str(presentation._dialogue_messages[2].get("text", "")), "拉爾斯帝國的時代結束了！！", "dialogue text should come from the level-52 resource table")
	var defeat_probe: Dictionary = scene.play_loop.duplicate(true)
	defeat_probe["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	presentation._queue_story_dialogue(defeat_probe)
	# 394 (STORY052 actSetDeadMessage) is Leonard's death word on the unit, spoken once at death by
	# BattleAftermath; the defeat result queues no line of its own.
	_assert_eq(presentation._dialogue_messages.size(), 3, "defeat_leonard queues no result-page repeat of the death word 394")
	_assert_true(presentation._shown_story_events.has("%s:378" % RuleAdapter.TERMINAL_DIALOGUE_KEY), "the victory line is paged once under the terminal dialogue key, not a per-level outcome table")

	scene.queue_free()
	await process_frame
	await process_frame
	# Match the established first-scene runner: allow stopped audio/resources to
	# leave the mixer before process exit so a zero exit cannot hide leak errors.
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	if failures.is_empty():
		print("SECOND_BATTLE_RUNTIME_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SECOND_BATTLE_RUNTIME_TESTS_FAIL count=%d" % failures.size())
		quit(1)

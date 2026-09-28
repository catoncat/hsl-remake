extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")

var failures: Array[String] = []


func _initialize() -> void:
	await _run_smoke()
	await process_frame
	# Drain the audio mixer's stopped voices after the queued scene destruction.
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	if failures.is_empty():
		print("BATTLE_SCENE_MAIN_PATH_SMOKE_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BATTLE_SCENE_MAIN_PATH_SMOKE_FAIL count=%d" % failures.size())
		quit(1)


func _run_smoke() -> void:
	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	if packed == null:
		_fail("BattleSceneRuntime scene should load as the main path")
		return

	var scene := packed.instantiate()
	if scene == null or not scene.get_script():
		_fail("BattleSceneRuntime scene should instantiate with its script loaded")
		return
	root.add_child(scene)
	await process_frame

	_assert_true(scene.opening_coordinator != null and scene.opening_coordinator.active, "main path should open through BattleOpeningCoordinator")
	var summary: Dictionary = RuntimeReadback.runtime_contract_summary(scene)
	_assert_eq(summary.get("runtime_entrypoint", ""), "product_opening", "main scene should not start in a dev harness")
	_assert_eq(summary.get("map_world_size", Vector2i.ZERO), Vector2i(768, 768), "main path should derive LEVEL51 world size from the texture")
	_assert_eq(summary.get("logical_viewport_size", Vector2i.ZERO), Vector2i(640, 480), "main path should keep the original 640x480 logical viewport")
	_assert_eq(summary.get("scenario_path", ""), "res://content/battles/battle_051.json", "main path should open the campaign's first battle")
	_assert_eq(int(summary.get("actor_runtime_count", 0)), 12, "main path should spawn all twelve level-51 actors")
	_assert_eq(int(summary.get("map_object_spawn_count", 0)), 10, "main path should spawn the ten map-object candidates")
	_assert_eq(int(summary.get("map_object_bridge_runtime_aligned_count", 0)), 2, "main path should runtime-align both bridge rail overlays from original evidence")
	_assert_eq(summary.get("message_text_status", ""), "resolved_from_resource_table", "main path should resolve original dialogue")

	if scene.has_method("interaction_summary"):
		var interaction: Dictionary = RuntimeReadback.interaction_summary(scene)
		_assert_eq(interaction.get("interaction_state", ""), "opening_timeline", "main path should start in opening mode")
		_assert_eq(interaction.get("action_menu_visible", true), false, "main path should not show the dev action menu at startup")
		_assert_eq(interaction.get("move_overlay_visible", true), false, "main path should not show Move overlay at startup")

	if scene.has_method("opening_timeline_summary"):
		var timeline: Dictionary = RuntimeReadback.opening_timeline_summary(scene)
		_assert_eq(timeline.get("mode", ""), "opening", "main path timeline should be opening")
		_assert_eq(timeline.get("current_event_kind", ""), "opening_music", "main path should begin at the STORY051 opening token")
		_assert_eq(timeline.get("first_control_playable", true), false, "main opening should suspend first-control input")

	_assert_eq(scene.opening_overlay.visible, false, "main opening should not show the dialogue board before its first message")
	_assert_no_visible_debug_text({"title_text": scene.opening_overlay.speaker_label.text, "detail_text": scene.opening_overlay.body_label.text, "meta_text": scene.opening_overlay.continue_label.text}, "main opening startup")
	var leonard = scene.actor_node_for_unit("leonard")
	_assert_true(leonard != null and scene.camera.position.distance_to(scene.camera_controller.clamped_position(leonard.position + Vector2(0, 48))) < 1.0, "main opening should frame Leonard where he stands before his walk (at the view's (320,192), 0x43bf30)")

	scene.queue_free()


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	failures.append(message)


func _assert_no_visible_debug_text(presentation: Dictionary, context: String) -> void:
	var combined := "%s\n%s\n%s" % [
		str(presentation.get("title_text", "")),
		str(presentation.get("detail_text", "")),
		str(presentation.get("meta_text", "")),
	]
	for token in ["Opening:", "source:", "status:", "not proof", "not proven", "evidence", "candidate", "runtime", "STORY051", "actPlay", "Status token"]:
		if combined.contains(token):
			_fail("%s visible UI leaked debug/evidence token: %s text=%s" % [context, token, combined])

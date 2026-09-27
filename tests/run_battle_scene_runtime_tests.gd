extends SceneTree
const GameOptions = preload("res://game/settings/GameOptions.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const MapObjectAnimation = preload("res://game/battle/runtime/MapObjectAnimation.gd")

const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const SceneTimeline = preload("res://game/battle/runtime/SceneTimeline.gd")
const MapObjectPlacement = preload("res://game/battle/runtime/MapObjectPlacement.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const run_position_equipment_tests = preload("res://tests/run_position_equipment_tests.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")

var failures: Array[String] = []


func _initialize() -> void:
	# A direct `--script` run gets the gate's seed (tools/verify_runner.py DEFAULT_RNG_SEED):
	# unseeded, the process global stream and the loop's damage stream start from the clock,
	# so the opening growth rolls (0x40e870) and with them the live-EXP and target-strip pins
	# drift run to run.
	if not OS.get_environment(GlobalRandomStream.SEED_ENV).is_valid_int():
		OS.set_environment(GlobalRandomStream.SEED_ENV, "1")
	await _run_all()
	# Let the audio mixer release the final scene's stopped voices before process exit;
	# wall clock because the gate runs this suite under --fixed-fps.
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("BATTLE_SCENE_RUNTIME_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BATTLE_SCENE_RUNTIME_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _run_all() -> void:
	_test_map_scene_uses_texture_world_size_and_spatial_gate()
	_test_map_object_placement_alignment_manifest()
	_test_grid_projection_round_trip_is_single_contract()
	_test_actor_runtime_consumes_real_walk_manifest_frames()
	await _test_battle_scene_runtime_scene_loads_with_camera_and_spatial_gate()
	await _test_battle_scene_select_move_cancel_loop()
	await _test_battle_scene_pointer_input_hit_test_loop()
	await _test_fire_animation_live_scene()
	await _test_walk_audio_cues()
	await _test_job_up_reconfigures_actor_frames()
	await _test_actor_depth_follows_visible_position()
	await _test_combat_feedback_once_per_exchange()
	await _test_result_presentation()
	await _test_status_inspection_no_turn_cost()
	await _test_attack_target_preview()
	await _test_move_select_identity_bar()
	await _test_combat_cutin_sequence()
	await _test_cutin_effect_anchors_and_reset()
	await _test_pending_combat_blocks_early_input()
	await _test_mage_magic()
	await _test_local_spell_layers()
	await _test_live_experience()
	await _test_growth_allocation_interaction()
	await _test_special_skill()
	await _test_recovery_item()
	await _test_camera_pan_spatial_contract()
	_test_stamina_builds_from_zero()
	_test_undead_survives_lethal_strike()
	await _test_priest_trial_scene()


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _assert_no_visible_debug_text(presentation: Dictionary, context: String) -> void:
	var combined := "%s\n%s\n%s" % [
		str(presentation.get("title_text", "")),
		str(presentation.get("detail_text", "")),
		str(presentation.get("meta_text", "")),
	]
	for token in ["Opening:", "source:", "status:", "not proof", "not proven", "evidence", "candidate", "runtime", "STORY051", "Status token", "actPlay", "actWalk", "Dialogue actor/message id order"]:
		if combined.contains(token):
			failures.append("%s visible UI leaked debug/evidence token: %s text=%s" % [context, token, combined])


func _test_map_scene_uses_texture_world_size_and_spatial_gate() -> void:
	var texture := _make_texture(Vector2i(768, 768))
	var config := MapSceneConfig.from_texture(
		"first_battle_scene",
		texture,
		Vector2i(640, 480),
		{
			"origin": Vector2(384.0, 256.0),
			"cell_size": Vector2(32.0, 32.0),
			"evidence_id": "move_overlay_primary",
			"evidence_tier": "runtime-measured",
			"provisional": true,
		}
	)
	_assert_eq(config.world_size, Vector2i(768, 768), "map world size should come from texture dimensions")
	_assert_eq(config.logical_viewport_size, Vector2i(640, 480), "map scene should keep original logical viewport")


func _test_map_object_placement_alignment_manifest() -> void:
	var manifest := _load_json("res://content/imported/hsl/chapter01/map_object_alignment.json")
	var resolver := MapObjectPlacement.from_alignment_manifest(manifest)
	var objects := _load_json("res://content/imported/hsl/chapter01/map_objects.json")
	var records: Array = objects.get("placements", [])
	var calibrated := {}
	for item in records:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = item
		var shape_id := str(record.get("shape_resource_id", ""))
		if shape_id != "bar004a.SHP" and shape_id != "bar004b.SHP":
			continue
		var texture: Texture2D = load("res://content/imported/hsl/shared/shape_previews/map_object/%s.png" % shape_id)
		var placement: Dictionary = resolver.resolve(record)
		calibrated[shape_id] = placement
	_assert_eq(calibrated["bar004b.SHP"]["top_left_world"], Vector2(392, 212), "Native bridge anchor must preserve the previously measured image location")
	_assert_eq(calibrated["bar004a.SHP"]["top_left_world"], Vector2(230, 232), "Removing the bridge override must preserve its rendered location")
	var tree: Dictionary = resolver.resolve({"record_index": 15, "shape_resource_id": "tree07.SHP", "candidate_x": 288, "candidate_y": 576})
	_assert_eq(tree["top_left_world"], Vector2(149, 351), "Tree origin is inside the image, not at its bottom edge")
	_assert_eq(calibrated.get("bar004b.SHP", {}).get("render_anchor_world", Vector2.ZERO), Vector2(402.0, 256.0), "bar004b should align to the original upper bridge rail bbox under the upper bridge camera crop")
	_assert_eq(calibrated.get("bar004a.SHP", {}).get("render_anchor_world", Vector2.ZERO), Vector2(385.0, 403.0), "bar004a should align to the original lower bridge rail bbox under the upper bridge camera crop")


func _test_grid_projection_round_trip_is_single_contract() -> void:
	var texture := _make_texture(Vector2i(1024, 768))
	var config := MapSceneConfig.from_texture(
		"non_square_map_probe",
		texture,
		Vector2i(640, 480),
		{
			"origin": Vector2(100.0, 80.0),
			"cell_size": Vector2(32.0, 32.0),
			"evidence_id": "move_overlay_primary",
			"evidence_tier": "runtime-measured",
			"provisional": true,
		}
	)
	var world: Vector2 = config.grid_to_world(Vector2i(3, 4))
	_assert_eq(world, Vector2(196.0, 208.0), "grid_to_world should use one map-scene projection contract")
	_assert_eq(config.world_to_grid(world + Vector2(8.0, 8.0)), Vector2i(3, 4), "world_to_grid should use the same projection contract")
	_assert_eq(config.world_size, Vector2i(1024, 768), "projection code must not bake LEVEL51 768x768 as a global constant")


func _test_actor_runtime_consumes_real_walk_manifest_frames() -> void:
	var manifest := _load_json("res://content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json")
	var actor_entry: Dictionary = manifest.get("actors", {}).get("001", {})
	var actor := ActorRuntime.new()
	actor.configure_from_manifest("leonard", actor_entry)
	actor.play_state("idle", "0")
	var summary: Dictionary = actor.runtime_summary()
	_assert_eq(summary.get("frame_source_status", ""), "manifest_frame_sequence", "ActorRuntime should consume manifest frame sequences")
	_assert_eq(int(summary.get("manifest_frame_count", 0)), 30, "ActorRuntime should load all 30 Leonard walk frames")
	_assert_eq(int(summary.get("animation_frame_count", 0)), 6, "ActorRuntime should expose six frames for one facing walk sequence")
	_assert_true(str(summary.get("current_frame_source", "")).ends_with("001-00001.png"), "ActorRuntime should start facing 0 walk on pose 1")
	_assert_eq(actor.get_node("Sprite2D").position, Vector2(-11, -49), "Leonard frame must subtract its original SHP anchor, not half the image")
	actor.advance_animation_frame()
	_assert_eq(actor.get_node("Sprite2D").position, Vector2(-10, -49), "Changing pose must apply its own SHP origin")
	var advanced: Dictionary = actor.runtime_summary()
	_assert_true(str(advanced.get("current_frame_source", "")).ends_with("001-00002.png"), "ActorRuntime should advance to the next real walk frame")
	actor.play_state("walk", "up")
	_assert_true(str(actor.runtime_summary().get("current_frame_source", "")).ends_with("001-30001.png"), "SHAPEDEF walk_up must use source group 3")
	actor.free()


func _test_battle_scene_runtime_scene_loads_with_camera_and_spatial_gate() -> void:
	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	_assert_true(packed != null, "BattleSceneRuntime scene should load")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	scene.set_process(false) # Inspect the boot contract before any autoplay clock tick.
	await process_frame
	if scene.has_method("apply_loop"):
		var summary: Dictionary = RuntimeReadback.runtime_contract_summary(scene)
		_assert_eq(summary.get("startup_mode", ""), "product_opening", "BattleSceneRuntime main scene should default to the product opening path")
		_assert_eq(summary.get("runtime_entrypoint", ""), "product_opening", "BattleSceneRuntime should not boot into a dev harness")
		_assert_eq(summary.get("product_main_path_state", ""), "opening_timeline", "product main path should start with the opening timeline")
		_assert_eq(summary.get("map_world_size", Vector2i.ZERO), Vector2i(768, 768), "BattleSceneRuntime should derive world size from LEVEL51 texture")
		_assert_eq(summary.get("logical_viewport_size", Vector2i.ZERO), Vector2i(640, 480), "BattleSceneRuntime should keep 640x480 logical viewport")
		_assert_eq(summary.get("scenario_path", ""), "res://content/battles/battle_051.json", "the scene launched directly opens the campaign's first battle")
		_assert_eq(int(summary.get("actor_runtime_count", 0)), 12, "BattleSceneRuntime should spawn all original level-51 actors through ActorRuntime")
		_assert_true(scene.actor_node_for_unit("leonard").get_node("WalkAudio").stream.resource_path.ends_with("walk0011.wav"), "Live soldier actor must load its table-bound walking sound")
		_assert_true(scene.actor_node_for_unit("actor024_1").get_node("WalkAudio").stream.resource_path.ends_with("walk0012.wav"), "Live beast actor must use its distinct walking sound")
		_assert_eq(int(summary.get("map_object_source_count", 0)), 10, "BattleSceneRuntime should see the ten first-battle stand objects")
		_assert_eq(int(summary.get("map_object_spawn_count", 0)), 10, "BattleSceneRuntime should spawn all ten map objects")
		_assert_eq(summary.get("scene_timeline_current_event_id", ""), "story051_00_opening_music", "BattleSceneRuntime should start with the product opening event")
		_assert_eq(int(summary.get("opening_timeline_event_count", 0)), 20, "BattleSceneRuntime should expose all compiled STORY051 opening events plus handoff marker")
		_assert_eq(summary.get("opening_timeline_mode", ""), "opening", "BattleSceneRuntime should default to product opening mode")
		_assert_eq(summary.get("message_text_status", ""), "resolved_from_resource_table", "BattleSceneRuntime should resolve original resource dialogue")
		_assert_true(scene.opening_coordinator != null and scene.opening_coordinator.active, "the first battle opens through BattleOpeningCoordinator like every other level")
		_assert_eq(int(summary.get("leonard_animation_frame_count", 0)), 6, "BattleSceneRuntime stand sequence must preserve six SHAPEDEF frames")
		var actor_unit_ids: Array = summary.get("actor_unit_ids", [])
		for unit_id in ["leonard", "actor021_1", "actor026_1", "actor023_1", "actor024_1"]:
			_assert_true(actor_unit_ids.has(unit_id), "BattleSceneRuntime should spawn %s from the first-scene unit contract" % unit_id)
			_assert_eq(summary.get("actor_frame_source_statuses", {}).get(unit_id, ""), "manifest_frame_sequence", "%s should use real manifest frames" % unit_id)
	var object_summary: Dictionary = RuntimeReadback.map_object_summary(scene)
	_assert_eq(object_summary.get("shape_counts", {}).get("tree07.SHP", 0), 6, "map object summary should count six tree07 stand objects")
	_assert_eq(object_summary.get("shape_counts", {}).get("FIRE01-01.SHP", 0), 2, "map object summary should count two fire stand objects")
	_assert_eq(object_summary.get("shape_counts", {}).get("bar004a.SHP", 0), 1, "map object summary should count bridge bar004a")
	_assert_eq(object_summary.get("shape_counts", {}).get("bar004b.SHP", 0), 1, "map object summary should count bridge bar004b")
	_assert_eq(int(object_summary.get("back_count", -1)), 0, "map object summary should report no current back-layer stand objects")
	_assert_eq(object_summary.get("bridge_runtime_aligned_candidates", []), ["8:bar004b.SHP", "13:bar004a.SHP"], "map object summary should identify both aligned bridge rail records")
	var bridge_records := {}
	for record_item in object_summary.get("records", []):
		if typeof(record_item) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_item
		var shape_id := str(record.get("shape_resource_id", ""))
		if shape_id == "bar004a.SHP" or shape_id == "bar004b.SHP":
			bridge_records[shape_id] = record
	_assert_eq(bridge_records.get("bar004b.SHP", {}).get("candidate_anchor_world", Vector2.ZERO), Vector2(402.0, 256.0), "bar004b should preserve raw EVEF candidate anchor")
	_assert_eq(bridge_records.get("bar004b.SHP", {}).get("render_anchor_world", Vector2.ZERO), Vector2(402.0, 256.0), "bar004b should render from runtime-measured bridge alignment")
	_assert_eq(bridge_records.get("bar004a.SHP", {}).get("candidate_anchor_world", Vector2.ZERO), Vector2(385.0, 403.0), "bar004a should preserve raw EVEF candidate anchor")
	_assert_eq(bridge_records.get("bar004a.SHP", {}).get("render_anchor_world", Vector2.ZERO), Vector2(385.0, 403.0), "bar004a should render from runtime-measured bridge alignment")
	var foreground_layer := scene.get_node_or_null("World/MapObjectsForeground")
	_assert_true(foreground_layer != null, "BattleSceneRuntime should include a foreground map object layer")
	if foreground_layer != null:
		_assert_eq(foreground_layer.get_child_count(), 10, "foreground map object layer should contain the ten spawned stand objects")
	var world := scene.get_node_or_null("World")
	_assert_true(world != null, "BattleSceneRuntime should include a World node for draw-order assertions")
	if world != null:
		var expected_world_order := ["MapBackdrop", "MapObjectsBack", "MoveOverlay", "Actors", "MapObjectsForeground"]
		_assert_eq(world.get_child_count(), expected_world_order.size(), "World should keep the current explicit draw-order layer set")
		for index in range(expected_world_order.size()):
			_assert_eq(str(world.get_child(index).name), expected_world_order[index], "World child draw order should keep %s at index %d" % [expected_world_order[index], index])
	scene.queue_free()
	await process_frame


func _test_battle_scene_select_move_cancel_loop() -> void:
	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	if scene.has_method("start_dev_first_control_harness"):
		scene.call("start_dev_first_control_harness")
		await process_frame

	scene.call("select_actor", "leonard")
	var initial_grid: Vector2i = scene.call("unit_grid_coord", "leonard")
	var target_grid := initial_grid + Vector2i(1, 0)
	var selected_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(selected_summary.get("interaction_state", ""), "action_menu", "selecting Leonard should open the action menu")
	_assert_eq(selected_summary.get("selected_unit_id", ""), "leonard", "selection should retain Leonard as selected")
	_assert_eq(selected_summary.get("action_menu_visible", false), true, "selection should make action menu visible")
	_assert_eq(selected_summary.get("play_loop", {}).get("command_ids", []), ["move", "attack", "item", "wait", "status", "special"], "product action menu must expose implemented Status and Item")
	_assert_eq(selected_summary.get("play_loop", {}).get("terrain_ok", false), true, "play loop should load WRD terrain tiles")
	_assert_true(int(selected_summary.get("play_loop", {}).get("terrain_blocking_count", 0)) > 0, "WRD terrain should report blocking cells")

	scene.menus.choose_command("move")
	var move_select_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(move_select_summary.get("interaction_state", ""), "move_select", "Move command should enter move selection")
	_assert_eq(move_select_summary.get("move_overlay_visible", false), true, "Move command should show movement overlay state")
	_assert_eq(int(move_select_summary.get("move_overlay_move_point", 0)), 5, "Move overlay should use Leonard's static-derived move_point=5 candidate")
	_assert_true(int(move_select_summary.get("move_overlay_cell_count", 0)) > 0, "Move overlay should create WRD-reachable cells")
	_assert_true(int(move_select_summary.get("move_overlay_cell_count", 0)) < 61, "WRD blocking should shrink the old Manhattan diamond")

	scene.call("cancel_current_interaction")
	var canceled_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(canceled_summary.get("interaction_state", ""), "action_menu", "cancel from move selection should return to action menu")
	_assert_eq(canceled_summary.get("move_overlay_visible", true), false, "cancel should clear movement overlay state")

	scene.menus.choose_command("move")
	scene.call("move_selected_actor_to_grid", target_grid)
	var post_move_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(post_move_summary.get("interaction_state", ""), "action_menu", "executed move should return to post-move action menu")
	_assert_eq(post_move_summary.get("pending_move_revert", false), true, "executed move should create pending move revert")
	_assert_eq(post_move_summary.get("selected_grid_coord", Vector2i.ZERO), target_grid, "move should update selected actor grid coord")
	_assert_true(float(post_move_summary.get("last_move_duration_seconds", 0.0)) > 0.0, "move should use a non-zero presentation duration instead of instant teleport")
	_assert_true(bool(post_move_summary.get("last_move_uses_frame_sequence", false)), "move should present with a multi-frame walk sequence")
	_assert_true(int(post_move_summary.get("last_move_animation_frame_count", 0)) >= 6, "move should expose the six-frame walk sequence for one facing")

	scene.call("cancel_pending_move")
	var reverted_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(reverted_summary.get("selected_grid_coord", Vector2i.ZERO), initial_grid, "pending move cancel should restore original grid coord")
	_assert_eq(reverted_summary.get("pending_move_revert", true), false, "pending move cancel should clear pending revert")
	_assert_eq(reverted_summary.get("interaction_state", ""), "move_select", "pending move cancel should reopen movement selection")
	_assert_true(reverted_summary.get("move_overlay_visible", false), "restored position displays a fresh movement envelope")
	scene.queue_free()
	await process_frame


func _test_battle_scene_pointer_input_hit_test_loop() -> void:
	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	if scene.has_method("start_dev_first_control_harness"):
		scene.call("start_dev_first_control_harness")
		await process_frame
	if not scene.has_method("grid_cell_center_to_logical_position") or not scene.scene_input.has_method("command_id_for_control") or not scene.has_method("unit_grid_coord"):
		scene.queue_free()
		await process_frame
		return

	var initial_grid: Vector2i = scene.call("unit_grid_coord", "leonard")
	var target_grid := initial_grid + Vector2i(1, 0)
	_assert_eq(scene.actor_node_for_unit("leonard").position, Vector2(496, 560), "Skipping opening must place the visible actor at the native script destination")
	var leonard_click: Vector2 = scene.call("grid_cell_center_to_logical_position", initial_grid)
	_dispatch_mouse_button(scene, leonard_click, MOUSE_BUTTON_LEFT, true)
	var selected_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	var selected_input: Dictionary = RuntimeReadback.input_summary(scene)
	_assert_eq(selected_summary.get("interaction_state", ""), "action_menu", "left-clicking Leonard through _input should open the action menu")
	_assert_eq(selected_summary.get("selected_unit_id", ""), "leonard", "input hit-test should select Leonard")
	_assert_eq(selected_input.get("hovered_grid_cell", Vector2i.ZERO), initial_grid, "input summary should report Leonard's grid cell")
	_assert_eq(selected_input.get("hovered_unit_id", ""), "leonard", "input summary should report the hit actor")

	_assert_true(scene.action_menu.is_expanding(), "new selection must expose the native menu opening before accepting commands")
	scene.action_menu._process(0.25)
	var move_command_click: Vector2 = RuntimeReadback.command_center_logical_position(scene.scene_input, "move")
	_dispatch_mouse_button(scene, move_command_click, MOUSE_BUTTON_LEFT, true)
	var command_down_input: Dictionary = RuntimeReadback.input_summary(scene)
	_assert_eq(command_down_input.get("held_command_id", ""), "move", "left press on Move command should hold the command until release")
	_assert_eq(command_down_input.get("hovered_command_id", ""), "move", "command hit-test should report Move")
	_dispatch_mouse_button(scene, move_command_click, MOUSE_BUTTON_LEFT, false)
	_assert_true(scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("interface_audio/confirm.wav"), "releasing an enabled command must play original accept sound")
	var move_select_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(move_select_summary.get("interaction_state", ""), "move_select", "left release on held Move should enter move selection")
	_assert_eq(move_select_summary.get("move_overlay_visible", false), true, "_input Move command should show the movement overlay")

	var target_click: Vector2 = scene.call("grid_cell_center_to_logical_position", target_grid)
	_dispatch_mouse_button(scene, target_click, MOUSE_BUTTON_LEFT, true)
	var post_move_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	var post_move_input: Dictionary = RuntimeReadback.input_summary(scene)
	_assert_eq(post_move_summary.get("interaction_state", ""), "action_menu", "left-clicking a highlighted target cell should execute the move")
	_assert_eq(post_move_summary.get("selected_grid_coord", Vector2i.ZERO), target_grid, "input move should update Leonard's grid coord")
	_assert_eq(post_move_summary.get("pending_move_revert", false), true, "input move should create a rollback slot")
	_assert_true(float(post_move_summary.get("last_move_duration_seconds", 0.0)) > 0.0, "input move should use a non-zero presentation duration")
	_assert_true(bool(post_move_summary.get("last_move_uses_frame_sequence", false)), "input move should use real walk frame sequence presentation")
	_assert_eq(post_move_input.get("hovered_grid_cell", Vector2i.ZERO), target_grid, "target hit-test should report the clicked grid cell")

	_dispatch_mouse_button(scene, target_click, MOUSE_BUTTON_RIGHT, true)
	var reverted_summary: Dictionary = RuntimeReadback.interaction_summary(scene)
	_assert_eq(reverted_summary.get("selected_grid_coord", Vector2i.ZERO), initial_grid, "right-click after move should cancel pending move through _input")
	_assert_eq(reverted_summary.get("pending_move_revert", true), false, "right-click cancel should clear pending move rollback")
	scene.queue_free()
	await process_frame


func _make_texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	return ImageTexture.create_from_image(image)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _dispatch_mouse_button(scene: Node, logical_position: Vector2, button_index: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = pressed
	event.position = RuntimeReadback.logical_to_viewport_position(scene, logical_position)
	scene.call("_input", event)


func _dispatch_key(scene: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	scene.call("_input", event)


func _test_fire_animation_live_scene() -> void:
	var scene: Node = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var count := 0
	for sprite in scene.get_node("World/MapObjectsForeground").get_children():
		if not sprite is MapObjectAnimation:
			continue
		count += 1
		sprite.set_process(false)
		sprite.elapsed = 0.0
		var start: int = sprite.frame_index
		var anchor: Vector2 = sprite.position
		_assert_eq(sprite.frames.size(), 10, "Both gate fires must use the complete source sequence")
		_assert_eq(sprite.scale, Vector2(0.625, 0.625), "Fire zoom must apply around its source anchor")
		sprite._process(sprite.frame_seconds * 0.5)
		_assert_eq(sprite.frame_index, start, "Fire must not change frame before the configured delay")
		sprite._process(sprite.frame_seconds * 0.6)
		_assert_eq(sprite.frame_index, (start + 1) % 10, "Fire must actually advance its displayed frame")
		_assert_eq(sprite.texture, sprite.textures[sprite.frame_index], "Advanced fire frame must reach the visible texture")
		sprite._process(sprite.frame_seconds * 9.0)
		_assert_eq(sprite.frame_index, start, "The ten-frame fire sequence must loop")
		_assert_eq(sprite.position, anchor, "Changing fire frames must not move its world anchor")
	_assert_eq(count, 2, "Both original gate fires must be animated in the live scene")
	scene.queue_free()
	await process_frame


func _test_walk_audio_cues() -> void:
	var manifest: Dictionary = _load_json("res://content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json")
	var actor := ActorRuntime.new()
	actor.configure_from_manifest("leonard", manifest["actors"]["001"])
	actor.configure_walk_audio("res://content/imported/hsl/chapter01/audio_normalized/walk0011.wav")
	root.add_child(actor)
	await process_frame
	var sound: AudioStreamPlayer = actor.get_node("WalkAudio")
	actor.move_along([Vector2(32, 0), Vector2(32, 32)], 0.2)
	actor._motion_tween.pause()
	actor._frame_tween.pause()
	_assert_true(not sound.playing, "Battle footsteps must not play before displacement")
	actor._motion_tween.custom_step(0.05)
	_assert_true(not sound.playing, "Half a cell must not emit a whole-step cue")
	actor._motion_tween.custom_step(0.06)
	_assert_true(sound.playing, "First completed cell must play the imported footstep")
	sound.stop()
	actor._motion_tween.custom_step(0.1)
	_assert_true(sound.playing, "Last cell must emit a cue even when returning to idle")
	actor.move_along([Vector2.ZERO], 0.0)
	_assert_true(not sound.playing, "Instant cancellation/teleport must stop sound without adding footsteps")
	actor.move_along([Vector2(0, -96)], 0.8, true)
	actor._motion_tween.pause()
	actor._frame_tween.pause()
	_assert_true(sound.playing, "Scripted walking begins its frame-zero cue")
	sound.stop()
	actor.advance_animation_frame()
	actor.advance_animation_frame()
	_assert_true(not sound.playing, "Scripted frames one and two must not repeat the cue")
	actor.advance_animation_frame()
	_assert_true(sound.playing, "Scripted frame three emits the second cue")
	actor.move_along([Vector2.ZERO], 0.0)
	actor.advance_animation_frame()
	_assert_true(not sound.playing, "Stopped movement must not leave a scripted sound schedule")
	actor.queue_free()
	# AudioServer releases stopped voices asynchronously on its mixer thread.
	await create_timer(0.1).timeout


## actPlayerJobUpProcess (level 37: 咕嚕 008 → 017) rewrites the PlayLoop unit's actor
## row after its node exists. Before this contract the node kept whatever frames it was
## spawned with (headless observation: ActorRuntime.actor_id stayed on the base row,
## frames never reloaded). Now the next _sync_from_play_loop reloads the frames from the
## shared up-title manifest and rebinds the walk sound from the shared job-up audio
## manifest (0x4348f0 copies the target row's sound fields); the same seam serves a
## replayed town job-up.
func _test_job_up_reconfigures_actor_frames() -> void:
	var JobUpRules = preload("res://game/sim/JobUpRules.gd")
	var Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	var scene := packed.instantiate()
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	var before: Dictionary = RuntimeReadback.runtime_contract_summary(scene)
	_assert_eq(int(before.get("shared_actor_walk_manifest_actor_count", 0)), 11, "runtime loads the shared up-title walk manifest (010–017/019/020 + 052)")
	_assert_eq(before.get("actor_frame_actor_ids", {}).get("leonard", ""), "001", "before the job-up Leonard shows his base 001 frames")
	var unit: Dictionary = Loop.unit_ref(scene.play_loop, "leonard")  # live reference, as the winfail interpreter mutates it
	var applied := JobUpRules.merge_source_template(unit, JobUpRules.load_source_template("017"), JobUpRules.NATIVE_JOB_UP_FLAG)
	_assert_true(bool(applied.get("ok", false)), "the 017 template merges onto a live unit (%s)" % str(applied.get("reason", "")))
	unit.merge(applied["actor"], true)
	_assert_eq([str(unit["actor_id"]), str(unit["job_up_target_actor_id"])], ["001", "017"], "the in-battle job-up keeps the actor id and records the target row like the town job-up")
	scene.apply_loop(scene.play_loop, "test")
	var actor: Node = scene.actor_node_for_unit("leonard")
	var summary: Dictionary = actor.runtime_summary()
	_assert_eq(str(summary.get("actor_id", "")), "017", "after actPlayerJobUpProcess the node shows the 017 row")
	_assert_eq(str(summary.get("frame_source_status", "")), "manifest_frame_sequence", "017 frames come from a manifest, not the single-frame fallback")
	_assert_eq(int(summary.get("manifest_frame_count", 0)), 30, "017 carries its full SHAPEDEF five-group frame set")
	_assert_true(str(summary.get("current_frame_source", "")).begins_with("res://content/imported/hsl/shared/actor_walk_frames/017/"), "017 frames are served from the shared up-title directory (%s)" % str(summary.get("current_frame_source", "")))
	_assert_eq(str(summary.get("animation_state", "")), "idle", "the reconfigured node stands idle at its position")
	_assert_true(actor.get_node("WalkAudio").stream.resource_path.ends_with("shared/actor_audio/fly002.wav"), "the walk sound follows the target row: 017 FLY002 from the shared job-up audio manifest (%s)" % actor.get_node("WalkAudio").stream.resource_path)
	var presentation: Node = scene.get_node("BattlePresentation")
	_assert_true(ActorSpriteKey.audio_binding(unit, "attack", [presentation.audio_manifest, presentation.shared_audio_manifest]).ends_with("shared/actor_audio/attack20.wav"), "the attack sound follows the target row too (017 ATTACK20)")
	_assert_true(ActorSpriteKey.audio_binding({"id": "x", "actor_id": "001"}, "walk", [presentation.audio_manifest, presentation.shared_audio_manifest]).ends_with("walk0011.wav"), "a member without job-up keeps the level manifest's base-row sound")
	_assert_true(ActorSpriteKey.audio_binding({"id": "x", "actor_id": "003", "job_up_target_actor_id": "012"}, "attack", [presentation.audio_manifest, presentation.shared_audio_manifest]).ends_with("attack09.wav"), "012 declares the same ATTACK09 as 003: the binding resolves through the shared manifest to the same file")
	scene.apply_loop(scene.play_loop, "test")
	_assert_eq(str(actor.runtime_summary().get("actor_id", "")), "017", "a second sync is a no-op (frames are reloaded only when the row changes)")
	# The attack cut-in follows the same row rule on the live unit, from the same combat manifest every level shares.
	var cutin: Node = presentation.cutin
	_assert_eq(cutin.art_key(unit), "017", "after the job-up the live unit cuts in with the 017 frames")
	_assert_eq(str(cutin.manifest["actors"]["017"]["frames"][0]["source_member"]), "ANIMAL\\P017_001.SHP", "017 cut-in frames are the P017 strip")
	_assert_true(cutin.manifest["actors"]["052"].has("frames") and cutin.manifest["actors"]["052"]["special_frames"] == [], "052 (the guardian「???」) keeps its own imported cut-in frames and declares no s_shape strip ([])")
	# A town job-up target without imported frames (018: SHAPEDEF row commented out) keeps the base frames.
	var claudie_like := {"id": "leonard", "actor_id": "009", "job_up_target_actor_id": "018"}
	_assert_eq(scene.stage.frame_key_for_unit(claudie_like), "009", "018 has no imported frames: the member keeps its 009 base sprite")
	_assert_eq(scene.stage.frame_key_for_unit({"id": "x", "actor_id": "001", "job_up_target_actor_id": "010"}), "010", "010 resolves to the shared up-title frames")
	_assert_eq(scene.stage.frame_key_for_unit({"id": "x", "actor_id": "001"}), "001", "a member without job-up keeps its own row")
	scene.queue_free()
	await process_frame
	await process_frame


func _test_actor_depth_follows_visible_position() -> void:
	var actor := ActorRuntime.new()
	root.add_child(actor)
	actor.position = Vector2(288, 540)
	actor._process(0)
	_assert_true(actor.z_index < 576, "actor behind a tree must remain behind its anchor depth")
	actor.move_along([Vector2(288, 604)], 0.4)
	actor._motion_tween.pause()
	actor._motion_tween.custom_step(0.3)
	actor._process(0)
	_assert_true(actor.z_index > 576, "walking in front of the tree must update draw depth before arrival")
	actor.queue_free()
	# A flyer's depth is 10 rows deeper (original 0x43f31e／0x443849): standing one row
	# north of the tree anchor it draws over the tree; the ablation (ground) stays behind.
	var flyer := ActorRuntime.new()
	root.add_child(flyer)
	flyer.position = Vector2(288, 540)
	flyer.flying_depth = true
	flyer._process(0)
	_assert_eq(flyer.z_index, 540 + ActorRuntime.FLYING_DEPTH_ROWS * 32, "a flying actor draws 10 rows deeper")
	_assert_true(flyer.z_index > 576 and ActorRuntime.depth_index(540, false) < 576, "a flyer north of the tree draws over it, a walker behind it")
	flyer.queue_free()
	await process_frame


func _test_combat_feedback_once_per_exchange() -> void:
	var scene: Node = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	for enemy in scene.play_loop.units:
		if enemy.id == "actor021_1":
			enemy.coord = player.coord + Vector2i.LEFT
			enemy.hp = 100
			enemy.max_hp = 100
			# This fixture isolates single-strike label deduplication. Independent
			# counter clip ordering is covered by the pending-input/handoff suites.
			enemy.combat_profile.attack_back = 0
	scene.apply_loop(scene.play_loop, "test")
	scene.select_actor("leonard")
	scene.menus.choose_command("attack")
	scene.apply_loop(scene.BattlePlayLoop.attack_target(scene.play_loop, "actor021_1", func(_n: int) -> int: return 0), "test")
	scene.finish_attack_attempt()
	_assert_true(not scene.get_node("World/MoveOverlay").visible, "Completed attacks must clear visible targeting cells")
	var presentation: Node = scene.get_node("BattlePresentation")
	presentation.refresh(scene.play_loop, scene.map_config, true, false)
	_assert_eq(_damage_labels(presentation).size(), 0, "Move-then-attack feedback must wait for movement to finish")
	presentation.refresh(scene.play_loop, scene.map_config, true)
	presentation.cutin.set_process(false)
	_assert_eq(_damage_labels(presentation).size(), 0, "Damage feedback must wait for the strike frame")
	presentation.refresh(scene.play_loop, scene.map_config, true, true, presentation.attack_cue.duration)
	_seek_ordinary(presentation.cutin, "impact")
	_assert_eq(_damage_labels(presentation).size(), 1, "A resolved exchange must create visible damage at the target")
	_assert_eq(_damage_labels(presentation)[0].text, "", "the damage label carries no words beside the digits, critical or not (UI6 照原版纯数字): the number is the digits node")
	var damage_digits: Node = _damage_labels(presentation)[0].get_parent().get_node_or_null("DamageDigits")
	_assert_true(damage_digits != null and damage_digits.digits == "%d" % scene.play_loop.last_combat.actual_damage, "the map damage number shows the capped HP loss in the NUM1xx glyphs without a sign glyph")
	presentation.refresh(scene.play_loop, scene.map_config, true)
	_assert_eq(_damage_labels(presentation).size(), 1, "Frame refresh must not replay the same strike")
	_seek_ordinary(presentation.cutin, "complete")
	presentation.refresh(scene.play_loop, scene.map_config, true)
	presentation.refresh(scene.play_loop, scene.map_config, true, true, presentation.aftermath.REWARD_SECONDS)
	var missed: Dictionary = scene.play_loop.duplicate(true)
	missed.last_combat.sequence = 2
	missed.last_combat.hit = false
	missed.last_combat.damage = 0
	missed.last_combat.actual_damage = 0
	missed.last_combat.critical = false
	missed.last_combat.counter = {}
	missed.last_combat.defender_hp_before = scene.BattlePlayLoop.unit(missed,"actor021_1")["hp"]
	missed.last_combat.defender_hp_after = missed.last_combat.defender_hp_before
	missed.last_combat.erase("experience")
	presentation.refresh(missed, scene.map_config, true)
	presentation.refresh(missed, scene.map_config, true, true, presentation.attack_cue.duration)
	_seek_ordinary(presentation.cutin, "impact")
	_assert_eq(_damage_labels(presentation).size(), 2, "A new exchange must play even against the same target")
	_assert_eq(_damage_labels(presentation)[1].text, "", "a miss has no font word beside its glyph, not 閃避 (UI6)")
	var miss_glyph: Node = _damage_labels(presentation)[1].get_parent().get_node_or_null("MissGlyph")
	_assert_true(miss_glyph != null and miss_glyph.text == "MISS" and miss_glyph.kind == "miss", "a miss draws the NUM513 MISS glyph (kind 5)")
	_seek_ordinary(presentation.cutin, "complete")
	# One-shot players free themselves on AudioStreamPlayer.finished, which follows the
	# audio mixer's wall clock, not the process step: wait real seconds (the label tweens
	# run on process frames and complete within the same spin under either clock).
	await TestSuite.settle_wall_clock(self, 1.1)
	_assert_eq(_damage_labels(presentation).size(), 0, "Transient combat labels must remove themselves after playback")
	for child in presentation.get_children():
		_assert_true(not child is AudioStreamPlayer, "Completed one-shot sounds must release their player nodes")
	scene.queue_free()
	await create_timer(0.1).timeout


func _damage_labels(presentation: Node) -> Array:
	var labels: Array = []
	for child in presentation.get_children():
		var label := child.get_node_or_null("Damage")
		if label != null:
			labels.append(label)
	return labels


func _test_result_presentation() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var presentation = scene.get_node("BattlePresentation")
	scene.play_loop["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	scene._process(0.0)
	# The death word (304) is spoken once, at death, by BattleAftermath under the busy
	# gate; the defeat result adds no line of its own (the original has no result-page reader).
	_assert_true(not presentation.dialogue_active(), "defeat adds no result-page repeat of the death word")
	_assert_true(presentation.battle_finished, "the defeat reaches the finished-battle state (no dimmer or retry page: 0x42cbd0 leaves for GAME OVER)")
	_assert_true(not scene.action_menu.visible and not scene.move_overlay.visible, "result must hide stale action menus and selection cells")
	_assert_true(not scene.ui_audio.playing, "the battle does not play GAMEOVER.WAV itself: the GAME OVER screen's first frame does (0x42aea0)")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.ui_audio.stop()
	scene._process(0.0)
	_assert_true(not scene.ui_audio.playing, "refreshing result must not repeat game-over sound")
	_assert_eq(scene.play_loop, before, "result presentation must preserve settled battle state")
	scene.queue_free()
	await process_frame


func _test_status_inspection_no_turn_cost() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.menus.choose_command("move")
	# 0x443c63: another unit's page opens from move-select only.
	var select_before: Dictionary = scene.play_loop.duplicate(true)
	for actor_id in ["026", "023"]:
		for target in scene.play_loop["units"]:
			if target["actor_id"] != actor_id:
				continue
			scene.center_camera_on_grid(target["coord"])
			var point: Vector2 = scene.grid_cell_center_to_logical_position(target["coord"])
			scene.scene_input.handle_pointer_left_pressed(point)
			if actor_id == "026":
				# 0x443cfa: an unknown unit's page does not open (the mask itself is covered by
				# run_presentation_contract_tests.identity_mask_contracts).
				_assert_true(not scene.status_panel.visible, "clicking an enemy the player has not fought opens no status page")
				_assert_eq(scene.play_loop, select_before, "the refused inspection preserves pending movement and turn state")
				break
			_assert_true(scene.status_panel.visible, "clicking another unit must open its status")
			_assert_true(scene.status_panel.portrait.texture.resource_path.ends_with("portraits/%s.png" % actor_id), "inspection must switch to the clicked actor portrait")
			_assert_eq(scene.status_panel.vitals.values["role"].text, scene.status_panel.UISkin.data()["actors"][actor_id]["title"], "original title field must follow the clicked actor, not replace it with a faction label")
			if actor_id == "023":
				_assert_eq(scene.status_panel.vitals.values["hp"].text, "%d/%d" % [int(target["hp"]), int(target["max_hp"])], "a friendly unit's status page is in the clear (pmPlayer actors are born known)")
			_dispatch_key(scene, KEY_ESCAPE)
			_assert_eq(scene.play_loop, select_before, "ally inspection must preserve move-select and turn state")
			_assert_eq(scene.interaction_state, preload("res://game/sim/Interaction.gd").MOVE_SELECT, "closing another unit's page returns to move-select (0x4440b7 sub 11 → 0)")
			break
	var cells: Array = scene.BattlePlayLoop.movement_cells(scene.play_loop, "leonard")
	scene.move_selected_actor_to_grid(cells[0])
	await create_timer(0.4).timeout
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.choose_command("status")
	_assert_true(scene.status_panel.visible, "Status command should open usable panel")
	_assert_eq(scene.status_panel.vitals.values["hp"].text, "30/30", "Status should show live health on the original status strip")
	_assert_true(scene.status_panel.portrait.texture.resource_path.ends_with("portraits/001.png"), "player Status must use source-bound portrait")
	_assert_true(scene.status_panel.equipment_labels["weapon"].text == "闊刃劍" and scene.status_panel.equipment_labels["armor"].text == "騎士鎧甲", "original equipment slots must show the actual weapon and armor")
	_assert_eq(scene.play_loop, before, "viewing Status must preserve pending move and queue")
	_dispatch_key(scene, KEY_ESCAPE)
	_assert_true(not scene.status_panel.visible, "Esc should close Status")
	_assert_eq(scene.play_loop, before, "closing Status must not cancel movement or spend turn")
	var controllable_ally: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "actor023_1")
	controllable_ally["player_commandable"] = true
	controllable_ally["battle_actor_role"] = scene.BattlePlayLoop.ROLE_PLAYER
	before = scene.play_loop.duplicate(true)
	scene.center_camera_on_grid(controllable_ally["coord"])
	scene.scene_input.handle_pointer_left_pressed(scene.grid_cell_center_to_logical_position(controllable_ally["coord"]))
	# The action ring (98／74 → 0x4447a7) has no unit-click branch, and a player-commanded unit
	# (+0xa0 & 0x10) never opens the page even from move-select.
	_assert_true(not scene.status_panel.visible, "clicking a unit from the action ring opens no status page")
	_assert_eq(scene.play_loop, before, "clicking a controllable ally cannot switch the acting unit or alter pending movement")
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout


func _cutin_unit(actor_id: String) -> Dictionary:
	var loop: Dictionary = BattleFixture.loop()
	for unit in loop["units"]:
		if str(unit["actor_id"]) == actor_id:
			return unit.duplicate(true)
	return {}


func _test_combat_cutin_sequence() -> void:
	var cutin = load("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	await process_frame
	cutin.set_process(false)
	var impacts := [0]
	cutin.impact.connect(func(_strike, _attacker, _defender, _counter): impacts[0] += 1)
	# A primary strike answered by a counter: the exchange opens on the primary and closes
	# with the counter (BattlePresentation passes the clip's place in the exchange).
	cutin.play({"damage": 19, "hit": true, "defender_hp_after": 10}, _cutin_unit("001"), _cutin_unit("021"), false, Vector2(320, 240), Vector2(240, 240), [], [], {}, true, false)
	cutin.play({"damage": 3, "hit": true, "defender_hp_after": 0}, _cutin_unit("021"), _cutin_unit("001"), true, Vector2(320, 240), Vector2(240, 240), [], [], {}, false, true)
	cutin._process(0.025)
	_assert_true(cutin.opening_ball.visible and cutin.opening_ball.material != null and not cutin.attacker_sprite.visible and not cutin.defender_sprite.visible and not cutin.vitals.visible, "the first shot opens with the additive ball zoom, no actor or board yet")
	_seek_dispatch_update(cutin, 0)
	_assert_true(not cutin.opening_ball.visible, "the opening ends after 56 ticks")
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("001/0.png"), "cut-in should begin at original initial pose")
	_assert_eq(cutin.attacker_sprite.scale, Vector2.ONE, "native close-up must not shrink or mirror original poses")
	_assert_true(cutin.attacker_sprite.visible and not cutin.defender_sprite.visible, "attack starts with a single-attacker shot")
	_assert_true(cutin.stage.clip_contents and cutin.stage.size == Vector2(640, 320), "status-board crop must hide the deliberately incomplete sprite lower edge")
	_assert_eq(impacts[0], 0, "Wind-up must not emit damage or sound")
	_seek_dispatch_update(cutin, 13)
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("001/0.png"), "delay exit call still retains the initial pose")
	_seek_dispatch_update(cutin, 14)
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("001/1.png"), "first pose change occurs on the call after delay exit")
	_seek_dispatch_update(cutin, 24)
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("001/2.png"), "cut-in should show original attack preparation")
	_seek_dispatch_update(cutin, 29)
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("001/3.png"), "cut-in should show original strike pose")
	_assert_eq(impacts[0], 0, "source attack flash is still the attacker shot, not target damage")
	_assert_true(cutin.flash_sprite.visible and cutin.flash_sprite.position == Vector2(230, 210), "Leonard attack flash must use source aniInsertAttackFlash(-90, -120) from the attacker on the shot line (320,330)")
	_seek_ordinary(cutin, "impact")
	_assert_eq(impacts[0], 1, "Strike frame must emit impact exactly once")
	_assert_true(not cutin.attacker_sprite.visible and cutin.defender_sprite.visible, "impact cuts to the full-size defender rather than showing a miniature duel")
	_assert_true(cutin.defender_sprite.texture.resource_path.ends_with("021/4.png"), "Hit should use the original hurt pose")
	_seek_ordinary(cutin, "recovery", -0.001)
	_assert_true(cutin.defender_sprite.texture.resource_path.ends_with("021/4.png") and not cutin.transition_shade.visible, "the hurt pose holds to the end of the shot; a shot with the counter still to come has no transition")
	_seek_ordinary(cutin, "complete")
	_assert_eq(cutin.clips.size(), 1, "counter must remain queued after primary animation")
	cutin._process(0.025)
	_assert_true(not cutin.opening_ball.visible and cutin.attacker_sprite.visible, "the counter's shot has no opening")
	_assert_true(cutin.attacker_sprite.texture.resource_path.ends_with("021/0.png"), "counter should swap attacker resource")
	_assert_eq(cutin.result.text, "", "the counter's shot carries no 反擊 caption before its impact (UI6: aniShowHitResult shows the number alone)")
	_assert_eq(cutin.attacker_sprite.position, Vector2(320, 330), "counter uses the same native centered shot anchor (0x140, 0x14a)")
	_seek_ordinary(cutin, "impact", 0.05)
	_assert_true(cutin.defender_sprite.texture.resource_path.ends_with("001/4.png"), "Lethal counter should show hurt pose")
	_assert_eq(cutin.defender_sprite.modulate.a, 1.0, "Lethal close-up holds the hurt pose until map aftermath owns the fade")
	_assert_true(not cutin.result.text.contains("擊倒"), "a lethal result shows its number alone, no 擊倒 caption (UI6)")
	_seek_ordinary(cutin, "recovery")
	_assert_true(cutin.defender_sprite.visible and cutin.defender_sprite.texture.resource_path.ends_with("001/4.png") and cutin.transition_shade.visible, "the last shot darkens over the held hurt pose")
	_seek_ordinary(cutin, "darkened")
	_assert_true(cutin.transition_shade.visible and not cutin.scenery.visible and not cutin.defender_sprite.visible and cutin.busy(), "the lighten shows the map under the shade while the cut-in still gates input")
	_seek_ordinary(cutin, "complete")
	_assert_eq(impacts[0], 2, "Primary and counter each emit one impact, including large frame steps")
	_assert_true(not cutin.busy() and not cutin.panel.visible, "finished cut-in must release input and hide")
	cutin.play({"damage": 0, "hit": false, "defender_hp_after": 10}, _cutin_unit("001"), _cutin_unit("021"), false)
	_seek_ordinary(cutin, "impact")
	_assert_true(cutin.defender_sprite.texture.resource_path.ends_with("021/0.png"), "Miss must keep neutral pose rather than hurt")
	_assert_true(not cutin.flash_sprite.visible, "Miss must not display hit flash")
	cutin.queue_free()
	await process_frame


## Dispatch update `update` of the attacker's program, after the clip's opening.
func _seek_dispatch_update(cutin: Node, update: int) -> void:
	var moment: float = float(_ordinary_schedule(cutin)["opening"]) + cutin.OriginalTick.seconds(float(update))
	cutin._process(maxf(0.0, moment - cutin.elapsed + 0.000001) / cutin.Timing.PLAYBACK_SPEED)


func _test_cutin_effect_anchors_and_reset() -> void:
	var cutin = load("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	await process_frame
	cutin.set_process(false)
	var impacts := [0]
	cutin.impact.connect(func(_strike, _attacker, _defender, _counter): impacts[0] += 1)
	cutin.play({"skill_name": "氣刃斬", "damage": 8, "hit": true, "defender_hp_after": 0}, _cutin_unit("001"), _cutin_unit("021"), false)
	# The borrowed staging keeps its beats on the cut-in's scaled clock (0.5 s lead, contact
	# burst, 1.5 s end); seek in scaled seconds so the checks hold at any playback speed.
	cutin._process(0.2 / cutin.Timing.PLAYBACK_SPEED)
	_assert_eq(cutin.blade.scale, Vector2.ONE, "source specCode01 crescent travels left from x=700 at native scale")
	var cast_bounds: Rect2 = cutin.attacker_sprite.get_rect()
	cast_bounds.position += cutin.attacker_sprite.position
	_assert_true(Rect2(0, 0, 640, 320).encloses(cast_bounds), "center-anchored cast panel must remain wholly above the status strip")
	_assert_true(not cutin.blade.centered and cutin.blade.offset != Vector2.ZERO, "effects must use their SHP drawing anchors")
	_assert_true(cutin.blade.position.x > 320 and impacts[0] == 0, "travelling effect cannot apply damage before reaching the central target")
	cutin._process(0.32 / cutin.Timing.PLAYBACK_SPEED)
	_assert_eq(impacts[0], 1, "contact emits exactly one settled impact")
	_assert_true(cutin.blade.scale.x > 0 and cutin.sparks[0].visible, "contact replaces travelling crescent with unmirrored radial burst and source sparks")
	cutin._process(1.2 / cutin.Timing.PLAYBACK_SPEED)
	_assert_true(not cutin.busy(), "large frame step still releases completed skill")
	cutin.play({"damage": 0, "hit": false, "defender_hp_after": 10}, _cutin_unit("021"), _cutin_unit("001"), false)
	cutin._process(0.025)
	_assert_true(not cutin.blade.visible and not cutin.sparks[0].visible, "next ordinary strike cannot inherit spell effects")
	_assert_eq(cutin.defender_sprite.modulate, Color.WHITE, "next defender cannot inherit a lethal fade")
	_assert_true(cutin.attacker_sprite.scale == Vector2.ONE and cutin.defender_sprite.scale == Vector2.ONE, "enemy shots preserve native drawing scale and orientation")
	cutin._process(4.0)
	_assert_eq(impacts[0], 2, "each clip emits once even when one update skips to its end")
	cutin.queue_free()
	await process_frame
	await create_timer(0.2).timeout


func _test_pending_combat_blocks_early_input() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var actor: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	var foe: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "actor021_1")
	foe["coord"] = actor["coord"] + Vector2i.RIGHT
	foe["hp"] = 100
	foe["max_hp"] = 100
	scene.apply_loop(scene.BattlePlayLoop.choose_command(scene.play_loop, "attack"), "test")
	scene.apply_loop(scene.BattlePlayLoop.attack_target(scene.play_loop, foe["id"], func(_n): return 0), "test")
	var presentation = scene.get_node("BattlePresentation")
	presentation.cutin.set_process(false)
	_assert_true(presentation.has_pending_combat(scene.play_loop), "resolved combat is pending before its next presentation refresh")
	scene.menus.set_action_menu_visible(true)
	_assert_true(not scene.action_menu.visible, "menu must not flash visible before cut-in has even been queued")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.choose_command("wait")
	_assert_eq(scene.play_loop, before, "early command cannot replace an unpresented attack or advance AI")
	scene._process(0.0)
	# The player's confirmed attack has no map lead-in (BattleAttackCue.leads; original
	# 0x50 → 0x51 → 0x52 draw nothing): the cut-in consumes the receipt on the next frame.
	_assert_true(presentation.cutin.busy() and not presentation.attack_cue.visible and not presentation.has_pending_combat(scene.play_loop), "a confirmed player attack enters its cut-in on the next frame, without a map lead-in")
	_assert_eq(scene.play_loop, before, "presentation must never mutate the already settled combat state")
	scene.menus.choose_command("wait")
	_assert_eq(scene.play_loop, before, "input stays blocked throughout the attack presentation")
	for _clip in range(2):
		if not presentation.cutin.busy(): break
		_seek_ordinary(presentation.cutin, "complete")
		_assert_eq(scene.play_loop,before,"finishing a primary/counter clip does not itself advance the acting unit")
	scene._process(0.0)
	_assert_true(presentation.aftermath.reward_label.visible and scene.play_loop == before, "map EXP keeps the action pending after all primary/counter clips")
	scene.menus.choose_command("wait")
	_assert_true(scene.play_loop == before, "input stays blocked through the earned reward")
	for _job in range(presentation.aftermath.jobs.size()):
		if not presentation.aftermath.busy(): break
		scene._process(0)
		_assert_true(scene.play_loop == before, "each committed attack/counter EXP message precedes the same handoff")
		scene._process(presentation.aftermath.REWARD_SECONDS)
	_assert_eq(scene.play_loop, scene.BattlePlayLoop.finish_exhausted_action(before), "completed map reward hands off the completed attack exactly once")
	_assert_true(not scene.BattlePlayLoop.action_exhausted(scene.play_loop), "successor does not inherit the completed attack")
	scene.queue_free()
	await process_frame


func _test_recovery_item() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	var before: Dictionary = scene.play_loop.duplicate(true)
	var spent_full: Dictionary = scene.BattlePlayLoop.use_item(before, "241")
	_assert_true(spent_full["last_item_use"]["restored_hp"] == 0 and spent_full["last_item_use"]["heal_numbers"]["hp"] == 0 and scene.BattlePlayLoop.unit(spent_full, "leonard")["inventory"].count(241) == scene.BattlePlayLoop.unit(before, "leonard")["inventory"].count(241) - 1, "full-health use still spends one item for a 0 HP number (0x409e40, 0x444aba)")
	scene.menus.use_inventory_item("241", "leonard")
	_assert_true(not scene.ui_audio.playing, "rejected full-health use must not play healing sound")
	for unit in scene.play_loop["units"]:
		if unit["id"] == "leonard":
			unit["hp"] = 10
	scene.menus.choose_command("item")
	_assert_true(scene.item_panel.visible, "Item command should open usable inventory")
	_assert_eq(scene.item_panel.page, "commands", "item opens the observed four-command submenu")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("UseCommand").pressed.emit()
	var potion = scene.item_panel.rows.get_child(0)
	_assert_true(not potion.disabled, "wounded player should be able to use recovery item")
	_assert_true(potion.get_node("OriginalConsumable").texture.resource_path.ends_with("panels/itemIconUse.png"), "inventory retains original category artwork at native size")
	potion.pressed.emit()
	_assert_eq(scene.item_panel.page, "target", "item selection enters map recipient selection before spending it")
	scene.menus.use_inventory_item("241", "leonard")
	_assert_true(scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("interface_audio/use_item.wav"), "successful potion must play original item-use sound")
	var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	_assert_eq(player["hp"], player["max_hp"], "recovery must cap at max HP")
	_assert_eq(player["inventory"].count(241), 2, "use must consume exactly one original item")
	_assert_true(not scene.item_panel.visible and scene.ai_playback_active, "use must close inventory and end action")
	var attacked: Dictionary = before.duplicate(true)
	attacked["attacked_this_action"] = true
	for unit in attacked["units"]:
		if unit["id"] == "leonard":
			unit["hp"] = 10
	_assert_eq(scene.BattlePlayLoop.use_item(attacked, "241"), attacked, "item must not grant a second action after attacking")
	var empty: Dictionary = before.duplicate(true)
	for unit in empty["units"]:
		if unit["id"] == "leonard":
			unit["hp"] = 10
			unit["inventory"] = [246, 0, 0, 0, 0, 0, 0, 0]
	_assert_eq(scene.BattlePlayLoop.use_item(empty, "241"), empty, "empty stack must not heal or spend action")
	scene.queue_free()
	await process_frame


func _test_camera_pan_spatial_contract() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.menus.choose_command("move")
	var before: Dictionary = scene.play_loop.duplicate(true)
	var camera_before: Vector2 = scene.camera.position
	Input.action_press("ui_up")
	scene._process(0.16)  # 10 ticks × 12 px per tick (0x43e4a0 edge／arrow request)
	Input.action_release("ui_up")
	_assert_true(scene.camera.position.is_equal_approx(camera_before - Vector2(0, 120)), "arrow input should pan at 12 px per tick (%s)" % str(scene.camera.position))
	_assert_eq(scene.play_loop, before, "viewing map must not mutate battle or movement selection")
	var coord: Vector2i = scene.unit_grid_coord("leonard")
	var screen: Vector2 = scene.grid_cell_center_to_logical_position(coord)
	_assert_eq(scene.grid_at_logical_position(screen), coord, "hit testing must follow panned camera")
	Input.action_press("ui_up")
	scene._process(10.0)
	Input.action_release("ui_up")
	_assert_eq(scene.camera.position.y, 240.0, "camera must stop at map boundary")
	_dispatch_key(scene, KEY_HOME)
	_assert_eq(scene.camera.position, camera_before, "Home should restore actor view without canceling movement")
	scene.status_panel.show_unit(scene.BattlePlayLoop.unit(scene.play_loop, "leonard"))
	Input.action_press("ui_up")
	scene._process(1.0)
	Input.action_release("ui_up")
	_assert_eq(scene.camera.position, camera_before, "inspection modal should suspend camera panning")
	var pointer := InputEventMouseMotion.new()
	pointer.position = RuntimeReadback.logical_to_viewport_position(scene, Vector2(9, 240))
	scene._input(pointer)
	_assert_true(scene.pointer_inside_window, "real pointer motion must arm edge browsing even while a panel is open")
	scene._process(0.2)
	_assert_eq(scene.camera.position, camera_before, "an edge pointer cannot move the camera behind a modal")
	scene.get_window().mouse_exited.emit()
	_assert_true(not scene.pointer_inside_window, "leaving the game viewport immediately disarms scrolling")
	scene._input(pointer)
	scene.get_window().focus_exited.emit()
	_assert_true(not scene.pointer_inside_window, "focus loss must disarm an old edge coordinate")
	scene.queue_free()
	await process_frame


func _test_special_skill() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame # the presentation takes its map config on the first battle frame
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var player: Dictionary = scene.BattlePlayLoop.unit_ref(loop, "leonard")
	player["stamina"] = 20
	var target_id := ""
	for unit in loop["units"]:
		if unit["battle_actor_role"] == "enemy_ai":
			target_id = unit["id"]
			unit["coord"] = player["coord"] + Vector2i(2, 0)
			unit["hp"] = 100
			break
	loop = scene.BattlePlayLoop.choose_command(loop, "special")
	_assert_eq(loop["interaction"], "special_select", "special opens the skill page first, also for a single skill (original skill page)")
	loop = scene.BattlePlayLoop.choose_special(loop, "special:magicOTHER:magicCode01")
	_assert_eq(loop["interaction"], "attack_select", "choosing the skill on the page starts normal target selection")
	var canceled: Dictionary = scene.BattlePlayLoop.cancel_interaction(loop)
	_assert_eq(scene.BattlePlayLoop.unit(canceled, "leonard")["stamina"], 20, "cancel must not consume ST")
	_assert_eq(canceled["selected_attack"], "attack", "cancel must restore normal weapon range")
	var fired: Dictionary = scene.BattlePlayLoop.attack_target(loop, target_id, func(_n): return 0)
	_assert_true(fired["last_attack"].has("skill_name"), "two-cell target must resolve skill")
	_assert_true(int(fired["last_attack"]["experience"]["gained"]) > 0, "damaging special must earn experience through the same reward path")
	_assert_eq(scene.BattlePlayLoop.unit(fired, "leonard")["stamina"], 0, "skill must consume one charge")
	_assert_true(fired["attacked_this_action"] and not fired["pending_move"], "skill uses attack and commits movement")
	_assert_true(not scene.BattlePlayLoop.can_use_special(fired, "leonard"), "skill cannot repeat in same action")
	var empty: Dictionary = canceled.duplicate(true)
	for unit in empty["units"]:
		if unit["id"] == "leonard":
			unit["stamina"] = 0
	var empty_page: Dictionary = scene.BattlePlayLoop.choose_command(empty, "special")
	_assert_eq(empty_page["interaction"], "special_select", "insufficient ST still opens the skill page to read it")
	_assert_eq(scene.BattlePlayLoop.choose_special(empty_page, "special:magicOTHER:magicCode01")["interaction"], "special_select", "insufficient ST cannot leave the page into target selection")
	var cutin = scene.get_node("BattlePresentation").cutin
	cutin.set_process(false)
	cutin.play(fired["last_attack"], player, scene.BattlePlayLoop.unit(fired, target_id), false)
	# 雷歐納德's ANIMAL s_action cast lead (140 ticks, AnimalCastLead: banner over the shadowed
	# map, insets, portrait) plays first; then 氣刃斬's own specCode01／02 scripts
	# (SkillEffectScriptPlayer, 62.5 ticks/s): the blade object flies during the 60-tick caster
	# shot, the hit lands on aniProcessHitMiss at script tick 90 and the clip completes at
	# script tick 190 (see run_skill_effect_script_tests).
	var lead_seconds: float = cutin.OriginalTick.seconds(float(cutin.cast_lead(cutin.clips[0])["complete_tick"]))
	cutin._process(0.5)
	_assert_true(cutin.attacker_sprite.visible and cutin.attacker_sprite.texture.resource_path.ends_with("001/special-0.png") and not cutin.scenery.visible and not cutin.clips[0]["release_emitted"], "the cast lead shows the caster's banner over the map shot before the script")
	cutin._process(lead_seconds)
	_assert_true(cutin.skill_effects.sprites.any(func(sprite): return sprite.visible) and not cutin.blade.visible and not cutin.clips[0]["impact_emitted"], "skill windup shows the script's blade object, not the borrowed staging, without early impact")
	cutin._process(0.875)
	_assert_true(cutin.clips[0]["release_emitted"] and not cutin.clips[0]["impact_emitted"], "the target's shot has begun but the hit mark (tick 90) is not reached at 1.375 s into the script")
	cutin._process(0.15)
	_assert_true(cutin.clips[0]["impact_emitted"], "skill must reveal hit on the script's aniProcessHitMiss")
	cutin._process(2.5)
	_assert_true(not cutin.busy(), "skill must finish and release modal input")
	await create_timer(1.0).timeout
	scene.queue_free()
	await process_frame


## AI casts settle from the loop's damage stream (0x42c780), not the decision callable. Pin
## that stream to the first seeded state whose settlement draws all equal `value` — what the
## decision callable used to feed them, clamped to each bound as `_rand_range` does (rand(1)
## and rand(0) can only give 0) — so the native samples below keep their expected values.
func _pin_cast_stream(scene, loop: Dictionary, caster_id: String, pick: Callable, value: int) -> void:
	var probe := loop.duplicate(true)
	var chosen: Dictionary = BattleLoopAI.try_skill_turn(probe, caster_id, [scene.BattlePlayLoop.unit_ref(probe, "leonard")], pick)
	var bounds: Array = []
	var replay := loop.duplicate(true)
	BattleLoopCombat.resolve_skill(replay, caster_id, "leonard", chosen["skill_id"], scene.BattlePlayLoop.skill_fields(replay, chosen["skill_id"]), chosen["to"], func(n):
		bounds.append(n)
		return value, null)
	for seed in range(1, 4000000):
		var state := DamageRandomStream.seeded(seed)
		var matched := true
		for bound in bounds:
			var drawn: Dictionary = DamageRandomStream.raw(state) if int(bound) < 0 else DamageRandomStream.rand(state, int(bound))
			if int(drawn["value"]) != (value if int(bound) < 0 else clampi(value, 0, maxi(int(bound) - 1, 0))):
				matched = false
				break
			state = drawn["state"]
		if matched:
			TestSuite.seed_stream(loop, "damage", seed)
			return
	_assert_true(false, "no damage-stream state draws %d for every settlement bound %s of %s" % [value, str(bounds), chosen["skill_id"]])


func _test_mage_magic() -> void:
	# Boot from the seeded global stream, not from where the earlier cases' openings and AI
	# turns left the process stream: the opening levels (0x40e870) decide the stats pinned here.
	GlobalRandomStream.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var mage: Dictionary = {}
	var victim: Dictionary = {}
	for unit in loop["units"]:
		if unit["actor_id"] == "026" and mage.is_empty():
			mage = unit
		if unit["id"] == "leonard":
			victim = unit
	# The pins below are the template caster's: undo its opening birth (0x40e870), whose random
	# level-up rides on the global stream, and refresh from the pre-birth level and attributes.
	var birth: Dictionary = mage["entry_growth"]["input"]
	for key in ["level", "exp", "stamina", "kill_exp"]: mage[key] = birth[key]
	for key in birth["attributes"]: mage["combat_profile"][key] = birth["attributes"][key]
	mage.erase("entry_growth")
	mage.erase("entry_readjust")
	mage.merge(ProgressionRules.refresh_growth_stats(mage, loop["equipment_items"]), true)
	mage["hp"] = mage["max_hp"]
	mage["mp"] = mage["max_mp"]
	mage["coord"] = Vector2i(10, 12)
	victim["coord"] = Vector2i(10, 15)
	victim["hp"] = 100
	var wind_pick := func(n): return 1 if n == 32 else 0
	var fire_pick := func(n): return 0 if n == 32 else 1
	_pin_cast_stream(scene, loop, mage["id"], wind_pick, 0)
	var strike: Dictionary = BattleLoopAI.try_skill_turn(loop, mage["id"], [victim], wind_pick)
	_assert_eq(strike.get("magic_key"), "wind", "mage must use source wind spell at range three")
	_assert_true(scene.BattlePlayLoop.strike_range_cells(loop, strike).has(victim["coord"]), "ranged caster's chosen position keeps the selected target in the actual spell mask")
	_assert_eq(mage["mp"], 22, "spell must spend source cost eight MP from template baseline")
	_assert_eq(strike["damage"], 14, "native wind triangular sample includes caster level and magic power before Leonard's resistance")
	_assert_true(victim["hp"] < 100, "spell must damage hostile target")
	var presentation = scene.get_node("BattlePresentation")
	var ending: Dictionary = loop.duplicate(true)
	ending["battle_outcome"] = BattleOutcome.VICTORY_ENEMIES_CLEARED
	presentation.refresh(ending, scene.map_config, true, false)
	_assert_true(not presentation.battle_finished, "result must wait for outstanding movement before closing dialogue")
	var cutin = presentation.cutin
	cutin.set_process(false)
	cutin.play(strike, mage, victim, false)
	cutin._process(0.5)
	_assert_true(cutin.skill_effects.sprites[0].visible and not cutin.clips[0]["impact_emitted"], "local magic windup waits for impact")
	cutin._process(cutin.Timing.CAST_LEAD_IN / cutin.Timing.PLAYBACK_SPEED + 1.25)
	_assert_true(cutin.clips[0]["impact_emitted"], "magic must emit impact")
	cutin._process(2.5)
	_assert_true(not cutin.busy(), "magic must release input after animation")
	mage["mp"] = 0
	var unchanged: Dictionary = loop.duplicate(true)
	_assert_true(BattleLoopAI.try_skill_turn(loop, mage["id"], [victim], func(_n): return 0).is_empty(), "empty MP must return to normal AI")
	_assert_eq(loop, unchanged, "unaffordable spell must not move or damage")
	mage["mp"] = 8
	_pin_cast_stream(scene, loop, mage["id"], fire_pick, 1)
	var fire: Dictionary = BattleLoopAI.try_skill_turn(loop, mage["id"], [victim], fire_pick)
	_assert_eq(fire.get("magic_key"), "fire", "mage must also use source fire spell")
	_assert_eq(mage["mp"], 0, "last cast must consume remaining MP exactly")
	victim["combat_profile"]["live_defense"] = 1000
	victim["combat_profile"]["resist_by_type"] = {"2": 80, "3": 0}
	victim["hp"] = 100
	mage["mp"] = 8
	_pin_cast_stream(scene, loop, mage["id"], wind_pick, 0)
	var warded: Dictionary = BattleLoopAI.try_skill_turn(loop, mage["id"], [victim], wind_pick)
	_assert_eq(warded["damage"], 3, "native wind resistance applies after caster scaling, independent of physical armor")
	mage["mp"] = 8
	_pin_cast_stream(scene, loop, mage["id"], fire_pick, 1)
	var unwarded: Dictionary = BattleLoopAI.try_skill_turn(loop, mage["id"], [victim], fire_pick)
	_assert_eq(unwarded["damage"], 20, "native fire uses caster scaling and fire resistance, not wind resistance or armor")
	await create_timer(1.5).timeout
	scene.queue_free()
	await process_frame


func _test_local_spell_layers() -> void:
	var cutin = load("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var impacts := [0]
	cutin.impact.connect(func(_s, _a, _d, _c): impacts[0] += 1)
	var mage := _cutin_unit("026")
	var target := _cutin_unit("001")
	# The receipt's skill_id names the effCode script the player draws (風刃 effCode16, 幻火 effCode23).
	for key in ["wind", "fire"]:
		cutin.play({"skill_id": "magic:magicAIR:magicCode01" if key == "wind" else "magic:magicFIRE:magicCode01", "magic_key": key, "magic_name": key, "hit": true, "damage": 8, "defender_hp_after": 22}, mage, target, false, Vector2(450, 430))
		cutin._process(0.4)
		_assert_true(cutin.background.visible and is_equal_approx(cutin.background.color.a, 0.5) and not cutin.scenery.visible and not cutin.vitals.visible, "local magic shadows the map at level 8／16 (object 154 sub-state 7, 0x401ed4／0x4030f7) but does not replace the battlefield")
		_assert_true(not cutin.attacker_sprite.visible and not cutin.defender_sprite.visible, "local spell cannot draw an enlarged caster over its victim")
		_assert_eq(cutin.stage.size, Vector2(640, 480), "local effects must not be clipped at the 320px close-up boundary")
		if key == "wind":
			# Sample the script at ticks 20.5, 70.5 and 84.5 (after the Cast_Star lead): the
			# native tracks (effect_motion.json) draw the first AirWave2 (inserted at 4) as AIR02
			# over frames 5..26, AirBlade1 (54) over 55..76 and AirBlade2 (64) over 65..86.
			var script_seconds := func(ticks: float) -> float: return ticks / cutin.skill_effects.TICKS_PER_SECOND
			cutin._process(cutin.Timing.CAST_LEAD_IN / cutin.Timing.PLAYBACK_SPEED - 0.4 + script_seconds.call(20.5))
			var early: Array = cutin.skill_effects.sprites.filter(func(sprite): return sprite.visible).map(func(sprite): return str(sprite.texture.resource_path))
			_assert_true(early.any(func(path): return path.contains("air02_")), "wind must include its previously missing second wave family (AIR02 at script tick 20)")
			cutin._process(script_seconds.call(50.0))
			var both: Array = cutin.skill_effects.sprites.filter(func(sprite): return sprite.visible).map(func(sprite): return str(sprite.texture.resource_path))
			_assert_true(both.any(func(path): return path.ends_with("air04_01.shp.png")) and both.any(func(path): return path.ends_with("air04_02.shp.png")), "wind shows both blade phases at script tick 70")
			cutin._process(script_seconds.call(14.0))
			var late: Array = cutin.skill_effects.sprites.filter(func(sprite): return sprite.visible).map(func(sprite): return str(sprite.texture.resource_path))
			_assert_true(not late.any(func(path): return path.ends_with("air04_01.shp.png")) and late.any(func(path): return path.ends_with("air04_02.shp.png")), "at script tick 84 the first blade's native track has ended, the second still shows")
			var blades: Array = cutin.clips[0]["effect_timeline"]["events"].filter(func(event): return event["kind"] == "object" and str(event["object"]).begins_with("obj_Effect_AirBlade"))
			_assert_true(blades.size() == 2 and int(blades[0]["tick"]) == 54 and int(blades[1]["tick"]) == 64, "first wind blade (effCode16 tick 54) must precede the second (64)")
		else:
			cutin._process(cutin.Timing.CAST_LEAD_IN / cutin.Timing.PLAYBACK_SPEED + 1.0)
			_assert_true(cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and sprite.scale == Vector2(1.25, 1.25)), "fire uses the source fixed-point 1.25 zoom, not a blanket 2.2 enlargement")
		cutin._process(1.25)
		cutin._process(5.0)
		_assert_true(not cutin.busy(), "all local spell effects must finish")
	_assert_eq(impacts[0], 2, "each local spell emits its damage once")
	cutin.play({"damage": 0, "hit": false, "defender_hp_after": 30}, mage, target, false)
	cutin._process(0.01)
	# The zoom draws over the battlefield (camera_panel_motion §5: the 2026-09-24 recording's
	# ball grows from the screen centre over the visible map at 113.49–113.78, 163.95–164.20,
	# 199.66–199.95 and 353.72–353.97 s); the close-up backdrop returns with the overlay.
	_assert_true(not cutin.background.visible and not cutin.scenery.visible and cutin.opening_ball.visible and cutin.stage.size.y == 320, "ordinary attacks after local magic open with the zoom over the battlefield, no close-up backdrop yet")
	cutin._process(cutin.OriginalTick.seconds(float(cutin.Timing.OPENING_ZOOM_TICKS)) / cutin.Timing.PLAYBACK_SPEED)
	_assert_true(cutin.background.visible and cutin.scenery.visible and cutin.opening_ball.visible and cutin.stage.size.y == 320, "ordinary attacks must restore their close-up frame after local magic, the overlay fading over the backdrop")
	_seek_dispatch_update(cutin, 0)
	_assert_true(cutin.vitals.visible and not cutin.opening_ball.visible, "the board returns with the attacker's program")
	for effect in cutin.skill_effects.sprites:
		_assert_true(not effect.visible, "no local particles may leak into the next ordinary attack")
	cutin.queue_free()
	await process_frame
	await create_timer(0.2).timeout


func _test_live_experience() -> void:
	# Boot from the seeded global stream, not from where the earlier cases' openings and AI
	# turns left the process stream: the opening levels (0x40e870) decide the stats pinned here.
	GlobalRandomStream.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	var target := ""
	var player: Dictionary
	for unit in scene.play_loop["units"]:
		if unit["id"] == "leonard":
			player = unit
			player["exp"] = 99
	for unit in scene.play_loop["units"]:
		if unit["actor_id"] == "021":
			target = unit["id"]
			unit["hp"] = 1
			unit["coord"] = player["coord"] + Vector2i(1, 0)
			break
	var loop: Dictionary = scene.BattlePlayLoop.choose_command(scene.play_loop, "attack")
	loop = scene.BattlePlayLoop.attack_target(loop, target, func(_n): return 0)
	var growth: Dictionary = loop["last_attack"]["experience"]
	_assert_eq(growth["gained"], 25, "one actual damage and kill_exp twenty enter native same-level EXP conversion")
	_assert_eq(growth["level_after"], 2, "live strike must apply level growth")
	var after: Dictionary = scene.BattlePlayLoop.unit(loop, "leonard")
	_assert_eq(after["exp"], 24, "native final award is applied once with threshold overflow retained")
	var retried: Dictionary = scene.BattlePlayLoop.attack_target(loop, target, func(_n): return 0)
	_assert_eq(scene.BattlePlayLoop.unit(retried, "leonard"), after, "rejected repeated strike cannot award EXP")
	var presentation = scene.get_node("BattlePresentation")
	scene.set_process(false)
	presentation.cutin.set_process(false)
	presentation.refresh(loop, scene.map_config, true)
	presentation.refresh(loop, scene.map_config, true, true, presentation.attack_cue.duration)
	presentation.cutin._process(0.25)
	_assert_true(not scene.ui_audio.playing, "level-up sound must wait for visible combat result")
	_assert_eq(presentation.cutin.vitals.values["level"].text, "1", "wind-up cannot reveal the precomputed level-up")
	_assert_eq(presentation.cutin.vitals.values["exp"].text, "99/100", "wind-up must retain pre-strike experience")
	_seek_ordinary(presentation.cutin, "impact")
	_assert_true(not presentation.cutin.result.text.contains("EXP") and not scene.ui_audio.playing, "impact cannot announce map growth early")
	_seek_ordinary(presentation.cutin, "complete")
	presentation.refresh(loop, scene.map_config, true)
	_assert_eq(presentation.current_message_id(), "372", "source death words precede the map reward")
	presentation.advance_dialogue()
	presentation.refresh(loop, scene.map_config, true, true, 1)
	presentation.refresh(loop, scene.map_config, true)
	# 0x442720: the EXP float (no level-up cue) → $ when earned → LEVEL UP with sfxLevelUp.
	_assert_eq(presentation.aftermath.reward_label.text, "EXP 25", "map reward shows the EXP float first")
	_assert_true(not scene.ui_audio.playing, "the EXP float carries no level-up cue")
	var shown: Array[String] = [str(presentation.aftermath.reward_label.text)]
	for _step in range(3):
		if presentation.aftermath.reward_label.text == "LEVEL UP": break
		presentation.refresh(loop, scene.map_config, true, true, presentation.aftermath.REWARD_SECONDS)
		presentation.refresh(loop, scene.map_config, true)
		shown.append(str(presentation.aftermath.reward_label.text))
	_assert_true(shown.back() == "LEVEL UP" and (shown.size() == 2 or shown[1].begins_with("$ ")), "map reward should reveal level growth as the LEVEL UP float after EXP and $ (%s)" % str(shown))
	_assert_true(scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("interface_audio/level_up.wav"), "visible upgrade must play original level-up resource")
	scene.ui_audio.stop()
	presentation.refresh(loop, scene.map_config, true, true, 0.25)
	_assert_true(not scene.ui_audio.playing, "repeated result refresh must not replay upgrade cue")
	scene.play_growth_sound({"level_before": 2, "level_after": 2})
	_assert_true(not scene.ui_audio.playing, "ordinary EXP gain must not play upgrade cue")
	scene.status_panel.show_unit(after)
	_assert_eq(scene.status_panel.vitals.values["level"].text, "2", "original status strip must show current level")
	_assert_eq(scene.status_panel.vitals.values["exp"].text, "24/150", "original status strip must show retained native EXP")
	scene.queue_free()
	await process_frame


func _test_growth_allocation_interaction() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var player: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	player["exp"] = 99
	player.merge(scene.BattlePlayLoop.ProgressionRules.resolve_experience(player, 1, scene.play_loop["equipment_items"]), true)
	scene.menus.choose_command("move")
	var destination: Vector2i = scene.BattlePlayLoop.movement_cells(scene.play_loop, "leonard")[0]
	scene.move_selected_actor_to_grid(destination)
	await create_timer(2.0).timeout
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene._process(0.0)
	_assert_true(scene.growth_panel.visible, "new level offers choices after motion without spending the pending move")
	_assert_true(not scene.action_menu.visible, "growth modal must hide map commands")
	_assert_true(scene.growth_panel.confirm_button.disabled, "empty draft cannot be submitted")
	var growth_choices: Dictionary = scene.growth_panel.choices
	_assert_true(growth_choices.values().all(func(row): return row["plus"].visible and not row["minus"].visible) and not scene.growth_panel.confirm_button.visible, "the window opens with only the four ＋ buttons, no － and no OK (recording 341.0 s)")
	scene.growth_panel.choices["str"]["plus"].pressed.emit()
	_assert_true(growth_choices["str"]["minus"].visible and not growth_choices["dex"]["minus"].visible, "a row holding a draft point shows its －, the others do not")
	for i in range(4):
		scene.growth_panel.choices["str"]["plus"].pressed.emit()
	_assert_true(scene.growth_panel.choices["dex"]["plus"].disabled, "full five-point draft cannot overspend")
	_assert_true(growth_choices.values().all(func(row): return not row["plus"].visible) and growth_choices["str"]["minus"].visible and scene.growth_panel.confirm_button.visible, "with no point left every ＋ is gone and OK appears (recording ≈ 350 s)")
	_assert_eq(scene.play_loop, before, "preview must not mutate battle state")
	scene.menus.choose_command("wait")
	_assert_eq(scene.play_loop, before, "commands cannot slip through the growth modal")
	# The original's mode 10 root carries flag 0x400 (0x43bbd3); its right click／Esc close skips on it (0x438839).
	_dispatch_key(scene, KEY_ESCAPE)
	_dispatch_mouse_button(scene, Vector2(320, 240), MOUSE_BUTTON_RIGHT, true)
	scene._process(0.0)
	_assert_true(scene.growth_panel.visible and scene.growth_panel.draft == {"str": 5}, "right click／Esc cannot close the window before OK")
	_assert_eq(scene.play_loop, before, "the refused close changes nothing")
	scene.growth_panel.hide() # the harness skip seam (as points left by an old save)
	scene._process(0.0)
	_assert_true(not scene.growth_panel.visible, "a skipped level is not reopened every frame")
	_assert_eq(scene.play_loop, before, "skipping preserves all points and pending movement")
	scene.menus.choose_command("status")
	_assert_true(scene.status_panel.growth_button.visible, "Status must provide the way back to unspent growth")
	scene.status_panel.growth_button.pressed.emit()
	_assert_true(scene.growth_panel.visible and not scene.status_panel.visible, "Status opens allocation without competing panels")
	_assert_eq(scene.growth_panel.draft, {}, "reopening clears only uncommitted choices")
	for key in ["str", "dex", "mind", "con"]:
		scene.growth_panel.choices[key]["plus"].pressed.emit()
	scene.growth_panel.choices["str"]["plus"].pressed.emit()
	scene.growth_panel.choices["str"]["minus"].pressed.emit()
	_assert_eq(scene.growth_panel.draft["str"], 1, "a draft increment can be undone")
	scene.growth_panel.choices["str"]["plus"].pressed.emit()
	scene.growth_panel.confirm_button.pressed.emit()
	_assert_true(not scene.growth_panel.visible, "successful confirmation closes the editor")
	var after: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	var original: Dictionary = scene.BattlePlayLoop.unit(before, "leonard")
	_assert_eq(after["pending_stat_points"], 0, "confirm spends five points exactly once")
	_assert_eq(after["combat_profile"]["str"], int(original["combat_profile"]["str"]) + 2, "confirmed Strength draft affects authoritative base attributes")
	_assert_eq(after["combat_profile"]["dex"], int(original["combat_profile"]["dex"]) + 1, "confirmed Dexterity draft affects authoritative base attributes")
	_assert_eq(after["combat_profile"]["mind"], int(original["combat_profile"]["mind"]) + 1, "confirmed Mind draft affects authoritative base attributes")
	_assert_eq(after["combat_profile"]["con"], int(original["combat_profile"]["con"]) + 1, "confirmed Constitution draft affects authoritative base attributes")
	_assert_eq(after["max_hp"], int(original["max_hp"]) + 2, "confirmed four-attribute draft recomputes health through the native SwordMan formula")
	_assert_eq(after["hp"], original["hp"], "confirmed growth must not refill current HP")
	_assert_eq(after["live_speed"], 15, "confirmed Dexterity refreshes the real actor speed")
	scene.status_panel.show_unit(after)
	_assert_eq(scene.status_panel.stat_values["mind"].text, "9", "Status must read live Mind rather than the static UI table")
	_assert_eq(scene.status_panel.stat_values["con"].text, "13", "Status must read live Constitution rather than the static UI table")
	_assert_eq(scene.status_panel.stat_values["magic"].text, "18%", "Status must format the live magic value with the observed percent suffix, without rescaling it")
	scene.status_panel.hide()
	for field in ["turn_queue", "pending_move", "pending_move_from", "moved_this_action", "attacked_this_action", "interaction", "last_combat"]:
		_assert_eq(scene.play_loop.get(field), before.get(field), "allocation preserves " + field)
	var settled: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.allocate_growth("leonard", {"str": 2, "dex": 1, "mind": 1, "con": 1})
	_assert_eq(scene.play_loop, settled, "duplicate UI signal cannot apply twice")
	_assert_eq(scene.BattlePlayLoop.allocate_growth(before, "actor021_1", {"str": 1}), before, "growth cannot edit an enemy")
	_assert_eq(scene.BattlePlayLoop.allocate_growth(before, "leonard", {"str": 6}), before, "overspending cannot mutate the authoritative loop")
	# A won loop still takes the final blow's points (user decision 2026-09-24, as the original's
	# 0x442720 phase 8 before the win scan) and nothing else; a lost loop takes none.
	var won := before.duplicate(true)
	won["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	var won_after: Dictionary = scene.BattlePlayLoop.allocate_growth(won, "leonard", {"str": 1})
	_assert_eq(int(scene.BattlePlayLoop.unit(won_after, "leonard")["pending_stat_points"]), int(scene.BattlePlayLoop.unit(won, "leonard")["pending_stat_points"]) - 1, "a won result still accepts the final blow's points")
	for field in ["battle_outcome", "turn_queue", "interaction", "last_combat", "gold", "settlement"]:
		_assert_eq(won_after.get(field), won.get(field), "allocation on a won result changes nothing but the member: " + field)
	_assert_eq(scene.BattlePlayLoop.allocate_growth(won, "actor021_1", {"str": 1}), won, "a won result still cannot edit an enemy")
	var lost := before.duplicate(true)
	lost["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	_assert_eq(scene.BattlePlayLoop.allocate_growth(lost, "leonard", {"str": 1}), lost, "a lost result rejects stat editing")
	scene.cancel_pending_move()
	_assert_eq(scene.unit_grid_coord("leonard"), before["pending_move_from"], "the preserved pending move remains cancelable after growth")
	scene.queue_free()
	await process_frame


func _test_attack_target_preview() -> void:
	# Boot from the seeded global stream, not from where the earlier cases' openings and AI
	# turns left the process stream: the opening levels (0x40e870) decide the stats pinned here.
	GlobalRandomStream.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	var player: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	var target: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "actor021_1")
	target["coord"] = player["coord"] + Vector2i.RIGHT
	player["hit_bonus_accum"] = 9
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command("attack")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(target["coord"]))
	scene._process(0)
	var presentation = scene.get_node("BattlePresentation")
	_assert_true(not presentation.combat_label.visible, "the weapon-target hover shows no overhead 命中 N% line (UI6 照原版: the identity strip carries the target)")
	_assert_true(presentation.target_vitals.visible and presentation.target_vitals.values["hp"].text == "???" and presentation.target_vitals.values["name"].text == "???", "the attack-target strip masks an enemy the player has not fought (0x434d10 is the one WINDOW10 text block)")
	_assert_true(presentation.selection_cursor.visible and presentation.selection_cursor.eligible, "a legal selected cell has a visible cursor")
	_assert_eq(presentation.selection_cursor.cell_rect.get_center(), scene.grid_cell_center_to_logical_position(target["coord"]), "selection cursor and click projection must identify the same cell")
	_assert_eq(scene.play_loop, before, "hover must not spend charge, commit movement or mutate combat")
	scene.play_loop[scene.LoopKeys.KNOWN_UNIT_IDS].append(target["id"])
	scene.apply_loop(scene.play_loop, "test")
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(target["coord"]))
	scene._process(0)
	_assert_true(presentation.target_vitals.visible and presentation.target_vitals.values["hp"].text == "22/22", "original target strip must show current HP of a fought enemy instead of a debug transcript")
	before = scene.play_loop.duplicate(true)
	var resolved: Dictionary = scene.BattlePlayLoop.CoreCombatRules.resolve_attack(player, target, func(_n): return 0)
	_assert_eq(resolved["hit_rate"], 100, "actual strike must share preview accuracy")
	scene.cancel_current_interaction()
	scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["stamina"] = 20
	scene.menus.choose_command("special")
	scene.magic_panel.choices["special:magicOTHER:magicCode01"].pressed.emit()
	scene._process(0)
	_assert_true(not presentation.combat_label.visible and presentation.selection_cursor.caption.text == "氣刃斬", "the special-target hover shows no overhead hit line; the skill's 命中率 reads on the skill page (UI6)")
	# Legality only decides the hit line: the strip of the unit under the cursor always shows.
	presentation.preview_target(scene.play_loop, "leonard")
	_assert_true(not presentation.combat_label.visible, "friendly hover must not offer an attack")
	_assert_true(presentation.target_vitals.visible and presentation.target_vitals.values["level"].text != "", "friendly hover still shows the unit's identity strip")
	presentation.preview_target(scene.play_loop, "actor026_1")
	_assert_true(not presentation.combat_label.visible, "out-of-range hover must not offer an attack")
	_assert_true(presentation.target_vitals.visible, "out-of-range hover still shows the unit's identity strip")
	before = scene.play_loop.duplicate(true)
	for cell in scene.BattlePlayLoop.attack_cells(scene.play_loop):
		if scene.scene_input.unit_id_at_grid(cell) == "":
			scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(cell))
			scene._process(0)
			_assert_true(presentation.selection_cursor.caption.text == "氣刃斬" and presentation.selection_cursor.eligible, "empty in-range tiles retain the current skill name")
			_assert_true(not presentation.target_vitals.visible and not presentation.combat_label.visible, "empty cells cannot reuse the preceding target's information")
			break
	scene.camera_controller.pan(Vector2.UP, 0.5, 240)
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(target["coord"]))
	scene._process(0)
	_assert_eq(scene.hovered_unit_id, target["id"], "camera movement must preserve the target under its displayed cell")
	_assert_eq(presentation.selection_cursor.cell_rect.get_center(), scene.grid_cell_center_to_logical_position(target["coord"]), "cursor follows the same camera transform after panning")
	_assert_true(not presentation.target_vitals.get_global_rect().intersects(presentation.selection_cursor.cell_rect), "target information must not cover the cell being confirmed")
	scene.scene_input.disarm_pointer_scroll()
	scene._process(0)
	_assert_true(not presentation.selection_cursor.visible and not presentation.target_vitals.visible, "leaving the window clears stale hover feedback")
	_assert_eq(scene.play_loop, before, "selection feedback, camera and focus changes remain read-only")
	scene.cancel_current_interaction()
	scene._process(0)
	_assert_true(not presentation.combat_label.visible and not presentation.selection_cursor.visible, "cancel must remove the complete target preview")
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout


## BattlePresentation.preview_hovered_unit ／ BattlePlayLoop.unit_known: the
## original identity strip on hover in move selection, ??? until the enemy was fought.
func _test_move_select_identity_bar() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	var Loop = scene.BattlePlayLoop
	var player: Dictionary = Loop.unit_ref(scene.play_loop, "leonard")
	var enemy: Dictionary = Loop.unit_ref(scene.play_loop, "actor021_1")
	var friend: Dictionary = Loop.unit_ref(scene.play_loop, "actor023_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	friend["coord"] = player["coord"] + Vector2i.LEFT
	scene.apply_loop(scene.play_loop, "test")
	var presentation = scene.get_node("BattlePresentation")
	var titles: Dictionary = presentation.target_vitals.UISkin.data()["actors"]
	_assert_true(Loop.unit_known(scene.play_loop, "leonard") and Loop.unit_known(scene.play_loop, "actor023_1"), "pmPlayer units are known from the start")
	_assert_true(not Loop.unit_known(scene.play_loop, "actor021_1"), "an enemy the player has not fought is unknown")
	# The original byte is indexed by the PLAYERS template row (obj+0xa2), shared by every
	# unit of that row (runtime-measured 2026-09-26: one 021 dies, all five 021 read known).
	var killed: Dictionary = scene.play_loop.duplicate(true) # off the scene: the hover checks below need 021 still unknown
	Loop.set_unit_defeated(killed, "actor021_3", true)
	_assert_true(killed[scene.LoopKeys.KNOWN_UNIT_IDS].has("actor021_3") and not killed[scene.LoopKeys.KNOWN_UNIT_IDS].has("actor021_4"), "death marks the dead unit's own id; the known set stays per unit id")
	_assert_true(Loop.unit_known(killed, "actor021_4") and Loop.unit_known(killed, "actor021_5"), "killing one 021 makes every other 021 read known (known byte per template row)")
	_assert_true(not Loop.unit_known(killed, "actor026_1"), "another row (026) stays unknown")
	scene.menus.choose_command("move")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(enemy["coord"]))
	scene._process(0)
	var vitals = presentation.target_vitals
	_assert_true(vitals.visible, "resting the pointer on an enemy during move selection shows the identity strip")
	_assert_eq(vitals.values["name"].text, "???", "unknown enemy name prints ???")
	_assert_eq(vitals.values["level"].text, "??", "unknown enemy level prints ??")
	_assert_eq(vitals.values["hp"].text, "???", "unknown enemy HP prints ???")
	_assert_eq(vitals.values["role"].text, str(titles["021"]["title"]), "the title stays readable for an unknown enemy")
	_assert_eq(vitals.values["race"].text, str(titles["021"]["race"]), "the race stays readable for an unknown enemy")
	_assert_true(vitals.resist_values[0].text.ends_with("???"), "unknown enemy resists print ???")
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(friend["coord"]))
	scene._process(0)
	_assert_true(vitals.visible and vitals.values["name"].text == "???", "a known friendly nameless 023 (name 306) prints ??? like the original (Wine 2026-09-22)")
	_assert_eq(vitals.values["hp"].text, "%d/%d" % [int(friend["hp"]), int(friend["max_hp"])], "a friendly unit shows its real HP on hover")
	for cell in Loop.movement_cells(scene.play_loop, "leonard"):
		if scene.scene_input.unit_id_at_grid(cell) == "":
			scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(cell))
			scene._process(0)
			_assert_true(not vitals.visible, "leaving the unit hides the identity strip")
			break
	_assert_eq(scene.play_loop, before, "hovering is read-only")
	scene.cancel_current_interaction()
	scene._process(0)
	_assert_true(not vitals.visible, "the action ring state shows no hover strip")
	scene.menus.choose_command("attack")
	scene.attack_selected_coord(enemy["coord"])
	_assert_true(Loop.unit_known(scene.play_loop, "actor021_1") or int(Loop.unit(scene.play_loop, "actor021_1")["hp"]) <= 0, "an attacked enemy becomes known at target confirmation")
	_assert_true(scene.play_loop[scene.LoopKeys.KNOWN_UNIT_IDS].has("actor021_1"), "the known set records the attacked enemy")
	var Checkpoint = load("res://game/battle/runtime/BattleCheckpoint.gd")
	var saved: Dictionary = Checkpoint.state(scene.play_loop)
	var restored: Dictionary = Checkpoint.restored(saved, scene.play_loop)
	_assert_true(Loop.unit_known(restored, "actor021_1"), "a restored loop keeps the fought enemy known")
	var broken: Dictionary = scene.play_loop.duplicate(true)
	broken.erase(scene.LoopKeys.KNOWN_UNIT_IDS)
	_assert_true(not Loop.same_state(broken, scene.play_loop), "a state without the known set is a different state")
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout


func _test_stamina_builds_from_zero() -> void:
	var Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
	var loop: Dictionary = BattleFixture.loop()
	var player: Dictionary = Loop.unit_ref(loop, "leonard")
	_assert_eq(player["stamina"], 0, "opening must not grant a free special charge")
	_assert_true(not Loop.can_use_special(loop, "leonard"), "zero stamina must disable special")
	var enemy: Dictionary = Loop.unit_ref(loop, "enemy021_1")
	enemy["hp"] = 500
	enemy["max_hp"] = 500
	player["hp"] = 500
	player["max_hp"] = 500
	BattleLoopCombat.apply_strike(loop, "leonard", "enemy021_1", func(_n): return 0)
	_assert_eq(player["stamina"], 3, "a nonlethal light strike earns original attacker gain")
	BattleLoopCombat.apply_strike(loop, "enemy021_1", "leonard", func(_n): return 0)
	_assert_eq(player["stamina"], 9, "receiving a light strike earns twice the base gain")
	BattleLoopCombat.apply_strike(loop, "leonard", "enemy021_1", func(_n): return 0)
	BattleLoopCombat.apply_strike(loop, "enemy021_1", "leonard", func(_n): return 0)
	_assert_true(not Loop.can_use_special(loop, "leonard"), "18 earned ST remains below the original20 cost")
	BattleLoopCombat.apply_strike(loop, "leonard", "enemy021_1", func(_n): return 0)
	_assert_true(Loop.can_use_special(loop, "leonard"), "earned charge should enable special")


## actSetPlayerUndead marker (level 3 漢克斯): 0x43ee66／0x4433b6 revive a dead-flagged
## undead object at 1 HP instead of removing it; the lethal hit itself settles as before.
func _test_undead_survives_lethal_strike() -> void:
	var Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
	var loop: Dictionary = BattleFixture.loop()
	var enemy: Dictionary = Loop.unit_ref(loop, "enemy021_1")
	enemy["hp"] = 1
	enemy["undead"] = true
	var strike: Dictionary = BattleLoopCombat.apply_strike(loop, "leonard", "enemy021_1", func(_n): return 0)
	_assert_true(int(strike.get("damage", 0)) > 0, "the fixture strike must hit a 1-HP target")
	_assert_eq(int(Loop.unit_ref(loop, "enemy021_1")["hp"]), 1, "an undead unit at HP <= 0 stands back up with 1 HP (0x43ee88 mov [rec+0xd8], 1)")
	_assert_eq(bool(Loop.unit_ref(loop, "enemy021_1")["defeated"]), false, "the undead unit is not defeated")
	_assert_eq(bool(strike.get("undead_revived", false)), true, "the strike receipt records the revive")
	_assert_eq(int(strike["defender_hp_after"]), 1, "the receipt's visible HP after is the revived value")
	enemy = Loop.unit_ref(loop, "enemy021_1")
	enemy["undead"] = false
	BattleLoopCombat.apply_strike(loop, "leonard", "enemy021_1", func(_n): return 0)
	_assert_eq(bool(Loop.unit_ref(loop, "enemy021_1")["defeated"]), true, "with the marker cleared the same hit defeats the unit")


func _seek_ordinary(cutin: Node, event: String, offset: float = 0.001) -> void:
	var schedule: Dictionary = _ordinary_schedule(cutin)
	cutin._process(maxf(0.0, (float(schedule[event]) + offset - cutin.elapsed) / cutin.Timing.PLAYBACK_SPEED))


## The queued clip's own schedule (its first_shot／last_shot place in the exchange included).
func _ordinary_schedule(cutin: Node) -> Dictionary:
	var clip: Dictionary = cutin.clips[0]
	return cutin.Timing.ordinary(cutin.manifest["actors"][clip["attacker"]], clip["strike"], bool(clip["first_shot"]), bool(clip["last_shot"]))


func _test_priest_trial_scene() -> void:
	var Loop = run_support_magic_tests.BattlePlayLoop
	var scene=load("res://game/battle/development/PriestTrial.tscn").instantiate()
	root.add_child(scene);await create_timer(0.2).timeout;scene.set_process(false)
	_assert_true(scene.play_loop["scenario_ok"] and scene.first_battle_scenario["player_unit_id"]=="tina","actual scene boots without a Leonard actor: "+str(scene.play_loop.get("scenario_error","")))
	_assert_true(scene.actor_node_for_unit("tina")!=null and scene.actor_node_for_unit("leonard")==null,"scene uses original002 actor resources under the correct identity")
	var budget:int=RuntimeReadback.move_point_for_selected_unit(scene)
	var selected:=str(scene.play_loop.get("selected_unit_id",""))
	if selected=="":selected="tina"
	_assert_true(budget==int(Loop.unit(scene.play_loop,selected)["move_point"]),"view reads selected actor's exact movement budget")
	Loop.unit_ref(scene.play_loop,selected)["move_point"]=0
	_assert_true(RuntimeReadback.move_point_for_selected_unit(scene)==0,"zero movement does not fall back to Leonard's budget")
	for sound in scene.find_children("*","AudioStreamPlayer",true,false):sound.stop();sound.stream=null
	scene.queue_free();await process_frame;await create_timer(0.1).timeout

extends SceneTree

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const OUTPUT_DIR := "res://ignored/first-scene-dev-interaction-harness/latest"
const CANVAS_SIZE := Vector2i(640, 480)

var failures: Array[String] = []
var captures: Array[Dictionary] = []
var capture_viewport: SubViewport


func _initialize() -> void:
	await _run_capture()
	if failures.is_empty():
		print("BATTLE_SCENE_DEV_INTERACTION_HARNESS_CAPTURE_PASS images=%d output=%s" % [captures.size(), OUTPUT_DIR])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BATTLE_SCENE_DEV_INTERACTION_HARNESS_CAPTURE_FAIL count=%d output=%s" % [failures.size(), OUTPUT_DIR])
		quit(1)


func _run_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("BattleSceneRuntime capture requires a non-headless renderer; run without --headless")
		return
	_prepare_output_dir()
	capture_viewport = SubViewport.new()
	capture_viewport.name = "BattleSceneRuntimeCaptureViewport"
	capture_viewport.size = CANVAS_SIZE
	capture_viewport.disable_3d = true
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)

	var packed: PackedScene = load("res://game/battle/scene/BattleSceneRuntime.tscn")
	if packed == null:
		_fail("BattleSceneRuntime scene failed to load")
		return
	var scene := packed.instantiate()
	capture_viewport.add_child(scene)
	await process_frame
	await process_frame
	if not scene.has_method("start_dev_first_control_harness"):
		_fail("BattleSceneRuntime missing explicit dev first-control harness")
		return
	scene.call("start_dev_first_control_harness")
	await process_frame
	var harness_summary: Dictionary = RuntimeReadback.runtime_contract_summary(scene)
	if str(harness_summary.get("runtime_entrypoint", "")) != "dev_first_control_harness":
		_fail("interaction capture must run through dev_first_control_harness, not product main path")
		return

	_capture("01_first_control_idle_640x480.png", "first_control_idle", scene)
	scene.call("select_actor", "leonard")
	await process_frame
	_capture("02_action_menu_640x480.png", "action_menu", scene)
	scene.menus.choose_command("move")
	await process_frame
	_capture("03_move_overlay_640x480.png", "move_overlay", scene)
	var initial_grid: Vector2i = scene.call("unit_grid_coord", "leonard")
	scene.call("move_selected_actor_to_grid", initial_grid + Vector2i(1, 0))
	await process_frame
	_capture("04_post_move_menu_640x480.png", "post_move_menu", scene)
	scene.call("cancel_pending_move")
	await process_frame
	_capture("05_cancel_revert_menu_640x480.png", "cancel_revert_menu", scene)
	_write_manifest(scene)


func _capture(file_name: String, stage: String, scene: Node) -> void:
	var image := _capture_image()
	if image.is_empty():
		_fail("capture image is empty: %s" % file_name)
		return
	if image.get_size() != CANVAS_SIZE:
		_fail("capture size mismatch for %s expected=%s actual=%s" % [file_name, str(CANVAS_SIZE), str(image.get_size())])
		return
	if _looks_blank(image):
		_fail("capture looks blank: %s" % file_name)
		return
	var map_object_summary: Dictionary = RuntimeReadback.map_object_summary(scene)
	if not _map_object_summary_matches(stage, map_object_summary):
		return
	var path := "%s/%s" % [ProjectSettings.globalize_path(OUTPUT_DIR), file_name]
	var result := image.save_png(path)
	if result != OK:
		_fail("failed to save capture %s result=%s" % [path, str(result)])
		return
	captures.append({
		"stage": stage,
		"file": path,
		"interaction_summary": RuntimeReadback.interaction_summary(scene),
		"runtime_contract_summary": RuntimeReadback.runtime_contract_summary(scene),
		"map_object_summary": map_object_summary,
	})


func _capture_image() -> Image:
	if capture_viewport == null:
		return Image.new()
	var texture := capture_viewport.get_texture()
	if texture == null:
		return Image.new()
	var image := texture.get_image()
	if image == null:
		return Image.new()
	return image


func _looks_blank(image: Image) -> bool:
	var size := image.get_size()
	if size.x <= 0 or size.y <= 0:
		return true
	var first := image.get_pixel(0, 0)
	for y in range(0, size.y, 32):
		for x in range(0, size.x, 32):
			var sample := image.get_pixel(x, y)
			var delta := absf(sample.r - first.r) + absf(sample.g - first.g) + absf(sample.b - first.b) + absf(sample.a - first.a)
			if delta > 0.02:
				return false
	return true


func _write_manifest(scene: Node) -> void:
	var map_object_summary: Dictionary = RuntimeReadback.map_object_summary(scene)
	if not _map_object_summary_matches("final_manifest", map_object_summary):
		return
	var path := "%s/manifest.json" % ProjectSettings.globalize_path(OUTPUT_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("failed to write capture manifest: %s" % path)
		return
	file.store_string(JSON.stringify({
		"schema": "hsl_first_scene_runtime_capture.v1",
		"output_dir": ProjectSettings.globalize_path(OUTPUT_DIR),
		"canvas_size": CANVAS_SIZE,
		"capture_count": captures.size(),
		"captures": captures,
		"final_interaction_summary": RuntimeReadback.interaction_summary(scene),
		"final_runtime_contract_summary": RuntimeReadback.runtime_contract_summary(scene),
		"final_map_object_summary": map_object_summary,
		"evidence_tier": "godot-rendered-provisional",
		"claim_limit": "Godot render evidence for the current runtime only; not original visual parity.",
	}, "\t"))


func _prepare_output_dir() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute)


func _map_object_summary_matches(stage: String, summary: Dictionary) -> bool:
	if str(summary.get("schema", "")) != "hsl_first_scene_map_objects_runtime.v1":
		_fail("map object summary schema missing stage=%s actual=%s" % [stage, str(summary.get("schema", ""))])
		return false
	if int(summary.get("source_map_object_count", 0)) != 10 or int(summary.get("spawned_count", 0)) != 10:
		_fail("map object count mismatch stage=%s source=%s spawned=%s" % [stage, str(summary.get("source_map_object_count", 0)), str(summary.get("spawned_count", 0))])
		return false
	if int(summary.get("foreground_count", 0)) != 10 or int(summary.get("back_count", -1)) != 0:
		_fail("map object layer count mismatch stage=%s foreground=%s back=%s" % [stage, str(summary.get("foreground_count", 0)), str(summary.get("back_count", -1))])
		return false
	if int(summary.get("visual_blocking_candidate_count", 0)) != 6:
		_fail("map object tree blocker candidate count mismatch stage=%s actual=%s" % [stage, str(summary.get("visual_blocking_candidate_count", 0))])
		return false
	var shape_counts: Dictionary = summary.get("shape_counts", {})
	var expected_counts := {
		"tree07.SHP": 6,
		"FIRE01-01.SHP": 2,
		"bar004a.SHP": 1,
		"bar004b.SHP": 1,
	}
	for shape_id in expected_counts.keys():
		if int(shape_counts.get(shape_id, 0)) != int(expected_counts[shape_id]):
			_fail("map object shape count mismatch stage=%s shape=%s expected=%s actual=%s" % [stage, shape_id, str(expected_counts[shape_id]), str(shape_counts.get(shape_id, 0))])
			return false
	return true


func _fail(message: String) -> void:
	failures.append(message)

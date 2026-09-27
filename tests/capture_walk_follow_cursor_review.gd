extends SceneTree
## Windowed review of lane R7-CAM (docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
## walk follow; docs/evidence_packets/runtime_observations/game_cursor/README.md):
## - level 51's first enemy turn: every 4th frame of each AI walk, so the camera can be seen
##   stepping with the walker instead of gliding to the destination (compare the 2026-09-24
##   recording at 110.74–111.30 s);
## - the game cursor: GameCursor draws it into the 640×480 picture, so each of the ten shapes is
##   captured as the game draws it, pointing at the selected actor's cell centre (the pointer is
##   pushed there too, so the battle hovers the same cell); each shot checks that the hotspot
##   pixel is the red orb and that the hit-test reads that cell.
## Output: ignored/walk-follow-cursor-review/*.png + manifest.json (visual review input, not parity proof).
## Run: tools/godot.sh --script res://tests/capture_walk_follow_cursor_review.gd [-- --window=1280x960 --cursor-only --out=DIR]
## (--window sizes the window; the frames are the 640×480 root picture the window scales as one.)
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
var out := "res://ignored/walk-follow-cursor-review/"
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Walk follow／cursor review requires a rendering window")
		quit(2)
		return
	var window := Vector2i(640, 480)
	var cursor_only := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--window="):
			var size := arg.trim_prefix("--window=").split("x")
			window = Vector2i(int(size[0]), int(size[1]))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=").trim_suffix("/") + "/"
		elif arg == "--cursor-only":
			cursor_only = true
	root.title = "HSL Walk Follow Cursor Review"
	root.size = window
	create_timer(120).timeout.connect(func(): push_error("Walk follow／cursor review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(out)
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	var presentation = scene.get_node("BattlePresentation")
	var frames := 0
	while frames < 600 and (scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state != "action_menu"):
		await process_frame
		frames += 1
	await _cursor_shots(scene)
	if cursor_only:
		_finish()
		return
	scene.menus.choose_command("wait")
	var walk := 0
	var walk_frame := -1
	frames = 0
	while frames < 3600 and not (scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion()):
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		var was_previewing: bool = scene.ai_move_preview.busy()
		await process_frame
		frames += 1
		if was_previewing and not scene.ai_move_preview.busy():
			walk += 1
			walk_frame = 0
		if walk_frame >= 0:
			if scene.camera_controller.scroll_mode != "follow" and walk_frame > 0:
				walk_frame = -1
			else:
				if walk_frame % 4 == 0:
					await shot("walk%02d-f%03d" % [walk, walk_frame], {"camera": [scene.camera.position.x, scene.camera.position.y], "mode": scene.camera_controller.scroll_mode})
				walk_frame += 1
	check(walk >= 2, "the first enemy turn walked at least two AI units (%d)" % walk)
	_finish()


func _finish() -> void:
	var manifest := {"schema": "hsl_walk_follow_cursor_review.v1", "window": [root.size.x, root.size.y], "records": records, "failures": failures}
	var file := FileAccess.open(out + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print("WALK_FOLLOW_CURSOR_REVIEW shots=%d failures=%d" % [records.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func _cursor_shots(scene: Node) -> void:
	var cursor: Node = root.get_node("GameCursor")
	cursor.set_process(false)
	var coord: Vector2i = scene.unit_grid_coord(scene.selected_unit_id)
	var point: Vector2 = scene.camera_controller.grid_cell_center_to_logical(coord).floor()
	root.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	cursor.sprite.hide()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "cursor00-none.png")
	for index in range(cursor.frames.size()):
		cursor.frame_index = index
		cursor.apply_frame()
		cursor.show_at(point)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var name := "cursor%02d" % (index + 1)
		image.save_png(out + name + ".png")
		var orb := image.get_pixelv(Vector2i(point))
		check(orb.r > 0.7 and orb.g < 0.2 and orb.b < 0.2, "%s: the pointer's logical pixel is the red orb (%s)" % [name, orb])
		check(scene.camera_controller.grid_at_logical(point) == coord, "%s: the hit-test reads the pointed cell %s" % [name, coord])
		records.append({"name": name, "picture": [image.get_width(), image.get_height()], "point": [point.x, point.y], "cell": [coord.x, coord.y], "hotspot": [cursor.hotspots[index].x, cursor.hotspots[index].y]})
	cursor.sprite.hide()
	cursor.set_process(true)


func shot(name: String, extra: Dictionary = {}) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(out + name + ".png")
	var record := {"name": name}
	record.merge(extra)
	records.append(record)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

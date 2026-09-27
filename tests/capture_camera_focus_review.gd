extends SceneTree
## Windowed review of lane R7-CAMX (docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
## §1「对准落点」): every "look at this" frames its unit at the view's (320, 192) as 0x43bf30 does
## (compare the 2026-09-24 recording at 212.45 s, where the framed mage stands there), and the
## kill aftermath glides to each recipient before its EXP (0x442720 phase 0; recording 336 s).
## Level 51, one window, five moments:
## - dialogue: the product opening's first line (the speaker cut, OpeningCinematics);
## - first-control: after the opening, the first player turn's focus (enter_first_control_state);
## - select: the player re-selects its unit (select_actor → focus_camera_on_grid);
## - ai-focus: an AI turn's focus before its move preview (BattleAiMovePreview);
## - reward: the first EXP float of the battle, the recipient framed (BattleAftermath focus).
## A yellow cross marks the view's (320, 192) on a copy of each frame (`*-cross.png`).
## Output: ignored/camera-focus-review/*.png + manifest.json (visual review input, not parity proof).
## Run: tools/godot.sh --script res://tests/capture_camera_focus_review.gd
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const OUT := "res://ignored/camera-focus-review/"
const FOCUS_POINT := Vector2(320, 192)
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Camera focus review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Camera Focus Review"
	root.size = Vector2i(640, 480)
	create_timer(600).timeout.connect(func(): push_error("Camera focus review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	await _opening_dialogue()
	await _battle_moments()
	var manifest := {"schema": "hsl_camera_focus_review.v1", "focus_point": [FOCUS_POINT.x, FOCUS_POINT.y], "records": records, "failures": failures}
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	print("CAMERA_FOCUS_REVIEW shots=%d failures=%d" % [records.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


## The product opening up to its first dialogue line: the camera cuts to the speaker.
func _opening_dialogue() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	root.add_child(scene)
	current_scene = scene
	var frames := 0
	while frames < 3000 and not scene.opening_overlay.visible:
		await process_frame
		frames += 1
	check(scene.opening_overlay.visible, "the opening reached its first dialogue line")
	var records_now: Array = scene.opening_coordinator.camera_records
	var unit_id := str(records_now.back().get("unit_id", "")) if not records_now.is_empty() else ""
	await shot("dialogue", scene, unit_id)
	scene.queue_free()
	await process_frame


func _battle_moments() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	var presentation = scene.get_node("BattlePresentation")
	await _settle(scene)
	await shot("first-control", scene, scene.selected_unit_id)
	var player: String = scene.selected_unit_id
	scene.camera_controller.snap_to(scene.camera.position + Vector2(160, -120))
	scene.select_actor(player)
	await _settle(scene)
	await shot("select", scene, player)
	var ai_shot := false
	var reward_shot := false
	var frames := 0
	scene.menus.choose_command("wait")
	while frames < 20000 and not (ai_shot and reward_shot):
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		if scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion() and not presentation.combat_busy(scene.play_loop):
			scene.menus.choose_command("wait")
		var previewing: bool = scene.ai_move_preview.busy()
		var stage: String = presentation.aftermath.stage
		await process_frame
		frames += 1
		if not ai_shot and previewing and scene.ai_move_preview.busy() and not scene.camera_controller.is_scrolling():
			ai_shot = true
			await shot("ai-focus", scene, str(scene.ai_move_preview.get("_unit_id")))
		if not reward_shot and stage != "experience" and presentation.aftermath.stage == "experience":
			reward_shot = true
			var coord: Vector2i = presentation.aftermath.jobs[presentation.aftermath.cursor]["coord"]
			await shot("reward", scene, "", coord)
	check(ai_shot, "an AI turn was framed before its move preview")
	check(reward_shot, "an EXP float appeared within the frame budget (%d frames)" % frames)
	scene.queue_free()
	await process_frame


func _settle(scene: Node) -> void:
	var frames := 0
	while frames < 1200 and (scene.ai_playback_active or scene.has_actor_motion() or scene.camera_controller.is_scrolling() or scene.interaction_state != "action_menu"):
		await process_frame
		frames += 1


## `unit_id` or `coord` names the framed unit; its cell centre's view position is recorded.
func shot(name: String, scene: Node, unit_id: String, coord: Vector2i = Vector2i(-1, -1)) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT + name + ".png")
	var crossed: Image = image.duplicate()
	var scale := float(image.get_width()) / 640.0
	var point := Vector2i(FOCUS_POINT * scale)
	for offset in range(-12, 13):
		for cell in [point + Vector2i(offset, 0), point + Vector2i(0, offset)]:
			if Rect2i(Vector2i.ZERO, crossed.get_size()).has_point(cell): crossed.set_pixelv(cell, Color(1, 1, 0))
	crossed.save_png(OUT + name + "-cross.png")
	if coord == Vector2i(-1, -1) and unit_id != "" and scene.unit_grid_coords.has(unit_id):
		coord = scene.unit_grid_coords[unit_id]
	var record := {"name": name, "unit_id": unit_id, "camera": [scene.camera.position.x, scene.camera.position.y]}
	if coord != Vector2i(-1, -1):
		var view: Vector2 = scene.camera_controller.grid_cell_center_to_logical(coord)
		record["coord"] = [coord.x, coord.y]
		record["cell_centre_in_view"] = [view.x, view.y]
		record["clamped"] = scene.camera.position != scene.camera_controller.focus_centre(scene.camera_controller.grid_cell_center_world(coord))
	records.append(record)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

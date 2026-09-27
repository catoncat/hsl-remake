extends SceneTree
## Windowed review of the big-map scene at normal remake pacing: the fresh map at
## 歐姆村, a mouse-driven trip along track 1 to 戈爾山道 (into the level-2 opening
## preview and back) and home, the town screen, and an edge scroll. Output: ignored/world-map-review/*.png + manifest.json
## (visual review input, not parity proof — no original big-map frames exist).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const OUT := "res://ignored/world-map-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("World map review requires a rendering window")
		quit(2)
		return
	CampaignProgress.reset_campaign()
	root.title = "HSL World Map Review"
	root.size = Vector2i(640, 480)
	create_timer(120).timeout.connect(func(): push_error("World map review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/world/world_map_scene.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var map = scene.world_map_runtime
	check(map != null and map.active, "world map scene starts through WorldMapRuntime")
	if map == null:
		finish()
		return
	# A new game shows only 歐姆村; track 1 reveals itself (clip expansion) and 戈爾山道 appears.
	await create_timer(0.25).timeout
	await shot("00-ohm-village-track-revealing")
	await create_timer(1.0).timeout
	check(int(map.summary().get("visible_point_count", 0)) == 2 and int(map.summary().get("revealing_track_count", 0)) == 0, "the first reveal shows 戈爾山道 at the end of track 1")
	check(int(map.summary().get("completion_percent", 0)) == 4, "the status bar reads 完成度 4%")
	await shot("01-ohm-village-start")
	# Hover 戈爾山道 (point 2 at map (862,474)) so its label shows, then click it.
	var target: Vector2 = scene.logical_to_viewport_position(scene.world_to_logical_position(Vector2(862, 474)))
	await move_mouse(target)
	await shot("02-hover-gorl-pass")
	await click(target)
	await create_timer(0.35).timeout
	await shot("03-travelling-track-1")
	while is_instance_valid(map) and map.traveling:
		await process_frame
	# 戈爾山道 is a General point with no scripted event: its own event value opens
	# level 2, registered as the STORY002 opening preview — the arrival hands off and
	# the scene reloads into the preview; its end card returns here standing at point 2.
	var map_id: int = scene.get_instance_id()
	var preview = await wait_reload(map_id)
	check(preview != null and str(preview.scenario_path) == "res://content/battles/story_002.json", "arriving at 戈爾山道 enters the level-2 opening preview")
	if preview == null:
		finish()
		return
	scene = preview
	await create_timer(0.6).timeout
	await shot("04-gorl-pass-level-2-preview")
	var coordinator = preview.opening_coordinator
	check(coordinator != null and coordinator.active and coordinator.story_mode, "the preview runs through the coordinator in story mode")
	if coordinator != null:
		coordinator.walk_pixels_per_second = 3200.0
		coordinator.delay_token_seconds = 0.002
		coordinator.default_step_seconds = 0.01
	var frames := 0
	while coordinator != null and is_instance_valid(coordinator) and not coordinator.story_finished and frames < 4000:
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			await key(KEY_SPACE)
			continue
		await process_frame
		frames += 1
	check(coordinator != null and is_instance_valid(coordinator) and coordinator.story_finished, "the level-2 preview reaches its end card")
	await create_timer(0.3).timeout
	await shot("04b-level-2-preview-end-card")
	await create_timer(1.0).timeout
	await key(KEY_SPACE)
	var back = await wait_reload(preview.get_instance_id())
	check(back != null and back.world_map_runtime != null and back.world_map_runtime.active, "confirming the card returns to the 大地圖")
	if back == null:
		finish()
		return
	scene = back
	map = scene.world_map_runtime
	check(int(map.summary().get("current_point", 0)) == 2 and not bool(map.summary().get("card_visible", false)), "the party stands at 戈爾山道 with no card")
	await create_timer(1.0).timeout
	await shot("04c-back-at-gorl-pass")
	# Back to 歐姆村: the town screen (TownBG01 beside its menu) opens; Escape leaves it.
	var home: Vector2 = scene.logical_to_viewport_position(scene.world_to_logical_position(Vector2(910, 527)))
	await move_mouse(home)
	await click(home)
	while map.traveling:
		await process_frame
	await create_timer(0.3).timeout
	check(bool(map.summary().get("town_open", false)), "arriving at 歐姆村 opens the town screen")
	await shot("05-ohm-village-town-screen")
	await key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	check(not bool(map.summary().get("town_open", false)), "Escape leaves the town")
	# Edge scroll: park the pointer at the right edge for a moment.
	await move_mouse(Vector2(636, 240) * root.size.x / 640.0)
	await create_timer(1.2).timeout
	check(scene.camera.position.x > 911.0, "the right edge scrolls the map")
	await shot("06-edge-scrolled-east")
	finish()


func move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func click(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	Input.parse_input_event(press)
	await create_timer(0.05).timeout
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.05).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	var summary: Dictionary = scene.world_map_runtime.summary() if scene.world_map_runtime != null else {"scenario_path": str(scene.scenario_path)}
	records.append({"capture": label, "camera": scene.camera.position, "summary": {
		"current_point": summary.get("current_point", 0),
		"traveling": summary.get("traveling", false),
		"card_kind": summary.get("card_kind", ""),
		"town_open": summary.get("town_open", false),
		"scenario_path": summary.get("scenario_path", "res://content/world/world_map_scene.json"),
	}})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


## reload_current_scene frees the old scene asynchronously; compare instance ids.
func wait_reload(previous_id: int) -> Node:
	var waited := 0
	while waited < 240:
		var current = current_scene
		if current != null and is_instance_valid(current) and current.get_instance_id() != previous_id:
			await process_frame
			await process_frame
			return current
		await process_frame
		waited += 1
	return null


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"records": records, "failures": failures, "summary": scene.world_map_runtime.summary() if scene.world_map_runtime != null else {}}, "  "))
		manifest.close()
	if failures.is_empty():
		print("WORLD_MAP_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("WORLD_MAP_REVIEW_FAIL count=%d" % failures.size())
		quit(1)

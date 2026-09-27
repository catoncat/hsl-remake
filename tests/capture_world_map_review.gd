extends SceneTree
## Windowed review of the big-map scene at normal remake pacing: the fresh map at
## 歐姆村, the town screen, an edge scroll there and back, and a mouse-driven trip along
## track 1 to 戈爾山道 into the level-2 battle. Output: ignored/world-map-review/*.png + manifest.json
## (visual review input, not parity proof — no original big-map frames exist).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
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
	# The reveal runs until reveal_busy clears (clicks meanwhile are dropped_while_revealing).
	var waited := 0.0
	while (bool(map.summary().get("reveal_busy", false)) or int(map.summary().get("revealing_track_count", 0)) > 0) and waited < 5.0:
		await create_timer(0.05).timeout
		waited += 0.05
	await create_timer(0.3).timeout
	check(int(map.summary().get("visible_point_count", 0)) == 2 and int(map.summary().get("revealing_track_count", 0)) == 0, "the first reveal shows 戈爾山道 at the end of track 1")
	check(int(map.summary().get("completion_percent", 0)) == 4, "the status bar reads 完成度 4%")
	await shot("01-ohm-village-start")
	# 歐姆村 first: the town screen (TownBG01 beside its menu) opens on a click; Escape leaves it.
	var home: Vector2 = RuntimeReadback.logical_to_viewport_position(scene, scene.world_to_logical_position(Vector2(910, 527)))
	await move_mouse(home)
	await click(home)
	await create_timer(0.3).timeout
	check(bool(map.summary().get("town_open", false)), "clicking 歐姆村 opens the town screen")
	await shot("05-ohm-village-town-screen")
	await key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	check(not bool(map.summary().get("town_open", false)), "Escape leaves the town")
	# Edge scroll: park the pointer at the right edge for a moment, then at the left edge to come back.
	await move_mouse(Vector2(636, 240) * root.size.x / 640.0)
	await create_timer(1.2).timeout
	check(scene.camera.position.x > 911.0, "the right edge scrolls the map")
	await shot("06-edge-scrolled-east")
	await move_mouse(Vector2(4, 240) * root.size.x / 640.0)
	var back_waited := 0.0
	while scene.camera.position.x > 910.0 and back_waited < 4.0:
		await create_timer(0.05).timeout
		back_waited += 0.05
	await move_mouse(Vector2(320, 240) * root.size.x / 640.0)
	await create_timer(0.3).timeout
	# Hover 戈爾山道 (point 2 at map (862,474)) so its label shows, then click it.
	var target: Vector2 = RuntimeReadback.logical_to_viewport_position(scene, scene.world_to_logical_position(Vector2(862, 474)))
	await move_mouse(target)
	await shot("02-hover-gorl-pass")
	# The arrival may reload the scene before the travelling shot: keep the map's id first.
	var map_id: int = scene.get_instance_id()
	await click(target)
	await create_timer(0.35).timeout
	if is_instance_valid(scene) and is_instance_valid(map) and map.traveling:
		await shot("03-travelling-track-1")
	# 戈爾山道's event value opens level 2: the arrival hands off and the scene reloads into the
	# level-2 battle (gol_road_battle.json; the STORY002 opening plays inside it).
	var battle = await wait_reload(map_id)
	check(battle != null and str(battle.scenario_path) == "res://content/battles/gol_road_battle.json", "arriving at 戈爾山道 enters the level-2 battle")
	if battle == null:
		finish()
		return
	scene = battle
	await create_timer(0.6).timeout
	await shot("04-gorl-pass-level-2-battle")
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
	if not is_instance_valid(scene):
		return  # the arrival reloaded the scene meanwhile
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

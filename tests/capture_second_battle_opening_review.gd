extends SceneTree
## Windowed review of the level-52 product opening at normal remake pacing.
## Output: ignored/second-battle-opening-review/*.png + manifest.json (visual review input, not parity proof).
const OUT := "res://ignored/second-battle-opening-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []
var shots_taken: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Second battle opening review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Second Battle Opening Review"
	root.size = Vector2i(640, 480)
	create_timer(150).timeout.connect(func(): push_error("Second battle opening review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_052.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	check(coordinator != null and coordinator.active, "product opening starts through BattleOpeningCoordinator")
	if coordinator == null:
		finish()
		return
	await shot("00-emperor-framed")
	var start_time := Time.get_ticks_msec()
	while coordinator.active:
		var current: Dictionary = coordinator.summary()
		var event_id := str(current.get("current_event_id", ""))
		var kind := str(current.get("current_event_kind", ""))
		if kind == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			await shot_once("dialogue-" + message_id)
			await key(KEY_SPACE)
			continue
		if kind == "actor_walk_disp_wait" and str(scene.scene_timeline.current_event().get("actor_token", "")) == "SID_PLAYER0":
			await create_timer(0.6).timeout
			await shot_once("party-walk-up")
		elif kind == "inserted_object_walk_disp_wait" and event_id.begins_with("story052_29_"):
			await create_timer(0.8).timeout
			await shot_once("guards-enter-left")
		elif kind == "inserted_object_walk_disp_wait" and event_id.begins_with("story052_47_"):
			await create_timer(0.8).timeout
			await shot_once("guards-enter-lower")
		elif kind == "section_title_resource":
			await create_timer(0.35).timeout
			await shot_once("section-title")
		await process_frame
	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	while scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state == "ai_resolving":
		await process_frame
	await create_timer(0.4).timeout
	await shot("first-control")
	check(scene.interaction_state == "action_menu", "opening hands off to the shared action menu")
	check(shots_taken.size() >= 16, "every dialogue and key stage was captured (%d)" % shots_taken.size())
	records.append({"case": "second_battle_product_opening", "elapsed_seconds": elapsed,
		"summary": coordinator.summary(), "selected_unit": scene.selected_unit_id, "round": scene.play_loop.get("round", 0)})
	finish()


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_second_battle_opening_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("SECOND_BATTLE_OPENING_REVIEW_PASS shots=%d output=%s" % [shots_taken.size(), OUT])
		quit(0)
	else:
		print("SECOND_BATTLE_OPENING_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


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


func shot_once(label: String) -> void:
	if shots_taken.has(label):
		return
	await shot(label)


func shot(label: String) -> void:
	shots_taken[label] = true
	await create_timer(0.12).timeout
	records.append({"capture": label, "interaction": scene.interaction_state, "camera": scene.camera.position,
		"event": scene.scene_timeline.current_event().get("id", ""), "motion": scene.has_actor_motion()})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

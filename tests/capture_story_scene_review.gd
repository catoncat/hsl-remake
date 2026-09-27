extends SceneTree
## Windowed review of a story-only scene (level 58 epilogue by default; `-- --level=60`
## for the second throne-hall scene, `-- --level=53` for the escape opening preview,
## `-- --level=1` for the 歐姆村 opening preview, `-- --level=2|3|5|6|7` for 戈爾山道／盜賊洞窟／呼嘯平原／席達鎮／寧靜之森, `-- --level=8|9|65` for 菲納斯河畔／廢都／廢都村民,
## `-- --level=55|56|61|62|64` for the post-battle camp talks and `-- --level=63` for the throne-hall report) at normal remake pacing.
## A preview whose card offers 略過戰鬥（視為勝利） is also captured with the second row highlighted.
## Output: ignored/story-scene-<level>-review/*.png + manifest.json (visual review input, not parity proof).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
var level := 58
var OUT := "res://ignored/story-scene-058-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []
var shots_taken: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Story scene review requires a rendering window")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = int(arg.trim_prefix("--level="))
	OUT = "res://ignored/story-scene-%03d-review/" % level
	CampaignProgress.reset_campaign()
	root.title = "HSL Story Scene %03d Review" % level
	root.size = Vector2i(640, 480)
	create_timer(240).timeout.connect(func(): push_error("Story scene review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/story_%03d.json" % level
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	check(coordinator != null and coordinator.active and coordinator.story_mode, "story scene starts through BattleOpeningCoordinator in story mode")
	if coordinator == null:
		finish()
		return
	var framed_label: String = {53: "00-tower-framed", 1: "00-village-framed", 2: "00-road-framed", 3: "00-cave-framed", 5: "00-plain-framed", 6: "00-town-gate-framed", 7: "00-forest-framed", 8: "00-riverside-framed", 9: "00-ruins-framed", 65: "00-interior-framed", 55: "00-camp-dusk-framed", 56: "00-camp-morning-framed", 61: "00-camp-framed", 62: "00-camp-framed", 64: "00-camp-framed", 901: "00-riverside-framed"}.get(level, "00-scene-framed")
	await shot(framed_label)
	var start_time := Time.get_ticks_msec()
	var star_shot := false
	var min_dialogue: int = {53: 6, 1: 28, 2: 8, 3: 6, 5: 3, 6: 3, 7: 3, 8: 6, 9: 5, 10: 17, 12: 11, 65: 16, 55: 29, 56: 10, 61: 12, 62: 13, 63: 16, 64: 18, 901: 3}.get(level, 1)  # levels without a curated floor only need a paged line
	var final_summary: Dictionary = {}
	while is_instance_valid(coordinator) and coordinator.active and not coordinator.story_finished:
		final_summary = coordinator.summary()
		var current: Dictionary = final_summary
		var kind := str(current.get("current_event_kind", ""))
		var event: Dictionary = scene.scene_timeline.current_event()
		if not (current.get("select_options", []) as Array).is_empty():
			# actSelectInsertEvent prompt (STORY073 / 900): capture it, take the first row.
			await shot_once("select-prompt")
			await key(KEY_ENTER)
			continue
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			# actEnterStorageWindow (STORY057 / 081): capture the 整理裝備 screen, then Esc.
			await shot_once("storage-window")
			await key(KEY_ESCAPE)
			continue
		if kind == "dialogue_message_id":
			await shot_once("dialogue-" + str(event.get("message_id", "")))
			await key(KEY_SPACE)
			continue
		if kind == "actor_walk_wait":
			await create_timer(0.9).timeout
			await shot_once("walk-" + str(event.get("id", "")).right(2) + "-" + str(event.get("actor_token", "")).to_lower())
		elif kind == "actor_walk" and level == 2 and str(event.get("actor_token", "")) == "SID_ENEMY028":
			await create_timer(0.9).timeout
			await shot_once("raiders-run")
		elif kind == "actor_walk_disp_wait" and str(event.get("actor_token", "")) in ["SID_ENEMY028", "SID_ENEMY036", "SID_琥"]:
			await create_timer(0.9).timeout
			await shot_once("march-" + str(event.get("actor_token", "")).to_lower().trim_prefix("sid_"))
		elif kind in ["actor_walk_and_delete", "actor_walk_and_delete_wait"]:
			await create_timer(0.9).timeout
			await shot_once("leaving")
		elif kind == "sound_effect" and not star_shot:
			star_shot = true
			await shot_once("lightning-strike" if level in [10, 12] else "medal-thrown")
		elif kind == "story_object_insert" and level == 12 and str(event.get("args", [""])[0]) == "obj_Story_Level_RainSound":
			await create_timer(0.4).timeout
			await shot_once("effect-storm-deck")
		elif kind == "story_object_insert" and level == 10 and str(event.get("args", [""])[0]) in ["obj_Story_Level10_Ring", "obj_Story_Level10_Fire", "obj_Story_Level10_RainBoss"]:
			# Effect readings: the glow right after the strike, the burning tree with its
			# 火01 embers, the first rain controller (drops need a moment to fall in).
			await create_timer(0.35 if str(event.get("args", [""])[0]) == "obj_Story_Level10_RainBoss" else 0.05).timeout
			await shot_once("effect-" + str(event.get("args", [""])[0]).trim_prefix("obj_Story_Level10_").to_lower())
		elif kind == "actor_walk_follow_wait":
			await create_timer(0.8).timeout
			await shot_once("escort-follows")
		elif kind == "screen_darken":
			await create_timer(0.85).timeout
			await shot_once("dark-screen")
		elif kind == "actor_move_disp_wait":
			await create_timer(1.2).timeout
			await shot_once("rope-climb")
		elif kind == "inserted_object_walk_disp_wait":
			await create_timer(0.6).timeout
			await shot_once("guard-enters-" + str(event.get("id", "")).right(2))
		elif kind == "camera_position_target" and coordinator.story_objects._position_markers.size() > 0:
			await create_timer(0.7).timeout
			await shot_once("escape-zone-marked")
		elif kind == "section_title_resource":
			await create_timer(0.5).timeout
			await shot_once("section-title")
		await process_frame
	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	await create_timer(0.3).timeout
	# A scene that hands off (next scenario or the big map) reloads the current
	# scene at once, freeing this one: the end frame is then the scene it opened.
	var handed_off := not is_instance_valid(scene) or not is_instance_valid(coordinator)
	if handed_off:
		await process_frame
		await process_frame
		scene = current_scene
		await create_timer(1.0).timeout
	var ended_on_card := not handed_off and scene.get_node_or_null("UI/ChapterEndCard") != null
	await shot("chapter-end-card" if ended_on_card else "scene-end-handoff")
	if ended_on_card and not (coordinator.summary().get("end_card_options", []) as Array).is_empty():
		# The two-row choice: highlight the plain return as well (Down), then restore.
		await key(KEY_DOWN)
		await shot("chapter-end-card-row2")
		await key(KEY_UP)
	check(handed_off or coordinator.story_finished, "story scene reaches its end marker")
	check(ended_on_card or handed_off or CampaignProgress.has_pending(), "scene end shows the chapter-end card or hands off to the next scenario")
	var dialogue_count := 0
	for label in shots_taken:
		if str(label).begins_with("dialogue-"):
			dialogue_count += 1
	var curated: bool = level in [53, 1, 2, 3, 5, 6, 7, 8, 9, 10, 12, 65, 55, 56, 61, 62, 63, 64, 901]
	check(dialogue_count >= min_dialogue and shots_taken.size() >= dialogue_count + (3 if curated else 2), "every dialogue and key stage was captured (%d)" % shots_taken.size())
	records.append({"case": "story_scene_%03d" % level, "elapsed_seconds": elapsed, "summary": coordinator.summary() if is_instance_valid(coordinator) else final_summary, "handed_off": handed_off})
	finish()


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_story_scene_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("STORY_SCENE_REVIEW_PASS shots=%d output=%s" % [shots_taken.size(), OUT])
		quit(0)
	else:
		print("STORY_SCENE_REVIEW_FAIL count=%d" % failures.size())
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
	var event_id: String = str(scene.scene_timeline.current_event().get("id", "")) if scene.scene_timeline != null else ""
	records.append({"capture": label, "camera": scene.camera.position, "event": event_id, "motion": scene.has_actor_motion()})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

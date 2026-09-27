extends SceneTree
## Windowed review of the campaign resume prompt: a fresh launch of the first battle
## with a persisted position (story 058) offers 繼續／重新開始; accepting reloads into
## the saved scenario. Output: ignored/campaign-resume-review/*.png + manifest.json.
const OUT := "res://ignored/campaign-resume-review/"
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Campaign resume review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Campaign Resume Review"
	root.size = Vector2i(640, 480)
	create_timer(60).timeout.connect(func(): push_error("Campaign resume review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.reset_campaign()
	var carry := {"schema": "hsl_campaign_carry.v1", "units": {"leonard": {"actor_id": "001", "level": 3, "exp": 0, "pending_stat_points": 0, "equipment": [], "weapon_code": 0, "inventory": [], "kill_count": 4, "attributes": {"str": 9, "dex": 8, "mind": 6, "con": 8}}}, "loop": {"gold": 120}}
	CampaignProgress.save_progress({"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_058.json", "carry": carry, "from_scenario_id": "battle_002_level52"})
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	check(bool(scene.campaign_progress.summary().get("resume_prompt_visible", false)), "resume prompt shows over the paused first-battle opening")
	check(paused, "tree pauses under the prompt")
	await shot("01-resume-prompt")
	var button: Button = scene.campaign_progress.resume_button
	await click(button.global_position + button.size * 0.5)
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	var reloaded = current_scene
	check(reloaded != scene and reloaded != null and str(reloaded.scenario_path) == "res://content/battles/story_058.json", "clicking 繼續 reloads into the saved story scene")
	check(not paused, "tree runs again after the reload")
	await shot("02-resumed-story-scene")
	finish()


func click(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	Input.parse_input_event(press)
	await create_timer(0.05).timeout
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_campaign_resume_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	CampaignProgress.reset_campaign()
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("CAMPAIGN_RESUME_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("CAMPAIGN_RESUME_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	RenderingServer.force_draw(false)
	records.append({"capture": label})
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

extends SceneTree

## Windowed review captures for the map-staging classes (lane R5-L4): opening positions
## (level 1 歐姆村 at first control), story objects and walkable terrain (level 53 rope while
## it unrolls, 緹娜 at first control), the opening camera (level 6 as the party enters) and
## scripted retreat walks (level 6 captain down), plus a same-class story object (level 10
## 樹03 on the struck tree's anchor). Saves the game viewport only (never the desktop) to
## the directory given after `--` (default user://map_staging_review). Not a gate suite:
## the pictures are for manual acceptance.
##   tools/godot.sh --script res://tests/capture_map_staging_review.gd -- /abs/output/dir

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")

var output := "user://map_staging_review"
var failures: Array[String] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("_run")


func _note(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	await _level_1()
	await _level_53()
	await _level_6()
	await _level_10()
	for failure in failures:
		push_warning(failure)
	print("MAP_STAGING_REVIEW_DONE dir=%s notes=%d" % [output, failures.size()])
	quit(0)


func _boot(path: String) -> Node:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [output, name])
	print("MAP_STAGING_REVIEW_SHOT %s" % name)


func _free(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


## Plays the opening at the script's own pace, clicking through dialogue, until `stop`
## (a Callable on the coordinator) holds or first control.
func _play_until(scene: Node, stop: Callable, frames: int = 20000) -> void:
	var coordinator = scene.opening_coordinator
	for _frame in range(frames):
		if coordinator == null or not coordinator.active or stop.call(coordinator):
			return
		if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
		await process_frame


func _level_1() -> void:
	var scene = await _boot("res://content/battles/ohm_village_battle.json")
	await _play_until(scene, func(_c): return false)
	await _shot("level01_first_control")
	await _free(scene)


func _level_53() -> void:
	var scene = await _boot("res://content/battles/battle_053.json")
	var unrolling := func(coordinator) -> bool:
		for record in coordinator.story_records:
			if str(record.get("symbol", "")) == "obj_Story_Level53_Rope":
				return true
		return false
	await _play_until(scene, unrolling)
	for _frame in range(45):
		await process_frame
	await _shot("level53_rope_unrolling")
	await _play_until(scene, func(c): return str(c.summary().get("current_event_kind", "")) == "actor_move_disp_wait")
	for _frame in range(30):
		await process_frame
	await _shot("level53_rope_slide")
	await _play_until(scene, func(_c): return false)
	var tina: Node = scene.actor_node_for_unit("tina")
	if tina != null:
		scene.camera.position = scene.camera_controller.clamped_position(tina.position + Vector2(0, -120))
	await _shot("level53_first_control_shaft")
	await _free(scene)


func _level_6() -> void:
	var scene = await _boot("res://content/battles/battle_006.json")
	await _play_until(scene, func(c): return c.motion_records.size() >= 4)
	for _frame in range(40):
		await process_frame
	await _shot("level06_opening_party_enters")
	await _play_until(scene, func(_c): return false)
	var rules = scene.BattlePlayLoop
	scene.set_process(false)
	var loop: Dictionary = rules.copy(scene.play_loop)
	loop["fail_statuses"] = []
	rules._set_unit_defeated(loop, "guard024_1", true)
	loop = rules._resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(loop))
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var coordinator = scene.opening_coordinator
	var retreat_started := -1
	for frame in range(3000):
		await process_frame
		if coordinator.active and coordinator.cutscene_mode:
			if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
				coordinator.handle_input(ForceWin.click())
			var walking: bool = coordinator.motion_records.any(func(r): return str(r.get("source_event_id", "")).begins_with("winfail006_win_0") and str(r.get("kind", "")) == "walk")
			if walking and retreat_started < 0:
				retreat_started = frame
			if retreat_started >= 0 and frame - retreat_started in [30, 70, 110]:
				scene.camera.position = scene.camera_controller.clamped_position(Vector2(720, 720))
				await _shot("level06_retreat_%03d" % (frame - retreat_started))
			if retreat_started >= 0 and frame - retreat_started > 110:
				break
	_note(retreat_started >= 0, "level 6: the retreat started")
	await _free(scene)


func _level_10() -> void:
	var scene = await _boot("res://content/battles/story_010.json")
	await _play_until(scene, func(c): return c.story_finished)
	scene.camera.position = scene.camera_controller.clamped_position(Vector2(528, 360))
	await _shot("level10_tree03_on_struck_tree")
	await _free(scene)

extends SceneTree
## Windowed review of the level-52 event1 reinforcement entrance: the interpreter fires
## WINFAIL052 event 1 (fewer than two 021 alive), ScriptActorCreationRules births the four
## obj_Story_Level52_Enemy21 script actor templates at their off-map insert pixels and the
## event cutscene walks each one to its actWalkPrevInsertObjectWait cell. Output:
## ignored/second-battle-reinforcement-review/*.png + manifest.json (visual review input,
## not parity proof).
const OUT := "res://ignored/second-battle-reinforcement-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Second battle reinforcement review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Second Battle Reinforcement Review"
	root.size = Vector2i(640, 480)
	create_timer(60).timeout.connect(func(): push_error("Second battle reinforcement review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_052.json"
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	while scene.ai_playback_active or scene.has_actor_motion() or scene.interaction_state == "ai_resolving":
		await process_frame
	var coordinator = scene.opening_coordinator
	check(coordinator != null and not coordinator.active, "dev first control leaves the coordinator attached but inactive")
	# Fire event1 through the interpreter: defeat every 021 but one (actCheckEnemyNumber
	# SID_ENEMY021 2 is a strict compare), run the round hooks and let the PlayLoop's outcome
	# boundary commit the script actor transaction, then watch the cutscene walk them in.
	var alive: Array = scene.play_loop["units"].filter(func(unit): return str(unit.get("class_id", "")) == "Enemy021" and int(unit.get("hp", 0)) > 0)
	for index in range(alive.size() - 1):
		scene.BattlePlayLoop.set_unit_defeated(scene.play_loop, str(alive[index]["id"]), true)
	scene.play_loop["turn"] = 2
	scene.apply_loop(scene.BattlePlayLoop.resolve_outcome(scene.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
	var recruits: Array = scene.play_loop["units"].filter(func(unit): return str(unit["id"]).begins_with("Enemy021_script_"))
	check(recruits.size() == 4, "event1 creates four script actor recruits (%d)" % recruits.size())
	var cells := [Vector2i(7, 38), Vector2i(12, 38), Vector2i(4, 30), Vector2i(14, 30)]
	var landed: Array = []
	for recruit in recruits:
		landed.append(recruit["coord"])
	check(landed == cells, "recruits land on the actWalkPrevInsertObjectWait cells %s" % str(landed))
	scene.camera.position = scene.camera_controller.clamped_position(scene.camera_controller.grid_cell_center_world(Vector2i(9, 34)))
	var frames := 0
	while frames < 240 and not coordinator.cutscene_mode:
		await process_frame
		frames += 1
	check(coordinator.cutscene_mode and coordinator.cutscene_key == "event_1", "the fired event1 starts its cutscene")
	# The chain is sequential (each actWalkPrevInsertObjectWait blocks): frame 00 is the first
	# recruit revealed at its bottom-edge insert pixel (227,1356), frame 01 its walk up.
	var revealed := 0
	frames = 0
	while frames < 600 and revealed < 1:
		revealed = coordinator.story_records.filter(func(record): return str(record.get("kind", "")) == "script_actor_revealed").size()
		await process_frame
		frames += 1
	await shot("00-inserted-at-edges")
	await create_timer(0.35).timeout
	await shot("01-walking-in")
	frames = 0
	while frames < 3000 and coordinator.active:
		await process_frame
		frames += 1
	check(not coordinator.active, "the event1 cutscene finishes")
	frames = 0
	while frames < 600 and scene.has_actor_motion():
		await process_frame
		frames += 1
	await shot("02-arrived")
	check(not scene.has_actor_motion(), "entrance walks finish")
	var entrances: Array = []
	for index in range(recruits.size()):
		var recruit: Dictionary = recruits[index]
		var actor = scene.actor_node_for_unit(str(recruit["id"]))
		var target: Vector2 = scene.camera_controller.grid_cell_center_world(recruit["coord"])
		check(actor != null and actor.visible and actor.position.is_equal_approx(target), "recruit %s stands on its PlayLoop cell" % str(recruit["id"]))
		var transaction: Dictionary = scene.play_loop["script_actor_transactions"][0]
		for row in transaction["actions"]:
			if (row as Dictionary).get("install", {}).get("unit_id", "") == recruit["id"]:
				entrances.append({"unit_id": recruit["id"], "insert_pixel": (row as Dictionary)["install"]["position"], "cell": recruit["coord"], "target_world": target})
	records.append({"case": "second_battle_reinforcement_entrance", "trigger": "winfail052 event_1 via run_event_hooks + _resolve_outcome", "entrances": entrances})
	finish()


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_second_battle_reinforcement_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("SECOND_BATTLE_REINFORCEMENT_REVIEW_PASS output=%s" % OUT)
		quit(0)
	else:
		print("SECOND_BATTLE_REINFORCEMENT_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	records.append({"capture": label, "camera": scene.camera.position, "motion": scene.has_actor_motion()})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

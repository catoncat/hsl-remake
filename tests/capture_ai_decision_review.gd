extends SceneTree
## Two bounded routes through real Wait controls and the live AI/presentation loop.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_ai_decision_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/ai-decision-review/"
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("AI visual review requires a rendering window")
		quit(2)
		return
	root.title = "HSL AI Decision Review"
	root.size = Vector2i(640, 480)
	create_timer(55.0).timeout.connect(func(): push_error("Bounded AI review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	for owner in ["enemy026_1", "leonard"]:
		await route(owner)
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "real_control_events": true,
		"input": "Viewport.push_input; actual Wait button, no desktop mouse or direct AI execution",
		"overrides": "Four-actor queue/positions and 400HP; 026 magic preference100 for visual route, source95 separately tested; LeonardST60; counterattack0",
		"window_position": root.position, "window_size": root.size, "routes": records, "failures": failures}, "  "))
	print("AI_DECISION_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func route(owner: String) -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var fixture := Cases.live_fixture(owner)
	var first := Loop.unit(fixture, "enemy023_1")
	first["id"] = "review-initial"
	first["coord"] = Vector2i(1, 1)
	first["live_speed"] = 110
	fixture["units"].append(first)
	for unit in fixture["units"]: unit["coord"] += Vector2i(5, 5)
	# Replace the harness roster's presentation nodes for this isolated fixture.
	for child in scene.actors_root.get_children():
		scene.actors_root.remove_child(child)
		child.queue_free()
	if owner == "leonard": Loop._unit(fixture, owner)["stamina"] = 60
	else: TestSuite.own(fixture, "ai_profiles")["actors"]["026"]["profile"]["ai_att_magic"] = 100
	fixture["turn_queue"] = Loop.CoreTurnQueue.rebuild(fixture["units"])
	scene.apply_loop(Loop._return_to_player(fixture, first["id"]), "test")
	scene.interaction_state = scene.play_loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(Vector2i(9, 8))
	scene._process(0.0)
	await create_timer(0.35).timeout
	var button: Control = scene.action_menu.get_node("WaitCommand")
	check(button.is_visible_in_tree(), "Wait is available for the actual initial player")
	var position := button.get_global_rect().get_center()
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	scene.set_process(true)
	var impact_saved := false
	var settled := false
	for _attempt in range(420):
		await create_timer(0.04).timeout
		var presentation = scene.get_node("BattlePresentation")
		var capture_time: float = presentation.cutin.Timing.CAST_LEAD_IN + 1.4 if owner == "enemy026_1" else 0.7
		if presentation.cutin.busy() and presentation.cutin.elapsed >= capture_time and not impact_saved:
			await shot(owner + "-cast")
			impact_saved = true
		if scene.selected_unit_id == "enemy023_1" and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion() and not presentation.cutin.busy() and not presentation.has_pending_combat(scene.play_loop):
			settled = true
			break
	check(settled and impact_saved, "AI cast visibly resolves and hands to next player: " + owner)
	var receipt: Dictionary = scene.play_loop.get("last_ai_action", {})
	check(receipt.get("actor_id") == owner and receipt.has("skill_id") and receipt.has("ai_decision"), "visible AI used source selection and shared skill receipt")
	check(scene.play_loop["last_ai_actions"].size() == 1 and scene.play_loop["turn_queue"]["index"] == 2, "no repeated AI cast or skipped successor")
	await shot(owner + "-handoff")
	records.append({"owner": owner, "skill_id": receipt.get("skill_id"), "resource_payment": receipt.get("resource_payment"),
		"target": receipt.get("defender_id"), "decision": receipt.get("ai_decision"), "next_actor": scene.selected_unit_id,
		"queue_index": scene.play_loop["turn_queue"]["index"], "visible_cast": impact_saved, "handoff": settled})
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "capture " + name)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

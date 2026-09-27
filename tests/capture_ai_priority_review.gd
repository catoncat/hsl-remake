extends SceneTree
## Real Wait controls trigger normal-clock self medicine and wounded-foe offense.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_ai_priority_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/ai-priority-review/"
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("AI priority visual review requires a rendered window")
		quit(2)
		return
	root.title = "HSL AI Priority Review"
	root.size = Vector2i(640, 480)
	create_timer(55.0).timeout.connect(func(): push_error("Bounded AI priority review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	for route_name in ["self-medicine", "wounded-melee", "wounded-magic"]:
		await route(route_name)
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "real_control_events": true,
		"input": "Viewport.push_input on the actual Wait button; normal Runtime AI and clock; no desktop mouse or direct AI-step mutation",
		"overrides": "Five-actor synthetic queue and positions, HP400 healthy/8 wounded/4 self recovery; two carried medicines only in self case; counter0; 026 magic tendency100 for deterministic visible class, native95 separately tested",
		"window_position": root.position, "window_size": root.size, "routes": records, "failures": failures}, "  "))
	print("AI_PRIORITY_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func route(route_name: String) -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var owner := "enemy026_1" if route_name == "wounded-magic" else "enemy021_1"
	var fixture := Cases.recovery_fixture() if route_name == "self-medicine" else Cases.opportunity_fixture(owner)
	var first := Loop.unit(fixture, "enemy023_1")
	first.merge({"id": "review-initial", "coord": Vector2i(2, 5), "live_speed": 110}, true)
	fixture["units"].append(first)
	Loop._unit(fixture, "enemy023_1")["coord"] = Vector2i(6, 6)
	for unit in fixture["units"]:
		unit["coord"] += Vector2i(5, 5)
		unit["grid_coord"] = unit["coord"]
	for child in scene.actors_root.get_children():
		scene.actors_root.remove_child(child)
		child.queue_free()
	if owner == "enemy026_1": TestSuite.own(fixture, "ai_profiles")["actors"]["026"]["profile"]["ai_att_magic"] = 100
	fixture["turn_queue"] = Loop.CoreTurnQueue.rebuild(fixture["units"])
	scene.apply_loop(Loop._return_to_player(fixture, first["id"]), "test")
	scene.interaction_state = scene.play_loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(Vector2i(9, 8))
	scene._process(0.0)
	await create_timer(0.35).timeout
	var button: Control = scene.action_menu.get_node("WaitCommand")
	check(button.is_visible_in_tree(), "actual Wait is available: " + route_name)
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	scene.set_process(true)
	var visible_effect := false
	var settled := false
	var feedback_text := ""
	for _attempt in range(500):
		await create_timer(0.025).timeout
		var presentation = scene.get_node("BattlePresentation")
		if route_name == "self-medicine" and presentation.item_feedback_busy():
			check(scene.ai_playback_active and not scene.action_menu.is_visible_in_tree(), "medicine feedback retains AI presentation before next player's controls")
			if not visible_effect:
				var effect: Dictionary = scene.play_loop["last_item_use"]
				feedback_text = presentation.get_node("ItemUseHeal").text
				check(feedback_text == "%d" % int(effect["restored_hp"]), "visible medicine amount matches settled receipt")
				var saved: Dictionary = scene.play_loop.duplicate(true)
				check(not presentation.show_item_use(effect, Vector2.ZERO), "duplicate receipt cannot replay medicine feedback")
				check(scene.play_loop == saved, "feedback never changes battle state")
				await shot(route_name + "-effect")
				visible_effect = true
		elif route_name != "self-medicine" and not visible_effect:
			var moment: float = presentation.cutin.Timing.CAST_LEAD_IN + 0.4 if owner == "enemy026_1" else 0.5
			if presentation.cutin.busy() and presentation.cutin.elapsed >= moment:
				check(not scene.action_menu.is_visible_in_tree(), "wounded-foe offense finishes before next controls")
				await shot(route_name + "-effect")
				visible_effect = true
		if scene.selected_unit_id == "enemy023_1" and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion() and not presentation.cutin.busy() and not presentation.has_pending_combat(scene.play_loop) and not presentation.item_feedback_busy():
			settled = true
			break
	check(settled and visible_effect, "visible effect and player handoff complete: " + route_name)
	var action: Dictionary = scene.play_loop.get("last_ai_action", {})
	check(action.get("actor_id") == owner and action.get("ai_decision", {}).get("priority", {}).get("kind") == ("use_item" if route_name == "self-medicine" else "dying"), "rendered AI used intended source-backed priority")
	check(scene.play_loop["last_ai_actions"].size() == 1 and scene.play_loop["turn_queue"]["index"] == 2, "one AI receipt and exact successor handoff")
	if route_name != "self-medicine": check(action.get("defender_id") == "priority-wounded", "actual offense targets wounded foe")
	if route_name == "self-medicine":
		check(Loop.unit(scene.play_loop, owner)["hp"] == 44 and Loop.unit(scene.play_loop, owner)["inventory"].count(241) == 1, "visible self recovery settles exactly one medicine")
	elif owner == "enemy026_1":
		check(action.has("skill_id") and Loop.unit(scene.play_loop, owner)["mp"] == 30 - int(action["resource_payment"]["amount"]), "visible magic pays the one receipt amount")
	await create_timer(0.3).timeout
	check(scene.action_menu.is_visible_in_tree(), "successor menu is visible after feedback")
	await shot(route_name + "-handoff")
	records.append({"route": route_name, "owner": owner, "action": action,
		"owner_after": Loop.unit(scene.play_loop, owner), "visible_effect": visible_effect, "feedback_text": feedback_text,
		"next_actor": scene.selected_unit_id, "handoff": settled, "queue_index": scene.play_loop["turn_queue"]["index"]})
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

extends SceneTree
## Actual Wait input, normal runtime movement/casting/feedback and player handoff.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_ai_skill_tests.gd")
const Fixtures = preload("res://tests/run_ai_decision_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/ai-skill-review/"
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("AI skill visual review needs a rendered window")
		quit(2)
		return
	root.title = "HSL AI Skill Review"
	root.size = Vector2i(640, 480)
	create_timer(75.0).timeout.connect(func(): push_error("AI skill review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	var keys: Array = ["fire", "wind", "poison"] if OS.get_cmdline_user_args().is_empty() else Array(OS.get_cmdline_user_args())
	for key in keys:
		if key not in ["fire", "wind", "poison"]:
			push_error("Unknown AI skill review route: " + str(key))
			quit(2)
			return
		await route(key)
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "real_control_events": true,
		"input": "Viewport mouse events on actual Wait; normal Runtime AI and timers",
		"overrides": "Synthetic positions, HP400, speed queue and commandable successor; real scene WRD blocking; magic tendency100; selected spell use_ratio100 and other spell0. Poison uses source actor025 on an isolated test roster. No RNG replacement, damage/result assignment or time acceleration.",
		"screen": root.current_screen, "window_position": root.position, "window_size": root.size,
		"routes": records, "failures": failures}, "  "))
	print("AI_SKILL_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func route(key: String) -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var fixture := Cases.area_fixture() if key == "poison" else Fixtures.live_fixture()
	fixture["tiles"] = scene.play_loop["tiles"]
	fixture["map_size"] = scene.play_loop["map_size"]
	var caster := Loop._unit(fixture, "enemy026_1")
	TestSuite.own(fixture, "ai_profiles")["actors"][caster["actor_id"]]["profile"]["ai_att_magic"] = 100
	if key == "poison": Loop.skill_fields(fixture, Cases.POISON)["use_ratio"] = "100"
	else:
		for name in ["wind", "fire"]:
			TestSuite.own(fixture, "skill_book")["skills"]["magic:magicAIR:magicCode01" if name == "wind" else "magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "100" if name == key else "0"
	var initial := Loop.unit(fixture, "enemy023_1")
	initial.merge({"id": "review-initial", "coord": Vector2i(2, 8), "live_speed": 110}, true)
	fixture["units"].append(initial)
	for unit in fixture["units"]:
		unit["coord"] += Vector2i(4, 4)
		unit["grid_coord"] = unit["coord"]
	for child in scene.actors_root.get_children():
		scene.actors_root.remove_child(child)
		child.queue_free()
	fixture["turn_queue"] = Loop.CoreTurnQueue.rebuild(fixture["units"])
	var before := fixture.duplicate(true)
	scene.apply_loop(Loop._return_to_player(fixture, initial["id"]), "test")
	scene.interaction_state = scene.play_loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(Vector2i(10, 10))
	scene._process(0.0)
	await create_timer(0.3).timeout
	await shot(key + "-before")
	var button: Control = scene.action_menu.get_node("WaitCommand")
	check(button.is_visible_in_tree(), "actual Wait is available " + key)
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	scene.set_process(true)
	var moving := false
	var lead_in := false
	var casting := false
	var settled := false
	var feedback_samples: Array = []
	var presentation = scene.get_node("BattlePresentation")
	for _attempt in range(800):
		await create_timer(0.025).timeout
		if scene.has_actor_motion() and not moving:
			moving = true
			check(not scene.action_menu.is_visible_in_tree(), "movement retains modal ownership " + key)
			await shot(key + "-move")
		if key != "poison" and presentation.cutin.busy() and presentation.cutin.elapsed > 0.12 and presentation.cutin.elapsed < presentation.cutin.Timing.CAST_LEAD_IN and not lead_in:
			lead_in = true
			await shot(key + "-lead")
		# 幻火's effCode23 impact is its FireBomb2 insertion at tick 100 (cut-in elapsed = lead + ticks × PLAYBACK_SPEED / 60).
		var effect_time: float = 0.75 if key == "poison" else presentation.cutin.Timing.CAST_LEAD_IN + (100.0 * presentation.cutin.Timing.PLAYBACK_SPEED / presentation.cutin.skill_effects.TICKS_PER_SECOND if key == "fire" else 0.4)
		if presentation.cutin.busy() and presentation.cutin.elapsed > effect_time and not casting:
			casting = true
			check(not scene.action_menu.is_visible_in_tree(), "cast feedback finishes before next controls " + key)
			if key == "poison":
				var labels: Array = presentation.status_feedback.get_children()
				check(labels.size() == 3, "each affected target has visible status feedback")
				for index in range(labels.size()):
					feedback_samples.append({"text": labels[index].text, "bounds": feedback_rect(labels[index])})
					for other in range(index):
						check(not feedback_rect(labels[index]).grow(4).intersects(feedback_rect(labels[other]).grow(4)), "actual adjacent status feedback remains readable")
			await shot(key + "-cast")
		if scene.selected_unit_id == "enemy023_1" and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion() and not presentation.cutin.busy() and not presentation.has_pending_combat(scene.play_loop):
			settled = true
			break
	check(moving and casting and settled, "normal-clock move/cast/handoff completes " + key)
	if key != "poison": check(lead_in, "source casting stars are visibly sampled " + key)
	var action: Dictionary = scene.play_loop.get("last_ai_action", {})
	check(action.get("magic_key") == key and action.get("kind") == "move_then_attack", "actual source spell and casting move " + key)
	check(scene.play_loop["last_ai_actions"].size() == 1 and scene.play_loop["turn_queue"]["index"] == 2, "one AI action hands off exactly once " + key)
	check(Loop.unit(scene.play_loop, "enemy026_1")["mp"] == caster["mp"] - int(action.get("resource_payment", {}).get("amount", -1)), "one visible cast pays the receipt amount " + key)
	if key == "poison": check(action.get("affected_targets", []).size() == 3 and action.get("target_id") == "area-center", "rendered area cast uses the three-target center")
	await create_timer(0.3).timeout
	check(scene.action_menu.is_visible_in_tree(), "successor command menu is visible " + key)
	await shot(key + "-handoff")
	records.append({"spell": key, "before": before, "action": action, "moving": moving, "casting": casting,
		"lead_in": lead_in, "feedback": feedback_samples, "handoff": settled, "next_actor": scene.selected_unit_id, "caster_after": Loop.unit(scene.play_loop, "enemy026_1")})
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


## A caption Label's rect, or a result number's (ResultNumberFloat) glyph rect at its current rise.
func feedback_rect(node: Node) -> Rect2:
	if node is Node2D:
		var rect: Rect2 = node.bounds()
		return rect if node.number == null else Rect2(rect.position + node.number.position, rect.size)
	return node.get_global_rect()

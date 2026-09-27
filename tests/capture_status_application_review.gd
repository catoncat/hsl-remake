extends SceneTree
## Bounded real Control/map input fixture. Never sends desktop mouse or keys.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const Cases = preload("res://tests/run_status_application_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/status-application-review/"
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Status application review requires a built-in-display rendering window")
		quit(2)
		return
	root.title = "HSL Status Application Review"
	root.size = Vector2i(640, 480)
	create_timer(35.0).timeout.connect(func(): push_error("Status review exceeded its bounded route"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	scene.apply_loop(Cases.fixture(), "test")
	# Source-owned 025 spell; deterministic success is explicitly fixture-only.
	TestSuite.own(scene.play_loop, "skill_book")["skills"][Cases.POISON]["fields"]["status_hit_ratio"] = "100"
	Loop._unit(scene.play_loop, "enemy021_2")["coord"] = Vector2i(13, 13)
	var mage := Loop._unit(scene.play_loop, "enemy026_1")
	mage["coord"] = Vector2i(10, 8)
	mage["live_speed"] = 98
	mage["hp"] = 1000
	mage["max_hp"] = 1000
	mage["status_flags"] = 2
	mage["status_counters"]["no_magic"] = 1
	var ally := Loop._unit(scene.play_loop, "enemy023_1")
	ally["battle_actor_role"] = Loop.ROLE_PLAYER
	ally["player_commandable"] = true
	ally["live_speed"] = 97
	for unit in scene.play_loop["units"]:
		unit["combat_profile"]["attack_back"] = 0
	scene.play_loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(scene.play_loop, "test")
	scene.interaction_state = scene.play_loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(Vector2i(9, 8))
	scene._process(0.0)
	await create_timer(0.35).timeout
	await click(scene.action_menu.get_node("MagicCommand"))
	check(scene.magic_panel.visible, "actual Magic command opens the owned-spell list")
	await shot("magic-list")
	await escape()
	check(scene.interaction_state == "action_menu" and scene.play_loop["interaction"] == "action_menu", "actual Cancel restores map and rules phase")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("MagicCommand"))
	await click(scene.magic_panel.choices[Cases.POISON])
	check(scene.interaction_state == "attack_select" and not scene.magic_panel.visible, "actual spell click enables map targeting")
	await shot("poison-range")
	await point(scene.grid_cell_center_to_logical_position(Vector2i(9, 8)))
	check(scene.play_loop["last_attack"].get("magic_key") == "poison", "actual map click submits the selected spell")
	check(Status.poisoned(Loop.unit(scene.play_loop, "enemy021_1")) and Status.poisoned(Loop.unit(scene.play_loop, "enemy026_1")), "one cast applies poison to both footprint opponents")
	check(Loop.unit(scene.play_loop, "emperor025")["mp"] == 90, "area cast charges MP exactly once")
	var settled_cast: Dictionary = scene.play_loop["last_attack"].duplicate(true)
	scene.set_process(true)
	await create_timer(0.85).timeout
	await shot("poison-impact")
	await until_actor("leonard")
	scene.center_camera_on_grid(Vector2i(9, 8))
	await point(scene.grid_cell_center_to_logical_position(Vector2i(10, 8)))
	check(scene.status_panel.visible, "actual enemy inspection opens live status")
	await shot("poison-and-silence")
	await escape()
	var before_ai := Loop.unit(scene.play_loop, "enemy026_1")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("WaitCommand"))
	await until_actor("enemy023_1")
	var after_ai := Loop.unit(scene.play_loop, "enemy026_1")
	var power := int(before_ai["status_counters"]["poison"]) >> 16
	check(after_ai["mp"] == before_ai["mp"] and after_ai["hp"] == before_ai["hp"] - power, "silenced AI keeps MP and takes one owner-action poison step")
	check(after_ai["status_counters"]["no_magic"] == 0 and int(after_ai["status_counters"]["poison"]) == int(before_ai["status_counters"]["poison"]) - 1, "AI expires silence and decrements poison once without corrupting potency")
	scene.center_camera_on_grid(after_ai["coord"])
	await point(scene.grid_cell_center_to_logical_position(after_ai["coord"]))
	check(scene.status_panel.visible, "post-AI inspection remains available")
	await shot("after-ai-expiry")
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "real_control_events": true,
		"input_delivery": "Viewport.push_input; no desktop input or direct signals",
		"fixture_overrides": "025 is commandable with 100MP; Acid Mist chance=100; 026 has 1000HP and one silence action; queue and positions isolated; counters disabled",
		"window_position": root.position, "window_size": root.size, "cast": settled_cast,
		"mage_before_ai": before_ai, "mage_after_ai": after_ai, "next_actor": scene.selected_unit_id,
		"failures": failures}, "  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("STATUS_APPLICATION_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func until_actor(id: String) -> void:
	for _attempt in range(200):
		if scene.selected_unit_id == id and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.has_actor_motion() and not scene.get_node("BattlePresentation").cutin.busy() and not scene.get_node("BattlePresentation").has_pending_combat(scene.play_loop):
			return
		await create_timer(0.05).timeout
	check(false, "bounded presentation reaches " + id)


func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "visible control before click")
	if control != null: await point(control.get_global_rect().get_center())


func point(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame


func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

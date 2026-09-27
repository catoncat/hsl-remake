extends SceneTree
## Bounded rendered fixture: actual viewport mouse events, no desktop input.
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/status-review/"
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Status visual review needs a rendering window on the built-in display")
		quit(2)
		return
	root.title = "HSL Status Review"
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var actor := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	actor["hp"] = actor["max_hp"]
	actor["live_speed"] = 100
	actor["status_flags"] = 3
	actor["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 2}
	var ally := BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["live_speed"] = 99
	ally["player_commandable"] = true
	ally["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	ally["inventory"] = [246, 0, 0, 0, 0, 0, 0, 0]
	scene.play_loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(BattlePlayLoop.select_player_unit(scene.play_loop, "leonard"), "test")
	scene._process(0.0)
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("StatusCommand"))
	check(scene.status_panel.visible, "real Status command opens")
	await shot("poison-and-no-magic")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	scene._process(0.0)
	await open_antidote(3)
	var before: Dictionary = scene.play_loop.duplicate(true)
	check(not scene.item_panel.target_buttons["leonard"].disabled, "full-health poisoned target accepts antidote")
	await shot("antidote-target")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	root.push_input(cancel, true)
	check(scene.play_loop == before and scene.item_panel.page == "inventory", "right-click cancel changes no battle state")
	await click(scene.item_panel.rows.get_node("Item_246_3"))
	await click(scene.item_panel.target_buttons["leonard"])
	var cured := BattlePlayLoop.unit(scene.play_loop, "leonard")
	check(cured["status_flags"] == 2 and cured["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 1}, "only poison cleared; silence ticks exactly once")
	check(cured["hp"] == cured["max_hp"] and cured["inventory"].count(246) == 0, "one antidote consumed with no poison damage after cure")
	check(scene.selected_unit_id == "enemy023_1" and not scene.ai_playback_active, "next ally is not skipped")
	scene._process(0.0)
	await create_timer(0.3).timeout
	await shot("cured-next-ally")
	var after: Dictionary = scene.play_loop.duplicate(true)
	await open_antidote(0)
	check(scene.item_panel.target_buttons["leonard"].disabled and scene.item_panel.target_buttons["enemy023_1"].disabled, "already-cured and healthy actors both reject pointless antidote")
	await click(scene.item_panel.target_buttons["enemy023_1"])
	check(scene.play_loop == after, "disabled target click consumes nothing")
	await shot("healthy-target-refusal")
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({"fixture": true, "native_execution": false, "real_control_events": true, "input_delivery": "Viewport.push_input; no desktop input or direct signals", "window_position": root.position, "window_size": root.size, "cured_unit": cured, "next_actor": scene.selected_unit_id, "healthy_refusal_unchanged": scene.play_loop == after, "failures": failures}, "  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("STATUS_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func open_antidote(index: int) -> void:
	scene._process(0.0)
	await create_timer(0.3).timeout
	# The scene's own _process is off (set_process(false) above), so the item-use presentation
	# before the next ally's ring only advances when the harness steps it.
	var steps := 0
	while not scene.action_menu.visible and steps < 50:
		scene._process(0.1)
		await create_timer(0.1).timeout
		steps += 1
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("UseCommand"))
	await click(scene.item_panel.rows.get_node("Item_246_" + str(index)))


func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "visible control before input")
	if control == null: return
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame


func shot(name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "capture " + name)


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)

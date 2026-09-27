extends SceneTree
## Real rendered frames and normal input; all fixture grants are listed in the receipt.
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const OUT := "res://ignored/combat-aftermath-review/"
var scene: Node
var view: Node
var records: Array = []
var failures: Array[String] = []
var current_case := ""
var started := 0
var mouse_entered := false


func _initialize() -> void: call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Aftermath review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Combat Aftermath Review"
	root.size = Vector2i(640, 480)
	check(Engine.time_scale == 1.0, "review must use unmodified clocks")
	create_timer(90).timeout.connect(func(): push_error("AFTERMATH_REVIEW_TIMEOUT"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	started = Time.get_ticks_msec()
	for command in ["attack", "special"]:
		current_case = command
		fixture()
		await create_timer(0.4).timeout
		var point: Vector2 = RuntimeReadback.command_center_logical_position(scene.scene_input, command)
		check(scene.action_menu.is_visible_in_tree() and scene.scene_input.command_id_at_logical_position(point) == command, "visible command: " + command)
		await click(point)
		if command == "special":
			check(scene.interaction_state == "special_select" and scene.magic_panel.visible, "特殊技 opens the skill page first (original skill page)")
			await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"].get_global_rect().get_center())
		check(scene.interaction_state == "attack_select", "actual menu input opens target selection")
		await click(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["coord"]))
		check(scene.play_loop.get("last_combat", {}).get("hit", false), "fixture attack really hit; a random miss is not relabeled as a kill")
		check(BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["hp"] == 0, "actual attack resolves the lethal hit")
		var settled: Dictionary = scene.play_loop.duplicate(true)
		await until(func(): return view.cutin.busy() and view.cutin.clips[0]["impact_emitted"])
		check(not view.dialogue_active() and not view.aftermath.reward_label.visible, "close-up precedes all map feedback")
		await shot("hurt")
		await until(func(): return view.aftermath.dialogue_active())
		check(view.current_message_id() == "372" and scene.actor_node_for_unit("enemy021_1").visible, "source last words hold the defeated map actor")
		await create_timer(0.3).timeout
		check(scene.play_loop == settled and not scene.action_menu.visible and not scene.growth_panel.visible, "reading cannot change the settled turn or reveal growth early")
		await shot("last-words")
		if command == "attack":
			await click(Vector2(570, 451))
		else:
			await key(KEY_SPACE)
		await create_timer(0.12).timeout
		check(view.aftermath.stage == "fade", "normal confirmation begins the map fade")
		await shot("fade")
		await until(func(): return view.aftermath.reward_label.visible)
		var earned: int = settled["last_combat"]["experience"]["gained"]
		check(not scene.actor_node_for_unit("enemy021_1").visible and view.aftermath.reward_label.text.contains("EXP %d" % earned), "final native reward follows the completed death")
		check(scene.play_loop == settled, "map reward does not mutate EXP or queue")
		await shot("experience")
		await until(func(): return scene.growth_panel.visible)
		check(not view.aftermath.busy() and not view.aftermath.reward_label.visible, "growth waits until the reward finishes")
		await shot("growth")
		scene.growth_panel.hide() # harness skip seam: right click／Esc cannot close the window before OK
		await until(func(): return scene.selected_unit_id == "enemy023_1" and scene.action_menu.visible)
		await create_timer(0.35).timeout
		check(BattlePlayLoop.unit(scene.play_loop, "leonard")["exp"] == earned - 1 and not BattlePlayLoop.action_exhausted(scene.play_loop), "exactly one native award and one successor")
		await shot("successor")
		scene.queue_free()
		await process_frame
	FileAccess.open(OUT + "review-receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"normal_clock": Engine.time_scale, "input": "Viewport.push_input mouse and Input.parse_input_event keyboard; no direct command or attack calls",
		"fixture": "dev first-control scene; one adjacent enemy at 1 HP; Leonard 99 EXP/60 ST/speed 100; next ally speed 99 and player-controlled; queue rebuilt once before input; no RNG/result overrides",
		"window_position": root.position, "window_size": root.size, "records": records, "failures": failures}, "  "))
	await create_timer(0.3).timeout
	print("COMBAT_AFTERMATH_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func fixture() -> void:
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	view = scene.get_node("BattlePresentation")
	var player := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	# Isolate this historical death/EXP/growth route from the separate loot modal.
	BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	player["exp"] = 99
	player["stamina"] = 60
	player["live_speed"] = 100
	var ally := BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
	ally["live_speed"] = 99
	ally["player_commandable"] = true
	ally["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	var enemy := BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	enemy["hp"] = 1
	scene.play_loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(BattlePlayLoop.select_player_unit(scene.play_loop, "leonard"), "test")
	scene.ai_playback_active = false
	scene.interaction_state = "action_menu"
	scene.apply_loop(scene.play_loop, "test")
	scene.select_actor("leonard") # Rebuild the visible menu after the explicit ST grant.
	# Advance time only through the actual SceneTree; do not seek/stop any animation.
	view.aftermath.experience_presented.connect(func(growth): records.append({"case": current_case, "event": "experience", "growth": growth}))


func until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(predicate.call(), "normal-clock stage completed before timeout: " + current_case)


func click(point: Vector2) -> void:
	if not mouse_entered:
		root.notify_mouse_entered()
		mouse_entered = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	var actor: Node2D = scene.actor_node_for_unit("enemy021_1")
	records.append({"case": current_case, "capture": label, "milliseconds": Time.get_ticks_msec() - started,
		"stage": view.aftermath.stage, "message_id": view.current_message_id(), "reward": view.aftermath.reward_label.text,
		"reward_visible": view.aftermath.reward_label.visible, "victim_visible": actor.visible, "victim_alpha": actor.modulate.a,
		"selected": scene.selected_unit_id, "growth_visible": scene.growth_panel.visible, "menu_visible": scene.action_menu.visible})
	check(root.get_texture().get_image().save_png(OUT + current_case + "-" + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
		FileAccess.open(OUT + "review-failure.json", FileAccess.WRITE).store_string(JSON.stringify({"case": current_case, "records": records, "failures": failures}, "  "))
		quit(1)

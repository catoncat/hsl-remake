extends SceneTree
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
## Normal-speed audiovisual fixtures for the shared presentation layer.
## Controlled setup, not a natural playthrough and not an automatic parity verdict.
const OUT := "res://ignored/presentation-reference/"
var scene: Node
var view: Node
var started := 0
var events: Dictionary = {}
var selected_case := "attack"
var movie_mode := false
var started_frame := 0
var mouse_entered := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		selected_case = args[0]
	movie_mode = args.size() > 1 and args[1] == "movie"
	if selected_case not in ["menu", "attack", "magic", "status", "items", "growth"] or DisplayServer.get_name() == "headless":
		push_error("Select menu, attack, magic, status, items or growth in an actual rendering window")
		quit(2)
		return
	root.title = "HSL Presentation Reference — " + selected_case
	DirAccess.make_dir_recursive_absolute(OUT + "resumed")
	root.size = Vector2i(960, 720)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop() # Isolate game action cues, not microphone/system audio.
	view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	var player: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "leonard")
	var caster: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "enemy026_1")
	caster["coord"] = player["coord"] + Vector2i(-3, -1)
	scene.apply_loop(scene.play_loop, "test")
	scene._process(0)
	# Explicit fixture-only latch lets the external window recorder start first.
	var latch := OUT + "start-" + selected_case
	var deadline := Time.get_ticks_msec() + 60000
	print("REFERENCE_READY case=", selected_case)
	while not movie_mode and not FileAccess.file_exists(latch):
		if Time.get_ticks_msec() > deadline:
			push_error("Reference recorder did not release fixture within 60 seconds")
			quit(2)
			return
		await create_timer(0.05).timeout
	if not movie_mode:
		DirAccess.remove_absolute(latch)
	started = Time.get_ticks_msec()
	started_frame = Engine.get_frames_drawn()
	if selected_case == "menu":
		await show_menu()
	elif selected_case in ["status", "items", "growth"]:
		await show_panel()
	else:
		scene.menus.set_action_menu_visible(false)
		var attacker: Dictionary = caster if selected_case == "magic" else scene.BattlePlayLoop.unit(scene.play_loop, "enemy023_1")
		var defender: Dictionary = player if selected_case == "magic" else scene.BattlePlayLoop.unit(scene.play_loop, "enemy021_1")
		var strike := {"attacker_id": attacker["id"], "defender_id": defender["id"], "damage": 6, "hit": true, "defender_hp_before": int(defender["hp"]), "defender_hp_after": int(defender["hp"]) - 6}
		if selected_case == "magic":
			strike.merge({"magic_key": "wind", "magic_name": "風刃"})
		view._map_config = scene.map_config
		view.cutin.released.connect(func(_s, _a, _d, _c): mark("release"))
		view.cutin.impact.connect(func(_s, _a, _d, _c): mark("impact"))
		mark("begin")
		view._show_strike(strike, scene.play_loop["units"], scene.map_config, false)
		view.cutin.set_process(true)
		while view.cutin.busy():
			await process_frame
			if view.cutin.busy():
				if selected_case == "attack":
					var schedule: Dictionary = view.cutin.Timing.ordinary(view.cutin.manifest["actors"][attacker["actor_id"]], view.cutin.clips[0]["strike"])
					var phase: String = view.cutin.Timing.phase_at(schedule, view.cutin.elapsed)
					if phase == "target_pause": mark("target")
					if phase == "recovery": mark("recovery")
				elif view.cutin.elapsed >= view.cutin.Timing.CAST_LEAD_IN:
					mark("target_effect")
		mark("return")
		await create_timer(1.0).timeout
	FileAccess.open(OUT + "remake-" + selected_case + "-events.json", FileAccess.WRITE).store_string(JSON.stringify({"fixture": true, "case": selected_case, "clock_scale": Engine.time_scale, "fixed_fps_movie": movie_mode, "started_frame": started_frame, "events": events}, "  "))
	print("REFERENCE_FIXTURE_FINISHED case=", selected_case)
	# Keep the completed window alive long enough for the bounded external recorder
	# to finalize its stream. Closing it early truncates the sound/return interval.
	await create_timer(0.5 if movie_mode else 15.0).timeout
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0)


func mark(event: String) -> void:
	if not events.has(event):
		events[event] = (Engine.get_frames_drawn() - started_frame) / 60.0 if movie_mode else (Time.get_ticks_msec() - started) / 1000.0
		print("REFERENCE_EVENT ", event, " ", events[event])


func show_menu() -> void:
	mark("idle")
	await create_timer(1.0).timeout
	scene.action_menu.set_hovered_command("move")
	mark("hover")
	await create_timer(2.0).timeout
	scene.action_menu.set_hovered_command("")
	mark("leave")
	await create_timer(1.0).timeout
	var all: Array = scene.play_loop["command_menu"]["commands"].duplicate(true)
	var moved: Array = all.filter(func(c): return c["command"] != "move")
	scene.action_menu.rebuild(moved)
	scene.menus.update_action_menu_anchor()
	mark("after_move")
	await create_timer(2.0).timeout
	# Controlled settled-action fixture. The live runtime, not a manually
	# constructed two-button menu, now owns the exhausted-action handoff.
	scene.play_loop["moved_this_action"] = true
	scene.play_loop["attacked_this_action"] = true
	scene._process(0)
	assert(scene.ai_playback_active and not scene.action_menu.visible, "both spent budgets must hand off through the normal runtime")
	mark("after_both")
	await create_timer(2.0).timeout


func click_control(control: Control) -> void:
	assert(control.is_visible_in_tree(), "reference must click a visible control")
	var move := InputEventMouseMotion.new()
	move.position = control.get_global_rect().get_center()
	if not mouse_entered:
		root.notify_mouse_entered()
		mouse_entered = true
	root.push_input(move, true)
	await process_frame
	print("REFERENCE_CLICK ", control.name, " point=", move.position, " hover=", root.gui_get_hovered_control())
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func escape_panel() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func snapshot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	assert(root.get_texture().get_image().save_png(OUT + "resumed/current-" + label + ".png") == OK)


func show_panel() -> void:
	if selected_case == "status":
		scene.menus.choose_command("status")
		scene._process(0)
		mark("open")
		await snapshot("status")
		await create_timer(2.0).timeout
		await escape_panel()
	elif selected_case == "items":
		scene.menus.choose_command("item")
		scene._process(0)
		mark("submenu")
		await snapshot("item-menu")
		await create_timer(1.0).timeout
		await click_control(scene.item_panel.menu.get_node("UseCommand"))
		assert(scene.item_panel.page == "inventory", "visible Use click must open the item list")
		mark("open")
		await snapshot("inventory")
		await create_timer(2.0).timeout
		await click_control(scene.item_panel.rows.get_child(0))
		mark("select")
		await snapshot("item-target")
		await create_timer(1.0).timeout
		await escape_panel()
		mark("cancel")
		await create_timer(1.0).timeout
		await escape_panel()
		await escape_panel()
	else:
		var player: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "leonard")
		player["exp"] = 99
		player.merge(scene.BattlePlayLoop.ProgressionRules.resolve_experience(player, 1, scene.play_loop["equipment_items"]), true)
		scene.menus.open_growth("leonard")
		scene.play_ui_sound("level_up")
		mark("open")
		await create_timer(1.0).timeout
		for key in ["str", "dex", "mind", "con"]:
			await click_control(scene.growth_panel.choices[key]["plus"])
		await click_control(scene.growth_panel.choices["str"]["plus"])
		mark("preview")
		await snapshot("growth")
		await create_timer(2.0).timeout
		await click_control(scene.growth_panel.confirm_button)
		mark("confirm")
		var after: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
		assert(not scene.growth_panel.visible and int(after["pending_stat_points"]) == 0)
		assert(int(after["combat_profile"]["str"]) == 18 and int(after["combat_profile"]["dex"]) == 17 and int(after["combat_profile"]["mind"]) == 9 and int(after["combat_profile"]["con"]) == 13)
	scene._process(0)
	mark("return")
	await create_timer(1.0).timeout

extends SceneTree
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
## Rendered regression fixtures, not an unmodified playthrough or a parity assertion.
## Samples the live scene and uses actual input events for the growth controls.
const OUT := "res://ignored/acceptance-fixes/review/"
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This review requires an actual rendering window")
		quit(2)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var view = scene.get_node("BattlePresentation")
	var cutin = view.cutin
	cutin.set_process(false)
	scene._process(0)
	await shot("map-clean")
	var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	var enemy: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	enemy["hp"] = 1
	scene.apply_loop(scene.play_loop, "test")
	scene.apply_loop(scene.BattlePlayLoop.choose_command(scene.play_loop, "attack"), "test")
	scene.apply_loop(scene.BattlePlayLoop.attack_target(scene.play_loop, "enemy021_1", func(_n): return 0), "test")
	scene.finish_attack_attempt()
	# The player's confirmed attack has no map lead-in (BattleAttackCue.leads): the cut-in
	# starts on the confirm frame.
	scene._process(0)
	cutin._process(0.02)
	await shot("player-windup")
	cutin._process(1.0)
	await shot("player-flash")
	seek_ordinary(cutin, "impact")
	check(cutin.defender_sprite.visible, "hurt screenshot must show the receiver, not the attacker")
	await shot("enemy-hurt")
	cutin._process(8)
	scene._process(0)
	await shot("map-after-lethal")
	scene.growth_panel.hide()
	scene.status_panel.hide()
	scene.menus.set_action_menu_visible(false)
	for actor_id in ["021", "023", "024", "026", "025"]:
		var unit := template(actor_id)
		cutin.play({"damage": 6, "hit": true, "defender_hp_before": 30, "defender_hp_after": 24}, unit, player, false)
		cutin._process(0.01)
		await shot(actor_id + "-attack")
		seek_ordinary(cutin, "impact")
		check(cutin.defender_sprite.visible, "victim screenshot must show the receiver")
		await shot(actor_id + "-victim")
		cutin._process(8)
	for key in ["wind", "fire"]:
		cutin.play({"magic_key": key, "magic_name": key, "damage": 8, "hit": true, "defender_hp_before": 30, "defender_hp_after": 22}, template("026"), player, false, scene.world_to_logical_position(scene.actor_node_for_unit("leonard").position))
		cutin._process(0.4)
		await shot(key + "-build")
		cutin._process(cutin.Timing.CAST_LEAD_IN / cutin.Timing.PLAYBACK_SPEED + 1.0)
		await shot(key + "-impact")
		cutin._process(1.25)
		await shot(key + "-finish")
		cutin._process(8)
	cutin.play({"skill_name": "氣刃斬", "damage": 8, "hit": true, "defender_hp_before": 22, "defender_hp_after": 14}, player, template("021"), false)
	cutin._process(0.35)
	await shot("special-cast")
	cutin._process(0.7)
	await shot("special-travel")
	cutin._process(0.3)
	await shot("special-impact")
	cutin._process(8)
	scene.status_panel.show_unit(player)
	await shot("status-player")
	scene.status_panel.show_unit(template("026"))
	await shot("status-mage")
	scene.status_panel.hide()
	# A controlled native-derived level-up fixture, committed through the real panel/PlayLoop path.
	var live: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "leonard")
	live["exp"] = 99
	live.merge(scene.BattlePlayLoop.ProgressionRules.resolve_experience(live, 1, scene.play_loop["equipment_items"]), true)
	scene.menus.open_growth("leonard")
	await shot("growth-empty")
	var hp_before := int(live["max_hp"])
	var current_hp_before := int(live["hp"])
	for key in ["str", "dex", "mind", "con"]:
		await click(scene.growth_panel.choices[key]["plus"])
	await click(scene.growth_panel.choices["str"]["plus"])
	await shot("growth-preview")
	await click(scene.growth_panel.confirm_button)
	var after: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	check(not scene.growth_panel.visible and int(after["pending_stat_points"]) == 0, "mouse growth confirmation must spend the five-point budget and close")
	check(int(after["combat_profile"]["str"]) == 18 and int(after["combat_profile"]["dex"]) == 17 and int(after["combat_profile"]["mind"]) == 9 and int(after["combat_profile"]["con"]) == 13, "mouse growth confirmation must commit four authoritative base attributes")
	check(int(after["max_hp"]) == hp_before + 2 and int(after["hp"]) == current_hp_before, "native-derived growth must recompute max HP without refilling current HP")
	scene.status_panel.show_unit(after)
	await shot("growth-confirmed")
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({"fixture": true, "mouse_growth_confirmed": failures.is_empty(), "failures": failures}, "  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("FIRST_BATTLE_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func template(actor_id: String) -> Dictionary:
	var loop: Dictionary = scene.BattleFixture.loop() if actor_id != "025" else scene.BattlePlayLoop.create([], "", scene.BattleScenario.load_file("res://content/battles/battle_052.json"))
	for unit in loop["units"]:
		if str(unit["actor_id"]) == actor_id:
			return unit.duplicate(true)
	assert(false, "missing fixture actor " + actor_id)
	return {}


func shot(label: String) -> void:
	if scene.get_node("BattlePresentation").cutin.busy():
		scene.menus.set_action_menu_visible(false)
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func click(button: Control) -> void:
	check(button.is_visible_in_tree(), "button must be visible before real input")
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func seek_ordinary(cutin: Node, event: String) -> void:
	var actor: Dictionary = cutin.manifest["actors"][cutin.clips[0]["attacker"]]
	var schedule: Dictionary = cutin.Timing.ordinary(actor, cutin.clips[0]["strike"])
	cutin._process(maxf(0.0, (float(schedule[event]) + 0.01 - cutin.elapsed) / cutin.Timing.PLAYBACK_SPEED))

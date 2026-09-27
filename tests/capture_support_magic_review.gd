extends SceneTree
## Normal-clock, real Control/map input. Grants and encounter setup are explicit
## fixtures; no original runtime or natural first-battle availability is claimed.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_support_magic_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/support-magic-review/"
var scene: Node
var failures: Array[String] = []
var routes: Array = []
var tail_checks := {}
var mode := ""


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Support review requires a built-in-display rendering window")
		quit(2)
		return
	root.title = "HSL Support Magic Review"
	root.size = Vector2i(640, 480)
	create_timer(180.0).timeout.connect(func(): push_error("Support review exceeded its bounded routes"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	var names: Array = ["heal_self", "heal_ally", "greater_heal", "life_heal", "cure_area", "ai_heal", "ai_cure", "ai_empty_mp"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup(mode.begins_with("ai_"))
		if mode.begins_with("ai_"): await ai_route()
		else: await player_route()
		await close_scene()
		if not failures.is_empty(): break
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "normal_clock": true, "real_control_events": true,
		"input_delivery": "Viewport.push_input; no desktop events, direct signals, combat RNG override, or post-input result mutation",
		"fixture_overrides": "Three original-rendered actors, fixed positions and speeds, 100maxHP/MP, explicit support ownership on 001/026, source WRD restored; AI rates/use_ratio=100 for visible success, no reinforcements. HP4 for AI recovery, HP20 for player healing. Cure has packed poison and ally silence. Default first-battle grants are unchanged.",
		"window_size": root.size, "routes": routes, "presentation_tails": tail_checks, "failures": failures}, "  "))
	print("SUPPORT_MAGIC_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size())
	quit(0 if failures.is_empty() else 1)


func setup(ai: bool) -> void:
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.2).timeout
	scene.get_node("BattleMusic").stop()
	var source := BattleFixture.loop()
	var loop := Cases.fixture(ai)
	loop["tiles"] = source["tiles"]
	loop["map_size"] = source["map_size"]
	loop["ai_calls"] = []
	if mode in ["cure_area", "ai_cure"]:
		for actor in [loop["units"][0], loop["units"][1]]:
			actor.merge(Loop.StatusEffectRules.apply(actor, "poison", 2, 10)["changes"], true)
		loop["units"][1].merge(Loop.StatusEffectRules.apply(loop["units"][1], "no_magic", 2)["changes"], true)
	if ai:
		var owner: Dictionary = loop["units"][0]
		TestSuite.own(loop, "skill_book")["actors"][owner["actor_id"]]["supported_initial_ids"] = [Cases.HEAL, Cases.CURE]
		for id in [Cases.HEAL, Cases.CURE]: TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "100"
		TestSuite.own(loop, "ai_profiles")["actors"][owner["actor_id"]]["profile"].merge({"ai_att_magic": 100, "ai_check_hp": 100, "ai_check_dying": 0}, true)
		loop["units"][2]["live_speed"] = 110
		loop["units"][1]["hp"] = 100
		if mode == "ai_cure": owner["hp"] = 100
		if mode == "ai_empty_mp": owner["mp"] = 0
		loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
		loop["interaction"] = "idle"
		loop = Loop.select_player_unit(loop, "leonard")
	scene.apply_loop(loop, "test")
	for child in scene.actors_root.get_children():
		scene.actors_root.remove_child(child)
		child.queue_free()
	scene.unit_grid_coords.clear()
	for unit in loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.apply_loop(scene.play_loop, "test")
	scene.interaction_state = loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(Vector2i(9, 8))
	scene._process(0.0)
	scene.set_process(true)
	await create_timer(0.3).timeout


func player_route() -> void:
	var id: String = {"heal_self": Cases.HEAL, "heal_ally": Cases.HEAL, "greater_heal": Cases.GREATER, "life_heal": Cases.LIFE, "cure_area": Cases.CURE}[mode]
	var target_id := "leonard" if mode == "heal_self" else "enemy023_1"
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("MagicCommand"))
	check(scene.magic_panel.visible and scene.magic_panel.choices.has(id), "owned support skill has a real selectable button")
	if mode == "heal_self": await shot("list")
	await click(scene.magic_panel.choices[id])
	check(scene.interaction_state == "attack_select", "support skill enters actual map targeting")
	await hover(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop, target_id)["coord"]))
	check(scene.get_node("BattlePresentation").target_vitals.visible, "friend/self hover has the shared live target preview")
	await shot("range")
	await escape()
	check(scene.play_loop["units"] == before["units"] and scene.play_loop["turn_queue"] == before["turn_queue"], "actual cancel preserves HP MP status and queue")
	await create_timer(0.25).timeout
	await click(scene.action_menu.get_node("MagicCommand"))
	await click(scene.magic_panel.choices[id])
	await point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop, target_id)["coord"]))
	var receipt: Dictionary = scene.play_loop["last_attack"].duplicate(true)
	check(receipt.get("skill_id") == id, "actual map click commits the selected support skill")
	if receipt.get("skill_id") != id: return
	var observed := await until_actor("enemy023_1", true)
	check(observed, "normal playback shows the support impact before returning control")
	check(scene.play_loop["last_combat"]["sequence"] == receipt["sequence"] and scene.play_loop["turn_queue"]["index"] == 1, "visual playback adds neither an extra payment nor an extra turn")
	if mode == "cure_area":
		check(Loop.unit(scene.play_loop, "leonard")["status_counters"]["poison"] == 0 and Loop.unit(scene.play_loop, target_id)["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 2}, "actual area cure clears both friends and preserves ally silence")
	else:
		check(receipt["healing"] > 0 and Loop.unit(scene.play_loop, target_id)["hp"] == receipt["defender_hp_after"], "positive map feedback agrees with settled HP")
	if target_id == scene.selected_unit_id: await click(scene.action_menu.get_node("StatusCommand"))
	else: await point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop, target_id)["coord"]))
	check(scene.status_panel.visible, "post-cast status is accessible through real controls")
	await shot("status")
	routes.append({"mode": mode, "receipt": receipt, "caster_after": compact(Loop.unit(scene.play_loop, "leonard")), "target_after": compact(Loop.unit(scene.play_loop, target_id)), "next_actor": scene.selected_unit_id, "index": scene.play_loop["turn_queue"]["index"]})


func ai_route() -> void:
	await click(scene.action_menu.get_node("WaitCommand"))
	var observed := await until_actor("enemy023_1", mode != "ai_empty_mp")
	check(observed or mode == "ai_empty_mp", "normal-clock AI support effect is visible")
	var action: Dictionary = scene.play_loop["last_ai_action"].duplicate(true)
	var caster := Loop.unit(scene.play_loop, "enemy026_1")
	if mode == "ai_empty_mp":
		check(action.get("kind") == "use_item" and caster["mp"] == 0 and caster["hp"] > 4, "actual AI falls back to medicine with no MP")
	else:
		check(action.get("skill_id") == (Cases.CURE if mode == "ai_cure" else Cases.HEAL) and action.get("defender_id") == "enemy026_1", "actual Wait leads to exactly the intended self spell")
		check(caster["mp"] == (96 if mode == "ai_cure" else 94) and caster["inventory"][0] == 241, "AI magic consumes one fee and preserves its medicine")
		if mode == "ai_cure": check(caster["status_counters"]["poison"] == 0 and caster["hp"] == 100, "self cure prevents the following owner poison tick")
	check(scene.play_loop["turn_queue"]["index"] == 2 and scene.play_loop["last_ai_actions"].size() == 1, "Wait, one AI action, then one controllable successor")
	await point(scene.grid_cell_center_to_logical_position(caster["coord"]))
	check(scene.status_panel.visible, "AI result can be inspected normally")
	await shot("status")
	routes.append({"mode": mode, "receipt": action, "caster_after": compact(caster), "next_actor": scene.selected_unit_id, "index": scene.play_loop["turn_queue"]["index"]})


func until_actor(id: String, observe_support: bool) -> bool:
	var observed := false
	for _attempt in range(800):
		var presentation = scene.get_node("BattlePresentation")
		if observe_support and not observed and presentation.cutin.busy() and presentation.cutin.clips[0]["impact_emitted"]:
			var labels: Array = []
			for child in presentation.status_feedback.get_children():
				if (child is Label and "解毒" in child.text) or (child is Node2D and child.kind == "heal"): labels.append(child)
			check(not labels.is_empty(), "impact has positive HP or cure feedback instead of damage")
			for index in range(labels.size()):
				for other in range(index): check(not feedback_rect(labels[index]).grow(4).intersects(feedback_rect(labels[other]).grow(4)), "multi-target feedback remains separated")
			await shot("impact")
			observed = true
		if observe_support and presentation.cutin.busy() and not tail_checks.has(mode) and presentation.cutin.clips[0].has("effect_timeline"):
			var clip: Dictionary = presentation.cutin.clips[0]
			# The effCode script's completion in the cut-in's elapsed seconds (cast lead + ticks).
			var complete: float = presentation.cutin.Timing.CAST_LEAD_IN + float(clip["effect_timeline"]["complete_tick"]) * presentation.cutin.Timing.PLAYBACK_SPEED / presentation.cutin.skill_effects.TICKS_PER_SECOND
			var remaining: float = complete - presentation.cutin.elapsed
			if remaining <= 0.10:
				var peak := 0.0
				for sprite in presentation.cutin.skill_effects.sprites:
					if sprite.visible: peak = maxf(peak, sprite.modulate.a)
				tail_checks[mode] = {"remaining_seconds": remaining, "maximum_alpha": peak}
				check(not scene.action_menu.is_visible_in_tree(), "controls remain gated during the remaining particle fade")
				await shot("tail")
		if scene.selected_unit_id == id and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not presentation.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding():
			if observe_support:
				var cleared: bool = presentation.cutin.skill_effects.sprites.all(func(sprite): return not sprite.visible or sprite.modulate.a <= 0.001)
				check(cleared and tail_checks.has(mode), "source particles finish their fade before successor controls")
				if tail_checks.has(mode): tail_checks[mode]["cleared_before_controls"] = cleared
				await shot("end")
			return observed
		await create_timer(0.025).timeout
	check(false, "bounded playback reaches " + id)
	return observed


func close_scene() -> void:
	var voices: Array[WeakRef] = []
	for player in scene.find_children("*", "AudioStreamPlayer", true, false):
		if player.playing:
			var deadline := Time.get_ticks_msec() + 1000
			while player.playing and player.get_playback_position() <= 0 and Time.get_ticks_msec() < deadline: await create_timer(0.01).timeout
			if player.playing: voices.append(weakref(player.get_stream_playback()))
		player.stop()
		player.stream = null
	scene.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while voices.any(func(voice): return voice.get_ref() != null) and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(voices.all(func(voice): return voice.get_ref() == null), "audio playback releases after the completed route")
	await create_timer(0.15).timeout


func compact(unit: Dictionary) -> Dictionary:
	var result := {}
	for key in ["id", "actor_id", "hp", "max_hp", "mp", "max_mp", "status_flags", "status_counters", "inventory", "coord"]: result[key] = unit.get(key)
	return result


func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "visible control before real click")
	if control == null: return
	var container := control.get_parent()
	while container != null and not container is ScrollContainer: container = container.get_parent()
	if container is ScrollContainer:
		for _attempt in range(12):
			if container.get_global_rect().encloses(control.get_global_rect()): break
			await hover(container.get_global_rect().get_center())
			var wheel := InputEventMouseButton.new()
			wheel.position = container.get_global_rect().get_center()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN if control.get_global_rect().end.y > container.get_global_rect().end.y else MOUSE_BUTTON_WHEEL_UP
			wheel.pressed = true
			root.push_input(wheel, true)
			wheel = wheel.duplicate()
			wheel.pressed = false
			root.push_input(wheel, true)
			await process_frame
		check(container.get_global_rect().encloses(control.get_global_rect()), "real scrolling exposes the chosen spell")
	await point(control.get_global_rect().get_center())


func hover(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame
	await process_frame


func point(position: Vector2) -> void:
	await hover(position)
	var button := InputEventMouseButton.new()
	button.position = position
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	root.push_input(button, true)
	button = button.duplicate()
	button.pressed = false
	root.push_input(button, true)
	await process_frame
	await process_frame


func escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key, true)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key, true)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + mode + "-" + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(mode + ": " + label)
		push_error(mode + ": " + label)


## A caption Label's rect, or a result number's (ResultNumberFloat) glyph rect at its current rise.
func feedback_rect(node: Node) -> Rect2:
	if node is Node2D:
		var rect: Rect2 = node.bounds()
		return rect if node.number == null else Rect2(rect.position + node.number.position, rect.size)
	return node.get_global_rect()

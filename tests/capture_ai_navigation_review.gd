extends "res://tests/capture_support_magic_review.gd"
## Actual controls and normal presentation clocks over explicit navigation cases.
const run_ai_navigation_tests = preload("res://tests/run_ai_navigation_tests.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DEST := "res://ignored/ai-navigation-review/"
var owner_id := ""
var observations := {}
var actions: Array = []
var sounds := {}
var cues := {"release":0, "impact":0}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Navigation review needs a rendered built-in display")
		quit(2)
		return
	root.title = "HSL AI Navigation Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(DEST)
	create_timer(240).timeout.connect(func(): push_error("AI_NAVIGATION_REVIEW_TIMEOUT"); quit(2))
	var modes: Array = ["detour", "unreachable", "target_death", "wait", "empty_center", "cure_center", "empty_mp", "silenced", "no_action", "player_center", "moving_cast", "defeat"]
	if not OS.get_cmdline_user_args().is_empty(): modes = Array(OS.get_cmdline_user_args())
	for name in modes:
		mode = name
		await prepare_case()
		await play_case()
		await close_scene()
		if not failures.is_empty(): break
	FileAccess.open(DEST + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"overrides":"Source scene WRD and art retained. Synthetic positions/400HP/speeds, two-cell movement (four in moving_cast) and commandable successors. Initial sentinel shares AI side. Source lock100 and aid/use preferences100 only in named cases; no combat RNG override. Area poison/cure explicitly granted to test caster; four recipients on walkable cells around empty (10,9). Detour uses actual blocked (8,9),(8,10),(9,10); unreachable target is in the other real WRD component. Target-death and defeat author a 1HP victim and caster hit_bonus_accum1000; target-death also supplies the existing target lock. Outcomes use the native strike. No artificial wall, result assignment or clock acceleration.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"routes":routes,"failures":failures},"  "))
	print("AI_NAVIGATION_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size())
	quit(0 if failures.is_empty() else 1)


func prepare_case() -> void:
	observations = {}
	actions = []
	sounds = {}
	cues = {"release":0, "impact":0}
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.2).timeout
	scene.get_node("BattleMusic").stop()
	var kind := "empty_center" if mode == "player_center" else "cast" if mode == "moving_cast" else mode
	var loop := run_ai_navigation_tests.fixture(kind)
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	var actor: Dictionary = loop["units"][0]
	owner_id = str(actor["id"])
	var target: Dictionary = loop["units"][1]
	var successor: Dictionary = loop["units"][2]
	if mode in ["empty_center", "cure_center", "player_center"]:
		for unit in loop["units"]: unit["coord"] += Vector2i(3,4)
		if mode == "player_center": actor["player_commandable"] = true
	else:
		actor["coord"] = Vector2i(7,10)
		target["coord"] = Vector2i(10,10)
		successor["coord"] = Vector2i(14,14)
		if mode == "wait":
			target["coord"] = Vector2i(18,14)
			successor["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		elif mode == "unreachable":
			actor["coord"] = Vector2i(7,9)
			target["coord"] = Vector2i(6,6)
			successor["coord"] = Vector2i(13,10)
		elif mode == "target_death":
			actor["coord"] = Vector2i(8,8)
			actor["hit_bonus_accum"] = 1000
			actor["ai_target_id"] = "enemy023_1"
			target["coord"] = Vector2i(12,10)
			successor["coord"] = Vector2i(9,8)
			successor["hp"] = 1
		elif mode == "moving_cast":
			actor["move_point"] = 4
			target["coord"] = Vector2i(11,9)
			for id in ["magic:magicAIR:magicCode01", "magic:magicFIRE:magicCode01"]: TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "100"
		elif mode == "defeat":
			actor["coord"] = Vector2i(8,8)
			actor["hit_bonus_accum"] = 1000
			target["coord"] = Vector2i(9,8)
			target["hp"] = 1
	var initial := BattlePlayLoop.unit(scene.play_loop,"enemy024_1")
	initial.merge({"id":"navigation-initial","coord":Vector2i(6,9),"hp":400,"max_hp":400,"player_commandable":true,"live_speed":110,"inventory":[0,0,0,0,0,0,0,0]},true)
	initial["battle_actor_role"] = actor["battle_actor_role"]
	loop["units"].append(initial)
	for unit in loop["units"]:
		unit["grid_coord"] = unit["coord"]
		unit["ai_home_coord"] = unit["coord"]
		check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false), "fixture participant stands on actual walkable WRD")
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop._return_to_player(loop,"navigation-initial"), "test")
	for child in scene.actors_root.get_children(): scene.actors_root.remove_child(child); child.queue_free()
	scene.unit_grid_coords.clear()
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(Vector2i(9,9))
	var view = scene.get_node("BattlePresentation")
	view.cutin.released.connect(func(_s,_a,_d,_c): cues["release"] += 1)
	view.cutin.impact.connect(func(_s,_a,_d,_c): cues["impact"] += 1)
	scene.set_process(true)
	await create_timer(0.35).timeout


func play_case() -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	await shot("before")
	await click(scene.action_menu.get_node("WaitCommand"))
	if mode == "defeat":
		await defeat_case()
		return
	if mode == "player_center":
		await quiet_actor(owner_id)
		await click(scene.action_menu.get_node("MagicCommand"))
		await click(scene.magic_panel.choices[run_ai_navigation_tests.POISON])
		var center: Vector2 = scene.grid_cell_center_to_logical_position(Vector2i(10,9))
		await hover(center)
		var view = scene.get_node("BattlePresentation")
		check(view.target_vitals.visible and view.combat_label.text.contains("4"), "empty-cell hover previews all four real targets")
		await shot("preview")
		var selected: Dictionary = scene.play_loop.duplicate(true)
		await escape()
		check(scene.play_loop["units"] == selected["units"] and scene.play_loop["turn_queue"] == selected["turn_queue"], "actual cancel preserves all target HP/status, MP and queue")
		await create_timer(0.25).timeout
		await click(scene.action_menu.get_node("MagicCommand"))
		await click(scene.magic_panel.choices[run_ai_navigation_tests.POISON])
		await point(center)
		await quiet_actor("enemy023_1")
		var receipt: Dictionary = scene.play_loop["last_combat"]
		check(receipt.get("cast_center") == Vector2i(10,9) and receipt["affected_targets"].size() == 4, "real empty-ground click commits the common area cast")
		actions.append(receipt.duplicate(true))
	elif mode == "target_death":
		await quiet_actor("leonard")
		remember_action()
		check(actions[0].get("defender_id") == "enemy023_1" and actions[0]["defender_hp_after"] == 0 and BattlePlayLoop.unit(scene.play_loop,owner_id)["ai_target_id"] == "", "real lethal strike clears the held target after death presentation")
		await click(scene.action_menu.get_node("WaitCommand"))
		await quiet_actor("navigation-initial")
		await click(scene.action_menu.get_node("WaitCommand"))
		await quiet_actor("leonard")
		remember_action()
		check(actions[1].get("toward",actions[1].get("target_id")) == "leonard", "next actual AI turn replaces the dead target and starts a legal new action")
	else:
		await quiet_actor("enemy023_1")
		remember_action()
		if mode == "detour":
			check(actions[0]["kind"] == "move" and actions[0]["path"].size() == 2 and actions[0]["cost"] == 1, "occupied flank consumes onward clearance: first action stops on the last affordable cell")
			for _round in range(6):
				if actions.back()["kind"] == "move_then_attack": break
				await next_observed_turn()
			check(actions.size() >= 3 and actions[1]["ai_decision"]["target_selection"]["retained"] and actions.back()["kind"] == "move_then_attack", "actual later rounds retain the target, pay clearance costs, finish the wall detour and attack")
			for action in actions:
				var costs := BattlePlayLoop.TacticalGridRules.path_costs(action["path"], before["units"], before["tiles"], owner_id)
				check(not costs.is_empty() and int(costs.back()) <= 2, "each actual detour respects two movement points including occupied-neighbor clearance")
		if mode == "wait": check(actions[0]["kind"] == "wait" and BattlePlayLoop.unit(scene.play_loop,owner_id)["ai_wait_remaining"] == 2 and observations.has("wait"), "real Wait input produces a visible AI wait and exactly one decrement")
		if mode == "unreachable": check(actions[0].get("toward") == "enemy023_1", "actual AI rejects the sealed-off nearer target and follows a route to the reachable actor")
		if mode == "no_action": check(actions[0]["kind"] == "wait" and observations.has("wait") and cues["impact"] == 0, "no legal category shows an honest wait, then returns control")
		if mode in ["empty_mp", "silenced"]: check(not actions[0].has("skill_id") and BattlePlayLoop.unit(scene.play_loop,owner_id)["mp"] == BattlePlayLoop.unit(before,owner_id)["mp"], "missing resource/status uses a legal movement fallback without paying magic")
		if mode in ["empty_center", "cure_center"]: check(actions[0].get("cast_center") == Vector2i(10,9) and actions[0].get("affected_targets",[]).size() == 4 and observations.has("impact"), "actual AI selects empty ground and presents all four outcomes")
		if mode == "moving_cast":
			for _round in range(3):
				if actions.back().has("magic_key"): break
				await next_observed_turn()
			var last: Dictionary = actions.back()
			var costs := BattlePlayLoop.TacticalGridRules.path_costs(last["path"], before["units"], before["tiles"], owner_id)
			check(last["kind"] == "move_then_attack" and last.has("magic_key") and costs.size() > 1 and int(costs.back()) <= 4 and observations.has("path") and observations.has("impact"), "affordable pursuit followed by a moving source cast completes with one MP payment")
			check(actions[0]["kind"] == "move" and actions[0]["cost"] == 4 and not actions[0].has("resource_payment"), "the first long approach pays only movement; the later cast owns the sole MP debit")
	var view = scene.get_node("BattlePresentation")
	check(not view.navigation_cue.visible and not view.navigation_cue.busy() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop), "path/wait and combat feedback are cleared before successor control")
	if mode == "moving_cast":
		# Wind/fire own the source cast/effect sounds and intentionally do not emit
		# the ordinary swing-release signal. Observe the real cast lead and mixer.
		check(cues["impact"] == 1 and observations.has("cast_lead") and sounds.keys().any(func(path): return path.ends_with("cast_magic.wav")), "moving magic has one impact and actual casting audio after arrival")
	elif actions.any(func(action): return action.has("skill_id")):
		check(cues == {"release":1,"impact":1} and not sounds.is_empty(), "one supported status/heal clip release/impact with actual mixer playback")
	await shot("handoff")
	routes.append({"mode":mode,"actions":actions,"observations":observations,"cues":cues,"sounds":sounds.keys(),"owner_after":compact(BattlePlayLoop.unit(scene.play_loop,owner_id)),"next_actor":scene.selected_unit_id,"round":scene.play_loop["turn_queue"]["round"]})


func defeat_case() -> void:
	var view = scene.get_node("BattlePresentation")
	for _attempt in range(800):
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"]: observations["impact"] = true
		if view.dialogue_active():
			if not observations.has("closing"):
				observations["closing"] = true
				await shot("closing")
			await key(KEY_SPACE)
		if view.battle_finished: break
		await create_timer(0.025).timeout
	check(view.battle_finished and scene.play_loop["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN and observations.has("impact") and observations.has("closing"), "real lethal AI action completes its impact and closing dialogue before defeat")
	var final: Dictionary = scene.play_loop.duplicate(true)
	remember_action()
	check(final["units"].all(func(unit): return unit["ai_target_id"] == "" and unit["ai_call_target_id"] == ""), "defeat clears every pending AI target")
	await create_timer(0.15).timeout
	check(scene.play_loop == final and not scene.action_menu.visible and not view.navigation_cue.visible, "terminal playback cannot replan, attack or advance another actor")
	check(scene.ui_audio.stream.resource_path == scene.ui_sounds["game_over"]["res_path"], "actual defeat plays the registered Game Over cue")
	await shot("result")
	reload_current_scene()
	await create_timer(0.4).timeout
	scene = current_scene
	check(scene != null and not BattleOutcome.decided(scene.play_loop) and scene.play_loop["units"].all(func(unit): return unit["ai_target_id"] == ""), "actual mouse restart initializes fresh navigation state")
	routes.append({"mode":mode,"actions":actions,"observations":observations,"cues":cues,"outcome":final["battle_outcome"],"restart":true})


func remember_action() -> void:
	var action: Dictionary = scene.play_loop["last_ai_action"].duplicate(true)
	check(action["actor_id"] == owner_id, "the actual AI owner produced this action")
	actions.append(action)


func next_observed_turn() -> void:
	await click(scene.action_menu.get_node("WaitCommand"))
	await quiet_actor("leonard")
	await click(scene.action_menu.get_node("WaitCommand"))
	await quiet_actor("navigation-initial")
	await click(scene.action_menu.get_node("WaitCommand"))
	await quiet_actor("enemy023_1")
	remember_action()


func quiet_actor(id: String) -> void:
	for _attempt in range(1600):
		var view = scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position() > 0: sounds[sound.stream.resource_path] = true
		if view.navigation_cue.visible:
			var phase := "wait" if view.navigation_cue.busy() else "path"
			if not observations.has(phase):
				observations[phase] = true
				check(not scene.action_menu.visible, "navigation feedback holds the successor menu")
				await shot(phase)
		if view.attack_cue.visible and not observations.has("target"):
			observations["target"] = true
			await shot("target")
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"] and not observations.has("impact"):
			observations["impact"] = true
			await shot("impact")
		if mode == "moving_cast" and view.cutin.busy() and view.cutin.clips[0].get("cast_started",false) and not observations.has("cast_lead"):
			observations["cast_lead"] = true
			check(not scene.has_actor_motion() and not view.navigation_cue.visible, "source casting starts only after the actual path is finished")
			await shot("cast-lead")
		if view.dialogue_active(): await key(KEY_SPACE)
		if scene.growth_panel.visible: scene.growth_panel.hide() # harness skip seam
		if scene.settlement_controller.panel.visible:
			var loot = scene.settlement_controller.panel
			if loot.rows.is_empty() or loot.first_empty_slot() < 0: await click(loot.finish_button)
			else: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
		if scene.selected_unit_id == id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not scene.has_actor_motion() and not view.combat_busy(scene.play_loop): return
		await create_timer(0.025).timeout
	check(false,"bounded normal-clock gameplay reaches " + id)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(DEST + mode + "-" + label + ".png") == OK,"capture " + label)

extends "res://tests/capture_ordinary_special_review.gd"
## Real buttons/map input, unchanged clocks, source art/audio and explicit fixtures.
const run_extra_attack_tests = preload("res://tests/run_extra_attack_tests.gd")
const OUTPUT := "res://ignored/extra-attack-review/"
var snapshots: Array = []


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Extra attack review requires a rendered window on the built-in display")
		quit(2)
		return
	root.title = "HSL Extra Attack Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(300).timeout.connect(func():push_error("EXTRA_ATTACK_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["equip_move","double_counter","early_kill","late_kill","counter_defeat","ai_move","miss","special","final_kill","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await prepare_case()
		await play_case()
		await close_scene()
		FileAccess.open(OUTPUT + "progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(OUTPUT + "receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"normal_clock":Engine.time_scale,
		"accuracy_note":"The miss route sets source hit0 and target avoid20, yielding native minimum10 percent before compensation, not forced zero accuracy. Each blow is checked against its observed result.",
		"overrides":"Three source-rendered actors, controlled positions/speeds and HP500; low-HP targets1/23 and counter victim21 exercise early/late death. All non-equipment numeric routes explicitly use attack20, equal STR/DEX20, hit100 (miss route0), counter/critical0 or100 and synthetic innate extra capability on source001/021. Equip route uses actual item12, its source refresh and original probabilities. Real WRD, animations, audio, target/cancel controls and runtime clocks retained. Kill routes start99EXP/chain1 and carry medicine241 with deterministic reward seed17; escape/final-clear start after the source report. No combat RNG substitution, time acceleration or assigned combat result. Default battle grants, inventory and actors are unchanged.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"routes":routes,"failures":failures},"  "))
	print("EXTRA_ATTACK_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func prepare_case() -> void:
	observed = {}; sound_paths = {}; cues = []; experience_events = []; receipt = {}; snapshots = []
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := run_extra_attack_tests.fixture(mode != "equip_move" and mode != "counter_defeat", mode in ["double_counter","counter_defeat","ai_move"])
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	for unit in loop["units"]: unit["hp"] = 500; unit["max_hp"] = 500
	var owner := BattlePlayLoop.unit_ref(loop,"leonard")
	var target := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	if mode == "equip_move":
		owner["inventory"] = [12,0,0,0,0,0,0,0]
		target["coord"] = Vector2i(10,8)
	if mode == "double_counter":
		owner["combat_profile"]["attack_damagex2"] = 100
		target["combat_profile"].merge({"attack_damagex2":100,"attack_back":100},true)
	if mode in ["early_kill","late_kill","final_kill"]:
		target["hp"] = 1 if mode == "early_kill" else 23
		target["inventory"] = [241,0,0,0,0,0,0,0]
		target["combat_profile"]["attack_back"] = 100
		owner["exp"] = 99
		owner["kill_chain_word"] = 1
		var drops_stream: GDScript = preload("res://game/sim/GlobalRandomStream.gd")
		loop[drops_stream.LOOP_KEY] = drops_stream.seeded(17)  # first drop roll 36: 241 (ratio 50) drops
	if mode == "counter_defeat":
		owner["hp"] = 21
		target["combat_profile"]["attack_back"] = 100
	if mode == "ai_move":
		owner["live_speed"] = 120
		owner["combat_profile"]["attack_back"] = 100
		target["coord"] = Vector2i(11,8)
		target["live_speed"] = 110
		target["move_point"] = 3
		TestSuite.own(loop, "ai_profiles")["actors"]["021"]["profile"].merge({"find_range":30,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_magic":0},true)
	if mode == "miss":
		owner["combat_profile"]["live_hit_ratio"] = 0
		target["combat_profile"]["avoid_hit_ratio"] = 20
	if mode == "special":
		owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"no_magic",2)["changes"],true)
		BattlePlayLoop.skill_fields(loop,"special:magicOTHER:magicCode01")["hit_ratio"] = "100"
	if mode in ["final_kill","escape"]:
		loop["turn"] = 6
		scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
		if mode == "escape":
			BattlePlayLoop.unit_ref(loop,"leonard")["coord"] = loop["escape_zone"][0]
			BattlePlayLoop.unit_ref(loop,"leonard")["exp"] = 23
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"leonard"), "test")
	scene.settlement_controller.checkpoint_path = OUTPUT + mode + ".save"
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear()
	for unit in scene.play_loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"])
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):experience_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(s,_a,_d,c):cues.append(["release",c,int(s.get("strike_number",1))]))
	view.cutin.impact.connect(func(s,_a,_d,c):cues.append(["impact",c,int(s.get("strike_number",1))]))
	scene.set_process(true)
	await create_timer(0.3).timeout


func play_case() -> void:
	if mode == "equip_move":
		await equip(12,true)
		check(BattlePlayLoop.attack_count(scene.play_loop,BattlePlayLoop.unit(scene.play_loop,"leonard"))["count"] == 2,"actual sword confirmation enables one extra strike")
		var old_coord: Vector2i = BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]
		await click(scene.action_menu.get_node("MoveCommand"))
		check(BattlePlayLoop.movement_cells(scene.play_loop).has(Vector2i(9,8)),"source map has a legal approach to the target")
		await point(scene.grid_cell_center_to_logical_position(Vector2i(9,8)))
		for _attempt in range(200):
			if not scene.has_actor_motion() and scene.action_menu.visible and not scene.action_menu.is_expanding(): break
			await create_timer(0.02).timeout
		check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] != old_coord and scene.pending_move_revert,"real Move reaches a pending position before attack")
	var before: Dictionary = scene.play_loop.duplicate(true)
	if mode in ["ai_move","escape"]:
		await click(scene.action_menu.get_node("WaitCommand"))
	else:
		var command := "SpecialCommand" if mode == "special" else "AttackCommand"
		await click(scene.action_menu.get_node(command))
		if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
		await hover(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
		check(scene.interaction_state == "attack_select","real control enters targeting")
		check(not scene.get_node("BattlePresentation").combat_label.visible,"target preview shows no overhead 命中／2擊 line (UI6 照原版)")
		await shot("target")
		await escape()
		check(scene.play_loop["units"] == before["units"] and scene.play_loop["turn_queue"] == before["turn_queue"],"actual targeting cancellation preserves movement, HP, resources and EXP")
		await create_timer(0.3).timeout
		await click(scene.action_menu.get_node(command))
		if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
		await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
		receipt = scene.play_loop["last_attack"].duplicate(true)
	await await_finished()
	if mode == "escape":
		check(cues.is_empty() and experience_events.is_empty() and BattlePlayLoop.unit(scene.play_loop,"leonard")["exp"] == 23,"Wait/escape does not turn the extra-hit passive into a second action or EXP award")
	else:
		var strikes := BattlePlayLoop.CombatSequence.strikes(receipt)
		var expected: Array = []
		for strike in strikes:
			expected.append(["release",bool(strike.get("is_counter",false)),int(strike.get("strike_number",1))])
			expected.append(["impact",bool(strike.get("is_counter",false)),int(strike.get("strike_number",1))])
		check(cues == expected,"every accepted main/additional/counter blow releases and impacts exactly once in order")
		check(strikes.size() == (4 if mode in ["double_counter","ai_move"] else 3 if mode == "counter_defeat" else 1 if mode in ["early_kill","special"] else 2),"normal playback has exactly the source-authorized number of blows")
		var expected_exp: Array = []
		for series in [receipt,receipt.get("counter",{})]:
			if series.has("experience"): expected_exp.append(series["experience"])
		check(experience_events == expected_exp,"all participant EXP appears once after all blows, including counter contributions")
		check(not sound_paths.is_empty(),"actual source audio advances during playback")
		if mode == "ai_move": check(observed.has("movement") and receipt["attacker_id"] == "enemy021_1" and scene.play_loop["last_ai_actions"].size() == 1,"AI movement, two blows and two counterblows are one accepted action")
		if mode in ["early_kill","late_kill","final_kill"]:
			check(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["defeated"] and receipt["rewards"]["kills"].size() == 1 and observed.has("dialogue") and observed.has("experience"),"early/late lethal hit retains actor until dialogue and earns one kill/EXP award")
		if mode == "miss":
			check(strikes.any(func(hit):return not hit["hit"]),"low-accuracy real input route includes a naturally missed blow")
			for hit in strikes:
				if not hit["hit"]: check(hit["actual_damage"] == 0 and hit["experience_basis"]["points"] == 0,"a missed blow has no fake damage or EXP even when another blow hits")
		if mode == "special": check(BattlePlayLoop.unit(scene.play_loop,"leonard")["stamina"] == 0,"extra attack does not duplicate a legal special under silence or charge it twice")
		if mode not in ["counter_defeat","final_kill"]: check(scene.play_loop["turn_queue"]["index"] == (2 if mode == "ai_move" else 1),"entire series hands control to exactly the expected successor")
	var terminal := mode in ["counter_defeat","final_kill","escape"]
	if terminal:
		var saved: Dictionary = scene.play_loop.duplicate(true)
		await key(KEY_F5)
		await key(KEY_F9)
		check(scene.play_loop == saved,"terminal save/load preserves every hit, kill and final award without replay")
		await shot("restored")
	routes.append({"mode":mode,"receipt":receipt,"actor":compact(BattlePlayLoop.unit(scene.play_loop,"leonard")),"cues":cues,"experience_events":experience_events,"observed":observed,"snapshots":snapshots,"sounds":sound_paths.keys(),"outcome":scene.play_loop["battle_outcome"],"next_actor":scene.selected_unit_id})
	if terminal:
		reload_current_scene()
		for _attempt in range(20):
			if is_instance_valid(current_scene): break
			await process_frame
		scene = current_scene
		var restarted: bool = is_instance_valid(scene) and not BattleOutcome.decided(scene.play_loop) and BattlePlayLoop.unit(scene.play_loop,"leonard")["hp"] == 30
		check(restarted,"real retry starts the unchanged default battle")
		routes.back()["restarted"] = restarted


func await_finished() -> void:
	var terminal := mode in ["counter_defeat","final_kill","escape"]
	for _attempt in range(2000):
		var view = scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position() > 0: sound_paths[sound.stream.resource_path] = true
		if mode == "ai_move" and scene.has_actor_motion() and not observed.has("movement"):
			observed["movement"] = true
			receipt = scene.play_loop["last_combat"].duplicate(true)
			check(not view.cutin.busy(),"accepted AI movement finishes before the first attack shot")
			await shot("movement")
		if view.cutin.busy() and view.cutin.elapsed > 0.005:
			var clip: Dictionary = view.cutin.clips[0]
			var hit: Dictionary = clip["strike"]
			var tag := ("counter" if clip["counter"] else "main") + str(int(hit.get("strike_number",1))) + ("-impact" if clip["impact_emitted"] else "-windup")
			if not observed.has(tag):
				observed[tag] = true
				check(not scene.action_menu.visible and not view.aftermath.reward_label.visible and not view.battle_finished,"all controls, rewards and result wait for the whole series")
				if not hit.has("skill_name"):
					var target_shot: bool = view.cutin.defender_sprite.visible
					var snapshot: Dictionary = hit["defender_before" if target_shot else "attacker_before"]
					var expected_st: int = snapshot["stamina"]
					if hit.has("stamina_gain"): expected_st = hit["stamina_gain"]["defender" if target_shot else "attacker"]["after" if clip["impact_emitted"] else "before"]
					check(view.cutin.vitals.st_bar.value == expected_st,"actual shot never leaks a later blow's stamina")
					snapshots.append({"tag":tag,"st":view.cutin.vitals.st_bar.value,"hp":view.cutin.vitals.values["hp"].text,"caption":view.cutin.result.text})
				await shot(tag)
			# The number spawns after the hit (ordinary: 40 ticks; a miss spawns none).
			if clip["impact_emitted"] and not observed.has(tag + "-number") and view.cutin.result_number.visible and view.cutin.result_number.get_children().any(func(number): return number.showing()):
				observed[tag + "-number"] = true
				check(view.cutin.result_text().split("\n")[0] == ("%d" % hit["actual_damage"] if hit["hit"] else "MISS"),"actual shot displays its own capped loss or MISS alone")
		if view.dialogue_active():
			if not observed.has("dialogue"): observed["dialogue"] = true; await shot("dialogue")
			await key(KEY_SPACE)
		if view.aftermath.reward_label.visible and not observed.has(view.aftermath.stage):
			observed[view.aftermath.stage] = true
			check(not view.cutin.busy(),"EXP/kill/gold begin after the final receiver shot")
			await shot(view.aftermath.stage)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			observed["loot"] = true
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			if not observed.has("growth"): observed["growth"] = true; await shot("growth")
			for attribute in ["str","str","dex","mind","con"]: await click(scene.growth_panel.choices[attribute]["plus"])
			await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			var expected := BattleOutcome.DEFEAT_FALLEN if mode == "counter_defeat" else BattleOutcome.VICTORY_ESCAPE if mode == "escape" else BattleOutcome.VICTORY_ENEMIES_CLEARED
			check(scene.play_loop["battle_outcome"] == expected,"the final committed series reaches the intended battle boundary")
			await shot("result")
			return
		if not terminal and scene.selected_unit_id == "enemy023_1" and scene.action_menu.is_visible_in_tree() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding():
			await shot("handoff")
			return
		await create_timer(0.02).timeout
	check(false,"bounded extra attack route reaches expected control/result")


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUTPUT + mode + "-" + label + ".png") == OK,"capture " + label)

extends "res://tests/capture_equipment_mobility_review.gd"
## Source terrain and actors, actual controls; synthetic encounter and trait grants.
const run_actor_traversal_tests = preload("res://tests/run_actor_traversal_tests.gd")
const TRAVERSAL_OUT := "res://ignored/actor-traversal-review/"
var owner_id := "leonard"
var transit_id := "traversal-ally"
var intended := ""
var cast_id := ""
var supplied_route := {}


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Traversal review requires a rendered built-in window"); quit(2); return
	root.title = "HSL Actor Traversal Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(TRAVERSAL_OUT)
	create_timer(300).timeout.connect(func():push_error("TRAVERSAL_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["ally_attack","ally_cast","ally_support","restore","flying","ai_cutoff","ai_cast","ai_support","ai_no_mp","ai_silence","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_traversal()
		if failures.is_empty(): await play_traversal()
		await close_scene()
		FileAccess.open(TRAVERSAL_OUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(TRAVERSAL_OUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"overrides":"Source WRD height packets and source art retained, no artificial terrain walls. Encounter positions, speeds, HP/maxHP and commandable successor are supplied. Players receive WIND/HEAL only in named spell cases; flying supplies the independently proven source trait to test Leonard, not a new default ability or flying sprite set. AI uses real026, source spells/probabilities set100 for selected category, healthy same-side blocker and commandable sentinel. Final-clear/defeat set1HP and hit_bonus1000; final clear starts99EXP. Victory/escape start after the scripted report. No RNG replacement, assigned damage/outcome or accelerated clock; controls own all changes after setup.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"routes":routes,"failures":failures},"  "))
	print("ACTOR_TRAVERSAL_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_traversal() -> void:
	observed = {}; cues = []; sound_paths = {}; experience_events = []; receipt = {}; changes = []; supplied_route = {}; cast_id = ""
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene); current_scene = scene
	scene.start_dev_first_control_harness(); scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := BattleFixture.loop()
	var player := BattlePlayLoop.unit(loop,"leonard")
	var enemy := BattlePlayLoop.unit(loop,"enemy021_1")
	var successor := BattlePlayLoop.unit(loop,"enemy023_1")
	var transit := successor.duplicate(true)
	transit.merge({"id":transit_id,"coord":Vector2i(9,8),"live_speed":40,"player_commandable":false,"battle_actor_role":BattlePlayLoop.ROLE_FRIENDLY},true)
	player.merge({"coord":Vector2i(8,8),"hp":100,"max_hp":100,"mp":100,"max_mp":100,"live_speed":120,"inventory":[193,0,0,0,0,0,0,0]},true)
	player["combat_profile"].merge({"mind":20,"live_magic_attack":100},true)
	enemy.merge({"coord":Vector2i(11,8),"hp":400,"max_hp":400,"live_speed":70},true)
	successor.merge({"coord":Vector2i(16,14),"hp":100,"max_hp":100,"live_speed":100,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER},true)
	loop["units"] = [player,enemy,successor,transit]
	loop["reinforcement_templates"] = []
	owner_id = "leonard"; landing = Vector2i(10,8); intended = "attack"
	if mode in ["ally_cast","ally_support"]:
		cast_id = run_actor_traversal_tests.WIND if mode == "ally_cast" else run_actor_traversal_tests.HEAL
		TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = [cast_id]
		if mode == "ally_support": successor["coord"] = Vector2i(11,8); successor["hp"] = 4; enemy["coord"] = Vector2i(17,18)
	if mode in ["restore","flying","escape"]: enemy["coord"] = Vector2i(17,18)
	if mode == "flying":
		player["coord"] = Vector2i(7,9); landing = Vector2i(6,6)
		check(BattlePlayLoop.movement_path(loop,"leonard",landing).is_empty(),"original ground barrier separates the flight destination")
		TestSuite.own(loop, "skill_book")["actors"]["001"]["traversal"]["flying"] = true
		player["traversal"]["flying"] = true
	if mode.begins_with("ai_"):
		var original := BattleFixture.loop()
		var ai := BattlePlayLoop.unit(original,"enemy026_1")
		owner_id = ai["id"]
		ai.merge({"coord":Vector2i(8,8),"hp":100,"max_hp":100,"mp":100,"max_mp":100,"base_move_point":4,"move_point":4,"live_speed":110,"inventory":[0,0,0,0,0,0,0,0]},true)
		ai["combat_profile"].merge({"mind":20,"live_magic_attack":100},true)
		player.merge({"coord":Vector2i(12,9),"hp":400,"max_hp":400,"live_speed":70},true)
		successor["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		transit["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		var initial := BattlePlayLoop.unit(original,"enemy024_1")
		initial.merge({"id":"traversal-initial","coord":Vector2i(6,14),"hp":100,"max_hp":100,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_ENEMY,"live_speed":130},true)
		loop["units"] = [ai,player,successor,transit,initial]
		var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]
		profile.merge({"find_range":10,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_magic":100,"lock_target":100},true)
		if mode == "ai_support":
			cast_id = run_actor_traversal_tests.HEAL
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [cast_id]
			TestSuite.own(loop, "skill_book")["skills"][cast_id]["fields"]["use_ratio"] = "100"
			profile.merge({"ai_check_hp":100,"ai_help_otherhp":100},true)
			successor["coord"] = Vector2i(12,9); successor["hp"] = 4; player["coord"] = Vector2i(18,18)
		elif mode == "ai_cast":
			cast_id = run_actor_traversal_tests.WIND
			TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
			TestSuite.own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
		elif mode == "ai_silence": ai.merge(BattlePlayLoop.StatusEffectRules.apply(ai,"no_magic",2)["changes"],true)
		else: ai["mp"] = 0
		intended = "move_then_attack"
		if mode == "ai_cutoff": ai["base_move_point"] = 1; ai["move_point"] = 1; intended = "wait"
	if mode == "defeat":
		player["hp"] = 1
		enemy["live_speed"] = 110; enemy["hit_bonus_accum"] = 1000; enemy["combat_profile"]["live_attack_damage"] = 200
		transit["coord"] = Vector2i(10,8); transit["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	if mode in ["victory","escape"]:
		scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
		player = BattlePlayLoop._unit(loop,"leonard"); enemy = BattlePlayLoop._unit(loop,"enemy021_1"); transit = BattlePlayLoop._unit(loop,transit_id)
		if mode == "victory": player["hit_bonus_accum"] = 1000; player["exp"] = 99; enemy["hp"] = 1
		else:
			landing = loop["escape_zone"][0]
			var found := false
			for y in range(loop["map_size"].y):
				for x in range(loop["map_size"].x):
					var cell := Vector2i(x,y)
					if loop["tiles"].get(cell,{}).get("blocks_movement",false) or BattlePlayLoop.unit_id_at_coord(loop,cell) not in ["","leonard"]: continue
					player["coord"] = cell
					var path := BattlePlayLoop.movement_path(loop,"leonard",landing)
					if path.size() >= 3 and path.size() <= 5:
						transit["coord"] = path[1]
						var updated := BattlePlayLoop.movement_path(loop,"leonard",landing)
						if updated.has(transit["coord"]): found = true; break
				if found: break
			check(found,"actual source escape zone has a legal path through a teammate")
	for unit in loop["units"]:
		unit["grid_coord"] = unit["coord"]; unit["ai_home_coord"] = unit["coord"]
		check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false),"each fixture participant begins on source walkable ground")
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop._return_to_player(loop,"traversal-initial" if mode.begins_with("ai_") else "leonard"), "test")
	scene.settlement_controller.checkpoint_path = TRAVERSAL_OUT+mode+".save"
	for child in scene.actors_root.get_children(): scene.actors_root.remove_child(child); child.queue_free()
	scene.unit_grid_coords.clear(); scene.resume_turn_presentation()
	scene.center_camera_on_grid(BattlePlayLoop.unit(loop,owner_id)["coord"])
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):experience_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(s,_a,_d,c):cues.append(["release",s["attacker_id"],c]))
	view.cutin.impact.connect(func(s,_a,_d,c):cues.append(["impact",s["attacker_id"],c]))
	scene.set_process(true)
	await create_timer(0.35).timeout


func play_traversal() -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	var view = scene.get_node("BattlePresentation")
	var terminal := mode in ["victory","defeat","escape"]
	if mode.begins_with("ai_") or mode == "defeat":
		await click(scene.action_menu.get_node("WaitCommand"))
		await finish_battle(terminal)
		receipt = scene.play_loop["last_ai_action"].duplicate(true)
		if mode != "defeat":
			check(receipt["actor_id"] == owner_id and receipt["kind"] == intended,"actual Wait produces the expected single AI traversal action")
			check(scene.play_loop["last_ai_actions"].size() == 1,"AI finishes only one action before the commandable successor")
			if mode == "ai_cutoff": check(BattlePlayLoop.unit(scene.play_loop,owner_id)["coord"] == BattlePlayLoop.unit(before,owner_id)["coord"],"AI does not stop on the ally at its budget cutoff")
			else:
				check(receipt["path"].has(BattlePlayLoop.unit(before,transit_id)["coord"]) and receipt["path"].back() != BattlePlayLoop.unit(before,transit_id)["coord"],"AI crosses its teammate and stops at a legal casting or attack position")
				if cast_id != "": check(receipt.get("skill_id") == cast_id and receipt.has("resource_payment"),"the arrived AI performs the chosen source spell once")
				else: check(not receipt.has("skill_id") and BattlePlayLoop.unit(scene.play_loop,owner_id)["mp"] == BattlePlayLoop.unit(before,owner_id)["mp"],"missing MP or silence retains the physical fallback without a spell debit")
	else:
		await click(scene.action_menu.get_node("MoveCommand"))
		var origin: Vector2i = BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]
		if mode != "flying":
			var ally_point: Vector2 = scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,transit_id)["coord"])
			await hover(ally_point)
			check(view.selection_cursor.caption.text.contains("可通過，不能停留") and not view.selection_cursor.eligible,"actual hover explains transit-only occupancy")
			await shot("transit")
			var selected: Dictionary = scene.play_loop.duplicate(true)
			await point(ally_point)
			check(scene.play_loop == selected,"actual click on a transit-only unit cannot commit movement")
		await hover(scene.grid_cell_center_to_logical_position(landing))
		check(view.movement_preview.visible and view.selection_cursor.eligible and view.selection_cursor.caption.text.contains(" / "),"legal hover exposes the same route and cost used by confirmation")
		if mode == "flying": check(view.selection_cursor.caption.text.begins_with("飛行"),"flight movement is distinguishable in actual selection feedback")
		supplied_route = BattlePlayLoop._movement_envelope(scene.play_loop,"leonard")["reachable_by_coord"].get(landing,{})
		await shot("path")
		await escape()
		await create_timer(0.25).timeout
		check(not view.movement_preview.visible and scene.play_loop["units"] == before["units"],"cancelling selection clears the path without spending resources")
		await move_to(landing)
		check(not view.movement_preview.visible,"the preview is cleared during and after the actual walk")
		if mode in ["restore","flying"]:
			if mode == "restore": await wear(193,"foot",6,true)
			await save_restore()
			await escape(); await process_frame
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] == origin and scene.interaction_state == "move_select","restored movement cancels back to the original point")
			await escape(); await create_timer(0.25).timeout
			await move_to(landing)
			await click(scene.action_menu.get_node("WaitCommand"))
		elif mode == "escape": await click(scene.action_menu.get_node("WaitCommand"))
		elif cast_id != "":
			await click(scene.action_menu.get_node("MagicCommand")); await click(scene.magic_panel.choices[cast_id])
			await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy023_1" if mode == "ally_support" else "enemy021_1")["coord"]))
			receipt = scene.play_loop["last_attack"].duplicate(true)
			check(receipt.get("skill_id") == cast_id,"actual post-move magic or support commits the chosen ability")
		else: await attack_target()
		await finish_battle(terminal)
		if mode == "ally_support": check(receipt["healing"] > 0 and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"] == 94,"post-passage support presents positive recovery and one MP fee")
		if mode == "victory": check(BattlePlayLoop.unit(scene.play_loop,"leonard")["level"] == 2,"the lethal post-passage strike includes final EXP and one level up")
	check(not view.movement_preview.visible and not view.navigation_cue.visible and not scene.ai_playback_active,"movement previews and AI paths clear before a successor or result")
	if terminal: await save_restore()
	routes.append({"mode":mode,"route":supplied_route,"receipt":receipt,"observed":observed,"cues":cues,"experience":experience_events,
		"owner_after":compact(BattlePlayLoop.unit(scene.play_loop,owner_id)),"traits":BattlePlayLoop.unit(scene.play_loop,owner_id)["traversal"],
		"outcome":scene.play_loop["battle_outcome"],"next_actor":scene.selected_unit_id,"sounds":sound_paths.keys()})
	if terminal:
		reload_current_scene(); await create_timer(0.3).timeout; scene = current_scene
		check(scene != null and not BattleOutcome.decided(scene.play_loop) and not BattlePlayLoop.unit(scene.play_loop,"leonard")["traversal"]["flying"],"real retry restores source traits and a fresh battle")
		routes.back()["restarted"] = true


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(TRAVERSAL_OUT+mode+"-"+label+".png") == OK,"capture "+label)

extends "res://tests/capture_equipment_mobility_review.gd"
## Real equipment, second-action controls, two independent receipts and recovery.
const run_extra_attack_tests = preload("res://tests/run_extra_attack_tests.gd")
const EXTRA_OUT := "res://ignored/extra-action-review/"
var owner := "leonard"
var first_snapshot := {}
var pair_receipts: Array = []
var transition_seen := false
var action_serial := 0


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Extra action review needs a rendered built-in window"); quit(2); return
	root.title = "HSL Extra Action Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(EXTRA_OUT)
	create_timer(450).timeout.connect(func():push_error("EXTRA_ACTION_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["wait_status","equip_restore","move_attack_cast","double_series","growth_kill","support_cure","ai_cast","ai_support","ai_no_mp","ai_silence","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_extra()
		if failures.is_empty(): await play_extra()
		await close_scene()
		FileAccess.open(EXTRA_OUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(EXTRA_OUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":true,"native_execution":false,"real_control_events":true,
		"time_scale":Engine.time_scale,"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"overrides":"Source WRD and default art. Wings227, boots193 and sword12 explicitly in player test inventory; player actually equips through Item. Encounter coordinates/speeds/HP supplied. Owned WIND/HEAL/CURE granted only in named player/AI spell fixtures, source magic eligibility and baseMP enabled for the test player. AI026 wears Wings as fixture, chooses source category and spell use_ratio100. Double-series has durable300 baseHP/1000HP opponent, native counter100 and explicit enemy double_attack trait. Growth/clear targets1HP and player99EXP; source hit compensation1000 avoids random misses without RNG replacement. Defeat player1HP and source attacker power200. Poison/cure starts with explicit three-turn7damage poison. Terminals start after report. No assigned attack/EXP/outcome results or accelerated clock; all post-setup changes use real controls.",
		"routes":routes,"failures":failures},"  "))
	print("EXTRA_ACTION_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_extra() -> void:
	observed = {}; changes = []; cues = []; sound_paths = {}; experience_events = []; receipt = {}; pair_receipts = []; transition_seen = false; action_serial = 0
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene); current_scene = scene
	scene.start_dev_first_control_harness(); scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := BattleFixture.loop()
	var player := BattlePlayLoop.unit(loop,"leonard")
	var enemy := BattlePlayLoop.unit(loop,"enemy021_1")
	var ally := BattlePlayLoop.unit(loop,"enemy023_1")
	player.merge({"coord":Vector2i(8,8),"live_speed":120,"hp":30,"max_hp":30,"inventory":[227,193,12,241,241,246,0,0]},true)
	player["hit_bonus_accum"] = 1000
	enemy.merge({"coord":Vector2i(11,8),"live_speed":90,"hp":500,"max_hp":500,"inventory":[0,0,0,0,0,0,0,0]},true)
	enemy["combat_profile"]["attack_back"] = 0
	ally.merge({"coord":Vector2i(17,19),"live_speed":100,"hp":100,"max_hp":100,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER},true)
	loop["units"] = [player,enemy,ally]; loop["reinforcement_templates"] = []
	owner = "leonard"
	if mode in ["move_attack_cast","growth_kill","support_cure"]:
		player["mp"] = 100; player["max_mp"] = 100
		player["growth_profile"]["source"].merge({"has_magic":true,"magic_point":50},true)
		TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = [run_extra_attack_tests.WIND,run_extra_attack_tests.HEAL,run_extra_attack_tests.CURE]
	if mode in ["wait_status","support_cure"]:
		player["hp"] = 20
		player.merge(BattlePlayLoop.StatusEffectRules.apply(player,"poison",3,7)["changes"],true)
	if mode == "support_cure":
		ally["coord"] = Vector2i(9,8); ally["hp"] = 4
		ally.merge(BattlePlayLoop.StatusEffectRules.apply(ally,"poison",3,7)["changes"],true)
	if mode == "double_series":
		player["growth_profile"]["source"]["hit_point"] += 300
		player["hp"] = 330; player["max_hp"] = 330
		enemy["hp"] = 1000; enemy["max_hp"] = 1000; enemy["combat_profile"]["attack_back"] = 100
		TestSuite.own(loop, "skill_book")["actors"]["021"]["double_attack"] = true
	if mode in ["victory","growth_kill"]:
		player["exp"] = 99; enemy["hp"] = 1
		if mode == "growth_kill":
			var later := enemy.duplicate(true)
			later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"max_hp":500,"live_speed":80},true)
			loop["units"].append(later)
			enemy["inventory"] = [241,0,0,0,0,0,0,0]
	if mode == "defeat":
		player["hp"] = 1
		enemy["combat_profile"].merge({"live_attack_damage":200,"attack_back":100},true)
	if mode in ["victory","escape"]:
		scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
		if mode == "escape":
			player = BattlePlayLoop._unit(loop,"leonard"); BattlePlayLoop._unit(loop,"enemy021_1")["coord"] = Vector2i(17,18)
			landing = loop["escape_zone"][0]
			var found := false
			for y in range(loop["map_size"].y):
				for x in range(loop["map_size"].x):
					var point := Vector2i(x,y)
					if loop["tiles"].get(point,{}).get("blocks_movement",false) or loop["escape_zone"].has(point) or BattlePlayLoop.unit_id_at_coord(loop,point) not in ["","leonard"]: continue
					player["coord"] = point
					var path := BattlePlayLoop.movement_path(loop,"leonard",landing)
					if path.size() >= 2 and path.size() <= 5: found = true; break
				if found: break
			check(found,"source escape destination is reachable during the independent second action")
	if mode.begins_with("ai_"):
		var source := BattleFixture.loop()
		var ai := BattlePlayLoop.unit(source,"enemy026_1")
		ai.merge({"coord":Vector2i(8,8),"live_speed":110,"hp":100,"max_hp":100,"mp":100,"max_mp":100,"inventory":[0,0,0,0,0,0,0,0]},true)
		ai["equipment"].append({"slot":"accessory2","item_code":227})
		player.merge({"coord":Vector2i(12,9),"hp":500,"max_hp":500,"live_speed":70},true)
		ally["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		var initial := BattlePlayLoop.unit(source,"enemy024_1")
		initial.merge({"id":"extra-initial","coord":Vector2i(6,14),"live_speed":130,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_ENEMY},true)
		loop["units"] = [ai,player,ally,initial]
		owner = ai["id"]
		var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]
		profile.merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"lock_target":100},true)
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
		if mode == "ai_no_mp": ai["mp"] = 0
		if mode == "ai_silence": ai.merge(BattlePlayLoop.StatusEffectRules.apply(ai,"no_magic",2)["changes"],true)
		if mode == "ai_support":
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_extra_attack_tests.HEAL]
			TestSuite.own(loop, "skill_book")["skills"][run_extra_attack_tests.HEAL]["fields"]["use_ratio"] = "100"
			profile.merge({"ai_check_hp":100,"ai_help_otherhp":100},true)
			ally["coord"] = Vector2i(12,9); ally["hp"] = 4; ally["max_hp"] = 400; player["coord"] = Vector2i(18,18)
	for actor in loop["units"]:
		actor["grid_coord"] = actor["coord"]; actor["ai_home_coord"] = actor["coord"]
		check(not loop["tiles"].get(actor["coord"],{}).get("blocks_movement",false),"fixture actor starts on the source ground")
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop._return_to_player(loop,"extra-initial" if mode.begins_with("ai_") else "leonard"), "test")
	scene.settlement_controller.checkpoint_path = EXTRA_OUT+mode+".save"
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear(); scene.resume_turn_presentation(); scene.center_camera_on_grid(BattlePlayLoop.unit(loop,owner)["coord"])
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):experience_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(s,_a,_d,c):cues.append(["release",s["attacker_id"],c]))
	view.cutin.impact.connect(func(s,_a,_d,c):cues.append(["impact",s["attacker_id"],c]))
	scene.set_process(true)
	await create_timer(0.35).timeout


func change_item(code: int, slot: String, cancellation: bool = false) -> void:
	await open_equipment_real()
	await click(item_button(code))
	if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	var text := ""
	for label in scene.item_panel.page_root.find_children("*","Label",true,false): text += label.text + "\n"
	if code == 227: check(text.contains("1次 → 2次"),"Wings preview describes a second action separately from additional strikes")
	for child in scene.item_panel.page_root.get_children():
		if child is ScrollContainer:
			for _step in range(12):
				var bar = child.get_v_scroll_bar()
				if bar.value >= bar.max_value - bar.page: break
				await hover(child.get_global_rect().get_center())
				var wheel := InputEventMouseButton.new()
				wheel.position = child.get_global_rect().get_center(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
				root.push_input(wheel,true); wheel = wheel.duplicate(); wheel.pressed = false; root.push_input(wheel,true)
				await process_frame
	await shot("equipment-preview")
	var before: Dictionary = scene.play_loop.duplicate(true)
	if cancellation:
		await click(find_button(scene.item_panel.page_root,"取消"))
		check(scene.play_loop["units"] == before["units"] and scene.play_loop["extra_action"] == before["extra_action"],"cancelling an equipment preview grants no action and loses no inventory")
		await click(item_button(code))
		if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	await click(scene.item_panel.confirm_button); await create_timer(0.3).timeout
	check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(scene.play_loop,"leonard")["equipment"],slot) == code,"real equipment confirmation updates the selected slot")
	check(scene.play_loop["extra_action"] == before["extra_action"] and scene.play_loop["turn_queue"] == before["turn_queue"],"free equipment confirmation neither spends nor replenishes the current action")


func open_equipment_real() -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("EquipCommand"))


func cast_real(id: String, target: String) -> void:
	await click(scene.action_menu.get_node("MagicCommand")); await click(scene.magic_panel.choices[id])
	await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,target)["coord"]))
	receipt = scene.play_loop["last_attack"].duplicate(true)
	check(receipt.get("skill_id") == id,"actual magic selection commits this action's source ability")
	pair_receipts.append(receipt.duplicate(true))


func play_extra() -> void:
	var terminal := mode in ["victory","defeat","escape"]
	if mode.begins_with("ai_"):
		first_snapshot = scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("WaitCommand"))
		await until_control("enemy023_1",false)
		pair_receipts = scene.play_loop["last_ai_actions"].duplicate(true)
		check(pair_receipts.size() == 2 and transition_seen and scene.play_loop["turn_queue"]["index"] == 2,"one Wait produces two visibly separated AI actions then exactly one successor")
		check(pair_receipts.all(func(action):return action["actor_id"] == owner),"the extra AI action belongs to the same original actor")
		if mode == "ai_no_mp" or mode == "ai_silence": check(pair_receipts.all(func(action):return not action.has("skill_id")),"unavailable spells retain the physical fallback on both actions")
		else:
			check(pair_receipts.all(func(action):return action.get("skill_id") == (run_extra_attack_tests.HEAL if mode == "ai_support" else run_extra_attack_tests.WIND)),"AI recomputes the expected owned spell for both actions")
			check(pair_receipts[1].has("sequence") and pair_receipts[0].has("sequence") and pair_receipts[1]["sequence"] == pair_receipts[0]["sequence"] + 1,"two AI casts have two unique receipts")
	else:
		if mode == "double_series": await change_item(12,"weapon")
		await change_item(227,"accessory2",mode == "equip_restore")
		first_snapshot = scene.play_loop.duplicate(true)
		if mode in ["move_attack_cast","double_series","growth_kill"]:
			await move_to(Vector2i(10,8)); await attack_target(); pair_receipts.append(receipt.duplicate(true))
		elif mode == "support_cure": await cast_real(run_extra_attack_tests.HEAL,"enemy023_1")
		else: await click(scene.action_menu.get_node("WaitCommand"))
		await until_control("leonard",false)
		check(transition_seen and scene.play_loop["extra_action"]["pending"] and scene.play_loop["turn_queue"] == first_snapshot["turn_queue"],"first action returns to the same owner and queue after all feedback")
		check(not scene.play_loop["moved_this_action"] and not scene.play_loop["attacked_this_action"],"second-action controls have fresh move and offense budgets")
		if mode in ["wait_status","support_cure"]:
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["hp"] == BattlePlayLoop.unit(first_snapshot,"leonard")["hp"] and BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"] == BattlePlayLoop.unit(first_snapshot,"leonard")["status_counters"],"no hidden poison tick occurs between actions")
		if mode == "equip_restore":
			await open_equipment_real()
			await click(scene.item_panel.equipment_view.slot_controls["accessory2"])
			await click(scene.item_panel.confirm_button); await create_timer(0.3).timeout
			check(not BattlePlayLoop.ExtraActionRules.equipment(BattlePlayLoop.unit(scene.play_loop,"leonard"),scene.play_loop["equipment_items"])["enabled"] and scene.play_loop["extra_action"]["pending"],"actual removal preserves the already-granted second action")
			await save_restore()
			await change_item(227,"accessory2")
		elif mode == "wait_status":
			await click(scene.action_menu.get_node("StatusCommand")); await shot("second-status"); await escape(); await create_timer(0.3).timeout
		elif mode == "growth_kill":
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["level"] == 2 and observed.has("growth"),"first-action kill settles EXP, loot and growth before the second action")
			await save_restore()
		if mode in ["move_attack_cast","growth_kill"]:
			await move_to(Vector2i(10,9)); await cast_real(run_extra_attack_tests.WIND,"enemy021_2" if mode == "growth_kill" else "enemy021_1")
		elif mode == "double_series": await attack_target(); pair_receipts.append(receipt.duplicate(true))
		elif mode == "support_cure": await cast_real(run_extra_attack_tests.CURE,"leonard")
		elif mode in ["victory","defeat"]: await move_to(Vector2i(10,8)); await attack_target(); pair_receipts.append(receipt.duplicate(true))
		elif mode == "escape": await move_to(landing); await click(scene.action_menu.get_node("WaitCommand"))
		else: await click(scene.action_menu.get_node("WaitCommand"))
		await until_control("enemy023_1",terminal)
		check(not scene.play_loop["extra_action"]["pending"],"completed pair or terminal outcome cannot grant a third action")
		if not terminal: check(scene.play_loop["turn_queue"]["index"] == 1,"both actions use one original queue slot")
		if mode == "wait_status": check(BattlePlayLoop.unit(scene.play_loop,"leonard")["hp"] == int(BattlePlayLoop.unit(first_snapshot,"leonard")["hp"]) - 7,"two Waits produce exactly one final poison tick")
		if mode == "support_cure": check(BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"]["poison"] == 0 and BattlePlayLoop.unit(scene.play_loop,"enemy023_1")["status_counters"]["poison"] == 0,"second action cures both friends before final status settlement")
		if mode == "double_series": check(pair_receipts.size() == 2 and pair_receipts.all(func(r):return BattlePlayLoop.CombatSequence.strikes(r).size() >= 3),"two independent actions each retain their complete extra-strike and counter series")
	if terminal: await save_restore()
	var view = scene.get_node("BattlePresentation")
	check(not view.extra_action_cue.label.visible and not scene.ai_playback_active,"final successor/result clears the extra-action cue and AI playback")
	routes.append({"mode":mode,"transition_seen":transition_seen,"extra_action":scene.play_loop["extra_action"],"receipts":pair_receipts,"observed":observed,
		"cues":cues,"experience":experience_events,"owner_after":compact(BattlePlayLoop.unit(scene.play_loop,owner)),"equipment":BattlePlayLoop.unit(scene.play_loop,owner)["equipment"],
		"outcome":scene.play_loop["battle_outcome"],"next_actor":scene.selected_unit_id,"sounds":sound_paths.keys()})
	if terminal:
		reload_current_scene(); await create_timer(0.3).timeout; scene = current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["extra_action"] == BattlePlayLoop.ExtraActionRules.empty() and not BattlePlayLoop.ExtraActionRules.equipment(BattlePlayLoop.unit(scene.play_loop,"leonard"),scene.play_loop["equipment_items"])["enabled"],"real retry clears the previous repeat and restores default equipment")
		routes.back()["restarted"] = true


func until_control(id: String, terminal: bool) -> void:
	for _attempt in range(2200):
		var view = scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position() > 0: sound_paths[sound.stream.resource_path] = true
		if view.extra_action_cue.label.visible and not transition_seen:
			transition_seen = true
			check(not view.cutin.busy() and not view.aftermath.busy() and not scene.has_actor_motion(),"second-action cue follows every prior animation and reward")
			check(not scene.action_menu.visible,"cue has a readable interval before same-owner controls reopen")
			await shot("again")
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"] and not observed.has("impact-"+str(action_serial)):
			observed["impact-"+str(action_serial)] = true
			check(not scene.action_menu.visible,"an action impact never leaks the next controls")
			await shot("impact-"+str(action_serial))
		if view.dialogue_active(): await key(KEY_SPACE)
		if view.aftermath.reward_label.visible and not observed.has(view.aftermath.stage+str(action_serial)):
			observed[view.aftermath.stage+str(action_serial)] = true; await shot(view.aftermath.stage+str(action_serial))
		var loot = scene.settlement_controller.panel
		if loot.visible:
			observed["loot"] = true
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"] = true
			for attribute in ["str","str","dex","mind","con"]: await click(scene.growth_panel.choices[attribute]["plus"])
			await shot("growth")
			await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(scene.play_loop["battle_outcome"] == (BattleOutcome.VICTORY_ENEMIES_CLEARED if mode == "victory" else BattleOutcome.DEFEAT_FALLEN if mode == "defeat" else BattleOutcome.VICTORY_ESCAPE),"pair reaches its intended terminal result")
			await shot("result"); action_serial += 1; return
		if not terminal and scene.selected_unit_id == id and scene.action_menu.visible and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding():
			await shot("ready-"+str(action_serial)); action_serial += 1; return
		await create_timer(0.02).timeout
	check(false,"bounded normal-clock extra-action chain reaches expected controls")


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(EXTRA_OUT+mode+"-"+label+".png") == OK,"capture "+label)


func click(control: Control) -> void:
	if control != null and scene != null and control.get_parent() == scene.action_menu:
		for _attempt in range(30):
			if not scene.action_menu.is_expanding(): break
			observed["waited_menu_expansion"] = true
			await create_timer(0.02).timeout
	await super.click(control)

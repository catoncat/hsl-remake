extends "res://tests/capture_casting_equipment_review.gd"
## Source map/art, actual input, ordinary clock. Only setup authors fixture state.
const POSITION_OUT := "res://ignored/position-equipment-review/"
var frames: Array = []
var position_before := {}
var run_started := 0


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Position review requires a rendered built-in window");quit(2);return
	root.title = "HSL Position and Action Phase Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(POSITION_OUT)
	run_started = Time.get_ticks_msec()
	create_timer(900).timeout.connect(func():check(false,"bounded complete review timed out"))
	var names: Array = ["cancel_equip","remove_restore","double_growth","counter_range","support_cure","no_mp_item","silence_special","detour","ai_stationary","ai_mobile","ai_silence","ai_wait","ai_support","ai_retarget","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_position()
		if failures.is_empty(): await play_position()
		await close_scene()
		write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json")
	print("POSITION_EQUIPMENT_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func write_receipt(filename: String) -> void:
	FileAccess.open(POSITION_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"pid":OS.get_process_id(),"elapsed_seconds":(Time.get_ticks_msec()-run_started)/1000.0,
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"overrides":"Actual source WRD/art/jobs/equipment eligibility. Controlled026 uses harness protagonist ID and manual growth. Selected232/233/236/227/12/145/241 are supplied in the eight-slot fixture; all player changes thereafter use Item controls. Source baseHP+300 and speed+120 keep the named encounter alive and ordered; source MP+100 and supported WIND explicitly granted only to sword growth/detour/silence fixtures. Source water HEAL/CURE granted only to named support fixtures. Positions, current resources, source hit compensation1000, counter100 and enemy double_attack are authored at setup. Growth/clear/retarget first enemy1HP; growth starts99EXP. AI category/use ratios100 and explicit owned rings/wings; ordinary foes no_attack except named counter/defeat. Terminal scenarios run the source turn6 report hook. No replacement RNG, assigned damage/EXP/AI decision, changed map tiles or accelerated clock. F5/F9 use dedicated ignored saves.",
		"routes":routes,"frames":frames,"failures":failures},"  "))


func setup_position() -> void:
	observed={};cues=[];sound_paths={};experience_events=[];pair_receipts=[];resource_beats=[];seen_tail_events={};action_serial=0;transition_seen=false;equipment_previews=[];receipt={}
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene);current_scene=scene
	scene.start_dev_first_control_harness();scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var sword: bool = mode in ["double_growth","counter_range","silence_special","detour","victory","defeat","escape"]
	chosen_role = "001" if sword else "026"
	var loop := run_position_equipment_tests.fixture(chosen_role)
	loop["tiles"] = scene.play_loop["tiles"];loop["map_size"] = scene.play_loop["map_size"]
	var actor := BattlePlayLoop.unit_ref(loop,"leonard")
	var enemy := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	var ally := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	actor["growth_profile"]["source"]["hit_point"] += 300
	actor["growth_profile"]["source"]["speed"] += 120
	if mode in ["double_growth","silence_special","detour"]:
		actor["growth_profile"]["source"].merge({"has_magic":true,"magic_point":100},true)
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["supported_initial_ids"].append(run_position_equipment_tests.WIND)
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"] = actor["max_hp"];actor["mp"] = actor["max_mp"];actor["hit_bonus_accum"] = 1000
	actor["inventory"] = [232,233,236,227,12 if sword else 145,218,241,0]
	enemy["combat_profile"]["attack_back"] = 0
	ally["coord"] = Vector2i(17,19);ally["live_speed"] = 100;ally["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	if mode == "counter_range":
		enemy["coord"] = Vector2i(10,8);enemy["hp"] = 3000;enemy["max_hp"] = 3000
		enemy["no_attack"] = false;enemy["hit_bonus_accum"] = 1000;enemy["combat_profile"]["attack_back"] = 100
		enemy["equipment"] = enemy["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		enemy["equipment"].append({"slot":"accessory1","item_code":233,"name":loop["equipment_items"]["233"]["name"]})
		TestSuite.own(loop, "skill_book")["actors"]["021"]["double_attack"] = true
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	if mode == "double_growth":
		actor["exp"] = 99;enemy["hp"] = 1
		var later := enemy.duplicate(true)
		later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"live_speed":60},true)
		loop["units"].append(later)
	if mode == "support_cure":
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["supported_initial_ids"] = [run_position_equipment_tests.HEAL,run_position_equipment_tests.CURE]
		ally["coord"] = Vector2i(11,8);ally["hp"] = 4;enemy["coord"] = Vector2i(17,18)
		for target in [actor,ally]:target.merge(BattlePlayLoop.StatusEffectRules.apply(target,"poison",3,7)["changes"],true)
	if mode == "no_mp_item": actor["mp"] = 0;actor["hp"] = 10
	if mode == "silence_special":
		actor["stamina"] = 60
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	if mode == "detour": actor["coord"] = Vector2i(7,10);enemy["coord"] = Vector2i(17,18)
	if mode.begins_with("ai_"):
		actor["player_commandable"] = false;actor["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY;actor["growth_profile"]["allocation"] = "fixed_template"
		actor["no_attack"] = mode != "ai_silence";actor["live_speed"] = 160
		actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		actor["equipment"].append({"slot":"accessory1","item_code":227,"name":loop["equipment_items"]["227"]["name"]})
		if mode != "ai_stationary": actor["equipment"].append({"slot":"accessory2","item_code":232,"name":loop["equipment_items"]["232"]["name"]})
		actor["inventory"] = [0,0,0,0,0,0,0,0]
		enemy["coord"] = Vector2i(13,9) # Six cells away on original ground; (14,8) is a source wall.
		var starter := BattlePlayLoop.unit(BattleFixture.loop(),"enemy024_1")
		starter.merge({"id":"resource-initial","coord":Vector2i(6,14),"live_speed":200,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_FRIENDLY},true)
		loop["units"].append(starter)
		TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0},true)
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
		if mode == "ai_wait": actor["mp"] = 0
		if mode == "ai_silence": actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
		if mode == "ai_support":
			ally["coord"] = Vector2i(13,9);ally["hp"] = 1;enemy["coord"] = Vector2i(17,18)
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_position_equipment_tests.HEAL]
			TestSuite.own(loop, "skill_book")["skills"][run_position_equipment_tests.HEAL]["fields"]["use_ratio"] = "100"
			TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_help_otherhp":100,"ai_check_hp":100},true)
		if mode == "ai_retarget":
			enemy["hp"] = 1
			var later := enemy.duplicate(true)
			later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"live_speed":60},true)
			loop["units"].append(later)
			actor["ai_target_id"] = enemy["id"];TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]["ai_lock"] = 100
	if mode in ["victory","defeat","escape"]:
		var view = scene.get_node("BattlePresentation")
		view._shown_story_events.assign(loop["event_log"])
		actor = BattlePlayLoop.unit_ref(loop,"leonard");enemy = BattlePlayLoop.unit_ref(loop,"enemy021_1")
		if mode == "victory": actor["exp"]=99;enemy["hp"]=1
		elif mode == "defeat":
			actor["hp"]=1;enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000
			enemy["combat_profile"].merge({"attack_back":100,"live_attack_damage":1000},true)
			enemy["equipment"] = enemy["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
			enemy["equipment"].append({"slot":"accessory1","item_code":233,"name":loop["equipment_items"]["233"]["name"]})
		else:
			enemy["coord"]=Vector2i(17,18);landing=loop["escape_zone"][0]
			var found := false
			for y in range(loop["map_size"].y):
				for x in range(loop["map_size"].x):
					var at := Vector2i(x,y)
					if loop["tiles"].get(at,{}).get("blocks_movement",false) or loop["escape_zone"].has(at) or BattlePlayLoop.unit_id_at_coord(loop,at) not in ["","leonard"]:continue
					actor["coord"]=at
					var path := BattlePlayLoop.movement_path(loop,"leonard",landing)
					if path.size()>=2 and path.size()<=5:found=true;break
				if found:break
			check(found,"actual source map offers a legal escape approach")
	for unit in loop["units"]:
		unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
		check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false),"authored encounter stands on source walkable terrain: %s %s" % [unit["id"],unit["coord"]])
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"resource-initial" if mode.begins_with("ai_") else "leonard"), "test")
	scene.settlement_controller.checkpoint_path = POSITION_OUT+mode+".save"
	for node in scene.actors_root.get_children():scene.actors_root.remove_child(node);node.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(actor["coord"])
	var view = scene.get_node("BattlePresentation")
	view.turn_end_cue.finish(scene.play_loop)
	view.experience_presented.connect(func(e):experience_events.append(e.duplicate(true)))
	view.cutin.impact.connect(func(s,_a,_d,c):
		cues.append({"sequence":s.get("sequence"),"attacker":s["attacker_id"],"defender":s["defender_id"],"strike":s.get("strike_number",1),"counter":c})
		check(not scene.action_menu.visible and not view.battle_finished,"impact finishes before successor/result controls"))
	position_before = actor.duplicate(true)
	scene.set_process(true);await create_timer(0.35).timeout


func play_position() -> void:
	var terminal: bool = mode in ["victory","defeat","escape"]
	if mode.begins_with("ai_"):
		var before: Dictionary = scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
		pair_receipts = scene.play_loop["last_ai_actions"].duplicate(true)
		check(pair_receipts.size()==2 and pair_receipts.all(func(a):return a["actor_id"]=="leonard"),"one starter wait runs exactly two decisions for the same AI then releases its ally")
		check(observed.has("again") and not scene.play_loop["extra_action"]["pending"],"AI second action is visibly separated and cannot create a third")
		if mode == "ai_stationary":
			check(pair_receipts[0]["kind"]=="move" and not pair_receipts[0].has("skill_id") and pair_receipts[1].get("skill_id")==run_position_equipment_tests.WIND and pair_receipts[1]["path"].is_empty(),"stationary mage prepares position then casts from new second-action origin")
		elif mode == "ai_mobile":check(pair_receipts[0]["kind"]=="move_then_attack" and pair_receipts.all(func(a):return a.get("skill_id")==run_position_equipment_tests.WIND),"source ring permits actual moved casting in each independent action")
		elif mode in ["ai_silence","ai_wait"]:
			check(pair_receipts.all(func(a):return not a.has("skill_id")) and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]==BattlePlayLoop.unit(before,"leonard")["mp"],"permission cannot bypass silence or missing MP")
			if mode=="ai_wait":check(pair_receipts.all(func(a):return a["kind"]=="wait"),"no effective action produces two bounded waits and one final status tail")
		elif mode=="ai_support":check(pair_receipts[0].get("skill_id")==run_position_equipment_tests.HEAL and not pair_receipts[1].has("skill_id"),"second AI decision cannot replay healing after the ally becomes full")
		else:check(pair_receipts[0].get("defender_id")!=pair_receipts[1].get("defender_id") and pair_receipts[0].get("defender_hp_after")==0,"death clears retained target before independent second cast")
	elif mode=="cancel_equip":
		await click(scene.action_menu.get_node("MoveCommand"));await hover(scene.grid_cell_center_to_logical_position(Vector2i(9,8)))
		check(scene.get_node("BattlePresentation").selection_cursor.caption.text.contains("移動後不能施法"),"real movement preview explains the action-phase consequence")
		await shot("movement-warning");await escape();await create_timer(0.3).timeout
		await move_to(Vector2i(9,8))
		var magic_command: Node = scene.action_menu.get_node_or_null("MagicCommand")
		check(magic_command == null or not magic_command.visible,"ordinary mage's moved menu hides magic")
		await save_restore();await escape();await create_timer(1).timeout;await escape();await create_timer(0.3).timeout
		check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]==position_before["coord"] and BattlePlayLoop.command_available(scene.play_loop,"magic"),"actual cancel returns original position and stationary casting")
		await move_to(Vector2i(9,8));await change_item(232,"accessory1",true)
		await cast_real(run_position_equipment_tests.WIND,"enemy021_1");await settle("enemy023_1")
	elif mode=="remove_restore":
		await change_item(236,"accessory1");await change_item(232,"accessory2")
		await move_to(Vector2i(10,8));await change_item(0,"accessory1")
		check(BattlePlayLoop.command_available(scene.play_loop,"magic"),"removing one movement source keeps the other")
		await change_item(0,"accessory2");await save_restore()
		check(not BattlePlayLoop.command_available(scene.play_loop,"magic") and BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]==Vector2i(10,8),"last-source removal preserves location while revoking magic")
		await escape();await create_timer(1).timeout;await escape();await create_timer(0.3).timeout
		await cast_real(run_position_equipment_tests.WIND,"enemy021_1");await settle("enemy023_1")
	elif mode=="double_growth":
		await change_item(12,"weapon");await change_item(236,"accessory1");await change_item(227,"accessory2")
		await move_to(Vector2i(9,8));await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("leonard")
		check(observed.has("growth") and BattlePlayLoop.unit(scene.play_loop,"leonard")["level"]==2 and receipt["planned_strikes"]==2 and receipt["followups"].is_empty(),"first lethal extended strike cancels its followup and completes EXP/growth before next action")
		await save_restore();await move_to(Vector2i(10,9));await cast_real(run_position_equipment_tests.WIND,"enemy021_2");await settle("enemy023_1")
		check(pair_receipts.back()["defender_hp_after"]>0 and pair_receipts.back().has("experience"),"grown second action retains moved magic and nonlethal contribution")
	elif mode=="counter_range":
		await change_item(12,"weapon");await change_item(233,"accessory1")
		await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("enemy023_1")
		check(BattlePlayLoop.CombatSequence.strikes(receipt).size()==4 and BattlePlayLoop.unit(scene.play_loop,"leonard")["hp"]>0 and receipt["defender_hp_after"]>0,"extended main and counter ranges each execute their full living two-strike series")
		check(resource_beats.size()==1 and resource_beats[0]["kind"]=="poison","four impacts do not multiply the final poison tick")
	elif mode=="support_cure":
		await change_item(236,"accessory1");await change_item(227,"accessory2")
		await move_to(Vector2i(10,8));await cast_real(run_position_equipment_tests.HEAL,"enemy023_1");await settle("leonard")
		await save_restore();await move_to(Vector2i(10,9))
		await click(scene.action_menu.get_node("MagicCommand"));await click(scene.magic_panel.choices[run_position_equipment_tests.CURE])
		var center := Vector2i(11,9)
		check(BattlePlayLoop.unit_id_at_coord(scene.play_loop,center)=="","cure uses actual empty ground rather than a fabricated primary")
		await point(scene.grid_cell_center_to_logical_position(center));pair_receipts.append(scene.play_loop["last_attack"].duplicate(true));await settle("enemy023_1")
		check(pair_receipts.back()["cast_center"]==center and pair_receipts.back()["affected_targets"].size()==2 and resource_beats.is_empty(),"moved empty-center cure reaches both allies before final poison settlement")
	elif mode in ["no_mp_item","silence_special"]:
		await change_item(232,"accessory1")
		if mode=="no_mp_item":await change_item(145,"armor")
		await move_to(Vector2i(10,8));await click(scene.action_menu.get_node("MagicCommand"))
		check(scene.magic_panel.choices[run_position_equipment_tests.WIND].disabled,"real menu keeps the resource/status restriction despite movement permission")
		await shot("disabled-magic");await escape();await create_timer(0.3).timeout
		if mode=="no_mp_item":
			await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.3).timeout
			await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(241));await click(scene.item_panel.target_buttons["leonard"])
			await settle("enemy023_1");check(observed.has("item") and not resource_beats.is_empty(),"actual item remains usable after movement, before final blood conversion")
		else:
			await click(scene.action_menu.get_node("SpecialCommand"))
			if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
			await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
			pair_receipts.append(scene.play_loop["last_attack"].duplicate(true));await settle("enemy023_1")
			check(pair_receipts.back().get("skill_id")=="special:magicOTHER:magicCode01","source special remains legal under silence after movement")
	else:
		await change_item(236,"accessory1",true)
		if terminal:
			await change_item(227,"accessory2");await click(scene.action_menu.get_node("WaitCommand"));await settle("leonard");await save_restore()
			await move_to(landing if mode=="escape" else Vector2i(9,8))
			if mode=="escape":await click(scene.action_menu.get_node("WaitCommand"))
			else:await attack_target();pair_receipts.append(receipt.duplicate(true))
			await settle("enemy023_1",true)
		else:
			var found := false
			for cell in BattlePlayLoop.movement_cells(scene.play_loop):
				var path := BattlePlayLoop.movement_path(scene.play_loop,"leonard",cell)
				if path.size()>BattlePlayLoop.TacticalGridRules.manhattan(path[0],cell)+1 and Rect2(24,24,592,414).has_point(scene.grid_cell_center_to_logical_position(cell)):landing=cell;found=true;break
			check(found,"combined movement equipment exposes a real source-map detour")
			await move_to(landing);await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
	await save_restore()
	var final: Dictionary = scene.play_loop.duplicate(true)
	var actor := BattlePlayLoop.unit(final,"leonard")
	routes.append({"mode":mode,"before":compact(position_before),"after":compact(actor),"equipment":actor["equipment"],"position_effects":BattlePlayLoop.PositionCapabilities.effects(actor,final["skill_book"],final["equipment_items"]),"range":BattlePlayLoop.weapon_pattern(final,actor),"receipts":pair_receipts,"beats":resource_beats,"last_action_end":final["last_action_end"],"extra_action":final["extra_action"],"observed":observed,"previews":equipment_previews,"sounds":sound_paths.keys(),"experience":experience_events,"cues":cues,"outcome":final["battle_outcome"]})
	if terminal:
		check(not final["extra_action"]["pending"] and final["action_end_sequence"]==0,"terminal transition freezes the remaining action and unspent resource tail")
		reload_current_scene();await create_timer(0.3).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["extra_action"]==BattlePlayLoop.ExtraActionRules.empty() and BattlePlayLoop.unit(scene.play_loop,"leonard")["move_point"]==5,"real restart restores default actor/gear/action state")
		routes.back()["restarted"]=true


func shot(label: String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var path := mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(POSITION_OUT+path)==OK,"capture "+label)
	if not frames.has(path):frames.append(path)


func check(ok: bool, message: String) -> void:
	if ok:return
	failures.append(mode+": "+message);push_error(mode+": "+message)
	DirAccess.make_dir_recursive_absolute(POSITION_OUT)
	write_receipt("failed.json")
	quit(1)

extends "res://tests/capture_extra_action_review.gd"
## Source art/WRD, real controls and normal clocks; explicit role/resource fixtures.
const run_job_stats_tests = preload("res://tests/run_job_stats_tests.gd")
const run_resource_recovery_tests = preload("res://tests/run_resource_recovery_tests.gd")
const REVIEW_OUT := "res://ignored/role-resources-review/"
var resource_beats: Array = []
var seen_tail_events := {}
var baseline_role := {}
var chosen_role := "001"


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Role/resource review requires the built-in rendered window");quit(2);return
	root.title = "HSL Role and Resource Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(REVIEW_OUT)
	create_timer(600).timeout.connect(func():push_error("ROLE_RESOURCE_REVIEW_TIMEOUT");quit(2))
	var modes: Array = ["mage_growth","heavy_growth","sword_double","poison_recovery","second_remove_restore","support_recovery","detour","ai_half_cast","ai_mp_return","ai_item_restore","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): modes = Array(OS.get_cmdline_user_args())
	for name in modes:
		mode = name
		await setup_role()
		if failures.is_empty(): await play_role()
		await close_scene()
		FileAccess.open(REVIEW_OUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(REVIEW_OUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"overrides":"Source current jobs80/90/94, original mode/caps/WRD/art retained. Controlled mage/heavy use explicit manual allocation and protagonist ID as harness role, not new default party control. Source equipment218/223/224/227, job-valid boots193 or armor138, and sword12 or staff94 are in test inventory, actually equipped through Item. Positions, queue speeds, current HP/MP, enemy durability and source hit compensation1000 supplied. Growth/clear uses target1HP and99EXP; growth retains a second durable target. Double series adds source baseHP300; AI recovery adds source baseMP100 to make next-cycle affordability deterministic with saved recovery stream. AI item starts HP4 and owns241. Support alone explicitly grants source HEAL/CURE. Poison3/7 and silence2 authored where named. AI category probabilities100, waiting foe has no_attack. Terminals begin after scripted report; defeat uses1HP and counter100/attack200. No RNG replacement, assigned damage/EXP/outcome, accelerated clocks or artificial terrain walls.",
		"routes":routes,"failures":failures},"  "))
	print("ROLE_RESOURCE_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_role() -> void:
	observed={};cues=[];sound_paths={};experience_events=[];pair_receipts=[];resource_beats=[];seen_tail_events={};action_serial=0;transition_seen=false
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene);current_scene=scene
	scene.start_dev_first_control_harness();scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	chosen_role = "024" if mode == "heavy_growth" else "001" if mode in ["sword_double","victory","defeat","escape","detour"] else "026"
	var loop := run_job_stats_tests.fixture(chosen_role)
	loop["tiles"]=scene.play_loop["tiles"];loop["map_size"]=scene.play_loop["map_size"]
	var player := BattlePlayLoop.unit_ref(loop,"leonard")
	var enemy := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	var ally := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	player["inventory"]=[218,223,224,138 if chosen_role == "024" else 193,227,12 if chosen_role == "001" else 94,246,241]
	player["hp"]=mini(10,int(player["max_hp"]));player["hit_bonus_accum"]=1000
	enemy["inventory"]=[0,0,0,0,0,0,0,0];enemy["combat_profile"]["attack_back"]=0
	if mode in ["mage_growth","heavy_growth"]:
		player["exp"]=99;enemy["hp"]=1
		var later := enemy.duplicate(true)
		later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"max_hp":500,"live_speed":60},true)
		loop["units"].append(later)
	if mode == "sword_double":
		player["growth_profile"]["source"]["hit_point"]+=300
		player["max_hp"]+=300;player["hp"]=player["max_hp"]-20
		enemy["hp"]=9000;enemy["max_hp"]=9000;enemy["combat_profile"]["attack_back"]=100
	if mode in ["poison_recovery","second_remove_restore"]: player["mp"]=0
	if mode == "poison_recovery":
		player.merge(BattlePlayLoop.StatusEffectRules.apply(player,"poison",3,7)["changes"],true)
		player.merge(BattlePlayLoop.StatusEffectRules.apply(player,"no_magic",2)["changes"],true)
	if mode == "support_recovery":
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["supported_initial_ids"]=[run_extra_attack_tests.HEAL,run_extra_attack_tests.CURE]
		ally["coord"]=Vector2i(11,8);ally["hp"]=4;enemy["coord"]=Vector2i(17,18)
		player.merge(BattlePlayLoop.StatusEffectRules.apply(player,"poison",3,7)["changes"],true)
	if mode == "detour": player["coord"]=Vector2i(7,10);enemy["coord"]=Vector2i(17,18)
	if mode.begins_with("ai_"):
		player["player_commandable"]=false;player["growth_profile"]["allocation"]="fixed_template"
		player["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY
		player["growth_profile"]["source"]["magic_point"]+=100
		player["equipment"]=player["equipment"].filter(func(e):return not str(e["slot"]).begins_with("accessory"))
		for entry in [["accessory1",218],["accessory2",224]]:
			player["equipment"].append({"slot":entry[0],"item_code":entry[1],"name":loop["equipment_items"][str(entry[1])]["name"]})
		player.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(player,loop["equipment_items"]),true)
		player["mp"]=4 if mode=="ai_half_cast" else 0
		player["hp"]=4 if mode=="ai_item_restore" else player["max_hp"]
		player["inventory"]=[241,0,0,0,0,0,0,0] if mode=="ai_item_restore" else [0,0,0,0,0,0,0,0]
		player["live_speed"]=110;player["no_attack"]=mode=="ai_mp_return"
		var starter := BattlePlayLoop.unit(BattleFixture.loop(),"enemy024_1")
		starter.merge({"id":"resource-initial","coord":Vector2i(6,14),"live_speed":130,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_FRIENDLY},true)
		loop["units"].append(starter)
		enemy["no_attack"]=true
		TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":100 if mode=="ai_item_restore" else 0,"ai_check_hp":100,"ai_help_otherhp":0,"ai_help_status":0},true)
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"]="100"
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"]="0"
	if mode in ["victory","defeat","escape"]:
		if mode=="defeat": player["hp"]=1;enemy["combat_profile"].merge({"live_attack_damage":200,"attack_back":100},true)
		else:
			scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
			player=BattlePlayLoop.unit_ref(loop,"leonard");enemy=BattlePlayLoop.unit_ref(loop,"enemy021_1")
			if mode=="victory": player["exp"]=99;enemy["hp"]=1
			else:
				enemy["coord"]=Vector2i(17,18);landing=loop["escape_zone"][0]
				var found:=false
				for y in range(loop["map_size"].y):
					for x in range(loop["map_size"].x):
						var point:=Vector2i(x,y)
						if loop["tiles"].get(point,{}).get("blocks_movement",false) or loop["escape_zone"].has(point) or BattlePlayLoop.unit_id_at_coord(loop,point) not in ["","leonard"]: continue
						player["coord"]=point
						var path:=BattlePlayLoop.movement_path(loop,"leonard",landing)
						if path.size()>=2 and path.size()<=5:found=true;break
					if found:break
				check(found,"actual source map has a finite escape approach")
	for a in loop["units"]:
		a["grid_coord"]=a["coord"];a["ai_home_coord"]=a["coord"]
		check(not loop["tiles"].get(a["coord"],{}).get("blocks_movement",false),"fixture stands on actual source ground")
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"resource-initial" if mode.begins_with("ai_") else "leonard"), "test")
	scene.settlement_controller.checkpoint_path=REVIEW_OUT+mode+".save"
	for a in scene.actors_root.get_children():scene.actors_root.remove_child(a);a.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(player["coord"])
	var view=scene.get_node("BattlePresentation")
	# The opening harness already advanced old actors; align only view cursors.
	view.turn_end_cue.finish(scene.play_loop)
	view.experience_presented.connect(func(g):experience_events.append(g.duplicate(true)))
	view.cutin.impact.connect(func(s,_a,_d,c):cues.append(["impact",s["attacker_id"],c]))
	baseline_role=player.duplicate(true)
	scene.set_process(true);await create_timer(0.35).timeout


func play_role() -> void:
	var terminal:=mode in ["victory","defeat","escape"]
	if mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
		pair_receipts.append(scene.play_loop["last_ai_action"].duplicate(true))
		check(not resource_beats.is_empty(),"AI final action has visible resource restoration")
		if mode=="ai_mp_return":
			check(not pair_receipts[0].has("skill_id"),"first AI action cannot cast with zero MP")
			for _round in range(3):
				await click(scene.action_menu.get_node("WaitCommand"));await settle("resource-initial")
				await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
				var next:Dictionary=scene.play_loop["last_ai_action"]
				pair_receipts.append(next.duplicate(true))
				if next.has("skill_id"):break
			check(pair_receipts.back().has("skill_id"),"subsequent real AI turn uses restored MP for a fresh cast")
		elif mode=="ai_half_cast":check(pair_receipts[0].get("skill_id")==run_extra_attack_tests.WIND,"four MP afforded the actual half-cost source wind cast")
		else:check(pair_receipts[0]["kind"] in ["use_item","move_then_item"] and observed.has("item"),"AI item feedback precedes its resource-tail feedback")
	else:
		await click(scene.action_menu.get_node("StatusCommand"));await shot("initial-stats");await escape()
		if mode=="sword_double":await change_item(12,"weapon")
		if mode=="mage_growth":await change_item(94,"weapon")
		await change_item(223 if mode not in ["second_remove_restore"] else 224,"accessory2",true)
		if mode in ["mage_growth","heavy_growth","sword_double","second_remove_restore","victory","defeat","escape"]:
			await change_item(227,"accessory1")
		elif mode=="poison_recovery":await change_item(224,"accessory1")
		elif mode=="support_recovery":await change_item(218,"accessory1")
		if mode=="heavy_growth":await change_item(138,"armor")
		if mode in ["sword_double","detour"]:await change_item(193,"foot")
		first_snapshot=scene.play_loop.duplicate(true)
		if mode in ["mage_growth","heavy_growth","sword_double"]:
			await move_to(Vector2i(10,8));await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("leonard")
			check(scene.play_loop["action_end_sequence"]==0,"first action cannot run the final recovery tail")
			if mode!="sword_double":check(observed.has("growth") and BattlePlayLoop.unit(scene.play_loop,"leonard")["level"]==2,"source job growth completed before independent second action")
			await save_restore()
			await move_to(Vector2i(11,9) if mode=="sword_double" else Vector2i(10,9))
			if mode=="mage_growth":await cast_real(run_extra_attack_tests.WIND,"enemy021_2")
			else:
				await click(scene.action_menu.get_node("AttackCommand"))
				var target_point:Vector2i=BattlePlayLoop.unit(scene.play_loop,"enemy021_1" if mode=="sword_double" else "enemy021_2")["coord"]
				check(BattlePlayLoop.attack_cells(scene.play_loop).has(target_point),"second action ends at a legal source weapon attack position")
				await point(scene.grid_cell_center_to_logical_position(target_point))
				pair_receipts.append(scene.play_loop["last_attack"].duplicate(true))
		elif mode=="support_recovery":await move_to(Vector2i(10,8));await cast_real(run_extra_attack_tests.HEAL,"enemy023_1")
		elif mode=="detour":
			var found:=false
			for cell in BattlePlayLoop.movement_cells(scene.play_loop):
				var path:=BattlePlayLoop.movement_path(scene.play_loop,"leonard",cell)
				if path.size()>BattlePlayLoop.TacticalGridRules.manhattan(path[0],cell)+1 and Rect2(24,24,592,414).has_point(scene.grid_cell_center_to_logical_position(cell)):
					landing=cell;found=true;break
			check(found,"source obstacles require a real affordable detour")
			if not found:return
			await move_to(landing);await click(scene.action_menu.get_node("WaitCommand"))
		elif mode=="second_remove_restore" or terminal:
			await click(scene.action_menu.get_node("WaitCommand"));await settle("leonard")
			check(resource_beats.is_empty(),"no final recovery occurs between the two actions")
			await save_restore()
			if terminal:
				await move_to(landing if mode=="escape" else Vector2i(10,8))
				if mode=="escape":await click(scene.action_menu.get_node("WaitCommand"))
				else:await attack_target();pair_receipts.append(receipt.duplicate(true))
			else:
				await change_item(218,"accessory2")
				await click(scene.action_menu.get_node("WaitCommand"))
		else:await click(scene.action_menu.get_node("WaitCommand"))
		await settle("enemy023_1",terminal)
		if mode=="second_remove_restore":check(BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]==0 and resource_beats.is_empty(),"removal after restore suppresses final MP gain without a third action")
		elif not terminal:check(not resource_beats.is_empty(),"the completed player action presents its actual source recovery")
		if mode=="poison_recovery":check(resource_beats.map(func(e):return e["kind"])==["poison","auto_hp","auto_mp"],"real frames present poison then HP then MP without early successor controls")
		if mode=="sword_double":check(pair_receipts.size()==2 and pair_receipts.all(func(r):return BattlePlayLoop.CombatSequence.strikes(r).size()==3),"each independent action keeps both source sword strikes and its one counter before final recovery")
	await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	routes.append({"mode":mode,"job":baseline_role["growth_profile"],"before":compact(baseline_role),"after":compact(BattlePlayLoop.unit(final,"leonard")),
		"combat_profile":BattlePlayLoop.unit(final,"leonard")["combat_profile"],"equipment":BattlePlayLoop.unit(final,"leonard")["equipment"],
		"beats":resource_beats,"receipts":pair_receipts,"last_action_end":final["last_action_end"],"extra_action":final["extra_action"],
		"observed":observed,"sounds":sound_paths.keys(),"cues":cues,"experience":experience_events,"outcome":final["battle_outcome"]})
	if terminal:
		check(final["action_end_sequence"]==0 and resource_beats.is_empty(),"victory/defeat/escape freezes unspent final recovery")
		reload_current_scene();await create_timer(0.3).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["action_end_sequence"]==0 and BattlePlayLoop.unit(scene.play_loop,"leonard")["max_hp"]==30,"actual restart restores source protagonist and fresh resource state")
		routes.back()["restarted"]=true


func settle(id: String, terminal: bool = false) -> void:
	for _attempt in range(2400):
		var view=scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream!=null and sound.get_playback_position()>0:sound_paths[sound.stream.resource_path]=true
		if view.item_feedback_busy():observed["item"]=true
		if view.turn_end_cue.showing():
			var event_key:="%s:%s" % [scene.play_loop["action_end_sequence"],view.turn_end_cue.cursor]
			if not seen_tail_events.has(event_key):
				seen_tail_events[event_key]=true
				var event:Dictionary=scene.play_loop["last_action_end"]["events"][view.turn_end_cue.cursor]
				resource_beats.append(event.duplicate(true))
				check(not view.cutin.busy() and not view.aftermath.busy() and not scene.has_actor_motion() and not view.item_feedback_busy() and not scene.action_menu.visible,"resource feedback follows prior action effects and blocks successor controls")
				await shot("tail-"+event_key.replace(":","-"))
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"] and not observed.has("impact"+str(action_serial)):
			observed["impact"+str(action_serial)]=true;await shot("impact-"+str(action_serial))
		if view.extra_action_cue.label.visible:observed["again"]=true
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for attribute in ["str","dex","mind","mind","con"]:await click(scene.growth_panel.choices[attribute]["plus"])
			await shot("growth")
			check(scene.growth_panel.vitals.mp_bar.max_value>0 and scene.growth_panel.vitals.resist_values.size()==5,"the original-layout vitals strip exposes the job-derived MP bar and five resist values")
			await shot("growth-resists");await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(scene.play_loop["battle_outcome"]==(BattleOutcome.VICTORY_ENEMIES_CLEARED if mode=="victory" else BattleOutcome.DEFEAT_FALLEN if mode=="defeat" else BattleOutcome.VICTORY_ESCAPE),"real attack/wait reaches the specified terminal outcome")
			await shot("result");action_serial+=1;return
		if not terminal and scene.selected_unit_id==id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(action_serial));action_serial+=1;return
		await create_timer(0.02).timeout
	check(false,"bounded role/resource route reaches requested control or result")


func shot(label: String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(REVIEW_OUT+mode+"-"+label+".png")==OK,"capture "+label)


func check(ok: bool, message: String) -> void:
	super.check(ok,message)
	if not ok:
		FileAccess.open(REVIEW_OUT+"failed.json",FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"failures":failures,"routes":routes},"  "))
		quit(1)

extends "res://tests/capture_growth_lifecycle_review.gd"
## Real input and real-time render. Public mode never patches its loaded state.
const run_water_strike_tests = preload("res://tests/run_water_strike_tests.gd")
const WATER_OUT := "res://ignored/water-strike-review/"
const WATER_TRIAL := "res://content/battles/water_strike_trial.json"
var water_signals:=[0,0]

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Water review requires rendering");quit(2);return
	root.title="HSL Water Strike Source Range Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80);root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(WATER_OUT);started=Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func():check(false,"bounded water review timeout"))
	var names:Array=["public","mixed","mobile","limited","silence","ai","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_water();await play_water();await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("WATER_STRIKE_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size()," checks=",check_count)
	quit(0 if failures.is_empty() else 1)

func setup_water() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0
	learning_texts=[];ai_receipts=[];recorded_ai={};water_signals=[0,0]
	CampaignProgress.pending={};CampaignProgress.last_entry={};owner_id="tina"
	scene=load("res://game/battle/development/WaterStrikeTrial.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=WATER_OUT+mode+".save"
	check(scene.play_loop["scenario_ok"],"water source-map scene loads")
	if mode!="public":
		scene.set_process(false)
		var loop:=run_water_strike_tests.fixture()
		loop["scenario_id"]="water_strike_trial";loop["scenario_path"]=WATER_TRIAL;loop["scenario_title"]="水剎・十字範圍演練"
		loop["consumables"]=scene.play_loop["consumables"].duplicate(true)
		var actor:=BattlePlayLoop._unit(loop,"tina");var ally:=BattlePlayLoop._unit(loop,"companion")
		actor["hit_bonus_accum"]=1000
		if mode=="mixed":BattlePlayLoop._unit(loop,"enemy021_2")["hp"]=1
		if mode=="limited":actor["mp"]=7
		if mode=="mobile":
			for unit in loop["units"]:unit["coord"]+=Vector2i(3,0)
		if mode=="silence":actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		if mode=="victory":
			for id in ["enemy021_1","enemy021_2"]:BattlePlayLoop._unit(loop,id)["hp"]=1
		if mode=="escape":
			actor["coord"]=Vector2i(13,10);ally["coord"]=Vector2i(13,11)
			BattlePlayLoop._unit(loop,"enemy021_1")["coord"]=Vector2i(16,10);BattlePlayLoop._unit(loop,"enemy021_2")["coord"]=Vector2i(15,9)
		if mode in ["ai","defeat"]:
			var source:=BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json"))
			var boss:Dictionary=BattlePlayLoop.unit(source,"emperor025").duplicate(true)
			boss.merge({"id":"enemy025_1","coord":Vector2i(13,16),"mp":8,"inventory":[0,0,0,0,0,0,0,0],"hit_bonus_accum":1000},true)
			boss["growth_profile"]["source"].merge({"speed":180,"hit_point":500},true)
			boss["equipment"]=boss["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
			boss["equipment"].append({"slot":"accessory2","item_code":227})
			boss.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(boss,loop["equipment_items"]),true);boss["hp"]=boss["max_hp"]
			ally["hp"]=ally["max_hp"]
			loop["units"]=[actor,ally,boss]
			TestSuite.own(loop, "ai_profiles")["actors"]["025"]["profile"].merge({"ai_att_magic":100,"ai_att_special":0,"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_magic_multi_first":1,"find_range":12},true)
			TestSuite.own(loop, "skill_book")["skills"][run_water_strike_tests.WATER]["fields"]["use_ratio"]="100"
			if mode=="defeat":actor["hp"]=1
		for unit in loop["units"]:
			unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
			check(BattlePlayLoop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"])=="","legal original-terrain water setup")
		loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
		loop=BattlePlayLoop._return_to_player(loop,"tina")
		scene.apply_loop(loop, "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(actor["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	var view=scene.get_node("BattlePresentation")
	view.cutin.released.connect(water_release)
	view.cutin.impact.connect(water_impact)
	await settle(owner_id)

func water_release(strike:Dictionary,_actor:Dictionary,_target:Dictionary,_counter:bool) -> void:
	if strike.get("skill_id")!=run_water_strike_tests.WATER:return
	water_signals[0]+=1
	await create_timer(0.35).timeout;await shot("water-rising-"+str(water_signals[0]))

func water_impact(strike:Dictionary,actor:Dictionary,target:Dictionary,counter:bool) -> void:
	impacts.append({"strike":strike.duplicate(true),"attacker":actor["id"],"defender":target["id"],"counter":counter})
	if strike.get("skill_id")!=run_water_strike_tests.WATER:return
	water_signals[1]+=1
	check(not scene.action_menu.visible and not scene.growth_panel.visible,"water impact precedes controls/growth")
	await create_timer(0.25).timeout;await shot("water-impact-"+str(water_signals[1]))
	await create_timer(0.4).timeout;await shot("water-damage-"+str(water_signals[1]))

func cast_water(center:Vector2i) -> void:
	await click(scene.action_menu.get_node("MagicCommand"))
	check(scene.magic_panel.choices.has(run_water_strike_tests.WATER) and not scene.magic_panel.choices[run_water_strike_tests.WATER].disabled,"current owned and affordable water appears in real menu")
	await shot("water-menu");await click(scene.magic_panel.choices[run_water_strike_tests.WATER]);await shot("water-targets")
	var target:String=BattlePlayLoop.magic_target_id_at_coord(scene.play_loop,center)
	check(target!="","empty center has actual source-footprint recipients")
	await point(scene.logical_to_viewport_position(scene.world_to_logical_position(scene.map_config.grid_to_world(center)+Vector2(16,16))))

func play_water() -> void:
	await save_restore()
	if mode=="public":
		check(not LearningRules.owns(BattlePlayLoop.unit(scene.play_loop,"tina"),run_water_strike_tests.WATER),"public starts without an unearned spell")
		await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
		await cast_stat(run_growth_lifecycle_tests.HEAL,"companion");await settle(owner_id)
		check(LearningRules.owns(BattlePlayLoop.unit(scene.play_loop,"tina"),run_water_strike_tests.WATER) and learning_texts.any(func(t):return t.contains("水剎")),"actual public healing earns and displays Water Strike")
		await save_restore()
	if mode in ["limited","silence"]:
		var before:Dictionary=scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("MagicCommand"))
		check(scene.magic_panel.choices[run_water_strike_tests.WATER].disabled,"learned water is visibly disabled by current resources/status")
		await shot("water-unavailable");await escape();await settle(owner_id)
		check(scene.play_loop==before,"cancelled unavailable selection consumes neither MP nor action")
		await use_item_real(244 if mode=="limited" else 247,owner_id);await settle("companion")
		await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
	if mode in ["ai","defeat"]:
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion",mode=="defeat")
		var actions:Array=ai_receipts.filter(func(a):return a.get("actor_id")=="enemy025_1")
		check(actions.any(func(a):return a.get("skill_id")==run_water_strike_tests.WATER),"real source025 AI selects its actual water skill")
		if mode=="ai":
			check(actions.size()==2 and actions[0].get("skill_id")==run_water_strike_tests.WATER and actions[1].get("skill_id")!=run_water_strike_tests.WATER,"AI second independent action redecides after its only eight MP is spent")
	else:
		if mode=="mobile":
			await change_gear(232,"accessory1")
			var actor:=BattlePlayLoop.unit(scene.play_loop,owner_id)
			var candidates:Array=BattlePlayLoop.movement_cells(scene.play_loop).filter(func(c):return c!=actor["coord"] and BattlePlayLoop.SkillTargetRules.cells(c,BattlePlayLoop.skill_fields(scene.play_loop,run_water_strike_tests.WATER),scene.play_loop["skill_target_data"],scene.play_loop["map_size"]).has(run_water_strike_tests.CENTER+Vector2i(3,0)))
			candidates.sort_custom(func(a,b):return a.distance_squared_to(actor["coord"])<b.distance_squared_to(actor["coord"]))
			check(not candidates.is_empty(),"legal water casting position after movement")
			if candidates.is_empty():return
			await move_to(candidates[0])
		var before:Dictionary=scene.play_loop.duplicate(true)
		await cast_water(Vector2i(15,10) if mode=="escape" else run_water_strike_tests.CENTER+Vector2i(3,0) if mode=="mobile" else run_water_strike_tests.CENTER)
		# A cure/MP item used the previous final action. After the next round this
		# cast is action one, so White Wings correctly returns the caster, not ally.
		await settle("" if mode=="victory" else owner_id if mode in ["limited","silence"] else "companion",mode=="victory")
		var receipt:Dictionary=scene.play_loop["last_attack"]
		check(receipt.get("skill_id")==run_water_strike_tests.WATER and receipt["affected_targets"].size()==2,"real empty-center cast settles each of two targets once")
		check(receipt["resource_payment"]["amount"]==8 and BattlePlayLoop.unit(scene.play_loop,"tina")["mp"]==BattlePlayLoop.unit(before,"tina")["mp"]-8,"two water recipients cost exactly eight MP once")
		if mode=="mixed":check(receipt["affected_targets"].any(func(r):return r["defender_hp_after"]==0) and receipt["affected_targets"].any(func(r):return r["defender_hp_after"]>0),"one area spell produces lethal and surviving outcomes")
		if mode=="escape":
			await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
			await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
	check(water_signals==[1,1] and sounds.keys().any(func(p):return p.ends_with("water005.wav")),"one audible source water release and one impact for the whole cast")
	var final:Dictionary=scene.play_loop.duplicate(true)
	await save_restore()
	var row:Dictionary={"mode":mode,"initial_units":initial_state["units"],"final_units":final["units"],"outcome":final["battle_outcome"],"receipts":receipts.duplicate(true),"impacts":impacts.duplicate(true),"ai_actions":ai_receipts.duplicate(true),"learning_texts":learning_texts.duplicate(),"events":events.duplicate(true),"sounds":sounds.keys(),"water_signals":water_signals.duplicate(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		check(final["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"real water lifecycle reaches the requested terminal")
		check(BattlePlayLoop.finish_exhausted_action(final)==final and BattlePlayLoop.step_ai_turn(final)==final,"terminal never replays water or growth")
		reload_current_scene();await create_timer(0.5).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and not LearningRules.owns(BattlePlayLoop.unit(scene.play_loop,"tina"),run_water_strike_tests.WATER),"actual restart returns to unlearned public entry")
		row["restarted"]=true
	routes.append(row)

func shot(label:String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(WATER_OUT+name)==OK,"frame "+label)
	if not frames.has(name):frames.append(name)

func write_receipt(filename:String) -> void:
	FileAccess.open(WATER_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_water_strike_review.v1","native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"setup":"Public is the unchanged authored WaterStrikeTrial. Other routes use declared level/HP/MP/status/equipment/position fixtures and source025 with white wings/8MP and forced strategy-use rate, not a new original loadout. Shared learning is applied before those routes; only public proves actual input acquiring the skill. No post-input model/RNG/effect injection. Original RNG/timing are not claimed.","routes":routes,"frames":frames,"checks":check_count,"failures":failures,"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"units":scene.play_loop["units"],"last_combat":scene.play_loop.get("last_combat",{}),"ai_actions":scene.play_loop.get("last_ai_actions",[])}},"  "))

extends "res://tests/capture_mobile_jobs_review.gd"
## Setup-only authored encounters. Inputs and normal rendering perform every
## cast, allocation, inventory operation, turn, checkpoint and scene transition.
const GrowthCases = preload("res://tests/run_growth_lifecycle_tests.gd")
const Learning = preload("res://game/sim/LearningRules.gd")
const DESTINATION := "res://ignored/growth-lifecycle-review/"
const TRIAL := "res://content/battles/growth_lifecycle_trial.json"
var learning_texts: Array = []
var ai_receipts: Array = []
var recorded_ai := {}
var check_count := 0


func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Growth lifecycle review requires rendering");quit(2);return
	root.title="HSL Growth Lifecycle and Learning Review"
	root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(DESTINATION)
	started=Time.get_ticks_msec()
	create_timer(1800).timeout.connect(func():check(false,"bounded growth lifecycle review timeout"))
	var names:Array=["public","unlock","below","multilevel","special","mobile","limited","paralyzed","permanent","npc","ai_learn","carry","victory","defeat","escape","initial","initial_dev"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name
		await setup_growth()
		await play_growth()
		await close_scene()
		write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("GROWTH_LIFECYCLE_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size()," checks=",check_count)
	quit(0 if failures.is_empty() else 1)


func setup_growth() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0
	learning_texts=[];ai_receipts=[];recorded_ai={}
	Campaign.pending={};Campaign.last_entry={};owner_id="tina"
	scene=load("res://game/battle/development/GrowthLifecycleTrial.tscn").instantiate()
	if mode in ["initial","initial_dev"]:
		scene.scenario_path="res://content/battles/battle_052.json"
		scene.startup_mode="product_opening" if mode=="initial" else "dev_first_control"
		owner_id="leonard"
	root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=DESTINATION+mode+".save"
	check(scene.play_loop["scenario_ok"],"source scene boot: "+str(scene.play_loop.get("scenario_error")))
	if mode not in ["public","initial","initial_dev"]:
		scene.set_process(false)
		var loop:=GrowthCases.fixture(4 if mode=="below" else 5)
		var own:=Loop._unit(loop,"tina");var ally:=Loop._unit(loop,"companion");var foe:=Loop._unit(loop,"enemy021_1")
		loop["scenario_id"]="growth_lifecycle_trial";loop["scenario_path"]=TRIAL;loop["scenario_title"]="成長與學技演練"
		loop["consumables"]=scene.play_loop["consumables"].duplicate(true)
		foe["coord"]=Vector2i(11,16);foe["ai_home_coord"]=foe["coord"]
		if mode=="mobile":foe["coord"]=Vector2i(13,16) # Leave the one source-terrain exit cell free.
		own["hit_bonus_accum"]=1000
		ally.merge(Loop.StatusEffectRules.apply(ally,"poison",3,3)["changes"],true)
		if mode=="limited":own["mp"]=6
		if mode=="multilevel":
			foe["hp"]=1;foe["kill_exp"]=4000
			var other:=foe.duplicate(true);other.merge({"id":"enemy021_2","hp":other["max_hp"],"coord":Vector2i(14,18)},true);other["ai_home_coord"]=other["coord"]
			loop["units"].append(other)
		if mode=="special":
			owner_id="companion"
			# Priest.fixture's companion is source024 (automatic heavy infantry),
			# not a registered player swordsman. Use source001's complete identity.
			ally.clear()
			ally.merge(Loop.unit(BattleFixture.loop(),"leonard").duplicate(true),true)
			ally["id"]="companion"
			ally["equipment"]=ally["equipment"].filter(func(s):return s["slot"]!="accessory2")
			ally["equipment"].append({"slot":"accessory2","item_code":227})
			ally.merge({"level":8,"exp":449,"pending_stat_points":0,"hit_bonus_accum":1000},true)
			ally["combat_profile"].merge({"str":25,"dex":20,"mind":20,"con":24},true)
			ally["growth_profile"]["source"].merge({"speed":500,"hit_point":500},true)
			ally["coord"]=Vector2i(10,16);own["coord"]=Vector2i(10,15)
			ally.merge(Loop.ProgressionRules.refresh_growth_stats(ally,loop["equipment_items"]),true);ally["hp"]=ally["max_hp"]
			ally["status_flags"]=0;ally["status_counters"]={"poison":0,"no_magic":0,"paralysis":0}
			foe["hp"]=1
			var other:=foe.duplicate(true);other.merge({"id":"enemy021_2","hp":other["max_hp"],"coord":Vector2i(14,18)},true);other["ai_home_coord"]=other["coord"]
			loop["units"].append(other)
		if mode=="paralyzed":
			own.merge(Loop.StatusEffectRules.apply(own,"paralysis",2)["changes"],true)
			own["status_counters"]["paralysis"]=1
		if mode=="npc":
			own["exp"]=0;own["hp"]=own["max_hp"]
			foe["no_attack"]=false;foe["exp"]=Loop.ProgressionRules.exp_to_next(foe["level"])-1;foe["hit_bonus_accum"]=1000
			foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":20},true)
			foe.merge(Loop.ProgressionRules.refresh_growth_stats(foe,loop["equipment_items"]),true)
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"]=true;TestSuite.own(loop, "skill_book")["actors"]["021"]["double_attack"]=true
		if mode=="ai_learn":
			own["player_commandable"]=false;own["battle_actor_role"]=Loop.ROLE_FRIENDLY
			ally["growth_profile"]["source"].merge({"hit_point":0,"speed":500},true)
			ally["combat_profile"].merge({"con":1,"dex":1,"str":1,"mind":1},true)
			ally.merge(Loop.ProgressionRules.refresh_growth_stats(ally,loop["equipment_items"]),true);ally["hp"]=1
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]=loop["ai_profiles"]["actors"]["026"].duplicate(true)
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]["missing_required"]=[]
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_help_otherhp":100,"ai_help_status":100,"ai_help_attack":0,"ai_check_dying":0,"ai_check_hp":0,"ai_att_magic":100,"ai_att_special":0,"find_range":12,"ai_fixed":0},true)
			for id in [GrowthCases.HEAL,GrowthCases.CURE]:TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"]="100"
		if mode in ["carry","escape"]:
			own["coord"]=Vector2i(13,10);ally["coord"]=Vector2i(13,11);foe["coord"]=Vector2i(16,12)
		if mode=="victory":foe["hp"]=1
		if mode=="defeat":
			own["hp"]=1;foe["no_attack"]=false;foe["hit_bonus_accum"]=1000
			foe["growth_profile"]["source"].merge({"attack_power":5000,"attack_back":100},true)
			foe.merge(Loop.ProgressionRules.refresh_growth_stats(foe,loop["equipment_items"]),true)
		for actor in loop["units"]:
			actor["grid_coord"]=actor["coord"];actor["ai_home_coord"]=actor["coord"]
			check(Loop.TraversalRules.placement_error(actor,loop["units"],loop["tiles"],loop["map_size"])=="","legal source-map training setup")
		loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
		loop=Loop._return_to_player(loop,"companion" if mode=="ai_learn" else owner_id)
		scene.apply_loop(loop, "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(Loop.unit(loop,owner_id)["coord"])
		scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	scene.get_node("BattlePresentation").cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await settle("companion" if mode in ["ai_learn","paralyzed"] else owner_id)


func settle(id:String,terminal:bool=false) -> void:
	for attempt in range(4500):
		check(scene.play_loop["scenario_ok"],"valid live growth state: "+str(scene.play_loop.get("scenario_error")))
		var view=scene.get_node("BattlePresentation")
		var latest:Dictionary=scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):receipt_sequences[latest["sequence"]]=true;receipts.append(latest.duplicate(true))
		for action in scene.play_loop.get("last_ai_actions",[]):
			# Completed combat receipts remain visible after the queue wraps. Their
			# immutable sequence, not the current turn, identifies one actual action.
			var identity:=str(action.get("actor_id",""))+":"+str(action["sequence"]) if action.has("sequence") else str(scene.play_loop["turn"])+str(action)
			if not recorded_ai.has(identity):recorded_ai[identity]=true;ai_receipts.append(action.duplicate(true))
		for audio in scene.find_children("*","AudioStreamPlayer",true,false):
			if audio.playing and audio.stream!=null and audio.get_playback_position()>0:sounds[audio.stream.resource_path]=true
		if scene.has_actor_motion():observed["movement"]=true
		if view.cutin.busy():
			check(not scene.action_menu.visible and not scene.growth_panel.visible and not view.battle_finished,"attack/cast finishes before allocation and next controls")
			var tag:="clip-"+str(receipts.size())
			if not observed.has(tag):observed[tag]=true;await shot(tag)
		if view.aftermath.reward_label.visible:
			check(not scene.action_menu.visible and not view.battle_finished,"EXP and learned-skill messages precede next action/result")
			var label:String=view.aftermath.reward_label.text
			if label.begins_with("習得") and not learning_texts.has(label):learning_texts.append(label);await shot("learn-"+str(learning_texts.size()))
			if label.contains("EXP") and not observed.has(label):observed[label]=true;await shot("experience-"+str(receipts.size()))
		if view.item_feedback_busy() or view.turn_end_cue.showing():
			check(not scene.action_menu.visible,"item/status resource feedback precedes control")
			var label:="item-"+str(scene.play_loop["item_use_sequence"]) if view.item_feedback_busy() else "tail-"+str(scene.play_loop["action_end_sequence"])
			if not observed.has(label):observed[label]=true;events.append((scene.play_loop["last_item_use"] if view.item_feedback_busy() else scene.play_loop["last_action_end"]).duplicate(true));await shot(label)
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺") and not observed.has("skip"):
			observed["skip"]=true;await shot("paralysis")
		if view.dialogue_active():await key(KEY_SPACE)
		if scene.opening_coordinator!=null and scene.opening_coordinator.active:
			if scene.scene_timeline.current_event().get("kind")=="dialogue_message_id":await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			var panel=scene.growth_panel
			if int(panel.source_unit["pending_stat_points"])>0:
				for i in range(int(panel.source_unit["pending_stat_points"])):
					var stat:String="str" if mode=="special" else ["str","dex","mind","con"][i%4]
					if panel.choices[stat]["plus"].disabled:stat="con"
					await click(panel.choices[stat]["plus"])
				if panel.special_box.visible:
					observed["special_learning"]="\n".join(panel.special_box.get_children().filter(func(c):return c is Label).map(func(c):return c.text))
					await shot("learn-special")
				await shot("allocation");await click(panel.confirm_button)
			else:
				await escape()
		if view.battle_finished:
			check(terminal,"terminal appears only in requested route")
			await shot("result");return
		if not terminal and (id=="" or scene.selected_unit_id==id) and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.growth_panel.visible and not scene.ScriptPresentation.pending(scene):
			await shot("ready-"+str(scene.play_loop["action_end_sequence"]));return
		if attempt==2000:write_receipt("waiting.json")
		await create_timer(0.02).timeout
	check(false,"bounded growth playback did not reach "+id)


func play_growth() -> void:
	if mode in ["public","initial","initial_dev"]:
		check(scene.play_loop.has("initial_roster_growth"),"real scene initializes its complete roster")
		check(Loop.ReinforcementGrowth.state_error(scene.play_loop)=="","real scene creation sequence is valid")
		await status_page(owner_id);await save_restore()
		if mode=="initial_dev":
			var before:Dictionary=scene.play_loop.duplicate(true)
			await click(scene.action_menu.get_node("MoveCommand"))
			check(scene.play_loop["interaction"]=="move_select" and scene.move_overlay_cells.size()>1,"dev initial roster reaches real clickable movement after clearing prefix EXP visuals")
			await shot("move-range");await key(KEY_ESCAPE);await settle(owner_id)
			check(scene.play_loop["global_rng"]==before["global_rng"] and scene.play_loop["units"]==before["units"],"cancel does not rerun initial NPC actions or growth")
		if mode=="public":
			check(Loop.unit(scene.play_loop,"companion")["actor_id"]=="001","published swordsman uses its real player identity")
			await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
			await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
			await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
			var ally:=Loop.unit(scene.play_loop,"companion")
			check(Loop.StatusEffectRules.poisoned(ally) and ally["hp"]<ally["max_hp"],"published scenario provides a real injured poisoned ally without runtime overrides")
			await cast_stat(GrowthCases.HEAL,"companion");await settle(owner_id)
			check(Learning.owns(Loop.unit(scene.play_loop,owner_id),GrowthCases.CURE),"ordinary play earns cure in the public trial")
			await cast_stat(GrowthCases.CURE,"companion");await settle("companion")
			check(not Loop.StatusEffectRules.poisoned(Loop.unit(scene.play_loop,"companion")),"public second action uses the acquired skill")
			await save_restore()
	elif mode=="permanent":
		var before:Dictionary=Loop.unit(scene.play_loop,owner_id)["permanent_gains"].duplicate(true)
		await use_item_real(253,owner_id);await settle(owner_id)
		var gained:Dictionary=Loop.unit(scene.play_loop,owner_id)["permanent_gains"].duplicate(true)
		check(gained!=before and not Loop.unit(scene.play_loop,owner_id)["inventory"].has(253),"actual permanent item commits one owned slot before growth")
		await save_restore()
		await cast_stat(GrowthCases.HEAL,"companion");await settle("companion")
		await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
		check(Learning.owns(Loop.unit(scene.play_loop,owner_id),GrowthCases.CURE),"real subsequent EXP learns cure with permanent gains already present")
		await change_gear(232,"accessory1")
		check(Loop.unit(scene.play_loop,owner_id)["permanent_gains"]==gained,"level, manual allocation and equipment refresh neither lose nor reapply the permanent gain")
		await status_page(owner_id);await save_restore()
	elif mode=="npc":
		var prior:=Loop.unit(scene.play_loop,"enemy021_1").duplicate(true)
		await attack("enemy021_1");await settle(owner_id)
		var after:=Loop.unit(scene.play_loop,"enemy021_1")
		check(int(after["level"])>int(prior["level"]) and after["pending_stat_points"]==0 and after["learned_skills"].is_empty(),"countering NPC automatically assigns stats without learning player abilities")
		check(impacts.size()==4,"two actual attack and counter strikes settle before NPC growth")
		await save_restore()
	elif mode=="ai_learn":
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		var actions:Array=ai_receipts.filter(func(a):return a.get("actor_id")=="tina")
		check(actions.size()==2 and int(actions[0].get("experience",{}).get("level_before",0))==5 and int(actions[0].get("experience",{}).get("level_after",0))>=6 and actions[1].get("skill_id")==GrowthCases.CURE,"registered player AI earns its level on the first action then independently chooses newly acquired allied cure")
		await save_restore()
	elif mode=="defeat":
		await attack("enemy021_1");await settle("",true)
	elif mode in ["multilevel","special"]:
		await attack("enemy021_1");await settle("")
		var actor:=Loop.unit(scene.play_loop,owner_id)
		if mode=="multilevel":
			check(actor["level"]>=8 and Learning.owns(actor,"magic:magicWATER:magicCode01") and Learning.owns(actor,GrowthCases.CURE),"one actual kill crosses several levels and acquires Water Strike and Cure")
			check(Learning.owns(actor,"magic:magicEARTH:magicCode06")== (int(actor["level"])>=9),"Earth Guard is acquired only when the real EXP roll reaches level9")
			check(actor["learned_skills"].size()==(3 if int(actor["level"])>=9 else 2) and not Learning.owns(actor,GrowthCases.HEAL),"initially declared healing is not counted or granted again as a learned ability")
		else:check(Learning.owns(actor,"special:magicAIR:magicCode01") and observed.has("special_learning"),"confirmed base allocation acquires one exact special and shows its availability boundary")
		await save_restore()
	else:
		if mode=="paralyzed":
			check(observed.has("skip") and Loop.unit(scene.play_loop,"tina")["learned_skills"].is_empty(),"paralysis entry does not generate growth or a second action")
			await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
		check(not Learning.owns(Loop.unit(scene.play_loop,"tina"),GrowthCases.CURE),"cure is not already learned before the actual EXP award")
		await cast_stat(GrowthCases.HEAL,"companion");await settle(owner_id)
		var actor:=Loop.unit(scene.play_loop,"tina")
		if mode=="below":
			check(actor["level"]==5 and not Learning.owns(actor,GrowthCases.CURE),"below level6 does not award cure")
			await save_restore()
		elif mode=="victory":
			await attack("enemy021_1");await settle("",true)
		elif mode=="escape":
			await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
		else:
			check(actor["level"]>=6 and Learning.owns(actor,GrowthCases.CURE) and learning_texts.any(func(t):return t.contains("驅毒")),"actual level-up awards and presents cure before second action")
			await save_restore()
			if mode=="mobile":
				await change_gear(232,"accessory1")
				var current:=Loop.unit(scene.play_loop,owner_id)
				var target:=Loop.unit(scene.play_loop,"companion")
				var choices:Array=Loop.movement_cells(scene.play_loop).filter(func(c):return c!=current["coord"] and Loop.SkillTargetRules.cells(c,Loop.skill_fields(scene.play_loop,GrowthCases.CURE),scene.play_loop["skill_target_data"],scene.play_loop["map_size"]).has(target["coord"]))
				choices.sort_custom(func(a,b):return a.distance_squared_to(current["coord"])<b.distance_squared_to(current["coord"]))
				check(not choices.is_empty(),"source terrain offers a reachable learned-cure position")
				if choices.is_empty():return
				await move_to(choices[0])
			if mode=="limited":
				await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[GrowthCases.CURE].disabled,"learned cure remains unavailable at MP0");await shot("no-mp");await escape();await settle(owner_id)
				await use_item_real(244,owner_id);await settle("companion")
			else:
				await cast_stat(GrowthCases.CURE,"companion");await settle("companion")
				check(not Loop.StatusEffectRules.poisoned(Loop.unit(scene.play_loop,"companion")),"second action uses learned cure through the real shared target transaction")
			if mode=="carry":
				await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
				await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
				await carry_growth()
			else:await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	var row:Dictionary={"mode":mode,"initial_units":initial_state["units"],"initial_skills":initial_state["skill_book"],"final_units":final["units"],"outcome":final["battle_outcome"],"global_rng":final["global_rng"],"initial_roster_growth":final.get("initial_roster_growth",{}),"receipts":receipts.duplicate(true),"impacts":impacts.duplicate(true),"events":events.duplicate(true),"ai_actions":ai_receipts.duplicate(true),"learning_texts":learning_texts.duplicate(),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		check(final["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual action reaches its intended terminal")
		check(Loop.step_ai_turn(final)==final and Loop.finish_exhausted_action(final)==final,"terminal cannot award more EXP or learn again")
		await save_restore()
		reload_current_scene();await create_timer(0.5).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and not Learning.owns(Loop.unit(scene.play_loop,"tina"),GrowthCases.CURE),"real restart returns unlearned training entry without residue")
		row["restarted"]=true
	routes.append(row)


func carry_growth() -> void:
	var carry:Dictionary=Campaign.CarryRules.capture(scene.play_loop,Campaign.load_campaign()["carry_policy"])
	check(not carry["units"]["tina"]["learned_skills"].is_empty(),"real configured campaign policy carries learned records")
	var handoff:Dictionary={"schema":Campaign.SCHEMA,"scenario_path":TRIAL,"carry":carry,"from_scenario_id":scene.play_loop["scenario_path"]}
	check(Campaign.save_progress(handoff,DESTINATION+"campaign.json"),"isolated persistent progress save")
	scene.campaign_progress._show_resume_prompt(Campaign.load_progress(DESTINATION+"campaign.json"),"成長演練續戰")
	await shot("campaign-resume");var previous:Node=scene;await click(scene.campaign_progress.resume_button)
	for _i in range(150):
		await process_frame
		if is_instance_valid(current_scene) and current_scene!=previous:scene=current_scene;break
	check(scene!=previous and scene.play_loop["scenario_ok"],"actual resume creates the next playable battle")
	scene.settlement_controller.checkpoint_path=DESTINATION+"carried.save"
	check(Loop.unit(scene.play_loop,"tina")["learned_skills"]==carry["units"]["tina"]["learned_skills"],"new scene preserves exact acquisitions without replay")
	check(not carry.has("initialization_rng") and not carry.has("global_rng"),"the carry holds no global stream: the next NPC roster draws from the process's live stream")
	await settle("");await save_restore()
	observed["campaign_carry"]=scene.play_loop["campaign_carry_receipt"].duplicate(true)
	Campaign.pending={};Campaign.last_entry={}


func shot(label:String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(DESTINATION+name)==OK,"frame "+label)
	if not frames.has(name):frames.append(name)


func check(ok:bool,label:String) -> void:
	check_count+=1
	if ok:return
	failures.append(mode+": "+label);push_error(mode+": "+label);write_receipt("failed.json");quit(1)


func write_receipt(filename:String) -> void:
	FileAccess.open(DESTINATION+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_growth_lifecycle_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"setup":"Public route uses the generated growth trial; initial route uses second-battle product opening. Other encounters set levels/near-threshold EXP, durability/current vitals/poison/paralysis, selected equipment, controlled speeds/AI use rates and double-strike flags before input. No post-input growth/cost/queue/random/state overrides. Native class/skill rules and source artwork execute through the shared production transaction. Unsupported acquired source abilities are explicitly unavailable, not substitutes. RNG remains the saved independent creation stream, not original global RNG equivalence.",
		"routes":routes,"frames":frames,"failures":failures,"checks":check_count,"active":{} if not is_instance_valid(scene) else {"mode":mode,"interaction":scene.play_loop.get("interaction"),"selected":scene.selected_unit_id,"units":scene.play_loop.get("units",[]),"last_combat":scene.play_loop.get("last_combat",{}),"last_ai_actions":scene.play_loop.get("last_ai_actions",[]),"observed":observed}},"  "))

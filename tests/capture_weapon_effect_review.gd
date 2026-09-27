extends "res://tests/capture_large_actor_review.gd"
## Actual controls, unchanged native10%/25% chances and normal presentation clock.
## Probabilistic routes retry real legal turns; no RNG/action-result substitution.
const run_weapon_effect_tests = preload("res://tests/run_weapon_effect_tests.gd")
const WEAPON_OUT := "res://ignored/weapon-effect-review/"
var attempts := 0
var effect_observations: Array = []


func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Weapon review requires a rendered window");quit(2);return
	root.title="HSL Weapon Effects Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(WEAPON_OUT);run_started=Time.get_ticks_msec()
	create_timer(1800).timeout.connect(func():check(false,"bounded weapon review timeout"))
	var modes:Array=["trial","poison_series","cancel_queue","protected_poison","guard_cure","growth_swap","phase_cancel","ai_poison","ai_fallback","ai_silence","ai_wait","ai_cure","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():modes=Array(OS.get_cmdline_user_args())
	for next_mode in modes:
		mode=next_mode;await setup_weapon()
		if failures.is_empty():await play_weapon()
		await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("WEAPON_EFFECT_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_weapon() -> void:
	observed={};cues=[];sound_paths={};experience_events=[];pair_receipts=[];resource_beats=[];seen_tail_events={};body_entries=[];action_serial=0;equipment_previews=[];receipt={};saves_checked=0;attempts=0;effect_observations=[]
	if mode=="trial":
		scene=load("res://game/battle/development/WeaponEffectsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
		chosen_role="001";scene.settlement_controller.checkpoint_path=WEAPON_OUT+"trial.save"
		initial_loop=scene.play_loop.duplicate(true);await create_timer(0.35).timeout;return
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	# Choose the existing development entry before _ready starts any opening
	# choreography; the authored encounter must not race an obsolete opening.
	scene.startup_mode="dev_first_control";root.add_child(scene);current_scene=scene
	scene.set_process(false);await create_timer(0.15).timeout
	var stock:=BattleFixture.loop();var loop:=stock.duplicate(true);loop["reinforcement_templates"]=[]
	chosen_role="001" if mode=="escape" else "039"
	var actor:=BattlePlayLoop.unit(stock,"leonard") if chosen_role=="001" else run_large_actor_tests.source_large()
	actor.merge({"id":"leonard","coord":Vector2i(13,17),"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER},true)
	actor["growth_profile"]["allocation"]="manual";actor["growth_profile"]["source"]["hit_point"]+=5000;actor["growth_profile"]["source"]["speed"]+=180
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"]=actor["max_hp"];actor["hit_bonus_accum"]=1000;actor["inventory"]=[29,35,37,229,227,246,248,0]
	var enemy:=run_large_actor_tests.source_large()
	enemy.merge({"coord":Vector2i(16,17),"no_attack":true,"inventory":[0,0,0,0,0,0,0,0]},true)
	enemy["growth_profile"]["source"]["hit_point"]+=20000;enemy["growth_profile"]["source"]["defense"]+=300
	enemy.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(enemy,loop["equipment_items"]),true)
	enemy["hp"]=enemy["max_hp"];enemy["hit_bonus_accum"]=1000;enemy["live_speed"]=50
	var observer:=BattlePlayLoop.unit(stock,"enemy023_1")
	observer.merge({"id":"observer_end","coord":Vector2i(20,21),"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"live_speed":100},true)
	loop["units"]=[actor,observer,enemy]
	if mode in ["poison_series","cancel_queue"]:
		enemy["no_attack"]=false;enemy["combat_profile"]["attack_back"]=100
		if mode=="poison_series":
			run_weapon_effect_tests.set_gear(enemy,loop["equipment_items"],"weapon",37)
			TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
		else:
			run_weapon_effect_tests.set_gear(enemy,loop["equipment_items"],"accessory1",224)
			run_weapon_effect_tests.set_gear(enemy,loop["equipment_items"],"accessory2",227)
			afflict(enemy,"poison",3,7);afflict(enemy,"no_magic",3)
		enemy["combat_profile"]["attack_back"]=100 # Source refresh above precedes the explicit counter fixture.
	if mode=="protected_poison":
		run_weapon_effect_tests.set_gear(enemy,loop["equipment_items"],"accessory1",229)
		afflict(enemy,"poison",3,7);afflict(enemy,"paralysis",2);afflict(enemy,"no_magic",3)
	if mode=="guard_cure":
		afflict(actor,"poison",3,24);afflict(actor,"no_magic",3)
	if mode=="growth_swap":
		enemy["hp"]=1;actor["exp"]=99
		var later:=enemy.duplicate(true);later.merge({"id":"later039","coord":Vector2i(16,20),"hp":later["max_hp"],"live_speed":40},true)
		loop["units"].append(later);TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
	if mode in ["phase_cancel","ai_silence","ai_wait"]:afflict(actor,"no_magic",3)
	if mode=="phase_cancel":
		run_large_actor_tests.spell_kit(loop);actor=BattlePlayLoop.unit_ref(loop,"leonard")
		actor["mp"]=actor["max_mp"];TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
	if mode in ["ai_poison","ai_fallback","ai_silence","ai_wait"]:
		actor["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY;actor["player_commandable"]=false;actor["growth_profile"]["allocation"]="fixed_template"
		run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"weapon",35)
		run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"accessory2",227)
		TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
		TestSuite.own(loop, "ai_profiles")["actors"]["039"]["profile"].merge({"find_range":80,"ai_att_magic":100,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0},true)
		if mode in ["ai_fallback","ai_silence","ai_wait"]:
			run_large_actor_tests.spell_kit(loop)
			actor=BattlePlayLoop.unit_ref(loop,"leonard");actor["mp"]=8
			TestSuite.own(loop, "skill_book")["actors"]["039"]["supported_initial_ids"]=[run_position_equipment_tests.WIND]
			TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"]="100"
			if mode=="ai_wait":actor["mp"]=0;actor["no_attack"]=true
		var starter:=observer.duplicate(true);starter.merge({"id":"observer","coord":Vector2i(6,18),"live_speed":300},true);loop["units"].append(starter)
	if mode=="ai_cure":
		# The first-battle messenger otherwise removes source026 on round6. This
		# probability arena retains its authored healer; formal departures are intact.
		var healer:=BattlePlayLoop.unit(stock,"enemy026_1")
		healer.merge({"id":"healer","coord":Vector2i(19,17),"battle_actor_role":BattlePlayLoop.ROLE_ENEMY,"player_commandable":false,"no_attack":true,"live_speed":150},true)
		healer["growth_profile"]["source"]["magic_point"]+=100
		healer.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(healer,loop["equipment_items"]),true);healer["mp"]=healer["max_mp"];healer["live_speed"]=150
		TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"]=[run_position_equipment_tests.CURE]
		TestSuite.own(loop, "skill_book")["skills"][run_position_equipment_tests.CURE]["fields"]["use_ratio"]="100"
		TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_help_status":100,"ai_help_otherhp":0,"ai_check_dying":0,"ai_check_hp":0,"ai_att_magic":100},true)
		loop["units"].append(healer)
	if mode in ["victory","defeat","escape"]:
		actor=BattlePlayLoop.unit_ref(loop,"leonard");enemy=BattlePlayLoop.unit_ref(loop,"enemy039_1")
		var view=scene.get_node("BattlePresentation");view._shown_story_events.assign(loop["event_log"])
		if mode=="victory":enemy["hp"]=1
		elif mode=="defeat":
			actor["hp"]=1;enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000
			run_weapon_effect_tests.set_gear(enemy,loop["equipment_items"],"weapon",37)
			enemy["combat_profile"]["attack_back"]=100;enemy["combat_profile"]["live_attack_damage"]=10000
		else:actor["coord"]=Vector2i(13,10);enemy["coord"]=Vector2i(16,20);actor["inventory"]=[144,229,227,0,0,0,0,0]
	for a in loop["units"]:
		a["grid_coord"]=a["coord"];a["ai_home_coord"]=a["coord"]
		check(BattlePlayLoop.TraversalRules.placement_error(a,loop["units"],loop["tiles"],loop["map_size"])=="","source terrain accepts actual footprint: "+a["id"])
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	var first:="observer" if mode in ["ai_poison","ai_fallback","ai_silence","ai_wait"] else "leonard"
	check(BattlePlayLoop.CoreTurnQueue.current(loop["turn_queue"])["id"]==first,"source-derived fixture queue owns first input")
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,first), "test");scene.settlement_controller.checkpoint_path=WEAPON_OUT+mode+".save"
	for node in scene.actors_root.get_children():scene.actors_root.remove_child(node);node.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(BattlePlayLoop.unit(loop,first)["coord"])
	var view=scene.get_node("BattlePresentation");view.turn_end_cue.finish(scene.play_loop)
	view.experience_presented.connect(func(e):experience_events.append(e.duplicate(true)))
	view.cutin.impact.connect(func(s,_a,_d,c):
		cues.append({"attacker":s["attacker_id"],"defender":s["defender_id"],"counter":c,"number":s.get("strike_number"),"weapon_effects":s.get("weapon_effects",{})})
		check(not scene.action_menu.visible and not view.battle_finished,"weapon impact and aftereffect precede controls/result"))
	initial_loop=scene.play_loop.duplicate(true);scene.set_process(true);await create_timer(0.35).timeout


func tail(strike:Dictionary)->Dictionary:
	var followups:Array=strike.get("followups",[])
	return followups.back().get("weapon_effects",{}) if not followups.is_empty() else strike.get("weapon_effects",{})


func ordinary_tail_matches(strike:Dictionary)->bool:
	var followups:Array=strike.get("followups",[])
	var last:Dictionary=followups.back() if not followups.is_empty() else strike
	# Real last-hit misses are a supported result, not a reason to substitute RNG.
	return last.has("weapon_effects")== (int(last.get("experience_basis",{}).get("points",0))>0)


func attack_enemy(id:String="enemy039_1")->void:
	var target:=BattlePlayLoop.unit(scene.play_loop,id)
	var cell:Variant=BattlePlayLoop.Footprint.contact(target,BattlePlayLoop.attack_cells(scene.play_loop))
	check(cell is Vector2i,"current weapon can target a living body edge")
	if cell is Vector2i:await attack_at(cell)


func play_weapon()->void:
	var terminal:bool=mode in ["victory","defeat","escape"]
	await settle("observer" if mode in ["ai_poison","ai_fallback","ai_silence","ai_wait"] else "leonard")
	if mode not in ["trial","ai_poison","ai_fallback","ai_silence","ai_wait","escape"]:
		await change_item(29 if mode=="cancel_queue" else 35,"weapon",mode=="poison_series")
	if mode=="trial":
		await shot("manual-entry");await wait_to("large039_friend")
		await open_equipment_real();await click(item_button(29))
		check(not scene.item_panel.confirm_button.disabled,"published trial permits source039 to select the supplied cancellation weapon")
		await shot("manual-cancel-weapon");await click(scene.item_panel.confirm_button);await settle("large039_friend")
		check(BattlePlayLoop.unit(scene.play_loop,"large039_friend")["weapon_code"]==29,"manual scene commits a real inventory exchange without test-state injection")
	elif mode in ["poison_series","cancel_queue","ai_cure"]:
		if mode=="poison_series":await move_to(Vector2i(13,16))
		var success:=false
		for index in range(48):
			attempts=index+1
			if mode=="ai_cure":check(not BattlePlayLoop.unit(scene.play_loop,"healer").is_empty(),"authored healer remains available before the next probability trial")
			await attack_enemy();await settle("observer_end")
			var effects:=tail(receipt);effect_observations.append(effects.duplicate(true))
			if mode=="poison_series":
				check(not receipt.has("weapon_effects") and receipt["followups"].size()==1,"extra strike cannot independently duplicate effect chance")
				success=effects.get("poison",{}).get("applied",false)
			elif mode=="cancel_queue":success=effects.get("cancel",{}).get("cancelled",false)
			else:
				success=effects.get("poison",{}).get("applied",false)
				if success:
					check(scene.play_loop["last_ai_actions"].any(func(a):return a.get("skill_id")==run_position_equipment_tests.CURE),"AI detects new weapon poison and casts the real ally cure")
					check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(scene.play_loop,"enemy039_1")),"ally support clears newly applied weapon poison before victim's own turn")
			if success:break
			await wait_to("leonard")
		check(success,"native chance produced an observed effect within48 actual legal attacks")
		await save_restore()
		if mode=="cancel_queue":
			var target_before:=BattlePlayLoop.unit(scene.play_loop,"enemy039_1");var old_sequence:int=scene.play_loop["action_end_sequence"]
			check(not receipt["counter"].is_empty(),"cancelled future turn leaves the observed current counter intact")
			await wait_to("leonard")
			check(BattlePlayLoop.unit(scene.play_loop,"enemy039_1")==target_before and scene.play_loop["action_end_sequence"]==old_sequence+1,"cancelled victim has no action, poison/recovery tail or extra-action grant")
			check(scene.play_loop["turn_queue"]["slots"].all(func(s):return s["enabled"]),"next real round rebuild restores future eligibility")
	elif mode=="protected_poison":
		var before:Dictionary=BattlePlayLoop.unit(scene.play_loop,"enemy039_1")["status_counters"].duplicate(true)
		await attack_enemy();await settle("observer_end")
		check(tail(receipt)["poison"]["immune"] and not tail(receipt)["poison"]["applied"] and tail(receipt)["draws"].is_empty(),"real poison weapon respects universal protection before chance draw")
		check(BattlePlayLoop.unit(scene.play_loop,"enemy039_1")["status_counters"]==before,"protective equipment preserves old poison/paralysis/silence")
	elif mode=="guard_cure":
		var before:Dictionary=BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"].duplicate(true)
		await change_item(229,"accessory1")
		check(BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"]==before,"actual equip does not clear existing poison or silence")
		await save_restore();await use_at(246,"leonard");await settle("observer_end")
		check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(scene.play_loop,"leonard")),"antidote removes compatible poison while universal protection remains equipped")
	elif mode=="growth_swap":
		await change_item(227,"accessory2");await attack_enemy();await settle("leonard")
		check(receipt["followups"].is_empty() and observed.has("growth"),"lethal first blow consumes one tail, releases body, completes growth and returns second action")
		await save_restore();await change_item(29,"weapon");await move_to(Vector2i(14,17));await attack_enemy("later039");await settle("observer_end")
		check(tail(receipt).has("cancel") and tail(receipt)["poison"].is_empty(),"second-action weapon swap removes old poison and applies only current cancellation source")
	elif mode=="phase_cancel":
		await change_item(227,"accessory2")
		var before:Dictionary=scene.play_loop.duplicate(true)
		await move_to(Vector2i(13,16))
		await click(scene.action_menu.get_node("AttackCommand"));await escape();await settle("leonard")
		check(scene.play_loop["pending_move"] and scene.play_loop["last_attack"]==before["last_attack"] and scene.play_loop["turn_queue"]==before["turn_queue"],"target cancellation preserves pending movement without weapon effects or lost queue slots")
		await save_restore();await escape();await create_timer(0.4).timeout;await escape();await settle("leonard")
		check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]==BattlePlayLoop.unit(before,"leonard")["coord"] and not scene.play_loop["moved_this_action"],"cancelling the accepted walk restores the entire footprint and action phase")
		await click(scene.action_menu.get_node("MagicCommand"))
		check(scene.magic_panel.choices[run_position_equipment_tests.WIND].disabled,"returning to stationary phase does not clear silence")
		await escape();await settle("leonard")
		check(scene.play_loop["units"]==before["units"] and scene.play_loop["action_end_sequence"]==before["action_end_sequence"],"cancel and reselect neither spend resources nor tick conditions")
		await attack_enemy();await settle("leonard")
		check(scene.play_loop["extra_action"]["pending"],"accepted double strike returns an independent second action")
		var second:Dictionary=scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("AttackCommand"));await escape();await settle("leonard")
		check(scene.play_loop==second,"cancelling second-action selection cannot repeat first-strike effects")
		await save_restore();await change_item(29,"weapon",true)
		await move_to(Vector2i(13,16));await attack_enemy();await settle("observer_end")
		check(ordinary_tail_matches(receipt) and tail(receipt).get("poison",{}).is_empty() and not scene.play_loop["extra_action"]["pending"] and scene.play_loop["action_end_sequence"]==1,"second moved action uses only current weapon, then exactly one final tail")
	elif mode in ["ai_poison","ai_fallback","ai_silence","ai_wait"]:
		var success:=false
		for index in range(32):
			attempts=index+1;await wait_to("observer_end")
			var actions:Array=scene.play_loop["last_ai_actions"].duplicate(true);pair_receipts.append_array(actions)
			check(actions.size()==2,"AI redecides exactly two independent actions")
			if mode=="ai_fallback":
				check(actions[0].get("skill_id")==run_position_equipment_tests.WIND and not actions[1].has("skill_id") and int(BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"])==0,"MP exhaustion chooses a fresh physical action with current poison weapon")
				check(ordinary_tail_matches(actions[1]),"fallback physical series respects the actual final-hit effect gate")
				success=true
			elif mode in ["ai_silence","ai_wait"]:
				check(actions.all(func(a):return not a.has("skill_id")),"silence cannot be bypassed by the newly supported weapon")
				check(int(BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"])==(0 if mode=="ai_wait" else 8),"physical/wait fallback leaves unavailable spell resources unchanged")
				if mode=="ai_wait":check(actions.all(func(a):return a["kind"]=="wait" and tail(a).is_empty()),"no effective action waits without rolling weapon effects")
				else:check(actions.all(ordinary_tail_matches),"silenced AI uses the actual final-hit gate for each independent action")
				check(int(BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"]["no_magic"])==2,"two AI decisions consume only one final status tail")
				success=true
			else:success=actions.any(func(a):return tail(a).get("poison",{}).get("applied",false))
			if success:break
			await wait_to("observer")
		check(success,"AI produced an actual poison effect within bounded normal turns")
	elif mode in ["victory","defeat"]:
		await change_item(227,"accessory2");await attack_enemy();await settle("",true)
	elif mode=="escape":
		await change_item(144,"armor");await change_item(229,"accessory1");await change_item(227,"accessory2")
		await wait_to("leonard");await save_restore();await move_to(scene.play_loop["escape_zone"][0]);await wait_to("",true)
	await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	routes.append({"mode":mode,"attempts":attempts,"initial_units":body_state(initial_loop),"final_units":body_state(final),"initial_queue":initial_loop["turn_queue"],"final_queue":final["turn_queue"],"receipts":pair_receipts,"effect_observations":effect_observations,"impacts":cues,"beats":resource_beats,"observed":observed,"saves_checked":saves_checked,"experience":experience_events,"sounds":sound_paths.keys(),"outcome":final["battle_outcome"],"action_end_sequence":final["action_end_sequence"]})
	if terminal:
		check(BattlePlayLoop.finish_exhausted_action(final)==final and BattlePlayLoop.step_ai_turn(final)==final,"terminal cannot continue queued effects or resource actions")
		reload_current_scene();await create_timer(0.35).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["action_end_sequence"]==0 and scene.play_loop["turn_queue"]["slots"].all(func(s):return s["enabled"]),"actual restart restores default eligibility and removes old weapon effects")
		routes.back()["restarted"]=true


func shot(label:String)->void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+str(attempts)+"-"+label+".png"
	check(root.get_texture().get_image().save_png(WEAPON_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)


func write_receipt(filename:String)->void:
	FileAccess.open(WEAPON_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({
		"schema":"hsl_weapon_effect_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,
		"pid":OS.get_process_id(),"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"time_scale":Engine.time_scale,
		"elapsed_seconds":(Time.get_ticks_msec()-run_started)/1000.0,
		"overrides":"Authored encounters on unchanged051 terrain, source039 job94/3x3 art and source equipment with real inventory changes. Actor/target HP and defense are raised to survive finite probability trials; explicit turn speeds, counter100, accuracy compensation1000, extra-strike capability and supported spell ownership/MP for designated AI branches are setup fixtures. The AI-cure probability arena marks messenger departure as already presented at setup, retaining its authored healer beyond round6; formal departures are unchanged. The trial route loads the published WeaponEffectsTrial scene without overriding its runtime state; its extra HP and supplied inventory are declared in the generated scenario. Cancellation10% and poison25%, duration/intensity RNG, actual action completion and combat outcomes are NOT overridden. Probabilistic routes retry legal real-control rounds until an observed effect or48 attempts; failures are not relabelled success. Source inventory/grants do not change either formal battle. All subsequent moves, strikes, status applications, queue changes, EXP/growth, item/cure, saves and restarts use the actual runtime.",
		"active_debug":debug_state() if not failures.is_empty() else {},
		"routes":routes,"frames":frames,"failures":failures},"  "))


func debug_state()->Dictionary:
	if not is_instance_valid(scene):return {}
	var view=scene.get_node("BattlePresentation")
	return {"mode":mode,"attempts":attempts,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),
		"queue":scene.play_loop.get("turn_queue"),"extra":scene.play_loop.get("extra_action"),"last_ai_action":scene.play_loop.get("last_ai_action"),
		"scenario_error":scene.play_loop.get("scenario_error"),"menu":scene.action_menu.visible,"ai_playback":scene.ai_playback_active,
		"menu_expanding":scene.action_menu.is_expanding(),"menu_processing":scene.action_menu.is_processing(),
		"menu_centers":scene.action_menu.centers,"menu_displayed_centers":scene.action_menu.displayed_centers,
		"scene_processing":scene.is_processing(),"scene_interaction":scene.interaction_state,
		"tree_paused":paused,"campaign_resume":scene.campaign_progress.summary().get("resume_prompt_visible"),
		"cutin":view.cutin.busy(),"combat":view.combat_busy(scene.play_loop),"tail":view.turn_end_cue.busy(scene.play_loop),
		"dialogue":view.dialogue_active(),"units":body_state(scene.play_loop)}


func check(ok:bool,message:String)->void:
	if ok:return
	failures.append(mode+": "+message);push_error(mode+": "+message)
	DirAccess.make_dir_recursive_absolute(WEAPON_OUT);write_receipt("failed.json");quit(1)

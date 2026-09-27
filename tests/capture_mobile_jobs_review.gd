extends "res://tests/capture_tactical_items_review.gd"
## Setup is explicit. Every subsequent move/use/equip/strike/save is real input.
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const MOBILE_OUT := "res://ignored/mobile-jobs-review/"
var owner_id := "thief"
var serial := 0
var carry_expected := {}
var carry_terminal := {}

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Mobile job review requires a rendered window"); quit(2); return
	root.title="HSL Mobile Professions and Mana Strike Review"; root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80); root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(MOBILE_OUT); started=Time.get_ticks_msec()
	create_timer(1800).timeout.connect(func():check(false,"bounded mobile review timeout"))
	var names:Array=["manual","single","double","counter","miss","low_mp","zero_mp","late_kill","growth","wing_growth","wing_move","support","mixed","ai_drain","ai_wing","paralysis","victory","defeat","escape","carry"]
	if not OS.get_cmdline_user_args().is_empty(): names=Array(OS.get_cmdline_user_args())
	CampaignProgress.pending={}; CampaignProgress.last_entry={}
	for name in names:
		mode=name; await setup_mobile(); await play_mobile(); await close_scene(); write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json"); print("MOBILE_JOBS_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func setup_mobile() -> void:
	impacts=[]; events=[]; sounds={}; observed={}; saves=0; receipts=[]; receipt_sequences={}; item_receipts=[]; item_seen={}; serial=0
	CampaignProgress.pending={}; CampaignProgress.last_entry={}
	scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate()
	root.add_child(scene); current_scene=scene; scene.settlement_controller.checkpoint_path=MOBILE_OUT+mode+".save"
	owner_id="wing" if mode in ["manual","wing_growth","wing_move","counter","ai_wing","paralysis"] else "thief"
	if mode!="manual":
		scene.set_process(false)
		var loop:=run_mobile_jobs_tests.fixture("006" if owner_id=="wing" else "004",false,mode in ["counter","defeat"])
		var actor:=BattlePlayLoop._unit(loop,owner_id); var foe:=BattlePlayLoop._unit(loop,"enemy026_1"); var friend:=BattlePlayLoop._unit(loop,"tina")
		actor["equipment"]=actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		if owner_id=="thief": run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"weapon",102)
		actor["inventory"]=[108,227,232,253,244,247,262,0] if owner_id=="thief" else [227,232,253,244,247,262,0,0]
		foe["mp"]=77; friend["coord"]=Vector2i(14,15)
		TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_att_magic":0,"ai_att_special":0,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0},true)
		if mode in ["double","counter","late_kill"]:
			TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["double_attack"]=true
			if mode=="counter":
				TestSuite.own(loop, "skill_book")["actors"]["026"]["double_attack"]=true
				TestSuite.own(loop, "equipment_items")[str(int(foe["weapon_code"]))]["weapon_effect_flags"]=BattlePlayLoop.WeaponEffects.MANA
				foe["growth_profile"]["source"]["attack_power"]=160
				actor["growth_profile"]["source"]["attack_damagex2"]=100
		if mode=="late_kill":
			actor["growth_profile"]["source"]["attack_damagex2"]=1
			actor["combat_profile"]["str"]=1;actor["combat_profile"]["dex"]=1
			# Explicit low-attribute/1% critical setup; native damage and random
			# checks remain live. HP150 spans the observed ordinary two-hit range.
			foe["growth_profile"]["source"]["defense"]=0;foe["combat_profile"]["con"]=1;foe["combat_profile"]["dex"]=1;foe["combat_profile"]["mind"]=1
			foe["equipment"]=foe["equipment"].filter(func(s):return s["slot"]=="weapon")
			foe["hp"]=150
		if mode=="miss":
			actor["hit_bonus_accum"]=0
			foe["growth_profile"]["source"]["avoid_hit_ratio"]=100
		if mode=="low_mp": foe["mp"]=1
		if mode=="zero_mp": foe["mp"]=0
		if mode in ["growth","wing_growth","victory"]: actor["exp"]=99;foe["hp"]=1
		if mode in ["growth","wing_growth","late_kill"]:
			var next_foe:=foe.duplicate(true);next_foe.merge({"id":"enemy026_2","coord":Vector2i(18,18),"hp":next_foe["max_hp"],"mp":0},true)
			loop["units"].append(next_foe)
		if mode in ["wing_move","wing_growth","support"]: actor["mp"]=8;friend["hp"]=12
		if mode=="support": friend["coord"]=Vector2i(15,15);actor["hp"]=100;foe["coord"]=Vector2i(18,16)
		if mode=="mixed":
			for key in ["poison","no_magic"]: actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,key,3,5 if key=="poison" else 0)["changes"],true)
			run_support_magic_tests.buff(loop,owner_id,"defense_up",3,30)
		if mode=="ai_drain":
			foe["mp"]=8;foe["no_attack"]=false
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"]=[run_mobile_jobs_tests.WIND]
			TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]["ai_att_magic"]=100
			TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"]="100"
		if mode=="ai_wing":
			actor["player_commandable"]=false;actor["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY
			run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"accessory2",227)
			actor["mp"]=8;actor["inventory"]=[0,0,0,0,0,0,0,0]
			friend["growth_profile"]["source"]["speed"]=500
			var ai:Dictionary=TestSuite.own(loop, "ai_profiles")["actors"]["006"]
			ai["missing_required"]=[];ai["profile"].merge({"find_type":3,"find_range":12,"ai_call_range":4,"ai_fixed":0,"ai_lock":0,"ai_att_magic":100,"ai_att_special":0,"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0},true)
			TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"]="100"
		if mode=="paralysis":
			run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"accessory2",227)
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true);actor["status_counters"]["paralysis"]=1
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		if mode=="defeat": actor["hp"]=1;foe["growth_profile"]["source"]["attack_power"]=5000
		if mode in ["escape","carry"]: actor["coord"]=Vector2i(13,10);friend["coord"]=Vector2i(13,11);foe["coord"]=Vector2i(16,12)
		for unit in loop["units"]:
			unit.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(unit,loop["equipment_items"]),true)
			unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
			check(BattlePlayLoop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"])=="","legal source-map setup")
		loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
		scene.apply_loop(BattlePlayLoop._return_to_player(loop,"tina" if mode=="ai_wing" else owner_id), "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(actor["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	scene.get_node("BattlePresentation").cutin.impact.connect(observe_hit)
	await create_timer(0.3).timeout

func observe_hit(strike:Dictionary,attacker:Dictionary,defender:Dictionary,counter:bool)->void:
	impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter})
	if strike.has("magic_key"):return
	await process_frame
	var cutin=scene.get_node("BattlePresentation").cutin
	check(cutin.vitals.values["mp"].text=="%d / %d"%[int(strike["defender_after"]["mp"]),int(defender["max_mp"])],"rendered impact shows only this strike's committed MP")
	await shot("impact-%d-%s"%[int(strike.get("strike_number",1)),"counter" if counter else "attack"])

func change_gear(code:int,slot:String)->void:
	var current:=str(scene.selected_unit_id)
	await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout;await click(scene.item_panel.menu.get_node("EquipCommand"))
	if code==0:await click(scene.item_panel.equipment_view.slot_controls[slot])
	else:
		await click(item_button(code))
		if slot.begins_with("accessory"):await click(button_text("飾品 "+slot.right(1)))
	check(not scene.item_panel.confirm_button.disabled,"source profession accepts selected equipment")
	await shot("equipment-"+str(code));await click(scene.item_panel.confirm_button);await settle(current)

func move_to(coord:Vector2i)->void:
	var current:=str(scene.selected_unit_id)
	await click(scene.action_menu.get_node("MoveCommand"));await hover(scene.grid_cell_center_to_logical_position(coord));await shot("move-preview")
	check(BattlePlayLoop.movement_cells(scene.play_loop).has(coord),"shared source path permits destination")
	await point(scene.grid_cell_center_to_logical_position(coord));await settle(current)

func play_mobile()->void:
	await settle("tina" if mode in ["ai_wing","paralysis"] else owner_id)
	if mode=="manual":
		await status_page("wing");check(BattlePlayLoop.magic_options(scene.play_loop,"wing").size()==1,"public006 exposes only its declared Wind")
		var choices:Array=BattlePlayLoop.movement_cells(scene.play_loop).filter(func(c):return c!=BattlePlayLoop.unit(scene.play_loop,"wing")["coord"] and BattlePlayLoop.SkillTargetRules.cells(c,BattlePlayLoop.skill_fields(scene.play_loop,run_mobile_jobs_tests.WIND),scene.play_loop["skill_target_data"],scene.play_loop["map_size"]).has(BattlePlayLoop.unit(scene.play_loop,"enemy026_1")["coord"]))
		choices.sort_custom(func(a,b):return a.distance_squared_to(Vector2i(12,16))<b.distance_squared_to(Vector2i(12,16)))
		check(not choices.is_empty(),"public source flight reaches a legal Wind position")
		await move_to(choices[0]);check(not BattlePlayLoop.command_available(scene.play_loop,"magic"),"flight alone cannot cast after movement")
		await change_gear(232,"accessory1");await cast_stat(run_mobile_jobs_tests.WIND,"enemy026_1");await settle("thief")
		await status_page("thief");await change_gear(108,"weapon")
		check(BattlePlayLoop.unit(scene.play_loop,"thief")["weapon_code"]==108,"public004 actually equipped its source-class weapon")
	elif mode=="paralysis":
		check(observed.has("skip") and not scene.play_loop["extra_action"]["pending"],"paralysis skipped once without a repeat grant")
		await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
		await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[run_mobile_jobs_tests.WIND].disabled,"still-silenced006 keeps its declared spell disabled")
		await shot("silence");await escape();await settle(owner_id)
		await use_item_real(247,owner_id);await settle(owner_id);await cast_stat(run_mobile_jobs_tests.WIND,"enemy026_1");await settle("tina")
	elif mode=="ai_wing":
		await click(scene.action_menu.get_node("WaitCommand"));await settle("tina")
		var actions:Array=scene.play_loop["last_ai_actions"].filter(func(a):return a.get("actor_id")=="wing")
		check(actions.size()==2 and actions[0].get("skill_id")==run_mobile_jobs_tests.WIND and not actions[1].has("skill_id"),"authored006 AI casts owned Wind then independently falls back at MP0")
	else:
		await change_gear(227,"accessory2")
		if owner_id=="thief":await change_gear(108,"weapon")
		if mode in ["growth","wing_growth","mixed","carry"]:
			await use_item_real(253,owner_id);await settle(owner_id);await save_restore()
		if mode in ["single","double","counter","miss","low_mp","zero_mp","late_kill","growth","wing_growth","victory","defeat","ai_drain"]:
			await attack("enemy026_1");await settle("" if mode in ["victory","defeat"] else ("tina" if mode in ["growth","wing_growth"] else owner_id),mode in ["victory","defeat"])
			var attack_receipt:Dictionary=receipts.back()
			if mode=="miss":
				# The original chance has a10% floor. Observe a real miss over bounded
				# normal turns instead of replacing the random stream or hit result.
				for attempt in range(8):
					if not attack_receipt["hit"]:break
					await click(scene.action_menu.get_node("WaitCommand"));await settle("tina")
					await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
					await attack("enemy026_1");await settle(owner_id);attack_receipt=receipts.back()
			var strikes:Array=BattlePlayLoop.CombatSequence.strikes(attack_receipt)
			for strike in strikes:
				if strike.has("weapon_effects") and strike["weapon_effects"].has("mana"):
					var mana:Dictionary=strike["weapon_effects"]["mana"]
					check(int(mana["loss"])==mini(int(mana["before"]),int(strike["native_contribution"])/3),"actual cutin loss equals final capped HP/3")
			if mode=="miss":check(not attack_receipt["hit"] and not attack_receipt.has("weapon_effects"),"miss does not execute a mana tail")
			if mode=="double":check(strikes.size()==2 and not strikes[0].has("weapon_effects") and strikes[1]["weapon_effects"].has("mana"),"two real hits give one tail on the second")
			if mode=="counter":check(strikes.size()==4 and not strikes[2].has("weapon_effects") and int(strikes[3]["weapon_effects"]["mana"]["loss"])>0,"separate two-hit counter uses its own positive last-tail")
			if mode in ["low_mp","zero_mp"]:check(BattlePlayLoop.unit(scene.play_loop,"enemy026_1")["mp"]==0,"actual low/empty target MP clamps at zero")
			if mode=="late_kill":check(strikes.size()==2 and int(strikes[0]["defender_hp_after"])>0 and int(strikes[1]["defender_hp_after"])==0,"second-hit death releases target once")
			if mode in ["growth","wing_growth"]:
				check(observed.has("growth"),"source profession kill reaches actual EXP and allocation")
				await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
				if owner_id=="thief":await change_gear(102,"weapon")
				else:await change_gear(232,"accessory1")
				await status_page(owner_id);await save_restore()
				check(PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,owner_id)),"growth and gear retain acquired source")
				if owner_id=="wing":await move_for_spell("enemy026_2");await cast_stat(run_mobile_jobs_tests.WIND,"enemy026_2");await settle(owner_id)
			elif mode=="ai_drain":
				await click(scene.action_menu.get_node("WaitCommand"));await settle("tina")
				await click(scene.action_menu.get_node("WaitCommand"));await settle(owner_id)
				check(BattlePlayLoop.unit(scene.play_loop,"enemy026_1")["mp"]==0 and scene.play_loop["last_ai_actions"].all(func(a):return not a.has("skill_id")),"drained source026 builds a fresh affordable non-magic action")
			elif mode not in ["victory","defeat"]:
				await save_restore()
				if owner_id=="thief":
					await change_gear(102,"weapon");await click(scene.action_menu.get_node("WaitCommand"));await settle("tina")
		elif mode=="wing_move":
			await move_to(Vector2i(13,16));await escape();await create_timer(0.3).timeout;await escape();await settle(owner_id)
			check(not scene.play_loop["moved_this_action"] and BattlePlayLoop.command_available(scene.play_loop,"magic"),"cancel restores stationary Wind eligibility")
			await change_gear(232,"accessory1");await move_to(Vector2i(13,16));await cast_stat(run_mobile_jobs_tests.WIND,"enemy026_1");await settle(owner_id)
			await save_restore();await change_gear(0,"accessory1");await move_to(Vector2i(14,16))
			check(not BattlePlayLoop.command_available(scene.play_loop,"magic"),"second move immediately respects unequipped permission")
			await use_item_real(244,owner_id);await settle("tina")
		elif mode=="support":
			await move_to(Vector2i(15,16));await use_item_real(262,"tina");await settle(owner_id)
			await use_item_real(253,owner_id);await settle("tina");await cast_heal(owner_id);await settle(owner_id)
			check(impacts.any(func(p):return p["strike"].get("healing",0)>0),"source002 supports new-class ally after moved item use")
		elif mode=="mixed":
			await attack("enemy026_1");await settle("tina")
			check(BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(scene.play_loop,owner_id)) and BattlePlayLoop.StatusEffectRules.magic_blocked(BattlePlayLoop.unit(scene.play_loop,owner_id)),"mana hit preserves independent poison/silence and permanent layer")
		else:
			await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"))
			if mode=="escape":await settle("",true)
			else:await carry_route()
	await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	var row:Dictionary={"mode":mode,"initial_units":initial_state["units"],"initial_book":initial_state["skill_book"],"initial_ai":initial_state["ai_profiles"],"final_units":final["units"],"outcome":final["battle_outcome"],"receipts":receipts.duplicate(true),"items":item_receipts.duplicate(true),"impacts":impacts.duplicate(true),"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode=="carry":row.merge({"carry_expected":carry_expected,"carried_terminal":carry_terminal,"restarted":true})
	if mode in ["victory","defeat","escape"]:
		check(BattlePlayLoop.step_ai_turn(final)==final and BattlePlayLoop.finish_exhausted_action(final)==final,"terminal cannot trigger another MP tail")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and BattlePlayLoop.unit(scene.play_loop,"thief")["weapon_code"]==102 and BattlePlayLoop.unit(scene.play_loop,"wing")["weapon_code"]==43,"real retry returns source templates without weapon residue")
		row["restarted"]=true
	routes.append(row)

func carry_route()->void:
	for _i in range(3000):
		var view=scene.get_node("BattlePresentation")
		if view.dialogue_active():await key(KEY_SPACE)
		if view.battle_finished:break
		await create_timer(0.02).timeout
	check(scene.play_loop["battle_outcome"]==BattleOutcome.VICTORY_ESCAPE,"actual escape ends first profession trial")
	carry_expected=CampaignProgress.CarryRules.capture(scene.play_loop)
	# This public trial is outside the chapter chain. The route supplies only a
	# destination/path and isolated storage; production handoff/carry does the work.
	var handoff:Dictionary={"schema":CampaignProgress.SCHEMA,"scenario_path":run_mobile_jobs_tests.PATH,"carry":carry_expected,"from_scenario_id":scene.play_loop["scenario_path"]}
	check(CampaignProgress.save_progress(handoff,MOBILE_OUT+"campaign.json"),"new professions serialize to isolated campaign file")
	var saved:=CampaignProgress.load_progress(MOBILE_OUT+"campaign.json")
	scene.campaign_progress._show_resume_prompt(saved,"下一場職業演練")
	await shot("campaign-resume");await click(scene.campaign_progress.resume_button)
	var old:Node=scene
	for _i in range(120):
		await process_frame
		if is_instance_valid(current_scene) and current_scene!=old:scene=current_scene;break
	check(scene!=old,"real resume callback creates a new battle")
	scene.settlement_controller.checkpoint_path=MOBILE_OUT+"carried.save"
	check(scene.play_loop["campaign_carry_receipt"]["errors"].is_empty(),"source role carry accepted")
	for id in carry_expected["units"]:
		var actor:=BattlePlayLoop.unit(scene.play_loop,id)
		check(actor["permanent_gains"]==carry_expected["units"][id]["permanent_gains"] and actor["weapon_code"]==carry_expected["units"][id]["weapon_code"],"new source template retains exact equipment/acquired source")
		check(scene.play_loop["item_use_sequence"]==0 and scene.play_loop.get("last_combat",{}).is_empty(),"new battle does not replay item or mana strike")
	await settle("wing");await click(scene.action_menu.get_node("WaitCommand"));await settle("thief");await status_page("thief");await save_restore()
	var carried_thief:=BattlePlayLoop.unit(scene.play_loop,"thief").duplicate(true)
	await run_carried_terminal()
	reload_current_scene()
	await create_timer(0.5).timeout;scene=current_scene
	scene.settlement_controller.checkpoint_path=MOBILE_OUT+"carried-retry.save"
	check(BattlePlayLoop.unit(scene.play_loop,"thief")["permanent_gains"]==carried_thief["permanent_gains"] and BattlePlayLoop.unit(scene.play_loop,"thief")["weapon_code"]==108,"actual next-battle retry retains incoming acquisitions and mana equipment once")
	await settle("wing")
	CampaignProgress.pending={};CampaignProgress.last_entry={}

func run_carried_terminal()->void:
	for step in range(12000):
		var view=scene.get_node("BattlePresentation")
		check(scene.play_loop["scenario_ok"],"carried default actors remain valid")
		if view.battle_finished:
			# Waiting still permits source counterattacks. The natural endpoint can
			# therefore be victory or defeat; this route checks a real ended battle
			# and preservation of its entry state on retry, not a prescribed winner.
			check(scene.play_loop["battle_outcome"] in [BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ENEMIES_CLEARED],"carried public party reaches a real combat endpoint")
			carry_terminal={"outcome":scene.play_loop["battle_outcome"],"units":scene.play_loop["units"].duplicate(true),"last_combat":scene.play_loop.get("last_combat",{}).duplicate(true)}
			await shot("carried-terminal");return
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var key:String=["str","dex","mind","con"][i%4]
				if not scene.growth_panel.choices[key]["plus"].disabled:await click(scene.growth_panel.choices[key]["plus"])
			await click(scene.growth_panel.confirm_button)
		if scene.action_menu.visible and not scene.action_menu.is_expanding() and not view.combat_busy(scene.play_loop) and not scene.ai_playback_active:
			await click(scene.action_menu.get_node("WaitCommand"))
		await create_timer(0.02).timeout
	check(false,"bounded carried default battle did not reach an outcome")

func move_for_spell(target_id:String)->void:
	var actor:=BattlePlayLoop.unit(scene.play_loop,str(scene.selected_unit_id))
	var target:=BattlePlayLoop.unit(scene.play_loop,target_id)
	var choices:Array=BattlePlayLoop.movement_cells(scene.play_loop).filter(func(c):return c!=actor["coord"] and BattlePlayLoop.SkillTargetRules.cells(c,BattlePlayLoop.skill_fields(scene.play_loop,run_mobile_jobs_tests.WIND),scene.play_loop["skill_target_data"],scene.play_loop["map_size"]).has(target["coord"]))
	choices.sort_custom(func(a,b):return a.distance_squared_to(actor["coord"])<b.distance_squared_to(actor["coord"]))
	check(not choices.is_empty(),"actual movement envelope contains a source spell position")
	await move_to(choices[0])

func shot(label:String)->void:
	if is_instance_valid(scene):
		var item:Dictionary=scene.play_loop.get("last_item_use",{})
		if not item.is_empty() and not item_seen.has(item["sequence"]):item_seen[item["sequence"]]=true;item_receipts.append(item.duplicate(true))
	await process_frame;RenderingServer.force_draw(false);serial+=1
	var name:="%s-%03d-%s.png"%[mode,serial,label]
	check(root.get_texture().get_image().save_png(MOBILE_OUT+name)==OK,"capture "+label);frames.append(name)

func write_receipt(filename:String)->void:
	FileAccess.open(MOBILE_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_mobile_jobs_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"screen":root.current_screen,"window_size":root.size,"time_scale":Engine.time_scale,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"routes":routes,"frames":frames,"failures":failures,
		"setup":"Manual uses the published trial. Other setups use original051 terrain,004/006/002/026 source roles, declared durability/speed/accuracy/counter/double flags, optional starting states and finite inventories.006 AI has an explicitly authored strategy because its source does not declare one. Counter mana bit is a capability fixture, not a legal enemy026 weapon grant. No RNG/result/turn is replaced after setup. Carry uses the real resume UI into a new public trial with isolated campaign storage, not a reconstructed chapter encounter.","active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"units":scene.play_loop["units"],"error":scene.play_loop.get("scenario_error"),"last_combat":scene.play_loop.get("last_combat",{}),"last_ai_actions":scene.play_loop.get("last_ai_actions",[])}},"  "))

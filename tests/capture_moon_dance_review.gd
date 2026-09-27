extends "res://tests/capture_priest_review.gd"
## Normal-clock input routes. All authored state changes stop at setup_moon.
const MoonCases = preload("res://tests/run_moon_dance_tests.gd")
const MoonRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const LargeCases = preload("res://tests/run_large_actor_tests.gd")
const MOON_OUT := "res://ignored/moon-dance-review/"
var receipts: Array = []
var receipt_sequences := {}


func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Moon review needs a rendered built-in window");quit(2);return
	root.title="HSL Moon Dance Playable Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(MOON_OUT);started=Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func():check(false,"bounded Moon input route timeout"))
	var names:Array=["manual","multi_kill","misses","phase_extra","ordinary_then_moon","aid_after_moon","large_target","ai_multi","ai_empty","ai_paralysis","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_moon();await play_moon()
		await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json");print("MOON_DANCE_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	call_deferred("quit",0 if failures.is_empty() else 1)


func setup_moon() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={}
	scene=load("res://game/battle/development/MoonDanceTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=MOON_OUT+mode+".save"
	if mode!="manual":
		scene.set_process(false)
		var loop:=MoonCases.fixture()
		# Keep the real original051 ground/art, not the flat headless fixture.
		loop["tiles"]=scene.play_loop["tiles"];loop["map_size"]=scene.play_loop["map_size"]
		var actor:=Loop._unit(loop,"tina");var ally:=Loop._unit(loop,"companion");var enemy:=Loop._unit(loop,"enemy021_1")
		actor["growth_profile"]["source"]["hit_point"]+=300
		actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true);actor["hp"]=actor["max_hp"]
		actor["inventory"]=[227,228,232,233,244,241,248,0]
		enemy["growth_profile"]["source"]["hit_point"]+=600
		enemy.merge(Loop.ProgressionRules.refresh_growth_stats(enemy,loop["equipment_items"]),true);enemy["hp"]=enemy["max_hp"];enemy["no_attack"]=true
		if mode in ["multi_kill","victory"]:
			actor["exp"]=99;enemy["hp"]=1
			for index in range(2):
				var foe:=enemy.duplicate(true)
				foe["id"]="moon_foe_"+str(index);foe["coord"]=Vector2i(9,15+index*2)
				foe["hp"]=1 if mode=="victory" or index==0 else foe["max_hp"]
				loop["units"].append(foe)
		if mode=="misses":
			enemy["no_attack"]=false
			TestSuite.own(loop, "skill_book")["skills"][MoonRules.ID]["fields"]["hit_ratio"]="0"
		if mode=="phase_extra":
			actor["stamina"]=40;actor["mp"]=0
			actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
			actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,1)["changes"],true)
		if mode=="aid_after_moon":ally["hp"]=1
		if mode=="ordinary_then_moon":
			actor["hit_bonus_accum"]=1000
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"]=true
			TestSuite.own(loop, "skill_book")["actors"]["021"]["double_attack"]=true
			enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100
		if mode=="large_target":
			var giant:=LargeCases.source_large()
			giant["id"]="enemy021_1";giant["coord"]=Vector2i(12,16);giant["hp"]=giant["max_hp"];giant["no_attack"]=true
			loop["units"][loop["units"].find(enemy)]=giant;enemy=giant
		if mode.begins_with("ai_"):
			actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
			actor["equipment"].append({"slot":"accessory2","item_code":227});actor["stamina"]=40
			actor["inventory"]=[0,0,0,0,0,0,0,0];ally["hp"]=ally["max_hp"]
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_special":100},true)
			TestSuite.own(loop, "skill_book")["skills"][MoonRules.ID]["fields"]["use_ratio"]="100" # Declared route probability override; numeric RNG remains original.
			enemy["coord"]=Vector2i(14,16)
			if mode=="ai_multi":
				var foe:=enemy.duplicate(true);foe["id"]="moon_ai_foe";foe["coord"]=Vector2i(14,17);foe["hp"]=1
				loop["units"].append(foe)
			elif mode=="ai_empty":
				actor["no_attack"]=true;actor["mp"]=0;actor["stamina"]=19
				actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
			else:actor.merge(Loop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true)
		if mode=="defeat":
			actor["hp"]=1;enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000
			enemy["combat_profile"].merge({"attack_back":100,"live_attack_damage":1000},true)
		if mode=="escape":actor["coord"]=Vector2i(13,10);enemy["coord"]=Vector2i(12,10)
		for unit in loop["units"]:
			if mode!="escape":unit["coord"]+=Vector2i(4,0)
			unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
			unit["live_speed"]=200 if unit["id"]=="tina" else (300 if mode.begins_with("ai_") else 100) if unit["id"]=="companion" else 50
			check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false),"authored fixture remains on original ground")
		loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
		scene.apply_loop(Loop._return_to_player(loop,"companion" if mode.begins_with("ai_") else "tina"), "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(actor["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	var view=scene.get_node("BattlePresentation")
	view.cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await create_timer(0.25).timeout


func settle(id:String,terminal:bool=false) -> void:
	for attempt in range(3000):
		var view=scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream!=null and sound.get_playback_position()>0:sounds[sound.stream.resource_path]=true
		var latest:Dictionary=scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):
			receipt_sequences[latest["sequence"]]=true;receipts.append(latest.duplicate(true))
		if scene.has_actor_motion():observed["movement"]=true
		if view.cutin.busy():
			check(not scene.action_menu.visible and not scene.growth_panel.visible and not view.battle_finished,"all receiver callbacks finish before menus, growth or result")
			var clip:Dictionary=view.cutin.clips[0]
			if clip["strike"].has("special_segments"):
				var count:=int(clip.get("moon_emitted",0));var token:="moon-"+str(receipts.size())+"-"+str(count)
				if not observed.has(token):
					observed[token]=true
					if count==0 or count==1 or count==5 or count==10 or count==15:await shot(token)
		if view.item_feedback_busy() or view.turn_end_cue.showing():
			check(not scene.action_menu.visible,"item/status tail completes before successor controls")
			var effect:Dictionary=scene.play_loop["last_item_use"] if view.item_feedback_busy() else scene.play_loop["last_action_end"]
			if events.is_empty() or events.back()!=effect:events.append(effect.duplicate(true));await shot("tail-"+str(events.size()))
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺") and not observed.has("skip"):
			observed["skip"]=true;await shot("skip")
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty():
				if loot.first_empty_slot() < 0:
					observed["deferred_full_bag"]=true;await shot("full-bag");await click(loot.finish_button)
				else:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var name:String=["str","dex","mind","con"][i%4]
				if not scene.growth_panel.choices[name]["plus"].disabled:await click(scene.growth_panel.choices[name]["plus"])
			await shot("growth");await click(scene.growth_panel.confirm_button)
		if view.battle_finished and (terminal or mode=="manual"):
			if terminal:check(scene.play_loop["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual action reaches the specified terminal")
			elif impacts.is_empty():check(false,"published Moon training must reach its first playable action")
			await shot("result");return
		if not terminal and scene.selected_unit_id==id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(scene.play_loop["action_end_sequence"]));return
		if attempt==1000:
			observed["wait_diagnostic"]={"interaction":scene.interaction_state,"ai":scene.ai_playback_active,"motion":scene.has_actor_motion(),
				"pending_combat":view.has_pending_combat(scene.play_loop),"cutin":view.cutin.clips.size(),"magic_impact":view.magic_impact.busy(),
				"aftermath":[view.aftermath.stage,view.aftermath.cursor,view.aftermath.jobs.size()],"navigation":view.navigation_cue.busy(),
				"item":view.item_feedback_busy(),"extra":view.extra_action_cue.busy(scene.play_loop),"tail":view.turn_end_cue.busy(scene.play_loop),
				"dialogue":view.dialogue_active(),"panels":[scene.status_panel.visible,scene.item_panel.visible,scene.magic_panel.visible,scene.growth_panel.visible],
				"loot":Loop.loot_waiting(scene.play_loop),"settlement":scene.settlement_controller.panel.visible,"story":false}
			await shot("waiting");write_receipt("waiting.json")
		check(scene.play_loop["scenario_ok"],"live Moon scenario remains valid: "+str(scene.play_loop.get("scenario_error","")))
		await create_timer(0.02).timeout
	check(false,"bounded Moon playback did not reach "+id)


func cast_moon() -> void:
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"]=="special_select":await click(scene.magic_panel.choices[MoonRules.ID])
	var center:Vector2i=Loop.unit(scene.play_loop,"tina")["coord"]
	await hover(scene.grid_cell_center_to_logical_position(center));await shot("self-center")
	await point(scene.grid_cell_center_to_logical_position(center))
	check(scene.play_loop["last_attack"].get("skill_id")==MoonRules.ID,"actual self-center click commits source Moon Dance")


func move_to(coord:Vector2i) -> void:
	await super.move_to(coord if mode=="escape" else coord+Vector2i(4,0))


func play_moon() -> void:
	await settle("companion" if mode.begins_with("ai_") else "tina")
	if mode=="manual":
		await cast_moon();await settle("tina")
		check(impacts.any(func(e):return e["strike"].get("skill_id")==MoonRules.ID),"published training scene performs its actual source special")
	elif mode=="multi_kill":
		await change_gear(228,"accessory1");await cast_moon();await settle("companion")
		check(impacts.size()==15 and scene.play_loop["rewarded_unit_ids"].size()==2,"three unique targets receive five callbacks, two deaths reward once")
		check(receipts[0]["experience_settlement"]["multiplier"]==2 and observed.has("growth"),"source EXP equipment and final priest growth follow all targets")
	elif mode=="misses":
		await cast_moon();await settle("companion")
		check(impacts.size()==5 and impacts.any(func(e):return not e["strike"]["hit"]),"source miss callback and following attempts all finish")
	elif mode in ["phase_extra","ordinary_then_moon","aid_after_moon"]:
		await change_gear(227,"accessory2")
		if mode=="phase_extra":
			var before:Dictionary=scene.play_loop.duplicate(true)
			await move_to(Vector2i(11,17));await click(scene.action_menu.get_node("SpecialCommand"));await escape();await settle("tina")
			await escape();await create_timer(0.3).timeout;await escape();await settle("tina")
			check(scene.play_loop["units"]==before["units"] and not scene.play_loop["moved_this_action"],"special cancellation restores phase without refunding another action")
			await move_to(Vector2i(11,17));await cast_moon();await settle("tina");await save_restore()
			await change_gear(0,"accessory2");await cast_moon();await settle("companion")
			check(Loop.unit(scene.play_loop,"tina")["stamina"]==0 and scene.play_loop["action_end_sequence"]==1,"two independent payments and one poison/status tail after second-action removal")
		elif mode=="ordinary_then_moon":
			await attack("enemy021_1");await settle("tina");await save_restore();await cast_moon();await settle("companion")
			check(impacts.size()==9 and impacts.filter(func(e):return e["counter"]).size()==2,"ordinary/counter double series precede five special pulses without multiplying them")
		else:
			await change_gear(232,"accessory1");await cast_moon();await settle("tina");await save_restore()
			await move_to(Vector2i(9,16));await cast_heal("companion");await settle("companion")
			check(impacts.any(func(e):return e["strike"].get("healing",0)>0),"second action uses current moved-cast permission and actual support ability")
	elif mode=="large_target":
		await cast_moon();await settle("companion")
		check(impacts.size()==5 and receipts[0]["affected_targets"].size()==1,"a large body's three covered cells remain one five-stage target")
	elif mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		var actions:Array=scene.play_loop["last_ai_actions"].filter(func(a):return a.get("actor_id")=="tina")
		if mode=="ai_multi":
			check(actions.size()==2 and actions[0].get("skill_id")==MoonRules.ID and actions[1].get("skill_id")==MoonRules.ID,"AI freshly selects and pays both independent area actions")
			check(impacts.filter(func(e):return e["strike"].get("skill_id")==MoonRules.ID).size()==15,"AI second action removes the first cast's dead target from coverage")
		elif mode=="ai_empty":check(actions.size()==2 and actions.all(func(a):return not a.has("skill_id")) and impacts.is_empty(),"no attack, no MP, low stamina and silence yield legal waits")
		else:check(actions.size()==1 and actions[0]["kind"]=="paralysis_skip" and observed.has("skip"),"paralysis blocks the special and skips only one turn")
	elif mode=="victory":await cast_moon();await settle("",true)
	elif mode=="defeat":await attack("enemy021_1");await settle("",true)
	else:
		await change_gear(227,"accessory2");await cast_moon();await settle("tina");await save_restore()
		await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
	await save_restore()
	var row:={"mode":mode,"initial_units":initial_state["units"],"initial_skills":initial_state["skill_book"]["actors"]["002"],
		"initial_moon_fields":initial_state["skill_book"]["skills"][MoonRules.ID]["fields"],"initial_ai_profile":initial_state["ai_profiles"]["actors"]["002"],
		"final_units":scene.play_loop["units"],"outcome":scene.play_loop["battle_outcome"],"impacts":impacts.duplicate(true),"receipts":receipts.duplicate(true),
		"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen,"terminal cannot run further receiver callbacks")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["player_unit_id"]=="tina" and not scene.play_loop["extra_action"]["pending"],"real restart uses published training defaults without old phases or resources")
		row["restarted"]=true
	routes.append(row)


func shot(label:String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png";check(root.get_texture().get_image().save_png(MOON_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)


func write_receipt(filename:String) -> void:
	FileAccess.open(MOON_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_moon_dance_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_size":root.size,
		"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"routes":routes,"frames":frames,"failures":failures,
		"setup":"Manual uses published MoonDanceTrial with40 supplied stamina. Other fixtures retain real051 ground and source002 job/heal/Moon/equipment; authoredHP durability/HP1, exp99, speeds/control, extra inventory, forced no_attack targets, silence/poison/paralysis, intrinsic double overrides or hit0 are saved in initial state. No code changes battle state after setup: all payments, results, target changes, AI and queue steps occur through actual controls. Source RNG is not replaced. Large target uses source039. Earlier default phase/double/cost contracts are reused, not new original-grant claims.",
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"observed":observed,"scenario_error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units",[]),"last_combat":scene.play_loop.get("last_combat",{}),"last_ai_actions":scene.play_loop.get("last_ai_actions",[])}},"  "))

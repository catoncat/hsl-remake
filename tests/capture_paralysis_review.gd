extends "res://tests/capture_position_equipment_review.gd"
## Actual controls/normal clocks on original terrain and art. Only setup authors
## encounters and gear grants; no action result, damage, EXP or RNG is replaced.
const ParalysisCases = preload("res://tests/run_paralysis_tests.gd")
const BIND := "magic:magicEARTH:magicCode05"
const PARALYSIS_OUT := "res://ignored/paralysis-review/"
var entry_events: Array = []
var seen_entries := {}
var earth_tails := {}

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Paralysis review requires the rendered built-in window");quit(2);return
	root.title="HSL Paralysis and Action Entry Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(PARALYSIS_OUT);run_started=Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func():check(false,"bounded paralysis review timed out"))
	var names:Array=["enemy_skip","player_skip","player_cure","ai_cure","support_bound","immunity","axe_growth","mixed_area","ai_bind","resume_skip","detour","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_paralysis()
		if failures.is_empty():await play_paralysis()
		await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("PARALYSIS_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func write_receipt(filename:String)->void:
	FileAccess.open(PARALYSIS_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"pid":OS.get_process_id(),"elapsed_seconds":(Time.get_ticks_msec()-run_started)/1000.0,"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"overrides":"Source WRD/art/job modes and gear eligibility retained. Source controlled026 or024 uses the protagonist harness ID with manual growth. Setup gives baseHP+200/baseMP+100/speed+120 and current resources, original BIND/WIND/HEAL/CURE fixture grants, eight-slot gear/cure inventory. BIND status rate100 is explicit for reliable visual branches; original rate40 is separately tested by native instructions. Foe currentHP500 or named kill1HP, counter/hit compensation, paralysis remaining1/2, poison3/7, silence2 and queue speeds are declared fixtures. Wings/recovery/blood effects on skipped actors and AI movement permission are authored current gear; player gear is changed using real Item controls. AI uses source categories with stated probability100 and no replacement result/RNG. Turn6 terminal report is initialized via existing hooks; all subsequent actions, EXP, drops, growth, save/load and restart use real controls. Terrain never modified; F5/F9 use dedicated ignored files.",
		"routes":routes,"frames":frames,"failures":failures},"  "))

func install_fixture_gear(actor:Dictionary,loop:Dictionary,slot:String,code:int)->void:
	actor["equipment"]=actor["equipment"].filter(func(e):return e["slot"]!=slot)
	actor["equipment"].append({"slot":slot,"item_code":code,"name":loop["equipment_items"][str(code)]["name"]})
	actor["equipment"].sort_custom(func(a,b):return Loop.EquipmentRules.SLOTS.find(a["slot"])<Loop.EquipmentRules.SLOTS.find(b["slot"]))

func setup_paralysis()->void:
	observed={};cues=[];sound_paths={};experience_events=[];pair_receipts=[];resource_beats=[];seen_tail_events={};entry_events=[];seen_entries={};earth_tails={};action_serial=0;transition_seen=false;equipment_previews=[];receipt={}
	scene=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate();scene.scenario_path=BattleFixture.PATH;scene.startup_mode="dev_first_control";root.add_child(scene);current_scene=scene
	scene.start_dev_first_control_harness();scene.set_process(false);await create_timer(0.15).timeout;scene.get_node("BattleMusic").stop()
	chosen_role="024" if mode=="axe_growth" else "001" if mode in ["victory","escape","detour"] else "026"
	var loop:=ParalysisCases.fixture(chosen_role)
	loop["tiles"]=scene.play_loop["tiles"];loop["map_size"]=scene.play_loop["map_size"]
	var actor:=Loop._unit(loop,"leonard");var enemy:=Loop._unit(loop,"enemy021_1");var ally:=Loop._unit(loop,"enemy023_1")
	actor["hit_bonus_accum"]=1000;actor["inventory"]=[211,248,232,227,31 if chosen_role=="024" else 12,236,241,0]
	ally["coord"]=Vector2i(17,19);ally["live_speed"]=100;ally["battle_actor_role"]=Loop.ROLE_PLAYER
	enemy["combat_profile"]["attack_back"]=0;enemy["no_attack"]=true
	TestSuite.own(loop, "skill_book")["skills"][BIND]["fields"]["status_hit_ratio"]="100"
	TestSuite.own(loop, "skill_book")["skills"][BIND]["fields"]["use_ratio"]="100"
	if mode in ["enemy_skip","resume_skip"]:install_fixture_gear(enemy,loop,"accessory2",227)
	if mode in ["player_cure","ai_cure"]:
		ally["coord"]=Vector2i(11,8);enemy["coord"]=Vector2i(17,18)
		ParalysisCases.afflict(ally);ally.merge(Loop.StatusEffectRules.apply(ally,"no_magic",2)["changes"],true)
		install_fixture_gear(ally,loop,"accessory2",227)
		actor["mp"]=0;actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	if mode=="support_bound":
		ally["coord"]=Vector2i(11,8);ally["hp"]=4;enemy["coord"]=Vector2i(17,18)
		ParalysisCases.afflict(ally);ally.merge(Loop.StatusEffectRules.apply(ally,"poison",3,7)["changes"],true)
		ally.merge(Loop.StatusEffectRules.apply(ally,"no_magic",2)["changes"],true)
	if mode=="immunity":
		var caster:=Loop.unit(BattleFixture.loop(),"enemy026_1")
		caster.merge({"id":"enemy021_1","coord":Vector2i(11,8),"live_speed":110,"player_commandable":true,"battle_actor_role":Loop.ROLE_ENEMY,"inventory":[0,0,0,0,0,0,0,0]},true)
		caster["growth_profile"]["source"]["magic_point"]+=100
		caster.merge(Loop.ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true);caster["mp"]=caster["max_mp"];caster["live_speed"]=110
		loop["units"]=[actor,caster,ally];enemy=caster
	if mode=="axe_growth":
		actor["exp"]=99;enemy["hp"]=1;ParalysisCases.afflict(enemy)
		var later:=enemy.duplicate(true);later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"live_speed":60},true)
		loop["units"].append(later)
	if mode=="mixed_area":
		actor["exp"]=99;install_fixture_gear(enemy,loop,"accessory2",211)
		var later:=enemy.duplicate(true);later.merge({"id":"enemy021_2","coord":Vector2i(10,9),"hp":500,"live_speed":60},true)
		later["equipment"]=later["equipment"].filter(func(e):return not e["slot"].begins_with("accessory"));loop["units"].append(later)
	var observer_mode:bool=mode in ["player_skip","ai_cure","ai_bind","defeat","escape"]
	if observer_mode:
		var starter:=Loop.unit(BattleFixture.loop(),"enemy024_1")
		starter.merge({"id":"paralysis-observer","coord":Vector2i(6,14),"live_speed":300,"player_commandable":true,"battle_actor_role":Loop.ROLE_PLAYER},true)
		loop["units"].append(starter);actor["live_speed"]=160
	if mode in ["ai_cure","ai_bind"]:
		actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY;actor["growth_profile"]["allocation"]="fixed_template"
		TestSuite.own(loop, "ai_profiles")["actors"][chosen_role]["profile"].merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":100 if mode=="ai_cure" else 0},true)
		actor["inventory"]=[248,0,0,0,0,0,0,0] if mode=="ai_cure" else [0,0,0,0,0,0,0,0]
	if mode=="ai_bind":
		install_fixture_gear(actor,loop,"accessory1",232);install_fixture_gear(actor,loop,"accessory2",227)
		actor["mp"]=16;actor["no_attack"]=false;enemy["coord"]=Vector2i(11,8);enemy["no_attack"]=false
		enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["supported_initial_ids"]=[BIND]
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["double_attack"]=true
	if mode=="player_skip":
		install_fixture_gear(actor,loop,"armor",145);install_fixture_gear(actor,loop,"accessory1",227);install_fixture_gear(actor,loop,"accessory2",224)
		ParalysisCases.afflict(actor,1);actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
		actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true);actor["hp"]=20;actor["mp"]=0
	if mode in ["victory","defeat","escape"]:
		var view=scene.get_node("BattlePresentation");view._shown_story_events.assign(loop["event_log"])
		actor=Loop._unit(loop,"leonard");enemy=Loop._unit(loop,"enemy021_1")
		if mode=="victory":actor["exp"]=99;enemy["hp"]=1
		elif mode=="defeat":
			actor["coord"]=Vector2i(10,8);actor["hp"]=1;ParalysisCases.afflict(actor);install_fixture_gear(actor,loop,"accessory2",227)
			enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["live_speed"]=180;enemy["combat_profile"]["live_attack_damage"]=1000
		else:
			enemy["coord"]=Vector2i(17,18);landing=loop["escape_zone"][0]
			var found:=false
			for y in range(loop["map_size"].y):
				for x in range(loop["map_size"].x):
					var at:=Vector2i(x,y)
					if loop["tiles"].get(at,{}).get("blocks_movement",false) or loop["escape_zone"].has(at) or Loop.unit_id_at_coord(loop,at) not in ["","leonard"]:continue
					actor["coord"]=at;var path:=Loop.movement_path(loop,"leonard",landing)
					if path.size()>=2 and path.size()<=5:found=true;break
				if found:break
			check(found,"source terrain has a legal post-expiry escape approach");ParalysisCases.afflict(actor,1)
	if mode=="detour":
		actor["coord"]=Vector2i(7,10);enemy["coord"]=Vector2i(17,18)
		scene.center_camera_on_grid(actor["coord"])
		var found:=false
		for cell in Loop.movement_cells(loop,"leonard"):
			var path:=Loop.movement_path(loop,"leonard",cell)
			if path.size()<=Loop._manhattan(path[0],cell)+1 or not Rect2(48,48,540,340).has_point(scene.grid_cell_center_to_logical_position(cell)):continue
			for offset in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				var target:Vector2i=cell+offset
				if path.has(target) or loop["tiles"].get(target,{}).get("blocks_movement",false) or Loop.unit_id_at_coord(loop,target)!="":continue
				enemy["coord"]=target;landing=cell;found=true;break
			if found:break
		check(found,"source obstacle offers a detour ending at a real binding target")
	for unit in loop["units"]:
		unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
		check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false),"fixture starts on source ground: %s %s"%[unit["id"],unit["coord"]])
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(Loop._return_to_player(loop,"paralysis-observer" if observer_mode else "leonard"), "test")
	scene.settlement_controller.checkpoint_path=PARALYSIS_OUT+mode+".save"
	for node in scene.actors_root.get_children():scene.actors_root.remove_child(node);node.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(Loop.unit(loop,"paralysis-observer" if observer_mode else "leonard")["coord"])
	var view=scene.get_node("BattlePresentation");view.turn_end_cue.finish(scene.play_loop)
	view.experience_presented.connect(func(e):experience_events.append(e.duplicate(true)))
	view.cutin.impact.connect(func(s,_a,_d,c):
		cues.append({"skill":s.get("skill_id"),"attacker":s["attacker_id"],"defender":s["defender_id"],"counter":c})
		check(not scene.action_menu.visible and not view.battle_finished,"impact precedes successor/result UI"))
	position_before=actor.duplicate(true);scene.set_process(true);await create_timer(0.35).timeout

func real_use(code:int,target:String)->void:
	await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(code));await click(scene.item_panel.target_buttons[target])

func wait_to(id:String,terminal:bool=false)->void:
	await click(scene.action_menu.get_node("WaitCommand"));await settle(id,terminal)

func play_paralysis()->void:
	var terminal:bool=mode in ["victory","defeat","escape"]
	if mode in ["enemy_skip","resume_skip"]:
		await cast_real(BIND,"enemy021_1");await settle("enemy023_1")
		var turns:int=Loop.unit(scene.play_loop,"enemy021_1")["status_counters"]["paralysis"]
		check(turns in [2,3],"actual source binding produces its sampled finite duration")
		if mode=="resume_skip":
			var saved:Dictionary=scene.play_loop.duplicate(true);await key(KEY_F5)
			await wait_to("leonard");var first:Dictionary=scene.play_loop.duplicate(true)
			await key(KEY_F9);check(scene.play_loop==saved,"restoring before the pending skip restores the original stage")
			await wait_to("leonard");check(scene.play_loop==first,"one resumed skip reproduces resources/queue without replaying prior spell/EXP")
		else:
			for index in range(turns):
				await wait_to("leonard")
				check(not scene.play_loop["extra_action"]["pending"] and scene.play_loop["last_ai_actions"].size()==1,"paralyzed foe with wings executes one skip per queue cycle")
				if index+1<turns:await wait_to("enemy023_1")
			check(not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"enemy021_1")),"actual repeated queue cycles expire paralysis")
	elif mode in ["player_skip","escape"]:
		await wait_to("enemy023_1")
		check(entry_events.size()==1 and not observed.has("again") and not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"leonard")),"skipped player expires once without an extra-action grant")
		if mode=="player_skip":check(resource_beats.map(func(e):return e["kind"])==["poison","auto_mp","transfer_hp","transfer_mp","paralysis_expired"],"skipped entry preserves poison/recovery/blood/expiry order")
		await save_restore();await wait_to("paralysis-observer");await wait_to("leonard")
		check(Loop.command_available(scene.play_loop,"move"),"the next healthy entry restores real movement controls")
		if mode=="escape":await change_item(227,"accessory2")
		await wait_to("leonard");check(scene.play_loop["extra_action"]["pending"],"a later healthy action independently grants wings' second action")
		if mode=="escape":await save_restore();await move_to(landing);await wait_to("enemy023_1",true)
	elif mode=="player_cure":
		await move_to(Vector2i(10,8));await real_use(248,"enemy023_1");await settle("enemy023_1")
		check(scene.play_loop["last_item_use"]["cured_paralysis"] and Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,"enemy023_1")),"real spirit stone releases paralysis while retaining silence")
		check(not Loop.unit(scene.play_loop,"leonard")["inventory"].has(248),"actual movement and cure spend one item")
		await wait_to("enemy023_1");check(scene.play_loop["extra_action"]["pending"],"rescued ally retains its ordinary independent extra-action eligibility")
	elif mode=="support_bound":
		await change_item(232,"accessory1");await change_item(227,"accessory2");await move_to(Vector2i(10,8))
		var counters:Dictionary=Loop.unit(scene.play_loop,"enemy023_1")["status_counters"].duplicate(true)
		await cast_real(PositionCases.HEAL,"enemy023_1");await settle("leonard")
		check(pair_receipts.back()["healing"]>0 and Loop.unit(scene.play_loop,"enemy023_1")["status_counters"]==counters,"moved healing restores HP without releasing paralysis or clearing poison/silence")
		await save_restore();await cast_real(PositionCases.CURE,"enemy023_1");await settle("leonard")
		check(entry_events.size()==1 and Loop.unit(scene.play_loop,"enemy023_1")["status_counters"]=={"poison":0,"paralysis":1,"no_magic":1},"second-action cure removes poison, then the patient skips once and retains the other conditions")
	elif mode in ["ai_cure","ai_bind"]:
		await wait_to("enemy023_1");pair_receipts=scene.play_loop["last_ai_actions"].duplicate(true)
		if mode=="ai_cure":
			check(pair_receipts.size()==1 and pair_receipts[0]["kind"]=="move_then_item" and observed.has("item") and not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"enemy023_1")),"silenced zero-MP AI walks, uses the real cure and releases patient controls")
		else:
			check(pair_receipts.size()==2 and pair_receipts[0].get("skill_id")==BIND and not pair_receipts[1].has("skill_id"),"AI spends binding MP then redecides its independent second action")
			check(Loop.CombatSequence.participant_strikes(pair_receipts[1]).size()==2 and pair_receipts[1]["counter"].is_empty(),"second-action ordinary double attack cannot receive a paralyzed counter")
			check(cues.size()==3 and cues[0]["skill"]==BIND and cues.all(func(c):return not c["counter"]),"rendered AI binding and its two later physical impacts each occur exactly once")
	elif mode=="immunity":
		await change_item(211,"accessory1",true);await wait_to("enemy021_1")
		await cast_real(BIND,"leonard");await settle("enemy023_1")
		check(pair_receipts.back()["status_effects"][0]["reason"]=="immune","source ring blocks an actual binding without a false duration or contribution")
		await wait_to("leonard");await change_item(0,"accessory1");await save_restore();await wait_to("enemy021_1")
		await cast_real(BIND,"leonard");await settle("enemy023_1");await wait_to("enemy021_1")
		check(not entry_events.is_empty() and Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"leonard")),"removing the final protection permits binding and actual skipped player entry")
	elif mode=="axe_growth":
		await change_item(31,"weapon",true);await move_to(Vector2i(10,8));await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("enemy023_1")
		check(observed.has("growth") and Loop.unit(scene.play_loop,"leonard")["level"]==2 and Loop.StatusApplicationRules.modifiers(Loop.unit(scene.play_loop,"leonard"),scene.play_loop["skill_book"],scene.play_loop["equipment_items"])["effects"] & 0x4000000,"source axe and actual job growth retain paralysis protection")
	elif mode=="mixed_area":
		await change_item(232,"accessory1");await move_to(Vector2i(9,8))
		await click(scene.action_menu.get_node("MagicCommand"));await click(scene.magic_panel.choices[BIND])
		var center:=Vector2i(10,8);check(Loop.unit_id_at_coord(scene.play_loop,center)=="","binding selects actual empty center")
		await point(scene.grid_cell_center_to_logical_position(center));pair_receipts.append(scene.play_loop["last_attack"].duplicate(true));await settle("enemy023_1")
		check(pair_receipts[0]["affected_targets"].size()==2 and not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"enemy021_1")) and Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"enemy021_2")),"one moved cast settles protected and susceptible targets separately")
		check(observed.has("growth") and Loop.unit(scene.play_loop,"leonard")["level"]==2,"actual non-damaging contribution enters final EXP and growth")
	elif mode=="detour":
		await change_item(236,"accessory1");await move_to(landing);await cast_real(BIND,"enemy021_1");await settle("enemy023_1")
		var path:Array=observed["last_path"];check(path.size()>Loop._manhattan(path[0],path.back())+1 and pair_receipts.back()["status_effects"][0]["applied"],"real source detour ends in one legal binding transaction")
	elif mode=="victory":
		await change_item(12,"weapon");await change_item(227,"accessory2");await cast_real(BIND,"enemy021_1");await settle("leonard")
		check(observed.has("growth") and Loop.unit(scene.play_loop,"leonard")["level"]==2,"status contribution levels before the independent finishing action")
		await save_restore();await move_to(Vector2i(10,8));await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("enemy023_1",true)
		check(receipt["followups"].is_empty() and receipt["counter"].is_empty(),"lethal first strike truncates the extra attack against the bound target")
	else:await wait_to("enemy023_1",true)
	await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	routes.append({"mode":mode,"before":compact(position_before),"after":compact(Loop.unit(final,"leonard")),"actors":final["units"].map(compact),"receipts":pair_receipts,"entries":entry_events,"beats":resource_beats,"observed":observed,"earth_tails":earth_tails,"equipment_previews":equipment_previews,"extra_action":final["extra_action"],"last_action_end":final["last_action_end"],"sounds":sound_paths.keys(),"experience":experience_events,"cues":cues,"outcome":final["battle_outcome"]})
	if terminal:
		check(not final["extra_action"]["pending"] and Loop.finish_exhausted_action(final)==final,"terminal cannot repeat paralysis/status/resources or a leftover action")
		reload_current_scene();await create_timer(0.3).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["extra_action"]==Loop.ExtraActionRules.empty() and not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"leonard")),"real retry starts default healthy actor and new queue")
		routes.back()["restarted"]=true

func settle(id:String,terminal:bool=false)->void:
	for _attempt in range(2400):
		var view=scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream!=null and sound.get_playback_position()>0:sound_paths[sound.stream.resource_path]=true
		if view.item_feedback_busy() and not observed.has("item"):
			observed["item"]=true
			check(view._item_feedback.text=="麻痺解除" and not scene.action_menu.visible,"actual spirit-stone feedback names the cured condition and gates the next controls")
			await shot("cure-item")
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺"):
			var key_text:="%s:%s"%[scene.play_loop["action_end_sequence"],scene.play_loop.get("last_ai_action",{}).get("actor_id")]
			if not seen_entries.has(key_text):
				seen_entries[key_text]=true;entry_events.append(scene.play_loop["last_ai_action"].duplicate(true))
				check(not scene.action_menu.visible and not view.turn_end_cue.showing(),"visible skipped-entry cue precedes its resource/expiry tail and controls")
				await shot("skip-"+key_text.replace(":","-"))
		if view.turn_end_cue.showing():
			var key_text:="%s:%s"%[scene.play_loop["action_end_sequence"],view.turn_end_cue.cursor]
			if not seen_tail_events.has(key_text):
				seen_tail_events[key_text]=true;resource_beats.append(scene.play_loop["last_action_end"]["events"][view.turn_end_cue.cursor].duplicate(true))
				check(not view.cutin.busy() and not view.aftermath.busy() and not scene.has_actor_motion() and not view.item_feedback_busy() and not scene.action_menu.visible,"tail waits for prior action and gates successor controls")
				await shot("tail-"+key_text.replace(":","-"))
		if view.cutin.busy():
			var clip:Dictionary=view.cutin.clips[0]
			var impact_key:="impact-%s-%s"%[action_serial,cues.size()]
			if clip["impact_emitted"] and not observed.has(impact_key):
				observed[impact_key]=true;await shot(impact_key)
			if clip["strike"].get("magic_key")=="paralysis" and not earth_tails.has(action_serial) and clip.has("effect_timeline") and view.cutin.Timing.CAST_LEAD_IN+float(clip["effect_timeline"]["complete_tick"])*view.cutin.Timing.PLAYBACK_SPEED/view.cutin.skill_effects.TICKS_PER_SECOND-view.cutin.elapsed<0.10:
				var peak:=0.0
				for sprite in view.cutin.skill_effects.sprites:
					if sprite.visible:peak=maxf(peak,sprite.modulate.a)
				earth_tails[action_serial]=peak;check(peak<=0.001,"last original earth/smoke frames finish before action handoff");await shot("earth-tail-"+str(action_serial))
		if view.extra_action_cue.label.visible:observed["again"]=true
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for attribute in ["str","dex","mind","mind","con"]:await click(scene.growth_panel.choices[attribute]["plus"])
			await shot("growth");await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(scene.play_loop["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual action reaches requested terminal")
			await shot("result");action_serial+=1;return
		if not terminal and scene.selected_unit_id==id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(action_serial));action_serial+=1;return
		await create_timer(0.02).timeout
	check(false,"bounded paralysis route reaches expected control/result: "+id)

func shot(label:String)->void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(PARALYSIS_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func check(ok:bool,message:String)->void:
	if ok:return
	failures.append(mode+": "+message);push_error(mode+": "+message)
	DirAccess.make_dir_recursive_absolute(PARALYSIS_OUT);write_receipt("failed.json");quit(1)

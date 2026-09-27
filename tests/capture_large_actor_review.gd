extends "res://tests/capture_position_equipment_review.gd"
## Source terrain/art, authored encounters, actual controls and normal clocks.
## No injected RNG/result, terrain edits or direct action/queue advancement in play.
const run_large_actor_tests = preload("res://tests/run_large_actor_tests.gd")
const LARGE_OUT := "res://ignored/large-actor-review/"
const BIND_LARGE := "magic:magicEARTH:magicCode05"
var body_entries: Array = []
var initial_loop := {}
var saves_checked := 0

func run() -> void:
	if DisplayServer.get_name() == "headless":push_error("Large review requires a rendered built-in window");quit(2);return
	root.title="HSL Large Actor Spatial Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(LARGE_OUT);run_started=Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func():check(false,"bounded whole-body review timeout"))
	var names:Array=["trial","movement","edge_series","giant_combat","empty_area","support","cure_item","skip_resume","ai_resource","ai_retarget","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_large()
		if failures.is_empty():await play_large()
		await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("LARGE_ACTOR_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func write_receipt(filename:String)->void:
	FileAccess.open(LARGE_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({
		"schema":"hsl_large_actor_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,
		"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"elapsed_seconds":(Time.get_ticks_msec()-run_started)/1000.0,
		"overrides":"Trial route starts the published development scene unchanged. Other encounters are authored on unchanged original051 WRD/art. Source039/job94 remains one 3x3 actor. Named controlled039 uses protagonist ID/manual growth, sourceHP+500/speed+180; supportive39 fixtures explicitly grant supported spells, baseMP100 and the already-proven innate moved-casting capability, NOT illegal caster-only equipment. Player gear changes use real inventory controls and original job masks. Other setup changes are declared in initial_units/skill_overrides: foeHP1 or500, fixed action order, no_attack except counter/defeat/resource cases, hit compensation1000, finite poison/paralysis/silence, rates100 for reliable AI/status branches. Source039 default spell ownership is not changed. Turn6 terminal setup consumes existing event hooks; all actions, paths, payments, effects, EXP/growth/loot, F5/F9 and restarts thereafter use actual controls, original art/sound and normal clocks. No fake RNG, damage, target result, map or action-queue completion.",
		"routes":routes,"frames":frames,"failures":failures},"  "))

func fixture_gear(actor:Dictionary,loop:Dictionary,slot:String,code:int)->void:
	actor["equipment"]=actor["equipment"].filter(func(e):return e["slot"]!=slot)
	actor["equipment"].append({"slot":slot,"item_code":code,"name":loop["equipment_items"][str(code)]["name"]})
	actor["equipment"].sort_custom(func(a,b):return BattlePlayLoop.EquipmentRules.SLOTS.find(a["slot"])<BattlePlayLoop.EquipmentRules.SLOTS.find(b["slot"]))

func afflict(actor:Dictionary,kind:String,turns:int,strength:int=0)->void:
	var result:=BattlePlayLoop.StatusEffectRules.apply(actor,kind,turns,strength)
	check(result["ok"],"valid supplied affliction: "+kind)
	if result["ok"]:actor.merge(result["changes"],true)

func setup_large()->void:
	observed={};cues=[];sound_paths={};experience_events=[];pair_receipts=[];resource_beats=[];seen_tail_events={};body_entries=[];action_serial=0;equipment_previews=[];receipt={};saves_checked=0
	scene=load("res://game/battle/development/LargeActorTrial.tscn" if mode=="trial" else "res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	if mode!="trial":scene.scenario_path=BattleFixture.PATH;scene.startup_mode="dev_first_control"
	root.add_child(scene);current_scene=scene
	if mode=="trial":
		await create_timer(0.4).timeout
		scene.settlement_controller.checkpoint_path=LARGE_OUT+mode+".save"
		await settle("leonard")
		initial_loop=scene.play_loop.duplicate(true)
		return
	scene.start_dev_first_control_harness();scene.set_process(false);await create_timer(0.15).timeout
	var loop:=BattleFixture.loop();loop["units"]=[];loop["reinforcement_templates"]=[]
	chosen_role="026" if mode in ["empty_area","ai_resource"] else "001" if mode in ["edge_series","escape"] else "039"
	var stock:=BattleFixture.loop()
	var actor:=run_large_actor_tests.source_large() if chosen_role=="039" else BattlePlayLoop.unit(stock,"enemy026_1" if chosen_role=="026" else "leonard")
	actor.merge({"id":"leonard","coord":Vector2i(13,17),"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER},true)
	actor["growth_profile"]["allocation"]="manual";actor["growth_profile"]["source"]["hit_point"]+=500;actor["growth_profile"]["source"]["speed"]+=180
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"]=actor["max_hp"];actor["mp"]=actor["max_mp"];actor["hit_bonus_accum"]=1000
	actor["inventory"]=[227,233,231,231,248,241,12 if chosen_role=="001" else 232,0]
	var end:=BattlePlayLoop.unit(stock,"enemy023_1")
	end.merge({"id":"observer_end","coord":Vector2i(20,21),"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"player_commandable":true,"live_speed":100},true)
	var enemy:=run_large_actor_tests.source_large()
	enemy.merge({"coord":Vector2i(16,17),"hp":500,"max_hp":500,"no_attack":true,"live_speed":50,"inventory":[0,0,0,0,0,0,0,0]},true)
	loop["units"]=[actor,end,enemy]
	if mode=="movement":
		actor["coord"]=Vector2i(8,21);end["coord"]=Vector2i(10,20);enemy["coord"]=Vector2i(15,21)
		landing=Vector2i(12,21)
	if mode=="edge_series":
		actor["coord"]=Vector2i(9,14);enemy["coord"]=Vector2i(12,14)
		enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100
		TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true;afflict(actor,"poison",3,7)
	if mode in ["giant_combat","ai_retarget"]:
		enemy["hp"]=1
		var later:=enemy.duplicate(true);later.merge({"id":"later039","coord":Vector2i(16,20),"hp":500,"live_speed":40},true)
		loop["units"].append(later);actor["exp"]=99
		TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true;afflict(actor,"poison",3,7)
	if mode in ["support","cure_item","skip_resume"]:
		run_large_actor_tests.spell_kit(loop)
		TestSuite.own(loop, "skill_book")["actors"]["039"]["move_magic_use"]=true
		actor=BattlePlayLoop._unit(loop,"leonard");actor["hp"]=actor["max_hp"]
	if mode in ["support","cure_item"]:
		var patient:=enemy.duplicate(true)
		patient.merge({"id":"patient039","battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"player_commandable":true,"hp":4,"live_speed":80},true)
		afflict(patient,"paralysis",2);afflict(patient,"poison",3,7);afflict(patient,"no_magic",2)
		loop["units"].append(patient);enemy["coord"]=Vector2i(20,17)
		if mode=="support":afflict(actor,"poison",3,7)
		else:actor["mp"]=0;afflict(actor,"no_magic",2)
	if mode in ["empty_area","ai_resource"]:
		run_large_actor_tests.spell_kit(loop);actor=BattlePlayLoop._unit(loop,"leonard")
		actor["coord"]=Vector2i(9,14);enemy["coord"]=Vector2i(13,14)
		TestSuite.own(loop, "skill_book")["skills"][BIND_LARGE]["fields"].merge({"status_hit_ratio":"100","use_ratio":"100"},true)
		if mode=="empty_area":
			var second:=BattlePlayLoop.unit(stock,"enemy021_1");second.merge({"id":"small_target","coord":Vector2i(11,15),"no_attack":true,"hp":500,"max_hp":500,"live_speed":40},true)
			loop["units"].append(second);actor["exp"]=99
	if mode in ["ai_resource","ai_retarget","skip_resume"]:
		var observer:=end.duplicate(true)
		observer.merge({"id":"observer","coord":Vector2i(6,18),"live_speed":300},true);loop["units"].append(observer)
	if mode.begins_with("ai_"):
		actor["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY;actor["player_commandable"]=false;actor["growth_profile"]["allocation"]="fixed_template"
		fixture_gear(actor,loop,"accessory2",227);actor["inventory"]=[0,0,0,0,0,0,0,0]
		if mode=="ai_resource":
			fixture_gear(actor,loop,"accessory1",232);actor["mp"]=16
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"]=[BIND_LARGE]
			TestSuite.own(loop, "skill_book")["actors"]["026"]["double_attack"]=true
			TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0},true)
			enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100
		else:afflict(actor,"no_magic",2)
	if mode=="skip_resume":
		fixture_gear(actor,loop,"accessory1",224);fixture_gear(actor,loop,"accessory2",227)
		actor["hp"]=20;actor["mp"]=0;afflict(actor,"paralysis",2);afflict(actor,"poison",3,7);afflict(actor,"no_magic",2)
		actor["status_counters"]["paralysis"]=1 # Supplied remaining time, not an invalid newly sampled one-turn application.
	if mode in ["victory","defeat","escape"]:
		actor=BattlePlayLoop._unit(loop,"leonard");enemy=BattlePlayLoop._unit(loop,"enemy039_1")
		var view=scene.get_node("BattlePresentation");view._shown_story_events.assign(loop["event_log"])
		if mode=="victory":enemy["hp"]=1
		elif mode=="defeat":
			actor["hp"]=1;enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100;enemy["combat_profile"]["live_attack_damage"]=1000
		else:actor["coord"]=Vector2i(13,10);enemy["coord"]=Vector2i(16,20);landing=loop["escape_zone"][0]
	for a in loop["units"]:
		a["grid_coord"]=a["coord"];a["ai_home_coord"]=a["coord"]
		check(BattlePlayLoop.TraversalRules.placement_error(a,loop["units"],loop["tiles"],loop["map_size"])=="","source map accepts complete body: "+a["id"])
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	var starter:="observer" if mode in ["skip_resume","ai_resource","ai_retarget"] else "leonard"
	check(BattlePlayLoop.CoreTurnQueue.current(loop["turn_queue"])["id"]==starter,"fixture starts at its actual queue owner")
	scene.apply_loop(BattlePlayLoop._return_to_player(loop,starter), "test")
	scene.settlement_controller.checkpoint_path=LARGE_OUT+mode+".save"
	for node in scene.actors_root.get_children():scene.actors_root.remove_child(node);node.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(BattlePlayLoop.unit(loop,starter)["coord"])
	var view=scene.get_node("BattlePresentation");view.turn_end_cue.finish(scene.play_loop)
	view.experience_presented.connect(func(e):experience_events.append(e.duplicate(true)))
	view.cutin.impact.connect(func(s,_a,_d,c):
		cues.append({"skill":s.get("skill_id"),"attacker":s["attacker_id"],"defender":s["defender_id"],"counter":c,"center":s.get("cast_center")})
		check(not scene.action_menu.visible and not view.battle_finished,"impact is before successor controls/result"))
	initial_loop=scene.play_loop.duplicate(true);scene.set_process(true);await create_timer(0.35).timeout

func body_state(loop:Dictionary)->Array:
	var result:Array=[]
	for a in loop["units"]:
		var row:=compact(a);row["traversal"]=a["traversal"];row["level"]=a["level"];row["exp"]=a["exp"];row["equipment"]=a["equipment"]
		row["occupied_cells"]=[] if a["defeated"] else BattlePlayLoop.Footprint.cells(a)
		result.append(row)
	return result

func save_restore()->void:
	var before:Dictionary=scene.play_loop.duplicate(true)
	await key(KEY_F5)
	var verified:=run_large_actor_tests.BattleCheckpoint.read(scene.settlement_controller.checkpoint_path, before)
	check(verified["ok"] and verified["snapshot"]["loop"]==before,"F5 writes an actual valid whole-body/phase checkpoint")
	await key(KEY_F9)
	check(scene.play_loop==before and body_state(scene.play_loop)==body_state(before),"F9 restores one actor per body without replaying state or actions")
	saves_checked+=1;await shot("restored-"+str(saves_checked))

func attack_at(cell:Vector2i)->void:
	await click(scene.action_menu.get_node("AttackCommand"));await hover(scene.grid_cell_center_to_logical_position(cell));await create_timer(0.08).timeout
	var view=scene.get_node("BattlePresentation")
	check(scene.attack_overlay_cells.has(cell) and view.target_vitals.visible,"clicked body edge exposes legal range and its one target's vitals")
	await shot("attack-edge-"+str(action_serial))
	await point(scene.grid_cell_center_to_logical_position(cell));receipt=scene.play_loop["last_attack"].duplicate(true)
	check(receipt.get("cast_center")==cell,"ordinary attack preserves actual body-edge selection")
	pair_receipts.append(receipt.duplicate(true))

func cast_at(id:String,cell:Vector2i)->void:
	await click(scene.action_menu.get_node("MagicCommand"));await click(scene.magic_panel.choices[id])
	await hover(scene.grid_cell_center_to_logical_position(cell));await create_timer(0.08).timeout;await shot("cast-center-"+str(action_serial))
	await point(scene.grid_cell_center_to_logical_position(cell));receipt=scene.play_loop["last_attack"].duplicate(true)
	check(receipt.get("skill_id")==id and receipt.get("cast_center")==cell,"spell keeps actual selected body edge/empty center")
	pair_receipts.append(receipt.duplicate(true))

func use_at(code:int,id:String)->void:
	await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(code));await click(scene.item_panel.target_buttons[id])

func wait_to(id:String,terminal:bool=false)->void:
	await click(scene.action_menu.get_node("WaitCommand"));await settle(id,terminal)

func play_large()->void:
	var terminal:bool=mode in ["victory","defeat","escape"]
	match mode:
		"trial":
			check(scene.play_loop["scenario_ok"] and BattlePlayLoop.unit(scene.play_loop,"large039_friend")["actor_id"]=="039","published trial starts with source039 and actual controls")
			var edge:Vector2i=BattlePlayLoop.unit(scene.play_loop,"large039_friend")["coord"]+Vector2i.LEFT
			await shot("trial-before-inspection")
			await point(scene.grid_cell_center_to_logical_position(edge));await create_timer(0.15).timeout
			check(scene.status_panel.visible and scene.status_panel.inspected_unit_id=="large039_friend","clicking non-current giant body edge inspects the same actor")
			await shot("source039-status");await escape();await create_timer(0.3).timeout
		"movement":
			await change_item(231,"accessory1",true);await change_item(231,"accessory2")
			await click(scene.action_menu.get_node("MoveCommand"));var blocked:=Vector2i(10,21)
			await hover(scene.grid_cell_center_to_logical_position(blocked));await shot("whole-body-blocked")
			var before:Dictionary=scene.play_loop.duplicate(true);await point(scene.grid_cell_center_to_logical_position(blocked));check(scene.play_loop==before,"friendly outer-cell blocker rejects the whole-body landing without spending movement")
			await escape();await create_timer(0.3).timeout;await move_to(landing)
			check(observed["last_path"].size()>BattlePlayLoop._manhattan(observed["last_path"][0],landing)+1,"actual whole-body route detours around a friendly occupied ring")
			await save_restore();await escape();await create_timer(0.15).timeout
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]==Vector2i(8,21),"actual cancellation reclaims every original body cell")
			check(scene.interaction_state=="move_select" and scene.move_overlay.visible,"cancel restores the source move-selection phase")
			await shot("cancelled-body");await escape();await settle("leonard")
			await move_to(landing);await attack_at(Vector2i(14,21));await settle("observer_end")
		"edge_series":
			await change_item(12,"weapon");await change_item(227,"accessory2");await move_to(Vector2i(10,14))
			await attack_at(Vector2i(11,14));await settle("leonard")
			check(BattlePlayLoop.CombatSequence.strikes(receipt).size()==4 and observed.has("again"),"edge-selected main/counter two-hit series finishes before the second action")
			await save_restore();await wait_to("observer_end")
			check(resource_beats.filter(func(e):return e["kind"]=="poison").size()==1,"four edge impacts do not multiply the owner's final poison tick")
		"giant_combat":
			await change_item(227,"accessory2");await attack_at(Vector2i(15,17));await settle("leonard")
			check(receipt["followups"].is_empty() and BattlePlayLoop.unit(scene.play_loop,"leonard")["level"]>1 and observed.has("growth"),"large killing strike truncates its followup and completes native EXP/manual growth")
			for cell in BattlePlayLoop.Footprint.cells(BattlePlayLoop.unit(scene.play_loop,"enemy039_1")):check(BattlePlayLoop.unit_id_at_coord(scene.play_loop,cell)=="","all nine defeated cells are released")
			await save_restore();await move_to(Vector2i(14,17));await attack_at(Vector2i(15,19));await settle("observer_end")
			check(receipt["defender_id"]=="later039" and receipt["followups"].size()==1,"second action reaches another living body with an independent series")
		"empty_area":
			await change_item(232,"accessory1");await move_to(Vector2i(10,14))
			var old_mp:int=BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]
			check(BattlePlayLoop.unit_id_at_coord(scene.play_loop,Vector2i(11,14))=="","chosen area center is empty ground")
			await cast_at(BIND_LARGE,Vector2i(11,14));await settle("observer_end")
			check(receipt["affected_targets"].size()==2 and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]==old_mp-16,"one moved empty-center cast affects each large/small target once and pays once")
		"support":
			await change_item(227,"accessory2");await move_to(Vector2i(13,16))
			var old:Dictionary=BattlePlayLoop.unit(scene.play_loop,"patient039")["status_counters"].duplicate(true)
			await cast_at(run_position_equipment_tests.HEAL,Vector2i(15,16));await settle("leonard")
			check(receipt["healing"]>0 and BattlePlayLoop.unit(scene.play_loop,"patient039")["status_counters"]==old,"body-edge healing leaves poison/paralysis/silence and their times alone")
			await save_restore();await move_to(Vector2i(13,15));await cast_at(run_position_equipment_tests.CURE,Vector2i(14,17));await settle("observer_end")
			check(receipt["affected_targets"].size()==2 and BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(scene.play_loop,"patient039")) and not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(scene.play_loop,"patient039")),"second moved empty-center cure deduplicates two bodies without curing paralysis")
		"cure_item":
			await move_to(Vector2i(13,16));await click(scene.action_menu.get_node("MagicCommand"))
			check(scene.magic_panel.choices[run_position_equipment_tests.WIND].disabled,"silenced empty-MP large actor cannot use a spell after moving")
			await shot("disabled-magic");await escape();await create_timer(0.3).timeout
			await use_at(248,"patient039");await settle("observer_end")
			check(scene.play_loop["last_item_use"]["cured_paralysis"] and not BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(scene.play_loop,"patient039")),"resource/status fallback walks then uses one real stone at the large body's edge")
		"skip_resume":
			await save_restore();var saved:Dictionary=scene.play_loop.duplicate(true)
			await wait_to("observer_end");var after:Dictionary=scene.play_loop.duplicate(true)
			check(body_entries.size()==1 and not observed.has("again") and not BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(after,"leonard")),"paralyzed large owner skips once, keeps occupation and expires without granting another action")
			await key(KEY_F9);check(scene.play_loop==saved,"pre-skip checkpoint returns before the pending queue entry")
			await wait_to("observer_end");check(scene.play_loop==after,"resumed skip preserves resource RNG, tail order and queue outcome")
			await save_restore();await wait_to("observer");await wait_to("leonard")
			await move_to(Vector2i(13,16));await wait_to("leonard")
			check(scene.play_loop["extra_action"]["pending"],"healthy next entry regains movement and an independent second action")
		"ai_resource","ai_retarget":
			await wait_to("observer_end");pair_receipts=scene.play_loop["last_ai_actions"].duplicate(true)
			check(pair_receipts.size()==2,"AI executes exactly two independent actions")
			if mode=="ai_resource":
				check(pair_receipts[0].get("skill_id")==BIND_LARGE and not pair_receipts[1].has("skill_id") and pair_receipts[1]["counter"].is_empty(),"AI casts on a body then redecides a zero-MP physical action against its paralyzed target")
			else:check(pair_receipts[0]["defender_id"]=="enemy039_1" and pair_receipts[1]["defender_id"]=="later039" and BattlePlayLoop.unit(scene.play_loop,"enemy039_1")["defeated"],"large AI releases killed body and replans a path to another candidate for its second action")
		"victory","defeat":
			await change_item(227,"accessory2");await attack_at(Vector2i(15,17));await settle("",true)
		"escape":
			await change_item(227,"accessory2");await wait_to("leonard");await save_restore();await move_to(landing);await wait_to("",true)
	await save_restore()
	var final:Dictionary=scene.play_loop.duplicate(true)
	routes.append({"mode":mode,"initial_units":body_state(initial_loop),"skill_overrides":initial_loop["skill_book"]["actors"].get(chosen_role,{}),"final_units":body_state(final),"receipts":pair_receipts,"impacts":cues,"entries":body_entries,"beats":resource_beats,"observed":observed,"saves_checked":saves_checked,"equipment_previews":equipment_previews,"experience":experience_events,"sounds":sound_paths.keys(),"extra_action":final["extra_action"],"action_end_sequence":final["action_end_sequence"],"outcome":final["battle_outcome"]})
	if terminal:
		check(not final["extra_action"]["pending"] and BattlePlayLoop.finish_exhausted_action(final)==final and BattlePlayLoop.step_ai_turn(final)==final,"terminal blocks all extra actions, resource tails and AI movement")
		reload_current_scene();await create_timer(0.35).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["extra_action"]==BattlePlayLoop.ExtraActionRules.empty() and scene.play_loop["action_end_sequence"]==0,"actual restart clears old body deaths, state and action transactions")
		routes.back()["restarted"]=true

func settle(id:String,terminal:bool=false)->void:
	for _attempt in range(3000):
		var view=scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream!=null and sound.get_playback_position()>0:sound_paths[sound.stream.resource_path]=true
		if scene.has_actor_motion():observed["ai_movement"]=true
		if view.item_feedback_busy() and not observed.has("item"):
			observed["item"]=true;check(not scene.action_menu.visible,"item effect finishes before next controls");await shot("item-effect")
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺"):
			var token:="entry-%s-%s"%[scene.play_loop["action_end_sequence"],body_entries.size()]
			if not observed.has("skip-active"):
				observed["skip-active"]=true;body_entries.append(scene.play_loop["last_ai_action"].duplicate(true));await shot(token)
		else:observed.erase("skip-active")
		if view.turn_end_cue.showing():
			var token:="tail-%s-%s"%[scene.play_loop["action_end_sequence"],view.turn_end_cue.cursor]
			if not seen_tail_events.has(token):
				seen_tail_events[token]=true;resource_beats.append(scene.play_loop["last_action_end"]["events"][view.turn_end_cue.cursor].duplicate(true))
				check(not scene.action_menu.visible and not view.cutin.busy() and not view.item_feedback_busy(),"status/resource tail follows action effects before handoff")
				await shot(token)
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"]:
			var token:="impact-%s-%s"%[action_serial,cues.size()]
			if not observed.has(token):observed[token]=true;await shot(token)
		if view.extra_action_cue.label.visible:observed["again"]=true
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for index in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var key_name:String=["str","dex","mind","con"][index%4]
				if not scene.growth_panel.choices[key_name]["plus"].disabled:await click(scene.growth_panel.choices[key_name]["plus"])
			await shot("growth-"+str(action_serial));await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(scene.play_loop["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual action reaches requested terminal")
			await shot("result");action_serial+=1;return
		if not terminal and scene.selected_unit_id==id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(action_serial));action_serial+=1;return
		await create_timer(0.02).timeout
	check(false,"bounded playable body route reaches expected control/result: "+id)

func shot(label:String)->void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(LARGE_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func check(ok:bool,message:String)->void:
	if ok:return
	failures.append(mode+": "+message);push_error(mode+": "+message)
	DirAccess.make_dir_recursive_absolute(LARGE_OUT);write_receipt("failed.json");quit(1)

extends "res://tests/capture_stat_magic_review.gd"
## Real controls after declared setup; source effects/RNG are never patched live.
const ItemCases = preload("res://tests/run_tactical_items_tests.gd")
const ITEM_OUT := "res://ignored/tactical-items-review/"
var item_receipts: Array = []
var item_seen := {}

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Tactical item review requires rendered built-in window"); quit(2); return
	root.title = "HSL Tactical Items Playable Review"; root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(ITEM_OUT); started = Time.get_ticks_msec()
	create_timer(1600).timeout.connect(func():check(false,"bounded tactical item review timeout"))
	var names: Array = ["manual","repeat","expiry","mixed","dispel","cure","stamina","melee","growth","movement","invalid","ai_self","ai_ally","paralysis","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name; await setup_items(); await play_items(); await close_scene(); write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json")
	print("TACTICAL_ITEMS_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	call_deferred("quit",0 if failures.is_empty() else 1)

func setup_items() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={}
	scene=load("res://game/battle/development/TacticalItemsTrial.tscn").instantiate()
	root.add_child(scene);current_scene=scene;scene.settlement_controller.checkpoint_path=ITEM_OUT+mode+".save"
	if mode != "manual":
		scene.set_process(false)
		var loop := ItemCases.fixture()
		# Keep the public training identity on restart/save; this is setup only.
		var config := ItemCases.initial()
		for key in ["scenario_path","scenario_title","consumables"]:loop[key]=config[key].duplicate(true) if config[key] is Dictionary else config[key]
		var actor:=Loop._unit(loop,"tina");var ally:=Loop._unit(loop,"companion");var foe:=Loop._unit(loop,"enemy026_1")
		actor["equipment"]=actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		actor["inventory"]=[262,262,263,247,250,227,244,0]
		if mode=="invalid":
			actor["inventory"]=[247,250,227,0,0,0,0,0];actor["stamina"]=60
			ally.merge(Loop.StatusEffectRules.apply(ally,"no_magic",3)["changes"],true);ally["stamina"]=0
		if mode in ["cure","ai_self","ai_ally","paralysis"]:
			var afflicted:Dictionary=ally if mode=="ai_ally" else actor
			afflicted.merge(Loop.StatusEffectRules.apply(afflicted,"no_magic",3)["changes"],true)
		if mode=="cure":
			actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,5)["changes"],true)
			StatCases.buff(loop,"tina","attack_up",4,24);StatCases.buff(loop,"tina","defense_up",4,30);ally["hp"]=100
		if mode=="stamina":
			actor["mp"]=0;actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
			foe["coord"]=Vector2i(15,16)
		if mode=="movement":
			actor["inventory"]=[263,262,227,232,244,0,0,0];ally["coord"]=Vector2i(15,15);ally["hp"]=100
		if mode=="melee":
			foe["coord"]=Vector2i(15,16);actor["hit_bonus_accum"]=1000;foe["hit_bonus_accum"]=1000;foe["no_attack"]=false
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"]=true;TestSuite.own(loop, "skill_book")["actors"]["026"]["double_attack"]=true
			actor["growth_profile"]["source"]["attack_damagex2"]=100;foe["growth_profile"]["source"]["attack_back"]=100
		if mode=="dispel":
			foe["mp"]=18
			TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"]=[StatCases.DISPEL]
			TestSuite.own(loop, "skill_book")["skills"][StatCases.DISPEL]["fields"]["use_ratio"]="100"
			TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_magic":100},true)
			ally.merge(Loop.StatusEffectRules.apply(ally,"no_magic",3)["changes"],true)
		if mode=="growth":
			actor["inventory"]=[263,227,87,232,244,0,0,0];actor["exp"]=99;actor["hit_bonus_accum"]=1000;ally["hp"]=100
			foe["coord"]=Vector2i(15,16);foe["hp"]=1
			var other:=foe.duplicate(true);other["id"]="enemy026_2";other["coord"]=Vector2i(18,18);other["hp"]=other["max_hp"]
			loop["units"].append(other)
		if mode=="paralysis":
			actor["equipment"].append({"slot":"accessory2","item_code":227})
			actor.merge(Loop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true);actor["status_counters"]["paralysis"]=1;ally["hp"]=100
		if mode.begins_with("ai_"):
			actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY;actor["no_attack"]=true;actor["inventory"]=[247,0,0,0,0,0,0,0]
			actor["equipment"].append({"slot":"accessory2","item_code":227});ally["growth_profile"]["source"]["speed"]=300
			if mode=="ai_self": ally["hp"]=100
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":100 if mode=="ai_self" else 0,"ai_help_status":100,"ai_help_attack":0,"ai_att_magic":100 if mode=="ai_self" else 0},true)
			TestSuite.own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"]=[Priest.HEAL] if mode=="ai_self" else []
			TestSuite.own(loop, "skill_book")["skills"][Priest.HEAL]["fields"]["use_ratio"]="100"
		if mode in ["victory","defeat"]:
			foe["coord"]=Vector2i(15,16);actor["hit_bonus_accum"]=1000
			if mode=="victory":foe["hp"]=1;actor["exp"]=99
			else:
				actor["hp"]=1;foe["no_attack"]=false;foe["hit_bonus_accum"]=1000;foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":1000},true)
		if mode=="escape":actor["coord"]=Vector2i(13,10);ally["coord"]=Vector2i(13,11);foe["coord"]=Vector2i(12,10)
		for unit in loop["units"]:
			unit.merge(Loop.ProgressionRules.refresh_growth_stats(unit,loop["equipment_items"]),true)
			unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
			check(Loop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"])=="","declared route uses legal source terrain")
		loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
		scene.apply_loop(Loop._return_to_player(loop,"companion" if mode.begins_with("ai_") else "tina"), "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(actor["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	scene.get_node("BattlePresentation").cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await create_timer(0.25).timeout

func play_items() -> void:
	await settle("companion" if mode.begins_with("ai_") or mode=="paralysis" else "tina")
	if mode not in ["manual","paralysis"] and not mode.begins_with("ai_"): await change_gear(227,"accessory2")
	if mode=="manual":
		await use_item_real(262,"tina");await settle("companion")
		check(Stats.power(Loop.unit(scene.play_loop,"tina"),"attack_up") in range(5,11),"published training uses actual source random item")
	elif mode=="repeat":
		var before:Dictionary=scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout;await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(262))
		await hover(scene.item_panel.target_buttons["tina"].get_global_rect().get_center());await shot("before-use-range");await escape();await escape();await create_timer(0.25).timeout;await escape();await settle("tina")
		check(scene.play_loop["units"]==before["units"] and scene.play_loop["damage_rng"]==before["damage_rng"],"cancelled inventory target preview consumes neither item nor random draw")
		await use_item_real(262,"tina");await settle("tina");await status_page("tina");await save_restore()
		var first:Dictionary=scene.play_loop["last_item_use"].duplicate(true)
		await use_item_real(262,"tina");await settle("companion")
		check(scene.play_loop["last_item_use"]["draws"].is_empty() and Stats.power(Loop.unit(scene.play_loop,"tina"),"attack_up")==first["stat_effects"][0]["after_power"],"second item extends actual strength without redraw or stacking")
	elif mode=="expiry":
		await use_item_real(263,"tina");await settle("tina");await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		for _turn in range(4):
			if Stats.word(Loop.unit(scene.play_loop,"tina"),"defense_up")==0:break
			await return_to_tina();await save_restore()
			await click(scene.action_menu.get_node("WaitCommand"));await settle("tina");await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		check(Stats.word(Loop.unit(scene.play_loop,"tina"),"defense_up")==0 and events.any(func(e):return e.get("expired",[]).has("defense_up")),"queue cycles naturally expire the smaller item strength")
	elif mode=="mixed":
		await use_item_real(262,"tina");await settle("tina");await cast_stat(StatCases.ATT,"tina");await settle("companion");await return_to_tina()
		var power:=Stats.power(Loop.unit(scene.play_loop,"tina"),"attack_up")
		await use_item_real(262,"tina");await settle("tina");await status_page("tina")
		check(scene.play_loop["last_item_use"]["draws"].is_empty() and Stats.power(Loop.unit(scene.play_loop,"tina"),"attack_up")==power,"item after actual spell retains its merged strength")
	elif mode=="dispel":
		await use_item_real(263,"companion");await settle("tina");await click(scene.action_menu.get_node("WaitCommand"));await settle("companion");await return_to_tina()
		check(Stats.word(Loop.unit(scene.play_loop,"companion"),"defense_up")==0 and Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,"companion")),"enemy dispel removes actual item buff while preserving remaining silence")
		check(impacts.any(func(p):return p["strike"].get("skill_id")==StatCases.DISPEL),"enemy actually selected and rendered the item-buff dispel")
	elif mode=="cure":
		await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[Priest.HEAL].disabled,"silence initially blocks the owned heal");await shot("silenced");await escape();await settle("tina")
		var original:Dictionary=Loop.unit(scene.play_loop,"tina")["status_counters"].duplicate(true)
		await use_item_real(247,"tina");await settle("tina");await status_page("tina");await save_restore()
		var unit:=Loop.unit(scene.play_loop,"tina")
		for key in ["poison","attack_up","defense_up"]:check(unit["status_counters"][key]==original[key],"破魔咒 preserves exact unrelated packed "+key)
		await cast_heal("companion");await settle("companion")
		check(impacts.any(func(p):return p["strike"].get("healing",0)>0),"second real action pays and heals after cure")
	elif mode=="stamina":
		check(Loop.unit(scene.play_loop,"tina")["stamina"]==0,"special initially lacks stamina")
		await use_item_real(250,"tina");await settle("tina");await save_restore();await moon()
		await settle("companion")
		check(Loop.unit(scene.play_loop,"tina")["stamina"]==0 and Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,"tina")),"wine funds one20ST special while silence and exhausted MP remain independent")
	elif mode=="melee":
		await use_item_real(262,"tina");await settle("tina");await attack("enemy026_1");await settle("companion")
		check(impacts.size()==4 and impacts.filter(func(p):return p["counter"]).size()==2,"temporary item bonus flows through two attacks and two counterstrikes")
	elif mode=="growth":
		await use_item_real(263,"tina");await settle("tina");await attack("enemy026_1");await settle("companion")
		check(observed.has("growth") and Loop.unit(scene.play_loop,"enemy026_1")["defeated"],"item-enhanced kill reaches actual EXP and growth allocation without ending the scenario")
		await return_to_tina();await change_gear(87,"weapon");await change_gear(232,"accessory1");await status_page("tina");await save_restore()
		await move_to(Vector2i(15,16));await cast_heal("companion");await settle("tina")
		check(observed.has("movement") and impacts.any(func(p):return p["strike"].get("healing",0)>0),"released dead target tile permits moved support after growth/equipment refresh")
	elif mode=="movement":
		await move_to(Vector2i(15,16));check(not Loop.command_available(scene.play_loop,"magic"),"ordinary moved phase still restricts casting")
		await use_item_real(263,"companion");await settle("tina");await save_restore()
		check(Loop.command_available(scene.play_loop,"magic") and not scene.play_loop["moved_this_action"],"item completes first moved action and reopens fresh stationary casting")
		await cast_heal("companion");await settle("companion")
	elif mode=="invalid":
		for code in [247,250]:
			var before:Dictionary=scene.play_loop.duplicate(true)
			await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout
			await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(code))
			var target:Button=scene.item_panel.target_buttons["tina"]
			check(target.disabled,"healthy/full recipient is visibly unavailable")
			await point(target.get_global_rect().get_center());await shot("unavailable-"+str(code))
			check(scene.play_loop==before,"disabled target click consumes no inventory, RNG or action")
			await escape();await escape();await create_timer(0.25).timeout;await escape();await settle("tina")
		await use_item_real(247,"companion");await settle("tina")
		await use_item_real(250,"companion");await settle("companion");await return_to_tina()
		check(Loop.unit(scene.play_loop,"tina")["inventory"].all(func(code):return int(code)==0),"two actual uses exhaust the two-item inventory")
		await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout;await click(scene.item_panel.menu.get_node("UseCommand"))
		check(scene.item_panel.rows.get_children().all(func(child):return not child is Button),"empty inventory offers no stale use button")
		await shot("empty-inventory");await escape();await create_timer(0.25).timeout;await escape();await settle("tina")
	elif mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		check(item_receipts.size()==1 and item_receipts[0]["item_code"]=="247","AI uses exactly one first-matching cure item")
		if mode=="ai_self":check(impacts.any(func(p):return p["strike"].get("healing",0)>0) and not Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,"tina")),"AI self-cures then rebuilds a real owned heal")
		else:check(not Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,"companion")) and scene.play_loop["item_use_sequence"]==1,"AI cures the living ally and does not duplicate the item on its second decision")
	elif mode=="paralysis":
		check(observed.has("skip") and scene.play_loop["item_use_sequence"]==0,"paralysis skip cannot pre-consume the available cure")
		await return_to_tina();await use_item_real(247,"tina");await settle("tina");await cast_heal("companion");await settle("companion")
	else:
		await use_item_real(263,"tina");await settle("tina");await save_restore()
		if mode=="escape":await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"))
		else:await attack("enemy026_1")
		await settle("",true)
	await save_restore()
	var row:Dictionary={"mode":mode,"initial_units":initial_state["units"],"initial_book":initial_state["skill_book"],"initial_ai":initial_state["ai_profiles"],"final_units":scene.play_loop["units"],"outcome":scene.play_loop["battle_outcome"],"combat_receipts":receipts.duplicate(true),"items":item_receipts.duplicate(true),"impacts":impacts.duplicate(true),"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false,"damage_rng_before":initial_state["damage_rng"],"damage_rng_after":scene.play_loop["damage_rng"]}
	if mode in ["victory","defeat","escape"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.use_item(frozen,"262")==frozen and Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen,"terminal rejects later item/RNG/tail callbacks")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["item_use_sequence"]==0 and scene.play_loop["units"].all(func(u):return (int(u["status_flags"])&0x30)==0),"actual restart resets item history and buffs to declared initial state")
		row["restarted"]=true
	routes.append(row)

func moon() -> void:
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"]=="special_select":await click(scene.magic_panel.choices[ItemCases.MOON])
	await point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop,"tina")["coord"]))
	check(scene.play_loop["last_attack"].get("skill_id")==ItemCases.MOON,"actual self-centered special was accepted")

func shot(label:String) -> void:
	var receipt:Dictionary=scene.play_loop.get("last_item_use",{}) if is_instance_valid(scene) else {}
	if not receipt.is_empty() and not item_seen.has(receipt["sequence"]):item_seen[receipt["sequence"]]=true;item_receipts.append(receipt.duplicate(true))
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png";check(root.get_texture().get_image().save_png(ITEM_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func write_receipt(filename:String) -> void:
	FileAccess.open(ITEM_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_tactical_items_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_size":root.size,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"setup":"Manual route uses the published TacticalItemsTrial. Other declared setups reuse source051 terrain and source002/023/026 roles/art, supplied kits/HP/speed/EXP99/HP1/negative states, intrinsic double/crit and AI probabilities for route determinism. No source item sampling, damage/cost or outcome is mocked. All post-setup changes use real controls including inventory target previews, equips, moves, attacks/spells, growth, save/load and restart; formal source kits/grants unchanged.","routes":routes,"frames":frames,"failures":failures,"active":{} if not is_instance_valid(scene) else {"mode":mode,"interaction":scene.play_loop.get("interaction"),"selected":scene.selected_unit_id,"scenario_error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units"),"last_item_use":scene.play_loop.get("last_item_use"),"last_combat":scene.play_loop.get("last_combat"),"last_ai_actions":scene.play_loop.get("last_ai_actions"),"observed":observed}},"  "))

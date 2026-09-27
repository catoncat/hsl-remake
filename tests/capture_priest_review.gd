extends "res://tests/capture_support_magic_review.gd"
## Real input and rendered source002. Changes below the setup boundary are only
## clicks/keys; authored initial state is captured explicitly in the receipt.
const Priest = preload("res://tests/run_support_magic_tests.gd")
const SAVE = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DEST := "res://ignored/priest-review/"
var initial_state := {}
var impacts: Array = []
var motion: Array = []
var events: Array = []
var sounds := {}
var observed := {}
var frames: Array = []
var saves := 0
var started := 0

func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Priest review needs a rendered built-in window");quit(2);return
	root.title="HSL Priest Player and Resource Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(DEST);started=Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func():check(false,"bounded priest review timeout"))
	var names:Array=["manual","healing_growth","mana_extra","phase_mobility","melee_series","ai_heal","ai_silence","ai_paralysis","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_priest();await play_priest()
		await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json");print("PRIEST_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func setup_priest()->void:
	impacts=[];motion=[];events=[];sounds={};observed={};saves=0
	scene=load("res://game/battle/development/PriestTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=DEST+mode+".save"
	if mode!="manual":
		scene.set_process(false)
		var loop:=Priest.priest_fixture()
		var actor:=Loop._unit(loop,"tina");var ally:=Loop._unit(loop,"companion");var enemy:=Loop._unit(loop,"enemy021_1")
		actor["growth_profile"]["source"]["hit_point"]+=300
		actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true);actor["hp"]=actor["max_hp"]
		ally["growth_profile"]["source"]["hit_point"]+=400
		ally.merge(Loop.ProgressionRules.refresh_growth_stats(ally,loop["equipment_items"]),true);ally["hp"]=8
		enemy["growth_profile"]["source"]["hit_point"]+=600
		enemy["growth_profile"]["source"]["defense"]+=70
		enemy.merge(Loop.ProgressionRules.refresh_growth_stats(enemy,loop["equipment_items"]),true);enemy["hp"]=enemy["max_hp"];enemy["no_attack"]=true
		actor["hit_bonus_accum"]=1000
		if mode in ["healing_growth","melee_series","victory"]:actor["exp"]=99
		if mode=="mana_extra":actor["mp"]=0
		if mode=="phase_mobility":actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,1)["changes"],true)
		if mode=="melee_series":
			enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"]=true;TestSuite.own(loop, "skill_book")["actors"]["021"]["double_attack"]=true
			enemy["coord"]=Vector2i(11,16)
		if mode.begins_with("ai_"):
			actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
			ally["live_speed"]=300;actor["live_speed"]=200
			actor["equipment"].append({"slot":"accessory2","item_code":227})
			actor["inventory"]=[241,244,0,0,0,0,0,0]
			if mode=="ai_heal":actor["mp"]=6;actor["inventory"]=[244,0,0,0,0,0,0,0]
			else:actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic" if mode=="ai_silence" else "paralysis",2)["changes"],true)
		if mode=="victory":enemy["hp"]=1;enemy["coord"]=Vector2i(11,16)
		if mode=="defeat":
			actor["hp"]=1;enemy["coord"]=Vector2i(11,16);enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000
			enemy["combat_profile"].merge({"attack_back":100,"live_attack_damage":1000},true)
		if mode=="escape":actor["coord"]=Vector2i(13,10)
		for unit in loop["units"]:
			unit["grid_coord"]=unit["coord"];unit["ai_home_coord"]=unit["coord"]
			unit["live_speed"]={"tina":200,"companion":300 if mode.begins_with("ai_") else 100,"enemy021_1":50}[unit["id"]]
		loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
		loop=Loop._return_to_player(loop,"companion" if mode.begins_with("ai_") else "tina")
		scene.apply_loop(loop, "test")
		for unit in loop["units"]:
			var art=scene.actor_node_for_unit(unit["id"])
			art.position=scene.actor_world_position_for_grid(unit["coord"])
		scene.center_camera_on_grid(actor["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	var view=scene.get_node("BattlePresentation")
	view.cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await create_timer(0.2).timeout

func settle(id:String,terminal:bool=false)->void:
	for attempt in range(2400):
		var view=scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream!=null and sound.get_playback_position()>0:sounds[sound.stream.resource_path]=true
		if scene.has_actor_motion():observed["movement"]=true
		if view.cutin.busy():
			check(not scene.action_menu.visible,"combat presentation closes player controls")
			var clip:Dictionary=view.cutin.clips[0]
			if clip["attacker"]=="002" and not clip["strike"].has("skill_name") and not clip["strike"].has("magic_key"):
				var y:float=view.cutin.attacker_sprite.position.y
				if y<270 and not observed.has("jump"):
					observed["jump"]=true;motion.append({"elapsed":view.cutin.elapsed,"position":view.cutin.attacker_sprite.position});await shot("jump")
			if clip["impact_emitted"]:
				var token:="impact-"+str(impacts.size())
				if not observed.has(token):observed[token]=true;await shot(token)
		if view.item_feedback_busy():
			check(not scene.action_menu.visible,"use-item feedback finishes before next controls")
			var token:="item-"+str(scene.play_loop["last_item_use"]["sequence"])
			if not observed.has(token):
				observed[token]=true;events.append(scene.play_loop["last_item_use"].duplicate(true));await shot(token)
		if view.turn_end_cue.showing():
			var token:="tail-%s-%s"%[scene.play_loop["action_end_sequence"],view.turn_end_cue.cursor]
			if not observed.has(token):observed[token]=true;events.append(scene.play_loop["last_action_end"].duplicate(true));await shot(token)
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺") and not observed.has("skip"):
			observed["skip"]=true;await shot("skip")
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var name:String=["str","dex","mind","con"][i%4]
				if not scene.growth_panel.choices[name]["plus"].disabled:await click(scene.growth_panel.choices[name]["plus"])
			await shot("growth");await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(scene.play_loop["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual action reaches configured priest terminal")
			await shot("result");return
		if mode=="manual" and view.battle_finished:
			check(impacts.any(func(r):return r["strike"].get("healing",0)>0),"manual source heal completed before the authored scenario outcome")
			await shot("result");return
		if not terminal and scene.selected_unit_id==id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(scene.play_loop["action_end_sequence"]));return
		check(scene.play_loop["scenario_ok"],"live scenario remains valid: "+str(scene.play_loop.get("scenario_error","")))
		await create_timer(0.02).timeout
	check(false,"bounded priest playback did not reach "+id)

func play_priest()->void:
	await settle("companion" if mode.begins_with("ai_") else "tina")
	if mode=="manual":
		check(Loop.unit(scene.play_loop,"tina")["actor_id"]=="002","unmodified published scene selects source002")
		await shot("entry");await cast_heal("companion");await settle("tina")
		check(impacts.any(func(r):return r["strike"].get("healing",0)>0),"published priest uses actual initial healing spell")
	elif mode in ["healing_growth","mana_extra","phase_mobility","melee_series"]:
		await change_gear(227,"accessory2")
		if mode=="healing_growth":
			await cast_heal("companion");await settle("tina")
			check(observed.has("growth") and scene.play_loop["extra_action"]["pending"],"support EXP and priest allocation finish before second action")
			await save_restore();await change_gear(87,"weapon");await attack("enemy021_1");await settle("companion")
		elif mode=="mana_extra":
			await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[Priest.HEAL].disabled,"empty MP disables actual source heal")
			await escape();await settle("tina");await use_item_real(244,"tina");await settle("tina")
			check(scene.play_loop["extra_action"]["pending"] and Loop.unit(scene.play_loop,"tina")["mp"]==19,"actual mana potion restores once before independent second action")
			await save_restore();await cast_heal("companion");await settle("companion")
			check(Loop.unit(scene.play_loop,"tina")["mp"]==13,"next actual heal uses newly restored MP")
		elif mode=="phase_mobility":
			await change_gear(232,"accessory1")
			var before:Dictionary=scene.play_loop.duplicate(true)
			await move_to(Vector2i(11,16));await click(scene.action_menu.get_node("MagicCommand"));await escape();await settle("tina")
			await escape();await create_timer(0.3).timeout;await escape();await settle("tina")
			check(scene.play_loop["units"]==before["units"] and not scene.play_loop["moved_this_action"],"cancel restores only accepted movement and phase")
			await move_to(Vector2i(11,16));await cast_heal("companion");await settle("tina");await save_restore()
			await change_gear(0,"accessory1");await move_to(Vector2i(10,16))
			check(not Loop.command_available(scene.play_loop,"magic"),"current equipment removal revokes moved casting in second action")
			await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
			check(scene.play_loop["action_end_sequence"]==1 and int(Loop.unit(scene.play_loop,"tina")["status_counters"]["poison"])&0xffff==2,"poison ticks only after the accepted final action")
		else:
			await attack("enemy021_1");await settle("tina");await save_restore()
			await attack("enemy021_1");await settle("companion")
			check(observed.has("jump") and impacts.size()==8,"two independent main/counter double series play actual priest jump poses")
		check(not scene.play_loop["extra_action"]["pending"] and scene.play_loop["action_end_sequence"]==1,"accepted pair closes exactly one owner tail")
	elif mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand"));await settle("companion")
		var actions:Array=scene.play_loop["last_ai_actions"].filter(func(a):return a.get("actor_id")=="tina")
		check(not actions.is_empty(),"source priest AI entered through the live queue")
		if mode=="ai_heal":
			check(actions.size()==2 and actions[0].get("skill_id")==Priest.HEAL and not actions[1].has("skill_id"),"AI pays one heal then freshly falls back after MP exhaustion")
		elif mode=="ai_silence":check(actions.all(func(a):return not a.has("skill_id")) and events.any(func(e):return e.get("item_code")=="241"),"silenced priest can use actual medicine while spells remain blocked")
		else:check(actions.size()==1 and actions[0]["kind"]=="paralysis_skip" and observed.has("skip"),"paralysis skips one priest turn without an extra-action replay")
	else:
		if mode=="escape":
			await change_gear(227,"accessory2");await click(scene.action_menu.get_node("WaitCommand"));await settle("tina");await save_restore()
			await move_to(Vector2i(14,10));await click(scene.action_menu.get_node("WaitCommand"))
		else:await attack("enemy021_1")
		await settle("",true)
	await save_restore()
	var row:={"mode":mode,"initial_units":initial_state["units"],"initial_skills":initial_state["skill_book"]["actors"]["002"],
		"final_units":scene.play_loop["units"],"outcome":scene.play_loop["battle_outcome"],"impacts":impacts.duplicate(true),"motion":motion.duplicate(true),
		"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen,"terminal cannot execute more actions or resources")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["player_unit_id"]=="tina" and scene.play_loop["action_end_sequence"]<3,"real restart retains configured priest without old outcome or extra action")
		row["restarted"]=true
	routes.append(row)

func change_gear(code:int,slot:String)->void:
	await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout;await click(scene.item_panel.menu.get_node("EquipCommand"))
	if code==0:await click(scene.item_panel.equipment_view.slot_controls[slot])
	else:
		await click(item_button(code))
		if slot.begins_with("accessory"):await click(button_text("飾品 "+slot.right(1)))
	check(not scene.item_panel.confirm_button.disabled,"actual priest job accepts source equipment")
	await shot("equipment-"+str(code));await click(scene.item_panel.confirm_button);await settle("tina")

func item_button(code:int)->Control:
	for child in scene.item_panel.page_root.find_children("*","Button",true,false):
		if child.get_meta("item_code","")==str(code):return child
	check(false,"requested source item missing: "+str(code));return null

func button_text(text:String)->Control:
	for child in scene.item_panel.page_root.find_children("*","Button",true,false):
		if child.text==text:return child
	check(false,"control missing: "+text);return null

func move_to(coord:Vector2i)->void:
	await click(scene.action_menu.get_node("MoveCommand"));await hover(scene.grid_cell_center_to_logical_position(coord));await shot("move-preview")
	check(Loop.movement_cells(scene.play_loop).has(coord),"actual source terrain permits selected movement")
	await point(scene.grid_cell_center_to_logical_position(coord));await settle("tina")

func cast_heal(target:String)->void:
	await click(scene.action_menu.get_node("MagicCommand"));await click(scene.magic_panel.choices[Priest.HEAL])
	await point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop,target)["coord"]))
	check(scene.play_loop["last_attack"].get("skill_id")==Priest.HEAL,"real target selection accepts source healing")

func attack(target:String)->void:
	await click(scene.action_menu.get_node("AttackCommand"));var coord:Vector2i=Loop.unit(scene.play_loop,target)["coord"]
	await hover(scene.grid_cell_center_to_logical_position(coord));await shot("attack-target")
	await point(scene.grid_cell_center_to_logical_position(coord))
	check(scene.play_loop["last_attack"].get("defender_id")==target,"real ordinary attack accepts target")

func use_item_real(code:int,target:String)->void:
	await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.25).timeout;await click(scene.item_panel.menu.get_node("UseCommand"))
	await click(item_button(code));await click(scene.item_panel.target_buttons[target])

func key(code:int)->void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true;root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true);await create_timer(0.15).timeout

func save_restore()->void:
	var before:Dictionary=scene.play_loop.duplicate(true);await key(KEY_F5)
	var saved:=SAVE.read(scene.settlement_controller.checkpoint_path, before)
	check(saved["ok"] and saved["snapshot"]["loop"]==before,"F5 writes complete non-Leonard state")
	await key(KEY_F9);check(scene.play_loop==before,"F9 restores state without replay or identity substitution")
	saves+=1;await shot("restored-"+str(saves))

func shot(label:String)->void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png";check(root.get_texture().get_image().save_png(DEST+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func write_receipt(filename:String)->void:
	FileAccess.open(DEST+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_priest_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_size":root.size,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"setup":"Manual route uses published PriestTrial unchanged. Other routes use original051 terrain/art and source002 job85/equipment/heal. Authored initial HP additions, fixed speeds, player/AI roles, exp99, status duration, lethal HP1/counter1000, hit compensation1000 and double_attack source overrides are visible in initial_units/initial_skills. AI uses source rates and spell probabilities. No terrain, combat RNG, healing result, costs, effects or queue advancement are changed after setup. Healing costs6; mana item244 restores30 capped. Added supplied equipment and wounded companion are developer trial settings, not formal053 parity.","routes":routes,"frames":frames,"failures":failures,
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"scenario_error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units",[]),"last_attack":scene.play_loop.get("last_attack",{}),"last_ai_actions":scene.play_loop.get("last_ai_actions",[])}},"  "))

func check(ok:bool,label:String)->void:
	if ok:return
	failures.append(mode+": "+label);push_error(mode+": "+label);write_receipt("failed.json");quit(1)

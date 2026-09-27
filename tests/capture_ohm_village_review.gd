extends "res://tests/capture_growth_lifecycle_review.gd"
## Source level001 and explicit setup-only encounter variants, driven by inputs.
## Runtime/PlayLoop perform all subsequent actions; no injected effect or RNG.
const Ohm = preload("res://tests/run_ohm_village_tests.gd")
const Arrow = preload("res://game/sim/PoisonArrowRules.gd")
const VillageScene = preload("res://game/battle/development/OhmVillage.tscn")
const OHM_OUT := "res://ignored/ohm-village-review/"
var arrow_signals := [0,0]
var opening_messages: Array = []
var arrow_receipt: Dictionary = {}
var player_decisions: Array = []

func _initialize() -> void:
	# All review saves/settings live outside the player's persistent campaign.
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","HSL-Review-Ohm-"+str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Ohm review needs a rendered window");quit(2);return
	root.title="HSL Ohm Village Gameplay Review"
	root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(OHM_OUT)
	started=Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func():check(false,"bounded Ohm render timeout"))
	var names: Array = ["opening"] if OS.get_cmdline_user_args().is_empty() else Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name
		await setup_ohm()
		await play_ohm()
		await close_scene()
		write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("OHM_VILLAGE_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size()," checks=",check_count)
	quit(0 if failures.is_empty() else 1)

func setup_ohm() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0
	learning_texts=[];ai_receipts=[];recorded_ai={};arrow_signals=[0,0];opening_messages=[];arrow_receipt={};player_decisions=[]
	Campaign.pending={};Campaign.last_entry={};owner_id="hu"
	scene=VillageScene.instantiate()
	if mode not in ["opening","natural"]:scene.startup_mode="dev_first_control"
	root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=OHM_OUT+mode+".save"
	check(scene.play_loop["scenario_ok"],"actual Ohm scene loads: "+str(scene.play_loop.get("scenario_error")))
	if mode not in ["opening","natural"]:
		scene.set_process(false)
		var loop: Dictionary = Ohm.fixture()
		if mode in ["insert61","insert62"]:
			var sample:=Ohm.insertion_fixture("061" if mode=="insert61" else "062")
			loop=sample["loop"]
			scene.first_battle_scenario=sample["scenario"]
		if mode=="double":
			Loop._unit(loop,"hu")["inventory"]=[69,227,0,0,0,0,0,0]
			Loop._unit(loop,"actor028_1")["coord"]=Vector2i(15,22)
			Loop._unit(loop,"actor028_1")["ai_home_coord"]=Vector2i(15,22)
		Loop._unit(loop,"hu")["hit_bonus_accum"]=1000
		if mode=="silence":Loop._unit(loop,"hu").merge(Loop.StatusEffectRules.apply(Loop.unit(loop,"hu"),"no_magic",3)["changes"],true)
		if mode=="limited":Loop._unit(loop,"hu")["stamina"]=19
		if mode=="mixed":Loop._unit(loop,"actor028_2")["hp"]=1
		if mode=="clear":
			# Terminal preconditions only; the last action and source win0 are real.
			for actor in loop["units"]:
				if actor["battle_actor_role"]==Loop.ROLE_ENEMY:
					actor["hp"]=1 if actor["id"] in ["actor028_1","actor028_2"] else 0
					actor["defeated"]=actor["hp"]==0
		if mode=="retreat":
			for id in ["actor028_5","actor028_6"]:
				Loop._unit(loop,id)["hp"]=0;Loop._unit(loop,id)["defeated"]=true
			Loop._unit(loop,"actor028_1")["hp"]=1
		if mode=="defeat":
			var hero:=Loop._unit(loop,"leonard")
			hero["growth_profile"]["source"]["speed"]+=290
			hero.merge(Loop.ProgressionRules.refresh_growth_stats(hero,loop["equipment_items"]),true)
			hero["hp"]=1;hero["hit_bonus_accum"]=1000
			var enemy:=Loop._unit(loop,"actor028_1")
			enemy["coord"]=Vector2i(17,19);enemy["ai_home_coord"]=enemy["coord"]
			enemy["growth_profile"]["source"].merge({"attack_power":5000,"attack_back":100},true)
			enemy.merge(Loop.ProgressionRules.refresh_growth_stats(enemy,loop["equipment_items"]),true);enemy["hit_bonus_accum"]=1000
		if mode=="villagers":
			for actor in loop["units"]:
				if actor["actor_id"] in ["061","062"]:
					actor["hp"]=0;actor["defeated"]=true
			var last:=Loop._unit(loop,"actor061_1")
			last["hp"]=1;last["defeated"]=false;last["coord"]=Vector2i(18,22)
			var enemy:=Loop._unit(loop,"actor028_1")
			enemy["coord"]=Vector2i(18,23);enemy["ai_home_coord"]=enemy["coord"]
			enemy["growth_profile"]["source"].merge({"attack_power":5000,"speed":280},true)
			enemy.merge(Loop.ProgressionRules.refresh_growth_stats(enemy,loop["equipment_items"]),true);enemy["hit_bonus_accum"]=1000
		loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
		loop=Loop._return_to_player(loop,"hu")
		if mode in ["ai_current","ai_paralysis"]:
			loop=Ohm.ai_fixture(mode=="ai_paralysis")
			owner_id="leonard"
		scene.apply_loop(loop, "test")
		for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear()
		scene.resume_turn_presentation()
		scene.center_camera_on_grid(Loop.unit(loop,"hu")["coord"])
		scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	var view=scene.get_node("BattlePresentation")
	view.cutin.released.connect(arrow_release)
	view.cutin.impact.connect(arrow_impact)
	await settle("" if mode in ["opening","natural"] else owner_id)

func settle(id:String,terminal:bool=false) -> void:
	# Natural play may finish during an enemy response. Keep the same presentation
	# barriers as the shared review, but allow either ready input or a real terminal.
	if mode not in ["natural","campaign1"]:
		await super.settle(id,terminal)
		return
	for attempt in range(6000):
		check(scene.play_loop["scenario_ok"],"natural source battle remains valid: "+str(scene.play_loop.get("scenario_error")))
		var view=scene.get_node("BattlePresentation")
		var latest:Dictionary=scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):
			receipt_sequences[latest["sequence"]]=true;receipts.append(latest.duplicate(true))
		for action in scene.play_loop.get("last_ai_actions",[]):
			var identity:=str(action.get("actor_id",""))+":"+str(action.get("sequence",str(scene.play_loop["turn"])+str(action)))
			if not recorded_ai.has(identity):recorded_ai[identity]=true;ai_receipts.append(action.duplicate(true))
		for audio in scene.find_children("*","AudioStreamPlayer",true,false):
			if audio.playing and audio.stream!=null and audio.get_playback_position()>0:sounds[audio.stream.resource_path]=true
		if view.cutin.busy():
			check(not scene.action_menu.visible and not scene.growth_panel.visible and not view.battle_finished,"natural attack finishes before growth or next controls")
			var tag:="clip-"+str(receipts.size())
			if not observed.has(tag):observed[tag]=true;await shot(tag)
		if view.aftermath.reward_label.visible:
			check(not scene.action_menu.visible and not view.battle_finished,"natural committed EXP precedes next action/result")
			var label:String=view.aftermath.reward_label.text
			if label.begins_with("習得") and not learning_texts.has(label):learning_texts.append(label);await shot("learn-"+str(learning_texts.size()))
		if view.dialogue_active():await key(KEY_SPACE)
		if scene.opening_coordinator!=null and scene.opening_coordinator.active and scene.scene_timeline.current_event().get("kind")=="dialogue_message_id":await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			var panel=scene.growth_panel
			if int(panel.source_unit["pending_stat_points"])>0:
				for i in range(int(panel.source_unit["pending_stat_points"])):
					var stat:String=["str","dex","mind","con"][i%4]
					if panel.choices[stat]["plus"].disabled:stat="con"
					await click(panel.choices[stat]["plus"])
				await shot("allocation");await click(panel.confirm_button)
			else:await escape()
		if view.battle_finished:
			await shot("result");return
		if scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.growth_panel.visible and not scene.ScriptPresentation.pending(scene):return
		if attempt==3000:write_receipt("waiting.json")
		await create_timer(0.02).timeout
	check(false,"natural playback exceeded bounded wait")

func _process(_delta:float) -> bool:
	if not is_instance_valid(scene):return false
	if scene.opening_coordinator!=null and scene.opening_coordinator.active:
		var event:Dictionary=scene.scene_timeline.current_event()
		if event.get("kind")=="dialogue_message_id" and not opening_messages.has(event.get("id")):
			opening_messages.append(event.get("id"))
	return false

func arrow_release(strike:Dictionary,_actor:Dictionary,_target:Dictionary,_counter:bool) -> void:
	if strike.get("skill_id")!=Arrow.ID:return
	arrow_signals[0]+=1
	await shot("arrow-release-"+str(arrow_signals[0]))

func arrow_impact(strike:Dictionary,actor:Dictionary,target:Dictionary,counter:bool) -> void:
	impacts.append({"strike":strike.duplicate(true),"attacker":actor["id"],"defender":target["id"],"counter":counter})
	if strike.get("skill_id")!=Arrow.ID:return
	arrow_signals[1]+=1
	check(not scene.action_menu.visible and not scene.growth_panel.visible,"poison impact occurs before successor input and growth")
	await create_timer(0.25).timeout
	await shot("arrow-impact-"+str(arrow_signals[1]))

func cast_arrow(center:Vector2i) -> void:
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"]=="special_select":await click(scene.magic_panel.choices[Arrow.ID])
	check(scene.play_loop["interaction"]=="attack_select" and scene.play_loop["selected_skill_id"]==Arrow.ID,"actual Hu special selects his original ability")
	await hover(scene.grid_cell_center_to_logical_position(center))
	await shot("arrow-targets")
	await point(scene.grid_cell_center_to_logical_position(center))
	check(scene.play_loop.get("last_attack",{}).get("skill_id")==Arrow.ID,"real control commits Poison Arrow")
	arrow_receipt=scene.play_loop["last_attack"].duplicate(true)
	await create_timer(0.35).timeout
	await shot("arrow-source-panels")

func save_restore() -> void:
	var before:Dictionary=scene.play_loop.duplicate(true)
	await key(KEY_F5)
	var stored:=Ohm.Save.read(scene.settlement_controller.checkpoint_path, before)
	check(stored["ok"] and stored["snapshot"]["loop"]==before,"real Ohm F5 stores exact source/growth/action state")
	await key(KEY_F9)
	check(scene.play_loop==before,"real Ohm F9 does not reroll, relearn, pay or settle again")
	saves+=1
	await shot("restored-"+str(saves))

func play_ohm() -> void:
	await save_restore()
	if mode=="natural":
		await play_natural()
	elif mode in ["ai_current","ai_paralysis"]:
		await click(scene.action_menu.get_node("WaitCommand"))
		await settle("leonard")
		# One player Wait starts this complete AI interval. Its authoritative ledger
		# survives the round wrap; the generic frame collector can observe a skip
		# without a combat sequence twice under two round numbers.
		ai_receipts=scene.play_loop["last_ai_actions"].duplicate(true)
		var actions:Array=ai_receipts.filter(func(a):return a.get("actor_id")=="hu")
		if mode=="ai_current":
			check(actions.size()==2 and actions[0].get("skill_id")==Arrow.ID and actions[1].get("skill_id")!=Arrow.ID,"real AI plays its owned special then replans its resource-depleted second action")
			check(arrow_signals==[1,1],"AI special has one rendered release and impact, not one per independent action")
		else:
			check(actions.size()==1 and actions[0].get("kind")=="paralysis_skip" and arrow_signals==[0,0],"paralyzed AI skips once without invisible special payment or a White Wings repeat")
			check(not Loop.StatusEffectRules.paralyzed(Loop.unit(scene.play_loop,"hu")),"paralysis release is visible before next player control")
		await save_restore()
	elif mode in ["insert61","insert62","double"]:
		await play_extended()
	elif mode=="opening":
		check(opening_messages.size()>=29,"full source opening messages reach actual player control")
		check(scene.play_loop["units"].size()==18 and scene.play_loop.has("initial_roster_growth"),"two players and sixteen NPCs exist in one grown battle state")
		await status_page(str(scene.selected_unit_id))
		await click(scene.action_menu.get_node("MoveCommand"))
		check(scene.move_overlay_cells.size()>1,"formal entry has usable source movement")
		await shot("formal-move-range")
		await key(KEY_ESCAPE)
		await settle("")
		await save_restore()
	elif mode=="limited":
		check(Loop.command_available(scene.play_loop,"special") and not Loop.can_use_special(scene.play_loop,"hu"),"nineteen stamina opens the skill page but cannot pay the twenty-stamina special")
		await shot("insufficient-stamina")
		await change_gear(0,"weapon")
		check(Loop.unit(scene.play_loop,"hu")["weapon_code"]==0 and not Loop.command_available(scene.play_loop,"attack"),"actual bow removal does not invent a melee range")
		await change_gear(61,"weapon")
		await save_restore()
	elif mode in ["defeat","villagers"]:
		await click(scene.action_menu.get_node("WaitCommand"))
		if mode=="defeat":
			await settle("leonard")
			await attack("actor028_1")
		await settle("",true)
		check(BattleOutcome.lost(scene.play_loop),"actual lethal action reaches source defeat")
		check(scene.play_loop["winfail_runtime"]["resolved"]["key"]==("fail_0" if mode=="defeat" else "fail_1"),"source hero/villager defeat branches stay distinct")
		await save_restore()
	else:
		if mode=="silence":
			var actor:=Loop.unit(scene.play_loop,"hu")
			var choices:Array=Loop.movement_cells(scene.play_loop).filter(func(c):return c!=actor["coord"] and Loop.SkillTargetRules.cells(c,Loop.skill_fields(scene.play_loop,Arrow.ID),scene.play_loop["skill_target_data"],scene.play_loop["map_size"]).has(Vector2i(15,21)))
			choices.sort_custom(func(a,b):return a.distance_squared_to(actor["coord"])<b.distance_squared_to(actor["coord"]))
			check(not choices.is_empty(),"actual map offers a legal moved special location")
			await move_to(choices[0])
		var before:Dictionary=scene.play_loop.duplicate(true)
		await cast_arrow(Vector2i(15,21))
		await settle("",mode in ["retreat","clear"])
		var special:Dictionary=arrow_receipt
		check(arrow_signals==[1,1] and special.get("skill_id")==Arrow.ID,"one cast produces exactly one release and impact")
		check(Loop.unit(before,"hu")["stamina"]-int(special["resource_payment"]["after"])==20,"real multi-target special pays twenty stamina once")
		check(special["affected_targets"].size()==2,"real range reaches two distinct actors")
		if mode=="mixed":check(special["affected_targets"].any(func(r):return r["defender_hp_after"]==0) and special["affected_targets"].any(func(r):return r["defender_hp_after"]>0),"one arrow cast mixes lethal and nonlethal results")
		if mode=="retreat":check(scene.play_loop["winfail_runtime"]["resolved"]["key"]=="win_1","actual kill triggers the source enemy retreat, not a fabricated player escape")
		if mode=="clear":check(scene.play_loop["winfail_runtime"]["resolved"]["key"]=="win_0","real final area action reaches source all-enemy clear before retreat")
		await save_restore()
	var row:Dictionary={"mode":mode,"initial_units":initial_state["units"],"final_units":scene.play_loop["units"].duplicate(true),"outcome":scene.play_loop["battle_outcome"],"opening_messages":opening_messages.duplicate(),"receipts":receipts.duplicate(true),"impacts":impacts.duplicate(true),"ai_actions":ai_receipts.duplicate(true),"learning_texts":learning_texts.duplicate(),"sounds":sounds.keys(),"saves":saves,"arrow_signals":arrow_signals.duplicate(),"arrow_receipt":arrow_receipt.duplicate(true),"decisions":player_decisions.duplicate(true),"restarted":false}
	if mode in ["retreat","clear","defeat","villagers","natural"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen,"terminal cannot execute late growth, poison or another action")
		reload_current_scene()
		await create_timer(0.5).timeout
		scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.scenario_path==Ohm.SCENE,"actual restart returns to the formal Ohm scenario")
		row["restarted"]=true
	routes.append(row)

func play_extended() -> void:
	if mode=="double":
		await change_gear(69,"weapon")
		await change_gear(227,"accessory2")
		check(Loop.attack_count(scene.play_loop,Loop.unit(scene.play_loop,"hu"))["count"]==2,"actual UI equip reads native double_attack")
	var before:Dictionary=scene.play_loop.duplicate(true)
	await attack("actor028_1")
	var combat:Dictionary=scene.play_loop["last_combat"].duplicate(true)
	await settle("hu")
	check(scene.play_loop["extra_action"]["pending"] and not scene.play_loop["moved_this_action"],"complete ordinary sequence gives one independent fresh second action")
	if mode=="double":
		var strikes:Array=Loop.CombatSequence.strikes(combat).filter(func(s):return not s.get("is_counter",false))
		check(strikes.size()==2 and strikes[0]["defender_hp_after"]>0 and strikes[1]["defender_hp_after"]>0,"rendered double bow performs two nonlethal strikes within one action")
	else:
		check(scene.play_loop["units"].size()==19,"first actual attack creates exactly one scripted villager")
		var born:Dictionary=scene.play_loop["units"].back()
		check(born["entry_growth"]["input"]["parameters"]==[20,3],"new villager uses the actual script adjustment and continued stream")
		check(born["battle_actor_role"]==Loop.ROLE_FRIENDLY and not born["player_commandable"] and born["level"]>1,"script inserted friendly remains noncommandable with real adjusted level")
		check(Loop.unit(scene.play_loop,"hu")["status_counters"]["poison"]==Loop.unit(before,"hu")["status_counters"]["poison"],"first independent action does not execute poison tail")
		await inspect_villager(born["id"])
	await save_restore()
	await cast_arrow(Vector2i(15,21))
	await settle("")
	check(arrow_receipt["resource_payment"]["amount"]==20 and arrow_signals==[1,1],"second independent action is exactly one Poison Arrow, never one per ordinary strike")
	if mode!="double":
		check(scene.play_loop["units"].size()==20,"rearmed event continues the stream into a second distinct villager")
		check(Loop.ReinforcementGrowth.state_error(scene.play_loop)=="","both births remain consistent after actual combat, growth, status tail and AI")
		await inspect_villager(scene.play_loop["units"].back()["id"])
	await save_restore()

func inspect_villager(id:String) -> void:
	var actor:=Loop.unit(scene.play_loop,id)
	scene.center_camera_on_grid(actor["coord"])
	await hover(scene.grid_cell_center_to_logical_position(actor["coord"]))
	await point(scene.grid_cell_center_to_logical_position(actor["coord"]))
	check(scene.status_panel.visible and scene.status_panel.permanent_summary.text.contains("入場成長"),"real map selection inspects adjusted friendly stats without issuing commands")
	check(scene.status_panel.stat_values["attack"].text==str(actor["combat_profile"]["live_attack_damage"]),"villager status reflects one current derived state")
	await shot("villager-stats-"+str(scene.play_loop["units"].size()))
	await escape();await settle("")

func play_natural() -> void:
	for action_index in range(120):
		if BattleOutcome.decided(scene.play_loop):break
		var loop:Dictionary=scene.play_loop
		var actor:=Loop.unit(loop,scene.selected_unit_id)
		var foes:Array=loop["units"].filter(func(a):return a["battle_actor_role"]==Loop.ROLE_ENEMY and Loop.Presence.living(a))
		var decision:Dictionary={"actor":actor["id"],"turn":loop["turn"],"coord":actor["coord"],"hp":actor["hp"],"stamina":actor["stamina"]}
		player_decisions.append(decision)
		if int(actor["hp"])*2<int(actor["max_hp"]) and actor["inventory"].has(241):
			decision["kind"]="heal_item"
			await use_item_real(241,actor["id"])
			await settle("");continue
		if actor["id"]=="hu" and Loop.command_available(loop,"special") and Loop.can_use_special(loop,"hu"):
			var fields:=Loop.skill_fields(loop,Arrow.ID)
			var centers:=Loop.SkillTargetRules.candidate_centers(actor,loop["units"],fields,loop["skill_target_data"],loop["map_size"],actor["coord"])
			var selectable:=Loop.SkillTargetRules.cells(actor["coord"],fields,loop["skill_target_data"],loop["map_size"])
			centers=centers.filter(func(c):return selectable.has(c))
			if not centers.is_empty():
				decision["kind"]="poison_arrow";decision["center"]=centers[0]
				await cast_arrow(centers[0]);await settle("");continue
		var reachable:Array=foes.filter(func(a):return Loop.Footprint.contact(a,Loop.attack_cells(loop)) is Vector2i)
		if not reachable.is_empty():
			reachable.sort_custom(func(a,b):return int(a["hp"])<int(b["hp"]))
			decision["kind"]="ordinary";decision["target"]=reachable[0]["id"]
			await attack(reachable[0]["id"]);await settle("");continue
		if not loop["moved_this_action"]:
			var pattern:=Loop.weapon_pattern(loop,actor)
			var best:Vector2i=actor["coord"]
			var best_score:=1000000
			for cell in Loop.movement_cells(loop):
				if cell==actor["coord"]:continue
				var score:=1000000
				for foe in foes:
					var delta:Vector2i=foe["coord"]-cell
					var distance:int=absi(delta.x)+absi(delta.y)
					var can_hit:bool=pattern["offsets"].any(func(o):return Vector2i(int(o[0]),int(o[1]))==delta)
					score=mini(score,(0 if can_hit else 1000)+distance*10+int(foe["hp"])/20)
				if score<best_score:best_score=score;best=cell
			if best!=actor["coord"]:
				decision["kind"]="move";decision["to"]=best
				await move_to(best);continue
		decision["kind"]="wait"
		await click(scene.action_menu.get_node("WaitCommand"));await settle("")
		if action_index%8==0 and not BattleOutcome.decided(scene.play_loop):await save_restore()
	check(BattleOutcome.decided(scene.play_loop),"unmodified source roster reaches a real outcome through bounded ordinary inputs")
	await save_restore()

func shot(label:String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(OHM_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func write_receipt(filename:String) -> void:
	var record := {"schema":"hsl_ohm_village_review.v1","native_execution":false,"real_control_events":true,
		"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,
		"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"isolated_user_dir":OS.get_user_data_dir(),
		"setup":"Opening and natural use the unmodified formal source level001. Other modes set fast Hu/40ST,enemy durability/position/hit compensation before input. Limited19ST, silence, mixed1HP or terminal preconditions are explicit variants. Insert61/62 use added test event901 (not in source001),party12,near-threshold EXP,poison and White Wings; double supplies real69/227 in test inventory and equips through UI. AI routes explicitly assign friendly AI control/strategy to source003, twenty ST and White Wings, with silence or last-turn paralysis; this is not a native003 AI-default claim. No post-input effect/RNG/state injection or changed formal grants.",
		"routes":routes,"frames":frames,"checks":check_count,"failures":failures,
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,
			"interaction":scene.play_loop.get("interaction"),"scenario_error":scene.play_loop.get("scenario_error"),
			"units":scene.play_loop.get("units",[]),"last_combat":scene.play_loop.get("last_combat",{}),"opening_messages":opening_messages}}
	FileAccess.open(OHM_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify(record,"  "))

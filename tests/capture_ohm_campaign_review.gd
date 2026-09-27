extends "res://tests/capture_ohm_village_review.gd"
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
## Real next-battle buttons and scene reloads. Only setup is synthetic: an incoming
## Leonard party at level7/345 gold and Tina just outside her source escape zone.
## Set an isolated user directory before any Runtime/settings/campaign creation.
var incoming_party:Dictionary={}
var chain_records:Array=[]

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","HSL-Review-Ohm-"+str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Campaign review needs a rendered window");quit(2);return
	root.title="HSL Ohm Campaign Handoff Review"
	root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(OHM_OUT)
	started=Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func():check(false,"bounded campaign route timeout"))
	mode="campaign53";owner_id="tina"
	var preceding:=BattlePlayLoop.initialize_roster_growth(BattleFixture.loop())
	var leader:=BattlePlayLoop._unit(preceding,"leonard")
	var steps:int=7-int(leader["level"])
	var experience:=0
	for level in range(int(leader["level"]),7):experience+=BattlePlayLoop.ProgressionRules.exp_to_next(level)
	leader.merge(BattlePlayLoop.ProgressionRules.resolve_experience(leader,experience,preceding["equipment_items"]),true)
	leader.merge(BattlePlayLoop.ProgressionRules.apply_allocation(leader,{"str":2*steps,"dex":steps,"mind":steps,"con":steps},preceding["equipment_items"]),true)
	leader["permanent_gains"]["defense"]=3
	leader.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(leader,preceding["equipment_items"]),true)
	preceding["gold"]=345
	incoming_party=BattlePlayLoop.CampaignCarryRules.capture(preceding)
	CampaignProgress.last_entry={}
	CampaignProgress.pending={"schema":CampaignProgress.SCHEMA,"scenario_path":"res://content/battles/battle_053.json","carry":incoming_party.duplicate(true),"from_scenario_id":"ohm_carry_review_setup"}
	scene=VillageScene.instantiate();scene.startup_mode="dev_first_control"
	root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=OHM_OUT+mode+".save"
	check(scene.play_loop["scenario_ok"] and scene.scenario_path.ends_with("battle_053.json"),"actual Runtime consumes the third-battle handoff")
	scene.set_process(false)
	var tina:=BattlePlayLoop._unit(scene.play_loop,"tina")
	tina["coord"]=Vector2i(29,35);tina["grid_coord"]=tina["coord"];tina["ai_home_coord"]=tina["coord"]
	tina["growth_profile"]["source"]["speed"]+=500
	tina.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(tina,scene.play_loop["equipment_items"]),true)
	scene.play_loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(BattlePlayLoop._return_to_player(scene.play_loop,"tina"), "test")
	for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(tina["coord"])
	scene.set_process(true)
	await settle("tina")
	await save_restore()
	await move_to(Vector2i(30,35))
	await click(scene.action_menu.get_node("WaitCommand"))
	await settle("",true)
	check(scene.play_loop["battle_outcome"]==BattleOutcome.VICTORY_ESCAPE,"real step and wait reaches source053 escape")
	var from53:Dictionary=scene.play_loop.duplicate(true)
	chain_records.append({"stage":"escaped53","rng":from53[GlobalRandomStream.LOOP_KEY],"outcome":from53["battle_outcome"]})
	await save_restore()
	await create_timer(0.1).timeout
	await next_scene(run_ohm_village_tests.SCENE)
	mode="campaign1";owner_id="hu"
	scene.settlement_controller.checkpoint_path=OHM_OUT+mode+".save"
	receipts=[];receipt_sequences={};recorded_ai={};ai_receipts=[];observed={};opening_messages=[]
	await settle("")
	check(scene.play_loop["units"].size()==18 and not BattlePlayLoop.unit(scene.play_loop,"hu").is_empty(),"53 next button enters the full Ohm battle, not a preview card")
	check(BattlePlayLoop.unit(scene.play_loop,"tina").is_empty() and BattlePlayLoop.unit(scene.play_loop,"leonard")["level"]==7 and scene.play_loop["gold"]==345,"separate Tina party neither overwrites nor replaces returning Leonard party")
	check(BattlePlayLoop.unit(scene.play_loop,"leonard")["permanent_gains"]["defense"]==3,"permanent growth survives actual scene reload separately from new NPC birth")
	chain_records.append({"stage":"ohm_entry","carried":scene.play_loop["initial_roster_growth"]["carried"],"units":scene.play_loop["units"].duplicate(true)})
	await save_restore()
	await play_natural()
	var finished:Dictionary=scene.play_loop.duplicate(true)
	check(BattleOutcome.won(finished),"carried party completes a real Ohm battle before returning to world map")
	var expected_carry:=BattlePlayLoop.CampaignCarryRules.capture(finished)
	chain_records.append({"stage":"ohm_won","outcome":finished["battle_outcome"],"resolved":finished["winfail_runtime"]["resolved"],"carry":expected_carry.duplicate(true),"decisions":player_decisions.duplicate(true)})
	await create_timer(0.1).timeout
	await next_scene("res://content/world/world_map_scene.json")
	mode="campaign_world"
	await create_timer(0.8).timeout
	check(scene.play_loop.is_empty(),"world map is not a second battle-state owner")
	var saved:=CampaignProgress.load_progress()
	check(saved.get("scenario_path")=="res://content/world/world_map_scene.json" and not saved["carry"].has("initialization_rng") and not saved["carry"].has(GlobalRandomStream.LOOP_KEY),"real return-to-map button persists the carry without any global stream")
	check(saved["carry"]["units"].has("hu") and saved["carry"]["units"].has("leonard") and not saved["carry"]["units"].has("tina"),"world carry contains both current controlled actors and no unrelated party")
	check(saved["carry"]["units"]["hu"]["level"]==BattlePlayLoop.unit(finished,"hu")["level"] and saved["carry"]["units"]["leonard"]["permanent_gains"]["defense"]==3,"earned level and permanent values survive world persistence")
	chain_records.append({"stage":"world_saved","record":saved.duplicate(true)})
	await shot("returned-from-victory")
	await close_scene()
	write_receipt("campaign-receipt.json")
	print("OHM_CAMPAIGN_RENDER_","PASS" if failures.is_empty() else "FAIL"," checks=",check_count," stages=",chain_records.size())
	quit(0 if failures.is_empty() else 1)

func next_scene(path:String) -> void:
	check(scene.get_node("BattlePresentation").battle_finished,"the battle finishes only after settlement")
	var previous:int=scene.get_instance_id()
	check(scene.campaign_progress.start_next_battle(),"the finished battle hands off to the next scene")
	for attempt in range(600):
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous:
			scene=current_scene
			check(scene.scenario_path==path,"next button resolves actual expected campaign destination: "+path)
			return
	check(false,"campaign next button did not reload the scene")

func write_receipt(filename:String) -> void:
	FileAccess.open(OHM_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_ohm_campaign_review.v1","native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"screen":root.current_screen,"time_scale":Engine.time_scale,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"isolated_user_dir":OS.get_user_data_dir(),"setup":"Incoming actual party record adjusted before play to Leonard Lv7/permanent defense3/gold345. Tina053 is placed at29,35 with speed500 before the first input; move30,35 and wait, next button, entire Ohm opening and natural battle, next button to world are real inputs. No post-input effects, battle state or RNG injection. Per-process user directory is selected before Runtime creation; the real user campaign/settings are never opened.","chain":chain_records,"frames":frames,"checks":check_count,"failures":failures,"active_mode":mode},"  "))

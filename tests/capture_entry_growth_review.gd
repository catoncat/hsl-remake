extends "res://tests/capture_script_wait_review.gd"
const BirthFixture = preload("res://tests/EntryGrowthFixture.gd")
const BirthTests = preload("res://tests/run_entry_growth_tests.gd")
const LoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const LoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const BIRTH_OUT := "res://ignored/entry-growth-review/"
var created_ids: Array = []
var birth_history := {}

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Entry growth requires a rendered review");quit(2);return
	root.title="HSL Reinforcement Entry Growth Review";root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80);root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(BIRTH_OUT);started=Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func():check(false,"bounded reinforcement growth review timeout"))
	var names:Array=["mage","thief","wing","large","zero","repeat","blocked","support","states","paralysis","victory","defeat","escape","carry","class_blocked"]
	if not OS.get_cmdline_user_args().is_empty():names=Array(OS.get_cmdline_user_args())
	for name in names:
		mode=name;await setup_birth();await play_birth();await close_scene();write_receipt("progress.json")
		if not failures.is_empty():break
	write_receipt("receipt.json")
	print("ENTRY_GROWTH_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func setup_birth() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0
	script_seen={};ai_seen={};ai_actions=[];guard_captions=[];created_ids=[];birth_history={}
	Campaign.pending={};Campaign.last_entry={}
	sample=BirthFixture.build(mode);owner_id=sample["owner_id"]
	scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene;scene.set_process(false)
	scene.settlement_controller.checkpoint_path=BIRTH_OUT+mode+".save"
	scene.first_battle_scenario=sample["scenario"].duplicate(true);scene.apply_loop(sample["loop"].duplicate(true), "test")
	for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(Loop.unit(scene.play_loop,owner_id)["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	await settle(owner_id)

func settle(id: String, terminal: bool=false) -> void:
	await super.settle(id,terminal)
	check(Loop.ReinforcementGrowth.state_error(scene.play_loop)=="","birth source and independent RNG order valid at every quiet boundary")
	for actor in BirthTests.created(scene.play_loop):
		if not created_ids.has(actor["id"]):created_ids.append(actor["id"]);birth_history[actor["id"]]=actor["entry_growth"].duplicate(true)
		check(actor["entry_growth"]==birth_history[actor["id"]],"later combat, resource tails and refresh cannot mutate birth receipt")

func inspect_birth(id: String) -> void:
	var actor:=Loop.unit(scene.play_loop,id)
	var contact:Vector2i=actor["coord"]
	await hover(scene.grid_cell_center_to_logical_position(contact))
	await point(scene.grid_cell_center_to_logical_position(contact))
	check(scene.status_panel.visible,"body input opens live reinforcement status")
	check(scene.status_panel.permanent_summary.text.contains("入場成長"),"status shows actual birth-level relationship")
	check(scene.status_panel.stat_values["attack"].text==str(actor["combat_profile"]["live_attack_damage"]),"displayed attack is the refreshed current value")
	await shot("birth-stats-"+actor["actor_id"]);await escape();await settle("")

func return_to_owner() -> void:
	for i in range(8):
		if scene.selected_unit_id==owner_id:return
		await click(scene.action_menu.get_node("WaitCommand"));await settle("")
	check(false,"controlled queue did not return to the owner")

func play_birth() -> void:
	await save_restore()
	check(created_ids.is_empty(),"no reinforcement materializes before its event")
	var seed_before:Array=scene.play_loop["global_rng"].duplicate()
	if mode=="mage":
		await click(scene.action_menu.get_node("MoveCommand"));await shot("cancel-move");await escape();await settle(owner_id)
		await click(scene.action_menu.get_node("AttackCommand"));await shot("cancel-target");await escape();await settle(owner_id)
		check(scene.play_loop["global_rng"]==seed_before,"cancel and reselect cannot generate or resample reinforcements")
	if mode in ["wing","support"]:
		await change_gear(232,"accessory1")
		await move_to(Vector2i(13,16))
		await cast_stat(Mobile.WIND if mode=="wing" else BirthFixture.Events.HEAL,sample["target_id"])
	else:
		if mode=="states":
			await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[Mobile.WIND].disabled,"silence and empty MP reject current spell before the action");await shot("restricted-magic");await escape();await settle(owner_id)
		await attack(sample["target_id"])
	await settle("")
	if mode in ["blocked","class_blocked"]:
		check(created_ids.is_empty() and BirthTests.created(scene.play_loop).is_empty(),"full footprint occupied: real event is pending and creates no birth")
		if mode=="class_blocked":
			check(Loop.unit(scene.play_loop,sample["target_id"])["defeated"] and not BattleOutcome.decided(scene.play_loop),"last original class member is dead but its pending recruit prevents premature victory")
			await shot("class-victory-pending")
		await save_restore()
		for i in range(4):
			if scene.selected_unit_id=="tina":break
			await click(scene.action_menu.get_node("WaitCommand"));await settle("")
		check(scene.selected_unit_id=="tina","blocker receives ordinary player control")
		await move_to(Vector2i(16,17) if mode=="class_blocked" else Vector2i(16,16));await click(scene.action_menu.get_node("WaitCommand"));await settle("")
	check(created_ids.size()==1,"one new actor is fully initialized and visible after the real trigger")
	if created_ids.is_empty():return
	var id:String=created_ids[0];var born:=Loop.unit(scene.play_loop,id)
	check(born["actor_id"]==sample["code"] and born["entry_growth"]["input"]["parameters"]==sample["parameters"],"actual role and script adjustment map into the same instance")
	check(born["entry_growth"]["result"]["source_level"]==Loop.ReinforcementGrowth.Entry.inferred_level(initial_state["reinforcement_templates"][0]["combat_profile"]),"entry inferred level uses original base attributes")
	check(born["entry_growth"]["draws"].is_empty() if mode=="zero" else not born["entry_growth"]["draws"].is_empty(),"explicit zero differs from randomized entry")
	await inspect_birth(id);await save_restore()
	if mode=="repeat":
		check(scene.play_loop["extra_action"]["pending"],"new insertion and dialogue finish before independent second action")
		await attack(sample["target_id"]);await settle("")
		check(created_ids.size()==2,"second event creates a distinct actor using the next saved initialization state")
		await inspect_birth(created_ids[1]);await save_restore()
	elif mode=="states":
		await use_item_real(247,owner_id);await settle("")
		check(not Loop.StatusEffectRules.magic_blocked(Loop.unit(scene.play_loop,owner_id)) and Loop.StatusEffectRules.poisoned(Loop.unit(scene.play_loop,owner_id)),"real clear-silence item leaves poison and birth records intact")
	elif mode in ["victory","class_blocked"]:
		if mode=="class_blocked":
			await finish_class_recruit(id)
		else:
			await return_to_owner()
			await move_to(Vector2i(15,16));await attack(id);await settle("",true)
		check(scene.play_loop["battle_outcome"]==(BattleOutcome.VICTORY_BOSS if mode=="class_blocked" else BattleOutcome.VICTORY_ENEMIES_CLEARED) and scene.play_loop["last_combat"]["rewards"]["gold"]==birth_history[id]["result"]["gold"],"new actor dies once and pays its actual adjusted gold before victory")
		check(scene.play_loop["last_attack"]["experience_basis"]["kill_exp"]==birth_history[id]["result"]["kill_exp"],"kill uses instance experience bonus")
	elif mode=="defeat":
		_drive_defeat_controls()
		await settle("",true)
		check(scene.play_loop["battle_outcome"]==BirthFixture.Rules.DEFEAT_OUTCOME,"grown enemy's real decision and physical attack cause defeat")
		check(ai_actions.any(func(a):return a.get("actor_id")==id and a.get("kind") in ["attack","move_then_attack"]),"the new actor, not the departed seed, performs the fatal physical decision")
	elif mode in ["escape","carry"]:
		await return_to_owner();await move_to(Vector2i(13,16));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
		check(scene.play_loop["battle_outcome"]==BattleOutcome.VICTORY_ESCAPE,"real movement/wait escapes without reticking birth initialization")
	elif mode not in ["blocked","repeat"]:
		await return_to_owner()
		for attempt in range(2):
			await cycle()
			if ai_actions.any(func(a):return a.get("actor_id")==id):break
		if mode=="paralysis":check(ai_actions.any(func(a):return a.get("actor_id")==id and a.get("kind")=="paralysis_skip"),"new actor's paralysis uses normal entry skip without another birth")
		else:check(ai_actions.any(func(a):return a.get("actor_id")==id),"adjusted actor enters the real AI queue")
	await save_restore()
	var row:Dictionary={"mode":mode,"initial":initial_state["units"],"template":initial_state["reinforcement_templates"],"final":scene.play_loop["units"].duplicate(true),"created_ids":created_ids.duplicate(),"birth_receipts":birth_history.duplicate(true),"rng_before":seed_before,"rng_after":scene.play_loop["global_rng"],"wait_cursor":scene.play_loop["script_wait_cursor"],"script_cursor":scene.script_cutscene_consumed,"ai_actions":ai_actions.duplicate(true),"combat":receipts.duplicate(true),"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"outcome":scene.play_loop["battle_outcome"],"restarted":false}
	if mode=="carry":
		var carry:=Loop.CampaignCarryRules.capture(scene.play_loop);await close_scene()
		Campaign.pending={"scenario_path":Mobile.PATH,"carry":carry}
		scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
		scene.settlement_controller.checkpoint_path=BIRTH_OUT+"carry-destination.save"
		await settle("")
		check(Campaign.pending.is_empty() and scene.play_loop["campaign_carry_receipt"]["errors"].is_empty() and not carry.has("initialization_rng") and not carry.has("global_rng") and BirthTests.created(scene.play_loop).is_empty(),"fresh battle carries the controlled party but not prior enemies or any random stream of theirs")
		await save_restore();row["carry_destination"]=scene.play_loop["units"].duplicate(true)
	elif mode in ["victory","defeat","escape","class_blocked"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true);LoopScript._maintain_script_pressure(frozen)
		check(frozen==scene.play_loop and Loop.step_ai_turn(frozen)==frozen,"terminal rejects later spawn and AI callbacks")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(scene.play_loop["scenario_ok"] and BirthTests.created(scene.play_loop).is_empty(),"restart constructs a fresh encounter without replayed birth increments")
		row["restarted"]=true
	routes.append(row)

func finish_class_recruit(id: String) -> void:
	# Observe the actual hit result. A legal miss leaves a living target and must
	# lead to another ordinary action, not a wait for a nonexistent terminal page.
	for attempt in range(8):
		await return_to_owner()
		var actor:=Loop.unit(scene.play_loop,owner_id)
		var target:=Loop.unit(scene.play_loop,id)
		var choice:=LoopAI._ai_physical_choice(scene.play_loop,actor,target,Loop._movement_envelope(scene.play_loop,owner_id))
		if choice.is_empty():
			await click(scene.action_menu.get_node("WaitCommand"));await settle("")
			continue
		if choice["to"]!=actor["coord"]:await move_to(choice["to"])
		await attack(id)
		observed["finishing_attacks"]=attempt+1
		await settle("",BattleOutcome.decided(scene.play_loop))
		if BattleOutcome.decided(scene.play_loop):return
	check(false,"bounded real attacks did not settle the class-count victory")

func _drive_defeat_controls() -> void:
	# Only this isolated encounter: normal Wait buttons advance controllable
	# actors while the inherited observer checks every AI/script/terminal frame.
	for frame in range(3000):
		if not is_instance_valid(scene) or BattleOutcome.decided(scene.play_loop):return
		var view=scene.get_node("BattlePresentation")
		if scene.action_menu.visible and not scene.action_menu.is_expanding() and not view.combat_busy(scene.play_loop) and not scene.ScriptPresentation.pending(scene) and not scene.ai_playback_active:
			await click(scene.action_menu.get_node("WaitCommand"))
		await create_timer(0.03).timeout
	check(false,"bounded defeat input driver did not reach the terminal")

func shot(label: String) -> void:
	await process_frame;RenderingServer.force_draw(false);serial+=1
	var name:="%s-%03d-%s.png"%[mode,serial,label]
	check(root.get_texture().get_image().save_png(BIRTH_OUT+name)==OK,"capture "+label);frames.append(name)

func write_receipt(filename: String) -> void:
	FileAccess.open(BIRTH_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_entry_growth_review.v1","fixture":true,"real_control_events":true,"native_execution":false,"pid":OS.get_process_id(),"screen":root.current_screen,"window_size":root.size,"time_scale":Engine.time_scale,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"checks":check_count,"routes":routes,"frames":frames,"failures":failures,
		"setup":"Authored event901 inserts the selected original026/028/036/039 template on original051 terrain after a real attack or heal. Initial controlled levels12, explicit durability/MP/status/equipment/AI probability and terminal-role source attack overrides are declared in EntryGrowthFixture. All actual births execute current native-matching proposals once with saved RNG; no post-setup stats or random outcomes are replaced. Isolated F5/F9 files and one-shot carry avoid user campaign writes.",
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"interaction":scene.play_loop.get("interaction"),"error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units"),"created":created_ids,"births":birth_history,"rng":scene.play_loop.get("global_rng"),"last_attack":scene.play_loop.get("last_attack"),"observed":observed}},"  "))

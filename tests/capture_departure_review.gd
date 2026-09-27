extends "res://tests/capture_mobile_jobs_review.gd"
## Authored event chains, source maps/roles; post-setup interaction uses real UI.
const Departure = preload("res://tests/ScriptDepartureFixture.gd")
const DEPART_OUT := "res://ignored/script-departure-review/"
var sample := {}
var retired_at_commit := {}
var cutscene_seen := {}

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Departure review needs rendered built-in window"); quit(2); return
	root.title = "HSL Script Departure and Restore Review"; root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80); root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(DEPART_OUT); started = Time.get_ticks_msec()
	create_timer(1800).timeout.connect(func():check(false,"bounded departure review timeout"))
	var names: Array = ["walk","delete","giant","second","mage","support","blocked","ai","paralysis","kill","victory","defeat","escape","carry","rearm"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	Campaign.pending = {}; Campaign.last_entry = {}
	for name in names:
		mode = name; await setup_departure(); await play_departure(); await close_scene(); write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json"); print("DEPARTURE_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)

func setup_departure() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0;retired_at_commit={};cutscene_seen={}
	Campaign.pending={};Campaign.last_entry={}; sample=Departure.build("support" if mode=="carry" else mode);owner_id=sample["owner_id"]
	scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.set_process(false);scene.settlement_controller.checkpoint_path=DEPART_OUT+mode+".save"
	scene.first_battle_scenario=sample["scenario"].duplicate(true);scene.apply_loop(sample["loop"].duplicate(true), "test")
	for art in scene.actors_root.get_children():scene.actors_root.remove_child(art);art.queue_free()
	scene.unit_grid_coords.clear();scene.resume_turn_presentation();scene.center_camera_on_grid(Loop.unit(scene.play_loop,sample["first_id"])["coord"]);scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	check(initial_state["event_statuses"].has(901),"authored event is armed through supported source insert token")
	scene.get_node("BattlePresentation").cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await settle(sample["first_id"])

func settle(id: String, terminal: bool = false) -> void:
	for attempt in range(4000):
		var view=scene.get_node("BattlePresentation");var coordinator=scene.opening_coordinator
		check(scene.play_loop["scenario_ok"],"valid live departure state: "+str(scene.play_loop.get("scenario_error")))
		check(Loop.Presence.state_error(scene.play_loop)=="","departure ledger matches grid and queue throughout playback")
		for audio in scene.find_children("*","AudioStreamPlayer",true,false):
			if audio.playing and audio.stream!=null and audio.get_playback_position()>0:sounds[audio.stream.resource_path]=true
		var latest:Dictionary=scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):receipt_sequences[latest["sequence"]]=true;receipts.append(latest.duplicate(true))
		var retired:=Loop.unit(scene.play_loop,sample["retiring_id"])
		if mode=="rearm" and scene.play_loop["departure_sequence"]>1:
			var prior=scene.actor_node_for_unit("enemy026_1")
			check(prior==null or not prior.visible,"second firing never resurrects the first template instance")
		if retired.get("departed",false):
			if retired_at_commit.is_empty():retired_at_commit=retired.duplicate(true)
			check(retired==retired_at_commit,"visual departure never mutates retired vitals/resources/status/growth")
			for cell in Loop.Footprint.cells(retired):check(Loop.unit_id_at_coord(scene.play_loop,cell)!=retired["id"],"retained picture cannot occupy or intercept a target")
		if scene.has_actor_motion():observed["movement"]=true
		if coordinator!=null and coordinator.active and coordinator.cutscene_mode:
			check(not scene.action_menu.visible and not view.battle_finished and not view.cutin.busy(),"script waits for combat then holds controls and terminal page")
			var event:Dictionary=scene.scene_timeline.current_event();var token:String=str(coordinator.cutscene_key)+":"+str(event.get("id"))
			if not cutscene_seen.has(token):cutscene_seen[token]=true;await shot("script-"+str(event.get("kind")))
			if not observed.has("busy_save"):
				var bytes:=FileAccess.get_file_as_bytes(scene.settlement_controller.checkpoint_path)
				await key(KEY_F5)
				check(FileAccess.get_file_as_bytes(scene.settlement_controller.checkpoint_path)==bytes,"F5 during an active script cannot overwrite the earlier safe checkpoint")
				observed["busy_save"]=true
			if event.get("kind")=="dialogue_message_id":await key(KEY_SPACE)
			await create_timer(0.02).timeout;continue
		if view.cutin.busy():
			check(not scene.action_menu.visible and not view.battle_finished,"impact sequence finishes before controls/results")
			if not observed.has("combat"):observed["combat"]=true;await shot("combat")
		if view.item_feedback_busy() or view.turn_end_cue.showing():
			check(not scene.action_menu.visible,"item and resource cues precede control")
			var token:="item-%s"%scene.play_loop["item_use_sequence"] if view.item_feedback_busy() else "tail-%s"%scene.play_loop["action_end_sequence"]
			if not observed.has(token):observed[token]=true;events.append((scene.play_loop["last_item_use"] if view.item_feedback_busy() else scene.play_loop["last_action_end"]).duplicate(true));await shot(token)
		if view.dialogue_active():await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:await click(loot.rows[0]);await click(loot.slots[loot.first_empty_slot()])
			else:await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var stat:String=["str","dex","mind","con"][i%4]
				if not scene.growth_panel.choices[stat]["plus"].disabled:await click(scene.growth_panel.choices[stat]["plus"])
			await shot("growth");await click(scene.growth_panel.confirm_button)
		if view.battle_finished:
			check(terminal,"unexpected outcome before requested action")
			check(not scene.ScriptPresentation.pending(scene),"all terminal scripts finish before result controls")
			await shot("result");return
		if not terminal and (id=="" or scene.selected_unit_id==id) and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.ScriptPresentation.pending(scene):
			await shot("ready");return
		if attempt==1500:await shot("waiting");write_receipt("waiting.json")
		await create_timer(0.02).timeout
	check(false,"bounded departure playback did not settle at "+id)

func play_departure() -> void:
	await save_restore()
	if mode in ["second","blocked"]:
		await use_item_real(241,owner_id);await settle(owner_id)
		check(scene.play_loop["extra_action"]["pending"],"actual item creates a second independent action")
		await save_restore()
	if mode=="blocked":
		await click(scene.action_menu.get_node("MagicCommand"));check(scene.magic_panel.choices[Departure.WIND].disabled,"MP0 and silence reject the owned spell")
		await shot("disabled-spell");await escape();await settle(owner_id)
	if mode=="ai":
		await click(scene.action_menu.get_node("WaitCommand"));await settle("tina")
	elif mode=="paralysis":
		# Paralyzed owner cannot act; a living ally's source heal triggers its exit.
		await cast_stat(Departure.HEAL,owner_id);await settle("tina")
	elif mode=="escape":
		await move_to(Vector2i(13,16));await click(scene.action_menu.get_node("WaitCommand"));await settle("",true)
	elif mode in ["mage","support","carry"]:
		await change_gear(232,"accessory1")
		await move_to(Vector2i(13,16))
		await cast_stat(Departure.HEAL if mode in ["support","carry"] else Departure.WIND,sample["target_id"])
		await settle("")
	else:
		if mode=="walk":await move_to(Vector2i(15,17))
		await attack(sample["target_id"]);await settle("",mode in ["victory","defeat"])
	if mode=="rearm":
		check(scene.play_loop["departure_sequence"]==1 and scene.play_loop["extra_action"]["pending"],"first repeated event retires one instance and leaves the owner's second action")
		await save_restore()
		sample["retiring_id"]="enemy026_2";retired_at_commit={}
		await attack("enemy026_2");await settle("")
		var deleted:Array=scene.opening_coordinator.story_records.filter(func(record):return record.get("kind")=="actor_deleted").map(func(record):return record["unit_id"])
		check(deleted==["enemy026_1","enemy026_2"] and scene.play_loop["winfail_runtime"]["fired"].size()==2,"re-armed event binds two committed identities in order across a save/restore")
	var gone:=Loop.unit(scene.play_loop,sample["retiring_id"])
	check(gone.get("departed",false) and not gone["defeated"],"configured role leaves without fabricating death or loot")
	check(scene.actor_node_for_unit(gone["id"])==null or not scene.actor_node_for_unit(gone["id"]).visible,"finished departure leaves no visible ghost")
	check(not scene.unit_grid_coords.has(gone["id"]),"finished departure cannot remain in input lookup")
	check(scene.script_cutscene_consumed==scene.play_loop["winfail_runtime"]["fired"].size(),"all script firings have a consumed cursor")
	check(scene.opening_coordinator.cutscene_records.all(func(row):return row["finished"]),"all started script presentations finish")
	if mode=="giant":
		var released:Vector2i=gone["coord"]
		check(Loop.movement_cells(scene.play_loop).has(released),"large departure releases the central destination for current player")
		await move_to(released)
	if mode=="second":check(scene.play_loop["action_end_sequence"]==0 and not scene.play_loop["extra_action"]["pending"],"owner departure cancels second eligibility without poison or recovery tail")
	if mode=="ai":check(scene.play_loop["last_ai_actions"].filter(func(a):return a.get("actor_id")==owner_id).size()==1,"AI cannot spend a second action after its scripted departure")
	if mode in ["kill","victory"]:check(Loop.unit(scene.play_loop,sample["target_id"])["defeated"] and Loop.unit(scene.play_loop,owner_id)["level"]>1,"real kill settles final experience independently of allied departure")
	await save_restore()
	await recreate_and_restore()
	var row:Dictionary={"mode":mode,"initial":initial_state["units"],"final":scene.play_loop["units"].duplicate(true),"departure":scene.play_loop["last_departure"].duplicate(true),"fired":scene.play_loop["winfail_runtime"]["fired"].duplicate(true),"cursor":scene.script_cutscene_consumed,"outcome":scene.play_loop["battle_outcome"],"combat":receipts.duplicate(true),"impacts":impacts.duplicate(true),"events":events.duplicate(true),"script_steps":cutscene_seen.keys(),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"fresh_scene_restored":true,"restarted":false}
	if mode=="carry":await carry_into_new_scene(row)
	if mode in ["victory","defeat","escape"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen and Loop.use_item(frozen,"241")==frozen,"terminal rejects later action/resource/item callbacks")
		reload_current_scene();await create_timer(0.4).timeout;scene=current_scene
		check(scene.script_cutscene_consumed==0 and scene.play_loop["departure_sequence"]==0 and not BattleOutcome.decided(scene.play_loop),"actual restart resets this battle cursor and departure history")
		check(scene.play_loop["units"].all(func(a):return not a.get("departed",false)),"restart reconstructs the declared roster")
		row["restarted"]=true
	routes.append(row)

func recreate_and_restore() -> void:
	var saved_loop:Dictionary=scene.play_loop.duplicate(true);var cursor:int=scene.script_cutscene_consumed
	var path:String=scene.settlement_controller.checkpoint_path
	await close_scene()
	scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.set_process(false);scene.first_battle_scenario=sample["scenario"].duplicate(true);scene.apply_loop(sample["loop"].duplicate(true), "test");scene.script_cutscene_consumed=0
	scene.settlement_controller.checkpoint_path=path
	# Authored fresh-opening setup: exercise the actual Runtime F9 routing while
	# an active coordinator would otherwise consume the key. No saved effect runs.
	if scene.opening_coordinator==null:
		scene.opening_coordinator=scene.BattleOpeningCoordinator.new();scene.opening_coordinator.name="OpeningCoordinator";scene.opening_coordinator.runtime=scene;scene.add_child(scene.opening_coordinator)
	scene.interaction_state="opening_timeline";scene.opening_coordinator.active=true;scene.opening_coordinator.cutscene_mode=false
	await key(KEY_F9)
	check(scene.play_loop==saved_loop and scene.script_cutscene_consumed==cursor and not scene.opening_coordinator.active,"actual opening F9 restores exact loop and cursor, retires old coordinator")
	scene.set_process(true);await settle("",BattleOutcome.decided(saved_loop))
	check(scene.opening_coordinator.cutscene_records.is_empty(),"fresh restored scene does not replay previously consumed dialogue/deletion")
	check(scene.actor_node_for_unit(sample["retiring_id"])==null,"fresh restore does not recreate departed actor node")
	await shot("fresh-restored")
	if mode=="support":
		var carry:=Loop.CampaignCarryRules.capture(scene.play_loop)
		var fresh:=Loop.apply_campaign_carry(Mobile.fresh(),carry)
		check(fresh["campaign_carry_receipt"]["errors"].is_empty() and fresh["departure_sequence"]==0 and not Loop.unit(fresh,sample["retiring_id"]).get("departed",false),"cross-battle party carry preserves role data but never old departure or script cursor")
		row_carry(carry,fresh)

func row_carry(carry:Dictionary,fresh:Dictionary)->void:
	observed["cross_battle"]={"carry":carry,"recipient_units":fresh["units"],"departure_sequence":fresh["departure_sequence"]}

func carry_into_new_scene(row:Dictionary)->void:
	var carry:=Loop.CampaignCarryRules.capture(scene.play_loop)
	await close_scene()
	# Authored handoff destination exercises the same one-use pending payload as
	# campaign buttons without changing the user's persistent campaign file.
	Campaign.pending={"scenario_path":Mobile.PATH,"carry":carry}
	scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate();root.add_child(scene);current_scene=scene
	scene.settlement_controller.checkpoint_path=DEPART_OUT+"carry-destination.save"
	await settle("")
	check(scene.play_loop["scenario_ok"] and scene.play_loop["campaign_carry_receipt"]["errors"].is_empty(),"actual fresh scene consumes carried role/gear/permanent fields")
	check(Campaign.pending.is_empty() and scene.script_cutscene_consumed==0 and scene.play_loop["departure_sequence"]==0,"new battle consumes handoff once without importing the old event/departure ledger")
	var friend:=Loop.unit(scene.play_loop,sample["retiring_id"])
	check(Loop.Presence.living(friend) and scene.actor_node_for_unit(friend["id"]).visible and scene.unit_grid_coords.has(friend["id"]),"new declared roster restores the carried companion as a real visible actor")
	await save_restore();await shot("carry-destination")
	row["cross_battle"]={"carry":carry,"recipient":scene.play_loop["units"].duplicate(true),"receipt":scene.play_loop["campaign_carry_receipt"].duplicate(true),"cursor":scene.script_cutscene_consumed,"saves":saves}

func attack(target:String)->void:
	await click(scene.action_menu.get_node("AttackCommand"))
	var coord:Variant=Loop.Footprint.contact(Loop.unit(scene.play_loop,target),Loop.attack_cells(scene.play_loop))
	check(coord is Vector2i,"shared target query exposes a reachable body contact")
	await hover(scene.grid_cell_center_to_logical_position(coord));await shot("attack-target")
	await point(scene.grid_cell_center_to_logical_position(coord))
	check(scene.play_loop["last_attack"].get("defender_id")==target,"body-edge click commits exactly one target")

func shot(label:String)->void:
	await process_frame;RenderingServer.force_draw(false);serial+=1
	var name:="%s-%03d-%s.png"%[mode,serial,label]
	check(root.get_texture().get_image().save_png(DEPART_OUT+name)==OK,"capture "+label);frames.append(name)

func write_receipt(filename:String)->void:
	FileAccess.open(DEPART_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_script_departure_review.v1","fixture":true,"real_control_events":true,"native_execution":false,"pid":OS.get_process_id(),"screen":root.current_screen,"window_size":root.size,"time_scale":Engine.time_scale,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"routes":routes,"frames":frames,"failures":failures,
		"setup":"Source051 terrain and004/006/002/026/039 roles/art, authored finite inventories/durability/speeds/HP1/EXP99/status/AI rates and event901. The authored status script uses supported actInsert/check/message/delete tokens and is not a recovered chapter encounter. Fresh-scene restore sets an opening boundary then sends real F9. All after-setup gameplay uses actual buttons, target cells, growth, F5/F9 and restart; no random roll or settlement is patched. Original16 logical ticks are independent from the declared0.24s remake fade.",
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"interaction":scene.play_loop.get("interaction"),"selected":scene.selected_unit_id,"error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units"),"cursor":scene.script_cutscene_consumed,"fired":scene.play_loop.get("winfail_runtime",{}).get("fired"),"observed":observed}},"  "))

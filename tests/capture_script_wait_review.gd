extends "res://tests/capture_mobile_jobs_review.gd"
## Source opening plus authored encounters; after setup, controls drive all play.
const WaitFixture = preload("res://tests/ScriptWaitFixture.gd")
const WaitSave = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const WAIT_OUT := "res://ignored/script-wait-review/"
var sample := {}
var script_seen := {}
var ai_seen := {}
var ai_actions: Array = []
var guard_captions: Array = []
var check_count := 0

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Script wait review requires a rendered window"); quit(2); return
	root.title = "HSL Guard Wait and Script Synchronization Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(WAIT_OUT)
	started = Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func():check(false,"bounded script wait review timeout"))
	var names: Array = ["opening","guard","double_guard","wounded","silenced","paralyzed","ai_chain","event","mage","support","sync","depart","kill","victory","defeat","escape","carry"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_wait()
		await play_wait()
		await close_scene()
		write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json")
	print("SCRIPT_WAIT_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size())
	quit(0 if failures.is_empty() else 1)

func setup_wait() -> void:
	impacts=[]; events=[]; sounds={}; observed={}; saves=0; receipts=[]; receipt_sequences={}; item_receipts=[]; item_seen={}; serial=0
	script_seen={}; ai_seen={}; ai_actions=[]; guard_captions=[]
	Campaign.pending={}; Campaign.last_entry={}
	if mode == "opening":
		scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
		scene.scenario_path = "res://content/battles/battle_052.json"
		scene.startup_mode = "product_opening"
		root.add_child(scene); current_scene=scene
		scene.settlement_controller.checkpoint_path=WAIT_OUT+mode+".save"
		owner_id="leonard"
	else:
		sample=WaitFixture.build(mode); owner_id=sample["owner_id"]
		scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate(); root.add_child(scene); current_scene=scene
		scene.set_process(false)
		scene.settlement_controller.checkpoint_path=WAIT_OUT+mode+".save"
		scene.first_battle_scenario=sample["scenario"].duplicate(true)
		scene.apply_loop(sample["loop"].duplicate(true), "test")
		for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art); art.queue_free()
		scene.unit_grid_coords.clear(); scene.resume_turn_presentation()
		scene.center_camera_on_grid(Loop.unit(scene.play_loop,owner_id)["coord"])
		scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	await settle(owner_id)

func settle(id: String, terminal: bool=false) -> void:
	for attempt in range(5000):
		check(scene.play_loop["scenario_ok"], "valid wait scenario: " + str(scene.play_loop.get("scenario_error")))
		check(Loop.ScriptWait.state_error(scene.play_loop)=="", "wait assignment/cursor remains coherent throughout presentation")
		var view=scene.get_node("BattlePresentation")
		var coordinator=scene.opening_coordinator
		for audio in scene.find_children("*","AudioStreamPlayer",true,false):
			if audio.playing and audio.stream!=null and audio.get_playback_position()>0: sounds[audio.stream.resource_path]=true
		var latest:Dictionary=scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]): receipt_sequences[latest["sequence"]]=true; receipts.append(latest.duplicate(true))
		for action in scene.play_loop.get("last_ai_actions",[]):
			var token:=str(scene.play_loop["turn"])+":"+str(action)
			if not ai_seen.has(token): ai_seen[token]=true; ai_actions.append(action.duplicate(true))
		if coordinator!=null and coordinator.active:
			check(not scene.action_menu.visible and not view.battle_finished, "script completes before player controls or outcome page")
			var event:Dictionary=scene.scene_timeline.current_event()
			var key:=str(scene.script_cutscene_consumed)+":"+str(event.get("id"))
			if not script_seen.has(key):
				script_seen[key]=true
				if event.get("kind") in ["dialogue_message_id","actor_action_wait","inserted_object_wait_round","first_control_marker"]: await shot("script-"+str(event.get("kind")))
			if event.get("kind")=="dialogue_message_id":
				if mode=="sync" and event.get("id")=="wait_message":
					var other=scene.actor_node_for_unit("enemy026_1")
					check(other!=null and other.is_moving(), "short actor wait releases dialogue while unrelated long walk continues")
					observed["target_specific_barrier"]=true
				await key(KEY_SPACE)
			await create_timer(0.02).timeout; continue
		if scene.has_actor_motion(): observed["movement"]=true
		if view.navigation_cue.caption.visible:
			check(not scene.action_menu.visible and not view.battle_finished, "guard/status feedback precedes successor controls")
			var caption:String=view.navigation_cue.caption.text
			if not guard_captions.has(caption): guard_captions.append(caption); await shot("guard-feedback")
		if view.cutin.busy():
			check(not scene.action_menu.visible and not view.battle_finished, "combat completes before waits or terminal controls")
			if not observed.has("combat"): observed["combat"]=true; await shot("combat")
		if view.aftermath.reward_label.visible and view.aftermath.reward_label.text.contains("EXP"):
			check(not view.battle_finished, "experience and level feedback complete before terminal presentation")
			var text:String=view.aftermath.reward_label.text
			if observed.get("experience_text","")!=text: observed["experience_text"]=text; await shot("experience")
		if view.item_feedback_busy() or view.turn_end_cue.showing():
			check(not scene.action_menu.visible, "item/resource/status tail cannot overlap the next menu")
			var token:="item-"+str(scene.play_loop["item_use_sequence"]) if view.item_feedback_busy() else "tail-"+str(scene.play_loop["action_end_sequence"])
			if not observed.has(token): observed[token]=true; events.append((scene.play_loop["last_item_use"] if view.item_feedback_busy() else scene.play_loop["last_action_end"]).duplicate(true)); await shot(token)
		if view.dialogue_active(): await key(KEY_SPACE)
		var loot=scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"]=true
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var stat:String=["str","dex","mind","con"][i%4]
				if not scene.growth_panel.choices[stat]["plus"].disabled: await click(scene.growth_panel.choices[stat]["plus"])
			await shot("growth"); await click(scene.growth_panel.confirm_button)
		if view.battle_finished:
			check(terminal, "outcome appears only after the requested terminal action")
			await shot("result"); return
		if not terminal and (id=="" or scene.selected_unit_id==id) and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.ScriptPresentation.pending(scene):
			await shot("ready"); return
		if attempt==2500: write_receipt("waiting.json")
		await create_timer(0.02).timeout
	check(false,"bounded wait playback failed to reach "+id)

func cycle() -> void:
	var turn:int=scene.play_loop["turn"]
	for attempt in range(8):
		await click(scene.action_menu.get_node("WaitCommand")); await settle("")
		if scene.play_loop["turn"]>turn and scene.selected_unit_id==owner_id: return
	check(false,"bounded real control cycle did not return to the owner")

func play_wait() -> void:
	await save_restore()
	if mode=="opening":
		check(scene.play_loop["script_wait_source"]["initial"].size()==4, "actual STORY052 opening installs four source wait assignments")
		for row in scene.play_loop["script_wait_source"]["initial"]:
			check(Loop.unit(initial_state,row["unit_id"])["ai_wait_remaining"]==2,"fresh opening starts with the source wait2 assignment")
			var turns:=ai_actions.filter(func(a):return a.get("actor_id")==row["unit_id"] and a.get("wait_reason")=="wait_round")
			check(turns.size()==1 and Loop.unit(scene.play_loop,row["unit_id"])["ai_wait_remaining"]==1,"guard takes its scheduled first action before Leonard control; F9 preserves remaining one")
	elif mode in WaitFixture.FAR_MODES:
		await cycle()
		var guard:=Loop.unit(scene.play_loop,"enemy026_1")
		if mode in ["guard","double_guard"]:
			check(guard["ai_wait_remaining"]==(1 if mode=="guard" else 0), "actual guard action decrements once per independent evaluation")
			check(guard_captions.any(func(t):return t.contains("守候")), "waiting is visible before control is returned")
		elif mode=="paralyzed": check(guard["ai_wait_remaining"]==2 and not Loop.StatusEffectRules.paralyzed(guard),"paralyzed guard uses only entry/status tail before future AI evaluation")
		else: check(guard["ai_wait_remaining"]==0,"damage or silence wakes source waiting logic before fresh action choice")
		await save_restore()
		await cycle()
		check(Loop.unit(scene.play_loop,"enemy026_1")["ai_wait_remaining"]==0,"later cycle progresses from saved remaining count")
	elif mode == "ai_chain":
		await cycle()
		check(Loop.unit(scene.play_loop,"enemy026_1")["ai_wait_remaining"]==0 and Loop.unit(scene.play_loop,"enemy026_1")["mp"]==0,"woken AI pays current MP once and exhausts its real resource")
		var spells:=ai_actions.filter(func(a):return a.get("actor_id")=="enemy026_1" and a.get("skill_id")==WaitFixture.Mobile.WIND)
		var ordinary:=ai_actions.filter(func(a):return a.get("actor_id")=="enemy026_1" and a.get("kind") in ["attack","move_then_attack"] and a.get("formula_source")=="core_logic")
		check(not spells.is_empty() and not ordinary.is_empty(),"second AI action replaces its exhausted spell intent with a real ordinary attack")
	elif mode in ["escape","carry"]:
		await move_to(Vector2i(13,16)); await click(scene.action_menu.get_node("WaitCommand")); await settle("",true)
	elif mode in ["mage","support"]:
		await change_gear(232,"accessory1")
		await move_to(Vector2i(13,16))
		await cast_stat(WaitFixture.Mobile.WIND if mode=="mage" else WaitFixture.Depart.HEAL,sample["target_id"])
		await settle("")
		check(not scene.play_loop["last_attack"].is_empty() and scene.play_loop["script_wait_cursor"]==2, "moved spell/support payment and event assignments settle together once")
	else:
		await attack("enemy026_1")
		await settle("",mode in ["victory","defeat"])
		if mode in ["event","depart"]:
			await save_restore()
			check(scene.play_loop["extra_action"]["pending"],"event completes before the independent second action")
			await attack("enemy026_2" if mode=="depart" else "enemy026_1"); await settle("")
			check(scene.play_loop["winfail_runtime"]["fired"].size()==2 and scene.play_loop["script_wait_cursor"]==4,"repeated event has two distinct consumed setter/sync requests")
		if mode=="sync": check(observed.get("target_specific_barrier",false),"actual scripted motion exercises the specific-object barrier")
		if mode=="depart":
			check(scene.play_loop["departure_sequence"]==2,"two current template instances depart without reusing a stale binding")
			for id in ["enemy026_1","enemy026_2"]: check(scene.actor_node_for_unit(id)==null or not scene.actor_node_for_unit(id).visible,"departed wait target cannot remain a visible ghost")
		if mode in ["kill","victory"]:
			var grown:=Loop.unit(scene.play_loop,owner_id)
			check(grown["level"]>1 and str(observed.get("experience_text","")).contains("升級"),"actual lethal action awards EXP and shows its level increase before control or result")
			check(observed.get("growth",false) if mode=="kill" else grown["pending_stat_points"]==5,"ongoing battle allocates growth; terminal preserves its five pending points for carry")
	await save_restore()
	var row:Dictionary={"mode":mode,"initial":initial_state["units"],"final":scene.play_loop["units"].duplicate(true),"wait_source":scene.play_loop["script_wait_source"].duplicate(true),"wait_cursor":scene.play_loop["script_wait_cursor"],"wait_receipt":scene.play_loop["last_script_wait"].duplicate(true),"requests":scene.play_loop.get("winfail_runtime",{}).get("wait_requests",[]).duplicate(true),"script_cursor":scene.script_cutscene_consumed,"ai_actions":ai_actions.duplicate(true),"guard_captions":guard_captions.duplicate(),"combat":receipts.duplicate(true),"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"outcome":scene.play_loop["battle_outcome"],"restarted":false}
	if mode=="carry":
		var carry:=Loop.CampaignCarryRules.capture(scene.play_loop)
		await close_scene()
		Campaign.pending={"scenario_path":Mobile.PATH,"carry":carry}
		scene=load("res://game/battle/development/MobileJobsTrial.tscn").instantiate()
		root.add_child(scene); current_scene=scene; scene.settlement_controller.checkpoint_path=WAIT_OUT+"carry-destination.save"
		await settle("")
		check(Campaign.pending.is_empty() and scene.play_loop["script_wait_cursor"]==0 and scene.script_cutscene_consumed==0,"cross-battle handoff consumes once and starts new script cursors")
		check(scene.play_loop["campaign_carry_receipt"]["errors"].is_empty() and scene.play_loop["script_wait_source"]["initial"].is_empty(),"new declared roster receives party progression and its own default waiting policy")
		await save_restore(); row["carry_destination"]=scene.play_loop["script_wait_source"].duplicate(true)
	elif mode in ["victory","defeat","escape"]:
		var frozen:Dictionary=scene.play_loop.duplicate(true)
		check(Loop.step_ai_turn(frozen)==frozen and Loop.finish_exhausted_action(frozen)==frozen,"terminal rejects all later action/tick callbacks")
		reload_current_scene(); await create_timer(0.4).timeout; scene=current_scene
		check(scene.play_loop["scenario_ok"] and scene.play_loop["script_wait_cursor"]==0 and not BattleOutcome.decided(scene.play_loop),"actual restart resets this encounter's assignment history")
		row["restarted"]=true
	routes.append(row)

func attack(target: String) -> void:
	await click(scene.action_menu.get_node("AttackCommand"))
	var coord:Variant=Loop.Footprint.contact(Loop.unit(scene.play_loop,target),Loop.attack_cells(scene.play_loop))
	check(coord is Vector2i,"current target has a legal body contact")
	await hover(scene.grid_cell_center_to_logical_position(coord)); await shot("attack-target")
	await point(scene.grid_cell_center_to_logical_position(coord))
	check(scene.play_loop["last_attack"].get("defender_id")==target,"actual target input commits one exchange")

func save_restore() -> void:
	var before:Dictionary=scene.play_loop.duplicate(true)
	await key(KEY_F5)
	check(FileAccess.file_exists(scene.settlement_controller.checkpoint_path),"actual save file exists")
	var encoded:=FileAccess.get_file_as_bytes(scene.settlement_controller.checkpoint_path)
	var decoded:=WaitSave.decode(encoded, before)
	check(decoded["ok"] and decoded["snapshot"]["loop"]==before,"saved assignment cursor and countdown exactly match the quiet battle")
	await key(KEY_F9)
	check(scene.play_loop==before,"actual F9 does not replay a wait, item, EXP or state tail")
	saves+=1
	await settle("",BattleOutcome.decided(scene.play_loop))
	await shot("restored")

func shot(label: String) -> void:
	await process_frame; RenderingServer.force_draw(false); serial+=1
	var name:="%s-%03d-%s.png"%[mode,serial,label]
	check(root.get_texture().get_image().save_png(WAIT_OUT+name)==OK,"capture "+label)
	frames.append(name)

func write_receipt(filename: String) -> void:
	FileAccess.open(WAIT_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_script_wait_review.v1","fixture":true,"real_control_events":true,"native_execution":false,"pid":OS.get_process_id(),"screen":root.current_screen,"time_scale":Engine.time_scale,"window_size":root.size,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"checks":check_count,"routes":routes,"frames":frames,"failures":failures,
		"setup":"Opening uses unchanged STORY052/player grants. Other encounters retain source051 terrain and004/006/002/026 roles/assets, with declared durability, current HP/MP/status, extra-action equipment, probability overrides and authored event901. Guard positions are legal source cells outside the existing nearby radius. Only setup assigns battle data; every later attack, spell, movement, equipment change, wait, growth, save/load and restart uses actual controls. Carry uses an isolated one-shot pending payload; no user campaign file is written.",
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units"),"wait_cursor":scene.play_loop.get("script_wait_cursor"),"fired":scene.play_loop.get("winfail_runtime",{}).get("fired"),"observed":observed}},"  "))

func check(ok: bool, message: String) -> void:
	check_count+=1
	if not ok:
		failures.append(message); push_error(message); write_receipt("failed.json"); quit(1)

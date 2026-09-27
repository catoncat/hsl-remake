extends "res://tests/capture_gol_road_review.gd"
## Real controls and normal rendering. natural_pickup uses the exact preceding
## Ohm victory carry, not a new full Gol win. Other routes declare their setup.
const run_treasure_tests = preload("res://tests/run_treasure_tests.gd")
const TREASURE_OUT := "res://ignored/treasure-review/"
var pause_on_treasure := false
var defer_all := false
var discovery_seen := {}
var setup_note := ""
var terminal_snapshot := {}


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "HSL-Review-Treasure-" + str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless" or Engine.time_scale != 1.0:
		push_error("Treasure review requires a rendered window and normal clock"); quit(2); return
	root.title = "HSL Treasure Gameplay Review"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(TREASURE_OUT)
	started = Time.get_ticks_msec()
	create_timer(1200).timeout.connect(func(): check(false, "bounded treasure review timeout"))
	var names: Array = ["natural_pickup"] if OS.get_cmdline_user_args().is_empty() else Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		check(mode in ["natural_pickup", "full", "duplicates", "attack", "defeat", "victory", "campaign", "resume_pool"], "known treasure route")
		await setup_treasure()
		var extension := {}
		if mode == "natural_pickup": await natural_treasure()
		elif mode == "full": await full_treasure()
		elif mode == "duplicates": await duplicate_treasure()
		elif mode == "attack": await attack_treasure()
		elif mode == "defeat": await defeat_treasure()
		elif mode == "victory": await victory_treasure()
		elif mode == "resume_pool": await resume_pool()
		else: extension = await treasure_campaign()
		if extension.is_empty(): extension = {"final": scene.play_loop.duplicate(true) if terminal_snapshot.is_empty() else terminal_snapshot, "restarted":not terminal_snapshot.is_empty()}
		routes.append({"mode": mode, "setup": setup_note, "initial": initial_state,
			"saves": saves, "discoveries": discovery_seen.keys(), "sounds": sounds.keys(),
			"combat": receipts.duplicate(true), "decisions": player_decisions.duplicate(true)})
		routes.back().merge(extension, true)
		await close_scene()
		write_receipt("progress.json")
	write_receipt("receipt.json")
	print("TREASURE_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size(), " checks=", check_count)
	quit(0 if failures.is_empty() else 1)


func setup_treasure() -> void:
	impacts=[]; events=[]; sounds={}; observed={}; saves=0; receipts=[]; receipt_sequences={}; item_receipts=[]; item_seen={}; serial=0
	learning_texts=[]; ai_receipts=[]; recorded_ai={}; arrow_signals=[0,0]; opening_messages=[]; player_decisions=[]; installations=[]; saved_arrival=false
	discovery_seen={}; pause_on_treasure=false; defer_all=false; terminal_snapshot={}
	CampaignProgress.pending={}; CampaignProgress.last_entry={}
	if mode == "natural_pickup":
		var prior_path:="res://docs/evidence_packets/runtime_observations/treasure/preceding_party.json"
		check(FileAccess.file_exists(prior_path), "curated exact previous Ohm victory party exists")
		var previous: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(prior_path))
		CampaignProgress.pending={"schema":CampaignProgress.SCHEMA,"scenario_path":"res://content/battles/gol_road_battle.json",
			"carry":previous["carry"],"from_scenario_id":"battle_004_level1"}
	if mode == "resume_pool":
		check(FileAccess.file_exists(TREASURE_OUT+"world-carry.json"), "actual campaign route left its carried reward pool")
		CampaignProgress.pending={"schema":CampaignProgress.SCHEMA,"scenario_path":"res://content/battles/gol_road_battle.json",
			"carry":JSON.parse_string(FileAccess.get_file_as_string(TREASURE_OUT+"world-carry.json")),"from_scenario_id":"world_map_scene"}
		pause_on_treasure=true
	scene = VillageScene.instantiate() if mode == "full" else GolScene.instantiate()
	if mode not in ["natural_pickup", "resume_pool"]: scene.startup_mode = "dev_first_control"
	root.add_child(scene); current_scene=scene
	scene.settlement_controller.checkpoint_path = TREASURE_OUT + mode + ".save"
	setup_note = "Formal Gol from the exact previously rendered unmodified Ohm victory carry: Leonard Lv2/EXP87, Hu Lv4/EXP32, actual gear/items/gold and generation cursor. Original opening, source boxes and ordinary gameplay RNG; no new stat or inventory fixture edits. The historical victory carry is a reproducible starting record, not a newly played Ohm run."
	if mode == "resume_pool": setup_note="Explicit next-formal-visit entry fixture using the exact real campaign carry; only the destination is selected by the harness, not by a claimed original world event."
	if mode in ["full", "duplicates", "attack", "defeat", "victory"]:
		scene.set_process(false)
		var loop := run_treasure_tests.placed(1, "leonard", 0) if mode == "full" else run_treasure_tests.placed(2, "hu", 0 if mode == "duplicates" else 1)
		var actor := BattlePlayLoop._unit(loop, "leonard" if mode == "full" else "hu")
		if mode == "full":
			actor["inventory"] = [241,241,241,241,241,241,241,241]
			actor["equipment"] = actor["equipment"].filter(func(row): return row["slot"] != "accessory2")
			actor["equipment"].append({"slot":"accessory2", "item_code":227})
			actor["permanent_gains"]["attack_power"] = 3
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor, "no_magic", 2)["changes"], true)
			actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"]), true)
			setup_note = "Ohm source box; Leonard starts on its tile with eight241, White Wings, permanent attack+3 and two-turn silence. Source contents unchanged."
		elif mode == "duplicates":
			setup_note = "Gol source west box; Hu starts on its tile. Default gear/inventory/abilities, duplicate source items retained."
		elif mode == "attack":
			var victim:=BattlePlayLoop._unit(loop,"actor028_2")
			victim["hp"]=1; actor["hit_bonus_accum"]=1000
			for offset in BattlePlayLoop.weapon_pattern(loop,actor)["offsets"]:
				victim["coord"]=actor["coord"]+Vector2i(int(offset[0]),int(offset[1]))
				if BattlePlayLoop.TraversalRules.placement_error(victim,loop["units"],loop["tiles"],loop["map_size"])=="":break
			victim["ai_home_coord"]=victim["coord"]
			setup_note="Hu begins on real Gol east box; one existing raider1HP placed in legal bow range and Hu hit compensation1000. Actual attack/loot/EXP finishes before discovery; no RNG substitution or fabricated box contents."
		elif mode == "defeat":
			actor["hp"] = 1
			actor["growth_profile"]["source"]["speed"] += 500
			actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"]), true)
			var enemy := BattlePlayLoop._unit(loop, "actor028_1")
			enemy["growth_profile"]["source"]["attack_power"] += 5000
			enemy["growth_profile"]["source"]["speed"] += 300
			enemy.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(enemy, loop["equipment_items"]), true)
			enemy["hit_bonus_accum"] = 1000
			enemy["coord"] = actor["coord"] + Vector2i.RIGHT; enemy["ai_home_coord"] = enemy["coord"]
			# Hu may discover before the enemy responds. This route verifies that an
			# already committed chest stays collected at actual defeat and on F9.
			loop = run_gol_road_tests.owned_turn(loop, "hu")
			setup_note = "Gol east box; Hu1HP on the box, fast Hu then adjacent lethal accurate raider. Defeat is caused by the real subsequent AI attack."
		else:
			loop=BattlePlayLoop._resolve_outcome(run_gol_road_tests.WinfailScenarioRules.run_event_hooks(run_gol_road_tests.ready_event(run_treasure_tests.initial())))
			actor=BattlePlayLoop._unit(loop,"hu")
			actor["coord"]=loop["treasure_source"]["chests"][1]["coord"]; actor["ai_home_coord"]=actor["coord"]
			actor["equipment"].append({"slot":"accessory2","item_code":227})
			actor["growth_profile"]["source"]["speed"]+=300; actor["hit_bonus_accum"]=1000
			actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
			var guards: Array=loop["units"].filter(func(a):return a["actor_id"]=="023")
			for index in range(2,guards.size()): BattlePlayLoop._set_unit_defeated(loop,guards[index]["id"],true)
			guards[0]["hp"]=1
			for offset in BattlePlayLoop.weapon_pattern(loop,actor)["offsets"]:
				guards[0]["coord"]=actor["coord"]+Vector2i(int(offset[0]),int(offset[1]))
				if BattlePlayLoop.TraversalRules.placement_error(guards[0],loop["units"],loop["tiles"],loop["map_size"])=="":break
			guards[0]["ai_home_coord"]=guards[0]["coord"]
			loop=run_gol_road_tests.owned_turn(loop,"hu")
			scene.script_cutscene_consumed=1
			setup_note="Explicit second-phase terminal preconditions: arrival already played; two pursuers remain, first1HP in legal bow range. Hu on actual east box, White Wings, speed+300 and hit compensation1000. Real Wait/discovery/second bow action invokes the source victory and outro; not natural encounter completion."
		scene.apply_loop(loop, "test")
		if mode=="victory": scene.mark_cutscene_messages_shown("event_0",scene.first_battle_scenario["scenario_rules"]["status_timelines"]["event_0"]["events"])
		for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art); art.queue_free()
		scene.unit_grid_coords.clear(); scene.resume_turn_presentation()
		scene.center_camera_on_grid(actor["coord"])
		scene.set_process(true)
	initial_state = scene.play_loop.duplicate(true)
	check(initial_state["scenario_ok"], "formal treasure scene initializes: " + str(initial_state.get("scenario_error", "")))
	var view = scene.get_node("BattlePresentation")
	view.cutin.released.connect(arrow_release); view.cutin.impact.connect(arrow_impact)
	await settle("")
	await shot("first-control")


func settle(id: String, terminal: bool = false) -> void:
	for _attempt in range(9000):
		check(scene.play_loop.get("scenario_ok", false), "live treasure battle valid: " + str(scene.play_loop.get("scenario_error", "")))
		var view = scene.get_node("BattlePresentation")
		var latest: Dictionary = scene.play_loop.get("last_combat", {})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):
			receipt_sequences[latest["sequence"]]=true; receipts.append(latest.duplicate(true))
		for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
			if audio.playing and audio.stream != null: sounds[audio.stream.resource_path]=true
		if scene.treasure_view != null and scene.treasure_view.busy():
			check(not scene.action_menu.visible and not scene.settlement_controller.panel.visible and not scene.settlement_controller.quiet(), "treasure discovery blocks next controls, loot and save")
			var sequence: int = scene.treasure_view._active_sequence
			if not discovery_seen.has(sequence):
				discovery_seen[sequence]=true; await shot("discovery-" + str(sequence))
		if view.dialogue_active():
			if not view._dialogue_messages.is_empty() and str(view._dialogue_messages[0].get("speaker_id"))=="2" and not observed.has("hu_portrait"):
				check(view.dialogue_view.visible and view.dialogue_view.portrait.texture!=null and view.dialogue_view.speaker_label.text.contains("琥"),"actual defeat dialogue displays Hu's source portrait")
				observed["hu_portrait"]=view.dialogue_view.portrait.texture.resource_path
				await shot("hu-defeat-dialogue")
			await key(KEY_SPACE)
		if scene.opening_coordinator != null and scene.opening_coordinator.active and scene.scene_timeline.current_event().get("kind") == "dialogue_message_id": await key(KEY_SPACE)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			if pause_on_treasure and scene.play_loop["settlement"].get("source_kind") in ["treasure", "campaign"]: return
			if defer_all or loot.rows.is_empty() or loot.first_empty_slot() < 0: await click(loot.finish_button)
			else:
				await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
		if scene.growth_panel.visible:
			var panel=scene.growth_panel
			if int(panel.source_unit["pending_stat_points"]) > 0:
				for i in range(int(panel.source_unit["pending_stat_points"])):
					var stat: String = ["str","dex","mind","con"][i%4]
					if panel.choices[stat]["plus"].disabled: stat="con"
					await click(panel.choices[stat]["plus"])
				await click(panel.confirm_button)
			else: await escape()
		if view.battle_finished: return
		if not terminal and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.growth_panel.visible and not scene.ScriptPresentation.pending(scene) and not scene.treasure_view.busy():
			if id == "" or str(scene.selected_unit_id) == id: return
		await create_timer(0.02).timeout
	check(false, "bounded treasure wait exhausted")


func open_here() -> void:
	pause_on_treasure=true
	var before: Dictionary=scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("WaitCommand")); await settle("")
	check(scene.settlement_controller.panel.visible and BattlePlayLoop.Treasure.awaiting_handoff(scene.play_loop), "actual Wait opens source treasure before action handoff")
	for key_name in ["gold","global_rng","damage_rng"]:
		check(scene.play_loop[key_name] == before[key_name], "opening does not consume unrelated value: " + key_name)
	await shot("loot")


func natural_treasure() -> void:
	var goal := Vector2i(15,14)
	for _action in range(16):
		var actor := BattlePlayLoop.unit(scene.play_loop, scene.selected_unit_id)
		if actor["coord"] == goal: break
		var choices := BattlePlayLoop.movement_cells(scene.play_loop)
		choices.sort_custom(func(a,b): return absi(a.x-goal.x)+absi(a.y-goal.y) < absi(b.x-goal.x)+absi(b.y-goal.y))
		if not choices.is_empty() and choices[0] != actor["coord"]:
			await move_to(choices[0])
			if choices[0] == goal: break
		await click(scene.action_menu.get_node("WaitCommand")); await settle("")
	check(BattlePlayLoop.unit(scene.play_loop, scene.selected_unit_id)["coord"] == goal, "unchanged starting party walks to the real source east chest")
	var moved: Dictionary=scene.play_loop.duplicate(true)
	check(moved["pending_move"] and moved["treasures"]["opened_ids"].is_empty(), "walking onto the box has not claimed it")
	await save_restore()
	await key(KEY_ESCAPE)
	check(scene.interaction_state == "move_select", "move rollback returns to the existing retry-selection stage")
	check(BattlePlayLoop.unit(scene.play_loop, scene.selected_unit_id)["coord"] == moved["pending_move_from"] and scene.play_loop["treasures"]["opened_ids"].is_empty(), "actual Esc rolls back provisional movement, not a committed chest")
	await key(KEY_ESCAPE); await settle("")
	await move_to(goal)
	await open_here()
	var panel=scene.settlement_controller.panel
	var found: Dictionary=scene.play_loop.duplicate(true)
	check(found["settlement"]["pending"].map(func(e): return e["code"]) == [2,241], "natural east chest queues the two original items")
	check(panel._recipient=="leonard","the chest opener owns the get-item window like the original")
	await click(panel.rows[0]); await click(panel.storage_button)
	check(scene.play_loop == found and not panel.holding(), "putting the held item back preserves both source items")
	await click(panel.rows[0])
	check(panel.holding() and panel.first_empty_slot()>=0,"the held source item has a free bag slot to land in")
	await key(KEY_ESCAPE)
	check(scene.play_loop["settlement"]["pending"].size()==1,"actual Esc drops the held item into the first free slot like the original right click")
	await save_restore()
	check(scene.play_loop["settlement"]["pending"].size() == 1, "partial pickup survives actual F9")
	pause_on_treasure=false; defer_all=true
	await click(panel.finish_button); await settle("")
	check(scene.action_menu.visible and not BattlePlayLoop.Treasure.awaiting_handoff(scene.play_loop),"natural pickup transaction fully returns to ordinary player control")
	check(scene.play_loop["settlement"]["pending"].any(func(e): return str(e["id"]).begins_with("treasure:")), "natural deferred source item survives the completed handoff")
	await save_restore(); await shot("next-action-deferred")


func full_treasure() -> void:
	await save_restore(); await open_here()
	var panel=scene.settlement_controller.panel
	var before: Dictionary=scene.play_loop.duplicate(true)
	await click(panel.rows[0]); check(panel.holding() and panel.first_empty_slot()<0, "full bag leaves the picked item in hand with no free slot")
	await key(KEY_ESCAPE)
	check(scene.play_loop == before and panel.holding(), "Esc cannot auto-place into a full bag; the item stays in hand")
	await click(panel.storage_button)
	check(scene.play_loop == before and not panel.holding(), "returned item preserves inventory and source treasure")
	await click(panel.rows[0]); await shot("exchange-preview"); await click(panel.slots[0])
	check(BattlePlayLoop.unit(scene.play_loop,"leonard")["inventory"].has(202) and scene.play_loop["settlement"]["pending"][0]["code"] == 241, "real full-bag exchange retains the displaced medicine")
	await save_restore()
	pause_on_treasure=false; defer_all=true
	await click(panel.finish_button); await settle("leonard")
	check(scene.play_loop["extra_action"]["pending"] and BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"] == initial_state["units"].filter(func(a): return a["id"]=="leonard")[0]["status_counters"], "independent second action arrives without an early silence tail")
	await change_gear(202,"accessory1")
	var equipped:=BattlePlayLoop.unit(scene.play_loop,"leonard")
	check(BattlePlayLoop.EquipmentRules.equipped_code(equipped["equipment"],"accessory1") == 202 and equipped["permanent_gains"] == BattlePlayLoop.unit(before,"leonard")["permanent_gains"] and equipped["exp"] == BattlePlayLoop.unit(before,"leonard")["exp"], "picked-up source accessory actually equips without reapplying permanent growth or awarding EXP")
	await click(scene.action_menu.get_node("WaitCommand")); await settle("")
	check(scene.play_loop["treasures"]["receipts"].size()==1, "second action and equip never reopen the source chest")
	await save_restore(); await shot("second-action-complete")


func duplicate_treasure() -> void:
	await open_here()
	var panel=scene.settlement_controller.panel
	check(panel.rows.size()==2 and scene.play_loop["settlement"]["pending"].map(func(e):return e["code"])==[244,244,254], "west chest keeps both original copies of the MP medicine as one (code, 2) row")
	for _copy in range(2): await click(panel.rows[0]); await click(panel.slots[panel.first_empty_slot()])
	check(BattlePlayLoop.unit(scene.play_loop,"hu")["inventory"].count(244)==2, "two independent real placements grant two and only two medicines")
	await save_restore(); await shot("duplicates-claimed")
	await click(panel.drop_button); await click(panel.rows[0]); await click(panel.storage_button)
	check(scene.play_loop["settlement"]["pending"].size()==1 and not panel._abandon_armed, "leaving the 丟棄 icon cancels the discard and preserves the final source item")
	await click(panel.drop_button); await click(panel.drop_button)
	check(scene.play_loop["settlement"]["abandoned"].size()==1, "explicit discard removes only the final pending item")
	pause_on_treasure=false
	await settle("")
	check(scene.play_loop["treasures"]["opened_ids"].size()==1, "subsequent action handoff never resets the discarded box")


func defeat_treasure() -> void:
	await open_here()
	var panel=scene.settlement_controller.panel
	await save_restore()
	pause_on_treasure=false; defer_all=true
	await click(panel.finish_button); await settle("",true)
	check(BattleOutcome.lost(scene.play_loop) and scene.play_loop["treasures"]["opened_ids"].size()==1, "real AI defeat retains the already committed chest and pending loot")
	await save_restore(); await shot("defeat")
	terminal_snapshot=scene.play_loop.duplicate(true)
	await restart_gol()
	check(scene.play_loop["treasures"]["opened_ids"].is_empty() and scene.play_loop["settlement"].is_empty(), "real restart restores source chests without carrying the failed attempt's awards")


func attack_treasure() -> void:
	pause_on_treasure=true; defer_all=true
	await save_restore()
	await attack("actor028_2"); await settle("")
	check(BattlePlayLoop.unit(scene.play_loop,"actor028_2")["defeated"] and scene.play_loop["last_combat"]["attacker_id"]=="hu","actual bow kill completes before collecting the box")
	var rewards: Dictionary=scene.play_loop["settlement"]
	check(rewards["source_kind"]=="treasure" and rewards["combat_sequence"]==scene.play_loop["last_combat"]["sequence"] and rewards["sequence"]>rewards["combat_sequence"],"post-attack discovery retains independent loot provenance without replaying combat")
	check(scene.play_loop["treasures"]["receipts"].size()==1 and BattlePlayLoop.Treasure.awaiting_handoff(scene.play_loop),"combat, loot and EXP feedback precede exactly one held treasure completion")
	await save_restore(); await shot("after-attack-loot")
	pause_on_treasure=false
	await click(scene.settlement_controller.panel.finish_button); await settle("")
	check(scene.play_loop["treasures"]["receipts"].size()==1,"post-discovery action handoff cannot replay the lethal attack's box")


func victory_treasure() -> void:
	await open_here(); await save_restore()
	pause_on_treasure=false; defer_all=true
	await click(scene.settlement_controller.panel.finish_button); await settle("hu")
	check(scene.play_loop["extra_action"]["pending"],"source treasure completion retains the independently granted second action")
	var target: String=scene.play_loop["units"].filter(func(a):return a["actor_id"]=="023" and BattlePlayLoop.Presence.living(a))[0]["id"]
	await attack(target); await settle("",true)
	check(BattleOutcome.won(scene.play_loop) and scene.play_loop["winfail_runtime"]["resolved"]["key"]=="win_0","real bow settlement invokes the original second-phase victory predicate")
	check(scene.play_loop["settlement"]["pending"].any(func(e):return str(e["id"]).begins_with("treasure:")),"actual lethal victory preserves the earlier deferred box items")
	var frozen: Dictionary=scene.play_loop.duplicate(true)
	check(BattlePlayLoop.step_ai_turn(frozen)==frozen and BattlePlayLoop.finish_exhausted_action(frozen)==frozen,"committed victory freezes further treasure, extra-action and tail work")
	await save_restore(); await shot("victory-deferred")
	FileAccess.open(TREASURE_OUT+"victory-producer.json",FileAccess.WRITE).store_string(JSON.stringify({
		"pid":OS.get_process_id(),"save_sha256":run_gol_road_tests.BattleCheckpoint.digest(FileAccess.get_file_as_bytes(TREASURE_OUT+"victory.save"))}))


func treasure_campaign() -> Dictionary:
	setup_note="Fresh process restores the actual victory-route final-strike checkpoint (that route has declared terminal preconditions), then uses real result/camp controls. No new victory assignment or carry reconstruction."
	scene.settlement_controller.checkpoint_path=TREASURE_OUT+"victory.save"
	var producer: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(TREASURE_OUT+"victory-producer.json"))
	check(int(producer.get("pid",-1))>0 and int(producer["pid"])!=OS.get_process_id(),"campaign recovery really runs in a different process from the victory producer")
	check(producer["save_sha256"]==run_gol_road_tests.BattleCheckpoint.digest(FileAccess.get_file_as_bytes(scene.settlement_controller.checkpoint_path)),"cross-process recovery uses the unchanged actual victory file")
	var saved:=run_gol_road_tests.BattleCheckpoint.read(scene.settlement_controller.checkpoint_path, scene.play_loop)
	check(saved["ok"] and BattleOutcome.won(saved["snapshot"]["loop"]),"actual final-strike treasure victory checkpoint exists")
	defer_all=true
	await key(KEY_F9); await settle("",true)
	check(scene.play_loop==saved["snapshot"]["loop"],"fresh process restores exact actual treasure victory without another discovery")
	var final: Dictionary=scene.play_loop.duplicate(true)
	var source:=final.duplicate(true); source["scenario_id"]=scene.first_battle_scenario["id"]
	var carry: Dictionary=JSON.parse_string(JSON.stringify(BattlePlayLoop.CampaignCarryRules.capture(source)))
	check(carry.get("pending_rewards",{}).get("items",[]).size()>0,"actual victory carry contains deferred items")
	await shot("restored-victory")
	for _frame in range(100):
		if scene.get_node("BattlePresentation").battle_finished: break
		await process_frame
	scene.campaign_progress.start_next_battle()
	var stages: Array=[]
	for _frame in range(9000):
		await create_timer(0.02).timeout
		if not is_instance_valid(current_scene): continue
		scene=current_scene
		var path: String=scene.scenario_path
		if not stages.has(path):
			stages.append(path)
			check(JSON.parse_string(JSON.stringify(scene.campaign_handoff.get("carry",{})))==carry,"camp/world preserves complete party and deferred treasure")
			await shot("stage-"+path.get_file().get_basename())
		if scene.world_map_runtime!=null and scene.world_map_runtime.active: break
		if scene.opening_coordinator!=null and scene.opening_coordinator.active and scene.scene_timeline.current_event().get("kind")=="dialogue_message_id": await key(KEY_SPACE)
	check(stages==["res://content/battles/story_055.json","res://content/battles/story_056.json","res://content/world/world_map_scene.json"],"real treasure victory follows both source camps back to Gol")
	check(CampaignProgress.load_progress().get("carry",{})==carry,"persistent campaign retains exact deferred treasure")
	FileAccess.open(TREASURE_OUT+"world-carry.json",FileAccess.WRITE).store_string(JSON.stringify(carry,"  "))
	return {"final":final,"carry":carry,"stages":stages,"fresh_process":true,"producer":producer,"consumer_pid":OS.get_process_id()}


func resume_pool() -> void:
	var panel=scene.settlement_controller.panel
	check(panel.visible and scene.play_loop["settlement"]["source_kind"]=="campaign", "next visit presents the retained pool, not invented combat loot")
	var before: Dictionary=scene.play_loop.duplicate(true)
	await click(panel.rows[0]); await click(panel.slots[panel.first_empty_slot()])
	check(scene.play_loop["settlement"]["pending"].size()==before["settlement"]["pending"].size()-1 and scene.play_loop["treasures"]["opened_ids"].is_empty(),"actual carried-item pickup does not open a new visit's source box")
	await save_restore(); await shot("carried-item-claimed")
	pause_on_treasure=false; defer_all=true
	await click(panel.finish_button); await settle("")


func shot(label: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(TREASURE_OUT+name)==OK,"capture "+label)
	if not frames.has(name): frames.append(name)


func write_receipt(filename: String) -> void:
	FileAccess.open(TREASURE_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({
		"schema":"hsl_treasure_review.v1","native_execution":false,"real_control_events":true,
		"pid":OS.get_process_id(),"screen":root.current_screen,"time_scale":Engine.time_scale,
		"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"isolated_user_dir":OS.get_user_data_dir(),
		"routes":routes,"frames":frames,"checks":check_count,"failures":failures,
		"active":{} if not is_instance_valid(scene) else {"mode":mode,"setup":setup_note,"state":scene.play_loop,
			"selected":scene.selected_unit_id,"interaction":scene.interaction_state,"decisions":player_decisions,
			"treasure_busy":scene.treasure_view.busy() if scene.treasure_view!=null else false}},"  "))

extends "res://tests/capture_ohm_village_review.gd"
## Reuses input drivers, never the old encounter fixture. The natural route uses
## the unchanged level2 source roster, actual combat RNG and original script.
const run_gol_road_tests = preload("res://tests/run_gol_road_tests.gd")
const GolScene = preload("res://game/battle/development/GolRoad.tscn")
const GOL_OUT := "res://ignored/gol-road-review/"
var installations: Array = []
const HEAL := "magic:magicWATER:magicCode06"
var saved_arrival := false


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "HSL-Review-Gol-" + str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Gol review requires rendering");quit(2);return
	root.title = "HSL Gol Road Gameplay Review"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(GOL_OUT)
	started = Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func(): check(false, "bounded Gol review timeout"))
	var names: Array = ["natural"] if OS.get_cmdline_user_args().is_empty() else Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		check(mode in ["natural", "arrival", "defeat_tina", "campaign"], "known Gol review route")
		await setup_gol()
		await shot("first-control")
		var extension := {}
		if mode == "campaign":
			extension = await continue_campaign()
		else:
			await save_restore()
			if mode == "natural":
				await play_natural()
				check(scene.play_loop.get("winfail_runtime", {}).get("fired", []).any(func(r): return r["key"] == "event_0"), "ordinary play reaches the actual Tina/pursuit event")
				check(BattlePlayLoop.unit(scene.play_loop, "tina").get("actor_id") == "002" and scene.play_loop["units"].filter(func(a): return a["actor_id"] == "023").size() == 4, "real source event creates one priest and four pursuers")
				check(BattleOutcome.won(scene.play_loop), "natural two-stage encounter is won through actual inputs")
			elif mode == "arrival": await play_arrival()
			else: await click(scene.action_menu.get_node("WaitCommand")); await settle("", true)
			if mode == "defeat_tina":
				check(BattleOutcome.lost(scene.play_loop) and scene.play_loop["winfail_runtime"]["resolved"]["key"] == "fail_2", "real pursuer attack activates the newly registered Tina defeat condition")
				await save_restore()
			var frozen: Dictionary = scene.play_loop.duplicate(true)
			extension = {"final":frozen}
			if mode == "defeat_tina":
				check(BattlePlayLoop.finish_exhausted_action(frozen) == frozen and BattlePlayLoop.step_ai_turn(frozen) == frozen, "defeat freezes the script birth stream and all further actions")
				await restart_gol()
				extension["restarted"] = true
		routes.append({"mode": mode, "initial": initial_state, "receipts": receipts, "decisions": player_decisions, "ai_actions": ai_receipts,
			"installations": installations, "opening_messages": opening_messages, "learning_texts": learning_texts, "sounds": sounds.keys(), "saves": saves})
		routes.back().merge(extension, true)
		await close_scene()
		write_receipt("progress.json")
	write_receipt("receipt.json")
	print("GOL_ROAD_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size(), " checks=", check_count)
	quit(0 if failures.is_empty() else 1)


func setup_gol() -> void:
	impacts=[];events=[];sounds={};observed={};saves=0;receipts=[];receipt_sequences={};item_receipts=[];item_seen={};serial=0
	learning_texts=[];ai_receipts=[];recorded_ai={};arrow_signals=[0,0];opening_messages=[];arrow_receipt={};player_decisions=[];installations=[];saved_arrival=false
	CampaignProgress.pending = {};CampaignProgress.last_entry = {}
	scene = GolScene.instantiate()
	if mode != "natural": scene.startup_mode = "dev_first_control"
	root.add_child(scene);current_scene = scene
	scene.settlement_controller.checkpoint_path = GOL_OUT + mode + ".save"
	if mode in ["arrival", "defeat_tina"]:
		scene.set_process(false)
		var loop := run_gol_road_tests.attack_fixture()
		if mode == "arrival":
			BattlePlayLoop._unit(loop, "leonard")["hp"] = 10
			# Isolate post-join support and queue review: pursuit/Wait still run, but
			# these test guards cannot kill the patient before the healing input.
			TestSuite.own(loop, "script_actor_source")["templates"]["obj_Story_Level2_Enemy23"]["actor"]["no_attack"] = true
		else:
			loop = BattlePlayLoop._resolve_outcome(run_gol_road_tests.WinfailScenarioRules.run_event_hooks(run_gol_road_tests.ready_event(run_gol_road_tests.initial())))
			var target := BattlePlayLoop._unit(loop, "tina")
			target["hp"] = 1
			var guard: Dictionary = loop["units"].filter(func(a): return a["actor_id"] == "023")[0]
			guard["growth_profile"]["source"]["attack_power"] += 5000
			guard["growth_profile"]["source"]["speed"] += 300
			guard.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(guard, loop["equipment_items"]), true)
			guard["hit_bonus_accum"] = 1000
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				guard["coord"] = target["coord"] + offset
				if BattlePlayLoop.TraversalRules.placement_error(guard, loop["units"], loop["tiles"], loop["map_size"]) == "": break
			guard["ai_home_coord"] = guard["coord"]
			TestSuite.own(loop, "ai_profiles")["actors"]["023"]["profile"]["find_type"] = loop["ai_profiles"]["find_types"]["AI_HPMIN"]
			var hu := BattlePlayLoop._unit(loop, "hu")
			hu["growth_profile"]["source"]["speed"] += 500
			hu.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(hu, loop["equipment_items"]), true)
			loop = run_gol_road_tests.owned_turn(loop, "hu")
			scene.script_cutscene_consumed = 1 # Explicit already-played arrival fixture.
		scene.apply_loop(loop, "test")
		if mode == "defeat_tina":
			# A pre-played cutscene fixture must retain its message receipts as well
			# as its cursor, exactly as a real quiet checkpoint does.
			scene.mark_cutscene_messages_shown("event_0", scene.first_battle_scenario["scenario_rules"]["status_timelines"]["event_0"]["events"])
		for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art);art.queue_free()
		scene.unit_grid_coords.clear();scene.resume_turn_presentation()
		scene.center_camera_on_grid(BattlePlayLoop.unit(loop, "hu")["coord"])
		scene.set_process(true)
	initial_state = scene.play_loop.duplicate(true)
	check(initial_state["scenario_ok"] and initial_state["units"].size() == (12 if mode == "defeat_tina" else 7), "source roster matches this route's declared starting phase")
	var view = scene.get_node("BattlePresentation")
	view.cutin.released.connect(arrow_release);view.cutin.impact.connect(arrow_impact)
	await settle("")


func play_arrival() -> void:
	await attack("actor028_2"); await settle("hu")
	check(scene.play_loop["units"].size() == 12 and installations.size() == 5, "actual lethal bow triggers and presents exactly five installations")
	check(scene.play_loop["extra_action"]["pending"], "loot, arrival and dialogue all finish before Hu's independent second action")
	await save_restore()
	for _i in range(16):
		if scene.selected_unit_id == "tina": break
		await click(scene.action_menu.get_node("WaitCommand")); await settle("")
	check(scene.selected_unit_id == "tina", "new registered priest receives a real turn in the shared queue")
	var before: Dictionary = scene.play_loop.duplicate(true)
	await cast_stat(HEAL, "leonard"); await settle("")
	check(BattlePlayLoop.unit(scene.play_loop, "tina")["mp"] == BattlePlayLoop.unit(before, "tina")["mp"] - 6 and BattlePlayLoop.unit(scene.play_loop, "leonard")["hp"] > BattlePlayLoop.unit(before, "leonard")["hp"], "new actor performs paid source healing through actual menu and target input")
	check(scene.play_loop["script_actor_transactions"] == before["script_actor_transactions"] and scene.play_loop["script_actor_transactions"].size() == 1, "healing and queue wrap never repeat the birth transaction")
	await save_restore()


func restart_gol() -> void:
	var old_id: int = scene.get_instance_id()
	reload_current_scene()
	for _i in range(150):
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id: scene = current_scene; break
	check(scene.get_instance_id() != old_id and not BattleOutcome.decided(scene.play_loop) and scene.play_loop["units"].size() == 7 and BattlePlayLoop.unit(scene.play_loop, "tina").is_empty(), "actual restart returns to phase one without retaining an event-created priest")
	await shot("restarted")


func continue_campaign() -> Dictionary:
	# Continue the exact on-disk victory of the unmodified natural route, in a new
	# process. Do not synthesize a win or reconstruct any actor/cost/EXP here.
	scene.settlement_controller.checkpoint_path = GOL_OUT + "natural.save"
	var saved := run_gol_road_tests.BattleCheckpoint.read(scene.settlement_controller.checkpoint_path, scene.play_loop)
	check(saved["ok"] and BattleOutcome.won(saved["snapshot"]["loop"]), "the natural-play victory checkpoint exists and matches current source configuration")
	await key(KEY_F9); await settle("", true)
	check(scene.play_loop == saved["snapshot"]["loop"], "a fresh process restores the complete actual two-stage victory without replay")
	var final: Dictionary = scene.play_loop.duplicate(true)
	var campaign_source := final.duplicate(true)
	# Campaign metadata identifies the scenario by its declared id, not its path.
	# Mirror that serialization input without modifying the actual battle snapshot.
	campaign_source["scenario_id"] = scene.first_battle_scenario["id"]
	var carry: Dictionary = JSON.parse_string(JSON.stringify(BattlePlayLoop.CampaignCarryRules.capture(campaign_source)))
	await shot("restored-victory")
	for _i in range(100):
		if scene.get_node("BattlePresentation").battle_finished: break
		await process_frame
	check(scene.campaign_progress.start_next_battle(), "the actual victory hands off to the registered camp continuation")
	var stages: Array = []
	for _i in range(9000):
		await create_timer(0.02).timeout
		if not is_instance_valid(current_scene): continue
		scene = current_scene
		var path: String = scene.scenario_path
		if not stages.has(path):
			stages.append(path)
			# Compare both sides after the same JSON representation: Godot's nested
			# integer arrays otherwise differ from parsed numeric arrays despite no
			# value changing. Fractional/missing/duplicated records still fail.
			var actual_carry: Dictionary = JSON.parse_string(JSON.stringify(scene.campaign_handoff.get("carry", {})))
			check(actual_carry == carry, "camp/world handoff preserves all three actors and the exact saved generation cursor")
			await shot("stage-" + path.get_file().get_basename())
		if scene.world_map_runtime != null and scene.world_map_runtime.active: break
		if scene.opening_coordinator != null and scene.opening_coordinator.active and scene.scene_timeline.current_event().get("kind") == "dialogue_message_id": await key(KEY_SPACE)
	check(stages == ["res://content/battles/story_055.json", "res://content/battles/story_056.json", "res://content/world/world_map_scene.json"], "source victory continues through both actual camps and returns to the map")
	check(scene.world_map_runtime != null and scene.world_map_runtime.current_point() == 2, "party returns to Gol Road point two")
	check(CampaignProgress.load_progress().get("carry", {}) == carry and carry["units"].has("tina"), "persistent campaign JSON retains the newly joined priest rather than only the original pair")
	await shot("carried-party")
	return {"final":final, "campaign_stages":stages, "carry":carry, "fresh_process_checkpoint":true}


func _process(delta: float) -> bool:
	super._process(delta)
	if not is_instance_valid(scene) or scene.play_loop.is_empty(): return false
	if scene.play_loop.has("script_actor_transactions") and not scene.play_loop["script_actor_transactions"].is_empty() and scene.script_cutscene_consumed == 0:
		check(scene.actor_node_for_unit("tina") == null, "committed arrival is not drawn before its source installation token")
	if scene.opening_coordinator != null and scene.opening_coordinator.active and scene.opening_coordinator.cutscene_mode:
		check(not scene.action_menu.visible, "script actor motion/dialogue blocks all player action handoff")
		var event: Dictionary = scene.scene_timeline.current_event()
		var row: Dictionary = event.get("script_actor_receipt", {})
		if row.has("install") and not installations.any(func(r): return r["source_event_id"] == event["id"]):
			installations.append({"source_event_id": event["id"], "install": row["install"].duplicate(true), "time_ms": Time.get_ticks_msec()})
			shot("install-" + str(installations.size()))
		if event.get("kind") == "dialogue_message_id" and not observed.has(event["id"]):
			observed[event["id"]] = true
			shot("script-" + str(event.get("message_id", "")))
	return false


func save_restore() -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	await key(KEY_F5)
	var stored := run_gol_road_tests.BattleCheckpoint.read(scene.settlement_controller.checkpoint_path, before)
	check(stored["ok"] and stored["snapshot"]["loop"] == before, "actual Gol F5 stores the exact stage, new members and growth stream")
	await key(KEY_F9)
	check(scene.play_loop == before, "Gol F9 cannot recreate actors, repeat movement or resample birth")
	saves += 1
	await shot("restored-" + str(saves))


func shot(label: String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	var name := mode + "-" + label + ".png"
	check(root.get_texture().get_image().save_png(GOL_OUT + name) == OK, "capture " + label)
	if not frames.has(name): frames.append(name)


func write_receipt(filename: String) -> void:
	FileAccess.open(GOL_OUT + filename, FileAccess.WRITE).store_string(JSON.stringify({
		"schema": "hsl_gol_road_review.v1", "native_execution": false, "real_control_events": true,
		"pid": OS.get_process_id(), "screen": root.current_screen, "time_scale": Engine.time_scale,
		"elapsed_seconds": (Time.get_ticks_msec() - started)/1000.0, "isolated_user_dir": OS.get_user_data_dir(),
		"setup": "Natural is the unchanged formal GolRoad source roster and event. Arrival sets three earlier raider deaths, one 1HP raider, wounded Leonard, fast Hu with White Wings and test guards no_attack before any input; real attack triggers birth, source dialogue and current turns. Defeat starts after an explicitly pre-played source event with Tina1HP and one adjacent, fast, accurate lethal pursuer. Campaign reads the exact natural victory checkpoint in a fresh process, with no synthetic outcome. No post-input health, ability, resource, RNG or model injection. Source global RNG/timing equivalence is not claimed.",
		"routes": routes, "frames": frames, "checks": check_count, "failures": failures,
		"decisions": player_decisions, "combat_receipts": receipts, "ai_actions": ai_receipts,
		"active": {} if not is_instance_valid(scene) else {"selected": scene.selected_unit_id,
			"interaction": scene.play_loop.get("interaction"), "scenario_error": scene.play_loop.get("scenario_error"),
			"units": scene.play_loop.get("units", []), "last_combat": scene.play_loop.get("last_combat", {}),
			"fired": scene.play_loop.get("winfail_runtime", {}).get("fired", [])}}, "  "))


func play_natural() -> void:
	# Input policy for the actual encounter, not an enemy/player rule change.
	# In particular, a newly joined healer must not inherit the old Ohm driver's
	# unconditional charge into melee. Decisions read only live, visible state.
	for action_index in range(180):
		if BattleOutcome.decided(scene.play_loop): break
		var loop: Dictionary = scene.play_loop
		if not saved_arrival and not loop["script_actor_transactions"].is_empty():
			saved_arrival = true
			await save_restore()
		var actor := BattlePlayLoop.unit(loop, scene.selected_unit_id)
		var foes: Array = loop["units"].filter(func(a): return a["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY and BattlePlayLoop.Presence.living(a))
		var decision := {"actor":actor["id"], "turn":loop["turn"], "coord":actor["coord"], "hp":actor["hp"], "mp":actor["mp"], "stamina":actor["stamina"]}
		player_decisions.append(decision)
		if actor["id"] == "tina" and BattlePlayLoop.command_available(loop, "magic"):
			var patients: Array = loop["units"].filter(func(a): return a["player_commandable"] and BattlePlayLoop.Presence.living(a) and int(a["max_hp"]) - int(a["hp"]) >= 6)
			patients.sort_custom(func(a,b): return float(a["hp"])/a["max_hp"] < float(b["hp"])/b["max_hp"])
			var patient_id := ""
			for patient in patients:
				var ready := BattlePlayLoop.SkillResolutionRules.prepare_cast(actor, patient, loop["units"], HEAL, BattlePlayLoop.skill_fields(loop, HEAL), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"])
				if ready["ok"]: patient_id = patient["id"]; break
			if patient_id != "":
				decision["kind"] = "heal_magic"; decision["target"] = patient_id
				await cast_stat(HEAL, patient_id); await settle(""); continue
		if int(actor["hp"])*3 < int(actor["max_hp"])*2 and actor["inventory"].has(241):
			decision["kind"] = "heal_item"
			await use_item_real(241, actor["id"]); await settle(""); continue
		if actor["id"] == "tina" and int(actor["mp"]) < 6 and actor["inventory"].has(244):
			decision["kind"] = "mp_item"
			await use_item_real(244, actor["id"]); await settle(""); continue
		if actor["id"] == "hu" and BattlePlayLoop.command_available(loop, "special") and BattlePlayLoop.can_use_special(loop, "hu"):
			var fields := BattlePlayLoop.skill_fields(loop, PoisonArrowRules.ID)
			var centers := BattlePlayLoop.SkillTargetRules.candidate_centers(actor, loop["units"], fields, loop["skill_target_data"], loop["map_size"], actor["coord"])
			var selectable := BattlePlayLoop.SkillTargetRules.cells(actor["coord"], fields, loop["skill_target_data"], loop["map_size"])
			centers = centers.filter(func(c): return selectable.has(c))
			if not centers.is_empty():
				decision["kind"] = "poison_arrow"; decision["center"] = centers[0]
				await cast_arrow(centers[0]); await settle(""); continue
		var reachable: Array = foes.filter(func(a): return BattlePlayLoop.Footprint.contact(a, BattlePlayLoop.attack_cells(loop)) is Vector2i)
		if actor["id"] != "tina" and not reachable.is_empty():
			reachable.sort_custom(func(a,b): return int(a["hp"]) < int(b["hp"]))
			decision["kind"] = "ordinary"; decision["target"] = reachable[0]["id"]
			await attack(reachable[0]["id"]); await settle(""); continue
		if not loop["moved_this_action"]:
			var pattern := BattlePlayLoop.weapon_pattern(loop, actor)
			var best: Vector2i = actor["coord"]
			var best_score := 1000000
			var friend := BattlePlayLoop.unit(loop, "leonard")
			for cell in BattlePlayLoop.movement_cells(loop):
				var score := 1000000
				if actor["id"] == "tina":
					var distance := 1000
					for foe in foes: distance = mini(distance, absi(foe["coord"].x-cell.x)+absi(foe["coord"].y-cell.y))
					var ally_distance: int = absi(friend["coord"].x-cell.x)+absi(friend["coord"].y-cell.y)
					score = maxi(0, 5-distance)*100 + maxi(0, ally_distance-3)*10 + absi(cell.x-actor["coord"].x)+absi(cell.y-actor["coord"].y)
				else:
					for foe in foes:
						var delta: Vector2i = foe["coord"]-cell
						var can_hit: bool = pattern["offsets"].any(func(o): return Vector2i(int(o[0]),int(o[1])) == delta)
						score = mini(score, (0 if can_hit else 1000)+(absi(delta.x)+absi(delta.y))*10+int(foe["hp"])/20)
				if score < best_score: best_score = score; best = cell
			if best != actor["coord"]:
				decision["kind"] = "retreat_healer" if actor["id"] == "tina" else "move"; decision["to"] = best
				await move_to(best); continue
		decision["kind"] = "wait"
		await click(scene.action_menu.get_node("WaitCommand")); await settle("")
	check(BattleOutcome.decided(scene.play_loop), "bounded unmodified Gol encounter reaches a real outcome")
	await save_restore()

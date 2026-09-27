extends SceneTree
## Windowed review of a formal battle assembled by tools/hsltools/levels/battle.py
## (`-- --level=6` for 席達鎮; default 6): the opening at remake pacing with every dialogue
## line captured, the first-control frame, then the shared forced-victory fixture with the
## win cutscene's lines and the result page. Output: ignored/battle-<level>-review/*.png +
## manifest.json — visual review input for a player-visible change, not parity proof.
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var level := 6
var OUT := "res://ignored/battle-006-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []
var shots_taken: Dictionary = {}


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Battle review requires a rendering window")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = int(arg.trim_prefix("--level="))
	OUT = "res://ignored/battle-%03d-review/" % level
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	root.title = "HSL Battle %03d Review" % level
	root.size = Vector2i(640, 480)
	create_timer(420).timeout.connect(func(): push_error("Battle review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_%03d.json" % level
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	check(bool(scene.play_loop.get("scenario_ok", false)), "battle scenario loads: " + str(scene.play_loop.get("scenario_error", "")))
	var coordinator = scene.opening_coordinator
	check(coordinator != null and coordinator.active and not coordinator.story_mode, "the formal battle opens through BattleOpeningCoordinator in battle mode")
	if coordinator == null or not bool(scene.play_loop.get("scenario_ok", false)):
		finish()
		return
	await shot("00-framed")
	if level == 73:
		await _complete_level73_event(scene, scene.BattlePlayLoop)
		var event_handoff_073_direct := CampaignProgress.pending if CampaignProgress.has_pending() else CampaignProgress.last_entry
		if not CampaignProgress.has_pending():
			scene.campaign_progress.start_next_battle()
			await process_frame
			event_handoff_073_direct = CampaignProgress.pending if CampaignProgress.has_pending() else CampaignProgress.last_entry
		var expected_map_073_direct := str(CampaignProgress.load_campaign().get("world_map", {}).get("scenario", ""))
		check(expected_map_073_direct != "" and str(event_handoff_073_direct.get("scenario_path", "")) == expected_map_073_direct, "level 73 event_2 hands off to the world map %s (handoff=%s)" % [expected_map_073_direct, str(event_handoff_073_direct)])
		records.append({"result": {"outcome": "event_handoff", "next": event_handoff_073_direct}})
		finish()
		return
	var start_time := Time.get_ticks_msec()
	while coordinator.active and Time.get_ticks_msec() - start_time < 240000:
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", scene.scene_timeline.current_event().get("id", "")))
			await shot_once("dialogue-" + message_id)
			coordinator.handle_input(click())
		await process_frame
	check(not coordinator.active, "the opening reaches first control within the review budget")
	await create_timer(0.4).timeout
	await shot("first-control")
	var units: Array = scene.play_loop["units"]
	records.append({"first_control": {"units": units.size(), "players": units.filter(func(u): return u["player_commandable"]).size(), "interaction": str(scene.play_loop.get("interaction", ""))}})
	# Forced victory (the shared traversal fixture): every living enemy defeated, the
	# outcome resolved, the win cutscene played with its lines captured.
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	if level == 13:
		await prepare_level13_arrival(scene, rules)
	elif level == 28:
		await prepare_level28_scripted_win(scene, rules)
	elif level == 7:
		await prepare_level7_scripted_rounds(scene, rules)
	elif level == 31:
		await prepare_level31_scripted_win(scene, rules)
	elif level == 33:
		await prepare_level33_scripted_win(scene, rules)
	elif level == 36:
		await prepare_level36_scripted_win(scene, rules)
	elif level == 38:
		await prepare_level38_arrival(scene, rules)
	elif level == 12:
		await prepare_level12_scripted_rounds(scene, rules)
	elif level == 17:
		await prepare_level17_scripted_rounds(scene, rules)
	elif level == 34:
		await prepare_level34_scripted_rounds(scene, rules)
	elif level == 902:
		await prepare_level902_arrival(scene, rules)
	# WINFAIL010 arms its first win status from event 3 at round 5; preserve that
	# source-timed phase before the generic review clear fixture.
	# The review clear is a victory-path probe, so protect the controlled roster
	# and keep failure statuses from racing the result while its dialogue settles.
	for protected in scene.play_loop["units"]:
		if protected["battle_actor_role"] == rules.ROLE_PLAYER:
			protected["defeated"] = false
			protected["hp"] = protected["max_hp"]
	scene.play_loop["fail_statuses"] = []
	if level == 73:
		await _complete_level73_event(scene, rules)
		var event_handoff_073 := CampaignProgress.pending if CampaignProgress.has_pending() else CampaignProgress.last_entry
		var expected_map_073 := str(CampaignProgress.load_campaign().get("world_map", {}).get("scenario", ""))
		check(expected_map_073 != "" and str(event_handoff_073.get("scenario_path", "")) == expected_map_073, "level 73 event_2 hands off to the world map %s (handoff=%s)" % [expected_map_073, str(event_handoff_073)])
		records.append({"result": {"outcome": "event_handoff", "next": event_handoff_073}})
		finish()
		return
	if level == 78:
		await _complete_level78_event(scene, rules)
		var handoff := CampaignProgress.pending if CampaignProgress.has_pending() else CampaignProgress.last_entry
		var expected_079 := str(CampaignProgress.load_campaign().get("battles", {}).get("79", {}).get("scenario", ""))
		check(expected_079 != "" and str(handoff.get("scenario_path", "")) == expected_079, "level 78 event_2 hands off to level 79 %s (handoff=%s)" % [expected_079, str(handoff)])
		records.append({"result": {"outcome": "event_handoff", "next": handoff}})
		finish()
		return
	if level == 80 and (scene.play_loop.get("win_statuses", []) as Array).is_empty():
		# WINFAIL080 reaches victory through scripted object progression rather
		# than enemy clearance; this fixture commits its recorded win status.
		scene.set_process(false)
		var scripted_080: Dictionary = scene.play_loop.duplicate(true)
		scripted_080["win_statuses"] = [0]
		scripted_080["event_statuses"] = []
		scripted_080 = rules.resolve_outcome(scripted_080)
		scene.apply_loop(scripted_080, "test")
		scene.set_process(true)
	elif (scene.play_loop.get("win_statuses", []) as Array).is_empty() and scene.play_loop.get("event_statuses", []).has(3):
		var scripted: Dictionary = scene.play_loop.duplicate(true)
		scripted["turn"] = 5
		scripted = rules.BattleScenarioRuleAdapter.run_event_hooks(scripted)
		scripted = rules.resolve_outcome(scripted)
		scene.apply_loop(scripted, "test")
	for _phase in range(6):
		if presentation.battle_finished:
			break
		var living := 0
		scene.set_process(false)
		for actor in scene.play_loop["units"]:
			if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
				rules.set_unit_defeated(scene.play_loop, actor["id"], true)
				living += 1
		if living == 0:
			scene.set_process(true)
			scene.apply_loop(rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
			if BattleOutcome.decided(scene.play_loop):
				break
			continue
		scene.apply_loop(rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
		if level == 7:
			var settlement: Dictionary = scene.play_loop.get("settlement", {})
			if not settlement.is_empty() and not bool(settlement.get("closed", true)):
				scene.apply_loop(rules.finish_rewards(scene.play_loop, int(settlement.get("sequence", 0)), int(settlement.get("revision", 0)), false, true), "test")
		scene.set_process(true)
		var settled := 0
		var phase_start := Time.get_ticks_msec()
		while not presentation.battle_finished and Time.get_ticks_msec() - phase_start < 120000:
			if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
				scene.party_equipment_screen.close()
			if presentation.dialogue_active():
				presentation.advance_dialogue()
			elif coordinator.active:
				settled = 0
				if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
					var message_id := str(scene.scene_timeline.current_event().get("message_id", scene.scene_timeline.current_event().get("id", "")))
					await shot_once("win-dialogue-" + message_id)
					coordinator.handle_input(click())
			elif scene.has_actor_motion():
				settled = 0
			else:
				settled += 1
				if settled > 90:
					break
			await process_frame
	var result_wait_start := Time.get_ticks_msec()
	while not presentation.battle_finished and Time.get_ticks_msec() - result_wait_start < 120000:
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		elif coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(click())
		await process_frame
	check(presentation.battle_finished and BattleOutcome.won(scene.play_loop), "the forced victory reaches the result page (%s)" % BattleOutcome.of(scene.play_loop))
	await create_timer(0.4).timeout
	await shot("result")
	records.append({"result": {"outcome": BattleOutcome.of(scene.play_loop), "resolved": scene.play_loop.get("winfail_runtime", {}).get("resolved", {})}})
	finish()


func _complete_level73_event(battle: Node, rules) -> void:
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop.duplicate(true)
	loop["fail_statuses"] = []
	loop["turn"] = 10
	loop["event_statuses"] = [2]
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	loop["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
	loop["interaction"] = "battle_result"
	battle.apply_loop(loop, "test")
	battle.set_process(true)
	var coordinator = battle.opening_coordinator
	for _frame in range(12000):
		if CampaignProgress.has_pending():
			break
		if battle.party_equipment_screen != null and battle.party_equipment_screen.active:
			battle.party_equipment_screen.close()
		elif coordinator != null and coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(click())
		await process_frame


func _complete_level78_event(battle: Node, rules) -> void:
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop.duplicate(true)
	loop["fail_statuses"] = []
	loop["turn"] = 10
	loop["event_statuses"] = [2]
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)
	var coordinator = battle.opening_coordinator
	for _frame in range(12000):
		if CampaignProgress.has_pending() or not is_instance_valid(battle):
			break
		if battle.party_equipment_screen != null and battle.party_equipment_screen.active:
			battle.party_equipment_screen.close()
		elif coordinator != null and coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(click())
		await process_frame


func prepare_level13_arrival(battle: Node, rules) -> void:
	# Keep the source arrival predicate; the review does not arm a synthetic win.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	loop["fail_statuses"] = []
	check(not BattleOutcome.decided(loop), "level 13 has no outcome at first control")
	var original_coord: Vector2i = rules.unit_ref(loop, "leonard").get("coord", Vector2i.ZERO)
	rules.set_unit_coord(loop, "leonard", Vector2i(13, 9))
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	# Preserve the logical victory while restoring a valid presentation footprint.
	rules.set_unit_coord(loop, "leonard", original_coord)
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level28_scripted_win(battle: Node, rules) -> void:
	# Reach event_2 at the source round-display transition; no initial win override.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	loop["fail_statuses"] = []
	check(not BattleOutcome.decided(loop), "level 28 has no outcome at first control")
	loop["turn"] = 4
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop["fail_statuses"] = []
	loop = rules.resolve_outcome(loop)
	check((loop.get("win_statuses", []) as Array).has(0), "level 28 event_2 arms win_0 at the source round-display transition")
	loop["fail_statuses"] = []
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level31_scripted_win(battle: Node, rules) -> void:
	# WINFAIL031 arms win_0 from source event_4; advance that status before the
	# generic clear fixture so this capture probes the recorded victory path.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop.duplicate(true)
	loop["fail_statuses"] = []
	for actor_value in loop.get("units", []):
		var actor: Dictionary = actor_value
		if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
			actor["defeated"] = true
	loop["event_statuses"] = [4]
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)
	check((loop.get("win_statuses", []) as Array).has(0), "level 31 arms source event_4 win status before capture victory")


func prepare_level33_scripted_win(battle: Node, rules) -> void:
	# WINFAIL033 arms win_0 from event_4 after the controlled roster has
	# departed; mirror that source condition before the clear fixture.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop.duplicate(true)
	loop["fail_statuses"] = []
	for actor_value in loop.get("units", []):
		var actor: Dictionary = actor_value
		if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
			actor["defeated"] = true
	loop["event_statuses"] = [4]
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)
	check((loop.get("win_statuses", []) as Array).has(0), "level 33 arms source event_4 win status before capture victory")


func prepare_level36_scripted_win(battle: Node, rules) -> void:
	# WINFAIL036 has an actTRUE terminal win status; arm that recorded status
	# before the generic clear fixture, which only proves result presentation.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop.duplicate(true)
	loop["fail_statuses"] = []
	loop["win_statuses"] = [0]
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)
	check((loop.get("win_statuses", []) as Array).has(0), "level 36 arms source actTRUE win status before capture victory")


func prepare_level38_arrival(battle: Node, rules) -> void:
	# WINFAIL038 enables win_0 only after every present controlled unit has
	# arrived and been removed by event_1..7; the conditional event_8/9 actors
	# are absent from this roster. Exercise that source ordering directly.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	loop["fail_statuses"] = []
	var zone: Array = battle.first_battle_scenario.get("scenario_rules", {}).get("script_fallback", {}).get("escape_zone", [])
	check(not zone.is_empty(), "level 38 capture has an escape zone for its arrival fixture")
	if zone.is_empty():
		battle.set_process(true)
		return
	var destination := Vector2i(int(zone[0][0]), int(zone[0][1]))
	for actor_value in loop.get("units", []):
		var actor: Dictionary = actor_value
		if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
			actor["coord"] = destination
	loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level902_arrival(battle: Node, rules) -> void:
	# WINFAIL902 wins when Leonard reaches the authored 1248,576..736 pixel
	# corridor; this is the first aligned cell in that corridor.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	loop["fail_statuses"] = []
	var leonard: Dictionary = rules.unit_ref(loop, "leonard")
	leonard["coord"] = Vector2i(39, 18)
	# The source arms win_0 through the preceding multi-party arrival events;
	# this review focuses the authored arrival predicate and result presentation.
	loop["win_statuses"] = [0]
	loop["event_statuses"] = []
	loop = rules.resolve_outcome(loop)
	check(BattleOutcome.won(loop), "level 902 resolves its authored arrival victory")
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level34_scripted_rounds(battle: Node, rules) -> void:
	# WINFAIL034 inserts the 023/044 escort at round 6 (event_0) and arms win_0 only
	# after the monsters fall (event_1 turns the escort hostile). Preserve that order.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	loop["fail_statuses"] = []
	loop["turn"] = 6
	loop = rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(loop))
	loop["fail_statuses"] = []
	for _phase in range(4):
		var converted := 0
		for actor in loop.get("units", []):
			if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
				rules.set_unit_defeated(loop, actor["id"], true)
				converted += 1
		loop = rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(loop))
		loop["fail_statuses"] = []
		if BattleOutcome.decided(loop) or converted == 0:
			break
	check((loop.get("win_statuses", []) as Array).has(0) or BattleOutcome.decided(loop), "level 34 arms win_0 after the monsters fall")
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level17_scripted_rounds(battle: Node, rules) -> void:
	# WINFAIL017 arms its terminal win status only after the round-6 insertion
	# wave and the round-8 story actor event. Preserve that source ordering before
	# the generic clear fixture removes the remaining enemies.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	for target_round in [6, 8]:
		loop["turn"] = target_round
		loop["fail_statuses"] = []
		loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
		loop["fail_statuses"] = []
		loop = rules.resolve_outcome(loop)
		loop["fail_statuses"] = []
		check(int(loop.get("turn", 0)) >= target_round or BattleOutcome.decided(loop), "level 17 reaches scripted round %d before capture victory" % target_round)
	for actor in loop.get("units", []):
		if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
			rules.set_unit_defeated(loop, actor["id"], true)
	loop = rules.resolve_outcome(loop)
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level12_scripted_rounds(battle: Node, rules) -> void:
	# WINFAIL012 arms its terminal actTRUE after source rounds 8/10/16/23.
	# Enemy101 hulls are static review objects, so hold out their provisional
	# fail count while advancing the source event hooks.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	for target_round in [8, 10, 16, 23]:
		loop["turn"] = target_round
		loop["fail_statuses"] = []
		loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
		loop["fail_statuses"] = []
		loop = rules.resolve_outcome(loop)
		loop["fail_statuses"] = []
		check(int(loop.get("turn", 0)) >= target_round or BattleOutcome.decided(loop), "level 12 reaches scripted round %d before capture victory" % target_round)
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func prepare_level7_scripted_rounds(battle: Node, rules) -> void:
	# The formal level-7 review must let WINFAIL007 install round-5/6 actors
	# before the visual forced-victory fixture clears the remaining enemies.
	battle.set_process(false)
	var loop: Dictionary = battle.play_loop
	for target_round in [5, 6]:
		var guard := 0
		while int(loop.get("turn", 0)) < target_round and guard < 256:
			if str(loop.get("interaction", "")) == "action_menu":
				loop = rules.choose_command(loop, "wait")
			elif str(loop.get("interaction", "")) == "ai_resolving":
				loop = rules.advance_current_actor(loop)
			else:
				break
			guard += 1
		# Round-N script events fire after round N's first completed action (the original scans
		# before the queue advance bumps the round, original_round_display.md): complete it too.
		if str(loop.get("interaction", "")) == "action_menu":
			loop = rules.choose_command(loop, "wait")
		elif str(loop.get("interaction", "")) == "ai_resolving":
			loop = rules.advance_current_actor(loop)
		check(int(loop.get("turn", 0)) >= target_round, "level 7 reaches scripted round %d before capture victory" % target_round)
	var shera: Dictionary = rules.unit(loop, "shera")
	check(str(shera.get("actor_id", "")) == "005" and str(shera.get("battle_actor_role", "")) == rules.ROLE_PLAYER, "level 7 capture includes player-controlled Shera")
	battle.apply_loop(loop, "test")
	battle.set_process(true)


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_battle_review.v1", "level": level, "records": records, "failures": failures}, "  "))
	manifest.close()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	if failures.is_empty():
		print("BATTLE_REVIEW_PASS level=%d shots=%d output=%s" % [level, shots_taken.size(), OUT])
		quit(0)
	else:
		print("BATTLE_REVIEW_FAIL level=%d count=%d" % [level, failures.size()])
		quit(1)


func click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func shot_once(label: String) -> void:
	if shots_taken.has(label):
		return
	await shot(label)


func shot(label: String) -> void:
	shots_taken[label] = true
	await create_timer(0.12).timeout
	records.append({"capture": label, "camera": scene.camera.position, "motion": scene.has_actor_motion()})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

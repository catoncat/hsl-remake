extends SceneTree

## Product path for the level-53 battle (緹娜 escapes Klein castle): the shared
## scene plays the compiled STORY053 opening through BattleOpeningCoordinator in
## battle mode (opening-only princess, player-slot install, rope climb, guard
## inserts) and hands control to the PLAYERS-002 unit inside the same PlayLoop;
## then the escape win, the capture defeat and the scripted reinforcements are
## exercised on that PlayLoop. Remake pacing; original timing is not claimed.

const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _click(coordinator: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	coordinator.handle_input(click)


func _fast(coordinator: Node) -> void:
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	coordinator.title_seconds = 0.05
	coordinator.move_pixels_per_frame_hz = 6000.0


func _run() -> void:
	CampaignProgress.reset_campaign()
	# Arrive from the level-60 throne hall carrying Leonard's party (gold 275): a
	# separate-party battle must neither apply nor lose that carry.
	CampaignProgress.pending = {
		"schema": CampaignProgress.SCHEMA,
		"scenario_path": "res://content/battles/battle_053.json",
		"carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}, "restore_vitals": true},
		"from_scenario_id": "story_060_wosfita_court_captive",
	}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_053.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame

	_assert_true(CampaignProgress.separate_party(CampaignProgress.load_campaign(), "res://content/battles/battle_053.json"), "campaign marks level 53 as a separate party")
	_assert_true(int(scene.play_loop.get("gold", 0)) != 275, "Leonard's gold is not applied to 緹娜's battle")
	_assert_true(not scene.play_loop.has("campaign_carry_receipt"), "no carry receipt: the carry was not applied")
	_assert_eq(int(((scene.campaign_handoff.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", -1)), 275, "the incoming carry is retained for pass-through")

	_assert_eq(str(scene.play_loop.get("rule_adapter", "")), "winfail", "level 53 dispatches through the data-driven winfail interpreter")
	_assert_true(scene.play_loop.has("winfail_script_rules") and scene.play_loop.has("winfail_runtime"), "the interpreter initialised its rules and runtime state")
	_assert_eq((scene.play_loop.get("winfail_runtime", {}) as Dictionary).get("unresolved_tokens", []), [], "every WINFAIL053 token resolves against the roster")
	_assert_eq(str(scene.play_loop.get("player_unit_id", "")), "tina", "the controlled unit is the obj_Story_Player2 slot (PLAYERS 002 template)")
	_assert_eq(str(scene.play_loop.get("objective_phase", "")), "escape", "level 53 starts as an escape objective")
	var gate_cells: Array = []
	for cell in scene.play_loop.get("escape_zone", []):
		gate_cells.append(cell if cell is Vector2i else Vector2i(int(cell[0]), int(cell[1])))
	_assert_eq(gate_cells, [Vector2i(30, 35), Vector2i(31, 35), Vector2i(30, 36), Vector2i(31, 36)], "gate cells come from winfail053 actCheckPlayerArrivePos")
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null, "level 53 product opening should create BattleOpeningCoordinator")
	if coordinator == null:
		_finish(scene)
		return
	_assert_true(coordinator.active and not coordinator.story_mode, "the coordinator runs the opening in battle mode")
	var tina = scene.get_node_or_null("World/Actors/ActorRuntime_tina")
	var princess = scene.get_node_or_null("World/Actors/ActorRuntime_actor029_1")
	var guard2 = scene.get_node_or_null("World/Actors/ActorRuntime_enemy023_2")
	_assert_true(tina != null and not tina.visible, "the controlled unit stays hidden until obj_Story_Player2 installs it")
	_assert_true(princess != null and princess.visible, "the opening-only princess (029) is spawned from story_actors")
	_assert_true(guard2 != null and not guard2.visible, "scripted guard inserts stay hidden until actInsertObject")
	_assert_true(not scene.unit_grid_coords.has("actor029_1"), "the opening-only princess never joins the PlayLoop grid map")

	_fast(coordinator)
	var dialogue_speakers: Array[String] = []
	var dialogue_ids: Array[String] = []
	var tina_revealed_at_install := false
	var climb_override_seen := false
	var frames := 0
	while coordinator.active and frames < 4000:
		var current: Dictionary = coordinator.summary()
		var kind := str(current.get("current_event_kind", ""))
		var event_id := str(current.get("current_event_id", ""))
		if kind == "dialogue_message_id":
			if not dialogue_ids.has(event_id):
				dialogue_ids.append(event_id)
				dialogue_speakers.append(str(scene.opening_overlay.speaker_label.text))
			_click(coordinator)
		if event_id == "story053_08_story_object_insert" and tina != null and tina.visible:
			tina_revealed_at_install = true
		if tina != null and tina.has_method("has_shape_override") and tina.has_shape_override():
			climb_override_seen = true
		await process_frame
		frames += 1

	_assert_true(not coordinator.active, "opening should finish within the bounded frame budget")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY053 token may be silently skipped")
	_assert_eq(dialogue_ids.size(), 6, "STORY053 opening presents six dialogue tokens (698-703; 698/700 are narration)")
	_assert_true(dialogue_speakers.has("緹娜："), "緹娜 speaks in the opening (speaker resource 1)")
	_assert_true(tina_revealed_at_install, "obj_Story_Player2 reveals the controlled unit at its install point")
	_assert_true(climb_override_seen, "actChangeShape swaps in the 002-3xxxx climb frames during actMoveDispWait")
	_assert_true(tina != null and not tina.has_shape_override(), "actRestoreShape clears the climb frames")
	_assert_true(princess != null and not princess.visible, "actWalkAndDeleteWait removes the opening-only princess")
	var tokens: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(tokens.get("win", []), ["0"], "actInsertWinStatus(0) registered")
	_assert_eq(tokens.get("fail", []), ["0"], "actInsertFailStatus(0) registered")
	_assert_eq(tokens.get("event", []), ["0", "1", "2"], "three event statuses registered")
	_assert_eq(str((tokens.get("dead_message", {}) as Dictionary).get("message_id", "")), "694", "緹娜's dead message 694 registered")
	_assert_eq(scene.opening_timeline_mode, "first_control", "runtime reports first control after the opening")
	_assert_true(scene.interaction_state in ["ai_resolving", "action_menu"], "opening hands off into the shared PlayLoop")
	for unit_id in ["tina", "enemy023_1", "enemy023_2", "enemy023_3"]:
		var actor = scene.get_node_or_null("World/Actors/ActorRuntime_%s" % unit_id)
		_assert_true(actor != null and actor.visible, "%s should be visible after the opening" % unit_id)
		if actor != null and not actor.is_moving():
			var expected: Vector2 = scene.camera_controller.grid_cell_center_world(scene.unit_grid_coord(unit_id))
			_assert_true(actor.position.is_equal_approx(expected), "%s should stand on its PlayLoop cell after the opening" % unit_id)
	_assert_eq(scene.unit_grid_coord("tina"), Vector2i(20, 23), "緹娜 stands where the rope climb ended (640,736)")
	if tina != null:
		_assert_true(tina.position.is_equal_approx(Vector2(656, 752)), "the climb end and the PlayLoop cell centre coincide (no snap at first control)")

	# Reach the player's action menu, then check the presentation reads the board labels.
	frames = 0
	while str(scene.play_loop.get("interaction", "")) != "action_menu" and frames < 600:
		await process_frame
		frames += 1
	_assert_eq(str(scene.play_loop.get("interaction", "")), "action_menu", "the controlled unit gets its action menu")
	_assert_eq(str(scene.play_loop.get("selected_unit_id", "")), "tina", "緹娜 is the selected unit")
	var view = scene.get_node("BattlePresentation")
	# The rules already chose 緹娜, but the presentation still plays the guards'
	# preceding AI moves; the menu appears once that motion settles.
	frames = 0
	while (scene.has_actor_motion() or scene.ai_playback_active) and frames < 600:
		await process_frame
		frames += 1
	await process_frame
	_assert_true(scene.action_menu.visible, "the action menu is shown for 緹娜 once the AI playback settles (moving=%s ai=%s)" % [str(_moving_actors(scene)), str(scene.ai_playback_active)])
	var menu_rect: Rect2 = scene.action_menu.layout_bounds()
	menu_rect.position += scene.action_menu.position
	_assert_true(Rect2(Vector2.ZERO, Vector2(640, 480)).encloses(menu_rect), "the action menu lies inside the 640x480 view (%s)" % str(menu_rect))
	var objective: String = view._objective_board_text(scene.play_loop)
	_assert_eq(objective, "目標：緹娜 逃出克萊恩城 ｜ 敗北：緹娜 被捕", "objective line comes from the winfail board labels 695/696")

	# Script cutscene with motion: a fired event whose chain interleaves a message,
	# a delay, a walk-and-delete and a closing message (the level-1 retreat shape),
	# injected as a status timeline plus the interpreter's fired/departed records.
	var cutscene_events := [
		{"id": "test_00_dialogue_message_id", "kind": "dialogue_message_id", "args": ["SID_ENEMY023", "1", "702"], "actor_token": "SID_ENEMY023", "message_id": "702", "source_token": "actMessage(SID_ENEMY023,1,702)"},
		{"id": "test_01_opening_delay", "kind": "opening_delay", "args": ["4"], "source_token": "actDelay(4)"},
		{"id": "test_02_actor_walk_and_delete_wait", "kind": "actor_walk_and_delete_wait", "args": ["SID_ENEMY023", "1", "1056", "768", "8"], "actor_token": "SID_ENEMY023", "source_token": "actWalkAndDeleteWait(SID_ENEMY023,1,1056,768,8)"},
		{"id": "test_03_event_status_enable", "kind": "event_status_enable", "args": ["2"], "cutscene_skip": true, "source_token": "actInsertEventStatus(2)"},
		{"id": "test_04_dialogue_message_id", "kind": "dialogue_message_id", "args": ["SID_ENEMY023", "1", "703"], "actor_token": "SID_ENEMY023", "message_id": "703", "source_token": "actMessage(SID_ENEMY023,1,703)"},
	]
	scene.first_battle_scenario["scenario_rules"]["status_timelines"]["event_test"] = {"status_key": "event_test", "events": cutscene_events, "event_count": 5, "playable_event_count": 4}
	var guard_actor = scene.actor_node_for_unit("enemy023_2")
	_assert_true(guard_actor != null and guard_actor.visible, "the bound guard enemy023_2 is on the field before the cutscene")
	# The level's script actor templates make every fired status a ScriptActorCreationRules
	# program: register the synthetic status as a message-only program so the transaction
	# ledger stays consistent (its motion is the coordinator's story-object walk, above).
	scene.play_loop["winfail_script_rules"]["statuses"]["event"].append({"kind": "event", "code": 99, "key": "event_test", "result_message": {}, "conditions": [], "unsupported": [], "inserts": [],
		"actions": [{"name": "actMessage", "args": ["SID_ENEMY023", "1", "702"], "supported": true}, {"name": "actMessage", "args": ["SID_ENEMY023", "1", "703"], "supported": true}]})
	scene.play_loop["winfail_runtime"]["fired"].append({"key": "event_test", "turn": 1, "context": "round"})
	scene.play_loop["winfail_runtime"]["departed_unit_ids"].append("enemy023_2")
	frames = 0
	while frames < 120 and not coordinator.cutscene_mode:
		await process_frame
		frames += 1
	_assert_true(coordinator.cutscene_mode and coordinator.cutscene_key == "event_test", "the fired event starts its cutscene at the next idle frame")
	_assert_true(not scene.action_menu.visible, "the action menu hides during the cutscene")
	_assert_eq(str(scene.scene_timeline.current_event().get("message_id", "")), "702", "the chain opens with message 702")
	_assert_eq(str(scene.opening_overlay.speaker_label.text), "一般兵：", "702 is spoken by the bound soldier")
	coordinator.advance("test_confirm")
	frames = 0
	while frames < 600 and (guard_actor.visible or coordinator.cutscene_mode) and str(scene.scene_timeline.current_event().get("kind", "")) != "dialogue_message_id":
		await process_frame
		frames += 1
	_assert_true(not guard_actor.visible, "the walk-and-delete hides the guard once it reaches (1056,768)")
	_assert_eq(str(scene.scene_timeline.current_event().get("message_id", "")), "703", "the closing message waits for the walk")
	var recorded_skip := false
	for record in coordinator.summary().get("story_records", []):
		if str(record.get("source_event_id", "")) == "test_03_event_status_enable" and str(record.get("status", "")) == "applied_by_winfail_interpreter":
			recorded_skip = true
	_assert_true(recorded_skip, "the interpreter-owned status token is recorded, not replayed")
	coordinator.advance("test_confirm")
	frames = 0
	while frames < 120 and coordinator.active:
		await process_frame
		frames += 1
	_assert_true(not coordinator.active, "the event cutscene finishes")
	frames = 0
	while frames < 120 and not scene.action_menu.visible:
		await process_frame
		frames += 1
	_assert_eq(scene.interaction_state, "action_menu", "the battle resumes 緹娜's turn after the cutscene")
	_assert_true(scene.action_menu.visible, "the action menu returns after the cutscene")
	_assert_true(not guard_actor.visible, "the departed guard stays hidden after the PlayLoop sync")
	_assert_true(not Loop.unit(scene.play_loop, "enemy023_2").is_empty(), "the roster record of the departed guard stays with the PlayLoop")
	_assert_eq(int(coordinator.summary().get("cutscene_records", []).size()), 1, "one cutscene record so far")

	# Escape: the controlled unit standing on a gate cell wins when its action ends.
	var control_loop: Dictionary = scene.play_loop.duplicate(true)
	var escape_loop: Dictionary = control_loop.duplicate(true)
	for unit in escape_loop["units"]:
		if str(unit.get("id", "")) == "tina":
			unit["coord"] = Vector2i(30, 35)
			unit["grid_coord"] = Vector2i(30, 35)
	escape_loop = Loop.begin_wait_resolution(Loop.choose_command(escape_loop, "wait"))
	_assert_eq(BattleOutcome.of(escape_loop), BattleOutcome.VICTORY_ESCAPE, "reaching the gate and waiting ends the battle with the escape win")
	scene.apply_loop(escape_loop, "test")
	await process_frame
	await process_frame
	_assert_eq(view.RuleAdapter.result_message_id(escape_loop, BattleOutcome.of(escape_loop)), "695", "the escape win is the status with board label 695")
	# The fired win status replays its result chain as a script cutscene (704 in
	# script order through the coordinator) before the battle finishes.
	frames = 0
	while frames < 240 and not coordinator.cutscene_mode:
		await process_frame
		frames += 1
	_assert_true(coordinator.cutscene_mode, "the fired win_0 chain starts a script cutscene")
	_assert_eq(coordinator.cutscene_key, "win_0", "the cutscene plays the win_0 status timeline")
	_assert_true(not view.battle_finished, "the battle end waits for the cutscene")
	_assert_eq(str(scene.scene_timeline.current_event().get("message_id", "")), "704", "緹娜's victory line 704 is the cutscene's dialogue event")
	_assert_eq(str(scene.opening_overlay.speaker_label.text), "緹娜：", "704 is spoken by 緹娜 through the script message box")
	frames = 0
	while frames < 240 and coordinator.active:
		coordinator.advance("test_confirm")
		await process_frame
		frames += 1
	_assert_true(not coordinator.active, "the cutscene finishes after its chain")
	_assert_true(not view.dialogue_active(), "the story queue does not page 704 a second time")
	frames = 0
	while frames < 240 and not view.battle_finished:
		await process_frame
		frames += 1
	_assert_true(view.battle_finished, "the battle finishes after the win cutscene")
	_assert_eq(int(coordinator.summary().get("cutscene_records", []).size()), 2, "the terminal status adds the second cutscene record")
	var progress = scene.get_node("CampaignProgress")
	_assert_true(not bool(progress.summary().get("chapter_end_mode", false)), "level 53 victory moves on: winfail [1,1] resolves to the playable level-1 battle")
	_assert_eq(str(progress.summary().get("next_scenario_path", "")), "res://content/battles/ohm_village_battle.json", "the campaign routes [1,1] to the source-bound Ohm Village battle")
	_assert_eq(str(CampaignProgress.next_destination(progress.campaign, scene.play_loop, str(scene.scenario_path)).get("title", "")), "歐姆村", "the destination is the playable 歐姆村 battle")

	# Defeat: the controlled unit falling is the capture outcome with board label 696 and dead message 694.
	# (Probed from the undecided first-control loop: a committed win stays resolved.)
	var defeat_loop: Dictionary = control_loop.duplicate(true)
	_assert_eq(BattleOutcome.of(Loop._resolve_outcome(escape_loop.duplicate(true))), BattleOutcome.VICTORY_ESCAPE, "a decided loop keeps its committed outcome")
	for unit in defeat_loop["units"]:
		if str(unit.get("id", "")) == "tina":
			unit["coord"] = Vector2i(20, 23)
			unit["grid_coord"] = Vector2i(20, 23)
			unit["hp"] = 0
			unit["defeated"] = true
	defeat_loop = Loop._resolve_outcome(defeat_loop)
	_assert_eq(BattleOutcome.of(defeat_loop), BattleOutcome.DEFEAT_FALLEN, "the controlled unit falling is the shared defeat key")
	_assert_eq((defeat_loop.get("winfail_runtime", {}) as Dictionary).get("resolved", {}).get("key", ""), "fail_0", "the PlayLoop commits the deciding fail status when it freezes the outcome")
	_assert_eq(view.RuleAdapter.result_message_id(defeat_loop, BattleOutcome.of(defeat_loop)), "696", "the capture defeat is the status with board label 696")
	# 694 (STORY053 actSetDeadMessage for 緹娜) is her death word on the unit, spoken once at death by
	# BattleAftermath; the defeat result adds no line of its own.
	var defeat_dialogue: Array = scene.get_node("BattlePresentation").RuleAdapter.story_dialogue_messages(defeat_loop)
	_assert_eq(defeat_dialogue.size(), 0, "defeat adds no result-page repeat of the death word 694")

	# Reinforcements: round 5 fires event0 (actInsertObject obj_Story_Level53_Enemy23 at (-32,480),
	# walk to (160,576)); ScriptActorCreationRules births the guard from the level's script actor
	# template and lands it on the walk cell — the generic path, no spawn-cell copy of the roster.
	var round_loop: Dictionary = escape_loop.duplicate(true)
	round_loop["battle_outcome"] = {}
	round_loop["turn"] = 5
	round_loop = scene.BattleScenarioRuleAdapter.run_event_hooks(round_loop)
	_assert_eq(scene.BattleScenarioRuleAdapter.reinforcement_deficits(round_loop), {"Enemy023": 1}, "round 5 owes one Enemy023 before the transaction")
	var before := (round_loop["units"] as Array).size()
	round_loop = Loop._resolve_outcome(round_loop)
	_assert_eq(str(round_loop.get("scenario_error", "")), "", "the round-5 transaction commits without a scenario error")
	_assert_eq((round_loop["units"] as Array).size(), before + 1, "the PlayLoop appends the inserted guard")
	if (round_loop["units"] as Array).size() <= before:
		_finish(scene)
		return
	_assert_eq(scene.BattleScenarioRuleAdapter.reinforcement_deficits(round_loop), {}, "the script actor transaction settles the deficit")
	var recruit: Dictionary = (round_loop["units"] as Array)[before]
	_assert_true(str(recruit.get("id", "")).begins_with("Enemy023_script_"), "the recruit is a script actor template unit (%s)" % str(recruit.get("id", "")))
	_assert_eq(recruit.get("coord"), Vector2i(5, 18), "the recruit lands on the event0 walk cell (160,576)")
	_assert_eq(str(recruit.get("actor_id", "")), "023", "the recruit is a 023 guard")
	_assert_eq((recruit.get("entry_growth", {}) as Dictionary).get("input", {}).get("parameters"), [0, 0], "actSetPrevInsertObjectAdjustLevel 0,0 births the guard without level adjustment")
	var death_ids: Array = []
	for message in (recruit.get("dead_message", {}) as Dictionary).get("messages", []):
		death_ids.append(str((message as Dictionary).get("id", "")))
	_assert_eq(death_ids, ["374", "693"], "the recruit keeps the obj_Data8 death pair of its object row")
	var transactions: Array = round_loop.get("script_actor_transactions", [])
	_assert_eq(transactions.size(), 3, "one script actor transaction per fired status: the synthetic event, win_0 and event0")
	if transactions.size() == 3:
		_assert_eq((transactions[2] as Dictionary).get("created_ids", []), [recruit["id"]], "the event0 transaction records the created guard")
		var install: Dictionary = {}
		for row in (transactions[2] as Dictionary).get("actions", []):
			if (row as Dictionary).has("install"):
				install = (row as Dictionary)["install"]
		_assert_eq(install.get("position"), Vector2i(-32, 480), "the cutscene reveals the guard at the left-edge insert pixel before its walk")
	_finish(scene)


func _moving_actors(scene: Node) -> Array:
	var names: Array = []
	for actor in scene.actors_root.get_children():
		if actor.has_method("is_moving") and actor.is_moving():
			names.append(actor.name)
	return names


func _finish(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	CampaignProgress.reset_campaign()
	if failures.is_empty():
		print("THIRD_BATTLE_RUNTIME_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("THIRD_BATTLE_RUNTIME_TESTS_FAIL count=%d" % failures.size())
		quit(1)

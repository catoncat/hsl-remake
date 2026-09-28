extends SceneTree

## Story-only levels (chapter-01 epilogue 58, the level-60 throne-hall scene and
## the level-53 opening preview): the shared scene must play the compiled STORY
## timelines through BattleOpeningCoordinator without a PlayLoop, spawn the EVEF
## cast and script inserts, run forward script motion, page every message and end
## on the campaign hand-off or the end card when the next step has no scenario yet.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const WorldScriptActions = preload("res://game/world/WorldScriptActions.gd")
const EndingDispatchRules = preload("res://game/sim/EndingDispatchRules.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _run() -> void:
	await _run_carried_job_up_forms()
	await _run_level_2_preview_skip_battle()
	await _run_level_5_preview()
	await _run_level_12_preview()
	await _run_camp_and_hall_chains()
	await _run_level_900_choice_branches()
	await _run_level_57_ending_routes()
	await _run_registered_story_sweep()
	await process_frame
	await process_frame
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("STORY_SCENE_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("STORY_SCENE_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _click(coordinator: Node) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	coordinator.handle_input(click)


func _fast(coordinator: Node) -> void:
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005


func _run_carried_job_up_forms() -> void:
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var carry := {"schema": "hsl_campaign_carry.v1", "loop": {"gold": 275}, "units": {
		"leonard": {"actor_id": "001", "job_up_target_actor_id": "010", "job_up_history": [{"from_actor_id": "001", "to_actor_id": "010", "flag": 0x80000000}]},
		"tina": {"actor_id": "002"},
		"hu": {"actor_id": "099", "job_up_target_actor_id": "012"}}}
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_058.json", "carry": carry, "from_scenario_id": "world_map_scene", "world": _seeded_world(world_map, 1)}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_058.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var leonard: Node = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	_assert_true(leonard != null and str(leonard.actor_id) == "010", "a carried 001→010 劍豪 is drawn in the story scene with the 010 frames (%s)" % (str(leonard.actor_id) if leonard != null else "missing"))
	if leonard != null:
		_assert_true(str(leonard.runtime_summary().get("current_frame_source", "")).begins_with("res://content/imported/hsl/shared/actor_walk_frames/010/"), "the 010 frames come from the shared up-title manifest")
	_assert_eq(scene.stage.carried_unit_view("tina", "002"), {"id": "tina", "actor_id": "002"}, "a carried member without a job-up keeps the base view")
	_assert_eq(scene.stage.carried_unit_view("hu", "003"), {"id": "hu", "actor_id": "003"}, "a carry record on another base row is not applied to the scene's cast entry")
	_assert_eq(scene.stage.carried_unit_view("hanks", "004"), {"id": "hanks", "actor_id": "004"}, "a member absent from the carry keeps the base view")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_2_preview_skip_battle() -> void:
	## 略過戰鬥（視為勝利）: story_002's opening.skip_battle carries WINFAIL002's win
	## section (static-derived: next 2,55; point 2 → event 501 / Visit, encounter ratio
	## 20, track 3 hidden). With level 55 registered the not-remade card offers the
	## continuation; confirming it hands the party to 營地・黃昏 with those writes
	## applied, STORY055 chains to 營地・清晨 (2,56), and STORY056 returns to the big
	## map standing at 戈爾山道 — the post-battle camp talks without the battle body.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 1), world_map, 2)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_002.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_002.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 2 preview (skip path) should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	var skip: Dictionary = coordinator.config.get("skip_battle", {})
	var skip_next: Array = skip.get("next_level_event", [])
	_assert_true(skip_next.size() == 2 and int(skip_next[0]) == 2 and int(skip_next[1]) == 55, "story_002 carries WINFAIL002's win-section next level (2,55)")
	_fast(coordinator)
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the preview reaches its card within the frame budget")
	var summary: Dictionary = coordinator.summary()
	var options: Array = summary.get("end_card_options", [])
	_assert_eq(options.size(), 2, "the card offers the skip-battle continuation and the plain return")
	if options.size() == 2:
		_assert_eq(str((options[0] as Dictionary).get("id", "")), "skip_battle", "the first row skips the battle as a victory")
		_assert_eq(str((options[0] as Dictionary).get("label", "")), "略過戰鬥（視為勝利）→ 續播劇情『營地・黃昏』", "the skip row names the registered level-55 scene")
		_assert_eq(str((options[1] as Dictionary).get("id", "")), "world_map", "the second row is the plain big-map return")
	_assert_eq(int(summary.get("end_card_selected", -1)), 0, "the skip row is highlighted first")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	var texts: Array[String] = []
	if card != null:
		for child in card.get_children():
			if child is Label:
				texts.append((child as Label).text)
	_assert_eq(texts.size(), 4, "title, statement and two choice rows")
	_assert_true(texts.size() == 4 and texts[2].begins_with("▶ "), "the highlighted row carries the cursor")
	# Down moves the highlight (wrapping), Up brings it back; nothing is handed off by moving.
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	coordinator.handle_input(down)
	_assert_eq(int(coordinator.summary().get("end_card_selected", -1)), 1, "Down highlights 回到大地圖（不施加戰果）")
	coordinator.handle_input(down)
	_assert_eq(int(coordinator.summary().get("end_card_selected", -1)), 0, "the highlight wraps around")
	_assert_true(not CampaignProgress.has_pending(), "moving the highlight hands nothing off")
	var confirm := InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.pressed = true
	coordinator.handle_input(confirm)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming 略過戰鬥 hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_055.json", "the hand-off targets story_055 (WINFAIL002 win: 2,55)")
	var next_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(next_world.get("current_point", 0)), 2, "the party still stands at 戈爾山道 (point 2)")
	_assert_eq(WorldMapRules.point_event(next_world, world_map, 2), 501, "actBMSetPointEvent 2,501,bmpmVisit is applied: point 2 now opens event 501")
	_assert_true((WorldMapRules.point_flags(next_world, world_map, 2) as Array).has("bmpmVisit"), "point 2 carries the Visit bit")
	_assert_eq(int(((next_world.get("encounter_ratios", {}) as Dictionary).get("2", -1))), 20, "actBMSetPointEncounterRatio 2,20 is applied")
	_assert_true(WorldMapRules.track_hidden(next_world, world_map, 3), "actBMSetTrackFlag 3,bmpmHidden hides track 3")
	_assert_eq(int(((CampaignProgress.pending.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", 0)), 275, "the carry passes through the skipped battle unchanged")
	scene.queue_free()
	await process_frame
	await process_frame
	# 營地・黃昏 (STORY055): 雷歐納德, 緹娜 and 琥 by the campfire; 32 lines, then 2,56.
	var camp = RuntimeScene.instantiate()
	camp.scenario_path = "res://content/battles/story_055.json"
	camp.startup_mode = "product_opening"
	root.add_child(camp)
	await process_frame
	await process_frame
	var camp_coordinator = camp.opening_coordinator
	_assert_true(camp_coordinator != null and camp_coordinator.active and camp_coordinator.story_mode, "story_055 runs in story mode from the skip hand-off")
	if camp_coordinator == null:
		camp.queue_free()
		return
	_assert_true(camp.play_loop.is_empty(), "the camp scene has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(camp).get("actor_runtime_count", 0)), 3, "EVEF cast: 雷歐納德, 緹娜, 琥")
	_assert_true(camp.get_node_or_null("World/Actors/ActorRuntime_tina") != null, "緹娜 sits at the camp (she joined after 戈爾山道)")
	var ambience: Array = RuntimeReadback.map_object_summary(camp).get("background_sound_records", [])
	_assert_eq(ambience.size(), 1, "the camp's EVEF 夜晚聲 (mapobjPlayBGSound) is one background sound")
	if ambience.size() == 1:
		_assert_eq(str((ambience[0] as Dictionary).get("status", "")), "looping", "NIGHT001.WAV loops for the scene")
		var night: AudioStreamPlayer = camp.get_node_or_null(str((ambience[0] as Dictionary).get("node_path", "")))
		_assert_true(night != null and night.playing and night.stream.resource_path.ends_with("NIGHT001.wav"), "the decoded night ambience is playing")
	_fast(camp_coordinator)
	var camp_messages: Array[String] = []
	var camp_seen: Dictionary = {}
	frames = 0
	while camp_coordinator.active and not camp_coordinator.story_finished and frames < 6000 and not CampaignProgress.has_pending():
		if str(camp_coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			var camp_event: Dictionary = camp.scene_timeline.current_event()
			if not camp_seen.has(str(camp_event.get("id", ""))):
				camp_seen[str(camp_event.get("id", ""))] = true
				camp_messages.append(str(camp_event.get("message_id", "")))
			_click(camp_coordinator)
		await process_frame
		frames += 1
	_assert_eq(camp_messages.size(), 32, "STORY055 pages its 32 message tokens")
	_assert_true(camp_messages.size() >= 2 and camp_messages[0] == "791" and camp_messages[camp_messages.size() - 1] == "818", "the talk runs from 791 to 818")
	_assert_eq((camp_coordinator.summary().get("skipped_records", []) as Array).size(), 0, "no STORY055 token is silently skipped")
	_assert_true(CampaignProgress.has_pending(), "the camp talk hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_056.json", "actSetNextPlayLevelEvent 2,56 chains to 營地・清晨")
	_assert_eq(WorldMapRules.point_event(CampaignProgress.pending.get("world", {}), world_map, 2), 501, "the win-section write survives the chain")
	camp.queue_free()
	await process_frame
	await process_frame
	# 營地・清晨 (STORY056): 緹娜 is installed through obj_Story_Player2, the three leave
	# westwards, and 2,gameBigMapLevel returns to the map standing at 戈爾山道.
	var morning = RuntimeScene.instantiate()
	morning.scenario_path = "res://content/battles/story_056.json"
	morning.startup_mode = "product_opening"
	root.add_child(morning)
	await process_frame
	await process_frame
	var morning_coordinator = morning.opening_coordinator
	_assert_true(morning_coordinator != null and morning_coordinator.active and morning_coordinator.story_mode, "story_056 runs in story mode")
	if morning_coordinator == null:
		morning.queue_free()
		return
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(morning).get("actor_runtime_count", 0)), 2, "EVEF cast before the insert: 琥 and 雷歐納德")
	_fast(morning_coordinator)
	var morning_messages: Array[String] = []
	var morning_seen: Dictionary = {}
	frames = 0
	while morning_coordinator.active and not morning_coordinator.story_finished and frames < 6000 and not CampaignProgress.has_pending():
		if str(morning_coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			var morning_event: Dictionary = morning.scene_timeline.current_event()
			if not morning_seen.has(str(morning_event.get("id", ""))):
				morning_seen[str(morning_event.get("id", ""))] = true
				morning_messages.append(str(morning_event.get("message_id", "")))
			_click(morning_coordinator)
		await process_frame
		frames += 1
	_assert_eq(morning_messages, ["819", "790", "820", "821", "822", "823", "824", "825", "826", "827"] as Array[String], "STORY056 pages its ten lines in script order")
	_assert_true(morning.get_node_or_null("World/Actors/ActorRuntime_tina") != null, "緹娜 was installed by obj_Story_Player2")
	_assert_eq((morning_coordinator.summary().get("skipped_records", []) as Array).size(), 0, "no STORY056 token is silently skipped")
	_assert_true(CampaignProgress.has_pending(), "the morning scene hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 2,gameBigMapLevel returns to the big map")
	var map_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(map_world.get("current_point", 0)), 2, "the party stands at 戈爾山道 (point 2) after the camp talks")
	_assert_eq(WorldMapRules.point_event(map_world, world_map, 2), 501, "point 2 keeps event 501 from the skipped victory")
	_assert_true(WorldMapRules.track_hidden(map_world, world_map, 3), "STORY056's actBMSetTrackFlag 3,bmpmHidden keeps track 3 hidden")
	_assert_eq(int(((CampaignProgress.pending.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", 0)), 275, "the carry passes through both camp scenes unchanged")
	morning.queue_free()
	await process_frame
	await process_frame


func _run_level_5_preview() -> void:
	## STORY005 (呼嘯平原): the camera locks on 雷歐納德, the four-member party walks to
	## the middle of the plain and wing warriors / 038 close in from every edge; the
	## battle is not remade, so the preview ends on its card and returns to the map.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(_seeded_world(world_map, 4), world_map, 5)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_005.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_005.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	# Keep this direct preview regression independent of campaign[5], now a real battle.
	var preview_progress = scene.get_node("CampaignProgress")
	preview_progress.campaign["battles"]["5"] = {"scenario":"res://content/battles/story_005.json","kind":"story","title":"呼嘯平原（開場預覽）"}
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 5 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the preview has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 13, "EVEF cast: four controlled slots, five 036 and four 038")
	## The EVEF 寶藏 chest (defProcTreasureBox, record 17) is a closed stand object at
	## its EVEF anchor (288,576); pickup belongs to the not-yet-remade battle.
	var chest: Node = null
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		for child in layer.get_children():
			if str(child.name).find("BOX0001") != -1:
				chest = child
	_assert_true(chest != null and chest.get_meta("candidate_anchor_world", Vector2.ZERO) == Vector2(288, 576), "the 寶藏 chest is drawn at its EVEF anchor")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("map_object_spawn_count", -1)), 2, "level 5 places its 樹01 tree and the 寶藏 chest")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(message_ids, ["899", "900", "901"] as Array[String], "STORY005 pages its three lines in script order")
	_assert_eq(str(speakers.get("899", "")), "漢克斯：", "漢克斯 notices the encirclement")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY005 token is skipped")
	var leonard = scene.actor_node_for_unit("leonard")
	_assert_true(leonard != null and leonard.position.is_equal_approx(Vector2(384 + 16, 288 + 16)), "雷歐納德 ends on his actWalkWait target (384,288)")
	var camera_center: Vector2 = scene.camera.get_screen_center_position()
	_assert_true(camera_center.x >= 320 and camera_center.y >= 240 and camera_center.x <= 960 - 320 and camera_center.y <= 704 - 240, "the camera centre stays inside the 960x704 map")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	if card != null:
		var texts: Array[String] = []
		for child in card.get_children():
			if child is Label:
				texts.append(child.text)
		_assert_true(texts.has("呼嘯平原"), "the card carries the scene title")
		_assert_true(texts.size() == 4 and texts[1] == "戰鬥部分（level 5）尚未重製", "the card states the battle is not remade")
		_assert_true(texts.size() == 4 and texts[2] == "▶ 略過戰鬥（視為勝利）→ 回到大地圖", "WINFAIL005's win sets no next level: the victory row returns to the big map")
	# 略過戰鬥（視為勝利）: back on the map with the win section's writes (point 5 → event
	# 507 / Visit, ratio 100, 席達鎮 exec event 19, tracks 6 and 15 hidden).
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	coordinator.handle_input(space)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the card hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the card exits to the world map")
	var won_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(won_world.get("current_point", 0)), 5, "the party stands at 呼嘯平原 (point 5)")
	_assert_eq(WorldMapRules.point_event(won_world, world_map, 5), 507, "actBMSetPointEvent 5,507,bmpmVisit is applied as the skipped victory")
	_assert_eq(int(((won_world.get("encounter_ratios", {}) as Dictionary).get("5", -1))), 100, "actBMSetPointEncounterRatio 5,100 is applied")
	_assert_true(WorldMapRules.track_hidden(won_world, world_map, 6) and WorldMapRules.track_hidden(won_world, world_map, 15), "actBMSetTrackFlag 6／15,bmpmHidden hide both tracks")
	_assert_eq(int(((won_world.get("towns", {}) as Dictionary).get("6", {}) as Dictionary).get("exec_event", 0)), 19, "actSetTownExecEvent town_席達鎮,19 arms the town's next event")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_12_preview() -> void:
	## STORY012 (巴瀚納海峽): the seven-member party on the ship deck in a storm — 雪拉,
	## 雷特, 嚎 and 琥 banter, the rain controllers and rain sound start, Enemy038
	## boarders climb aboard by displacement walks, 雷特 challenges them. The 62
	## Enemy101 船殼 hull pieces are registered actors (PLAYERS 101, no_showshape: not drawn, ACTORS100); 咕嚕 / 克羅蒂 are
	## conditional installs and stay out. The battle is not remade: card, back to point 12.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 11), world_map, 12)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_012.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_012.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 12 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 101, "seven party members, 32 Enemy038 boarders and the 62 Enemy101 hull actors (registered like the original's 0x4c34c0 entries, ACTORS100)")
	for unit_id in ["rett", "howl"]:
		_assert_true(scene.actor_node_for_unit(unit_id) != null, "%s is installed from the EVEF slot" % unit_id)
	_assert_true(scene.actor_node_for_unit("actor101_1") != null, "Enemy101 船殼 pieces are spawned as actors (ACTORS100)")
	var hulls := 0
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		for child in layer.get_children():
			if str(child.name).find("18_DOOR01") != -1:
				hulls += 1
	_assert_eq(hulls, 0, "no Enemy101 hull is drawn as a stand object any more: no_showshape (0x4420ef) hides the actor, the deck art is the map backdrop")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var seen_events: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 6000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var event: Dictionary = scene.scene_timeline.current_event()
			var event_id := str(event.get("id", ""))
			if not seen_events.has(event_id):
				seen_events[event_id] = true
				message_ids.append(str(event.get("message_id", "")))
				speakers[str(event.get("message_id", ""))] = str(scene.opening_overlay.speaker_label.text)
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	_assert_eq(message_ids, ["1701", "1702", "1703", "1704", "1705", "1706", "1707", "1708", "1709", "728", "1710"] as Array[String], "STORY012 pages its eleven lines in script order")
	_assert_eq(str(speakers.get("1702", "")), "雷特：", "雷特 speaks 1702 (slot 5)")
	_assert_eq(str(speakers.get("1704", "")), "嚎：", "嚎 speaks 1704 (slot 6)")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY012 token is skipped")
	var effects: Dictionary = {}
	for record in coordinator.story_records:
		if record.has("effect"):
			effects[str(record["effect"])] = int(effects.get(str(record["effect"]), 0)) + 1
	_assert_eq(effects, {"rain_emitter": 4, "background_sound": 1}, "four rain controllers and the rain sound start the storm")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	coordinator.handle_input(space)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the card hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "WINFAIL012's win (12,gameBigMapLevel) returns to the big map")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 12, "the party stands at 巴瀚納海峽 (point 12)")
	_assert_true(not WorldMapRules.point_hidden(CampaignProgress.pending.get("world", {}), world_map, 13), "the skipped victory reveals point 13 (actBMClearPointFlag 13,bmpmHidden)")
	scene.queue_free()
	await process_frame
	await process_frame


func _seeded_world(world_map: Dictionary, world_point: int) -> Dictionary:
	var seeded: Dictionary = WorldScriptActions.ensure_state({}, CampaignProgress.load_campaign())
	var state: Dictionary = seeded.get("state", WorldMapRules.initial_state(world_map, 1))
	return WorldMapRules.visit(state, world_map, world_point)


## Skipped tokens the scene does not explain: a preview leaves out its conditional
## installs (「(有才產生)」 party members whose membership is not modelled), so their walk
## and dialogue tokens are unbound by design and listed in unresolved_semantics.
## Everything else skipped is a real gap (object id -1 resolves to the last insert).
func _unexplained_skips(scene, coordinator) -> Array:
	var allowed: Array[String] = []
	for note in scene.first_battle_scenario.get("unresolved_semantics", []):
		var text := str(note)
		if text.begins_with("conditional installs left out"):
			for part in text.split(": ")[1].split(", "):
				allowed.append("SID_" + str(part).split("(")[0])
		elif text.contains("binds to nothing and is skipped"):
			# A token walked by the STORY without any EVEF install (STORY078 SID_咕嚕): the
			# scene documents the skip explicitly.
			for word in text.split(" "):
				if str(word).begins_with("SID_"):
					allowed.append(str(word).trim_suffix(",").trim_suffix(")"))
	var by_id: Dictionary = {}
	for event in scene.scene_timeline.events:
		by_id[str(event.get("id", ""))] = event
	var unexplained: Array = []
	for record in coordinator.summary().get("skipped_records", []):
		var event: Dictionary = by_id.get(str((record as Dictionary).get("source_event_id", "")), {})
		var token := str(event.get("source_token", ""))
		var explained := false
		for name in allowed:
			if token.contains(name):
				explained = true
		if not explained:
			unexplained.append({"record": record, "token": token})
	return unexplained


## Boots a story scene from a big-map hand-off standing at world_point, pages every
## line and returns {scene, coordinator, messages (script order, per token), speakers
## (message id → speaker label at the time), portrait_faces (message id → portrait
## texture path), world_map}. Callers assert the hand-off and free the scene.
func _play_story_scene(path: String, world_point: int, frame_budget: int = 6000, expect_handoff: bool = true, world_patch: Dictionary = {}) -> Dictionary:
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = _seeded_world(world_map, world_point)
	for key in world_patch:
		world[key] = world_patch[key]
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": path, "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	var result := {"scene": scene, "coordinator": coordinator, "messages": [] as Array[String], "speakers": {}, "portrait_faces": {}, "panel_tops": {}, "world_map": world_map, "initial_cast": int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0))}
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "%s runs in story mode" % path)
	if coordinator == null:
		return result
	_fast(coordinator)
	# The sweep and the chain cases check order and hand-offs, not pacing: shrink every
	# remake delay so sixty-odd scenes run in a few minutes.
	coordinator.delay_token_seconds = 0.002
	coordinator.default_step_seconds = 0.004
	coordinator.title_seconds = 0.1
	var seen_event_ids: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < frame_budget and not CampaignProgress.has_pending():
		if not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(0)
			await process_frame
			frames += 1
			continue
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			# actEnterStorageWindow: the sweep closes the 整理裝備 screen unchanged.
			result["storage_windows"] = int(result.get("storage_windows", 0)) + 1
			scene.party_equipment_screen.close()
			await process_frame
			frames += 1
			continue
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			var event: Dictionary = scene.scene_timeline.current_event()
			var event_id := str(event.get("id", ""))
			if not seen_event_ids.has(event_id):
				seen_event_ids[event_id] = true
				var message_id := str(event.get("message_id", ""))
				(result["messages"] as Array[String]).append(message_id)
				result["speakers"][message_id] = str(scene.opening_overlay.speaker_label.text)
				var texture: Texture2D = scene.opening_overlay.portrait.texture
				result["portrait_faces"][message_id] = texture.resource_path if texture != null and scene.opening_overlay.portrait.visible else ""
				result["panel_tops"][message_id] = scene.opening_overlay.position.y
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(_unexplained_skips(scene, coordinator), [], "%s: no token is silently skipped (conditional-install tokens aside)" % path)
	_assert_true(coordinator.story_finished or CampaignProgress.has_pending(), "%s reaches its end within the frame budget" % path)
	if expect_handoff:
		_assert_true(CampaignProgress.has_pending(), "%s hands off through the campaign" % path)
	return result


func _run_camp_and_hall_chains() -> void:
	## The post-battle story segments the win sections chain into (P-044 tools lane):
	## 61 (after 盜賊洞窟) → big map at point 3 with its town / big-map writes;
	## 62 (after 席達鎮) → 63 (throne hall, the spies' actShapeMessage faces) → point 6;
	## 64 (after 寧靜之森, 雪拉 joins) → point 7. Each plays on level 55's camp map
	## (63 on level 58's hall) by map alias — provisional readings recorded in the seeds.
	var camp61 := await _play_story_scene("res://content/battles/story_061.json", 3)
	_assert_eq(int(camp61["initial_cast"]), 4, "STORY061: 雷歐納德, 緹娜, 琥 and 漢克斯 at the camp")
	_assert_eq(camp61["messages"], ["847", "848", "849", "850", "380", "851", "852", "853", "854", "855", "856", "857"] as Array[String], "STORY061 pages its twelve lines in script order")
	_assert_eq(str(camp61["speakers"].get("847", "")), "漢克斯：", "漢克斯 reports first (847)")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 3,gameBigMapLevel returns to the big map")
	var world61: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(world61.get("current_point", 0)), 3, "the party stands at 盜賊洞窟 (point 3)")
	_assert_true(not WorldMapRules.track_hidden(world61, camp61["world_map"], 3), "actBMClearTrackFlag 3,bmpmHidden reveals track 3")
	_assert_eq(int(((world61.get("towns", {}) as Dictionary).get("1", {}) as Dictionary).get("exec_event", 0)), 10, "actSetTownExecEvent town_歐姆村,10 arms the village's next event")
	(camp61["scene"] as Node).queue_free()
	await process_frame
	await process_frame
	var camp62 := await _play_story_scene("res://content/battles/story_062.json", 6)
	_assert_eq(int(camp62["initial_cast"]), 3, "STORY062: 漢克斯, 緹娜 and 雷歐納德 (琥 is not placed)")
	_assert_eq((camp62["messages"] as Array[String]).size(), 14, "STORY062 pages its fourteen message tokens (988 twice)")
	_assert_eq(str(camp62["speakers"].get("980", "")), "緹娜：", "緹娜 opens by questioning 漢克斯 (980)")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_063.json", "actSetNextPlayLevelEvent 6,63 chains to the throne hall")
	(camp62["scene"] as Node).queue_free()
	await process_frame
	await process_frame
	var hall63 := await _play_story_scene("res://content/battles/story_063.json", 6)
	_assert_eq(int(hall63["initial_cast"]), 4, "STORY063: 克里歐司, two 027 attendants and a 023 guard")
	_assert_eq(hall63["messages"], ["993", "994", "678", "995", "380", "996", "997", "998", "999", "1000", "1001", "1002", "1003", "678", "380", "1004", "1005", "1006"] as Array[String], "STORY063 pages its eighteen lines including the five actShapeMessage tokens")
	_assert_eq(str(hall63["speakers"].get("997", "")), "???：", "actShapeMessage names its speaker by resource id 306 (???)")
	_assert_true(str(hall63["portrait_faces"].get("997", "")).ends_with("FACE0054.png"), "the first spy speaks under the script's FACE0054 face")
	_assert_true(str(hall63["portrait_faces"].get("1002", "")).ends_with("FACE0008.png"), "the second spy speaks under FACE0008")
	# Dialogue handler 0x414280: only a script-faced line (actShapeMessage, flag 0x4000 via
	# 0x414220) takes the top slot, camera y + 20; a cast member's line keeps the bottom one.
	_assert_eq(float(hall63["panel_tops"].get("997", -1.0)), 20.0, "the first spy's actShapeMessage line takes the top slot (y 20)")
	_assert_eq(float(hall63["panel_tops"].get("1002", -1.0)), 20.0, "the second spy's actShapeMessage line takes the top slot (y 20)")
	_assert_eq(float(hall63["panel_tops"].get("999", -1.0)), 320.0, "克里歐司's actMessage answer keeps the bottom slot (y 320)")
	_assert_eq(str(hall63["speakers"].get("999", "")), "克里歐司：", "克里歐司 answers between the spies' lines")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 6,gameBigMapLevel returns to the big map")
	var world63: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(world63.get("current_point", 0)), 6, "the party stands at 席達鎮 (point 6) after the hall scene")
	_assert_true(not WorldMapRules.track_hidden(world63, hall63["world_map"], 6), "actBMClearTrackFlag 6,bmpmHidden reveals track 6")
	(hall63["scene"] as Node).queue_free()
	await process_frame
	await process_frame
	var camp64 := await _play_story_scene("res://content/battles/story_064.json", 7)
	_assert_eq(int(camp64["initial_cast"]), 5, "STORY064: the five-member party with 雪拉")
	_assert_eq((camp64["messages"] as Array[String]).size(), 19, "STORY064 pages its nineteen message tokens")
	_assert_eq(str(camp64["speakers"].get("1036", "")), "雷歐納德：", "雷歐納德 asks 雪拉 first (1036)")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 7,gameBigMapLevel returns to the big map")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 7, "the party stands at 寧靜之森 (point 7)")
	(camp64["scene"] as Node).queue_free()
	await process_frame
	await process_frame


## Every campaign.json story-kind scenario boots from a big-map hand-off, pages to
## its end without a silently skipped token, and either hands off or ends on a card
## whose plain return reaches the big map. A scale guard for scenes registered by
## the data lanes without a hand-written case; per-scene semantics stay above.
func _run_registered_story_sweep() -> void:
	var campaign := CampaignProgress.load_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var swept: Array[String] = []
	var expected: Array = campaign.get("battles", {}).keys().filter(func(key): return str(campaign["battles"][key].get("kind", "")) == "story")
	for key in campaign.get("battles", {}):
		var entry: Dictionary = campaign["battles"][key]
		if str(entry.get("kind", "")) != "story":
			continue
		var level := int(str(key))
		var point := level if CampaignProgress.level_is_map_point(campaign, level) else 1
		var path := str(entry.get("scenario", ""))
		var played := await _play_story_scene(path, point, 8000, false)
		var coordinator = played["coordinator"]
		if coordinator == null:
			continue
		var scene = played["scene"]
		var opening: Dictionary = scene.first_battle_scenario.get("opening", {})
		var game_clear := false
		for record in coordinator.summary().get("story_records", []):
			if str((record as Dictionary).get("kind", "")) == "game_clear":
				game_clear = true
		var chapter_end: bool = game_clear or (opening.has("end_card") and not opening.has("end_exit") and coordinator.story_finished and not CampaignProgress.has_pending())
		if game_clear:
			# STORY082 → 90,998: the registered GameClear sequence takes over the tree.
			await process_frame
			await process_frame
			var ending = current_scene
			_assert_true(ending != null and ending.has_method("summary") and str(ending.summary().get("schema", "")) == "hsl_game_clear_screen.v1", "%s: the ending hands over to the GameClear sequence" % path)
			if ending != null:
				ending.queue_free()
			await process_frame
		elif chapter_end:
			# A chapter card without a registered continuation: its confirm restarts the
			# campaign instead of handing off; the scene must still have reached the card.
			_assert_true(scene.get_node_or_null("UI/ChapterEndCard") != null, "%s: the ending shows its chapter card" % path)
		elif not CampaignProgress.has_pending() and coordinator.story_finished:
			# Not-remade card: the plain return row (or the single confirm) leaves for the big map.
			var options: Array = coordinator.summary().get("end_card_options", [])
			if options.size() > 1:
				coordinator.select_end_card_option(options.size() - 1)
			_click(coordinator)
			await process_frame
		if not chapter_end:
			_assert_true(CampaignProgress.has_pending(), "%s: the scene end hands off through the campaign" % path)
			_assert_true(str(CampaignProgress.pending.get("scenario_path", "")) != "", "%s: the hand-off names a scenario" % path)
		swept.append(str(key))
		scene.queue_free()
		await process_frame
		await process_frame
	_assert_eq(swept, expected, "the sweep covered exactly every currently registered story scene")
	print("REGISTERED_STORY_SWEEP scenes=%d" % swept.size())


func _boot_900_to_choice() -> Dictionary:
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = _seeded_world(world_map, 9)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_900.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_900.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	var result := {"scene": scene, "coordinator": coordinator, "world_map": world_map, "messages": [] as Array[String]}
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "story_900 runs in story mode")
	if coordinator == null:
		return result
	_fast(coordinator)
	var seen: Dictionary = {}
	var frames := 0
	while coordinator.active and (coordinator.summary().get("select_options", []) as Array).is_empty() and not coordinator.story_finished and frames < 6000:
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			var event: Dictionary = scene.scene_timeline.current_event()
			if not seen.has(str(event.get("id", ""))):
				seen[str(event.get("id", ""))] = true
				(result["messages"] as Array[String]).append(str(event.get("message_id", "")))
			_click(coordinator)
		await process_frame
		frames += 1
	return result


func _run_level_57_ending_routes() -> void:
	## story_057 (塔克斯之死) ends on actSetNextPlayLevelGetOverEvent 0. The original picks
	## the finale in 0x42c520 (static-derived): sort gameoverID1..3 by score (ties keep
	## 1, 2, 3), then the first id whose over-flag condition holds — 1 → 76 with no flag,
	## 2 → 77 with FreeEnemy, 3 → 78 with EnemyJobUp — else 76. The card shows that
	## finale beside the plain return and hands the carry there with [level, level].
	var plain := EndingDispatchRules.route({}, 0)
	_assert_eq(int(plain.get("level", 0)), 76, "no score and no flag: gameoverID1 leads and 76 妖精王 follows")
	_assert_eq(plain.get("order", []), [1, 2, 3], "equal scores keep the id order")
	_assert_eq(int(EndingDispatchRules.route({"1": 3, "2": 5}, 1).get("level", 0)), 77, "the top score gameoverID2 with FreeEnemy set → 77 席德爾")
	_assert_eq(int(EndingDispatchRules.route({"1": 3, "2": 5}, 0).get("level", 0)), 76, "gameoverID2 without FreeEnemy is skipped; gameoverID1 with no flag → 76")
	var tie := EndingDispatchRules.route({"1": 4, "3": 4}, 2)
	_assert_eq(tie.get("order", []), [1, 3, 2], "a strict-less bubble sort keeps 1 before the tied 3")
	_assert_eq(int(tie.get("level", 0)), 78, "gameoverID1 is refused by the set flag, gameoverID3 with EnemyJobUp → 78 接觸")
	_assert_eq(int(EndingDispatchRules.route({"1": 9}, 3).get("level", 0)), 77, "both flags set: 1 is refused, 2 accepts FreeEnemy")
	_assert_eq(int(EndingDispatchRules.route({"2": 1}, 2).get("level", 0)), 78, "FreeEnemy missing and 1 refused by EnemyJobUp: the third id decides")
	_assert_eq(EndingDispatchRules.next_level_event(EndingDispatchRules.route({"1": 3, "2": 5}, 1)), [77, 77], "the handler writes (level 0 → result, result)")
	var played := await _play_story_scene("res://content/battles/story_057.json", 45, 8000, false, {"over_score": {"1": 3, "2": 5}, "over_flag": 1})
	var coordinator = played["coordinator"]
	var scene = played["scene"]
	if coordinator == null:
		return
	_assert_true(coordinator.story_finished, "STORY057 reaches its card")
	var options: Array = coordinator.summary().get("end_card_options", [])
	var ids: Array = options.map(func(option): return str(option.get("id", "")))
	_assert_eq(ids, ["end_route", "world_map"], "the card offers the dispatched finale then the plain return")
	var decision: Dictionary = coordinator.summary().get("end_route_decision", {})
	_assert_eq(int(decision.get("level", 0)), 77, "the hand-off world (ID2 5 > ID1 3, FreeEnemy) dispatches 77")
	if options.size() == 2:
		_assert_eq(str(options[0].get("label", "")), "結局路線 → 續播『破滅的命運・席德爾』", "the row names 77 席德爾")
		_assert_eq(str(options[0].get("path", "")), "res://content/battles/battle_077.json", "the route resolves through the campaign registry")
		coordinator.confirm_end_card_option()
		await process_frame
		_assert_true(CampaignProgress.has_pending(), "confirming the finale hands off through the campaign")
		_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_077.json", "the dispatched final is the next scene")
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame


func _run_to_end(scene, coordinator, frame_budget: int = 8000) -> Array[String]:
	var messages: Array[String] = []
	var seen: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < frame_budget and not CampaignProgress.has_pending():
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		elif str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			var event: Dictionary = scene.scene_timeline.current_event()
			if not seen.has(str(event.get("id", ""))):
				seen[str(event.get("id", ""))] = true
				messages.append(str(event.get("message_id", "")))
			_click(coordinator)
		await process_frame
		frames += 1
	return messages


func _run_level_900_choice_branches() -> void:
	## STORY900 (曼多力亞 對峙): the Wosfita soldiers press the villagers, the party walks
	## in and 雷歐納德's actSelectInsertEvent offers two lines. 選擇一 splices winfail900
	## event 0 — 雷歐納德 kicks the soldier (KICK001, the 023-1000x shape set), the party
	## walks off, 曼多力亞 is restored to a town (actBMSetPointEvent 9,0,bmpmTown) and the
	## scene returns to the big map at point 9 with no battle. 選擇二 splices event 1 — the
	## camera sweeps, villagers move, WORD900 shows, win / fail statuses arm and
	## actPlayLevelMusic keeps the current track (level 900 has no table track) — then the
	## not-remade battle ends the preview on its card.
	var first := await _boot_900_to_choice()
	var coordinator = first["coordinator"]
	if coordinator == null:
		return
	var scene = first["scene"]
	var world_map: Dictionary = first["world_map"]
	_assert_eq(first["messages"], ["1103", "1104", "1105", "1106", "1107", "1108", "1109", "1110", "1111", "1112"] as Array[String], "STORY900 pages its ten lines before the choice")
	var options: Array = coordinator.summary().get("select_options", [])
	_assert_eq(options.size(), 2, "actSelectInsertEvent offers two choices")
	if options.size() == 2:
		_assert_true(str((options[0] as Dictionary).get("text", "")).begins_with("1.") and str((options[0] as Dictionary).get("event_code", "")) == "0", "選擇一 (message 1113) inserts winfail event 0")
		_assert_true(str((options[1] as Dictionary).get("text", "")).begins_with("2.") and str((options[1] as Dictionary).get("event_code", "")) == "1", "選擇二 (message 1114) inserts winfail event 1")
	# Case 0x4f (0x451f2b–0x451fe3) calls only 0x4264a0: no message board beside the select board.
	_assert_true(not scene.opening_overlay.visible, "the dialogue board is closed while the select board is up")
	_assert_true(scene.get_node_or_null("UI/StorySelectPrompt/Choice1") != null, "two choice rows are shown")
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	coordinator.handle_input(down)
	_assert_eq(int(coordinator.summary().get("select_selected", -1)), 1, "Down highlights 選擇二")
	coordinator.handle_input(down)
	_assert_eq(int(coordinator.summary().get("select_selected", -1)), 0, "the highlight wraps back to 選擇一")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	coordinator.handle_input(enter)
	_assert_true((coordinator.summary().get("select_options", []) as Array).is_empty(), "Enter resolves the prompt")
	_assert_true(scene.get_node_or_null("UI/StorySelectPrompt") == null or not is_instance_valid(scene.get_node_or_null("UI/StorySelectPrompt")) or scene.get_node_or_null("UI/StorySelectPrompt").is_queued_for_deletion(), "the prompt is removed")
	var after: Array[String] = await _run_to_end(scene, coordinator)
	_assert_eq(after, ["1115", "1116", "1117", "1118", "1119", "1120", "1136"] as Array[String], "選擇一 plays winfail900 event 0's seven lines in script order")
	var records: Array = coordinator.summary().get("story_records", [])
	var shape_changes := 0
	for record in records:
		if str((record as Dictionary).get("kind", "")) == "actor_shape_change":
			shape_changes += 1
	_assert_eq(shape_changes, 1, "the kicked soldier swaps to the 023-1000x shape set")
	var kicks := 0
	for sound in coordinator.summary().get("sound_records", []):
		if str((sound as Dictionary).get("resource", "")).ends_with("KICK001.WAV") and str((sound as Dictionary).get("status", "")) == "played":
			kicks += 1
	_assert_eq(kicks, 1, "KICK001 plays with the kick")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	_assert_true(leonard != null and not leonard.visible, "雷歐納德 walked off (actWalkAndDelete)")
	_assert_true(CampaignProgress.has_pending(), "選擇一 ends the scene through the campaign — no battle")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 9,gameBigMapLevel returns to the big map")
	var world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(world.get("current_point", 0)), 9, "the party stands at 曼多力亞 (point 9)")
	_assert_eq([WorldMapRules.point_event(world, world_map, 9), WorldMapRules.point_type(world, world_map, 9)], [0, "bmpmTown"], "actBMSetPointEvent 9,0,bmpmTown restores 曼多力亞 as a town")
	scene.queue_free()
	await process_frame
	await process_frame
	# 選擇二: the battle branch.
	var second := await _boot_900_to_choice()
	coordinator = second["coordinator"]
	if coordinator == null:
		return
	scene = second["scene"]
	coordinator.choose_select_option(1)
	var fight: Array[String] = await _run_to_end(scene, coordinator)
	_assert_eq(fight, ["1121", "1137", "1122", "1123"] as Array[String], "選擇二 plays winfail900 event 1's four lines")
	var summary: Dictionary = coordinator.summary()
	_assert_true((summary.get("camera_records", []) as Array).size() >= 3, "the three actScrollBGToPosSpeed sweeps move the camera")
	var status: Dictionary = summary.get("status_tokens", {})
	_assert_eq([status.get("win", []), status.get("fail", [])], [["0"], ["0", "1", "2"]], "event 1 arms win 0 and fail 0 / 1 / 2 before the battle")
	_assert_true(coordinator.story_finished and not CampaignProgress.has_pending(), "the not-remade battle ends the branch on the card")
	var card_options: Array = summary.get("end_card_options", [])
	_assert_eq(card_options.size(), 2, "the card offers the victory row and the plain return")
	if card_options.size() == 2:
		_assert_eq(str((card_options[0] as Dictionary).get("label", "")), "略過戰鬥（視為勝利）→ 回到大地圖", "WINFAIL900's win returns to the map (9,gameBigMapLevel)")
	coordinator.confirm_end_card_option()
	await process_frame
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the victory row returns to the big map")
	var won: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq([WorldMapRules.point_event(won, world_map, 9), WorldMapRules.point_type(won, world_map, 9)], [0, "bmpmTown"], "the victory write restores 曼多力亞 as a town")
	scene.queue_free()
	await process_frame
	await process_frame

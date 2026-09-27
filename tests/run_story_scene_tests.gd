extends SceneTree

## Story-only levels (chapter-01 epilogue 58, the level-60 throne-hall scene and
## the level-53 opening preview): the shared scene must play the compiled STORY
## timelines through BattleOpeningCoordinator without a PlayLoop, spawn the EVEF
## cast and script inserts, run forward script motion, page every message and end
## on the campaign hand-off or the end card when the next step has no scenario yet.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
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
	await _run_level_58()
	await _run_carried_job_up_forms()
	await _run_level_60()
	await _run_level_53_preview()
	await _run_level_1_preview()
	await _run_level_2_preview()
	await _run_level_2_preview_skip_battle()
	await _run_level_3_preview()
	await _run_level_5_preview()
	await _run_level_7_preview()
	await _run_level_10_preview()
	await _run_level_12_preview()
	await _run_level_6_preview()
	await _run_level_8_story()
	await _run_level_9_story()
	await _run_level_65_story()
	await _run_camp_and_hall_chains()
	await _run_level_901_preview()
	await _run_level_900_choice_branches()
	await _run_level_59_ending_film()
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


func _run_level_58() -> void:
	CampaignProgress.reset_campaign()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_058.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame

	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null, "story scene should create BattleOpeningCoordinator")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(coordinator.active and coordinator.story_mode, "coordinator should run in story mode")
	_assert_true(scene.play_loop.is_empty(), "story-only scenes must not create a PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 12, "the EVEF cast (Leonard, 058, 2x027, 8x024) should be spawned")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("map_object_spawn_count", -1)), 0, "level 58 has no stand objects")
	_assert_eq(str(scene.scene_timeline.events[0].get("kind", "")), "background_object_target", "STORY058 starts on actSetBGToObject(SID_ENEMY058)")
	var king = scene.get_node_or_null("World/Actors/ActorRuntime_actor058_1")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	var minister = scene.get_node_or_null("World/Actors/ActorRuntime_actor027_2")
	_assert_true(king != null and leonard != null and minister != null, "cast nodes should exist")
	if king != null:
		_assert_true(king.position.is_equal_approx(Vector2(256 + 16, 256 + 16)), "the elf king stands at his EVEF cell centre")
		_assert_true(scene.camera.position.distance_to(scene.camera_controller.clamped_position(king.position + Vector2(0, 48))) < 1.0, "the first token frames the elf king (at the view's (320,192), 0x43bf30)")
	if leonard != null:
		_assert_true(leonard.position.is_equal_approx(Vector2(384 + 16, 768 + 16)), "Leonard starts at his EVEF placement")

	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005

	var dialogue_event_ids: Array[String] = []
	var narration_seen := false
	var star_seen := false
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		var kind := str(current.get("current_event_kind", ""))
		if kind == "dialogue_message_id":
			_assert_true(scene.opening_overlay.visible, "dialogue token must show the shared dialogue board")
			var event_id := str(current.get("current_event_id", ""))
			if not dialogue_event_ids.has(event_id):
				dialogue_event_ids.append(event_id)
				if str(scene.scene_timeline.current_event().get("message_id", "")) == "675":
					narration_seen = not scene.opening_overlay.portrait.visible and scene.opening_overlay.speaker_label.text == ""
				elif str(scene.scene_timeline.current_event().get("message_id", "")) == "663":
					_assert_eq(scene.opening_overlay.speaker_label.text, "克里歐司：", "the elf king speaks 663 with his PLAYERS name")
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			coordinator.handle_input(click)
		if scene.get_node_or_null("World/StoryObject_obj_Story_Level58_Star") != null:
			star_seen = true
		await process_frame
		frames += 1

	_assert_true(coordinator.story_finished, "story scene should reach its end marker within the frame budget")
	_assert_eq(dialogue_event_ids.size(), 18, "all eighteen STORY058 messages should be paged")
	_assert_true(narration_seen, "message 675 (defNoOne) should render as portrait-less narration")
	_assert_true(star_seen, "actInsertStoryObject should place the medal sprite")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq(final_summary.get("next_level_event", []), [60, 60], "actSetNextPlayLevelEvent(60,60) should be recorded")
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY058 token may be silently skipped")
	var deleted := 0
	for record in final_summary.get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == "actor_deleted":
			deleted += 1
	_assert_eq(deleted, 3, "Leonard and the two escort knights leave through actWalkAndDelete")
	if leonard != null:
		_assert_true(not leonard.visible, "Leonard should be hidden after his actWalkAndDelete walk")
		_assert_true(leonard.position.is_equal_approx(Vector2(384 + 16, 768 + 16)), "Leonard's final walk target is the script pixel (384,768)")
	var knight3 = scene.get_node_or_null("World/Actors/ActorRuntime_actor024_3")
	if knight3 != null:
		_assert_true(knight3.position.is_equal_approx(Vector2(416 + 16, 768 + 16)), "knight 3 follows/leaves to (416,768)")
	_assert_true(scene.get_node_or_null("UI/ChapterEndCard") == null, "level 58 continues into level 60 instead of ending the chapter")
	_assert_true(CampaignProgress.has_pending(), "scene end hands the campaign to the next story scene")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_060.json", "next_level_event [60,60] resolves to story_060.json")
	_assert_eq(str(CampaignProgress.load_progress().get("scenario_path", "")), "res://content/battles/story_060.json", "the story hand-off persists the campaign position")
	_assert_true(coordinator.active, "the coordinator keeps the scene blocked until the reload")
	var sounds: Array = final_summary.get("sound_records", [])
	_assert_eq(sounds.size(), 2, "COIN001 and COIN002 should be recorded")
	for record in sounds:
		_assert_eq(str((record as Dictionary).get("status", "")), "played", "decoded coin sounds should play")
	scene.queue_free()
	await process_frame
	await process_frame


## Story-only scenes have no PlayLoop unit behind a cast member: the hand-off carry's
## job-up row (a 命運神殿 title, or 37's 咕嚕 → 017) is what the cast is drawn with,
## the same shared up-title frames the battles use; members without one keep their row.
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


func _run_level_60() -> void:
	CampaignProgress.reset_campaign()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_060.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 60 should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "level 60 has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 15, "the EVEF cast (058, 2x027, 8x024, 3x023, 029) should be spawned")
	_assert_true(scene.get_node_or_null("World/Actors/ActorRuntimeLeonard") == null, "Leonard is absent from the level-60 scene")
	var princess = scene.get_node_or_null("World/Actors/ActorRuntime_actor029_1")
	_assert_true(princess != null, "the captive princess actor should exist")
	if princess != null:
		_assert_true(princess.position.is_equal_approx(Vector2(384 + 16, 832 + 16)), "actor029_1 starts at its EVEF placement")
	_fast(coordinator)
	var dialogue_event_ids: Array[String] = []
	var message_ids: Array[String] = []
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var event_id := str(current.get("current_event_id", ""))
			if not dialogue_event_ids.has(event_id):
				dialogue_event_ids.append(event_id)
				var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
				if not message_ids.has(message_id):
					message_ids.append(message_id)
				if message_id == "683":
					_assert_eq(scene.opening_overlay.speaker_label.text, "緹娜：", "SID_ENEMY029 speaks as 緹娜 (PLAYERS name_1)")
				elif message_id == "676":
					_assert_eq(scene.opening_overlay.speaker_label.text, "一般兵：", "SID_ENEMY023 keeps the remake soldier label")
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "level 60 should reach its end marker within the frame budget")
	_assert_eq(dialogue_event_ids.size(), 20, "all twenty STORY060 message tokens should be paged")
	_assert_eq(message_ids.size(), 18, "seventeen new ids plus the reused 380 ellipsis")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq(final_summary.get("next_level_event", []), [53, 53], "actSetNextPlayLevelEvent(53,53) should be recorded")
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY060 token may be silently skipped")
	var deleted: Array[String] = []
	for record in final_summary.get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == "actor_deleted":
			deleted.append(str((record as Dictionary).get("unit_id", "")))
	deleted.sort()
	_assert_eq(deleted, ["actor023_1", "actor023_2", "actor023_3", "actor029_1"], "escorts and the princess leave through actWalkAndDelete(Wait)")
	if princess != null:
		_assert_true(not princess.visible and princess.position.is_equal_approx(Vector2(384 + 16, 800 + 16)), "the princess exits toward (384,800) and is hidden")
	_assert_true(scene.get_node_or_null("UI/ChapterEndCard") == null, "level 60 continues into the level-53 battle")
	_assert_true(CampaignProgress.has_pending(), "scene end hands the campaign to battle_053.json")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_053.json", "next_level_event [53,53] resolves to the level-53 battle scenario")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_53_preview() -> void:
	## STORY053 opening: 緹娜 resolves in the tower, climbs down the rope (shape
	## swap + pixel slide), is discovered, two guards enter by script, the escape
	## cells are marked; the preview ends where player control would begin. It is
	## kept as the story-mode regression of the STORY053 tokens; the campaign now
	## routes level 53 to the battle scenario (battle_053.json).
	CampaignProgress.reset_campaign()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_053.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 53 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the opening preview has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 2, "EVEF cast: the tower princess copy and the gate guard")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("map_object_spawn_count", -1)), 20, "level 53 stand objects should be placed")
	var story_copy = scene.get_node_or_null("World/Actors/ActorRuntime_actor029_1")
	_assert_true(story_copy != null and story_copy.position.is_equal_approx(Vector2(640 + 16, 448 + 16)), "SID_ENEMY029 starts in the tower window cell")
	_assert_true(scene.get_node_or_null("World/Actors/ActorRuntime_tina") == null, "the controlled princess is installed only by obj_Story_Player2")
	_fast(coordinator)
	coordinator.move_pixels_per_frame_hz = 60000.0
	var message_ids: Array[String] = []
	var climb_frames_seen := false
	var markers_seen := 0
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				if message_id == "699":
					_assert_eq(scene.opening_overlay.speaker_label.text, "緹娜：", "SID_ENEMY029 speaks 699 as 緹娜")
				elif message_id == "701":
					_assert_eq(scene.opening_overlay.speaker_label.text, "緹娜：", "SID_PLAYER1 (installed slot) speaks 701 as 緹娜")
				elif message_id == "702":
					_assert_eq(scene.opening_overlay.speaker_label.text, "一般兵：", "the inserted guard speaks 702")
			_click(coordinator)
		var tina = scene.get_node_or_null("World/Actors/ActorRuntime_tina")
		if tina != null and tina.has_shape_override():
			climb_frames_seen = true
		markers_seen = maxi(markers_seen, coordinator.story_objects._position_markers.size())
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	_assert_eq(message_ids, ["698", "699", "700", "701", "702", "703"], "STORY053 opening messages in script order")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY053 opening token may be silently skipped")
	_assert_true(climb_frames_seen, "actChangeShape should swap 緹娜 to the rope-climb frames while she descends")
	_assert_eq(markers_seen, 4, "four actInsertShowPosObject cells mark the escape zone")
	_assert_eq(coordinator.story_objects._position_markers.size(), 0, "actDeleteShowPosObject clears the markers")
	var kinds: Array[String] = []
	for record in final_summary.get("story_records", []):
		kinds.append(str((record as Dictionary).get("kind", "")))
	_assert_true(kinds.has("actor_shape_change") and kinds.has("actor_shape_restore"), "shape change and restore should be recorded")
	_assert_true(kinds.has("actor_deleted"), "the story copy of 緹娜 leaves through actWalkAndDeleteWait")
	var tina = scene.get_node_or_null("World/Actors/ActorRuntime_tina")
	_assert_true(tina != null, "obj_Story_Player2 installs the controlled princess")
	if tina != null:
		_assert_true(not tina.has_shape_override(), "actRestoreShape returns her walk frames")
		_assert_true(tina.position.is_equal_approx(Vector2(640 + 16, 416 + 32 + 288 + 16)), "she walks 32px down then slides 288px down the rope to (640,736)")
	var guard1 = scene.get_node_or_null("World/Actors/ActorRuntime_guard023_1")
	var guard2 = scene.get_node_or_null("World/Actors/ActorRuntime_guard023_2")
	_assert_true(guard1 != null and guard2 != null, "both script guards should be inserted")
	if guard1 != null:
		_assert_true(guard1.position.is_equal_approx(Vector2(928 + 16, 768 + 16)), "guard 1 walks from the right edge to (928,768)")
	if guard2 != null:
		_assert_true(guard2.position.is_equal_approx(Vector2(864 + 16, 736 + 16)), "guard 2 walks to (864,736)")
	_assert_true(scene.get_node_or_null("World/StoryObject_obj_Story_Level53_Rope") != null, "the rope sprite should be inserted")
	var status: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(status.get("win", []), ["0"], "actInsertWinStatus,0 recorded")
	_assert_eq(status.get("event", []), ["0", "1", "2"], "the three WINFAIL053 events are enabled")
	_assert_eq(str((status.get("dead_message", {}) as Dictionary).get("message_id", "")), "694", "緹娜's death message 694 is registered")
	_assert_eq(final_summary.get("next_level_event", []), [], "the opening sets no next level; the battle would follow")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	if card != null:
		var texts: Array[String] = []
		for child in card.get_children():
			if child is Label:
				texts.append((child as Label).text)
		_assert_true(texts.has("逃出克萊恩城"), "the card carries the scene title")
		_assert_true(texts.size() == 2 and texts[1].begins_with("戰鬥部分（level 53）尚未重製"), "the card states the battle is not remade")
	_assert_true(not CampaignProgress.has_pending(), "no campaign hand-off is pending at the preview end")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_2_preview() -> void:
	## STORY002 opening preview (戈爾山道), entered from the big map: the five raiders
	## run up the road from the south-east edge, the camera turns to 雷歐納德 and
	## 琥 following them, the exchange, then first control — where the preview stops
	## with the not-remade card and returns to the big map standing at 戈爾山道.
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
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 2 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the opening preview has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 7, "EVEF cast: 雷歐納德, 琥 and five raiders")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	var hu = scene.get_node_or_null("World/Actors/ActorRuntime_hu")
	var raider1 = scene.get_node_or_null("World/Actors/ActorRuntime_actor028_1")
	var raider5 = scene.get_node_or_null("World/Actors/ActorRuntime_actor028_5")
	_assert_true(leonard != null and leonard.position.is_equal_approx(Vector2(832 + 16, 672 + 16)), "雷歐納德 starts on his EVEF install cell off the south-east edge of the 768x640 map")
	_assert_true(hu != null and hu.position.is_equal_approx(Vector2(864 + 16, 608 + 16)), "琥 starts on her EVEF install cell")
	_assert_true(raider1 != null and raider1.position.is_equal_approx(Vector2(736 + 16, 704 + 16)), "raider 1 waits below the map")
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
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	_assert_eq(message_ids, ["750", "751", "752", "753", "754", "755", "756", "757"] as Array[String], "STORY002 pages its eight lines in script order")
	_assert_eq(str(speakers.get("750", "")), "盜賊：", "SID_ENEMY028 speaks 750 under its remake label 盜賊")
	_assert_eq(str(speakers.get("752", "")), "", "752 is narration (defNoOne) without a speaker")
	_assert_eq(str(speakers.get("753", "")), "琥：", "SID_琥 speaks 753 as 琥")
	_assert_eq(str(speakers.get("757", "")), "雷歐納德：", "SID_雷歐納德 speaks 757")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY002 opening token may be silently skipped")
	if raider1 != null:
		_assert_true(raider1.position.is_equal_approx(Vector2(128 + 16, 64 + 16)), "raider 1 runs up the road to the script pixel (128,64)")
	if raider5 != null:
		_assert_true(raider5.position.is_equal_approx(Vector2(192 + 16, 128 + 16)), "raider 5 runs to (192,128)")
	if hu != null:
		_assert_true(hu.position.is_equal_approx(Vector2(704 + 16, 512 + 16)), "琥 walks onto the road at (704,512)")
	if leonard != null:
		_assert_true(leonard.position.is_equal_approx(Vector2(640 + 16, 544 + 16)), "雷歐納德 walks to (640,544)")
	_assert_true(scene.camera.position.x <= 768.0 - 320.0 + 0.5 and scene.camera.position.y <= 640.0 - 240.0 + 0.5, "the camera stays inside the 768x640 map while it follows the party (%s)" % [scene.camera.position])
	var status: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(status.get("event", []), ["0"], "WINFAIL002 event status 0 is enabled")
	_assert_eq(status.get("fail", []), ["0", "1"], "WINFAIL002 fail statuses 0 and 1 are enabled")
	_assert_eq(str((status.get("dead_message", {}) as Dictionary).get("message_id", "")), "743", "the last registered dead message is 琥's 743")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	if card != null:
		var texts: Array[String] = []
		for child in card.get_children():
			if child is Label:
				texts.append((child as Label).text)
		_assert_true(texts.has("戈爾山道"), "the card carries the scene title")
		_assert_true(texts.size() == 4 and texts[1] == "戰鬥部分（level 2）尚未重製", "the card states the battle is not remade (two-row choice: no single-confirm key hint)")
		_assert_true(texts.size() == 4 and texts[3].ends_with("回到大地圖（不施加戰果）"), "the card's second row is the plain return to the big map")
	_assert_true(not CampaignProgress.has_pending(), "no campaign hand-off is pending at the preview end")
	# The plain return (row 2) goes back to the big map standing at 戈爾山道 with the carry intact.
	coordinator.select_end_card_option(1)
	_click(coordinator)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming 回到大地圖（不施加戰果） hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the hand-off targets campaign.json's world_map scene")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 2, "the party still stands at 戈爾山道 (point 2)")
	_assert_eq((CampaignProgress.pending.get("world", {}) as Dictionary).get("visited_points", []), [1, 2], "the carried world state keeps its visited points")
	_assert_eq(WorldMapRules.point_event(CampaignProgress.pending.get("world", {}), world_map, 2), 2, "the plain return applies none of the skipped battle's win-section writes")
	_assert_eq(int(((CampaignProgress.pending.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", 0)), 275, "the carry passes through the preview unchanged")
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
	_assert_eq((skip.get("world_actions", []) as Array).size(), 3, "the win section writes point 2's event, encounter ratio and track 3's flag")
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
	var skipped: Dictionary = {}
	for record in coordinator.summary().get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == "battle_skipped":
			skipped = record
	_assert_eq(int(skipped.get("level", 0)), 2, "the skip is recorded against level 2")
	_assert_eq(int(skipped.get("world_action_count", 0)), 3, "the record counts the applied world actions")
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


func _run_level_3_preview() -> void:
	## STORY003 opening preview (盜賊洞窟), entered from the big map: 漢克斯 is set
	## hostile / undead by script (recorded only), the three mercenaries walk in from
	## the west edge, two raiders come to meet them, then first control — where the
	## preview stops with the not-remade card and returns to the big map at point 3.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.visit(WorldMapRules.initial_state(world_map, 1), world_map, 2), world_map, 3)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_003.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_003.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 3 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the opening preview has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 17, "EVEF cast: four controlled slots, nine raiders and four winged raiders")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	var tina = scene.get_node_or_null("World/Actors/ActorRuntime_tina")
	var hu = scene.get_node_or_null("World/Actors/ActorRuntime_hu")
	var hanks = scene.get_node_or_null("World/Actors/ActorRuntime_hanks")
	var raider1 = scene.get_node_or_null("World/Actors/ActorRuntime_actor028_1")
	_assert_true(leonard != null and leonard.position.is_equal_approx(Vector2(-64 + 16, 288 + 16)), "雷歐納德 starts off the west edge (signed EVEF x -64)")
	_assert_true(hu != null and hu.position.is_equal_approx(Vector2(-128 + 16, 288 + 16)), "琥 starts at EVEF x -128")
	_assert_true(hanks != null and hanks.position.is_equal_approx(Vector2(1056 + 16, 448 + 16)), "漢克斯 waits inside the cave on his EVEF install cell")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var panel_tops: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
				panel_tops[message_id] = scene.opening_overlay.position.y
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	_assert_eq(message_ids, ["828", "829", "830", "831", "832", "833"] as Array[String], "STORY003 pages its six lines in script order")
	# The cave party speaks from (160,320) on the 1152x672 map, above the bottom panel
	# band, so the panel keeps the source bottom slot.
	_assert_eq(float(panel_tops.get("829", -1.0)), 320.0, "雷歐納德 speaks 829 above the panel band, so the panel keeps the source bottom slot")
	_assert_eq(str(speakers.get("828", "")), "盜賊：", "SID_ENEMY028 speaks 828 as 盜賊")
	_assert_eq(str(speakers.get("829", "")), "雷歐納德：", "SID_雷歐納德 speaks 829")
	_assert_eq(str(speakers.get("833", "")), "漢克斯：", "SID_漢克斯 speaks 833 as 漢克斯 (speaker resource 3)")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY003 opening token may be silently skipped")
	var recorded: Array = (final_summary.get("story_records", []) as Array).filter(func(record): return str(record.get("kind", "")) in ["player_mode_set", "player_undead_flag"])
	_assert_eq(recorded.size(), 2, "漢克斯's pmEnemy mode and undead flag are recorded, not applied")
	if leonard != null:
		_assert_true(leonard.position.is_equal_approx(Vector2(160 + 16, 320 + 16)), "雷歐納德 walks in to (160,320)")
	if tina != null:
		_assert_true(tina.position.is_equal_approx(Vector2(96 + 16, 320 + 16)), "緹娜 walks in to (96,320)")
	if hu != null:
		_assert_true(hu.position.is_equal_approx(Vector2(128 + 16, 288 + 16)), "琥 walks in to (128,288)")
	if raider1 != null:
		_assert_true(raider1.position.is_equal_approx(Vector2(288 + 16, 288 + 16)), "raider 1 comes to meet them at (288,288)")
	_assert_true(scene.camera.position.x >= 320.0 - 0.5 and scene.camera.position.y >= 240.0 - 0.5, "the camera stays inside the 1152x672 map while the party enters from off-map (%s)" % [scene.camera.position])
	var status: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(status.get("event", []), ["0", "1", "2"], "WINFAIL003 event statuses 0-2 are enabled")
	_assert_eq(status.get("fail", []), ["0", "1"], "WINFAIL003 fail statuses 0 and 1 are enabled")
	_assert_eq(str((status.get("dead_message", {}) as Dictionary).get("message_id", "")), "846", "the last registered dead message is 緹娜's 846")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	if card != null:
		var texts: Array[String] = []
		for child in card.get_children():
			if child is Label:
				texts.append((child as Label).text)
		_assert_true(texts.has("盜賊洞窟"), "the card carries the scene title")
		_assert_true(texts.size() == 4 and texts[1] == "戰鬥部分（level 3）尚未重製", "the card states the battle is not remade")
		_assert_true(texts.size() == 4 and texts[2] == "▶ 略過戰鬥（視為勝利）→ 續播劇情『營地・漢克斯的報告』", "WINFAIL003's win (61,61) offers the camp report as the skip destination")
	coordinator.select_end_card_option(1)
	_click(coordinator)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming 回到大地圖（不施加戰果） hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the hand-off targets campaign.json's world_map scene")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 3, "the party still stands at 盜賊洞窟 (point 3)")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_8_story() -> void:
	## STORY008 (菲納斯河畔) is a complete story-only scene entered from the big map:
	## the five-member party walks up from the south edge, bickers at the Lars border,
	## walks on west, and the script marks point 8 visited, turns 廢都 (9) into a
	## battle point and returns to the big map standing at point 8.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 7), world_map, 8)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_008.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_008.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 8 should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the story scene has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 5, "EVEF cast: the five-member party")
	var shera = scene.get_node_or_null("World/Actors/ActorRuntime_shera")
	_assert_true(shera != null and shera.position.is_equal_approx(Vector2(1376 + 16, 928 + 16)), "雪拉 (actor 005) starts below the 1504x800 map on her EVEF cell")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var panel_tops: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000 and not CampaignProgress.has_pending():
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
				panel_tops[message_id] = scene.opening_overlay.position.y
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(message_ids, ["1052", "1053", "1054", "1055", "380", "1056"] as Array[String], "STORY008 pages its six lines in script order")
	# 雪拉 speaks 1053 from (1408,736) on the 1504x800 map: the camera clamps at the south
	# edge and she stands inside the bottom panel band; an actMessage line still keeps the
	# bottom slot (the top slot is only for script-faced lines, BattleDialogue.PANEL_TOP_TOP_SLOT).
	_assert_eq(float(panel_tops.get("1053", -1.0)), 320.0, "雪拉's actMessage line keeps the bottom slot although she speaks from the riverside's south band")
	_assert_eq(str(speakers.get("1053", "")), "雪拉：", "SID_雪拉 speaks 1053 as 雪拉 (speaker resource 4)")
	_assert_eq(str(speakers.get("1054", "")), "漢克斯：", "SID_漢克斯 speaks 1054")
	_assert_true(CampaignProgress.has_pending(), "the scene end hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "actSetNextPlayLevelEvent 8,gameBigMapLevel returns to the big map")
	var next_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(next_world.get("current_point", 0)), 8, "the party stands at 菲納斯河畔 (point 8)")
	_assert_true((WorldMapRules.point_flags(next_world, world_map, 8) as Array).has("bmpmVisit"), "actBMSetPointEvent 8,8,bmpmVisit marks point 8 visited in the hand-off world state")
	_assert_eq(WorldMapRules.point_type(next_world, world_map, 9), "bmpmBattle", "actBMSetPointEvent 9,9,bmpmBattle turns 廢都 into a battle point")
	_assert_eq(int(((next_world.get("encounter_ratios", {}) as Dictionary).get("8", -1))), 0, "actBMSetPointEncounterRatio 8,0 is applied")
	_assert_eq(int(((CampaignProgress.pending.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", 0)), 275, "the carry passes through the story scene unchanged")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_9_story() -> void:
	## STORY009 (廢都 曼多利亞) follows level 8's rewrite of point 9 into a battle point:
	## villagers wander the ruins, the party walks in from the south, 緹娜 is revealed
	## as the princess, the script turns point 9 back into a town and chains to level
	## 65 — unregistered, so the scene ends on its card and returns to the big map.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.initial_state(world_map, 8)
	var towndef: Dictionary = TownEventRules.load_towndef("res://content/imported/hsl/global/world_map/towndef.json")
	var armed: Dictionary = TownEventRules.apply_script_town_actions(world, [{"name": "actBMSetPointEvent", "args": ["9", "9", "bmpmBattle"]}], towndef)
	world = armed.get("state", world)
	_assert_eq(WorldMapRules.point_type(world, world_map, 9), "bmpmBattle", "precondition: STORY008 has turned 廢都 into a battle point")
	world = WorldMapRules.visit(world, world_map, 9)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_009.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_009.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 9 should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the story scene has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 19, "EVEF cast: the party plus fourteen 061 / 062 villagers")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 6000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(message_ids, ["1057", "1058", "1059", "380", "1060"] as Array[String], "STORY009 pages its five lines in script order (actMEssage matched case-insensitively)")
	_assert_eq(str(speakers.get("1059", "")), "雪拉：", "SID_雪拉 speaks 1059 through the misspelled actMEssage token")
	_assert_true(coordinator.story_finished, "the story reaches its end marker")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY009 token is skipped")
	var tina = scene.get_node_or_null("World/Actors/ActorRuntime_tina")
	_assert_true(tina != null and tina.position.is_equal_approx(Vector2(704 + 16, 1024 + 16)), "緹娜 ends on her last actWalkWait target (704,1024)")
	_assert_true(CampaignProgress.has_pending(), "actSetNextPlayLevelEvent 9,65 hands off to the registered level 65")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_065.json", "the next scene is the 廢都 interior")
	var next_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(next_world.get("current_point", 0)), 9, "the carried world still stands at 廢都 (point 9)")
	_assert_eq(WorldMapRules.point_type(next_world, world_map, 9), "bmpmTown", "actBMSetPointEvent 9,0,bmpmTown turns 廢都 back into a town in the hand-off world state")
	_assert_eq(WorldMapRules.point_event(next_world, world_map, 9), 0, "the point event is cleared to 0")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_65_story() -> void:
	## STORY065 (the 廢都 interior, chained from level 9): 緹娜 asks the villagers for
	## help and is refused, the party leaves one by one (actWalkAndDelete) and 雷歐納德
	## has the last word; level 66 has no map shape yet, so the scene ends on its
	## card and returns to the big map at 廢都.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 8), world_map, 9)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_065.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "story_009_mandoria_ruins", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_065.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 65 should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 12, "EVEF cast: the party plus seven villagers on the 640x480 interior")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 6000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(message_ids, ["1061", "1062", "1063", "1064", "1065", "1066", "1067", "1068", "1069", "380", "1070", "1071", "1072", "1073", "1074", "1075"] as Array[String], "STORY065 pages its 17 message tokens (380 twice) in script order")
	_assert_eq(str(speakers.get("1062", "")), "村民：", "SID_ENEMY062 speaks as 村民 (remake label 656)")
	_assert_eq(str(speakers.get("1075", "")), "雷歐納德：", "雷歐納德 has the last word")
	_assert_true(coordinator.story_finished, "the story reaches its end marker")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY065 token is skipped")
	var still_visible: Array[String] = []
	for unit_id in ["tina", "hanks", "hu", "shera", "leonard"]:
		var actor = scene.actor_node_for_unit(unit_id)
		if actor == null or actor.visible:
			still_visible.append(unit_id + (":missing" if actor == null else ":moving=%s" % str(actor.is_moving())))
	_assert_eq(still_visible, [] as Array[String], "the five actWalkAndDelete walks hide the whole party")
	var deleted: Array[String] = []
	for record in coordinator.story_records:
		if str(record.get("kind", "")) == "actor_deleted":
			deleted.append(str(record.get("unit_id", "")))
	_assert_eq(deleted, ["tina", "hanks", "hu", "shera", "leonard"] as Array[String], "actor_deleted records in walk order")
	# Level 66 (營地・廢都之後, the camp after the ruins) is registered now: STORY065's
	# actSetNextPlayLevelEvent 9,66 hands off there instead of ending on the card.
	_assert_true(CampaignProgress.has_pending(), "STORY065 hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_066.json", "actSetNextPlayLevelEvent 9,66 chains to 營地・廢都之後")
	var next_world: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(next_world.get("current_point", 0)), 9, "the party still stands at 廢都 (point 9)")
	scene.queue_free()
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


func _run_level_6_preview() -> void:
	## STORY006 (席達鎮): the party is installed by obj_Story_Player1-4 inserts at the
	## east gate and walks in, three Wosfita soldiers 023 and their captain 024 follow
	## (actInsertObject + the non-wait actWalkPrevInsertObject), the captain denounces
	## 雷歐納德; the battle is not remade, so the preview ends on its card.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 5), world_map, 6)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_006.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_006.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 6 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.actor_node_for_unit("leonard") == null, "the party is not on the EVEF map before its obj_Story_Player inserts")
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
	_assert_eq(message_ids, ["950", "951", "952"] as Array[String], "STORY006 pages the captain's denunciation, the soldier's objection and the reply")
	_assert_eq(str(speakers.get("950", "")), "重裝兵：", "the captain 024 speaks first")
	_assert_eq(str(speakers.get("951", "")), "一般兵：", "SID_ENEMY023,8 is read as the first inserted soldier")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY006 token is skipped")
	var spawned: Array[String] = []
	for record in coordinator.story_records:
		if str(record.get("kind", "")) == "story_object_insert" and record.has("spawned_unit_id"):
			spawned.append(str(record.get("spawned_unit_id", "")))
	_assert_eq(spawned, ["leonard", "tina", "hu", "hanks"] as Array[String], "obj_Story_Player1-4 spawn the four controlled slots in order")
	var leonard = scene.actor_node_for_unit("leonard")
	_assert_true(leonard != null and leonard.visible and leonard.position.is_equal_approx(Vector2(736 + 16, 256 + 16)), "雷歐納德 walks from the gate insert to (736,256)")
	var captain = scene.actor_node_for_unit("guard024_1")
	_assert_true(captain != null and captain.visible and captain.position.is_equal_approx(Vector2(992 + 16, 256 + 16)), "the inserted captain walks to (992,256) by the non-wait actWalkPrevInsertObject")
	var soldier = scene.actor_node_for_unit("guard023_3")
	_assert_true(soldier != null and soldier.position.is_equal_approx(Vector2(928 + 16, 288 + 16)), "the third inserted soldier reaches (928,288)")
	var recorded: Array[String] = []
	for record in coordinator.story_records:
		if str(record.get("kind", "")) == "player_level_adjust_all":
			recorded.append(str(record.get("status", "")))
	_assert_eq(recorded, ["recorded_no_handler"] as Array[String], "actAdjustAllPlayerLevel is recorded, not applied")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	coordinator.handle_input(space)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the card's victory row hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_062.json", "WINFAIL006's win (6,62) continues at 營地・漢克斯的警告")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 6, "the party stands at 席達鎮 (point 6)")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_7_preview() -> void:
	## STORY007 (寧靜之森): the party walks north into the silent forest, 緹娜 and 琥
	## speak, 036 / 037 / 038 pour in from every edge, 雷歐納德 closes; the battle is
	## not remade, so the preview ends on its card and returns to the map.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 6), world_map, 7)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_007.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_007.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 7 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 25, "EVEF cast: four controlled slots, ten 036, six 038 and five 037")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var panel_tops: Dictionary = {}
	var speaker_logical_y: Dictionary = {}
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 4000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
				panel_tops[message_id] = scene.opening_overlay.position.y
				var speaker_unit := str(coordinator.binding_for_token(str(scene.scene_timeline.current_event().get("actor_token", "")), "1").get("unit_id", ""))
				var speaker_node = scene.actor_node_for_unit(speaker_unit)
				speaker_logical_y[message_id] = scene.camera_controller.world_to_logical(speaker_node.position).y if speaker_node != null else -1.0
			_click(coordinator)
		await process_frame
		frames += 1
	_assert_eq(message_ids, ["1007", "1008", "1009"] as Array[String], "STORY007 pages its three lines in script order")
	_assert_eq(str(speakers.get("1009", "")), "雷歐納德：", "雷歐納德 closes the opening")
	# The forest party speaks from the map's south edge: the camera clamps there, so the
	# speaker's logical y falls inside the bottom panel band — and the board still takes the
	# bottom slot: the original raises it only for script-faced lines (flag 0x4000, see
	# BattleDialogue.PANEL_TOP_TOP_SLOT), never for where the speaker stands.
	_assert_true(float(speaker_logical_y.get("1007", -1.0)) >= 320.0, "緹娜 stands inside the bottom panel band when she speaks 1007 (logical y %s)" % str(speaker_logical_y.get("1007")))
	_assert_eq(float(panel_tops.get("1007", -1.0)), 320.0, "緹娜's actMessage line keeps the bottom slot although she stands under it")
	_assert_eq(float(panel_tops.get("1009", -1.0)), 320.0, "雷歐納德 at (448,704) speaks from the south band too, and 1009 keeps the bottom slot")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY007 token is skipped")
	var leonard = scene.actor_node_for_unit("leonard")
	_assert_true(leonard != null and leonard.position.is_equal_approx(Vector2(448 + 16, 704 + 16)), "雷歐納德 ends on his actWalkWait target (448,704)")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	coordinator.handle_input(space)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the card's victory row hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_064.json", "WINFAIL007's win (7,64) continues at 營地・雪拉入隊")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 7, "the party stands at 寧靜之森 (point 7)")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_level_10_preview() -> void:
	## STORY010 (帕尼西亞城 廢墟): 雷歐納德 and 緹娜 before the ruined capital; the rain
	## controllers start the downpour and its looping sound, the camera scrolls to the
	## old tree, lightning flashes with fire bombs, the tree is swapped for the burning
	## 樹03 with five 火01 flames, the 034 / 035 creatures close in. The battle is not
	## remade, so the preview ends on its card and returns to the map at point 10.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 9), world_map, 10)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_010.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 275}}, "from_scenario_id": "world_map_scene", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_010.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 10 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 6, "EVEF cast: 雷歐納德, 緹娜, two 034 and two 035")
	var tree02: Node = null
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		for child in layer.get_children():
			if child.has_meta("candidate_anchor_world") and (child.get_meta("candidate_anchor_world") as Vector2).is_equal_approx(Vector2(528, 418)):
				tree02 = child
	_assert_true(tree02 != null and tree02.visible, "the EVEF 樹02 stands at (528,418) before the strike")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var seen_events: Dictionary = {}
	var max_drops := 0
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
		for child in scene.world_root.get_children():
			if str(child.name).begins_with("StoryEffect_obj_Story_Level10_RainBoss"):
				max_drops = maxi(max_drops, child.drops.size())
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	_assert_eq(message_ids, ["1081", "380", "1082", "1083", "873", "1084", "1085", "1086", "380", "1087", "873", "1088", "797", "1089", "1090", "1091", "1092", "1002", "1093"] as Array[String], "STORY010 pages its nineteen lines in script order")
	_assert_eq(str(speakers.get("1081", "")), "雷歐納德：", "雷歐納德 opens before the ruins")
	_assert_eq(str(speakers.get("1087", "")), "緹娜：", "緹娜 asks whether she is being contemptible (1087)")
	_assert_eq(coordinator.skipped_records.size(), 0, "no STORY010 token is skipped")
	# Effect readings: two rain controllers (4 drops per tick from obj_Data3 0x00020004),
	# the looping rain sound, two lightning flashes, four fire bombs, two glows and the
	# five 火01 frame loops; the struck 樹02 is hidden and 樹03 stands in its place.
	var effects: Dictionary = {}
	var rain_status := ""
	for record in coordinator.story_records:
		if record.has("effect"):
			effects[str(record["effect"])] = int(effects.get(str(record["effect"]), 0)) + 1
			if str(record["effect"]) == "background_sound":
				rain_status = str(record.get("status", ""))
	_assert_eq(effects, {"rain_emitter": 2, "background_sound": 1, "flash": 2, "frame_once": 4, "glow": 2, "frame_loop": 5}, "STORY010's inserted objects resolve to their effect readings")
	_assert_eq(rain_status, "looping", "雨聲 loops the decoded RAIN001.WAV")
	_assert_true(max_drops > 20, "the rain emitters keep falling drops over the view (max %d)" % max_drops)
	_assert_true(tree02 != null and not tree02.visible, "actDeletePosObject 528,418 hides the EVEF 樹02")
	var tree03: Node = scene.world_root.get_node_or_null("StoryObject_obj_Story_Level10_Tree")
	_assert_true(tree03 != null and tree03.visible, "樹03 is inserted where the tree stood")
	var fires := 0
	for child in scene.world_root.get_children():
		if str(child.name).begins_with("StoryEffect_obj_Story_Level10_Fire"):
			fires += 1
	_assert_eq(fires, 5, "five 火01 frame loops keep burning on the tree")
	var played := 0
	for record in coordinator.sound_records:
		if str(record.get("status", "")) == "played":
			played += 1
	_assert_eq(played, 3, "LIGHTN007 twice and BOMB0027 once are played from the level's decoded sounds")
	var camera_center: Vector2 = scene.camera.position
	_assert_true(camera_center.x >= 320.0 and camera_center.x <= 640.0 and camera_center.y >= 240.0 and camera_center.y <= 464.0, "the camera centre stays inside the 960x704 map")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	coordinator.handle_input(space)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the card hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "WINFAIL010's win (10,gameBigMapLevel) returns to the big map")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 10, "the party stands at 帕尼西雅城 廢墟 (point 10)")
	_assert_eq(WorldMapRules.point_event(CampaignProgress.pending.get("world", {}), world_map, 10), 513, "actBMSetPointEvent 10,513,bmpmVisit is applied as the skipped victory")
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


func _run_level_1_preview() -> void:
	## STORY001 opening preview (歐姆村): the village morning with 雷歐納德 and 琥,
	## villagers pacing, the six raiders and two winged raiders marching up from
	## the south edge, then first player control — where the preview stops with
	## the not-remade card because the level-1 battle waits for its job models.
	CampaignProgress.reset_campaign()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_001.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	# Keep this direct preview regression independent of campaign[1], now a real battle.
	var preview_progress = scene.get_node("CampaignProgress")
	preview_progress.campaign["battles"]["1"] = {"scenario":"res://content/battles/story_001.json","kind":"story","title":"歐姆村（開場預覽）"}
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "level 1 preview should run in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the opening preview has no PlayLoop")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("actor_runtime_count", 0)), 18, "EVEF cast: 8 villagers, 雷歐納德, 琥, 6 raiders, 2 winged raiders")
	_assert_eq(int(RuntimeReadback.runtime_contract_summary(scene).get("map_object_spawn_count", -1)), 88, "level 1 places its 33 stand objects (incl. the 寶藏 chest) plus the 55 children of the 26 combined tree/house + shadow groups")
	var leonard = scene.get_node_or_null("World/Actors/ActorRuntimeLeonard")
	var hu = scene.get_node_or_null("World/Actors/ActorRuntime_hu")
	_assert_true(leonard != null and leonard.position.is_equal_approx(Vector2(544 + 16, 448 + 16)), "雷歐納德 starts on his EVEF install cell")
	_assert_true(hu != null and hu.position.is_equal_approx(Vector2(512 + 16, 480 + 16)), "琥 (actor 003) starts on her EVEF install cell")
	var raider1 = scene.get_node_or_null("World/Actors/ActorRuntime_actor028_1")
	_assert_true(raider1 != null and raider1.position.is_equal_approx(Vector2(480 + 16, 1216 + 16)), "the first raider waits at the south edge")
	_fast(coordinator)
	var message_ids: Array[String] = []
	var speakers: Dictionary = {}
	var frames := 0
	var camera_min: Vector2 = scene.camera.position
	var camera_max: Vector2 = scene.camera.position
	while coordinator.active and not coordinator.story_finished and frames < 6000:
		var current: Dictionary = coordinator.summary()
		if str(current.get("current_event_kind", "")) == "dialogue_message_id":
			var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
			if not message_ids.has(message_id):
				message_ids.append(message_id)
				speakers[message_id] = str(scene.opening_overlay.speaker_label.text)
			_click(coordinator)
		await process_frame
		camera_min = Vector2(minf(camera_min.x, scene.camera.position.x), minf(camera_min.y, scene.camera.position.y))
		camera_max = Vector2(maxf(camera_max.x, scene.camera.position.x), maxf(camera_max.y, scene.camera.position.y))
		frames += 1
	_assert_true(coordinator.story_finished, "the preview should reach first_control_marker within the frame budget")
	# The raiders stage at EVEF y >= 1184 below the 1280x1120 map; focusing them
	# must keep the 640x480 view inside the map instead of showing the void.
	_assert_true(camera_min.x >= 320.0 - 0.5 and camera_min.y >= 240.0 - 0.5, "the story camera centre never leaves the map through the top/left edge (min %s)" % [camera_min])
	_assert_true(camera_max.x <= 1280.0 - 320.0 + 0.5 and camera_max.y <= 1120.0 - 240.0 + 0.5, "the story camera centre never leaves the map through the bottom/right edge (max %s)" % [camera_max])
	_assert_eq(message_ids.size(), 29, "STORY001 pages 30 dialogue tokens over 29 distinct messages (380 twice)")
	_assert_eq(message_ids.slice(0, 5), ["705", "706", "707", "708", "709"], "the opening lines page in script order")
	_assert_eq(str(speakers.get("705", "")), "琥：", "SID_琥 speaks 705 as 琥 (speaker resource 2)")
	_assert_eq(str(speakers.get("708", "")), "雷歐納德：", "SID_雷歐納德 speaks 708 as 雷歐納德")
	_assert_eq(str(speakers.get("725", "")), "盜賊：", "SID_ENEMY028 speaks 725 under its job show name")
	var final_summary: Dictionary = coordinator.summary()
	_assert_eq((final_summary.get("skipped_records", []) as Array).size(), 0, "no STORY001 opening token may be silently skipped")
	if leonard != null:
		_assert_true(leonard.position.is_equal_approx(Vector2(544 - 32 + 16, 448 + 32 + 128 + 16)), "雷歐納德 walks (0,32) then (-32,128) to (512,608)")
	if raider1 != null:
		_assert_true(raider1.position.is_equal_approx(Vector2(480 + 16, 1216 - 192 + 16)), "raider 1 marches 192px north from the south edge")
	var winged = scene.get_node_or_null("World/Actors/ActorRuntime_actor036_1")
	_assert_true(winged != null and winged.position.is_equal_approx(Vector2(160 + 16, 1216 - 128 + 16)), "the first winged raider flies 128px north")
	var status: Dictionary = final_summary.get("status_tokens", {})
	_assert_eq(status.get("win", []), ["0", "1"], "WINFAIL001 win statuses 0 and 1 are enabled")
	_assert_eq(status.get("fail", []), ["0", "1"], "WINFAIL001 fail statuses 0 and 1 are enabled")
	_assert_eq(str((status.get("dead_message", {}) as Dictionary).get("message_id", "")), "742", "the last registered dead message is 琥's 742")
	var card = scene.get_node_or_null("UI/ChapterEndCard")
	_assert_true(card != null, "without the remade battle the preview ends on the not-remade card")
	if card != null:
		var texts: Array[String] = []
		for child in card.get_children():
			if child is Label:
				texts.append((child as Label).text)
		_assert_true(texts.has("歐姆村"), "the card carries the scene title")
		_assert_true(texts.size() == 4 and texts[1] == "戰鬥部分（level 1）尚未重製", "the card states the battle is not remade")
		_assert_true(texts.size() == 4 and texts[2] == "▶ 略過戰鬥（視為勝利）→ 回到大地圖", "WINFAIL001 sets no next level: the victory row returns to the big map")
		_assert_true(texts.size() == 4 and texts[3] == "回到大地圖（不施加戰果）", "the plain return stays available")
	_assert_true(not CampaignProgress.has_pending(), "no campaign hand-off is pending at the preview end")
	# The plain return continues the campaign on the big map at 歐姆村 (the skipped
	# level-1 battle outcome is not applied) instead of restarting.
	coordinator.select_end_card_option(1)
	_click(coordinator)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the not-remade card hands off to the big map")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the hand-off targets campaign.json's world_map scene")
	_assert_eq(str(CampaignProgress.load_progress().get("scenario_path", "")), "res://content/world/world_map_scene.json", "the persisted campaign position moves to the big map")
	var exits: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "world_map_exit")
	_assert_eq(exits.size(), 1, "the coordinator records the world-map exit")
	scene.queue_free()
	await process_frame
	await process_frame


## A world state as the product seeds it (every town's initial tree, new-game point
## flags) after visiting world_point — town writes need the towns table.
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
	var face_records := 0
	for record in (hall63["coordinator"] as Node).summary().get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == "shape_message" and bool((record as Dictionary).get("face_imported", false)):
			face_records += 1
	_assert_eq(face_records, 5, "all five actShapeMessage tokens resolved with an imported face")
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


func _run_level_901_preview() -> void:
	## 菲納斯河畔伏擊 (level 901, armed at point 8 by winfail010's victory): the ambush
	## opening on level 8's map (map alias, obj-901.obs 地圖管理員), three lines, then the
	## not-remade card whose victory row returns to the big map with WINFAIL901's win
	## writes — point 8 → event 516 / ratio 20 and the 席達鎮 tavern rewrite (children
	## 26 / 27 under 酒館, 護甲店二 45, exec event 25) that later opens 薛維斯港.
	var played := await _play_story_scene("res://content/battles/story_901.json", 8, 6000, false)
	var coordinator = played["coordinator"]
	if coordinator == null:
		return
	var scene = played["scene"]
	var world_map: Dictionary = played["world_map"]
	_assert_eq(int(played["initial_cast"]), 22, "EVEF cast: the five-member party, fourteen 023 and three 024")
	_assert_eq(played["messages"], ["1139", "1140", "1141"] as Array[String], "STORY901 pages its three lines in script order")
	_assert_eq(str(played["speakers"].get("1140", "")), "重裝兵：", "SID_ENEMY024 speaks 1140 under its remake label 重裝兵")
	_assert_eq(str(played["speakers"].get("1141", "")), "雷歐納德：", "雷歐納德 answers with 1141")
	_assert_true(coordinator.story_finished and not CampaignProgress.has_pending(), "the preview ends on its card")
	var options: Array = coordinator.summary().get("end_card_options", [])
	_assert_eq(options.size(), 2, "the card offers the victory row and the plain return")
	if options.size() == 2:
		_assert_eq(str((options[0] as Dictionary).get("label", "")), "略過戰鬥（視為勝利）→ 回到大地圖", "WINFAIL901's win returns to the big map (8,gameBigMapLevel)")
	coordinator.confirm_end_card_option()
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "confirming the victory row hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/world/world_map_scene.json", "the victory returns to the big map")
	var won: Dictionary = CampaignProgress.pending.get("world", {})
	_assert_eq(int(won.get("current_point", 0)), 8, "the party stands at 菲納斯河畔 (point 8)")
	_assert_eq(WorldMapRules.point_event(won, world_map, 8), 516, "actBMSetPointEvent 8,516,bmpmVisit: point 8 now opens encounter 516")
	_assert_eq(int(((won.get("encounter_ratios", {}) as Dictionary).get("8", -1))), 20, "actBMSetPointEncounterRatio 8,20 is applied")
	var town: Dictionary = (won.get("towns", {}) as Dictionary).get("6", {})
	_assert_eq(int(town.get("exec_event", 0)), 25, "actSetTownExecEvent town_席達鎮,25 arms the tavern keeper's line")
	var tree: Dictionary = town.get("tree", {})
	_assert_eq(tree.get("20", []), [26, 27], "actDeleteTE 20,0 + actAddTE 20,2,26,27 rewrite the tavern's children")
	_assert_true((tree.get("0", []) as Array).has(45) and not (tree.get("0", []) as Array).has(17), "actDeleteTE 17 / actAddTE 45 swap the armour shop for 護甲店二")
	scene.queue_free()
	await process_frame
	await process_frame


## Boots 曼多力亞 對峙 (level 900, point 9 event 900 after the tavern chain) and pages to
## the actSelectInsertEvent prompt; returns {scene, coordinator, world_map, messages}.
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


## Runs a scene on after a choice until it hands off or ends on its card; returns the
## message ids paged after the choice.
func _run_level_59_ending_film() -> void:
	## story_059 (劫數・地劫神 preview): its skip row carries WINFAIL059's win section —
	## actPlayMovie 140 (movie.pak end.ani, provisional code reading) then 90,998. Confirming
	## 略過戰鬥（視為勝利） plays the ending film over the scene, holds the card, and its end
	## (here a skip) enters the GameClear sequence instead of a world hand-off.
	var played := await _play_story_scene("res://content/battles/story_059.json", 1, 8000, false)
	var coordinator = played["coordinator"]
	var scene = played["scene"]
	if coordinator == null:
		return
	var skip: Dictionary = coordinator.config.get("skip_battle", {})
	_assert_eq(str(skip.get("movie", "")), "end", "story_059's skip row names the ending film")
	_assert_eq(str(skip.get("movie_source", "")), "actPlayMovie 140", "the film comes from the win section's actPlayMovie")
	_assert_true(coordinator.story_finished, "the level-59 preview reaches its card")
	var options: Array = coordinator.summary().get("end_card_options", [])
	_assert_true(options.size() >= 1 and str(options[0].get("id", "")) == "skip_battle" and str(options[0].get("kind", "")) == "game_clear", "the skip row leads to the GameClear sequence")
	coordinator.select_end_card_option(0)
	coordinator.confirm_end_card_option()
	await process_frame
	var movie = scene.get_node_or_null("StoryMovie")
	_assert_true(movie != null and bool(movie.summary().get("playing", false)) and str(movie.summary().get("movie", "")) == "end", "confirming the skip row plays end.ani over the scene")
	var early: Array = coordinator.summary().get("story_records", [])
	_assert_true(not CampaignProgress.has_pending() and not early.any(func(record): return str(record.get("kind", "")) == "game_clear"), "the hand-off waits for the film")
	var skipped: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "battle_skipped")
	_assert_true(skipped.size() == 1 and str(skipped[0].get("movie", "")) == "end", "the battle_skipped record names the film")
	if movie != null:
		_click(coordinator)
	await process_frame
	await process_frame
	var records: Array = coordinator.summary().get("story_records", [])
	var film_records: Array = records.filter(func(record): return str(record.get("kind", "")) == "movie_play")
	_assert_true(film_records.size() == 1 and str(film_records[0].get("status", "")) == "skipped", "a click skips the film and records it")
	_assert_true(records.any(func(record): return str(record.get("kind", "")) == "game_clear"), "the skipped finale enters the GameClear sequence")
	var ending = current_scene
	_assert_true(ending != null and ending != scene and ending.has_method("summary") and str(ending.summary().get("schema", "")) == "hsl_game_clear_screen.v1", "the GameClear scene takes over the tree")
	if ending != null and ending != scene:
		ending.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame


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
	var storage: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "storage_window_enter")
	_assert_eq(storage.map(func(record): return str(record.get("status", ""))), ["skipped_unknown_source_scenario"], "actEnterStorageWindow with the sweep's source-less carry closes the 整理裝備 screen again and records why")
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
		var chosen: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "end_route_chosen")
		_assert_true(chosen.size() == 1 and (chosen[0].get("next_level_event", []) as Array) == [77, 77], "the route is recorded as static-derived with the pair (77, 77)")
		_assert_eq(int((chosen[0].get("decision", {}) as Dictionary).get("over_flag", -1)) if chosen.size() == 1 else -1, 1, "the record keeps the decision inputs")
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
		_assert_true(bool((options[0] as Dictionary).get("compiled", false)) and bool((options[1] as Dictionary).get("compiled", false)), "both branches are precompiled in select_event_timelines")
	_assert_eq(str(scene.opening_overlay.body_label.text), "雷歐納德：請選擇", "the dialogue board asks 雷歐納德 to choose")
	_assert_true(scene.get_node_or_null("UI/StorySelectPrompt/Choice1") != null, "two choice buttons are shown")
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
	var spliced: Dictionary = {}
	var shape_changes := 0
	for record in records:
		if str((record as Dictionary).get("kind", "")) == "event_select_choice":
			spliced = record
		if str((record as Dictionary).get("kind", "")) == "actor_shape_change":
			shape_changes += 1
	_assert_eq([int(spliced.get("choice", -1)), int(spliced.get("inserted_events", 0))], [0, 28], "the choice spliced event 0's 28 compiled events")
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

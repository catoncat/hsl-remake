extends SceneTree

## Headless coverage for the big-map scene: BattleSceneRuntime hosting
## WorldMapRuntime over content/world/world_map_scene.json — data load, visible
## points/tracks, the party marker at 歐姆村, one-track travel and arrival
## resolution (plain stop, town card, registered level hand-off with the world
## state, unregistered level card), persistence of the map position, and the
## world state passing through a campaign hand-off. Travel pacing is forced fast;
## nothing here proves original big-map behaviour.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const Rules = preload("res://game/world/WorldMapRules.gd")
const ScriptActions = preload("res://game/world/WorldScriptActions.gd")
const TownRules = preload("res://game/sim/TownEventRules.gd")

const SCENE_PATH := "res://content/world/world_map_scene.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _boot(handoff: Dictionary = {}) -> Node:
	CampaignProgress.pending = handoff.duplicate(true)
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _travel(scene: Node, point_id: int) -> Dictionary:
	var map = scene.world_map_runtime
	map.travel_pixels_per_second = 100000.0
	var record: Dictionary = map.select_point(point_id, "test")
	var frames := 0
	while map.traveling and frames < 120:
		await process_frame
		frames += 1
	await process_frame
	await _settle(map)
	return record


## Waits for the track reveal animations (and their point fades) to finish.

## Original frames 01／03／04 (original_world_town, runtime-measured): STATUS_BAR.SHP is
## subtracted from the map rather than covering it, the texts are FONT.24 rows in colour codes
## @5 yellow (caption from x 6, digits from x 114) and @1 white (time right-aligned to x 634)
## with their shadows, glyph rows y 427–444, and BigMap.SHP's own
## 1 px black grid lines (x 200, 400, …) show on screen — nothing dims or scales the map.
func _check_status_bar_and_grid(scene: Node) -> void:
	var bar: Control = scene.get_node_or_null("UI/WorldMapStatusBar")
	if bar == null:
		return
	var shade: TextureRect = bar.get_node_or_null("StatusBarShade")
	_assert_true(shade != null and shade.material is CanvasItemMaterial and (shade.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_SUB, "STATUS_BAR.SHP is drawn subtractively over the map")
	_assert_true(shade != null and shade.self_modulate == Color.WHITE and shade.modulate == Color.WHITE, "the whole shape is subtracted (frame 04 fits dst − 1.04 × src)")
	var rows := {}
	for child in bar.get_children():
		if child is Label:
			var label := child as Label
			var global_rect := Rect2(bar.position + label.position, label.size)
			rows[label.text] = {"left": global_rect.position.x, "right": global_rect.end.x, "center_y": global_rect.get_center().y, "align": label.horizontal_alignment, "outline": label.get_theme_constant("outline_size"), "color": label.get_theme_color("font_color"), "shadow": label.get_theme_color("font_shadow_color")}
	_assert_true(rows.has("完成度："), "the caption row reads 完成度：")
	if rows.has("完成度："):
		var caption: Dictionary = rows["完成度："]
		_assert_true(is_equal_approx(caption["left"], 6.0) and absf(caption["center_y"] - 435.5) <= 0.5 and caption["outline"] == 0 and caption["color"] == Color8(255, 255, 123) and caption["shadow"] == Color8(131, 133, 0), "the caption is an @5 yellow row with its shadow from x 6 on the y 427–444 glyph row, got %s" % caption)
	var percent: Dictionary = rows.get("2%", {})
	_assert_true(not percent.is_empty() and is_equal_approx(percent["left"], 114.0) and absf(percent["center_y"] - 435.5) <= 0.5, "the percent starts at the 24 px cell after the caption and a space (x 114), got %s" % percent)
	var time_row: Dictionary = {}
	for text in rows:
		if str(text).count(":") == 2:
			time_row = rows[text]
	_assert_true(not time_row.is_empty() and is_equal_approx(time_row["right"], 634.0) and time_row["align"] == HORIZONTAL_ALIGNMENT_RIGHT and time_row["color"] == Color8(255, 255, 255) and time_row["shadow"] == Color8(132, 134, 132), "the play time is an @1 white row right-aligned to x 634, got %s" % time_row)
	var backdrop: Sprite2D = scene.map_backdrop
	var image: Image = backdrop.texture.get_image()
	_assert_true(image.get_pixel(200, 100).is_equal_approx(Color.BLACK) and image.get_pixel(400, 700).is_equal_approx(Color.BLACK) and image.get_pixel(100, 199).is_equal_approx(Color.BLACK), "BigMap.SHP keeps its black grid columns and rows")
	_assert_true(backdrop.scale == Vector2.ONE and backdrop.modulate == Color.WHITE and backdrop.self_modulate == Color.WHITE and backdrop.visible, "the map is drawn 1:1 and undimmed, so its 1 px grid lines stay visible")

func _settle(map: Node) -> void:
	map.track_reveal_tick_seconds = 0.0001
	var frames := 0
	while bool(map.summary().get("reveal_busy", false)) and frames < 2400:
		await process_frame
		frames += 1
	await process_frame
	await process_frame


func _new_game() -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_PATH))
	return config.get("new_game", {})


func _run() -> void:
	await _run_rules()
	await _run_fresh_map()
	await _run_arrivals()
	await _run_encounters()
	await _run_amphibian_unlock()
	await _run_over_score_writes()
	await _run_carried_state()
	await _run_marker_job_up_form()
	_run_script_actions()
	# Let the audio server release the freed players' playbacks before quitting
	# (the same settle the story-scene suite uses).
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("WORLD_MAP_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: ", failure)
		quit(1)


func _run_rules() -> void:
	## Pure queries over the tracked data: 45 points, 44 tracks, 18 hidden tracks,
	## 歐姆村's single route to 戈爾山道, oriented polylines and sprite placement.
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	_assert_true(bool(world_map.get("ok", false)), "world_map.json loads with schema hsl_world_map.v1")
	var state: Dictionary = Rules.initial_state(world_map, 1, {}, _new_game())
	_assert_true(Rules.state_valid(state), "the initial state is a valid hsl_world_state.v1")
	_assert_eq((state.get("point_flags", {}) as Dictionary).size(), 45, "every bigmap.dat point gets a flag entry")
	var hidden := 0
	for track_id in range(1, 45):
		if Rules.track_hidden(state, world_map, track_id):
			hidden += 1
	_assert_eq(hidden, 18, "18 tracks start hidden (bmpmHidden in the track record)")
	var hidden_points := 0
	for point_id in range(1, 46):
		if Rules.point_hidden(state, world_map, point_id):
			hidden_points += 1
	_assert_eq(hidden_points, 17, "a new game hides 17 points by code (0x42c86e, scene new_game.hidden_points)")
	_assert_true(Rules.point_hidden(state, world_map, 11) and not Rules.point_hidden(state, world_map, 2), "薛維斯港 starts hidden, 戈爾山道 does not")
	_assert_eq([Rules.point_mode(state, world_map, 1), Rules.point_mode(state, world_map, 2), Rules.track_mode(state, world_map, 1)], [2, 0, 0], "only 歐姆村 starts shown (file mode 2); other points and every track start at phase 0")
	_assert_true(not Rules.point_shown(state, world_map, 2) and Rules.point_shown(state, world_map, 1), "phase 0 points are not drawn")
	_assert_eq(Rules.reachable_points(state, world_map, 1), [] as Array[int], "no route is travelable before its reveal")
	var revealing := Rules.reveal_tracks_at(state, world_map, 1)
	_assert_eq(revealing["track_ids"], [1] as Array[int], "standing at 歐姆村 starts revealing track 1")
	_assert_eq(Rules.track_mode(revealing["state"], world_map, 1), Rules.MODE_REVEALING, "the track enters phase 1")
	_assert_eq(Rules.reachable_points(revealing["state"], world_map, 1), [2] as Array[int], "a revealing track is already travelable")
	var revealed := Rules.finish_track_reveal(revealing["state"], world_map, 1)
	_assert_eq([revealed["revealed_points"], Rules.track_mode(revealed["state"], world_map, 1), Rules.point_mode(revealed["state"], world_map, 2)], [[2] as Array[int], 2, 2], "finishing the reveal shows the far endpoint (phase 2)")
	_assert_eq([Rules.completion_percent(state, world_map), Rules.completion_percent(revealed["state"], world_map)], [2, 4], "completion = shown points / (45 named − 1): 1/44 → 2%, 2/44 → 4%")
	state = revealed["state"]
	_assert_eq(Rules.point_label(world_map, 1), "歐姆村", "point 1 is 歐姆村 (RESOURCE.TXT 315)")
	_assert_eq(Rules.point_label(world_map, 45), "克萊恩城", "point 45 is 克萊恩城 (RESOURCE.TXT 359)")
	_assert_eq(Rules.reachable_points(state, world_map, 1), [2] as Array[int], "歐姆村 connects only to 戈爾山道 over track 1")
	_assert_eq(Rules.reachable_points(Rules.reveal_tracks_at(state, world_map, 2)["state"], world_map, 2), [1, 3, 4] as Array[int], "戈爾山道 connects to points 1, 3 and 4 once its routes are revealed")
	_assert_eq(Rules.track_between(state, world_map, 1, 3), 0, "no track joins 歐姆村 directly to 盜賊洞窟")
	var polyline: Array[Vector2] = Rules.travel_polyline(world_map, 1, 2)
	_assert_true(polyline.size() == 4 and polyline[0] == Vector2(862, 474) and polyline[3] == Vector2(910, 527), "travelling 2→1 reverses track 1's polyline")
	_assert_eq([Rules.marker_kind(state, world_map, 1), Rules.MARKER_KIND_TOWN], [3, 3], "歐姆村 draws frame 2 = M_PNT003 (POINT.H Town)")
	_assert_eq([Rules.marker_kind(state, world_map, 5), Rules.marker_kind(state, world_map, 2)], [Rules.MARKER_KIND_BATTLE, Rules.MARKER_KIND_GENERAL], "呼嘯平原 (bmpmBattle) draws frame 0, 戈爾山道 (bmpmGeneral) frame 1")
	_assert_eq(Rules.track_sprite_top_left(world_map, 3), Vector2(862 - 73, 474 - 1), "track sprite top-left is the from point minus the SHP draw origin")
	_assert_eq(str(Rules.arrival(state, world_map, 1).get("kind", "")), "town", "arriving at 歐姆村 opens its town")
	# Arrival table: the original handler's branches (SR-069, 0x427ab3), dice fixed.
	_assert_eq(Rules.point_event(state, world_map, 2), 2, "the file gives point 2 event 2 (its own id)")
	var general := Rules.arrival(state, world_map, 2)
	_assert_eq([str(general.get("kind", "")), int(general.get("level", 0)), bool(general.get("visited", true))], ["level", 2, false], "an unvisited General point opens its event level")
	_assert_eq([str(Rules.arrival(state, world_map, 5).get("kind", "")), int(Rules.arrival(state, world_map, 5).get("level", 0))], ["level", 5], "an unvisited Battle point opens level 5")
	_assert_eq(str(Rules.arrival(state, world_map, 20).get("reason", "")), "town_without_data", "王都希里烏斯 (bmpmTown, no TOWNDEF data) is a stop")
	_assert_eq(str(Rules.arrival(state, world_map, 1, false).get("reason", "")), "passing_town", "a town that is not the chosen destination is passed by")
	var cleared: Dictionary = Rules.visit(state, world_map, 2)
	_assert_true(Rules.point_visited(cleared, world_map, 2) and (cleared["visited_points"] as Array).has(2), "visit() sets the bmpmVisit bit and the history")
	cleared["point_events"]["2"] = {"event": 501, "flag": "bmpmVisit"}
	cleared["encounter_ratios"]["2"] = 20
	_assert_eq(Rules.point_type(cleared, world_map, 2), "bmpmGeneral", "WINFAIL002's post-clear write keeps 戈爾山道 a General point")
	var encounter := Rules.arrival(cleared, world_map, 2, true, 10, 1)
	_assert_eq([str(encounter.get("kind", "")), int(encounter.get("level", 0)), int(encounter.get("ratio", 0)), int(encounter.get("offset", -1))], ["level", 502, 20, 1], "a visited General point: sample 10 ≤ ratio 20, then event 501 + offset 1")
	_assert_eq([str(Rules.arrival(cleared, world_map, 2, true, 21, 0).get("reason", "")), str(Rules.arrival(cleared, world_map, 2, true, 100, 0).get("reason", ""))], ["no_encounter", "no_encounter"], "samples above the ratio are plain stops")
	cleared["encounter_ratios"]["2"] = 0
	_assert_eq(str(Rules.arrival(cleared, world_map, 2, true, 1, 0).get("kind", "")), "stop", "ratio 0 never rolls an encounter")
	cleared["point_events"]["2"] = {"event": 0, "flag": "bmpmVisit"}
	_assert_eq(str(Rules.arrival(cleared, world_map, 2).get("reason", "")), "no_event", "event 0 does nothing")
	var battle: Dictionary = Rules.visit(state, world_map, 5)
	_assert_eq(int(Rules.arrival(battle, world_map, 5, true, -1, 2).get("level", 0)), 7, "a visited Battle point adds 0..2 without a ratio check (5 + 2)")
	var scripted: Dictionary = state.duplicate(true)
	scripted["point_flags"]["9"] = ["bmpmBattle"]
	scripted["point_events"]["9"] = {"event": 9, "flag": "bmpmBattle"}
	_assert_eq([str(Rules.arrival(scripted, world_map, 9).get("kind", "")), int(Rules.arrival(scripted, world_map, 9).get("level", 0)), Rules.marker_kind(scripted, world_map, 9)], ["level", 9, Rules.MARKER_KIND_BATTLE], "STORY008 turns town point 9 into battle 9 (marker follows)")
	scripted["point_flags"]["9"] = ["bmpmTown"]
	scripted["point_events"]["9"] = {"event": 0, "flag": "bmpmTown"}
	_assert_eq(str(Rules.arrival(scripted, world_map, 9).get("kind", "")), "town", "STORY009 turns it back into the town")
	_assert_eq(Rules.BIG_MAP_LEVEL, 49, "TYPE.H gameBigMapLevel")
	var hidden_state: Dictionary = state.duplicate(true)
	hidden_state["track_flags"]["1"] = ["bmpmHidden"]
	_assert_eq(Rules.reachable_points(hidden_state, world_map, 1), [] as Array[int], "a hidden track override removes the route")


func _run_fresh_map() -> void:
	CampaignProgress.reset_campaign()
	var scene = await _boot()
	var map = scene.world_map_runtime
	_assert_true(map != null and map.active, "a world_map scenario boots WorldMapRuntime")
	if map == null:
		scene.queue_free()
		return
	_assert_true(scene.play_loop.is_empty(), "the big map has no PlayLoop")
	_assert_true(scene.opening_coordinator == null, "the big map has no opening coordinator")
	var summary: Dictionary = map.summary()
	_assert_eq(int(summary.get("current_point", 0)), 1, "a fresh campaign stands at 歐姆村")
	_assert_eq(int(summary.get("visible_point_count", 0)), 1, "a new game shows only 歐姆村 (file mode 2)")
	_assert_eq([int(summary.get("visible_track_count", 0)), int(summary.get("revealing_track_count", 0))], [1, 1], "track 1 is drawn while its reveal animation runs")
	_assert_eq(int(summary.get("completion_percent", 0)), 2, "the status bar starts at 完成度 2%")
	_assert_true(scene.get_node_or_null("UI/WorldMapStatusBar") != null, "the status bar (STATUS_BAR.SHP at y 412) is on the UI layer")
	_check_status_bar_and_grid(scene)
	await _settle(map)
	summary = map.summary()
	_assert_eq([int(summary.get("visible_point_count", 0)), int(summary.get("visible_track_count", 0)), int(summary.get("completion_percent", 0))], [2, 1, 4], "the reveal shows 戈爾山道 at the far end of track 1 (完成度 4%)")
	_assert_eq(int(summary.get("label_count", 0)), 2, "labels for the current point and its one reachable neighbour")
	var marker = scene.get_node_or_null("World/Actors/ActorRuntime_party_marker")
	_assert_true(marker != null and marker.position.is_equal_approx(Vector2(910, 527)), "the party marker stands on 歐姆村's map pixel")
	_assert_true(scene.camera.position.is_equal_approx(Vector2(910, 527)), "the camera centres on the current point (inside the 1280x960 clamp)")
	var music: AudioStreamPlayer = scene.get_node("BattleMusic")
	_assert_true(music.playing and music.stream != null, "the big-map track 06 plays")
	_assert_eq(scene.get_node_or_null("World/WorldMapLayer/Track001") != null, true, "track 1 (歐姆村–戈爾山道) is drawn")
	_assert_eq(scene.get_node_or_null("World/WorldMapLayer/Track010") == null, true, "hidden track 10 is not drawn")
	var point_node = scene.get_node_or_null("World/WorldMapLayer/Point01")
	_assert_true(point_node != null and point_node.position.is_equal_approx(Vector2(910, 527)), "point 1's marker sits at (910,527)")
	# Unreachable / miss clicks are recorded and do nothing.
	_assert_eq(str(map.select_point(3, "test").get("status", "")), "unreachable", "盜賊洞窟 is not one track away from 歐姆村")
	_assert_eq(str(map.select_point(0, "test").get("status", "")), "miss", "a click on nothing is a miss")
	_assert_eq(int(map.summary().get("current_point", 0)), 1, "failed selections do not move the party")
	# Travel to 戈爾山道 along track 1.
	var record := await _travel(scene, 2)
	_assert_eq(int(record.get("track_id", 0)), 1, "travel 1→2 uses track 1")
	_assert_eq(int(record.get("path_point_count", 0)), 4, "track 1 has four polyline vertices")
	_assert_true(not map.traveling, "travel completes")
	_assert_eq(int(map.summary().get("current_point", 0)), 2, "the party stands at 戈爾山道")
	_assert_true(marker.position.is_equal_approx(Vector2(862, 474)), "the marker rests on point 2")
	_assert_eq(map.summary().get("state", {}).get("visited_points", []), [1, 2], "visited points accumulate")
	_assert_eq((map.summary().get("arrival_records", []) as Array).size(), 1, "one arrival is recorded")
	_assert_eq(str((map.summary().get("arrival_records", [])[0] as Dictionary).get("kind", "")), "level", "戈爾山道 without a scripted point event opens level 2 (its own event value)")
	# Level 2 is now a formal battle: the arrival hands off with the
	# world state; the test scene is not the tree's current scene, so no reload runs.
	_assert_true(CampaignProgress.has_pending(), "a registered level at the arrival point hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/gol_road_battle.json", "戈爾山道 enters the actual two-stage level-2 battle")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 2, "the hand-off world state stands at 戈爾山道")
	_assert_true(not bool(map.summary().get("card_visible", false)), "no card for a registered level")
	var saved: Dictionary = CampaignProgress.load_progress()
	_assert_eq(str(saved.get("scenario_path", "")), "res://content/battles/gol_road_battle.json", "the pending formal-battle hand-off is persisted")
	_assert_eq(int((saved.get("world", {}) as Dictionary).get("current_point", 0)), 2, "the persisted world state records point 2")
	CampaignProgress.pending = {}
	_assert_eq(int(map.summary().get("label_count", 0)), 4, "labels now cover point 2 and its three neighbours")
	# Back to 歐姆村: a town point with data opens the town screen; Escape on its
	# root menu leaves it (the town screen itself is covered by run_town_scene_tests).
	await _travel(scene, 1)
	_assert_eq(int(map.summary().get("current_point", 0)), 1, "the party returns to 歐姆村")
	_assert_true(bool(map.summary().get("town_open", false)), "arriving at the town opens the town screen")
	_assert_true(not bool(map.summary().get("card_visible", false)), "no picture card when the town screen opens")
	_assert_eq(str((map.summary().get("town", {}) as Dictionary).get("town_label", "")), "歐姆村", "the town screen names 歐姆村")
	_assert_eq((map.summary().get("town", {}) as Dictionary).get("menu_codes", []), [1, 2, 3], "a fresh world state seeds 歐姆村's initial menu tree")
	_assert_eq((map.summary().get("state", {}) as Dictionary).get("towns", {}).size(), 12, "a fresh world state carries all 12 towns")
	map.handle_input(_key(KEY_ESCAPE))
	await process_frame
	_assert_true(not bool(map.summary().get("town_open", false)), "Escape leaves the town")
	# Re-selecting the current town point re-opens it without travelling.
	map.select_point(1, "test")
	_assert_true(bool(map.summary().get("town_open", false)), "selecting the current town point re-enters the town")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_script_actions() -> void:
	## A finished battle's recorded town / big-map writes reach the world state at
	## hand-off: without a state yet, a fresh one is seeded from the registered
	## world-map scene (歐姆村 start, 12 towns), then the actions apply in order.
	var campaign := CampaignProgress.load_campaign()
	var loop := {"winfail_runtime": {"pending_world_flags": [
		{"key": "win", "name": "actSetTownExecEvent", "args": ["town_歐姆村", "9"]},
		{"key": "win", "name": "actBMSetPointEvent", "args": ["2", "501", "bmpmVisit"]},
		{"key": "win", "name": "actBMSetPointEncounterRatio", "args": ["2", "20"]},
		{"key": "win", "name": "actBMClearTrackFlag", "args": ["3", "bmpmHidden"]},
		{"key": "win", "name": "actAddTE", "args": ["town_席達鎮", "20", "1", "24"]},
	]}}
	var flow := ScriptActions.apply_pending({}, loop, campaign)
	_assert_true(not flow.has("error"), "recorded world-flow actions apply without error (%s)" % str(flow.get("error", "")))
	_assert_eq(bool(flow.get("seeded", false)), true, "a campaign without a world state gets one seeded")
	_assert_eq(int(flow.get("applied", 0)), 5, "all five actions applied")
	var world: Dictionary = flow["world"]
	_assert_true(Rules.state_valid(world), "the seeded state is a valid hsl_world_state.v1")
	_assert_eq(int(world.get("current_point", 0)), 1, "seeded at the scene start point 歐姆村")
	_assert_eq((world.get("towns", {}) as Dictionary).size(), 12, "seeded with all 12 towns")
	_assert_eq(int(((world["towns"] as Dictionary)["1"] as Dictionary).get("exec_event", 0)), 9, "actSetTownExecEvent arms 歐姆村 event 9 (level 1's victory write)")
	_assert_eq((world["point_events"] as Dictionary).get("2", {}), {"event": 501, "flag": "bmpmVisit"}, "actBMSetPointEvent records the point event")
	_assert_eq(int((world["encounter_ratios"] as Dictionary).get("2", 0)), 20, "actBMSetPointEncounterRatio recorded")
	_assert_true(not ((world["track_flags"] as Dictionary).get("3", []) as Array).has("bmpmHidden"), "actBMClearTrackFlag reveals track 3")
	_assert_eq((((world["towns"] as Dictionary)["6"] as Dictionary)["tree"] as Dictionary).get("20", []), [21, 22, 23, 24], "actAddTE appends child 24 under 席達鎮 node 20")
	# A valid carried state is edited in place (no reseed); no actions pass through.
	var again := ScriptActions.apply_pending(world, {"winfail_runtime": {"pending_world_flags": [{"key": "win", "name": "actSetTownExecEvent", "args": ["town_歐姆村", "0"]}]}}, campaign)
	_assert_eq(bool(again.get("seeded", false)), false, "an existing state is not reseeded")
	_assert_eq(int(((again["world"]["towns"] as Dictionary)["1"] as Dictionary).get("exec_event", -1)), 0, "later writes edit the carried state")
	_assert_eq(int(again["world"].get("encounter_ratios", {}).get("2", 0)), 20, "earlier writes survive")
	var none := ScriptActions.apply_pending(world, {}, campaign)
	_assert_eq(none["world"], world, "a loop without recorded actions passes the world through unchanged")
	var no_map := ScriptActions.apply_pending({}, loop, {"schema": "hsl_campaign.v1", "battles": {}})
	_assert_eq(str(no_map.get("error", "")), "no_world_map_scene", "a campaign without a world map leaves the actions pending")
	_assert_eq((no_map.get("pending", []) as Array).size(), 5, "unapplied actions are returned for the record")
	# Returning to the map: "N,gameBigMapLevel" stands the party at point N, seeding a first state.
	var placed := ScriptActions.place_party({}, 10, campaign)
	_assert_eq([bool(placed.get("seeded", false)), int(placed["world"].get("current_point", 0)), (placed["world"].get("visited_points", []) as Array).has(10)], [true, 10, true], "place_party seeds the state and stands the party at 帕尼西雅城廢墟 (point 10)")
	var moved := ScriptActions.place_party(placed["world"], 3, campaign)
	_assert_eq([bool(moved.get("seeded", false)), int(moved["world"].get("current_point", 0)), moved["world"].get("visited_points", [])], [false, 3, [1, 10, 3]], "a later return keeps the state and moves the party")


func _confirm_key() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	return key


func _run_arrivals() -> void:
	## Script-assigned point events: a registered level hands off with the world
	## state and the carried party; an unregistered level shows a card and stays.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var state: Dictionary = Rules.initial_state(world_map, 1)
	state["point_events"]["2"] = {"event": 52, "flag": "bmpmBattle"}
	var scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {"gold": 275, "units": []}, "from_scenario_id": "story_001_ohm_village_opening", "world": state})
	var map = scene.world_map_runtime
	_assert_eq(int(map.summary().get("current_point", 0)), 1, "the carried world state places the party at its current point")
	await _travel(scene, 2)
	_assert_true(CampaignProgress.has_pending(), "a registered level at the point hands off through the campaign")
	var pending: Dictionary = CampaignProgress.pending
	_assert_eq(str(pending.get("scenario_path", "")), "res://content/battles/battle_052.json", "point event 52 enters the level-52 scenario")
	_assert_eq(int((pending.get("carry", {}) as Dictionary).get("gold", 0)), 275, "the carried party passes through the map unchanged")
	_assert_eq(int((pending.get("world", {}) as Dictionary).get("current_point", 0)), 2, "the hand-off carries the world state at the arrival point")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()
	state["point_events"]["2"] = {"event": 14, "flag": "bmpmBattle"}
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": state})
	map = scene.world_map_runtime
	await _travel(scene, 2)
	_assert_true(not CampaignProgress.has_pending(), "an unregistered level (14, no STORY014) does not hand off")
	_assert_eq(str(map.summary().get("card_kind", "")), "level_not_remade", "an unregistered level shows the not-remade card")
	_assert_eq(int(map.summary().get("current_point", 0)), 2, "the party stays at the point")
	map.handle_input(_confirm_key())
	await process_frame
	_assert_true(not bool(map.summary().get("card_visible", false)), "confirm closes the card and the party stays on the map")
	_assert_eq(str(CampaignProgress.load_progress().get("scenario_path", "")), SCENE_PATH, "the campaign position stays on the map")
	scene.queue_free()
	await process_frame
	await process_frame
	# winfail010's victory arms point 8 with event 901 (bmpmGeneral): arriving at
	# 菲納斯河畔 afterwards enters the registered level-901 ambush preview.
	CampaignProgress.reset_campaign()
	var ambush: Dictionary = Rules.initial_state(world_map, 7)
	ambush["point_events"]["8"] = {"event": 901, "flag": "bmpmGeneral"}
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {"gold": 275, "units": []}, "from_scenario_id": "", "world": ambush})
	map = scene.world_map_runtime
	await _travel(scene, 8)
	_assert_true(CampaignProgress.has_pending(), "point 8 armed with event 901 hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_901.json", "event 901 enters the 菲納斯河畔 formal ambush battle")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 8, "the hand-off stands at 菲納斯河畔 (point 8)")
	scene.queue_free()
	await process_frame
	await process_frame
	# A (town_*, gameBigMapLevel) event stands the party at that point without a scene change.
	CampaignProgress.reset_campaign()
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": Rules.initial_state(world_map, 1)})
	map = scene.world_map_runtime
	map._enter_level_event(4, Rules.BIG_MAP_LEVEL)
	await process_frame
	_assert_true(not CampaignProgress.has_pending(), "returning to the map from the map is not a hand-off")
	_assert_eq(int(map.summary().get("current_point", 0)), 4, "the party now stands at 米蘭多 (point 4)")
	_assert_eq(int((CampaignProgress.load_progress().get("world", {}) as Dictionary).get("current_point", 0)), 4, "the move persists")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_encounters() -> void:
	## Random encounters (registered 501-506): the visited point's roll enters the
	## encounter scenario with the carried party, whose conditional slots (有才產生)
	## field only the carried members; a party carrying a member the encounter cannot
	## field yet stays on the map with an explicit card.
	var Conditional = load("res://game/sim/ConditionalPartyRules.gd")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_504.json"))
	var carry := {"schema": "hsl_campaign_carry.v1", "gold": 300, "loop": {"gold": 300}, "units": {"leonard": {"actor_id": "001", "hp": 40}, "tina": {"actor_id": "002", "hp": 30}, "hu": {"actor_id": "003", "hp": 45}}}
	var applied: Dictionary = Conditional.apply(scenario, carry)
	_assert_eq(applied["receipt"]["installed"], ["leonard", "tina", "hu"], "carried members take their conditional slots")
	_assert_eq(applied["receipt"]["skipped"], ["hanks", "shera", "rett", "howl", "gulu", "claudie"], "uncarried slots are not fielded")
	var roles: Array = (applied["scenario"]["playable_units"] as Array).map(func(unit): return str(unit["id"]))
	_assert_eq(roles, ["leonard", "tina", "hu", "actor036_1", "actor036_2", "actor036_3"], "the filtered roster keeps the monsters and the carried party only")
	_assert_eq(Conditional.apply(scenario, {})["receipt"]["mode"], "no_carry_all_slots", "a launch without a hand-off fields every slot")
	var blocked: Array = Conditional.blocked_members(scenario, {"units": {"leonard": {"actor_id": "001"}, "gulu": {"actor_id": "008"}}})
	_assert_eq(blocked, [], "a carried Gulu member is fieldable after the source range is compiled")
	# The unfieldable-member path stays reachable for a future unavailable slot (synthetic scenario).
	var synthetic: Dictionary = scenario.duplicate(true)
	synthetic["conditional_party"]["unavailable_slots"] = [{"actor_id": "999", "reason": "synthetic"}]
	var synthetic_blocked: Array = Conditional.blocked_members(synthetic, {"units": {"leonard": {"actor_id": "001"}, "ghost": {"actor_id": "999"}}})
	_assert_eq(synthetic_blocked.map(func(member): return str(member["actor_id"])), ["999"], "a carried member without a fieldable slot is still reported")
	# World map: point 3 cleared (event 504, ratio 40) — the roll's level enters the encounter.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var state: Dictionary = Rules.initial_state(world_map, 3)
	var scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": carry, "from_scenario_id": "", "world": state})
	var map = scene.world_map_runtime
	map._enter_level_event(3, 504)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "encounter 504 hands off through the campaign")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_504.json", "the roll enters the registered encounter scenario")
	_assert_eq(int((CampaignProgress.pending.get("carry", {}) as Dictionary).get("gold", 0)), 300, "the carried party enters the encounter")
	scene.queue_free()
	await process_frame
	await process_frame
	# The encounter scene fields only the carried members (hand-off consumed by BattleSceneRuntime).
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/battle_504.json", "carry": carry, "from_scenario_id": "", "world": state}
	CampaignProgress.last_entry = {}
	var battle = RuntimeScene.instantiate()
	battle.scenario_path = "res://content/battles/battle_504.json"
	battle.startup_mode = "product_opening"
	root.add_child(battle)
	await process_frame
	await process_frame
	var fielded: Array = (battle.play_loop.get("units", []) as Array).filter(func(unit): return str(unit.get("battle_actor_role", "")) == "player_controlled").map(func(unit): return str(unit["id"]))
	_assert_eq(fielded, ["leonard", "tina", "hu"], "the encounter fields the carried members only")
	_assert_eq(RuntimeReadback.interaction_summary(battle).get("conditional_party", {}).get("skipped", []), ["hanks", "shera", "rett", "howl", "gulu", "claudie"], "the runtime summary reports the skipped slots")
	_assert_eq(int(battle.play_loop.get("gold", 0)), 300, "the carry applies to the fielded party")
	battle.queue_free()
	await process_frame
	await process_frame
	# Point 5 is a visited Battle point whose script event is 507. Its mandatory
	# encounter roll selects the event plus 0..2, so every result must hand off to
	# one of the registered battle_507..509 scenes.
	CampaignProgress.reset_campaign()
	var point_five: Dictionary = Rules.visit(Rules.initial_state(world_map, 5), world_map, 5)
	point_five["point_events"]["5"] = {"event": 507, "flag": "bmpmBattle"}
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": point_five})
	map = scene.world_map_runtime
	var encounter_507_to_509: Dictionary = map.select_point(5, "test_reenter")
	await process_frame
	_assert_true(int(encounter_507_to_509.get("level", 0)) >= 507 and int(encounter_507_to_509.get("level", 0)) <= 509, "point 5 always resolves its visited Battle event to encounter 507..509")
	_assert_true(CampaignProgress.has_pending(), "point 5 encounter hands off through the campaign")
	var encounter_path := str(CampaignProgress.pending.get("scenario_path", ""))
	_assert_true(encounter_path in ["res://content/battles/battle_507.json", "res://content/battles/battle_508.json", "res://content/battles/battle_509.json"], "point 5 hand-off targets a registered battle_507..509 scene")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 5, "point 5 encounter hand-off preserves the map position")
	scene.queue_free()
	await process_frame
	await process_frame

	# A party carrying 咕嚕 (008, whose source range3CellCircle weapon is now compiled) enters the encounter.
	CampaignProgress.reset_campaign()
	var carry_gulu := {"schema": "hsl_campaign_carry.v1", "gold": 300, "units": {"leonard": {"actor_id": "001"}, "gulu": {"actor_id": "008"}}}
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": carry_gulu, "from_scenario_id": "", "world": Rules.initial_state(world_map, 3)})
	map = scene.world_map_runtime
	map._enter_level_event(3, 505)
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "an encounter fields a carried 咕嚕 and hands off")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_505.json", "the 咕嚕 party enters battle_505")
	_assert_true((CampaignProgress.pending.get("carry", {}) as Dictionary).get("units", {}).has("gulu"), "the hand-off carry keeps 咕嚕")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_over_score_writes() -> void:
	## The ending's inputs live in the shared world state: a battle's winfail
	## actAddOverScore / actSetOverFlag (pending_world_flags) and a story scene's
	## game_over_score_add / game_over_flag records reach TownEventRules as
	## teAddOverScore / teSetOverFlag — the same store TOWNDEF's teAddOverScore writes —
	## so over_score accumulates by gameoverID and over_flag ORs TYPE.H's bits.
	var campaign := CampaignProgress.load_campaign()
	var seeded: Dictionary = ScriptActions.ensure_state({}, campaign)
	var base: Dictionary = seeded["state"]
	_assert_eq(int(base.get("over_flag", 0)), 0, "a fresh world carries no over flag")
	var flow: Dictionary = ScriptActions.apply_actions(base, [
		{"name": "actAddOverScore", "args": ["gameoverID2", "3"]},
		{"name": "actAddOverScore", "args": ["gameoverID2", "-2"]},
		{"name": "actAddOverScore", "args": ["gameoverID3", "1"]},
		{"name": "actSetOverFlag", "args": ["gameoverflagFreeEnemy"]},
		{"name": "actSetOverFlag", "args": ["gameoverflagEnemyJobUp"]},
		{"name": "actSetOverFlag", "args": ["gameoverflagFreeEnemy"]},
	], campaign)
	_assert_eq(int(flow.get("applied", 0)), 6, "every over write is applied, none recorded only")
	var world: Dictionary = flow["world"]
	_assert_eq(world.get("over_score", {}), {"2": 1, "3": 1}, "scores add by gameoverID (TOWNDEF 37's −2 included)")
	_assert_eq(int(world.get("over_flag", 0)), 3, "flags OR: FreeEnemy 1 | EnemyJobUp 2, repeated bits stay")
	var story_actions: Array = ScriptActions.story_actions([
		{"kind": "game_over_score_add", "args": ["gameoverID1", "2"], "source_event_id": "winfail900_event_1_16"},
		{"kind": "game_over_flag", "args": ["gameoverflagFreeEnemy"], "source_event_id": "winfail073_event_1_2"},
		{"kind": "dialogue_message_id", "args": ["1"], "source_event_id": "x"},
	])
	_assert_eq(story_actions.map(func(action): return str(action.get("name", ""))), ["actAddOverScore", "actSetOverFlag"], "story records of the two kinds become the script actions")
	var second: Dictionary = ScriptActions.apply_actions(world, story_actions, campaign)
	_assert_eq((second["world"] as Dictionary).get("over_score", {}), {"2": 1, "3": 1, "1": 2}, "a story scene's choice adds to the same table")


func _run_amphibian_unlock() -> void:
	## Provisional bridge (world scene config.provisional_unlocks, P-051): after WINFAIL012's
	## writes (point 13 Town-typed with event 0, tracks 12/13 shown, 兩棲族部落 141 armed with
	## 142–145 and 145's 146–149), standing at 龍之息 (point 13) is a plain stop, and the
	## village's 集會場 then lists the second-stage talks 150 / 151 instead of 148 / 149 —
	## 151 being the only route into level 13. Applied once; recorded as provisional.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var campaign := CampaignProgress.load_campaign()
	var seeded: Dictionary = ScriptActions.ensure_state({}, campaign)
	var base: Dictionary = Rules.visit(Rules.visit(seeded["state"], world_map, 11), world_map, 12)
	var writes: Array = [
		{"name": "actBMSetPointEvent", "args": ["12", "537", "bmpmVisit"]}, {"name": "actBMSetPointEncounterRatio", "args": ["12", "10"]},
		{"name": "actBMSetPointEvent", "args": ["13", "0", "bmpmVisit"]}, {"name": "actBMSetPointFlag", "args": ["13", "bmpmTown"]}, {"name": "actBMSetPointEncounterRatio", "args": ["13", "0"]},
		{"name": "actBMClearPointFlag", "args": ["13", "bmpmHidden"]}, {"name": "actBMClearPointFlag", "args": ["14", "bmpmHidden"]}, {"name": "actBMClearPointFlag", "args": ["15", "bmpmHidden"]},
		{"name": "actBMClearTrackFlag", "args": ["12", "bmpmHidden"]}, {"name": "actBMClearTrackFlag", "args": ["13", "bmpmHidden"]}, {"name": "actBMClearTrackFlag", "args": ["14", "bmpmHidden"]},
		{"name": "actSetTownExecEvent", "args": ["town_兩棲族部落", "141"]},
		{"name": "actAddTE", "args": ["town_兩棲族部落", "142", "0"]}, {"name": "actAddTE", "args": ["town_兩棲族部落", "143", "0"]}, {"name": "actAddTE", "args": ["town_兩棲族部落", "144", "0"]},
		{"name": "actAddTE", "args": ["town_兩棲族部落", "145", "4", "146", "147", "148", "149"]},
	]
	var flow: Dictionary = ScriptActions.apply_actions(base, writes, campaign)
	_assert_true(not flow.has("error"), "WINFAIL012's world writes apply (%s)" % str(flow.get("error", "")))
	var world: Dictionary = flow["world"]
	var scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {"gold": 275, "units": []}, "from_scenario_id": "story_012", "world": world})
	var map = scene.world_map_runtime
	_assert_eq(int(map.summary().get("current_point", 0)), 12, "the party stands at 巴瀚納海峽 (point 12)")
	var before_tree: Dictionary = ((map.state.get("towns", {}) as Dictionary).get("14", {}) as Dictionary).get("tree", {})
	_assert_eq(before_tree.get("145", []), [146, 147, 148, 149], "the village's 集會場 starts with the four first-stage talks")
	await _travel(scene, 13)
	_assert_true(not CampaignProgress.has_pending(), "龍之息 (Town-typed, event 0, no town data) is a stop, not a hand-off")
	_assert_eq(str((map.arrival_records.back() as Dictionary).get("kind", "")), "stop", "arriving at point 13 is a stop (General bit kept beside the added Town bit; event 0)")
	var unlocks: Array = map.summary().get("unlock_records", [])
	_assert_true(unlocks.size() == 1 and str(unlocks[0].get("id", "")) == "amphibian_second_stage" and str(unlocks[0].get("status", "")) == "applied", "standing at 龍之息 applies the provisional 集會場 unlock once")
	var after_tree: Dictionary = ((map.state.get("towns", {}) as Dictionary).get("14", {}) as Dictionary).get("tree", {})
	_assert_eq(after_tree.get("145", []), [146, 147, 150, 151], "集會場 now offers 兩棲族老人二 (150) and 人類學者二 (151) in place of 148 / 149")
	_assert_eq(map.state.get("provisional_unlocks_applied", []), ["amphibian_second_stage"], "the applied unlock is remembered in the world state")
	_assert_eq(int(((CampaignProgress.load_progress().get("world", {}) as Dictionary).get("provisional_unlocks_applied", []) as Array).size()), 1, "the unlock persists with the map position")
	await _travel(scene, 14)
	_assert_true(map.town_runtime != null, "兩棲族部落 opens as a town")
	var towndef: Dictionary = TownRules.load_towndef("res://content/imported/hsl/global/world_map/towndef.json")
	var codes: Array = []
	for entry in TownRules.menu_entries(map.state, towndef, 14, 145):
		codes.append(int((entry as Dictionary).get("code", 0)))
	_assert_eq(codes, [146, 147, 150, 151], "the 集會場 sub-menu lists the second-stage talks")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_marker_job_up_form() -> void:
	## The party marker reuses 雷歐納德's walk frames; after a 命運神殿 job-up the carried
	## record stands him on 010, and the figurine follows (remake presentation).
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var carry := {"schema": "hsl_campaign_carry.v1", "gold": 275, "units": {"tina": {"actor_id": "002", "job_up_target_actor_id": "011"}, "leonard": {"actor_id": "001", "job_up_target_actor_id": "010"}}}
	var scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": carry, "from_scenario_id": "", "world": Rules.initial_state(world_map, 1)})
	var map = scene.world_map_runtime
	_assert_eq(str(map.marker.actor_id), "010", "the marker walks the map in the carried 010 劍豪 frames")
	_assert_true(str(map.marker.runtime_summary().get("current_frame_source", "")).begins_with("res://content/imported/hsl/shared/actor_walk_frames/010/"), "marker frames come from the shared up-title manifest")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {"gold": 275, "units": {"leonard": {"actor_id": "001"}}}, "from_scenario_id": "", "world": Rules.initial_state(world_map, 1)})
	_assert_eq(str(scene.world_map_runtime.marker.actor_id), "001", "without a job-up the marker keeps the 001 frames")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_carried_state() -> void:
	## A hidden-track override in the carried state is honoured by the drawing and
	## the reachability; an invalid carried state falls back to the fresh start.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = Rules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var state: Dictionary = Rules.initial_state(world_map, 2)
	state["track_flags"]["1"] = ["bmpmHidden"]
	var scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": state})
	var map = scene.world_map_runtime
	_assert_eq(int(map.summary().get("current_point", 0)), 2, "the carried state starts the party at 戈爾山道")
	_assert_eq(map.summary().get("reachable_points", []), [3, 4] as Array[int], "the hidden track 1 removes 歐姆村 from the neighbours")
	_assert_eq(scene.get_node_or_null("World/WorldMapLayer/Track001") == null, true, "the hidden track is not drawn")
	await _settle(map)
	_assert_eq([int(map.summary().get("visible_track_count", 0)), int(map.summary().get("visible_point_count", 0))], [2, 4], "only 戈爾山道's two non-hidden routes and their far points are revealed (plus 歐姆村, shown by the file)")
	scene.queue_free()
	await process_frame
	await process_frame
	# A script-requested walk (teSetBMWalkToPoint / actSetBMWalkToPoint) in the carried
	# state is performed when the map opens: 戈爾山道 → 盜賊洞窟 along track 2.
	CampaignProgress.reset_campaign()
	var walking: Dictionary = Rules.initial_state(world_map, 2)
	walking["pending_walk"] = {"from": 2, "to": 3}
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": walking})
	map = scene.world_map_runtime
	map.travel_pixels_per_second = 100000.0
	var frames := 0
	while map.traveling and frames < 240:
		await process_frame
		frames += 1
	await _settle(map)
	_assert_eq([str((map.summary().get("travel_records", [])[0] as Dictionary).get("trigger", "")), int(map.summary().get("current_point", 0))], ["script_walk", 3], "the pending walk travels 2 → 3 on its own and arrives")
	_assert_true(not (map.summary().get("state", {}) as Dictionary).has("pending_walk"), "the walk is consumed")
	_assert_true(CampaignProgress.has_pending() and str(CampaignProgress.pending.get("scenario_path", "")) == "res://content/battles/battle_003.json", "arriving at 盜賊洞窟 (General, unvisited) enters the registered level-3 formal battle")
	CampaignProgress.pending = {}
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()
	scene = await _boot({"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": {}, "from_scenario_id": "", "world": {"schema": "bogus"}})
	map = scene.world_map_runtime
	_assert_eq(int(map.summary().get("current_point", 0)), 1, "an invalid carried world state falls back to the scenario start point")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()

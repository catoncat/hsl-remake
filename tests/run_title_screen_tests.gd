extends SceneTree

## Title screen: the original Title*.SHP shapes at the reference layout, the three-item
## ring menu (keyboard selection, mouse hover lighting an item), 戰場記錄 without a saved
## position, 戰場記錄 resuming a saved campaign position into BattleSceneRuntime, and
## 開始新故事 fading into the intro film and then the product opening with the saved
## position cleared, and the MoviePlayer paging the imported FLI sheets at the manifest rate.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const TitleScene = preload("res://game/title/TitleScreen.tscn")
const GameOverScene = preload("res://game/title/GameOverScreen.tscn")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameClearScene = preload("res://game/title/GameClearScreen.tscn")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const MoviePlayer = preload("res://game/title/MoviePlayer.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")

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
	await _run_layout_and_menu()
	await _run_battle_record_without_save()
	await _run_battle_record_resume()
	await _run_battle_record_checkpoint()
	await _run_new_story()
	await _run_game_over_screen()
	await _run_defeat_leaves_for_game_over()
	await _run_game_clear_screen()
	CampaignProgress.reset_campaign()
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await process_frame
	await process_frame
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("TITLE_SCREEN_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("TITLE_SCREEN_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _boot() -> Node:
	var scene = TitleScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.finish_slide_in() # the 0x45e882 slide-in lands before the layout checks
	return scene


## The original gem and book (original_title_ornaments, static-derived): spawned at the ring
## top-left + (33,112)／(207,107) minus their draw origins (0x423e06／0x423e32), vertical travel
## only, trunc(6·sin) about the spawn y (0x424406 → 0x45e9bc) whatever is selected, each with its
## own start angle rand() % 255 (0x424389). Samples one swing (256/3 ticks).
func _check_ornaments(scene: Node, context: String) -> void:
	var anchors := {"gem_position": Vector2(216, 259), "hand_position": Vector2(386, 247)}
	var low := {"gem_position": INF, "hand_position": INF}
	var high := {"gem_position": -INF, "hand_position": -INF}
	var start: float = scene.ornament_clock
	while scene.ornament_clock - start < scene.ORNAMENT_BOB_PERIOD:
		var summary: Dictionary = scene.summary()
		for key in anchors:
			var at: Vector2 = summary[key]
			_assert_eq(at.x, anchors[key].x, "%s: %s never moves sideways" % [context, key])
			low[key] = minf(low[key], at.y - anchors[key].y)
			high[key] = maxf(high[key], at.y - anchors[key].y)
		await process_frame
	for key in anchors:
		_assert_true(low[key] >= -6.0 and low[key] <= -4.0 and high[key] <= 6.0 and high[key] >= 4.0, "%s: %s bobs at most 6 px about its spawn y (got %.0f…%.0f)" % [context, key, low[key], high[key]])
	var phases: Vector2i = scene.summary()["ornament_phases"]
	_assert_true(phases.x >= 0 and phases.x < 255 and phases.y >= 0 and phases.y < 255, "%s: gem and book keep their own start angles %s" % [context, phases])


func _run_layout_and_menu() -> void:
	CampaignProgress.reset_campaign()
	var scene = await _boot()
	var summary: Dictionary = scene.summary()
	_assert_eq(summary.get("manifest_schema", ""), "hsl_title_assets.v1", "title manifest loaded")
	_assert_eq(summary.get("items", []), ["new_story", "battle_record", "quit"], "the ring menu has the three original items")
	for role in ["background", "logo", "ring", "statue_left", "statue_right", "cursor_gem", "cursor_hand"]:
		var sprite = scene.get_node_or_null("Title_" + role)
		_assert_true(sprite != null and sprite.texture != null, "%s sprite is drawn" % role)
	_assert_eq(scene.get_node("Title_logo").position, Vector2(99, 12), "the logo sits at its reference position")
	_assert_eq(scene.get_node("Title_ring").position, Vector2(197, 161), "the ring sits at its reference position")
	_assert_eq(scene.get_node("Title_statue_left").position, Vector2(117, 227), "left statue reference position")
	_assert_eq(scene.get_node("Title_statue_right").position, Vector2(405, 227), "right statue reference position")
	_assert_eq(summary.get("selected", -1), 0, "開始新故事 is selected first")
	await _check_ornaments(scene, "item 1 selected")
	_assert_eq(summary.get("lit_visible", []), [false, false, false], "no item is lit without hover")
	_assert_true(str(summary.get("music_stream", "")).ends_with("/03.ogg") and bool(summary.get("music_playing", false)), "the original title track 03 plays on the title (original_music.md §3.1)")
	var version: Control = scene.get_node("Overlay/Version")
	_assert_true(summary.get("version_text", "") == "V1.06" and version.visible and version.get_rect().encloses(Rect2(3, 459, 39, 9)), "V1.06 covers the measured bottom-left ink box (3,459)–(41,467): %s" % version.get_rect())
	scene.select(1)
	summary = scene.summary()
	_assert_eq(summary.get("selected_item_id", ""), "battle_record", "down selects 戰場記錄")
	_assert_eq(summary.get("lit_visible", []), [false, true, false], "the keyboard-selected item shows its lit shape")
	await _check_ornaments(scene, "item 2 selected")
	scene.select(-1)
	_assert_eq(scene.summary().get("selected_item_id", ""), "quit", "selection wraps to 離開遊戲")
	await _check_ornaments(scene, "item 3 selected")
	# Mouse hover: the point inside item 2's lit shape (ring top-left + offset [50,113]).
	var hovered: int = scene.hover_at(Vector2(197 + 50 + 70, 161 + 113 + 18))
	_assert_eq(hovered, 1, "hovering the 戰場記錄 row reports item 2")
	summary = scene.summary()
	_assert_eq(summary.get("lit_visible", []), [false, false, false], "hover lights nothing under OPT-GUIDE＝原版 (the original hover only sparkles)")
	_assert_eq(summary.get("selected_item_id", ""), "battle_record", "hover moves the selection")
	_assert_eq(scene.hover_at(Vector2(10, 10)), -1, "hovering outside the ring lights nothing")
	_assert_eq(scene.summary().get("lit_visible", []), [false, false, false], "lit shape hides when the mouse leaves")
	# Keyboard: up from item 2 goes back to item 1; Enter confirms the current item.
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	scene._unhandled_input(up)
	_assert_eq(scene.summary().get("selected_item_id", ""), "new_story", "KEY_UP selects the previous item")
	scene.select(2)
	var transition: Dictionary = scene.confirm()
	_assert_eq(transition.get("action", ""), "quit", "confirming item 3 requests quit")
	_assert_true(bool(scene.summary().get("quit_requested", false)), "headless run records the quit instead of quitting")
	scene.queue_free()
	await process_frame


func _run_battle_record_without_save() -> void:
	CampaignProgress.reset_campaign()
	var scene = await _boot()
	scene.select(1)
	var transition: Dictionary = scene.confirm()
	_assert_eq(transition.get("status", ""), "no_record", "戰場記錄 without a saved position does not leave the title")
	_assert_eq(scene.summary().get("message", ""), "無存檔記錄", "message 12 無存檔記錄 is shown (0x42404c → 0x4072b0)")
	_assert_true(not CampaignProgress.has_pending(), "no hand-off is armed")
	_assert_true(is_instance_valid(scene) and current_scene == scene, "the title stays current")
	scene.queue_free()
	await process_frame


func _run_battle_record_resume() -> void:
	## A saved campaign position at 戈爾山道 (story_002) resumes through the title.
	CampaignProgress.reset_campaign()
	var world_map: Dictionary = WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var world: Dictionary = WorldMapRules.visit(WorldMapRules.initial_state(world_map, 1), world_map, 2)
	var saved := {
		"scenario_path": "res://content/battles/story_002.json",
		"carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "gold": 275},
		"from_scenario_id": "world_map",
		"world": world,
	}
	_assert_true(CampaignProgress.save_progress(saved), "the saved position is written")
	var scene = await _boot()
	scene.select(1)
	var transition: Dictionary = scene.confirm()
	_assert_eq(transition.get("status", ""), "fading", "戰場記錄 with a saved position starts the fade")
	_assert_eq(transition.get("resume_scenario_path", ""), "res://content/battles/story_002.json", "the saved scenario is the resume target")
	_assert_true(CampaignProgress.has_pending(), "the saved position is armed as the pending hand-off")
	_assert_true(scene.confirm().is_empty(), "the menu is locked while fading")
	# The confirmed item stays lit and the screen stays clear through the hold (user
	# recording: lit 13.52 s, black ramp 14.27 → 14.82 s), then fades to black.
	_assert_eq(scene.summary().get("lit_visible", []), [false, true, false], "the confirmed item shows its lit shape")
	await create_timer(scene.CONFIRM_HOLD_SECONDS * 0.6).timeout
	var fade: ColorRect = scene.get_node("Overlay/Fade")
	_assert_true(fade.color.a == 0.0 and scene.summary().get("lit_visible", []) == [false, true, false], "the lit item holds on a clear screen before the fade: alpha %.2f" % fade.color.a)
	await create_timer(scene.CONFIRM_HOLD_SECONDS * 0.4 + scene.FADE_TO_BLACK_SECONDS * 0.5).timeout
	_assert_true(fade.color.a > 0.2 and fade.color.a < 0.95, "the screen is fading after the hold: alpha %.2f" % fade.color.a)
	_assert_true(bool(scene.summary().get("music_playing", false)) and is_equal_approx(float(scene.summary().get("music_volume_db", 0.0)), GameSettings.MUSIC_PLAYER_DB), "03 keeps its volume through the fade (the original stops it with the scene change)")
	await create_timer(scene.FADE_TO_BLACK_SECONDS * 0.5 + 0.3).timeout
	await process_frame
	await process_frame
	var runtime = current_scene
	_assert_true(runtime != null and runtime.has_method("apply_loop"), "the fade hands over to BattleSceneRuntime")
	if runtime != null and runtime.has_method("apply_loop"):
		_assert_eq(str(runtime.scenario_path), "res://content/battles/story_002.json", "the runtime boots the saved scenario")
		_assert_true(runtime.opening_coordinator != null and runtime.opening_coordinator.story_mode, "戈爾山道 resumes in story mode")
		runtime.queue_free()
	await process_frame
	await process_frame


func _run_battle_record_checkpoint() -> void:
	## A mid-battle checkpoint (the original 戰場記錄) wins over the saved position: the title
	## boots that battle with a hand-off that loads the checkpoint, and the battle resumes it.
	CampaignProgress.reset_campaign()
	var runtime_probe = RuntimeScene.instantiate()
	root.add_child(runtime_probe)
	current_scene = runtime_probe
	await process_frame
	runtime_probe.start_dev_first_control_harness()
	runtime_probe.set_process(false)
	var saved: Dictionary = runtime_probe.settlement_controller.save_battle()
	_assert_true(bool(saved.get("ok", false)), "a first-battle checkpoint can be written for the test")
	var turn_saved := int(runtime_probe.play_loop.get("turn", 0))
	runtime_probe.queue_free()
	await process_frame
	await process_frame
	var records: Array = CampaignProgress.battle_record_entries()
	_assert_eq(records.size(), 1, "the title sees one battle record")
	var scene = await _boot()
	scene.select(1)
	var transition: Dictionary = scene.confirm()
	_assert_eq(transition.get("status", ""), "fading", "戰場記錄 with a checkpoint starts the fade")
	_assert_eq(transition.get("resume_scenario_path", ""), "res://content/battles/battle_051.json", "the checkpoint's battle is the target")
	_assert_true(str(transition.get("battle_record", "")).ends_with("battle_051_cannon_fodder.save"), "the transition names the checkpoint file")
	_assert_true(CampaignProgress.has_pending() and bool(CampaignProgress.pending.get("load_checkpoint", false)), "the hand-off asks the battle to load its checkpoint")
	await create_timer(scene.FADE_SECONDS + 0.3).timeout
	await process_frame
	await process_frame
	await process_frame
	var runtime = current_scene
	_assert_true(runtime != null and runtime.has_method("apply_loop"), "the fade hands over to BattleSceneRuntime")
	if runtime != null and runtime.has_method("apply_loop"):
		_assert_eq(str(runtime.runtime_entrypoint), "restored_battle_checkpoint", "the battle boots straight into the restored checkpoint")
		_assert_eq(int(runtime.play_loop.get("turn", -1)), turn_saved, "the restored loop is the saved one")
		_assert_true(runtime.interaction_state != "opening_timeline", "the opening is replaced by the restored battle")
		runtime.queue_free()
	DirAccess.remove_absolute("user://battle_051_cannon_fodder.save")
	await process_frame
	await process_frame


func _run_new_story() -> void:
	## 開始新故事 clears the saved position, fades into the intro film (start.ani, skippable)
	## and then boots the product opening (level 51).
	CampaignProgress.reset_campaign()
	CampaignProgress.save_progress({"scenario_path": "res://content/battles/story_002.json", "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "gold": 1}, "from_scenario_id": "x", "world": {}})
	var scene = await _boot()
	var transition: Dictionary = scene.confirm()
	_assert_eq(transition.get("action", ""), "new_story", "Enter on the first item starts a new story")
	_assert_eq(transition.get("scene", ""), "res://game/battle/scene/BattleSceneRuntime.tscn", "the new story boots the product opening scene")
	_assert_true(CampaignProgress.load_progress().is_empty(), "a new story clears the saved campaign position")
	_assert_true(not CampaignProgress.has_pending(), "a new story arms no hand-off")
	await create_timer(scene.FADE_SECONDS + 0.3).timeout
	await process_frame
	await process_frame
	_assert_eq(str(scene.transition.get("status", "")), "movie", "the fade leads into the intro film")
	_assert_true(scene.intro_player != null, "the intro film player is on the title")
	if scene.intro_player != null:
		var film: Dictionary = scene.intro_player.summary()
		_assert_eq(str(film.get("movie", "")), "start", "the intro plays movie.pak start.ani")
		_assert_true(bool(film.get("playing", false)) and int(film.get("frame_index", -1)) >= 0, "the intro is paging frames")
		_assert_true(bool(film.get("audio_playing", false)), "start.snd plays with the film")
		_assert_true(current_scene == scene, "the title stays the current scene while the film plays")
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_SPACE
		scene.intro_player.handle_input(key)
		_assert_eq(str(scene.transition.get("movie", "")), "skipped", "a key skips the intro film")
	_assert_eq(str(scene.transition.get("status", "")), "scene_changed", "the skipped film boots the first scene")
	await process_frame
	await process_frame
	var runtime = current_scene
	_assert_true(runtime != null and runtime.has_method("apply_loop"), "the fade hands over to BattleSceneRuntime")
	if runtime != null and runtime.has_method("apply_loop"):
		var summary: Dictionary = RuntimeReadback.runtime_contract_summary(runtime)
		_assert_eq(summary.get("startup_mode", ""), "product_opening", "the new story starts the product opening")
		_assert_eq(str(runtime.scenario_path), "res://content/battles/battle_051.json", "the new story starts at the first battle")
		runtime.queue_free()
	await process_frame
	await process_frame


func _run_game_over_screen() -> void:
	## Title011 sunset + Title012 text fade in from black; a key after the fade fades out
	## into the title screen.
	var scene = GameOverScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var summary: Dictionary = scene.summary()
	_assert_eq(summary.get("phase", ""), "fading_in", "the GAME OVER screen starts behind the black fade")
	_assert_true(bool(summary.get("cue_playing", false)), "GAMEOVER.WAV (resource 628, defProcGameOverBOSS) plays as the screen appears")
	_assert_eq(summary.get("text_position"), Vector2(55, 211), "GAME OVER text is centred on the frame (provisional)")
	for role in ["game_over_background", "game_over_text"]:
		var sprite = scene.get_node_or_null("Title_" + role)
		_assert_true(sprite != null and sprite.texture != null, "%s sprite is drawn" % role)
	_assert_true(scene.dismiss().is_empty(), "input during the fade-in is ignored")
	# 0x42aea0／0x42afc0 unhurried: 60-tick hold, ≈128-tick word, hand-back — ≈190 ticks.
	await create_timer(OriginalTick.seconds(200) + 0.2).timeout
	_assert_eq(scene.summary().get("phase", ""), "waiting", "once the GAME OVER word is full the screen waits for input")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	scene._unhandled_input(key)
	_assert_eq(scene.summary().get("phase", ""), "fading_out", "a key press starts the fade-out")
	_assert_eq(scene.summary().get("transition", {}).get("scene", ""), "res://game/title/TitleScreen.tscn", "the fade-out leads to the title")
	await create_timer(scene.FADE_OUT_SECONDS + 0.3).timeout
	await process_frame
	await process_frame
	var title = current_scene
	_assert_true(title != null and title.has_method("summary") and str(title.summary().get("schema", "")) == "hsl_title_screen.v1", "the GAME OVER screen hands over to the title screen")
	if title != null:
		title.queue_free()
	await process_frame
	await process_frame


func _run_defeat_leaves_for_game_over() -> void:
	## A lost battle has no result page: it fades to black and leaves for the GAME OVER
	## screen by itself (0x42cbd0 -> level 999 -> defProcGameOverBOSS 0x42aea0).
	var scene = RuntimeScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var presentation = scene.get_node("BattlePresentation")
	_assert_true(not presentation.battle_finished, "a running battle is not finished")
	scene.play_loop["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	scene._process(0.0)
	while presentation.dialogue_active():
		presentation.advance_dialogue()
	scene._process(0.0)
	_assert_true(presentation.battle_finished, "the defeat reaches the finished-battle state")
	await process_frame
	_assert_true(current_scene == scene, "the finished battle first fades to black")
	for _frame in range(9):
		scene._process(scene.END_FADE_SECONDS / 4.0)
	await process_frame
	await process_frame
	var game_over = current_scene
	_assert_true(game_over != null and game_over.has_method("summary") and str(game_over.summary().get("schema", "")) == "hsl_game_over_screen.v1", "after the fade the defeat opens the GAME OVER screen")
	if game_over != null:
		game_over.queue_free()
	await process_frame
	await process_frame


func _run_game_clear_screen() -> void:
	## The GameClear sequence (level 998) in the defProcClearBOSS state order
	## (original_music.md §3.5): the epilogue text over the dusk castle, the STORYOVER dialogue
	## on black (ten 緹娜／漢克斯 lines with the script's pauses, click-confirmed), the second
	## text over the second backdrop, the party showcase, the credits scroll — each behind a
	## fade, with a key skipping ahead; after the credits a key leaves for the title. The music
	## follows the phases: 07, then 04 at the showcase, 02 at the credits, never faded.
	var clear_script: Script = load("res://game/title/GameClearScreen.gd")
	clear_script.set("showcase", [{"actor_id": "001", "name": "雷歐納德", "portrait": "res://content/imported/hsl/chapter01/portraits/001.png"}, {"actor_id": "002", "name": "緹娜", "portrait": "res://content/imported/hsl/chapter01/portraits/002.png"}])
	var scene = GameClearScene.instantiate()
	scene.phase_seconds_scale = 0.05
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var summary: Dictionary = scene.summary()
	_assert_eq(str(summary.get("phase", "")), "epilogue_1", "the sequence opens on Over001 over the first backdrop (state 1)")
	_assert_eq(int(summary.get("phase_count", 0)), 5, "five phases: epilogue 1, the dialogue, epilogue 2, the party showcase, credits")
	_assert_eq(int(summary.get("epilogue_step_count", 0)), 24, "STORYOVER compiles to 24 steps (delays, ten lines, the footsteps, the reveal)")
	_assert_eq(int(summary.get("showcase_count", 0)), 2, "two party members are shown")
	_assert_true(str(summary.get("music_stream", "")).ends_with("/07.ogg") and bool(summary.get("music_playing", false)), "the ending opens on track 07 (§3.5)")
	var background = scene.get_node_or_null("Background")
	var text = scene.get_node_or_null("Text")
	_assert_true(background != null and background.texture != null and background.texture.resource_path.ends_with("OverBG01.SHP.png"), "OverBG01 is the first backdrop")
	_assert_true(text != null and text.texture != null and text.texture.resource_path.ends_with("Over001.SHP.png"), "Over001 is the first narration")
	_assert_eq(text.position, Vector2(42, 0), "Over001 starts centred at the top (remake layout)")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	scene._unhandled_input(key)
	_assert_eq(str(scene.summary().get("phase", "")), "epilogue", "a key skips to the STORYOVER dialogue (state 3)")
	_assert_true(str(scene.summary().get("music_stream", "")).ends_with("/07.ogg"), "07 carries on through the dialogue")
	await create_timer(0.12).timeout
	await process_frame
	summary = scene.summary()
	_assert_true(bool(summary.get("epilogue_waiting_confirm", false)), "after the opening pause the first line waits for a confirm")
	_assert_eq(summary.get("epilogue_messages", []), ["2396"] as Array[String], "緹娜's first line (2396) opens the dialogue")
	_assert_eq(str(summary.get("epilogue_speaker", "")), "緹娜：", "the board names 緹娜")
	_assert_true(scene.get_node("DialogueLayer/EpilogueBoard").visible, "the dialogue board shows over the black screen")
	scene._unhandled_input(key)
	_assert_true(not bool(scene.summary().get("epilogue_waiting_confirm", true)), "confirming the line enters the following pause")
	await create_timer(0.08).timeout
	await process_frame
	_assert_eq(str(scene.summary().get("epilogue_speaker", "")), "漢克斯：", "漢克斯 answers (2397) after the pause")
	var epilogue_frames := 0
	while str(scene.summary().get("phase", "")) == "epilogue" and epilogue_frames < 900:
		if bool(scene.summary().get("epilogue_waiting_confirm", false)):
			scene._unhandled_input(key)
		await process_frame
		epilogue_frames += 1
	var expected_lines: Array[String] = []
	for step in (scene.manifest.get("game_clear_epilogue", {}) as Dictionary).get("steps", []):
		if str((step as Dictionary).get("kind", "")) == "message":
			expected_lines.append(str((step as Dictionary).get("message_id", "")))
	_assert_eq(scene.summary().get("epilogue_messages", []), expected_lines, "every STORYOVER line is shown once, in script order")
	_assert_eq(expected_lines.size(), 10, "STORYOVER has ten lines")
	_assert_true(not scene.get_node("DialogueLayer/EpilogueBoard").visible, "the board clears when the dialogue ends")
	summary = scene.summary()
	_assert_eq(str(summary.get("phase", "")), "epilogue_2", "actDeleteDarkScreen hands over to the second epilogue (state 9)")
	_assert_true(text.texture.resource_path.ends_with("Over002.SHP.png") and background.texture.resource_path.ends_with("OverBG02.SHP.png"), "Over002 over OverBG02")
	_assert_true(str(summary.get("music_stream", "")).ends_with("/07.ogg") and bool(summary.get("music_playing", false)), "07 still plays over Over002")
	scene._unhandled_input(key)
	summary = scene.summary()
	_assert_eq(str(summary.get("phase", "")), "showcase", "another key skips to the party showcase")
	_assert_true(str(summary.get("music_stream", "")).ends_with("/04.ogg") and bool(summary.get("music_playing", false)), "the showcase switches to track 04 (state 11)")
	_assert_true(background.texture.resource_path.ends_with("Title011.SHP.png"), "the showcase uses the TITLE011 card backdrop")
	_assert_eq(scene.get_node("Showcase").get_child_count(), 2, "one card per member")
	_assert_eq(str(scene.get_node("Showcase/Member0/Name").text), "雷歐納德", "the first card names 雷歐納德")
	_assert_true(scene.get_node_or_null("Showcase/Member0/Portrait") != null, "the first card carries the portrait")
	scene._unhandled_input(key)
	summary = scene.summary()
	_assert_eq(str(summary.get("phase", "")), "credits", "another key skips to the credits")
	_assert_true(str(summary.get("music_stream", "")).ends_with("/02.ogg") and bool(summary.get("music_playing", false)), "the credits switch to track 02 (states 16-17)")
	_assert_true(text.texture.resource_path.ends_with("workteam_simplified.png"), "the workteam scroll is the credits, shown as its simplified redraw (SimplifiedDisplay.texture_path)")
	var start_y: float = text.position.y
	await create_timer(1.2).timeout
	await process_frame
	_assert_true(text.position.y < start_y, "the credits roll upwards")
	var frames := 0
	while str(scene.summary().get("phase", "")) != "waiting" and frames < 600:
		await process_frame
		frames += 1
	_assert_eq(str(scene.summary().get("phase", "")), "waiting", "after the credits the screen waits for input")
	scene._unhandled_input(key)
	_assert_eq(str(scene.summary().get("phase", "")), "fading_out", "a key after the credits starts the fade-out")
	_assert_eq(str((scene.summary().get("transition", {}) as Dictionary).get("scene", "")), "res://game/title/TitleScreen.tscn", "the fade-out leads to the title")
	await create_timer(scene.FADE_SECONDS * 0.5).timeout
	summary = scene.summary()
	_assert_true(bool(summary.get("music_playing", false)) and is_equal_approx(float(summary.get("music_volume_db", 0.0)), GameSettings.MUSIC_PLAYER_DB), "02 keeps its volume through the fade-out: %.1f dB" % float(summary.get("music_volume_db", 0.0)))
	await create_timer(scene.FADE_SECONDS * 0.5 + 0.3).timeout
	await process_frame
	await process_frame
	var title = current_scene
	_assert_true(title != null and title.has_method("summary") and str(title.summary().get("schema", "")) == "hsl_title_screen.v1", "the GameClear screen hands over to the title screen")
	_assert_true(title != null and str(title.summary().get("music_stream", "")).ends_with("/03.ogg"), "back at the title the title track 03 plays")
	if title != null:
		title.queue_free()
	await process_frame
	await process_frame

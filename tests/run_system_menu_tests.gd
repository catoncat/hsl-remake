extends SceneTree

## In-battle system menu (BattleSystemMenu): Esc at a quiet action-phase boundary
## scrolls the Title041 panel in from the bottom edge; keyboard/mouse selection lights the
## Title042-047 item; 任務說明 shows the objective board; 儲存／讀取戰場記錄 go through the
## settlement controller's checkpoint; 讀取回憶錄 opens the 回憶錄 load list shared with the
## world scroll; 設定選項 is a not-remade hint; 回主選單 asks 確定／取消 then leaves for
## the title screen.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const WORLD_SCENE_PATH := "res://content/world/world_map_scene.json"
const GameSettings = preload("res://game/settings/GameSettings.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const StoryEffectObjects = preload("res://game/battle/runtime/StoryEffectObjects.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")

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
	CampaignProgress.reset_campaign()
	_run_confirm_class_inventory()
	await _run_scroll_and_items()
	await _run_records_and_memoir()
	await _run_main_menu_confirm()
	await _run_world_scroll_and_memoirs()
	CampaignProgress.reset_campaign()
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await process_frame
	await process_frame
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("SYSTEM_MENU_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SYSTEM_MENU_TESTS_FAIL count=%d" % failures.size())
		quit(1)


## Class check over both scroll variants: every item that writes a record or leaves the
## current game asks 確定／取消 on the one shared Title061 prompt (user recording 581.0 s
## 儲存戰場記錄, 592.5 s 回主選單). Only viewing items and the memoir list — whose occupied
## slots ask on the same prompt themselves — open without it.
func _run_confirm_class_inventory() -> void:
	var SystemMenu = load("res://game/battle/scene/BattleSystemMenu.gd")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SystemMenu.MANIFEST_PATH))
	var opens_without_prompt := {"system_items": ["mission", "load_memoir", "options"], "world_items": ["arrange_equipment", "save_memoir", "load_memoir", "options"]}
	for key in opens_without_prompt:
		var table: Dictionary = SystemMenu.WORLD_CONFIRM_ACTIONS if key == "world_items" else SystemMenu.CONFIRM_ACTIONS
		for item in manifest[key]:
			var id := str(item.get("id", ""))
			_assert_true(table.has(id) != (id in opens_without_prompt[key]), "%s %s: asks 確定／取消 = %s" % [key, id, table.has(id)])


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _boot_battle() -> Node:
	var scene = RuntimeScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame
	return scene


func _open(scene: Node) -> void:
	scene._input(_key(KEY_ESCAPE))
	await create_timer(scene.system_menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame


func _run_scroll_and_items() -> void:
	var scene = await _boot_battle()
	var menu = scene.system_menu
	_assert_true(menu != null and not menu.active(), "the scroll starts closed")
	_assert_eq(scene.interaction_state, "action_menu", "the dev harness leaves the runtime in the player action phase")
	scene._input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "opening", "Esc with nothing to cancel starts the scroll")
	_assert_true(menu.visible and menu.summary().get("panel_position").y > 400.0, "the panel starts below the frame")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	var summary: Dictionary = menu.summary()
	_assert_eq(summary.get("phase", ""), "menu", "the scroll settles into the menu phase")
	_assert_eq(summary.get("panel_position"), Vector2(190, 67), "the open panel sits at the reference position")
	_assert_eq(summary.get("selected_id", ""), "mission", "the first item is selected")
	_assert_true(bool(summary.get("lit_visible", false)), "the selected item is lit")
	_assert_eq(menu.get_node("Title_system_panel/Lit").position, Vector2(50, 35), "the 任務說明 lit shape sits on its glyph row (glyph registration, lane R5-L5)")
	menu.handle_input(_key(KEY_UP))
	_assert_eq(menu.summary().get("selected_id", ""), "main_menu", "Up wraps to the last item")
	menu.handle_input(_key(KEY_DOWN))
	_assert_eq(menu.summary().get("selected_id", ""), "mission", "Down wraps back")
	menu.hover_at(Vector2(300, 67 + 200))
	_assert_eq(menu.summary().get("selected_id", ""), "load_record", "hovering the fourth glyph row selects 讀取戰場記錄")
	_assert_eq(menu.item_at(Vector2(100, 200)), -1, "points outside the panel select nothing")
	# 任務說明: the objective board text on a card, Esc returns to the menu.
	menu.select(0)
	var result: Dictionary = menu.activate()
	_assert_eq(result.get("status", ""), "mission_shown", "任務說明 opens the mission card")
	_assert_eq(menu.summary().get("phase", ""), "mission", "the menu waits in the mission phase")
	_assert_true(menu.get_node("Mission").visible and str(menu._mission_text.text) != "", "the card shows the objective text")
	# The card is the win／fail board (user recording 577.55–579.48 s: WINDOW60 at (136,108),
	# 勝利條件／失敗條件 headings) dissolving in over the scroll and waiting for input — longer
	# than the opening board's own hold cap.
	var board = menu._mission_board
	_assert_true(board.global_position == Vector2(136, 108) and board.row_labels[0].text == "勝利條件" and board.stage == "in", "任務說明 dissolves the WINDOW60 win／fail board in at (136,108)")
	await create_timer((board.FADE_IN_TICKS + board.HOLD_TICKS + 10) * 0.016).timeout
	_assert_true(board.visible and board.stage == "hold" and board.modulate.a == 1.0, "the mission board waits for input (stage %s alpha %.2f)" % [board.stage, board.modulate.a])
	menu.handle_input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "menu", "Esc closes the card back to the menu")
	_assert_true(board.stage == "out", "the board dissolves out over the scroll")
	await create_timer((board.FADE_OUT_TICKS + 6) * 0.016).timeout
	_assert_true(not board.visible, "the board is gone after its dissolve")
	# 設定選項: the Title039 panel with gem knobs; toggles and sliders persist and drive the buses.
	GameSettings.reset()
	menu.select(4)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "options_shown", "設定選項 opens the options panel")
	_assert_eq(menu.summary().get("phase", ""), "options", "the scroll waits in the options phase")
	_assert_true(menu.get_node("Options").visible, "the Title039 panel is shown")
	_assert_eq(menu._options_panel.position, Vector2(142, 90), "the panel is centred on the frame")
	var scene_knob: TextureRect = menu._options_knobs["scene_effects"]
	_assert_eq(scene_knob.position, Vector2(330 - 18 - 14, 106 - 14), "場景效果 on puts the gem at the groove's on end")
	var music_knob: TextureRect = menu._options_knobs["music_volume"]
	_assert_eq(float(GameSettings.get_value("music_volume")), 1.0, "音樂音量 defaults to full, like the original's 255 (original_music.md §1; user decision 2026-09-26)")
	_assert_eq(music_knob.position, Vector2(330 - 18 - 14, 249 - 14), "音樂音量 1.0 puts the gem at the groove's max end")
	_assert_eq(menu._options_knobs["ready_action"].position, Vector2(330 - 18 - 14, 149 - 14), "預備動作 defaults on like the original's [0x477c14] = 3")
	result = menu.adjust_option(0)
	_assert_eq(result.get("value"), false, "Enter flips 場景效果 off")
	_assert_eq(scene_knob.position, Vector2(162 + 18 - 14, 106 - 14), "the gem moves to the off end")
	_assert_eq(GameSettings.get_value("scene_effects"), false, "the setting is stored")
	menu.handle_input(_key(KEY_DOWN))
	_assert_eq(menu.summary().get("options_selected", -1), 1, "Down selects 預備動作")
	result = menu.adjust_option(0)
	_assert_eq(GameSettings.get_value("ready_action"), false, "Enter flips 預備動作 off and stores it")
	menu.adjust_option(0)
	menu.handle_input(_key(KEY_DOWN))
	menu.handle_input(_key(KEY_LEFT))
	_assert_true(is_equal_approx(float(GameSettings.get_value("sfx_volume")), 0.9), "Left lowers 音效音量 by one step: %s" % GameSettings.get_value("sfx_volume"))
	_assert_true(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.9)), "Master carries 音效音量: %s" % AudioServer.get_bus_volume_db(0))
	menu.hover_at(Vector2(142 + 200, 90 + 249))
	_assert_eq(menu.summary().get("options_selected", -1), 3, "hovering the fourth row selects 音樂音量")
	result = menu.adjust_option(0, 0.5)
	_assert_true(is_equal_approx(float(GameSettings.get_value("music_volume")), 0.5), "a groove click sets 音樂音量 by position: %s" % GameSettings.get_value("music_volume"))
	var music_index := AudioServer.get_bus_index("Music")
	_assert_true(music_index > 0, "the Music bus exists")
	_assert_true(is_equal_approx(AudioServer.get_bus_volume_db(music_index) + AudioServer.get_bus_volume_db(0), linear_to_db(0.5)), "music out equals 音樂音量 alone: bus=%s master=%s" % [AudioServer.get_bus_volume_db(music_index), AudioServer.get_bus_volume_db(0)])
	_assert_eq(scene.get_node("BattleMusic").bus, "Music", "battle music sits on the Music bus")
	GameSettings._cache = {}
	_assert_true(is_equal_approx(float(GameSettings.get_value("music_volume")), 0.5), "settings reload from disk")
	# 場景效果 off: story effect objects are recorded but not drawn (sounds still play).
	GameSettings.set_value("scene_effects", false)
	var flash_spec := {"process": "defProcObjectMove", "object_fields": {"obj_Mode": "engZOOM"}}
	var record: Dictionary = StoryEffectObjects.new().insert(null, null, flash_spec, {}, "obj_Story_Test_Lightn", Vector2.ZERO, "ev1")
	_assert_eq(record.get("effect", ""), "flash", "the spec still classifies as a flash")
	_assert_eq(record.get("status", ""), "scene_effects_disabled", "with 場景效果 off the flash is not drawn")
	GameSettings.set_value("scene_effects", true)
	menu.handle_input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "menu", "Esc leaves the options for the scroll")
	GameSettings.reset()
	# Esc on the menu scrolls it away; the runtime stays in the action phase.
	menu.handle_input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "closing", "Esc on the menu starts the scroll-out")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	_assert_true(not menu.active() and not menu.visible, "the scroll is hidden after closing")
	_assert_eq(scene.interaction_state, "action_menu", "the battle is untouched by the menu")
	scene.queue_free()
	await process_frame
	await process_frame


func _run_records_and_memoir() -> void:
	var scene = await _boot_battle()
	var menu = scene.system_menu
	var checkpoint_path: String = scene.settlement_controller.checkpoint_path
	if FileAccess.file_exists(checkpoint_path):
		DirAccess.remove_absolute(checkpoint_path)
	await _open(scene)
	menu.select(1)
	# 儲存戰場記錄 asks 確定／取消 first (user recording 581.0 s: Title061 over the centre of
	# the open scroll, (256,217)); the checkpoint is written only after 確定.
	var result: Dictionary = menu.activate()
	_assert_eq(result.get("status", ""), "confirm", "儲存戰場記錄 asks for confirmation")
	_assert_eq(menu.summary().get("phase", ""), "confirm", "the save confirm prompt is up")
	_assert_true(menu.get_node("Confirm").visible and menu._confirm_buttons.position == Vector2(256, 217), "the Title061 pair sits over the scroll centre: %s" % menu._confirm_buttons.position)
	_assert_true(not FileAccess.file_exists(checkpoint_path), "nothing is written before 確定")
	_assert_true(bool(menu.summary().get("lit_visible", false)), "儲存戰場記錄 stays lit under the prompt")
	result = menu.confirm(false)
	_assert_eq(result.get("status", ""), "cancelled", "取消 returns to the menu without saving")
	_assert_eq(menu.summary().get("phase", ""), "menu", "the menu phase resumes after 取消")
	_assert_true(not FileAccess.file_exists(checkpoint_path), "取消 writes no checkpoint")
	menu.activate()
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "saved", "確定 writes the checkpoint")
	_assert_true(FileAccess.file_exists(checkpoint_path), "the checkpoint file exists afterwards")
	# The scroll stays open under 「進度儲存完成」 on the bottom BOARD02 message board (582.53–583.87 s).
	_assert_eq(menu.summary().get("phase", ""), "menu", "saving leaves the scroll open")
	_assert_true(RuntimeReadback.save_notice_visible(menu), "the 進度儲存完成 notice is shown")
	await create_timer(menu.SAVE_NOTICE_IN_SECONDS + menu.SAVE_NOTICE_HOLD_SECONDS * 0.5).timeout
	_assert_true(RuntimeReadback.save_notice_visible(menu) and menu.get_node("SaveNotice").modulate.a > 0.9, "the notice holds after its fade-in")
	await create_timer(menu.SAVE_NOTICE_HOLD_SECONDS * 0.5 + menu.SAVE_NOTICE_OUT_SECONDS + 0.2).timeout
	_assert_true(not RuntimeReadback.save_notice_visible(menu), "the notice is gone after about 1.35 s")
	menu.handle_input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	await _open(scene)
	menu.select(3)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "confirm", "讀取戰場記錄 asks for confirmation")
	_assert_eq(menu.summary().get("phase", ""), "confirm", "the confirm prompt is up")
	_assert_eq(menu.summary().get("confirm_selected", -1), 1, "取消 is preselected")
	_assert_true(menu.get_node("Confirm").visible and menu.summary().get("confirm_question", "?") == "", "the prompt shows only 確定／取消, no question (OPT-GUIDE＝原版)")
	menu.handle_input(_key(KEY_LEFT))
	_assert_eq(menu.summary().get("confirm_selected", -1), 0, "Left selects 確定")
	_assert_eq(menu.get_node("Confirm/Title_confirm_buttons/ConfirmLit").position, Vector2(7, 14), "確定 is lit on its button face (glyph registration, lane R5-L5)")
	result = menu.confirm(false)
	_assert_eq(result.get("status", ""), "cancelled", "取消 returns to the menu without loading")
	_assert_eq(menu.summary().get("phase", ""), "menu", "the menu phase resumes after 取消")
	result = menu.activate()
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "loaded", "確定 loads the checkpoint through the settlement controller")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	# 讀取回憶錄 opens the Title031 load list like the world scroll (0x425842 → 0x423bd0(…, 0));
	# an occupied slot asks, then leaves the battle for that memoir.
	var saved := {"scenario_path": "res://content/battles/story_002.json", "carry": {"gold": 275}, "world": {"current_point": 2}, "play_seconds": 12.0}
	_assert_true(CampaignProgress.save_memoir(0, saved, "test"), "a memoir can be saved for the test")
	await _open(scene)
	menu.select(2)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "memoir_list", "讀取回憶錄 opens the 回憶錄 list")
	_assert_eq(menu.summary().get("memoir_mode", ""), "load", "the list is in load mode")
	menu.select_memoir(0)
	menu.activate_memoir()
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "memoir_resumed", "確定 on an occupied slot resumes that memoir")
	_assert_eq(result.get("scenario_path", ""), "res://content/battles/story_002.json", "the resumed scenario is the memoir's")
	_assert_true(CampaignProgress.has_pending(), "the memoir is armed as the pending hand-off")
	CampaignProgress.consume_pending()
	CampaignProgress.clear_memoir(0)
	CampaignProgress.clear_progress()
	if FileAccess.file_exists(checkpoint_path):
		DirAccess.remove_absolute(checkpoint_path)
	# resume_saved_progress reloads the current scene; free the reloaded runtime too.
	await process_frame
	await process_frame
	if current_scene != null and current_scene != scene:
		current_scene.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame


func _run_main_menu_confirm() -> void:
	var scene = await _boot_battle()
	var menu = scene.system_menu
	await _open(scene)
	menu.select(5)
	var result: Dictionary = menu.activate()
	_assert_eq(result.get("status", ""), "confirm", "回主選單 asks for confirmation")
	menu.handle_input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "menu", "Esc on the prompt cancels it")
	menu.activate()
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "title", "確定 leaves for the title")
	await process_frame
	await process_frame
	var title = current_scene
	_assert_true(title != null and title.has_method("summary") and str(title.summary().get("schema", "")) == "hsl_title_screen.v1", "the title screen is the current scene afterwards")
	if title != null:
		title.queue_free()
	await process_frame
	await process_frame


func _boot_world_map() -> Node:
	## Big map standing at 歐姆村 (point 1) after the first battle, as the campaign hand-off leaves it.
	CampaignProgress.pending = {"scenario_path": WORLD_SCENE_PATH, "carry": {"gold": 275}, "from_scenario_id": "first_battle", "world": {"current_point": 1}}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = WORLD_SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	return scene


func _run_world_scroll_and_memoirs() -> void:
	for slot in range(CampaignProgress.MEMOIR_SLOTS):
		CampaignProgress.clear_memoir(slot)
	var scene = await _boot_world_map()
	var map = scene.world_map_runtime
	_assert_true(map != null and map.active, "the big map is active")
	var menu = scene.world_system_menu
	_assert_eq(menu.summary().get("variant", ""), "world", "the world scroll is the Title051 variant")
	_assert_true(not scene.system_menu.active(), "the battle scroll stays closed on the big map")
	scene._input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "opening", "Esc on the big map raises the world scroll")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	_assert_eq(menu.summary().get("selected_id", ""), "arrange_equipment", "the first world item is 整理裝備")
	_assert_eq(menu.get_node("Title_world_panel/Lit").position, Vector2(54, 38), "整理裝備 is lit on its glyph row")
	var result: Dictionary = menu.activate()
	_assert_eq(result.get("status", ""), "party_equipment", "整理裝備 hands off to the party equipment screen")
	_assert_true(scene.party_equipment_screen.active, "the screen opened")
	_assert_eq(str(scene.party_equipment_screen.summary().get("error", "")), "no_party", "this boot's {gold} carry is not a party: the screen only offers to close")
	scene.party_equipment_screen.close()
	_assert_eq(menu.summary().get("phase", ""), "menu", "closing the window brings the world scroll straight back")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	# 儲存回憶錄: the list opens in save mode, slot 1 saves the current world position.
	menu.select(1)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "memoir_list", "儲存回憶錄 opens the 回憶錄 list")
	_assert_eq(menu.summary().get("phase", ""), "memoir", "the scroll waits in the memoir phase")
	_assert_eq(menu.summary().get("memoir_mode", ""), "save", "the list is in save mode")
	_assert_true(str(menu._memoir_heading.texture.resource_path).ends_with("Title033.SHP.png"), "the save heading (Title033 儲存回憶錄) is shown")
	_assert_true(menu._memoir_rows[0].text.contains("──"), "an empty slot shows a dash")
	menu.handle_input(_key(KEY_DOWN))
	_assert_eq(menu.summary().get("memoir_selected", -1), 1, "Down selects the second slot")
	_assert_eq(menu.get_node("Memoir/Title_memoir_list/Cursor").position, Vector2(63, 80 + 33), "the cursor sits on the second slot band")
	menu.hover_at(Vector2(87 + 200, 44 + 80 + 10))
	_assert_eq(menu.summary().get("memoir_selected", -1), 0, "hovering the first band selects slot 1")
	result = menu.activate_memoir()
	_assert_eq(result.get("status", ""), "saved", "Enter on an empty slot saves the memoir")
	_assert_true(str(result.get("label", "")).contains("大地圖") and str(result.get("label", "")).contains("歐姆村"), "the label names the big map and the current point: %s" % result.get("label", ""))
	_assert_true(not CampaignProgress.load_memoir(0).is_empty(), "slot 1 holds a record afterwards")
	_assert_true(menu._memoir_rows[0].text.contains("歐姆村"), "the list row shows the saved label")
	# Saving again over the occupied slot asks first.
	result = menu.activate_memoir()
	_assert_eq(result.get("status", ""), "confirm", "saving over an occupied slot asks 確定／取消")
	_assert_true(menu.get_node("Confirm").visible and menu.summary().get("confirm_question", "?") == "", "the overwrite prompt shows no question (OPT-GUIDE＝原版)")
	result = menu.confirm(false)
	_assert_eq(result.get("status", ""), "cancelled", "取消 keeps the old memoir")
	_assert_eq(menu.summary().get("phase", ""), "memoir", "the list stays up after 取消")
	menu.handle_input(_key(KEY_ESCAPE))
	_assert_eq(menu.summary().get("phase", ""), "menu", "Esc leaves the list for the scroll")
	# 讀取回憶錄: an empty slot says so, an occupied slot asks then arms the resume hand-off.
	menu.select(2)
	result = menu.activate()
	_assert_eq(menu.summary().get("memoir_mode", ""), "load", "讀取回憶錄 opens the list in load mode")
	_assert_true(str(menu._memoir_heading.texture.resource_path).ends_with("Title032.SHP.png"), "the load heading (Title032 讀取回憶錄) is shown")
	menu.select_memoir(3)
	result = menu.activate_memoir()
	_assert_eq(result.get("status", ""), "empty", "an empty slot cannot be loaded")
	_assert_true(menu._hint.text == "空的回憶錄", "the hint reads 空的回憶錄")
	menu.select_memoir(0)
	result = menu.activate_memoir()
	_assert_eq(result.get("status", ""), "confirm", "loading an occupied slot asks first")
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "memoir_resumed", "確定 resumes the memoir")
	_assert_eq(result.get("scenario_path", ""), WORLD_SCENE_PATH, "the memoir resumes onto the big map")
	_assert_true(CampaignProgress.has_pending(), "the memoir is armed as the pending hand-off")
	CampaignProgress.consume_pending()
	await process_frame
	await process_frame
	if current_scene != null and current_scene != scene:
		current_scene.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame
	# 讀取戰場記錄 on the big map: without any mid-battle checkpoint it says so; with one it
	# asks, then re-enters that battle with a hand-off that loads the checkpoint on boot.
	scene = await _boot_world_map()
	menu = scene.world_system_menu
	var first_battle_save := "user://battle_051_cannon_fodder.save"
	if FileAccess.file_exists(first_battle_save):
		DirAccess.remove_absolute(first_battle_save)
	scene._input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	menu.select(3)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "no_record", "讀取戰場記錄 without a checkpoint reports none")
	_assert_true(menu._hint.text == "沒有戰場記錄", "the hint reads 沒有戰場記錄")
	var file := FileAccess.open(first_battle_save, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	result = menu.activate()
	_assert_eq(result.get("status", ""), "confirm", "讀取戰場記錄 with a checkpoint asks first")
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "battle_record_resumed", "確定 resumes the battle record")
	_assert_true(CampaignProgress.has_pending() and bool(CampaignProgress.pending.get("load_checkpoint", false)), "the hand-off asks the battle to load its checkpoint")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_051.json", "the hand-off targets the first battle")
	CampaignProgress.consume_pending()
	DirAccess.remove_absolute(first_battle_save)
	await process_frame
	await process_frame
	if current_scene != null and current_scene != scene:
		current_scene.queue_free()
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame
	# 回主選單 from the big map asks then leaves for the title.
	scene = await _boot_world_map()
	menu = scene.world_system_menu
	scene._input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	menu.select(5)
	result = menu.activate()
	_assert_eq(result.get("status", ""), "confirm", "回主選單 asks for confirmation on the big map")
	result = menu.confirm(true)
	_assert_eq(result.get("status", ""), "title", "確定 leaves the big map for the title")
	await process_frame
	await process_frame
	var title = current_scene
	_assert_true(title != null and title.has_method("summary") and str(title.summary().get("schema", "")) == "hsl_title_screen.v1", "the title screen follows the world scroll's 回主選單")
	if title != null:
		title.queue_free()
	for slot in range(CampaignProgress.MEMOIR_SLOTS):
		CampaignProgress.clear_memoir(slot)
	await process_frame
	await process_frame

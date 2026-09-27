extends SceneTree
## Windowed review of the in-battle system scroll: mid-scroll, fully open with 任務說明 lit,
## 讀取戰場記錄 hovered, the 確定／取消 prompt, the 任務說明 board, the 儲存戰場記錄 prompt and
## its 進度儲存完成 notice; on the big map 設定選項 with its 重製選項 entry and the 重製選項 page
## under the 原版 preset, the 舒適 preset and one row changed (自定).
## Output: ignored/system-menu-review/*.png + manifest.json (visual review input, not parity proof).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const OUT := "res://ignored/system-menu-review/"
var scene: Node
var menu: Node
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("System menu review requires a rendering window")
		quit(2)
		return
	CampaignProgress.reset_campaign() # a saved position would raise the resume prompt over the battle
	root.title = "HSL System Menu Review"
	root.size = Vector2i(640, 480)
	create_timer(90).timeout.connect(func(): push_error("System menu review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame
	menu = scene.system_menu
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	scene._input(escape)
	await create_timer(menu.SCROLL_SECONDS * 0.5).timeout
	await shot("00-scrolling-in")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await shot("01-open-mission-lit")
	scene.set_process_input(false)
	menu.hover_at(Vector2(300, 67 + 200))
	await shot("02-hover-load-record")
	menu.activate()
	await shot("03-confirm-prompt")
	menu.handle_input(_key(KEY_LEFT))
	await shot("04-confirm-ok-lit")
	menu.confirm(false)
	menu.select(0)
	menu.activate()
	await create_timer(0.7).timeout # the board's 32-tick dissolve in
	await shot("05-mission-card")
	menu.handle_input(_key(KEY_ESCAPE))
	await create_timer(0.7).timeout
	# 儲存戰場記錄: 確定／取消 over the scroll, then 進度儲存完成 at the bottom (the review
	# removes the checkpoint it wrote so later runs see no battle record).
	var checkpoint_path: String = scene.settlement_controller.checkpoint_path
	var had_checkpoint := FileAccess.file_exists(checkpoint_path)
	menu.select(1)
	menu.activate()
	menu.handle_input(_key(KEY_LEFT))
	await shot("05b-save-confirm-ok-lit")
	menu.confirm(true)
	await create_timer(menu.SAVE_NOTICE_IN_SECONDS + 0.2).timeout
	await shot("05c-save-notice")
	check(menu.save_notice_visible() and menu.active(), "the save notice shows over the open scroll")
	if not had_checkpoint:
		DirAccess.remove_absolute(checkpoint_path)
	menu.close()
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	check(not menu.active(), "the scroll closes again")
	# World variant (Title051) on the big map with the 回憶錄 list in save mode.
	scene.queue_free()
	await process_frame
	await process_frame
	for slot in range(CampaignProgress.MEMOIR_SLOTS):
		CampaignProgress.clear_memoir(slot)
	CampaignProgress.pending = {"scenario_path": "res://content/world/world_map_scene.json", "carry": {"gold": 275}, "from_scenario_id": "first_battle", "world": {"current_point": 1}}
	CampaignProgress.last_entry = {}
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/world/world_map_scene.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	menu = scene.world_system_menu
	scene._input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	scene.set_process_input(false)
	menu.select(4)
	menu.activate()
	GameSettings.set_value("music_volume", 0.6)
	menu.select_option(3)
	menu._refresh_options()
	await shot("06b-options-panel")
	GameSettings.reset()
	menu.select_option(menu.options_rows.size())
	await shot("06c-options-remake-entry")
	menu.adjust_option(0)
	await shot("06d-remake-options-original")
	menu.handle_input(_key(KEY_RIGHT)) # the preset row: 舒適
	await shot("06e-remake-options-comfort")
	menu.handle_input(_key(KEY_DOWN))
	menu.handle_input(_key(KEY_DOWN))
	menu.handle_input(_key(KEY_LEFT)) # 戰鬥資訊公開 back to 原版: the page turns 自定
	await shot("06f-remake-options-custom")
	check(menu.summary()["remake_options"].get("preset", "") == "custom", "changing one row turns the preset to 自定")
	menu.handle_input(_key(KEY_ESCAPE))
	GameSettings.reset()
	menu.handle_input(_key(KEY_ESCAPE))
	menu.select(1)
	await shot("06-world-scroll-save-memoir-lit")
	menu.activate()
	menu.activate_memoir()
	menu.select_memoir(1)
	await create_timer(menu.HINT_SECONDS + 0.2).timeout
	await shot("07-memoir-list-slot1-saved")
	for slot in range(CampaignProgress.MEMOIR_SLOTS):
		CampaignProgress.clear_memoir(slot)
	CampaignProgress.reset_campaign()
	finish()


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	records.append({"capture": label, "summary": menu.summary() if is_instance_valid(menu) else {}})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func finish() -> void:
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "hsl_system_menu_review.v1", "records": records, "failures": failures}, "  "))
	file.close()
	if failures.is_empty():
		print("SYSTEM_MENU_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("SYSTEM_MENU_REVIEW_FAIL count=%d" % failures.size())
		quit(1)

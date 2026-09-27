extends SceneTree
## Windowed review shots for the lane R5-L5 UI classes (menu highlight, cursor ornaments,
## panel alignment, stamina segments, name-safe wraps, town buttons). One short rendered
## run; shots go to OUT (ignored/). `-- before` writes to the before/ folder so the same
## route can be taken on a tree with the pre-fix game files restored.
##   tools/godot.sh --script res://tests/capture_ui_class_review.gd [-- before]
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const OUT := "res://ignored/ui-class-review/"
## Story line 81 of the protected-word scan: the natural wrap cuts 緹娜 after 緹.
const SPLIT_LINE_NEEDLE := "緹娜，妳就"
var folder := "after/"
var shots: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("UI class review requires a rendered window")
		quit(2)
		return
	root.title = "HSL UI Class Review"
	root.size = Vector2i(640, 480)
	create_timer(120.0).timeout.connect(func(): push_error("UI class review timed out"); quit(2))
	if OS.get_cmdline_user_args().has("before"):
		folder = "before/"
	DirAccess.make_dir_recursive_absolute(OUT + folder)
	await status_page()
	await system_menus()
	await title_cursor()
	await dialogue_wrap()
	await town_screen()
	print("UI_CLASS_REVIEW_SHOTS ", folder, " ", shots.size())
	quit(0)


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OUT + folder + name + ".png")
	shots.append(name)


func status_page() -> void:
	var loop := BattleFixture.loop()
	var unit: Dictionary = Loop._unit(loop, "leonard").duplicate(true)
	var panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	root.add_child(panel)
	await process_frame
	for stamina in [16, 20, 40]:
		unit["stamina"] = stamina
		panel.show_unit(unit, true)
		panel.money_label.text = "230" if folder == "after/" else "$  230"
		await shot("status_st%d" % stamina)
	panel.queue_free()
	await process_frame


func system_menus() -> void:
	for variant in ["battle", "world"]:
		var menu = preload("res://game/battle/scene/BattleSystemMenu.gd").new()
		menu.variant = variant
		root.add_child(menu)
		await process_frame
		menu.open()
		await create_timer(0.4).timeout
		for index in range(menu.items.size()):
			menu.select(index)
			await shot("system_%s_%d_%s" % [variant, index, menu.items[index]["id"]])
		menu.queue_free()
		await process_frame


func title_cursor() -> void:
	var title = load("res://game/title/TitleScreen.tscn").instantiate()
	root.add_child(title)
	await create_timer(0.8).timeout
	for index in range(title.items.size()):
		title.hover_at(title.item_rect(index).get_center())
		await shot("title_%d" % index)
	title.queue_free()
	await process_frame


func dialogue_wrap() -> void:
	var text := ""
	for file in DirAccess.get_files_at("res://content/imported/hsl/story_corpus/scripts"):
		if not file.ends_with(".json"):
			continue
		for message in JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/story_corpus/scripts/" + file))["messages"]:
			if str(message.get("text", "")).contains(SPLIT_LINE_NEEDLE):
				text = str(message["text"])
				break
		if text != "":
			break
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	root.add_child(dialogue)
	await process_frame
	dialogue.configure_portraits(preload("res://game/sim/ContentPaths.gd").ACTOR_PORTRAITS)
	dialogue.show_message("wrap", "漢克斯", text, "004")
	dialogue.position.y = 160
	await shot("dialogue_name_wrap")
	dialogue.queue_free()
	await process_frame


func town_screen() -> void:
	var units := {}
	for pair in [["hanks", "004"], ["hu", "003"], ["leonard", "001"], ["tina", "002"]]:
		units[pair[0]] = {"actor_id": pair[1], "level": 3, "inventory": [0, 0, 0, 0, 0, 0, 0, 0], "attributes": {}}
	var carry := {"schema": "hsl_campaign_carry.v1", "from_scenario_id": "story_001_ohm_village_opening", "from_outcome": "", "units": units, "loop": {"gold": 270}, "restore_vitals": true}
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/world/world_map_scene.json", "carry": carry, "from_scenario_id": "story_001_ohm_village_opening", "world": {}}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/world/world_map_scene.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await create_timer(0.6).timeout
	await shot("world_map")
	scene.world_map_runtime.select_point(1, "review")
	await create_timer(0.6).timeout
	await shot("town_menu")
	scene.queue_free()
	await process_frame

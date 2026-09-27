extends SceneTree
## Windowed review shots for lane R5-L5b (UI matched to the original captures): the title
## ornaments over 4 s while the hover moves across the three items (frames + a per-frame
## position table), the big-map status bar at the camera of original frame 01／04, and the town
## root screens of 席達鎮 and 兩棲族部落 at the cameras of original frames 03／04, plus an NPC
## line (top board) and a party line (bottom board). One short rendered run; output under
## ignored/ui-reference-review/ (visual review input — the parity checks are the headless suites).
##   tools/godot.sh --script res://tests/capture_ui_reference_review.gd
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const OUT := "res://ignored/ui-reference-review/"
const TITLE_SECONDS := 4.0
const TITLE_SHOT_INTERVAL := 0.1
## Camera top-left corners of the original frames (grid lines and BigMap.SHP matched):
## frames 01／04 at (640,480), frame 03 at (438,225); the camera node is centred.
const CAMERA_AMPHIBIAN := Vector2(640, 480)
const CAMERA_SIDAZHEN := Vector2(438, 225)
var shots: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("UI reference review requires a rendered window")
		quit(2)
		return
	root.title = "HSL UI Reference Review"
	root.size = Vector2i(640, 480)
	create_timer(180.0).timeout.connect(func(): push_error("UI reference review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT + "title/")
	await title_ornaments()
	await world_and_towns()
	for failure in failures:
		push_error(failure)
	print("UI_REFERENCE_REVIEW_SHOTS ", shots.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	shots.append(name)


func title_ornaments() -> void:
	var title = load("res://game/title/TitleScreen.tscn").instantiate()
	root.add_child(title)
	title.set_process_unhandled_input(false)
	await create_timer(0.5).timeout
	var table := PackedStringArray(["t_seconds\thovered\tgem_x\tgem_y\tbook_x\tbook_y"])
	var start: float = title.ornament_clock
	var next_shot := 0.0
	var index := 0
	while title.ornament_clock - start < TITLE_SECONDS:
		var elapsed: float = title.ornament_clock - start
		var item := mini(int(elapsed / (TITLE_SECONDS / 3.0)), 2)
		if title.hovered != item:
			title.hover_at(title.item_rect(item).get_center())
		if elapsed >= next_shot:
			var summary: Dictionary = title.summary()
			table.append("%.3f\t%d\t%.1f\t%.2f\t%.1f\t%.2f" % [elapsed, item, summary["gem_position"].x, summary["gem_position"].y, summary["hand_position"].x, summary["hand_position"].y])
			await shot("title/%03d" % index)
			index += 1
			next_shot += TITLE_SHOT_INTERVAL
		else:
			await process_frame
	var file := FileAccess.open(OUT + "title/ornament_positions.tsv", FileAccess.WRITE)
	file.store_string("\n".join(table) + "\n")
	file.close()
	check(index >= int(TITLE_SECONDS / TITLE_SHOT_INTERVAL) - 2, "title: %d frames over %.0f s" % [index, TITLE_SECONDS])
	title.queue_free()
	await process_frame


func world_and_towns() -> void:
	var units := {}
	for pair in [["hanks", "004"], ["hu", "003"], ["leonard", "001"], ["tina", "002"]]:
		units[pair[0]] = {"actor_id": pair[1], "level": 8, "inventory": [0, 0, 0, 0, 0, 0, 0, 0], "attributes": {}}
	var carry := {"schema": "hsl_campaign_carry.v1", "from_scenario_id": "story_001_ohm_village_opening", "from_outcome": "", "units": units, "loop": {"gold": 1270}, "restore_vitals": true}
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/world/world_map_scene.json", "carry": carry, "from_scenario_id": "story_001_ohm_village_opening", "world": {}}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/world/world_map_scene.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await create_timer(1.0).timeout
	var map = scene.world_map_runtime
	check(map != null and map.active, "world map starts")
	if map == null:
		return
	scene.camera.position = CAMERA_AMPHIBIAN + Vector2(320, 240)
	await shot("world_status_bar")
	for town in [[14, "amphibian_tribe", CAMERA_AMPHIBIAN], [6, "sidazhen", CAMERA_SIDAZHEN]]:
		scene.camera.position = (town[2] as Vector2) + Vector2(320, 240)
		var towns: Dictionary = map.state.get("towns", {})
		(towns[str(town[0])] as Dictionary)["exec_event"] = 0
		if int(town[0]) == 14:
			# Frame 04's save lists 武器店／護甲店／道具店／集會場 (TOWNDEF 142–145); a new
			# game's tree for this town is still empty.
			((towns["14"] as Dictionary)["tree"] as Dictionary)["0"] = [142, 143, 144, 145]
		map._open_town(int(town[0]))
		await create_timer(0.3).timeout
		var runtime = map.town_runtime
		check(runtime != null and str(runtime.mode) == "menu", "%s opens on its root menu" % town[1])
		if runtime == null:
			continue
		await shot("town_%s_root" % town[1])
		if int(town[0]) == 6:
			# Last: event 23 ends by requesting level 6, so the town is not left by hand.
			await dialogue_slots(runtime)
			break
		runtime.leave()
		await create_timer(0.2).timeout
	scene.queue_free()
	await process_frame


## 席達鎮: the weapon shop's keeper greets with a teShapeMessage (top board); event 23 (the
## tavern scene of original frame 06) has party lines (bottom board).
func dialogue_slots(town: Node) -> void:
	var codes: Array = town.menu_codes()
	if not codes.is_empty():
		town.select_entry(int(codes[0]))
		await create_timer(0.2).timeout
		check(str(town.summary()["dialogue_slot"]) == "top", "席達鎮 shop keeper speaks on the top board")
		await shot("town_sidazhen_npc_top")
		var guard := 0
		while str(town.mode) == "dialogue" and guard < 20:
			town.confirm()
			guard += 1
		if str(town.mode) == "shop":
			await shot("town_sidazhen_shop")
			town.shop_close()
		while str(town.mode) == "dialogue" and guard < 40:
			town.confirm()
			guard += 1
	await create_timer(0.1).timeout
	if str(town.mode) != "menu":
		return
	town._start_run(23, "review")
	var guard := 0
	while str(town.mode) == "dialogue" and str(town.summary()["dialogue_slot"]) != "bottom" and guard < 20:
		town.confirm()
		guard += 1
	await create_timer(0.2).timeout
	check(str(town.mode) == "dialogue" and str(town.summary()["dialogue_slot"]) == "bottom", "席達鎮 event 23 shows a party line on the bottom board")
	await shot("town_sidazhen_party_bottom")

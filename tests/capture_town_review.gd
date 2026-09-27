extends SceneTree
## Windowed review of the menu-style town screen at normal remake pacing: 歐姆村
## opened from the big map with Leonard's carried party, the root menu, the
## weapon-shop greeting and the original-composition shop window (buy onto the hand by a goods
## click and put down on a bag slot, sell by
## picking a bag item up and dropping it on the goods list, right click out), the armed exec-event
## dialogue (event 10 with the villager portrait and the 2000-gold grant), and
## the return to the map. Output: ignored/town-review/*.png + manifest.json
## (visual review input, not parity proof; the shop compares with original_world_town
## frames 08–14).
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const OUT := "res://ignored/town-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Town review requires a rendering window")
		quit(2)
		return
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {
		"schema": CampaignProgress.SCHEMA,
		"scenario_path": "res://content/world/world_map_scene.json",
		"carry": {
			"schema": "hsl_campaign_carry.v1", "from_scenario_id": "battle_004_level1", "from_outcome": "",
			"units": {"leonard": {"actor_id": "001", "level": 3, "inventory": [1, 0, 0, 0, 0, 0, 0, 0], "attributes": {}}},
			"loop": {"gold": 275}, "restore_vitals": true,
		},
		"from_scenario_id": "story_001_ohm_village_opening",
		"world": {},
	}
	root.title = "HSL Town Review"
	root.size = Vector2i(640, 480)
	create_timer(120).timeout.connect(func(): push_error("Town review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/world/world_map_scene.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var map = scene.world_map_runtime
	check(map != null and map.active, "world map scene starts through WorldMapRuntime")
	if map == null:
		finish()
		return
	# A fresh map reveals track 1 first and drops clicks meanwhile (input_records dropped_while_revealing).
	await wait_for(func(): return not bool(map.summary().get("reveal_busy", false)) and int(map.summary().get("revealing_track_count", 0)) == 0, 3.0)
	await create_timer(0.3).timeout
	# Click the current point (歐姆村) to enter the town.
	var home: Vector2 = RuntimeReadback.logical_to_viewport_position(scene, scene.world_to_logical_position(Vector2(910, 527)))
	await move_mouse(home)
	await click(home)
	await wait_for(func(): return map.town_runtime != null)
	await create_timer(0.2).timeout
	var town = map.town_runtime
	check(town != null and str(town.mode) == "menu", "clicking 歐姆村 opens the town on its root menu")
	if town == null:
		finish()
		return
	await shot("01-ohm-village-root-menu")
	# 武器店 is the first row on the WINDOW70 board (x 72, centre y 79.5).
	await click_until(ui(Vector2(120, 80)), func(): return str(town.mode) == "dialogue")
	check(str(town.mode) == "dialogue", "the weapon shop greets first")
	await shot("02-weapon-shop-greeting")
	await key(KEY_SPACE)
	await wait_for(func(): return str(town.mode) == "shop")
	check(str(town.mode) == "shop", "confirm opens the shop window")
	await shot("03-shop-window")
	# 長劍 is the first goods row: a click pays and puts it on the hand; a bag click puts it down.
	await click_until(ui(Vector2(360, 235)), func(): return int(town.party_gold()) == 75)
	check(int(town.party_gold()) == 75 and town.shop_screen.holding(), "buying 長劍 leaves 75 gold and puts it on the hand")
	await move_mouse(ui(Vector2(120, 268)))
	await shot("04-shop-bought-in-hand")
	await click_until(ui(Vector2(120, 268)), func(): return not town.shop_screen.holding())
	check(not town.shop_screen.holding(), "clicking bag slot 3 puts the bought 長劍 down")
	await move_mouse(ui(Vector2(600, 60)))
	await shot("04b-shop-placed")
	# Selling: pick the bought 長劍 (bag slot 2) up, then drop it on the goods list.
	await click_until(ui(Vector2(120, 224)), func(): return town.shop_screen != null and town.shop_screen.holding())
	check(town.shop_screen != null and town.shop_screen.holding(), "clicking the bag item picks it up")
	await move_mouse(ui(Vector2(420, 300)))
	await shot("05-shop-holding-bag-item")
	await click_until(ui(Vector2(420, 300)), func(): return int(town.party_gold()) == 175)
	check(int(town.party_gold()) == 175, "dropping it on the goods list sells it for 100")
	await right_click(ui(Vector2(420, 300)))
	await wait_for(func(): return str(town.mode) == "menu")
	check(str(town.mode) == "menu", "right click leaves the shop for the root menu")
	await shot("06-root-menu-after-shop")
	# Arm the finished 歐姆村 chain (event 10) as a script would, re-enter, talk.
	await key(KEY_ESCAPE)
	await wait_for(func(): return map.town_runtime == null)
	check(map.town_runtime == null, "Escape leaves the town")
	await shot("07-back-on-the-map")
	(map.state["towns"]["1"] as Dictionary)["exec_event"] = 10
	await click(home)
	await create_timer(0.3).timeout
	town = map.town_runtime
	check(town != null and str(town.mode) == "dialogue", "an armed exec event talks on entry")
	await shot("08-exec-event-villager")
	await key(KEY_SPACE)
	await create_timer(0.2).timeout
	await shot("09-exec-event-leonard")
	var guard := 0
	while town != null and str(town.mode) == "dialogue" and str(town.current_text) != "獲得 2000 金錢" and guard < 12:
		await key(KEY_SPACE)
		await create_timer(0.15).timeout
		guard += 1
	await shot("10-exec-event-gold-grant")
	while town != null and str(town.mode) == "dialogue" and guard < 24:
		await key(KEY_SPACE)
		await create_timer(0.15).timeout
		guard += 1
	check(town != null and str(town.mode) == "menu" and int(town.party_gold()) == 2175, "the chain ends on the menu with 2175 gold")
	await shot("11-root-menu-after-grant")
	finish()


## Windowed input lands a frame or two late (and the first click may only
## focus the window): poll the condition instead of sleeping a fixed time.
## A real player moves onto a button before pressing it; the harness does the
## same and re-clicks once when the GUI missed the first press (recorded).
func click_until(position: Vector2, condition: Callable) -> void:
	for attempt in range(2):
		await move_mouse(position)
		await click(position)
		await wait_for(condition, 0.8)
		if bool(condition.call()):
			if attempt > 0:
				records.append({"retry_click": position, "attempt": attempt + 1})
			return


func wait_for(condition: Callable, seconds: float = 2.0) -> void:
	var waited := 0.0
	while not bool(condition.call()) and waited < seconds:
		await create_timer(0.05).timeout
		waited += 0.05


func ui(logical: Vector2) -> Vector2:
	return logical * root.size.x / 640.0


func move_mouse(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func click(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	press.global_position = position
	Input.parse_input_event(press)
	await create_timer(0.05).timeout
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame


func right_click(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = position
	press.global_position = position
	Input.parse_input_event(press)
	await create_timer(0.05).timeout
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.05).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	var town = scene.world_map_runtime.town_runtime
	records.append({"capture": label, "town": town.summary() if town != null else {}})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func finish() -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify({"records": records, "failures": failures, "summary": scene.world_map_runtime.summary() if scene.world_map_runtime != null else {}}, "  "))
		manifest.close()
	if failures.is_empty():
		print("TOWN_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("TOWN_REVIEW_FAIL count=%d" % failures.size())
		quit(1)

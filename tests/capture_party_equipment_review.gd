extends SceneTree
## Windowed review of the 整理裝備 window (world scroll Title051 item 0 → the shared status
## window's mode 0): the scroll on the big map, page 4 狀態 over the level-2 party (琥
## shown), Leonard on the 裝備 page, 銀劍 held, and the result after it goes on. Fixture =
## the level-2 hand-off carry plus 銀劍／長弓／回復藥 in Leonard's bag (test items, not
## default grants). Output ignored/partyequip/.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")

const SCENARIO_PATH := "res://content/battles/gol_road_battle.json"
const WORLD_SCENE_PATH := "res://content/world/world_map_scene.json"
const SILVER_SWORD := 3
const LONG_BOW := 61
const POTION := 241

var OUT := "res://ignored/partyequip/"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("party equipment review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Party Equipment Review"
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.reset_campaign()
	var scenario := BattleScenario.load_file(SCENARIO_PATH)
	var loop := BattlePlayLoop.create([], "", scenario)
	loop["scenario_id"] = str(scenario.get("id", ""))
	loop["gold"] = 1234
	var carry := CampaignCarryRules.capture(loop)
	var bag: Array = carry["units"]["leonard"]["inventory"]
	for code in [SILVER_SWORD, LONG_BOW, POTION]:
		bag[bag.find(0)] = code
	carry["units"]["leonard"]["inventory"] = bag
	var world_map := WorldMapRules.load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": WORLD_SCENE_PATH, "carry": carry, "from_scenario_id": "battle_005_level2", "world": WorldMapRules.initial_state(world_map, 2)}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = WORLD_SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	var menu = scene.world_system_menu
	var screen = scene.party_equipment_screen
	scene._input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.3).timeout
	await shot("01-world-scroll")
	menu.activate()
	await create_timer(menu.SCROLL_SECONDS + 0.3).timeout
	check(screen.active and str(screen.summary().get("error", "")) == "", "the screen opened on the carry")
	await shot("02-status-page-hu")
	screen.select_member("leonard")
	screen.window.set_page(screen.StatusWindow.PAGE_EQUIP)
	await process_frame
	await shot("03-leonard-equip-page")
	var sword_index := -1
	for entry in screen.summary().get("bag", []):
		if int(entry.get("code", 0)) == SILVER_SWORD:
			sword_index = int(entry["index"])
	check(sword_index >= 0, "銀劍 is listed in Leonard's bag")
	screen.window.pick_up(sword_index)
	await process_frame
	await shot("04-holding-silver-sword")
	screen.window.click_equipment("weapon")
	check(str(screen.last_result.get("status", "")) == "changed", "銀劍 equipped")
	await process_frame
	await shot("05-after-equip")
	scene._input(_key(KEY_ESCAPE))
	await process_frame
	check(not screen.active, "Esc closed the screen")
	check(int(scene.campaign_handoff["carry"]["units"]["leonard"]["weapon_code"]) == SILVER_SWORD, "the hand-off carry took 銀劍")
	await shot("06-back-on-map")
	scene.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PARTY_EQUIPMENT_REVIEW_PASS output=%s" % OUT)
		quit(0)
	else:
		print("PARTY_EQUIPMENT_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

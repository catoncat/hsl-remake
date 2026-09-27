extends SceneTree

## Headless coverage for the between-battle 整理裝備 screen and its rules layer
## (PartyEquipmentRules over a sandbox PlayLoop of the carry's source scenario):
## template lookup by scenario id, members, dry-run marks, equip / unequip with the
## in-battle validation order, stat refresh, weapon_code, carry projection that keeps
## every other top-level field, and the explicit failure when the source scenario is
## unknown. Layout is a remake reading; nothing here proves original behaviour.

const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const PlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const Rules = preload("res://game/sim/PartyEquipmentRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const Screen = preload("res://game/world/PartyEquipmentScreen.tscn")

const SCENARIO_PATH := "res://content/battles/gol_road_battle.json"
const WORLD_SCENE_PATH := "res://content/world/world_map_scene.json"
const SILVER_SWORD := 3 # 銀劍: type 2 (weapon), job mask bit 0 = job 80 SwordMan (Leonard)
const LONG_BOW := 61 # 長弓: weapon for jobs 83/84 only — wrong_job for Leonard
const POTION := 241 # 回復藥: consumable, not equipment

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


## A carry as the level-2 battle would hand it on, plus test items in Leonard's bag
## and two foreign top-level fields that must survive the screen untouched.
func _fixture_carry() -> Dictionary:
	var scenario := BattleScenario.load_file(SCENARIO_PATH)
	var loop := PlayLoop.create([], "", scenario)
	_assert_true(bool(loop.get("scenario_ok", false)), "the level-2 scenario creates a loop (%s)" % str(loop.get("scenario_error", "")))
	loop["scenario_id"] = str(scenario.get("id", ""))
	loop["gold"] = 1234
	var carry := CarryRules.capture(loop)
	var leonard: Dictionary = carry["units"]["leonard"]
	var bag: Array = leonard["inventory"]
	bag[bag.find(0)] = SILVER_SWORD
	bag[bag.find(0)] = LONG_BOW
	bag[bag.find(0)] = POTION
	leonard["inventory"] = bag
	# A valid unclaimed-reward pool (SR-077 shape; CampaignCarryRules.apply validates it):
	# the screen must pass it through untouched, never rebuild or drop it.
	carry["pending_rewards"] = {"schema": "hsl_pending_rewards.v1", "items": [{"id": "carry:test-pool", "code": SILVER_SWORD, "source_id": "campaign", "source_slot": 0}]}
	carry["initialization_rng"] = 424242
	return carry


func _run() -> void:
	_run_rules()
	await _run_screen()
	await _run_scroll_hookup()
	await _run_story_storage_window()
	await process_frame
	await process_frame
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	if failures.is_empty():
		print("PARTY_EQUIPMENT_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: ", failure)
		print("PARTY_EQUIPMENT_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _run_rules() -> void:
	var campaign := CampaignProgress.load_campaign()
	_assert_eq(Rules.template_scenario_path(campaign, "battle_005_level2"), SCENARIO_PATH, "the level-2 scenario id resolves to gol_road_battle.json")
	_assert_eq(Rules.template_scenario_path(campaign, "no_such_scenario"), "", "an unknown scenario id resolves to nothing")
	_assert_eq(Rules.template_scenario_path(campaign, ""), "", "an empty scenario id resolves to nothing")
	var carry := _fixture_carry()
	var scenario := BattleScenario.load_file(SCENARIO_PATH)
	var bad := Rules.sandbox(PlayLoop.create([], "", scenario), {"schema": "bogus"})
	_assert_eq([bool(bad["ok"]), str(bad["error"])], [false, "invalid_carry_schema"], "a carry with the wrong schema is refused")
	var box := Rules.sandbox(PlayLoop.create([], "", scenario), carry)
	_assert_true(bool(box["ok"]), "the sandbox loop builds from the scenario and carry (%s)" % str(box["error"]))
	if not bool(box["ok"]):
		return
	var loop: Dictionary = box["loop"]
	var ids: Array = Rules.members(loop).map(func(u): return str(u["id"]))
	_assert_eq(ids, ["hu", "leonard"], "members are the controlled units in roster order")
	var leonard := PlayLoop.unit(loop, "leonard")
	_assert_eq(int(leonard["weapon_code"]), 2, "Leonard starts with 闊刃劍 (code 2)")
	_assert_eq(int(leonard["hp"]), int(leonard["max_hp"]), "the carry restores vitals in the sandbox")
	var sword_index: int = (leonard["inventory"] as Array).find(SILVER_SWORD)
	var bow_index: int = (leonard["inventory"] as Array).find(LONG_BOW)
	_assert_true(sword_index >= 0 and bow_index >= 0, "the test items reached the sandbox inventory")
	_assert_eq(Rules.preview(loop, "leonard", "weapon", sword_index, SILVER_SWORD), {"ok": true, "reason": ""}, "銀劍 previews as equippable for Leonard")
	_assert_eq(Rules.preview(loop, "leonard", "weapon", bow_index, LONG_BOW), {"ok": false, "reason": "wrong_job"}, "長弓 previews as wrong_job for Leonard")
	_assert_eq(str(Rules.preview(loop, "leonard", "weapon", (leonard["inventory"] as Array).find(POTION), POTION).get("reason", "")), "unsupported_equipment", "a potion is not equipment")
	_assert_eq(str(Rules.preview(loop, "nobody", "weapon", sword_index, SILVER_SWORD).get("reason", "")), "unknown_member", "an unknown member is refused")
	_assert_eq(str(Rules.preview(loop, "actor028_1", "weapon", 0, 21).get("reason", "")), "unknown_member", "an enemy is not a party member")
	var attack_before := int(leonard["combat_profile"]["live_attack_damage"])
	var rejected := Rules.change(loop, "leonard", "weapon", bow_index, LONG_BOW)
	_assert_eq([bool(rejected["ok"]), str(rejected["error"])], [false, "wrong_job"], "equipping 長弓 is rejected with its reason")
	_assert_eq(rejected["loop"], loop, "a rejected change returns the loop untouched")
	var changed := Rules.change(loop, "leonard", "weapon", sword_index, SILVER_SWORD)
	_assert_true(bool(changed["ok"]), "equipping 銀劍 succeeds (%s)" % str(changed["error"]))
	var after := PlayLoop.unit(changed["loop"], "leonard")
	_assert_eq(int(after["weapon_code"]), SILVER_SWORD, "weapon_code follows the equipped weapon")
	_assert_eq(EquipmentRules.equipped_code(after["equipment"], "weapon"), SILVER_SWORD, "the weapon slot holds 銀劍")
	_assert_eq(int(after["combat_profile"]["live_attack_damage"]), attack_before + 5, "attack refreshes by the +5 difference (銀劍 28 − 闊刃劍 23)")
	_assert_true((after["inventory"] as Array).has(2) and not (after["inventory"] as Array).has(SILVER_SWORD), "the old sword returns to the bag and the new one leaves it")
	_assert_eq(int(PlayLoop.unit(loop, "leonard")["weapon_code"]), 2, "the input loop is not mutated")
	var removed := Rules.change(changed["loop"], "leonard", "head", -1, 0)
	_assert_true(bool(removed["ok"]), "unequipping the head slot succeeds (%s)" % str(removed["error"]))
	var bare := PlayLoop.unit(removed["loop"], "leonard")
	_assert_eq(EquipmentRules.equipped_code(bare["equipment"], "head"), 0, "the head slot is empty afterwards")
	_assert_true((bare["inventory"] as Array).has(153), "鐵護輪 returns to the bag")
	_assert_eq(int(bare["combat_profile"]["live_defense"]), int(after["combat_profile"]["live_defense"]) - 6, "defense drops by 鐵護輪's +6")
	var projected := Rules.project(carry, removed["loop"])
	_assert_eq(int(projected["units"]["leonard"]["weapon_code"]), SILVER_SWORD, "project writes the new weapon into the carry unit")
	_assert_eq(projected["units"]["leonard"]["equipment"], bare["equipment"], "project writes the refreshed equipment list")
	_assert_eq(projected["units"]["leonard"]["inventory"], bare["inventory"], "project writes the refreshed inventory")
	_assert_eq(projected["units"]["hu"], carry["units"]["hu"], "an untouched member projects unchanged")
	for key in carry.keys():
		if key == "units":
			continue
		_assert_eq(projected[key], carry[key], "project keeps top-level field %s" % key)
	_assert_eq(projected.keys(), carry.keys(), "project adds no top-level fields")
	_assert_eq(int(carry["units"]["leonard"]["weapon_code"]), 2, "project does not mutate the input carry")
	# The projected carry applies back onto a fresh loop with the new equipment.
	var again := Rules.sandbox(PlayLoop.create([], "", scenario), projected)
	_assert_true(bool(again["ok"]), "the projected carry re-applies (%s)" % str(again["error"]))
	_assert_eq(int(PlayLoop.unit(again["loop"], "leonard")["weapon_code"]), SILVER_SWORD, "the re-applied carry keeps 銀劍")


func _run_screen() -> void:
	## The screen alone (no runtime): the mode 0 window (page, buttons), members, marks,
	## equip / unequip by hand, refusals, and the close projection that keeps every other
	## carry field.
	var campaign := CampaignProgress.load_campaign()
	var carry := _fixture_carry()
	var screen = Screen.instantiate()
	root.add_child(screen)
	await process_frame
	var received: Array = []
	screen.closed.connect(func(next_carry: Dictionary, changes: int) -> void: received.append({"carry": next_carry, "changes": changes}))
	var opened: Dictionary = screen.open(carry, campaign)
	_assert_true(bool(opened.get("ok", false)), "the screen opens on the carry via the campaign lookup (%s)" % str(opened.get("error", "")))
	var summary: Dictionary = screen.summary()
	_assert_eq(str(summary.get("schema", "")), "hsl_party_equipment.v1", "summary schema")
	_assert_eq(str(summary.get("scenario_path", "")), SCENARIO_PATH, "from_scenario_id battle_005_level2 resolves to the level-2 scenario")
	_assert_eq((summary.get("members", []) as Array).map(func(m): return str(m["name"])), ["琥", "雷歐納德"], "members show the portrait-manifest names in roster order")
	_assert_eq(str(summary.get("selected", "")), "hu", "the first member is selected")
	_assert_eq(int(summary.get("page", -1)), 4, "the window opens on page 4 狀態 (0x428390 +0x94 = 4)")
	_assert_eq(summary.get("buttons", []), ["prev", "next", "storage", "status", "equip", "magic", "special"], "page 4 shows 上一位／下一位／倉庫／狀態／裝備／魔法／特殊技; 丟棄／使用 only on the 倉庫 page (0x42a330 flags)")
	_assert_eq(["prev", "next", "storage", "status", "equip", "magic", "special"].map(func(key): return screen.window.buttons[key].position + Vector2(21, 21)), [Vector2(272, 429), Vector2(320, 429), Vector2(389, 429), Vector2(457, 429), Vector2(505, 429), Vector2(553, 429), Vector2(601, 429)], "button centres are 0x42ab40 mode 0's (y 0x1ad)")
	_assert_true(screen.window.get_node("Vitals").visible and screen.window.get_node_or_null("EquipmentBoard") != null and screen.window.get_node_or_null("AttributeBoard") != null, "vitals, the 狀態 attributes and the equipment board show for the selection")
	screen.select_member("leonard")
	summary = screen.summary()
	_assert_eq(str(summary.get("selected", "")), "leonard", "selecting Leonard")
	_assert_eq(screen.window.get_node("Vitals").values["name"].text, "雷歐納德", "the vitals strip names the selected member")
	var bag: Array = summary.get("bag", [])
	_assert_eq(bag.map(func(e): return [int(e["code"]), bool(e["ok"]), str(e["reason"])]), [[SILVER_SWORD, true, ""], [LONG_BOW, false, "wrong_job"]], "the bag lists only equipment, marked equippable / wrong_job (the potion is not listed)")
	var sword_index := int(bag[0]["index"])
	var bow_index := int(bag[1]["index"])
	# Wrong job: the held 長弓 stays in the hand (0x436f30 returns −1: no board, no change).
	var result: Dictionary = screen.request_equip(bow_index, LONG_BOW)
	_assert_eq([bool(result.get("ok", true)), str(result.get("reason", ""))], [false, "wrong_job"], "requesting 長弓 is refused with wrong_job")
	_assert_eq([int(screen.summary().get("page", -1)), int((screen.summary().get("holding", {}) as Dictionary).get("code", 0)), str(screen.summary().get("message", "x"))], [10, LONG_BOW, ""], "on the 裝備 page the refused 長弓 stays in the hand, no message board")
	_assert_true(screen.handle_input(_key(KEY_ESCAPE)) and screen.active and (screen.summary().get("holding", {}) as Dictionary).is_empty(), "the first Esc puts the held item back and keeps the window open")
	# Equip 銀劍 straight from the hand.
	var attack_before := int((screen.summary()["members"][1] as Dictionary)["attack"])
	result = screen.request_equip(sword_index, SILVER_SWORD)
	_assert_eq(str(result.get("status", "")), "changed", "the held 銀劍 goes on when the equipment board is clicked")
	summary = screen.summary()
	var leonard: Dictionary = summary["members"][1]
	_assert_eq(int(leonard["weapon_code"]), SILVER_SWORD, "the member summary shows the new weapon_code")
	_assert_eq(int(leonard["attack"]), attack_before + 5, "attack refreshed on screen (+5)")
	_assert_eq(int(summary.get("changes", 0)), 1, "one change counted")
	_assert_eq(screen.window.get_node("Slot_weapon/Name").text, "銀劍", "the equipment board shows 銀劍 in the weapon slot")
	_assert_true((summary.get("bag", []) as Array).any(func(e): return int(e["code"]) == 2), "闊刃劍 is back in the bag list")
	# Unequip the helmet from its slot.
	result = screen.request_unequip("head")
	_assert_eq(str(result.get("status", "")), "changed", "an empty-hand click on the 裝備 page takes the helmet off")
	_assert_true(screen.window.get_node_or_null("Slot_head/Name") == null, "the head slot reads empty")
	_assert_eq(int(screen.summary().get("changes", 0)), 2, "two changes counted")
	# Esc closes and projects.
	_assert_true(screen.handle_input(_key(KEY_ESCAPE)), "Esc is consumed")
	_assert_true(not screen.active and not screen.visible, "the screen closed")
	_assert_eq(received.size(), 1, "closed emitted once")
	var next_carry: Dictionary = received[0]["carry"]
	_assert_eq(int(received[0]["changes"]), 2, "closed reports the change count")
	_assert_eq(int(next_carry["units"]["leonard"]["weapon_code"]), SILVER_SWORD, "the returned carry holds 銀劍")
	_assert_eq(EquipmentRules.equipped_code(next_carry["units"]["leonard"]["equipment"], "head"), 0, "the returned carry has no helmet")
	_assert_true((next_carry["units"]["leonard"]["inventory"] as Array).has(153) and (next_carry["units"]["leonard"]["inventory"] as Array).has(2), "the returned bag holds 鐵護輪 and 闊刃劍")
	_assert_eq(next_carry["units"]["hu"], carry["units"]["hu"], "琥 is unchanged")
	for key in carry.keys():
		if key != "units":
			_assert_eq(next_carry[key], carry[key], "closing keeps top-level field %s" % key)
	_assert_eq(next_carry.keys(), carry.keys(), "closing adds no top-level field")
	_assert_eq(int(carry["units"]["leonard"]["weapon_code"]), 2, "the input carry is not mutated")
	# Unknown source scenario: explicit failure, close only.
	var lost := carry.duplicate(true)
	lost["from_scenario_id"] = "no_such_scenario"
	opened = screen.open(lost, campaign)
	_assert_eq([bool(opened.get("ok", true)), str(opened.get("error", ""))], [false, "unknown_source_scenario"], "an unknown from_scenario_id fails explicitly")
	_assert_true(str(screen.summary().get("message", "")).contains("找不到隊伍來源"), "the failure shows on screen")
	_assert_eq((screen.summary().get("members", []) as Array).size(), 0, "no members without a sandbox")
	_assert_eq(str(screen.request_equip(0, SILVER_SWORD).get("reason", "")), "inactive", "no equipment change without a sandbox")
	screen.close()
	_assert_eq(received.size(), 2, "closing still emits")
	_assert_eq(received[1]["carry"], lost, "the carry passes back unchanged")
	# Direct scenario path (dev / test entry) bypasses the campaign lookup.
	opened = screen.open(carry, {}, SCENARIO_PATH)
	_assert_true(bool(opened.get("ok", false)), "a scenario path override opens without a campaign")
	screen.close()
	# No carry at all.
	opened = screen.open({}, campaign)
	_assert_eq(str(opened.get("error", "")), "no_party", "an empty carry shows the no-party hint")
	screen.close()
	screen.queue_free()
	await process_frame


func _run_scroll_hookup() -> void:
	## On the big map: 整理裝備 in the world scroll opens the screen over the hand-off
	## carry; closing writes the carry back to the hand-off and the persisted position.
	CampaignProgress.reset_campaign()
	var carry := _fixture_carry()
	var world_map := preload("res://game/world/WorldMapRules.gd").load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var state: Dictionary = preload("res://game/world/WorldMapRules.gd").initial_state(world_map, 2)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": WORLD_SCENE_PATH, "carry": carry, "from_scenario_id": "battle_005_level2", "world": state}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = WORLD_SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var menu = scene.world_system_menu
	var screen = scene.party_equipment_screen
	_assert_true(screen != null and not screen.active, "the runtime hosts a closed party equipment screen")
	scene._input(_key(KEY_ESCAPE))
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	_assert_eq(str(menu.summary().get("selected_id", "")), "arrange_equipment", "整理裝備 is the first world item")
	var result: Dictionary = menu.activate()
	_assert_eq(str(result.get("status", "")), "party_equipment", "整理裝備 reports party_equipment")
	_assert_true(screen.active, "the screen opened from the scroll")
	_assert_eq(str(screen.summary().get("error", "")), "", "the hand-off carry resolves its source scenario")
	_assert_eq((screen.summary().get("members", []) as Array).size(), 2, "both carried members are listed")
	await create_timer(menu.SCROLL_SECONDS + 0.2).timeout
	await process_frame
	_assert_true(not menu.active(), "the scroll closed")
	screen.select_member("leonard")
	var sword_index := int((screen.summary()["bag"][0] as Dictionary)["index"])
	_assert_eq(str(screen.request_equip(sword_index, SILVER_SWORD).get("status", "")), "changed", "equipping through the hosted screen")
	scene._input(_key(KEY_ESCAPE))
	await process_frame
	_assert_true(not screen.active and str(menu.summary().get("phase", "")) == "menu", "Esc through the runtime closes the window and the world scroll comes straight back (original: right click returns to the scroll)")
	var handoff_carry: Dictionary = scene.campaign_handoff.get("carry", {})
	_assert_eq(int(handoff_carry["units"]["leonard"]["weapon_code"]), SILVER_SWORD, "the hand-off carry took the change")
	_assert_eq(handoff_carry["pending_rewards"], carry["pending_rewards"], "the pending_rewards pool survives the write-back untouched")
	_assert_eq(int(handoff_carry["initialization_rng"]), 424242, "initialization_rng survives the write-back")
	var saved: Dictionary = CampaignProgress.load_progress()
	_assert_eq(int((saved.get("carry", {}) as Dictionary).get("units", {}).get("leonard", {}).get("weapon_code", 0)), SILVER_SWORD, "the persisted campaign position holds the new weapon")
	_assert_eq(int((saved.get("world", {}) as Dictionary).get("current_point", 0)), 2, "the persisted world state stays at 戈爾山道")
	_assert_eq(str(saved.get("scenario_path", "")), WORLD_SCENE_PATH, "the position stays on the big map")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()


func _run_story_storage_window() -> void:
	## actEnterStorageWindow (STORY057, before the finals) opens the same hosted 整理裝備
	## screen over the hand-off carry and holds the story timeline until it closes; a
	## change made there rides the finale hand-off (provisional reading of the token).
	CampaignProgress.reset_campaign()
	var carry := _fixture_carry()
	var world_map := preload("res://game/world/WorldMapRules.gd").load_world_map("res://content/imported/hsl/global/world_map/world_map.json")
	var state: Dictionary = preload("res://game/world/WorldMapRules.gd").initial_state(world_map, 45)
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_057.json", "carry": carry, "from_scenario_id": "battle_005_level2", "world": state}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/story_057.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var coordinator = scene.opening_coordinator
	var screen = scene.party_equipment_screen
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "story_057 runs in story mode")
	if coordinator == null:
		scene.queue_free()
		return
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 6000 and not bool(coordinator.summary().get("storage_window_open", false)):
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(click)
		await process_frame
		frames += 1
	_assert_true(bool(coordinator.summary().get("storage_window_open", false)), "the timeline holds at actEnterStorageWindow")
	_assert_true(screen.active and str(screen.summary().get("error", "")) == "", "the 整理裝備 screen is up over the carried party")
	var opened: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "storage_window_enter")
	_assert_true(opened.size() == 1 and str(opened[0].get("status", "")) == "opened", "the entry is recorded as opened")
	for _i in range(20):
		await process_frame
	_assert_true(bool(coordinator.summary().get("storage_window_open", false)), "the story does not advance while the screen is up")
	screen.select_member("leonard")
	var sword_index := int((screen.summary()["bag"][0] as Dictionary)["index"])
	_assert_eq(str(screen.request_equip(sword_index, SILVER_SWORD).get("status", "")), "changed", "equipping inside the story's storage window")
	scene._input(_key(KEY_ESCAPE))
	await process_frame
	_assert_true(not screen.active and not bool(coordinator.summary().get("storage_window_open", false)), "Esc closes the screen and releases the timeline")
	var closed: Array = coordinator.summary().get("story_records", []).filter(func(record): return str(record.get("kind", "")) == "storage_window_enter" and str(record.get("status", "")) == "closed")
	_assert_true(closed.size() == 1 and int(closed[0].get("changes", 0)) == 1, "the close is recorded with its one change")
	frames = 0
	while coordinator.active and not coordinator.story_finished and frames < 6000:
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(click)
		await process_frame
		frames += 1
	_assert_true(coordinator.story_finished, "the scene reaches its card after the window")
	var options: Array = coordinator.summary().get("end_card_options", [])
	_assert_true(options.size() >= 1 and str(options[0].get("id", "")) == "end_route", "the card offers the dispatched finale")
	coordinator.confirm_end_card_option()
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "the finale hand-off is armed")
	var pending_carry: Dictionary = CampaignProgress.pending.get("carry", {})
	_assert_eq(int(pending_carry.get("units", {}).get("leonard", {}).get("weapon_code", 0)), SILVER_SWORD, "the finale hand-off carries the storage-window change")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()

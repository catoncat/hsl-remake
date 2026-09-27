extends SceneTree

## Headless coverage for the menu-style town screen: WorldPartyRules (carry <->
## town party bridge, buy / sell), and TownRuntime hosted by WorldMapRuntime over
## content/world/world_map_scene.json — opening 歐姆村 from its point, the root
## menu from the provisional initial tree, the weapon shop (goods table, buying
## into a member's inventory, insufficient gold, selling at half price), an armed
## exec_event chain (歐姆村 events 10 -> 11 -> 0 with the 2000-gold grant), the
## 米蘭多 tavern sub-menu whose child rewrites the tree, a teSetNextPlayLevelEvent
## exit into a not-remade level card, and persistence of gold and world state.
## Layout, pacing and prices are remake readings; nothing here proves the original.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const WorldPartyRules = preload("res://game/world/WorldPartyRules.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const TownShopScreen = preload("res://game/world/TownShopScreen.gd")

const SCENE_PATH := "res://content/world/world_map_scene.json"
const WORLD_MAP_PATH := "res://content/imported/hsl/global/world_map/world_map.json"
const TOWNDEF_PATH := "res://content/imported/hsl/global/world_map/towndef.json"
const TREES_PATH := "res://content/world/town_initial_trees.json"
const SPEAKERS := {
	"SID_雷歐納德": {"slot": 0, "players_row": 1, "name_text": "雷歐納德", "portrait_key": "face_0000"},
	"SID_緹娜": {"slot": 1, "players_row": 2, "name_text": "緹娜", "portrait_key": "face_0001"},
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _right_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	return event


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _carry(gold: int, inventory: Array) -> Dictionary:
	return {
		"schema": "hsl_campaign_carry.v1",
		"from_scenario_id": "battle_004_level1",
		"from_outcome": "",
		"units": {"leonard": {"actor_id": "001", "level": 3, "inventory": inventory, "attributes": {}}},
		"loop": {"gold": gold},
		"restore_vitals": true,
	}


func _fresh_state(start_point: int) -> Dictionary:
	var world_map := WorldMapRules.load_world_map(WORLD_MAP_PATH)
	var towns := TownEventRules.initial_town_state(TownEventRules.load_towndef(TOWNDEF_PATH), TownEventRules.load_initial_trees(TREES_PATH))
	var state := WorldMapRules.initial_state(world_map, start_point, towns)
	# Fixed tavern secret-man die (strict < ratio 8): keeps the tavern menus deterministic.
	state["secret_roll"] = 100
	return state


func _boot(carry: Dictionary, world: Dictionary) -> Node:
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": carry, "from_scenario_id": "story_001_ohm_village_opening", "world": world}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _open_town(scene: Node, point_id: int) -> Node:
	scene.world_map_runtime.select_point(point_id, "test")
	await process_frame
	return scene.world_map_runtime.town_runtime


## Confirms through every message page of the current run until it leaves
## dialogue mode; returns the texts seen.
func _confirm_through(town: Node, limit: int = 40) -> Array[String]:
	var seen: Array[String] = []
	var guard := 0
	while town.mode in ["dialogue", "delay"] and guard < limit:
		if town.mode == "dialogue" and (seen.is_empty() or seen[seen.size() - 1] != str(town.current_text)):
			seen.append(str(town.current_text))
		town.confirm()
		guard += 1
	return seen


## Waits for the route reveal animations to finish.
func _settle_reveals(map: Node) -> void:
	map.track_reveal_tick_seconds = 0.0001
	var frames := 0
	while bool(map.summary().get("reveal_busy", false)) and frames < 2400:
		await process_frame
		frames += 1
	await process_frame


func _teardown(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


## Original frames 03／04 (original_world_town, runtime-measured): the big map is not dimmed,
## TownBG sits at (158,148), the WINDOW70 stone board at (60,60) over TownBG's top-left, the
## entries are white rows from x 72 with glyph rows centred on y 79.5 + 32·n. Like the original
## there is no town name, gold／party strip or 離開城鎮 button (right click／Escape leave,
## checked by the Escape／leave paths).
func _check_town_composition(scene: Node, town: Node) -> void:
	await process_frame
	for child in town.get_children():
		if child is ColorRect:
			var rect := Rect2((child as ColorRect).position, (child as ColorRect).size)
			_assert_true(rect.size.x < 640.0 or rect.size.y < 480.0, "no full-screen shade dims the big map (%s)" % child.name)
	_assert_eq(town._picture.position, Vector2(158, 148), "TownBG at its original position")
	var board: TextureRect = town.get_node_or_null("MenuBoard")
	_assert_true(board != null and board.visible and board.position == Vector2(60, 60) and board.texture != null and board.texture.get_size() == Vector2(238, 264), "the WINDOW70 stone board shows at (60,60) on the root menu")
	_assert_true(board != null and board.get_index() > town._picture.get_index(), "the board is drawn over TownBG")
	var codes: Array = town.menu_codes()
	for index in range(codes.size()):
		var row: Button = town._menu_root.get_node_or_null("Entry%d" % int(codes[index]))
		_assert_true(row != null and row.flat and row.alignment == HORIZONTAL_ALIGNMENT_LEFT, "entry %d is a flat left-aligned text row" % int(codes[index]))
		if row == null:
			continue
		_assert_true(is_equal_approx(row.position.x, 72.0) and absf(row.position.y + row.size.y / 2.0 - (79.5 + 32.0 * index)) <= 0.6, "entry %d sits on original row %d (x 72, centre y %.1f), got %s" % [int(codes[index]), index, 79.5 + 32.0 * index, row.position])
		_assert_true(Rect2(board.position, board.size).encloses(Rect2(row.position, row.size)), "entry %d stays inside the board" % int(codes[index]))
	var labels := town.find_children("*", "Label", true, false).filter(func(node): return (node as CanvasItem).is_visible_in_tree())
	var buttons := town.find_children("*", "Button", true, false).filter(func(node): return (node as CanvasItem).is_visible_in_tree() and not str(node.name).begins_with("Entry"))
	_assert_true(labels.is_empty() and buttons.is_empty(), "no town name, gold／party strip or leave button on the root screen, as in original frames 03／04 (labels %s, buttons %s)" % [labels, buttons])
	var map_bar: Control = scene.get_node_or_null("UI/WorldMapStatusBar")
	_assert_true(map_bar != null and map_bar.visible and map_bar.get_index() < town.get_index(), "the big-map status bar stays visible under the town screen")


## Original frames 08–14 (original_world_town, runtime-measured; the loot window's static
## coordinates): the shop is the status window over the undimmed big map — WINDOW10 strip at
## (0,14), WINDOW20 bag (12,168), WINDOW90 goods (252,168) under the shop name, WINDOW40 `$:`
## (20,442), the six status buttons centred at y 429 (no 離開 — right click／Esc leave), prices
## ending at x 594.
func _check_shop_composition(scene: Node, town: Node, screen: Control) -> void:
	await process_frame
	_assert_true(not town._picture.visible, "the town picture hides under the shop window")
	var map_bar: Control = scene.get_node_or_null("UI/WorldMapStatusBar")
	_assert_true(map_bar != null and map_bar.visible, "the big map's status bar stays under the shop window")
	var vitals: Control = screen.get_node_or_null("Vitals")
	_assert_true(vitals != null and vitals.visible and vitals.position == Vector2(0, 14) and str(screen.vitals_error) == "", "the member's WINDOW10 strip shows at (0,14) (vitals error: %s)" % str(screen.vitals_error))
	var boards := {"BagBoard": [Vector2(12, 168), Vector2(224, 264)], "GoodsBoard": [Vector2(252, 168), Vector2(375, 220)], "GoldBoard": [Vector2(20, 442), Vector2(208, 32)]}
	for key in boards:
		var node: TextureRect = screen.get_node_or_null(key)
		_assert_true(node != null and node.position == boards[key][0] and node.texture.get_size() == boards[key][1], "%s at %s" % [key, boards[key][0]])
	_assert_eq(str((screen.get_node("ShopTitle") as Label).text), "武器店", "the goods board is titled with the shop name")
	_assert_eq(screen.goods_rows.size(), 3, "one row per goods code")
	for index in range(screen.goods_rows.size()):
		var row: Button = screen.goods_rows[index]
		_assert_eq(row.position, Vector2(260, 219 + 32 * index), "goods row %d at the loot window's row origin" % index)
		var labels := row.get_children().filter(func(child): return child is Label)
		var price: Label = labels[labels.size() - 1]
		_assert_true(price.text.begins_with("$") and is_equal_approx(row.position.x + price.position.x + price.size.x, 594.0), "goods row %d price right-aligned at x 594 (%s)" % [index, price.text])
	var centres := {"prev": 284, "next": 332, "equip": 397, "trade": 445, "storage": 493, "drop": 589}
	var original: Array[Rect2] = [Rect2(0, 14, 640, 144), Rect2(12, 168, 224, 264), Rect2(252, 168, 375, 220), Rect2(20, 442, 208, 32)]
	for key in centres:
		var button: TextureButton = screen.buttons.get(key)
		_assert_true(button != null and button.position + Vector2(21, 21) == Vector2(centres[key], 429), "%s button centred at (%d,429)" % [key, centres[key]])
		if button != null:
			original.append(Rect2(button.position, Vector2(42, 42)))
	for key in ["equip", "trade", "storage", "drop"]:
		_assert_true(screen.buttons.has(key) and (screen.buttons[key] as TextureButton).disabled, "%s is dimmed (no remake counterpart in the shop)" % key)
	for key in ["prev", "next"]:
		_assert_true(screen.buttons.has(key) and not (screen.buttons[key] as TextureButton).disabled, "%s works" % key)
	_assert_eq(screen.buttons.size(), 6, "only the original six status buttons (no remake 離開)")
	_assert_true(not screen.get_node("Description").visible, "the WINDOW50 description only shows on hover")


func _run() -> void:
	_run_party_rules()
	await _run_shop()
	await _run_shop_members()
	await _run_exec_event_chain()
	await _run_tavern_sub_menu()
	await _run_next_level_exit()
	await _run_ambush_victory_tavern_chain()
	await _run_town_reveals_map()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("TOWN_SCENE_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			print("FAIL: ", failure)
		quit(1)


func _run_party_rules() -> void:
	var carry := _carry(275, [1, 0, 0, 0, 0, 0, 0, 0])
	var party := WorldPartyRules.party_from_carry(carry, SPEAKERS)
	_assert_eq(int(party["gold"]), 275, "party gold comes from loop gold")
	_assert_eq(party["items"], [{"id": 1, "count": 1}], "party items count inventory codes")
	_assert_eq(party["members"], ["SID_雷歐納德"], "members resolve to SID tokens by PLAYERS row")
	_assert_eq(WorldPartyRules.party_from_carry({"gold": 5}, SPEAKERS)["gold"], 0, "an invalid carry yields an empty party")
	var members := WorldPartyRules.members(carry, SPEAKERS)
	_assert_eq(members.size(), 1, "one member summary")
	_assert_eq(str(members[0]["name"]), "雷歐納德", "member name from the speaker table")
	_assert_eq(int(members[0]["free_slots"]), 7, "free slots counted")
	# Interpreter deltas: +2 of item 12, -1 of item 1.
	var after := party.duplicate(true)
	after["gold"] = 2275
	after["items"] = [{"id": 12, "count": 2}]
	var applied := WorldPartyRules.apply_party(carry, party, after)
	_assert_eq(int(applied["carry"]["loop"]["gold"]), 2275, "apply_party writes gold")
	_assert_eq(applied["carry"]["units"]["leonard"]["inventory"], [12, 12, 0, 0, 0, 0, 0, 0], "apply_party removes lost codes and inserts gains at the first holes")
	_assert_eq((applied["receipt"]["placed"] as Array).size(), 2, "two placements receipted")
	_assert_eq((applied["receipt"]["removed"] as Array).size(), 1, "one removal receipted")
	var full := _carry(0, [1, 1, 1, 1, 1, 1, 1, 1])
	var dropped := WorldPartyRules.apply_party(full, WorldPartyRules.party_from_carry(full, SPEAKERS), {"gold": 0, "items": [{"id": 1, "count": 8}, {"id": 5, "count": 1}]})
	_assert_eq(dropped["receipt"]["dropped"], [{"item_id": 5}], "a gain with no room is receipted as dropped, never silently lost")
	var bought := WorldPartyRules.buy(carry, "leonard", 81, 180)
	_assert_true(bool(bought["ok"]), "buy succeeds with enough gold and room")
	_assert_eq(int(bought["gold"]), 95, "buy deducts the price")
	_assert_eq(bought["carry"]["units"]["leonard"]["inventory"], [1, 81, 0, 0, 0, 0, 0, 0], "buy inserts at the first empty slot")
	_assert_eq(str(WorldPartyRules.buy(carry, "leonard", 101, 500)["reason"]), "insufficient_gold", "buy refuses when gold is short")
	_assert_eq(str(WorldPartyRules.buy(full, "leonard", 1, 0)["reason"]), "inventory_full", "buy refuses a full inventory")
	_assert_eq(str(WorldPartyRules.buy(carry, "nobody", 1, 0)["reason"]), "unknown_member", "buy refuses an unknown member")
	_assert_eq(WorldPartyRules.sell_price(201), 100, "sell price is cost * 50 / 100 (0x414ab0), half rounded down")
	_assert_eq(WorldPartyRules.sell_price(-3), 0, "negative table costs are clamped, never paid out")
	var sold := WorldPartyRules.sell(bought["carry"], "leonard", 1, 81, 90, {"81": {"important": false}})
	_assert_true(bool(sold["ok"]), "sell succeeds for the slot's code")
	_assert_eq(int(sold["gold"]), 185, "sell adds the price")
	_assert_eq(sold["carry"]["units"]["leonard"]["inventory"], [1, 0, 0, 0, 0, 0, 0, 0], "sell removes the slot and shifts left")
	_assert_eq(str(WorldPartyRules.sell(carry, "leonard", 0, 1, 100, {"1": {"important": true}})["reason"]), "important_item", "important items cannot be sold")
	_assert_eq(str(WorldPartyRules.sell(carry, "leonard", 3, 1, 100, {})["reason"]), "inventory_selection_changed", "selling a slot holding another code is refused")


func _run_shop() -> void:
	var scene = await _boot(_carry(275, [1, 0, 0, 0, 0, 0, 0, 0]), {})
	var map = scene.world_map_runtime
	_assert_eq(map.current_point(), 1, "fresh map starts at 歐姆村")
	var town = await _open_town(scene, 1)
	_assert_true(town != null, "re-entering the current town point opens the town screen")
	if town == null:
		await _teardown(scene)
		return
	_assert_eq(str(town.mode), "menu", "a town without an armed exec event opens on its root menu")
	_assert_eq(town.menu_codes(), [1, 2, 3], "歐姆村 root menu = weapon / armour / item shop (provisional initial tree)")
	_assert_eq(str(town.town_label), "歐姆村", "town label from the point name")
	_assert_true(town._picture != null, "TownBG01 shows on the town screen")
	await _check_town_composition(scene, town)
	_assert_eq(int(town.party_gold()), 275, "gold from the carry")
	_assert_eq(map.summary()["town_open"], true, "map summary reports the open town")
	var picked: Dictionary = town.select_entry(1)
	_assert_eq(str(picked["status"]), "run", "picking the weapon shop runs its event")
	_assert_eq(str(town.mode), "dialogue", "the shopkeeper greets first (teShapeMessage 869)")
	_assert_eq(str(town.current_speaker), "武器店老闆", "shape name id 876")
	_assert_eq(str(town.summary()["dialogue_slot"]), "top", "an NPC line (teShapeMessage) uses the top board, as in original frames 05／07")
	_assert_true(is_equal_approx(town._dialogue.position.y, 20.0), "the top board sits 300 px above the bottom one (text board y 22 in the original)")
	_assert_true(not bool(town.summary()["menu_board_visible"]), "the stone board hides while a message plays")
	_confirm_through(town)
	_assert_eq(str(town.mode), "shop", "teCreateShop opens the shop window")
	_assert_eq(town.shop_goods(), [1, 81, 101], "goods = TOWNDEF item table 1 (長劍 / 木杖 / 匕首)")
	var screen: Control = town.shop_screen
	_assert_true(screen != null and screen.get_parent() == town, "the shop window is TownShopScreen")
	if screen == null:
		await _teardown(scene)
		return
	await _check_shop_composition(scene, town, screen)
	# Hover: WINDOW50 replaces the buttons, the last line is the sell price (frame 10: 賣價 = half).
	var long_sword: Button = screen.goods_rows[0]
	long_sword.mouse_entered.emit()
	var description: Control = screen.get_node("Description")
	var description_texts: Array = description.get_children().filter(func(child): return child is Label).map(func(child): return str(child.text))
	_assert_true(description.visible and description_texts.size() >= 2 and description_texts[0].begins_with("長劍") and description_texts[description_texts.size() - 1] == "賣價$100", "hovering 長劍 shows its description ending 賣價$100 (%s)" % [description_texts])
	long_sword.mouse_exited.emit()
	_assert_true(not description.visible, "leaving the row hides the description")
	# Buying: a goods click buys into the shown member's first empty slot.
	(screen.goods_rows[0] as Button).pressed.emit()
	var bought: Dictionary = town.records[town.records.size() - 1].get("result", {})
	_assert_true(bool(bought.get("ok", false)), "clicking 長劍 (200) buys it")
	_assert_eq(int(town.party_gold()), 75, "gold after buying")
	_assert_eq(scene.campaign_handoff["carry"]["units"]["leonard"]["inventory"], [1, 1, 0, 0, 0, 0, 0, 0], "the purchase lands in the carried inventory")
	_assert_eq(int(scene.campaign_handoff["carry"]["loop"]["gold"]), 75, "the runtime hand-off carry follows the purchase")
	_assert_eq(int((CampaignProgress.load_progress().get("carry", {}) as Dictionary).get("loop", {}).get("gold", -1)), 75, "the saved progress persists the new gold")
	_assert_true(str(town.shop_message).contains("買下"), "purchase receipt recorded")
	_assert_true(not screen.message_visible(), "a purchase raises no message board (original: only refusals do)")
	_assert_eq(str((screen.get_node("Gold") as Label).text), "75", "the `$:` box follows the purchase")
	_assert_true((screen.get_node("Bag_1") as Button).get_child_count() > 0, "the bought 長劍 shows in bag slot 2")
	(screen.goods_rows[2] as Button).pressed.emit()
	_assert_eq(str(town.records[town.records.size() - 1]["result"]["reason"]), "insufficient_gold", "匕首 (210) is refused at 75 gold")
	_assert_eq(str(town.shop_message), "抱歉, 您的金錢不足無法購買。", "refusal shows the original shop message 606 (0x415611)")
	var board: TextureRect = screen.get_node_or_null("MessageBoard")
	var line: Label = screen.get_node_or_null("MessageText")
	_assert_true(board != null and board.position == Vector2(75, 320) and board.texture.get_size() == Vector2(489, 145), "the refusal shows on BOARD02 at (75,320) (frame 12)")
	_assert_true(line != null and line.text == town.shop_message and line.get_theme_color("font_color") == BattleUISkin.TEXT_RED, "message 606 prints red (@2)")
	(screen.get_node("Bag_0") as Button).pressed.emit()
	_assert_true(not screen.holding(), "clicks under the message board do nothing")
	(screen.get_node("MessageBlocker") as Button).pressed.emit()
	_assert_true(not screen.message_visible(), "a click closes the message board")
	_assert_eq(town._reason_text("important_item"), "抱歉, 本店不收購此物品。", "important-item refusal uses the original shop message 607 (0x4153c2)")
	_assert_eq(str(town.shop_buy(5, "leonard")["reason"]), "not_for_sale", "items outside the goods table cannot be bought")
	screen.dismiss_message()
	# Selling: pick the bag item up, then click the goods list (0x414c00 shop branch).
	(screen.get_node("Bag_1") as Button).pressed.emit()
	_assert_eq(screen.summary()["holding"], {"unit_id": "leonard", "slot": 1, "code": 1}, "clicking a bag item picks it up")
	_assert_true((screen.get_node("Bag_1") as Button).get_child_count() == 0 and (screen.get_node("Hand") as TextureRect).visible, "the held item leaves its slot and follows the cursor")
	town.handle_input(_right_click())
	_assert_true(not screen.holding() and str(town.mode) == "shop", "right click puts the held item back first")
	_assert_eq(scene.campaign_handoff["carry"]["units"]["leonard"]["inventory"], [1, 1, 0, 0, 0, 0, 0, 0], "putting back sells nothing")
	(screen.get_node("Bag_1") as Button).pressed.emit()
	(screen.get_node("GoodsDrop") as Button).pressed.emit()
	_assert_eq(str(town.records[town.records.size() - 1].get("kind", "")), "shop_sell", "dropping the held item on the goods list sells it")
	_assert_eq(int(town.party_gold()), 175, "half price (100) returned")
	_assert_eq(scene.campaign_handoff["carry"]["units"]["leonard"]["inventory"], [1, 0, 0, 0, 0, 0, 0, 0], "inventory after selling")
	_assert_true(not screen.holding(), "the hand is empty after the sale")
	town.handle_input(_right_click())
	_assert_eq(str(town.mode), "menu", "right click with nothing held closes the shop and the event returns to the root menu")
	_assert_true(town.shop_screen == null, "the shop window is gone")
	_assert_eq(town.menu_codes(), [1, 2, 3], "root menu unchanged by the shop")
	_assert_eq(int(town.party_gold()), 175, "gold survives the run finish (interpreter party refreshed from the carry)")
	town.handle_input(_key(KEY_ESCAPE))
	await process_frame
	_assert_true(map.town_runtime == null, "Escape on the root menu leaves the town")
	_assert_eq(map.summary()["town_open"], false, "map summary reports the closed town")
	_assert_eq(int(scene.campaign_handoff["carry"]["loop"]["gold"]), 175, "the carry keeps the town's result after leaving")
	_assert_true(map.point_nodes.size() >= 1 and map.point_nodes.has(1), "the map layer is rebuilt after leaving (歐姆村 and whatever the reveal has shown)")
	var again = await _open_town(scene, 1)
	_assert_true(again != null and str(again.mode) == "menu", "the town reopens on its root menu")
	if again != null:
		again.handle_input(_right_click())
		await process_frame
		_assert_true(map.town_runtime == null, "right click on the root menu leaves the town, as in the original")
	await _teardown(scene)


## 上一位／下一位 cycle the shown member (strip, bag and the member a goods click buys for); a
## held item goes back to its slot first.
func _run_shop_members() -> void:
	var carry := _carry(275, [1, 0, 0, 0, 0, 0, 0, 0])
	carry["units"]["hu"] = {"actor_id": "003", "level": 3, "inventory": [0, 0, 0, 0, 0, 0, 0, 0], "attributes": {}}
	var scene = await _boot(carry, {})
	var town = await _open_town(scene, 1)
	if town == null:
		_assert_true(false, "town opens for the member test")
		await _teardown(scene)
		return
	town.select_entry(1)
	_confirm_through(town)
	var screen: Control = town.shop_screen
	_assert_true(screen != null, "the shop window opens")
	if screen == null:
		await _teardown(scene)
		return
	_assert_eq(screen.member_ids(), ["leonard", "hu"], "both carried members are listed")
	_assert_eq(str(screen.unit_id), "leonard", "the first member shows first")
	(screen.get_node("Bag_0") as Button).pressed.emit()
	_assert_true(screen.holding(), "Leonard's 長劍 is picked up")
	(screen.buttons["next"] as TextureButton).pressed.emit()
	_assert_true(str(screen.unit_id) == "hu" and not screen.holding(), "下一位 shows 琥 and puts the held item back")
	_assert_true((screen.get_node("Vitals") as Control).visible, "琥's strip shows (vitals error: %s)" % str(screen.vitals_error))
	(screen.goods_rows[1] as Button).pressed.emit()
	_assert_eq(scene.campaign_handoff["carry"]["units"]["hu"]["inventory"], [81, 0, 0, 0, 0, 0, 0, 0], "a goods click buys for the shown member")
	_assert_eq(scene.campaign_handoff["carry"]["units"]["leonard"]["inventory"], [1, 0, 0, 0, 0, 0, 0, 0], "the other member's bag is untouched")
	(screen.buttons["prev"] as TextureButton).pressed.emit()
	_assert_eq(str(screen.unit_id), "leonard", "上一位 steps back to Leonard")
	(screen.buttons["prev"] as TextureButton).pressed.emit()
	_assert_eq(str(screen.unit_id), "hu", "上一位 wraps round the party")
	screen.back()
	_assert_eq(str(town.mode), "menu", "right click／Esc (back) with nothing held closes the shop")
	await _teardown(scene)


func _run_exec_event_chain() -> void:
	## After level 1 the original arms 歐姆村 event 9; events 10 -> 11 -> 0 are the
	## finished chain (2000 gold). Arm 10 directly and walk the chain.
	var state := _fresh_state(1)
	(state["towns"]["1"] as Dictionary)["exec_event"] = 10
	var scene = await _boot(_carry(275, [0, 0, 0, 0, 0, 0, 0, 0]), state)
	var town = await _open_town(scene, 1)
	_assert_true(town != null, "town opens with an armed exec event")
	if town == null:
		await _teardown(scene)
		return
	_assert_eq(str(town.mode), "dialogue", "the armed exec event starts talking at once")
	_assert_eq(str(town.current_speaker), "村民", "teShapeMessage name id 656 = 村民")
	var seen := _confirm_through(town)
	_assert_true(seen.size() >= 5, "event 10 shows its messages and the gold grant (seen=%d)" % seen.size())
	_assert_true(seen.has("獲得 2000 金錢"), "teGetGold shows as a narration line")
	_assert_eq(str(town.mode), "menu", "the chain returns to the root menu")
	_assert_eq(int(town.party_gold()), 2275, "2000 gold granted")
	_assert_eq(int(scene.campaign_handoff["carry"]["loop"]["gold"]), 2275, "the grant persists into the carry")
	_assert_eq(int((scene.world_map_runtime.state["towns"]["1"] as Dictionary)["exec_event"]), 11, "teSetExecEvent arms event 11 on the map's state")
	_assert_eq(int((CampaignProgress.load_progress().get("world", {}) as Dictionary).get("towns", {}).get("1", {}).get("exec_event", -1)), 11, "the armed event persists in the saved world state")
	town.leave()
	await process_frame
	town = await _open_town(scene, 1)
	_assert_true(town != null and str(town.mode) == "dialogue", "re-entering runs the armed event 11")
	_confirm_through(town)
	_assert_eq(int((scene.world_map_runtime.state["towns"]["1"] as Dictionary)["exec_event"]), 0, "event 11 disarms the town")
	_assert_eq(str(town.mode), "menu", "back on the root menu")
	await _teardown(scene)


func _run_tavern_sub_menu() -> void:
	var scene = await _boot(_carry(300, [0, 0, 0, 0, 0, 0, 0, 0]), _fresh_state(4))
	var town = await _open_town(scene, 4)
	_assert_true(town != null, "米蘭多 opens from point 4")
	if town == null:
		await _teardown(scene)
		return
	_assert_eq(town.menu_codes(), [4, 5, 6, 7], "米蘭多 root menu (provisional initial tree)")
	town.select_entry(7)
	_assert_eq(str(town.mode), "dialogue", "the tavern greets first")
	_confirm_through(town)
	_assert_eq(str(town.mode), "sub_menu", "teCreateSubEventMenu opens the tavern menu")
	_assert_eq(str(town.summary()["pending_kind"]), "sub_menu", "summary reports the sub-menu")
	_assert_true(bool(town.summary()["menu_board_visible"]), "the tavern sub-menu lists its rows on the stone board")
	var first_row: Button = town._choice_root.get_node_or_null("Sub8")
	_assert_true(first_row != null and first_row.position == Vector2(72, 64), "sub-menu rows use the board's row origin")
	town.menu_pick(14)
	_assert_eq(str(town.mode), "dialogue", "the traveller talks")
	var seen := _confirm_through(town)
	_assert_true(seen.size() >= 10, "the traveller conversation has many lines (seen=%d)" % seen.size())
	_assert_eq(str(town.mode), "sub_menu", "the tavern menu re-opens after the child")
	_assert_eq(((town.run["state"]["towns"]["4"] as Dictionary)["tree"] as Dictionary)["7"], [8, 12, 13, 15], "teDeleteSelfTE / teAddSelfTE rewrote the tavern children in the running state")
	var reopened: Array = []
	for entry in (town.run["pending"] as Dictionary).get("entries", []):
		reopened.append(int(entry["code"]))
	_assert_eq(reopened, [8, 12, 13, 15], "the re-opened tavern menu lists the rewritten children")
	town.menu_exit()
	_assert_eq(str(town.mode), "menu", "leaving the tavern menu finishes the event")
	_assert_eq(((scene.world_map_runtime.state["towns"]["4"] as Dictionary)["tree"] as Dictionary)["7"], [8, 12, 13, 15], "the rewritten tree reached the map's world state")
	town.leave()
	await process_frame
	_assert_true(scene.world_map_runtime.town_runtime == null, "left 米蘭多")
	await _teardown(scene)


## After the 菲納斯河畔 ambush (level 901) is won — here through story_901's skip_battle
## world actions, the same writes WinfailScenarioRules would leave — 席達鎮 speaks
## exec event 25, its tavern lists the keeper (26) and the woman guest (27), and the
## chain 27 → 28 (妖精) → 30 (女客人二) reveals 薛維斯港 (point 11, track 10) and fills
## the port's menu tree: the route to the second half of the chapter.
func _run_ambush_victory_tavern_chain() -> void:
	var state := _fresh_state(6)
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/story_901.json"))
	var actions: Array = ((story.get("opening", {}) as Dictionary).get("skip_battle", {}) as Dictionary).get("world_actions", [])
	_assert_eq(actions.size(), 7, "story_901 carries WINFAIL901's seven win-section writes")
	var applied := TownEventRules.apply_script_town_actions(state, actions, TownEventRules.load_towndef(TOWNDEF_PATH))
	_assert_true(not applied.has("error"), "the ambush victory writes apply to a fresh 席達鎮 state")
	state = applied["state"]
	var scene = await _boot(_carry(300, [0, 0, 0, 0, 0, 0, 0, 0]), state)
	var town = await _open_town(scene, 6)
	_assert_true(town != null, "席達鎮 opens from point 6")
	if town == null:
		await _teardown(scene)
		return
	_assert_eq(str(town.mode), "dialogue", "exec event 25 (席達鎮事件後) talks at once")
	_assert_eq(str(town.current_speaker), "雷歐納德", "雷歐納德 speaks 1153")
	_assert_eq(str(town.summary()["dialogue_slot"]), "bottom", "a party line (tePlayerMessage) uses the bottom board, as in original frame 06")
	_assert_true(is_equal_approx(town._dialogue.position.y, 320.0), "the bottom board keeps BattleDialogue's bottom slot")
	_confirm_through(town)
	_assert_eq(str(town.mode), "menu", "back on the root menu")
	var codes: Array = town.menu_codes()
	_assert_true(codes.has(45) and not codes.has(17) and codes.has(20), "the root menu shows 護甲店二 (45) instead of 17 and keeps the tavern (20)")
	town.select_entry(20)
	_confirm_through(town)
	_assert_eq(str(town.mode), "sub_menu", "the tavern opens its menu")
	var entries: Array = []
	for entry in (town.run["pending"] as Dictionary).get("entries", []):
		entries.append(int(entry["code"]))
	_assert_eq(entries, [26, 27], "after the ambush the tavern lists 酒館老闆三 and 女客人")
	town.menu_pick(27)
	_confirm_through(town)
	_assert_eq(str(town.mode), "sub_menu", "the tavern menu re-opens after the woman guest")
	entries = []
	for entry in (town.run["pending"] as Dictionary).get("entries", []):
		entries.append(int(entry["code"]))
	_assert_true(entries.has(28), "event 27 adds 妖精 (28) to the tavern")
	town.menu_pick(28)
	var fairy := _confirm_through(town, 60)
	_assert_true(fairy.size() >= 10, "the fairy conversation has many lines (seen=%d)" % fairy.size())
	_assert_eq(str(town.mode), "sub_menu", "the tavern menu re-opens after the fairy")
	entries = []
	for entry in (town.run["pending"] as Dictionary).get("entries", []):
		entries.append(int(entry["code"]))
	_assert_eq(entries, [29, 30, 31], "event 28 rewrites the tavern to 老闆四 / 女客人二 / 妖精二")
	town.menu_pick(30)
	_confirm_through(town, 60)
	_assert_eq(str(town.mode), "sub_menu", "back on the tavern menu after 女客人二")
	var world: Dictionary = town.run["state"]
	var world_map := WorldMapRules.load_world_map(WORLD_MAP_PATH)
	_assert_true(not WorldMapRules.point_hidden(world, world_map, 11), "event 30 reveals 薛維斯港 (point 11)")
	_assert_true(not WorldMapRules.track_hidden(world, world_map, 10), "event 30 reveals track 10")
	_assert_eq(WorldMapRules.point_event(world, world_map, 9), 900, "event 30 arms 曼多力亞 with event 900")
	var port: Dictionary = (world.get("towns", {}) as Dictionary).get("11", {})
	_assert_eq((port.get("tree", {}) as Dictionary).get("0", []), [33, 34, 35, 36, 41], "薛維斯港's menu tree is filled: shops, tavern and 港口")
	_assert_eq(int(port.get("exec_event", 0)), 32, "第一次到薛維斯港 (32) is armed")
	town.menu_exit()
	town.leave()
	await process_frame
	await _teardown(scene)


## 席達鎮 event 30 (酒館女客人二) clears 曼多力亞→薛維斯港's Hidden bits and names
## 曼多力亞 with teBMSetShowTrackPoint: when the town closes the route reveals from
## there while the party still stands in 席達鎮, and 薛維斯港 appears at its end.
func _run_town_reveals_map() -> void:
	var world_map := WorldMapRules.load_world_map(WORLD_MAP_PATH)
	var towns := TownEventRules.initial_town_state(TownEventRules.load_towndef(TOWNDEF_PATH), TownEventRules.load_initial_trees(TREES_PATH))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCENE_PATH))
	var state := WorldMapRules.initial_state(world_map, 6, towns, config.get("new_game", {}))
	state["secret_roll"] = 100
	(state["towns"]["6"] as Dictionary)["exec_event"] = 30
	_assert_true(WorldMapRules.point_hidden(state, world_map, 11) and WorldMapRules.track_hidden(state, world_map, 10), "薛維斯港 and track 10 start Hidden in a new game")
	var scene = await _boot(_carry(100, [0, 0, 0, 0, 0, 0, 0, 0]), state)
	var map = scene.world_map_runtime
	await _settle_reveals(map)
	var town = await _open_town(scene, 6)
	_assert_true(town != null, "席達鎮 opens with event 30 armed")
	if town == null:
		await _teardown(scene)
		return
	var seen := _confirm_through(town)
	_assert_true(seen.size() >= 8, "the tavern conversation plays its lines (seen=%d)" % seen.size())
	_assert_eq(str(town.mode), "menu", "event 30 ends on the town menu")
	_assert_eq(int((map.state["towns"]["11"] as Dictionary).get("exec_event", 0)), 32, "teSetTownExecEvent armed 薛維斯港's event 32 in the map's world state")
	_assert_eq(map.state.get("show_track_points", []), [9], "teBMSetShowTrackPoint queued 曼多力亞 for the map")
	_assert_true(map.summary().get("revealing_track_count", 0) == 0 and not WorldMapRules.track_shown(map.state, world_map, 10), "nothing reveals while the town screen is open")
	town.leave()
	await process_frame
	_assert_true(map.town_runtime == null, "left 席達鎮")
	_assert_true(not WorldMapRules.point_hidden(map.state, world_map, 11) and not WorldMapRules.track_hidden(map.state, world_map, 10), "the town event cleared the Hidden bits of 薛維斯港 and track 10")
	# The walker (0x427420) takes the request after the routes underfoot: the camera glides to
	# 曼多力亞, track 10 reveals there, the camera glides back; clicks are dropped meanwhile.
	_assert_true(bool(map.summary().get("reveal_busy", false)) and str(map.summary().get("show_phase", "")) in ["to_point", "revealing"], "closing the town starts the show-track sequence for 曼多力亞 (phase %s)" % str(map.summary().get("show_phase", "")))
	_assert_eq(WorldMapRules.marker_kind(map.state, world_map, 9), WorldMapRules.MARKER_KIND_GENERAL, "曼多力亞 now carries event 900 as a General point")
	await _settle_reveals(map)
	_assert_eq(map.state.get("show_track_points", []), [], "the sequence consumed the teBMSetShowTrackPoint request")
	_assert_true(WorldMapRules.point_shown(map.state, world_map, 11) and map.point_nodes.has(11), "薛維斯港 is shown once the route finishes revealing")
	_assert_eq(int(WorldMapRules.track_mode(map.state, world_map, 10)), WorldMapRules.MODE_SHOWN, "track 10 settles to the shown phase")
	await _teardown(scene)


func _run_next_level_exit() -> void:
	## 席達鎮 event 23 ends with teSetNextPlayLevelEvent 6,6; level 6 is registered
	## (the formal battle_006.json), so the town closes into a campaign hand-off
	## instead of the map's not-remade card.
	var state := _fresh_state(6)
	(state["towns"]["6"] as Dictionary)["exec_event"] = 23
	var scene = await _boot(_carry(100, [0, 0, 0, 0, 0, 0, 0, 0]), state)
	var town = await _open_town(scene, 6)
	_assert_true(town != null, "席達鎮 opens with event 23 armed")
	if town == null:
		await _teardown(scene)
		return
	_confirm_through(town)
	await process_frame
	var map = scene.world_map_runtime
	_assert_true(map.town_runtime == null, "teSetNextPlayLevelEvent closes the town")
	_assert_eq(str(map._card_kind), "", "a registered level shows no card")
	var kinds: Array[String] = []
	for record in map.town_records:
		kinds.append(str(record["kind"]))
	_assert_true(kinds.has("level_requested"), "the map recorded the level request")
	_assert_true(CampaignProgress.has_pending(), "the level request hands off to the registered scenario")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/battle_006.json", "席達鎮's tavern event enters the level-6 battle")
	_assert_eq(int((CampaignProgress.pending.get("world", {}) as Dictionary).get("current_point", 0)), 6, "the hand-off carries the party at point 6")
	CampaignProgress.pending = {}
	await _teardown(scene)

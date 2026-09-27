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
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
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
		_assert_true(screen.buttons.has(key) and not (screen.buttons[key] as TextureButton).disabled, "%s acts (0x42a330 mode 1: 裝備／買賣／倉庫 set the page, 丟棄 drops the hand)" % key)
	for key in ["prev", "next"]:
		_assert_true(screen.buttons.has(key) and not (screen.buttons[key] as TextureButton).disabled, "%s works" % key)
	_assert_eq(screen.buttons.size(), 6, "only the original six status buttons (no remake 離開)")
	_assert_true(not screen.get_node("Description").visible, "the WINDOW50 description only shows on hover")


func _run() -> void:
	_run_party_rules()
	await _run_shop()
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
	# Buying: a goods click pays and puts the item on the hand (0x41553c); a bag click puts it down.
	(screen.goods_rows[0] as Button).pressed.emit()
	var bought: Dictionary = town.records[town.records.size() - 1].get("result", {})
	_assert_true(bool(bought.get("ok", false)), "clicking 長劍 (200) buys it")
	_assert_eq(int(town.party_gold()), 75, "gold after buying")
	_assert_eq(screen.summary()["holding"], {"loose": true, "code": 1}, "the bought 長劍 is on the hand")
	_assert_true(not screen.message_visible(), "a purchase raises no message board (original: only refusals do)")
	(screen.get_node("Bag_5") as Button).pressed.emit()
	_assert_eq(scene.campaign_handoff["carry"]["units"]["leonard"]["inventory"], [1, 1, 0, 0, 0, 0, 0, 0], "the purchase lands in the carried inventory")
	_assert_eq(int(scene.campaign_handoff["carry"]["loop"]["gold"]), 75, "the runtime hand-off carry follows the purchase")
	_assert_eq(int((CampaignProgress.load_progress().get("carry", {}) as Dictionary).get("loop", {}).get("gold", -1)), 75, "the saved progress persists the new gold")
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
	_assert_eq(screen.summary()["holding"], {"loose": true, "code": 1}, "clicking a bag item lifts it out of the bag (0x436e80)")
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

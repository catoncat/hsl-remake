extends Control
## The original's shared status window (0x42ab40) in its two modes: mode 1 is the town shop,
## mode 0 the 整理裝備 window (world scroll item 0 and actEnterStorageWindow — hosted by
## PartyEquipmentScreen; see the mode 0 notes below).
##
## Town shop window in the original composition. The original shop is the status window in
## shop mode (0x414c00 with window flag bit 2, docs/evidence_packets/static_reverse/
## original_shop_transaction.md) — the same boards as the 獲得物品 window (BattleLootPanel):
## the member's WINDOW10 strip on top, the member's bag in WINDOW20, the goods in WINDOW90
## under the shop name, the `$:` WINDOW40 box, a WINDOW50 description on hover and the
## status buttons 上一位／下一位／裝備／買賣／倉庫／丟棄; the big map shows in the gaps.
## Original frames: docs/evidence_packets/runtime_observations/original_world_town/README.md
## (08–14).
##
## Presentation only: every transaction is the host's (TownRuntime.shop_buy／shop_sell through
## WorldPartyRules); this node keeps the shown member, the list scroll and one uncommitted held
## bag item. The vitals strip reads a sandbox PlayLoop built from the carry (the
## PartyEquipmentScreen path); without one the strip stays hidden and `vitals_error` says why.
##
## Remake readings: a goods click buys straight into the shown member's first empty slot (the
## original puts the paid item on the cursor for the player to place — WorldPartyRules'
## remake policy); selling follows the original gesture (pick a bag item up, click the goods
## list). 裝備／倉庫／丟棄 stay dimmed (no town equip mode, party storage or town discard in the
## remake); as in the original the window has no 離開 button — right click／Esc leave it (frame
## 13). The ↓ mark the original draws after some goods names is not drawn —
## what it compares is not read.
##
## Mode 0 (整理裝備, docs/evidence_packets/static_reverse/original_storage_window.md): the same
## boards; the root opens on page 4 (狀態) and the nine buttons 上一位／下一位／倉庫／狀態／
## 丟棄／使用／裝備／魔法／特殊技 show by page (0x42a330 flags). The left board is the page's:
## 狀態 attributes (page 4), the bag (裝備 10／倉庫 7), the magic or special list (2／3); the
## right board is the six equipment slots on every page but 倉庫. Only on the 裝備 page do the
## slots take the hand: an empty hand takes an item off, a held bag item goes on by its kind.
## The window keeps no rules: equip／unequip go to the host (equip_requested／
## unequip_requested → PartyEquipmentRules.change) and come back through show_loop. Remake
## readings: 倉庫 stays dimmed (no party storage), so 丟棄／使用 (storage page only) never
## show; a taken-off item goes to the bag (the rules' unequip) instead of the hand; a refused
## item stays in the hand silently as in the original (0x436f30 returns −1) and the reason
## is only kept for summary(). Original frames of the 狀態／裝備／倉庫 pages:
## docs/evidence_packets/runtime_observations/original_world_town/README.md (15–17).
## provenance:
##   rules: n/a
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md; static-derived docs/evidence_packets/static_reverse/original_storage_window.md (mode 0 boards, nine buttons at y 429 x 272／320／389／457／389／437／505／553／601, page flags, equipment slot hand rules); runtime-measured docs/evidence_packets/runtime_observations/original_world_town/README.md (boards over the undimmed big map; buttons at y 429; price right edge x 594; hover description); remake-invented (dimmed 裝備／倉庫／丟棄; no ↓ mark; mode 0: dimmed 倉庫, magic／special lists on the plain WINDOW20 board — the original's shape-table boards 5／10 are not read)
##   strings: resource-derived content/imported/hsl/chapter01/source_texts/RESOURCE.TXT; resource-derived content/imported/hsl/global/world_map/town_messages.json; remake-invented (tooltips of the dimmed buttons)
##   timing: n/a
##   audio: n/a
signal buy_requested(item_id: int, unit_id: String)
signal sell_requested(unit_id: String, slot: int)
signal close_requested
## Mode 0: the host runs PartyEquipmentRules.change and answers with show_loop or refuse.
signal equip_requested(unit_id: String, inventory_index: int, code: int)
signal unequip_requested(unit_id: String, slot: String)

const UISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const Loot = preload("res://game/battle/scene/BattleLootPanel.gd")
const Vitals = preload("res://game/battle/scene/BattleVitals.gd")
const EquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const ItemText = preload("res://game/battle/scene/BattleItemText.gd")
const EquipmentCatalog = preload("res://game/battle/runtime/EquipmentCatalog.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const PlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const PartyEquipmentRules = preload("res://game/sim/PartyEquipmentRules.gd")
const JobStats = preload("res://game/sim/JobStatsRules.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const PartyRules = preload("res://game/world/WorldPartyRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
const Growth = preload("res://game/battle/scene/BattleGrowthPanel.gd")

## 0x42ab40 param_1; the page is the root's +0x94 (Data6 of the button that set it).
const MODE_ARRANGE := 0
const MODE_SHOP := 1
const PAGE_MAGIC := 2
const PAGE_SPECIAL := 3
const PAGE_STATUS := 4
const PAGE_STORAGE := 7
const PAGE_EQUIP := 10
const PAGE_TRADE := 11

## Frames 08／12 (weapon and armour shops): every price's glyphs end at x 594 — ten pixels
## right of the loot window's count column (Loot.COUNT_RIGHT, x 584); the cell ends there.
const PRICE_RIGHT := 342
## Frames 08／12: the six status buttons' red frames span x 263–304, 311–352, 376–417, 424–465,
## 472–513 and 568–609 over y 408–449 (42×42 icons centred on these points); the cell between
## 倉庫 and 丟棄 stays empty (0x42ab40 mode 1 adds only these six). The fifth column is the
## button's +0x98 flags (0x42a330: -1 always; bit 31 clear → only on that page; set → hidden
## on page flags & 0x7fffffff).
const BUTTON_Y := 429
const BUTTONS := [
	["prev", "B_PREV1", "上一位", 284, -1],
	["next", "B_NEXT1", "下一位", 332, -1],
	["equip", "BCMD07_1", "裝備", 397, -1],
	["trade", "BCMD06_1", "買賣", 445, -1],
	["storage", "BCMD15_1", "倉庫", 493, 0x80007fff],
	["drop", "BCMD08_1", "丟棄", 589, -1],
]
## 0x42ab40 mode 0, in its creation order (templates 724／729／731／728／730／733／734／726／727,
## captions = obj_Data9 RESOURCE 133／134／309／40／26／23／25／28／29).
const ARRANGE_BUTTONS := [
	["prev", "B_PREV1", "上一位", 272, -1],
	["next", "B_NEXT1", "下一位", 320, -1],
	["storage", "BCMD15_1", "倉庫", 389, 0x80000007],
	["status", "BCMD13_1", "狀態", 457, 0x80000007],
	["drop", "BCMD08_1", "丟棄", 389, 7],
	["use", "BCMD05_1", "使用", 437, 7],
	["equip", "BCMD07_1", "裝備", 505, -1],
	["magic", "BCMD09_1", "魔法", 553, -1],
	["special", "BCMD10_1", "特殊技", 601, -1],
]
const ARRANGE_PAGES := {"storage": PAGE_STORAGE, "status": PAGE_STATUS, "equip": PAGE_EQUIP, "magic": PAGE_MAGIC, "special": PAGE_SPECIAL}
const DIMMED_BUTTONS := {
	"equip": "重製版商店不切換到裝備畫面；請用大地圖的「整理裝備」",
	"trade": "",
	"storage": "重製版沒有隊伍倉庫",
	"drop": "重製版商店不丟棄物品",
}
const ARRANGE_DIMMED := {
	"storage": "重製版沒有隊伍倉庫",
	"drop": "重製版沒有隊伍倉庫",
	"use": "重製版沒有隊伍倉庫",
}
## Mode 0 right board: WINDOW30 at (252,168) (0x428410 case 3); the slot rows are the status
## page's (BattleEquipmentView, board at y 174) moved up with the board.
const EQUIPMENT_AT := Vector2(252, 168)
## Mode 0 magic／special lists: 28 px rows (0x4289e0 +0x98 = 0x1c), nine visible.
const SKILL_ROW := 28
const SKILL_ROWS := 9
## Frame 12 (armour shop, 70 gold, 布衣 $80): the message board is BOARD02 (489×145) at
## (75,320) with the line centred in it.
const MESSAGE_BOARD_AT := Vector2(75, 320)
const MESSAGE_BOARD_SIZE := Vector2(489, 145)

var mode := MODE_SHOP
var page := PAGE_TRADE
var last_refusal := ""
var title := ""
var goods: Array[int] = []
var carry: Dictionary = {}
var speakers: Dictionary = {}
var shop_catalog: Dictionary = {}
var unit_id := ""
var vitals_error := ""
var message := ""
var message_color := UISkin.TEXT_WHITE
var buttons: Dictionary = {}
var goods_rows: Array[Button] = []
var bag_slots: Array[Button] = []
var description_box: Control
var hand_icon: TextureRect
var _hand: Dictionary = {}
var _scroll := 0
var _loop: Dictionary = {}
var _items: Dictionary = {}
var _pointer := Vector2.ZERO


func _ready() -> void:
	name = "TownShop"
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The held item follows the cursor (0x414c00 draws it after the window).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and visible:
		_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if hand_icon != null and hand_icon.visible:
			hand_icon.position = _pointer - hand_icon.get_meta("origin", Vector2.ZERO)


## Opens over a shop: `scenario_path` names the carry's source battle for the vitals sandbox.
## The sandbox member records are the opening carry's; the bag and gold always read `carry`.
func open(shop_title: String, shop_goods: Array[int], next_carry: Dictionary, shop_speakers: Dictionary, catalog: Dictionary, scenario_path: String) -> void:
	mode = MODE_SHOP
	page = PAGE_TRADE
	title = shop_title
	goods = shop_goods.duplicate()
	speakers = shop_speakers
	shop_catalog = catalog
	_items = EquipmentCatalog.items()
	_scroll = 0
	unit_id = ""
	# The strip, the row colours (job) and the consumable texts do not change with a purchase
	# or a sale: one sandbox per opening.
	_loop = {}
	vitals_error = ""
	if scenario_path == "":
		vitals_error = "unknown_source_scenario"
	else:
		var box := PartyEquipmentRules.sandbox(PlayLoop.create([], "", BattleScenario.load_file(scenario_path)), next_carry)
		if bool(box["ok"]):
			_loop = box["loop"]
		else:
			vitals_error = str(box["error"])
	show_carry(next_carry, "")


## Redraws for a new carry (after every transaction); `next_message` is the board line to show
## in `next_color` (the host's: RESOURCE 606 is coded @2 red, 607 @5 yellow).
func show_carry(next_carry: Dictionary, next_message: String, next_color: Color = UISkin.TEXT_WHITE) -> void:
	carry = next_carry.duplicate(true)
	message = next_message
	message_color = next_color
	_hand = {}
	var ids := member_ids()
	if not ids.has(unit_id):
		unit_id = "" if ids.is_empty() else str(ids[0])
	_rebuild()


## Mode 0 over the host's sandbox `loop` (PartyEquipmentScreen); `next_carry` only feeds the
## money box; `next_message` is the host's failure line (no sandbox). Opens on page 4.
func open_arrange(next_carry: Dictionary, loop: Dictionary, next_message: String = "") -> void:
	mode = MODE_ARRANGE
	page = PAGE_STATUS
	title = ""
	goods = []
	shop_catalog = {}
	_items = EquipmentCatalog.items()
	_scroll = 0
	unit_id = ""
	vitals_error = ""
	show_loop(next_carry, loop, next_message)


## Mode 0 redraw after an equipment change; the hand empties.
func show_loop(next_carry: Dictionary, loop: Dictionary, next_message: String = "") -> void:
	carry = next_carry.duplicate(true)
	_loop = loop
	message = next_message
	message_color = UISkin.TEXT_WHITE
	_hand = {}
	last_refusal = ""
	var ids := member_ids()
	if not ids.has(unit_id):
		unit_id = "" if ids.is_empty() else str(ids[0])
	_rebuild()


## Mode 0 page change (the button's Data6); a held item stays in the hand (0x42a330).
func set_page(next_page: int) -> void:
	page = next_page
	_rebuild()


## Mode 0: show `next_unit_id` (the host's select_member).
func show_member(next_unit_id: String) -> void:
	if member_ids().has(next_unit_id):
		_hand = {}
		unit_id = next_unit_id
		_rebuild()


## Mode 0, 裝備 page: a click on equipment slot `slot` — a held bag item goes on (its kind picks
## the slot, 0x436f30), an empty hand takes the slot's item off (0x437020).
func click_equipment(slot: String) -> void:
	if mode != MODE_ARRANGE or page != PAGE_EQUIP or message_visible() or unit_id == "":
		return
	if holding():
		equip_requested.emit(unit_id, int(_hand["slot"]), int(_hand["code"]))
	elif _worn_code(slot) > 0:
		unequip_requested.emit(unit_id, slot)


## Mode 0: the host refused the held item; it stays in the hand (no board, no sound).
func refuse(reason: String) -> void:
	last_refusal = reason


func _worn_code(slot: String) -> int:
	for item in _actor().get("equipment", []):
		if str(item["slot"]) == slot:
			return int(item["item_code"])
	return 0


static func _shown_on(flags: int, on_page: int) -> bool:
	if flags == -1 or flags == 0:
		return true
	if flags & 0x80000000:
		return on_page != (flags & 0x7fffffff)
	return on_page == flags


func member_ids() -> Array:
	if mode == MODE_ARRANGE:
		return [] if _loop.is_empty() else PartyEquipmentRules.members(_loop).map(func(unit): return str(unit["id"]))
	return PartyRules.members(carry, speakers).map(func(member): return str(member["unit_id"]))


func holding() -> bool:
	return not _hand.is_empty()


func message_visible() -> bool:
	return message != ""


## 上一位／下一位 (step -1／+1) cycle the shown member; a held item goes back first.
func step_member(step: int) -> void:
	var ids := member_ids()
	if ids.is_empty():
		return
	_hand = {}
	unit_id = str(ids[posmod(ids.find(unit_id) + step, ids.size())])
	_rebuild()


## Original right click／Esc order: close the message, else put the held item back, else leave.
func back() -> void:
	if message_visible():
		dismiss_message()
	elif holding():
		put_back()
	else:
		close_requested.emit()


func dismiss_message() -> void:
	message = ""
	_rebuild()


func put_back() -> void:
	_hand = {}
	_rebuild()


## Picks the bag item in `slot` of the shown member up (the original's first half of a sale).
func pick_up(slot: int) -> void:
	var inventory: Array = _member().get("inventory", [])
	if message_visible() or slot < 0 or slot >= inventory.size() or int(inventory[slot]) <= 0:
		return
	_hand = {"unit_id": unit_id, "slot": slot, "code": int(inventory[slot])}
	_rebuild()


## Dropping the held item on the goods list sells it (0x414c00 shop branch).
func drop_on_list() -> void:
	if holding():
		var hand := _hand
		_hand = {}
		sell_requested.emit(str(hand["unit_id"]), int(hand["slot"]))


func _member() -> Dictionary:
	if mode == MODE_ARRANGE:
		return _actor()
	for member in PartyRules.members(carry, speakers):
		if str(member["unit_id"]) == unit_id:
			return member
	return {}


func _actor() -> Dictionary:
	return {} if _loop.is_empty() or unit_id == "" else PlayLoop.unit(_loop, unit_id)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	goods_rows.clear()
	bag_slots.clear()
	buttons.clear()
	var vitals := Vitals.new()
	vitals.name = "Vitals"
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	var actor := _actor()
	vitals.visible = not actor.is_empty()
	if not actor.is_empty():
		vitals.show_unit(actor)
	if mode == MODE_SHOP:
		_build_bag()
		_build_goods()
	else:
		match page:
			PAGE_STATUS: _build_attributes()
			PAGE_MAGIC, PAGE_SPECIAL: _build_skills()
			_: _build_bag()
		if page != PAGE_STORAGE:
			_build_equipment()
	UISkin.board(self, "WINDOW40", Loot.MONEY_AT).name = "MoneyBoard"
	var amount := UISkin.text(self, Loot.MONEY_AT + Vector2(80, 4), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(108, 24))
	amount.name = "Money"
	amount.text = str(int((carry.get("loop", {}) as Dictionary).get("gold", 0)))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for spec in (BUTTONS if mode == MODE_SHOP else ARRANGE_BUTTONS):
		if _shown_on(int(spec[4]), page):
			_status_button(spec[0], spec[1], spec[2], spec[3])
	description_box = Control.new()
	description_box.name = "Description"
	description_box.position = Loot.DESCRIPTION_AT
	description_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.board(description_box, "WINDOW50", Vector2.ZERO)
	description_box.hide()
	add_child(description_box)
	if message_visible():
		_build_message()
	hand_icon = TextureRect.new()
	# GameCursor hides the sceptre while this held item shows (0x430310).
	hand_icon.add_to_group("game_cursor_held_items")
	hand_icon.name = "Hand"
	hand_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hand_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_icon.hide()
	add_child(hand_icon)
	if holding():
		var key := str(_items[str(int(_hand["code"]))]["icon"])
		var origin: Array = UISkin.data()["assets"][key]["draw_origin"]
		UISkin.show_shape(hand_icon, UISkin.texture(key))
		hand_icon.set_meta("origin", Vector2(float(origin[0]), float(origin[1])))
		hand_icon.position = _pointer - hand_icon.get_meta("origin")
		hand_icon.show()


func _build_bag() -> void:
	UISkin.board(self, "WINDOW20", Loot.BAG_AT).name = "BagBoard"
	var inventory: Array = _member().get("inventory", [])
	for index in range(inventory.size()):
		var code := int(inventory[index])
		var shown := code > 0 and not (holding() and int(_hand["slot"]) == index)
		var button := _row_button(Loot.BAG_AT + Vector2(8, 8 + index * Loot.BAG_ROW), Vector2(208, Loot.BAG_ROW))
		button.name = "Bag_%d" % index
		if shown:
			var details: Dictionary = _items[str(code)]
			UISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 8))
			var label := UISkin.text(button, Vector2(48, 0), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(160, Loot.BAG_ROW))
			label.text = str(details["name"])
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
		button.pressed.connect(func():
			if message_visible(): return
			if holding(): put_back()
			elif shown: pick_up(index))
		bag_slots.append(button)


func _build_goods() -> void:
	UISkin.board(self, "WINDOW90", Loot.LIST_AT).name = "GoodsBoard"
	var heading := UISkin.text(self, Loot.LIST_AT + Vector2(0, 10), UISkin.TEXT_IVORY, UISkin.FONT_BODY, Vector2(375, 24))
	heading.name = "ShopTitle"
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# While an item is held the whole list area takes the drop (rows included).
	var drop_area := _row_button(Loot.LIST_AT + Vector2(8, Loot.LIST_TOP), Vector2(340, Loot.LIST_ROW * Loot.VISIBLE_ROWS))
	drop_area.name = "GoodsDrop"
	drop_area.pressed.connect(func(): if not message_visible(): drop_on_list())
	_scroll = clampi(_scroll, 0, maxi(0, goods.size() - Loot.VISIBLE_ROWS))
	var job := int(_actor().get("growth_profile", {}).get("job_code", -1))
	for index in range(mini(Loot.VISIBLE_ROWS, goods.size() - _scroll)):
		var code := goods[_scroll + index]
		var details: Dictionary = _items[str(code)]
		var button := _row_button(Loot.LIST_AT + Vector2(8, Loot.LIST_TOP + index * Loot.LIST_ROW), Vector2(340, Loot.LIST_ROW))
		button.name = "Goods%d" % code
		UISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 6))
		var color := _row_color(details, job)
		var label := UISkin.text(button, Vector2(48, 0), color, UISkin.FONT_BODY, Vector2(168, Loot.LIST_ROW))
		label.text = str(details["name"])
		label.set_meta("base_color", color)
		var price := UISkin.text(button, Vector2(PRICE_RIGHT - 8 - 108, 0), color, UISkin.FONT_BODY, Vector2(108, Loot.LIST_ROW))
		price.text = "$%d" % _cost(code)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.mouse_entered.connect(_show_description.bind(code, label))
		button.mouse_exited.connect(_hide_description.bind(label))
		button.pressed.connect(func():
			if message_visible(): return
			if holding(): drop_on_list()
			else: buy_requested.emit(code, unit_id))
		goods_rows.append(button)
	if goods.size() > Loot.VISIBLE_ROWS:
		for step in [-1, 1]:
			var arrow := _row_button(Loot.LIST_AT + Vector2(351, 0 if step < 0 else 200), Vector2(24, 20))
			arrow.name = "Scroll_up" if step < 0 else "Scroll_down"
			arrow.pressed.connect(func():
				_scroll = clampi(_scroll + step, 0, goods.size() - Loot.VISIBLE_ROWS)
				_rebuild())


## Mode 0 page 4: the status page's attribute column (WINDOW21, BattleGrowthPanel rows) on the
## left board's (12,168).
func _build_attributes() -> void:
	var at := Loot.BAG_AT
	UISkin.asset(self, "WINDOW21", at).name = "AttributeBoard"
	var unit := _actor()
	if unit.is_empty():
		return
	var profile := Combat.combat_profile_from_unit(unit)
	var values := [int(profile["str"]), int(profile["dex"]), int(profile["mind"]), int(profile["con"]), int(profile["live_attack_damage"]), int(profile["live_defense"]), "%d%%" % int(profile["live_magic_attack"]), int(unit["live_speed"]), int(unit["move_point"])]
	for index in range(values.size()):
		var value := UISkin.text(self, Vector2(Growth.ATTRIBUTE_VALUE_X if index < 4 else Growth.DERIVED_VALUE_X, at.y + 8 + index * Growth.ROW_HEIGHT), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(60, Growth.GLYPH_ROW))
		value.name = "Attribute_%d" % index
		value.text = str(values[index])


## Mode 0 pages 2／3: the member's magic or special list, 28 px rows (0x4289e0).
func _build_skills() -> void:
	UISkin.board(self, "WINDOW20", Loot.BAG_AT).name = "SkillBoard"
	if unit_id == "" or _loop.is_empty():
		return
	var options: Array = PlayLoop.magic_options(_loop, unit_id) if page == PAGE_MAGIC else PlayLoop.special_options(_loop, unit_id)
	for index in range(mini(options.size(), SKILL_ROWS)):
		var row := UISkin.text(self, Loot.BAG_AT + Vector2(48, 8 + index * SKILL_ROW), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(160, SKILL_ROW))
		row.name = "Skill_%d" % index
		row.text = str(options[index]["name"])


## Mode 0 right board: WINDOW30 with the six slots (two columns × three rows); hovering shows
## the item's description, a click goes to click_equipment (acts on the 裝備 page only).
func _build_equipment() -> void:
	UISkin.board(self, "WINDOW30", EQUIPMENT_AT).name = "EquipmentBoard"
	var origin := EQUIPMENT_AT
	for index in range(EquipmentView.SLOTS.size()):
		var slot: String = EquipmentView.SLOTS[index]
		var column := index % 2
		var row := floori(index / 2.0)
		var at: Vector2 = origin + Vector2(EquipmentView.SLOT_LEFTS[column], EquipmentView.LABEL_ROW_CENTERS[row] - EquipmentView.SLOT_SIZE.y / 2.0)
		var button := _row_button(at, EquipmentView.SLOT_SIZE)
		button.name = "Slot_" + slot
		var code := _worn_code(slot)
		if code > 0:
			var details: Dictionary = _items[str(code)]
			var anchor: Vector2 = origin + EquipmentView.ICON_ANCHORS[column] + Vector2(0, EquipmentView.ICON_ROW_PITCH * row) - at
			UISkin.anchored_asset(button, str(details["icon"]), anchor)
			var label := UISkin.text(button, Vector2(EquipmentView.COLON_ENDS[column] + EquipmentView.NAME_GAP - EquipmentView.SLOT_LEFTS[column], 0), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(150, EquipmentView.SLOT_SIZE.y))
			label.name = "Name"
			label.text = str(details["name"])
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
		button.pressed.connect(click_equipment.bind(slot))


## 0x414c00 row colour (shared with the loot list): important @6, usable by the member's job
## @1, otherwise @2. A member without a sandbox job shows every row usable.
static func _row_color(details: Dictionary, job: int) -> Color:
	if bool(details["important"]):
		return UISkin.TEXT_IVORY
	if job < 0 or (JobStats.has_job(job) and (int(details["job_mask"]) & JobStats.job_mask_bit(job)) != 0):
		return UISkin.TEXT_WHITE
	return UISkin.TEXT_RED


func _cost(code: int) -> int:
	return int((shop_catalog.get(str(code), {}) as Dictionary).get("cost", 0))


func _status_button(key: String, resource: String, caption: String, centre_x: int) -> void:
	var button := TextureButton.new()
	button.name = "Button_" + key
	button.texture_normal = load(UISkin.ROOT + resource + ".SHP.png")
	button.position = Vector2(centre_x - 21, BUTTON_Y - 21)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(button)
	# 0x43a640: 15 px caption centred under the icon at centre_y + 13, yellow while hovered.
	var label := UISkin.text(self, Vector2(centre_x - 40, BUTTON_Y + 13), UISkin.TEXT_WHITE, UISkin.FONT_SMALL, Vector2(80, 16))
	label.name = "Caption_" + key
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var dimmed_table: Dictionary = DIMMED_BUTTONS if mode == MODE_SHOP else ARRANGE_DIMMED
	var dimmed := dimmed_table.has(key)
	# 0x42a330 marks the button whose Data6 is the current page (+0x10000000); the original
	# frames draw it dark (mode 0 狀態／裝備 pages, 2026-09-27; the shop's 買賣, frame 08).
	var current := mode == MODE_ARRANGE and int(ARRANGE_PAGES.get(key, -1)) == page
	button.disabled = dimmed
	button.self_modulate = Color(0.45, 0.45, 0.45) if dimmed or current else Color.WHITE
	button.tooltip_text = str(dimmed_table.get(key, ""))
	if not dimmed:
		button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", UISkin.TEXT_YELLOW))
		button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", UISkin.TEXT_WHITE))
	match key:
		"prev": button.pressed.connect(func(): if not message_visible(): step_member(-1))
		"next": button.pressed.connect(func(): if not message_visible(): step_member(1))
		_:
			if mode == MODE_ARRANGE and ARRANGE_PAGES.has(key) and not dimmed:
				button.pressed.connect(func(): if not message_visible(): set_page(int(ARRANGE_PAGES[key])))
	buttons[key] = button


## The refusal board: BOARD02 over the window, the line centred; any click closes it.
func _build_message() -> void:
	var blocker := _row_button(Vector2.ZERO, size)
	blocker.name = "MessageBlocker"
	blocker.pressed.connect(dismiss_message)
	UISkin.board(self, "BOARD02", MESSAGE_BOARD_AT).name = "MessageBoard"
	var line := UISkin.text(self, MESSAGE_BOARD_AT, message_color, UISkin.FONT_BODY, Vector2(MESSAGE_BOARD_SIZE.x, MESSAGE_BOARD_SIZE.y))
	line.name = "MessageText"
	line.text = message
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _row_button(at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(button)
	return button


## Hovering a bag or goods row greens its name and shows WINDOW50 over the buttons (0x436d70);
## the shop adds the 賣價 line (RESOURCE 608).
func _show_description(code: int, label: Label) -> void:
	if holding() or message_visible():
		return
	label.add_theme_color_override("font_color", UISkin.TEXT_GREEN)
	for child in description_box.get_children():
		if child is Label:
			description_box.remove_child(child)
			child.queue_free()
	var lines := description_lines(code)
	for index in range(mini(lines.size(), 4)):
		var row := UISkin.text(description_box, Vector2(8, 12 + index * 16), UISkin.TEXT_GREEN if index == 0 else UISkin.TEXT_WHITE, UISkin.FONT_SMALL, Vector2(360, 16))
		row.text = str(lines[index])
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_box.show()


func _hide_description(label: Label) -> void:
	label.add_theme_color_override("font_color", label.get_meta("base_color", UISkin.TEXT_WHITE))
	description_box.hide()


func description_lines(code: int) -> Array:
	var details: Dictionary = _items[str(code)]
	var lines: Array = []
	if int(details["type_code"]) in range(2, 7):
		lines.append_array(EquipmentView.description_lines(details))
	else:
		lines.append_array([str(details["name"]), "可使用"])
		var definition: Dictionary = (_loop.get(LoopKeys.CONSUMABLES, {}) as Dictionary).get(str(code), {})
		if not definition.is_empty():
			lines.append_array(ItemText.description(definition).split("\n"))
	lines = lines.filter(func(line): return str(line) != "")
	if mode == MODE_ARRANGE:
		return lines.slice(0, 4)
	if lines.size() > 3:
		lines = lines.slice(0, 3)
	lines.append("賣價$%d" % PartyRules.sell_price(_cost(code)))
	return lines


func summary() -> Dictionary:
	return {
		"mode": mode,
		"page": page,
		"buttons": buttons.keys(),
		"last_refusal": last_refusal,
		"unit_id": unit_id,
		"members": member_ids(),
		"holding": _hand.duplicate(),
		"message": message,
		"vitals_error": vitals_error,
		"scroll": _scroll,
	}

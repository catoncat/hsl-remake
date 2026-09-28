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
## An empty-handed goods click pays and puts the item on the hand (TownRuntime.shop_pick,
## 0x415519-0x41553c: gold at once, 0x4c1ce4 = code, no message); the player puts it down on a
## bag slot (0x42923b) or right click puts it into the shown member's first empty slot
## (0x436e30). Selling follows the original gesture (pick a bag item up, click the goods
## list). 裝備 (page 10) shows the member's six slots and takes the hand like mode 0; 倉庫
## (page 7) shows the party storage; 丟棄 throws a non-important held item away; as in the
## original the window has no 離開 button — right click／Esc leave it (frame 13). The ↓ mark the original draws after some goods names is not drawn —
## what it compares is not read.
##
## Mode 0 (整理裝備, docs/evidence_packets/static_reverse/original_storage_window.md): the same
## boards; the root opens on page 4 (狀態) and the nine buttons 上一位／下一位／倉庫／狀態／
## 丟棄／使用／裝備／魔法／特殊技 show by page (0x42a330 flags). The left board is the page's:
## 狀態 attributes (page 4), the bag (裝備 10／倉庫 7), the magic or special list (2／3); the
## right board is the six equipment slots on every page but 倉庫. Only on the 裝備 page do the
## slots take the hand: an empty hand takes an item off, a held bag item goes on by its kind.
## The window keeps no rules: every hand gesture goes to the host (hand_requested →
## PartyEquipmentRules.hand_action; unequip_requested → change) and comes back through
## show_loop／show_state. The hand survives 上一位／下一位 (0x4282c0 never writes 0x4c1ce4) and
## page changes; on the 倉庫 page (7) the right board is the storage list (WINDOW90「倉庫」,
## rows with counts) and 丟棄／使用 act on the hand. A picked-up bag item leaves the bag
## (0x436e80) and a taken-off piece goes onto the hand (0x437020; the old piece of an equip too,
## 0x436f30). A refused item stays in the hand silently as in the original (0x436f30 returns −1)
## and the reason is only kept for summary(). Original frames of the 狀態／裝備／倉庫 pages:
## docs/evidence_packets/runtime_observations/original_world_town/README.md (15–17).
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (mode 0 boards, nine buttons at y 429 x 272／320／389／457／389／437／505／553／601, page flags, equipment slot hand
##     rules)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (boards over the undimmed big map; buttons at y 429; price right edge x 594; hover description)
##   layout: remake-invented
##     (no ↓ mark; magic／special lists on the plain WINDOW20 board — the original's shape-table boards 5／10 are
##     not read; slide side by node name／centre x; close = last-frame snapshot)
##   strings: resource-derived content/imported/hsl/chapter01/source_texts/RESOURCE.TXT
##   strings: resource-derived content/imported/hsl/global/world_map/town_messages.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (open 400 px out, 0x45e882 speed 40; close 0x45e80d step 20 tol 4)
##   audio: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (button press 398 ACCEPT01, 0x42a6f4)
signal buy_requested(item_id: int, unit_id: String)
signal sell_requested(unit_id: String, slot: int)
## Shop: the hand dropped on the goods list (0x4153b1: important → 607, else half price, 2563).
signal sell_hand_requested(code: int)
signal close_requested
## Mode 0: the host runs PartyEquipmentRules.change and answers with show_loop or refuse.
signal unequip_requested(unit_id: String, slot: String)
## Both modes: a hand gesture (PartyEquipmentRules.hand_action action／args) on the current hand.
signal hand_requested(action: String, args: Dictionary, hand: Dictionary)

const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleLootPanel = preload("res://game/battle/scene/BattleLootPanel.gd")
const BattleSkillScrollBar = preload("res://game/battle/scene/BattleSkillScrollBar.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattleItemText = preload("res://game/battle/scene/BattleItemText.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const PartyEquipmentRules = preload("res://game/sim/PartyEquipmentRules.gd")
const JobStatsRules = preload("res://game/sim/JobStatsRules.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const WorldPartyRules = preload("res://game/world/WorldPartyRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const BattleGrowthPanel = preload("res://game/battle/scene/BattleGrowthPanel.gd")
const PartyStorageRules = preload("res://game/sim/PartyStorageRules.gd")

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
## right of the loot window's count column (BattleLootPanel.COUNT_RIGHT, x 584); the cell ends there.
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
## The button whose Data6 is the page (drawn dark, 0x42a330 +0x10000000; frames 08 and the
## 2026-09-27 shop 裝備／倉庫 frames).
const SHOP_PAGES := {"equip": PAGE_EQUIP, "trade": PAGE_TRADE, "storage": PAGE_STORAGE}
## RESOURCE 309, the storage list's title (0x428410 case 6, +0xa0 = 0x135).
const STORAGE_TITLE := "倉庫"
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
var message_color := BattleUISkin.TEXT_WHITE
var buttons: Dictionary = {}
var goods_rows: Array[Button] = []
var bag_slots: Array[Button] = []
var description_box: Control
var hand_icon: TextureRect
var _hand: Dictionary = {}
## The party storage shown on page 7 (PartyStorageRules form; the host's).
var storage: Dictionary = {}
var storage_rows: Array[Button] = []
var _scroll := 0
## The goods／storage list's 0x446060 bar (null off those pages).
var list_bar: BattleSkillScrollBar
var _loop: Dictionary = {}
var _items: Dictionary = {}
var _pointer := Vector2.ZERO
## Open／close slide (0x428410／0x4285e0 start points, 0x45e882／0x45e80d steps).
const SLIDE_DISTANCE := 400
const SLIDE_IN_SPEED := 40
const SLIDE_OUT_STEP := 20
const SLIDE_OUT_TOLERANCE := 4
const SLIDE_SPLIT_X := 252.0
## Distance still to go on the open slide (0 = landed); every part shares it (all start 400 px out).
var slide_remaining := 0
var _slide_clock := 0.0
## Close snapshots actually drawn (0 without a renderer).
var slide_out_count := 0
## 398 ACCEPT01 (sfxAccept), the status buttons' press sound.
const BUTTON_SOUND := "res://content/imported/hsl/shared/interface_audio/confirm.wav"
var _button_sound: AudioStreamPlayer
## The hand's sounds in the shared status window: 399 sfxTakeUp when an item comes into the hand
## (list take 0x415559, bag lift 0x4292c3, take-off 0x429eb5), 400 sfxPutDown when the hand sets
## it down (bag 0x42929d, put on 0x429e6d, storage list 0x415452), 2563 sfxSellItem on a sale
## (0x415435). Queued with the request, played when the host commits it; a refusal stays silent.
const ITEM_SOUNDS := {
	"take_up": "res://content/imported/hsl/shared/interface_audio/take_up.wav",
	"put_down": "res://content/imported/hsl/shared/interface_audio/put_down.wav",
	"sell_item": "res://content/imported/hsl/shared/interface_audio/sell_item.wav",
}
const HAND_SOUNDS := {"lift": "take_up", "unequip": "take_up", "retrieve": "take_up", "place": "put_down", "equip": "put_down", "store": "put_down"}
var _item_sound: AudioStreamPlayer
var _pending_sound := ""
## The last item sound played (a key of ITEM_SOUNDS; "" before any).
var last_item_sound := ""


func _ready() -> void:
	name = "TownShop"
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	# Internal: _rebuild frees the window's children, not this player.
	_button_sound = AudioStreamPlayer.new()
	_button_sound.name = "ButtonSound"
	_button_sound.stream = load(BUTTON_SOUND)
	_button_sound.volume_db = -6.0
	add_child(_button_sound, false, Node.INTERNAL_MODE_FRONT)
	_item_sound = AudioStreamPlayer.new()
	_item_sound.name = "ItemSound"
	_item_sound.volume_db = -6.0
	add_child(_item_sound, false, Node.INTERNAL_MODE_FRONT)


func _request_hand(action: String, args: Dictionary, held: Dictionary) -> void:
	_pending_sound = str(HAND_SOUNDS.get(action, ""))
	hand_requested.emit(action, args, held)


## The host committed the queued request: play its sound once.
func _play_pending_sound() -> void:
	var key := _pending_sound
	_pending_sound = ""
	if key == "":
		return
	last_item_sound = key
	if _item_sound != null:
		_item_sound.stream = load(str(ITEM_SOUNDS[key]))
		_item_sound.play()


## 0x45e882(cur, target, speed): distance ≤ 1 lands; else step min(speed, distance >> 3), at least 2.
static func slide_in_step(remaining: int) -> int:
	if remaining <= 1:
		return 0
	return maxi(remaining - maxi(mini(SLIDE_IN_SPEED, remaining >> 3), 2), 0)


## 0x45e80d(cur, start, tol 4, step 20) on the one moving axis: within 4 lands; else half the
## rest, at most 20.
static func slide_out_step(travelled: int) -> int:
	var rest := SLIDE_DISTANCE - travelled
	if rest <= SLIDE_OUT_TOLERANCE:
		return SLIDE_DISTANCE
	return travelled + mini(rest >> 1, SLIDE_OUT_STEP)


## The unit direction a part slides from: WINDOW10 strip from above, buttons from below, left
## boards (WINDOW20／40) from the left, right boards (WINDOW30／90) from the right; the
## description, message board and hand do not slide.
func _slide_direction(part: Control) -> Vector2:
	var key := str(part.name)
	if key == "Vitals":
		return Vector2.UP
	if key.begins_with("Button_") or key.begins_with("Caption_"):
		return Vector2.DOWN
	if key in ["Description", "Hand", "MessageBlocker", "MessageBoard", "MessageText"]:
		return Vector2.ZERO
	return Vector2.LEFT if part.position.x + part.size.x * 0.5 < SLIDE_SPLIT_X else Vector2.RIGHT


func _begin_slide_in() -> void:
	slide_remaining = SLIDE_DISTANCE
	_slide_clock = 0.0
	set_process(true)


func sliding_in() -> bool:
	return slide_remaining > 0


func _process(delta: float) -> void:
	_slide_clock += maxf(delta, 0.0)
	while _slide_clock >= OriginalTick.TICK_SECONDS and sliding_in():
		_slide_clock -= OriginalTick.TICK_SECONDS
		slide_remaining = slide_in_step(slide_remaining)
		_apply_slide()
	if not sliding_in():
		set_process(false)


## Draw-only offset (RenderingServer transform): layout and hit testing stay the landed ones.
func _apply_slide() -> void:
	for child in get_children():
		if child is Control:
			var part := child as Control
			var xform := part.get_transform()
			xform.origin += _slide_direction(part) * float(slide_remaining)
			RenderingServer.canvas_item_set_transform(part.get_canvas_item(), xform)


## Explicit fast-forward (tests): lands the open slide at once.
func finish_slide() -> void:
	slide_remaining = 0
	_apply_slide()
	set_process(false)


## Close: a snapshot of the last frame's parts slides back to the start points over the host
## (the host frees／hides the window right after close_requested).
func _begin_slide_out() -> void:
	if sliding_in():
		finish_slide()
		return
	if DisplayServer.get_name() == "headless" or not is_inside_tree() or not is_visible_in_tree():
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var view := Rect2(Vector2.ZERO, size)
	var scale := Vector2(image.get_size()) / size
	var ghost := SlideGhost.new()
	ghost.name = "StatusWindowCloseGhost"
	var host_layer := get_canvas_layer_node()
	ghost.layer = (host_layer.layer if host_layer != null else 0) + 1
	for child in get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		var part := child as Control
		var direction := _slide_direction(part)
		var rect := part.get_global_rect().intersection(view)
		if direction == Vector2.ZERO or rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		var region := Rect2i(Vector2i((rect.position * scale).floor()), Vector2i((rect.size * scale).ceil())).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if region.size.x <= 0 or region.size.y <= 0:
			continue
		var piece := TextureRect.new()
		piece.texture = ImageTexture.create_from_image(image.get_region(region))
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.position = rect.position
		piece.size = rect.size
		ghost.add_child(piece)
		ghost.pieces.append({"item": piece, "from": rect.position, "direction": direction})
	if ghost.pieces.is_empty():
		ghost.free()
		return
	slide_out_count += 1
	get_tree().root.add_child(ghost)


## The close snapshot: every piece steps as slide_out_step until it reaches its start point.
class SlideGhost extends CanvasLayer:
	var pieces: Array = []
	var travelled := 0
	var clock := 0.0

	func _process(delta: float) -> void:
		clock += maxf(delta, 0.0)
		while clock >= OriginalTick.TICK_SECONDS and travelled < SLIDE_DISTANCE:
			clock -= OriginalTick.TICK_SECONDS
			var rest := SLIDE_DISTANCE - travelled
			travelled = SLIDE_DISTANCE if rest <= SLIDE_OUT_TOLERANCE else travelled + mini(rest >> 1, SLIDE_OUT_STEP)
			for entry in pieces:
				(entry["item"] as TextureRect).position = entry["from"] + entry["direction"] * float(travelled)
		if travelled >= SLIDE_DISTANCE:
			queue_free()


## The held item follows the cursor (0x414c00 draws it after the window).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and visible:
		_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if hand_icon != null and hand_icon.visible:
			hand_icon.position = _pointer - hand_icon.get_meta("origin", Vector2.ZERO)
	elif event is InputEventKey and event.pressed and not event.echo and _shown():
		# 0x42a6d3: key bit 0x10000 presses 上一位 (id 0), 0x20000 下一位 (id 5).
		match (event as InputEventKey).keycode:
			KEY_LEFT: press_button("prev")
			KEY_RIGHT: press_button("next")


func _shown() -> bool:
	var layer := get_canvas_layer_node()
	return is_inside_tree() and is_visible_in_tree() and (layer == null or layer.visible)


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
	_loop = {}
	vitals_error = "" if scenario_path != "" else "unknown_source_scenario"
	_shop_scenario = scenario_path
	_begin_slide_in()
	show_carry(next_carry, "")


## Redraws for a new carry (after every transaction); `next_message` is the board line to show
## in `next_color` (the host's: RESOURCE 606 is coded @2 red, 607 @5 yellow).
func show_carry(next_carry: Dictionary, next_message: String, next_color: Color = BattleUISkin.TEXT_WHITE, keep_hand: bool = false) -> void:
	carry = next_carry.duplicate(true)
	message = next_message
	message_color = next_color
	if next_message == "":
		_play_pending_sound()
	_pending_sound = ""
	if not keep_hand:
		_hand = {}
	storage = PartyStorageRules.of_carry(carry)
	_refresh_shop_loop()
	var ids := member_ids()
	if not ids.has(unit_id):
		unit_id = "" if ids.is_empty() else str(ids[0])
	_rebuild()


## Shop mode: the vitals and the 裝備 page read a sandbox of the current carry (rebuilt after
## every transaction; the scenario path is the opening's).
var _shop_scenario := ""


func _refresh_shop_loop() -> void:
	if mode != MODE_SHOP or _shop_scenario == "":
		return
	var box := PartyEquipmentRules.sandbox(BattlePlayLoop.create([], "", BattleScenario.load_file(_shop_scenario)), carry)
	if bool(box["ok"]):
		_loop = box["loop"]
		vitals_error = ""
	else:
		vitals_error = str(box["error"])


## Both modes: redraw after a hand gesture — the host's new carry (shop) or sandbox (mode 0),
## storage and hand; the page and the shown member stay.
func show_state(next_carry: Dictionary, loop: Dictionary, next_storage: Dictionary, next_hand: Dictionary) -> void:
	carry = next_carry.duplicate(true)
	storage = next_storage.duplicate(true)
	if mode == MODE_SHOP:
		_refresh_shop_loop()
	else:
		_loop = loop
	message = ""
	last_refusal = ""
	_hand = next_hand.duplicate()
	_play_pending_sound()
	_rebuild()


## Mode 0 over the host's sandbox `loop` (PartyEquipmentScreen); `next_carry` only feeds the
## gold box; `next_message` is the host's failure line (no sandbox). Opens on page 4.
func open_arrange(next_carry: Dictionary, loop: Dictionary, next_message: String = "", next_storage: Dictionary = {}) -> void:
	storage = next_storage.duplicate(true) if not next_storage.is_empty() else PartyStorageRules.empty()
	mode = MODE_ARRANGE
	page = PAGE_STATUS
	title = ""
	goods = []
	shop_catalog = {}
	_items = EquipmentCatalog.items()
	_scroll = 0
	unit_id = ""
	vitals_error = ""
	_begin_slide_in()
	show_loop(next_carry, loop, next_message)


## Mode 0 redraw after an equipment change; the hand empties.
func show_loop(next_carry: Dictionary, loop: Dictionary, next_message: String = "") -> void:
	carry = next_carry.duplicate(true)
	_loop = loop
	message = next_message
	message_color = BattleUISkin.TEXT_WHITE
	_hand = {}
	last_refusal = ""
	_play_pending_sound()
	var ids := member_ids()
	if not ids.has(unit_id):
		unit_id = "" if ids.is_empty() else str(ids[0])
	_rebuild()


## Mode 0 page change (the button's Data6); a held item stays in the hand (0x42a330).
func set_page(next_page: int) -> void:
	page = next_page
	_rebuild()


## Mode 0: show `next_unit_id` (the host's select_member); the hand stays.
func show_member(next_unit_id: String) -> void:
	if member_ids().has(next_unit_id):
		unit_id = next_unit_id
		_rebuild()


## Mode 0, 裝備 page: a click on equipment slot `slot` — a held bag item goes on (its kind picks
## the slot, 0x436f30), an empty hand takes the slot's item off (0x437020).
func click_equipment(slot: String) -> void:
	if page != PAGE_EQUIP or message_visible() or unit_id == "":
		return
	if holding():
		_request_hand("equip", {"unit_id": unit_id, "slot": _slot_for_hand(slot)}, _hand.duplicate())
	elif _worn_code(slot) > 0:
		# 0x437020: the piece comes off onto the hand.
		_request_hand("unequip", {"unit_id": unit_id, "slot": slot}, {})


## Mode 0: the host refused the held item; it stays in the hand (no board, no sound).
func refuse(reason: String) -> void:
	last_refusal = reason
	_pending_sound = ""


## The held item's kind picks its slot (0x436f30); accessories go to the clicked accessory slot
## when it is one, else the first empty accessory slot.
func _slot_for_hand(clicked: String) -> String:
	var kind := int((_items.get(str(int(_hand.get("code", 0))), {}) as Dictionary).get("type_code", 0))
	if kind >= 2 and kind <= 5:
		return str(BattleEquipmentView.SLOTS[kind - 2])
	if clicked.begins_with("accessory"):
		return clicked
	return "accessory2" if _worn_code("accessory1") > 0 and _worn_code("accessory2") == 0 else "accessory1"


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
	return WorldPartyRules.members(carry, speakers).map(func(member): return str(member["unit_id"]))


func holding() -> bool:
	return not _hand.is_empty()


func message_visible() -> bool:
	return message != ""


## 上一位／下一位 (step -1／+1) cycle the shown member; the hand stays (0x42a76e／0x42a77a call
## 0x4282c0, which reloads the member and never touches 0x4c1ce4).
func step_member(step: int) -> void:
	var ids := member_ids()
	if ids.is_empty():
		return
	unit_id = str(ids[posmod(ids.find(unit_id) + step, ids.size())])
	_rebuild()


## Original right click／Esc order: close the message, else put the held item back, else leave.
func back() -> void:
	if message_visible():
		dismiss_message()
	elif holding():
		put_back()
	else:
		_begin_slide_out()
		close_requested.emit()


func dismiss_message() -> void:
	message = ""
	_rebuild()


func put_back() -> void:
	if holding() and (bool(_hand.get("loose", false)) or str(_hand.get("unit_id", "")) != unit_id):
		# 0x436e30: into the shown member's first empty slot (the host decides; a full bag keeps
		# nothing lost — see PartyEquipmentRules.hand_action back).
		_request_hand("back", {"unit_id": unit_id}, _hand.duplicate())
		return
	_hand = {}
	_rebuild()


## Picks the bag item in `slot` of the shown member up: it leaves the bag and the slots after it
## close up (0x436e80, sound 399) — the host's lift.
func pick_up(slot: int) -> void:
	var inventory: Array = _member().get("inventory", [])
	if message_visible() or holding() or slot < 0 or slot >= inventory.size() or int(inventory[slot]) <= 0:
		return
	_request_hand("lift", {"unit_id": unit_id, "slot": slot}, {})


## Dropping the held item on the goods list sells it (0x414c00 shop branch, 0x4153b1); whatever
## is on the hand sells — lifted, taken off, bought or from the storage.
func drop_on_list() -> void:
	if holding() and bool(_hand.get("loose", false)):
		_pending_sound = "sell_item"
		sell_hand_requested.emit(int(_hand["code"]))
		return
	if holding():
		var hand := _hand
		_hand = {}
		_pending_sound = "sell_item"
		sell_requested.emit(str(hand["unit_id"]), int(hand["slot"]))


func _member() -> Dictionary:
	if mode == MODE_ARRANGE:
		return _actor()
	for member in WorldPartyRules.members(carry, speakers):
		if str(member["unit_id"]) == unit_id:
			return member
	return {}


func _actor() -> Dictionary:
	return {} if _loop.is_empty() or unit_id == "" else BattlePlayLoop.unit(_loop, unit_id)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	goods_rows.clear()
	bag_slots.clear()
	buttons.clear()
	list_bar = null
	var vitals := BattleVitals.new()
	vitals.name = "Vitals"
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	var actor := _actor()
	vitals.visible = not actor.is_empty()
	if not actor.is_empty():
		vitals.show_unit(actor)
	storage_rows.clear()
	if mode == MODE_SHOP:
		_build_bag()
		match page:
			PAGE_EQUIP: _build_equipment()
			PAGE_STORAGE: _build_storage()
			_: _build_goods()
	else:
		match page:
			PAGE_STATUS: _build_attributes()
			PAGE_MAGIC, PAGE_SPECIAL: _build_skills()
			_: _build_bag()
		if page != PAGE_STORAGE:
			_build_equipment()
		else:
			_build_storage()
	BattleUISkin.board(self, "WINDOW40", BattleLootPanel.GOLD_AT).name = "GoldBoard"
	var amount := BattleUISkin.text(self, BattleLootPanel.GOLD_AT + Vector2(80, 4), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(108, 24))
	amount.name = "Gold"
	amount.text = str(int((carry.get("loop", {}) as Dictionary).get("gold", 0)))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for spec in (BUTTONS if mode == MODE_SHOP else ARRANGE_BUTTONS):
		if _shown_on(int(spec[4]), page):
			_status_button(spec[0], spec[1], spec[2], spec[3])
	description_box = Control.new()
	description_box.name = "Description"
	description_box.position = BattleLootPanel.DESCRIPTION_AT
	description_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BattleUISkin.board(description_box, "WINDOW50", Vector2.ZERO)
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
	if holding() and _items.has(str(int(_hand["code"]))):
		var key := str(_items[str(int(_hand["code"]))]["icon"])
		var origin: Array = BattleUISkin.data()["assets"][key]["draw_origin"]
		BattleUISkin.show_shape(hand_icon, BattleUISkin.texture(key))
		hand_icon.set_meta("origin", Vector2(float(origin[0]), float(origin[1])))
		hand_icon.position = _pointer - hand_icon.get_meta("origin")
		hand_icon.show()
	if sliding_in():
		_apply_slide()


func _build_bag() -> void:
	BattleUISkin.board(self, "WINDOW20", BattleLootPanel.BAG_AT).name = "BagBoard"
	var inventory: Array = _member().get("inventory", [])
	for index in range(inventory.size()):
		var code := int(inventory[index])
		var shown := code > 0 and not (holding() and not bool(_hand.get("loose", false)) and str(_hand.get("unit_id", "")) == unit_id and int(_hand["slot"]) == index)
		var button := _row_button(BattleLootPanel.BAG_AT + Vector2(8, 8 + index * BattleLootPanel.BAG_ROW), Vector2(208, BattleLootPanel.BAG_ROW))
		button.name = "Bag_%d" % index
		if shown:
			var details: Dictionary = _items[str(code)]
			BattleUISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 8))
			var label := BattleUISkin.text(button, Vector2(48, 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(160, BattleLootPanel.BAG_ROW))
			label.text = str(details["name"])
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
		button.pressed.connect(func():
			if message_visible(): return
			if holding(): click_bag_with_hand(index)
			elif shown: pick_up(index))
		bag_slots.append(button)


## The hand on bag slot `index` of the shown member: its own slot takes it back; anything else
## is the host's place (first empty slot, a full bag swaps — 0x42923b).
func click_bag_with_hand(index: int) -> void:
	if not holding() or message_visible():
		return
	if not bool(_hand.get("loose", false)) and str(_hand.get("unit_id", "")) == unit_id:
		_hand = {}
		_rebuild()
		return
	_request_hand("place", {"unit_id": unit_id, "slot": index}, _hand.duplicate())


## Page 7: the storage list (WINDOW90「倉庫」, the loot list's rows: icon, name, count).
## A click with the hand stores it (0x44f2d0); an empty-handed click on a row takes one
## (important rows stay, 0x4154cd).
func _build_storage() -> void:
	BattleUISkin.board(self, "WINDOW90", BattleLootPanel.LIST_AT).name = "StorageBoard"
	var heading := BattleUISkin.text(self, BattleLootPanel.LIST_AT + Vector2(0, 10), BattleUISkin.TEXT_IVORY, BattleUISkin.FONT_BODY, Vector2(375, 24))
	heading.name = "StorageTitle"
	heading.text = STORAGE_TITLE
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var drop_area := _row_button(BattleLootPanel.LIST_AT + Vector2(8, BattleLootPanel.LIST_TOP), Vector2(340, BattleLootPanel.LIST_ROW * BattleLootPanel.VISIBLE_ROWS))
	drop_area.name = "StorageDrop"
	drop_area.pressed.connect(func(): if not message_visible() and holding(): _request_hand("store", {}, _hand.duplicate()))
	var rows := PartyStorageRules.entries(storage)
	var job := int(_actor().get("growth_profile", {}).get("job_code", -1))
	_build_list(rows.size(), func():
		storage_rows.clear()
		for index in range(mini(BattleLootPanel.VISIBLE_ROWS, rows.size() - _scroll)):
			var row_index := _scroll + index
			var code := int(rows[row_index]["code"])
			var details: Dictionary = _items.get(str(code), {"icon": "", "name": str(code), "important": false, "job_mask": 0})
			var button := _row_button(BattleLootPanel.LIST_AT + Vector2(8, BattleLootPanel.LIST_TOP + index * BattleLootPanel.LIST_ROW), Vector2(340, BattleLootPanel.LIST_ROW))
			button.name = "Storage_%d" % row_index
			if str(details["icon"]) != "":
				BattleUISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 6))
			var color := _row_color(details, job)
			var label := BattleUISkin.text(button, Vector2(48, 0), color, BattleUISkin.FONT_BODY, Vector2(168, BattleLootPanel.LIST_ROW))
			label.text = str(details["name"])
			label.set_meta("base_color", color)
			var count := BattleUISkin.text(button, Vector2(BattleLootPanel.COUNT_RIGHT - BattleLootPanel.LIST_AT.x - 8 - 108, 0), color, BattleUISkin.FONT_BODY, Vector2(108, BattleLootPanel.LIST_ROW))
			count.text = str(int(rows[row_index]["qty"]))
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
			button.pressed.connect(func():
				if message_visible(): return
				if holding(): _request_hand("store", {}, _hand.duplicate())
				else: _request_hand("retrieve", {"index": row_index}, {}))
			storage_rows.append(button))


## The goods and storage lists are 0x414c00's, like the 獲得物品 list: its first tick
## (0x414c3e, window flag 0x20000000, whatever the shop flag) hangs 0x446060(win, 760, 151,
## 152, 153, width − 24, 0, 0, 0, 5, 0x414af0) — WIN06BAR 24×220 at WINDOW90 + (351,0), five
## rows. `fill` lays the rows from `_scroll`; the bar swaps them in place without rebuilding the page.
func _build_list(rows: int, fill: Callable) -> void:
	_scroll = clampi(_scroll, 0, maxi(0, rows - BattleLootPanel.VISIBLE_ROWS))
	var first := get_child_count()
	fill.call()
	var laid := [get_child_count() - first]  # lambdas capture locals by value
	list_bar = BattleSkillScrollBar.new(BattleLootPanel.LIST_AT, "WIN06BAR", BattleLootPanel.VISIBLE_ROWS, 375 - 24)
	add_child(list_bar)
	list_bar.count = rows
	list_bar.scroll_to(_scroll, false)
	list_bar.scrolled.connect(func(pos: int):
		_scroll = pos
		for index in range(laid[0]):
			var row := get_child(first)
			remove_child(row)
			row.queue_free()
		var end := get_child_count()
		fill.call()
		laid[0] = get_child_count() - end
		for index in range(laid[0]):
			move_child(get_child(end + index), first + index)
		if sliding_in(): _apply_slide())


func _build_goods() -> void:
	BattleUISkin.board(self, "WINDOW90", BattleLootPanel.LIST_AT).name = "GoodsBoard"
	var heading := BattleUISkin.text(self, BattleLootPanel.LIST_AT + Vector2(0, 10), BattleUISkin.TEXT_IVORY, BattleUISkin.FONT_BODY, Vector2(375, 24))
	heading.name = "ShopTitle"
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# While an item is held the whole list area takes the drop (rows included).
	var drop_area := _row_button(BattleLootPanel.LIST_AT + Vector2(8, BattleLootPanel.LIST_TOP), Vector2(340, BattleLootPanel.LIST_ROW * BattleLootPanel.VISIBLE_ROWS))
	drop_area.name = "GoodsDrop"
	drop_area.pressed.connect(func(): if not message_visible(): drop_on_list())
	var job := int(_actor().get("growth_profile", {}).get("job_code", -1))
	_build_list(goods.size(), func():
		goods_rows.clear()
		for index in range(mini(BattleLootPanel.VISIBLE_ROWS, goods.size() - _scroll)):
			var code := goods[_scroll + index]
			var details: Dictionary = _items[str(code)]
			var button := _row_button(BattleLootPanel.LIST_AT + Vector2(8, BattleLootPanel.LIST_TOP + index * BattleLootPanel.LIST_ROW), Vector2(340, BattleLootPanel.LIST_ROW))
			button.name = "Goods%d" % code
			BattleUISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 6))
			var color := _row_color(details, job)
			var label := BattleUISkin.text(button, Vector2(48, 0), color, BattleUISkin.FONT_BODY, Vector2(168, BattleLootPanel.LIST_ROW))
			label.text = str(details["name"])
			label.set_meta("base_color", color)
			var price := BattleUISkin.text(button, Vector2(PRICE_RIGHT - 8 - 108, 0), color, BattleUISkin.FONT_BODY, Vector2(108, BattleLootPanel.LIST_ROW))
			price.text = "$%d" % _cost(code)
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
			button.pressed.connect(func():
				if message_visible(): return
				if holding(): drop_on_list()
				else:
					_pending_sound = "take_up"
					buy_requested.emit(code, unit_id))
			goods_rows.append(button))


## Mode 0 page 4: the status page's attribute column (WINDOW21, BattleGrowthPanel rows) on the
## left board's (12,168).
func _build_attributes() -> void:
	var at := BattleLootPanel.BAG_AT
	BattleUISkin.asset(self, "WINDOW21", at).name = "AttributeBoard"
	var unit := _actor()
	if unit.is_empty():
		return
	var profile := CoreCombatRules.combat_profile_from_unit(unit)
	var values := [int(profile["str"]), int(profile["dex"]), int(profile["mind"]), int(profile["con"]), int(profile["live_attack_damage"]), int(profile["live_defense"]), "%d%%" % int(profile["live_magic_attack"]), int(unit["live_speed"]), int(unit["move_point"])]
	for index in range(values.size()):
		var value := BattleUISkin.text(self, Vector2(BattleGrowthPanel.ATTRIBUTE_VALUE_X if index < 4 else BattleGrowthPanel.DERIVED_VALUE_X, at.y + 8 + index * BattleGrowthPanel.ROW_HEIGHT), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(60, BattleGrowthPanel.GLYPH_ROW))
		value.name = "Attribute_%d" % index
		value.text = str(values[index])


## Mode 0 pages 2／3: the member's magic or special list, 28 px rows (0x4289e0).
func _build_skills() -> void:
	BattleUISkin.board(self, "WINDOW20", BattleLootPanel.BAG_AT).name = "SkillBoard"
	if unit_id == "" or _loop.is_empty():
		return
	var options: Array = BattlePlayLoop.magic_options(_loop, unit_id) if page == PAGE_MAGIC else BattlePlayLoop.special_options(_loop, unit_id)
	for index in range(mini(options.size(), SKILL_ROWS)):
		var row := BattleUISkin.text(self, BattleLootPanel.BAG_AT + Vector2(48, 8 + index * SKILL_ROW), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(160, SKILL_ROW))
		row.name = "Skill_%d" % index
		row.text = str(options[index]["name"])


## Mode 0 right board: WINDOW30 with the six slots (two columns × three rows); hovering shows
## the item's description, a click goes to click_equipment (acts on the 裝備 page only).
func _build_equipment() -> void:
	BattleUISkin.board(self, "WINDOW30", EQUIPMENT_AT).name = "EquipmentBoard"
	var origin := EQUIPMENT_AT
	for index in range(BattleEquipmentView.SLOTS.size()):
		var slot: String = BattleEquipmentView.SLOTS[index]
		var column := index % 2
		var row := floori(index / 2.0)
		var at: Vector2 = origin + Vector2(BattleEquipmentView.SLOT_LEFTS[column], BattleEquipmentView.LABEL_ROW_CENTERS[row] - BattleEquipmentView.SLOT_SIZE.y / 2.0)
		var button := _row_button(at, BattleEquipmentView.SLOT_SIZE)
		button.name = "Slot_" + slot
		var code := _worn_code(slot)
		if code > 0:
			var details: Dictionary = _items[str(code)]
			var anchor: Vector2 = origin + BattleEquipmentView.ICON_ANCHORS[column] + Vector2(0, BattleEquipmentView.ICON_ROW_PITCH * row) - at
			BattleUISkin.anchored_asset(button, str(details["icon"]), anchor)
			var label := BattleUISkin.text(button, Vector2(BattleEquipmentView.COLON_ENDS[column] + BattleEquipmentView.NAME_GAP - BattleEquipmentView.SLOT_LEFTS[column], 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(150, BattleEquipmentView.SLOT_SIZE.y))
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
		return BattleUISkin.TEXT_IVORY
	if job < 0 or (JobStatsRules.has_job(job) and (int(details["job_mask"]) & JobStatsRules.job_mask_bit(job)) != 0):
		return BattleUISkin.TEXT_WHITE
	return BattleUISkin.TEXT_RED


func _cost(code: int) -> int:
	return int((shop_catalog.get(str(code), {}) as Dictionary).get("cost", 0))


func _status_button(key: String, resource: String, caption: String, centre_x: int) -> void:
	var button := TextureButton.new()
	button.name = "Button_" + key
	button.texture_normal = load(BattleUISkin.ROOT + resource + ".SHP.png")
	button.position = Vector2(centre_x - 21, BUTTON_Y - 21)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(button)
	# 0x43a640: 15 px caption centred under the icon at centre_y + 13, yellow while hovered.
	var label := BattleUISkin.text(self, Vector2(centre_x - 40, BUTTON_Y + 13), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(80, 16))
	label.name = "Caption_" + key
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pages: Dictionary = SHOP_PAGES if mode == MODE_SHOP else ARRANGE_PAGES
	# 0x42a330 marks the button whose Data6 is the current page (+0x10000000); the original
	# frames draw it dark (mode 0 狀態／裝備 pages, 2026-09-27; the shop's 買賣, frame 08).
	var current := int(pages.get(key, -1)) == page
	button.self_modulate = Color(0.45, 0.45, 0.45) if current else Color.WHITE
	button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE))
	button.pressed.connect(press_button.bind(key))
	buttons[key] = button


## A status button press (0x42a330 sub-state 2 → 3): the current page's button does nothing;
## any other plays ACCEPT01 (0x18e, 0x42a6f4) and runs its action (sub-state 3 table).
func press_button(key: String) -> void:
	var pages: Dictionary = SHOP_PAGES if mode == MODE_SHOP else ARRANGE_PAGES
	if message_visible() or not buttons.has(key) or int(pages.get(key, -1)) == page:
		return
	if _button_sound != null:
		_button_sound.play()
	match key:
		"prev": step_member(-1)
		"next": step_member(1)
		"drop":
			if holding():
				_request_hand("drop", {}, _hand.duplicate())
		"use":
			if holding():
				_request_hand("use", {"unit_id": unit_id}, _hand.duplicate())
		_:
			if pages.has(key):
				set_page(int(pages[key]))


## The refusal board: BOARD02 over the window, the line centred; any click closes it.
func _build_message() -> void:
	var blocker := _row_button(Vector2.ZERO, size)
	blocker.name = "MessageBlocker"
	blocker.pressed.connect(dismiss_message)
	BattleUISkin.board(self, "BOARD02", MESSAGE_BOARD_AT).name = "MessageBoard"
	var line := BattleUISkin.text(self, MESSAGE_BOARD_AT, message_color, BattleUISkin.FONT_BODY, Vector2(MESSAGE_BOARD_SIZE.x, MESSAGE_BOARD_SIZE.y))
	line.name = "MessageText"
	line.text = message
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _row_button(at: Vector2, dimensions: Vector2, parent: Node = self) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(button)
	return button


## Hovering a bag or goods row greens its name and shows WINDOW50 over the buttons (0x436d70);
## the shop adds the 賣價 line (RESOURCE 608).
func _show_description(code: int, label: Label) -> void:
	if holding() or message_visible():
		return
	label.add_theme_color_override("font_color", BattleUISkin.TEXT_GREEN)
	for child in description_box.get_children():
		if child is Label:
			description_box.remove_child(child)
			child.queue_free()
	var lines := description_lines(code)
	for index in range(mini(lines.size(), 4)):
		var row := BattleUISkin.text(description_box, Vector2(8, 12 + index * 16), BattleUISkin.TEXT_GREEN if index == 0 else BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(360, 16))
		row.text = str(lines[index])
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_box.show()


func _hide_description(label: Label) -> void:
	label.add_theme_color_override("font_color", label.get_meta("base_color", BattleUISkin.TEXT_WHITE))
	description_box.hide()


func description_lines(code: int) -> Array:
	var details: Dictionary = _items[str(code)]
	var lines: Array = []
	if int(details["type_code"]) in range(2, 7):
		lines.append_array(BattleEquipmentView.description_lines(details))
	else:
		lines.append_array([str(details["name"]), "可使用"])
		var definition: Dictionary = (_loop.get(LoopKeys.CONSUMABLES, {}) as Dictionary).get(str(code), {})
		if not definition.is_empty():
			lines.append_array(BattleItemText.description(definition).split("\n"))
	lines = lines.filter(func(line): return str(line) != "")
	if mode == MODE_ARRANGE:
		return lines.slice(0, 4)
	if lines.size() > 3:
		lines = lines.slice(0, 3)
	lines.append("賣價$%d" % WorldPartyRules.sell_price(_cost(code)))
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
		"storage": PartyStorageRules.entries(storage),
	}

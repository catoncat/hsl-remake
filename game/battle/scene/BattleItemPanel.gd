extends Control
## One modal stack: item commands -> inventory -> map pick／give recipient window; equip／drop
## share one held-item window (mode 4／5).
## Draft selection is presentation-only; all item mutations return to PlayLoop.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (the use target is a map cell pick, not a window: the page gives way, BattleSceneMenus draws the range)
##   rules: static-derived docs/evidence_packets/static_reverse/original_give_exchange.md
##     (give: giver's window → held item → adjacent-cell map pick → recipient's window → back to the giver's)
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md
##     (equip／drop: the 0x43b4e0 mode-4／5 held-item window; no preview or confirmation page)
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#07
##     (item sub-menu, target selection)
##   layout: static-derived docs/evidence_packets/runtime_observations/game_cursor/README.md
##     (the picked item's icon rides the pointer while its use target is chosen)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (使用／交換／裝備／丟棄 windows: boards, 32 px rows, icon and name cells, pulse-green hover, description, gold)
##   strings: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (裝備 row colour: 0x434d10 @2 red for a consumable or a piece outside the job mask; important @6)
##   strings: resource-derived content/generated/hsl/equipment/items.json
##   strings: resource-derived content/imported/hsl/chapter01/consumables.json
##   strings: remake-invented (返回, 沒有道具, 道具 N / 8 — OPT-GUIDE＝提示 only)
signal use_requested(item_code: String, target_id: String)
## The use target pick (page "target"): started, every pointer move／left press on the map, left.
signal use_pick_started
signal use_pick_pointer(viewport_position: Vector2, confirm: bool)
signal use_pick_ended
signal give_started
signal give_requested(target_id: String, index: int, code: int, target_index: int, return_code: int, revision: int)
signal give_finished(revision: int)
signal drop_requested(item_code: String)
signal equipment_requested(slot: String, inventory_index: int, item_code: int)
signal hand_return_requested(inventory_index: int, item_code: int)
signal hand_swap_requested(inventory_index: int, item_code: int, held: int)
## take_up (399) when an item comes into the hand, put_down (400) when the hand places it.
signal ui_sound_requested(event: String)
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const JobStatsRules = preload("res://game/sim/JobStatsRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattleItemText = preload("res://game/battle/scene/BattleItemText.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const BattleMagicPanel = preload("res://game/battle/scene/BattleMagicPanel.gd")
const BattleGrowthPanel = preload("res://game/battle/scene/BattleGrowthPanel.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
## 使用／交換 window (mode 6／7), runtime-measured on 玩家第 2 场 · 惡夢的終曲（LEVEL052）
## (menus_ui/README.md#7): WINDOW20 (12,174), rows from (20,182) every 32 px, the item icon
## anchored at (row x+24, row y+8) → 回復藥 texture (25,173+32i), the FONT.24 name cell at row
## x+48 (ink x 72, y 187–202), WINDOW40 `$:` (416,440), WINDOW50 description (252,349).
const LIST_BOARD_AT := Vector2(12, 174)
const LIST_ROW_ORIGIN := Vector2(8, 8)
const LIST_ROW_HEIGHT := 32
const LIST_ROW_SIZE := Vector2(208, 32)
const LIST_ICON_ANCHOR := Vector2(24, 8)
const LIST_NAME_DX := 48
const GOLD_AT := Vector2(416, 440)
const DETAIL_AT := Vector2(252, 349)
## Party gold for the `$:` box (BattleSceneMenus sets it before opening the window).
var gold := 0
var detail_box: Control
var hover_caption: Label
var _pulse_clock := 0.0
var rows: Control
var menu: Control
var page_root: Control
var source_unit: Dictionary = {}
var items: Dictionary = {}
var targets: Array = []
var anchor := Vector2(320, 240)
## Map bounds in the anchor's coordinates; the item submenu (0x43ea30 mode 3) shifts off map edges.
var map_area := Rect2(0, 0, 640, 480)
var page := "commands"
var operation := "use"
var selected_item := ""
var selected_index := -1
var selected_slot := ""
var equipment_view: Control
var target_buttons: Dictionary = {}
## Mode 4／5 held slot [0x4c1ce4] as a draft: the real inventory index and code of the held item.
## held_index -1 with a code is the loop's full-bag hand (BattlePlayLoop.held_item_code): the
## piece is in neither bag nor equipment.
var held_index := -1
var held_code := 0
## Mode 4／5 left column 屬性 page (WINDOW21) shown over the bag while an item is held over the board.
var attribute_page: Control
var _attribute_shown := false
var drop_button: TextureButton
const DROP_BUTTON_CENTRE := Vector2(285, 387)
var give_revision := -1
var give_target_id := ""
var give_target_index := -1
var give_return_code := 0
## The item picked for use rides the pointer while its target is chosen (held_icon; see _show_use_pick).
var held_icon: TextureRect
var picking := false


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root = Control.new()
	page_root.size = size
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_root)
	menu = preload("res://game/battle/scene/BattleCommandMenu.gd").new()
	menu.gui_interaction = true
	add_child(menu)
	menu.command_selected.connect(func(command):
		if command == "give": give_started.emit()
		else: _show_list(command))
	visibility_changed.connect(func(): if not visible: _end_pick())
	hide()


func show_inventory(unit: Dictionary, definitions: Dictionary, recipients: Array, at: Vector2, _capabilities: Dictionary) -> void:
	source_unit = unit.duplicate(true)
	items = definitions.duplicate(true)
	targets = recipients.duplicate(true)
	anchor = at
	selected_item = ""
	selected_index = -1
	selected_slot = ""
	held_index = -1
	held_code = 0
	give_revision = -1
	give_target_id = ""
	show()
	_show_commands()


func _clear_page() -> void:
	_end_pick()
	for child in page_root.get_children():
		page_root.remove_child(child)
		child.queue_free()
	target_buttons.clear()
	hover_caption = null
	menu.hide()


func _show_commands() -> void:
	_clear_page()
	page = "commands"
	menu.rebuild([{"command": "use"}, {"command": "equip"}, {"command": "drop"}, {"command": "give"}])
	menu.place_near(anchor, map_area)
	menu.show()


## `owner` set: the give recipient's window (state 114 0x444d9c opens the same mode-7 window on the
## target); its slots take the held item (_place_give_item) and the held icon stays on the pointer.
func _show_list(command: String, owner: Dictionary = {}) -> void:
	if command in ["equip", "drop"]:
		_show_hand_window(command)
		return
	_clear_page()
	operation = command
	var placing := not owner.is_empty()
	var unit: Dictionary = owner if placing else source_unit
	page = "give_inventory" if placing else "inventory"
	# OPT-GUIDE read once per window: the original window is icons and names only.
	var hints := not GameOptions.is_original("OPT-GUIDE")
	BattleUISkin.clear_panel(page_root)
	var vitals := BattleVitals.new()
	vitals.position = Vector2(0, 14)
	page_root.add_child(vitals)
	vitals.show_unit(unit)
	var equipment := BattleEquipmentView.new()
	equipment_view = equipment
	page_root.add_child(equipment)
	equipment.show_unit(unit)
	_list_frame()
	var catalog := EquipmentCatalog.items()
	for index in range(unit["inventory"].size()):
		var code := str(int(unit["inventory"][index]))
		if code == "0":
			# 0x438cbf..0x438d0c: a pick on an empty slot inserts into the first empty slot.
			if placing and index == unit["inventory"].find(0):
				var empty_slot := _empty_slot_button(index)
				empty_slot.position = Vector2(0, index * LIST_ROW_HEIGHT)
				empty_slot.size = LIST_ROW_SIZE
				rows.add_child(empty_slot)
			continue
		var details: Dictionary = catalog[code]
		# 0x434d10 (0x435e12／0x435e9d): an important item (+0xa0 bit 0x8000000) prints @6 in every mode.
		var button := _bag_button(details, code, index, index, BattleUISkin.TEXT_IVORY if bool(details.get("important", false)) else BattleUISkin.TEXT_WHITE)
		var caption: Label = button.get_node("Caption")
		button.disabled = operation == "use" and ItemUseRules.definition_error(items.get(code, {})) != ""
		button.mouse_entered.connect(_hover_row.bind(caption, _item_lines(details, code)))
		button.mouse_exited.connect(_hover_row.bind(null, []))
		button.pressed.connect(_place_give_item.bind(index, int(code)) if placing else _select_item.bind(code, index))
		rows.add_child(button)
	if hints and rows.get_child_count() == 0:
		var empty := BattleUISkin.text(rows, Vector2(LIST_NAME_DX, 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(160, 24))
		empty.text = "沒有道具"
	# Remake-only (the original window has neither): back button and count, OPT-GUIDE＝提示 only.
	var back := BattleUISkin.button(page_root, "返回", Vector2(252, 442), Vector2(113, 30))
	back.pressed.connect(cancel)
	back.visible = hints
	var capacity := BattleUISkin.label(page_root, Vector2(20, 440), 15)
	capacity.text = "道具 %d / 8" % (8 - unit["inventory"].count(0))
	capacity.visible = hints
	if placing:
		_hold_selected_item()



## WINDOW20 with the eight fixed row slots, WINDOW40 `$:` and the hidden WINDOW50 description
## box: the 使用／交換 (mode 6／7) and 裝備／丟棄 (mode 4／5) windows share them (menus_ui §7).
func _list_frame() -> void:
	BattleUISkin.board(page_root, "WINDOW20", LIST_BOARD_AT)
	BattleUISkin.board(page_root, "WINDOW40", GOLD_AT)
	var gold_label := BattleUISkin.text(page_root, GOLD_AT + Vector2(80, 4), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(108, 24))
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_label.text = str(gold)
	detail_box = Control.new()
	detail_box.name = "ItemDescription"
	detail_box.position = DETAIL_AT
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BattleUISkin.board(detail_box, "WINDOW50", Vector2.ZERO)
	detail_box.hide()
	BattleUISkin.in_place(detail_box)
	page_root.add_child(detail_box)
	# Eight fixed 32 px bag rows (the status page's 道具 page geometry); the window never scrolls.
	rows = Control.new()
	rows.name = "Rows"
	rows.position = LIST_BOARD_AT + LIST_ROW_ORIGIN
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(rows)


## One bag row at slot `row`: icon anchored at (x+24, y+8), the FONT.24 name cell at x+48.
func _bag_button(details: Dictionary, code: String, index: int, row: int, colour: Color) -> Button:
	var button := Button.new()
	button.name = "Item_%s_%d" % [code, index]
	button.set_meta("item_code", code)
	button.set_meta("inventory_index", index)
	button.position = Vector2(0, row * LIST_ROW_HEIGHT)
	button.size = LIST_ROW_SIZE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var art := BattleUISkin.anchored_asset(button, str(details["icon"]), LIST_ICON_ANCHOR)
	art.name = "OriginalConsumable"
	var caption := BattleUISkin.text(button, Vector2(LIST_NAME_DX, 0), colour, BattleUISkin.FONT_BODY, Vector2(LIST_ROW_SIZE.x - LIST_NAME_DX, 24))
	caption.name = "Caption"
	caption.set_meta("colour", colour)
	caption.text = str(details["name"])
	return button


## Description rows of a bag row (0x430710 through BattleItemText; the frame's 回復藥／可使用／生命+40),
## coloured per row (an equipment row keeps its place when the one above is empty).
func _item_lines(details: Dictionary, code: String) -> Array:
	return BattleEquipmentView.description_rows(details, BattleItemText.description_lines(details, items.get(code, {})))


## Hovering a row pulses its name green (BattleMagicPanel.hover_colour) and fills WINDOW50 with
## up to four FONT.15 rows at (x+8, y+12+16i), 360 px centred, the first @3 green (0x436d70,
## BattleEquipmentView.fill_box).
func _hover_row(caption: Label, lines: Array) -> void:
	if is_instance_valid(hover_caption):
		hover_caption.add_theme_color_override("font_color", hover_caption.get_meta("colour", BattleUISkin.TEXT_WHITE))
	hover_caption = caption
	BattleEquipmentView.fill_box(detail_box, lines)
	detail_box.visible = caption != null
	if caption != null:
		caption.add_theme_color_override("font_color", _hover_colour())


func _hover_colour() -> Color:
	var period := 2 * BattleMagicPanel.HOVER_PULSE_HALF + 1
	var step := int(OriginalTick.ticks(_pulse_clock)) % period - BattleMagicPanel.HOVER_PULSE_HALF
	return Color8(0, BattleMagicPanel.HOVER_GREEN_BASE - 2 * absi(step), 0)


func _select_item(code: String, index: int = -1) -> void:
	selected_item = code
	selected_index = index if index >= 0 else source_unit["inventory"].find(int(code))
	if operation == "use":
		_show_use_pick()
	elif operation == "give":
		_show_targets()


## Give target pick (state 112 0x444bc7 → 113 0x444c27): the picked item is already held
## (0x438c53..0x438d8d store it in 0x4c1ce4 and close the window); 0x40f440(user, 1, 4) marks the
## adjacent cells and clears the user's own; the cell cursor and hover strip are the use pick's.
## BattleSceneMenus draws the range and confirms a marked cell holding a give target.
func _show_targets() -> void:
	BattlePanelMotion.attach(self).slide_out()
	_clear_page()
	page = "give_target"
	picking = true
	_hold_selected_item()
	use_pick_started.emit()


## An empty-slot row of the recipient's window (no caption; the original slot is blank).
func _empty_slot_button(index: int, hand := false) -> Button:
	var button := Button.new()
	button.name = "Item_0_%d" % index
	button.set_meta("item_code", "0")
	button.set_meta("inventory_index", index)
	button.custom_minimum_size = Vector2(195, 32)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_hand_row.bind(-1, 0) if hand else _place_give_item.bind(-1, 0))
	return button


## Original: picking the item in the use window moves it into the held slot [0x4c1ce4]
## (0x439997 -> 0x437020) and the window closes; state 104 (0x4448f4) marks the range and state
## 105 (0x44492a..) is a map cell pick, with 0x430410 -> 0x430310 drawing the held item's icon
## at the mouse and no sceptre. The page slides out as on close and only the icon stays;
## BattleSceneMenus draws the range, cursor and hover strip and confirms the cell (use_pick_*).
func _show_use_pick() -> void:
	BattlePanelMotion.attach(self).slide_out()
	_clear_page()
	page = "target"
	picking = true
	_hold_selected_item()
	use_pick_started.emit()


func _end_pick() -> void:
	if picking:
		picking = false
		if not visible and is_instance_valid(held_icon):
			_release_held_icon.call_deferred(held_icon)
			held_icon = null
		use_pick_ended.emit()


## The confirmed pick hides the panel on the confirm tick, but the held slot is only cleared on
## the next tick (state 106 0x444aba), so the icon stays where it is for one more tick.
func _release_held_icon(icon: TextureRect) -> void:
	if not is_instance_valid(icon) or not is_inside_tree():
		return
	icon.reparent(get_parent())
	get_tree().create_timer(OriginalTick.TICK_SECONDS).timeout.connect(func(): if is_instance_valid(icon): icon.queue_free())


## Picking the item puts it in the held slot at once (0x439997 -> 0x437020), so the icon is on
## the pointer, above the page's close snapshot, while the window slides out. The icon lives on
## the pick page, so leaving the page drops it (0x444a81 on cancel; a confirm keeps it one tick,
## _release_held_icon); GameCursor hides the sceptre while it shows.
func _hold_selected_item() -> void:
	var icon := str(EquipmentCatalog.items().get(selected_item, {}).get("icon", ""))
	if icon == "":
		return
	var record: Dictionary = BattleUISkin.data()["assets"][icon]
	held_icon = TextureRect.new()
	held_icon.name = "HeldItem"
	held_icon.add_to_group("game_cursor_held_items")
	held_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	held_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_icon.z_index = 1
	BattleUISkin.show_shape(held_icon, BattleUISkin.texture(icon))
	held_icon.set_meta("origin", Vector2(float(record["draw_origin"][0]), float(record["draw_origin"][1])))
	page_root.add_child(held_icon)
	_follow_pointer()


func _process(delta: float) -> void:
	if visible and is_instance_valid(held_icon):
		_follow_pointer()
	if visible: _update_attribute_page()
	_pulse_clock += delta
	if visible and is_instance_valid(hover_caption):
		hover_caption.add_theme_color_override("font_color", _hover_colour())


func _follow_pointer() -> void:
	held_icon.position = page_root.get_local_mouse_position() - held_icon.get_meta("origin", Vector2.ZERO)


## Every give session step lands on the giver's window (state 110 0x444b8a; 116 returns there).
func show_give_session(unit: Dictionary, recipients: Array, revision: int) -> void:
	source_unit = unit.duplicate(true)
	targets = recipients.duplicate(true)
	give_revision = revision
	operation = "give"
	selected_item = ""
	selected_index = -1
	give_target_index = -1
	give_target_id = ""
	show()
	_show_list("give")


func _give_target() -> Dictionary:
	for target in targets:
		if str(target["id"]) == give_target_id:
			return target
	return {}


## BattleSceneMenus: a left press on a marked cell holding a give target.
func select_give_target(id: String) -> void:
	if page != "give_target" or not targets.any(func(target): return str(target["id"]) == id):
		return
	give_target_id = id
	_show_give_inventories()


func _show_give_inventories() -> void:
	_show_list("give", _give_target())
	BattlePanelMotion.attach(self).slide_in()


## One pick in the recipient's window is the whole transfer (0x438c92 → 0x438d29 closes it): a
## held slot is swapped out, an empty one takes the item first-empty; PlayLoop checks and commits.
func _place_give_item(target_index: int, return_code: int) -> void:
	if page != "give_inventory" or selected_index < 0:
		return
	var target := _give_target()
	if not InventoryRules.exchange(source_unit["inventory"], selected_index, int(selected_item), target["inventory"], target_index, return_code)["ok"]:
		return
	give_target_index = target_index
	give_return_code = return_code
	give_requested.emit(give_target_id, selected_index, int(selected_item), target_index, return_code, give_revision)


## Equip／Drop window (player state 7 0x444185／state 8 0x4441ac → 0x43b4e0 mode 4／5, both
## built at 0x43b7fd: root flags 0x40004000, left WINDOW20 inventory, right WINDOW30 board; mode 5
## alone adds the 丟棄 button 0x43b280(0,0), template 148 BCMD08_1 centred at (285,387)).
## The held slot is [0x4c1ce4]; here it is a draft over the real inventory (`held_index`), and
## every change that reaches the rules is one PlayLoop command, refreshed back into the window.
func _show_hand_window(command: String) -> void:
	# 0x43ac10 builds the root with +0x94 = 4, so a fresh window starts on 屬性 until the pointer
	# is off the board; rebuilds after a change keep the page.
	if page != "hand": _attribute_shown = true
	_clear_page()
	operation = command
	page = "hand"
	BattleUISkin.clear_panel(page_root)
	var vitals := BattleVitals.new()
	vitals.position = Vector2(0, 14)
	page_root.add_child(vitals)
	vitals.show_unit(source_unit)
	var equipment := BattleEquipmentView.new()
	equipment_view = equipment
	equipment.interactive = true
	equipment.accepts_empty_slots = true
	equipment.slot_requested.connect(_hand_slot)
	page_root.add_child(equipment)
	equipment.show_unit(source_unit)
	_list_frame()
	var catalog := EquipmentCatalog.items()
	# The picked item left its slot (0x436e80 deletes and compacts); the rows show what remains,
	# packed from row 0 on the use window's eight fixed slots.
	for index in range(source_unit["inventory"].size()):
		var code := int(source_unit["inventory"][index])
		if index == held_index or code == 0:
			continue
		var details: Dictionary = catalog[str(code)]
		var button := _bag_button(details, str(code), index, rows.get_child_count(), _hand_colour(details))
		var caption: Label = button.get_node("Caption")
		button.mouse_entered.connect(_hover_row.bind(caption, _item_lines(details, str(code))))
		button.mouse_exited.connect(_hover_row.bind(null, []))
		button.pressed.connect(_hand_row.bind(index, code))
		rows.add_child(button)
	# 0x438c84: with an item held a pick on any row puts it back (first empty, 0x436e30).
	for index in range(8 - rows.get_child_count()):
		var empty := _empty_slot_button(-1, true)
		empty.name = "Empty_%d" % index
		empty.position = Vector2(0, rows.get_child_count() * LIST_ROW_HEIGHT)
		empty.size = LIST_ROW_SIZE
		rows.add_child(empty)
	# Remake-only, as on the use window: back button and count, OPT-GUIDE＝提示 only.
	var back := BattleUISkin.button(page_root, "返回", Vector2(252, 442), Vector2(113, 30))
	back.pressed.connect(cancel)
	back.visible = not GameOptions.is_original("OPT-GUIDE")
	var capacity := BattleUISkin.label(page_root, Vector2(20, 440), 15)
	capacity.text = "道具 %d / 8" % (8 - source_unit["inventory"].count(0))
	capacity.visible = back.visible
	if operation == "drop":
		drop_button = _drop_icon_button()
	_build_attribute_page()
	if held_code != 0:
		selected_item = str(held_code)
		_hold_selected_item()


## 0x439a0f..0x439a35 (WINDOW30 procedure, root flag 0x4000): each tick the pointer is off the
## board the left column goes to 道具 (root +0x94 = 1); an item held over the board turns it to
## 屬性 (+0x94 = 4: WINDOW21 and its nine live values, 0x448840 after every change). Over the
## board with an empty hand the page stays as it was.
func _build_attribute_page() -> void:
	attribute_page = Control.new()
	attribute_page.name = "AttributePage"
	attribute_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attribute_page.visible = _attribute_shown
	page_root.add_child(attribute_page)
	BattleUISkin.asset(attribute_page, "WINDOW21", BattleGrowthPanel.LEFT)
	var profile := CoreCombatRules.combat_profile_from_unit(source_unit)
	var live: Dictionary = StatusEffectRules.weakened_attributes(source_unit) if source_unit.get("status_counters") is Dictionary else profile
	var values := [int(live["str"]), int(live["dex"]), int(live["mind"]), int(live["con"]), int(profile["live_attack_damage"]), int(profile["live_defense"]), "%d%%" % int(profile["live_magic_attack"]), int(source_unit["live_speed"]), int(source_unit["move_point"])]
	for index in range(values.size()):
		var value := BattleUISkin.text(attribute_page, Vector2(BattleGrowthPanel.ATTRIBUTE_VALUE_X if index < 4 else BattleGrowthPanel.DERIVED_VALUE_X, BattleGrowthPanel.LEFT.y + 8 + index * BattleGrowthPanel.ROW_HEIGHT), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(60, BattleGrowthPanel.GLYPH_ROW))
		value.name = "Attribute_%d" % index
		value.text = str(values[index])


func _update_attribute_page() -> void:
	if page != "hand" or not is_instance_valid(attribute_page): return
	var over_board := Rect2(BattleEquipmentView.BOARD_AT, Vector2(376, 168)).has_point(page_root.get_local_mouse_position())
	if not over_board: _attribute_shown = false
	elif held_code != 0: _attribute_shown = true
	attribute_page.visible = _attribute_shown


## Name colour of a hand-window row (0x434d10 bag rows, 0x4c1cf8 == 1 in 裝備): a consumable, or
## a piece outside the unit's job mask (+0xa8), prints @2 red; anything else @1 white. 丟棄 takes
## the white branch for every row. An important item (+0xa0 bit 0x8000000) prints @6 ivory
## (255,255,222) on either branch (0x435e12／0x435e9d), in every mode.
func _hand_colour(details: Dictionary) -> Color:
	if bool(details.get("important", false)):
		return BattleUISkin.TEXT_IVORY
	if operation != "equip":
		return BattleUISkin.TEXT_WHITE
	if not int(details["type_code"]) in range(2, 7):
		return BattleUISkin.TEXT_RED
	var job := int(source_unit.get("growth_profile", {}).get("job_code", -1))
	if job == 1000 or (JobStatsRules.has_job(job) and (int(details.get("job_mask", 0)) & JobStatsRules.job_mask_bit(job)) != 0):
		return BattleUISkin.TEXT_WHITE
	return BattleUISkin.TEXT_RED


## Mode 5's 丟棄 (template 148 BCMD08_1, 42×42, origin (21,21)) centred at (285,387): x 0x11d,
## y 0x183 from 0x43b280(0,0); the caption sits under the icon as on the loot window's.
func _drop_icon_button() -> TextureButton:
	var button := TextureButton.new()
	button.name = "Button_drop"
	button.texture_normal = load(BattleUISkin.ROOT + "BCMD08_1.SHP.png")
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.position = DROP_BUTTON_CENTRE - Vector2(21, 21)
	page_root.add_child(button)
	var label := BattleUISkin.text(page_root, DROP_BUTTON_CENTRE + Vector2(-40, 13), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(80, 16))
	label.name = "Caption_drop"
	label.text = "丟棄"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE))
	button.pressed.connect(_hand_drop)
	return button


## A pick on a WINDOW20 row (0x438c53..0x438de7): empty hand takes the row's item (sound 399; the
## rows close its gap, 0x436e80); a held item goes back first-empty — the end of the compacted bag
## (0x436e30, sound 400), committed through hand_return_requested. The loop's full-bag hand
## trades places with the row instead (0x436ed0 full: row item to the hand, held piece to
## slot 8), committed through hand_swap_requested.
func _hand_row(index: int, code: int) -> void:
	if page != "hand":
		return
	if held_code != 0 and held_index < 0 and code != 0:
		selected_item = str(code)
		selected_index = index
		hand_swap_requested.emit(index, code, held_code)
	elif held_code != 0:
		_return_hand()
	elif code != 0:
		_set_hand(index, code)
		ui_sound_requested.emit("take_up")


## A pick on a WINDOW30 slot (0x439903..0x4399ec): held → setter 0x436f30 (-1 keeps the hand,
## no sound), the old piece comes into the hand (sound 400); empty hand → 0x437020 takes the
## piece off into the hand (sound 399). Both are committed through equipment_requested.
func _hand_slot(slot: String) -> void:
	if page != "hand":
		return
	selected_slot = slot
	if held_code != 0:
		selected_item = str(held_code)
		selected_index = held_index
		equipment_requested.emit(slot, held_index, held_code)
	elif EquipmentRules.equipped_code(source_unit["equipment"], slot) != 0:
		selected_item = "0"
		selected_index = -1
		equipment_requested.emit(slot, -1, 0)


## BattleSceneMenus after a committed change: the window stays up on the new unit and the piece
## that came off (old code) is in the hand, found where the rules put it (first empty) — or,
## with a full bag, in the loop's hand (`loop_held`).
func hand_equipment_changed(unit: Dictionary, old_code: int, loop_held := 0) -> void:
	source_unit = unit.duplicate(true)
	var index: int = source_unit["inventory"].rfind(old_code) if old_code != 0 and loop_held == 0 else -1
	held_index = index
	held_code = loop_held if loop_held != 0 else (old_code if index >= 0 else 0)
	ui_sound_requested.emit("put_down" if selected_item != "0" else "take_up")
	_show_hand_window(operation)


## Mode 5's 丟棄 (0x43aacb..0x43aae6): a held non-important item is cleared; an important one
## stays in the hand.
func _hand_drop() -> void:
	if page != "hand" or held_code == 0:
		return
	if InventoryRules.discard_error(held_code, EquipmentCatalog.items()) != "":
		return
	selected_item = str(held_code)
	selected_index = held_index
	drop_requested.emit(selected_item)


## BattleSceneMenus after a committed full-bag row trade: the row's item is the loop's hand
## (sound 400).
func hand_swapped(unit: Dictionary, held: int) -> void:
	source_unit = unit.duplicate(true)
	held_index = -1
	held_code = held
	ui_sound_requested.emit("put_down")
	_show_hand_window(operation)


## BattleSceneMenus after a committed discard: the hand is empty, the window stays up.
func hand_item_dropped(unit: Dictionary) -> void:
	source_unit = unit.duplicate(true)
	held_index = -1
	held_code = 0
	_show_hand_window(operation)


func _return_hand() -> void:
	selected_item = str(held_code)
	selected_index = held_index
	hand_return_requested.emit(held_index, held_code)


## BattleSceneMenus after a committed put-back: the hand is empty, the item is last in the bag
## (the use pick's cancel reopens the use window instead).
func hand_item_returned(unit: Dictionary) -> void:
	if page == "target":
		source_unit = unit.duplicate(true)
		_show_list(operation)
		BattlePanelMotion.attach(self).slide_in()
		return
	hand_item_dropped(unit)
	ui_sound_requested.emit("put_down")


func _set_hand(index: int, code: int) -> void:
	held_index = index
	held_code = code
	_show_hand_window(operation)


## Modal input while the stack is up: right click / Esc step back one page (`cancel`)
## (BattleSceneRuntime.modal_panels dispatch); during the use pick pointer moves and left
## presses go to use_pick_pointer; every other event is swallowed.
func handle_input(event: InputEvent) -> bool:
	if picking and event is InputEventMouseMotion:
		use_pick_pointer.emit(event.position, false)
	elif picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		use_pick_pointer.emit(event.position, true)
		get_viewport().set_input_as_handled()
		return true
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		cancel()
		get_viewport().set_input_as_handled()
		return true
	return false


func cancel() -> void:
	if page == "give_inventory":
		# Closing the recipient's window keeps the held item, which 116 returns to the giver (provisional).
		_show_list("give")
	elif page == "give_target":
		# 0x444d3b..0x444d73: the held item goes back and the giver's window reopens (state 110).
		_show_list("give")
		BattlePanelMotion.attach(self).slide_in()
	elif page == "inventory" and operation == "give":
		# 0x444bff: right click on the giver's window ends the session.
		give_finished.emit(give_revision)
	elif page == "target":
		# 0x444a5c..0x444a94: right click puts the held item (lifted out of its row by the pick,
		# 0x437020) back first-empty (0x436e30) — the bag's end — and reopens the use window
		# (state 102), silently; BattleSceneMenus.return_held_item commits it.
		hand_return_requested.emit(selected_index, int(selected_item))
	elif page == "hand" and held_code != 0:
		# 0x438868: right click puts the held item back (first empty) and keeps the window.
		_return_hand()
	elif page in ["inventory", "hand"]:
		# 0x43896b → root 3 → parent 76→77, 0x444c19 writes 3: the item sub-menu reopens.
		_show_commands()
	else:
		hide()

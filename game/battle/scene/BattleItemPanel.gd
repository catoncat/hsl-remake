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
##   layout: remake-invented (scrollable lists, preview rows)
##   strings: resource-derived content/generated/hsl/equipment/items.json
##   strings: resource-derived content/imported/hsl/chapter01/consumables.json
##   strings: remake-invented (tooltips, 沒有道具, 道具 N / 8 — OPT-GUIDE＝提示 only)
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
## take_up (399) when an item comes into the hand, put_down (400) when the hand places it.
signal ui_sound_requested(event: String)
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
var rows: VBoxContainer
var menu: Control
var page_root: Control
var source_unit: Dictionary = {}
var attack_source: Dictionary = {}
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
var held_index := -1
var held_code := 0
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


func show_inventory(unit: Dictionary, definitions: Dictionary, recipients: Array, at: Vector2, capabilities: Dictionary) -> void:
	source_unit = unit.duplicate(true)
	attack_source = capabilities.duplicate(true)
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
	BattleUISkin.board(page_root, "WINDOW20", Vector2(12, 174))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 180)
	scroll.size = Vector2(207, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_root.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	var catalog := EquipmentCatalog.items()
	for index in range(unit["inventory"].size()):
		var code := str(int(unit["inventory"][index]))
		if code == "0":
			# 0x438cbf..0x438d0c: a pick on an empty slot inserts into the first empty slot.
			if placing and index == unit["inventory"].find(0):
				rows.add_child(_empty_slot_button(index))
			continue
		var details: Dictionary = catalog[code]
		var button := Button.new()
		button.name = "Item_%s_%d" % [code, index]
		button.text = str(details["name"])
		button.set_meta("item_code", code)
		button.set_meta("inventory_index", index)
		button.custom_minimum_size = Vector2(195, 32)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_hover_color", Color.YELLOW)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxEmpty.new()
			style.content_margin_left = 43
			button.add_theme_stylebox_override(state, style)
		var art := BattleUISkin.asset(button, str(details["icon"]), Vector2(3, 0))
		art.name = "OriginalConsumable"
		button.disabled = operation == "use" and ItemUseRules.definition_error(items.get(code, {})) != ""
		if hints and operation == "use" and not button.disabled:
			button.tooltip_text = preload("res://game/battle/scene/BattleItemText.gd").description(items[code])
		button.pressed.connect(_place_give_item.bind(index, int(code)) if placing else _select_item.bind(code, index))
		rows.add_child(button)
	if hints and rows.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "沒有道具"
		empty.add_theme_font_size_override("font_size", 16)
		rows.add_child(empty)
	var back := BattleUISkin.button(page_root, "返回", Vector2(502, 442), Vector2(113, 30))
	back.pressed.connect(cancel)
	var capacity := BattleUISkin.label(page_root, Vector2(20, 440), 15)
	capacity.text = "道具 %d / 8" % (8 - unit["inventory"].count(0))
	capacity.visible = hints
	if placing:
		_hold_selected_item()


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


func _process(_delta: float) -> void:
	if visible and is_instance_valid(held_icon):
		_follow_pointer()


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
	BattleUISkin.board(page_root, "WINDOW20", Vector2(12, 174))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 180)
	scroll.size = Vector2(207, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_root.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	var catalog := EquipmentCatalog.items()
	# The picked item left its slot (0x436e80 deletes and compacts); the rows show what remains.
	for index in range(source_unit["inventory"].size()):
		var code := int(source_unit["inventory"][index])
		if index == held_index or code == 0:
			continue
		var details: Dictionary = catalog[str(code)]
		var button := Button.new()
		button.name = "Item_%d_%d" % [code, index]
		button.text = str(details["name"])
		button.set_meta("item_code", str(code))
		button.set_meta("inventory_index", index)
		button.custom_minimum_size = Vector2(195, 32)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_hover_color", Color.YELLOW)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxEmpty.new()
			style.content_margin_left = 43
			button.add_theme_stylebox_override(state, style)
		BattleUISkin.asset(button, str(details["icon"]), Vector2(3, 0)).name = "OriginalConsumable"
		button.pressed.connect(_hand_row.bind(index, code))
		rows.add_child(button)
	# 0x438c84: with an item held a pick on any row puts it back (first empty, 0x436e30).
	for index in range(8 - rows.get_child_count()):
		var empty := _empty_slot_button(-1, true)
		empty.name = "Empty_%d" % index
		rows.add_child(empty)
	var back := BattleUISkin.button(page_root, "返回", Vector2(502, 442), Vector2(113, 30))
	back.pressed.connect(cancel)
	var capacity := BattleUISkin.label(page_root, Vector2(20, 440), 15)
	capacity.text = "道具 %d / 8" % (8 - source_unit["inventory"].count(0))
	capacity.visible = not GameOptions.is_original("OPT-GUIDE")
	if operation == "drop":
		drop_button = _drop_icon_button()
	if held_code != 0:
		selected_item = str(held_code)
		_hold_selected_item()


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
	label.text = "丟棄"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE))
	button.pressed.connect(_hand_drop)
	return button


## A pick on a WINDOW20 row (0x438c53..0x438de7): empty hand takes the row's item (sound 399);
## a held item goes back first-empty (sound 400). The real inventory is untouched either way.
func _hand_row(index: int, code: int) -> void:
	if page != "hand":
		return
	if held_code != 0:
		_set_hand(-1, 0)
		ui_sound_requested.emit("put_down")
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
## that came off (old code) is in the hand, found where the rules put it (first empty).
func hand_equipment_changed(unit: Dictionary, old_code: int) -> void:
	source_unit = unit.duplicate(true)
	var index: int = source_unit["inventory"].rfind(old_code) if old_code != 0 else -1
	held_index = index
	held_code = old_code if index >= 0 else 0
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


## BattleSceneMenus after a committed discard: the hand is empty, the window stays up.
func hand_item_dropped(unit: Dictionary) -> void:
	source_unit = unit.duplicate(true)
	held_index = -1
	held_code = 0
	_show_hand_window(operation)


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
		# 0x444a5c: right click returns the held item (0x436e30) and reopens the use window (state 102).
		_show_list(operation)
		BattlePanelMotion.attach(self).slide_in()
	elif page == "hand" and held_code != 0:
		# 0x438868: right click puts the held item back (first empty) and keeps the window.
		_set_hand(-1, 0)
	elif page in ["inventory", "hand"]:
		# 0x43896b → root 3 → parent 76→77, 0x444c19 writes 3: the item sub-menu reopens.
		_show_commands()
	else:
		hide()

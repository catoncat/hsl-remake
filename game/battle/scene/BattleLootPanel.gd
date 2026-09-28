extends Control
## Original 獲得物品 window (status mode 0xb, docs/evidence_packets/static_reverse/original_getitem_window.md).
## Immutable snapshots and one uncommitted held item only. All transfers use PlayLoop.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##     (five button semantics)
##   rules: remake-invented (a lifted bag item goes back to its slot from the list／another slot)
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#16
##     (frame_003／frame_006 held-item and green hover)
##   layout: remake-invented (scroll arrows for more than five codes; disabled 離開 while holding)
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   audio: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
signal claim_requested(request: Dictionary)
signal finish_requested(request: Dictionary)
signal discard_requested(request: Dictionary)
signal store_requested(request: Dictionary)
signal cue_requested(event: String)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattleItemText = preload("res://game/battle/scene/BattleItemText.gd")
## Recipient bag: WINDOW20 at (12,168), eight 32 px rows; icon anchor (44, 184+32i), name (68, 176+32i).
const BAG_AT := Vector2(12, 168)
const BAG_ROW := 32
## Loot list: WINDOW90 at (252,168); title centred at y+10; five rows from y+43+8, icon anchor
## (x+32, row+6), name x+56, fourteen-cell name field then a seven-cell count ending at x+332.
const LIST_AT := Vector2(252, 168)
const LIST_TOP := 51
const LIST_ROW := 32
const VISIBLE_ROWS := 5
const COUNT_RIGHT := 332
## Description WINDOW50 at (252,390): 15 px lines from (x+8, y+12), row 16, centred in 360 px.
const DESCRIPTION_AT := Vector2(252, 390)
## `$:` WINDOW40 at (20,442); nine-cell amount ends at x=208. Buttons BCMD08/15/14 centred at y=429.
const GOLD_AT := Vector2(20, 442)
const BUTTON_CENTRES := {"drop": 285, "storage": 346, "exit": 468}
const BUTTON_Y := 429
var rows: Array[Button] = []
var _arrows: Array[Button] = []
var slots: Array[Button] = []
var finish_button: TextureButton
var drop_button: TextureButton
var storage_button: TextureButton
var button_labels: Dictionary = {}
var description_box: Control
var hand_icon: TextureRect
var vitals: Control
var _state: Dictionary = {}
var _actors: Array = []
var _catalog: Dictionary = {}
var _consumables: Dictionary = {}
var _recipient := ""
var _hand: Dictionary = {}
var _groups: Array = []
var _scroll := 0
var _epoch := 0
var _key := ""
var _pointer := Vector2.ZERO


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


## The held item is drawn at the cursor (0x414c00 draws it after the window). Motion is read from the
## input stream so pushed test input and the real pointer both move it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and visible:
		_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if hand_icon != null and hand_icon.visible: hand_icon.position = _pointer - hand_icon.get_meta("origin", Vector2.ZERO)


func close() -> void:
	_epoch += 1
	_key = ""
	_hand = {}
	if hand_icon != null: hand_icon.hide()
	hide()


func accepts(request: Dictionary) -> bool:
	return visible and request.get("epoch") == _epoch and request.get("sequence") == _state.get("sequence") and request.get("revision") == _state.get("revision")


func holding() -> bool:
	return not _hand.is_empty()


func show_rewards(state: Dictionary, actors: Array, catalog: Dictionary, gold: int, recipient_id: String = "", consumables: Dictionary = {}) -> void:
	var key := "%d:%d:%s" % [int(state["sequence"]), int(state["revision"]), recipient_id]
	if visible and key == _key: return
	_key = key
	_state = state.duplicate(true)
	_actors = actors.duplicate(true)
	_catalog = catalog
	_consumables = consumables
	var available: Array = _actors.map(func(actor): return str(actor["id"]))
	_recipient = recipient_id if available.has(recipient_id) else ("" if available.is_empty() else str(available[0]))
	_hand = {}
	_epoch += 1
	for child in get_children(): remove_child(child); child.queue_free()
	hand_icon = null
	description_box = null
	rows.clear()
	_arrows.clear()
	slots.clear()
	BattleUISkin.clear_panel(self)
	_build_bag()
	_build_list()
	_build_gold(gold)
	_build_buttons()
	description_box = Control.new()
	description_box.position = DESCRIPTION_AT
	description_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BattleUISkin.board(description_box, "WINDOW50", Vector2.ZERO)
	description_box.hide()
	add_child(description_box)
	hand_icon = TextureRect.new()
	# GameCursor hides the sceptre while this held item shows (0x430310).
	hand_icon.add_to_group("game_cursor_held_items")
	hand_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hand_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_icon.hide()
	add_child(hand_icon)
	vitals = preload("res://game/battle/scene/BattleVitals.gd").new()
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	var actor := _actor()
	if not actor.is_empty(): vitals.show_unit(actor)
	_refresh_buttons()
	show()


func _actor() -> Dictionary:
	for actor in _actors:
		if actor["id"] == _recipient: return actor
	return {}


func _build_bag() -> void:
	BattleUISkin.board(self, "WINDOW20", BAG_AT)
	var actor := _actor()
	for index in range(8):
		var code := 0 if actor.is_empty() else int(actor["inventory"][index])
		var button := _row_button(BAG_AT + Vector2(8, 8 + index * BAG_ROW), Vector2(208, BAG_ROW))
		button.name = "Bag_%d" % index
		button.set_meta("inventory_index", index)
		button.set_meta("item_code", code)
		var icon := Control.new()
		icon.name = "Content"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		if code > 0:
			BattleUISkin.anchored_asset(icon, str(_catalog[str(code)]["icon"]), Vector2(24, 8))
			var label := BattleUISkin.text(icon, Vector2(48, 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(160, BAG_ROW))
			label.text = str(_catalog[str(code)]["name"])
			button.mouse_entered.connect(_show_description.bind(code, label))
			button.mouse_exited.connect(_hide_description.bind(label))
		var epoch := _epoch
		button.pressed.connect(func():
			if not visible or epoch != _epoch: return
			if not holding():
				if code > 0: _lift(index, code)
			elif _hand.has("slot"): cancel()
			else: _place(index, code))
		slots.append(button)


func _build_list() -> void:
	BattleUISkin.board(self, "WINDOW90", LIST_AT)
	var title := BattleUISkin.text(self, LIST_AT + Vector2(0, 10), BattleUISkin.TEXT_IVORY, BattleUISkin.FONT_BODY, Vector2(375, 24))
	title.text = "獲得物品"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rebuild_rows()


## Rows are the pending pool minus the held item, grouped by code like the original (code, qty) pairs;
## taking the last of a code removes its row and the rows below shift up (0x44f430).
func _rebuild_rows() -> void:
	for row in rows + _arrows: remove_child(row); row.queue_free()
	rows.clear()
	_arrows.clear()
	_groups = []
	for item in _state["pending"]:
		if holding() and str(item["id"]) == str(_hand.get("entry_id", "")): continue
		var code := int(item["code"])
		var group: Dictionary = {}
		for candidate in _groups:
			if int(candidate["code"]) == code: group = candidate
		if group.is_empty():
			group = {"code": code, "entry_ids": []}
			_groups.append(group)
		group["entry_ids"].append(str(item["id"]))
	_scroll = clampi(_scroll, 0, maxi(0, _groups.size() - VISIBLE_ROWS))
	var job := int(_actor().get("growth_profile", {}).get("job_code", -1))
	for index in range(mini(VISIBLE_ROWS, _groups.size() - _scroll)):
		var group: Dictionary = _groups[_scroll + index]
		var code := int(group["code"])
		var details: Dictionary = _catalog[str(code)]
		var button := _row_button(LIST_AT + Vector2(8, LIST_TOP + index * LIST_ROW), Vector2(340, LIST_ROW))
		button.name = "Loot_%d" % code
		button.set_meta("item_code", code)
		button.set_meta("entry_id", group["entry_ids"][0])
		BattleUISkin.anchored_asset(button, str(details["icon"]), Vector2(24, 6))
		var usable := job >= 80 and job <= 100 and (int(details["job_mask"]) & (1 << (job - 80))) != 0
		# 0x414c00 row colour: important @6, usable by the recipient's job @1, otherwise @2.
		var color := BattleUISkin.TEXT_IVORY if bool(details["important"]) else (BattleUISkin.TEXT_WHITE if usable else BattleUISkin.TEXT_RED)
		var label := BattleUISkin.text(button, Vector2(48, 0), color, BattleUISkin.FONT_BODY, Vector2(168, LIST_ROW))
		label.text = str(details["name"])
		label.set_meta("base_color", color)
		var count := BattleUISkin.text(button, Vector2(COUNT_RIGHT - 8 - 84, 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(84, LIST_ROW))
		count.text = str(group["entry_ids"].size())
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.mouse_entered.connect(_show_description.bind(code, label))
		button.mouse_exited.connect(_hide_description.bind(label))
		var epoch := _epoch
		button.pressed.connect(func():
			if not visible or epoch != _epoch: return
			if holding(): cancel()
			elif not bool(_catalog[str(group["code"])]["important"]): _take(group))
		rows.append(button)
	if _groups.size() > VISIBLE_ROWS:
		for step in [-1, 1]:
			var arrow := _row_button(LIST_AT + Vector2(351, 0 if step < 0 else 200), Vector2(24, 20))
			arrow.name = "Scroll_up" if step < 0 else "Scroll_down"
			arrow.pressed.connect(func():
				_scroll = clampi(_scroll + step, 0, _groups.size() - VISIBLE_ROWS)
				_rebuild_rows())
			_arrows.append(arrow)
	if hand_icon != null: move_child(hand_icon, get_child_count() - 1)


func _build_gold(gold: int) -> void:
	BattleUISkin.board(self, "WINDOW40", GOLD_AT)
	var amount := BattleUISkin.text(self, GOLD_AT + Vector2(80, 4), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(108, 24))
	amount.text = str(gold)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_buttons() -> void:
	drop_button = _icon_button("drop", "BCMD08_1", "丟棄")
	storage_button = _icon_button("storage", "BCMD15_1", "倉庫")
	finish_button = _icon_button("exit", "BCMD14_1", "離開")
	var epoch := _epoch
	# 丟棄 drops only the held item (never an important one); 倉庫 stores the held item; 離開 needs
	# an empty hand and stores whatever is left in the pool (0x42aad0).
	drop_button.pressed.connect(func():
		if not visible or epoch != _epoch or drop_button.disabled or not holding(): return
		discard_requested.emit(_hand_request()))
	storage_button.pressed.connect(func():
		if not visible or epoch != _epoch or not holding(): return
		store_requested.emit(_hand_request()))
	finish_button.pressed.connect(func():
		if not visible or epoch != _epoch or holding(): return
		var request := _request({"store_rest": true})
		if accepts(request): finish_requested.emit(request))


func _icon_button(key: String, resource: String, caption: String) -> TextureButton:
	var button := TextureButton.new()
	button.name = "Button_" + key
	button.texture_normal = load(BattleUISkin.ROOT + resource + ".SHP.png")
	button.position = Vector2(BUTTON_CENTRES[key] - 21, BUTTON_Y - 21)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(button)
	# 0x43a640 draws the 15 px caption centred under the icon at centre_y + 13, yellow while hovered.
	var label := BattleUISkin.text(self, Vector2(BUTTON_CENTRES[key] - 40, BUTTON_Y + 13), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(80, 16))
	label.name = "Caption_" + key
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_meta("caption", caption)
	button_labels[key] = label
	button.mouse_entered.connect(func(): if not button.disabled: label.add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE))
	return button


func _row_button(at: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(button)
	return button


func _refresh_buttons() -> void:
	_set_enabled(drop_button, holding() and not bool(_catalog[str(_hand["code"])]["important"]))
	_set_enabled(storage_button, holding())
	_set_enabled(finish_button, not holding())


func _set_enabled(button: TextureButton, enabled: bool) -> void:
	button.disabled = not enabled
	button.self_modulate = Color.WHITE if enabled else Color(0.45, 0.45, 0.45)


func _take(group: Dictionary) -> void:
	_grab({"entry_id": str(group["entry_ids"][0]), "code": int(group["code"])})
	cue_requested.emit("take_up")


## An empty hand clicking a bag item lifts it (0x436e80, sound 399); the slot shows empty until the
## item is dropped, stored or put back.
func _lift(slot: int, code: int) -> void:
	_grab({"slot": slot, "code": code})
	slots[slot].get_node("Content").hide()
	cue_requested.emit("take_up")


## After an exchange the displaced bag item (now pool entry `entry_id`) is in the hand (0x42923b).
func hold_entry(entry_id: String) -> void:
	for item in _state.get("pending", []):
		if str(item["id"]) == entry_id: _grab({"entry_id": entry_id, "code": int(item["code"])}); return


func _grab(hand: Dictionary) -> void:
	_hand = hand
	var code := int(hand["code"])
	# Sound 399 TAKEUP01: the picked item travels with the cursor; the list row loses one count.
	var record: Dictionary = BattleUISkin.data()["assets"][str(_catalog[str(code)]["icon"])]
	BattleUISkin.show_shape(hand_icon, BattleUISkin.texture(str(_catalog[str(code)]["icon"])))
	hand_icon.set_meta("origin", Vector2(float(record["draw_origin"][0]), float(record["draw_origin"][1])))
	hand_icon.position = _pointer - hand_icon.get_meta("origin")
	hand_icon.show()
	description_box.hide()
	_rebuild_rows()
	_refresh_buttons()


## Original: clicking the list while holding puts the item back into the pool; a lifted bag item
## goes back to its slot (remake).
func cancel() -> void:
	if not holding(): return
	if _hand.has("slot"): slots[int(_hand["slot"])].get_node("Content").show()
	_hand = {}
	hand_icon.hide()
	_rebuild_rows()
	_refresh_buttons()
	cue_requested.emit("put_down")


## Original right click / Esc while holding (0x438160 root case 1): drop into the first free bag slot.
func quick_place() -> void:
	if _hand.has("slot"): cancel()
	elif holding(): _place(-1, 0)


func _place(slot: int, expected_code: int) -> void:
	claim_requested.emit(_request({"entry_id": _hand["entry_id"], "recipient_id": _recipient, "slot": slot, "expected_code": expected_code}))


func _hand_request() -> Dictionary:
	if _hand.has("slot"):
		return _request({"entry_id": "", "recipient_id": _recipient, "slot": int(_hand["slot"]), "expected_code": int(_hand["code"])})
	return _request({"entry_id": str(_hand["entry_id"]), "recipient_id": "", "slot": -1, "expected_code": 0})


func _request(extra: Dictionary) -> Dictionary:
	var result := {"epoch": _epoch, "sequence": int(_state["sequence"]), "revision": int(_state["revision"])}
	result.merge(extra)
	return result


func _show_description(code: int, label: Label) -> void:
	label.add_theme_color_override("font_color", BattleUISkin.TEXT_GREEN)
	for child in description_box.get_children():
		if child is Label: description_box.remove_child(child); child.queue_free()
	var lines: Array = _description_lines(code)
	for index in range(mini(lines.size(), 4)):
		var row := BattleUISkin.text(description_box, Vector2(8, 12 + index * 16), BattleUISkin.TEXT_GREEN if index == 0 else BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(360, 16))
		row.text = str(lines[index])
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_box.show()


func _hide_description(label: Label) -> void:
	label.add_theme_color_override("font_color", label.get_meta("base_color", BattleUISkin.TEXT_WHITE))
	description_box.hide()


func _description_lines(code: int) -> Array:
	var details: Dictionary = _catalog[str(code)]
	if int(details["type_code"]) in range(2, 7):
		return BattleEquipmentView.description_lines(details)
	var lines: Array = [str(details["name"]), "可使用"]
	var definition: Dictionary = _consumables.get(str(code), {})
	if not definition.is_empty(): lines.append_array(BattleItemText.description(definition).split("\n"))
	return lines

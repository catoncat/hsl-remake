extends Control
## Original 獲得物品 window (status mode 0xb, docs/evidence_packets/static_reverse/original_getitem_window.md).
## Immutable snapshots and the held item only. All transfers use PlayLoop.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##     (five buttons; held + bag row 0x438c84 first-empty or full swap; lift 0x436e80, pool 0x44f2d0)
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##     (0x446060 WIN06BAR scroll bar, five rows, keys 0x445f00; 0x43a640 buttons dim only while pressed)
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#16
##     (frame_003／frame_006 held-item and green hover)
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   audio: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
signal claim_requested(request: Dictionary)
signal finish_requested(request: Dictionary)
signal discard_requested(request: Dictionary)
signal store_requested(request: Dictionary)
signal return_requested(request: Dictionary)
signal pool_requested(request: Dictionary)
signal cue_requested(event: String)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleItemText = preload("res://game/battle/scene/BattleItemText.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattleSkillScrollBar = preload("res://game/battle/scene/BattleSkillScrollBar.gd")
const JobStatsRules = preload("res://game/sim/JobStatsRules.gd")
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
## Description WINDOW50 at (249,390): 0x436d70 draws it at camera + (252,349), y + 41 with
## [0x4c1cbc] bit 0 and x − 3 without bit 1 (0x436dbd..0x436dcb); in battle 0x43b4e0 zeroes the
## flags (0x43b4ea) and the 獲得物品 mode sets bit 0 alone (0x43bda4). 15 px lines from (x+8, y+12),
## row 16, centred in 360 px.
const DESCRIPTION_AT := Vector2(249, 390)
## `$:` WINDOW40 at (20,442); nine-cell amount ends at x=208. Buttons BCMD08/15/14 centred at y=429.
const GOLD_AT := Vector2(20, 442)
const BUTTON_CENTRES := {"drop": 285, "storage": 346, "exit": 468}
const BUTTON_Y := 429
## 0x43a640 case 2 → 3 marks a pressed button +0 0x10000000, +0x28 = 0x1082 (0x43a993), the dark
## BattleStatusPanel draws on its current-page button (same flag and colour, 0x43a8fb).
const PRESSED_DARK := Color(0.45, 0.45, 0.45)
var rows: Array[Button] = []
var scroll_bar: BattleSkillScrollBar
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
## BattlePanelMotion draws the pending list off its Controls (open slide, close snapshot): the
## rows' own enter／exit signals wait and `drawn_hover` places the hover.
var _drawn := false
## The pending row `drawn_hover` last described (−1: none) and the box it used. Landed, the panel
## keeps it until the pointer leaves that row (`_input`): a row that shows up under a still
## pointer gets no enter, so it would get no exit either.
var _drawn_row := -1
var _drawn_box: Control


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


## The held item is drawn at the cursor (the cursor process draws it at the mouse, 0x4304d5 → 0x430310, with no window offset). Motion is read from the
## input stream so pushed test input and the real pointer both move it; the pointer is kept while
## hidden too, for the close slide's `drawn_hover`.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer = get_global_transform_with_canvas().affine_inverse() * event.position
		if visible and hand_icon != null and hand_icon.visible: hand_icon.position = _pointer - hand_icon.get_meta("origin", Vector2.ZERO)
		if visible and not _drawn and _drawn_row >= 0 and _drawn_row < rows.size() and is_instance_valid(rows[_drawn_row]) and not Rect2(rows[_drawn_row].position, rows[_drawn_row].size).has_point(_pointer):
			if is_instance_valid(_drawn_box): _drawn_box.hide()
			_forget_drawn_row()
	elif visible and _drawn and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Sliding in, a pending row answers where it is drawn (0x414c00 takes clicks in every
		# state, on the window's rect of the last tick); the rows' Controls do not.
		var point := get_global_transform_with_canvas().affine_inverse() * (event as InputEventMouseButton).position
		var hit := _drawn_row_at(point)
		var covered := hit >= 0
		for row in rows:
			if is_instance_valid(row) and Rect2(row.position, row.size).has_point(point): covered = true
		if covered: get_viewport().set_input_as_handled()
		if hit >= 0 and _scroll + hit < _groups.size(): _press_row(_groups[_scroll + hit])
	elif visible and _drawn and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Remake convenience, not an original input (0x43a640 only reads the three buttons): right
		# click is 離開 with an empty hand, like the right-click cancel of the other windows. With an
		# item in hand it does nothing, as the button would.
		get_viewport().set_input_as_handled()
		_finish()


## 離開: needs an empty hand and stores whatever is left in the pool (0x42aad0).
func _finish() -> void:
	if not visible or holding(): return
	var request := _request({"store_rest": true})
	if accepts(request): finish_requested.emit(request)


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


## The window has landed (BattlePanelMotion has no open slide left). The root window's right-click
## claim (case 1 0x438811) and the bag rows (mode 2 page 1, 0x438b9c: this window's +0x8c == 1
## at 0x438c16／0x438c1d, else the click at 0x438c78–0x438c84 is skipped) wait for it; the pending
## list takes clicks in every state (0x414c00).
func landed() -> bool:
	var motion := _motion()
	return motion == null or not motion.opening()


func _motion() -> Node:
	for child in get_children(true):
		if child.has_method("rescan"): return child
	return null


## Pending row under `point` where BattlePanelMotion draws it this tick (−1: none).
func _drawn_row_at(point: Vector2) -> int:
	var motion := _motion()
	for index in rows.size():
		if not is_instance_valid(rows[index]): continue
		var offset: Variant = motion.drawn_offset(rows[index]) if motion != null else Vector2.ZERO
		if offset is Vector2 and Rect2(rows[index].position + offset, rows[index].size).has_point(point): return index
	return -1


func show_rewards(state: Dictionary, actors: Array, catalog: Dictionary, gold: int, recipient_id: String = "", consumables: Dictionary = {}) -> void:
	var key := "%d:%d:%s" % [int(state["sequence"]), int(state["revision"]), recipient_id]
	if visible and key == _key: return
	_key = key
	_state = state.duplicate(true)
	_actors = actors.duplicate(true)
	_catalog = catalog
	_consumables = consumables
	# Shown already (a claim, a new recipient): the rebuilt parts carry on the window's motion.
	var shown := visible
	var available: Array = _actors.map(func(actor): return str(actor["id"]))
	_recipient = recipient_id if available.has(recipient_id) else ("" if available.is_empty() else str(available[0]))
	_hand = {}
	_epoch += 1
	for child in get_children(): remove_child(child); child.queue_free()
	hand_icon = null
	description_box = null
	vitals = null # built last: the row rebuilds leave the motion to the end of the build
	rows.clear()
	scroll_bar = null
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
	BattleUISkin.in_place(description_box)
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
	if shown: _rejoin_motion()
	show()


## BattlePanelMotion (an internal child the settlement controller attaches): parts rebuilt while
## the window shows join its open slide where it is and the new shade keeps its level.
func _rejoin_motion() -> void:
	for child in get_children(true):
		if child.has_method("rescan"): child.rescan()


func _actor() -> Dictionary:
	for actor in _actors:
		if actor["id"] == _recipient: return actor
	return {}


func _build_bag() -> void:
	BattleUISkin.board(self, "WINDOW20", BAG_AT)
	_rebuild_bag()


## A lifted item has left the bag (0x436e80 deletes the slot and closes the gap): the rows show what
## remains packed from row 0; each row keeps the real slot it stands for.
func _rebuild_bag() -> void:
	for slot in slots: remove_child(slot); slot.queue_free()
	slots.clear()
	var actor := _actor()
	var held := int(_hand.get("slot", -1))
	var entries: Array = []
	if not actor.is_empty():
		for index in range(actor["inventory"].size()):
			if index != held and int(actor["inventory"][index]) != 0: entries.append([index, int(actor["inventory"][index])])
	while entries.size() < 8: entries.append([-1, 0])
	for row in range(8):
		var index: int = entries[row][0]
		var code: int = entries[row][1]
		var button := _row_button(BAG_AT + Vector2(8, 8 + row * BAG_ROW), Vector2(208, BAG_ROW))
		button.name = "Bag_%d" % row
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
			button.mouse_entered.connect(_show_description.bind(code, label, true))
			button.mouse_exited.connect(_hide_description.bind(label))
		var epoch := _epoch
		button.pressed.connect(func():
			if not visible or epoch != _epoch or not landed(): return
			if not holding():
				if code > 0: _lift(index, code)
			elif _hand.has("slot"): return_requested.emit(_hand_request())
			elif _bag_full(): _place(index, code)
			else: _place(-1, 0))
		slots.append(button)
	if hand_icon != null: move_child(hand_icon, get_child_count() - 1)
	if visible and vitals != null: _rejoin_motion()


func _build_list() -> void:
	BattleUISkin.board(self, "WINDOW90", LIST_AT)
	var title := BattleUISkin.text(self, LIST_AT + Vector2(0, 10), BattleUISkin.TEXT_IVORY, BattleUISkin.FONT_BODY, Vector2(375, 24))
	title.text = "獲得物品"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 0x414c00 first tick: 0x446060 hangs the bar at the window's right edge − 24, five rows,
	# scroll start *0x4c1a5c = 0, range = pool count (0x445d70).
	_scroll = 0
	scroll_bar = BattleSkillScrollBar.new(LIST_AT, "WIN06BAR", VISIBLE_ROWS, 375 - 24)
	scroll_bar.scrolled.connect(func(pos: int):
		_scroll = pos
		_rebuild_rows())
	add_child(scroll_bar)
	_rebuild_rows()


## Rows are the pending pool minus the held item, grouped by code like the original (code, qty) pairs;
## taking the last of a code removes its row and the rows below shift up (0x44f430).
func _rebuild_rows() -> void:
	if _drawn_row >= 0:
		if is_instance_valid(_drawn_box): _drawn_box.hide()
		_drawn_row = -1
	for row in rows: remove_child(row); row.queue_free()
	rows.clear()
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
		var usable := JobStatsRules.has_job(job) and (int(details["job_mask"]) & JobStatsRules.job_mask_bit(job)) != 0
		# 0x414c00 row colour: important @6, usable by the recipient's job @1, otherwise @2.
		var color := BattleUISkin.TEXT_IVORY if bool(details["important"]) else (BattleUISkin.TEXT_WHITE if usable else BattleUISkin.TEXT_RED)
		var label := BattleUISkin.text(button, Vector2(48, 0), color, BattleUISkin.FONT_BODY, Vector2(168, LIST_ROW))
		label.text = str(details["name"])
		label.set_meta("base_color", color)
		button.set_meta("label", label)
		var count := BattleUISkin.text(button, Vector2(COUNT_RIGHT - 8 - 84, 0), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(84, LIST_ROW))
		count.text = str(group["entry_ids"].size())
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.mouse_entered.connect(func(): if not _drawn: _show_description(code, label, false))
		button.mouse_exited.connect(func(): if not _drawn: _hide_description(label))
		var epoch := _epoch
		button.pressed.connect(func():
			# Sliding in, `_input` answers presses on the rows' rects and where they are drawn.
			if not visible or epoch != _epoch: return
			_press_row(group))
		rows.append(button)
	if scroll_bar != null: scroll_bar.resize(_groups.size())
	if hand_icon != null: move_child(hand_icon, get_child_count() - 1)
	if visible and vitals != null: _rejoin_motion()


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
	# 0x43a640 case 2: every press sounds 398 ACCEPT01 whatever the hand (_icon_button); the
	# release (case 3) then does nothing where it does not apply. 丟棄 drops only the held item
	# (never an important one); 倉庫 stores the held item; 離開 needs an empty hand and stores
	# whatever is left in the pool (0x42aad0).
	drop_button.pressed.connect(func():
		if not visible or epoch != _epoch or drop_button.get_meta("left", false): return
		if not holding() or bool(_catalog[str(_hand["code"])]["important"]): return
		discard_requested.emit(_hand_request()))
	storage_button.pressed.connect(func():
		if not visible or epoch != _epoch or storage_button.get_meta("left", false): return
		if not holding(): return
		store_requested.emit(_hand_request()))
	finish_button.pressed.connect(func():
		if not visible or epoch != _epoch or finish_button.get_meta("left", false): return
		if holding(): return
		var request := _request({"store_rest": true})
		if accepts(request): finish_requested.emit(request))


func _icon_button(key: String, resource: String, caption: String) -> TextureButton:
	var button := TextureButton.new()
	button.name = "Button_" + key
	button.texture_normal = BattleUISkin.ui_shape(resource)
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
	button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE))
	# 0x43a640: the press tick darkens the icon and sounds 398 (case 2 → 3); it stays dark while the
	# left button is held over it (0x4c6398 bit 0 and the hover bit); the first tick the button is up
	# runs the press and clears the dark (0x43ab52). Leaving it while held clears the dark and
	# drops the press, even if the pointer comes back before the release.
	button.button_down.connect(func():
		button.set_meta("left", false)
		button.self_modulate = PRESSED_DARK
		cue_requested.emit("confirm"))
	button.button_up.connect(func(): button.self_modulate = Color.WHITE)
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and button.is_pressed() and not Rect2(Vector2.ZERO, button.size).has_point(event.position):
			button.set_meta("left", true)
			button.self_modulate = Color.WHITE)
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


## 0x436ed0: the recipient's last slot (+0x154) holds an item.
func _bag_full() -> bool:
	var actor := _actor()
	return not actor.is_empty() and int(actor["inventory"][7]) != 0


## A click on a pending row: a lifted bag item goes to the pool, a held pool item back, an empty
## hand takes one of the row (not an important item).
func _press_row(group: Dictionary) -> void:
	if _hand.has("slot"): pool_requested.emit(_hand_request())
	elif holding(): cancel()
	elif not bool(_catalog[str(group["code"])]["important"]): _take(group)


func _take(group: Dictionary) -> void:
	_grab({"entry_id": str(group["entry_ids"][0]), "code": int(group["code"])})
	cue_requested.emit("take_up")


## An empty hand clicking a bag item lifts it (0x436e80 deletes the slot and closes the gap, sound
## 399); the rules commit that with whatever the held item does next (丟棄, 倉庫, back, pool).
func _lift(slot: int, code: int) -> void:
	_grab({"slot": slot, "code": code})
	_rebuild_bag()
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


## Clicking the list while holding a pool item puts it back into the pool (0x44f2d0); a lifted bag
## item goes there through pool_requested.
func cancel() -> void:
	if not holding() or _hand.has("slot"): return
	_hand = {}
	hand_icon.hide()
	_rebuild_rows()
	cue_requested.emit("put_down")


## ↑↓／PgUp PgDn go to the list's scroll bar: 0x445f00 gets the skill page's masks
## (0x8000000／0x10000000／0x40000／0x80000 → PgUp／PgDn／↑／↓), and 0x445860 pages by the
## thumb's +0x94, the five visible rows (0x445d70(bar, count, pos, 5, 0)). No wheel.
func handle_key(event: InputEvent) -> bool:
	return visible and scroll_bar != null and scroll_bar.handle_key(event)


## Original right click / Esc while holding (0x438160 root case 1): drop into the first free bag slot.
func quick_place() -> void:
	if not landed(): return
	if _hand.has("slot"): return_requested.emit(_hand_request())
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


## `held`: a bag row (root-window list branch, drawn once landed) versus a pending-list row
## (0x414c00 draws the box at 0x4150ab in every state, mid-slide included).
func _show_description(code: int, label: Label, held: bool) -> void:
	_forget_drawn_row()
	BattleUISkin.in_place(description_box, held)
	label.add_theme_color_override("font_color", BattleUISkin.TEXT_GREEN)
	_describe(description_box, code)


func _describe(box: Control, code: int) -> void:
	BattleEquipmentView.fill_box(box, BattleEquipmentView.description_rows(_catalog[str(code)], _description_lines(code)))
	box.show()


## 0x414c00 hit-tests the pending list on its current rect in every state (0x415601 registers it
## each draw, 0x4304ac intersects) and 0x4150ab describes the row under the pointer, mid-slide and
## in the close state 2 too. BattlePanelMotion calls this every tick while it draws the rows off
## their Controls: `offset_of(row)` is where a row is drawn (null: not drawn), `box` the box to
## fill (null: the panel's own; the close snapshot passes its copy). `drawn` false: the rows are
## on their Controls again (or gone with the window) and their own signals take over for the
## next row entered. Hidden, the panel's own box and row colours are cleared here: the rows'
## exits come after the window's visibility_changed (with `_drawn` already set) and are dropped.
func drawn_hover(offset_of: Callable, box: Control, drawn: bool) -> void:
	_drawn = drawn
	if not visible:
		if description_box != null: description_box.hide()
		for row in rows:
			if is_instance_valid(row): _hide_label(row.get_meta("label"))
	if box == null: box = description_box
	var hovered := -1
	for index in rows.size():
		if not is_instance_valid(rows[index]): continue
		var offset: Variant = offset_of.call(rows[index]) if drawn else (Vector2.ZERO if visible else null)
		if offset is Vector2 and Rect2(rows[index].position + offset, rows[index].size).has_point(_pointer): hovered = index
	if hovered == _drawn_row and (hovered < 0 or (box == _drawn_box and is_instance_valid(box) and box.visible)):
		return
	if _drawn_row >= 0 and is_instance_valid(_drawn_box): _drawn_box.hide()
	_forget_drawn_row()
	if hovered >= 0 and box != null:
		var row: Button = rows[hovered]
		if box == description_box: BattleUISkin.in_place(description_box, false)
		if visible: (row.get_meta("label") as Label).add_theme_color_override("font_color", BattleUISkin.TEXT_GREEN)
		_describe(box, int(row.get_meta("item_code")))
		_drawn_row = hovered
		_drawn_box = box


## The drawn hover's row goes back to its own colour (its box stays for the caller).
func _forget_drawn_row() -> void:
	if _drawn_row >= 0 and _drawn_row < rows.size() and is_instance_valid(rows[_drawn_row]):
		_hide_label(rows[_drawn_row].get_meta("label"))
	_drawn_row = -1


func _hide_description(label: Label) -> void:
	_hide_label(label)
	description_box.hide()


func _hide_label(label: Label) -> void:
	label.add_theme_color_override("font_color", label.get_meta("base_color", BattleUISkin.TEXT_WHITE))


func _description_lines(code: int) -> Array:
	return BattleItemText.description_lines(_catalog[str(code)], _consumables.get(str(code), {}))

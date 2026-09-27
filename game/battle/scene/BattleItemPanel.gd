extends Control
## One modal stack: item commands -> inventory -> recipient/confirmation.
## Draft selection is presentation-only; all item mutations return to PlayLoop.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (the use target is a map cell pick, not a window: the page gives way, BattleSceneMenus draws the range)
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#07
##     (item sub-menu, target selection)
##   layout: static-derived docs/evidence_packets/runtime_observations/game_cursor/README.md
##     (the picked item's icon rides the pointer while its use target is chosen)
##   layout: remake-invented (give recipient page, scrollable lists, preview rows)
##   strings: resource-derived content/generated/hsl/equipment/items.json
##   strings: resource-derived content/imported/hsl/chapter01/consumables.json
##   strings: remake-invented (captions and refusals)
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
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")
const BattleGiveView = preload("res://game/battle/scene/BattleGiveView.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
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
var confirm_button: Button
var give_view: Control
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


func _show_list(command: String) -> void:
	_clear_page()
	operation = command
	page = "inventory"
	BattleUISkin.clear_panel(page_root)
	var vitals := BattleVitals.new()
	vitals.position = Vector2(0, 14)
	page_root.add_child(vitals)
	vitals.show_unit(source_unit)
	var equipment := BattleEquipmentView.new()
	equipment_view = equipment
	equipment.interactive = operation == "equip"
	equipment.slot_requested.connect(func(slot):
		selected_item = "0"
		selected_index = -1
		_show_equipment_confirmation(slot))
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
	for index in range(source_unit["inventory"].size()):
		var code := str(int(source_unit["inventory"][index]))
		if code == "0":
			continue
		var details: Dictionary = catalog[code]
		if operation == "equip" and int(details["type_code"]) not in range(2, 7):
			continue
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
		if operation == "use" and not button.disabled:
			button.tooltip_text = preload("res://game/battle/scene/BattleItemText.gd").description(items[code])
		if operation == "equip" and not bool(details["supported"]):
			button.disabled = true
			button.tooltip_text = "此裝備效果尚未開放"
		if operation == "drop" and InventoryRules.discard_error(int(code), catalog) != "":
			button.disabled = true
			button.tooltip_text = "重要道具不可丟棄"
		button.pressed.connect(_select_item.bind(code, index))
		rows.add_child(button)
	if rows.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "沒有可更換的裝備" if operation == "equip" else "沒有道具"
		empty.add_theme_font_size_override("font_size", 16)
		rows.add_child(empty)
	var back := BattleUISkin.button(page_root, "返回", Vector2(502, 442), Vector2(113, 30))
	back.pressed.connect(cancel)
	var capacity := BattleUISkin.label(page_root, Vector2(20, 440), 15)
	capacity.text = "道具 %d / 8" % (8 - source_unit["inventory"].count(0))
	if operation == "equip":
		var hint := BattleUISkin.label(page_root, Vector2(252, 444), 12)
		hint.text = "點選裝備卸下；空手不能攻擊"
	elif operation == "drop":
		var hint := BattleUISkin.label(page_root, Vector2(252, 444), 12)
		hint.text = "重要道具不可丟棄"


func _select_item(code: String, index: int = -1) -> void:
	selected_item = code
	selected_index = index if index >= 0 else source_unit["inventory"].find(int(code))
	if operation == "drop":
		_show_drop_confirmation()
	elif operation == "use":
		_show_use_pick()
	elif operation == "give":
		_show_targets()
	elif operation == "equip":
		var kind := int(EquipmentCatalog.items()[code]["type_code"])
		if kind == 6:
			_show_accessory_slots()
		else:
			_show_equipment_confirmation(EquipmentRules.SLOTS[kind - 2])


func _show_targets() -> void:
	_clear_page()
	page = "give_target"
	var vitals := BattleVitals.new()
	vitals.position = Vector2(0, 322)
	page_root.add_child(vitals)
	vitals.hide()
	for target in targets:
		if target["id"] == source_unit["id"]:
			continue
		var point: Vector2 = target.get("screen_position", anchor)
		var button := Button.new()
		button.position = point - Vector2(16, 16)
		button.size = Vector2(32, 32)
		button.set_meta("target_id", str(target["id"]))
		button.tooltip_text = str(BattleUISkin.data()["actors"][str(target["actor_id"])]["title"])
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.0, 0.15, 1.0, 0.14)
			style.border_color = Color.YELLOW if state in ["hover", "pressed"] else Color(0.1, 0.25, 1.0)
			style.set_border_width_all(2)
			button.add_theme_stylebox_override(state, style)
		button.mouse_entered.connect(func(): vitals.show_unit(target); vitals.show())
		button.mouse_exited.connect(vitals.hide)
		button.pressed.connect(_select_give_target.bind(str(target["id"])))
		page_root.add_child(button)
		target_buttons[str(target["id"])] = button
	if target_buttons.is_empty():
		var hint := BattleUISkin.label(page_root, Vector2(172, 412), 17)
		hint.text = "附近沒有可交換的同伴"
	BattleUISkin.button(page_root, "結束給予", Vector2(474, 438), Vector2(148, 34)).pressed.connect(cancel)


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
		use_pick_ended.emit()


## The icon lives on the pick page, so leaving the page drops it (0x444aba clears the slot the
## tick after the confirm, 0x444a81 on cancel); GameCursor hides the sceptre while it shows.
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
	BattleUISkin.show_shape(held_icon, BattleUISkin.texture(icon))
	held_icon.set_meta("origin", Vector2(float(record["draw_origin"][0]), float(record["draw_origin"][1])))
	page_root.add_child(held_icon)
	_follow_pointer()


func _process(_delta: float) -> void:
	if visible and is_instance_valid(held_icon):
		_follow_pointer()


func _follow_pointer() -> void:
	held_icon.position = page_root.get_local_mouse_position() - held_icon.get_meta("origin", Vector2.ZERO)


func show_give_session(unit: Dictionary, recipients: Array, revision: int, keep_target: bool = false) -> void:
	source_unit = unit.duplicate(true)
	targets = recipients.duplicate(true)
	give_revision = revision
	operation = "give"
	selected_item = ""
	selected_index = -1
	give_target_index = -1
	show()
	if keep_target and not _give_target().is_empty():
		_show_give_inventories()
	else:
		give_target_id = ""
		_show_targets()


func _give_target() -> Dictionary:
	for target in targets:
		if str(target["id"]) == give_target_id:
			return target
	return {}


func _select_give_target(id: String) -> void:
	if page != "give_target":
		return
	give_target_id = id
	selected_index = -1
	selected_item = ""
	_show_give_inventories()


func _show_give_inventories() -> void:
	_clear_page()
	page = "give_inventory"
	give_view = BattleGiveView.new()
	page_root.add_child(give_view)
	give_view.show_inventories(source_unit, _give_target(), EquipmentCatalog.items(), selected_index)
	var view := give_view
	give_view.source_selected.connect(func(index, code):
		if page != "give_inventory" or give_view != view: return
		selected_index = index
		selected_item = str(code)
		_show_give_inventories())
	give_view.destination_selected.connect(func(index, code):
		if page == "give_inventory" and give_view == view: _show_give_confirmation(index, code))
	give_view.back_requested.connect(func():
		if page == "give_inventory" and give_view == view: _show_targets())
	var revision := give_revision
	give_view.finish_requested.connect(func():
		if page == "give_inventory" and give_view == view: give_finished.emit(revision))


func _show_give_confirmation(target_index: int, return_code: int) -> void:
	if page != "give_inventory" or selected_index < 0:
		return
	_clear_page()
	page = "give_confirm"
	give_target_index = target_index
	give_return_code = return_code
	var catalog := EquipmentCatalog.items()
	var target := _give_target()
	var result := InventoryRules.exchange(source_unit["inventory"], selected_index, int(selected_item), target["inventory"], target_index, return_code)
	BattleGiveView.fitted_board(page_root, Vector2(112, 140), Vector2(416, 224))
	var title := BattleUISkin.label(page_root, Vector2(132, 158), 19)
	title.text = "確認交換" if return_code > 0 else "確認給予"
	var description := BattleUISkin.label(page_root, Vector2(132, 201), 17)
	description.size = Vector2(376, 85)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var summary := "%s → %s" % [catalog[selected_item]["name"], BattleGiveView.unit_name(target)]
	if return_code > 0:
		summary += "\n換回：%s" % catalog[str(return_code)]["name"]
	BattleUISkin.set_wrapped_text(description, summary)
	confirm_button = BattleUISkin.button(page_root, "確定", Vector2(132, 306), Vector2(158, 36))
	confirm_button.disabled = not result["ok"]
	# Capture this exact proposal: an old Button signal cannot authorize a newer selection.
	var request := [give_target_id, selected_index, int(selected_item), target_index, return_code, give_revision]
	var proposal_button := confirm_button
	confirm_button.pressed.connect(func():
		if page == "give_confirm" and confirm_button == proposal_button:
			give_requested.emit(request[0], request[1], request[2], request[3], request[4], request[5]))
	BattleUISkin.button(page_root, "取消", Vector2(350, 306), Vector2(158, 36)).pressed.connect(cancel)


func _show_drop_confirmation() -> void:
	_clear_page()
	page = "drop_confirm"
	BattleUISkin.board(page_root, "WINDOW50", Vector2(132, 174))
	var title := BattleUISkin.label(page_root, Vector2(154, 191), 19)
	var catalog := EquipmentCatalog.items()
	var rejected := InventoryRules.discard_error(int(selected_item), catalog) != ""
	title.text = "此道具不可丟棄" if rejected else "丟棄 %s？" % catalog[selected_item]["name"]
	confirm_button = BattleUISkin.button(page_root, "確定", Vector2(152, 268), Vector2(150, 36))
	confirm_button.disabled = rejected
	confirm_button.pressed.connect(func(): drop_requested.emit(selected_item))
	var back := BattleUISkin.button(page_root, "取消", Vector2(338, 268), Vector2(150, 36))
	back.pressed.connect(cancel)


func _show_accessory_slots() -> void:
	_clear_page()
	page = "equipment_slot"
	var board := BattleUISkin.board(page_root, "WINDOW50", Vector2(132, 174))
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.size = Vector2(376, 164)
	var title := BattleUISkin.label(page_root, Vector2(154, 191), 19)
	title.text = "選擇飾品位置"
	for index in range(2):
		var slot := "accessory%d" % (index + 1)
		var button := BattleUISkin.button(page_root, "飾品 %d" % (index + 1), Vector2(152 + 186 * index, 235), Vector2(150, 36))
		button.pressed.connect(_show_equipment_confirmation.bind(slot))
	BattleUISkin.button(page_root, "取消", Vector2(246, 286), Vector2(150, 36)).pressed.connect(cancel)


func _show_equipment_confirmation(slot: String) -> void:
	_clear_page()
	page = "equip_confirm"
	selected_slot = slot
	var catalog := EquipmentCatalog.items()
	var result := EquipmentRules.replace(source_unit, slot, selected_index, int(selected_item), catalog)
	if ProgressionRules.refresh_input_error(source_unit, catalog) != "":
		result = {"ok": false, "reason": "unsupported_growth_model"}
	var proposed := source_unit.duplicate(true)
	if result["ok"]:
		proposed["equipment"] = result["equipment"]
		var error := ProgressionRules.refresh_input_error(proposed, catalog)
		if error != "": result = {"ok": false, "reason": error}
	var board := BattleUISkin.board(page_root, "WINDOW50", Vector2(132, 140))
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.size = Vector2(376, 248)
	var title := BattleUISkin.label(page_root, Vector2(154, 160), 19)
	var old := EquipmentRules.equipped_code(source_unit["equipment"], slot)
	title.text = "卸下 %s？" % catalog[str(old)]["name"] if selected_item == "0" else "裝備 %s？" % catalog[selected_item]["name"]
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(154, 197)
	scroll.size = Vector2(330, 125)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_root.add_child(scroll)
	var preview := BattleUISkin.label(scroll, Vector2.ZERO, 17)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if result["ok"]:
		result = _preview_equipment_change(proposed, catalog, preview, result)
	else:
		var messages := {"inventory_full": "背包已滿，無法收回裝備。", "wrong_job": "目前職業無法使用這件裝備。", "equipment_cannot_be_removed": "這件裝備無法卸下。", "equipment_unchanged": "已裝備相同道具。", "unsupported_equipment": "此裝備效果尚未開放。"}
		preview.text = messages.get(result["reason"], "目前無法更換這件裝備。")
	confirm_button = BattleUISkin.button(page_root, "確定", Vector2(152, 334), Vector2(150, 36))
	confirm_button.disabled = not result["ok"]
	confirm_button.pressed.connect(func(): equipment_requested.emit(selected_slot, selected_index, int(selected_item)))
	BattleUISkin.button(page_root, "取消", Vector2(338, 334), Vector2(150, 36)).pressed.connect(cancel)


## _show_equipment_confirmation: the before → after lines of a legal change (stats,
## 氣力, attack count, extra actions); returns `result`, replaced when source data is bad.
func _preview_equipment_change(proposed: Dictionary, catalog: Dictionary, preview: Label, result: Dictionary) -> Dictionary:
	proposed = ProgressionRules.refresh_growth_stats(proposed, catalog)
	var before: Dictionary = source_unit["combat_profile"]
	var after: Dictionary = proposed["combat_profile"]
	preview.text = "移動力  %d → %d\n攻擊  %d → %d\n防禦  %d → %d\n魔擊  %d → %d\n敏捷  %d → %d" % [source_unit["move_point"], proposed["move_point"], before["live_attack_damage"], after["live_attack_damage"], before["live_defense"], after["live_defense"], before["live_magic_attack"], after["live_magic_attack"], source_unit["live_speed"], proposed["live_speed"]]
	for key in ["attack_damagex2", "attack_back", "avoid_hit_ratio"]:
		if before[key] != after[key]: preview.text += "\n%s  %d%% → %d%%" % [{"attack_damagex2": "暴擊", "attack_back": "反擊", "avoid_hit_ratio": "迴避"}[key], before[key], after[key]]
	if before["weapon_magic_attack_type"] != after["weapon_magic_attack_type"] or before["weapon_damage_variance_lo"] != after["weapon_damage_variance_lo"] or before["weapon_damage_variance_hi"] != after["weapon_damage_variance_hi"]:
		var names := ["無附加", "地", "水", "風", "火", "心", "無屬性"]
		preview.text += "\n武器附加  %s → %s" % [names[int(before["weapon_magic_attack_type"]) + 1], names[int(after["weapon_magic_attack_type"]) + 1]]
	var stamina = preload("res://game/sim/StaminaRules.gd")
	var previous := stamina.equipment_caption(source_unit, catalog)
	var current := stamina.equipment_caption(proposed, catalog)
	if previous != current: preview.text += "\n氣力累積  %s → %s" % [previous, current]
	var sequence = preload("res://game/sim/CombatSequenceRules.gd")
	var old_count: Dictionary = sequence.attack_count(source_unit, attack_source, catalog)
	var new_count: Dictionary = sequence.attack_count(proposed, attack_source, catalog)
	if old_count["ok"] and new_count["ok"] and old_count["count"] != new_count["count"]:
		preview.text += "\n普通攻擊與反擊  %d擊 → %d擊" % [old_count["count"], new_count["count"]]
	if not old_count["ok"] or not new_count["ok"]:
		result = {"ok": false, "reason": "invalid_extra_attack_source"}
		preview.text = "攻擊資料異常，無法更換這件裝備。"
	var extra = preload("res://game/sim/ExtraActionRules.gd")
	var old_actions: Dictionary = extra.equipment(source_unit, catalog)
	var new_actions: Dictionary = extra.equipment(proposed, catalog)
	if old_actions["ok"] and new_actions["ok"] and old_actions["count"] != new_actions["count"]:
		preview.text += "\n輪到時連續行動  %d次 → %d次" % [old_actions["count"], new_actions["count"]]
	if not old_actions["ok"] or not new_actions["ok"]:
		result = {"ok": false, "reason": "invalid_extra_action_source"}
		preview.text = "行動資料異常，無法更換這件裝備。"
	return _preview_equipment_effects(proposed, catalog, preview, result)


## _preview_equipment_change, continued: resource, position, weapon, casting, experience
## and stamina effects.
func _preview_equipment_effects(proposed: Dictionary, catalog: Dictionary, preview: Label, result: Dictionary) -> Dictionary:
	var stamina = preload("res://game/sim/StaminaRules.gd")
	var experience = preload("res://game/sim/ExperienceRules.gd")
	var recovery = preload("res://game/sim/ResourceRecoveryRules.gd")
	var old_resources: Dictionary = recovery.effects(source_unit, catalog)
	var new_resources: Dictionary = recovery.effects(proposed, catalog)
	if old_resources["ok"] and new_resources["ok"]:
		for key in recovery.KEYS:
			if old_resources["effects"][key] != new_resources["effects"][key]:
				var title_text: String = {"mp_use_half": "魔法減耗", "hp_auto_restore": "末次行動回血", "mp_auto_restore": "末次行動回魔", "hp_transfer_mp": "末次行動生命轉魔力"}[key]
				preview.text += "\n%s  %s → %s" % [title_text, "有" if old_resources["effects"][key] else "無", "有" if new_resources["effects"][key] else "無"]
		if new_resources["effects"]["hp_transfer_mp"]:
			preview.text += "\n魔力已滿仍耗生命，最低保留1HP。"
	else:
		result = {"ok": false, "reason": "invalid_resource_effect"}
		preview.text = "資源效果資料異常，無法更換這件裝備。"
	var status = preload("res://game/sim/StatusApplicationRules.gd")
	var casting_source := {"actors": {str(source_unit["actor_id"]): attack_source}}
	var position_rules = preload("res://game/sim/PositionCapabilityRules.gd")
	var old_position: Dictionary = position_rules.effects(source_unit, casting_source, catalog)
	var new_position: Dictionary = position_rules.effects(proposed, casting_source, catalog)
	if old_position["ok"] and new_position["ok"]:
		for key in ["move_magic_use", "add_attack_range"]:
			if old_position["effects"][key] != new_position["effects"][key]:
				preview.text += "\n%s  %s → %s" % ["移動後施法" if key == "move_magic_use" else "攻擊範圍加成", "有" if old_position["effects"][key] else "無", "有" if new_position["effects"][key] else "無"]
		if new_position["effects"]["add_attack_range"]: preview.text += "\n攻擊／反擊提升一檔；魔法範圍不變。"
	else:
		result = {"ok": false, "reason": "invalid_position_capability"}
		preview.text = "範圍或行動資料異常，無法更換這件裝備。"
	var old_casting: Dictionary = status.modifiers(source_unit, casting_source, catalog)
	var weapon = preload("res://game/sim/WeaponEffectRules.gd")
	var old_weapon: Dictionary = weapon.effects(source_unit, catalog)
	var new_weapon: Dictionary = weapon.effects(proposed, catalog)
	if old_weapon["ok"] and new_weapon["ok"]:
		for bit in [weapon.POISON, weapon.CANCEL, weapon.MANA]:
			if (int(old_weapon["flags"]) & bit) != (int(new_weapon["flags"]) & bit):
				preview.text += "\n%s  %s → %s" % [{weapon.POISON:"末擊附毒25%",weapon.CANCEL:"末擊取消行動10%",weapon.MANA:"末擊削減魔力"}[bit], "有" if int(old_weapon["flags"]) & bit else "無", "有" if int(new_weapon["flags"]) & bit else "無"]
		if int(new_weapon["flags"]) & weapon.MANA: preview.text += "\n削減目標魔力＝末擊實際傷害的三分之一；自身不回魔。"
	else:
		result = {"ok": false, "reason": "invalid_weapon_effect_source"}
		preview.text = "武器效果資料異常，無法更換這件裝備。"
	var new_casting: Dictionary = status.modifiers(proposed, casting_source, catalog)
	if old_casting["ok"] and new_casting["ok"]:
		for key in status.IMMUNITY:
			var before_protected: bool = (int(old_casting["effects"]) & (int(status.IMMUNITY[key]) | 0x80)) != 0
			var after_protected: bool = (int(new_casting["effects"]) & (int(status.IMMUNITY[key]) | 0x80)) != 0
			if before_protected != after_protected:
				preview.text += "\n%s  %s → %s" % ["防止" + preload("res://game/sim/StatusCatalog.gd").name_of(key), "有" if before_protected else "無", "有" if after_protected else "無"]
				if after_protected: preview.text += "（不解除已有狀態）"
		if old_casting["magic_hit_bonus"] != new_casting["magic_hit_bonus"]:
			preview.text += "\n魔法命中修正  +%d → +%d" % [old_casting["magic_hit_bonus"], new_casting["magic_hit_bonus"]]
	else:
		result = {"ok": false, "reason": "invalid_casting_equipment"}
		preview.text = "施法裝備資料異常，無法更換這件裝備。"
	var old_exp: Dictionary = experience.multiplier(source_unit, catalog)
	var new_exp: Dictionary = experience.multiplier(proposed, catalog)
	if old_exp["ok"] and new_exp["ok"] and old_exp["value"] != new_exp["value"]:
		preview.text += "\n獲得經驗  ×%d → ×%d" % [old_exp["value"], new_exp["value"]]
	if not old_exp["ok"] or not new_exp["ok"]:
		result = {"ok": false, "reason": "invalid_experience_equipment_effect"}
		preview.text = "經驗資料異常，無法更換這件裝備。"
	if stamina.input_error(source_unit, catalog) != "" or not stamina.effects(proposed, catalog)["ok"]:
		result = {"ok": false, "reason": "invalid_stamina_equipment_effect"}
		preview.text = "氣力資料異常，無法更換這件裝備。"
	return result


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
	if page == "give_confirm":
		_show_give_inventories()
	elif page == "give_inventory":
		_show_targets()
	elif page == "give_target":
		give_finished.emit(give_revision)
	elif page == "target":
		# 0x444a5c: right click returns the held item (0x436e30) and reopens the use window (state 102).
		_show_list(operation)
		BattlePanelMotion.attach(self).slide_in()
	elif page in ["drop_confirm", "equip_confirm", "equipment_slot"]:
		_show_list(operation)
	elif page == "inventory":
		_show_commands()
	else:
		hide()

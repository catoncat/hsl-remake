extends Control
## Shared equipment view; optional slot requests never mutate battle state.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V05
##     (frame_006 name start after the colon and per-column icon anchors)
##   layout: resource-derived content/generated/hsl/text/protected_words.json
##   layout: remake-invented (355×70 detail scroll area)
##   strings: resource-derived content/generated/hsl/equipment/items.json
##   strings: remake-invented (detail captions)
signal slot_requested(slot: String)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
var interactive := false
## Mode 4／5 window (0x439903): a pick on an empty slot also counts (it takes the held item).
var accepts_empty_slots := false
var slot_controls: Dictionary = {}
var labels: Dictionary = {}
var icons: Dictionary = {}
var slot_items: Dictionary = {}
var description: Label
## WINDOW50 and its text: shown only while the pointer is on a slot holding an item (the
## WINDOW30 process 0x430710 writes the text and 0x436d70 draws the box on hover; frame_006
## hovering 鐵護輪 covers the page buttons, the box is absent otherwise).
var detail_box: Control
var source_unit: Dictionary = {}
const SLOTS := ["weapon", "head", "armor", "foot", "accessory1", "accessory2"]
const BOARD_AT := Vector2(252, 174)
## Slot geometry inside WINDOW30 (board-local). The baked 武／頭／體／腳／飾 label rows are
## centred at y 35, 86, 136 with their colons ending at x 39 (left column) and 219 (right
## column) — resource-derived from the WINDOW30 pixels. In 06_status_and_stats_screen
## frame_006 each item name starts 6 px after its colon on the label's row centre, and each
## icon's draw origin sits on a fixed anchor per column and row: (103, 26 + 50·row) and
## (282, 26 + 50·row) (runtime-reference: the sword／helmet／armor／boot icons template-match
## there; the 飾 row anchor follows the 50 px pitch).
const LABEL_ROW_CENTERS := [35, 86, 136]
const COLON_ENDS := [39, 219]
const NAME_GAP := 6
const ICON_ANCHORS := [Vector2(103, 26), Vector2(282, 26)]
const ICON_ROW_PITCH := 50
## Hover／click area of one slot: the label column plus the name, one row tall.
const SLOT_LEFTS := [4, 184]
const SLOT_SIZE := Vector2(176, 44)
## Detail scroll area under WINDOW50; the description keeps one fixed width (the area less a
## vertical scroll bar) so its wrap is known before layout and never moves when a long
## description brings the bar in — BattleUISkin.set_wrapped_text keeps every name on one line.
const DETAIL_AT := Vector2(262, 359)
## 0x436d70 draws WINDOW50 at (252,349) on the status page (Wine template match, menus_ui §5).
const DETAIL_BOARD_AT := Vector2(252, 349)
const DETAIL_SIZE := Vector2(355, 70)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	BattleUISkin.board(self, "WINDOW30", BOARD_AT)
	detail_box = Control.new()
	detail_box.name = "Description"
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.hide()
	add_child(detail_box)
	BattleUISkin.board(detail_box, "WINDOW50", DETAIL_BOARD_AT)
	var scroll := ScrollContainer.new()
	scroll.position = DETAIL_AT
	scroll.size = DETAIL_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_box.add_child(scroll)
	description = BattleUISkin.label(scroll, Vector2.ZERO, 15)
	description.custom_minimum_size.x = DETAIL_SIZE.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x
	description.size = Vector2(description.custom_minimum_size.x, 0)
	description.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for index in range(SLOTS.size()):
		var slot: String = SLOTS[index]
		var column := index % 2
		var row := floori(index / 2.0)
		var at := BOARD_AT + Vector2(SLOT_LEFTS[column], LABEL_ROW_CENTERS[row] - SLOT_SIZE.y / 2.0)
		var area := Control.new()
		area.position = at
		area.size = SLOT_SIZE
		area.mouse_filter = Control.MOUSE_FILTER_PASS
		area.set_meta("equipment_slot", slot)
		add_child(area)
		slot_controls[slot] = area
		area.mouse_entered.connect(_select.bind(slot))
		area.mouse_exited.connect(_deselect.bind(slot))
		area.gui_input.connect(func(event):
			if interactive and (accepts_empty_slots or slot_items.has(slot)) and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				slot_requested.emit(slot)
				accept_event())
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.set_meta("anchor", BOARD_AT + ICON_ANCHORS[column] + Vector2(0, ICON_ROW_PITCH * row) - at)
		area.add_child(icon)
		icons[slot] = icon
		var label := BattleUISkin.label(area, Vector2(COLON_ENDS[column] + NAME_GAP - SLOT_LEFTS[column], 0), 17)
		label.size = Vector2(0, SLOT_SIZE.y)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels[slot] = label


## Places an item icon by its SHP draw origin on the slot's anchor (the engine's 0x4607f9
## anchor convention, as BattleUISkin.anchored_asset).
func _show_icon(slot: String, key: String) -> void:
	var icon: TextureRect = icons[slot]
	BattleUISkin.show_shape(icon, BattleUISkin.texture(key))
	var origin: Array = BattleUISkin.data()["assets"][key]["draw_origin"]
	icon.position = Vector2(icon.get_meta("anchor")) - Vector2(float(origin[0]), float(origin[1]))


func show_unit(unit: Dictionary) -> void:
	source_unit = unit.duplicate(true)
	slot_items.clear()
	for slot in SLOTS:
		labels[slot].text = ""
		BattleUISkin.show_shape(icons[slot], null)
	var catalog := EquipmentCatalog.items()
	for item in unit["equipment"]:
		var slot: String = item["slot"]
		var details: Dictionary = catalog[str(int(item["item_code"]))]
		slot_items[slot] = details
		labels[slot].text = str(details["name"])
		_show_icon(slot, str(details["icon"]))
	_deselect("")


## Hovering a slot that holds an item greens its name and brings up WINDOW50 with its text.
func _select(slot: String) -> void:
	for key in labels:
		labels[key].modulate = Color(0.4, 1, 0.3) if key == slot and slot_items.has(slot) else Color.WHITE
	if not slot_items.has(slot):
		_deselect(slot)
		return
	show_description(slot_items[slot])
	detail_box.show()


func _deselect(_slot: String) -> void:
	for key in labels:
		labels[key].modulate = Color.WHITE
	description.text = ""
	detail_box.hide()


## The description text for `item` (an item without stat values leaves no trailing blank line).
static func description_text(item: Dictionary) -> String:
	return "\n".join(description_lines(item)).rstrip("\n")


func show_description(item: Dictionary) -> void:
	BattleUISkin.set_wrapped_text(description, description_text(item))


## Equipment effect lines shared by the status equipment box and the loot window's description box.
static func description_lines(item: Dictionary) -> Array[String]:
	var fields: Dictionary = item["effects"]
	var lines: Array[String] = [str(item["name"])]
	var captions := {"attack": "攻擊力", "hit_rate": "命中", "defense": "防禦", "speed": "敏捷", "move_point": "移動力", "max_hp": "生命", "max_mp": "魔力", "magic_attack": "魔擊", "avoid_hit_ratio": "迴避", "attack_back": "反擊", "attack_damagex2": "暴擊"}
	var values: Array[String] = []
	for key in captions:
		if int(fields[key]) != 0:
			values.append("%s %d%s" % [captions[key], int(fields[key]), "%" if key in ["hit_rate", "avoid_hit_ratio", "attack_back", "attack_damagex2"] else ""])
	lines.append("  ".join(values))
	var stamina_flags := int(item["stamina_effect_flags"])
	if stamina_flags & 0x400: lines.append("不再累積氣力")
	elif stamina_flags & 0x40: lines.append("氣力累積加倍")
	if bool(item["experience_double"]): lines.append("獲得經驗加倍")
	if bool(item.get("gold_double", false)): lines.append("獲得金錢加倍")
	if bool(item["double_attack"]): lines.append("普通攻擊與反擊可追加一擊")
	var weapon_flags := int(item["weapon_effect_flags"])
	if weapon_flags & 0x200000: lines.append("普通／反擊系列末擊命中後25%附毒")
	if weapon_flags & 0x400000:
		lines.append("普通／反擊末擊使目標損失魔力")
		lines.append("依該擊實際傷害的三分之一；自身不回魔")
	if weapon_flags & 0x10000:
		lines.append("系列末擊命中後10%取消本輪未用行動")
		lines.append("不阻止當前反擊或已開始的行動")
	if bool(item["move_magic_use"]): lines.append("移動後仍可施放魔法")
	if bool(item["add_attack_range"]): lines.append("普通攻擊與反擊範圍提升一檔（不擴大魔法）")
	if bool(item["action_twice"]): lines.append("每次輪到時可連續行動兩次")
	if bool(item["mp_use_half"]): lines.append("魔法消耗減半（最低 1 MP）")
	if bool(item["hp_auto_restore"]): lines.append("最後行動結束時回復生命")
	if bool(item["mp_auto_restore"]): lines.append("最後行動結束時回復魔力")
	if bool(item["hp_transfer_mp"]):
		lines.append("最後行動以生命換魔力")
		lines.append("魔力已滿仍耗生命，最低保留1HP")
	if int(item["status_effect_flags"]) & 0x800000: lines.append("防止中毒（不解除已有中毒）")
	if int(item["status_effect_flags"]) & 0x1000000: lines.append("防止禁魔（不解除已有禁魔）")
	if int(item["status_effect_flags"]) & 0x4000000: lines.append("防止麻痺（不解除已有麻痺）")
	if int(item["status_effect_flags"]) & 0x80:
		lines.append("防止中毒、禁魔與麻痺")
		lines.append("不解除已有狀態；不防止行動取消")
	if int(item["magic_hit_bonus"]) > 0: lines.append("魔法命中修正 +%d" % int(item["magic_hit_bonus"]))
	var element: int = item["weapon_magic"]["element"]
	if element >= 0: lines.append("附加%s屬性傷害" % ["地", "水", "風", "火", "心", "無"][element])
	return lines

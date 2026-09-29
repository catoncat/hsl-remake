extends Control
## Shared equipment view; optional slot requests never mutate battle state.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V05
##     (frame_006 name start after the colon and per-column icon anchors)
##   layout: resource-derived content/generated/hsl/text/protected_words.json
##   layout: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (0x436d70 WINDOW50 box, 0x412060 four FONT.15 rows centred on 45 half-width cells)
##   strings: resource-derived content/generated/hsl/equipment/items.json
##   strings: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (0x430710 types 2..6 with RESOURCE ids, job bracket 0x430520／0x4465e0)
##   strings: remake-invented (the OPT-GUIDE＝提示 explanatory rows)
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
## The WINDOW50 origin inside detail_box; fill_box writes the rows here.
var detail_rows: Control
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
## 0x436d70 draws WINDOW50 at (252,349) on the status page (Wine template match, menus_ui §5);
## [0x4c1cbc] bit 0 (getitem／倉庫／shop) moves it to y 390 and, without bit 1, x 249.
const DETAIL_BOARD_AT := Vector2(252, 349)
## 0x436d70 → 0x412060: text at (x+8, y+12), 16 px rows, centred on 45 half-width cells of 8 px,
## clipped at y+h−11 (WINDOW50 is 88 high) so four rows show.
const BOX_TEXT_AT := Vector2(8, 12)
const BOX_ROW_PITCH := 16
const BOX_CELLS := 45
const BOX_CELL := 8
const BOX_ROWS := 4
const GameOptions = preload("res://game/settings/GameOptions.gd")
## 0x430710 colour codes of an equipment description's rows: @3 name, @1 type row, @5 (0x47856c)
## common row, @6 (0x478568 "#@6") flag row.
const ROW_COLOURS := [BattleUISkin.TEXT_GREEN, BattleUISkin.TEXT_WHITE, BattleUISkin.TEXT_YELLOW, BattleUISkin.TEXT_IVORY]
## 0x4465e0 job → name for job bits 0..20 (byte map 0x4466b4, jumps 0x44668c): RESOURCE 229 劍,
## 230 弓, 231 祭, 232 賊, 603 法, 233 翼, 234 獸, 235 魔物, 236 魔劍; bits 21..31 name nothing.
const JOB_NAMES := ["劍", "劍", "劍", "弓", "弓", "祭", "祭", "祭", "賊", "賊", "法", "法", "翼", "翼", "獸", "獸", "魔物", "魔物", "魔劍", "魔劍", "魔劍"]
## Weapon ITEM+0x8c 0..4 (sub-table 0x4330d0): RESOURCE 217..221, then 223 基礎攻擊力.
const ELEMENT_NAMES := ["地系", "水系", "風系", "火系", "心靈系"]
## Common tail 0x431968, each field only when nonzero, signed (0x45b6de 0x80000006), one space
## (0x476c74) apart: [items.json key, RESOURCE text, "%" after]. A type's own base field is on
## its type row (items.json merges +0x88 into that key; no ITEM row carries both).
const COMMON_FIELDS := [["attack", "攻擊", false], ["defense", "防禦", false], ["magic_attack", "魔擊", true],
	["hit_rate", "武器命中率", true], ["magic_hit_bonus", "魔法命中率", true], ["max_hp", "生命", false],
	["max_mp", "魔法", false], ["speed", "敏捷", false], ["move_point", "移動", false]]
const OWN_FIELDS := {2: ["attack", "hit_rate"], 3: ["defense"], 4: ["defense"], 5: ["speed"], 6: []}
## Resist names by the elements an ITEM+0x10 code covers (table 0x4330e4; importer RESISTS):
## 0..4 → 65 抗土／68 抗水／66 抗風／67 抗火／69 抗心靈, 7 → 201, 8 → 602, 9..18 → 2516..2525.
## Codes 5, 6 and past 18 print the value alone; no ITEM row uses them.
const RESIST_NAMES := {"0": "抗土", "1": "抗水", "2": "抗風", "3": "抗火", "4": "抗心靈",
	"0,1,2,3,4": "全部抗力", "0,1,2,3": "地火風水抗力", "1,3": "火水抗力", "0,3": "地火抗力",
	"2,3": "火風抗力", "3,4": "火心靈抗力", "0,1": "地水抗力", "1,2": "風水抗力", "1,4": "水心靈抗力",
	"0,2": "地風抗力", "0,4": "地心靈抗力", "2,4": "風心靈抗力"}
## The "#@6" row: ITEM+0xa0 bits in 0x43206e order with their RESOURCE texts, one space apart.
## 0x2000 喪失氣力／0x4000 喪失魔法力 are on no equipment row (items.json does not carry them).
const FLAG_NAMES := [[0x1, "攻擊距離加一"], [0x40, "氣力2倍回復"], [0x2, "魔法消耗減半"], [0x4, "被武器攻擊傷害減半"],
	[0x8, "行動兩次"], [0x10, "經驗值x2"], [0x20, "所得金錢x2"], [0x80, "狀態永遠良好"], [0x100, "自動回復生命"],
	[0x200, "自動回復魔法"], [0x1000, "移動後可用魔法"], [0x4000, "喪失魔法力"], [0x2000, "喪失氣力"],
	[0x8000, "兩次武器攻擊"], [0x10000, "行動取消效果"], [0x400000, "降低敵傷害1/3之法力"], [0x800000, "防毒"],
	[0x1000000, "防魔法封印"], [0x2000000, "防衰弱"], [0x4000000, "防麻痺"], [0x800, "高價值"],
	[0x400, "無法增加氣力"], [0x40000, "狀態不定異常"], [0x20000, "衰弱效果"], [0x80000, "魔法封印效果"],
	[0x100000, "痲痺效果"], [0x200000, "中毒效果"]]
## 0x432a26: with 0x40000 the row writes 612 and jumps past these four.
const RANDOM_STATUS_SKIPS := [0x20000, 0x80000, 0x100000, 0x200000]
## After the bits: ITEM+0xa4 bit 1 → 622, then ITEM+0x40／0x44／0x48／0x4c signed with "%".
const RATE_FIELDS := [["steal_ratio", "偷物品機率"], ["avoid_hit_ratio", "閃避率"], ["attack_back", "反擊率"], ["attack_damagex2", "痛恨一擊率"]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# WINDOW30 is a window object of its own (0x43ae70, from the right): the view sits on the
	# board and takes its size, so BattlePanelMotion slides it as one part; children keep their
	# screen positions (board-local = screen − BOARD_AT).
	position = BOARD_AT
	size = BattleUISkin.board(self, "WINDOW30", Vector2.ZERO).texture.get_size()
	detail_box = Control.new()
	detail_box.name = "Description"
	# Screen-origin layer for the in-place WINDOW50 (0x436d70 draws it at a fixed screen point).
	detail_box.position = -BOARD_AT
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.hide()
	BattleUISkin.in_place(detail_box)
	add_child(detail_box)
	BattleUISkin.board(detail_box, "WINDOW50", DETAIL_BOARD_AT)
	detail_rows = Control.new()
	detail_rows.name = "Rows"
	detail_rows.position = DETAIL_BOARD_AT
	detail_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.add_child(detail_rows)
	for index in range(SLOTS.size()):
		var slot: String = SLOTS[index]
		var column := index % 2
		var row := floori(index / 2.0)
		var at := BOARD_AT + Vector2(SLOT_LEFTS[column], LABEL_ROW_CENTERS[row] - SLOT_SIZE.y / 2.0)
		var area := Control.new()
		area.position = at - BOARD_AT
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
	fill_box(detail_rows, [])
	detail_box.hide()


## The description text for `item`, rows joined (trailing empty rows are not written).
static func description_text(item: Dictionary) -> String:
	return "\n".join(description_lines(item))


func show_description(item: Dictionary) -> void:
	fill_box(detail_rows, description_rows(item, description_lines(item)))


## The description rows of an equipment item (ITEM+8 types 2..6), as 0x430710 writes them: the
## @3 name and the job bracket, the type row (0x431462 weapon, 0x43172f head／body, 0x431815
## shoes, 0x4318fb accessory: none), the @5 common row and the @6 flag row. A middle row may be
## empty (0x412060 still steps down a row on its "#"); empty rows at the end are not returned.
## Under OPT-GUIDE＝提示 the non-empty rows come first, then the remake's explanatory rows.
static func description_lines(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for row in _rows(item):
		lines.append(str(row[0]))
	return lines


## [text, colour] per description row of `item` (see description_lines).
static func _rows(item: Dictionary) -> Array:
	var texts: Array[String] = [str(item["name"]) + "(" + job_text(int(item["job_mask"])) + ")", type_row(item), common_row(item), flag_row(item)]
	var rows := []
	for index in range(texts.size()):
		rows.append([texts[index], ROW_COLOURS[index]])
	if not GameOptions.is_original("OPT-GUIDE"):
		rows = rows.filter(func(row): return row[0] != "")
		for hint in _hint_rows(item):
			rows.append([hint, BattleUISkin.TEXT_WHITE])
	while rows.size() > 1 and rows[rows.size() - 1][0] == "":
		rows.pop_back()
	return rows


## 0x430520: mask −1 → 237 所有職業, 0 → 306 ???; otherwise the 0x4465e0 name of each set bit
## 0..31, a name equal to the last one written skipped, "," (0x47855c) between them and 228 專用
## after a single name.
static func job_text(mask: int) -> String:
	mask &= 0xffffffff
	if mask == 0xffffffff: return "所有職業"
	if mask == 0: return "???"
	var names: Array[String] = []
	for bit in range(JOB_NAMES.size()):
		if mask & (1 << bit) and (names.is_empty() or names[names.size() - 1] != JOB_NAMES[bit]):
			names.append(JOB_NAMES[bit])
	return ",".join(names) + ("專用" if names.size() == 1 else "")


## The row after the name: weapon 54 攻擊力 +0x88, 196 命中率 +0x98 "%" and, for an ITEM+0x8c
## element 0..4, the element name, 223 基礎攻擊力 and +0x90 "∼" (0x478560) +0x94; head／body 56
## 防禦力 +0x88; shoes 132 敏捷度 +0x88; accessories none ("@1##"). Plain numbers (0x45b6de 6).
static func type_row(item: Dictionary) -> String:
	var fields: Dictionary = item["effects"]
	match int(item["type_code"]):
		2:
			var row := "攻擊力%d 命中率%d%%" % [int(fields["attack"]), int(fields["hit_rate"])]
			var magic: Dictionary = item["weapon_magic"]
			var element := int(magic["element"])
			if element >= 0 and element < ELEMENT_NAMES.size():
				row += " %s基礎攻擊力%d∼%d" % [ELEMENT_NAMES[element], int(magic["low"]), int(magic["high"])]
			return row
		3, 4: return "防禦力%d" % int(fields["defense"])
		5: return "敏捷度%d" % int(fields["speed"])
	return ""


## The @5 row (0x431968): COMMON_FIELDS, then a resist when ITEM+0x10 is not −1 (its name, the
## signed +0x14 and "%").
static func common_row(item: Dictionary) -> String:
	var fields: Dictionary = item["effects"]
	var own: Array = OWN_FIELDS.get(int(item["type_code"]), [])
	var parts: Array[String] = []
	for entry in COMMON_FIELDS:
		if entry[0] in own: continue
		var value := int(item["magic_hit_bonus"]) if entry[0] == "magic_hit_bonus" else int(fields[entry[0]])
		if value != 0: parts.append("%s%+d%s" % [entry[1], value, "%" if entry[2] else ""])
	var covered: Array[String] = []
	var amount := 0
	var resists: Dictionary = fields["resist_by_type"]
	for index in range(5):
		if int(resists[str(index)]) != 0:
			covered.append(str(index))
			amount = int(resists[str(index)])
	if not covered.is_empty():
		parts.append("%s%+d%%" % [RESIST_NAMES.get(",".join(covered), ""), amount])
	return " ".join(parts)


## The ITEM+0xa0 word as items.json carries it (the loader bits of 0x447dc0..0x4481c0).
static func item_flags(item: Dictionary) -> int:
	var word := int(item["weapon_effect_flags"]) | int(item["status_effect_flags"]) | int(item["stamina_effect_flags"])
	for pair in [["add_attack_range", 0x1], ["mp_use_half", 0x2], ["hp_damage_half", 0x4], ["action_twice", 0x8],
			["experience_double", 0x10], ["gold_double", 0x20], ["hp_auto_restore", 0x100], ["mp_auto_restore", 0x200],
			["high_cost", 0x800], ["move_magic_use", 0x1000], ["double_attack", 0x8000]]:
		if bool(item.get(pair[0], false)): word |= pair[1]
	return word


## The @6 row (0x43206e..0x432fab): FLAG_NAMES, then 622 for ITEM+0xa4 bit 1, then RATE_FIELDS.
static func flag_row(item: Dictionary) -> String:
	var word := item_flags(item)
	var parts: Array[String] = []
	for pair in FLAG_NAMES:
		if word & pair[0] and not (pair[0] in RANDOM_STATUS_SKIPS and word & 0x40000):
			parts.append(pair[1])
	if bool(item["hp_transfer_mp"]): parts.append("每回減生命力加魔法力")
	var fields: Dictionary = item["effects"]
	for pair in RATE_FIELDS:
		if int(fields[pair[0]]) != 0: parts.append("%s%+d%%" % [pair[1], int(fields[pair[0]])])
	return " ".join(parts)


## The remake's explanatory rows (OPT-GUIDE＝提示 only; the original rows already name each flag).
static func _hint_rows(item: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if bool(item["double_attack"]): lines.append("普通攻擊與反擊可追加一擊")
	var weapon_flags := int(item["weapon_effect_flags"])
	if weapon_flags & 0x200000: lines.append("普通／反擊系列末擊命中後25%附毒")
	if weapon_flags & 0x400000:
		lines.append("普通／反擊末擊使目標損失魔力")
		lines.append("依該擊實際傷害的三分之一；自身不回魔")
	if weapon_flags & 0x10000:
		lines.append("系列末擊命中後10%取消本輪未用行動")
		lines.append("不阻止當前反擊或已開始的行動")
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
	return lines


## Description rows of any bag／loot／shop item for fill_box: equipment rows in the 0x430710
## colours of their rows, other rows (types 0／1, all "@1" after the name) green then white.
static func description_rows(details: Dictionary, lines: Array) -> Array:
	var colours := [BattleUISkin.TEXT_GREEN]
	if int(details.get("type_code", 1)) in range(2, 7):
		colours = _rows(details).map(func(row): return row[1])
	var rows := []
	for index in range(lines.size()):
		rows.append([[str(lines[index]), colours[index] if index < colours.size() else BattleUISkin.TEXT_WHITE]])
	return rows


## Half-width cells of `text` as 0x412030 counts them: a Big5 glyph 2, a byte below 0xa1 1 (the
## remake's ∼ stands for the half-width 0x17).
static func cells(text: String) -> int:
	var count := 0
	for character in text:
		count += 1 if character.unicode_at(0) < 0x80 or character == "∼" else 2
	return count


## Fills a WINDOW50 description box the way 0x436d70 has 0x412060 draw the text: row i at
## (8, 12 + 16i), up to four rows (the bottom clip), each centred on 45 half-width cells. A row
## is a String (the first green, the rest white) or a list of [text, colour] runs; an "@N" run
## change inside a row starts where the cells before it end, as 0x412060 draws each run.
static func fill_box(box: Control, rows: Array) -> void:
	for child in box.get_children():
		if child is Label:
			box.remove_child(child)
			child.queue_free()
	for index in range(mini(rows.size(), BOX_ROWS)):
		var runs: Array = rows[index] if rows[index] is Array else [[str(rows[index]), BattleUISkin.TEXT_GREEN if index == 0 else BattleUISkin.TEXT_WHITE]]
		var at := BOX_TEXT_AT + Vector2(0, index * BOX_ROW_PITCH)
		if runs.size() == 1:
			if str(runs[0][0]) == "": continue
			var row := BattleUISkin.text(box, at, runs[0][1], BattleUISkin.FONT_SMALL, Vector2(BOX_CELLS * BOX_CELL, BOX_ROW_PITCH))
			row.text = str(runs[0][0])
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			continue
		var total := 0
		for run in runs:
			total += cells(str(run[0]))
		var spare := BOX_CELLS - total
		var x := at.x + BOX_CELL * int(spare / 2.0) + ((BOX_CELL >> 1) if spare % 2 != 0 else 0)
		for run in runs:
			var width := cells(str(run[0])) * BOX_CELL
			if width > 0:
				var part := BattleUISkin.text(box, Vector2(x, at.y), run[1], BattleUISkin.FONT_SMALL, Vector2(width, BOX_ROW_PITCH))
				part.text = str(run[0])
			x += width

extends Control
## The skill page (特殊技 and 魔法) as the original draws it: its status window in root mode 3
## (special) or 2 (magic) — the WINDOW10 strip with portrait, bars and resists, the left
## WINDOW20 column listing the skills, the `$:` WINDOW40 gold box — and the 0x436d70
## description box for the hovered row. A row the actor cannot pay is red and still shows
## its description when hovered; clicking it does nothing. There is no title, list board,
## cursor bar or 取消 button: right click／Esc cancel. Past nine rows the 0x446060 scroll bar
## appears (arrows, trough paging, thumb drag, ↑↓／PgUp PgDn; no wheel). Choosing／cancelling
## returns intent to PlayLoop.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md#描述框-0x436d70
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##     (2026-09-26 Wine frames: all four boards at offset 0, rows, red row, hover)
##   strings: resource-derived content/imported/hsl/global/tables/MAGIC.TXT
##   strings: resource-derived content/imported/hsl/global/tables/SPECIAL.TXT
##   strings: resource-derived content/imported/hsl/chapter01/source_texts/RESOURCE.TXT
##   strings: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##   timing: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##     (hovered name green 236／244 in two Wine frames)
signal spell_selected(skill_id: String)
signal cancelled
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
## Left column: 0x43add0 docks WINDOW20 (object 132) at (12,174). 0x438160 case 2: first row
## 8 px below the top (+0x9a), 28 px rows (+0x98), nine rows per page (0x446060). Names at
## x+8+24 (0x4123b0); element gem MAGICON[type] at (x+15, row+2) (0x4607f9, table 0x4c3460).
## Rows are drawn from y+8−28·pos and clipped to (x, y+8)–(x+224, y+258): the ninth row
## loses its last 2 px.
const LIST_AT := Vector2(12, 174)
const LIST_SIZE := Vector2(224, 264)
const ROW_TOP := 8
const ROW_HEIGHT := 28
const VISIBLE_ROWS := 9
const LIST_CLIP_HEIGHT := 250
## 0x434d10 lists type by type (TYPE.H magicEARTH..magicOTHER2 = 0..6), each type's owned
## codes by bit (magicCode01 = bit 0). An authored code has no bit and follows its type's
## original bits, as its skill_book source_order does.
const LIST_TYPES := ["magicEARTH", "magicWATER", "magicAIR", "magicFIRE", "magicMIND", "magicOTHER", "magicOTHER2"]
## Scroll bar 0x446060: BattleSkillScrollBar at WINDOW20 + (200,0), shared with the status page.
const BattleSkillScrollBar = preload("res://game/battle/scene/BattleSkillScrollBar.gd")
const NAME_DX := 32
const GEM_AT := Vector2(15, 2)
## 0x438160 redraws the hovered name (0x4132f0 mode 1) in the 0x42c130 pulse colour — green
## 255 − 2·|p| with red and blue bases 0 — where p is the 0x42c110 counter stepping once a tick
## through −16..16 (33 ticks); not the @3 (205,255,205) the description title uses.
const HOVER_GREEN_BASE := 255
const HOVER_PULSE_HALF := 16
## 0x43af60 docks the `$:` WINDOW40 (object 134) at (416,440); the amount right-aligned in
## the status page's cell.
const GOLD_AT := Vector2(416, 440)
## Description box of 0x436d70 at the status-page position; rows (x+8, y+12+16i), 360 px centred.
const DESCRIPTION_AT := Vector2(252, 349)
const DESCRIPTION_SIZE := Vector2(376, 88)
## TYPE.H magicEARTH..magicMIND = 0..4 (magicOTHER／OTHER2 have no gem and no element word);
## RESOURCE.TXT 217–221 (0xd9 + type).
const ELEMENT_TYPES := ["magicEARTH", "magicWATER", "magicAIR", "magicFIRE", "magicMIND"]
const ELEMENT_WORDS := ["地系", "水系", "風系", "火系", "心靈系"]
## TYPE.H magicFun_* bits of the table `function` field.
const FUNCTION_BITS := {
	"magicFun_Attack": 0x1, "magicFun_Heal": 0x2, "magicFun_Paralysis": 0x4, "magicFun_Poison": 0x8,
	"magicFun_NoMagic": 0x10, "magicFun_DefUp": 0x20, "magicFun_AttUp": 0x40, "magicFun_AllUp": 0x100,
	"magicFun_CureParalysis": 0x200, "magicFun_CurePoison": 0x400, "magicFun_CureNoMagic": 0x800,
	"magicFun_Weaken": 0x1000, "magicFun_CureWeaken": 0x2000, "magicFun_ClearAtDfUp": 0x4000,
	"magicFun_HealMP": 0x8000, "magicFun_ActiveAgain": 0x10000, "magicFun_StealGold": 0x20000,
	"magicFun_StealItem": 0x40000, "magicFun_CancelActive": 0x80000, "magicFun_StealHP": 0x100000,
}
## Effect words of the power row in the order 0x433a90／0x4331b0 test them (RESOURCE.TXT ids in
## the packet): a full group prints its one word instead of the members.
const INFLICT_ALL := [0x101c, "所有狀態異常"]
const INFLICT := [[0x4, "痲痺敵人"], [0x8, "中毒傷害"], [0x10, "魔法封印效果"], [0x1000, "衰弱效果"]]
const CURE_ALL := [0x2e00, "回復人物正常狀態"]
const CURE := [[0x2000, "解除衰弱效果"], [0x200, "解除痲痺狀態"], [0x400, "治療中毒"], [0x800, "解除魔法封印"]]
const SUPPORT := [[0x20, "增加防禦力效果"], [0x40, "增加攻擊力效果"], [0x4000, "解除敵人附加攻防力"], [0x100, "所有魔法抗力上升"]]
## Only the special builder 0x433a90 goes on past 0x100.
const SPECIAL_ONLY := [[0x8000, "回復魔法"], [0x10000, "可再次行動"], [0x20000, "偷取金錢"], [0x40000, "偷取物品"], [0x80000, "取消行動"], [0x100000, "吸取敵人生命"]]
var choices: Dictionary = {}
var description_box: TextureRect
var vitals: Control
var gold_label: Label
var list: Control
var scroll_bar: BattleSkillScrollBar
var _rows: VBoxContainer
var _hover_name: Label
var _pulse_clock := 0.0


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	BattleUISkin.clear_panel(self)
	BattleUISkin.board(self, "WINDOW20", LIST_AT)
	list = Control.new()
	list.name = "Skills"
	list.position = LIST_AT + Vector2(0, ROW_TOP)
	list.size = Vector2(LIST_SIZE.x, LIST_CLIP_HEIGHT)
	list.clip_contents = true
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 0)
	list.add_child(_rows)
	scroll_bar = BattleSkillScrollBar.new(LIST_AT)
	scroll_bar.scrolled.connect(func(pos: int): _rows.position.y = -ROW_HEIGHT * pos)
	add_child(scroll_bar)
	BattleUISkin.board(self, "WINDOW40", GOLD_AT)
	gold_label = BattleUISkin.text(self, GOLD_AT + Vector2(80, 4), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(108, 24))
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	description_box = BattleUISkin.board(self, "WINDOW50", DESCRIPTION_AT)
	description_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	description_box.size = DESCRIPTION_SIZE
	description_box.name = "Description"
	description_box.hide()
	BattleUISkin.in_place(description_box)
	vitals = BattleVitals.new()
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	hide()


func _process(delta: float) -> void:
	if not visible: return
	_pulse_clock += delta
	if _hover_name != null: _hover_name.add_theme_color_override("font_color", hover_colour())


## The hovered name's colour this tick (0x42c130 on the 0x42c110 counter).
func hover_colour() -> Color:
	var period := 2 * HOVER_PULSE_HALF + 1
	var step := int(OriginalTick.ticks(_pulse_clock)) % period - HOVER_PULSE_HALF
	return Color8(0, HOVER_GREEN_BASE - 2 * absi(step), 0)


## Modal input while the page is up: right click / Esc cancel (BattleSceneRuntime.modal_panels
## dispatch); ↑↓／PgUp PgDn go to the scroll bar. Everything else is left to the rows and the bar.
func handle_input(event: InputEvent) -> bool:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		cancelled.emit()
		get_viewport().set_input_as_handled()
		return true
	return scroll_bar.handle_key(event)


## Moves the list to row `pos` (clamped) and puts the thumb where 0x445d70 does.
func scroll_to(pos: int) -> void:
	scroll_bar.scroll_to(pos)


## Row order of the page (0x434d10): type index × 32 + code bit.
static func list_order(option: Dictionary) -> int:
	var fields: Dictionary = option.get("fields", {})
	var code := str(fields.get("code", ""))
	var bit := int(code.trim_prefix("magicCode")) - 1 if code.begins_with("magicCode") else 31
	return LIST_TYPES.find(str(fields.get("type", ""))) * 32 + bit


## `unit` fills the status strip (the actor); `gold` the gold box.
func show_spells(options: Array, channel: String = "magic", unit: Dictionary = {}, gold: int = 0) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	choices.clear()
	_hover_name = null
	vitals.visible = not unit.is_empty()
	if vitals.visible: vitals.show_unit(unit)
	gold_label.text = str(gold)
	var ordered := range(options.size())
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var order_a := list_order(options[a])
		var order_b := list_order(options[b])
		return order_a < order_b or (order_a == order_b and a < b))
	for index in ordered:
		var option: Dictionary = options[index]
		var fields: Dictionary = option.get("fields", {})
		var row := Button.new()
		row.flat = true
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(LIST_SIZE.x, ROW_HEIGHT)
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			row.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		row.disabled = not option["quote"]["ok"]
		_rows.add_child(row)
		var element := ELEMENT_TYPES.find(str(fields.get("type", "")))
		if element >= 0: BattleUISkin.asset(row, "magicon%d" % (element + 1), GEM_AT)
		# 0x434d10 codes an affordable row @1 white and one 0x409040／0x408fe0 refuses @2 red.
		var rest := BattleUISkin.TEXT_RED if row.disabled else BattleUISkin.TEXT_WHITE
		var name_label := BattleUISkin.text(row, Vector2(NAME_DX, 0), rest, BattleUISkin.FONT_BODY)
		name_label.text = str(option["name"])
		var lines := description_lines(option, channel)
		# The hovered row's name pulses green (a red row too); no cursor bar is drawn.
		row.mouse_entered.connect(func():
			_hover_name = name_label
			name_label.add_theme_color_override("font_color", hover_colour())
			show_description(lines))
		row.mouse_exited.connect(func():
			if _hover_name == name_label: _hover_name = null
			name_label.add_theme_color_override("font_color", rest)
			hide_description())
		row.pressed.connect(func():
			if visible and not row.disabled and choices.get(option["id"]) == row:
				spell_selected.emit(option["id"]))
		choices[option["id"]] = row
	# Every opening starts at row 0: 0x43add0 creates WINDOW20 with +0xa0 = 2 and 0x438160's first
	# tick finds that unlike its page word (5 magic, 10 special), so it zeroes *0x4c1cd4.
	scroll_bar.reset(choices.size())
	hide_description()
	show()


## The four description rows of one option, as 0x433a90 (special) and 0x4331b0 (magic) write
## them: name (magic: `(地系)`…), cost (special: `, 屬性: 地系`…), power and effect words,
## hit rate with the target count.
static func description_lines(option: Dictionary, channel: String) -> Array:
	var fields: Dictionary = option.get("fields", {})
	var element := ELEMENT_TYPES.find(str(fields.get("type", "")))
	var special := channel == "special"
	var title := str(option["name"])
	if not special and element >= 0: title += " (%s)" % ELEMENT_WORDS[element]
	var cost := ("氣格消耗%s" if special else "魔法消耗%s") % str(fields.get("expend", "0"))
	if special and element >= 0: cost += ", 屬性: %s" % ELEMENT_WORDS[element]
	var bits := 0
	for word in str(fields.get("function", "")).split(","):
		bits |= int(FUNCTION_BITS.get(word.strip_edges(), 0))
	var parts := PackedStringArray()
	var damage: PackedStringArray = (str(fields.get("damage", "")) + ",0").split(",")
	var bounds := "%s~%s" % [damage[0].strip_edges(), damage[1].strip_edges()]
	if bits & 0x1: parts.append("基礎攻擊力" + bounds)
	elif bits & 0x2: parts.append("基礎回復力" + bounds)
	parts.append_array(_group_words(bits, INFLICT_ALL, INFLICT))
	parts.append_array(_group_words(bits, CURE_ALL, CURE))
	for pair in SUPPORT + (SPECIAL_ONLY if special else []):
		if bits & int(pair[0]): parts.append(pair[1])
	var target := "對象一名" if str(fields.get("effect_range", "")) == "range0Cell" else "對象多名"
	var hit := ("命中率%s%%,%s" if special else "魔法命中率%s%%, %s") % [str(fields.get("hit_ratio", "0")), target]
	return [title, cost, " ".join(parts), hit]


static func _group_words(bits: int, whole: Array, members: Array) -> PackedStringArray:
	if bits & int(whole[0]) == int(whole[0]): return PackedStringArray([whole[1]])
	var words := PackedStringArray()
	for pair in members:
		if bits & int(pair[0]): words.append(pair[1])
	return words


func show_description(lines: Array) -> void:
	if description_box == null: return
	for child in description_box.get_children():
		description_box.remove_child(child)
		child.queue_free()
	for index in range(mini(lines.size(), 4)):
		var row := BattleUISkin.text(description_box, Vector2(8, 12 + index * 16), BattleUISkin.TEXT_GREEN if index == 0 else BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, Vector2(360, 16))
		row.text = str(lines[index])
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_box.show()


func hide_description() -> void:
	if description_box != null: description_box.hide()


## The rows currently written in the description box (tests and captures read them).
func description_text() -> Array:
	var rows: Array = []
	if description_box == null or not description_box.visible: return rows
	for child in description_box.get_children():
		if child is Label: rows.append(child.text)
	return rows

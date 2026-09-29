extends Control
## Read-only inspection of values actually consumed by current combat rules. The page for a
## no_attack unit prints the original's ??? in the identity strip and the attribute rows
## (BattleVitals.mask); the equipment list stays readable as in the original's text block.
## The original opens the page from the action ring's 狀態 (0x444285, 0x43b4e0 mode 0) and
## from a click on a unit the player does not command (0x443cfa, mode 1) — the latter only
## when the unit is known (opens_for). Mode 1 builds no `$:` gold box (0x43af60 skipped).
## The left column opens on 屬性 (WINDOW21): 0x43ac10 sets root +0x94 = 4 and only a page
## button changes it (0x43a640 case 3); the item list is the 道具 page and the bag windows.
## Page buttons (0x43b0a0..0x43b230, docked y 387): mode 0 上一位 下一位 道具 狀態 魔法 特殊技,
## mode 1 only the four page buttons; the current page's button is drawn dark (0x10000000).
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   layout: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (§4 魔法／特殊技 pages: 0x43add0 WINDOW20 with the 0x446060 scroll bar past nine rows)
##   layout: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V05
##     (frame_006: status page fields, 魔擊力 percent suffix, WINDOW40 at the bottom right)
##   layout: remake-invented docs/OPTIONS.md
##     (OPT-INFO=公開: permanent-gain row and tooltips; OPT-GUIDE=提示: save／load／pending-loot／back buttons; OPT-GROWTH:
##     growth button)
##   strings: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V05
##     (魔擊力 %)
##   strings: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##   strings: remake-invented (tooltip prose and captions)
##   strings: remake-invented docs/OPTIONS.md (OPT-INFO=公開: the page never masks, every unit reads as known)
signal growth_requested(unit_id: String)
signal save_requested
signal load_requested
signal rewards_requested
## 上一位／下一位 (mode 0 only): step -1／+1 through the party.
signal member_step_requested(step: int)
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleMagicPanel = preload("res://game/battle/scene/BattleMagicPanel.gd")
const BattleSkillScrollBar = preload("res://game/battle/scene/BattleSkillScrollBar.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
var portrait: TextureRect
var equipment_labels: Dictionary = {}
var portraits: Dictionary
var growth_button: Button
var inspected_unit_id := ""
const UISkin = preload("res://game/common/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
var vitals: Control
var equipment_view: Control
var stat_values: Dictionary = {}
var rewards_button: Button
var gold_label: Label
var permanent_summary: Label
var gold_board: TextureRect
## save／load／pending loot／back: OPT-GUIDE=提示 only.
var hint_buttons: Array[Button] = []


## Left column: WINDOW21 (the frame with the nine baked 力量…移動力 labels) with the 升級
## window's static row geometry — the status page and mode 10 share Status_Window_2 at
## (12,174), 28 px text rows from y+8, attribute values at x 92 and derived rows at x 116
## (BattleGrowthPanel, docs/evidence_packets/static_reverse/original_growth_window.md §2–3).
const BattleGrowthPanel = preload("res://game/battle/scene/BattleGrowthPanel.gd")
const STAT_KEYS := ["str", "dex", "mind", "con", "attack", "defense", "magic", "speed", "move"]
## `$:` gold box: WINDOW40 at the bottom right of the page (06_status_and_stats_screen
## frame_006 template match (415,439) in the 638 px recording → 416 in 640), amount drawn
## as the 獲得物品 window's: nine cells right-aligned from (x+8, y+8), right edge x+188.
const GOLD_AT := Vector2(416, 439)
## Remake-only buttons (save／load／pending loot／growth／back) share the free strip left of
## the gold box; the original page has none, so they show only under OPT-GUIDE=提示 (the
## growth button follows the OPT-GROWTH postpone path: it shows while points are pending).
const BUTTON_Y := 443
const BUTTON_HEIGHT := 30
const BUTTON_FONT := 14
const BUTTONS_LEFT := 12
const BUTTON_GAP := 3
## Permanent-gain／birth summary (remake-invented, OPT-INFO=公開 only): the bottom band of
## the WINDOW50 box.
const SUMMARY_AT := Vector2(360, 416)
const SUMMARY_SIZE := Vector2(252, 22)
## Left-column pages: root +0x94 (the Data6 of the page button that set it).
const PAGE_ITEMS := 1
const PAGE_MAGIC := 2
const PAGE_SPECIAL := 3
const PAGE_STATUS := 4
## 0x43b0a0／0x43b230／0x43b140／0x43b0f0／0x43b190／0x43b1e0 build objects 137／142／138／141／139／140
## docked at (+0xaa, 387); the 42×42 icons are centred there (frame_028: first column x 264–304,
## rows 366–406). Shape and caption (obj_Data9 → RESOURCE 133／134／19／40／28／29) from obj-051.obs;
## the last field is the page (obj_Data6), -1 for the member steps that mode 1 skips.
const PAGE_BUTTON_Y := 387
const PAGE_BUTTONS := [
	["prev", "B_PREV1", "上一位", 285, -1],
	["next", "B_NEXT1", "下一位", 346, -1],
	["items", "BCMD03_1", "道具", 407, PAGE_ITEMS],
	["status", "BCMD13_1", "狀態", 468, PAGE_STATUS],
	["magic", "BCMD09_1", "魔法", 529, PAGE_MAGIC],
	["special", "BCMD10_1", "特殊技", 590, PAGE_SPECIAL],
]
## 道具 page: eight 32 px bag rows from the board's y + 8, icon anchored at x 44 and the name at
## x 68 as the 獲得物品 window's bag (original_getitem_window.md, board y 168 → 174 here).
const BAG_ROW := 32
## Description box of the 道具／魔法／特殊技 rows: WINDOW50 at (252,349), up to four 15 px rows
## at (x+8, y+12+16i), 360 px centred, first row green (0x436d70).
const PAGE_DETAIL_AT := Vector2(252, 349)
var page := PAGE_STATUS
var page_buttons: Dictionary = {}
var page_captions: Dictionary = {}
## WINDOW21 and its nine values (direct children, so BattlePanelMotion slides them).
var attribute_nodes: Array[Control] = []
var page_root: Control
var page_detail: Control
## 魔法／特殊技 pages: the 0x446060 bar of their WINDOW20 (null on the other pages).
var skill_scroll: BattleSkillScrollBar
var _unit: Dictionary = {}
var _loop: Dictionary = {}
var _own_page := true


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.clear_panel(self)
	# Screen-wide wrapper: BattlePanelMotion opens it one level and slides the page's boards.
	page_root = Control.new()
	page_root.size = Vector2(640, 480)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_root)
	attribute_nodes.append(UISkin.asset(self, "WINDOW21", BattleGrowthPanel.LEFT))
	portraits = preload("res://game/sim/ContentPaths.gd").actor_portraits()
	for index in range(STAT_KEYS.size()):
		var top := BattleGrowthPanel.LEFT.y + 8 + index * BattleGrowthPanel.ROW_HEIGHT
		var x: int = BattleGrowthPanel.ATTRIBUTE_VALUE_X if index < 4 else BattleGrowthPanel.DERIVED_VALUE_X
		var value := UISkin.text(self, Vector2(x, top), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(0, BattleGrowthPanel.GLYPH_ROW))
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_values[STAT_KEYS[index]] = value
		attribute_nodes.append(value)
	permanent_summary = UISkin.label(self, SUMMARY_AT, 14)
	permanent_summary.size = SUMMARY_SIZE
	permanent_summary.clip_text = true
	permanent_summary.mouse_filter = Control.MOUSE_FILTER_STOP
	for spec in PAGE_BUTTONS:
		_page_button(spec[0], spec[1], spec[2], spec[3], spec[4])
	equipment_view = preload("res://game/battle/scene/BattleEquipmentView.gd").new()
	add_child(equipment_view)
	# Keep the optional summary above the equipment description background.
	move_child(permanent_summary, get_child_count()-1)
	equipment_labels = equipment_view.labels
	gold_board = UISkin.board(self, "WINDOW40", GOLD_AT)
	gold_label = UISkin.text(self, GOLD_AT + Vector2(80, 4), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(108, 24))
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var save := _button("保存 F5", 72)
	save.pressed.connect(func(): save_requested.emit())
	var load_button := _button("讀取 F9", 72)
	load_button.pressed.connect(func(): load_requested.emit())
	rewards_button = _button("待領物品", 84)
	rewards_button.pressed.connect(func(): rewards_requested.emit())
	growth_button = _button("分配成長點", 96)
	growth_button.pressed.connect(func(): growth_requested.emit(inspected_unit_id))
	var close := _button("返回", 60)
	close.tooltip_text = "空格 / Esc / 右鍵返回"
	close.pressed.connect(hide)
	hint_buttons = [save, load_button, rewards_button, close]
	page_detail = Control.new()
	page_detail.name = "PageDescription"
	page_detail.position = PAGE_DETAIL_AT
	page_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.board(page_detail, "WINDOW50", Vector2.ZERO)
	page_detail.hide()
	UISkin.in_place(page_detail)
	add_child(page_detail)
	vitals = BattleVitals.new()
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	portrait = vitals.portrait
	hide()


var _buttons_right := BUTTONS_LEFT


## One page button: the icon centred on its dock point, the 15 px caption centred under it at
## centre_y + 13, yellow while hovered (0x43a640, as BattleLootPanel's buttons).
func _page_button(key: String, resource: String, caption: String, centre_x: int, target_page: int) -> void:
	var button := TextureButton.new()
	button.name = "Page_" + key
	button.texture_normal = load(UISkin.ROOT + resource + ".SHP.png")
	button.position = Vector2(centre_x - 21, PAGE_BUTTON_Y - 21)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(button)
	var label := UISkin.text(self, Vector2(centre_x - 40, PAGE_BUTTON_Y + 13), UISkin.TEXT_WHITE, UISkin.FONT_SMALL, Vector2(80, 16))
	label.name = "Caption_" + key
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_entered.connect(func(): label.add_theme_color_override("font_color", UISkin.TEXT_YELLOW))
	button.mouse_exited.connect(func(): label.add_theme_color_override("font_color", UISkin.TEXT_WHITE))
	match key:
		"prev": button.pressed.connect(func(): member_step_requested.emit(-1))
		"next": button.pressed.connect(func(): member_step_requested.emit(1))
		_: button.pressed.connect(func(): set_page(target_page))
	page_buttons[key] = button
	page_captions[key] = label


## Switches the left column (0x43a640 case 3: root +0x94 = the button's Data6).
func set_page(next_page: int) -> void:
	page = next_page
	for spec in PAGE_BUTTONS:
		var button: TextureButton = page_buttons[spec[0]]
		button.visible = int(spec[4]) >= 0 or _own_page
		page_captions[spec[0]].visible = button.visible
		button.self_modulate = Color(0.45, 0.45, 0.45) if int(spec[4]) == page else Color.WHITE
	for node in attribute_nodes:
		node.visible = page == PAGE_STATUS
	for child in page_root.get_children():
		page_root.remove_child(child)
		child.queue_free()
	page_detail.hide()
	skill_scroll = null
	match page:
		PAGE_ITEMS: _build_bag()
		PAGE_MAGIC, PAGE_SPECIAL: _build_skills()


func _build_bag() -> void:
	UISkin.board(page_root, "WINDOW20", BattleGrowthPanel.LEFT)
	var catalog := preload("res://game/sim/EquipmentCatalog.gd").items()
	var inventory: Array = _unit.get("inventory", [])
	for index in range(inventory.size()):
		var code := str(int(inventory[index]))
		if code == "0" or not catalog.has(code):
			continue
		var details: Dictionary = catalog[code]
		var row := _hover_row(BattleGrowthPanel.LEFT + Vector2(8, 8 + index * BAG_ROW), Vector2(208, BAG_ROW))
		row.name = "Bag_%d" % index
		UISkin.anchored_asset(row, str(details["icon"]), Vector2(24, 8))
		var label := UISkin.text(row, Vector2(48, 0), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(160, BAG_ROW))
		label.text = str(details["name"])
		_hover_lines(row, label, UISkin.TEXT_WHITE, _item_lines(details, code))


func _item_lines(details: Dictionary, code: String) -> Array:
	var definition: Dictionary = (_loop.get(LoopKeys.CONSUMABLES, {}) as Dictionary).get(code, {})
	return preload("res://game/battle/scene/BattleItemText.gd").description_lines(details, definition).filter(func(line): return str(line) != "")


## 魔法／特殊技 pages: the unit's list in the skill page's order and row geometry, @1 white or
## @2 red when it cannot pay (BattleMagicPanel); read-only. Mode 0 builds WINDOW20 through
## 0x43add0 like the skill page, whose 0x438330 always hangs the 0x446060 bar on it: past nine
## rows the shared BattleSkillScrollBar appears, and each page switch starts at row 0 (0x438160
## sees a new page word).
func _build_skills() -> void:
	UISkin.board(page_root, "WINDOW20", BattleMagicPanel.LIST_AT)
	if _loop.is_empty():
		return
	var channel := "magic" if page == PAGE_MAGIC else "special"
	var options: Array = BattlePlayLoop.magic_options(_loop, inspected_unit_id) if page == PAGE_MAGIC else BattlePlayLoop.special_options(_loop, inspected_unit_id)
	options.sort_custom(func(a, b): return BattleMagicPanel.list_order(a) < BattleMagicPanel.list_order(b))
	var clip := Control.new()
	clip.name = "Skills"
	clip.position = BattleMagicPanel.LIST_AT + Vector2(0, BattleMagicPanel.ROW_TOP)
	clip.size = Vector2(BattleMagicPanel.LIST_SIZE.x, BattleMagicPanel.LIST_CLIP_HEIGHT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(clip)
	var rows := Control.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(rows)
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var row := _hover_row(Vector2(0, index * BattleMagicPanel.ROW_HEIGHT), Vector2(BattleMagicPanel.LIST_SIZE.x - 24, BattleMagicPanel.ROW_HEIGHT), rows)
		row.name = "Skill_%d" % index
		var element := BattleMagicPanel.ELEMENT_TYPES.find(str(option.get("fields", {}).get("type", "")))
		if element >= 0: UISkin.asset(row, "magicon%d" % (element + 1), BattleMagicPanel.GEM_AT)
		var rest := UISkin.TEXT_WHITE if option["quote"]["ok"] else UISkin.TEXT_RED
		var label := UISkin.text(row, Vector2(BattleMagicPanel.NAME_DX, 0), rest, UISkin.FONT_BODY)
		label.text = str(option["name"])
		_hover_lines(row, label, rest, BattleMagicPanel.description_lines(option, channel))
	skill_scroll = BattleSkillScrollBar.new(BattleMagicPanel.LIST_AT)
	skill_scroll.scrolled.connect(func(pos: int): rows.position.y = -BattleMagicPanel.ROW_HEIGHT * pos)
	page_root.add_child(skill_scroll)
	skill_scroll.reset(options.size())


func _hover_row(at: Vector2, dimensions: Vector2, parent: Control = null) -> Control:
	var row := Control.new()
	row.position = at
	row.size = dimensions
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	(parent if parent != null else page_root).add_child(row)
	return row


## Hovering a row greens its name and writes up to four lines into WINDOW50 over the buttons.
func _hover_lines(row: Control, label: Label, rest: Color, lines: Array) -> void:
	row.mouse_entered.connect(func():
		label.add_theme_color_override("font_color", UISkin.TEXT_GREEN)
		for child in page_detail.get_children():
			if child is Label:
				page_detail.remove_child(child)
				child.queue_free()
		for index in range(mini(lines.size(), 4)):
			var text := UISkin.text(page_detail, Vector2(8, 12 + index * 16), UISkin.TEXT_GREEN if index == 0 else UISkin.TEXT_WHITE, UISkin.FONT_SMALL, Vector2(360, 16))
			text.text = str(lines[index])
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page_detail.show())
	row.mouse_exited.connect(func():
		label.add_theme_color_override("font_color", rest)
		page_detail.hide())


func _button(title: String, width: int) -> Button:
	var control := UISkin.button(self, title, Vector2(_buttons_right, BUTTON_Y), Vector2(width, BUTTON_HEIGHT))
	control.add_theme_font_size_override("font_size", BUTTON_FONT)
	control.size = Vector2(width, BUTTON_HEIGHT)
	_buttons_right += width + BUTTON_GAP
	return control


## Modal input while the sheet is up: right click / Esc／Enter／Space close it
## (BattleSceneRuntime.modal_panels dispatch). Unlike the other modals the closing event is
## not marked handled — the runtime dispatcher never did, and GUI focus keeps its turn.
## On a 魔法／特殊技 page ↑↓／PgUp PgDn go to its scroll bar.
func handle_input(event: InputEvent) -> bool:
	if skill_scroll != null and skill_scroll.handle_key(event):
		return true
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]):
		hide()
		return true
	return false


## Whether a click on a unit the player does not command opens its page: the original only
## for a known unit (0x443cfa reads the known byte; unknown falls to 0x443d9d like a click
## on empty ground). OPT-INFO=公開 (read once per click) reads every unit as known.
static func opens_for(known: bool) -> bool:
	return known or not GameOptions.is_original("OPT-INFO")


## `known`: BattlePlayLoop.unit_known; OPT-INFO=公開 (read once as the page opens) reads every
## unit as known, so an enemy's numbers show before anyone has attacked it, and brings back
## the permanent-gain row and tooltips. `own_page`: the action ring's 狀態 (mode 0) with its
## `$:` box; false for the page a click on another unit opens (mode 1, no gold box).
## OPT-GUIDE=提示 (read once as the page opens) shows the save／load／loot／back buttons.
## `loop` (BattlePlayLoop state, read only) feeds the 道具 page's consumable lines and the
## 魔法／特殊技 lists. Every open starts on 屬性 (0x43ac10 root +0x94 = 4).
func show_unit(unit: Dictionary, known: bool = true, own_page: bool = true, loop: Dictionary = {}) -> void:
	var public := not GameOptions.is_original("OPT-INFO")
	_unit = unit
	_loop = loop
	_own_page = own_page
	known = known or public
	for control in hint_buttons:
		control.visible = not GameOptions.is_original("OPT-GUIDE")
	gold_board.visible = own_page
	gold_label.visible = own_page
	inspected_unit_id = str(unit["id"])
	var profile := CoreCombatRules.combat_profile_from_unit(unit)
	var masked: bool = BattleVitals.mask(unit, known)["identity"]
	permanent_summary.text = PermanentCapabilityRules.description(unit)
	permanent_summary.tooltip_text = permanent_summary.text.replace("、", "\n") + "\n與力量、反應、精神、體質分開累計"
	if unit.has("entry_growth"):
		var birth := EntryGrowthRules.description(unit)
		permanent_summary.text = birth + (" · 永久加成" if PermanentCapabilityRules.active(unit) else "")
		permanent_summary.tooltip_text = birth + "\n入場時確定的固有能力；換裝與讀取進度不會重複增加。\n" + PermanentCapabilityRules.description(unit)
	permanent_summary.visible = public and not permanent_summary.text.is_empty() and not masked
	vitals.show_unit(unit, -1, known)
	for index in range(5):
		var key := "resist_" + str(index)
		var source := PermanentCapabilityRules.base_value(unit, key)
		var gained := int(unit["permanent_gains"][key])
		vitals.resist_values[index].tooltip_text = "原始 %d ＋ 永久 %d ＝ %d / 80\n職業與裝備另計；最終抗性上限80%%" % [source, gained, source + gained] if source >= 0 and not masked and public else ""
		vitals.resist_values[index].mouse_filter = Control.MOUSE_FILTER_STOP if public else Control.MOUSE_FILTER_IGNORE
	equipment_view.show_unit(unit)
	# 0x448840 shows the live attributes: an active 衰弱 subtracts its power from all four.
	var live_attributes: Dictionary = preload("res://game/sim/StatusEffectRules.gd").weakened_attributes(unit) if unit.get("status_counters") is Dictionary else profile
	var values := {"str": int(live_attributes["str"]), "dex": int(live_attributes["dex"]), "mind": int(live_attributes["mind"]), "con": int(live_attributes["con"]), "attack": int(profile["live_attack_damage"]), "defense": int(profile["live_defense"]), "magic": int(profile["live_magic_attack"]), "speed": int(unit["live_speed"]), "move": int(unit["move_point"])}
	for key in values:
		if masked:
			# 0x434d10 writes ??? in place of every 0x434bf0 attribute row (bVar22 ‖ bVar21).
			stat_values[key].text = "???"
			stat_values[key].tooltip_text = ""
			stat_values[key].mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		stat_values[key].text = str(values[key]) + ("%" if key == "magic" else "")
		var permanent_key: String = {"attack":"attack_power","defense":"defense","magic":"magic_attack_power","speed":"speed"}.get(key,"")
		var permanent := int(unit["permanent_gains"].get(permanent_key,0))
		stat_values[key].tooltip_text = "含永久獲得 +%d；不含在四項基礎屬性內" % permanent if permanent>0 and public else ""
		if public and unit.has("entry_growth") and unit["entry_growth"]["result"]["source_gains"].has(permanent_key):
			var birth_bonus := EntryGrowthRules.source_gain(unit, permanent_key)
			if birth_bonus > 0: stat_values[key].tooltip_text += "\n含入場固有加成 +%d，與永久道具、裝備及臨時增益分開。" % birth_bonus
		stat_values[key].mouse_filter = Control.MOUSE_FILTER_STOP if not stat_values[key].tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
		if key in ["attack", "defense"]:
			var bonus := preload("res://game/sim/StatEnhancementRules.gd").power(unit, key + "_up")
			if bonus > 0: stat_values[key].text += " (+%d)" % bonus
	growth_button.visible = bool(unit.get("player_commandable", false)) and int(unit.get("pending_stat_points", 0)) > 0
	growth_button.text = "成長點  %d" % int(unit.get("pending_stat_points", 0))
	set_page(PAGE_STATUS)
	show()

extends Control
## Read-only inspection of values actually consumed by current combat rules. The page for a
## no_attack unit prints the original's ??? in the identity strip and the attribute rows
## (BattleVitals.mask); the equipment list stays readable as in the original's text block.
## The original opens the page from the action ring's 狀態 (0x444285, 0x43b4e0 mode 0) and
## from a click on a unit the player does not command (0x443cfa, mode 1) — the latter only
## when the unit is known (opens_for). Mode 1 builds no `$:` money box (0x43af60 skipped).
## The left column opens on 屬性 (WINDOW21): 0x43ac10 sets root +0x94 = 4 and only a page
## button changes it (0x43a640 case 3); the item list is the 道具 page and the bag windows.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   layout: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
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
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
var portrait: TextureRect
var equipment_labels: Dictionary = {}
var portraits: Dictionary
var growth_button: Button
var inspected_unit_id := ""
const UISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
var vitals: Control
var equipment_view: Control
var stat_values: Dictionary = {}
var rewards_button: Button
var money_label: Label
var permanent_summary: Label
var money_board: TextureRect
## save／load／pending loot／back: OPT-GUIDE=提示 only.
var hint_buttons: Array[Button] = []


## Left column: WINDOW21 (the frame with the nine baked 力量…移動力 labels) with the 升級
## window's static row geometry — the status page and mode 10 share Status_Window_2 at
## (12,174), 28 px text rows from y+8, attribute values at x 92 and derived rows at x 116
## (BattleGrowthPanel, docs/evidence_packets/static_reverse/original_growth_window.md §2–3).
const BattleGrowthPanel = preload("res://game/battle/scene/BattleGrowthPanel.gd")
const STAT_KEYS := ["str", "dex", "mind", "con", "attack", "defense", "magic", "speed", "move"]
## `$:` money box: WINDOW40 at the bottom right of the page (06_status_and_stats_screen
## frame_006 template match (415,439) in the 638 px recording → 416 in 640), amount drawn
## as the 獲得物品 window's: nine cells right-aligned from (x+8, y+8), right edge x+188.
const MONEY_AT := Vector2(416, 439)
## Remake-only buttons (save／load／pending loot／growth／back) share the free strip left of
## the money box; the original page has none, so they show only under OPT-GUIDE=提示 (the
## growth button follows the OPT-GROWTH postpone path: it shows while points are pending).
const BUTTON_Y := 443
const BUTTON_HEIGHT := 30
const BUTTON_FONT := 14
const BUTTONS_LEFT := 12
const BUTTON_GAP := 3
## Permanent-gain／birth summary (remake-invented, OPT-INFO=公開 only): the bottom band of
## the WINDOW50 box.
const SUMMARY_AT := Vector2(360, 411)
const SUMMARY_SIZE := Vector2(252, 24)


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UISkin.clear_panel(self)
	UISkin.asset(self, "WINDOW21", BattleGrowthPanel.LEFT)
	portraits = preload("res://game/sim/ContentPaths.gd").actor_portraits()
	for index in range(STAT_KEYS.size()):
		var top := BattleGrowthPanel.LEFT.y + 8 + index * BattleGrowthPanel.ROW_HEIGHT
		var x: int = BattleGrowthPanel.ATTRIBUTE_VALUE_X if index < 4 else BattleGrowthPanel.DERIVED_VALUE_X
		var value := UISkin.text(self, Vector2(x, top), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(0, BattleGrowthPanel.GLYPH_ROW))
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_values[STAT_KEYS[index]] = value
	permanent_summary = UISkin.label(self, SUMMARY_AT, 14)
	permanent_summary.size = SUMMARY_SIZE
	permanent_summary.clip_text = true
	permanent_summary.mouse_filter = Control.MOUSE_FILTER_STOP
	equipment_view = preload("res://game/battle/scene/BattleEquipmentView.gd").new()
	add_child(equipment_view)
	# Keep the optional summary above the equipment description background.
	move_child(permanent_summary, get_child_count()-1)
	equipment_labels = equipment_view.labels
	money_board = UISkin.board(self, "WINDOW40", MONEY_AT)
	money_label = UISkin.text(self, MONEY_AT + Vector2(80, 4), UISkin.TEXT_WHITE, UISkin.FONT_BODY, Vector2(108, 24))
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	vitals = BattleVitals.new()
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	portrait = vitals.portrait
	# Status windows step the ST overlay pulse on their own counter (no 0x10000, BattleStaminaBar).
	vitals.st_bar.shared_pulse = false
	hide()


var _buttons_right := BUTTONS_LEFT


func _button(title: String, width: int) -> Button:
	var control := UISkin.button(self, title, Vector2(_buttons_right, BUTTON_Y), Vector2(width, BUTTON_HEIGHT))
	control.add_theme_font_size_override("font_size", BUTTON_FONT)
	control.size = Vector2(width, BUTTON_HEIGHT)
	_buttons_right += width + BUTTON_GAP
	return control


## Modal input while the sheet is up: right click / Esc／Enter／Space close it
## (BattleSceneRuntime.modal_panels dispatch). Unlike the other modals the closing event is
## not marked handled — the runtime dispatcher never did, and GUI focus keeps its turn.
func handle_input(event: InputEvent) -> bool:
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
## `$:` box; false for the page a click on another unit opens (mode 1, no money box).
## OPT-GUIDE=提示 (read once as the page opens) shows the save／load／loot／back buttons.
func show_unit(unit: Dictionary, known: bool = true, own_page: bool = true) -> void:
	var public := not GameOptions.is_original("OPT-INFO")
	known = known or public
	for control in hint_buttons:
		control.visible = not GameOptions.is_original("OPT-GUIDE")
	money_board.visible = own_page
	money_label.visible = own_page
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
	show()

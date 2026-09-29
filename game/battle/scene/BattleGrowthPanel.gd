extends Control
## Original 升級 window (status mode 10, docs/evidence_packets/static_reverse/original_growth_window.md).
## Draft choices only: OK submits once through PlayLoop.allocate_growth; the window cannot be
## closed before every point is placed (`hide()` stays the harness skip seam). A multi-level
## award opens one window per level (0x442a22: phase 8 reopens while points are left), each
## placing that level's five points; BattleSceneMenus.allocate_growth opens the next. OPT-GROWTH
## (docs/OPTIONS.md), read as the window opens: 合成一窗，可暫緩 shows every pending point in one
## window and lets right click／Esc close it with the points kept (Status 成長點 reopens it).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   rules: remake-invented docs/OPTIONS.md
##     (OPT-GROWTH=合成一窗，可暫緩 only: one window for every pending point, right click／Esc postpone them)
##   layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_growth_window.md#8-录屏对照r7-ui
##     (unavailable buttons are not drawn: ＋ needs a point left, － a draft point on its row, OK all placed)
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   strings: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
signal allocation_requested(unit_id: String, allocation: Dictionary)
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const ATTRIBUTES := ["str", "dex", "mind", "con"]
const DERIVED := ["attack", "defense", "magic", "speed", "move"]
## WINDOW21 at (12,174): nine 28 px rows from y+8; attribute values after six half-width cells
## (x = 92), derived rows after eight (x = 116) — the original text slot's space padding.
const LEFT := Vector2(12, 174)
const ROW_HEIGHT := 28
## Each row's text is the 24 px FONT.24 glyph row drawn from the row top (y+8+28·row).
const GLYPH_ROW := 24
const ATTRIBUTE_VALUE_X := 92
const DERIVED_VALUE_X := 116
## BT_ADD1 (+) / BT_ADD2 (−) at x 159 / 196, y 181 + 28·row; BT_OK at (168,395); WINDOW41 at (20,442).
const BUTTON_X := [159, 196]
const BUTTON_Y := 181
const OK_AT := Vector2(168, 395)
const POINTS_BOX := Vector2(20, 442)
## WINDOW31 (學會魔法) at (252,174) and WINDOW50 (學會特殊技) at (252,344); text from (x+8, y+10), row 26.
const MAGIC_BOX := Vector2(252, 174)
const SPECIAL_BOX := Vector2(252, 344)
const MESSAGE_ROW := 26
## 0x434d10 sets bit 8 of its flag word (0x434daf) only for an object whose +0xa2 word is 7
## (SID_PLAYER7, actor 008 咕嚕), whatever the caller; 0x434bf0 then skips the @5 near-cap yellow.
const NO_NEAR_CAP_SID := 7
## 0x434bf0 appends byte 0x1a before a differing live value; ASCFONT.24 glyph 0x1a is a right arrow.
const LIVE_ARROW := "→"
static var _actor_sids: Dictionary = {}
var source_unit: Dictionary
var skill_book: Dictionary = {}
var draft: Dictionary = {}
var choices: Dictionary = {}
var derived_values: Dictionary = {}
var confirm_button: TextureButton
var remaining_label: Label
var magic_box: Control
var special_box: Control
var vitals: Control
## OPT-GROWTH read when the window opens (show_unit): false on the original path.
var postpone_allowed := false
## Points this window places: one level's five on the original path (0x439f70 per window),
## every pending point when merged; `shown_level` is the level that window stands for.
var window_points := 0
var shown_level := 0


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	BattleUISkin.clear_panel(self)
	BattleUISkin.asset(self, "WINDOW21", LEFT)
	for index in range(ATTRIBUTES.size() + DERIVED.size()):
		var top := LEFT.y + 8 + index * ROW_HEIGHT
		var attribute_row := index < ATTRIBUTES.size()
		var value := BattleUISkin.text(self, Vector2(ATTRIBUTE_VALUE_X if attribute_row else DERIVED_VALUE_X, top), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(60, GLYPH_ROW))
		if attribute_row:
			var key: String = ATTRIBUTES[index]
			var plus := _button(BattleUISkin.ROOT + "BT_ADD1.SHP.png", Vector2(BUTTON_X[0], BUTTON_Y + index * ROW_HEIGHT))
			plus.pressed.connect(_adjust.bind(key, 1))
			var minus := _button(BattleUISkin.data()["assets"]["BT_ADD2"]["res_path"], Vector2(BUTTON_X[1], BUTTON_Y + index * ROW_HEIGHT))
			minus.pressed.connect(_adjust.bind(key, -1))
			choices[key] = {"plus": plus, "minus": minus, "value": value}
		else:
			derived_values[DERIVED[index - ATTRIBUTES.size()]] = value
	confirm_button = _button(BattleUISkin.ROOT + "BT_OK.SHP.png", OK_AT)
	confirm_button.pressed.connect(_confirm)
	BattleUISkin.asset(self, "WINDOW41", POINTS_BOX)
	remaining_label = BattleUISkin.text(self, POINTS_BOX + Vector2(128, 6), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(72, 24))
	remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	magic_box = _message_box("WINDOW31", MAGIC_BOX)
	special_box = _message_box("WINDOW50", SPECIAL_BOX)
	vitals = preload("res://game/battle/scene/BattleVitals.gd").new()
	vitals.position = Vector2(0, 14)
	add_child(vitals)
	hide()


func _button(texture_path: String, at: Vector2) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(texture_path)
	button.position = at
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(button)
	return button


func _message_box(resource: String, at: Vector2) -> Control:
	var box := Control.new()
	box.position = at
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var board := BattleUISkin.asset(box, resource, Vector2.ZERO) if resource == "WINDOW31" else BattleUISkin.board(box, resource, Vector2.ZERO)
	# The box is a window object of its own (0x43aec0／0x43af10, from the right): sized to its
	# board it slides as one part.
	box.size = board.texture.get_size()
	box.hide()
	return box


## Modal input while allocating (BattleSceneRuntime.modal_panels dispatch): every event is
## swallowed. Right click / Esc do not close it — the original's mode 10 root carries flag
## 0x400 (0x43bbd3) and its close branch skips on that flag (0x438839), with no message or
## sound; only OK, shown once every point is placed, closes the window. OPT-GROWTH=合成一窗，
## 可暫緩 closes it there without spending points.
func handle_input(event: InputEvent) -> bool:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if postpone_allowed: hide()
		get_viewport().set_input_as_handled()
		return true
	return false


func show_unit(unit: Dictionary, book: Dictionary = {}) -> void:
	postpone_allowed = not GameOptions.is_original("OPT-GROWTH")
	source_unit = unit.duplicate(true)
	var pending := int(source_unit.get("pending_stat_points", 0))
	window_points = pending if postpone_allowed else mini(ProgressionRules.POINTS_PER_LEVEL, pending)
	# The original raises the level as each window opens: the windows still to come after
	# this one are levels the remake has already settled, shown here one below per window.
	var later_windows := 0 if postpone_allowed else ceili(float(pending - window_points) / ProgressionRules.POINTS_PER_LEVEL)
	shown_level = int(source_unit["level"]) - later_windows
	skill_book = book
	draft.clear()
	_refresh()
	show()


func _adjust(key: String, amount: int) -> void:
	var proposed := draft.duplicate()
	proposed[key] = int(proposed.get(key, 0)) + amount
	if int(proposed[key]) <= 0: proposed.erase(key)
	var cost := ProgressionRules.allocation_cost(proposed)
	if cost < 0 or cost > window_points or not ProgressionRules.can_allocate(source_unit, proposed):
		return
	draft = proposed
	_refresh()


func _refresh() -> void:
	var remaining := window_points - ProgressionRules.allocation_cost(draft)
	var preview := ProgressionRules.apply_allocation(source_unit, draft, EquipmentCatalog.items())
	var profile: Dictionary = preview["combat_profile"]
	for key in ATTRIBUTES:
		# Mode 10 passes live = base (0x4356f1), so the window never shows the 0x1a suffix.
		show_attribute(choices[key]["value"], attribute_text(source_unit, key, int(profile[key]), int(profile[key])))
		var plus_draft := draft.duplicate()
		plus_draft[key] = int(plus_draft.get(key, 0)) + 1
		_set_enabled(choices[key]["plus"], remaining > 0 and ProgressionRules.can_allocate(source_unit, plus_draft))
		_set_enabled(choices[key]["minus"], int(draft.get(key, 0)) > 0)
	derived_values["attack"].text = str(int(profile["live_attack_damage"]))
	derived_values["defense"].text = str(int(profile["live_defense"]))
	derived_values["magic"].text = "%d%%" % int(profile["live_magic_attack"])
	derived_values["speed"].text = str(int(preview["live_speed"]))
	derived_values["move"].text = str(int(preview["move_point"]))
	remaining_label.text = str(remaining)
	# The original OK only lights once every point is placed; empty drafts cannot be submitted.
	_set_enabled(confirm_button, remaining == 0 and ProgressionRules.allocation_cost(draft) > 0)
	var magics: Array = source_unit.get("learned_skills", []).filter(func(row): return str(row["id"]).begins_with("magic:") and row.get("trigger") == "level_up" and int(row["level"]) == shown_level)
	_show_messages(magic_box, "學會魔法:", magics.map(func(row): return str(row["name"])))
	var specials: Array = ProgressionRules.Learning.acquire(preview, skill_book, "special")["added"] if not skill_book.is_empty() else []
	_show_messages(special_box, "學會特殊技:", specials.map(func(row): return str(row["name"])))
	vitals.show_unit(_shown_unit())


## The vitals strip as the original shows it at this window: its level, and the EXP before
## the later levels' thresholds come off (0x43a140 init: level +1, exp −= next per window).
func _shown_unit() -> Dictionary:
	if shown_level == int(source_unit["level"]): return source_unit
	var shown := source_unit.duplicate()
	for level in range(shown_level, int(source_unit["level"])):
		shown["exp"] = int(shown["exp"]) + ProgressionRules.exp_to_next(level)
	shown["level"] = shown_level
	return shown


## The original's flag 0x10000000 on an unavailable button hides it (recording 341–350 s):
## no dimmed ＋／－／OK is ever drawn.
func _set_enabled(button: TextureButton, enabled: bool) -> void:
	button.disabled = not enabled
	button.visible = enabled


func _show_messages(box: Control, heading: String, names: Array) -> void:
	for child in box.get_children():
		if child is Label: box.remove_child(child); child.queue_free()
	box.visible = not names.is_empty()
	if names.is_empty(): return
	var lines: Array = [heading] + names
	for index in range(lines.size()):
		BattleUISkin.text(box, Vector2(8, 10 + index * MESSAGE_ROW), BattleUISkin.TEXT_GREEN if index == 0 else BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(360, 24)).text = str(lines[index])


func _confirm() -> void:
	if visible and not confirm_button.disabled:
		allocation_requested.emit(str(source_unit["id"]), draft.duplicate())


## One attribute row of 0x434d10 (升級 window mode 10, 狀態 window, battle status page) as
## 0x434bf0(buf, base, live, cap, flag) writes it: base ≥ cap in @2 red; cap−50 ≤ base with the
## flag clear in @5 yellow; otherwise @1 white. Digits from 0x45b6de(base, …, 10, 4, 0): at most
## three, no padding. When base ≠ live, byte 0x1a + live follows the closing @1, so the suffix
## is white. A unit without a cap for the key stays white.
static func attribute_text(unit: Dictionary, key: String, base: int, live: int) -> Dictionary:
	var caps: Dictionary = unit.get("growth_profile", {}).get("caps", {})
	var color := BattleUISkin.TEXT_WHITE
	if caps.has(key) and base >= int(caps[key]):
		color = BattleUISkin.TEXT_RED
	elif caps.has(key) and base >= int(caps[key]) - 50 and _actor_sid(unit) != NO_NEAR_CAP_SID:
		color = BattleUISkin.TEXT_YELLOW
	return {"text": str(base), "color": color, "suffix": "" if base == live else LIVE_ARROW + str(live)}


## Writes an attribute_text row into a value label; the suffix sits in a white child label
## right after the digits.
static func show_attribute(value: Label, row: Dictionary) -> void:
	value.text = row["text"]
	value.add_theme_color_override("font_color", row["color"])
	var suffix: Label = value.get_node_or_null("LiveSuffix")
	if suffix == null and row["suffix"] != "":
		suffix = BattleUISkin.text(value, Vector2.ZERO, BattleUISkin.TEXT_WHITE, value.get_theme_font_size("font_size"), Vector2(0, value.size.y))
		suffix.name = "LiveSuffix"
	if suffix == null: return
	suffix.text = row["suffix"]
	suffix.position = Vector2(value.get_theme_font("font").get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x, 0)
	suffix.visible = row["suffix"] != ""


## The object's +0xa2 word: the actor template's SID (content/generated/hsl/ai/profiles.json).
static func _actor_sid(unit: Dictionary) -> int:
	if _actor_sids.is_empty():
		var actors: Dictionary = ContentPaths.read_json(ContentPaths.AI_PROFILES).get("actors", {})
		for actor_id in actors:
			_actor_sids[actor_id] = -1 if actors[actor_id].get("sid") == null else int(actors[actor_id]["sid"])
	return int(_actor_sids.get(str(unit.get("actor_id", "")), -1))

extends Control
## Original WINDOW10 and portrait artwork; numbers are always current remake state. The
## original's text block masks by three predicates (mask()): an unknown unit
## (BattlePlayLoop.unit_known false) prints ?? for the level and ??? for
## exp／HP／MP／name／state／resists; a no_attack unit prints the same except HP; a level
## above 99 prints ?? for the level alone. 稱號 and 種族 always stay readable.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V05
##     (frame_006 value x positions)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/closeup_floaters/README.md
##     (resist row: gems at (138 + 48·i, 450) in the close-up, value glyphs from x 149 + 48·i)
##   layout: resource-derived content/imported/hsl/chapter01/portraits/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_stamina.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_identity_bar.md#runtime-measured
##     (a known unit's HP bar is proportional (19/29, 10/29 frames); unknown hover frames carry the bar object)
##   strings: resource-derived content/imported/hsl/shared/panels/manifest.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_field_coverage.md
##   strings: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##   strings: runtime-measured docs/evidence_packets/static_reverse/original_identity_bar.md#runtime-measured
##     (拉爾斯帝國兵 hover frame)
##   strings: resource-derived content/imported/hsl/chapter01/source_texts/RESOURCE.TXT
const UI_ROOT := preload("res://game/sim/ContentPaths.gd").BATTLE_UI_PREVIEWS
var portrait: TextureRect
var values: Dictionary = {}
var hp_bar: TextureProgressBar
var mp_bar: TextureProgressBar
var st_bar: BattleStaminaBar
var resist_values: Array[Label] = []
var portraits: Dictionary
const UISkin = preload("res://game/common/BattleUISkin.gd")
const BattleStaminaBar = preload("res://game/battle/scene/BattleStaminaBar.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const StatusCatalog = preload("res://game/sim/StatusCatalog.gd")


## Layout of the strip in its own frame (the root sits at screen (0,14): portrait (12,14)).
## Static: 0x43ac90 docks WINDOW10 (draw origin (248,0)) at (381,14) → left edge 133;
## 0x43ace0／0x43ad30／0x43ad80 dock Bar_HP／Bar_MP／Bar_ST at screen (170,67)／(170,97)／
## (154,116) (docs/evidence_packets/static_reverse/original_growth_window.md §2).
const BOARD_AT := Vector2(133, 0)
const PORTRAIT_AT := Vector2(12, 0)
const HP_BAR_AT := Vector2(170, 53)
const MP_BAR_AT := Vector2(170, 83)
const ST_BAR_AT := Vector2(154, 102)
## Value cells: x is where the original prints each value (06_status_and_stats_screen
## frame_006, measured against the matched WINDOW10 left edge) and the cell is vertically
## centred on the baked label glyph row of WINDOW10 (resource-derived rows 12-28, 42-56,
## 73-88 on the left, 14-28, 48-62, 83-96, 116-128 on the right) — in frame_006 every value
## centre equals its label's row centre.
const VALUE_CELLS := {
	"level": [Vector2(197, 20), 17], "exp": [Vector2(279, 20), 17],
	"hp": [Vector2(231, 49), 17], "mp": [Vector2(231, 80), 17], "st": [Vector2(231, 111), 17],
	"name": [Vector2(463, 21), 16], "role": [Vector2(463, 55), 16], "race": [Vector2(463, 89), 16], "state": [Vector2(463, 122), 16],
}
const VALUE_CELL_HEIGHT := 24
## Resist row: five element gems (panels magicon1..5 = earth, water, wind, fire, mind — the
## element order of the handle table 0x4c3460 and of resist_by_type) 48 px apart, each followed
## by its value. The 2026-09-24 recording (close-up strip at y 322) puts the gems' top-left at
## screen (138 + 48·i, 450) and the white value glyphs at x 149 + 48·i, rows 457–465.
const RESIST_GEM_AT := Vector2(138, 128)
const RESIST_PITCH := 48
const RESIST_TEXT_DX := 11
const RESIST_TEXT_CENTRE_Y := 139
## 0x434d10 prints each value as two zero-padded digits and "%", or "MAX" from 80 up.
const RESIST_MAX := 80
var resist_gems: Array[TextureRect] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(640, 158)
	portraits = ContentPaths.actor_portraits()
	var original := TextureRect.new()
	original.texture = load(UI_ROOT + "WINDOW10.SHP.png")
	original.position = BOARD_AT
	original.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(original)
	portrait = TextureRect.new()
	portrait.position = PORTRAIT_AT
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(portrait)
	hp_bar = _bar("bar_hp1", "bar_hp2", HP_BAR_AT)
	mp_bar = _bar("bar_hp1", "bar_hp3", MP_BAR_AT)
	st_bar = BattleStaminaBar.new()
	st_bar.position = ST_BAR_AT
	add_child(st_bar)
	# The baked labels draw over the bars' left ends (frame_006: of the bar pixels under a
	# label glyph, 50 of 64 (MP) and 65 of 77 (ST) show the label colour).
	move_child(original, get_child_count() - 1)
	for key in VALUE_CELLS:
		var cell: Array = VALUE_CELLS[key]
		var label := Label.new()
		label.position = Vector2(cell[0].x, cell[0].y - VALUE_CELL_HEIGHT / 2.0)
		label.size = Vector2(0, VALUE_CELL_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", cell[1])
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(label)
		values[key] = label
	values["st"].hide() # Original status strip presents stamina with its segmented bar.
	for index in range(5):
		resist_gems.append(UISkin.asset(self, "magicon%d" % (index + 1), RESIST_GEM_AT + Vector2(RESIST_PITCH * index, 0)))
		var label := UISkin.label(self, Vector2(RESIST_GEM_AT.x + RESIST_TEXT_DX + RESIST_PITCH * index, RESIST_TEXT_CENTRE_Y - VALUE_CELL_HEIGHT / 2.0), 12)
		label.size = Vector2(0, VALUE_CELL_HEIGHT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		resist_values.append(label)


func _bar(back: String, fill: String, at: Vector2) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.texture_under = load(UISkin.data()["assets"][back]["res_path"])
	bar.texture_progress = load(UISkin.data()["assets"][fill]["res_path"])
	bar.position = at
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bar)
	return bar


## The original's three mask predicates for one unit's identity text (0x434d10 on
## WINDOW10／WINDOW20; 0x436490 builds the same text for the cut-in strip):
##   `hp`       — known byte clear (bVar22): HP and the ST strip print ???.
##   `identity` — known byte clear or the no_attack template bit (bVar21, 0x446b00 →
##                the unit's `no_attack`): exp／MP／name／state／resists and the status
##                page's attribute rows print ???.
##   `level`    — either predicate or template level > 99: the level prints ??.
## `known` is BattlePlayLoop.unit_known for the unit; every caller passes the same
## value so there is exactly one "known" policy.
static func mask(unit: Dictionary, known: bool) -> Dictionary:
	var unknown := not known
	var no_attack := bool(unit.get("no_attack", false))
	return {"hp": unknown, "identity": unknown or no_attack, "level": unknown or no_attack or int(unit.get("level", 0)) > 99}


func show_unit(unit: Dictionary, visible_hp: int = -1, known: bool = true) -> void:
	# A job-up member shows the target row's face where it has one (020 FACE0020), else its own.
	var visual: Dictionary = portraits[ActorSpriteKey.row_key(unit, portraits)]
	UISkin.show_shape(portrait, load(visual["res_path"]))
	# A placed object's obj_Data5 installs the unit's own 稱號 (unit `title`, live +0x1c); a
	# town job-up keeps the actor id as resource key and the title is the target row's.
	# 稱號 and 種族 stay readable on an unknown unit (0x434d10 never masks them).
	values["role"].text = str(unit.get("title", UISkin.data()["actors"][ActorSpriteKey.row_key(unit, UISkin.data()["actors"])]["title"]))
	values["race"].text = str(UISkin.data()["actors"][str(unit["actor_id"])]["race"])
	var masked := mask(unit, known)
	var hp := int(unit["hp"]) if visible_hp < 0 else visible_hp
	var mp := int(unit.get("mp", 0))
	var max_mp := int(unit.get("max_mp", mp))
	# The bar object (0x4364e0) fills from the live record +0xd8/+0xdc and +0xe0/+0xe4 and
	# never reads the known byte: the bars keep the real ratio under every mask, only the
	# text block (0x434d10) prints ???.
	hp_bar.value = 100 * clampf(float(hp) / maxf(1, float(unit["max_hp"])), 0, 1)
	mp_bar.value = 100 * clampf(float(mp) / maxf(1, float(max_mp)), 0, 1)
	if masked["hp"]:
		_show_unknown()
		return
	values["level"].text = str(int(unit["level"]))
	values["exp"].text = "%d / %d" % [int(unit.get("exp", 0)), preload("res://game/sim/ProgressionRules.gd").exp_to_next(int(unit["level"]))]
	values["hp"].text = "%d / %d" % [hp, int(unit["max_hp"])]
	values["mp"].text = "%d / %d" % [mp, max_mp]
	values["st"].text = str(int(unit.get("stamina", 0)))
	st_bar.value = clampf(float(unit.get("stamina", 0)), 0, StaminaRules.CAP)
	# 0x434d10 prints the live +0x04 name id's RESOURCE text verbatim (0x4477b0(+4)): a
	# placed object's obj_Data5 installs the unit's own (unit `display_name`), every other
	# unit shows its PLAYERS row's (UISkin actors `name`). Nameless rows (306) print 「???」
	# even when known — no remake title fill-in (lead decision 2026-09-26).
	values["name"].text = str(unit.get("display_name", UISkin.data()["actors"][ActorSpriteKey.row_key(unit, UISkin.data()["actors"])]["name"]))
	values["state"].text = state_text(int(unit.get("status_flags", 0)))
	var resist: Dictionary = unit["combat_profile"].get("resist_by_type", {})
	for index in range(5):
		resist_values[index].text = resist_text(int(resist.get(str(index), 0)))
	if masked["identity"]:
		_mask_identity()
	if masked["level"]:
		values["level"].text = "??"


## 狀態 as 0x434d10 prints it (0x435230..0x43537b): flags +0x24 == 0 → RESOURCE 124 正常;
## otherwise the one-character word of every set bit, in bit order and run together —
## 1 毒 (125), 2 封 (126), 4 痲 (127), 8 弱 (128), 0x10 攻 (129), 0x20 防 (130). Nothing else:
## no counters, no 抗 (0x40 has no word), no 戰鬥不能 for a fallen unit.
## The status words are StatusCatalog state_word; the enhancement words follow here.
const STATE_NORMAL := "正常"
const ENHANCEMENT_WORDS := [[0x10, "攻"], [0x20, "防"]]
static var STATE_WORDS: Array = _state_words()


static func _state_words() -> Array:
	var words: Array = ENHANCEMENT_WORDS.duplicate(true)
	for key in StatusCatalog.ENTRIES:
		words.append([int(StatusCatalog.ENTRIES[key]["flag"]), str(StatusCatalog.ENTRIES[key]["state_word"])])
	words.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	words.make_read_only()
	return words


static func state_text(flags: int) -> String:
	if flags == 0:
		return STATE_NORMAL
	var text := ""
	for entry in STATE_WORDS:
		if flags & int(entry[0]):
			text += str(entry[1])
	return text


## One resist value as 0x434d10 prints it (0x435616／0x43563b): "07%", "MAX" from 80.
static func resist_text(value: int) -> String:
	return "MAX" if value >= RESIST_MAX else "%02d%%" % value


## The original identity strip for a unit whose known byte is clear: 等級 ??, every other
## number and the name／state ???, resist row ??? behind each element gem; the HP／MP bars
## keep the ratio show_unit already set (0x4364e0). The ST strip is remake-invented and
## stays empty for an unknown unit.
func _show_unknown() -> void:
	_mask_identity()
	values["level"].text = "??"
	values["hp"].text = "???"
	values["st"].text = "???"
	st_bar.value = 0


## The bVar21／bVar22 rows of 0x434d10: exp／MP／name／state ??? and every resist ???;
## HP and the ST strip are outside this set (no_attack keeps them readable).
func _mask_identity() -> void:
	for key in ["exp", "mp", "name", "state"]:
		values[key].text = "???"
	for index in range(5):
		resist_values[index].text = "???"

extends Node2D
## One map float of the combat aftermath drawn with the original art: KILL N (the killer's chain
## over the fallen victim), EXP N, $ N and LEVEL UP (over the recipient). The node sits at the
## original object's spawn point; every glyph is a sprite placed by its SHP draw origin, as the
## two draw routines lay them out (reward_floats manifest `layout`). `text` names what the float
## shows ("KILL 3", "EXP 40", "$ 100", "LEVEL UP"); a learning notice (remake-invented, no
## original glyphs) is the one text float.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   layout: runtime-measured docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##     (EXP, $ and LEVEL UP centred on x 320 with the recipient centred; KILL digit 35 px clear of the word)
##   layout: remake-invented (the learning notice's text and colour)
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   strings: remake-invented (learning notice)
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const MANIFEST_PATH := "res://content/imported/hsl/shared/reward_floats/manifest.json"
## defProcShowNumber (kinds 1–6): level 16 for 16 ticks, then one level down every 2 ticks;
## deleted at level 0 (tick 46); y − 1 every other tick.
const SHOW_NUMBER_HOLD_TICKS := 16
const SHOW_NUMBER_TICKS := 46
## defProcShowContinueKillNumber: +0x90 = 40, deleted when it counts down; no rise, no fade.
const KILL_TICKS := 40
static var _manifest: Dictionary = {}
var text := ""
var kind := ""
var ticks := 0.0
var glyphs: Array[Sprite2D] = []
var caption: Label


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		assert(parsed is Dictionary and (parsed as Dictionary).get("schema") == "hsl_reward_floats.v1", "Missing reward float art")
		_manifest = parsed
	return _manifest


func _ready() -> void:
	caption = Label.new()
	caption.size = Vector2(230, 64)
	caption.position = Vector2(-115, -32)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(1.0, 0.94, 0.25))
	caption.add_theme_constant_override("outline_size", 4)
	caption.add_theme_color_override("font_outline_color", Color(0.12, 0.04, 0.17))
	add_child(caption)
	caption.hide()
	hide()


## Shows a float of `float_kind` ("kill", "experience", "gold", "level_up") for `value`, or the
## learning notice (`float_kind` "learning", `notice` its text). Restarts the float's clock.
func present(float_kind: String, value: int = 0, notice: String = "") -> void:
	kind = float_kind
	ticks = 0.0
	for glyph in glyphs:
		glyph.queue_free()
	glyphs.clear()
	caption.hide()
	var layout: Dictionary = manifest()["layout"]
	var digits := str(value)
	match float_kind:
		"experience", "gold":
			var prefix := "exp" if float_kind == "experience" else "gold"
			var show_number: Dictionary = layout["show_number"]
			var pitch := int(show_number["pitch"])
			var units := int(show_number["prefix_units"][prefix])
			var x := -((digits.length() - 1) + units) * (pitch / 2)
			_glyph(prefix, x)
			x += units * pitch
			for digit in digits:
				_glyph("%s_digit_%s" % [prefix, digit], x)
				x += pitch
			text = ("EXP %s" if float_kind == "experience" else "$ %s") % digits
		"level_up":
			_glyph("level_up", 0)
			text = "LEVEL UP"
		"kill":
			var kill: Dictionary = layout["kill"]
			var left := -(int(kill["left_per_digit"]) * digits.length() + int(kill["left_base"]))
			_glyph("kill", left)
			var x := left + int(kill["first_digit"])
			for digit in digits:
				_glyph("kill_digit_%s" % digit, x)
				x += int(kill["digit_pitch"])
			text = "KILL %s" % digits
		"learning":
			caption.text = notice
			caption.show()
			text = notice
		_:
			push_error("unknown reward float kind: " + float_kind)
			text = ""
	modulate = Color.WHITE
	show()


func _glyph(key: String, x: int) -> void:
	var record: Dictionary = manifest()["assets"][key]
	var sprite := Sprite2D.new()
	sprite.texture = load(record["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.position = Vector2(x, 0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	glyphs.append(sprite)


## Life of this float in ticks (KILL 40, the show-number kinds 46).
func life_ticks() -> int:
	return KILL_TICKS if kind == "kill" else SHOW_NUMBER_TICKS


## Advances the float's own clock; returns false once its life is over (then hidden).
func advance(delta: float) -> bool:
	ticks += maxf(0.0, OriginalTick.ticks(delta))
	if ticks >= float(life_ticks()):
		hide()
		return false
	modulate.a = 1.0 if kind == "kill" else level(ticks) / 16.0
	return true


## The draw level of a show-number float `at` ticks after it appeared (16 → 0).
static func level(at: float) -> float:
	if at < float(SHOW_NUMBER_HOLD_TICKS):
		return 16.0
	return maxf(0.0, 15.0 - floorf((at - float(SHOW_NUMBER_HOLD_TICKS)) / 2.0))


## Pixels risen `at` ticks after it appeared (y − 1 every other tick; KILL stays).
func rise(at: float = -1.0) -> float:
	if kind == "kill":
		return 0.0
	return floorf((ticks if at < 0.0 else at) / 2.0)

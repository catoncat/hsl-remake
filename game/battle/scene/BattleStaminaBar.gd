extends Control
## The identity strip's 氣力 bar, drawn as the original ST bar object process 0x4368c0 does
## (docs/evidence_packets/static_reverse/original_stamina.md#氣力条的画法): BAR_ST1 is the
## empty bar; the red BAR_ST2 fill is clipped to a width taken from the stage the value
## has reached — ST ≤ 20 fills value/20 of BAR_ST3's width (the first segment), ≤ 40 fills
## value/40 of BAR_ST4's (the first two segments), ≤ 60 fills value/60 of BAR_ST2's — and
## every completed 20-point segment is overdrawn with the stage shape (blue BAR_ST3 for one
## segment, yellow BAR_ST4 for two, BAR_ST2 when full). A segment therefore changes colour
## exactly when one more expend-1 絕技 (20 ST, SkillResourceRules.ST_PER_EXPEND) is paid for.
## The overlay is blended (0x460799 flag 0x20000000) at level +0x28 of 16, which the draw
## branch keeps pulsing 12..16: |c| + 12 with c stepping -4..4. A strip whose ST object carries
## flag 0x10000 (only 0x43b4e0 modes 2／3: the close-up strip and the hover／target strip)
## steps the shared 0x4c1ce0 once every 5 ticks (reload word 0x4782a6 = 4); every other status
## window steps the object's own +0x98 each tick (+0xa2 = 0, Bar_ST has no obj_Data6).
## The red fill is clipped at object x + width with an exclusive right edge (the default
## clip is (0,0,640,480)) while the shape starts one pixel in, so it shows width - 1 pixels.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_stamina.md
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_stamina.md
const BattleUISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
## 0x436904／0x43696a／0x4369c9: the bar's stage boundaries (cmp esi, 0x14／0x28／0x3c).
const SEGMENT_POINTS := 20
## Completed-segment overlay per stage (0x436ab2..0x436adb: ebx+2, ebx+3, ebx+1).
const LIT_SHAPES := ["bar_st3", "bar_st4", "bar_st2"]
## Clip-width reference shape per partial stage (0x436928 ebx+2, 0x436986 ebx+3, 0x4369e5 ebx+1).
const STAGE_SHAPES := ["bar_st3", "bar_st4", "bar_st2"]
## 0x436a7c／0x436a7e and 0x436ade／0x436ae0 (inc ecx; inc ebp): the fill and the overlay are
## drawn one pixel right and down of the object, where BAR_ST1 sits — which lands BAR_ST2's
## segment gaps (x 58, 122) on BAR_ST1's separators (x 59, 123).
const FILL_OFFSET := Vector2(1, 1)
## 0x436aa2..0x436aaf／0x436b9d..0x436bab: level = |c| + 12, c in -4..4 (wraps 5 → -4); the
## blitter rejects a 0x20000000 level above 16 (0x461479), so the level is in sixteenths.
const PULSE_BASE := 12
const PULSE_SPAN := 4
const BLEND_LEVELS := 16.0
## Ticks per pulse step: shared counter (0x4782a6 reload 4 → one step per 5 draws) and the
## object's own counter (reload +0xa2 = 0 → one step per draw).
const SHARED_STEP_TICKS := 5
const OWN_STEP_TICKS := 1
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")

## True for the strips 0x43b4e0 builds in mode 2／3 (flag 0x10000); status windows set false.
var shared_pulse := true
var _own_origin_msec := 0
var _drawn_level := -1

var max_value := float(StaminaRules.CAP)
var value := 0.0:
	set(next):
		value = clampf(next, 0.0, max_value)
		# The window object is rebuilt each time a page opens: its own counter starts at 0.
		_own_origin_msec = Time.get_ticks_msec()
		queue_redraw()
var _under: Texture2D
var _fill: Texture2D
## Held for the canvas: a texture referenced only by a draw command is freed after _draw and
## renders as a white rectangle.
var _lit: Array[Texture2D] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_under = BattleUISkin.texture("bar_st1")
	_fill = BattleUISkin.texture("bar_st2")
	for key in LIT_SHAPES:
		_lit.append(BattleUISkin.texture(key))
	size = _under.get_size()


## Completed 20-point segments: 0..3.
func lit_segments() -> int:
	return mini(int(value) / SEGMENT_POINTS, LIT_SHAPES.size())


## The red fill's clip width (object x to the clip's right edge); 0 when the stage overlay
## covers the whole reached bar. The visible red is one pixel narrower (_draw).
func fill_width() -> int:
	var st := int(value)
	if st <= 0 or lit_segments() == LIT_SHAPES.size():
		return 0
	var stage := mini((st - 1) / SEGMENT_POINTS, STAGE_SHAPES.size() - 1)
	var reference := int(BattleUISkin.texture(STAGE_SHAPES[stage]).get_width())
	# 16.16 fixed point as the original: ((st << 16) / (20 × (stage + 1))) × width >> 16.
	return (((st << 16) / (SEGMENT_POINTS * (stage + 1))) * reference) >> 16


## Width of the completed-segment overlay in pixels (0 when no segment is complete).
func lit_width() -> int:
	var lit := lit_segments()
	return 0 if lit == 0 else int(BattleUISkin.texture(LIT_SHAPES[lit - 1]).get_width())


## Blend level of the completed-segment overlay now (12..16 of 16).
func pulse_level() -> int:
	var tick_msec := OriginalTick.TICK_SECONDS * 1000.0
	var step: int
	if shared_pulse:
		step = int(Time.get_ticks_msec() / tick_msec) / SHARED_STEP_TICKS
	else:
		step = 1 + int((Time.get_ticks_msec() - _own_origin_msec) / tick_msec) / OWN_STEP_TICKS
	var c := posmod(step + PULSE_SPAN, 2 * PULSE_SPAN + 1) - PULSE_SPAN
	return absi(c) + PULSE_BASE


func _process(_delta: float) -> void:
	if lit_segments() > 0 and is_visible_in_tree() and pulse_level() != _drawn_level:
		queue_redraw()


func _draw() -> void:
	draw_texture(_under, Vector2.ZERO)
	# Clip right edge x + width is exclusive and the shape starts at x + 1: width - 1 pixels.
	var width := fill_width() - int(FILL_OFFSET.x)
	if width > 0:
		draw_texture_rect_region(_fill, Rect2(FILL_OFFSET, Vector2(width, _fill.get_height())), Rect2(0, 0, width, _fill.get_height()))
	var lit := lit_segments()
	if lit > 0:
		_drawn_level = pulse_level()
		draw_texture(_lit[lit - 1], FILL_OFFSET, Color(1, 1, 1, _drawn_level / BLEND_LEVELS))

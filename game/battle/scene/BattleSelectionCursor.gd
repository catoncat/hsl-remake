extends Control
## A view of the same logical cell used by hit testing; never chooses a target. Every pick
## state (move, attack／magic／special, item／give) draws the original's cell cursor 0x430230 on
## the pointer cell whether or not the cell is legal: the I_rect01..08 frames, one per 8 drawn
## ticks.
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#04
##     (cell cursor exists in recording 04; drawn square and info bar are remake)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (target selection: the I_RECT01 yellow frame on the cursor cell, user recording 178.0 s at (320,220))
##   layout: resource-derived content/imported/hsl/shared/shape_previews/battle_ui/I_RECT01.SHP.png
##   layout: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#窗与光标
##     (cursor 0x430230 in every pick state, I_rect01..08, frame word 0x4784f8)
##   layout: remake-invented (cost／budget caption bar, footprint outline)
##   strings: remake-invented (「飛行」／「可通過，不能停留」)
##   timing: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#窗与光标
## The original's cursor frame 1 (I_RECT01.SHP, 32×32, yellow ramp 238,222,0 → 139,121,0);
## I_RECT02..08 are the same outline with the corner dots at red 238／222／180／164／180／222／238.
## I_rect01..08 left to right (range_cells manifest `cursor`); a frame per 8 drawn ticks.
const CURSOR_SHEET: Texture2D = preload("res://content/imported/hsl/shared/range_cells/range_border_cursor.png")
const CURSOR_FRAME_TICKS := 8
const CURSOR_FRAMES := 8
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const TARGET_FRAME: Texture2D = preload("res://content/imported/hsl/shared/shape_previews/battle_ui/I_RECT01.SHP.png")
var cell_rect := Rect2()
## true: attack／skill／item target selection; false: move selection (same cursor, cost caption).
var target_frame := false
## Drawn ticks of the cursor so far (8 ticks a frame).
var cursor_ticks := 0
var _cursor_clock := 0.0
var footprint_rect := Rect2()
var eligible := false
var caption: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption = preload("res://game/common/BattleUISkin.gd").label(self, Vector2.ZERO, 16)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 3)
	hide()


func present(rect: Rect2, text: String, in_range: bool, body_rect: Rect2 = Rect2(), targeting: bool = false) -> void:
	cell_rect = rect
	target_frame = targeting
	footprint_rect = body_rect
	eligible = in_range
	caption.text = text
	caption.reset_size()
	var at := Vector2(rect.get_center().x - caption.size.x / 2, rect.end.y + 2)
	if at.y + caption.size.y > 476:
		at.y = rect.position.y - caption.size.y - 2
	caption.position = Vector2(clampf(at.x, 4, maxf(4, 636 - caption.size.x)), maxf(4, at.y))
	caption.visible = text != ""
	show()
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_cursor_clock += delta
		while _cursor_clock >= OriginalTick.TICK_SECONDS:
			_cursor_clock -= OriginalTick.TICK_SECONDS
			cursor_ticks += 1
		queue_redraw()


func _draw() -> void:
	if footprint_rect.has_area():
		draw_rect(footprint_rect.grow(-1), Color(1,0.8,0.32,0.92) if eligible else Color(1,0.5,0.4,0.8), false, 2)
	draw_texture_rect_region(CURSOR_SHEET, cell_rect, cursor_region(cursor_ticks))


## The sheet region of the cursor frame at drawn tick `tick` (0x4302a2: every 8th tick, mod 8).
static func cursor_region(tick: int) -> Rect2:
	return Rect2(float(posmod(tick / CURSOR_FRAME_TICKS, CURSOR_FRAMES)) * 32.0, 0.0, 32.0, 32.0)

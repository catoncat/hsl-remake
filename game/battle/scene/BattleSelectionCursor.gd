extends Control
## A view of the same logical cell used by hit testing; never chooses a target. In target
## selection (attack／magic／special) an eligible cell carries the original's yellow I_RECT01
## cell frame; move selection keeps the remake's breathing corner brackets.
## provenance:
##   rules: n/a
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#04 (cell cursor exists in recording 04; drawn square and info bar are remake); runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md (target selection: the I_RECT01 yellow frame on the cursor cell, user recording 178.0 s at (320,220)); resource-derived content/imported/hsl/shared/shape_previews/battle_ui/I_RECT01.SHP.png; remake-invented (move-selection corner brackets, cost／budget caption bar)
##   strings: remake-invented (「飛行」／「可通過，不能停留」)
##   timing: n/a
##   audio: n/a
## The original's target-cell frame (I_RECT01.SHP, 32×32, yellow ramp 238,222,0 → 139,121,0).
## I_RECT02..08 recolour the same outline; the remake draws frame 01 only (provisional).
const TARGET_FRAME: Texture2D = preload("res://content/imported/hsl/shared/shape_previews/battle_ui/I_RECT01.SHP.png")
var cell_rect := Rect2()
## true: target selection (the I_RECT01 frame); false: move selection (corner brackets).
var target_frame := false
var footprint_rect := Rect2()
var eligible := false
var caption: Label
var _elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption = preload("res://game/battle/scene/BattleUISkin.gd").label(self, Vector2.ZERO, 16)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_color", Color.WHITE)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 3)
	hide()


func present(rect: Rect2, text: String, in_range: bool, body_rect: Rect2 = Rect2(), targeting: bool = false) -> void:
	if rect != cell_rect or text != caption.text:
		_elapsed = 0.0
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
		_elapsed += delta
		queue_redraw()


func _draw() -> void:
	if footprint_rect.has_area():
		draw_rect(footprint_rect.grow(-1), Color(1,0.8,0.32,0.92) if eligible else Color(1,0.5,0.4,0.8), false, 2)
	if not eligible:
		return
	if target_frame:
		draw_texture(TARGET_FRAME, cell_rect.position)
		return
	# Breathing rate and corner length are explicit remake choices.
	var color := Color(1.0, 0.9, 0.25, 0.8 + 0.2 * sin(_elapsed * TAU))
	var rect := cell_rect.grow(-1)
	for corner in [Vector2.ZERO, Vector2(1, 0), Vector2.ONE, Vector2(0, 1)]:
		var at: Vector2 = rect.position + rect.size * corner
		var direction: Vector2 = Vector2.ONE - 2 * corner
		draw_line(at, at + Vector2(8 * direction.x, 0), color, 2)
		draw_line(at, at + Vector2(0, 8 * direction.y), color, 2)

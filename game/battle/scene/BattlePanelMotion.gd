extends Node
## Open／close motion shared by the battle panels (status, item, magic list, growth, loot).
## Attached once per panel (`attach`); it watches the panel's visibility and moves only what
## is drawn: each part (`parts_of`: the visible child Controls, a screen-wide wrapper opened one
## level) slides in from the screen edge its side belongs to — the
## top strip from above, the left column from the left, the right column from the right —
## decelerating by an eighth of the remaining distance per tick (at least 2 px), the right
## column first, the left 3 ticks later, the top 9 ticks later. On close a snapshot of the
## last frame's parts slides back out linearly at 20 px per tick while the panel itself is
## already hidden. The Controls keep their positions: the slide rewrites only the parts'
## RenderingServer draw transforms, so layout, hit testing and every input rule stay the
## panel's own (a click during the slide lands where the part is going).
## The page's black shade (`shades_of`) fades with it: in from level 2 to
## BattleUISkin.PANEL_SHADE_LEVEL (9 of 16) one level per 3 ticks; on close a shade left in
## the panel's place steps back down 9→2 one level per 3 ticks and then vanishes (24 ticks),
## renderer or not.
## provenance:
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (status page: right window enters from the right, left from the left, top strip from above; leaves alike)
##   layout: remake-invented
##     (the side of a part is read from its rect: centre above y 170 → top, centre left of x 246 → left, else right;
##     bottom boxes slide with their side instead of appearing last)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (open ≈0.62 s at remaining×7/8 per frame, left +0.05 s, top +0.17 s; close ≈0.23 s; shade 8 luma steps)
##   timing: provisional (the per-tick formula is a fit of the frames, the EXE helper is unread)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const VIEW := Vector2(640, 480)
const TOP_LIMIT_Y := 170.0
const LEFT_LIMIT_X := 246.0
const OPEN_DELAY_TICKS := {"right": 0, "left": 3, "top": 9}
const OPEN_MIN_STEP := 2.0
const CLOSE_STEP := 20.0
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const SHADE_TICKS_PER_LEVEL := 3
const SHADE_FIRST_LEVEL := 2

var panel: Control
## [{item: CanvasItem, side: String, offset: Vector2, delay: int}]
var _parts: Array = []
var _clock := 0.0
var _ghost: Control
var _ghost_parts: Array = []
var opened_count := 0
var closed_count := 0
## Close snapshots actually drawn (0 without a renderer, e.g. headless tests).
var ghost_count := 0
## Shade fade: current level in 16ths, +1 fading in, −1 fading out, 0 still.
var shade_level := 0
var _shade_direction := 0
var _shade_wait := 0
var _shades: Array[ColorRect] = []
var _shade_ghost: ColorRect


static func attach(target: Control) -> Node:
	for child in target.get_children():
		if child.get_script() == preload("res://game/battle/scene/BattlePanelMotion.gd"):
			return child
	var motion := new()
	motion.name = "PanelMotion"
	motion.panel = target
	target.add_child(motion)
	target.visibility_changed.connect(motion._on_visibility_changed)
	return motion


func opening() -> bool:
	return not _parts.is_empty()


func closing() -> bool:
	return _ghost != null


func shading() -> bool:
	return _shade_direction != 0


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	_free_ghost()
	_free_shade_ghost()


static func side_of(rect: Rect2) -> String:
	var centre := rect.get_center()
	if centre.y < TOP_LIMIT_Y and rect.size.x > VIEW.x * 0.5:
		return "top"
	return "left" if centre.x < LEFT_LIMIT_X else "right"


## Offset that puts `rect` just off the screen on `side`.
static func off_screen_offset(rect: Rect2, side: String) -> Vector2:
	match side:
		"top":
			return Vector2(0, -rect.end.y)
		"left":
			return Vector2(-rect.end.x, 0)
		_:
			return Vector2(VIEW.x - rect.position.x, 0)


## One opening tick of an offset: an eighth of the rest, at least OPEN_MIN_STEP px.
static func open_step(offset: Vector2) -> Vector2:
	var length := offset.length()
	if length <= OPEN_MIN_STEP:
		return Vector2.ZERO
	var step := maxf(floorf(length / 8.0), OPEN_MIN_STEP)
	return offset - offset / length * step


## The panel's drawn parts: its visible Control children, a child that covers most of the
## screen replaced by its own visible Control children (a bare backdrop contributes none and
## neither slides nor joins the close snapshot).
func parts_of(root: Control) -> Array[Control]:
	var parts: Array[Control] = []
	for child in root.get_children():
		if not (child is Control) or not (child as Control).visible:
			continue
		var rect := (child as Control).get_global_rect()
		if rect.size == Vector2.ZERO:
			continue
		if _screen_wide(rect):
			# A screen-wide backdrop (the page's shade) stays put; a wrapper opens one level.
			for inner in child.get_children():
				if inner is Control and (inner as Control).visible and (inner as Control).get_global_rect().size != Vector2.ZERO and not _screen_wide((inner as Control).get_global_rect()):
					parts.append(inner)
		else:
			parts.append(child)
	return parts


## The page's visible screen-wide ColorRects (BattleUISkin.clear_panel), a screen-wide
## wrapper opened one level like `parts_of`.
func shades_of(root: Control) -> Array[ColorRect]:
	var shades: Array[ColorRect] = []
	for child in root.get_children():
		if not (child is Control) or not (child as Control).visible or not _screen_wide((child as Control).get_global_rect()):
			continue
		if child is ColorRect:
			shades.append(child)
			continue
		for inner in child.get_children():
			if inner is ColorRect and (inner as ColorRect).visible and _screen_wide((inner as ColorRect).get_global_rect()):
				shades.append(inner)
	return shades


## One fade step of the shade level: up to PANEL_SHADE_LEVEL, down to SHADE_FIRST_LEVEL and
## then straight to 0.
static func shade_step(level: int, direction: int) -> int:
	var next := level + direction
	if direction < 0 and next < SHADE_FIRST_LEVEL:
		return 0
	return clampi(next, 0, BattleUISkin.PANEL_SHADE_LEVEL)


static func _screen_wide(rect: Rect2) -> bool:
	return rect.get_area() > VIEW.x * VIEW.y * 0.6


func _screen_rect(item: CanvasItem) -> Rect2:
	if item is Control:
		return (item as Control).get_global_rect()
	return Rect2()


func _on_visibility_changed() -> void:
	if panel == null:
		return
	if panel.visible:
		_begin_open()
	else:
		_begin_close()


func _begin_open() -> void:
	_restore_parts()
	_free_ghost()
	_parts.clear()
	_begin_shade_in()
	for child in parts_of(panel):
		var rect := _screen_rect(child)
		var side := side_of(rect)
		_parts.append({"item": child, "side": side, "offset": off_screen_offset(rect, side), "delay": int(OPEN_DELAY_TICKS[side])})
	if _parts.is_empty():
		return
	opened_count += 1
	_clock = 0.0
	_apply_parts()
	set_process(true)


func _begin_shade_in() -> void:
	_free_shade_ghost()
	_shades = shades_of(panel)
	if _shades.is_empty():
		shade_level = 0
		_shade_direction = 0
		return
	shade_level = maxi(shade_level, SHADE_FIRST_LEVEL)
	_shade_direction = 1 if shade_level < BattleUISkin.PANEL_SHADE_LEVEL else 0
	_shade_wait = SHADE_TICKS_PER_LEVEL
	_apply_shade()
	if shading():
		_clock = 0.0
		set_process(true)


func _begin_shade_out() -> void:
	_free_shade_ghost()
	var had_shade := not _shades.is_empty()
	_shades.clear()
	if not had_shade or shade_level <= 0 or panel.get_parent() == null:
		shade_level = 0
		_shade_direction = 0
		return
	_shade_ghost = ColorRect.new()
	_shade_ghost.name = "PanelShadeFade"
	_shade_ghost.size = VIEW
	_shade_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := panel.get_parent()
	parent.add_child(_shade_ghost)
	parent.move_child(_shade_ghost, panel.get_index())
	_shade_direction = -1
	_shade_wait = SHADE_TICKS_PER_LEVEL
	_apply_shade()
	_clock = 0.0
	set_process(true)


func _begin_close() -> void:
	var was_opening := opening()
	_restore_parts()
	_parts.clear()
	closed_count += 1
	_begin_shade_out()
	if was_opening or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var scale := Vector2(image.get_size()) / VIEW
	_free_ghost()
	_ghost = Control.new()
	_ghost.name = "PanelCloseGhost"
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost_parts.clear()
	for child in parts_of(panel):
		var rect := _screen_rect(child).intersection(Rect2(Vector2.ZERO, VIEW))
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue
		var region := Rect2i(Vector2i((rect.position * scale).floor()), Vector2i((rect.size * scale).ceil()))
		region = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if region.size.x <= 0 or region.size.y <= 0:
			continue
		var piece := TextureRect.new()
		piece.texture = ImageTexture.create_from_image(image.get_region(region))
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.position = rect.position
		piece.size = rect.size
		_ghost.add_child(piece)
		var side := side_of(rect)
		_ghost_parts.append({"item": piece, "side": side, "limit": off_screen_offset(rect, side)})
	if _ghost_parts.is_empty():
		_free_ghost()
		return
	ghost_count += 1
	panel.get_parent().add_child(_ghost)
	_clock = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	while _clock >= OriginalTick.TICK_SECONDS:
		_clock -= OriginalTick.TICK_SECONDS
		_tick()
	if not opening() and not closing() and not shading():
		set_process(false)


func _tick() -> void:
	if opening():
		var moving := false
		for part in _parts:
			if int(part["delay"]) > 0:
				part["delay"] = int(part["delay"]) - 1
				moving = true
				continue
			part["offset"] = open_step(part["offset"])
			moving = moving or part["offset"] != Vector2.ZERO
		_apply_parts()
		if not moving:
			_restore_parts()
			_parts.clear()
	if closing():
		var done := true
		for part in _ghost_parts:
			var piece: TextureRect = part["item"]
			var limit: Vector2 = part["limit"]
			var travelled: Vector2 = piece.get_meta("travelled", Vector2.ZERO)
			var next := travelled.move_toward(limit, CLOSE_STEP)
			piece.position += next - travelled
			piece.set_meta("travelled", next)
			done = done and next == limit
		if done:
			_free_ghost()
	if shading():
		_shade_wait -= 1
		if _shade_wait <= 0:
			_shade_wait = SHADE_TICKS_PER_LEVEL
			shade_level = shade_step(shade_level, _shade_direction)
			_apply_shade()
			if shade_level <= 0 or shade_level >= BattleUISkin.PANEL_SHADE_LEVEL:
				_shade_direction = 0
				if shade_level <= 0:
					_free_shade_ghost()


func _apply_shade() -> void:
	var colour := Color(0, 0, 0, shade_level / BattleUISkin.SHADE_LEVEL_SCALE)
	for shade in _shades:
		if is_instance_valid(shade):
			shade.color = colour
	if _shade_ghost != null and is_instance_valid(_shade_ghost):
		_shade_ghost.color = colour


func _free_shade_ghost() -> void:
	if _shade_ghost != null:
		if is_instance_valid(_shade_ghost):
			_shade_ghost.queue_free()
		_shade_ghost = null


func _apply_parts() -> void:
	for part in _parts:
		var item: CanvasItem = part["item"]
		if is_instance_valid(item):
			var xform := item.get_transform()
			xform.origin += part["offset"]
			RenderingServer.canvas_item_set_transform(item.get_canvas_item(), xform)


func _restore_parts() -> void:
	for part in _parts:
		var item: CanvasItem = part["item"]
		if is_instance_valid(item):
			RenderingServer.canvas_item_set_transform(item.get_canvas_item(), item.get_transform())


func _free_ghost() -> void:
	if _ghost != null:
		if is_instance_valid(_ghost):
			_ghost.queue_free()
		_ghost = null
	_ghost_parts.clear()


## Explicit fast-forward (tests, restore): ends both motions and the shade fade at once.
## A panel that stays up while its page gives way to a map pick (the item panel's use target):
## the page leaves as on close (`slide_out`) and comes back as on open (`slide_in`).
func slide_out() -> void:
	_begin_close()


func slide_in() -> void:
	_begin_open()


func finish() -> void:
	_restore_parts()
	_parts.clear()
	_free_ghost()
	_free_shade_ghost()
	_shade_direction = 0
	shade_level = BattleUISkin.PANEL_SHADE_LEVEL if panel != null and panel.visible and not _shades.is_empty() else 0
	_apply_shade()
	set_process(false)

extends Node
## Open／close motion shared by the battle panels (status, item, magic list, growth, loot).
## Attached once per panel (`attach`); it watches the panel's visibility and moves only what
## is drawn (`parts_of`: the visible child Controls, a screen-wide wrapper opened one level).
## As the original's battle window objects (builders 0x43ac10..0x43b3a0 under 0x43b4e0): each
## sub-window starts SLIDE_DISTANCE (380) px off its landing point on one axis — the top strip
## (templates 130／131 and the 145／146／147 bars) from above, WINDOW20 from the left, WINDOW30／
## 31／50／90 from the right, the `$:` WINDOW40 and every button (y 387 from y 767) from below,
## the growth window's WINDOW41 and BT_OK from the left; every part starts together and steps
## each tick by 0x45e882(cur, target, 40) (`slide_in_step`: within 1 px lands, else min(40,
## distance >> 3), at least 2 — 380 px in 33 ticks). On close a snapshot of the last frame's
## parts slides back to the start points by 0x45e80d(cur, start, 4, 20) on the one moving axis
## (`slide_out_step`: half the rest, at most 20, lands within 4) while the panel itself is
## already hidden. The Controls keep their positions: the slide rewrites only the parts'
## RenderingServer draw transforms, so layout, hit testing and every input rule stay the
## panel's own (a click during the slide lands where the part is going).
## The page's black shade (`shades_of`) is the root window's full-screen black shape
## (0x4385d3..0x43862c): level +0xae from 0, one level per 3 ticks (+0x84／+0x86 = 3, 0x43828d)
## up to BattleUISkin.PANEL_SHADE_LEVEL (8 of 16, drawn half-blended, 0x40000000) while the
## window slides in and stays; on close it steps back down one level per 3 ticks while the
## window slides out and vanishes with it (0x43898f, 0x4389ce), renderer or not.
## provenance:
##   layout: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (battle window builders 0x43ac10..0x43b3a0: start points 380 px off the landing point, side per template)
##   layout: remake-invented
##     (a part that is no board, button, caption or vitals strip follows the board under its centre, else its
##     rect: centre above y 170 → top, left of x 246 → left, else right)
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (0x45e882 speed 40 in, 0x45e80d tolerance 4 step 20 out, all parts at once; shade 0→8 one level per 3 ticks)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const VIEW := Vector2(640, 480)
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const TOP_LIMIT_Y := 170.0
const LEFT_LIMIT_X := 246.0
## Battle window start offset (0x43ac90: y 14 from −366), 0x45e882 speed, 0x45e80d tolerance and step.
const SLIDE_DISTANCE := 380
const SLIDE_IN_SPEED := 40
const SLIDE_OUT_TOLERANCE := 4
const SLIDE_OUT_STEP := 20
const SIDE_DIRECTIONS := {"top": Vector2.UP, "bottom": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const SHADE_TICKS_PER_LEVEL := 3

var panel: Control
## [{item: CanvasItem, side: String, direction: Vector2}]
var _parts: Array = []
## Distance still to go on the open slide; every part shares it (all start 400 px out).
var slide_remaining := 0
var _clock := 0.0
var _ghost: Control
var _ghost_parts: Array = []
var _ghost_travelled := 0
var opened_count := 0
var closed_count := 0
## Close snapshots actually drawn (0 without a renderer, e.g. headless tests).
var ghost_count := 0
## Shade fade: current level in 16ths, +1 fading in, −1 fading out, 0 still.
var shade_level := 0
var _shade_direction := 0
var _shade_wait := 0
## Close: ticks until the root window is deleted and its shade with it.
var _shade_life := 0
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


## The side a part starts on: the vitals strip from above, a button (Button_／Page_) and its
## caption (Caption_) from below, a WINDOW board by its template (see the header), "" for any
## other part (`sides_of` then gives it its board's side).
static func part_side(part: Control) -> String:
	if part.get_script() == BattleVitals:
		return "top"
	var key := str(part.name)
	if key.begins_with("Button_") or key.begins_with("Page_") or key.begins_with("Caption_"):
		return "bottom"
	return board_side(part)


## The side of a WINDOW board (TextureRect of a WINDOW shape), "" for anything else.
static func board_side(part: Control) -> String:
	if not (part is TextureRect) or (part as TextureRect).texture == null:
		return ""
	var template := (part as TextureRect).texture.resource_path.get_file().get_basename().get_basename()
	if not template.begins_with("WINDOW") or template.length() < 7:
		return ""
	if template == "WINDOW40":
		return "bottom"
	match template[6]:
		"1": return "top"
		"2", "4": return "left"
		"3", "5", "9": return "right"
	return ""


## The side of every part: its own (`part_side`), else the side of the smallest board its
## centre lies on, else `side_of` its rect.
static func sides_of(parts: Array) -> Array[String]:
	var sides: Array[String] = []
	var boards: Array = []
	for part in parts:
		var side := part_side(part)
		sides.append(side)
		if side != "" and board_side(part) != "":
			boards.append({"rect": (part as Control).get_global_rect(), "side": side})
	for index in parts.size():
		if sides[index] != "":
			continue
		var rect: Rect2 = (parts[index] as Control).get_global_rect()
		var best := ""
		var best_area := INF
		for board in boards:
			if (board["rect"] as Rect2).has_point(rect.get_center()) and (board["rect"] as Rect2).get_area() < best_area:
				best = board["side"]
				best_area = (board["rect"] as Rect2).get_area()
		sides[index] = best if best != "" else side_of(rect)
	return sides


## 0x45e882(cur, target, 40) on the distance still to go: within 1 px lands; else step
## min(40, distance >> 3), at least 2.
static func slide_in_step(remaining: int) -> int:
	if remaining <= 1:
		return 0
	return maxi(remaining - maxi(mini(SLIDE_IN_SPEED, remaining >> 3), 2), 0)


## 0x45e80d(cur, start, 4, 20) on the one moving axis, as distance travelled back to the start
## point: within 4 lands; else half the rest, at most 20.
static func slide_out_step(travelled: int) -> int:
	var rest := SLIDE_DISTANCE - travelled
	if rest <= SLIDE_OUT_TOLERANCE:
		return SLIDE_DISTANCE
	return travelled + mini(rest >> 1, SLIDE_OUT_STEP)


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


## One fade step of the shade level (0x4388d9／0x43898f): up to PANEL_SHADE_LEVEL, down to 0.
static func shade_step(level: int, direction: int) -> int:
	return clampi(level + direction, 0, BattleUISkin.PANEL_SHADE_LEVEL)


## Ticks the close slide takes: 0x45e80d steps until landed, then the delete tick (0x4389ce).
static func slide_out_ticks() -> int:
	var travelled := 0
	var ticks := 0
	while travelled < SLIDE_DISTANCE:
		travelled = slide_out_step(travelled)
		ticks += 1
	return ticks + 1


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
	var parts := parts_of(panel)
	var sides := sides_of(parts)
	for index in parts.size():
		_parts.append({"item": parts[index], "side": sides[index], "direction": SIDE_DIRECTIONS[sides[index]]})
	if _parts.is_empty():
		return
	opened_count += 1
	slide_remaining = SLIDE_DISTANCE
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
	# A fresh root window starts at level 0 with its counter at 3 (0x43828d).
	shade_level = 0
	_shade_direction = 1
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
	# The counter carries on from the opening (0x4389a6 shares +0x84 with 0x4388e6).
	_shade_direction = -1
	_shade_life = slide_out_ticks()
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
	var parts := parts_of(panel)
	var sides := sides_of(parts)
	for index in parts.size():
		var child: Control = parts[index]
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
		_ghost_parts.append({"item": piece, "from": rect.position, "direction": SIDE_DIRECTIONS[sides[index]]})
	if _ghost_parts.is_empty():
		_free_ghost()
		return
	ghost_count += 1
	_ghost_travelled = 0
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
		slide_remaining = slide_in_step(slide_remaining)
		_apply_parts()
		if slide_remaining <= 0:
			_restore_parts()
			_parts.clear()
	if closing():
		_ghost_travelled = slide_out_step(_ghost_travelled)
		for part in _ghost_parts:
			if is_instance_valid(part["item"]):
				(part["item"] as TextureRect).position = part["from"] + part["direction"] * float(_ghost_travelled)
		if _ghost_travelled >= SLIDE_DISTANCE:
			_free_ghost()
	if shading():
		var stepping := shade_level > 0 if _shade_direction < 0 else shade_level < BattleUISkin.PANEL_SHADE_LEVEL
		if stepping:
			_shade_wait -= 1
			if _shade_wait <= 0:
				_shade_wait = SHADE_TICKS_PER_LEVEL
				shade_level = shade_step(shade_level, _shade_direction)
				_apply_shade()
		if _shade_direction > 0 and shade_level >= BattleUISkin.PANEL_SHADE_LEVEL:
			_shade_direction = 0
		elif _shade_direction < 0:
			_shade_life -= 1
			if _shade_life <= 0:
				shade_level = 0
				_shade_direction = 0
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
		# A page rebuilt mid-motion frees its parts; a typed read of a freed part errors.
		var item: Variant = part["item"]
		if is_instance_valid(item):
			var xform: Transform2D = item.get_transform()
			xform.origin += part["direction"] * float(slide_remaining)
			RenderingServer.canvas_item_set_transform(item.get_canvas_item(), xform)


func _restore_parts() -> void:
	slide_remaining = 0
	for part in _parts:
		# A page rebuilt mid-motion frees its parts; a typed read of a freed part errors.
		var item: Variant = part["item"]
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

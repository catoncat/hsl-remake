extends Node
## Open／close motion shared by the battle panels (status, item, magic list, growth, loot).
## Attached once per panel (`attach`); it watches the panel's visibility and moves only what
## is drawn (`parts_of`: the visible child Controls, a screen-wide wrapper opened one level).
## As the original's battle window objects (builders 0x43ac10..0x43b3a0 under 0x43b4e0): each
## sub-window starts SLIDE_DISTANCE (380) px off its landing point on one axis — the top strip
## (templates 130／131 and the 145／146／147 bars) from above, WINDOW20 from the left, WINDOW30／
## 31／50／90 from the right, the `$:` WINDOW40 and every button (y 387 from y 767) from below,
## the growth window's WINDOW41, BT_OK and the eight BT_ADD＋／－ (0x43bd3e: x 37·col − 221 to
## 37·col + 159) from the left; every part starts together and steps
## each tick by 0x45e882(cur, target, 40) (`slide_in_step`: within 1 px lands, else min(40,
## distance >> 3), at least 2 — 380 px in 33 ticks). On close a snapshot of the last frame's
## parts slides back to the start points by 0x45e80d(cur, start, 4, 20) on the one moving axis
## (`slide_out_step`: half the rest, at most 20, lands within 4) while the panel itself is
## already hidden. The Controls keep their positions: the slide rewrites only the parts'
## RenderingServer draw transforms, so layout, hit testing and every input rule stay the
## panel's own (a click during the slide lands where the part is going). A Control's redraw
## (NOTIFICATION_DRAW) sets its draw transform back to its own place: a part shown, relabelled or
## resized mid slide — every part in the frame a page opens from the scene's process, e.g. the
## settlement's 獲得物品 window and the growth window — takes its offset back in that same redraw
## (`draw` signal), so no frame draws it on its landing point before the slide gets there.
## A hover description box (BattleUISkin.in_place: 0x436d70 draws WINDOW50 at camera + (252,349),
## no window object) never slides and is left out of the close snapshot (the snapshot is drawn
## again without any in-place box when one shows: the root-window list boxes stop drawing in
## state 2); a held one (root-window list branches, drawn only at +0x8c == 1) stays undrawn while
## the open slide runs and shows in place when it lands — one a page rebuilt mid-slide brings in
## too (rescanned every tick) —, an unheld one (the 獲得物品 pending list, 0x4150ab in every
## state) shows in place mid-slide and on close. That list hit-tests its current rect in every
## state (0x415601, 0x4304ac): a panel with `drawn_hover` is told each tick where its parts are
## drawn (`drawn_offset`: the open slide's offset, then the close snapshot piece's), and on close
## gets a copy of its in-place box above the pieces to describe the row under the pointer.
## A page that rebuilds while it shows (the 獲得物品 window on a pick-up, a claim or a new
## recipient: the original refreshes the one window object's rows, 0x414c00 state carried on)
## calls `rescan`: its new parts join the open slide at the distance still to go and its new
## shade takes the current level. A held item drawn at the cursor is never a part.
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
const OriginalSlide = preload("res://game/common/OriginalSlide.gd")
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
## GameCursor.HELD_GROUP: the item a page draws at the cursor (the cursor process draws it at the mouse, 0x4304d5 → 0x430310, with no window offset).
const HELD_GROUP := "game_cursor_held_items"

var panel: Control
## [{item: CanvasItem, side: String, direction: Vector2}]
var _parts: Array = []
## Distance still to go on the open slide; every part shares it (all start 400 px out).
var slide_remaining := 0
var _clock := 0.0
var _ghost: Control
var _ghost_parts: Array = []
var _ghost_travelled := 0
## The close snapshot's copy of the panel's in-place box (a `drawn_hover` panel only).
var _ghost_box: Control
var opened_count := 0
var closed_count := 0
## Close snapshots actually drawn (0 without a renderer, e.g. headless tests).
var ghost_count := 0
## Part redraws mid open slide that took the slide offset back (see the header).
var redrawn_count := 0
## Shade fade: current level in 16ths, +1 fading in, −1 fading out, 0 still.
var shade_level := 0
var _shade_direction := 0
var _shade_wait := 0
## Close: ticks until the root window is deleted and its shade with it.
var _shade_life := 0
var _shades: Array[ColorRect] = []
var _shade_ghost: ColorRect
## In-place boxes met during the open slide (rescanned every tick); the held ones stay undrawn
## while it runs and all are restored when it lands.
var _held: Array = []


## An internal child: a page that clears its children to rebuild (BattleLootPanel.show_rewards)
## keeps it.
static func attach(target: Control) -> Node:
	for child in target.get_children(true):
		if child.get_script() == preload("res://game/battle/scene/BattlePanelMotion.gd"):
			return child
	var motion := new()
	motion.name = "PanelMotion"
	motion.panel = target
	target.add_child(motion, false, Node.INTERNAL_MODE_BACK)
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
	if part is TextureButton and (part as TextureButton).texture_normal != null:
		var shape := (part as TextureButton).texture_normal.resource_path.get_file()
		if shape.begins_with("BT_ADD") or shape.begins_with("BT_OK"):
			return "left"
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
	return OriginalSlide.approach(remaining, SLIDE_IN_SPEED)


## 0x45e80d(cur, start, 4, 20) on the one moving axis, as distance travelled back to the start
## point: within 4 lands; else half the rest, at most 20.
static func slide_out_step(travelled: int) -> int:
	return OriginalSlide.retreat(travelled, SLIDE_DISTANCE, SLIDE_OUT_TOLERANCE, SLIDE_OUT_STEP)


## The panel's drawn parts: its visible Control children, a child that covers most of the
## screen replaced by its own visible Control children (a bare backdrop contributes none and
## neither slides nor joins the close snapshot); an in-place box or a held item is never a part.
func parts_of(root: Control) -> Array[Control]:
	var parts: Array[Control] = []
	for child in root.get_children():
		if not (child is Control) or not (child as Control).visible or child.has_meta(BattleUISkin.IN_PLACE_META) or child.is_in_group(HELD_GROUP):
			continue
		var rect := (child as Control).get_global_rect()
		if rect.size == Vector2.ZERO:
			continue
		if _screen_wide(rect):
			# A screen-wide backdrop (the page's shade) stays put; a wrapper opens one level.
			for inner in child.get_children():
				if inner is Control and (inner as Control).visible and not inner.has_meta(BattleUISkin.IN_PLACE_META) and not inner.is_in_group(HELD_GROUP) and (inner as Control).get_global_rect().size != Vector2.ZERO and not _screen_wide((inner as Control).get_global_rect()):
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
	_register_parts()
	if _parts.is_empty():
		_drawn_hover(false)
		return
	opened_count += 1
	slide_remaining = SLIDE_DISTANCE
	_clock = 0.0
	_drawn_hover(true)
	_apply_parts()
	set_process(true)


## The page rebuilt its parts while it shows: mid open slide the parts drawn now are the slide's
## parts at the distance still to go (a freed part drops out, a new one joins where the others
## are); the shade drawn now takes the current level (a fresh ColorRect starts at the full 8).
func rescan() -> void:
	if panel == null or not panel.visible:
		return
	if opening():
		var remaining := slide_remaining
		_restore_parts()
		_parts.clear()
		_register_parts()
		if _parts.is_empty():
			_drawn_hover(false)
		else:
			slide_remaining = remaining
			_apply_parts()
	if not _shades.is_empty():
		_shades = shades_of(panel)
		_apply_shade()


func _register_parts() -> void:
	var parts := parts_of(panel)
	var sides := sides_of(parts)
	for index in parts.size():
		var direction: Vector2 = SIDE_DIRECTIONS[sides[index]]
		var redraw := _on_part_drawn.bind(parts[index], direction)
		parts[index].draw.connect(redraw)
		_parts.append({"item": parts[index], "side": sides[index], "direction": direction, "redraw": redraw})


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
	if not was_opening and DisplayServer.get_name() != "headless" and is_inside_tree():
		_cut_ghost()
	_drawn_hover(closing())


## The close snapshot cut into one piece per part (`_ghost_parts`, each with the part it came
## from), sliding from where the part was.
func _cut_ghost() -> void:
	var image := _snapshot()
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
		_ghost_parts.append({"item": piece, "source": child, "from": rect.position, "direction": SIDE_DIRECTIONS[sides[index]]})
	if _ghost_parts.is_empty():
		_free_ghost()
		return
	var boxes := _in_place_boxes()
	if panel.has_method("drawn_hover") and not boxes.is_empty() and boxes[0] is Control:
		_ghost_box = (boxes[0] as Control).duplicate()
		_ghost_box.position = (boxes[0] as Control).get_global_rect().position
		_ghost_box.hide()
		_ghost.add_child(_ghost_box)
	ghost_count += 1
	_ghost_travelled = 0
	panel.get_parent().add_child(_ghost)
	_clock = 0.0
	set_process(true)


## The in-place boxes under the panel.
func _in_place_boxes() -> Array:
	return panel.find_children("*", "CanvasItem", true, false).filter(func(node): return node.has_meta(BattleUISkin.IN_PLACE_META))


## The last frame for the close snapshot. The original stops drawing every in-place box in
## state 2 (the root window's list branches need +0x8c == 1), so when one is up the frame is
## drawn once more, unpresented, with the panel as it was and no in-place box. The page's own
## shade stays in that frame, as in the presented one, so the parts' see-through cells (a
## caption's cell under its button, text off the boards) carry the dimmed field; the shade fade
## just put in its place is left out of it (it would dim the frame twice). RenderingServer
## visibility only: no node visibility changes, so no signal or input rule sees it.
func _snapshot() -> Image:
	var boxes := _in_place_boxes().filter(_shown_in_panel)
	if boxes.is_empty():
		return get_viewport().get_texture().get_image()
	if _shade_ghost != null and is_instance_valid(_shade_ghost):
		boxes.append(_shade_ghost)
	RenderingServer.canvas_item_set_visible(panel.get_canvas_item(), true)
	for item in boxes:
		RenderingServer.canvas_item_set_visible(item.get_canvas_item(), false)
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	for item in boxes:
		RenderingServer.canvas_item_set_visible(item.get_canvas_item(), item.visible)
	RenderingServer.canvas_item_set_visible(panel.get_canvas_item(), panel.visible)
	return image


## Visible up to the panel (the panel itself may already be hidden).
func _shown_in_panel(item: CanvasItem) -> bool:
	var node: Node = item
	while node != null and node != panel:
		if node is CanvasItem and not (node as CanvasItem).visible:
			return false
		node = node.get_parent()
	return node == panel


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
		# Before the parts are drawn, so a box the hover shows is drawn this tick.
		_drawn_hover(slide_remaining > 0)
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
		_drawn_hover(closing())
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
		_offset_part(part["item"], part["direction"])
	for item in _in_place_boxes():
		if not _held.has(item):
			_held.append(item)
	for item in _held:
		if is_instance_valid(item):
			var held := bool(item.get_meta(BattleUISkin.IN_PLACE_META, true))
			RenderingServer.canvas_item_set_modulate(item.get_canvas_item(), Color(item.modulate, 0.0) if held else item.modulate)


## A part drawn `slide_remaining` px off its place towards `direction`.
func _offset_part(item: Variant, direction: Vector2) -> void:
	# A page rebuilt mid-motion frees its parts; a typed read of a freed part errors.
	if is_instance_valid(item):
		var xform: Transform2D = item.get_transform()
		xform.origin += direction * float(slide_remaining)
		RenderingServer.canvas_item_set_transform(item.get_canvas_item(), xform)


## A part redrawn mid open slide: its draw just put it back on its own place.
func _on_part_drawn(item: Control, direction: Vector2) -> void:
	if slide_remaining > 0:
		redrawn_count += 1
		_offset_part(item, direction)


func _restore_parts() -> void:
	slide_remaining = 0
	for part in _parts:
		# A page rebuilt mid-motion frees its parts; a typed read of a freed part errors.
		var item: Variant = part["item"]
		if is_instance_valid(item):
			if item.draw.is_connected(part["redraw"]):
				item.draw.disconnect(part["redraw"])
			RenderingServer.canvas_item_set_transform(item.get_canvas_item(), item.get_transform())
	for item in _held:
		if is_instance_valid(item):
			RenderingServer.canvas_item_set_modulate(item.get_canvas_item(), item.modulate)
	_held.clear()


func _free_ghost() -> void:
	if _ghost != null:
		if is_instance_valid(_ghost):
			_ghost.queue_free()
		_ghost = null
	_ghost_parts.clear()
	_ghost_box = null


## Where a panel Control is drawn right now, off its own place: its open-slide offset (a Control
## that is no part is drawn in place), during the close slide the offset of the snapshot piece
## cut from it (null: in no piece, not drawn).
func drawn_offset(item: CanvasItem) -> Variant:
	if closing():
		for part in _ghost_parts:
			if is_instance_valid(part["source"]) and part["source"] == item:
				return part["direction"] * float(_ghost_travelled)
		return null
	for part in _parts:
		if is_instance_valid(part["item"]) and part["item"] == item:
			return part["direction"] * float(slide_remaining)
	return Vector2.ZERO


## Tells a panel that hit-tests where its parts are drawn (`drawn_hover`) that they are drawn off
## their Controls (`drawn`, every tick of either slide), or back on them.
func _drawn_hover(drawn: bool) -> void:
	if panel != null and panel.has_method("drawn_hover"):
		panel.drawn_hover(drawn_offset, _ghost_box if closing() else null, drawn)


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
	_drawn_hover(false)
	_free_shade_ghost()
	_shade_direction = 0
	shade_level = BattleUISkin.PANEL_SHADE_LEVEL if panel != null and panel.visible and not _shades.is_empty() else 0
	_apply_shade()
	set_process(false)

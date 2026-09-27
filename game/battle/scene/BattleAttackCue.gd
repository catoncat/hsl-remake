extends Node2D
## Visual-only lead-in. The immutable settled exchange remains in PlayLoop.
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#08
##     (range cells and target square exist in recording 08／12)
##   layout: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md
##     (caption font [0x4c1ae0] = FONT.24 body face)
##   layout: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   layout: resource-derived content/imported/hsl/shared/range_cells/manifest.json
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (the AI lead-in cursor is the yellow I_RECT01 cell frame)
##   strings: resource-derived content/imported/hsl/global/tables/MAGIC.TXT
##   strings: resource-derived content/imported/hsl/global/tables/SPECIAL.TXT
##   timing: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const CombatPresentationTiming = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
## OPT-PACE (docs/OPTIONS.md), read once per begin: the multiplier on advance (PACE_MAP).
var pace := 1.0
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const RangeCellOverlay = preload("res://game/battle/runtime/RangeCellOverlay.gd")
## The yellow cell frame drawn on the cursor cell (BattleSelectionCursor.TARGET_FRAME).
const TARGET_FRAME: Texture2D = preload("res://game/battle/scene/BattleSelectionCursor.gd").TARGET_FRAME

## AI normal attack (0x440b2c states 7–9): the setup tick loads [unit+0x94]=6 (0x441372);
## state 8 (0x44139d) draws the range with the cursor on the attacker for those 6 ticks, then
## glides the cursor (0x440233) until it arrives; state 9 (0x44142a) holds the cursor on the
## target for 12 ticks (0x440288) before the attack state.
const ATTACK_RANGE_TICKS := 6
const ATTACK_TARGET_TICKS := 12
## AI magic (0x44174d → 0x4417df／0x44182a／0x441947) and special (0x441a46 → 0x441ae9／
## 0x441b35／0x441c4c): the setup falls into 0x441ad3, [unit+0x94]=24 — 24 ticks of range
## with the cursor on the caster; the glide; on arrival 24 more ticks (0x44188c／0x441b91)
## of range, area and cursor on the target; then the effect／cut-in.
const CAST_RANGE_TICKS := 24
const CAST_TARGET_TICKS := 24
## AI item use (0x440132, low-word states 7–0xa via table 0x4422a0): state 7 (0x440176) marks the
## use range (0x40f440 from the user's cell) and loads [unit+0x94]=12; state 8 (0x4401c7) draws
## it with the move palette (0x411200) and the cursor on the user for those 12 ticks; state 9
## (0x440211) keeps the range while the cursor glides (the shared 0x440233); state 10
## (0x4402ed) holds the cursor on the lit target for 12 ticks, then the item is used.
const ITEM_RANGE_TICKS := 12
const ITEM_TARGET_TICKS := 12
## 0x45e882(x, y, tx, ty, 16, …): largest per-tick step of the glide.
const GLIDE_MAX_STEP := 16
## Safety bound on a glide that does not converge; map-sized glides take well under 100.
const GLIDE_TICK_LIMIT := 4096
## The AI cast caption (0x43e110 magic／0x43e1c0 special): x = camera + 320 − (bytes / 2) × 12,
## y = camera + 0x114 — centred on the screen at a fixed height, independent of the cells.
## Both pass 0x460884 the font [0x4c1ae0], the FONT.24 body face (24 px full glyphs, cell top
## at y); CAPTION_FONT_SIZE picks that face of the theme font (OriginalBitmapFont.BODY_SIZES).
const CAPTION_TOP := 276.0
const CAPTION_FONT_SIZE := 24

var elapsed := 0.0
var sequence := 0
var range_rects: Array[Rect2] = []
## The range cells' palette: "attack" (0x411480) for a strike, "move" (0x411200) for an item.
var range_palette := "attack"
## Set by begin_item: the cue belongs to an item use (BattleItemUsePresentation), not an exchange.
var item_lead := false
## Whether the strike is a cast (magic／special): its glide and target stages draw the effect
## area at the cursor and its glide frames the cursor; an attack's target stage draws the
## cursor only and its glide scrolls with the cursor away from the far map edges.
var cast := false
## The 0x4116a0 palette of a cast's effect area: "magic" (palette 0) or "special" (palette 1).
var area_palette := "special"
## Ticks of the leading "camera" stage: the 0x43bf30 glide to the actor, drawing nothing.
var camera_ticks := 0
## The effect area under the cursor after each glide tick (cast only; the last entry is the
## target's), as world rects.
var glide_area: Array = []
## The battle camera the lead-in moves (BattleCameraController); null leaves the view alone.
var camera_controller: RefCounted
## The last lead-in tick whose camera step has been applied (−1: none).
var _camera_tick := -1
var source := Vector2.ZERO
var target := Vector2.ZERO
var cell_size := Vector2(32, 32)
var range_ticks := 0
var target_ticks := 0
## The strike's defender: lit with the shared target highlight during the "target" hold.
var target_unit_id := ""
## Cursor position after each glide tick (the last entry is the target).
var glide: Array[Vector2] = []
var duration := 0.0
## The skill name an AI cast captions its lead-in with; empty for an attack.
var caption := ""
var caption_label: Label
var caption_layer: CanvasLayer

static var _cos_table: PackedInt64Array = PackedInt64Array()
static var _sin_table: PackedInt64Array = PackedInt64Array()
static var _tangent_edges: PackedInt64Array = PackedInt64Array()


func _ready() -> void:
	caption_layer = CanvasLayer.new()
	add_child(caption_layer)
	caption_label = Label.new()
	caption_label.name = "SkillCaption"
	caption_label.position = Vector2(0, CAPTION_TOP)
	caption_label.size = Vector2(640, 24)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	caption_label.add_theme_color_override("font_color", Color.WHITE)
	caption_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption_label.add_theme_constant_override("shadow_offset_x", 1)
	caption_label.add_theme_constant_override("shadow_offset_y", 1)
	caption_label.add_theme_constant_override("shadow_outline_size", 0)
	caption_layer.add_child(caption_label)
	_sync_caption()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_caption()


func _sync_caption() -> void:
	if caption_layer != null:
		caption_layer.visible = is_visible_in_tree() and caption != "" and stage() in ["range", "cursor", "target"]


## Whether a settled exchange opens with this map lead-in: only when the AI acted. The
## player's confirmed attack (0x50 → 0x51 → 0x52) and cast (0x79 → 0x7a, 0x98 → 0x99) switch
## state on the confirm tick without drawing range, cursor or hovered-unit info again; the
## original's AI attack and cast states draw the range, glide the cursor and hold on the
## target. See docs/evidence_packets/static_reverse/original_cast_overlays.md.
static func leads(_strike: Dictionary, attacker: Dictionary) -> bool:
	return not bool(attacker.get("player_commandable", false))


## Marks the exchange as presented without drawing anything (a player's confirmed action).
func skip(exchange_sequence: int) -> void:
	sequence = exchange_sequence
	item_lead = false
	elapsed = 0.0
	duration = 0.0
	caption = ""
	cast = false
	camera_ticks = 0
	camera_controller = null
	glide.clear()
	glide_area.clear()
	range_rects.clear()
	hide()
	_sync_caption()


## `area_at(cell) -> Array` gives a cast's effect cells centred on a map cell (empty Callable for
## an attack); `controller` is the battle camera (null in presentation-only harnesses).
func begin(exchange_sequence: int, strike: Dictionary, cells: Array, origin: Vector2i, destination: Vector2i, map_config: RefCounted, controller: RefCounted = null, area_at: Callable = Callable()) -> void:
	sequence = exchange_sequence
	item_lead = false
	range_palette = "attack"
	target_unit_id = str(strike.get("defender_id", ""))
	elapsed = 0.0
	pace = float(CombatPresentationTiming.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0))
	cell_size = map_config.grid_projection["cell_size"]
	source = map_config.grid_to_world(origin)
	target = map_config.grid_to_world(destination)
	range_rects.clear()
	for cell in cells:
		range_rects.append(Rect2(map_config.grid_to_world(cell), cell_size))
	cast = strike.has("skill_id")
	area_palette = "magic" if str(strike.get("skill_id", "")).begins_with("magic:") else "special"
	range_ticks = CAST_RANGE_TICKS if cast else ATTACK_RANGE_TICKS
	target_ticks = CAST_TARGET_TICKS if cast else ATTACK_TARGET_TICKS
	glide.clear()
	for point in glide_path(Vector2i(source.round()), Vector2i(target.round())):
		glide.append(Vector2(point))
	# 0x4100e0 takes the cursor pixel >> 5 as the centre cell and never tests the range.
	glide_area.clear()
	var area_by_cell := {}
	for point in glide:
		var cell: Vector2i = map_config.world_to_grid(point)
		if not area_by_cell.has(cell):
			var rects: Array[Rect2] = []
			if cast and area_at.is_valid():
				for area_cell in area_at.call(cell):
					rects.append(Rect2(map_config.grid_to_world(area_cell), cell_size))
			area_by_cell[cell] = rects
		glide_area.append(area_by_cell[cell])
	# The camera stage: the shared battle focus glide to the actor (0x43bf30 at the battle
	# step); the ticks it returns 0 run before the range, its landing tick is the setup tick.
	camera_controller = controller
	camera_ticks = 0
	_camera_tick = -1
	if camera_controller != null and camera_controller.camera != null and camera_controller.scroll_to_grid(origin) and camera_controller.is_scrolling():
		camera_ticks = BattleCameraController.scroll_ticks(camera_controller.camera.position, camera_controller.scroll_target, BattleCameraController.BATTLE_SCROLL_STEP) - 1
	duration = OriginalTick.seconds(camera_ticks + range_ticks + glide.size() + target_ticks)
	caption = str(strike.get("magic_name", strike.get("skill_name", ""))) if cast else ""
	if caption_label != null:
		caption_label.text = caption
	show()
	_sync_caption()
	queue_redraw()


## The AI item lead-in (ITEM_RANGE_TICKS／ITEM_TARGET_TICKS): the same camera, cursor glide and
## lit-target hold as an attack, with the use range in the move palette.
func begin_item(target_id: String, cells: Array, origin: Vector2i, destination: Vector2i, map_config: RefCounted, controller: RefCounted = null) -> void:
	begin(sequence, {"defender_id": target_id}, cells, origin, destination, map_config, controller)
	item_lead = true
	range_palette = "move"
	range_ticks = ITEM_RANGE_TICKS
	target_ticks = ITEM_TARGET_TICKS
	duration = OriginalTick.seconds(camera_ticks + range_ticks + glide.size() + target_ticks)


func advance(delta: float) -> void:
	elapsed = minf(duration, elapsed + maxf(0.0, delta) * pace)
	_apply_camera()
	_sync_caption()
	queue_redraw()


func stage() -> String:
	if not visible or elapsed >= duration:
		return "complete"
	var tick := int(OriginalTick.ticks(elapsed))
	if tick < camera_ticks:
		return "camera"
	if tick < camera_ticks + range_ticks:
		return "range"
	if tick < camera_ticks + range_ticks + glide.size():
		return "cursor"
	return "target"


## Glide ticks elapsed (0 = the first glide tick; negative before the glide).
func _glide_tick() -> int:
	return int(OriginalTick.ticks(elapsed)) - camera_ticks - range_ticks


## The cursor is drawn once per tick after that tick's glide step (0x4402c8／0x441927).
func cursor_position() -> Vector2:
	var glide_tick := _glide_tick()
	if glide_tick < 0 or glide.is_empty():
		return source
	return glide[mini(glide_tick, glide.size() - 1)]


## Per stage, what the original draws: nothing while the camera reaches the actor; the range in
## the range and glide stages and, for a cast only, in the target hold (0x44142a draws the
## attack's target with the cursor alone).
func range_visible() -> bool:
	var current := stage()
	return current in ["range", "cursor"] or (current == "target" and cast)


func cursor_visible() -> bool:
	return stage() in ["range", "cursor", "target"]


## A cast's effect area at the cursor's cell in the glide and target stages (0x4116a0).
func area_rects() -> Array:
	if not cast or glide_area.is_empty() or stage() not in ["cursor", "target"]:
		return []
	return glide_area[clampi(_glide_tick(), 0, glide_area.size() - 1)]


## The camera steps of the glide, one per tick crossed since the last call: a cast frames the
## cursor every tick (0x43c0f0: the cursor's cell point where the battle focus puts it,
## clamped to the map); an attack adds the cursor's step on each axis edge_follow_request
## allows and clamps (0x42dc50 → 0x46bede). The camera stage is the controller's own glide.
func _apply_camera() -> void:
	if camera_controller == null or camera_controller.camera == null or glide.is_empty():
		return
	var last := mini(_glide_tick(), glide.size() - 1)
	var half: Vector2 = Vector2(camera_controller.logical_viewport_size) * 0.5
	var world := Vector2(camera_controller.map_config.world_size) if camera_controller.map_config != null else Vector2.ZERO
	while _camera_tick < last:
		_camera_tick += 1
		var point: Vector2 = glide[_camera_tick]
		if cast:
			if _camera_tick == last:
				camera_controller.center_on_point(point + cell_size * 0.5)
		else:
			var before: Vector2 = source if _camera_tick == 0 else glide[_camera_tick - 1]
			var request := edge_follow_request(point, point - before, half, world)
			if request != Vector2.ZERO:
				camera_controller.snap_to(camera_controller.camera.position + request)


## 0x4402cd..0x441425: after the glide step the cursor (the cell's top-left pixel) requests the
## step on an axis when `c < 0 ? c > half view : c < map size − half view` holds for its new
## coordinate — the sign of the position, not of the step, is tested, so on the map the
## camera goes with the cursor unless it stands in the right／bottom half-view band.
static func edge_follow_request(cursor: Vector2, step: Vector2, half_viewport: Vector2, world_size: Vector2) -> Vector2:
	var request := Vector2.ZERO
	if (cursor.x > half_viewport.x) if cursor.x < 0.0 else (cursor.x < world_size.x - half_viewport.x):
		request.x = step.x
	if (cursor.y > half_viewport.y) if cursor.y < 0.0 else (cursor.y < world_size.y - half_viewport.y):
		request.y = step.y
	return request


## The cursor positions of the glide, one per tick, from `from` to `to` (pixels): 0x45e882
## each tick — distance = trunc(sqrt(dx² + dy²)); within 1 px it snaps to the target and the
## state ends (that tick counts); otherwise it moves max(2, min(16, distance >> 3)) px along
## direction 0x45e6da(from, to) of a 256-step circle, each axis (table × step) >> 16.
static func glide_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_build_tables()
	var path: Array[Vector2i] = []
	var at := from
	while path.size() < GLIDE_TICK_LIMIT:
		var offset := to - at
		var distance := int(sqrt(float(offset.x * offset.x + offset.y * offset.y)))
		if distance <= 1:
			path.append(to)
			return path
		var step := maxi(2, mini(GLIDE_MAX_STEP, distance >> 3))
		var direction := direction_index(offset)
		at += Vector2i((_cos_table[direction] * step) >> 16, (_sin_table[direction] * step) >> 16)
		path.append(at)
	push_error("BattleAttackCue glide from %s to %s did not converge" % [from, to])
	path.append(to)
	return path


## 0x45e6da: the 256-step direction of `offset`. |dy|·65536／|dx| is bisected against the
## 64 half-step tangent edges (0x4a3dfc), then folded into the quadrant; a vertical offset is
## 64 (down) or 192 (up). A near-horizontal offset pointing up yields 256, one past the table.
static func direction_index(offset: Vector2i) -> int:
	_build_tables()
	var run := absi(offset.x)
	if run == 0:
		return 192 if offset.y < 0 else 64
	var ratio := (absi(offset.y) << 16) / run
	var low := 0
	var high := 64
	var index := 0
	while true:
		var half := (high - low) >> 1
		if half == 0:
			index = 0
			break
		var middle := low + half
		if ratio < _tangent_edges[middle]:
			high = middle
			if ratio < _tangent_edges[middle - 1]:
				continue
			index = middle
			break
		low = middle
		if ratio > _tangent_edges[middle + 1]:
			continue
		index = middle + 1
		break
	if offset.x < 0:
		return index + 128 if offset.y < 0 else 128 - index
	return 256 - index if offset.y < 0 else index


## The original's fixed-point tables, reproduced: cos／sin (0x4a35fc／0x4a39fc) are
## round(65536 · cos／sin(2πi／256)); the tangent edges (0x4a3dfc) are round(65536 ·
## tan(2π(i + ½)／256)) for i < 64, edge 64 wraps negative and so never bounds a ratio.
## Index 256 reads the next table's first entry: cos → sin[0] = 0, sin → edge[0].
static func _build_tables() -> void:
	if not _cos_table.is_empty():
		return
	for i in range(256):
		_cos_table.append(roundi(65536.0 * cos(TAU * i / 256.0)))
		_sin_table.append(roundi(65536.0 * sin(TAU * i / 256.0)))
	for i in range(64):
		_tangent_edges.append(roundi(65536.0 * tan(TAU * (i + 0.5) / 256.0)))
	_tangent_edges.append(1 << 40)
	_cos_table.append(_sin_table[0])
	_sin_table.append(_tangent_edges[0])


func _draw() -> void:
	# The lead-in's own tick drives the 17-tick pulse and the 8-tick border frames.
	var tick := int(OriginalTick.ticks(elapsed))
	if range_visible():
		_draw_cells(range_rects, range_palette, tick)
	_draw_cells(area_rects(), area_palette, tick)
	# The gliding target cursor is the original's yellow I_RECT01 cell frame (the same frame
	# the player's target selection shows), not a teleport of the physical mouse.
	if cursor_visible():
		draw_texture(TARGET_FRAME, cursor_position())


## One palette's cells as the original drawers blit them: the ramp colour averaged over the map
## (blit mode 6) under the opaque I_rect border frame.
func _draw_cells(rects: Array, palette: String, tick: int) -> void:
	if rects.is_empty():
		return
	var fill := RangeCellOverlay.fill_color(palette, tick)
	var sheet := RangeCellOverlay.border_sheet(palette)
	var frame := RangeCellOverlay.border_region(palette, tick)
	for rect in rects:
		draw_rect(rect, fill)
		draw_texture_rect_region(sheet, rect, frame)

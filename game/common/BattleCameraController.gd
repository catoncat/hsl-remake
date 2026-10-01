extends RefCounted
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_mechanics_audit.md
##   rules: remake-invented (Home recenter, clamp)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.md
##     (logical 640×480 → world → grid chain)
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (focus moves 32→24→12→6→2 px per frame; during an AI walk it follows the path at ≈4 px per tick)
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   timing: remake-invented (Home recenter and save restore snap)
##
## Every write of the battle camera's position goes through this controller: `scroll_to` /
## `scroll_to_grid` (the original's per-tick glide; the speed token passes its own step and
## tolerance), `follow_walk` (the camera walking with a walker), `pan` (edge/arrow scrolling) and
## `snap_to` (cuts). `advance(delta)` steps a running glide once per original tick;
## `run_camera_panel_motion_tests` checks that no other game file assigns the camera position.

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const DEFAULT_CELL_SIZE := Vector2(32.0, 32.0)
## 0x43e4a0 requests ±12 px per tick at the view edge (or the arrow keys) and 0x46bede
## applies the request once per frame: 12 px per 16 ms tick.
const EDGE_SCROLL_PIXELS_PER_TICK := 12.0
const EDGE_SCROLL_PIXELS_PER_SECOND := EDGE_SCROLL_PIXELS_PER_TICK * OriginalTick.TICKS_PER_SECOND
## 0x43e4a0 runs its request loop twice while [0x4c6390] & 0x600 — the input poll 0x415910
## sets 0x200 for DIK 0x2a (left Shift) and 0x400 for DIK 0x36 (right Shift): ±24 px a tick.
const EDGE_SCROLL_SHIFT_PASSES := 2
## 0x43bf30 centring glide: 0x45e80d moves each axis by clamp((target − current) >> 1, ±step)
## per tick and lands when both axes are within the tolerance. The step is 32 px (0x43bffa) in
## battle and 16 px (0x43c007) while the story phase bit is set; the tolerance is 4 (0x43c030).
const BATTLE_SCROLL_STEP := 32
const STORY_SCROLL_STEP := 16
const SCROLL_TOLERANCE := 4
## actScrollBGToPosSpeed (0x43c140): the same 0x45e80d call with step = the script speed and
## tolerance 1; no story-phase or fast-forward step change.
const SPEED_SCROLL_TOLERANCE := 1
## Battle walkers (defProcPlayer 0x443f5a, defProcEnemy 0x4411cb) step 4 px per tick, 8 ticks a
## cell (`+0x9e = 8`); the camera follows by the same step.
const WALK_FOLLOW_PIXELS_PER_TICK := 4.0
## 0x43bf30 frames an object by setting the view's top-left to its point − (0x140, 0xc0): the
## point lands at the view's (320, 192), not its centre. The camera position here is the centre
## of the 640×480 view, so a framed point's centre is the point + (0, 48). Every "look at this"
## goes through it: battle focus (turn start, first control, selection, AI turns, Home,
## treasure, the reward recipient) and the script's object／position shots.
const FOCUS_VIEW_POINT := Vector2(320, 192)
const FOCUS_OFFSET := Vector2(320, 240) - FOCUS_VIEW_POINT

var camera: Camera2D
var map_config: RefCounted
var logical_viewport_size: Vector2i = Vector2i(640, 480)
## The running glide: "" (none), "step" (0x45e80d per tick) or "follow" (walk follow, one precomputed position per tick; scroll_target is its end).
var scroll_mode := ""
var scroll_target := Vector2.ZERO
var _scroll_step := BATTLE_SCROLL_STEP
var _scroll_tolerance := SCROLL_TOLERANCE
var _scroll_clock := 0.0
## Glides started (sum of kinds), read by the camera-motion tests and the route log.
var scroll_count := 0
var _follow_trace: Array = []
var _follow_index := 0
## Walk follows started (read by the walk-follow tests).
var follow_count := 0


static func create(camera_node: Camera2D, config: RefCounted, viewport_size: Vector2i) -> RefCounted:
	var controller := new()
	controller.camera = camera_node
	controller.map_config = config
	controller.logical_viewport_size = viewport_size
	return controller


func configure_camera_limits() -> void:
	if camera == null or map_config == null:
		return
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = map_config.world_size.x
	camera.limit_bottom = map_config.world_size.y
	camera.enabled = true
	camera.make_current()


func viewport_to_logical(position: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return position
	return Vector2(
		position.x * float(logical_viewport_size.x) / viewport_size.x,
		position.y * float(logical_viewport_size.y) / viewport_size.y
	)


func logical_to_world(logical_position: Vector2) -> Vector2:
	if camera == null:
		return logical_position
	return camera.position - _half_viewport() + logical_position


func world_to_logical(world_position: Vector2) -> Vector2:
	if camera == null:
		return world_position
	return world_position - camera.position + _half_viewport()


func grid_cell_size() -> Vector2:
	if map_config == null:
		return DEFAULT_CELL_SIZE
	return map_config.grid_projection.get("cell_size", DEFAULT_CELL_SIZE)


func grid_cell_center_world(coord: Vector2i) -> Vector2:
	if map_config == null:
		return Vector2.ZERO
	return map_config.grid_to_world(coord) + grid_cell_size() * 0.5


func grid_cell_center_to_logical(coord: Vector2i) -> Vector2:
	return world_to_logical(grid_cell_center_world(coord))


func grid_at_logical(logical_position: Vector2) -> Vector2i:
	if map_config == null:
		return Interaction.NO_CELL
	return map_config.world_to_grid(logical_to_world(logical_position))


## The camera centre that puts world `point` where 0x43bf30 frames it (the view's (320, 192)),
## before the map clamp.
static func focus_centre(point: Vector2) -> Vector2:
	return point + FOCUS_OFFSET


## Cut: the cell centre jumps to the focus point (clamped) and any glide stops.
func center_on_grid(coord: Vector2i) -> bool:
	if camera == null or map_config == null:
		return false
	center_on_point(grid_cell_center_world(coord))
	return true


## Cut that puts world `point` at the focus point (the view's (320, 192)), clamped; stops any
## glide. The AI cast lead-in frames its gliding cursor with it every tick: 0x43c0f0 puts the
## cursor cell where 0x43bf30 puts a unit (original_cast_overlays).
func center_on_point(point: Vector2) -> void:
	snap_to(focus_centre(point))


## Cut to a world position (clamped); stops any glide.
func snap_to(target: Vector2) -> void:
	if camera == null:
		return
	stop_scroll()
	camera.position = clamped_position(target)


## Battle focus: the 0x43bf30 glide that frames the cell centre at the view's (320, 192), at the
## battle step.
func scroll_to_grid(coord: Vector2i) -> bool:
	if camera == null or map_config == null:
		return false
	scroll_to(focus_centre(grid_cell_center_world(coord)), BATTLE_SCROLL_STEP)
	return true


## Starts the per-tick glide to `target` (clamped) and returns its seconds; a target already
## within the tolerance lands at once (0 s).
func scroll_to(target: Vector2, step: int = BATTLE_SCROLL_STEP, tolerance: int = SCROLL_TOLERANCE) -> float:
	if camera == null:
		return 0.0
	var clamped := clamped_position(target)
	var ticks := scroll_ticks(camera.position, clamped, step, tolerance)
	if ticks <= 1:
		snap_to(clamped)
		return 0.0
	scroll_mode = "step"
	scroll_target = clamped
	_scroll_step = step
	_scroll_tolerance = tolerance
	_scroll_clock = 0.0
	scroll_count += 1
	return OriginalTick.seconds(ticks)


## Walk follow: each tick the walker (from `walker_start` along `points`, world positions)
## steps `pixels_per_tick` and the camera takes the same step on every axis where
## walk_follow_request allows it, clamped to the map (0x46bede). The walk's camera positions are
## precomputed; returns the ticks, 0 when the camera would not move (nothing starts).
func follow_walk(walker_start: Vector2, points: Array, pixels_per_tick: float = WALK_FOLLOW_PIXELS_PER_TICK) -> int:
	if camera == null or map_config == null:
		return 0
	var trace := walk_follow_trace(camera.position, walker_start, points, pixels_per_tick, _half_viewport(), Vector2(map_config.world_size))
	if trace.all(func(position: Vector2) -> bool: return position == camera.position):
		return 0
	scroll_mode = "follow"
	_follow_trace = trace
	_follow_index = 0
	scroll_target = trace.back()
	_scroll_clock = 0.0
	follow_count += 1
	return trace.size()


## Camera positions, one per walker tick. The walker takes one step per tick toward the next
## point (a shorter last step lands on it); the camera adds walk_follow_request and clamps.
static func walk_follow_trace(camera_start: Vector2, walker_start: Vector2, points: Array, pixels_per_tick: float, half_viewport: Vector2, world_size: Vector2) -> Array:
	var trace: Array = []
	var max_centre := Vector2(maxf(half_viewport.x, world_size.x - half_viewport.x), maxf(half_viewport.y, world_size.y - half_viewport.y))
	var view := camera_start
	var walker := walker_start
	for point in points:
		var target: Vector2 = point
		while walker != target and trace.size() < 4096:
			var delta := target - walker
			var move := delta if delta.length() <= pixels_per_tick else delta.normalized() * pixels_per_tick
			view = (view + walk_follow_request(walker, move, half_viewport, world_size)).clamp(half_viewport, max_centre)
			walker = target if move == delta else walker + move
			trace.append(view)
	return trace


## The walker's step `move` from `walker` (before the step) is requested on an axis unless the
## walker stands within half a view of the map edge it walks toward: right needs x > half width,
## left x < map width − half width, down y > half height, up y < map height − half height
## (0x4c0960／0x4c0968／0x4c0964／0x4c096c, set by 0x46bb02(640, 480) and 0x46bb65).
static func walk_follow_request(walker: Vector2, move: Vector2, half_viewport: Vector2, world_size: Vector2) -> Vector2:
	var request := Vector2.ZERO
	if (move.x > 0.0 and walker.x > half_viewport.x) or (move.x < 0.0 and walker.x < world_size.x - half_viewport.x):
		request.x = move.x
	if (move.y > 0.0 and walker.y > half_viewport.y) or (move.y < 0.0 and walker.y < world_size.y - half_viewport.y):
		request.y = move.y
	return request


func is_scrolling() -> bool:
	return scroll_mode != ""


## Stops a glide where it is.
func stop_scroll() -> void:
	scroll_mode = ""


## Lands a running glide on its target at once (fast-forward).
func finish_scroll() -> void:
	if scroll_mode != "":
		snap_to(scroll_target)


## Steps a running glide; returns whether the camera moved.
func advance(delta: float) -> bool:
	if scroll_mode == "" or camera == null:
		return false
	var before := camera.position
	_scroll_clock += maxf(delta, 0.0)
	if scroll_mode == "follow":
		while _scroll_clock >= OriginalTick.TICK_SECONDS and scroll_mode == "follow":
			_scroll_clock -= OriginalTick.TICK_SECONDS
			camera.position = _follow_trace[_follow_index]
			_follow_index += 1
			if _follow_index >= _follow_trace.size():
				scroll_mode = ""
		return camera.position != before
	while _scroll_clock >= OriginalTick.TICK_SECONDS and scroll_mode != "":
		_scroll_clock -= OriginalTick.TICK_SECONDS
		var current := Vector2i(camera.position.round())
		var target := Vector2i(scroll_target.round())
		if scroll_landed(current, target, _scroll_tolerance):
			camera.position = scroll_target
			scroll_mode = ""
		else:
			camera.position = Vector2(scroll_step(current, target, _scroll_step))
	return camera.position != before


## One 0x45e80d call: each axis moves half the remaining distance (arithmetic shift),
## clamped to ±step.
static func scroll_step(current: Vector2i, target: Vector2i, step: int) -> Vector2i:
	var difference := target - current
	return current + Vector2i(clampi(difference.x >> 1, -step, step), clampi(difference.y >> 1, -step, step))


static func scroll_landed(current: Vector2i, target: Vector2i, tolerance: int) -> bool:
	return absi(target.x - current.x) <= tolerance and absi(target.y - current.y) <= tolerance


## Ticks a glide from `from` to `to` takes, the landing tick included.
static func scroll_ticks(from: Vector2, to: Vector2, step: int, tolerance: int = SCROLL_TOLERANCE) -> int:
	var current := Vector2i(from.round())
	var target := Vector2i(to.round())
	var ticks := 0
	while not scroll_landed(current, target, tolerance) and ticks < 4096:
		current = scroll_step(current, target, step)
		ticks += 1
	return ticks + 1


## Edge／arrow scrolling; player input stops a running glide.
func pan(direction: Vector2, delta: float, pixels_per_second: float) -> bool:
	if camera == null or direction == Vector2.ZERO:
		return false
	stop_scroll()
	var next := clamped_position(camera.position + direction * pixels_per_second * delta)
	if next == camera.position:
		return false
	camera.position = next
	return true


## Touch drag (TouchControls.take_pan): moves the camera by `offset` world pixels, clamped to the
## map; player input stops a running glide. Returns whether the camera moved.
func pan_by(offset: Vector2) -> bool:
	if camera == null or offset == Vector2.ZERO:
		return false
	stop_scroll()
	var next := clamped_position(camera.position + offset)
	if next == camera.position:
		return false
	camera.position = next
	return true


static func edge_direction(point: Vector2, pointer_active: bool) -> Vector2:
	# 0x43e4a0 uses strict viewport thresholds, independently on both axes; the
	# caller pans at EDGE_SCROLL_PIXELS_PER_SECOND within the normal map bounds.
	if not pointer_active or not Rect2(0, 0, 640, 480).has_point(point):
		return Vector2.ZERO
	return Vector2(-1 if point.x < 10 else (1 if point.x > 630 else 0), -1 if point.y < 10 else (1 if point.y > 470 else 0))


## 0x43e4a0 checks four directions independently, each "arrow bit set or pointer past that
## edge" → one ±12 px request: an arrow key and the same edge together still request once, an
## arrow key and the opposite edge cancel, and a diagonal is 12 px on each axis (not normalised).
## Arrow bits 1／2／4／8 are ←／→／↑／↓. Battle (0x43e570) and the big map (0x4271f1) share it.
static func scroll_direction(edge: Vector2) -> Vector2:
	var left := Input.is_action_pressed("ui_left") or edge.x < 0
	var right := Input.is_action_pressed("ui_right") or edge.x > 0
	var up := Input.is_action_pressed("ui_up") or edge.y < 0
	var down := Input.is_action_pressed("ui_down") or edge.y > 0
	return Vector2(int(right) - int(left), int(down) - int(up))


## Edge／arrow scroll speed this frame: doubled while either Shift key is held (0x43e4a0).
static func edge_scroll_pixels_per_second() -> float:
	return EDGE_SCROLL_PIXELS_PER_SECOND * (EDGE_SCROLL_SHIFT_PASSES if Input.is_key_pressed(KEY_SHIFT) else 1)


func clamped_position(target: Vector2) -> Vector2:
	if map_config == null:
		return target
	var half_viewport := _half_viewport()
	var max_center := Vector2(
		max(half_viewport.x, float(map_config.world_size.x) - half_viewport.x),
		max(half_viewport.y, float(map_config.world_size.y) - half_viewport.y)
	)
	return Vector2(
		clampf(target.x, half_viewport.x, max_center.x),
		clampf(target.y, half_viewport.y, max_center.y)
	)


func _half_viewport() -> Vector2:
	return Vector2(float(logical_viewport_size.x) * 0.5, float(logical_viewport_size.y) * 0.5)

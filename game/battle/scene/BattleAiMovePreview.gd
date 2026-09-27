extends RefCounted
## Enemy／ally AI move preview: before an AI unit walks, the camera glides to it and its blue
## reach (the same move palette as the player's Move overlay) shows for preview_ticks(action)
## after the glide's own ticks; then the overlay clears, the walk starts and the camera walks with the
## walker (BattleCameraController.follow_walk). `BattleSceneRuntime._process` drives `tick` (a
## harness with processing off drives it through `tick_ai_playback`). The PlayLoop has already settled the move: the preview only holds the actor
## node at its origin (`holds`) and counts as actor motion so AI playback, combat and menus
## wait for it. Explicit fast-forward (`finish`) starts the walk at once.
## provenance:
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (blue reach centred on the mover, ≈ RGB(70,75,170) over the map, then the walk)
##   layout: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_action_state_machine.md
##     (AI move sub-state 1 0x441043: reach 12 ticks after a pursuit 0x440d92, 24 after a station 0x441ad3)
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   audio: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (no onset while the reach shows)

const OriginalTick = preload("res://game/common/OriginalTick.gd")
## `[unit+0x94]` on entering move sub-state 1 (0x441043 counts it down, drawing the reach each tick).
const PURSUIT_PREVIEW_TICKS := 12
const STATION_PREVIEW_TICKS := 24

var runtime: Node
var _unit_id := ""
var _actor: Node
var _path: Array = []
var _duration := 0.0
var _action: Dictionary = {}
var _clock := 0.0
var _ticks := 0
## Glide ticks to the mover plus preview_ticks(action).
var _total_ticks := STATION_PREVIEW_TICKS
## The reach appears once the glide's ticks have passed (the recording: scroll, then reach).
var _glide_ticks := 0
var _cells: Array = []
var reach_shown := false
## Previews started (read by tests and the route log).
var shown_count := 0
var last_cells: Array = []


static func create(scene_runtime: Node) -> RefCounted:
	var preview := new()
	preview.runtime = scene_runtime
	return preview


## A pursuit walk (0x440d5c→0x4111a0, no strike this turn) writes 12 at 0x440d92; every walk to a
## chosen station or goal — attack, skill, item, home — goes through 0x441ad3, which writes 24.
static func preview_ticks(action: Dictionary) -> int:
	return PURSUIT_PREVIEW_TICKS if str(action.get("purpose", "")) == "pursuit" else STATION_PREVIEW_TICKS


## `cells` is the mover's reach from its origin (read from the loop before the step).
func begin(action: Dictionary, actor: Node, path: Array, duration: float, origin: Vector2i, cells: Array) -> void:
	finish()
	_unit_id = str(action.get("actor_id", ""))
	_actor = actor
	_path = path
	_duration = duration
	_action = action
	_clock = 0.0
	_ticks = 0
	shown_count += 1
	last_cells = cells.duplicate()
	_cells = cells.duplicate()
	reach_shown = false
	_glide_ticks = 0
	if runtime.camera_controller != null and runtime.camera != null:
		var target: Vector2 = runtime.camera_controller.clamped_position(runtime.camera_controller.grid_cell_center_world(origin))
		var glide: int = runtime.camera_controller.scroll_ticks(runtime.camera.position, target, runtime.camera_controller.BATTLE_SCROLL_STEP)
		_glide_ticks = glide - 1 if glide > 1 else 0
	_total_ticks = _glide_ticks + preview_ticks(action)
	runtime.focus_camera_on_grid(origin)
	_show_reach_when_due()


func busy() -> bool:
	return _unit_id != ""


func holds(unit_id: String) -> bool:
	return _unit_id != "" and unit_id == _unit_id


func tick(delta: float) -> void:
	if _unit_id == "":
		return
	_clock += maxf(delta, 0.0)
	while _clock >= OriginalTick.TICK_SECONDS and _ticks < _total_ticks:
		_clock -= OriginalTick.TICK_SECONDS
		_ticks += 1
	_show_reach_when_due()
	if _ticks >= _total_ticks:
		finish()


func _show_reach_when_due() -> void:
	if not reach_shown and _ticks >= _glide_ticks:
		reach_shown = true
		runtime.overlays.show_ai_move_preview(_cells)


## Ends the preview and starts the held walk (no-op when idle).
func finish() -> void:
	if _unit_id == "":
		return
	var actor := _actor
	var action := _action
	_unit_id = ""
	_actor = null
	reach_shown = false
	runtime.overlays.clear_ai_move_preview()
	if actor != null and is_instance_valid(actor):
		var walker_start: Vector2 = actor.position
		actor.move_along(_path, _duration)
		if runtime.camera_controller != null:
			runtime.camera_controller.follow_walk(walker_start, _path)
		runtime.get_node("BattlePresentation").navigation_cue.begin(action, actor, runtime.map_config)

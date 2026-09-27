extends Node
## Debug freeze for playtesting (user request 2026-09-24): P freezes the whole game — title,
## opening movie, battle, story, town and big map — and while frozen N advances exactly one
## frame (hold N to creep forward); P again resumes where it stopped. It is the SceneTree
## pause: every game node, tween, animation and audio player is pausable, so nothing moves,
## nothing sounds and no click or key reaches the game while it is frozen.
##
## This autoload processes always and first in every process pass (process_priority), so a
## step's frame — its _process, timers and tweens — completes before the next pass freezes the
## tree again; and it keeps itself the last child of root, because _input runs in reverse tree
## order: P／N reach it before any scene's "any key" handler (movie skip, dialogue advance).
##
## Contract for game code (tests/run_debug_pause_tests.gd scans it): SceneTree timers are
## created with process_always = false, and only what a freeze must leave usable processes
## always (CampaignProgress's resume prompt, the drawn mouse cursor GameCursor, this node).
##
## A development switch, not a player control (docs/OPTIONS.md OPT-DEV): HSL_DEBUG_PAUSE=1
## turns it on and tools/play.sh sets that by default, so playtests keep P／N; =0 turns it off.
## Unset, a windowless run (tests, harnesses) has it on and a windowed one off — a player who
## starts the game any other way never freezes it by accident. Off, the node stays installed
## but takes no key and never touches the pause.
## provenance:
##   rules: remake-invented
##     (debug freeze and single-frame step behind the HSL_DEBUG_PAUSE development switch; the original has no such
##     control)
##   layout: remake-invented (top-left badge)
##   strings: remake-invented (「停格中」badge)
##   timing: remake-invented (one step = one process frame)

const TOGGLE_KEY := KEY_P
const STEP_KEY := KEY_N
const SWITCH_ENV := "HSL_DEBUG_PAUSE"
const BADGE_TEXT := "停格中 · 第 %d 幀　P 繼續　N 下一幀"

## Whether P／N work in this process (the HSL_DEBUG_PAUSE switch, read once at start).
var enabled := false
## True while the game is held frozen.
var held := false
## Frames advanced with N during the current hold (the badge shows it).
var stepped_frames := 0
## tree.paused as someone else wants it (the campaign resume prompt): taken when the hold
## begins, cleared when they release it under the hold, restored when the hold ends.
var _others_paused := false
## Process passes a pending step may still run; _stepping marks the unfrozen step.
var _step_passes := 0
var _stepping := false
var badge: Label


## HSL_DEBUG_PAUSE: 1 on, 0 off; unset follows the display (windowless on, windowed off).
static func switched_on() -> bool:
	var raw := OS.get_environment(SWITCH_ENV).strip_edges()
	if raw == "":
		return DisplayServer.get_name() == "headless"
	if raw != "0" and raw != "1":
		push_error("%s must be 0 or 1, got %s; the debug freeze stays off" % [SWITCH_ENV, raw])
		return false
	return raw == "1"


func _ready() -> void:
	enabled = switched_on()
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000000
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	badge = Label.new()
	badge.name = "DebugPauseBadge"
	badge.position = Vector2(6, 4)
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.hide()
	layer.add_child(badge)
	get_tree().root.child_order_changed.connect(_stay_last)
	_stay_last()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == TOGGLE_KEY and not key.echo:
		set_held(not held)
		get_viewport().set_input_as_handled()
	elif key.keycode == STEP_KEY and held:
		step()
		get_viewport().set_input_as_handled()


func set_held(on: bool) -> void:
	if not enabled or on == held:
		return
	held = on
	_step_passes = 0
	_stepping = false
	if held:
		_others_paused = get_tree().paused
		stepped_frames = 0
		get_tree().paused = true
	else:
		get_tree().paused = _others_paused
	_show_badge()


## Unfreezes the held game for exactly one process frame; each call queues one more frame.
func step() -> void:
	if not held:
		return
	_step_passes += 1
	_stepping = true
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not held:
		return
	if _step_passes > 0:
		_step_passes -= 1
		stepped_frames += 1
		_show_badge()
	elif _stepping:
		_stepping = false
		get_tree().paused = true
	elif not get_tree().paused:
		# Someone else released their pause under the hold (the resume prompt closed).
		_others_paused = false
		get_tree().paused = true


func _show_badge() -> void:
	badge.visible = held
	badge.text = BADGE_TEXT % stepped_frames


## root's children change while it is busy adding a scene, so the move is deferred.
func _stay_last() -> void:
	_move_last.call_deferred()


func _move_last() -> void:
	var root := get_parent()
	if is_inside_tree() and root == get_tree().root and get_index() != root.get_child_count() - 1:
		root.move_child(self, -1)

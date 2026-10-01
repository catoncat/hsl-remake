extends Node
## Autoload: plays the game by touch on a device with a touchscreen (phone and tablet browsers, a
## touch laptop). One finger is the left button — a tap clicks on the lift, a held or moved
## finger holds and drags it; a two-finger tap is the right button (cancel, the battle's system
## scroll — as Esc／right click); two fingers moved together pan the battle map and the big map.
## The gestures themselves are TouchGestureRecognizer's.
##
## Without a touchscreen (every desktop) it does nothing at all: no listener, no processing, no
## Input setting changed. With one it turns off Godot's own mouse-from-touch emulation, which
## would press the left button under the first finger of a two-finger gesture, and makes the
## mouse events itself: it reads each touch from the root window's window_input (before any node
## sees it, in window coordinates), hands the recognizer logical positions and parses the mouse
## motion and buttons it returns through Input, at the same window positions Godot's emulation
## would use, motion before each button. The touches themselves stop at this node's _input, so
## controls only ever see the mouse. A mouse keeps working beside it.
##
## When the last finger lifts the pointer leaves the window (the root window's mouse_exited, once
## the gesture's mouse events are through), so a tap at the screen edge does not keep the
## battle's or big map's edge scrolling going (BattleSceneInput.disarm_pointer_scroll).
## The pan is published once a frame and read with take_pan() by the battle runtime and the big
## map, each at its edge-scroll site and under the same condition; a frame that does not read it
## drops it, so a pan made while the map takes no input never lands later as a jump.
## Processes always: like the mouse it drives, touch must still work under a pause (the Tab
## 重製選項 page, the debug freeze).
## provenance:
##   rules: remake-invented (touch input; the original is played with mouse and keyboard only)

const TouchGestureRecognizer = preload("res://game/input/TouchGestureRecognizer.gd")

## The enabled instance; null without a touchscreen (take_pan() then reads nothing).
static var _active: Node = null

var enabled := false
var recognizer: RefCounted
## This frame's pan, logical pixels.
var _frame_pan := Vector2.ZERO
var _last_point := Vector2.ZERO


func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		set_process(false)
		set_process_input(false)
		return
	enabled = true
	_active = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.emulate_mouse_from_touch = false
	recognizer = TouchGestureRecognizer.new()
	get_window().window_input.connect(_on_window_input)
	get_window().focus_exited.connect(_on_focus_exited)


func _exit_tree() -> void:
	if _active == self:
		_active = null


## The camera offset the two-finger drag asked for this frame, in logical pixels — world pixels
## too, as the battle map and the big map draw the world 1:1 in the logical picture. Zero
## without a touchscreen; whatever a frame does not take is dropped.
static func take_pan() -> Vector2:
	if _active == null:
		return Vector2.ZERO
	var pan: Vector2 = _active._frame_pan
	_active._frame_pan = Vector2.ZERO
	return pan


func _process(delta: float) -> void:
	_send(recognizer.advance(delta))
	_frame_pan = recognizer.take_pan()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


func _on_window_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_send(recognizer.touch(touch.index, touch.pressed, _logical(touch.position), touch.canceled))
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_send(recognizer.drag(drag.index, _logical(drag.position)))


func _on_focus_exited() -> void:
	_send(recognizer.reset())


func _logical(window_point: Vector2) -> Vector2:
	return get_window().get_final_transform().affine_inverse() * window_point


func _window_point(logical: Vector2) -> Vector2:
	return get_window().get_final_transform() * logical


func _send(events: Array) -> void:
	for event in events:
		match str(event["kind"]):
			"motion":
				var motion := InputEventMouseMotion.new()
				var at := _window_point(event["position"])
				motion.device = InputEvent.DEVICE_ID_EMULATION
				motion.position = at
				motion.global_position = at
				motion.relative = at - _last_point
				motion.screen_relative = motion.relative
				motion.button_mask = int(event["mask"])
				_last_point = at
				Input.parse_input_event(motion)
			"button":
				var button := InputEventMouseButton.new()
				var at := _window_point(event["position"])
				button.device = InputEvent.DEVICE_ID_EMULATION
				button.position = at
				button.global_position = at
				button.button_index = int(event["button"])
				button.pressed = bool(event["pressed"])
				button.button_mask = int(event["mask"])
				_last_point = at
				Input.parse_input_event(button)
			"leave":
				# Deferred: the mouse events parsed above are delivered first.
				get_window().call_deferred("emit_signal", "mouse_exited")

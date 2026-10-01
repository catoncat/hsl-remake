extends "res://tests/support/TestSuite.gd"

## Touch gestures (game/input/TouchGestureRecognizer.gd, driven by the TouchControls autoload on a
## touchscreen): a finger clicks only on its lift or once it holds or moves, a two-finger tap is
## the right button and never the left, a two-finger drag pans without buttons, leftover fingers
## click nothing and every gesture ends with the pointer leaving. Without a touchscreen the
## autoload stays off.

const TouchGestureRecognizer = preload("res://game/input/TouchGestureRecognizer.gd")
const A := Vector2(100, 200)
const B := Vector2(160, 200)
const EDGE := Vector2(2, 240)


func _init() -> void:
	tag = "TOUCH_GESTURE_TESTS"


func run() -> void:
	_tap_clicks_on_lift()
	_drag_and_hold_press_left()
	_two_finger_tap_is_right_only()
	_two_finger_drag_pans()
	_late_and_extra_fingers()
	_stuck_buttons_released()
	_desktop_stays_off()


static func summary(events: Array) -> Array:
	var rows: Array = []
	for event in events:
		match str(event["kind"]):
			"motion": rows.append("motion %s %d" % [event["position"], event["mask"]])
			"button": rows.append("%s %s %s %d" % [
				"left" if event["button"] == MOUSE_BUTTON_LEFT else "right",
				"down" if event["pressed"] else "up", event["position"], event["mask"]])
			_: rows.append(str(event["kind"]))
	return rows


static func buttons(events: Array, button: int) -> int:
	return events.filter(func(event: Dictionary) -> bool: return event["kind"] == "button" and event["button"] == button).size()


func _tap_clicks_on_lift() -> void:
	var touch := TouchGestureRecognizer.new()
	var events := touch.touch(0, true, A)
	events.append_array(touch.advance(0.05))
	events.append_array(touch.drag(0, A + Vector2(3, 0)))
	_assert_eq(events, [], "a finger landing, resting and moving within the slop sends nothing")
	_assert_eq(summary(touch.touch(0, false, A + Vector2(3, 0))),
		["motion %s 0" % A, "left down %s 1" % A, "left up %s 0" % A, "leave"],
		"the tap clicks on the lift: motion, press and release at the touch-down point, then the pointer leaves")
	_assert_eq(summary(touch.touch(1, false, A)), [], "a lift never seen landing sends nothing")
	touch.touch(2, true, EDGE)
	_assert_eq(summary(touch.touch(2, false, EDGE)).back(), "leave",
		"a tap at the screen edge ends with the pointer leaving, so edge scrolling does not run on")


func _drag_and_hold_press_left() -> void:
	var touch := TouchGestureRecognizer.new()
	touch.touch(0, true, A)
	_assert_eq(summary(touch.drag(0, A + Vector2(20, 0))),
		["motion %s 0" % A, "left down %s 1" % A, "motion %s 1" % (A + Vector2(20, 0))],
		"moving past the slop presses the left button where the finger landed and drags with it held")
	_assert_eq(summary(touch.drag(0, A + Vector2(40, 0))), ["motion %s 1" % (A + Vector2(40, 0))], "the held drag follows the finger")
	_assert_eq(summary(touch.touch(0, false, A + Vector2(40, 0))), ["left up %s 0" % (A + Vector2(40, 0)), "leave"], "the lift releases")
	touch.touch(0, true, B)
	_assert_eq(touch.advance(0.1), [], "a lone finger is not a press before the hold time")
	_assert_eq(summary(touch.advance(0.06)), ["motion %s 0" % B, "left down %s 1" % B], "held still, it becomes a left press at the touch-down point")
	_assert_eq(summary(touch.touch(0, false, B)), ["left up %s 0" % B, "leave"], "a long press lifted is one ordinary click")


func _two_finger_tap_is_right_only() -> void:
	var touch := TouchGestureRecognizer.new()
	var events := touch.touch(0, true, A)
	events.append_array(touch.advance(0.03))
	events.append_array(touch.touch(1, true, B))
	events.append_array(touch.advance(0.05))
	events.append_array(touch.touch(1, false, B))
	events.append_array(touch.touch(0, false, A))
	var centre := (A + B) * 0.5
	_assert_eq(summary(events), ["motion %s 0" % centre, "right down %s 2" % centre, "right up %s 0" % centre, "leave"],
		"a two-finger tap is one right click at the fingers' centre on the last lift")
	_assert_eq(buttons(events, MOUSE_BUTTON_LEFT), 0, "the first finger of a two-finger tap never presses the left button")
	touch.touch(0, true, A)
	touch.touch(1, true, B)
	touch.advance(0.31)
	touch.touch(1, false, B)
	_assert_eq(summary(touch.touch(0, false, A)), ["leave"], "two fingers held past the tap window click nothing")


func _two_finger_drag_pans() -> void:
	var touch := TouchGestureRecognizer.new()
	var events := touch.touch(0, true, A)
	events.append_array(touch.touch(1, true, B))
	events.append_array(touch.drag(0, A + Vector2(-8, 0)))
	events.append_array(touch.drag(1, B + Vector2(-8, 0)))
	_assert_eq(touch.take_pan(), Vector2.ZERO, "two fingers moved within the slop do not pan yet")
	for step in range(1, 4):
		events.append_array(touch.drag(0, A + Vector2(-8 - 10 * step, 0)))
		events.append_array(touch.drag(1, B + Vector2(-8 - 10 * step, 0)))
	var pan := touch.take_pan()
	check(pan.x > 0.0 and is_zero_approx(pan.y), "fingers moving left grab the map: the camera moves right (%s)" % pan)
	_assert_eq(touch.take_pan(), Vector2.ZERO, "take_pan hands each pan out once")
	events.append_array(touch.touch(1, false, B + Vector2(-38, 0)))
	events.append_array(touch.drag(0, A + Vector2(-60, 0)))
	_assert_eq(touch.take_pan(), Vector2.ZERO, "the pan ends when fewer than two fingers stay down")
	events.append_array(touch.touch(0, false, A + Vector2(-60, 0)))
	_assert_eq(summary(events), ["leave"], "a two-finger drag sends no button or motion, and the finger left over clicks nothing on its lift")


func _late_and_extra_fingers() -> void:
	var touch := TouchGestureRecognizer.new()
	touch.touch(0, true, A)
	var events := touch.advance(0.2)
	events.append_array(touch.touch(1, true, B))
	events.append_array(touch.drag(1, B + Vector2(0, 30)))
	events.append_array(touch.touch(1, false, B + Vector2(0, 30)))
	events.append_array(touch.touch(0, false, A))
	_assert_eq(summary(events), ["motion %s 0" % A, "left down %s 1" % A, "left up %s 0" % A, "leave"],
		"a second finger after the hold time is ignored: the first finger's press is released on its lift, no right click")
	touch.touch(0, true, A)
	touch.touch(1, true, B)
	events = touch.touch(2, true, B + Vector2(30, 0))
	for finger in 3:
		events.append_array(touch.drag(finger, A + Vector2(0, 40 + finger)))
	_assert_eq(touch.take_pan(), Vector2.ZERO, "a third finger stops the gesture: no pan")
	for finger in 3:
		events.append_array(touch.touch(finger, false, A))
	_assert_eq(summary(events), ["leave"], "three fingers click nothing")
	_assert_eq(summary(touch.touch(5, true, A) + touch.touch(5, false, A)).size(), 4, "with every finger up the next touch starts afresh and taps")


func _stuck_buttons_released() -> void:
	var touch := TouchGestureRecognizer.new()
	touch.touch(0, true, A)
	touch.advance(0.2)
	_assert_eq(summary(touch.touch(0, false, A, true)), ["left up %s 0" % A, "leave"], "a canceled touch releases the held left button")
	touch.touch(0, true, A)
	touch.drag(0, A + Vector2(30, 0))
	_assert_eq(summary(touch.touch(0, true, B)), ["left up %s 0" % (A + Vector2(30, 0)), "leave"],
		"a finger landing again without its lift resets the gesture and releases the held button")
	_assert_eq(summary(touch.reset()), ["leave"], "a reset (focus lost) drops the fingers")
	_assert_eq(touch.reset(), [], "a reset with nothing down sends nothing")


func _desktop_stays_off() -> void:
	if DisplayServer.is_touchscreen_available():
		return
	var controls: Node = root.get_node_or_null("TouchControls")
	check(controls != null, "the TouchControls autoload is installed")
	if controls == null:
		return
	check(not controls.enabled and not controls.is_processing() and not controls.is_processing_input(),
		"without a touchscreen TouchControls processes nothing")
	check(Input.emulate_mouse_from_touch, "without a touchscreen Godot's own touch emulation is left as it is")
	_assert_eq(controls.take_pan(), Vector2.ZERO, "without a touchscreen there is no pan")

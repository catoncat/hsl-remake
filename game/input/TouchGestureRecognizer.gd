extends RefCounted
## Touch gestures as pure logic: finger touches and drags in, mouse events and a camera pan out.
## TouchControls feeds it the window's touches and turns its events into InputEvents;
## tests/run_touch_gesture_tests.gd drives it with a hand clock. Positions are logical pixels
## (the 640×480 picture); the caller passes each frame's delta to advance().
##
## One finger sends nothing when it lands. The first of these decides what it is:
##   - a second finger lands: a two-finger gesture, and the first finger never clicks;
##   - the finger lifts having moved less than TAP_SLOP: a tap — motion, left press and left
##     release at the touch-down point, all on the lift;
##   - the finger moves TAP_SLOP or stays down HOLD_SECONDS: a left hold — motion and left press
##     at the touch-down point, then motion that follows the finger and the release on its lift.
## Two fingers both lifted within TWO_FINGER_TAP_SECONDS of the first touch, the pair's centre
## moved less than TAP_SLOP: a right click at that centre. Once the centre moves TAP_SLOP the
## pair pans the camera (take_pan) until fewer than two fingers stay down.
## Anything else — a third finger, a finger after the gesture is decided, the fingers left over
## after a pan or a hold — is ignored until every finger is up. A held button is always
## released, and the last finger's lift ends every gesture with a "leave" event.
##
## Events are dictionaries: {kind: "motion", position, mask}, {kind: "button", button, pressed,
## position, mask} (mask = the mouse buttons held after the event) and {kind: "leave"}.
## provenance:
##   rules: remake-invented (touch gestures; the original is played with mouse and keyboard only)
##   timing: remake-invented (hold and two-finger tap windows)

## Logical pixels a finger (or the two fingers' centre) may move and still tap.
const TAP_SLOP := 12.0
## A finger held this long without a second one becomes a left hold.
const HOLD_SECONDS := 0.15
## Both fingers of a two-finger tap lift within this many seconds of the first touch.
const TWO_FINGER_TAP_SECONDS := 0.30
## Camera offset per logical pixel the two fingers move: −1 grabs the map (fingers move left,
## the map follows them left, the camera moves right); +1 pushes the view the other way.
const PAN_DIRECTION := -1.0

enum Phase { IDLE, PENDING, LEFT_HELD, TWO_FINGER, PANNING, IGNORED }

var phase := Phase.IDLE
## Every finger down: index → its latest position.
var _down := {}
var _primary := -1
var _origin := Vector2.ZERO
## Seconds since the first finger landed.
var _clock := 0.0
var _pair: Array = []
var _centre_start := Vector2.ZERO
var _centre_last := Vector2.ZERO
var _tap_alive := false
## Where the finger left over from a two-finger tap stood when its partner lifted.
var _lone_anchor := Vector2.ZERO
var _pan := Vector2.ZERO
## Mouse buttons this recognizer holds down (MouseButtonMask bits) and the pointer it last sent.
var _mask := 0
var _pointer := Vector2.ZERO


func touch(index: int, pressed: bool, position: Vector2, canceled := false) -> Array:
	var events: Array = []
	if pressed:
		if _down.has(index):
			# The platform lost this finger's lift: whatever was going on is over.
			events.append_array(reset())
		_down[index] = position
		match phase:
			Phase.IDLE:
				phase = Phase.PENDING
				_primary = index
				_origin = position
				_clock = 0.0
			Phase.PENDING:
				phase = Phase.TWO_FINGER
				_pair = [_primary, index]
				_centre_start = _centre()
				_centre_last = _centre_start
				_tap_alive = true
			Phase.TWO_FINGER, Phase.PANNING:
				phase = Phase.IGNORED
		return events
	if not _down.has(index):
		return events
	_down.erase(index)
	match phase:
		Phase.PENDING:
			if not canceled:
				if position.distance_to(_origin) < TAP_SLOP:
					events.append_array([_motion(_origin), _button(MOUSE_BUTTON_LEFT, true, _origin), _button(MOUSE_BUTTON_LEFT, false, _origin)])
				else:
					events.append_array([_motion(_origin), _button(MOUSE_BUTTON_LEFT, true, _origin), _motion(position), _button(MOUSE_BUTTON_LEFT, false, position)])
			phase = Phase.IGNORED
		Phase.LEFT_HELD:
			if index == _primary:
				if position != _pointer:
					events.append(_motion(position))
				events.append(_button(MOUSE_BUTTON_LEFT, false, position))
				phase = Phase.IGNORED
		Phase.TWO_FINGER:
			if canceled:
				_tap_alive = false
			var left := _pair.filter(func(finger: int) -> bool: return _down.has(finger))
			if left.size() == 1:
				_lone_anchor = _down[left[0]]
			elif left.is_empty():
				if _tap_alive and _clock <= TWO_FINGER_TAP_SECONDS:
					events.append_array([_motion(_centre_last), _button(MOUSE_BUTTON_RIGHT, true, _centre_last), _button(MOUSE_BUTTON_RIGHT, false, _centre_last)])
				phase = Phase.IGNORED
		Phase.PANNING:
			if _pair.has(index):
				phase = Phase.IGNORED
	if _down.is_empty():
		events.append_array(_release_held())
		events.append({"kind": "leave"})
		_restart()
	return events


func drag(index: int, position: Vector2) -> Array:
	var events: Array = []
	if not _down.has(index):
		return events
	_down[index] = position
	match phase:
		Phase.PENDING:
			if position.distance_to(_origin) >= TAP_SLOP:
				events.append_array(_start_hold())
		Phase.LEFT_HELD:
			if index == _primary and position != _pointer:
				events.append(_motion(position))
		Phase.TWO_FINGER:
			if _pair.all(func(finger: int) -> bool: return _down.has(finger)):
				var centre := _centre()
				if centre.distance_to(_centre_start) >= TAP_SLOP:
					# The pan starts from here: the map does not jump by the slop.
					phase = Phase.PANNING
					_tap_alive = false
				_centre_last = centre
			elif _pair.has(index) and position.distance_to(_lone_anchor) >= TAP_SLOP:
				_tap_alive = false
		Phase.PANNING:
			if _pair.has(index) and _pair.all(func(finger: int) -> bool: return _down.has(finger)):
				var centre := _centre()
				_pan += (centre - _centre_last) * PAN_DIRECTION
				_centre_last = centre
	return events


## Steps the clock: a lone finger held HOLD_SECONDS becomes a left hold.
func advance(delta: float) -> Array:
	if phase == Phase.IDLE:
		return []
	_clock += maxf(delta, 0.0)
	if phase == Phase.PENDING and _clock >= HOLD_SECONDS:
		return _start_hold()
	return []


## The camera offset (logical pixels) the two-finger pan asked for since the last call.
func take_pan() -> Vector2:
	var pan := _pan
	_pan = Vector2.ZERO
	return pan


## Drops every finger and releases what is held (focus lost, a lost lift).
func reset() -> Array:
	var events := _release_held()
	if not _down.is_empty() or not events.is_empty():
		events.append({"kind": "leave"})
	_down.clear()
	_restart()
	return events


func _start_hold() -> Array:
	phase = Phase.LEFT_HELD
	var events: Array = [_motion(_origin), _button(MOUSE_BUTTON_LEFT, true, _origin)]
	var at: Vector2 = _down[_primary]
	if at != _origin:
		events.append(_motion(at))
	return events


func _release_held() -> Array:
	var events: Array = []
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if _mask & _bit(button):
			events.append(_button(button, false, _pointer))
	return events


func _restart() -> void:
	phase = Phase.IDLE
	_primary = -1
	_pair = []
	_tap_alive = false
	_clock = 0.0


func _centre() -> Vector2:
	return (_down[_pair[0]] + _down[_pair[1]]) * 0.5


func _motion(position: Vector2) -> Dictionary:
	_pointer = position
	return {"kind": "motion", "position": position, "mask": _mask}


func _button(button: int, pressed: bool, position: Vector2) -> Dictionary:
	_pointer = position
	_mask = (_mask | _bit(button)) if pressed else (_mask & ~_bit(button))
	return {"kind": "button", "button": button, "pressed": pressed, "position": position, "mask": _mask}


static func _bit(button: int) -> int:
	return 1 << (button - 1)

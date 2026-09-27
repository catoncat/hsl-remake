extends RefCounted
## Native integer tables and frame order. Availability remains in PlayLoop.
## provenance:
##   rules: static-derived content/imported/hsl/shared/command_menu/native_layout.json
##   rules: static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md
##   layout: static-derived content/imported/hsl/shared/command_menu/native_layout.json
##   timing: static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
const SOURCE := "res://content/imported/hsl/shared/command_menu/native_layout.json"
static var _source: Dictionary = {}


static func data() -> Dictionary:
	if _source.is_empty():
		_source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	return _source


static func centers(count: int) -> Array[Vector2]:
	assert(count >= 1 and count <= 10)
	var source := data()
	var step := 256 / count + (1 if count == 6 else 0)
	var mask := 248 if count == 7 else 255
	var result: Array[Vector2] = []
	for i in range(count):
		var index := ((192 - i * step) & 255) & mask
		result.append(Vector2((int(source["tables"]["x"][index]) * 66) >> 16, (int(source["tables"]["y"][index]) * 72) >> 16))
	return result


static func frame_at(frame_count: int, updates: int, looped: bool) -> int:
	assert(frame_count > 0)
	var advances := maxi(0, updates) / int(data()["hover_delay_calls"])
	if looped or frame_count == 1:
		return advances % frame_count
	# 0x45e5d9 reverses direction without duplicating the endpoint frames.
	var cycle := 2 * (frame_count - 1)
	var phase := advances % cycle
	return phase if phase < frame_count else cycle - phase


## One call of the native slide helper 0x45e80d: it halves each signed distance (SAR),
## clamps it to ±max_step, and snaps only when BOTH axes are within tolerance. The menu
## (0x43e72a..0x43e73b) calls it with tolerance 2, step 8; the ANIMAL cast lead
## (aniMoveToCenter 0x402771 and the cast-object slides 0x402ac9／0x402d27) with 16, 32.
## This is an update count, not seconds.
static func opening_step(current: Vector2i, target: Vector2i, tolerance: int = 2, max_step: int = 8) -> Vector2i:
	var difference := target - current
	if absi(difference.x) <= tolerance and absi(difference.y) <= tolerance:
		return target
	return current + Vector2i(clampi(difference.x >> 1, -max_step, max_step), clampi(difference.y >> 1, -max_step, max_step))

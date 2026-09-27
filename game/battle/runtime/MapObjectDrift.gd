extends Node
## Motion of the stand objects whose obj_Data9 moves them (defProcStandObject 0x43ccf0):
## mapobjCloud drifts every original tick at its obj_Data7 angle／obj_Data8 speed and wraps
## around the map; mapobjMoveBG follows the camera by obj_Score/640 and obj_HitPoint/480
## (−1 pins it to the view). Works on the original object point (the EVEF anchor); a sprite
## draws at point − its SHP draw origin. Presentation only, no battle state.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (0x43d7e0 wrap by map size + picture size; 0x43d4c1 camera parallax)
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (wraps and parallax samples of levels 1／2／6／53)
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##     (obj_Data7／obj_Data8／obj_Score／obj_HitPoint)
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (0x45eb9d／0x45ebdc 16.16 step per tick)
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (level 1: +265,+265 in 1499 ticks)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: remake-invented
##     (moving backgrounds are placed every display frame from the current camera, the original once per tick before
##     that frame's scroll)
##   timing: provisional
##     (the original hides and holds clouds while [0x4c1b00] & 0x1400000 or its options bit 0x477c14 & 1 is clear; not
##     wired)

const OriginalTick = preload("res://game/common/OriginalTick.gd")

## 0x4a35fc／0x4a39fc: 256-step cos／sin tables, each entry round(·65536).
const ANGLE_STEPS := 256
const FIXED_ONE := 65536
## 0x43d509／0x43d55b: the parallax ratios are obj_Score/640 and obj_HitPoint/480.
const MOVE_BG_X_SPAN := 640
const MOVE_BG_Y_SPAN := 480
const PIN_TO_VIEW := -1

## Map size in pixels: every cloud template leaves obj_X1..Y2 at the 0,0,640,480 default,
## which 0x43ce14 replaces with the map's own size (range X1 = Y1 = 0).
var map_size := Vector2i.ZERO
## View top-left in map pixels (the original's [0x4c091c]／[0x4c0920]).
var camera_top_left: Callable
var clouds: Array[Dictionary] = []
var backgrounds: Array[Dictionary] = []
var _clock := 0.0


func clear() -> void:
	clouds.clear()
	backgrounds.clear()
	_clock = 0.0


## 0x45eb9d: velocity in 1/65536 px per tick from an angle (0 right, 64 down) and a 16.16 speed.
static func velocity(angle: int, speed: int) -> Vector2i:
	var turn := TAU * float(posmod(angle, ANGLE_STEPS)) / float(ANGLE_STEPS)
	var c := int(round(cos(turn) * FIXED_ONE))
	var s := int(round(sin(turn) * FIXED_ONE))
	return Vector2i((c * speed) >> 16, (s * speed) >> 16)


static func field_int(value: String) -> int:
	return value.hex_to_int() if value.begins_with("0x") or value.begins_with("-0x") else value.to_int()


## A cloud starts at its EVEF point with both fractions 0; `size` and `origin` are the
## SHP frame's width／height and draw origin (0x4606a9 descriptor).
func add_cloud(sprite: Node2D, point: Vector2, angle: int, speed: int, size: Vector2i, origin: Vector2i) -> void:
	clouds.append({"sprite": sprite, "x": int(point.x), "y": int(point.y), "fx": 0, "fy": 0,
		"v": velocity(angle, speed), "size": size, "origin": origin})


func add_background(sprite: Node2D, point: Vector2, score: int, hit_point: int, origin: Vector2i) -> void:
	backgrounds.append({"sprite": sprite, "x0": int(point.x), "y0": int(point.y), "x": int(point.x), "y": int(point.y),
		"score": score, "hit_point": hit_point, "origin": origin})
	_place_background(backgrounds.back())


func _process(delta: float) -> void:
	if not clouds.is_empty():
		_clock += delta
		var steps := floori(_clock / OriginalTick.TICK_SECONDS)
		if steps > 0:
			_clock -= float(steps) * OriginalTick.TICK_SECONDS
			for cloud in clouds:
				for _i in steps:
					step_cloud(cloud, map_size)
				_draw_cloud(cloud)
	for background in backgrounds:
		_place_background(background)


## One tick of 0x45ebdc plus the wrap 0x43d7e0..0x43d848: the fraction keeps the low 16
## bits, the whole pixels move the point; a picture wholly past one map edge re-enters
## just outside the opposite one (period map size + picture size, per axis).
static func step_cloud(cloud: Dictionary, map_pixels: Vector2i) -> void:
	var v: Vector2i = cloud["v"]
	var size: Vector2i = cloud["size"]
	var origin: Vector2i = cloud["origin"]
	var sum_x: int = v.x + int(cloud["fx"])
	var sum_y: int = v.y + int(cloud["fy"])
	cloud["fx"] = sum_x & 0xFFFF
	cloud["fy"] = sum_y & 0xFFFF
	cloud["x"] = _wrap(int(cloud["x"]) + (sum_x >> 16), map_pixels.x, size.x, origin.x)
	cloud["y"] = _wrap(int(cloud["y"]) + (sum_y >> 16), map_pixels.y, size.y, origin.y)


static func _wrap(point: int, span: int, extent: int, origin: int) -> int:
	if point > span + origin:
		return point - span - extent
	if point < -extent + origin:
		return point + span + extent
	return point


func _draw_cloud(cloud: Dictionary) -> void:
	var sprite: Node2D = cloud["sprite"]
	var origin: Vector2i = cloud["origin"]
	sprite.position = Vector2(int(cloud["x"]) - origin.x, int(cloud["y"]) - origin.y)
	# The remake orders stand objects by their point's y (BattleSceneStage).
	sprite.z_index = int(cloud["y"])


## 0x43d4c1: x = x0 + trunc((camX − x0)·score / 640) (−1: camX; 0: stays), y alike / 480.
func _place_background(background: Dictionary) -> void:
	var view := Vector2i(camera_top_left.call()) if camera_top_left.is_valid() else Vector2i.ZERO
	background["x"] = _follow(int(background["x"]), int(background["x0"]), view.x, int(background["score"]), MOVE_BG_X_SPAN)
	background["y"] = _follow(int(background["y"]), int(background["y0"]), view.y, int(background["hit_point"]), MOVE_BG_Y_SPAN)
	var origin: Vector2i = background["origin"]
	(background["sprite"] as Node2D).position = Vector2(int(background["x"]) - origin.x, int(background["y"]) - origin.y)


static func _follow(current: int, start: int, view: int, ratio: int, span: int) -> int:
	if ratio == PIN_TO_VIEW:
		return view
	if ratio == 0:
		return current
	# GDScript int division truncates toward zero, as the original's sign fix does.
	return start + (view - start) * ratio / span

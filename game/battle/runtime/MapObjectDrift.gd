extends Node
## Motion of the stand objects whose obj_Data9 moves them (defProcStandObject 0x43ccf0):
## mapobjCloud drifts every original tick at its obj_Data7 angle／obj_Data8 speed and wraps
## around the map; mapobjMoveBG follows the camera by obj_Score/640 and obj_HitPoint/480
## (−1 pins it to the view); mapobjWaterFall takes the same parallax from its chain root and
## scrolls by its own picture size. Works on the original object point (the EVEF anchor); a sprite
## draws at point − its SHP draw origin. Presentation only, no battle state.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (0x43d7e0 wrap by map size + picture size; 0x43d4c1 camera parallax; 0x43d13e waterfall)
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (wraps and parallax samples of levels 1／2／6／53)
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##     (obj_Data7／obj_Data8／obj_Score／obj_HitPoint)
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (0x45eb9d／0x45ebdc 16.16 step per tick; 0x43ceba hold on 0x4c1b00 & 0x1400000 or 場景效果 off;
##     0x43d13e／0x43d758 likewise)
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (level 1: +265,+265 in 1499 ticks)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: provisional
##     (0x1400000 read as a busy cut-in queue or the open status panel; scroll order not read)

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")

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
## True while the original would hide the clouds: 0x43ceba writes the hold counter +0xae = 2 while
## [0x4c1b00] & 0x1400000 (map magic effect 0x1000000, close-up／status window 0x400000) or while
## [0x477c14] bit0 (設定選項 場景效果) is clear. Moving backgrounds jump past it (0x43d573).
var clouds_hidden: Callable
## True while 設定選項 場景效果 is off: mapobjWaterFall (0x43d13e) and mapobjBuildBottom
## (0x43d758) write the same hold counter on [0x477c14] bit0 clear, so they neither draw nor
## move.
var scene_hidden: Callable
## True while a close-up or the status window is up ([0x4c1b00] & 0x400000): mapobjBuildBottom
## (0x43d758) tests it before 場景效果 and holds the same way; the map magic bit 0x1000000 is
## not tested there.
var close_up_hidden: Callable
var clouds: Array[Dictionary] = []
## The stand objects held only by 場景效果 (waterfalls, building bottoms); the remake draws
## them still, so a hold is just not drawing.
var scene_held: Array[Node2D] = []
## The building bottoms among scene_held, also held by close_up_hidden.
var close_up_held: Array[Node2D] = []
var backgrounds: Array[Dictionary] = []
## mapobjWaterFall (0x43d07b init, 0x43d13e tick): camera parallax like a moving background but
## measured from its chain root, plus a scroll offset stepped at obj_Data7／obj_Data8 and wrapped
## by the picture's own width／height.
var waterfalls: Array[Dictionary] = []
var _clock := 0.0


func clear() -> void:
	clouds.clear()
	backgrounds.clear()
	waterfalls.clear()
	scene_held.clear()
	close_up_held.clear()
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


func add_scene_held(sprite: Node2D, on_close_up := false) -> void:
	scene_held.append(sprite)
	if on_close_up:
		close_up_held.append(sprite)
	sprite.visible = not (scene_hidden.is_valid() and bool(scene_hidden.call())) \
		and not (on_close_up and close_up_hidden.is_valid() and bool(close_up_hidden.call()))


## 0x43d07b: x0／y0 = its own point (+0x4a／+0x48); the root (0x45ef11: up the combined chain to
## its head, else itself) point clamped to ≥ 0 (+0x92／+0x90); offsets +0x46／+0x44 = 0;
## wrap spans = the frame width／height (0x4606a9 → +0x70／+0x74). Also held by 場景效果 off.
func add_waterfall(sprite: Node2D, point: Vector2, root: Vector2, score: int, hit_point: int, angle: int, speed: int, size: Vector2i, origin: Vector2i) -> void:
	waterfalls.append({"sprite": sprite, "x0": int(point.x), "y0": int(point.y), "x": int(point.x), "y": int(point.y),
		"rx": maxi(int(root.x), 0), "ry": maxi(int(root.y), 0), "score": score, "hit_point": hit_point,
		"v": velocity(angle, speed), "fx": 0, "fy": 0, "ox": 0, "oy": 0, "size": size, "origin": origin})
	add_scene_held(sprite)
	_draw_waterfall(waterfalls.back())


func add_background(sprite: Node2D, point: Vector2, score: int, hit_point: int, origin: Vector2i) -> void:
	backgrounds.append({"sprite": sprite, "x0": int(point.x), "y0": int(point.y), "x": int(point.x), "y": int(point.y),
		"score": score, "hit_point": hit_point, "origin": origin})
	_place_background(backgrounds.back())


## Once per original tick like the object executor 0x45f5f7: a cloud steps unless held; a held
## cloud (0x43d76a: counter still non-zero → 0x43d202 sets +0x80 0x10000000, which 0x45f716 skips
## drawing) keeps its point and fractions and walks on from there the first tick the condition is
## gone; a moving background takes the camera of that tick.
func _process(delta: float) -> void:
	if clouds.is_empty() and backgrounds.is_empty() and scene_held.is_empty() and waterfalls.is_empty():
		return
	_clock += delta
	var steps := floori(_clock / OriginalTick.TICK_SECONDS)
	if steps <= 0:
		return
	_clock -= float(steps) * OriginalTick.TICK_SECONDS
	var hidden := clouds_hidden.is_valid() and bool(clouds_hidden.call())
	for cloud in clouds:
		(cloud["sprite"] as Node2D).visible = not hidden
		if hidden:
			continue
		for _i in steps:
			step_cloud(cloud, map_size)
		_draw_cloud(cloud)
	for background in backgrounds:
		_place_background(background)
	var scene_off := scene_hidden.is_valid() and bool(scene_hidden.call())
	var view := Vector2i(camera_top_left.call()) if camera_top_left.is_valid() else Vector2i.ZERO
	for waterfall in waterfalls:
		for _i in steps:
			step_waterfall(waterfall, view, scene_off)
		_draw_waterfall(waterfall)
	var close_up_off := close_up_hidden.is_valid() and bool(close_up_hidden.call())
	for sprite in scene_held:
		if is_instance_valid(sprite):
			sprite.visible = not scene_off and not (close_up_off and close_up_held.has(sprite))


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
	# A y-sorted stand object's bucket follows its point (0x43ccf0); an ATTACKFLAG one keeps
	# its fixed obj_Plane depth (ActorRuntime.apply_object_depth).
	if not sprite.has_meta("depth_plane"):
		sprite.z_index = ActorRuntime.stand_object_z(float(cloud["y"]), int(sprite.get_meta("stand_plane", ActorRuntime.PLANE_OBJECT1)))


## One tick of 0x43d13e..0x43d28a: the parallax runs even while held (0x43d150..0x43d1e6:
## x = x0 + trunc((camX − rootX)·score / 640), −1: camX, 0: x kept; y alike / 480); unheld, the
## 16.16 step 0x45ebdc moves the offsets, each wrapped once (> span: − span; < 0: + span), and
## the point adds the whole offset (0x43d275..0x43d28a).
static func step_waterfall(waterfall: Dictionary, view: Vector2i, held: bool) -> void:
	var score := int(waterfall["score"])
	var hit_point := int(waterfall["hit_point"])
	if score != 0:
		waterfall["x"] = view.x if score == PIN_TO_VIEW else int(waterfall["x0"]) + (view.x - int(waterfall["rx"])) * score / MOVE_BG_X_SPAN
	if hit_point != 0:
		waterfall["y"] = view.y if hit_point == PIN_TO_VIEW else int(waterfall["y0"]) + (view.y - int(waterfall["ry"])) * hit_point / MOVE_BG_Y_SPAN
	if held:
		return
	var v: Vector2i = waterfall["v"]
	var size: Vector2i = waterfall["size"]
	var sum_x: int = v.x + int(waterfall["fx"])
	var sum_y: int = v.y + int(waterfall["fy"])
	waterfall["fx"] = sum_x & 0xFFFF
	waterfall["fy"] = sum_y & 0xFFFF
	waterfall["ox"] = _wrap_offset(int(waterfall["ox"]) + (sum_x >> 16), size.x)
	waterfall["oy"] = _wrap_offset(int(waterfall["oy"]) + (sum_y >> 16), size.y)
	waterfall["x"] = int(waterfall["x"]) + int(waterfall["ox"])
	waterfall["y"] = int(waterfall["y"]) + int(waterfall["oy"])


static func _wrap_offset(offset: int, span: int) -> int:
	if offset > span:
		return offset - span
	if offset < 0:
		return offset + span
	return offset


func _draw_waterfall(waterfall: Dictionary) -> void:
	var origin: Vector2i = waterfall["origin"]
	(waterfall["sprite"] as Node2D).position = Vector2(int(waterfall["x"]) - origin.x, int(waterfall["y"]) - origin.y)


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

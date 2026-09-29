extends Node2D
## mapobjDropRain (original_story_rain.md): the 降雨BOSS stand object's timer (0x43d578) and the
## defProcDropRain drops it spawns (0x43c4a0), stepped per original tick.
##
## Boss, every tick: timer −1; at ≤ 0 it reloads rand(|lo − hi + 1|) + hi from its obj_Data3
## words (lo +0x94, hi +0x96) and, while fewer than 400 objects live, spawns one obj_Data4 drop —
## level 10 every 2–4 ticks, level 12 every 2–3. The boss itself is never drawn (+0x30 = 0xffff).
## Drop, first call: a random frame of its run, kept for life; speed rand(Data4 − Data3) + Data3
## (16.16 px a tick); angle (rand(Data6 − Data5 + 1) + Data5) & 0xff (0 right, 64 down); landing
## point x = r + camX + 320 with r folded from rand(2·(hi(Data7) + 576)) into ±(hi(Data7) + 576),
## y alike from lo(Data7) + 400 around camY + 240; the start is the landing point pushed back
## 80 ticks along angle + 128 (0x45eaa3 on speed·80). Every tick, the same call included: step
## (0x45ebdc), engADDCOLOR_MIX level +1 up to 16 then plain add; after 80 steps level 14 counting
## down one a tick, deleted at 0. Depth +0xc = max(0x4300f0(slot), 5): the slot is the landing y
## on the first call and afterwards the stack word the previous drop's step left (its dy), so
## bucket 5 once falling. Every call also reads 場景效果 ([0x477c14] bit0, 0x43c63f): clear, the
## drop is not drawn (+0x30 = 0xffff) but keeps stepping, so switching it mid-story hides or shows
## the rain at once where it has fallen to.
## Landing (0x43c6ac..0x43c735): on a map word with 0x8000 (0x43dec0; off the map is not water) the
## drop leaves global.obs 698 Wave_Up and 699 Wave_Up2 (defProcWaterWave 0x43c3f0) at its point,
## +0xc copied from the drop. planeEffect4 runs before the drops' planeEffect6, so a wave's first
## call is the next tick: engADDCOLOR_ZOOM, scale 0.5, +0xc ± 1 (obj_Data7); then scale +0xc00
## a tick, full add for 18 ticks (+0x7c), engMIX from level 16 down one a tick, deleted at 0. The
## creation tick is not drawn (+0x80 0x10000000); the wave reads neither 場景效果 nor the close-up
## bit, so it stays drawn while the drops are hidden.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_story_rain.md
##     (own words; the original's global stream 0x4795d4 is PlayLoop's global_rng, AI／script rolls)
##   layout: static-derived docs/evidence_packets/static_reverse/original_story_rain.md
##   layout: resource-derived content/imported/hsl/chapter01/battle010/map_objects.json
##   layout: resource-derived content/imported/hsl/shared/first_skill/global.obs (698／699)
##   layout: provisional
##     (the 400 cap counts this emitter's drops and waves; a tick's first stale slot is this
##     emitter's last dy — see the packet's 边界)
##   timing: static-derived docs/evidence_packets/static_reverse/original_story_rain.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const AdditiveLevelBlend = preload("res://game/battle/scene/AdditiveLevelBlend.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const WAVE_MANIFEST := "res://content/imported/hsl/shared/skill_effects/manifest.json"

## 0x4a35fc／0x4a39fc: 256-step cos／sin tables, each entry round(·65536).
const ANGLE_STEPS := 256
const FIXED_ONE := 65536
## 0x43d5d0: a drop spawns only while [0x4a19dc] (live objects) < 0x190.
const OBJECT_CAP := 400
## 0x43c557／0x43c55d: half widths added to the drop's obj_Data7 words; 0x43c57f／0x43c5ae: the
## view centre offsets from the camera's top-left.
const BAND_HALF := Vector2i(0x240, 0x190)
const VIEW_CENTRE := Vector2i(0x140, 0xf0)
## 0x43c5c8: +0xa8 = 0x50 falling ticks; 0x43c6dc: +0x28 = 14 fading ticks after.
const FALL_TICKS := 0x50
const FADE_LEVEL := 14
const MIX_LEVELS := 16
## 0x43c61e: the depth bucket is at least 5.
const MIN_BUCKET := 5
## The emitters' shared state words for 0x458c10／0x458c80. The original draws the global stream
## 0x4795d4／0x4795d8; the remake's global stream is PlayLoop's clock-seeded, unsaved global_rng,
## which AI, reinforcement and script rolls draw — rain drawing it would shift those rolls, so the
## presentation keeps its own words (seed kept from the remake's former rain RNG).
const SEED := 10
## global.obs 698 Wave_Up／699 Wave_Up2 (0x43c6f7／0x43c71c): shape, obj_Data7 plane modify; both
## planeEffect4, obj_Shape_Delay 18 (+0x7c), obj_Data6 zoom step 0x00000c00 (+0xa0).
const WAVES := [["MAGIC\\WAVEUP001.SHP", -1], ["MAGIC\\WAVEUP002.SHP", 1]]
const WAVE_PLANE := "planeEffect4"
const WAVE_DELAY := 18
const WAVE_ZOOM_STEP := 0x0c00
## 0x43c414: +0x20 = +0x24 = 0x8000 (16.16 zoom 0.5); 0x43c47c: +0x28 = 16 when engMIX is set.
const WAVE_ZOOM_START := 0x8000
## 0x46c091 &／0x43dec0: the map word bit a wave needs.
const WATER_BIT := 0x8000

var camera_top_left: Callable
## [0x4c1b00] & 0x400000 (close-up or status window): the drops are not drawn but keep falling.
var close_up_hidden: Callable
## (world pixel: Vector2i) -> bool, the map word under it & 0x8000; off the map false (0x43dec0).
var is_water: Callable
var wave_textures: Array[Texture2D] = []
var wave_origins: Array = []
var wave_plane := ActorRuntime.plane_number(WAVE_PLANE)
var waves: Array[Dictionary] = []
## Shared across a scene's emitters ({"state": [w0, w1]}), as the original's bosses share one stream.
var stream: Dictionary = {}
var textures: Array[Texture2D] = []
var origins: Array = []
var plane := ActorRuntime.PLANE_OBJECT1
var interval_low := 2
var interval_high := 2
var speed_min := 0
var speed_span := 0
var angle_min := 0
var angle_span := 1
var band_half := BAND_HALF
var drops: Array[Dictionary] = []
## Boss +0x50: 0 at the first call, which spawns at once.
var _timer := 0
## The stack word 0x4300f0 reads after a drop's first call (the last stepped drop's dy).
var _slot := 0
var _clock := 0.0


static func new_stream() -> Dictionary:
	return {"state": [SEED, SEED ^ 0xe54a231c]}


## boss_data3: the boss's obj_Data3 (lo word, hi word); drop_spec: the obj_Data4 template.
func configure(drop_spec: Dictionary, boss_data3: String, shared_stream: Dictionary) -> void:
	stream = shared_stream
	for frame in drop_spec.get("frames", [drop_spec.get("preview", "")]):
		textures.append(load(str(frame)))
	origins = drop_spec.get("frame_draw_origins", [drop_spec.get("draw_origin", [0, 0])])
	plane = ActorRuntime.plane_number(str(drop_spec.get("plane", "")))
	var fields: Dictionary = drop_spec.get("object_fields", {})
	var words := _field(boss_data3)
	var lo := words & 0xFFFF
	var hi := (words >> 16) & 0xFFFF
	interval_low = hi
	interval_high = hi + absi(lo - hi + 1) - 1
	var data3 := _field(str(fields.get("obj_Data3", "")))
	speed_min = data3
	speed_span = _field(str(fields.get("obj_Data4", ""))) - data3
	angle_min = _field(str(fields.get("obj_Data5", "")))
	angle_span = _field(str(fields.get("obj_Data6", ""))) - angle_min + 1
	var data7 := _field(str(fields.get("obj_Data7", "")))
	band_half = BAND_HALF + Vector2i(_signed16(data7 >> 16), _signed16(data7))
	var frames := _wave_frames()
	for wave in WAVES:
		var entry: Dictionary = frames.get(str(wave[0]), {})
		wave_textures.append(load(str(entry["res_path"])) if not entry.is_empty() else null)
		wave_origins.append(entry.get("draw_origin", [0, 0]))


static var _wave_frame_cache: Dictionary = {}


static func _wave_frames() -> Dictionary:
	if _wave_frame_cache.is_empty():
		var parsed: Variant = ContentPaths.read_json(WAVE_MANIFEST)
		_wave_frame_cache = (parsed as Dictionary).get("frames", {}) if parsed is Dictionary else {}
	return _wave_frame_cache


static func _field(token: String) -> int:
	if token == "":
		return 0
	return token.hex_to_int() if token.begins_with("0x") else token.to_int()


static func _signed16(word: int) -> int:
	var value := word & 0xFFFF
	return value - 0x10000 if value >= 0x8000 else value


static func cos_tab(angle: int) -> int:
	return int(round(cos(TAU * float(posmod(angle, ANGLE_STEPS)) / ANGLE_STEPS) * FIXED_ONE))


static func sin_tab(angle: int) -> int:
	return int(round(sin(TAU * float(posmod(angle, ANGLE_STEPS)) / ANGLE_STEPS) * FIXED_ONE))


static func _signed32(value: int) -> int:
	var word := value & 0xFFFFFFFF
	return word - 0x100000000 if word >= 0x80000000 else word


## 0x45eaa3: whole pixels of dist (16.16) along angle — (table·dist) bits 16..47, then sar 16.
static func push_back(angle: int, dist: int) -> Vector2i:
	return Vector2i(_signed32((cos_tab(angle) * dist) >> 16) >> 16, _signed32((sin_tab(angle) * dist) >> 16) >> 16)


func _rand(bound: int) -> int:
	var step := DamageRandomStream.rand(stream["state"], bound)
	stream["state"] = step["state"]
	return int(step["value"])


## 0x43c57f／0x43c5ae: r in [0, 2·half) folded to (−half, half].
func _band(half: int) -> int:
	var r := _rand(2 * half)
	return r - 2 * half if r > half else r


func _process(delta: float) -> void:
	if textures.is_empty():
		return
	_clock += delta
	var steps := floori(_clock / OriginalTick.TICK_SECONDS)
	if steps <= 0:
		return
	_clock -= float(steps) * OriginalTick.TICK_SECONDS
	var hidden := (close_up_hidden.is_valid() and bool(close_up_hidden.call())) or not GameSettings.scene_effects_enabled()
	for _i in steps:
		tick()
	for drop in drops:
		var sprite: Sprite2D = drop["sprite"]
		sprite.visible = not hidden
		sprite.position = Vector2(int(drop["x"]), int(drop["y"]))
		sprite.modulate.a = AdditiveLevelBlend.alpha(int(drop["level"]))
		# The drop's bucket is at most 23 (0x4300f0 caps a row at 19, + 4) and a cast-lifted unit's
		# 27..46, so the rain stays under the CAST_LIFT_Z band like every y-sorted object.
		sprite.z_index = mini(ActorRuntime.bucket_z(int(drop["bucket"]), plane), ActorRuntime.CAST_LIFT_Z - 2)
	for wave in waves:
		var sprite: Sprite2D = wave["sprite"]
		# 0x45f716: the creation tick's draw is skipped; its first call is the next tick.
		sprite.visible = not bool(wave["first"])
		sprite.position = Vector2(int(wave["x"]), int(wave["y"]))
		var zoom := float(int(wave["zoom"])) / FIXED_ONE
		sprite.scale = Vector2(zoom, zoom)
		sprite.modulate.a = AdditiveLevelBlend.alpha(int(wave["level"])) if bool(wave["mix"]) else 1.0
		sprite.z_index = mini(ActorRuntime.bucket_z(int(wave["bucket"]), wave_plane), ActorRuntime.CAST_LIFT_Z - 2)


## One original tick in 0x45f5f7's plane order: the boss (planeBG3, 0x43d578), the waves
## (planeEffect4, 0x43c3f0), then every drop in creation order (planeEffect6, 0x43c611..); the
## waves a landing drop leaves join the tail and first run next tick.
func tick() -> void:
	_timer -= 1
	if _timer <= 0:
		_timer = _rand(interval_high - interval_low + 1) + interval_low
		if drops.size() + waves.size() < OBJECT_CAP:
			drops.append(_spawn())
	var kept: Array[Dictionary] = []
	for wave in waves:
		if _step_wave(wave):
			kept.append(wave)
		else:
			(wave["sprite"] as Node).queue_free()
	waves = kept
	var alive: Array[Dictionary] = []
	for drop in drops:
		if _step(drop):
			alive.append(drop)
		else:
			(drop["sprite"] as Node).queue_free()
	drops = alive


## 0x43c4ba..0x43c60e: the drop's first call up to the per-tick part.
func _spawn() -> Dictionary:
	var frame := _rand(textures.size())
	var speed := _rand(speed_span) + speed_min
	var angle := (_rand(angle_span) + angle_min) & 0xFF
	var velocity := Vector2i(_signed32((cos_tab(angle) * speed) >> 16), _signed32((sin_tab(angle) * speed) >> 16))
	var view := Vector2i(camera_top_left.call()) if camera_top_left.is_valid() else Vector2i.ZERO
	var landing := Vector2i(_band(band_half.x), _band(band_half.y)) + view + VIEW_CENTRE
	# 0x45e785 then 0x45e77a: (0x80 − a) then negated, i.e. a + 128.
	var back := push_back((angle + 128) & 0xFF, _signed32(speed * FALL_TICKS))
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.z_as_relative = false
	sprite.texture = textures[frame]
	var origin: Array = origins[frame] if frame < origins.size() else origins[0]
	sprite.offset = -Vector2(float(origin[0]), float(origin[1]))
	sprite.material = AdditiveLevelBlend.material()
	add_child(sprite)
	return {"sprite": sprite, "x": landing.x + back.x, "y": landing.y + back.y, "fx": 0, "fy": 0,
		"v": velocity, "life": FALL_TICKS, "level": 0, "falling": true, "first": true,
		"landing_y": landing.y, "bucket": MIN_BUCKET}


## 0x43c611..0x43c75a: the per-tick part; false once deleted (0x45e3ed).
func _step(drop: Dictionary) -> bool:
	var slot := int(drop["landing_y"]) if bool(drop["first"]) else _slot
	drop["first"] = false
	drop["bucket"] = maxi(ActorRuntime.depth_bucket(float(slot), false), MIN_BUCKET)
	if not bool(drop["falling"]):
		drop["level"] = int(drop["level"]) - 1
		return int(drop["level"]) > 0
	var v: Vector2i = drop["v"]
	var sum_x: int = v.x + int(drop["fx"])
	var sum_y: int = v.y + int(drop["fy"])
	drop["fx"] = sum_x & 0xFFFF
	drop["fy"] = sum_y & 0xFFFF
	drop["x"] = int(drop["x"]) + (sum_x >> 16)
	drop["y"] = int(drop["y"]) + (sum_y >> 16)
	_slot = sum_y >> 16
	if int(drop["level"]) < MIX_LEVELS:
		drop["level"] = int(drop["level"]) + 1
	drop["life"] = int(drop["life"]) - 1
	if int(drop["life"]) <= 0:
		drop["falling"] = false
		drop["level"] = FADE_LEVEL
		if is_water.is_valid() and bool(is_water.call(Vector2i(int(drop["x"]), int(drop["y"])))):
			for index in WAVES.size():
				_add_wave(index, drop)
	return true


## 0x45e307(x, y, 698／699, 0): at the drop's point, +0xc = the drop's (0x43c713／0x43c735).
func _add_wave(index: int, drop: Dictionary) -> void:
	var texture: Texture2D = wave_textures[index] if index < wave_textures.size() else null
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.z_as_relative = false
	sprite.visible = false
	sprite.texture = texture
	var origin: Array = wave_origins[index]
	# 0x461982 scales each segment's offset from the anchor: position = point, offset = −origin.
	sprite.offset = -Vector2(float(origin[0]), float(origin[1]))
	sprite.material = AdditiveLevelBlend.material()
	add_child(sprite)
	waves.append({"sprite": sprite, "x": int(drop["x"]), "y": int(drop["y"]), "bucket": int(drop["bucket"]),
		"modify": int(WAVES[index][1]), "zoom": WAVE_ZOOM_START, "delay": WAVE_DELAY, "fading": false,
		"mix": false, "level": 0, "first": true})


## defProcWaterWave 0x43c3f0..0x43c495; false once deleted (0x45e3ed).
func _step_wave(wave: Dictionary) -> bool:
	if bool(wave["first"]):
		wave["first"] = false
		wave["zoom"] = WAVE_ZOOM_START
		wave["bucket"] = int(wave["bucket"]) + int(wave["modify"])
		return true
	wave["zoom"] = int(wave["zoom"]) + WAVE_ZOOM_STEP
	if not bool(wave["fading"]):
		wave["delay"] = int(wave["delay"]) - 1
		if int(wave["delay"]) <= 0:
			wave["level"] = MIX_LEVELS
			wave["mix"] = true
			wave["fading"] = true
		return true
	wave["level"] = int(wave["level"]) - 1
	return int(wave["level"]) > 0

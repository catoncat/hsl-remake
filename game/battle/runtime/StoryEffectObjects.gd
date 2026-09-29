extends RefCounted
## Story-script effect objects (level 10 帕尼西亞城 廢墟 and later): the readings of an
## inserted object's obj_Process_Code / obj_Mode / obj_Data* fields that the remake acts
## on. Every timing, speed and fade here is a remake presentation choice; the source
## proves only the object fields, insert order and insert points (see the story scene's
## story_objects entries). No battle state: instances live under the runtime's world
## root and free themselves; the coordinator keeps the records (story_records).
##
## Readings (data-driven from the story_objects spec):
##   obj_Data9 mapobjDropRain      -> StoryRainEmitter (0x43d578 timer, 0x43c4a0 drops of the obj_Data4 object)
##   obj_Data9 mapobjPlayBGSound   -> looping background WAV named by obj_Data2
##   obj_Data9 mapobjNextShape     -> looping frame run (火01), additive when engADDCOLOR
##   defProcEffectProcess1 + frames -> one-shot frame run then free (obj_Effect_FireBomb)
##   defProcObjectMove with a native objcomd track (every chapter-1 story object: 閃電 5, 光環 7,
##     白光圈／黑光圈 13, 白光 21／62／151, 徽章 149, 繩子 150, 消失岩石 5; objcomd_motion key
##     symbol@level, level 37 bare) -> the 0x4051d0 track per tick: offset, zoom, engADDCOLOR／
##     engSUBCOLOR, engMIX level, deletion; obj_Plane depth; engRANGE clips at the insert line
##   defProcObjectMove without a track (data-only objects of a new level) + engZOOM／engADDCOLOR*
##     -> fallback flash／glow fading over obj_Data7 ticks
## Anything else keeps the coordinator's plain sprite path.
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
##   layout: remake-invented (flash／glow fallback for defProcObjectMove objects without a native track)
##   layout: provisional
##     (engRANGE blit read as a clip at the insert line — the blit is unread)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived content/generated/hsl/skills/objcomd_motion.json
##   audio: resource-derived content/imported/hsl/chapter01/scripts
##   audio: static-derived docs/evidence_packets/static_reverse/first_battle_audio.md
##     (mapobjPlayBGSound loop at full volume, 0 dB)

const ObjcomdMotion = preload("res://game/battle/scene/ObjcomdMotion.gd")
const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const EffectObjectMotion = preload("res://game/battle/scene/EffectObjectMotion.gd")
const MapObjectAnimation = preload("res://game/battle/runtime/MapObjectAnimation.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const StoryRainEmitter = preload("res://game/battle/runtime/StoryRainEmitter.gd")
## Object ticks (shape_delay, obj_Data7, 16.16 velocities) are original ticks.
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const TICK_SECONDS := OriginalTick.TICK_SECONDS
const DEFAULT_FRAME_TICKS := 3
## Effect planes draw over every actor (planeEffect*); the map is at most 1184 px tall.
const EFFECT_Z := 4000
const FIXED_POINT_ONE := 65536.0

var _counts: Dictionary = {}
## One random state for every rain boss of the scene (the original's bosses share one stream).
var _rain_stream: Dictionary = StoryRainEmitter.new_stream()


static func effect_kind(spec: Dictionary, symbol: String = "", level: int = 0) -> String:
	var fields: Dictionary = spec.get("object_fields", {})
	var data9 := str(fields.get("obj_Data9", ""))
	var mode := str(fields.get("obj_Mode", ""))
	var process := str(spec.get("process", ""))
	var frames: Array = spec.get("frames", [])
	if data9 == "mapobjDropRain":
		return "rain_emitter"
	if data9 == "mapobjPlayBGSound":
		return "background_sound"
	if data9 == "mapobjNextShape" and frames.size() > 1:
		return "frame_loop"
	if process == "defProcEffectProcess1" and frames.size() > 1:
		return "frame_once"
	if process == "defProcObjectMove" and native_track(spec, symbol, level) != "":
		return "objcomd_track"
	if process == "defProcObjectMove" and mode.begins_with("engZOOM"):
		return "flash"
	if process == "defProcObjectMove" and mode.begins_with("engADDCOLOR"):
		return "glow"
	return ""


## The objcomd_motion object whose native track this story object draws: the probe ran
## `symbol@level` (level 37: bare `symbol`) from this level's obj-0xx.obs with the spec's object
## code and obj_Data7 program; "" otherwise.
static func native_track(spec: Dictionary, symbol: String, level: int) -> String:
	if symbol == "" or level <= 0:
		return ""
	var level_obs := "obj-%03d.obs" % level
	for key in ["%s@%03d" % [symbol, level], symbol]:
		if not ObjcomdMotion.tracked(key):
			continue
		var row: Dictionary = ObjcomdMotion.packet()["objects"][key]
		if str(row.get("level_obs", "")).ends_with(level_obs) and int(row["code"]) == int(spec.get("object_code", -1)) \
				and str(row["command_code"]) == str((spec.get("object_fields", {}) as Dictionary).get("obj_Data7", "")):
			return key
	return ""


## The scene's level (the obj-0xx.obs the story objects come from).
static func scene_level(runtime: Node) -> int:
	return int(runtime.first_battle_scenario.get("level", 0)) if runtime != null else 0


static func zoom_of(spec: Dictionary) -> Vector2:
	## obj_ZoomX / obj_ZoomY are 16.16 fixed point (0x00020000 = 2.0).
	var fields: Dictionary = spec.get("object_fields", {})
	var x := _fixed(str(fields.get("obj_ZoomX", "")))
	var y := _fixed(str(fields.get("obj_ZoomY", "")))
	return Vector2(x if x > 0.0 else 1.0, y if y > 0.0 else 1.0)


static func _fixed(token: String) -> float:
	if token == "":
		return 0.0
	return float(token.hex_to_int() if token.begins_with("0x") else token.to_int()) / FIXED_POINT_ONE


static func frame_manifest(spec: Dictionary, frame_ticks: int) -> Dictionary:
	var frames: Array = []
	var textures: Array = spec.get("frames", [spec.get("preview", "")])
	var origins: Array = spec.get("frame_draw_origins", [spec.get("draw_origin", [0, 0])])
	for index in textures.size():
		frames.append({"texture": textures[index], "draw_origin": origins[index] if index < origins.size() else origins[0]})
	return {"frames": frames, "frame_ticks": frame_ticks, "scale": [zoom_of(spec).x, zoom_of(spec).y]}


func insert(runtime: Node, coordinator: Node, spec: Dictionary, all_specs: Dictionary, symbol: String, anchor: Vector2, source_event_id: String) -> Dictionary:
	var level := scene_level(runtime)
	var kind := effect_kind(spec, symbol, level)
	var index := int(_counts.get(symbol, 0)) + 1
	_counts[symbol] = index
	var record := {"kind": "story_object_insert", "source_event_id": source_event_id, "symbol": symbol, "anchor_world": anchor, "effect": kind, "instance": index}
	var fields: Dictionary = spec.get("object_fields", {})
	var frame_ticks := int(spec.get("shape_delay", 0))
	if frame_ticks <= 0:
		frame_ticks = DEFAULT_FRAME_TICKS
	# 設定選項 場景效果 off: visual effects are recorded but not drawn; sounds still play.
	if kind != "background_sound" and not GameSettings.scene_effects_enabled():
		record["status"] = "scene_effects_disabled"
		return record
	match kind:
		"rain_emitter":
			var drop_spec: Dictionary = all_specs.get(str(fields.get("obj_Data4", "")), {})
			if drop_spec.is_empty():
				record["status"] = "rain_object_unbound"
			else:
				var emitter := StoryRainEmitter.new()
				emitter.name = "StoryEffect_%s_%d" % [symbol, index]
				emitter.configure(drop_spec, str(fields.get("obj_Data3", "")), _rain_stream)
				emitter.camera_top_left = func() -> Vector2: return _view_top_left(runtime)
				var stage = runtime.get("stage")
				if stage != null and stage.has_method("_close_up_hidden"):
					emitter.close_up_hidden = Callable(stage, "_close_up_hidden")
				runtime.world_root.add_child(emitter)
				record["drop_symbol"] = str(fields.get("obj_Data4", ""))
				record["spawn_interval_ticks"] = [emitter.interval_low, emitter.interval_high]
		"background_sound":
			record["resource"] = str(fields.get("obj_Data2", ""))
			record["status"] = _start_background_sound(coordinator, str(fields.get("obj_Data2", "")), symbol, index)
		"frame_loop":
			var sprite := MapObjectAnimation.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			sprite.configure(frame_manifest(spec, frame_ticks), anchor)
			if not str(fields.get("obj_Mode", "")).begins_with("engADDCOLOR"):
				sprite.material = null
			ActorRuntime.apply_object_depth(sprite, anchor.y, str(spec.get("plane", "")), false)
			runtime.world_root.add_child(sprite)
		"frame_once":
			var sprite := FrameOnce.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			sprite.configure(frame_manifest(spec, frame_ticks), anchor)
			sprite.z_index = EFFECT_Z
			runtime.world_root.add_child(sprite)
			record["frame_count"] = sprite.frames.size()
		"objcomd_track":
			var sprite := TrackSprite.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			var key := native_track(spec, symbol, level)
			sprite.configure(spec, anchor, key, index - 1)
			# 0x4051d0 never rewrites the depth: obj_Plane (planeObject1 繩子 under 緹娜, planeEffect* over every actor).
			sprite.z_index = EFFECT_Z
			ActorRuntime.apply_object_depth(sprite, anchor.y, str(spec.get("plane", "")), true)
			runtime.world_root.add_child(sprite)
			record["track"] = key
			record["track_frames"] = sprite.frames
		"flash", "glow":
			var sprite := FadeSprite.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			var life_ticks := int(str(fields.get("obj_Data7", "0")).to_int())
			sprite.configure(str(spec.get("preview", "")), spec.get("draw_origin", [0, 0]), anchor, zoom_of(spec), life_ticks, kind == "glow")
			sprite.z_index = EFFECT_Z
			runtime.world_root.add_child(sprite)
			record["life_seconds"] = sprite.life_seconds
		_:
			record["status"] = "no_effect_reading"
	return record


## The camera's top-left in map pixels ([0x4c091c]／[0x4c0920]).
static func _view_top_left(runtime: Node) -> Vector2:
	var controller = runtime.get("camera_controller")
	if controller != null:
		return controller.logical_to_world(Vector2.ZERO)
	var camera: Camera2D = runtime.get("camera")
	return camera.position - Vector2(StoryRainEmitter.VIEW_CENTRE) if camera != null else Vector2.ZERO


func _start_background_sound(coordinator: Node, resource_token: String, symbol: String, index: int) -> String:
	var row: Dictionary = coordinator._script_sounds.get(resource_token, {})
	var res_path := str(row.get("res_path", ""))
	if res_path == "" or not ResourceLoader.exists(res_path):
		return "not_imported_skipped"
	var stream: AudioStream = load(res_path)
	if stream == null:
		return "load_failed_skipped"
	var player := AudioStreamPlayer.new()
	player.name = "StoryEffectSound_%s_%d" % [symbol, index]
	player.stream = stream
	player.volume_db = 0.0
	coordinator.add_child(player)
	# Loop by restarting on finish; the decoded WAV is not re-tagged as a looping stream.
	player.finished.connect(player.play)
	player.play()
	return "looping"


class FrameOnce extends Sprite2D:
	## Plays a frame run once at the anchor, then frees itself (obj_Effect_FireBomb).
	var frames: Array = []
	var textures: Array[Texture2D] = []
	var frame_index := 0
	var frame_seconds := 0.0
	var elapsed := 0.0

	func configure(manifest: Dictionary, anchor: Vector2) -> void:
		frames = manifest["frames"]
		for frame in frames:
			textures.append(load(str(frame["texture"])))
		frame_seconds = OriginalTick.seconds(float(manifest["frame_ticks"]))
		position = anchor
		centered = false
		scale = Vector2(float(manifest["scale"][0]), float(manifest["scale"][1]))
		_apply_frame()

	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed < frame_seconds:
			return
		elapsed -= frame_seconds
		frame_index += 1
		if frame_index >= frames.size():
			queue_free()
			return
		_apply_frame()

	func _apply_frame() -> void:
		texture = textures[frame_index]
		var origin: Array = frames[frame_index]["draw_origin"]
		offset = -Vector2(float(origin[0]), float(origin[1]))


class TrackSprite extends Sprite2D:
	## A story defProcObjectMove object drawn from its native 0x4051d0 track (白光 21: BALL001
	## zooming 0.4375 → +0.1875 per tick, full add for 5 ticks, then add weighted 16/16 → 1/16,
	## one level per 2 ticks, deleted at tick 38). Tick n shows track frame n at the insert point
	## plus the track offset; the script is not held (its own actDelay runs alongside). Repeated
	## inserts take the seed variants in turn (程序 5's objmRandomDelay). engRANGE (繩子) shows
	## only the part below the insert line.
	var track := {}
	var frames := 0
	var elapsed := 0.0
	var anchor := Vector2.ZERO
	var origin := Vector2.ZERO
	var range_clip := false

	func configure(spec: Dictionary, insert_point: Vector2, key: String, variant: int) -> void:
		texture = load(str(spec.get("preview", "")))
		centered = false
		var draw_origin: Array = spec.get("draw_origin", [0, 0])
		origin = Vector2(float(draw_origin[0]), float(draw_origin[1]))
		offset = -origin
		anchor = insert_point
		position = anchor
		range_clip = str((spec.get("object_fields", {}) as Dictionary).get("obj_Mode", "")) == "engRANGE"
		region_enabled = range_clip
		track = ObjcomdMotion.track(key, variant)
		frames = int(track["frames"])
		material = CanvasItemMaterial.new()
		_show(1)

	func _process(delta: float) -> void:
		elapsed += delta
		_show(1 + int(elapsed / OriginalTick.TICK_SECONDS))

	func _show(frame: int) -> void:
		var drawn: Array = EffectObjectMotion.sprites_at(track, frame)
		if drawn.is_empty():
			if frame >= frames:
				queue_free()
			else:
				visible = false
			return
		var row: Dictionary = drawn[0]
		visible = true
		position = anchor + (row["offset"] as Vector2)
		scale = row["scale"]
		modulate.a = float(row["alpha"])
		var blend := str(row["blend"])
		(material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if blend == "add" else (CanvasItemMaterial.BLEND_MODE_SUB if blend == "sub" else CanvasItemMaterial.BLEND_MODE_MIX)
		if range_clip:
			var size := texture.get_size()
			var hidden := clampf(anchor.y - (position.y - origin.y), 0.0, size.y)
			region_rect = Rect2(0.0, hidden, size.x, size.y - hidden)
			offset = Vector2(-origin.x, hidden - origin.y)


class FadeSprite extends Sprite2D:
	## Fallback for a defProcObjectMove object without a native track (data-only levels):
	## a single frame at its zoom fading out over obj_Data7 ticks; engADDCOLOR* blends
	## additively and swells while fading. Chapter-1 objects all draw TrackSprite.
	const TICK_SECONDS := OriginalTick.TICK_SECONDS
	var life_seconds := 0.0
	var elapsed := 0.0
	var base_scale := Vector2.ONE
	var swell := false

	func configure(preview: String, origin: Array, anchor: Vector2, zoom: Vector2, life_ticks: int, glow: bool) -> void:
		texture = load(preview)
		centered = false
		offset = -Vector2(float(origin[0]), float(origin[1]))
		position = anchor
		base_scale = zoom
		scale = zoom
		swell = glow
		# obj_Data7 ticks at the original tick; a flash lives at least DEFAULT_FRAME_TICKS.
		life_seconds = float(maxi(life_ticks, DEFAULT_FRAME_TICKS)) * TICK_SECONDS
		if glow:
			var blend := CanvasItemMaterial.new()
			blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			material = blend

	func _process(delta: float) -> void:
		elapsed += delta
		var t := clampf(elapsed / life_seconds, 0.0, 1.0)
		modulate.a = 1.0 - t
		if swell:
			scale = base_scale * (1.0 + 0.5 * t)
		if t >= 1.0:
			queue_free()

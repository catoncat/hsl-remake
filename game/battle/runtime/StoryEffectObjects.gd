extends RefCounted
## Story-script effect objects (level 10 帕尼西亞城 廢墟 and later): the readings of an
## inserted object's obj_Process_Code / obj_Mode / obj_Data* fields that the remake acts
## on. Every timing, speed and fade here is a remake presentation choice; the source
## proves only the object fields, insert order and insert points (see the story scene's
## story_objects entries). No battle state: instances live under the runtime's world
## root and free themselves; the coordinator keeps the records (story_records).
##
## Readings (data-driven from the story_objects spec):
##   obj_Data9 mapobjDropRain      -> RainEmitter (drops = the obj_Data4 object's frames)
##   obj_Data9 mapobjPlayBGSound   -> looping background WAV named by obj_Data2
##   obj_Data9 mapobjNextShape     -> looping frame run (火01), additive when engADDCOLOR
##   defProcEffectProcess1 + frames -> one-shot frame run then free (obj_Effect_FireBomb)
##   defProcObjectMove + engZOOM    -> zoomed flash that fades over obj_Data7 ticks (閃電)
##   defProcObjectMove + engADDCOLOR* -> additive glow that swells and fades (光環)
## Anything else keeps the coordinator's plain sprite path.
## provenance:
##   rules: n/a
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json; remake-invented (rain emitter, zoom flash, glow readings of those fields)
##   strings: n/a
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md; provisional (obj_Data7 read as a flash lifetime, glow swell, rain drop frame cadence and spawn band — the mapobjDropRain／defProcObjectMove processes are unread)
##   audio: resource-derived content/imported/hsl/chapter01/scripts

const MapObjectAnimation = preload("res://game/battle/runtime/MapObjectAnimation.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
## Object ticks (shape_delay, obj_Data7, 16.16 velocities) are original ticks.
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const TICK_SECONDS := OriginalTick.TICK_SECONDS
const DEFAULT_FRAME_TICKS := 3
## Effect planes draw over every actor (planeEffect*); the map is at most 1184 px tall.
const EFFECT_Z := 4000
const FIXED_POINT_ONE := 65536.0

var _counts: Dictionary = {}


static func effect_kind(spec: Dictionary) -> String:
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
	if process == "defProcObjectMove" and mode.begins_with("engZOOM"):
		return "flash"
	if process == "defProcObjectMove" and mode.begins_with("engADDCOLOR"):
		return "glow"
	return ""


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
	var kind := effect_kind(spec)
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
				var emitter := RainEmitter.new()
				emitter.name = "StoryEffect_%s_%d" % [symbol, index]
				emitter.configure(runtime.camera, drop_spec, str(fields.get("obj_Data3", "")))
				emitter.z_index = EFFECT_Z
				runtime.world_root.add_child(emitter)
				record["drop_symbol"] = str(fields.get("obj_Data4", ""))
				record["drops_per_tick"] = emitter.drops_per_tick
		"background_sound":
			record["resource"] = str(fields.get("obj_Data2", ""))
			record["status"] = _start_background_sound(coordinator, str(fields.get("obj_Data2", "")), symbol, index)
		"frame_loop":
			var sprite := MapObjectAnimation.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			sprite.configure(frame_manifest(spec, frame_ticks), anchor)
			if not str(fields.get("obj_Mode", "")).begins_with("engADDCOLOR"):
				sprite.material = null
			sprite.z_index = int(anchor.y) + 1
			runtime.world_root.add_child(sprite)
		"frame_once":
			var sprite := FrameOnce.new()
			sprite.name = "StoryEffect_%s_%d" % [symbol, index]
			sprite.configure(frame_manifest(spec, frame_ticks), anchor)
			sprite.z_index = EFFECT_Z
			runtime.world_root.add_child(sprite)
			record["frame_count"] = sprite.frames.size()
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
	player.volume_db = -8.0
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


class FadeSprite extends Sprite2D:
	## Single frame shown at a zoom, fading out over obj_Data7 ticks (閃電 flashes);
	## glow variants (光環, engADDCOLOR_MIX) blend additively and swell while fading.
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


class RainEmitter extends Node2D:
	## mapobjDropRain: keeps a pool of falling drop sprites over the camera's view. The
	## drop object's obj_Data3 / obj_Data4 read as 16.16 velocities per tick (7.5, 9.5
	## px for level 10's 雨), cycling its frame run while falling; the boss object's
	## obj_Data3 low word reads as drops spawned per tick. Density, spawn band and the
	## fall distance are remake choices.
	const TICK_SECONDS := OriginalTick.TICK_SECONDS
	const FIXED_POINT_ONE := 65536.0
	var camera: Camera2D
	var textures: Array[Texture2D] = []
	var origins: Array = []
	var velocity := Vector2(0.0, 300.0)
	var drops_per_tick := 2
	var drops: Array[Sprite2D] = []
	var _spawn_accumulator := 0.0
	var _rng := RandomNumberGenerator.new()
	const MAX_DROPS := 180
	const VIEW_HALF := Vector2(340.0, 260.0)
	## A drop cycles its frames every DEFAULT_FRAME_TICKS (its own shape_delay is not exported).
	const FRAME_SECONDS := OriginalTick.TICK_SECONDS * DEFAULT_FRAME_TICKS

	func configure(camera_node: Camera2D, drop_spec: Dictionary, boss_data3: String) -> void:
		camera = camera_node
		_rng.seed = 10
		for frame in drop_spec.get("frames", [drop_spec.get("preview", "")]):
			textures.append(load(str(frame)))
		origins = drop_spec.get("frame_draw_origins", [drop_spec.get("draw_origin", [0, 0])])
		var fields: Dictionary = drop_spec.get("object_fields", {})
		var vx := _fixed_field(str(fields.get("obj_Data3", "")))
		var vy := _fixed_field(str(fields.get("obj_Data4", "")))
		if vy > 0.0:
			velocity = Vector2(vx, vy) / TICK_SECONDS
		var per_tick := boss_data3.hex_to_int() & 0xFFFF if boss_data3.begins_with("0x") else boss_data3.to_int()
		drops_per_tick = clampi(per_tick, 1, 6)

	static func _fixed_field(token: String) -> float:
		if token == "":
			return 0.0
		return float(token.hex_to_int() if token.begins_with("0x") else token.to_int()) / FIXED_POINT_ONE

	func _process(delta: float) -> void:
		if camera == null or textures.is_empty():
			return
		var center: Vector2 = camera.position
		_spawn_accumulator += delta / TICK_SECONDS * float(drops_per_tick)
		while _spawn_accumulator >= 1.0 and drops.size() < MAX_DROPS:
			_spawn_accumulator -= 1.0
			var drop := Sprite2D.new()
			drop.centered = false
			drop.texture = textures[0]
			drop.position = Vector2(center.x + _rng.randf_range(-VIEW_HALF.x - 120.0, VIEW_HALF.x), center.y - VIEW_HALF.y - _rng.randf_range(0.0, 80.0))
			drop.set_meta("frame", 0)
			drop.set_meta("elapsed", 0.0)
			add_child(drop)
			drops.append(drop)
		var alive: Array[Sprite2D] = []
		for drop in drops:
			drop.position += velocity * delta
			var elapsed := float(drop.get_meta("elapsed")) + delta
			if elapsed >= FRAME_SECONDS:
				elapsed -= FRAME_SECONDS
				var frame := (int(drop.get_meta("frame")) + 1) % textures.size()
				drop.set_meta("frame", frame)
				drop.texture = textures[frame]
				var origin: Array = origins[frame] if frame < origins.size() else origins[0]
				drop.offset = -Vector2(float(origin[0]), float(origin[1]))
			drop.set_meta("elapsed", elapsed)
			if drop.position.y > center.y + VIEW_HALF.y + 40.0 or drop.position.x > center.x + VIEW_HALF.x + 80.0:
				drop.queue_free()
			else:
				alive.append(drop)
		drops = alive

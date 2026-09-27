extends Node2D
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/actor_walk_frames
##   layout: resource-derived content/imported/hsl/shared/actor_magic_poses/manifest.json
##   layout: resource-derived content/generated/hsl/chapter01/battle080_seed.json
##   layout: static-derived docs/evidence_packets/static_reverse/actor_shp_draw_origin.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_draw_order.md
##   layout: provisional (pixel foot Y instead of the original's 32 px row buckets)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/dialogue_death/README.md
##     (speaker／target／actor highlight tint and pulse, one recording — provisional)
##   timing: static-derived docs/evidence_packets/static_reverse/actor_animation_groups.md
##   timing: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##     (idle 6 × 11 ticks, 4 px per tick = 8 ticks per cell, 3 ticks per walk frame, 16 ms tick)
##   timing: provisional
##     (actChangeShape sets cycle at the standing cadence — the actor state during a script shape override is unread)
##   audio: resource-derived content/imported/hsl/chapter01/actor_audio.json
##   audio: provisional (script walks step at relative frames 0／3)

const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const MOVE_SCHEMA := "hsl_actor_runtime_move.v1"
const SUMMARY_SCHEMA := "hsl_actor_runtime_summary.v1"
## Actor cadence in original ticks: the standing loop reloads delay 10 (11 updates per
## frame), walking reloads delay 2 (3 per frame), and a walking actor moves 4 px per tick,
## so one 32 px cell takes 8 ticks. The walk-frame manifests' `fps: 8` is a superseded
## provisional field and is not read.
const IDLE_FRAME_TICKS := 11
const WALK_FRAME_TICKS := 3
const WALK_CELL_TICKS := 8
const IDLE_FRAMES_PER_SECOND := OriginalTick.TICKS_PER_SECOND / IDLE_FRAME_TICKS
const WALK_CELL_SECONDS := OriginalTick.TICK_SECONDS * WALK_CELL_TICKS
const WALK_FRAME_SECONDS := OriginalTick.TICK_SECONDS * WALK_FRAME_TICKS
## Draw depth: the original sorts actors and stand objects into per-frame buckets by the
## foot row (0x4300f0), and a flying actor's bucket is 10 rows deeper (enemy 0x43f31e,
## player 0x443849: +10 when 0x446ad0 reads the flying bit), so a flyer draws over the
## roofs and trees just south of it. The remake's depth is the foot Y in pixels; a
## flyer adds the same 10 rows.
const FLYING_DEPTH_ROWS := 10
const CELL_PIXELS := 32
## One highlight for the three cases the original lights a map actor: the speaker of the shown
## message, the unit under a target cursor, the actor whose turn it is (R6-P1, runtime-measured
## on the 2026-09-24 original recording: a speaker's pixels went from about (117,111,96) to
## (153,152,206) — a blue-white tint — at the message start, pulsed up and back within ≈0.9 s;
## a targeted enemy read about (183,123,131), pinkish, pulsing ±5 luma about every 0.5 s; the
## acting Leonard read about (138,150,201)). Colour is the tint at full level, level swings
## between low and 1.0 with the period; the tint multiplies the sprite (self_modulate), so
## node modulate (fades, dimming) stays its owners'. Priority: speaker, target, actor.
## provisional: one recording, one or two samples each; the original's highlight handler is not read.
const HIGHLIGHTS := {
	"speaker": {"color": Color(1.31, 1.37, 2.15), "low": 0.4, "period": 0.9},
	"target": {"color": Color(1.55, 1.1, 1.25), "low": 0.7, "period": 0.5},
	"actor": {"color": Color(1.2, 1.3, 1.9), "low": 0.4, "period": 0.9},
}
const HIGHLIGHT_ORDER := ["speaker", "target", "actor"]
## The map casting pose (0x4071e0 → 0x446c40(actor, SID, 7, 3)): the SHAPEDEF use_magic frames
## at delay 3 — 4 ticks a frame — played once forward (0x45e575), the last frame held 40 ticks
## (+0x92), played back to the first (0x45e660), then the standing loop again (+0x90 = −1
## makes 0x442161 reselect state 0). Frame index at tick t of n frames: t÷4 up to n − 1 until
## tick 4n, n − 1 until 4n + 40, then one frame back every 4 ticks; over at 8n + 40 (88 ticks
## for the usual six). Static-derived (enemy 0x43f1dc..0x43f24c, player 0x4436f9..0x443770).
const MAGIC_POSES_PATH := "res://content/imported/hsl/shared/actor_magic_poses/manifest.json"
const MAGIC_POSE_FRAME_TICKS := 4
const MAGIC_POSE_HOLD_TICKS := 40
static var _magic_poses: Dictionary = {}

var unit_id: String = ""
var actor_id: String = ""
var animation_state: String = "idle"
var facing: String = "south"
var frame_source_status: String = "unconfigured"
var unresolved_semantics: Array = []
var last_path: Array[Vector2] = []
## Set from the PlayLoop unit's traversal (BattleSceneStage.sync_actor_depth).
var flying_depth := false

var _sprite: Sprite2D = null
var _frame_textures: Dictionary = {}
var _frame_sources: Dictionary = {}
var _frame_origins: Dictionary = {}
var _animations: Dictionary = {}
var _current_sequence: Array[int] = []
var _current_sequence_pos: int = 0
var _motion_tween: Tween = null
var _frame_tween: Tween = null
var _walk_audio: AudioStreamPlayer = null
var _scripted_walk_audio := false
var _idle_elapsed := 0.0
## Script shape override (STORY actChangeShape/actRestoreShape): a looping frame
## set drawn instead of the walk/idle frames until cleared. Frame pixels and draw
## origins come from the level manifest; the cycle rate is the standing cadence.
var _override_textures: Array[Texture2D] = []
var _override_origins: Array[Vector2] = []
var _override_fps := IDLE_FRAMES_PER_SECOND
var _override_pos := 0
var _override_elapsed := 0.0
var _highlights: Dictionary = {}
var _highlight_kind := ""
var _highlight_clock := 0.0
## The running use_magic pose: its frames (texture, origin) and the ticks since it began.
var _magic_pose_textures: Array[Texture2D] = []
var _magic_pose_origins: Array[Vector2] = []
var _magic_pose_ticks := 0.0


## The object's display mode engADDCOLOR (obj_Mode, template +0x00): the sprite blends
## additively like the map's glow objects (the level-37 gems, level 80's 怨念體).
## PLAYERS no_showshape (level 12／26 hull pieces 101): the original's enemy process writes shape
## 0xffff each tick (0x4420ef) and never draws the object; the node stays for position and cues.
func hide_shape() -> void:
	_get_or_create_sprite().visible = false


func set_additive(on: bool) -> void:
	var sprite := _get_or_create_sprite()
	if on == (sprite.material != null):
		return
	if on:
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sprite.material = blend
	else:
		sprite.material = null


## Turns one highlight kind on or off (idempotent: repeating `on` keeps the pulse's phase).
func set_highlight(kind: String, on: bool) -> void:
	assert(HIGHLIGHTS.has(kind), "unknown actor highlight: " + kind)
	if on == _highlights.has(kind): return
	if on: _highlights[kind] = true
	else: _highlights.erase(kind)
	_refresh_highlight()


func clear_highlight() -> void:
	_highlights.clear()
	_refresh_highlight()


func highlight_kind() -> String:
	return _highlight_kind


## The pulse level (low..1.0) `clock` seconds into a highlight: starts at low, peaks mid-period.
static func highlight_level(kind: String, clock: float) -> float:
	var spec: Dictionary = HIGHLIGHTS[kind]
	var wave := 0.5 - 0.5 * cos(TAU * clock / float(spec["period"]))
	return lerpf(float(spec["low"]), 1.0, wave)


func _refresh_highlight() -> void:
	var kind := ""
	for candidate in HIGHLIGHT_ORDER:
		if _highlights.has(candidate):
			kind = candidate
			break
	if kind != _highlight_kind:
		_highlight_kind = kind
		_highlight_clock = 0.0
	_apply_highlight()


func _apply_highlight() -> void:
	var sprite := _get_or_create_sprite()
	if _highlight_kind == "":
		sprite.self_modulate = Color.WHITE
		return
	var tint: Color = HIGHLIGHTS[_highlight_kind]["color"]
	sprite.self_modulate = Color.WHITE.lerp(tint, highlight_level(_highlight_kind, _highlight_clock))


func _process(delta: float) -> void:
	if _highlight_kind != "":
		_highlight_clock += maxf(delta, 0.0)
		_apply_highlight()
	# Match the map objects' native anchor-depth domain, including during a walk.
	# A constant zero put every actor behind every tree, even after walking in front.
	z_index = depth_index(position.y, flying_depth)
	if is_posing():
		_magic_pose_ticks += OriginalTick.ticks(maxf(delta, 0.0))
		_apply_magic_pose_frame()
		return
	if has_shape_override():
		_override_elapsed += maxf(delta, 0.0)
		var override_steps := int(floor(_override_elapsed * _override_fps))
		if override_steps > 0 and _override_textures.size() > 1:
			_override_elapsed -= float(override_steps) / _override_fps
			_override_pos = (_override_pos + override_steps) % _override_textures.size()
			_apply_override_frame()
		return
	if animation_state != "idle" or _current_sequence.size() < 2 or is_moving():
		return
	_idle_elapsed += maxf(delta, 0.0)
	var steps := int(floor(_idle_elapsed * IDLE_FRAMES_PER_SECOND))
	if steps > 0:
		_idle_elapsed -= float(steps) / IDLE_FRAMES_PER_SECOND
		_current_sequence_pos = (_current_sequence_pos + steps) % _current_sequence.size()
		_apply_frame_index(_current_sequence[_current_sequence_pos])


## z_index for a foot at world Y (the map objects' z_index is their EVEF anchor Y).
static func depth_index(foot_y: float, flying: bool) -> int:
	return clampi(roundi(foot_y) + (FLYING_DEPTH_ROWS * CELL_PIXELS if flying else 0), -4096, 4080)


func configure_from_manifest(next_unit_id: String, manifest_entry: Dictionary) -> void:
	unit_id = next_unit_id
	actor_id = str(manifest_entry.get("actor_id", ""))
	unresolved_semantics = manifest_entry.get("unresolved", []).duplicate(true)
	_animations = manifest_entry.get("animations", {}).duplicate(true)
	_load_manifest_frames(manifest_entry.get("frames", []))

	var fallback: Dictionary = manifest_entry.get("fallback", {})
	var fallback_src := str(fallback.get("src", ""))
	if not _frame_textures.is_empty():
		frame_source_status = "manifest_frame_sequence"
		_apply_frame_index(_first_loaded_frame_index())
	elif fallback_src != "":
		_set_fallback_texture(fallback_src)
		frame_source_status = "fallback_single_frame"
	else:
		frame_source_status = "missing_frame_manifest"
	_get_or_create_sprite()


## Starts the use_magic pose (0x4071e0). Returns false — the actor keeps its frames — when its
## SHAPEDEF block has no separate use_magic shape (manifest use_magic_is_stand／without_use_magic).
## A pose already running starts over, as a second 0x4071e0 call resets the frame and counters.
func play_use_magic() -> bool:
	var entry: Dictionary = magic_pose_entry(actor_id)
	if entry.is_empty() or has_shape_override():
		return false
	_magic_pose_textures = []
	_magic_pose_origins = []
	for frame in entry["frames"]:
		var texture := _load_texture(str(frame["res_path"]))
		assert(texture != null, "Missing use_magic frame: " + str(frame["res_path"]))
		_magic_pose_textures.append(texture)
		_magic_pose_origins.append(Vector2(float(frame["draw_origin"][0]), float(frame["draw_origin"][1])))
	_magic_pose_ticks = 0.0
	_apply_magic_pose_frame()
	return true


func is_posing() -> bool:
	return not _magic_pose_textures.is_empty()


## Ends a running pose at once and restores the standing frames (a walk, a death pose, a script shape).
func stop_use_magic() -> void:
	if not is_posing():
		return
	_magic_pose_textures = []
	_magic_pose_origins = []
	play_state("idle", "0")


## The key's use_magic frames ({} when it has none).
static func magic_pose_entry(key: String) -> Dictionary:
	if _magic_poses.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAGIC_POSES_PATH))
		assert(parsed is Dictionary and (parsed as Dictionary).get("schema") == "hsl_actor_magic_poses.v1", "Missing actor magic poses")
		_magic_poses = parsed
	return _magic_poses["poses"].get(key, {})


## Pose frame at `tick` for `count` frames, or −1 once the pose is over (8 × count + 40).
static func magic_pose_frame(tick: float, count: int) -> int:
	var t := int(floor(tick))
	var forward := MAGIC_POSE_FRAME_TICKS * count
	if t < forward:
		return mini(t / MAGIC_POSE_FRAME_TICKS, count - 1)
	var hold_end := forward + MAGIC_POSE_HOLD_TICKS
	if t < hold_end:
		return count - 1
	var back := (t - hold_end) / MAGIC_POSE_FRAME_TICKS
	if back >= count:
		return -1
	return maxi(count - 1 - back, 0)


func _apply_magic_pose_frame() -> void:
	var index := magic_pose_frame(_magic_pose_ticks, _magic_pose_textures.size())
	if index < 0:
		stop_use_magic()
		return
	var sprite := _get_or_create_sprite()
	sprite.texture = _magic_pose_textures[index]
	sprite.centered = false
	sprite.position = -_magic_pose_origins[index]


func set_shape_override(frames: Array, fps: float = IDLE_FRAMES_PER_SECOND) -> int:
	## frames: [{"res_path": String, "draw_origin": [x, y]}, ...]; returns loaded count.
	stop_use_magic()
	_override_textures = []
	_override_origins = []
	for item in frames:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var frame: Dictionary = item
		var texture := _load_texture(str(frame.get("res_path", "")))
		var origin: Array = frame.get("draw_origin", [])
		if texture == null or origin.size() != 2:
			continue
		_override_textures.append(texture)
		_override_origins.append(Vector2(float(origin[0]), float(origin[1])))
	_override_fps = maxf(fps, 0.1)
	_override_pos = 0
	_override_elapsed = 0.0
	if not _override_textures.is_empty():
		_apply_override_frame()
	return _override_textures.size()


func clear_shape_override() -> void:
	if not has_shape_override():
		return
	_override_textures = []
	_override_origins = []
	if not _current_sequence.is_empty():
		_apply_frame_index(_current_sequence[_current_sequence_pos])
	else:
		_apply_frame_index(_first_loaded_frame_index())


func has_shape_override() -> bool:
	return not _override_textures.is_empty()


func _apply_override_frame() -> void:
	var sprite := _get_or_create_sprite()
	sprite.texture = _override_textures[_override_pos]
	sprite.centered = false
	sprite.position = -_override_origins[_override_pos]


func configure_walk_audio(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("Missing actor walk sound: %s" % path)
		return
	if _walk_audio == null:
		_walk_audio = AudioStreamPlayer.new()
		_walk_audio.name = "WalkAudio"
		add_child(_walk_audio)
	_walk_audio.stream = stream


func _play_walk_sound() -> void:
	if _walk_audio != null and is_inside_tree():
		_walk_audio.play()


func _play_scripted_walk_frame_sound() -> void:
	# Native scripted walking checks relative frame 0 or 3 (0x454078..0x45408a).
	if has_shape_override():
		return  # a script shape (e.g. rope climb) is not a footstep cycle
	if _scripted_walk_audio and animation_state == "walk" and _current_sequence_pos in [0, 3]:
		_play_walk_sound()


func play_state(next_state: String, next_facing: String) -> void:
	_idle_elapsed = 0.0
	animation_state = next_state
	facing = next_facing
	_current_sequence = _sequence_for(next_state, next_facing)
	_current_sequence_pos = 0
	if not _current_sequence.is_empty():
		_apply_frame_index(_current_sequence[_current_sequence_pos])
		_play_scripted_walk_frame_sound()


func advance_animation_frame() -> Dictionary:
	if _current_sequence.size() > 1:
		_current_sequence_pos = (_current_sequence_pos + 1) % _current_sequence.size()
		_apply_frame_index(_current_sequence[_current_sequence_pos])
		_play_scripted_walk_frame_sound()
	return runtime_summary()


func move_along(path: Array, duration_seconds: float = 0.0, scripted_walk: bool = false) -> Dictionary:
	stop_use_magic()
	_stop_motion_tweens()
	last_path = []
	for point in path:
		if typeof(point) == TYPE_VECTOR2:
			last_path.append(point)
	var intended_final_position := position
	var frame_advance_steps := 0
	if not last_path.is_empty():
		intended_final_position = last_path[last_path.size() - 1]
		if duration_seconds <= 0.0:
			position = intended_final_position
		else:
			var targets: Array[Vector2] = []
			var previous := position
			for point in last_path:
				if not point.is_equal_approx(previous):
					targets.append(point)
				previous = point
			if not targets.is_empty():
				_scripted_walk_audio = scripted_walk
				_face_walk_target(targets[0])
				_motion_tween = create_tween()
				# Each segment gets its share of the duration by length (a constant speed):
				# grid paths are equal 32 px steps, a scripted walk path may end off-centre.
				var total_length := 0.0
				var from := position
				for point in targets:
					total_length += from.distance_to(point)
					from = point
				from = position
				for point in targets:
					var step_duration := duration_seconds * from.distance_to(point) / total_length if total_length > 0.0 else duration_seconds / float(targets.size())
					from = point
					_motion_tween.tween_callback(_face_walk_target.bind(point))
					_motion_tween.tween_property(self, "position", point, step_duration)
					if not scripted_walk:
						# Normal battle walking emits a cue at each completed grid step.
						_motion_tween.tween_callback(_play_walk_sound)
				_motion_tween.tween_callback(_finish_walking)
				frame_advance_steps = _start_frame_sequence_tween(duration_seconds)

	return {
		"schema": MOVE_SCHEMA,
		"unit_id": unit_id,
		"path_point_count": last_path.size(),
		"duration_seconds": duration_seconds,
		"final_position": intended_final_position,
		"uses_frame_sequence": _current_sequence.size() > 1,
		"animation_frame_count": _current_sequence.size(),
		"frame_advance_steps": frame_advance_steps,
		"frame_source_status": frame_source_status,
		"unresolved_semantics": unresolved_semantics.duplicate(true),
	}


func _face_walk_target(target: Vector2) -> void:
	var delta := target - position
	if delta.is_zero_approx():
		return
	var direction: String
	if absf(delta.x) >= absf(delta.y):
		direction = "right" if delta.x > 0 else "left"
	else:
		direction = "down" if delta.y > 0 else "up"
	if animation_state != "walk" or facing != direction:
		play_state("walk", direction)


func _finish_walking() -> void:
	_scripted_walk_audio = false
	if _frame_tween != null:
		_frame_tween.kill()
		_frame_tween = null
	play_state("idle", "0")


func is_moving() -> bool:
	return _motion_tween != null and _motion_tween.is_running()


func runtime_summary() -> Dictionary:
	return {
		"schema": SUMMARY_SCHEMA,
		"unit_id": unit_id,
		"actor_id": actor_id,
		"animation_state": animation_state,
		"facing": facing,
		"position": position,
		"frame_source_status": frame_source_status,
		"manifest_frame_count": _frame_textures.size(),
		"animation_frame_count": _current_sequence.size(),
		"current_frame_source": _current_frame_source(),
		"motion_active": is_moving(),
		"use_magic_pose": is_posing(),
		"frame_tween_active": _frame_tween != null and _frame_tween.is_running(),
		"unresolved_semantics": unresolved_semantics.duplicate(true),
	}


func _stop_motion_tweens() -> void:
	_scripted_walk_audio = false
	if _walk_audio != null:
		_walk_audio.stop()
	if _motion_tween != null:
		_motion_tween.kill()
		_motion_tween = null
	if _frame_tween != null:
		_frame_tween.kill()
		_frame_tween = null


func _start_frame_sequence_tween(duration_seconds: float) -> int:
	if _current_sequence.size() <= 1 or duration_seconds <= 0.0:
		return 0
	# One walk frame per WALK_FRAME_TICKS (3 ticks): 8 / 3 frames per cell.
	var steps: int = max(1, ceili(duration_seconds / WALK_FRAME_SECONDS))
	var interval: float = duration_seconds / float(steps)
	_frame_tween = create_tween()
	for _index in range(steps):
		_frame_tween.tween_interval(interval)
		_frame_tween.tween_callback(Callable(self, "advance_animation_frame"))
	return steps


func _set_fallback_texture(path: String) -> void:
	var sprite := _get_or_create_sprite()
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path)
	elif FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture != null:
		sprite.texture = texture


func _load_manifest_frames(frames: Array) -> void:
	_frame_textures.clear()
	_frame_sources.clear()
	_frame_origins.clear()
	for item in frames:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var frame: Dictionary = item
		var frame_index := int(frame.get("index", -1))
		if frame_index < 0:
			continue
		var texture := _load_texture_from_frame(frame)
		if texture == null:
			continue
		var origin: Array = frame.get("draw_origin", [])
		if origin.size() != 2:
			push_error("Actor frame missing SHP draw_origin: %s" % str(frame.get("source_member", "")))
			continue
		_frame_origins[frame_index] = Vector2(origin[0], origin[1])
		_frame_textures[frame_index] = texture
		_frame_sources[frame_index] = str(frame.get("res_path", frame.get("png_path", "")))


func _load_texture_from_frame(frame: Dictionary) -> Texture2D:
	var candidates := [
		str(frame.get("res_path", "")),
		str(frame.get("png_path", "")),
	]
	for candidate in candidates:
		if candidate == "":
			continue
		var texture := _load_texture(candidate)
		if texture != null:
			return texture
	return null


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null


func _sequence_for(state: String, next_facing: String) -> Array[int]:
	var state_map: Dictionary = _animations.get(state, {})
	var sequence_entry: Dictionary = state_map.get(next_facing, {})
	var frames: Array = sequence_entry.get("frames", [])
	var sequence: Array[int] = []
	for frame_index in frames:
		var index := int(frame_index)
		if _frame_textures.has(index):
			sequence.append(index)
	return sequence


func _first_loaded_frame_index() -> int:
	var indexes := []
	for index in _frame_textures.keys():
		indexes.append(int(index))
	indexes.sort()
	return indexes[0] if not indexes.is_empty() else -1


func _apply_frame_index(frame_index: int) -> void:
	if not _frame_textures.has(frame_index) or has_shape_override() or is_posing():
		return
	var sprite := _get_or_create_sprite()
	sprite.texture = _frame_textures[frame_index]
	sprite.centered = false
	sprite.position = -_frame_origins[frame_index]


func _current_frame_source() -> String:
	if _current_sequence.is_empty():
		var first_index := _first_loaded_frame_index()
		return str(_frame_sources.get(first_index, ""))
	var frame_index := _current_sequence[_current_sequence_pos]
	return str(_frame_sources.get(frame_index, ""))


func _get_or_create_sprite() -> Sprite2D:
	if _sprite != null:
		return _sprite
	var existing := get_node_or_null("Sprite2D")
	if existing is Sprite2D:
		_sprite = existing
	else:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)
	_sprite.centered = false
	return _sprite

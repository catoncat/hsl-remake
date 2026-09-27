extends Sprite2D
## SHP frame playback at a fixed source anchor. No battle state.
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##   layout: static-derived docs/evidence_packets/static_reverse/gate_fire_animation.md
##   timing: resource-derived content/imported/hsl/chapter01/map_objects.json
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: provisional (additive colour cycle)

const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")

var frames: Array = []
var textures: Array[Texture2D] = []
var frame_index: int = 0
var frame_seconds: float = 0.0
var elapsed: float = 0.0


func configure(manifest: Dictionary, anchor: Vector2) -> void:
	frames = manifest["frames"]
	textures.clear()
	for frame in frames:
		textures.append(load(str(frame["texture"])))
	frame_seconds = OriginalTick.seconds(float(manifest["frame_ticks"]))
	position = anchor
	centered = false
	scale = Vector2(float(manifest["scale"][0]), float(manifest["scale"][1]))
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	frame_index = 0
	elapsed = 0.0
	_apply_frame()


func _process(delta: float) -> void:
	if frames.is_empty():
		return
	elapsed += delta
	var steps := floori(elapsed / frame_seconds)
	if steps > 0:
		elapsed -= float(steps) * frame_seconds
		frame_index = (frame_index + steps) % frames.size()
		_apply_frame()


func _apply_frame() -> void:
	texture = textures[frame_index]
	var origin: Array = frames[frame_index]["draw_origin"]
	offset = -Vector2(float(origin[0]), float(origin[1]))

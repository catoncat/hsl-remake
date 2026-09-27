extends Sprite2D
## Additive light glow with a gentle brightness flicker for stand objects whose
## source token is mapobjFlash. Presentation only; TYPE.H gives the object obj_Score = level
## and obj_HitPoint = delay, which the map-object export does not carry yet, so cadence
## and depth stay provisional values.
## provenance:
##   rules: n/a
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##   strings: n/a
##   timing: provisional content/imported/hsl/global/tables/TYPE.H (mapobjFlash objsScore = level, objsHitPoint = delay ticks; 0.55 s／0.22 stand in until the flash branch is read)
##   audio: n/a

const PERIOD_SECONDS := 0.55
const DEPTH := 0.22

var elapsed := 0.0
var _seed_phase := 0.0


func configure(anchor: Vector2, additive: bool) -> void:
	position = anchor
	centered = false
	_seed_phase = fmod(anchor.x * 0.013 + anchor.y * 0.007, TAU)
	if additive:
		var blend := CanvasItemMaterial.new()
		blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = blend
	_apply(0.0)


func _process(delta: float) -> void:
	elapsed += delta
	_apply(elapsed)


func _apply(time: float) -> void:
	var wave := sin(time * TAU / PERIOD_SECONDS + _seed_phase) * 0.5 + sin(time * TAU / (PERIOD_SECONDS * 0.37) + _seed_phase * 2.0) * 0.5
	var brightness := 1.0 - DEPTH * 0.5 + wave * DEPTH * 0.5
	modulate = Color(brightness, brightness, brightness, 1.0)

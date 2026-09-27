extends Sprite2D
## Stand object whose obj_Data9 is mapobjFlash: drawn engADDCOLOR_MIX (dst + src × level/16)
## with the level stepping down and back up. Presentation only.
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_map_object_flash.md
##     (0x462240 → 0x4623e1 level-table add; the object keeps its anchor depth)
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_object_flash.md
##     (0x43cee7 flash branch: step every obj_HitPoint ticks, level 16 − obj_Score .. 16)

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const FULL_LEVEL := 16

## obj_Score (+0x84): steps down before turning back; obj_HitPoint (+0x88): ticks per step.
var depth_steps := 0
var delay_ticks := 0
## +0x28: the add level, 16 unless obj_Data preset it; +0x86: the signed step counter.
var level := FULL_LEVEL
var counter := 0
var countdown := 0
var elapsed := 0.0


## 0x43cee7 first call: mode |= 0x24000000 (engADDCOLOR_MIX, always additive), level 16
## when +0x28 is 0, delay copied to +0x8a; the same call already counts one tick.
func configure(anchor: Vector2, score: int, hit_point: int, preset_level: int = 0) -> void:
	position = anchor
	centered = false
	depth_steps = score
	delay_ticks = hit_point
	level = preset_level if preset_level != 0 else FULL_LEVEL
	counter = 0
	countdown = delay_ticks
	elapsed = 0.0
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = blend
	tick()


func _process(delta: float) -> void:
	elapsed += delta
	while elapsed >= OriginalTick.TICK_SECONDS:
		elapsed -= OriginalTick.TICK_SECONDS
		tick()


## One process update: countdown −1; at ≤ 0 reload and step the counter
## (c < score → c + 1, else c = −c); c > 0 dims one level (floor 0), c < 0 brightens (cap 16).
func tick() -> void:
	countdown -= 1
	if countdown > 0:
		_apply()
		return
	countdown = delay_ticks
	counter = counter + 1 if counter < depth_steps else -counter
	if counter > 0:
		level = maxi(level - 1, 0)
	elif counter < 0:
		level = mini(level + 1, FULL_LEVEL)
	_apply()


func _apply() -> void:
	var weight := float(level) / float(FULL_LEVEL)
	modulate = Color(weight, weight, weight, 1.0)

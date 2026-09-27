extends Node2D
## The LEVEL UP star shower over a recipient: obj_LevelUp_Star 149 (MAGIC\AIR06_03..06, 4 frames,
## additive) scattered by 0x408b20 case 3 when the LEVEL UP float spawns (0x4084e0 kind 6). The
## node stands at the recipient's point (the actor (x, y), its cell centre); BattleAftermath
## places it every frame like the reward floats, so the shower follows the map.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   timing: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##     (engADDCOLOR level draw: AdditiveLevelBlend, kind 8 0x462154 with the level tables 0x4bfbf0)
##   timing: remake-invented
##     (the draws come from a presentation RNG seeded by the exchange and the recipient, not the original global
##     0x458c10 stream)
const AdditiveLevelBlend = preload("res://game/battle/scene/AdditiveLevelBlend.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
## 0x408b20 case 3 → 0x415c10(x, y − 0x30 + 0x30, 0x95, 0x40, 0x18, 0, 6, 0x24, 0).
const STAR_COUNT := 36
const RANGE_X := 64
const RANGE_Y := 24
const DELAY_JITTER := 6
const FRAMES := 4
## effProcFlyUpShape: speed = obj_Data6 (0x4000) + (0x458c10() & 0x1f000), 16.16 px a tick;
## +0x7c (shape delay 0) += 6 + (rand & 7); 0x45e575 ends the hold when it counts below zero.
const BASE_SPEED := 0x4000
const SPEED_MASK := 0x1f000
const HOLD_BASE := 6
const HOLD_MASK := 7
## 0x422c9a: once held, +0x28 (level 16) −1 a tick; deleted at 0.
const LEVELS := 16
var stars: Array[Dictionary] = []
var sprites: Array[Sprite2D] = []
var ticks := 0.0
var blend: ShaderMaterial = AdditiveLevelBlend.material()


## Draws the 36 stars' parameters from `seed` (0x415c10's loop order: x, y, then the next delay;
## effProcFlyUpShape's frame, speed and hold at each star's first tick) and restarts the clock.
func begin(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	stars.clear()
	var delay := 0
	for index in range(STAR_COUNT):
		var dx := rng.randi_range(0, RANGE_X - 1)
		if dx > RANGE_X / 2: dx = RANGE_X / 2 - dx
		var dy := rng.randi_range(0, RANGE_Y - 1)
		if dy > RANGE_Y / 2: dy = RANGE_Y / 2 - dy
		stars.append({"offset": Vector2(dx, dy), "appear": appear_tick(delay), "frame": rng.randi_range(0, FRAMES - 1),
			"speed": float(BASE_SPEED + (rng.randi() & SPEED_MASK)) / 65536.0, "hold": HOLD_BASE + (rng.randi() & HOLD_MASK)})
		delay += 1 + rng.randi_range(0, DELAY_JITTER - 1)
	ticks = 0.0
	for sprite in sprites:
		sprite.queue_free()
	sprites.clear()
	var assets: Dictionary = BattleRewardFloater.manifest()["assets"]
	for star in stars:
		var record: Dictionary = assets["level_up_star_%d" % int(star["frame"])]
		var sprite := Sprite2D.new()
		sprite.texture = load(record["res_path"])
		sprite.centered = false
		sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
		sprite.material = blend
		sprite.hide()
		add_child(sprite)
		sprites.append(sprite)
	show()


## The tick a star inserted with delay `delay` first draws: 0x415dc0 decrements +0xae before
## testing it, so delays 0 and 1 both draw on the first tick.
static func appear_tick(delay: int) -> int:
	return maxi(delay - 1, 0)


## A star's draw level `age` ticks after its first draw: 16 until its hold runs out (hold + 1
## FlyUp2 calls after the first tick), then one less a tick; 0 = deleted.
static func level(age: int, hold: int) -> int:
	return clampi(LEVELS - maxi(age - (hold + 1), 0), 0, LEVELS)


## Pixels risen `age` ticks after the first draw (0x45ebdc keeps the fraction: floor(speed × age)).
static func rise_at(age: int, speed: float) -> float:
	return floorf(speed * float(maxi(age, 0)))


## Advances the shower; returns false once every star is gone (then hidden).
func advance(delta: float) -> bool:
	ticks += maxf(0.0, OriginalTick.ticks(delta))
	var now := int(floor(ticks))
	var alive := false
	for index in range(stars.size()):
		var star: Dictionary = stars[index]
		var sprite := sprites[index]
		var age: int = now - int(star["appear"])
		var star_level := level(age, int(star["hold"])) if age >= 0 else LEVELS
		alive = alive or age < 0 or star_level > 0
		sprite.visible = age >= 0 and star_level > 0
		if sprite.visible:
			sprite.position = Vector2(star["offset"]) - Vector2(0, rise_at(age, float(star["speed"])))
			sprite.modulate.a = AdditiveLevelBlend.alpha(star_level)
	if not alive:
		hide()
	return alive


## Trailing-float interface (BattleAftermath._place): the node itself does not rise.
func rise(_at: float = -1.0) -> float:
	return 0.0

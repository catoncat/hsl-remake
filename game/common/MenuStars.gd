extends Node2D
## Menu_Star (object 788) and Menu_Star2 (789) sparkles of the title menu and the 回憶錄 list:
## 0x423aa0(object, template, width, jitter, count) walks columns from the object's left + 16
## every 32 px across its width; each column 0x415c10 drops `count` stars at (column, top + 16)
## plus folded rand offsets (x within `width`, y within 2 × (height − 16)), the n-th star delayed
## by the sum of n rand(jitter) + 1. Both templates run effProcFlyUpShape (0x41f5db): random
## start shape of 3, held; straight up at (rand & 0x1f000) + Data6 (16.16 px a tick); held
## Shape_Delay + 6..13 + 1 ticks, then effProcFlyUp2's fade (0x422c9a) one of 16 additive levels
## a tick. The host calls tick() once per original tick.
## provenance:
##   rules: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (0x423aa0 → 0x415c10, effProcFlyUpShape 0x41f5db, effProcFlyUp2 0x422c9a)
##   rules: provisional (per-star offsets and delays use the remake RNG, not the original global rand stream)
##   layout: resource-derived content/imported/hsl/shared/skill_effects/manifest.json (EAR24 frames)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##   timing: provisional (Menu_Star's unset Shape_Delay taken as 0)

const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const SKILL_EFFECTS_PATH := "res://content/imported/hsl/shared/skill_effects/manifest.json"
## Per template: its three shapes, Data6 speed and Shape_Delay; width and jitter are the
## 0x423aa0 arguments of the title's hover／click calls (other callers pass their own).
const KINDS := {
	"hover": {"frames": ["MAGIC\\EAR24_22.SHP", "MAGIC\\EAR24_23.SHP", "MAGIC\\EAR24_24.SHP"], "width": 48, "jitter": 6, "speed_base": 0, "shape_delay": 0},
	"click": {"frames": ["MAGIC\\EAR24_21.SHP", "MAGIC\\EAR24_22.SHP", "MAGIC\\EAR24_23.SHP"], "width": 64, "jitter": 1, "speed_base": 0x8000, "shape_delay": 2},
}
const COLUMN_PITCH := 32
const LEVELS := 16

var _stars: Array = []
var _material: CanvasItemMaterial
var _frames: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_material = CanvasItemMaterial.new()
	_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var effects: Variant = ContentPaths.read_json(SKILL_EFFECTS_PATH)
	_frames = (effects.get("frames", {}) as Dictionary) if typeof(effects) == TYPE_DICTIONARY else {}


func count() -> int:
	return _stars.size()


## 0x423aa0 over `rect` (the object's shape, in this node's coordinates); width／jitter < 0 take
## the kind's title values.
func spawn(rect: Rect2, kind: String, per_column: int, width: int = -1, jitter: int = -1) -> void:
	var spec: Dictionary = KINDS[kind]
	var spread := width if width >= 0 else int(spec["width"])
	var step := jitter if jitter >= 0 else int(spec["jitter"])
	var span_y := 2 * int(rect.size.y - 16)
	var x := rect.position.x + 16
	while x < rect.end.x:
		var delay := 0
		for index in per_column:
			_add(Vector2(x + _fold(spread), rect.position.y + 16 + _fold(span_y)), kind, delay)
			delay += _rng.randi() % step + 1
		x += COLUMN_PITCH


## 0x415c10 offset: r = rand() % n, folded to n/2 − r past n/2.
func _fold(n: int) -> int:
	if n <= 0:
		return 0
	var r := _rng.randi() % n
	return r if r <= n / 2 else n / 2 - r


func _add(at: Vector2, kind: String, delay: int) -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.material = _material
	sprite.visible = false
	add_child(sprite)
	_stars.append({"sprite": sprite, "kind": kind, "at": at, "delay": delay, "started": false, "speed": 0.0, "life": 0, "fading": false, "level": LEVELS})


## Per star each tick: the effect prologue (0x415dc0) waits out +0xae; the first drawn tick runs
## effProcFlyUpShape's setup; later ticks run effProcFlyUp2 (move, then count the held shape down
## or fade one level; deleted at level 0).
func tick() -> void:
	var alive: Array = []
	for star in _stars:
		var sprite: Sprite2D = star["sprite"]
		star["delay"] = int(star["delay"]) - 1
		if int(star["delay"]) > 0:
			alive.append(star)
			continue
		var spec: Dictionary = KINDS[star["kind"]]
		if not bool(star["started"]):
			star["started"] = true
			var frame: Dictionary = _frames.get(spec["frames"][_rng.randi() % 3], {})
			var origin: Array = frame.get("draw_origin", [0, 0])
			sprite.texture = load(str(frame.get("res_path", ""))) if frame.has("res_path") else null
			sprite.offset = -Vector2(float(origin[0]), float(origin[1]))
			star["speed"] = float((_rng.randi() & 0x1f000) + int(spec["speed_base"])) / 65536.0
			star["life"] = int(spec["shape_delay"]) + 6 + (_rng.randi() & 7)
			sprite.visible = true
		else:
			star["at"] = (star["at"] as Vector2) - Vector2(0, float(star["speed"]))
			if bool(star["fading"]):
				star["level"] = int(star["level"]) - 1
			else:
				star["life"] = int(star["life"]) - 1
				star["fading"] = int(star["life"]) < 0
		if int(star["level"]) <= 0:
			sprite.queue_free()
			continue
		sprite.position = (star["at"] as Vector2).floor()
		sprite.modulate.a = float(star["level"]) / LEVELS
		alive.append(star)
	_stars = alive

extends Node2D
## A red damage number drawn the way defProcShowNumber draws kind 0 (0x408580 → 0x40863e): the
## NUM100..109 digits appear one at a time from the left, every 10 ticks — the newest at 2×,
## the one it replaced at 1.5× until the next half-step, a 4× additive NUM510 flash behind a new
## digit for 6 ticks — then the whole number stands 18 ticks and fades 16 ticks. It does not rise
## (the kind 0 branch returns before the 0x10000 rise toggle at 0x408ad8). The node sits where
## the number is centred and advances itself on the tick clock (emitting `finished` when the
## object would be deleted); `state_at` replays the object's counters tick by tick. The node's
## own alpha is the draw level; `followers` (a caption beside it) take the same alpha.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   timing: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##     (0x2c000000 flash: AdditiveLevelBlend, kind 9; digit fade: kind 4 0x4699fd as alpha level／16)
const AdditiveLevelBlend = preload("res://game/battle/scene/AdditiveLevelBlend.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
const DIGIT_PITCH := 14
const DIGIT_STEP_TICKS := 10
const FLASH_TICKS := 6
const FLASH_LEVEL_BASE := 10
const NEWEST_SCALE := 2.0
const PREVIOUS_SCALE := 1.5
const FLASH_SCALE := 4.0
const LEVELS := 16
## defProcShowNumber's hold: +0xa8 counts down before the first draw (map and cut-in callers pass 0 → 1 tick).
const HOLD_TICKS := 1
signal finished
var digits := ""
var ticks := 0.0
var done := false
var followers: Array[CanvasItem] = []
var glyphs: Array[Sprite2D] = []
var flash: Sprite2D
var flash_blend: ShaderMaterial = AdditiveLevelBlend.material()


## Shows `amount` (its decimal digits) and restarts the object's clock.
func present(amount: int) -> void:
	digits = str(absi(amount))
	ticks = 0.0
	done = false
	for glyph in glyphs:
		glyph.queue_free()
	glyphs.clear()
	if flash != null:
		flash.queue_free()
	var assets: Dictionary = BattleRewardFloater.manifest()["assets"]
	flash = _sprite(assets["damage_flash"])
	flash.material = flash_blend
	for index in range(digits.length()):
		var glyph := _sprite(assets["damage_digit_" + digits[index]])
		glyph.position = Vector2(-7 * (digits.length() - 1) + DIGIT_PITCH * index, 0)
		glyphs.append(glyph)
	_draw_state(state_at(0, digits.length()))
	show()


func _sprite(record: Dictionary) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(record["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.hide()
	add_child(sprite)
	return sprite


## The object `tick` ticks after spawning, for a number of `count` digits: {visible (digits drawn,
## 0 during the hold or once deleted), newest, previous (1-based, 0 = none), flash (digit, 0 =
## none), flash_level, level, alive}. Tick 0 is the hold tick (drawn nowhere).
static func state_at(tick: int, count: int) -> Dictionary:
	var result := {"visible": 0, "newest": 0, "previous": 0, "flash": 0, "flash_level": 0, "level": LEVELS, "alive": true}
	if tick < HOLD_TICKS:
		return result
	var newest := 1
	var previous := 0
	var step := DIGIT_STEP_TICKS
	var half := 5
	var half_reload := 2
	var flash_digit := 1
	var flash_count := FLASH_TICKS
	var level := LEVELS
	for _call in range(tick - HOLD_TICKS + 1):
		var shown_previous := previous
		if newest != 0:
			step -= 1
			if step <= 0:
				step = DIGIT_STEP_TICKS
				shown_previous = newest
				newest += 1
				if newest > count:
					newest = 0
				else:
					flash_digit = newest
					flash_count = FLASH_TICKS
				previous = shown_previous
		half -= 1
		if half <= 0:
			half = half_reload
			if newest == 0 and shown_previous == 0:
				level -= 1
				if level <= 0:
					return {"visible": 0, "newest": 0, "previous": 0, "flash": 0, "flash_level": 0, "level": 0, "alive": false}
			else:
				shown_previous = 0
				previous = 0
				if newest == 0:
					half = 18
					half_reload = 1
		result = {"visible": count if newest == 0 and shown_previous == 0 else maxi(newest, shown_previous),
			"newest": newest, "previous": shown_previous, "flash": flash_digit if flash_count > 0 else 0,
			"flash_level": flash_count + FLASH_LEVEL_BASE if flash_count > 0 else 0, "level": level, "alive": true}
		# The flash is drawn with the flashing digit, so it only burns down while that digit shows.
		if flash_count > 0 and flash_digit <= int(result["visible"]):
			flash_count -= 1
	return result


## Ticks the number lives, spawn to deletion: the hold, 10 per digit, 18 settle, 16 fade.
static func life_ticks(count: int) -> int:
	return HOLD_TICKS + DIGIT_STEP_TICKS * count + 18 + LEVELS - 1


func _process(delta: float) -> void:
	if digits != "" and not done:
		advance(delta)


## Advances the clock; returns false once deleted (then hidden, `finished` emitted once).
func advance(delta: float) -> bool:
	return draw_at(ticks + maxf(0.0, OriginalTick.ticks(delta)))


## Draws the object `tick` ticks after its spawn (an owner with its own clock calls this with
## `_process` off); returns false once deleted (hidden, `finished` emitted once).
func draw_at(tick: float) -> bool:
	ticks = tick
	var state := state_at(int(floor(ticks)), digits.length())
	_draw_state(state)
	if not bool(state["alive"]) and not done:
		done = true
		hide()
		finished.emit()
	return bool(state["alive"])


func _draw_state(state: Dictionary) -> void:
	modulate.a = float(state["level"]) / float(LEVELS)
	for follower in followers:
		if is_instance_valid(follower): follower.modulate.a = modulate.a
	for index in range(glyphs.size()):
		var glyph := glyphs[index]
		var digit := index + 1
		glyph.visible = digit <= int(state["visible"])
		glyph.scale = Vector2.ONE * (PREVIOUS_SCALE if digit == int(state["previous"]) else NEWEST_SCALE if digit == int(state["newest"]) else 1.0)
	var flash_digit := int(state["flash"])
	flash.visible = flash_digit > 0 and flash_digit <= int(state["visible"])
	if flash.visible:
		flash.position = glyphs[flash_digit - 1].position
		flash.scale = Vector2.ONE * FLASH_SCALE
		flash.modulate.a = AdditiveLevelBlend.alpha(int(state["flash_level"]))

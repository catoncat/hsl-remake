extends Node2D
## One result number as the original spawns it through 0x4084e0(x, y, value, waiter, kind, hold)
## → defProcShowNumber (0x408580), drawn with the original glyphs: kind 0 red damage
## (DamageNumberFloater: NUM100..109 revealed digit by digit, no rise), kind 2 green heal
## (NUM200..209), kind 3 blue MP (NUM300..309), kind 5 MISS (NUM513 alone). Kinds 2／3／5 hold
## level 16 for 16 ticks, then −1 every 2 ticks to 0 at tick 46, rising 1 px every other tick;
## digits start at x − 7 × (digits − 1), 14 px apart, each glyph placed by its SHP draw origin;
## no sign glyph. The node sits at the spawn point (x, y); `hold` is the spawn's +0xa8 countdown,
## during which the object draws nothing (at least one tick). An owner with its own clock (the
## cut-in, the magic receiver) turns `clocked` off and calls `draw_at`; otherwise the node
## advances itself on the tick clock and emits `finished` once the object would be deleted.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
const DamageNumberFloater = preload("res://game/battle/scene/DamageNumberFloater.gd")
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
## Result number kinds with an original glyph set (ShowNumberStyle kinds).
const KINDS := ["damage", "heal", "mp", "miss"]
## The word of the NUM513 glyph.
const MISS_WORD := "MISS"
## aniShowHitResult (0x4046b9), item use (0x444b2f) and the resource recovery (0x40e55c) spawn the
## MP number with hold 0x28 at the HP number's point.
const MP_AFTER_HP_HOLD_TICKS := 40
signal finished
var kind := ""
var amount := 0
var hold := 0
var ticks := 0.0
var clocked := true
var done := false
## What the number shows: its digits, or MISS.
var text := ""
## The DamageNumberFloater (damage) or the glyph sprites' parent (heal／MP／MISS).
var number: Node2D


## The numbers aniShowHitResult (0x404643) spawns at one point for a result: the red damage
## number alone when HP was lost; else the green heal number (hold 0) and the blue MP number
## 40 ticks behind it; else the MP number alone; else MISS when `miss`, nothing otherwise.
## Each entry {kind, value, hold}. Item use and the turn-end recovery spawn the same heal／MP pair.
static func spawns(damage: int, healing: int, restored_mp: int, miss: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if damage > 0:
		result.append({"kind": "damage", "value": damage, "hold": 0})
	elif healing > 0:
		result.append({"kind": "heal", "value": healing, "hold": 0})
		if restored_mp > 0: result.append({"kind": "mp", "value": restored_mp, "hold": MP_AFTER_HP_HOLD_TICKS})
	elif restored_mp > 0:
		result.append({"kind": "mp", "value": restored_mp, "hold": 0})
	elif miss:
		result.append({"kind": "miss", "value": 0, "hold": 0})
	return result


## Adds one number per `spawn` entry under `parent` at `point` (each self-clocked unless
## `self_clocked` is false); returns them in spawn order.
static func spawn_all(parent: Node, entries: Array[Dictionary], point: Vector2, self_clocked: bool = true) -> Array[Node2D]:
	var numbers: Array[Node2D] = []
	for entry in entries:
		var number: Node2D = (load("res://game/battle/scene/ResultNumberFloater.gd") as GDScript).new()
		number.clocked = self_clocked
		number.position = point
		parent.add_child(number)
		number.present(str(entry["kind"]), int(entry["value"]), int(entry.get("hold", 0)))
		numbers.append(number)
	return numbers


## Shows `value` as a `number_kind` ("damage", "heal", "mp", "miss") number spawned with
## `hold_ticks`, restarting its clock. Call once the node is in the tree.
func present(number_kind: String, value: int = 0, hold_ticks: int = 0) -> void:
	assert(number_kind in KINDS, "unknown result number kind: " + number_kind)
	kind = number_kind
	amount = absi(value)
	hold = maxi(0, hold_ticks)
	ticks = 0.0
	done = false
	if number != null:
		number.free()
	if kind == "damage":
		number = DamageNumberFloater.new()
		number.name = "DamageDigits"
		add_child(number)
		number.set_process(false)
		number.present(amount)
		text = str(amount)
	else:
		number = Node2D.new()
		number.name = {"heal": "HealDigits", "mp": "MpDigits", "miss": "Miss"}[kind]
		add_child(number)
		if kind == "miss":
			_glyph("miss", 0)
			text = MISS_WORD
		else:
			# 0x408580: first glyph at x − ((digits − 1) + prefix units) × pitch／2; kinds 2／3 carry no prefix.
			var layout: Dictionary = BattleRewardFloater.manifest()["layout"]["show_number"]
			var pitch := int(layout["pitch"])
			text = str(amount)
			var x := -((text.length() - 1) + int(layout["prefix_units"][kind])) * (pitch / 2)
			for digit in text:
				_glyph("%s_digit_%s" % [kind, digit], x)
				x += pitch
	show()
	draw_at(0.0)


func _glyph(key: String, x: int) -> void:
	var record: Dictionary = BattleRewardFloater.manifest()["assets"][key]
	var sprite := Sprite2D.new()
	sprite.texture = load(record["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.position = Vector2(x, 0)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	number.add_child(sprite)


## The glyphs' rectangle at 1× in the parent's coordinates, at the spawn point (before any rise).
func bounds() -> Rect2:
	var assets: Dictionary = BattleRewardFloater.manifest()["assets"]
	var keys: Array[String] = []
	var xs: Array[int] = []
	if kind == "miss":
		keys.append("miss")
		xs.append(0)
	else:
		var x := -(text.length() - 1) * 7
		for digit in text:
			keys.append("%s_digit_%s" % [kind, digit])
			xs.append(x)
			x += 14
	var rect := Rect2()
	for index in range(keys.size()):
		var record: Dictionary = assets[keys[index]]
		var glyph := Rect2(position + Vector2(xs[index] - int(record["draw_origin"][0]), -int(record["draw_origin"][1])), Vector2(record["size"][0], record["size"][1]))
		rect = glyph if index == 0 else rect.merge(glyph)
	return rect


## Ticks before the first drawn tick: the +0xa8 hold counts down (a spawn with hold 0 still
## spends its first tick initialising).
static func hidden_ticks(hold_ticks: int) -> int:
	return maxi(1, hold_ticks)


## Ticks from the spawn to the deletion of a `number_kind` number of `digits` digits.
static func life_of(number_kind: String, digits: int, hold_ticks: int = 0) -> int:
	if number_kind == "damage":
		return hidden_ticks(hold_ticks) - DamageNumberFloater.HOLD_TICKS + DamageNumberFloater.life_ticks(digits)
	return hidden_ticks(hold_ticks) + BattleRewardFloater.SHOW_NUMBER_TICKS


func life_ticks() -> int:
	return life_of(kind, text.length(), hold)


## Draws the object `tick` ticks after its spawn; false once deleted (hidden, `finished` once).
func draw_at(tick: float) -> bool:
	ticks = maxf(0.0, tick)
	var alive := ticks < float(life_ticks())
	if kind == "damage":
		number.visible = alive
		if alive:
			number.draw_at(ticks - float(hidden_ticks(hold) - DamageNumberFloater.HOLD_TICKS))
	else:
		var age := ticks - float(hidden_ticks(hold))
		number.visible = alive and age >= 0.0
		if number.visible:
			number.modulate.a = BattleRewardFloater.level(age) / float(DamageNumberFloater.LEVELS)
			number.position.y = -floorf(age / 2.0)
	visible = alive
	if alive:
		done = false
	elif not done:
		done = true
		finished.emit()
	return alive


## Whether the number draws anything now (past its hold, not yet deleted).
func showing() -> bool:
	return visible and number != null and number.visible


func advance(delta: float) -> bool:
	return draw_at(ticks + maxf(0.0, OriginalTick.ticks(delta)))


func _process(delta: float) -> void:
	if clocked and kind != "" and not done:
		advance(delta)

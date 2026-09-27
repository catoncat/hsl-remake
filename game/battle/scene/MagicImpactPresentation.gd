extends Node2D
## Transient map receiver bars and amount, as the original recording shows them: each
## receiver's HP／MP bars appear at its own cell with the HP before the hit, switch to the HP
## after it, the number joins them and the bars go while the number stays. The number is the
## original's at the target's (x, y − 0x34) (0x40aba0): a hit's red kind-0 number (NUM100..109
## revealed digit by digit, 10 ticks per digit + 34, no rise), a miss's NUM513 MISS (level 16
## for 16 ticks, then fading to tick 46, rising 1 px every other tick), both through
## ResultNumberFloater. Several receivers' bars stay at their own cells (no avoidance).
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V08
##   layout: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: remake-invented (42×7 bar)
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: runtime-reference docs/evidence_packets/static_reverse/original_magic_damage.md
##     (bar beats read from the 2026-09-24 recording at 19.4 ms／tick: before-HP 21, number 29, bars 60 ticks)
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ResultNumberFloater = preload("res://game/battle/scene/ResultNumberFloater.gd")
## 0x40aba0／0x40ac24: the magic channel spawns its number at (target x, target y − 0x34).
const NUMBER_OFFSET := Vector2(0, -0x34)
## Bar beats in original ticks, read from the recording (474.600 s bars with the HP before,
## 475.000 s HP after, 475.167 s number, 475.767 s bars gone; 30 fps, 19.4 ms／tick).
const BEFORE_TICKS := 21
const NUMBER_TICKS := 29
const BAR_TICKS := 60
var entries: Array[Dictionary] = []
var elapsed := 0.0
## OPT-PACE (docs/OPTIONS.md), read once per begin: the multiplier on the clock (Timing.PACE_MAP).
var pace := 1.0


func begin(strike: Dictionary, runtime: Node) -> void:
	finish()
	pace = float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0))
	for hit in strike.get("affected_targets", [strike]):
		var actor = runtime.actor_node_for_unit(str(hit["defender_id"]))
		if actor == null: continue
		var unit: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, str(hit["defender_id"]))
		unit.merge(hit.get("defender_before", {}), true)
		var point: Vector2 = runtime.world_to_logical_position(actor.position)
		var panel := Control.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = Vector2(clampf(point.x - 22, 8, 518), clampf(point.y + 5, 8, 435))
		panel.size = Vector2(114, 30)
		add_child(panel)
		var hp_bar := _bar(panel, int(unit["hp"]), int(unit["max_hp"]), 0, Color(0.8, 0.12, 0.08))
		_bar(panel, int(unit.get("mp", 0)), int(unit.get("max_mp", 0)), 15, Color(0.1, 0.5, 0.85))
		var damage := int(hit.get("actual_damage", hit["damage"]))
		# 0x40aba0: the red kind-0 number of a hit, MISS (kind 5) of a miss; hold 0.
		var amount: Node2D = ResultNumberFloater.new()
		amount.name = "DamageDigits" if bool(hit["hit"]) else "MissGlyph"
		amount.clocked = false
		amount.position = point + NUMBER_OFFSET
		add_child(amount)
		amount.present("damage" if bool(hit["hit"]) else "miss", damage)
		amount.hide()
		entries.append({"panel": panel, "amount": amount, "actor": weakref(actor), "hit": bool(hit["hit"]),
			"hp_bar": hp_bar, "hp_after": int(hit["defender_hp_after"]), "max_hp": int(unit["max_hp"]),
			"unit_id": hit["defender_id"], "float_seconds": OriginalTick.seconds(amount.life_ticks())})
	elapsed = 0.0
	_process(0.0)


## Seconds until every bar and number has gone: the bars' 60 ticks or the longest number
## from its tick 29, whichever ends later.
func total_seconds() -> float:
	return maxf(OriginalTick.seconds(BAR_TICKS), OriginalTick.seconds(NUMBER_TICKS) + float_seconds())


## The longest number among the entries: a red damage number lives 10 ticks per digit + 34,
## MISS 47 (its first tick initialises, then 46).
func float_seconds() -> float:
	var longest := 0.0
	for entry in entries:
		longest = maxf(longest, float(entry["float_seconds"]))
	return longest


func _bar(parent: Control, value: int, maximum: int, top: float, color: Color) -> Dictionary:
	# A themed ProgressBar retains a font-sized minimum height even when its
	# percentage is hidden. These small map-only bars must stay exactly seven px.
	var bar := Control.new()
	bar.position = Vector2(0, top + 3)
	bar.size = Vector2(42, 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	_rect(bar, Vector2.ZERO, Vector2(42, 7), Color(0.95, 0.95, 0.95))
	_rect(bar, Vector2.ONE, Vector2(40, 5), Color(0.04, 0.04, 0.04, 0.94))
	var fill := _rect(bar, Vector2.ONE, Vector2.ZERO, color)
	var text := Label.new()
	text.position = Vector2(47, top - 3)
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_constant_override("outline_size", 3)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)
	var parts := {"fill": fill, "text": text}
	_set_bar(parts, value, maximum)
	return parts


func _set_bar(parts: Dictionary, value: int, maximum: int) -> void:
	parts["fill"].size = Vector2(40 * clampf(float(value) / maxi(1, maximum), 0, 1), 5)
	parts["text"].text = "%d/%d" % [value, maximum]


func _rect(parent: Control, at: Vector2, dimensions: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = dimensions
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func busy() -> bool:
	return not entries.is_empty()


func _process(delta: float) -> void:
	if not busy(): return
	elapsed += maxf(0.0, delta) * pace
	if elapsed >= total_seconds():
		finish()
		return
	var tick := OriginalTick.ticks(elapsed)
	for entry in entries:
		entry["panel"].visible = tick < BAR_TICKS
		if tick >= BEFORE_TICKS and not entry.get("after_shown", false):
			entry["after_shown"] = true
			_set_bar(entry["hp_bar"], int(entry["hp_after"]), int(entry["max_hp"]))
		if tick < NUMBER_TICKS:
			entry["amount"].hide()
		else:
			entry["amount"].draw_at(tick - NUMBER_TICKS)
		var actor: Node2D = entry["actor"].get_ref()
		if actor != null:
			var brightness := 1.0 + maxf(0, 1 - tick / BEFORE_TICKS) if entry["hit"] else 1.0
			actor.modulate = Color(brightness, brightness, brightness)


func finish() -> void:
	for entry in entries:
		var actor: Node2D = entry["actor"].get_ref()
		if actor != null: actor.modulate = Color.WHITE
		entry["panel"].queue_free()
		entry["amount"].queue_free()
	entries.clear()


func _exit_tree() -> void:
	finish()

extends Node2D
## Transient map receiver bars -> amount, observed in original V08. The bar is a remake
## beat; then the original number at the target's (x, y − 0x34) (0x40aba0): a hit's red kind-0
## number (NUM100..109 revealed digit by digit, 10 ticks per digit + 34, no rise), a miss's
## NUM513 MISS (level 16 for 16 ticks, then fading to tick 46, rising 1 px every other tick),
## both through ResultNumberFloat. Bar collision avoidance is remake presentation.
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V08
##   layout: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: remake-invented (42×7 bar, bar collision avoidance)
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: remake-invented
##     (0.45 s receiver bar before the number — kept remake beat, the original shows the number at once)
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ResultNumberFloat = preload("res://game/battle/scene/ResultNumberFloat.gd")
## 0x40aba0／0x40ac24: the magic channel spawns its number at (target x, target y − 0x34).
const NUMBER_OFFSET := Vector2(0, -0x34)
## Remake beat: the short HP／MP bar shown before the number (deliberately kept).
const VITALS_SECONDS := 0.45
var entries: Array[Dictionary] = []
var elapsed := 0.0
## OPT-PACE (docs/OPTIONS.md), read once per begin: the multiplier on the clock (Timing.PACE_MAP).
var pace := 1.0


func begin(strike: Dictionary, runtime: Node) -> void:
	finish()
	pace = float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0))
	var occupied: Array[Rect2] = []
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
		var rect := Rect2(panel.position, panel.size).grow(3)
		for _attempt in range(occupied.size() + 1):
			var collision := false
			for previous in occupied:
				if rect.intersects(previous):
					rect.position.y = previous.position.y - rect.size.y - 2
					collision = true
					break
			if not collision: break
		occupied.append(rect)
		panel.position = rect.position + Vector2(3, 3)
		add_child(panel)
		_bar(panel, int(hit["defender_hp_after"]), int(unit["max_hp"]), 0, Color(0.8, 0.12, 0.08))
		_bar(panel, int(unit.get("mp", 0)), int(unit.get("max_mp", 0)), 15, Color(0.1, 0.5, 0.85))
		var damage := int(hit.get("actual_damage", hit["damage"]))
		# 0x40aba0: the red kind-0 number of a hit, MISS (kind 5) of a miss; hold 0.
		var amount: Node2D = ResultNumberFloat.new()
		amount.name = "DamageDigits" if bool(hit["hit"]) else "MissGlyph"
		amount.clocked = false
		amount.position = point + NUMBER_OFFSET
		add_child(amount)
		amount.present("damage" if bool(hit["hit"]) else "miss", damage)
		amount.hide()
		entries.append({"panel": panel, "amount": amount, "actor": weakref(actor), "hit": bool(hit["hit"]),
			"unit_id": hit["defender_id"], "float_seconds": OriginalTick.seconds(amount.life_ticks())})
	elapsed = 0.0
	_process(0.0)


## The longest number among the entries: a red damage number lives 10 ticks per digit + 34,
## MISS 47 (its first tick initialises, then 46).
func float_seconds() -> float:
	var longest := 0.0
	for entry in entries:
		longest = maxf(longest, float(entry["float_seconds"]))
	return longest


func _bar(parent: Control, value: int, maximum: int, top: float, color: Color) -> void:
	# A themed ProgressBar retains a font-sized minimum height even when its
	# percentage is hidden. These small map-only bars must stay exactly seven px.
	var bar := Control.new()
	bar.position = Vector2(0, top + 3)
	bar.size = Vector2(42, 7)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	_rect(bar, Vector2.ZERO, Vector2(42, 7), Color(0.95, 0.95, 0.95))
	_rect(bar, Vector2.ONE, Vector2(40, 5), Color(0.04, 0.04, 0.04, 0.94))
	_rect(bar, Vector2.ONE, Vector2(40 * clampf(float(value) / maxi(1, maximum), 0, 1), 5), color)
	var text := Label.new()
	text.position = Vector2(47, top - 3)
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_constant_override("outline_size", 3)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.text = "%d/%d" % [value, maximum]
	parent.add_child(text)


func _rect(parent: Control, at: Vector2, dimensions: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = dimensions
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func busy() -> bool:
	return not entries.is_empty()


func _process(delta: float) -> void:
	if not busy(): return
	elapsed += maxf(0.0, delta) * pace
	if elapsed >= VITALS_SECONDS + float_seconds():
		finish()
		return
	for entry in entries:
		entry["panel"].visible = elapsed < VITALS_SECONDS
		if elapsed < VITALS_SECONDS:
			entry["amount"].hide()
		else:
			entry["amount"].draw_at(OriginalTick.ticks(elapsed - VITALS_SECONDS))
		var actor: Node2D = entry["actor"].get_ref()
		if actor != null:
			var brightness := 1.0 + maxf(0, 1 - elapsed / VITALS_SECONDS) if entry["hit"] else 1.0
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

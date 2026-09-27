extends Node
## Read-only departure of retained sprites. Original phase 53/54 holds the actor 16 logical
## ticks and then unregisters it; the remake spends those 16 ticks (256 ms) on an alpha fade.
## provenance:
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_departure.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: remake-invented (alpha ramp over the removal ticks)
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const DEPARTURE_TICKS := 16
const FADE_SECONDS := OriginalTick.TICK_SECONDS * DEPARTURE_TICKS
var runtime: Node
var _fades := {}

func begin(unit_id: String) -> bool:
	if runtime == null or runtime.opening_coordinator == null or not runtime.opening_coordinator.cutscene_mode or runtime.opening_coordinator.story_mode: return false
	var unit: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, unit_id)
	if not unit.get("departed", false) or unit.get("departure", {}).get("source") != "winfail": return false
	var actor: Node2D = runtime.actor_node_for_unit(unit_id)
	if actor == null: return true
	if _fades.has(unit_id): return true
	if DisplayServer.get_name() == "headless":
		actor.hide()
		return true
	var tween := create_tween()
	_fades[unit_id] = tween
	tween.tween_property(actor, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func():
		if is_instance_valid(actor): actor.hide(); actor.modulate.a = 1.0
		_fades.erase(unit_id))
	return true

func busy() -> bool:
	return not _fades.is_empty()

func actor_busy(unit_id: String) -> bool:
	return _fades.has(unit_id)

func reset() -> void:
	for tween in _fades.values(): tween.kill()
	_fades.clear()

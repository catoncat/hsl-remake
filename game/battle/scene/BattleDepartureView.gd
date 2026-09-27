extends Node
## Read-only departure of retained sprites. Original phase 53/54 (0x453ce0／0x454286) draws
## the actor engMIX (+0 = 0x20000000) at level +0x28 = 16, takes one level a tick and
## unregisters it at 0: 16 drawn frames at 16/16 … 1/16, then gone (a Wait chain resumes after).
## provenance:
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_entry.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_departure.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
const OriginalTick = preload("res://game/common/OriginalTick.gd")
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
	fade(unit_id, actor)
	return true

## The engMIX step-down on any retained actor node (battle or story walk-and-delete).
func fade(unit_id: String, actor: Node2D) -> void:
	if _fades.has(unit_id): return
	if DisplayServer.get_name() == "headless":
		actor.hide()
		return
	var tween := create_tween()
	_fades[unit_id] = tween
	tween.tween_method(func(t: float) -> void: _mix_level(actor, t), 0.0, FADE_SECONDS, FADE_SECONDS)
	tween.tween_callback(func():
		if is_instance_valid(actor): actor.hide(); actor.modulate.a = 1.0
		_fades.erase(unit_id))

## Level 16 minus the ticks elapsed, over 16 (engMIX src × level / 16).
static func _mix_level(actor: Node2D, elapsed: float) -> void:
	if is_instance_valid(actor): actor.modulate.a = float(DEPARTURE_TICKS - mini(int(elapsed / OriginalTick.TICK_SECONDS), DEPARTURE_TICKS)) / DEPARTURE_TICKS

func busy() -> bool:
	return not _fades.is_empty()

func actor_busy(unit_id: String) -> bool:
	return _fades.has(unit_id)

func reset() -> void:
	for tween in _fades.values(): tween.kill()
	_fades.clear()

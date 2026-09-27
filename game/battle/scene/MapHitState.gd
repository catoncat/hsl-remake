extends RefCounted
## The map hit state 0x407230 writes on a receiver: +0x92 = 60 ticks, +0x98 = 0x300 (phase 0,
## amplitude 3), +0x80 clears 0x1000 and sets 0x800. While 0x800 is set the actor process
## (0x43f288) steps the phase 1,2,3,−3,−2,−1,0,… each tick — phase ≥ 0 draws the actor at cell
## x + 15, else + 17 — and its tail (0x4420ba..0x442161) poses state 6, the SHAPEDEF `hit`
## shape; the 60th tick clears 0x800, returns x to the cell centre and the tail poses stand again.
## The magic channel of 0x40aa80 calls it for every receiver it hurt (0x40b831); the close-up
## (ordinary attack, 絶技) never does.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_map_strike.md
##     (hit shape for 60 ticks, ±1 px shake)
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_map_strike.md#录屏对照
##     (V08 frame_041 receiver in its hit shape)
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_strike.md (60 ticks, phase period 7)
##   audio: static-derived docs/evidence_packets/static_reverse/original_map_strike.md (0x407230 plays no sound)
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const HIT_POSES_PATH := "res://content/imported/hsl/shared/actor_hit_poses/manifest.json"
const TICKS := 60
const AMPLITUDE := 3
static var _poses: Dictionary = {}


## 0x40aa80's counter (0x40b831): the receiver took HP damage or an applied negative status.
## A receiver the strike killed is left to the death job (BattleAftermath.show_hit_pose).
static func hurt(outcome: Dictionary) -> bool:
	if not bool(outcome.get("hit", false)) or int(outcome.get("defender_hp_after", 1)) <= 0:
		return false
	if int(outcome.get("actual_damage", outcome.get("damage", 0))) > 0:
		return true
	return outcome.get("status_effects", []).any(func(effect): return bool(effect.get("applied", false)))


## Every receiver `hurt` by a magic-channel strike enters the hit state; `pace` is the map clock
## multiplier (OPT-PACE).
static func begin_strike(strike: Dictionary, runtime: Node, owner: Node, pace: float = 1.0) -> void:
	for outcome in strike.get("affected_targets", [strike]):
		if hurt(outcome):
			begin(runtime, owner, str(outcome["defender_id"]), pace)


static func begin(runtime: Node, owner: Node, unit_id: String, pace: float = 1.0) -> void:
	var actor: Node2D = runtime.actor_node_for_unit(unit_id)
	if actor == null:
		return
	# A no_showshape object (ActorRuntime.hide_shape) keeps its sprite hidden through the pose.
	var pose: Dictionary = poses().get(str(actor.get("actor_id")), {})
	if not pose.is_empty() and actor.has_method("set_shape_override"):
		actor.set_shape_override([pose])
	var base := actor.position
	var tick_seconds := OriginalTick.seconds(1) / maxf(pace, 0.01)
	var tween := owner.create_tween()
	for tick in range(1, TICKS):
		var dx := -1.0 if posmod(tick + AMPLITUDE, 2 * AMPLITUDE + 1) - AMPLITUDE >= 0 else 1.0
		tween.tween_callback(func(): if is_instance_valid(actor): actor.position = base + Vector2(dx, 0.0))
		tween.tween_interval(tick_seconds)
	tween.tween_callback(func(): _end(runtime, actor, unit_id, base))


static func _end(runtime: Node, actor: Node2D, unit_id: String, base: Vector2) -> void:
	if not is_instance_valid(actor):
		return
	actor.position = base
	# A receiver that died meanwhile keeps the hit shape: its death job owns it.
	var unit: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, unit_id)
	if int(unit.get("hp", 0)) > 0 and actor.has_method("clear_shape_override"):
		actor.clear_shape_override()


static func poses() -> Dictionary:
	if _poses.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(HIT_POSES_PATH))
		assert(typeof(source) == TYPE_DICTIONARY and (source as Dictionary).get("schema") == "hsl_actor_hit_poses.v1", "Missing actor hit poses")
		_poses = (source as Dictionary)["poses"]
	return _poses

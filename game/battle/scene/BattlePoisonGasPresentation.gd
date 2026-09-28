extends RefCounted
## 噴人沼氣 (defProcPoisonGas 0x43c7c0) presentation: replays the receipt PoisonGasRules left
## on winfail_runtime.story_object_wait_requests[].poison_gas. Rules are already committed.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md
##     (0x43c337: 設定選項 場景效果 off leaves the smoke undrawn)
##   layout: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md
##     (camera, 3 SMOKE001 at the centre ±38 px rising 0.25..0.75 px/tick, hit actors shake ±1 px)
##   layout: remake-invented (ADDCOLOR_MIX level drawn as additive alpha)
##   timing: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md
##     (scroll, burst, 90／40-tick hold, 60-tick shake, smoke fade in 16 ticks then a level per 3..7 ticks)
##   audio: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md (the process plays no sound)
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const MapHitState = preload("res://game/battle/scene/MapHitState.gd")
const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const StoryEffectObjects = preload("res://game/battle/runtime/StoryEffectObjects.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const MANIFEST := "res://content/imported/hsl/shared/skill_effects/manifest.json"
## global.obs 706 obj_Fire_Smoke: MAGIC\SMOKE001.SHP, obj_Shape_Delay 3 (+0x7c). From its second
## call defProcFireSmoke (0x43c260) writes +0x30 = +0x32 each tick, so the MIN20 frame the gas put
## in +0x30 only exists on the creation tick (skip-draw bit) and the init tick (level 0).
const SMOKE_FRAME := "MAGIC\\SMOKE001.SHP"
const SMOKE_DELAY := 3
## 0x43c298..0x43c31c init draws (PoisonGasRules smoke_draws): hold 3 + rand(5), offsets rand(77)
## above 38 folded to 38 − r, speed 0x4000 + rand(0x8000).
const SMOKE_OFFSET_FOLD := 38
const SMOKE_SPEED_BASE := 0x4000
const SMOKE_LEVELS := 16
## 0x407230: +0x92 = 60 ticks, +0x98 = 0x300 (phase 0, amplitude 3); 0x43f288 per tick.
const SHAKE_TICKS := 60


## The actInsertStoryObjectWaitPos requests one firing installed, in chain order.
static func requests(loop: Dictionary, firing_index: int) -> Array:
	var result: Array = []
	for request in loop.get("winfail_runtime", {}).get("story_object_wait_requests", []):
		if int(request.get("firing_index", -1)) == firing_index:
			result.append(request)
	return result


static func has_gas(loop: Dictionary, firing_index: int) -> bool:
	return requests(loop, firing_index).any(func(request): return request.has("poison_gas"))


## The chain's WaitPos events become playable where their request carried a burst.
static func attach(loop: Dictionary, events: Array, firing_index: int) -> Array:
	var found := requests(loop, firing_index)
	var ordinal := 0
	var result: Array = []
	for event_value in events:
		var event: Dictionary = event_value
		if event.get("kind") == "story_object_insert_wait_position":
			if ordinal < found.size() and found[ordinal].has("poison_gas"):
				event = event.duplicate(true)
				event["cutscene_skip"] = false
				event["poison_gas"] = found[ordinal]["poison_gas"]
			ordinal += 1
		result.append(event)
	return result


## Starts the burst; returns the seconds the script waits (0x43c7c0 clears *(+0xac) at the end).
static func play(coordinator: Node, event: Dictionary) -> float:
	var runtime: Node = coordinator.runtime
	var gas: Dictionary = event["poison_gas"]
	var position: Array = gas.get("position", [])
	# State 0: 0x43bf30(obj, 0) glides until the object point sits at the view focus.
	var scroll := 0.0
	if runtime.camera_controller != null and position.size() == 2:
		scroll = coordinator.cinematics._scroll_camera(runtime.camera_controller.clamped_position(OpeningCinematics.script_position_camera_centre(position, false)))
	var burst := Node2D.new()
	burst.name = "PoisonGasBurst"
	burst.z_index = StoryEffectObjects.EFFECT_Z
	burst.visible = false
	runtime.world_root.add_child(burst)
	var centre: Vector2i = gas.get("centre", Vector2i.ZERO)
	var pixel := Vector2(TacticalGridRules.cell_center_pixel(centre))
	var entry: Dictionary = _frames().get(SMOKE_FRAME, {})
	var texture: Texture2D = load(str(entry["res_path"])) if not entry.is_empty() else null
	var origin: Array = entry.get("draw_origin", [0, 0])
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var smoke_ticks := 0
	for draws in gas.get("smoke_draws", []):
		var hold := SMOKE_DELAY + int(draws[0])
		var offset := Vector2(_smoke_offset(int(draws[1])), _smoke_offset(int(draws[2])))
		var speed := SMOKE_SPEED_BASE + int(draws[3])
		smoke_ticks = maxi(smoke_ticks, _smoke_life(hold))
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.material = additive
		sprite.visible = false
		burst.add_child(sprite)
		var base := pixel + offset - Vector2(float(origin[0]), float(origin[1]))
		sprite.position = base
		var motion := sprite.create_tween()
		motion.tween_interval(maxf(scroll, 0.001))
		motion.tween_method(func(t: float): _smoke_tick(sprite, base, int(t), hold, speed),
			0.0, float(_smoke_life(hold)), OriginalTick.seconds(_smoke_life(hold)))
		motion.tween_callback(sprite.queue_free)
	var hit_ids: Array = []
	for hit in gas.get("hits", []):
		if not hit_ids.has(str(hit["unit_id"])):
			hit_ids.append(str(hit["unit_id"]))
	var linger := OriginalTick.seconds(int(gas.get("linger_ticks", 40)))
	var tween := burst.create_tween()
	tween.tween_interval(maxf(scroll, 0.001))
	tween.tween_callback(func():
		burst.visible = true
		for unit_id in hit_ids:
			shake(runtime, burst, str(unit_id)))
	# The gas releases the script after its hold; the smoke objects run their own course.
	tween.tween_interval(OriginalTick.seconds(maxi(int(gas.get("linger_ticks", 40)) + 1, smoke_ticks)))
	tween.tween_callback(burst.queue_free)
	coordinator.story_records.append({"kind": "poison_gas_burst", "source_event_id": str(event.get("id", "")),
		"centre": centre, "smoke_frames": gas.get("smoke_frames", []), "smoke_ticks": smoke_ticks, "hit_unit_ids": hit_ids,
		"scroll_seconds": scroll, "linger_ticks": int(gas.get("linger_ticks", 40))})
	return scroll + OriginalTick.seconds(1) + linger


## 0x407230 puts the victim into the hit state: hit frame plus the 60-tick shake (0x43f288 phase
## byte 1,2,3,−3,−2,−1,0,…; ≥ 0 draws at cell x + 15, else + 17). MapHitState is the one reader
## of that state (STRIKEFX 2026-09-27); the drop-lightning victims call it through here too.
static func shake(runtime: Node, owner: Node, unit_id: String) -> void:
	MapHitState.begin(runtime, owner, unit_id)


static func _smoke_offset(r: int) -> float:
	return float(SMOKE_OFFSET_FOLD - r if r > SMOKE_OFFSET_FOLD else r)


## Ticks from creation to 0x45e3ed: init call, 16 fade-in calls, then 16 holds of `hold` ticks.
static func _smoke_life(hold: int) -> int:
	return 1 + SMOKE_LEVELS + SMOKE_LEVELS * hold


## Tick k after creation (0x43c260): k 0 is skipped by the creation bit, k 1 is the init call
## (level 0); from k 2 the level climbs one per call to 16 (k 17), then drops one every `hold`
## calls; every call but the init and the deleting one moves 0x45ebdc one 16.16 step up (angle
## 0xc0: vx 0, vy = −speed), so y has moved floor(−(k − 1)·speed / 65536).
static func _smoke_tick(sprite: Sprite2D, base: Vector2, k: int, hold: int, speed: int) -> void:
	if not is_instance_valid(sprite):
		return
	var level := 0
	if k >= 1 + SMOKE_LEVELS:
		level = SMOKE_LEVELS - floori(float(k - 1 - SMOKE_LEVELS) / float(hold))
	elif k >= 2:
		level = k - 1
	# 0x43c337: with 設定選項 場景效果 off (or 0x400000) the smoke writes +0x30 = 0xffff and is
	# not drawn, but still rises and fades.
	sprite.visible = level > 0 and GameSettings.scene_effects_enabled()
	sprite.modulate.a = float(level) / float(SMOKE_LEVELS)
	var rise := floori(-float(maxi(k - 1, 0) * speed) / 65536.0)
	sprite.position = base + Vector2(0.0, float(rise))


static func _frames() -> Dictionary:
	var parsed: Variant = ContentPaths.read_json(MANIFEST)
	return (parsed as Dictionary).get("frames", {}) if parsed is Dictionary else {}

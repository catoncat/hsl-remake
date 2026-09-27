extends RefCounted
## 打人閃電 (defProcDropLightn 0x43ca70) presentation: replays the receipt DropLightningRules left
## on winfail_runtime.presentation_requests[].drop_lightning. Rules (HP, draws) are already committed.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_drop_lightning.md
##     (camera, AIR14 2× additive, FireBomb 162／165, numbers at y − 48, shake)
##   layout: static-derived content/generated/hsl/skills/effect_motion.json (FireBomb tracks)
##   layout: provisional (planeEffect6 drawn over planeEffect2)
##   timing: static-derived docs/evidence_packets/static_reverse/original_drop_lightning.md
##     (scroll, 11 full + 15 fading frames, strike on tick 27, 80／20-tick hold)
##   audio: static-derived docs/evidence_packets/static_reverse/original_drop_lightning.md
##     (the process plays nothing; FireBomb obj_X1 BOMB0004 as it starts)
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const StoryEffectObjects = preload("res://game/battle/runtime/StoryEffectObjects.gd")
const EffectObjectMotion = preload("res://game/battle/scene/EffectObjectMotion.gd")
const ResultNumberFloat = preload("res://game/battle/scene/ResultNumberFloat.gd")
const BattlePoisonGasPresentation = preload("res://game/battle/scene/BattlePoisonGasPresentation.gd")
const MANIFEST := "res://content/imported/hsl/shared/skill_effects/manifest.json"
const TOKEN := "actInsertStoryObjectWait"
## OBJ-010 code 25: obj_Shape_Name MAGIC\AIR14_01.SHP is shape +0x32; +0x32 + frame is AIR14_0(frame+1).
const FRAME_NAME := "MAGIC\\AIR14_%02d.SHP"
## Template obj_Mode engZOOM, obj_Zoom 2.0.
const BOLT_ZOOM := 2.0
## State 1: +0x90 = 10 ticks at full level (drawn ticks 0..10); state 2: engMIX with level
## +0x28 = 16 counting down (15..1 on ticks 11..25); the tick it reaches 0 the shape turns 0xffff.
const FULL_TICKS := 11
const FADE_LEVELS := 16
## State 3 runs on the tick after the shape is cleared.
const STRIKE_TICK := 27
## 0x43c9d0: 0x4084e0(x, y − 48, damage, 0, kind 0, hold 0).
const NUMBER_OFFSET := Vector2(0, -48)
const FIREBOMBS := ["obj_Effect_FireBomb", "obj_Effect_FireBomb2"]
const SOUND := "WAV\\BOMB0004.WAV"


## The drop_lightning receipts of one firing: the key's requests in firing order, as many per
## firing as its chain has actInsertStoryObjectWait tokens.
static func requests(loop: Dictionary, firing_index: int, events: Array) -> Array:
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	var fired: Array = runtime.get("fired", [])
	if firing_index < 0 or firing_index >= fired.size():
		return []
	var key := str(fired[firing_index].get("key", ""))
	var per_firing := events.filter(func(event): return event.get("script_action_name") == TOKEN).size()
	var ordinal := 0
	for index in range(firing_index):
		if str(fired[index].get("key", "")) == key: ordinal += 1
	var matching: Array = runtime.get("presentation_requests", []).filter(func(request): return request.get("key") == key and request.get("name") == TOKEN)
	return matching.slice(ordinal * per_firing, (ordinal + 1) * per_firing)


## The chain's InsertStoryObjectWait events become playable where their request carried a bolt.
static func attach(loop: Dictionary, events: Array, firing_index: int) -> Array:
	var found := requests(loop, firing_index, events)
	var ordinal := 0
	var result: Array = []
	for event_value in events:
		var event: Dictionary = event_value
		if event.get("script_action_name") == TOKEN:
			if ordinal < found.size() and found[ordinal].has("drop_lightning"):
				event = event.duplicate(true)
				event["cutscene_skip"] = false
				event["drop_lightning"] = found[ordinal]["drop_lightning"]
			ordinal += 1
		result.append(event)
	return result


## Starts the bolt; returns the seconds until 0x43ca70 clears *(+0xac) and deletes itself.
static func play(coordinator: Node, event: Dictionary) -> float:
	var runtime: Node = coordinator.runtime
	var bolt: Dictionary = event["drop_lightning"]
	var pixel := Vector2(bolt.get("pixel", Vector2i.ZERO))
	# State 0: 0x43bf30(obj, 0) glides until the bolt sits at the view focus.
	var scroll := 0.0
	if runtime.camera_controller != null:
		scroll = coordinator.cinematics._scroll_camera(runtime.camera_controller.clamped_position(OpeningCinematics.script_position_camera_centre([pixel.x, pixel.y], false)))
	var node := Burst.new()
	node.name = "DropLightningBolt"
	node.runtime = runtime
	node.position = pixel
	node.frame = int(bolt.get("frame", 0))
	node.hits = bolt.get("hits", [])
	node.delay = scroll
	runtime.world_root.add_child(node)
	var hold := int(bolt.get("linger_ticks", 20))
	coordinator.story_records.append({"kind": "drop_lightning", "source_event_id": str(event.get("id", "")),
		"pixel": bolt.get("pixel"), "frame": node.frame, "hit_unit_ids": node.hits.map(func(hit): return str(hit["unit_id"])),
		"scroll_seconds": scroll, "linger_ticks": hold})
	# State 3 sets +0x90 and counts it once on the same tick.
	return scroll + OriginalTick.seconds(STRIKE_TICK + hold - 1)


class Burst extends Node2D:
	## One bolt on the tick clock: tick 0 is the state-0 tick the camera arrived; the
	## FireBombs (created then, processed from the next tick) and the shakes outlive the bolt.
	var runtime: Node
	var frame := 0
	var hits: Array = []
	var delay := 0.0
	var elapsed := 0.0
	var sounded := false
	var struck := false
	var bolt: Sprite2D
	var sprites: Array[Sprite2D] = []
	var manifest: Dictionary = {}
	var materials := {}
	var end_tick := STRIKE_TICK + BattlePoisonGasPresentation.SHAKE_TICKS + 1

	func _ready() -> void:
		manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		for blend in ["add", "sub", "mix"]:
			var material := CanvasItemMaterial.new()
			material.blend_mode = {"add": CanvasItemMaterial.BLEND_MODE_ADD, "sub": CanvasItemMaterial.BLEND_MODE_SUB, "mix": CanvasItemMaterial.BLEND_MODE_MIX}[blend]
			materials[blend] = material
		for object_name in FIREBOMBS:
			if EffectObjectMotion.tracked(object_name):
				end_tick = maxi(end_tick, int(EffectObjectMotion.track(object_name)["frames"]))
		bolt = Sprite2D.new()
		var entry: Dictionary = manifest["frames"].get(FRAME_NAME % (frame + 1), {})
		if not entry.is_empty():
			bolt.texture = load(str(entry["res_path"]))
			bolt.offset = -Vector2(float(entry["draw_origin"][0]), float(entry["draw_origin"][1]))
		bolt.centered = false
		bolt.scale = Vector2.ONE * BOLT_ZOOM
		bolt.material = materials["add"]
		bolt.z_index = StoryEffectObjects.EFFECT_Z + 1
		bolt.z_as_relative = false
		bolt.hide()
		add_child(bolt)
		_update()

	func _process(delta: float) -> void:
		elapsed += delta
		_update()

	func _update() -> void:
		if elapsed < delay:
			return
		var tick := int(OriginalTick.ticks(elapsed - delay))
		if tick >= 1 and not sounded:
			# defProcEffectProcess1 plays the template's obj_X1 as each FireBomb starts (0x415e1a).
			sounded = true
			_sound(SOUND)
		bolt.visible = tick < FULL_TICKS + FADE_LEVELS - 1
		bolt.modulate.a = 1.0 if tick < FULL_TICKS else float(FADE_LEVELS - 1 - (tick - FULL_TICKS)) / FADE_LEVELS
		var used := 0
		for object_name in FIREBOMBS:
			if not EffectObjectMotion.tracked(object_name):
				continue
			for entry in EffectObjectMotion.sprites_at(EffectObjectMotion.track(object_name), tick):
				var record: Dictionary = manifest["frames"].get(str(entry["member"]), {})
				if record.is_empty():
					continue
				while sprites.size() <= used:
					var fresh := Sprite2D.new()
					fresh.centered = false
					fresh.z_index = StoryEffectObjects.EFFECT_Z
					fresh.z_as_relative = false
					add_child(fresh)
					sprites.append(fresh)
				var sprite := sprites[used]
				used += 1
				sprite.texture = load(str(record["res_path"]))
				sprite.offset = -Vector2(float(record["draw_origin"][0]), float(record["draw_origin"][1]))
				sprite.scale = entry["scale"]
				sprite.material = materials[str(entry["blend"])]
				sprite.modulate = Color(1, 1, 1, float(entry["alpha"]))
				sprite.position = entry["offset"]
				sprite.show()
		for index in range(used, sprites.size()):
			sprites[index].hide()
		if tick >= STRIKE_TICK and not struck:
			struck = true
			for hit in hits:
				var number: Node2D = ResultNumberFloat.new()
				number.position = Vector2(hit["cell"]) * 32.0 + Vector2(16, 16) + NUMBER_OFFSET - position
				number.z_index = StoryEffectObjects.EFFECT_Z + 2
				number.z_as_relative = false
				add_child(number)
				number.present("damage", int(hit["damage"]))
				BattlePoisonGasPresentation._shake(runtime, self, str(hit["unit_id"]))
		if tick >= end_tick:
			queue_free()

	func _sound(member: String) -> void:
		var entry: Dictionary = manifest["sounds"].get(member, {})
		if entry.is_empty():
			return
		var player := AudioStreamPlayer.new()
		player.stream = load(str(entry["res_path"]))
		add_child(player)
		player.play()

extends "res://game/battle/scene/SkillPresenter.gd"
## spec37 attacker shot -> spec38 map receivers, using original SP19 art/audio.
## Source tick counts are kept: attacker phase 80 ticks (shoot sound at 20), receiver
## phase 20 + 12 ticks to aniProcessHitMiss and 60 more to aniShowHitResult, object frames
## every shape_delay + 1 = 5 ticks. The arrows (obj_Special19_01／02, objcomd.txt commands
## 17／18) and the hit sparks (obj_Special19_03, command 19) move on their native tracks
## (ObjcomdMotion, objcomd_motion.json): the arrows hold 21 frames at (680,160), then fly left
## 32 px per tick until off screen; each spark sprays at a random angle and speed, fading in.
## The receiver phase is drawn on the map around the target, the stage offsets from the stage
## target centre (320,160) shrunk by the sprites' own scale (remake composition).
## This view never changes gameplay or the play loop's RNG.
## The cut-in routes 毒魔箭 here through skill_effects/manifest.json (`dedicated_module`).
## provenance:
##   layout: resource-derived content/imported/hsl/shared/poison_arrow/manifest.json
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##   layout: remake-invented (receiver phase on the map, scaled offsets; spark insertion offsets from a clip-seeded RNG)
##   timing: resource-derived content/imported/hsl/shared/poison_arrow/manifest.json
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   audio: resource-derived content/imported/hsl/shared/poison_arrow/manifest.json
var data: Dictionary
var backdrop: Sprite2D
var caster: Sprite2D
var portrait: Sprite2D
var detail: Sprite2D
var shade: ColorRect
var sprites: Array[Sprite2D] = []
var sounds: Array[AudioStreamPlayer] = []
var caption: Label
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const ObjcomdMotion = preload("res://game/battle/scene/ObjcomdMotion.gd")
## The special stage's target centre and the arrows' insertion point (specCode37／38).
const STAGE_TARGET := Vector2(320, 160)
const ARROW_POINT := Vector2(680, 160)
const ARROW_SCALE := 0.7
const SPARK_SCALE := 0.32
## aniInsertHitRandomObject obj_Special19_03,320,160,126,126,1,16.
const SPARK_RANGE := Vector2(126, 126)
const SPARK_DELAY := 1
const SPARK_COUNT := 16
var materials: Dictionary = {}
## One original tick on the cut-in's scaled clock: source delays play at the original rate
## (instance state following Timing.PLAYBACK_SPEED; a static var in a runtime-loaded
## presenter script keeps the script alive past exit).
var scaled_tick_seconds: float = Timing.scaled(OriginalTick.TICK_SECONDS)
## specCode37: objects at 0, SHOOT001 at aniDelay 20, phase ends after aniDelay 60.
const SHOOT_TICKS := 20
const ATTACKER_TICKS := 80
## specCode38: objects at 0, sound at 20, aniProcessHitMiss at 32, aniShowHitResult at 92.
const IMPACT_TICKS := 32
const RESULT_TICKS := 92
var receiver: float = ATTACKER_TICKS * scaled_tick_seconds

func schedule() -> Dictionary:
	return {"release": SHOOT_TICKS * scaled_tick_seconds, "impact": receiver + IMPACT_TICKS * scaled_tick_seconds, "complete": receiver + RESULT_TICKS * scaled_tick_seconds + Timing.RECOVERY}

func _ready() -> void:
	data = ContentPaths.read_json(ContentPaths.POISON_ARROW)
	for blend in ["add", "sub", "mix"]:
		var material := CanvasItemMaterial.new()
		material.blend_mode = {"add": CanvasItemMaterial.BLEND_MODE_ADD, "sub": CanvasItemMaterial.BLEND_MODE_SUB, "mix": CanvasItemMaterial.BLEND_MODE_MIX}[blend]
		materials[blend] = material
	shade = ColorRect.new()
	shade.color = Color.BLACK
	shade.size = Vector2(640,480)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	backdrop = Sprite2D.new()
	add_child(backdrop)
	portrait = Sprite2D.new()
	add_child(portrait)
	caster = Sprite2D.new()
	add_child(caster)
	detail = Sprite2D.new()
	add_child(detail)
	caption = Label.new()
	caption.position = Vector2(20, 16)
	caption.text = "毒魔箭"
	caption.add_theme_font_size_override("font_size", 24)
	caption.add_theme_constant_override("outline_size", 5)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(caption)
	for key in ["shoot", "shoot", "hit"]:
		var audio := AudioStreamPlayer.new()
		audio.stream = load(data["sounds"][key]["res_path"])
		add_child(audio)
		sounds.append(audio)
	hide()

func put(sprite: Sprite2D, record: Dictionary, point: Vector2, scale_value: float = 1.0) -> void:
	sprite.texture = load(record["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.position = point
	sprite.rotation = 0
	sprite.scale = Vector2.ONE * scale_value
	sprite.modulate = Color.WHITE
	sprite.show()

## Every sprite of `object`'s native track (seed `variant`) at `frame` ticks since its insertion,
## placed at `anchor` + offset × `scale`; returns the next sprite index.
func native(index: int, object: String, variant: int, frame: int, anchor: Vector2, scale_value: float = 1.0) -> int:
	for entry in ObjcomdMotion.sprites_at(object, variant, frame):
		var member := str(entry["member"])
		if not data["images"].has(member):
			continue
		while sprites.size() <= index:
			var sprite := Sprite2D.new()
			add_child(sprite)
			sprites.append(sprite)
		var sprite := sprites[index]
		put(sprite, data["images"][member], anchor + (entry["offset"] as Vector2) * scale_value, scale_value)
		sprite.scale = (entry["scale"] as Vector2) * scale_value
		sprite.material = materials[str(entry["blend"])]
		sprite.modulate.a = float(entry["alpha"])
		index += 1
	return index


## The receivers' map shot needs no combat-animation rows; the caster's panels come from
## `host.special_frames` with its own fallbacks.
func needs_actor_art(_strike: Dictionary) -> bool:
	return false


func present(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	show()
	hide_actors(host)
	host.stage.size = Vector2(640, 480)
	host.background.visible = false
	host.scenery.visible = false
	host.vitals.visible = false
	host.result.visible = false
	for sprite in sprites: sprite.hide()
	var timeline := schedule()
	if mark(host, clip, elapsed, timeline):
		hide()
		return true
	for index in range(3):
		var moment: float = [timeline["release"], receiver + SHOOT_TICKS * scaled_tick_seconds, timeline["impact"]][index]
		var key := "arrow_audio_" + str(index)
		if elapsed >= moment and not clip.get(key, false):
			clip[key] = true
			if index < 2 or bool(clip["strike"]["hit"]): sounds[index].play()
	backdrop.visible = elapsed < receiver
	shade.visible = elapsed < receiver
	portrait.visible = elapsed < receiver
	caster.visible = elapsed < receiver
	detail.visible = elapsed < receiver
	caption.visible = elapsed < receiver
	if elapsed < receiver:
		# The attacker phase: aniInsertSpecialBG SP00_003 with the arrow objects inserted at
		# tick 0 on their native tracks; the caster's panels are composed over it.
		put(backdrop, data["images"]["MAGIC\\SP00_003.SHP"], Vector2.ZERO)
		# P003_201 is a portrait strip,202 a face inset,203..206 the hand/draw
		# inset. They are not six full-body casting poses. Compose the unmodified
		# source panels in distinct slots; positions are remake staging.
		# A 003→012 弓聖 brings the 3-panel P012 strip (banner + two insets) into the
		# same three slots; the detail slot then holds its last panel.
		var frames: Array = host.special_frames(clip)
		if not frames.is_empty():
			put(portrait, frames[0], Vector2(320,104))
			put(caster, frames[mini(1, frames.size() - 1)], Vector2(174,306))
			put(detail, frames[mini(frames.size() - 1, 2+int(elapsed/receiver*4))], Vector2(480,306))
		var frame := int(elapsed / scaled_tick_seconds)
		native(native(0, "obj_Special19_01", 0, frame, ARROW_POINT), "obj_Special19_02", 0, frame, ARROW_POINT)
		return false
	var age := elapsed - receiver
	if elapsed < timeline["impact"]:
		# The arrows' tracks restart with specCode38 (inserted at tick 0 at (680,160)): by
		# aniProcessHitMiss at 32 they have flown 11 × 32 px to x = 328, over the target.
		var target: Vector2 = clip["map_target"] + Vector2(0,-26)
		var anchor := target + (ARROW_POINT - STAGE_TARGET) * ARROW_SCALE
		var frame := int(age / scaled_tick_seconds)
		native(native(0, "obj_Special19_01", 0, frame, anchor, ARROW_SCALE), "obj_Special19_02", 0, frame, anchor, ARROW_SCALE)
	else:
		# aniInsertHitRandomObject obj_Special19_03 ×16 at the hit: offsets within ±range/2 of
		# the target centre, each rand(delay) late (the same reading as SkillEffectScriptPlayer).
		var index := 0
		var rng := RandomNumberGenerator.new()
		var strike: Dictionary = clip["strike"]
		rng.seed = hash(str(strike.get("skill_id", "")) + str(strike.get("attacker_id", "")) + str(strike.get("defender_id", "")) + str(strike.get("hit_roll", "")))
		var sparks: Array = []
		for particle in range(SPARK_COUNT):
			sparks.append({"offset": Vector2(rng.randf_range(-SPARK_RANGE.x / 2.0, SPARK_RANGE.x / 2.0), rng.randf_range(-SPARK_RANGE.y / 2.0, SPARK_RANGE.y / 2.0)).round(),
				"wait": rng.randi_range(0, SPARK_DELAY), "variant": particle})
		var since := int((elapsed - float(timeline["impact"])) / scaled_tick_seconds)
		for point in clip["affected_positions"]:
			for spark in sparks:
				var frame: int = since - int(spark["wait"])
				if frame < 0: continue
				index = native(index, "obj_Special19_03", int(spark["variant"]) % ObjcomdMotion.variants("obj_Special19_03"), frame, point + Vector2(0, -26) + spark["offset"] * SPARK_SCALE, SPARK_SCALE)
	return false

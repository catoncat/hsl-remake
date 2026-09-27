extends "res://game/battle/scene/SkillPresenter.gd"
## spec37 attacker shot -> spec38 map receivers, using original SP19 art/audio.
## Source tick counts are kept: attacker phase 80 ticks (shoot sound at 20), receiver
## phase 20 + 12 ticks to aniProcessHitMiss and 60 more to aniShowHitResult, object frames
## every shape_delay + 1 = 5 ticks; trajectory and particle placement are remake composition.
## This view never changes gameplay or draws RNG.
## The cut-in routes 毒魔箭 here through skill_effects/manifest.json (`dedicated_module`).
## provenance:
##   layout: resource-derived content/imported/hsl/shared/poison_arrow/manifest.json
##   layout: remake-invented (trajectory and particle placement)
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
const FRAME_TICKS := 5
var receiver: float = ATTACKER_TICKS * scaled_tick_seconds

func schedule() -> Dictionary:
	return {"release": SHOOT_TICKS * scaled_tick_seconds, "impact": receiver + IMPACT_TICKS * scaled_tick_seconds, "complete": receiver + RESULT_TICKS * scaled_tick_seconds + Timing.RECOVERY}

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(preload("res://game/sim/ContentPaths.gd").POISON_ARROW))
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

func effect(index: int, group: String, age: float, point: Vector2, scale_value: float = 1.0) -> Sprite2D:
	while sprites.size() <= index:
		var sprite := Sprite2D.new()
		add_child(sprite)
		sprites.append(sprite)
	var frames: Array = data["groups"][group]
	put(sprites[index], data["images"][frames[mini(frames.size() - 1, maxi(0, int(age / (FRAME_TICKS * scaled_tick_seconds))))]], point, scale_value)
	return sprites[index]

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
		# tick 0 and flying left across the 80 ticks; the caster's panels are composed over it.
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
		# 760 px across the attacker phase: 9.5 px per tick (remake trajectory).
		var point := Vector2(680 - elapsed / scaled_tick_seconds * 9.5,160)
		effect(0,"obj_Special19_01",elapsed,point)
		effect(1,"obj_Special19_02",elapsed,point)
		return false
	var age := elapsed - receiver
	var impact_seconds := IMPACT_TICKS * scaled_tick_seconds
	var result_seconds := (RESULT_TICKS - IMPACT_TICKS) * scaled_tick_seconds
	if elapsed < timeline["impact"]:
		# 272 px in the 32 ticks to aniProcessHitMiss: 8.5 px per tick (remake trajectory).
		var target: Vector2 = clip["map_target"] + Vector2(0,-26)
		var point := target + Vector2((impact_seconds-age) / scaled_tick_seconds * 8.5,0)
		effect(0,"obj_Special19_01",age,point,0.7)
		effect(1,"obj_Special19_02",age,point,0.7)
	else:
		# aniInsertHitRandomObject obj_Special19_03 ×16 spread over the 60 ticks to the result.
		var index := 0
		for point in clip["affected_positions"]:
			for particle in range(16):
				var lifetime := elapsed-float(timeline["impact"])-particle*scaled_tick_seconds
				if lifetime < 0: continue
				var angle := particle * 2.4
				var radius := 0.45 + float(particle%4)*0.18
				var shift := Vector2(sin(angle)*44*radius,cos(angle)*28*radius-30-lifetime/scaled_tick_seconds*0.5)
				var sprite := effect(index,"obj_Special19_03",lifetime,point+shift,0.32)
				sprite.modulate.a = clampf((result_seconds-lifetime)/(result_seconds*0.3),0,1)
				index += 1
	return false

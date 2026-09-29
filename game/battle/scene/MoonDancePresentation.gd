extends "res://game/battle/scene/SkillPresenter.gd"
## Original Moon artwork and source delay ratios; only immutable receipt playback. The
## cut-in routes 月花圓舞 here through skill_effects/manifest.json (`dedicated_module`). The
## caster's ANIMAL s_action lead opens the clip the way every other 絶技 caster's does: the
## host's cast_lead over the combat manifest's 002 `special_frames` (P002_201..203, each panel
## at its SHP draw origin; AnimalCastLead.skipped with 預備動作 off), drawn by
## show_cast_lead; the empty attack script (specCode19) yields at once, so the target
## program (specCode20) starts on the lead's last call.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/moon_dance/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##     (002's s_action lead over its special_frames, via cast_lead)
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##     (petals obj_Special10_01 run objcomd.txt command 10, bursts obj_Special10_02 command 11, on their native tracks)
##   layout: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
##     (spawner 0x401390 placements and delays; bursts at the defender object + (60,−160), 0x403be2)
##   layout: provisional (petal／burst offsets from a target-seeded RNG; seed variants stand in for the shared stream)
##   timing: resource-derived content/generated/hsl/skills/moon_dance.json
##   timing: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##     (lead length = AnimalCastLead complete_tick)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   audio: resource-derived content/imported/hsl/shared/moon_dance/manifest.json
const RepeatedSpecialRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const ObjcomdMotion = preload("res://game/battle/scene/ObjcomdMotion.gd")
## specCode20: aniInsertRandomObject obj_Special10_01,360,0,480,0,6,64 after aniDelay 20;
## each pulse aniInsertHitRandomObjectDisp obj_Special10_02,60,-160,40,80,2,1.
const PETAL := "obj_Special10_01"
const BURST := "obj_Special10_02"
const PETAL_POINT := Vector2(360, 0)
const PETAL_RANGE := Vector2(480, 0)
const PETAL_DELAY := 6
const PETAL_COUNT := 64
const BURST_DISP := Vector2(60, -160)
const BURST_RANGE := Vector2(40, 80)
## Scaled-clock values follow Timing.PLAYBACK_SPEED (instance state: a static var in a
## runtime-loaded presenter script keeps the script alive past exit).
## One original tick on the cut-in's scaled clock: source delays play at the original rate.
var scaled_tick_seconds: float = Timing.scaled(OriginalTick.TICK_SECONDS)
const WIND_DELAY_TICKS := 20
var data: Dictionary
var assets: Dictionary
var pool: Array[Sprite2D] = []
var materials: Dictionary = {}
var wind: AudioStreamPlayer
var hit_sound: AudioStreamPlayer


func _ready() -> void:
	data = ContentPaths.read_json("res://content/generated/hsl/skills/moon_dance.json")
	assets = ContentPaths.read_json(ContentPaths.MOON_DANCE)
	for blend in ["add", "sub", "mix"]:
		var material := CanvasItemMaterial.new()
		material.blend_mode = {"add": CanvasItemMaterial.BLEND_MODE_ADD, "sub": CanvasItemMaterial.BLEND_MODE_SUB, "mix": CanvasItemMaterial.BLEND_MODE_MIX}[blend]
		materials[blend] = material
	wind = AudioStreamPlayer.new()
	wind.stream = load(assets["sounds"]["wind"]["res_path"])
	add_child(wind)
	hit_sound = AudioStreamPlayer.new()
	hit_sound.stream = load(assets["sounds"]["hit"]["res_path"])
	add_child(hit_sound)
	hide()


func reset() -> void:
	wind.stop()
	hit_sound.stop()
	hide()


## Every sprite of `object`'s native track (seed `variant`) at `frame` ticks since its insertion,
## placed at `anchor` + offset; returns the next pool index.
func native(host: CanvasLayer, index: int, object: String, variant: int, frame: int, anchor: Vector2) -> int:
	for entry in ObjcomdMotion.sprites_at(object, variant, frame):
		var member := str(entry["member"])
		if not assets["images"].has(member):
			continue
		while pool.size() <= index:
			var sprite := Sprite2D.new()
			add_child(sprite)
			pool.append(sprite)
		var sprite := pool[index]
		host._set_effect(sprite, assets["images"][member], anchor + (entry["offset"] as Vector2), 1.0)
		sprite.scale = entry["scale"]
		sprite.material = materials[str(entry["blend"])]
		sprite.modulate.a = float(entry["alpha"])
		sprite.show()
		index += 1
	return index


## The spawner 0x401390's placements for one insert: [offset, wait] per object, offsets
## rand(range) folded into (−range/2, range/2], the first with insertion delay 0, each next
## rand(delay) + 1 more; defProcObjectMove (0x405294) decrements +0xae before testing it, so
## delay d starts max(d − 1, 0) ticks after the insert (the wait returned).
static func spawn(rng: RandomNumberGenerator, span: Vector2, delay: int, count: int) -> Array:
	var placed: Array = []
	var wait := 0
	for _index in range(count):
		placed.append([Vector2(_fold(rng, int(span.x)), _fold(rng, int(span.y))), maxi(wait - 1, 0)])
		wait += (rng.randi_range(0, delay - 1) if delay > 0 else 0) + 1
	return placed


static func _fold(rng: RandomNumberGenerator, span: int) -> int:
	var width := maxi(span, 1)
	var value := rng.randi_range(0, width - 1)
	var half := int(width / 2)
	return half - value if value > half else value


## Pulse `index`'s settle time on the scaled clock, `intro` seconds of cast lead before the first target.
func impact_time(index: int, intro: float) -> float:
	return intro + (float(index / RepeatedSpecialRules.PULSES) * float(data["source_duration"]) + float(data["source_hit_delays"][index % RepeatedSpecialRules.PULSES])) * scaled_tick_seconds


func present(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	show()
	for sprite in pool: sprite.hide()
	host.blade.hide();host.flash_sprite.hide()
	host.scenery.texture = load(host.manifest["background"]["res_path"])
	var segments: Array = clip["strike"]["special_segments"]
	var target_count := segments.size() / RepeatedSpecialRules.PULSES
	var duration := float(data["source_duration"]) * scaled_tick_seconds
	# The caster's s_action lead ({} without an imported strip: the targets start at once).
	var lead: Dictionary = host.cast_lead(clip)
	var intro := float(lead.get("complete_tick", 0)) * scaled_tick_seconds
	var emitted := int(clip.get("moon_emitted", 0))
	while emitted < segments.size() and elapsed >= impact_time(emitted, intro):
		var part: Dictionary = segments[emitted]
		var target: Dictionary = clip["participants"][part["defender_id"]].duplicate(true)
		target.merge(part["defender_before"], true)
		var caster: Dictionary = clip["attacker_unit"].duplicate(true)
		caster.merge(part["attacker_before"], true)
		if not part["silent_after_defeat"] and part["hit"]: hit_sound.play()
		host.impact.emit(part, caster, target, false)
		emitted += 1
	clip["moon_emitted"] = emitted
	if elapsed >= intro + target_count * duration:
		reset()
		return true
	if elapsed < intro:
		host.show_cast_lead(clip, lead, elapsed / scaled_tick_seconds)
		host.result.visible = false
		host.result.text = ""
		if not clip["release_emitted"]:
			clip["release_emitted"] = true
			host.released.emit(clip["strike"],clip["attacker_unit"],clip["defender_unit"],false)
		return false
	var target_index := mini(target_count - 1, int((elapsed - intro) / duration))
	var local_time := elapsed - intro - target_index * duration
	var first_index := target_index * RepeatedSpecialRules.PULSES
	var active := first_index
	var impact_shown := emitted > first_index
	if impact_shown: active = mini(first_index + RepeatedSpecialRules.PULSES - 1, emitted - 1)
	var part: Dictionary = segments[active]
	var defender: Dictionary = clip["participants"][part["defender_id"]].duplicate(true)
	defender.merge(part["defender_before"], true)
	var shot := {"attacker_unit":clip["attacker_unit"], "defender_unit":defender, "strike":part, "impact_emitted":impact_shown, "known":clip["known"]}
	host._show_shot(shot, true)
	var hurt: bool = impact_shown and (part["hit"] or part["silent_after_defeat"])
	var actor_id: String = host.art_key(defender)
	host._set_frame(host.defender_sprite, actor_id, int(host.manifest["actors"][actor_id]["hurt_frame"]) if hurt else 0, CutinLayout.side_swapped(defender))
	var used := 0
	var tick := int(local_time / scaled_tick_seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(clip["strike"].get("skill_id", "")) + str(clip["attacker_unit"].get("id", "")) + str(target_index))
	var petal_spawn := spawn(rng, PETAL_RANGE, PETAL_DELAY, PETAL_COUNT)
	if local_time >= WIND_DELAY_TICKS * scaled_tick_seconds:
		if int(clip.get("moon_wind_target", -1)) != target_index:
			clip["moon_wind_target"] = target_index
			wind.stop();wind.play()
		for index in range(petal_spawn.size()):
			var frame: int = tick - WIND_DELAY_TICKS - int(petal_spawn[index][1])
			if frame >= 0:
				used = native(host, used, PETAL, index % ObjcomdMotion.variants(PETAL), frame, PETAL_POINT + petal_spawn[index][0])
	# One burst per hit pulse at the defender object + (60,−160), each on its native track.
	for pulse in range(first_index, emitted):
		var pulse_part: Dictionary = segments[pulse]
		if not pulse_part["hit"] or pulse_part["silent_after_defeat"]: continue
		var offset: Vector2 = spawn(rng, BURST_RANGE, 2, 1)[0][0]
		var frame := int((elapsed - impact_time(pulse, intro)) / scaled_tick_seconds)
		used = native(host, used, BURST, 0, frame, host.defender_sprite.position + BURST_DISP + offset)
	host.result.position.y = 272
	# _show_shot wrote the pulse's number alone (aniShowHitResult, UI6); a pulse on a fallen target shows nothing.
	if impact_shown and part["silent_after_defeat"]: host.result.text = ""
	return false

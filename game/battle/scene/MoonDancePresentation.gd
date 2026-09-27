extends "res://game/battle/scene/SkillPresenter.gd"
## Original Moon artwork and source delay ratios; only immutable receipt playback. The
## cut-in routes 月花圓舞 here through skill_effects/manifest.json (`dedicated_module`).
## provenance:
##   layout: resource-derived content/imported/hsl/shared/moon_dance/manifest.json
##   layout: remake-invented (particle paths and layout)
##   timing: resource-derived content/generated/hsl/skills/moon_dance.json
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: provisional
##     (the 1.5 s intro lead stands in for 002's s_action lead — read by AnimalCastLead, but 002's s_shape strip is not
##     in the combat manifest; petal／burst particle curves)
##   audio: resource-derived content/imported/hsl/shared/moon_dance/manifest.json
const RepeatedSpecialRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
## s_action lead, 1.5 s visible on the cut-in's scaled clock; the source lead is unread in ticks.
const INTRO_VISIBLE_SECONDS := 1.5
## Scaled-clock values follow Timing.PLAYBACK_SPEED (instance state: a static var in a
## runtime-loaded presenter script keeps the script alive past exit).
var intro: float = Timing.scaled(INTRO_VISIBLE_SECONDS)
## One original tick on the cut-in's scaled clock: source delays play at the original rate.
var scaled_tick_seconds: float = Timing.scaled(OriginalTick.TICK_SECONDS)
const WIND_DELAY_TICKS := 20
var data: Dictionary
var assets: Dictionary
var petals: Array[Sprite2D] = []
var bursts: Array[Sprite2D] = []
var wind: AudioStreamPlayer
var hit_sound: AudioStreamPlayer


func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/skills/moon_dance.json"))
	assets = JSON.parse_string(FileAccess.get_file_as_string(preload("res://game/sim/ContentPaths.gd").MOON_DANCE))
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for index in range(8):
		var sprite := Sprite2D.new()
		sprite.material = additive
		add_child(sprite)
		if index < 6: petals.append(sprite)
		else: bursts.append(sprite)
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


func impact_time(index: int) -> float:
	return intro + (float(index / RepeatedSpecialRules.PULSES) * float(data["source_duration"]) + float(data["source_hit_delays"][index % RepeatedSpecialRules.PULSES])) * scaled_tick_seconds


func present(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	show()
	for sprite in petals + bursts: sprite.hide()
	host.blade.hide();host.flash_sprite.hide()
	host.scenery.texture = load(host.manifest["background"]["res_path"])
	var segments: Array = clip["strike"]["special_segments"]
	var target_count := segments.size() / RepeatedSpecialRules.PULSES
	var duration := float(data["source_duration"]) * scaled_tick_seconds
	var emitted := int(clip.get("moon_emitted", 0))
	while emitted < segments.size() and elapsed >= impact_time(emitted):
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
		host._show_shot(clip, false)
		host.defender_sprite.hide()
		var frame_index := 0 if elapsed < 0.24 else 1 if elapsed < 0.42 else 2
		var frame: Dictionary = assets["images"][assets["groups"]["caster"][frame_index]]
		host.attacker_sprite.texture = load(frame["res_path"])
		host.attacker_sprite.centered = true
		host.attacker_sprite.offset = Vector2.ZERO
		host.attacker_sprite.scale = Vector2.ONE
		host.attacker_sprite.position = Vector2(320, 156)
		host.result.position.y = 272
		host.result.text = ""
		if elapsed >= 0.24:
			var shown: Dictionary = clip["attacker_unit"].duplicate(true)
			shown["stamina"] = clip["strike"]["resource_payment"]["after"]
			host.vitals.show_unit(shown)
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
	if local_time >= WIND_DELAY_TICKS * scaled_tick_seconds:
		if int(clip.get("moon_wind_target", -1)) != target_index:
			clip["moon_wind_target"] = target_index
			wind.stop();wind.play()
		for index in range(petals.size()):
			var t := maxf(0.0, local_time - WIND_DELAY_TICKS * scaled_tick_seconds)
			var point := Vector2(fposmod(650 - t * 560 + index * 101, 710) - 35, 58 + index * 39 + sin(t * 8 + index) * 26)
			var frame: Dictionary = assets["images"][assets["groups"]["421"][int(t * 25 + index) % 4]]
			host._set_effect(petals[index], frame, point, 1.4)
			petals[index].modulate.a = clampf((duration - local_time) / 0.35, 0, 1)
			petals[index].show()
	if impact_shown:
		var age := elapsed - impact_time(active)
		if part["hit"] and not part["silent_after_defeat"] and age < 0.3:
			for index in range(bursts.size()):
				var frame: Dictionary = assets["images"][assets["groups"]["422"][mini(3,int(age * 16))]]
				host._set_effect(bursts[index],frame,Vector2(285 + index*68,155 + index*42),0.65,index==1)
				bursts[index].modulate.a = clampf(1.0-age/0.3,0,1)
				bursts[index].show()
	host.result.position.y = 272
	# _show_shot wrote the pulse's number alone (aniShowHitResult, UI6); a pulse on a fallen target shows nothing.
	if impact_shown and part["silent_after_defeat"]: host.result.text = ""
	return false

extends CanvasLayer
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/combat_animation/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   layout: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_map_strike.md
##     (0x40418a hit flash)
##   layout: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md#7-普攻切入的攻方开场
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#12
##     (one full-size actor per shot over BG051; frame_001 whited-out board)
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (the zoom grows over the battlefield map, centred (320,240), before the white-out)
##   strings: resource-derived content/imported/hsl/shared/first_skill/manifest.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: remake-invented
##     (OPT-INFO=公開 only: cure labels, stat-buff captions, 未回復 and the weapon-effect line on the result line — effects
##     the original shows no glyph for)
##   timing: resource-derived content/imported/hsl/chapter01/combat_animation/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##     (defProcAttackFlash 0x401140)
##   timing: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   timing: remake-invented (the borrowed 氣刃斬 staging used only by synthetic clips)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json
## The presenters skill_effects/manifest.json names: `skill_effects` (the script player, every
## `script` row) and one node per `dedicated_module` file, each holding its routed rows. The
## first whose matches(strike) is true presents the clip; a strike none claims is an ordinary
## strike, or the borrowed 氣刃斬 staging when it carries a skill_name.
var presenters: Array[SkillPresenter] = []
## OPT-INFO=公開 (read as a queue starts): the result line's captions without an original glyph
## (caption_feedback, the weapon-effect line); the original path shows the numbers alone.
var captions_public := false
var skill_effects: SkillEffectScriptPlayer
signal impact(strike: Dictionary, attacker: Dictionary, defender: Dictionary, counter: bool)
signal released(strike: Dictionary, attacker: Dictionary, defender: Dictionary, counter: bool)
## A map spell's state-0 glide to the caster starts／ends (SkillEffectScriptPlayer._hold_caption).
signal cast_caption_held(held: bool)
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
## Original attack frames and delay order in a compact remake presentation. The source pose
## order runs at Timing.PLAYBACK_SPEED × the original tick rate (1.0 unless the developer
## switch slows it).
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const SkillPresenter = preload("res://game/battle/scene/SkillPresenter.gd")
const SkillEffectScriptPlayer = preload("res://game/battle/scene/SkillEffectScriptPlayer.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const AnimalCastLead = preload("res://game/battle/scene/AnimalCastLead.gd")
const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const StatusCatalog = preload("res://game/sim/StatusCatalog.gd")
const ShowNumberStyle = preload("res://game/battle/runtime/ShowNumberStyle.gd")
const ResultNumberFloater = preload("res://game/battle/scene/ResultNumberFloater.gd")
const AdditiveLevelBlend = preload("res://game/battle/scene/AdditiveLevelBlend.gd")
## The word of the NUM513 glyph: a miss reads MISS on the result line and the map (0x404643 kind 5).
const MISS_TEXT := "MISS"
## 0x404290: an ordinary shot's defender object spawns its red damage number at (320, camera
## y + 200), 40 ticks after the hit — screen (320, 200).
const ORDINARY_NUMBER_POINT := Vector2(320, 200)
## aniShowHitResult (0x404643): a script shot's numbers at (320, camera y + 180).
const SCRIPT_NUMBER_POINT := Vector2(320, 180)
## The hit flash's y: camera y + 0xb4 (0x40416f..0x404181).
const HIT_FLASH_Y := 180.0
const PRESENTER_DIRECTORY := "res://game/battle/scene/"
## The scene's combat manifest (hsl_combat_animation rows: frames, dispatch, strips, the
## backdrop and opening shape), set by configure() from the scenario's
## `resources.combat_animation`: chapter-1 levels name the imported chapter-1 manifest, an
## authored level its generated one (hsltools.levels.authored). {} until configured — every
## clip then takes the no-art path and the first play() reports the missing manifest.
var manifest: Dictionary = {}
var manifest_path := ""
var _reported_unconfigured := false
var clips: Array[Dictionary] = []
var elapsed := 0.0
## OPT-PACE (docs/OPTIONS.md), read once as an exchange's first clip is queued (play on an empty
## queue): the multiplier on this node's frame delta (Timing.PACE_CUTIN) and, under 極快,
## the close-up layer hidden while the clips still run in order.
var pace := 1.0
var cutin_hidden := false
var panel: Control
var background: ColorRect
var attacker_sprite: Sprite2D
var defender_sprite: Sprite2D
var flash_sprite: Sprite2D
## The receiver's hit flash (0x40418a): ANIMAL\ATTACK_FLASH00N.SHP by the attacker weapon's icon class.
var hit_flash_sprite: Sprite2D
## The result line: only the captions the original has no glyph for (cure／buff words, the
## weapon-effect line); the numbers are `result_number`'s original glyphs.
var result: Label
## The result numbers of the current shot (ResultNumberFloater children, clocked by the clip).
var result_number: Node2D
## The previous shot's numbers still alive when the next shot takes over: obj_ShowNumber is its
## own object (0x4084e0), so a continuation (phase 101 sub 0 → 2 at once, no transition) leaves
## a red number's last ticks — released at 27 ＋ 10×digits, deleted at 34 ＋ 10×digits — drawn
## over the next shot until 0x408580 deletes it.
var result_tail: Node2D
var _result_key: Array = []
var skill: Dictionary
var blade: Sprite2D
var ability_sound: AudioStreamPlayer
var scenery: TextureRect
var stage: Control
var vitals: Control
var sparks: Array[Sprite2D] = []
var cue_manifest: Dictionary
## The cast lead's inset and portrait panels (the banner is the attacker sprite itself).
var cast_inset: Sprite2D
var cast_portrait: Sprite2D
## The cast lead's afterimages (AnimalCastLead `afterimages`), created on demand: a banner copy
## (panel 0) under the banner, an inset copy over the live inset and portrait.
var cast_afterimages: Array[Sprite2D] = []
## Compiled AnimalCastLead per combat manifest row (deterministic: program × panel sizes).
var cast_leads: Dictionary = {}
## The opening ball (MAGIC\BALL001.SHP) and the closing transition shade, drawn over the whole
## 640×480 panel including the identity board (the original's layer 0x34 and the transition's
## top layer both sit above the actor and window layers).
var opening_ball: Sprite2D
var opening_add_material: CanvasItemMaterial
var transition_shade: ColorRect
## The map spell's screen ripple (effProcIconBGSet, SkillEffectScriptPlayer._effect_view): a
## full-view rect last in the battle World that redraws the map and units already drawn with
## 0x461687's per-row x offsets. Built on first use; hidden every frame unless re-shown.
var effect_ripple: ColorRect
## The map spell's colour change (effProcIconBGSet, SkillEffectScriptPlayer._effect_view): the
## material the map backdrop and the plain stand objects draw with while it shows, the nodes
## that carry it, and whether this frame asked for it (a frame without a request restores them).
var effect_tint_material: ShaderMaterial
var _effect_tinted: Array = []
var _effect_tint_requested := false
## The cast shadow (shade_map): the level 0..8 this frame and its black rect in the battle World.
var map_shadow_level := 0
var map_shadow: ColorRect
## The map spell effect phase, [0x4c1b00] & 0x1000000 — the one source the shadow, the cast lift
## and the shadows' hold read (BattleSceneStage.spell_effect_phase). The cast routine 0x442a90
## sets it in states 4／7／0x17／0x19 (0x442c77, 0x442cf5, 0x442f53, 0x442ff7), after the lead's
## sub-state 5 steps the VM (0x40309e): SkillEffectScriptPlayer._present_effect on sub-state 5's
## call, the one after the caster poses.
## Both run only once the effect script reaches op 0 (0x4239ac steps the routine's state):
## eff_proc_Global clears it at state 9's entry (0x442da3), before the first receiver's glide
## and bars; eff_proc_Local after the last receiver's bars go (0x443271). The effect clip clears
## it at its script end (SkillEffectScriptPlayer `script_end_tick`) unless a relay holds it
## (`spell_phase_held`); MagicImpactPresentation lets go after the last bars and the last
## replay's script end (release_spell_phase).
## While it holds, object 154's sub-state 6 (0x4030b7) keeps the shadow at level 8; once clear
## it takes one level a call from +0x90 and draws down to 0, then deletes itself: 7..0 (8 calls)
## after a strip lead (+0x90 = 8), 8..0 (9 calls) after the 預備動作-off lead, whose sub-state 7
## leaves at +0x90 = 9 (0x4030fe `cmp` against 8 from 0x401f17, `jbe`).
var spell_phase := false
## The strike whose effect phase holds (the lift footprint outlives the clip for Local).
var spell_strike: Dictionary = {}
## True while MagicImpactPresentation owns the clear (eff_proc_Local's receivers).
var spell_phase_held := false
## Sub-state 6's fade after the clear: map-clock seconds since it started, < 0 when none runs.
var _shade_fade := -1.0
var _shade_fade_pace := 1.0
## The level the fade draws on its first call (+0x90 − 1 at the clear).
var _shade_fade_from := AnimalCastLead.SHADOW_MAX_LEVEL - 1
const EFFECT_RIPPLE_SHADER := """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float offsets[480];
void fragment() {
	int row = clamp(int(SCREEN_UV.y * 480.0), 0, 479);
	COLOR = texture(screen_texture, SCREEN_UV - vec2(offsets[row] / 640.0, 0.0));
}
"""
## Draw kind 2 (0x46ac63, mode 0x10000000 through 0x46b691): each drawn pixel of the shape
## becomes ((pixel & 0xf7de) + (colour & 0xf7de)) >> 1 — the half mix of the shape's own pixel
## and the colour, over whatever the screen held. `tint` is the colour with each channel's
## lowest bit already dropped; the pixel's is not.
const EFFECT_TINT_SHADER := """shader_type canvas_item;
uniform vec3 tint = vec3(0.0);
void fragment() {
	COLOR.rgb = (COLOR.rgb + tint) * 0.5;
}
"""


func _ready() -> void:
	layer = 5
	panel = Control.new()
	add_child(panel)
	background = ColorRect.new()
	background.size = Vector2(640, 480)
	background.color = Color(0.015, 0.025, 0.04)
	panel.add_child(background)
	scenery = TextureRect.new()
	scenery.name = "OriginalBattleBackdrop"
	scenery.position = Vector2.ZERO
	scenery.size = Vector2(640, 320)
	panel.add_child(scenery)
	# Native framing: one full-size actor per shot, cropped at the status board.
	stage = Control.new()
	stage.size = Vector2(640, 320)
	stage.clip_contents = true
	panel.add_child(stage)
	attacker_sprite = Sprite2D.new()
	stage.add_child(attacker_sprite)
	defender_sprite = Sprite2D.new()
	stage.add_child(defender_sprite)
	flash_sprite = Sprite2D.new()
	stage.add_child(flash_sprite)
	hit_flash_sprite = Sprite2D.new()
	hit_flash_sprite.hide()
	stage.add_child(hit_flash_sprite)
	cast_inset = Sprite2D.new()
	cast_inset.hide()
	stage.add_child(cast_inset)
	cast_portrait = Sprite2D.new()
	cast_portrait.hide()
	stage.add_child(cast_portrait)
	vitals = preload("res://game/battle/scene/BattleVitals.gd").new()
	vitals.position = Vector2(0, 322)
	vitals.resist_gem_at = vitals.RESIST_STRIP_GEM_AT
	panel.add_child(vitals)
	# 0x43b4e0 mode 2 (0x403512／0x404bf3 push 2) sets the ST object's 0x10000: shared pulse.
	vitals.st_bar.shared_pulse = true
	result = Label.new()
	result.position = Vector2(32, 264)
	result.size = Vector2(576, 44)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 20)
	result.add_theme_constant_override("outline_size", 5)
	result.add_theme_color_override("font_outline_color", Color(0.03, 0.025, 0.02))
	panel.add_child(result)
	result_number = Node2D.new()
	result_number.name = "ResultNumber"
	result_number.hide()
	panel.add_child(result_number)
	result_tail = Node2D.new()
	result_tail.name = "ResultTail"
	panel.add_child(result_tail)
	opening_ball = Sprite2D.new()
	opening_ball.hide()
	opening_ball.position = Vector2(320, 240)
	panel.add_child(opening_ball)
	opening_add_material = CanvasItemMaterial.new()
	opening_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	transition_shade = ColorRect.new()
	transition_shade.color = Color.BLACK
	transition_shade.size = Vector2(640, 480)
	transition_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_shade.hide()
	panel.add_child(transition_shade)
	_build_skill_layers()


## _ready, continued: cue／skill manifests, the blade, sparks and ability sound, the additive
## light material, and the skill presenters (dedicated modules, then the script player).
func _build_skill_layers() -> void:
	cue_manifest = ContentPaths.read_json(ContentPaths.INTERFACE_AUDIO)
	skill = ContentPaths.read_json(ContentPaths.FIRST_SKILL)
	blade = Sprite2D.new()
	stage.add_child(blade)
	for i in range(5):
		var spark := Sprite2D.new()
		spark.hide()
		stage.add_child(spark)
		sparks.append(spark)
	ability_sound = AudioStreamPlayer.new()
	ability_sound.stream = load(skill["sound"]["res_path"])
	add_child(ability_sound)
	# Remake compositing: these light effects contain black RGB padding.
	var light_material := CanvasItemMaterial.new()
	light_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	blade.material = light_material
	# defProcAttackFlash draws engADDCOLOR_MIX: dst + src × level／16 (modulate alpha = level／16).
	flash_sprite.material = AdditiveLevelBlend.material()
	hit_flash_sprite.material = AdditiveLevelBlend.material()
	for spark in sparks:
		spark.material = light_material
	panel.hide()
	skill_effects = SkillEffectScriptPlayer.new()
	stage.add_child(skill_effects)
	var modules := {}
	for skill_id in skill_effects.manifest["rows"]:
		var row: Dictionary = skill_effects.manifest["rows"][skill_id]
		if str(row["presentation"]) != "dedicated_module":
			continue
		var module := str(row["module"])
		if not modules.has(module):
			modules[module] = load(PRESENTER_DIRECTORY + module).new()
			stage.add_child(modules[module])
			presenters.append(modules[module])
		modules[module].skill_ids.append(str(skill_id))
	presenters.append(skill_effects)


## Loads the scene's combat manifest (`resources.combat_animation`). Call after the node is
## in the tree. A path that does not parse is reported and leaves the cut-in unconfigured
## (no other manifest is tried).
func configure(path: String) -> bool:
	manifest_path = path
	manifest = {}
	cast_leads.clear()
	var parsed: Variant = ContentPaths.read_json(path) if path != "" and FileAccess.file_exists(path) else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actors")) != TYPE_DICTIONARY:
		push_error("Combat cut-in manifest missing or invalid: %s" % path)
		return false
	manifest = parsed
	scenery.texture = load(manifest["background"]["res_path"])
	_apply_source_frame(opening_ball, manifest["opening"])
	return true


## `known` maps a unit id to BattlePlayLoop.unit_known over the exchange's known set at
## target confirmation: the strip in the shot masks a unit no attack has yet targeted
## (0x436490 mode 3 builds the cut-in text through the same 0x434d10 block). A unit absent
## from the map is shown known.
## `first_shot`／`last_shot` place the clip in its exchange (primary strike, extra strikes,
## counter and its extras): the first ordinary shot plays the attacker's phase-100 opening,
## the last (or one that kills the defender) the screen transition; a lone clip is both.
func play(strike: Dictionary, attacker: Dictionary, defender: Dictionary, counter: bool, map_target: Vector2 = Vector2(320, 240), map_caster: Vector2 = Vector2(240, 240), affected_positions: Array = [], participants: Array = [], known: Dictionary = {}, first_shot: bool = true, last_shot: bool = true) -> void:
	if manifest.is_empty() and not _reported_unconfigured:
		_reported_unconfigured = true
		push_error("Combat cut-in played without a combat manifest: the scenario declares no resources.combat_animation")
	if clips.is_empty():
		captions_public = not GameOptions.is_original("OPT-INFO")
		var pace_value := GameOptions.value("OPT-PACE")
		pace = float(Timing.PACE_CUTIN.get(pace_value, 1.0))
		if cutin_hidden != (pace_value == Timing.PACE_HIDDEN_CUTIN):
			cutin_hidden = not cutin_hidden
			visible = not cutin_hidden
	var attacker_view := attacker.duplicate(true)
	var defender_view := defender.duplicate(true)
	attacker_view.merge(strike.get("attacker_before", {}), true)
	defender_view.merge(strike.get("defender_before", {}), true)
	clips.append({"attacker": art_key(attacker), "defender": art_key(defender), "attacker_base": str(attacker["actor_id"]), "strike": strike.duplicate(true), "attacker_unit": attacker_view, "defender_unit": defender_view, "counter": counter, "impact_emitted": false, "release_emitted": false, "map_target": map_target, "map_caster": map_caster, "affected_positions": affected_positions.duplicate() if not affected_positions.is_empty() else [map_target], "known": known.duplicate(), "first_shot": first_shot, "last_shot": last_shot})
	if strike.has("special_segments"):
		var views := {}
		for unit in participants: views[unit["id"]] = unit.duplicate(true)
		views[attacker["id"]] = attacker_view
		views[defender["id"]] = defender_view
		clips.back()["participants"] = views


## Ordinary cut-in row (frames/hurt_frame/flash/dispatch): the unit's job-up target row when
## the combat manifest carries it (010–017／019／020／052 imported; 018 is not), else its base
## actor id — the same lookup rule as walk frames (ActorSpriteKey.frame_key).
func art_key(unit: Dictionary) -> String:
	return ActorSpriteKey.frame_key(unit, [manifest])


## Special-skill panels: the ANIMAL `s_shape` strip of the row the attacker cuts in with
## (`art_key`: the job-up target row when imported — 010／012／013／016／017／019／020 carry a
## 3-panel strip of eye banner + two insets, the same shape as 002's strip), else
## the base row's strip (001's seven 氣刃斬 cast panels, 003's six 毒魔箭 portrait／insets,
## 002／004／006／007／009's 3／4-panel strips, the monsters 053–055／057), else [] — every combat
## manifest row declares `special_frames` (`[]` = the ANIMAL block declares no strip, e.g. 056;
## manifest `special_frames_policy`) and the
## cut-in then shows the caster's standing frame. A row without the declaration is a data error: it is
## reported and treated as [] so the clip still completes.
func special_frames(clip: Dictionary) -> Array:
	for row in [str(clip["attacker"]), str(clip["attacker_base"])]:
		var actor: Dictionary = manifest["actors"].get(row, {})
		if actor.is_empty():
			continue
		if not actor.has("special_frames"):
			push_error("Combat manifest row without a special_frames declaration: " + row)
			continue
		var strip: Array = actor["special_frames"]
		if not strip.is_empty():
			return strip
	return []


## The caster's compiled ANIMAL cast lead of one channel — `"special"` (s_action over the
## s_shape strip `special_frames`／`cast_program`) or `"magic"` (m_action over the m_shape strip
## `magic_frames`／`magic_cast_program`): the first combat manifest row (art row, then base row)
## that carries both the imported strip and its program; {} when the caster has no strip (the
## 絶技 cut-in then shows the standing caster, the map magic presenter rings the caster with
## Cast_Star — the manifest's `cast_program_policy`／`magic_cast_program_policy`). The compiled
## states are cached per row and channel; the lead remembers its strip. With 預備動作 off
## (GameSettings `ready_action`, read per call like the original's per-cast 0x401e74) a caster
## with a lead gets AnimalCastLead.skipped instead; one without keeps its stand-in either way,
## as the original takes the same branch for both.
func cast_lead(clip: Dictionary, channel: String = "special") -> Dictionary:
	var strip_key := "magic_frames" if channel == "magic" else "special_frames"
	var program_key := "magic_cast_program" if channel == "magic" else "cast_program"
	for row in [str(clip["attacker"]), str(clip["attacker_base"])]:
		var actor: Dictionary = manifest["actors"].get(row, {})
		var strip: Array = actor.get(strip_key, [])
		var program: Array = actor.get(program_key, [])
		if strip.is_empty() or not AnimalCastLead.playable(program, strip.size()):
			continue
		if not GameSettings.ready_action_enabled():
			var skipped_key := channel + ":skipped"
			if not cast_leads.has(skipped_key):
				cast_leads[skipped_key] = AnimalCastLead.skipped(channel == "magic")
			return cast_leads[skipped_key]
		# A side-swapped caster (0x446be0) plays the mirrored lead.
		var mirrored := CutinLayout.side_swapped(clip.get("attacker_unit", {}))
		var key: String = row + ":" + channel + (":mirrored" if mirrored else "")
		if not cast_leads.has(key):
			var textures: Array = []
			for frame in strip:
				textures.append(load(frame["res_path"]))
			cast_leads[key] = AnimalCastLead.compile(program, AnimalCastLead.panel_metrics(strip, textures), mirrored, channel == "magic")
			cast_leads[key]["row"] = row
			cast_leads[key]["strip"] = strip
		return cast_leads[key]
	return {}


## Draws the cast lead's state at `tick` (whole original ticks since the clip began): the map
## shows through the 640×480 stage (a spell or 絶技 object sets +0x80 0x100 at 0x401e66, so the
## black backdrop of 0x4034c6 is skipped), under a black layer at shadow level／16 (0x4035ef:
## [0x4bbb4e] crossfaded into bucket 0x17 — each map component × (16 − level)／16); the banner
## (panel 0) is the attacker sprite (x zoom −1 when mirrored), the inset and portrait panels
## their own opaque sprites (mode 0), each afterimage a copy at level／16 (engMIX: src ×
## level/16 + dst × (16 − level)/16). Order as the buckets give it: banner afterimage
## (planeEffect2) < banner (0x32) < inset, portrait (0x33, submitted by the process in the first
## pass) < inset afterimages (0x33, object 179 submitted in the second pass of 0x45f5f7). Sub-state
## 4's centred glow (`glow`, 0x403052) is the opening ball at AnimalCastLead.GLOW_ZOOM added at
## level／16, submitted after the panels in the same bucket.
func show_cast_lead(clip: Dictionary, lead: Dictionary, tick: float) -> void:
	var states: Array = lead["states"]
	var state: Dictionary = states[clampi(int(tick), 0, states.size() - 1)]
	var strip: Array = lead["strip"]
	stage.size = Vector2(640, 480)
	scenery.visible = false
	vitals.visible = false
	shade_map(int(state["shadow"]))
	defender_sprite.hide()
	blade.hide()
	flash_sprite.hide()
	var faded := 1.0 - float(state["fade"])
	# 預備動作 off (AnimalCastLead.skipped): the caster object is hidden, 0x401ecc.
	attacker_sprite.visible = not bool(state.get("hidden", false))
	if attacker_sprite.visible:
		_apply_source_frame(attacker_sprite, strip[0])
		attacker_sprite.position = Vector2(state["banner"])
		attacker_sprite.scale = Vector2(-1, 1) if bool(state["mirrored"]) else Vector2.ONE
		attacker_sprite.modulate = Color.WHITE
	var ghosts: Array = state["afterimages"]
	for index in range(ghosts.size()):
		var ghost: Dictionary = ghosts[index]
		var sprite := _cast_afterimage(index)
		if int(ghost["panel"]) == 0:
			if sprite.get_index() > attacker_sprite.get_index():
				stage.move_child(sprite, attacker_sprite.get_index())
		elif sprite.get_index() < cast_portrait.get_index():
			stage.move_child(sprite, cast_portrait.get_index())
		_apply_source_frame(sprite, strip[int(ghost["panel"])])
		sprite.position = Vector2(ghost["anchor"])
		sprite.scale = Vector2(-1, 1) if bool(ghost["mirrored"]) else Vector2.ONE
		sprite.modulate = Color(1, 1, 1, float(ghost["level"]) / AnimalCastLead.LEVELS)
		sprite.show()
	for entry in [[cast_inset, "inset"], [cast_portrait, "portrait"]]:
		var sprite: Sprite2D = entry[0]
		var panel := int(state[entry[1]])
		sprite.visible = panel >= 0
		if panel >= 0:
			_apply_source_frame(sprite, strip[panel])
			sprite.position = Vector2(state[entry[1] + "_anchor"])
			sprite.modulate = Color(1, 1, 1, faded)
	var glow := int(state.get("glow", 0))
	if glow > 0:
		opening_ball.material = opening_add_material
		opening_ball.scale = Vector2.ONE * AnimalCastLead.GLOW_ZOOM
		var level := float(glow) / AnimalCastLead.LEVELS
		opening_ball.modulate = Color(level, level, level, 1)
		opening_ball.show()


## The `index`-th afterimage sprite, created on first use (show_cast_lead places it).
func _cast_afterimage(index: int) -> Sprite2D:
	while cast_afterimages.size() <= index:
		var sprite := Sprite2D.new()
		sprite.hide()
		stage.add_child(sprite)
		cast_afterimages.append(sprite)
	return cast_afterimages[index]


func busy() -> bool:
	return not clips.is_empty()


## The battle's camera controller (BattleSceneRuntime.camera_controller); null outside a battle.
func battle_camera() -> RefCounted:
	var runtime: Node = get_parent().get_parent() if get_parent() != null else null
	return runtime.get("camera_controller") if runtime != null else null


## Shows this frame's ripple (EffectObjectMotion.ripple_at parameters) over the battle World's
## map and units; {} leaves it hidden.
## The cast shadow at `level`／16: 0x4035ef draws the all-black shape at the camera origin into
## bucket 0x17 (mode 0x20000000), so the map and every unit in a bucket < 0x17 darken while the
## units the spell effect phase lifts 23 buckets (ActorRuntime.CAST_LIFT_Z, submitted in the
## second pass of the same bucket) and the planeEffect／panel buckets above stay lit. The remake
## draws it as a black rect in the battle World just under CAST_LIFT_Z (over every foot-y z,
## under the lifted band and FIXED_PLANE_ABOVE_Z); the cut-in panel's own backdrop stays off.
## Outside a battle scene only the level is kept. Reset every frame in _process.
func shade_map(level: int) -> void:
	map_shadow_level = level
	background.visible = false
	var camera := battle_camera()
	var world: Node = get_parent().get_parent().get_node_or_null("World") if camera != null else null
	if level <= 0 or world == null or camera.camera == null:
		if map_shadow != null:
			map_shadow.hide()
		return
	if map_shadow == null:
		map_shadow = ColorRect.new()
		map_shadow.name = "CastShadow"
		map_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_shadow.z_index = ActorRuntime.CAST_LIFT_Z - 1
	if map_shadow.get_parent() != world:
		world.add_child(map_shadow)
	map_shadow.size = Vector2(camera.logical_viewport_size)
	map_shadow.position = camera.logical_to_world(Vector2.ZERO)
	map_shadow.color = Color(0, 0, 0, float(level) / AnimalCastLead.LEVELS)
	map_shadow.show()


## Sets the map spell effect phase for `strike` (the shadow holds at level 8 from this frame);
## `fade_from` is the level the fade after the clear starts at (7 after a strip lead, 8 after
## the 預備動作-off lead).
func begin_spell_phase(strike: Dictionary, fade_from: int = AnimalCastLead.SHADOW_MAX_LEVEL - 1) -> void:
	spell_phase = true
	spell_strike = strike
	spell_phase_held = false
	_shade_fade = -1.0
	_shade_fade_from = fade_from
	shade_map(AnimalCastLead.SHADOW_MAX_LEVEL)


## Clears the map spell effect phase; object 154's fade (fade_from..0) runs from the next frame
## on the map clock (OPT-PACE, Timing.PACE_MAP), whether or not a clip or relay still runs.
func end_spell_phase() -> void:
	if not spell_phase:
		return
	spell_phase = false
	spell_strike = {}
	spell_phase_held = false
	_shade_fade = 0.0
	_shade_fade_pace = float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0))


## The Local relay lets go of the clear: the phase ends now, or at the effect clip's script end
## when that clip is still short of its op 0.
func release_spell_phase() -> void:
	spell_phase_held = false
	if busy() and is_same(clips[0]["strike"], spell_strike) and not bool(clips[0].get("script_ended", false)):
		return
	end_spell_phase()


## This frame's sub-state 6 shadow: level 8 while the phase holds, then fade_from..0 one per
## tick — the first frame after the clear draws fade_from, the clock advancing after the draw.
func _shade_spell_phase(delta: float) -> void:
	if spell_phase:
		shade_map(AnimalCastLead.SHADOW_MAX_LEVEL)
		return
	if _shade_fade < 0.0:
		return
	var level := _shade_fade_from - int(OriginalTick.ticks(_shade_fade))
	_shade_fade += maxf(0.0, delta) * _shade_fade_pace
	if level <= 0:
		_shade_fade = -1.0
		return
	shade_map(level)


func show_effect_ripple(params: Dictionary) -> void:
	var camera := battle_camera()
	var world: Node = get_parent().get_parent().get_node_or_null("World") if camera != null else null
	if params.is_empty() or world == null or camera.camera == null:
		if effect_ripple != null:
			effect_ripple.hide()
		return
	if effect_ripple == null:
		effect_ripple = ColorRect.new()
		effect_ripple.name = "EffectRipple"
		effect_ripple.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := Shader.new()
		shader.code = EFFECT_RIPPLE_SHADER
		effect_ripple.material = ShaderMaterial.new()
		effect_ripple.material.shader = shader
	if effect_ripple.get_parent() != world:
		world.add_child(effect_ripple)
	world.move_child(effect_ripple, -1)
	effect_ripple.size = Vector2(camera.logical_viewport_size)
	effect_ripple.position = camera.logical_to_world(Vector2.ZERO)
	effect_ripple.material.set_shader_parameter("offsets", SkillEffectScriptPlayer.EffectObjectMotion.ripple_rows(params))
	effect_ripple.show()


## The presenter the manifest routes this clip's strike to; null for an ordinary strike or
## the borrowed staging. Remembered on the clip so a queue of clips keeps one route each.
func _presenter(clip: Dictionary) -> SkillPresenter:
	if clip.has("presenter"):
		return clip["presenter"]
	clip["presenter"] = null
	for presenter in presenters:
		if presenter.matches(clip["strike"]):
			clip["presenter"] = presenter
			break
	return clip["presenter"]


func _complete_clip() -> void:
	clips.pop_front()
	elapsed = 0.0
	panel.visible = busy()
	# The next shot spawns its own numbers; this shot's live ones finish their own clock.
	_result_key = []
	for number in result_number.get_children():
		if busy() and number.visible:
			number.reparent(result_tail, false)
		else:
			number.free()


## Shows this frame's colour change (EffectObjectMotion.tint_at: RGB565 channels, alpha 0 for
## none). The original sets mode 0x10000000 and colour +0x28 on the map it draws (0x430370:
## the object itself, or every tile through 0x46bf6f) and, at the stand-object procedure's
## tail (0x43d853), on each stand object whose mode lacks engADDCOLOR (0x4000000), clearing
## engMIX; the mode comes back from +0xa0 the next tick (0x43ce53). Units and effect objects
## never read it. The remake gives the map backdrop, the backdrop-layer pictures and the
## stand-object sprites drawn plain (no material of their own) the half-mix material; the
## glass, additive and animated ones keep theirs.
func show_effect_tint(colour: Color) -> void:
	var world: Node = get_parent().get_parent().get_node_or_null("World") if get_parent() != null and get_parent().get_parent() != null else null
	if colour.a <= 0.0 or world == null:
		_restore_effect_tint()
		return
	_effect_tint_requested = true
	if effect_tint_material == null:
		var shader := Shader.new()
		shader.code = EFFECT_TINT_SHADER
		effect_tint_material = ShaderMaterial.new()
		effect_tint_material.shader = shader
	var r := int(colour.r) & 0x1e
	var g := int(colour.g) & 0x3e
	var b := int(colour.b) & 0x1e
	effect_tint_material.set_shader_parameter("tint", Vector3(float(r) / 31.0, float(g) / 63.0, float(b) / 31.0))
	var targets: Array = [world.get_node_or_null("MapBackdrop")]
	for child in world.get_children():
		if child.get_meta("runtime_layer", "") == "backdrop":
			targets.append(child)
	for layer_name in ["MapObjectsBack", "MapObjectsForeground"]:
		var layer: Node = world.get_node_or_null(layer_name)
		if layer == null: continue
		# Only defProcStandObject reads the tint (0x43d853); chests (0x415730) and level 12's
		# hull pieces (enemy process 0x443330) share the layer but do not.
		for child in layer.get_children():
			if str(child.get_meta("process_code", "")) == "defProcStandObject":
				targets.append(child)
	for node in targets:
		if node is CanvasItem and (node.material == null or node.material == effect_tint_material):
			node.material = effect_tint_material
			if not _effect_tinted.has(node):
				_effect_tinted.append(node)


func _restore_effect_tint() -> void:
	for node in _effect_tinted:
		if is_instance_valid(node) and node.material == effect_tint_material:
			node.material = null
	_effect_tinted.clear()


func _process(delta: float) -> void:
	var map_delta := delta
	delta *= pace
	for presenter in presenters:
		presenter.hide()
	if effect_ripple != null:
		effect_ripple.hide()
	if not _effect_tint_requested and not _effect_tinted.is_empty():
		_restore_effect_tint()
	_effect_tint_requested = false
	map_shadow_level = 0
	if map_shadow != null:
		map_shadow.hide()
	_shade_spell_phase(map_delta)
	cast_inset.hide()
	cast_portrait.hide()
	hit_flash_sprite.hide()
	for ghost in cast_afterimages:
		ghost.hide()
	opening_ball.hide()
	transition_shade.hide()
	result_number.hide()
	scenery.modulate = Color.WHITE
	panel.visible = busy()
	for number in result_tail.get_children():
		if not busy() or not number.advance(delta):
			number.free()
	if not busy():
		return
	elapsed += delta * Timing.PLAYBACK_SPEED
	var clip: Dictionary = clips[0]
	var presenter: SkillPresenter = _presenter(clip)
	var actor_manifest: Dictionary = manifest.get("actors", {})
	var missing_actor_art := not actor_manifest.has(clip["attacker"]) or not actor_manifest.has(clip["defender"])
	if manifest.is_empty() or (missing_actor_art and (presenter == null or presenter.needs_actor_art(clip["strike"]))):
		_process_missing_ordinary_clip(clip)
		return
	# The close-up frame; a map presenter overrides it for its own shot.
	background.visible = true
	background.color = Color(0.015, 0.025, 0.04)
	scenery.visible = true
	vitals.visible = true
	result.visible = true
	stage.size = Vector2(640, 320)
	for spark in sparks:
		spark.hide()
	attacker_sprite.modulate = Color.WHITE
	if presenter != null:
		if presenter.present(self, clip, elapsed):
			_complete_clip()
		return
	if clip["strike"].has("skill_name"):
		_process_borrowed_skill(clip)
		return
	blade.hide()
	scenery.texture = load(manifest["background"]["res_path"])
	var actor: Dictionary = manifest["actors"][clip["attacker"]]
	var schedule := Timing.ordinary(actor, clip["strike"], bool(clip["first_shot"]), bool(clip["last_shot"]))
	var strike_time: float = schedule["release"]
	var impact_time: float = schedule["impact"]
	if elapsed >= strike_time and not clip["release_emitted"]:
		clip["release_emitted"] = true
		released.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	if elapsed >= impact_time and not clip["impact_emitted"]:
		clip["impact_emitted"] = true
		impact.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	if elapsed >= float(schedule["complete"]):
		_complete_clip()
		return
	if elapsed >= float(schedule["darkened"]):
		_show_closing_lighten(schedule)
		return
	_show_shot(clip, elapsed >= float(schedule["target"]))
	if elapsed < float(schedule["opening"]):
		_show_opening(OriginalTick.ticks(elapsed))
	elif elapsed >= float(schedule["recovery"]):
		_show_closing_darken(OriginalTick.ticks(elapsed - float(schedule["recovery"])))
	_show_ordinary_shot(clip, actor, schedule, strike_time, impact_time)


## _process, ordinary strike: attacker pose and motion, defender reaction, flash and result.
func _show_ordinary_shot(clip: Dictionary, actor: Dictionary, schedule: Dictionary, strike_time: float, impact_time: float) -> void:
	var update := maxf(0.0, OriginalTick.ticks(elapsed - float(schedule["opening"])))
	var dispatch: Dictionary = actor["dispatch"]
	var frame := int(dispatch["initial_frame"])
	for pose in dispatch["poses"]:
		if update + 0.000001 < float(pose["update"]):
			break
		frame = int(pose["frame"])
	# Each close-up object reads its own actor's side-swap bit at init (0x446be0): the
	# attacker 0x401ddf (x zoom −1 about its anchor), its aniSetXYDisp x negated (0x4021b8)
	# and its aniSetAdd／SubSpeed angle reflected (0x45e785) — the program's x motion mirrors.
	var attacker_mirrored := CutinLayout.side_swapped(clip["attacker_unit"])
	var facing := -1.0 if attacker_mirrored else 1.0
	_set_frame(attacker_sprite, clip["attacker"], frame, attacker_mirrored)
	if dispatch.has("presentation_transform_states"):
		var transform: Dictionary = dispatch["presentation_transform_states"][mini(int(update),dispatch["presentation_transform_states"].size()-1)]
		# The object's zoom words +0x20／+0x24 are written only by the side swap (0x401ddf) and
		# aniSetZoom (0x40247f): no fit-to-frame scale; the identity window draws over the actor.
		attacker_sprite.scale = Vector2(facing, 1) * float(transform["zoom"]) / 65536.0
		attacker_sprite.position += Vector2(facing * float(transform["offset"][0]), float(transform["offset"][1]))
	elif dispatch.has("motion_offsets"):
		# The original draws before its common movement tail. Position from the
		# preceding integration belongs to this pose, not the following update.
		var offset: Array = dispatch["motion_offsets"][mini(maxi(0,int(update)-1), dispatch["motion_offsets"].size()-1)]
		attacker_sprite.scale = Vector2(facing, 1)
		attacker_sprite.position += Vector2(facing * float(offset[0]), float(offset[1]))
	var hit: bool = clip["strike"]["hit"]
	var defeated := hit and int(clip["strike"]["defender_hp_after"]) <= 0
	# The hurt pose (0x404015) persists until the defender object hides itself at the
	# transition or hands over to the next shot; the original has no return to neutral.
	var hurt: bool = hit and clip["impact_emitted"]
	var defender: Dictionary = manifest["actors"][clip["defender"]]
	# The defender object 0x4038a0 reads its own actor's bit (0x4044ae): x zoom −1 and the hit
	# move flag exchanged, so a side-swapped victim also shifts and recoils the other way.
	var defender_mirrored := CutinLayout.side_swapped(clip["defender_unit"])
	_set_frame(defender_sprite, clip["defender"], int(defender["hurt_frame"]) if hurt else 0, defender_mirrored)
	# Knock-back (hit) or dodge slide (miss) from the roll, along the object's hit move flag.
	if clip["impact_emitted"]:
		defender_sprite.position.x += CutinLayout.reaction_x(defender, hit, OriginalTick.ticks(elapsed - impact_time), defender_mirrored)
	var flash: Dictionary = actor["flash"]
	# aniInsertAttackFlash belongs to the attacker's pose; phase 101 holds the shot until the
	# flash object deletes itself (Timing.ordinary), so it never reaches the victim's shot.
	var flash_level := Timing.flash_level(int(OriginalTick.ticks(elapsed - strike_time)), Timing.ATTACK_FLASH_LEVEL, Timing.ATTACK_FLASH_HOLD_TICKS)
	flash_sprite.visible = elapsed >= strike_time and flash_level > 0 and elapsed < float(schedule["target"]) and not flash.is_empty()
	if flash_sprite.visible:
		# 0x40222e..0x402245: the flash object starts at the attacker object's (x, y) plus the
		# opcode's displacement — on the shot line, not at a fixed screen point. A side-swapped
		# attacker hands 0x401310 its mirror flag: the flash is drawn at x zoom −1 about that
		# point, the displacement itself is not negated (0x402231 adds it as read).
		var displacement: Array = actor["attack_flash_offset"]
		_set_effect(flash_sprite, flash, CutinLayout.attacker_anchor() + Vector2(float(displacement[0]), float(displacement[1])), 1.0, attacker_mirrored)
		flash_sprite.modulate.a = float(flash_level) / float(Timing.ATTACK_FLASH_LEVEL)
	if hit and clip["impact_emitted"]:
		_show_hit_flash(clip, OriginalTick.ticks(elapsed - impact_time))
	# The source hurt pose carries the reaction; do not paint the whole person red.
	defender_sprite.modulate = Color.WHITE
	# Hold the source hurt pose. Map aftermath owns the later death fade.
	result.position.y = 264
	# The number alone: no counter／series／lethal caption (UI6). 0x40424c counts 40 ticks from
	# the hit, then 0x404290 spawns the red number (hold 0) — only for a hit that took HP; a
	# miss (phases 5／6／4) spawns none.
	result.text = ""
	var number_time := impact_time + Timing.scaled(OriginalTick.seconds(Timing.HIT_TO_NUMBER_TICKS))
	if elapsed >= number_time:
		show_result(clip["strike"], OriginalTick.ticks((elapsed - number_time) / Timing.PLAYBACK_SPEED), ORDINARY_NUMBER_POINT, ordinary_result_spawns(clip["strike"]))
	if clip["impact_emitted"] and captions_public:
		var effects := preload("res://game/sim/WeaponEffectRules.gd").feedback(clip["strike"].get("weapon_effects", {}), not defeated)
		if effects != "": result.text += ("\n" if result.text != "" else "") + effects


## The receiver's hit flash `tick` ticks after the hit (0x40418a → 0x401310, then level 9 and 6
## held ticks): shape ATTACK_FLASH001 + the attacker weapon's ITEM icon class ([0x4c6f60],
## 0x4043a5), at the defender object's x on the hit tick and camera y + 180 (0xb4), x zoom −1 when
## the defender's side word 0x40ba20 is exactly pmPlayer. A weapon code without an ITEM weapon row
## draws none.
func _show_hit_flash(clip: Dictionary, tick: float) -> void:
	var hit_flashes: Dictionary = manifest.get("hit_flashes", {})
	var weapon := str(int(clip["attacker_unit"].get("weapon_code", 0)))
	if hit_flashes.is_empty() or not hit_flashes["weapon_icon_class"].has(weapon):
		return
	var level := Timing.flash_level(int(tick), Timing.HIT_FLASH_LEVEL, Timing.HIT_FLASH_HOLD_TICKS)
	if level <= 0:
		return
	var shape: Dictionary = hit_flashes["shapes"][int(hit_flashes["weapon_icon_class"][weapon])]
	_set_effect(hit_flash_sprite, shape, Vector2(defender_anchor(clip).x, HIT_FLASH_Y), 1.0, CutinLayout.player_side(clip["defender_unit"]))
	hit_flash_sprite.modulate.a = float(level) / float(Timing.ATTACK_FLASH_LEVEL)
	hit_flash_sprite.show()


## AnimalAttack phase 100 at `tick` ticks into the clip: 24 additive zoom draws of the ball
## at the screen centre (0x401060 ramp, mode 0xc000000 = saturating add), attacker hidden
## (+0x30 = 0xffff) and no identity strip yet; then 32 level-blend draws at 18× (mode
## 0x28000000, level 16 → 1 every 2 ticks) over the restored attacker and the strip.
func _show_opening(tick: float) -> void:
	var index := int(tick)
	if index >= Timing.OPENING_ZOOM_TICKS + Timing.OPENING_OVERLAY_TICKS:
		# Sub-state 2 (0x4027ee): the ball is no longer drawn; the attacker waits one tick.
		opening_ball.hide()
		return
	opening_ball.show()
	if index < Timing.OPENING_ZOOM_TICKS:
		opening_ball.material = opening_add_material
		opening_ball.modulate = Color.WHITE
		opening_ball.scale = Vector2.ONE * float(Timing.OPENING_ZOOM_RAMP[index]) / 65536.0
		# The zoom draws over the battlefield: the 2026-09-24 recording shows the map around
		# the growing ball until it whites out the screen (camera_panel_motion §5); the
		# close-up backdrop appears with the overlay phase.
		background.visible = false
		scenery.visible = false
		attacker_sprite.hide()
		defender_sprite.hide()
		vitals.visible = false
		result.visible = false
		return
	opening_ball.material = null
	opening_ball.scale = Vector2.ONE * float(Timing.OPENING_OVERLAY_ZOOM) / 65536.0
	opening_ball.modulate = Color(1, 1, 1, float(Timing.opening_overlay_level(index - Timing.OPENING_ZOOM_TICKS)) / float(Timing.TRANSITION_LEVELS))


## Phase 101 of the last shot: 0x46098f(1) blends the full-screen black shape at level 1 → 16,
## one level per tick, over the held hurt shot.
func _show_closing_darken(tick: float) -> void:
	transition_shade.show()
	transition_shade.color = Color(0, 0, 0, float(Timing.closing_darken_level(int(tick))) / float(Timing.TRANSITION_LEVELS))


## After the darken the defender hides and the cut-in flag clears (0x42c3f0(0)): the map
## shows under the shade while 0x4609c0(1) takes the level 16 → 1.
func _show_closing_lighten(schedule: Dictionary) -> void:
	show_closing_lighten_ticks(OriginalTick.ticks(elapsed - float(schedule["darkened"])))


## The closing lighten `tick` ticks in (also the special script's close, 0x404ada).
func show_closing_lighten_ticks(tick_in: float) -> void:
	background.visible = false
	scenery.visible = false
	vitals.visible = false
	result.visible = false
	attacker_sprite.hide()
	defender_sprite.hide()
	flash_sprite.hide()
	transition_shade.show()
	transition_shade.color = Color(0, 0, 0, float(Timing.closing_lighten_level(int(tick_in))) / float(Timing.TRANSITION_LEVELS))


func _process_missing_ordinary_clip(clip: Dictionary) -> void:
	# Formal battles can reference actor art that is not in the compact combat
	# animation packet. Keep the combat receipt observable without indexing absent art.
	attacker_sprite.hide()
	defender_sprite.hide()
	blade.hide()
	result.visible = true
	result.position.y = 264
	# Remake fallback: the result from the clip's start, at its shot's number point.
	var ordinary: bool = _presenter(clip) == null and not clip["strike"].has("skill_name")
	show_result(clip["strike"], OriginalTick.ticks(elapsed / Timing.PLAYBACK_SPEED), ORDINARY_NUMBER_POINT if ordinary else SCRIPT_NUMBER_POINT, ordinary_result_spawns(clip["strike"]) if ordinary else null)
	if elapsed >= 0.18 and not clip["release_emitted"]:
		clip["release_emitted"] = true
		released.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	if elapsed >= 0.45 and not clip["impact_emitted"]:
		clip["impact_emitted"] = true
		impact.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	if elapsed >= 0.75:
		_complete_clip()


## Result text of one strike (the digits, MISS or the receipt captions; the map label and tests).
## Numbers carry no sign glyph, as the original's defProcShowNumber digit sets (ShowNumberStyle);
## the number stands alone — no 暴擊 caption, and a miss reads MISS, the NUM513 glyph (UI6).
## 0x404643 spawns a number only for a non-zero HP／MP change, MISS when both are zero and no
## state took effect: a support or stat-buff receipt never reads as the number 0. A stat receipt
## whose effects are empty (nothing took) falls through to the miss text. A utility special
## (special_utility) that took HP shows its number; one that took none shows no result ("")
## when its effect landed and the miss text when it did not (shows_miss).
static func strike_feedback(strike: Dictionary) -> String:
	if strike.has("support_effects") or not strike.get("stat_effects", []).is_empty(): return " · ".join(support_feedback_parts(strike))
	if shows_miss(strike): return MISS_TEXT
	if strike.get("special_key") == "special_utility" and strike_actual_damage(strike) == 0: return ""
	return "%d" % strike_actual_damage(strike)


## Draws the strike's result `age_ticks` after its numbers spawned at `point`: `entries`
## (ResultNumberFloater spawns; null = result_spawns, aniShowHitResult) in the original glyphs,
## and on the result line the captions that have no glyph (caption_feedback).
func show_result(strike: Dictionary, age_ticks: float, point: Vector2 = SCRIPT_NUMBER_POINT, entries: Variant = null) -> void:
	result.text = caption_feedback(strike) if captions_public else ""
	result.add_theme_color_override("font_color", ShowNumberStyle.CAPTION)
	var spawns: Array[Dictionary] = result_spawns(strike) if entries == null else entries
	var key := [spawns, point]
	if key != _result_key:
		_result_key = key
		for number in result_number.get_children():
			number.free()
		ResultNumberFloater.spawn_all(result_number, spawns, point, false)
	result_number.show()
	for number in result_number.get_children():
		number.draw_at(age_ticks)


## The numbers aniShowHitResult (0x404643) spawns for a strike (ResultNumberFloater.spawns): the
## red HP loss; for a support／stat receipt its heal and MP numbers (never MISS — its captions
## say what took); MISS when shows_miss; a utility special that took no HP, or a hit that took
## none, spawns nothing.
static func result_spawns(strike: Dictionary) -> Array[Dictionary]:
	if strike.has("support_effects") or not strike.get("stat_effects", []).is_empty():
		var amounts := {"damage": 0, "heal": 0, "mp": 0}
		for part in feedback_parts(strike):
			if amounts.has(str(part["kind"])): amounts[str(part["kind"])] = int(part["text"])
		return ResultNumberFloater.spawns(amounts["damage"], amounts["heal"], amounts["mp"], false)
	if shows_miss(strike): return ResultNumberFloater.spawns(0, 0, 0, true)
	return ResultNumberFloater.spawns(strike_actual_damage(strike), 0, 0, false)


## An ordinary shot's number (0x404290): the red HP loss of a hit; a miss spawns nothing.
static func ordinary_result_spawns(strike: Dictionary) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	return result_spawns(strike) if bool(strike["hit"]) else none


## The result line's captions: the support／stat parts the original has no glyph for (cure and
## buff words, 未回復), " · "-joined; "" for any other strike.
static func caption_feedback(strike: Dictionary) -> String:
	if not strike.has("support_effects") and strike.get("stat_effects", []).is_empty(): return ""
	var captions: Array[String] = []
	for part in feedback_parts(strike):
		if str(part["kind"]) == "caption": captions.append(str(part["text"]))
	return " · ".join(captions)


## Whether the result reads as the miss (0x404643 kind 5 MISS). A utility special (天鳴覺醒／
## 獅子吼／吸血劍／竊殺／金之手／銀之手／高級金之手) runs 0x40b8f0 → 0x40aa80 channel 1, which
## spawns no number itself; the defender script adds its EXP return into *0x4c13f0 (0x40485d)
## and its HP／MP change into *0x4c6f74／*0x4c6f78. With no HP／MP change, aniShowHitResult
## shows nothing when *0x4c13f0 ≠ 0 (item or gold taken, queue slot reactivated or cancelled —
## each branch converts EXP at once) and MISS when it is 0 (roll failed, every item-slot roll
## failed, a gold take under 2). The receipt's experience_basis.points is that EXP return.
static func shows_miss(strike: Dictionary) -> bool:
	if not bool(strike["hit"]): return true
	if strike.get("special_key") != "special_utility" or strike_actual_damage(strike) > 0: return false
	return int(strike["experience_basis"]["points"]) <= 0


## Current receipts carry capped HP loss; older synthetic presentation clips derive the
## same projection from their before/after HP, never queued ST.
static func strike_actual_damage(strike: Dictionary) -> int:
	return int(strike.get("actual_damage", mini(int(strike["damage"]), int(strike.get("defender_hp_before", strike["damage"])))))


## Typed result parts of one per-target result: `[{text, kind}]`, kind naming the
## defProcShowNumber digit set (`damage`／`heal`／`mp`／`miss`) or `caption` for text the
## original has no glyph for. Map labels colour each part through ShowNumberStyle.color.
## Damage comes first (the original spawns the HP number, the MP number 0x28 px above it);
## support receipts (heal／HealMP／cure) never carry damage. Numbers carry no HP／MP suffix
## (UI6): the digit colour tells heal from MP, as the original's NUM2xx／NUM3xx sets. Cure rows
## name the removed status, stat rows the buff (power · turns) or its dispel; a support receipt
## that restored nothing → 未回復.
static func feedback_parts(result: Dictionary) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	if int(result.get("actual_damage", 0)) > 0: parts.append({"text": "%d" % int(result["actual_damage"]), "kind": "damage"})
	if int(result.get("healing", 0)) > 0: parts.append({"text": "%d" % int(result["healing"]), "kind": "heal"})
	if int(result.get("restored_mp", 0)) > 0: parts.append({"text": "%d" % int(result["restored_mp"]), "kind": "mp"})
	for effect in result.get("support_effects", []):
		var row: Dictionary = StatusCatalog.ENTRIES[effect.get("status", StatusCatalog.POISON_KEY)]
		parts.append({"text": str(row["cure_label"]) if effect["removed"] else "無" + str(row["name"]), "kind": "caption"})
	for effect in result.get("stat_effects", []):
		var name: String = StatEnhancementRules.LABELS[effect["kind"]]
		parts.append({"text": name + "增益解除" if int(effect["after_word"]) == 0 else "%s +%d · %d回" % [name, int(effect["after_power"]), int(effect["duration"])], "kind": "caption"})
	if result.has("support_effects") and parts.is_empty(): parts.append({"text": "未回復", "kind": "caption"})
	return parts


## The texts of feedback_parts for a support／stat receipt (cut-in result line, moon-dance segments).
static func support_feedback_parts(result: Dictionary) -> Array[String]:
	var texts: Array[String] = []
	for part in feedback_parts(result):
		texts.append(str(part["text"]))
	return texts


## Stands `actor_id`'s combat frame on `sprite`, drawn at x zoom −1 about its anchor when
## `mirrored` (the actor's side-swap bit, `side_swapped`).
func _set_frame(sprite: Sprite2D, actor_id: String, frame_index: int, mirrored: bool = false) -> void:
	var actor: Dictionary = manifest["actors"][actor_id]
	var frame: Dictionary = actor["frames"][frame_index]
	_apply_source_frame(sprite, frame)
	if mirrored:
		sprite.scale = Vector2(-1, 1)


func _apply_source_frame(sprite: Sprite2D, frame: Dictionary) -> void:
	sprite.texture = load(frame["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(frame["draw_origin"][0], frame["draw_origin"][1])
	sprite.scale = Vector2.ONE


## The victim's neutral spot in its shot (CutinLayout: the shot line shifted by the row's
## hit move flag); a defender without a manifest row stands on the shot line.
func defender_anchor(clip: Dictionary) -> Vector2:
	# A moon-dance target clip names no `defender` row (MoonDancePresentation targets by unit).
	var row: Dictionary = manifest.get("actors", {}).get(str(clip.get("defender", "")), {})
	return CutinLayout.defender_anchor(row, CutinLayout.side_swapped(clip.get("defender_unit", {}))) if not row.is_empty() else CutinLayout.attacker_anchor()


func _show_shot(clip: Dictionary, target_shot: bool) -> void:
	attacker_sprite.position = CutinLayout.attacker_anchor()
	defender_sprite.position = defender_anchor(clip)
	attacker_sprite.visible = not target_shot
	defender_sprite.visible = target_shot
	var unit: Dictionary = (clip["defender_unit"] if target_shot else clip["attacker_unit"]).duplicate(true)
	# EXP is settled already, but its UI must not announce an upgrade in the wind-up.
	if not target_shot and clip["strike"].has("experience"):
		var growth: Dictionary = clip["strike"]["experience"]
		unit["level"] = int(growth["level_before"])
		unit["exp"] = int(growth["exp_before"])
	var hp := int(clip["strike"]["defender_hp_after"]) if target_shot else int(unit["hp"])
	if target_shot and not clip["impact_emitted"]:
		hp = int(clip["strike"].get("defender_hp_before", unit["hp"]))
	if target_shot and clip["impact_emitted"] and clip["strike"].has("defender_after"):
		for key in ["status_flags", "status_counters", "mp"]:
			unit[key] = clip["strike"]["defender_after"][key]
	# A primary attacker may already be logically dead from a queued counterattack.
	var counter: Dictionary = clip["strike"].get("counter", {})
	if not target_shot and not counter.is_empty() and bool(counter.get("hit", false)):
		hp = int(counter["defender_hp_before"])
	# Production clips carry each strike's own snapshot. An intermediate extra
	# hit has no ST transition; the following blow/counter must not supply one.
	var gain: Dictionary = clip["strike"].get("stamina_gain", {})
	if not gain.is_empty():
		var participant: Dictionary = gain["defender" if target_shot else "attacker"]
		unit["stamina"] = participant["after" if clip["impact_emitted"] else "before"]
	elif counter.has("stamina_gain") and not clip["strike"].has("attacker_before"):
		# Older synthetic presentation clips lack per-strike snapshots.
		unit["stamina"] = counter["stamina_gain"]["attacker" if target_shot else "defender"]["before"]
	vitals.show_unit(unit, hp, bool(clip["known"].get(str(unit.get("id", "")), true)))


func _set_effect(sprite: Sprite2D, record: Dictionary, point: Vector2, scale_factor: float, flip: bool = false) -> void:
	sprite.texture = load(record["res_path"])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.position = point
	sprite.scale = Vector2(-scale_factor if flip else scale_factor, scale_factor)
	sprite.modulate = Color.WHITE


## The borrowed 氣刃斬 staging: a strike with a skill_name that no presenter claims — a row
## declared `borrowed_qi_blade` (an opcode outside the player's set; none today) or a strike
## without a `skill_id` (synthetic presentation clips).
func _process_borrowed_skill(clip: Dictionary) -> void:
	# 氣刃斬's source-bound art/sound in a compact remake staging at a provisional 60 Hz,
	# lent to any row the skill_effects manifest does not route to the script player.
	scenery.texture = load(skill["images"]["MAGIC\\SP00_001.SHP"]["res_path"])
	flash_sprite.hide()
	var casting: Array = special_frames(clip)
	if casting.is_empty():
		_set_frame(attacker_sprite, clip["attacker"], 0, CutinLayout.side_swapped(clip["attacker_unit"]))
	else:
		# The strip's panels play in order across the 0.5 s lead (banner first, then the
		# insets); remake pacing.
		_apply_source_frame(attacker_sprite, casting[mini(casting.size() - 1, int(elapsed * casting.size() / 0.5))])
	attacker_sprite.position = CutinLayout.attacker_anchor()
	_set_frame(defender_sprite, clip["defender"], 0, CutinLayout.side_swapped(clip["defender_unit"]))
	defender_sprite.position = defender_anchor(clip)
	defender_sprite.modulate = Color.WHITE
	if not clip["release_emitted"]:
		clip["release_emitted"] = true
		ability_sound.stream = load(skill["sound"]["res_path"])
		ability_sound.play()
		released.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], false)
	if elapsed >= 0.5 and not clip["impact_emitted"]:
		clip["impact_emitted"] = true
		impact.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], false)
	_show_shot(clip, bool(clip["impact_emitted"]))
	var hit: bool = clip["strike"]["hit"]
	# P001_201..207 (and the up rows' P0xx_201..203) are already-composed cast panels with
	# center anchors, not standing actors with foot anchors. Keep the entire source panel
	# above the HUD; a caster without a strip stands on the shot line like an ordinary strike.
	attacker_sprite.position = Vector2(320, 160) if not casting.is_empty() else CutinLayout.attacker_anchor()
	var member := "MAGIC\\SP01_%03d.SHP" % (1 + int(elapsed * 15) % 2)
	var effect_position := Vector2(lerpf(700, 320, clampf(elapsed / 0.5, 0, 1)), 160)
	blade.visible = elapsed < 0.5 or (hit and elapsed < 0.75)
	if elapsed >= 0.5:
		member = "MAGIC\\SP01_%03d.SHP" % (11 + mini(4, int((elapsed - 0.5) * 20)))
		effect_position = Vector2(320, 160)
		if hit:
			_set_frame(defender_sprite, clip["defender"], int(manifest["actors"][clip["defender"]]["hurt_frame"]), CutinLayout.side_swapped(clip["defender_unit"]))
		if manifest.get("actors", {}).has(clip["defender"]):
			defender_sprite.position.x += CutinLayout.reaction_x(manifest["actors"][clip["defender"]], hit, OriginalTick.ticks(elapsed - 0.5), CutinLayout.side_swapped(clip["defender_unit"]))
	# specCode01 starts the original left-facing projectile at (700, 160).
	_set_effect(blade, skill["images"][member], effect_position, 1.0)
	if hit and elapsed >= 0.5 and elapsed < 1.0:
		var burst_time := elapsed - 0.5
		var spark_frame := 21 + mini(4, int(burst_time * 10))
		for i in range(sparks.size()):
			var angle := float(i) * TAU / float(sparks.size())
			_set_effect(sparks[i], skill["images"]["MAGIC\\SP01_%03d.SHP" % spark_frame], effect_position + Vector2(cos(angle), sin(angle)) * (12 + burst_time * 110), 0.85)
			sparks[i].modulate.a = 1.0 - burst_time * 2
			sparks[i].show()
	if elapsed > 0.9:
		_set_frame(attacker_sprite, clip["attacker"], 0, CutinLayout.side_swapped(clip["attacker_unit"]))
		if hit and int(clip["strike"]["defender_hp_after"]) > 0:
			_set_frame(defender_sprite, clip["defender"], 0, CutinLayout.side_swapped(clip["defender_unit"]))
	# The name caption belongs to the map range (BattleAttackCue.caption); the line shows the result alone.
	result.visible = clip["impact_emitted"]
	result.position.y = 264
	if clip["impact_emitted"]:
		show_result(clip["strike"], OriginalTick.ticks((elapsed - 0.5) / Timing.PLAYBACK_SPEED))
	if elapsed >= 1.5:
		blade.hide()
		_complete_clip()

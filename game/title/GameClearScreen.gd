extends Node2D
## GameClear (level 998) sequence: the original ending shapes decoded from the PAK
## (content/imported/hsl/global/title/manifest.json, game_clear block) — the dusk castle
## backdrops OverBG01/02, the epilogue narration Over001/002 and the credits scroll
## workteam ending in 劇終 — played as timed phases with a fade between them, then any
## key or click returns to the title. obj-998.obs gives the shapes (defProcClearBOSS /
## ShowPlayer / ShowWorkTeam) and the defProcClearBOSS states their order: Over001, the
## STORYOVER dialogue, Over002, the player showcase, the credits
## (docs/evidence_packets/static_reverse/original_music.md §3.5); positions, scroll speeds,
## phase lengths and skipping are remake readings (provisional): no recording of the
## original GameClear exists.
##
## Between the two narration phases the epilogue dialogue plays on black: DATA\STORYOVER.TXT
## (loaded by defProcClearBOSS state 3, static-derived — manifest.game_clear_epilogue), 緹娜 and
## 漢克斯 in ten lines with the script's delays and the WALKSOUND footsteps, ending with
## actDeleteDarkScreen; click / key confirms a line (or ends a pause); board, portraits and
## pacing are remake readings.
##
## Music follows the phases (manifest.game_clear.music, §3.5): 07 from the first phase, 04 when
## the showcase starts, 02 with the credits, each from the start; skipping a phase switches with
## it. Nothing fades: leaving for the title cuts it with the scene change, and the title plays 03.
## With no party to show there is no showcase phase, so 07 runs on until the credits bring 02
## (in the original the nine-player state, and 04 with it, always runs).
## provenance:
##   rules: resource-derived content/imported/hsl/global/title/manifest.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_game_clear_epilogue.md
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: provisional (text positions, showcase card layout — no original GameClear recording)
##   layout: remake-invented content/generated/hsl/text/simplified_images.json
##     (workteam lettering redrawn with the original FONT.24 simplified glyphs)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: remake-invented (showcase names from portraits)
##   timing: provisional (phase lengths, scroll speed, skip input; actDelay units are the coordinator's 16 ms ticks)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json
##   audio: resource-derived content/imported/hsl/global/title/manifest.json (WALKSOUND cue)

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const TITLE_SCENE_PATH := "res://game/title/TitleScreen.tscn"
const GameSettings = preload("res://game/settings/GameSettings.gd")
const BattleDialogue = preload("res://game/battle/scene/BattleDialogue.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const SimplifiedDisplay = preload("res://game/text/SimplifiedDisplay.gd")
const FADE_SECONDS := 0.8
## Tests may shorten the phase lengths before _ready runs (phase_seconds_scale).
var phase_seconds_scale := 1.0
## The party shown between the epilogue and the credits (defProcClearShowPlayer on
## TITLE011, one object per slot in obj-998.obs): [{actor_id, name, portrait}], set by the
## scene that hands over (the finale's controlled slots) before the scene change.
static var showcase: Array = []
const SHOWCASE_SECONDS_PER_MEMBER := 2.4
var _showcase_root: Node2D

var manifest: Dictionary = {}
var phases: Array = []
var phase_index := -1
var phase := "starting"
var transition: Dictionary = {}
## STORYOVER steps ({kind: delay|message|sound|reveal, ...}) and the index being played.
var epilogue_steps: Array = []
var epilogue_step := -1
var epilogue_messages: Array[String] = []
var _epilogue_waiting_confirm := false
var _epilogue_timer: SceneTreeTimer
var _board: Control
var _sound: AudioStreamPlayer
var _background: Sprite2D
var _text: Sprite2D
var _fade: ColorRect
var _music: AudioStreamPlayer
## manifest.game_clear.music: phase id -> {track, stream}, started from the top when that phase begins.
var _music_cues: Dictionary = {}
var _scroll_tween: Tween
var _phase_tween: Tween


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	var config: Dictionary = manifest.get("game_clear", {})
	phases = (config.get("phases", []) as Array).duplicate(true)
	if not showcase.is_empty() and phases.size() >= 2:
		# The slot showcase sits between the second epilogue text and the credits.
		phases.insert(2, {"id": "showcase", "background": "game_over_background", "text": "", "text_top_left": [0, 0], "scroll_pixels": 0,
			"seconds": SHOWCASE_SECONDS_PER_MEMBER * showcase.size() + 1.0,
			"note": "one TITLE011 card per party slot with the member's portrait and name (remake layout; the original showcase objects are located, their layout is not)"})
	epilogue_steps = ((manifest.get("game_clear_epilogue", {}) as Dictionary).get("steps", []) as Array).duplicate(true)
	if not epilogue_steps.is_empty():
		# defProcClearBOSS runs Over001 (state 1), STORYOVER (state 3), Over002 (state 9): §3.5.
		phases.insert(mini(1, phases.size()), {"id": "epilogue", "background": "", "text": "", "text_top_left": [0, 0], "scroll_pixels": 0, "seconds": 0.0,
			"note": "STORYOVER dialogue on black after Over001 (defProcClearBOSS state 3); its actDeleteDarkScreen reveals Over002"})
	var cues: Variant = config.get("music", {})
	_music_cues = cues if cues is Dictionary else {}
	_background = Sprite2D.new()
	_background.name = "Background"
	_background.centered = false
	add_child(_background)
	_text = Sprite2D.new()
	_text.name = "Text"
	_text.centered = false
	add_child(_text)
	_showcase_root = Node2D.new()
	_showcase_root.name = "Showcase"
	add_child(_showcase_root)
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 10
	add_child(overlay)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.size = Vector2(640, 480)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_fade)
	var dialogue_layer := CanvasLayer.new()
	dialogue_layer.name = "DialogueLayer"
	dialogue_layer.layer = 20
	add_child(dialogue_layer)
	_board = BattleDialogue.new()
	_board.name = "EpilogueBoard"
	dialogue_layer.add_child(_board)
	_board.configure_portraits(ContentPaths.ACTOR_PORTRAITS)
	_board.position = Vector2(0, 320)
	var sound_path := str(((manifest.get("game_clear_epilogue", {}) as Dictionary).get("sound", {}) as Dictionary).get("res_path", ""))
	if sound_path != "" and ResourceLoader.exists(sound_path):
		_sound = AudioStreamPlayer.new()
		_sound.name = "EpilogueSound"
		_sound.stream = load(sound_path)
		add_child(_sound)
	_music = AudioStreamPlayer.new()
	_music.name = "ClearMusic"
	_music.volume_db = GameSettings.MUSIC_PLAYER_DB
	_music.bus = GameSettings.music_bus()
	add_child(_music)
	_start_phase(0)


func _shape(role: String) -> Dictionary:
	return (manifest.get("shapes", {}) as Dictionary).get(role, {})


func _start_phase(index: int) -> void:
	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	if _phase_tween != null and _phase_tween.is_running():
		_phase_tween.kill()
	if index >= phases.size():
		phase_index = phases.size()
		phase = "waiting"
		return
	phase_index = index
	var spec: Dictionary = phases[index]
	phase = str(spec.get("id", "phase_%d" % index))
	_play_phase_music(phase)
	for child in _showcase_root.get_children():
		child.queue_free()
	_stop_epilogue()
	if phase == "epilogue":
		_background.texture = null
		_text.texture = null
		_fade.color = Color(0, 0, 0, 1)
		_run_epilogue_step(0)
		return
	_background.texture = load(str(_shape(str(spec.get("background", ""))).get("texture", "")))
	_background.position = Vector2.ZERO
	var text_role := str(spec.get("text", ""))
	# Baked traditional lettering (workteam) shows its simplified redraw (SimplifiedDisplay).
	_text.texture = load(SimplifiedDisplay.texture_path(str(_shape(text_role).get("texture", "")))) if text_role != "" else null
	if phase == "showcase":
		_build_showcase(float(spec.get("seconds", 10.0)) * phase_seconds_scale)
	var top_left: Array = spec.get("text_top_left", [0, 0])
	_text.position = Vector2(float(top_left[0]), float(top_left[1]))
	var seconds: float = float(spec.get("seconds", 10.0)) * phase_seconds_scale
	var scroll: float = float(spec.get("scroll_pixels", 0))
	_fade.color = Color(0, 0, 0, 1)
	_phase_tween = create_tween()
	_phase_tween.tween_property(_fade, "color:a", 0.0, FADE_SECONDS * phase_seconds_scale)
	if scroll > 0.0:
		_scroll_tween = create_tween()
		_scroll_tween.tween_interval(FADE_SECONDS * phase_seconds_scale)
		_scroll_tween.tween_property(_text, "position:y", _text.position.y - scroll, maxf(seconds - 2.0 * FADE_SECONDS * phase_seconds_scale, 0.05))
	_phase_tween.tween_interval(maxf(seconds - 2.0 * FADE_SECONDS * phase_seconds_scale, 0.05))
	if index + 1 < phases.size():
		_phase_tween.tween_property(_fade, "color:a", 1.0, FADE_SECONDS * phase_seconds_scale)
		_phase_tween.tween_callback(_start_phase.bind(index + 1))
	else:
		_phase_tween.tween_callback(func() -> void: phase = "waiting")


## The phase's music cue, if it has one, replaces the current track from its start (PlayMusic
## restarts even the same track and loops it whole: original_music.md §1).
func _play_phase_music(phase_id: String) -> void:
	var cue: Variant = _music_cues.get(phase_id)
	if not cue is Dictionary or _music == null:
		return
	var stream_path := str((cue as Dictionary).get("stream", ""))
	if stream_path == "" or not ResourceLoader.exists(stream_path):
		push_error("GameClear music missing: " + stream_path)
		return
	var stream: AudioStream = load(stream_path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stop()
	_music.stream = stream
	_music.play()


## Plays STORYOVER step by step: a delay waits (a key ends it early), a message shows on
## the shared dialogue board until confirmed, the footstep cue plays, and the final
## actDeleteDarkScreen hands over to the next phase (Over002).
func _run_epilogue_step(index: int) -> void:
	_epilogue_waiting_confirm = false
	_epilogue_timer = null
	if index >= epilogue_steps.size():
		_board.clear_message()
		_start_phase(phase_index + 1)
		return
	epilogue_step = index
	var step: Dictionary = epilogue_steps[index]
	match str(step.get("kind", "")):
		"delay":
			_board.clear_message()
			var timer := get_tree().create_timer(maxf(float(step.get("seconds", 0.0)) * phase_seconds_scale, 0.001), false)
			_epilogue_timer = timer
			timer.timeout.connect(func() -> void:
				if _epilogue_timer == timer and phase == "epilogue":
					_run_epilogue_step(index + 1))
		"message":
			var message_id := str(step.get("message_id", ""))
			_board.show_message(message_id, str(step.get("speaker", "")), str(step.get("text", "")), str(step.get("actor_id", "")))
			epilogue_messages.append(message_id)
			_epilogue_waiting_confirm = true
		"sound":
			if _sound != null:
				_sound.play()
			_run_epilogue_step(index + 1)
		_:
			# reveal (actDeleteDarkScreen) and anything unknown: the dialogue is over.
			_run_epilogue_step(epilogue_steps.size())


func _stop_epilogue() -> void:
	_epilogue_timer = null
	_epilogue_waiting_confirm = false
	if _board != null:
		_board.clear_message()


## A key / click while the epilogue plays: page or confirm the current line, or end
## the current pause. Returns false when no epilogue is running.
func _advance_epilogue() -> bool:
	if phase != "epilogue":
		return false
	if _epilogue_waiting_confirm:
		if _board.advance_page():
			return true
		_run_epilogue_step(epilogue_step + 1)
		return true
	if _epilogue_timer != null:
		_run_epilogue_step(epilogue_step + 1)
		return true
	return true


## One card per member: portrait left of centre, name to its right; members fade in
## and out in slot order across the phase.
func _build_showcase(total_seconds: float) -> void:
	var each: float = total_seconds / maxf(float(showcase.size()), 1.0)
	for index in range(showcase.size()):
		var member: Dictionary = showcase[index]
		var card := Node2D.new()
		card.name = "Member%d" % index
		card.modulate = Color(1, 1, 1, 0)
		var portrait_path := str(member.get("portrait", ""))
		if portrait_path != "" and ResourceLoader.exists(portrait_path):
			var portrait := Sprite2D.new()
			portrait.name = "Portrait"
			portrait.centered = false
			portrait.texture = load(portrait_path)
			portrait.position = Vector2(196, 168)
			card.add_child(portrait)
		var label := Label.new()
		label.name = "Name"
		label.text = str(member.get("name", member.get("actor_id", "")))
		label.position = Vector2(336, 216)
		label.size = Vector2(200, 48)
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(0.97, 0.92, 0.75))
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		card.add_child(label)
		_showcase_root.add_child(card)
		var tween := create_tween()
		tween.tween_interval(index * each)
		tween.tween_property(card, "modulate:a", 1.0, minf(0.4, each * 0.2))
		tween.tween_interval(maxf(each - 2.0 * minf(0.4, each * 0.2), 0.01))
		tween.tween_property(card, "modulate:a", 0.0, minf(0.4, each * 0.2))


## Any key or click: during a phase it skips to the next one; after the credits it
## leaves for the title.
func advance() -> Dictionary:
	if phase == "waiting":
		return dismiss()
	if phase == "fading_out" or phase == "starting":
		return {}
	if _advance_epilogue():
		return summary()
	_start_phase(phase_index + 1)
	return summary()


func dismiss() -> Dictionary:
	if phase != "waiting":
		return {}
	phase = "fading_out"
	transition = {"scene": TITLE_SCENE_PATH, "status": "fading"}
	# The music keeps playing at full volume until the scene change cuts it (original_music.md §3.1).
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_SECONDS)
	tween.finished.connect(func() -> void:
		transition["status"] = "scene_changed"
		get_tree().change_scene_to_file(TITLE_SCENE_PATH))
	return transition


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
		advance()


func summary() -> Dictionary:
	return {
		"schema": "hsl_game_clear_screen.v1",
		"phase": phase,
		"phase_index": phase_index,
		"phase_count": phases.size(),
		"showcase_count": showcase.size(),
		"epilogue_step": epilogue_step,
		"epilogue_step_count": epilogue_steps.size(),
		"epilogue_messages": epilogue_messages.duplicate(),
		"epilogue_waiting_confirm": _epilogue_waiting_confirm,
		"epilogue_speaker": str(_board.speaker_label.text) if _board != null and _board.visible else "",
		"epilogue_sound_playing": _sound != null and _sound.playing,
		"text_position": _text.position if _text != null else Vector2.ZERO,
		"music_stream": _music.stream.resource_path if _music != null and _music.stream != null else "",
		"music_playing": _music != null and _music.playing,
		"music_volume_db": _music.volume_db if _music != null else 0.0,
		"transition": transition.duplicate(true),
	}

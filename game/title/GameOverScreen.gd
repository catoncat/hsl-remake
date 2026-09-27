extends Node2D
## GAME OVER screen a lost battle leaves for (0x42cbd0 -> level 999): the original Title011
## sunset backdrop and Title012 "GAME OVER" text (content/imported/hsl/global/title/
## manifest.json), stepped once per original tick (OriginalTick) as defProcGameOverBOSS
## 0x42aea0 runs: GAMEOVER.WAV (resource 628) and a 60 count on the first frame; while the count
## is above 40 (the first 20 ticks) input is ignored; at 0 — or on input after that — the word
## object 0x42afc0 appears centred on (320,240), growing from 1/32 by 1/128 a tick and fading in
## over 16 levels one per 4 ticks (input doubles both); once full and opaque it hands back, the
## count is set to 160 and a key or click — or the count running out — calls 0x42cb90 and the
## screen fades out into the title. The backdrop comes in through the level transition the
## recorded victory shows (0.2 s black, 0.5 s fade in); no recording shows the GAME OVER screen.
## OPT-RETRY (docs/OPTIONS.md), read once as the screen is built: 可重新挑戰本戰 adds a two-row
## menu — 重新挑戰本戰 re-enters the lost battle with the party that entered it (the entry
## hand-off CampaignProgress.last_entry, a 戰場記錄 load reset to the battle's start; as if the
## original had saved a 戰場記錄 at the first action) and 回到標題 is the original way out; the
## menu appears once the original timeline has reached its wait, then waits for the choice
## instead of leaving by itself.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/first_battle_audio.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_game_clear_epilogue.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_battle_end_flow.md
##     (0x42aea0: count 60, no input above 40, word at 0 or input, then 160 → 0x42cb90)
##   rules: remake-invented docs/OPTIONS.md
##     (OPT-RETRY=可重新挑戰本戰 only: re-enter the battle from its entry hand-off, no self-timed exit)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_battle_end_flow.md
##     (word object at (320,240), Title012 drawn about its centre)
##   layout: remake-invented docs/OPTIONS.md (OPT-RETRY=可重新挑戰本戰 only: the two-row menu under the text)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: remake-invented docs/OPTIONS.md (OPT-RETRY=可重新挑戰本戰 only: 重新挑戰本戰／回到標題)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_battle_end_flow.md
##     (0x42afc0: scale 0x800 +0x200 a tick, 16 alpha levels every 4 ticks; input speeds both)
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_battle_end_flow.md
##     (0.2 s black, 0.5 s fade in: the victory's 0x42dc90(2), taken for level 999)
##   timing: provisional (0.6 s fade-out)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const INTERFACE_AUDIO_PATH := preload("res://game/sim/ContentPaths.gd").INTERFACE_AUDIO
const TITLE_SCENE_PATH := "res://game/title/TitleScreen.tscn"
const BATTLE_SCENE_PATH := "res://game/battle/scene/BattleSceneRuntime.tscn"
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
## OPT-RETRY menu rows (remake layout): centred under the GAME OVER text, one 32 px pitch.
const RETRY_ROWS := [{"id": "retry", "text": "重新挑戰本戰"}, {"id": "title", "text": "回到標題"}]
const RETRY_MENU_TOP := 352.0
const RETRY_MENU_PITCH := 32.0
## The level transition as the recorded victory shows it (516.2–516.9 s): black, then fade in.
const BLACK_HOLD_SECONDS := 0.2
const FADE_IN_SECONDS := 0.5
const FADE_OUT_SECONDS := 0.6
## 0x42aea0: count 60 on the first frame; input is ignored while the count is above 40.
const HOLD_TICKS := 60
const INPUT_LOCK_ABOVE := 40
## 0x42afc0 word object at (320,240): scale 0x800 → 0x10000 by 0x200 a tick (+0x400 once input
## was seen), alpha level 0 → 16 one step every 4 ticks (2 after input); both done → hand back.
const WORD_CENTRE := Vector2(320, 240)
const WORD_SCALE_ONE := 0x10000
const WORD_SCALE_START := 0x800
const WORD_SCALE_STEP := 0x200
const WORD_SCALE_FAST_EXTRA := 0x400
const WORD_ALPHA_LEVELS := 16
const WORD_ALPHA_INTERVAL := 4
## 0x42aea0 phase 2 sets its counter to 160; phase 3 leaves for the title at 0 or on input.
const AUTO_LEAVE_TICKS := 160

var manifest: Dictionary = {}
var phase := "fading_in"
var transition: Dictionary = {}
var _fade: ColorRect
var _cue: AudioStreamPlayer
var _tick_clock := 0.0
var _input_latched := false
## 0x42aea0 state: phase 0 hold, 1 word running, 2 hand-back, 3 wait; `_count` is +0xa0.
var _boss_phase := 0
var _count := HOLD_TICKS
## 0x42afc0 state: -1 before it exists, then its ticks; scale (0x10000 = 1), alpha level,
## the 4／2-tick reload counter and the input-seen flag (0x10000 in +0x80).
var word_tick := -1
var _word_done := false
var _word_scale := WORD_SCALE_START
var _word_alpha := 0
var _word_reload := WORD_ALPHA_INTERVAL
var _word_fast := false
var _word: Sprite2D
## OPT-RETRY read when the screen is built: false on the original path.
var retry_offered := false
var retry_labels: Array[Label] = []
var retry_focus := 0


func _ready() -> void:
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	for role in ["game_over_background", "game_over_text"]:
		var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(role, {})
		var layout: Dictionary = (manifest.get("layout", {}) as Dictionary).get(role, {})
		var top_left: Array = layout.get("top_left", [0, 0])
		var sprite := Sprite2D.new()
		sprite.name = "Title_" + role
		sprite.centered = false
		sprite.texture = load(str(entry.get("texture", "")))
		sprite.position = Vector2(float(top_left[0]), float(top_left[1]))
		add_child(sprite)
		if role == "game_over_text":
			# Scaled about its draw origin, which the word object places on (320,240).
			var origin: Array = entry.get("draw_origin", [0, 0])
			sprite.offset = -Vector2(float(origin[0]), float(origin[1]))
			sprite.position = WORD_CENTRE
			sprite.hide()
			_word = sprite
	retry_offered = not GameOptions.is_original("OPT-RETRY")
	if retry_offered:
		_build_retry_menu()
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
	var audio: Variant = ContentPaths.read_json(INTERFACE_AUDIO_PATH)
	var cue_path := str((((audio if typeof(audio) == TYPE_DICTIONARY else {}) as Dictionary).get("sounds", {}) as Dictionary).get("game_over", {}).get("res_path", ""))
	if cue_path != "" and ResourceLoader.exists(cue_path):
		_cue = AudioStreamPlayer.new()
		_cue.name = "GameOverCue"
		_cue.stream = load(cue_path)
		add_child(_cue)
		_cue.play()
	var tween := create_tween()
	tween.tween_interval(BLACK_HOLD_SECONDS)
	tween.tween_property(_fade, "color:a", 0.0, FADE_IN_SECONDS)


func _process(delta: float) -> void:
	if phase == "fading_out":
		return
	_tick_clock += delta
	while _tick_clock >= OriginalTick.TICK_SECONDS and phase != "fading_out":
		_tick_clock -= OriginalTick.TICK_SECONDS
		_step()


## One original tick of 0x42aea0 (and, once it exists, 0x42afc0).
func _step() -> void:
	var input := _input_latched
	_input_latched = false
	match _boss_phase:
		0:
			if _count > INPUT_LOCK_ABOVE:
				input = false
			_count -= 1
			if _count <= 0 or input:
				_boss_phase = 1
				word_tick = 0
				_draw_word()
		1:
			_step_word(input)
		2:
			_count = AUTO_LEAVE_TICKS
			_boss_phase = 3
			phase = "waiting"
			for row in retry_labels: row.show()
		3:
			if retry_offered:
				return # OPT-RETRY: the menu waits for the player's choice
			_count -= 1
			if _count <= 0 or input:
				dismiss()


func _step_word(input: bool) -> void:
	if _word_done:
		_boss_phase = 2 # 0x42b064: the word bumps the boss's phase
		return
	word_tick += 1
	if input:
		_word_fast = true
	var done := 0
	_word_reload -= 1
	if _word_reload <= 0:
		_word_reload = WORD_ALPHA_INTERVAL / (2 if _word_fast else 1)
		if _word_alpha < WORD_ALPHA_LEVELS:
			_word_alpha += 1
		else:
			done = 1
	if _word_scale < WORD_SCALE_ONE:
		_word_scale = mini(WORD_SCALE_ONE, _word_scale + WORD_SCALE_STEP + (WORD_SCALE_FAST_EXTRA if _word_fast else 0))
	else:
		done |= 2
	_word_done = done == 3
	_draw_word()


func _draw_word() -> void:
	if _word == null:
		return
	_word.visible = _word_alpha > 0
	_word.scale = Vector2.ONE * (float(_word_scale) / WORD_SCALE_ONE)
	_word.modulate.a = float(_word_alpha) / WORD_ALPHA_LEVELS


## Any key or click once the word is up (or the 160-tick count) leaves for the title.
func dismiss() -> Dictionary:
	if phase != "waiting":
		return {}
	phase = "fading_out"
	transition = {"scene": TITLE_SCENE_PATH, "status": "fading"}
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_OUT_SECONDS)
	tween.finished.connect(func() -> void:
		transition["status"] = "scene_changed"
		get_tree().change_scene_to_file(TITLE_SCENE_PATH))
	return transition


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)
	if retry_offered and phase == "waiting":
		_retry_menu_input(event)
		return
	# 0x42aea0／0x42afc0 read the input bits each tick: latched for the next step; at the
	# wait (phase 3) the next tick would leave anyway, so the press leaves now.
	if pressed and phase == "waiting":
		dismiss()
	elif pressed:
		_input_latched = true


## OPT-RETRY=可重新挑戰本戰: re-enter the lost battle. The entry hand-off becomes the pending
## one again (a 戰場記錄 load starts the battle over instead of reloading the record); a battle
## entered without a hand-off (開始新故事's first battle, a development launch) reboots the same.
func retry() -> Dictionary:
	if phase != "waiting" or not retry_offered:
		return {}
	phase = "fading_out"
	var entry: Dictionary = CampaignProgress.last_entry.duplicate(true)
	entry.erase("load_checkpoint")
	if not entry.is_empty():
		CampaignProgress.pending = entry
	transition = {"scene": BATTLE_SCENE_PATH, "status": "fading", "retry": true}
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_OUT_SECONDS)
	tween.finished.connect(func() -> void:
		transition["status"] = "scene_changed"
		get_tree().change_scene_to_file(BATTLE_SCENE_PATH))
	return transition


func _build_retry_menu() -> void:
	for index in RETRY_ROWS.size():
		var row := BattleUISkin.text(self, Vector2(0, RETRY_MENU_TOP + index * RETRY_MENU_PITCH), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(640, 24))
		row.name = "Retry_" + str(RETRY_ROWS[index]["id"])
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.text = str(RETRY_ROWS[index]["text"])
		row.hide() # shown once the original timeline reaches its wait
		retry_labels.append(row)
	_refresh_retry_menu()


func _refresh_retry_menu() -> void:
	for index in retry_labels.size():
		retry_labels[index].add_theme_color_override("font_color", BattleUISkin.TEXT_YELLOW if index == retry_focus else BattleUISkin.TEXT_WHITE)


func _retry_row_at(point: Vector2) -> int:
	for index in retry_labels.size():
		var row := retry_labels[index]
		var width := row.get_theme_font("font").get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, BattleUISkin.FONT_BODY).x
		if Rect2(row.position + Vector2((row.size.x - width) / 2.0, 0), Vector2(width, row.size.y)).has_point(point):
			return index
	return -1


## Up／Down move between the rows, Enter／Space choose, the mouse picks a row by pointing and
## clicking; every other input is ignored.
func _retry_menu_input(event: InputEvent) -> void:
	if phase != "waiting":
		return
	if event is InputEventMouse:
		var hovered := _retry_row_at(event.position)
		if hovered >= 0 and hovered != retry_focus:
			retry_focus = hovered
			_refresh_retry_menu()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hovered >= 0:
			_choose_retry_row()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:
			retry_focus = (retry_focus + 1) % retry_labels.size()
			_refresh_retry_menu()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_choose_retry_row()


func _choose_retry_row() -> void:
	if str(RETRY_ROWS[retry_focus]["id"]) == "retry":
		retry()
	else:
		dismiss()


func summary() -> Dictionary:
	return {
		"schema": "hsl_game_over_screen.v1",
		"phase": phase,
		"transition": transition.duplicate(true),
		"text_position": _word.position + _word.offset if _word != null else Vector2.ZERO,
		"word_tick": word_tick,
		"word_scale": float(_word_scale) / WORD_SCALE_ONE,
		"word_alpha_level": _word_alpha,
		"cue_playing": _cue != null and _cue.playing,
		"retry_offered": retry_offered,
		"retry_focus": retry_focus,
	}

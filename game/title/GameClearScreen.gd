extends Node2D
## GameClear (level 998) as the four obj-998 processes run it, one step per original 16 ms tick
## (docs/evidence_packets/static_reverse/original_game_clear.md, numbers in
## content/imported/hsl/global/title/manifest.json game_clear):
## defProcClearBOSS 0x42b6b0 orders the states — fade in from black over OverBG01 (16 levels × 6
## ticks), 40 ticks, Over001 scrolled up from y 500 at 0.5 px/tick until 80 px past the top, the
## STORYOVER dialogue under the obj-700 dark screen (6 ticks a level; the backdrop turns to
## OverBG02 120 ticks after the script starts), 40 ticks, Over002 the same way, track 04 and 40
## ticks, the nine party slots (defProcClearShowPlayer 0x42ba10: combat shape frame 0 anchored at
## x 320, 1 px/tick from y 500 + height, the next slot released at y 100, removed at −250, the
## 0x42b2b0 FONT.24 status sheet at (x − 252, y + 6)), 240 ticks, track 02 and the workteam credits
## (defProcClearShowWorkTeam 0x42bc20, 0.5 px/tick until its bottom rests on 480). The credits are
## the workteam shape itself: no runtime credit strings exist. Nothing before that reads input
## except the dialogue's own confirms; once the credits rest a key or click leaves for the title
## (0x42cc10(0,0) → 0x42dc90(2): 16 levels × 2 ticks to black). OPT-PACE 快／極快 (docs/OPTIONS.md)
## add a remake-invented skip: a confirm outside the dialogue jumps to the next segment's start.
##
## The epilogue dialogue is DATA\STORYOVER.TXT (manifest.game_clear_epilogue, static-derived):
## 緹娜 and 漢克斯 in ten lines with the script's delays and the WALKSOUND footsteps, ending with
## actDeleteDarkScreen; click / key confirms a line (or ends a pause); board, portraits and
## pacing follow original_game_clear_epilogue.md.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_game_clear.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_game_clear_epilogue.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_game_clear.md
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: remake-invented content/generated/hsl/text/simplified_images.json
##     (workteam lettering redrawn with the original FONT.24 simplified glyphs)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json (status-sheet RESOURCE labels)
##   timing: static-derived docs/evidence_packets/static_reverse/original_game_clear.md
##   timing: provisional (STORYOVER actDelay unit and key-ended pauses, original_game_clear_epilogue.md)
##   timing: remake-invented (segment skip on confirm under OPT-PACE 快／極快; 原版 keeps no skip)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json
##   audio: resource-derived content/imported/hsl/global/title/manifest.json (WALKSOUND cue)

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const TITLE_SCENE_PATH := "res://game/title/TitleScreen.tscn"
const GameSettings = preload("res://game/settings/GameSettings.gd")
const BattleDialogue = preload("res://game/battle/scene/BattleDialogue.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const InterfaceArt = preload("res://game/common/InterfaceArt.gd")
const SimplifiedDisplay = preload("res://game/text/SimplifiedDisplay.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const UISkin = preload("res://game/common/BattleUISkin.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
## Tests may speed the clock up before _ready runs: one tick lasts TICK_SECONDS × this.
var phase_seconds_scale := 1.0
## The nine party slots handed over by the finale (BattleOpeningCoordinator._game_clear_showcase):
## [{actor_id, joined, sprite_actor_id, sheet: {key: value}}] in slot order; a missing or
## not-joined slot shows 此角色未加入隊伍 under the slot's default combat shape.
static var showcase: Array = []
## The finale scenario's resources.combat_animation manifest (the slots' combat shapes), set with
## `showcase`; empty draws the sheets without shapes.
static var combat_animation_path := ""

var manifest: Dictionary = {}
var config: Dictionary = {}
## defProcClearBOSS state (+0x8c) and countdown (+0x94).
var boss_state := 0
var boss_counter := 0
var phase := "starting"
var transition: Dictionary = {}
var ticks_elapsed := 0
var _tick_accumulator := 0.0
## Screen fade (0x460a06): level 0..16, 16 black; direction −1 / +1, reload per level.
var _fade_level := 16
var _fade_direction := 0
var _fade_reload := 1
var _fade_count := 0
## obj 700 dark screen: level 0..16, direction, reload / count.
var _dark_level := 0
var _dark_direction := 0
var _dark_count := 0
## The ShowWorkTeam object being scrolled: {role, y, frac, remaining, removed, done}.
var _scroll: Dictionary = {}
## ShowPlayer objects on screen: [{node, y, released}] and the next slot to insert.
var _members: Array = []
var _slot_index := 0
var slots_shown: Array[String] = []
var _story_running := false
## STORYOVER steps ({kind: delay|message|sound|reveal, ...}) and the index being played.
var epilogue_steps: Array = []
var epilogue_step := -1
var epilogue_messages: Array[String] = []
var _epilogue_waiting_confirm := false
var _epilogue_delay_ticks := 0
var _board: Control
var _sound: AudioStreamPlayer
var _background: Sprite2D
var _text: Sprite2D
var _showcase_root: Node2D
var _dark: ColorRect
var _fade: ColorRect
var _music: AudioStreamPlayer
var _music_cues: Dictionary = {}
var _combat_frames: Dictionary = {}


func _ready() -> void:
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	config = manifest.get("game_clear", {})
	var combat: Variant = ContentPaths.read_json(combat_animation_path) if combat_animation_path != "" else null
	_combat_frames = (combat as Dictionary).get("actors", {}) if combat is Dictionary else {}
	epilogue_steps = ((manifest.get("game_clear_epilogue", {}) as Dictionary).get("steps", []) as Array).duplicate(true)
	var cues: Variant = config.get("music", {})
	_music_cues = cues if cues is Dictionary else {}
	_background = Sprite2D.new()
	_background.name = "Background"
	_background.centered = false
	add_child(_background)
	_text = Sprite2D.new()
	_text.name = "Text"
	_text.centered = false
	_text.visible = false
	add_child(_text)
	_showcase_root = Node2D.new()
	_showcase_root.name = "Showcase"
	add_child(_showcase_root)
	var dark_layer := CanvasLayer.new()
	dark_layer.name = "DarkLayer"
	dark_layer.layer = 5
	add_child(dark_layer)
	_dark = _black_rect("DarkScreen", 0.0)
	dark_layer.add_child(_dark)
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 30
	add_child(overlay)
	_fade = _black_rect("Fade", 1.0)
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
	# BOSS first frame (0x42b6c6): track 07, the fade-in from black, 40 ticks, OverBG01.
	_set_background(0)
	_play_music("epilogue_1")
	_start_fade(-1, int(config.get("fade_in_ticks_per_level", 6)))
	boss_counter = _wait("opening")
	phase = "epilogue_1"


func _black_rect(node_name: String, alpha: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.size = Vector2(640, 480)
	rect.color = Color(0, 0, 0, alpha)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _wait(key: String) -> int:
	return int((config.get("waits", {}) as Dictionary).get(key, 0))


func _shape(role: String) -> Dictionary:
	return (manifest.get("shapes", {}) as Dictionary).get(role, {})


func _set_background(frame: int) -> void:
	var roles: Array = config.get("backgrounds", [])
	if frame < roles.size():
		_background.texture = InterfaceArt.texture(str(_shape(str(roles[frame])).get("texture", "")))


func _process(delta: float) -> void:
	if manifest.is_empty():
		return
	var tick_seconds := OriginalTick.TICK_SECONDS * maxf(phase_seconds_scale, 0.00001)
	_tick_accumulator += delta
	var budget := 5000
	while _tick_accumulator >= tick_seconds and budget > 0:
		_tick_accumulator -= tick_seconds
		budget -= 1
		_tick()


## One original tick: the BOSS state, its child objects, the fade and the dark screen.
func _tick() -> void:
	ticks_elapsed += 1
	_boss_tick()
	_scroll_tick()
	_members_tick()
	_epilogue_tick()
	_fade_tick()
	_dark_tick()


func _boss_tick() -> void:
	match boss_state:
		0, 8:
			boss_counter -= 1
			if boss_counter <= 0:
				boss_state += 1
		1:
			boss_state = 2
			_start_scroll("epilogue_1")
		3:
			# 0x42b775: the dark screen (obj 700, 0x60006) and STORYOVER; 40 ticks.
			boss_state = 4
			boss_counter = _wait("before_story")
			phase = "epilogue"
			_dark_direction = 1
			_dark_count = int(config.get("dark_screen_ticks_per_level", 6))
		4:
			boss_counter -= 1
			if boss_counter <= 0 and _fade_direction == 0:
				boss_state = 5
				boss_counter = _wait("backdrop_swap")
				_story_running = true
				_run_epilogue_step(0)
		5:
			boss_counter -= 1
			if boss_counter <= 0:
				_set_background(1)
				boss_state = 6
		6:
			if not _story_running:
				boss_state = 7
		7:
			boss_counter = _wait("after_story")
			boss_state = 8
		9:
			boss_state = 10
			phase = "epilogue_2"
			_start_scroll("epilogue_2")
		11:
			phase = "showcase"
			_play_music("showcase")
			boss_counter = _wait("before_players")
			boss_state = 12
		12:
			boss_counter -= 1
			if boss_counter <= 0:
				_slot_index = 0
				boss_state = 13
		13:
			boss_state = 14
			_insert_member(_slot_index)
		15:
			_slot_index += 1
			boss_state = 13 if _slot_index < 9 else 16
		16:
			boss_counter = _wait("before_credits")
			boss_state = 17
		17:
			boss_counter -= 1
			if boss_counter <= 0:
				_play_music("credits")
				boss_state = 18
				phase = "credits"
				_start_scroll("credits")
		19:
			if phase == "credits":
				phase = "waiting"


## defProcClearShowWorkTeam: y 500, 0.5 px/tick upwards (16.16 fraction kept in 16 bits, so the
## whole-pixel steps alternate 1, 0), until the remaining distance runs out.
func _start_scroll(id: String) -> void:
	var spec: Dictionary = (config.get("scrolls", {}) as Dictionary).get(id, {})
	var role := str(spec.get("shape", ""))
	var shape := _shape(role)
	var height := int((shape.get("size", [0, 0]) as Array)[1])
	var start_y := int(config.get("scroll_start_y", 500))
	var remaining := start_y + height + int(spec.get("past_top", 0)) if bool(spec.get("removed", true)) else start_y + height - int(spec.get("rest_bottom", 480))
	_scroll = {"id": id, "role": role, "y": start_y, "frac": 0, "remaining": remaining, "removed": bool(spec.get("removed", true)), "done": false}
	# Baked traditional lettering (workteam) shows its simplified redraw (SimplifiedDisplay).
	_text.texture = load(SimplifiedDisplay.texture_path(InterfaceArt.path(str(shape.get("texture", "")))))
	_text.visible = true
	_place_scroll()


func _place_scroll() -> void:
	var origin: Array = _shape(str(_scroll.get("role", ""))).get("draw_origin", [0, 0])
	_text.position = Vector2(-float(origin[0]), float(int(_scroll["y"])) - float(origin[1]))


func _scroll_tick() -> void:
	# The object is drawn where it stood before this tick's step (the position is set first).
	if _scroll.is_empty() or (bool(_scroll["done"]) and bool(_scroll["removed"])):
		return
	_place_scroll()
	if bool(_scroll["done"]):
		return
	var step := -int(round(float(config.get("scroll_px_per_tick", 0.5)) * 65536.0)) + int(_scroll["frac"])
	_scroll["frac"] = step & 0xffff
	var delta := step >> 16
	if int(_scroll["remaining"]) > 0:
		_scroll["y"] = int(_scroll["y"]) + delta
		_scroll["remaining"] = int(_scroll["remaining"]) + delta
	if int(_scroll["remaining"]) <= 0:
		_scroll["done"] = true
		boss_state += 1
		if bool(_scroll["removed"]):
			_text.visible = false
			_text.texture = null


## defProcClearShowPlayer for slot `index`: the slot's combat shape frame 0 anchored at x 320,
## starting at y 500 + its height, with its status sheet at (x − 252, y + 6).
func _insert_member(index: int) -> void:
	var spec: Dictionary = config.get("showcase", {})
	var slots: Array = spec.get("slots", [])
	var slot_actor := str(slots[index]) if index < slots.size() else ""
	var entry: Dictionary = {}
	for value in showcase:
		if value is Dictionary and str((value as Dictionary).get("actor_id", "")) == slot_actor:
			entry = value
	var joined := bool(entry.get("joined", false))
	var sprite_actor := str(entry.get("sprite_actor_id", slot_actor)) if joined else slot_actor
	if not _combat_frames.has(sprite_actor):
		sprite_actor = slot_actor
	var node := Node2D.new()
	node.name = "Member%d" % index
	var height := 0
	var frames: Array = (_combat_frames.get(sprite_actor, {}) as Dictionary).get("frames", [])
	if not frames.is_empty():
		var frame: Dictionary = frames[0]
		var texture: Texture2D = load(str(frame.get("res_path", "")))
		var origin: Array = frame.get("draw_origin", [0, 0])
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.centered = false
		sprite.texture = texture
		sprite.position = Vector2(float(spec.get("anchor_x", 320)) - float(origin[0]), -float(origin[1]))
		node.add_child(sprite)
		height = texture.get_height() if texture != null else 0
	var sheet := Node2D.new()
	sheet.name = "Sheet"
	var offset: Array = spec.get("sheet_offset", [-252, 6])
	sheet.position = Vector2(float(spec.get("anchor_x", 320)) + float(offset[0]), float(offset[1]))
	node.add_child(sheet)
	_build_sheet(sheet, spec, entry if joined else {})
	var y := int(spec.get("start_y", 500)) + height
	node.position = Vector2(0, y)
	_showcase_root.add_child(node)
	_members.append({"node": node, "y": y, "released": false})
	slots_shown.append(slot_actor)


## 0x42b2b0's sheet: per item `@3`label`: @1`value padded to its byte width (12 px a byte in
## FONT.24); a slot not in the party gets only 此角色未加入隊伍 centred in 42 bytes, three rows down.
func _build_sheet(parent: Node2D, spec: Dictionary, entry: Dictionary) -> void:
	var pitch := float(spec.get("line_pitch", 26))
	var byte_px := float(spec.get("byte_px", 12))
	if entry.is_empty():
		var line: Dictionary = spec.get("not_joined", {})
		var text := str(line.get("text", ""))
		var pad := maxi(int(line.get("width", 42)) - _bytes(text), 0) / 2
		UISkin.text(parent, Vector2(pad * byte_px, int(line.get("row", 3)) * pitch), UISkin.TEXT_WHITE).text = text
		return
	var values: Dictionary = entry.get("sheet", {})
	var rows: Array = spec.get("rows", [])
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var column := int(row.get("indent", 0))
		for item_value in row.get("items", []):
			var item: Dictionary = item_value
			var label := str(item.get("label", "")) + ": "
			var value := str(values.get(str(item.get("key", "")), ""))
			if bool(item.get("percent", false)):
				value += "%"
			var y := row_index * pitch
			UISkin.text(parent, Vector2(column * byte_px, y), UISkin.TEXT_GREEN).text = label
			UISkin.text(parent, Vector2((column + _bytes(label)) * byte_px, y), UISkin.TEXT_WHITE).text = value
			column += maxi(int(item.get("width", 0)), _bytes(label + value))


## Big5 byte width: two bytes a full-width glyph, one an ASCII character.
static func _bytes(text: String) -> int:
	var count := 0
	for index in range(text.length()):
		count += 1 if text.unicode_at(index) < 0x80 else 2
	return count


func _members_tick() -> void:
	var spec: Dictionary = config.get("showcase", {})
	for member in _members.duplicate():
		var y := int(member["y"])
		(member["node"] as Node2D).position.y = y
		if not bool(member["released"]) and y <= int(spec.get("release_y", 100)):
			member["released"] = true
			boss_state += 1
		y -= int(spec.get("px_per_tick", 1))
		member["y"] = y
		if y <= int(spec.get("remove_y", -250)):
			(member["node"] as Node2D).queue_free()
			_members.erase(member)


func _start_fade(direction: int, reload: int) -> void:
	if _fade_direction == 0:
		_fade_level = 16 if direction < 0 else 1
	_fade_direction = direction
	_fade_reload = reload
	_fade_count = reload
	_fade.color.a = _fade_level / 16.0


func _fade_tick() -> void:
	if _fade_direction == 0:
		return
	_fade_count -= 1
	if _fade_count <= 0:
		_fade_count = _fade_reload
		_fade_level += _fade_direction
		if _fade_level <= 0:
			_fade_level = 0
			_fade_direction = 0
		elif _fade_level > 16:
			_fade_level = 16
			_fade_direction = 0
			if phase == "fading_out":
				_leave()
	_fade.color.a = _fade_level / 16.0


func _dark_tick() -> void:
	if _dark_direction == 0:
		return
	_dark_count -= 1
	if _dark_count <= 0:
		_dark_count = int(config.get("dark_screen_ticks_per_level", 6))
		_dark_level = clampi(_dark_level + _dark_direction, 0, 16)
		if _dark_level == 0 or _dark_level == 16:
			_dark_direction = 0
	_dark.color.a = _dark_level / 16.0


func _play_music(cue_id: String) -> void:
	var cue: Variant = _music_cues.get(cue_id)
	if not cue is Dictionary or _music == null or not GameSettings.music_starts():
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


## Plays STORYOVER step by step: a delay waits its ticks (a key ends it early), a message shows
## on the shared dialogue board until confirmed, the footstep cue plays, and actDeleteDarkScreen
## lifts the dark screen and ends the script (BOSS state 6 then moves on).
func _run_epilogue_step(index: int) -> void:
	_epilogue_waiting_confirm = false
	_epilogue_delay_ticks = 0
	if index >= epilogue_steps.size():
		_board.clear_message()
		_story_running = false
		return
	epilogue_step = index
	var step: Dictionary = epilogue_steps[index]
	match str(step.get("kind", "")):
		"delay":
			_board.clear_message()
			_epilogue_delay_ticks = maxi(roundi(float(step.get("seconds", 0.0)) / OriginalTick.TICK_SECONDS), 1)
		"message":
			var message_id := str(step.get("message_id", ""))
			_board.show_message(message_id, str(step.get("speaker", "")), str(step.get("text", "")), str(step.get("actor_id", "")))
			epilogue_messages.append(message_id)
			_epilogue_waiting_confirm = true
		"sound":
			if _sound != null:
				_sound.play()
			_run_epilogue_step(index + 1)
		"reveal":
			_dark_direction = -1
			_dark_count = int(config.get("dark_screen_ticks_per_level", 6))
			_run_epilogue_step(index + 1)
		_:
			_run_epilogue_step(index + 1)


func _epilogue_tick() -> void:
	if not _story_running or _epilogue_delay_ticks <= 0:
		return
	_epilogue_delay_ticks -= 1
	if _epilogue_delay_ticks <= 0:
		_run_epilogue_step(epilogue_step + 1)


## A key / click: confirms or pages the dialogue line, ends a dialogue pause, or — once the
## credits rest (BOSS state 19) — leaves for the title. Under OPT-PACE 原版 nothing else reads
## input; 快／極快 let a confirm (`confirm`) outside the dialogue skip to the next segment.
func advance(confirm: bool = true) -> Dictionary:
	if phase == "waiting":
		return dismiss()
	if _story_running:
		if _epilogue_waiting_confirm:
			if not _board.advance_page():
				_run_epilogue_step(epilogue_step + 1)
		elif _epilogue_delay_ticks > 0:
			_run_epilogue_step(epilogue_step + 1)
	elif confirm and not GameOptions.is_original("OPT-PACE"):
		skip_segment()
	return summary()


## OPT-PACE 快／極快 skip (remake-invented; the order of segments, music cues and the final
## key-to-title stay the original's): the opening fade and wait end, a narration scroll ends, the
## waits around the monologue end (its lines still confirm one by one), the showcase moves to
## the next member (after the ninth, to the credits), and the credits rest at once so the next
## key leaves for the title. Returns whether anything was skipped.
func skip_segment() -> bool:
	if phase == "fading_out" or phase == "waiting" or _story_running:
		return false
	if _fade_direction < 0:
		_fade_level = 0
		_fade_direction = 0
		_fade.color.a = 0.0
	match boss_state:
		0:
			boss_state = 1
		1, 2:
			_end_scroll()
			boss_state = 3
		3, 4:
			if boss_state == 3:
				_boss_tick()
			_dark_level = 16
			_dark_direction = 0
			_dark.color.a = 1.0
			boss_counter = 0
		7, 8:
			_dark_level = 0
			_dark_direction = 0
			_dark.color.a = 0.0
			boss_state = 9
		9, 10:
			_end_scroll()
			boss_state = 11
		11, 12:
			if boss_state == 11:
				_boss_tick()
			boss_counter = 1
		13, 14, 15:
			if boss_state == 13:
				_boss_tick()
			for member in _members:
				(member["node"] as Node2D).queue_free()
			_members.clear()
			boss_state = 15
		16, 17:
			if boss_state == 16:
				_boss_tick()
			boss_counter = 1
		18:
			if _scroll.is_empty() or bool(_scroll["done"]):
				return false
			_scroll["y"] = int(_scroll["y"]) - int(_scroll["remaining"])
			_end_scroll()
			_place_scroll()
			boss_state = 19
			phase = "waiting"
		_:
			return false
	return true


func _end_scroll() -> void:
	if _scroll.is_empty() or bool(_scroll["done"]):
		return
	_scroll["remaining"] = 0
	_scroll["done"] = true
	if bool(_scroll["removed"]):
		_text.visible = false
		_text.texture = null


func dismiss() -> Dictionary:
	if phase != "waiting":
		return {}
	phase = "fading_out"
	transition = {"scene": TITLE_SCENE_PATH, "status": "fading"}
	# 0x42cc10(0,0) → 0x42dc90(2): 2 ticks a level; the music plays on until the scene change.
	_start_fade(1, int(config.get("exit_fade_ticks_per_level", 2)))
	return transition


func _leave() -> void:
	transition["status"] = "scene_changed"
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
		var confirm: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) \
				or (event is InputEventKey and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE))
		# OPT-PACE 原版: the monologue board reads no key while its page wipes in or scrolls.
		if _story_running and _epilogue_waiting_confirm and _board.holds_confirm():
			return
		advance(confirm)


func summary() -> Dictionary:
	return {
		"schema": "hsl_game_clear_screen.v1",
		"phase": phase,
		"boss_state": boss_state,
		"ticks": ticks_elapsed,
		"fade_level": _fade_level,
		"dark_level": _dark_level,
		"slots_shown": slots_shown.duplicate(),
		"members_on_screen": _members.size(),
		"epilogue_step": epilogue_step,
		"epilogue_step_count": epilogue_steps.size(),
		"epilogue_messages": epilogue_messages.duplicate(),
		"epilogue_waiting_confirm": _epilogue_waiting_confirm,
		"epilogue_speaker": str(_board.speaker_label.text) if _board != null and _board.visible else "",
		"epilogue_sound_playing": _sound != null and _sound.playing,
		"text_position": _text.position if _text != null else Vector2.ZERO,
		"text_visible": _text != null and _text.visible,
		"music_stream": _music.stream.resource_path if _music != null and _music.stream != null else "",
		"music_playing": _music != null and _music.playing,
		"music_volume_db": _music.volume_db if _music != null else 0.0,
		"transition": transition.duplicate(true),
	}

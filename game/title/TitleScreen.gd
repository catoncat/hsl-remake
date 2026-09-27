extends Node2D
## Title screen — the product entry. Draws the original Title*.SHP shapes at the layout
## measured from the reference recording (content/imported/hsl/global/title/manifest.json,
## tools/hsltools/assets/title_assets.py) and runs the three-item ring menu:
##   開始新故事 -> fresh campaign (clears the saved position) -> intro film -> BattleSceneRuntime
##                 on campaign.json start_level (the film is campaign.json start_movie; chapter 1
##                 names movie.pak start.ani: the original's level-entry routine 0x42da60 plays it on
##                 entering level 51 unless a re-entry flag is set — static-derived; playing it
##                 between the fade and the first scene, and skipping on any key, are remake readings)
##   戰場記錄   -> continue the saved campaign position (CampaignProgress) -> BattleSceneRuntime
##   離開遊戲   -> quit
## The gem (Title027) and the book (Title028) stay beside item 1 whatever is selected and bob
## vertically on their own sine clocks (runtime-measured on the original,
## docs/evidence_packets/runtime_observations/original_title_ornaments/README.md). The red lit
## item shape shows on the hovered item, or on the keyboard-selected one after an arrow key.
## Confirming an item lights it (the red Title024-026 shape with its white flare), holds
## CONFIRM_HOLD_SECONDS, then fades to black over FADE_TO_BLACK_SECONDS; the version string
## V1.06 stays at the bottom-left corner (runtime-measured on the 2026-09-24 recording,
## docs/evidence_packets/runtime_observations/menus_ui/README.md). The hover lit rule is a remake
## reading (provisional) — see manifest.unresolved_semantics. The title plays the original track
## 03 (manifest.music: level 0's table track, played after the vendor logos —
## docs/evidence_packets/static_reverse/original_music.md §3.1; the remake has no logo stage, so it
## starts with the title); like every level exit it stops at once on the scene change or when the
## intro film starts, and holds its volume through the fade to black.
## provenance:
##   rules: static-derived docs/evidence_packets/resource_inventory/original_movies.md
##   rules: provisional (0x4c1ae4 read as a re-entry marker)
##   rules: remake-invented (戰場記錄 resumes checkpoint or campaign position; film placed between fade and first scene)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (V1.06 ink box (3,459)–(41,467), 8 px glyph advance, white; not baked into Title001)
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#01
##     (background／logo／ring／statue corners and first-item gem＋book measured on 01/frame_001)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (gem and book stay beside item 1 whatever is selected; vertical travel −2…+8 px)
##   layout: remake-invented (lit shape on the keyboard-selected item)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (「V1.06」; negative-evidence: not an ASCII／UTF-16 string of hsl01.exe)
##   strings: remake-invented (「沒有戰場記錄」hint)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (gem／book bob period ≈1.65 s, amplitude ≈5 px, no fixed phase relation)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (開始新故事 click: lit shape from 13.52 s, fade 14.27→14.82 s — 0.75 s hold, 0.55 s fade)
##   timing: provisional
##     (period and amplitude are fits to 4–5 fps samples; random start phases; the same hold／fade for 戰場記錄, 1.6 s hint,
##     hover lit rule)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json

const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const MoviePlayer = preload("res://game/title/MoviePlayer.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const FIRST_SCENE_PATH := "res://game/battle/scene/BattleSceneRuntime.tscn"
## Confirm → black: the lit item holds, then the screen fades (runtime-measured on the user
## recording: lit at 13.52 s, black ramp 14.27 → 14.82 s). FADE_SECONDS is the whole span.
const CONFIRM_HOLD_SECONDS := 0.75
const FADE_TO_BLACK_SECONDS := 0.55
const FADE_SECONDS := CONFIRM_HOLD_SECONDS + FADE_TO_BLACK_SECONDS
## The version string at the bottom-left corner (runtime-measured: a white fixed-pitch
## bitmap font, 8 px advance, ink (3,459)–(41,467)). It is ASCFONT.15 (8×15 half cells, ink
## rows 3–11 and columns 1–7), so the cells start at (2,456); the small face draws a half
## glyph 2 px below its 16 px line, hence the line box top 454.
const VERSION_TEXT := "V1.06"
const VERSION_BOX := Rect2(2, 454, 40, 16)
const VERSION_ADVANCE := 8.0
const VERSION_FONT_SIZE := 13
const HINT_SECONDS := 1.6
const NO_RECORD_HINT := "沒有戰場記錄"
## Gem／book bob (runtime-measured, original_title_ornaments): sine period and amplitude are
## fits to 4–5 fps samples (provisional). Each swings from 2 px above to 8 px below its
## manifest position: the reference frame 01/frame_001 caught the gem near the top of its
## swing and the book near the measurement template's position.
const ORNAMENT_BOB_PERIOD := 1.646
const ORNAMENT_BOB_AMPLITUDE := 5.0
const ORNAMENT_BOB_REST_OFFSET := 3.0

var manifest: Dictionary = {}
var items: Array = []
var selected := 0
var hovered := -1
var transition: Dictionary = {}
var quit_requested := false
var menu_locked := false

var _sprites: Dictionary = {}
var _lit: Array[Sprite2D] = []
var _gem: Sprite2D
var _hand: Sprite2D
var _fade: ColorRect
var _hint: Label
var _music: AudioStreamPlayer
var _hint_token := 0
## Seconds of ornament bob; the gem and the book each start at their own random phase (the
## original's phase difference changed between samples — neither in step nor opposed).
var ornament_clock := 0.0
var ornament_phases := Vector2.ZERO
## An arrow key moved the selection: the selected item shows its lit shape until the mouse
## hovers one.
var _keyboard_lit := false
## The confirmed item keeps its lit shape through the hold and the fade; -1 before a confirm.
var _confirmed_index := -1
var _version: Control
## The intro film while it plays (開始新故事 after the fade); null otherwise.
var intro_player: CanvasLayer


func _ready() -> void:
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	items = manifest.get("items", [])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ornament_phases = Vector2(rng.randf() * TAU, rng.randf() * TAU)
	_build_scene()
	_place_ornaments()
	_refresh_lit()


func _build_scene() -> void:
	for role in ["background", "logo", "statue_left", "statue_right", "ring"]:
		_sprites[role] = _sprite(role, _layout_top_left(role))
	var ring_top_left := _layout_top_left("ring")
	for item in items:
		var lit := _sprite(str(item["lit"]), ring_top_left + Vector2(float(item["lit_offset_in_ring"][0]), float(item["lit_offset_in_ring"][1])))
		lit.visible = false
		_lit.append(lit)
	_gem = _sprite("cursor_gem", _layout_top_left("cursor_gem"))
	_hand = _sprite("cursor_hand", _layout_top_left("cursor_hand"))
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 10
	add_child(overlay)
	_hint = BattleUISkin.label(overlay, Vector2(0, 442), 18)
	_hint.size = Vector2(640, 28)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = ""
	_version = Control.new()
	_version.name = "Version"
	_version.position = VERSION_BOX.position
	_version.size = VERSION_BOX.size
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_version)
	for index in VERSION_TEXT.length():
		var glyph := BattleUISkin.text(_version, Vector2(VERSION_ADVANCE * index, 0), Color.WHITE, VERSION_FONT_SIZE, Vector2(VERSION_ADVANCE, VERSION_BOX.size.y))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_constant_override("shadow_offset_x", 0)
		glyph.add_theme_constant_override("shadow_offset_y", 0)
		glyph.text = VERSION_TEXT[index]
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.size = Vector2(640, 480)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_fade)
	_start_music()


## The original title track 03 (manifest.music, original_music.md §3.1), looping whole from the start.
func _start_music() -> void:
	var stream_path := str((manifest.get("music", {}) as Dictionary).get("stream", ""))
	if stream_path == "":
		return
	var stream: AudioStream = load(stream_path)
	if stream == null:
		push_error("Title music failed to load: " + stream_path)
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music = AudioStreamPlayer.new()
	_music.name = "TitleMusic"
	_music.stream = stream
	_music.volume_db = GameSettings.MUSIC_PLAYER_DB
	_music.bus = GameSettings.music_bus()
	add_child(_music)
	_music.play()


func _sprite(role: String, top_left: Vector2) -> Sprite2D:
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(role, {})
	var sprite := Sprite2D.new()
	sprite.name = "Title_" + role
	sprite.centered = false
	sprite.texture = load(str(entry.get("texture", "")))
	sprite.position = top_left
	add_child(sprite)
	return sprite


func _layout_top_left(role: String) -> Vector2:
	var entry: Dictionary = (manifest.get("layout", {}) as Dictionary).get(role, {})
	var value: Array = entry.get("top_left", [0, 0])
	return Vector2(float(value[0]), float(value[1]))


func _process(delta: float) -> void:
	ornament_clock += delta
	_place_ornaments()


## The original gem and book never move sideways and do not follow the selection: both bob
## about their item-1 positions (original_title_ornaments: mean positions differ ≤0.3 px
## between hovering items 1, 2 and 3).
func _place_ornaments() -> void:
	if _gem == null or _hand == null:
		return
	_gem.position = _layout_top_left("cursor_gem") + Vector2(0, ornament_offset(ornament_phases.x))
	_hand.position = _layout_top_left("cursor_hand") + Vector2(0, ornament_offset(ornament_phases.y))


func ornament_offset(phase: float) -> float:
	return ORNAMENT_BOB_REST_OFFSET + ORNAMENT_BOB_AMPLITUDE * sin(TAU * ornament_clock / ORNAMENT_BOB_PERIOD + phase)


func _refresh_lit() -> void:
	var lit_index := _confirmed_index if _confirmed_index >= 0 else (hovered if hovered >= 0 else (selected if _keyboard_lit else -1))
	for index in _lit.size():
		_lit[index].visible = index == lit_index


func item_rect(index: int) -> Rect2:
	var item: Dictionary = items[index]
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(str(item["lit"]), {})
	var size: Array = entry.get("size", [0, 0])
	return Rect2(_lit[index].position, Vector2(float(size[0]), float(size[1])))


func select(index: int) -> void:
	if items.is_empty() or menu_locked:
		return
	selected = wrapi(index, 0, items.size())
	_keyboard_lit = true
	_refresh_lit()


func hover_at(logical_point: Vector2) -> int:
	var found := -1
	for index in items.size():
		if item_rect(index).has_point(logical_point):
			found = index
	if found != hovered:
		hovered = found
		if found >= 0 and not menu_locked:
			selected = found
			_keyboard_lit = false
		_refresh_lit()
	return found


func selected_item_id() -> String:
	return str(items[selected]["id"]) if not items.is_empty() else ""


## Runs the selected item. Returns the transition record (also kept in `transition`).
func confirm() -> Dictionary:
	if items.is_empty() or menu_locked:
		return {}
	var action := selected_item_id()
	match action:
		"new_story":
			# A fresh campaign opens at campaign.json's start_level: the runtime boots with
			# no hand-off and resolves it (BattleSceneRuntime.scenario_path empty).
			CampaignProgress.reset_campaign()
			var campaign := CampaignProgress.load_campaign()
			_start_transition(action, FIRST_SCENE_PATH)
			transition["start_scenario_path"] = CampaignProgress.first_scenario_path(campaign)
			transition["start_movie"] = str(campaign.get("start_movie", ""))
		"battle_record":
			# A mid-battle checkpoint (the original's 戰場記錄) wins; otherwise the auto-saved
			# campaign position (remake reading); otherwise 沒有戰場記錄.
			var records: Array = CampaignProgress.battle_record_entries()
			var saved := CampaignProgress.load_progress()
			if not records.is_empty():
				var newest: Dictionary = records[0]
				CampaignProgress.queue_battle_record(newest)
				_start_transition(action, FIRST_SCENE_PATH, str(newest.get("scenario_path", "")))
				transition["battle_record"] = str(newest.get("save_path", ""))
			elif saved.is_empty():
				show_hint(NO_RECORD_HINT)
				transition = {"action": action, "status": "no_record"}
			else:
				CampaignProgress.queue_resume(saved)
				_start_transition(action, FIRST_SCENE_PATH, str(saved.get("scenario_path", "")))
		"quit":
			quit_requested = true
			transition = {"action": action, "status": "quit"}
			if DisplayServer.get_name() != "headless":
				get_tree().quit()
	return transition


func _start_transition(action: String, scene_path: String, resume_scenario: String = "") -> void:
	menu_locked = true
	_confirmed_index = selected
	_refresh_lit()
	transition = {"action": action, "scene": scene_path, "status": "fading"}
	if resume_scenario != "":
		transition["resume_scenario_path"] = resume_scenario
	var tween := create_tween()
	tween.tween_interval(CONFIRM_HOLD_SECONDS)
	# The music keeps its volume: the original stops it at once on leaving the level (§3.1).
	tween.tween_property(_fade, "color:a", 1.0, FADE_TO_BLACK_SECONDS)
	tween.finished.connect(_on_fade_finished.bind(scene_path))


func _on_fade_finished(scene_path: String) -> void:
	if str(transition.get("action", "")) == "new_story" and str(transition.get("start_movie", "")) != "":
		_play_intro(scene_path, str(transition["start_movie"]))
		return
	_change_scene(scene_path)


func _change_scene(scene_path: String) -> void:
	transition["status"] = "scene_changed"
	get_tree().change_scene_to_file(scene_path)


## The intro film between the fade and the first scene (campaign.json `start_movie`: the
## chapter-1 campaign names start.ani; a campaign without it boots its start level directly);
## its end (or a skip) boots the scene.
func _play_intro(scene_path: String, movie: String) -> void:
	if _music != null:
		_music.stop()
	intro_player = MoviePlayer.new()
	intro_player.name = "IntroMovie"
	add_child(intro_player)
	intro_player.finished.connect(_on_intro_finished.bind(scene_path))
	transition["status"] = "movie"
	intro_player.play(movie)


func _on_intro_finished(reason: String, scene_path: String) -> void:
	transition["movie"] = reason
	if intro_player != null:
		intro_player.queue_free()
		intro_player = null
	_change_scene(scene_path)


## Skips the intro film (tests and any key / click while it plays).
func skip_intro() -> Dictionary:
	if intro_player == null:
		return {}
	return intro_player.skip()


func show_hint(text: String) -> void:
	_hint.text = text
	_hint_token += 1
	var token := _hint_token
	get_tree().create_timer(HINT_SECONDS, false).timeout.connect(func() -> void:
		if token == _hint_token and is_instance_valid(_hint):
			_hint.text = "")


func _unhandled_input(event: InputEvent) -> void:
	if menu_locked or items.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_UP or key == KEY_W:
			select(selected - 1)
		elif key == KEY_DOWN or key == KEY_S:
			select(selected + 1)
		elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_Z:
			confirm()
		elif key == KEY_ESCAPE:
			select(items.size() - 1)
	elif event is InputEventMouseMotion:
		hover_at(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if hover_at(get_global_mouse_position()) >= 0:
			confirm()


func summary() -> Dictionary:
	return {
		"schema": "hsl_title_screen.v1",
		"manifest_schema": str(manifest.get("schema", "")),
		"items": items.map(func(item): return str(item["id"])),
		"selected": selected,
		"selected_item_id": selected_item_id(),
		"hovered": hovered,
		"gem_position": _gem.position if _gem != null else Vector2.ZERO,
		"hand_position": _hand.position if _hand != null else Vector2.ZERO,
		"ornament_phases": ornament_phases,
		"lit_visible": _lit.map(func(sprite): return sprite.visible),
		"transition": transition.duplicate(true),
		"quit_requested": quit_requested,
		"hint": _hint.text if _hint != null else "",
		"version_text": "".join(_version.get_children().map(func(glyph): return glyph.text)) if _version != null else "",
		"music_stream": _music.stream.resource_path if _music != null and _music.stream != null else "",
		"music_playing": _music.playing if _music != null else false,
		"music_volume_db": _music.volume_db if _music != null else 0.0,
	}

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
##   (playtest switch HSL_SKIP_TITLE=1, off by default: the first title of the process runs this
##    item's resume at once, without the menu, the hold or the fade — tools/playtest.sh)
##   With campaigns registered beside chapter 1 (content/authored/campaigns.json, not hidden),
##   開始新故事 first asks which on the object 704 select board; 戰場記錄 continues the campaign
##   saved last and a 回憶錄 row its own campaign. Chapter 1 alone: no board, nothing changes.
##   離開遊戲   -> quit after the same lit hold and fade (handler 0x423f00: every item waits out
##                 the hold timer, state 3 0x424004; code 2 0x4240b2 fades via 0x42cb60／0x42dc90(2))
## The gem (Title027) and the book (Title028) stay beside item 1 whatever is selected and bob
## vertically on their own angle counters: defProcMainMenuItem 0x424360 (static-derived,
## docs/evidence_packets/runtime_observations/original_title_ornaments/README.md). The menu
## (ring, items, statues, gem, book) opens 300 px low and slides up at 0x45e882 speed 40 before
## it takes input. The original lights no item on hover: the hovered item, gem or book throws
## Menu_Star sparkles (object 788) every 6 ticks, a click adds Menu_Star2 (789); OPT-GUIDE＝提示
## shows the red lit shape on the hovered item. Clicking the gem opens 設定選項 and the book the
## 讀取回憶錄 list (BattleSystemMenu.open_standalone) after a 10-tick hold; the menu stays drawn and inert until the
## window goes back. An arrow key lights the keyboard-selected item (remake keyboard path).
## Clicking an item plays ACCEPT01 (RESOURCE 398, defProcMainMenuString 0x4242d6). Confirming an item lights it (the red Title024-026 shape with its white flare), holds
## CONFIRM_HOLD_TICKS, then fades to black in 16 levels over OriginalFade.DONE_TICKS; the version string
## V1.06 stays at the bottom-left corner (runtime-measured on the 2026-09-24 recording,
## docs/evidence_packets/runtime_observations/menus_ui/README.md). 戰場記錄 with nothing to resume
## shows message 12「無存檔記錄」in red (@2) on the BOARD02 message board (0x42404c → 0x4072b0). The title plays the original track
## 03 (manifest.music: level 0's table track, played after the vendor logos —
## docs/evidence_packets/static_reverse/original_music.md §3.1; the remake has no logo stage, so it
## starts with the title); like every level exit it stops at once on the scene change or when the
## intro film starts, and holds its volume through the fade to black.
## provenance:
##   rules: static-derived docs/evidence_packets/resource_inventory/original_movies.md
##   rules: provisional (0x4c1ae4 read as a re-entry marker)
##   rules: remake-invented (戰場記錄 resumes checkpoint or campaign position; film placed between fade and first scene;
##     HSL_SKIP_TITLE=1 playtest switch; campaign choice when several are registered)
##   rules: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (gem code 10 → 設定選項 0x423b90, book code 11 → memoir list 0x423bd0; menu inert meanwhile)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (V1.06 ink box (3,459)–(41,467), 8 px advance; no-record board at (75,320))
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#01
##     (background／logo／ring／statue corners and first-item gem＋book measured on 01/frame_001)
##   layout: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (gem／book spawn at ring＋(33,112)／(207,107), 0x423e06／0x423e32; y＝spawn＋trunc(6·sin), 0x424406)
##   layout: remake-invented (lit shape on the keyboard-selected item; hover lit under OPT-GUIDE＝提示,
##     content/authored/options/remake_options.json)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (「V1.06」; negative-evidence: not an ASCII／UTF-16 string of hsl01.exe)
##   strings: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (無存檔記錄 message 12 via 0x4072b0, an @2 red line)
##     (戰場記錄 code 1 0x42404c: message 12「無存檔記錄」, 11「讀取存檔失敗」)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (bob angle +3／tick, 0x424389; slide 0x45e882 speed 40; sparkles 0x4241a0／0x41f5db)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (開始新故事 click: lit shape from 13.52 s, fade 14.27→14.82 s — 0.75 s hold, 0.55 s fade)
##   timing: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (hold = obj_Data8, 40／10 ticks, 0x424004; fade 0x42dc90(2): +1 level／2 ticks, 0x460a58)
##   timing: provisional
##     (the message board reuses the save notice's in／hold／out)
##     (Menu_Star's unset Shape_Delay taken as 0; memoir load fades without a hold)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json
##   audio: static-derived docs/evidence_packets/runtime_observations/original_title_ornaments/README.md
##     (item click plays ACCEPT01 RESOURCE 398, 0x4242d6; the 回憶錄 row click too, 0x425370)

const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const OriginalFade = preload("res://game/common/OriginalFade.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const MoviePlayer = preload("res://game/title/MoviePlayer.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const FIRST_SCENE_PATH := "res://game/battle/scene/BattleSceneRuntime.tscn"
## Confirm → black (static-derived, menus_ui §1): a click hands the item's obj_Data8 to the
## menu's hold timer +0xa8 (0x424302); state 3 0x424004 counts it down one a tick and runs the
## code at 0 — 40 ticks for the three text items, 10 for the gem and the book. The exits fade
## through 0x42dc90(2) → 0x46098f: level 1 at once, one level every 2 ticks (0x460a58), black
## (16) after 30 ticks, done at 32. On the 19.4 ms host that is 0.78 s + 0.58 s, matching the
## recording (lit 13.52 s, black ramp 14.27 → 14.82 s). FADE_SECONDS is the whole span.
const CONFIRM_HOLD_TICKS := 40
const WINDOW_HOLD_TICKS := 10
const CONFIRM_HOLD_SECONDS := CONFIRM_HOLD_TICKS * OriginalTick.TICK_SECONDS
const FADE_TO_BLACK_SECONDS := OriginalFade.TO_BLACK_SECONDS
const FADE_SECONDS := CONFIRM_HOLD_SECONDS + FADE_TO_BLACK_SECONDS
## The version string at the bottom-left corner (runtime-measured: a white fixed-pitch
## bitmap font, 8 px advance, ink (3,459)–(41,467)). It is ASCFONT.15 (8×15 half cells, ink
## rows 3–11 and columns 1–7), so the cells start at (2,456); the small face draws a half
## glyph 2 px below its 16 px line, hence the line box top 454.
const VERSION_TEXT := "V1.06"
const VERSION_BOX := Rect2(2, 454, 40, 16)
const VERSION_ADVANCE := 8.0
const VERSION_FONT_SIZE := 13
## 戰場記錄 with nothing to resume: message 12 on the BOARD02 board (0x4072b0; same board, place
## and in／hold／out as the battle scroll's save notice, BattleSystemMenu).
const NO_RECORD_MESSAGE := "無存檔記錄"
const MESSAGE_AT := Vector2(75, 320)
const MESSAGE_TEXT_Y := 44.0
const MESSAGE_IN_SECONDS := 0.25
const MESSAGE_HOLD_SECONDS := 0.95
const MESSAGE_OUT_SECONDS := 0.15
## Gem／book bob (static-derived, original_title_ornaments): defProcMainMenu 0x423cd0 spawns
## Item1 (gem) and Item2 (book) at the menu position (the ring's top-left) plus these offsets;
## each tick defProcMainMenuItem 0x424360 sets y = spawn y + trunc(6 · sin(angle·2π/256)) via
## 0x45e9bc (16.16 sine table 0x4a39fc, radius 0x60000) and advances the byte angle by 3; x
## never changes. The start angle is rand() % 255, drawn separately for each object (0x424389).
const ORNAMENT_SPAWN_OFFSETS := {"cursor_gem": Vector2(33, 112), "cursor_hand": Vector2(207, 107)}
const ORNAMENT_RADIUS := 6
const ORNAMENT_ANGLE_STEP := 3
const ORNAMENT_ANGLE_START_MODULO := 255
## One full swing: 256 / 3 ticks.
const ORNAMENT_BOB_PERIOD := 256.0 / ORNAMENT_ANGLE_STEP * OriginalTick.TICK_SECONDS
const INTERFACE_AUDIO_PATH := "res://content/imported/hsl/shared/interface_audio/manifest.json"
## Menu slide-in (static-derived, original_title_ornaments): defProcMainMenu 0x423cd0 first frame
## puts the menu (ring, the three items, both statues, gem and book) 300 px below its rest
## (0x423d06); state 0 steps it back with 0x45e882 speed 40 (each tick min(40, distance >> 3),
## at least 2, landing inside 1 px) and 0x45efce carries the children; the menu takes input only
## after it lands (state 1 arms 0x10000). Background and logo do not move.
const MENU_SLIDE_DISTANCE := 300
const MENU_SLIDE_CAP := 40
const MENU_SLIDE_SHIFT := 3
const MENU_SLIDE_MIN := 2
## Sparkles (static-derived): every title object (the three items, gem and book: 0x4241a0) under
## the mouse while the menu waits for input counts +0x90 down from 6 each tick and at zero spawns
## 4 Menu_Star (object 788) per 32 px column (0x423aa0 → 0x415c10); a click spawns 24 Menu_Star2
## (789) and 16 Menu_Star per column. The stars themselves are MenuStars (shared with the 回憶錄 list).
const MenuStars = preload("res://game/common/MenuStars.gd")
const HOVER_SPARK_TICKS := 6
const HOVER_SPARK_COUNT := 4
const CLICK_SPARK2_COUNT := 24
const CLICK_SPARK_COUNT := 16
## Gem and book carry codes 10 and 11 (Data9): 0x424037 opens 設定選項 (0x423b90) and the
## 讀取回憶錄 list (0x423bd0(…, 0)); the menu stays drawn but takes no input until the window
## writes its result back (states 4／5: 0x424101／0x424117).
const ORNAMENT_CODES := {10: "cursor_gem", 11: "cursor_hand"}
const WINDOW_OF_CODE := {10: "options", 11: "memoir"}
const BattleSystemMenu = preload("res://game/battle/scene/BattleSystemMenu.gd")
const EventSelectWindow = preload("res://game/common/EventSelectWindow.gd")
## The campaign board's last row (RESOURCE 312, tePlayerSelectInsertEvent's leave row).
const CAMPAIGN_LEAVE_TEXT := "離開"
## Playtest switch (tools/playtest.sh): "1" makes the process's first title run 戰場記錄 at once.
const SKIP_TITLE_ENV := "HSL_SKIP_TITLE"
## Once per process: a later return to the title (game over, game clear) shows the menu.
static var _title_skip_used := false

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
var _message: Control
var _message_text: Label
var _message_tween: Tween
var _music: AudioStreamPlayer
var _click_audio: AudioStreamPlayer
## Seconds since the title opened (whole original ticks advance the ornament angles); the gem
## and the book keep their own start angles (0..254), so their phase relation varies per visit.
var ornament_clock := 0.0
var ornament_phases := Vector2i.ZERO
## An arrow key moved the selection: the selected item shows its lit shape until the mouse
## hovers one.
var _keyboard_lit := false
## The confirmed item keeps its lit shape through the hold and the fade; -1 before a confirm.
var _confirmed_index := -1
var _version: Control
## The intro film while it plays (開始新故事 after the fade); null otherwise.
var intro_player: CanvasLayer
## Pixels the menu still sits below its rest (MENU_SLIDE_DISTANCE on open, 0 once landed).
var menu_slide := MENU_SLIDE_DISTANCE
## "" or the window a gem／book click opened ("options" | "memoir").
var window_open := ""
## Gem／book clicked: the code waiting out WINDOW_HOLD_TICKS before its window opens; -1 none.
var window_hold_code := -1
var _window_hold_left := 0
## Code of the title object under the mouse: 0..2 the items, 10 gem, 11 book, -1 none.
var hover_code := -1
var _menu_rest: Dictionary = {}
var _tick_clock := 0.0
var _spark_counters: Dictionary = {}
var _stars: MenuStars
var _rng := RandomNumberGenerator.new()
var _system: Control
## HSL_SKIP_TITLE=1 on this process's first title: no music, 戰場記錄 runs on the first frame.
var skipping_title := false
var _overlay: CanvasLayer
## 開始新故事's campaign board while it is up, and the campaign rows behind it.
var campaign_select: Control
var campaign_choices: Array = []


func _ready() -> void:
	skipping_title = OS.get_environment(SKIP_TITLE_ENV) == "1" and not _title_skip_used
	_title_skip_used = _title_skip_used or skipping_title
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	items = manifest.get("items", [])
	_rng.randomize()
	ornament_phases = Vector2i(_rng.randi() % ORNAMENT_ANGLE_START_MODULO, _rng.randi() % ORNAMENT_ANGLE_START_MODULO)
	_build_scene()
	_apply_menu_slide()
	_refresh_lit()
	if skipping_title:
		call_deferred("_skip_title")


## HSL_SKIP_TITLE=1: the 戰場記錄 resume without the menu, the hold or the fade; with nothing
## to resume the title stays up and shows message 12 as the item would.
func _skip_title() -> void:
	var record := _arm_battle_record()
	if record.is_empty():
		show_message(NO_RECORD_MESSAGE, BattleUISkin.TEXT_RED)
		transition = {"action": "battle_record", "status": "no_record"}
		return
	menu_locked = true
	transition = {"action": "battle_record", "scene": FIRST_SCENE_PATH, "resume_scenario_path": str(record.get("scenario_path", "")), "skipped_title": true}
	_change_scene(FIRST_SCENE_PATH)


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
	for node in [_sprites["ring"], _sprites["statue_left"], _sprites["statue_right"]] + _lit:
		_menu_rest[node] = node.position
	_stars = MenuStars.new()
	_stars.name = "MenuStars"
	add_child(_stars)
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 10
	add_child(overlay)
	_overlay = overlay
	_message = Control.new()
	_message.name = "Message"
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.visible = false
	overlay.add_child(_message)
	BattleUISkin.board(_message, "BOARD02", MESSAGE_AT)
	_message_text = BattleUISkin.text(_message, MESSAGE_AT + Vector2(0, MESSAGE_TEXT_Y), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(489, 24))
	_message_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	_system = BattleSystemMenu.new()
	_system.name = "TitleWindows"
	_system.runtime = self
	overlay.add_child(_system)
	_system.standalone_closed.connect(_on_window_closed)
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
	if stream_path == "" or not GameSettings.music_starts() or skipping_title:
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
	_tick_clock += maxf(delta, 0.0)
	while _tick_clock >= OriginalTick.TICK_SECONDS:
		_tick_clock -= OriginalTick.TICK_SECONDS
		_tick()
	_place_ornaments()


## One original tick: the slide step (0x45e882), hover sparkles (0x4241a0) and the stars.
func _tick() -> void:
	if menu_slide > 0:
		menu_slide = 0 if menu_slide <= 1 else menu_slide - clampi(menu_slide >> MENU_SLIDE_SHIFT, MENU_SLIDE_MIN, MENU_SLIDE_CAP)
		_apply_menu_slide()
	if hover_code >= 0 and menu_armed():
		var left := int(_spark_counters.get(hover_code, HOVER_SPARK_TICKS)) - 1
		if left <= 0:
			left = HOVER_SPARK_TICKS
			spawn_sparkles(hover_code, "hover", HOVER_SPARK_COUNT)
		_spark_counters[hover_code] = left
	if window_hold_code >= 0:
		_window_hold_left -= 1
		if _window_hold_left <= 0:
			var code := window_hold_code
			window_hold_code = -1
			open_window(code)
	_stars.tick()


## The menu waits for input: landed, no window up, not leaving (state 2, +0x80 & 0x10000).
func menu_armed() -> bool:
	return menu_slide == 0 and window_open == "" and window_hold_code < 0 and not menu_locked


func _apply_menu_slide() -> void:
	for node in _menu_rest:
		node.position = _menu_rest[node] + Vector2(0, menu_slide)
	_place_ornaments()


## test hook: land the menu at once (the harness checks the rest layout).
func finish_slide_in() -> void:
	menu_slide = 0
	_apply_menu_slide()


## The original gem and book never move sideways and do not follow the selection: both bob
## about their spawn positions beside item 1 (carried along by the slide-in, 0x424360).
func _place_ornaments() -> void:
	if _gem == null or _hand == null:
		return
	_gem.position = ornament_spawn_top_left("cursor_gem") + Vector2(0, ornament_offset(ornament_phases.x) + menu_slide)
	_hand.position = ornament_spawn_top_left("cursor_hand") + Vector2(0, ornament_offset(ornament_phases.y) + menu_slide)


## Shape rect of a title object by code (items 0..2 by their lit shape, gem 10, book 11).
func code_rect(code: int) -> Rect2:
	if ORNAMENT_CODES.has(code):
		var sprite := _gem if code == 10 else _hand
		return Rect2(sprite.position, sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO)
	return item_rect(code)


## 0x423aa0 over the object's shape (MenuStars.spawn with the title's width／jitter).
func spawn_sparkles(code: int, kind: String, count: int) -> void:
	_stars.spawn(code_rect(code), kind, count)


## Top-left of the ornament's shape at its spawn position (object position minus draw origin).
func ornament_spawn_top_left(role: String) -> Vector2:
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(role, {})
	var origin: Array = entry.get("draw_origin", [0, 0])
	return _layout_top_left("ring") + ORNAMENT_SPAWN_OFFSETS[role] - Vector2(float(origin[0]), float(origin[1]))


## 0x45e9bc: |sin table entry| × radius in 16.16, truncated toward zero, sign restored.
func ornament_offset(start_angle: int) -> int:
	var tick := int(floor(ornament_clock / OriginalTick.TICK_SECONDS))
	var angle := (start_angle + ORNAMENT_ANGLE_STEP * tick) % 256
	var entry := int(round(sin(TAU * angle / 256.0) * 65536.0))
	var magnitude := (absi(entry) * ORNAMENT_RADIUS) >> 16
	return -magnitude if entry < 0 else magnitude


func _refresh_lit() -> void:
	var hover_lit := hovered if hovered >= 0 and not GameOptions.is_original("OPT-GUIDE") else -1
	var lit_index := _confirmed_index if _confirmed_index >= 0 else (hover_lit if hovered >= 0 else (selected if _keyboard_lit else -1))
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
	hover_code = found
	if found < 0:
		for code in ORNAMENT_CODES:
			if code_rect(code).has_point(logical_point):
				hover_code = code
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
	if items.is_empty() or not menu_armed():
		return {}
	var action := selected_item_id()
	match action:
		"new_story":
			var choices := CampaignProgress.listed_campaigns()
			if choices.size() > 1:
				_open_campaign_select(choices)
			else:
				# No board: back to the campaign the process started in (a 回憶錄 or 戰場記錄
				# may have moved it to another since).
				CampaignProgress.use_campaign(CampaignProgress.startup_campaign_id())
				_start_new_story()
		"battle_record":
			var record := _arm_battle_record()
			if record.is_empty():
				show_message(NO_RECORD_MESSAGE, BattleUISkin.TEXT_RED)
				transition = {"action": action, "status": "no_record"}
			else:
				_start_transition(action, FIRST_SCENE_PATH, str(record.get("scenario_path", "")))
				if record.has("save_path"):
					transition["battle_record"] = str(record["save_path"])
		"quit":
			quit_requested = true
			_start_transition(action, "")
	return transition


## A fresh campaign opens at campaign.json's start_level: the runtime boots with no hand-off
## and resolves it (BattleSceneRuntime.scenario_path empty).
func _start_new_story() -> void:
	CampaignProgress.reset_campaign()
	var campaign := CampaignProgress.load_campaign()
	_start_transition("new_story", FIRST_SCENE_PATH)
	transition["start_scenario_path"] = CampaignProgress.first_scenario_path(campaign)
	transition["start_movie"] = str(campaign.get("start_movie", ""))


## 開始新故事 with more than one listed campaign (CampaignProgress.listed_campaigns): the object 704
## select board (EventSelectWindow) names them, with a 離開 row; the menu is inert meanwhile.
func _open_campaign_select(choices: Array) -> void:
	campaign_choices = choices
	var labels: Array[String] = []
	for row in choices:
		labels.append(str(row["title"]) if str(row["title"]) != "" else str(row["id"]))
	campaign_select = EventSelectWindow.open(_overlay, labels, null, [], CAMPAIGN_LEAVE_TEXT, "CampaignSelect", self)
	campaign_select.answered.connect(func(pick: int, leave: bool) -> void: choose_campaign(-1 if leave else pick))
	window_open = "campaign"
	hover_code = -1
	hovered = -1
	_refresh_lit()
	transition = {"action": "new_story", "status": "choosing_campaign"}


## A campaign row picked (the board's click after its fade-out; tests call it directly): the process
## plays that campaign and the new story starts as with one campaign. -1 (離開) returns to the menu.
func choose_campaign(index: int) -> Dictionary:
	if window_open != "campaign":
		return {}
	if campaign_select != null:
		campaign_select.queue_free()
		campaign_select = null
	window_open = ""
	if index < 0 or index >= campaign_choices.size():
		transition = {"action": "new_story", "status": "campaign_cancelled"}
		return transition
	CampaignProgress.use_campaign(str(campaign_choices[index]["id"]))
	_start_new_story()
	transition["campaign_id"] = str(campaign_choices[index]["id"])
	return transition


## 戰場記錄: a mid-battle checkpoint (the original's 戰場記錄) wins; otherwise the auto-saved
## campaign position (remake reading). Arms it as the next boot's hand-off and returns it
## ({} when there is neither: message 12 無存檔記錄). It reads the campaign saved last
## (CampaignProgress.latest_saved_campaign_id) and moves the process there only once that
## campaign yields a readable record; otherwise the process stays where it is.
func _arm_battle_record() -> Dictionary:
	var id := CampaignProgress.latest_saved_campaign_id()
	var data := CampaignProgress.load_campaign(CampaignProgress.campaign_path_of(id))
	var records: Array = CampaignProgress.battle_record_entries(data, id) if not data.is_empty() else []
	var saved := CampaignProgress.load_progress(CampaignProgress.progress_path(id)) if records.is_empty() else {}
	if records.is_empty() and saved.is_empty():
		return {}
	CampaignProgress.use_campaign(id)
	if not records.is_empty():
		CampaignProgress.queue_battle_record(records[0])
		return records[0]
	CampaignProgress.queue_resume(saved)
	return saved


func _start_transition(action: String, scene_path: String, resume_scenario: String = "", lit_hold := true) -> void:
	menu_locked = true
	_confirmed_index = selected if lit_hold else -1
	_refresh_lit()
	transition = {"action": action, "scene": scene_path, "status": "fading"}
	if resume_scenario != "":
		transition["resume_scenario_path"] = resume_scenario
	var tween := create_tween()
	if lit_hold:
		tween.tween_interval(CONFIRM_HOLD_SECONDS)
	# The music keeps its volume: the original stops it at once on leaving the level (§3.1).
	tween.tween_method(_set_fade_level, 0.0, FADE_TO_BLACK_SECONDS, FADE_TO_BLACK_SECONDS)
	tween.finished.connect(_on_fade_finished.bind(scene_path))


func _set_fade_level(elapsed: float) -> void:
	_fade.color.a = OriginalFade.alpha(elapsed)


func _on_fade_finished(scene_path: String) -> void:
	if str(transition.get("action", "")) == "quit":
		transition["status"] = "quit"
		if DisplayServer.get_name() != "headless":
			get_tree().quit()
		return
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
## test hook
func skip_intro() -> Dictionary:
	if intro_player == null:
		return {}
	return intro_player.skip()


## RESOURCE.TXT 12 is an @2 (red) line.
func show_message(text: String, color: Color = BattleUISkin.TEXT_WHITE) -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_text.text = text
	_message_text.add_theme_color_override("font_color", color)
	_message.modulate.a = 0.0
	_message.visible = true
	_message_tween = create_tween()
	_message_tween.tween_property(_message, "modulate:a", 1.0, MESSAGE_IN_SECONDS)
	_message_tween.tween_interval(MESSAGE_HOLD_SECONDS)
	_message_tween.tween_property(_message, "modulate:a", 0.0, MESSAGE_OUT_SECONDS)
	_message_tween.tween_callback(func() -> void: _message.visible = false)


## A gem／book click: the menu stops taking input and counts the item's hold (0x424004) before
## open_window runs.
func press_window(code: int) -> void:
	if not menu_armed() or not WINDOW_OF_CODE.has(code):
		return
	window_hold_code = code
	_window_hold_left = WINDOW_HOLD_TICKS


## Gem (code 10) → 設定選項, book (11) → the 讀取回憶錄 list (0x424037 → 0x423b90／0x423bd0).
func open_window(code: int) -> Dictionary:
	if not menu_armed() or not WINDOW_OF_CODE.has(code):
		return {}
	var result: Dictionary = _system.open_standalone(WINDOW_OF_CODE[code])
	if bool(result.get("ok", false)):
		window_open = WINDOW_OF_CODE[code]
		hover_code = -1
		hovered = -1
		_refresh_lit()
	return result


func _on_window_closed(_kind: String) -> void:
	window_open = ""


## The memoir list's slot confirmed (0x424117: result 1 → load and leave the title): arm the
## record like 戰場記錄 and fade out without a lit item; the list stays drawn, inert, under the
## 0x42dc90(2) fade (BattleSystemMenu holds it in its "loading" phase).
func resume_memoir_record(record: Dictionary) -> void:
	_system.standalone = ""
	window_open = ""
	CampaignProgress.use_memoir_campaign(record)
	CampaignProgress.queue_resume(record)
	_start_transition("load_memoir", FIRST_SCENE_PATH, str(record.get("scenario_path", "")), false)


## BattleSystemMenu's logical mapping; the title has no camera.
func viewport_to_logical_position(position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * position


func _unhandled_input(event: InputEvent) -> void:
	if _system != null and _system.active():
		_system.handle_input(event)
		return
	if window_open == "campaign":
		if (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE) \
				or (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT):
			# The board fades out first; its answered (leave) then returns to the menu.
			if campaign_select != null:
				campaign_select.dismiss()
		return
	if not menu_armed() or items.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_UP or key == KEY_W:
			select(selected - 1)
		elif key == KEY_DOWN or key == KEY_S:
			select(selected + 1)
		elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_Z:
			play_click_sound()
			confirm()
		elif key == KEY_ESCAPE:
			select(items.size() - 1)
	elif event is InputEventMouseMotion:
		hover_at(get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var index := hover_at(get_global_mouse_position())
		if hover_code >= 0:
			play_click_sound()
			spawn_sparkles(hover_code, "click", CLICK_SPARK2_COUNT)
			spawn_sparkles(hover_code, "hover", CLICK_SPARK_COUNT)
		if index >= 0:
			confirm()
		elif WINDOW_OF_CODE.has(hover_code):
			press_window(hover_code)


## BattleSystemMenu's interface sounds on the title: the 回憶錄 row click (0x425370) is the
## same ACCEPT01.
func play_ui_sound(event: String) -> void:
	if event == "confirm":
		play_click_sound()


## defProcMainMenuString 0x4242d6: a click on an item plays ACCEPT01 (RESOURCE 398).
func play_click_sound() -> void:
	if _click_audio == null:
		var audio: Variant = ContentPaths.read_json(INTERFACE_AUDIO_PATH)
		var entry: Dictionary = (audio.get("sounds", {}) as Dictionary).get("confirm", {}) if typeof(audio) == TYPE_DICTIONARY else {}
		if int(entry.get("resource_id", 0)) != 398:
			return
		_click_audio = AudioStreamPlayer.new()
		_click_audio.name = "ClickSound"
		_click_audio.volume_db = -6.0 # the battle runtime's interface-sound level
		_click_audio.stream = load(str(entry.get("res_path", "")))
		add_child(_click_audio)
	_click_audio.play()


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
		"menu_slide": menu_slide,
		"hover_code": hover_code,
		"stars": _stars.count() if _stars != null else 0,
		"window": window_open,
		"lit_visible": _lit.map(func(sprite): return sprite.visible),
		"transition": transition.duplicate(true),
		"quit_requested": quit_requested,
		"message": _message_text.text if _message != null and _message.visible else "",
		"version_text": "".join(_version.get_children().map(func(glyph): return glyph.text)) if _version != null else "",
		"music_stream": _music.stream.resource_path if _music != null and _music.stream != null else "",
		"music_playing": _music.playing if _music != null else false,
		"music_volume_db": _music.volume_db if _music != null else 0.0,
	}

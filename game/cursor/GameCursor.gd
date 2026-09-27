extends Node
## Autoload: the original game cursor on every screen — title, battle, story, big map and town.
## Every original OBS defines the same cursor object (游標, defProcCursor, planeCursor): the ten
## CURSOR01..CURSOR10 shapes of a winged sceptre whose wings turn, obj_Shape_Delay 5. The
## original object stands on the mouse each tick (0x430410) and animates through 0x45e5a6: one
## shape every delay + 1 = 6 ticks, looping after the tenth. A shape draws at the object's
## position minus its SHP draw origin, so the origin — (8,3) on the wide frames, (6,3)／(4,3) on
## the narrow ones, the red orb on all — is the hotspot.
##
## As in the original, the game draws the shape into its own 640×480 picture: a Sprite2D on the
## topmost canvas layer of the root viewport (stretch mode viewport: a root-viewport point is
## the logical point), so the window scales the cursor with everything else and the orb pixel
## is the logical pixel the pointer is on — the one hit-tests read. The system pointer is hidden
## only while the drawn one shows: window focused and pointer on the picture; elsewhere
## (letterbox, outside the window, unfocused) the OS arrow is back. The drawn one first shows
## once the real pointer moves. Following processes always, so the pointer still moves under a
## debug freeze or the resume prompt; the wings animate only while the tree runs.
##
## OPT-CURSOR (docs/OPTIONS.md), read at start and when the 重製選項 page closes with a changed
## value: 系統硬體游標 draws nothing into the picture and hands the same shape and hotspot to the
## OS pointer (Input.set_custom_mouse_cursor, each wing frame as it turns) — native size, no
## frame of lag.
##
## 0x430410 draws no sceptre while [0x4c1b00] & 0x1800000 — 0x1000000 while the shared cast
## routine 0x442a90 plays a magic effect, 0x800000 while a combat close-up plays (AnimalDefense
## 0x4038dd sets it, 0x403089／0x406fc2 clear it) — nor while an item is held ([0x4c1ce4]: 0x430310
## draws the item's icon at the mouse instead). Here a node of HIDER_GROUP whose
## hides_game_cursor() is true stands for the first two, a visible held-item icon of HELD_GROUP
## for the third; the OS pointer of the 系統硬體游標 branch hides the same way. While hidden the
## wings stop; shown again, the shape restarts at CURSOR01 with a fresh delay (0x4304ee..0x430502).
## provenance:
##   rules: remake-invented docs/OPTIONS.md (OPT-CURSOR=系統硬體游標 only: the OS pointer shows the sceptre)
##   layout: resource-derived content/imported/hsl/shared/game_cursor/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/game_cursor/README.md
##     (hidden during magic effects, combat close-ups and while an item is held)
##   timing: resource-derived content/imported/hsl/shared/game_cursor/manifest.json
##   timing: static-derived docs/evidence_packets/runtime_observations/game_cursor/README.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/game_cursor/README.md
##     (CURSOR10 returns every 1.151 s in the 2026-09-24 recording = 60 ticks of 19.2 ms)

const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
## RemakeOptionsPage.LISTENERS (a literal: preloading the page would pull the UI skin into the autoload).
const OPTION_LISTENERS := "remake_options_listeners"
const MANIFEST_PATH := "res://content/imported/hsl/shared/game_cursor/manifest.json"
const MANIFEST_SCHEMA := "hsl_game_cursor.v1"
## planeCursor is the top plane: above every game layer and the embedded popup canvas (tooltips,
## Viewport SUBWINDOW_CANVAS_LAYER 1024).
const CANVAS_LAYER := 1025
## Nodes whose hides_game_cursor() hides the sceptre while true (the 0x1800000 bits).
const HIDER_GROUP := "game_cursor_hiders"
## Held-item icons drawn at the pointer ([0x4c1ce4]): while one shows, the sceptre does not.
const HELD_GROUP := "game_cursor_held_items"

## The shapes in source order and their hotspots (SHP draw origins).
var frames: Array[Texture2D] = []
var hotspots: Array[Vector2i] = []
var frame_ticks := 0
## The shape showing now and the ticks it has shown.
var frame_index := 0
var _ticks_in_frame := 0
var _clock := 0.0
## The drawn cursor and its layer.
var layer: CanvasLayer
var sprite: Sprite2D
## The real pointer's screen position last frame; the drawn cursor waits for it to move.
var _screen_pointer := Vector2i.ZERO
var _pointer_moved := false
## OPT-CURSOR as last read: false on the original path (the drawn sceptre).
var hardware := false
## True while a presentation or a held item hides the cursor (suppressed()).
var hidden := false


func _ready() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(typeof(manifest) == TYPE_DICTIONARY and str(manifest.get("schema", "")) == MANIFEST_SCHEMA,
		"GameCursor: %s missing or not %s" % [MANIFEST_PATH, MANIFEST_SCHEMA])
	frame_ticks = int(manifest["frame_ticks"])
	for frame in manifest["frames"]:
		frames.append(load(str(frame["texture"])))
		hotspots.append(Vector2i(int(frame["draw_origin"][0]), int(frame["draw_origin"][1])))
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.name = "GameCursorLayer"
	layer.layer = CANVAS_LAYER
	add_child(layer)
	sprite = Sprite2D.new()
	sprite.name = "GameCursorSprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = false
	layer.add_child(sprite)
	_screen_pointer = DisplayServer.mouse_get_position()
	apply_frame()
	add_to_group(OPTION_LISTENERS)
	_read_cursor_option()


func _process(delta: float) -> void:
	var was_hidden := hidden
	hidden = suppressed()
	if was_hidden and not hidden:
		frame_index = 0
		_ticks_in_frame = 0
		apply_frame()
	if not hardware:
		follow_pointer()
	else:
		var mode := Input.MOUSE_MODE_HIDDEN if hidden else Input.MOUSE_MODE_VISIBLE
		if Input.mouse_mode != mode:
			Input.mouse_mode = mode
	if get_tree().paused or hidden:
		return
	_clock += delta
	while _clock >= OriginalTick.TICK_SECONDS:
		_clock -= OriginalTick.TICK_SECONDS
		advance_tick()


## 0x430410: the object stands on the mouse. The real pointer each frame, once it has moved.
func follow_pointer() -> void:
	var screen := DisplayServer.mouse_get_position()
	if screen != _screen_pointer:
		_screen_pointer = screen
		_pointer_moved = true
	if not _pointer_moved:
		return
	var point := get_viewport().get_mouse_position()
	var on_picture := get_window().has_focus() and get_viewport().get_visible_rect().has_point(point)
	show_at(point, on_picture and not hidden)
	var mode := Input.MOUSE_MODE_HIDDEN if on_picture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


## 0x430410's hide tests: a presentation hider says so, or a held-item icon shows.
func suppressed() -> bool:
	for node in get_tree().get_nodes_in_group(HIDER_GROUP):
		if node.has_method("hides_game_cursor") and node.hides_game_cursor():
			return true
	for node in get_tree().get_nodes_in_group(HELD_GROUP):
		if node is CanvasItem and node.is_visible_in_tree():
			return true
	return false


## Draws the cursor with its hotspot on the logical pixel under `point` (or hides it).
func show_at(point: Vector2, shown := true) -> void:
	sprite.position = point.floor()
	sprite.visible = shown


## One original tick of 0x45e5a6: after frame_ticks ticks the next shape shows, the tenth loops.
func advance_tick() -> void:
	_ticks_in_frame += 1
	if _ticks_in_frame < frame_ticks:
		return
	_ticks_in_frame = 0
	frame_index = (frame_index + 1) % frames.size()
	apply_frame()


func apply_frame() -> void:
	if frames.is_empty():
		return
	sprite.texture = frames[frame_index]
	sprite.offset = -Vector2(hotspots[frame_index])
	if hardware:
		Input.set_custom_mouse_cursor(frames[frame_index], Input.CURSOR_ARROW, Vector2(hotspots[frame_index]))


## The 重製選項 page closed with a changed value (RemakeOptionsPage.LISTENERS).
func remake_options_changed() -> void:
	_read_cursor_option()


## OPT-CURSOR read point. 系統硬體游標: the drawn sceptre hides, the OS pointer shows and takes
## the current shape; back to the original: the OS arrow returns and the drawn one follows the
## pointer again at once.
func _read_cursor_option() -> void:
	var was_hardware := hardware
	hardware = not GameOptions.is_original("OPT-CURSOR")
	if hardware:
		sprite.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		apply_frame()
	elif was_hardware:
		Input.set_custom_mouse_cursor(null)
		_pointer_moved = true

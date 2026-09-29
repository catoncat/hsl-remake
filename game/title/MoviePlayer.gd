extends CanvasLayer
## Plays one film of the original movie.pak — the intro start.ani or the ending end.ani —
## from the import manifest (content/imported/hsl/movie/manifest.json, tools/hsltools/assets/movie_import.py):
## WebP sprite sheets of 320×240 frames in row-major order at the manifest frame rate, with
## the decoded .snd soundtrack. Frames are pixel-doubled onto the 640×480 screen (the
## original played the 320×240 FLI on its 640×480 mode; the doubling filter is a remake
## reading). Any key or click skips the film (remake reading — the original skip behaviour
## is not located). Emits finished("completed" | "skipped" | "missing_movie") once.
##
## Usage: MoviePlayer.new(), add the node, call play("start" | "end"), await finished. The
## node draws on its own canvas layer above the scene's UI and frees nothing itself; the
## caller removes it.
## provenance:
##   rules: static-derived docs/evidence_packets/resource_inventory/original_movies.md
##   rules: remake-invented (any-key skip; original skip behaviour not located)
##   layout: resource-derived content/imported/hsl/movie/manifest.json
##   layout: remake-invented (nearest-neighbour doubling to 640×480)
##   timing: static-derived docs/evidence_packets/resource_inventory/original_movies.md
##   timing: resource-derived content/imported/hsl/movie/manifest.json
##   audio: resource-derived content/imported/hsl/movie/manifest.json

signal finished(reason: String)

const GameSettings = preload("res://game/settings/GameSettings.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const MANIFEST_PATH := "res://content/imported/hsl/movie/manifest.json"
const MOVIE_DIR := "res://content/imported/hsl/movie/"
const SCREEN_SIZE := Vector2(640, 480)
const LAYER := 40

var movie_name := ""
var spec: Dictionary = {}
var playing := false
var finished_reason := ""
## Playback clock in seconds; tests may set it forward to reach a later frame.
var elapsed := 0.0
var frame_index := -1
var skippable := true

var _backdrop: ColorRect
var _sprite: Sprite2D
var _audio: AudioStreamPlayer
var _sheet_index := -1
var _prefetch_path := ""
var _first_tick := false


static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The manifest entry of one film ({} when the film is not imported).
static func movie_spec(name: String) -> Dictionary:
	var movies: Dictionary = load_manifest().get("movies", {})
	var entry: Variant = movies.get(name, {})
	return entry if typeof(entry) == TYPE_DICTIONARY else {}


func _ready() -> void:
	_ensure_nodes()
	set_process(playing)


func _exit_tree() -> void:
	# Freed mid-film (scene change): nothing may stay parked on the loader thread.
	_drop_prefetch()


func _ensure_nodes() -> void:
	if _sprite != null:
		return
	layer = LAYER
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color.BLACK
	_backdrop.size = SCREEN_SIZE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_sprite = Sprite2D.new()
	_sprite.name = "Frame"
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_audio = AudioStreamPlayer.new()
	_audio.name = "Soundtrack"
	_audio.bus = GameSettings.movie_bus() # 0x42df6f: film sound follows 音效音量
	add_child(_audio)


## Starts the named film from its first frame; returns the summary. A film missing from
## the manifest finishes at once with "missing_movie" (and an error) so callers continue.
func play(name: String) -> Dictionary:
	_ensure_nodes()
	movie_name = name
	spec = movie_spec(name)
	elapsed = 0.0
	frame_index = -1
	_sheet_index = -1
	_prefetch_path = ""
	finished_reason = ""
	if spec.is_empty() or (spec.get("sheets", []) as Array).is_empty():
		push_error("MoviePlayer: film '%s' is missing from %s" % [name, MANIFEST_PATH])
		_finish("missing_movie")
		return summary()
	_sprite.scale = SCREEN_SIZE / _frame_size()
	# The first sheet decodes synchronously (tens of MB); show frame 0, then start the
	# soundtrack and the clock together so the stall lands before both.
	_show_frame(0)
	var audio: Dictionary = spec.get("audio", {})
	var audio_path := MOVIE_DIR + str(audio.get("file", ""))
	if str(audio.get("file", "")) != "" and ResourceLoader.exists(audio_path):
		_audio.stream = load(audio_path)
		_audio.play()
	playing = true
	_first_tick = true
	set_process(true)
	return summary()


func frame_rate() -> float:
	return maxf(float(spec.get("frame_rate", 15)), 1.0)


func frame_count() -> int:
	return int(spec.get("frame_count", 0))


func _frame_size() -> Vector2:
	return Vector2(maxf(float(spec.get("frame_width", 320)), 1.0), maxf(float(spec.get("frame_height", 240)), 1.0))


func _process(delta: float) -> void:
	if not playing:
		return
	if _first_tick:
		# This delta still carries the frame that loaded the first sheet.
		_first_tick = false
		return
	elapsed += delta
	var target := floori(elapsed * frame_rate())
	if target >= frame_count():
		_finish("completed")
		return
	if target != frame_index:
		_show_frame(target)


func _show_frame(index: int) -> void:
	var sheets: Array = spec.get("sheets", [])
	var sheet_index := _sheet_for_frame(index, sheets)
	if sheet_index < 0:
		return
	if sheet_index != _sheet_index:
		_sheet_index = sheet_index
		_sprite.texture = _sheet_texture(str((sheets[sheet_index] as Dictionary).get("file", "")))
		# Fetch the next sheet on the loader thread so the boundary does not hitch.
		_prefetch_path = ""
		if sheet_index + 1 < sheets.size():
			_prefetch_path = MOVIE_DIR + str((sheets[sheet_index + 1] as Dictionary).get("file", ""))
			ResourceLoader.load_threaded_request(_prefetch_path)
	var sheet: Dictionary = sheets[sheet_index]
	var local := index - int(sheet.get("frame_start", 0))
	var columns := maxi(int(sheet.get("columns", 1)), 1)
	var size := _frame_size()
	_sprite.region_rect = Rect2(float(local % columns) * size.x, float(floori(local / float(columns))) * size.y, size.x, size.y)
	frame_index = index


func _sheet_for_frame(index: int, sheets: Array) -> int:
	for sheet_index in range(sheets.size()):
		var sheet: Dictionary = sheets[sheet_index]
		var start := int(sheet.get("frame_start", 0))
		if index >= start and index < start + int(sheet.get("frame_count", 0)):
			return sheet_index
	return -1


func _sheet_texture(file: String) -> Texture2D:
	var path := MOVIE_DIR + file
	if path == _prefetch_path:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path)
	return load(path)


## Ends the film early (any key / click while skippable).
func skip() -> Dictionary:
	if playing and skippable:
		_finish("skipped")
	return summary()


func handle_input(event: InputEvent) -> bool:
	if not playing or not skippable:
		return false
	if event is InputEventMouseButton and event.pressed:
		skip()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		skip()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# A skip that ends the movie can hand over to the next scene and take this node out of the tree.
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


func _finish(reason: String) -> void:
	playing = false
	finished_reason = reason
	set_process(false)
	if _audio != null and _audio.playing:
		_audio.stop()
	_drop_prefetch()
	finished.emit(reason)


## A sheet requested on the loader thread stays referenced until it is fetched; take it
## (blocking only when its load is still running) so an early end leaks nothing.
func _drop_prefetch() -> void:
	if _prefetch_path == "":
		return
	var status := ResourceLoader.load_threaded_get_status(_prefetch_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
		ResourceLoader.load_threaded_get(_prefetch_path)
	_prefetch_path = ""


func summary() -> Dictionary:
	var sheets: Array = spec.get("sheets", [])
	return {
		"schema": "hsl_movie_player.v1",
		"movie": movie_name,
		"playing": playing,
		"finished_reason": finished_reason,
		"elapsed": snappedf(elapsed, 0.001),
		"frame_index": frame_index,
		"frame_count": frame_count(),
		"frame_rate": frame_rate(),
		"sheet_index": _sheet_index,
		"sheet_file": str((sheets[_sheet_index] as Dictionary).get("file", "")) if _sheet_index >= 0 and _sheet_index < sheets.size() else "",
		"audio_playing": _audio != null and _audio.playing,
		"skippable": skippable,
	}

extends Node
## Web delivery (autoload PackManager): the web export's core pack carries the scripts, scenes,
## the title, shared art and rule tables; every level, film and music track and the battle-only
## presentation data are resource packs (tools/web_packs.py plan／build) fetched when a scene
## needs them, checked against the pack manifest (bytes, sha256), kept in user://packs/
## (IndexedDB in a browser) and mounted with ProjectSettings.load_resource_pack. A mounted pack
## stays mounted (Godot cannot unmount one); the packs already cached are mounted at start, so
## 戰場記錄 and the memoir list find the scenarios played before.
##
## Every scene change into a battle, story, town or big-map scenario, a film or the ending goes
## through after_scenario／after_groups, which mount the packs first: the scenes'
## ResourceLoader.exists guards would skip a missing file silently (no sound, no effect, no
## portrait). Off the web and without HSL_WEB_PACKS_DIR (a local directory of built packs
## standing in for the server) the manager is off and `then` runs in the same call, so desktop
## scene changes keep their order and timing. Once a scenario is entered, the packs of the
## scenarios it can hand off to (manifest `next`) are prefetched in the background, one at a
## time, and a load the player waits on cancels a prefetch it does not need.
## provenance:
##   rules: remake-invented (web delivery of the remake's own build; the original ships one install)
##   layout: remake-invented (loading overlay)
##   strings: remake-invented (loading overlay text)
##   timing: remake-invented (prefetch delay, retry backoff)

signal progress(done_bytes: int, total_bytes: int)
signal _manifest_settled
signal _download_settled
signal _retry_requested

const CACHE_DIR := "user://packs/"
const MANIFEST_FILE := "manifest.json"
const MANIFEST_SCHEMA := "hsl_web_packs_manifest.v1"
const RETRIES := 3
const PREFETCH_DELAY_SECONDS := 3.0
const OVERLAY_LAYER := 1010
## A browser reads one HTTPRequest chunk a frame: the 64 KiB default ran ≈3.7 MB/s, 4 MiB
## fetched 24.7 MB in 3.0 s (6.9 s before).
const DOWNLOAD_CHUNK_BYTES := 4194304
## A body-face size of OriginalBitmapFont (BODY_SIZES); other sizes draw code boxes.
const OVERLAY_FONT_SIZE := 24

var enabled := false
## HSL_WEB_PACKS_DIR: packs copied from this directory instead of downloaded.
var source_dir := ""
var base_url := ""
var manifest: Dictionary = {}
var mounted: Dictionary = {}
var last_error := ""
var _manifest_state := "none"
var _http: HTTPRequest
var _overlay: CanvasLayer
var _label: Label
var _foreground := 0
var _transition_busy := false
var _waiting_retry := false
var _done_bytes := 0
var _total_bytes := 0
var _downloading := ""
var _prefetching := ""
var _prefetch_queue: Array[String] = []


## The running manager, or null (a test or tool tree without the autoload).
static func instance() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("PackManager") if tree != null and tree.root != null else null


## Runs `then` once the scenario's packs are mounted (manifest scenarios → group; a core scenario
## needs none), then queues the prefetch of the scenarios it hands off to. Off: runs `then` now.
static func after_scenario(scenario_path: String, then: Callable) -> void:
	var packs := instance()
	if packs == null or not packs.enabled:
		then.call()
		return
	packs._run_after([], scenario_path, then)


## after_scenario for named groups (movie:start, scene:game_clear, ...).
static func after_groups(groups: Array, then: Callable) -> void:
	var packs := instance()
	if packs == null or not packs.enabled:
		then.call()
		return
	packs._run_after(groups, "", then)


## Background fetch of a scenario's packs into the cache (the first level while the intro film plays).
static func prefetch_scenario(scenario_path: String) -> void:
	var packs := instance()
	if packs != null and packs.enabled and scenario_path != "":
		packs._queue_prefetch([scenario_path], 0.0)


func _ready() -> void:
	source_dir = OS.get_environment("HSL_WEB_PACKS_DIR")
	enabled = OS.has_feature("web") or source_dir != ""
	if not enabled:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if source_dir == "":
		base_url = str(JavaScriptBridge.eval("new URL('packs/', window.location.href).href", true))
		if not base_url.begins_with("http"):
			_fail("no page address to fetch packs from (JavaScriptBridge.eval gave %s)" % base_url)
		# No download_file: it writes nothing in a browser, and DirAccess.rename fails on user://
		# there; the body is checked and stored under its final name (_store).
		_http = HTTPRequest.new()
		_http.name = "Download"
		_http.download_chunk_size = DOWNLOAD_CHUNK_BYTES
		# The browser has already undone any Content-Encoding (a CDN or tunnel gzips the manifest and other text);
		# with accept_gzip on, HTTPRequest inflates the plain body again and fails with RESULT_BODY_DECOMPRESS_FAILED.
		_http.accept_gzip = false
		_http.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_http)
	_build_overlay()
	_load_manifest()


## Mounts the group's packs, fetching what the cache lacks. Returns at once when all are mounted.
func ensure(group: String) -> bool:
	if not enabled:
		return true
	if _manifest_state != "ready":
		var loaded: bool = await _load_manifest()
		if not loaded:
			return false
	var ids := _group_packs(group)
	if group != "" and not (manifest.get("groups", {}) as Dictionary).has(group):
		_fail("unknown pack group %s" % group)
		return false
	var missing := ids.filter(func(id: String) -> bool: return not mounted.has(id))
	if missing.is_empty():
		return true
	_foreground += 1
	_done_bytes = 0
	_total_bytes = 0
	for id in missing:
		_total_bytes += 0 if _cached(id) else int(manifest["packs"][id]["bytes"])
	var ok := true
	for id in missing:
		if _prefetching != "" and not missing.has(_prefetching):
			_cancel_prefetch()
		while _downloading != "" or _prefetching != "":
			await _download_settled
		ok = await _obtain(id)
		if not ok:
			break
	_foreground -= 1
	if _foreground == 0:
		if not _waiting_retry:
			_overlay.visible = false
		_prefetch_next.call_deferred()
	return ok


func _run_after(groups: Array, scenario_path: String, then: Callable) -> void:
	if _transition_busy:
		push_warning("PackManager: a scene change is already waiting for its packs; this one is dropped")
		return
	_transition_busy = true
	while true:
		var ok := true
		if _manifest_state != "ready":
			ok = await _load_manifest()
		var wanted := groups.duplicate()
		var group := str((manifest.get("scenarios", {}) as Dictionary).get(scenario_path, ""))
		if group != "":
			wanted.append(group)
		for name in wanted:
			if not ok:
				break
			ok = await ensure(str(name))
		if ok:
			break
		_show("Load failed: %s\nClick or press a key to retry." % last_error)
		_waiting_retry = true
		await _retry_requested
	_transition_busy = false
	_overlay.visible = false
	if then.is_valid():
		then.call()
	if scenario_path != "":
		_queue_prefetch((manifest.get("next", {}) as Dictionary).get(scenario_path, []), PREFETCH_DELAY_SECONDS)


func _load_manifest() -> bool:
	if _manifest_state == "ready":
		return true
	if _manifest_state == "loading":
		await _manifest_settled
		return _manifest_state == "ready"
	_manifest_state = "loading"
	var text := ""
	if source_dir != "":
		text = FileAccess.get_file_as_string(source_dir.path_join(MANIFEST_FILE))
		if text == "":
			last_error = "%s unreadable (%s)" % [source_dir.path_join(MANIFEST_FILE), error_string(FileAccess.get_open_error())]
	else:
		# The manifest names the current packs; never take it from the browser cache.
		var body: PackedByteArray = await _download(MANIFEST_FILE + "?t=%d" % int(Time.get_unix_time_from_system()), "")
		text = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary and str(parsed.get("schema", "")) == MANIFEST_SCHEMA:
		manifest = parsed
		_manifest_state = "ready"
		_clean_cache()
		for id in manifest.get("packs", {}):
			if _cached(id):
				_mount(id)
	else:
		_manifest_state = "none"
		_fail("pack manifest unavailable: %s" % (last_error if text == "" else "wrong schema"))
	_manifest_settled.emit()
	return _manifest_state == "ready"


func _group_packs(group: String) -> Array:
	var ids: Variant = (manifest.get("groups", {}) as Dictionary).get(group, [])
	return (ids as Array).duplicate() if ids is Array else []


func _cache_path(id: String) -> String:
	return CACHE_DIR + str(manifest["packs"][id]["file"])


func _cached(id: String) -> bool:
	var path := _cache_path(id)
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	return file != null and file.get_length() == int(manifest["packs"][id]["bytes"])


## Cache hit or fetch (RETRIES tries), then mount; errors are reported, never swallowed.
func _obtain(id: String) -> bool:
	for attempt in RETRIES:
		if _cached(id):
			return _mount(id)
		var body: PackedByteArray = await _fetch(id)
		if _store(id, body):
			_done_bytes += body.size()
			return _mount(id)
		push_error("PackManager: %s (try %d of %d)" % [last_error, attempt + 1, RETRIES])
		if attempt + 1 < RETRIES:
			await get_tree().create_timer(1.0 + attempt, false).timeout
	return false


func _fetch(id: String) -> PackedByteArray:
	var file := str(manifest["packs"][id]["file"])
	if source_dir == "":
		return await _download(file, id)
	var body := FileAccess.get_file_as_bytes(source_dir.path_join(file))
	if body.is_empty():
		last_error = "%s unreadable (%s)" % [source_dir.path_join(file), error_string(FileAccess.get_open_error())]
	return body


## One request at a time through the single HTTPRequest node.
func _download(file: String, id: String) -> PackedByteArray:
	_downloading = id if id != "" else file
	var err := _http.request(base_url + file)
	var result: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if err == OK:
		result = await _http.request_completed
	_downloading = ""
	_download_settled.emit()
	if err != OK or int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		last_error = "%s: request error %d, result %d, HTTP %d" % [file, err, int(result[0]), int(result[1])]
		return PackedByteArray()
	return result[3]


## Verifies the bytes against the manifest and writes them to the cache.
func _store(id: String, body: PackedByteArray) -> bool:
	var row: Dictionary = manifest["packs"][id]
	if body.is_empty():
		return false
	if body.size() != int(row["bytes"]):
		last_error = "%s: %d bytes, manifest says %d" % [row["file"], body.size(), int(row["bytes"])]
		return false
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(body)
	if hashing.finish().hex_encode() != str(row["sha256"]):
		last_error = "%s: sha256 mismatch" % row["file"]
		return false
	var file := FileAccess.open(_cache_path(id), FileAccess.WRITE)
	if file == null:
		last_error = "%s: cache write failed (%s)" % [row["file"], error_string(FileAccess.get_open_error())]
		return false
	file.store_buffer(body)
	file.close()
	return true


func _mount(id: String) -> bool:
	if mounted.has(id):
		return true
	if not ProjectSettings.load_resource_pack(_cache_path(id), false):
		last_error = "%s: load_resource_pack failed" % manifest["packs"][id]["file"]
		push_error("PackManager: " + last_error)
		DirAccess.remove_absolute(_cache_path(id))
		return false
	mounted[id] = true
	return true


## Drops cached packs the manifest no longer names (an older build's).
func _clean_cache() -> void:
	var keep := {}
	for id in manifest.get("packs", {}):
		keep[str(manifest["packs"][id]["file"])] = true
	for name in DirAccess.get_files_at(CACHE_DIR):
		if not keep.has(name):
			DirAccess.remove_absolute(CACHE_DIR + name)


func _queue_prefetch(scenarios: Array, delay: float) -> void:
	for scenario in scenarios:
		var group := str((manifest.get("scenarios", {}) as Dictionary).get(str(scenario), ""))
		for id in _group_packs(group):
			if not mounted.has(id) and not _prefetch_queue.has(id) and id != _prefetching:
				_prefetch_queue.append(id)
	if _prefetch_queue.is_empty():
		return
	if delay > 0.0:
		get_tree().create_timer(delay, false).timeout.connect(_prefetch_next)
	else:
		_prefetch_next.call_deferred()


func _prefetch_next() -> void:
	while _prefetching == "" and _foreground == 0 and _downloading == "" and not _prefetch_queue.is_empty():
		var id: String = _prefetch_queue.pop_front()
		if mounted.has(id) or _cached(id):
			continue
		_prefetching = id
		var body: PackedByteArray = await _fetch(id)
		if _prefetching == id and not _store(id, body):
			push_warning("PackManager: prefetch of %s failed: %s" % [id, last_error])
		_prefetching = ""
		_download_settled.emit()


func _cancel_prefetch() -> void:
	var id := _prefetching
	_prefetching = ""
	_prefetch_queue.push_front(id)
	if _http != null and _downloading == id:
		_http.cancel_request()
		_http.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


func _fail(message: String) -> void:
	last_error = message
	push_error("PackManager: " + message)


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "PackOverlay"
	_overlay.layer = OVERLAY_LAYER
	_overlay.visible = false
	add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_overlay_input)
	_overlay.add_child(shade)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", OVERLAY_FONT_SIZE)
	shade.add_child(_label)


func _show(text: String) -> void:
	_label.text = text
	_overlay.visible = true


func _process(_delta: float) -> void:
	if _foreground == 0 or _waiting_retry:
		return
	var done := _done_bytes + (_http.get_downloaded_bytes() if _http != null and _downloading != "" and _prefetching == "" else 0)
	progress.emit(done, _total_bytes)
	if _total_bytes > 0:
		_show("Loading %.1f / %.1f MB" % [done / 1e6, _total_bytes / 1e6])


func _on_overlay_input(event: InputEvent) -> void:
	if _waiting_retry and event is InputEventMouseButton and event.pressed:
		_retry()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting_retry and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_retry()


func _retry() -> void:
	_waiting_retry = false
	_overlay.visible = false
	_retry_requested.emit()

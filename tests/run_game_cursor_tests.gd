extends "res://tests/support/TestSuite.gd"

## The original game cursor (game_cursor/README.md): every original OBS defines object 2 游標 the
## same way — CURSOR01..CURSOR10, obj_Shape_Delay 5, defProcCursor, planeCursor (resource-derived,
## `hsl check game_cursor`). 0x430410 puts the object on the mouse and 0x45e5a6 shows the next
## shape every delay + 1 = 6 ticks, looping after ten (static-derived); the recording's CURSOR10
## returns every 1.151 s = 60 ticks of 19.2 ms (runtime-measured). A shape draws at the position
## minus its SHP draw origin, so the origin is the hotspot — the red orb on every frame; the
## game draws it into its own 640×480 picture on planeCursor, the top plane.
## Checks the GameCursor autoload against that, and that no other game code sets a cursor.

const MANIFEST_PATH := "res://content/imported/hsl/shared/game_cursor/manifest.json"
const AUTOLOAD_PATH := "res://game/cursor/GameCursor.gd"


func _init() -> void:
	tag = "GAME_CURSOR_TESTS"


func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_test_manifest(manifest)
	var cursor: Node = root.get_node_or_null("GameCursor")
	check(cursor != null, "the GameCursor autoload is installed for every scene")
	check(str(ProjectSettings.get_setting("autoload/GameCursor", "")) == "*" + AUTOLOAD_PATH, "project.godot registers GameCursor as an autoload")
	if cursor == null:
		return
	_test_frames_and_hotspots(cursor, manifest)
	_test_animation(cursor)
	_test_no_other_cursor_source()


func _test_manifest(manifest: Dictionary) -> void:
	var fields: Dictionary = manifest.get("source_fields", {})
	_assert_eq(str(fields.get("obj_Process_Code", "")), "defProcCursor", "the cursor object runs defProcCursor")
	_assert_eq(str(fields.get("obj_Plane", "")), "planeCursor", "it draws on planeCursor, above every menu plane")
	_assert_eq(int(fields.get("obj_Shape_Number", 0)), 10, "ten shapes CURSOR01..CURSOR10")
	_assert_eq(int(manifest.get("frame_ticks", 0)), int(fields.get("obj_Shape_Delay", 0)) + 1, "a shape shows obj_Shape_Delay + 1 ticks (0x45e5a6)")
	_assert_eq(int(manifest.get("frame_ticks", 0)), 6, "six ticks a shape, a 60-tick loop")
	check(int(manifest.get("obs_definitions", 0)) >= 100 and (manifest.get("obs_disagreements", [0]) as Array).is_empty(), "every OBS that defines the cursor defines the same one (%d)" % int(manifest.get("obs_definitions", 0)))


func _test_frames_and_hotspots(cursor: Node, manifest: Dictionary) -> void:
	var frames: Array = manifest.get("frames", [])
	_assert_eq(cursor.frames.size(), frames.size(), "the autoload loads every shape")
	_assert_eq(cursor.frame_ticks, 6, "the autoload animates at six ticks a shape")
	var on_orb := 0
	for index in range(mini(frames.size(), cursor.frames.size())):
		var origin := Vector2i(int(frames[index]["draw_origin"][0]), int(frames[index]["draw_origin"][1]))
		_assert_eq(cursor.hotspots[index], origin, "shape %d's hotspot is its SHP draw origin" % (index + 1))
		var image: Image = cursor.frames[index].get_image()
		_assert_eq(Vector2i(image.get_width(), image.get_height()), Vector2i(int(frames[index]["size"][0]), int(frames[index]["size"][1])), "shape %d keeps its source size" % (index + 1))
		var pixel := image.get_pixelv(origin)
		if pixel.a > 0.9 and pixel.r > 0.7 and pixel.g < 0.2 and pixel.b < 0.2:
			on_orb += 1
	_assert_eq(on_orb, frames.size(), "the hotspot is the red orb on every shape")
	_assert_eq(cursor.hotspots[0], Vector2i(8, 3), "the wide first shape points with (8,3)")


func _test_animation(cursor: Node) -> void:
	cursor.frame_index = 0
	cursor._ticks_in_frame = 0
	cursor.apply_frame()
	var changes: Array[int] = []
	for tick in range(1, 61):
		var before: int = cursor.frame_index
		cursor.advance_tick()
		if cursor.frame_index != before:
			changes.append(tick)
	_assert_eq(changes, [6, 12, 18, 24, 30, 36, 42, 48, 54, 60], "the next shape every six ticks")
	_assert_eq(cursor.frame_index, 0, "after the tenth shape the loop starts again (60 ticks)")
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	var sprite: Sprite2D = cursor.sprite
	_assert_eq(sprite.texture, cursor.frames[1], "each new shape is drawn")
	check(sprite.get_viewport() == root and cursor.layer.layer > 1024 and sprite.global_scale == Vector2.ONE, "the cursor draws at source size in the 640×480 picture above every layer and popup (%d), so the window scales it with the game" % cursor.layer.layer)
	cursor.show_at(Vector2(100.7, 50.2))
	_assert_eq(Vector2i(sprite.position + sprite.offset) + cursor.hotspots[1], Vector2i(100, 50), "the hotspot lands on the logical pixel under the pointer")
	sprite.hide()
	cursor.frame_index = 0
	cursor._ticks_in_frame = 0
	cursor.apply_frame()


## One cursor for every screen: only GameCursor sets the mouse cursor image or shape or hides
## the system pointer.
func _test_no_other_cursor_source() -> void:
	var offenders: Array[String] = []
	var pattern := RegEx.create_from_string("set_custom_mouse_cursor|mouse_default_cursor_shape|cursor_set_shape|cursor_set_custom_image|Input\\.set_default_cursor_shape|mouse_mode")
	for path in _files("res://game", [".gd", ".tscn"]):
		if path == AUTOLOAD_PATH:
			continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)
	_assert_eq(offenders, [], "no other game file sets a mouse cursor")


func _files(directory: String, suffixes: Array) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for name in dir.get_files():
		for suffix in suffixes:
			if name.ends_with(suffix):
				found.append(directory.path_join(name))
	for name in dir.get_directories():
		found.append_array(_files(directory.path_join(name), suffixes))
	return found

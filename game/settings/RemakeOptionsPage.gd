extends Control
## 重製選項: the second page behind the original 設定選項 panel (docs/OPTIONS.md §9 B1). Three
## preset buttons (原版／舒適 apply at once; 自定 is not pressed — changing any row turns it on)
## and one row per listed option card: name, layer tag, a segmented value selector and the one
## sentence of the value shown (the original value says what the original does, an improved
## value what the remake adds). Only the experience tier is listed: the development tier never
## is, and no rules-layer card exists yet (one would wait for the campaign lock of OPTIONS B2).
##
## Everything the page shows — texts, row sizes, groups and the preset buttons — is the
## `page` block of content/authored/options/remake_options.json, so the layout can be tuned
## there; this script only flows it top to bottom. The window is the original Title031 (回憶錄)
## window cut into corners, edges and stone and rebuilt at the page size; the rows sit on its
## dark slot band. Presentation only: every change goes through GameOptions into GameSettings.
## Keys and mouse as in the system scroll: Up／Down pick a row, Left／Right or a click set a
## value, Enter steps it, Esc／Tab／right click (or the crumb) go back to 設定選項 — or, when Tab
## raised the page over the game (RemakeOptionsHotkey), close it. A close after a change calls
## `remake_options_changed` on the LISTENERS group, so a screen that read an option once when it
## was built (BattleSceneRuntime's OPT-TREASURE) takes the new value at once.
## provenance:
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##     (Title031 frame, stone and slot band rebuilt at page size)
##   layout: remake-invented content/authored/options/remake_options.json (page layout)
##   strings: remake-invented content/authored/options/remake_options.json
##     (option names, value labels, descriptions, preset buttons)

signal back_requested

## Every page instance (RemakeOptionsHotkey leaves Tab to a page already showing).
const GROUP := "remake_options_page"
## Nodes told `remake_options_changed()` when the page closes with a changed value.
const LISTENERS := "remake_options_listeners"
const GameOptions = preload("res://game/settings/GameOptions.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const TITLE_MANIFEST := "res://content/imported/hsl/global/title/manifest.json"
## Title031 (466×392) pieces: the ornamented corners, the rim between them (the top rim in two
## title-free spans), the stone of the bottom rim that fills the inside, and one slot band.
const FRAME_SHAPE := "memoir_list"
const SLICE_TOP_LEFT := Rect2i(0, 0, 104, 78)
const SLICE_TOP_RIGHT := Rect2i(362, 0, 104, 78)
const SLICE_TOP_EDGES := [Rect2i(104, 0, 84, 78), Rect2i(278, 0, 84, 78)]
const SLICE_LEFT_EDGE := Rect2i(0, 78, 35, 252)
const SLICE_RIGHT_EDGE := Rect2i(432, 78, 34, 252)
const SLICE_BOTTOM_LEFT := [Rect2i(0, 330, 35, 62), Rect2i(35, 344, 69, 48)]
const SLICE_BOTTOM_RIGHT := [Rect2i(432, 330, 34, 62), Rect2i(362, 344, 70, 48)]
const SLICE_BOTTOM_EDGE := Rect2i(104, 344, 258, 48)
const SLICE_STONE := Rect2i(104, 345, 258, 33)
const SLICE_BAND := Rect2i(36, 80, 395, 30)
## Horizontal shift between stone rows so the patch does not line up (brickwork).
const STONE_ROW_SHIFT := 97
const BAND_MARGIN := 4
const GOLD := Color(0.91, 0.77, 0.42)
const INK := Color(0.95, 0.91, 0.82)
const MUTED := Color(0.72, 0.66, 0.54)
const ORIGINAL_TEXT := Color(0.62, 0.92, 0.62)
const DARK_INK := Color(0.13, 0.10, 0.06)
const LOCKED := Color(0.5, 0.47, 0.42)
const SEGMENT_FILL := Color(0.10, 0.09, 0.08, 0.9)
const SEGMENT_BORDER := Color(0.54, 0.45, 0.27)
const CURSOR_COLOR := Color(0.95, 0.8, 0.35, 0.16)

static var _manifest: Dictionary = {}
var layout: Dictionary = {}
## Focusable rows in order: the preset row first, then one per listed option.
## {kind: preset|option, id, rect, segments: [{rect, value, panel, label}], text: Label}
var rows: Array = []
var focus := 0
var _built := false
var _window_rect := Rect2()
var _crumb_rect := Rect2()
var _preset_hint: Label
var _backs: Control
var _cursor: ColorRect
var _fronts: Control
## GameOptions values when the page opened; a close compares against them.
var _opened_values: Dictionary = {}


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)


func open() -> void:
	if not _built:
		_build()
	focus = clampi(focus, 0, maxi(rows.size() - 1, 0))
	refresh()
	_opened_values = GameOptions.summary()["values"]
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	if is_inside_tree() and GameOptions.summary()["values"] != _opened_values:
		get_tree().call_group(LISTENERS, "remake_options_changed")


## Keys and mouse while the page is up (the system scroll routes them here).
func handle_input(event: InputEvent, logical: Vector2) -> void:
	if event is InputEventMouseMotion:
		var hovered := row_at(logical)
		if hovered >= 0:
			set_focus(hovered)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			back_requested.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			click(logical)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_TAB:
				back_requested.emit()
			KEY_UP, KEY_W:
				set_focus(wrapi(focus - 1, 0, rows.size()))
			KEY_DOWN, KEY_S:
				set_focus(wrapi(focus + 1, 0, rows.size()))
			KEY_LEFT, KEY_A:
				step_focused(-1)
			KEY_RIGHT, KEY_D:
				step_focused(1)
			KEY_ENTER, KEY_SPACE, KEY_Z:
				step_focused(0)


## Row under a logical point, or -1.
func row_at(logical: Vector2) -> int:
	for index in range(rows.size()):
		if (rows[index]["rect"] as Rect2).has_point(logical):
			return index
	return -1


func set_focus(index: int) -> void:
	if rows.is_empty():
		return
	focus = clampi(index, 0, rows.size() - 1)
	var rect: Rect2 = rows[focus]["rect"]
	_cursor.position = rect.position
	_cursor.size = rect.size


## A click: a preset button or a value segment takes effect, the crumb goes back.
func click(logical: Vector2) -> void:
	if _crumb_rect.has_point(logical):
		back_requested.emit()
		return
	var index := row_at(logical)
	if index < 0:
		return
	set_focus(index)
	for segment in rows[index]["segments"]:
		if (segment["rect"] as Rect2).has_point(logical):
			_take(rows[index], str(segment["value"]))
			return


## Left／Right (-1／+1) move the focused row's value, Enter (0) steps it round.
func step_focused(direction: int) -> void:
	if rows.is_empty():
		return
	var row: Dictionary = rows[focus]
	if row["kind"] == "preset":
		var current := GameOptions.preset()
		var target := GameOptions.PRESET_ORIGINAL if direction < 0 else GameOptions.PRESET_COMFORT
		if direction == 0:
			target = GameOptions.PRESET_ORIGINAL if current == GameOptions.PRESET_COMFORT else GameOptions.PRESET_COMFORT
		_take(row, target)
		return
	var ids := GameOptions.value_ids(GameOptions.option(str(row["id"])))
	var at := ids.find(GameOptions.value(str(row["id"])))
	var next := wrapi(at + 1, 0, ids.size()) if direction == 0 else clampi(at + direction, 0, ids.size() - 1)
	_take(row, str(ids[next]))


func _take(row: Dictionary, value_id: String) -> void:
	if row["kind"] == "preset":
		if value_id != GameOptions.PRESET_CUSTOM:
			GameOptions.apply_preset(value_id)
	elif value_id != GameOptions.value(str(row["id"])):
		GameOptions.choose(str(row["id"]), value_id)
	refresh()


## Paints every selector, description and the preset hint from the current values.
func refresh() -> void:
	if not _built:
		return
	var preset := GameOptions.preset()
	var author := GameOptions.campaign_has_defaults()
	for row in rows:
		if row["kind"] == "preset":
			for segment in row["segments"]:
				var button: Dictionary = segment["entry"]
				var shown: Dictionary = button.get("author", button) if author else button
				(segment["label"] as Label).text = str(shown.get("label", button.get("label", "")))
				var on := str(segment["value"]) == preset
				_paint_segment(segment, on, str(segment["value"]) == GameOptions.PRESET_CUSTOM and not on)
				if on:
					_preset_hint.text = str(shown.get("text", button.get("text", "")))
			continue
		var card := GameOptions.option(str(row["id"]))
		var value := GameOptions.value(str(row["id"]))
		for segment in row["segments"]:
			_paint_segment(segment, str(segment["value"]) == value, false)
		var text: Label = row["text"]
		text.text = str(GameOptions.value_entry(card, value).get("text", ""))
		text.add_theme_color_override("font_color", ORIGINAL_TEXT if value == str(card["original_value"]) else INK)
	set_focus(focus)


func summary() -> Dictionary:
	var texts := {}
	for row in rows:
		if row["kind"] == "option":
			texts[str(row["id"])] = (row["text"] as Label).text
	return {
		"schema": "hsl_remake_options_page.v1",
		"visible": visible,
		"focus": focus,
		"focus_id": str(rows[focus]["id"]) if focus < rows.size() else "",
		"preset": GameOptions.preset(),
		"preset_hint": _preset_hint.text if _preset_hint != null else "",
		"rows": rows.map(func(row: Dictionary) -> String: return str(row["id"])),
		"texts": texts,
		"options": GameOptions.summary(),
	}


func _build() -> void:
	_built = true
	layout = GameOptions.page_layout()
	var window: Dictionary = layout.get("window", {})
	var rect: Array = window.get("rect", [0, 0, 640, 480])
	_window_rect = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	var frame := TextureRect.new()
	frame.name = "Window"
	frame.texture = frame_texture(Vector2i(_window_rect.size))
	frame.position = _window_rect.position
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_backs = _layer("Backs")
	_cursor = ColorRect.new()
	_cursor.name = "Cursor"
	_cursor.color = CURSOR_COLOR
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)
	_fronts = _layer("Fronts")
	var margin := float(window.get("margin", 22))
	var left := _window_rect.position.x + margin
	var right := _window_rect.end.x - margin
	var top := _window_rect.position.y
	var heading: Dictionary = layout.get("heading", {})
	var title := _text(str(heading.get("title", "")), Vector2(_window_rect.position.x, top + float(heading.get("y", 12))), int(heading.get("font", 20)), GOLD)
	title.size.x = _window_rect.size.x
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var crumb_data: Dictionary = layout.get("crumb", {})
	var crumb := _text(str(crumb_data.get("text", "")), Vector2.ZERO, int(crumb_data.get("font", 12)), MUTED)
	var crumb_width := _width(crumb.text, int(crumb_data.get("font", 12)))
	crumb.position = Vector2(_window_rect.end.x - float(crumb_data.get("right_inset", 108)) - crumb_width, top + float(crumb_data.get("y", 20)))
	_crumb_rect = Rect2(crumb.position - Vector2(4, 2), Vector2(crumb_width + 8, 20))
	var hotkey: Dictionary = layout.get("hotkey", {})
	_text(str(hotkey.get("text", "")), Vector2(_window_rect.position.x + float(hotkey.get("left_inset", 108)), top + float(hotkey.get("y", 20))), int(hotkey.get("font", 12)), MUTED)
	_build_presets(left, right, top)
	var y := top + float(layout.get("first_group_y", 68))
	var row_style: Dictionary = layout.get("rows", {})
	for group in layout.get("groups", []):
		var group_title := _text(str(group.get("title", "")), Vector2(left, y), 15, GOLD)
		_text(str(group.get("text", "")), Vector2(left + _width(group_title.text, 15) + 10, y + 3), 12, MUTED)
		y += float(layout.get("group_height", 20))
		for card in GameOptions.listed_options():
			if str(card["tier"]) == str(group.get("id", "")):
				_build_option_row(card, left, right, y, row_style)
				y += float(row_style.get("pitch", 41))


func _build_presets(left: float, right: float, top: float) -> void:
	var data: Dictionary = layout.get("presets", {})
	var y := top + float(data.get("y", 40))
	var font := int(data.get("font", 15))
	var button_size: Array = data.get("button_size", [66, 24])
	var dimensions := Vector2(float(button_size[0]), float(button_size[1]))
	_text(str(data.get("label", "")), Vector2(_window_rect.position.x + float(data.get("label_x", 40)), y + 2), font, MUTED)
	var x := _window_rect.position.x + float(data.get("button_x", 84))
	var row := {"kind": "preset", "id": "preset", "segments": []}
	for button in data.get("buttons", []):
		var segment := _segment(Rect2(Vector2(x, y), dimensions), str(button.get("label", "")), font)
		segment["value"] = str(button.get("id", ""))
		segment["entry"] = button
		row["segments"].append(segment)
		x += dimensions.x + float(data.get("gap", 8))
	_preset_hint = _text("", Vector2(x + 4, y + 3), 13, MUTED)
	row["rect"] = Rect2(left - 6, y - 3, right - left + 12, dimensions.y + 6)
	rows.append(row)


func _build_option_row(card: Dictionary, left: float, right: float, y: float, style: Dictionary) -> void:
	var rect := Rect2(left - 6, y, right - left + 12, float(style.get("height", 39)))
	band(_backs, rect)
	var name_font := int(style.get("name_font", 16))
	var name_y := y + float(style.get("name_y", 1))
	var name_label := _text(str(card.get("name", "")), Vector2(left, name_y), name_font, INK)
	var tag_text := _tag_label(str(card.get("layer", "")))
	if bool(card.get("info", false)):
		tag_text += "·" + _tag_label("info")
	_tag(tag_text, Vector2(left + _width(name_label.text, name_font) + 8, name_y + 3), int(style.get("tag_font", 11)), MUTED)
	var labels: Array = (card["values"] as Array).map(func(entry: Dictionary) -> String: return str(entry.get("label", "")))
	var segments := _segment_strip(labels, right, y + float(style.get("segment_y", 3)), style)
	for index in range(segments.size()):
		segments[index]["value"] = str(card["values"][index]["id"])
	var text := _text("", Vector2(left, y + float(style.get("text_y", 21))), int(style.get("text_font", 13)), INK)
	text.size.x = right - left
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.append({"kind": "option", "id": str(card["id"]), "rect": rect, "segments": segments, "text": text})


func _segment_strip(labels: Array, right: float, y: float, style: Dictionary) -> Array:
	var font := int(style.get("segment_font", 14))
	var padding := float(style.get("segment_padding", 9))
	var height := float(style.get("segment_height", 20))
	var widths: Array = labels.map(func(label: String) -> float: return _width(label, font) + padding * 2.0)
	var x: float = right - float(widths.reduce(func(total: float, width: float) -> float: return total + width, 0.0))
	var segments: Array = []
	for index in range(labels.size()):
		segments.append(_segment(Rect2(x, y, float(widths[index]), height), str(labels[index]), font))
		x += float(widths[index])
	return segments


func _segment(rect: Rect2, text: String, font: int) -> Dictionary:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fronts.add_child(panel)
	var label := _text(text, rect.position, font, INK)
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var segment := {"rect": rect, "panel": panel, "label": label, "value": ""}
	_paint_segment(segment, false, false)
	return segment


func _paint_segment(segment: Dictionary, on: bool, locked: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = GOLD if on else SEGMENT_FILL
	style.border_color = GOLD if on else SEGMENT_BORDER
	style.set_border_width_all(1)
	(segment["panel"] as Panel).add_theme_stylebox_override("panel", style)
	var label: Label = segment["label"]
	label.add_theme_color_override("font_color", DARK_INK if on else (LOCKED if locked else INK))
	label.add_theme_constant_override("shadow_offset_x", 0 if on else 1)
	label.add_theme_constant_override("shadow_offset_y", 0 if on else 1)


func _tag(text: String, at: Vector2, font: int, color: Color) -> void:
	var width := _width(text, font) + 10.0
	var pill := Panel.new()
	pill.position = at
	pill.size = Vector2(width, 15)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	pill.add_theme_stylebox_override("panel", style)
	_fronts.add_child(pill)
	var label := _text(text, at, font, color)
	label.size = pill.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _tag_label(id: String) -> String:
	for tag in layout.get("tags", []):
		if str(tag.get("id", "")) == id:
			return str(tag.get("label", id))
	return id


func _text(text: String, at: Vector2, font: int, color: Color) -> Label:
	var label := BattleUISkin.label(_fronts, at, font)
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _width(text: String, font: int) -> float:
	return get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font).x


func _layer(layer_name: String) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.size = size
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


## Title031's dark slot band stretched over `rect` (the page rows, the 重製選項 entry).
static func band(parent: Node, rect: Rect2) -> NinePatchRect:
	var patch := NinePatchRect.new()
	patch.texture = load(_shape_path(FRAME_SHAPE))
	patch.region_rect = Rect2(SLICE_BAND)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		patch.set_patch_margin(side, BAND_MARGIN)
	patch.position = rect.position
	patch.size = rect.size
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(patch)
	return patch


## Title031 rebuilt at `dimensions`: inside stone first (shifted row by row), the rim tiled
## along each side, the four ornamented corners last. The page builds it once, on first open.
static func frame_texture(dimensions: Vector2i) -> Texture2D:
	var source: Image = (load(_shape_path(FRAME_SHAPE)) as Texture2D).get_image()
	if source.is_compressed():
		source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var w := dimensions.x
	var h := dimensions.y
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var inside := Rect2i(35, 78, w - 69, h - 126)
	var row := 0
	for y in range(inside.position.y, inside.end.y, SLICE_STONE.size.y):
		var shift := (row * STONE_ROW_SHIFT) % SLICE_STONE.size.x
		for x in range(inside.position.x - shift, inside.end.x, SLICE_STONE.size.x):
			_blit(image, source, SLICE_STONE, Vector2i(x, y), inside)
		row += 1
	var top_rim := Rect2i(104, 0, w - 208, 78)
	var span := 0
	for x in range(104, w - 104, SLICE_TOP_EDGES[0].size.x):
		_blit(image, source, SLICE_TOP_EDGES[span % 2], Vector2i(x, 0), top_rim)
		span += 1
	var bottom_rim := Rect2i(104, h - 48, w - 208, 48)
	for x in range(104, w - 104, SLICE_BOTTOM_EDGE.size.x):
		_blit(image, source, SLICE_BOTTOM_EDGE, Vector2i(x, h - 48), bottom_rim)
	var left_rim := Rect2i(0, 78, 35, h - 140)
	var right_rim := Rect2i(w - 34, 78, 34, h - 140)
	for y in range(78, h - 62, SLICE_LEFT_EDGE.size.y):
		_blit(image, source, SLICE_LEFT_EDGE, Vector2i(0, y), left_rim)
		_blit(image, source, SLICE_RIGHT_EDGE, Vector2i(w - 34, y), right_rim)
	var whole := Rect2i(0, 0, w, h)
	_blit(image, source, SLICE_TOP_LEFT, Vector2i(0, 0), whole)
	_blit(image, source, SLICE_TOP_RIGHT, Vector2i(w - 104, 0), whole)
	_blit(image, source, SLICE_BOTTOM_LEFT[0], Vector2i(0, h - 62), whole)
	_blit(image, source, SLICE_BOTTOM_LEFT[1], Vector2i(35, h - 48), whole)
	_blit(image, source, SLICE_BOTTOM_RIGHT[0], Vector2i(w - 34, h - 62), whole)
	_blit(image, source, SLICE_BOTTOM_RIGHT[1], Vector2i(w - 104, h - 48), whole)
	return ImageTexture.create_from_image(image)


static func _blit(image: Image, source: Image, from: Rect2i, at: Vector2i, clip: Rect2i) -> void:
	var placed := Rect2i(at, from.size).intersection(clip)
	if placed.size.x <= 0 or placed.size.y <= 0:
		return
	image.blit_rect(source, Rect2i(from.position + placed.position - at, placed.size), placed.position)


static func _shape_path(role: String) -> String:
	if _manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TITLE_MANIFEST))
		if not parsed is Dictionary:
			push_error("Title manifest missing or invalid: " + TITLE_MANIFEST)
			return ""
		_manifest = parsed
	return str(((_manifest.get("shapes", {}) as Dictionary).get(role, {}) as Dictionary).get("texture", ""))

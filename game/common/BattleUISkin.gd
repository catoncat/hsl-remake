extends RefCounted
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: resource-derived content/generated/hsl/text/protected_words.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_dialogue_board.md
##   layout: provisional
##     (set_wrapped_text's break-before-name rule for the shaped UI labels; those labels have no original counterpart
##     read)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (panel shade: black at level 9 of 16, map luma × 0.46 under the status page and the growth panel)
##   layout: static-derived docs/evidence_packets/static_reverse/original_font_script/README.md
##     (FONT_BODY／FONT_SMALL = FONT.24／FONT.15 per window; cell top on row y; label() @1 white
##     over 0x8430 at (+1,+1))
##   layout: remake-invented
##     (button styling and the button step-down 17→11 for remake buttons; message_rows under
##     OPT-WORDBREAK keeps a protected name whole where the 38-byte break cuts it)
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const InterfaceArt = preload("res://game/common/InterfaceArt.gd")
const ROOT := ContentPaths.BATTLE_UI_PREVIEWS
const PANEL_DATA := "res://content/imported/hsl/shared/panels/manifest.json"
## Depth of the black shade under a full panel page, in 16ths: the battle root window's black
## shape at its last level, 8, drawn half-blended (0x4385e0..0x4385ff; BattlePanelMotion fades it).
const PANEL_SHADE_LEVEL := 8
const SHADE_LEVEL_SCALE := 16.0
## Original text colour codes @1/@2/@3/@5/@6 (hsl01.exe table 0x476b44, RGB565 → RGB) with their
## shadow colours; the original draws every glyph once at (+1,+1) in the shadow colour first.
const TEXT_WHITE := Color8(255, 255, 255)
const TEXT_RED := Color8(255, 80, 82)
const TEXT_GREEN := Color8(205, 255, 205)
const TEXT_YELLOW := Color8(255, 255, 123)
const TEXT_IVORY := Color8(255, 255, 222)
const TEXT_SHADOW := Color8(132, 134, 132)
## Original FONT.24 / FONT.15 cells: 24 px (12 px half-width) body text, 16 px (8 px) small text.
## Which one a window uses follows the original's call site (font pointer [0x4c1ae0] / [0x4c1adc],
## table in original_font_script/README.md). These are requested sizes: the default UI font (OriginalBitmapFont, OPT-FONT original) draws
## FONT_BODY with the FONT.24 face and FONT_SMALL with the FONT.15 face, unscaled; the system
## font (OPT-FONT system) draws them at 22／14 px.
const FONT_BODY := 22
const FONT_SMALL := 14
static var _panel_data: Dictionary = {}
static var _protected_words: PackedStringArray = []
## Message row width in source bytes (0x414561 pushes 0x26 to the row breaker 0x413960):
## 19 full-width Big5 glyphs, or 38 half-width ASCII characters.
const MESSAGE_ROW_BYTES := 38
## Upper bound on the re-shaping passes of set_wrapped_text (one per moved break).
const WRAP_PASSES := 32
## WINDOW50 frame width of UISkin.button (nine-patch margin).
const BUTTON_FRAME_MARGIN := 8.0
## UISkin.button text size, and the smallest it steps down to for a low button.
const BUTTON_FONT := 17
const BUTTON_FONT_MIN := 11


## The panel manifest (assets, items) with `actors` taken from the generated panel table
## (ContentPaths.ACTOR_PANELS: the imported rows plus the authored characters).
static func data() -> Dictionary:
	if _panel_data.is_empty():
		_panel_data = ContentPaths.read_json(PANEL_DATA)
		var panels: Variant = ContentPaths.read_json(ContentPaths.ACTOR_PANELS) if FileAccess.file_exists(ContentPaths.ACTOR_PANELS) else null
		if not panels is Dictionary or not (panels as Dictionary).get("actors") is Dictionary:
			push_error("Actor panel table missing or invalid: " + ContentPaths.ACTOR_PANELS)
		else:
			_panel_data["actors"] = panels["actors"]
	return _panel_data


static func asset(parent: Node, key: String, at: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture(key)
	image.position = at
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


static func texture(key: String) -> Texture2D:
	var record: Dictionary = data()["assets"][key]
	# Source I_CLAW is explicitly zero-sized. A blank equipment glyph is not a
	# load failure and must never silently borrow another weapon's icon.
	return null if record["empty"] else InterfaceArt.texture(record["res_path"])


## Swaps the shape shown by a reused TextureRect and resets the rect to the new shape's
## size. A TextureRect only ever grows to its minimum size, and its default STRETCH_SCALE
## draws the texture over the whole rect, so without the reset a smaller shape shown after
## a larger one is stretched (the Title042-047 lit items drawn at the 224 px 儲存戰場記錄
## width). Every runtime texture swap on an original-art TextureRect goes through here.
static func show_shape(rect: TextureRect, shape: Texture2D) -> void:
	rect.texture = shape
	rect.size = shape.get_size() if shape != null else Vector2.ZERO


## Marks a hover description box (WINDOW50): 0x436d70 draws it straight to the screen at a
## fixed spot (camera + (252,349)) with no window object of its own, so BattlePanelMotion never
## slides it and leaves it out of the close snapshot. `held`: drawn by a root-window list branch,
## which calls 0x436d70 only once its window has landed (+0x8c == 1), so it stays undrawn until
## the open slide lands; false for the 獲得物品 pending list (0x414c00 calls it at 0x4150ab in
## every state), whose box shows at its fixed spot mid-slide.
const IN_PLACE_META := &"panel_in_place"


static func in_place(box: CanvasItem, held := true) -> CanvasItem:
	box.set_meta(IN_PLACE_META, held)
	return box


static func clear_panel(parent: Control) -> ColorRect:
	parent.size = Vector2(640, 480)
	var shade := ColorRect.new()
	shade.size = parent.size
	shade.color = Color(0, 0, 0, PANEL_SHADE_LEVEL / SHADE_LEVEL_SCALE)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	return shade


## The battle UI shape `resource` (ROOT + resource + ".SHP.png"), or its authored replacement
## (InterfaceArt). Every load of a ROOT shape goes through here.
static func ui_shape(resource: String) -> Texture2D:
	return InterfaceArt.texture(ROOT + resource + ".SHP.png")


static func board(parent: Node, resource: String, at: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = ui_shape(resource)
	image.position = at
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


## Text in an original window: the cell is the original's 24 px / 16 px bitmap glyph row, whose
## top is the y the original passes 0x460884 (the bitmap font's line is the cell, so the glyphs
## sit exactly there). A system-font line (OPT-FONT system) taller than the cell grows the
## Label, so the cell is widened symmetrically about its centre instead of downwards.
static func text(parent: Node, at: Vector2, color: Color = TEXT_WHITE, font_size: int = FONT_BODY, cell: Vector2 = Vector2(0, 24)) -> Label:
	var row := label(parent, at, font_size)
	row.add_theme_color_override("font_color", color)
	row.add_theme_color_override("font_shadow_color", TEXT_SHADOW)
	var line := ceilf(row.get_theme_font("font").get_height(font_size))
	var height := maxf(cell.y, line)
	row.position = at - Vector2(0, (height - cell.y) / 2.0)
	row.size = Vector2(cell.x, height)
	row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## Original SHP placed by its draw origin (the anchor the engine passes to 0x4607f9).
static func anchored_asset(parent: Node, key: String, anchor: Vector2) -> TextureRect:
	var record: Dictionary = data()["assets"][key]
	var origin: Array = record["draw_origin"]
	return asset(parent, key, anchor - Vector2(float(origin[0]), float(origin[1])))


static func label(parent: Node, at: Vector2, font_size: int = 17) -> Label:
	var text := Label.new()
	text.position = at
	text.add_theme_font_size_override("font_size", font_size)
	text.add_theme_color_override("font_color", TEXT_WHITE)
	text.add_theme_color_override("font_shadow_color", TEXT_SHADOW)
	text.add_theme_constant_override("shadow_offset_x", 1)
	text.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(text)
	return text


## A WINDOW50-framed button exactly `dimensions` big. The 8 px frame margin is the texture's
## nine-patch margin; the text's vertical content margin shrinks so that the font line fits
## inside the requested height — with the full 8 px the minimum height (~40 px at 17 px)
## exceeded the 32 px town entries, every button grew and the stacked frames ran into each
## other (the town menu, lane R5-L5).
static func button(parent: Node, title: String, at: Vector2, dimensions: Vector2) -> Button:
	var control := Button.new()
	control.text = title
	control.position = at
	var font := control.get_theme_font("font")
	var font_size := BUTTON_FONT
	while font_size > BUTTON_FONT_MIN and ceilf(font.get_height(font_size)) > dimensions.y:
		font_size -= 1
	control.add_theme_font_size_override("font_size", font_size)
	var line := ceilf(font.get_height(font_size))
	var vertical := clampf(floorf((dimensions.y - line) / 2.0), 0.0, BUTTON_FRAME_MARGIN)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = ui_shape("WINDOW50")
		style.set_texture_margin_all(BUTTON_FRAME_MARGIN)
		style.content_margin_left = BUTTON_FRAME_MARGIN
		style.content_margin_right = BUTTON_FRAME_MARGIN
		style.content_margin_top = vertical
		style.content_margin_bottom = vertical
		style.modulate_color = Color(1.2, 1.12, 0.85) if state == "hover" else (Color(0.55, 0.55, 0.55) if state == "disabled" else Color.WHITE)
		control.add_theme_stylebox_override(state, style)
	parent.add_child(control)
	# Sized in the tree: out of it the rect clamps to a minimum measured without the overrides.
	control.size = dimensions
	return control


## Proper names (ContentPaths.PROTECTED_WORDS, longest first) a wrapped line never splits.
static func protected_words() -> PackedStringArray:
	if _protected_words.is_empty():
		var payload: Variant = ContentPaths.read_json(ContentPaths.PROTECTED_WORDS)
		if not payload is Dictionary:
			push_error("Protected word table missing or invalid: " + ContentPaths.PROTECTED_WORDS)
			return _protected_words
		for entry in payload["words"]:
			_protected_words.append(str(entry["word"]))
	return _protected_words


## Start of the protected word that a line starting at `index` would cut, or -1.
static func split_word_start(text: String, index: int) -> int:
	for word in protected_words():
		for inside in range(1, word.length()):
			var start := index - inside
			if start >= 0 and text.substr(start, word.length()) == word:
				return start
	return -1


## Line start indices of `text` as `label` wraps it (same font, size, width and break flags).
## Shapes the displayed form (`label.atr`: the simplified display seam maps one character to
## one, so the indices are those of `text`), because a simplified glyph can be narrower.
static func line_starts(label: Label, text: String) -> PackedInt32Array:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | (TextServer.BREAK_ADAPTIVE if label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART else 0)
	paragraph.width = label.size.x
	paragraph.add_string(label.atr(text), label.get_theme_font("font"), label.get_theme_font_size("font_size"), label.language)
	var starts := PackedInt32Array()
	for line in paragraph.get_line_count():
		starts.append(paragraph.get_line_range(line).x)
	return starts


## The rows of a message body as the original row breaker 0x413960 cuts them: a character
## that would take the row past `row_bytes` source bytes starts the next row (a Big5 character
## is two bytes, ASCII one; the imported text's "\n" is the source's "#" hard break). The
## original has no kinsoku and keeps no word whole (雪｜拉, 通行｜證 are cut). OPT-WORDBREAK
## (docs/OPTIONS.md, read on every call) 保護專名 moves a break that would cut a protected name
## to the name's start. The rows joined by "\n" are the body plus line breaks.
static func message_rows(text: String, row_bytes: int = MESSAGE_ROW_BYTES) -> PackedStringArray:
	var protect_names := str(load("res://game/settings/GameOptions.gd").value("OPT-WORDBREAK")) == "protect"
	var rows := PackedStringArray()
	var start := 0
	var used := 0
	var index := 0
	while index < text.length():
		if text[index] == "\n":
			rows.append(text.substr(start, index - start))
			start = index + 1
			used = 0
			index += 1
			continue
		var width := 1 if text.unicode_at(index) < 0x80 else 2
		if used + width > row_bytes and index > start:
			var cut := index
			var name_start := split_word_start(text, index) if protect_names else -1
			if name_start > start:
				cut = name_start
			rows.append(text.substr(start, cut - start))
			start = cut
			used = 0
			index = cut
			continue
		used += width
		index += 1
	rows.append(text.substr(start))
	return rows


## Sets a wrapping label's text so that no line break falls inside a protected name: where
## the shaped break would cut one, a line break is inserted before the name instead (the
## text is otherwise unchanged). Godot's ICU breaker may break between any two CJK
## ideographs (the 同伴 strip showed 緹／娜); the original message renderer is not read, so
## the rule is a remake choice (provisional). Call after the label has its final width.
static func set_wrapped_text(label: Label, text: String) -> void:
	var shown := text
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF and label.size.x > 0.0:
		for _pass in WRAP_PASSES:
			var moved := false
			for start in line_starts(label, shown):
				var word_start := split_word_start(shown, start)
				if word_start > 0 and shown[word_start - 1] != "\n":
					shown = shown.substr(0, word_start) + "\n" + shown.substr(word_start)
					moved = true
					break
			if not moved:
				break
	label.text = shown

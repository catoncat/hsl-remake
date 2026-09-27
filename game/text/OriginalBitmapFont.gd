extends RefCounted
## The original bitmap fonts as the game's UI font: FONT.24＋ASCFONT.24 (body: full glyphs 24×24,
## half glyphs 12×24) and FONT.15＋ASCFONT.15 (small: full 16×15, half 8×15 drawn 2 px lower),
## built from the atlases and glyph table `hsl generate original_bitmap_font` decodes from hsl.pak.
## One FontFile holds both faces as pre-rendered size caches: a requested font size in
## SMALL_SIZES draws the small face, one in BODY_SIZES the body face, glyphs never scaled — the
## original has only these two text sizes. A glyph sits with its cell's top on the line top and
## advances its cell width, no extra gap, as hsl01.exe's draw loop 0x4608e4. There is no system
## fallback font: Godot sizes every line by the tallest font of the chain (get_height), so a
## fallback would grow the 24／16 px lines to the system font's; a character missing from the
## atlas (`hsl check original_bitmap_font` counts them) or a size in neither list draws a code box.
## install() is the OPT-FONT read point: the default theme font is this font (original value) or
## the system font (improved value).
## provenance:
##   layout: resource-derived content/generated/hsl/fonts/original_fonts.json
##     (glyph bitmaps, cells and the character → glyph slot table)
##   layout: static-derived tools/hsltools/assets/original_bitmap_font.py
##     (advances = cell widths, zero extra gap, half-glyph drop 2 px in FONT.15: hsl01.exe 0x42f230／0x42f308／0x4608e4)
##   layout: remake-invented
##     (small line 16 px = 15 px cell + 1; the face per remake font size, SMALL_SIZES／BODY_SIZES; aliases ・ − ▶ › drawn
##     as ‧ - → >)

const GameOptions = preload("res://game/settings/GameOptions.gd")
const TABLE_PATH := "res://content/generated/hsl/fonts/original_fonts.json"
const SCHEMA := "hsl_original_fonts.v2"
const SYSTEM_FONT := "res://game/assets/ui_font.tres"
const OPTION := "OPT-FONT"
const BODY := "FONT24"
const SMALL := "FONT15"
## Line height per face: the full cell's height (body 24) or cell plus one (small 16).
const LINE_HEIGHT := {BODY: 24, SMALL: 16}
## The remake's requested font sizes (BattleUISkin.FONT_SMALL 14, the button step-down 11–17,
## FONT_BODY 22, panel literals 18–30) mapped onto the two original faces.
const SMALL_SIZES := [11, 12, 13, 14, 15, 16]
const BODY_SIZES := [17, 18, 20, 22, 24, 26, 30]

static var _table: Dictionary = {}
static var _font: FontFile = null


static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		assert(typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("schema", "")) == SCHEMA,
			"OriginalBitmapFont: %s missing or not %s" % [TABLE_PATH, SCHEMA])
		_table = parsed
	return _table


## The UI font with both faces, built once.
static func font() -> FontFile:
	if _font == null:
		_font = FontFile.new()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font.hinting = TextServer.HINTING_NONE
		_font.allow_system_fallback = false
		var images := {}
		for size in SMALL_SIZES:
			_add_face(_font, SMALL, size, images)
		for size in BODY_SIZES:
			_add_face(_font, BODY, size, images)
	return _font


## OPT-FONT read point (SimplifiedDisplay reads it at start and when the 重製選項 page closes
## with a change): the default theme font every Control without its own font override draws with.
static func install() -> void:
	var wanted: Font = font() if GameOptions.is_original(OPTION) else load(SYSTEM_FONT)
	var theme := ThemeDB.get_default_theme()
	if theme.default_font != wanted:
		theme.default_font = wanted
		ThemeDB.fallback_font = wanted


static func _add_face(target: FontFile, face: String, size: int, images: Dictionary) -> void:
	var record: Dictionary = table()["faces"][face]
	if not images.has(face):
		var texture := load("res://" + str(record["atlas"])) as Texture2D
		assert(texture != null, "OriginalBitmapFont: atlas %s not imported" % record["atlas"])
		images[face] = texture.get_image()
	var cache := Vector2i(size, 0)
	var line: int = LINE_HEIGHT[face]
	var cell_full := Vector2(record["full_cell"][0], record["full_cell"][1])
	var cell_half := Vector2(record["half_cell"][0], record["half_cell"][1])
	var columns := int(record["full_columns"])
	var half_top := float(record["half_row_top"])
	var drop := float(record["half_drop"])
	target.set_cache_ascent(0, size, cell_full.y)
	target.set_cache_descent(0, size, line - cell_full.y)
	target.set_texture_image(0, cache, 0, images[face])
	var chars: String = table()["chars"]
	for index in chars.length():
		_glyph(target, cache, chars.unicode_at(index), Rect2(Vector2(index % columns, index / columns) * cell_full, cell_full), cell_full.y, 0.0)
	var half: Array = table()["half_range"]
	for code in range(int(half[0]), int(half[1])):
		_glyph(target, cache, code, Rect2(Vector2(code * cell_half.x, half_top), cell_half), cell_full.y, drop)
	var aliases: Dictionary = table()["half_aliases"]
	for character in aliases:
		var code := String(aliases[character]).unicode_at(0)
		_glyph(target, cache, String(character).unicode_at(0), Rect2(Vector2(code * cell_half.x, half_top), cell_half), cell_full.y, drop)


static func _glyph(target: FontFile, cache: Vector2i, code: int, uv: Rect2, ascent: float, drop: float) -> void:
	target.set_glyph_advance(0, cache.x, code, Vector2(uv.size.x, 0))
	target.set_glyph_offset(0, cache, code, Vector2(0, drop - ascent))
	target.set_glyph_size(0, cache, code, uv.size)
	target.set_glyph_uv_rect(0, cache, code, uv)
	target.set_glyph_texture_idx(0, cache, code, 0)

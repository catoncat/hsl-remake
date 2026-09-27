extends Translation
## The one display seam that shows the traditional source text the way the original font draws
## it. The original stores Big5 traditional text and draws simplified glyphs at traditional
## codes (FONT.24／FONT.15); the remake keeps the traditional text (label.text, data, saves)
## and swaps characters here, when a Control translates its text for display. One character
## maps to one character (content/generated/hsl/text/simplified_chars.json keeps every display
## form a single BMP character), so string lengths and indexes stay those of the source.
## Controls translate automatically (auto_translate_mode inherits ALWAYS from the root);
## text drawn outside a Control would bypass this seam — game/ has none.
## provenance:
##   strings: resource-derived docs/evidence_packets/static_reverse/original_font_script/glyph_review.json
##   strings: remake-invented content/generated/hsl/text/simplified_chars.json#remake_choices
##     (職 font bug, 噁 outside the system font, 鍾針魘 unresolved)
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const TABLE_PATH := "res://content/generated/hsl/text/simplified_chars.json"
const SCHEMA := "hsl_simplified_chars.v1"

var chars: Dictionary = {}


func _init() -> void:
	locale = "zh_CN"
	var parsed: Variant = ContentPaths.read_json(TABLE_PATH)
	assert(typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("schema", "")) == SCHEMA,
		"SimplifiedDisplayTranslation: %s missing or not %s" % [TABLE_PATH, SCHEMA])
	chars = parsed["chars"]


## The displayed form of `text`; "" when nothing changes (TranslationServer then keeps the source).
func convert_text(text: String) -> String:
	var out := PackedStringArray()
	var changed := false
	for character in text:
		var shown: String = chars.get(character, character)
		changed = changed or shown != character
		out.append(shown)
	return "".join(out) if changed else ""


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	return StringName(convert_text(String(src_message)))

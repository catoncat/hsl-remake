extends Node
## Autoload that installs the simplified display seam (SimplifiedDisplayTranslation) for the
## whole game — title, battle, world map and town scenes and every scene suite — and removes it
## when the tree shuts down (a script Translation left in TranslationServer past script
## shutdown crashes Godot 4.7 on exit). texture_path() is the image half of the seam: a shape
## whose baked lettering is traditional (workteam) resolves to its simplified redraw. It also
## installs the UI font (OriginalBitmapFont.install, the OPT-FONT read point) at start and again
## when the 重製選項 page closes with a changed value.
## provenance:
##   strings: resource-derived docs/evidence_packets/static_reverse/original_font_script/README.md
##   strings: remake-invented content/generated/hsl/text/simplified_images.json
##     (workteam credits redrawn with FONT.24 glyphs)

const SimplifiedDisplayTranslation = preload("res://game/text/SimplifiedDisplayTranslation.gd")
const OriginalBitmapFont = preload("res://game/text/OriginalBitmapFont.gd")
## RemakeOptionsPage.LISTENERS (a literal: preloading the page would pull the UI skin into the autoload).
const OPTION_LISTENERS := "remake_options_listeners"
const IMAGE_TABLE_PATH := "res://content/generated/hsl/text/simplified_images.json"
const IMAGE_SCHEMA := "hsl_simplified_images.v1"

static var _images: Dictionary = {}
var translation: Translation = null


## The texture to show for `path`: its simplified redraw when the image table lists one.
static func texture_path(path: String) -> String:
	if _images.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IMAGE_TABLE_PATH))
		assert(typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("schema", "")) == IMAGE_SCHEMA,
			"SimplifiedDisplay: %s missing or not %s" % [IMAGE_TABLE_PATH, IMAGE_SCHEMA])
		_images = parsed["images"]
	return str(_images.get(path, path))


func _enter_tree() -> void:
	translation = SimplifiedDisplayTranslation.new()
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale(translation.locale)
	OriginalBitmapFont.install()
	add_to_group(OPTION_LISTENERS)


func remake_options_changed() -> void:
	OriginalBitmapFont.install()


func _exit_tree() -> void:
	TranslationServer.remove_translation(translation)
	translation = null

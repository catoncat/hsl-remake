extends Node
## Start scene of the web export only (tools/web_build.py stage makes it the main scene; desktop
## keeps the title): the core carries the code and the few files the autoloads read at start, the
## title-side art and data are the base packs of the `boot` group (tools/web_packs.py BASE_PACKS).
## This scene mounts that group — from the browser cache, or downloaded on the first visit and
## after a build that changed one of them — and only then hands over to the title, which loads them.
## provenance:
##   rules: remake-invented (web delivery of the remake's own build; the original ships one install)

const WebPacks = preload("res://game/web/PackManager.gd")
const TITLE_SCENE := "res://game/title/TitleScreen.tscn"
const BOOT_GROUP := "boot"


func _ready() -> void:
	WebPacks.after_groups([BOOT_GROUP], get_tree().change_scene_to_file.bind(TITLE_SCENE))

extends RefCounted
## Player settings behind the original 設定選項 panel: 場景效果 (story effect objects drawn or
## not), 預備動作 (`ready_action`: the magic／絶技 caster's ANIMAL cast lead plays or not —
## the original's [0x477c14] bit1, on by default), 音效音量 and 音樂音量. Stored in
## user://settings.json and applied to the audio buses.
## The same file keeps the 重製選項 choice (docs/OPTIONS.md §6): `preset` (original／comfort／
## custom) and `presentation` (option id → value id, the rows chosen under 自定); GameOptions
## resolves them against the option registry. Unknown keys are ignored and missing keys take
## their defaults, so files written before these keys still read as hsl_settings.v1; neither
## key goes into any save.
##
## Bus model (remake): every player sits on Master by default, so 音效音量 drives the Master
## bus and music players sit on a runtime-created "Music" bus whose gain is compensated so
## that 音樂音量 stays independent of Master (music_out = music_db). The original mixer is
## not located; the 設定選項 row semantics are provisional readings of the baked labels.
## The music tracks are the original ones (docs/evidence_packets/static_reverse/original_music.md);
## the bus model and the volume curve are the remake's: 0 mutes and a change is heard at once,
## where the original skips PlayMusic at volume 0 and only its next call starts a track (§1).
## provenance:
##   rules: static-derived docs/evidence_packets/runtime_observations/system_menu/README.md
##     (預備動作 = [0x477c14] bit1, default on)
##   rules: provisional (設定選項 row semantics read from the baked Title039 labels; original mixer not located)
##   rules: remake-invented docs/OPTIONS.md (preset／presentation keys hold the 重製選項 choice)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json

const PATH := "user://settings.json"
const SCHEMA := "hsl_settings.v1"
const MUSIC_BUS := "Music"
const MIN_DB := -60.0
## Gain of every music player (battle, title, world map, town, GameClear). The original plays
## music and sound effects at the same full volume (255, docs/evidence_packets/static_reverse/
## original_music.md §1); the remake's effect players sit at -4..-8 dB, so music sits at -6 dB.
const MUSIC_PLAYER_DB := -6.0
## 音樂音量 defaults to full like the original's 255 (original_music.md §1; user decision
## 2026-09-26). A stored value is the player's own choice and is kept as it is.
const DEFAULTS := {"scene_effects": true, "ready_action": true, "sfx_volume": 1.0, "music_volume": 1.0, "preset": "original", "presentation": {}}
## 重製選項 presets a stored `preset` may name; anything else reads as original.
const PRESETS := ["original", "comfort", "custom"]
static var _cache: Dictionary = {}


static func load_settings() -> Dictionary:
	if not _cache.is_empty():
		return _cache.duplicate(true)
	var settings := DEFAULTS.duplicate(true)
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("schema", "")) == SCHEMA:
			for key in DEFAULTS:
				if parsed.has(key):
					settings[key] = parsed[key]
	_cache = _normalized(settings)
	return _cache.duplicate(true)


static func get_value(key: String) -> Variant:
	return load_settings().get(key, DEFAULTS.get(key))


## Stores one setting, persists the file and re-applies the audio buses.
static func set_value(key: String, value: Variant) -> Dictionary:
	return set_values({key: value})


## Stores several settings in one write (the 重製選項 preset and its rows change together).
static func set_values(values: Dictionary) -> Dictionary:
	var settings := load_settings()
	settings.merge(values, true)
	_cache = _normalized(settings)
	var record := _cache.duplicate(true)
	record["schema"] = SCHEMA
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(record, "  "))
		file.close()
	apply()
	return _cache.duplicate(true)


static func reset() -> void:
	_cache = {}
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	apply()


static func scene_effects_enabled() -> bool:
	return bool(get_value("scene_effects"))


## 預備動作: the original's 0x424590 sets／clears [0x477c14] bit1, read once per cast by the
## attacker object 0x401c20 (0x401e74); off plays no cast lead (AnimalCastLead.skipped).
static func ready_action_enabled() -> bool:
	return bool(get_value("ready_action"))


## Name of the music bus, created on first use so music players can be routed to it.
static func music_bus() -> String:
	if AudioServer.get_bus_index(MUSIC_BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, MUSIC_BUS)
		AudioServer.set_bus_send(index, "Master")
		apply()
	return MUSIC_BUS


## Master carries 音效音量; the Music bus is offset so its output equals 音樂音量 alone.
static func apply() -> void:
	var settings := load_settings()
	var master_db := volume_db(float(settings["sfx_volume"]))
	AudioServer.set_bus_volume_db(0, master_db)
	var music_index := AudioServer.get_bus_index(MUSIC_BUS)
	if music_index >= 0:
		AudioServer.set_bus_volume_db(music_index, clampf(volume_db(float(settings["music_volume"])) - master_db, MIN_DB, -MIN_DB))


static func volume_db(linear: float) -> float:
	if linear <= 0.001:
		return MIN_DB
	return maxf(linear_to_db(clampf(linear, 0.0, 1.0)), MIN_DB)


static func _normalized(settings: Dictionary) -> Dictionary:
	var preset := str(settings.get("preset", DEFAULTS["preset"]))
	var presentation := {}
	var stored: Variant = settings.get("presentation", {})
	if stored is Dictionary:
		for id in stored:
			if id is String and stored[id] is String:
				presentation[id] = stored[id]
	return {
		"scene_effects": bool(settings.get("scene_effects", DEFAULTS["scene_effects"])),
		"ready_action": bool(settings.get("ready_action", DEFAULTS["ready_action"])),
		"sfx_volume": snappedf(clampf(float(settings.get("sfx_volume", DEFAULTS["sfx_volume"])), 0.0, 1.0), 0.01),
		"music_volume": snappedf(clampf(float(settings.get("music_volume", DEFAULTS["music_volume"])), 0.0, 1.0), 0.01),
		"preset": preset if preset in PRESETS else str(DEFAULTS["preset"]),
		"presentation": presentation,
	}


static func summary() -> Dictionary:
	var settings := load_settings()
	settings["master_db"] = AudioServer.get_bus_volume_db(0)
	var music_index := AudioServer.get_bus_index(MUSIC_BUS)
	settings["music_bus_db"] = AudioServer.get_bus_volume_db(music_index) if music_index >= 0 else 0.0
	return settings

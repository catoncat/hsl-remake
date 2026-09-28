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
## Bus model (original mixer, docs/evidence_packets/static_reverse/original_music.md §5):
## 音效音量 [0x477c20] goes to waveOutSetVolume (0x458220 → 0x4581c0, both channels v×256) —
## a linear device gain over everything the game plays — so it drives the Master bus linearly,
## 0 mutes. Effect sounds play at 255 (0 dB) under it. 音樂音量 [0x477c24] sets the music
## stream's DirectSound volume (0x424630 → 0x459e60 → 0x459d70): (⌊60v/255⌋ − 60) × 40
## hundredths of a dB, so the Music bus runs 0 dB down to −24 dB at 0 (not silent) and sends
## into Master. Film soundtracks take the same stream curve from 音效音量 (0x42df6f → 0x45c5f0
## → 0x45a330), on the Movie bus. Both sliders act at once on what is playing; at 音樂音量 0
## a new track does not start (PlayMusic 0x42c250), see music_starts().
## provenance:
##   rules: static-derived docs/evidence_packets/runtime_observations/system_menu/README.md
##     (預備動作 = [0x477c14] bit1, default on)
##   rules: static-derived docs/evidence_packets/static_reverse/original_music.md (§5 volume curves)
##   rules: provisional (sliders step 0.1 where the original steps 15／255; 場景效果 hides clouds and
##     story effect objects, the original also hides mapobjWaterFall／mapobjBuildBottom and two
##     unidentified objects)
##   rules: remake-invented docs/OPTIONS.md (preset／presentation keys hold the 重製選項 choice)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const PATH := "user://settings.json"
const SCHEMA := "hsl_settings.v1"
const MUSIC_BUS := "Music"
const MOVIE_BUS := "Movie"
## IDirectSoundBuffer::SetVolume floor used by 0x459d70 (−10000 hundredths of a dB).
const STREAM_FLOOR_DB := -100.0
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
		var parsed: Variant = ContentPaths.read_json(PATH)
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
	return _bus(MUSIC_BUS)


## Name of the film soundtrack bus (stream curve from 音效音量, 0x42df6f).
static func movie_bus() -> String:
	return _bus(MOVIE_BUS)


static func _bus(bus_name: String) -> String:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
		apply()
	return bus_name


## Master = waveOutSetVolume gain of 音效音量 (linear, 0 mutes); Music／Movie = stream curve.
static func apply() -> void:
	var settings := load_settings()
	var sfx := float(settings["sfx_volume"])
	AudioServer.set_bus_mute(0, original_level(sfx) <= 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(sfx, 0.001)))
	var music_index := AudioServer.get_bus_index(MUSIC_BUS)
	if music_index >= 0:
		AudioServer.set_bus_volume_db(music_index, stream_db(float(settings["music_volume"])))
	var movie_index := AudioServer.get_bus_index(MOVIE_BUS)
	if movie_index >= 0:
		AudioServer.set_bus_volume_db(movie_index, stream_db(sfx))


## Slider value 0..1 as the original's 0..255 volume byte.
static func original_level(value: float) -> int:
	return clampi(roundi(clampf(value, 0.0, 1.0) * 255.0), 0, 255)


## 0x459d70: SetVolume((⌊60v/255⌋ − 60) × 40) hundredths of a dB, floor −10000.
static func stream_db(value: float) -> float:
	var v := original_level(value)
	return maxf(float(floori(60.0 * v / 255.0) - 60) * 0.4, STREAM_FLOOR_DB)


## PlayMusic 0x42c250 returns before stopping or starting anything while 音樂音量 is 0; the
## track already playing goes on, and raising the volume starts nothing until the next call.
static func music_starts() -> bool:
	return original_level(float(get_value("music_volume"))) > 0


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

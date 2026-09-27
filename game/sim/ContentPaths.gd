extends RefCounted
## The generated／imported tables the battle loop and its panels read for every
## scenario, in one place. A battle JSON names its own inputs under `resources`
## (map, terrain, seed, consumables, portraits of its speakers, …); these are the
## shared tables a scenario cannot override — skills, learning, AI profiles,
## entry growth, rewards, the equipment catalog and the roster face table.
## provenance:
##   rules: remake-invented (path registry; the tables themselves carry their own provenance)

const SKILL_TARGETING := "res://content/generated/hsl/skills/targeting.json"
const SKILL_BOOK := "res://content/generated/hsl/skills/initial_book.json"
const GROWTH_LIFECYCLE := "res://content/generated/hsl/roles/growth_lifecycle.json"
const AI_PROFILES := "res://content/generated/hsl/ai/profiles.json"
const ENTRY_GROWTH := "res://content/generated/hsl/roles/entry_growth.json"
const BATTLE_REWARDS := "res://content/generated/hsl/combat/rewards.json"
const EQUIPMENT_ITEMS := "res://content/generated/hsl/equipment/items.json"
## Proper names a wrapped UI line keeps on one line (tools/hsltools/data/protected_words.py).
const PROTECTED_WORDS := "res://content/generated/hsl/text/protected_words.json"
## Face／name row per actor id for every unit a panel can select (the scenario's
## `resources.portraits` lists only that battle's dialogue speakers): the imported
## chapter-01 faces plus the authored characters (tools/hsltools/data/roster_portraits.py).
const ACTOR_PORTRAITS := "res://content/generated/hsl/roles/actor_portraits.json"
## 稱號／種族／display stats per actor id for the WINDOW10 boards and panels: the imported
## panel rows plus the authored characters (tools/hsltools/data/actor_panels.py).
const ACTOR_PANELS := "res://content/generated/hsl/roles/actor_panels.json"
## Imported art and sound every level shares (content/imported/hsl/shared/), read by the
## engine itself rather than named per scenario. Per-level resources (battleNNN/ maps, walk
## frames, portraits, timelines, …) come from the scenario's `resources`, never from a path
## built here.
## Stand sprites of map_objects.json records, one PNG per shape id.
const MAP_OBJECT_PREVIEWS := "res://content/imported/hsl/shared/shape_previews/map_object"
## Battle UI SHP previews (bars, digits, frames), one PNG per `<name>.SHP.png`.
const BATTLE_UI_PREVIEWS := "res://content/imported/hsl/shared/shape_previews/battle_ui/"
## RESOURCE interface cues (confirm, hit, cast, level-up, game over); a scenario's
## `resources.interface_audio` names the same manifest for its menus.
const INTERFACE_AUDIO := "res://content/imported/hsl/shared/interface_audio/manifest.json"
## 氣刃斬 panels and art — the staging a synthetic clip borrows.
const FIRST_SKILL := "res://content/imported/hsl/shared/first_skill/manifest.json"
## EFFECTS.TXT scripts, frames and WAVs of every imported SPECIAL／MAGIC row.
const SKILL_EFFECTS := "res://content/imported/hsl/shared/skill_effects/manifest.json"
## Cast_Star casting frames.
const MAGE_MAGIC := "res://content/imported/hsl/shared/mage_magic/manifest.json"
## 月花圓舞 frames and its two sounds.
const MOON_DANCE := "res://content/imported/hsl/shared/moon_dance/manifest.json"
## 毒魔箭 SP19 art and sounds.
const POISON_ARROW := "res://content/imported/hsl/shared/poison_arrow/manifest.json"


## Parsed JSON at `path`: null when the path is empty, missing or not JSON.
static func read_json(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## `actors` table of the roster face manifest; an unreadable table is a data error,
## not a reason to draw from another chapter.
static func actor_portraits() -> Dictionary:
	var parsed: Variant = read_json(ACTOR_PORTRAITS)
	if not parsed is Dictionary or not (parsed as Dictionary).get("actors") is Dictionary:
		push_error("Roster portrait manifest missing or invalid: " + ACTOR_PORTRAITS)
		return {}
	return (parsed as Dictionary)["actors"]

extends RefCounted
## Which PLAYERS row keys a unit's presentation resources (walk frames, portrait).
## The original job-up exchange 0x4348f0 overwrites the member's shape record (+0x2c)
## and face (+0x5c) with the target row's (static-derived, original_town_job_up.md),
## so a member that has changed title is drawn with the target row; the remake keeps
## `actor_id` as the rules key and stores that row in `job_up_target_actor_id`.
## Pure lookups over the PlayLoop unit dictionary — no state lives here.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_town_job_up.md
##   audio: resource-derived content/imported/hsl/shared/actor_audio.json

const SHARED_WALK_MANIFEST_PATH := "res://content/imported/hsl/shared/actor_walk_frames/actor_walk_manifest.json"
## Sound bindings of the job-up target rows 010–020 and of the level-37 guardian 052 (whose
## walk frames share the up-title manifest; tools/hsltools/assets/job_up_audio.py), looked up
## after the level's own actor_audio manifest.
const SHARED_AUDIO_MANIFEST_PATH := "res://content/imported/hsl/shared/actor_audio.json"


## The row the unit currently stands on: its job-up target when it has one, else its actor id.
static func resolve(unit: Dictionary) -> String:
	var target := str(unit.get("job_up_target_actor_id", ""))
	return target if target != "" else str(unit.get("actor_id", ""))


## Walk-frame key: the resolved row when a manifest in `manifests` (level first, then the
## shared up-title manifest) carries it, otherwise the base actor id. 018 (克羅蒂's second
## title) has its SHAPEDEF row commented out in the original and is not imported, so such
## a member keeps its base frames rather than dropping to the single-frame fallback.
static func frame_key(unit: Dictionary, manifests: Array) -> String:
	var key := resolve(unit)
	if manifest_entry(key, manifests).is_empty():
		return str(unit.get("actor_id", ""))
	return key


## First manifest entry for `actor_id` in lookup order; {} when none has it.
static func manifest_entry(actor_id: String, manifests: Array) -> Dictionary:
	for manifest_value in manifests:
		if typeof(manifest_value) != TYPE_DICTIONARY:
			continue
		var actors: Dictionary = (manifest_value as Dictionary).get("actors", {})
		var entry: Dictionary = actors.get(actor_id, {})
		if not entry.is_empty():
			return entry
	return {}


## Sound `event` (walk／attack／miss／dead) res_path for a unit: 0x4348f0 copies the target
## row's four sound fields into the member record (static-derived, original_town_job_up.md),
## so the resolved row is tried first in each `hsl_actor_audio.v1` manifest of `manifests`
## (level first, then the shared job-up manifest), then the base actor id. "" when no
## manifest binds the event (PLAYERS rows may declare no sound for it).
static func audio_binding(unit: Dictionary, event: String, manifests: Array) -> String:
	var rows := [resolve(unit), str(unit.get("actor_id", ""))]
	for row in rows:
		if row == "" or not row.is_valid_int():
			continue
		var code := str(int(row))
		for manifest_value in manifests:
			if typeof(manifest_value) != TYPE_DICTIONARY:
				continue
			var manifest: Dictionary = manifest_value
			var character: Dictionary = (manifest.get("characters", {}) as Dictionary).get(code, {})
			var sound_id := str(character.get(event, ""))
			if sound_id == "":
				continue
			return str(((manifest.get("sounds", {}) as Dictionary).get(sound_id, {}) as Dictionary).get("res_path", ""))
	return ""


## Row key into an actor-id table (portrait manifest actors, UISkin actors): the resolved
## row when the table has it — 020 has its own FACE0020 portrait and every 010–020 row has
## its own title — otherwise the base actor id (rows 010–019 repeat the base FACE).
static func row_key(unit: Dictionary, table: Dictionary) -> String:
	var key := resolve(unit)
	return key if table.has(key) else str(unit.get("actor_id", ""))

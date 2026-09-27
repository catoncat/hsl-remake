extends RefCounted
## Applies the town / big-map actions a finished script recorded to the campaign's
## shared world state (hsl_world_state.v1) at hand-off time, so the big map and
## the towns see what the script changed: a battle's WinfailScenarioRules keeps
## actSetTownExecEvent, actBMSetPointEvent, actBMClearTrackFlag, actAddTE, ... as
## winfail_runtime.pending_world_flags (level 1's victory arms 歐姆村 event 9; most
## main-range levels write point events / encounter ratios), and a story scene's
## BattleOpeningCoordinator keeps the same tokens as recorded_no_handler
## story_records (STORY 8/9/56/61/63/69/71/72/74). A campaign without a world state
## yet gets a fresh one seeded from the registered world-map scene. Pure: returns
## new dictionaries plus the interpreter's effects/records; token semantics are
## TownEventRules' provisional readings.
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: provisional
##     (token semantics are TownEventRules' readings — docs/evidence_packets/static_reverse/town_event_semantics.md)

const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")

## Compiled-timeline event kinds (tools/hsltools/levels/timeline.py) back to
## the script token TownEventRules interprets.
const STORY_KIND_ACTIONS := {
	"town_exec_event": "actSetTownExecEvent",
	"town_exit_exec_event": "actSetTownExitExecEvent",
	"town_event_add": "actAddTE",
	"town_event_delete": "actDeleteTE",
	"bigmap_walk_to_point": "actSetBMWalkToPoint",
	"bigmap_walker_player_id": "actSetBMWalkerPlayerID",
	"bigmap_point_mode": "actBMSetPointMode",
	"bigmap_track_mode": "actBMSetTrackMode",
	"bigmap_point_flag_set": "actBMSetPointFlag",
	"bigmap_track_flag_set": "actBMSetTrackFlag",
	"bigmap_point_flag_clear": "actBMClearPointFlag",
	"bigmap_track_flag_clear": "actBMClearTrackFlag",
	"bigmap_point_event": "actBMSetPointEvent",
	"bigmap_point_encounter_ratio": "actBMSetPointEncounterRatio",
	"bigmap_show_track_point": "actBMSetShowTrackPoint",
	"game_over_score_add": "actAddOverScore",
	"game_over_flag": "actSetOverFlag",
}


## The recorded world-flow actions of a finished PlayLoop, in script order.
static func pending_actions(loop: Dictionary) -> Array:
	var actions: Array = []
	var runtime: Variant = loop.get("winfail_runtime", {})
	if typeof(runtime) != TYPE_DICTIONARY:
		return actions
	for entry in (runtime as Dictionary).get("pending_world_flags", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry
		actions.append({"name": str(record.get("name", "")), "args": (record.get("args", []) as Array).duplicate(), "key": str(record.get("key", ""))})
	return actions


## The registered world-map scene descriptor (campaign.json world_map), or {}.
static func scene_config(campaign: Dictionary) -> Dictionary:
	var entry: Variant = campaign.get("world_map", {})
	var scene_path := str((entry as Dictionary).get("scenario", "")) if typeof(entry) == TYPE_DICTIONARY else ""
	if scene_path == "" or not FileAccess.file_exists(scene_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(scene_path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The town / big-map events a story scene recorded, in playback order.
static func story_actions(records: Array) -> Array:
	var actions: Array = []
	for entry in records:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry
		var kind := str(record.get("kind", ""))
		if not STORY_KIND_ACTIONS.has(kind):
			continue
		actions.append({"name": str(STORY_KIND_ACTIONS[kind]), "args": (record.get("args", []) as Array).duplicate(), "key": str(record.get("source_event_id", ""))})
	return actions


## World state to apply script actions to: the carried one when valid, otherwise
## a fresh state at the world-map scene's start point with every town's initial
## tree. Returns an error when the campaign registers no world map or its data
## cannot be loaded — callers then leave the actions recorded.
static func ensure_state(world: Dictionary, campaign: Dictionary) -> Dictionary:
	if WorldMapRules.state_valid(world):
		return {"state": world.duplicate(true), "seeded": false}
	var config := scene_config(campaign)
	if config.is_empty():
		return {"state": {}, "seeded": false, "error": "no_world_map_scene"}
	var world_map := WorldMapRules.load_world_map(BattleScenario.resource_path(config, "world_map"))
	if not bool(world_map.get("ok", false)):
		return {"state": {}, "seeded": false, "error": "world_map_load_failed"}
	var towndef := TownEventRules.load_towndef(BattleScenario.resource_path(config, "towndef"))
	var trees := TownEventRules.load_initial_trees(BattleScenario.resource_path(config, "town_initial_trees"))
	if towndef.has("error") or trees.has("error"):
		return {"state": {}, "seeded": false, "error": "town_data_load_failed"}
	var towns := TownEventRules.initial_town_state(towndef, trees)
	if towns.has("error"):
		return {"state": {}, "seeded": false, "error": str(towns["error"])}
	return {"state": WorldMapRules.initial_state(world_map, int(config.get("start_point", 1)), towns, config.get("new_game", {})), "seeded": true, "world_map": world_map}


## Stands the party at a big-map point (a level's "N,gameBigMapLevel" return or
## its default own-point return), seeding the world state on a first visit.
static func place_party(world: Dictionary, point: int, campaign: Dictionary) -> Dictionary:
	var ensured := ensure_state(world, campaign)
	if ensured.has("error"):
		return {"world": world.duplicate(true), "error": str(ensured["error"])}
	var world_map: Dictionary = ensured.get("world_map", {})
	if world_map.is_empty():
		world_map = WorldMapRules.load_world_map(BattleScenario.resource_path(scene_config(campaign), "world_map"))
		if not bool(world_map.get("ok", false)):
			return {"world": world.duplicate(true), "error": "world_map_load_failed"}
	var placed := WorldMapRules.visit(ensured["state"], world_map, point)
	# The returned-to point is shown even when its reveal never played (script returns).
	var modes: Dictionary = placed.get("point_modes", {})
	modes[str(point)] = WorldMapRules.MODE_SHOWN
	placed["point_modes"] = modes
	return {"world": placed, "seeded": bool(ensured.get("seeded", false))}


## Applies recorded actions to the hand-off world state. Returns {world, applied,
## effects, records, seeded, error?}; with no actions the incoming world passes
## through untouched (no seeding for nothing).
static func apply_actions(world: Dictionary, actions: Array, campaign: Dictionary) -> Dictionary:
	if actions.is_empty():
		return {"world": world.duplicate(true), "applied": 0, "effects": [], "records": [], "seeded": false}
	var untouched := {"world": world.duplicate(true), "applied": 0, "effects": [], "records": [], "seeded": false, "pending": actions}
	var ensured := ensure_state(world, campaign)
	if ensured.has("error"):
		untouched["error"] = str(ensured["error"])
		return untouched
	var config := scene_config(campaign)
	var towndef := TownEventRules.load_towndef(BattleScenario.resource_path(config, "towndef"))
	if towndef.has("error"):
		untouched["error"] = "town_data_load_failed"
		return untouched
	var result := TownEventRules.apply_script_town_actions(ensured["state"], actions, towndef)
	if result.has("error"):
		untouched["error"] = str(result["error"])
		return untouched
	var applied := 0
	for record in result.get("records", []):
		if str((record as Dictionary).get("status", "")) == "applied":
			applied += 1
	return {"world": result["state"], "applied": applied, "effects": result["effects"], "records": result["records"], "seeded": bool(ensured.get("seeded", false))}


## A finished battle loop's recorded actions (winfail_runtime.pending_world_flags).
static func apply_pending(world: Dictionary, loop: Dictionary, campaign: Dictionary) -> Dictionary:
	return apply_actions(world, pending_actions(loop), campaign)


## A finished story scene's recorded town / big-map events (story_records).
static func apply_story(world: Dictionary, records: Array, campaign: Dictionary) -> Dictionary:
	return apply_actions(world, story_actions(records), campaign)

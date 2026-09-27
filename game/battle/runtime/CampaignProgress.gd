extends Node
## Campaign progression between battles: resolves the next scenario from the
## finished PlayLoop's next_level_event, captures the controlled party and hands
## the next scene its scenario path plus carry-over. Holds no battle state; the
## pending hand-off is a process-local static consumed once by the next runtime.
## provenance:
##   rules: resource-derived content/battles/campaign.json; static-derived docs/evidence_packets/static_reverse/original_check_targets.md#R8; remake-invented (one-shot hand-off, resume prompt, play-time counter, not-remade chapter end returns to the title; the carry stands in for the original registered-slot table)
##   layout: remake-invented (resume prompt placement)
##   strings: remake-invented (「繼續」／「從第一戰重新開始」)
##   timing: n/a
##   audio: n/a

const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const WorldScriptActions = preload("res://game/world/WorldScriptActions.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const UISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const CAMPAIGN_PATH := "res://content/battles/campaign.json"
const SCHEMA := "hsl_campaign_progress.v1"
## Campaign position persisted across app launches: the last hand-off (scenario
## path + carried party), written when the campaign moves to a new scenario.
const PROGRESS_PATH := "user://campaign_progress.json"
const PROGRESS_SCHEMA := "hsl_campaign_progress_save.v1"

static var pending: Dictionary = {}
## Headless test seams and dev entry points do not show the resume prompt unless
## a test opts in; the product opening of the campaign's first battle always does.
static var resume_prompt_in_headless := false
## Hand-off that entered the current battle; a scene reload without a new
## pending hand-off (restart / retry) re-enters the same battle with the same party.
static var last_entry: Dictionary = {}
## Cumulative play time of the campaign in seconds (the big-map status bar shows
## it as h:mm:ss); counted while a scene processes, persisted with the progress.
static var play_seconds := 0.0
## The campaign this process plays: campaign.json; a test points it at a fixture
## campaign (another start_level) before booting the title or the runtime.
static var campaign_path := CAMPAIGN_PATH

var runtime: Node
var campaign: Dictionary = {}
## A won campaign battle whose original next level is not remade yet ends the chapter:
## start_next_battle returns false and the battle leaves for the title (progress kept).
var chapter_end_mode := false
var last_handoff: Dictionary = {}
## Receipt of the last hand-off's script world-flow application (tests / summary).
var last_world_flow: Dictionary = {}
var resume_layer: CanvasLayer
var resume_button: Button
var restart_button: Button


static func load_campaign(path: String = "") -> Dictionary:
	if path == "":
		path = campaign_path
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("schema", "")) != "hsl_campaign.v1":
		return {}
	return parsed


static func has_pending() -> bool:
	return not pending.is_empty()


static func consume_pending() -> Dictionary:
	var handoff := pending.duplicate(true)
	pending = {}
	return handoff


## The hand-off a freshly bootstrapping runtime should apply: a new pending
## hand-off wins and becomes the retry baseline; otherwise the previous entry is
## replayed so restarting the current battle keeps its scenario and carry.
static func take_handoff() -> Dictionary:
	if has_pending():
		last_entry = consume_pending()
	return last_entry.duplicate(true)


static func reset_campaign() -> void:
	pending = {}
	last_entry = {}
	play_seconds = 0.0
	clear_progress()


static func save_progress(handoff: Dictionary, path: String = PROGRESS_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write campaign progress: %s" % path)
		return false
	var record := handoff.duplicate(true)
	record["schema"] = PROGRESS_SCHEMA
	record["saved_at_unix"] = int(Time.get_unix_time_from_system())
	record["play_seconds"] = play_seconds
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	return true


static func load_progress(path: String = PROGRESS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var record: Dictionary = parsed
	if str(record.get("schema", "")) != PROGRESS_SCHEMA or str(record.get("scenario_path", "")) == "":
		return {}
	if typeof(record.get("carry")) != TYPE_DICTIONARY:
		return {}
	return record


static func clear_progress(path: String = PROGRESS_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 回憶錄 slots: explicit between-battle saves made from the world scroll (儲存回憶錄).
## Each slot holds one progress record (same shape as PROGRESS_PATH) plus a display label;
## the eight-slot count follows the Title031 list art, the file layout is a remake choice.
const MEMOIR_SLOTS := 8


static func memoir_path(slot: int) -> String:
	return "user://memoir_%02d.json" % slot


static func save_memoir(slot: int, record: Dictionary, label: String) -> bool:
	if slot < 0 or slot >= MEMOIR_SLOTS or record.is_empty():
		return false
	var copy := record.duplicate(true)
	copy["memoir_label"] = label
	return save_progress(copy, memoir_path(slot))


static func load_memoir(slot: int) -> Dictionary:
	if slot < 0 or slot >= MEMOIR_SLOTS:
		return {}
	return load_progress(memoir_path(slot))


static func clear_memoir(slot: int) -> void:
	clear_progress(memoir_path(slot))


## One row per slot: {slot, empty, label, saved_at_unix, play_seconds}.
static func memoir_entries() -> Array:
	var entries: Array = []
	for slot in range(MEMOIR_SLOTS):
		var record := load_memoir(slot)
		if record.is_empty():
			entries.append({"slot": slot, "empty": true, "label": "", "saved_at_unix": 0, "play_seconds": 0.0})
		else:
			entries.append({"slot": slot, "empty": false, "label": str(record.get("memoir_label", "")),
				"saved_at_unix": int(record.get("saved_at_unix", 0)), "play_seconds": float(record.get("play_seconds", 0.0))})
	return entries


static func format_play_seconds(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]


static func campaign_entry_for_scenario(campaign_data: Dictionary, scenario_path: String) -> Dictionary:
	for entry_value in campaign_data.get("battles", {}).values():
		if typeof(entry_value) == TYPE_DICTIONARY and str((entry_value as Dictionary).get("scenario", "")) == scenario_path:
			return entry_value
	var world_map: Variant = campaign_data.get("world_map", {})
	if typeof(world_map) == TYPE_DICTIONARY and str((world_map as Dictionary).get("scenario", "")) == scenario_path:
		return world_map
	return {}


## The registered big-map scene (campaign.json world_map), or "" when none.
static func world_map_scenario_path(campaign_data: Dictionary) -> String:
	var world_map: Variant = campaign_data.get("world_map", {})
	return str((world_map as Dictionary).get("scenario", "")) if typeof(world_map) == TYPE_DICTIONARY else ""


## Campaign battles fought by a different party (level 53: 緹娜's escape) neither
## receive nor overwrite the carried party; the incoming carry passes through to
## the next scenario. Remake policy — the original's party state across the
## prologue is not proven.
static func separate_party(campaign_data: Dictionary, scenario_path: String) -> bool:
	return str(campaign_entry_for_scenario(campaign_data, scenario_path).get("party", "")) == "separate"


static func first_scenario_path(campaign_data: Dictionary) -> String:
	## The campaign declares where it starts (`start_level`: the prologue opens at
	## level 51, not at the lowest registered number — level 1 follows level 53).
	var battles: Dictionary = campaign_data.get("battles", {})
	var start := str(campaign_data.get("start_level", ""))
	if start == "" or not battles.has(start):
		push_error("campaign.json must declare start_level as a registered battle key")
		return ""
	return str((battles[start] as Dictionary).get("scenario", ""))


## The registered battle key (level number) of a scenario path, or 0.
static func level_key_for_scenario(campaign_data: Dictionary, scenario_path: String) -> int:
	var battles: Dictionary = campaign_data.get("battles", {})
	for key in battles:
		var entry: Variant = battles[key]
		if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("scenario", "")) == scenario_path:
			return int(str(key))
	return 0


## Whether a level number is a big-map point (campaign.json world_map
## point_level_range, the bigmap.dat ids 1–45): such a level returns to the map
## at its own point when its script sets no next level.
static func level_is_map_point(campaign_data: Dictionary, level: int) -> bool:
	var world_map: Variant = campaign_data.get("world_map", {})
	if typeof(world_map) != TYPE_DICTIONARY:
		return false
	var range_value: Array = (world_map as Dictionary).get("point_level_range", [])
	return range_value.size() == 2 and level >= int(range_value[0]) and level <= int(range_value[1])


## Where a finished scene goes, from its next_level_event [level, event] — the
## original scripts' reading (tools/hsl_big_map_flow.py): `event` is the level
## whose script set runs next (WINFAIL002 "2,55" → STORY055 "2,56" → STORY056
## "2,gameBigMapLevel"), and event == gameBigMapLevel returns to the big map
## standing at point `level`. A battle whose script sets no next level at all
## (WINFAIL001, WINFAIL005) returns to the map at its own point. Returns {} when
## nothing follows; "path" is "" when the target level is not registered.
static func next_destination(campaign_data: Dictionary, loop: Dictionary, scenario_path: String = "") -> Dictionary:
	var next_level: Array = loop.get("next_level_event", [])
	var world_map_path := world_map_scenario_path(campaign_data)
	if next_level.is_empty():
		var own := level_key_for_scenario(campaign_data, scenario_path)
		if world_map_path != "" and own > 0 and level_is_map_point(campaign_data, own):
			return {"kind": "world_map", "path": world_map_path, "point": own, "level": WorldMapRules.BIG_MAP_LEVEL, "default_return": true, "title": "大地圖"}
		return {}
	var event := int(next_level[1]) if next_level.size() > 1 else int(next_level[0])
	if event == WorldMapRules.BIG_MAP_LEVEL:
		if world_map_path == "":
			return {"kind": "world_map", "path": "", "point": int(next_level[0]), "level": event, "title": "大地圖"}
		return {"kind": "world_map", "path": world_map_path, "point": int(next_level[0]), "level": event, "default_return": false, "title": "大地圖"}
	var entry: Dictionary = campaign_data.get("battles", {}).get(str(event), {})
	return {"kind": str(entry.get("kind", "battle")), "path": str(entry.get("scenario", "")), "point": 0, "level": event, "title": str(entry.get("title", ""))}


static func next_scenario_path(campaign_data: Dictionary, loop: Dictionary, scenario_path: String = "") -> String:
	return str(next_destination(campaign_data, loop, scenario_path).get("path", ""))


## 戰場記錄 (mid-battle checkpoints written by the settlement controller): one per battle
## scenario at scenario_save_path. Rows {scenario_path, title, save_path, modified_unix},
## newest first; the newest is what 讀取戰場記錄 / the title's 戰場記錄 resume.
static func battle_record_entries(campaign_data: Dictionary = {}) -> Array:
	var data := campaign_data if not campaign_data.is_empty() else load_campaign()
	var entries: Array = []
	var battles: Dictionary = data.get("battles", {})
	for key in battles:
		var entry: Variant = battles[key]
		if typeof(entry) != TYPE_DICTIONARY or str((entry as Dictionary).get("kind", "battle")) != "battle":
			continue
		var scenario_path := str((entry as Dictionary).get("scenario", ""))
		if scenario_path == "" or not FileAccess.file_exists(scenario_path):
			continue
		var scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string(scenario_path))
		if typeof(scenario) != TYPE_DICTIONARY:
			continue
		var save_path := scenario_save_path(scenario)
		if not FileAccess.file_exists(save_path):
			continue
		entries.append({"scenario_path": scenario_path, "title": str((entry as Dictionary).get("title", "")), "save_path": save_path,
			"modified_unix": int(FileAccess.get_modified_time(save_path))})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified_unix"]) > int(b["modified_unix"]))
	return entries


## Arms a hand-off into the record's battle scenario that loads its checkpoint on boot
## (BattleSettlementController.tick honours load_checkpoint once).
static func queue_battle_record(record: Dictionary) -> Dictionary:
	var saved := load_progress()
	pending = {
		"scenario_path": str(record.get("scenario_path", "")),
		"carry": _carry_of(saved),
		"from_scenario_id": str(saved.get("from_scenario_id", "")),
		"world": _world_of(saved),
		"load_checkpoint": true,
	}
	return pending.duplicate(true)


static func scenario_save_path(scenario: Dictionary) -> String:
	## One checkpoint slot per scenario id (the first battle's is battle_051_cannon_fodder.save).
	return "user://%s.save" % str(scenario.get("id", "battle"))


func _ready() -> void:
	campaign = load_campaign()
	if play_seconds <= 0.0:
		play_seconds = float(load_progress().get("play_seconds", 0.0))
	if runtime.settlement_controller != null:
		runtime.settlement_controller.checkpoint_path = scenario_save_path(runtime.first_battle_scenario)
	call_deferred("_offer_saved_progress")


## A fresh launch of the campaign's first battle with a saved position further
## along offers to resume it: the scene pauses under the prompt until the player
## chooses; the prompt lives on an always-processing layer so it stays clickable.
func _offer_saved_progress() -> void:
	if runtime == null or not runtime.is_inside_tree():
		return
	if str(runtime.startup_mode) != "product_opening" or not last_entry.is_empty() or has_pending():
		return
	if DisplayServer.get_name() == "headless" and not resume_prompt_in_headless:
		return
	if str(runtime.scenario_path) != first_scenario_path(campaign):
		return
	var saved := load_progress()
	if saved.is_empty() or str(saved.get("scenario_path", "")) == str(runtime.scenario_path):
		return
	var entry := campaign_entry_for_scenario(campaign, str(saved.get("scenario_path", "")))
	if entry.is_empty():
		return
	_show_resume_prompt(saved, str(entry.get("title", "")))


func _show_resume_prompt(saved: Dictionary, title: String) -> void:
	resume_layer = CanvasLayer.new()
	resume_layer.name = "CampaignResume"
	resume_layer.layer = 4
	resume_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(resume_layer)
	var dim := ColorRect.new()
	dim.size = Vector2(640, 480)
	dim.color = Color(0, 0, 0, 0.72)
	resume_layer.add_child(dim)
	UISkin.board(resume_layer, "WINDOW50", Vector2(150, 150)).size = Vector2(340, 190)
	var heading := UISkin.label(resume_layer, Vector2(0, 168), 20)
	heading.size = Vector2(640, 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.text = "偵測到戰役進度"
	var info := UISkin.label(resume_layer, Vector2(0, 204))
	info.size = Vector2(640, 26)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "上次進行到：%s" % title
	resume_button = UISkin.button(resume_layer, "繼續 · %s" % title, Vector2(190, 246), Vector2(260, 36))
	resume_button.pressed.connect(resume_saved_progress.bind(saved))
	restart_button = UISkin.button(resume_layer, "從第一戰重新開始", Vector2(190, 290), Vector2(260, 36))
	restart_button.pressed.connect(decline_saved_progress)
	runtime.get_tree().paused = true


## Arms the saved campaign position as the pending hand-off for the next runtime boot
## (the title screen's 戰場記錄 and the in-scene resume prompt share this).
static func queue_resume(saved: Dictionary) -> Dictionary:
	play_seconds = float(saved.get("play_seconds", play_seconds))
	pending = {
		"schema": SCHEMA,
		"scenario_path": str(saved.get("scenario_path", "")),
		"carry": (saved.get("carry", {}) as Dictionary).duplicate(true),
		"from_scenario_id": str(saved.get("from_scenario_id", "")),
		"world": _world_of(saved),
	}
	return pending


func resume_saved_progress(saved: Dictionary) -> void:
	last_handoff = queue_resume(saved)
	_close_resume_prompt()
	if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
		runtime.get_tree().reload_current_scene()


func decline_saved_progress() -> void:
	clear_progress()
	_close_resume_prompt()


func _close_resume_prompt() -> void:
	if runtime.is_inside_tree():
		runtime.get_tree().paused = false
	if resume_layer != null:
		resume_layer.queue_free()
		resume_layer = null
		resume_button = null
		restart_button = null


func _process(delta: float) -> void:
	play_seconds += delta


func prepare_handoff() -> Dictionary:
	var destination := next_destination(campaign, runtime.play_loop, str(runtime.scenario_path))
	var path := str(destination.get("path", ""))
	if path == "":
		return {}
	var loop: Dictionary = runtime.play_loop.duplicate(true)
	loop["scenario_id"] = str(runtime.first_battle_scenario.get("id", ""))
	var carry: Dictionary = CarryRules.capture(loop, campaign.get("carry_policy", CarryRules.DEFAULT_POLICY))
	if separate_party(campaign, str(runtime.scenario_path)):
		carry = CarryRules.pass_level_entry(runtime.campaign_handoff.get("carry", {}), CarryRules.keeps_stamina(loop))
		CarryRules.keep_damage_stream(carry, loop)
	# The script's town / big-map writes (actSetTownExecEvent, actBMSetPointEvent, ...)
	# land in the shared world state here; a first write seeds the state.
	var flow := WorldScriptActions.apply_pending(_world_of(runtime.campaign_handoff), loop, campaign)
	last_world_flow = flow
	if flow.has("error"):
		push_warning("World-flow actions left unapplied: %s" % str(flow["error"]))
	return {
		"schema": SCHEMA,
		"scenario_path": path,
		"carry": carry,
		"from_scenario_id": str(runtime.first_battle_scenario.get("id", "")),
		"world": _placed_world(flow["world"], destination),
	}


## A hand-off into the big map stands the party at the destination point
## (seeding the world state on a first visit); other destinations pass it through.
func _placed_world(world: Dictionary, destination: Dictionary) -> Dictionary:
	if str(destination.get("kind", "")) != "world_map" or int(destination.get("point", 0)) <= 0:
		return world
	var placed := WorldScriptActions.place_party(world, int(destination["point"]), campaign)
	if placed.has("error"):
		push_warning("World state could not place the party at point %d: %s" % [int(destination["point"]), str(placed["error"])])
		return world
	return placed["world"]


## The won battle's leave (BattleSceneRuntime.leave_finished_battle, 0x42cc10's hand-off to
## the winfail win section's next level): the next scenario, the game-clear screen, or — the
## original next level not remade — the chapter end. False when the battle has nowhere to go
## (outside the campaign).
func start_next_battle() -> bool:
	var destination := next_destination(campaign, runtime.play_loop, str(runtime.scenario_path))
	var path := str(destination.get("path", ""))
	if chapter_end_mode or (path == "" and not destination.is_empty() \
			and not campaign_entry_for_scenario(campaign, str(runtime.scenario_path)).is_empty()):
		# The win section names a level the remake has not built (the original enters it): leave
		# for the title (leave_finished_battle) with progress and 戰場記錄 kept, not a silent restart.
		chapter_end_mode = true
		push_warning("Next level %s is not remade; returning to the title" % str(destination.get("level", "")))
		return false
	if str(destination.get("kind", "")) == "game_clear" and path != "":
		_enter_game_clear(path)
		return true
	var handoff := prepare_handoff()
	if handoff.is_empty():
		return false
	last_handoff = handoff
	pending = handoff
	save_progress(handoff)
	if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
		runtime.get_tree().reload_current_scene()
	return true


## Story-only scenes carry the party they received straight through: no battle
## happened, so the incoming carry is the outgoing carry; the scene's recorded
## town / big-map events do reach the world state.
func start_story_handoff(next_path: String, carry: Dictionary, story_records: Array = [], next_level_event: Array = []) -> void:
	if next_path == "":
		return
	var destination := next_destination(campaign, {"next_level_event": next_level_event}, str(runtime.scenario_path))
	# The story was a level entry too: it consumes a kept ST unless it ran actKeepPlayerST itself
	# (STORY057／STORY081).
	var keep := story_records.any(func(row): return row is Dictionary and row.get("kind") == "player_stamina_keep")
	start_world_handoff(next_path, CarryRules.pass_level_entry(carry, keep) if not carry.is_empty() else carry, _placed_world(world_after_story(story_records), destination))


## A battle-opening preview whose player skips the not-yet-remade battle continues
## where the level's winfail win section would have sent a victor (opening.skip_battle,
## static-derived from the seed's WINFAIL): the carried party passes straight through
## (no battle happened, so no rewards, experience or party changes) while the win
## section's town / big-map writes — actSetTownExecEvent, actBMSetPointEvent,
## actBMSetPointEncounterRatio, actBMSetTrackFlag, ... as {name, args} — are applied
## after the scene's own recorded events, as if the battle had been won.
func start_skip_battle_handoff(next_path: String, carry: Dictionary, story_records: Array, world_actions: Array, next_level_event: Array) -> void:
	if next_path == "":
		return
	var destination := next_destination(campaign, {"next_level_event": next_level_event}, str(runtime.scenario_path))
	var world := world_after_story(story_records)
	var flow := WorldScriptActions.apply_actions(world, world_actions, campaign)
	last_world_flow = flow
	if flow.has("error"):
		push_warning("Skipped battle's win-section world actions left unapplied: %s" % str(flow["error"]))
	start_world_handoff(next_path, CarryRules.pass_level_entry(carry, false) if not carry.is_empty() else carry, _placed_world(flow["world"], destination))


## The hand-off world state after a story scene: the carried state with the
## scene's recorded town / big-map events (STORY actBM*/actSetTownExecEvent/actAddTE
## records) applied; a first write seeds the state from the world-map scene.
func world_after_story(story_records: Array) -> Dictionary:
	var flow := WorldScriptActions.apply_story(_world_of(runtime.campaign_handoff), story_records, campaign)
	last_world_flow = flow
	if flow.has("error"):
		push_warning("Story world-flow actions left unapplied: %s" % str(flow["error"]))
	return flow["world"]


## Scene change that also carries the world state (hsl_world_state.v1: current
## big-map point, flag overrides, town trees). Battles and story scenes pass the
## world through with their scripts' recorded writes applied; the big-map scene
## rewrites it as the player travels.
func start_world_handoff(next_path: String, carry: Dictionary, world: Dictionary) -> void:
	if next_path == "":
		return
	var handoff := {
		"schema": SCHEMA,
		"scenario_path": next_path,
		"carry": carry.duplicate(true),
		"from_scenario_id": str(runtime.first_battle_scenario.get("id", "")),
		"world": world.duplicate(true),
	}
	last_handoff = handoff
	pending = handoff
	save_progress(handoff)
	if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
		runtime.get_tree().reload_current_scene()


## The big map persists its position after every arrival so a relaunch resumes
## on the map at that point; the entry hand-off stays the retry baseline. A town
## transaction also passes the rewritten carry (gold / inventories) to persist.
## Where the campaign stands right now (what 儲存回憶錄 saves): the last hand-off record
## when one exists, else the current scenario with its carry and the live big-map state.
func current_progress_record() -> Dictionary:
	if not last_handoff.is_empty():
		return last_handoff.duplicate(true)
	if runtime == null or str(runtime.scenario_path) == "":
		return {}
	var record := {
		"schema": SCHEMA,
		"scenario_path": str(runtime.scenario_path),
		"carry": _carry_of(runtime.campaign_handoff),
		"from_scenario_id": str(runtime.campaign_handoff.get("from_scenario_id", "")),
		"world": _world_of(runtime.campaign_handoff),
	}
	if runtime.world_map_runtime != null and runtime.world_map_runtime.active:
		record["world"] = runtime.world_map_runtime.state.duplicate(true)
	return record


func update_world_state(world: Dictionary, carry: Dictionary = {}) -> void:
	runtime.campaign_handoff["world"] = world.duplicate(true)
	if not carry.is_empty():
		runtime.campaign_handoff["carry"] = carry.duplicate(true)
	if not last_entry.is_empty():
		last_entry["world"] = world.duplicate(true)
		if not carry.is_empty():
			last_entry["carry"] = carry.duplicate(true)
	var record := {
		"schema": SCHEMA,
		"scenario_path": str(runtime.scenario_path),
		"carry": _carry_of(runtime.campaign_handoff),
		"from_scenario_id": str(runtime.campaign_handoff.get("from_scenario_id", "")),
		"world": world.duplicate(true),
	}
	last_handoff = record
	save_progress(record)


static func _world_of(handoff: Dictionary) -> Dictionary:
	var world: Variant = handoff.get("world", {})
	return (world as Dictionary).duplicate(true) if typeof(world) == TYPE_DICTIONARY else {}


static func _carry_of(handoff: Dictionary) -> Dictionary:
	var carry: Variant = handoff.get("carry", {})
	return (carry as Dictionary).duplicate(true) if typeof(carry) == TYPE_DICTIONARY else {}


## Chapter end without a next scenario: forget the campaign state and reload the
## scene, which re-enters the project's default first battle.
## A battle whose winfail names the game-clear entry (actSetNextPlayLevelEvent N,998 — a
## sequel's final battle; chapter 1 reaches 998 only through STORY082) ends the campaign from
## its battle end the way BattleOpeningCoordinator._enter_game_clear ends a story scene:
## the auto-saved position is cleared, the controlled party is the GameClear showcase.
func _enter_game_clear(path: String) -> void:
	var clear_script: Script = load(path.get_basename() + ".gd")
	if clear_script != null:
		clear_script.set("showcase", _battle_showcase())
	reset_campaign()
	last_handoff = {"schema": SCHEMA, "scenario_path": path, "kind": "game_clear"}
	pending = {}
	if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
		runtime.get_tree().change_scene_to_file(path)


## The fielded controlled units with the roster face table's portrait and name.
func _battle_showcase() -> Array:
	var portraits := ContentPaths.actor_portraits()
	var members: Array = []
	for unit_value in runtime.play_loop.get("units", []):
		var unit: Dictionary = unit_value
		if str(unit.get("battle_actor_role", "")) != "player_controlled":
			continue
		var row: Dictionary = portraits.get(ActorSpriteKey.row_key(unit, portraits), {})
		members.append({"actor_id": str(unit.get("actor_id", "")), "name": str(row.get("name", unit.get("id", ""))), "portrait": str(row.get("res_path", ""))})
	return members


func restart_campaign() -> void:
	reset_campaign()
	last_handoff = {}
	if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
		runtime.get_tree().reload_current_scene()


func summary() -> Dictionary:
	return {
		"schema": SCHEMA,
		"campaign_loaded": not campaign.is_empty(),
		"next_scenario_path": next_scenario_path(campaign, runtime.play_loop) if runtime != null else "",
		"chapter_end_mode": chapter_end_mode,
		"pending": pending.duplicate(true),
		"last_handoff_scenario": str(last_handoff.get("scenario_path", "")),
		"saved_progress_scenario": str(load_progress().get("scenario_path", "")),
		"saved_world_point": int(_world_of(load_progress()).get("current_point", 0)),
		"world_flow_applied": int(last_world_flow.get("applied", 0)),
		"resume_prompt_visible": resume_layer != null,
	}

extends Node
## Scenario-driven opening presentation for battles whose scenario carries an
## `opening` config and a compiled STORY timeline (the scenario's
## `resources.opening_timeline`, e.g. battle_052.json).
##
## The coordinator owns only the timeline cursor, the autoplay clock and
## presentation bookkeeping. Unit positions, factions and the turn queue stay in
## BattlePlayLoop; actor nodes are moved for presentation and snapped back to
## their PlayLoop cells when player control begins.
##
## The same handlers replay a fired winfail status' result chain mid-battle or at
## the outcome (start_cutscene; scenario_rules.status_timelines): the runtime pauses
## while the cutscene runs and resumes turn presentation afterwards.
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: static-derived docs/evidence_packets/static_reverse/second_battle_opening_script.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_walk_path.md
##   rules: remake-invented
##     (confirm outside dialogue fast-forwards walks and scrolls under OPT-PACE 快／極快 only — the original has no skip)
##   rules: provisional
##     (cutscene resume semantics)
##   layout: resource-derived content/imported/hsl/chapter01/battle052/opening_timeline.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   strings: resource-derived content/imported/hsl/chapter01/message_text_evidence.json
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##     (4 px per tick default walk)
##   audio: resource-derived content/imported/hsl/chapter01/scripts
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##     (PlayMusic restarts the track from the top, −1 keeps the current one; the track is resolved at generation)

const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const OpeningSelectPrompt = preload("res://game/battle/runtime/opening/OpeningSelectPrompt.gd")
const OpeningEndCard = preload("res://game/battle/runtime/opening/OpeningEndCard.gd")
const OpeningStoryObjects = preload("res://game/battle/runtime/opening/OpeningStoryObjects.gd")
const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const BattleWinFailBoard = preload("res://game/battle/scene/BattleWinFailBoard.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const UISkin = preload("res://game/common/BattleUISkin.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")

const SUMMARY_SCHEMA := "hsl_battle_opening_coordinator.v1"
## Pacing in original ticks (16 ms). Tests may shorten these before start(); the product
## keeps the defaults. Walks: 0x453b90 state 0x32 maps the script speed argument through
## the 0x4543d8 table — 1 → 1 px per tick, 2／3 → 2, 8 → 8, 0／4／other → 4 — so
## `walk_pixels_per_second` is the speed-4 rate and `walk_pixels_per_tick(speed)` scales it.
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const DEFAULT_WALK_SPEED := 4.0
const WALK_PIXELS_PER_TICK := {1: 1.0, 2: 2.0, 3: 2.0, 8: 8.0}
## actShowSectionName (original_tick_counts.md §2): 1 + 51 + 56 + 51 ticks in, a 320-tick hold
## that a key ([0x4c6390] & 0x600010) or click ([0x4c6398] & 0x10002) ends early, 51 + 51 + 1
## ticks out — 582 ticks unskipped, 263 when the first hold tick takes a key. The remake plays
## the same sub-states (OpeningCinematics steps them and draws the band and name) and lets any
## key or mouse button end the hold (any key／any button is the remake reading of the two
## input masks).
const SECTION_TITLE_IN_TICKS := 159
const SECTION_TITLE_HOLD_TICKS := 320
const SECTION_TITLE_OUT_TICKS := 103
const SECTION_TITLE_TICKS := SECTION_TITLE_IN_TICKS + SECTION_TITLE_HOLD_TICKS + SECTION_TITLE_OUT_TICKS
var walk_pixels_per_second := DEFAULT_WALK_SPEED * OriginalTick.TICKS_PER_SECOND
var delay_token_seconds := OriginalTick.TICK_SECONDS
var default_step_seconds := OriginalTick.TICK_SECONDS
var title_seconds := OriginalTick.seconds(SECTION_TITLE_TICKS)


var runtime: Node
var active := false
var config: Dictionary = {}
var bindings: Dictionary = {}
var wait_remaining := 0.0
var step_count := 0
var last_transition: Dictionary = {}
var motion_records: Array[Dictionary] = []
var status_tokens: Dictionary = {"win": [], "fail": [], "event": [], "dead_message": {}, "board_visible": false}
var sound_records: Array[Dictionary] = []
## actShowWinFailStatus board (BattleWinFailBoard, created on first use under the runtime UI).
var winfail_board: Control
var camera_records: Array[Dictionary] = []
var skipped_records: Array[Dictionary] = []
var _inserted_unit_ids: Array[String] = []
var _script_sounds: Dictionary = {}
var _sound_player: AudioStreamPlayer = null
## Story-only scenes (level_kind == "story"): the cast is spawned from story_actors,
## walks are forward script motion from EVEF pixels, and the scene ends with a
## campaign hand-off instead of first player control.
var story_mode := false
var story_finished := false
var next_level_event: Array = []
var story_records: Array[Dictionary] = []
## The current token holds the timeline until actor motion ends: only the Wait variants of
## the walk tokens (and actWaitPlayer) do, as the original VM parks on the walker's +0x50
## pointer (0x453b90 state 0x32 sub 7); a plain walk lets the next token run at once, so
## chained plain walks with short actDelays move together. `_blocking_unit_id` names the
## walker the Wait form waits for ("" = any actor motion).
var _blocking_motion := true
var _blocking_unit_id := ""
var _pending_deletes: Array[String] = []
## A Wait walk sets off only once the camera is centred on its walker (0x453b90 state 0x32 sub 0:
## 0x43bf30(actor, 0) every tick until it returns 1); `_pending_walk` starts it after the scroll.
var _pending_walk := Callable()
var _pending_walk_seconds := 0.0
## Story cast, inserts, walks, deletes, shapes, story-object sprites and markers.
var story_objects: RefCounted = OpeningStoryObjects.create(self)
## Section title, dark screen, film, camera and cutscene entry／exit (OpeningCinematics).
var cinematics: RefCounted = OpeningCinematics.create(self)
## Not-remade card choices (opening.skip_battle previews): [{id, label, path}] with
## the highlighted row; empty when the card has its single confirm only. The card
## controls and the hand-offs its rows trigger live in OpeningEndCard.
var end_card_options: Array[Dictionary] = []
var end_card_selected := 0
var end_card: RefCounted = OpeningEndCard.create(self)
## EndingDispatchRules.route of the hand-off world state when the card offered an
## end route ({} otherwise); summary() exposes it as end_route_decision.
var end_route_decision: Dictionary = {}
## The actEnterStorageWindow event whose 整理裝備 screen is up; the timeline holds
## until the player closes it (summary storage_window_open).
var _storage_window_event_id := ""
## Open actSelectInsertEvent prompt: [{message_id, text, event_code}] with the highlighted
## row; empty when no choice is pending. The prompt controls live in OpeningSelectPrompt.
var select_options: Array[Dictionary] = []
var select_selected := 0
var select_prompt: RefCounted = OpeningSelectPrompt.create(self)
## Script cutscene: a fired winfail status' result chain (scenario_rules.status_timelines)
## replayed with the opening handlers while the battle waits; see start_cutscene.
var cutscene_mode := false
var cutscene_key := ""
var cutscene_records: Array[Dictionary] = []
var _cutscene_finishing := false
## Extended STORY tokens that tools/hsltools/levels/timeline.py names but the
## remake does not act on yet (unit state, win/fail edits, town/big-map tables, random
## inserts, flow flags...) or that level assembly pre-bakes into the roster
## (player_mode_set → battle.py role_overrides; inserted_object_adjust_level →
## battle.py trace_opening script_insert.adjust_level, born by InitialRosterGrowthRules;
## player_level_adjust_all → battle.py opening_birth.adjust_all_level, the opcode 73
## re-adjust InitialRosterGrowthRules applies). They are
## kept in story_records with status recorded_no_handler, so no token is silently
## skipped; tools/test_hsl_story_token_coverage.py checks every compiler kind appears
## in this file.
const RECORD_ONLY_KINDS: Array[String] = [
	"inserted_object_adjust_level",
	"actor_move", "actor_move_wait",
	"actor_move_disp", "actor_shape_change_wait", "actor_use_shape_wait", "actor_walk_to_actor_disp",
	"actor_walk_to_actor_disp_wait", "actor_wait_round", "inserted_object_id_change",
	"inserted_object_fly_flag", "inserted_object_stamina", "inserted_object_equip", "inserted_player_wait",
	"story_object_insert_wait", "story_object_insert_wait_position",
	"story_object_insert_x_range", "random_object_insert",
	"position_actor_delete_x_range", "position_object_proc_code_change", "system_arrive_position_random",
	"player_undead_flag", "player_mode_set",
	"player_exec_mode", "player_fix_position", "player_walk_shape", "player_fly_flag",
	"player_no_attack_flag", "player_position_random0", "player_name_set", "player_id_change",
	"player_code_delete", "player_stamina_keep", "player_level_adjust_all", "player_job_up_process",
	"item_use", "item_grant", "win_status_disable", "fail_status_disable",
	"event_status_disable", "win_status_replace", "fail_status_replace", "event_status_replace",
	"winfail_process_exec", "earthquake", "double_page_mode",
	"walk_sound_mode", "round_disp_detect", "script_over", "demo",
	"next_level_get_over_event", "game_over_flag", "game_over_score_add",
	"town_exec_event", "town_exit_exec_event", "town_event_add", "town_event_delete",
	"bigmap_walk_to_point", "bigmap_walker_player_id", "bigmap_point_mode", "bigmap_track_mode",
	"bigmap_point_flag_set", "bigmap_track_flag_set", "bigmap_point_flag_clear", "bigmap_track_flag_clear",
	"bigmap_point_event", "bigmap_point_encounter_ratio", "bigmap_show_track_point",
]

## Compiled STORY kind → handler method of _apply_event (each takes event, kind, args). A kind
## missing here is recorded when it is in RECORD_ONLY_KINDS, otherwise skipped (skipped_records).
## BattleScriptCoordinator overrides _apply_event and _wait_bound_actor; handlers are called by
## name, so overrides still apply.
const EVENT_HANDLERS := {
	"background_object_target": &"_ev_camera_object_target",
	"camera_object_target": &"_ev_camera_object_target",
	"opening_music": &"_ev_music",
	"music_track": &"_ev_music",
	"default_level_music": &"_ev_music",
	"opening_delay": &"_ev_opening_delay",
	"dialogue_message_id": &"_ev_dialogue_message_id",
	"actor_walk_disp_wait": &"_ev_actor_walk_disp_wait",
	"sound_effect": &"_ev_sound_effect",
	"object_insert": &"_ev_object_insert",
	"inserted_object_wait_round": &"_ev_inserted_object_wait_round",
	"inserted_object_walk_disp_wait": &"_ev_inserted_object_walk_disp_wait",
	"inserted_object_walk_disp": &"_ev_inserted_object_walk_disp",
	"dead_message_registration": &"_ev_dead_message_registration",
	"section_title_resource": &"_ev_section_title_resource",
	"win_status_enable": &"_ev_win_status_enable",
	"fail_status_enable": &"_ev_fail_status_enable",
	"event_status_enable": &"_ev_event_status_enable",
	"winfail_board_refresh": &"_ev_winfail_board_refresh",
	"actor_walk_wait": &"_ev_actor_walk_wait",
	"actor_walk": &"_ev_actor_walk",
	"actor_walk_and_delete": &"_ev_actor_walk_and_delete",
	"actor_walk_and_delete_wait": &"_ev_actor_walk_and_delete_wait",
	"actor_walk_disp": &"_ev_actor_walk_disp",
	"actor_walk_follow": &"_ev_actor_walk_follow",
	"actor_walk_follow_wait": &"_ev_actor_walk_follow_wait",
	"story_object_insert": &"_ev_story_object_insert",
	"screen_darken": &"_ev_screen_darken",
	"next_level_event": &"_ev_next_level_event",
	"camera_position_target": &"_ev_camera_position_target",
	"actor_shape_change": &"_ev_actor_shape_change",
	"actor_shape_restore": &"_ev_actor_shape_restore",
	"actor_move_disp_wait": &"_ev_actor_move_disp_wait",
	"show_position_marker": &"_ev_show_position_marker",
	"show_position_marker_clear": &"_ev_show_position_marker_clear",
	# Extended opening/presentation tokens (see EXTENDED_TOKENS in the compiler).
	"camera_position_set": &"_ev_camera_position_set",
	"camera_position_target_speed": &"_ev_camera_position_target_speed",
	"actor_delete": &"_ev_actor_delete",
	"position_object_delete": &"_ev_position_object_delete",
	# actSetRandomPos family (STORY037's guardian beats): slots in table order.
	"random_position_set": &"_ev_random_position_set",
	"camera_random_position_target": &"_ev_camera_random_position_target",
	"random_position_object_delete": &"_ev_random_position_object_delete",
	"story_object_insert_random_position": &"_ev_story_object_insert_random_position",
	"object_insert_random_position": &"_ev_object_insert_random_position",
	"dialogue_message_if_exist": &"_ev_dialogue_message_if_exist",
	"shape_message": &"_ev_shape_message",
	"event_select_insert": &"_ev_event_select_insert",
	"actor_action_wait": &"_ev_actor_action_wait",
	"screen_darken_clear": &"_ev_screen_darken_clear",
	"movie_play": &"_ev_movie_play",
	"storage_window_enter": &"_ev_storage_window_enter",
	"level_up_star_insert": &"_ev_level_up_star_insert",
}


## px per tick for a script walk speed argument (0x4543d8 table); 0 and unknown values walk
## at the default 4.
static func walk_pixels_per_tick(speed_arg: int) -> float:
	return float(WALK_PIXELS_PER_TICK.get(speed_arg, DEFAULT_WALK_SPEED))


func _ready() -> void:
	_load_script_sounds()
	story_objects._load_shape_sets()


func _load_script_sounds() -> void:
	## Decoded actPlaySound resources (tools/hsltools/levels/sounds.py). Missing manifests
	## keep the explicit not_imported_skipped record instead of failing the opening.
	_script_sounds = {}
	if runtime == null:
		return
	var manifest_path := str((runtime.first_battle_scenario.get("resources", {}) as Dictionary).get("script_sounds", ""))
	if manifest_path == "" or not FileAccess.file_exists(manifest_path):
		return
	var parsed = ContentPaths.read_json(manifest_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_script_sounds = (parsed as Dictionary).get("sounds", {})


func _play_script_sound(resource_token: String) -> String:
	var row: Dictionary = _script_sounds.get(resource_token, {})
	var res_path := str(row.get("res_path", ""))
	if res_path == "" or not ResourceLoader.exists(res_path):
		return "not_imported_skipped"
	var stream: AudioStream = load(res_path)
	if stream == null:
		return "load_failed_skipped"
	if _sound_player == null:
		_sound_player = AudioStreamPlayer.new()
		_sound_player.name = "OpeningScriptSound"
		_sound_player.volume_db = -4.0
		add_child(_sound_player)
	_sound_player.stream = stream
	_sound_player.play()
	return "played"


func start() -> Dictionary:
	if runtime == null or runtime.scene_timeline == null:
		push_error("BattleOpeningCoordinator needs a runtime with a compiled scene timeline")
		return summary()
	config = (runtime.first_battle_scenario.get("opening", {}) as Dictionary).duplicate(true)
	bindings = (config.get("actor_bindings", {}) as Dictionary).duplicate(true)
	active = true
	step_count = 0
	last_transition = {}
	motion_records = []
	sound_records = []
	camera_records = []
	skipped_records = []
	status_tokens = {"win": [], "fail": [], "event": [], "dead_message": {}, "board_visible": false}
	runtime.runtime_entrypoint = runtime.ENTRYPOINT_PRODUCT_OPENING
	runtime.scene_timeline.reset()
	runtime.opening_timeline_mode = "opening"
	runtime.interaction_state = Interaction.OPENING_TIMELINE
	runtime.menus.set_action_menu_visible(false)
	runtime.overlays.set_move_overlay_visible(false)
	runtime.opening_overlay.clear_message()
	story_mode = runtime.is_story_scene()
	story_finished = false
	next_level_event = []
	story_records = []
	end_card_options = []
	end_card_selected = 0
	select_options = []
	select_selected = 0
	_pending_deletes = []
	_blocking_motion = true
	cinematics._ensure_title()
	if story_mode:
		story_objects._spawn_story_actors()
	else:
		story_objects._prepare_actor_positions()
		# Opening-only cast (STORY053: 緹娜 who walks off before the player slot is
		# installed) exists beside the PlayLoop roster and never joins the grid map.
		story_objects._spawn_story_actors()
	_apply_event(runtime.scene_timeline.current_event())
	return summary()


## Plays a fired winfail status' result chain with the opening handlers
## (OpeningCinematics.start_cutscene); the runtime and tests address it here.
func start_cutscene(status_key: String, events: Array) -> Dictionary:
	return cinematics.start_cutscene(status_key, events)


func tick(delta: float) -> void:
	if not active:
		return
	cinematics._fade_title(delta)
	_settle_pending_deletes()
	var departure = runtime.get_node_or_null("DepartureView") if cutscene_mode and not story_mode else null
	var fading: bool = departure != null and departure.busy()
	if _cutscene_finishing:
		# Non-blocking walk-and-delete at the end of a chain: let the actors leave
		# before handing the scene back.
		if not runtime.has_actor_motion() and _pending_deletes.is_empty() and not fading:
			cinematics._finish_cutscene()
		return
	if story_finished or cinematics._movie != null or _storage_window_event_id != "":
		return
	var event: Dictionary = runtime.scene_timeline.current_event()
	if str(event.get("kind", "")) == "dialogue_message_id" or not select_options.is_empty():
		return
	# actShowWinFailStatus waits on the board (0x450840 case 0x1f → 0x407320).
	if str(event.get("kind", "")) == "winfail_board_refresh" and winfail_board != null and winfail_board.busy():
		return
	if _pending_walk.is_valid():
		_pending_walk_seconds -= maxf(delta, 0.0)
		if _pending_walk_seconds <= 0.0:
			_flush_pending_walk()
		return
	wait_remaining -= maxf(delta, 0.0)
	if wait_remaining <= 0.0 and (not _blocking_motion or not _blocking_busy()) and not fading:
		advance("automatic_stage")


## Runs `start_walk` after `seconds` of camera scroll (at once when 0).
func _defer_walk(seconds: float, start_walk: Callable) -> void:
	_flush_pending_walk()
	if seconds <= 0.0:
		start_walk.call()
		return
	_pending_walk = start_walk
	_pending_walk_seconds = seconds


func _flush_pending_walk() -> void:
	if _pending_walk.is_valid():
		var start_walk := _pending_walk
		_pending_walk = Callable()
		_pending_walk_seconds = 0.0
		start_walk.call()


## A Wait token holds the timeline until `unit_id` ("" = every actor) stops walking.
func _block_on(unit_id: String) -> void:
	_blocking_motion = true
	_blocking_unit_id = unit_id


func _blocking_busy() -> bool:
	if _blocking_unit_id != "":
		var actor: Node = runtime.actor_node_for_unit(_blocking_unit_id)
		return actor != null and actor.is_moving()
	return runtime.has_actor_motion()


func handle_input(event: InputEvent) -> void:
	if not active:
		return
	if cinematics._movie != null:
		cinematics._movie.handle_input(event)
		return
	if _storage_window_event_id != "":
		return  # the runtime routes input to the equipment screen while it is up
	if story_finished:
		end_card.handle_input(event)
		return
	if not select_options.is_empty():
		select_prompt._handle_select_input(event)
		return
	var kind := str(runtime.scene_timeline.current_event().get("kind", ""))
	if kind == "winfail_board_refresh" and winfail_board != null and winfail_board.busy():
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and not event.echo):
			winfail_board.dismiss()
		return
	if kind == "section_title_resource":
		if event is InputEventMouseButton and event.pressed:
			skip_section_title("mouse_button")
		elif event is InputEventKey and event.pressed and not event.echo:
			skip_section_title("key")
		return
	if kind != "dialogue_message_id":
		# OPT-PACE (docs/OPTIONS.md), read on each confirm: 原版 walks and scrolls play out (the
		# original has no skip here); 快／極快 fast-forward them.
		if _is_confirm(event) and not GameOptions.is_original("OPT-PACE"):
			fast_forward_motion("left_click" if event is InputEventMouseButton else "key_confirm")
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance("left_click")
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		advance("key_confirm")


static func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)


## Confirm (Enter/Space/left click) outside dialogue skips ahead: every walking actor lands
## on its walk's end, a running camera scroll lands on its target and the current token's
## remaining wait is cut to one tick (remake-invented: the original has no skip here; the
## script's order and every landing cell stay the same). Returns the actors landed.
func fast_forward_motion(trigger: String) -> int:
	if not active or story_finished:
		return 0
	_flush_pending_walk()
	var landed := 0
	for actor in runtime.actors_root.get_children():
		if actor is ActorRuntime and actor.is_moving() and not actor.last_path.is_empty():
			actor.move_along([actor.last_path[actor.last_path.size() - 1]], 0.0)
			actor.play_state("idle", "0")
			landed += 1
	if runtime.camera_controller != null:
		runtime.camera_controller.finish_scroll()
	wait_remaining = minf(wait_remaining, default_step_seconds)
	story_records.append({"kind": "motion_fast_forward", "trigger": trigger, "actors_landed": landed, "event_kind": str(runtime.scene_timeline.current_event().get("kind", ""))})
	return landed


## Ends the section title's 320-tick hold early (original sub-state 4 on a key or click):
## the next hold tick takes the input and the 103-tick exit follows, so the wait becomes the
## rest of the current tick, that hold tick and the exit. Input during the entry ramps or the
## exit is ignored, as in the original. Returns whether the hold was cut; records the cut in
## story_records (`section_title_skip`, hold ticks including the one that takes the input).
func skip_section_title(trigger: String) -> bool:
	if not active or str(runtime.scene_timeline.current_event().get("kind", "")) != "section_title_resource":
		return false
	if not cinematics.title_hold_accepts_input():
		return false
	var done: int = cinematics.title_ticks_done()
	var elapsed := title_seconds - wait_remaining
	wait_remaining = maxf(OriginalTick.seconds(done + 1 + SECTION_TITLE_OUT_TICKS) - elapsed, OriginalTick.seconds(SECTION_TITLE_OUT_TICKS))
	cinematics._skip_title_hold()
	story_records.append({"kind": "section_title_skip", "source_event_id": str(runtime.scene_timeline.current_event().get("id", "")),
		"trigger": trigger, "held_ticks": done + 1 - SECTION_TITLE_IN_TICKS})
	return true


func advance(trigger: String = "confirm") -> Dictionary:
	if not active:
		return summary()
	var timeline = runtime.scene_timeline
	if str(timeline.current_event().get("kind", "")) == "dialogue_message_id" and runtime.opening_overlay.advance_page():
		return summary()
	_finish_winfail_board()
	_flush_pending_walk()
	last_transition = timeline.advance(trigger)
	step_count += 1
	var current: Dictionary = timeline.current_event()
	if cutscene_mode:
		if timeline.is_finished():
			_cutscene_finishing = true
			wait_remaining = 0.0
		else:
			_apply_event(current)
		return summary()
	if str(current.get("kind", "")) == "scene_end_marker" or (story_mode and (timeline.is_finished() or str(current.get("kind", "")) == "first_control_marker")):
		# A story scene built from a battle opening (opening preview) stops where
		# player control would start; without a next scenario it shows the end card.
		_finish_story(str(current.get("id", "scene_end_ready")))
	elif str(current.get("kind", "")) == "first_control_marker" or timeline.is_finished():
		_finish(str(current.get("id", "first_control_ready")))
	else:
		_apply_event(current)
	return summary()


func summary() -> Dictionary:
	var event: Dictionary = runtime.scene_timeline.current_event() if runtime != null and runtime.scene_timeline != null else {}
	return {
		"schema": SUMMARY_SCHEMA,
		"active": active,
		"source_script": str(config.get("source_script", "")),
		"current_event_id": str(event.get("id", "")),
		"current_event_kind": str(event.get("kind", "")),
		"step_count": step_count,
		"wait_remaining": wait_remaining,
		"motion_count": motion_records.size(),
		"inserted_unit_ids": _inserted_unit_ids.duplicate(),
		"status_tokens": status_tokens.duplicate(true),
		"sound_records": sound_records.duplicate(true),
		"story_mode": story_mode,
		"story_finished": story_finished,
		"next_level_event": next_level_event.duplicate(),
		"story_records": story_records.duplicate(true),
		"end_card_options": end_card_options.duplicate(true),
		"end_card_selected": end_card_selected,
		"end_route_decision": end_route_decision.duplicate(true),
		"storage_window_open": _storage_window_event_id != "",
		"select_options": select_options.duplicate(true),
		"select_selected": select_selected,
		"camera_records": camera_records.duplicate(true),
		"skipped_records": skipped_records.duplicate(true),
		"cutscene_mode": cutscene_mode,
		"cutscene_key": cutscene_key,
		"cutscene_records": cutscene_records.duplicate(true),
		"last_transition": last_transition.duplicate(true),
		"claim_limit": "Compiled STORY token order with explicit remake pacing; original delay units, walk paths, camera curves and handler side effects are not proven.",
	}


func binding_for_token(actor_token: String, instance: String) -> Dictionary:
	return bindings.get("%s/%s" % [actor_token, instance], {})


func _apply_event(event: Dictionary) -> void:
	var kind := str(event.get("kind", ""))
	var args: Array = event.get("args", [])
	wait_remaining = default_step_seconds
	_blocking_motion = false
	_blocking_unit_id = ""
	cinematics._set_title_visible(kind == "section_title_resource")
	if kind != "dialogue_message_id":
		runtime.opening_overlay.clear_message()
	if cutscene_mode and bool(event.get("cutscene_skip", false)):
		# Already applied to the PlayLoop by WinfailScenarioRules (statuses, inserts,
		# hand-off, carry): keep the chain order, play nothing.
		story_records.append({"kind": kind, "source_event_id": str(event.get("id", "")), "status": "applied_by_winfail_interpreter"})
		wait_remaining = 0.0
		return
	if EVENT_HANDLERS.has(kind):
		call(EVENT_HANDLERS[kind], event, kind, args)
	elif kind in RECORD_ONLY_KINDS:
		story_records.append({"kind": kind, "source_event_id": str(event.get("id", "")), "args": args.duplicate(), "params": (event.get("params", {}) as Dictionary).duplicate(true), "status": "recorded_no_handler"})
	else:
		skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": kind})


## background_object_target／camera_object_target.
func _ev_camera_object_target(event: Dictionary, kind: String, _args: Array) -> void:
	cinematics._focus_camera_on_token(event, kind == "camera_object_target")


## opening_music／music_track／default_level_music.
func _ev_music(event: Dictionary, kind: String, _args: Array) -> void:
	story_records.append({"kind": kind, "source_event_id": str(event.get("id", "")), "track": int(event.get("track", -1)),
		"status": play_music_stream(runtime.get_node("BattleMusic"), str(event.get("stream", "")))})


func _ev_opening_delay(_event: Dictionary, _kind: String, args: Array) -> void:
	wait_remaining = float(str(args[0]).to_int()) * delay_token_seconds if not args.is_empty() else default_step_seconds


func _ev_dialogue_message_id(event: Dictionary, _kind: String, _args: Array) -> void:
	_show_dialogue(event)


func _ev_actor_walk_disp_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._start_walk(event)


func _ev_sound_effect(event: Dictionary, _kind: String, args: Array) -> void:
	var resource_token := str(args[0]) if not args.is_empty() else ""
	sound_records.append({
		"source_event_id": str(event.get("id", "")),
		"resource": resource_token,
		"status": _play_script_sound(resource_token),
	})


func _ev_object_insert(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._insert_object(event)


func _ev_inserted_object_wait_round(_event: Dictionary, _kind: String, args: Array) -> void:
	if not story_objects._pending_insert.is_empty() and not args.is_empty():
		story_objects._pending_insert["wait_round"] = str(args[0]).to_int()


func _ev_inserted_object_walk_disp_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_inserted_object(event, true)


func _ev_inserted_object_walk_disp(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_inserted_object(event, false)


func _ev_dead_message_registration(event: Dictionary, _kind: String, args: Array) -> void:
	status_tokens["dead_message"] = {
		"actor_token": str(args[0]) if args.size() > 0 else "",
		"message_id": str(args[2]) if args.size() > 2 else "",
		"source_event_id": str(event.get("id", "")),
	}


func _ev_section_title_resource(_event: Dictionary, _kind: String, _args: Array) -> void:
	wait_remaining = title_seconds


func _ev_win_status_enable(_event: Dictionary, _kind: String, args: Array) -> void:
	_append_token(status_tokens["win"], args)


func _ev_fail_status_enable(_event: Dictionary, _kind: String, args: Array) -> void:
	_append_token(status_tokens["fail"], args)


func _ev_event_status_enable(_event: Dictionary, _kind: String, args: Array) -> void:
	_append_token(status_tokens["event"], args)


func _ev_winfail_board_refresh(event: Dictionary, _kind: String, _args: Array) -> void:
	status_tokens["board_visible"] = true
	_show_winfail_board(event)


func _ev_actor_walk_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_absolute(event, true, false)


func _ev_actor_walk(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_absolute(event, false, false)


func _ev_actor_walk_and_delete(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_absolute(event, false, true)


func _ev_actor_walk_and_delete_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_absolute(event, true, true)


func _ev_actor_walk_disp(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_relative(event, false)


func _ev_actor_walk_follow(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_follow(event, false)


func _ev_actor_walk_follow_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._walk_follow(event, true)


func _ev_story_object_insert(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._insert_story_object(event)


func _ev_screen_darken(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._darken_screen(event)


func _ev_next_level_event(event: Dictionary, kind: String, args: Array) -> void:
	next_level_event = []
	for value in args.slice(0, 2):
		# TYPE.H gameBigMapLevel: "N,gameBigMapLevel" returns to the big map at point N.
		next_level_event.append(WorldMapRules.BIG_MAP_LEVEL if str(value) == "gameBigMapLevel" else str(value).to_int())
	story_records.append({"kind": kind, "source_event_id": str(event.get("id", "")), "next_level_event": next_level_event.duplicate()})


func _ev_camera_position_target(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._scroll_camera_to_position(event)


func _ev_actor_shape_change(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._change_shape(event)


func _ev_actor_shape_restore(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._restore_shape(event)


func _ev_actor_move_disp_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._move_disp(event)


func _ev_show_position_marker(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._show_position_marker(event)


func _ev_show_position_marker_clear(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._clear_position_markers(event)


func _ev_camera_position_set(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._set_camera_to_position(event)


func _ev_camera_position_target_speed(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._scroll_camera_to_position_speed(event)


func _ev_actor_delete(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._delete_bound_actor(event)


func _ev_position_object_delete(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._delete_position_objects(event)


func _ev_random_position_set(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._set_random_slots(event)


func _ev_camera_random_position_target(event: Dictionary, _kind: String, _args: Array) -> void:
	var slot_event: Dictionary = story_objects.random_slot_event(event, false)
	if not slot_event.is_empty():
		cinematics._scroll_camera_to_position(slot_event)


func _ev_random_position_object_delete(event: Dictionary, _kind: String, _args: Array) -> void:
	var delete_event: Dictionary = story_objects.random_slot_event(event, false)
	if not delete_event.is_empty():
		story_objects._delete_position_objects(delete_event)


func _ev_story_object_insert_random_position(event: Dictionary, _kind: String, _args: Array) -> void:
	var story_event: Dictionary = story_objects.random_slot_event(event, true)
	if not story_event.is_empty():
		story_objects._insert_story_object(story_event)


func _ev_object_insert_random_position(event: Dictionary, _kind: String, _args: Array) -> void:
	story_objects._insert_random_object(event)


func _ev_dialogue_message_if_exist(event: Dictionary, _kind: String, _args: Array) -> void:
	_show_dialogue_if_exist(event)


func _ev_shape_message(event: Dictionary, _kind: String, _args: Array) -> void:
	_show_shape_message(event)


func _ev_event_select_insert(event: Dictionary, _kind: String, _args: Array) -> void:
	select_prompt._show_select_prompt(event)


func _ev_actor_action_wait(event: Dictionary, _kind: String, _args: Array) -> void:
	_wait_bound_actor(event)


func _ev_screen_darken_clear(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._clear_dark_screen(event)


func _ev_movie_play(event: Dictionary, _kind: String, _args: Array) -> void:
	cinematics._play_movie(event)


func _ev_storage_window_enter(event: Dictionary, _kind: String, _args: Array) -> void:
	_enter_storage_window(event)


func _ev_level_up_star_insert(event: Dictionary, _kind: String, _args: Array) -> void:
	_record_level_up_star(event)


## Opens the win／fail board over the scene: in an opening with the labels of the statuses the
## script armed so far (its tokens and the loop's), in a winfail chain with the loop's.
func _show_winfail_board(event: Dictionary) -> void:
	if runtime.play_loop.is_empty():
		story_records.append({"kind": "winfail_board", "source_event_id": str(event.get("id", "")), "status": "no_battle"})
		return
	if winfail_board == null:
		winfail_board = BattleWinFailBoard.new()
		winfail_board.hold_ticks = BattleWinFailBoard.automation_hold_ticks()
		runtime.get_node("UI").add_child(winfail_board)
	var tokens: Dictionary = {} if cutscene_mode else status_tokens
	var view = runtime.get_node("BattlePresentation")
	var rows: Dictionary = BattleWinFailBoard.rows_for(runtime.play_loop, tokens, view._board_label)
	winfail_board.show_rows(rows)
	story_records.append({"kind": "winfail_board", "source_event_id": str(event.get("id", "")), "status": "shown", "rows": rows.duplicate(true)})


func _finish_winfail_board() -> void:
	if winfail_board != null and winfail_board.busy():
		winfail_board.finish()


func _append_token(target: Array, args: Array) -> void:
	if not args.is_empty() and not target.has(str(args[0])):
		target.append(str(args[0]))


func _show_dialogue(event: Dictionary) -> void:
	var args: Array = event.get("args", [])
	if event.has("face_member"):
		# actShapeMessage resolved by _show_shape_message: named line with a script face.
		var face_body := str(event.get("message_text", runtime.message_text_evidence.get("messages", {}).get(str(event.get("message_id", "")), "")))
		if face_body == "":
			skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "shape_message", "reason": "missing_text"})
			return
		runtime.opening_overlay.show_face_message(str(event.get("id", "")), str(event.get("speaker_name", "")), face_body, str(event.get("face_member", "")))
		return
	var token := str(event.get("actor_token", ""))
	var instance := str(args[1]) if args.size() > 1 else "1"
	var binding := binding_for_token(token, instance)
	var actor_id := str(binding.get("actor_id", ""))
	var speaker := str(event.get("speaker_name", runtime.message_text_evidence.get("speaker_names", {}).get(token, token)))
	var body := str(event.get("message_text", runtime.message_text_evidence.get("messages", {}).get(str(event.get("message_id", "")), "")))
	if bool(event.get("narration", false)) and body != "":
		runtime.opening_overlay.show_narration(str(event.get("id", "")), body)
		return
	if actor_id == "" or body == "":
		skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "dialogue_message_id", "reason": "missing_binding_or_text"})
		return
	var unit_id := str(binding.get("unit_id", ""))
	cinematics._focus_camera_on_unit(unit_id, false, str(event.get("id", "")))
	var speaker_node: Node = runtime.actor_node_for_unit(unit_id)
	runtime.opening_overlay.set_speaker_actor(speaker_node)
	runtime.opening_overlay.show_message(str(event.get("id", "")), speaker, body, actor_id)


func _settle_pending_deletes() -> void:
	## actWalkAndDelete: the actor leaves the scene once its walk finishes.
	var remaining: Array[String] = []
	for unit_id in _pending_deletes:
		var actor: Node = runtime.actor_node_for_unit(unit_id)
		if actor != null and actor.is_moving():
			remaining.append(unit_id)
			continue
		if actor != null:
			# Both VMs' walk-and-delete enter state 0x36 (0x450450), whose end is the 16-level
			# engMIX fade (original_script_entry.md); story walks fade the same way.
			var departure = runtime.get_node_or_null("DepartureView")
			if departure != null and story_mode and actor is Node2D: departure.fade(unit_id, actor)
			elif departure == null or not cutscene_mode or not departure.begin(unit_id): actor.visible = false
		story_records.append({"kind": "actor_deleted", "unit_id": unit_id})
	_pending_deletes = remaining


## PlayMusic(n) (original_music.md §1). The event's stream is resolved at generation: music_track
## N, opening_music the level's table track, default_level_music the table track of its argument.
## An empty stream is track −1 and leaves the current track playing; any other track starts from
## the top, even the one already playing. Imported OGGs loop whole (project.godot importer_defaults).
static func play_music_stream(player: AudioStreamPlayer, stream_path: String) -> String:
	if stream_path == "":
		return "unchanged"
	if not ResourceLoader.exists(stream_path):
		return "not_imported_skipped"
	player.stream = load(stream_path)
	player.play()
	return "played"


## The development seam skips the opening: the music is what its last music action left (a film
## stops it, OpeningCinematics._start_movie). A track already playing is not restarted.
static func resume_skipped_music(player: AudioStreamPlayer, events: Array) -> void:
	var target := ""
	for event_value in events:
		var event: Dictionary = event_value if typeof(event_value) == TYPE_DICTIONARY else {}
		var kind := str(event.get("kind", ""))
		if kind == "first_control_marker" or kind == "scene_end_marker":
			break
		if kind == "movie_play":
			target = ""
		elif kind in ["opening_music", "music_track", "default_level_music"] and str(event.get("stream", "")) != "":
			target = str(event["stream"])
	if target == "":
		player.stop()
	elif not player.playing or player.stream == null or player.stream.resource_path != target:
		play_music_stream(player, target)


func _finish_story(source_event_id: String) -> void:
	## Scene end: hand the carried party to the campaign's next scenario when it
	## exists; otherwise show the chapter-end card and wait for a confirm to restart.
	story_finished = true
	cinematics._set_title_visible(false)
	runtime.opening_overlay.clear_message()
	cinematics._kill_camera_tween()
	runtime.opening_timeline_mode = "scene_end"
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	var next_path := ""
	var destination: Dictionary = {}
	if progress != null and not next_level_event.is_empty():
		destination = progress.next_destination(progress.campaign, {"next_level_event": next_level_event}, str(runtime.scenario_path))
		next_path = str(destination.get("path", ""))
	story_records.append({"kind": "scene_end", "source_event_id": source_event_id, "next_level_event": next_level_event.duplicate(), "next_scenario_path": next_path})
	if str(destination.get("kind", "")) == "game_clear" and next_path != "":
		_enter_game_clear(next_path, source_event_id)
		return
	if next_path != "" and progress != null:
		progress.start_story_handoff(next_path, runtime.campaign_handoff.get("carry", {}), story_records, next_level_event)
		return
	end_card._show_end_card()


## actSetNextPlayLevelEvent 90,998 (STORY082 / winfail059 / 079): the GameClear
## sequence. The campaign is over — its auto-saved position is cleared (memoirs
## and battle records stay) and the ending scene takes over, returning to the title.
func _enter_game_clear(next_path: String, source_event_id: String) -> void:
	story_records.append({"kind": "game_clear", "source_event_id": source_event_id, "scene": next_path})
	var clear_script: Script = load(next_path.get_basename() + ".gd")
	if clear_script != null:
		clear_script.set("showcase", _game_clear_showcase())
		var resources: Dictionary = runtime.first_battle_scenario.get("resources", {})
		clear_script.set("combat_animation_path", BattleScenario.resource_path(runtime.first_battle_scenario, "combat_animation") if resources.has("combat_animation") else "")
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress != null:
		progress.reset_campaign()
	runtime.get_tree().change_scene_to_file(next_path)


## actEnterStorageWindow (STORY057 / STORY081 before the finals, winfail045 / 078 win
## paths): the party's last chance to re-arrange equipment — 0x450840 case 0x8b calls the
## same 0x42ab40(0, …) as the world scroll's 整理裝備, so both open the runtime's
## PartyEquipmentScreen (the shared status window's mode 0). The
## timeline holds until the screen closes; its carry write-back is the runtime's
## (BattleSceneMenus._on_party_equipment_closed), so the following hand-off carries the changes. A
## screen that cannot open (no carried party) is closed again and only recorded.
func _enter_storage_window(event: Dictionary) -> void:
	var screen: Node = runtime.party_equipment_screen
	if screen == null:
		story_records.append({"kind": "storage_window_enter", "source_event_id": str(event.get("id", "")), "status": "recorded_no_handler"})
		return
	var result: Dictionary = runtime.menus.open_party_equipment()
	if not bool(result.get("ok", false)):
		screen.close()
		story_records.append({"kind": "storage_window_enter", "source_event_id": str(event.get("id", "")), "status": "skipped_" + str(result.get("error", "unopened"))})
		return
	_storage_window_event_id = str(event.get("id", ""))
	screen.closed.connect(_on_storage_window_closed, CONNECT_ONE_SHOT)
	story_records.append({"kind": "storage_window_enter", "source_event_id": _storage_window_event_id, "status": "opened"})


func _on_storage_window_closed(_next_carry: Dictionary, changes: int) -> void:
	story_records.append({"kind": "storage_window_enter", "source_event_id": _storage_window_event_id, "status": "closed", "changes": changes})
	_storage_window_event_id = ""
	wait_remaining = 0.0


func _record_level_up_star(event: Dictionary) -> void:
	## The native helper only requests an effect/sound; no dedicated level-up star
	## sprite is part of the current remake asset contract. Keep the token visible
	## in records rather than silently dropping a battle event.
	story_records.append({"kind": "level_up_star_insert", "source_event_id": str(event.get("id", "")), "args": (event.get("args", []) as Array).duplicate(), "status": "skipped_no_level_up_star_sprite"})


## The nine GameClear party slots (defProcClearShowPlayer, original_game_clear.md): each party
## member of the finale's loop by its base actor id 001–009, with the 0x42b2b0 status-sheet values
## (the status page's live figures) and its job row for the combat shape; the screen shows
## 此角色未加入隊伍 for a slot with no member. Revive counts are not tracked (0).
func _game_clear_showcase() -> Array:
	var members: Array = []
	var actors: Dictionary = UISkin.data().get("actors", {})
	for unit_value in runtime.play_loop.get("units", []):
		if not unit_value is Dictionary:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("battle_actor_role", "")) != "player_controlled":
			continue
		var actor_id := str(unit.get("actor_id", ""))
		var row: Dictionary = actors.get(ActorSpriteKey.row_key(unit, actors), actors.get(actor_id, {}))
		var profile := CoreCombatRules.combat_profile_from_unit(unit)
		members.append({"actor_id": actor_id, "joined": true, "sprite_actor_id": ActorSpriteKey.resolve(unit), "sheet": {
			"name": str(unit.get("display_name", row.get("name", actor_id))), "title": str(unit.get("title", row.get("title", ""))),
			"race": str((actors.get(actor_id, {}) as Dictionary).get("race", "")), "str": int(profile.get("str", 0)), "dex": int(profile.get("dex", 0)),
			"mind": int(profile.get("mind", 0)), "con": int(profile.get("con", 0)), "attack": int(profile.get("live_attack_damage", 0)),
			"defense": int(profile.get("live_defense", 0)), "magic": int(profile.get("live_magic_attack", 0)), "move": int(unit.get("move_point", 0)),
			"speed": int(unit.get("live_speed", 0)), "level": int(unit.get("level", 1)), "max_hp": int(unit.get("max_hp", 0)),
			"max_mp": int(unit.get("max_mp", 0)), "kills": int(unit.get("kill_count", 0)), "revives": 0}})
	return members


## Card row selection／confirm (OpeningEndCard); kept on the coordinator for tests and support fixtures.
func select_end_card_option(index: int) -> Dictionary:
	return end_card.select_end_card_option(index)


func confirm_end_card_option() -> Dictionary:
	return end_card.confirm_end_card_option()


func _finish(source_event_id: String) -> void:
	# A formal battle can still have a story-side choice before first control
	# (level 900 choice one). Its selected branch writes the map destination and
	# must hand off like a story scene; choice two has no next-level token and
	# enters the battle normally.
	if not story_mode and not cutscene_mode and not next_level_event.is_empty():
		_finish_story(source_event_id)
		return
	active = false
	cinematics._set_title_visible(false)
	runtime.opening_overlay.clear_message()
	cinematics._kill_camera_tween()
	_finish_winfail_board()
	for unit_id in runtime.unit_grid_coords.keys():
		var actor: Node = runtime.actor_node_for_unit(str(unit_id))
		if actor == null:
			continue
		actor.move_along([runtime.actor_world_position_for_grid(runtime.unit_grid_coords[unit_id])], 0.0)
		actor.play_state("idle", "0")
		actor.visible = true
	runtime.opening_timeline_mode = "first_control"
	runtime.enter_first_control_state(source_event_id)


## Resolves the open actSelectInsertEvent prompt (OpeningSelectPrompt.choose_select_option).
func choose_select_option(index: int) -> Dictionary:
	return select_prompt.choose_select_option(index)


## --- Extended opening/presentation tokens -----------------------------------
## Handlers below cover the STORY tokens the compiler maps in EXTENDED_TOKENS whose
## semantics follow directly from existing handlers. Every value is a remake reading
## (provisional): view anchors, the speed unit, the position selector radius and the
## existence test are not proven against the original engine.


func _show_shape_message(event: Dictionary) -> void:
	## actShapeMessage,<face shape>,<name id>,<message id>: a line spoken under a
	## script-named face and a name resource id (STORY063's spies, 306 = ???), with
	## no cast binding. Rewritten in the timeline as a dialogue_message_id carrying
	## face_member / speaker_name so the shared confirm / paging path applies; the
	## record notes whether the face shape is imported (portrait manifest shape_faces).
	var args: Array = event.get("args", [])
	var face_member := str(args[0]) if not args.is_empty() else ""
	var name_id := str(args[1]) if args.size() > 1 else ""
	var messages: Dictionary = runtime.message_text_evidence.get("messages", {})
	var speaker := str(messages.get(name_id, name_id))
	var resolved: Dictionary = event.duplicate(true)
	resolved["kind"] = "dialogue_message_id"
	resolved["resolved_from_kind"] = "shape_message"
	resolved["face_member"] = face_member
	resolved["speaker_name"] = speaker
	var timeline = runtime.scene_timeline
	if timeline.current_index >= 0 and timeline.current_index < timeline.events.size():
		timeline.events[timeline.current_index] = resolved
	story_records.append({"kind": "shape_message", "source_event_id": str(event.get("id", "")), "face_member": face_member, "name_id": name_id, "speaker": speaker, "message_id": str(event.get("message_id", "")), "face_imported": runtime.opening_overlay.has_face(face_member), "status": "resolved_to_dialogue"})
	_show_dialogue(resolved)


func _show_dialogue_if_exist(event: Dictionary) -> void:
	## actMessageIfExist,code,serial,true_id,false_id,check_number,check codes...:
	## spoken by [code][serial]; shows true_id when every checked unit (instance 1 of
	## each listed code, or the speaker itself when the list is empty) has a live,
	## visible actor, otherwise false_id (0 = nothing). The resolved message is
	## written back into the timeline as an ordinary dialogue_message_id so the shared
	## confirm/paging path applies; the record keeps the branch that was taken.
	var args: Array = event.get("args", [])
	var params: Dictionary = event.get("params", {})
	var speaker_token := str(event.get("actor_token", ""))
	var checks: Array = (params.get("check_player_codes", []) as Array).duplicate()
	if checks.is_empty():
		checks = [speaker_token]
	var checked: Array[String] = []
	var exists := true
	for code in checks:
		var token := str(code)
		var instance := str(args[1]) if token == speaker_token and args.size() > 1 else "1"
		var binding := binding_for_token(token, instance)
		var actor: Node = runtime.actor_node_for_unit(str(binding.get("unit_id", "")))
		checked.append(token)
		if actor == null or not actor.visible:
			exists = false
	var message_id := str(event.get("message_id", "")) if exists else str(event.get("message_id_false", ""))
	var record := {"kind": "dialogue_message_if_exist", "source_event_id": str(event.get("id", "")), "speaker_token": speaker_token, "checked_tokens": checked, "exists": exists, "message_id": message_id}
	if message_id == "" or message_id == "0":
		record["status"] = "no_message_for_branch"
		story_records.append(record)
		return
	var resolved: Dictionary = event.duplicate(true)
	resolved["kind"] = "dialogue_message_id"
	resolved["message_id"] = message_id
	resolved["resolved_from_kind"] = "dialogue_message_if_exist"
	resolved["exists"] = exists
	if not exists:
		if event.has("message_text_false"):
			resolved["message_text"] = event["message_text_false"]
		else:
			resolved.erase("message_text")
	var timeline = runtime.scene_timeline
	if timeline.current_index >= 0 and timeline.current_index < timeline.events.size():
		timeline.events[timeline.current_index] = resolved
	record["status"] = "resolved_to_dialogue"
	story_records.append(record)
	_show_dialogue(resolved)


func _wait_bound_actor(event: Dictionary) -> void:
	## actWaitPlayer,code,serial: hold the queue until the bound actor's scripted
	## motion ends. tick() already blocks on actor motion while _blocking_motion is
	## true; this token turns a preceding non-blocking walk into an explicit wait and
	## records whether the actor was still moving (the original wait scope is unresolved).
	var bound: Array = story_objects._bound_actor(event, 0)
	var unit_id: String = bound[0]
	var actor: Node = bound[1]
	if actor == null:
		skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_action_wait", "reason": "unbound_actor"})
		return
	_block_on(unit_id)
	wait_remaining = default_step_seconds
	story_records.append({"kind": "actor_action_wait", "source_event_id": str(event.get("id", "")), "unit_id": unit_id, "was_moving": actor.is_moving()})

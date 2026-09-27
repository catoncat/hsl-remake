extends RefCounted
## Screen-level presentation for BattleOpeningCoordinator: the section title card, the
## story dark screen (actDarkScreen／actDeleteDarkScreen), the film over the scene
## (actPlayMovie／skip-battle win film), the camera (object／position targets, per-tick
## scrolls) and the script-cutscene entry／exit (start_cutscene／_finish_cutscene:
## timeline swap around a fired winfail chain). Bodies moved from the coordinator
## unchanged; the coordinator keeps the timeline cursor, cutscene_mode／cutscene_key／
## cutscene_records (summary()), the pacing values and camera_records. Camera anchors put the
## framed point at the view's (320, 192) as 0x43bf30 does; scroll ticks and the title card's sub-states, blends and
## placement are static readings (every level's actShowSectionName plays through here).
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   layout: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_tick_counts.md
##     (user recording 27.6–31.9 s: whole screen darkens, band settles centred on y 240, 棄卒 name 161 px wide at 1×)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (recording 212.45 s: a framed unit stands at (320,192))
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: provisional
##     (dark level n: 0x4699fd floors each 565 channel to c·(16−n)／16; black alpha n／16 is that ratio at 8 bits)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##     (§3.4: the film player stops the music and nothing resumes it)

const SceneTimeline = preload("res://game/battle/runtime/SceneTimeline.gd")
const MoviePlayer = preload("res://game/title/MoviePlayer.gd")

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
## actDarkScreen (opcode 48, 0x452102 → 0x43e2a0) inserts obj_ScreenDarker (700) with no VM
## wait; its process 0x43e2d0 raises the dark level [0x4c1ca8] by one every 3 ticks (+0x94 =
## 0x30003) from 0 to 16, then holds. actDeleteDarkScreen (opcode 49, 0x452123 → 0x43e270) sets
## 0x10000, again with no wait: the level falls by one every 3 ticks to 0 and the object deletes.
const DARK_SCREEN_LEVELS := 16
const DARK_SCREEN_TICKS_PER_LEVEL := 3
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
## actShowSectionName (opcode 12, original_tick_counts.md §2): 0x452f32 steps sub-state
## +0x8c once per tick and then draws two layers at the view's (0x140, 0xf0):
## - layer 0x32, the SHAPE\LEVELSEC.SHP band (+0x9e level): mode 0x2000000 (0x22000000 below
##   level 16, | 0x8000000 while zoomed) = pixel kind 10／11, `dst − src` saturated per RGB565
##   channel with src scaled by level／16; zoom x 1.0, zoom y [0x4c1d34] (16.16);
## - layer 0x33, the level's WORD name (+0x9a level): mode 0 (opaque) at level 16, 0x20000000
##   (cross-fade `src·level／16 + dst·(16 − level)／16`) below it; no zoom.
## Level ramps reload their 3-tick counter and test the level *before* stepping it, so a
## ramp takes 16 × 3 + 3 = 51 ticks; sub-state 6 ends when the band level reaches 0 (zoom
## then 7.375, not 8.0).
const TITLE_DRAW_CENTRE := Vector2(320, 240)
const TITLE_BAND_ASSET := "LEVELSEC"
const TITLE_LEVEL_MAX := 16
const TITLE_LEVEL_PERIOD := 3
const TITLE_HOLD_TICKS := 320
const TITLE_ZOOM_ONE := 0x10000
const TITLE_ZOOM_START := 0x80000
const TITLE_ZOOM_STEP := 0x2000
## After sub-state 7's tick (+0x8c = 0) the VM has moved on: the title is over.
const TITLE_SUB_DONE := 8
## Script camera scrolls (actScrollBGToPos／ToObject, 0x43bf30): each tick moves the view by
## the signed distance halved, clamped to ±step, and snaps when both axes are within 4; the
## step is 16 px while the story bit 0x4c1b00 & 0x4000000 is set (32 otherwise, +12 fast-forward).
const SCROLL_STEP_MAX := 16
const SCROLL_TOLERANCE := 4

var coordinator: Node
var runtime: Node:
	get:
		return coordinator.runtime
var _title: Control
var _title_band: TextureRect
var _title_name: TextureRect
var _title_elapsed := 0.0
## The card's 0x452f32 state (section_title_new_state) and the ticks stepped so far.
var _title_state: Dictionary = {}
## A key／click reached the hold (skip_section_title): the next sub-state 4 tick takes it.
var _title_skip_pending := false
var _dark_fade: Tween
var _dark_screen: ColorRect
## The film playing over the scene (actPlayMovie / a skipped battle's win-section film);
## the timeline and the card wait for it. Null when no film plays.
var _movie: CanvasLayer
var _after_movie: Callable
var _cutscene_saved_timeline: RefCounted = null
var _cutscene_saved_mode := ""


static func create(opening_coordinator: Node) -> RefCounted:
	var cinematics := new()
	cinematics.coordinator = opening_coordinator
	return cinematics


## The state 0x452f32 starts from (sub-state 0 initialises it on the first tick).
static func section_title_new_state() -> Dictionary:
	return {"sub": 0, "tick": 0, "band_level": 0, "name_level": 0, "zoom": TITLE_ZOOM_START, "counter": TITLE_LEVEL_PERIOD, "hold": TITLE_HOLD_TICKS}


## One original tick of 0x452f32 (in place). `input` is the key／click test of sub-state 4
## ([0x4c6390] & 0x600010 or [0x4c6398] & 0x10002); no other sub-state reads input.
static func section_title_step(state: Dictionary, input: bool) -> void:
	var sub := int(state["sub"])
	if sub == TITLE_SUB_DONE:
		return
	state["tick"] = int(state["tick"]) + 1
	match sub:
		0:
			state["band_level"] = 0
			state["name_level"] = 0
			state["hold"] = TITLE_HOLD_TICKS
			state["counter"] = TITLE_LEVEL_PERIOD
			state["zoom"] = TITLE_ZOOM_START
			state["sub"] = 1
		1, 3:
			var key := "band_level" if sub == 1 else "name_level"
			if _title_counter_expired(state):
				if int(state[key]) >= TITLE_LEVEL_MAX:
					state["sub"] = sub + 1
				else:
					state[key] = int(state[key]) + 1
		2:
			state["zoom"] = int(state["zoom"]) - TITLE_ZOOM_STEP
			if int(state["zoom"]) <= TITLE_ZOOM_ONE:
				state["zoom"] = TITLE_ZOOM_ONE
				state["sub"] = 3
		4:
			state["hold"] = int(state["hold"]) - 1
			if int(state["hold"]) < 1 or input:
				state["sub"] = 5
		5:
			if _title_counter_expired(state):
				if int(state["name_level"]) == 0:
					state["sub"] = 6
				else:
					state["name_level"] = int(state["name_level"]) - 1
		6:
			state["zoom"] = mini(int(state["zoom"]) + TITLE_ZOOM_STEP, TITLE_ZOOM_START)
			if _title_counter_expired(state):
				if int(state["band_level"]) == 0:
					state["sub"] = 7
				else:
					state["band_level"] = int(state["band_level"]) - 1
		7:
			state["sub"] = TITLE_SUB_DONE


## The 3-tick counter of the level ramps (+0xa4, reload +0xa6): true on the reload tick.
static func _title_counter_expired(state: Dictionary) -> bool:
	state["counter"] = int(state["counter"]) - 1
	if int(state["counter"]) >= 1:
		return false
	state["counter"] = TITLE_LEVEL_PERIOD
	return true


## Per-tick section title card (coordinator.tick): steps 0x452f32 once per elapsed original
## tick and shows the result.
func _fade_title(delta: float) -> void:
	if _title == null or not _title.visible:
		return
	_title_elapsed += delta
	var due := int(floor(OriginalTick.ticks(_title_elapsed) + 0.0001))
	while int(_title_state["tick"]) < due and int(_title_state["sub"]) != TITLE_SUB_DONE:
		var holding := int(_title_state["sub"]) == 4
		section_title_step(_title_state, holding and _title_skip_pending)
		if holding and _title_skip_pending:
			_title_skip_pending = false
	apply_section_title_state(_title, _title_state)


## Whether a key／click now would reach the hold (sub-state 4 still running, not yet cut).
func title_hold_accepts_input() -> bool:
	return _title != null and _title.visible and int(_title_state.get("sub", 0)) == 4 and not _title_skip_pending


## Ticks the card has stepped since it appeared.
func title_ticks_done() -> int:
	return int(_title_state.get("tick", 0))


## The coordinator cut the title's hold (skip_section_title): the next hold tick takes the
## input and the exit sub-states follow.
func _skip_title_hold() -> void:
	_title_skip_pending = true


## The card's two layers under one full-view Control: the LEVELSEC band (subtractive,
## stretched vertically about its origin) and the WORD name (alpha = level／16), both
## placed by their SHP origin on TITLE_DRAW_CENTRE. Every WORD*.SHP has its origin at
## (width ÷ 2, height ÷ 2) rounded down (resource-derived, all 46 in the PAK), so the name's
## origin is taken from its size.
static func build_section_title_view(name_texture: Texture2D, band_texture: Texture2D, band_origin: Vector2) -> Control:
	var view := Control.new()
	view.name = "OpeningSectionTitle"
	view.size = Vector2(640, 480)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := TextureRect.new()
	band.name = "SectionTitleBand"
	band.texture = band_texture
	band.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.position = TITLE_DRAW_CENTRE - band_origin
	band.pivot_offset = band_origin
	var subtract := CanvasItemMaterial.new()
	subtract.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	band.material = subtract
	view.add_child(band)
	var title_name := TextureRect.new()
	title_name.name = "SectionTitleName"
	title_name.texture = name_texture
	title_name.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	title_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_size := name_texture.get_size()
	title_name.position = TITLE_DRAW_CENTRE - Vector2(floorf(name_size.x / 2.0), floorf(name_size.y / 2.0))
	view.add_child(title_name)
	apply_section_title_state(view, section_title_new_state())
	return view


## Shows a 0x452f32 state on a build_section_title_view view: a layer at level 0 is not drawn.
static func apply_section_title_state(view: Control, state: Dictionary) -> void:
	var band: TextureRect = view.get_node("SectionTitleBand")
	var title_name: TextureRect = view.get_node("SectionTitleName")
	var band_level := int(state["band_level"])
	var name_level := int(state["name_level"])
	band.visible = band_level > 0
	band.modulate.a = float(band_level) / TITLE_LEVEL_MAX
	band.scale = Vector2(1.0, float(int(state["zoom"])) / TITLE_ZOOM_ONE)
	title_name.visible = name_level > 0
	title_name.modulate.a = float(name_level) / TITLE_LEVEL_MAX


## Ticks the original's scroll helper needs from `from` to `to` (both axes converge in
## the same calls), converted to seconds (the timeline wait of a blocking scroll).
static func camera_scroll_seconds(from: Vector2, to: Vector2) -> float:
	var current := Vector2i(from.round())
	var target := Vector2i(to.round())
	var ticks := 0
	while (absi(target.x - current.x) > SCROLL_TOLERANCE or absi(target.y - current.y) > SCROLL_TOLERANCE) and ticks < 4096:
		var difference := target - current
		current += Vector2i(clampi(difference.x >> 1, -SCROLL_STEP_MAX, SCROLL_STEP_MAX), clampi(difference.y >> 1, -SCROLL_STEP_MAX, SCROLL_STEP_MAX))
		ticks += 1
	return OriginalTick.seconds(ticks + 1)


## Stops a running camera scroll (scene end／first control／cutscene exit).
func _kill_camera_tween() -> void:
	if runtime != null and runtime.camera_controller != null:
		runtime.camera_controller.stop_scroll()


## Starts the story-phase 0x43bf30 glide (BattleCameraController, step 16) and returns its
## seconds as camera_scroll_seconds counts them.
func _scroll_camera(target: Vector2) -> float:
	var seconds := camera_scroll_seconds(runtime.camera.position, target)
	runtime.camera_controller.scroll_to(target, SCROLL_STEP_MAX, SCROLL_TOLERANCE)
	return seconds


func start_cutscene(status_key: String, events: Array) -> Dictionary:
	## Plays the result chain of a winfail status the interpreter just fired
	## (precompiled by hsltools.levels.scenario.status_timelines into scenario_rules.status_timelines):
	## messages, delays, walks / walk-and-delete, camera, sounds and story objects in
	## script order with the opening handlers and remake pacing. Events flagged
	## cutscene_skip were already applied to the loop by WinfailScenarioRules and are
	## only recorded. The runtime pauses AI playback, menus and the battle end while
	## the cutscene is coordinator.active and resumes through _on_script_cutscene_finished.
	if runtime == null or coordinator.active:
		return coordinator.summary()
	var playable := 0
	for event in events:
		if typeof(event) == TYPE_DICTIONARY and not bool((event as Dictionary).get("cutscene_skip", false)):
			playable += 1
	if playable == 0:
		return coordinator.summary()
	coordinator.config = (runtime.first_battle_scenario.get("opening", {}) as Dictionary).duplicate(true)
	coordinator.bindings = (coordinator.config.get("actor_bindings", {}) as Dictionary).duplicate(true)
	var formal_timelines: Dictionary = (runtime.first_battle_scenario.get("scenario_rules", {}) as Dictionary).get("status_timelines", {})
	if not formal_timelines.is_empty():
		coordinator.config["select_event_timelines"] = formal_timelines
	_cutscene_saved_timeline = runtime.scene_timeline
	_cutscene_saved_mode = runtime.opening_timeline_mode
	runtime.scene_timeline = SceneTimeline.from_events(events)
	runtime.opening_timeline_mode = "script_cutscene"
	coordinator.active = true
	coordinator.cutscene_mode = true
	coordinator.cutscene_key = status_key
	coordinator._cutscene_finishing = false
	coordinator.story_mode = false
	coordinator.story_finished = false
	coordinator.step_count = 0
	coordinator.last_transition = {}
	var cleared_deletes: Array[String] = []
	coordinator._pending_deletes = cleared_deletes
	coordinator._blocking_motion = true
	runtime.menus.set_action_menu_visible(false)
	runtime.overlays.set_move_overlay_visible(false)
	runtime.opening_overlay.clear_message()
	coordinator.cutscene_records.append({
		"status_key": status_key,
		"event_count": events.size(),
		"playable_event_count": playable,
		"turn": int(runtime.play_loop.get("turn", 0)),
		"battle_outcome": BattleOutcome.of(runtime.play_loop),
		"finished": false,
	})
	coordinator._apply_event(runtime.scene_timeline.current_event())
	return coordinator.summary()


func _finish_cutscene() -> void:
	coordinator.active = false
	coordinator.cutscene_mode = false
	coordinator._cutscene_finishing = false
	_set_title_visible(false)
	runtime.opening_overlay.clear_message()
	_kill_camera_tween()
	coordinator._finish_winfail_board()
	runtime.scene_timeline = _cutscene_saved_timeline
	runtime.opening_timeline_mode = _cutscene_saved_mode
	_cutscene_saved_timeline = null
	var key: String = coordinator.cutscene_key
	coordinator.cutscene_key = ""
	if not coordinator.cutscene_records.is_empty():
		coordinator.cutscene_records[coordinator.cutscene_records.size() - 1]["finished"] = true
	runtime.on_script_cutscene_finished(key)


func _focus_camera_on_token(event: Dictionary, scroll: bool) -> void:
	var args: Array = event.get("args", [])
	var token := str(event.get("actor_token", ""))
	var instance := str(args[1]) if args.size() > 1 else "1"
	var binding: Dictionary = coordinator.binding_for_token(token, instance)
	var seconds := _focus_camera_on_unit(str(binding.get("unit_id", "")), scroll, str(event.get("id", "")))
	if scroll:
		coordinator.wait_remaining = seconds


## Returns the scroll's seconds (0 for a cut or an unbound unit). The actor's point goes where
## 0x43bf30 frames an object, the view's (320, 192) (BattleCameraController.focus_centre).
## actScrollBGToObject (scroll, VM case 0x14 → 0x13 stage 0) first rounds the point to its cell
## centre `(v & ~0x1f) + 0x10`; actSetBGToObject (case 0x15, 0x43bf30(obj, 1)) and the remake's
## dialogue and pre-walk cuts use the point as it is.
func _focus_camera_on_unit(unit_id: String, scroll: bool, source_event_id: String) -> float:
	if unit_id == "" or runtime.camera_controller == null:
		return 0.0
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	var anchor: Vector2 = actor.position if actor != null else runtime.actor_world_position_for_grid(runtime.unit_grid_coords.get(unit_id, Vector2i.ZERO))
	if scroll:
		anchor = Vector2(float((int(anchor.x) & ~0x1f) + 0x10), float((int(anchor.y) & ~0x1f) + 0x10))
	var target: Vector2 = runtime.camera_controller.clamped_position(BattleCameraController.focus_centre(anchor))
	var seconds := 0.0
	if scroll:
		seconds = _scroll_camera(target)
	else:
		runtime.camera_controller.snap_to(target)
	coordinator.camera_records.append({"source_event_id": source_event_id, "unit_id": unit_id, "target": target, "scroll": scroll, "duration_seconds": seconds})
	return seconds


## 0x43bf30(actor, 0) for a Wait walk: the walker's own pixel (no cell rounding) eased to the
## view's script focus at the story step; returns the scroll seconds (0 when already there).
func _centre_camera_on_walker(unit_id: String, source_event_id: String) -> float:
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	if actor == null or runtime.camera_controller == null:
		return 0.0
	var target: Vector2 = runtime.camera_controller.clamped_position(BattleCameraController.focus_centre(actor.position))
	var seconds := 0.0
	if runtime.camera.position.round() != target.round():
		seconds = _scroll_camera(target)
	coordinator.camera_records.append({"source_event_id": source_event_id, "unit_id": unit_id, "target": target, "scroll": true, "walk_centre": true, "duration_seconds": seconds})
	return seconds


func _scroll_camera_to_position(event: Dictionary) -> void:
	## actScrollBGToPos,x,y: the cell centre of (x,y) is scrolled to the view's script
	## focus (see script_position_camera_centre); the centre is clamped to the map.
	var args: Array = event.get("args", [])
	if args.size() < 2 or runtime.camera_controller == null:
		return
	var target: Vector2 = runtime.camera_controller.clamped_position(script_position_camera_centre(args, true))
	var seconds := _scroll_camera(target)
	coordinator.wait_remaining = seconds
	coordinator.camera_records.append({"source_event_id": str(event.get("id", "")), "unit_id": "", "position_args": [str(args[0]).to_int(), str(args[1]).to_int()], "target": target, "scroll": true, "duration_seconds": seconds})


func _darken_screen(event: Dictionary) -> void:
	## Dark level n draws as black alpha n／16. The original (0x4699fd, op 4 over the all-black
	## shape [0x4bbb4e]) writes floor(c·(16−n)／16) per 565 channel: the same linear ratio, only
	## the 5／6-bit truncation differs (original_tick_counts.md §5).
	if _dark_screen == null:
		_dark_screen = ColorRect.new()
		_dark_screen.name = "StoryDarkScreen"
		_dark_screen.color = Color(0, 0, 0, 0)
		_dark_screen.size = Vector2(640, 480)
		_dark_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ui: Node = runtime.get_node("UI")
		ui.add_child(_dark_screen)
		ui.move_child(_dark_screen, 0)
	var seconds := _step_dark_screen(DARK_SCREEN_LEVELS)
	coordinator.story_records.append({"kind": "screen_darken", "source_event_id": str(event.get("id", "")), "seconds": seconds})


## Steps the dark level from its current value to `to_level`, one level per 3 ticks; returns
## the seconds the fade takes. The script runs on meanwhile (neither token waits).
func _step_dark_screen(to_level: int) -> float:
	if _dark_fade != null and _dark_fade.is_valid():
		_dark_fade.kill()
	var from_level := roundi(_dark_screen.color.a * DARK_SCREEN_LEVELS)
	var levels := absi(to_level - from_level)
	var seconds := OriginalTick.seconds(levels * DARK_SCREEN_TICKS_PER_LEVEL)
	if levels == 0:
		return 0.0
	var direction := signi(to_level - from_level)
	_dark_fade = coordinator.create_tween()
	_dark_fade.tween_method(func(elapsed: float) -> void:
		var steps := mini(int(floor(elapsed / OriginalTick.TICK_SECONDS + 0.001)) / DARK_SCREEN_TICKS_PER_LEVEL, levels)
		_dark_screen.color = Color(0, 0, 0, float(from_level + steps * direction) / DARK_SCREEN_LEVELS), 0.0, seconds, seconds)
	return seconds


## actPlayMovie: the film named by the compiled event (params.movie, from
## tools/hsltools/levels/timeline.py's code table) plays over the scene and holds
## the timeline until it ends or is skipped; an unmapped code is only recorded.
func _play_movie(event: Dictionary) -> void:
	var params: Dictionary = event.get("params", {})
	var name := str(params.get("movie", ""))
	if name == "":
		coordinator.story_records.append({"kind": "movie_play", "source_event_id": str(event.get("id", "")), "args": (event.get("args", []) as Array).duplicate(), "status": "unmapped_code"})
		return
	_start_movie(name, str(event.get("id", "")), Callable())


func _start_movie(name: String, source_event_id: String, after: Callable) -> void:
	runtime.get_node("BattleMusic").stop() # StopMusic 0x42def1 opens the film player; nothing resumes it
	_movie = MoviePlayer.new()
	_movie.name = "StoryMovie"
	_after_movie = after
	runtime.add_child(_movie)
	_movie.finished.connect(_on_movie_finished.bind(source_event_id))
	if coordinator.end_card._end_card != null:
		coordinator.end_card._end_card.visible = false
	_movie.play(name)


func _on_movie_finished(reason: String, source_event_id: String) -> void:
	if _movie == null:
		return
	coordinator.story_records.append({"kind": "movie_play", "source_event_id": source_event_id, "movie": str(_movie.movie_name), "status": reason, "frame_index": int(_movie.frame_index), "frame_count": int(_movie.frame_count())})
	_movie.queue_free()
	_movie = null
	coordinator.wait_remaining = 0.0
	var after := _after_movie
	_after_movie = Callable()
	if after.is_valid():
		after.call()


func _ensure_title() -> void:
	if _title != null:
		return
	var title_value: Variant = runtime.message_text_evidence.get("section_title", {})
	if typeof(title_value) != TYPE_DICTIONARY:
		return  # story scenes without actShowSectionName record section_title as null
	var title_info: Dictionary = title_value
	var res_path := str(title_info.get("res_path", ""))
	if res_path == "" or not ResourceLoader.exists(res_path):
		return
	var band_origin: Array = BattleUISkin.data()["assets"][TITLE_BAND_ASSET]["draw_origin"]
	_title = build_section_title_view(load(res_path), BattleUISkin.texture(TITLE_BAND_ASSET), Vector2(float(band_origin[0]), float(band_origin[1])))
	_title_band = _title.get_node("SectionTitleBand")
	_title_name = _title.get_node("SectionTitleName")
	runtime.get_node("UI").add_child(_title)
	_title.hide()


func _set_title_visible(visible: bool) -> void:
	if _title == null:
		return
	if visible and not _title.visible:
		_title_elapsed = 0.0
		_title_state = section_title_new_state()
		_title_skip_pending = false
		apply_section_title_state(_title, _title_state)
	_title.visible = visible


## Where the camera centre goes for a script position token (x, y). The original puts the
## point at the view's (320, 192) — `0x43bf30` sets the view's top-left to the point minus
## (0x140, 0xc0), clamped to the map — so in the remake's 640×480 view the centre is the
## point plus (0, 48). actScrollBGToPos／actScrollBGToPosSpeed first round the point to its
## cell centre (`(v & ~0x1f) + 0x10`, VM stage 0 at 0x45360e); actSetBGToPos (case 0x61)
## uses the raw point. Static-derived: original_script_camera_scroll.md. The x, y are not
## the view's top-left (the reading this replaces, which left STORY006's entering party
## at the top edge of the view).
static func script_position_camera_centre(args: Array, cell_centre: bool) -> Vector2:
	var point := Vector2(float(str(args[0])), float(str(args[1])))
	if cell_centre:
		point = Vector2(float((int(point.x) & ~0x1f) + 0x10), float((int(point.y) & ~0x1f) + 0x10))
	return BattleCameraController.focus_centre(point)


## An actor the script inserts where the script's camera shows it only in part (WINFAIL041
## event 0 raises its water monsters 160 px above the framed point, feet at the view's top
## edge) pulls the view just far enough to hold its sprite: the box around the foot point
## (KEEP_IN_VIEW_SIDE either side, KEEP_IN_VIEW_UP above) plus a margin. Remake-invented: the
## original frames only the token's point. Returns the (unclamped-to-map) camera centre;
## `centre` itself when the box already fits.
const KEEP_IN_VIEW_SIDE := 24.0
const KEEP_IN_VIEW_UP := 72.0
const KEEP_IN_VIEW_MARGIN := 8.0


static func keep_in_view_centre(centre: Vector2, foot: Vector2, view: Vector2) -> Vector2:
	var box := Rect2(foot + Vector2(-KEEP_IN_VIEW_SIDE - KEEP_IN_VIEW_MARGIN, -KEEP_IN_VIEW_UP - KEEP_IN_VIEW_MARGIN), Vector2(2.0 * (KEEP_IN_VIEW_SIDE + KEEP_IN_VIEW_MARGIN), KEEP_IN_VIEW_UP + 2.0 * KEEP_IN_VIEW_MARGIN))
	var half := view * 0.5
	var shifted := centre
	if box.position.x < centre.x - half.x: shifted.x = box.position.x + half.x
	elif box.end.x > centre.x + half.x: shifted.x = box.end.x - half.x
	if box.position.y < centre.y - half.y: shifted.y = box.position.y + half.y
	elif box.end.y > centre.y + half.y: shifted.y = box.end.y - half.y
	return shifted


## Applies keep_in_view_centre to a freshly inserted actor standing inside the map (an
## off-map insert walks in and is framed by the script's own camera tokens). The pull is a
## script-speed scroll that does not hold the timeline.
func _keep_inserted_actor_in_view(unit_id: String, source_event_id: String) -> void:
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	if actor == null or runtime.camera_controller == null or runtime.map_config == null:
		return
	var foot: Vector2 = actor.position
	var world := Vector2(runtime.map_config.world_size)
	if foot.x < 0.0 or foot.y < 0.0 or foot.x > world.x or foot.y > world.y:
		return
	var from: Vector2 = runtime.camera.position
	if runtime.camera_controller.is_scrolling():
		from = runtime.camera_controller.scroll_target
	var target: Vector2 = runtime.camera_controller.clamped_position(keep_in_view_centre(from, foot, Vector2(runtime.map_config.logical_viewport_size)))
	if target.is_equal_approx(from):
		return
	var seconds := _scroll_camera(target)
	coordinator.camera_records.append({"source_event_id": source_event_id, "unit_id": unit_id, "target": target, "scroll": true, "duration_seconds": seconds, "reason": "keep_inserted_actor_in_view"})


func _camera_target_for_script_position(args: Array, cell_centre: bool) -> Vector2:
	return runtime.camera_controller.clamped_position(script_position_camera_centre(args, cell_centre))


func _set_camera_to_position(event: Dictionary) -> void:
	## actSetBGToPos,x,y: immediate view placement without a tween (the first camera
	## token of most main-chapter openings, before the level music delay).
	var args: Array = event.get("args", [])
	if args.size() < 2 or runtime.camera_controller == null:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "camera_position_set", "reason": "missing_args_or_camera"})
		return
	var target := _camera_target_for_script_position(args, false)
	runtime.camera_controller.snap_to(target)
	coordinator.camera_records.append({"source_event_id": str(event.get("id", "")), "unit_id": "", "position_args": [str(args[0]).to_int(), str(args[1]).to_int()], "target": target, "scroll": false})


func _scroll_camera_to_position_speed(event: Dictionary) -> void:
	## actScrollBGToPosSpeed,x,y,speed (VM case 0x4b → 0x43c140): the cell centre of (x,y) goes
	## to the view's script focus like actScrollBGToPos, but each tick runs 0x45e80d with
	## step = speed and tolerance 1 (half the remaining distance per axis, at most `speed` px),
	## landing on the target. Blocking. The corpus uses speeds 1／2／4／8; a missing or
	## non-positive speed would never converge in the original and is refused here.
	var args: Array = event.get("args", [])
	var speed := str(args[2]).to_int() if args.size() > 2 else 0
	if args.size() < 2 or runtime.camera_controller == null or speed <= 0:
		push_error("actScrollBGToPosSpeed without a camera, target or positive speed: %s" % [args])
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "camera_position_target_speed", "reason": "missing_args_camera_or_speed"})
		return
	var target := _camera_target_for_script_position(args, true)
	var seconds: float = runtime.camera_controller.scroll_to(target, speed, BattleCameraController.SPEED_SCROLL_TOLERANCE)
	coordinator.wait_remaining = seconds
	coordinator.camera_records.append({"source_event_id": str(event.get("id", "")), "unit_id": "", "position_args": [str(args[0]).to_int(), str(args[1]).to_int()], "target": target, "scroll": true, "speed_arg": float(speed), "duration_seconds": seconds})


func _clear_dark_screen(event: Dictionary) -> void:
	## actDeleteDarkScreen: the level falls from where it is (0x43e2d0 state 2).
	if _dark_screen == null:
		coordinator.story_records.append({"kind": "screen_darken_clear", "source_event_id": str(event.get("id", "")), "status": "no_dark_screen"})
		return
	var seconds := _step_dark_screen(0)
	coordinator.story_records.append({"kind": "screen_darken_clear", "source_event_id": str(event.get("id", "")), "seconds": seconds})

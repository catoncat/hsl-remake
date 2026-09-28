extends Node2D
## Big-map scene module hosted by BattleSceneRuntime when a scenario's level_kind
## is world_map. Draws the decoded BigMap.SHP with the bigmap.dat points (m_pnt
## sprites), the visible TRACK.TXT routes (m_trk sprites) and the party marker,
## and lets the player travel one visible track at a time. Arrival resolves
## through WorldMapRules.arrival: a town with data opens the menu-style
## TownRuntime over the map (a town without data shows its picture card), a
## script-assigned level hands off through the campaign when it is remade and
## otherwise shows a not-remade card. The world state is the campaign's carried
## dictionary (hsl_world_state.v1); this node owns no battle truth and no second
## copy of it. The town hands its rewritten state and carry back here and this
## node persists both through CampaignProgress.
## Music follows the original (docs/evidence_packets/static_reverse/original_music.md §3.2):
## the map plays 06, a town that opens plays 05, and back on the map 06 starts again from
## the beginning; a picture-card town is the original's town that did not open, so the
## track does not change. Both play on the shared BattleMusic player.
## provenance:
##   rules: resource-derived content/imported/hsl/global/world_map/world_map.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_world_town.md
##     (reveal order and dropped clicks: walker 0x427420)
##   rules: provisional (encounter die and provisional town-tree unlocks; the glide uses the battle step 32)
##   layout: resource-derived content/imported/hsl/global/world_map/world_map.json
##   layout: runtime-measured docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (status bar subtracted, text rows, grid lines visible; walker at battle size, frame 01)
##   layout: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_font_script/README.md
##     (point name: FONT.15 white over 0x8430 at (+1,+1), x − 8·(bytes/2), y − 25 — 0x427df0 → 0x427e99／0x427ee0)
##   layout: remake-invented (not-remade card; point name labels only under OPT-GUIDE=提示)
##   strings: static-derived docs/evidence_packets/static_reverse/original_world_town.md
##   strings: remake-invented (card texts)
##   timing: static-derived docs/evidence_packets/static_reverse/original_world_town.md
##     (walker speed; track reveal: 0x4280d0 square clip round the anchor, +1 px per tick)
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json

const GameSettings = preload("res://game/settings/GameSettings.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const Rules = preload("res://game/world/WorldMapRules.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const TownRuntime = preload("res://game/world/TownRuntime.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const WorldScriptActions = preload("res://game/world/WorldScriptActions.gd")
const ConditionalPartyRules = preload("res://game/sim/ConditionalPartyRules.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const SUMMARY_SCHEMA := "hsl_world_map_runtime.v1"
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
## The big-map walker moves its 16.16 speed 0x20000 = 2 px per tick (0x4277ed).
const WALKER_PIXELS_PER_TICK := 2.0
const MARKER_UNIT_ID := "party_marker"

var runtime: Node
var config: Dictionary = {}
var world_map: Dictionary = {}
var state: Dictionary = {}
var active := false
var traveling := false
## The original walker speed is the 16.16 value 2 per logic tick (0x4277ed): 125 px/s at
## the 16 ms tick. The scene config may override it (tests do).
var travel_pixels_per_second := WALKER_PIXELS_PER_TICK * OriginalTick.TICKS_PER_SECOND
## Encounter die (WorldMapRules.arrival sample 1..100): -1 rolls like the original; the
## chapter walkthrough fixes it (100: only ratio-100 points fight) so its route stays deterministic.
var encounter_sample: int = -1
## The original point initialiser writes a [-16,-16,16,16] hit box (0x427f0d).
var point_hit_half_extent := 16.0
## Wall-clock length of the original's tick-driven track clip expansion (0x4280d0, its
## per-tick step unread — provisional); endpoints appear at once when it ends, as the
## original point phase-1 callback settles to 2 immediately (0x427df0).
## Wall seconds per track-reveal tick (0x4280d0 runs once per logic tick); 0 reveals at once.
var track_reveal_tick_seconds := OriginalTick.TICK_SECONDS
## The party marker reuses a battle actor's walk frames at their battle size: the original
## walker in frame 01 (original_world_town, runtime-measured) stands about 42 px tall, the
## height of a battle figure.
var marker_scale := 1.0
var marker: Node
var point_nodes: Dictionary = {}
## teSetBMWalkToPoint `from` value that keeps the current point (0x455443 cmp eax, 0x31).
const SCRIPT_WALK_KEEP_POINT := 49
var label_nodes: Dictionary = {}
var track_nodes: Dictionary = {}
var travel_records: Array[Dictionary] = []
var arrival_records: Array[Dictionary] = []
var input_records: Array[Dictionary] = []
## Provisional town-tree bridges applied on arrival (config.provisional_unlocks).
var unlock_records: Array[Dictionary] = []
var hovered_point := 0
var _layer: Node2D
var _card: Control
var _card_kind := ""
var _travel_tween: Tween
## The walk in progress (0x427070's chain 0x4c59e0): chosen destination, its tracks in order.
var _route_target := 0
var _route_tracks: Array[int] = []
var _route_trigger := ""
var _marker_textures: Dictionary = {}
var town_runtime: Control
var town_records: Array[Dictionary] = []
## Every track the map started ({key, stream}): 06 on entry, 05 per opened town, 06 back.
var music_records: Array[Dictionary] = []
var _towndef: Dictionary = {}
var _town_messages: Dictionary = {}
var _town_speakers: Dictionary = {}
var _shop_catalog: Dictionary = {}
## Track reveal animations in flight ({track_id, node, ticks, length, origin, size, top_left}).
## The walker's show-track sequence (0x427420 sub-states 0／1): "" idle, "to_point" gliding to
## a teBMSetShowTrackPoint point, "revealing" its routes, "back" gliding home.
var _show_phase := ""
var _show_point := 0
var _reveals: Array[Dictionary] = []
var _status_bar: Control
var _completion_caption: Label
var _completion_label: Label
var _time_label: Label


func start() -> Dictionary:
	config = runtime.first_battle_scenario
	world_map = Rules.load_world_map(BattleScenario.resource_path(config, "world_map"))
	if not bool(world_map.get("ok", false)):
		push_error("World map data failed to load: %s" % str(world_map.get("error", "unknown")))
		return summary()
	var travel: Dictionary = config.get("travel", {})
	travel_pixels_per_second = float(travel.get("pixels_per_second", travel_pixels_per_second))
	point_hit_half_extent = float(travel.get("point_hit_half_extent", point_hit_half_extent))
	marker_scale = float(travel.get("marker_scale", marker_scale))
	var carried: Dictionary = runtime.campaign_handoff.get("world", {}) if typeof(runtime.campaign_handoff.get("world")) == TYPE_DICTIONARY else {}
	if Rules.state_valid(carried):
		state = carried.duplicate(true)
	else:
		state = Rules.initial_state(world_map, int(config.get("start_point", 1)), _initial_towns(), config.get("new_game", {}))
	_build_layer()
	_build_status_bar()
	_spawn_marker(str(travel.get("marker_actor_id", "001")))
	_play_music("map_music")
	runtime.camera_controller.snap_to(Rules.point_position(world_map, current_point()))
	# Reveal the routes at the party's point and any point a script asked to show.
	_reveal_from(current_point())
	_consume_show_track_points()
	_refresh_labels()
	_refresh_status_bar()
	active = true
	_consume_pending_walk()
	return summary()


func current_point() -> int:
	return int(state.get("current_point", 0))


func reachable_points() -> Array[int]:
	return Rules.reachable_points(state, world_map, current_point())


func tick(delta: float) -> void:
	if not active:
		return
	_advance_reveals(delta)
	_advance_show_sequence()
	_refresh_status_bar()
	if traveling and marker != null:
		runtime.camera_controller.snap_to(marker.position)
		return
	if town_runtime != null or (_card != null and _card.visible) or reveal_busy():
		return
	var pan := BattleCameraController.scroll_direction(BattleCameraController.edge_direction(runtime.pointer_logical_position, runtime.pointer_inside_window and runtime.get_window().has_focus()))
	runtime.camera_controller.pan(pan, delta, BattleCameraController.edge_scroll_pixels_per_second())


## Consumes every input while the map is active. Left click on a reachable point
## starts travel; clicking the current town point re-enters its town; the cards
## close on confirm. Right click / Escape are recorded only (no system menu yet).
func handle_input(event: InputEvent) -> void:
	if not active:
		return
	if town_runtime != null:
		town_runtime.handle_input(event)
		return
	if event is InputEventMouseMotion:
		runtime.pointer_logical_position = runtime.viewport_to_logical_position(event.position)
		runtime.pointer_inside_window = Rect2(Vector2.ZERO, Vector2(runtime.logical_viewport_size)).has_point(runtime.pointer_logical_position)
		if _card == null or not _card.visible:
			_set_hovered(_point_at(runtime.logical_to_world_position(runtime.pointer_logical_position)))
		return
	if _card != null and _card.visible:
		if _confirm_pressed(event):
			_close_card()
		return
	if traveling:
		return
	if reveal_busy() and (event is InputEventMouseButton or (event is InputEventKey and event.keycode != KEY_ESCAPE)):
		# 0x427420 sub-state 1 waits for the reveals and the show-track glides, then clears the
		# click target 0x4c1ab8: a click meanwhile is dropped.
		input_records.append({"kind": "dropped_while_revealing"})
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_position: Vector2 = runtime.logical_to_world_position(runtime.viewport_to_logical_position(event.position))
		select_point(_point_at(world_position), "left_click")
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		if hovered_point > 0:
			select_point(hovered_point, "key_confirm")
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		# Esc / right-click raise the between-battle system scroll (Title051; remake binding,
		# the original big-map cancel input is not located).
		var opened: Dictionary = runtime.world_system_menu.open() if runtime.world_system_menu != null else {"ok": false, "reason": "no_scroll"}
		input_records.append({"kind": "cancel", "status": "system_menu_opened" if bool(opened.get("ok", false)) else "system_menu_" + str(opened.get("reason", "refused"))})


## Player choice of a point: travel along the route 0x427070 finds (any number of
## phase-2 tracks, WorldMapRules.route_between), otherwise record why. Clicking the current point only re-enters a town:
## walker 0x427420 sub-state 3 finds no track to itself (0x427070(a,a) = 0), then
## 0x42779c..0x4277e8 opens the town (event non-zero and Town bit) and every other
## case clears the click target at 0x4276fd; a Battle / General point is not
## re-dispatched (static-derived, original_world_town.md).
func select_point(point_id: int, trigger: String = "select") -> Dictionary:
	if point_id <= 0:
		input_records.append({"kind": "miss", "trigger": trigger})
		return {"status": "miss"}
	if point_id == current_point():
		if Rules.point_type(state, world_map, point_id) != Rules.TOWN or Rules.point_event(state, world_map, point_id) == 0:
			input_records.append({"kind": "current_point_ignored", "trigger": trigger, "point_id": point_id})
			return {"status": "current_point_ignored", "point_id": point_id}
		input_records.append({"kind": "reenter", "trigger": trigger, "point_id": point_id})
		return _resolve_arrival(point_id)
	var route := Rules.route_between(state, world_map, current_point(), point_id)
	if route.is_empty():
		input_records.append({"kind": "unreachable", "trigger": trigger, "point_id": point_id})
		return {"status": "unreachable", "point_id": point_id}
	_route_target = point_id
	_route_tracks = route
	_route_trigger = trigger
	var first := Rules.track_other_end(world_map, route[0], current_point())
	var record := _begin_travel(first, route[0], trigger)
	record["destination"] = point_id
	record["route_tracks"] = route.duplicate()
	return record


func _begin_travel(point_id: int, track_id: int, trigger: String, from_point: int = -1) -> Dictionary:
	if from_point < 0:
		from_point = current_point()
	var path := Rules.travel_polyline(world_map, track_id, from_point)
	var seconds := maxf(Rules.polyline_length(path) / maxf(travel_pixels_per_second, 1.0), 0.05)
	var record := {
		"kind": "travel",
		"trigger": trigger,
		"from_point": from_point,
		"to_point": point_id,
		"track_id": track_id,
		"path_point_count": path.size(),
		"duration_seconds": seconds,
	}
	travel_records.append(record)
	traveling = true
	_clear_labels()
	if marker != null:
		marker.move_along(path, seconds, true)
	if _travel_tween != null and _travel_tween.is_running():
		_travel_tween.kill()
	_travel_tween = create_tween()
	_travel_tween.tween_interval(seconds)
	_travel_tween.tween_callback(_arrive.bind(point_id, track_id))
	return record


func _arrive(point_id: int, track_id: int) -> void:
	traveling = false
	if _route_target > 0 and point_id != _route_target and _pass_point(point_id, track_id):
		return
	_route_target = 0
	_route_tracks = []
	# The original reads the point's flags before it marks Visit (0x427ab3 then the
	# Visit write), so the arrival branch is taken on the pre-visit state.
	var before: Dictionary = state
	state = Rules.visit(state, world_map, point_id)
	_apply_provisional_unlocks(point_id)
	if marker != null:
		marker.position = Rules.point_position(world_map, point_id)
	_reveal_from(point_id)
	_persist_state()
	_refresh_labels()
	_resolve_arrival(point_id, before)


## A point on the way to the chosen destination (0x427a86..0x427bd2): the walker runs the
## arrival dispatch 0x427ab3 on it as not-selected — a Town is passed, event 0 is passed, a
## General / Battle point with an event requests its level exactly as at a destination
## (the same encounter-ratio and 0..2 draws, in route order) and the walk ends there; the
## party then stands at that point (0x42cc10 keeps it in 0x4c1ba8, 0x42f7a4 restores it).
## A passed point is neither marked Visit nor has its tracks revealed, and the current
## point 0x4c1ba4 is written only when the walk ends. False when the point is the last one.
func _pass_point(point_id: int, track_id: int) -> bool:
	var index := _route_tracks.find(track_id)
	var outcome := Rules.arrival(state, world_map, point_id, false, encounter_sample)
	travel_records.append({"kind": "pass_point", "point_id": point_id, "outcome": outcome.duplicate()})
	if str(outcome.get("kind", "")) == "level":
		_route_target = 0
		_route_tracks = []
		state = Rules.visit(state, world_map, point_id)
		_apply_provisional_unlocks(point_id)
		if marker != null:
			marker.position = Rules.point_position(world_map, point_id)
		_reveal_from(point_id)
		_persist_state()
		_refresh_labels()
		arrival_records.append(outcome)
		_enter_level_event(point_id, int(outcome.get("level", 0)))
		return true
	if index < 0 or index + 1 >= _route_tracks.size():
		return false
	var next_track := _route_tracks[index + 1]
	_begin_travel(Rules.track_other_end(world_map, next_track, point_id), next_track, _route_trigger, point_id)
	return true


## Town-tree rewrites the scripts never issue but the story needs (world scene
## config.provisional_unlocks, each with evidence_tier provisional, its basis and the
## replacement evidence): applied once when the party first stands at the entry's point,
## through the same actAddTE / actDeleteTE path as script world writes.
func _apply_provisional_unlocks(point_id: int) -> void:
	var unlocks: Array = config.get("provisional_unlocks", [])
	if unlocks.is_empty():
		return
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress == null:
		return
	var applied: Array = (state.get("provisional_unlocks_applied", []) as Array).duplicate()
	for entry_value in unlocks:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var id := str(entry.get("id", ""))
		var when: Dictionary = entry.get("when", {})
		if id == "" or applied.has(id) or int(when.get("point_visited", -1)) != point_id:
			continue
		var flow: Dictionary = WorldScriptActions.apply_actions(state, entry.get("town_actions", []), progress.campaign)
		if flow.has("error"):
			push_warning("Provisional unlock %s left unapplied: %s" % [id, str(flow["error"])])
			unlock_records.append({"kind": "provisional_unlock", "id": id, "point_id": point_id, "status": "error", "error": str(flow["error"])})
			continue
		state = flow["world"]
		applied.append(id)
		state["provisional_unlocks_applied"] = applied
		unlock_records.append({"kind": "provisional_unlock", "id": id, "point_id": point_id, "status": "applied", "applied": int(flow.get("applied", 0))})


## Re-entering the current point (select_point) resolves on the present state: a
## visited General point then rolls its encounter like the original.
func _resolve_arrival(point_id: int, basis: Dictionary = {}) -> Dictionary:
	var outcome := Rules.arrival(basis if not basis.is_empty() else state, world_map, point_id, true, encounter_sample)
	arrival_records.append(outcome)
	match str(outcome.get("kind", "")):
		"town":
			_open_town(int(outcome.get("town_id", 0)))
		"level", "encounter":
			_enter_level_event(point_id, int(outcome.get("level", 0)))
		_:
			pass
	return outcome


## The level a point opens (its script-assigned event, the same-id default or an
## encounter) or a town's teSetNextPlayLevelEvent: hand the carried party and
## world state to the registered scenario as next_level_event [point, level]
## (script reading: the second value is the level to load, the first the big-map
## point it belongs to); unregistered levels stay on the map with a card. True when
## the scene hands off to the level.
func _enter_level_event(point: int, level_no: int) -> bool:
	if level_no == Rules.BIG_MAP_LEVEL:
		# (town_*, gameBigMapLevel) from a town event: stay on the map, standing at that point.
		state = Rules.visit(state, world_map, point)
		var modes: Dictionary = state.get("point_modes", {})
		modes[str(point)] = Rules.MODE_SHOWN
		state["point_modes"] = modes
		if marker != null:
			marker.position = Rules.point_position(world_map, point)
		_rebuild_layer()
		_reveal_from(point)
		_persist_state()
		return false
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	var path := ""
	if progress != null:
		path = progress.next_scenario_path(progress.campaign, {"next_level_event": [point, level_no]})
	if path != "" and progress != null:
		var carry: Dictionary = runtime.campaign_handoff.get("carry", {}) if typeof(runtime.campaign_handoff.get("carry")) == TYPE_DICTIONARY else {}
		var blocked := _blocked_party_members(path, carry)
		if not blocked.is_empty():
			# A random encounter that cannot field a carried member yet (no reviewed template /
			# shared portrait): explicit stop on the map, never a silently smaller party.
			var names: Array = blocked.map(func(member): return str(member.get("unit_id", member.get("actor_id", ""))))
			_show_card("encounter_party_unfielded", "level %d · %s" % [level_no, Rules.point_label(world_map, point)], "此遭遇戰尚無 %s 的來源資料　　空格／點擊：返回地圖" % "／".join(names), null)
			return false
		progress.start_world_handoff(path, carry, state)
		return true
	_show_card("level_not_remade", "level %d · %s" % [level_no, Rules.point_label(world_map, point)], "此地的關卡尚未重製　　空格／點擊：返回地圖", null)
	return false


## Carried members a conditional-party scenario (random encounter) lists as not fieldable.
func _blocked_party_members(scenario_path: String, carry: Dictionary) -> Array:
	var scenario := BattleScenario.load_file(scenario_path)
	if not bool(scenario.get("ok", false)):
		return []
	return ConditionalPartyRules.blocked_members(scenario, carry)


## The menu-style town screen for a town the world state knows (its tree from
## the provisional initial-tree table plus script edits); towns without state
## fall back to the picture card.
func _open_town(town_id: int) -> void:
	if town_runtime != null:
		return
	var towns: Dictionary = state.get("towns", {})
	if not towns.has(str(town_id)):
		_show_town_card(town_id)
		return
	_load_town_data()
	if _towndef.has("error"):
		push_error("Town data failed to load: %s" % str(_towndef.get("error", "")))
		_show_town_card(town_id)
		return
	_close_card()
	var town := TownRuntime.new()
	town.runtime = runtime
	town.town_id = town_id
	town.town_label = Rules.point_label(world_map, town_id)
	town.towndef = _towndef
	town.messages = _town_messages
	town.speakers = _town_speakers
	town.shop_catalog = _shop_catalog
	town.portraits_path = BattleScenario.resource_path(config, "town_portraits")
	town.sounds_path = BattleScenario.resource_path(config, "town_sounds")
	town.background = _town_background(town_id)
	town.state = state.duplicate(true)
	town.carry = _carry()
	town.party_changed.connect(_on_town_party_changed)
	town.level_requested.connect(_on_town_level_requested)
	town.closed.connect(_on_town_closed)
	town_runtime = town
	runtime.get_node("UI").add_child(town)
	town.open()
	town_records.append({"kind": "open", "town_id": town_id, "exec_event": int((towns[str(town_id)] as Dictionary).get("exec_event", 0))})
	# The town loaded: the original calls PlayMusic(5) here (0x4564e1, original_music.md §3.2).
	_play_music("town_music")


## Fresh world state seeds every town's menu tree from the provisional initial
## tree table (hsl_town_initial_trees.v1); scripts rewrite it from there.
func _initial_towns() -> Dictionary:
	_load_town_data()
	if _towndef.has("error"):
		return {}
	var trees := TownEventRules.load_initial_trees(BattleScenario.resource_path(config, "town_initial_trees"))
	if trees.has("error"):
		push_error("Town initial trees failed to load: %s" % str(trees.get("error", "")))
		return {}
	var towns := TownEventRules.initial_town_state(_towndef, trees)
	return towns if not towns.has("error") else {}


func _load_town_data() -> void:
	if not _towndef.is_empty():
		return
	_towndef = TownEventRules.load_towndef(BattleScenario.resource_path(config, "towndef"))
	var messages := _load_json(BattleScenario.resource_path(config, "town_messages"), "hsl_town_message_text.v1")
	_town_messages = messages.get("messages", {}) if typeof(messages.get("messages")) == TYPE_DICTIONARY else {}
	_town_speakers = messages.get("speakers", {}) if typeof(messages.get("speakers")) == TYPE_DICTIONARY else {}
	var shop := _load_json(BattleScenario.resource_path(config, "town_shop_items"), "hsl_town_shop_items.v1")
	_shop_catalog = shop.get("items", {}) if typeof(shop.get("items")) == TYPE_DICTIONARY else {}


static func _load_json(path: String, schema: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		push_error("Missing town data: %s" % path)
		return {}
	var parsed: Variant = ContentPaths.read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("schema", "")) != schema:
		push_error("Town data schema mismatch: %s (expected %s)" % [path, schema])
		return {}
	return parsed


func _town_background(town_id: int) -> Texture2D:
	var town: Dictionary = Rules.town(world_map, town_id)
	var background: Variant = town.get("background")
	if typeof(background) == TYPE_DICTIONARY and str((background as Dictionary).get("preview", "")) != "":
		var preview := str((background as Dictionary).get("preview", ""))
		return load("%s/%s" % [BattleScenario.resource_path(config, "town_background_dir"), preview.get_file()])
	return null


func _carry() -> Dictionary:
	var carry: Variant = runtime.campaign_handoff.get("carry", {})
	return (carry as Dictionary).duplicate(true) if typeof(carry) == TYPE_DICTIONARY else {}


## Every finished town run (and every shop transaction) rewrites the world state
## and the carried party; both persist at once so a relaunch resumes with them.
func _on_town_party_changed(next_state: Dictionary, next_carry: Dictionary) -> void:
	state = next_state.duplicate(true)
	runtime.campaign_handoff["carry"] = next_carry.duplicate(true)
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress != null:
		progress.update_world_state(state, next_carry)
	town_records.append({"kind": "party_changed", "gold": int((next_carry.get("loop", {}) as Dictionary).get("gold", 0)) if typeof(next_carry.get("loop")) == TYPE_DICTIONARY else 0})


func _on_town_level_requested(next_level_event: Array) -> void:
	town_records.append({"kind": "level_requested", "next_level_event": next_level_event.duplicate()})
	_free_town()
	if next_level_event.size() >= 2 and _enter_level_event(int(next_level_event[0]), int(next_level_event[1])):
		return
	# Still on the map (a big-map point or a card over it): 06 again, as when the town closes.
	_play_music("map_music")


func _on_town_closed(town_id: int) -> void:
	town_records.append({"kind": "closed", "town_id": town_id})
	_free_town()
	# Back from an opened town the original replays 06 from the start (0x427d31, §3.2).
	_play_music("map_music")
	_rebuild_layer()
	_reveal_from(current_point())
	_consume_show_track_points()
	_consume_pending_walk()


## teBMSetShowTrackPoint / actBMSetShowTrackPoint name the point whose routes
## reveal next (resource-derived: the eight town events that clear a point's and
## a route's Hidden bit all follow with this token at the far point — 席達鎮酒館
## 女客人二 shows 曼多力亞 so track 10 to 薛維斯港 appears while the party still
## stands in 席達鎮). The walker (0x427420 sub-state 1) takes them after the routes underfoot
## have revealed: the camera glides to the point (0x43bf30, retried each tick until it lands),
## its routes reveal, and once they are done the camera glides back to the party's point.
## Requests stay in the world state until their turn; the map opening and a town closing
## start the sequence.
func _consume_show_track_points() -> void:
	_advance_show_sequence()


## Whether reveals or the show-track sequence still run (the walker takes no click meanwhile).
func reveal_busy() -> bool:
	return not _reveals.is_empty() or _show_phase != "" or not (state.get("show_track_points", []) as Array).is_empty()


func _advance_show_sequence() -> void:
	if not _reveals.is_empty() or traveling or town_runtime != null or runtime == null or runtime.camera_controller == null or runtime.camera_controller.is_scrolling():
		return
	match _show_phase:
		"":
			var queue: Array = (state.get("show_track_points", []) as Array).duplicate()
			if queue.is_empty():
				return
			_show_point = int(queue.pop_front())
			state["show_track_points"] = queue
			_show_phase = "to_point"
			_glide_to_point(_show_point)
		"to_point":
			_show_phase = "revealing"
			_reveal_from(_show_point)
		"revealing":
			if not (state.get("show_track_points", []) as Array).is_empty():
				_show_phase = ""
				_advance_show_sequence()
				return
			_show_phase = "back"
			_glide_to_point(current_point())
		"back":
			_show_phase = ""
			_reveal_from(current_point())
			_persist_state()


func _glide_to_point(point_id: int) -> void:
	runtime.camera_controller.scroll_to(BattleCameraController.focus_centre(Rules.point_position(world_map, point_id)), BattleCameraController.BATTLE_SCROLL_STEP)


## teSetBMWalkToPoint / actSetBMWalkToPoint left a walk in the world state (static-derived,
## original_world_town.md): the town handler 0x45543a writes `to` into 0x4c1bb4 and, unless
## `from` is 49, `from` into 0x477c18 (0x42cc60); on the way back to the map 0x42f7a4 makes
## that the current point 0x4c1ba4 (no Visit, no reveal). The walker's sub-state 2 turns
## 0x4c1bb4 into the click target (0x427723..0x42774b) and sub-state 3 routes it with 0x427070
## exactly like a player click, so the party walks the multi-track route (ship routes such as
## 薛維斯港 → 巴瀚納海峽) through select_point. No route: 0x427796 clears the click at 0x4276fd
## and the party stays where it is; the target being the current point re-enters a town.
func _consume_pending_walk() -> void:
	var walk: Variant = state.get("pending_walk")
	if typeof(walk) != TYPE_DICTIONARY:
		return
	state.erase("pending_walk")
	var to_point := int((walk as Dictionary).get("to", 0))
	var from_point := int((walk as Dictionary).get("from", 0))
	if from_point > 0 and from_point != SCRIPT_WALK_KEEP_POINT and not Rules.point(world_map, from_point).is_empty() and from_point != current_point():
		state["current_point"] = from_point
		if marker != null:
			marker.position = Rules.point_position(world_map, from_point)
		_refresh_labels()
	if to_point <= 0 or Rules.point(world_map, to_point).is_empty():
		_persist_state()
		return
	var record := select_point(to_point, "script_walk")
	if str(record.get("kind", "")) != "travel":
		_persist_state()


func _free_town() -> void:
	if town_runtime != null:
		town_runtime.queue_free()
		town_runtime = null


## Town events may reveal tracks / points or change point kinds: redraw the map
## layer from the current state (the marker is not part of the layer).
func _rebuild_layer() -> void:
	if _layer != null:
		_layer.queue_free()
		_layer = null
	point_nodes.clear()
	label_nodes.clear()
	track_nodes.clear()
	_reveals.clear()
	_build_layer()
	_refresh_labels()
	_refresh_status_bar()


func _show_town_card(town_id: int) -> void:
	var town: Dictionary = Rules.town(world_map, town_id)
	var texture: Texture2D = null
	var background: Variant = town.get("background")
	if typeof(background) == TYPE_DICTIONARY and str((background as Dictionary).get("preview", "")) != "":
		var preview := str((background as Dictionary).get("preview", ""))
		texture = load("%s/%s" % [BattleScenario.resource_path(config, "town_background_dir"), preview.get_file()])
	_show_card("town", Rules.point_label(world_map, town_id), "城鎮內容重製中　　空格／點擊：返回地圖", texture)


func _show_card(kind: String, title_text: String, hint_text: String, texture: Texture2D) -> void:
	_close_card()
	_card_kind = kind
	_card = Control.new()
	_card.name = "WorldMapCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.size = Vector2(640, 480)
	dim.color = Color(0, 0, 0, 0.72)
	_card.add_child(dim)
	var title_y := 300.0
	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.position = Vector2(320.0 - texture.get_width() * 0.5, 60.0)
		_card.add_child(picture)
		title_y = 60.0 + texture.get_height() + 24.0
	else:
		title_y = 200.0
	var title := Label.new()
	title.text = title_text
	title.position = Vector2(0, title_y)
	title.size = Vector2(640, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.93, 0.87, 0.6))
	_card.add_child(title)
	var hint := Label.new()
	hint.text = hint_text
	hint.position = Vector2(0, title_y + 48.0)
	hint.size = Vector2(640, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_card.add_child(hint)
	runtime.get_node("UI").add_child(_card)


func _close_card() -> void:
	if _card != null:
		_card.queue_free()
		_card = null
	_card_kind = ""


## Once a hand-off is pending the map is being left: its record already carries
## the world state, and a late reveal or arrival must not overwrite it with the
## map position.
func _persist_state() -> void:
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress != null and not progress.has_pending():
		progress.update_world_state(state)


func _build_layer() -> void:
	_layer = Node2D.new()
	_layer.name = "WorldMapLayer"
	runtime.world_root.add_child(_layer)
	runtime.world_root.move_child(_layer, runtime.map_backdrop.get_index() + 1)
	var markers: Dictionary = (config.get("resources", {}) as Dictionary).get("point_marker_textures", {})
	for key in markers.keys():
		_marker_textures[int(key)] = load(str(markers[key]))
	# Only points and tracks in a show phase (1 revealing / 2 stable) are drawn; a
	# stable track is complete, a revealing one restarts its clip animation.
	for track_value in world_map.get("tracks", []):
		var entry: Dictionary = track_value
		var track_id := int(entry.get("id", 0))
		if Rules.track_hidden(state, world_map, track_id) or not Rules.track_shown(state, world_map, track_id):
			continue
		_add_track_node(track_id, Rules.track_mode(state, world_map, track_id) == Rules.MODE_REVEALING, current_point())
	for point_value in world_map.get("points", []):
		var entry: Dictionary = point_value
		var point_id := int(entry.get("id", 0))
		if Rules.point_hidden(state, world_map, point_id) or not Rules.point_shown(state, world_map, point_id):
			continue
		_add_point_node(point_id)


func _add_track_node(track_id: int, revealing: bool, origin_point: int) -> void:
	if track_nodes.has(track_id):
		return
	var entry := Rules.track(world_map, track_id)
	var sprite: Dictionary = entry.get("sprite", {}) if typeof(entry.get("sprite")) == TYPE_DICTIONARY else {}
	var preview := str(sprite.get("preview", ""))
	if preview == "":
		return
	var node := Sprite2D.new()
	node.name = "Track%03d" % track_id
	node.texture = load("%s/%s" % [BattleScenario.resource_path(config, "track_sprite_dir"), preview.get_file()])
	node.centered = false
	node.position = Rules.track_sprite_top_left(world_map, track_id)
	node.z_index = 1
	_layer.add_child(node)
	track_nodes[track_id] = node
	if revealing:
		_start_track_reveal(track_id, node, origin_point)


func _add_point_node(point_id: int) -> void:
	if point_nodes.has(point_id):
		return
	var node := Sprite2D.new()
	node.name = "Point%02d" % point_id
	node.texture = _marker_textures.get(Rules.marker_kind(state, world_map, point_id))
	node.position = Rules.point_position(world_map, point_id)
	node.z_index = 2
	_layer.add_child(node)
	point_nodes[point_id] = node


## Remake reveal trigger (provisional): the non-hidden, not yet shown tracks at a
## point start their clip animation; their far endpoints appear when it ends.
func _reveal_from(point_id: int) -> void:
	var result := Rules.reveal_tracks_at(state, world_map, point_id)
	state = result["state"]
	for track_id in result["track_ids"]:
		if track_nodes.has(int(track_id)):
			_start_track_reveal(int(track_id), track_nodes[int(track_id)], point_id)
		else:
			_add_track_node(int(track_id), true, point_id)


## Track phase 1 (0x4280d0, static-derived): the first tick sets the clip flag with half-size
## r = 0 and takes N = max(origin.x, w − origin.x, origin.y, h − origin.y) from the shape
## bounds (0x4606a9) — the anchor's distance to the farthest edge; each later tick grows r
## by 1 and the clip is the square anchor ± r (0x428280). The anchor is the track object's
## EVEF position, the track's from point, whichever end the party stands at; when N ticks
## have run the track settles to phase 2 and both endpoints enter phase 1.
func _start_track_reveal(track_id: int, node: Sprite2D, _origin_point: int) -> void:
	var size: Vector2 = node.texture.get_size() if node.texture != null else Vector2.ZERO
	for existing in _reveals:
		if int(existing["track_id"]) == track_id:
			return
	var anchor: Vector2 = Rules.point_position(world_map, int(Rules.track(world_map, track_id).get("from_point", 0))) - node.position
	var length := maxf(maxf(anchor.x, size.x - anchor.x), maxf(anchor.y, size.y - anchor.y))
	var reveal := {"track_id": track_id, "node": node, "ticks": 0.0, "length": length, "origin": anchor, "size": size, "top_left": node.position}
	node.region_enabled = true
	_apply_reveal_clip(reveal)
	if track_reveal_tick_seconds <= 0.0:
		_finish_reveal(reveal)
	else:
		_reveals.append(reveal)


func _apply_reveal_clip(reveal: Dictionary) -> void:
	var node: Sprite2D = reveal["node"]
	var radius := floorf(clampf(float(reveal["ticks"]), 0.0, float(reveal["length"])))
	var origin: Vector2 = reveal["origin"]
	var clip := Rect2(Vector2.ZERO, reveal["size"]).intersection(Rect2(origin - Vector2(radius, radius), Vector2(radius, radius) * 2.0))
	node.visible = clip.has_area()
	node.region_rect = clip
	node.position = (reveal["top_left"] as Vector2) + clip.position


func _advance_reveals(delta: float) -> void:
	if _reveals.is_empty():
		return
	var finished: Array[Dictionary] = []
	for reveal in _reveals:
		reveal["ticks"] = float(reveal["ticks"]) + delta / maxf(track_reveal_tick_seconds, 0.000001)
		_apply_reveal_clip(reveal)
		if float(reveal["ticks"]) >= float(reveal["length"]):
			finished.append(reveal)
	for reveal in finished:
		_reveals.erase(reveal)
		_finish_reveal(reveal)


func _finish_reveal(reveal: Dictionary) -> void:
	var node: Sprite2D = reveal["node"]
	node.region_enabled = false
	node.visible = true
	node.position = reveal["top_left"]
	var result := Rules.finish_track_reveal(state, world_map, int(reveal["track_id"]))
	state = result["state"]
	for point_id in result["revealed_points"]:
		_add_point_node(int(point_id))
	_refresh_labels()
	_refresh_status_bar()
	_persist_state()


## The original status bar (obj12, STATUS_BAR.SHP at camera + (0, 412)) shows
## 「完成度： 」 with the completion percent and the cumulative play time as h:mm:ss
## (static-derived). Its drawing is runtime-measured on the original frames
## (docs/evidence_packets/runtime_observations/original_world_town/README.md): the shape is not
## pasted — it is subtracted from the map beneath it (frame 04, whose map matches BigMap.SHP at
## camera (640,480) to a mean 2.2: dst − 1.04 × STATUS_BAR fits to RMS 3.3, so a plain
## subtraction), leaving a black band centred on y 437 with the map, its grid lines and routes
## visible above and below. The texts are FONT.24 rows in the original colour codes with their
## (+1,+1) shadows (hsl01.exe table 0x476b44): the @5 yellow caption from x 6, its digits from
## the 24 px cell after the caption and a space (x 114), the @1 white time right-aligned to
## x 634, glyph rows y 427–444 (frames 01／03／04).
const STATUS_TEXT_ROW_TOP := 11.5
const STATUS_CAPTION_X := 6.0
const STATUS_PERCENT_X := 114.0
const STATUS_TIME_RIGHT := 634.0
## @5's shadow colour in the 0x476b44 table (RGB565 0x8420); @1 white uses BattleUISkin.TEXT_SHADOW.
const STATUS_CAPTION_SHADOW := Color8(131, 133, 0)


func _build_status_bar() -> void:
	var bar_config: Dictionary = config.get("status_bar", {})
	var texture_path := BattleScenario.resource_path(config, "status_bar_texture")
	if texture_path == "" or bar_config.is_empty():
		return
	var offset: Array = bar_config.get("position", [0, 412])
	_status_bar = Control.new()
	_status_bar.name = "WorldMapStatusBar"
	_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.position = Vector2(float(offset[0]), float(offset[1]))
	var picture := TextureRect.new()
	picture.name = "StatusBarShade"
	picture.texture = load(texture_path)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := CanvasItemMaterial.new()
	shade.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	picture.material = shade
	_status_bar.add_child(picture)
	_completion_caption = _status_label(STATUS_CAPTION_X, 4 * 24.0, BattleUISkin.TEXT_YELLOW, STATUS_CAPTION_SHADOW, HORIZONTAL_ALIGNMENT_LEFT)
	_completion_caption.text = str(bar_config.get("completion_label", "完成度："))
	_completion_label = _status_label(STATUS_PERCENT_X, 4 * 12.0, BattleUISkin.TEXT_YELLOW, STATUS_CAPTION_SHADOW, HORIZONTAL_ALIGNMENT_LEFT)
	_time_label = _status_label(STATUS_TIME_RIGHT - 160.0, 160.0, BattleUISkin.TEXT_WHITE, BattleUISkin.TEXT_SHADOW, HORIZONTAL_ALIGNMENT_RIGHT)
	runtime.get_node("UI").add_child(_status_bar)
	runtime.get_node("UI").move_child(_status_bar, 0)


func _status_label(x: float, width: float, color: Color, shadow: Color, alignment: int) -> Label:
	var label := BattleUISkin.text(_status_bar, Vector2(x, STATUS_TEXT_ROW_TOP), color, BattleUISkin.FONT_BODY, Vector2(width, 24))
	label.add_theme_color_override("font_shadow_color", shadow)
	label.horizontal_alignment = alignment
	return label


func _refresh_status_bar() -> void:
	if _status_bar == null:
		return
	_completion_label.text = "%d%%" % completion_percent()
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	var seconds := int(progress.play_seconds) if progress != null else 0
	_time_label.text = "%d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]


func completion_percent() -> int:
	return Rules.completion_percent(state, world_map) if not world_map.is_empty() else 0


## The marker figurine follows the carried member standing on `actor_id`'s row (001
## 雷歐納德): after a 命運神殿 job-up it walks the map in the up-title frames, like the
## battles and cutscenes draw him. Remake presentation — the original walker's shape
## source is not established.
func _spawn_marker(actor_id: String) -> void:
	var view := {"id": MARKER_UNIT_ID, "actor_id": actor_id}
	var units: Variant = _carry().get("units", {})
	if typeof(units) == TYPE_DICTIONARY:
		for unit_id in (units as Dictionary).keys():
			var record: Variant = (units as Dictionary)[unit_id]
			if typeof(record) == TYPE_DICTIONARY and str((record as Dictionary).get("actor_id", "")) == actor_id:
				view = runtime.stage.carried_unit_view(str(unit_id), actor_id)
				break
	marker = runtime.stage.spawn_actor_node(MARKER_UNIT_ID, actor_id, Rules.point_position(world_map, current_point()), view)
	marker.z_index = 3
	marker.scale = Vector2(marker_scale, marker_scale)


## Plays resources.map_music (06) or resources.town_music (05) on the shared BattleMusic
## player, always from the beginning like the original PlayMusic (original_music.md §1).
func _play_music(key: String) -> void:
	var music: AudioStreamPlayer = runtime.get_node_or_null("BattleMusic")
	var path := BattleScenario.resource_path(config, key)
	if music == null or path == "":
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_error("World map music missing: " + path)
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	music.stop()
	music.stream = stream
	music.volume_db = GameSettings.MUSIC_PLAYER_DB
	music.bus = GameSettings.music_bus()
	music.play()
	music_records.append({"key": key, "stream": path})


## Name labels for the current point and the points one visible track away, plus
## the hovered point: enough to navigate without covering the map with 45 names. The
## original draws no point names (frames 01／03／04, original_world_town.md), so they are an
## OPT-GUIDE=提示 addition read on every refresh; 原版 draws none.
func _refresh_labels() -> void:
	_clear_labels()
	if GameOptions.is_original("OPT-GUIDE"):
		return
	var wanted: Array[int] = [current_point()]
	for point_id in reachable_points():
		wanted.append(point_id)
	if hovered_point > 0 and not wanted.has(hovered_point) and point_nodes.has(hovered_point):
		wanted.append(hovered_point)
	for point_id in wanted:
		if not point_nodes.has(point_id):
			continue
		var label := Label.new()
		label.name = "PointLabel%02d" % point_id
		label.text = Rules.point_label(world_map, point_id)
		# As the original point proc 0x427df0 draws a name: FONT.15, white over the 0x8430 shadow
		# at (+1,+1), centred by Big5 bytes (8 px each) on the point, cell top 25 px above it.
		label.add_theme_font_size_override("font_size", BattleUISkin.FONT_SMALL)
		label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE)
		label.add_theme_color_override("font_shadow_color", BattleUISkin.TEXT_SHADOW)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		var name_bytes := 0
		for character in label.text:
			name_bytes += 1 if character.unicode_at(0) < 0x80 else 2
		label.position = Rules.point_position(world_map, point_id) - Vector2(8.0 * floorf(name_bytes / 2.0), 25.0)
		label.z_index = 4
		_layer.add_child(label)
		label_nodes[point_id] = label


func _clear_labels() -> void:
	for node in label_nodes.values():
		(node as Node).queue_free()
	label_nodes.clear()


func _set_hovered(point_id: int) -> void:
	if point_id == hovered_point:
		return
	hovered_point = point_id
	if not traveling:
		_refresh_labels()


## The original hit box is the [-16,-16,16,16] square around a shown point; the
## nearest centre wins where squares overlap.
func _point_at(world_position: Vector2) -> int:
	var best := 0
	var best_distance := INF
	for point_id in point_nodes.keys():
		var centre := Rules.point_position(world_map, int(point_id))
		if absf(centre.x - world_position.x) > point_hit_half_extent or absf(centre.y - world_position.y) > point_hit_half_extent:
			continue
		var distance := centre.distance_to(world_position)
		if distance < best_distance:
			best = int(point_id)
			best_distance = distance
	return best


static func _confirm_pressed(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)


func summary() -> Dictionary:
	return {
		"schema": SUMMARY_SCHEMA,
		"active": active,
		"current_point": current_point(),
		"current_point_label": Rules.point_label(world_map, current_point()) if not world_map.is_empty() else "",
		"reachable_points": reachable_points() if not world_map.is_empty() else [],
		"visible_point_count": point_nodes.size(),
		"visible_track_count": track_nodes.size(),
		"revealing_track_count": _reveals.size(),
		"reveal_busy": reveal_busy(),
		"show_phase": _show_phase,
		"completion_percent": completion_percent(),
		"label_count": label_nodes.size(),
		"traveling": traveling,
		"card_visible": _card != null and _card.visible,
		"card_kind": _card_kind,
		"town_open": town_runtime != null,
		"town": town_runtime.summary() if town_runtime != null else {},
		"town_records": town_records.duplicate(true),
		"music_records": music_records.duplicate(true),
		"travel_records": travel_records.duplicate(true),
		"arrival_records": arrival_records.duplicate(true),
		"unlock_records": unlock_records.duplicate(true),
		"input_records": input_records.duplicate(true),
		"state": state.duplicate(true),
		"claim_limit": "remake_notes:world_map_claim_limit",
	}

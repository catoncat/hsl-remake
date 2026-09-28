extends RefCounted
## Read-only queries over the resource-derived world map (bigmap.dat points,
## TRACK.TXT polylines, extras.h towns — content/imported/hsl/global/world_map/
## world_map.json) and the shared world state (hsl_world_state.v1) that the
## campaign carries between scenes. Stateless: every mutation from te/act tokens
## belongs to TownEventRules. Reachability, travel orientation and marker kinds
## are remake readings of the bmpm bits and the track table; the original
## big-map handler (hit areas, walk speed, point activation) is not proven.
## Point records carry three independent fields (static-derived, SR-069
## docs/evidence_packets/static_reverse/original_world_town.md): +0 mode (0 not
## shown / 1 revealing / 2 stable), +4 bmpm bits (Hidden blocks revealing; Visit
## marks a visited point; Town / General / Battle is the type, replaced as a
## group by point events) and +8 the event a point opens — the file gives every
## point its own id there. Arrival (0x427ab3): event 0 does nothing; General
## unvisited opens the event, visited rolls the encounter ratio then adds 0..2;
## Battle opens the event (+0..2 once visited); Town enters only as the chosen
## destination. A new game hides 17 points / 18 tracks by code (0x42c86e).
## What sets a track to mode 1 (the reveal animation) is not located: this remake
## reveals the non-hidden tracks at the point the party stands on (provisional).
## provenance:
##   rules: resource-derived content/imported/hsl/global/world_map/world_map.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_world_town.md
##   rules: provisional (track reveal trigger — what sets mode 1 is not located)
##   layout: resource-derived content/imported/hsl/global/world_map/world_map.json
##   strings: resource-derived content/imported/hsl/global/world_map/world_map.json
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const STATE_SCHEMA := "hsl_world_state.v1"
const DATA_SCHEMA := "hsl_world_map.v1"
## TYPE.H gameBigMapLevel: the big map is level 49 to the scripts, so
## actSetNextPlayLevelEvent(N, gameBigMapLevel) returns to the map at point N.
const BIG_MAP_LEVEL := 49
const HIDDEN := "bmpmHidden"
const TOWN := "bmpmTown"
const BATTLE := "bmpmBattle"
const GENERAL := "bmpmGeneral"
const VISIT := "bmpmVisit"

## M_PNT001..003 are three consecutive frames of one point shape; POINT.H adds
## Battle 0 / General 1 / Town 2 to the base frame (static-derived, 0x427f0d).
const MARKER_KIND_BATTLE := 1
const MARKER_KIND_GENERAL := 2
const MARKER_KIND_TOWN := 3
## Point / track show phases (+0): 0 not shown, 1 revealing, 2 stable.
const MODE_HIDDEN := 0
const MODE_REVEALING := 1
const MODE_SHOWN := 2
## Named points minus one is the completion denominator (0x427200).
const COMPLETION_DENOMINATOR_OFFSET := 1
## Route search bounds (0x427070): 100 point slots, unreached cost 600000 (0x927c0).
const ROUTE_SLOTS := 100
const ROUTE_UNREACHED_COST := 600000


static func load_world_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "missing_world_map", "path": path}
	var parsed: Variant = ContentPaths.read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("schema", "")) != DATA_SCHEMA:
		return {"ok": false, "error": "unsupported_world_map_schema", "path": path}
	var data: Dictionary = parsed
	data["ok"] = true
	return data


## Fresh world state at the campaign's first arrival on the map: every flag
## starts as bigmap.dat records it plus the new-game Hidden bits the original
## ORs by code (scene config new_game.hidden_points / hidden_tracks, 0x42c86e),
## no point event overrides, the given town dictionary
## (TownEventRules.initial_town_state) and the start point shown (mode 2).
static func initial_state(world_map: Dictionary, start_point: int, towns: Dictionary = {}, new_game: Dictionary = {}) -> Dictionary:
	var hidden_points: Array[int] = []
	for value in new_game.get("hidden_points", []):
		hidden_points.append(int(value))
	var hidden_tracks: Array[int] = []
	for value in new_game.get("hidden_tracks", []):
		hidden_tracks.append(int(value))
	var point_flags := {}
	for point_value in world_map.get("points", []):
		var entry: Dictionary = point_value
		var point_id := int(entry.get("id", 0))
		var names: Array = (entry.get("flag_names", []) as Array).duplicate()
		if hidden_points.has(point_id) and not names.has(HIDDEN):
			names.append(HIDDEN)
		point_flags[str(point_id)] = names
	var track_flags := {}
	for track_value in world_map.get("tracks", []):
		var entry: Dictionary = track_value
		var track_id := int(entry.get("id", 0))
		var names: Array = (entry.get("field1_flag_names", []) as Array).duplicate()
		for name in entry.get("field0_flag_names", []):
			if not names.has(name):
				names.append(name)
		if hidden_tracks.has(track_id) and not names.has(HIDDEN):
			names.append(HIDDEN)
		track_flags[str(track_id)] = names
	return {
		"schema": STATE_SCHEMA,
		"current_point": start_point,
		"point_flags": point_flags,
		"track_flags": track_flags,
		"point_events": {},
		"encounter_ratios": {},
		"point_modes": {str(start_point): MODE_SHOWN},
		"track_modes": {},
		"show_track_points": [],
		"towns": towns.duplicate(true),
		"over_score": {},
		"over_flag": 0,
		"secret_man_index": 0,
		"visited_points": [start_point],
	}


static func state_valid(state: Dictionary) -> bool:
	return str(state.get("schema", "")) == STATE_SCHEMA and int(state.get("current_point", 0)) > 0 \
		and typeof(state.get("point_flags")) == TYPE_DICTIONARY and typeof(state.get("track_flags")) == TYPE_DICTIONARY


static func point(world_map: Dictionary, point_id: int) -> Dictionary:
	for point_value in world_map.get("points", []):
		if int((point_value as Dictionary).get("id", 0)) == point_id:
			return point_value
	return {}


static func track(world_map: Dictionary, track_id: int) -> Dictionary:
	for track_value in world_map.get("tracks", []):
		if int((track_value as Dictionary).get("id", 0)) == track_id:
			return track_value
	return {}


static func point_position(world_map: Dictionary, point_id: int) -> Vector2:
	var entry := point(world_map, point_id)
	return Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))


static func point_label(world_map: Dictionary, point_id: int) -> String:
	return str(point(world_map, point_id).get("name_text", ""))


static func point_flags(state: Dictionary, world_map: Dictionary, point_id: int) -> Array:
	var overrides: Dictionary = state.get("point_flags", {})
	if overrides.has(str(point_id)):
		return overrides[str(point_id)]
	return point(world_map, point_id).get("flag_names", [])


static func track_flags(state: Dictionary, world_map: Dictionary, track_id: int) -> Array:
	var overrides: Dictionary = state.get("track_flags", {})
	if overrides.has(str(track_id)):
		return overrides[str(track_id)]
	var entry := track(world_map, track_id)
	var names: Array = (entry.get("field1_flag_names", []) as Array).duplicate()
	for name in entry.get("field0_flag_names", []):
		if not names.has(name):
			names.append(name)
	return names


static func point_hidden(state: Dictionary, world_map: Dictionary, point_id: int) -> bool:
	return point_flags(state, world_map, point_id).has(HIDDEN)


## Show phase of a point: the state override, else the record's +0 (歐姆村 is 2 in
## the file, every other point 0).
static func point_mode(state: Dictionary, world_map: Dictionary, point_id: int) -> int:
	var overrides: Dictionary = state.get("point_modes", {})
	if overrides.has(str(point_id)):
		return int(overrides[str(point_id)])
	return _mode_value(point(world_map, point_id).get("raw_field0", 0))


static func track_mode(state: Dictionary, world_map: Dictionary, track_id: int) -> int:
	var overrides: Dictionary = state.get("track_modes", {})
	if overrides.has(str(track_id)):
		return int(overrides[str(track_id)])
	return _mode_value(track(world_map, track_id).get("raw_field0", 0))


static func _mode_value(raw: Variant) -> int:
	if typeof(raw) == TYPE_STRING:
		return str(raw).hex_to_int() if str(raw).begins_with("0x") else int(str(raw))
	return int(raw)


## Drawn / travelable: phase 1 or 2 (a Hidden point never gets there by the
## normal setters, so Hidden is not re-checked here).
static func point_shown(state: Dictionary, world_map: Dictionary, point_id: int) -> bool:
	return point_mode(state, world_map, point_id) >= MODE_REVEALING


static func track_shown(state: Dictionary, world_map: Dictionary, track_id: int) -> bool:
	return track_mode(state, world_map, track_id) >= MODE_REVEALING


## The non-hidden, not yet shown tracks at a point enter the revealing phase.
## Triggers: teBMSetShowTrackPoint / actBMSetShowTrackPoint naming the point
## (resource-derived — the eight town events clearing a point's and a route's
## Hidden bit all follow with this token at the far point), and, provisional
## (the original 0→1 trigger for the initial routes is not located), the party's
## own point on map entry and arrival. Returns the new state and the track ids.
static func reveal_tracks_at(state: Dictionary, world_map: Dictionary, point_id: int) -> Dictionary:
	var next := state.duplicate(true)
	var modes: Dictionary = next.get("track_modes", {})
	var started: Array[int] = []
	for track_id in tracks_at(world_map, point_id):
		if track_hidden(next, world_map, track_id) or track_mode(next, world_map, track_id) != MODE_HIDDEN:
			continue
		modes[str(track_id)] = MODE_REVEALING
		started.append(track_id)
	next["track_modes"] = modes
	return {"state": next, "track_ids": started}


## The track reveal completes (0x4280d0): the track is stable and its endpoints
## are shown — the point phase-1 callback settles to 2 at once (0x427df0), so
## the endpoint goes straight to 2 unless Hidden.
static func finish_track_reveal(state: Dictionary, world_map: Dictionary, track_id: int) -> Dictionary:
	var next := state.duplicate(true)
	var track_modes: Dictionary = next.get("track_modes", {})
	track_modes[str(track_id)] = MODE_SHOWN
	next["track_modes"] = track_modes
	var point_modes: Dictionary = next.get("point_modes", {})
	var revealed: Array[int] = []
	var entry := track(world_map, track_id)
	for point_id in [int(entry.get("from_point", 0)), int(entry.get("to_point", 0))]:
		if point_id <= 0 or point_hidden(next, world_map, point_id) or point_mode(next, world_map, point_id) == MODE_SHOWN:
			continue
		point_modes[str(point_id)] = MODE_SHOWN
		revealed.append(point_id)
	next["point_modes"] = point_modes
	return {"state": next, "revealed_points": revealed}


## Completion as the original status bar computes it: shown, non-hidden points
## over named points minus one, capped at 100 (0x427200).
static func completion_percent(state: Dictionary, world_map: Dictionary) -> int:
	var shown := 0
	var named := 0
	for point_value in world_map.get("points", []):
		var point_id := int((point_value as Dictionary).get("id", 0))
		if str((point_value as Dictionary).get("name_text", "")) != "":
			named += 1
		if point_mode(state, world_map, point_id) == MODE_SHOWN and not point_hidden(state, world_map, point_id):
			shown += 1
	var denominator := maxi(named - COMPLETION_DENOMINATOR_OFFSET, 1)
	return mini(int(shown * 100 / denominator), 100)


static func track_hidden(state: Dictionary, world_map: Dictionary, track_id: int) -> bool:
	return track_flags(state, world_map, track_id).has(HIDDEN)


## Tracks touching a point, read from the track table's from/to columns (the
## point record's three track slots agree for every point except 16, which
## lists none and has no track — see world_map.json self_check).
static func tracks_at(world_map: Dictionary, point_id: int) -> Array[int]:
	var ids: Array[int] = []
	for track_value in world_map.get("tracks", []):
		var entry: Dictionary = track_value
		if int(entry.get("from_point", 0)) == point_id or int(entry.get("to_point", 0)) == point_id:
			ids.append(int(entry.get("id", 0)))
	return ids


static func track_other_end(world_map: Dictionary, track_id: int, point_id: int) -> int:
	var entry := track(world_map, track_id)
	var from_point := int(entry.get("from_point", 0))
	var to_point := int(entry.get("to_point", 0))
	if from_point == point_id:
		return to_point
	if to_point == point_id:
		return from_point
	return 0


## Points one shown (phase ≥ 1), non-hidden track away from from_point whose own
## record is not hidden.
static func reachable_points(state: Dictionary, world_map: Dictionary, from_point: int) -> Array[int]:
	var result: Array[int] = []
	for track_id in tracks_at(world_map, from_point):
		if track_hidden(state, world_map, track_id) or not track_shown(state, world_map, track_id):
			continue
		var other := track_other_end(world_map, track_id, from_point)
		if other <= 0 or point_hidden(state, world_map, other) or result.has(other):
			continue
		result.append(other)
	result.sort()
	return result


## The shown, non-hidden track joining two points, or 0.
static func track_between(state: Dictionary, world_map: Dictionary, a: int, b: int) -> int:
	for track_id in tracks_at(world_map, a):
		if track_other_end(world_map, track_id, a) == b and not track_hidden(state, world_map, track_id) and track_shown(state, world_map, track_id):
			return track_id
	return 0


## The walker's route search 0x427070(from, to) (static-derived, original_world_town.md
## 「寻路与行走」): a label-correcting shortest path over the point table. Every point
## starts at 600000 (0x927c0), the origin at 0 and active; passes sweep the point slots
## in order, and each active point relaxes its record's track slots (+0x18..+0x24) through
## 0x426fc0 — only tracks in show phase 2 (0x426c50), cost = the track's TRACK.TXT
## polyline length as the sum of |dx|+|dy| (0x44e006), a relaxation taken only when it is
## below both the neighbour's cost and the best cost to `to` so far (strict) — then goes
## inactive; passes repeat while anything relaxed. Neither point Hidden nor point phase is
## checked. The track ids in walking order, empty when `to` is not reached or equals
## `from` (0x42708a).
static func route_between(state: Dictionary, world_map: Dictionary, from_point: int, to_point: int) -> Array[int]:
	var result: Array[int] = []
	if from_point == to_point or from_point <= 0 or to_point <= 0 or from_point >= ROUTE_SLOTS or to_point >= ROUTE_SLOTS:
		return result
	var slots: Array = []
	for point_value in world_map.get("points", []):
		var entry: Dictionary = point_value
		var tracks: Array[int] = []
		for raw in (entry.get("raw_track_fields", []) as Array) + [entry.get("raw_field9", 0)]:
			if int(raw) > 0:
				tracks.append(int(raw))
		slots.append([int(entry.get("slot", entry.get("id", 0))), tracks])
	slots.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var cost: Dictionary = {from_point: 0}
	var active: Dictionary = {from_point: true}
	var previous: Dictionary = {}
	var via: Dictionary = {}
	var best := ROUTE_UNREACHED_COST
	var relaxed := true
	while relaxed:
		relaxed = false
		for slot in slots:
			var node := int(slot[0])
			if not bool(active.get(node, false)):
				continue
			for track_id in slot[1]:
				if track_mode(state, world_map, track_id) != MODE_SHOWN:
					continue
				var entry := track(world_map, track_id)
				var neighbour := int(entry.get("to_point", 0)) if int(entry.get("from_point", 0)) == node else int(entry.get("from_point", 0))
				var candidate := int(cost[node]) + track_route_cost(world_map, track_id)
				if candidate >= best or int(cost.get(neighbour, ROUTE_UNREACHED_COST)) <= candidate:
					continue
				cost[neighbour] = candidate
				active[neighbour] = true
				previous[neighbour] = node
				via[neighbour] = track_id
				relaxed = true
				if neighbour == to_point:
					best = candidate
			active[node] = false
	if not previous.has(to_point):
		return result
	var node := to_point
	while node != from_point:
		result.push_front(int(via[node]))
		node = int(previous[node])
	return result


## A track's route cost as the original track loader stores it at +8 (0x44e006..0x44e061):
## the sum of |dx| + |dy| between successive TRACK.TXT polyline points.
static func track_route_cost(world_map: Dictionary, track_id: int) -> int:
	var total := 0
	var polyline: Array = track(world_map, track_id).get("polyline", [])
	for index in range(1, polyline.size()):
		var a: Array = polyline[index - 1]
		var b: Array = polyline[index]
		total += absi(int(b[0]) - int(a[0])) + absi(int(b[1]) - int(a[1]))
	return total


## TRACK.TXT polyline oriented so it starts at from_point (the table stores each
## track once, from its from_point).
static func travel_polyline(world_map: Dictionary, track_id: int, from_point: int) -> Array[Vector2]:
	var entry := track(world_map, track_id)
	var points: Array[Vector2] = []
	for pair in entry.get("polyline", []):
		var xy: Array = pair
		if xy.size() >= 2:
			points.append(Vector2(float(xy[0]), float(xy[1])))
	if int(entry.get("to_point", 0)) == from_point and int(entry.get("from_point", 0)) != from_point:
		points.reverse()
	return points


static func polyline_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


## Where the pre-drawn track sprite (m_trkNNN, decoded with its 0x1C draw origin)
## sits: top-left = from point − draw origin. Checked against the polylines: the
## sprite rectangle encloses every polyline within stroke width for all 44 tracks
## (resource-derived geometry; the original placement code is not located).
static func track_sprite_top_left(world_map: Dictionary, track_id: int) -> Vector2:
	var entry := track(world_map, track_id)
	var sprite: Dictionary = entry.get("sprite", {}) if typeof(entry.get("sprite")) == TYPE_DICTIONARY else {}
	var origin: Array = sprite.get("draw_origin", [0, 0])
	var from_position := point_position(world_map, int(entry.get("from_point", 0)))
	return from_position - Vector2(float(origin[0]), float(origin[1]))


static func marker_kind(state: Dictionary, world_map: Dictionary, point_id: int) -> int:
	match point_type(state, world_map, point_id):
		TOWN:
			return MARKER_KIND_TOWN
		BATTLE:
			return MARKER_KIND_BATTLE
		_:
			return MARKER_KIND_GENERAL


## The event a point opens: the script-assigned value (actBMSetPointEvent /
## teBMSetPointEvent, kept by TownEventRules as point_events[id].event) or the
## record's own +8 value — the file gives every point its id there (SR-069:
## "原文件的 45 个非空点初值均等于点号"), so this is data, not a fallback.
static func point_event(state: Dictionary, world_map: Dictionary, point_id: int) -> int:
	var events: Dictionary = state.get("point_events", {})
	var assigned: Variant = events.get(str(point_id), {})
	if typeof(assigned) == TYPE_DICTIONARY and (assigned as Dictionary).has("event"):
		return int((assigned as Dictionary)["event"])
	return int(point(world_map, point_id).get("id", 0))


## The point's type bit (Town / General / Battle) from its current flags; point
## events replace the type as a group (0x426c70), so at most one is set. "" when
## none.
static func point_type(state: Dictionary, world_map: Dictionary, point_id: int) -> String:
	var flags := point_flags(state, world_map, point_id)
	for candidate in [GENERAL, BATTLE, TOWN]:
		if flags.has(candidate):
			return candidate
	return ""


static func point_visited(state: Dictionary, world_map: Dictionary, point_id: int) -> bool:
	return point_flags(state, world_map, point_id).has(VISIT)


static func town_id_for_point(world_map: Dictionary, point_id: int) -> int:
	for town_value in world_map.get("towns", []):
		if int((town_value as Dictionary).get("point_id", 0)) == point_id:
			return point_id
	return 0


static func town(world_map: Dictionary, town_id: int) -> Dictionary:
	for town_value in world_map.get("towns", []):
		if int((town_value as Dictionary).get("point_id", 0)) == town_id:
			return town_value
	return {}


## What arriving at a point means for the campaign — the original arrival
## handler's branches (static-derived, 0x427ab3..0x427b95, SR-069):
##   event 0                → nothing, whatever the type — a Town included (0x427aca
##                            tests the event before any type bit);
##   General, not visited   → opens level <event>;
##   General, visited       → encounter ratio first (0x458c80(100)+1 ≤ ratio, the
##                            `cmp ratio, r; jl` skip), then level <event> + 0..2;
##   Battle                 → level <event>, + 0..2 once visited (no ratio check);
##   Town                   → enters the town only as the chosen destination.
## Visited is the bmpmVisit bit. `sample` (1..100) and `offset` (0..2) fix the
## dice for tests; -1 rolls. Arrival itself does not mark Visit — visit() does, and
## only for a dispatch that holds (level / town).
static func arrival(state: Dictionary, world_map: Dictionary, point_id: int, selected: bool = true, sample: int = -1, offset: int = -1) -> Dictionary:
	var event := point_event(state, world_map, point_id)
	var flags := point_flags(state, world_map, point_id)
	var visited := flags.has(VISIT)
	var kind := point_type(state, world_map, point_id)
	if event == 0:
		return {"kind": "stop", "point_id": point_id, "reason": "no_event"}
	match kind:
		GENERAL:
			if not visited:
				return {"kind": "level", "level": event, "flag": kind, "point_id": point_id, "visited": false}
			var ratio := int((state.get("encounter_ratios", {}) as Dictionary).get(str(point_id), 0))
			var die := sample if sample >= 1 else int(randi() % 100) + 1
			if ratio <= 0 or die > ratio:
				return {"kind": "stop", "point_id": point_id, "reason": "no_encounter", "ratio": ratio, "sample": die}
			var step := offset if offset >= 0 else int(randi() % 3)
			return {"kind": "level", "level": event + step, "flag": kind, "point_id": point_id, "visited": true, "ratio": ratio, "sample": die, "offset": step}
		BATTLE:
			if not visited:
				return {"kind": "level", "level": event, "flag": kind, "point_id": point_id, "visited": false}
			var step := offset if offset >= 0 else int(randi() % 3)
			return {"kind": "level", "level": event + step, "flag": kind, "point_id": point_id, "visited": true, "offset": step}
		TOWN:
			if not selected:
				return {"kind": "stop", "point_id": point_id, "reason": "passing_town"}
			if town_id_for_point(world_map, point_id) > 0:
				return {"kind": "town", "town_id": town_id_for_point(world_map, point_id), "point_id": point_id}
			return {"kind": "stop", "point_id": point_id, "reason": "town_without_data"}
		_:
			return {"kind": "stop", "point_id": point_id, "reason": "untyped"}


## The party stands at a point: current_point and the stood-at history, no Visit bit
## (a destination whose dispatch does not hold, 0x427d36).
static func stand_at(state: Dictionary, point_id: int) -> Dictionary:
	var next := state.duplicate(true)
	next["current_point"] = point_id
	var visited: Array = next.get("visited_points", [])
	if not visited.has(point_id):
		visited.append(point_id)
	next["visited_points"] = visited
	return next


## The party stands at a point and its bmpmVisit bit is set (the original marks Visit
## on town entry, 0x427b88, and right after the level request, 0x427b54).
static func visit(state: Dictionary, world_map: Dictionary, point_id: int) -> Dictionary:
	var next := stand_at(state, point_id)
	var overrides: Dictionary = next.get("point_flags", {})
	var flags: Array = (overrides.get(str(point_id), point(world_map, point_id).get("flag_names", [])) as Array).duplicate()
	if not flags.has(VISIT):
		flags.append(VISIT)
	overrides[str(point_id)] = flags
	next["point_flags"] = overrides
	return next

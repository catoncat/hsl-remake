extends RefCounted
## Story actors and objects for BattleOpeningCoordinator: the opening-only cast
## (story_actors), actInsertObject／actWalkPrevInsertObject inserts, forward walks
## (absolute／relative／follow／slide), actor deletes, shape overrides, story-object
## sprites and effects and position markers. Bodies moved from
## the coordinator unchanged; the coordinator keeps the records (motion／skipped／story),
## the pacing values, `_pending_deletes` and `_inserted_unit_ids`
## (summary()), and every walk still resolves bindings through
## `coordinator.binding_for_token` so the battle subclass override applies.
## provenance:
##   rules: resource-derived content/imported/hsl/global/tables/ACTION.H
##   rules: static-derived docs/evidence_packets/static_reverse/original_fixpos_fly_prev_insert.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_walk_path.md
##   rules: provisional (follow／slide walk readings)
##   rules: static-derived docs/evidence_packets/static_reverse/original_random_position.md
##   rules: provisional docs/evidence_packets/static_reverse/original_random_position.md
##     (random-position slots in table order instead of the native shuffle)
##   layout: resource-derived content/imported/hsl/chapter01/battle052/opening_timeline.json
##   layout: resource-derived content/imported/hsl/chapter01/map_object_alignment.json
##   layout: provisional
##     (walk start = final cell minus accumulated deltas; engRANGE objects hang from the insert point and unroll over
##     the following actDelay)
##   layout: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   audio: resource-derived content/imported/hsl/chapter01/actor_audio.json

const StoryEffectObjects = preload("res://game/battle/runtime/StoryEffectObjects.gd")
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const ScriptWalkPath = preload("res://game/battle/runtime/opening/ScriptWalkPath.gd")
const WrdTerrainTiles = preload("res://game/battle/runtime/WrdTerrainTiles.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const RangeCellOverlay = preload("res://game/battle/runtime/RangeCellOverlay.gd")

## obj_Story_Show_Pos (process 0x4504d0) steps its I_rect31..38 frame every 6 ticks (words
## 0x479358／0x47935a), where the range-cell drawers step every 8.
const SHOW_POS_FRAME_TICKS := 6

var coordinator: Node
var runtime: Node:
	get:
		return coordinator.runtime
## The last actInsertObject: {unit_id, insert_world, source_event_id, wait_round}
## until its walk token consumes it (object id -1 in later tokens names it too).
var _pending_insert: Dictionary = {}
## The last walk _move_actor started: {start, points, pixels_per_tick} (the camera follow's input).
var _last_walk: Dictionary = {}
var _story_objects: Dictionary = {}
## Effect readings of inserted objects (rain, flashes, fire runs...); see StoryEffectObjects.
var _effects: RefCounted = StoryEffectObjects.new()
var _position_markers: Array[Node2D] = []
## One RangeCellOverlay holds every live marker, so they share one clock (0x4504d0: only the
## first marker, flag 0x10000, advances the frame and pulse); freed with the last marker.
var _position_overlay: RangeCellOverlay = null
var _position_serial: int = 0
## actSetRandomPos slots (script pixels) after the battle's shuffle: the PlayLoop decided
## the slot order once at create (BattleLoopInit._load_opening_story_state, 0x451d0f) and
## placed the bound inserts there; a story scene without a PlayLoop keeps table order.
var _random_slots: Array[Vector2] = []
var _shape_sets: Dictionary = {}
## Story scenes (no PlayLoop): {tiles, map_size} of the scenario terrain for walk routes.
var _story_terrain: Dictionary = {}


static func create(opening_coordinator: Node) -> RefCounted:
	var objects := new()
	objects.coordinator = opening_coordinator
	return objects


## actDeleteShowPosObject: every marker of actInsertShowPosObject leaves the scene.
func _clear_position_markers(event: Dictionary) -> void:
	_position_markers = []
	_release_position_overlay()
	coordinator.story_records.append({"kind": "show_position_marker_clear", "source_event_id": str(event.get("id", ""))})


func _load_shape_sets() -> void:
	## actChangeShape frame sets decoded by tools/hsltools/levels/actors.py (resources.actor_shape_sets).
	_shape_sets = {}
	if runtime == null:
		return
	var manifest_path := str((runtime.first_battle_scenario.get("resources", {}) as Dictionary).get("actor_shape_sets", ""))
	if manifest_path == "" or not FileAccess.file_exists(manifest_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(parsed) == TYPE_DICTIONARY:
		_shape_sets = (parsed as Dictionary).get("sets", {})


func _shape_set_for_member(first_member: String) -> Dictionary:
	for entry_value in _shape_sets.values():
		var entry: Dictionary = entry_value
		var frames: Array = entry.get("frames", [])
		if not frames.is_empty() and str((frames[0] as Dictionary).get("source_member", "")).to_lower() == first_member.to_lower():
			return entry
	return {}


func _walk_events_for_binding() -> Dictionary:
	## unit_id -> accumulated walk delta of every actor_walk_disp_wait token, in world pixels.
	var totals: Dictionary = {}
	for item in runtime.opening_timeline_manifest.get("events", []):
		if typeof(item) != TYPE_DICTIONARY or str(item.get("kind", "")) != "actor_walk_disp_wait":
			continue
		var args: Array = item.get("args", [])
		if args.size() < 4:
			continue
		var binding: Dictionary = coordinator.binding_for_token(str(args[0]), str(args[1]))
		var unit_id := str(binding.get("unit_id", ""))
		if unit_id == "":
			continue
		totals[unit_id] = totals.get(unit_id, Vector2.ZERO) + Vector2(float(str(args[2])), float(str(args[3])))
	return totals


func _prepare_actor_positions() -> void:
	var cleared_inserts: Array[String] = []
	coordinator._inserted_unit_ids = cleared_inserts
	var totals := _walk_events_for_binding()
	for unit_id in totals.keys():
		var actor: Node = runtime.actor_node_for_unit(str(unit_id))
		if actor == null:
			continue
		var target: Vector2 = runtime.actor_world_position_for_grid(runtime.unit_grid_coord(unit_id))
		actor.move_along([target - totals[unit_id]], 0.0)
		actor.play_state("idle", "0")
	for key in coordinator.bindings.keys():
		var binding: Dictionary = coordinator.bindings[key]
		if not binding.has("insert_xy"):
			continue
		var actor: Node = runtime.actor_node_for_unit(str(binding.get("unit_id", "")))
		if actor != null:
			actor.visible = false
	# obj_Story_PlayerN installs the controlled slot mid-opening: the PlayLoop unit
	# behind it stays hidden until its story_object_insert token reveals it there.
	for spec_value in (coordinator.config.get("story_objects", {}) as Dictionary).values():
		if typeof(spec_value) != TYPE_DICTIONARY:
			continue
		var spawn_unit_id := str((spec_value as Dictionary).get("spawns_unit_id", ""))
		var slot_actor: Node = runtime.actor_node_for_unit(spawn_unit_id) if spawn_unit_id != "" else null
		if slot_actor != null:
			slot_actor.visible = false


## actWalkDisp(Wait): `wait_variant` is the Wait form, whose walker the camera follows.
func _start_walk(event: Dictionary, wait_variant: bool = true) -> void:
	var args: Array = event.get("args", [])
	if args.size() < 4:
		return
	var bound := _bound_actor(event, 0)
	var unit_id: String = bound[0]
	var actor: Node = bound[1]
	if actor == null:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_walk_disp_wait", "reason": "unbound_actor"})
		return
	var delta := Vector2(float(str(args[2])), float(str(args[3])))
	var start: Vector2 = _motion_end(actor)
	var target: Vector2 = start + delta
	if not coordinator.story_mode:
		var final_target: Vector2 = runtime.actor_world_position_for_grid(runtime.unit_grid_coord(unit_id))
		if target.distance_to(final_target) < 1.0:
			target = final_target
	_move_actor(actor, unit_id, start, target, str(event.get("id", "")), str(event.get("source_token", "")), _speed_arg(args, 4))
	coordinator._block_on(unit_id)
	coordinator.cinematics._focus_camera_on_unit(unit_id, false, str(event.get("id", "")))
	if wait_variant:
		_camera_follows_last_walk()


## The script speed argument (0 → the default speed 4); missing → 0.
static func _speed_arg(args: Array, index: int) -> float:
	return float(str(args[index]).to_int()) if args.size() > index else 0.0


func _insert_object(event: Dictionary) -> void:
	## Inserts are bound per header symbol in script order ("<symbol>/insertN", the
	## scenario generator's numbering): STORY006 inserts three Enemy23 and then one
	## Enemy24, so the count must not mix symbols.
	var args: Array = event.get("args", [])
	var symbol := str(args[0]) if not args.is_empty() else ""
	var insert_index := 0
	for record in coordinator.motion_records:
		if str(record.get("kind", "")) == "object_insert" and str(record.get("symbol", "")) == symbol:
			insert_index += 1
	for record in coordinator.skipped_records:
		if str(record.get("kind", "")) == "object_insert" and str(record.get("symbol", "")) == symbol:
			insert_index += 1
	var binding: Dictionary = coordinator.bindings.get("%s/insert%d" % [symbol, insert_index + 1], {})
	var unit_id := str(binding.get("unit_id", ""))
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	if actor == null and coordinator.story_mode and unit_id != "" and args.size() >= 3:
		# Story scenes have no PlayLoop unit behind the insert: spawn the bound
		# script actor at the off-map insert pixel (cell origin, like EVEF placements).
		actor = runtime.stage.spawn_actor_node(unit_id, str(binding.get("actor_id", "")), _story_world([args[1], args[2]]), runtime.stage.carried_unit_view(unit_id, str(binding.get("actor_id", ""))))
	if actor == null and args.size() >= 3 and (coordinator.config.get("story_objects", {}) as Dictionary).has(symbol):
		# An actInsertObject of an enemy-process object without walk frames (STORY018's
		# obj_Story_Level_Door 18_DOOR01): a static sprite, like the EVEF static_enemy_object
		# placements — drawn through the story-object path instead of spawning an actor.
		_pending_insert = {}
		_insert_story_object(event)
		return
	if actor == null or args.size() < 3:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "object_insert", "symbol": symbol, "reason": "unbound_insert"})
		_pending_insert = {}
		return
	var insert_world := Vector2(float(str(args[1])), float(str(args[2])))
	actor.move_along([insert_world], 0.0)
	actor.play_state("idle", "0")
	actor.visible = true
	coordinator._inserted_unit_ids.append(unit_id)
	_pending_insert = {"unit_id": unit_id, "insert_world": insert_world, "source_event_id": str(event.get("id", "")), "wait_round": 0}
	coordinator.motion_records.append({"kind": "object_insert", "symbol": symbol, "unit_id": unit_id, "insert_world": insert_world, "source_event_id": str(event.get("id", ""))})
	coordinator.cinematics._keep_inserted_actor_in_view(unit_id, str(event.get("id", "")))


func _set_random_slots(event: Dictionary) -> void:
	## actSetRandomPos,num,x1,y1,...: up to five slots (0x451d0f).
	var args: Array = event.get("args", [])
	_random_slots.clear()
	var count := mini(str(args[0]).to_int(), 5) if not args.is_empty() else 0
	for index in range(count):
		if args.size() > 2 + index * 2:
			_random_slots.append(Vector2(float(str(args[1 + index * 2])), float(str(args[2 + index * 2]))))
	var order: Array = runtime.play_loop.get("opening_story_state", {}).get("random_slot_order", []) if not runtime.play_loop.is_empty() else []
	if order.size() == _random_slots.size():
		var table := _random_slots.duplicate()
		for index in range(order.size()):
			_random_slots[index] = table[int(order[index])]


## The slot a random-position token names as a synthetic absolute event: `[x, y] + tail`
## for camera／delete tokens (slot id first), `[code, x + dx, y + dy]` for inserts
## ([code][dx][dy][slot], 0x450f2c). {} when the slot was never set.
func random_slot_event(event: Dictionary, insert: bool) -> Dictionary:
	var args: Array = event.get("args", [])
	var slot_index := str(args[3 if insert else 0]).to_int() if args.size() > (3 if insert else 0) else -1
	if slot_index < 0 or slot_index >= _random_slots.size():
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": str(event.get("kind", "")), "reason": "random_slot_unset"})
		return {}
	var slot: Vector2 = _random_slots[slot_index]
	var resolved := event.duplicate(true)
	if insert:
		resolved["args"] = [args[0], str(int(slot.x) + str(args[1]).to_int()), str(int(slot.y) + str(args[2]).to_int())]
	else:
		resolved["args"] = [str(int(slot.x)), str(int(slot.y))] + args.slice(1)
	return resolved


func _insert_random_object(event: Dictionary) -> void:
	## actInsertObjectRandomPos: the bound guardian (`<symbol>/insertN`, insert order per
	## symbol like _insert_object) appears at slot + disp — the cell the assembly placed it in.
	var resolved := random_slot_event(event, true)
	if resolved.is_empty():
		return
	var symbol := str(resolved["args"][0])
	var insert_index := 0
	for record in coordinator.motion_records:
		if str(record.get("kind", "")) == "object_insert_random_position" and str(record.get("symbol", "")) == symbol:
			insert_index += 1
	var binding: Dictionary = coordinator.bindings.get("%s/insert%d" % [symbol, insert_index + 1], {})
	var unit_id := str(binding.get("unit_id", ""))
	# The shuffled slot + disp, on the cell the constructor centres it in (v & ~31) — the
	# cell the PlayLoop placed the unit on.
	var world := _story_world([int(resolved["args"][1]) & ~31, int(resolved["args"][2]) & ~31])
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	if actor == null and coordinator.story_mode and unit_id != "":
		actor = runtime.stage.spawn_actor_node(unit_id, str(binding.get("actor_id", "")), world, runtime.stage.carried_unit_view(unit_id, str(binding.get("actor_id", ""))))
	if actor == null:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "object_insert_random_position", "symbol": symbol, "reason": "unbound_insert"})
		return
	actor.move_along([world], 0.0)
	actor.play_state("idle", "0")
	actor.visible = true
	coordinator._inserted_unit_ids.append(unit_id)
	coordinator.motion_records.append({"kind": "object_insert_random_position", "symbol": symbol, "unit_id": unit_id, "insert_world": world, "source_event_id": str(event.get("id", ""))})


func _walk_inserted_object(event: Dictionary, blocking: bool = true) -> void:
	## actWalkPrevInsertObject(Wait),x,y,speed: the last inserted object walks to the
	## script pixel; the Wait form blocks the script until it arrives, the plain form
	## (STORY006's soldiers) lets the next token run like actWalk versus actWalkWait.
	if _pending_insert.is_empty():
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": str(event.get("kind", "")), "reason": "no_pending_insert"})
		return
	var unit_id := str(_pending_insert.get("unit_id", ""))
	var actor: Node = runtime.actor_node_for_unit(unit_id)
	if actor == null:
		_pending_insert = {}
		return
	# The script pixel target is preserved in the token; the presentation lands on
	# the PlayLoop cell that the scenario generator derived from that same target.
	# Story scenes have no PlayLoop cell and walk to the script pixel itself.
	var args: Array = event.get("args", [])
	var target: Vector2 = _story_world([args[0], args[1]]) if coordinator.story_mode and args.size() >= 2 else runtime.actor_world_position_for_grid(runtime.unit_grid_coord(unit_id))
	_move_actor(actor, unit_id, actor.position, target, str(event.get("id", "")), str(event.get("source_token", "")), _speed_arg(args, 2))
	coordinator.cinematics._focus_camera_on_unit(unit_id, false, str(event.get("id", "")))
	if blocking:
		_camera_follows_last_walk()
		coordinator._block_on(unit_id)
	else:
		coordinator.wait_remaining = coordinator.default_step_seconds
		coordinator._blocking_motion = false
	_pending_insert = {}


func _spawn_story_actors() -> void:
	## Cast from EVEF placements; script/EVEF pixels are 32px cell origins, so actors
	## stand at the cell centre exactly like PlayLoop units in the battle scenes.
	## Story-only scenes have no PlayLoop unit behind a cast member, so the hand-off
	## carry supplies a member's job-up row (runtime.stage.carried_unit_view): a 劍豪 walks
	## the camp in the 010 frames, as in the battles.
	## In a battle opening the same list holds the opening-only cast: entries that
	## are PlayLoop units are skipped, and nobody here joins the grid map, so
	## _finish neither snaps nor re-shows an actor the script deleted.
	for entry_value in runtime.first_battle_scenario.get("story_actors", []):
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var unit_id := str(entry.get("id", ""))
		var xy: Array = entry.get("placement_xy", [])
		var coord: Array = entry.get("coord", [])
		if unit_id == "" or xy.size() != 2:
			continue
		if not coordinator.story_mode and runtime.unit_grid_coords.has(unit_id):
			continue
		if coordinator.story_mode and coord.size() == 2:
			runtime.unit_grid_coords[unit_id] = Vector2i(int(coord[0]), int(coord[1]))
		var world := _story_world(xy)
		var actor: Node = runtime.actor_node_for_unit(unit_id)
		if actor == null:
			actor = runtime.stage.spawn_actor_node(unit_id, str(entry.get("actor_id", "")), world, runtime.stage.carried_unit_view(unit_id, str(entry.get("actor_id", ""))))
		actor.move_along([world], 0.0)
		actor.play_state("idle", "0")
		actor.visible = true


## A story object (stand sprite or effect) stands on the script pixel itself, like the EVEF
## stand objects MapObjectPlacement draws at their raw anchor minus the SHP draw origin (the
## original rounds only actors to their cell: 0x407cc0); STORY010 inserts 樹03 at the anchor
## of the 樹02 it deleted, WINFAIL028 its torch fire at the torch it removed.
func _object_world(xy: Array) -> Vector2:
	return Vector2(float(str(xy[0])), float(str(xy[1])))


func _story_world(xy: Array) -> Vector2:
	var cell_size: Vector2 = runtime.map_config.grid_projection["cell_size"] if runtime.map_config != null else Vector2(32, 32)
	return Vector2(float(str(xy[0])), float(str(xy[1]))) + cell_size * 0.5


func _motion_end(actor: Node) -> Vector2:
	## Where a (possibly still walking) actor will stand: chained script tokens
	## measure from the previous target, not from the mid-walk position.
	if actor.is_moving() and not actor.last_path.is_empty():
		return actor.last_path[actor.last_path.size() - 1]
	return actor.position


func _bound_actor(event: Dictionary, token_index: int) -> Array:
	var args: Array = event.get("args", [])
	if args.size() < token_index + 2:
		return ["", null]
	if str(args[token_index]) == "-1":
		# Object id -1 names the object inserted last (STORY013 / winfail015 / 021:
		# actInsertObject … actWalkDispWait(-1,1,…) right after each insert, 51 uses in
		# the PAK scripts — a static reading of the script pattern, the handler is not
		# located). Resolved like actWalkPrevInsertObject to the pending insert.
		var last_unit := str(_pending_insert.get("unit_id", ""))
		return [last_unit, runtime.actor_node_for_unit(last_unit) if last_unit != "" else null]
	var binding: Dictionary = coordinator.binding_for_token(str(args[token_index]), str(args[token_index + 1]))
	var unit_id := str(binding.get("unit_id", ""))
	return [unit_id, runtime.actor_node_for_unit(unit_id)]


## actDeleteObject on an EVEF enemy-process object drawn as a stand sprite (no walk
## frames: STORY018's 門1 SID_ENEMY100, a static_enemy_object placement): the n-th
## placement carrying that obj_Data6 token is hidden. Returns false when no such
## placement exists so the caller records the skip.
func _hide_static_object(event: Dictionary) -> bool:
	var args: Array = event.get("args", [])
	if args.size() < 2:
		return false
	var token := str(args[0])
	var wanted := int(str(args[1]))
	var seen := 0
	for item in runtime.map_objects_manifest.get("placements", []):
		if typeof(item) != TYPE_DICTIONARY or str((item as Dictionary).get("role", "")) != "static_enemy_object":
			continue
		var record: Dictionary = item
		if runtime.stage.map_object_field_value(record, "obj_Data6") != token:
			continue
		seen += 1
		if seen != wanted:
			continue
		var node_name: String = runtime.stage.map_object_node_name(record)
		for layer in [runtime.map_objects_back, runtime.map_objects_foreground]:
			var node: Node = layer.get_node_or_null(node_name) if layer != null else null
			if node != null:
				node.visible = false
				coordinator.story_records.append({"kind": "map_object_deleted", "source_event_id": str(event.get("id", "")), "token": token, "instance": wanted, "record_index": int(record.get("record_index", -1)), "node": node_name})
				return true
	return false


func _walk_absolute(event: Dictionary, blocking: bool, delete_after: bool) -> void:
	var args: Array = event.get("args", [])
	var bound := _bound_actor(event, 0)
	var unit_id: String = bound[0]
	var actor: Node = bound[1]
	if actor == null or args.size() < 4:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": str(event.get("kind", "")), "reason": "unbound_actor"})
		return
	var start: Vector2 = _motion_end(actor)
	var target := _story_world([args[2], args[3]])
	_move_actor(actor, unit_id, start, target, str(event.get("id", "")), str(event.get("source_token", "")), _speed_arg(args, 4))
	if blocking and not delete_after:
		_camera_follows_last_walk()
	if blocking:
		coordinator._block_on(unit_id)
	else:
		coordinator.wait_remaining = coordinator.default_step_seconds
		coordinator._blocking_motion = false
	if delete_after:
		coordinator._pending_deletes.append(unit_id)


func _walk_relative(event: Dictionary, blocking: bool) -> void:
	_start_walk(event, blocking)
	if not blocking:
		coordinator.wait_remaining = coordinator.default_step_seconds
		coordinator._blocking_motion = false


func _walk_follow(event: Dictionary, blocking: bool) -> void:
	## actWalkFollow(follower, inst, leader, inst, offset): the follower walks to the
	## leader's destination keeping its offset from the leader's start (remake reading;
	## the original follow rule is unresolved).
	var follower := _bound_actor(event, 0)
	var leader := _bound_actor(event, 2)
	var follower_actor: Node = follower[1]
	var leader_actor: Node = leader[1]
	if follower_actor == null or leader_actor == null:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": str(event.get("kind", "")), "reason": "unbound_actor"})
		return
	var leader_start: Vector2 = leader_actor.last_path[0] if leader_actor.is_moving() and not leader_actor.last_path.is_empty() else leader_actor.position
	var offset: Vector2 = _motion_end(follower_actor) - leader_start
	var target: Vector2 = _motion_end(leader_actor) + offset
	_move_actor(follower_actor, follower[0], _motion_end(follower_actor), target, str(event.get("id", "")), str(event.get("source_token", "")))
	if blocking:
		coordinator._block_on(str(follower[0]))
	else:
		coordinator.wait_remaining = coordinator.default_step_seconds
		coordinator._blocking_motion = false


func _insert_story_object(event: Dictionary) -> void:
	var args: Array = event.get("args", [])
	var symbol := str(args[0]) if not args.is_empty() else ""
	var objects: Dictionary = coordinator.config.get("story_objects", {})
	var spec: Dictionary = objects.get(symbol, {})
	if str(spec.get("kind", "")) == "shapeless_no_draw" and args.size() >= 3:
		coordinator.story_records.append({"kind": "story_object_insert", "source_event_id": str(event.get("id", "")), "symbol": symbol, "anchor_world": _object_world([args[1], args[2]]), "status": "shapeless_no_draw"})
		return
	var spawn_unit_id := str(spec.get("spawns_unit_id", ""))
	if spawn_unit_id != "" and args.size() >= 3:
		# obj_Story_PlayerN: the controlled slot is installed at the insert point;
		# the preview spawns the bound actor there (no PlayLoop in a story scene).
		var world := _story_world([args[1], args[2]])
		var actor: Node = runtime.actor_node_for_unit(spawn_unit_id)
		if actor == null:
			actor = runtime.stage.spawn_actor_node(spawn_unit_id, str(spec.get("actor_id", "")), world, runtime.stage.carried_unit_view(spawn_unit_id, str(spec.get("actor_id", ""))))
		actor.move_along([world], 0.0)
		actor.play_state("idle", "0")
		actor.visible = true
		coordinator.story_records.append({"kind": "story_object_insert", "source_event_id": str(event.get("id", "")), "symbol": symbol, "anchor_world": world, "spawned_unit_id": spawn_unit_id})
		coordinator.cinematics._keep_inserted_actor_in_view(spawn_unit_id, str(event.get("id", "")))
		return
	var preview := str(spec.get("preview", ""))
	if args.size() < 3 or preview == "" or not ResourceLoader.exists(preview):
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "story_object_insert", "reason": "unbound_story_object"})
		return
	if StoryEffectObjects.effect_kind(spec) != "":
		# Rain controllers, background sounds, fire runs, flashes and glows: one instance
		# per insert (STORY010 inserts 火01 five times), records kept by the effects object.
		coordinator.story_records.append(_effects.insert(runtime, coordinator, spec, objects, symbol, _object_world([args[1], args[2]]), str(event.get("id", ""))))
		return
	var sprite: Sprite2D = _story_objects.get(symbol)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "StoryObject_" + symbol
		sprite.centered = false
		sprite.texture = load(preview)
		runtime.world_root.add_child(sprite)
		_story_objects[symbol] = sprite
	var origin: Array = spec.get("draw_origin", [0, 0])
	var anchor := _object_world([args[1], args[2]])
	sprite.position = anchor - Vector2(float(origin[0]), float(origin[1]))
	sprite.z_index = int(anchor.y)
	sprite.visible = true
	var record := {"kind": "story_object_insert", "source_event_id": str(event.get("id", "")), "symbol": symbol, "anchor_world": anchor}
	if str((spec.get("object_fields", {}) as Dictionary).get("obj_Mode", "")) == "engRANGE":
		record.merge(_unroll_range_object(sprite, anchor, origin))
	coordinator.story_records.append(record)


## A defProcObjectMove object drawn with engRANGE (STORY053's 繩子 53_ROPE001, 8×241, draw
## origin at its bottom): the remake hangs it from the insert point and lets it unroll
## downward over the script's following actDelay (80 ticks in STORY053), so the rope reaches
## the ground 緹娜 then slides down to. Provisional remake reading: the object process
## (0x4051d0) and the engRANGE blit are unread, and no original frame of this moment is
## recorded; replace with a frame capture of the level-53 opening.
func _unroll_range_object(sprite: Sprite2D, anchor: Vector2, origin: Array) -> Dictionary:
	var size: Vector2 = sprite.texture.get_size()
	sprite.position = Vector2(anchor.x - float(origin[0]), anchor.y)
	sprite.z_index = int(anchor.y + size.y)
	sprite.region_enabled = true
	var timeline: RefCounted = runtime.scene_timeline
	var next: Dictionary = timeline.events[timeline.current_index + 1] if timeline.current_index + 1 < timeline.events.size() else {}
	var ticks := int(str((next.get("args", ["0"]) as Array)[0]).to_int()) if str(next.get("kind", "")) == "opening_delay" and not (next.get("args", []) as Array).is_empty() else 0
	var seconds := OriginalTick.seconds(ticks) if ticks > 0 else 0.0
	var reveal := func(length: float) -> void:
		if is_instance_valid(sprite):
			sprite.region_rect = Rect2(0.0, size.y - length, size.x, length)
	if seconds <= 0.0:
		reveal.call(size.y)
	else:
		reveal.call(0.0)
		coordinator.create_tween().tween_method(reveal, 0.0, size.y, seconds)
	return {"presentation": "range_unroll", "hang_top_world": sprite.position, "unroll_seconds": seconds}


func _change_shape(event: Dictionary) -> void:
	## actChangeShape,token,inst,?,first_member,count: swap the actor's frames for
	## the decoded script shape set that starts at first_member.
	var args: Array = event.get("args", [])
	var bound := _bound_actor(event, 0)
	var actor: Node = bound[1]
	var first_member := str(args[3]) if args.size() > 3 else ""
	var entry := _shape_set_for_member(first_member)
	if actor == null or entry.is_empty():
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_shape_change", "reason": "unbound_actor" if actor == null else "shape_set_not_imported"})
		return
	var loaded: int = actor.set_shape_override(entry.get("frames", []))
	coordinator.story_records.append({"kind": "actor_shape_change", "source_event_id": str(event.get("id", "")), "unit_id": bound[0], "first_member": first_member, "frames_loaded": loaded})


func _restore_shape(event: Dictionary) -> void:
	var bound := _bound_actor(event, 0)
	var actor: Node = bound[1]
	if actor == null:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_shape_restore", "reason": "unbound_actor"})
		return
	actor.clear_shape_override()
	coordinator.story_records.append({"kind": "actor_shape_restore", "source_event_id": str(event.get("id", "")), "unit_id": bound[0]})


func _move_disp(event: Dictionary) -> void:
	## actMoveDispWait,token,inst,dx,dy,speed: pixel slide (no footsteps) at the
	## script speed read as pixels per original frame; blocking.
	var args: Array = event.get("args", [])
	var bound := _bound_actor(event, 0)
	var unit_id: String = bound[0]
	var actor: Node = bound[1]
	if actor == null or args.size() < 4:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_move_disp_wait", "reason": "unbound_actor"})
		return
	var delta := Vector2(float(str(args[2])), float(str(args[3])))
	var speed := maxf(float(str(args[4]).to_int()), 1.0) if args.size() > 4 else 2.0
	var start: Vector2 = _motion_end(actor)
	var target: Vector2 = start + delta
	var seconds: float = delta.length() / (speed * coordinator.move_pixels_per_frame_hz)
	actor.move_along([start, target], seconds, true)
	coordinator.wait_remaining = seconds
	coordinator._block_on(unit_id)
	coordinator.motion_records.append({"kind": "move_disp", "unit_id": unit_id, "source_event_id": str(event.get("id", "")), "source_token": str(event.get("source_token", "")),
		"start_world": start, "target_world": target, "duration_seconds": seconds, "speed_arg": speed})
	coordinator.cinematics._focus_camera_on_unit(unit_id, false, str(event.get("id", "")))


func _show_position_marker(event: Dictionary) -> void:
	## actInsertShowPosObject,x,y (opcode 58, 0x450d4b → 0x45e307(x,y,702)) inserts
	## obj_Story_Show_Pos; its process 0x4504d0 draws the cell holding (x,y) (x&~31, y&~31)
	## on planeMenu1 in the magic range-cell look: ICONBOX averaged with ramp 0x479344 (the
	## magic ramp 0x476c1c) under I_rect31..38. The first marker restarts the frame timer.
	var args: Array = event.get("args", [])
	if args.size() < 2:
		return
	var script_pixel := Vector2(float(str(args[0])), float(str(args[1])))
	var cell_rect := _show_position_cell(script_pixel)
	if _position_overlay == null or not is_instance_valid(_position_overlay):
		_position_overlay = RangeCellOverlay.new()
		_position_overlay.name = "ShowPosOverlay"
		_position_overlay.frame_ticks = SHOW_POS_FRAME_TICKS
		_position_overlay.z_index = 4000
		runtime.world_root.add_child(_position_overlay)
	var prefix := "ShowPosMarker_%d_" % _position_serial
	var rects: Array[Rect2] = [cell_rect]
	_position_overlay.add_cells(prefix, rects, "magic")
	var marker: Node2D = _position_overlay.get_node(prefix + "00")
	marker.name = "ShowPosMarker_%d" % _position_serial
	_position_serial += 1
	marker.set_meta("script_pixel", script_pixel)
	marker.set_meta("cell_origin", cell_rect.position)
	_position_markers.append(marker)
	coordinator.story_records.append({"kind": "show_position_marker", "source_event_id": str(event.get("id", "")), "cell_origin": cell_rect.position, "script_pixel": script_pixel})


func _show_position_cell(script_pixel: Vector2) -> Rect2:
	var map_config = runtime.map_config
	if map_config != null:
		return Rect2(map_config.grid_to_world(map_config.world_to_grid(script_pixel)), map_config.grid_projection["cell_size"])
	return Rect2(Vector2(float(int(script_pixel.x) & ~31), float(int(script_pixel.y) & ~31)), Vector2(32, 32))


func _release_position_overlay() -> void:
	if _position_overlay != null and is_instance_valid(_position_overlay):
		_position_overlay.queue_free()
	_position_overlay = null


## The Wait walks (actWalkWait／actWalkDispWait／actWalkPrevInsertObjectWait: 0x44fcf0／0x44fd90／
## 0x44fed0 store the VM pointer at +0x50) walk in 0x453b90 state 0x32, whose sub 3／6 request the
## walker's step for the camera (0x453fbd..0x454039): the camera follows the walk just started,
## from wherever the walk-start focus left it. The plain forms leave the camera alone there.
func _camera_follows_last_walk() -> void:
	if runtime.camera_controller != null and not _last_walk.is_empty():
		runtime.camera_controller.follow_walk(_last_walk["start"], _last_walk["points"], _last_walk["pixels_per_tick"])


## `speed_arg` is the script's speed argument (0x4543d8: 1／2／2／4／8 px per tick, 0 → 4);
## the coordinator's walk_pixels_per_second is the speed-4 rate. The actor steps cell by
## cell along ScriptWalkPath.route over the scene terrain (the original path buffer),
## never straight through walls; the duration follows the walked length.
func _move_actor(actor: Node, unit_id: String, start: Vector2, target: Vector2, source_event_id: String, source_token: String, speed_arg: float = 0.0) -> void:
	var speed: float = coordinator.walk_pixels_per_tick(int(speed_arg))
	var terrain := _walk_terrain()
	var route: Dictionary = ScriptWalkPath.route(terrain["tiles"], terrain["map_size"], start, target, terrain["cell_size"], _unit_flies(unit_id))
	var points: Array = route["points"]
	var seconds: float = ScriptWalkPath.length(start, points) / (coordinator.walk_pixels_per_second * speed / coordinator.DEFAULT_WALK_SPEED)
	var result: Dictionary = actor.move_along([start] + points, seconds, true)
	# The follow's step covers the same length per tick as the walk (speed px per tick at the
	# production pacing; a harness that raises walk_pixels_per_second scales both).
	_last_walk = {"start": start, "points": points, "pixels_per_tick": speed * coordinator.walk_pixels_per_second / coordinator.DEFAULT_WALK_SPEED * OriginalTick.TICK_SECONDS}
	coordinator.wait_remaining = seconds
	coordinator.motion_records.append({
		"kind": "walk",
		"unit_id": unit_id,
		"source_event_id": source_event_id,
		"source_token": source_token,
		"start_world": start,
		"target_world": target,
		"end_world": points[points.size() - 1] if not points.is_empty() else start,
		"route_status": route["status"],
		"route_cells": route["cells"],
		"duration_seconds": seconds,
		"speed_arg": speed_arg,
		"path_point_count": result.get("path_point_count", 0),
		"uses_frame_sequence": result.get("uses_frame_sequence", false),
	})


## The terrain script walks route over: the PlayLoop's map (with mid-battle edits) in a battle, the scenario's
## WRD terrain in a story scene (loaded once per scene).
func _walk_terrain() -> Dictionary:
	var cell_size: Vector2 = runtime.map_config.grid_projection["cell_size"] if runtime.map_config != null else Vector2(32, 32)
	if runtime.play_loop.has("tiles"):
		return {"tiles": TerrainEditRules.tiles(runtime.play_loop), "map_size": runtime.play_loop.get("map_size", Vector2i.ZERO), "cell_size": cell_size}
	if _story_terrain.is_empty():
		var path := str((runtime.first_battle_scenario.get("resources", {}) as Dictionary).get("terrain", ""))
		var loaded: Dictionary = WrdTerrainTiles.load_tiles(path) if path != "" else {}
		_story_terrain = {"tiles": loaded.get("tiles", {}) if bool(loaded.get("ok", false)) else {}, "map_size": loaded.get("map_size", Vector2i.ZERO)}
	return {"tiles": _story_terrain["tiles"], "map_size": _story_terrain["map_size"], "cell_size": cell_size}


func _unit_flies(unit_id: String) -> bool:
	for unit in runtime.play_loop.get("units", []):
		if typeof(unit) == TYPE_DICTIONARY and str(unit.get("id", "")) == unit_id:
			return bool((unit.get("traversal", {}) as Dictionary).get("flying", false))
	return false


func _delete_bound_actor(event: Dictionary) -> void:
	## actDeleteObject,code,serial: the bound actor leaves the scene now. Presentation
	## only: the node is stopped and hidden; PlayLoop rosters are untouched and battle
	## scenes re-show every unit at first control.
	var bound := _bound_actor(event, 0)
	var unit_id: String = bound[0]
	var actor: Node = bound[1]
	if actor == null:
		if _hide_static_object(event):
			return
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "actor_delete", "reason": "unbound_actor"})
		return
	if actor.is_moving():
		actor.move_along([_motion_end(actor)], 0.0)
	actor.play_state("idle", "0")
	var departure = runtime.get_node_or_null("DepartureView") if coordinator.cutscene_mode and not coordinator.story_mode else null
	if departure == null or not departure.begin(unit_id): actor.visible = false
	coordinator._pending_deletes.erase(unit_id)
	coordinator.story_records.append({"kind": "actor_deleted", "unit_id": unit_id, "source_event_id": str(event.get("id", "")), "source_kind": "actor_delete"})


## The stand objects (map_objects.json sprites) an opening position delete removes: EVEF
## anchor within `radius` map pixels of `anchor`. Shared with the entries that skip the
## opening (BattleSceneRuntime.apply_opening_object_deletes). Returns the hidden node names.
static func hide_stand_objects(scene: Node, anchor: Vector2, radius: float, proc_code: String) -> Array[String]:
	var removed: Array[String] = []
	if proc_code != "" and proc_code != "defProcStandObject":
		return removed
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		if layer == null:
			continue
		for child in layer.get_children():
			if not (child is CanvasItem) or not child.visible or not child.has_meta("candidate_anchor_world"):
				continue
			var candidate: Vector2 = child.get_meta("candidate_anchor_world")
			if candidate.distance_to(anchor) <= radius:
				child.visible = false
				removed.append(str(child.name))
	return removed


func _delete_position_objects(event: Dictionary) -> void:
	## actDeletePosObject,x,y,range,proc_code: hide the stand objects (defProcStandObject
	## sprites spawned from map_objects.json) whose EVEF anchor lies within `range`
	## map pixels of (x,y), and drop position markers there. Scripts pair it with an
	## exact anchor and range 2/8 before inserting a story object in the same place;
	## the range unit and which processes the selector reaches are provisional.
	var args: Array = event.get("args", [])
	if args.size() < 2:
		coordinator.skipped_records.append({"source_event_id": str(event.get("id", "")), "kind": "position_object_delete", "reason": "missing_args"})
		return
	var anchor := Vector2(float(str(args[0])), float(str(args[1])))
	var radius := maxf(float(str(args[2]).to_int()), 0.0) if args.size() > 2 else 0.0
	var proc_code := str(args[3]) if args.size() > 3 else ""
	var removed: Array[String] = hide_stand_objects(runtime, anchor, radius, proc_code)
	var remaining: Array[Node2D] = []
	for marker in _position_markers:
		if (marker.get_meta("script_pixel") as Vector2).distance_to(anchor) <= radius:
			removed.append(str(marker.name))
			marker.queue_free()
		else:
			remaining.append(marker)
	_position_markers = remaining
	if _position_markers.is_empty():
		_release_position_overlay()
	coordinator.story_records.append({"kind": "position_object_delete", "source_event_id": str(event.get("id", "")), "anchor": anchor, "range": radius, "proc_code": proc_code, "removed": removed, "status": "removed" if not removed.is_empty() else "no_match"})

extends RefCounted
## Read-only rendering of already-committed script actor transactions. No game
## actor, reward, resource, learned skill or random stream is initialized here.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_script_entry.md
##     (no entry state: the insert appears at its landing; walking in is the script's own walk rows)
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_wait.md


static func attach(runtime: Node, events: Array, firing: int) -> Array:
	var records: Array = runtime.play_loop.get("script_actor_transactions", [])
	if firing < 0 or firing >= records.size(): return events
	var result := events.duplicate(true)
	var by_index := {}
	for row in records[firing]["actions"]: by_index[int(row["source_index"])] = row
	for event in result:
		var row: Dictionary = by_index.get(int(event.get("source_action_index", -1)), {})
		if not row.is_empty(): event["script_actor_receipt"] = row.duplicate(true)
	return result


static func pending_firing(runtime: Node, firing: int) -> bool:
	if firing >= runtime.script_cutscene_consumed: return true
	var coordinator: Node = runtime.opening_coordinator
	return coordinator != null and coordinator.active and coordinator.cutscene_mode and not coordinator.story_mode and firing == runtime.script_cutscene_consumed - 1


static func defer_spawn(runtime: Node, actor: Dictionary) -> bool:
	return actor.has("script_creation") and pending_firing(runtime, int(actor["script_creation"]["firing_index"]))


static func holds_actor(runtime: Node, id: String) -> bool:
	for record in runtime.play_loop.get("script_actor_transactions", []):
		if not pending_firing(runtime, int(record["firing_index"])): continue
		if record["created_ids"].has(id): return true
		for row in record["actions"]:
			if row.get("motion", {}).get("unit_id") == id: return true
	return false


static func apply_event(coordinator: Node, event: Dictionary) -> bool:
	if not coordinator.cutscene_mode or coordinator.story_mode or not event.has("script_actor_receipt"): return false
	var row: Dictionary = event["script_actor_receipt"]
	var runtime: Node = coordinator.runtime
	if not row.has("install") and not row.has("motion") and not row.has("departure") and not row.get("missing_actor", false): return false
	coordinator.wait_remaining = 0.0
	coordinator._blocking_motion = false
	coordinator._blocking_unit_id = ""
	coordinator.cinematics._set_title_visible(false)
	runtime.opening_overlay.clear_message()
	if row.get("missing_actor", false):
		coordinator.story_records.append({"kind": "script_actor_absent", "source_event_id": event["id"]})
		return true
	if row.has("install"):
		var install: Dictionary = row["install"]
		var unit: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, install["unit_id"])
		# A unit this same chain inserts and later walks out (WINFAIL051's messenger) is
		# already departed in the PlayLoop; it is still revealed for its walk and line.
		if unit.is_empty() or unit.get("defeated", false) or (unit.get("departed", false) and not runtime.ScriptPresentation.retain_actor(runtime, unit)): return true
		var actor: Node = runtime.actor_node_for_unit(install["unit_id"])
		var point: Vector2 = Vector2(install["position"]) + Vector2(16, 16)
		if actor == null: actor = runtime.stage.spawn_actor_node(install["unit_id"], unit["actor_id"], point, unit)
		if install["created"]: actor.move_along([point], 0.0)
		actor.show()
		coordinator.story_records.append({"kind": "script_actor_revealed", "source_event_id": event["id"], "unit_id": unit["id"], "created": install["created"]})
		coordinator.cinematics._keep_inserted_actor_in_view(unit["id"], event["id"])
		return true
	var id := str(row.get("motion", row.get("departure", {})).get("unit_id", ""))
	var actor: Node = runtime.actor_node_for_unit(id)
	if actor == null: return true
	if row.has("motion"):
		var motion: Dictionary = row["motion"]
		var point: Vector2 = Vector2(motion["to"]) + Vector2(16, 16)
		# The token's speed argument: actWalkPrevInsertObject*(x, y, speed) vs actWalk*(code, serial, x, y, speed).
		var speed_index := 2 if str(row["name"]).begins_with("actWalkPrevInsertObject") else 4
		coordinator.story_objects._move_actor(actor, id, coordinator.story_objects._motion_end(actor), point, event["id"], event.get("source_token", ""), coordinator.story_objects._speed_arg(event.get("args", []), speed_index))
		coordinator.cinematics._focus_camera_on_unit(id, false, event["id"])
		if str(row["name"]).ends_with("Wait"): coordinator._block_on(id)
		else: coordinator.wait_remaining = coordinator.default_step_seconds
	if row.has("departure"):
		if row.has("motion"):
			if not coordinator._pending_deletes.has(id): coordinator._pending_deletes.append(id)
		else:
			var view: Node = runtime.get_node_or_null("DepartureView")
			if view == null or not view.begin(id): actor.hide()
	return true

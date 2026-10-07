extends "res://game/battle/runtime/BattleOpeningCoordinator.gd"
## Battle-only binding adapter; the shared story/world coordinator is unchanged.
## Re-arming the same script may select another registered instance of a code.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_wait.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_check_targets.md
##   rules: provisional (re-arming may pick another registered instance)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
const BattlePoisonGasPresentation = preload("res://game/battle/scene/BattlePoisonGasPresentation.gd")
const BattleDropLightningPresentation = preload("res://game/battle/scene/BattleDropLightningPresentation.gd")
var _wait_actor_id := ""

func _apply_event(event: Dictionary) -> void:
	_wait_actor_id = ""
	if runtime.ScriptActorsPresentation.apply_event(self, event): return
	if not story_mode and event.has("poison_gas"):
		# The installed defProcPoisonGas object holds the script until its burst is over.
		runtime.opening_overlay.clear_message()
		_blocking_motion = false
		wait_remaining = BattlePoisonGasPresentation.play(self, event)
		return
	if not story_mode and event.has("drop_lightning"):
		# The installed defProcDropLightn object holds the script until its hold is over.
		runtime.opening_overlay.clear_message()
		_blocking_motion = false
		wait_remaining = BattleDropLightningPresentation.play(self, event)
		return
	if not story_mode and event.get("kind") == "actor_action_wait":
		# Older compiled timelines classified this token as a rule-only record.
		# Its VM wait is a presentation barrier, not a second logical mutation.
		event = event.duplicate(true)
		event["cutscene_skip"] = false
	super._apply_event(event)

func start_cutscene(status_key: String, events: Array) -> Dictionary:
	if runtime != null and not runtime.play_loop.is_empty():
		events = BattleDropLightningPresentation.attach(runtime.play_loop, events, runtime.script_cutscene_consumed - 1)
	return super.start_cutscene(status_key, events)

func _wait_bound_actor(event: Dictionary) -> void:
	if story_mode:
		super._wait_bound_actor(event)
		return
	var bound: Array = story_objects._bound_actor(event, 0)
	_wait_actor_id = str(bound[0])
	if cutscene_mode:
		var args: Array = event.get("args", []).map(func(value): return str(value))
		var matches: Array = []
		for request in runtime.play_loop.get(LoopKeys.WINFAIL_RUNTIME, {}).get("wait_requests", []):
			if request.get("kind") == "wait_player" and request.get("firing_index") == runtime.script_cutscene_consumed - 1 and request.get("args", []).map(func(value): return str(value)) == args: matches.append(request)
		var ordinal := 0
		for prior in runtime.scene_timeline.events:
			if prior.get("id") == event.get("id"): break
			if prior.get("kind") == "actor_action_wait" and prior.get("args", []).map(func(value): return str(value)) == args: ordinal += 1
		_wait_actor_id = ""
		if ordinal < matches.size():
			var request: Dictionary = matches[ordinal]
			if not request["unit_ids"].is_empty(): _wait_actor_id = str(request["unit_ids"][0])
			elif int(request["insert_index"]) >= 0: _wait_actor_id = str(runtime.play_loop[LoopKeys.WINFAIL_RUNTIME]["inserts"][request["insert_index"]].get("unit_id", ""))
	wait_remaining = 0.0
	_blocking_motion = false
	story_records.append({"kind": "actor_action_wait", "source_event_id": str(event.get("id", "")),
		"unit_id": _wait_actor_id, "was_moving": _target_busy(), "scope": "specified_battle_object"})

func _enter_storage_window(event: Dictionary) -> void:
	if story_mode:
		super._enter_storage_window(event)
		return
	var screen: Node = runtime.party_equipment_screen
	if screen == null:
		story_records.append({"kind": "storage_window_enter", "source_event_id": str(event.get("id", "")), "status": "recorded_no_handler"})
		return
	var result: Dictionary = runtime.menus.open_battle_party_equipment()
	if not bool(result.get("ok", false)):
		screen.close()
		story_records.append({"kind": "storage_window_enter", "source_event_id": str(event.get("id", "")), "status": "skipped_" + str(result.get("error", "unopened"))})
		return
	_storage_window_event_id = str(event.get("id", ""))
	screen.closed.connect(_on_storage_window_closed, CONNECT_ONE_SHOT)
	story_records.append({"kind": "storage_window_enter", "source_event_id": _storage_window_event_id, "status": "opened", "scope": "battle_play_loop"})


func _on_storage_window_closed(next_carry: Dictionary, changes: int) -> void:
	if not story_mode and cutscene_mode and changes > 0:
		var projection: Dictionary = runtime.menus.apply_battle_party_equipment(next_carry)
		if not bool(projection.get("ok", false)):
			var failed: Dictionary = runtime.play_loop.duplicate(true)
			failed.merge({"scenario_ok": false, LoopKeys.INTERACTION: Interaction.SCENARIO_ERROR, "scenario_error": str(projection.get("error", "storage_projection_failed"))}, true)
			runtime.apply_loop(failed, "storage_projection_failed")
			story_records.append({"kind": "storage_window_enter", "source_event_id": _storage_window_event_id, "status": "projection_failed", "error": str(projection.get("error", "storage_projection_failed"))})
		else:
			story_records.append({"kind": "storage_window_enter", "source_event_id": _storage_window_event_id, "status": "projected_to_play_loop", "changes": changes})
	super._on_storage_window_closed(next_carry, changes)


func _target_busy() -> bool:
	var actor: Node = runtime.actor_node_for_unit(_wait_actor_id)
	if actor == null: return false
	var departure = runtime.get_node_or_null("DepartureView")
	return actor.is_moving() or (departure != null and departure.actor_busy(_wait_actor_id))

func tick(delta: float) -> void:
	if active and not story_mode and not _cutscene_finishing and runtime.scene_timeline.current_event().get("kind") == "actor_action_wait":
		_settle_pending_deletes()
		if not _target_busy(): advance("specified_actor_idle")
		return
	super.tick(delta)

func advance(trigger: String = "confirm") -> Dictionary:
	if active and not story_mode and runtime.scene_timeline.current_event().get("kind") == "actor_action_wait" and _target_busy(): return summary()
	return super.advance(trigger)

func speaking_binding(token: String, serial: int) -> Dictionary:
	# A script cutscene speaks through its own chain: the receipt numbers each token's live
	# units 1..n at this row (an empty TOKEN/1 when none is), the 0x44fad0 count.
	var row: Dictionary = {} if runtime == null or not cutscene_mode or story_mode else runtime.scene_timeline.current_event().get("script_actor_receipt", {})
	if not row.get("bindings", {}).has("%s/1" % token): return super.speaking_binding(token, serial)
	var live: Array = []
	var number := 1
	while row["bindings"].has("%s/%d" % [token, number]):
		var binding: Dictionary = row["bindings"]["%s/%d" % [token, number]]
		if str(binding.get("unit_id", "")) != "": live.append(binding)
		number += 1
	if live.is_empty(): return {}
	return live[serial - 1] if serial >= 1 and serial <= live.size() else live.back()

func binding_for_token(actor_token: String, instance: String) -> Dictionary:
	var base := super.binding_for_token(actor_token, instance)
	if runtime == null or not cutscene_mode or story_mode: return base
	var row: Dictionary = runtime.scene_timeline.current_event().get("script_actor_receipt", {})
	var key := "%s/%s" % [actor_token, instance]
	if row.get("bindings", {}).has(key): return row["bindings"][key]
	return runtime.ScriptPresentation.departure_binding(runtime.play_loop, cutscene_key,
		runtime.script_cutscene_consumed - 1, runtime.scene_timeline.current_event(),
		runtime.ScriptPresentation.timeline(runtime, cutscene_key).get("events", []), base)

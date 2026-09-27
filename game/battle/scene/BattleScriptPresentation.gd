extends RefCounted
## Presentation cursor only. Effects and presence are already committed by the
## PlayLoop; retained sprites cannot become another map or queue truth.
## provenance:
##   layout: remake-invented (retained sprites stay at the last cell)
const BattlePoisonGasPresentation = preload("res://game/battle/scene/BattlePoisonGasPresentation.gd")

static func timeline(runtime: Node, key: String) -> Dictionary:
	return runtime.first_battle_scenario.get("scenario_rules", {}).get("status_timelines", {}).get(key, {})

static func pending(runtime: Node) -> bool:
	var fired: Array = runtime.play_loop.get("winfail_runtime", {}).get("fired", [])
	for index in range(runtime.script_cutscene_consumed, fired.size()):
		if int(timeline(runtime, str(fired[index].get("key", ""))).get("playable_event_count", 0)) > 0: return true
		if BattlePoisonGasPresentation.has_gas(runtime.play_loop, index): return true
	return false

static func active(runtime: Node) -> bool:
	return runtime.opening_coordinator != null and runtime.opening_coordinator.active

static func departure_binding(loop: Dictionary, key: String, index: int, event: Dictionary, events: Array, base: Dictionary) -> Dictionary:
	var fired: Array = loop.get("winfail_runtime", {}).get("fired", [])
	var name := str(event.get("source_token", ""))
	if index < 0 or index >= fired.size() or fired[index].get("key") != key or name not in ["actDeleteObject", "actWalkAndDelete", "actWalkAndDeleteWait"]:
		return base
	var args: Array = event.get("args", []).map(func(value): return str(value))
	var matching: Array = []
	for request in loop.get("winfail_runtime", {}).get("departure_requests", []):
		if int(request["firing_index"]) == index and request["key"] == key and request["name"] == name and request.get("args", []).map(func(value): return str(value)) == args:
			matching.append(request)
	var ordinal := 0
	for prior in events:
		if prior.get("id") == event.get("id"): break
		if prior.get("source_token") == name and prior.get("args", []).map(func(value): return str(value)) == args: ordinal += 1
	var binding := base.duplicate(true)
	# An executed script with no corresponding departure request must not hide a
	# static opening actor. Manually injected presentation-only timelines continue
	# through the parent adapter because they have no matching fired occurrence.
	binding["unit_id"] = ""
	if ordinal < matching.size() and matching[ordinal]["unit_ids"].size() == 1:
		binding["unit_id"] = matching[ordinal]["unit_ids"][0]
	return binding

static func prerequisites_busy(runtime: Node) -> bool:
	var view = runtime.get_node("BattlePresentation")
	# The successor's repeat cue belongs after this script. Waiting for that cue
	# here would either show control prematurely or deadlock a deferred notice.
	return view.has_pending_combat(runtime.play_loop) or view.cutin.busy() or view.magic_impact.busy() or view.aftermath.busy() or view.navigation_cue.busy() or view.item_feedback_busy() or view.turn_end_cue.busy(runtime.play_loop)

static func defer_extra_action(runtime: Node) -> void:
	var extra: Dictionary = runtime.play_loop.get("extra_action", {})
	var cue = runtime.get_node("BattlePresentation").extra_action_cue
	if extra.get("pending", false):
		cue.shown_sequence = mini(cue.shown_sequence, int(extra["sequence"]) - 1)
		cue.remaining = 0.0
	cue.label.hide()

static func retain_actor(runtime: Node, unit: Dictionary) -> bool:
	if not unit.get("departed", false): return true
	var record: Dictionary = unit.get("departure", {})
	if record.get("source") != "winfail": return false
	for request in runtime.play_loop.get("winfail_runtime", {}).get("departure_requests", []):
		if request.get("key") != record.get("status_key") or not request["unit_ids"].has(unit["id"]): continue
		var index := int(request["firing_index"])
		if index >= runtime.script_cutscene_consumed:
			return int(timeline(runtime, request["key"]).get("playable_event_count", 0)) > 0
		return index + 1 == runtime.script_cutscene_consumed and active(runtime) and runtime.opening_coordinator.cutscene_mode and runtime.opening_coordinator.cutscene_key == request["key"]
	return false

static func reserve_dialogue(runtime: Node) -> void:
	# Reserve pages before waiting for an earlier attack/item/loot, so generic
	# dialogue cannot pre-empt the script's own walks and camera cues.
	var fired: Array = runtime.play_loop.get("winfail_runtime", {}).get("fired", [])
	for index in range(runtime.script_cutscene_consumed, fired.size()):
		var key := str(fired[index].get("key", ""))
		var program := timeline(runtime, key)
		if int(program.get("playable_event_count", 0)) > 0:
			runtime.mark_cutscene_messages_shown(key, program.get("events", []))

static func hold_controls(runtime: Node) -> void:
	if not pending(runtime) and not active(runtime): return
	var view = runtime.get_node("BattlePresentation")
	runtime.action_menu.hide()
	view.battle_finished = false
	view.selection_cursor.hide()
	view.movement_preview.hide()
	view.target_vitals.hide()
	view.extra_action_cue.label.hide()

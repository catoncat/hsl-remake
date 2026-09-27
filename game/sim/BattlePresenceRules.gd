extends RefCounted
## Retained actor history is distinct from an actor still participating in battle.
## Original cleanup:0x4542a7 (map -> queue -> actor registration -> object unlink).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_departure.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Queue = preload("res://game/sim/CoreTurnQueue.gd")
const POLICY := "script_departure_v1"


static func living(actor: Dictionary) -> bool:
	var hp: Variant = actor.get("hp")
	return typeof(hp) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(hp)) and hp > 0 and hp == int(hp) and not bool(actor.get("defeated", false)) and not bool(actor.get("departed", false))


static func prepare(loop: Dictionary, ids: Array, source: String, status_key: String = "") -> Dictionary:
	# Every departure is a winfail script request naming its status (the hand-written
	# first-battle messenger stage is gone).
	if source != "winfail" or status_key == "":
		return {"ok": false, "reason": "invalid_departure_source"}
	var unique := {}
	for id in ids:
		if not id is String or id == "" or unique.has(id): return {"ok": false, "reason": "invalid_departure_identity"}
		unique[id] = true
	var sequence := int(loop.get("departure_sequence", 0)) + 1
	var proposals: Array = []
	var removed: Array = []
	var survivors: Array = []
	for actor in loop["units"]:
		if not living(actor): continue
		if not unique.has(actor["id"]):
			survivors.append({"id": actor["id"], "live_speed": actor["live_speed"], "action_ready": true})
			continue
		removed.append(actor["id"])
		proposals.append({"id": actor["id"], "changes": {"departed": true, "action_ready": false,
			"ai_call_target_id": "", "ai_target_id": "", "departure": {"sequence": sequence, "source": source, "status_key": status_key}}})
	if removed.is_empty(): return {"ok": true, "changed": false}
	var old_current := str(Queue.current(loop["turn_queue"]).get("id", ""))
	var queue := Queue.remove_actors(loop["turn_queue"], removed, survivors)
	if not queue["ok"]: return queue
	return {"ok": true, "changed": true, "units": proposals, "queue": queue["queue"],
		"receipt": {"sequence": sequence, "unit_ids": removed, "source": source, "status_key": status_key,
			"current_before": old_current, "current_after": Queue.current(queue["queue"]).get("id", ""),
			"round_before": loop["turn_queue"]["round"], "round_after": queue["queue"]["round"]}}


static func state_error(loop: Dictionary) -> String:
	if loop.get("departure_policy") != POLICY or not loop.get("departure_sequence") is int or loop["departure_sequence"] < 0:
		return "invalid_departure_policy"
	var last: Variant = loop.get("last_departure")
	if not last is Dictionary: return "missing_departure_receipt"
	if (loop["departure_sequence"] == 0) != last.is_empty(): return "invalid_departure_sequence"
	if not last.is_empty() and (last.get("sequence") != loop["departure_sequence"] or not last.get("unit_ids") is Array): return "invalid_departure_receipt"
	var departed := {}
	for actor in loop["units"]:
		if not actor.get("departed", false) is bool: return "invalid_departed_flag"
		var record: Variant = actor.get("departure", {})
		if not record is Dictionary: return "invalid_departed_record"
		if not actor.get("departed", false):
			if not record.is_empty(): return "orphan_departure_record"
			continue
		if actor.get("defeated") or int(actor["hp"]) <= 0 or actor.get("action_ready", true) or actor.get("ai_call_target_id", "") != "" or actor.get("ai_target_id", "") != "": return "invalid_departed_actor"
		if not record.get("sequence") is int or record["sequence"] < 1 or record["sequence"] > loop["departure_sequence"] or record.get("source") != "winfail" or not record.get("status_key") is String:
			return "invalid_departed_record"
		departed[actor["id"]] = record
	for slot in loop["turn_queue"]["slots"]:
		if departed.has(slot.get("id")): return "departed_actor_in_queue"
	if departed.has(loop.get("selected_unit_id")) or departed.has(loop.get("extra_action", {}).get("owner_id")):
		return "departed_actor_still_current"
	for actor in loop["units"]:
		if departed.has(actor.get("ai_target_id")) or departed.has(actor.get("ai_call_target_id")): return "departed_actor_still_targeted"
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	var fired: Array = runtime.get("fired", [])
	for request in runtime.get("departure_requests", []):
		if not request is Dictionary or not request.get("unit_ids") is Array or not request.get("firing_index") is int:
			return "invalid_departure_firing"
		var index: int = request["firing_index"]
		if index < 0 or index >= fired.size() or fired[index].get("key") != request.get("key"): return "invalid_departure_firing"
	var ledger: Variant = runtime.get("departed_unit_ids", [])
	if not ledger is Array: return "invalid_departure_ledger"
	var seen := {}
	for id in ledger:
		if not id is String or seen.has(id): return "invalid_departure_ledger"
		seen[id] = true
		if not departed.has(id) or departed[id]["source"] != "winfail": return "unsettled_departure_request"
	for id in departed:
		if departed[id]["source"] == "winfail" and not seen.has(id): return "unrecorded_script_departure"
	if not last.is_empty():
		for id in last["unit_ids"]:
			if not departed.has(id) or departed[id]["sequence"] != last["sequence"] or departed[id]["source"] != last.get("source") or departed[id]["status_key"] != last.get("status_key"): return "invalid_departure_receipt"
	return ""

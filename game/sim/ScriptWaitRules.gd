extends RefCounted
## Source wait assignments are distinct from AI countdown and object animation.
## This module proposes changes; the sole PlayLoop commits them. No RNG or ticks.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_wait.md
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const POLICY := "script_wait_v1"
const MAX_WAIT := 10000

static func valid_count(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == int(value) and value >= 0 and value <= MAX_WAIT

static func select(candidates: Array, serial: int) -> Array:
	return [] if candidates.is_empty() else [candidates[clampi(serial - 1, 0, candidates.size() - 1)]]

static func initial_source(scenario: Dictionary, units: Array, events: Array) -> Dictionary:
	var bindings: Dictionary = scenario.get("opening", {}).get("actor_bindings", {})
	var initial: Array = []
	var previous := ""
	# Insert bindings are numbered per header symbol ("<symbol>/insertN"), the scenario
	# generator's and BattleOpeningCoordinator's numbering: STORY006 inserts three
	# Enemy23 and then one Enemy24, so the count must not mix symbols.
	var insert_counts := {}
	for event in events:
		var kind := str(event.get("kind", ""))
		var args: Array = event.get("args", [])
		if kind == "first_control_marker": break
		if kind == "object_insert":
			var symbol := str(args[0]) if not args.is_empty() else ""
			insert_counts[symbol] = int(insert_counts.get(symbol, 0)) + 1
			previous = str(bindings.get("%s/insert%d" % [symbol, int(insert_counts[symbol])], {}).get("unit_id", ""))
			continue
		if kind not in ["inserted_object_wait_round", "actor_wait_round"]: continue
		var required := 1 if kind == "inserted_object_wait_round" else 3
		if args.size() < required or not str(args[required - 1]).is_valid_int() or not valid_count(int(str(args[required - 1]))):
			return {"ok": false, "reason": "invalid_initial_script_wait"}
		var ids: Array = []
		if kind == "inserted_object_wait_round":
			ids = [previous]
		else:
			var token := str(args[0])
			if not str(args[1]).is_valid_int(): return {"ok": false, "reason": "invalid_initial_wait_serial"}
			for actor in units:
				var matched: bool = token == "SID_ENEMY" + str(actor["actor_id"])
				for key in bindings:
					matched = matched or (str(key).begins_with(token + "/") and bindings[key].get("unit_id") == actor["id"])
				if matched and Presence.living(actor): ids.append(actor["id"])
			ids = select(ids, int(str(args[1])))
		for id in ids:
			# Story-only cast entries are not silently promoted into combat actors.
			if not units.any(func(actor): return actor["id"] == id and Presence.living(actor)): continue
			initial.append({"unit_id": id, "rounds": int(str(args[required - 1])), "source_event_id": str(event["id"])})
	return {"ok": true, "source": {"policy": POLICY, "initial": initial, "previous_insert_unit_id": previous}}

static func request_error(request: Variant, runtime: Dictionary) -> String:
	if not request is Dictionary or request.get("kind") not in ["wait_round", "wait_player"] or not request.get("unit_ids") is Array or request["unit_ids"].size() > 1:
		return "invalid_script_wait_request"
	if not request.get("firing_index") is int or not request.get("insert_index") is int or not request.get("args") is Array:
		return "invalid_script_wait_binding"
	var index: int = request["firing_index"]
	var fired: Array = runtime.get("fired", [])
	if index < 0 or index >= fired.size() or fired[index].get("key") != request.get("key"): return "invalid_script_wait_firing"
	var insert: int = request["insert_index"]
	if insert < -1 or insert >= runtime.get("inserts", []).size() or (insert >= 0 and not request["unit_ids"].is_empty()): return "invalid_script_wait_insert"
	for id in request["unit_ids"]:
		if not id is String or id == "": return "invalid_script_wait_identity"
	if request["kind"] == "wait_round" and not valid_count(request.get("rounds")): return "invalid_script_wait_rounds"
	return ""

static func prepare(loop: Dictionary) -> Dictionary:
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	var requests: Variant = runtime.get("wait_requests", [])
	var cursor: Variant = loop.get("script_wait_cursor")
	if not requests is Array or not cursor is int or cursor < 0 or cursor > requests.size(): return {"ok": false, "reason": "invalid_script_wait_cursor"}
	var current := {}
	var rows: Array = []
	for index in range(cursor, requests.size()):
		var error := request_error(requests[index], runtime)
		if error != "": return {"ok": false, "reason": error}
		var request: Dictionary = requests[index]
		var row := {"request_index": index, "kind": request["kind"], "changes": []}
		if request["kind"] == "wait_round":
			for id in request["unit_ids"]:
				for actor in loop["units"]:
					if actor["id"] != id or not Presence.living(actor): continue
					var before := int(current.get(id, actor["ai_wait_remaining"]))
					current[id] = int(request["rounds"])
					row["changes"].append({"unit_id": id, "before": before, "after": current[id]})
		rows.append(row)
	return {"ok": true, "values": current, "cursor": requests.size(),
		"receipt": {"from": cursor, "to": requests.size(), "rows": rows} if not rows.is_empty() else loop.get("last_script_wait", {}).duplicate(true)}

static func next_insert(loop: Dictionary, class_id: String) -> int:
	var inserts: Array = loop.get("winfail_runtime", {}).get("inserts", [])
	for index in range(inserts.size()):
		if inserts[index].get("class_id") == class_id and str(inserts[index].get("unit_id", "")) == "": return index
	return -1

static func state_error(loop: Dictionary) -> String:
	var source: Variant = loop.get("script_wait_source")
	if not source is Dictionary or source.get("policy") != POLICY or not source.get("initial") is Array: return "invalid_script_wait_source"
	for row in source["initial"]:
		if not row is Dictionary or not row.get("unit_id") is String or not valid_count(row.get("rounds")) or not row.get("source_event_id") is String: return "invalid_initial_script_wait"
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	var requests: Variant = runtime.get("wait_requests", [])
	if not requests is Array or not loop.get("script_wait_cursor") is int or loop["script_wait_cursor"] != requests.size(): return "unsettled_script_wait_requests"
	for request in requests:
		var error := request_error(request, runtime)
		if error != "": return error
	var receipt: Variant = loop.get("last_script_wait")
	if not receipt is Dictionary: return "missing_script_wait_receipt"
	var insert_error := _insert_error(loop)
	if insert_error != "": return insert_error
	if requests.is_empty(): return "" if receipt.is_empty() else "orphan_script_wait_receipt"
	if not receipt.get("from") is int or receipt["from"] < 0 or receipt.get("to") != requests.size() or not receipt.get("rows") is Array or receipt["rows"].size() != receipt["to"] - receipt["from"]:
		return "invalid_script_wait_receipt"
	for offset in range(receipt["rows"].size()):
		var row: Variant = receipt["rows"][offset]
		var index: int = receipt["from"] + offset
		if not row is Dictionary or row.get("request_index") != index or row.get("kind") != requests[index]["kind"] or not row.get("changes") is Array: return "invalid_script_wait_receipt"
		var seen := {}
		for change in row["changes"]:
			if not change is Dictionary or requests[index]["kind"] != "wait_round" or not requests[index]["unit_ids"].has(change.get("unit_id")) or seen.has(change.get("unit_id")) or not valid_count(change.get("before")) or change.get("after") != int(requests[index]["rounds"]): return "invalid_script_wait_receipt"
			seen[change["unit_id"]] = true
	return ""

static func _insert_error(loop: Dictionary) -> String:
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	var assigned := {}
	for insert in runtime.get("inserts", []):
		if insert.get("wait_round_set", false) and not valid_count(insert.get("wait_round")): return "invalid_insert_wait"
		var id := str(insert.get("unit_id", ""))
		if id == "": continue
		if assigned.has(id) or not loop["units"].any(func(actor): return actor["id"] == id and actor.get("class_id") == insert.get("class_id")): return "invalid_insert_wait_identity"
		assigned[id] = true
	return ""

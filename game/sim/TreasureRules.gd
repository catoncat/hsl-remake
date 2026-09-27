extends RefCounted
## Source chest contents and exactly-once action-tail proposals. PlayLoop owns
## the ledger and existing pending reward pool; presentation never awards items.
## Each chest's `hidden` (template obj_Attribute without objattrATTACKFLAG) is carried for
## the presentation only: hidden and shown chests are collected by the same rule.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_treasure.md; resource-derived content/generated/hsl/treasures
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const POLICY := "source_treasure_v1"
const Reward = preload("res://game/sim/BattleRewardRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


static func initialize(data: Dictionary, level: int, catalog: Dictionary, size: Vector2i) -> Dictionary:
	if data.get("schema") != "hsl_battle_treasures.v1" or not data.get("levels", {}).get(str(level)) is Dictionary:
		return {"ok": false, "reason": "missing_treasure_source"}
	var source: Dictionary = data["levels"][str(level)].duplicate(true)
	source["policy"] = POLICY
	if not source.get("chests") is Array: return {"ok": false, "reason": "invalid_treasure_source"}
	for chest in source["chests"]:
		if not chest is Dictionary or not chest.get("coord") is Array or chest["coord"].size() != 2: return {"ok": false, "reason": "invalid_treasure_coord"}
		for value in chest["coord"]:
			if not Reward.integer(value): return {"ok": false, "reason": "invalid_treasure_coord"}
		chest["coord"] = Vector2i(int(chest["coord"][0]), int(chest["coord"][1]))
		if chest.get("items") is Array: chest["items"] = chest["items"].map(func(code): return int(code) if Reward.integer(code, 1) else code)
	var error := source_error(source, catalog, size)
	if error != "": return {"ok": false, "reason": error}
	return {"ok": true, "source": source, "state": {"policy": POLICY, "opened_ids": [], "receipts": [], "handoff": {}}}


static func source_error(source: Variant, catalog: Dictionary, size: Vector2i) -> String:
	if not source is Dictionary or source.get("policy") != POLICY or not Reward.integer(source.get("level"), 1) or not source.get("chests") is Array or source["chests"].size() > 128:
		return "invalid_treasure_source"
	for key in ["level_sha256", "obs_sha256"]:
		if not source.get(key) is String or source[key].length() != 64: return "invalid_treasure_provenance"
	var ids := {}
	for chest in source["chests"]:
		if not chest is Dictionary or not Reward.integer(chest.get("record_index")) or chest.get("id") != "%d:%d" % [source["level"], chest["record_index"]] or ids.has(chest["id"]): return "invalid_treasure_identity"
		if not chest.get("coord") is Vector2i or chest["coord"].x < 0 or chest["coord"].y < 0 or chest["coord"].x >= size.x or chest["coord"].y >= size.y: return "invalid_treasure_coord"
		if not chest.get("items") is Array or chest["items"].size() > 8 or not chest.get("shape_resource_id") is String: return "invalid_treasure_contents"
		if not chest.get("hidden") is bool: return "invalid_treasure_visibility"
		for code in chest["items"]:
			if not Reward.integer(code, 1) or not catalog.has(str(int(code))): return "unknown_treasure_item"
		ids[chest["id"]] = true
	return ""


static func chest_at(loop: Dictionary, coord: Vector2i) -> Dictionary:
	for chest in loop.get("treasure_source", {}).get("chests", []):
		if chest["coord"] == coord and not loop.get("treasures", {}).get("opened_ids", []).has(chest["id"]): return chest
	return {}


static func entries(chests: Array) -> Array:
	var result: Array = []
	for chest in chests:
		for index in range(chest["items"].size()):
			result.append({"id": "treasure:%s:%d" % [chest["id"], index], "code": int(chest["items"][index]),
				"source_id": "treasure:" + chest["id"], "source_slot": index})
	return result


static func prepare(loop: Dictionary, actor: Dictionary) -> Dictionary:
	var error := state_error(loop)
	if error != "": return {"ok": false, "reason": error}
	if not loop.has("treasure_source") or not Presence.living(actor) or not actor.get("player_commandable", false) or actor.get("source_object_kind", 3) != 3 or Status.paralyzed(actor): return {"ok": true}
	if BattleOutcome.decided(loop) or not loop.get("scenario_ok", false) or awaiting_handoff(loop) or not loop.get("settlement", {}).get("closed", true): return {"ok": true}
	var chests: Array = loop["treasure_source"]["chests"].filter(func(chest): return chest["coord"] == actor["coord"] and not loop["treasures"]["opened_ids"].has(chest["id"]))
	if chests.is_empty(): return {"ok": true}
	var state: Dictionary = loop["treasures"].duplicate(true)
	var found := entries(chests)
	var sequence: int = state["receipts"].size() + 1
	var settled := Reward.settle(loop["settlement"], "treasure", int(loop.get("last_combat", {}).get("sequence", 0)), int(loop["gold"]), 0, found, [], actor["id"], str(sequence))
	var ids: Array = chests.map(func(chest): return chest["id"])
	state["opened_ids"].append_array(ids)
	state["receipts"].append({"sequence": sequence, "reward_sequence": settled["sequence"], "actor_id": actor["id"],
		"source_actor_id": actor["actor_id"], "coord": actor["coord"], "chest_ids": ids, "items": found,
		"turn": int(loop["turn"]), "rng_consumed": 0})
	state["handoff"] = {"actor_id": actor["id"], "receipt_sequence": sequence, "queue_round": loop["turn_queue"]["round"],
		"queue_index": loop["turn_queue"]["index"], "extra_action": loop["extra_action"].duplicate(true), "action_end_sequence": loop["action_end_sequence"]}
	return {"ok": true, "state": state, "settlement": settled}


static func awaiting_handoff(loop: Dictionary) -> bool:
	return not loop.get("treasures", {}).get("handoff", {}).is_empty()


static func state_error(loop: Dictionary) -> String:
	if not loop.has("treasure_source"):
		return "unexpected_treasure_state" if loop.has("treasures") else ""
	var error := source_error(loop["treasure_source"], loop["equipment_items"], loop["map_size"])
	if error != "": return error
	var state: Variant = loop.get("treasures")
	if not state is Dictionary or state.get("policy") != POLICY or not state.get("opened_ids") is Array or not state.get("receipts") is Array or not state.get("handoff") is Dictionary: return "invalid_treasure_state"
	var source := {}
	for chest in loop["treasure_source"]["chests"]: source[chest["id"]] = chest
	var opened: Array = []
	var previous_reward := 0
	for index in range(state["receipts"].size()):
		var record: Variant = state["receipts"][index]
		if not record is Dictionary or record.get("sequence") != index + 1 or not Reward.integer(record.get("reward_sequence"), previous_reward + 1) or not record.get("chest_ids") is Array or record["chest_ids"].is_empty() or not record.get("coord") is Vector2i or record.get("rng_consumed") != 0 or not Reward.integer(record.get("turn"), 1): return "invalid_treasure_receipt"
		var actor := _actor(loop, str(record.get("actor_id", "")))
		if actor.is_empty() or record.get("source_actor_id") != actor.get("actor_id"): return "invalid_treasure_actor"
		var boxes: Array = []
		for id in record["chest_ids"]:
			if not id is String or not source.has(id) or opened.has(id) or source[id]["coord"] != record["coord"]: return "duplicate_or_mismatched_treasure"
			opened.append(id); boxes.append(source[id])
		if record.get("items") != entries(boxes): return "inconsistent_treasure_contents"
		previous_reward = int(record["reward_sequence"])
	if state["opened_ids"] != opened: return "treasure_opened_rollback"
	if awaiting_handoff(loop):
		var handoff: Dictionary = state["handoff"]
		var queue: Dictionary = loop["turn_queue"]
		var slots: Variant = queue.get("slots")
		if not slots is Array or not Reward.integer(queue.get("index"), 0, slots.size() - 1): return "invalid_treasure_handoff_queue"
		if not slots[int(queue["index"])] is Dictionary: return "invalid_treasure_handoff_queue"
		var owner := _actor(loop, str(handoff.get("actor_id", "")))
		if state["receipts"].is_empty() or handoff.get("receipt_sequence") != state["receipts"].size() or handoff.get("queue_round") != queue["round"] or handoff.get("queue_index") != queue["index"] or queue["slots"][queue["index"]]["id"] != handoff["actor_id"]:
			return "invalid_treasure_handoff"
		if not Presence.living(owner) or owner["coord"] != state["receipts"].back()["coord"] or handoff.get("extra_action") != loop["extra_action"] or handoff.get("action_end_sequence") != loop["action_end_sequence"] or loop.get("interaction") != "ai_resolving" or BattleOutcome.decided(loop) or loop.get("pending_move", true): return "premature_treasure_action_handoff"
	return ""


static func settlement_error(loop: Dictionary) -> String:
	var settled: Dictionary = loop.get("settlement", {})
	if settled.is_empty(): return ""
	if not Reward.integer(settled.get("sequence"), 1): return "invalid_saved_settlement"
	if settled.has("combat_sequence") and not Reward.integer(settled["combat_sequence"]): return "invalid_settlement_combat_sequence"
	var kind := str(settled.get("source_kind", "combat"))
	var combat := int(loop.get("last_combat", {}).get("sequence", 0))
	if Reward.combat_sequence(settled) != combat or int(settled["sequence"]) < combat: return "unbound_saved_settlement"
	match kind:
		"combat":
			if combat == 0: return "unbound_saved_settlement"
		"treasure":
			var records: Array = loop.get("treasures", {}).get("receipts", [])
			if records.is_empty() or str(records.back()["sequence"]) != settled.get("source_id") or records.back()["reward_sequence"] != settled["sequence"] or records.back()["actor_id"] != settled.get("owner_id") or settled.get("gold") != 0 or not settled.get("kills", []).is_empty(): return "unbound_treasure_settlement"
		"campaign":
			if not loop.get("campaign_carry_receipt", {}).has("pending_rewards") or combat != 0 or settled["sequence"] != 1 or settled.get("gold") != 0: return "unbound_carried_settlement"
		_:
			return "unknown_settlement_source"
	return ""


static func _actor(loop: Dictionary, id: String) -> Dictionary:
	for actor in loop["units"]:
		if actor["id"] == id: return actor
	return {}

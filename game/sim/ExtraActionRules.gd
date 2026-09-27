extends RefCounted
## Original action_twice completion gate. The first completed action may repeat
## this actor immediately; the second goes to the shared status/queue tail.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_extra_action.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Number = preload("res://game/sim/SkillResourceRules.gd")


static func empty(sequence: int = 0) -> Dictionary:
	return {"owner_id": "", "pending": false, "sequence": sequence}


static func equipment(actor: Dictionary, catalog: Dictionary) -> Dictionary:
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_extra_action_equipment"}
	var enabled := false
	for slot in actor["equipment"]:
		if not slot is Dictionary or Number._integer(slot.get("item_code")) <= 0: return {"ok": false, "reason": "invalid_extra_action_equipment"}
		var item: Variant = catalog.get(str(int(slot["item_code"])))
		if not item is Dictionary or not item.get("action_twice") is bool: return {"ok": false, "reason": "invalid_extra_action_effect"}
		enabled = enabled or item["action_twice"]
	return {"ok": true, "enabled": enabled, "count": 2 if enabled else 1}


static func state_error(state: Variant, current_id: String, terminal: bool = false) -> String:
	if not state is Dictionary or not state.get("owner_id") is String or not state.get("pending") is bool:
		return "invalid_extra_action_state"
	var sequence := Number._integer(state.get("sequence"))
	if sequence < 0 or sequence > 1000000: return "invalid_extra_action_sequence"
	if state["pending"]:
		if terminal or sequence == 0 or current_id == "" or state["owner_id"] != current_id: return "invalid_extra_action_owner"
	elif state["owner_id"] != "": return "invalid_extra_action_owner"
	return ""


static func complete(state: Dictionary, actor_id: String, enabled: bool) -> Dictionary:
	var repeat: bool = not state["pending"] and enabled
	return {"repeat": repeat, "state": {"owner_id": actor_id, "pending": true, "sequence": int(state["sequence"]) + 1} if repeat else empty(int(state["sequence"]))}

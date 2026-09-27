extends RefCounted
## Immutable final-action proposals. PlayLoop alone commits vitals/RNG/queue.
## Poison precedes HP/MP restoration; duration/kill-chain/queue tail stays final.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_resource_recovery.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_effects.md
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
## v5: the recovery draws come from the loop's damage stream ([word0, word1]); v4 drew them
## from a separate Park-Miller recovery_rng.
const POLICY := "source_resource_tail_v5"
const FIELDS := ["id", "coord", "hp", "max_hp", "mp", "max_mp", "status_flags", "status_counters"]


static func compact(actor: Dictionary) -> Dictionary:
	var result := {}
	for key in FIELDS: result[key] = actor.get(key)
	return result.duplicate(true)


static func prepare(actor: Dictionary, capabilities: Dictionary, random_state: Array, sequence: int) -> Dictionary:
	if not actor.get("id") is String or actor["id"] == "" or not actor.get("coord") is Vector2i:
		return {"ok": false, "reason": "invalid_turn_end_actor"}
	if not BattleRewardRules.integer(sequence, 1): return {"ok": false, "reason": "invalid_turn_end_sequence"}
	var error := ResourceRecoveryRules.health_error(actor)
	if error != "": return {"ok": false, "reason": error}
	var status := StatusEffectRules.after_action(actor)
	if not status["ok"]: return status
	var before := compact(actor)
	var after := before.duplicate(true)
	after.merge(status["changes"], true)
	var result := ResourceRecoveryRules.prepare(after, capabilities, random_state)
	if not result["ok"]: return result
	var events: Array = []
	if status["poison_damage"] > 0:
		events.append({"kind": StatusEffectRules.Catalog.POISON_KEY, "resource": "hp", "amount": -int(status["poison_damage"]), "before": int(before["hp"]), "after": int(after["hp"])})
	events.append_array(result["events"])
	for key in StatusEffectRules.Catalog.keys_where("expiry_event", true):
		if status["expired"].has(key):
			events.append({"kind": key + "_expired", "resource": "status", "amount": 0, "before": int(before["status_counters"][key]), "after": 0})
	for key in StatusEffectRules.Enhancements.FLAGS:
		if status["expired"].has(key):
			events.append({"kind": key + "_expired", "resource": "status", "amount": 0,
				"before": int(before["status_counters"][key]), "after": 0})
	after.merge(result["changes"], true)
	var changes: Dictionary = status["changes"].duplicate(true)
	changes.merge(result["changes"], true)
	return {"ok": true, "changes": changes, "rng": result["state"],
		"receipt": {"sequence": sequence, "actor_id": actor["id"], "coord": actor["coord"],
			"before": before, "after": after, "effects": capabilities.duplicate(true), "events": events,
			"draws": result["draws"], "expired": status["expired"]}}


static func state_error(loop: Dictionary) -> String:
	if loop.get("turn_end_policy") != POLICY: return "invalid_turn_end_policy"
	if not DamageRandomStream.valid(loop.get(DamageRandomStream.LOOP_KEY)): return "invalid_recovery_rng"
	if not BattleRewardRules.integer(loop.get("action_end_sequence")): return "invalid_turn_end_sequence"
	var receipt: Variant = loop.get("last_action_end")
	if not receipt is Dictionary: return "missing_turn_end_receipt"
	if loop["action_end_sequence"] == 0: return "" if receipt.is_empty() else "inconsistent_turn_end_receipt"
	if receipt.get("sequence") != loop["action_end_sequence"] or not receipt.get("before") is Dictionary or not receipt.get("effects") is Dictionary:
		return "inconsistent_turn_end_receipt"
	return ""

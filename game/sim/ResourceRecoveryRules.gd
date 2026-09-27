extends RefCounted
## Current equipment capabilities and the original resource-recovery arithmetic.
## Sampling draws from the loop's one saved damage stream (DamageRandomStream), as
## 0x40e430／0x406fe0 draw through 0x42c780.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_resource_recovery.md; static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Number = preload("res://game/sim/SkillResourceRules.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const KEYS := ["mp_use_half", "hp_auto_restore", "mp_auto_restore", "hp_transfer_mp"]


static func effect_error(effects: Variant) -> String:
	if not effects is Dictionary: return "missing_resource_effects"
	for key in KEYS:
		if not effects.get(key) is bool: return "invalid_resource_effect_" + key
	return ""


static func effects(actor: Dictionary, catalog: Dictionary) -> Dictionary:
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_recovery_equipment"}
	var result := {"mp_use_half": false, "hp_auto_restore": false, "mp_auto_restore": false, "hp_transfer_mp": false}
	for slot in actor["equipment"]:
		if not slot is Dictionary or Number._integer(slot.get("item_code")) <= 0: return {"ok": false, "reason": "invalid_recovery_equipment"}
		var item: Variant = catalog.get(str(int(slot["item_code"])))
		var error := effect_error(item)
		if error != "": return {"ok": false, "reason": error}
		for key in KEYS: result[key] = result[key] or item[key]
	return {"ok": true, "effects": result}


static func health_error(actor: Dictionary) -> String:
	for key in ["hp", "max_hp", "mp", "max_mp"]:
		var number := Number._integer(actor.get(key))
		if number < 0 or number > 1000000: return "invalid_recovery_" + key
	if actor["max_hp"] <= 0 or actor["hp"] > actor["max_hp"] or actor["mp"] > actor["max_mp"]: return "inconsistent_recovery_vitals"
	return ""


static func amount(resource: String, maximum: int, current: int, roll: int) -> int:
	var result := maximum * (roll + (5 if resource == "hp" else 3)) / 100
	# These are native additions, not max(result, minimum).
	if result < 3: result += 3 if resource == "hp" else 2
	return mini(maximum - current, result)


static func transfer_bounds(max_hp: int) -> Dictionary:
	var low := maxi(1, max_hp * 8 / 100)
	var high := maxi(low + 1, max_hp * 12 / 100)
	var half := (high - low) / 2
	return {"low": low, "half": half, "bound": half + 1}


static func transfer_values(max_hp: int, hp: int, max_mp: int, mp: int, first_roll: int, second_roll: int) -> Dictionary:
	var bounds := transfer_bounds(max_hp)
	var loss := mini(hp - 1, int(bounds["low"]) + int(bounds["half"]) - first_roll + second_roll)
	return {"hp_loss": loss, "mp_gain": mini(max_mp - mp, loss)}


static func prepare(actor: Dictionary, capabilities: Dictionary, random_state: Array) -> Dictionary:
	var error := health_error(actor)
	if error == "": error = effect_error(capabilities)
	if error != "": return {"ok": false, "reason": error}
	if not DamageRandom.valid(random_state): return {"ok": false, "reason": "invalid_recovery_rng"}
	if actor["hp"] <= 0 or actor.get("defeated", false): return {"ok": false, "reason": "recovery_actor_unavailable"}
	var changes := {"hp": int(actor["hp"]), "mp": int(actor["mp"])}
	var events: Array = []
	var draws: Array = []
	for key in ["hp", "mp"]:
		if not capabilities[key + "_auto_restore"] or actor[key] >= actor["max_" + key]: continue
		var draw := DamageRandom.rand(random_state, 6)
		random_state = draw["state"]
		var gain := amount(key, int(actor["max_" + key]), int(actor[key]), int(draw["value"]))
		draws.append({"resource": key, "bound": 6, "value": draw["value"]})
		changes[key] += gain
		if gain > 0: events.append({"kind": "auto_" + key, "resource": key, "amount": gain, "before": int(actor[key]), "after": changes[key]})
	if capabilities["hp_transfer_mp"]:
		# 0x4094c0 follows both auto restores. It still samples at1HP and spends
		# HP when MP is full or the job has no MP. Only actual HP loss transfers.
		var bounds := transfer_bounds(int(actor["max_hp"]))
		var first := DamageRandom.rand(random_state, int(bounds["bound"]))
		var second := DamageRandom.rand(first["state"], int(bounds["bound"]))
		random_state = second["state"]
		for roll in [first, second]: draws.append({"resource": "hp_transfer_mp", "bound": bounds["bound"], "value": roll["value"]})
		var transfer := transfer_values(int(actor["max_hp"]), int(changes["hp"]), int(actor["max_mp"]), int(changes["mp"]), int(first["value"]), int(second["value"]))
		for key in ["hp", "mp"]:
			var delta: int = -int(transfer["hp_loss"]) if key == "hp" else int(transfer["mp_gain"])
			if delta == 0: continue
			var before := int(changes[key])
			changes[key] += delta
			events.append({"kind": "transfer_" + key, "resource": key, "amount": delta, "before": before, "after": changes[key]})
	return {"ok": true, "changes": changes, "events": events, "draws": draws, "state": random_state}

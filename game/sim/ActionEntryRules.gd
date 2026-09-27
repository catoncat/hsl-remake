extends RefCounted
## Original fresh-action paralysis gates (443996 / 43f47b). The caller owns
## entry/queue transitions; this module stores no actor, phase or timer.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_paralysis.md
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const Values = preload("res://game/sim/Values.gd")
## Catalog rows with blocks_action (麻痺) and their flags.
static var BLOCKING_KEYS: Array = StatusEffectRules.Catalog.keys_where("blocks_action", true)
static var BLOCKING_FLAGS: int = StatusEffectRules.Catalog.flag_mask("blocks_action")


static func skips(flags: int, phase: int = 0, enabled: bool = true) -> bool:
	return enabled and phase == 0 and (flags & BLOCKING_FLAGS) != 0


static func prepare(actor: Dictionary) -> Dictionary:
	var error := StatusEffectRules.input_error(actor)
	if error != "": return {"ok": false, "reason": error}
	if not Values.is_integer_in(actor.get("hp"), 0, Values.MAX_UNSIGNED) or actor["hp"] == 0 or actor.get("defeated", false) or actor.get("departed", false):
		return {"ok": false, "reason": "entry_actor_unavailable"}
	var remaining := 0
	for key in BLOCKING_KEYS: remaining = maxi(remaining, int(actor["status_counters"].get(key, 0)))
	return {"ok": true, "skip": skips(int(actor["status_flags"])), "remaining": remaining}

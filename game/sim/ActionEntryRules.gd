extends RefCounted
## Original fresh-action paralysis gates (443996 / 43f47b). The caller owns
## entry/queue transitions; this module stores no actor, phase or timer.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_paralysis.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Status = preload("res://game/sim/StatusEffectRules.gd")


static func skips(flags: int, phase: int = 0, enabled: bool = true) -> bool:
	return enabled and phase == 0 and (flags & Status.PARALYSIS) != 0


static func prepare(actor: Dictionary) -> Dictionary:
	var error := Status.input_error(actor)
	if error != "": return {"ok": false, "reason": error}
	if not Status._unsigned(actor.get("hp")) or actor["hp"] == 0 or actor.get("defeated", false) or actor.get("departed", false):
		return {"ok": false, "reason": "entry_actor_unavailable"}
	return {"ok": true, "skip": skips(int(actor["status_flags"])),
		"remaining": int(actor["status_counters"]["paralysis"])}

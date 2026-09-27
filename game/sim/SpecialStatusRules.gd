extends RefCounted
## Special channel1 status abilities: 弱體箭 / 獸神怒號 (Attack+Weaken) and 影纏 (Paralysis).
## 0x40aa80 visits exactly the channel0 status branches; only the numeric helper
## differs (0x40a7b0 channel1: hit_ratio + compensation, level/dex/con/mind terms,
## attackpow_ratio, elemental resistance, none for magicOTHER). Pure proposals:
## payment, per-target EXP and the single PlayLoop commit stay shared.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md; static-derived docs/evidence_packets/static_reverse/original_poison_arrow.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Special = preload("res://game/sim/SpecialDamageRules.gd")
const StatusApplication = preload("res://game/sim/StatusApplicationRules.gd")
const PoisonArrow = preload("res://game/sim/PoisonArrowRules.gd")


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary) -> Dictionary:
	var status := StatusApplication.prepare(caster, target, fields, book, targeting, equipment, "special")
	if not status["ok"]: return status
	var special := Special.prepare(caster, target, fields, book, equipment)
	if not special["ok"]: return special
	# Channel1 helper terms (attackpow_ratio, dex, con, level) join the shared status input.
	status["roll_input"].merge(special["input"], true)
	status["roll_input"]["proc"] = 0
	return status


## Channel1 roll: proc0 = special damage helper with resistance, proc6 = status check
## on hit_ratio + compensation (PoisonArrowRules.roll models both 0x40a7b0 paths).
static func resolve(prepared: Dictionary, target: Dictionary, rng: Variant, equipment: Dictionary) -> Dictionary:
	return StatusApplication.resolve(prepared, target, rng, Callable(PoisonArrow, "roll"), equipment)
